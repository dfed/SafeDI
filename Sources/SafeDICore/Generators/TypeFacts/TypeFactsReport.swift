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
		/// What the generator built at the place decided, once the place is finished.
		var generator: TypeFactsGeneratorFacts?
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

	/// Records what the generator built at the place at `index` decided.
	mutating func record(_ index: Int, generator: ScopeGenerator) {
		places[index].generator = TypeFactsGeneratorFacts(generator)
	}
}

/// What one place's generator decided that a node's columns stand for, kept for the checks to compare with the graph.
struct TypeFactsGeneratorFacts: Sendable {
	init(_ fillOrGenerator: ScopeGenerator) {
		// A fill's generator holds one child, the filled property built as declared, which builds the fill's node.
		let generator = if case .fill = fillOrGenerator.scopeData, let child = fillOrGenerator.propertiesToGenerate.first {
			child
		} else {
			fillOrGenerator
		}
		// A call's fills follow the properties its scope lists; a node's fills are edges of their own.
		let children = generator.propertiesToGenerate.filter { child in
			if case .fill = child.scopeData {
				false
			} else {
				true
			}
		}
		childCount = children.count
		orderedIndices = generator.orderedChildGeneratorsWithIndices.map(\.index).filter { $0 < children.count }
		loopByChildIndex = children.indices.map { generator.receivedBuilderLoops.loopByChildIndex[$0] ?? -1 }
		// Every child is built as a property: a fill is left out above, and no root is a child.
		childLabels = children.map { $0.property?.label ?? "" }
		received = generator.receivedProperties
		required = generator.requiredReceivedProperties
		onlyIfAvailableUnwrapped = generator.onlyIfAvailableUnwrappedReceivedProperties
		requiredAliasFulfilling = generator.requiredAliasFulfillingProperties
		typesDeclaredEscaping = generator.typesDeclaredEscaping
		buildsInSendableFunction = generator.buildsInSendableFunction
		constructsWithHandWrittenMock = generator.constructsWithHandWrittenMock
		callsSeam = if case let .property(_, _, _, _, _, seamCall) = generator.scopeData {
			seamCall != nil
		} else {
			false
		}
		callsPublicMock = generator.publicMockCall != nil
		cycleParameters = generator.cycleParameters.map(\.property)
	}

	let childCount: Int
	/// The children's indices in the order the generator builds them.
	let orderedIndices: [Int]
	/// Each child's loop of builders, named by the index of its first member, or -1.
	let loopByChildIndex: [Int]
	let childLabels: [String]
	let received: Set<Property>
	let required: Set<Property>
	let onlyIfAvailableUnwrapped: Set<Property>
	let requiredAliasFulfilling: Set<Property>
	let typesDeclaredEscaping: Set<TypeDescription>
	let buildsInSendableFunction: Bool
	let constructsWithHandWrittenMock: Bool
	let callsSeam: Bool
	let callsPublicMock: Bool
	/// The parameters of the place's builder function that a cycle closing on it passes, in the function's order.
	let cycleParameters: [Property]
}

/// A world's graph beside the places one build of its tree made, for a test to compare (`ConstructionMemoOracle`): each
/// node with its edges, what its subtree reads from above it and its first route; each place with the node it maps to
/// and the reads its subtree made of the context above it, as `Read`s and with their answers. Made only where a test
/// observes trees, never by the tool.
public struct TypeFactsReport: Sendable {
	init(root: ConstructionScope, places: TypeFactsPlaces, forMockGeneration: Bool, tree: ScopeGenerator) {
		let graph = TypeFactsGraph(root: root, forMockGeneration: forMockGeneration)
		let unfolding = TypeFactsDOT(graph: graph, tree: tree)
		dot = DOT(
			drawnByTree: ScopeGenerator.drawnTree(of: tree),
			unfolded: unfolding.unfolded,
			declarationsDrawnPerPath: unfolding.declarationsDrawnPerPath,
		)
		self.graph = graph
		self.root = root.instantiable.concreteInstantiable.asSource
		self.forMockGeneration = forMockGeneration
		holesArePlaces = graph.holesArePlaces
		projection = graph.projection
		world = Self.projection(of: graph)
		var variantCounts = [Int](repeating: 0, count: graph.declarationCount)
		for variant in 0..<graph.variantCount {
			variantCounts[Int(graph.declaration(of: VariantID(variant)))] += 1
		}
		variantCountsByNode = variantCounts
		variantNodes = (0..<graph.variantCount).map { Int(graph.declaration(of: VariantID($0))) }
		variantFamilies = (0..<graph.variantCount).map { "\(graph.family(of: VariantID($0)))" }
		variantBuildsInSendableFunction = (0..<graph.variantCount).map { graph.buildsInSendableFunction(VariantID($0)) }
		var variantOneFunctionGroups = [Int?](repeating: nil, count: graph.variantCount)
		for (group, members) in graph.oneFunctionGroups.enumerated() {
			for member in members {
				variantOneFunctionGroups[member] = group
			}
		}
		self.variantOneFunctionGroups = variantOneFunctionGroups
		variantCalls = (0..<graph.variantCount).map { graph.calls(of: VariantID($0)).map(Int.init) }
		variantMadeAgainCalls = (0..<graph.variantCount).map { graph.madeAgainCalls(of: VariantID($0)).map(Int.init) }
		variantMadeAgain = (0..<graph.variantCount).map { graph.madeAgain(of: VariantID($0)).map(Int.init) }
		variantMadeAgainLabels = (0..<graph.variantCount).map { graph.madeAgainLabels(of: VariantID($0)).map { graph.labelTexts[Int($0)] } }
		variantIsCalledOnce = (0..<graph.variantCount).map { graph.isCalledOnce(VariantID($0)) }
		func sourceDescriptions(_ sources: ArraySlice<AnswerSource>) -> [String] {
			sources.map { source in
				switch source.kind {
				case .none, .passedThrough:
					"\(source.kind)"
				case .bound:
					"bound \(graph.answer(source.answer).form)"
				}
			}
		}
		variantCallSources = (0..<graph.variantCount).map { variant in
			graph.calls(of: VariantID(variant)).indices.map { call in
				sourceDescriptions(graph.sources(ofCall: call - graph.calls(of: VariantID(variant)).startIndex, of: VariantID(variant)))
			}
		}
		variantMadeAgainCallSources = (0..<graph.variantCount).map { variant in
			graph.madeAgainCalls(of: VariantID(variant)).indices.map { call in
				sourceDescriptions(graph.sources(ofMadeAgainCall: call - graph.madeAgainCalls(of: VariantID(variant)).startIndex, of: VariantID(variant)))
			}
		}
		loopMembersSharedApart = graph.loopMembersSharedApart.map(Int.init)
		let arrivals = TypeFactsReadArrivals(world: graph)
		variantParameters = (0..<graph.variantCount).map { graph.parameters(of: VariantID($0), arrivals: arrivals).map(\.property.spelledWithoutAny) }
		columnElementCount = graph.columnElementCount
		edgeCount = graph.graph.edgeCount
		func spelled(_ row: BitRows, of index: Int, _ spelling: (Int32) -> String) -> [String] {
			row.columns(inRow: index).map(spelling).sorted()
		}
		func property(_ id: Int32) -> String {
			graph.propertyTable[Int(id)].asSource
		}
		// The receive sets intern a property's first spelling, while the generator's keep the most explicit, so both are
		// spelled as `==` reads them.
		func propertyWithoutAny(_ id: Int32) -> String {
			graph.propertyTable[Int(id)].spelledWithoutAny
		}
		func type(_ id: Int32) -> String {
			graph.typeTable[Int(id)].asSource
		}
		nodes = graph.graph.nodes.indices.map { index in
			let edgeFacts = graph.edgeFacts(from: index)
			return Node(
				description: graph.description(ofNode: index),
				kind: "\(graph.kinds[index])",
				construction: "\(graph.constructions[index])",
				label: graph.graph.nodes[index].property?.label ?? "",
				isLeaf: graph.graph.nodes[index].key.leaf != .none,
				cycleKey: graph.cycleKey(ofNode: index),
				cycleKeyID: Int(graph.cycleIDs[index]),
				twin: Int(graph.twins[index]),
				edges: graph.graph.edges(from: index).map(Int.init),
				edgeFacts: edgeFacts.map { edge in
					Edge(
						buildPosition: Int(edge.buildPosition),
						loop: Int(edge.loop),
						opens: "\(edge.opens)",
						isFill: edge.isFill,
						isCallEdge: edge.isCallEdge,
						bindingsBefore: Int(edge.bindingsBefore),
					)
				},
				instantiatedEdgeCount: edgeFacts.count { !$0.isFill },
				madeAgain: graph.madeAgain(from: DeclarationID(index)).map(Int.init),
				madeAgainLabels: graph.madeAgainLabels(from: DeclarationID(index)).map { graph.labelTexts[Int($0)] },
				bindings: graph.worldBindings(of: index).map { binding in
					"\(graph.labelTexts[Int(binding.label)]): \(property(binding.property))"
				},
				bindingModules: graph.worldBindings(of: index).map { binding in
					binding.declaringModule >= 0 ? graph.moduleNames[Int(binding.declaringModule)] : ""
				},
				module: graph.graph.nodes[index].scope.instantiable.moduleName ?? "",
				parents: graph.parents(of: index).map { Int($0.parent) },
				fillCount: graph.fills.count { TypeFactsGraph.source(ofEdge: Int($0.edge), in: graph.graph) == index },
				received: spelled(graph.receives.received, of: index, propertyWithoutAny),
				required: spelled(graph.receives.required, of: index, propertyWithoutAny),
				onlyIfAvailableUnwrapped: spelled(graph.receives.onlyIfAvailableUnwrapped, of: index, propertyWithoutAny),
				requiredAliasFulfilling: spelled(graph.receives.requiredAliasFulfilling, of: index, propertyWithoutAny),
				typesDeclaredEscaping: spelled(graph.typesDeclaredEscaping, of: index, type),
				typesBeneath: spelled(graph.typesBeneath, of: index, type),
				holdsHoleBeneath: graph.holesBeneath.contains(0, inRow: index),
				holdsCaseBeneath: graph.casesBeneath.contains(0, inRow: index),
				builtType: type(graph.builtTypes[index]),
				isOnCycle: graph.graph.isOnCycle(index),
				readsFromAbove: graph.reads.reads(of: index).map(graph.readDescription),
				firstRoute: graph.graph.firstRoute(to: index),
				owedFacts: Self.names(of: graph.owedFacts(of: Int32(index))),
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
				builtType: place.declaration.scope.instantiable.concreteInstantiable.asSource,
				generator: place.generator.map(Generator.init),
			)
		}
	}

	/// An edge's facts (`TypeFactsEdge`), as text where they are an enum.
	public struct Edge: Sendable {
		public let buildPosition: Int
		public let loop: Int
		public let opens: String
		public let isFill: Bool
		public let isCallEdge: Bool
		public let bindingsBefore: Int
	}

	/// What the generator built at a place decided (`TypeFactsGeneratorFacts`), properties and types as text.
	public struct Generator: Sendable {
		init(_ facts: TypeFactsGeneratorFacts) {
			childCount = facts.childCount
			orderedIndices = facts.orderedIndices
			loopByChildIndex = facts.loopByChildIndex
			childLabels = facts.childLabels
			received = facts.received.map(\.spelledWithoutAny).sorted()
			required = facts.required.map(\.spelledWithoutAny).sorted()
			onlyIfAvailableUnwrapped = facts.onlyIfAvailableUnwrapped.map(\.spelledWithoutAny).sorted()
			requiredAliasFulfilling = facts.requiredAliasFulfilling.map(\.spelledWithoutAny).sorted()
			typesDeclaredEscaping = facts.typesDeclaredEscaping.map(\.asSource).sorted()
			buildsInSendableFunction = facts.buildsInSendableFunction
			constructsWithHandWrittenMock = facts.constructsWithHandWrittenMock
			callsSeam = facts.callsSeam
			callsPublicMock = facts.callsPublicMock
			cycleParameters = facts.cycleParameters.map(\.spelledWithoutAny)
		}

		public let childCount: Int
		public let orderedIndices: [Int]
		public let loopByChildIndex: [Int]
		public let childLabels: [String]
		public let received: [String]
		public let required: [String]
		public let onlyIfAvailableUnwrapped: [String]
		public let requiredAliasFulfilling: [String]
		public let typesDeclaredEscaping: [String]
		public let buildsInSendableFunction: Bool
		public let constructsWithHandWrittenMock: Bool
		public let callsSeam: Bool
		public let callsPublicMock: Bool
		public let cycleParameters: [String]
	}

	public struct Node: Sendable {
		public let description: String
		/// The node's kind (`TypeFactsKind`).
		public let kind: String
		/// How the node's type comes to exist (`TypeFactsConstruction`).
		public let construction: String
		/// The label of the property the node is built as, empty for the root.
		public let label: String
		/// Whether the node is an alias or a hole its scope declares, which no place builds.
		public let isLeaf: Bool
		/// What a place of the node closes a cycle on, as cycle validation sees its property: two nodes of one key close on
		/// each other, a lazy wrapper and its constant among them.
		public let cycleKey: String
		/// The node's cycle identity (A4), which two nodes of one `cycleKey` share, or -1 for a leaf.
		public let cycleKeyID: Int
		/// The first other node of its cycle identity, or -1.
		public let twin: Int
		/// The positions of the nodes its edges lead to, in edge order.
		public let edges: [Int]
		/// Each edge's facts, parallel to `edges`.
		public let edgeFacts: [Edge]
		/// How many of `edges`, the first ones, are properties the node's scope lists; the rest are fills.
		public let instantiatedEdgeCount: Int
		/// The positions of the members of loops of builders its body makes again, in the order it rebinds them.
		public let madeAgain: [Int]
		/// The label its body rebinds each of those as, which its own argument for that label always passes.
		public let madeAgainLabels: [String]
		/// The node's bindings in binding order, `label: property`.
		public let bindings: [String]
		/// The module declaring each binding, parallel to `bindings`.
		public let bindingModules: [String]
		/// The module of the node's type.
		public let module: String
		/// The node's parents, in first-reach order.
		public let parents: [Int]
		/// How many fills the node's call passes.
		public let fillCount: Int
		public let received: [String]
		public let required: [String]
		public let onlyIfAvailableUnwrapped: [String]
		public let requiredAliasFulfilling: [String]
		public let typesDeclaredEscaping: [String]
		/// The types the node's subtree builds, its own included.
		public let typesBeneath: [String]
		public let holdsHoleBeneath: Bool
		/// In a seam's own tree, whether a hole is beneath the node along every edge, fills included.
		public let holdsCaseBeneath: Bool
		public let builtType: String
		public let isOnCycle: Bool
		/// What the node's subtree reads from above it, as `Read` descriptions.
		public let readsFromAbove: [String]
		/// The nodes from the root to this one on the first route a walk of the edges in order finds.
		public let firstRoute: [Int]
		/// The facts producers still owe the node's answers (`TypeFactsOwedFacts`), by the names of their bits.
		public let owedFacts: Set<String>
	}

	private static func names(of owed: TypeFactsOwedFacts) -> Set<String> {
		let named: [(TypeFactsOwedFacts, String)] = [
			(.fillBeingBuilt, "fillBeingBuilt"),
			(.mockRootPin, "mockRootPin"),
			(.mockRootRecord, "mockRootRecord"),
			(.mockRootBinding, "mockRootBinding"),
		]
		return Set(named.filter { owed.contains($0.0) }.map(\.1))
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
		/// The concrete type the place builds.
		public let builtType: String
		/// What the place's generator decided, or `nil` where the walk recorded none.
		public let generator: Generator?
	}

	/// The tree's DOT graph as its places draw it and as the graph's declarations unfold it (`TypeFactsDOT`), which must be
	/// the same bytes.
	public struct DOT: Sendable {
		/// `ScopeGenerator.generateDOT()`'s text of the tree.
		public let drawnByTree: String
		/// The text unfolded from each declaration's column.
		public let unfolded: String
		/// The declarations two of whose places draw otherwise.
		public let declarationsDrawnPerPath: [String]
	}

	/// The world's graph, which a test of what it holds reads.
	let graph: TypeFactsGraph
	/// The concrete type of the world's root.
	public let root: String
	public let dot: DOT
	/// The 32-bit elements of the graph's columns, which grow with its nodes and edges.
	public let columnElementCount: Int
	public let edgeCount: Int
	public let forMockGeneration: Bool
	/// Whether the world's holes are places: a seam's own tree, or a public mock's.
	public let holesArePlaces: Bool
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
	/// Each variant's family (`VariantFamily`), spelled as its case.
	public let variantFamilies: [String]
	/// Per variant, whether a call builds its body inside a `@Sendable` function, folded over every call into it.
	public let variantBuildsInSendableFunction: [Bool]
	/// Per variant, the group of twins' variants one function serves that it is in, which share the mark of any family.
	public let variantOneFunctionGroups: [Int?]
	/// The variant each edge of a variant's node calls, in edge order.
	public let variantCalls: [[Int]]
	/// The variant each made-again call of a variant calls, in the order its node rebinds the members.
	public let variantMadeAgainCalls: [[Int]]
	/// The node of each member a variant makes again, in the order it rebinds them.
	public let variantMadeAgain: [[Int]]
	/// The label a variant rebinds each member of `variantMadeAgain` as.
	public let variantMadeAgainLabels: [[String]]
	/// Whether each variant is called by exactly one call, a made-again call counted, and off every cycle.
	public let variantIsCalledOnce: [Bool]
	/// For each call of each variant, in edge order, where each answer it hands comes from: `none`, `passedThrough`, or
	/// `bound` with the answer's form.
	public let variantCallSources: [[[String]]]
	/// As `variantCallSources`, for each made-again call.
	public let variantMadeAgainCallSources: [[[String]]]
	/// The loop members whose parents' loops make different members again.
	public let loopMembersSharedApart: [Int]
	/// The parameters each variant's function takes for what its subtree reads from above (`TypeFactsWorld.parameters(of:)`).
	public let variantParameters: [[String]]

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
			line += " receives \(world.receives(of: declaration).count)"
			line += " reads [\(world.reads(of: declaration).map { "\(world.read($0).channel.name)" }.joined(separator: ", "))]"
			line += " labels \(Array(world.labels(of: declaration)))"
			lines.append(line)
			let madeAgain = world.madeAgain(from: declaration)
			if !madeAgain.isEmpty {
				lines.append("d\(index) makes again \(Array(madeAgain)) as labels \(Array(world.madeAgainLabels(from: declaration)))")
			}
		}
		if !world.loopMembersSharedApart.isEmpty {
			lines.append("loop members shared apart \(world.loopMembersSharedApart)")
		}
		lines.append("roots \((0..<world.rootCount).map(world.rootVariant))")
		for index in 0..<world.variantCount {
			let variant = VariantID(index)
			var line = "v\(index) d\(world.declaration(of: variant)) \(world.family(of: variant))"
			line += " keys [\(world.keys(of: variant).map { "\(world.answer($0).form) \(world.forms(of: $0).count)" }.joined(separator: ", "))]"
			let calls = world.calls(of: variant)
			let sources = calls.indices.map { index in
				let callee = world.declaration(of: calls[index])
				let described = zip(world.sources(ofCall: index - calls.startIndex, of: variant), world.reads(of: callee)).map { source, read in
					Self.description(of: source, read: read, beneath: callee, in: world)
				}
				return "\(described)"
			}
			line += " calls \(Array(calls)) sources [\(sources.joined(separator: ", "))]"
			line += world.isCalledOnce(variant) ? " once" : ""
			line += " outcomes \(world.outcomes(of: variant).map { "\($0)" }) bound before \(Array(world.boundBefore(of: variant)))"
			lines.append(line)
			let madeAgainCalls = world.madeAgainCalls(of: variant)
			if !madeAgainCalls.isEmpty {
				lines.append("v\(index) makes again \(Array(world.madeAgain(of: variant))) as \(Array(madeAgainCalls)) sources [\(madeAgainCalls.indices.map { "\(world.sources(ofMadeAgainCall: $0 - madeAgainCalls.startIndex, of: variant).map(\.kind))" }.joined(separator: ", "))]")
			}
		}
		return lines.joined(separator: "\n")
	}

	/// A call's source as the projection spells it: its kind, and for a bound answer its form, and whether it provides a
	/// form the callee's subtree reads where it does not.
	private static func description(of source: AnswerSource, read: ReadID, beneath callee: DeclarationID, in world: some TypeFactsWorld) -> String {
		switch source.kind {
		case .none, .passedThrough:
			"\(source.kind)"
		case .bound:
			"bound \(world.answer(source.answer).form)\(world.providesFormRead(by: source.answer, read, beneath: callee) ? "" : " not provided")"
		}
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
		case .declarationClosedOn, .cycleParameterContext, .cycleArgumentBinding:
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

extension Property {
	/// The property as `TypeDescription`'s `==` reads it: `any P` as `P`.
	fileprivate var spelledWithoutAny: String {
		Property(label: label, typeDescription: typeDescription.withoutAny).asSource
	}
}
