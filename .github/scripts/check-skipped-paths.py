#!/usr/bin/env python3
"""Fails when something the build and test jobs run reads a path "Detect Changed Files" lets them skip.

`ci.yml`'s classifier leaves a change under `.claude/` out of `source`, so the build and test jobs skip a pull
request that changes nothing else. That is sound only while nothing those jobs build, test or run reads a file
there. This check fails on:

- a line of `ci.yml`, outside comments, that names `.claude/` in any job other than the classifier
  (`changes`) and the job that always runs the skill scripts' self-tests (`skill-self-tests`);
- a line of Swift under `Sources/`, `Plugins/` or `Tests/`, or of `Package.swift`, that names `.claude/` outside
  a comment.

Usage: python3 .github/scripts/check-skipped-paths.py            (from the checkout's root)
       python3 .github/scripts/check-skipped-paths.py --self-test
"""

import re
import subprocess
import sys

SKIPPED_PREFIX = ".claude/"
JOBS_THAT_MAY_NAME_IT = {"changes", "skill-self-tests"}
JOB_HEADER = re.compile(r"^  ([A-Za-z0-9_-]+):\s*$")


def workflow_problems(text: str, name: str) -> list[str]:
    problems = []
    job = None
    in_jobs = False
    for number, line in enumerate(text.splitlines(), start=1):
        if line.startswith("jobs:"):
            in_jobs = True
            continue
        if not in_jobs:
            continue
        header = JOB_HEADER.match(line)
        if header:
            job = header.group(1)
            continue
        if line.lstrip().startswith("#") or SKIPPED_PREFIX not in line:
            continue
        if job not in JOBS_THAT_MAY_NAME_IT:
            problems.append(f"{name}:{number}: job `{job}` names {SKIPPED_PREFIX}, which it skips changes to")
    return problems


def swift_problems(text: str, name: str) -> list[str]:
    problems = []
    for number, line in enumerate(text.splitlines(), start=1):
        code = line.split("//", 1)[0]
        if SKIPPED_PREFIX in code:
            problems.append(f"{name}:{number}: Swift code names {SKIPPED_PREFIX}, which the build and test jobs skip changes to")
    return problems


def self_test() -> int:
    workflow = "\n".join([
        "name: CI",
        "jobs:",
        "  changes:",
        "    steps:",
        "      - run: case x in .claude/*) ;; esac",
        "  skill-self-tests:",
        "    steps:",
        "      - run: python3 .claude/skills/a/a.py --self-test",
        "  linux:",
        "    steps:",
        "      # a comment about .claude/rules/ci.md",
        "      - run: swift test",
    ])
    assert workflow_problems(workflow, "ci.yml") == [], workflow_problems(workflow, "ci.yml")
    reading = workflow + "\n      - run: python3 .claude/skills/a/a.py\n"
    assert workflow_problems(reading, "ci.yml") == ["ci.yml:13: job `linux` names .claude/, which it skips changes to"], workflow_problems(reading, "ci.yml")
    assert swift_problems("let a = 1 // see .claude/rules/a.md\n/// `.claude/rules/b.md`\n", "A.swift") == []
    assert len(swift_problems('let path = ".claude/settings.json"\n', "A.swift")) == 1
    print("self-test passed")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    problems = workflow_problems(open(".github/workflows/ci.yml", encoding="utf-8").read(), ".github/workflows/ci.yml")
    tracked = subprocess.run(
        ["git", "ls-files", "-z", "--", "Package.swift", "Sources", "Plugins", "Tests"],
        check=True, capture_output=True, text=True,
    ).stdout.split("\0")
    for path in tracked:
        if path.endswith(".swift"):
            problems += swift_problems(open(path, encoding="utf-8").read(), path)
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        print(f"A change under {SKIPPED_PREFIX} skips the build and test jobs, so nothing they run may read a file there. "
              "Move the reader to the job that always runs, or count the path as source in \"Detect Changed Files\".")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
