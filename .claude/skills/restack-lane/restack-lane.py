#!/usr/bin/env python3
"""Moves a branch onto a new base and checks the result, in one command.

    restack-lane.py NEW_BASE [--old-base REV] [--skip-compile-checks]
    restack-lane.py --continue NEW_BASE [--old-base REV] [--skip-compile-checks]
    restack-lane.py --self-test

NEW_BASE is the branch or commit to move onto; a branch name is fetched from `origin` first. `--old-base` is the commit
the branch's own commits start after (default: the merge base of `HEAD` and NEW_BASE, which is right only when the old
base is an ancestor of the new one; a base that was itself rebased needs `--old-base`). Run it from the repository
root, on the branch, with nothing uncommitted.

What it does, stopping at the first step that fails:

1. `git rebase --onto NEW_BASE OLD_BASE`. On a conflict it lists the files and stops with status 1, the rebase still
   in progress: resolve, `git rebase --continue` until it ends, then run this script again with `--continue`, which
   skips this step. Pass `--old-base` again with it, or step 4 runs only the suites the branch touches.
2. Fails on a conflict marker left in any file the branch or the base's move touched.
3. Builds the tests (`swift build --build-tests --traits sourceBuild`).
4. Runs the suites the branch touches and the suites the base's move touched, through the `verify-touched` skill's
   script, with generated code compiled unless `--skip-compile-checks`.
5. `./CLI/lint.sh --check`.

Then it prints the new head. It never pushes: a restacked branch is pushed by whoever owns it, under their own rules.
It does not regenerate expectations: when step 4 fails on expected text the base's move changed, use the
`regenerate-expectations` skill where the branch has it, then run this script again with `--continue`.

Exit status: 0 when every step passed, 1 when a step failed (its output says which), 2 for wrong arguments or a
checkout that is not ready.
"""

import argparse
import importlib.util
import os
import pathlib
import re
import subprocess
import sys

def load_verify_touched():
    path = pathlib.Path(__file__).resolve().parent.parent / "verify-touched" / "verify-touched.py"
    spec = importlib.util.spec_from_file_location("verify_touched", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, path


def git(*arguments, check=True):
    return subprocess.run(["git", *arguments], check=check, capture_output=True, text=True)


def has_conflict_marker(text):
    """Whether `text` holds a line git writes around a conflict: seven `<` or `>` and a space, or seven `=` alone."""
    opens = re.search(r"^<{7} ", text, re.MULTILINE)
    closes = re.search(r"^>{7} ", text, re.MULTILINE)
    return bool(opens and closes)


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


def run(arguments):
    verify_touched, verify_touched_path = load_verify_touched()
    if git("status", "--porcelain", "--untracked-files=no").stdout.strip() and not arguments.resume:
        print("restack-lane: the checkout has uncommitted changes; commit or stash them first.", file=sys.stderr)
        return 2
    rebase_in_progress = any(pathlib.Path(git("rev-parse", "--git-path", name).stdout.strip()).exists() for name in ("rebase-merge", "rebase-apply"))
    if rebase_in_progress:
        print("restack-lane: a rebase is in progress; finish it with `git rebase --continue`, then pass --continue.", file=sys.stderr)
        return 2

    new_base = arguments.new_base
    if git("ls-remote", "--exit-code", "--heads", "origin", new_base, check=False).returncode == 0:
        fetched = git("fetch", "origin", new_base, check=False)
        if fetched.returncode != 0:
            print(f"restack-lane: {fetched.stderr.strip()}", file=sys.stderr)
            return 2
        new_base = git("rev-parse", "FETCH_HEAD").stdout.strip()
    resolved = git("rev-parse", "--verify", "--quiet", f"{new_base}^{{commit}}", check=False)
    if resolved.returncode != 0:
        print(f"restack-lane: `{arguments.new_base}` names no commit.", file=sys.stderr)
        return 2
    new_base = resolved.stdout.strip()

    if arguments.resume:
        # The branch already sits on the new base; the old base is only needed for what the base's move touched.
        old_base = arguments.old_base
    else:
        old_base = arguments.old_base or git("merge-base", "HEAD", new_base).stdout.strip()
    if old_base:
        old_resolved = git("rev-parse", "--verify", "--quiet", f"{old_base}^{{commit}}", check=False)
        if old_resolved.returncode != 0:
            print(f"restack-lane: `{old_base}` names no commit.", file=sys.stderr)
            return 2
        old_base = old_resolved.stdout.strip()

    if not arguments.resume:
        step(f"Rebase onto {new_base[:9]} the commits after {old_base[:9]}")
        rebased = subprocess.run(["git", "rebase", "--onto", new_base, old_base])
        if rebased.returncode != 0:
            conflicted = git("diff", "--name-only", "--diff-filter=U").stdout.split()
            print("Conflicts in:" if conflicted else "The rebase stopped.")
            for path in conflicted:
                print(f"  {path}")
            print("Resolve, `git rebase --continue` until it ends, then run this script again with --continue.")
            return 1
    elif git("merge-base", "--is-ancestor", new_base, "HEAD", check=False).returncode != 0:
        print(f"restack-lane: --continue, but HEAD is not on {new_base[:9]}.", file=sys.stderr)
        return 2

    lane_paths = set(git("diff", "--name-only", new_base, "HEAD").stdout.split("\n")) - {""}
    base_paths = set(git("diff", "--name-only", old_base, new_base).stdout.split("\n")) - {""} if old_base else set()

    step("Conflict markers")
    marked = files_with_conflict_markers(lane_paths | base_paths, read_text_in_checkout)
    if marked:
        for path in marked:
            print(f"  {path}")
        print("A conflict marker is left in the files above.")
        return 1
    print(f"None in the {len(lane_paths | base_paths)} files the branch or the base's move touched.")

    environment = dict(os.environ)
    temporary_directory = verify_touched.caches_directory() / "swiftpm"
    temporary_directory.mkdir(parents=True, exist_ok=True)
    environment["TMPDIR"] = str(temporary_directory)

    step("Build the tests")
    built = subprocess.run(["swift", "build", "--build-tests", "--traits", "sourceBuild"], env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if built.returncode != 0:
        errors = [line for line in built.stdout.split("\n") if "error:" in line]
        print("\n".join(errors[:40]) if errors else built.stdout[-4000:])
        return 1
    print("Built.")

    step("Suites the branch touches and suites the base's move touched")
    command = [sys.executable, "-I", str(verify_touched_path), new_base]
    try:
        for pattern in verify_touched.filters_of_changes(base_paths, read_text_in_checkout):
            command += ["--also", pattern]
    except verify_touched.WholeSuite as reason:
        print(f"The base's move changed {reason}, which reaches every test: running the whole suite.")
        command = ["swift", "test", "--traits", "sourceBuild"]
    if arguments.skip_compile_checks:
        if command[0] == "swift":
            environment["SAFEDI_SKIP_COMPILE_CHECK"] = "1"
        else:
            command.append("--skip-compile-checks")
    tested = subprocess.run(command, env=environment)
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
    expect(files_with_conflict_markers(set(files) | {"Gone.swift"}, files.get), ["A.swift"], "only a file with an opening and a closing marker line is reported, and a deleted file is skipped")
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
