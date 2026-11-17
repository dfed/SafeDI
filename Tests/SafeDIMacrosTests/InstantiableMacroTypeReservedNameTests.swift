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
