#!/usr/bin/env python3
"""Usage: git diff -U0 BASE -- 'Sources/*.swift' 'Plugins/*.swift' | changed-line-coverage.py [--files LIST] LCOV
       changed-line-coverage.py --self-test DIRECTORY

Prints `path:line: source` for every added or changed line the lcov report records as executed zero times, and a
total; exits 1 when the total is not zero. Files are matched through `os.path.realpath`, so a file the plugin
compiles through a symbolic link and the file it links to are one file, whose counts are summed. Lines with no
`DA` record (comments, declarations) are skipped, as Codecov skips them.

With --files LIST, a file of the paths the change adds, renames or edits, one per line, it also prints each of those
Swift files under Sources/ or Plugins/ that the report does not record and Scripts/unmeasured-files.txt does not
list, and exits 1 when there is any. "Check Line Coverage on Linux" (Scripts/unexecuted-lines.py) fails on such a
file, which has no unexecuted line to report: a file of declarations only gives the compiler nothing to count. A
file is recorded when the report has a `DA` record for a line of it whose text is more than a brace, as in that
check. This report is one platform's, so a file only the other platform's tests compile is printed too.

--self-test DIRECTORY writes fixtures into DIRECTORY, which must not exist, and checks both reports.
"""
import collections
import os
import re
import sys


def read_coverage(lcov_path):
    counts = collections.defaultdict(lambda: collections.defaultdict(int))
    current = None
    with open(lcov_path, encoding="utf-8") as lcov:
        for record in lcov:
            record = record.rstrip("\n")
            if record.startswith("SF:"):
                current = counts[os.path.realpath(record[3:])]
            elif record.startswith("DA:") and current is not None:
                line_number, count = record[3:].split(",")[:2]
                current[int(line_number)] += int(count)
            elif record == "end_of_record":
                current = None
    return counts


def read_changed_lines(diff):
    changed = collections.defaultdict(list)
    path = None
    new_line = 0
    for line in diff:
        line = line.rstrip("\n")
        if line.startswith("+++ "):
            path = None if line == "+++ /dev/null" else line[len("+++ b/"):]
        elif line.startswith("@@"):
            match = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
            new_line = int(match.group(1)) if match else 0
        elif path is not None and line.startswith("+"):
            changed[path].append(new_line)
            new_line += 1
    return changed


UNMEASURED_FILES_LIST = "Scripts/unmeasured-files.txt"
MEASURED_PREFIXES = ("Sources/", "Plugins/")
UNCOUNTED_TEXT = ("", "{", "}")


def read_unmeasured_files():
    """The paths Scripts/unmeasured-files.txt lists, each a line `path: reason`."""
    listed = set()
    if os.path.isfile(UNMEASURED_FILES_LIST):
        with open(UNMEASURED_FILES_LIST, encoding="utf-8") as unmeasured:
            for line in unmeasured:
                line = line.strip()
                if line and not line.startswith("#"):
                    listed.add(line.partition(":")[0].strip())
    return listed


def unrecorded_files(paths, coverage):
    """The Swift files among `paths` under Sources/ or Plugins/, once symbolic links resolve, that the report
    records no counted line of and Scripts/unmeasured-files.txt does not list, in path order."""
    listed = read_unmeasured_files()
    unrecorded = set()
    for path in paths:
        if not path.endswith(".swift") or not os.path.isfile(path):
            continue
        resolved = os.path.realpath(path)
        relative = os.path.relpath(resolved, os.path.realpath("."))
        if not relative.startswith(MEASURED_PREFIXES) or relative in listed:
            continue
        with open(resolved, encoding="utf-8") as source:
            source_lines = source.read().split("\n")
        recorded_lines = coverage.get(resolved, {})
        if not any(
            line_number <= len(source_lines) and source_lines[line_number - 1].strip() not in UNCOUNTED_TEXT
            for line_number in recorded_lines
        ):
            unrecorded.add(relative)
    return sorted(unrecorded)


def report(lcov_path, diff, files_path):
    coverage = read_coverage(lcov_path)
    changed = read_changed_lines(diff)
    unexecuted = 0
    for path in sorted(changed):
        file_counts = coverage.get(os.path.realpath(path))
        if file_counts is None:
            continue
        with open(path, encoding="utf-8") as source:
            source_lines = source.read().split("\n")
        for line_number in changed[path]:
            if file_counts.get(line_number) == 0:
                unexecuted += 1
                print(f"{path}:{line_number}: {source_lines[line_number - 1].strip()}")
    print(f"{unexecuted} changed line(s) no test executed")
    unrecorded = []
    if files_path is not None:
        with open(files_path, encoding="utf-8") as files:
            unrecorded = unrecorded_files([line.rstrip("\n") for line in files], coverage)
        for path in unrecorded:
            print(
                f"{path}: this report records no line of it, and {UNMEASURED_FILES_LIST} does not list it;"
                " \"Check Line Coverage on Linux\" fails on such a file unless the other platform's tests record it."
                " Move its declarations into a file a test executes, or list it with the reason no test can"
            )
        print(f"{len(unrecorded)} changed file(s) the report does not record")
    return 1 if unexecuted or unrecorded else 0


def self_test(root):
    if os.path.exists(root):
        print(f"{root} exists; --self-test writes a new directory", file=sys.stderr)
        return 2
    sources = {
        "Sources/Core/Executed.swift": "func executed() {\n\tprint(1)\n}\n",
        "Sources/Core/Declarations.swift": "struct Declarations {\n\tlet value: Int\n}\n",
        "Sources/Core/BracesOnly.swift": "struct BracesOnly {\n\tlet value: Int\n}\n",
        "Sources/Core/Unexecuted.swift": "func unexecuted() {\n\tprint(2)\n}\n",
        "Plugins/Listed.swift": "struct Listed {}\n",
        "Plugins/Notes.md": "notes\n",
        "Tests/Core/Tests.swift": "struct Tests {}\n",
        UNMEASURED_FILES_LIST: "# reasons\nPlugins/Listed.swift: imports PackagePlugin\n",
    }
    for path, text in sources.items():
        os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
        with open(os.path.join(root, path), "w", encoding="utf-8") as source:
            source.write(text)
    os.symlink("Executed.swift", os.path.join(root, "Sources/Core/Linked.swift"))
    here = os.getcwd()
    os.chdir(root)
    try:
        absolute = os.path.realpath(".")
        with open("report.lcov", "w", encoding="utf-8") as lcov:
            lcov.write(f"SF:{absolute}/Sources/Core/Executed.swift\nDA:1,1\nDA:2,1\nDA:3,1\nend_of_record\n")
            lcov.write(f"SF:{absolute}/Sources/Core/BracesOnly.swift\nDA:3,0\nend_of_record\n")
            lcov.write(f"SF:{absolute}/Sources/Core/Unexecuted.swift\nDA:1,0\nDA:2,0\nDA:3,0\nend_of_record\n")
        coverage = read_coverage("report.lcov")
        failures = []
        actual = unrecorded_files(sorted(sources) + ["Sources/Core/Linked.swift", "Sources/Core/Deleted.swift"], coverage)
        expected = ["Sources/Core/BracesOnly.swift", "Sources/Core/Declarations.swift"]
        if actual != expected:
            failures.append(f"unrecorded files: {actual}, expected {expected}")
        with open("files.txt", "w", encoding="utf-8") as files:
            files.write("Sources/Core/Executed.swift\nSources/Core/Declarations.swift\n")
        diff = ["+++ b/Sources/Core/Unexecuted.swift", "@@ -0,0 +1,3 @@", "+func unexecuted() {", "+\tprint(2)", "+}"]
        for name, arguments, expected_status in (
            ("an unexecuted line", (diff, None), 1),
            ("no finding", ([], None), 0),
            ("an unrecorded file", ([], "files.txt"), 1),
        ):
            saved, sys.stdout = sys.stdout, open(os.devnull, "w", encoding="utf-8")
            try:
                status = report("report.lcov", *arguments)
            finally:
                sys.stdout.close()
                sys.stdout = saved
            if status != expected_status:
                failures.append(f"{name}: status {status}, expected {expected_status}")
    finally:
        os.chdir(here)
    for failure in failures:
        print(failure, file=sys.stderr)
    print("self-test passed" if not failures else f"self-test: {len(failures)} failure(s)")
    return 1 if failures else 0


def main():
    arguments = sys.argv[1:]
    if len(arguments) == 2 and arguments[0] == "--self-test":
        return self_test(arguments[1])
    files_path = None
    if len(arguments) == 3 and arguments[0] == "--files":
        files_path = arguments[1]
        arguments = arguments[2:]
    if len(arguments) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    return report(arguments[0], sys.stdin, files_path)


if __name__ == "__main__":
    sys.exit(main())
