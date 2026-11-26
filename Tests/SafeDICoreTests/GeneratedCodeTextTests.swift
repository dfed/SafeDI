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

	@Test
	func withoutIntegrationSpellings_dropsTrailingCommentsAndSourceLocationDirectories_whenLinesHoldBoth() {
		let text = "let a = A() // Declared at /checkout/Sources/A.swift:3\n#sourceLocation(file: \"/checkout/Sources/B.swift\", line: 9)\nb()"
		#expect(GeneratedCodeText.withoutIntegrationSpellings(text) == "let a = A()\n#sourceLocation(file: \"B.swift\", line: 9)\nb()")
	}

	@Test
	func withoutIntegrationSpellings_returnsWhatFoundationSearchReturns_forEveryStringOfUpToFiveTokens() {
		// Every string of up to five of these tokens: the parts the pass looks for, a path's separator, a line feed, a
		// carriage return that forms `"\r\n"` with a line feed, and a combining mark that extends the scalar before it.
		let tokens = [" // ", "#sourceLocation(file: \"", "\", line: ", "/", "\n", "\r", "x", "\u{301}"]
		let texts = Self.strings(of: tokens, upToLength: 5)
		// Foundation’s search matches whole `Character`s, so it misses a part, or a path’s last separator, whose last scalar
		// a combining mark extends; the pass finds its bytes, which only names a body otherwise (the case below).
		let partsBeforeCombiningMark = tokens.prefix(4).map { $0 + "\u{301}" }
		let mismatches = texts.filter { text in
			Array(GeneratedCodeText.withoutIntegrationSpellings(text).utf8) != Array(Self.withoutIntegrationSpellingsThroughFoundation(text).utf8)
		}
		#expect(texts.count == 37_449)
		#expect(mismatches.filter { text in !partsBeforeCombiningMark.contains { Array(text.utf8).firstRange(of: Array($0.utf8)) != nil } } == [])
	}

	@Test
	func withoutIntegrationSpellings_dropsComment_whenCombiningMarkExtendsItsLastSpace() {
		// Foundation’s search does not find `" // "` here, since its space and the mark are one `Character`.
		let text = "a() // \u{301}b"
		#expect(Self.withoutIntegrationSpellingsThroughFoundation(text) == text)
		#expect(GeneratedCodeText.withoutIntegrationSpellings(text) == "a()")
	}

	/// The expression `GeneratedCodeText.withoutIntegrationSpellings(_:)` replaces.
	private static func withoutIntegrationSpellingsThroughFoundation(_ text: String) -> String {
		let trailingComment = " // "
		let sourceLocationFile = "#sourceLocation(file: \""
		guard text.contains(trailingComment) || text.contains(sourceLocationFile) else { return text }
		return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
			let code = line[..<(line.range(of: trailingComment)?.lowerBound ?? line.endIndex)]
			guard let directive = code.range(of: sourceLocationFile),
			      let closing = code.range(of: "\", line: ", range: directive.upperBound..<code.endIndex)
			else { return String(code) }
			let path = code[directive.upperBound..<closing.lowerBound]
			return String(code[..<directive.upperBound] + path[(path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex)...] + code[closing.lowerBound...])
		}.joined(separator: "\n")
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
