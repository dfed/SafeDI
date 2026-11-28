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

/// A mock world as its node records read it (`NodeRecordSources`), in its own graph's dense numbering, assembled from its
/// top graph (`TypeFactsGraph(root:forMockGeneration:sharedBelow:)`) and the mock worlds' shared graph
/// (`MockWorldsSharedGraph`), with no fact computed again: two walks over integers number its declarations depth first
/// from its root, as its own graph's walk would (`OrderedGraph`), and its variants by the worklist's order
/// (`TypeFactsVariants`), and each fact is copied from the graph that holds it, its declarations and calls renumbered.
/// A declaration's reads keep the order the world's own graph gives them, its read IDs interned in declaration order
/// from what each declaration reads itself, so its reads, the keys its callers hand and the sources of each call are in
/// one order, as the layout reads them.
///
/// A transitional view: its columns grow with the whole world. It is built only for a world that is not clean
/// (`MockWorlds`), one that reaches a shared variant that is no row, or a shared declaration or frontier in two variants,
/// whose node records and refusals it reads, and, where a test observes the table, compared with the world's graph built
/// whole. It holds its columns for as long as its world is being built (`MockWorlds.build`).
struct MockWorldGraph: NodeRecordSources, Sendable {
	/// - Parameters:
	///   - top: The world's top graph, or its whole graph where `shared` is `nil`.
	///   - shared: The shared graph whose frontier `top` stops at, its variants, and the shared variant of each of `top`'s
	///     variants whose declaration is a frontier, -1 for each other.
	///   - table: The mock worlds' table, which names each declaration.
	init(top: TypeFactsGraph, shared: Shared?, table: MockWorldsTable) {
		func sharedNode(ofTopNode node: Int32) -> Int32 {
			top.sharedNodeByNode.isEmpty ? -1 : top.sharedNodeByNode[Int(node)]
		}
		func origin(ofTopNode node: Int32) -> Origin {
			let sharedNode = sharedNode(ofTopNode: node)
			return sharedNode >= 0 ? Origin(isShared: true, node: sharedNode) : Origin(isShared: false, node: node)
		}
		let graph = OrderedGraph(root: Origin(isShared: false, node: 0)) { origin in
			if origin.isShared, let shared {
				return shared.graph.graph.edges(from: Int(origin.node)).map { Origin(isShared: true, node: $0) }
			}
			return top.graph.edges(from: Int(origin.node)).map(origin(ofTopNode:))
		}
		// Identity finds a node's dense position and orders nothing.
		var denseByOrigin = [Origin: Int32](minimumCapacity: graph.nodes.count)
		for (index, origin) in graph.nodes.enumerated() {
			denseByOrigin[origin] = Int32(index)
		}
		func declaration(of origin: Origin) -> TypeFactsDeclaration {
			if origin.isShared, let shared {
				return shared.graph.graph.nodes[Int(origin.node)]
			}
			return top.graph.nodes[Int(origin.node)]
		}
		declarations = graph.nodes.map(declaration(of:))
		kinds = graph.nodes.map { origin in
			if origin.isShared, let shared {
				return shared.graph.facts.kinds[Int(origin.node)]
			}
			return top.kinds[Int(origin.node)]
		}
		constructions = graph.nodes.map { origin in
			if origin.isShared, let shared {
				return shared.graph.facts.constructions[Int(origin.node)]
			}
			return top.constructions[Int(origin.node)]
		}
		tableDeclarations = graph.nodes.map { origin in
			if origin.isShared, let shared {
				return shared.graph.declarations[Int(origin.node)]
			}
			// The table holds every declaration a world holds.
			return table.declarationID(of: top.graph.nodes[Int(origin.node)]) ?? -1
		}
		edgeFacts = Self.edgeFacts(of: graph, top: top, shared: shared)
		// A loop of builders is wholly the top graph's or wholly the shared graph's (`MockWorldsTable.isShareable`): its
		// members and the declarations that make them again are of one graph, which says what each makes again.
		var madeAgainOffsets: [Int32] = [0]
		var madeAgainTargets = [Int32]()
		for node in graph.nodes {
			if node.isShared, let shared {
				madeAgainTargets += (shared.graph.facts.madeAgain?.targets(of: Int(node.node)) ?? []).map { denseByOrigin[Origin(isShared: true, node: $0)] ?? -1 }
			} else {
				madeAgainTargets += top.madeAgain(from: DeclarationID(node.node)).map { denseByOrigin[origin(ofTopNode: $0)] ?? -1 }
			}
			madeAgainOffsets.append(Int32(madeAgainTargets.count))
		}
		self.madeAgainOffsets = madeAgainOffsets
		self.madeAgainTargets = madeAgainTargets
		// In the dense view's order, as the world's graph lists them: a shared member the world does not reach is no member
		// of its loops.
		var isSharedApart = [Bool](repeating: false, count: graph.nodes.count)
		let membersSharedApart = top.loopMembersSharedApart.map(origin(ofTopNode:)) + (shared?.graph.facts.loopMembersSharedApart ?? []).map { Origin(isShared: true, node: $0) }
		for member in membersSharedApart {
			if let dense = denseByOrigin[member] {
				isSharedApart[Int(dense)] = true
			}
		}
		loopMembersSharedApart = isSharedApart.indices.filter { isSharedApart[$0] }.map(Int32.init)
		parentOffsetsAndParents = Self.parents(of: graph, edgeFacts: edgeFacts, top: top, shared: shared)
		let reads = Self.reads(of: graph, top: top, shared: shared)
		readTable = reads.readTable
		labelTexts = reads.labelTexts
		readColumn = reads.column
		readOffsets = reads.offsets
		variants = Self.variants(top: top, shared: shared, denseByOrigin: denseByOrigin, origin: origin(ofTopNode:), reads: reads)
		self.graph = graph
	}

	/// The shared graph a top graph stops at, its variants, and the shared variant of each of the top graph's variants
	/// whose declaration is a frontier, -1 for each other.
	struct Shared: Sendable {
		let graph: MockWorldsSharedGraph
		let variants: MockWorldsSharedVariants
		let variantOfTopVariant: [Int32]
	}

	/// The graph a dense declaration's facts come from, and its position there.
	private struct Origin: Hashable, Sendable {
		let isShared: Bool
		let node: Int32
	}

	var declarationCount: Int {
		graph.nodes.count
	}

	func kind(of declaration: DeclarationID) -> TypeFactsKind {
		kinds[Int(declaration)]
	}

	func construction(of declaration: DeclarationID) -> TypeFactsConstruction {
		constructions[Int(declaration)]
	}

	func isOnCycle(_ declaration: DeclarationID) -> Bool {
		graph.isOnCycle(Int(declaration))
	}

	func edges(from declaration: DeclarationID) -> ArraySlice<Int32> {
		graph.edges(from: Int(declaration))
	}

	func edgeFacts(from declaration: DeclarationID) -> ArraySlice<TypeFactsEdge> {
		edgeFacts[graph.edgeIndices(from: Int(declaration))]
	}

	func parents(of declaration: DeclarationID) -> ArraySlice<TypeFactsParent> {
		let offsets = parentOffsetsAndParents.offsets
		return parentOffsetsAndParents.parents[Int(offsets[Int(declaration)])..<Int(offsets[Int(declaration) + 1])]
	}

	func madeAgain(from declaration: DeclarationID) -> ArraySlice<Int32> {
		madeAgainTargets[Int(madeAgainOffsets[Int(declaration)])..<Int(madeAgainOffsets[Int(declaration) + 1])]
	}

	let loopMembersSharedApart: [Int32]

	func owedFacts(of declaration: DeclarationID) -> TypeFactsOwedFacts {
		TypeFactsGraph.owedFacts(
			of: declaration,
			isMockWorld: true,
			parents: parents(of:),
			isFill: { declarations[Int($0)].key.isFill },
		)
	}

	func reads(of declaration: DeclarationID) -> ArraySlice<ReadID> {
		readColumn[Int(readOffsets[Int(declaration)])..<Int(readOffsets[Int(declaration) + 1])]
	}

	func read(_ read: ReadID) -> Read {
		readTable[Int(read)]
	}

	var variantCount: Int {
		variants.declarations.count
	}

	func declaration(of variant: VariantID) -> DeclarationID {
		variants.declarations[Int(variant)]
	}

	func calls(of variant: VariantID) -> ArraySlice<VariantID> {
		variants.callees[Int(variants.callOffsets[Int(variant)])..<Int(variants.callOffsets[Int(variant) + 1])]
	}

	func sources(ofCall edgeIndex: Int, of variant: VariantID) -> ArraySlice<AnswerSource> {
		let call = Int(variants.callOffsets[Int(variant)]) + edgeIndex
		return variants.sources[Int(variants.sourceOffsets[call])..<Int(variants.sourceOffsets[call + 1])]
	}

	func scope(of declaration: DeclarationID) -> ConstructionScope {
		declarations[Int(declaration)].scope
	}

	func property(of declaration: DeclarationID) -> Property? {
		declarations[Int(declaration)].property
	}

	func isErased(_ declaration: DeclarationID) -> Bool {
		declarations[Int(declaration)].key.erasedToConcreteExistential
	}

	func text(ofLabel label: WorldLabelID) -> String {
		labelTexts[Int(label)]
	}

	/// The read by value.
	func value(ofRead read: ReadID) -> ReadValue {
		ReadValue(readTable[Int(read)], labels: labelTexts)
	}

	var isMockWorld: Bool {
		true
	}

	/// The table's ID of each declaration, by its dense position.
	let tableDeclarations: [Int32]

	/// The dense numbering's walk, whose nodes name the graph each declaration's facts come from.
	private let graph: OrderedGraph<Origin>
	private let declarations: [TypeFactsDeclaration]
	private let kinds: [TypeFactsKind]
	private let constructions: [TypeFactsConstruction]
	/// Each edge's facts, parallel to `graph.edgeTargets`, its child by dense position.
	private let edgeFacts: [TypeFactsEdge]
	private let parentOffsetsAndParents: (offsets: [Int32], parents: [TypeFactsParent])
	/// The members each declaration makes again, by dense position, one run per declaration.
	private let madeAgainOffsets: [Int32]
	private let madeAgainTargets: [Int32]
	private let readTable: [Read]
	private let labelTexts: [String]
	/// Each declaration's reads from above, by dense read ID in increasing order, one run per declaration.
	private let readColumn: [Int32]
	private let readOffsets: [Int32]
	private let variants: Variants

	/// The variants' columns: each variant's declaration, and for each of its calls the callee and
	/// the run of sources, in the callee's dense read order.
	private struct Variants: Sendable {
		var declarations = [Int32]()
		var callOffsets = [Int32]()
		var callees = [Int32]()
		var sourceOffsets = [Int32]()
		var sources = [AnswerSource]()
	}

	/// The dense reads: their table, the labels they ask about, and each declaration's run.
	private struct Reads {
		var readTable = [Read]()
		var labelTexts = [String]()
		var column = [Int32]()
		var offsets = [Int32]()
		/// Each dense read's ID, by value.
		var readIDByValue = [ReadValue: Int32]()
	}

	/// Each edge's facts from the graph that holds its source, its child renumbered.
	private static func edgeFacts(of graph: OrderedGraph<Origin>, top: TypeFactsGraph, shared: Shared?) -> [TypeFactsEdge] {
		var edgeFacts = [TypeFactsEdge]()
		edgeFacts.reserveCapacity(graph.edgeCount)
		for (index, origin) in graph.nodes.enumerated() {
			let originFacts = if origin.isShared, let shared {
				shared.graph.facts.edgeFacts[shared.graph.graph.edgeIndices(from: Int(origin.node))]
			} else {
				top.edgeFacts(from: Int(origin.node))
			}
			for (target, fact) in zip(graph.edges(from: index), originFacts) {
				edgeFacts.append(TypeFactsEdge(child: target, buildPosition: fact.buildPosition, loop: fact.loop, opens: fact.opens, isFill: fact.isFill, bindingsBefore: fact.bindingsBefore, isCallEdge: fact.isCallEdge))
			}
		}
		return edgeFacts
	}

	/// The parents of each declaration, in the order the walk meets each edge, as the world's own graph gives them: each
	/// with the offset of its parent's bindings among every declaration's, in dense order, and the bindings before its edge.
	private static func parents(of graph: OrderedGraph<Origin>, edgeFacts: [TypeFactsEdge], top: TypeFactsGraph, shared: Shared?) -> (offsets: [Int32], parents: [TypeFactsParent]) {
		var bindingOffsets = [Int32]()
		var bindingCount: Int32 = 0
		for origin in graph.nodes {
			bindingOffsets.append(bindingCount)
			let offsets = if origin.isShared, let shared {
				shared.graph.facts.bindingOffsets
			} else {
				top.bindingOffsets
			}
			bindingCount += offsets[Int(origin.node) + 1] - offsets[Int(origin.node)]
		}
		var parentCounts = [Int32](repeating: 0, count: graph.nodes.count + 1)
		for edge in 0..<graph.edgeCount {
			parentCounts[Int(graph.edgeTargets[edge]) + 1] += 1
		}
		for index in graph.nodes.indices {
			parentCounts[index + 1] += parentCounts[index]
		}
		var parentSlots = parentCounts
		var parents = [TypeFactsParent](repeating: TypeFactsParent(parent: -1, segmentStart: 0, segmentCount: 0), count: graph.edgeCount)
		for index in graph.nodes.indices {
			for edge in graph.edgeIndices(from: index) {
				let target = Int(graph.edgeTargets[edge])
				parents[Int(parentSlots[target])] = TypeFactsParent(parent: Int32(index), segmentStart: bindingOffsets[index], segmentCount: edgeFacts[edge].bindingsBefore)
				parentSlots[target] += 1
			}
		}
		return (parentCounts, parents)
	}

	/// The dense reads: each read ID in the order the world's own graph interns them, what each declaration reads itself
	/// in dense order, and each declaration's reads from above in increasing dense ID.
	private static func reads(of graph: OrderedGraph<Origin>, top: TypeFactsGraph, shared: Shared?) -> Reads {
		var reads = Reads()
		var labelIDByText = [String: Int32]()
		for origin in graph.nodes {
			for value in ownReads(of: origin, top: top, shared: shared) where reads.readIDByValue[value] == nil {
				reads.readIDByValue[value] = Int32(reads.readTable.count)
				var label: Int32 = -1
				if let text = value.label {
					if let existing = labelIDByText[text] {
						label = existing
					} else {
						label = Int32(reads.labelTexts.count)
						labelIDByText[text] = label
						reads.labelTexts.append(text)
					}
				}
				reads.readTable.append(Read(value.channel, label: label))
			}
		}
		for origin in graph.nodes {
			reads.offsets.append(Int32(reads.column.count))
			// Every read from above is one a declaration beneath reads itself, so each is interned above.
			reads.column += readsFromAbove(of: origin, top: top, shared: shared).compactMap { reads.readIDByValue[$0] }.sorted()
		}
		reads.offsets.append(Int32(reads.column.count))
		return reads
	}

	/// What the declaration reads itself, by value, in the order it reads them.
	private static func ownReads(of origin: Origin, top: TypeFactsGraph, shared: Shared?) -> [ReadValue] {
		if origin.isShared, let shared {
			return shared.graph.facts.ownReadsByNode[Int(origin.node)].map { ReadValue(shared.graph.facts.readInterner.values[Int($0)], labels: shared.graph.facts.labels.values) }
		}
		return top.ownReads(of: Int(origin.node)).map { ReadValue(top.readTable[Int($0)], labels: top.labelTexts) }
	}

	/// What the declaration's subtree reads from above it, by value, in its origin graph's read order.
	private static func readsFromAbove(of origin: Origin, top: TypeFactsGraph, shared: Shared?) -> [ReadValue] {
		if origin.isShared, let shared {
			return shared.graph.reads.rows.columns(inRow: Int(origin.node)).map { ReadValue(shared.graph.facts.readInterner.values[Int($0)], labels: shared.graph.facts.labels.values) }
		}
		return top.reads.rows.columns(inRow: Int(origin.node)).map { ReadValue(top.readTable[Int($0)], labels: top.labelTexts) }
	}

	/// The variants in the order the world's own worklist makes them: from the root's, each variant's calls in edge order,
	/// then its made-again calls, a callee met first made next. A top variant whose declaration is a frontier is its shared
	/// variant. Only the top graph's variants make calls again: every loop is the top graph's. The view keeps no made-again
	/// call, which no record reads, but makes its callee where the worklist makes it.
	private static func variants(top: TypeFactsGraph, shared: Shared?, denseByOrigin: [Origin: Int32], origin: (Int32) -> Origin, reads: Reads) -> Variants {
		var variants = Variants()
		var origins: [(isShared: Bool, variant: Int32)] = [(false, 0)]
		var viewVariantOfTopVariant = [Int32](repeating: -1, count: top.variantCount)
		viewVariantOfTopVariant[0] = 0
		// Identity finds a shared variant's view variant and orders nothing.
		var viewVariantOfSharedVariant = [Int32: Int32]()
		/// The dense ranks of `values`, reads of the dense declaration `declaration`'s reads from above.
		func ranks(of values: [ReadValue], inReadsOf declaration: Int32) -> [Int32] {
			let row = reads.column[Int(reads.offsets[Int(declaration)])..<Int(reads.offsets[Int(declaration) + 1])]
			return values.map { value in
				let id = reads.readIDByValue[value] ?? -1
				return Int32((row.firstIndex(of: id) ?? row.startIndex) - row.startIndex)
			}
		}
		func viewVariant(isShared: Bool, variant: Int32) -> Int32 {
			if isShared, let existing = viewVariantOfSharedVariant[variant] {
				return existing
			}
			if !isShared, viewVariantOfTopVariant[Int(variant)] >= 0 {
				return viewVariantOfTopVariant[Int(variant)]
			}
			let made = Int32(origins.count)
			origins.append((isShared, variant))
			if isShared {
				viewVariantOfSharedVariant[variant] = made
			} else {
				viewVariantOfTopVariant[Int(variant)] = made
			}
			return made
		}
		var next = 0
		while next < origins.count {
			let (isShared, variant) = origins[next]
			next += 1
			// The caller's dense declaration, its origin's calls, and for each call its callee, its sources, and the reads
			// their positions follow in the origin graph: the caller's and the callee's.
			var calls = [(callee: Int32, sources: ArraySlice<AnswerSource>, calleeReads: [ReadValue], calleeDeclaration: Int32)]()
			let callerDeclaration: Int32
			let callerReads: [ReadValue]
			if isShared, let shared {
				let sharedVariants = shared.variants.variants
				let node = sharedVariants.node(of: Int(variant))
				let callerOrigin = Origin(isShared: true, node: node)
				callerDeclaration = denseByOrigin[callerOrigin] ?? -1
				callerReads = readsFromAbove(of: callerOrigin, top: top, shared: shared)
				for (edgeIndex, callee) in sharedVariants.callees(of: Int(variant)).enumerated() {
					let calleeOrigin = Origin(isShared: true, node: sharedVariants.node(of: Int(callee)))
					calls.append((
						viewVariant(isShared: true, variant: callee),
						sharedVariants.sources(ofCall: sharedVariants.callOffset(of: Int(variant)) + edgeIndex),
						readsFromAbove(of: calleeOrigin, top: top, shared: shared),
						denseByOrigin[calleeOrigin] ?? -1,
					))
				}
				for callee in sharedVariants.madeAgainCallees(of: Int(variant)) {
					_ = viewVariant(isShared: true, variant: callee)
				}
			} else {
				let node = top.declaration(of: variant)
				callerDeclaration = denseByOrigin[origin(node)] ?? -1
				callerReads = readsFromAbove(of: Origin(isShared: false, node: node), top: top, shared: shared)
				for (edgeIndex, callee) in top.calls(of: variant).enumerated() {
					let calleeNode = top.declaration(of: callee)
					let calleeOrigin = origin(calleeNode)
					let viewCallee = if calleeOrigin.isShared, let shared {
						viewVariant(isShared: true, variant: shared.variantOfTopVariant[Int(callee)])
					} else {
						viewVariant(isShared: false, variant: callee)
					}
					calls.append((
						viewCallee,
						top.sources(ofCall: edgeIndex, of: variant),
						readsFromAbove(of: Origin(isShared: false, node: calleeNode), top: top, shared: shared),
						denseByOrigin[calleeOrigin] ?? -1,
					))
				}
				for callee in top.madeAgainCalls(of: variant) {
					_ = viewVariant(isShared: false, variant: callee)
				}
			}
			variants.declarations.append(callerDeclaration)
			variants.callOffsets.append(Int32(variants.callees.count))
			let callerRanks = ranks(of: callerReads, inReadsOf: callerDeclaration)
			for call in calls {
				variants.callees.append(call.callee)
				variants.sourceOffsets.append(Int32(variants.sources.count))
				var sources = [AnswerSource](repeating: .none, count: call.calleeReads.count)
				for (source, rank) in zip(call.sources, ranks(of: call.calleeReads, inReadsOf: call.calleeDeclaration)) {
					sources[Int(rank)] = switch source.kind {
					case .none:
						.none
					case .bound:
						// The view carries no answer ID: each graph interns its own.
						// A bound source names a declaration of the caller's origin graph.
						.bound(denseByOrigin[isShared ? Origin(isShared: true, node: source.payload) : origin(source.payload)] ?? -1, answer: -1)
					case .passedThrough:
						.passedThrough(callerRanks[Int(source.payload)])
					}
				}
				variants.sources += sources
			}
		}
		variants.callOffsets.append(Int32(variants.callees.count))
		variants.sourceOffsets.append(Int32(variants.sources.count))
		return variants
	}
}
