#!/usr/bin/env python3
"""Usage: unexecuted-lines.py [--summary FILE] --commit SHA linux=DIRECTORY macos=DIRECTORY
       unexecuted-lines.py --self-test DIRECTORY

Run from the root of a checkout of commit SHA. Each DIRECTORY holds one platform's test run: `coverage.lcov`, its
`llvm-cov export -format=lcov`; `checkout-root.txt`, the absolute path of the checkout that run built, which the
report's `SF:` paths start with; and `commit.txt`, the commit that run built.

Prints `path:line: source` for every line under Sources/ or Plugins/ that a report records and no report records as
executed, and a total, and exits 1 when there is any. A line counts as executed when either platform executed it in
any file that resolves to it: the macro plugin and some test targets compile files through symbolic links
(Sources/SafeDIMacros/SafeDICore, Tests/SafeDIGeneratorPluginTests/PluginScannerStringUtilities.swift), so each
recorded path is resolved with os.path.realpath in this checkout and the copies are one file. A line counts only when
a report has a `DA` record for it, as in Codecov. llvm-cov gives one to every line inside a function body, comment
lines included, and none to declarations outside one. Codecov counts those comment lines, and so does this script,
so a comment that is the only line of a branch no test takes is reported. Lines whose only text is `}` or `{`, or
nothing, are skipped: Codecov drops those from its counts (checked against its report of main on 2026-11-14), and
llvm-cov gives a zero to the closing brace after a `return`, which no test can execute. Under GitHub Actions each line
also gets an error annotation; --summary FILE appends a Markdown table of them to FILE.

Exits 2 when the reports cannot be trusted, so the check never passes on missing or partial data:
- the platforms given are not exactly linux and macos, each once;
- a report, its root or its commit is missing, or the commit is not SHA;
- a report does not end with `end_of_record` (the export was cut short), or has a malformed record;
- a report records no line under Sources/ or Plugins/ of its root;
- a report names a file under Sources/ or Plugins/ that this checkout lacks, or a line past the end of one;
- a Swift file under Sources/ or Plugins/ is recorded by neither report and not listed in Scripts/unmeasured-files.txt;
- a file that list names is recorded by a report, or is not a Swift file under Sources/ or Plugins/ once symbolic
  links resolve.

--self-test DIRECTORY writes a fixture checkout and fixture reports into DIRECTORY, which must not exist, and checks
the union, the symbolic links, the annotations and each refusal above. Exit 0 when every expectation holds.
"""
import collections
import contextlib
import io
import os
import sys

MEASURED_DIRECTORIES = ("Sources", "Plugins")
MEASURED_PREFIXES = tuple(directory + "/" for directory in MEASURED_DIRECTORIES)
REQUIRED_PLATFORMS = ("linux", "macos")
UNMEASURED_FILES_LIST = "Scripts/unmeasured-files.txt"
# Lines Codecov leaves out of its counts.
UNCOUNTED_TEXT = ("", "{", "}")


class UntrustworthyReport(Exception):
    pass


def lines_of(path):
    """The lines of the file at `path`, without the empty string after a final newline."""
    with open(path, encoding="utf-8") as source_file:
        lines = source_file.read().split("\n")
    if lines[-1] == "":
        lines.pop()
    return lines


def escape_annotation_data(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_annotation_property(text):
    return escape_annotation_data(text).replace(":", "%3A").replace(",", "%2C")


def measured_files(checkout):
    """The paths, relative to `checkout`, of every Swift file under Sources/ and Plugins/ once symbolic links
    resolve."""
    files = set()
    for directory in MEASURED_DIRECTORIES:
        for parent, _, names in os.walk(os.path.join(checkout, directory)):
            for name in names:
                if not name.endswith(".swift"):
                    continue
                resolved = os.path.realpath(os.path.join(parent, name))
                relative = os.path.relpath(resolved, checkout)
                if relative.startswith(MEASURED_PREFIXES) and os.path.isfile(resolved):
                    files.add(relative)
    return files


def read_unmeasured_files(checkout):
    """{path: reason} for each file Scripts/unmeasured-files.txt lists."""
    list_path = os.path.join(checkout, UNMEASURED_FILES_LIST)
    if not os.path.isfile(list_path):
        raise UntrustworthyReport(f"{UNMEASURED_FILES_LIST} is missing")
    reasons = {}
    for number, line in enumerate(lines_of(list_path), start=1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path, _, reason = line.partition(":")
        path, reason = path.strip(), reason.strip()
        if not reason:
            raise UntrustworthyReport(f"{UNMEASURED_FILES_LIST}:{number} gives no reason; write `path: reason`")
        if path in reasons:
            raise UntrustworthyReport(f"{UNMEASURED_FILES_LIST}:{number} lists {path} a second time")
        reasons[path] = reason
    return reasons


def repository_path(recorded_path, checkout_root, checkout):
    """The path, relative to `checkout`, of the file a report's `SF:` path names once symbolic links resolve, or None
    when that file is outside the checkout or outside Sources/ and Plugins/."""
    if not recorded_path.startswith(checkout_root + "/"):
        return None
    relative = recorded_path[len(checkout_root) + 1:]
    resolved = os.path.relpath(os.path.realpath(os.path.join(checkout, relative)), checkout)
    if not resolved.startswith(MEASURED_PREFIXES):
        return None
    if not os.path.isfile(os.path.join(checkout, resolved)):
        raise UntrustworthyReport(f"the report records {relative}, which this checkout lacks: it measured another commit")
    return resolved


def read_report(platform, directory, checkout, commit):
    """({repository path: {line: execution count}}, the repository paths it records) for one platform's report, the
    copies of a file summed."""
    lcov_path = os.path.join(directory, "coverage.lcov")
    root_path = os.path.join(directory, "checkout-root.txt")
    commit_path = os.path.join(directory, "commit.txt")
    for required in (lcov_path, root_path, commit_path):
        if not os.path.isfile(required):
            raise UntrustworthyReport(
                f"{platform}: {required} is missing: the {platform} test job uploaded no report"
                " (it failed, was cancelled, or could not export its coverage)"
            )
    with open(commit_path, encoding="utf-8") as commit_file:
        measured_commit = commit_file.read().strip()
    if measured_commit != commit:
        raise UntrustworthyReport(f"{platform}: the report measured commit {measured_commit or '(none)'}, not {commit}")
    with open(root_path, encoding="utf-8") as root_file:
        checkout_root = root_file.read().strip().rstrip("/")
    if not checkout_root.startswith("/"):
        raise UntrustworthyReport(f"{platform}: {root_path} does not hold an absolute path")
    counts = collections.defaultdict(lambda: collections.defaultdict(int))
    recorded_files = set()
    source_lines_by_path = {}
    current = None
    current_source_lines = None
    in_record = False
    last_record = None
    with open(lcov_path, encoding="utf-8") as lcov:
        for record in lcov:
            record = record.rstrip("\n")
            if not record:
                continue
            last_record = record
            if record.startswith("SF:"):
                if in_record:
                    raise UntrustworthyReport(f"{platform}: a record in the report does not end with end_of_record")
                in_record = True
                try:
                    path = repository_path(record[3:], checkout_root, checkout)
                except UntrustworthyReport as error:
                    raise UntrustworthyReport(f"{platform}: {error}") from None
                if path is None:
                    current, current_source_lines = None, None
                else:
                    if path not in source_lines_by_path:
                        source_lines_by_path[path] = lines_of(os.path.join(checkout, path))
                    current, current_source_lines = counts[path], source_lines_by_path[path]
                    recorded_files.add(path)
            elif record.startswith("DA:") and current is not None:
                try:
                    line_number, count = (int(field) for field in record[3:].split(",")[:2])
                except ValueError:
                    raise UntrustworthyReport(f"{platform}: the report holds a malformed record, {record!r}") from None
                if not 1 <= line_number <= len(current_source_lines):
                    raise UntrustworthyReport(
                        f"{platform}: the report records a line past the end of a file: it measured another commit"
                    )
                if current_source_lines[line_number - 1].strip() not in UNCOUNTED_TEXT:
                    current[line_number] += max(count, 0)
            elif record == "end_of_record":
                in_record = False
                current, current_source_lines = None, None
    if last_record != "end_of_record":
        raise UntrustworthyReport(f"{platform}: the report does not end with end_of_record: the export was cut short")
    if not any(counts.values()):
        raise UntrustworthyReport(
            f"{platform}: the report records no line under Sources/ or Plugins/ of {checkout_root};"
            " check checkout-root.txt and the export"
        )
    return counts, recorded_files


def load_reports(platform_directories, checkout, commit):
    """{platform: {repository path: {line: execution count}}} for `platform_directories`, a list of (platform,
    directory), once every refusal in the module's docstring has been checked."""
    platforms = [platform for platform, _ in platform_directories]
    repeated = sorted({platform for platform in platforms if platforms.count(platform) > 1})
    if repeated:
        raise UntrustworthyReport(f"{', '.join(repeated)} is given more than once")
    if sorted(platforms) != sorted(REQUIRED_PLATFORMS):
        raise UntrustworthyReport(
            f"the check needs exactly the platforms {' and '.join(REQUIRED_PLATFORMS)}, not {', '.join(sorted(platforms))}"
        )
    reports = {}
    recorded_by = collections.defaultdict(list)
    for platform, directory in sorted(platform_directories):
        reports[platform], recorded_files = read_report(platform, directory, checkout, commit)
        for path in recorded_files:
            recorded_by[path].append(platform)
    unmeasured = read_unmeasured_files(checkout)
    files = measured_files(checkout)
    problems = []
    for path in sorted(unmeasured):
        if path not in files:
            problems.append(
                f"{UNMEASURED_FILES_LIST} lists {path}, which is not a Swift file under Sources/ or Plugins/ once"
                " symbolic links resolve; list the file it resolves to, or remove it"
            )
        elif path in recorded_by:
            problems.append(
                f"{UNMEASURED_FILES_LIST} lists {path}, which the {' and '.join(recorded_by[path])} report records;"
                " remove it from the list"
            )
    for path in sorted(files - set(recorded_by) - set(unmeasured)):
        problems.append(
            f"no report records {path}, so no test target compiles it and this check cannot see it; compile it into"
            f" a test target, or list it in {UNMEASURED_FILES_LIST} with the reason no test can"
        )
    if problems:
        raise UntrustworthyReport("\n".join(problems))
    return reports


def unexecuted_lines(reports):
    """(every recorded line, the unexecuted ones) over all platforms' reports, in path and line order. Each entry is
    (path, line, {platform: count})."""
    recorded = collections.defaultdict(dict)
    for platform in sorted(reports):
        for path, line_counts in reports[platform].items():
            for line, count in line_counts.items():
                recorded[(path, line)][platform] = count
    entries = [(path, line, recorded[(path, line)]) for path, line in sorted(recorded)]
    return entries, [entry for entry in entries if not any(count > 0 for count in entry[2].values())]


def describe_records(by_platform):
    return ", ".join(
        f"{platform} {by_platform[platform]}" if platform in by_platform else f"{platform} no record"
        for platform in REQUIRED_PLATFORMS
    )


def check(arguments, checkout, annotate):
    summary_path = None
    commit = None
    platform_arguments = []
    while arguments:
        argument, arguments = arguments[0], arguments[1:]
        if argument in ("--summary", "--commit") and arguments:
            value, arguments = arguments[0], arguments[1:]
            if argument == "--summary":
                summary_path = value
            else:
                commit = value
        elif "=" in argument and not argument.startswith("-"):
            platform_arguments.append(tuple(argument.split("=", 1)))
        else:
            print(__doc__, file=sys.stderr)
            return 64
    if commit is None:
        print(__doc__, file=sys.stderr)
        return 64
    try:
        reports = load_reports(platform_arguments, checkout, commit)
    except UntrustworthyReport as error:
        for message in str(error).split("\n"):
            print(f"::error::{escape_annotation_data(message)}" if annotate else message)
        return 2
    for platform in sorted(reports):
        files = sum(1 for line_counts in reports[platform].values() if line_counts)
        lines = sum(len(line_counts) for line_counts in reports[platform].values())
        print(f"{platform}: {lines} lines recorded in {files} files under Sources/ and Plugins/")
    print(f"{len(read_unmeasured_files(checkout))} files are listed in {UNMEASURED_FILES_LIST} as unmeasured")
    entries, unexecuted = unexecuted_lines(reports)
    rows = []
    source_lines_by_path = {}
    for path, line, by_platform in unexecuted:
        if path not in source_lines_by_path:
            source_lines_by_path[path] = lines_of(os.path.join(checkout, path))
        source = source_lines_by_path[path][line - 1].strip()
        records = describe_records(by_platform)
        print(f"{path}:{line}: {source}    [{records}]")
        if annotate:
            print(
                f"::error file={escape_annotation_property(path)},line={line}::"
                f"{escape_annotation_data(f'No test executes this line ({records}).')}"
            )
        rows.append((path, line, source, records))
    executed = len(entries) - len(unexecuted)
    print(f"{len(unexecuted)} of {len(entries)} recorded lines no test executes on {' or '.join(REQUIRED_PLATFORMS)}"
          f" ({100 * executed / len(entries):.2f}% executed)")
    if summary_path is not None:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write(f"### Line coverage: {executed} of {len(entries)} lines executed\n\n")
            if rows:
                summary.write("| Line | Source | Counts |\n| --- | --- | --- |\n")
                for path, line, source, records in rows:
                    escaped = source.replace("|", "\\|").replace("`", "'")
                    summary.write(f"| `{path}:{line}` | `{escaped}` | {records} |\n")
            else:
                summary.write("Every recorded line under Sources/ and Plugins/ is executed.\n")
    return 1 if unexecuted else 0


def self_test(directory):
    if os.path.exists(directory):
        print(f"{directory} exists; --self-test writes a new directory", file=sys.stderr)
        return 64
    commit = "0123456789abcdef0123456789abcdef01234567"
    checkout = os.path.join(directory, "checkout")
    sources = {
        "Sources/Core/A.swift": "let a1 = 1\nlet a2 = 2\nlet a3 = 3\nlet a4 = 4\nlet a5 = 5\n}\n\n",
        "Plugins/B,%.swift": "let b1 = 1\nlet b2 = 2\nlet b3 = 3\n",
        "Plugins/Unmeasured.swift": "import PackagePlugin\n",
        "Sources/Core/Notes.md": "Not Swift.\n",
        UNMEASURED_FILES_LIST: "# Comment.\n\nPlugins/Unmeasured.swift: imports PackagePlugin\n",
    }

    def write(path, contents):
        os.makedirs(os.path.join(checkout, os.path.dirname(path)), exist_ok=True)
        with open(os.path.join(checkout, path), "w", encoding="utf-8") as written_file:
            written_file.write(contents)

    for path, contents in sources.items():
        write(path, contents)
    os.makedirs(os.path.join(checkout, "Sources/Macros"))
    os.symlink("../Core", os.path.join(checkout, "Sources/Macros/Core"))
    os.makedirs(os.path.join(checkout, "Plugins/Generator"))
    os.symlink("../B,%.swift", os.path.join(checkout, "Plugins/Generator/B,%.swift"))
    os.makedirs(os.path.join(checkout, "Tests/PluginTests"))
    os.symlink("../../Plugins/B,%.swift", os.path.join(checkout, "Tests/PluginTests/B,%.swift"))
    checkout = os.path.realpath(checkout)

    def write_report(name, root, records, ending="end_of_record\n", report_commit=commit):
        report_directory = os.path.join(directory, name)
        os.makedirs(report_directory)
        with open(os.path.join(report_directory, "checkout-root.txt"), "w", encoding="utf-8") as root_file:
            root_file.write(root + "\n")
        with open(os.path.join(report_directory, "commit.txt"), "w", encoding="utf-8") as commit_file:
            commit_file.write(report_commit + "\n")
        with open(os.path.join(report_directory, "coverage.lcov"), "w", encoding="utf-8") as lcov:
            for index, (path, line_counts) in enumerate(records):
                lcov.write(f"SF:{path}\n")
                lcov.writelines(f"DA:{line},{count}\n" for line, count in line_counts)
                lcov.write(ending if index == len(records) - 1 else "end_of_record\n")
        return report_directory

    linux_root = "/__w/SafeDI/SafeDI"
    macos_root = "/Users/runner/work/SafeDI/SafeDI"
    linux = write_report("linux", linux_root, [
        (f"{linux_root}/Sources/Core/A.swift", [(1, 0), (2, 4), (3, 0), (6, 0), (7, 0)]),
        (f"{linux_root}/Tests/PluginTests/B,%.swift", [(1, 1), (2, 0)]),
        (f"{linux_root}/.build/checkouts/Dependency/Sources/C.swift", [(1, 0)]),
        ("/elsewhere/Sources/Core/A.swift", [(4, 0)]),
    ])
    macos = write_report("macos", macos_root, [
        (f"{macos_root}/Sources/Core/A.swift", [(1, 3), (3, 0), (4, 0)]),
        (f"{macos_root}/Sources/Macros/Core/A.swift", [(5, 2)]),
        (f"{macos_root}/Plugins/B,%.swift", [(2, 0), (3, 7)]),
    ])

    def linux_with(name, records, **arguments):
        return [("linux", write_report(name, linux_root, records, **arguments)), ("macos", macos)]

    failures = []

    def expect_refusal(name, platform_directories, refusal):
        try:
            load_reports(platform_directories, checkout, commit)
            failures.append(f"{name}: read without the refusal '{refusal}'")
        except UntrustworthyReport as error:
            if refusal not in str(error):
                failures.append(f"{name}: refused with '{error}', expected '{refusal}'")

    both = [("linux", linux), ("macos", macos)]
    _, unexecuted = unexecuted_lines(load_reports(both, checkout, commit))
    found = [(path, line) for path, line, _ in unexecuted]
    expected = [("Plugins/B,%.swift", 2), ("Sources/Core/A.swift", 3), ("Sources/Core/A.swift", 4)]
    if found != expected:
        failures.append(f"unexecuted lines {found}, expected {expected}")

    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        status = check(["--commit", commit, f"linux={linux}", f"macos={macos}"], checkout, annotate=True)
    expected_annotation = "::error file=Plugins/B%2C%25.swift,line=2::No test executes this line (linux 0, macos 0)."
    if status != 1 or expected_annotation not in output.getvalue().split("\n"):
        failures.append(f"check exited {status}, expected 1 with '{expected_annotation}', and printed:\n{output.getvalue()}")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        status = check(["--commit", commit, f"linux={directory}/missing", f"macos={macos}"], checkout, annotate=True)
    if status != 2 or not output.getvalue().startswith("::error::linux: "):
        failures.append(f"check of a missing report exited {status}, expected 2, and printed:\n{output.getvalue()}")

    expect_refusal("only linux", [("linux", linux)], "exactly the platforms linux and macos")
    expect_refusal("another platform", both + [("windows", linux)], "exactly the platforms linux and macos")
    expect_refusal("linux twice", both + [("linux", linux)], "linux is given more than once")
    expect_refusal("missing", [("linux", os.path.join(directory, "missing")), ("macos", macos)], "is missing")
    expect_refusal("wrong root", [("linux", write_report("wrong-root", "/home/runner/work/SafeDI/SafeDI", [
        (f"{linux_root}/Sources/Core/A.swift", [(1, 1)]),
    ])), ("macos", macos)], "records no line")
    expect_refusal("other commit", linux_with("other-commit", [
        (f"{linux_root}/Sources/Core/A.swift", [(1, 1)]),
    ], report_commit="fedcba9876543210fedcba9876543210fedcba98"), "measured commit fedcba98")
    expect_refusal("file of another commit", linux_with("deleted-file", [
        (f"{linux_root}/Sources/Core/A.swift", [(1, 1)]),
        (f"{linux_root}/Sources/Core/Deleted.swift", [(1, 1)]),
    ]), "which this checkout lacks")
    # B,%.swift has three lines and ends with a newline, so line 4 is past its end.
    expect_refusal("longer file", linux_with("longer-file", [
        (f"{linux_root}/Plugins/B,%.swift", [(1, 1), (4, 0)]),
    ]), "past the end of a file")
    expect_refusal("cut short", linux_with("cut-short", [
        (f"{linux_root}/Sources/Core/A.swift", [(1, 1)]),
    ], ending=""), "does not end with end_of_record")
    expect_refusal("unclosed record", linux_with("unclosed-record", [
        (f"{linux_root}/Sources/Core/A.swift", [(1, 1)]),
    ], ending="SF:/__w/SafeDI/SafeDI/Plugins/B,%.swift\nDA:1,1\nend_of_record\n"), "a record in the report does not end")
    expect_refusal("malformed", linux_with("malformed", [
        (f"{linux_root}/Sources/Core/A.swift", [(1, "one")]),
    ]), "malformed record")
    expect_refusal("unmeasured file recorded", linux_with("unmeasured-recorded", [
        (f"{linux_root}/Sources/Core/A.swift", [(1, 1)]),
        (f"{linux_root}/Plugins/Unmeasured.swift", [(1, 0)]),
    ]), "lists Plugins/Unmeasured.swift, which the linux report records")

    write("Sources/Core/New.swift", "let new = 1\n")
    expect_refusal("file no report records", both, "no report records Sources/Core/New.swift")
    os.remove(os.path.join(checkout, "Sources/Core/New.swift"))
    write(UNMEASURED_FILES_LIST, sources[UNMEASURED_FILES_LIST] + "Plugins/Gone.swift: deleted\n")
    expect_refusal("listed file missing", both, "lists Plugins/Gone.swift, which is not a Swift file")
    write(UNMEASURED_FILES_LIST, sources[UNMEASURED_FILES_LIST] + "Plugins/Generator/B,%.swift: a symbolic link\n")
    expect_refusal("listed symbolic link", both, "lists Plugins/Generator/B,%.swift, which is not a Swift file")
    write(UNMEASURED_FILES_LIST, sources[UNMEASURED_FILES_LIST] + "Plugins/NoReason.swift\n")
    expect_refusal("listed without reason", both, "gives no reason")
    write(UNMEASURED_FILES_LIST, sources[UNMEASURED_FILES_LIST])

    for failure in failures:
        print(f"self-test failed: {failure}")
    if not failures:
        print("self-test passed")
    return 1 if failures else 0


def main():
    if sys.argv[1:2] == ["--self-test"] and len(sys.argv) == 3:
        return self_test(sys.argv[2])
    return check(sys.argv[1:], os.path.realpath(os.getcwd()), os.environ.get("GITHUB_ACTIONS") == "true")


if __name__ == "__main__":
    sys.exit(main())
