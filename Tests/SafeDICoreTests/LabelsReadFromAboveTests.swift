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
	func labels_holdsOwnAndEachTargetsUnboundLabelsInTheOrderTheyWereFirstGiven_whenGraphHasNoCycle() {
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
			["a", "d", "e", "f"],
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
			["y", "w", "x"],
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

	@Test
	func labels_holdAndFoldWordsInProportionToTheGraph_whenFeaturesWithLabelsOfTheirOwnShareOneTree() {
		// The shape that made a pass per declaring scope grow with labels times declaring scopes times shared scopes: F
		// features, each binding K labels of its own types and building 3 screens, the last of which links back to the
		// feature, every screen reading the feature's labels and opening one shared tree of M types, each of which reads the
		// root's 6 services. Every axis grows from the first size to the second; the words held and read per element of the
		// graph (node, edge, read and bound label) must not.
		var wordsPerElement = [Double]()
		var workPerElement = [Double]()
		for (features, labelsPerFeature, sharedTypes) in [(50, 5, 250), (200, 20, 1_000)] {
			let shape = FeaturesOverSharedTree(features: features, labelsPerFeature: labelsPerFeature, sharedTypes: sharedTypes)
			let graph = OrderedGraph(root: 0, edges: shape.edges(from:))
			let labels = LabelsReadFromAbove(
				graph: graph,
				own: { shape.own(of: graph.nodes[$0]) },
				bound: { shape.bound(by: graph.nodes[$0]) },
			)
			let elements = graph.nodes.count + graph.edgeCount + graph.nodes.reduce(0) { $0 + shape.own(of: $1).count + shape.bound(by: $1).count }
			wordsPerElement.append(Double(labels.wordCount) / Double(elements))
			workPerElement.append(Double(labels.work) / Double(elements))

			let feature = graph.index(of: shape.feature(0)) ?? -1
			let screen = graph.index(of: shape.screen(2, ofFeature: 0)) ?? -1
			#expect(labels.labels(of: feature) == FeaturesOverSharedTree.services)
			#expect(labels.labels(of: screen) == shape.labels(ofFeature: 0) + FeaturesOverSharedTree.services)
		}

		#expect(wordsPerElement[1] <= wordsPerElement[0] * 1.1, "\(wordsPerElement)")
		#expect(workPerElement[1] <= workPerElement[0] * 1.1, "\(workPerElement)")
	}
}

/// The nodes of the growth row's graph: 0 the root; then per feature its node, its label types and its 3 screens; then
/// the shared types, a binary tree.
private struct FeaturesOverSharedTree {
	static let services = (0..<6).map { "service\($0)" }

	let features: Int
	let labelsPerFeature: Int
	let sharedTypes: Int

	func feature(_ feature: Int) -> Int {
		1 + feature * nodesPerFeature
	}

	func screen(_ screen: Int, ofFeature feature: Int) -> Int {
		self.feature(feature) + 1 + labelsPerFeature + screen
	}

	func labels(ofFeature feature: Int) -> [String] {
		(0..<labelsPerFeature).map { "feature\(feature)Label\($0)" }
	}

	func edges(from node: Int) -> [Int] {
		if node == 0 {
			return (0..<features).map(feature)
		} else if node >= firstSharedType {
			let child = (node - firstSharedType) * 2 + 1
			return [child, child + 1].filter { $0 < sharedTypes }.map { firstSharedType + $0 }
		} else {
			let (feature, offset) = (node - 1).quotientAndRemainder(dividingBy: nodesPerFeature)
			if offset == 0 {
				return (1...labelsPerFeature + 3).map { node + $0 }
			} else if offset <= labelsPerFeature {
				return []
			} else if offset == labelsPerFeature + 3 {
				return [firstSharedType, self.feature(feature)]
			} else {
				return [firstSharedType]
			}
		}
	}

	func own(of node: Int) -> [String] {
		if node >= firstSharedType {
			return Self.services
		} else if node == 0 {
			return []
		} else {
			let (feature, offset) = (node - 1).quotientAndRemainder(dividingBy: nodesPerFeature)
			return offset > labelsPerFeature ? labels(ofFeature: feature) : []
		}
	}

	func bound(by node: Int) -> Set<String> {
		if node == 0 {
			return Set(Self.services)
		} else if node >= firstSharedType {
			return []
		} else {
			let (feature, offset) = (node - 1).quotientAndRemainder(dividingBy: nodesPerFeature)
			return offset == 0 ? Set(labels(ofFeature: feature)) : []
		}
	}

	private var nodesPerFeature: Int {
		1 + labelsPerFeature + 3
	}

	private var firstSharedType: Int {
		1 + features * nodesPerFeature
	}
}
