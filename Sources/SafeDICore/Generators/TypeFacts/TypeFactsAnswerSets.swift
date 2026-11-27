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

/// What answers each read of each node on some route to it: per node and read from above, the set of answers a caller
/// hands it, joined over every route. Validation asks whether any route fails, which each answer of a read's set
/// decides, so it needs no product of answers along a route: a node reached along thousands of routes holds, for each
/// read, the few answers the declarations of the read's label give.
///
/// The least fixed point over the edges: at an edge, a read its source binds is answered there; any other read has
/// every answer its source has for it; and a read its source neither binds nor reads from above, which nothing above
/// answers, has the answer `none`. The fold follows the edges depth first in edge order, as validation's walk does, and
/// carries along an edge only the answers that newly arrived at its source, so each answer of each read of a node
/// crosses each edge of the node once: the work is the edges times their targets' reads, and the answers times their
/// nodes' edges, never the routes.
///
/// Beside each answer it keeps a witness: the edge that first brought the answer to the node in that order, and the
/// answer of the edge's source it was passed down from. Following the witnesses up gives one route of the graph along
/// which the answer arrives, the same on every run, with no walk over routes.
///
/// It holds four columns for as long as its owner keeps it: an offset per read of each node, the answers of each set,
/// and each answer's two witness entries.
struct TypeFactsAnswerSets: Sendable {
	/// The answer of a read nothing above answers.
	static let none: Int32 = -1

	/// - Parameters:
	///   - readOffsets: Each node's run of `readColumn`, one more than the nodes.
	///   - readColumn: Each node's reads from above, in increasing read ID.
	///   - binding: The answer the source of the edge at a position among every node's edges gives a read, or `nil` where
	///     it binds none.
	init(graph: OrderedGraph<some Hashable>, readOffsets: [Int32], readColumn: [Int32], binding: (_ edge: Int, _ read: Int32) -> Int32?) {
		var sets = [[Int32]](repeating: [], count: readColumn.count)
		// Parallel to `sets`: the edge that first brought each answer, and the source's read it was passed down from.
		var edgesBySet = [[Int32]](repeating: [], count: readColumn.count)
		var passedFromBySet = [[Int32]](repeating: [], count: readColumn.count)
		var stepCount = 0
		/// The position in `readColumn` of the node's read, or `nil` where its subtree does not read it from above.
		func slot(of read: Int32, in node: Int) -> Int? {
			var low = Int(readOffsets[node])
			var high = Int(readOffsets[node + 1])
			while low < high {
				let middle = (low + high) / 2
				if readColumn[middle] < read {
					low = middle + 1
				} else {
					high = middle
				}
			}
			return low < Int(readOffsets[node + 1]) && readColumn[low] == read ? low : nil
		}
		/// Adds an answer to the set at `slot` with its witness, and returns whether the set did not hold it.
		func add(_ answer: Int32, toSetAt slot: Int, broughtBy edge: Int, passedFrom sourceSlot: Int?) -> Bool {
			stepCount += 1
			let position = Self.position(of: answer, in: sets[slot][...])
			guard position == sets[slot].count || sets[slot][position] != answer else {
				return false
			}
			sets[slot].insert(answer, at: position)
			edgesBySet[slot].insert(Int32(edge), at: position)
			passedFromBySet[slot].insert(sourceSlot.map(Int32.init) ?? -1, at: position)
			return true
		}
		var isEntered = [Bool](repeating: false, count: graph.nodes.count)
		isEntered[0] = true
		var stack = [Frame(node: 0, isEntering: true, arrived: [])]
		while let frame = stack.last {
			let source = Int(frame.node)
			let targets = graph.edges(from: source)
			guard frame.nextEdge < targets.count else {
				stack.removeLast()
				continue
			}
			stack[stack.count - 1].nextEdge += 1
			let edge = graph.edgeOffset(of: source) + frame.nextEdge
			let target = Int(targets[targets.startIndex + frame.nextEdge])
			var arrived = [Arrival]()
			if frame.isEntering {
				// The first time the fold follows the edge: what the source answers there, and what nothing above answers.
				for targetSlot in Int(readOffsets[target])..<Int(readOffsets[target + 1]) {
					let read = readColumn[targetSlot]
					let answer = binding(edge, read) ?? (slot(of: read, in: source) == nil ? Self.none : nil)
					if let answer, add(answer, toSetAt: targetSlot, broughtBy: edge, passedFrom: nil) {
						arrived.append(Arrival(read: read, answer: answer))
					}
				}
			}
			// What newly arrived at the source passes down wherever the target reads it and the source does not answer it.
			for arrival in frame.arrived {
				guard let targetSlot = slot(of: arrival.read, in: target), binding(edge, arrival.read) == nil else {
					stepCount += 1
					continue
				}
				if add(arrival.answer, toSetAt: targetSlot, broughtBy: edge, passedFrom: slot(of: arrival.read, in: source)) {
					arrived.append(arrival)
				}
			}
			guard !arrived.isEmpty || !isEntered[target] else {
				continue
			}
			stack.append(Frame(node: Int32(target), isEntering: !isEntered[target], arrived: arrived))
			isEntered[target] = true
		}
		var offsets: [Int32] = [0]
		for set in sets {
			offsets.append((offsets.last ?? 0) + Int32(set.count))
		}
		var answers = [Int32]()
		var witnessEdges = [Int32]()
		var witnessOrigins = [Int32]()
		answers.reserveCapacity(Int(offsets.last ?? 0))
		witnessEdges.reserveCapacity(Int(offsets.last ?? 0))
		witnessOrigins.reserveCapacity(Int(offsets.last ?? 0))
		for (slot, set) in sets.enumerated() {
			answers.append(contentsOf: set)
			witnessEdges.append(contentsOf: edgesBySet[slot])
			for (answer, passedFrom) in zip(set, passedFromBySet[slot]) {
				// An answer passed down is in its source's set, which only grew since.
				witnessOrigins.append(passedFrom < 0 ? -1 : offsets[Int(passedFrom)] + Int32(Self.position(of: answer, in: sets[Int(passedFrom)][...])))
			}
		}
		self.offsets = offsets
		self.answers = answers
		self.witnessEdges = witnessEdges
		self.witnessOrigins = witnessOrigins
		self.stepCount = stepCount
	}

	/// The answers of the read at a position in the read column, in increasing ID, `none` first.
	func answers(ofReadAt slot: Int) -> ArraySlice<Int32> {
		answers[Int(offsets[slot])..<Int(offsets[slot + 1])]
	}

	/// One route along which the answer at a position of `answers` arrives at its node, as positions of the graph's
	/// nodes, the root first and the node last: the chain along which the walk first reached the node that answers the
	/// read (or above which nothing does), then the edges that first brought the answer down, in the fold's order.
	func firstRoute(toAnswerAt entry: Int, in graph: OrderedGraph<some Hashable>) -> [Int] {
		var edges = [Int]()
		var entry = entry
		while entry >= 0 {
			edges.append(Int(witnessEdges[entry]))
			entry = Int(witnessOrigins[entry])
		}
		// The topmost edge's source: the one node whose run of edges holds the edge.
		var low = 0
		var high = graph.nodes.count - 1
		while low < high {
			let middle = (low + high) / 2
			if graph.edgeOffset(of: middle + 1) > edges[edges.count - 1] {
				high = middle
			} else {
				low = middle + 1
			}
		}
		var route = graph.firstRoute(to: low)
		for edge in edges.reversed() {
			route.append(Int(graph.edges(from: route[route.count - 1])[edge]))
		}
		return route
	}

	/// The 32-bit elements of the four columns.
	var columnElementCount: Int {
		offsets.count + answers.count + witnessEdges.count + witnessOrigins.count
	}

	/// Where each read's set begins in `answers`, by the read's position in the read column, and where the last ends.
	let offsets: [Int32]
	/// Every set's answers, each set in increasing ID.
	let answers: [Int32]
	/// How many times the fold took an answer to an edge, which a test bounds by the graph's size.
	let stepCount: Int

	/// A node the fold is following the edges of.
	private struct Frame {
		let node: Int32
		/// Whether this is the first time the fold follows the node's edges.
		let isEntering: Bool
		/// The answers that arrived at the node with the edge that led here, which no earlier frame carried down.
		let arrived: [Arrival]
		var nextEdge = 0
	}

	private struct Arrival {
		let read: Int32
		let answer: Int32
	}

	/// Where `answer` is, or would be inserted, in a set in increasing order.
	private static func position(of answer: Int32, in set: ArraySlice<Int32>) -> Int {
		var low = set.startIndex
		var high = set.endIndex
		while low < high {
			let middle = (low + high) / 2
			if set[middle] < answer {
				low = middle + 1
			} else {
				high = middle
			}
		}
		return low
	}

	/// By an answer's position in `answers`: the edge that first brought it to its node.
	private let witnessEdges: [Int32]
	/// By an answer's position in `answers`: the position of the answer of the edge's source it was passed down from, or
	/// -1 where the edge's source answered the read or nothing above the source answers it.
	private let witnessOrigins: [Int32]
}
