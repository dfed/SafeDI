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

struct LabelsReadFromAboveTests {
	@Test
	func labels_holdsOwnThenEachTargetsUnboundLabelsInEdgeOrder_whenGraphHasNoCycle() {
		// 0 reads "a" and builds 1 and 2; it binds "c", which 1 reads, and "e", which 2's child reads.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2, 1], 2: [3]][node, default: []]
		}
		let labels = LabelsReadFromAbove(
			graph: graph,
			own: { [["a"], ["b", "c", "b"], ["d", "a"], ["e", "f"]][$0] },
			bound: { [["c", "e"], [], [], ["d"]][$0] },
		)

		#expect(graph.nodes.indices.map { labels.labels(of: $0) } == [
			["a", "b", "d", "f"],
			["b", "c"],
			["d", "a", "e", "f"],
			["e", "f"],
		])
	}

	@Test
	func labels_givesEveryNodeOfACycleWhatTheCycleReads_whenNoNodeBetweenBindsTheLabel() {
		// 1, 2 and 3 form a cycle beneath the root. 3 reads "x", which reaches 1 and 2 around the cycle; 2 binds "y", which
		// 3 also reads, so "y" reaches 2 from 3 no further, while 1 reads "y" itself.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1], 1: [2], 2: [3], 3: [1]][node, default: []]
		}
		let labels = LabelsReadFromAbove(
			graph: graph,
			own: { [[], ["y"], ["w"], ["x", "y"]][$0] },
			bound: { [["w"], [], ["y"], []][$0] },
		)

		#expect(graph.nodes.indices.map { labels.labels(of: $0) } == [
			["y", "x"],
			["y", "w", "x"],
			["w", "x"],
			["x", "y", "w"],
		])
	}

	@Test
	func labels_holdsTheSameSets_whenRootsEdgesComeInEachOfSixOrders() {
		// Two cycles share node 1, and each of 2, 3 and 4 reads a label of its own. 3 binds "four", which only 4 reads and
		// only 3 builds within the cycles, so "four" reaches 4 and the root, which also builds 4 itself. Whatever order the
		// root's edges come in, and so whatever position each node has, every node reads the same labels.
		let edges = [1: [2, 3], 2: [1], 3: [4], 4: [1]]
		let own = [0: [String](), 1: [], 2: ["two"], 3: ["three"], 4: ["four"]]
		for rootEdges in [[2, 3, 4], [2, 4, 3], [3, 2, 4], [3, 4, 2], [4, 2, 3], [4, 3, 2]] {
			let graph = OrderedGraph(root: 0) { node in
				node == 0 ? rootEdges : edges[node, default: []]
			}
			let labels = LabelsReadFromAbove(
				graph: graph,
				own: { own[graph.nodes[$0], default: []] },
				bound: { graph.nodes[$0] == 3 ? ["four"] : [] },
			)
			var labelsByNode = [Int: Set<String>]()
			for (index, node) in graph.nodes.enumerated() {
				labelsByNode[node] = Set(labels.labels(of: index))
			}

			#expect(labelsByNode == [
				0: ["two", "three", "four"],
				1: ["two", "three"],
				2: ["two", "three"],
				3: ["two", "three"],
				4: ["two", "three", "four"],
			], "\(rootEdges)")
		}
	}
}
