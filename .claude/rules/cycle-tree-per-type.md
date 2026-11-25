---
paths:
  - "Sources/SafeDICore/Generators/CycleTree/*.swift"
  - "Tests/SafeDICoreTests/{OrderedGraph,LabelsReadFromAbove}Tests.swift"
  - "Tests/SafeDIToolDependencyTreeTests/SafeDIToolPerTypePlanTests.swift"
---

# A tree's plan by declaration

`Sources/SafeDICore/Generators/CycleTree/` holds a plan of a root's tree with one node per declaration (a scope's record and the property it is built as), where `Scope.createScopeGenerator` builds one generator per path. A tree whose screens open each other has a number of paths that grows with every cycle, and a number of declarations that does not.

- **Nothing reads the plan to generate code.** `PerTypePlan` is built only where a test sets `PerTypePlanObservation.observer`, beside the tree each path builds, so that the two can be compared. A run with no observer does no work for it. Until a change makes an emitter read it, it is no input to a place's build and has no entry in the construction memo's key or log.
- **The core names no feature.** `OrderedGraph` is generic over its node and knows nothing of a scope: nodes in the order a depth-first walk first reaches them, edges in the order given, strongly connected components by Tarjan's algorithm in the same walk, all on an explicit stack. Positions are the only names, so no `Set` or `Dictionary` order reaches a result; its one dictionary only finds a node's position.
- **A declaration is a record and a property.** `Declaration` is equal by the scope's record, the property's ID and whether it is erased, never by a path. The graph has an edge for each property a scope instantiates (`ScopeRecord.PropertyToGenerate.instantiated`); an alias builds nothing and has none.
- **Twins.** Generation closes a cycle on the property as cycle validation sees it and the concrete type built (`CycleIdentity`, as `ContextStack.entryClosedOn(byPropertyID:concreteTypeID:interner:)` compares them). Two declarations of one component with one identity, such as a constant and a `LazilyInstantiated` of one label built for one type, are twins (`PerTypePlan.twins`): a path closes on whichever it built first, so what such a declaration builds differs between paths, and a plan cannot stand for both.
- **Nothing crosses a module.** A plan is built from the frozen table of one run and dropped with its root's build. Nothing of it is written to a `.safedi` file, a manifest or a cache.
- **Labels read from above.** `LabelsReadFromAbove` gives each node the labels its subtree reads that it does not bind, the least sets that satisfy the rule, a component at a time. A node's order is its own labels, then each target's in edge order; inside a cycle, passes over the cycle's nodes in position order, so no order but the graph's reaches it. A node's bound labels hide a label from the nodes above whichever of its properties is built first, since the nearest declaration of a label answers a read even where it is built later.
- **Shapes not built yet.** `Answer`, `Variant`, `PlanStatement` and `PerPathReason` (`PlanStatement.swift`) are the shapes the layout and the tree walks are written against. Nothing constructs them until the plan's variants are built; a pull request of this folder either builds each or removes it.
