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

/// Text transforms the generator runs at every node of a tree, over UTF-8 bytes. Splitting a `String` into `Character`s,
/// or rewriting it through Foundation, at every node made them a quarter or more of `generate`’s time on deep or
/// mock-heavy trees.
enum GeneratedCodeText {
	/// `code` with `whitespace` before each of its lines, and without its empty lines: the same bytes as
	/// `code.split(separator: "\n").map { whitespace + $0 }.joined(separator: "\n")`.
	static func indentingNonEmptyLines(of code: String, by whitespace: String) -> String {
		let lineFeed = UInt8(ascii: "\n")
		let carriageReturn = UInt8(ascii: "\r")
		let indentation = Array(whitespace.utf8)
		var code = code
		let result = code.withUTF8 { bytes in
			// Splitting on `"\n"` compares `Character`s, and `"\r\n"` is one `Character`, which is no `"\n"`: its line feed
			// ends no line. A line feed is a `Character` of its own everywhere else.
			let lineEnds = bytes.indices.filter { index in
				bytes[index] == lineFeed && (index == bytes.startIndex || bytes[index - 1] != carriageReturn)
			}
			var result = [UInt8]()
			result.reserveCapacity(bytes.count + (lineEnds.count + 1) * indentation.count)
			let lineStarts = [bytes.startIndex] + lineEnds.map { $0 + 1 }
			let lines = zip(lineStarts, lineEnds + [bytes.endIndex]).map { lineStart, lineEnd in lineStart..<lineEnd }
			for line in lines where !line.isEmpty {
				// A line written before this one ends with the separator `joined` puts between lines.
				if !result.isEmpty {
					result.append(lineFeed)
				}
				result.append(contentsOf: indentation)
				result.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[line]))
			}
			return result
		}
		return String(decoding: result, as: UTF8.self)
	}

	/// The name a mock gives what it reads from the override at `nodePath`, a path of labels below
	/// `safeDIOverrides` joined by `.`: the path without each `safeDIOverrides.`, its labels joined by `_`. The same bytes
	/// as Foundation’s replacing every `"safeDIOverrides."` with `""` and then every `"."` with `"_"`, unless a `.` forms
	/// one `Character` with the scalar after it: a label may start with a scalar that extends the character before it
	/// (U+064B, a zero-width joiner, or a raw identifier’s combining accent). Foundation’s search, which matches whole
	/// `Character`s, kept such a `.`, which left the name uncompilable; this pass rewrites every `.`, as intended.
	static func overrideRelativePath(of nodePath: String) -> String {
		let period = UInt8(ascii: ".")
		let underscore = UInt8(ascii: "_")
		let removedPrefix = Array("\(ReservedName.mockOverridesParameterName).".utf8)
		let bytes = Array(nodePath.utf8)
		var result = [UInt8]()
		result.reserveCapacity(bytes.count)
		var index = bytes.startIndex
		while index < bytes.endIndex {
			if bytes[index...].starts(with: removedPrefix) {
				index += removedPrefix.count
			} else {
				let byte = bytes[index]
				result.append(byte == period ? underscore : byte)
				index += 1
			}
		}
		return String(decoding: result, as: UTF8.self)
	}

	/// `text` without what an integration or a checkout spells its own way, for the text a name is hashed from: on each
	/// line, the comment that ends it (from the first `" // "`: a seam call's guard names how each integration compiles the
	/// seam's module, and `// Declared at` names a file by the path the integration hands `generate`), and the directory
	/// of the file a `#sourceLocation(file:line:)` directive before it names. The same bytes as splitting `text` on
	/// `"\n"`, cutting each line at Foundation’s `range(of:)` of each part, and joining the lines with `"\n"`, unless a
	/// part forms one `Character` with a scalar beside it, which Foundation’s search, matching whole `Character`s, does
	/// not find: this pass finds every part's bytes. A line feed after a carriage return ends no line, as `"\r\n"` is one
	/// `Character`, which is no `"\n"`. A seam's fill bodies are named by this text, and Foundation's search over each
	/// body's whole text was a third of `generate`'s time where fills share bodies.
	static func withoutIntegrationSpellings(_ text: String) -> String {
		let bytes = Array(text.utf8)
		guard firstIndex(of: trailingComment, in: bytes, from: 0, upTo: bytes.count) != nil
			|| firstIndex(of: sourceLocationFile, in: bytes, from: 0, upTo: bytes.count) != nil
		else { return text }
		let lineFeed = UInt8(ascii: "\n")
		let carriageReturn = UInt8(ascii: "\r")
		let slash = UInt8(ascii: "/")
		var result = [UInt8]()
		result.reserveCapacity(bytes.count)
		var lineStart = 0
		var searchStart = 0
		while true {
			var lineEnd = bytes[searchStart...].firstIndex(of: lineFeed) ?? bytes.count
			while lineEnd < bytes.count, lineEnd > lineStart, bytes[lineEnd - 1] == carriageReturn {
				lineEnd = bytes[(lineEnd + 1)...].firstIndex(of: lineFeed) ?? bytes.count
			}
			let codeEnd = firstIndex(of: trailingComment, in: bytes, from: lineStart, upTo: lineEnd) ?? lineEnd
			if let directive = firstIndex(of: sourceLocationFile, in: bytes, from: lineStart, upTo: codeEnd),
			   case let pathStart = directive + sourceLocationFile.count,
			   let closing = firstIndex(of: sourceLocationLine, in: bytes, from: pathStart, upTo: codeEnd)
			{
				result.append(contentsOf: bytes[lineStart..<pathStart])
				result.append(contentsOf: bytes[(bytes[pathStart..<closing].lastIndex(of: slash).map { $0 + 1 } ?? pathStart)..<codeEnd])
			} else {
				result.append(contentsOf: bytes[lineStart..<codeEnd])
			}
			guard lineEnd < bytes.count else { break }
			result.append(lineFeed)
			lineStart = lineEnd + 1
			searchStart = lineStart
		}
		return String(decoding: result, as: UTF8.self)
	}

	private static let trailingComment = Array(" // ".utf8)
	private static let sourceLocationFile = Array("#sourceLocation(file: \"".utf8)
	private static let sourceLocationLine = Array("\", line: ".utf8)

	/// The first index at or after `start` where `part` lies wholly before `end` in `bytes`.
	private static func firstIndex(of part: [UInt8], in bytes: [UInt8], from start: Int, upTo end: Int) -> Int? {
		guard end - start >= part.count else { return nil }
		for index in start...(end - part.count) where bytes[index] == part[0] && bytes[index..<(index + part.count)].elementsEqual(part) {
			return index
		}
		return nil
	}
}
