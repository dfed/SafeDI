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

/// The declarations of a module's mock worlds, one entry per distinct declaration key, and which of them a world may take
/// from one graph shared by every world rather than build in its own: the frozen table the mock worlds' sharing is
/// decided by.
///
/// Built whole, on one task, from the roots of the module's mock worlds in the order the module lowers its mock roots,
/// before the lowerings run, and never changed, so parallel work only reads it. One walk, depth first from each root in
/// turn, taking each declaration's edges in the order a world's graph takes them (`TypeFactsDeclaration.edges`), gives
/// each declaration its ID (`RunFactsInterning`) and records its edges once.
///
/// A declaration is shareable only where its facts and its variants' keys are decided by its own subtree and the keys
/// of the reads it takes from above, which a world hands it at its call. So it is not shareable where any declaration
/// it reaches, itself included:
/// - lies on a cycle of the union of the worlds, or beneath one: a cycle's entered slots and twins are decided over the
///   world's paths, so nothing a cycle reaches is shared either, decided over every world at once;
/// - may take part in a loop of builders, or read what a member's rebinding answers
///   (`loopDeclarations(of:nodesByComponent:)`), whose made-again calls and levels are decided over the loop's parents; a
///   declaration merely beneath a member, which reads nothing a member rebinds, stays shareable;
/// - is a hole, a fill, or a call of another module's public mock: a hole of a public mock's world is a place, bound
///   from the builder its mock takes, a fill reads the values of the scope that makes the call (`FillCallerReads`), and a
///   call's record follows the answers its callers pass it upward; and nothing of a world that holds a hole is shared,
///   since its carriers are a fact of a type over the whole world;
/// - receives a label only if available that the module's worlds declare lazily anywhere: what a `nil` answer keys as
///   there (`TypeFactsGraph`'s rule A) is folded over every call into the declaration in its world;
/// - receives a label only if available that a mock root may pin (some world both requires the label and receives it
///   only if available): whether a place passes it `nil` follows the path from the world's mock root to the place
///   (`TypeFactsMockRootPins.receivesPassedNil(alongPath:)`), the world's own required receives above it and beneath its
///   type, so the shared graph, which has no mock root, decides no such pin. This is wider than needed, a place's path
///   could be carried by value, but it keeps what the shared graph holds world-independent.
///
/// A mock root's own declaration is never shareable, and a world keeps the declarations its root builds itself in its
/// own graph whatever the table says (`topDeclarations(ofWorld:)`): their records are made for that world alone. These
/// are facts of the run, known before any world is built, so no world decides another's.
///
/// Built only where a test observes the mock worlds' sharing, so a plain `generate` does no more work. It holds each
/// declaration and its edges as 32-bit IDs and a flag per declaration for as long as `generateMockCode` keeps it: one
/// run's mock generation. Nothing of it is stored between runs.
struct MockWorldsTable: Sendable {
	/// - Parameter worlds: Each mock root's mocked type and the root of its world, in the order the module lowers them.
	init(worlds: [(mockedType: TypeDescription, root: ConstructionScope)]) {
		let rootDeclarations = worlds.map { TypeFactsDeclaration(scope: $0.root, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false) }
		// One graph over every world, from a node that stands for the run and leads to each world's root in order, so the
		// walk's first-reach order is that of each world's walk in turn, and the cycles are those of the union of the worlds.
		let graph = OrderedGraph(root: Node.run) { node in
			switch node {
			case .run:
				rootDeclarations.map(Node.declaration)
			case let .declaration(declaration):
				declaration.edges.map { .declaration($0.target) }
			}
		}
		let interning = RunFactsInterning(declarationsInFirstReachOrder: graph.nodes.lazy.compactMap(\.declaration))
		// A declaration's ID is its node's position less one, the run's node being first.
		var edgeOffsets = [Int32]()
		var edgeTargets = [Int32]()
		for node in 1..<graph.nodes.count {
			edgeOffsets.append(Int32(edgeTargets.count))
			edgeTargets.append(contentsOf: graph.edges(from: node).map { $0 - 1 })
		}
		edgeOffsets.append(Int32(edgeTargets.count))
		let worldRootDeclarations = rootDeclarations.compactMap(interning.declarationID(of:))
		self.interning = interning
		self.edgeOffsets = edgeOffsets
		self.edgeTargets = edgeTargets
		mockedTypes = worlds.map(\.mockedType)
		self.worldRootDeclarations = worldRootDeclarations

		var nodesByComponent = [[Int]](repeating: [], count: graph.componentCount)
		for node in graph.nodes.indices {
			nodesByComponent[Int(graph.componentByNode[node])].append(node)
		}
		let isExcluded = Self.exclusions(of: graph, nodesByComponent: nodesByComponent, worldRoots: worldRootDeclarations.map { Int($0) + 1 })
		// Whether each component reaches an excluded declaration. A component's number is lower than that of every other
		// component that reaches it, so each is judged after every component it reaches.
		var reachesExclusionByComponent = [Bool](repeating: false, count: graph.componentCount)
		for (component, nodes) in nodesByComponent.enumerated() {
			var reachesExclusion = false
			for node in nodes {
				reachesExclusion = reachesExclusion || isExcluded[node]
				for target in graph.edges(from: node) where Int(graph.componentByNode[Int(target)]) != component {
					reachesExclusion = reachesExclusion || reachesExclusionByComponent[Int(graph.componentByNode[Int(target)])]
				}
			}
			reachesExclusionByComponent[component] = reachesExclusion
		}
		var isShareable = (1..<graph.nodes.count).map { !reachesExclusionByComponent[Int(graph.componentByNode[$0])] }
		for root in worldRootDeclarations {
			isShareable[Int(root)] = false
		}
		shareableByDeclaration = isShareable
	}

	/// Whether each node of the run's graph is excluded from sharing itself, before what reaches it is: the conditions
	/// the type's documentation lists. The run's node is excluded too, which nothing reaches.
	private static func exclusions(of graph: OrderedGraph<Node>, nodesByComponent: [[Int]], worldRoots: [Int]) -> [Bool] {
		let nodes = graph.nodes
		var isExcluded = Self.loopDeclarations(of: graph, nodesByComponent: nodesByComponent)
		isExcluded[0] = true
		// Each node's receives only if available from above, the labels the module requires, and those it declares lazily,
		// as the pins and the answers read them.
		var onlyIfAvailableLabels = [Set<String>](repeating: [], count: nodes.count)
		var requiredLabels = Set<String>()
		var lazilyDeclaredLabels = Set<String>()
		for (index, node) in nodes.enumerated() {
			guard let declaration = node.declaration else { continue }
			switch declaration.key.leaf {
			case .alias:
				if declaration.isOnlyIfAvailableAlias, let fulfillingProperty = declaration.aliasFulfillingProperty {
					onlyIfAvailableLabels[index].insert(fulfillingProperty.label)
				}
			case .hole:
				isExcluded[index] = true
			case .none:
				let scope = declaration.scope
				if declaration.key.isFill || scope.publicMockCall != nil {
					isExcluded[index] = true
				}
				for receive in DependencyTreeGenerator.onlyIfAvailableReceivesFromAbove(of: scope) {
					onlyIfAvailableLabels[index].insert(receive.property.label)
				}
				for (label, _) in DependencyTreeGenerator.propertiesReadByRequiredReceivesFromAbove(of: scope.instantiable, publicMockCall: scope.publicMockCall) {
					requiredLabels.insert(label)
				}
				for (property, _) in scope.sortedDeclaredPropertyForms {
					if property.propertyType.isLazilyInstantiated {
						lazilyDeclaredLabels.insert(property.label)
					}
				}
			}
		}
		let receivedOnlyIfAvailableLabels = onlyIfAvailableLabels.reduce(into: Set<String>()) { $0.formUnion($1) }
		let pinnableLabels = requiredLabels.intersection(receivedOnlyIfAvailableLabels)

		// What each component's subtree receives only if available. A component's number is lower than that of every other
		// component that reaches it.
		var subtreeOnlyIfAvailableByComponent = [Set<String>](repeating: [], count: graph.componentCount)
		for (component, componentNodes) in nodesByComponent.enumerated() {
			var onlyIfAvailable = Set<String>()
			for node in componentNodes {
				onlyIfAvailable.formUnion(onlyIfAvailableLabels[node])
				for target in graph.edges(from: node) where Int(graph.componentByNode[Int(target)]) != component {
					onlyIfAvailable.formUnion(subtreeOnlyIfAvailableByComponent[Int(graph.componentByNode[Int(target)])])
				}
			}
			subtreeOnlyIfAvailableByComponent[component] = onlyIfAvailable
			if !onlyIfAvailable.isDisjoint(with: pinnableLabels) || !onlyIfAvailable.isDisjoint(with: lazilyDeclaredLabels) {
				for node in componentNodes {
					isExcluded[node] = true
				}
			}
		}

		// Beneath a cycle, and in a world that holds a hole: every node reached from a node on a cycle or from such a
		// world's root.
		var pending = nodes.indices.filter { $0 > 0 && graph.isOnCycle($0) }
		for root in worldRoots where Self.reachesHole(from: root, in: graph) {
			pending.append(root)
		}
		var isBeneath = [Bool](repeating: false, count: nodes.count)
		while let node = pending.popLast() {
			guard !isBeneath[node] else { continue }
			isBeneath[node] = true
			isExcluded[node] = true
			pending.append(contentsOf: graph.targets(from: node))
		}
		return isExcluded
	}

	/// Whether the world rooted at the run graph's node `root` holds a hole.
	private static func reachesHole(from root: Int, in graph: OrderedGraph<Node>) -> Bool {
		var visited = Set<Int>()
		var pending = [root]
		while let node = pending.popLast() {
			guard visited.insert(node).inserted else { continue }
			if graph.nodes[node].declaration?.key.leaf == .hole {
				return true
			}
			pending.append(contentsOf: graph.targets(from: node))
		}
		return false
	}

	/// Whether each node of the run’s graph may take part in a loop of builders (`SiblingOrder.loops(of:graph:facts:)`) in
	/// some world: a scope with a child built as a builder whose subtree receives the label of a builder child of that
	/// scope, which may be a loop’s parent; each such child, which may be a member, made again and shared apart; and each
	/// declaration beneath such a child that receives one of those labels itself, whose read a member’s rebinding may
	/// answer. A loop needs a member whose tree receives a sibling builder’s label, or its own, so this holds of every
	/// declaration of every loop and of every read a rebinding answers, and of more: labels are compared without the
	/// declarations that hide them.
	private static func loopDeclarations(of graph: OrderedGraph<Node>, nodesByComponent: [[Int]]) -> [Bool] {
		let ownReceivedLabels = graph.nodes.map { node in node.declaration.map(Self.labelsReceived(by:)) ?? [] }
		// A component's number is lower than that of every other component that reaches it.
		var subtreeLabelsByComponent = [Set<String>](repeating: [], count: graph.componentCount)
		for (component, nodes) in nodesByComponent.enumerated() {
			var labels = Set<String>()
			for node in nodes {
				labels.formUnion(ownReceivedLabels[node])
				for target in graph.edges(from: node) where Int(graph.componentByNode[Int(target)]) != component {
					labels.formUnion(subtreeLabelsByComponent[Int(graph.componentByNode[Int(target)])])
				}
			}
			subtreeLabelsByComponent[component] = labels
		}
		func subtreeLabels(of node: Int) -> Set<String> {
			subtreeLabelsByComponent[Int(graph.componentByNode[node])]
		}
		func builderLabel(of node: Int) -> String? {
			graph.nodes[node].declaration?.property.flatMap { ScopeGenerator.isBuilder($0) ? $0.label : nil }
		}
		var isOnLoop = [Bool](repeating: false, count: graph.nodes.count)
		for parent in graph.nodes.indices where graph.nodes[parent].declaration?.key.leaf == TypeFactsDeclaration.Leaf.none {
			let children = graph.targets(from: parent)
			let builderLabels = Set(children.compactMap(builderLabel(of:)))
			for child in children where builderLabel(of: child) != nil && !subtreeLabels(of: child).isDisjoint(with: builderLabels) {
				isOnLoop[parent] = true
				isOnLoop[child] = true
				var visited = Set<Int>()
				var pending = [child]
				while let current = pending.popLast() {
					guard visited.insert(current).inserted else { continue }
					if !ownReceivedLabels[current].isDisjoint(with: builderLabels) {
						isOnLoop[current] = true
					}
					pending.append(contentsOf: graph.targets(from: current).filter { !subtreeLabels(of: $0).isDisjoint(with: builderLabels) })
				}
			}
		}
		return isOnLoop
	}

	/// The labels `declaration` receives itself: its received dependencies’ and the property an alias renames.
	private static func labelsReceived(by declaration: TypeFactsDeclaration) -> Set<String> {
		switch declaration.key.leaf {
		case .none:
			var labels = Set<String>()
			for dependency in declaration.scope.instantiable.dependencies {
				switch dependency.source {
				case .received:
					labels.insert(dependency.property.label)
				case let .aliased(fulfillingProperty, _, _):
					labels.insert(fulfillingProperty.label)
				case .instantiated, .forwarded:
					break
				}
			}
			return labels
		case .alias:
			return declaration.aliasFulfillingProperty.map { [$0.label] } ?? []
		case .hole:
			return []
		}
	}

	/// The ID of the declaration whose key equals `declaration`'s, or `nil` where no world holds one.
	func declarationID(of declaration: TypeFactsDeclaration) -> Int32? {
		interning.declarationID(of: declaration)
	}

	/// The declaration whose ID is `id`, an ID of this table.
	func declaration(ofID id: Int32) -> TypeFactsDeclaration {
		interning.declaration(ofID: id)
	}

	/// The IDs of the declarations the declaration `declaration`, an ID of this table, leads to, in its scope's order.
	func edges(of declaration: Int32) -> ArraySlice<Int32> {
		edgeTargets[Int(edgeOffsets[Int(declaration)])..<Int(edgeOffsets[Int(declaration) + 1])]
	}

	/// How many worlds the table is built over.
	var worldCount: Int {
		worldRootDeclarations.count
	}

	/// The root declaration of the world at `world`, by the order of the worlds.
	func rootDeclaration(ofWorld world: Int) -> Int32 {
		worldRootDeclarations[world]
	}

	/// The declarations the world at `world` builds in its own graph, in the order its walk first reaches them: its root,
	/// each declaration its root builds itself, and each declaration that is not shareable. The shareable declarations it
	/// reaches that one of these leads to are its frontier (`frontierDeclarations(ofWorld:)`).
	func topDeclarations(ofWorld world: Int) -> [Int32] {
		topAndFrontier(ofWorld: world).top
	}

	/// The shareable declarations the world at `world` reaches that one of its top declarations leads to, in the order its
	/// walk first reaches them: the calls its own graph makes into the shared one.
	func frontierDeclarations(ofWorld world: Int) -> [Int32] {
		topAndFrontier(ofWorld: world).frontier
	}

	private func topAndFrontier(ofWorld world: Int) -> (top: [Int32], frontier: [Int32]) {
		let root = worldRootDeclarations[world]
		let rootChildren = Set(edges(of: root))
		var top = [Int32]()
		var frontier = [Int32]()
		var isReached = [Bool](repeating: false, count: shareableByDeclaration.count)
		var frames = [(declaration: root, next: 0)]
		isReached[Int(root)] = true
		top.append(root)
		// Depth first in edge order, as a world's graph walks, stopping at the frontier.
		while var frame = frames.popLast() {
			let targets = edges(of: frame.declaration)
			guard frame.next < targets.count else { continue }
			let target = targets[targets.startIndex + frame.next]
			frame.next += 1
			frames.append(frame)
			guard !isReached[Int(target)] else { continue }
			isReached[Int(target)] = true
			// A child of the root is the root's own wherever the walk first reaches it.
			if shareableByDeclaration[Int(target)], !rootChildren.contains(target) {
				frontier.append(target)
			} else {
				top.append(target)
				frames.append((target, 0))
			}
		}
		return (top, frontier)
	}

	/// What a test observes of the table and of the shared graph built from it: `differences` every way a world's facts
	/// built from the shared graph differ from those of the world built whole.
	func report(shared: MockWorldsSharedGraph, differences: [String]) -> MockWorldsTableReport {
		MockWorldsTableReport(
			declarationCount: interning.declarationCount,
			sharedDeclarationCount: shared.graph.graph.nodes.count,
			sharedVariantCount: shared.graph.variants.count,
			shareableDeclarations: shareableByDeclaration.indices.filter { shareableByDeclaration[$0] }.map { id in
				let declaration = declaration(ofID: Int32(id))
				return "\(id): \(declaration.property?.asSource ?? declaration.scope.instantiable.concreteInstantiable.asSource)"
			},
			differences: differences,
			worlds: mockedTypes.indices.map { world in
				let root = worldRootDeclarations[world]
				let declarations = declarations(inWorldRootedAt: root)
				let (top, frontier) = topAndFrontier(ofWorld: world)
				return MockWorldsTableReport.World(
					mockedType: mockedTypes[world].asSource,
					rootDeclaration: Int(root),
					declarationCount: declarations.count,
					shareableDeclarationCount: declarations.count(where: { shareableByDeclaration[Int($0)] }),
					topDeclarationCount: top.count,
					frontierDeclarationCount: frontier.count,
					sharedVariantsCalled: shared.worlds[world].frontierCalls.map { Int($0.sharedVariant) },
					sharedDeclarationParents: shared.worlds[world].parentsByDeclaration.map { declaration, parents in
						let parentTexts = parents.map { parent in
							switch parent {
							case let .top(id):
								"top \(id)"
							case let .shared(node):
								"shared \(node)"
							}
						}
						return "\(declaration) ← \(parentTexts.joined(separator: ", "))"
					},
				)
			},
		)
	}

	/// The declarations the world rooted at `root` holds, in the order its walk first reaches them.
	private func declarations(inWorldRootedAt root: Int32) -> [Int32] {
		var isReached = [Bool](repeating: false, count: shareableByDeclaration.count)
		isReached[Int(root)] = true
		var reached = [root]
		var pending = [root]
		while let declaration = pending.popLast() {
			for target in edges(of: declaration) where !isReached[Int(target)] {
				isReached[Int(target)] = true
				reached.append(target)
				pending.append(target)
			}
		}
		return reached
	}

	/// A node of the table's walk: the run, which leads to each world's root, or a declaration.
	private enum Node: Hashable, Sendable {
		case run
		case declaration(TypeFactsDeclaration)

		var declaration: TypeFactsDeclaration? {
			switch self {
			case .run:
				nil
			case let .declaration(declaration):
				declaration
			}
		}
	}

	private let interning: RunFactsInterning
	/// Where each declaration's edges start in `edgeTargets`; the last entry is the number of edges.
	private let edgeOffsets: [Int32]
	/// The declaration each edge leads to, each declaration's edges in a run starting at its offset, in its scope's order.
	private let edgeTargets: [Int32]
	/// Whether each declaration is shareable.
	private let shareableByDeclaration: [Bool]
	private let mockedTypes: [TypeDescription]
	/// The declaration of each world's root, in the order of `mockedTypes`.
	private let worldRootDeclarations: [Int32]
}

/// What a test observes of the mock worlds' sharing (`MockWorldsTable`), where it sets `observer`.
public enum MockWorldsTableObservation {
	/// Handed the table's report once per module's mock generation, where this is set. Only a test sets it.
	@TaskLocal public static var observer: (@Sendable (MockWorldsTableReport) -> Void)?
}

/// The counts of the mock worlds' table: its distinct declarations, those shareable, and each world's; and every way a
/// world's facts taken from the shared graph differ from those of the world built whole.
public struct MockWorldsTableReport: Equatable, Sendable {
	/// One mock root's world.
	public struct World: Equatable, Sendable {
		public init(mockedType: String, rootDeclaration: Int, declarationCount: Int, shareableDeclarationCount: Int, topDeclarationCount: Int, frontierDeclarationCount: Int, sharedVariantsCalled: [Int], sharedDeclarationParents: [String]) {
			self.mockedType = mockedType
			self.rootDeclaration = rootDeclaration
			self.declarationCount = declarationCount
			self.shareableDeclarationCount = shareableDeclarationCount
			self.topDeclarationCount = topDeclarationCount
			self.frontierDeclarationCount = frontierDeclarationCount
			self.sharedVariantsCalled = sharedVariantsCalled
			self.sharedDeclarationParents = sharedDeclarationParents
		}

		/// The mocked type.
		public let mockedType: String
		/// The ID of the world's root declaration: its position in the table's walk.
		public let rootDeclaration: Int
		/// How many declarations the world holds, its root's included.
		public let declarationCount: Int
		/// How many of them are shareable.
		public let shareableDeclarationCount: Int
		/// How many declarations the world builds in its own graph: its root, those its root builds, and those not
		/// shareable.
		public let topDeclarationCount: Int
		/// How many shareable declarations its own declarations lead to: the declarations it calls in the shared graph.
		public let frontierDeclarationCount: Int
		/// The shared variant each call of the world's own variants into the shared graph lands on, in the world's order of
		/// variants, each variant's calls in edge order.
		public let sharedVariantsCalled: [Int]
		/// Each shared declaration the world reaches, by its position in the shared graph, in the order the world first
		/// reaches them, with the parents the world reaches it through, in the world's order: `top` and the table ID of a
		/// declaration of the world's own graph, or `shared` and a position in the shared graph.
		public let sharedDeclarationParents: [String]
	}

	public init(declarationCount: Int, sharedDeclarationCount: Int, sharedVariantCount: Int, shareableDeclarations: [String], differences: [String], worlds: [World]) {
		self.declarationCount = declarationCount
		self.sharedDeclarationCount = sharedDeclarationCount
		self.sharedVariantCount = sharedVariantCount
		self.shareableDeclarations = shareableDeclarations
		self.differences = differences
		self.worlds = worlds
	}

	/// How many distinct declarations the module's mock worlds hold.
	public let declarationCount: Int
	/// How many declarations the shared graph holds, each once whatever number of worlds reach it.
	public let sharedDeclarationCount: Int
	/// How many variants the shared graph holds: one per body the worlds' calls reach with one key.
	public let sharedVariantCount: Int
	/// Each shareable declaration, in ID order: its ID and its property (the type, for a declaration with none).
	public let shareableDeclarations: [String]
	/// Each way a world's facts taken from the shared graph differ from those of the world built whole, which a test fails
	/// on.
	public let differences: [String]
	/// Each world, in the order the module lowers its mock roots.
	public let worlds: [World]
}
