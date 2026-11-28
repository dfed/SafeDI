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

import Testing
@testable import SafeDICore

struct ReadsFromAboveTests {
	@Test
	func reads_hidesReadOnlyAtNodeThatHidesIt_whenTargetBeneathReadsIt() {
		// 0 builds 1 and 2, and 1 builds 2. 2 reads 0 and 1; 1 hides 0, so 0 reaches the root only straight from 2.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [2]][node, default: []]
		}
		let own = BitRows(rowCount: 3, columnCount: 3) { row, insert in
			[[2], [], [1, 0, 1]][row].forEach(insert)
		}
		let hidden = BitRows(rowCount: 3, columnCount: 3) { row, insert in
			[[], [0], []][row].forEach(insert)
		}
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden)

		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[0, 1, 2], [1], [0, 1]])
	}

	@Test
	func reads_givesEveryNodeOfCycleWhatTheCycleReads_whenNodesReachEachOther() {
		let graph = OrderedGraph(root: 0) { node in
			[0: [1], 1: [2], 2: [1]][node, default: []]
		}
		let own = BitRows(rowCount: 3, columnCount: 200) { row, insert in
			[[], [0], [199]][row].forEach(insert)
		}
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: BitRows(rowCount: 3, columnCount: 200) { _, _ in })

		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[0, 199], [0, 199], [0, 199]])
		#expect(reads.rows.contains(199, inRow: 0))
		#expect(!reads.rows.contains(1, inRow: 0))
		#expect(!reads.rows.contains(64, inRow: 0))
		// Two of the four words a row of 200 columns spans hold a bit, in each of three rows.
		#expect(reads.rows.wordCount == 6)
	}

	@Test
	func reads_hidesWhatEachMemberOfCycleHides_whenCycleReachesCompleteComponent() {
		// 1 and 2 form a cycle beneath the root, and 2 builds 3, which reads 0 and 1. 2 hides 1, so 1 reaches 1 and the
		// root only through 2's own read of it; 1 hides 0, which reaches 2 from 3 and the root through 2 alone.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [2], 2: [1, 3]][node, default: []]
		}
		let own = BitRows(rowCount: 4, columnCount: 2) { row, insert in
			[[], [], [], [0, 1]][row].forEach(insert)
		}
		let hidden = BitRows(rowCount: 4, columnCount: 2) { row, insert in
			[[], [0], [1], []][row].forEach(insert)
		}
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden)

		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[0], [], [0], [0, 1]])
	}

	@Test
	func reads_hidesAlongOneEdgeOnly_whenEdgeHidesWhatItsSourceDoesNot() {
		// 0 builds 1 and 2, and 1 builds 2, which reads 0 and 1. 1 hides 0, and the edge from 0 to 2 hides 0 too, so 0 reaches
		// the root along neither; 2 still reads both.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [2]][node, default: []]
		}
		let own = BitRows(rowCount: 3, columnCount: 2) { row, insert in
			[[], [], [0, 1]][row].forEach(insert)
		}
		let hidden = BitRows(rowCount: 3, columnCount: 2) { row, insert in
			[[], [0], []][row].forEach(insert)
		}
		let hiddenAtEdge = BitRows(rowCount: graph.edgeCount, columnCount: 2) { edge, insert in
			[[], [0], []][edge].forEach(insert)
		}
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden, hiddenAtEdge: hiddenAtEdge)

		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[1], [1], [0, 1]])
	}

	@Test
	func reads_hidesAlongOneEdgeOfCycle_whenEdgeToMemberAndEdgeOutOfCycleHide() {
		// 1 and 2 form a cycle beneath the root, and 2 builds 3, which reads 0. 1 reads 1. The edge from 2 back to 1 hides
		// 1, and the edge from 2 to 3 hides 0, so 2 reads nothing and the cycle reads only 1's own read.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1], 1: [2], 2: [1, 3]][node, default: []]
		}
		let own = BitRows(rowCount: 4, columnCount: 2) { row, insert in
			[[], [1], [], [0]][row].forEach(insert)
		}
		let hiddenAtEdge = BitRows(rowCount: graph.edgeCount, columnCount: 2) { edge, insert in
			[[], [], [1], [0]][edge].forEach(insert)
		}
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: BitRows(rowCount: 4, columnCount: 2) { _, _ in }, hiddenAtEdge: hiddenAtEdge)

		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[1], [1], [], [0]])
	}

	@Test
	func reads_hidesOnlyReboundReadsOnMadeAgainCall_whenCallerDeclaresWhatMemberReads() {
		// The root builds members 1 and 2; 1 makes 2 again and rebinds 2's label, read 0. 2 reads 0 and 1; 1 declares 1
		// for its children, but its made-again call is at its top, before that declaration, so 1 reaches 1 and the root
		// through the call, and 0 does not.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2]][node, default: []]
		}
		let own = BitRows(rowCount: 3, columnCount: 2) { row, insert in
			[[], [], [0, 1]][row].forEach(insert)
		}
		let hidden = BitRows(rowCount: 3, columnCount: 2) { row, insert in
			[[], [0, 1], []][row].forEach(insert)
		}
		let rebound = BitRows(rowCount: 3, columnCount: 2) { row, insert in
			[[], [0], []][row].forEach(insert)
		}
		let madeAgain = MadeAgainEdges(graph: graph, targetsByNode: [[], [2], []], labelsByNode: [[], [0], []], parentEdgesByNode: [[], [1], []], rebound: rebound)
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden, madeAgain: madeAgain)

		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[0, 1], [1], [0, 1]])
	}

	@Test
	func reads_settlesRingOfMadeAgainCalls_whenNoGraphEdgeClosesACycle() {
		// The root builds 1, 2 and 3, a ring: each makes the next again and rebinds its label (reads 0, 1, 2 are the
		// labels of 1, 2, 3), and each reads the next one's label. Only the made-again calls close the ring, so the graph
		// has no cycle while the closure settles it as one component. A member's own reads are never hidden, so each reads
		// every label of the ring: its own, and the others through the members it makes again.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2, 3]][node, default: []]
		}
		let own = BitRows(rowCount: 4, columnCount: 3) { row, insert in
			[[], [1], [2], [0]][row].forEach(insert)
		}
		let rebound = BitRows(rowCount: 4, columnCount: 3) { row, insert in
			[[], [1], [2], [0]][row].forEach(insert)
		}
		let madeAgain = MadeAgainEdges(graph: graph, targetsByNode: [[], [2], [3], [1]], labelsByNode: [[], [0], [1], [2]], parentEdgesByNode: [[], [1], [2], [0]], rebound: rebound)
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: rebound, madeAgain: madeAgain)

		#expect(graph.nodes.indices.map(graph.isOnCycle) == [false, false, false, false])
		#expect(madeAgain.isOnReadCycle == [false, true, true, true])
		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[0, 1, 2], [0, 1, 2], [0, 1, 2], [0, 1, 2]])
	}
}
