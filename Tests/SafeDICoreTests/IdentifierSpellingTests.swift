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

import SwiftParser
import SwiftSyntax
import Testing
@testable import SafeDICore

struct IdentifierSpellingTests {
	@Test
	func keywordsVariableNamesCannotSpell_areTheKeywordsTheParserRejects() {
		let keywords = (UInt8.min...UInt8.max)
			.compactMap(Keyword.init(rawValue:))
			.map { TokenSyntax.keyword($0).text }
		#expect(keywords.count > 100)
		let rejectedKeywords = Set(keywords.filter { !$0.isValidSwiftIdentifier(for: .variableName) })
		#expect(keywordsVariableNamesCannotSpell == rejectedKeywords, "\(rejectedKeywords.sorted())")
	}

	@Test
	func isValidVariableName_decidesAsTheParserDoes_forNamesOfEveryShape() {
		let names = [
			"leaf", "Leaf", "leaf2", "leaf_2", "_leaf", "__leaf", "_", "__", "_1", "x", "X", "a1b2",
			"1leaf", "leaf-2", "leaf.two", "my leaf", "émile", "leaf\u{301}", "$0", "$leaf", "",
			"self", "Self", "Type", "Protocol", "default", "inout", "init", "async", "await", "get", "set", "open",
		]
		let disagreements = names.filter { name in
			name.isValidVariableName != name.isValidSwiftIdentifier(for: .variableName)
		}
		#expect(disagreements == [])
	}
}
