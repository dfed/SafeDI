#!/usr/bin/env python3
"""Runs, on this machine, the test suites a branch touches, and prints only what failed.

    verify-touched.py [BASE] [--list] [--skip-compile-checks] [--also FILTER]... [--whole-suite] [--log FILE]
                      [--runner COMMAND]
    verify-touched.py --self-test

BASE is the commit or branch the change is measured from (default `origin/main`); the changed files are those that
differ between its merge base with `HEAD` and the working tree, with untracked files. It runs from the checkout's top
level, wherever it is started.

Every changed path matches one rule, in this order, or runs the whole suite; no path is skipped silently:

- `Package.swift`, `Package.resolved` or a file under `Tests/SafeDIToolTestSupport`: the whole suite;
- a Swift file of a test target: every type it declares or extends at the top level, as `Target.Type`; its whole
  target when it was deleted, declares no test, contains `#if` (a suite inside one is not at the top level) or yields
  no type; any other file of a test target: its target;
- a file under `Sources/` or `Plugins/`: the test targets `TARGETS_OF_SOURCES` names for its directory. Every source
  directory reaches the plugin's tests, which read the sources (`SourceRuleTests`, `MacroTargetSourceTests`), and
  every one but the plugins reaches the five `SafeDITool` test targets, whose compile checks build against it;
- a path a test reads (`TARGETS_OF_READ_PATHS`): the targets of those tests;
- a path on `REACHES_NO_TEST`: nothing, and the script prints it.

`--list` prints the `swift test` filters and runs nothing. `--skip-compile-checks` sets `SAFEDI_SKIP_COMPILE_CHECK`,
for a first pass; without it each test's generated code is compiled, in a debug build, and an inherited
`SAFEDI_SKIP_COMPILE_CHECK` is dropped. `--also` adds a filter, and `--whole-suite` runs every test whatever changed. `--runner` (or
`SAFEDI_VERIFY_RUNNER`) is a command the `swift test` command is appended to, for a machine that queues heavy work.

The build is a debug build, not CI's release build, so it finds what tests assert and not what only the release
compiler rejects. `TMPDIR` is a folder of this run's own, inside an inherited `TMPDIR` when that is outside the
system temporary directory and the checkout, else inside the SwiftPM folder `CLAUDE.md` names; the script removes it
when it ends, also when it is terminated. The run's whole output goes to a log of this run's own, which it names.

It prints each failed test with its recorded issues and the run's last line. Exit status: `swift test`'s; 0 without a
run when every changed path reaches no test; 1 when the run passed and ran no test; 2 for wrong arguments or a base
git cannot find.
"""

import argparse
import fnmatch
import os
import pathlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

# Another script may import this one; neither leaves a `__pycache__` in the checkout.
sys.dont_write_bytecode = True

TEST_TARGETS_DIRECTORY = "Tests"
HELPER_TARGET = "SafeDIToolTestSupport"
PLUGIN_TEST_TARGET = "SafeDIGeneratorPluginTests"
TOOL_TEST_TARGETS = [
    "SafeDIToolTests",
    "SafeDIToolDependencyTreeTests",
    "SafeDIToolMockTests",
    "SafeDIToolSeamTests",
    "SafeDIToolFuzzerTests",
]
# The test targets that exercise each source directory. A directory missing here runs the whole suite.
TARGETS_OF_SOURCES = {
    "Sources/SafeDI": ["SafeDITests"] + TOOL_TEST_TARGETS + [PLUGIN_TEST_TARGET],
    "Sources/SafeDIMacros": ["SafeDIMacrosTests"] + TOOL_TEST_TARGETS + [PLUGIN_TEST_TARGET],
    "Sources/SafeDICore": ["SafeDICoreTests", "SafeDIMacrosTests"] + TOOL_TEST_TARGETS + [PLUGIN_TEST_TARGET],
    "Sources/SafeDIToolLibrary": TOOL_TEST_TARGETS + [PLUGIN_TEST_TARGET],
    "Sources/SafeDITool": TOOL_TEST_TARGETS + [PLUGIN_TEST_TARGET],
    "Plugins": [PLUGIN_TEST_TARGET],
}
# Paths outside the targets that tests read, as `fnmatch` patterns, and the targets of those tests.
TARGETS_OF_READ_PATHS = {
    "Documentation/Manual.md": TOOL_TEST_TARGETS,
    "TuistPlugins/*": [PLUGIN_TEST_TARGET],
    ".github/scripts/*": ["SafeDIToolFuzzerTests", PLUGIN_TEST_TARGET],
    "bazel/*": [PLUGIN_TEST_TARGET],
    "BUILD.bazel": [PLUGIN_TEST_TARGET],
}
# Paths no test reads, as `fnmatch` patterns (`*` crosses `/`). A path that matches no rule runs the whole suite.
REACHES_NO_TEST = [
    ".claude/*",
    ".github/*",
    ".bcr/*",
    "CLI/*",
    "Examples/*",
    "Scripts/*",
    "Documentation/*",
    "*.md",
    ".bazelignore",
    ".bazelrc",
    ".bazelversion",
    ".editorconfig",
    ".git-blame-ignore-revs",
    ".gitignore",
    ".spi.yml",
    ".swiftformat",
    "LICENSE",
    "MODULE.bazel",
    "MODULE.bazel.lock",
    "codecov.yml",
]
WHOLE_SUITE_FILES = {"Package.swift", "Package.resolved"}
TOP_LEVEL_TYPE = re.compile(
    r"^(?:@[^\n]*\n)*?(?:(?:public|internal|private|fileprivate|final|nonisolated)\s+)*"
    r"(?:struct|class|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
DECLARES_TESTS = re.compile(r"@Test\b|@Suite\b|\bfunc\s+test[A-Z0-9_]")
CONDITIONAL_COMPILATION = re.compile(r"^\s*#if\b", re.MULTILINE)
TESTS_RUN = re.compile(r"Test run with (\d+) tests?|Executed (\d+) tests?")


class WholeSuite(Exception):
    """A changed file reaches every test."""


def suites_of_test_file(target, text):
    """The filters of the top-level types a test file declares or extends; none when its whole target must run."""
    if not DECLARES_TESTS.search(text) or CONDITIONAL_COMPILATION.search(text):
        return []
    names = []
    for match in TOP_LEVEL_TYPE.finditer(text):
        if match.group(1) not in names:
            names.append(match.group(1))
    return [f"^{target}\\.{name}[./]" for name in names]


def filters_of_changes(changed_paths, read_text, unselected=None):
    """The `swift test` filters of the changed paths, in a stable order, and why each is there.

    Raises `WholeSuite` when a path reaches every test, which a path no rule matches does. `read_text` returns a
    path's text, or None when the path no longer exists. The paths on `REACHES_NO_TEST` are appended to `unselected`.
    """
    filters = {}

    def add(pattern, reason):
        filters.setdefault(pattern, reason)

    for path in sorted(changed_paths):
        parts = pathlib.PurePosixPath(path).parts
        read_targets = [targets for pattern, targets in TARGETS_OF_READ_PATHS.items() if fnmatch.fnmatchcase(path, pattern)]
        if path in WHOLE_SUITE_FILES:
            raise WholeSuite(path)
        if parts[0] == TEST_TARGETS_DIRECTORY and len(parts) >= 3:
            target = parts[1]
            if target == HELPER_TARGET:
                raise WholeSuite(path)
            text = read_text(path) if path.endswith(".swift") else None
            patterns = suites_of_test_file(target, text) if text is not None else []
            for pattern in patterns:
                add(pattern, path)
            if not patterns:
                # Deleted, a file of helpers, a fixture, or suites this script cannot name: the target's tests tell.
                add(f"^{target}\\.", f"{path} names no suite of its own")
        elif parts[0] in ("Sources", "Plugins") and len(parts) >= 2:
            directory = "Plugins" if parts[0] == "Plugins" else "/".join(parts[:2])
            targets = TARGETS_OF_SOURCES.get(directory)
            if targets is None:
                raise WholeSuite(path)
            for target in targets:
                add(f"^{target}\\.", f"{directory} changed")
        elif read_targets:
            for target in read_targets[0]:
                add(f"^{target}\\.", f"its tests read {path}")
        elif any(fnmatch.fnmatchcase(path, pattern) for pattern in REACHES_NO_TEST):
            if unselected is not None:
                unselected.append(path)
        else:
            raise WholeSuite(path)
    return without_covered(filters)


def without_covered(filters):
    """Drops a suite's filter when its whole target is already selected."""
    whole_targets = {pattern for pattern in filters if pattern.count("\\.") == 1 and pattern.endswith("\\.")}
    kept = {}
    for pattern, reason in filters.items():
        target_pattern = pattern.split("\\.")[0] + "\\."
        if pattern in whole_targets or target_pattern not in whole_targets:
            kept[pattern] = reason
    return kept


def tests_run(lines):
    """How many tests the run's summary lines count, swift-testing's and XCTest's together."""
    total = 0
    for line in lines:
        for match in TESTS_RUN.finditer(line):
            total += int(match.group(1) or match.group(2))
    return total


def failures_of_output(lines):
    """The lines of a swift-testing or XCTest run that report a failure, and the run's last summary line."""
    failures = []
    summary = None
    for line in lines:
        stripped = line.rstrip("\n")
        if "Test run with " in stripped or stripped.startswith("Executed "):
            summary = stripped
            continue
        if " recorded a known issue" in stripped or stripped.startswith("✘ Suite "):
            continue
        if stripped.startswith("✘") and " passed after " not in stripped:
            failures.append(stripped)
        elif re.search(r": error: ", stripped) or stripped.startswith("error: "):
            failures.append(stripped)
    return failures, summary


def git(*arguments):
    return subprocess.run(["git", *arguments], check=True, capture_output=True, text=True).stdout


def changed_paths_since(base):
    merge_base = git("merge-base", base, "HEAD").strip()
    changed = set(git("diff", "--name-only", "--no-renames", merge_base).split("\n"))
    changed |= set(git("ls-files", "--others", "--exclude-standard").split("\n"))
    changed.discard("")
    return changed


def read_text_in_checkout(path):
    file = pathlib.Path(path)
    if file.is_file():
        return file.read_text(encoding="utf-8")
    else:
        return None


def caches_directory():
    return pathlib.Path.home() / ("Library/Caches" if sys.platform == "darwin" else ".cache") / "SafeDITests"


def is_inside(path, directory):
    return path == directory or directory in path.parents


def temporary_directory_parent(inherited, checkout, system_temporary_directories):
    """The folder this run's `TMPDIR` is made in: the inherited one when it is safe, else the one CLAUDE.md names.

    Safe is outside the system temporary directory, which macOS empties at startup, and outside the checkout, where
    fixtures would be read as part of the project.
    """
    if inherited:
        candidate = pathlib.Path(inherited).resolve()
        unsafe = [checkout.resolve()] + [pathlib.Path(directory).resolve() for directory in system_temporary_directories]
        if candidate.is_dir() and not any(is_inside(candidate, directory) for directory in unsafe):
            return candidate
    return caches_directory() / "swiftpm"


def system_temporary_directories():
    directories = ["/tmp", "/var/tmp", "/var/folders", "/private/tmp", "/private/var/tmp", "/private/var/folders"]
    return [directory for directory in directories if pathlib.Path(directory).exists()]


def run(arguments):
    try:
        os.chdir(git("rev-parse", "--show-toplevel").strip())
        changed = changed_paths_since(arguments.base)
    except subprocess.CalledProcessError as error:
        print(f"verify-touched: {error.stderr.strip()}", file=sys.stderr)
        return 2
    whole_suite_reason = None
    filters = {}
    unselected = []
    try:
        filters = filters_of_changes(changed, read_text_in_checkout, unselected)
    except WholeSuite as reason:
        whole_suite_reason = str(reason)
    if arguments.whole_suite and whole_suite_reason is None:
        whole_suite_reason = "--whole-suite"
    for pattern in arguments.also:
        filters.setdefault(pattern, "--also")

    command = shlex.split(arguments.runner) + ["swift", "test", "--traits", "sourceBuild"]
    if whole_suite_reason is not None:
        print(f"The whole suite: {whole_suite_reason} reaches every test, or no rule says which it reaches.")
    else:
        for path in unselected:
            print(f"# {path} reaches no test")
        for pattern, reason in filters.items():
            print(f"--filter '{pattern}'   # {reason}")
            command += ["--filter", pattern]
        if not filters:
            print(f"No changed path since {arguments.base} reaches a test: nothing to run.")
            return 0
    if arguments.list:
        return 0

    parent = temporary_directory_parent(os.environ.get("TMPDIR"), pathlib.Path.cwd(), system_temporary_directories())
    parent.mkdir(parents=True, exist_ok=True)
    temporary_directory = pathlib.Path(tempfile.mkdtemp(prefix="verify-touched-", dir=parent))
    if arguments.log:
        log = pathlib.Path(arguments.log)
    else:
        logs = caches_directory() / "verify-touched-logs"
        logs.mkdir(parents=True, exist_ok=True)
        log = logs / f"{time.strftime('%Y%m%dT%H%M%S')}-{os.getpid()}.log"
    environment = dict(os.environ, TMPDIR=str(temporary_directory))
    if arguments.skip_compile_checks:
        environment["SAFEDI_SKIP_COMPILE_CHECK"] = "1"
    elif environment.pop("SAFEDI_SKIP_COMPILE_CHECK", None) is not None:
        print("Dropped the inherited SAFEDI_SKIP_COMPILE_CHECK: generated code is compiled unless --skip-compile-checks.")
    print(f"Running; the whole output goes to {log}", flush=True)
    started = []

    def end(signal_number, _frame):
        for process in started:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        shutil.rmtree(temporary_directory, ignore_errors=True)
        sys.exit(128 + signal_number)

    # Before the run starts, so that no signal finds `swift test` running and this script without a handler.
    for signal_number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signal_number, end)
    with log.open("w", encoding="utf-8") as output:
        # A session of its own, so that ending this script ends `swift test` and everything it started.
        started.append(subprocess.Popen(command, env=environment, stdout=output, stderr=subprocess.STDOUT, start_new_session=True))
        status = started[0].wait()
    shutil.rmtree(temporary_directory, ignore_errors=True)
    with log.open(encoding="utf-8", errors="replace") as output:
        lines = output.readlines()
    failures, summary = failures_of_output(lines)
    for line in failures:
        print(line)
    print(summary if summary else f"No summary line; read {log}.")
    if status == 0 and tests_run(lines) == 0:
        print("The run passed and ran no test: a filter matched nothing. Read --list.")
        return 1
    else:
        return status


def check_against_checkout(expect):
    """The maps name exactly the targets the checkout has, and every tracked file matches a rule."""
    test_targets = {path.name for path in pathlib.Path(TEST_TARGETS_DIRECTORY).iterdir() if path.is_dir()}
    mapped = {target for targets in list(TARGETS_OF_SOURCES.values()) + list(TARGETS_OF_READ_PATHS.values()) for target in targets}
    expect(sorted(mapped - test_targets), [], "every mapped test target is a directory under Tests/")
    expect(sorted(test_targets - mapped - {HELPER_TARGET}), [], "every test target but the helpers is mapped from what it tests")
    source_directories = {f"Sources/{path.name}" for path in pathlib.Path("Sources").iterdir() if path.is_dir()} | {"Plugins"}
    expect(sorted(TARGETS_OF_SOURCES), sorted(source_directories), "TARGETS_OF_SOURCES lists exactly the source directories")
    tracked = [path for path in git("ls-files").split("\n") if path]
    unselected = []
    for path in tracked:
        try:
            filters = filters_of_changes({path}, read_text_in_checkout)
        except WholeSuite:
            # Ruled: a path no rule names runs the whole suite, which is safe, so a new top-level path fails nothing.
            continue
        if path.startswith(f"{TEST_TARGETS_DIRECTORY}/") and path.count("/") >= 2 and not filters:
            unselected.append(path)
    expect(unselected, [], "every file of a test target selects a filter")


def self_test():
    def expect(actual, expected, what):
        if actual != expected:
            print(f"self-test failed: {what}\n  expected {expected!r}\n  actual   {actual!r}", file=sys.stderr)
            sys.exit(1)

    suite = "/// A comment.\n@Suite(.serialized)\nstruct SeamTests: ~Copyable {\n\t@Test func a() {}\n\tstruct Nested {}\n}\nextension SeamTests.Inner {\n}\nprivate enum Fixture {}\n"
    files = {
        "Tests/SafeDIToolSeamTests/SeamTests.swift": suite,
        "Tests/SafeDIToolSeamTests/Helpers.swift": "enum Helpers {}\n",
        "Tests/SafeDIMacrosTests/MacroTests.swift": "final class MacroTests: XCTestCase {\n\tfunc testIt() {}\n}\n",
    }
    read = files.get
    expect(
        list(filters_of_changes({"Tests/SafeDIToolSeamTests/SeamTests.swift"}, read)),
        ["^SafeDIToolSeamTests\\.SeamTests[./]", "^SafeDIToolSeamTests\\.Fixture[./]"],
        "a test file selects its top-level types, once each, and no nested one",
    )
    expect(
        list(filters_of_changes({"Tests/SafeDIToolSeamTests/Helpers.swift"}, read)),
        ["^SafeDIToolSeamTests\\."],
        "a file that declares no suite selects its target's tests",
    )
    expect(
        list(filters_of_changes({"Tests/SafeDIMacrosTests/MacroTests.swift", "Sources/SafeDIMacros/A.swift"}, read))[0],
        "^SafeDIMacrosTests\\.",
        "a source change selects its target's tests, which cover a changed suite of that target",
    )
    expect(
        list(filters_of_changes({"Tests/SafeDIToolSeamTests/Gone.swift"}, read)),
        ["^SafeDIToolSeamTests\\."],
        "a deleted test file selects its target",
    )
    expect(
        list(filters_of_changes({"Sources/SafeDIToolLibrary/A.swift", "README.md"}, read)),
        [f"^{target}\\." for target in TOOL_TEST_TARGETS] + ["^SafeDIGeneratorPluginTests\\."],
        "a tool change selects the tool's five test targets and the plugin's, and Markdown nothing",
    )
    conditional = "#if canImport(SafeDIMacros)\n\tfinal class MacroTests: XCTestCase {\n\t\tfunc testIt() {}\n\t}\n#endif\n"
    files["Tests/SafeDIMacrosTests/ConditionalTests.swift"] = conditional
    expect(
        list(filters_of_changes({"Tests/SafeDIMacrosTests/ConditionalTests.swift"}, read)),
        ["^SafeDIMacrosTests\\."],
        "a suite declared inside `#if` selects its target",
    )
    expect(
        list(filters_of_changes({"Sources/SafeDI/SafeDI.swift"}, read)),
        ["^SafeDITests\\."] + [f"^{target}\\." for target in TOOL_TEST_TARGETS] + ["^SafeDIGeneratorPluginTests\\."],
        "the library the compile checks build against selects the tool's test targets and the plugin's",
    )
    expect(
        list(filters_of_changes({"Sources/SafeDICore/BUILD.bazel", "TuistPlugins/SafeDITuist/A.swift"}, read))[-1],
        "^SafeDIGeneratorPluginTests\\.",
        "a source directory's other files and the Tuist plugin select the plugin's tests",
    )
    expect(
        list(filters_of_changes({"Documentation/Manual.md"}, read)),
        [f"^{target}\\." for target in TOOL_TEST_TARGETS],
        "the manual selects the targets whose tests read it",
    )
    unselected = []
    expect(list(filters_of_changes({"README.md", ".claude/rules/seams.md"}, read, unselected)), [], "no filter")
    expect(unselected, [".claude/rules/seams.md", "README.md"], "a path that reaches no test is reported")
    expect(tests_run(["✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.\n", "Executed 0 tests, with 0 failures\n"]), 0, "no test ran")
    expect(tests_run(["✔ Test run with 12 tests in 2 suites passed after 1 seconds.\n"]), 12, "tests ran")
    checkout = pathlib.Path("/checkout")
    expect(
        temporary_directory_parent("/tmp", checkout, ["/tmp"]),
        caches_directory() / "swiftpm",
        "an inherited TMPDIR in the system temporary directory is not used",
    )
    safe = pathlib.Path.home()
    expect(temporary_directory_parent(str(safe), checkout, ["/tmp"]), safe.resolve(), "a safe inherited TMPDIR is kept")
    check_against_checkout(expect)
    for path in ("Tests/SafeDIToolTestSupport/Helper.swift", "Package.swift", "Sources/NewTarget/A.swift", "New/File.txt"):
        try:
            filters_of_changes({path}, read)
        except WholeSuite as reason:
            expect(str(reason), path, "the whole suite names the path that reaches it")
        else:
            expect(None, path, "a helper, the manifest, an unlisted source directory or a path no rule matches runs the whole suite")
    failures, summary = failures_of_output(
        [
            "✔ Test a() passed after 0.1 seconds.\n",
            "✘ Test b() recorded an issue at A.swift:3:5: Expectation failed: x == y\n",
            "✘ Test c() recorded a known issue at A.swift:9:5: Issue recorded\n",
            "✘ Test c() passed after 0.1 seconds with 1 known issue.\n",
            "✘ Test b() failed after 0.1 seconds with 1 issue.\n",
            "✘ Suite S failed after 0.1 seconds with 1 issue.\n",
            "/x/A.swift:1:1: error: cannot find 'q' in scope\n",
            "✘ Test run with 3 tests in 1 suite failed after 0.2 seconds with 1 issue.\n",
        ]
    )
    expect(
        failures,
        [
            "✘ Test b() recorded an issue at A.swift:3:5: Expectation failed: x == y",
            "✘ Test b() failed after 0.1 seconds with 1 issue.",
            "/x/A.swift:1:1: error: cannot find 'q' in scope",
        ],
        "failures keep issues, failed tests and compiler errors, and drop known issues, suites and the summary",
    )
    expect(summary, "✘ Test run with 3 tests in 1 suite failed after 0.2 seconds with 1 issue.", "the summary line")
    print("verify-touched: self-test passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("base", nargs="?", default="origin/main")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--skip-compile-checks", action="store_true")
    parser.add_argument("--also", action="append", default=[], metavar="FILTER")
    parser.add_argument("--whole-suite", action="store_true")
    parser.add_argument("--log", metavar="FILE")
    parser.add_argument("--runner", metavar="COMMAND", default=os.environ.get("SAFEDI_VERIFY_RUNNER", ""))
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    else:
        return run(arguments)


if __name__ == "__main__":
    sys.exit(main())
