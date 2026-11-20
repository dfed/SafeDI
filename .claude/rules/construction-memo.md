---
paths:
  - "Sources/SafeDICore/Generators/ConstructionMemo.swift"
  - "Sources/SafeDICore/Generators/ScopeGenerator.swift"
  - "Sources/SafeDICore/Generators/DependencyTreeGenerator.swift"
  - "Sources/SafeDICore/Generators/DependencyTreeGenerator+{MockOrchestration,MockRootPromotion,SeamDriver}.swift"
  - "Sources/SafeDICore/Models/{Scope,ConstructionGraph}.swift"
---

# The construction memo

`ConstructionMemo` lets a place reuse a generator another place built: a hit needs an equal key and a read log that the new place's context answers alike (`ConstructionMemo.swift`'s header has the argument). Production trees keep a memo per tree; the mock roots share one, a local of `generateMockCode`'s loop, carrying first-pass entries only. A tree with a seam root or a mock root's builders keeps a memo of its own, for one pass, because it reads its own `SeamHoles`.

A memo that only one tree reads, every memo but the one the mock roots share, neither keys, looks up nor stores a place of a scope the tree builds at one place only (`ConstructionScope.isAtOnePlaceOfTheTree`, which `ConstructionGraph` decides once per tree from how many references reach each scope): no other place of a pass has that place's key, and the pass after builds the place again rather than reusing it settled. A place records its subtree's reads (`ScopeGeneratorUnderConstruction.recordsReads`) only where it has a key or is beneath a place that has one: only a place with a key is stored, and every place beneath it records, so an entry's log holds every read its subtree made, while the reads of a place beneath no keyed place reach no entry. `SafeDIToolConstructionMemoTests`' `generate_keys…` tests and `SafeDIToolMockConstructionMemoTests`' `mock_keysPlacesBuiltAtOnePlaceInMemo_whenMockRootsShareMemo` count the places keyed.

**Every input a place's build takes, and every value a generator stores without querying the context, is in the key, in the log, excluded, or constant for a stated reason, and is listed here.** A new one is added here in the change that adds it. The memo oracle (`ConstructionMemoOracle`, which the test executors install) compares every tree built with and without the memo by reflection, so a miss fails the first test or fuzzer graph whose places differ in it; dropping the cycle parameter context read from the log fails base-corpus seeds 35 and 168. Its build with the memo shares one memo across trees whatever the tree's own sharing, so under a production root it keys every place, and it takes the one-place skip only in a tree with a seam root or a mock root's builders. A production tree's own build reuses at a subset of the places the oracle's reuses, and each of its stored entries holds a whole log because every place beneath a keyed place records, so the oracle's judgment still covers it.

"Excluded" means only places the memo neither stores nor reuses hold the value in a non-trivial form: `memoKey` is `nil` inside a fill and in a tree with seam holes, and `isMemoizable` is cleared up through every ancestor by a fill, a scope inside one, non-empty `seamHoles`, non-empty `holeArguments` (a seam or public mock call with holes), and `addHoleGenerator`.

Construction reads the scopes through `ConstructionGraph`, a `Sendable` snapshot taken once per tree before its first pass, never through `Scope` itself: a scope's key is its `ConstructionScopeIdentity`, which the memo keeps alive. A new read of a scope during construction goes into the graph's node, in the same change.

## Inputs a place passes to its children, and values a generator stores without querying them

| Input or stored value | Classification |
|---|---|
| `scope`, `property`, `erasedToConcreteExistential`, `forMockGeneration`, `startsCodeGeneration`, `validatesForwardedProperties`, `buildsWithHandWrittenMocks` | Key. |
| `lazilyInstantiatedInstanceProperties`, `reboundProperties` | Key, with the spellings of both sets, compared by UTF-8 bytes, since `String`'s `==` reads canonically equivalent labels as one. |
| `previousPassGenerator` and everything read from it (`foundCycleParameters`, `receivedBuilderLoops`, the child taken by index, and the fill findings `fillDeferredLabelsHiddenByReenteringCalls`, `fillDeferredLabelsReadInsideSendableFunction`, `fillSendableWrapperReads` and `publicMockLevelReentries`) | Key (its identity). Only first-pass entries cross trees, and their key holds `nil` there. The fill findings are empty but on a scope with non-empty `holeArguments`, never memoizable, so settling (below) need not compare them. |
| Across passes: a place whose previous-pass generator `G` the pass before built settled (`ConstructionMemo.settledReuse`) | Reuses `G` itself, when the key equals `G`'s but for `previousPassGenerator` and `G`'s reads are answered alike. Settled (`Entry.isSettled`, `ConstructionMemo.foundAlike`) means every scope of `G`'s subtree found the cycle parameters and loops of builders its previous-pass generator found, by `==` and spelling, so a build from `G` reads what `G`'s build read from its own pass before. Only while both passes read the same `placeHoldingPropertiesByType`. The reuse collects again what `G`'s build started (`Entry.startedBeneath`). |
| `propertyStack`, `concreteTypeStack`, `depthStack` | Logged: read only through `declarationClosedOn`, whose answer is the declaration closed on. `closedOnFillPathDeclarationsBeneath` reads the stack unlogged, only where `fillPathStackCount > 0`: inside a fill, excluded. |
| `nearestDeclarations` | Logged: `nearestDeclaration`, `binding`, `passesNil`. A `ConstructionLog.Read` key hashes its label as `String` does, canonically, as `NearestDeclarations` matches labels; a change that makes label matching byte-based updates those keys in the same pull request. A logged `nearestDeclaration` answer compares every field of `NearestDeclaration` (`bindings`, `formsBeingBuilt`, `receivesPassedNil`, `isBoundByMockRoot`), so a declaration a scope of the subtree changes (`build(_:)`) carries nothing the log does not hold. |
| `NearestDeclarations.passesNil`'s reads: `holdsReceivesPassedNil` (`mayPassNil`), each declaration's `receivesPassedNil` | `mayPassNil` is in the key: `false` in every tree but a mock root's, where every `passesNil` answer is `false` and nothing is logged. Where it holds, each receive only if available logs its `passesNil` read with its answer, `false` included, at the depth of the declaration that answers it: two mock roots can reach one place and differ only in a receive the one passes `nil` and the other binds (`SafeDIToolMockConstructionMemoTests`' `mock_buildsEachMockRootsOwnPlace_…` tests: dropping the logged read fails the first, and leaving `mayPassNil` out of the key fails both). |
| `isBoundByMockRoot` | Set by the mock root's binding of what its tree receives and cleared at the root (`markBoundUnderLabelByRoot`), a root place, never stored; compared in every logged `nearestDeclaration` answer; read only by `callersOwnLabels`, under a public mock call's non-empty `holeArguments`, excluded. |
| `enclosingCarriedInnerScopes`, `enclosingLevelReentries` | Excluded: a child inherits its parent's, and only a fill is handed a call's own, so both are empty outside a fill. |
| `cycleParameterContexts` | Logged: `cycleParameterContext`, keyed by the resolved closed-on declaration, misses included. Its depths are used only as the depths the log records. |
| `depth` | Stored by no generator; used only for the log's answering depths, which a hit asks again at the new place. |
| `placeHoldingPropertiesByType` | Constant within a pass of one tree; `nil` on every first pass, the only pass whose entries cross trees; non-nil only in a tree with a build site, excluded. |
| `declaredTypeNames` | Constant for the run: `DependencyTreeGenerator`'s `let`. |
| `fill`, `enclosingFills` | Excluded. |
| `fillPathStackCount` | 0 outside a fill. |
| `enclosingFillNames` | Read only under non-empty `holeArguments`, never memoizable. |
| `seamHoles`, `sitePath` | Excluded when `seamHoles` is non-empty. Otherwise `sitePath` is `[]` at every place, so the five reads of `SeamHoles` a generator stores – `valuesBindings(at: sitePath)`, `memberCallsInsideFunction(at: sitePath)`, `declaresBuilderStructs` (as `sendableFunctionsAreNonisolated`), `holdsLoopPayloadsInBoxes` (set only for a seam root's tree) and `namesBoundBySeam` – are the same at every place of the tree; `innerScopes`, `carriesStruct` and `carriedStruct` are read only under non-empty `holeArguments`. They are not the same across trees, which is why a tree with a seam root or a mock root's builders never shares its memo across trees or keeps it past a pass. |
| `seamRoot`, `mockBuilders` | The root place only (children get `seamRoot: nil`), and a root place is never stored. A tree with either keeps its memo to itself (`sharesMemo` in `Scope.createScopeGenerator`). |
| `holeArguments`, which feed `holeCallArguments`, `builderCallArguments`, `fillDispatchers` and `passedUpHoles` | Excluded when non-empty; all four are empty otherwise. |
| `closedOnFillPathDeclarationsBeneath` | Non-nil only inside a fill. Excluded. |
| A hole generator's `ownerPropertyStack`, `ownerConcreteTypeStack` | Excluded by `addHoleGenerator`: the creating scope and every ancestor are not memoizable. |
| `isBuiltByFill`, `fillReturnsWrapperBuilder`, and a fill generator's own fields | Excluded. |
| `constructsWithHandWrittenMock` | Key (flag, scope, property). |
| `cycleParameters`, `builtCycleParameters`, `cycleParameterUnavailableProperties`, `callSiteLazilyInstantiatedInstanceProperties` | From the key and logged reads (cycle context, bindings). |
| `unavailableOptionalProperties`, `lazilyInstantiatedInstanceProperties`, `receivesPassedNil` | From the key's sets and logged `binding` and `passesNil` reads. |
| `instantiable`, `propertiesToDeclare`, `instantiatedDependenciesNotGenerated`, `forwardedLazilyInstantiatedInstanceProperties`, `fillLabelsReadOnlyIfAvailable`, `builtInlineSeamComment`, `seamCall`, `publicMockCall` | Read from `scope`, in the key. |
| `placeHoldingProperties` | From `placeHoldingPropertiesByType`, above. |
| Children and everything aggregated from them | Built from the same inputs, or reused under the same rule at the child's own place. |

Walks of a finished tree that key by a generator's identity rely on a shared generator having the same subtree at each place: `SeamBuilderParameters`' nested cycle parameter bindings (the first place's binding is each place's) and its declarations between a closed-on scope and its closers (a closed-on scope on a site's path holds a hole and is never shared). `SeamBuilderParameters`' `placesByGenerator` reads a tree beside a site's path at that tree's own path, so it relies on more: every tree it finds a place in holds a hole or passes one up, and is never shared, while a tree that can be shared holds no place at any path.

## State a mock emission writes to a non-root generator

These are every `var` `ScopeGenerator` stores; everything else is a `let` set at construction.

| State | Why it does not depend on the root or the place |
|---|---|
| `fillCodeByPropertiesGeneratedLater` | Written only on a scope with non-empty `holeArguments`, never memoizable, and keyed by its whole input. |
| `unavailablePropertiesToGenerateCodeTask`, `unavailablePropertiesToGeneratedCode` | Keyed by `UnavailablePropertiesCacheKey`, every argument of `generatePropertyCode` but the constant `codeGeneration`. Several places can share one generator, and the oracle compares construction only, so a new emission argument goes in the key. |
| `rootMockParameterTreeTask` | A mock root only; a root place is never stored. |

A construction error ends the mock pass (`ErasedInstantiatorForwardedPropertiesMismatchError`, the only one), so no mock root reads the shared memo after a root that failed. A construction error the mock pass catches would owe a test that a root failing first, in the middle and last reports the same errors, and leaves the other roots the same mocks, with the memo shared and without it.
