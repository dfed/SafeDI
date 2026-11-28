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

/// A directed graph over `Node`s in a fixed order: the nodes in the order a depth-first walk from the root, taking each
/// node's edges in the order given, first reaches them, and each node's edges in that order, duplicates kept. A node is
/// named by its position, a dense 32-bit ID. No `Set` or `Dictionary` order reaches a result: the one dictionary only
/// finds a node's position while the graph is built and when a caller asks for one.
///
/// Built once by the one walk, on an explicit stack, and never changed. Its facts are columns of 32-bit positions: the
/// targets of every node's edges in one array, with each node's offset into it, the node each was first reached from,
/// and each node's component. It holds them, the nodes and the dictionary for as long as its owner keeps it.
struct OrderedGraph<Node: Hashable & Sendable>: Sendable {
	/// Walks from `root`, asking `edges` once for each node, when the walk first reaches it.
	init(root: Node, edges: (Node) -> [Node]) {
		var nodes = [root]
		var indexByNode = [root: Int32(0)]
		// Each frame's targets are kept until it is finished, and then appended to the flat columns in node order below.
		var targetsByNode = [[Int32]()]
		var parentByNode: [Int32] = [0]
		// Tarjan's strongly connected components, in the same walk: a node's position is its discovery number.
		var lowestReachedByNode: [Int32] = [0]
		var isOnComponentStack = [true]
		var componentStack: [Int32] = [0]
		var componentByNode: [Int32] = [0]
		var componentSizes = [Int32]()
		var frames = [Frame(node: 0, edges: edges(root))]
		while let frame = frames.last {
			let node = Int(frame.node)
			if frame.nextEdge < frame.edges.count {
				frames[frames.count - 1].nextEdge += 1
				let target = frame.edges[frame.nextEdge]
				if let targetIndex = indexByNode[target] {
					targetsByNode[node].append(targetIndex)
					if isOnComponentStack[Int(targetIndex)] {
						lowestReachedByNode[node] = min(lowestReachedByNode[node], targetIndex)
					}
				} else {
					let targetIndex = Int32(nodes.count)
					nodes.append(target)
					indexByNode[target] = targetIndex
					targetsByNode[node].append(targetIndex)
					targetsByNode.append([])
					parentByNode.append(frame.node)
					lowestReachedByNode.append(targetIndex)
					isOnComponentStack.append(true)
					componentStack.append(targetIndex)
					componentByNode.append(0)
					frames.append(Frame(node: targetIndex, edges: edges(target)))
				}
			} else {
				frames.removeLast()
				if lowestReachedByNode[node] == frame.node {
					// Every node above this one on the component stack reaches it and is reached from it.
					var size: Int32 = 0
					while let member = componentStack.popLast() {
						isOnComponentStack[Int(member)] = false
						componentByNode[Int(member)] = Int32(componentSizes.count)
						size += 1
						guard member != frame.node else { break }
					}
					componentSizes.append(size)
				}
				if let parentFrame = frames.last {
					lowestReachedByNode[Int(parentFrame.node)] = min(lowestReachedByNode[Int(parentFrame.node)], lowestReachedByNode[node])
				}
			}
		}
		var edgeOffsets = [Int32]()
		edgeOffsets.reserveCapacity(nodes.count + 1)
		var edgeTargets = [Int32]()
		edgeTargets.reserveCapacity(targetsByNode.reduce(0) { $0 + $1.count })
		for targets in targetsByNode {
			edgeOffsets.append(Int32(edgeTargets.count))
			edgeTargets.append(contentsOf: targets)
		}
		edgeOffsets.append(Int32(edgeTargets.count))
		self.nodes = nodes
		self.indexByNode = indexByNode
		self.edgeOffsets = edgeOffsets
		self.edgeTargets = edgeTargets
		self.parentByNode = parentByNode
		self.componentByNode = componentByNode
		self.componentSizes = componentSizes
	}

	/// The nodes in first-reach order: `nodes[0]` is the root.
	let nodes: [Node]

	/// The strongly connected component of each node. Components are numbered in the order the walk completes them, so a
	/// component's number is lower than that of every other component that reaches it.
	let componentByNode: [Int32]

	/// How many components the graph has.
	var componentCount: Int {
		componentSizes.count
	}

	func index(of node: Node) -> Int? {
		indexByNode[node].map(Int.init)
	}

	/// The position of the node's first edge among every node's edges, in node order: an edge's position is this plus its
	/// index among the node's edges.
	func edgeOffset(of index: Int) -> Int {
		Int(edgeOffsets[index])
	}

	/// The targets of the node's edges, in the order its edges were given.
	func edges(from index: Int) -> ArraySlice<Int32> {
		edgeTargets[Int(edgeOffsets[index])..<Int(edgeOffsets[index + 1])]
	}

	/// The targets of the node's edges as indices of `nodes`, in the order its edges were given.
	func targets(from index: Int) -> [Int] {
		edges(from: index).map(Int.init)
	}

	/// The strongly connected component of the node, numbered as `componentByNode` numbers it.
	func component(of index: Int) -> Int {
		Int(componentByNode[index])
	}

	/// The positions of the node's edges among every edge of the graph, in the order its edges were given: what a column
	/// parallel to the edges is indexed by.
	func edgeIndices(from index: Int) -> Range<Int> {
		Int(edgeOffsets[index])..<Int(edgeOffsets[index + 1])
	}

	/// How many edges the graph has, duplicates included.
	var edgeCount: Int {
		edgeTargets.count
	}

	/// The 32-bit elements of the graph's columns: a node's offset, parent and component, each edge's target, and each
	/// component's size.
	var columnElementCount: Int {
		edgeOffsets.count + edgeTargets.count + parentByNode.count + componentByNode.count + componentSizes.count
	}

	/// Whether the node is on a cycle: its component holds another node, or it has an edge to itself.
	func isOnCycle(_ index: Int) -> Bool {
		componentSizes[Int(componentByNode[index])] > 1 || edges(from: index).contains(Int32(index))
	}

	/// The first chain from the root to the node, depth first in edge order, the root first and the node last: the chain
	/// along which the walk first reached it.
	func firstRoute(to index: Int) -> [Int] {
		var route = [index]
		var node = index
		while node != 0 {
			node = Int(parentByNode[node])
			route.append(node)
		}
		return route.reversed()
	}

	private struct Frame {
		let node: Int32
		let edges: [Node]
		var nextEdge = 0
	}

	private let indexByNode: [Node: Int32]
	/// Where each node's targets start in `edgeTargets`; the last entry is the number of edges.
	private let edgeOffsets: [Int32]
	/// The target of every edge, each node's in a run starting at its offset.
	let edgeTargets: [Int32]
	/// The node the walk first reached each node from; the root's is itself.
	private let parentByNode: [Int32]
	private let componentSizes: [Int32]
}
