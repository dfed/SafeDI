# Slice 3 addenda (fan-out, 2026-11-15 15:40 PST) — wins over the brief

The binding rulings are in `~/Library/Caches/SafeDIScratch/handoff/fan-out-rulings.md`. Read the sections "What the speculative base has and lacks", every ruling that names slice 3, ruling 13 (speculative start, with its per-file table) and ruling 14 (Mac load). Where a ruling gives "lane text", that text is part of this addenda.

BRIEFS = `~/Library/Caches/SafeDIScratch/briefs/2026-11-15-lanes`; BIN = `~/Library/Caches/SafeDIScratch/orchestrator-scratch-2026-11-01/bin`; L = your lane folder `~/Library/Caches/SafeDIScratch/lanes/s2-3/`.

## Message to the lane: slice 3

> Start now. Your addenda file is `BRIEFS/s2-slice-3-addenda.md`; it wins over the brief.
>
> **Base.** `<SLICE2_SHA>` = `163f93d081b76998cc0be2fea3ea292802f6f504`, speculative. It lacks the compile of C, its kind and floor, the masking self-test, #714's fix-up and current lists. Do not build them and do not stop for them. The must-contain list is checked on slice 2's final head, which I will message; the cell-2.7 roll is off the list, replaced by the handwritten test `generate_declaresFieldOfInternalTypeAtItsAccess_whenPublicSeamsPathRunsThroughInternalTypes`.
>
> **Rulings.**
> - No commit 0: the generic parameter is already `__safeDI_Built`. Confirm it in your first progress note. Cell 3.15's cases are still yours.
> - Builders stay sorted by label. A new roll's seed that fails only by that reorder joins the existing `seamBuilderOrderReason` entry.
> - F9 is settled: a switched mock's builder follows the seam's type table at lane B's restack. Keep the readable-type computation a function of a builder's places and family, with no seam-only state. No mock output changes here.
> - F8 compares `.fill` places as written. Append the new retention field last and list its public-mock pin for lane B.
> - `remedyAddsBuilder` stays never masked; remove only the flip seeds your switch makes pass.
>
> **Before the rebase** you may write commit 1, the generator commit and new fuzzer code (draws, features, readers, unit tests). You may not commit pins or fixture hashes, edit any known-issue list (keep `L/list-edits.md`), commit regenerator output or commit 3b's hand edits (keep `L/hand-edits.md`), touch the never-masked expressions, `builderSurfaceFlooredKinds` or the compile of C, or run `linux-pins` or a release `linux-verify`. There is no `L/pins-base/` run. Stops about seeds, pins and hashes are recorded now and come into force on the final base; stops about generated code, values and retention are in force now. Append `generator commit: <full SHA>` as the brief says.
>
> **New tests are whole literals**, the guard hash written out; only a value a test argument decides is interpolated.
>
> **Rebase.** On my message: `git rebase --onto <final base> 163f93d08`, build the tests, check for conflict markers; then onto the migration commit when I name it (once, if both exist). Then regenerate, make 3b, edit lists, pins from `linux-pins` read against slice 2's final pins report, release `linux-verify`, hand back with all three SHAs.
>
> **Your files** are the seam side only: see the table in `handoff/fan-out-rulings.md`, ruling 13. Never `PublicMockGeneration.swift`, `GraphFuzzerPublicMocks.swift` or `SeamBuilderParameters.swift`. No `CLAUDE.md` edit before the rebase.
>
> **Test runs.** Linux first: `BIN/linux-verify <commit> '<filter>' fast` in the background. `heavy` only for a warm one-file loop, record runs and single seeds, one at a time.


## Owed at the final restack (from the 07c2e7498 rehearsal, 2026-11-16 04:50Z; rehearsal branch dfed--claude/s2-slice-3-on-07c2e74 @ b8c99a35d, clean)
1. `placeValue(of:)` (ScopeGenerator ~5003) binds a fixed, unreserved `forwarded`; claim it from the member allocator (`memberNames`) as slice 2's adbd2bcc4 does for every other conversion binding, and add a failing-first test with a place property or builder labelled `forwarded`.
2. Run slice 2's grown suites at the head before migrating (`SafeDIToolSeamBuilderStructTests|SafeDIToolSeamBuilderStructMatrixTests|GraphFuzzerBuilderStructReaderTests|SafeDIToolSeamHoleLazyInputTests`); migrate what moves through the regenerator only.
3. Docs commit: seam-generation.md:37 (names `declaresBuilderStructs(of:holesBySite:)`, gone), ScopeGenerator.swift:1033 doc (missing `holesBySite:`), `knownBuilderSurfaceKinds` doc (~GraphFuzzerBuilderSurface.swift:1250), Manual ~835 (re-read against `placeValue`, which treats every `isAnyInstantiator` place as a wrapper-builder place).
4. Reader fixture `switchedAndKeptHome` (GraphFuzzerBuilderStructReaderTests ~272-322) models code the tool no longer generates: regenerate from the tool at the migration, move its "kept" coverage to a shape that still keeps the closure (an inner-seam case), add the wrapper `.Builder` row to the probe test (~159-186).
5. Forwarding floor: append `GraphFuzzerDrawnHolePlace(kind: .forwarding, returnedTypeName:)` for holeHandedBuilder, holeHandedErased, holeHandedLater, holeServiceLater (each place that forwards a value). Ruling (orchestrator): a place forwarding `()` (holeLaterBuilder) does NOT count toward the forwarding floor; it is the nothing-forwarded shape, judged under its own draw.

## From slice 2's round-2 review (2026-11-16): this head conflicts with slice 3's rehearsal in Scope.swift ~1283: keep slice 2's `enclosingFill: EnclosingFill?` (replaces `referencedName`) and its `let valuesName = …` allocator line. seam-generation.md's builder-struct paragraphs move to `.claude/rules/seam-builder-structs.md` in slice 2's final commit: put slice 3's docs edits there.
