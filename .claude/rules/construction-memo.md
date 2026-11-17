---
paths:
  - "Sources/SafeDICore/Generators/ConstructionMemo.swift"
  - "Sources/SafeDICore/Generators/ScopeGenerator.swift"
  - "Sources/SafeDICore/Generators/DependencyTreeGenerator.swift"
  - "Sources/SafeDICore/Models/Scope.swift"
---

# The construction memo

`ConstructionMemo` lets a place reuse a generator another place built: a hit needs an equal key and a read log that the new place's context answers alike (`ConstructionMemo.swift`'s header has the argument). Production trees keep a memo per tree; the mock roots share one, a local of `generateMockCode`'s loop, carrying first-pass entries only. A tree with a seam root or a mock root's builders keeps a memo of its own, for one pass, because it reads its own `SeamHoles`.

**Every input a place's build takes, and every value a generator stores without querying the context, is in the key, in the log, excluded, or constant for a stated reason, and is listed here.** A new one is added here in the change that adds it. The memo oracle (`ConstructionMemoOracle`, which the test executors install) compares every tree built with and without the memo by reflection, so a miss fails the first test or fuzzer graph whose places differ in it; dropping the cycle parameter context read from the log fails base-corpus seeds 35 and 168.

"Excluded" means only places the memo neither stores nor reuses hold the value in a non-trivial form: `memoKey` is `nil` inside a fill and in a tree with seam holes, and `isMemoizable` is cleared up through every ancestor by a fill, a scope inside one, non-empty `seamHoles`, non-empty `holeArguments` (a seam or public mock call with holes), and `addHoleGenerator`.

## Inputs a place passes to its children, and values a generator stores without querying them

| Input or stored value | Classification |
|---|---|
| `scope`, `property`, `erasedToConcreteExistential`, `forMockGeneration`, `startsCodeGeneration`, `validatesForwardedProperties`, `buildsWithHandWrittenMocks` | Key. |
| `lazilyInstantiatedInstanceProperties`, `reboundProperties` | Key, with the spellings of both sets, compared by UTF-8 bytes, since `String`'s `==` reads canonically equivalent labels as one. |
| `previousPassGenerator` and everything read from it (`foundCycleParameters`, `receivedBuilderLoops`, the child taken by index) | Key (its identity). Only first-pass entries cross trees, and their key holds `nil` there. |
| `propertyStack`, `concreteTypeStack`, `depthStack` | Logged: read only through `declarationClosedOn`, whose answer is the declaration closed on. `closedOnFillPathDeclarationsBeneath` reads the stack unlogged, only where `fillPathStackCount > 0`: inside a fill, excluded. |
| `nearestDeclarations` | Logged: `nearestDeclaration`, `binding`. A `ConstructionLog.Read` key hashes its label as `String` does, canonically, as `NearestDeclarations` matches labels; a change that makes label matching byte-based updates those keys in the same pull request. |
| `cycleParameterContexts` | Logged: `cycleParameterContext`, keyed by the resolved closed-on declaration, misses included. Its depths are used only as the depths the log records. |
| `depth` | Stored by no generator; used only for the log's answering depths, which a hit asks again at the new place. |
| `placeHoldingPropertiesByType` | Constant within a pass of one tree; `nil` on every first pass, the only pass whose entries cross trees; non-nil only in a tree with a build site, excluded. |
| `declaredTypeNames` | Constant for the run: `DependencyTreeGenerator`'s `let`. |
| `fill`, `enclosingFills` | Excluded. |
| `fillPathStackCount` | 0 outside a fill. |
| `enclosingFillNames` | Read only under non-empty `holeArguments`, never memoizable. |
| `seamHoles`, `sitePath` | Excluded when `seamHoles` is non-empty. Otherwise `sitePath` is `[]` at every place, so the four reads of `SeamHoles` a generator stores – `valuesBindings(at: sitePath)`, `memberCallsInsideFunction(at: sitePath)`, `declaresBuilderStructs` (as `sendableFunctionsAreNonisolated`) and `namesBoundBySeam` – are the same at every place of the tree. They are not the same across trees, which is why a tree with a seam root or a mock root's builders never shares its memo across trees or keeps it past a pass. |
| `seamRoot`, `mockBuilders` | The root place only (children get `seamRoot: nil`), and a root place is never stored. A tree with either keeps its memo to itself (`sharesMemo` in `Scope.createScopeGenerator`). |
| `holeArguments`, which feed `holeCallArguments`, `builderCallArguments`, `fillDispatchers` and `passedUpHoles` | Excluded when non-empty; all four are empty otherwise. |
| `closedOnFillPathDeclarationsBeneath` | Non-nil only inside a fill. Excluded. |
| A hole generator's `ownerPropertyStack`, `ownerConcreteTypeStack` | Excluded by `addHoleGenerator`: the creating scope and every ancestor are not memoizable. |
| `isBuiltByFill`, `fillReturnsWrapperBuilder`, and a fill generator's own fields | Excluded. |
| `constructsWithHandWrittenMock` | Key (flag, scope, property). |
| `cycleParameters`, `builtCycleParameters`, `cycleParameterUnavailableProperties`, `callSiteLazilyInstantiatedInstanceProperties` | From the key and logged reads (cycle context, bindings). |
| `unavailableOptionalProperties`, `lazilyInstantiatedInstanceProperties` | From the key's sets and logged `binding` reads. |
| `instantiable`, `propertiesToDeclare`, `forwardedLazilyInstantiatedInstanceProperties`, `builtInlineSeamComment`, `seamCall`, `publicMockCall` | Read from `scope`, in the key. |
| `placeHoldingProperties` | From `placeHoldingPropertiesByType`, above. |
| Children and everything aggregated from them | Built from the same inputs, or reused under the same rule at the child's own place. |

Walks of a finished tree that key by a generator's identity rely on a shared generator having the same subtree at each place: `SeamBuilderParameters`' nested cycle parameter bindings (the first place's binding is each place's) and its declarations between a closed-on scope and its closers (a closed-on scope on a site's path holds a hole and is never shared).

## State a mock emission writes to a non-root generator

These are every `var` `ScopeGenerator` stores; everything else is a `let` set at construction.

| State | Why it does not depend on the root or the place |
|---|---|
| `fillCodeByPropertiesGeneratedLater` | Written only on a scope with non-empty `holeArguments`, never memoizable, and keyed by its whole input. |
| `unavailablePropertiesToGenerateCodeTask`, `unavailablePropertiesToGeneratedCode` | Keyed by `UnavailablePropertiesCacheKey`, every argument of `generatePropertyCode` but the constant `codeGeneration`. Several places can share one generator, and the oracle compares construction only, so a new emission argument goes in the key. |
| `rootMockParameterTreeTask` | A mock root only; a root place is never stored. |

A construction error ends the mock pass (`ErasedInstantiatorForwardedPropertiesMismatchError`, the only one), so no mock root reads the shared memo after a root that failed. A construction error the mock pass catches would owe a test that a root failing first, in the middle and last reports the same errors, and leaves the other roots the same mocks, with the memo shared and without it.
