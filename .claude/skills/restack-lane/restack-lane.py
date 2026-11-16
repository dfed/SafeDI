#!/usr/bin/env python3
"""Moves a branch of a stack onto its parent's new head, from a record of the head it was built on.

    restack-lane.py --record PARENT
    restack-lane.py --onto NEW_PARENT [--old-parent REV]
    restack-lane.py --finish
    restack-lane.py --show
    restack-lane.py --self-test

A branch in a stack holds its own commits on top of its parent's head. When the parent is rebuilt (amended, rebased,
or landed on main as one squashed commit), the commits the branch sits on are no longer in the parent, and only
someone who knows the head the branch was built on can say where the branch's own commits begin. This script never
guesses that head: it reads it from a record, the ref `refs/stack-parent/BRANCH` in this clone, or takes it from
`--old-parent`, and runs `git rebase --onto NEW_PARENT OLD_PARENT`.

`--record PARENT` writes the record for the branch that is checked out: the commit of PARENT, which must be an
ancestor of `HEAD`. Run it once, when a branch is built on its parent or first used with this script.

`--onto NEW_PARENT` moves the branch. NEW_PARENT written `origin/X` is fetched and used at the commit `origin` has
now, never at what this clone last saw; anything else is used as this clone resolves it. A parent that landed on main
as a squashed commit is `--onto origin/main`: the record still names the parent's last head, so only the branch's own
commits are replayed. `--old-parent REV` names the old head in place of the record, for a branch built in another
clone. It prints the commits it moves and the command that undoes the move, moves no other branch, and writes the
record again once the branch is on the new parent. It never pushes and never runs tests: it prints the commands for
both.

On a conflict it lists the files and stops, the rebase in progress. Resolve, `git rebase --continue` until it ends,
then `--finish`, which fetches nothing and completes the record; or `git rebase --abort`, which leaves the branch
and the record as they were.

`--show` prints the record. `--self-test` checks the script in repositories it makes under the user's caches
directory.

Run it from the checkout, on the branch, with nothing uncommitted. One run at a time per branch: a lock file in the
git directory stops a second, and names the process that holds it.

Exit status: 0 when the branch is on the new parent with every commit it had; 1 when the rebase stopped on a
conflict, or left a conflict marker; 2 for wrong arguments, a checkout that is not ready, a missing record or a held
lock; 3 when the branch moved and has fewer commits than before, which happens when the new parent already holds a
commit's change: read the list it prints.
"""

import argparse
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import time


class Stop(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def git(*arguments, check=True, directory=None):
    result = subprocess.run(["git", *arguments], capture_output=True, text=True, cwd=directory)
    if check and result.returncode != 0:
        raise Stop(2, f"git {' '.join(arguments)} failed:\n{result.stderr.strip()}")
    return result


def commit_of(revision):
    result = git("rev-parse", "--verify", "--quiet", f"{revision}^{{commit}}", check=False)
    if result.returncode != 0:
        raise Stop(2, f"{revision} names no commit in this clone.")
    return result.stdout.strip()


def short(commit):
    return commit[:9]


def current_branch():
    result = git("symbolic-ref", "--quiet", "--short", "HEAD", check=False)
    if result.returncode != 0:
        raise Stop(2, "HEAD is not on a branch. Check out the branch to move.")
    return result.stdout.strip()


def git_directory(name):
    return pathlib.Path(git("rev-parse", "--path-format=absolute", name).stdout.strip())


def rebase_in_progress():
    directory = git_directory("--git-dir")
    return (directory / "rebase-merge").exists() or (directory / "rebase-apply").exists()


def record_ref(branch):
    return f"refs/stack-parent/{branch}"


def pending_refs(branch):
    return f"refs/stack-pending/{branch}/new-parent", f"refs/stack-pending/{branch}/old-parent", f"refs/stack-pending/{branch}/old-head"


def read_ref(ref):
    result = git("rev-parse", "--verify", "--quiet", ref, check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def is_ancestor(ancestor, descendant):
    return git("merge-base", "--is-ancestor", ancestor, descendant, check=False).returncode == 0


def subjects(revision_range):
    return [line for line in git("log", "--reverse", "--format=%s", revision_range).stdout.splitlines()]


class Lock:
    """One run per branch in this clone: a file made with O_EXCL in the git directory all worktrees share."""

    def __init__(self, branch):
        self.path = git_directory("--git-common-dir") / ("restack-lane-" + branch.replace("/", "--") + ".lock")

    def __enter__(self):
        try:
            descriptor = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        except FileExistsError:
            holder = self.path.read_text().strip() or "an unknown process"
            raise Stop(2, f"Another run holds {self.path} (process {holder}). If no such process runs, delete the file.") from None
        with os.fdopen(descriptor, "w") as file:
            file.write(str(os.getpid()))
        return self

    def __exit__(self, *_):
        self.path.unlink(missing_ok=True)


def require_ready_checkout():
    if rebase_in_progress():
        raise Stop(2, "A rebase is in progress here. Finish it (`git rebase --continue`, then `--finish`) or `git rebase --abort`.")
    if git("status", "--porcelain", "--untracked-files=no").stdout.strip():
        raise Stop(2, "The checkout has uncommitted changes. Commit or stash them first.")


def record(parent):
    branch = current_branch()
    commit = commit_of(parent)
    if not is_ancestor(commit, "HEAD"):
        raise Stop(2, f"{parent} ({short(commit)}) is not an ancestor of {branch}, so the branch was not built on it.")
    git("update-ref", record_ref(branch), commit)
    print(f"Recorded: {branch} is built on {short(commit)}.")
    return 0


def show():
    branch = current_branch()
    commit = read_ref(record_ref(branch))
    if commit is None:
        print(f"{branch} has no recorded parent head.")
    else:
        own = git("rev-list", "--count", f"{commit}..HEAD").stdout.strip()
        print(f"{branch} is built on {short(commit)} and holds {own} commit(s) of its own.")
    return 0


def resolve_new_parent(new_parent):
    if new_parent.startswith("origin/"):
        git("fetch", "--quiet", "origin", new_parent[len("origin/"):])
        return commit_of("FETCH_HEAD")
    return commit_of(new_parent)


def onto(new_parent_name, old_parent_name):
    # First, since HEAD is on no branch while a rebase is in progress.
    require_ready_checkout()
    branch = current_branch()
    with Lock(branch):
        recorded = read_ref(record_ref(branch))
        if old_parent_name is not None:
            old_parent = commit_of(old_parent_name)
            if recorded is not None and recorded != old_parent:
                print(f"Note: the record says {short(recorded)}; using --old-parent {short(old_parent)}.")
        elif recorded is not None:
            old_parent = recorded
        else:
            raise Stop(2, f"{branch} has no recorded parent head. Pass --old-parent REV, the parent's head this branch was built on, or run --record PARENT first.")
        if not is_ancestor(old_parent, "HEAD"):
            raise Stop(2, f"The old parent head {short(old_parent)} is not an ancestor of {branch}.")
        old_head = commit_of("HEAD")
        if old_head == old_parent:
            raise Stop(2, f"{branch} holds no commit after {short(old_parent)}, so there is nothing to move.")
        new_parent = resolve_new_parent(new_parent_name)
        if new_parent == old_parent:
            print(f"{branch} is already on {short(new_parent)}.")
            return 0

        print(f"Moving {branch} from {short(old_parent)} onto {new_parent_name} at {short(new_parent)}. Its commits:")
        print(git("log", "--reverse", "--format=  %h %s", f"{old_parent}..HEAD").stdout.rstrip())
        print(f"To undo: git reset --hard {old_head}")
        sys.stdout.flush()
        new_ref, old_ref, head_ref = pending_refs(branch)
        git("update-ref", new_ref, new_parent)
        git("update-ref", old_ref, old_parent)
        git("update-ref", head_ref, old_head)

        # In a session of its own, so that a signal sent to this script's group reaches git only through the handler,
        # which lets git stop between commits rather than in the middle of one.
        rebase = subprocess.Popen(
            ["git", "-c", "core.editor=true", "rebase", "--no-update-refs", "--no-autostash", "--onto", new_parent, old_parent],
            start_new_session=True,
        )
        interrupted = []

        def forward(signal_number, _frame):
            interrupted.append(signal_number)
            try:
                os.killpg(rebase.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

        previous = {number: signal.signal(number, forward) for number in (signal.SIGINT, signal.SIGTERM)}
        try:
            status = rebase.wait()
        finally:
            for number, handler in previous.items():
                signal.signal(number, handler)
        if interrupted:
            print("\nInterrupted. git may have stopped inside a commit: run `git rebase --abort`, which puts the branch back, then start again.")
            return 1
        if status != 0:
            if rebase_in_progress():
                conflicted = git("diff", "--name-only", "--diff-filter=U").stdout.split()
                print("\nThe rebase stopped on a conflict in:")
                for path in conflicted:
                    print(f"  {path}")
                print("Resolve, `git rebase --continue` until it ends, then run this script with --finish. Or `git rebase --abort`.")
                return 1
            clear_pending(branch)
            raise Stop(1, "git rebase failed and left no rebase in progress; the branch is where it was.")
        return finish(branch)


def clear_pending(branch):
    for ref in pending_refs(branch):
        git("update-ref", "-d", ref, check=False)


def finish_command():
    if rebase_in_progress():
        raise Stop(2, "The rebase is still in progress. `git rebase --continue` until it ends, then --finish.")
    branch = current_branch()
    with Lock(branch):
        return finish(branch)


def finish(branch):
    new_ref, old_ref, head_ref = pending_refs(branch)
    new_parent, old_parent, old_head = read_ref(new_ref), read_ref(old_ref), read_ref(head_ref)
    if new_parent is None or old_parent is None or old_head is None:
        raise Stop(2, f"No move of {branch} is waiting to be finished.")
    if not is_ancestor(new_parent, "HEAD"):
        clear_pending(branch)
        raise Stop(1, f"{branch} is not on {short(new_parent)}: the rebase was aborted or the branch was reset. The record still says {short(old_parent)}.")
    git("update-ref", record_ref(branch), new_parent)
    clear_pending(branch)

    status = 0
    before, after = subjects(f"{old_parent}..{old_head}"), subjects(f"{new_parent}..HEAD")
    missing = list(before)
    for subject in after:
        if subject in missing:
            missing.remove(subject)
    if len(after) < len(before):
        print(f"\n{branch} had {len(before)} commit(s) and now has {len(after)}. git drops a commit whose change the new parent already holds. Missing:")
        for subject in missing:
            print(f"  {subject}")
        print(f"If one of them is work the parent lacks, undo with: git reset --hard {old_head}")
        status = 3

    marked = []
    for path in git("diff", "--name-only", "--diff-filter=d", f"{new_parent}..HEAD").stdout.splitlines():
        try:
            lines = pathlib.Path(path).read_text(errors="replace").splitlines()
        except (FileNotFoundError, IsADirectoryError):
            continue
        if any(line.startswith(("<<<<<<< ", ">>>>>>> ")) for line in lines):
            marked.append(path)
    if marked:
        print("\nA conflict marker is left in:")
        for path in marked:
            print(f"  {path}")
        status = 1

    head = commit_of("HEAD")
    print(f"\n{branch} is on {short(new_parent)} at {short(head)}; the record is updated.")
    print(f"Compare with before: git range-diff {short(old_parent)}..{short(old_head)} {short(new_parent)}..{short(head)}")
    print(f"Then check it: python3 -I .claude/skills/verify-touched/verify-touched.py {short(new_parent)} && ./CLI/lint.sh --check")
    print("Nothing was pushed. A branch that was pushed before needs your own rules for pushing a rebuilt branch.")
    return status


# MARK: Self-test


def self_test():
    script = pathlib.Path(__file__).resolve()
    caches = pathlib.Path(os.environ.get("XDG_CACHE_HOME") or (pathlib.Path.home() / ("Library/Caches" if sys.platform == "darwin" else ".cache")))
    root = caches / "SafeDIRestackLaneSelfTest" / str(os.getpid())
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    environment = {
        **os.environ,
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_SYSTEM": os.devnull,
        "GIT_AUTHOR_NAME": "Self Test",
        "GIT_AUTHOR_EMAIL": "self-test@example.invalid",
        "GIT_COMMITTER_NAME": "Self Test",
        "GIT_COMMITTER_EMAIL": "self-test@example.invalid",
    }
    failures = []

    def run(directory, *arguments):
        return subprocess.run(list(arguments), cwd=directory, env=environment, capture_output=True, text=True)

    def g(directory, *arguments):
        result = run(directory, "git", *arguments)
        assert result.returncode == 0, (arguments, result.stderr)
        return result.stdout.strip()

    def restack(directory, *arguments):
        return run(directory, sys.executable, "-I", str(script), *arguments)

    def commit(directory, path, text, subject):
        (directory / path).write_text(text)
        g(directory, "add", path)
        g(directory, "commit", "--quiet", "-m", subject)

    def repository(name):
        """main: base. parent: P1, P2 on main. child: C1, C2 on parent, recorded."""
        directory = root / name
        directory.mkdir()
        g(directory, "init", "--quiet", "--initial-branch=main")
        commit(directory, "base.txt", "base\n", "base")
        g(directory, "checkout", "--quiet", "-b", "parent")
        commit(directory, "parent.txt", "one\n", "P1")
        commit(directory, "parent-2.txt", "two\n", "P2")
        g(directory, "checkout", "--quiet", "-b", "child")
        commit(directory, "child.txt", "one\n", "C1")
        commit(directory, "child-2.txt", "two\n", "C2")
        result = restack(directory, "--record", "parent")
        assert result.returncode == 0, result.stdout + result.stderr
        return directory

    def check(name, condition, detail=""):
        if not condition:
            failures.append(f"{name}: {detail}")

    def read_pending(directory):
        return run(directory, "git", "rev-parse", "--verify", "--quiet", "refs/stack-pending/child/old-head").returncode == 0

    def log(directory, revision_range):
        return g(directory, "log", "--reverse", "--format=%s", revision_range).splitlines()

    try:
        # A parent rebuilt with other commits: only the child's own commits move.
        directory = repository("rebuilt")
        g(directory, "checkout", "--quiet", "parent")
        g(directory, "reset", "--quiet", "--hard", "main")
        commit(directory, "parent.txt", "one, rewritten\n", "P1 rewritten")
        g(directory, "checkout", "--quiet", "child")
        result = restack(directory, "--onto", "parent")
        check("rebuilt parent", result.returncode == 0, result.stdout + result.stderr)
        check("rebuilt parent", log(directory, "main..child") == ["P1 rewritten", "C1", "C2"], str(log(directory, "main..child")))
        check("rebuilt parent", not (directory / "parent-2.txt").exists(), "a commit the parent dropped came back")
        check("rebuilt parent records", g(directory, "rev-parse", "refs/stack-parent/child") == g(directory, "rev-parse", "parent"))

        # A parent that landed on main as one squashed commit.
        directory = repository("squashed")
        g(directory, "checkout", "--quiet", "main")
        g(directory, "merge", "--quiet", "--squash", "parent")
        g(directory, "commit", "--quiet", "-m", "Parent (#1)")
        g(directory, "checkout", "--quiet", "child")
        result = restack(directory, "--onto", "main")
        check("squashed parent", result.returncode == 0, result.stdout + result.stderr)
        check("squashed parent", log(directory, "main..child") == ["C1", "C2"], str(log(directory, "main..child")))

        # `origin/X` is used at the commit origin has, not at what the clone last saw.
        upstream = repository("upstream")
        clone = root / "clone"
        g(root, "clone", "--quiet", str(upstream), str(clone))
        g(clone, "checkout", "--quiet", "child")
        result = restack(clone, "--record", "origin/parent")
        check("clone records", result.returncode == 0, result.stdout + result.stderr)
        g(upstream, "checkout", "--quiet", "parent")
        commit(upstream, "parent-3.txt", "three\n", "P3")
        result = restack(clone, "--onto", "origin/parent")
        check("fetches origin", result.returncode == 0, result.stdout + result.stderr)
        check("fetches origin", log(clone, "origin/main..child") == ["P1", "P2", "P3", "C1", "C2"], str(log(clone, "origin/main..child")))

        # No record and no --old-parent: nothing is guessed.
        directory = repository("no-record")
        g(directory, "update-ref", "-d", "refs/stack-parent/child")
        head = g(directory, "rev-parse", "HEAD")
        result = restack(directory, "--onto", "main")
        check("no record", result.returncode == 2 and "--old-parent" in result.stderr, result.stdout + result.stderr)
        check("no record", g(directory, "rev-parse", "HEAD") == head, "the branch moved")
        result = restack(directory, "--onto", "main", "--old-parent", "parent")
        check("--old-parent", result.returncode == 0 and log(directory, "main..child") == ["C1", "C2"], result.stdout + result.stderr)

        # A held lock, uncommitted changes, an old parent the branch does not hold, a detached HEAD.
        directory = repository("guards")
        lock = directory / ".git" / "restack-lane-child.lock"
        lock.write_text("12345")
        result = restack(directory, "--onto", "main")
        check("lock", result.returncode == 2 and "12345" in result.stderr, result.stdout + result.stderr)
        lock.unlink()
        (directory / "child.txt").write_text("edited\n")
        result = restack(directory, "--onto", "main")
        check("uncommitted", result.returncode == 2 and "uncommitted" in result.stderr, result.stdout + result.stderr)
        g(directory, "checkout", "--quiet", "child.txt")
        g(directory, "branch", "elsewhere", "main")
        g(directory, "checkout", "--quiet", "elsewhere")
        commit(directory, "elsewhere.txt", "x\n", "E1")
        g(directory, "checkout", "--quiet", "child")
        result = restack(directory, "--onto", "main", "--old-parent", "elsewhere")
        check("old parent not an ancestor", result.returncode == 2 and "not an ancestor" in result.stderr, result.stdout + result.stderr)
        result = restack(directory, "--record", "elsewhere")
        check("record not an ancestor", result.returncode == 2, result.stdout + result.stderr)
        g(directory, "checkout", "--quiet", "--detach")
        result = restack(directory, "--onto", "main")
        check("detached", result.returncode == 2 and "not on a branch" in result.stderr, result.stdout + result.stderr)
        check("lock released", not lock.exists(), "a refused run left its lock")

        # A conflict stops with the rebase in progress; --finish completes the record and fetches nothing.
        directory = repository("conflict")
        g(directory, "checkout", "--quiet", "parent")
        commit(directory, "child.txt", "the parent's\n", "P3 takes the child's file")
        g(directory, "checkout", "--quiet", "child")
        old_record = g(directory, "rev-parse", "refs/stack-parent/child")
        result = restack(directory, "--onto", "parent")
        check("conflict", result.returncode == 1 and "child.txt" in result.stdout and "--finish" in result.stdout, result.stdout + result.stderr)
        check("conflict keeps the record", g(directory, "rev-parse", "refs/stack-parent/child") == old_record)
        result = restack(directory, "--onto", "parent")
        check("second run during a conflict", result.returncode == 2 and "in progress" in result.stderr, result.stdout + result.stderr)
        result = restack(directory, "--finish")
        check("--finish during a conflict", result.returncode == 2 and "still in progress" in result.stderr, result.stdout + result.stderr)
        (directory / "child.txt").write_text("resolved\n")
        g(directory, "add", "child.txt")
        g(directory, "-c", "core.editor=true", "rebase", "--continue")
        result = restack(directory, "--finish")
        check("--finish", result.returncode == 0, result.stdout + result.stderr)
        check("--finish records", g(directory, "rev-parse", "refs/stack-parent/child") == g(directory, "rev-parse", "parent"))
        result = restack(directory, "--finish")
        check("--finish twice", result.returncode == 2, result.stdout + result.stderr)

        # An aborted rebase leaves the record, and --finish says so.
        directory = repository("aborted")
        g(directory, "checkout", "--quiet", "parent")
        commit(directory, "child.txt", "the parent's\n", "P3 takes the child's file")
        g(directory, "checkout", "--quiet", "child")
        old_record = g(directory, "rev-parse", "refs/stack-parent/child")
        restack(directory, "--onto", "parent")
        g(directory, "rebase", "--abort")
        result = restack(directory, "--finish")
        check("aborted", result.returncode == 1 and g(directory, "rev-parse", "refs/stack-parent/child") == old_record, result.stdout + result.stderr)

        # A conflict marker committed during the resolution fails the finish.
        directory = repository("marker")
        g(directory, "checkout", "--quiet", "parent")
        commit(directory, "child.txt", "the parent's\n", "P3 takes the child's file")
        g(directory, "checkout", "--quiet", "child")
        restack(directory, "--onto", "parent")
        g(directory, "add", "child.txt")
        g(directory, "-c", "core.editor=true", "rebase", "--continue")
        result = restack(directory, "--finish")
        check("marker", result.returncode == 1 and "conflict marker" in result.stdout, result.stdout + result.stderr)

        # A commit whose change the new parent already holds is dropped, and named.
        directory = repository("dropped")
        g(directory, "checkout", "--quiet", "parent")
        g(directory, "cherry-pick", "child~1")
        g(directory, "checkout", "--quiet", "child")
        result = restack(directory, "--onto", "parent")
        check("dropped", result.returncode == 3 and "  C1" in result.stdout, result.stdout + result.stderr)
        check("dropped", log(directory, "parent..child") == ["C2"], str(log(directory, "parent..child")))

        # A signal ends git, says how to put the branch back, and releases the lock.
        directory = repository("signal")
        g(directory, "checkout", "--quiet", "parent")
        commit(directory, "parent-3.txt", "three\n", "P3")
        g(directory, "checkout", "--quiet", "child")
        hook = directory / ".git" / "hooks" / "pre-rebase"
        hook.parent.mkdir(exist_ok=True)
        hook.write_text("#!/bin/sh\nsleep 60\n")
        hook.chmod(0o755)
        process = subprocess.Popen([sys.executable, "-I", str(script), "--onto", "parent"], cwd=directory, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        lock = directory / ".git" / "restack-lane-child.lock"
        for _ in range(200):
            if lock.exists() and read_pending(directory):
                break
            time.sleep(0.05)
        time.sleep(0.5)
        process.send_signal(signal.SIGTERM)
        try:
            output, errors = process.communicate(timeout=20)
            check("signal", process.returncode == 1 and "git rebase --abort" in output, output + errors)
        except subprocess.TimeoutExpired:
            process.kill()
            check("signal", False, "the script did not end within 20 seconds of SIGTERM")
        check("signal releases the lock", not lock.exists())

        # --show prints the record.
        directory = repository("show")
        result = restack(directory, "--show")
        check("--show", result.returncode == 0 and "2 commit(s) of its own" in result.stdout, result.stdout + result.stderr)
    finally:
        shutil.rmtree(root, ignore_errors=True)

    if failures:
        print("restack-lane.py --self-test failed:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("restack-lane.py --self-test passed.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--record", metavar="PARENT")
    action.add_argument("--onto", metavar="NEW_PARENT")
    action.add_argument("--finish", action="store_true")
    action.add_argument("--show", action="store_true")
    action.add_argument("--self-test", action="store_true")
    parser.add_argument("--old-parent", metavar="REV")
    arguments = parser.parse_args()
    if arguments.old_parent is not None and arguments.onto is None:
        parser.error("--old-parent goes with --onto")
    try:
        if arguments.self_test:
            return self_test()
        if arguments.record is not None:
            return record(arguments.record)
        if arguments.show:
            return show()
        if arguments.finish:
            return finish_command()
        return onto(arguments.onto, arguments.old_parent)
    except Stop as stop:
        print(stop.message, file=sys.stderr)
        return stop.status


if __name__ == "__main__":
    sys.exit(main())
