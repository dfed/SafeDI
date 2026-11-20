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

	/// The lines of `code` that hold more than whitespace, joined by line feeds: the same bytes as
	/// `code.components(separatedBy: "\n").filter { !$0.allSatisfy(\.isWhitespace) }.joined(separator: "\n")`, written
	/// into one string of `code`'s size rather than a string per line, which a mock body as large as the module's mocks
	/// would hold beside the text they are joined into. Code with a carriage return, which forms one `Character` with a
	/// line feed after it, takes that expression itself.
	static func nonBlankLinesJoined(of code: String) -> String {
		let lineFeed = UInt8(ascii: "\n")
		let carriageReturn = UInt8(ascii: "\r")
		var code = code
		return code.withUTF8 { bytes in
			guard !bytes.contains(carriageReturn) else {
				return String(decoding: bytes, as: UTF8.self)
					.components(separatedBy: "\n")
					.filter { !$0.allSatisfy(\.isWhitespace) }
					.joined(separator: "\n")
			}
			// Written straight into the string's storage, reserved at the code's size, which no line it drops makes too small:
			// a buffer of bytes decoded into a string afterwards would hold the text twice.
			return String(unsafeUninitializedCapacity: bytes.count) { result in
				var count = 0
				var lineStart = bytes.startIndex
				for index in bytes.indices where bytes[index] == lineFeed {
					appendIfNotBlank(UnsafeBufferPointer(rebasing: bytes[lineStart..<index]), to: result, count: &count)
					lineStart = index + 1
				}
				appendIfNotBlank(UnsafeBufferPointer(rebasing: bytes[lineStart...]), to: result, count: &count)
				return count
			}
		}
	}

	/// Writes `line` into `result` after its first `count` bytes, after a line feed where `result` holds a line already,
	/// unless every `Character` of it is whitespace. A line of ASCII bytes is judged by its bytes, the ASCII whitespace
	/// `Character.isWhitespace` accepts being the space and U+0009 to U+000D.
	private static func appendIfNotBlank(_ line: UnsafeBufferPointer<UInt8>, to result: UnsafeMutableBufferPointer<UInt8>, count: inout Int) {
		let isASCII = line.allSatisfy { $0 < 0x80 }
		let isBlank = if isASCII {
			line.allSatisfy { $0 == UInt8(ascii: " ") || (0x09...0x0D).contains($0) }
		} else {
			String(decoding: line, as: UTF8.self).allSatisfy(\.isWhitespace)
		}
		if !isBlank {
			if count > 0 {
				result[count] = UInt8(ascii: "\n")
				count += 1
			}
			_ = UnsafeMutableBufferPointer(rebasing: result[count..<(count + line.count)]).initialize(from: line)
			count += line.count
		}
	}

	/// `lines` joined by line feeds, between `#if <condition>` and `#endif` where there is a condition: the bytes of
	/// `lines.joined(separator: "\n")` so wrapped, written into one string reserved at its size, since a module's mocks
	/// can be tens of megabytes, which a join that grows its string by doubling would hold twice over.
	static func joined(_ lines: [String], wrappedInConditionalCompilation condition: String?) -> String {
		var size = lines.reduce(lines.count) { $0 + $1.utf8.count }
		if let condition {
			size += "#if \(condition)\n\n#endif".utf8.count
		}
		var result = ""
		result.reserveCapacity(size)
		if let condition {
			result += "#if \(condition)\n"
		}
		for (index, line) in lines.enumerated() {
			if index > 0 {
				result += "\n"
			}
			result += line
		}
		if condition != nil {
			result += "\n#endif"
		}
		return result
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
}
