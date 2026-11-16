---
name: restack-lane
description: Move a branch of a stack onto its parent's new head, from a record of the head it was built on, so only the branch's own commits are replayed. Use whenever the branch below yours changes or lands, before pushing the restacked branch.
---

# Move a stacked branch onto its parent's new head

When the branch below yours is rebuilt or lands on main as one squashed commit, the commits your branch sits on are no longer in it, and `git rebase PARENT` would replay them. `restack-lane.py`, beside this file, keeps a record of the parent head each branch was built on and runs `git rebase --onto NEW_PARENT OLD_PARENT` from it. It never guesses the old head. Run it from the checkout, on the branch, with nothing uncommitted; `S` below is `.claude/skills/restack-lane/restack-lane.py`. Its `--help` is the full contract.

1. Once per branch, when you build it on its parent or first use the script: `python3 -I S --record PARENT`. The record is a ref in this clone (`refs/stack-parent/BRANCH`); `--show` prints it.
2. Each time the parent moves: `python3 -I S --onto NEW_PARENT`. Write `origin/X` to use the commit `origin` has now. A parent that landed on main is `--onto origin/main`. For a branch built in another clone, which has no record here, add `--old-parent REV`, the parent's head the branch was built on. It prints the commits it moves and the command that undoes the move, and moves no other branch.
3. On a conflict it lists the files and stops. Resolve, `git rebase --continue` until it ends, then `python3 -I S --finish`. Or `git rebase --abort`, which leaves the branch and the record as they were.
4. It then names any commit the branch had and no longer has (git drops one whose change the new parent already holds; exit 3), fails on a conflict marker left in a file the branch changes (exit 1), and prints the commands to compare the branch with before and to check it: the `verify-touched` skill from the new parent, and the lint. It never pushes.

When a check fails on expected text the parent's move changed, regenerate the expectations with the `regenerate-expectations` skill; do not edit them by hand.

One run at a time per branch: a second stops and names the process holding the lock. After changing the script, run `python3 -I S --self-test`. "Check Line Coverage on Linux" runs the same.
