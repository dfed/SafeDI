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

/// The made-again calls of a world's loops of builders, a column of their own beside the graph's edges: for each edge
/// from a parent to a member M of a loop of builders it declares, the members M's tree receives, M itself among them for
/// a loop of one, each of which M's body makes again at its top (`let xBuilder = Instantiator<X>(__safeDI_xBuilder)`).
/// The set is the edge's, never the node's: one node two parents build can be a member under one and not the other, or
/// make different members again under each, and each variant makes again the set of the edge that made it.
///
/// A made-again call is an edge of the reads closure: what the member made again reads from above, its caller reads from
/// above (`ReadsFromAbove`), and the worklist calls a variant of it from the caller's variant (`TypeFactsVariants`). A
/// node's made-again calls in the closure are every member any of its sets holds. It is no edge of the build order, of
/// `OrderedGraph.isOnCycle` or of `OrderedGraph.firstRoute`, which read the graph's edges alone, so a ring of members
/// stays off every cycle. The reads closure takes its components from `componentByNode` here, the strongly connected
/// components of both columns, and it is built only for a world with a loop.
struct MadeAgainEdges: Sendable {
	/// - Parameter setsByEdge: For each edge (its position among every node's edges), the members its target makes again
	///   there, in the order its body rebinds them: each member's node, the label the target rebinds it as (by the world's
	///   label IDs), and the edge of the loop's parent that builds the member, whose family it is built in wherever it is
	///   made again. Two edges share a set where they hold the same members, labels and parent edges, and a set's
	///   identity (`identity(ofSet:)`) where they hold the same members and labels, which is what tells variants apart: a
	///   variant two parents' edges call with one key and one identity makes its first caller's set again.
	///   - readCount: The number of reads of the world, the columns of `answeredAtParentEdge`.
	///   - answeredAtParentEdge: The reads of a member, by its node and its parent's edge, that the parent answers at that
	///     edge whoever calls it: the labels the member rebinds there and its own label. A call that makes the member again
	///     hands it those, so they never reach its caller's reads.
	init(
		graph: OrderedGraph<some Hashable & Sendable>,
		setsByEdge: [[(node: Int32, label: Int32, parentEdge: Int32)]],
		readCount: Int,
		answeredAtParentEdge: (_ member: Int32, _ parentEdge: Int32) -> [Int32],
	) {
		// Set 0 is the empty set.
		var setByEdge = [Int32](repeating: 0, count: setsByEdge.count)
		var setOffsets: [Int32] = [0, 0]
		var setTargets = [Int32]()
		var setLabels = [Int32]()
		var setParentEdges = [Int32]()
		var setIdentities: [Int32] = [0]
		var setByMembers = [[Int32]: Int32]()
		var identityByMembers = [[Int32]: Int32]()
		for (edge, members) in setsByEdge.enumerated() where !members.isEmpty {
			let full = members.flatMap { [$0.node, $0.label, $0.parentEdge] }
			if let existing = setByMembers[full] {
				setByEdge[edge] = existing
			} else {
				let set = Int32(setOffsets.count - 1)
				setByMembers[full] = set
				setByEdge[edge] = set
				let identity = members.flatMap { [$0.node, $0.label] }
				if let existing = identityByMembers[identity] {
					setIdentities.append(existing)
				} else {
					identityByMembers[identity] = set
					setIdentities.append(set)
				}
				setTargets.append(contentsOf: members.map(\.node))
				setLabels.append(contentsOf: members.map(\.label))
				setParentEdges.append(contentsOf: members.map(\.parentEdge))
				setOffsets.append(Int32(setTargets.count))
			}
		}
		// Each node's made-again calls in the closure: every member of every set of an edge to it (by its position among
		// the sets' members), in the order the edges and their sets first name each.
		let nodeCount = graph.nodes.count
		var membersByNode = [[Int32]](repeating: [], count: nodeCount)
		for (edge, set) in setByEdge.enumerated() where set != 0 {
			let node = Int(graph.edgeTargets[edge])
			for member in setOffsets[Int(set)]..<setOffsets[Int(set) + 1] where !membersByNode[node].contains(member) {
				membersByNode[node].append(member)
			}
		}
		var offsets = [Int32]()
		offsets.reserveCapacity(nodeCount + 1)
		var members = [Int32]()
		for nodeMembers in membersByNode {
			offsets.append(Int32(members.count))
			members.append(contentsOf: nodeMembers)
		}
		offsets.append(Int32(members.count))
		self.offsets = offsets
		self.members = members
		let targets = members.map { setTargets[Int($0)] }
		self.targets = targets
		answered = BitRows(rowCount: setTargets.count, columnCount: readCount) { member, insert in
			answeredAtParentEdge(setTargets[member], setParentEdges[member]).forEach(insert)
		}
		self.setByEdge = setByEdge
		self.setIdentities = setIdentities
		self.setOffsets = setOffsets
		self.setTargets = setTargets
		self.setLabels = setLabels
		self.setParentEdges = setParentEdges
		// Tarjan's strongly connected components over both columns, on an explicit stack: a node's edges are its graph
		// edges, then its made-again calls.
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

	/// Every member any edge to the node has it make again: its made-again calls in the reads closure.
	func targets(of index: Int) -> ArraySlice<Int32> {
		targets[Int(offsets[index])..<Int(offsets[index + 1])]
	}

	/// For each of `targets(of:)`, the row of `answered` that its call hands it.
	func answeredRows(of index: Int) -> ArraySlice<Int32> {
		members[Int(offsets[index])..<Int(offsets[index + 1])]
	}

	/// Per member of a set, the reads its parent answers at its edge (`answeredAtParentEdge`).
	let answered: BitRows

	/// How many sets the edges hold, the empty set 0 among them.
	var setCount: Int {
		setOffsets.count - 1
	}

	/// The set of members the edge's target makes again there, 0 for none.
	func set(ofEdge edge: Int) -> Int32 {
		setByEdge[edge]
	}

	/// The set with the same members and labels as `set` that the edges name first: two variants of a node making sets of
	/// one identity again are one variant where their keys are equal.
	func identity(ofSet set: Int32) -> Int32 {
		setIdentities[Int(set)]
	}

	/// The members of `set`, in the order the member rebinds them.
	func targets(ofSet set: Int32) -> ArraySlice<Int32> {
		setTargets[Int(setOffsets[Int(set)])..<Int(setOffsets[Int(set) + 1])]
	}

	/// For each member of `set`, the label it is rebound as.
	func labels(ofSet set: Int32) -> ArraySlice<Int32> {
		setLabels[Int(setOffsets[Int(set)])..<Int(setOffsets[Int(set) + 1])]
	}

	/// For each member of `set`, the edge of the loop's parent that builds it.
	func parentEdges(ofSet set: Int32) -> ArraySlice<Int32> {
		setParentEdges[Int(setOffsets[Int(set)])..<Int(setOffsets[Int(set) + 1])]
	}

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
		offsets.count + 2 * targets.count + 2 * answered.wordCount + setByEdge.count + setIdentities.count + setOffsets.count + setTargets.count + setLabels.count + setParentEdges.count + componentByNode.count + componentSizes.count + isOnReadCycle.count
	}

	private let offsets: [Int32]
	private let targets: [Int32]
	private let members: [Int32]
	private let setByEdge: [Int32]
	private let setIdentities: [Int32]
	private let setOffsets: [Int32]
	private let setTargets: [Int32]
	private let setLabels: [Int32]
	private let setParentEdges: [Int32]
	private let componentSizes: [Int32]
}
