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

/// The made-again calls of a world's loops of builders, a column of their own beside the graph's edges: for each member M
/// of a loop of builders its parent declares, the members M's tree receives, M itself among them for a loop of one, each
/// of which M's body makes again at its top (`let xBuilder = Instantiator<X>(__safeDI_xBuilder)`), and the reads of the
/// labels M so rebinds.
///
/// A made-again call is an edge of the reads closure: what the member made again reads from above, but for the labels the
/// caller rebinds, the caller reads from above (`ReadsFromAbove`), and the worklist calls a variant of it from the
/// caller's variant (`TypeFactsVariants`). It is no edge of the build order, of `OrderedGraph.isOnCycle` or of
/// `OrderedGraph.firstRoute`, which read the graph's edges alone, so a ring of members stays off every cycle. The reads
/// closure takes its components from `componentByNode` here, the strongly connected components of both columns, and it
/// is built only for a world with a loop.
struct MadeAgainEdges: Sendable {
	/// - Parameters:
	///   - targetsByNode: The members each node makes again, in the order its body rebinds them.
	///   - parentEdgesByNode: For each of those, the edge of the loop's parent that builds the member (its position among
	///     every node's edges), whose family the member is built in wherever it is made again.
	///   - rebound: The reads of the labels each node rebinds, a row per node, read IDs as the reads closure takes them.
	init(graph: OrderedGraph<some Hashable & Sendable>, targetsByNode: [[Int32]], parentEdgesByNode: [[Int32]], rebound: BitRows) {
		var offsets = [Int32]()
		offsets.reserveCapacity(targetsByNode.count + 1)
		var targets = [Int32]()
		for nodeTargets in targetsByNode {
			offsets.append(Int32(targets.count))
			targets.append(contentsOf: nodeTargets)
		}
		offsets.append(Int32(targets.count))
		self.offsets = offsets
		self.targets = targets
		parentEdges = Array(parentEdgesByNode.joined())
		self.rebound = rebound
		// Tarjan's strongly connected components over both columns, on an explicit stack: a node's edges are its graph
		// edges, then its made-again calls.
		let nodeCount = targetsByNode.count
		var discovery = [Int32](repeating: -1, count: nodeCount)
		var lowestReached = [Int32](repeating: 0, count: nodeCount)
		var isOnComponentStack = [Bool](repeating: false, count: nodeCount)
		var componentStack = [Int32]()
		var componentByNode = [Int32](repeating: 0, count: nodeCount)
		var componentSizes = [Int32]()
		var nextDiscovery: Int32 = 0
		func target(of node: Int, at position: Int) -> Int32? {
			let graphEdges = graph.edges(from: node)
			if position < graphEdges.count {
				return graphEdges[graphEdges.startIndex + position]
			}
			let madeAgainPosition = Int(offsets[node]) + position - graphEdges.count
			return madeAgainPosition < Int(offsets[node + 1]) ? targets[madeAgainPosition] : nil
		}
		for start in 0..<nodeCount where discovery[start] < 0 {
			discovery[start] = nextDiscovery
			lowestReached[start] = nextDiscovery
			nextDiscovery += 1
			isOnComponentStack[start] = true
			componentStack.append(Int32(start))
			var frames = [(node: start, nextPosition: 0)]
			while let (node, position) = frames.last {
				if let next = target(of: node, at: position) {
					frames[frames.count - 1].nextPosition += 1
					let nextIndex = Int(next)
					if discovery[nextIndex] < 0 {
						discovery[nextIndex] = nextDiscovery
						lowestReached[nextIndex] = nextDiscovery
						nextDiscovery += 1
						isOnComponentStack[nextIndex] = true
						componentStack.append(next)
						frames.append((nextIndex, 0))
					} else if isOnComponentStack[nextIndex] {
						lowestReached[node] = min(lowestReached[node], discovery[nextIndex])
					}
				} else {
					frames.removeLast()
					if lowestReached[node] == discovery[node] {
						var size: Int32 = 0
						while let member = componentStack.popLast() {
							isOnComponentStack[Int(member)] = false
							componentByNode[Int(member)] = Int32(componentSizes.count)
							size += 1
							guard member != Int32(node) else { break }
						}
						componentSizes.append(size)
					}
					if let parent = frames.last {
						lowestReached[parent.node] = min(lowestReached[parent.node], lowestReached[node])
					}
				}
			}
		}
		self.componentByNode = componentByNode
		self.componentSizes = componentSizes
		isOnReadCycle = (0..<nodeCount).map { node in
			componentSizes[Int(componentByNode[node])] > 1
				|| graph.edges(from: node).contains(Int32(node))
				|| targets[Int(offsets[node])..<Int(offsets[node + 1])].contains(Int32(node))
		}
	}

	/// The members the node's body makes again, in the order it rebinds them.
	func targets(of index: Int) -> ArraySlice<Int32> {
		targets[Int(offsets[index])..<Int(offsets[index + 1])]
	}

	/// For each member the node makes again, the edge of the loop's parent that builds it.
	func parentEdges(of index: Int) -> ArraySlice<Int32> {
		parentEdges[Int(offsets[index])..<Int(offsets[index + 1])]
	}

	/// The reads of the labels each node rebinds, which it hides from the nodes above it and from what it makes again.
	let rebound: BitRows

	/// The strongly connected component of each node over both columns, numbered as `OrderedGraph.componentByNode` is: a
	/// component's number is lower than that of every other component that reaches it.
	let componentByNode: [Int32]

	var componentCount: Int {
		componentSizes.count
	}

	/// Whether the node is on a cycle of either column: its component over both holds another node, or it has an edge or
	/// a made-again call to itself. What the reads closure settles in passes, never what `OrderedGraph.isOnCycle` says.
	let isOnReadCycle: [Bool]

	/// The 32-bit elements of the column (each 64-bit word of a bit set counts two).
	var columnElementCount: Int {
		offsets.count + targets.count + parentEdges.count + componentByNode.count + componentSizes.count + isOnReadCycle.count + 2 * rebound.wordCount
	}

	private let offsets: [Int32]
	private let targets: [Int32]
	private let parentEdges: [Int32]
	private let componentSizes: [Int32]
}
