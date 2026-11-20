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

import Foundation

/// The code a production body plans, as a tree whose levels share their children's code instead of copying it: text, pieces
/// written one after another, and a child's code each level indents.
///
/// Each level of a tree used to indent its whole subtree's text again, so a scope's text was copied once per level above
/// it, and every scope's cache held its subtree's text. A level now holds its children's plans, and the root's plan is
/// spelled once (`spelled()`), each line written with the indentation of every level around it. The bytes are the ones
/// re-indenting at every level wrote (`GeneratedCodeText.indentingNonEmptyLines`), which `GeneratedCodeTests` checks.
///
/// A plan can be as deep as the module has types, so everything that reads one walks it with a stack of its own.
indirect enum GeneratedCode: Hashable, Sendable {
	/// Text, written as it is.
	case text(String)
	/// Pieces written one after another.
	case sequence([GeneratedCode])
	/// Pieces written one after another with a line feed between each two, as `joined(separator: "\n")` writes strings.
	case lines([GeneratedCode])
	/// `code`, each of whose lines that is not empty is written after `indentation`, with the empty ones left out and no line
	/// feed after the last, as `GeneratedCodeText.indentingNonEmptyLines(of:by:)` writes text. Empty `indentation` writes
	/// `code` as it is: a scope generated with no leading whitespace keeps its empty lines.
	case indented(GeneratedCode, by: String)

	/// The empty code.
	static let empty = GeneratedCode.sequence([])

	/// The text of the code.
	func spelled() -> String {
		var writer = GeneratedCodeWriter()
		writer.write(self)
		return writer.text
	}
}

extension GeneratedCode {
	/// The text of the code as the root of what is generated: `spelled()`'s bytes, its larger levels written at their final
	/// indentation in parallel.
	///
	/// The levels written in parallel, the blocks, are levels that indent their code, none inside another, each of at
	/// least `minimumBlockSize` bytes and at most a share of the plan sized so that each processor writes several. Each is
	/// written by a writer of its own, beneath its enclosing levels' indentation, as if each of their lines had ended; the
	/// root's writer then writes the plan, appending a block's bytes where it reaches the block in that state, which it is
	/// in wherever a level begins on a line of its own, and writing the block again where it is not.
	func spelledAsRoot() async -> String {
		await spelledAsRoot(
			minimumBlockSize: Self.minimumBlockSize,
			blockCount: ProcessInfo.processInfo.activeProcessorCount * Self.blocksPerProcessor,
			concurrency: ProcessInfo.processInfo.activeProcessorCount,
			blockWritingOrder: nil,
		)
	}

	/// - Parameters:
	///   - blockCount: How many blocks the plan is shared out into, where its levels are small enough.
	///   - concurrency: How many blocks are written at once.
	///   - blockWritingOrder: For a test, the order in which the blocks are written one after another, given how many
	///     there are, in place of writing them at once.
	func spelledAsRoot(
		minimumBlockSize: Int,
		blockCount: Int,
		concurrency: Int,
		blockWritingOrder: (@Sendable (Int) -> [Int])?,
	) async -> String {
		let blocks = Self.blocks(of: self, minimumBlockSize: minimumBlockSize, blockCount: blockCount)
		guard blocks.count > 1 else { return spelled() }
		var writtenBlocks = [WrittenBlock?](repeating: nil, count: blocks.count)
		if let blockWritingOrder {
			for blockIndex in blockWritingOrder(blocks.count) {
				writtenBlocks[blockIndex] = blocks[blockIndex].written()
			}
		} else {
			await withTaskGroup(of: (Int, WrittenBlock).self) { group in
				var nextBlock = 0
				func addBlockTask() {
					let blockIndex = nextBlock
					let block = blocks[blockIndex]
					nextBlock += 1
					group.addTask { (blockIndex, block.written()) }
				}
				while nextBlock < min(blocks.count, max(1, concurrency)) {
					addBlockTask()
				}
				// Each result is placed by its block's index, so the order in which they finish never reaches the text.
				for await (blockIndex, writtenBlock) in group {
					writtenBlocks[blockIndex] = writtenBlock
					if nextBlock < blocks.count {
						addBlockTask()
					}
				}
			}
		}
		var writer = GeneratedCodeWriter()
		writer.write(self, substituting: writtenBlocks.compactMap(\.self))
		return writer.text
	}

	/// Whether a level's current line has begun, and whether it has written a line.
	struct LevelState: Sendable {
		let lineHasBegun: Bool
		let hasWrittenALine: Bool
	}

	/// A level of a plan to write by a writer of its own.
	struct Block: Sendable {
		/// The index at which a walk of the plan reaches the level, in preorder.
		let index: Int
		/// The index the walk reaches after the level's code.
		let end: Int
		/// The level, an `.indented` code.
		let code: GeneratedCode
		/// The indentation of each level around it, outermost first.
		let enclosingIndentations: [[UInt8]]

		func written() -> WrittenBlock {
			var writer = GeneratedCodeWriter(enclosingIndentations: enclosingIndentations)
			writer.write(code)
			return WrittenBlock(index: index, end: end, bytes: writer.writtenBytes, enclosingLevelStatesAfter: writer.levelStates)
		}
	}

	/// What a block's writer wrote.
	struct WrittenBlock: Sendable {
		let index: Int
		let end: Int
		let bytes: [UInt8]
		/// The state of each level around the block once the block is written.
		let enclosingLevelStatesAfter: [LevelState]
	}

	/// The levels of `code` to write by writers of their own, in the order a walk reaches them.
	static func blocks(of code: GeneratedCode, minimumBlockSize: Int, blockCount: Int) -> [Block] {
		let measures = measures(of: code, minimumBlockSize: minimumBlockSize)
		guard let total = measures.first?.size else { return [] }
		let largestBlockSize = max(minimumBlockSize, total / max(1, blockCount))
		enum Step {
			case visit(GeneratedCode)
			case endOfLevel
		}
		var blocks = [Block]()
		var enclosingIndentations = [[UInt8]]()
		var steps = [Step.visit(code)]
		var index = 0
		while let step = steps.popLast() {
			switch step {
			case let .visit(code):
				let measure = measures[index]
				switch code {
				case .text:
					index = measure.end
				case let .sequence(pieces), let .lines(pieces):
					if measure.size < minimumBlockSize {
						index = measure.end
					} else {
						index += 1
						for piece in pieces.reversed() {
							steps.append(.visit(piece))
						}
					}
				case let .indented(inner, indentation):
					if measure.size < minimumBlockSize {
						index = measure.end
					} else if indentation.isEmpty {
						index += 1
						steps.append(.visit(inner))
					} else if measure.size > largestBlockSize, measure.holdsBlockCandidate {
						// Shared out among the blocks inside it.
						index += 1
						enclosingIndentations.append(Array(indentation.utf8))
						steps.append(.endOfLevel)
						steps.append(.visit(inner))
					} else {
						blocks.append(Block(index: index, end: measure.end, code: code, enclosingIndentations: enclosingIndentations))
						index = measure.end
					}
				}
			case .endOfLevel:
				enclosingIndentations.removeLast()
			}
		}
		return blocks
	}

	/// What a walk of a plan finds of one code it reaches.
	private struct Measure {
		/// The index the walk reaches after the code.
		var end = 0
		/// The bytes of the code's text, counting a line feed between two lines and no indentation.
		var size = 0
		/// Whether a level inside the code that indents it holds at least the fewest bytes a block holds.
		var holdsBlockCandidate = false
	}

	/// What a walk of `code` finds of each code it reaches, in preorder.
	private static func measures(of code: GeneratedCode, minimumBlockSize: Int) -> [Measure] {
		enum Step {
			case visit(GeneratedCode)
			case exit(Int, isLevel: Bool, bytesBefore: Int, candidatesBefore: Int)
		}
		var measures = [Measure]()
		var bytes = 0
		var candidates = 0
		var steps = [Step.visit(code)]
		while let step = steps.popLast() {
			switch step {
			case let .visit(code):
				let isLevel = if case let .indented(_, indentation) = code {
					!indentation.isEmpty
				} else {
					false
				}
				steps.append(.exit(measures.count, isLevel: isLevel, bytesBefore: bytes, candidatesBefore: candidates))
				measures.append(Measure())
				switch code {
				case let .text(text):
					bytes += text.utf8.count
				case let .sequence(pieces):
					for piece in pieces.reversed() {
						steps.append(.visit(piece))
					}
				case let .lines(pieces):
					bytes += max(0, pieces.count - 1)
					for piece in pieces.reversed() {
						steps.append(.visit(piece))
					}
				case let .indented(inner, _):
					steps.append(.visit(inner))
				}
			case let .exit(index, isLevel, bytesBefore, candidatesBefore):
				let size = bytes - bytesBefore
				measures[index] = Measure(end: measures.count, size: size, holdsBlockCandidate: candidates > candidatesBefore)
				if isLevel, size >= minimumBlockSize {
					candidates += 1
				}
			}
		}
		return measures
	}

	/// The fewest bytes a block holds: a smaller one is written faster than its task is started.
	static let minimumBlockSize = 1 << 16
	/// How many blocks each processor writes, where the plan's levels are small enough: several, so that one large block
	/// does not keep the others waiting.
	static let blocksPerProcessor = 4
}

/// Writes a plan's text, keeping for each level around the current piece whether its current line has begun, so each line
/// is written once, after the indentation of every level around it, and no level's text is written again.
struct GeneratedCodeWriter {
	private static let lineFeed = UInt8(ascii: "\n")
	private static let carriageReturn = UInt8(ascii: "\r")

	/// A level that indents its code's lines.
	private struct Level {
		let indentation: [UInt8]
		/// Whether the level's current line has begun: a line begins with its first byte, and ends with a line feed.
		var lineHasBegun = false
		/// Whether the level has written a line, so that the next one it begins is written after a line feed.
		var hasWrittenALine = false
	}

	/// What is left to write, last first.
	private enum Work {
		case code(GeneratedCode)
		/// The line feed `.lines` writes between two pieces, in the text of the innermost level.
		case lineFeed
		/// The end of the innermost level's code. A line feed after its last line is left out with the empty line it begins.
		case endOfLevel
	}

	private var bytes = [UInt8]()
	private var levels = [Level]()
	/// The pieces a line's beginning still has to write, last first.
	private var pending = [Piece]()

	var text: String {
		String(decoding: bytes, as: UTF8.self)
	}

	/// A writer that writes code beneath `enclosingIndentations`, as the levels of a plan around it whose lines have each
	/// been written and ended: the state in which `spelledAsRoot()` writes a block.
	init(enclosingIndentations: [[UInt8]] = []) {
		levels = enclosingIndentations.map { Level(indentation: $0, lineHasBegun: false, hasWrittenALine: true) }
	}

	/// Whether each level around the code written next has begun its current line and has written a line.
	var levelStates: [GeneratedCode.LevelState] {
		levels.map { GeneratedCode.LevelState(lineHasBegun: $0.lineHasBegun, hasWrittenALine: $0.hasWrittenALine) }
	}

	/// The bytes written so far.
	var writtenBytes: [UInt8] {
		bytes
	}

	/// Writes `code`. Each of `blocks`, in the order the walk reaches them, a block of the plan written beforehand by a
	/// writer of its own, is appended as that writer wrote it where this writer is in the state that writer began in, and
	/// written again otherwise.
	mutating func write(_ code: GeneratedCode, substituting blocks: [GeneratedCode.WrittenBlock] = []) {
		var work = [Work.code(code)]
		// The index of the next code the walk reaches, in the order `GeneratedCode.blocks(of:…)` numbers them.
		var codeIndex = 0
		var nextBlock = 0
		while let next = work.popLast() {
			switch next {
			case let .code(code):
				let index = codeIndex
				codeIndex += 1
				if nextBlock < blocks.count, blocks[nextBlock].index == index {
					let block = blocks[nextBlock]
					nextBlock += 1
					if beginsLineAfterEveryEnclosingLevelsLine {
						// The block's writer began in this writer's state, so it wrote what this writer would.
						if !block.bytes.isEmpty {
							bytes.append(contentsOf: block.bytes)
							for (levelIndex, state) in block.enclosingLevelStatesAfter.enumerated() {
								levels[levelIndex].lineHasBegun = state.lineHasBegun
								levels[levelIndex].hasWrittenALine = state.hasWrittenALine
							}
						}
						codeIndex = block.end
						continue
					}
				}
				switch code {
				case let .text(text):
					write(text)
				case let .sequence(pieces):
					for piece in pieces.reversed() {
						work.append(.code(piece))
					}
				case let .lines(pieces):
					for (index, piece) in pieces.enumerated().reversed() {
						work.append(.code(piece))
						if index > 0 {
							work.append(.lineFeed)
						}
					}
				case let .indented(code, indentation):
					if indentation.isEmpty {
						work.append(.code(code))
					} else {
						levels.append(Level(indentation: Array(indentation.utf8)))
						work.append(.endOfLevel)
						work.append(.code(code))
					}
				}
			case .lineFeed:
				write(.lineFeed(level: levels.count - 1))
			case .endOfLevel:
				levels.removeLast()
			}
		}
	}

	/// Whether a level pushed now writes the bytes it writes beneath levels whose lines have each been written and ended:
	/// the innermost level's line has ended, after a line, and no carriage return precedes, which a line feed beginning the
	/// next line would continue. A level whose line has begun around it writes the same bytes as one whose line has ended,
	/// since a line the innermost level begins ends and begins each line around it.
	private var beginsLineAfterEveryEnclosingLevelsLine: Bool {
		guard let innermost = levels.last else { return true }
		return !innermost.lineHasBegun && innermost.hasWrittenALine && bytes.last != Self.carriageReturn
	}

	private mutating func write(_ text: String) {
		var text = text
		text.withUTF8 { textBytes in
			let level = levels.count - 1
			var start = 0
			while start <= textBytes.count {
				var end = start
				while end < textBytes.count, textBytes[end] != Self.lineFeed {
					end += 1
				}
				if end > start {
					write(.bytes(UnsafeBufferPointer(rebasing: textBytes[start..<end]), level: level))
				}
				if end < textBytes.count {
					write(.lineFeed(level: level))
				}
				start = end + 1
			}
		}
	}

	/// A run of bytes to write as part of the text of the level at `level`, or of the plan's text where `level` is negative.
	private enum Piece {
		/// Bytes that hold no line feed.
		case bytes(UnsafeBufferPointer<UInt8>, level: Int)
		/// The indentation of the level at `levelIndex`.
		case indentation(ofLevelAt: Int, level: Int)
		case lineFeed(level: Int)
	}

	/// Writes `piece`.
	///
	/// A level splits its text into lines at each line feed that does not follow a carriage return, since `"\r\n"` is one
	/// `Character`, which `GeneratedCodeText.indentingNonEmptyLines(of:by:)` does not split at, and writes each line that is
	/// not empty after its indentation, with a line feed before every line but its first, into the text of the level around
	/// it. While a level's line has begun, so has the line of every level around it, which holds it, so the last byte of
	/// each such level's text is the last byte written.
	private mutating func write(_ piece: Piece) {
		// A line that begins writes its line feed and indentation into the level around it, which can begin a line there
		// too, so the levels are walked outward, each run written at the level it belongs to. The stack is the writer's, so
		// a line's beginning allocates nothing.
		pending.removeAll(keepingCapacity: true)
		pending.append(piece)
		while let piece = pending.popLast() {
			switch piece {
			case let .bytes(run, level):
				if level < 0 {
					bytes.append(contentsOf: run)
				} else {
					write(.bytes(run, level: level - 1), beginningLineAt: level)
				}
			case let .indentation(levelIndex, level):
				if level < 0 {
					bytes.append(contentsOf: levels[levelIndex].indentation)
				} else {
					write(.indentation(ofLevelAt: levelIndex, level: level - 1), beginningLineAt: level)
				}
			case let .lineFeed(level):
				if level < 0 {
					bytes.append(Self.lineFeed)
				} else if levels[level].lineHasBegun, bytes.last == Self.carriageReturn {
					// A line feed after a carriage return continues the line.
					pending.append(.lineFeed(level: level - 1))
				} else {
					// A line ends. An empty one is left out.
					levels[level].lineHasBegun = false
				}
			}
		}
	}

	/// Writes `run`, a run of bytes of the level at `level` that holds no line feed and is not empty, as the run of the
	/// level around it that it is, after the line feed and indentation that begin the level's line where it has not begun.
	private mutating func write(_ run: Piece, beginningLineAt level: Int) {
		let outer = level - 1
		// Pushed last first, so they are written in order.
		pending.append(run)
		if !levels[level].lineHasBegun {
			levels[level].lineHasBegun = true
			pending.append(.indentation(ofLevelAt: level, level: outer))
			if levels[level].hasWrittenALine {
				pending.append(.lineFeed(level: outer))
			}
			levels[level].hasWrittenALine = true
		}
	}
}
