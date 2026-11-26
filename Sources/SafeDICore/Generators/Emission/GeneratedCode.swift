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
		/// A function the root may declare once at its top (`RootFunctionHoisting`), written as `inPlace` where it does not.
		case rootFunction(RootFunctionRecord, inPlace: GeneratedCode)
		/// The body of a `@Sendable` function, written as it is, which calls only functions that are `@Sendable` too.
		case sendableFunction(GeneratedCode)
		/// `code` without the root functions named `names`, which the root declares at its top.
		case omittingRootFunctions(GeneratedCode, named: Set<String>)
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

	/// The text of the code without its root functions, and the names of those it holds, in the order it reaches them: the
	/// text a place's record holds where the root declares them from the place's plan.
	func spelledWithoutRootFunctions() -> (text: String, rootFunctionNames: [String]) {
		let names = RootFunctionHoisting.records(in: [self]).map(\.name)
		return (GeneratedCode.omittingRootFunctions(self, named: Set(names)).spelled(), names)
	}

	/// A place of the body's walk (`PlacePlan`), whose code is written as it is.
	static func place(_ plan: PlacePlan) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.place(record: plan.record, laysOut: TypeKeyLayout.laysOut(placeRecordedAs: plan.record)), [plan.code])))
	}

	/// A function the root may declare once at its top, written as the call declares it where the root does not
	/// (`Node.rootFunction`).
	static func rootFunction(_ record: RootFunctionRecord) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.rootFunction(record), [record.spelled(isSendable: record.isSendable)])))
	}

	/// The body of a `@Sendable` function (`Node.sendableFunction`).
	static func sendableFunction(_ code: GeneratedCode) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.sendableFunction, [code])))
	}

	/// `code` without the root functions named `names` (`Node.omittingRootFunctions`).
	static func omittingRootFunctions(_ code: GeneratedCode, named names: Set<String>) -> GeneratedCode {
		GeneratedCode(storage: .children(Children(.omittingRootFunctions(names), [code])))
	}

	/// The empty code.
	static let empty = GeneratedCode.sequence([])

	/// Whether the plan holds a root function (`Node.rootFunction`), which its levels record as they are built.
	var holdsRootFunction: Bool {
		switch storage {
		case .text:
			false
		case let .children(children):
			children.holdsRootFunction
		}
	}

	/// Whether this level, under the indentations around it, is a place the type key can lay out with every place of its
	/// tree (`TypeKeyLayout.laysOut(_:)`), which the place records as it is built.
	var isPlaceTheTypeKeyLaysOut: Bool {
		guard case let .children(children) = unindented.storage, case let .place(_, laysOut) = children.kind else { return false }
		return laysOut
	}

	/// Whether the type key can lay out every statement this level stands for in a body, as `TypeKeyLayout.statementCodes(of:)`
	/// reads it: the place it is, or each place of a sequence of places, from what each place recorded as it was built. It
	/// reads the levels' storage, so asking it makes nothing: every place is built with it.
	///
	/// A level that is no sequence is one statement: a place, or a piece that is no place. A body's statements hold no other
	/// node: `.lines` and `.sendableFunction` stand only inside a builder function's own code, beneath its place
	/// (`BuilderFunctionGraph`), `.omittingRootFunctions` only around a root's body, and `.rootFunction` only among the
	/// statements of a body that makes a seam call, whose place the type key never plans.
	var statementsAreLaidOutByTypeKey: Bool {
		guard case let .children(children) = unindented.storage, case .sequence = children.kind else { return isPlaceTheTypeKeyLaysOut }
		// A sequence that holds anything but places is one statement, with no record, as a piece that is no place is.
		return children.codes.allSatisfy(\.isPlaceTheTypeKeyLaysOut)
	}

	/// This level without the indentations around it.
	private var unindented: GeneratedCode {
		var code = self
		while case let .children(children) = code.storage, case .indented = children.kind {
			code = children.codes[0]
		}
		return code
	}

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
			case let .place(record, _):
				.place(PlacePlan(code: children.codes[0], record: record))
			case let .rootFunction(record):
				.rootFunction(record, inPlace: children.codes[0])
			case .sendableFunction:
				.sendableFunction(children.codes[0])
			case let .omittingRootFunctions(names):
				.omittingRootFunctions(children.codes[0], named: names)
			}
		}
	}

	/// The text of the code.
	func spelled() -> String {
		// Text no level indents is written as it is, so it is its own spelling: a mock's text, tens of megabytes on a deep
		// chain, is not copied into the writer's bytes, which grow by doubling, and then into a string again.
		switch node {
		case let .text(text):
			return text
		case .sequence, .lines, .indented, .place, .rootFunction, .sendableFunction, .omittingRootFunctions:
			break
		}
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
			/// `laysOut`: whether the type key can lay out every place of the tree beneath, its own included, which the
			/// places beneath recorded as they were built, so no walk of the tree asks it.
			case place(record: PlaceRecord?, laysOut: Bool)
			case rootFunction(RootFunctionRecord)
			case sendableFunction
			case omittingRootFunctions(Set<String>)
		}

		init(_ kind: Kind, _ codes: [GeneratedCode]) {
			self.kind = kind
			holdsRootFunction = switch kind {
			case .rootFunction:
				true
			case .sequence, .lines, .indented, .place, .sendableFunction, .omittingRootFunctions:
				codes.contains(where: \.holdsRootFunction)
			}
			slot = DeferredReleaseSlot(codes)
		}

		let kind: Kind
		/// Whether the level or a level beneath it is a root function, decided as the level is built from the levels beneath
		/// it, so a walk for root functions skips every level that holds none. Held as long as the level.
		let holdsRootFunction: Bool
		var codes: [GeneratedCode] {
			slot.value
		}

		private let slot: DeferredReleaseSlot<[GeneratedCode]>
	}

	private let storage: Storage
}

/// What a body's plan holds for one place: its code, and what the type key reads of it. A scope's cached code is reached
/// once for every place that holds it.
struct PlacePlan: Sendable {
	/// The place's code, which holds the plans of the places beneath it.
	let code: GeneratedCode
	/// What the type key reads of the place (`TypeKeyBody`), or `nil` for a place it does not plan yet, whose root keeps
	/// the path key's body.
	let record: PlaceRecord?

	init(code: GeneratedCode, record: PlaceRecord? = nil) {
		self.code = code
		self.record = record
	}

	/// This plan, with `record`.
	func with(record: PlaceRecord?) -> PlacePlan {
		PlacePlan(code: code, record: record)
	}
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
		/// The end of the innermost `Node.omittingRootFunctions`.
		case endOfOmission
	}

	private var bytes = [UInt8]()
	private var levels = [Level]()
	/// The indentation of every level, outermost first, so that the indentations a line begins with are one run of it.
	private var indentations = [UInt8]()
	/// The names of the root functions the root declares at its top, which are not written where they are reached.
	private var omittedRootFunctionNames = [Set<String>]()

	var text: String {
		String(decoding: bytes, as: UTF8.self)
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
						indentations.append(contentsOf: indentation.utf8)
						levels.append(Level(indentationEnd: indentations.count))
						work.append(.endOfLevel)
						work.append(.code(code))
					}
				case let .place(plan):
					work.append(.code(plan.code))
				case let .rootFunction(record, inPlace):
					if !omittedRootFunctionNames.contains(where: { $0.contains(record.name) }) {
						work.append(.code(inPlace))
					}
				case let .sendableFunction(code):
					work.append(.code(code))
				case let .omittingRootFunctions(code, names):
					omittedRootFunctionNames.append(names)
					work.append(.endOfOmission)
					work.append(.code(code))
				}
			case .lineFeed:
				writeLineFeed(ofLevelAt: levels.count - 1)
			case .endOfLevel:
				levels.removeLast()
				indentations.removeLast(indentations.count - (levels.last?.indentationEnd ?? 0))
			case .endOfOmission:
				omittedRootFunctionNames.removeLast()
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
