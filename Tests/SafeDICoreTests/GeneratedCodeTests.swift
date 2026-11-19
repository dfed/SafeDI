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

import Testing
@testable import SafeDICore

/// A plan's text is the text re-indenting every level wrote: each test compares `GeneratedCode.spelled()` with the
/// expression it replaces, every level's text indented again by `GeneratedCodeText.indentingNonEmptyLines(of:by:)`.
struct GeneratedCodeTests {
	@Test
	func spelled_writesEachLineAfterEveryLevelsIndentation_whenLevelsNest() {
		let code = GeneratedCode.indented(
			.lines([
				.text("func a() -> A {"),
				.indented(.text("let b = B()\n\nreturn A(b: b)"), by: "\t"),
				.text("}\n"),
			]),
			by: "    ",
		)
		#expect(code.spelled() == "    func a() -> A {\n    \tlet b = B()\n    \treturn A(b: b)\n    }")
	}

	@Test
	func spelled_keepsEmptyLines_whenIndentationIsEmpty() {
		#expect(GeneratedCode.indented(.text("a\n\nb\n"), by: "").spelled() == "a\n\nb\n")
	}

	@Test
	func spelled_keepsCarriageReturnLineFeedInsideItsLine_whenTextHasWindowsLineEndings() {
		let code = GeneratedCode.indented(.sequence([.text("a\r"), .text("\nb\n"), .text("\r\nc")]), by: "  ")
		#expect(code.spelled() == "  a\r\nb\n  \r\nc")
	}

	@Test
	func spelled_writesPlaceCodeAsItIs_whenPlanHoldsPlace() {
		let place = PlacePlan(kind: .builtByFunction, functionNames: ["__safeDI_a"], closedOnFunctionName: nil, code: .text("x\ny"))
		#expect(GeneratedCode.indented(.place(place), by: "\t").spelled() == "\tx\n\ty")
	}

	@Test
	func spelled_returnsWhatReindentingEveryLevelReturns_forTwentyThousandSeededPlans() {
		var generator = SeededGenerator(seed: 0x5AFE_D1)
		var mismatches = [String]()
		for _ in 0..<20_000 {
			let code = Self.randomCode(depth: 4, using: &generator)
			let expected = Self.reindentingEveryLevel(code)
			let spelled = code.spelled()
			if Array(spelled.utf8) != Array(expected.utf8) {
				mismatches.append(expected)
			}
		}
		#expect(mismatches == [])
	}

	/// The text the emitter wrote before plans: every level indents its whole code again.
	private static func reindentingEveryLevel(_ code: GeneratedCode) -> String {
		switch code {
		case let .text(text):
			text
		case let .sequence(pieces):
			pieces.map(reindentingEveryLevel).joined()
		case let .lines(pieces):
			pieces.map(reindentingEveryLevel).joined(separator: "\n")
		case let .indented(code, indentation):
			indentation.isEmpty
				? reindentingEveryLevel(code)
				: GeneratedCodeText.indentingNonEmptyLines(of: reindentingEveryLevel(code), by: indentation)
		case let .place(plan):
			reindentingEveryLevel(plan.code)
		}
	}

	private static func randomCode(depth: Int, using generator: inout SeededGenerator) -> GeneratedCode {
		let tokens = ["x", "\n", "\r", "é", "\u{301}", " ", "\n\n", "\r\n"]
		let kind = depth == 0 ? 0 : Int(generator.next() % 5)
		switch kind {
		case 0:
			let count = Int(generator.next() % 5)
			return .text((0..<count).map { _ in tokens[Int(generator.next() % UInt64(tokens.count))] }.joined())
		case 1, 2:
			let pieces = (0..<Int(generator.next() % 4)).map { _ in randomCode(depth: depth - 1, using: &generator) }
			return kind == 1 ? .sequence(pieces) : .lines(pieces)
		case 3:
			let indentations = ["", "\t", "    ", "\r"]
			return .indented(randomCode(depth: depth - 1, using: &generator), by: indentations[Int(generator.next() % UInt64(indentations.count))])
		default:
			return .place(PlacePlan(kind: .alias, functionNames: [], closedOnFunctionName: nil, code: randomCode(depth: depth - 1, using: &generator)))
		}
	}
}

/// SplitMix64: the same plans on every run.
private struct SeededGenerator {
	var state: UInt64

	init(seed: UInt64) {
		state = seed
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var value = state
		value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
		value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
		return value ^ (value >> 31)
	}
}
