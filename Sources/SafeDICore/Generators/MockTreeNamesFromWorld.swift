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
/// in. Where the world holds no cycle, the tree is the world unfolded along its built edges, so:
/// - "first met in a walk of the tree in generation order" is the order a depth-first walk in generation order first
///   visits each declaration, since the walk of a tree visits a declaration's whole subtree on its first visit;
/// - a fact that holds "on some path" (a dependency hidden by a builder function around its creator, or created inside a
///   `@Sendable` builder function) is a fold over each declaration's parents in topological order, or a walk of
///   (declaration, inside-`@Sendable`) states;
/// - the types that create a dependency, in the order of their creators' paths sorted by declaration index, then
///   generation index, are the order a depth-first walk in that order first visits each creator.
///
/// It refuses a root it cannot answer exactly (`Refusal`).
enum MockTreeNamesFromWorld {
	/// Why the world of a mock root cannot answer its tree's names exactly.
	enum Refusal: String, Sendable {
		/// A public mock's tree is built with builders for its holes, which its world, built from the tree without them,
		/// does not hold.
		case publicMockRoot
		/// A call of another module's public mock or of a seam, a fill it passes, or a hole's site: the places and passed-up
		/// builders the tree reads from its generator, which the world does not hold.
		case callOrPlace
		/// A declaration on a cycle, or one whose cycle identity another declaration of the world shares (a value and a
		/// lazy wrapper of one label and type): the tree closes a cycle at a path-dependent place, which a world holds no
		/// edge for where the two declarations are built from different records, and a closer can make the builder
		/// functions around it `@Sendable`.
		case cycle
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
	static func treeNames(of instantiable: Instantiable, worldRoot: ConstructionScope) -> Answer {
		guard instantiable.generateMock != .public else { return .refused(.publicMockRoot) }
		let world = TypeFactsGraph(root: worldRoot, forMockGeneration: true)
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
			reached.append(declaration)
			for edge in world.edgeFacts(from: declaration) {
				guard !edge.isFill, world.kind(of: edge.child) != .hole, !isCall(world.construction(of: edge.child)) else { return .refused(.callOrPlace) }
			}
			let declarationChildren = children(of: declaration, declaredBy: dependencies(of: declaration))
			childrenByDeclaration[Int(declaration)] = declarationChildren
			for child in declarationChildren.built where !isReached[Int(child.declaration)] {
				// A twin of another record closes a cycle the world does not hold; one of the same record is on a cycle.
				guard !world.isOnCycle(child.declaration), world.twins[Int(child.declaration)] < 0 else { return .refused(.cycle) }
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

		// Whether a builder function around a creator declares the dependency's label on some path: a fold over the
		// creators' ancestors in topological order, of the labels each type declares that are no dependency it leaves
		// uncovered. The root's level declares in no builder function. Only the labels of uncovered dependencies are kept.
		var uncoveredLabels = Set<String>()
		for declaration in reached where declaration != 0 {
			for dependency in uncoveredDependencies(of: declaration) {
				uncoveredLabels.insert(dependency.property.label)
			}
		}
		var hiddenProperties = Set<Property>()
		if !uncoveredLabels.isEmpty {
			var declaredAround = [Set<String>](repeating: [], count: declarationCount)
			for declaration in topologicalOrder(from: 0, childrenOf: { childrenOf($0).built.map(\.declaration) }, count: declarationCount) where declaration != 0 {
				let uncovered = Set(uncoveredDependencies(of: declaration).map(\.property.label))
				for dependency in uncoveredDependencies(of: declaration) where declaredAround[Int(declaration)].contains(dependency.property.label) {
					hiddenProperties.insert(dependency.property)
				}
				var handedDown = declaredAround[Int(declaration)]
				for dependency in dependencies(of: declaration) where uncoveredLabels.contains(dependency.property.label) && !uncovered.contains(dependency.property.label) {
					handedDown.insert(dependency.property.label)
				}
				for child in childrenOf(declaration).built {
					declaredAround[Int(child.declaration)].formUnion(handedDown)
				}
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

	/// The declarations `root` reaches through `childrenOf`, each before every declaration it reaches: the reverse of a
	/// depth-first walk's finishing order, on an explicit stack. The graph it walks holds no cycle.
	private static func topologicalOrder(from root: DeclarationID, childrenOf: (DeclarationID) -> [DeclarationID], count: Int) -> [DeclarationID] {
		var finished = [DeclarationID]()
		var isStarted = [Bool](repeating: false, count: count)
		var frames = [(declaration: root, children: childrenOf(root), next: 0)]
		isStarted[Int(root)] = true
		while let frame = frames.last {
			if frame.next < frame.children.count {
				frames[frames.count - 1].next += 1
				let child = frame.children[frame.next]
				if !isStarted[Int(child)] {
					isStarted[Int(child)] = true
					frames.append((declaration: child, children: childrenOf(child), next: 0))
				}
			} else {
				finished.append(frame.declaration)
				frames.removeLast()
			}
		}
		return finished.reversed()
	}
}

/// The comparison of each internal mock root's tree names (`ScopeGenerator.treeNames(of:readsFills:)`) with those its
/// world answers (`MockTreeNamesFromWorld`), handed to `observer`, which only a test sets: a run that sets none builds no
/// world for it and compares nothing.
public enum MockTreeNamesObservation {
	@TaskLocal public static var observer: (@Sendable (MockTreeNamesReport) -> Void)?

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

	/// The report of the mocked type `instantiable`, whose tree's names are `tree`, against its world's answer.
	static func report(of instantiable: Instantiable, tree: ScopeGenerator.TreeNames, worldRoot: ConstructionScope) -> MockTreeNamesReport {
		switch MockTreeNamesFromWorld.treeNames(of: instantiable, worldRoot: worldRoot) {
		case let .names(world):
			MockTreeNamesReport(root: instantiable.concreteInstantiable.asSource, refusal: nil, fields: fields(of: tree, besideThoseOf: world))
		case let .refused(refusal):
			MockTreeNamesReport(root: instantiable.concreteInstantiable.asSource, refusal: refusal.rawValue, fields: [])
		}
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

	/// The fields whose two values differ.
	public var differences: [Field] {
		fields.filter { $0.tree != $0.world }
	}

	/// The world's value of `field`, or `nil` where the world refused.
	public func worldValue(of field: String) -> String? {
		fields.first { $0.field == field }?.world
	}
}
