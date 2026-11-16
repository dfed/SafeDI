#!/usr/bin/env python3
"""Moves a branch onto a new base and checks the result, in one command.

    restack-lane.py NEW_BASE [--old-base REV] [--accept-drop] [--skip-compile-checks] [--runner COMMAND]
    restack-lane.py --continue NEW_BASE [--old-base REV] [--accept-drop] [--skip-compile-checks] [--runner COMMAND]
    restack-lane.py --self-test

NEW_BASE is the branch or commit to move onto. A branch `origin` has, named `X` or `origin/X`, is fetched and used at
`origin`'s commit, never at the remote-tracking ref the checkout last saw; given as `X`, the script stops when a local
branch `X` is at another commit. It prints the commit it uses. `--old-base` is the commit the branch's own commits
start after: an ancestor of `HEAD` with at least one commit after it. Without it the script takes the merge base of
`HEAD` and NEW_BASE. A base that was itself rebuilt, the usual case in a stack, no longer holds the commits the branch
sits on, so that merge base is older and the rebase would replay the old base's commits: when the reflog of NEW_BASE's
remote-tracking ref or local branch, or of any other branch or remote-tracking ref at the new base's commit, shows
the branch left it at another commit, the script stops and prints that commit as the `--old-base` to pass, and it
warns when a given `--old-base` is not that commit. A checkout whose reflogs never saw the old base (a fresh clone)
cannot tell: read the list of commits it prints before the rebase. When the old base holds a commit whose subject
the new base lacks (one that moved up the stack, or was dropped), nothing would replay it, so the script names it and
stops with status 1 before the rebase; `--accept-drop` goes on without it. It runs from the checkout's top level, on a branch, with nothing uncommitted and no
untracked file the test step would count as a change (any but those no test reaches).

What it does, stopping at the first step that fails:

1. `git rebase --no-update-refs --no-autostash --onto NEW_BASE OLD_BASE`, after printing the commits it moves and the
   command that undoes it. No other branch moves, whatever `rebase.updateRefs` says. On a conflict it lists the files
   and stops with status 1, the rebase still in progress: resolve, `git rebase --continue` until it ends, then run
   this script again with `--continue`, which skips this step and takes the old base and the branch's earlier head
   from what this step recorded under `.git`. When the rebased branch lacks a commit it had (git drops one whose
   change the new base already holds, and `git rebase --skip` drops one), it names the missing subjects and stops with
   status 1; `--continue --accept-drop` goes on. A signal during the rebase is held until git returns. The record
   is the branch's own, and is removed once every step passed.
2. Fails on a conflict marker left in any file the branch or the base's move touched.
3. Builds the tests and runs the suites the branch touches and the suites the base's move touched, through the
   `verify-touched` skill's script: its runner, its own `TMPDIR` and log, generated code compiled unless
   `--skip-compile-checks`. A compile error is a failure there. The whole suite is not this machine's work: when
   the base's move reaches every test it runs only the suites the branch touches, when the branch's own change
   does it runs none, and either way it prints the full Verify to dispatch.
4. `./CLI/lint.sh --check`, through the runner.

Then it prints the new head. It never pushes: a restacked branch is pushed by whoever owns it, under their own rules.
It does not regenerate expectations: when step 3 fails on expected text the base's move changed, use the
`regenerate-expectations` skill, then run this script again with `--continue`.

`--runner` (or `SAFEDI_VERIFY_RUNNER`) is a command put before `swift test` and the lint, for a machine that queues
heavy work. A signal that ends the script ends what it started, each child in a session of its own.

Exit status: 0 when every step passed, 1 when a step failed (its output says which), 2 for wrong arguments or a
checkout that is not ready, 3 when everything it ran passed and the whole suite is still owed.
"""

import argparse
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

def load_verify_touched():
    path = pathlib.Path(__file__).resolve().parent.parent / "verify-touched" / "verify-touched.py"
    spec = importlib.util.spec_from_file_location("verify_touched", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, path


def git(*arguments, check=True):
    return subprocess.run(["git", *arguments], check=check, capture_output=True, text=True)


def has_conflict_marker(text):
    """Whether `text` holds a line git writes at either end of a conflict: seven `<` or seven `>`, then a space."""
    # Either end counts: a file resolved by hand can keep one of them.
    return bool(re.search(r"^(<{7}|>{7}) ", text, re.MULTILINE))


def files_with_conflict_markers(paths, read_text):
    return sorted(path for path in paths if (text := read_text(path)) is not None and has_conflict_marker(text))


def read_text_in_checkout(path):
    file = pathlib.Path(path)
    if not file.is_file():
        return None
    try:
        return file.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None


def step(title):
    print(f"\n== {title}", flush=True)


def paths_of(*diff_arguments):
    """The paths a `git diff --name-only` lists, a path with a space or a newline in it whole."""
    return set(git("diff", "--name-only", "--no-renames", "-z", *diff_arguments).stdout.split("\0")) - {""}


def commit_of(revision):
    resolved = git("rev-parse", "--verify", "--quiet", f"{revision}^{{commit}}", check=False)
    return resolved.stdout.strip() if resolved.returncode == 0 else None


def new_base_commit(name):
    """The commit to rebase onto, and how it was chosen; or None and what is wrong.

    `NAME` that `origin` has as a branch, or `origin/NAME`, is fetched and used at `origin`'s commit, never at the
    remote-tracking ref this checkout last saw. A local branch `NAME` at another commit is refused, since which of the
    two was meant is the caller's to say; `origin/NAME` says it.
    """
    explicit = name.startswith("origin/")
    branch = name[len("origin/"):] if explicit else name
    # The full name: `--heads X` would also match `refs/heads/other/X`.
    listed = git("ls-remote", "--exit-code", "origin", f"refs/heads/{branch}", check=False)
    # 2 is `--exit-code`'s "no such ref"; anything else is an origin that could not be asked.
    if listed.returncode not in (0, 2):
        return None, f"origin could not be asked for `{branch}`: {listed.stderr.strip()}"
    if listed.returncode == 0:
        fetched = git("fetch", "origin", f"refs/heads/{branch}", check=False)
        if fetched.returncode != 0:
            return None, fetched.stderr.strip()
        remote = git("rev-parse", "FETCH_HEAD").stdout.strip()
        local = commit_of(f"refs/heads/{branch}")
        if not explicit and local is not None and local != remote:
            return None, f"the local branch `{branch}` is at {local} and origin's is at {remote}; pass `origin/{branch}` for origin's, or {local} for yours."
        return remote, f"origin's `{branch}`, fetched now"
    if explicit:
        return None, f"origin has no branch `{branch}`."
    commit = commit_of(name)
    if commit is None:
        return None, f"`{name}` names no commit."
    return commit, "as named; origin has no branch of that name"


def references_named(name):
    branch = name[len("origin/"):] if name.startswith("origin/") else name
    return [f"refs/remotes/origin/{branch}", f"refs/heads/{branch}"]


def references_at(commit, current_branch):
    """The local branches and remote-tracking refs at `commit`, but for the branch being moved."""
    own = {f"refs/heads/{current_branch}", f"refs/remotes/origin/{current_branch}"}
    listed = git("for-each-ref", "--format=%(refname)", "--points-at", commit, "refs/heads", "refs/remotes").stdout.split("\n")
    return [reference for reference in listed if reference and reference not in own and not reference.endswith("/HEAD")]


def fork_points(references):
    """Where `HEAD` left each of `references`, by its reflog here, with the count of commits after it; none when no reflog says.

    A base that was rebuilt, on `origin` or in this repository, no longer holds the commits the branch sits on, so the
    merge base with it is older than where the branch's own commits start, and a rebase from there would replay the
    old base's commits. The reflog of the base's remote-tracking ref or local branch still holds the old tip.
    """
    found = []
    for reference in references:
        if commit_of(reference) is None:
            continue
        point = git("merge-base", "--fork-point", reference, "HEAD", check=False).stdout.strip()
        if point:
            found.append((int(git("rev-list", "--count", f"{point}..HEAD").stdout.strip()), point))
    return found


def untracked_files_a_run_would_take(verify_touched):
    """The untracked files the test step would count as changes: all but those no test reaches.

    The test step counts untracked files, so one would be built, or select suites, or, at a path no rule names, turn
    the step into the whole suite.
    """
    listed = git("ls-files", "--others", "--exclude-standard", "-z").stdout
    taken = []
    for path in sorted(path for path in listed.split("\0") if path):
        unselected = []
        try:
            verify_touched.filters_of_changes({path}, read_text_in_checkout, unselected)
        except verify_touched.WholeSuite:
            pass
        if not unselected:
            taken.append(path)
    return taken


def subjects(revision_range):
    return [line for line in git("log", "--reverse", "--format=%s", revision_range).stdout.split("\n") if line]


def dropped_subjects(before, after):
    """The subjects in `before` that `after` lacks, counting a subject as often as it occurs."""
    remaining = list(after)
    dropped = []
    for subject in before:
        if subject in remaining:
            remaining.remove(subject)
        else:
            dropped.append(subject)
    return dropped


def state_path():
    return pathlib.Path(git("rev-parse", "--git-path", "restack-lane-before").stdout.strip())


def read_state():
    try:
        return json.loads(state_path().read_text())
    except (OSError, ValueError):
        return None


def reports_dropped_commits(old_base, head_before, new_base, accept_drop):
    """Prints the commits the rebase dropped; True when that stops the script."""
    dropped = dropped_subjects(subjects(f"{old_base}..{head_before}"), subjects(f"{new_base}..HEAD"))
    if not dropped:
        return False
    print("The rebase dropped these commits, which git does when the new base already holds their change, or you skipped:")
    for subject in dropped:
        print(f"  {subject}")
    if accept_drop:
        print("Accepted (--accept-drop).")
        return False
    print("If none of them is work the new base lacks, run this script again with --continue --accept-drop.")
    return True


class SignalsHeld:
    """Holds the signals that end the script while git rewrites the branch, and ends the script afterwards.

    Ended inside the rebase, the script would leave it half done with nothing printed about where it stopped. git
    itself still receives a terminal's interrupt, and stops as a conflict does.
    """

    NUMBERS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)

    def __enter__(self):
        self.received = None
        self.previous = {number: signal.signal(number, self.hold) for number in self.NUMBERS}
        return self

    def hold(self, signal_number, _frame):
        self.received = signal_number

    def __exit__(self, *_exception):
        for number, handler in self.previous.items():
            signal.signal(number, handler)


class Children:
    """The process this script waits on, ended when the script is: `swift test` must not outlive a cancelled restack.

    Each child leads a session of its own, so that a signal ends everything it started too.
    """

    def __init__(self):
        self.running = None
        self.previous = {number: signal.signal(number, self.end) for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}

    def restore(self):
        for number, handler in self.previous.items():
            signal.signal(number, handler)

    def end(self, signal_number, _frame):
        # No wait here: the handler can interrupt `communicate` while it holds the lock a wait takes. `run` waits,
        # once the exit raised here has left `communicate`.
        self.terminate(signal.SIGTERM)
        sys.exit(128 + signal_number)

    def terminate(self, signal_number):
        if self.running is not None and self.running.poll() is None:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(self.running.pid, signal_number)

    def run(self, command, **options):
        self.running = subprocess.Popen(command, start_new_session=True, **options)
        try:
            output, _ = self.running.communicate()
        except BaseException:
            try:
                self.running.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.terminate(signal.SIGKILL)
                self.running.wait()
            raise
        status = self.running.returncode
        self.running = None
        return status, output


def moved(arguments, verify_touched):
    """Checks the checkout and the arguments and rebases; returns a status to exit with, or the two bases."""
    if git("status", "--porcelain", "--untracked-files=no").stdout.strip():
        print("restack-lane: the checkout has uncommitted changes; commit or stash them first.", file=sys.stderr)
        return 2
    untracked = untracked_files_a_run_would_take(verify_touched)
    if untracked:
        print("restack-lane: untracked files the test step would count as changes; commit or remove them first:\n  " + "\n  ".join(untracked), file=sys.stderr)
        return 2
    rebase_in_progress = any(pathlib.Path(git("rev-parse", "--git-path", name).stdout.strip()).exists() for name in ("rebase-merge", "rebase-apply"))
    if rebase_in_progress:
        print("restack-lane: a rebase is in progress; finish it with `git rebase --continue`, then pass --continue.", file=sys.stderr)
        return 2
    current_branch = git("symbolic-ref", "--quiet", "--short", "HEAD", check=False).stdout.strip()
    if not current_branch:
        print("restack-lane: HEAD is detached; check out the branch to move.", file=sys.stderr)
        return 2

    # Asked of the refs NEW_BASE names before the fetch, which moves the remote-tracking ref, and afterwards of every
    # ref at the new base, which finds a base named by its commit and a lower branch rebuilt here and not pushed.
    found = [] if arguments.resume else fork_points(references_named(arguments.new_base))
    new_base, how = new_base_commit(arguments.new_base)
    if new_base is None:
        print(f"restack-lane: {how}", file=sys.stderr)
        return 2
    print(f"New base: {new_base} ({how}).")
    if not arguments.resume:
        found += fork_points(references_at(new_base, current_branch))
    # The latest of them: the branch's own commits start after the last tip of the base it held.
    forked_at = min(found)[1] if found else None

    old_base = None
    if arguments.old_base:
        old_base = commit_of(arguments.old_base)
        if old_base is None:
            print(f"restack-lane: `{arguments.old_base}` names no commit.", file=sys.stderr)
            return 2

    if arguments.resume:
        if git("merge-base", "--is-ancestor", new_base, "HEAD", check=False).returncode != 0:
            print(f"restack-lane: --continue, but HEAD is not on {new_base[:9]}.", file=sys.stderr)
            return 2
        state = read_state()
        if state is not None and (state.get("new_base") != new_base or state.get("branch") != current_branch):
            state = None
        if old_base is None and state is not None:
            old_base = state["old_base"]
            print(f"Old base: {old_base}, as the rebase this script began recorded it.")
        if old_base is None:
            print("Warning: --continue without --old-base, after a rebase this script did not begin, checks only the suites the branch touches, not those the base's move touched, and does not look for dropped commits.")
        elif state is None:
            print("Note: this script did not begin the rebase, so it does not look for dropped commits.")
        elif reports_dropped_commits(old_base, state["head"], new_base, arguments.accept_drop):
            return 1
        return new_base, old_base

    if old_base is None:
        old_base = git("merge-base", "HEAD", new_base).stdout.strip()
        if forked_at is not None and forked_at != old_base:
            print(f"restack-lane: `{arguments.new_base}` was rebuilt since this branch was made on it: the branch left it at {forked_at}, and its merge base with the new one is {old_base[:9]}, so a rebase from there would replay the old base's commits. Pass --old-base {forked_at}", file=sys.stderr)
            return 2
    elif forked_at is not None and forked_at != old_base:
        print(f"Warning: --old-base is {old_base[:9]}, and by its reflog the branch left `{arguments.new_base}` at {forked_at[:9]}. Read the list of commits below.")
    if git("merge-base", "--is-ancestor", old_base, "HEAD", check=False).returncode != 0:
        print(f"restack-lane: the old base {old_base[:9]} is not an ancestor of HEAD.", file=sys.stderr)
        return 2
    before = int(git("rev-list", "--count", f"{old_base}..HEAD").stdout.strip())
    if before == 0:
        print(f"restack-lane: no commit follows the old base {old_base[:9]}; there is nothing to move.", file=sys.stderr)
        return 2
    # A rebuilt base that lost a commit the old one had, which moved up the stack or was dropped: nothing replays it,
    # since it is before the old base, and the new base lacks it.
    fork = git("merge-base", old_base, new_base).stdout.strip()
    lost = dropped_subjects(subjects(f"{fork}..{old_base}"), subjects(f"{fork}..{new_base}"))
    if lost:
        print(f"The old base {old_base[:9]} holds these commits and the new base holds none of their subjects, so the rebase would leave them out:")
        for subject in lost:
            print(f"  {subject}")
        if arguments.accept_drop:
            print("Accepted (--accept-drop).")
        else:
            print("If the branch should carry one of them, pass an --old-base before it. If none of them is wanted, run this script again with --accept-drop.")
            return 1
    undo = git("rev-parse", "HEAD").stdout.strip()
    # `ORIG_HEAD` would do until the next command that sets it, which a resolved conflict can be.
    state_path().write_text(json.dumps({"branch": current_branch, "head": undo, "old_base": old_base, "new_base": new_base}))
    step(f"Rebase onto {new_base[:9]} the {before} commits after {old_base[:9]}")
    print(git("log", "--oneline", "--reverse", f"{old_base}..HEAD").stdout, end="")
    print(f"To undo: git reset --hard {undo}", flush=True)
    # A configured `rebase.updateRefs` would move other branches that point into the range, and an autostash
    # would carry changes this script refused above.
    with SignalsHeld() as signals:
        rebased = subprocess.run(["git", "rebase", "--no-update-refs", "--no-autostash", "--onto", new_base, old_base])
    if signals.received is not None:
        print(f"Signalled during the rebase, which {'ended' if rebased.returncode == 0 else 'stopped'}; nothing was checked. Go on with --continue.", flush=True)
        sys.exit(128 + signals.received)
    if rebased.returncode != 0:
        conflicted = sorted(paths_of("--diff-filter=U"))
        print("Conflicts in:" if conflicted else "The rebase stopped.")
        for path in conflicted:
            print(f"  {path}")
        print("Resolve, `git rebase --continue` until it ends, then run this script again with --continue.")
        return 1
    if reports_dropped_commits(old_base, undo, new_base, arguments.accept_drop):
        return 1
    return new_base, old_base


def run(arguments):
    try:
        os.chdir(git("rev-parse", "--show-toplevel").stdout.strip())
    except subprocess.CalledProcessError as error:
        print(f"restack-lane: {error.stderr.strip()}", file=sys.stderr)
        return 2
    verify_touched, verify_touched_path = load_verify_touched()
    result = moved(arguments, verify_touched)
    if isinstance(result, int):
        return result
    new_base, old_base = result

    lane_paths = paths_of(new_base, "HEAD")
    base_paths = paths_of(old_base, new_base) if old_base else set()

    step("Conflict markers")
    marked = files_with_conflict_markers(lane_paths | base_paths, read_text_in_checkout)
    if marked:
        for path in marked:
            print(f"  {path}")
        print("A conflict marker is left in the files above.")
        return 1
    print(f"None in the {len(lane_paths | base_paths)} files the branch or the base's move touched.")

    runner = shlex.split(arguments.runner)
    children = Children()
    try:
        return checked(arguments, children, runner, verify_touched, verify_touched_path, new_base, lane_paths, base_paths)
    finally:
        children.restore()


def checked(arguments, children, runner, verify_touched, verify_touched_path, new_base, lane_paths, base_paths):
    """Runs the test step and the lint; returns the status to exit with."""
    # verify-touched builds the tests, reports a compile error as a failure, and gives the run its own `TMPDIR`, log,
    # runner and cleanup.
    step("Build, then the suites the branch touches and the suites the base's move touched")
    command = [sys.executable, "-I", str(verify_touched_path), new_base, "--runner", arguments.runner]
    if arguments.skip_compile_checks:
        command.append("--skip-compile-checks")
    owed = None
    try:
        # The branch's own paths are verify-touched's to select; asked here only for whether they reach every test.
        verify_touched.filters_of_changes(lane_paths, read_text_in_checkout)
    except verify_touched.WholeSuite as reason:
        owed = f"The branch changed {reason}, which reaches every test, so no test runs here."
        command = None
    if command is not None:
        try:
            for pattern in verify_touched.filters_of_changes(base_paths, read_text_in_checkout):
                command += ["--also", pattern]
        except verify_touched.WholeSuite as reason:
            owed = f"The base's move changed {reason}, which reaches every test, so only the suites the branch touches run here."
    if owed is not None:
        branch = git("symbolic-ref", "--quiet", "--short", "HEAD", check=False).stdout.strip()
        print(owed)
        print("The whole suite is a full Verify's work, not this machine's:")
        print(f"  push the branch, then: gh workflow run verify.yml --ref {branch}", flush=True)
    if command is not None:
        status, _ = children.run(command)
        if status != 0:
            return 1

    step("Lint")
    status, output = children.run([*runner, "./CLI/lint.sh", "--check"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if status != 0:
        print(output[-3000:])
        return 1
    print("Clean.")

    head = git("rev-parse", "HEAD").stdout.strip()
    state_path().unlink(missing_ok=True)
    print(f"\nRestacked: {head}")
    print("Not pushed." + ("" if owed is None else " The whole suite is still owed: dispatch the full Verify."))
    return 0 if owed is None else 3


def ended(process_identifier):
    state = subprocess.run(["ps", "-o", "stat=", "-p", str(process_identifier)], capture_output=True, text=True).stdout.strip()
    return state == "" or state.startswith("Z")


def signal_ends_children(expect, root):
    """A signal while a child runs ends the child and what it started, and the script exits, without a hang."""
    identifiers = root / "identifiers"
    child = (
        "import subprocess, sys, time\n"
        "grandchild = subprocess.Popen(['sleep', '300'])\n"
        f"open({str(identifiers)!r}, 'w').write(f'{{grandchild.pid}}')\n"
        "print('started', flush=True)\n"
        "time.sleep(300)\n"
    )
    children = Children()
    timer = threading.Timer(2, os.kill, (os.getpid(), signal.SIGTERM))
    timer.start()
    began = time.monotonic()
    try:
        children.run([sys.executable, "-c", child], stdout=subprocess.PIPE, text=True)
        status = None
    except SystemExit as exit:
        status = exit.code
    finally:
        timer.cancel()
        children.restore()
    expect(status, 128 + signal.SIGTERM, "a signal while a child runs exits the script with the signal's status")
    expect(time.monotonic() - began < 20, True, "and promptly, not at the child's end")
    expect(children.running.poll() is not None, True, "the child has ended and was waited for")
    grandchild = int(identifiers.read_text())
    deadline = time.monotonic() + 10
    while not ended(grandchild) and time.monotonic() < deadline:
        time.sleep(0.1)
    expect(ended(grandchild), True, "what the child started has ended too")


def guards(expect, verify_touched):
    """Runs `moved` and `run` in a repository made for the purpose, once per guard."""
    # A machine that never ran the tests, as a CI runner is, has no caches folder yet.
    verify_touched.caches_directory().mkdir(parents=True, exist_ok=True)
    root = pathlib.Path(tempfile.mkdtemp(prefix="restack-lane-self-test-", dir=verify_touched.caches_directory()))
    start = pathlib.Path.cwd()
    environment = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_EDITOR": "true"}
    saved = {name: os.environ.get(name) for name in environment}
    os.environ.update(environment)

    def commit(name, text="x\n", subject=None):
        file = pathlib.Path(name)
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)
        git("add", name)
        git("commit", "-q", "-m", subject or name)
        return git("rev-parse", "HEAD").stdout.strip()

    def head(revision="HEAD"):
        return git("rev-parse", revision).stdout.strip()

    def options(new_base, old_base, resume, accept_drop, runner=""):
        return argparse.Namespace(new_base=new_base, old_base=old_base, resume=resume, accept_drop=accept_drop, runner=runner, skip_compile_checks=False)

    def status(new_base, old_base=None, resume=False, accept_drop=False):
        with contextlib.redirect_stdout(io.StringIO()) as printed, contextlib.redirect_stderr(printed):
            result = moved(options(new_base, old_base, resume, accept_drop), verify_touched)
        return result, printed.getvalue()

    def status_of_run(new_base, runner=""):
        with contextlib.redirect_stdout(io.StringIO()) as printed, contextlib.redirect_stderr(printed):
            result = run(options(new_base, None, False, False, runner))
        return result, printed.getvalue()

    try:
        signal_ends_children(expect, root)

        origin, work = root / "origin.git", root / "work"
        git("init", "-q", "--bare", "-b", "main", str(origin))
        git("init", "-q", "-b", "main", str(work))
        os.chdir(work)
        git("remote", "add", "origin", str(origin))
        git("config", "advice.detachedHead", "false")
        first = commit("a")
        git("push", "-q", "origin", "main")
        git("checkout", "-q", "-b", "base")
        base_old = commit("b")
        git("push", "-q", "origin", "base")
        git("checkout", "-q", "-b", "lane")
        lane_first = commit("c")
        commit("c2")
        # origin's `base` is rebuilt, as a restacked branch below this one is; the checkout has not fetched it.
        git("checkout", "-q", "-B", "elsewhere", first)
        base_new = commit("b", "rebuilt\n")
        # As another checkout's push leaves it: the remote-tracking ref stays where it was. Set back, since some
        # versions of git move it on a push by path too.
        git("push", "-q", "--force", str(origin), "elsewhere:base")
        git("update-ref", "refs/remotes/origin/base", base_old)
        git("checkout", "-q", "lane")

        expect(head("refs/remotes/origin/base"), base_old, "the remote-tracking ref is stale before `origin/NAME` is first asked for")
        result, text = status("origin/base")
        expect(f"New base: {base_new} " in text, True, "origin/NAME is fetched, not read from the stale remote-tracking ref")
        expect((result, f"--old-base {base_old}" in text), (2, True), "a base rebuilt on origin stops the script without --old-base, and names the commit to pass")
        result, text = status("base")
        expect(result, 2, "a local branch that differs from origin's stops the script")
        expect(base_old in text and base_new in text, True, "and both commits are named")
        result, text = status("origin/base", old_base="lane")
        expect((result, "nothing to move" in text), (2, True), "an old base with no commit after it stops the script")
        expect("Warning: --old-base" in text, True, "an --old-base that is not where the branch left the base is warned about")
        result, text = status("origin/base", old_base="elsewhere")
        expect((result, "not an ancestor" in text), (2, True), "an old base that is no ancestor of HEAD stops the script")
        for path in ("Sources/New.swift", "Plugins/New.swift", "Tests/SomeTests/New.swift", "Package.swift", "unruled.txt"):
            file = pathlib.Path(path)
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("")
            result, text = status("origin/base", old_base="base")
            expect((result, path in text), (2, True), f"the untracked file {path} stops the script")
            file.unlink()
        pathlib.Path("notes.md").write_text("")
        result, text = status("origin/base", old_base="lane")
        expect((result, "nothing to move" in text), (2, True), "an untracked file no test reaches stops nothing")
        pathlib.Path("notes.md").unlink()
        git("checkout", "-q", "--detach")
        result, text = status("origin/base", old_base="base")
        expect((result, "detached" in text), (2, True), "a detached HEAD stops the script")
        git("checkout", "-q", "lane")
        # A branch at a commit the rebase moves, which `rebase.updateRefs` would move with it.
        git("branch", "-q", "bystander", lane_first)
        git("config", "rebase.updateRefs", "true")
        result, text = status("origin/base", old_base="base")
        expect(result, (base_new, base_old), "the rebase uses origin's commit, with the old base as given")
        expect(head("HEAD~2"), base_new, "the branch's two commits sit on origin's commit")
        expect(head("bystander"), lane_first, "a branch inside the moved range did not move")
        expect("To undo: git reset --hard" in text and " c2\n" in text, True, "the undo command and the commits moved are printed")
        git("config", "--unset", "rebase.updateRefs")

        # A lower branch rebuilt in this repository, which origin never had.
        git("checkout", "-q", "-b", "lower", first)
        lower_old = commit("l")
        git("checkout", "-q", "-b", "upper")
        commit("u")
        git("checkout", "-q", "-B", "lower", first)
        lower_new = commit("l", "rebuilt\n")
        git("checkout", "-q", "upper")
        result, text = status("lower")
        expect((result, f"--old-base {lower_old}" in text), (2, True), "a base rebuilt in this repository stops the script without --old-base, and names the commit to pass")
        result, text = status(lower_new)
        expect((result, f"--old-base {lower_old}" in text), (2, True), "and so does that base named by its commit, by the reflog of the branch at it")
        result, text = status("lower", old_base=lower_old)
        expect(result, (lower_new, lower_old), "and moves with it")
        result, text = status("lower", resume=True)
        expect((result, "did not begin" in text), ((lower_new, lower_old), False), "--continue takes the old base from what the rebase recorded")

        # A base rebuilt without a commit it had: nothing would replay that commit.
        git("checkout", "-q", "-b", "two", first)
        commit("p")
        two_old = commit("q")
        git("checkout", "-q", "-b", "top")
        top_old = commit("t")
        git("checkout", "-q", "-B", "two", first)
        two_new = commit("p")
        git("checkout", "-q", "top")
        result, text = status("two", old_base=two_old)
        expect((result, "\n  q\n" in text, head()), (1, True, top_old), "a commit of the old base that the new base lacks stops the script before the rebase, and is named")
        result, text = status("two", old_base=two_old, accept_drop=True)
        expect(result, (two_new, two_old), "--accept-drop goes on without it")
        git("checkout", "-q", "upper")
        result, text = status("lower", resume=True)
        expect((result, "did not begin" in text), ((lower_new, None), True), "--continue on a branch whose rebase this script did not record says what it cannot check")

        # A conflict stops the script with the rebase in progress; --continue goes on from what it recorded.
        git("checkout", "-q", "-b", "under", first)
        under_old = commit("f", "1\n")
        git("checkout", "-q", "-b", "over")
        commit("f", "2\n", subject="over")
        git("checkout", "-q", "-B", "under", first)
        under_new = commit("f", "3\n")
        git("checkout", "-q", "over")
        result, text = status("under", old_base=under_old)
        expect((result, "Conflicts in:\n  f\n" in text), (1, True), "a conflict stops the script and names the file")
        result, text = status("under", old_base=under_old)
        expect((result, "uncommitted" in text), (2, True), "an unresolved conflict stops the script")
        pathlib.Path("f").write_text("4\n")
        git("add", "f")
        git("commit", "-q", "-m", "over")
        result, text = status("under", old_base=under_old)
        expect((result, "a rebase is in progress" in text), (2, True), "a rebase in progress stops the script")
        git("rebase", "--continue")
        result, text = status("under", resume=True)
        expect(result, (under_new, under_old), "--continue after a resolved conflict takes both bases from the record")

        # A branch above this one holds this one's commits too, which is no reason to stop.
        git("checkout", "-q", "main")
        main_new = commit("m")
        git("push", "-q", "origin", "main")
        git("checkout", "-q", "-b", "plain", first)
        commit("k")
        commit("own")
        git("branch", "-q", "above")
        result, text = status("main")
        expect(result, (main_new, first), "a base that only advanced needs no --old-base, whatever branch sits above")

        # A commit whose change the new base already holds is dropped by git, which the script reports.
        git("checkout", "-q", "main")
        main_newer = commit("k", subject="the same change under another subject")
        git("push", "-q", "origin", "main")
        git("checkout", "-q", "plain")
        result, text = status("main")
        expect((result, "\n  k\n" in text), (1, True), "a commit the rebase dropped stops the script and is named")
        result, text = status("main", resume=True)
        expect((result, "\n  k\n" in text), (1, True), "--continue reports the dropped commit again, from what the rebase recorded")
        result, text = status("main", resume=True, accept_drop=True)
        expect(result, (main_newer, main_new), "--accept-drop goes on, with the old base the rebase recorded")
        git("checkout", "-q", "--detach")
        result, text = status("main", resume=True)
        expect((result, "detached" in text), (2, True), "--continue needs a branch too")
        git("checkout", "-q", "plain")

        # `run`, with a lint that passes or fails, and changes that reach no test, one suite, or every test.
        git("checkout", "-q", "-b", "runs", "main")
        commit("CLI/lint.sh", "#!/bin/sh\necho linted\nexit 0\n")
        pathlib.Path("CLI/lint.sh").chmod(0o755)
        git("add", "CLI/lint.sh")
        git("commit", "-q", "-m", "executable")
        result, text = status_of_run("main")
        expect((result, "Clean." in text, state_path().exists()), (0, True, False), "a branch that reaches no test passes on the lint, and the record of its rebase is removed")
        git("checkout", "-q", "main")
        commit("unruled")
        git("push", "-q", "origin", "main")
        git("checkout", "-q", "runs")
        result, text = status_of_run("main")
        expect((result, "The base's move changed unruled" in text, "Clean." in text), (3, True, True), "a base whose move reaches every test runs the branch's own suites, lints, and exits 3")
        commit("Plugins/A.swift")
        result, text = status_of_run("main", runner="false")
        expect((result, "== Lint" in text), (1, False), "a failed test step fails the script before the lint")
        commit("Package.swift", "// swift-tools-version: 6.2\n")
        result, text = status_of_run("main")
        expect((result, "The branch changed Package.swift" in text, "gh workflow run verify.yml --ref runs" in text, "Clean." in text), (3, True, True, True), "a branch that reaches every test runs none, names the Verify to dispatch, lints, and exits 3")
        commit("CLI/lint.sh", "#!/bin/sh\necho misformatted\nexit 1\n")
        result, text = status_of_run("main")
        expect((result, "misformatted" in text), (1, True), "a failed lint fails the script and its output is printed")
        commit("Notes.md", "<<<<<<< HEAD\n")
        result, text = status_of_run("main")
        expect((result, "A conflict marker is left" in text and "Notes.md" in text), (1, True), "a conflict marker fails the script before anything is built")

        pathlib.Path("d").write_text("uncommitted\n")
        git("add", "d")
        result, text = status("main", resume=True)
        expect((result, "uncommitted" in text), (2, True), "--continue needs a clean checkout too")
        git("reset", "-q", "--hard")
        git("remote", "set-url", "origin", str(root / "missing.git"))
        result, text = status("main")
        expect((result, "could not be asked" in text), (2, True), "an origin that cannot be reached is an error, not a branch origin lacks")
    finally:
        os.chdir(start)
        for name, value in saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        shutil.rmtree(root, ignore_errors=True)


def self_test():
    def expect(actual, expected, what):
        if actual != expected:
            print(f"self-test failed: {what}\n  expected {expected!r}\n  actual   {actual!r}", file=sys.stderr)
            sys.exit(1)

    conflict = "a\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> 1a2b3c4 (Commit)\nb\n"
    files = {
        "A.swift": conflict,
        "B.swift": "let separator = \"=======\"\n// <<<<<<< not at the start of a line\n",
        "C.md": "Heading\n=======\ntext\n",
        "D.swift": "<<<<<<< HEAD\nonly the opening line\n",
    }
    expect(files_with_conflict_markers(set(files) | {"Gone.swift"}, files.get), ["A.swift", "D.swift"], "a file with an opening or a closing marker line is reported, a line of `=` alone is not, and a deleted file is skipped")
    verify_touched, _ = load_verify_touched()
    expect(
        list(verify_touched.filters_of_changes({"Plugins/A.swift"}, files.get)),
        ["^SafeDIGeneratorPluginTests\\."],
        "the verify-touched script beside this skill loads and selects suites",
    )
    guards(expect, verify_touched)
    print("restack-lane: self-test passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("new_base", nargs="?")
    parser.add_argument("--old-base", metavar="REV")
    parser.add_argument("--continue", dest="resume", action="store_true")
    parser.add_argument("--accept-drop", action="store_true")
    parser.add_argument("--skip-compile-checks", action="store_true")
    parser.add_argument("--runner", metavar="COMMAND", default=os.environ.get("SAFEDI_VERIFY_RUNNER", ""))
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    # Each line out before the next child writes, so that the two streams and the children's output keep their order.
    sys.stdout.reconfigure(line_buffering=True)
    if arguments.self_test:
        return self_test()
    if not arguments.new_base:
        parser.error("NEW_BASE is required")
    return run(arguments)


if __name__ == "__main__":
    sys.exit(main())
