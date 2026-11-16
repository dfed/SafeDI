#!/usr/bin/env python3
"""Checks that every planned stack item has an active lane or a wait reason that still holds.

usage: plan-watch.py PLAN.md PRS.json RUNS.json REPOSITORY [--now ISO] [--quiet-minutes N]

PLAN.md holds one table row per planned item, bottom of the stack first:

    | item | branch | state | detail | since (UTC) |

state is one of:
    lane      a lane is working on it now; detail names the lane. The branch must show a push or a
              workflow run, or the row's since time must be, within the quiet limit (default 90
              minutes), or the row is questioned. since is when the row was last confirmed true,
              so a lane that pushes nothing is kept alive by whoever updates its row.
    waiting   nobody works on it; detail says on what ("on #752", "on slice 6", "on Dan"). A wait on a
              pull request that is no longer open, or on an item that is done, is questioned.
    done      landed or dropped.
A row with any other state, or a waiting row without a detail, is questioned. So is a plan nobody
has edited within the quiet limit while it has a lane row.

The process watch and stack watch read only pull requests and runs, so an item with no branch, no
pull request and no run was invisible to them: slices 7a and 7b sat without a lane for hours on
2026-11-16 while every watch said nothing was idle. This reads the plan instead.
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone


def parse_time(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def last_push(repository, branch):
    fetched = subprocess.run(["git", "-C", repository, "fetch", "-q", "origin", branch], capture_output=True, text=True)
    if fetched.returncode != 0:
        return None
    shown = subprocess.run(["git", "-C", repository, "log", "-1", "--format=%cI", "FETCH_HEAD"], capture_output=True, text=True)
    return parse_time(shown.stdout.strip()) if shown.returncode == 0 and shown.stdout.strip() else None


def main():
    arguments = sys.argv[1:]
    now = datetime.now(timezone.utc)
    quiet_minutes = 90
    for flag in ("--now", "--quiet-minutes"):
        if flag in arguments:
            index = arguments.index(flag)
            value = arguments[index + 1]
            del arguments[index:index + 2]
            if flag == "--now":
                now = parse_time(value)
            else:
                quiet_minutes = int(value)
    plan_path, pull_requests_path, runs_path, repository = arguments
    open_pull_requests = {pull_request["number"] for pull_request in json.load(open(pull_requests_path))}
    runs = json.load(open(runs_path))
    runs = runs.get("workflow_runs", runs) if isinstance(runs, dict) else runs
    newest_run = {}
    for run in runs:
        time = parse_time(run.get("updated_at") or run["created_at"])
        branch = run.get("head_branch")
        if branch and (branch not in newest_run or time > newest_run[branch]):
            newest_run[branch] = time

    rows = []
    for line in open(plan_path):
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if not line.lstrip().startswith("|") or len(cells) < 4 or cells[0] in ("item", "") or set(cells[0]) <= set("-: "):
            continue
        rows.append((cells + [""])[:5])
    if not rows:
        print("QUESTION: the plan lists no item. Is the stack empty?")
        return
    done = {item.lower() for item, _, state, _, _ in rows if state.lower() == "done"}
    questions = []
    has_lane = False
    for item, branch, state, detail, since in rows:
        state = state.lower()
        if state == "done":
            continue
        if state == "lane":
            has_lane = True
            if not detail:
                questions.append(f"{item}: no lane is named. Who is working on it?")
            if not branch or branch == "-":
                questions.append(f"{item}: a lane is named but no branch. Where is the work?")
                continue
            confirmed = None
            try:
                confirmed = datetime.strptime(since, "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc)
            except ValueError:
                questions.append(f"{item}: 'since' is not a time like 2026-11-16 22:25. When was this row last true?")
            # A lane on the lead's machine pushes nothing, so the row's own time counts as a sign of life.
            times = [time for time in (last_push(repository, branch), newest_run.get(branch), confirmed) if time]
            if times:
                quiet = (now - max(times)).total_seconds() / 60
                if quiet > quiet_minutes:
                    questions.append(f"{item} ({detail}): no push, no run and no word on {branch} for {quiet:.0f} minutes. Is the lane still on it?")
        elif state == "waiting":
            if not detail:
                questions.append(f"{item}: it waits, but on what? Give the reason or a lane.")
                continue
            for number in re.findall(r"#(\d+)", detail):
                if int(number) not in open_pull_requests:
                    questions.append(f"{item}: it waits {detail}, and #{number} is no longer open. Is the wait over?")
            for other in done:
                if re.search(r"\b" + re.escape(other) + r"\b", detail.lower()):
                    questions.append(f"{item}: it waits {detail}, and {other} is done. Is the wait over?")
        else:
            questions.append(f"{item}: state '{state}' is neither lane, waiting nor done. Who has it?")
    edited = (now - datetime.fromtimestamp(os.path.getmtime(plan_path), timezone.utc)).total_seconds() / 60
    if has_lane and edited > quiet_minutes:
        questions.append(f"the plan was last edited {edited:.0f} minutes ago. Is every row still true?")
    open_items = sum(1 for row in rows if row[2].lower() != "done")
    print(f"Planned items: {len(rows)}, {open_items} not done.")
    for question in questions:
        print("QUESTION:", question)
    if not questions:
        print("Every planned item has an active lane or a wait reason that still holds.")


if __name__ == "__main__":
    main()
