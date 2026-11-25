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

struct AttributeListSyntaxElementExtensionsTests {
	@Test(arguments: ["@Instantiated", "@SafeDI.Instantiated"])
	func instantiatedMacro_findsAttribute_whenSpelledAloneOrQualifiedBySafeDI(spelling: String) {
		#expect(Self.attributes(of: "\(spelling) let child: Child").contains { $0.instantiatedMacro != nil })
	}

	@Test(arguments: ["@Kit.Instantiated", "@SafeDI<Int>.Instantiated", "@Kit.SafeDI.Instantiated", "@SafeDI.Received", "@Instantiable"])
	func instantiatedMacro_findsNoAttribute_whenNameIsAnotherOrQualifiedByAnotherType(spelling: String) {
		#expect(!Self.attributes(of: "\(spelling) let child: Child").contains { $0.instantiatedMacro != nil })
	}

	private static func attributes(of source: String) -> AttributeListSyntax {
		Parser.parse(source: source).statements.first?.item.as(VariableDeclSyntax.self)?.attributes ?? []
	}
}
