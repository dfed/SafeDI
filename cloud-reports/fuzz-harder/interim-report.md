# Fuzz the 2.3.0 stack harder: interim report (2026-11-16, ~05:30Z)

Paused overnight under the rule: no new fuzz rounds until morning. Everything here ran on main 4d8ee5f, before stack #727–#731 landed (58cbc93), unless stated.

## F1 (reported earlier): a passed-up place's fill reads the root's value
Repros: branch claude/project-thread-a6wosh, commit 0880575, cloud-reports/fuzz-harder/repros/. Routed to slice 4 as a must-fix.

## F2 (new, likely F1's family): a fill passes `nil` where the visible build passes a forwarded value
- Seam corpus seed 2006 (`SAFEDI_GRAPH_FUZZER_FEATURES=generateDependencyTree`, outside the 1000-seed corpus).
- Oracle: "the build that fills a hole constructs other values than the visible build".
- Shape: `HoleNestScreen` (FuzzSession) forwards `holeNestId: Int` and builds `holeNestService` (`HoleNestImpl`, FuzzFeature). That builds the hole `holeService`; `HoleImpl` (FuzzApp) receives `holeNestId: Int?` only if available. Below it, a hole fill (`HoleTrackerImpl`) builds `HoleSeam` again through `holeSeamBuilder`, and that inner seam's `HoleImpl` gets `nil`. The visible build gives it 7, the nearest declaration.
- Class: a new-feature bug (2.2.0 had no holes). It's a wrong value in code that compiles. Probably the same cause as F1: the fill reads the outermost scope, not the place's. Not reduced yet.

## F3 (new, low severity): a hole build accepts what its visible build rejects
- Seam seed 1815. `CycleRoot` declares `cycle6Tag: LazilyInstantiated<CycleTag>`.
- Inside `CycleSeam`'s tree, `Cycle4Reader` receives `cycle6Tag: LazilyInstantiated<CycleTag>?` and the hole fill `CycleImpl` receives `cycle6Tag: CycleTag?`, both only if available.
- With `CycleImpl` in App (a hole), the tool accepts and passes `CycleImpl(cycle6Tag: nil)`. With it in Feature (visible), the tool rejects with "receives `cycle6Tag` in two forms … declare it on `CycleSeam`".
- Class: new-feature sibling-path inconsistency. No wrong value against inline, since `nil` is what an inline tree passes a mismatched type. Decide whether the hole build should report the same error.

## Retention on old main (needs a re-check on the new main)
- 19 of 22 unexplained seam seeds in 1000–2060 fail "the seam build keeps alive what the inline build frees", which no corpus entry documents: 1050 1094 1145 1156 1232 1269 1315 1471 1524 1541 1569 1581 1637 1668 1790 1794 2006 2056 2134.
- The leak-fix stack landed after this run. These may already be fixed, or wait on slice 2's builder structs. The first job tomorrow is to re-run these seeds on 58cbc93 (tests are built there).
- The other seam failures in that range (builder surface naming a generated type, renamed-order mock fields) are each documented by some corpus entry when matched one finding at a time.
- Seed 1311 hit the value comparator's 10,000-traversal limit, which is a harness limit and not a bug.

## Release acceptance vs 2.2.0, seeds 5000–9999 (main 4d8ee5f)
122 breaks. None is clearly a regression yet:
- **14 C**, all in families already ruled:
  - 12 are a receive hidden in a mock's tree (#593/#597, or #718 where 2.2.0 used `nil` defaults): 5427 6053 6144 7056 7323 7340 7763 8410 8484 8538 9026 9283.
  - 2 are an `Instantiator` received inside a `@Sendable` builder (#649 second commit, like 1178): 6403 7643.
- **98 F** whose main output shows a loop through received instantiators (#649, release-noted). See release-acceptance-5000-9999-loops.txt.
- **10 F still to attribute**: 5248 6454 6836 7014 7016 7109 7829 9292 9553 9620.
  - Most look like #533: the receiver now gets a nearer declaration in a lazy cycle.
  - 7014 looks like #571/#572: 2.2.0 passed `nil`.
  - 6836 (main builds a fresh `t3` where 2.2.0 passed the root's) and 9292 (a fresh `LazilyInstantiated` value per receive where 2.2.0 shared one) need reduction before a verdict.

Files: interim-report.md, release-acceptance-5000-9999.txt, release-acceptance-5000-9999-loops.txt and seam-1000-2060-unexplained.report, all in /mnt/project-files/fuzz-harder/.

## Update 2026-11-16 ~06:20Z
- The 19 retention seeds still leak on main 58cbc93. All of them are the known in-seam leak. The lead made them stack-level leak acceptance seeds (slice 4 addenda).
- The 10 unattributed 2.2.0 breaks (5248 6454 6836 7014 7016 7109 7829 9292 9553 9620) all bisect to #533 5cf9cbd5.
  - Method: I generated each with SafeDITool built at #532 bbed2888 and at #533. At #532 the output matches 2.2.0's cycle-builder signatures; at #533 it matches main's.
  - What changed: a cycle closed through an instantiator now passes the nearest declaration as a cycle parameter. 2.2.0 captured the declaration above the cycle, or passed `nil`.
  - The lead ruled these Fixes, not Breaking.

## Seam corpus 2061–4999 on main 58cbc93 (~07:20Z)
2939 seeds. 2840 are clean or documented: each finding matches a corpus entry. Unexplained:
- **In-seam leak**: 81 more seeds for the leak acceptance set: 2134 2149 2208 2277 2303 2441 2449 2464 2496 2538 2594 2645 2667 2687 2717 2735 2791 2819 2873 2881 2914 2931 2976 2985 3019 3057 3066 3082 3163 3181 3203 3256 3264 3329 3337 3383 3430 3463 3465 3479 3522 3532 3575 3661 3723 3729 3736 3855 3859 3912 3929 3937 3950 3966 3994 4054 4074 4090 4091 4184 4217 4335 4339 4435 4525 4538 4595 4627 4634 4670 4686 4717 4718 4731 4765 4772 4811 4818 4842 4891 4954. New held things beyond the corpus list include the wrappers themselves (`Instantiator<…>`, `LazilyInstantiated<…>`, `SendableInstantiator<…>`) and `CycleTag`, `ChainBase`.
- **F2, second seed: 3575.** Same shape as 2006: a fill reached through a seam built again inside the hole chain passes `holeNestId: nil`. The visible and inline builds pass 7, so the seam build differs from inline too.
- **F3 upgraded, seed 4668.** In 1815's shape, the hole build passes `S4668_CycleImpl(cycle6Tag: nil)`, while the inline build passes the root's `CycleTag` (unwrapped from `LazilyInstantiated`). That's a wrong value compared with inline. The visible build rejects the graph instead. Oracles: seamBuildsOtherValuesThanInline, seamPassesNilWhereInlinePassesValue, seamAcceptsGraphInlineRejects (visible).
- **F4, seeds 4749 and 4867.** The SwiftPM plugin flow and the module-info flow (Bazel/Tuist) generate different mocks for one graph. In 4867, the plugin flow's `SafeDIOverrides` takes `chainLink: S4867_ChainLink.SafeDIMockConfiguration` plus `chainToken:`. The module-info flow's takes a closure `chainLink: ((S4867_ChainBase) -> S4867_ChainLink)?`, and only the module-info flow emits `S4867_HoleOwner.SafeDIMockConfiguration` in FuzzFeature. `ChainLink` is a seam in FuzzSession. Not reduced yet. A mock's API differing by build system is an adopter-facing inconsistency.
- **Oracle false positive (probably), seed 3855.** #731's builder-label oracle flags `S3855_HoleSeam.mock`'s `holeTicketBuilder: @autoclosure @escaping @Sendable () -> ErasedInstantiator<Int, any S3855_HoleTicketService>`. That's a received instantiator promoted to a mock parameter, not a hole builder, and the label the oracle expects is `erasedInstantiator<Int, any …>SendableBuilder`.
- **Remedy oracle, seeds 2628 and 2862.** Applying the remedy for places of one builder that forward other values changes which builders the seam's init takes: the `@Sendable` family builder is added or kept.
- **Harness limit**: 2897, 3212, 4429, 4631 and 4708 spent the comparator's 10,000 traversals.

## Reductions (~08:10Z)
- **F3**: 2-module repro on branch claude/project-thread-a6wosh, commit 1590d943, cloud-reports/fuzz-harder/repros/f3 (also f3i, f3b). The trigger is a second form of the label inside the seam's tree. Ruled a 2.3.0 blocker owned by slice 5.
- **F4**: documented behavior, not a bug. Repro f4, commit 287fd40d. The fix is fuzzer-only: give the integrations oracle an exemption, or have the module-info flow list the modules a mock reaches.
- **3855, label oracle false positive.** `GraphFuzzerBuilderSurface.isBuilder` counts any parameter whose label ends in `Builder` and whose type is a function type. `holeTicketBuilder: @autoclosure @escaping @Sendable () -> ErasedInstantiator<…>` is a received instantiator promoted to a `mock()` parameter as a deferred pass-through, not a hole builder. Fix: skip `@autoclosure` parameters in `isBuilder`. The generator is fine.
- **2628/2862, remedy oracle false positive.** The failing pair is `.placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied`. In a graph whose types are `Sendable` (`context.isSendableGraph`), the edit declares the inner seam's place as `SendableErasedInstantiator<(), any HoleService>`. A `SendableErasedInstantiator` place belongs to the `@Sendable` family, so the remedied graph adds `holeServiceSendableBuilder` beside the drawn plain `holeServiceBuilder`, and `remedyBuildersJudgment` reports a builder the drawn graph lacks. The generator is right: another family gets another builder, as rule 8 says. Fix: in a Sendable graph, judge the remedy against the drawn builder's `@Sendable` twin, or skip the pair when the drawn place's family differs. Confirmed by generating both seeds with the edit (ExplorationBuilderSurfaceEditTests on my branch).
