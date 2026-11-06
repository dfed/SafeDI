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
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// How SafeDITool decides from a file's text whether to parse it: only a file whose bytes contain `@Instantiable`
/// or `#SafeDIConfiguration` can declare SafeDI content.
struct SafeDIToolMarkerSearchTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_findsInstantiable_whenOtherAttributesPrecedeMarker() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor @preconcurrency
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.generateOutput.module.instantiables.map(\.concreteInstantiable) == [.simple(name: "Service")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_findsConfiguration_whenFileDeclaresOnlyConfiguration() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				"Configuration.swift": """
				#SafeDIConfiguration(additionalImportedModules: ["Shared"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.generateOutput.module.configurations.map(\.additionalImportedModules) == [["Shared"]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_doesNotParseFile_whenItsTextEndsWithPartOfMarker() async throws {
		// A file that is parsed reports its syntax errors, so the broken file shows whether it was parsed.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				"Broken.swift": """
				public final class Unrelated {
				    :::brokenSyntax
				}
				// @Instantiabl
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.generateOutput.module.filesWithUnexpectedNodes == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_parsesFile_whenMarkerIsFollowedByCombiningMark() async throws {
		// The bytes of `@Instantiable` followed by a combining acute accent contain the marker's bytes, although
		// its last character, `é`, differs from the marker's. The file is parsed as any file mentioning SafeDI is,
		// so the syntax errors it holds are reported.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				"Broken.swift": """
				// Mentions @Instantiable\u{0301}.
				public final class Unrelated {
				    :::brokenSyntax
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.generateOutput.module.filesWithUnexpectedNodes == [output.fixtures["Broken.swift"]])
	}

	@Test(arguments: [
		// The name in backticks after whitespace, directly after the keyword, and on the keyword's next line.
		(text: "package struct `Token` {}", names: ["Token"]),
		(text: "struct`Token`{}", names: ["Token"]),
		(text: "enum\n    `Token` {}", names: ["Token"]),
		// A raw identifier, whose backticks enclose a space.
		(text: "struct `My Token` {}", names: ["My Token"]),
	] as [(text: String, names: Set<String>)])
	func typeDeclarationWords_findsNameInBackticks_whenItFollowsTypeKeyword(text: String, names: Set<String>) {
		// D3.6: a backtick keeps the name after the keyword, and is no part of it.
		#expect(Self.typeDeclarationWords(of: text).namesFollowingKeywords == names)
	}

	@Test(arguments: [
		// No closing backtick on its line: the backtick encloses nothing, and a declaration after it is read.
		(text: "typealias `Token", names: [], findsPackage: false),
		(text: "struct `Token\nstruct Other {}", names: ["Other"], findsPackage: false),
		(text: "let tick = \"`\"; package struct Token {}", names: ["Token"], findsPackage: true),
		// The closing backtick is on a later line: the backtick there opens a name of its own.
		(text: "let tick = \"`\"\npackage struct `Token` {}", names: ["Token"], findsPackage: true),
	] as [(text: String, names: Set<String>, findsPackage: Bool)])
	func typeDeclarationWords_readsLaterDeclaration_whenBacktickHasNoClosingBacktickOnItsLine(text: String, names: Set<String>, findsPackage: Bool) {
		// A backtick without a closing one on its line is an ordinary byte, so the search stays a superset.
		let words = Self.typeDeclarationWords(of: text)
		#expect(words.namesFollowingKeywords == names)
		#expect(words.mayDeclareTypeOtherModulesCanName == findsPackage)
	}

	@Test(arguments: [
		"let `class` = 1",
		"func make(`struct`: Int, `enum`: Token) {}",
		"for `enum` in kinds {}",
	])
	func typeDeclarationWords_findsNoName_whenKeywordIsInBackticks(text: String) {
		// D3.4: a keyword in backticks is a name, which introduces no declaration.
		#expect(Self.typeDeclarationWords(of: text).namesFollowingKeywords.isEmpty)
	}

	@Test
	func typeDeclarationWords_findsNoPackageModifier_whenPackageIsInBackticks() {
		// `package` in backticks is a name, never the access modifier.
		#expect(!Self.typeDeclarationWords(of: "let `package` = Package()").mayDeclareTypeOtherModulesCanName)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What the text search finds in `text`.
	private static func typeDeclarationWords(of text: String) -> TypeDeclarationWords {
		var text = text
		return text.withUTF8(\.typeDeclarationWords)
	}
}
