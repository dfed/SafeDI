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
/// spelled once (`spelled`), each line written with the indentation of every level around it. The bytes are the ones
/// re-indenting at every level wrote (`GeneratedCodeText.indentingNonEmptyLines`).
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
	/// A place of the body's walk (`PlacePlan`), whose code is written as it is.
	case place(PlacePlan)

	/// The empty code.
	static let empty = GeneratedCode.sequence([])

	/// The text of the code. The plan is consumed: a body's plan holds its whole tree, so its pieces are released as they are
	/// written.
	consuming func spelled() -> String {
		var writer = GeneratedCodeWriter()
		writer.write(self)
		return writer.text
	}
}

/// What a body's plan holds for one place of its walk: the place's kind, its builder functions, and its code. A place is a
/// position in a root's tree that the body's ordered walk (ordered children, depth first) reaches: a scope that builds a
/// property, closes a cycle, renames a value, or fills a seam call's hole, or a seam's hole site. Its identity is the
/// index at which the walk first reaches it (`PlaceIdentity`), counted by the body (`BuilderFunctionGraph.places(of:)`),
/// never a scope's or a generator's identity, which two places can share: a plan is one generator's, and its walk index is
/// its position in the body that writes it.
struct PlacePlan: Hashable, Sendable {
	/// What the graph holds for the place, which the oracle checks against what each kind holds.
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
enum PlaceKind: Hashable, Sendable {
	/// A property built by a builder function of its own: one function.
	case builtByFunction
	/// A member of a loop of builders whose function takes the parameters a lazy cycle needs: two functions, its own and its
	/// `_received` function.
	case loopMemberWithCycleParameters
	/// A constant built in place, whose function would write nothing but its value: no function, one binding.
	case constantBuiltInPlace
	/// A scope that closes a cycle: no function, and one closing edge to the function of the place it repeats.
	case closesCycle
	/// A rename of a value: no function.
	case alias
	/// A seam call's fill, or a seam's hole site, hosted as the text the seam emitter writes until seam bodies are planned:
	/// no function the graph holds, and no place beneath it.
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

	private var bytes = [UInt8]()
	private var levels = [Level]()

	var text: String {
		String(decoding: bytes, as: UTF8.self)
	}

	mutating func write(_ code: consuming GeneratedCode) {
		switch consume code {
		case let .text(text):
			write(text)
		case let .sequence(pieces):
			for piece in pieces {
				write(piece)
			}
		case let .lines(pieces):
			for (index, piece) in pieces.enumerated() {
				if index > 0 {
					write(Self.lineFeed, atLevel: levels.count - 1)
				}
				write(piece)
			}
		case let .indented(code, indentation):
			if indentation.isEmpty {
				write(code)
			} else {
				levels.append(Level(indentation: Array(indentation.utf8)))
				write(code)
				// A line feed after the code's last line is left out with the empty line it begins.
				levels.removeLast()
			}
		case let .place(plan):
			write(plan.code)
		}
	}

	private mutating func write(_ text: String) {
		var text = text
		text.withUTF8 { textBytes in
			let level = levels.count - 1
			for byte in textBytes {
				// Nearly every byte continues a line every level has begun.
				if byte != Self.lineFeed, level < 0 || levels[level].lineHasBegun {
					bytes.append(byte)
				} else {
					write(byte, atLevel: level)
				}
			}
		}
	}

	/// Writes `byte` as a byte of the text of the level at `level`, or of the plan's text where `level` is negative.
	///
	/// A level splits its text into lines at each line feed that does not follow a carriage return, since `"\r\n"` is one
	/// `Character`, which `GeneratedCodeText.indentingNonEmptyLines(of:by:)` does not split at, and writes each line that is
	/// not empty after its indentation, with a line feed before every line but its first, into the text of the level around
	/// it. While a level's line has begun, so has the line of every level around it, which holds it, so the last byte of
	/// each such level's text is the last byte written.
	private mutating func write(_ byte: UInt8, atLevel level: Int) {
		guard level >= 0 else {
			bytes.append(byte)
			return
		}
		if byte == Self.lineFeed, !(levels[level].lineHasBegun && bytes.last == Self.carriageReturn) {
			// A line ends. An empty one is left out.
			levels[level].lineHasBegun = false
		} else {
			if !levels[level].lineHasBegun {
				if levels[level].hasWrittenALine {
					write(Self.lineFeed, atLevel: level - 1)
				}
				for indentationByte in levels[level].indentation {
					write(indentationByte, atLevel: level - 1)
				}
				levels[level].lineHasBegun = true
				levels[level].hasWrittenALine = true
			}
			write(byte, atLevel: level - 1)
		}
	}
}
