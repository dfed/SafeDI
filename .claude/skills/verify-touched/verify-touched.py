#!/usr/bin/env python3
"""Runs, on this machine, the test suites a branch touches, and prints only what failed.

    verify-touched.py [BASE] [--list] [--skip-compile-checks] [--also FILTER]... [--log FILE]
    verify-touched.py --self-test

BASE is the commit or branch the change is measured from (default `origin/main`); the changed files are those that
differ between its merge base with `HEAD` and the working tree, with untracked files. Run it from the repository root.

Which suites a change touches:

- a changed file of a test target that declares tests: every type it declares or extends at the top level, as
  `Target.Type`;
- a changed file under `Tests/SafeDIToolTestSupport`, `Package.swift` or `Package.resolved`: the whole suite, since
  every `SafeDITool` test goes through the helpers;
- a changed file under `Sources/` or `Plugins/`: the test targets `TARGETS_OF_SOURCES` names for its directory. A
  change to SafeDICore or the tool reaches every `SafeDITool` test target, so name the suites with `--also` and read
  `--list` when that is more than the change needs: the script never narrows a source change by guessing.

`--list` prints the `swift test` filters and runs nothing. `--skip-compile-checks` sets `SAFEDI_SKIP_COMPILE_CHECK`,
for a first pass; without it generated code is compiled as a full Verify compiles it. `--also` adds a filter.

The run's whole output goes to the log (default: a file in the SwiftPM temporary folder's parent). The script prints
each failed test with its recorded issues and the run's last line, and exits with `swift test`'s status; 2 means the
arguments or the checkout were wrong, and 3 that the branch touches no test.
"""

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys

TEST_TARGETS_DIRECTORY = "Tests"
HELPER_TARGET = "SafeDIToolTestSupport"
TOOL_TEST_TARGETS = [
    "SafeDIToolTests",
    "SafeDIToolDependencyTreeTests",
    "SafeDIToolMockTests",
    "SafeDIToolSeamTests",
    "SafeDIToolFuzzerTests",
]
# The test targets that exercise each source directory. A directory missing here runs the whole suite.
TARGETS_OF_SOURCES = {
    "Sources/SafeDI": ["SafeDITests"],
    "Sources/SafeDIMacros": ["SafeDIMacrosTests"],
    "Sources/SafeDICore": ["SafeDICoreTests", "SafeDIMacrosTests"] + TOOL_TEST_TARGETS,
    "Sources/SafeDIToolLibrary": TOOL_TEST_TARGETS,
    "Sources/SafeDITool": TOOL_TEST_TARGETS,
    "Plugins": ["SafeDIGeneratorPluginTests"],
}
WHOLE_SUITE_FILES = {"Package.swift", "Package.resolved"}
TOP_LEVEL_TYPE = re.compile(
    r"^(?:@[^\n]*\n)*?(?:(?:public|internal|private|fileprivate|final|nonisolated)\s+)*"
    r"(?:struct|class|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
DECLARES_TESTS = re.compile(r"@Test\b|@Suite\b|\bfunc\s+test[A-Z0-9_]")


class WholeSuite(Exception):
    """A changed file reaches every test."""


def suites_of_test_file(target, text):
    """The filters of the top-level types a test file declares or extends, or none when it declares no test."""
    if not DECLARES_TESTS.search(text):
        return []
    names = []
    for match in TOP_LEVEL_TYPE.finditer(text):
        if match.group(1) not in names:
            names.append(match.group(1))
    return [f"^{target}\\.{name}[./]" for name in names]


def filters_of_changes(changed_paths, read_text):
    """The `swift test` filters of the changed paths, in a stable order, and why each is there.

    Raises `WholeSuite` when a path reaches every test. `read_text` returns a path's text, or None when the path no
    longer exists.
    """
    filters = {}

    def add(pattern, reason):
        filters.setdefault(pattern, reason)

    for path in sorted(changed_paths):
        parts = pathlib.PurePosixPath(path).parts
        if path in WHOLE_SUITE_FILES:
            raise WholeSuite(path)
        if parts[0] == TEST_TARGETS_DIRECTORY and len(parts) >= 3 and path.endswith(".swift"):
            target = parts[1]
            if target == HELPER_TARGET:
                raise WholeSuite(path)
            text = read_text(path)
            if text is None:
                # A deleted test file: its target's other tests are what can still tell.
                add(f"^{target}\\.", f"{path} was deleted")
            else:
                for pattern in suites_of_test_file(target, text):
                    add(pattern, path)
        elif parts[0] in ("Sources", "Plugins") and path.endswith(".swift"):
            directory = "Plugins" if parts[0] == "Plugins" else "/".join(parts[:2])
            targets = TARGETS_OF_SOURCES.get(directory)
            if targets is None:
                raise WholeSuite(path)
            for target in targets:
                add(f"^{target}\\.", f"{directory} changed")
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
    changed = set(git("diff", "--name-only", merge_base).split("\n"))
    changed |= set(git("ls-files", "--others", "--exclude-standard").split("\n"))
    changed.discard("")
    return changed


def read_text_in_checkout(path):
    file = pathlib.Path(path)
    if file.is_file():
        return file.read_text(encoding="utf-8")
    else:
        return None


def swiftpm_temporary_directory():
    """A folder outside the system temporary directory and the checkout, as CLAUDE.md asks of every `swift` command."""
    caches = pathlib.Path.home() / ("Library/Caches" if sys.platform == "darwin" else ".cache")
    return caches / "SafeDITests" / "swiftpm"


def run(arguments):
    try:
        changed = changed_paths_since(arguments.base)
    except subprocess.CalledProcessError as error:
        print(f"verify-touched: {error.stderr.strip()}", file=sys.stderr)
        return 2
    whole_suite_reason = None
    filters = {}
    try:
        filters = filters_of_changes(changed, read_text_in_checkout)
    except WholeSuite as reason:
        whole_suite_reason = str(reason)
    for pattern in arguments.also:
        filters.setdefault(pattern, "--also")

    command = ["swift", "test", "--traits", "sourceBuild"]
    if whole_suite_reason is not None:
        print(f"The whole suite: {whole_suite_reason} reaches every test.")
    elif not filters:
        print(f"Nothing under Tests/, Sources/ or Plugins/ differs from {arguments.base}: no test to run.")
        return 3
    else:
        for pattern, reason in filters.items():
            print(f"--filter '{pattern}'   # {reason}")
            command += ["--filter", pattern]
    if arguments.list:
        return 0

    temporary_directory = swiftpm_temporary_directory()
    temporary_directory.mkdir(parents=True, exist_ok=True)
    log = pathlib.Path(arguments.log) if arguments.log else temporary_directory.parent / "verify-touched.log"
    environment = dict(os.environ, TMPDIR=str(temporary_directory))
    if arguments.skip_compile_checks:
        environment["SAFEDI_SKIP_COMPILE_CHECK"] = "1"
    print(f"Running; the whole output goes to {log}", flush=True)
    with log.open("w", encoding="utf-8") as output:
        status = subprocess.run(command, env=environment, stdout=output, stderr=subprocess.STDOUT).returncode
    # Emptied, not removed: a later `swift` command with this `TMPDIR` fails when the folder is gone.
    shutil.rmtree(temporary_directory, ignore_errors=True)
    temporary_directory.mkdir(parents=True, exist_ok=True)
    with log.open(encoding="utf-8", errors="replace") as output:
        failures, summary = failures_of_output(output)
    for line in failures:
        print(line)
    print(summary if summary else f"No test ran; read {log}.")
    return status


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
        [],
        "a file that declares no test selects nothing",
    )
    expect(
        list(filters_of_changes({"Tests/SafeDIMacrosTests/MacroTests.swift", "Sources/SafeDIMacros/A.swift"}, read)),
        ["^SafeDIMacrosTests\\."],
        "a source change selects its target's tests, which cover a changed suite of that target",
    )
    expect(
        list(filters_of_changes({"Tests/SafeDIToolSeamTests/Gone.swift"}, read)),
        ["^SafeDIToolSeamTests\\."],
        "a deleted test file selects its target",
    )
    expect(
        list(filters_of_changes({"Sources/SafeDIToolLibrary/A.swift", "README.md"}, read)),
        [f"^{target}\\." for target in TOOL_TEST_TARGETS],
        "a tool change selects the tool's five test targets and Markdown nothing",
    )
    for path in ("Tests/SafeDIToolTestSupport/Helper.swift", "Package.swift", "Sources/NewTarget/A.swift"):
        try:
            filters_of_changes({path}, read)
        except WholeSuite as reason:
            expect(str(reason), path, "the whole suite names the path that reaches it")
        else:
            expect(None, path, "a helper, the manifest or an unlisted source directory runs the whole suite")
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
    parser.add_argument("--log", metavar="FILE")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    else:
        return run(arguments)


if __name__ == "__main__":
    sys.exit(main())
