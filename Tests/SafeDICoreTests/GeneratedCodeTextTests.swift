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
import Testing
@testable import SafeDICore

/// `GeneratedCodeText` replaces two expressions the generator ran at every node of a tree with passes over UTF-8, which
/// must return the same bytes: each test compares the bytes of the pass with those of the expression it replaces on every
/// string of a few tokens, and spells results out, including the one case where the override path deliberately differs.
struct GeneratedCodeTextTests {
	@Test
	func indentingNonEmptyLines_indentsEachLineAndDropsEmptyLines_whenCodeHasBlankLines() {
		let code = "\nfunc build() -> A {\n\n    return A()\n}\n\n"
		#expect(GeneratedCodeText.indentingNonEmptyLines(of: code, by: "\t") == "\tfunc build() -> A {\n\t    return A()\n\t}")
	}

	@Test
	func indentingNonEmptyLines_keepsCarriageReturnLineFeedInsideItsLine_whenCodeHasWindowsLineEndings() {
		// `"\r\n"` is one `Character`, which is no `"\n"`, so splitting on `"\n"` never splits it.
		#expect(GeneratedCodeText.indentingNonEmptyLines(of: "a\r\nb\n\r\nc", by: "  ") == "  a\r\nb\n  \r\nc")
	}

	@Test
	func indentingNonEmptyLines_splitsBeforeCombiningMark_whenLineStartsWithCombiningMark() {
		// Unicode breaks every grapheme after a line feed, so a line feed never forms one `Character` with the scalar after
		// it, and splitting on `"\n"` splits here too, unlike a `"."` before a combining mark in an override path.
		let code = "a\n\u{301}b"
		#expect(code.split(separator: "\n").map(String.init) == ["a", "\u{301}b"])
		#expect(Array(GeneratedCodeText.indentingNonEmptyLines(of: code, by: "\t").utf8) == Array("\ta\n\t\u{301}b".utf8))
	}

	@Test
	func indentingNonEmptyLines_returnsWhatSplittingOnNewlinesReturns_forEveryStringOfUpToSixTokens() {
		// Every string of up to six of these tokens: a line feed, a carriage return that forms `"\r\n"` with a line feed
		// beside it, a multi-byte character, a combining accent that extends the character before it, and plain text.
		let tokens = ["x", "\n", "\r", "é", "\u{301}", " "]
		let codes = Self.strings(of: tokens, upToLength: 6)
		let mismatches = codes.filter { code in
			let expected = code
				.split(separator: "\n")
				.map { "\t\t" + $0 }
				.joined(separator: "\n")
			return Array(GeneratedCodeText.indentingNonEmptyLines(of: code, by: "\t\t").utf8) != Array(expected.utf8)
		}
		#expect(codes.count == 55_987)
		#expect(mismatches.map { Array($0.unicodeScalars) } == [])
	}

	@Test
	func nonBlankLinesJoined_dropsLinesOfWhitespace_whenCodeHasBlankAndIndentedLines() {
		let code = "\n\tlet a = A()\n  \t\n\u{0B}\nlet b = B()\n"
		#expect(Self.nonBlankLinesJoined(of: code) == "\tlet a = A()\nlet b = B()")
	}

	@Test
	func nonBlankLinesJoined_returnsWhatSplittingFilteringAndJoiningReturns_forEveryStringOfUpToSixTokens() {
		// Every string of up to six of these tokens: a line feed, a carriage return that forms `"\r\n"` with a line feed
		// beside it, a multi-byte character, a non-ASCII whitespace character, ASCII whitespace, and plain text.
		let tokens = ["x", "\n", "\r", "\u{A0}", "\t", " "]
		let codes = Self.strings(of: tokens, upToLength: 6)
		let mismatches = codes.filter { code in
			let expected = code
				.components(separatedBy: "\n")
				.filter { !$0.allSatisfy(\.isWhitespace) }
				.joined(separator: "\n")
			return Array(Self.nonBlankLinesJoined(of: code).utf8) != Array(expected.utf8)
		}
		#expect(codes.count == 55_987)
		#expect(mismatches.map { Array($0.unicodeScalars) } == [])
	}

	private static func nonBlankLinesJoined(of code: String) -> String {
		var code = code
		return code.withUTF8(GeneratedCodeText.nonBlankLinesJoined(ofUTF8:))
	}

	@Test
	func joined_returnsWhatJoiningReturnsWrappedInCondition_whenGivenACondition() {
		let lines = ["struct A {", "", "\tlet a = 1", "}"]
		#expect(GeneratedCodeText.joined(lines, wrappedInConditionalCompilation: "DEBUG") == "#if DEBUG\n\(lines.joined(separator: "\n"))\n#endif")
	}

	@Test
	func joined_returnsWhatJoiningReturns_whenGivenNoCondition() {
		let lines = ["struct A {", "", "\tlet a = 1", "}"]
		#expect(GeneratedCodeText.joined(lines, wrappedInConditionalCompilation: nil) == lines.joined(separator: "\n"))
	}

	@Test
	func overrideRelativePath_dropsOverridesPrefixAndJoinsLabelsWithUnderscores_whenPathIsNested() {
		#expect(GeneratedCodeText.overrideRelativePath(of: "safeDIOverrides.child.grandchild") == "child_grandchild")
	}

	@Test
	func overrideRelativePath_rewritesPeriodBeforeExtendingScalar_whenLabelStartsWithCombiningMark() {
		// U+064B may start an identifier and extends the character before it, so a `.` and it form one `Character`, which
		// Foundation’s search did not match, leaving a `.` in a local name that did not compile. The pass treats the `.`
		// as it treats any other.
		#expect(Array(GeneratedCodeText.overrideRelativePath(of: "safeDIOverrides.\u{064B}x.\u{064B}y").utf8) == Array("\u{064B}x_\u{064B}y".utf8))
	}

	@Test
	func overrideRelativePath_returnsWhatFoundationReplacementReturns_forEveryStringOfUpToFiveTokens() {
		// Every string of up to five of these tokens, including a label that ends in the overrides parameter’s name and
		// parts of that name that only form it together.
		let tokens = ["safeDIOverrides", ".", "a", "safeDI", "Overrides", "é"]
		let paths = Self.strings(of: tokens, upToLength: 5)
		let mismatches = paths.filter { path in
			let expected = path
				.replacingOccurrences(of: "safeDIOverrides.", with: "")
				.replacingOccurrences(of: ".", with: "_")
			return Array(GeneratedCodeText.overrideRelativePath(of: path).utf8) != Array(expected.utf8)
		}
		#expect(paths.count == 9_331)
		#expect(mismatches == [])
	}

	/// Every concatenation of up to `length` of `tokens`, the empty string first.
	private static func strings(of tokens: [String], upToLength length: Int) -> [String] {
		var strings = [""]
		var previousLength = [""]
		for _ in 0..<length {
			previousLength = previousLength.flatMap { prefix in tokens.map { prefix + $0 } }
			strings += previousLength
		}
		return strings
	}
}
