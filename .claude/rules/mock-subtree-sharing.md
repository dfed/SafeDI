---
paths:
  - "Sources/SafeDICore/Generators/MockLowering+SubtreeSharing.swift"
  - "Sources/SafeDICore/Generators/MockLowering+Walk.swift"
  - "Tests/SafeDIToolMockTests/SafeDIToolMockSubtreeSharingTests.swift"
  - "Tests/SafeDIToolTestSupport/MockSubtreeSharingChecks.swift"
---

# Sharing subtrees in an internal mock's walk

An internal mock's walk (`MockLowering.Walk`) reaches every place on every path, so a tree whose screens each build the next layer's screens beneath two parents walks 2^n places. Where one generator is met again in the same context, the later meeting takes the first meeting's tree nodes and child records (`MockLowering.SubtreeSharing`, `Walk.sharedSubtreeKey(of:orderedChildren:childrenScope:)`), and writes no text: a root that shares lays its places out by type key, which reads the records alone.

**When a root shares at all.** `MockLowering.Walk.sharesSubtrees(of:)` refuses a public mock's root, whose records read their overrides by the path from the root where an internal mock's read them from the place's own configuration (`relateConfiguration(ofBuiltPlaceAt:of:)`), so a later meeting would read the first meeting's override (`mock_sharesNothing_whenRootIsPublicMock`; a public mock is laid out only behind `MockLowering.laysOutPublicMocksWithTypeKey`), and a root whose tree holds an inline public mock's places (`filledCallBuilders`, whose fills read the caller's scope by path) or a root-level property bound apart from its label (`pathsNamedApart`). `SubtreeSharing.init?(sharingBeneath:)` refuses a root that holds a cycle-closing node or a loop of builders (whose records read every path's place: `nearestConfigurations`, `loopMemberConfigurations`), a type built both with its hand-written mock and with its initializer, and a tree that reaches no generator on several paths.

**When a node forms a key.** Only a node whose generator the root reaches on several paths, with children, outside every `@Sendable` builder function's override extraction (`sendableOverrideExtractor == nil`), where its override reaches its children's (`overridePathReachable`), and whose subtree is closed (`SubtreeFacts.isClosed`): it holds no call of a seam or of another module's public mock, no hole or fill, no unfulfilled dependency instantiated only if available, no `@Sendable` builder function and no actor (`mock_sharesNothing_whenSubtreeHoldsActor`, `mock_sharesNothing_whenSubtreeHoldsSendableInstantiator`).

**What the key holds**, each part filtered to the labels its readers read, so meetings that differ only in what nothing reads still share:

| Part | Readers | Filtered to | Test that fails without it |
|---|---|---|---|
| `generator` | every node | — | — |
| `childrenPropertiesGeneratedLater` | each child's unavailable properties and order (`orderedChildren`) | — | `mock_sharesNothing_whenChildrenAreBuiltBeforeOtherSiblings` |
| `renames` | a receive handed a flat parameter or override named apart | `facts.receivedLabels` | `mock_sharesNothing_whenRepeatedSubtreeReceivesRenamedParameter` |
| `lazilyInstantiatedNames` | a receive of a wrapper `mock()` binds apart | `facts.receivedLabels` | none: the construction memo already builds the places of `mock_sharesNothing_whenRepeatedSubtreeReceivesWrapperBoundApart` with two generators |
| `scope` | `aliasNode`: an alias's fulfilling property's optional form, a wrapper's instance | `facts.aliasFulfillingLabels` | none: as above, for `mock_sharesNothing_whenRepeatedSubtreeAliasesDeclarationOnePathHolds` |

The construction memo (`construction-memo.md`) logs no required receive, so `renames` is load-bearing: two places whose memo keys match can still read different names. The memo does tell apart the places tried whose wrappers or alias declarations differ, so `lazilyInstantiatedNames` and `scope` keep the key from relying on the memo; a part no graph turns red may go only with a stated reason.

**Every walk field is classified.** `SafeDIToolMockSubtreeSharingTests.walkFieldClassification` lists each stored field of `MockLowering.Walk` as keyed, guarded (a key forms only where it holds a value the subtree reads alike), constant through the root's walk, relative to the node, set only at the root's level, output, or a name scope the node's function opens afresh. A field added to the walk fails `subtreeKey_accountsForEveryFieldOfWalk_whenDecidingWhatSharedSubtreeReads` until it is classified; a field classified keyed must be a part of `SubtreeKey`.

**The shadow is the oracle.** `executeSafeDIToolTest`, the multi-module execution and every fuzzer graph lower each sharing root again with `MockLowering.$sharesSubtrees` off and fail on any byte of difference in its code or configurations (`MockSubtreeSharingChecks`). A key part dropped by hand fails its test above through the shadow. The base corpus draws a subtree met on several paths (`addingSharedSubtreeShapes`), and `sharedSubtreeSeeds_judgeSubtreeSharing_inGraphsWhoseMocksMeetASubtreeAgain` requires ten of its first 120 seeds to share and lay out, and every root that shares to lay out; dropping `childrenPropertiesGeneratedLater` fails seeds 12 and 31. The draw renames no receive, so `renames` rests on its handwritten test until a draw does.

**Facts stay small.** The walk keeps facts only of generators on several paths, as label bit sets (`LabelSet`), so a chain of features that builds each type once holds none (`mock_holdsNoFacts_whenChainBuildsEachTypeOnOnePath`).

**Other walks of a mock's tree visit a node once per context.** The label-read scan (`MockLowering.receiveReadsLabelByName`) computes each node once per generator, unavailable properties and properties generated later; `treeNames(of:readsFills:)` visits each generator once per `@Sendable` context, records its later meetings, and takes a node's first path and the labels declared around it over every meeting, while a child of the root keeps a node of its own wherever its generator was met first, since the public mock's stored plan and `query needs` read the root's children from the nodes without a parent (`mock_callsPublicMockWithPromotedValue_whenSameGeneratorIsMetFirstBeneathAnotherChild`); `validateMockRootScopeForCycles` skips a scope reached again in a context its subtree reads alike from one it was walked clean in (`cycle-validation.md`). Each reports its work to a test (`labelReadScanObserver`, `treeNamesWalkObserver`, `mockRootCycleWalkObserver`), and `SafeDIToolMockSubtreeSharingTests` pins it at 3, 6 and 12 layers of screens built beneath two parents, where each grows with the layers. A new input a node's visit reads joins what it is visited once per.
