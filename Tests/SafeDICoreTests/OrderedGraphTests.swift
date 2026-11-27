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

struct OrderedGraphTests {
	@Test
	func init_ordersNodesAsDepthFirstWalkFirstReachesThem_whenLaterEdgesReachNodesAgain() {
		// 0 reaches 5 before 3, and 5 reaches 8 before the root's second edge would: positions follow the walk, and each
		// node's edges keep the order and the duplicates they were given.
		let graph = OrderedGraph(root: 0) { node in
			[0: [5, 3, 5], 5: [8], 3: [8, 5]][node, default: []]
		}

		#expect(graph.nodes == [0, 5, 8, 3])
		#expect(graph.index(of: 3) == 3)
		#expect(graph.index(of: 4) == nil)
		#expect(graph.nodes.indices.map { Array(graph.edges(from: $0)) } == [[1, 3, 1], [2], [], [2, 1]])
		#expect(graph.nodes.indices.map { graph.isOnCycle($0) } == [false, false, false, false])
		#expect(graph.componentByNode == [3, 1, 0, 2])
	}

	@Test
	func componentByNode_groupsNodesThatReachEachOther_whenCyclesNestAndShareNodes() {
		// 1, 2 and 3 reach each other through two cycles that share 1; 4 and 5 form a cycle the first reaches; 6 has an edge
		// to itself; 0 and 7 are on no cycle.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 6], 1: [2], 2: [3, 1], 3: [1, 4], 4: [5], 5: [4, 7], 6: [6]][node, default: []]
		}

		#expect(graph.nodes == [0, 1, 2, 3, 4, 5, 7, 6])
		#expect(graph.componentByNode == [4, 2, 2, 2, 1, 1, 0, 3])
		#expect(graph.nodes.indices.map { graph.isOnCycle($0) } == [false, true, true, true, true, true, false, true])
	}

	@Test
	func componentByNode_isTheSameForEveryOrderOfEachNodesEdges_whenGraphIsOneOfSixPermutations() {
		// The root's three edges in each of their six orders: positions move with the order, and which nodes share a
		// component never does.
		let edges = [1: [2], 2: [1, 3], 3: [4], 4: [3]]
		for rootEdges in [[1, 3, 5], [1, 5, 3], [3, 1, 5], [3, 5, 1], [5, 1, 3], [5, 3, 1]] {
			let graph = OrderedGraph(root: 0) { node in
				node == 0 ? rootEdges : edges[node, default: []]
			}
			var nodesByComponent = [Int32: [Int]]()
			for (index, node) in graph.nodes.enumerated() {
				nodesByComponent[graph.componentByNode[index], default: []].append(node)
			}

			#expect(Set(nodesByComponent.values.map { $0.sorted() }) == [[0], [1, 2], [3, 4], [5]], "\(rootEdges)")
		}
	}

	@Test
	func firstRoute_followsTheChainTheWalkFirstReachedTheNodeBy_whenAShorterChainComesLater() {
		// 9 is reached first through 1 and 2, and again straight from the root.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 9], 1: [2], 2: [9]][node, default: []]
		}

		#expect(graph.firstRoute(to: 3).map { graph.nodes[$0] } == [0, 1, 2, 9])
		#expect(graph.firstRoute(to: 0) == [0])
	}

	@Test
	func init_walksAChainDeeperThanAnyRecursionCouldGo_whenGraphIsOneLongCycle() {
		let length = 200_000
		let graph = OrderedGraph(root: 0) { node in
			[(node + 1) % length]
		}

		#expect(graph.nodes.count == length)
		#expect(Set(graph.componentByNode) == [0])
		#expect(graph.isOnCycle(length - 1))
	}

	@Test
	func init_walksEachRootNoEarlierWalkReachedInTurn_whenRootsShareNodes() {
		// 10 reaches 20 and 30; 20, a root after it, is reached already and starts no walk; 40 reaches 30 again and 50.
		let graph = OrderedGraph(roots: [10, 20, 40]) { node in
			[10: [20, 30], 20: [30], 40: [30, 50]][node, default: []]
		}

		#expect(graph.nodes == [10, 20, 30, 40, 50])
		#expect(graph.nodes.indices.map { Array(graph.edges(from: $0)) } == [[1, 2], [2], [], [2, 4], []])
		#expect(graph.nodes.indices.map { graph.firstRoute(to: $0).map { graph.nodes[$0] } } == [[10], [10, 20], [10, 20, 30], [40], [40, 50]])
		#expect(graph.componentByNode == [2, 1, 0, 4, 3])
		#expect(graph.nodes.indices.map { graph.isOnCycle($0) } == [false, false, false, false, false])
	}

	@Test
	func init_givesEachRootsCycleAComponentOfItsOwn_whenTwoRootsEachReachACycle() {
		// 0 and 1 reach each other; 2, a later root, reaches 3 and 4, which reach each other, and the first cycle again.
		let graph = OrderedGraph(roots: [0, 2]) { node in
			[0: [1], 1: [0], 2: [3], 3: [4, 0], 4: [3]][node, default: []]
		}

		#expect(graph.nodes == [0, 1, 2, 3, 4])
		#expect(graph.componentByNode == [0, 0, 2, 1, 1])
		#expect(graph.nodes.indices.map { graph.isOnCycle($0) } == [true, true, false, true, true])
	}
}
