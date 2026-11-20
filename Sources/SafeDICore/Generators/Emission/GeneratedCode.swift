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

	/// The text of the code's lines that hold more than whitespace, joined by line feeds
	/// (`GeneratedCodeText.nonBlankLinesJoined(ofUTF8:)`), read from the bytes the code is spelled into, so the text is
	/// held once rather than spelled into a string and copied again without its blank lines.
	func spelledNonBlankLines() -> String {
		var writer = GeneratedCodeWriter()
		writer.write(self)
		return writer.nonBlankLinesJoined
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

/// Writes a plan's text, keeping for each level around the current piece whether its current line has begun, so each line
/// is written once, after the indentation of every level around it, and no level's text is written again.
private struct GeneratedCodeWriter {
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

	var nonBlankLinesJoined: String {
		bytes.withUnsafeBufferPointer(GeneratedCodeText.nonBlankLinesJoined(ofUTF8:))
	}

	mutating func write(_ code: GeneratedCode) {
		var work = [Work.code(code)]
		while let next = work.popLast() {
			switch next {
			case let .code(code):
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
				write(.lineFeed(level: levels.count - 1))
			case .endOfLevel:
				levels.removeLast()
			}
		}
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
				// Where the level's line has begun, so has every line around it, so the run is written as it is: walking
				// it out through every level made a chain of levels write each byte once per level around it.
				if level < 0 || levels[level].lineHasBegun {
					bytes.append(contentsOf: run)
				} else {
					write(.bytes(run, level: level - 1), beginningLineAt: level)
				}
			case let .indentation(levelIndex, level):
				if level < 0 || levels[level].lineHasBegun {
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

	/// Writes `run`, a run of bytes of the level at `level`, whose line has not begun, that holds no line feed and is not
	/// empty, as the run of the level around it that it is, after the line feed and indentation that begin the level's line.
	private mutating func write(_ run: Piece, beginningLineAt level: Int) {
		let outer = level - 1
		// Pushed last first, so they are written in order.
		pending.append(run)
		levels[level].lineHasBegun = true
		pending.append(.indentation(ofLevelAt: level, level: outer))
		if levels[level].hasWrittenALine {
			pending.append(.lineFeed(level: outer))
		}
		levels[level].hasWrittenALine = true
	}
}
