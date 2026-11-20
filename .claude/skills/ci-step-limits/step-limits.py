#!/usr/bin/env python3
"""Usage: step-limits.py [--check] [--workflows DIRECTORY] RUN…
       step-limits.py --self-test

Compares every `timeout-minutes` in the workflows of this checkout with how long that step, or that job, took in the
given runs, and prints for each the limit, how many times it was measured, the longest and median time, and the limit
the rule asks for: twice the longest, rounded up to a minute. Run it from the root of a checkout of the commit the
runs built, so that the steps it reads are the steps that ran.

Each RUN is a run id, read with `gh run view RUN --json databaseId,jobs`, or the path of a file holding that
command's output or the output of the REST API's `actions/runs/RUN/jobs` (bare, or under a `jobs` key of its own).
Only a step that succeeded is measured: a failed or cancelled step stopped early, so its time says nothing about how
long the step takes. A step that ran out of its limit is listed on its own, because it is the evidence that the limit
is too short.

A limit is reported as
- `short` when it is under one and a half times the longest measured time: one slow runner away from failing a job
  whose code is fine;
- `long` when it is over three times the longest, and more than five minutes over twice the longest;
- `ok` otherwise, and `unmeasured` when no given run ran the step to success.
For each short limit the report ends with the limit and comment the step should carry: the measurement and the run
it came from. A long limit's row already gives the rule's figure.

With --check, exits 1 when any limit is short or any step ran out of its limit. A step that downloads (a package
resolve, a tool install) keeps a limit sized for a slow network, so a `long` verdict is for a person to judge and
never fails the check.

A job matches a run's job by name, with each `${{ … }}` in the workflow's name standing for any text, and with or
without the calling job's name that GitHub puts before a reusable workflow's jobs. A matrix job's legs are measured
together, since they share one limit.

--self-test checks the workflow reader, the matching and each verdict against fixtures in a temporary directory.
"""
import datetime
import json
import math
import os
import re
import statistics
import subprocess
import sys
import tempfile

SHORT_BELOW_LONGEST_TIMES = 1.5
LONG_ABOVE_LONGEST_TIMES = 3
LONG_ONLY_WHEN_OVER_RULE_BY_MINUTES = 5
EXPRESSION = re.compile(r"\$\{\{.*?\}\}")


class Limit:
    """One `timeout-minutes` of a workflow: a step's when `step` is a name, its job's when `step` is None."""

    def __init__(self, workflow, line, job, step, minutes):
        self.workflow = workflow
        self.line = line
        self.job = job
        self.step = step
        self.minutes = minutes
        # (minutes, run) of each successful execution.
        self.measurements = []
        # (job name, run) of each execution that ran out of the limit.
        self.exhausted = []

    @property
    def description(self):
        if self.step is None:
            return f"{self.job} (the whole job)"
        else:
            return f"{self.job} › {self.step}"


def unquoted(value):
    value = value.strip()
    # A YAML anchor before the value names it for a stand-in job; the name itself follows.
    value = re.sub(r"^&\S+\s+", "", value)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        value = value[1:-1]
    return value


def limits_of_workflow(path):
    """The limits a workflow file declares. Reads the layout GitHub's workflows share, by indentation: a job's key at
    two spaces under `jobs:`, its `name:` and `timeout-minutes:` at four, a step's `- name:` at six and the step's
    other keys at eight."""
    limits = []
    in_jobs = False
    job_key = None
    job_name = None
    step_name = None
    pending_step_limit = None
    with open(path, encoding="utf-8") as workflow_file:
        lines = workflow_file.read().split("\n")

    def close_step():
        nonlocal step_name, pending_step_limit
        if pending_step_limit is not None:
            line, minutes = pending_step_limit
            limits.append(Limit(os.path.basename(path), line, job_name or job_key, step_name, minutes))
        step_name = None
        pending_step_limit = None

    job_limit_index_by_key = {}
    for number, text in enumerate(lines, start=1):
        if re.match(r"^\S", text):
            close_step()
            in_jobs = text.startswith("jobs:")
            job_key = None
            continue
        if not in_jobs:
            continue
        job_match = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", text)
        if job_match:
            close_step()
            job_key = job_match.group(1)
            job_name = None
            continue
        if job_key is None:
            continue
        name_match = re.match(r"^    name:\s*(.+)$", text)
        if name_match:
            job_name = unquoted(name_match.group(1))
            if job_key in job_limit_index_by_key:
                limits[job_limit_index_by_key[job_key]].job = job_name
            continue
        job_limit_match = re.match(r"^    timeout-minutes:\s*(\d+)\s*(#.*)?$", text)
        if job_limit_match:
            job_limit_index_by_key[job_key] = len(limits)
            limits.append(Limit(os.path.basename(path), number, job_name or job_key, None, int(job_limit_match.group(1))))
            continue
        step_match = re.match(r"^      - (?:name:\s*(.+))?", text)
        if step_match:
            close_step()
            if step_match.group(1) is not None:
                step_name = unquoted(step_match.group(1))
            continue
        step_name_match = re.match(r"^        name:\s*(.+)$", text)
        if step_name_match:
            step_name = unquoted(step_name_match.group(1))
            continue
        step_limit_match = re.match(r"^        timeout-minutes:\s*(\d+)\s*(#.*)?$", text)
        if step_limit_match:
            pending_step_limit = (number, int(step_limit_match.group(1)))
    close_step()
    return limits


def pattern_of(name, reusable_prefix):
    """A pattern for the names GitHub reports for a workflow's `name`: each expression stands for any text."""
    parts = [re.escape(part) for part in EXPRESSION.split(name)]
    prefix = r"(?:.* / )?" if reusable_prefix else ""
    return re.compile("^" + prefix + ".*".join(parts) + "$")


def moment(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))


def minutes_between(started, completed):
    if not started or not completed:
        return None
    else:
        return (moment(completed) - moment(started)).total_seconds() / 60


def field(record, snake_case, camel_case):
    """A field the REST API spells one way and `gh run view --json` another."""
    if snake_case in record:
        return record[snake_case]
    else:
        return record.get(camel_case)


def jobs_of_run(argument):
    """(run label, jobs) for a run id or a file of a run's jobs."""
    if os.path.exists(argument):
        with open(argument, encoding="utf-8") as jobs_file:
            document = json.load(jobs_file)
        label = str(document.get("databaseId") or os.path.basename(argument))
    elif argument.isdigit():
        output = subprocess.run(
            ["gh", "run", "view", argument, "--json", "databaseId,jobs"], check=True, capture_output=True, text=True
        ).stdout
        document = json.loads(output)
        label = argument
    else:
        raise SystemExit(f"{argument} is neither a run id nor a file.")
    jobs = document["jobs"]
    if isinstance(jobs, dict):
        # A tool that wraps the REST API's response under a `jobs` key of its own.
        jobs = jobs["jobs"]
    for job in jobs:
        run_id = job.get("run_id")
        if run_id is not None:
            label = str(run_id)
    return label, jobs


def record(limits, label, jobs):
    for limit in limits:
        job_pattern = pattern_of(limit.job, reusable_prefix=True)
        step_pattern = None if limit.step is None else pattern_of(limit.step, reusable_prefix=False)
        for job in jobs:
            if not job_pattern.match(job["name"]):
                continue
            if limit.step is None:
                executions = [job]
            else:
                executions = [step for step in job.get("steps") or [] if step_pattern.match(step["name"])]
            for execution in executions:
                minutes = minutes_between(
                    field(execution, "started_at", "startedAt"), field(execution, "completed_at", "completedAt")
                )
                conclusion = execution.get("conclusion")
                if minutes is None:
                    continue
                if conclusion == "success":
                    limit.measurements.append((minutes, label))
                elif conclusion in ("failure", "cancelled", "timed_out") and minutes >= limit.minutes:
                    limit.exhausted.append((job["name"], label))


def rule_minutes(longest):
    return max(1, math.ceil(2 * longest))


def verdict(limit):
    if not limit.measurements:
        return "unmeasured"
    longest = max(minutes for minutes, _ in limit.measurements)
    if limit.minutes < SHORT_BELOW_LONGEST_TIMES * longest:
        return "short"
    elif (
        limit.minutes > LONG_ABOVE_LONGEST_TIMES * longest
        and limit.minutes - rule_minutes(longest) > LONG_ONLY_WHEN_OVER_RULE_BY_MINUTES
    ):
        return "long"
    else:
        return "ok"


def report(limits, run_count, out):
    """Writes the report and returns whether --check fails."""
    rows = []
    comments = []
    exhausted = []
    for limit in limits:
        outcome = verdict(limit)
        where = f"{limit.workflow}:{limit.line}"
        if limit.measurements:
            longest, longest_run = max(limit.measurements)
            median = statistics.median(minutes for minutes, _ in limit.measurements)
            rows.append(
                (outcome, where, str(limit.minutes), str(len(limit.measurements)), f"{longest:.1f}", f"{median:.1f}",
                 str(rule_minutes(longest)), limit.description)
            )
            if outcome == "short":
                count = len(limit.measurements)
                comments.append(
                    f"{where} {limit.description}\n"
                    f"    timeout-minutes: {rule_minutes(longest)}\n"
                    f"    # Twice the longest of {count} measured, {longest:.1f} minutes "
                    f"(run {longest_run}; the median was {median:.1f})."
                )
        else:
            rows.append((outcome, where, str(limit.minutes), "0", "", "", "", limit.description))
        for job_name, label in limit.exhausted:
            exhausted.append(f"{where} {limit.description} ran out of its {limit.minutes} minutes in run {label} ({job_name})")
    header = ("verdict", "where", "limit", "measured", "longest", "median", "rule", "step")
    widths = [max(len(row[column]) for row in [header] + rows) for column in range(len(header) - 1)]
    for row in [header] + rows:
        cells = [row[column].ljust(widths[column]) for column in range(len(header) - 1)]
        print("  ".join(cells + [row[-1]]), file=out)
    counts = {name: sum(1 for row in rows if row[0] == name) for name in ("short", "long", "ok", "unmeasured")}
    print(
        f"\n{len(rows)} limits over {run_count} run{'' if run_count == 1 else 's'}: {counts['short']} short, "
        f"{counts['long']} long, {counts['ok']} ok, {counts['unmeasured']} unmeasured.",
        file=out,
    )
    if exhausted:
        print("\nRan out of its limit:", file=out)
        for line in exhausted:
            print(line, file=out)
    if comments:
        print("\nWhat the rule asks for:", file=out)
        for comment in comments:
            print(comment, file=out)
    return counts["short"] > 0 or bool(exhausted)


def limits_of_directory(directory):
    limits = []
    for name in sorted(os.listdir(directory)):
        if name.endswith((".yml", ".yaml")):
            limits.extend(limits_of_workflow(os.path.join(directory, name)))
    return limits


SELF_TEST_WORKFLOW = """name: CI
on:
  push:
    branches:
      - main
jobs:
  linux:
    name: Build and Test on Linux
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repo
        uses: actions/checkout@v7
      # Twice the longest.
      - name: Test Framework
        timeout-minutes: 20
        run: swift test
      - name: Resolve Package Dependencies
        timeout-minutes: 15
        run: swift package resolve
      - name: Lint
        timeout-minutes: 4
        run: ./CLI/lint.sh
      - name: Never Runs
        timeout-minutes: 3
        run: true
  repeat:
    timeout-minutes: 40
    name: &repeat-name Repeat Tests on Linux (pass ${{ matrix.pass }})
    strategy:
      matrix:
        pass: [2, 3]
    steps:
      - name: Run pass ${{ matrix.pass }}
        timeout-minutes: 30
        run: swift test
  inner:
    name: 'Fuzz'
    steps:
      - uses: actions/checkout@v7
        name: Checkout
        timeout-minutes: 2
"""


def self_test_step(name, minutes, conclusion="success"):
    started = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
    completed = started + datetime.timedelta(minutes=minutes)
    return {
        "name": name,
        "conclusion": conclusion,
        "started_at": started.isoformat().replace("+00:00", "Z"),
        "completed_at": completed.isoformat().replace("+00:00", "Z"),
    }


def self_test():
    failures = []

    def expect(what, actual, expected):
        if actual != expected:
            failures.append(f"{what}: expected {expected!r}, got {actual!r}")

    with tempfile.TemporaryDirectory() as directory:
        workflows = os.path.join(directory, "workflows")
        os.mkdir(workflows)
        with open(os.path.join(workflows, "ci.yml"), "w", encoding="utf-8") as workflow_file:
            workflow_file.write(SELF_TEST_WORKFLOW)
        rest_run = {
            "jobs": [
                {
                    "name": "Build and Test on Linux",
                    "run_id": 101,
                    "conclusion": "success",
                    "steps": [
                        self_test_step("Checkout Repo", 0.1),
                        self_test_step("Test Framework", 15),
                        self_test_step("Resolve Package Dependencies", 1),
                        self_test_step("Lint", 2),
                    ],
                },
                dict(self_test_step("Repeat Tests on Linux (pass 2)", 12), run_id=101, steps=[self_test_step("Run pass 2", 11)]),
                dict(
                    self_test_step("Repeat Tests on Linux (pass 3)", 31, "failure"),
                    run_id=101,
                    steps=[self_test_step("Run pass 3", 30, "cancelled")],
                ),
                dict(self_test_step("Caller / Fuzz", 3), run_id=101, steps=[self_test_step("Checkout", 0.5)]),
            ]
        }
        command_line_step = {
            "name": "Test Framework",
            "conclusion": "success",
            "startedAt": "2026-01-02T00:00:00Z",
            "completedAt": "2026-01-02T00:09:00Z",
        }
        command_line_run = {
            "databaseId": 102,
            "jobs": [
                {"name": "Build and Test on Linux", "conclusion": "success", "steps": [command_line_step,
                 dict(self_test_step("Lint", 1, "failure"))]},
            ],
        }
        paths = []
        for name, document in (("rest.json", rest_run), ("command-line.json", command_line_run)):
            paths.append(os.path.join(directory, name))
            with open(paths[-1], "w", encoding="utf-8") as jobs_file:
                json.dump(document, jobs_file)

        limits = limits_of_directory(workflows)
        expect(
            "the limits read",
            [(limit.job, limit.step, limit.minutes) for limit in limits],
            [
                ("Build and Test on Linux", "Test Framework", 20),
                ("Build and Test on Linux", "Resolve Package Dependencies", 15),
                ("Build and Test on Linux", "Lint", 4),
                ("Build and Test on Linux", "Never Runs", 3),
                ("Repeat Tests on Linux (pass ${{ matrix.pass }})", None, 40),
                ("Repeat Tests on Linux (pass ${{ matrix.pass }})", "Run pass ${{ matrix.pass }}", 30),
                ("Fuzz", "Checkout", 2),
            ],
        )
        labels = []
        for path in paths:
            label, jobs = jobs_of_run(path)
            labels.append(label)
            record(limits, label, jobs)
        expect("the run labels", labels, ["101", "102"])
        by_step = {(limit.job.split(" (")[0], limit.step): limit for limit in limits}
        test_step = by_step[("Build and Test on Linux", "Test Framework")]
        expect("a step measured in both spellings", sorted(test_step.measurements), [(9.0, "102"), (15.0, "101")])
        expect("a limit under one and a half times the longest", verdict(test_step), "short")
        expect("a download step's limit", verdict(by_step[("Build and Test on Linux", "Resolve Package Dependencies")]), "long")
        lint = by_step[("Build and Test on Linux", "Lint")]
        expect("a failed step is not measured", lint.measurements, [(2.0, "101")])
        expect("a limit of twice the longest", verdict(lint), "ok")
        expect("a step no run ran", verdict(by_step[("Build and Test on Linux", "Never Runs")]), "unmeasured")
        repeat_job = by_step[("Repeat Tests on Linux", None)]
        expect("a matrix job's limit", repeat_job.measurements, [(12.0, "101")])
        expect("a job limit over three times the longest", verdict(repeat_job), "long")
        repeat_step = by_step[("Repeat Tests on Linux", "Run pass ${{ matrix.pass }}")]
        expect("a matrix step", repeat_step.measurements, [(11.0, "101")])
        expect("a step that ran out of its limit", repeat_step.exhausted, [("Repeat Tests on Linux (pass 3)", "101")])
        expect("a reusable workflow's step", by_step[("Fuzz", "Checkout")].measurements, [(0.5, "101")])

        class Lines:
            def __init__(self):
                self.text = ""

            def write(self, text):
                self.text += text

        lines = Lines()
        expect("the check fails", report(limits, 2, lines), True)
        expect(
            "the summary",
            "7 limits over 2 runs: 1 short, 2 long, 3 ok, 1 unmeasured." in lines.text,
            True,
        )
        expect(
            "the comment",
            "    timeout-minutes: 30\n    # Twice the longest of 2 measured, 15.0 minutes (run 101; the median was 12.0)."
            in lines.text,
            True,
        )
        expect(
            "the exhausted line",
            "ran out of its 30 minutes in run 101 (Repeat Tests on Linux (pass 3))" in lines.text,
            True,
        )
        test_step.minutes = 30
        repeat_step.exhausted = []
        expect("the check passes once the limit follows the rule", report(limits, 2, Lines()), False)
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        return 1
    else:
        print("step-limits.py: every self-test expectation holds.")
        return 0


def main(arguments):
    if arguments == ["--self-test"]:
        return self_test()
    check = False
    workflows = os.path.join(".github", "workflows")
    runs = []
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--check":
            check = True
        elif argument == "--workflows" and index + 1 < len(arguments):
            index += 1
            workflows = arguments[index]
        elif argument.startswith("--"):
            print(__doc__, file=sys.stderr)
            return 2
        else:
            runs.append(argument)
        index += 1
    if not runs:
        print(__doc__, file=sys.stderr)
        return 2
    limits = limits_of_directory(workflows)
    for run in runs:
        label, jobs = jobs_of_run(run)
        record(limits, label, jobs)
    fails = report(limits, len(runs), sys.stdout)
    if check and fails:
        return 1
    else:
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
