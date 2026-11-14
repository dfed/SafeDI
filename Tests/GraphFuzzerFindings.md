# Graph fuzzer findings

Each defect the graph fuzzer has found, with the draw that produced the graph and the oracle that judged it wrong, so that what each draw and oracle has found can be counted. A defect found by a hand-written test, a review or an integration capture is not listed, even when the fuzzer draws its shape later.

- **Draw** names the generator pass or feature that made the shape (`GraphFuzzerFeature`, `GraphFuzzerSeamDrawFeature` or the pass's name in `GraphFuzzerGenerator`), or "base graph" for the graph every seed draws before its passes.
- **Oracle** names the check that failed: compile (`GraphFuzzerOracle.compilationFailures`), warning (`generatedCodeDrawsWarning`), rename (`renamedGraphDiffers`), base value (`mockBuildsOtherValuesThanProduction`), seam value (`seamBuildsOtherValuesThanInline`), or another `GraphFuzzerFailure` kind by name; "not recorded" where the pull request that fixed it did not say.
- **Outcome** is the pull request that fixed or rejected the shape, or the known-issue entry that still lists it.

When a fix or a new known-issue entry lands for something the fuzzer found, add its row in the same pull request.

| Defect | Corpus and seeds | Draw | Oracle | Outcome |
|---|---|---|---|---|
| A mock cycle closed by an alias of the instantiator being built | base: 705, 1062, … | base graph (cycles through instantiators) | compile | rejected by the tool, #404 |
| Builder functions of a lazy cycle closed past a same-labeled one share a name | base: 17 seeds | base graph (lazy cycles) | compile | fixed, #407 |
| A mock's `onlyIfAvailable` override named by label alone | base: 2810 and shapes A to C (1225, 84, 2306, …) | base graph (`onlyIfAvailable` receives) | compile | fixed, #408 |
| A mock's received dependency is not passed its promoted sibling's name | exploratory: 100913, 101329, 106445 | `LazilyInstantiated` receives | compile | fixed, #435 |
| An `Instantiator` received inside a `Sendable` builder's subtree from outside it is captured | base: 78 seeds | mixed `Sendable` wrappers | compile (Swift 6 mode) | rejected by the tool, #441 |
| A cycle through a `Sendable` builder and an `Instantiator` closes on a builder function that is not `@Sendable` | base: 33 seeds | mixed `Sendable` wrappers | compile | fixed (`buildsInSendableFunction`) |
| A promoted dependency shares the label of the mock root's own uncovered dependency of another type | base: 645, 2570, 2879, 3222, 4572, 4785 | `addingDependenciesMocksCannotBuild` | compile | fixed, #446 |
| Two mock bindings for a label received as several wrappers | base: 2606, 3004, 3719, 3077 | `items` received as several wrappers | compile | fixed, #448 and #470 |
| A mock rebinds a label received as one type above a receive of it as another | base | `addingReceiversOfDependenciesMocksCannotBuild` | compile | rejected by the tool (`receivedPropertyHiddenInMockTree`) |
| A required receive in a promoted dependency's tree is handed the mocked type's optional `onlyIfAvailable` alias | base | `addingReceiversOfDependenciesMocksCannotBuild` | compile | fixed: the mock binds the root alias under a name of its own |
| A non-`Sendable` value a mock hands a `@Sendable` builder | base: 11 seeds | `nonSendableValuesInsideSendableBuilder` motif | compile | fixed, #507 |
| A mock promotes the optional form of the mocked type's own alias and builds a dead node | base: 916 | base graph (aliases) | warning | fixed (`ScopeGenerator.provides`) |
| Label-sorted parameters reorder under a renaming | base: 35, 594 | base graph | rename | fixed, #533; the rest is a ruling, listed in `knownIssues` |
| A lazy cycle passes `nil` to a receive beneath a declaration of the label of another type | base: 2147 | base graph (lazy cycles) | not recorded | fixed, #533 |
| A mock handed an `onlyIfAvailable` alias that a type built through an instantiator aliases again passes `nil` | base: 4724 | `addingAliasChains` | base value | fixed, #537 |
| A root's mock rejects as hidden an unfulfilled `onlyIfAvailable` receive production accepts | base: 23 seeds | base graph | `valueOracleFixtureRejected` | intended; listed in `knownIssues` |
| A lazy cycle's mock configuration field follows type-name order | base: 231 seeds, and the other corpora | base graph (lazy cycles of mocked types) | rename | listed in `knownIssues` |
| A label received in two forms along a promoted dependency's tree | base: 4747; public mock: 665 | motif: one label received as an instantiator and as an instance | compile | rejected by the tool, #593 and #597 |
| A type a lazy cycle in a seam's tree builds again reads a farther declaration than the nearest | seam: 662 | seam draw (lazy cycles) | seam value | fixed, #533 |
| A lazy cycle's parameter of the closed-on property's own label | seam: 107 | seam draw (lazy cycles) | not recorded | fixed, #533 |
| A seam parameter's access cause list depends on file order | seam | seam draw (narrower types across packages) | rename | fixed, #527 |
| A staged builder's stage is called after a `@Sendable` function a cycle closes on | seam | `cycleParameter…` draws | seam value | fixed, #654 |
| A fill that re-enters its own seam passes `nil` for an only-if-available value its visible build and its inline build pass | seam: 600, 945 | `holePlaceInsidePlainFill` | `holeBuildsOtherValuesThanVisibleBuild`, seam value | listed in `seamKnownIssues`; fixed in a later PR |
| The error that a fill passes a builder on from its own caller names a place by file order | seam: 590 | `holePlaceInsidePlainFill` | rename | listed in `seamKnownIssues`; fixed in a later PR |
