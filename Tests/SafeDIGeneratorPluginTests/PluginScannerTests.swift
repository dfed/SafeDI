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

struct PluginScannerStripCommentsAndStringsTests {
	// MARK: Line comments

	@Test
	func stripsLineComment_whenInstantiableIsAfterDoubleSlash() {
		let source = "// @Instantiable(isRoot: true)\nlet x = 1"
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let x = 1"))
	}

	@Test
	func stripsTripleSlashDocComment_whenInstantiableIsInsideDocComment() {
		let source = "/// See `@Instantiable(isRoot: true)` for usage.\nlet x = 1"
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let x = 1"))
	}

	@Test
	func preservesCodeAfterLineComment_whenCommentPrecedesCode() {
		let source = "let a = 1 // @Instantiable(isRoot: true)\nlet b = 2"
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(stripped.contains("let a = 1"))
		#expect(stripped.contains("let b = 2"))
		#expect(!stripped.contains("@Instantiable"))
	}

	// MARK: Block comments

	@Test
	func stripsBlockComment_whenInstantiableIsInsideBlockComment() {
		let source = "/* @Instantiable(isRoot: true) */ let x = 1"
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let x = 1"))
	}

	@Test
	func stripsNestedBlockComment_whenOuterContainsInnerContainingInstantiable() {
		let source = "/* outer /* @Instantiable(isRoot: true) */ still in outer */ let x = 1"
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let x = 1"))
	}

	@Test
	func preservesLinesInsideMultilineBlockComment_whenCommentSpansMultipleLines() {
		let source = """
		/*
		@Instantiable(isRoot: true)
		*/
		let x = 1
		"""
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let x = 1"))
		let newlineCount = stripped.count(where: { $0 == "\n" })
		let sourceNewlineCount = source.count(where: { $0 == "\n" })
		#expect(newlineCount == sourceNewlineCount)
	}

	// MARK: String literals

	@Test
	func stripsDoubleQuotedStringLiteral_whenInstantiableIsInsideString() {
		let source = #"let s = "@Instantiable(isRoot: true)""#
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let s ="))
	}

	@Test
	func stripsTripleQuotedStringLiteral_whenInstantiableIsInsideMultilineString() {
		let source = """
		let s = \"\"\"
		@Instantiable(isRoot: true)
		\"\"\"
		"""
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let s ="))
	}

	@Test
	func handlesEscapedQuoteInsideStringLiteral_whenEscapedQuotePrecedesInstantiable() {
		let source = #"let s = "escaped \" before @Instantiable(isRoot: true)""#
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(!stripped.contains("@Instantiable"))
		#expect(stripped.contains("let s ="))
	}

	// MARK: Real code preservation

	@Test
	func preservesRealInstantiable_whenSourceContainsOnlyRealCode() {
		let source = """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init() {}
		}
		"""
		let stripped = stripSwiftCommentsAndStrings(from: source)
		#expect(stripped.contains("@Instantiable(isRoot: true)"))
		#expect(stripped.contains("public struct Root"))
	}

	@Test
	func preservesRealInstantiable_whenSourceMixesCommentsAndRealCode() {
		let source = """
		/// Demonstrates `@Instantiable(isRoot: false)` but the real one is below.
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init() {}
		}
		"""
		let stripped = stripSwiftCommentsAndStrings(from: source)
		// The comment's mention of isRoot:false must be gone, but the real
		// declaration must survive.
		#expect(!stripped.contains("isRoot: false"))
		#expect(stripped.contains("@Instantiable(isRoot: true)"))
	}

	// MARK: Regression — the exact shape that caused PR #271

	@Test
	func doesNotMatchSafeDIToolManifestDocComment_whenCommentMentionsIsRootTrue() {
		// Mirrors the line in Sources/SafeDICore/Models/SafeDIToolManifest.swift
		// that triggered the original bug: the scanner flagged the file as
		// containing a root declaration because the regex matched the text
		// inside a doc comment.
		let source = """
		/// Each entry maps a Swift file containing `@Instantiable(isRoot: true)` to the
		/// generated output file.
		public struct SafeDIToolManifest: Codable, Sendable {}
		"""
		let stripped = stripSwiftCommentsAndStrings(from: source)
		let matched = stripped.range(
			of: #"@Instantiable\s*\((.|\n)*?isRoot\s*:\s*true"#,
			options: .regularExpression,
		) != nil
		#expect(!matched)
	}
}
