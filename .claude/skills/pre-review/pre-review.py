#!/usr/bin/env python3
"""Runs the checks a branch owes before it is reviewed, and prints the block its hand-back carries.

    pre-review.py [BASE] [--ref BRANCH] [--pins-run ID] [--no-wait] [--runner COMMAND]
                  [--matrix FILE --hand-back FILE]
    pre-review.py --report
    pre-review.py --self-test

BASE is the commit or branch the change is measured from (default `origin/main`; in a stack, the head of the branch
below, so that the checks and the lists are of this branch's own commits). A base too far down only measures more:
more suites, and pins owed more often. A base that already holds the head measures nothing, and is refused. The
block gives the base's commit and how many commits it measured, for the reviewer to compare with the stack. It runs
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


def block(record):
    """The text a hand-back carries, and whether it says READY."""
    commits = record.get("commits", 0)
    lines = ["Pre-review block", f"head: {record['head']} ({record['branch']}), {commits} commit(s) measured from {record['base']}"]
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
        refresh_pins(record, wait=False)
        finish(record)
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
        "commits": int(output_of("git", "rev-list", "--count", f"{base}..HEAD")),
        "uncommitted": bool(status),
        "steps": {},
        "sorts": choices_keyed_on_a_name(added, lines_of),
        "tests": tests_of_a_choice(added),
    }
    if arguments.matrix:
        record["cells"] = cells_unaccounted_for(pathlib.Path(matrix_path).read_text(), pathlib.Path(hand_back_path).read_text())
    runner = shlex.split(arguments.runner) if arguments.runner else []
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
        except RuntimeError as error:
            # Lint and the suites took minutes: their results are kept when the dispatch fails.
            record["steps"]["pins"] = (f"not run: the dispatch failed ({str(error).splitlines()[-1][:160]}). Dispatch verify.yml with pins=true and base={base[:9]} on {branch} and pass the run's id with --pins-run", False)
            finish(record)
        record["steps"]["pins"] = (f"in progress, run {record['pins run']}", False)
        # Before the wait, so that the run's id outlives anything that stops the wait.
        save(record)
        refresh_pins(record, wait=not arguments.no_wait)
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
