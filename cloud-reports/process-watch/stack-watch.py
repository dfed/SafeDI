#!/usr/bin/env python3
"""Checks the one-stack rules from the open pull requests and the workflow runs.

usage: stack-watch.py PULL_REQUESTS.json RUNS.json REPOSITORY

PULL_REQUESTS.json is the saved result of listing the open pull requests (number, draft, head, base);
RUNS.json the saved result of listing workflow runs; REPOSITORY a clone, which this script fetches.

Rule A, no lane on a stale parent: each pull request's head contains the current head of its base branch.
Rule B, macOS only on the top: no pull request CI run is queued or in progress for a pull request that
another open pull request is based on.
"""
import json
import subprocess
import sys


def git(repository, *arguments):
    return subprocess.run(["git", "-C", repository, *arguments], capture_output=True, text=True)


def main():
    pull_requests = json.load(open(sys.argv[1]))
    runs = json.load(open(sys.argv[2]))
    runs = runs.get("workflow_runs", runs) if isinstance(runs, dict) else runs
    repository = sys.argv[3]
    git(repository, "fetch", "--quiet", "origin", "+refs/heads/*:refs/remotes/origin/*")

    by_head = {pull_request["head"]["ref"]: pull_request for pull_request in pull_requests}
    bases = {pull_request["base"]["ref"] for pull_request in pull_requests}
    # Bottom to top: a pull request's depth is how many open pull requests lie under it.
    def depth(pull_request):
        count = 0
        while pull_request["base"]["ref"] in by_head and count < 100:
            pull_request = by_head[pull_request["base"]["ref"]]
            count += 1
        return count

    print("Open pull requests, bottom to top:")
    for pull_request in sorted(pull_requests, key=lambda p: (depth(p), p["number"])):
        top = "" if pull_request["head"]["ref"] in bases else "  (a top)"
        draft = " draft" if pull_request["draft"] else ""
        print(f"  {'  ' * depth(pull_request)}#{pull_request['number']}{draft} {pull_request['head']['ref']} {pull_request['head']['sha'][:9]} on {pull_request['base']['ref']}{top}")

    print("\nRule A, no lane on a stale parent:")
    stale = 0
    for pull_request in sorted(pull_requests, key=lambda p: p["number"]):
        base = "origin/" + pull_request["base"]["ref"]
        head = "origin/" + pull_request["head"]["ref"]
        parent = git(repository, "rev-parse", "--short=9", base).stdout.strip()
        if git(repository, "merge-base", "--is-ancestor", base, head).returncode != 0:
            behind = git(repository, "rev-list", "--count", f"{head}..{base}").stdout.strip()
            print(f"  #{pull_request['number']} {pull_request['head']['ref']} lacks {behind} commit(s) of {pull_request['base']['ref']} (now {parent})")
            stale += 1
    if not stale:
        print("  held")

    print("\nRule B, macOS only on the top:")
    below = 0
    for run in runs:
        if run["name"] == "CI" and run["event"] == "pull_request" and run["status"] in ("queued", "in_progress") and run["head_branch"] in bases:
            print(f"  CI {run['id']} ({run['status']}) runs for {run['head_branch']}, which another pull request is based on")
            below += 1
    if not below:
        print("  held")


main()
