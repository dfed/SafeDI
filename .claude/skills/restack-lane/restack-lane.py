#!/usr/bin/env python3
"""Moves a branch onto a new base and checks the result, in one command.

    restack-lane.py NEW_BASE [--old-base REV] [--skip-compile-checks]
    restack-lane.py --continue NEW_BASE [--old-base REV] [--skip-compile-checks]
    restack-lane.py --self-test

NEW_BASE is the branch or commit to move onto. A branch `origin` has is fetched and used at `origin`'s commit, and the
script stops when a local branch of that name is at another commit; it prints the commit it uses. `--old-base` is the
commit the branch's own commits start after: it must be an ancestor of `HEAD` with at least one commit after it. Its
default, the merge base of `HEAD` and NEW_BASE, is right only when the old base is an ancestor of the new one; a base
that was itself rebased, the usual case in a stack, needs `--old-base`. Run it on the branch, with nothing uncommitted.

What it does, stopping at the first step that fails:

1. `git rebase --no-update-refs --no-autostash --onto NEW_BASE OLD_BASE`, after printing the command that undoes it. No
   other branch moves, whatever `rebase.updateRefs` says. On a conflict it lists the files and stops with status 1, the
   rebase still in progress: resolve, `git rebase --continue` until it ends, then run this script again with
   `--continue`, which skips this step. Pass `--old-base` again with it, or step 3 runs only the suites the branch
   touches. It says so when the rebase ends with fewer commits than it began with.
2. Fails on a conflict marker left in any file the branch or the base's move touched.
3. Builds the tests and runs the suites the branch touches and the suites the base's move touched, through the
   `verify-touched` skill's script: its runner, its own `TMPDIR` and log, generated code compiled unless
   `--skip-compile-checks`, the whole suite when the base's move reaches every test. A compile error is a failure there.
4. `./CLI/lint.sh --check`.

Then it prints the new head. It never pushes: a restacked branch is pushed by whoever owns it, under their own rules.
It does not regenerate expectations: when step 3 fails on expected text the base's move changed, use the
`regenerate-expectations` skill, then run this script again with `--continue`.

Exit status: 0 when every step passed, 1 when a step failed (its output says which), 2 for wrong arguments or a
checkout that is not ready.
"""

import argparse
import importlib.util
import pathlib
import re
import subprocess
import sys

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

    A branch `origin` has is fetched and used at `origin`'s commit. A local branch of that name at another commit is
    refused: which of the two was meant is the caller's to say, by commit.
    """
    if git("ls-remote", "--exit-code", "--heads", "origin", name, check=False).returncode == 0:
        fetched = git("fetch", "origin", name, check=False)
        if fetched.returncode != 0:
            return None, fetched.stderr.strip()
        remote = git("rev-parse", "FETCH_HEAD").stdout.strip()
        local = commit_of(f"refs/heads/{name}")
        if local is not None and local != remote:
            return None, f"the local branch `{name}` is at {local} and origin's is at {remote}; name the commit you mean."
        return remote, f"origin/{name}, fetched now"
    commit = commit_of(name)
    if commit is None:
        return None, f"`{name}` names no commit."
    return commit, "as named; origin has no branch of that name"


def run(arguments):
    verify_touched, verify_touched_path = load_verify_touched()
    if git("status", "--porcelain", "--untracked-files=no").stdout.strip():
        print("restack-lane: the checkout has uncommitted changes; commit or stash them first.", file=sys.stderr)
        return 2
    rebase_in_progress = any(pathlib.Path(git("rev-parse", "--git-path", name).stdout.strip()).exists() for name in ("rebase-merge", "rebase-apply"))
    if rebase_in_progress:
        print("restack-lane: a rebase is in progress; finish it with `git rebase --continue`, then pass --continue.", file=sys.stderr)
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
            print("Warning: --continue without --old-base checks only the suites the branch touches, not those the base's move touched.")
    else:
        old_base = old_base or git("merge-base", "HEAD", new_base).stdout.strip()
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

    # verify-touched builds the tests, reports a compile error as a failure, and gives the run its own `TMPDIR`, log,
    # runner and cleanup, so the build and the whole suite go through it too.
    step("Build, then the suites the branch touches and the suites the base's move touched")
    command = [sys.executable, "-I", str(verify_touched_path), new_base]
    try:
        for pattern in verify_touched.filters_of_changes(base_paths, read_text_in_checkout):
            command += ["--also", pattern]
    except verify_touched.WholeSuite as reason:
        print(f"The base's move changed {reason}, which reaches every test.")
        command.append("--whole-suite")
    if arguments.skip_compile_checks:
        command.append("--skip-compile-checks")
    tested = subprocess.run(command)
    if tested.returncode != 0:
        return 1

    step("Lint")
    linted = subprocess.run(["./CLI/lint.sh", "--check"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if linted.returncode != 0:
        print(linted.stdout[-3000:])
        return 1
    print("Clean.")

    head = git("rev-parse", "HEAD").stdout.strip()
    branch = git("branch", "--show-current").stdout.strip()
    print(f"\nRestacked: {branch} is at {head} on {new_base[:9]}. Not pushed.")
    return 0


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
    print("restack-lane: self-test passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("new_base", nargs="?")
    parser.add_argument("--old-base", metavar="REV")
    parser.add_argument("--continue", dest="resume", action="store_true")
    parser.add_argument("--skip-compile-checks", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    if not arguments.new_base:
        parser.error("NEW_BASE is required")
    return run(arguments)


if __name__ == "__main__":
    sys.exit(main())
