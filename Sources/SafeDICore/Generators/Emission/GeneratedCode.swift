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
/// written one after another, a child's code each level indents, and the places of the body's walk.
///
/// Each level of a tree used to indent its whole subtree's text again, so a place's text was copied once per level above
/// it, and every scope's cache held its subtree's text. A level now holds its children's plans, and the root's plan is
/// spelled once (`spelled()`), each line written with the indentation of every level around it. The bytes are the ones
/// re-indenting at every level wrote (`GeneratedCodeText.indentingNonEmptyLines`), which `GeneratedCodeTests` checks.
///
/// A plan can be as deep as the module has types, so everything that reads one walks it with a stack of its own, and
/// a level releases its children after its own release returns rather than within it (`Children`): a plan's last owner
/// can be a temporary, and releasing a plan nested once per level from within each level's release overflowed the
/// stack of a concurrency thread on a chain 1,500 types deep.
struct GeneratedCode: Sendable {
	/// What a level of the plan is, read from its storage.
	enum Node {
		/// Text, written as it is.
		case text(String)
		/// Pieces written one after another.
		case sequence([GeneratedCode])
		/// Pieces written one after another with a line feed between each two, as `joined(separator: "\n")` writes
		/// strings.
		case lines([GeneratedCode])
		/// `code`, each of whose lines that is not empty is written after `indentation`, with the empty ones left out and
		/// no line feed after the last, as `GeneratedCodeText.indentingNonEmptyLines(of:by:)` writes text. Empty
		/// `indentation` writes `code` as it is: a scope generated with no leading whitespace keeps its empty lines.
		case indented(GeneratedCode, by: String)
		/// A place of the body's walk (`PlacePlan`), whose code is written as it is.
		case place(PlacePlan)
	}

	/// Text, written as it is.
	static func text(_ text: String) -> GeneratedCode {
		GeneratedCode(storage: .text(text))
	}

	/// Pieces written one after another.
	static func sequence(_ pieces: [GeneratedCode]) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.sequence, pieces)))
	}

	/// Pieces written one after another with a line feed between each two.
	static func lines(_ pieces: [GeneratedCode]) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.lines, pieces)))
	}

	/// `code` with each of its lines that is not empty written after `indentation` (`Node.indented`).
	static func indented(_ code: GeneratedCode, by indentation: String) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.indented(indentation), [code])))
	}

	/// A place of the body's walk, whose code is written as it is.
	static func place(_ plan: PlacePlan) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.place(kind: plan.kind, functionNames: plan.functionNames, closedOnFunctionName: plan.closedOnFunctionName), [plan.code])))
	}

	/// The empty code.
	static let empty = GeneratedCode.sequence([])

	/// What this level of the plan is.
	var node: Node {
		switch storage {
		case let .text(text):
			.text(text)
		case let .children(children):
			switch children.kind {
			case .sequence:
				.sequence(children.codes)
			case .lines:
				.lines(children.codes)
			case let .indented(indentation):
				.indented(children.codes[0], by: indentation)
			case let .place(kind, functionNames, closedOnFunctionName):
				.place(PlacePlan(kind: kind, functionNames: functionNames, closedOnFunctionName: closedOnFunctionName, code: children.codes[0]))
			}
		}
	}

	/// The text of the code.
	func spelled() -> String {
		var writer = GeneratedCodeWriter()
		writer.write(self)
		return writer.text
	}

	private enum Storage: Sendable {
		case text(String)
		case children(Children)
	}

	/// The codes a level holds, which its release hands to `DeferredRelease` so that releasing a deep plan nests no
	/// release per level.
	private final class Children: Sendable {
		enum Kind: Sendable {
			case sequence
			case lines
			case indented(String)
			case place(kind: PlaceKind, functionNames: [String], closedOnFunctionName: String?)
		}

		init(_ kind: Kind, _ codes: [GeneratedCode]) {
			self.kind = kind
			self.codes = codes
		}

		deinit {
			var codes = [GeneratedCode]()
			swap(&codes, &self.codes)
			DeferredRelease.release(consume codes)
		}

		let kind: Kind
		/// Mutated only by `deinit`, which has the only access.
		nonisolated(unsafe) private(set) var codes: [GeneratedCode]
	}

	private let storage: Storage
}

/// What a body's plan holds for one place of its walk: the place's kind, its builder functions, and its code. A place is a
/// position in a root's tree that the body's ordered walk (ordered children, depth first) reaches: a scope that builds a
/// property, closes a cycle, renames a value, or hosts a seam's code. Its identity is the index at which the walk first
/// reaches it (`PlaceIdentity`, `GeneratedCode.places()`), never a scope's or a generator's identity, which two places can
/// share: a scope's cached code is reached once for every place that holds it.
struct PlacePlan: Sendable {
	/// What the graph holds for the place, which the oracle checks against what each kind holds (`PlaceOracle`).
	let kind: PlaceKind
	/// The names of the builder functions the place declares, in the order it declares them.
	let functionNames: [String]
	/// The name of the function a cycle-closing place calls, the function of the place it repeats; `nil` for every other
	/// place.
	let closedOnFunctionName: String?
	/// The place's code, which holds the plans of the places beneath it.
	let code: GeneratedCode
}

/// The kinds of place a production body's walk reaches, each holding a fixed number of builder functions and closing
/// edges (`.claude/rules/emission-decisions.md`, "Places").
public enum PlaceKind: CaseIterable, Hashable, Sendable {
	/// A property built by a builder function of its own: one function.
	case builtByFunction
	/// A member of a loop of builders whose function takes the parameters a lazy cycle needs: two functions, its own and its
	/// `_received` function.
	case loopMemberWithCycleParameters
	/// A constant built in place, whose function would write nothing but its value: no function, one binding.
	case constantBuiltInPlace
	/// A scope that closes a cycle: no function, and one closing edge to the function of an enclosing place.
	case closesCycle
	/// A member of a loop of builders that closes a cycle: one function, the `_received` function that wraps again the
	/// functions of the loop's members its tree receives, and one closing edge to the function of an enclosing place.
	case loopMemberClosingCycle
	/// A rename of a value: no function.
	case alias
	/// A seam call's fill, or a seam's hole site, hosted as the text the seam emitter writes until seam bodies are planned:
	/// no function the graph holds, and no place beneath it. A hole's site, the seam side, is hosted until the 2.3.1 seam
	/// rework (R2a) deletes today's seam emission; a fill, the caller side, until fills are planned.
	case hostedSeamCode
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
				switch code.node {
				case .text:
					index = measure.end
				case let .place(plan):
					if measure.size < minimumBlockSize {
						index = measure.end
					} else {
						index += 1
						steps.append(.visit(plan.code))
					}
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
				let isLevel = if case let .indented(_, indentation) = code.node {
					!indentation.isEmpty
				} else {
					false
				}
				steps.append(.exit(measures.count, isLevel: isLevel, bytesBefore: bytes, candidatesBefore: candidates))
				measures.append(Measure())
				switch code.node {
				case let .text(text):
					bytes += text.utf8.count
				case let .place(plan):
					steps.append(.visit(plan.code))
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
				switch code.node {
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
				case let .place(plan):
					work.append(.code(plan.code))
				}
			case .lineFeed:
				writeLineFeed(ofLevelAt: levels.count - 1)
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
					write(UnsafeBufferPointer(rebasing: textBytes[start..<end]), ofLevelAt: level)
				}
				if end < textBytes.count {
					writeLineFeed(ofLevelAt: level)
				}
				start = end + 1
			}
		}
	}

	/// Writes `run`, bytes of the text of the level at `level` that hold no line feed and are not empty, or of the plan's
	/// text where `level` is negative.
	///
	/// A level splits its text into lines at each line feed that does not follow a carriage return, since `"\r\n"` is one
	/// `Character`, which `GeneratedCodeText.indentingNonEmptyLines(of:by:)` does not split at, and writes each line that is
	/// not empty after its indentation, with a line feed before every line but its first, into the text of the level around
	/// it. While a level's line has begun, so has the line of every level around it, which holds it, so the last byte of
	/// each such level's text is the last byte written, and a run of a level whose line has begun is written as it is.
	private mutating func write(_ run: UnsafeBufferPointer<UInt8>, ofLevelAt level: Int) {
		// The run begins the line of its level and of each level around it whose line has not begun, innermost first. A
		// level that has written a line writes a line feed into the level around it first, which can end that level's line
		// too. Every line feed comes before the indentations, which are written outermost first.
		var outermostBeginning = level + 1
		while outermostBeginning > 0, !levels[outermostBeginning - 1].lineHasBegun {
			outermostBeginning -= 1
			levels[outermostBeginning].lineHasBegun = true
			if levels[outermostBeginning].hasWrittenALine {
				writeLineFeed(ofLevelAt: outermostBeginning - 1)
			}
			levels[outermostBeginning].hasWrittenALine = true
		}
		for index in outermostBeginning..<(level + 1) {
			bytes.append(contentsOf: levels[index].indentation)
		}
		bytes.append(contentsOf: run)
	}

	/// Writes a line feed of the text of the level at `level`, or of the plan's text where `level` is negative.
	private mutating func writeLineFeed(ofLevelAt level: Int) {
		var level = level
		// A line feed after a carriage return continues the line, as a line feed of the level around it.
		while level >= 0, levels[level].lineHasBegun, bytes.last == Self.carriageReturn {
			level -= 1
		}
		if level < 0 {
			bytes.append(Self.lineFeed)
		} else {
			// A line ends. An empty one is left out.
			levels[level].lineHasBegun = false
		}
	}
}
