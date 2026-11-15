# Fuzzer pins for eddac9a3d (coverage)

- Commit: `eddac9a3d365f9c38dc766aaa3b7af7c05b1ab43`
- Mode: coverage
- Provenance: event `workflow_dispatch`, head `eddac9a3d365f9c38dc766aaa3b7af7c05b1ab43`, base ref `None`, base `None`, valid for the head: `true`
- **valid only for `eddac9a3d365f9c38dc766aaa3b7af7c05b1ab43`; a rebase invalidates every value**
- Run (all): https://github.com/dfed/SafeDI/actions/runs/43764374914, failure, 42 min 1 s from dispatch to completion
- Combine verdict: exit 1 (red), 1 problem
- Complete: yes, every corpus the `corpora` line names has a complete report for every shard
- Exit: 1

## (a) Pins that differ

```
generateMockPublic publicMockCorpusFixtureHash pinned=0x7A3E59F695DB4AE1 actual=0x9731E1275C7C8651
```

## (b) Unknown failures

None.

## (c) Stale known-issue seeds

None.

## (d) Floors below their floor

None.

## Builder surface (informational; a floored kind below its floor is in (d))

### base

Floored kinds (the line’s list; floor 10, from the commit’s combine script): none

| Kind | Graphs judged | Floored |
|---|---|---|
| `base-plain` | 0 |  |
| `base-lazy` | 0 |  |
| `base-forwarding` | 0 |  |
| `base-sendable` | 0 |  |
| `secondPlaceInAnotherType` | 0 |  |
| `secondPlaceInInnerSeamOfAnotherModule` | 0 |  |
| `holderMovedToInnerSeamOfAnotherModule` | 0 |  |
| `placeBehindLazilyInstantiated` | 0 |  |
| `instantiatorPlaceMovedToPlainPlace` | 0 |  |
| `instantiatorChangedToErasedInstantiator` | 0 |  |
| `sendableInstantiatorPlaceMovedToPlainPlace` | 0 |  |
| `sendableInstantiatorChangedToSendableErasedInstantiator` | 0 |  |
| `placeOfNewBuilderOfExistingFillingType` | 0 |  |
| `placeOfNewBuilderInInnerSeamOfAnotherModule` | 0 |  |
| `placeForwardingOtherValues` | 0 |  |
| `placeForwardingOtherValuesRemedied` | 0 |  |
| `placeForwardingOtherValuesInInnerSeamOfAnotherModule` | 0 |  |
| `placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied` | 0 |  |
| `lazilyInstantiatedPlaceMovedBack` | 0 |  |
| `plainPlaceMovedToInstantiator` | 0 |  |
| `erasedInstantiatorChangedToInstantiator` | 0 |  |
| `plainPlaceMovedToSendableInstantiator` | 0 |  |
| `sendableErasedInstantiatorChangedToSendableInstantiator` | 0 |  |
| `secondErasureOfFillingType` | 0 |  |
| `secondCallOfPublicMock` | 0 |  |
| `remedyKeepsDrawnBuilders` | 0 |  |

### generateDependencyTree

Floored kinds (the line’s list; floor 10, from the commit’s combine script): `base-plain`, `base-lazy`, `base-forwarding`, `base-sendable`, `secondPlaceInAnotherType`, `secondPlaceInInnerSeamOfAnotherModule`, `holderMovedToInnerSeamOfAnotherModule`, `placeBehindLazilyInstantiated`, `placeOfNewBuilderInInnerSeamOfAnotherModule`, `placeForwardingOtherValues`, `placeForwardingOtherValuesRemedied`, `placeForwardingOtherValuesInInnerSeamOfAnotherModule`, `placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied`, `lazilyInstantiatedPlaceMovedBack`, `secondErasureOfFillingType`, `remedyKeepsDrawnBuilders`

| Kind | Graphs judged | Floored |
|---|---|---|
| `base-plain` | 144 | yes |
| `base-lazy` | 25 | yes |
| `base-forwarding` | 31 | yes |
| `base-sendable` | 44 | yes |
| `secondPlaceInAnotherType` | 94 | yes |
| `secondPlaceInInnerSeamOfAnotherModule` | 17 | yes |
| `holderMovedToInnerSeamOfAnotherModule` | 17 | yes |
| `placeBehindLazilyInstantiated` | 74 | yes |
| `instantiatorPlaceMovedToPlainPlace` | 0 |  |
| `instantiatorChangedToErasedInstantiator` | 0 |  |
| `sendableInstantiatorPlaceMovedToPlainPlace` | 0 |  |
| `sendableInstantiatorChangedToSendableErasedInstantiator` | 0 |  |
| `placeOfNewBuilderOfExistingFillingType` | 0 |  |
| `placeOfNewBuilderInInnerSeamOfAnotherModule` | 17 | yes |
| `placeForwardingOtherValues` | 94 | yes |
| `placeForwardingOtherValuesRemedied` | 94 | yes |
| `placeForwardingOtherValuesInInnerSeamOfAnotherModule` | 17 | yes |
| `placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied` | 17 | yes |
| `lazilyInstantiatedPlaceMovedBack` | 74 | yes |
| `plainPlaceMovedToInstantiator` | 0 |  |
| `erasedInstantiatorChangedToInstantiator` | 0 |  |
| `plainPlaceMovedToSendableInstantiator` | 0 |  |
| `sendableErasedInstantiatorChangedToSendableInstantiator` | 0 |  |
| `secondErasureOfFillingType` | 14 | yes |
| `secondCallOfPublicMock` | 0 |  |
| `remedyKeepsDrawnBuilders` | 111 | yes |

### generateMockPublic

Floored kinds (the line’s list; floor 10, from the commit’s combine script): `base-plain`, `base-lazy`, `base-forwarding`, `base-sendable`, `placeBehindLazilyInstantiated`, `instantiatorPlaceMovedToPlainPlace`, `plainPlaceMovedToInstantiator`, `instantiatorChangedToErasedInstantiator`, `erasedInstantiatorChangedToInstantiator`, `sendableInstantiatorPlaceMovedToPlainPlace`, `plainPlaceMovedToSendableInstantiator`, `sendableInstantiatorChangedToSendableErasedInstantiator`, `sendableErasedInstantiatorChangedToSendableInstantiator`, `placeOfNewBuilderOfExistingFillingType`, `placeForwardingOtherValues`, `placeForwardingOtherValuesRemedied`, `lazilyInstantiatedPlaceMovedBack`, `secondCallOfPublicMock`, `remedyKeepsDrawnBuilders`

| Kind | Graphs judged | Floored |
|---|---|---|
| `base-plain` | 676 | yes |
| `base-lazy` | 72 | yes |
| `base-forwarding` | 36 | yes |
| `base-sendable` | 62 | yes |
| `secondPlaceInAnotherType` | 0 |  |
| `secondPlaceInInnerSeamOfAnotherModule` | 0 |  |
| `holderMovedToInnerSeamOfAnotherModule` | 0 |  |
| `placeBehindLazilyInstantiated` | 111 | yes |
| `instantiatorPlaceMovedToPlainPlace` | 27 | yes |
| `instantiatorChangedToErasedInstantiator` | 27 | yes |
| `sendableInstantiatorPlaceMovedToPlainPlace` | 26 | yes |
| `sendableInstantiatorChangedToSendableErasedInstantiator` | 26 | yes |
| `placeOfNewBuilderOfExistingFillingType` | 128 | yes |
| `placeOfNewBuilderInInnerSeamOfAnotherModule` | 0 |  |
| `placeForwardingOtherValues` | 104 | yes |
| `placeForwardingOtherValuesRemedied` | 104 | yes |
| `placeForwardingOtherValuesInInnerSeamOfAnotherModule` | 0 |  |
| `placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied` | 0 |  |
| `lazilyInstantiatedPlaceMovedBack` | 111 | yes |
| `plainPlaceMovedToInstantiator` | 27 | yes |
| `erasedInstantiatorChangedToInstantiator` | 27 | yes |
| `plainPlaceMovedToSendableInstantiator` | 26 | yes |
| `sendableErasedInstantiatorChangedToSendableInstantiator` | 26 | yes |
| `secondErasureOfFillingType` | 0 |  |
| `secondCallOfPublicMock` | 112 | yes |
| `remedyKeepsDrawnBuilders` | 104 | yes |

## Observed (informational; not counted for the exit status)

### Known seeds, base (`knownIssues`)

- 87: A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them
- 17: A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them, and which back-edge of a lazy cycle loses its override follows the order of type names, so one field of a configuration struct is present under one naming and absent under another
- 4: An error advises declaring a property on a root whose own properties the declared type's tree receives and that require the declaration, so the declaration closes a dependency cycle there (remedyRuns_leaveNoErrorAtTheReceive_whenTheDeclaredTypesTreeReceivesARootPropertyThatRequiresTheDeclaration: Root builds `t2: T2`, which requires `t0Builder: Instantiator<T0>`, and T0 receives `t2`)
- 17: An error advises receiving a property only if available, or a suggested property, beneath a type whose mock is generated and that declares the label with another type, so the mock rejects the receive as hidden (remedyRuns_leaveNoErrorAtTheReceive_whenAMockedTypeBetweenDeclaresItsLabelWithAnotherType: T3, mocked, declares `t4: T1` and builds T5, which Root builds too and which requires `t4: T0?`, and the error says to declare `t4: T0` on Root and receive it only if available)
- 18: An error at a receive inside a `@Sendable` builder advises receiving, or declaring, a property that is not `Sendable`, which then cannot be received there (remedyRuns_leaveNoErrorAtTheReceive_whenTheSuggestedOnlyIfAvailableReceiveIsInsideASendableBuilder: Root builds `t1Builder: SendableInstantiator<T1>` and `t2Builder: Instantiator<T2>`, and T1 requires `t2Builder: Instantiator<T2>?`, which the error says to receive only if available)
- 6: An error suggests receiving a property whose receive closes a dependency cycle (remedyRuns_leaveNoErrorAtTheReceive_whenTheSuggestedPropertyIsOfTheMockedReceiversOwnType: T1, mocked, requires `t0: T1` beneath T2, which forwards `t0: T1?` and builds T1, and the error suggests `t0: T1?`, which the mock of T1 receives while building T1)
- 2: Each error reports one path to a receiver, so receiving the property one path suggests leaves an error on another path, which suggests the first label again (remedyRuns_leaveNoErrorAtTheReceive_whenTwoPathsToTheReceiverDeclareTheReceivedTypeUnderOtherLabels: T1 declares `t4: T4` and T2 declares `lazyT4: T4`, and each builds T3, which requires `t4: T4`)
- 19: Intended: a root's mock rejects a tree that repeats a label along a branch, a receive, only if available, of a label a closer declaration holds with another type, which production accepts for the same tree
- 1: Intended: a root's mock rejects a tree that repeats a label along a branch, a receive, only if available, of a label a closer declaration holds with another type, which production accepts for the same tree, in a graph whose lazy cycle also drops another configuration field under a renaming
- 3: Intended: a root's mock rejects a tree that repeats a label along a branch, a receive, only if available, of a label a closer declaration holds with another type, which production accepts for the same tree, in a graph whose mock's parameters and fields also reorder under a renaming
- 229: Which back-edge of a lazy cycle loses its override follows the order of type names, so one field of a configuration struct, with the reads of it, is present under one naming and absent under another

### Known seeds, generateDependencyTree (`seamKnownIssues`)

- 1: A fill that re-enters its own seam hands the re-entered seam the root dispatcher, not its own values, so a fill there reads `nil` for an only-if-available value its visible build and its inline build pass; fixed in a later PR; and A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 1: A fill that re-enters its own seam hands the re-entered seam the root dispatcher, not its own values, so a fill there reads `nil` for an only-if-available value its visible build and its inline build pass; fixed in a later PR; and A seam's builders are ordered by label, which its hole type's names spell, so moving type names across wrapper names reorders the builders of a seam with two hole types, its generated initializers and the calls of them; and A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A builder written by hand, handed to a seam as its readable initializer hands it on, keeps alive every value of each level on the way to its places, even when it reads none, where the inline build frees them, until the in-seam leak fix gives the readable initializer a builder that reads nothing; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 5: A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them
- 2: A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them, and which back-edge of a lazy cycle loses its override follows the order of type names, so one field of a configuration struct is present under one naming and absent under another
- 1: A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them; and A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A builder written by hand, handed to a seam as its readable initializer hands it on, keeps alive every value of each level on the way to its places, even when it reads none, where the inline build frees them, until the in-seam leak fix gives the readable initializer a builder that reads nothing; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and A seam's own internal mock, which cannot build a hole whose fill is in another module, takes the hole's value, or the wrapper its place spells, as a parameter where the seam takes one builder per filling type, returned type and family, as contract rules 7 and 8 ask of the mock too, so moving the place behind `LazilyInstantiated` or into an inner seam, or giving a second place the same label, changes the parameter's type, its label or its order; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 2: A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards
- 1: A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 2: A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A builder written by hand, handed to a seam as its readable initializer hands it on, keeps alive every value of each level on the way to its places, even when it reads none, where the inline build frees them, until the in-seam leak fix gives the readable initializer a builder that reads nothing; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards
- 8: A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A builder written by hand, handed to a seam as its readable initializer hands it on, keeps alive every value of each level on the way to its places, even when it reads none, where the inline build frees them, until the in-seam leak fix gives the readable initializer a builder that reads nothing; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 1: A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards
- 2: A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and A seam's own internal mock, which cannot build a hole whose fill is in another module, takes the hole's value, or the wrapper its place spells, as a parameter where the seam takes one builder per filling type, returned type and family, as contract rules 7 and 8 ask of the mock too, so moving the place behind `LazilyInstantiated` or into an inner seam, or giving a second place the same label, changes the parameter's type, its label or its order; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 5: A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 1: A seam's builders are ordered by label, which its hole type's names spell, so moving type names across wrapper names reorders the builders of a seam with two hole types, its generated initializers and the calls of them; and A mock's parameters and fields are sorted by label, so a renaming that reorders labels reorders them; and A seam's readable initializer and a mock hand each hole's builder a generated scope enum, so a builder a person writes names generated code; the planned builder structs replace it with builders that take only what their place forwards; and Places of one builder that forward other values are merged into one builder rather than rejected, so the builder cannot take only what each place forwards
- 2: A seam's builders are ordered by label, which its hole type's names spell, so moving type names across wrapper names reorders the builders of a seam with two hole types, its generated initializers and the calls of them; and A seam's builder functions capture the values of each level on the way to a place, so holding a builder keeps them alive where the inline build frees them, until the in-seam leak fix; and A builder written by hand, handed to a seam as its readable initializer hands it on, keeps alive every value of each level on the way to its places, even when it reads none, where the inline build frees them, until the in-seam leak fix gives the readable initializer a builder that reads nothing; and A seam's reada