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

/// A set of small integers per row, kept sparse: a row holds only its 64-bit words that have a bit set, each as its word
/// index and its bits, in increasing word order, every row's words in one pair of flat arrays. What a fold over a world's
/// graph keeps per node, such as the reads a node's subtree makes from above it or the labels a node binds, so what it
/// holds grows with the bits set, never with rows times columns: a world of many labels, each read in a few subtrees,
/// keeps a few words per node.
struct BitRows: Sendable {
	/// Rows in order, each given its columns by `columnsOfRow`, which calls the function it is handed once per column of
	/// the row, in any order and with repeats.
	init(rowCount: Int, columnCount: Int, columnsOfRow: (_ row: Int, _ insert: (Int32) -> Void) -> Void) {
		var accumulator = RowAccumulator(columnCount: columnCount)
		self.init(columnCount: columnCount)
		for row in 0..<rowCount {
			columnsOfRow(row) { column in
				let (word, bit) = Int(column).quotientAndRemainder(dividingBy: 64)
				_ = accumulator.add(1 << UInt64(bit), toWord: Int32(word))
			}
			appendRow(from: &accumulator)
		}
	}

	fileprivate init(columnCount: Int) {
		self.columnCount = columnCount
	}

	let columnCount: Int

	func contains(_ column: Int32, inRow row: Int) -> Bool {
		let (word, bit) = Int(column).quotientAndRemainder(dividingBy: 64)
		for index in Int(rowStarts[row])..<Int(rowEnds[row]) where wordIndices[index] == Int32(word) {
			return wordBits[index] & 1 << UInt64(bit) != 0
		}
		return false
	}

	/// The columns set in a row, in increasing order.
	func columns(inRow row: Int) -> [Int32] {
		var columns = [Int32]()
		for index in Int(rowStarts[row])..<Int(rowEnds[row]) {
			var word = wordBits[index]
			while word != 0 {
				columns.append(wordIndices[index] * 64 + Int32(word.trailingZeroBitCount))
				word &= word - 1
			}
		}
		return columns
	}

	/// Hands each column set in a row to `body`, in increasing order, with its rank: how many columns of the row precede it.
	func forEachColumn(inRow row: Int, _ body: (_ column: Int32, _ rank: Int) -> Void) {
		var rank = 0
		for index in Int(rowStarts[row])..<Int(rowEnds[row]) {
			var word = wordBits[index]
			while word != 0 {
				body(wordIndices[index] * 64 + Int32(word.trailingZeroBitCount), rank)
				rank += 1
				word &= word - 1
			}
		}
	}

	/// How many columns of a row precede `column`, where the row holds it; `nil` where it does not.
	func rank(of column: Int32, inRow row: Int) -> Int? {
		let (word, bit) = Int(column).quotientAndRemainder(dividingBy: 64)
		var rank = 0
		for index in Int(rowStarts[row])..<Int(rowEnds[row]) {
			let bits = wordBits[index]
			if wordIndices[index] == Int32(word) {
				guard bits & 1 << UInt64(bit) != 0 else {
					return nil
				}
				return rank + (bits & (1 << UInt64(bit) - 1)).nonzeroBitCount
			} else {
				rank += bits.nonzeroBitCount
			}
		}
		return nil
	}

	/// The words held, for a test to count what a fold keeps.
	var wordCount: Int {
		wordIndices.count
	}

	/// The words `row` holds.
	func wordCount(ofRow row: Int) -> Int {
		Int(rowEnds[row] - rowStarts[row])
	}

	/// Adds each word of `row` to `accumulator`.
	fileprivate func add(row: Int, to accumulator: inout RowAccumulator) {
		for index in Int(rowStarts[row])..<Int(rowEnds[row]) {
			_ = accumulator.add(wordBits[index], toWord: wordIndices[index])
		}
	}

	/// Adds each word of `row` to `accumulator`, without the bits `mask` holds, and returns whether that set any bit the
	/// accumulator lacked.
	fileprivate func add(row: Int, to accumulator: inout RowAccumulator, excluding mask: RowAccumulator) -> Bool {
		var changed = false
		for index in Int(rowStarts[row])..<Int(rowEnds[row]) {
			let word = wordIndices[index]
			if accumulator.add(wordBits[index] & ~mask.bits(ofWord: word), toWord: word) {
				changed = true
			}
		}
		return changed
	}

	/// Adds the accumulator's words as the next row, and empties the accumulator.
	fileprivate mutating func appendRow(from accumulator: inout RowAccumulator) {
		rowStarts.append(Int32(wordIndices.count))
		accumulator.drain { word, bits in
			wordIndices.append(word)
			wordBits.append(bits)
		}
		rowEnds.append(Int32(wordIndices.count))
	}

	/// Points row `row`, of rows appended out of order, at the words appended last.
	fileprivate mutating func appendWords(ofRow row: Int, from accumulator: inout RowAccumulator) {
		rowStarts[row] = Int32(wordIndices.count)
		accumulator.drain { word, bits in
			wordIndices.append(word)
			wordBits.append(bits)
		}
		rowEnds[row] = Int32(wordIndices.count)
	}

	/// Makes room for `count` rows appended out of order, keeping the storage this set already has.
	fileprivate mutating func reserveRows(_ count: Int) {
		rowStarts.removeAll(keepingCapacity: true)
		rowStarts.append(contentsOf: repeatElement(0, count: count))
		rowEnds.removeAll(keepingCapacity: true)
		rowEnds.append(contentsOf: repeatElement(0, count: count))
	}

	fileprivate mutating func removeAllWords() {
		wordIndices.removeAll(keepingCapacity: true)
		wordBits.removeAll(keepingCapacity: true)
	}

	private var rowStarts = [Int32]()
	private var rowEnds = [Int32]()
	private var wordIndices = [Int32]()
	private var wordBits = [UInt64]()
}

/// One row being gathered: a word per 64 columns, allocated once for every row a fold gathers, and the words a bit was set
/// in, so emptying it costs what it held, never its width.
private struct RowAccumulator {
	init(columnCount: Int) {
		words = [UInt64](repeating: 0, count: (columnCount + 63) / 64)
	}

	func bits(ofWord word: Int32) -> UInt64 {
		words[Int(word)]
	}

	/// Sets `bits` in `word`, and returns whether any was not set.
	mutating func add(_ bits: UInt64, toWord word: Int32) -> Bool {
		let current = words[Int(word)]
		guard bits & ~current != 0 else {
			return false
		}
		if current == 0 {
			touchedWords.append(word)
		}
		words[Int(word)] = current | bits
		return true
	}

	/// Hands each word that has a bit set to `body` in increasing order, then empties the accumulator.
	mutating func drain(_ body: (_ word: Int32, _ bits: UInt64) -> Void) {
		touchedWords.sort()
		for word in touchedWords {
			body(word, words[Int(word)])
			words[Int(word)] = 0
		}
		touchedWords.removeAll(keepingCapacity: true)
	}

	/// Sets the words of `row` of `rows`, for a mask.
	mutating func load(row: Int, of rows: BitRows) {
		rows.add(row: row, to: &self)
	}

	private var words: [UInt64]
	private var touchedWords = [Int32]()
}

/// For each node of a graph, what its subtree reads from above it, as a row of read IDs: what the node reads itself, and
/// each read of a node it has an edge to that the node does not hide, which a node does for each read it binds what is
/// asked for. The least sets that satisfy that rule, so a node on a cycle reads what every node of its cycle reads and
/// none between hides. A world with loops of builders adds its made-again calls (`MadeAgainEdges`) as edges of the
/// closure: a node reads what each member it makes again reads, but for the labels it rebinds, and its components are
/// those of both columns. An edge can hide reads of its own beside its source's (`hiddenAtEdge`): a call's edge to a fill
/// hides what the fill binds as fields of the place it fills, which the call's other fills do not.
///
/// Computed once, a component at a time, each after every component it reaches; a component on a cycle in passes over its
/// nodes in position order until a pass adds nothing. It works on IDs and bit sets only: a read is the caller's dense ID,
/// and the caller spells it. Its work is the words of the rows its edges reach, summed over the edges (and over the
/// passes of a cycle's component), and it holds the words of its rows for as long as its owner keeps it.
struct ReadsFromAbove: Sendable {
	/// - Parameters:
	///   - own: The reads each node makes itself, a row per node in position order.
	///   - hidden: The reads each node hides from the nodes above it, of the same shape.
	///   - followsEdge: Whether a node takes what the target of an edge, by its position among the graph's edges, reads:
	///     every edge, unless a fold says otherwise.
	///   - hiddenAtEdge: The reads each edge hides beside its source's, a row per edge by its position among the graph's
	///     edges, or `nil` where no edge hides any of its own.
	///   - madeAgain: The world's made-again calls, or `nil` for a world with no loop of builders.
	init(graph: OrderedGraph<some Hashable & Sendable>, own: BitRows, hidden: BitRows, followsEdge: (_ edgeIndex: Int) -> Bool = { _ in true }, hiddenAtEdge: BitRows? = nil, madeAgain: MadeAgainEdges? = nil) {
		var rows = BitRows(columnCount: own.columnCount)
		rows.reserveRows(graph.nodes.count)
		var accumulator = RowAccumulator(columnCount: own.columnCount)
		var mask = RowAccumulator(columnCount: own.columnCount)
		let componentByNode = madeAgain?.componentByNode ?? graph.componentByNode
		let componentCount = madeAgain?.componentCount ?? graph.componentCount
		// The mask of an edge that hides reads of its own: its source's, with the edge's.
		var edgeMask = RowAccumulator(columnCount: own.columnCount)
		/// Adds `row` of `source`, without what the node `node` hides and what the edge at `edgeIndex` hides, to `accumulator`,
		/// and returns whether that set any bit the accumulator lacked.
		func accumulate(row: Int, of source: BitRows, excludingAt edgeIndex: Int, of node: Int) -> Bool {
			guard let hiddenAtEdge, hiddenAtEdge.wordCount(ofRow: edgeIndex) > 0 else {
				return source.add(row: row, to: &accumulator, excluding: mask)
			}
			edgeMask.load(row: node, of: hidden)
			edgeMask.load(row: edgeIndex, of: hiddenAtEdge)
			let changed = source.add(row: row, to: &accumulator, excluding: edgeMask)
			edgeMask.drain { _, _ in }
			return changed
		}
		var nodesByComponent = [Int32](repeating: 0, count: graph.nodes.count)
		var componentStarts = [Int32](repeating: 0, count: componentCount + 1)
		for index in graph.nodes.indices {
			componentStarts[Int(componentByNode[index]) + 1] += 1
		}
		for component in 0..<componentCount {
			componentStarts[component + 1] += componentStarts[component]
		}
		var nextSlotByComponent = componentStarts
		for index in graph.nodes.indices {
			let component = Int(componentByNode[index])
			nodesByComponent[Int(nextSlotByComponent[component])] = Int32(index)
			nextSlotByComponent[component] += 1
		}
		// A cycle's rows while its passes run: the pass before's and the pass's own, each a row per member.
		var previousPass = BitRows(columnCount: own.columnCount)
		var pass = BitRows(columnCount: own.columnCount)
		var memberSlotByNode = [Int32](repeating: -1, count: graph.nodes.count)
		var work = 0
		// A component's number is lower than that of every component that reaches it, so every target outside the
		// component is complete when the component starts.
		for component in 0..<componentCount {
			let members = nodesByComponent[Int(componentStarts[component])..<Int(componentStarts[component + 1])]
			if members.count == 1, let index = members.first.map(Int.init), !(madeAgain?.isOnReadCycle[index] ?? graph.isOnCycle(index)) {
				mask.load(row: index, of: hidden)
				own.add(row: index, to: &accumulator)
				for edgeIndex in graph.edgeIndices(from: index) where followsEdge(edgeIndex) {
					let target = graph.edgeTargets[edgeIndex]
					work += rows.wordCount(ofRow: Int(target))
					_ = accumulate(row: Int(target), of: rows, excludingAt: edgeIndex, of: index)
				}
				mask.drain { _, _ in }
				if let madeAgain {
					// A member made again reads from above its caller's top, where only the labels the caller rebinds are
					// bound: the caller's own declarations come after.
					mask.load(row: index, of: madeAgain.rebound)
					for target in madeAgain.targets(of: index) {
						work += rows.wordCount(ofRow: Int(target))
						_ = rows.add(row: Int(target), to: &accumulator, excluding: mask)
					}
					mask.drain { _, _ in }
				}
				rows.appendWords(ofRow: index, from: &accumulator)
			} else {
				previousPass.reserveRows(members.count)
				previousPass.removeAllWords()
				for (slot, index) in members.enumerated() {
					memberSlotByNode[Int(index)] = Int32(slot)
					own.add(row: Int(index), to: &accumulator)
					previousPass.appendWords(ofRow: slot, from: &accumulator)
				}
				var changed = true
				while changed {
					changed = false
					pass.reserveRows(members.count)
					pass.removeAllWords()
					/// Adds the row of `target`, a member's from the pass before or a finished one's, without what `mask` holds.
					func add(rowOf target: Int32) {
						let targetSlot = memberSlotByNode[Int(target)]
						if targetSlot >= 0 {
							work += previousPass.wordCount(ofRow: Int(targetSlot))
							if previousPass.add(row: Int(targetSlot), to: &accumulator, excluding: mask) {
								changed = true
							}
						} else {
							work += rows.wordCount(ofRow: Int(target))
							if rows.add(row: Int(target), to: &accumulator, excluding: mask) {
								changed = true
							}
						}
					}
					for (slot, index) in members.enumerated() {
						mask.load(row: Int(index), of: hidden)
						previousPass.add(row: slot, to: &accumulator)
						for edgeIndex in graph.edgeIndices(from: Int(index)) where followsEdge(edgeIndex) {
							let target = graph.edgeTargets[edgeIndex]
							let targetSlot = memberSlotByNode[Int(target)]
							if targetSlot >= 0 {
								work += previousPass.wordCount(ofRow: Int(targetSlot))
								if accumulate(row: Int(targetSlot), of: previousPass, excludingAt: edgeIndex, of: Int(index)) {
									changed = true
								}
							} else {
								work += rows.wordCount(ofRow: Int(target))
								if accumulate(row: Int(target), of: rows, excludingAt: edgeIndex, of: Int(index)) {
									changed = true
								}
							}
						}
						mask.drain { _, _ in }
						if let madeAgain {
							mask.load(row: Int(index), of: madeAgain.rebound)
							for target in madeAgain.targets(of: Int(index)) {
								add(rowOf: target)
							}
							mask.drain { _, _ in }
						}
						pass.appendWords(ofRow: slot, from: &accumulator)
					}
					swap(&previousPass, &pass)
				}
				for (slot, index) in members.enumerated() {
					previousPass.add(row: slot, to: &accumulator)
					rows.appendWords(ofRow: Int(index), from: &accumulator)
					memberSlotByNode[Int(index)] = -1
				}
			}
		}
		self.rows = rows
		self.work = work
	}

	/// The reads of each node's subtree from above it.
	let rows: BitRows

	/// The words the fold read from its edges' targets, summed over every pass, for a test to count how its work grows.
	let work: Int

	/// What the node's subtree reads from above it, in increasing ID order.
	func reads(of index: Int) -> [Int32] {
		rows.columns(inRow: index)
	}
}
