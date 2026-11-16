---
name: restack-lane
description: Move a branch onto a new base and check the result in one command, rebase, conflict markers, test build, the suites the branch and the base's move touched, and lint. Use whenever the branch below yours in a stack changes or main moves, before pushing the restacked branch.
---

# Restack a branch and check it

`restack-lane.py`, beside this file, does the steps `CLAUDE.md` asks for after a rebase, in order, and stops at the first that fails. Run it from the repository root, on the branch, with nothing uncommitted and no untracked file the test step would count as a change (any but those no test reaches); `S` below is `.claude/skills/restack-lane/restack-lane.py`. Its `--help` is the full contract.

1. `python3 -I S NEW_BASE` rebases the branch's commits onto `NEW_BASE`, moving no other branch, after printing the commits it moves and the command that undoes it. A branch `origin` has, named `X` or `origin/X`, is fetched and used at `origin`'s commit, never at the remote-tracking ref the checkout last saw; given as `X`, the script stops when your local branch `X` is at another commit, and you name `origin/X` or the commit. When the old base was itself rebuilt, which is the usual case in a stack, name the commit the branch's own commits start after: `--old-base REV`. Without it the script takes the merge base, which would replay the old base's commits; it stops and prints the `--old-base` to pass when the reflog of the base's remote-tracking ref or local branch shows where the branch left it. A fresh clone has no such reflog, so read the commits it lists.
2. On a conflict it lists the files and stops, with the rebase in progress. Resolve, `git rebase --continue` until it ends, then `python3 -I S --continue NEW_BASE`, which skips the rebase, takes the old base from what step 1 recorded, and runs the checks. When the rebased branch lacks a commit it had, with or without a conflict, the script names the subjects and exits 1: git drops a commit whose change the new base already holds. Once none of them is work the base lacks, `--continue --accept-drop` goes on.
3. After the rebase it fails on a conflict marker in any file either side touched, then builds the tests and runs the suites the branch touches and the suites the base's move touched through the `verify-touched` skill's script (its runner, its own temporary folder, generated code compiled unless `--skip-compile-checks`), and runs `./CLI/lint.sh --check`. When a change reaches every test (a test helper, `Package.swift`), it runs no test, prints the full Verify to dispatch, still lints, and exits 3: the whole suite is not this machine's work. Start it in the background. `--runner COMMAND` (or `SAFEDI_VERIFY_RUNNER`) puts a command before `swift test` and the lint, for a machine that queues heavy work; a signal that ends the script ends what it started.
4. It prints the new head and never pushes. Push under your own rules, and dispatch the full Verify only now.

When step 3 fails on expected text that the base's move changed, regenerate the expectations (the `regenerate-expectations` skill, where the branch has it) and run the script again with `--continue`; do not edit expectations by hand.

It exits 0 when every step passed, 1 when a step failed, 2 for wrong arguments or a checkout that is not ready, and 3 when everything it ran passed and the whole suite is still owed.

After changing the script, run `python3 -I S --self-test`. "Check Line Coverage on Linux" runs the same.
