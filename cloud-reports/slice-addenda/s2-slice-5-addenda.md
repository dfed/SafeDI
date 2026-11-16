# Slice 5 addenda (fan-out, 2026-11-15 15:40 PST) — wins over the brief

The binding rulings are in `~/Library/Caches/SafeDIScratch/handoff/fan-out-rulings.md`. Read the sections "What the speculative base has and lacks", every ruling that names slice 5, ruling 13 (speculative start, with its per-file table) and ruling 14 (Mac load). Where a ruling gives "lane text", that text is part of this addenda.

BRIEFS = `~/Library/Caches/SafeDIScratch/briefs/2026-11-15-lanes`; BIN = `~/Library/Caches/SafeDIScratch/orchestrator-scratch-2026-11-01/bin`; L = your lane folder `~/Library/Caches/SafeDIScratch/lanes/s2-5/`.

## Message to the lane: slice 5

> Start now. Your brief is three files (`s2-slice-5.md`, `-tables.md`, `-fuzzer.md`) plus `BRIEFS/s2-slice-5-addenda.md`, which wins.
>
> **Base.** `163f93d081b76998cc0be2fea3ea292802f6f504`, speculative. It has slice 2's regenerated and hand-updated expectations but stale lists and no pins commit. The hand-back is made on the migration commit, which I will message after slice 2's final head.
>
> **Rulings.**
> - A5 keeps its public-mock hunks: lane B changes only what the public mock's guard hashes, not its emitter or `PublicMockCall.guardLine`. Ignore "expect to drop it there".
> - Hand-written builder-struct expectations spell the generic parameter `__safeDI_Built`.
> - `BIN/linux-pins-analyze.py` does not know `level-captures` yet. Say so in your first progress note and go on; it will be taught before your commit 6.
>
> **Before the rebase** you may write the oracle's file and unit tests, the G4 tests, the guard tests, A4, the rewording in `Sources`, the Manual paragraph and the rules text. `L/reword.py` may be written and run as a dry run; its changes to `Tests/` are committed after the rebase onto the migration commit, where it is rerun over all of `Tests/`. You may not commit pins, counts read from a corpus run, or any list edit, and you run no `linux-pins` or release `linux-verify`. Stops about seeds and pins are recorded now and come into force on the final base; a change in generated output is a stop now.
>
> **New tests are whole literals**, the guard hash written out.
>
> **Rebase.** As the tables' "Rebase": `git rebase --onto <final base> 163f93d08`, then onto the migration commit (once, if both exist), then `reword.py`, the pipeline counts, the mutation seed, `linux-pins`, release `linux-verify`, hand back with all three SHAs.
>
> **Your files:** `SeamBuilderParameters.swift`; message text and the tier loop in `DependencyTreeGenerator.swift`; one hunk in `SeamBuilderFamilies.swift`; A5 in `ScopeGenerator.swift`; your four new test files; the narrow hunks the brief names in `GraphFuzzer.swift`, `SafeDIToolGraphFuzzerTests.swift` and the combine script. Never `PublicMockGeneration.swift` or `GraphFuzzerPublicMocks.swift`. No `CLAUDE.md` edit before the rebase.
>
> **Test runs.** Linux first: `BIN/linux-verify <commit> '<filter>' fast` in the background. `heavy` only for a warm one-file loop and single seeds, one at a time.

