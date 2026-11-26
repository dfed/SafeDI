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

/// The places one pass of a tree builds, in the order its walk starts them, as a test observes them beside the tree's
/// graph (`TypeFactsReport`). Recorded only for the reference build the construction memo oracle makes, which reuses
/// nothing, so every place is walked; the tool records none. It holds one entry per place, with the reads its subtree
/// made of the context above it, until the report is made.
struct TypeFactsPlaces {
	struct Place {
		/// The place that builds this one, or `nil` for the root.
		let parent: Int?
		let declaration: TypeFactsDeclaration
		/// Whether the place closes a cycle on a declaration above it, which builds no children.
		var closesCycle = false
		/// What the place's subtree read of the context above it, once the place is finished.
		var reads = ConstructionLog()
	}

	private(set) var places = [Place]()

	/// Starts a place built as `declaration` by the place at `parent`, and returns its position.
	mutating func start(_ declaration: TypeFactsDeclaration, parent: Int?) -> Int {
		places.append(Place(parent: parent, declaration: declaration))
		return places.count - 1
	}

	/// Finishes the place at `index`.
	mutating func finish(_ index: Int, closesCycle: Bool, reads: ConstructionLog) {
		places[index].closesCycle = closesCycle
		places[index].reads = reads
	}
}

/// A world's graph beside the places one build of its tree made, for a test to compare (`ConstructionMemoOracle`): each
/// node with its edges, what its subtree reads from above it and its first route; each place with the node it maps to
/// and the reads its subtree made of the context above it, as `Read`s and with their answers. Made only where a test
/// observes trees, never by the tool.
public struct TypeFactsReport: Sendable {
	init(root: ConstructionScope, places: TypeFactsPlaces, forMockGeneration: Bool) {
		let graph = TypeFactsGraph(root: root, forMockGeneration: forMockGeneration)
		self.root = root.instantiable.concreteInstantiable.asSource
		self.forMockGeneration = forMockGeneration
		projection = graph.projection
		world = Self.projection(of: graph)
		var variantCounts = [Int](repeating: 0, count: graph.declarationCount)
		for variant in 0..<graph.variantCount {
			variantCounts[Int(graph.declaration(of: VariantID(variant)))] += 1
		}
		variantCountsByNode = variantCounts
		variantNodes = (0..<graph.variantCount).map { Int(graph.declaration(of: VariantID($0))) }
		variantCalls = (0..<graph.variantCount).map { graph.calls(of: VariantID($0)).map(Int.init) }
		columnElementCount = graph.columnElementCount
		edgeCount = graph.graph.edgeCount
		nodes = graph.graph.nodes.indices.map { index in
			Node(
				description: graph.description(ofNode: index),
				construction: "\(graph.constructions[index])",
				cycleKey: graph.cycleKey(ofNode: index),
				edges: graph.graph.edges(from: index).map(Int.init),
				instantiatedEdgeCount: Int(graph.instantiatedEdgeCounts[index]),
				isOnCycle: graph.graph.isOnCycle(index),
				readsFromAbove: graph.reads.reads(of: index).map(graph.readDescription),
				firstRoute: graph.graph.firstRoute(to: index),
			)
		}
		self.places = places.places.map { place in
			var reads = [String]()
			var answeredReads = [String]()
			var cycleReads = [String]()
			var readsAnswered = Set<ConstructionLog.Read>()
			place.reads.forEachRead { read, answer, _ in
				guard let declaredRead = read.declaredRead else {
					cycleReads.append("\(read) = \(answer.projection)")
					return
				}
				reads.append(declaredRead)
				// The first answer of a read is the one a key compares; a deeper declaration answers it for a scope beneath.
				if readsAnswered.insert(read).inserted {
					answeredReads.append("\(declaredRead) = \(answer.projection)")
				}
			}
			return Place(
				parent: place.parent,
				node: graph.graph.index(of: place.declaration),
				declaration: place.declaration.scope.instantiable.concreteInstantiable.asSource + (place.declaration.property.map { " as \($0.asSource)" } ?? ""),
				isFill: place.declaration.key.isFill,
				closesCycle: place.closesCycle,
				reads: reads,
				answeredReads: answeredReads.sorted(),
				cycleReads: cycleReads,
			)
		}
	}

	public struct Node: Sendable {
		public let description: String
		/// How the node's type is built: `initializer`, `seamCall`, `publicMockCall` or `fill`.
		public let construction: String
		/// What a place of the node closes a cycle on, as cycle validation sees its property: two nodes of one key close on
		/// each other, a lazy wrapper and its constant among them.
		public let cycleKey: String
		/// The positions of the nodes its edges lead to, in edge order.
		public let edges: [Int]
		/// How many of `edges`, the first ones, are properties the node's scope instantiates; the rest are fills.
		public let instantiatedEdgeCount: Int
		public let isOnCycle: Bool
		/// What the node's subtree reads from above it, as `Read` descriptions.
		public let readsFromAbove: [String]
		/// The nodes from the root to this one on the first route a walk of the edges in order finds.
		public let firstRoute: [Int]
	}

	public struct Place: Sendable {
		/// The place that builds this one, or `nil` for the root.
		public let parent: Int?
		/// The node of the place's declaration, or `nil` where the graph has none.
		public let node: Int?
		public let declaration: String
		public let isFill: Bool
		public let closesCycle: Bool
		/// The reads the place's subtree made of the context above it, as `Read` descriptions, in the order they were made.
		public let reads: [String]
		/// Each read with the answer the place's context gave, sorted: what tells two places of one node apart.
		public let answeredReads: [String]
		/// The reads of what a cycle closes on or passes, which no `Read` stands for, each with its answer.
		public let cycleReads: [String]
	}

	/// The concrete type of the world's root.
	public let root: String
	/// The 32-bit elements of the graph's columns, which grow with its nodes and edges.
	public let columnElementCount: Int
	public let edgeCount: Int
	public let forMockGeneration: Bool
	/// The graph as text, a line per node (`TypeFactsGraph.projection`).
	public let projection: String
	public let nodes: [Node]
	/// The places in the order the build started them, the root first.
	public let places: [Place]
	/// The world as every track reads it (`TypeFactsWorld`), a line per declaration then a line per variant.
	public let world: String
	/// How many variants each node has, by node position.
	public let variantCountsByNode: [Int]
	/// Each variant's node.
	public let variantNodes: [Int]
	/// The variant each edge of a variant's node calls, in edge order.
	public let variantCalls: [[Int]]

	/// The world read through its interface only, as text: what a consumer of the frozen accessors sees.
	private static func projection(of world: some TypeFactsWorld) -> String {
		var lines = [String]()
		for index in 0..<world.declarationCount {
			let declaration = DeclarationID(index)
			var line = "d\(index) \(world.kind(of: declaration)) \(world.construction(of: declaration)) property \(world.propertyID(of: declaration))"
			line += " type \(world.builtType(of: declaration).raw) cycle \(world.cycle(of: declaration)) component \(world.component(of: declaration))"
			line += world.isOnCycle(declaration) ? " on cycle" : ""
			line += " route \(world.firstRoute(to: declaration)) edges \(Array(world.edges(from: declaration)))"
			line += " facts \(world.edgeFacts(from: declaration).count) bindings \(world.bindings(of: declaration).count)"
			line += " parents \(world.parents(of: declaration).count) hole \(world.hole(declaration) != nil) received \(world.received(by: declaration).count)"
			line += " receives \(world.receives(of: declaration).map { world.acceptedProperties(of: $0).count })"
			line += " reads [\(world.reads(of: declaration).map { "\(world.read($0).channel.name)" }.joined(separator: ", "))]"
			line += " labels \(Array(world.labels(of: declaration)))"
			lines.append(line)
		}
		lines.append("roots \((0..<world.rootCount).map(world.rootVariant))")
		for index in 0..<world.variantCount {
			let variant = VariantID(index)
			var line = "v\(index) d\(world.declaration(of: variant)) \(world.family(of: variant))"
			line += " keys [\(world.keys(of: variant).map { "\(world.answer($0).form) \(world.forms(of: $0).count)" }.joined(separator: ", "))]"
			let calls = world.calls(of: variant)
			line += " calls \(Array(calls)) sources [\(calls.indices.map { "\(world.sources(ofCall: $0 - calls.startIndex, of: variant).map(\.kind))" }.joined(separator: ", "))]"
			line += world.isCalledOnce(variant) ? " once" : ""
			line += " outcomes \(world.outcomes(of: variant).map { "\($0)" }) bound before \(Array(world.boundBefore(of: variant)))"
			lines.append(line)
		}
		return lines.joined(separator: "\n")
	}
}

extension ConstructionLog.Read {
	/// The text of the declared read this logged read is, as `Read.description(labels:)` spells it, or `nil` for a read of
	/// what a cycle closes on or passes, which every reference to a cycle's member, a call, makes unnecessary.
	var declaredRead: String? {
		switch self {
		case let .nearestDeclaration(label):
			"\(ReadChannel.value.name)(\(label))"
		case let .binding(property):
			"\(ReadChannel.optional.name)(\(property.label))"
		case let .passesNil(property, _, _):
			"\(ReadChannel.mock.name)(\(property.label))"
		case .declarationClosedOn, .cycleParameterContext:
			nil
		}
	}
}

extension ConstructionLog.Answer {
	/// The answer as text that two answers `==` equates share, every set and dictionary in it sorted.
	var projection: String {
		switch self {
		case let .nearestDeclaration(declaration):
			guard let declaration else { return "none" }
			var parts = [String]()
			parts.append("bindings [\(declaration.bindings.sorted { $0.key < $1.key }.map { "\($0.key.asSource): \($0.value.asSource)" }.joined(separator: ", "))]")
			parts.append("being built [\(declaration.formsBeingBuilt.sorted().map(\.asSource).joined(separator: ", "))]")
			parts.append("passed nil [\(declaration.receivesPassedNil.sorted { $0.key < $1.key }.map { "\($0.key.asSource): \($0.value.sorted().map(\.asSource).joined(separator: ", "))" }.joined(separator: "; "))]")
			parts.append("pinned above \(declaration.judgesPlacesPinnedFromAbove)")
			parts.append("read above [\(declaration.propertiesReadByRequiredReceivesAbove.map { $0.sorted().map(\.asSource).joined(separator: ", ") }.joined(separator: "; "))]")
			parts.append("bound by mock root \(declaration.isBoundByMockRoot)")
			return parts.joined(separator: " ")
		case let .binding(property):
			return property?.asSource ?? "nil"
		case let .passesNil(passesNil):
			return "\(passesNil)"
		case let .declarationClosedOn(id):
			return id.map { "\($0)" } ?? "nil"
		case let .cycleParameterContext(parameters):
			return parameters.map { "\($0.map(\.property.asSource))" } ?? "nil"
		}
	}
}
