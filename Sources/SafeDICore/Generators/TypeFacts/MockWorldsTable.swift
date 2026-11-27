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
/// declaration it reaches, itself included, lies on a cycle of that graph or is a hole: a hole of a public mock's world is
/// a place, bound from the builder that world's mock takes, so whatever holds one is built per world. A mock root's own
/// declaration is never shareable: its record is made for its world alone. These are facts of the run, known before any
/// world is built, so no world decides another's.
///
/// Built only where mock worlds are (a test observing node records), so a plain `generate` does no more work. It holds
/// each declaration and its edges as 32-bit IDs, and a bit per declaration, for as long as `generateMockCode` keeps it:
/// one run's mock generation. Nothing of it is stored between runs.
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
				reachesExclusion = reachesExclusion || graph.isOnCycle(node) || graph.nodes[node].declaration?.key.leaf == .hole
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
		self.isShareable = isShareable
		mockedTypes = worlds.map(\.mockedType)
		self.worldRootDeclarations = worldRootDeclarations
	}

	/// What a test observes of the table.
	var report: MockWorldsTableReport {
		MockWorldsTableReport(
			declarationCount: interning.declarationCount,
			shareableDeclarationCount: isShareable.count(where: \.self),
			worlds: zip(mockedTypes, worldRootDeclarations).map { mockedType, root in
				let declarations = declarations(inWorldRootedAt: root)
				return MockWorldsTableReport.World(
					mockedType: mockedType.asSource,
					rootDeclaration: Int(root),
					declarationCount: declarations.count,
					shareableDeclarationCount: declarations.count(where: { isShareable[Int($0)] }),
				)
			},
		)
	}

	/// The declarations the world rooted at `root` holds, in the order its walk first reaches them.
	private func declarations(inWorldRootedAt root: Int32) -> [Int32] {
		var isReached = [Bool](repeating: false, count: isShareable.count)
		isReached[Int(root)] = true
		var reached = [root]
		var pending = [root]
		while let declaration = pending.popLast() {
			for target in edgeTargets[Int(edgeOffsets[Int(declaration)])..<Int(edgeOffsets[Int(declaration) + 1])] where !isReached[Int(target)] {
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
	private let isShareable: [Bool]
	private let mockedTypes: [TypeDescription]
	/// The declaration of each world's root, in the order of `mockedTypes`.
	private let worldRootDeclarations: [Int32]
}

/// What a test observes of the mock worlds' table (`MockWorldsTable`), where it sets `observer`.
public enum MockWorldsTableObservation {
	/// Handed the table's report once per module's mock generation, where the table is built (where a test observes node
	/// records) and this is set. Only a test sets it.
	@TaskLocal public static var observer: (@Sendable (MockWorldsTableReport) -> Void)?
}

/// The counts of the mock worlds' table: its distinct declarations, those shareable, and each world's.
public struct MockWorldsTableReport: Equatable, Sendable {
	/// One mock root's world.
	public struct World: Equatable, Sendable {
		public init(mockedType: String, rootDeclaration: Int, declarationCount: Int, shareableDeclarationCount: Int) {
			self.mockedType = mockedType
			self.rootDeclaration = rootDeclaration
			self.declarationCount = declarationCount
			self.shareableDeclarationCount = shareableDeclarationCount
		}

		/// The mocked type.
		public let mockedType: String
		/// The ID of the world's root declaration: its position in the table's walk.
		public let rootDeclaration: Int
		/// How many declarations the world holds, its root's included.
		public let declarationCount: Int
		/// How many of them are shareable.
		public let shareableDeclarationCount: Int
	}

	public init(declarationCount: Int, shareableDeclarationCount: Int, worlds: [World]) {
		self.declarationCount = declarationCount
		self.shareableDeclarationCount = shareableDeclarationCount
		self.worlds = worlds
	}

	/// How many distinct declarations the module's mock worlds hold.
	public let declarationCount: Int
	/// How many of them are shareable.
	public let shareableDeclarationCount: Int
	/// Each world, in the order the module lowers its mock roots.
	public let worlds: [World]
}
