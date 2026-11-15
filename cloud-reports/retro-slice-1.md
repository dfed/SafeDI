# Retro: leak-fix slice 1 (builder labels), for the developer-productivity lane

2026-11-15. Sources: the worker's transcript timeline, its scratch folder (`lanes/s2-1`), `review-verdicts.json`, the briefs, the tools' headers. Savings marked "estimate" are not measured.

## Where the wall clock went

269 minutes from start to the second `linux-verify` (still running when measured). About 60 minutes were editing and reading; about 197 (73%) were waiting.

| Wait | Minutes | Needed? |
|---|---|---|
| Single seeds, one `swift test` process each (10 + 1 + 3 + 48 + 7 + 144 = 213 seeds) | 96 | Only the 21 roll, mutation and base seeds (17 min). The other 192 seeds (79 min) asked one question: which builder-surface list entries went stale. `linux-pins` answers that for the whole corpus in about 33 minutes, off this Mac, and its report has a stale-entries section. |
| `linux-verify`, release, full suite, twice | 67+ | Once. The second run verified review fixes that touched tests, comments, docs and the source-rule check, not the generator. |
| Expectation renames: three near-full local runs plus hand-fixing a home-made rename script | 34 | No. `Scripts/regenerate-expectations.py` now exists. |
| Final local targeted run (run6) and fuzzer filter run (run5) | 24 | Partly: run5's fixture-hash pin was derived before the list it hashes was final, so run6 failed on it. |
| Idle while the review ran | 13 | No: the review started only after `linux-verify` #1 finished (35 minutes later than it could have). |
| `heavy` queue for a 0.84 s incremental `swift build --product SafeDITool` | 14 | No: `Sources/` had not changed since the tool was last built. |

No line reached `productivity-inbox.md`, though three waits passed `common.md`'s thresholds.

## What the review found that a cheaper check would have caught

Of 15 confirmed findings, none was a generator defect. Eleven were text:
- **Overclaims (4).** The Manual, a doc comment and the pull request body said adding a place "never renames" a builder; the worker's own tie-break test showed a rename. A check of each "never/always/only" sentence in the diff against the tests catches all four.
- **Pull request body rules (4).** Leftovers without a named plan, history, a count ("two cases") where a third exists.
- **Stale comments (2).** Fuzzer-support comments still said "colliding stems". A grep of `Tests/` for the old rule's words after changing a rule catches both.
- **One test, two behaviors (1).** Its name contained "Or".

Three were test-matrix gaps (the six-order test did not include the brief's own `Impl_Api` example; the App side was not compared; one position unaccounted). A done-when line quoting the required trio catches the first. One (the source rule's scope) was a judgment call.

So a ten-minute self-review pass with a fixed checklist, run while `linux-verify` #1 waited, would have removed most of the review round (22 minutes active, 14 queued, and the second 32-minute `linux-verify`).

## (A) For the slice 2 worker, now

1. **Do not run seeds singly to find stale list entries.** Run singly only the roll's seeds, with and without the hand mutation. For every other list removal, commit your work and run `linux-pins <commit>` in the background (about 33 minutes, no Mac slot); take stale entries from its `report.md`. Slice 1 spent 79 minutes on 192 such seeds.
2. **Start `linux-pins` and the release `linux-verify` together**, on the same commit, as soon as the generator and handwritten tests are committed, not after lint. Keep editing docs, rules and the pull request body while they run. Re-run only what a later commit can change: after a docs, comment or test-only commit, use `linux-verify <commit> '<the touched suites>' fast`, not the full release run.
3. **Start waits with `run_in_background`, not a foreground `until … sleep` loop.** Each foreground loop dies at about 170 s; slice 1 made about 60 such calls. For a run id, `gh-wait-run --timeout 570 <id>`.
4. **Expectations: regenerator only.** Never infer renames from failure diffs with your own script; slice 1 lost about 15 minutes and two 7-minute runs to that.
5. **Pin order.** Edit `seamSmokeAndKnownIssueFixtureHash` and `publicMockSmokeAndKnownIssueFixtureHash` last, after every known-issue list is final, then run `fixture_matchesReferenceHash` once.
6. **Never queue on `heavy` for a tool that is already built.** After your first local build, copy `SafeDITool` to your scratch folder with the output of `git rev-parse HEAD:Sources` in its name. If that hash is unchanged, use the copy. Otherwise use `linux-probe`.
7. **Base checks in one swap.** List every check that needs the base source (base seeds, "fails on base" tests), swap `Sources/` once, run them all in one script, swap back.
8. **Edits as script files from the start.** The worktree checker refuses multi-line heredocs, compound commands and `$(…)` in tool arguments. Write a `.py` file in scratch and run it; pass literal SHAs. Read a file before Write.
9. **Before hand-back, while `linux-verify` runs, check your own text** (ten minutes):
   - every sentence with "never", "always" or "only" in the Manual, doc comments, rules and the pull request body: name the test that would fail if it were false, and look for one of your tests that contradicts it;
   - grep `Tests/` and `.claude/rules/` for the words of the rule you replaced;
   - each pull request leftover names a pull request or a release; no history; no counts of cases where a rule can be stated;
   - no test name contains "Or" or "And" joining two conditions;
   - each handwritten test the brief gives an example for uses that example.
10. **Log waits** to `productivity-inbox.md` at the thresholds (heavy queue over 5 minutes, `linux-verify` or `linux-pins` over 20).

## (B) Tools and harness, for the orchestrator

Ranked by minutes saved per slice.

1. **Review in parallel with verification (saves 35–50).** Ask the worker to hand back at its last content commit and start the review workflow and `linux-verify` at once; one release `linux-verify` then runs on the commit that holds the review fixes. Cost: a sentence in the hand-back rule; a failed verify may send a second fix round, which the fixes commit absorbs.
2. **`linux-pins` as the stale-list oracle (saves 60–80 on slices that shrink lists).** Already built. Cost: confirm its report lists stale builder-surface and public-mock entries by kind (its header says "stale"; not checked against a real builder-surface list here), and hand the worker the report path.
3. **A seed-list input for the long run (saves about 10 on rolls; estimate).** `SAFEDI_GRAPH_FUZZER_SEEDS=98,311,383` in one process instead of one 17–27 s process per seed. Cost: a small test-support pull request, or a `run-seeds` tool in `bin/` that all lanes share.
4. **Pre-hand-back text lens (saves most of a review round, 20–60).** A Sonnet agent with item 9's checklist over the diff, run by the worker's workflow before the Opus lenses. Cost: one prompt file.
5. **Split `verify.yml`'s Test step across runners by test target (saves 15–20 per full verify; estimate).** The step took 33.75 minutes. Cost: a workflow pull request on main, kept in step with "Build and Test on Linux"; measure before adopting.
6. **`heavy` and `linux-verify` log their own long waits to the inbox (saves no minutes; makes them visible).** Workers did not log. Cost: a few lines in each script. Also: `heavy` could skip the queue for `swift build --product SafeDITool` when the build is already up to date, or `bin/` could offer a cached-tool helper (item A6).

## (C) Future briefs

1. **Split the "which entries went stale" work out of the worker's loop:** the brief names the roll's seeds only and says every other list edit comes from `linux-pins`. (Slice 2's brief already says this; slices 3, 5 and 6 should.)
2. **Order of work states the parallel waits:** "commit, start `linux-pins` and `linux-verify`, then write docs and the pull request body".
3. **Done-when quotes each required fixture example literally** (for instance "the six-order test permutes `Impl_Api`, `Impl` as `any Api`, and one more"), and says "compare every module's generated file" where a caller module exists.
4. **Add the self-review checklist (A9) to `common.md`** under "Hand-back", and "universal claims need a named test" to the documentation step.
5. **State the shell limits in `common.md`:** no heredocs, no compound commands, no command substitution in tool calls; edits go in scratch script files.
6. **Name the regenerator and forbid home-made rename scripts** wherever a brief expects expectation churn.
