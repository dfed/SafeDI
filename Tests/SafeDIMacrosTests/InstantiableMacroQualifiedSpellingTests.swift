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

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(SafeDIMacros)
	@testable import SafeDIMacros

	/// SafeDI's macros and wrappers spelled with SafeDI's module name (`@SafeDI.Instantiated`, `SafeDI.Instantiator<T>`)
	/// are read as their bare spellings are. `assertMacroExpansion` expands only a macro spelled as its key in the macros
	/// it is given, so `@SafeDI.Instantiable` itself is expanded by the compiler in `SafeDIToolQualifiedSpellingTests`,
	/// whose fixtures are compiled.
	struct InstantiableMacroQualifiedSpellingTests {
		@Test
		func declaration_fixit_generatesRequiredInitializer_whenDependencyMacrosAreQualifiedBySafeDI() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @SafeDI.Instantiated let child: Child
				    @SafeDI.Received let session: Session
				    @SafeDI.Forwarded let user: User
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    @SafeDI.Instantiated let child: Child
				    @SafeDI.Received let session: Session
				    @SafeDI.Forwarded let user: User
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(
				child: Child,
				session: Session,
				user: User
				) {
				self.child = child
				self.session = session
				self.user = user
				}

				    @SafeDI.Instantiated let child: Child
				    @SafeDI.Received let session: Session
				    @SafeDI.Forwarded let user: User
				}
				""",
			)
		}

		@Test
		func expansion_warnsThatForwardingIsDeprecated_whenForwardedPropertyIsInstantiatorQualifiedBySafeDI() {
			// `SafeDI.Instantiator<Child>` is the instantiator a bare `Instantiator<Child>` is.
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    @Forwarded let childBuilder: SafeDI.Instantiator<Child>
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let childBuilder: SafeDI.Instantiator<Child>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`@Forwarded` on an `Instantiator` property is deprecated and will be an error in SafeDI 3.0: declare it `@Instantiated` on this type, or receive it with `@Received` from an ancestor that declares it, or forward the value it builds.",
						line: 2,
						column: 34,
						severity: .warning,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func declaration_fixit_spellsParameterQualifiedBySafeDI_whenTypeHasNoInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let childBuilder: SafeDI.Instantiator<Child>
				    @Received let session: Session
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let childBuilder: SafeDI.Instantiator<Child>
				    let session: Session
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(
				childBuilder: SafeDI.Instantiator<Child>,
				session: Session
				) {
				self.childBuilder = childBuilder
				self.session = session
				}

				    @Instantiated let childBuilder: SafeDI.Instantiator<Child>
				    @Received let session: Session
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsArgumentQualifiedBySafeDI_whenInitializerLacksIt() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Instantiated let childBuilder: SafeDI.Instantiator<Child>
				    @Received let session: Session
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(session: Session) {
				        self.session = session
				    }

				    let childBuilder: SafeDI.Instantiator<Child>
				    let session: Session
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `childBuilder: SafeDI.Instantiator<Child>`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for childBuilder: SafeDI.Instantiator<Child>"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for childBuilder: SafeDI.Instantiator<Child>",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(
				childBuilder: SafeDI.Instantiator<Child>,
				session: Session
				) {
				        self.childBuilder = childBuilder
				        self.session = session
				    }

				    @Instantiated let childBuilder: SafeDI.Instantiator<Child>
				    @Received let session: Session
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsMockArgumentQualifiedBySafeDI_whenMockMethodLacksIt() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(childBuilder: SafeDI.Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }
				    @Instantiated let childBuilder: SafeDI.Instantiator<Child>

				    public static func mock() -> ExampleService {
				        fatalError()
				    }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(childBuilder: SafeDI.Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }
				    let childBuilder: SafeDI.Instantiator<Child>

				    public static func mock() -> ExampleService {
				        fatalError()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `childBuilder: SafeDI.Instantiator<Child>`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for childBuilder: SafeDI.Instantiator<Child>"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `mock()` arguments for childBuilder: SafeDI.Instantiator<Child>",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(childBuilder: SafeDI.Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }
				    @Instantiated let childBuilder: SafeDI.Instantiator<Child>

				    public static func mock(childBuilder: SafeDI.Instantiator<Child>) -> ExampleService {
				        fatalError()
				    }
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesMockStubQualifiedBySafeDI_whenMockOnlyTypeHasNoMockMethod() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let childBuilder: SafeDI.Instantiator<Child>
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let childBuilder: SafeDI.Instantiator<Child>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `static func mock(…) -> ExampleService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func mock(…) -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let childBuilder: SafeDI.Instantiator<Child>
				public static func mock(childBuilder: SafeDI.Instantiator<Child>) -> ExampleService {ExampleService(childBuilder: childBuilder)}


				}
				""",
			)
		}

		@Test
		func extension_fixit_addsMockArgumentQualifiedBySafeDI_whenMockMethodLacksIt() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(childBuilder: SafeDI.Instantiator<Child>) -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        fatalError()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(childBuilder: SafeDI.Instantiator<Child>) -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        fatalError()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `childBuilder: SafeDI.Instantiator<Child>`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for childBuilder: SafeDI.Instantiator<Child>"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `mock()` arguments for childBuilder: SafeDI.Instantiator<Child>",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(childBuilder: SafeDI.Instantiator<Child>) -> ExampleService { fatalError() }

				    public static func mock(childBuilder: SafeDI.Instantiator<Child>) -> ExampleService {
				        fatalError()
				    }
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsConformanceQualifiedBySafeDI_whenMacroIsQualifiedBySafeDI() throws {
			let fixedDeclarations = try fixedDeclarationsOfMissingConformance(in: """
			@SafeDI.Instantiable
			public struct ExampleService {
			    public init() {}
			}
			""")
			#expect(fixedDeclarations == [
				"""
				@SafeDI.Instantiable
				public struct ExampleService: SafeDI.Instantiable {
				    public init() {}
				}
				""",
			])
		}

		@Test
		func extension_fixit_addsConformanceQualifiedBySafeDI_whenMacroIsQualifiedBySafeDI() throws {
			let fixedDeclarations = try fixedDeclarationsOfMissingConformance(in: """
			@SafeDI.Instantiable
			extension ExampleService {
			    public static func instantiate() -> ExampleService { fatalError() }
			}
			""")
			#expect(fixedDeclarations == [
				"""
				@SafeDI.Instantiable
				extension ExampleService: SafeDI.Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			])
		}

		/// The declarations the missing-conformance fix-it replaces the first declaration of `source` with, from the
		/// macro expanded directly: `assertMacroExpansion` expands only a macro spelled as its key in the macros it
		/// is given, so it never expands `@SafeDI.Instantiable`.
		private func fixedDeclarationsOfMissingConformance(in source: String) throws -> [String] {
			let sourceFile = Parser.parse(source: source)
			let declaration = try #require(sourceFile.statements.first?.item.asProtocol(DeclGroupSyntax.self))
			let attribute = try #require(declaration.attributes.first.flatMap { AttributeSyntax($0) })
			let context = BasicMacroExpansionContext(sourceFiles: [sourceFile: .init(moduleName: "TestModule", fullFilePath: "Test.swift")])
			_ = try InstantiableMacro.expansion(of: attribute, providingMembersOf: declaration, conformingTo: [], in: context)
			return context.diagnostics
				.filter { $0.diagMessage.message == FixableInstantiableError.missingInstantiableConformance.description }
				.flatMap(\.fixIts)
				.flatMap(\.changes)
				.compactMap { change in
					guard case let .replace(_, newNode) = change else { return nil }
					return newNode.description
				}
		}
	}
#endif
