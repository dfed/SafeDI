"""usage: combine-base-comparison-reports.py REPORTS-DIRECTORY
       combine-base-comparison-reports.py --self-test

Judges the base comparison across the reports of ci.yml's fuzzer shards, each
in a folder of its own under REPORTS-DIRECTORY, and prints a Markdown summary.
Each shard whose pull request's base tool built runs
SafeDIToolBaseComparisonTests/longRun, which writes base-comparison.txt beside
the fuzzer's report:

    base-comparison corpus=<corpus> seeds=<first>..<<end>
    difference <seed> <flow> <first difference> (<n> in all)
        <a further difference>         (up to nine)
    problem <seed> <text>             (a graph the comparison could not judge)
    summary compared=<n> differing=<n> problems=<n> plugin=<n> module-info=<n> files=<n>
    cpu wall=<seconds>
    completed <seeds>

The environment says what the run expects:

    BASE_TOOL_RESULT   the result of "Build the Base SafeDITool on Linux":
                       success, failure, cancelled, or skipped (no base, as on
                       a push to main, where nothing is compared)
    PULL_REQUEST_BODY  the pull request's description

A pull request whose description holds the line `Generated output: unchanged`
says it changes nothing SafeDI generates. For it, the check fails on any
difference, any graph the comparison could not judge, a shard without a
complete report, or a base tool that did not build. For any other pull
request, which may change output on purpose, the summary lists what differs
and the check passes. Exits non-zero only on a failure.
"""

import os
import re
import sys

OPT_IN = re.compile(r"^[ \t]*Generated output: unchanged[ \t]*\r?$", re.MULTILINE)
REPORT_NAME = "base-comparison.txt"
LISTED_LIMIT = 30


def says_unchanged(body):
    """Whether a pull request's description opts into the failing comparison."""
    return OPT_IN.search(body or "") is not None


def read_reports(reports_directory):
    """Each shard folder's report lines, or None for a folder without one."""
    reports = {}
    for name in sorted(os.listdir(reports_directory)):
        folder = os.path.join(reports_directory, name)
        if not os.path.isdir(folder):
            continue
        path = os.path.join(folder, REPORT_NAME)
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as report:
                reports[name] = report.read().splitlines()
        else:
            reports[name] = None
    return reports


def combine(reports, base_tool_result, unchanged):
    """The summary's lines and whether the check fails."""
    lines = ["## Generated output compared with the base", ""]
    if base_tool_result == "skipped":
        lines.append("No base to compare with: the run is not a pull request's, or it changes only Markdown.")
        return lines, False
    expectation = (
        "The pull request says `Generated output: unchanged`, so any difference fails this check."
        if unchanged
        else "The pull request does not say `Generated output: unchanged`, so differences are listed and fail nothing."
    )
    lines += [expectation, ""]
    failures = []
    if base_tool_result != "success":
        failures.append(f"The base tool did not build (result: {base_tool_result}), so nothing was compared.")
    totals = {"compared": 0, "differing": 0, "problems": 0, "plugin": 0, "module-info": 0, "files": 0}
    differences = []
    problems = []
    if base_tool_result == "success":
        if not reports:
            failures.append("No shard uploaded a report.")
        for shard, report in reports.items():
            if report is None:
                failures.append(f"Shard {shard} wrote no base comparison report.")
                continue
            if not any(line.startswith("completed ") for line in report):
                failures.append(f"Shard {shard}'s base comparison report does not complete.")
            corpus = next((line.split()[1] for line in report if line.startswith("base-comparison ")), "corpus=?")
            corpus = corpus.removeprefix("corpus=")
            for line in report:
                if line.startswith("summary "):
                    for field in line.split()[1:]:
                        key, _, value = field.partition("=")
                        if key in totals and value.isdigit():
                            totals[key] += int(value)
                elif line.startswith("difference "):
                    differences.append(f"{corpus} {line.removeprefix('difference ')}")
                elif line.startswith("problem "):
                    problems.append(f"{corpus} {line.removeprefix('problem ')}")
    lines.append(
        f"Graphs compared: {totals['compared']} ({totals['plugin']} as the SwiftPM plugin runs the tool, "
        f"{totals['module-info']} per module as Bazel runs it), files compared: {totals['files']}, "
        f"graphs that differ: {totals['differing']}, graphs not judged: {totals['problems']}."
    )
    for title, entries in (("Graphs that differ (corpus, seed, flow, first difference)", differences), ("Graphs not judged", problems)):
        if entries:
            lines += ["", f"### {title}", ""]
            lines += [f"- `{entry}`" for entry in entries[:LISTED_LIMIT]]
            if len(entries) > LISTED_LIMIT:
                lines.append(f"- … and {len(entries) - LISTED_LIMIT} more, in the shards' `{REPORT_NAME}`.")
    if failures:
        lines += ["", "### What kept the comparison from completing", ""]
        lines += [f"- {failure}" for failure in failures]
    fails = unchanged and bool(failures or differences or problems)
    return lines, fails


def self_test():
    import tempfile

    assert says_unchanged("Some text.\n\nGenerated output: unchanged\n")
    assert says_unchanged("Generated output: unchanged\r\n")
    assert not says_unchanged("Generated output: changed\n")
    assert not says_unchanged("We claim the Generated output: unchanged in passing.")
    assert not says_unchanged(None)
    with tempfile.TemporaryDirectory() as directory:
        clean = os.path.join(directory, "graph-fuzzer-report-base-0")
        differing = os.path.join(directory, "graph-fuzzer-report-base-1250")
        missing = os.path.join(directory, "graph-fuzzer-report-base-2500")
        for folder in (clean, differing, missing):
            os.makedirs(folder)
        with open(os.path.join(clean, REPORT_NAME), "w") as report:
            report.write("base-comparison corpus=base seeds=0..<1250\nsummary compared=1250 differing=0 problems=0 plugin=1250 module-info=0 files=5000\ncompleted 1250\n")
        with open(os.path.join(differing, REPORT_NAME), "w") as report:
            report.write("base-comparison corpus=base seeds=1250..<2500\ndifference 1300 plugin file Output/A.swift: line 2: base `a`, head `b` (1 in all)\nsummary compared=1250 differing=1 problems=0 plugin=1250 module-info=0 files=5000\ncompleted 1250\n")
        reports = read_reports(directory)
        _, fails = combine({k: v for k, v in reports.items() if k.endswith("-0")}, "success", True)
        assert not fails, "a clean shard fails an unchanged pull request"
        lines, fails = combine({k: v for k, v in reports.items() if not k.endswith("-2500")}, "success", True)
        assert fails, "a difference passes an unchanged pull request"
        assert any("base 1300 plugin" in line for line in lines), lines
        _, fails = combine({k: v for k, v in reports.items() if not k.endswith("-2500")}, "success", False)
        assert not fails, "a difference fails a pull request that may change output"
        _, fails = combine(reports, "success", True)
        assert fails, "a shard without a report passes an unchanged pull request"
        _, fails = combine({}, "failure", True)
        assert fails, "a base that did not build passes an unchanged pull request"
        _, fails = combine({}, "failure", False)
        assert not fails, "a base that did not build fails a pull request that may change output"
        _, fails = combine({}, "skipped", True)
        assert not fails, "a run without a base fails"
    print("self-test passed")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    reports_directory = sys.argv[1]
    reports = read_reports(reports_directory) if os.path.isdir(reports_directory) else {}
    lines, fails = combine(reports, os.environ.get("BASE_TOOL_RESULT", "skipped"), says_unchanged(os.environ.get("PULL_REQUEST_BODY", "")))
    print("\n".join(lines))
    if fails:
        print("::error::The pull request says `Generated output: unchanged`, but the base comparison did not show that.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
