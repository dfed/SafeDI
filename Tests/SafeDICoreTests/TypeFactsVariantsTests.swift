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

struct TypeFactsVariantsTests {
	@Test
	func init_callsVariantMadeBefore_whenCycleReachesNodeWithSameAnswers() {
		// 1 and 2 form a cycle beneath the root, and 2 reads 0, which nothing binds: the call from 2 back to 1 hands 1
		// the answers it was made with, so it calls that variant.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1], 1: [2], 2: [1]][node, default: []]
		}
		let variants = makeVariants(graph: graph, own: [[], [], [0]], bindings: [:])

		#expect(variants.count == 3)
		#expect((0..<variants.count).map { Array(variants.callees(of: $0)) } == [[1], [2], [1]])
		#expect(variants.isCalledOnce == [false, false, false])
	}

	@Test
	func init_sharesVariantAndKeepsEachCallsSource_whenTwoParentsBindOneAnswer() {
		// The root builds 1 and 2, which each build 3, which reads 0; 1 and 2 each bind 0 with the same answer, so 3 has
		// one variant, and each call says which declaration handed it.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [3], 2: [3]][node, default: []]
		}
		let variants = makeVariants(graph: graph, own: [[], [], [], [0]], bindings: [
			Edge(node: 1, index: 0): [0: VariantBinding(answer: 7, declaration: 1)],
			Edge(node: 2, index: 0): [0: VariantBinding(answer: 7, declaration: 2)],
		])

		#expect(variants.count == 4)
		#expect(variants.callees(of: 1) == variants.callees(of: 2))
		#expect(Array(variants.sources(ofCall: variants.callOffset(of: 1))) == [.bound(1, answer: 7)])
		#expect(Array(variants.sources(ofCall: variants.callOffset(of: 2))) == [.bound(2, answer: 7)])
		#expect(variants.isCalledOnce == [false, true, true, false])
	}

	@Test
	func init_makesVariantPerAnswer_whenTwoParentsBindDifferentAnswers() {
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [3], 2: [3]][node, default: []]
		}
		let variants = makeVariants(graph: graph, own: [[], [], [], [0]], bindings: [
			Edge(node: 1, index: 0): [0: VariantBinding(answer: 7, declaration: 1)],
			Edge(node: 2, index: 0): [0: VariantBinding(answer: 8, declaration: 2)],
		])

		#expect(variants.count == 5)
		#expect((0..<variants.count).map { variants.node(of: $0) } == [0, 1, 3, 2, 2])
		#expect((0..<variants.count).map { Array(variants.keys(of: $0)) } == [[], [], [], [7], [8]])
	}

	@Test
	func init_makesTheSameVariants_whenEveryKeyFallsInOneBucket() {
		// Keys of different nodes and answers that share a bucket are told apart by value, so a bucket holding every key
		// makes the variants the default buckets make.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [3], 2: [3]][node, default: []]
		}
		let bindings: [Edge: [Int32: VariantBinding]] = [
			Edge(node: 1, index: 0): [0: VariantBinding(answer: 7, declaration: 1)],
			Edge(node: 2, index: 0): [0: VariantBinding(answer: 8, declaration: 2)],
		]
		let hashed = makeVariants(graph: graph, own: [[], [], [], [0]], bindings: bindings)
		let oneBucket = makeVariants(graph: graph, own: [[], [], [], [0]], bindings: bindings, bucket: { _, _, _ in 0 })

		#expect(oneBucket.count == hashed.count)
		#expect((0..<oneBucket.count).map { oneBucket.node(of: $0) } == (0..<hashed.count).map { hashed.node(of: $0) })
		#expect((0..<oneBucket.count).map { Array(oneBucket.keys(of: $0)) } == (0..<hashed.count).map { Array(hashed.keys(of: $0)) })
		#expect((0..<oneBucket.count).map { Array(oneBucket.callees(of: $0)) } == (0..<hashed.count).map { Array(hashed.callees(of: $0)) })
	}

	@Test
	func init_answersNone_whenCallerBindsReadAtAnotherEdgeOnly() throws {
		// 1 builds 2 and 3, and binds reads 0 and 128 only at its edge to 2, so neither reaches above 1; 3 reads them
		// beside 1 and 64, which 1 passes through. At the edge to 3 nothing answers 0 or 128: 1's row holds 0's word but
		// not 0, and not 128's word at all.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1], 1: [2, 3]][node, default: []]
		}
		let variants = makeVariants(graph: graph, own: [[], [], [], [0, 1, 64, 128]], bindings: [
			Edge(node: 1, index: 0): [0: VariantBinding(answer: 7, declaration: 1), 128: VariantBinding(answer: 8, declaration: 1)],
		])
		let variantOfOne = try #require((0..<variants.count).first { variants.node(of: $0) == 1 })

		#expect(Array(variants.sources(ofCall: variants.callOffset(of: variantOfOne) + 1)) == [.none, .passedThrough(0), .passedThrough(1), .none])
	}

	@Test
	func init_sharesVariantAndKeepsEachCallsAnswer_whenKeyProjectsTwoAnswersToOneInEitherEdgeOrder() {
		// The parameter rules live in the key: answers a parameter can carry project to one key, and the variant keeps
		// the key alone, so whichever caller the worklist meets first, each call's own answer is its source's.
		for rootEdges in [[1, 2], [2, 1]] {
			let graph = OrderedGraph(root: 0) { node in
				[0: rootEdges, 1: [3], 2: [3]][node, default: []]
			}
			let variants = makeVariants(graph: graph, own: [[], [], [], [0]], bindings: [
				Edge(node: 1, index: 0): [0: VariantBinding(answer: 7, declaration: 1)],
				Edge(node: 2, index: 0): [0: VariantBinding(answer: 8, declaration: 2)],
			], key: { _, _ in 9 })
			let variantOfNode = { (node: Int) in Int(variants.callees(of: 0)[rootEdges.firstIndex(of: node) ?? 0]) }

			#expect(variants.count == 4)
			#expect(Array(variants.keys(of: 3)) == [9])
			#expect(Array(variants.sources(ofCall: variants.callOffset(of: variantOfNode(1)))) == [.bound(1, answer: 7)], "\(rootEdges)")
			#expect(Array(variants.sources(ofCall: variants.callOffset(of: variantOfNode(2)))) == [.bound(2, answer: 8)], "\(rootEdges)")
		}
	}

	@Test
	func init_passesCallersAnswerThrough_whenNodeBindsNothingAtEdge() {
		// The root binds 0 for 1, and 1 hands it on to 2.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1], 1: [2]][node, default: []]
		}
		let variants = makeVariants(graph: graph, own: [[], [], [0]], bindings: [
			Edge(node: 0, index: 0): [0: VariantBinding(answer: 5, declaration: 0)],
		])

		#expect(Array(variants.sources(ofCall: variants.callOffset(of: 0))) == [.bound(0, answer: 5)])
		#expect(Array(variants.sources(ofCall: variants.callOffset(of: 1))) == [.passedThrough(0)])
		#expect(Array(variants.keys(of: 2)) == [5])
	}

	@Test
	func init_handsCollapsedKeyDownUnchanged_whenReadPassesThroughTwoCallsBelowTheCollapse() {
		// 1 and 2 bind 11 and 12 for 3, which the key collapses to 101; 3 and 4 hand it through to 5. The key is not
		// idempotent (101 would key as 110), so a fold that applied it again to a passed-through key would split 4 and 5
		// from 3 or tell their keys apart: one variant per node, and the same key at each depth.
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [3], 2: [3], 3: [4], 4: [5]][node, default: []]
		}
		let variants = makeVariants(graph: graph, own: [[], [], [], [], [], [0]], bindings: [
			Edge(node: 1, index: 0): [0: VariantBinding(answer: 11, declaration: 1)],
			Edge(node: 2, index: 0): [0: VariantBinding(answer: 12, declaration: 2)],
		], key: { _, answer in answer < 0 ? answer : 100 + answer / 10 })

		#expect(variants.count == 6)
		#expect((3..<6).map { Array(variants.keys(of: $0)) } == [[101], [101], [101]])
		#expect(Array(variants.sources(ofCall: variants.callOffset(of: 4))) == [.passedThrough(0)])
	}

	@Test
	func init_makesVariantPerFamily_whenOneEdgeOpensSendableFunction() {
		let graph = OrderedGraph(root: 0) { node in
			[0: [1, 2], 1: [3], 2: [3]][node, default: []]
		}
		let sendableEdge = graph.edgeOffset(of: graph.index(of: 2) ?? 0)
		let variants = makeVariants(graph: graph, own: [[], [], [], []], bindings: [:], family: { edge, family in
			edge == sendableEdge ? .sendable : family
		})

		#expect(variants.count == 5)
		#expect((0..<variants.count).map { variants.family(of: $0) } == [.plain, .plain, .plain, .plain, .sendable])
	}

	@Test
	func init_answersRootsReadsFromRootAnswer_whenSeamRootTakesParameter() {
		let graph = OrderedGraph(root: 0) { node in
			[0: [1]][node, default: []]
		}
		let variants = makeVariants(graph: graph, own: [[1], [0]], bindings: [:], rootAnswer: { read in
			read == 0 ? VariantBinding(answer: 3, declaration: 0) : nil
		})

		#expect(variants.rootSources == [.bound(0, answer: 3), .none])
		#expect(Array(variants.keys(of: 0)) == [3, -1])
		#expect(Array(variants.sources(ofCall: 0)) == [.passedThrough(0)])
	}

	@Test
	func init_keepsVariantsAndWorkInProportionToTheGraph_whenEveryLayerOfHubDoublesItsPaths() {
		// Each layer builds the next twice and every layer reads what the root binds, so the paths double at each layer
		// while the graph gains one node and two edges: the variants, their elements and the worklist's work stay linear.
		var perNodeAndEdge = [[Double]]()
		for layerCount in [10, 40] {
			let graph = OrderedGraph(root: 0) { node in
				node < layerCount ? [node + 1, node + 1] : []
			}
			let variants = makeVariants(graph: graph, own: [[]] + Array(repeating: [0], count: layerCount), bindings: [
				Edge(node: 0, index: 0): [0: VariantBinding(answer: 1, declaration: 0)],
				Edge(node: 0, index: 1): [0: VariantBinding(answer: 1, declaration: 0)],
			])
			let elements = Double(graph.nodes.count + graph.edgeCount)

			#expect(variants.count == layerCount + 1)
			perNodeAndEdge.append([Double(variants.columnElementCount) / elements, Double(variants.work) / elements])
		}

		#expect(perNodeAndEdge[1][0] <= perNodeAndEdge[0][0] * 1.1, "\(perNodeAndEdge)")
		#expect(perNodeAndEdge[1][1] <= perNodeAndEdge[0][1] * 1.1, "\(perNodeAndEdge)")
	}

	private struct Edge: Hashable {
		let node: Int
		let index: Int
	}

	/// Variants of a graph whose nodes are their own positions, each reading `own[node]` and hiding what it binds at any
	/// of its edges.
	private func makeVariants(
		graph: OrderedGraph<Int>,
		own: [[Int32]],
		bindings: [Edge: [Int32: VariantBinding]],
		rootAnswer: (Int32) -> VariantBinding? = { _ in nil },
		family: (Int, VariantFamily) -> VariantFamily = { _, family in family },
		key: (Int32, Int32) -> Int32 = { _, answer in answer },
		bucket: @escaping (Int32, VariantFamily, [Int32]) -> Int = TypeFactsVariants.hash,
	) -> TypeFactsVariants {
		let columnCount = Int((own.flatMap(\.self).max() ?? 0) + 1)
		let ownRows = BitRows(rowCount: graph.nodes.count, columnCount: columnCount) { index, insert in
			own[graph.nodes[index]].forEach(insert)
		}
		let hidden = BitRows(rowCount: graph.nodes.count, columnCount: columnCount) { index, insert in
			for (edge, reads) in bindings where edge.node == graph.nodes[index] {
				reads.keys.forEach(insert)
			}
		}
		var bindingByEdge = [Int: [Int32: VariantBinding]]()
		for (edge, reads) in bindings {
			if let index = graph.index(of: edge.node) {
				bindingByEdge[graph.edgeOffset(of: index) + edge.index] = reads
			}
		}
		return TypeFactsVariants(
			graph: graph,
			reads: ReadsFromAbove(graph: graph, own: ownRows, hidden: hidden),
			rootAnswer: rootAnswer,
			binding: { edge, read in bindingByEdge[edge]?[read] },
			family: family,
			key: key,
			bucket: bucket,
		)
	}
}
