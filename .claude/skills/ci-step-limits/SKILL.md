---
name: ci-step-limits
description: Compare every CI step's `timeout-minutes` with how long the step took in given runs, and print the limits a larger suite has outgrown with the comment each should carry. Use before calling a stack's head final, whenever a change makes the suite or a build noticeably longer, and when a job is cancelled at a step's limit.
---

# Set CI step limits from measured time

A step that can hang has a `timeout-minutes` of about twice its measured duration, with the measurement in a comment beside it. The measurement goes stale when the suite grows: a stack that doubles the suite leaves every test step one slow runner from failing a job whose code is fine, and the failure arrives hours into the final run. `step-limits.py`, beside this file, reads the limits from `.github/workflows/` and the durations from runs, and says which limits no longer follow the rule. Run it from the repository root, in a checkout of the commit the runs built; `S` below is `.claude/skills/ci-step-limits/step-limits.py`. Its `--help` is the full contract.

1. Pick runs that built this head, or the head just below it: one CI run and one Verify run cover most limits, and more runs give a truer longest time. A run in which every compile check was skipped measures a test step at its fastest, so include one whose checks compiled when there is one.
2. `python3 -I S --check RUN…` prints one row per limit: the verdict, the limit, how many times the step was measured, its longest and median time, and the limit the rule asks for. `RUN` is a run id, which the script reads with `gh run view`, or a file holding a run's jobs as `gh run view RUN --json databaseId,jobs` or the REST API prints them.
3. For each `short` row, and each step that ran out of its limit, change the `timeout-minutes` and its comment to what the report's last section prints. A `long` row is for judgment, and its `rule` column gives the figure: a step that downloads keeps a limit sized for a slow network, and a job's own limit is a backstop over its steps', so leave those. `unmeasured` means no given run ran the step to success; name another run, or leave it.
4. Change limits in the same pull request that makes the step slower, or in the stack's cut, never after the final run fails on one.

It exits 1 with `--check` when a limit is short or a step ran out of its limit, and 0 otherwise. Only a step that succeeded is measured, and a matrix job's legs are measured together, since they share one limit.

After changing the script, run `python3 -I S --self-test`. "Check Line Coverage on Linux" runs the same.
