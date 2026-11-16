# Adjudication: `cloud-reports/2.3.1-emitter-design.md` (3b12c7b16) against main a6d44aff

**Ready for E1: yes, after the "before E1" fixes below.** All of them are text edits to the note and plan plus additions to N1's brief; none needs a spike. The path-key design holds for E1–E5. The type-mode sections (3 fixed point, 4) are not ready and must be rewritten before R1 is dispatched.

Checked against main: SG:172–197, 2080, 2104–2141, 3565–3588, 4538–4745, 5055–5122, 5128–5260, 5320–5405, 9890–9900; DTG:1296–1332; `Models/Initializer.swift:246–282`; `Models/Scope.swift` (which is under `Models/`, not `Generators/`) 395–456, 1136–1146, 1304–1322; `DifferentialValueComparator.swift:135–148`; `cycle-generation.md` "Eager instances at a lazy cycle's calls". I did not open the slice-2 snapshot, issue #646 or the retros-branch files, so claims resting only on those are taken from the reviews.

"A" is the first review (byte identity), "B" the second (plan fit).

## Rulings on section 9

### (a) Fills keep a string adapter until E3/E4: ACCEPTED, with conditions
**Reason.** The mock side splices fill text and keeps its empty lines until E4 whatever E2 does (SG:9897), and `inlinedFill` decides output from text (SG:4712–4737). E2 is the longest critical-path item. The note's stated reason is wrong: E2 already sits on slice 7's head, because E1 depends on S1 and S1 on the complete 2.3.0 stack. Replace it with these reasons.

**Conditions (binding).**
1. The boundary runs both ways and the note names each direction with its whitespace rule:
   - (i) Old seam and mock code (`generateFillCode`, `buildSiteCode`, dispatchers, readers, `prepareFillCode`) gets a production subtree as a string from the new plan-and-spell. No old production branch stays alive to serve it.
   - (ii) New production bodies host old seam output (fills, hole sites, dispatchers, readers, `valuesBindingLines`, seam guard lines) as `.verbatim(String)` statements.
2. Only a chunk spelled with empty leading whitespace keeps its empty lines (`prepareFillCode`, SG:3581, consumed at SG:9897). Every deeper level drops them.
3. Section 1.1 says `inlinedFill`'s text tests are the one output decision still driven by text after E2.
4. E2's gate runs the seam, mock and public-mock corpora, not only the base corpus.
5. E3's done-when deletes direction (ii) for seams and (i) for fills. E4's deletes the mock splice.
6. The adapter's lines are fully covered while they exist.

### (b) Production splits by family (d2): ACCEPTED, not gated on Dan
**Reason.**
- It changes nothing a person writes.
- It costs at most two functions per key, so the linear bound holds.
- A Sendable-family node hoisted out of a `@Sendable` builder captures only what that builder's text already captures today, so no new non-`Sendable` capture can appear.
- Under d1, adding one `SendableInstantiator` changes the decorator and placement of functions used by plain places. That is shape instability for no gain.
- It matches the planned seam form.

It is also the reversible choice: removing `family` from the key later only merges classes. So R1 does not wait on Dan's seam wording. If Dan rules d1 for seams, the orchestrator reopens production then.

**Definition (binding; corrects both reviews).**
- **Family.** A place is in the Sendable family if any enclosing builder function up to the body root is `@Sendable` under today's `buildsInSendableFunction`, or if its own function is. A's "nearest enclosing" is wrong: a plain function nested in a plain function nested in a `@Sendable` one would be shared with outside places and then captured across the `@Sendable` function.
- **Decorator.** A type-mode node writes `@Sendable` only if its form requires it by today's rule, or if after placement a `@Sendable` function it is not declared inside refers to it (transitive worklist, cycle closers included). Decorator is not equal to family, contrary to B's (b) and the first clause of A's finding 8. A Sendable-family function left inside its `@Sendable` builder may capture that builder's non-`Sendable` locals, and marking it `@Sendable` would not compile under Swift 6. This is from Swift's capture rule, not from a compile here; R1 adds a whole-literal pin for it.
- R1's "each key in one function" oracle keys by family. N1 counts types built in both families on the lifelike benchmark.

## Fix before E1

| # | Source | Final severity | Verdict and fix |
|---|---|---|---|
| 1 | B S4 | must-fix | **Confirmed.** `.passed`, `.passedWrapper`, `FreeRead`, type-mode `.parameter` and a general body-wide allocator never run in path mode, so they fail the 100% coverage rule and "test through the pipeline". Fix in the note and the plan's E1 row: "E1 and E2 add only what path mode executes. `BuilderKey` arrives in E2 with `place` as its first consumer. `FreeRead`, `ReadOutcome`, `.passedWrapper`, the fixed point and type-mode naming arrive in R1 with their tests." Splitting E1 into stacked PRs (spellings B2/B3; argument source C2; facts B8; one commit per 1.1 decision) is recommended. |
| 2 | A 11 | must-fix (plan text) | **Confirmed**; the plan's E1 row contradicts note section 5. Plan E1: "Path mode keeps `builderFunctionNames(for:enclosingFunctionNames:)`'s renames and the `_received` allocator's seeds (SG:5006–5014) unchanged. No call site's names move in E1." |
| 3 | B S1 | should-fix | **Confirmed.** Section 1.1 was taken from main; the note itself says slices 2–7 move this code. Add: "E1's first commit re-derives this table on slice 7's head by audit: every `.split(`, `.contains(`, `hasPrefix`, `.isEmpty` on emitted text, every `min()`/`max()` over spelled text, every branch on `generatedProperties`. Each gets a port and a gate." |
| 4 | A 3 | should-fix, narrowed | **Partly confirmed.** The instantiator and lazy return rules test the unfiltered array (SG:5216, 5326), and constants filter it (SG:5358). But `generateProperties` only emits children `where fillEmitsCode` (SG:4648), and a hole without a site exists only in signature trees. So an empty chunk is probably unreachable in an emitted tree, and the root's blank line survives only if one is. Add to 2.2: "E1 writes a test that tries to reach an empty chunk in an emitted tree. If it cannot, cite the rejection and remove the filter. If it can, empty chunks are statements and the instantiator and lazy rules count them." Add SG:9897 to 2.2.1 as the consumer that keeps the fill's empty lines. |
| 5 | A 14 | should-fix (raised from nit) | **Confirmed**; it is an output decision and the row misleads, since an elided constant's `let` line counts. Replace the port cell: "true if the body has a seam guard line, any emitting child chunk (an elided constant's binding counts), a dispatcher or a reader." |
| 6 | A 6, B S10 | should-fix | **Confirmed**: note section 8 and plan section 10 contradict. Ruling: no byte diff ships in stack B on a lane's own decision. Add to section 8: "If a corner (E4's mock body only) cannot reach byte identity, that PR keeps today's code for the corner, still covered, and routes only the corner through it, listed under Found and not fixed with R3 as its plan. A reviewed diff instead needs the lead's sign-off, a per-expectation list, equal values and frees under `DifferentialValueComparator` on every corpus and a long run, and a compile on Swift 6.2 Linux and Xcode 26. Never for E1–E3 or E5." Change plan section 10's bullet to match. |
| 7 | A 1, A 5, B S6 | must-fix as a marker now; the rewrite is due before R1 | Add at the top of section 3's type-mode bullets and section 4: "Provisional. Rewritten and reviewed before R1; E1–E5 do not depend on it." |
| 8 | B B1, B S8, B S9 | must-fix now (N1 is running) | Add to N1's brief: (1) profile main on #646 at 12 and 16 screens and the mock variant, with instructions per phase: `createScopeGenerator` passes, `ScopeGenerator.init` facts, validation walks, emission; (2) for the speculative-generation change, report instructions and wall time before and after; (3) lifelike production compile at `-Onone` and `-O`, 2.3.0 head against 2.2.0, and the count of types built in both families. |

## Fix before E2

| # | Source | Final severity | Verdict and fix |
|---|---|---|---|
| 9 | A 2 | should-fix | **Confirmed.** A cycle-closing scope declares no function (SG:5172–5176, 5213); a loop member with cycle parameters writes a second `_received` function (SG:5227–5258); dispatchers and readers are per-call helpers (SG:4683–4704). A's fix text is adopted as written, with the oracle "every place has exactly one node or exactly one closing edge". The plan's E2 row takes the same wording. |
| 10 | A 4 | should-fix | **Confirmed.** `generateArgumentList` and `createInitializerArgumentList` throw `GenerationError.unexpectedArgument` during emission (SG:5061, 5110–5121; `Initializer.swift:246–256`), and the speculative task discards its error (`Scope.swift:1317–1321`). Add to section 1: "The plan step throws the first error in today's emission order. E2 adds a fixture with two throwing places in one root that pins which is reported." |
| 11 | B S2 | should-fix | **Confirmed** (SG:3577–3582 calls `generateProperties`; production bodies host seam lines at SG:5150). Covered by ruling (a), conditions 1–5. |
| 12 | A 9, B S3 | should-fix | Covered by ruling (a). |
| 13 | B S8 | should-fix | **Confirmed**: speculation is one detached task per generator with an empty key. Section 9.1 states that the stage 2 gate reads both instructions and wall time, with parallel subtree planning only if wall time regresses. |

## Fix before R1 (the section 3–4 rewrite)

| # | Source | Final severity | Verdict and fix |
|---|---|---|---|
| 14 | A 1, B S6(ii) | blocking for R1 | **Confirmed.** `BindingInstance` as "the `ScopeGenerator` node" cannot name a node's parameter, a loop rebinding, a `_received` wrapper or a mock parameter. Step 3 sends a disagreement to `.passed` while step 4 splits on one, so the rule is not a total function. A's fix text is adopted with one change: drop the "except when some call site cannot supply the value" split. Validation rejects that shape, and an unavailable read is `nil` to an optional parameter, so the branch would be unreachable code. The rule is: a disagreement is always passed, and splits come only from plan differences. Free reads are transitive (the subtree's reads minus what it binds), which covers B's upward propagation. |
| 15 | A 5, B S6(i) | blocking for R1 | **Confirmed.** `orderedChildren` is per place (SG:4544), and the tree is re-created when the start order differs by path (`Scope.swift:395–401`). Refinement compares each node's ordered, name-free plan (statement kind, callee class or closing edge, argument sources, per-place lines), and `reads` is an ordered list. R1 adds a pin for one type at two places whose children start in different orders. State the round bound and measure it on N1. |
| 16 | B B1 | blocking for R1's done-when | **Plausible; not verified against #646.** The design keeps one `ScopeGenerator` per place and the repeated whole-tree passes (`Scope.swift:449`), so `generate` stays proportional to places whatever the key. Add section 4.1 after N1's profile: if emission dominates, type mode as written suffices. Otherwise R1, or an R0 before it, shares places while the tree is built. That changes code section 1 calls kept, and is gated on identical diagnostics under the rename-invariance oracle and unchanged path-mode expectations. Until then R1 does not promise 2.2.0's instructions. |
| 17 | B B2 | blocking for the stage 3 gate | **Confirmed.** The comparator marks an instance "(built before the probe's value)" (`DifferentialValueComparator.swift:135–146`); path mode keeps the eager `instance` argument and type mode hands the wrapper. Fix section 4 "Lazy cycles": "From R1 on, path mode is test-only and hands the wrapper too, so the modes differ only in sharing. R1 pins the first-read creation with a whole-literal test." Dropping the other path-only policies in R1 is the lane's choice, not required. |
| 18 | B S7 | should-fix | **Confirmed** (fills are planned by the production emitter). "`KeyMode` is chosen per body kind: R1 flips root production bodies; fills and seam initializers flip in R2a; mock bodies and mock fills in R3." |
| 19 | B N2 | should-fix (raised from nit) | **Valid.** A nested local function shadows an outer one, so a same-named nested function would be called silently. Section 5: "In type mode one allocator spans the whole generated body, nested bodies included." |
| 20 | A 7 | should-fix | **Confirmed** (`computeCycleEdges` sorts by `asSource`, DTG:1313–1318). Section 5's claim that first-reach order ignores names is false for mock trees until D16 is fixed. Add: "Path mode keeps `computeCycleEdges` as written. Type-mode mock naming is rename-invariant only after D16; R3 gates on D16's seeds." |
| 21 | B N4 | should-fix | **Valid** under CLAUDE.md's fuzzer rule. R1–R3 each name draws: one type at two places with different reads; one type in both families; a lazy closing call; a `.passedWrapper` read. The coverage-report gate applies to R PRs too. |
| 22 | B S5 | dropped | Superseded by ruling (b): R1 is not gated on Dan. |
| 23 | A 8 | accepted, corrected | See ruling (b). |

## Nits (apply when the section is next edited)

- **A 12, B N5:** `BuilderKey` equality is an explicit projection: `built` is a `TypeDescription`, never an `Instantiable`; `place` compares by identity.
- **B N1 with A 7's `min()` half:** the candidates per label are `label`, `label.instance` and `"nil"` (`Scope.swift:1138–1145`), so the `min()` always prefers `label`. If the dispatcher survives slice 7, port it as an ordered `ArgumentSource` preference, not a `min()` over text. The output is the same.
- **B N3:** the one-function-per-key oracle reads the emitted Swift, not the graph.
- **B N6:** reword "Family in production" with ruling (b)'s reasons.
- **A 10:** "path mode keeps each emitter's first-receive walk as a named policy". The alias difference was not verified; the sentence is harmless either way.
- **A 13:** optional sentence on conditional compilation. Not verified.

## Where bytes are most likely to break
A's ranked list stands: E4's mock body first, then E3's inlining driven by text. The plan step must walk each emitter's own order: `MockParameterNode` for mocks, not the `ScopeGenerator` tree.
