// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// The names `mock()`'s parameters are chosen from (`ScopeGenerator.treeNames(of:readsFills:)`, read without fills), read
/// from the per-type world of a mock root (`TypeFactsGraph`) rather than from its generator tree: each declaration is
/// visited at most once per inside-`@Sendable` state, never once per path. Only a test compares it with the tree's names
/// (`MockTreeNamesObservation`); `mock()` still reads the tree's.
///
/// The world's sibling order (`TypeFactsEdge.buildPosition`) is the order the tree generates each declaration's children
/// in. The tree is the world unfolded along its built edges from the root, each path cut where it would repeat a
/// declaration on it: a node whose declaration is an ancestor's closes a cycle (`isPropertyCycle`), refers to that
/// ancestor's builder function, and builds nothing. So every path of the tree is a path of the world that repeats no
/// declaration, and every such path is a path of the tree. A declaration whose cycle identity another shares (`twins`)
/// is refused: the tree closes on it where the world holds no edge back. Field by field:
/// - Which declarations the tree builds: those the root reaches, since the shortest path to one repeats nothing.
///   `builderFunctionNames` and `namesDeclaredInBuilderFunctions` are what the built declarations and the closers
///   declare, and a closer repeats a built declaration, so each is one visit per reached declaration.
/// - "First met in a walk of the tree in generation order" (the uncovered dependencies, and the `nil`-bound ones outside
///   every `@Sendable` function) is the order a depth-first walk in generation order with a visited set first visits each
///   declaration: the tree's walk meets a declaration again either as a closer, which the walk skips as visited, or
///   beneath a declaration already visited, whose subtree's first meetings are behind it.
/// - Inside a `@Sendable` builder function: a walk of (declaration, inside-`@Sendable`) states gives the states some
///   path of the world reaches. Where no `Sendable` wrapper is on a cycle, a path that reaches a state reaches it
///   without repeating a declaration (cutting a repeated stretch removes no `Sendable` edge, which would be on a cycle),
///   and a builder function is `@Sendable` exactly where its wrapper is (a closer can make one `@Sendable` only from
///   inside a `@Sendable` function on its cycle). A `Sendable` wrapper on a cycle is refused (`sendableCycle`).
/// - Hidden by a builder function around its creator: whether a path from the root through a declaration of the label
///   to the creator repeats nothing. Through a declaration on no cycle every path does, so a fold over the components
///   in topological order hands each such declaration's labels to every declaration it reaches. Through one on a
///   cycle the world bounds it: from above, the declaration reaches the creator without passing a declaration that
///   dominates it (every path from the root to it passes those); from below, a path shown to repeat nothing (the walk's
///   first path to the declaration, then any path on from it that avoids that path; or the path on to the creator, and a
///   path from the root to the declaration that avoids it). The bounds differing is refused (`hiddenOnCycle`).
/// - The types that create a dependency, in the order of their creators' paths sorted by declaration index, then
///   generation index, are the order a depth-first walk in that order with a visited set first visits each creator, by
///   the argument for first meetings.
///
/// Each walk visits a declaration a bounded number of times, but the bounds for a declaration on a cycle, which walk
/// the declarations once for each declaration of an uncovered label on a cycle and each creator it reaches.
///
/// It refuses a root it cannot answer exactly (`Refusal`).
enum MockTreeNamesFromWorld {
	/// Why the world of a mock root cannot answer its tree's names exactly.
	enum Refusal: String, Sendable {
		/// A public mock's tree is built with builders for its holes, which its world, built from the tree without them,
		/// does not hold.
		case publicMockRoot
		/// A mock that passes `nil` to a receive only if available that a required receive pins (`MockReceivesPassedNil`):
		/// the receive reads nothing from its sibling, so the tree orders the siblings without that edge, which the world's
		/// sibling order (`SiblingOrder`) still holds.
		case pins
		/// A call of another module's public mock or of a seam, a fill it passes, or a hole's site: the places and passed-up
		/// builders the tree reads from its generator, which the world does not hold.
		case callOrPlace
		/// A declaration whose cycle identity another declaration of the world shares (a value and a lazy wrapper of one
		/// label and type): the tree closes a cycle on the other declaration, which the world holds no edge to.
		case twin
		/// A `Sendable` wrapper on a cycle: a cycle-closing node beneath it makes the builder functions it refers to
		/// `@Sendable` on some paths and not on others (`ScopeGenerator.buildsInSendableFunction`).
		case sendableCycle
		/// An uncovered dependency that a declaration on a cycle may hide: whether a path of the tree runs from the root
		/// through that declaration to the dependency's creator without repeating a declaration, which the world bounds
		/// from below and above and the two bounds differ.
		case hiddenOnCycle
		/// A property the root's subtree receives, by the world's row, that `createMockRootScopeGenerator` binds in no
		/// spelling (`MockRootPromotion.received`), so the world has no spelling of it to hand the signature.
		case spelling
	}

	/// The world's answer for one mock root: its tree's names, or why it refuses.
	enum Answer {
		case names(ScopeGenerator.TreeNames)
		case refused(Refusal)
	}

	/// The children a declaration's type builds, in generation order: those that build a type, each property once, and
	/// those instantiated only if available that nothing fulfills, which bind `nil`.
	private struct Children {
		/// Each built child's declaration, its property, and its position among its parent's children: its declaration
		/// index in the parent's dependencies (`Int.max` for one the mock promotes), then its generation index.
		var built = [(declaration: DeclarationID, property: Property, declarationIndex: Int, generationIndex: Int32)]()
		var unavailable = [Property]()
		/// The labels of every child property, built or bound to `nil`.
		var labels = Set<String>()
	}

	/// The names of `instantiable`'s mock's tree, read from the world whose root is `worldRoot`
	/// (`MockRootPlan.freezingRoot()`).
	/// - Parameters:
	///   - passesNilToPinnedReceives: Whether the mock passes `nil` to a receive a required receive pins, which
	///     `createMockRootScopeGenerator` decides before the tree is built.
	///   - declarationVisits: Incremented once for each declaration a walk visits, which a test reads to show the work
	///     grows with the world rather than with the tree's paths.
	static func treeNames(of instantiable: Instantiable, worldRoot: ConstructionScope, passesNilToPinnedReceives: Bool, declarationVisits: inout Int) -> Answer {
		guard instantiable.generateMock != .public else { return .refused(.publicMockRoot) }
		guard !passesNilToPinnedReceives else { return .refused(.pins) }
		return treeNames(of: instantiable, world: TypeFactsGraph(root: worldRoot, forMockGeneration: true), passesNilToPinnedReceives: passesNilToPinnedReceives, declarationVisits: &declarationVisits)
	}

	/// The same, read from `world`, the mock root's world (`TypeFactsGraph(root:forMockGeneration:)`), which a caller that
	/// reads the world again builds once.
	static func treeNames(of instantiable: Instantiable, world: TypeFactsGraph, passesNilToPinnedReceives: Bool, declarationVisits: inout Int) -> Answer {
		guard instantiable.generateMock != .public else { return .refused(.publicMockRoot) }
		guard !passesNilToPinnedReceives else { return .refused(.pins) }
		let declarationCount = world.declarationCount

		// Each reached declaration's children, read once; the reach refuses what the world cannot answer.
		var childrenByDeclaration = [Children?](repeating: nil, count: declarationCount)
		func children(of declaration: DeclarationID, declaredBy dependencies: [Dependency]) -> Children {
			var candidates = [(declaration: DeclarationID, property: Property, generationIndex: Int32, isUnavailable: Bool)]()
			// The reach refuses a world with a fill before it reads any declaration’s children.
			for edge in world.edgeFacts(from: declaration) {
				guard world.kind(of: edge.child) != .alias, let property = world.property(of: edge.child) else { continue }
				candidates.append((edge.child, property, edge.buildPosition, world.scope(of: edge.child).isUnavailableDependency))
			}
			candidates.sort { $0.generationIndex < $1.generationIndex }
			var result = Children()
			var listed = Set<Property>()
			// A child that lists a property a sibling before it lists is never built (`orderedPropertiesToGenerate`).
			for candidate in candidates where listed.insert(candidate.property).inserted {
				result.labels.insert(candidate.property.label)
				if candidate.isUnavailable {
					result.unavailable.append(candidate.property)
				} else {
					result.built.append((
						declaration: candidate.declaration,
						property: candidate.property,
						declarationIndex: dependencies.firstIndex { $0.property.label == candidate.property.label } ?? Int.max,
						generationIndex: candidate.generationIndex,
					))
				}
			}
			return result
		}
		func dependencies(of declaration: DeclarationID) -> [Dependency] {
			declaration == 0 ? instantiable.dependencies : world.scope(of: declaration).instantiable.dependencies
		}
		func isCall(_ construction: TypeFactsConstruction) -> Bool {
			switch construction {
			case .publicMockCall, .seamCall, .fill:
				true
			case .initializer, .handWrittenMock, .constructionFunction:
				false
			}
		}
		var reached = [DeclarationID]()
		var isReached = [Bool](repeating: false, count: declarationCount)
		var pending: [DeclarationID] = [0]
		isReached[0] = true
		while let declaration = pending.popLast() {
			declarationVisits += 1
			reached.append(declaration)
			for edge in world.edgeFacts(from: declaration) {
				guard !edge.isFill, world.kind(of: edge.child) != .hole, !isCall(world.construction(of: edge.child)) else { return .refused(.callOrPlace) }
			}
			let declarationChildren = children(of: declaration, declaredBy: dependencies(of: declaration))
			childrenByDeclaration[Int(declaration)] = declarationChildren
			for child in declarationChildren.built where !isReached[Int(child.declaration)] {
				guard world.twins[Int(child.declaration)] < 0 else { return .refused(.twin) }
				isReached[Int(child.declaration)] = true
				pending.append(child.declaration)
			}
		}
		func childrenOf(_ declaration: DeclarationID) -> Children {
			childrenByDeclaration[Int(declaration)] ?? Children()
		}
		/// The dependencies a declaration's type instantiates that none of its children builds.
		func uncoveredDependencies(of declaration: DeclarationID) -> [Dependency] {
			let labels = childrenOf(declaration).labels
			return dependencies(of: declaration).filter { $0.source.isInstantiated && !labels.contains($0.property.label) }
		}

		// The built edges alone, whose components are the tree's cycles; a node of it is named by its position.
		let built = OrderedGraph<DeclarationID>(root: 0) { childrenOf($0).built.map(\.declaration) }
		for node in built.nodes.indices {
			for (target, child) in zip(built.edges(from: node), childrenOf(built.nodes[node]).built) where child.property.propertyType.isSendable {
				guard built.componentByNode[Int(target)] != built.componentByNode[node] else { return .refused(.sendableCycle) }
			}
		}

		// The mocked type's own, in its declaration order, which its root's children and their instances cover.
		let rootChildren = childrenOf(0)
		var builtAtRoot = Set(rootChildren.unavailable)
		for child in rootChildren.built {
			builtAtRoot.insert(child.property)
			if let instanceProperty = child.property.asLazilyInstantiatedInstanceProperty {
				builtAtRoot.insert(instanceProperty)
			}
		}
		let mockedTypeUncoveredDependencies = instantiable.dependencies.filter { $0.source.isInstantiated && !builtAtRoot.contains($0.property) }

		var properties = [Property]()
		var dependencyByProperty = [Property: Dependency]()
		var propertiesInstantiatedInSendableFunction = Set<Property>()
		for dependency in mockedTypeUncoveredDependencies where dependencyByProperty[dependency.property] == nil {
			properties.append(dependency.property)
			dependencyByProperty[dependency.property] = dependency
		}

		// One walk in generation order over (declaration, inside-`@Sendable`) states: the first visit of each state keeps
		// every first meeting of a declaration, and every first meeting outside a `@Sendable` function, in the tree's order.
		var namesDeclaredInBuilderFunctions = Set<String>()
		var builderFunctionNames = Set<String>()
		var unavailableProperties = rootChildren.unavailable
		var visitedOutside = [Bool](repeating: false, count: declarationCount)
		var visitedInside = [Bool](repeating: false, count: declarationCount)
		var visits = rootChildren.built.reversed().map { (declaration: $0.declaration, isInside: $0.property.propertyType.isSendable) }
		while let visit = visits.popLast() {
			let index = Int(visit.declaration)
			if visit.isInside {
				guard !visitedInside[index] else { continue }
				visitedInside[index] = true
			} else {
				guard !visitedOutside[index] else { continue }
				visitedOutside[index] = true
				// One a type built inside a `@Sendable` builder function declares is bound to `nil` there.
				for property in childrenOf(visit.declaration).unavailable where !unavailableProperties.contains(property) {
					unavailableProperties.append(property)
				}
			}
			declarationVisits += 1
			if let property = world.property(of: visit.declaration) {
				builderFunctionNames.insert(ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
			}
			for dependency in dependencies(of: visit.declaration) {
				namesDeclaredInBuilderFunctions.insert(dependency.property.label)
			}
			for dependency in uncoveredDependencies(of: visit.declaration) {
				if dependencyByProperty[dependency.property] == nil {
					properties.append(dependency.property)
					dependencyByProperty[dependency.property] = dependency
				}
				if visit.isInside {
					propertiesInstantiatedInSendableFunction.insert(dependency.property)
				}
			}
			visits.append(contentsOf: childrenOf(visit.declaration).built.reversed().map { child in
				(declaration: child.declaration, isInside: visit.isInside || child.property.propertyType.isSendable)
			})
		}

		// Whether a builder function around a creator declares the dependency's label on some path that repeats no
		// declaration. The root's level declares in no builder function. Only the labels of uncovered dependencies are kept.
		var uncoveredLabels = Set<String>()
		for declaration in reached where declaration != 0 {
			for dependency in uncoveredDependencies(of: declaration) {
				uncoveredLabels.insert(dependency.property.label)
			}
		}
		var hiddenProperties = Set<Property>()
		if !uncoveredLabels.isEmpty {
			switch hidden(in: built, uncoveredLabels: uncoveredLabels, dependenciesOf: dependencies(of:), uncoveredDependenciesOf: uncoveredDependencies(of:), declarationVisits: &declarationVisits) {
			case let .some(hidden):
				hiddenProperties = hidden
			case .none:
				return .refused(.hiddenOnCycle)
			}
		}

		// The types that create each dependency: the mocked type, then each creator in the order its first path sorts by
		// declaration index, then generation index, each type once.
		var creatingTypesByProperty = [Property: [TypeDescription]]()
		for dependency in mockedTypeUncoveredDependencies {
			creatingTypesByProperty[dependency.property, default: []].append(instantiable.concreteInstantiable)
		}
		var visitedInDeclarationOrder = [Bool](repeating: false, count: declarationCount)
		func inDeclarationOrder(_ children: [(declaration: DeclarationID, property: Property, declarationIndex: Int, generationIndex: Int32)]) -> [DeclarationID] {
			children.sorted { ($0.declarationIndex, $0.generationIndex) < ($1.declarationIndex, $1.generationIndex) }.map(\.declaration)
		}
		var creators = Array(inDeclarationOrder(rootChildren.built).reversed())
		while let declaration = creators.popLast() {
			guard !visitedInDeclarationOrder[Int(declaration)] else { continue }
			visitedInDeclarationOrder[Int(declaration)] = true
			declarationVisits += 1
			let type = world.scope(of: declaration).instantiable.concreteInstantiable
			for dependency in uncoveredDependencies(of: declaration) where !(creatingTypesByProperty[dependency.property]?.contains(type) ?? false) {
				creatingTypesByProperty[dependency.property, default: []].append(type)
			}
			creators.append(contentsOf: inDeclarationOrder(childrenOf(declaration).built).reversed())
		}

		var uncoveredDependencies = [ScopeGenerator.MockTreeNames.UncoveredDependency]()
		for property in properties {
			guard let dependency = dependencyByProperty[property] else { continue }
			uncoveredDependencies.append(ScopeGenerator.MockTreeNames.UncoveredDependency(
				dependency: dependency,
				isHiddenWhereReferenced: hiddenProperties.contains(property),
				isInstantiatedInSendableFunction: propertiesInstantiatedInSendableFunction.contains(property),
				creatingTypes: creatingTypesByProperty[property] ?? [],
			))
		}
		var names = ScopeGenerator.MockTreeNames(
			rootProperties: rootChildren.built.map(\.property),
			mockedTypeUncoveredDependencies: mockedTypeUncoveredDependencies,
			uncoveredDependencies: uncoveredDependencies,
			namesDeclaredInBuilderFunctions: namesDeclaredInBuilderFunctions,
			builderFunctionNames: builderFunctionNames,
		)
		names.unavailableDependencyProperties = unavailableProperties
		names.rootHoleSiteProperties = rootChildren.unavailable
		return .names(ScopeGenerator.TreeNames(names: names, mockedTypeUncoveredProperties: Set(mockedTypeUncoveredDependencies.map(\.property))))
	}

	/// The uncovered dependencies a builder function around their creators hides, over `built`, the world's built edges:
	/// exact where the labels are declared on no cycle, and `nil` where a declaration on a cycle hides one on some
	/// bound of the paths that repeat no declaration and not on the other.
	private static func hidden(
		in built: OrderedGraph<DeclarationID>,
		uncoveredLabels: Set<String>,
		dependenciesOf: (DeclarationID) -> [Dependency],
		uncoveredDependenciesOf: (DeclarationID) -> [Dependency],
		declarationVisits: inout Int,
	) -> Set<Property>? {
		let nodeCount = built.nodes.count
		/// The labels of uncovered dependencies the node's type declares, which hide a parameter beneath it.
		func declaredLabels(of node: Int) -> Set<String> {
			let uncovered = Set(uncoveredDependenciesOf(built.nodes[node]).map(\.property.label))
			return Set(dependenciesOf(built.nodes[node]).lazy.map(\.property.label).filter { uncoveredLabels.contains($0) && !uncovered.contains($0) })
		}
		var hidden = Set<Property>()

		// The labels declared on no cycle, folded over the components, each before every component it reaches: a
		// component's number is lower than that of every component that reaches it.
		var membersByComponent = [[Int]](repeating: [], count: built.componentCount)
		for node in 0..<nodeCount {
			membersByComponent[Int(built.componentByNode[node])].append(node)
		}
		var declaredAroundByComponent = [Set<String>](repeating: [], count: built.componentCount)
		for component in membersByComponent.indices.reversed() {
			for node in membersByComponent[component] {
				declarationVisits += 1
				for dependency in uncoveredDependenciesOf(built.nodes[node]) where declaredAroundByComponent[component].contains(dependency.property.label) {
					hidden.insert(dependency.property)
				}
				var handedDown = declaredAroundByComponent[component]
				if node != 0, !built.isOnCycle(node) {
					handedDown.formUnion(declaredLabels(of: node))
				}
				for target in built.edges(from: node) where Int(built.componentByNode[Int(target)]) != component {
					declaredAroundByComponent[Int(built.componentByNode[Int(target)])].formUnion(handedDown)
				}
			}
		}

		// The labels declared on a cycle, bounded.
		var hiddenOnlyAbove = Set<Property>()
		let dominators = TypeFactsGraph.immediateDominators(of: built, followsEdge: { _ in true })
		/// The node each node `start` reaches avoiding `avoided` was first reached from (`start`'s is itself), -1 for one it
		/// does not reach.
		func reached(from start: Int, avoiding avoided: Set<Int>) -> [Int] {
			var parentByNode = [Int](repeating: -1, count: nodeCount)
			parentByNode[start] = start
			var pending = [start]
			while let node = pending.popLast() {
				declarationVisits += 1
				for target in built.edges(from: node) where !avoided.contains(Int(target)) && parentByNode[Int(target)] < 0 {
					parentByNode[Int(target)] = node
					pending.append(Int(target))
				}
			}
			return parentByNode
		}
		for declarer in 1..<nodeCount where built.isOnCycle(declarer) {
			let labels = declaredLabels(of: declarer)
			guard !labels.isEmpty else { continue }
			var dominatorsAbove = Set<Int>()
			var dominator = dominators[declarer]
			while dominator != 0 {
				dominatorsAbove.insert(dominator)
				dominator = dominators[dominator]
			}
			dominatorsAbove.insert(0)
			let reachedAbove = reached(from: declarer, avoiding: dominatorsAbove)
			let reachedPastFirstRoute = reached(from: declarer, avoiding: Set(built.firstRoute(to: declarer).dropLast()))
			for creator in 0..<nodeCount where creator != declarer && reachedAbove[creator] >= 0 {
				let hiddenByDeclarer = uncoveredDependenciesOf(built.nodes[creator]).filter { labels.contains($0.property.label) && !hidden.contains($0.property) }
				guard !hiddenByDeclarer.isEmpty else { continue }
				var isShownToRepeatNothing = reachedPastFirstRoute[creator] >= 0
				if !isShownToRepeatNothing {
					var routeOn = Set<Int>()
					var node = creator
					while node != declarer {
						routeOn.insert(node)
						node = reachedAbove[node]
					}
					isShownToRepeatNothing = reached(from: 0, avoiding: routeOn)[declarer] >= 0
				}
				for dependency in hiddenByDeclarer {
					if isShownToRepeatNothing {
						hidden.insert(dependency.property)
					} else {
						hiddenOnlyAbove.insert(dependency.property)
					}
				}
			}
		}
		return hiddenOnlyAbove.isSubset(of: hidden) ? hidden : nil
	}
}

extension MockTreeNamesFromWorld {
	/// The inputs the world whose root is `worldRoot` holds for its root: what the root's subtree receives from above it,
	/// the names it declares `@escaping`, and its children in the order the world builds them; or `nil` where a property
	/// the subtree receives has no spelling in `bound`.
	/// What the subtree receives is the world's rows, each received property spelled as `bound` spells it: the properties
	/// `createMockRootScopeGenerator` binds at the mock root (`MockRootPromotion.received`), each in the most explicit
	/// spelling its receivers give, before the tree is built. Only the received properties' spellings reach the signature
	/// (`MockedTypeSpellings` respells them); the required and only-if-available rows are read for membership alone, which
	/// `Property`'s `==` reads without `any`, so they keep the world's spellings.
	/// A root the world answers calls no public mock and is none, so it receives nothing only such a call does and takes no
	/// builder.
	static func rootInputs(of worldRoot: ConstructionScope, spelledAs bound: Set<Property>) -> (inputs: MockRootParameterInputs, childrenInBuildOrder: [Property])? {
		rootInputs(ofWorld: TypeFactsGraph(root: worldRoot, forMockGeneration: true), spelledAs: bound)
	}

	/// The same, read from `world`, the mock root's world, which a caller that reads the world again builds once.
	static func rootInputs(ofWorld world: TypeFactsGraph, spelledAs bound: Set<Property>) -> (inputs: MockRootParameterInputs, childrenInBuildOrder: [Property])? {
		// The world tells every two spellings apart, and a set of received properties keeps the most explicit of each.
		func properties(_ rows: BitRows) -> Set<Property> {
			var properties = Set<Property>()
			properties.formUnionKeepingMostExplicitSpelling(rows.columns(inRow: 0).map { world.propertyTable[Int($0)] })
			return properties
		}
		// `==` reads two spellings of one property as one, so the bound set holds at most one spelling of each.
		var receivedProperties = Set<Property>()
		for property in properties(world.receives.received) {
			guard let index = bound.firstIndex(of: property) else { return nil }
			receivedProperties.insert(bound[index])
		}
		// A child that lists a property a sibling before it lists is never built (`orderedPropertiesToGenerate`).
		var listed = Set<Property>()
		let childrenInBuildOrder = world.edgeFacts(from: 0)
			.sorted { $0.buildPosition < $1.buildPosition }
			.compactMap { world.property(of: $0.child) }
			.filter { listed.insert($0).inserted }
		let inputs = MockRootParameterInputs(
			receivedProperties: receivedProperties,
			requiredReceivedProperties: properties(world.receives.required),
			onlyIfAvailableUnwrappedReceivedProperties: properties(world.receives.onlyIfAvailableUnwrapped),
			typesDeclaredEscaping: Set(world.typesDeclaredEscaping.columns(inRow: 0).map { world.typeTable[Int($0)] }),
			propertiesToDeclare: world.scope(of: 0).propertiesToDeclare,
			receivedOnlyByPublicMockCalls: [],
			passedByPublicMockCalls: [],
			passedByPublicMockCallLabelsReadInsideSendableFunctions: [],
			mockBuilders: nil,
		)
		return (inputs, childrenInBuildOrder)
	}
}

/// What `createMockRootScopeGenerator` decides of a mock root before its tree is built, which the tree names comparison
/// reads (`MockTreeNamesObservation.recordsMockRootPromotion`).
struct MockRootPromotion: Sendable {
	let mockedType: TypeDescription
	/// Whether the mock passes `nil` to a receive a required receive pins (`MockReceivesPassedNil`).
	let passesNilToPinnedReceives: Bool
	/// What the mock root binds of what its tree and its promoted scopes' trees receive (`allReceived`), each in the most
	/// explicit spelling its receivers give.
	let received: Set<Property>
}

/// The comparison of each internal mock root's tree names (`ScopeGenerator.treeNames(of:readsFills:)`) with those its
/// world answers (`MockTreeNamesFromWorld`), handed to `observer`, which only a test sets: a run that sets none builds no
/// world for it and compares nothing.
public enum MockTreeNamesObservation {
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (MockTreeNamesReport) -> Void>?
	/// Handed what `createMockRootScopeGenerator` decides of each mock root before its tree is built, where an `observer` is
	/// set (`DependencyTreeGenerator.generateMockCode`).
	@TaskLocal static var recordsMockRootPromotion: TaskLocalFunction<@Sendable (MockRootPromotion) -> Void>?

	/// Every field of `tree` beside the same field of `world`, each projected to text.
	static func fields(of tree: ScopeGenerator.TreeNames, besideThoseOf world: ScopeGenerator.TreeNames) -> [MockTreeNamesReport.Field] {
		func properties(_ properties: [Property]) -> String {
			properties.map(\.asSource).joined(separator: ", ")
		}
		func sorted(_ texts: some Sequence<String>) -> String {
			texts.sorted().joined(separator: ", ")
		}
		// Every uncovered dependency is instantiated, so its property and the type it instantiates name it.
		func dependency(_ dependency: Dependency) -> String {
			"\(dependency.property.asSource) instantiates \(dependency.asInstantiatedType.asSource)"
		}
		func uncovered(_ uncovered: ScopeGenerator.MockTreeNames.UncoveredDependency) -> String {
			"\(dependency(uncovered.dependency)) hidden: \(uncovered.isHiddenWhereReferenced) sendable: \(uncovered.isInstantiatedInSendableFunction) creatingTypes: [\(uncovered.creatingTypes.map(\.asSource).joined(separator: ", "))]"
		}
		let projections: [(field: String, tree: String, world: String)] = [
			("rootProperties", properties(tree.names.rootProperties), properties(world.names.rootProperties)),
			("mockedTypeUncoveredDependencies", tree.names.mockedTypeUncoveredDependencies.map(dependency).joined(separator: "; "), world.names.mockedTypeUncoveredDependencies.map(dependency).joined(separator: "; ")),
			("uncoveredDependencies", tree.names.uncoveredDependencies.map(uncovered).joined(separator: "; "), world.names.uncoveredDependencies.map(uncovered).joined(separator: "; ")),
			("namesDeclaredInBuilderFunctions", sorted(tree.names.namesDeclaredInBuilderFunctions), sorted(world.names.namesDeclaredInBuilderFunctions)),
			("builderFunctionNames", sorted(tree.names.builderFunctionNames), sorted(world.names.builderFunctionNames)),
			("unavailableDependencyProperties", properties(tree.names.unavailableDependencyProperties), properties(world.names.unavailableDependencyProperties)),
			("rootHoleSiteProperties", properties(tree.names.rootHoleSiteProperties), properties(world.names.rootHoleSiteProperties)),
			("mockedTypeUncoveredProperties", sorted(tree.mockedTypeUncoveredProperties.map(\.asSource)), sorted(world.mockedTypeUncoveredProperties.map(\.asSource))),
		]
		return projections.map { MockTreeNamesReport.Field(field: $0.field, tree: $0.tree, world: $0.world) }
	}

	/// Every input of `tree` beside the same input of `world`, each projected to text, spellings included, and the
	/// generator's children in build order beside the world's.
	static func fields(
		of tree: MockRootParameterInputs,
		besideThoseOf world: MockRootParameterInputs,
		childrenInBuildOrder: (tree: [Property], world: [Property]),
	) -> [MockTreeNamesReport.Field] {
		func sorted(_ properties: Set<Property>) -> String {
			properties.map(\.asSource).sorted().joined(separator: ", ")
		}
		let projections: [(field: String, tree: String, world: String)] = [
			("receivedProperties", sorted(tree.receivedProperties), sorted(world.receivedProperties)),
			("requiredReceivedProperties", sorted(tree.requiredReceivedProperties), sorted(world.requiredReceivedProperties)),
			("onlyIfAvailableUnwrappedReceivedProperties", sorted(tree.onlyIfAvailableUnwrappedReceivedProperties), sorted(world.onlyIfAvailableUnwrappedReceivedProperties)),
			("typesDeclaredEscaping", tree.typesDeclaredEscaping.map(\.asSource).sorted().joined(separator: ", "), world.typesDeclaredEscaping.map(\.asSource).sorted().joined(separator: ", ")),
			("propertiesToDeclare", sorted(tree.propertiesToDeclare), sorted(world.propertiesToDeclare)),
			("receivedOnlyByPublicMockCalls", sorted(tree.receivedOnlyByPublicMockCalls), sorted(world.receivedOnlyByPublicMockCalls)),
			("passedByPublicMockCalls", sorted(tree.passedByPublicMockCalls), sorted(world.passedByPublicMockCalls)),
			("passedByPublicMockCallLabelsReadInsideSendableFunctions", tree.passedByPublicMockCallLabelsReadInsideSendableFunctions.sorted().joined(separator: ", "), world.passedByPublicMockCallLabelsReadInsideSendableFunctions.sorted().joined(separator: ", ")),
			("mockBuilders", tree.mockBuilders == nil ? "none" : "some", world.mockBuilders == nil ? "none" : "some"),
			("childrenInBuildOrder", childrenInBuildOrder.tree.map(\.asSource).joined(separator: ", "), childrenInBuildOrder.world.map(\.asSource).joined(separator: ", ")),
		]
		return projections.map { MockTreeNamesReport.Field(field: $0.field, tree: $0.tree, world: $0.world) }
	}

	/// Every field of the signature `tree`, which the generator lowered, beside the same field of `world`, which the
	/// world's names and inputs lowered with no generator
	/// (`ScopeGenerator.lowerRootSignature(of:flatParameterMockDefaults:tree:inputs:)`), each projected to text, spellings
	/// included. `propertyNodes`, which only a public mock's plan reads, is the generator's alone.
	static func fields(of tree: MockLowering.RootSignature, besideThoseOf world: MockLowering.RootSignature) -> [MockTreeNamesReport.Field] {
		func parameters(_ parameters: [MockLowering.RootSignature.Parameter]) -> String {
			parameters.map { parameter in
				"\(parameter.name): \(parameter.typeSource ?? parameter.property.typeDescription.asSource) = \(parameter.defaultExpression ?? "none") for \(parameter.property.asSource)"
			}.joined(separator: "; ")
		}
		func names(_ namesByLabelAndType: [String: [TypeDescription: String]]) -> String {
			namesByLabelAndType.flatMap { label, names in names.map { "\(label): \($0.key.asSource) -> \($0.value)" } }.sorted().joined(separator: "; ")
		}
		func uncoveredRootParameters(_ signature: MockLowering.RootSignature) -> String {
			signature.uncoveredRootParameters.map { parameter in
				"\(parameter.label): \(parameter.typeSource) for \(parameter.property.asSource) instantiates \(parameter.instantiatedType.asSource) sendable: \(parameter.isSendableAutoclosure) creatingTypes: [\(parameter.creatingTypes.map(\.asSource).joined(separator: ", "))]"
			}.joined(separator: "; ")
		}
		func onlyIfAvailableOverrides(_ signature: MockLowering.RootSignature) -> String {
			signature.onlyIfAvailableOverrides.map { "\($0.name): \($0.typeDescription.asSource) for \($0.receivedProperty.asSource)" }.joined(separator: "; ")
		}
		func lazilyInstantiatedBindings(_ signature: MockLowering.RootSignature) -> String {
			signature.lazilyInstantiatedBindings.map { "\($0.name): \($0.boundType.asSource) = \($0.value)" }.joined(separator: "; ")
		}
		func unavailableDependencyOverrideNames(_ signature: MockLowering.RootSignature) -> String {
			signature.unavailableDependencyOverrideNames.map { "\($0.key.asSource) -> \($0.value)" }.sorted().joined(separator: "; ")
		}
		func builders(_ signature: MockLowering.RootSignature) -> String {
			var builders = signature.passedUpBuilders.map { "passed up \($0.label): \($0.typeSource)" }
			builders.append(contentsOf: signature.seamMockBuilders.map { "seam \($0.label): \($0.parameterType.asSource)" })
			return builders.joined(separator: "; ")
		}
		let projections: [(field: String, tree: String, world: String)] = [
			("forwardedParameters", parameters(tree.forwardedParameters), parameters(world.forwardedParameters)),
			("rootDefaultParameters", parameters(tree.rootDefaultParameters), parameters(world.rootDefaultParameters)),
			("flatReceivedParameters", parameters(tree.flatReceivedParameters), parameters(world.flatReceivedParameters)),
			("uncoveredParameters", parameters(tree.uncoveredParameters), parameters(world.uncoveredParameters)),
			("uncoveredRootParameters", uncoveredRootParameters(tree), uncoveredRootParameters(world)),
			("sharedValueDocumentation", tree.sharedValueDocumentation.joined(separator: "; "), world.sharedValueDocumentation.joined(separator: "; ")),
			("onlyIfAvailableOverrides", onlyIfAvailableOverrides(tree), onlyIfAvailableOverrides(world)),
			("renamesByLabelAndType", names(tree.renamesByLabelAndType), names(world.renamesByLabelAndType)),
			("uncoveredParameterNamesByLabelAndType", names(tree.uncoveredParameterNamesByLabelAndType), names(world.uncoveredParameterNamesByLabelAndType)),
			("signatureTypesDeclaredEscaping", tree.typesDeclaredEscaping.map(\.asSource).sorted().joined(separator: ", "), world.typesDeclaredEscaping.map(\.asSource).sorted().joined(separator: ", ")),
			("lazilyInstantiatedBindings", lazilyInstantiatedBindings(tree), lazilyInstantiatedBindings(world)),
			("lazilyInstantiatedBindingNamesByLabelAndType", names(tree.lazilyInstantiatedBindingNamesByLabelAndType), names(world.lazilyInstantiatedBindingNamesByLabelAndType)),
			("signatureNamesDeclaredInBuilderFunctions", tree.namesDeclaredInBuilderFunctions.sorted().joined(separator: ", "), world.namesDeclaredInBuilderFunctions.sorted().joined(separator: ", ")),
			("unavailableDependencyOverrideNames", unavailableDependencyOverrideNames(tree), unavailableDependencyOverrideNames(world)),
			("builders", builders(tree), builders(world)),
		]
		return projections.map { MockTreeNamesReport.Field(field: $0.field, tree: $0.tree, world: $0.world) }
	}

	/// Every field of what the root's level binds in the tree, `tree`, beside the same field read from the world, `world`
	/// (`MockLowering.rootLevelBindings(of:signature:rootLevelNodes:callsBindNothing:)`), each projected to text.
	static func fields(of tree: MockLowering.RootLevelBindings, besideThoseOf world: MockLowering.RootLevelBindings) -> [MockTreeNamesReport.Field] {
		func names(_ namesByLabelAndType: [String: [TypeDescription: String]]) -> String {
			namesByLabelAndType.flatMap { label, names in names.map { "\(label): \($0.key.asSource) -> \($0.value)" } }.sorted().joined(separator: "; ")
		}
		return [
			MockTreeNamesReport.Field(field: "rootNamesApart", tree: names(tree.namesApart), world: names(world.namesApart)),
			MockTreeNamesReport.Field(field: "rootPropertyNodeBindingNames", tree: tree.propertyNodeBindingNames.sorted().joined(separator: ", "), world: world.propertyNodeBindingNames.sorted().joined(separator: ", ")),
			MockTreeNamesReport.Field(field: "bindsOnlyNodes", tree: "\(tree.bindsOnlyNodes)", world: "\(world.bindsOnlyNodes)"),
		]
	}

	/// The report of the mocked type `instantiable`, whose tree's names are `tree`, whose generator's other inputs to
	/// `mockRootParameters(instantiable:mockDefaults:treeNames:inputs:)` are `inputs`, whose root builds its children in
	/// `childrenInBuildOrder`, and whose signature the generator lowered as `signature` with `flatParameterMockDefaults`,
	/// against its world's answer and the signature that answer lowers with no generator. `promotion` is what
	/// `createMockRootScopeGenerator` decided of the root before its tree was built.
	static func report(
		of instantiable: Instantiable,
		tree: ScopeGenerator.TreeNames,
		inputs: MockRootParameterInputs,
		childrenInBuildOrder: [Property],
		rootLevelNodes: [MockLowering.LevelNode],
		signature: MockLowering.RootSignature,
		flatParameterMockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault],
		worldRoot: ConstructionScope,
		promotion: MockRootPromotion,
	) -> MockTreeNamesReport {
		var declarationVisits = 0
		let answer = MockTreeNamesFromWorld.treeNames(of: instantiable, worldRoot: worldRoot, passesNilToPinnedReceives: promotion.passesNilToPinnedReceives, declarationVisits: &declarationVisits)
		let refusal: MockTreeNamesFromWorld.Refusal
		switch answer {
		case let .names(world):
			if let worldInputs = MockTreeNamesFromWorld.rootInputs(of: worldRoot, spelledAs: promotion.received) {
				let worldSignature = ScopeGenerator.lowerRootSignature(of: instantiable, flatParameterMockDefaults: flatParameterMockDefaults, tree: world, inputs: worldInputs.inputs)
				var comparedFields = fields(of: tree, besideThoseOf: world)
				comparedFields.append(contentsOf: fields(of: inputs, besideThoseOf: worldInputs.inputs, childrenInBuildOrder: (childrenInBuildOrder, worldInputs.childrenInBuildOrder)))
				comparedFields.append(contentsOf: fields(of: signature, besideThoseOf: worldSignature))
				// What the root's level binds, which node records' acceptance reads (`bindsOnlyNodes`): a root the world answers
				// makes no call, so its calls bind nothing.
				comparedFields.append(contentsOf: fields(
					of: MockLowering.rootLevelBindings(of: instantiable, signature: signature, rootLevelNodes: rootLevelNodes, callsBindNothing: true),
					besideThoseOf: MockLowering.rootLevelBindings(of: instantiable, signature: worldSignature, rootLevelNodes: MockLowering.rootLevelNodes(ofWorldRootedAt: worldRoot), callsBindNothing: true),
				))
				return MockTreeNamesReport(root: instantiable.concreteInstantiable.asSource, refusal: nil, fields: comparedFields, declarationVisits: declarationVisits)
			} else {
				refusal = .spelling
			}
		case let .refused(refusalOfNames):
			refusal = refusalOfNames
		}
		return MockTreeNamesReport(root: instantiable.concreteInstantiable.asSource, refusal: refusal.rawValue, fields: [], declarationVisits: declarationVisits)
	}
}

/// One mock root's comparison (`MockTreeNamesObservation`).
public struct MockTreeNamesReport: Sendable {
	/// A field's value in the tree and in the world, each projected to text.
	public struct Field: Sendable, Equatable {
		public let field: String
		public let tree: String
		public let world: String
	}

	/// The mocked type.
	public let root: String
	/// Why the world refused to answer (`MockTreeNamesFromWorld.Refusal`), or `nil` where it answered.
	public let refusal: String?
	/// Every field compared, in a fixed order, empty where the world refused.
	public let fields: [Field]
	/// How many declarations the world's walks visited (`MockTreeNamesFromWorld.treeNames(of:worldRoot:passesNilToPinnedReceives:declarationVisits:)`).
	public let declarationVisits: Int

	/// The fields whose two values differ.
	public var differences: [Field] {
		fields.filter { $0.tree != $0.world }
	}

	/// The world's value of `field`, or `nil` where the world refused.
	public func worldValue(of field: String) -> String? {
		fields.first { $0.field == field }?.world
	}
}
