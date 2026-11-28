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

import Foundation

/// One mock root's world, built once before the module's mock roots are lowered (`MockWorlds`) and handed to its root's
/// lowering (`ScopeGenerator.nodeRecordsMockStatements(of:world:bindsOnlyNodes:)`). It holds the world's node records,
/// which hold the table's shared records where the world holds their rows, and the table, from which the layout reads
/// a node's row (`MockWorldsTable.sharedRecordID(of:)`), for as long as the root's lowering keeps it.
struct MockWorld: Sendable {
	/// The world's node records, or why they refused it.
	let records: Result<NodeRecords, NodeRecordRefusal>
	/// Every refusal the world holds where its records were refused, each once (`NodeRecords.refusals(in:declaredTypeNames:)`),
	/// or `[.recordsThrew]` where making them threw something else: what a test reports of the world.
	let everyRefusal: [NodeRecordRefusal]
	/// The table the world took its shared records from.
	let table: MockWorldsTable
	/// The key of each of the world's variants' declarations, by variant, one entry for every variant, a row or not: the
	/// table's ID of the declaration times two, plus one where every parent of the declaration is the world's root. A row's
	/// key is its row's (`MockWorlds`).
	///
	/// Two worlds give one key to the same declaration with the same bit, and to nothing else, but not to the same record:
	/// the record of a declaration on a cycle, or of one that reaches a cycle, a hole, a fill or a loop of builders,
	/// depends on where the world's root enters it. The key is for facts of the declaration alone.
	let declarationKeyByVariant: [Int32]
}

/// Every mock world of a module, each built once, before the mock roots are lowered, from the frozen mock worlds' table,
/// with the records the worlds share made once for the run (`MockWorldsTable.sharedRecords`).
///
/// A row is one (declaration, mock flag, key): the table's declaration, a mock world's (every world here is one), and
/// whether every parent of the declaration in its world is the world's root, which decides where a mock construction
/// reads its override (the field of `mock()`'s own overrides or of its parent's configuration), so a declaration that is
/// the root's child in one world and deeper in another is two rows. A variant is a row only where the table finds its
/// declaration shareable (no mock root's own, none that reaches a cycle, a hole or a fill), it is no member of a loop of
/// builders in its world and holds none (a member's record reads its siblings and the world's builder function names,
/// `TypeFactsEdge.loop`), it is of kind `mockConstruction` and holds no refusal (`NodeRecords.kindAndRefusals(of:in:)`),
/// and every variant it calls is a row. Each fact is of the declaration's subtree, but the loop's, which is read per
/// world, so a subtree beneath a member that reaches no loop stays a row.
///
/// Four passes, three of them parallel, each task reading only frozen values: each world's graph and the row each of its
/// variants is (one task per world); the rows' numbering, in the order the worlds first meet them (serial, a pass over
/// integers); each row's record, built from the first world that holds it, in levels by height, so a record's children
/// are the records of the level below, frozen before it starts (one task per row); and each world's node records, which
/// take each shared variant's record from the table (one task per world). A world never decides another's: two worlds
/// that share no row build apart in every pass.
///
/// Each world's records are also built without the table, and the two compared field by field (`NodeRecordsObservation`,
/// with the sharing fields), so a record a row would make wrong in some world is reported (`MockWorldsTableReport`).
/// Both builds are made without refusing a world for owed facts, so that the comparison covers every world whose records
/// are made, and the owed facts are judged after.
struct MockWorlds: Sendable {
	/// Each world, in the order of `roots`.
	let worlds: [MockWorld]
	/// What a test observes of the table and the worlds' records.
	let report: MockWorldsTableReport

	/// - Parameters:
	///   - roots: The root of each mock root's world, in the order the module lowers them, which `table` was built from.
	///   - table: The mock worlds' table of `roots`, holding no shared record yet.
	///   - sharedGraph: The shared graph of `table`'s shareable declarations, whose facts each world's are compared with.
	static func build(roots: [ConstructionScope], table: MockWorldsTable, sharedGraph: MockWorldsSharedGraph) async throws -> MockWorlds {
		let width = ProcessInfo.processInfo.activeProcessorCount
		// Each world's top graph, which stops at the shared declarations it reaches, and the calls it makes into them; and
		// its graph built whole, which the observers compare with. A `.public` mock whose root reaches a hole is built
		// whole: its holes are places, whose carrier edges are a fact of its whole tree.
		let tops = try await BoundedConcurrency.map(roots, width: width) { root, _ in
			let wholeGraph = TypeFactsGraph(root: root, forMockGeneration: true)
			let topGraph = TypeFactsGraph(root: root, forMockGeneration: true, sharedBelow: sharedGraph)
			let isBuiltWhole = (root.instantiable.generatesDependencyTree || root.instantiable.generateMock == .public) && topGraph.holesBeneath.contains(0, inRow: 0)
			return WorldTop(
				wholeGraph: wholeGraph,
				top: isBuiltWhole ? wholeGraph : topGraph,
				isBuiltWhole: isBuiltWhole,
				entries: isBuiltWhole ? [] : frontierEntries(of: topGraph, in: sharedGraph),
				sharedFactsDifferences: sharedFactsDifferences(of: wholeGraph, in: table, sharedGraph: sharedGraph),
			)
		}

		// Every world's calls into the shared graph, each distinct one numbered in the order the worlds first make it, and
		// the shared graph's variants found from them.
		var entries = [MockWorldsSharedEntry]()
		// Identity numbers an entry by its first call and orders nothing.
		var entryIndexByEntry = [MockWorldsSharedEntry: Int]()
		let entryIndicesByWorld = tops.map { top in
			top.entries.map { call in
				if let index = entryIndexByEntry[call.entry] {
					return index
				}
				entryIndexByEntry[call.entry] = entries.count
				entries.append(call.entry)
				return entries.count - 1
			}
		}
		let sharedVariants = sharedGraph.variants(seededBy: entries)
		let frozenEntryIndicesByWorld = entryIndicesByWorld

		let worldRows = try await BoundedConcurrency.map(Array(tops.indices), width: width) { world, _ in
			let top = tops[world]
			var variantOfTopVariant = [Int32](repeating: -1, count: top.top.variantCount)
			for (call, entryIndex) in zip(top.entries, frozenEntryIndicesByWorld[world]) {
				variantOfTopVariant[Int(call.topVariant)] = sharedVariants.variantOfEntry[entryIndex]
			}
			let view = MockWorldGraph(top: top.top, shared: top.isBuiltWhole ? nil : MockWorldGraph.Shared(graph: sharedGraph, variants: sharedVariants, variantOfTopVariant: variantOfTopVariant), table: table)
			let declarationKeyByVariant = declarationKeys(of: view)
			return WorldRows(
				graph: view,
				wholeGraph: top.wholeGraph,
				graphDeclarationCount: top.top.declarationCount,
				declarationKeyByVariant: declarationKeyByVariant,
				rowKeyByVariant: rowKeys(of: view, in: table, declarationKeyByVariant: declarationKeyByVariant),
				sharedFactsDifferences: top.sharedFactsDifferences + viewDifferences(of: view, from: top.wholeGraph, in: table),
			)
		}

		// Each row's number, in the order the worlds first meet it, and the world and variant it is first met at.
		var rowByKey = [Int32](repeating: -1, count: sharedVariants.variants.count * 2)
		var rowOwners = [RowOwner]()
		for (worldIndex, rows) in worldRows.enumerated() {
			for (variant, key) in rows.rowKeyByVariant.enumerated() where key >= 0 && rowByKey[Int(key)] < 0 {
				rowByKey[Int(key)] = Int32(rowOwners.count)
				rowOwners.append(RowOwner(world: worldIndex, variant: VariantID(variant)))
			}
		}
		let frozenRowByKey = rowByKey
		let frozenRowOwners = rowOwners
		// The rows each row's variant calls in its owner's world, which are rows too, in call order.
		let childRowsByRow = frozenRowOwners.map { owner in
			let rows = worldRows[owner.world]
			return rows.graph.calls(of: owner.variant).map { frozenRowByKey[Int(rows.rowKeyByVariant[Int($0)])] }
		}

		// Each row's record, in levels by height: a leaf's first, each level after the levels its children are in.
		var records = [BuiltPlaceRecord?](repeating: nil, count: frozenRowOwners.count)
		for level in levels(ofRowsCalling: childRowsByRow) {
			let recordsBelow = records
			let levelRecords = try await BoundedConcurrency.map(level, width: width) { row, _ in
				let owner = frozenRowOwners[Int(row)]
				return try record(of: owner.variant, in: worldRows[owner.world].graph, childRecords: childRowsByRow[Int(row)].compactMap { recordsBelow[Int($0)] })
			}
			for (row, record) in zip(level, levelRecords) {
				records[Int(row)] = record
			}
		}
		let sharedRecords = records.compactMap(\.self)
		var rows = [MockWorldsTable.Row]()
		for case let (owner, record?) in zip(frozenRowOwners, records) {
			let world = worldRows[owner.world]
			let key = world.declarationKeyByVariant[Int(owner.variant)]
			rows.append(MockWorldsTable.Row(declaration: key / 2, everyParentIsRoot: key % 2 == 1, record: record))
		}
		let sharedTable = table.holding(sharedRecordsOf: rows)

		let builtWorlds = try await BoundedConcurrency.map(worldRows, width: width) { rows, _ in
			let sharedRecordByVariant = rows.rowKeyByVariant.map { key in key < 0 ? nil : sharedRecords[Int(frozenRowByKey[Int(key)])] }
			let records = NodeRecords.refusingWhatRecordsThrow {
				try NodeRecords(world: rows.graph, declaredTypeNames: nil, sharedRecordByVariant: sharedRecordByVariant, refusesOwedFacts: false)
			}
			let recordsWithoutTable = NodeRecords.refusingWhatRecordsThrow {
				try NodeRecords(world: rows.wholeGraph, declaredTypeNames: nil, refusesOwedFacts: false)
			}
			return BuiltWorld(
				world: world(of: rows.graph, records: records, table: sharedTable, declarationKeyByVariant: rows.declarationKeyByVariant),
				builtRecords: builtRecords(of: records),
				recordCountWithoutTable: builtRecords(of: recordsWithoutTable)?.count ?? 0,
				differences: Self.differences(between: records, and: recordsWithoutTable),
			)
		}
		var differences = [String]()
		for ((root, builtWorld), rows) in zip(zip(roots, builtWorlds), worldRows) {
			differences += (rows.sharedFactsDifferences + builtWorld.differences).map { "\(root.instantiable.concreteInstantiable.asSource): \($0)" }
		}
		return MockWorlds(
			worlds: builtWorlds.map(\.world),
			report: sharedTable.report(
				sharedGraphDeclarations: sharedGraph.declarations,
				sharedVariantCount: sharedVariants.variants.count,
				graphDeclarationCounts: worldRows.map(\.graphDeclarationCount),
				worldRecords: builtWorlds.map(\.builtRecords),
				declarationKeysByWorld: worldRows.map(\.declarationKeyByVariant),
				recordCountsWithoutTable: builtWorlds.map(\.recordCountWithoutTable),
				differences: differences,
			),
		)
	}

	/// Each call `top`, a world's top graph, makes into the shared graph: each of its variants whose declaration is a
	/// frontier, in variant order, with the shared declaration, the family, and the key of each of its reads from above,
	/// by value, in the shared graph's read order.
	private static func frontierEntries(of top: TypeFactsGraph, in sharedGraph: MockWorldsSharedGraph) -> [WorldTop.Call] {
		// Identity finds a read's ID and orders nothing.
		var topReadIDByValue = [ReadValue: Int32](minimumCapacity: top.readTable.count)
		for (id, read) in top.readTable.enumerated() {
			topReadIDByValue[ReadValue(read, labels: top.labelTexts)] = Int32(id)
		}
		var calls = [WorldTop.Call]()
		for variant in 0..<Int32(top.variantCount) {
			let node = top.declaration(of: variant)
			let sharedNode = top.sharedNodeByNode[Int(node)]
			guard sharedNode >= 0 else { continue }
			let topKeys = top.keys(of: variant)
			// A frontier's reads are its subtree's in the shared graph, by value, so each is a read of its top graph's row.
			let keys = sharedGraph.reads.rows.columns(inRow: Int(sharedNode)).map { sharedRead -> MockWorldsSharedEntry.Key in
				let value = ReadValue(sharedGraph.facts.readInterner.values[Int(sharedRead)], labels: sharedGraph.facts.labels.values)
				let rank = topReadIDByValue[value].flatMap { top.reads.rows.rank(of: $0, inRow: Int(node)) } ?? 0
				let key = topKeys[topKeys.startIndex + rank]
				guard key >= 0 else { return .constant(key) }
				let property = top.answerProperties[Int(key)]
				return .answer(TypeFactsGraph.VariantSeeding.Answer(
					text: top.answerTexts[Int(key)],
					isBeingBuilt: top.answerIsBeingBuilt[Int(key)],
					kind: top.answerKinds[Int(key)],
					property: property >= 0 ? top.propertyTable[Int(property)] : nil,
				))
			}
			calls.append(WorldTop.Call(topVariant: variant, entry: MockWorldsSharedEntry(node: sharedNode, family: top.family(of: variant), keys: keys)))
		}
		return calls
	}

	/// Each way `view`, a world's dense view, differs from `graph`, the world's graph built whole: its declarations by
	/// the table's IDs, their kinds, constructions, edges, edges' facts, parents and reads in order, and its variants'
	/// declarations, calls, and sources' kinds and payloads.
	private static func viewDifferences(of view: MockWorldGraph, from graph: TypeFactsGraph, in table: MockWorldsTable) -> [String] {
		guard view.declarationCount == graph.declarationCount, view.variantCount == graph.variantCount else {
			return ["the dense view holds \(view.declarationCount) declarations and \(view.variantCount) variants, the world’s graph \(graph.declarationCount) and \(graph.variantCount)"]
		}
		var differences = [String]()
		for declaration in 0..<Int32(graph.declarationCount) {
			var facts = [String]()
			if view.tableDeclarations[Int(declaration)] != table.declarationID(of: graph.graph.nodes[Int(declaration)]) ?? -1 {
				facts.append("declaration")
			}
			if view.kind(of: declaration) != graph.kind(of: declaration) || view.construction(of: declaration) != graph.construction(of: declaration) {
				facts.append("kind or construction")
			}
			if view.edges(from: declaration) != graph.edges(from: declaration) || view.edgeFacts(from: declaration) != graph.edgeFacts(from: declaration) {
				facts.append("edges")
			}
			if view.parents(of: declaration) != graph.parents(of: declaration) {
				facts.append("parents")
			}
			if view.reads(of: declaration).map(view.value(ofRead:)) != graph.reads(of: declaration).map({ ReadValue(graph.read($0), labels: graph.labelTexts) }) {
				facts.append("reads")
			}
			if !facts.isEmpty {
				differences.append("the dense view’s declaration \(declaration) differs from the world’s graph’s: \(facts.joined(separator: ", "))")
			}
		}
		for variant in 0..<Int32(graph.variantCount) {
			let callsAlike = view.calls(of: variant) == graph.calls(of: variant)
			let sourcesAlike = callsAlike && view.calls(of: variant).indices.allSatisfy { call in
				let edgeIndex = call - view.calls(of: variant).startIndex
				return view.sources(ofCall: edgeIndex, of: variant).map { [Int32($0.kind.rawValue), $0.payload] }
					== graph.sources(ofCall: edgeIndex, of: variant).map { [Int32($0.kind.rawValue), $0.payload] }
			}
			if view.declaration(of: variant) != graph.declaration(of: variant) || !sourcesAlike {
				differences.append("the dense view’s variant \(variant) differs from the world’s graph’s")
			}
		}
		return differences
	}

	/// Each way `world`'s facts of one of its shareable declarations differ from the shared graph's facts of it, by value
	/// (`MockWorldsDeclarationProjection`), each declaration's in the world's order.
	private static func sharedFactsDifferences(of world: TypeFactsGraph, in table: MockWorldsTable, sharedGraph: MockWorldsSharedGraph) -> [String] {
		let declarationByNode = world.graph.nodes.map { table.declarationID(of: $0) ?? -1 }
		let columns = world.sharedFactsColumns
		var differences = [String]()
		for (node, declaration) in declarationByNode.enumerated() where declaration >= 0 && table.isShareable(declaration) {
			let worldFacts = columns.projection(ofNode: node, declarationByNode: declarationByNode)
			guard let sharedFacts = sharedGraph.projection(ofDeclaration: declaration) else {
				differences.append("the shared graph holds no declaration \(declaration)")
				continue
			}
			let differingFacts = worldFacts.differingFacts(from: sharedFacts)
			if !differingFacts.isEmpty {
				differences.append("the shared graph’s facts of declaration \(declaration) differ from the world’s: \(differingFacts.joined(separator: ", "))")
			}
		}
		return differences
	}

	/// The key of each of `world`'s variants' declarations (`MockWorld.declarationKeyByVariant`). The table was built from
	/// the same roots by the same walk of each root's declarations, so it holds every declaration of the world, and no
	/// entry is -1.
	private static func declarationKeys(of world: MockWorldGraph) -> [Int32] {
		let keyByDeclaration = (0..<Int32(world.declarationCount)).map { declaration in
			let everyParentIsRoot = world.parents(of: declaration).allSatisfy { $0.parent == 0 }
			return world.tableDeclarations[Int(declaration)] * 2 + (everyParentIsRoot ? 1 : 0)
		}
		return (0..<Int32(world.variantCount)).map { keyByDeclaration[Int(world.declaration(of: $0))] }
	}

	/// The row of each of `world`'s variants, its declaration's key (`declarationKeyByVariant`), or -1 for a variant that
	/// is no row.
	private static func rowKeys(of world: MockWorldGraph, in table: MockWorldsTable, declarationKeyByVariant: [Int32]) -> [Int32] {
		// Each member of a loop of builders, and each declaration whose children hold one.
		var holdsLoop = [Bool](repeating: false, count: world.declarationCount)
		for declaration in 0..<Int32(world.declarationCount) {
			for edge in world.edgeFacts(from: declaration) where edge.loop >= 0 {
				holdsLoop[Int(declaration)] = true
				holdsLoop[Int(edge.child)] = true
			}
		}
		// Whether each declaration may be a row of its own. The root, declaration 0, is its world's own.
		var mayBeRow = [Bool](repeating: false, count: world.declarationCount)
		for declaration in 1..<world.declarationCount where !holdsLoop[declaration] {
			guard table.isShareable(world.tableDeclarations[declaration]) else { continue }
			let (kind, refusals) = NodeRecords.kindAndRefusals(of: Int32(declaration), in: world)
			mayBeRow[declaration] = kind == .mockConstruction && refusals.isEmpty
		}
		// A variant is a row where its declaration may be one and every variant it calls is a row: a post-order walk from
		// the root, with a stack, since a tree can be as deep as the module has types. A callee still on the path closes a
		// cycle, and is no row.
		var rowKeyByVariant = [Int32](repeating: -1, count: world.variantCount)
		var state = [VisitState](repeating: .unvisited, count: world.variantCount)
		var stack: [(variant: VariantID, childrenPushed: Bool)] = [(0, false)]
		while let (variant, childrenPushed) = stack.popLast() {
			let calls = world.calls(of: variant)
			guard childrenPushed else {
				guard state[Int(variant)] == .unvisited else { continue }
				state[Int(variant)] = .onPath
				stack.append((variant, true))
				for callee in calls.reversed() where state[Int(callee)] == .unvisited {
					stack.append((callee, false))
				}
				continue
			}
			state[Int(variant)] = .visited
			let sharedVariant = world.sharedVariants[Int(variant)]
			guard sharedVariant >= 0, mayBeRow[Int(world.declaration(of: variant))], calls.allSatisfy({ rowKeyByVariant[Int($0)] >= 0 }) else { continue }
			rowKeyByVariant[Int(variant)] = sharedVariant * 2 + declarationKeyByVariant[Int(variant)] % 2
		}
		return rowKeyByVariant
	}

	/// The rows of `childRowsByRow`, each row's children by row, in levels: the rows of each level call only rows of the
	/// levels before it, each level's rows in row order.
	private static func levels(ofRowsCalling childRowsByRow: [[Int32]]) -> [[Int32]] {
		// Each row's height, the longest chain of calls beneath it: a post-order walk of the rows, with a stack. Rows call
		// no row still on the path, since a row's subtree reaches no cycle.
		var heights = [Int?](repeating: nil, count: childRowsByRow.count)
		for start in childRowsByRow.indices where heights[start] == nil {
			var stack: [(row: Int, childrenPushed: Bool)] = [(start, false)]
			while let (row, childrenPushed) = stack.popLast() {
				guard childrenPushed else {
					stack.append((row, true))
					for child in childRowsByRow[row] where heights[Int(child)] == nil {
						stack.append((Int(child), false))
					}
					continue
				}
				heights[row] = (childRowsByRow[row].compactMap { heights[Int($0)] }.max() ?? -1) + 1
			}
		}
		var levels = [[Int32]]()
		for (row, height) in heights.enumerated() {
			// Every row's height is set above.
			let height = height ?? 0
			while levels.count <= height {
				levels.append([])
			}
			levels[height].append(Int32(row))
		}
		return levels
	}

	/// The record of a row, the variant `variant` of `world` that is its first world's, whose children's rows have the
	/// records `childRecords`, in call order: the record `NodeRecords` makes of a node of kind `mockConstruction`.
	/// - Throws: Nothing for a row: a row's declaration is of kind `mockConstruction` and holds no refusal, so it is built
	///   as a property, has an initializer, and its initializer's arguments fulfill its dependencies.
	private static func record(of variant: VariantID, in world: MockWorldGraph, childRecords: [BuiltPlaceRecord]) throws -> BuiltPlaceRecord {
		let declaration = world.declaration(of: variant)
		let calls = world.calls(of: variant)
		// Two calls of one variant are of one row, so the first call's record is each one's. Found by variant, never iterated.
		let recordByCallee = Dictionary(zip(calls, childRecords), uniquingKeysWith: { first, _ in first })
		var escaping = NodeRecords.typesDeclaredEscaping(byConstructionsOf: world.scope(of: declaration).instantiable)
		let children = NodeRecords.children(ofCalls: calls, inOrder: NodeBuildOrder.edgeIndices(inOrderOf: world.edgeFacts(from: declaration)), escaping: &escaping) { callee in
			(recordByCallee[callee].map { .place(PlacePlan(code: .empty, record: .built($0))) }, recordByCallee[callee]?.typesDeclaredEscaping)
		}
		return try NodeRecords.mockConstructionRecord(of: declaration, variant: variant, in: world, typesDeclaredEscaping: escaping, children: children)
	}

	/// The world whose node records, made with the table and without refusing owed facts, are `records`: refused as
	/// `readAnsweredTwoWays` where a producer owes its facts, as `NodeRecords` refuses it.
	private static func world(of graph: MockWorldGraph, records: Result<NodeRecords, NodeRecordRefusal>, table: MockWorldsTable, declarationKeyByVariant: [Int32]) -> MockWorld {
		let records = records.flatMap { made in NodeRecords.owesFacts(in: graph) ? .failure(.readAnsweredTwoWays) : .success(made) }
		let everyRefusal: [NodeRecordRefusal] = switch records {
		case .success:
			[]
		case let .failure(refusal):
			refusal == .recordsThrew ? [.recordsThrew] : NodeRecords.refusals(in: graph, declaredTypeNames: nil)
		}
		return MockWorld(records: records, everyRefusal: everyRefusal, table: table, declarationKeyByVariant: declarationKeyByVariant)
	}

	/// The built records `records` holds, or `nil` where they were refused.
	private static func builtRecords(of records: Result<NodeRecords, NodeRecordRefusal>) -> [BuiltPlaceRecord]? {
		switch records {
		case let .success(made):
			made.builtRecords
		case .failure:
			nil
		}
	}

	/// Each way `records`, made with the table, differ from `recordsWithoutTable`: their refusals, or, where both were
	/// made, any field of any place, its sharing fields included.
	private static func differences(between records: Result<NodeRecords, NodeRecordRefusal>, and recordsWithoutTable: Result<NodeRecords, NodeRecordRefusal>) -> [String] {
		let (refusal, body) = refusalAndBody(of: records)
		let (refusalWithoutTable, bodyWithoutTable) = refusalAndBody(of: recordsWithoutTable)
		var differences = NodeRecordsObservation.differences(between: bodyWithoutTable, and: body, comparingSharingFields: true).differences
		differences += refusal == refusalWithoutTable ? [] : ["refused as \(refusal ?? "nothing") with the table, as \(refusalWithoutTable ?? "nothing") without it"]
		return differences
	}

	/// The refusal of `records`, or their root's body where they were made.
	private static func refusalAndBody(of records: Result<NodeRecords, NodeRecordRefusal>) -> (refusal: String?, body: [GeneratedCode]) {
		switch records {
		case let .success(made):
			(nil, made.rootBody)
		case let .failure(refusal):
			(refusal.rawValue, [])
		}
	}

	/// A world's graph, the key of each of its variants' declarations (`declarationKeys(of:in:)`), and the row each of its
	/// variants is (`rowKeys(of:in:declarationKeyByVariant:)`).
	private struct WorldRows: Sendable {
		/// The world's dense view, which its records read.
		let graph: MockWorldGraph
		/// The world's graph built whole, which the observers compare with.
		let wholeGraph: TypeFactsGraph
		/// How many declarations the world's own graph holds: its top graph's, or its whole graph's where it is built whole.
		let graphDeclarationCount: Int
		let declarationKeyByVariant: [Int32]
		let rowKeyByVariant: [Int32]
		/// Each way the world's facts of its shareable declarations differ from the shared graph's, and its dense view from
		/// its graph built whole.
		let sharedFactsDifferences: [String]
	}

	/// A world's top graph, its graph built whole, and its calls into the shared graph.
	private struct WorldTop: Sendable {
		/// A variant of the top graph whose declaration is a frontier, and its call into the shared graph.
		struct Call: Sendable {
			let topVariant: VariantID
			let entry: MockWorldsSharedEntry
		}

		let wholeGraph: TypeFactsGraph
		let top: TypeFactsGraph
		/// Whether the world takes nothing from the shared graph, and `top` is its whole graph.
		let isBuiltWhole: Bool
		let entries: [Call]
		let sharedFactsDifferences: [String]
	}

	/// The world and variant where the worlds first meet a row.
	private struct RowOwner: Sendable {
		let world: Int
		let variant: VariantID
	}

	/// A world built from the table, with its built records and its differences from the world built without it.
	private struct BuiltWorld: Sendable {
		let world: MockWorld
		let builtRecords: [BuiltPlaceRecord]?
		/// How many built records the world's node records hold where they are made without the table.
		let recordCountWithoutTable: Int
		let differences: [String]
	}

	private enum VisitState {
		case unvisited
		case onPath
		case visited
	}
}
