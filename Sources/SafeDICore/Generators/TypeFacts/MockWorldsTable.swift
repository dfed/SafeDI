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
/// from the table rather than build: the frozen table the mock worlds are to fill their rows from.
///
/// Built whole, on one task, from the roots of the module's mock worlds in the order the module lowers its mock roots,
/// before the lowerings run, and never changed, so the parallel lowerings only read it. One walk, depth first from each
/// root in turn, taking each declaration's edges in the order a world's graph takes them (`TypeFactsDeclaration.edges`),
/// gives each declaration its ID (`RunFactsInterning`) and records its edges once. A declaration is shareable only if no
/// declaration it reaches, itself included, lies on a cycle of that graph, is a hole or is a fill: a hole of a public mock's
/// world is a place, bound from the builder that world's mock takes, and a fill, what a call of another module's public
/// mock is passed, reads the values of the scope that makes the call (`FillCallerReads`), so whatever holds either is
/// built per world. A mock root's own
/// declaration is never shareable: its record is made for its world alone. These are facts of the run, known before any
/// world is built, so no world decides another's.
///
/// Once each world is built from it (`MockWorlds`), it also holds the records the worlds share, one per row
/// (`sharedRecords`): a frozen value again, handed to each root's lowering.
///
/// Built only where mock worlds are (a test observing node records), so a plain `generate` does no more work. It holds
/// each declaration and its edges as 32-bit IDs, a bit per declaration, and each shared record with its node, for as long
/// as `generateMockCode` keeps it: one run's mock generation. Nothing of it is stored between runs.
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

		// Whether each component reaches a cycle or a hole. A component's number is lower than that of every other
		// component that reaches it, so each is judged after every component it reaches.
		var nodesByComponent = [[Int]](repeating: [], count: graph.componentCount)
		for node in graph.nodes.indices {
			nodesByComponent[Int(graph.componentByNode[node])].append(node)
		}
		var reachesExclusionByComponent = [Bool](repeating: false, count: graph.componentCount)
		for (component, nodes) in nodesByComponent.enumerated() {
			var reachesExclusion = false
			for node in nodes {
				let declarationKey = graph.nodes[node].declaration?.key
				reachesExclusion = reachesExclusion || graph.isOnCycle(node) || declarationKey?.leaf == .hole || declarationKey?.isFill == true
				for target in graph.edges(from: node) where Int(graph.componentByNode[Int(target)]) != component {
					reachesExclusion = reachesExclusion || reachesExclusionByComponent[Int(graph.componentByNode[Int(target)])]
				}
			}
			reachesExclusionByComponent[component] = reachesExclusion
		}
		var isShareable = (1..<graph.nodes.count).map { !reachesExclusionByComponent[Int(graph.componentByNode[$0])] }
		let worldRootDeclarations = rootDeclarations.compactMap(interning.declarationID(of:))
		for root in worldRootDeclarations {
			isShareable[Int(root)] = false
		}
		self.interning = interning
		self.edgeOffsets = edgeOffsets
		self.edgeTargets = edgeTargets
		shareableByDeclaration = isShareable
		mockedTypes = worlds.map(\.mockedType)
		self.worldRootDeclarations = worldRootDeclarations
		sharedRecords = []
		sharedRecordIDByNode = [:]
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

	/// Whether the declaration `declaration`, an ID of this table, is shareable: neither a mock root's own nor one that
	/// reaches a cycle, a hole or a fill.
	func isShareable(_ declaration: Int32) -> Bool {
		shareableByDeclaration[Int(declaration)]
	}

	/// How many distinct declarations the worlds hold.
	var declarationCount: Int {
		shareableByDeclaration.count
	}

	/// One shared record: a row's ID, its key, and the record every world that holds the row reads.
	struct SharedRecord: Sendable {
		/// Its position in `sharedRecords`.
		let id: Int32
		/// The ID of the row's declaration.
		let declaration: Int32
		/// Whether every parent of the declaration is its world's root, in each world that holds the row.
		let everyParentIsRoot: Bool
		/// The record, whose `node` is the row's one `PlanNode`.
		let record: BuiltPlaceRecord
	}

	/// What a row is, before its ID: its declaration, whether every parent of it is the root, and its record.
	struct Row: Sendable {
		let declaration: Int32
		let everyParentIsRoot: Bool
		let record: BuiltPlaceRecord
	}

	/// Every shared built record, in ID order: the order the worlds first meet their rows, mock roots in the order the
	/// module lowers them, each world's variants in its worklist's order.
	private(set) var sharedRecords: [SharedRecord]

	/// The row `node` is the node of, or `nil` for a node made for one world.
	func sharedRecordID(of node: PlanNode) -> Int32? {
		sharedRecordIDByNode[node]
	}

	/// This table, holding the records of `rows` as its shared records, in ID order.
	func holding(sharedRecordsOf rows: [Row]) -> MockWorldsTable {
		var table = self
		table.sharedRecords = rows.enumerated().map { SharedRecord(id: Int32($0.offset), declaration: $0.element.declaration, everyParentIsRoot: $0.element.everyParentIsRoot, record: $0.element.record) }
		// Identity finds a node's row and orders nothing.
		table.sharedRecordIDByNode = [PlanNode: Int32](minimumCapacity: rows.count)
		for sharedRecord in table.sharedRecords {
			table.sharedRecordIDByNode[sharedRecord.record.node] = sharedRecord.id
		}
		return table
	}

	/// What a test observes of the table, once each world is built from it: `sharedGraphDeclarations` the table's ID of
	/// each declaration of the shared graph (`MockWorldsSharedGraph`), in its order, `sharedVariantCount` how many variants
	/// it holds, `graphDeclarationCounts` how many declarations each world's own graph holds, `worlds` each world's records, by the
	/// order of `mockedTypes`, `nil` for a world whose records were refused, `declarationKeysByWorld` each world's key of
	/// each of its variants' declarations (`MockWorld.declarationKeyByVariant`), `recordCountsWithoutTable` how many records
	/// each world's node records hold where made without the table, and `differences` every way a world's records differ
	/// from the records the world builds without the table.
	func report(sharedGraphDeclarations: [Int32], sharedVariantCount: Int, graphDeclarationCounts: [Int], worldRecords: [[BuiltPlaceRecord]?], declarationKeysByWorld: [[Int32]], recordCountsWithoutTable: [Int], differences: [String]) -> MockWorldsTableReport {
		MockWorldsTableReport(
			declarationCount: interning.declarationCount,
			shareableDeclarationCount: shareableByDeclaration.count(where: \.self),
			sharedGraphDeclarations: sharedGraphDeclarations,
			sharedVariantCount: sharedVariantCount,
			graphDeclarationCounts: graphDeclarationCounts,
			sharedRecordCount: sharedRecords.count,
			rows: sharedRecords.map { sharedRecord in
				let declaration = declaration(ofID: sharedRecord.declaration)
				return "\(sharedRecord.declaration): \(declaration.property?.asSource ?? declaration.scope.instantiable.concreteInstantiable.asSource)\(sharedRecord.everyParentIsRoot ? ", every parent the root" : "")"
			},
			differences: differences,
			worlds: zip(zip(zip(zip(mockedTypes, worldRootDeclarations), worldRecords), recordCountsWithoutTable), declarationKeysByWorld).map { worldAndCounts, declarationKeys in
				let (((mockedType, root), records), recordCountWithoutTable) = worldAndCounts
				let declarations = declarations(inWorldRootedAt: root)
				return MockWorldsTableReport.World(
					mockedType: mockedType.asSource,
					rootDeclaration: Int(root),
					declarationCount: declarations.count,
					shareableDeclarationCount: declarations.count(where: { shareableByDeclaration[Int($0)] }),
					recordCount: records?.count ?? 0,
					sharedRecordCount: records?.count(where: { sharedRecordID(of: $0.node) != nil }) ?? 0,
					recordCountWithoutTable: recordCountWithoutTable,
					declarationKeys: declarationKeys,
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
	/// Each shared record's ID, by its node.
	private var sharedRecordIDByNode: [PlanNode: Int32]
}

/// What a test observes of the mock worlds' table (`MockWorldsTable`), where it sets `observer`.
public enum MockWorldsTableObservation {
	/// Handed the table's report once per module's mock generation, where the table is built (where a test observes node
	/// records) and this is set, once every world is built from it. Only a test sets it.
	@TaskLocal public static var observer: (@Sendable (MockWorldsTableReport) -> Void)?
}

/// The counts of the mock worlds' table: its distinct declarations, those shareable, the shared graph's declarations, its
/// shared records, and each world's; and every way a world's records differ from those it builds without the table, or
/// its facts of a shareable declaration from the shared graph's.
public struct MockWorldsTableReport: Equatable, Sendable {
	/// One mock root's world.
	public struct World: Equatable, Sendable {
		public init(mockedType: String, rootDeclaration: Int, declarationCount: Int, shareableDeclarationCount: Int, recordCount: Int, sharedRecordCount: Int, recordCountWithoutTable: Int, declarationKeys: [Int32]) {
			self.mockedType = mockedType
			self.rootDeclaration = rootDeclaration
			self.declarationCount = declarationCount
			self.shareableDeclarationCount = shareableDeclarationCount
			self.recordCount = recordCount
			self.sharedRecordCount = sharedRecordCount
			self.recordCountWithoutTable = recordCountWithoutTable
			self.declarationKeys = declarationKeys
		}

		/// The mocked type.
		public let mockedType: String
		/// The ID of the world's root declaration: its position in the table's walk.
		public let rootDeclaration: Int
		/// How many declarations the world holds, its root's included.
		public let declarationCount: Int
		/// How many of them are shareable.
		public let shareableDeclarationCount: Int
		/// How many built records the world's node records hold, 0 where they refused it before making any. A shared
		/// record holds its children's records, so the world holds only the shared records at the top of each shared subtree.
		public let recordCount: Int
		/// How many of those are the table's shared records: the rest the world built for itself.
		public let sharedRecordCount: Int
		/// How many built records the world's node records hold where they are made without the table: each built for the
		/// world alone.
		public let recordCountWithoutTable: Int
		/// The key of each of the world's variants' declarations, by variant (`MockWorld.declarationKeyByVariant`).
		public let declarationKeys: [Int32]
	}

	public init(declarationCount: Int, shareableDeclarationCount: Int, sharedGraphDeclarations: [Int32], sharedVariantCount: Int, graphDeclarationCounts: [Int], sharedRecordCount: Int, rows: [String], differences: [String], worlds: [World]) {
		self.declarationCount = declarationCount
		self.shareableDeclarationCount = shareableDeclarationCount
		self.sharedGraphDeclarations = sharedGraphDeclarations
		self.sharedVariantCount = sharedVariantCount
		self.graphDeclarationCounts = graphDeclarationCounts
		self.sharedRecordCount = sharedRecordCount
		self.rows = rows
		self.differences = differences
		self.worlds = worlds
	}

	/// How many distinct declarations the module's mock worlds hold.
	public let declarationCount: Int
	/// How many of them are shareable.
	public let shareableDeclarationCount: Int
	/// The table's ID of each declaration of the shared graph (`MockWorldsSharedGraph`), in the graph's order: every
	/// shareable declaration, each once, built once for the run.
	public let sharedGraphDeclarations: [Int32]
	/// How many variants the shared graph holds: one per shared declaration and answers to its reads from above that
	/// some world calls it with, each found once for the run.
	public let sharedVariantCount: Int
	/// How many declarations each world's own graph holds, in the order of `worlds`: those that are not shareable and the
	/// frontier beneath them, or every declaration of a world built whole.
	public let graphDeclarationCounts: [Int]
	/// How many records the worlds share, one per row: each built once for the run.
	public let sharedRecordCount: Int
	/// Each row, in ID order: its declaration's ID and property (the type, for a declaration with none), and whether every
	/// parent of it is the root.
	public let rows: [String]
	/// Each way a world's records differ from the records the world builds without the table, or its facts of a shareable
	/// declaration from the shared graph's, which a test fails on.
	public let differences: [String]
	/// Each world, in the order the module lowers its mock roots.
	public let worlds: [World]
}
