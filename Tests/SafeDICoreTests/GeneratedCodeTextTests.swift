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
	func lines_keepsEmptyLinesAndCarriageReturnLineFeeds_whenCodeHasBoth() {
		#expect(GeneratedCodeText.lines(of: "a\r\nb\n\nc\n") == ["a\r\nb", "", "c", ""])
		#expect(GeneratedCodeText.lines(of: "") == [""])
	}

	@Test
	func lines_returnsWhatSplittingOnNewlinesKeepingEmptyLinesReturns_forEveryStringOfUpToSixTokens() {
		let codes = Self.strings(of: Self.lineTokens, upToLength: 6)
		let mismatches = codes.filter { code in
			let expected = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
			return GeneratedCodeText.lines(of: code).map { Array($0.utf8) } != expected.map { Array($0.utf8) }
		}
		#expect(codes.count == 55_987)
		#expect(mismatches.map { Array($0.unicodeScalars) } == [])
	}

	@Test
	func indentingLines_indentsEveryLineAndKeepsEmptyLines_whenCodeHasBlankLines() {
		#expect(GeneratedCodeText.indentingLines(of: "\nfunc build() {\n\n}\n", by: "\t") == "\t\n\tfunc build() {\n\t\n\t}\n\t")
	}

	@Test
	func indentingLines_returnsWhatSplittingOnNewlinesKeepingEmptyLinesReturns_forEveryStringOfUpToSixTokens() {
		let codes = Self.strings(of: Self.lineTokens, upToLength: 6)
		let mismatches = codes.filter { code in
			let expected = code
				.split(separator: "\n", omittingEmptySubsequences: false)
				.map { "\t\t" + $0 }
				.joined(separator: "\n")
			return Array(GeneratedCodeText.indentingLines(of: code, by: "\t\t").utf8) != Array(expected.utf8)
		}
		#expect(codes.count == 55_987)
		#expect(mismatches.map { Array($0.unicodeScalars) } == [])
	}

	@Test
	func containsIdentifier_findsOnlyWholeRuns_whenIdentifierIsPartOfALongerName() {
		#expect(GeneratedCodeText.containsIdentifier("value", in: "let x = build(value)"))
		#expect(!GeneratedCodeText.containsIdentifier("value", in: "let x = build(values)"))
		#expect(!GeneratedCodeText.containsIdentifier("", in: "let x"))
		#expect(!GeneratedCodeText.containsIdentifier("value", in: "val"))
	}

	@Test
	func containsIdentifier_returnsWhatSplittingIntoIdentifiersReturns_forEveryStringOfUpToFiveTokens() {
		// A combining accent after the identifier forms one `Character` with its last letter, which then is no run equal
		// to it, though its bytes are there; a non-ASCII letter or digit beside it joins the run.
		let tokens = ["ab", "a", "b", " ", "_", "\u{301}", "é", "٣"]
		let codes = Self.strings(of: tokens, upToLength: 5)
		let mismatches = codes.filter { code in
			let expected = code.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).contains(Substring("ab"))
			return GeneratedCodeText.containsIdentifier("ab", in: code) != expected
		}
		#expect(codes.count == 37_449)
		#expect(mismatches.map { Array($0.unicodeScalars) } == [])
	}

	@Test
	func containsIdentifier_findsCanonicallyEquivalentSpelling_whenIdentifierOrCodeIsNotASCII() {
		#expect(GeneratedCodeText.containsIdentifier("caf\u{E9}", in: "let x = cafe\u{301}"))
		#expect(GeneratedCodeText.containsIdentifier("cafe\u{301}", in: "build(caf\u{E9})"))
		#expect(GeneratedCodeText.containsIdentifier("Kind", in: "let x = \u{212A}ind"))
		#expect(GeneratedCodeText.containsIdentifier("\u{212A}ind", in: "let x = Kind"))
		#expect(!GeneratedCodeText.containsIdentifier("`ab`", in: "let x = `ab`"))
	}

	@Test
	func containsIdentifier_returnsWhatSplittingIntoIdentifiersReturns_forEveryStringOfUpToFourTokensSpellingIdentifiersOutsideASCII() {
		// Precomposed and decomposed accents, the Kelvin sign and `K`, and the Greek varia and a backtick are each
		// canonically equivalent, so `Character`s equate them though their bytes differ; a raw identifier's backticks are
		// no letters, so no run holds them.
		let tokens = ["ab", "a", " ", "_", "\u{301}", "\u{E9}", "e", "\u{663}", "`", "K", "\u{212A}", "\u{3C0}", "\r", "\n", "\u{1FEF}"]
		let identifiers = ["ab", "\u{E9}", "e\u{301}", "K", "\u{212A}", "\u{3C0}", "`ab`", "a b", "\u{1FEF}ab", "`", ""]
		let codes = Self.strings(of: tokens, upToLength: 4)
		let mismatches = codes.flatMap { code in
			identifiers.filter { identifier in
				let expected = code.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).contains(Substring(identifier))
				return GeneratedCodeText.containsIdentifier(identifier, in: code) != expected
			}.map { [$0, code] }
		}
		#expect(codes.count == 54_241)
		#expect(mismatches.map { $0.map { Array($0.unicodeScalars) } } == [])
	}

	@Test
	func lines_returnsWhatSplittingOnNewlinesKeepingEmptyLinesReturns_forEveryStringOfUpToFiveTokensSpellingIdentifiersOutsideASCII() {
		let codes = Self.strings(of: Self.identifierLineTokens, upToLength: 5)
		let mismatches = codes.filter { code in
			let expected = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
			return GeneratedCodeText.lines(of: code).map { Array($0.utf8) } != expected.map { Array($0.utf8) }
		}
		#expect(codes.count == 66_430)
		#expect(mismatches.map { Array($0.unicodeScalars) } == [])
	}

	@Test
	func indentingLines_returnsWhatSplittingOnNewlinesKeepingEmptyLinesReturns_forEveryStringOfUpToFiveTokensSpellingIdentifiersOutsideASCII() {
		let codes = Self.strings(of: Self.identifierLineTokens, upToLength: 5)
		let mismatches = codes.filter { code in
			let expected = code
				.split(separator: "\n", omittingEmptySubsequences: false)
				.map { "\t\t" + $0 }
				.joined(separator: "\n")
			return Array(GeneratedCodeText.indentingLines(of: code, by: "\t\t").utf8) != Array(expected.utf8)
		}
		#expect(codes.count == 66_430)
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
	func withoutIntegrationSpellings_dropsTrailingComments_whenLinesEndInOne() {
		let text = "let a = A() // Declared as Root.a\nb() // c"
		#expect(GeneratedCodeText.withoutIntegrationSpellings(text) == "let a = A()\nb()")
	}

	@Test
	func withoutIntegrationSpellings_returnsWhatFoundationSearchReturns_forEveryStringOfUpToFiveTokens() {
		// Every string of up to five of these tokens: the part the pass looks for, a slash, a line feed, a carriage return
		// that forms `"\r\n"` with a line feed, and a combining mark that extends the scalar before it.
		let tokens = [" // ", "/", "\n", "\r", "x", "\u{301}"]
		let texts = Self.strings(of: tokens, upToLength: 5)
		// Foundation’s search matches whole `Character`s, so it misses the part where a combining mark extends its last
		// scalar; the pass finds its bytes, which only names a body otherwise (the case below).
		let partsBeforeCombiningMark = tokens.prefix(1).map { $0 + "\u{301}" }
		let mismatches = texts.filter { text in
			Array(GeneratedCodeText.withoutIntegrationSpellings(text).utf8) != Array(Self.withoutIntegrationSpellingsThroughFoundation(text).utf8)
		}
		#expect(texts.count == 9_331)
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
		guard text.contains(trailingComment) else { return text }
		return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
			String(line[..<(line.range(of: trailingComment)?.lowerBound ?? line.endIndex)])
		}.joined(separator: "\n")
	}

	/// A line feed, a carriage return that forms `"\r\n"` with a line feed beside it, a multi-byte character, a combining
	/// accent that extends the character before it, and plain text.
	private static let lineTokens = ["x", "\n", "\r", "é", "\u{301}", " "]

	/// A line feed, a carriage return, a raw identifier's backtick, a decomposed and a precomposed accent, a non-ASCII
	/// letter, the Kelvin sign, the Greek varia, which is canonically equivalent to a backtick, and an emoji joined by a
	/// zero-width joiner.
	private static let identifierLineTokens = ["\n", "\r", "`", "e\u{301}", "\u{3C0}", "\u{212A}", "\u{1FEF}", "\u{1F468}\u{200D}", "\u{E9}"]

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
