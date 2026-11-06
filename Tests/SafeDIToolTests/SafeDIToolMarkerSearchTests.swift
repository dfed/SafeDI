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
		#expect(words.holdsPackageAccessModifier == findsPackage)
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
		#expect(!Self.typeDeclarationWords(of: "let `package` = Package()").holdsPackageAccessModifier)
	}

	@Test
	func typeDeclarationWords_findsPackageModifierAndName_whenTextStartsWithByteOrderMark() {
		// A byte order mark is no part of the word after it, whether or not the platform's Foundation removed it when
		// reading the file.
		let words = Self.typeDeclarationWords(of: "\u{FEFF}package enum Token {}")
		#expect(words.holdsPackageAccessModifier)
		#expect(words.namesFollowingKeywords == ["Token"])
	}

	@Test(arguments: [
		// Between the modifier and the keyword, between the keyword and the name, and after the name.
		(text: "package\u{A0}struct Token {}", names: ["Token"], findsPackage: true),
		(text: "struct\u{A0}Token {}", names: ["Token"], findsPackage: false),
		(text: "enum Token\u{A0}{}", names: ["Token"], findsPackage: false),
		(text: "package\u{A0}typealias\u{A0}Token\u{A0}= Int", names: ["Token"], findsPackage: true),
	] as [(text: String, names: Set<String>, findsPackage: Bool)])
	func typeDeclarationWords_findsPackageModifierAndName_whenNonBreakingSpaceSeparatesWords(text: String, names: Set<String>, findsPackage: Bool) {
		// The compiler reads a non-breaking space, U+00A0, as whitespace (with a warning), so it is no part of a word.
		let words = Self.typeDeclarationWords(of: text)
		#expect(words.namesFollowingKeywords == names)
		#expect(words.holdsPackageAccessModifier == findsPackage)
	}

	@Test(arguments: [
		"package struct Token {}",
		"package enum Space {}",
		"public enum Space {\n    package enum Token {}\n}",
	])
	func mayDeclareTypeModulesReadingModuleInfoNeed_isTrue_whenTextHoldsPackage(text: String) {
		// A run that writes module info without a target graph keeps every `package` declaration, top-level ones too.
		#expect(Self.mayDeclareTypeModulesReadingModuleInfoNeed(text))
	}

	@Test(arguments: [
		// Top-level declarations alone: a module that reads the module's info names them by their own names.
		"public struct Token {}",
		"open class Token {}",
		"public struct First {\n    public init() {}\n}\n\npublic struct Second {}",
		"public extension Space {\n    func make() {}\n}\n\npublic enum Token {}",
		// A nested type no module can name.
		"enum Space {\n    struct Token {}\n}",
		"public final class Model {\n    private enum Constants {}\n    public func make() {}\n}",
		"public enum Space {\n    enum Token {}\n}",
		// `class` modifying a member introduces no type.
		"public class Model {\n    public class func make() -> Model { Model() }\n    open class var shared: Model { Model() }\n}",
		// Words in comments and string literals introduce nothing.
		"public enum Space {\n    /// The public struct that holds a token.\n    static let description = \"public struct\"\n}",
		// A division, and an interpolation of names, end where the search can tell, so the next type is at the top level.
		"public struct Size {\n    var half: Int { width / 2 }\n}\n\npublic struct Token {}",
		"public struct Label {\n    var text: String { \"\\(count) of \\(items.count)\" }\n}\n\npublic struct Token {}",
		// `public` in backticks is a name.
		"let `public` = 1\nenum Space {\n    struct Token {}\n}",
		// `class` and a non-breaking space modifying a member introduce no type.
		"public class Model {\n    public class\u{A0}func make() -> Model { Model() }\n}",
		// A type keyword the search cannot place, outside every brace.
		"let half = 4/2; public struct Token {}",
		// Text that ends after a slash, inside a slash the search cannot place, or inside an interpolation.
		"public struct Token {}\nlet half = width /",
		"public struct Token {}\nlet half = (width/2)",
		"public struct Token {}\nlet label = \"\\(count",
	])
	func mayDeclareTypeModulesReadingModuleInfoNeed_isFalse_whenTextDeclaresNoNestedTypeEveryModuleCanName(text: String) {
		// The search reads comments, string literals and braces, so that a file without such a declaration is not parsed.
		#expect(!Self.mayDeclareTypeModulesReadingModuleInfoNeed(text))
	}

	@Test(arguments: [
		"public enum Space {\n    public struct Token {}\n}",
		"public enum Space {\n    open class Token {}\n}",
		"extension Space {\n    public typealias Token = Int\n}",
		"public extension Space {\n    struct Token {}\n}",
		"public enum Space {\n    public /* } */ final // }\n    class Token {}\n}",
		"public class Model {\n    public class func make() -> Model { Model() }\n    public class Token {}\n}",
		// A `public` extension after a slash the search cannot place.
		"let half = 4/2; public extension Space {\n    struct Token {}\n}",
		// After a string literal that does not end on its line, which is not Swift the search can read, it finds a nested
		// type wherever it may be.
		"let broken = \"\\\npublic enum Space {\n    public struct Token {}\n}",
		"let broken = \"text\npublic enum Space {\n    public struct Token {}\n}",
	])
	func mayDeclareTypeModulesReadingModuleInfoNeed_isTrue_whenTextMayDeclareNestedTypeEveryModuleCanName(text: String) {
		// A type nested in another that is `public` or `open` by its own modifier, or by the extension it is directly inside.
		#expect(Self.mayDeclareTypeModulesReadingModuleInfoNeed(text))
	}

	@Test(arguments: [
		// Between the modifier and the keyword, directly and after a comment.
		"public enum Space {\n    public\u{A0}struct Token {}\n}",
		"public enum Space {\n    public /* */\u{A0}struct Token {}\n}",
		"public enum Space {\n    open\u{A0}class\u{A0}Token {}\n}",
		// Between the modifier and `extension`, and between `extension` and the extended type's name.
		"public\u{A0}extension Space {\n    struct Token {}\n}",
		"public extension\u{A0}Space {\n    struct Token {}\n}",
		// After `#if`, whose clause holds a `}` the compiler does not parse.
		"public enum Space {\n#if\u{A0}compiler(>=99)\n}\n#endif\n    public struct Token {}\n}",
		// In bytes the search cannot place, to the end of the line and to the end of the text.
		"public enum Space {\n    static let d = /a/; public\u{A0}struct Token {}\n}",
		"let broken = \"text\npublic enum Space {\n    public\u{A0}struct Token {}\n}",
	])
	func mayDeclareTypeModulesReadingModuleInfoNeed_isTrue_whenNonBreakingSpaceSeparatesWords(text: String) {
		// The compiler reads a non-breaking space, U+00A0, as whitespace (with a warning), so it is no part of a word.
		#expect(Self.mayDeclareTypeModulesReadingModuleInfoNeed(text))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func parseModule_keepsEveryNestedDeclarationEveryModuleCanName_whenLexicalNoiseComesBeforeIt() async throws {
		// A run that writes module info without a target graph parses a file that mentions no SafeDI marker only when the
		// text search finds it may declare a type a module reading the module's info needs. A false negative would lose a
		// declaration, so the run keeps every one the same file keeps when it mentions SafeDI in a trailing comment, and so
		// is parsed whatever the search finds, however the comments, string literals, regex literals, and clauses the
		// compiler does not parse that come before it hold braces, quotes, slashes, and backslashes.
		let directory = try temporaryDirectory()
		var texts = [String]()
		for container in Self.nestedDeclarationContainers {
			for declaration in container.declarations {
				for firstNoise in Self.lexicalNoise {
					for secondNoise in Self.lexicalNoise {
						texts.append(container.opening + firstNoise + secondNoise + declaration + "\n}\n")
					}
					// Every line break as Windows writes it.
					texts.append((container.opening + firstNoise + declaration + "\n}\n").replacingOccurrences(of: "\n", with: "\r\n"))
				}
			}
		}
		var markerlessFilePaths = Set<String>()
		var markedFilePaths = Set<String>()
		for (index, text) in texts.enumerated() {
			let markerlessFile = directory.appendingPathComponent("Markerless/\(index).swift")
			let markedFile = directory.appendingPathComponent("Marked/\(index).swift")
			try FileManager.default.createDirectory(at: markerlessFile.deletingLastPathComponent(), withIntermediateDirectories: true)
			try FileManager.default.createDirectory(at: markedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
			try text.write(to: markerlessFile, atomically: true, encoding: .utf8)
			try (text + "// Mentions @Instantiable.\n").write(to: markedFile, atomically: true, encoding: .utf8)
			markerlessFilePaths.insert(markerlessFile.path)
			markedFilePaths.insert(markedFile.path)
		}

		let markerlessModule = try await parseModule(
			filePaths: markerlessFilePaths,
			configurationFilePaths: markerlessFilePaths,
			activeCompilationConditions: [],
			keepsTypeDeclarationsOtherModulesCanName: true,
		).module
		let markedModule = try await parseModule(
			filePaths: markedFilePaths,
			configurationFilePaths: markedFilePaths,
			activeCompilationConditions: [],
			keepsTypeDeclarationsOtherModulesCanName: true,
		).module

		let markerlessDeclarationsByFileName = Self.keptDeclarationsByFileName(of: markerlessModule)
		let markedDeclarationsByFileName = Self.keptDeclarationsByFileName(of: markedModule)
		// The parse keeps the nested declaration from every text, so each text tests the search.
		#expect(markedDeclarationsByFileName.count == texts.count)
		#expect(markedDeclarationsByFileName.values.allSatisfy { $0.contains("Space.Token") })
		#expect(markerlessDeclarationsByFileName == markedDeclarationsByFileName)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What the text search finds in `text`.
	private static func typeDeclarationWords(of text: String) -> TypeDeclarationWords {
		var text = text
		return text.withUTF8(\.typeDeclarationWords)
	}

	private mutating func temporaryDirectory() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		return directory
	}

	/// The plain declarations `module` keeps, spelled, by the name of the file that holds each.
	private static func keptDeclarationsByFileName(of module: ParsedModule) -> [String: [String]] {
		var declarationsByFileName = [String: [String]]()
		for declaration in module.moduleInfo.plainTypeDeclarations {
			let fileName = URL(fileURLWithPath: declaration.sourceFilePath ?? "").lastPathComponent
			declarationsByFileName[fileName, default: []].append(declaration.typeDescription.asSource)
		}
		return declarationsByFileName
	}

	/// Whether a run that writes module info without a target graph parses `text` when it mentions no SafeDI marker.
	private static func mayDeclareTypeModulesReadingModuleInfoNeed(_ text: String) -> Bool {
		var text = text
		return text.withUTF8 { source in
			source.mayDeclareTypeModulesReadingModuleInfoNeed(holdingWords: source.typeDeclarationWords)
		}
	}

	/// Where a nested declaration another module can name is: the opening of the type or extension that encloses it, and
	/// each declaration of it, which a closing brace ends.
	private static let nestedDeclarationContainers: [(opening: String, declarations: [String])] = [
		(
			opening: "public enum Space {\n",
			declarations: [
				"public struct Token {}",
				"open class Token {}",
				"public /* } */ final // }\n class Token {}",
				"public\n    indirect enum Token {}",
				"public typealias Token = Int",
				"#if os(Linux)\npublic struct Token {}\n#endif",
			],
		),
		(opening: "extension Space {\n", declarations: ["public actor Token {}"]),
		(opening: "\u{FEFF}@MainActor\npublic extension Space where Base: Equatable {\n", declarations: ["struct Token {}"]),
	]

	/// Members that hold braces, quotes, slashes and backslashes in comments, string literals, regex literals, and
	/// clauses the compiler does not parse, each a line or more ending in a line break; the first is empty.
	private static let lexicalNoise = [
		"",
		"// }} \"\n",
		"/* } /* } */ } \" */\n",
		"static let a = \"}} // /*\"\n",
		"static let b = \"\\(count)}\\\"}\"\n",
		"static let c = \"\\([1].map { \"\\($0)}\" })}\"\n",
		"static let d = /a}\"/\n",
		"static let e = #/\n}\n/#\n",
		"static let f = #\"}\"\"#\n",
		"static let g = ##\"}\"#\"##\n",
		"static let h = \"\"\"\n}\n\"\"\"\n",
		"static let i = \"\"\"\n\\([\"}\"].count) \\(\"\"\"\n}\n\"\"\")\n}\n\"\"\"\n",
		"static let j = #\"\"\"\n}\n\"\"\"#\n",
		"static var k: Int { 4 / 2 }\n",
		"static var l: Int { 4/2 }\n",
		"static func m() { _ = 1 /* } */ }\n",
		"#if compiler(>=99)\n}\n#endif\n",
		"#if compiler(>=99)\n}\n#else\n#endif\n",
		"#if compiler(>=99)\n}\n#elseif compiler(>=98)\n}\n#endif\n",
		"static let q = #line\n",
		"static let r = \"\"\"\n\\\"\"\"}\n\\(count)}\n\"\"\"\n",
		"static let s = 4/2; static let t = \"\"\"\n}\n\"\"\"\n",
		"static let n = \"\\u{7D}\"\n",
	]
}
