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

struct SourceDiagnosticTests {
	@Test
	func formatted_omitsLocationPrefix_whenLocationIsNil() {
		// Model values built during macro expansion carry no location. The dependency tree generator never
		// sees them, but the formatter does not have to prove that: a location-less diagnostic is rendered
		// the way the compiler renders its own, as `<severity>: <message>`.
		let diagnostic = SourceDiagnostic(
			severity: .error,
			location: nil,
			message: "Dependency cycle detected: A -> B -> A",
		)
		#expect(diagnostic.formatted == "error: Dependency cycle detected: A -> B -> A")
	}

	@Test
	func formatted_escapesReplacementAsJSONString_whenFixItReplacementContainsQuotesBackslashesAndNewlines() {
		// swift-build reads the replacement as a JSON string literal, so the characters it would unescape must be escaped.
		let diagnostic = SourceDiagnostic(
			severity: .error,
			location: Dependency.DeclarationLocation(filePath: "Sources/App/Child.swift", line: 7, column: 5),
			message: "@Received property `shared2: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?",
			fixIts: [
				SourceDiagnostic.FixIt(
					range: Dependency.SourceRange(startLine: 7, startColumn: 19, endLine: 7, endColumn: 26),
					replacement: "quote\" backslash\\ newline\n return\r tab\t",
				),
			],
		)
		#expect(diagnostic.formatted == """
		Sources/App/Child.swift:7:5: error: @Received property `shared2: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?
		Sources/App/Child.swift:7:19-7:26: fixit: quote\\" backslash\\\\ newline\\n return\\r tab\\t
		""")
	}

	@Test
	func resolvingFilePath_makesPathAbsolute_whenFilePathIsRelative() {
		let diagnostic = SourceDiagnostic(
			severity: .note,
			location: Dependency.DeclarationLocation(filePath: "Sources/App/Child.swift", line: 12, column: 5),
			message: "`Child` is part of the cycle",
		)
		let resolved = diagnostic.resolvingFilePath(relativeToDirectory: "/Users/developer/Project")
		#expect(resolved.formatted == "/Users/developer/Project/Sources/App/Child.swift:12:5: note: `Child` is part of the cycle")
	}

	@Test
	func resolvingFilePath_makesFixItPathsAbsolute_whenFilePathIsRelative() {
		let diagnostic = SourceDiagnostic(
			severity: .error,
			location: Dependency.DeclarationLocation(filePath: "Sources/App/Child.swift", line: 7, column: 5),
			message: "@Received property `shared2: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?",
			fixIts: [
				SourceDiagnostic.FixIt(
					range: Dependency.SourceRange(startLine: 7, startColumn: 19, endLine: 7, endColumn: 26),
					replacement: "shared",
				),
			],
		)
		let resolved = diagnostic.resolvingFilePath(relativeToDirectory: "/Users/developer/Project")
		#expect(resolved.formatted == """
		/Users/developer/Project/Sources/App/Child.swift:7:5: error: @Received property `shared2: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?
		/Users/developer/Project/Sources/App/Child.swift:7:19-7:26: fixit: shared
		""")
	}

	@Test
	func resolvingFilePath_keepsPath_whenFilePathIsAbsolute() {
		let diagnostic = SourceDiagnostic(
			severity: .error,
			location: Dependency.DeclarationLocation(filePath: "/Users/developer/Other/Root.swift", line: 3, column: 1),
			message: "Dependency cycle detected: Root -> Root",
		)
		let resolved = diagnostic.resolvingFilePath(relativeToDirectory: "/Users/developer/Project")
		#expect(resolved.formatted == "/Users/developer/Other/Root.swift:3:1: error: Dependency cycle detected: Root -> Root")
	}

	@Test
	func precedesInSourceOrder_ordersByFileLineAndColumnWithLocationlessLast() {
		// Line and column compare numerically, so line 10 follows line 9; a location-less diagnostic sorts last;
		// equal locations fall back to the message. The nil arms are reachable only for values built without a
		// file context, which the generator never sees, so they are covered here rather than through the tool.
		func diagnostic(_ location: Dependency.DeclarationLocation?, _ message: String = "message") -> SourceDiagnostic {
			SourceDiagnostic(severity: .error, location: location, message: message)
		}
		let lineNine = Dependency.DeclarationLocation(filePath: "/Project/File.swift", line: 9, column: 5)
		let lineTen = Dependency.DeclarationLocation(filePath: "/Project/File.swift", line: 10, column: 5)
		let otherFile = Dependency.DeclarationLocation(filePath: "/Project/Other.swift", line: 1, column: 1)

		let sorted = [
			diagnostic(nil, "b"),
			diagnostic(otherFile),
			diagnostic(lineTen, "b"),
			diagnostic(lineTen, "a"),
			diagnostic(nil, "a"),
			diagnostic(lineNine),
		].sorted(by: SourceDiagnostic.precedesInSourceOrder)

		#expect(sorted.map(\.formatted) == [
			"/Project/File.swift:9:5: error: message",
			"/Project/File.swift:10:5: error: a",
			"/Project/File.swift:10:5: error: b",
			"/Project/Other.swift:1:1: error: message",
			"error: a",
			"error: b",
		])
	}
}
