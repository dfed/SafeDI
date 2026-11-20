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

	/// A type whose name begins with a prefix of the types SafeDI generates (`SafeDIScope_`, `SafeDISendableScope_`,
	/// `SafeDIMockScope_`, `SafeDISendableMockScope_`, or `__safeDI_`), declared where the `@Instantiable` macro sees it: the decorated type, the type an `@Instantiable`
	/// extension extends, or a type declared inside either. Generated code declares types of those names beside the
	/// person's, so a type of such a name makes the generated code fail to compile.
	struct InstantiableMacroTypeReservedNameTests {
		// MARK: The decorated type

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenClassNameBeginsWithSeamScopePrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class SafeDIScope_Api: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class SafeDIScope_Api: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 2,
						column: 20,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenStructNameBeginsWithSendableSeamScopePrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct SafeDISendableScope_Api: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct SafeDISendableScope_Api: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDISendableScope_Api` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.",
						line: 2,
						column: 15,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenClassNameBeginsWithPublicMockScopePrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class SafeDIMockScope_Api: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class SafeDIMockScope_Api: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIMockScope_Api` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.",
						line: 2,
						column: 20,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenStructNameBeginsWithSendablePublicMockScopePrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct SafeDISendableMockScope_Api: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct SafeDISendableMockScope_Api: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDISendableMockScope_Api` begins with `SafeDISendableMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableMockScope_`.",
						line: 2,
						column: 15,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenActorNameBeginsWithBuilderFunctionNamePrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public actor __safeDI_Builder: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public actor __safeDI_Builder: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `__safeDI_Builder` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 2,
						column: 14,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticWithoutBackticks_whenTypeNameIsWrittenInBackticks() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct `SafeDIScope_Api`: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct `SafeDIScope_Api`: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 2,
						column: 15,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: A type declared inside the decorated type

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenSeamDeclaresNestedTypeNamedLikeItsScopeEnum() {
			assertMacroExpansion(
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Home: Instantiable {
				    public init(detailBuilder: Instantiator<Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    @Instantiated public let detailBuilder: Instantiator<Detail>

				    public final class SafeDIScope_Api {}
				}
				""",
				expandedSource: """
				public final class Home: Instantiable {
				    public init(detailBuilder: Instantiator<Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    public let detailBuilder: Instantiator<Detail>

				    public final class SafeDIScope_Api {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 9,
						column: 24,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtEachNestedType_whenSeamDeclaresNestedTypesNamedWithItsGuardEnumsPrefix() {
			// The enum a seam’s module generates beside the seam’s initializer is named `__safeDI_<Seam>_<hash>`. A type the
			// seam declares with that prefix is rejected whatever follows it, the exact hashed name included.
			assertMacroExpansion(
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(cache: Cache) {
				        self.cache = cache
				    }

				    @Instantiated let cache: Cache

				    public enum __safeDI_Screen {}
				    public enum __safeDI_Screen_ {}
				    public enum __safeDI_Screen_0000000000000000 {}
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(cache: Cache) {
				        self.cache = cache
				    }

				    let cache: Cache

				    public enum __safeDI_Screen {}
				    public enum __safeDI_Screen_ {}
				    public enum __safeDI_Screen_0000000000000000 {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `__safeDI_Screen` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 9,
						column: 17,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_Screen_` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 10,
						column: 17,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_Screen_0000000000000000` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 11,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtEachNestedType_whenNestedTypesOfEveryKindBeginWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Home: Instantiable {
				    public init() {}

				    public enum SafeDIScope_Enum {}
				    public struct SafeDIScope_Struct {}
				    public final class SafeDISendableScope_Class {}
				    public actor SafeDISendableScope_Actor {}
				    public protocol __safeDI_Protocol {}
				    public typealias __safeDI_Alias = Int
				}
				""",
				expandedSource: """
				public struct Home: Instantiable {
				    public init() {}

				    public enum SafeDIScope_Enum {}
				    public struct SafeDIScope_Struct {}
				    public final class SafeDISendableScope_Class {}
				    public actor SafeDISendableScope_Actor {}
				    public protocol __safeDI_Protocol {}
				    public typealias __safeDI_Alias = Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Enum` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 5,
						column: 17,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Struct` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 6,
						column: 19,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDISendableScope_Class` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.",
						line: 7,
						column: 24,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDISendableScope_Actor` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.",
						line: 8,
						column: 18,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_Protocol` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 9,
						column: 21,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_Alias` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 10,
						column: 22,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtEachAssociatedType_whenNestedProtocolDeclaresAssociatedTypesWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Home: Instantiable {
				    public init() {}

				    public protocol Holder {
				        associatedtype SafeDIScope_Value
				        #if DEBUG
				        associatedtype SafeDIMockScope_Element
				        #else
				        associatedtype __safeDI_Element
				        #endif
				    }
				}
				""",
				expandedSource: """
				public struct Home: Instantiable {
				    public init() {}

				    public protocol Holder {
				        associatedtype SafeDIScope_Value
				        #if DEBUG
				        associatedtype SafeDIMockScope_Element
				        #else
				        associatedtype __safeDI_Element
				        #endif
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Value` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 6,
						column: 24,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIMockScope_Element` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.",
						line: 8,
						column: 24,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_Element` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 10,
						column: 24,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenNestedProtocolDeclaresRenamedAssociatedTypes() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Home: Instantiable {
				    public init() {}

				    public protocol Holder {
				        associatedtype Value
				        #if DEBUG
				        associatedtype MockElement
				        #else
				        associatedtype Element
				        #endif
				    }
				}
				""",
				expandedSource: """
				public struct Home: Instantiable {
				    public init() {}

				    public protocol Holder {
				        associatedtype Value
				        #if DEBUG
				        associatedtype MockElement
				        #else
				        associatedtype Element
				        #endif
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenTypeNestedInsideNestedTypeBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Home: Instantiable {
				    public init() {}

				    public enum Route {
				        public struct __safeDI_Builder {}
				    }
				}
				""",
				expandedSource: """
				public struct Home: Instantiable {
				    public init() {}

				    public enum Route {
				        public struct __safeDI_Builder {}
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `__safeDI_Builder` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 6,
						column: 23,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticInEachClause_whenNestedTypeInConditionalCompilationBlockBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Home: Instantiable {
				    public init() {}

				    #if DEBUG
				    public struct SafeDIScope_Api {}
				    #else
				    public struct SafeDISendableScope_Api {}
				    #endif
				}
				""",
				expandedSource: """
				public struct Home: Instantiable {
				    public init() {}

				    #if DEBUG
				    public struct SafeDIScope_Api {}
				    #else
				    public struct SafeDISendableScope_Api {}
				    #endif
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 6,
						column: 19,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDISendableScope_Api` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.",
						line: 8,
						column: 19,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticOnce_whenNestedInstantiableTypeNameBeginsWithReservedPrefix() {
			// The nested type’s own expansion reports its name and the types declared inside it.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Home: Instantiable {
				    public init() {}

				    @Instantiable
				    public struct SafeDIScope_Api: Instantiable {
				        public init() {}

				        public struct __safeDI_Builder {}
				    }
				}
				""",
				expandedSource: """
				public struct Home: Instantiable {
				    public init() {}
				    public struct SafeDIScope_Api: Instantiable {
				        public init() {}

				        public struct __safeDI_Builder {}
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 6,
						column: 19,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_Builder` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 9,
						column: 23,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: An extension

		@Test
		func extension_producesReservedTypeNameDiagnostic_whenExtendedTypeNameBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension SafeDIScope_Api: Instantiable {
				    public static func instantiate() -> SafeDIScope_Api { fatalError() }
				}
				""",
				expandedSource: """
				extension SafeDIScope_Api: Instantiable {
				    public static func instantiate() -> SafeDIScope_Api { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 2,
						column: 11,
						severity: .error,
					),
					// `instantiate()` spells the type it builds, which generated code spells too.
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 41,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesReservedTypeNameDiagnostic_whenQualifiedExtendedTypeNameBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Feature.__safeDI_Builder: Instantiable {
				    public static func instantiate() -> Feature.__safeDI_Builder { fatalError() }
				}
				""",
				expandedSource: """
				extension Feature.__safeDI_Builder: Instantiable {
				    public static func instantiate() -> Feature.__safeDI_Builder { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `__safeDI_Builder` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 2,
						column: 19,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesReservedTypeNameDiagnostic_whenTypeNestedInExtensionBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Home: Instantiable {
				    public static func instantiate() -> Home { fatalError() }

				    public struct SafeDISendableScope_Api {}
				}
				""",
				expandedSource: """
				extension Home: Instantiable {
				    public static func instantiate() -> Home { fatalError() }

				    public struct SafeDISendableScope_Api {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDISendableScope_Api` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.",
						line: 5,
						column: 19,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: A type the declaration spells

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtEachSpelling_whenDependencyTypesSpellReservedNamesInGenericOptionalTupleAndClosure() {
			// Generated code spells a dependency’s type, and each type the initializer that fulfills it takes, in scopes where a
			// type SafeDI generates can hide a type of a reserved name, wherever that type is declared.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(a: Array<SafeDIScope_A>, b: SafeDISendableScope_B?, c: (SafeDIMockScope_C, Int), d: @escaping (__safeDI_D) -> Void) {
				        self.a = a
				        self.b = b
				        self.c = c
				        self.d = d
				    }

				    @Received let a: Array<SafeDIScope_A>
				    @Received let b: SafeDISendableScope_B?
				    @Received let c: (SafeDIMockScope_C, Int)
				    @Received let d: (__safeDI_D) -> Void
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(a: Array<SafeDIScope_A>, b: SafeDISendableScope_B?, c: (SafeDIMockScope_C, Int), d: @escaping (__safeDI_D) -> Void) {
				        self.a = a
				        self.b = b
				        self.c = c
				        self.d = d
				    }

				    let a: Array<SafeDIScope_A>
				    let b: SafeDISendableScope_B?
				    let c: (SafeDIMockScope_C, Int)
				    let d: (__safeDI_D) -> Void
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 26,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDISendableScope_B` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.",
						line: 3,
						column: 45,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIMockScope_C` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.",
						line: 3,
						column: 73,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_D` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 3,
						column: 112,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 10,
						column: 28,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDISendableScope_B` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.",
						line: 11,
						column: 22,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIMockScope_C` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.",
						line: 12,
						column: 23,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `__safeDI_D` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.",
						line: 13,
						column: 23,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRenamedTypesReplaceReservedNamesTheDependencyTypesSpelled() {
			// The remedy: once each type is renamed, so that its name does not begin with a reserved prefix, nothing is reported.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(a: Array<ScopeA>, b: SendableScopeB?, c: (MockScopeC, Int), d: @escaping (BuilderD) -> Void) {
				        self.a = a
				        self.b = b
				        self.c = c
				        self.d = d
				    }

				    @Received let a: Array<ScopeA>
				    @Received let b: SendableScopeB?
				    @Received let c: (MockScopeC, Int)
				    @Received let d: (BuilderD) -> Void
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(a: Array<ScopeA>, b: SendableScopeB?, c: (MockScopeC, Int), d: @escaping (BuilderD) -> Void) {
				        self.a = a
				        self.b = b
				        self.c = c
				        self.d = d
				    }

				    let a: Array<ScopeA>
				    let b: SendableScopeB?
				    let c: (MockScopeC, Int)
				    let d: (BuilderD) -> Void
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtEachSpelling_whenAliasOfTypeSpellsReservedNameInGeneric() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(apis: Array<SafeDIScope_Api>) {
				        self.apis = apis
				    }

				    @Received(fulfilledByDependencyNamed: "services", ofType: Array<SafeDIScope_Api>.self) let apis: Array<SafeDIScope_Api>
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(apis: Array<SafeDIScope_Api>) {
				        self.apis = apis
				    }

				    let apis: Array<SafeDIScope_Api>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 29,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 7,
						column: 69,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 7,
						column: 108,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtString_whenFulfilledByTypeNamesReservedName() {
			// Generated code constructs the type `fulfilledByType:` names, so a reserved name there is reported at the string.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(service: AnyService) {
				        self.service = service
				    }

				    @Instantiated(fulfilledByType: "SafeDIScope_Impl", erasedToConcreteExistential: true) let service: AnyService
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(service: AnyService) {
				        self.service = service
				    }

				    let service: AnyService
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Impl` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 7,
						column: 36,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnostic_whenDefaultValuedInitializerParameterSpellsReservedNameInOptional() {
			// A default-valued parameter is no dependency, but a generated `mock()` takes it, spelling its type.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(service: Service, mode: SafeDIScope_Mode? = nil) {
				        self.service = service
				        self.mode = mode
				    }

				    @Received let service: Service
				    let mode: SafeDIScope_Mode?
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(service: Service, mode: SafeDIScope_Mode? = nil) {
				        self.service = service
				        self.mode = mode
				    }

				    let service: Service
				    let mode: SafeDIScope_Mode?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Mode` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 41,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesReservedTypeNameDiagnosticAtEachSpelling_whenInstantiateParameterAndReturnTypeSpellReservedNames() {
			// An extension’s dependencies are its `instantiate(…)` parameters, and the type it builds is what that returns.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Box: Instantiable {
				    public static func instantiate(handler: @escaping (SafeDIScope_Event) -> Void) -> Box<SafeDIScope_Item> {
				        Box(handler: handler)
				    }
				}
				""",
				expandedSource: """
				extension Box: Instantiable {
				    public static func instantiate(handler: @escaping (SafeDIScope_Event) -> Void) -> Box<SafeDIScope_Item> {
				        Box(handler: handler)
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Event` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 56,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Item` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 91,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtEachSpelling_whenHandWrittenMockParameterAndReturnTypeSpellReservedNames() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct Box<Item>: Instantiable {
				    public static func mock(item: [SafeDIScope_Item] = []) -> Box<SafeDIScope_Item> {
				        Box()
				    }
				}
				""",
				expandedSource: """
				public struct Box<Item>: Instantiable {
				    public static func mock(item: [SafeDIScope_Item] = []) -> Box<SafeDIScope_Item> {
				        Box()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Item` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 36,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Item` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 67,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticAtFirstNameOnly_whenSpellingQualifiesReservedName() {
			// `Feature.SafeDIScope_Api` resolves as a member of `Feature`, which no type SafeDI generates can hide, while
			// `SafeDIScope_Mode.Kind` resolves its first name lexically.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(api: Feature.SafeDIScope_Api, mode: SafeDIScope_Mode.Kind, service: AnyService) {
				        self.api = api
				        self.mode = mode
				        self.service = service
				    }

				    @Received let api: Feature.SafeDIScope_Api
				    @Received let mode: SafeDIScope_Mode.Kind
				    @Instantiated(fulfilledByType: "Feature.SafeDIScope_Impl", erasedToConcreteExistential: true) let service: AnyService
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(api: Feature.SafeDIScope_Api, mode: SafeDIScope_Mode.Kind, service: AnyService) {
				        self.api = api
				        self.mode = mode
				        self.service = service
				    }

				    let api: Feature.SafeDIScope_Api
				    let mode: SafeDIScope_Mode.Kind
				    let service: AnyService
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Mode` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 53,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_Mode` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 10,
						column: 25,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedTypeNameDiagnosticInEachClause_whenDependencyInConditionalCompilationBlockSpellsReservedName() {
			// The macro reads every clause, as the compiler may select any of them.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(a: SafeDIScope_A) {
				        self.a = a
				    }

				    #if DEBUG
				    @Received let a: SafeDIScope_A
				    #else
				    @Received let a: SafeDIScope_A
				    #endif
				}
				""",
				expandedSource: """
				public struct Screen: Instantiable {
				    public init(a: SafeDIScope_A) {
				        self.a = a
				    }

				    #if DEBUG
				    let a: SafeDIScope_A
				    #else
				    let a: SafeDIScope_A
				    #endif
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 3,
						column: 20,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 8,
						column: 22,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.",
						line: 10,
						column: 22,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: Names that only resemble a reserved prefix

		@Test
		func declaration_expandsWithoutIssue_whenTypeNamesOnlyResembleReservedPrefixes() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct SafeDIScopeX: Instantiable {
				    public init() {}

				    public struct SafeDIScope {}
				    public struct SafeDISendableScopeApi {}
				    public struct _safeDI_Builder {}
				    public struct __SafeDI_Builder {}
				    public struct safeDIScope_Api {}
				    public struct MySafeDIScope_Api {}
				    public struct Detail_Scope {}
				    public struct detailBuilder_Values {}
				    public struct SafeDIMockScope {}
				    public struct SafeDIMockScopeApi {}
				    public struct SafeDISendableMockScopeApi {}
				    public struct safeDIMockScope_Api {}
				    public struct SafeDISendablemockScope_Api {}
				    public struct SAFEDIMOCKSCOPE_Api {}
				}
				""",
				expandedSource: """
				public struct SafeDIScopeX: Instantiable {
				    public init() {}

				    public struct SafeDIScope {}
				    public struct SafeDISendableScopeApi {}
				    public struct _safeDI_Builder {}
				    public struct __SafeDI_Builder {}
				    public struct safeDIScope_Api {}
				    public struct MySafeDIScope_Api {}
				    public struct Detail_Scope {}
				    public struct detailBuilder_Values {}
				    public struct SafeDIMockScope {}
				    public struct SafeDIMockScopeApi {}
				    public struct SafeDISendableMockScopeApi {}
				    public struct safeDIMockScope_Api {}
				    public struct SafeDISendablemockScope_Api {}
				    public struct SAFEDIMOCKSCOPE_Api {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenExtendedTypeNameOnlyResemblesReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension SafeDISendableScopeX: Instantiable {
				    public static func instantiate() -> SafeDISendableScopeX { fatalError() }
				}
				""",
				expandedSource: """
				extension SafeDISendableScopeX: Instantiable {
				    public static func instantiate() -> SafeDISendableScopeX { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}
	}
#endif
