#!/usr/bin/env python3
"""Moves a branch onto a new base and checks the result, in one command.

    restack-lane.py NEW_BASE [--old-base REV] [--skip-compile-checks] [--runner COMMAND]
    restack-lane.py --continue NEW_BASE [--old-base REV] [--skip-compile-checks] [--runner COMMAND]
    restack-lane.py --self-test

NEW_BASE is the branch or commit to move onto. A branch `origin` has, named `X` or `origin/X`, is fetched and used at
`origin`'s commit, never at the remote-tracking ref the checkout last saw; given as `X`, the script stops when a local
branch `X` is at another commit. It prints the commit it uses. `--old-base` is the commit the branch's own commits
start after: an ancestor of `HEAD` with at least one commit after it. Without it the script takes the merge base of
`HEAD` and NEW_BASE, and stops when commits after that merge base are on another branch too, since those are an old
base's and would be replayed: a base that was itself rebased, the usual case in a stack, needs `--old-base`. It runs
from the checkout's top level, on a branch, with nothing uncommitted and no untracked file the build would compile.

What it does, stopping at the first step that fails:

1. `git rebase --no-update-refs --no-autostash --onto NEW_BASE OLD_BASE`, after printing the command that undoes it. No
   other branch moves, whatever `rebase.updateRefs` says. On a conflict it lists the files and stops with status 1, the
   rebase still in progress: resolve, `git rebase --continue` until it ends, then run this script again with
   `--continue`, which skips this step. Pass `--old-base` again with it, or step 3 runs only the suites the branch
   touches. It says so when the rebase ends with another number of commits than it began with.
2. Fails on a conflict marker left in any file the branch or the base's move touched.
3. Builds the tests and runs the suites the branch touches and the suites the base's move touched, through the
   `verify-touched` skill's script: its runner, its own `TMPDIR` and log, generated code compiled unless
   `--skip-compile-checks`. A compile error is a failure there. When a change reaches every test, it runs none and
   prints the full Verify to dispatch: the whole suite is not this machine's work.
4. `./CLI/lint.sh --check`, through the runner.

Then it prints the new head. It never pushes: a restacked branch is pushed by whoever owns it, under their own rules.
It does not regenerate expectations: when step 3 fails on expected text the base's move changed, use the
`regenerate-expectations` skill, then run this script again with `--continue`.

`--runner` (or `SAFEDI_VERIFY_RUNNER`) is a command put before `swift test` and the lint, for a machine that queues
heavy work. Ending the script ends what it started.

Exit status: 0 when every step passed, 1 when a step failed (its output says which), 2 for wrong arguments or a
checkout that is not ready, 3 when everything it ran passed and the whole suite is still owed.
"""

import argparse
import contextlib
import importlib.util
import io
import os
import pathlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

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
    if git("ls-remote", "--exit-code", "--heads", "origin", branch, check=False).returncode == 0:
        fetched = git("fetch", "origin", branch, check=False)
        if fetched.returncode != 0:
            return None, fetched.stderr.strip()
        remote = git("rev-parse", "FETCH_HEAD").stdout.strip()
        local = commit_of(f"refs/heads/{branch}")
        if not explicit and local is not None and local != remote:
            return None, f"the local branch `{branch}` is at {local} and origin's is at {remote}; pass `origin/{branch}` or the commit you mean."
        return remote, f"origin's `{branch}`, fetched now"
    if explicit:
        return None, f"origin has no branch `{branch}`."
    commit = commit_of(name)
    if commit is None:
        return None, f"`{name}` names no commit."
    return commit, "as named; origin has no branch of that name"


def commits_other_branches_hold(old_base, current_branch):
    """How many commits after `old_base` on `HEAD` another branch holds too, and one such branch.

    A branch's own commits are on no other branch. Commits of the range that another branch holds are the old base's,
    which the rebase would replay onto a base that already has them in another form.
    """
    own = {f"refs/heads/{current_branch}", f"refs/remotes/origin/{current_branch}"}
    references = [line for line in git("for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes").stdout.split("\n") if line and line not in own and not line.endswith("/HEAD")]
    most, holder = 0, None
    for reference in references:
        base = git("merge-base", reference, "HEAD", check=False).stdout.strip()
        if not base:
            continue
        held = int(git("rev-list", "--count", f"{old_base}..{base}", check=False).stdout.strip() or 0)
        if held > most:
            most, holder = held, reference
    return most, holder


def untracked_package_files():
    listed = git("ls-files", "--others", "--exclude-standard", "-z", "--", "Sources", "Plugins", "Tests", "Package.swift").stdout
    return sorted(path for path in listed.split("\0") if path)


class Children:
    """The process this script waits on, ended when the script is: `swift test` must not outlive a cancelled restack."""

    def __init__(self):
        self.running = None
        for signal_number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(signal_number, self.end)

    def end(self, signal_number, _frame):
        if self.running is not None and self.running.poll() is None:
            self.running.terminate()
            self.running.wait()
        sys.exit(128 + signal_number)

    def run(self, command, **options):
        self.running = subprocess.Popen(command, **options)
        output, _ = self.running.communicate()
        status = self.running.returncode
        self.running = None
        return status, output


def moved(arguments):
    """Checks the checkout and the arguments and rebases; returns a status to exit with, or the two bases."""
    if git("status", "--porcelain", "--untracked-files=no").stdout.strip():
        print("restack-lane: the checkout has uncommitted changes; commit or stash them first.", file=sys.stderr)
        return 2
    untracked = untracked_package_files()
    if untracked:
        print("restack-lane: untracked files the build would compile; commit or remove them first:\n  " + "\n  ".join(untracked), file=sys.stderr)
        return 2
    rebase_in_progress = any(pathlib.Path(git("rev-parse", "--git-path", name).stdout.strip()).exists() for name in ("rebase-merge", "rebase-apply"))
    if rebase_in_progress:
        print("restack-lane: a rebase is in progress; finish it with `git rebase --continue`, then pass --continue.", file=sys.stderr)
        return 2
    current_branch = git("symbolic-ref", "--quiet", "--short", "HEAD", check=False).stdout.strip()
    if not current_branch:
        print("restack-lane: HEAD is detached; check out the branch to move.", file=sys.stderr)
        return 2

    new_base, how = new_base_commit(arguments.new_base)
    if new_base is None:
        print(f"restack-lane: {how}", file=sys.stderr)
        return 2
    print(f"New base: {new_base} ({how}).")

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
        if old_base is None:
            print("Warning: --continue without --old-base checks only the suites the branch touches, not those the base's move touched, and does not compare commit counts.")
        else:
            # `ORIG_HEAD` is the branch as the rebase found it.
            before = git("rev-list", "--count", f"{old_base}..ORIG_HEAD", check=False).stdout.strip()
            after = git("rev-list", "--count", f"{new_base}..HEAD").stdout.strip()
            if before and before != after:
                print(f"Note: {before} commits before the rebase, {after} after. Check that none of yours was dropped.")
        return new_base, old_base

    if old_base is None:
        old_base = git("merge-base", "HEAD", new_base).stdout.strip()
        held, holder = commits_other_branches_hold(old_base, current_branch)
        if held:
            print(f"restack-lane: {held} of the commits after the merge base {old_base[:9]} are also on {holder}, so they look like the old base's and would be replayed. Pass --old-base with the commit your own commits start after.", file=sys.stderr)
            return 2
    if git("merge-base", "--is-ancestor", old_base, "HEAD", check=False).returncode != 0:
        print(f"restack-lane: the old base {old_base[:9]} is not an ancestor of HEAD.", file=sys.stderr)
        return 2
    before = int(git("rev-list", "--count", f"{old_base}..HEAD").stdout.strip())
    if before == 0:
        print(f"restack-lane: no commit follows the old base {old_base[:9]}; there is nothing to move.", file=sys.stderr)
        return 2
    undo = git("rev-parse", "HEAD").stdout.strip()
    step(f"Rebase onto {new_base[:9]} the {before} commits after {old_base[:9]}")
    print(f"To undo: git reset --hard {undo}")
    # A configured `rebase.updateRefs` would move other branches that point into the range, and an autostash
    # would carry changes this script refused above.
    rebased = subprocess.run(["git", "rebase", "--no-update-refs", "--no-autostash", "--onto", new_base, old_base])
    if rebased.returncode != 0:
        conflicted = sorted(paths_of("--diff-filter=U"))
        print("Conflicts in:" if conflicted else "The rebase stopped.")
        for path in conflicted:
            print(f"  {path}")
        print("Resolve, `git rebase --continue` until it ends, then run this script again with --continue and the same --old-base.")
        return 1
    after = int(git("rev-list", "--count", f"{new_base}..HEAD").stdout.strip())
    if after != before:
        print(f"Note: {before} commits before the rebase, {after} after: git dropped the commits the new base already holds. Check that none of yours is among them.")
    return new_base, old_base


def run(arguments):
    try:
        os.chdir(git("rev-parse", "--show-toplevel").stdout.strip())
    except subprocess.CalledProcessError as error:
        print(f"restack-lane: {error.stderr.strip()}", file=sys.stderr)
        return 2
    verify_touched, verify_touched_path = load_verify_touched()
    result = moved(arguments)
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
    # verify-touched builds the tests, reports a compile error as a failure, and gives the run its own `TMPDIR`, log,
    # runner and cleanup.
    step("Build, then the suites the branch touches and the suites the base's move touched")
    command = [sys.executable, "-I", str(verify_touched_path), new_base, "--runner", arguments.runner]
    try:
        # The branch's own paths are verify-touched's to select; asked here only for whether they reach every test.
        verify_touched.filters_of_changes(lane_paths, read_text_in_checkout)
        for pattern in verify_touched.filters_of_changes(base_paths, read_text_in_checkout):
            command += ["--also", pattern]
    except verify_touched.WholeSuite as reason:
        branch = git("symbolic-ref", "--quiet", "--short", "HEAD", check=False).stdout.strip()
        print(f"{reason} changed, which reaches every test. The whole suite is a full Verify's work, not this machine's:")
        print(f"  push the branch, then: gh workflow run verify.yml --ref {branch}")
        print("Lint still runs here.")
        command = None
    if command is not None:
        if arguments.skip_compile_checks:
            command.append("--skip-compile-checks")
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
    print(f"\nRestacked: {head}")
    print("Not pushed." + ("" if command is not None else " The whole suite is still owed: dispatch the full Verify."))
    return 0 if command is not None else 3


def guards(expect, verify_touched):
    """Runs `moved` in a repository made for the purpose, once per guard."""
    root = pathlib.Path(tempfile.mkdtemp(prefix="restack-lane-self-test-", dir=verify_touched.caches_directory()))
    start = pathlib.Path.cwd()
    environment = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com", "GIT_CONFIG_GLOBAL": os.devnull}
    saved = {name: os.environ.get(name) for name in environment}
    os.environ.update(environment)

    def commit(name, text="x\n"):
        pathlib.Path(name).write_text(text)
        git("add", name)
        git("commit", "-q", "-m", name)
        return git("rev-parse", "HEAD").stdout.strip()

    def status(new_base, old_base=None, resume=False):
        with contextlib.redirect_stdout(io.StringIO()) as printed, contextlib.redirect_stderr(printed):
            result = moved(argparse.Namespace(new_base=new_base, old_base=old_base, resume=resume))
        return result, printed.getvalue()

    try:
        origin, work = root / "origin.git", root / "work"
        git("init", "-q", "--bare", "-b", "main", str(origin))
        git("init", "-q", "-b", "main", str(work))
        os.chdir(work)
        git("remote", "add", "origin", str(origin))
        first = commit("a")
        git("push", "-q", "origin", "main")
        git("checkout", "-q", "-b", "base")
        base_old = commit("b")
        git("push", "-q", "origin", "base")
        git("checkout", "-q", "-b", "lane")
        commit("c")
        # origin's `base` is rebuilt, as a restacked branch below this one is; the checkout has not fetched it.
        git("checkout", "-q", "-B", "elsewhere", first)
        base_new = commit("b2")
        git("push", "-q", "--force", "origin", "elsewhere:base")
        git("checkout", "-q", "lane")

        result, text = status("base")
        expect(result, 2, "a local branch that differs from origin's stops the script")
        expect(base_old in text and base_new in text, True, "and both commits are named")
        result, text = status("origin/base")
        expect((result, "also on" in text), (2, True), "without --old-base, commits another branch holds stop the script")
        result, text = status("origin/base", old_base="lane")
        expect((result, "nothing to move" in text), (2, True), "an old base with no commit after it stops the script")
        result, text = status("origin/base", old_base="elsewhere")
        expect((result, "not an ancestor" in text), (2, True), "an old base that is no ancestor of HEAD stops the script")
        pathlib.Path("Sources").mkdir()
        pathlib.Path("Sources/New.swift").write_text("")
        result, text = status("origin/base", old_base="base")
        expect((result, "Sources/New.swift" in text), (2, True), "an untracked source file stops the script")
        pathlib.Path("Sources/New.swift").unlink()
        git("checkout", "-q", "--detach")
        result, text = status("origin/base", old_base="base")
        expect((result, "detached" in text), (2, True), "a detached HEAD stops the script")
        git("checkout", "-q", "lane")
        git("branch", "-q", "bystander", "base")
        git("config", "rebase.updateRefs", "true")
        result, text = status("origin/base", old_base="base")
        expect(result, (base_new, base_old), "origin/NAME is fetched and used at origin's commit, with the old base as given")
        expect(git("rev-parse", "HEAD~1").stdout.strip(), base_new, "the branch sits on origin's commit")
        expect(git("rev-parse", "bystander").stdout.strip(), base_old, "no other branch moved")
        expect("To undo: git reset --hard" in text, True, "the undo command is printed")
        pathlib.Path("d").write_text("uncommitted\n")
        git("add", "d")
        result, text = status("origin/base", old_base="base", resume=True)
        expect((result, "uncommitted" in text), (2, True), "--continue needs a clean checkout too")
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
    parser.add_argument("--skip-compile-checks", action="store_true")
    parser.add_argument("--runner", metavar="COMMAND", default=os.environ.get("SAFEDI_VERIFY_RUNNER", ""))
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    if not arguments.new_base:
        parser.error("NEW_BASE is required")
    return run(arguments)


if __name__ == "__main__":
    sys.exit(main())
