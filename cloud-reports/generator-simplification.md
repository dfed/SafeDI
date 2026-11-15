# Generator simplification: what to change, when, and what to leave

Written Sun Nov 15 2026, 10:38 PST (`date`), by a research subagent. Read-only: nothing in the SafeDI repository was edited, built or run. Base: origin/main `247598444` (#708). Inputs: four mapper reports (production, mocks, seams, cross-cutting), the leak-fix slice plan (`s2-slice-plan.md`, its section 5 numbering is used here), the target design, spike 2's report, spike 3's report on `origin/dfed--claude/cloud-mock-overrides-spike`, `per-type-rewrite.md`, and the rules files.

**Evidence marks.** **checked** = I read or diffed the lines on `247598444` myself. **mapper** = a mapper's reading I did not re-read. **guess** = my inference; a test or a build would settle it. No claim here is "built".

**Slices, as the slice plan's section 5 numbers them:** 1 labels (in flight on `dfed--claude/s2-builder-labels`; it changes only `SeamBuilderFamilies.swift`, 53+/34−, checked); 2 seam structs, both families (brief under attack review); 3 forwarding places; 4 carried scopes and pass-up, cases out; 5 diagnostics and guard review; 6 mocks: `__safeDI_mock`; 7 mocks: per-route, pass-up, lazy.

---

## 1. Where the complexity comes from

### Essential (do not try to remove it)

1. **Per-path emission.** Each path through a tree has its own nil decisions, cycle closers, lazily instantiated forms and names, so today's emitter writes one nested local function per path. This is the cost the 2.3.1 per-type rewrite attacks (functions keyed by type, differing values as parameters). No refactor of today's emitter removes it.
2. **Two models on purpose.** Validation (`DependencyTreeGenerator`, about 4,100 lines of walks) decides acceptance and which error is reported by source location. Generation (`Scope` → `ScopeGenerator`) trusts it. They model "nearest declaration" twice (`ScopeDeclarations` and `NearestDeclarations`), and the per-type design keeps both.
3. **No recursion per tree level.** Half-megabyte concurrency stacks force explicit stacks and frame structs in every walk.
4. **Determinism.** Every choice needs a stated order, so each site carries its own sort key.
5. **`Sendable` snapshots.** `MockParameterNode` copies generator facts so mock emission runs off the actor. The rule (`generator-design.md`) requires it.
6. **A cross-module contract.** Seams and public mocks must be recomputed identically by callers, hence the call shape, the guard hash and the callers' view.

### Accidental (this is what the list below targets)

1. **Emission is string joining with no shared spelling sites.** The same construct is spelled again wherever it is needed: the construction call five times (checked: `ScopeGenerator.swift:5123`, `:6682`, `:6996`, `:7838`, `PublicMockGeneration.swift:414`), the wrapper binding four times with three different annotation predicates (checked: `:4768`, `:5606`, `:10099`), the `"@Sendable "` ternary at 18 sites (checked: 15 + 1 + 2), the "nil / `x.instance` / `x`" argument rule about seven times (mapper).
2. **Structure read back from generated text.** `inlinedFill` decides inlining from `lines[0].contains("(_ scope: ")` and `contains(" = scope.")` (checked, `:4717-4722`). `isConstructedByAnnotation` is `asSource.contains("nonisolated(")` (checked).
3. **Names.** `GeneratedNameAllocator.claim` has 7 call sites; the same "append `_` while taken" loop is hand-written at 9 more (checked by grep), three of them with a raw `+= "_"`.
4. **Seams and public mocks run in parallel, not shared.** Two call types with the same fields, two guard hashes, three tier computations (checked: the same expression at `DependencyTreeGenerator.swift:4851`, `SeamBuilderFamilies.swift:513`, `PublicMockGeneration.swift:1012`), two tier chains, two omission walks, and "is this a public mock" encoded five ways (mapper).
5. **Recomputation in place of passing.** `mockRootParameters` has seven callers (checked); one function computes `mockedTypeUncoveredDependencies` at `:6327` and its caller computes it again at `:6554` with the same arguments (checked).
6. **Verbatim copies.** `CycleParameter.forms(providedBy:)` and `DependencyTreeGenerator.formsProvided(by:)` differ only in the parameter name (checked). The two `dependsOn` closures are identical (checked). `cycleParametersOfAnyBuild` and `reboundPropertiesOfAnyBuild` differ in 5 of 23 lines (checked). The alias and hole initializers of `ScopeGenerator` each assign about 60 stored properties by hand and differ in about 12 (checked).
7. **Two files hold everything.** `ScopeGenerator.swift` is 10,637 lines (CLAUDE.md's task text says "over 7,000") and `DependencyTreeGenerator.swift` 10,977. Each holds nine or more concerns, so every agent reads far more than its change needs and every stack conflicts with every other.

My estimate (guess): accidental duplication is 600 to 900 lines of about 26,000 in the generator. The larger gain is not lines. It is that a rule lives in one place, so the leak fix, F5 and 2.3.1 each change one site, not five.

---

## 2. Ranked opportunities

Ranked by (clarity gained × how many later changes it shortens) ÷ risk. "Order" never overlaps an in-flight slice: anything in a seam file or in `ScopeGenerator.swift:883-1893`, `:4600-4738`, `:5438-5904` waits for the slice that owns it or for slice 7.

### Fold into the remaining leak-fix slices

These cost nothing extra, because the slice rewrites the lines and regenerates the expectations anyway.

**A1. Decide fill inlining from the model, not from text.**
- Change: slice 2 rewrites `FillDispatcher.declaration` and the fills into level functions. Whatever replaces `inlinedFill` takes `carriesPayload`, `readsScope`, the scope parameter's name and `readsForwardedValue` from the fill's own data (its fields and its `ScopeGenerator`), never from `code.split`. If level functions make inlining pointless, delete it (guess: the target design's level functions call a fill's member directly, so it may be).
- Gain: about 30 lines, and the coupling between `generateFillCode`'s `scope` name (`:5657-5661`) and the parser at `:4717` goes.
- Risk: low inside slice 2 (output is regenerated); high as a separate refactor, since it would collide.
- Order: slice 2; the forwarded-value half in slice 3.

**A2. Every new name through `GeneratedNameAllocator`.**
- Change: level-function names (rule 6), the `up:` parameter (slice 4), and anything slice 6 adds are claimed, never fixed words. `passUpParameterName = "passUp"` is fixed today, on the argument that generated names start with `__safeDI_` (checked, `:1340-1342`), while mock dispatcher parameters are named by user labels (`RoutePlan.Parameter.name = channel.label`, checked). A channel labeled `passUp` would give two `passUp:` parameters (guess; a public-mock fixture with a dependency labeled `passUp` and a passed-up place settles it). Slice 4 replaces `passUp` with `up`, so the same question applies to `up`.
- Gain: no lines; removes a possible uncompilable shape and stops new hand loops.
- Order: slices 2, 4, 6, as a line in each brief.

**A3. `ReservedName` gets the type names too.**
- Change: slice 2 must add `__safeDI_Builder` and `__safeDI_noScope` (F8), slice 6 `__safeDI_mock`. In the same commits, give `SafeDIScope`/`SafeDISendableScope`/`SafeDIMockScope`/`SafeDISendableMockScope` (spelled at `SeamBuilderFamilies.swift:78/:81` and again at `SeamBuilderParameters.swift:181`) and `SafeDIOverrides` (five literal sites, mapper) one constant each.
- Gain: one grep finds every generated type name.
- Risk: none (no output change).

**A4. Delete what the slices strand.**
- `HoleCallArgument.label` is never read, and `.passUp` entries carry no `enclosingFillKey`, so both consumers (`:203`, `:2003`) skip them (checked). Slice 2 rewrites `builderCallArguments`; drop the field and the `.passUp` entries there.
- The per-site draft names in `holes()` (`SeamBuilderParameters.swift:115-187`: `<property>Builder`, the literal `SafeDIScope_<Owner>_<label>`) are overwritten by `shapedBuilders` for every own place, but passed-up holes keep the draft label and the guard hashes it (mapper). Slice 4 changes pass-up: decide there that a passed-up hole takes the per-family label, then delete the draft naming (about 70 lines; guess on the count).
- `tierOmitsBuilder` prints `hole.builtType` when `builder` is nil while its sibling prints `builder.parameterType` (mapper): F6 already reopens both messages in slice 2 or 5.

**A5. One guard-enum emitter and one guard line.**
- Change: slice 5's guard review extracts `extension T { public enum <guard> {} }` (three sites: `:5888`, `:6696`, `:7016`) and gives seams a `guardLine` like `PublicMockCall.guardLine` (the seam's is inline at `:5150`).
- Do **not** align the two hashes' input order or the `_mock_` name spelling (section 4).
- Gain: about 15 lines.

**A6. "Is a public mock" asked of one value.**
- No work now. Slices 6 and 7 delete F1's gate, `decidesPerRoute` and `RoutePlan`. Add to slice 7's done-when: after it, only `ScopeTypeNames` (or its successor) distinguishes the kinds; `bindsReceivesAgain`, `isPublicMockCall` and `scope.publicMockCall != nil` tests in shared code are gone or derive from it.

**A7. The isolation and `@Sendable` prefix, if F5 chooses (b) or (c).**
- Change: one function, for example `SendableSpelling.localFunctionPrefix(isSendable:)`, returning `""`, `"@Sendable "` or `"@Sendable nonisolated "`, used at all 18 sites; and one for the attribute-prefix idiom (`:5066`, `:5758`, `:6523`).
- If F5 is (b) or (c), this is the first commit of slice 2, so the spelling switch is one line and one regeneration. If F5 is (a), it moves to the between-releases batch (B6) and #661's lane later changes one line.
- Gain: about 20 lines; the main-actor-default work becomes a one-site change.
- Risk: none by itself (no output change).

### Between 2.3.0 and 2.3.1

All of these change no generated byte. The suite's full `==` expectations and the fuzzer corpora prove it: the acceptance test for each is "no expectation file changes". They go in one short stack, opened only when no other stack touches the generator, and before 2.3.1's PR 1 and spike 3's implementation start. Both of those are re-derived on main anyway (spike 2 on the struct; spike 3 is a spike branch), so neither loses work.

**B1. Split the two large files by concern (pure moves).** Highest clarity gain.
- Change: `ScopeGenerator.swift` into extensions by the mappers' areas: facts and initializers; sibling order and loops; cycle closing; builder names; production emission; seam emission; fills and dispatchers; mock root; mock parameter tree; mock structs; mock body; tree analyses. `DependencyTreeGenerator.swift` likewise: seam driver, seam errors, mock orchestration, mock-root promotion, validation walks.
- Gain: scoped rules (`paths:`) can target a concern, so the right rules file loads; agents read 800 lines, not 10,000; parallel lanes stop conflicting in one file.
- Risk: no behavior change, but `private` members used across the new files become internal, and every open branch conflicts. That is why it goes at this gate and nowhere else. `Scripts/unmeasured-files.txt` and any path lists need the new names (guess: also the fuzzer coverage report's file filters).
- 2.3.1: not rewritten by it; it makes 2.3.1's PRs reviewable. The leak-fix slices must not carry it.

**B2. One construction-call function and one erasure wrap.**
- Change: `Instantiable`/node → `ConstructionTarget { case initializer, instantiate, mock(name) }` plus one function that spells `T(…)`, `T.instantiate(…)`, `T.<mock>(…)` through `TypeDescription`, and one `wrapErased`. Five call sites and three to seven erasure sites use them.
- Gain: about 60 lines; closes the standing breach of "Build type spellings through `TypeDescription`" at every construction site, including the skipped `wrappedIfAmbiguous`.
- Risk: low. The root-versus-node difference in *which* initializer is chosen stays (deliberate, section 4); only the spelling is shared.
- 2.3.1: both the per-type body and spike 3's shared builders reuse this spelling (spike 3 reuses `defaultBuilderCall`), so landing it first means both are written once.

**B3. One wrapper-binding function.**
- Change: `let x[: T] = Wrapper(fn)` at `:4760`, `:5604`, `:10090`, `:10364` becomes one function with one predicate, `isConstructedByAnnotation`. Before merging the predicates, write the fixture that separates them: an extension-declared type held in a wrapper whose type differs from its construction spelling (`:4768` has `!isExtension`; `:5606` does not).
- Gain: about 30 lines and one rule for "when to annotate".
- Risk: low to medium; the three predicates may differ on purpose in one case (guess). Slice 2 rewrites the `:5604` site, so it can adopt the function there if B3's function exists; otherwise after slice 7.

**B4. One mock-root model, computed once.**
- Change: a `MockRootModel` value (parameters, parameter names, uncovered dependencies, tree binding names, the root's scope-name set, and for a public mock the plan) built once per root and passed to `generateMockRootCode`, `publicMockFindings`, `fulfillersOfMock`, the query, and `createMockRootScopeGenerator`. Stored per the actor rule (an optional filled by an isolated method, not a `lazy var` with a closure).
- Gain: removes six recomputations of `mockRootParameters`, the plan built three times, five hand-built name sets (`:6147`, `:6204`, `:6459`, `:6616`, `:6873`, mapper) and the double `mockedTypeUncoveredDependencies`; about 80 lines and measurable `generate` time for public mocks with builders (guess; unmeasured).
- Risk: medium. Mock output has the densest expectations, which is also the safety net. `callersViewFinding` deliberately recomputes from the callers' view; that one stays a second computation.
- Order: after slice 7 (slices 6 and 7 rewrite the public path of `generateMockRootCode`), before spike 3's work (which adds a hunk at the same place).

**B5. Shared pieces of seams and public mocks.**
- Change, smallest first: `AccessLevel.tiers(widest:parameterAccesses:)` for the three identical expressions; one `visibleDeclaration(of:instanceProperty:)` (three copies, mapper); one omission walk parameterised by "which call does this scope make" (the two walks share about half their lines: 111 of 233 differ, checked); a shared core struct inside `SeamCall` and `PublicMockCall` for holes, builders, scope enums, guard name, comment, escaping types and `calledBuilders`; `ModuleIdentity` in `SeamCall` in place of four strings.
- Gain: about 120 lines; one walk to fix when a tier rule changes.
- Risk: medium for the walk (diagnostics; which omission is reported must not move), low for the rest.
- Order: after slice 7, because slices 1, 4, 5, 6 and 7 all change these types.

**B6. Property-form and forwarded-property helpers.**
- Change: delete `DependencyTreeGenerator.formsProvided(by:)`; move `CycleParameter.forms(providedBy:)` to `Property` (it has 20 callers, most not about cycles, checked); add one `Instantiable.forwardedProperties` in declaration order and replace the 9 to 11 inline `dependencies.filter { $0.source == .forwarded }` (mapper); merge the two `dependsOn` closures and the two "of any build" walks (one generic walk taking the per-child collector); `mockForwardedArguments` becomes `forwardedArguments(of:spreading: "$0")` (mapper: same function).
- Gain: about 90 lines.
- Risk: very low.
- Also fix the rule text: `lazily-instantiated.md` and a comment at `DependencyTreeGenerator.swift:4818` still name `propertiesToDeclare(in:)`, which no longer exists (checked: only `Scope.propertiesToDeclare` does).

**B7. Remaining hand name loops onto the allocator.**
- Change: the loops that survive 2.3.1 (`PublicMockGeneration.swift:67`, `DependencyTreeGenerator.swift:5482`, `SeamBuilderFamilies.swift:325`, `:461`, `:550`, `ScopeGenerator.swift:9665`) call `claim`. Leave `valuesBindingNames` and the dispatcher locals: slice 4 and spike 2 remove them.
- Gain: about 30 lines; one append rule (`spelledAsJoinedIdentifier`).
- Risk: low; identical output where the base has no backticks (the raw-`+=` sites append to fixed words or stems, mapper).

**B8. One facts value for a scope's bottom-up facts.**
- Change: group the facts `ScopeGenerator.init` computes into a `Sendable` struct with an `empty` value; the alias and hole initializers assign `empty` and override the roughly 12 fields that differ; `MockParameterNode` holds the same struct in place of copying about 15 fields one by one.
- Gain: about 110 lines; a new fact is added once, not in three initializers and a snapshot.
- Risk: medium, from churn (`self.x` becomes `facts.x` across the file unless forwarding properties are kept). 2.3.1's PR 2 changes how `buildsInSendableFunction` is derived, so do B8 before it or not at all; if the gate between releases is short, drop B8 first.

Minor, same batch if cheap: the index-based Tarjan (`ScopeGenerator.swift:4122`) calling the generic one (`DependencyTreeGenerator.swift:4747`) — only if component numbering provably stays the same; comments on why `orderedIndexByUnwrappedProperty` keeps the last index and `firstOrderedIndexByProperty` the first; TypeDescription keys where `asSource` strings key concrete types (`sendableConfigurationTypeNames`, `CycleEdge`, the internal configuration dedupe).

### Inside 2.3.1's rewrite (do not refactor separately)

**C1. Production emission's three branches.** The instantiator, lazy and constant branches each re-derive the function name, decorator, parameters and child call (`:5172-5392`, mapper). `BuilderFunctionGraph` (per-type PR 2) emits a function from one description, so the duplication goes with it. Today's emitter stays behind a test-only option as the differential oracle and is later deleted: refactoring it would be paid twice.

**C2. One argument-source type.** The per-type design already says a value is "captured, `nil`, or a parameter". Make that an enum with a `lazyInstance` case and one spelling function, and have `createInitializerArgumentList`, `cycleParameterArguments`, `callerReads`, `valuesArguments` and the mock's `dependencyArgument` all go through it. This is the seven-site rule of area 6. It also settles the three inconsistent lazy tests (mapper: `Initializer.swift:272` against `Scope.swift:1139` against `:4511`).

**C3. Names.** PR 2's body-wide allocator replaces per-body `builderFunctionNames`. Fold `identifierSafeNames`' four suffix-order lists into one candidate order there, and settle spike 2's open name scheme under the same allocator. Spike 3's `__safeDI_Nested`, `__safeDI_Reference` and `__safeDI_nested` are string literals in `ScopeGenerator.swift` and would fail `SourceRuleTests` (mapper): they need `ReservedName` entries in its first PR.

**C4. One builder key for production and mocks.** Per-type PR 1 adds `BuilderKey`; spike 3 keys shared mock builders on concrete type, instantiated type, erasure, construction, extension-based and forwarded properties. Two key types for one idea would be the next parallel pair. Ask both designs to share one type, with the mock adding "reads a configuration" (guess: feasible; the designs were written apart).

**C5. Spike 3's prework, as its first commits with no output change.**
- Merge the constant-node builder branch (`:9462-9581`) and `generateInstantiatorBinding` (`:10176-10357`), which repeat eight steps in the same order (mapper), into one function. Spike 3 adds shared emission in both; it should add it once.
- One member model for configuration structs: `.calledMockOverrides`, `.nestedConfiguration`, `.builderClosure`, rendered by one struct emitter with an access argument, replacing the three-way branch written four times and the two hand-rolled struct emitters beside `publicStructBody` (mapper). Then the storage change is one site, which is the best lever on its 446 changed test functions.
- `SharedMockBuilders`' "is this label declared again on a path" must reuse the predicate behind `receiveReadsLabelByName`/`removingRenames`, not restate it.

**C6. Cycle parameters and first-receive order.** `mockCycleParameterArguments` and `cycleParameterArguments` carry one rule and one documented gap; PR 2 generalises both into `BuilderParameter`, and optional PR 6 closes the gap. The two first-receive walks treat aliases differently (production skips an alias the type itself fulfils, `:4385`; the mock promotion walk counts every alias, `DependencyTreeGenerator.swift:6840`; mapper). PR 2 should state which is right and add the fixture; whether output differs today is unverified.

**C7. Speculative generation.** `startCodeGeneration` calls `generateCode()` with empty `propertiesGeneratedLater` and default names (checked), while parents ask with per-child keys, so the cache misses for renamed builders, loop members and later siblings (mapper's reading; unmeasured). Per-type makes the cache key the builder key. Measure before and after there; do not tune today's cache.

### Possible defects seen in passing (not simplifications; each needs a fixture before anything else)

Per the leftover rule, none earns a pull request unless a fixture shows uncompilable code or a wrong value in a shape an adopter writes.
- `handWrittenMockDefaultParameters` reduces over `typeDescriptionToFulfillingInstantiableMap.values` and writes `result[concreteInstantiable]` last-write-wins (checked, `DependencyTreeGenerator.swift:462-469`). It reads the concrete entry's dependencies but the iterated entry's `mockInitializer`. Safe only if every entry of one concrete type carries the same mock initializer (guess: true after the `mockOnly` merge). CLAUDE.md's determinism section names exactly this pattern.
- `collectUniqueConfigurationTypes` keys its ancestor set by concrete type only, and `collectSendableConfigurationTypeNames` applies no cycle filter, while the body uses other cycle notions (mapper: five notions for one question).
- A dependency labeled with a word that needs member-declaration spelling: `_Values` fields use `spelledAsMemberDeclarationName`; `SafeDIOverrides` and configuration fields interpolate the raw label (mapper; not compiled).
- `passUp`/`up` against a user label (A2).

---

## 3. Consistency rules worth writing into `.claude/rules`

Each is one or two sentences in the file that owns the topic. Rules 1 to 3 could be `SourceRuleTests` checks, which converge agents better than prose.

1. **One allocator** (`reserved-names-and-spelling.md`). A generated name that shares a scope with any other name is claimed through `GeneratedNameAllocator` (underscore) or `identifierSafeNames` (type suffix, one candidate order). No hand-written `while taken.contains` loop, and no fixed word argued safe by prefix when user labels can name parameters in the same list. Check: a `while … contains` followed by an appended `_` outside the allocator's file fails.
2. **Never read structure back from generated text** (`generator-design.md`). No `contains`, `hasPrefix` or `split` on code the generator emitted, or on `asSource`, to decide what to emit next; carry the fact in the model. A prefilter before a real parse (as `GeneratedImportAccess.swift:312` does, checked) is fine.
3. **One spelling site per construct** (`generator-design.md`). The construction call, the wrapper binding, the erasure wrap, the `@Sendable` and isolation prefix, the guard enum, the guard line and the argument source each have one function; a new emission path calls it. Check: the literal `"@Sendable "` outside its one file fails.
4. **Seams and public mocks share by parameter** (`seam-generation.md`, `public-mocks.md`). What both kinds do is one function taking the kind; a difference is a stated case in that function with its reason. "Is this a public mock" is read from one value.
5. **Mock mirrors of production** (`mock-generation.md`). Where a mock function carries a production rule, it calls the production function on value inputs. Where it cannot (the snapshot boundary), both carry a comment naming the other, as deliberate gaps already do.
6. **Compute once per root, then pass** (`mock-generation.md`). A function that needs a mock root's parameters, names or plan takes them as an argument. The callers' view is the one named exception.
7. **Forms and forwarded properties have one accessor each** (`lazily-instantiated.md`), replacing the stale sentence about `propertiesToDeclare(in:)`.
8. **Concrete types key by `TypeDescription`**, never by `asSource` (`generator-design.md`).
9. **A member a generated struct declares or reads is spelled through `spelledAsMemberDeclarationName`/`spelledAsMemberReference`** (`reserved-names-and-spelling.md`), once its fixture exists.
10. **A new bottom-up fact goes in the facts value** (after B8), so alias, hole and fill scopes and the mock snapshot get it by construction.
11. **Record the deinit exception.** `generator-design.md` forbids `nonisolated(unsafe)`, and four properties use it (checked: `Scope.swift:1801`, `ScopeGenerator.swift:3374`, `:8040`, `:8043`), each "mutated only by `deinit`" to release children one at a time. Either name that as the allowed primitive or add a `SourceRuleTests` waiver form for it; today the rule and the code disagree silently.
12. **Stale instruction text**: CLAUDE.md says `MockContext` carries four things (it holds six, mapper); fix when B1 moves it.

---

## 4. What not to touch, and why

- **The validation walks** (`DependencyTreeGenerator.swift:6429-10497`). Each has its own frame struct and its own "keep only completed walks" memo. Unifying them risks changing which error is reported first, for no adopter-visible gain. Per-type keeps them as the diagnostic model.
- **The two nearest-declaration models.** Deliberate ("two models").
- **Sibling ordering, `ReceivedBuilderLoops`, the index maps.** Correct through subtle indirections (the by-value form of a lazy sibling, mapper), recently landed, and PR 2 touches the same lines. Add comments only.
- **The guard hashes' inputs and names.** The seam and mock guards hash in different orders, and only the mock hashes `labelsBoundLater` (documented). Aligning them renames every guard and regenerates expectations for nothing a user sees. F4's work in slice 5 is the only change they need.
- **The enum model after the cases leave the output.** The guard hashes it (F4); `scopeEnumsByType`, `markingIndirectCases` and `SeamDeclarationGraph` stay as the model through 2.3.1.
- **Deliberate differences**: the root's and a node's choice of construction initializer (the two-layer mock return type); the eager instance at a lazy cycle's closing call (2.3.1's optional PR 6); `callerReadLabels` cleared for mock fills; public against internal `@Sendable` default storage; the isolated public mock's defaults as parameters (decision 53); the query skipping whole-module gates; `mockBuildsFirstGeneric`.
- **`nonisolated` on internal `SafeDIOverrides`, and the explicit `internal` spelling.** The first is F5 option (c), parked behind #661 and Dan's. The second is churn across mock expectations.
- **`MockParameterNode` as a snapshot.** Keep it; only stop copying fields one by one (B8).
- **Today's per-path emitter, once 2.3.1 starts.** It becomes the differential oracle and is then deleted.
- **`SeamSignature`, `SeamAccessExplanation`, `TypeAccessProof`, the access infrastructure, `fields(of:)`.** Large but not duplicated in a way that costs changes. `levelDeclarations` and `receivesBoundAgainOfAnyBuild` say they follow `fields(of:)`; the rule 5 field-set decision in slice 2 may change all three together, so leave their merge to that decision.
- **Any refactor inside a file an open slice edits.** Slice 1 owns `SeamBuilderFamilies.swift` now; slices 2 to 7 own the seam and public-mock paths.

---

## 5. Recommended sequence

**Now, while slices are in flight:** nothing in `Sources/`. Add A1 to A7 as lines in the slice briefs (slice 2's brief is still under review, so A1, A2, A3, A4's first item and A7 can go in before it settles). Decide F5 first: it decides whether A7 is slice 2's first commit.

**In the slices:** slice 2: A1, A2, A3, A4 (dead field), A7 if F5 is (b) or (c). Slice 3: A1's forwarded half. Slice 4: A2 (`up`), A4 (draft names, passed-up label). Slice 5: A5, A4 (message). Slice 6: A2, A3 (`__safeDI_mock`). Slice 7: A6 as a done-when.

**Between 2.3.0 and 2.3.1, one stack, no output change, opened when no other generator stack is open:** B1 (file split) first, since everything after it is then a small diff in a small file; then B6, B2, B3, B7, B5, B4; B8 last and optional. Write section 3's rules in the same stack, each with the change that makes it true. Gate: every expectation file unchanged, fuzzer corpora unchanged.

**In 2.3.1:** C1 to C4 and C6 to C7 inside the per-type PRs (PR 1 the key, PR 2 the graph, names and argument source); C5 as the first, output-neutral commits of the mock-overrides work, before its storage change.

**Not recommended at any point:** a general "intermediate representation" for emitted Swift. B2, B3, A7 and C2 give most of its benefit as four small functions, and 2.3.1's function graph is the real replacement for per-path string assembly.
