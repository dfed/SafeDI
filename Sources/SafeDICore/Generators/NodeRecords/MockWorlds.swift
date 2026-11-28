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
	/// What the type key reads of the plan nodes of the table's shared records, worked out once for every world.
	let nodeFacts: NodeLayoutFacts
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
/// A row is one (shared variant, mock flag, key): a variant of the mock worlds' shared graph (`MockWorldsSharedVariants`),
/// a mock world's (every world here is one), and whether every parent of its declaration in its world is the world's
/// root, which decides where a mock construction reads its override (the field of `mock()`'s own overrides or of its
/// parent's configuration), so a declaration that is the root's child in one world and deeper in another is two rows. A
/// shared variant is a row where its declaration is of kind `mockConstruction` and holds no refusal
/// (`NodeRecords.mockKindAndRefusals(of:in:)`) and every variant it calls is a row: facts of the shared graph alone, found
/// once for the run. A shareable declaration is no member of a loop of builders and holds none (`MockWorldsTable`), so
/// no world's loop decides a row.
///
/// Five passes, three of them parallel, each task reading only frozen values: each world's top graph and its calls into
/// the shared graph (one task per world); the shared graph's variants and which are rows (serial); each world's walk of
/// its variants, in the order its whole graph's worklist makes them, which gives each its declaration's key and its row,
/// over integers (one task per world); each row's record, built from the shared graph itself, in levels by height, so a
/// record's children are the records of the levels below, frozen before it starts (one task per row), the rows numbered
/// in the order the worlds first meet them; and each world's node records, which take each frontier variant's record
/// from the table (one task per world). A world never decides another's: two worlds that share no row build apart in
/// every pass.
///
/// A world every shared variant of which is a row, none of whose shared declarations it reaches in two variants, makes
/// its node records over its top graph alone: its frontier variants take their rows' records, and only its top graph's
/// declarations make records. Any other world, which reaches a shared declaration that refuses it or that a test's claim
/// makes of another kind, makes them over its dense view of its top graph and the shared graph (`MockWorldGraph`),
/// taking the record of each of its variants that is a row, so that it reports every refusal its whole graph holds.
///
/// Where a test observes the table (`MockWorldsTableObservation`), each world's graph is also built whole, its records
/// built from it without the table, and the two compared field by field (`NodeRecordsObservation`, with the sharing
/// fields), with their refusals, so a record a row would make wrong in some world is reported (`MockWorldsTableReport`).
/// Both builds are made without refusing a world for owed facts, so that the comparison covers every world whose records
/// are made, and the owed facts are judged after. No run that no test observes builds a whole graph a world does not use.
struct MockWorlds: Sendable {
	/// Each world, in the order of `roots`.
	let worlds: [MockWorld]
	/// What a test observes of the table and the worlds' records, where a test observes the table.
	let report: MockWorldsTableReport?

	/// - Parameters:
	///   - roots: The root of each mock root's world, in the order the module lowers them, which `table` was built from.
	///   - table: The mock worlds' table of `roots`, holding no shared record yet.
	///   - sharedGraph: The shared graph of `table`'s shareable declarations, whose facts each world's are compared with.
	static func build(roots: [ConstructionScope], table: MockWorldsTable, sharedGraph: MockWorldsSharedGraph) async throws -> MockWorlds {
		// Each pass reads the module's mock roots at the bound their lowering reads them at, a measured memory constant
		// (`BoundedConcurrency.mockRootWidth`), never the processor count: a world's graphs and records are alive while its
		// job runs. Widening the pre-pass needs a measurement of its peak memory first.
		let width = BoundedConcurrency.mockRootWidth
		let isObserved = MockWorldsTableObservation.observer != nil
		// Each world's top graph, which stops at the shared declarations it reaches, and the calls it makes into them; and,
		// where a test observes the table, its graph built whole, which the observers compare with. A `.public` mock whose
		// root reaches a hole is built whole: its holes are places, whose carrier edges are a fact of its whole tree.
		let tops = try await BoundedConcurrency.map(roots, width: width) { root, _ in
			let topGraph = TypeFactsGraph(root: root, forMockGeneration: true, sharedBelow: sharedGraph)
			let isBuiltWhole = (root.instantiable.generatesDependencyTree || root.instantiable.generateMock == .public) && topGraph.holesBeneath.contains(0, inRow: 0)
			let wholeGraph = isBuiltWhole || isObserved ? TypeFactsGraph(root: root, forMockGeneration: true) : nil
			return WorldTop(
				wholeGraph: wholeGraph,
				top: isBuiltWhole ? wholeGraph ?? topGraph : topGraph,
				isBuiltWhole: isBuiltWhole,
				entries: isBuiltWhole ? [] : frontierEntries(of: topGraph, in: sharedGraph),
				sharedFactsDifferences: wholeGraph.map { sharedFactsDifferences(of: $0, in: table, sharedGraph: sharedGraph) } ?? [],
			)
		}

		// Every world's calls into the shared graph, each distinct one numbered in the order the worlds first make it, and
		// the shared graph's variants found from them, and which of them are rows.
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
		let sources = MockWorldsSharedSources(graph: sharedGraph, variants: sharedVariants)
		let isRowVariant = rowVariants(of: sources)
		let frozenEntryIndicesByWorld = entryIndicesByWorld

		let worldRows = try await BoundedConcurrency.map(Array(tops.indices), width: width) { world, _ in
			let top = tops[world]
			var variantOfTopVariant = [Int32](repeating: -1, count: top.top.variantCount)
			for (call, entryIndex) in zip(top.entries, frozenEntryIndicesByWorld[world]) {
				variantOfTopVariant[Int(call.topVariant)] = sharedVariants.variantOfEntry[entryIndex]
			}
			let walk = WorldWalk(top: top.top, sources: sources, variantOfTopVariant: variantOfTopVariant, table: table, isRowVariant: isRowVariant)
			// A world that is not clean reads its dense view, which a test also compares with its graph built whole.
			let view = walk.isClean ? nil : MockWorldGraph(top: top.top, shared: MockWorldGraph.Shared(graph: sharedGraph, variants: sharedVariants, variantOfTopVariant: variantOfTopVariant), table: table)
			var differences = top.sharedFactsDifferences
			if let wholeGraph = top.wholeGraph {
				differences += view.map { viewDifferences(of: $0, from: wholeGraph, in: table) } ?? []
				differences += declarationKeys(of: wholeGraph, in: table) == walk.declarationKeyByVariant ? [] : ["the walk’s declaration keys differ from the world’s graph’s"]
			}
			return WorldRows(top: top.top, wholeGraph: top.wholeGraph, view: view, walk: walk, variantOfTopVariant: variantOfTopVariant, sharedFactsDifferences: differences)
		}

		// Each row, by its key, in the order the worlds first meet it, and the rows its shared variant calls, which are rows
		// too, in call order: a row's callee is called beneath a shared declaration, so no parent of its declaration is the
		// root.
		var rowByKey = [Int32](repeating: -1, count: sharedVariants.variants.count * 2)
		var keysInFirstMeetOrder = [Int32]()
		for rows in worldRows {
			for key in rows.walk.rowKeyByVariant where key >= 0 && rowByKey[Int(key)] < 0 {
				rowByKey[Int(key)] = Int32(keysInFirstMeetOrder.count)
				keysInFirstMeetOrder.append(key)
			}
		}
		let frozenRowByKey = rowByKey
		let rowKeys = keysInFirstMeetOrder
		let childRowsByRow = rowKeys.map { key in
			sources.calls(of: key / 2).map { frozenRowByKey[Int($0) * 2] }
		}

		// Each row's record, in levels by height: a leaf's first, each level after the levels its children are in, each
		// record kept at its row.
		var recordByRow = [BuiltPlaceRecord?](repeating: nil, count: rowKeys.count)
		for level in levels(ofRowsCalling: childRowsByRow) {
			let recordsBelow = recordByRow
			let levelRecords = try await BoundedConcurrency.map(level, width: width) { row, _ in
				let variant = rowKeys[Int(row)] / 2
				return try record(of: variant, in: sources, childRecords: childRowsByRow[Int(row)].compactMap { recordsBelow[Int($0)] })
			}
			for (row, record) in zip(level, levelRecords) {
				recordByRow[Int(row)] = record
			}
		}
		// Every row's record is made above, in its level.
		let sharedRecords = recordByRow.compactMap(\.self)
		let rows = zip(rowKeys, sharedRecords).map { key, record in
			MockWorldsTable.Row(declaration: sharedGraph.declarations[Int(sources.declaration(of: key / 2))], everyParentIsRoot: key % 2 == 1, record: record)
		}
		let sharedTable = table.holding(sharedRecordsOf: rows)
		// Only a root laid out from its records reads the facts of their nodes.
		let nodeFacts = NodeRecordsObservation.laysOutMockRoots ? NodeLayoutFacts(records: sharedRecords) : .none

		let builtWorlds = try await BoundedConcurrency.map(worldRows, width: width) { rows, _ in
			let records: Result<NodeRecords, NodeRecordRefusal>
			let world: MockWorld
			if let view = rows.view {
				let sharedRecordByVariant = rows.walk.rowKeyByVariant.map { key in key < 0 ? nil : sharedRecords[Int(frozenRowByKey[Int(key)])] }
				records = NodeRecords.refusingWhatRecordsThrow {
					try NodeRecords(world: view, declaredTypeNames: nil, sharedRecordByVariant: sharedRecordByVariant, refusesOwedFacts: false)
				}
				world = Self.world(of: view, records: records, table: sharedTable, nodeFacts: nodeFacts, declarationKeyByVariant: rows.walk.declarationKeyByVariant)
			} else {
				// Each frontier variant takes the record of its row, of the shared variant it calls.
				let sharedRecordByVariant = rows.variantOfTopVariant.map { variant in
					variant < 0 ? nil : sharedRecords[Int(frozenRowByKey[Int(rows.walk.rowKey(ofSharedVariant: variant))])]
				}
				records = NodeRecords.refusingWhatRecordsThrow {
					try NodeRecords(world: rows.top, declaredTypeNames: nil, sharedRecordByVariant: sharedRecordByVariant, refusesOwedFacts: false)
				}
				world = Self.world(of: rows.top, records: records, table: sharedTable, nodeFacts: nodeFacts, declarationKeyByVariant: rows.walk.declarationKeyByVariant)
			}
			guard let wholeGraph = rows.wholeGraph, isObserved else {
				return BuiltWorld(world: world, builtRecords: [], recordCountWithoutTable: 0, differences: [])
			}
			let recordsWithoutTable = NodeRecords.refusingWhatRecordsThrow {
				try NodeRecords(world: wholeGraph, declaredTypeNames: nil, refusesOwedFacts: false)
			}
			let refusalsWithoutTable = Self.world(of: wholeGraph, records: recordsWithoutTable, table: sharedTable, nodeFacts: nodeFacts, declarationKeyByVariant: []).everyRefusal
			let refusalDifferences = world.everyRefusal == refusalsWithoutTable ? [] : ["every refusal is \(world.everyRefusal.map(\.rawValue)) with the table, \(refusalsWithoutTable.map(\.rawValue)) without it"]
			return BuiltWorld(
				world: world,
				builtRecords: builtRecords(of: records),
				recordCountWithoutTable: builtRecords(of: recordsWithoutTable)?.count ?? 0,
				differences: Self.differences(between: records, and: recordsWithoutTable) + refusalDifferences,
			)
		}
		guard isObserved else {
			return MockWorlds(worlds: builtWorlds.map(\.world), report: nil)
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
				graphDeclarationCounts: worldRows.map(\.top.declarationCount),
				worldRecords: builtWorlds.map(\.builtRecords),
				declarationKeysByWorld: worldRows.map(\.walk.declarationKeyByVariant),
				recordCountsWithoutTable: builtWorlds.map(\.recordCountWithoutTable),
				differences: differences,
			),
		)
	}

	/// Whether each of the shared graph's variants is a row: its declaration is of kind `mockConstruction` and holds no
	/// refusal, and every variant it calls is a row. A post-order walk of the variants, with a stack; the shared graph is
	/// a forest of subtrees that reach no cycle, so no callee is still on the path.
	private static func rowVariants(of sources: MockWorldsSharedSources) -> [Bool] {
		let variantCount = sources.variants.variants.count
		// Whether each shared declaration may be a row, found once per declaration.
		var mayBeRowByDeclaration = [Bool?](repeating: nil, count: sources.graph.graph.nodes.count)
		var isRowVariant = [Bool?](repeating: nil, count: variantCount)
		for start in 0..<Int32(variantCount) where isRowVariant[Int(start)] == nil {
			var stack: [(variant: VariantID, childrenPushed: Bool)] = [(start, false)]
			while let (variant, childrenPushed) = stack.popLast() {
				let calls = sources.calls(of: variant)
				guard childrenPushed else {
					stack.append((variant, true))
					for callee in calls.reversed() where isRowVariant[Int(callee)] == nil {
						stack.append((callee, false))
					}
					continue
				}
				let declaration = sources.declaration(of: variant)
				let mayBeRow = mayBeRowByDeclaration[Int(declaration)] ?? {
					let (kind, refusals) = NodeRecords.mockKindAndRefusals(of: declaration, in: sources)
					return kind == .mockConstruction && refusals.isEmpty
				}()
				mayBeRowByDeclaration[Int(declaration)] = mayBeRow
				isRowVariant[Int(variant)] = mayBeRow && calls.allSatisfy { isRowVariant[Int($0)] == true }
			}
		}
		return isRowVariant.map { $0 == true }
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
			if view.madeAgain(from: declaration) != graph.madeAgain(from: declaration) || view.loopMembersSharedApart.contains(declaration) != graph.loopMembersSharedApart.contains(declaration) {
				facts.append("loops")
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

	/// The key of each of `world`'s variants' declarations (`MockWorld.declarationKeyByVariant`), from the world's graph built
	/// whole, which a world's walk (`WorldWalk`) gives where a test observes the table. The table was built from the same
	/// roots by the same walk of each root's declarations, so it holds every declaration of the world, and no entry is -1.
	private static func declarationKeys(of world: TypeFactsGraph, in table: MockWorldsTable) -> [Int32] {
		let keyByDeclaration = (0..<Int32(world.declarationCount)).map { declaration in
			let everyParentIsRoot = world.parents(of: declaration).allSatisfy { $0.parent == 0 }
			return (table.declarationID(of: world.graph.nodes[Int(declaration)]) ?? -1) * 2 + (everyParentIsRoot ? 1 : 0)
		}
		return (0..<Int32(world.variantCount)).map { keyByDeclaration[Int(world.declaration(of: $0))] }
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

	/// The record of a row, of the shared variant `variant` of `world`, the shared graph, whose children's rows have the
	/// records `childRecords`, in call order: the record `NodeRecords` makes of a node of kind `mockConstruction`.
	/// - Throws: Nothing for a row: a row's declaration is of kind `mockConstruction` and holds no refusal, so it is built
	///   as a property, has an initializer, and its initializer's arguments fulfill its dependencies.
	private static func record(of variant: VariantID, in world: MockWorldsSharedSources, childRecords: [BuiltPlaceRecord]) throws -> BuiltPlaceRecord {
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
	private static func world(of graph: some NodeRecordSources, records: Result<NodeRecords, NodeRecordRefusal>, table: MockWorldsTable, nodeFacts: NodeLayoutFacts, declarationKeyByVariant: [Int32]) -> MockWorld {
		let records = records.flatMap { made in NodeRecords.owesFacts(in: graph) ? .failure(.readAnsweredTwoWays) : .success(made) }
		let everyRefusal: [NodeRecordRefusal] = switch records {
		case .success:
			[]
		case let .failure(refusal):
			refusal == .recordsThrew ? [.recordsThrew] : NodeRecords.refusals(in: graph, declaredTypeNames: nil)
		}
		return MockWorld(records: records, everyRefusal: everyRefusal, table: table, nodeFacts: nodeFacts, declarationKeyByVariant: declarationKeyByVariant)
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

	/// A world's top graph, its graph built whole where a test observes it, its dense view where it is not clean, and its
	/// walk (`WorldWalk`).
	private struct WorldRows: Sendable {
		/// The world's top graph, or its whole graph where it is built whole.
		let top: TypeFactsGraph
		/// The world's graph built whole, where a test observes the table or the world is built whole.
		let wholeGraph: TypeFactsGraph?
		/// The world's dense view, which its records read where the world is not clean.
		let view: MockWorldGraph?
		let walk: WorldWalk
		/// The shared variant of each of `top`'s variants whose declaration is a frontier, -1 for each other.
		let variantOfTopVariant: [Int32]
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

		/// The world's graph built whole, where a test observes the table or the world is built whole.
		let wholeGraph: TypeFactsGraph?
		let top: TypeFactsGraph
		/// Whether the world takes nothing from the shared graph, and `top` is its whole graph.
		let isBuiltWhole: Bool
		let entries: [Call]
		let sharedFactsDifferences: [String]
	}

	/// A world's variants, walked over integers in the order its whole graph's worklist makes them (`MockWorldGraph`): from
	/// the root's, each top variant's calls in edge order, a frontier's callee taken as its shared variant, then its
	/// made-again calls, and each shared variant's calls, a callee met first walked next. It gives each variant its
	/// declaration's key and its row, and says whether the world is clean: every shared variant it reaches is a row, and it
	/// reaches each shared declaration, and each frontier, in one variant. It holds its columns for as long as its world is
	/// being built.
	private struct WorldWalk: Sendable {
		init(top: TypeFactsGraph, sources: MockWorldsSharedSources, variantOfTopVariant: [Int32], table: MockWorldsTable, isRowVariant: [Bool]) {
			func sharedNode(ofTopNode node: Int32) -> Int32 {
				top.sharedNodeByNode.isEmpty ? -1 : top.sharedNodeByNode[Int(node)]
			}
			let sharedNodeCount = sources.graph.graph.nodes.count
			var origins: [(isShared: Bool, variant: Int32)] = [(false, 0)]
			var isTopVariantMade = [Bool](repeating: false, count: top.variantCount)
			isTopVariantMade[0] = true
			var isSharedVariantMade = [Bool](repeating: false, count: sources.variants.variants.count)
			// Whether each shared node is called beneath a shared declaration, the frontier it is, and how many variants of it,
			// and of each frontier, the world reaches.
			var isInterior = [Bool](repeating: false, count: sharedNodeCount)
			var topNodeBySharedNode = [Int32](repeating: -1, count: sharedNodeCount)
			var variantCountBySharedNode = [Int32](repeating: 0, count: sharedNodeCount)
			var variantCountByTopNode = [Int32](repeating: 0, count: top.declarationCount)
			var reachesSharedVariantThatIsNoRow = false
			var next = 0
			while next < origins.count {
				let (isShared, variant) = origins[next]
				next += 1
				if isShared {
					let node = sources.declaration(of: variant)
					variantCountBySharedNode[Int(node)] += 1
					reachesSharedVariantThatIsNoRow = reachesSharedVariantThatIsNoRow || !isRowVariant[Int(variant)]
					for callee in sources.calls(of: variant) {
						isInterior[Int(sources.declaration(of: callee))] = true
						if !isSharedVariantMade[Int(callee)] {
							isSharedVariantMade[Int(callee)] = true
							origins.append((true, callee))
						}
					}
					continue
				}
				for callee in top.calls(of: variant) {
					let calleeNode = top.declaration(of: callee)
					let calleeSharedNode = sharedNode(ofTopNode: calleeNode)
					guard calleeSharedNode >= 0 else {
						if !isTopVariantMade[Int(callee)] {
							isTopVariantMade[Int(callee)] = true
							origins.append((false, callee))
						}
						continue
					}
					topNodeBySharedNode[Int(calleeSharedNode)] = calleeNode
					if !isTopVariantMade[Int(callee)] {
						isTopVariantMade[Int(callee)] = true
						variantCountByTopNode[Int(calleeNode)] += 1
					}
					let sharedVariant = variantOfTopVariant[Int(callee)]
					if !isSharedVariantMade[Int(sharedVariant)] {
						isSharedVariantMade[Int(sharedVariant)] = true
						origins.append((true, sharedVariant))
					}
				}
				for callee in top.madeAgainCalls(of: variant) where !isTopVariantMade[Int(callee)] {
					isTopVariantMade[Int(callee)] = true
					origins.append((false, callee))
				}
			}
			// Whether every parent of each declaration is the root: a top declaration's parents are the top graph's, and a
			// shared one's are its frontier's where nothing shared calls it.
			func everyParentIsRoot(ofTopNode node: Int32) -> Bool {
				top.parents(of: node).allSatisfy { $0.parent == 0 }
			}
			let bitBySharedNode = (0..<sharedNodeCount).map { node in
				!isInterior[node] && topNodeBySharedNode[node] >= 0 && everyParentIsRoot(ofTopNode: topNodeBySharedNode[node]) ? Int32(1) : 0
			}
			var declarationKeyByVariant = [Int32]()
			var rowKeyByVariant = [Int32]()
			declarationKeyByVariant.reserveCapacity(origins.count)
			rowKeyByVariant.reserveCapacity(origins.count)
			for (isShared, variant) in origins {
				guard isShared else {
					let node = top.declaration(of: variant)
					// The table was built from the same roots by the same walk of each root's declarations, so it holds every
					// declaration of the world.
					declarationKeyByVariant.append((table.declarationID(of: top.graph.nodes[Int(node)]) ?? -1) * 2 + (everyParentIsRoot(ofTopNode: node) ? 1 : 0))
					rowKeyByVariant.append(-1)
					continue
				}
				let node = sources.declaration(of: variant)
				declarationKeyByVariant.append(sources.graph.declarations[Int(node)] * 2 + bitBySharedNode[Int(node)])
				rowKeyByVariant.append(isRowVariant[Int(variant)] ? variant * 2 + bitBySharedNode[Int(node)] : -1)
			}
			self.declarationKeyByVariant = declarationKeyByVariant
			self.rowKeyByVariant = rowKeyByVariant
			self.bitBySharedNode = bitBySharedNode
			self.sources = sources
			isClean = !reachesSharedVariantThatIsNoRow && variantCountBySharedNode.allSatisfy { $0 <= 1 } && variantCountByTopNode.allSatisfy { $0 <= 1 }
		}

		/// The key of each variant's declaration, in the walk's order (`MockWorld.declarationKeyByVariant`).
		let declarationKeyByVariant: [Int32]
		/// The row of each variant, in the walk's order: its shared variant times two, plus its declaration's bit, or -1 for
		/// a variant that is no row.
		let rowKeyByVariant: [Int32]
		/// Whether the world's node records can be made over its top graph alone.
		let isClean: Bool

		/// The row key of the shared variant `variant`, which the world reaches.
		func rowKey(ofSharedVariant variant: Int32) -> Int32 {
			variant * 2 + bitBySharedNode[Int(sources.declaration(of: variant))]
		}

		/// Whether every parent of each shared node's declaration in the world is the world's root, as 1 or 0.
		private let bitBySharedNode: [Int32]
		private let sources: MockWorldsSharedSources
	}

	/// A world built from the table, with its built records and its differences from the world built without it.
	private struct BuiltWorld: Sendable {
		let world: MockWorld
		let builtRecords: [BuiltPlaceRecord]?
		/// How many built records the world's node records hold where they are made without the table.
		let recordCountWithoutTable: Int
		let differences: [String]
	}
}
