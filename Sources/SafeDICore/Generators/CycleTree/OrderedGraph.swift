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
/// named by its position. No `Set` or `Dictionary` order reaches a result: the one dictionary only finds a node's position.
///
/// Built once by the one walk, on an explicit stack, and never changed. It holds one entry per node and one per edge, for
/// as long as its owner keeps it.
struct OrderedGraph<Node: Hashable & Sendable>: Sendable {
	/// Walks from `root`, asking `edges` once for each node, when the walk first reaches it.
	init(root: Node, edges: (Node) -> [Node]) {
		var nodes = [root]
		var indexByNode = [root: 0]
		var targetsByNode = [[Int]()]
		var parentByNode = [0]
		// Tarjan's strongly connected components, in the same walk: a node's position is its discovery number.
		var lowestReachedByNode = [0]
		var isOnComponentStack = [true]
		var componentStack = [0]
		var componentByNode = [0]
		var componentSizes = [Int]()
		var frames = [Frame(node: 0, edges: edges(root))]
		while let frame = frames.last {
			if frame.nextEdge < frame.edges.count {
				frames[frames.count - 1].nextEdge += 1
				let target = frame.edges[frame.nextEdge]
				if let targetIndex = indexByNode[target] {
					targetsByNode[frame.node].append(targetIndex)
					if isOnComponentStack[targetIndex] {
						lowestReachedByNode[frame.node] = min(lowestReachedByNode[frame.node], targetIndex)
					}
				} else {
					let targetIndex = nodes.count
					nodes.append(target)
					indexByNode[target] = targetIndex
					targetsByNode[frame.node].append(targetIndex)
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
				if lowestReachedByNode[frame.node] == frame.node {
					// Every node above this one on the component stack reaches it and is reached from it.
					var size = 0
					while let member = componentStack.popLast() {
						isOnComponentStack[member] = false
						componentByNode[member] = componentSizes.count
						size += 1
						guard member != frame.node else { break }
					}
					componentSizes.append(size)
				}
				if let parentFrame = frames.last {
					lowestReachedByNode[parentFrame.node] = min(lowestReachedByNode[parentFrame.node], lowestReachedByNode[frame.node])
				}
			}
		}
		self.nodes = nodes
		self.indexByNode = indexByNode
		self.targetsByNode = targetsByNode
		self.parentByNode = parentByNode
		self.componentByNode = componentByNode
		self.componentSizes = componentSizes
	}

	/// The nodes in first-reach order: `nodes[0]` is the root.
	let nodes: [Node]

	/// The strongly connected component of each node. Components are numbered in the order the walk completes them, so a
	/// component's number is lower than that of every other component that reaches it.
	let componentByNode: [Int]

	func index(of node: Node) -> Int? {
		indexByNode[node]
	}

	/// The targets of the node's edges, in the order its edges were given.
	func edges(from index: Int) -> [Int] {
		targetsByNode[index]
	}

	/// Whether the node is on a cycle: its component holds another node, or it has an edge to itself.
	func isOnCycle(_ index: Int) -> Bool {
		componentSizes[componentByNode[index]] > 1 || targetsByNode[index].contains(index)
	}

	/// The first chain from the root to the node, depth first in edge order, the root first and the node last: the chain
	/// along which the walk first reached it.
	func firstRoute(to index: Int) -> [Int] {
		var route = [index]
		var node = index
		while node != 0 {
			node = parentByNode[node]
			route.append(node)
		}
		return route.reversed()
	}

	private struct Frame {
		let node: Int
		let edges: [Node]
		var nextEdge = 0
	}

	private let indexByNode: [Node: Int]
	private let targetsByNode: [[Int]]
	/// The node the walk first reached each node from; the root's is itself.
	private let parentByNode: [Int]
	private let componentSizes: [Int]
}
