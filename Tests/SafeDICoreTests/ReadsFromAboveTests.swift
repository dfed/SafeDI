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
	func reads_takesEveryReadOfMadeAgainCall_whenCallerDeclaresWhatMemberReads() {
		// The root builds members 1 and 2; 1 makes 2 again, rebinding 2's label, read 0, which the root's edge to 1 answers
		// rather than 1 hiding it. 2 reads 0 and 1; 1 declares both for its children, but its made-again call is at its
		// top, before those declarations, so 1 reaches both through the call.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2]][node, default: []]
		}
		let own = BitRows(rowCount: 3, columnCount: 2) { row, insert in
			[[], [], [0, 1]][row].forEach(insert)
		}
		let hidden = BitRows(rowCount: 3, columnCount: 2) { row, insert in
			[[], [0, 1], []][row].forEach(insert)
		}
		let madeAgain = MadeAgainEdges(graph: graph, setsByEdge: [[(node: 2, label: 0, parentEdge: 1)], []], readCount: 2) { _, _ in [] }
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden, madeAgain: madeAgain)

		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[0, 1], [0, 1], [0, 1]])
	}

	@Test
	func reads_settlesRingOfMadeAgainCalls_whenNoGraphEdgeClosesACycle() {
		// The root builds 1, 2 and 3, a ring: each makes the next again and rebinds its label (reads 0, 1, 2 are the
		// labels of 1, 2, 3), and each reads the next one's label. Only the made-again calls close the ring, so the graph
		// has no cycle while the closure settles it as one component. Each member reads only its own receive: what the
		// member it makes again reads, its parent answers at its edge.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2, 3]][node, default: []]
		}
		let own = BitRows(rowCount: 4, columnCount: 3) { row, insert in
			[[], [1], [2], [0]][row].forEach(insert)
		}
		let hidden = BitRows(rowCount: 4, columnCount: 3) { row, insert in
			[[], [1], [2], [0]][row].forEach(insert)
		}
		// The root answers, at its edge to each member, the member's own label and the label it rebinds, so a call that
		// makes the member again hands it both.
		let answered: [Int32: [Int32]] = [1: [0, 1], 2: [1, 2], 3: [2, 0]]
		let madeAgain = MadeAgainEdges(graph: graph, setsByEdge: [[(node: 2, label: 1, parentEdge: 1)], [(node: 3, label: 2, parentEdge: 2)], [(node: 1, label: 0, parentEdge: 0)]], readCount: 3) { member, _ in
			answered[member, default: []]
		}
		let reads = ReadsFromAbove(graph: graph, own: own, hidden: hidden, madeAgain: madeAgain)

		#expect(graph.nodes.indices.map(graph.isOnCycle) == [false, false, false, false])
		#expect(madeAgain.isOnReadCycle == [false, true, true, true])
		#expect(graph.nodes.indices.map { reads.reads(of: $0) } == [[0, 1, 2], [1], [2], [0]])
	}
}
