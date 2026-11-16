# Slice 6 addenda (fan-out, 2026-11-15 15:40 PST) — wins over the brief

The binding rulings are in `~/Library/Caches/SafeDIScratch/handoff/fan-out-rulings.md`. Read the sections "What the speculative base has and lacks", every ruling that names slice 6, ruling 13 (speculative start, with its per-file table) and ruling 14 (Mac load). Where a ruling gives "lane text", that text is part of this addenda.

BRIEFS = `~/Library/Caches/SafeDIScratch/briefs/2026-11-15-lanes`; BIN = `~/Library/Caches/SafeDIScratch/orchestrator-scratch-2026-11-01/bin`; L = your lane folder `~/Library/Caches/SafeDIScratch/lanes/s2-6/`.

## Message to the lane: slice 6

> Start now. Your addenda file is `BRIEFS/s2-slice-6-addenda.md`; it wins over the brief.
>
> **Base.** `<SLICE2_SHA>` = `163f93d081b76998cc0be2fea3ea292802f6f504`, speculative. It lacks #714's fix-up, `SafeDIToolGraphFuzzerCallingMockTests`, `seamMockTakesHoleValueReason`, `callingMockTakesHoleValueReason`, `builderSurfaceKindsNeverMasked` and current lists (346 public-mock seeds are unlisted on it). Say so in your first progress note and treat every row that names them as "after the rebase", as the brief says.
>
> **Confirmed.**
> - M6: a seam's own mock takes a plain function, no struct, no `__safeDI_mock`. Start M6 and cell 6.14.
> - M1 (b): an erased instantiator that forwards nothing switches.
> - The static-call mechanism of "How a static call is built". If its check fails, stop before commit 3; lane A changes `structDeclaration`, never you.
> - The same-supply floor rule, seed 799's move, and the below-ten rules as the fuzzer file states them.
> - The conversion writer stays for kept calls until slice 7.
>
> **Changed.**
> - The all-`ErasedInstantiator<(), B>` case is not a deliberate difference. On this base it is `() -> B`, in a public mock and in a seam's own mock; add cell 6.12 (c) asserting that, and write no comment, rule or Manual text calling it the lasting type. At your restack above slice 3 its type comes from slice 3's readable-type function and becomes `ErasedInstantiator<(), B>.Builder`. M6's "always `() -> T`" reads "on this base". Name it in the hand-back as owed at the restack.
> - Add `publicMockBuildsOtherValuesThanKnownRight` to the `laterFailures.first(where:)` filter, after the rebase, in a commit of its own, with the masking self-test rerun. A seed it exposes that also fails on the base with only that commit is a base failure: report it, list it nowhere, go on.
> - No T6 rolls: cells 6.6 and 6.7 get no draw here. Slice 7 owns both.
> - Slice 4 does not rename `passUp`; slice 7 does. Keep spelling it through `FillDispatcher.passUpParameterName`.
> - Hand-written builder-struct expectations spell the generic parameter `__safeDI_Built`.
>
> **Before the rebase** you may write commit 1, the folds, the generator commit and new fuzzer code (readers, features, the hand-written callers, unit tests), and do the leak partition as a reading exercise. You may not commit pins or fixture hashes, edit any known-issue list (keep `L/list-edits.md`), commit regenerator output or commit 4b's hand edits (keep `L/hand-edits.md`), touch the never-masked expressions, or run `linux-pins` or a release `linux-verify`. Stops about seeds, pins, hashes and `publicMockCorpusAcceptedSeedsSum` are recorded now and come into force on the final base; stops about generated code, values and retention are in force now. Append `generator commit: <full SHA>` as the brief says.
>
> **New tests are whole literals**, the guard hash written out.
>
> **Rebase.** On my message: `git rebase --onto <final base> 163f93d08`, build the tests, check for conflict markers; then onto the migration commit (once, if both exist). Then regenerate, make 4b, edit lists, pins from `linux-pins`, release `linux-verify`, hand back with all three SHAs.
>
> **Your files:** `PublicMockGeneration.swift` and `GraphFuzzerPublicMocks.swift` are yours alone. Elsewhere only the hunks in the table of `handoff/fan-out-rulings.md`, ruling 13. Never `structDeclaration`, `scopeEnumDeclaration`, `generateFillCode` or `SeamBuilderParameters.swift`. No `CLAUDE.md` edit before the rebase.
>
> **Test runs.** Linux first: `BIN/linux-verify <commit> '<filter>' fast` in the background. `heavy` only for a warm one-file loop, record runs and single seeds, one at a time.


## Owed at the final restack (07c2e7498 rehearsal, 2026-11-16 04:50Z; branch dfed--claude/s2-slice-6-on-07c2e74 @ ceed7a931, clean)
1. Docs commit rewrites Manual ~1330 (public mock's hole builder "always handed the scope … even where the seam's builder takes nothing") and seam-generation.md:37 ("and every public mock's, keeps the closure over its enum"); both contradict slice 6's generator.
2. Cell 6.12 (c)'s `() -> B` becomes `ErasedInstantiator<(), B>.Builder` above slice 3.
3. Run slice 2's reader suites (`GraphFuzzerBuilderStructReaderTests`, `SafeDIToolGraphFuzzerBuilderSurfaceTests`) at the head: slice 6 changes shared fuzzer readers.

## From slice 2's round-2 review (2026-11-16): slice 6 conflicts in Scope.swift ~1283: take one `enclosingFill: EnclosingFill?` through `publicMockCallArgument` and test `enclosingFill == nil` (it replaces `referencedName`). Builder-struct rules move to `.claude/rules/seam-builder-structs.md`.
