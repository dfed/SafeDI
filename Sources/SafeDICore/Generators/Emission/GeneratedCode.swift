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
/// Each level of a tree used to indent its whole subtree's text again, so a place's text was copied once per level above
/// it, and every scope's cache held its subtree's text. A level now holds its children's plans, and the root's plan is
/// spelled once (`spelled()`), each line written with the indentation of every level around it. A small subtree started
/// early is spelled while the rest of the tree is generated (`Node.spelled`), and the root's spelling copies its text. The bytes are the ones
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
		/// Code spelled while the rest of the tree was being generated, written as its text, with no plan kept.
		case spelled(String)
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

	/// `code`'s text, which a writer writes as it is (`Node.spelled`). The plan is dropped once it is spelled.
	static func spelled(_ code: GeneratedCode) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.spelled(code.spelled()), [])))
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
			case let .spelled(text):
				.spelled(text)
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

	/// The codes a level holds, which its slot hands to `DeferredRelease` when the level is released, so that releasing a
	/// deep plan nests no release per level.
	private final class Children: Sendable {
		enum Kind: Sendable {
			case sequence
			case lines
			case indented(String)
			case spelled(String)
		}

		init(_ kind: Kind, _ codes: [GeneratedCode]) {
			self.kind = kind
			slot = DeferredReleaseSlot(codes)
		}

		let kind: Kind
		var codes: [GeneratedCode] {
			slot.value
		}

		private let slot: DeferredReleaseSlot<[GeneratedCode]>
	}

	private let storage: Storage
}

/// Writes a plan's text, keeping for each level around the current piece whether its current line has begun, so each line
/// is written once, after the indentation of every level around it, and no level's text is written again.
private struct GeneratedCodeWriter {
	private static let lineFeed = UInt8(ascii: "\n")
	private static let carriageReturn = UInt8(ascii: "\r")

	/// A level that indents its code's lines.
	private struct Level {
		/// Where the level's indentation ends in `indentations`.
		let indentationEnd: Int
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
	/// The indentation of every level, outermost first, so that the indentations a line begins with are one run of it.
	private var indentations = [UInt8]()

	var text: String {
		String(decoding: bytes, as: UTF8.self)
	}

	mutating func write(_ code: GeneratedCode) {
		var work = [Work.code(code)]
		while let next = work.popLast() {
			switch next {
			case let .code(code):
				switch code.node {
				case let .text(text), let .spelled(text):
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
						indentations.append(contentsOf: indentation.utf8)
						levels.append(Level(indentationEnd: indentations.count))
						work.append(.endOfLevel)
						work.append(.code(code))
					}
				}
			case .lineFeed:
				writeLineFeed(ofLevelAt: levels.count - 1)
			case .endOfLevel:
				levels.removeLast()
				indentations.removeLast(indentations.count - (levels.last?.indentationEnd ?? 0))
			}
		}
	}

	private mutating func write(_ text: String) {
		var text = text
		text.withUTF8 { textBytes in
			let level = levels.count - 1
			var start = 0
			while start <= textBytes.count {
				var end = textBytes.count
				if start < textBytes.count, let baseAddress = textBytes.baseAddress,
				   let lineFeed = memchr(baseAddress + start, Int32(Self.lineFeed), textBytes.count - start)
				{
					end = baseAddress.distance(to: lineFeed.assumingMemoryBound(to: UInt8.self))
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
		if outermostBeginning <= level {
			let start = outermostBeginning == 0 ? 0 : levels[outermostBeginning - 1].indentationEnd
			bytes.append(contentsOf: indentations[start..<levels[level].indentationEnd])
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
