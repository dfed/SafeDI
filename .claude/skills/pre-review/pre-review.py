#!/usr/bin/env python3
"""Runs the checks a branch owes before it is reviewed, and prints the block its hand-back carries.

    pre-review.py [BASE] [--ref BRANCH] [--pins-run ID] [--no-wait] [--runner COMMAND]
                  [--matrix FILE --hand-back FILE]
    pre-review.py --report
    pre-review.py --self-test

BASE is the commit or branch the change is measured from (default `origin/main`; in a stack, the head of the branch
below, so that the checks and the lists are of this branch's own commits). A bare branch NAME whose local branch is
missing or at another commit than `origin/NAME` is measured from `origin/NAME`, which the stack is worked out from,
and the block says so when the local one differs. A base too far down only measures more: more suites, and pins
owed more often. A base that already holds the head measures nothing, and is refused. The block gives the base's
commit and how many commits it measured, for the reviewer to compare with the stack. It runs
from the checkout's top level, wherever it is started, on `HEAD`, and does these in order of cost:

1. `./CLI/lint.sh --check`, on this machine.
2. `.claude/skills/verify-touched/verify-touched.py BASE`, on this machine: the suites the change touches. The block
   gives every summary line it prints. `--runner COMMAND` (or `SAFEDI_VERIFY_RUNNER`) names a command both run
   behind, for a machine that queues heavy work.
3. Every fuzzer corpus with its pins, on CI and never on this machine: `gh workflow run verify.yml --ref BRANCH -f
   pins=true -f base=<BASE's commit>`, when the change touches a path the corpora draw from (`PINS_PREFIXES`) or one
   the fuzzer's rules file lists in its `paths:` (`.claude/rules/fuzzer-corpora.md`: the fuzzer, its workflows and
   its scripts). BRANCH (default: the current branch) must be pushed and its head on the remote must be `HEAD`,
   which is checked before the first two steps. `--pins-run ID` takes a Verify run already dispatched with pins on
   this head in place of a new one. The script then waits for the run: through the command `SAFEDI_PRE_REVIEW_WAIT`
   names, given the run's id, where a machine has one waiter for every run, else by asking GitHub once a minute.
   `--no-wait` prints the block with the run in progress, and `--report` later prints it again with the run's
   result. The run's id is recorded before the wait.

Both local checks run in a worktree of their own, checked out at `HEAD`, so they check this head's files whatever
is edited, stashed or committed in the checkout while they run. There is one such worktree per checkout, under the
user's caches directory (`SafeDIPreReview/worktrees`), kept between runs so that its build stays warm, and removed
by the first run, from any checkout, after its checkout's folder is gone. A second run
on the same checkout waits for the first to leave it, and a worktree that cannot be reused is made again. The
coverage report of step 3 is made there too.

`--coverage` adds `Scripts/changed-line-coverage.sh BASE` as a step, in that worktree: every changed line under
`Sources/` and `Plugins/` runs in a test. Without it the block says nothing of unit-test coverage, which
"Check Line Coverage on Linux" gates on CI.

It then lists these for the hand-back to answer, which fail nothing:

- every call the change adds or edits under `Sources/` that sorts, or takes a minimum, maximum or first element, by
  a key that names a label, a name or a position (an index or offset is the order of the list it came from):
  `CLAUDE.md`'s "Determinism" has choices follow declaration or source order. A comparator over several lines is
  read whole; a lookup by `==` is not a choice. An order inherited from a loop over a list that is already in label
  order has no such call, and only reading finds it;
- every test the change adds whose name says it tests a choice or an order: "Determinism" has such a test use twenty
  candidates or more, or a permutation of six;
- when the pins run passed, its report of the changed generator lines no corpus graph executed
  (`Scripts/fuzzer-coverage-report.sh`), each run of which the hand-back gives a disposition
  (`.claude/rules/fuzzer-corpora.md`, "Coverage of a change"). A report with no such run gives its count only. A
  report that could not be read makes the block NOT READY, and `--report` asks for it again.

- every file the change shares with another open change, the open pull requests' first and then the branches' that
  are work in progress with no pull request yet: on the remote, never the head of a pull request in any state (among
  the 300 newest), not a workflow's scratch ref (the prefixes main's workflows on the remote delete, read from them,
  whatever the checkout's say), and committed to within a day; the branches older than that are counted, as are the
  recent ones left out because a closed or merged pull request had their name as its head. Branches
  at one commit are one change, read at that commit. Each is measured from its merge base with main, or, when its
  history holds the head of another change the list reads (an open pull request, another such branch, or a branch
  below this one) or of a merged pull request, from the newest such head, so that it shares only the files it
  changed itself, a file it moved counted at both paths; one at another change's head, or built on this one, is
  left out and counted. A branch whose answer GitHub cut (300 files or 250 commits) is named. A change that shares
  a file with another is stacked on it, or the hand-back says why not. Two changes that each owe a pins run share
  the fuzzer's pins whatever files they edit: the pull requests that do are named, the branches counted. This
  branch's own stack is left out: what it is based on, by the pull requests' bases and BASE (`origin/NAME`, a
  branch's name, or the commit an open pull request or a branch is at), and what is based on it; a pull request that
  only shares its base is not. The list is asked of GitHub (two pull request lists and one branch list per hundred
  branches, then one request per such branch and one more for each built on another change, four at a time), and
  changes nothing anywhere. It is asked beside the local checks and given a minute in all: a request still
  unanswered then is given up, and the block takes the list after the pins run is dispatched and the record saved,
  so a slow GitHub delays neither; the list is dated by when it was asked. `--report`, and a run once its wait
  ends, ask it again when the pins run's state (in progress, passed or not) has changed or the list is five minutes
  old, or one minute when it was not checked or left a branch unread. Without `gh`, or when a pull request or branch list does not answer, the block says it was not
  checked; a branch that is gone, unreadable or not read in time is named and the rest are read.
- every instruction file (`CLAUDE.md`, `.claude/rules/*.md`, a directory's `CLAUDE.md`) within reach of the limit
  `Scripts/check-claude-instruction-files.sh` fails at, counted as that script counts: 500 characters for a rules
  file, 100 for a directory's `CLAUDE.md`, 50 words for the root one. Those the change edits are listed to trim or
  split before review; the others are named in one line, so that a lane about to add a rule knows the room it has.

With `--matrix` and `--hand-back` it also lists every cell of the brief's shape matrix that the hand-back does not
account for. A cell is a row of a Markdown table whose first column is a number such as `6.11`. The hand-back
accounts for it where it names the cell, or a range such as `6.1–6.4`, at the start of a line, a list item, a table
cell (after a `|`) or a clause after a semicolon, after the word "cell", or after a comma or "and" that follows a
cell so named (so `Swift 6.2` names none), and before the next cell it names, a semicolon or the end of the line
gives a test in backticks whose name has the three parts of `method_expectation_whenCondition`, the third beginning
`when`, a seed, or `unchanged`, `stopped` or `not done` straight after the cell. In `6.1, 6.2: unchanged` only the
last cell has its outcome straight after it; write the range. This too fails nothing: it is a list to answer.

The block names the head it describes. A block for another head is stale, as is one printed with uncommitted changes
(it says so). `--report` checks nothing on this machine again: it reads what the last run on this head recorded, asks
GitHub for the pins run's state, and prints the block, so a reviewer can print it too. A dispatch that fails keeps
the record of lint and the suites, and `--pins-run` on the same head runs them again.

What a run records is kept per head under the user's caches directory (`SafeDIPreReview`), never in the checkout.

Exit status: 0 when the block says READY; 1 when a check failed or is unfinished; 2 for wrong arguments, a base git
cannot find or that holds the head, or a head that is not on the remote under BRANCH when pins are owed.
"""

import argparse
import calendar
import collections
import contextlib
import fcntl
import hashlib
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True

SKILLS = pathlib.PurePosixPath(".claude/skills")
# A change to any of these can change what a corpus draws or what the tool generates for it. What runs the corpora and
# judges their pins is listed where the fuzzer's rules list it: the `paths:` front matter of FUZZER_RULES.
PINS_PREFIXES = ("Sources/", "Plugins/", "Tests/SafeDIToolTestSupport/", "Tests/SafeDIToolFuzzerTests/", "Package.swift", "Package.resolved")
FUZZER_RULES = ".claude/rules/fuzzer-corpora.md"
COVERAGE_REPORT = "Scripts/fuzzer-coverage-report.sh"
WAITER_VARIABLE = "SAFEDI_PRE_REVIEW_WAIT"
CHOICE_CALL = re.compile(r"\.(sorted|sort|min|max|first)\s*(\(|\{)")
CHOICE_KEY = re.compile(r"label|name|\bindex\b|offset|enumerated", re.IGNORECASE)
ORDER_COMPARISON = re.compile(r"\s[<>]\s|precedes|by:\s*[<>]")
CHOICE_TEST = re.compile(r"order|sorted|first|tie|determinis|choos|prefer|picks?(?=[A-Z_]|$)", re.IGNORECASE)
TEST_DECLARATION = re.compile(r"\bfunc\s+([A-Za-z0-9_]+)\s*\(")
LINES_OF_A_CHOICE = 40
UNDRAWN_RUN = re.compile(r"^R\d+ ")
UNDRAWN_COUNT = re.compile(r"changed executable generator line|left no coverage profile|has no coverage record|unit suite failed")
SUMMARY = re.compile(r"Test run with |^Executed |^No summary line|ran no test")


def front_matter_paths(text):
    """The globs a rules file's `paths:` front matter lists."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return []
    globs = []
    listing = False
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if re.match(r"\S", line):
            listing = line.strip() == "paths:"
        elif listing:
            match = re.match(r"\s+-\s+[\"']?(.+?)[\"']?\s*$", line)
            if match:
                globs.append(match.group(1))
    return globs


def glob_pattern(glob):
    """A path glob as a regular expression: `**/` is any directories, `*` anything but a slash."""
    pattern = ""
    index = 0
    while index < len(glob):
        if glob.startswith("**/", index):
            pattern += "(?:.*/)?"
            index += 3
        elif glob.startswith("**", index):
            pattern += ".*"
            index += 2
        elif glob[index] == "*":
            pattern += "[^/]*"
            index += 1
        else:
            pattern += re.escape(glob[index])
            index += 1
    return re.compile(pattern)


def owes_pins(changed_paths, fuzzer_globs):
    patterns = [glob_pattern(glob) for glob in fuzzer_globs]
    return any(
        path == prefix or (prefix.endswith("/") and path.startswith(prefix))
        for path in changed_paths for prefix in PINS_PREFIXES
    ) or any(pattern.fullmatch(path) for path in changed_paths for pattern in patterns)


def refusal(base, head, base_name):
    """Why nothing can be measured from this base, or None."""
    if base == head:
        return f"{base_name} holds this head, so there is no change to check. BASE must be the branch below this change, not one that contains it."
    return None


def remote_refusal(remote_head, head, branch):
    """Why a pins run cannot be dispatched on this branch, or None."""
    if remote_head != head:
        return f"{branch} on the remote is not at {head[:9]}. Push this head under a branch name, or name the branch with --ref."
    return None


def stack_of(branch, base_branch, pulls):
    """The branches this branch is stacked on or under, itself included, read from the pull requests' bases.

    Below it: the branch its pull request is based on (`base_branch`, the branch BASE names, when it has none yet),
    that branch's base, and so on. Above it: the pull requests based on it, those based on them, and so on. A pull
    request based on a branch below this one is a sibling, not part of the stack: it shares that base and nothing
    else. A branch in the stack shares files with this one by construction, so it is no overlap.
    """
    stack = {branch} | branches_below(branch, base_branch, pulls)
    above = {branch}
    grew = True
    while grew:
        grew = False
        for pull in pulls:
            if pull["base"] in above and pull["head"] not in above:
                above.add(pull["head"])
                grew = True
    return stack | above


def branches_below(branch, base_branch, pulls):
    """The branches this branch is stacked on, down to main: the bottom part of `stack_of`."""
    base_of = {pull["head"]: pull["base"] for pull in pulls}
    below = set()
    under = base_of.get(branch, base_branch)
    while under is not None and under != "main" and under != branch and under not in below:
        below.add(under)
        under = base_of.get(under)
    return below


def base_branch_of(base_name, base_commit, pulls, branches, scratch=()):
    """The branch BASE names: `origin/NAME`, a bare NAME on the remote, or the commit a branch is at.

    A commit is matched with the open pull requests' heads first, then with the branches' that are not scratch refs,
    the first by name of those at that commit: any of them is below this change.
    """
    name = base_name.removeprefix("origin/")
    if name in branches or any(pull["head"] == name for pull in pulls):
        return name
    for pull in pulls:
        if pull.get("commit") == base_commit:
            return pull["head"]
    at_base = sorted(name for name, (commit, _) in branches.items() if commit == base_commit and not name.startswith(tuple(scratch)))
    return at_base[0] if at_base else None


def remote_base(name, local, remote):
    """The BASE to measure from, and a note for the block when it is not the one given.

    A bare branch NAME is read by git as the local branch, but the stack is worked out from the remote's. When
    `origin/NAME` is at another commit than the local NAME (`local` and `remote`, empty when there is none), or there
    is no local NAME, the change is measured from `origin/NAME`, and the note says so.
    """
    if name.startswith("origin/") or not remote or local == remote:
        return name, None
    if not local:
        return f"origin/{name}", None
    return f"origin/{name}", f"the local {name} is at {local[:9]}, not at origin/{name}'s {remote[:9]}, so this measures from origin/{name}"


SCRATCH_PREFIX = re.compile(r"startsWith\(github\.ref_name, '([^']+/)'\)")


def scratch_prefixes(workflows):
    """The branch prefixes the workflows delete as scratch refs of one run, read from the texts of the workflows."""
    return sorted({prefix for text in workflows for prefix in SCRATCH_PREFIX.findall(text)})


def workflow_texts(repository):
    """The texts of main's workflows on the remote, from the branches query's answer, in file name order.

    Read from the remote's main, not from the checkout, whose workflows are of whatever commit it is at.
    """
    entries = (repository.get("workflows") or {}).get("entries") or []
    return [entry["object"]["text"] for entry in sorted(entries, key=lambda entry: entry["name"]) if entry["name"].endswith(".yml") and (entry.get("object") or {}).get("text")]


def lane_branches(branches, pulls, stack, heads_with_a_pull_request, scratch, now, newest=24 * 3600):
    """The branches on the remote that are someone's work in progress with no pull request yet, outside `stack`; how
    many more there are that are older; and how many recent ones are left out because a closed or merged pull
    request had their name as its head.

    One whose name no pull request has had as its head, open, closed or merged; that is not a workflow's scratch ref;
    and whose last commit is within `newest` seconds of `now`. The two counts are of branches that are no scratch ref
    and outside `stack`, so that the block says what the age cut and the head-name rule left out.
    """
    open_heads = {pull["head"] for pull in pulls}
    outside = [(name, now - committed <= newest) for name, (commit, committed) in branches.items() if name not in open_heads | stack | {"main"} and not name.startswith(tuple(scratch))]
    candidates = [(name, recent) for name, recent in outside if name not in heads_with_a_pull_request]
    once_a_head = sum(1 for name, recent in outside if recent and name in heads_with_a_pull_request)
    return sorted(name for name, recent in candidates if recent), sum(1 for _, recent in candidates if not recent), once_a_head


THIS_CHANGE = "this change"
BELOW_THIS_CHANGE = "below this change"


def lane_groups(names, branches):
    """The lane branches as changes: branches at one commit are one change, named together, in name order."""
    by_commit = {}
    for name in sorted(names):
        by_commit.setdefault(branches[name][0], []).append(name)
    return [{"name": "branch " + " = ".join(group), "branch": group[0], "commit": commit} for commit, group in by_commit.items()]


def known_heads(head, base_commit, below, stack, branches, pulls, groups, merged=()):
    """The commits a lane branch may be built on, each with the change whose head it is.

    This change's head; its base and the heads of the branches below it; the heads of the rest of its stack, this
    branch's on the remote and those above it, which are this change's too; the open pull requests' heads, in number
    order; the lane branches' own; and the heads of merged pull requests, (number, head commit) pairs, whose files
    are on main. No other branch's: a branch the list does not read (one older than a day, or a closed pull
    request's) may hold changes that are not on main, which a lane built on it carries and would otherwise show
    nowhere. The first to name a commit keeps it.
    """
    known = {head: THIS_CHANGE, base_commit: BELOW_THIS_CHANGE}
    for name in sorted(stack):
        if name in branches:
            known.setdefault(branches[name][0], BELOW_THIS_CHANGE if name in below else THIS_CHANGE)
    for pull in sorted(pulls, key=lambda pull: pull["number"]):
        known.setdefault(pull["commit"], pull["name"])
    for group in groups:
        known.setdefault(group["commit"], group["name"])
    for number, commit in sorted(merged):
        known.setdefault(commit, f"merged #{number}")
    return known


def lane_start(group, commits, known):
    """Where a lane branch's own changes start: "main", the commit to measure it from, or None to leave it out.

    `commits` are the branch's commits since its merge base with main, as GitHub's compare lists them. A branch at
    the head of another change has none of its own, and one built on this change is above it, in its stack: both are
    left out. A branch built on another change, an open pull request, another lane branch, a merged pull request or
    a branch below this change, is measured from the newest head of one in its history, so that it shares only the
    files it changed itself.
    """
    if known.get(group["commit"], group["name"]) != group["name"]:
        return None
    for commit in reversed(commits):
        if commit != group["commit"] and commit in known:
            return None if known[commit] == THIS_CHANGE else commit
    return "main"


def overlaps(changed, owed, pulls, lanes, fuzzer_globs):
    """The lines of the block's overlap list: the open pull requests' first, then the lane branches'.

    `pulls` and `lanes` are the changes outside this branch's stack, each with its `name` and changed `files`, a
    pull request with its `number` too. A line is a file this change shares with some of them, and who has it. Two
    changes that each owe a pins run share the pins the fuzzer's corpus tests hold even when neither has edited them
    yet, since landing either moves them under the other: that is each group's last line, which names the pull
    requests and counts the lane branches.
    """
    changed = sorted(set(changed))
    lines = []
    pulls_in_order = sorted(pulls, key=lambda pull: pull["number"])
    for others in (pulls_in_order, sorted(lanes, key=lambda lane: lane["name"])):
        holders = collections.defaultdict(list)
        for other in others:
            for path in set(other["files"]):
                holders[path].append(other["name"])
        lines += [f"{path}: {', '.join(holders[path])}" for path in changed if path in holders]
        if owed:
            owing = [other["name"] for other in others if owes_pins(other["files"], fuzzer_globs)]
            if owing and others is pulls_in_order:
                lines.append(f"the fuzzer's pins, which each of these also owes a run of: {', '.join(owing)}")
            elif owing:
                # Many lane branches owe a run at any time, and naming them all buries the pull requests above.
                lines.append(f"the fuzzer's pins, which {len(owing)} branch(es) without a pull request also owe a run of")
    return lines


def overlap_summary(pulls, lanes, skipped, cut, left_out=0, older=0, late=(), cut_lanes=(), branches_cut=None, once_a_head=0, seconds=None):
    """What was read to make the overlap list, for the block's line.

    `older` counts the branches the age cut left out, and `once_a_head` the recent ones left out because a closed or
    merged pull request had their name as its head; `late` names the branches not read before the deadline, which
    was `seconds` after the list was asked; `cut_lanes` the branches whose compare GitHub cut, each with what it cut;
    `branches_cut` is (read, all) when the branch list itself was cut.
    """
    text = f"{len(pulls)} pull request(s) and {len(lanes)} branch(es) without one read"
    if branches_cut:
        text += f"; only {branches_cut[0]} of the remote's {branches_cut[1]} branches listed"
    if older:
        text += f"; {older} branch(es) older than a day not read"
    if once_a_head:
        text += f"; {once_a_head} branch(es) not read, named as a closed or merged pull request's head"
    if left_out:
        text += f"; {left_out} branch(es) left out, at another change's head or built on this one"
    if skipped:
        text += f"; {len(skipped)} branch(es) not read, gone or unreadable: {', '.join(sorted(skipped))}"
    if late:
        text += f"; {len(late)} branch(es) not read within {SECONDS_FOR_THE_OVERLAP if seconds is None else seconds:g} s: {', '.join(sorted(late))}"
    if cut:
        text += f"; only the first {FILES_OF_A_PULL_REQUEST} files of {', '.join(cut)}"
    if cut_lanes:
        text += f"; GitHub cut the compare of {', '.join(f'{name} ({what})' for name, what in sorted(cut_lanes))}"
    return text


def added_lines(diff):
    """The lines a unified diff with no context adds, as (path, line number, text)."""
    added = []
    path = None
    number = 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@"):
            match = re.match(r"@@ -\S+ \+(\d+)", line)
            number = int(match.group(1)) if match else 0
        elif line.startswith("+") and path is not None:
            added.append((path, number, line[1:]))
            number += 1
    return added


def without_comment(line):
    return line.split("//")[0]


def choice_text(lines, number, start):
    """The call that starts at column `start` of line `number` (from 1), through the brace or parenthesis that closes it."""
    text = ""
    depth = 0
    opened = False
    # After a `for`, `if`, `guard` or `while`, a brace that follows the call's parentheses opens the statement's body.
    takes_trailing_closure = not re.match(r"\s*(for|if|guard|while|switch)\b", lines[number - 1]) if number <= len(lines) else True
    for offset, line in enumerate(lines[number - 1:number - 1 + LINES_OF_A_CHOICE]):
        code = without_comment(line)[start:] if offset == 0 else without_comment(line)
        for position, character in enumerate(code):
            if character in "({":
                depth += 1
                opened = True
            elif character in ")}":
                depth -= 1
                if opened and depth == 0 and not (takes_trailing_closure and code[position + 1:].lstrip().startswith("{")):
                    return text + code[:position + 1]
        text += code + "\n"
    return text


def choices_keyed_on_a_name(added, lines_of):
    """The calls under `Sources/` the change adds or edits that order or pick by a key naming a label, a name or a
    position, as (path, the call's line, the call's first line).

    `lines_of(path)` gives the file's lines at the head, so a comparator written over several lines is read whole, and
    an added line inside a comparator that was already there counts as its call. A lookup by equality chooses nothing
    and is left out, as is a bare `sorted()` unless its first or last element is taken. An order inherited from an
    iteration with no such call cannot be seen here.
    """
    found = []
    seen = set()

    def judge(path, number, lines):
        text = lines[number - 1] if number <= len(lines) else ""
        for match in CHOICE_CALL.finditer(without_comment(text)):
            whole = choice_text(lines, number, match.start())
            if re.fullmatch(r"\.(sorted|sort)\s*\(\s*\)", whole.strip()):
                # Sorted by its elements' own order, which matters only where one of them is then picked.
                if not re.match(r"\s*(\.first\b|\.last\b|\[0\])", without_comment(text)[match.start() + len(whole.strip()):]):
                    continue
                whole = without_comment(text)
            if not CHOICE_KEY.search(whole):
                continue
            if match.group(1) == "first" and "==" in whole and not ORDER_COMPARISON.search(whole):
                continue
            return True
        return False

    def calls_holding(number, lines):
        """The lines of the calls that span line `number`, itself included."""
        holding = [number]
        for earlier in range(number - 1, max(number - LINES_OF_A_CHOICE, 0), -1):
            for match in CHOICE_CALL.finditer(without_comment(lines[earlier - 1])):
                if earlier + choice_text(lines, earlier, match.start()).count("\n") >= number:
                    holding.append(earlier)
        return holding

    for path, number, _ in added:
        if not (path.startswith("Sources/") and path.endswith(".swift")):
            continue
        lines = lines_of(path)
        for call in calls_holding(number, lines):
            if (path, call) not in seen:
                seen.add((path, call))
                if judge(path, call, lines):
                    found.append((path, call, lines[call - 1].strip()))
    return sorted(found)


def tests_of_a_choice(added):
    found = []
    for path, number, text in added:
        match = TEST_DECLARATION.search(text)
        if path.startswith("Tests/") and path.endswith(".swift") and match and CHOICE_TEST.search(match.group(1)):
            found.append((path, number, match.group(1)))
    return found


MATRIX_CELL = re.compile(r"^\|\s*(\d+\.\d+)\s*\|")
# A cell is named at the start of an item (a line, a list item, a table cell, a clause after a semicolon), after the
# word "cell", or after a comma or "and" that follows a cell so named, so that a version number such as `Swift 6.2`
# names none.
CELL_MENTION = re.compile(r"(?P<lead>^\s*(?:[-*•]\s+)?|[;|]\s*|\bcells?\s+|,\s*|\band\s+)(\d+)\.(\d+)(?:\s*[–-]\s*\2\.(\d+))?(?!\d)", re.IGNORECASE)
CELL_LIST_LEAD = re.compile(r"^(,\s*|and\s+)$", re.IGNORECASE)
TEST_NAME = re.compile(r"`[a-z]\w*_[a-zA-Z]\w*_when\w*[^`]*`")
SEED = re.compile(r"\bseeds?\b\s*`?\d")
OUTCOME = re.compile(r"^\s*(\([a-z]\))?\s*[:–-]?\s*(unchanged|stopped|not done)\b")


def cells_unaccounted_for(matrix, hand_back):
    """The matrix's cells the hand-back does not account for.

    A cell is accounted for where the hand-back names it, or a range that holds it such as `6.1–6.4`, where
    `CELL_MENTION` reads a cell, and between that and the next cell it names, a semicolon or the end of the line,
    gives a test named `method_expectation_whenCondition` in backticks, a seed, or the outcome `unchanged`,
    `stopped` or `not done` straight after the cell.
    """
    cells = []
    for line in matrix.splitlines():
        match = MATRIX_CELL.match(line)
        if match and match.group(1) not in cells:
            cells.append(match.group(1))
    accounted = set()
    for line in hand_back.splitlines():
        mentions = []
        for mention in CELL_MENTION.finditer(line):
            if mentions or not CELL_LIST_LEAD.match(mention.group("lead")):
                mentions.append(mention)
        for index, mention in enumerate(mentions):
            # A mention's match may start at the semicolon before it, so the next one's start ends this one's clause.
            end = mentions[index + 1].start() if index + 1 < len(mentions) else len(line)
            said = line[mention.end():end].split(";")[0]
            if not (TEST_NAME.search(said) or SEED.search(said) or OUTCOME.search(said)):
                continue
            first = int(mention.group(3))
            last = int(mention.group(4)) if mention.group(4) else first
            accounted.update(f"{mention.group(2)}.{number}" for number in range(first, last + 1))
    return [cell for cell in cells if cell not in accounted]


def duration(seconds):
    seconds = int(round(seconds))
    return f"{seconds} s" if seconds < 60 else f"{seconds // 60} min {seconds % 60} s"


def pins_step(run, head):
    """What the block says of a Verify run, from `gh run view --json`'s answer, and whether it passed."""
    url = run.get("url", "")
    if run.get("headSha") != head:
        return f"failed: run {url} is of {str(run.get('headSha'))[:9]}, not this head", False
    if run.get("workflowName") != "Verify":
        return f"failed: run {url} is not a Verify run", False
    fuzzing = [job for job in run.get("jobs", []) if job.get("name", "").startswith("Fuzz")]
    if run.get("status") != "completed":
        return f"in progress, {url}", False
    seconds = seconds_between(run.get("createdAt"), run.get("updatedAt"))
    took = f", {duration(seconds)}" if seconds is not None else ""
    # A run whose build or tests failed skips its fuzzing too, so its conclusion is read first.
    if run.get("conclusion") != "success":
        return f"failed ({run.get('conclusion')}){took}, {url}", False
    if not any(job.get("conclusion") not in ("skipped", None, "") for job in fuzzing):
        return f"failed: run {url} fuzzed nothing (it was not dispatched with pins=true)", False
    return f"passed{took}, {url}", True


def dispatched_run(printed, runs, head, dispatched):
    """The id of the run a dispatch started: the one `gh workflow run` printed the URL of, else the only run of this
    head the listing shows since the dispatch. None while the listing shows none."""
    match = re.search(r"/actions/runs/(\d+)", printed)
    if match:
        return int(match.group(1))
    mine = [run for run in runs if run["headSha"] == head and run["createdAt"] >= dispatched]
    if len(mine) > 1:
        raise RuntimeError(f"gh printed no run, and {len(mine)} Verify runs of this head started since the dispatch ({', '.join(str(run['databaseId']) for run in mine)}). Pass the one with pins to --pins-run")
    return mine[0]["databaseId"] if mine else None


def seconds_between(start, end):
    try:
        return time.mktime(time.strptime(end, "%Y-%m-%dT%H:%M:%SZ")) - time.mktime(time.strptime(start, "%Y-%m-%dT%H:%M:%SZ"))
    except (TypeError, ValueError):
        return None


def instruction_limit(path):
    """The limit `Scripts/check-claude-instruction-files.sh` holds an instruction file to, as (limit, unit, margin), or None for another file."""
    if path == "CLAUDE.md":
        return 5500, "words", 50
    if path.startswith(".claude/rules/") and path.endswith(".md") and path.count("/") == 2:
        return 32000, "characters", 500
    if path.endswith("/CLAUDE.md"):
        return 1500, "characters", 100
    return None


def instruction_files_near_their_limit(texts, changed):
    """Each instruction file within its margin of its limit, or over it, as (path, size, limit, unit, edited here), fullest first.

    Measured as the script measures: characters, and words for the root `CLAUDE.md`."""
    near = []
    for path, text in texts.items():
        limit = instruction_limit(path)
        if limit is None:
            continue
        ceiling, unit, margin = limit
        size = len(text.split()) if unit == "words" else len(text)
        if size > ceiling - margin:
            near.append((path, size, ceiling, unit, path in changed))
    return sorted(near, key=lambda entry: (entry[2] - entry[1], entry[0]))


def block(record):
    """The text a hand-back carries, and whether it says READY."""
    commits = record.get("commits", 0)
    lines = ["Pre-review block", f"head: {record['head']} ({record['branch']}), {commits} commit(s) measured from {record['base']}"]
    if record.get("base note"):
        lines.append(f"base: {record['base note']}")
    ready = True
    if record.get("uncommitted"):
        lines.append("uncommitted changes in the checkout: they are not this head's, and no check saw them")
        ready = False
    for name in ("lint", "touched suites", "changed-line coverage", "pins"):
        if name == "changed-line coverage" and name not in record["steps"]:
            continue
        text, passed = record["steps"].get(name, ("not run", False))
        lines.append(f"{name}: {text}")
        ready = ready and passed
    sorts = record.get("sorts", [])
    if sorts:
        lines.append(f"to justify in the hand-back: {len(sorts)} added choice(s) keyed on a label, a name or a position")
        lines += [f"  {path}:{number}: {text}" for path, number, text in sorts]
    tests = record.get("tests", [])
    if tests:
        lines.append(f"to give the candidate count of in the hand-back: {len(tests)} added test(s) of a choice or an order")
        lines += [f"  {path}:{number}: {name}" for path, number, name in tests]
    overlap = record.get("overlap")
    if overlap is not None:
        text, shared = overlap
        if shared:
            lines.append(f"to stack on, or to answer in the hand-back: {len(shared)} overlap(s) with other open changes ({text})")
            lines += [f"  {line}" for line in shared]
        else:
            lines.append(f"overlap with other open changes: {text}")
    near = record.get("near limit", [])
    edited = [entry for entry in near if entry[4]]
    if edited:
        lines.append(f"to trim or split before review: {len(edited)} instruction file(s) this change edits at or near the limit")
        lines += [f"  {path}: {size:,} of {limit:,} {unit}" for path, size, limit, unit, _ in edited]
    others = [f"{path} ({size - limit:,} {unit} over)" if size > limit else f"{path} ({limit - size:,} {unit} left)" for path, size, limit, unit, here in near if not here]
    if others:
        lines.append(f"instruction files near their limit, not edited here: {', '.join(others)}")
    cells = record.get("cells")
    if cells:
        lines.append(f"to account for in the hand-back: {len(cells)} matrix cell(s) with no test, seed or outcome named: {', '.join(cells)}")
    if record.get("undrawn error"):
        lines.append(f"fuzzer coverage of the change: {record['undrawn error']}")
        ready = False
    undrawn = record.get("undrawn")
    if undrawn and any(UNDRAWN_RUN.match(line) for line in undrawn):
        lines.append(f"to give each run's disposition in the hand-back ({FUZZER_RULES}, \"Coverage of a change\"):")
        lines += [f"  {line}" for line in undrawn]
    elif undrawn:
        # No run to dispose of: only what the report says it counted and what it could not check.
        lines += [f"fuzzer coverage of the change: {line}" for line in undrawn if UNDRAWN_COUNT.search(line)]
    lines.append("result: READY" if ready else "result: NOT READY")
    return "\n".join(lines), ready


# MARK: Running


def output_of(*arguments, check=True):
    completed = subprocess.run(arguments, capture_output=True, text=True)
    if check and completed.returncode != 0:
        raise RuntimeError(f"{' '.join(arguments)}: {completed.stderr.strip() or completed.stdout.strip()}")
    return completed.stdout.strip()


def output_of_gh(*arguments):
    """What `gh` prints, asking up to three times: GitHub answers the odd request with a 502."""
    for attempt in range(3):
        try:
            return output_of("gh", *arguments)
        except RuntimeError:
            if attempt == 2:
                raise
            time.sleep(10)


def caches_directory():
    if sys.platform == "darwin":
        return pathlib.Path.home() / "Library/Caches"
    return pathlib.Path(os.environ.get("XDG_CACHE_HOME") or pathlib.Path.home() / ".cache")


def record_path(head):
    return caches_directory() / "SafeDIPreReview" / f"{head}.json"


def save(record):
    path = record_path(record["head"])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=1))


def timed(arguments, worktree):
    """A command's exit status, its seconds, and the lines it printed, run in the scratch worktree."""
    started = time.time()
    completed = subprocess.run(arguments, capture_output=True, text=True, cwd=worktree.path, pass_fds=(worktree.lock,))
    lines = [line.strip() for line in (completed.stdout + completed.stderr).splitlines() if line.strip()]
    return completed.returncode, time.time() - started, lines


Worktree = collections.namedtuple("Worktree", "path lock")


def remove_worktrees_of_deleted_checkouts(directory):
    """Removes each scratch worktree whose checkout is gone, with its build, which is several gigabytes.

    Beside each worktree a `.checkout` file names the checkout it serves. One that another run holds is left.
    """
    for record in directory.glob("*.checkout"):
        try:
            if os.path.isdir(record.read_text()):
                continue
            path = record.with_suffix("")
            with open(f"{path}.lock", "w") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                other = registering_repository(path)
                shutil.rmtree(path, ignore_errors=True)
                if other is not None:
                    output_of("git", "--git-dir", other, "worktree", "prune", check=False)
                record.unlink(missing_ok=True)
                pathlib.Path(f"{path}.lock").unlink(missing_ok=True)
        except OSError:
            continue


@contextlib.contextmanager
def scratch_worktree(top, head):
    """A worktree of this checkout at `head`, where lint, the suites and the coverage report run.

    They run there so that they check the head's files whatever is edited, stashed or committed in the checkout
    meanwhile. One worktree per checkout, in the caches directory and kept between runs, so that its `.build` and
    `CLI/.build`, which git ignores, stay warm. A lock file beside it is held for as long as the worktree is in use,
    so that a second run on the same checkout waits for the first and cannot change the files it is checking.

    Gives the worktree's path and the lock's file descriptor. Each command run in the worktree inherits the
    descriptor (`pass_fds`), so the lock outlives this script while any of them still runs: when the script alone
    is killed, the next run waits for the lint or `swift test` it left behind.
    """
    directory = caches_directory() / "SafeDIPreReview" / "worktrees"
    directory.mkdir(parents=True, exist_ok=True)
    remove_worktrees_of_deleted_checkouts(directory)
    path = directory / hashlib.sha256(top.encode()).hexdigest()[:16]
    pathlib.Path(f"{path}.checkout").write_text(top)
    with open(f"{path}.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("pre-review: waiting for another run on this checkout to leave the scratch worktree", file=sys.stderr)
            fcntl.flock(lock, fcntl.LOCK_EX)
        prepare_worktree(path, head)
        try:
            yield Worktree(path, lock.fileno())
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def registering_repository(path):
    """The git directory of the repository a worktree's `.git` file names, when it still exists."""
    try:
        match = re.match(r"gitdir: (.+)/worktrees/[^/]+\s*$", (path / ".git").read_text())
    except OSError:
        return None
    return match.group(1) if match and os.path.isdir(match.group(1)) else None


def prepare_worktree(path, head):
    """Checks `path` out at `head`, making the worktree again when it cannot be reused. Called with its lock held."""
    output_of("git", "worktree", "prune")
    try:
        # A worktree left by a checkout that was deleted and cloned again at the same path belongs to a repository
        # that is gone, or to none: it is reused only when it is this repository's.
        mine = os.path.realpath(output_of("git", "rev-parse", "--path-format=absolute", "--git-common-dir"))
        if os.path.realpath(output_of("git", "-C", str(path), "rev-parse", "--path-format=absolute", "--git-common-dir")) != mine:
            raise RuntimeError("the scratch worktree is another repository's")
        # Nothing else is here, since the lock is held and every command run here holds it too, so an index.lock
        # is what a killed run left behind.
        pathlib.Path(output_of("git", "-C", str(path), "rev-parse", "--path-format=absolute", "--git-dir"), "index.lock").unlink(missing_ok=True)
        output_of("git", "-C", str(path), "checkout", "--force", "--detach", head)
        output_of("git", "-C", str(path), "clean", "-fdq")
    except (RuntimeError, OSError):
        # Twice forced, which also removes a worktree that is locked or whose folder is missing.
        output_of("git", "worktree", "remove", "--force", "--force", str(path), check=False)
        other = registering_repository(path)
        shutil.rmtree(path, ignore_errors=True)
        output_of("git", "worktree", "prune")
        if other is not None:
            # The repository that had registered this path drops its record of it.
            output_of("git", "--git-dir", other, "worktree", "prune", check=False)
        output_of("git", "worktree", "add", "--force", "--detach", str(path), head)


def view_run(run):
    return json.loads(output_of_gh("run", "view", str(run), "--json", "headSha,workflowName,status,conclusion,url,createdAt,updatedAt,jobs"))


def dispatch_pins(branch, head, base):
    dispatched = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 5))
    # `base` is what the run's coverage report lists changes since: the commit this change builds on.
    # Asked once: a dispatch that GitHub answered with an error may still have started a run, and asking again
    # would start a second, so a failure is believed only when no run of this head appears.
    failure = None
    try:
        printed = output_of("gh", "workflow", "run", "verify.yml", "--ref", branch, "-f", "pins=true", "-f", f"base={base}")
    except RuntimeError as error:
        printed, failure = "", str(error).splitlines()[-1][:160]
    run = dispatched_run(printed, [], head, dispatched)
    for _ in range(30 if failure is None else 8):
        if run is not None:
            return run
        time.sleep(4)
        runs = json.loads(output_of_gh("run", "list", "--workflow", "verify.yml", "--branch", branch, "--event", "workflow_dispatch", "--limit", "10", "--json", "databaseId,headSha,createdAt"))
        run = dispatched_run("", runs, head, dispatched)
    if failure is not None:
        raise RuntimeError(f"gh workflow run failed and started no run of this head: {failure}")
    raise RuntimeError("the Verify run was dispatched and did not appear in two minutes; pass its id with --pins-run")


def undrawn_lines(run, base, worktree):
    """The report of the changed generator lines no corpus graph executed, from the run's coverage, made in the
    scratch worktree at the head."""
    completed = subprocess.run([COVERAGE_REPORT, str(run), base], capture_output=True, text=True, cwd=worktree.path, pass_fds=(worktree.lock,))
    if completed.returncode != 0:
        lines = [line for line in (completed.stderr + completed.stdout).splitlines() if line.strip()]
        raise RuntimeError(f"not read ({lines[-1].strip() if lines else 'no output'}). Run this command again with --report, or {COVERAGE_REPORT} {run} {base}")
    return [line for line in completed.stdout.splitlines() if line.strip()]


BRANCHES_QUERY = """
query($owner: String!, $name: String!, $after: String, $workflows: Boolean!) {
  repository(owner: $owner, name: $name) {
    refs(refPrefix: "refs/heads/", first: 100, after: $after) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { name target { oid ... on Commit { committedDate } } }
    }
    workflows: object(expression: "main:.github/workflows") @include(if: $workflows) {
      ... on Tree { entries { name object { ... on Blob { text } } } }
    }
  }
}
"""
FILES_OF_A_PULL_REQUEST = 100
PULL_REQUESTS_READ_FOR_THEIR_HEADS = 300
# GitHub's compare lists at most this many files, and this many commits on its first page.
FILES_OF_A_COMPARE = 300
COMMITS_OF_A_COMPARE = 250
# Twenty pages of a hundred: far more branches than the remote has had, and a bound on the requests if it ever does.
PAGES_OF_BRANCHES = 20
SECONDS_FOR_A_REQUEST = 60
SECONDS_FOR_THE_OVERLAP = 60
SECONDS_AN_OVERLAP_IS_KEPT = 300
SECONDS_A_PARTIAL_OVERLAP_IS_KEPT = 60
REQUESTS_AT_ONCE = 4


class Late(Exception):
    """The overlap's deadline passed before a request was asked. Not a RuntimeError, so that no request is asked again."""


def answer_of_gh(*arguments, seconds=SECONDS_FOR_A_REQUEST):
    """What one `gh` request prints, asked once and given `seconds`; a RuntimeError when it fails or does not answer."""
    try:
        completed = subprocess.run(("gh",) + arguments, capture_output=True, text=True, timeout=seconds)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"gh {arguments[0]}: {type(error).__name__}") from error
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip() or f"gh {arguments[0]} failed")
    return completed.stdout.strip()


def asking_before(deadline, clock, ask):
    """`ask`, given only what is left until `deadline` (on `clock`) and at most a minute; Late once nothing is left."""
    def ask_in_time(*arguments):
        left = deadline - clock()
        if left <= 0:
            raise Late()
        return ask(*arguments, seconds=min(SECONDS_FOR_A_REQUEST, left))
    return ask_in_time


def branch_list(ask):
    """The remote's branches, every page of them, with main's workflows from the first page's answer, and (read, all)
    when there were more than PAGES_OF_BRANCHES pages, else None."""
    nodes, first, cursor = [], None, None
    for page in range(PAGES_OF_BRANCHES):
        arguments = ["api", "graphql", "-F", "owner={owner}", "-F", "name={repo}", "-F", f"workflows={'true' if page == 0 else 'false'}", "-f", f"query={BRANCHES_QUERY}"]
        if cursor is not None:
            arguments += ["-f", f"after={cursor}"]
        repository = json.loads(ask(*arguments))["data"]["repository"]
        first = first or repository
        nodes += repository["refs"]["nodes"]
        if not repository["refs"]["pageInfo"]["hasNextPage"]:
            return nodes, first, None
        cursor = repository["refs"]["pageInfo"]["endCursor"]
    return nodes, first, (len(nodes), repository["refs"]["totalCount"])


def compare_of(start, end, ask=answer_of_gh):
    """The files a commit changed since its merge base with `start`, each moved file at both its paths, its commits
    since then, oldest first, and what GitHub cut of the answer.

    `end` is the commit the branch was listed at, so that a branch pushed or deleted since is read as listed, and no
    branch name goes into the URL. None when it cannot be read: a commit GitHub does not have answers 404, which is
    not asked again; any other failure is asked once more.
    """
    for attempt in range(2):
        try:
            answer = json.loads(ask("api", f"repos/{{owner}}/{{repo}}/compare/{start}...{end}", "--jq", "{files: [.files[]? | [.filename, .previous_filename]], commits: [.commits[]?.sha], total_commits: .total_commits}"))
            files = [path for paths in answer["files"] for path in paths if path]
            cut = []
            if len(answer["files"]) >= FILES_OF_A_COMPARE:
                cut.append(f"{FILES_OF_A_COMPARE} files or more")
            if (answer.get("total_commits") or 0) > len(answer["commits"]):
                cut.append(f"{len(answer['commits'])} of {answer['total_commits']} commits")
            return {"files": files, "commits": answer["commits"], "cut": cut}
        except RuntimeError as error:
            if "HTTP 404" in str(error):
                return None
        except (ValueError, KeyError, TypeError):
            pass
    return None


def in_daemon_threads(function, items, workers=REQUESTS_AT_ONCE):
    """`function` of each item, `workers` at a time, in the items' order. The threads are daemons, unlike a
    ThreadPoolExecutor's, which the interpreter joins at exit: a run whose main thread fails exits at once instead of
    waiting for the requests in flight. An item whose call raises gives None."""
    items = list(items)
    answers = [None] * len(items)
    lock = threading.Lock()
    taken = [0]

    def work():
        while True:
            with lock:
                index = taken[0]
                taken[0] += 1
            if index >= len(items):
                return
            try:
                answers[index] = function(items[index])
            except Exception:
                answers[index] = None

    threads = [threading.Thread(target=work, daemon=True) for _ in range(min(workers, len(items)))]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return answers


def overlap_of(record, fuzzer_globs=None, ask=answer_of_gh, now=time.time, clock=time.monotonic, deadline=None, seconds=SECONDS_FOR_THE_OVERLAP):
    """Which files this change shares with other open changes: the block's (summary, lines).

    It asks GitHub and changes nothing, on this machine or there, so two runs at once, or one that is killed, leave
    nothing behind. The pull request lists and the branch list must answer, or the block says the overlap was not
    checked; a branch that cannot be read, or is not read by `deadline` (on `clock`, `seconds` from now by default),
    is named in the block and the rest are still read. It fails nothing, as every list of the block. It reads only the
    record's head, branch, base, changed files and whether pins are owed. `ask`, `now`, `clock` and `fuzzer_globs` are
    the self-test's.
    """
    if ask is answer_of_gh and shutil.which("gh") is None:
        return ("not checked: this machine has no gh", [])
    if deadline is None:
        deadline = clock() + seconds
    in_time = asking_before(deadline, clock, ask)
    try:
        listed = json.loads(in_time("pr", "list", "--state", "open", "--limit", "200", "--json", "number,headRefName,headRefOid,baseRefName,files"))
        pulls = [{"number": pull["number"], "head": pull["headRefName"], "commit": pull["headRefOid"], "base": pull["baseRefName"], "name": f"#{pull['number']} ({pull['headRefName']})", "files": [file["path"] for file in pull["files"]]} for pull in listed]
        every = json.loads(in_time("pr", "list", "--state", "all", "--limit", str(PULL_REQUESTS_READ_FOR_THEIR_HEADS), "--json", "number,headRefName,headRefOid,state"))
        heads = {pull["headRefName"] for pull in every}
        merged = [(pull["number"], pull["headRefOid"]) for pull in every if pull.get("state") == "MERGED"]
        nodes, repository, branches_cut = branch_list(in_time)
        branches = {node["name"]: (node["target"]["oid"], calendar.timegm(time.strptime(node["target"]["committedDate"], "%Y-%m-%dT%H:%M:%SZ"))) for node in nodes if "committedDate" in node["target"]}
        scratch = scratch_prefixes(workflow_texts(repository))
        base_branch = base_branch_of(record.get("base name", ""), record.get("base commit"), pulls, branches, scratch)
        stack = stack_of(record["branch"], base_branch, pulls)
        outside = [pull for pull in pulls if pull["head"] not in stack]
        names, older, once_a_head = lane_branches(branches, pulls, stack, heads, scratch, now())
        groups = lane_groups(names, branches)
        known = known_heads(record["head"], record.get("base commit"), branches_below(record["branch"], base_branch, pulls), stack, branches, pulls, groups, merged)

        def compare(start, group):
            try:
                return compare_of(start, group["commit"], in_time)
            except Late:
                return Late

        compared = in_daemon_threads(lambda group: compare("main", group), groups)
        first = list(compared)
        starts = [lane_start(group, found["commits"], known) if isinstance(found, dict) else None for group, found in zip(groups, compared)]
        # A branch built on another change is compared again, from that change's head.
        again = [(index, start) for index, start in enumerate(starts) if start not in (None, "main")]
        for (index, start), found in zip(again, in_daemon_threads(lambda pair: compare(pair[1], groups[pair[0]]), again)):
            compared[index] = found
        read = [(group, found, start, index) for index, (group, found, start) in enumerate(zip(groups, compared, starts)) if isinstance(found, dict)]
        lanes = [{"name": group["name"], "files": found["files"]} for group, found, start, _ in read if start is not None]
        skipped = [group["name"].removeprefix("branch ") for group, found in zip(groups, compared) if found is None]
        late = [group["name"].removeprefix("branch ") for group, found in zip(groups, compared) if found is Late]
        left_out = sum(1 for _, _, start, _ in read if start is None)
        cut_lanes = []
        for group, found, _, index in read:
            cut = list(dict.fromkeys(first[index]["cut"] + found["cut"]))
            if cut:
                cut_lanes.append((group["name"].removeprefix("branch "), ", ".join(cut)))
        if fuzzer_globs is None:
            fuzzer_globs = front_matter_paths(pathlib.Path(FUZZER_RULES).read_text())
        shared = overlaps(record["changed"], record["owes pins"], outside, lanes, fuzzer_globs)
        cut_pulls = [pull["name"] for pull in sorted(outside, key=lambda pull: pull["number"]) if len(pull["files"]) >= FILES_OF_A_PULL_REQUEST]
        text = overlap_summary(outside, lanes, skipped, cut_pulls, left_out, older, late, cut_lanes, branches_cut, once_a_head, seconds)
        return (text if shared else f"none ({text})", shared)
    except Late:
        return (f"not checked: GitHub did not list the pull requests and branches within {seconds:g} s", [])
    except (RuntimeError, OSError, KeyError, TypeError, ValueError) as error:
        return (f"not checked: {(str(error).splitlines() or [type(error).__name__])[-1][:160]}", [])


OVERLAP_INPUTS = ("head", "branch", "base name", "base commit", "changed", "owes pins")


def start_overlap(record, fuzzer_globs, ask=answer_of_gh, clock=time.monotonic, seconds=SECONDS_FOR_THE_OVERLAP):
    """Starts `overlap_of` in a thread of its own, beside the local checks, and gives the function that takes its
    answer: it waits until the deadline, and a few seconds more for a request given up at it, and returns the list,
    or a line saying it was not checked when the thread has not answered by then, with the time the list was asked.

    The thread reads a copy of what it needs, so the record can be saved meanwhile. It and its workers are daemons:
    a run that ends, or fails, does not wait for them. An error `overlap_of` does not expect is reported as such, not
    as GitHub's silence.
    """
    asked_at = time.time()
    deadline = clock() + seconds
    inputs = {key: record.get(key) for key in OVERLAP_INPUTS}
    answers = []

    def read():
        try:
            answers.append(overlap_of(inputs, fuzzer_globs, ask, clock=clock, deadline=deadline, seconds=seconds))
        except Exception as error:
            answers.append((f"not checked: {type(error).__name__}: {(str(error).splitlines() or [''])[-1][:160]}", []))

    thread = threading.Thread(target=read, daemon=True)
    thread.start()

    def take(grace=5):
        thread.join(max(0, deadline - clock()) + grace)
        return (answers[0] if answers else (f"not checked: GitHub did not answer within {seconds:g} s", [])), asked_at
    return take


def pins_state(step):
    """The pins step's state, without the details its text carries: whether a run is in progress, passed or not."""
    if not step:
        return None
    text, passed = step
    return "in progress" if text.startswith("in progress") else ("passed" if passed else "not passed")


def overlap_is_stale(record, pins_before, now):
    """Whether the overlap is asked again: when the record has none, when the pins run's state changed since it was
    saved (`pins_before` is the step as the record had it; only in progress, passed or not), or when the list is
    SECONDS_AN_OVERLAP_IS_KEPT old, or SECONDS_A_PARTIAL_OVERLAP_IS_KEPT when it was not checked or left branches
    unread. A waiter that reports every minute would otherwise ask GitHub for every lane branch each time."""
    if "overlap" not in record or "overlap at" not in record:
        return True
    if pins_state(record["steps"].get("pins")) != pins_state(pins_before):
        return True
    text = record["overlap"][0]
    partial = text.startswith("not checked") or " not read within " in text or "gone or unreadable" in text
    return now - record["overlap at"] >= (SECONDS_A_PARTIAL_OVERLAP_IS_KEPT if partial else SECONDS_AN_OVERLAP_IS_KEPT)


def refresh_overlap_if_stale(record, pins_before):
    """Asks the overlap again, synchronously and under its own deadline, when `overlap_is_stale` says so; stamped
    with the time it was asked."""
    if "changed" in record and overlap_is_stale(record, pins_before, time.time()):
        asked_at = time.time()
        record["overlap"], record["overlap at"] = overlap_of(record), asked_at


def refresh_pins(record, wait):
    """Reads the pins run's state into the record, waiting for the run to end when `wait`.

    The wait is the command `SAFEDI_PRE_REVIEW_WAIT` names, given the run's id, on a machine that has one waiter for
    every GitHub run; without it this asks GitHub once a minute. An answer GitHub fails to give counts as in progress.
    """
    run = record.get("pins run")
    if run is None:
        return
    waiter = os.environ.get(WAITER_VARIABLE, "")
    while True:
        try:
            text, passed = pins_step(view_run(run), record["head"])
        except RuntimeError as error:
            text, passed = f"in progress, run {run} (GitHub did not answer: {str(error).splitlines()[-1][:120]})", False
        record["steps"]["pins"] = (text, passed)
        if not text.startswith("in progress"):
            break
        if not wait:
            return
        if waiter:
            # Captured, so that nothing the waiter prints is taken for part of the block.
            subprocess.run(shlex.split(waiter) + [str(run)], capture_output=True)
            waiter = ""
        else:
            time.sleep(60)
    # A report that could not be read is asked for again by every later run, `--report` included.
    if passed and "undrawn" not in record:
        try:
            # In the scratch worktree, as the checks ran: the report reads the head's files, not the checkout's.
            with scratch_worktree(output_of("git", "rev-parse", "--show-toplevel"), record["head"]) as worktree:
                record["undrawn"] = undrawn_lines(run, record.get("base commit") or "origin/main", worktree)
            record.pop("undrawn error", None)
        except RuntimeError as error:
            record["undrawn error"] = str(error)


def finish(record):
    save(record)
    text, ready = block(record)
    print(text)
    sys.exit(0 if ready else 1)


def run(arguments):
    if bool(arguments.matrix) != bool(arguments.hand_back):
        print("pre-review: --matrix and --hand-back go together", file=sys.stderr)
        sys.exit(2)
    # Named from where the command was started, before it moves to the checkout's top level.
    matrix_path = os.path.abspath(arguments.matrix) if arguments.matrix else None
    hand_back_path = os.path.abspath(arguments.hand_back) if arguments.hand_back else None
    top = output_of("git", "rev-parse", "--show-toplevel")
    os.chdir(top)
    head, status = output_of("git", "rev-parse", "HEAD"), output_of("git", "status", "--porcelain")
    if arguments.report:
        path = record_path(head)
        if not path.exists():
            print(f"pre-review: no run is recorded for {head[:9]} on this machine. Run it without --report.", file=sys.stderr)
            sys.exit(2)
        record = json.loads(path.read_text())
        pins_before = record["steps"].get("pins")
        refresh_pins(record, wait=False)
        refresh_overlap_if_stale(record, pins_before)
        finish(record)
    # Exact refs only, so that BASE written as a revision such as `HEAD~1` is never read as a branch's name.
    local = output_of("git", "show-ref", "--verify", "--hash", f"refs/heads/{arguments.base}", check=False)
    remote = output_of("git", "show-ref", "--verify", "--hash", f"refs/remotes/origin/{arguments.base}", check=False)
    arguments.base, base_note = remote_base(arguments.base, local, remote)
    try:
        base = output_of("git", "merge-base", arguments.base, "HEAD")
    except RuntimeError as error:
        print(f"pre-review: {error}", file=sys.stderr)
        sys.exit(2)
    refused = refusal(base, head, arguments.base)
    branch = arguments.ref or output_of("git", "rev-parse", "--abbrev-ref", "HEAD")
    # Without rename detection, so that a file moved out of `Sources/` is a change there.
    changed = output_of("git", "diff", "--name-only", "--no-renames", base, "HEAD").splitlines()
    fuzzer_globs = front_matter_paths(pathlib.Path(FUZZER_RULES).read_text())
    if not fuzzer_globs:
        raise RuntimeError(f"{FUZZER_RULES} lists no paths, so what owes a pins run is not known")
    owed = owes_pins(changed, fuzzer_globs)
    dispatches = owed and shutil.which("gh") is not None and not arguments.pins_run
    # Before the checks, which take minutes: a head that is not on the remote cannot be fuzzed.
    if refused is None and dispatches:
        refused = remote_refusal(output_of("git", "ls-remote", "origin", f"refs/heads/{branch}").split("\t")[0], head, branch)
    if refused is not None:
        print(f"pre-review: {refused}", file=sys.stderr)
        sys.exit(2)
    added = added_lines(output_of("git", "diff", "-U0", "--no-color", "--no-renames", base, "HEAD", "--", "Sources", "Tests"))
    sources = {}

    def lines_of(path):
        if path not in sources:
            sources[path] = output_of("git", "show", f"{head}:{path}").splitlines()
        return sources[path]

    record = {
        "head": head,
        "branch": branch,
        "base": f"{arguments.base} at {base[:9]}",
        "base commit": base,
        "base note": base_note,
        "commits": int(output_of("git", "rev-list", "--count", f"{base}..HEAD")),
        "uncommitted": bool(status),
        "changed": changed,
        "owes pins": owed,
        "base name": arguments.base,
        "steps": {},
        "sorts": choices_keyed_on_a_name(added, lines_of),
        "tests": tests_of_a_choice(added),
    }
    instruction_paths = [path for path in output_of("git", "ls-tree", "-r", "--name-only", head).splitlines() if instruction_limit(path)]
    record["near limit"] = instruction_files_near_their_limit({path: subprocess.run(["git", "show", f"{head}:{path}"], capture_output=True, check=True).stdout.decode("utf-8") for path in instruction_paths}, set(changed))
    if arguments.matrix:
        record["cells"] = cells_unaccounted_for(pathlib.Path(matrix_path).read_text(), pathlib.Path(hand_back_path).read_text())
    runner = shlex.split(arguments.runner) if arguments.runner else []
    # Asked of GitHub beside the local checks, and taken only after the pins run is dispatched and the record saved.
    take_overlap = start_overlap(record, fuzzer_globs)
    # The worktree is held for the local checks only, not for the wait on CI that follows.
    with scratch_worktree(top, head) as worktree:
        status_code, seconds, lines = timed(runner + ["./CLI/lint.sh", "--check"], worktree)
        last = lines[-1] if lines else ""
        record["steps"]["lint"] = (f"passed, {duration(seconds)}" if status_code == 0 else f"failed, {duration(seconds)}: {last}", status_code == 0)
        touched = [sys.executable, "-I", str(SKILLS / "verify-touched/verify-touched.py"), arguments.base]
        if arguments.runner:
            touched += ["--runner", arguments.runner]
        status_code, seconds, lines = timed(touched, worktree)
        # Every run's summary line, not the last one only: a passing run after a failing one must not hide it.
        summaries = [line for line in lines if SUMMARY.search(line)] or lines[-1:]
        record["steps"]["touched suites"] = (f"{'passed' if status_code == 0 else 'failed'}, {duration(seconds)}: {'; '.join(summaries)}", status_code == 0)
        if arguments.coverage:
            status_code, seconds, lines = timed(runner + ["Scripts/changed-line-coverage.sh", arguments.base], worktree)
            last = lines[-1] if lines else ""
            record["steps"]["changed-line coverage"] = (f"{'passed' if status_code == 0 else 'failed'}, {duration(seconds)}: {last}", status_code == 0)
    if not owed:
        record["steps"]["pins"] = ("not owed: the change touches nothing a corpus draws from or runs", True)
    elif shutil.which("gh") is None:
        record["steps"]["pins"] = (f"not run: this machine has no gh. Dispatch verify.yml with pins=true and base={base[:9]} on {branch} and pass the run's id with --pins-run", False)
    else:
        try:
            record["pins run"] = arguments.pins_run or dispatch_pins(branch, head, base)
            record["steps"]["pins"] = (f"in progress, run {record['pins run']}", False)
        except RuntimeError as error:
            # Lint and the suites took minutes: their results are kept when the dispatch fails.
            record["steps"]["pins"] = (f"not run: the dispatch failed ({str(error).splitlines()[-1][:160]}). Dispatch verify.yml with pins=true and base={base[:9]} on {branch} and pass the run's id with --pins-run", False)
    # Before the overlap and the wait, so that lint's and the suites' results and the run's id outlive anything that
    # stops either.
    save(record)
    # Stamped with the time it was asked, before the local checks, so a list from minutes ago is not taken as new.
    record["overlap"], record["overlap at"] = take_overlap()
    pins_before = record["steps"].get("pins")
    if "pins run" in record:
        refresh_pins(record, wait=not arguments.no_wait)
    # The list the block prints is asked again when the wait changed the run's state or it is too old.
    refresh_overlap_if_stale(record, pins_before)
    finish(record)


# MARK: Self-test


def self_test():
    failures = []

    def expect(what, actual, expected):
        if actual != expected:
            failures.append(f"{what}\n  expected {expected!r}\n  actual   {actual!r}")

    rules = "\n".join(["---", "paths:", '  - "Tests/**/GraphFuzzer*.swift"', '  - ".github/workflows/graph-fuzzer.yml"', '  - ".github/scripts/*graph-fuzzer*"', '  - "Scripts/fuzz-corpus.sh"', "---", "# Rules", "  - not a path"])
    globs = front_matter_paths(rules)
    expect("a rules file's paths", globs, ["Tests/**/GraphFuzzer*.swift", ".github/workflows/graph-fuzzer.yml", ".github/scripts/*graph-fuzzer*", "Scripts/fuzz-corpus.sh"])
    expect("a file with no front matter lists none", front_matter_paths("# Rules\npaths:\n  - x"), [])
    expect("a source change owes pins", owes_pins(["Sources/SafeDICore/Generators/ScopeGenerator.swift"], globs), True)
    expect("the fuzzer owes pins", owes_pins(["Tests/SafeDIToolFuzzerTests/SafeDIToolGraphFuzzerTests.swift"], globs), True)
    expect("the manifest owes pins", owes_pins(["README.md", "Package.swift"], globs), True)
    expect("a test of another target owes none", owes_pins(["Tests/SafeDIToolMockTests/SafeDIToolMockGenerationTests.swift", "Documentation/Manual.md"], globs), False)
    expect("a path that only starts like the manifest owes none", owes_pins(["Package.swift.orig"], globs), False)
    for path in (".github/workflows/graph-fuzzer.yml", ".github/scripts/combine-graph-fuzzer-reports.py", ".github/scripts/summarize-graph-fuzzer-report.sh", "Scripts/fuzz-corpus.sh", "Tests/SafeDIToolTestSupport/Deep/GraphFuzzerDraws.swift"):
        expect(f"{path} owes pins", owes_pins([path], globs), True)
    expect("another workflow owes none", owes_pins([".github/workflows/publish.yml", ".github/scripts/check-links.py"], globs), False)
    # `git diff --name-only --no-renames` lists both paths of a move, so the path it leaves is seen.
    expect("a file moved out of Sources owes pins", owes_pins(["Sources/SafeDICore/Helper.swift", "Tests/SafeDIToolTests/Helper.swift"], globs), True)
    expect("a base that holds the head is refused", refusal("c" * 40, "c" * 40, "slice-3"), "slice-3 holds this head, so there is no change to check. BASE must be the branch below this change, not one that contains it.")
    expect("a base below the head is not", refusal("b" * 40, "c" * 40, "slice-1"), None)
    expect("a branch that is elsewhere on the remote is refused", remote_refusal("b" * 40, "c" * 40, "claude/x"), "claude/x on the remote is not at ccccccccc. Push this head under a branch name, or name the branch with --ref.")
    expect("a branch that is absent from the remote is refused", remote_refusal("", "c" * 40, "claude/x") is None, False)
    expect("a pushed head is not", remote_refusal("c" * 40, "c" * 40, "claude/x"), None)

    diff = "\n".join([
        "diff --git a/Sources/SafeDICore/A.swift b/Sources/SafeDICore/A.swift",
        "--- a/Sources/SafeDICore/A.swift",
        "+++ b/Sources/SafeDICore/A.swift",
        "@@ -10,0 +11,3 @@ func f() {",
        "+\tlet first = properties.sorted { $0.label < $1.label }",
        "+\tlet second = properties.sorted { $0.declarationLocation < $1.declarationLocation } // not by label",
        "+\tlet third = names.min(by: { $0.typeName < $1.typeName })",
        "@@ -40 +44 @@",
        "-\told",
        "+\tlet label = property.label",
        "--- a/Tests/SafeDIToolMockTests/B.swift",
        "+++ b/Tests/SafeDIToolMockTests/B.swift",
        "@@ -0,0 +7,3 @@",
        "+\t@Test func mock_reportsTheFirstError_whenTwoTypesCollide() {",
        "+\t@Test func mock_generatesAMock_whenATypeHasOne() {",
        "+\tlet sorted = labels.sorted { $0.name < $1.name }",
        "--- a/Sources/SafeDICore/Gone.swift",
        "+++ /dev/null",
        "@@ -1 +0,0 @@",
        "-\tlet x = a.sorted { $0.label < $1.label }",
    ])
    added = added_lines(diff)
    expect("added lines carry their numbers", [(path, number) for path, number, _ in added], [
        ("Sources/SafeDICore/A.swift", 11), ("Sources/SafeDICore/A.swift", 12), ("Sources/SafeDICore/A.swift", 13), ("Sources/SafeDICore/A.swift", 44),
        ("Tests/SafeDIToolMockTests/B.swift", 7), ("Tests/SafeDIToolMockTests/B.swift", 8), ("Tests/SafeDIToolMockTests/B.swift", 9),
    ])
    files = {}
    for path, number, text in added:
        files.setdefault(path, {})[number] = text
    expect("choices keyed on a label or a name, in Sources only, a comment aside", choices_keyed_on_a_name(added, lambda path: [files[path].get(number, "") for number in range(1, 50)]), [
        ("Sources/SafeDICore/A.swift", 11, "let first = properties.sorted { $0.label < $1.label }"),
        ("Sources/SafeDICore/A.swift", 13, "let third = names.min(by: { $0.typeName < $1.typeName })"),
    ])
    # The shapes a review found by reading: comparators over several lines, a tie broken by position in a list that
    # is in label order, and what to leave out, a lookup by equality and names sorted for a message.
    source = [
        "\t\tlet fills = children.enumerated().compactMap { index, child in",
        "\t\t\tchild.fillHole.map { (index: index, pathHole: $0) }",
        "\t\t}.sorted { lhs, rhs in",
        "\t\t\tif lhs.pathHole.declarationLocation == rhs.pathHole.declarationLocation {",
        "\t\t\t\tlhs.index < rhs.index",
        "\t\t\t} else {",
        "\t\t\t\tprecedesInSourceOrder(lhs.pathHole.declarationLocation, rhs.pathHole.declarationLocation)",
        "\t\t\t}",
        "\t\t}",
        "\t\tlet ordered = fills.sorted { first, second in",
        "\t\t\t// by where each is forwarded",
        "\t\t\tfirst.builderLabel < second.builderLabel",
        "\t\t}",
        "\t\tenumerated().sorted { first, second in",
        "\t\t\tlet (firstLocation, secondLocation) = (place(first.element)?.forwardingLocation, place(second.element)?.forwardingLocation)",
        "\t\t\treturn firstLocation == secondLocation ? first.offset < second.offset : firstLocation < secondLocation",
        "\t\t}.map(\\.element)",
        "\t\tlet byLocation = fills.sorted { first, second in",
        "\t\t\tfirst.declarationLocation < second.declarationLocation",
        "\t\t}",
        "\t\tlet match = fills.first(where: { $0.property.label == label })",
        "\t\tlet other = fills.first { $0.name == name }",
        "\t\tlet earliest = fills.first { $0.name < name }",
        "\t\tlet message = labels.sorted().joined(separator: \", \")",
        "\t\tlet chosen = labels.sorted().first",
        "\t\tlet smallest = fills.min(by: {",
        "\t\t\t$0.typeName < $1.typeName",
        "\t\t})",
    ]
    choices = choices_keyed_on_a_name([("Sources/SafeDICore/Fills.swift", number, text) for number, text in enumerate(source, start=1)], lambda path: source)
    expect("choices written over several lines, ties by position, and no lookups", [number for _, number, _ in choices], [3, 10, 14, 23, 25, 26])
    expect("a line added inside a comparator that was already there counts as its call", choices_keyed_on_a_name([("Sources/SafeDICore/Fills.swift", 15, source[14])], lambda path: source), [("Sources/SafeDICore/Fills.swift", 14, "enumerated().sorted { first, second in")])
    expect("a loop's body is not the trailing closure of the call in its header", choices_keyed_on_a_name([("Sources/A.swift", 1, "for label in labels.sorted() {")], lambda path: ["for label in labels.sorted() {", "\tprint(label.name)", "}"]), [])
    expect("tests whose names say they test a choice", tests_of_a_choice(added), [("Tests/SafeDIToolMockTests/B.swift", 7, "mock_reportsTheFirstError_whenTwoTypesCollide")])

    head = "a" * 40
    passed = {"headSha": head, "workflowName": "Verify", "status": "completed", "conclusion": "success", "url": "https://example.com/runs/1", "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:54:10Z", "jobs": [{"name": "Verify on Linux", "conclusion": "success"}, {"name": "Fuzz / Fuzz Graphs on Linux (base)", "conclusion": "success"}]}
    expect("a passed pins run", pins_step(passed, head), ("passed, 54 min 10 s, https://example.com/runs/1", True))
    expect("a run of another head", pins_step(passed, "b" * 40), ("failed: run https://example.com/runs/1 is of aaaaaaaaa, not this head", False))
    expect("a run of another workflow", pins_step({**passed, "workflowName": "CI"}, head), ("failed: run https://example.com/runs/1 is not a Verify run", False))
    expect("a run in progress", pins_step({**passed, "status": "in_progress", "conclusion": ""}, head), ("in progress, https://example.com/runs/1", False))
    expect("a Verify run without pins", pins_step({**passed, "jobs": [{"name": "Verify on Linux", "conclusion": "success"}, {"name": "Fuzz", "conclusion": "skipped"}]}, head), ("failed: run https://example.com/runs/1 fuzzed nothing (it was not dispatched with pins=true)", False))
    expect("a failed pins run", pins_step({**passed, "conclusion": "failure"}, head), ("failed (failure), 54 min 10 s, https://example.com/runs/1", False))
    expect("a pins run whose build failed, so that it fuzzed nothing", pins_step({**passed, "conclusion": "failure", "jobs": [{"name": "Verify on Linux", "conclusion": "failure"}, {"name": "Fuzz", "conclusion": "skipped"}]}, head), ("failed (failure), 54 min 10 s, https://example.com/runs/1", False))
    listing = [{"databaseId": 1001, "headSha": head, "createdAt": "2026-01-01T00:00:01Z"}, {"databaseId": 1002, "headSha": head, "createdAt": "2026-01-01T00:00:03Z"}, {"databaseId": 900, "headSha": head, "createdAt": "2025-12-31T23:00:00Z"}, {"databaseId": 1003, "headSha": "b" * 40, "createdAt": "2026-01-01T00:00:02Z"}]
    expect("the run gh printed, whatever else started", dispatched_run("https://github.com/o/r/actions/runs/1001\n", listing, head, "2026-01-01T00:00:00Z"), 1001)
    expect("the only run of this head since the dispatch", dispatched_run("", listing[:1] + listing[2:], head, "2026-01-01T00:00:00Z"), 1001)
    expect("no run yet", dispatched_run("", listing[2:], head, "2026-01-01T00:00:00Z"), None)
    try:
        dispatched_run("", listing, head, "2026-01-01T00:00:00Z")
        expect("two runs since the dispatch are refused", "adopted one", "refused")
    except RuntimeError as error:
        expect("two runs since the dispatch are refused, by name", "1001, 1002" in str(error), True)

    record = {"head": head, "branch": "claude/x", "base": "origin/main at 123456789", "commits": 3, "uncommitted": False, "steps": {"lint": ("passed, 9 s", True), "touched suites": ("passed, 1 min 5 s: ok", True), "pins": ("not owed: the change touches nothing a corpus draws from or runs", True)}, "sorts": [], "tests": []}
    expect("a ready block", block(record), ("\n".join([
        "Pre-review block",
        f"head: {head} (claude/x), 3 commit(s) measured from origin/main at 123456789",
        "lint: passed, 9 s",
        "touched suites: passed, 1 min 5 s: ok",
        "pins: not owed: the change touches nothing a corpus draws from or runs",
        "result: READY",
    ]), True))
    rules = ".claude/rules/"
    near = instruction_files_near_their_limit({
        "CLAUDE.md": "word " * 5451, rules + "full.md": "x" * 31501, rules + "roomy.md": "x" * 31500, rules + "over.md": "é" * 32001,
        rules + "nested/deeper.md": "x" * 31999, "Tests/CLAUDE.md": "x" * 1401, "Sources/CLAUDE.md": "x" * 1400, "Documentation/Manual.md": "x" * 99999,
    }, {rules + "full.md", "Tests/CLAUDE.md"})
    expect("instruction files within their margin of the limit, fullest first, as the check measures them", near, [
        (rules + "over.md", 32001, 32000, "characters", False), ("CLAUDE.md", 5451, 5500, "words", False), ("Tests/CLAUDE.md", 1401, 1500, "characters", True),
        (rules + "full.md", 31501, 32000, "characters", True),
    ])
    expect("a block that names them", block({**record, "near limit": near}), ("\n".join([
        "Pre-review block",
        f"head: {head} (claude/x), 3 commit(s) measured from origin/main at 123456789",
        "lint: passed, 9 s",
        "touched suites: passed, 1 min 5 s: ok",
        "pins: not owed: the change touches nothing a corpus draws from or runs",
        "to trim or split before review: 2 instruction file(s) this change edits at or near the limit",
        "  Tests/CLAUDE.md: 1,401 of 1,500 characters",
        "  .claude/rules/full.md: 31,501 of 32,000 characters",
        "instruction files near their limit, not edited here: .claude/rules/over.md (1 characters over), CLAUDE.md (49 words left)",
        "result: READY",
    ]), True))
    listed = {**record, "uncommitted": True, "steps": {"lint": ("passed, 9 s", True)}, "sorts": [("Sources/A.swift", 3, "x.sorted { $0.label < $1.label }")], "tests": [("Tests/B.swift", 7, "a_picksTheFirst_whenTwo")]}
    expect("a block that is not ready, with its lists", block(listed), ("\n".join([
        "Pre-review block",
        f"head: {head} (claude/x), 3 commit(s) measured from origin/main at 123456789",
        "uncommitted changes in the checkout: they are not this head's, and no check saw them",
        "lint: passed, 9 s",
        "touched suites: not run",
        "pins: not run",
        "to justify in the hand-back: 1 added choice(s) keyed on a label, a name or a position",
        "  Sources/A.swift:3: x.sorted { $0.label < $1.label }",
        "to give the candidate count of in the hand-back: 1 added test(s) of a choice or an order",
        "  Tests/B.swift:7: a_picksTheFirst_whenTwo",
        "result: NOT READY",
    ]), False))
    expect("a record survives being saved", block(json.loads(json.dumps(listed))), block(listed))
    listing = block({**record, "undrawn": ["Changed generator lines that no fuzzer corpus graph executed.", "R1 Sources/SafeDICore/A.swift:4 (1 line(s)) in f()"]})
    expect("a block lists the runs no graph executed, and is ready", (listing[0].splitlines()[-4:], listing[1]), (
        ["to give each run's disposition in the hand-back (.claude/rules/fuzzer-corpora.md, \"Coverage of a change\"):", "  Changed generator lines that no fuzzer corpus graph executed.", "  R1 Sources/SafeDICore/A.swift:4 (1 line(s)) in f()", "result: READY"],
        True,
    ))
    nothing_undrawn = block({**record, "undrawn": ["Changed generator lines that no fuzzer corpus graph executed.", "Dispose of each run before review.", "3 changed executable generator line(s); the corpus executed 3, the unit suite 0 more."]})
    expect("a report with no run gives its count and no instruction", (nothing_undrawn[0].splitlines()[-2:], nothing_undrawn[1]), (
        ["fuzzer coverage of the change: 3 changed executable generator line(s); the corpus executed 3, the unit suite 0 more.", "result: READY"],
        True,
    ))
    unread = block({**record, "undrawn error": "not read (no artifact). Run this command again with --report"})
    expect("a coverage report that could not be read is not ready", (unread[0].splitlines()[-2:], unread[1]), (
        ["fuzzer coverage of the change: not read (no artifact). Run this command again with --report", "result: NOT READY"],
        False,
    ))
    covered = block({**record, "steps": {**record["steps"], "changed-line coverage": ("failed, 9 min 2 s: 2 changed line(s) no test executed", False)}})
    expect("changed-line coverage is a step only when asked for", (["changed-line coverage" in line for line in block(record)[0].splitlines()].count(True), covered[0].splitlines()[-3], covered[1]), (
        0, "changed-line coverage: failed, 9 min 2 s: 2 changed line(s) no test executed", False,
    ))
    matrix = "\n".join([
        "| Cell | Shape | Handwritten |",
        "|---|---|---|",
        "| 6.1 | A mock | yes |",
        "| 6.2 | A static call (as 6.1) | yes |",
        "| 6.11 | A level that reopens | yes |",
        "| 6.12 | Rule Q | yes |",
        "| 6.13 | Tiers | yes |",
        "| M1 | not a cell | |",
    ])
    hand_back = "\n".join([
        "- 6.1: `generate_takesBuilder_whenMockHasPlace` fails first, passes after.",
        "- 6.2 is done.",
        "- 6.11 (b): stopped, owned by slice 7.",
        "- 6.12 (c) and 6.13 roll: seed 454 fails with the fix reverted.",
        "- 16.12: `another_cell_entirely_whenNamed`.",
    ])
    expect("cells the hand-back does not account for: one it only mentions, one whose line's seed is another cell's", cells_unaccounted_for(matrix, hand_back), ["6.2", "6.12"])
    expect("a range accounts for each cell in it", cells_unaccounted_for(matrix, "- 6.1–6.2: unchanged.\n- 6.11-6.13: seed 7 reproduces."), [])
    expect("an identifier that is no test name, and an outcome word used otherwise, account for nothing", cells_unaccounted_for(matrix, "- 6.1: ran with `SAFEDI_VERIFY_RUNNER` set\n- 6.2: the stopped CI run was retried\n- 6.11: hand edit; 6.12: `a_b_whenC` and 6.13 `x_y_whenZ`"), ["6.1", "6.2", "6.11"])
    expect("a version number names no cell, and the word cell does", cells_unaccounted_for(matrix, "Built with Swift 6.2: unchanged. Under 6.11 `a_b_whenC` nothing moved.\nFor cell 6.1 see `a_b_whenC`; cells 6.12 and 6.13: unchanged."), ["6.2", "6.11", "6.12"])
    expect("every cell, with no hand-back", cells_unaccounted_for(matrix, ""), ["6.1", "6.2", "6.11", "6.12", "6.13"])
    expect("a block that lists cells", block({**record, "cells": ["6.2", "6.9"]})[0].splitlines()[-2], "to account for in the hand-back: 2 matrix cell(s) with no test, seed or outcome named: 6.2, 6.9")
    def pull(number, head, base, files):
        return {"number": number, "head": head, "commit": f"commit-of-{head}", "base": base, "name": f"#{number} ({head})", "files": files}

    pulls = [
        pull(757, "slice-3", "main", ["Tests/SafeDIToolTestSupport/GraphFuzzer.swift", "Sources/SafeDICore/Generators/ScopeGenerator.swift"]),
        pull(760, "retry-fix", "slice-3", [".github/workflows/ci.yml"]),
        pull(759, "side-by-side", "retry-fix", ["Tests/SafeDIToolTestSupport/GraphFuzzer.swift"]),
        pull(761, "docs", "main", ["README.md", ".github/workflows/ci.yml"]),
        pull(758, "sibling", "slice-3", ["CLAUDE.md"]),
    ]
    expect("a stack is the branches below and above, by the pull requests' bases", sorted(stack_of("retry-fix", None, pulls)), ["retry-fix", "side-by-side", "slice-3"])
    expect("a pull request that shares this branch's base is a sibling, outside its stack", "sibling" in stack_of("retry-fix", None, pulls) or "sibling" in stack_of("side-by-side", None, pulls), False)
    expect("the bottom of a stack has everything based on it above it", sorted(stack_of("slice-3", None, pulls)), ["retry-fix", "sibling", "side-by-side", "slice-3"])
    expect("a pull request on main is in no other's stack", sorted(stack_of("docs", "main", pulls)), ["docs"])
    expect("a branch with no pull request is stacked on the branch its base names", sorted(stack_of("new", "side-by-side", pulls)), ["new", "retry-fix", "side-by-side", "slice-3"])
    now = 1_800_000_000
    branches = {"main": ("m", now), "docs": ("d", now), "lane": ("l", now - 3600), "yesterday": ("o", now - 25 * 3600), "landed": ("x", now - 60), "slice-3": ("s", now), "verify/abc-1": ("v", now), "probe/x": ("p", now), "coverage/y": ("c", now), "verified-idea": ("i", now)}
    expect("BASE as origin/NAME, as a bare branch name, as an open pull request's commit, and as neither", [base_branch_of(name, commit, pulls, branches) for name, commit in (("origin/slice-3", "x"), ("lane", "x"), ("0123abc", "commit-of-retry-fix"), ("0123abc", "y"), ("origin/main", "m"))], ["slice-3", "lane", "retry-fix", None, "main"])
    at_lane = {**branches, "lane-copy": ("l", now), "verify/l-1": ("l", now)}
    expect("BASE as the commit a branch with no pull request is at: the first by name of those there, never a scratch ref", [base_branch_of("0123abc", commit, pulls, at_lane, ["verify/"]) for commit in ("l", "x", "v")], ["lane", "landed", None])
    expect("a bare BASE whose local branch is elsewhere than the remote's is measured from the remote's, and says so", [remote_base(*arguments) for arguments in (
        ("slice-3", "a" * 40, "b" * 40),
        ("slice-3", "", "b" * 40),
        ("slice-3", "a" * 40, "a" * 40),
        ("local-only", "a" * 40, ""),
        ("origin/slice-3", "", "b" * 40),
        ("HEAD~1", "", ""),
    )], [
        ("origin/slice-3", "the local slice-3 is at aaaaaaaaa, not at origin/slice-3's bbbbbbbbb, so this measures from origin/slice-3"),
        ("origin/slice-3", None),
        ("slice-3", None),
        ("local-only", None),
        ("origin/slice-3", None),
        ("HEAD~1", None),
    ])
    noted = block({**record, "base": "origin/slice-3 at bbbbbbbbb", "base note": remote_base("slice-3", "a" * 40, "b" * 40)[1]})[0].splitlines()
    expect("a block names the base it measured from, and why it is not the one given", noted[1:3], [
        f"head: {head} (claude/x), 3 commit(s) measured from origin/slice-3 at bbbbbbbbb",
        "base: the local slice-3 is at aaaaaaaaa, not at origin/slice-3's bbbbbbbbb, so this measures from origin/slice-3",
    ])
    workflow = "    if: ${{ always() && (startsWith(github.ref_name, 'verify/') || startsWith(github.ref_name, 'probe/') || startsWith(github.ref_name, 'coverage/')) }}\n    if: startsWith(github.ref, 'refs/tags/')"
    expect("the scratch prefixes a workflow deletes", scratch_prefixes([workflow, "name: CI"]), ["coverage/", "probe/", "verify/"])
    answer = {"workflows": {"entries": [
        {"name": "verify.yml", "object": {"text": workflow}},
        {"name": "README.md", "object": {"text": "startsWith(github.ref_name, 'docs/')"}},
        {"name": "ci.yml", "object": {"text": "name: CI"}},
        {"name": "binary.yml", "object": {"text": None}},
        {"name": "folder.yml", "object": {}},
    ]}}
    expect("main's workflows on the remote, in name order, the .yml files with text only", workflow_texts(answer), ["name: CI", workflow])
    expect("no workflows when main has none", (workflow_texts({"workflows": None}), workflow_texts({})), ([], []))
    workflows = pathlib.Path(__file__).resolve().parents[3] / ".github/workflows"
    expect("this repository's workflows name their scratch prefixes", scratch_prefixes(path.read_text() for path in sorted(workflows.glob("*.yml"))), ["coverage/", "probe/", "verify/"])
    asked = []

    def answering(*answers):
        remaining = list(answers)

        def ask(*arguments, seconds=None):
            asked.append(arguments[1])
            answer = remaining.pop(0)
            if isinstance(answer, str):
                return answer
            raise answer
        return ask

    gone = RuntimeError("gh: No commit found for SHA: g0 (HTTP 404)")
    compared = '{"files": [["a.swift", null], ["b.swift", "old/b.swift"]], "commits": ["c1", "c2"], "total_commits": 2}'
    read_back = {"files": ["a.swift", "b.swift", "old/b.swift"], "commits": ["c1", "c2"], "cut": []}
    expect("a commit GitHub does not have is not read, and is asked for once", (compare_of("main", "g0", answering(gone)), len(asked)), (None, 1))
    expect("a request that fails otherwise, with a 404 elsewhere in its text, is asked once more", (compare_of("main", "f0", answering(RuntimeError("HTTP 502: run 4040 failed"), compared)), len(asked)), (read_back, 3))
    expect("a branch that fails twice is not read", (compare_of("main", "d0", answering(RuntimeError("HTTP 502"), RuntimeError("gh api: TimeoutExpired"))), len(asked)), (None, 5))
    expect("an answer that is not JSON is asked once more", (compare_of("main", "b0", answering("<html>", compared))["files"], len(asked)), (["a.swift", "b.swift", "old/b.swift"], 7))
    expect("a compare is asked by commit, and a moved file is at both its paths", (compare_of("C5", "C6", answering(compared)), asked[-1]), (read_back, "repos/{owner}/{repo}/compare/C5...C6"))
    many = json.dumps({"files": [[f"f{number}.swift", None] for number in range(FILES_OF_A_COMPARE)], "commits": [f"c{number}" for number in range(COMMITS_OF_A_COMPARE)], "total_commits": 260})
    expect("a compare GitHub cut says what it cut", compare_of("main", "h0", answering(many))["cut"], ["300 files or more", "250 of 260 commits"])
    expect("a request is given what is left until the deadline, at most a minute, and none once it has passed", [
        asking_before(10.0, lambda: 0.0, lambda *arguments, seconds: seconds)("api"),
        asking_before(100.0, lambda: 0.0, lambda *arguments, seconds: seconds)("api"),
    ], [10.0, 60])
    try:
        asking_before(10.0, lambda: 10.0, lambda *arguments, seconds: "asked")("api")
        expect("a request after the deadline is not asked", "asked", "Late")
    except Late:
        pass
    stack = stack_of("docs", "main", pulls)
    expect("lane branches: recent, never a pull request's head, no scratch ref, outside the stack; the older ones counted, and the recent ones a closed or merged pull request named", lane_branches(branches, pulls, stack, {"landed", "slice-3"}, ["coverage/", "probe/", "verify/"], now), (["lane", "verified-idea"], 1, 1))
    expect("what was read, with branches a closed or merged pull request named", overlap_summary([], [], [], [], once_a_head=2), "0 pull request(s) and 0 branch(es) without one read; 2 branch(es) not read, named as a closed or merged pull request's head")
    outside = [each for each in pulls if each["head"] not in stack]
    lanes = [{"name": "branch lane", "files": ["README.md", "Sources/SafeDICore/Models/Property.swift"]}, {"name": "branch a-lane", "files": ["README.md"]}]
    expect("each shared file with who has it: pull requests first by number, then branches by name; no pins line for a change that owes none", overlaps(["README.md", ".github/workflows/ci.yml", "CLAUDE.md"], False, outside, lanes, globs), [".github/workflows/ci.yml: #760 (retry-fix)", "CLAUDE.md: #758 (sibling)", "README.md: branch a-lane, branch lane"])
    expect("two changes that owe pins share the pins with no file in common: the pull requests named, the lane branches counted", overlaps(["Sources/SafeDICore/Models/Dependency.swift"], True, outside, lanes + [{"name": "branch z-lane", "files": ["Package.swift"]}], globs), ["the fuzzer's pins, which each of these also owes a run of: #757 (slice-3), #759 (side-by-side)", "the fuzzer's pins, which 2 branch(es) without a pull request also owe a run of"])
    expect("holders of one file are in pull request number order", overlaps(["Tests/SafeDIToolTestSupport/GraphFuzzer.swift"], False, list(reversed(outside)), [], globs), ["Tests/SafeDIToolTestSupport/GraphFuzzer.swift: #757 (slice-3), #759 (side-by-side)"])
    expect("no overlap with nothing open", overlaps(["README.md"], True, [], [], globs), [])
    expect("what was read, with a branch that went away while it was read", overlap_summary(outside, lanes[:1], ["gone-lane", "a-gone"], []), "4 pull request(s) and 1 branch(es) without one read; 2 branch(es) not read, gone or unreadable: a-gone, gone-lane")
    expect("what was read, with a pull request of a hundred files", overlap_summary(outside[:1], [], [], ["#757 (slice-3)"]), "1 pull request(s) and 0 branch(es) without one read; only the first 100 files of #757 (slice-3)")
    expect("what was read, with branches left out", overlap_summary(outside[:1], lanes, [], [], 3), "1 pull request(s) and 2 branch(es) without one read; 3 branch(es) left out, at another change's head or built on this one")
    expect("what was read, with the branch list cut, older branches, late branches and cut compares", overlap_summary(outside[:1], lanes, [], [], 0, 4, ["z-late", "a-late"], [("huge", "300 files or more")], (2000, 2500)), "1 pull request(s) and 2 branch(es) without one read; only 2000 of the remote's 2500 branches listed; 4 branch(es) older than a day not read; 2 branch(es) not read within 60 s: a-late, z-late; GitHub cut the compare of huge (300 files or more)")
    expect("branches at one commit are one change, named together", lane_groups(["b-twin", "lane", "a-twin"], {"a-twin": ("t", now), "b-twin": ("t", now), "lane": ("l", now)}), [
        {"name": "branch a-twin = b-twin", "branch": "a-twin", "commit": "t"},
        {"name": "branch lane", "branch": "lane", "commit": "l"},
    ])
    # A stack slice-3 <- retry-fix <- this change `mine` (head H, an older push at MR) <- upper; open pull requests'
    # heads at commit-of-*; a branch the list does not read at LP0, a scratch ref at VX, and a merged pull request's
    # head at MG.
    lane_names = ["on-main", "on-pull", "on-lane", "at-pull", "above", "at-base", "on-base", "beside", "on-old-push", "on-upper", "on-other", "on-scratch", "on-merged"]
    lane_commits = {
        "on-main": "om", "on-pull": "op", "on-lane": "ol", "at-pull": "commit-of-docs", "above": "ab", "at-base": "commit-of-retry-fix", "on-base": "ob", "beside": "op",
        "on-old-push": "mo", "on-upper": "uo", "on-other": "oo", "on-scratch": "so", "on-merged": "mg1",
    }
    groups = lane_groups(lane_names, {name: (commit, now) for name, commit in lane_commits.items()})
    remote = {"main": ("m", now), "slice-3": ("commit-of-slice-3", now), "retry-fix": ("commit-of-retry-fix", now), "mine": ("MR", now), "upper": ("UP", now), "other": ("LP0", now), "verify/x": ("VX", now), **{name: (commit, now) for name, commit in lane_commits.items()}}
    known = known_heads("H", "commit-of-retry-fix", {"slice-3", "retry-fix"}, {"slice-3", "retry-fix", "mine", "upper"}, remote, pulls, groups, [(700, "MG")])
    histories = {
        "on-main": ["m1", "om"],
        "beside": ["d0", "commit-of-docs", "op"],
        "on-lane": ["d0", "commit-of-docs", "op", "o1", "ol"],
        "at-pull": ["d0", "commit-of-docs"],
        "above": ["s1", "commit-of-slice-3", "commit-of-retry-fix", "H", "ab"],
        "at-base": ["s1", "commit-of-slice-3", "commit-of-retry-fix"],
        "on-base": ["s1", "commit-of-slice-3", "commit-of-retry-fix", "ob"],
        "on-old-push": ["s1", "commit-of-slice-3", "commit-of-retry-fix", "MR", "mo"],
        "on-upper": ["s1", "commit-of-slice-3", "commit-of-retry-fix", "H", "UP", "uo"],
        "on-other": ["LP0", "oo"],
        "on-scratch": ["VX", "so"],
        "on-merged": ["MG", "mg1"],
    }
    expect("where each lane branch's own changes start: main; the newest head in its history of a change the list reads or a merged pull request; or left out at another change's head or above this one", {group["name"]: lane_start(group, histories[group["branch"]], known) for group in groups}, {
        "branch above": None,
        "branch at-base": None,
        "branch at-pull": None,
        "branch on-base": "commit-of-retry-fix",
        "branch on-lane": "op",
        "branch on-main": "main",
        "branch beside = on-pull": "commit-of-docs",
        "branch on-old-push": None,
        "branch on-upper": None,
        "branch on-other": "main",
        "branch on-scratch": "main",
        "branch on-merged": "MG",
    })
    fuzzer_file = "Tests/SafeDIToolTestSupport/GraphFuzzer.swift"
    moment = [0.0]

    def github(workflows, late_after_branches=False):
        """Answers the overlap's requests as GitHub would, for a change `mine` at H measured from main, listing the
        branches in two pages. With `late_after_branches`, the clock passes the deadline as the last page answers."""
        recent, old = "2026-11-17T05:00:00Z", "2026-11-14T05:00:00Z"
        refs = [
            ("main", "M", recent), ("mine", "H", recent), ("slice-3", "S3", recent), ("side", "P9", recent), ("landed", "L", recent), ("old", "O", old), ("chain-s5", "C5", recent),
            ("chain-s6", "C6", recent), ("twin-b", "T", recent), ("twin-a", "T", recent), ("backup", "P9", recent), ("above", "AB", recent), ("verify/abc", "V", recent), ("probe/x", "H", recent),
            ("lane-pins", "LP", recent), ("gone-lane", "G", recent), ("on-landed", "OL", recent), ("on-old", "OD", recent), ("huge", "HU", recent), ("mover", "MV", recent),
        ]
        pages = [refs[:9], refs[9:]]
        compares = {
            "main...C5": ([fuzzer_file, "Sources/A.swift"], ["s0", "S3", "C5"]), "S3...C5": (["Sources/A.swift"], ["C5"]),
            "main...C6": ([fuzzer_file, "Sources/A.swift", "README.md"], ["s0", "S3", "C5", "C6"]), "C5...C6": ([fuzzer_file], ["C6"]),
            "main...T": (["README.md"], ["T"]), "main...P9": (["Package.swift"], ["P9"]), "main...AB": ([fuzzer_file], ["H", "AB"]),
            "main...LP": (["Sources/B.swift"], ["LP"]), "main...V": (["Sources/C.swift"], ["V"]), "main...H": ([fuzzer_file], ["H"]),
            "main...OL": ([fuzzer_file, "Sources/D.swift"], ["LH", "OL"]), "LH...OL": (["Sources/D.swift"], ["OL"]),
            "main...OD": ([fuzzer_file, "README.md"], ["O", "OD"]),
            "main...HU": ([f"f{number}.swift" for number in range(FILES_OF_A_COMPARE)], [f"c{number}" for number in range(COMMITS_OF_A_COMPARE)]),
            "main...MV": (["Sources/New.swift"], ["MV"]),
        }
        moved = {"Sources/New.swift": fuzzer_file}
        open_pulls = [
            {"number": 759, "headRefName": "side", "headRefOid": "P9", "baseRefName": "main", "files": [{"path": "Package.swift"}]},
            {"number": 757, "headRefName": "slice-3", "headRefOid": "S3", "baseRefName": "main", "files": [{"path": fuzzer_file}]},
        ]
        every_pull = [
            {"number": 757, "headRefName": "slice-3", "headRefOid": "S3", "state": "OPEN"}, {"number": 759, "headRefName": "side", "headRefOid": "P9", "state": "OPEN"},
            {"number": 700, "headRefName": "landed", "headRefOid": "LH", "state": "MERGED"},
        ]
        compared, pages_asked = [], []

        def ask(*arguments, seconds=None):
            if arguments[:2] == ("pr", "list"):
                return json.dumps(open_pulls if arguments[3] == "open" else every_pull)
            if arguments[1] == "graphql":
                options = dict(argument.split("=", 1) for argument in arguments if "=" in argument and not argument.startswith("query="))
                query = next(argument for argument in arguments if argument.startswith("query="))
                page = 0 if "after" not in options else int(options["after"].removeprefix("cursor-"))
                pages_asked.append((options.get("after"), options["workflows"], "orderBy" in query))
                if page == len(pages) - 1 and late_after_branches:
                    moment[0] = 61.0
                repository = {"refs": {"totalCount": len(refs), "pageInfo": {"hasNextPage": page + 1 < len(pages), "endCursor": f"cursor-{page + 1}"}, "nodes": [{"name": name, "target": {"oid": oid, "committedDate": date}} for name, oid, date in pages[page]]}}
                if options["workflows"] == "true":
                    repository["workflows"] = workflows
                return json.dumps({"data": {"repository": repository}})
            comparison = arguments[1].removeprefix("repos/{owner}/{repo}/compare/")
            compared.append(comparison)
            if comparison not in compares:
                raise RuntimeError("gh: Not Found (HTTP 404)")
            files, commits = compares[comparison]
            return json.dumps({"files": [[path, moved.get(path)] for path in files], "commits": commits, "total_commits": len(commits) + (10 if len(commits) == COMMITS_OF_A_COMPARE else 0)})
        return ask, compared, pages_asked

    six_in_the_morning = calendar.timegm(time.strptime("2026-11-17T06:00:00Z", "%Y-%m-%dT%H:%M:%SZ"))
    overlap_record = {"head": "H", "branch": "mine", "base name": "origin/main", "base commit": "M", "changed": [fuzzer_file], "owes pins": True}

    def overlap_with(workflows, late_after_branches=False):
        ask, compared, pages_asked = github(workflows, late_after_branches)
        moment[0] = 0.0
        found = overlap_of(overlap_record, globs, ask, lambda: six_in_the_morning, lambda: moment[0], 60.0)
        return found, sorted(compared), pages_asked

    main_workflows = {"entries": [{"name": "verify.yml", "object": {"text": workflow}}]}
    expect("the overlap of a change on main: open pull requests named; lane branches read at their commits, every page of them, measured from the change they are built on (a listed one or a merged pull request), one per commit, a moved file at both paths, those at another change's head or above this one left out, the older ones counted, and counted on the pins line; scratch refs by main's workflows on the remote", overlap_with(main_workflows), ((
        "2 pull request(s) and 8 branch(es) without one read; 1 branch(es) older than a day not read; 1 branch(es) not read, named as a closed or merged pull request's head; 2 branch(es) left out, at another change's head or built on this one; 1 branch(es) not read, gone or unreadable: gone-lane; GitHub cut the compare of huge (300 files or more, 250 of 260 commits)",
        [
            f"{fuzzer_file}: #757 (slice-3)",
            "the fuzzer's pins, which each of these also owes a run of: #757 (slice-3), #759 (side)",
            f"{fuzzer_file}: branch chain-s6, branch mover, branch on-old",
            "the fuzzer's pins, which 6 branch(es) without a pull request also owe a run of",
        ],
    ), ["C5...C6", "LH...OL", "S3...C5", "main...AB", "main...C5", "main...C6", "main...G", "main...HU", "main...LP", "main...MV", "main...OD", "main...OL", "main...P9", "main...T"], [(None, "true", False), ("cursor-1", "false", False)]))
    expect("scratch refs are read from main's workflows on the remote, whatever the checkout's say", overlap_with({"entries": []})[0], (
        "2 pull request(s) and 9 branch(es) without one read; 1 branch(es) older than a day not read; 1 branch(es) not read, named as a closed or merged pull request's head; 3 branch(es) left out, at another change's head or built on this one; 1 branch(es) not read, gone or unreadable: gone-lane; GitHub cut the compare of huge (300 files or more, 250 of 260 commits)",
        [
            f"{fuzzer_file}: #757 (slice-3)",
            "the fuzzer's pins, which each of these also owes a run of: #757 (slice-3), #759 (side)",
            f"{fuzzer_file}: branch chain-s6, branch mover, branch on-old",
            "the fuzzer's pins, which 7 branch(es) without a pull request also owe a run of",
        ],
    ))
    expect("branches not compared by the deadline are named, and nothing is asked after it", overlap_with(main_workflows, late_after_branches=True)[:2], ((
        "2 pull request(s) and 0 branch(es) without one read; 1 branch(es) older than a day not read; 1 branch(es) not read, named as a closed or merged pull request's head; 11 branch(es) not read within 60 s: above, backup, chain-s5, chain-s6, gone-lane, huge, lane-pins, mover, on-landed, on-old, twin-a = twin-b",
        [f"{fuzzer_file}: #757 (slice-3)", "the fuzzer's pins, which each of these also owes a run of: #757 (slice-3), #759 (side)"],
    ), []))
    expect("lists not answered by the deadline leave the overlap not checked", overlap_of(overlap_record, globs, github(main_workflows)[0], lambda: six_in_the_morning, lambda: 60.0, 60.0), ("not checked: GitHub did not list the pull requests and branches within 60 s", []))

    def endless(*arguments, seconds=None):
        page = {"totalCount": 2500, "pageInfo": {"hasNextPage": True, "endCursor": "next"}, "nodes": [{"name": f"b{len(asked)}-{number}", "target": {"oid": "o"}} for number in range(100)]}
        asked.append(arguments[1])
        return json.dumps({"data": {"repository": {"refs": page}}})
    asked.clear()
    expect("a branch list longer than its pages is cut, and says so", (branch_list(endless)[2], len(asked)), ((2000, 2500), PAGES_OF_BRANCHES))

    def hanging(*arguments, seconds=None):
        time.sleep(1)
        return "[]"
    expect("an overlap still unanswered at its deadline is not waited for", start_overlap(overlap_record, globs, hanging, seconds=0.05)(grace=0.05)[0], ("not checked: GitHub did not answer within 0.05 s", []))
    before = time.time()
    take = start_overlap(overlap_record, globs, answering(RuntimeError("HTTP 502")))
    started = time.time()
    taken, asked_at = take()
    expect("an overlap answered in its thread is taken, dated when it was asked", (taken, before <= asked_at <= started), (("not checked: HTTP 502", []), True))
    expect("an error the overlap does not expect is reported as itself, not as GitHub's silence", start_overlap(overlap_record, globs, answering(ZeroDivisionError("boom")))()[0], ("not checked: ZeroDivisionError: boom", []))
    expect("a deadline other than a minute is the one the block names", (
        overlap_of(overlap_record, globs, github(main_workflows)[0], lambda: six_in_the_morning, lambda: 20.0, 20.0, seconds=20)[0],
        overlap_summary([], [], [], [], late=["x"], seconds=20),
    ), ("not checked: GitHub did not list the pull requests and branches within 20 s", "0 pull request(s) and 0 branch(es) without one read; 1 branch(es) not read within 20 s: x"))
    # The workers of an overlap whose run failed do not hold the process: with a ThreadPoolExecutor's, it would wait
    # for the hanging requests.
    holding = "import importlib.util, sys, threading, time\nspec = importlib.util.spec_from_file_location('pre_review', sys.argv[1])\nmodule = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(module)\nthreading.Thread(target=lambda: module.in_daemon_threads(lambda item: time.sleep(30), [1, 2]), daemon=True).start()\ntime.sleep(0.2)\nraise SystemExit(3)\n"
    started = time.time()
    exited = subprocess.run([sys.executable, "-I", "-B", "-c", holding, str(pathlib.Path(__file__).resolve())], capture_output=True, text=True, timeout=60)
    expect("a run that fails while the overlap's requests hang exits at once", (exited.returncode, time.time() - started < 10), (3, True))
    expect("the overlap's answers are in the items' order, and a call that raises gives None", in_daemon_threads(lambda item: 10 // item, [5, 0, 2, 1, 10], workers=3), [2, None, 5, 10, 1])
    kept = {"steps": {"pins": ["in progress, run 7", False]}, "overlap": ["x", []], "overlap at": 1000.0}
    partial = {**kept, "overlap": ["2 pull request(s) and 3 branch(es) without one read; 1 branch(es) not read within 60 s: x", []]}
    expect("the overlap is asked again only when there is none, the pins run's state changed, or it is five minutes old, one when it was partial", [
        overlap_is_stale({"steps": {}}, None, 1000.0),
        overlap_is_stale(kept, ("in progress, run 7", False), 1299.0),
        overlap_is_stale(kept, ["in progress, run 7", False], 1300.0),
        overlap_is_stale({**kept, "steps": {"pins": ("passed, 54 min 10 s, url", True)}}, ["in progress, run 7", False], 1001.0),
        overlap_is_stale({**kept, "steps": {"pins": ("in progress, run 7 (GitHub did not answer: HTTP 502)", False)}}, ["in progress, run 7", False], 1001.0),
        overlap_is_stale(partial, ["in progress, run 7", False], 1059.0),
        overlap_is_stale(partial, ["in progress, run 7", False], 1060.0),
        overlap_is_stale({**kept, "overlap": ["not checked: HTTP 502", []]}, ["in progress, run 7", False], 1060.0),
    ], [True, False, True, True, False, False, True, True])
    shared = overlaps(["README.md", ".github/workflows/ci.yml"], False, outside, lanes, globs)
    expect("a block with overlaps lists them and stays ready", (block({**record, "overlap": ("4 pull request(s) and 2 branch(es) without one read", shared)})[0].splitlines()[-4:-1], block({**record, "overlap": ("x", shared)})[1]), ([
        "to stack on, or to answer in the hand-back: 2 overlap(s) with other open changes (4 pull request(s) and 2 branch(es) without one read)",
        "  .github/workflows/ci.yml: #760 (retry-fix)",
        "  README.md: branch a-lane, branch lane",
    ], True))
    expect("a block with none, and one that could not check, say so in one line", [block({**record, "overlap": (text, [])})[0].splitlines()[-2] for text in ("none (4 pull request(s) and 0 branch(es) without one read)", "not checked: this machine has no gh")], [
        "overlap with other open changes: none (4 pull request(s) and 0 branch(es) without one read)",
        "overlap with other open changes: not checked: this machine has no gh",
    ])
    expect("a saved overlap reads back the same", block(json.loads(json.dumps({**record, "overlap": ("x", shared)}))), block({**record, "overlap": ("x", shared)}))
    expect("durations", [duration(9.4), duration(60), duration(3250)], ["9 s", "1 min 0 s", "54 min 10 s"])

    if failures:
        for failure in failures:
            print(f"self-test failed: {failure}", file=sys.stderr)
        sys.exit(1)
    print("pre-review: self-test passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("base", nargs="?", default="origin/main")
    parser.add_argument("--ref", metavar="BRANCH")
    parser.add_argument("--pins-run", metavar="ID")
    parser.add_argument("--no-wait", action="store_true")
    parser.add_argument("--runner", metavar="COMMAND", default=os.environ.get("SAFEDI_VERIFY_RUNNER", ""))
    parser.add_argument("--matrix", metavar="FILE")
    parser.add_argument("--hand-back", metavar="FILE")
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--coverage", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
    else:
        try:
            run(arguments)
        except RuntimeError as error:
            print(f"pre-review: {error}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
