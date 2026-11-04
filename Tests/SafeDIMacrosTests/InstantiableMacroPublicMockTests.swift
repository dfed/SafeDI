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

import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(SafeDIMacros)
	@testable import SafeDIMacros

	struct InstantiableMacroPublicMockTests {
		// MARK: Accepted spellings

		@Test(arguments: [
			"public struct Service: Instantiable {\n    public init() {}\n}",
			"open class Service: Instantiable {\n    public init() {}\n}",
		])
		func declaration_expandsWithoutIssue_whenPublicMockIsOnPublicOrOpenType(declaration: String) {
			assertMacroExpansion(
				"@Instantiable(generateMock: .public)\n" + declaration,
				expandedSource: declaration,
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenPublicMockIsOnUnspelledTypeDirectlyInsidePublicExtension() {
			assertMacroExpansion(
				"""
				public extension Feed {
				    @Instantiable(generateMock: .public)
				    struct Panel: Instantiable {
				        public init() {}
				    }
				}
				""",
				expandedSource: """
				public extension Feed {
				    struct Panel: Instantiable {
				        public init() {}
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ["true", "false", ".none", ".internal", ".public", "MockGeneration.none", "MockGeneration.internal", "MockGeneration.public"])
		func declaration_expandsWithoutIssue_whenGenerateMockSpellsMockGenerationCase(spelling: String) {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: \(spelling))
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: Errors

		@Test(arguments: ["someVariable", ".init(booleanLiteral: true)", "Other.public", ".public(x:)", "MockGeneration(x:).public", ".unknown"])
		func declaration_throwsError_whenGenerateMockSpellsNoMockGenerationCase(spelling: String) {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: \(spelling))
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `generateMock` must be `true`, `false`, `.none`, `.internal`, or `.public`.",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsError_whenPublicMockIsOnPackageType() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: .public)
				package struct Session: Instantiable {
				    package init() {}
				}
				""",
				expandedSource: """
				package struct Session: Instantiable {
				    package init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` requires a `public` or `open` type; `Session` is `package`. Make it `public`, or use `.internal`.",
						line: 1,
						column: 29,
						fixIts: [
							FixItSpec(message: "Replace `package` with `public`"),
							FixItSpec(message: "Replace `.public` with `.internal`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `package` with `public`"],
				fixedSource: """
				@Instantiable(generateMock: .public)
				public struct Session: Instantiable {
				    package init() {}
				}
				""",
			)
		}

		@Test
		func declaration_offersInternalMock_whenPublicMockIsOnPackageType() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: .public)
				package struct Session: Instantiable {
				    package init() {}
				}
				""",
				expandedSource: """
				package struct Session: Instantiable {
				    package init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` requires a `public` or `open` type; `Session` is `package`. Make it `public`, or use `.internal`.",
						line: 1,
						column: 29,
						fixIts: [
							FixItSpec(message: "Replace `package` with `public`"),
							FixItSpec(message: "Replace `.public` with `.internal`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `.public` with `.internal`"],
				fixedSource: """
				@Instantiable(generateMock: .internal)
				package struct Session: Instantiable {
				    package init() {}
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenPublicMockIsOnUnspelledInternalType() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: .public)
				final class Session: Instantiable {
				    init() {}
				}
				""",
				expandedSource: """
				final class Session: Instantiable {
				    init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` requires a `public` or `open` type; `Session` is `internal`. Make it `public`, or use `.internal`.",
						line: 1,
						column: 29,
						fixIts: [
							FixItSpec(message: "Insert `public`"),
							FixItSpec(message: "Replace `.public` with `.internal`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Insert `public`"],
				fixedSource: """
				@Instantiable(generateMock: .public)
				public final class Session: Instantiable {
				    init() {}
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenPublicMockIsOnUnspelledTypeInsideExtensionThatSpellsNoPublic() {
			assertMacroExpansion(
				"""
				extension Feed {
				    @Instantiable(generateMock: .public)
				    struct Panel: Instantiable {
				        public init() {}
				    }
				}
				""",
				expandedSource: """
				extension Feed {
				    struct Panel: Instantiable {
				        public init() {}
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` requires a `public` or `open` type; `Panel` is `internal`. Make it `public`, or use `.internal`.",
						line: 2,
						column: 33,
						fixIts: [
							FixItSpec(message: "Insert `public`"),
							FixItSpec(message: "Replace `.public` with `.internal`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Insert `public`"],
				fixedSource: """
				extension Feed {
				    @Instantiable(generateMock: .public)
				    public struct Panel: Instantiable {
				        public init() {}
				    }
				}
				""",
			)
		}

		@Test
		func extension_throwsError_whenPublicMockIsOnExtension() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: .public)
				extension Shelf: Instantiable {
				    public static func instantiate() -> Shelf { Shelf() }
				}
				""",
				expandedSource: """
				extension Shelf: Instantiable {
				    public static func instantiate() -> Shelf { Shelf() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` needs a type declaration; an extension cannot prove its type is `public`. Use `.internal`, or write a public `mock` by hand.",
						line: 1,
						column: 29,
						fixIts: [
							FixItSpec(message: "Replace `.public` with `.internal`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: .internal)
				extension Shelf: Instantiable {
				    public static func instantiate() -> Shelf { Shelf() }
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenPublicMockIsOnMockOnlyDeclaration() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true, generateMock: .public)
				public struct Service {
				    public static func mock() -> Service { Service() }
				}
				""",
				expandedSource: """
				public struct Service {
				    public static func mock() -> Service { Service() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`mockOnly` cannot be combined with `generateMock: true`, `.internal`, or `.public`: a `mockOnly` declaration provides a hand-written mock. To generate a mock, set `generateMock` on the production `@Instantiable` declaration instead.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `generateMock: .public`"),
						],
					),
					DiagnosticSpec(
						message: "@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`.",
						line: 3,
						column: 5,
						fixIts: [
							FixItSpec(message: "Rename method to `customMock` and add `customMockName: \"customMock\"` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Remove `generateMock: .public`"],
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct Service {
				    public static func mock() -> Service { Service() }
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenPublicMockIsOnGenericType() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: .public)
				public struct Cache<Key: Hashable>: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct Cache<Key: Hashable>: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` cannot be used on the generic type `Cache`: SafeDI cannot generate a public `mock()` for a type in a generic context. Use `generateMock: true` for a mock its own module calls, or write a public `mock()` by hand for other modules to call.",
						line: 1,
						column: 29,
						fixIts: [
							FixItSpec(message: "Replace `.public` with `true`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: true)
				public struct Cache<Key: Hashable>: Instantiable {
				    public init() {}
				}
				""",
			)
		}

		@Test(arguments: [
			("class", "public final class Cache<Key>: Instantiable {"),
			("actor", "public actor Cache<Key>: Instantiable {"),
		])
		func declaration_throwsError_whenPublicMockIsOnGenericClassOrActor(kind _: String, declaration: String) {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: .public)
				\(declaration)
				    public init() {}
				}
				""",
				expandedSource: """
				\(declaration)
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` cannot be used on the generic type `Cache`: SafeDI cannot generate a public `mock()` for a type in a generic context. Use `generateMock: true` for a mock its own module calls, or write a public `mock()` by hand for other modules to call.",
						line: 1,
						column: 29,
						fixIts: [
							FixItSpec(message: "Replace `.public` with `true`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: true)
				\(declaration)
				    public init() {}
				}
				""",
			)
		}

		@Test(arguments: [
			"public final class Outer<T> {",
			"public actor Outer<T> {",
			"public enum Outer<T> {",
		])
		func declaration_throwsError_whenPublicMockIsOnTypeDeclaredInGenericClassActorOrEnumBody(enclosingDeclaration: String) {
			assertMacroExpansion(
				"""
				\(enclosingDeclaration)
				    @Instantiable(generateMock: .public)
				    public struct Inner: Instantiable {
				        public init() {}
				    }
				}
				""",
				expandedSource: """
				\(enclosingDeclaration)
				    public struct Inner: Instantiable {
				        public init() {}
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` cannot be used on `Inner`, which is declared inside the generic type `Outer`: SafeDI cannot generate a public `mock()` for a type in a generic context. Use `generateMock: true` for a mock its own module calls, or write a public `mock()` by hand for other modules to call.",
						line: 2,
						column: 33,
						fixIts: [
							FixItSpec(message: "Replace `.public` with `true`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				\(enclosingDeclaration)
				    @Instantiable(generateMock: true)
				    public struct Inner: Instantiable {
				        public init() {}
				    }
				}
				""",
			)
		}

		@Test
		func declaration_reportsOnlyPrivateType_whenPublicMockIsOnPrivateType() {
			// `privateOrFilePrivateType` reports the type; the public mock adds nothing.
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: .public)
				private struct Service: Instantiable {
				    init() {}
				}
				""",
				expandedSource: """
				private struct Service: Instantiable {
				    init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must not be `private`: SafeDI constructs it in a generated file, where a `private` type is not visible. Remove `private`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `private` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: .public)
				struct Service: Instantiable {
				    init() {}
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenPublicMockIsOnTypeDeclaredInGenericTypesBody() {
			assertMacroExpansion(
				"""
				public struct Outer<T> {
				    @Instantiable(generateMock: .public)
				    public struct Inner: Instantiable {
				        public init() {}
				    }
				}
				""",
				expandedSource: """
				public struct Outer<T> {
				    public struct Inner: Instantiable {
				        public init() {}
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`generateMock: .public` cannot be used on `Inner`, which is declared inside the generic type `Outer`: SafeDI cannot generate a public `mock()` for a type in a generic context. Use `generateMock: true` for a mock its own module calls, or write a public `mock()` by hand for other modules to call.",
						line: 2,
						column: 33,
						fixIts: [
							FixItSpec(message: "Replace `.public` with `true`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				public struct Outer<T> {
				    @Instantiable(generateMock: true)
				    public struct Inner: Instantiable {
				        public init() {}
				    }
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenDefaultValuedParameterIsAutoclosure() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Service: Instantiable {
				    public init(flag: @autoclosure () -> Bool = false) {}
				}
				""",
				expandedSource: """
				public struct Service: Instantiable {
				    public init(flag: @autoclosure () -> Bool = false) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "A default-valued `@autoclosure` parameter cannot be forwarded by a generated mock. Remove `@autoclosure` from `flag`, or remove its default.",
						line: 3,
						column: 17,
					),
				],
				macros: instantiableTestMacros,
			)
		}
	}
#endif
