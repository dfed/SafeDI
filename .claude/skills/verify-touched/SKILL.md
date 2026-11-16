---
name: verify-touched
description: Run on this machine only the test suites a branch touches, with generated code compiled as CI compiles it, and print only the failures. Use before dispatching a full Verify or pushing for CI, and after a rebase, so that a run of half an hour is never spent learning what a few local minutes show.
---

# Run the suites a branch touches

`verify-touched.py`, beside this file, works out which suites a branch's changes reach, runs them with `swift test`, and prints each failed test with its issues and the run's last line. Run it from the repository root; `S` below is `.claude/skills/verify-touched/verify-touched.py`. Its `--help` is the full contract.

1. `python3 -I S [BASE] --list` prints the filters and why each is there, and runs nothing. `BASE` is what the branch is measured from (default `origin/main`); in a stack, name the branch below. Uncommitted and untracked files count.
2. `python3 -I S [BASE]` runs them. Generated code is compiled, as a full Verify compiles it; `--skip-compile-checks` is for a first pass only. The whole output goes to the log the script names.
3. Fix what it prints and run it again. Dispatch a full Verify (`gh workflow run verify.yml --ref <branch>`) only once it passes: the full run is still what counts, since a change can reach a suite this selection leaves out.

What it selects: the top-level types of each changed test file, or its whole target when it declares none (a file of helpers); the test targets of each changed directory under `Sources/` or `Plugins/`; and the whole suite for a change to `Tests/SafeDIToolTestSupport`, `Package.swift` or `Package.resolved`. A change to SafeDICore or the tool reaches all five `SafeDITool` test targets, which is nearly the whole suite: when the change is to one area (seams, mocks), run that area's suites first with `swift test --filter`, then this. `--also FILTER` adds suites the diff does not show, for example those a regenerated expectation lives in.

It sets `TMPDIR` to the SwiftPM folder `CLAUDE.md` names and empties it afterwards. It exits with `swift test`'s status, 2 for wrong arguments or a base git cannot find, and 3 when the branch touches no test.

After changing the script, run `python3 -I S --self-test`. "Check Line Coverage on Linux" runs the same.
