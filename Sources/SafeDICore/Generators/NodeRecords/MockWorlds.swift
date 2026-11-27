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
	static func build(roots: [ConstructionScope], table: MockWorldsTable) async throws -> MockWorlds {
		let width = ProcessInfo.processInfo.activeProcessorCount
		let worldRows = try await BoundedConcurrency.map(roots, width: width) { root, _ in
			let graph = TypeFactsGraph(root: root, forMockGeneration: true)
			return WorldRows(graph: graph, rowKeyByVariant: rowKeys(of: graph, in: table))
		}

		// Each row's number, in the order the worlds first meet it, and the world and variant it is first met at.
		var rowByKey = [Int32](repeating: -1, count: table.declarationCount * 2)
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
			let key = worldRows[owner.world].rowKeyByVariant[Int(owner.variant)]
			rows.append(MockWorldsTable.Row(declaration: key / 2, everyParentIsRoot: key % 2 == 1, record: record))
		}
		let sharedTable = table.holding(sharedRecordsOf: rows)

		let builtWorlds = try await BoundedConcurrency.map(worldRows, width: width) { rows, _ in
			let sharedRecordByVariant = rows.rowKeyByVariant.map { key in key < 0 ? nil : sharedRecords[Int(frozenRowByKey[Int(key)])] }
			let records = NodeRecords.refusingWhatRecordsThrow {
				try NodeRecords(world: rows.graph, declaredTypeNames: nil, sharedRecordByVariant: sharedRecordByVariant, refusesOwedFacts: false)
			}
			let recordsWithoutTable = NodeRecords.refusingWhatRecordsThrow {
				try NodeRecords(world: rows.graph, declaredTypeNames: nil, refusesOwedFacts: false)
			}
			return BuiltWorld(
				world: world(of: rows.graph, records: records, table: sharedTable),
				builtRecords: builtRecords(of: records),
				recordCountWithoutTable: builtRecords(of: recordsWithoutTable)?.count ?? 0,
				differences: Self.differences(between: records, and: recordsWithoutTable),
			)
		}
		var differences = [String]()
		for (root, builtWorld) in zip(roots, builtWorlds) {
			differences += builtWorld.differences.map { "\(root.instantiable.concreteInstantiable.asSource): \($0)" }
		}
		return MockWorlds(
			worlds: builtWorlds.map(\.world),
			report: sharedTable.report(worldRecords: builtWorlds.map(\.builtRecords), recordCountsWithoutTable: builtWorlds.map(\.recordCountWithoutTable), differences: differences),
		)
	}

	/// The row of each of `world`'s variants, as its table declaration's ID times two, plus one where every parent of the
	/// declaration is the root, or -1 for a variant that is no row.
	private static func rowKeys(of world: TypeFactsGraph, in table: MockWorldsTable) -> [Int32] {
		// Each member of a loop of builders, and each declaration whose children hold one.
		var holdsLoop = [Bool](repeating: false, count: world.declarationCount)
		for declaration in 0..<Int32(world.declarationCount) {
			for edge in world.edgeFacts(from: declaration) where edge.loop >= 0 {
				holdsLoop[Int(declaration)] = true
				holdsLoop[Int(edge.child)] = true
			}
		}
		// The table's ID of each declaration that may be a row of its own, -1 for one that may not. The root, declaration 0,
		// is its world's own.
		var rowDeclarations = [Int32](repeating: -1, count: world.declarationCount)
		for declaration in 1..<world.declarationCount where !holdsLoop[declaration] {
			guard let id = table.declarationID(of: world.graph.nodes[declaration]), table.isShareable(id) else { continue }
			let (kind, refusals) = NodeRecords.kindAndRefusals(of: Int32(declaration), in: world)
			if kind == .mockConstruction, refusals.isEmpty {
				rowDeclarations[declaration] = id
			}
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
			let declaration = world.declaration(of: variant)
			let id = rowDeclarations[Int(declaration)]
			guard id >= 0, calls.allSatisfy({ rowKeyByVariant[Int($0)] >= 0 }) else { continue }
			let everyParentIsRoot = world.parents(of: declaration).allSatisfy { $0.parent == 0 }
			rowKeyByVariant[Int(variant)] = id * 2 + (everyParentIsRoot ? 1 : 0)
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
	private static func record(of variant: VariantID, in world: TypeFactsGraph, childRecords: [BuiltPlaceRecord]) throws -> BuiltPlaceRecord {
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
	private static func world(of graph: TypeFactsGraph, records: Result<NodeRecords, NodeRecordRefusal>, table: MockWorldsTable) -> MockWorld {
		let records = records.flatMap { made in NodeRecords.owesFacts(in: graph) ? .failure(.readAnsweredTwoWays) : .success(made) }
		let everyRefusal: [NodeRecordRefusal] = switch records {
		case .success:
			[]
		case let .failure(refusal):
			refusal == .recordsThrew ? [.recordsThrew] : NodeRecords.refusals(in: graph, declaredTypeNames: nil)
		}
		return MockWorld(records: records, everyRefusal: everyRefusal, table: table)
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

	/// A world's graph, and the row each of its variants is (`rowKeys(of:in:)`).
	private struct WorldRows: Sendable {
		let graph: TypeFactsGraph
		let rowKeyByVariant: [Int32]
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
