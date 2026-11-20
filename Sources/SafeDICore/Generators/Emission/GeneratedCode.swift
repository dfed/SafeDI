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

/// The code a scope generated, held as the pieces it is written from until it is written out once.
///
/// A scope's code holds its children's code, and each scope used to indent its whole subtree's text again, so a line was
/// indented once for each level above it, and a chain of scopes took time growing with the cube of its depth. A piece
/// holds its text and the indentation still owed to it: indenting a scope's code adds to the indentation of each piece,
/// and a piece's text is indented once, where the code is written out (`written`), with the same bytes
/// `GeneratedCodeText.indentingNonEmptyLines` wrote at every level.
struct GeneratedCode: Sendable {
	/// Text, and the indentation still owed to it.
	struct Piece: Sendable {
		/// The number of spaces before each line of `text` that is not empty, whose empty lines are dropped, or `nil` for
		/// `text` as it is written: the code of a scope indented by nothing, as the root of what is generated is.
		var indentation: Int?
		var text: String

		/// `text` as the piece writes it.
		var written: String {
			if let indentation {
				GeneratedCodeText.indentingNonEmptyLines(of: text, by: String(repeating: " ", count: indentation))
			} else {
				text
			}
		}
	}

	/// The pieces, in the order their text is written.
	private(set) var pieces: [Piece]

	/// The code `scopeCode` stands for, its placeholders replaced by its children's code, indented by `whitespace` as
	/// `GeneratedCodeText.indentingNonEmptyLines` indents it, or written as it is where `whitespace` is empty. The
	/// generator indents with spaces alone (`ScopeGenerator.standardIndent`), so a piece owes a number of them.
	init(_ scopeCode: ScopeCode, indentedBy whitespace: String) {
		let indentation = whitespace.utf8.count
		let parts = Self.parts(of: scopeCode)
		if whitespace.isEmpty {
			// Written out here: a scope indented by nothing is the root of what is generated, or of a fill's statements,
			// whose text is written as it is.
			var text = ""
			for part in parts {
				switch part {
				case let .text(partText):
					text += partText
				case let .child(index, extraIndentation):
					text += scopeCode.children[index].indented(by: extraIndentation).written
				}
			}
			pieces = [Piece(indentation: nil, text: text)]
		} else {
			var pieces = [Piece]()
			for part in parts {
				switch part {
				case let .text(partText):
					pieces.append(Piece(indentation: indentation, text: partText))
				case let .child(index, extraIndentation):
					pieces += scopeCode.children[index].indented(by: indentation + extraIndentation).pieces
				}
			}
			self.pieces = pieces
		}
	}

	/// The code as it is written.
	var written: String {
		Self.joined(pieces.map(\.written))
	}

	/// The pieces' text as written, joined as `written` joins it.
	private static func joined(_ writtenPieces: [String]) -> String {
		if writtenPieces.count == 1 {
			writtenPieces[0]
		} else {
			writtenPieces.filter { !$0.isEmpty }.joined(separator: "\n")
		}
	}

	/// The code `scopeCode` stands for as the root of what is generated, written as `init(_:indentedBy:)` writes it with no
	/// whitespace, with its pieces indented by concurrent tasks. Every piece is indented on its own, so the root's code is
	/// written on as many cores as the scopes' code was generated on, where one task indenting every line of a large tree
	/// took longer than generating it.
	static func writtenAsRoot(_ scopeCode: ScopeCode) async -> String {
		let parts = parts(of: scopeCode)
		var children = [GeneratedCode]()
		for part in parts {
			if case let .child(index, extraIndentation) = part {
				children.append(scopeCode.children[index].indented(by: extraIndentation))
			}
		}
		var writtenChildren = await writtenConcurrently(children).makeIterator()
		var text = ""
		for part in parts {
			switch part {
			case let .text(partText):
				text += partText
			case .child:
				text += writtenChildren.next() ?? ""
			}
		}
		return text
	}

	/// What each of `codes` writes, as `written` writes it, from its pieces indented in chunks of about the same size by
	/// concurrent tasks.
	private static func writtenConcurrently(_ codes: [GeneratedCode]) async -> [String] {
		let pieces = codes.flatMap(\.pieces)
		let totalSize = pieces.reduce(0) { $0 + $1.text.utf8.count }
		let chunkSize = max(minimumChunkSize, totalSize / (ProcessInfo.processInfo.activeProcessorCount * chunksPerProcessor))
		var chunks = [Range<Int>]()
		var chunkStart = 0
		var size = 0
		for (index, piece) in pieces.enumerated() {
			size += piece.text.utf8.count
			if size >= chunkSize {
				chunks.append(chunkStart..<(index + 1))
				chunkStart = index + 1
				size = 0
			}
		}
		if chunkStart < pieces.count {
			chunks.append(chunkStart..<pieces.count)
		}
		var writtenPieces = [String](repeating: "", count: pieces.count)
		if chunks.count == 1 {
			writtenPieces = pieces.map(\.written)
		} else {
			await withTaskGroup(of: (Range<Int>, [String]).self) { group in
				for chunk in chunks {
					group.addTask { (chunk, pieces[chunk].map(\.written)) }
				}
				for await (chunk, written) in group {
					writtenPieces.replaceSubrange(chunk, with: written)
				}
			}
		}
		var codeStart = 0
		return codes.map { code in
			defer { codeStart += code.pieces.count }
			return joined(Array(writtenPieces[codeStart..<(codeStart + code.pieces.count)]))
		}
	}

	/// The fewest bytes of text a task indents, below which a task costs more than it saves.
	private static let minimumChunkSize = 1 << 16
	/// How many chunks each processor is offered, so that a processor that finishes early takes another.
	private static let chunksPerProcessor = 4

	/// Whether the code, indented by a scope above it, writes a line: every line of a piece owed indentation is written
	/// unless it is empty, and a piece written as it is is never indented again.
	var writesALineWhenIndented: Bool {
		pieces.allSatisfy { $0.indentation != nil } && pieces.contains { $0.text.utf8.contains { $0 != Self.lineFeed } }
	}

	/// This code with `count` more spaces owed to each piece: a piece written as it is is owed them alone, as
	/// `indentingNonEmptyLines` indents text it has not indented before.
	private func indented(by count: Int) -> GeneratedCode {
		guard count > 0 else { return self }
		var code = self
		for index in code.pieces.indices {
			code.pieces[index].indentation = (code.pieces[index].indentation ?? 0) + count
		}
		return code
	}

	/// A part of a scope's text: text of its own, or a placeholder line, which stands for the code of a child.
	private enum Part {
		case text(String)
		/// The child's code, owed the spaces the placeholder's line holds before it.
		case child(index: Int, extraIndentation: Int)
	}

	/// `scopeCode`'s text cut at each placeholder line: the text before a placeholder ends where the placeholder's line
	/// starts, and the text after it starts with the line feed that ends that line. Cutting there writes the same lines
	/// `indentingNonEmptyLines` writes of the whole text, which ends no line at a line feed after a carriage return: the
	/// line before a placeholder is the last of a statement the generator writes, which ends in a token of its own, never
	/// in a carriage return.
	private static func parts(of scopeCode: ScopeCode) -> [Part] {
		guard !scopeCode.children.isEmpty else { return [.text(scopeCode.text)] }
		let bytes = Array(scopeCode.text.utf8)
		var parts = [Part]()
		var textStart = 0
		var lineStart = 0
		while lineStart <= bytes.count {
			let lineEnd = bytes[lineStart...].firstIndex(of: lineFeed) ?? bytes.count
			var markerStart = lineStart
			while markerStart < lineEnd, bytes[markerStart] == space {
				markerStart += 1
			}
			if let index = ScopeCode.childIndex(inPlaceholder: bytes[markerStart..<lineEnd]) {
				if textStart < lineStart {
					parts.append(.text(String(decoding: bytes[textStart..<lineStart], as: UTF8.self)))
				}
				parts.append(.child(index: index, extraIndentation: markerStart - lineStart))
				textStart = lineEnd
			}
			lineStart = lineEnd + 1
		}
		if textStart < bytes.count {
			parts.append(.text(String(decoding: bytes[textStart...], as: UTF8.self)))
		}
		return parts
	}

	private static let space = UInt8(ascii: " ")
	private static let lineFeed = UInt8(ascii: "\n")
}

/// The text a scope writes around its children's code, each child's code standing as a placeholder line of its own
/// (`placeholder(ofChildAt:)`), and the children's code.
struct ScopeCode: Sendable {
	let text: String
	let children: [GeneratedCode]

	init(text: String, children: [GeneratedCode] = []) {
		self.text = text
		self.children = children
	}

	/// The line that stands for the code of the child at `index` among `children`. The unit separator is a control
	/// character, which Swift accepts in no source outside a string literal or a comment, and only the text a scope writes
	/// around its children holds a placeholder: their code is held apart.
	static func placeholder(ofChildAt index: Int) -> String {
		"\u{1F}\(index)\u{1F}"
	}

	/// The index of the child `bytes` is the placeholder of, or `nil` where they are no placeholder.
	fileprivate static func childIndex(inPlaceholder bytes: ArraySlice<UInt8>) -> Int? {
		guard bytes.count >= 3, bytes.first == unitSeparator, bytes.last == unitSeparator else { return nil }
		let digits = bytes.dropFirst().dropLast()
		guard digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return nil }
		return Int(String(decoding: digits, as: UTF8.self))
	}

	private static let unitSeparator = UInt8(0x1F)
}
