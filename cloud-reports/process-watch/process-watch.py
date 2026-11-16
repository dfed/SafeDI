#!/usr/bin/env python3
"""Checks a listing of workflow runs against the pacing rules the lead adopted after slice 2.

    process-watch.py RUNS.json [--since 2026-11-16T03:25:00Z]

RUNS.json is the saved result of listing the repository's workflow runs (the GitHub MCP tool's `list_workflow_runs`,
or `gh api repos/OWNER/REPO/actions/runs`). Prints, for the heavy workflows (CI, Verify, Graph Fuzzer):

- each run since `--since` with its branch, how it ended and how long it took;
- rule 1, no overlap: the pairs of pins runs on one line of work (one commit an ancestor of the other) that overlapped, and landings (CI on a push to main) that overlapped a
  pull request's CI or a pins run;
- rule 2, one dispatch: Graph Fuzzer runs dispatched by hand, which `verify -f pins=true` replaces;
- rule 3, a local run first: branches with two or more failed Verify runs.

A run still going counts as running until now.
"""
import datetime, json, sys

HEAVY = {"CI", "Verify", "Graph Fuzzer"}


def same_lineage(first, second):
    """Whether one commit is the other or its ancestor, by the checkout this script is in; None when git cannot say."""
    import pathlib, subprocess
    checkout = pathlib.Path(__file__).resolve().parent
    def git(*arguments):
        return subprocess.run(["git", "-C", str(checkout), *arguments], capture_output=True, text=True).returncode
    if first == second:
        return True
    for commit in (first, second):
        if git("cat-file", "-e", f"{commit}^{{commit}}") != 0 and git("fetch", "-q", "origin", commit) != 0:
            return None
    return git("merge-base", "--is-ancestor", first, second) == 0 or git("merge-base", "--is-ancestor", second, first) == 0


def parse(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))


def main():
    arguments = sys.argv[1:]
    since = parse("1970-01-01T00:00:00Z")
    if "--since" in arguments:
        i = arguments.index("--since"); since = parse(arguments[i + 1]); del arguments[i:i + 2]
    data = json.load(open(arguments[0]))
    runs = data.get("workflow_runs", data) if isinstance(data, dict) else data
    now = datetime.datetime.now(datetime.timezone.utc)
    rows = []
    for run in runs:
        if run["name"] not in HEAVY: continue
        start = parse(run["run_started_at"])
        if start < since: continue
        done = run["status"] == "completed"
        end = parse(run["updated_at"]) if done else now
        rows.append(dict(id=run["id"], name=run["name"], event=run["event"], branch=run["head_branch"], sha=run["head_sha"][:9], full_sha=run["head_sha"], start=start, end=end, result=run.get("conclusion") if done else run["status"], attempt=run.get("run_attempt", 1)))
    rows.sort(key=lambda row: row["start"])
    for row in rows:
        minutes = (row["end"] - row["start"]).total_seconds() / 60
        print(f'{row["start"]:%H:%M} {minutes:5.1f} min  {row["name"]:<12} {row["event"]:<17} {row["result"]:<11} {row["branch"]} {row["sha"]} {row["id"]}')

    def overlap(a, b):
        return (min(a["end"], b["end"]) - max(a["start"], b["start"])).total_seconds() / 60

    print("\nRule 1, no overlap:")
    found = False
    landings = [r for r in rows if r["name"] == "CI" and r["event"] == "push"]
    fuzz = [r for r in rows if r["name"] == "Graph Fuzzer"]
    pull = [r for r in rows if r["name"] == "CI" and r["event"] == "pull_request"]
    for i, a in enumerate(fuzz):
        for b in fuzz[i + 1:]:
            if overlap(a, b) > 2:
                # The lead's ruling of 2026-11-16 11:06Z: one pins run per line of work; two lines may overlap.
                line = same_lineage(a["full_sha"], b["full_sha"])
                if line is None:
                    print(f'  note: pins runs {a["id"]} ({a["branch"]}) and {b["id"]} ({b["branch"]}) overlapped {overlap(a, b):.0f} min; their commits could not be fetched to tell whether they are one line of work')
                elif line:
                    found = True; print(f'  two pins runs on one line of work overlapped {overlap(a, b):.0f} min: {a["id"]} ({a["branch"]}) and {b["id"]} ({b["branch"]})')
    for a in landings:
        for b in pull + fuzz:
            if overlap(a, b) > 5:
                found = True; print(f'  a landing\'s CI {a["id"]} overlapped {b["name"]} {b["id"]} ({b["branch"]}) for {overlap(a, b):.0f} min')
    if not found: print("  held")
    print("Rule 2, one dispatch for tests and pins:")
    # verify.yml with pins=true dispatches Graph Fuzzer itself, on a branch named verify/pins-<commit>-<n>.
    by_hand = [r for r in fuzz if r["event"] == "workflow_dispatch" and not r["branch"].startswith("verify/pins-")]
    for r in by_hand: print(f'  Graph Fuzzer dispatched by hand: {r["id"]} on {r["branch"]} at {r["start"]:%H:%M}')
    if not by_hand: print("  held")
    print("Rule 3, a local run before a full Verify:")
    failed = {}
    for r in rows:
        if r["name"] == "Verify" and r["result"] == "failure": failed.setdefault(r["branch"], []).append(r)
    repeated = {branch: runs for branch, runs in failed.items() if len(runs) >= 2}
    for branch, runs in repeated.items():
        print(f'  {len(runs)} failed Verify runs on {branch}: ' + ", ".join(str(r["id"]) for r in runs))
    # Each dispatch runs on a branch of its own (verify/<commit>-<n>), so repeats show only as early failures:
    # a Verify that fails inside 12 minutes failed in its build or first tests, which a local run shows sooner.
    early = [r for r in rows if r["name"] == "Verify" and r["result"] == "failure" and (r["end"] - r["start"]).total_seconds() < 720]
    for r in early: print(f'  Verify {r["id"]} on {r["sha"]} failed after {(r["end"] - r["start"]).total_seconds() / 60:.0f} min, started {r["start"]:%H:%M}')
    if not repeated and not early: print("  held")
    print("Rule 4, no re-run or dispatch on main without asking the lead:")
    on_main = [r for r in rows if r["branch"] == "main" and (r["attempt"] > 1 or r["event"] == "workflow_dispatch")]
    for r in on_main: print(f'  {r["name"]} {r["id"]} on main: attempt {r["attempt"]}, {r["event"]}, started {r["start"]:%H:%M}')
    if not on_main: print("  held")


main()
