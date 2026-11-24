#!/usr/bin/env python3
"""Names the Swift Testing tests a run started and never finished.

    Scripts/unfinished-tests.py LOG…       a saved log of a test step, or `-` for standard input
    Scripts/unfinished-tests.py --self-test

No test has a time limit of its own: a test's limit also counts the time it waits for a thread behind the rest of
the suite, so on a loaded runner it fails a test that did a fraction of a second of work. A test that never ends is
stopped by its job's step limit instead (or by whoever interrupts a local run), and the log then ends without a
verdict for it. This reads that log: a test is unfinished when it has more "started" lines than "passed", "failed"
or "skipped" lines. Tests run in parallel, so every test still running when the run was stopped is listed; with one
hung test the rest have long finished and it is listed alone.

Prints one name per line and exits 1 when a test is unfinished, 0 when every started test finished, and 2 when the
log holds no test's "started" line, as when it is not a test step's log.
"""

import collections
import re
import sys

# A Swift Testing line opens with a symbol that differs by platform and terminal, then one or more spaces. A log
# GitHub saved has a timestamp before that, and a terminal's log has color codes. "Test run started." and "Test run
# with 5 tests passed after" are the run's own lines, not a test's.
TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z ")
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
STARTED = re.compile(r"^(?:\S+\s+)?Test (?!run )(.+) started\.$")
FINISHED = re.compile(r"^(?:\S+\s+)?Test (?!run )(.+?) (?:passed after |failed after |skipped(?:\.|:| ))")


def unfinished_tests(lines):
    """The tests with more "started" lines than verdicts, in the order they started, and how many tests started.
    Two suites' tests of one name are told apart only by count, which is enough to say one of them is unfinished."""
    running = collections.Counter()
    order = []
    started = 0
    for line in lines:
        line = ANSI_ESCAPE.sub("", TIMESTAMP.sub("", line.rstrip("\n"))).strip()
        match = STARTED.match(line)
        if match:
            started += 1
            running[match.group(1)] += 1
            order.append(match.group(1))
        else:
            match = FINISHED.match(line)
            if match and running[match.group(1)] > 0:
                running[match.group(1)] -= 1
    names = []
    for name in order:
        if running[name] > 0:
            running[name] -= 1
            names.append(name)
    return names, started


def self_test():
    failures = []

    def expect(what, actual, expected):
        if actual != expected:
            failures.append(f"{what}: expected {expected!r}, got {actual!r}")

    log = [
        "2026-11-23T20:13:01.1234567Z ◇ Test run started.",
        "2026-11-23T20:13:01.1234567Z ◇ Suite ATests started.",
        "2026-11-23T20:13:01.1234567Z ◇ Test quick() started.",
        "2026-11-23T20:13:01.1234567Z ◇ Test hung() started.",
        "2026-11-23T20:13:01.1234567Z ◇ Test broken() started.",
        "2026-11-23T20:13:01.1234567Z ◇ Test \"a display name\" started.",
        "2026-11-23T20:13:01.1234567Z ◇ Test same() started.",
        "2026-11-23T20:13:01.1234567Z ◇ Test same() started.",
        "2026-11-23T20:13:01.1234567Z ➜ Test unavailable() skipped.",
        "2026-11-23T20:13:01.2234567Z ✔ Test quick() passed after 0.001 seconds.",
        "2026-11-23T20:13:01.2234567Z ✘ Test broken() recorded an issue at A.swift:3:5: Expectation failed",
        "2026-11-23T20:13:01.2234567Z ✘ Test broken() failed after 0.1 seconds with 1 issue.",
        "2026-11-23T20:13:01.2234567Z ✔ Test \"a display name\" passed after 0.001 seconds.",
        "2026-11-23T20:13:01.2234567Z ✔ Test same() passed after 0.001 seconds.",
        "##[error]The action 'Test' has timed out after 70 minutes.",
    ]
    expect("a hung test and one of two tests of one name, of a log GitHub saved", unfinished_tests(log), (["hung()", "same()"], 6))
    expect(
        "the symbol and spacing of another platform, and a terminal's colors",
        unfinished_tests(["\U00100884  Test first() started.", "\x1b[32m\U00100884\x1b[0m  Test second() started.", "\U00100884  Test first() passed after 0.5 seconds."]),
        (["second()"], 2),
    )
    expect("a run that finished", unfinished_tests(log[:3] + [log[9], "✔ Test run with 1 test passed after 0.1 seconds."]), ([], 1))
    expect("a log of something else", unfinished_tests(["Compiling SafeDICore", "Build complete!"]), ([], 0))
    for failure in failures:
        print(failure, file=sys.stderr)
    print("self-test failed" if failures else "self-test passed")
    return 1 if failures else 0


def main(arguments):
    if arguments == ["--self-test"]:
        return self_test()
    if not arguments or any(argument.startswith("--") for argument in arguments):
        print(__doc__, file=sys.stderr)
        return 2
    lines = []
    for path in arguments:
        if path == "-":
            lines += sys.stdin.readlines()
        else:
            with open(path, errors="replace") as log:
                lines += log.readlines()
    names, started = unfinished_tests(lines)
    if started == 0:
        print("no test's \"started\" line in the log, so it is not the log of a Swift Testing run", file=sys.stderr)
        return 2
    for name in names:
        print(name)
    print(f"{len(names)} of {started} started tests did not finish", file=sys.stderr)
    return 1 if names else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
