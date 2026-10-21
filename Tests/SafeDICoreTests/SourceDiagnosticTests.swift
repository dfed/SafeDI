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
	func formatted_usesUnknownLocation_whenLocationIsNil() {
		let diagnostic = SourceDiagnostic(
			severity: .error,
			location: nil,
			message: "Dependency cycle detected: A -> B -> A",
		)
		#expect(diagnostic.formatted == "<unknown>:0: error: Dependency cycle detected: A -> B -> A")
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
	func resolvingFilePath_keepsPath_whenFilePathIsAbsolute() {
		let diagnostic = SourceDiagnostic(
			severity: .error,
			location: Dependency.DeclarationLocation(filePath: "/Users/developer/Other/Root.swift", line: 3, column: 1),
			message: "Dependency cycle detected: Root -> Root",
		)
		let resolved = diagnostic.resolvingFilePath(relativeToDirectory: "/Users/developer/Project")
		#expect(resolved.formatted == "/Users/developer/Other/Root.swift:3:1: error: Dependency cycle detected: Root -> Root")
	}
}
