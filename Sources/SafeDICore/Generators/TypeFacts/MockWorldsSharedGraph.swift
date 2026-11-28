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

/// One graph over the shareable declarations of a module's mock worlds (`MockWorldsTable.isShareable(_:)`), built once
/// for the run: the facts of each shareable declaration that its own subtree decides, which every world that holds the
/// declaration would otherwise compute alike, each in its own graph.
///
/// A shareable declaration reaches no cycle, hole or fill, so what it reaches is shareable too, and its subtree is closed
/// downward. The graph is the forest of those subtrees: its roots are the shareable declarations that have a parent that
/// is not shareable, in the table's order, each walked as a world's graph walks its declarations (`OrderedGraph`,
/// `TypeFactsDeclaration.edges`), so its positions follow the table's order and no `Set` or `Dictionary` order. Its facts
/// are a world graph's per-declaration facts (`TypeFactsGraph.declarationFacts(of:edgeEntries:edgeIsFill:fillHoles:forMockGeneration:frontierRows:)`),
/// with interners of its own, frozen once built, and the reads each subtree makes from above it. Each world's top graph
/// stops at the shared declarations it reaches, its frontier, and copies their rows from here by value
/// (`frontierRows(ofNode:)`); its variants are found once for every world's calls into it (`variants(seededBy:)`), since
/// which body a world builds of a declaration depends on what the world answers its reads with.
///
/// Built beside the table, on one task, before the mock worlds are built, and never changed, so parallel tasks only read
/// it. It holds the table, the forest's declarations, its columns and its interners' values for as long as
/// `generateMockCode` keeps it: one run's mock generation.
struct MockWorldsSharedGraph: Sendable {
	init(table: MockWorldsTable) {
		// The roots: each shareable declaration that a declaration that is not shareable leads to, in table order.
		var hasUnshareableParent = [Bool](repeating: false, count: table.declarationCount)
		for declaration in 0..<Int32(table.declarationCount) where !table.isShareable(declaration) {
			for target in table.edges(of: declaration) where table.isShareable(target) {
				hasUnshareableParent[Int(target)] = true
			}
		}
		let roots = hasUnshareableParent.indices.filter { hasUnshareableParent[$0] }.map { table.declaration(ofID: Int32($0)) }
		var edgeEntries = [Int32]()
		var edgeIsFill = [Bool]()
		var fillHoles = [(edge: Int32, hole: SeamSignature.Hole)]()
		let graph = OrderedGraph(roots: roots) { declaration in
			let edges = declaration.edges
			for edge in edges {
				if let filledHole = edge.filledHole {
					fillHoles.append((Int32(edgeEntries.count), filledHole))
				}
				edgeEntries.append(edge.entry)
				edgeIsFill.append(edge.filledHole != nil)
			}
			return edges.map(\.target)
		}
		let facts = TypeFactsGraph.declarationFacts(of: graph, edgeEntries: edgeEntries, edgeIsFill: edgeIsFill, fillHoles: fillHoles, forMockGeneration: true)
		let reads = ReadsFromAbove(graph: graph, own: facts.own, hidden: facts.hidden)
		var nodeByDeclaration = [Int32](repeating: -1, count: table.declarationCount)
		var declarations = [Int32]()
		for (index, node) in graph.nodes.enumerated() {
			// The table holds every declaration a world holds, and every shareable one is a node here.
			let declaration = table.declarationID(of: node) ?? -1
			declarations.append(declaration)
			if declaration >= 0 {
				nodeByDeclaration[Int(declaration)] = Int32(index)
			}
		}
		// Identity finds a read's ID and orders nothing.
		var readIDByValue = [ReadValue: Int32](minimumCapacity: facts.readInterner.values.count)
		for (id, read) in facts.readInterner.values.enumerated() {
			readIDByValue[ReadValue(read, labels: facts.labels.values)] = Int32(id)
		}
		self.table = table
		self.graph = graph
		self.facts = facts
		self.reads = reads
		self.declarations = declarations
		self.nodeByDeclaration = nodeByDeclaration
		self.readIDByValue = readIDByValue
	}

	/// The table the graph is built over.
	let table: MockWorldsTable
	/// The forest, in the order its walk from each root in turn first reaches each declaration.
	let graph: OrderedGraph<TypeFactsDeclaration>
	let facts: TypeFactsGraph.DeclarationFacts
	/// What each node's subtree reads from above it, by the graph's read IDs.
	let reads: ReadsFromAbove

	/// The table's ID of each of the graph's declarations, in the graph's order.
	let declarations: [Int32]

	/// The graph's position of `declaration`, where it is a shareable declaration of the table; `nil` for any other.
	func node(of declaration: TypeFactsDeclaration) -> Int32? {
		guard let id = table.declarationID(of: declaration) else { return nil }
		let node = nodeByDeclaration[Int(id)]
		return node >= 0 ? node : nil
	}

	/// The rows of the node at `index` by value: what a world's top graph holds for it where it is a frontier.
	func frontierRows(ofNode index: Int) -> TypeFactsFrontierRows {
		let properties = facts.properties.values
		let types = facts.types.values
		return TypeFactsFrontierRows(
			required: facts.receives.required.columns(inRow: index).map { properties[Int($0)] },
			onlyIfAvailable: facts.onlyIfAvailableRows.columns(inRow: index).map { properties[Int($0)] },
			onlyIfAvailableUnwrappedIncludingRequired: facts.onlyIfAvailableUnwrappedIncludingRequired.columns(inRow: index).map { properties[Int($0)] },
			requiredAliasFulfilling: facts.receives.requiredAliasFulfilling.columns(inRow: index).map { properties[Int($0)] },
			typesBeneath: facts.typesBeneath.columns(inRow: index).map { types[Int($0)] },
			typesDeclaredEscaping: facts.typesDeclaredEscaping.columns(inRow: index).map { types[Int($0)] },
			reads: reads.rows.columns(inRow: index).map { ReadValue(facts.readInterner.values[Int($0)], labels: facts.labels.values) },
		)
	}

	/// The graph's read ID of `read`, which a node's subtree reads.
	func readID(of read: ReadValue) -> Int32? {
		readIDByValue[read]
	}

	/// The variants of the graph's bodies that every world's calls into it start, `entries` in the order the worlds first
	/// make them: mock roots in the order the module lowers them, each world's calls in its worklist's order.
	func variants(seededBy entries: [MockWorldsSharedEntry]) -> MockWorldsSharedVariants {
		var answers = [TypeFactsGraph.VariantSeeding.Answer]()
		// Identity numbers an answer by its first entry and orders nothing.
		var answerIndexByAnswer = [TypeFactsGraph.VariantSeeding.Answer: Int32]()
		let seeds = entries.map { entry in
			TypeFactsVariants.Seed(node: entry.node, family: entry.family, keys: entry.keys.map { key in
				switch key {
				case let .constant(constant):
					return constant
				case let .answer(answer):
					if let index = answerIndexByAnswer[answer] {
						return index
					}
					let index = Int32(answers.count)
					answerIndexByAnswer[answer] = index
					answers.append(answer)
					return index
				}
			})
		}
		let answered = TypeFactsGraph.answers(
			of: graph,
			reads: reads,
			readTable: facts.readInterner.values,
			labels: facts.labels,
			bindings: facts.bindings,
			bindingOffsets: facts.bindingOffsets,
			bindingsBefore: facts.bindingsBefore,
			properties: facts.properties,
			seeding: TypeFactsGraph.VariantSeeding(answers: answers, seeds: seeds),
		)
		return MockWorldsSharedVariants(variants: answered.variants)
	}

	/// Each table declaration's position in the graph, or -1 for one it does not hold.
	private let nodeByDeclaration: [Int32]
	private let readIDByValue: [ReadValue: Int32]

	/// The facts of the table's declaration `declaration`, a shareable one, as the observer compares them; `nil` for one
	/// the graph does not hold.
	func projection(ofDeclaration declaration: Int32) -> MockWorldsDeclarationProjection? {
		let node = nodeByDeclaration[Int(declaration)]
		guard node >= 0 else { return nil }
		return columns.projection(ofNode: Int(node), declarationByNode: declarations)
	}

	private var columns: MockWorldsFactsColumns {
		MockWorldsFactsColumns(
			graph: graph,
			kinds: facts.kinds,
			constructions: facts.constructions,
			nodeProperties: facts.nodeProperties,
			builtTypes: facts.builtTypes,
			edgeFacts: facts.edgeFacts,
			bindings: facts.bindings,
			bindingOffsets: facts.bindingOffsets,
			receives: facts.receives,
			typesBeneath: facts.typesBeneath,
			typesDeclaredEscaping: facts.typesDeclaredEscaping,
			reads: reads.rows,
			readTable: facts.readInterner.values,
			labelTexts: facts.labels.values,
			propertyTable: facts.properties.values,
			typeTable: facts.types.values,
			moduleNames: facts.modules.values,
			declarationLocations: facts.locations.values,
		)
	}
}

/// The variants of the mock worlds' shared graph, found once from every world's calls into it, in the order the worlds
/// make them (`MockWorldsSharedGraph.variants(seededBy:)`): a variant's ID is its position in that worklist. Built on one
/// task after every world's top graph and before any world's records, and held for as long as `MockWorlds.build` runs.
struct MockWorldsSharedVariants: Sendable {
	let variants: TypeFactsVariants

	/// The shared variant each entry is, in the order of the entries.
	var variantOfEntry: [Int32] {
		variants.seedVariants
	}
}

/// A world's call into the shared graph: the shared declaration it calls, by the graph's position, the family it builds
/// it in, and its key of each read of the declaration's reads from above, in the shared graph's read order, by value.
struct MockWorldsSharedEntry: Hashable, Sendable {
	enum Key: Hashable, Sendable {
		/// A key that is no answer: none, or a parameter rule's.
		case constant(Int32)
		/// An answer, by its key text and what it declares.
		case answer(TypeFactsGraph.VariantSeeding.Answer)
	}

	let node: Int32
	let family: VariantFamily
	let keys: [Key]
}

/// A read by value: its channel and the text of the label it asks about, `nil` for a read of no label.
struct ReadValue: Hashable, Sendable {
	init(_ read: Read, labels: [String]) {
		channel = read.channel
		label = read.label >= 0 ? labels[Int(read.label)] : nil
	}

	let channel: ReadChannel
	let label: String?
}

/// What a world's top graph holds of a frontier, a shareable declaration its own graph does not walk beneath: the
/// shared graph's rows of its subtree, by value, each in the shared graph's order.
struct TypeFactsFrontierRows: Sendable {
	let required: [Property]
	let onlyIfAvailable: [Property]
	let onlyIfAvailableUnwrappedIncludingRequired: [Property]
	let requiredAliasFulfilling: [Property]
	let typesBeneath: [TypeDescription]
	let typesDeclaredEscaping: [TypeDescription]
	let reads: [ReadValue]
}

/// The columns of a graph of declarations that the observer of the mock worlds' shared graph projects: a world's graph
/// (`TypeFactsGraph`) or the shared graph (`MockWorldsSharedGraph`), each by its own positions and interners. It holds
/// what its graph holds, for as long as its owner keeps it.
struct MockWorldsFactsColumns: Sendable {
	let graph: OrderedGraph<TypeFactsDeclaration>
	let kinds: [TypeFactsKind]
	let constructions: [TypeFactsConstruction]
	let nodeProperties: [Int32]
	let builtTypes: [Int32]
	let edgeFacts: [TypeFactsEdge]
	let bindings: [TypeFactsWorldBinding]
	let bindingOffsets: [Int32]
	let receives: TypeFactsReceives
	let typesBeneath: BitRows
	let typesDeclaredEscaping: BitRows
	let reads: BitRows
	let readTable: [Read]
	let labelTexts: [String]
	let propertyTable: [Property]
	let typeTable: [TypeDescription]
	let moduleNames: [String]
	let declarationLocations: [Dependency.DeclarationLocation]

	/// The facts of the node at `index` by value, its edges' targets by the table's IDs in `declarationByNode`.
	func projection(ofNode index: Int, declarationByNode: [Int32]) -> MockWorldsDeclarationProjection {
		let edges = edgeFacts[graph.edgeIndices(from: index)].map { edge in
			MockWorldsDeclarationProjection.Edge(
				target: declarationByNode[Int(edge.child)],
				buildPosition: edge.buildPosition,
				loop: edge.loop,
				opens: edge.opens,
				isFill: edge.isFill,
				bindingsBefore: edge.bindingsBefore,
			)
		}
		let bindings = bindings[Int(bindingOffsets[index])..<Int(bindingOffsets[index + 1])].map { binding in
			MockWorldsDeclarationProjection.Binding(
				label: labelTexts[Int(binding.label)],
				property: propertyTable[Int(binding.property)],
				declaringType: typeTable[Int(binding.declaringType)],
				declarationLocation: binding.declarationLocation >= 0 ? declarationLocations[Int(binding.declarationLocation)] : nil,
				declaringModule: binding.declaringModule >= 0 ? moduleNames[Int(binding.declaringModule)] : nil,
				isReceivedOnlyIfAvailable: binding.isReceivedOnlyIfAvailable,
				isReboundByBuilderFunction: binding.isReboundByBuilderFunction,
				isForwarded: binding.isForwarded,
			)
		}
		func properties(_ rows: BitRows) -> [Property] {
			rows.columns(inRow: index).map { propertyTable[Int($0)] }.sorted()
		}
		func types(_ rows: BitRows) -> [TypeDescription] {
			rows.columns(inRow: index).map { typeTable[Int($0)] }.sorted()
		}
		let property = nodeProperties[index] >= 0 ? propertyTable[Int(nodeProperties[index])] : nil
		return MockWorldsDeclarationProjection(
			kind: kinds[index],
			construction: constructions[index],
			property: property,
			builtType: typeTable[Int(builtTypes[index])],
			edges: edges,
			bindings: bindings,
			reads: reads.columns(inRow: index).map { readTable[Int($0)].description(labels: labelTexts) }.sorted(),
			received: properties(receives.received),
			required: properties(receives.required),
			onlyIfAvailableUnwrapped: properties(receives.onlyIfAvailableUnwrapped),
			requiredAliasFulfilling: properties(receives.requiredAliasFulfilling),
			typesBeneath: types(typesBeneath),
			typesDeclaredEscaping: types(typesDeclaredEscaping),
		)
	}
}

extension TypeFactsGraph {
	/// The world's columns the observer of the mock worlds' shared graph projects.
	var sharedFactsColumns: MockWorldsFactsColumns {
		MockWorldsFactsColumns(
			graph: graph,
			kinds: kinds,
			constructions: constructions,
			nodeProperties: nodeProperties,
			builtTypes: builtTypes,
			edgeFacts: edgeFacts,
			bindings: bindings,
			bindingOffsets: bindingOffsets,
			receives: receives,
			typesBeneath: typesBeneath,
			typesDeclaredEscaping: typesDeclaredEscaping,
			reads: reads.rows,
			readTable: readTable,
			labelTexts: labelTexts,
			propertyTable: propertyTable,
			typeTable: typeTable,
			moduleNames: moduleNames,
			declarationLocations: declarationLocations,
		)
	}
}

/// A declaration's facts that its own subtree decides, by value, so that two graphs that number them apart compare
/// alike: its kind, construction, property and built type; its edges, each by the table's ID of its target, with its
/// build position, loop, function opened, whether it is a fill and the bindings before it; its bindings by label text and
/// property; its subtree's reads from above as text, sorted; and its subtree's four receive rows and two type rows, each
/// sorted.
struct MockWorldsDeclarationProjection: Equatable, Sendable {
	struct Edge: Equatable, Sendable {
		let target: Int32
		let buildPosition: Int32
		let loop: Int32
		let opens: TypeFactsFunctionOpened
		let isFill: Bool
		let bindingsBefore: Int32
	}

	struct Binding: Equatable, Sendable {
		let label: String
		let property: Property
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		let declaringModule: String?
		let isReceivedOnlyIfAvailable: Bool
		let isReboundByBuilderFunction: Bool
		let isForwarded: Bool
	}

	let kind: TypeFactsKind
	let construction: TypeFactsConstruction
	let property: Property?
	let builtType: TypeDescription
	let edges: [Edge]
	let bindings: [Binding]
	let reads: [String]
	let received: [Property]
	let required: [Property]
	let onlyIfAvailableUnwrapped: [Property]
	let requiredAliasFulfilling: [Property]
	let typesBeneath: [TypeDescription]
	let typesDeclaredEscaping: [TypeDescription]

	/// The names of the facts in which `other` differs from this, in the order this declares them.
	func differingFacts(from other: Self) -> [String] {
		var facts = [String]()
		if kind != other.kind {
			facts.append("kind")
		}
		if construction != other.construction {
			facts.append("construction")
		}
		if property != other.property {
			facts.append("property")
		}
		if builtType != other.builtType {
			facts.append("built type")
		}
		if edges != other.edges {
			facts.append("edges")
		}
		if bindings != other.bindings {
			facts.append("bindings")
		}
		if reads != other.reads {
			facts.append("reads")
		}
		if received != other.received {
			facts.append("received")
		}
		if required != other.required {
			facts.append("required")
		}
		if onlyIfAvailableUnwrapped != other.onlyIfAvailableUnwrapped {
			facts.append("only if available unwrapped")
		}
		if requiredAliasFulfilling != other.requiredAliasFulfilling {
			facts.append("required through alias")
		}
		if typesBeneath != other.typesBeneath {
			facts.append("types beneath")
		}
		if typesDeclaredEscaping != other.typesDeclaredEscaping {
			facts.append("types declared escaping")
		}
		return facts
	}
}
