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

	/// A declaration SafeDI generates – a root’s `init()`, a seam’s initializers, a `mock()` – has the type’s isolation or
	/// the one its attributes spell, so one that calls a `@MainActor` declaration needs the attribute when nothing states
	/// an isolation. The macro matches no actor by name: it reports only a callee spelled exactly `@MainActor`.
	/// The error must never fire on code that compiles: compiled with and without `-default-isolation MainActor`, in
	/// Swift 5 and 6, the generated code of each shape these tests report fails, while a type that conforms to another
	/// protocol or subclasses another class can take a global actor from it (in a module whose declarations default to
	/// the main actor, a protocol or class of its own does), so the macro stays quiet on it.
	struct InstantiableMacroIsolationTests {
		// MARK: Roots

		@Test
		func declaration_producesErrorAddingGeneratedInitializerAttributes_whenRootInitializerIsMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_producesErrorAddingToGeneratedInitializerAttributesText_whenRootInitializerIsMainActorAndAttributesStateNoIsolation() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@available(macOS 14, *)", generateMock: true)
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes` and `mockAttributes`"),
						],
					),
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor @available(macOS 14, *)", mockAttributes: "@MainActor", generateMock: true)
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootWithoutDependenciesHasMainActorInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @MainActor public init() {}
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @MainActor public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootTypeIsBoundToInitializersGlobalActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true) @MainActor
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				@MainActor
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesErrorReplacingNonisolated_whenGeneratedInitializerAttributesStateNonisolated() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generatedInitializerAttributes: "nonisolated")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenGeneratedInitializerAttributesSpellAnotherAttributeWithoutArguments() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@DatabaseActor")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenGeneratedInitializerAttributesSpellModuleQualifiedMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@_Concurrency.MainActor")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootTypeSpellsAnotherAttributeWithoutArguments() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generateMock: true) @DatabaseActor
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				@DatabaseActor
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootTypeSpellsTypeAliasOfMainActor() {
			assertMacroExpansion(
				"""
				typealias UI = MainActor

				@Instantiable(isRoot: true, generateMock: true) @UI
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				typealias UI = MainActor

				@UI
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootTypeSpellsModuleQualifiedMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generateMock: true) @_Concurrency.MainActor
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				@_Concurrency.MainActor
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootTypeSpellsMacroAttribute() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generateMock: true) @Observable
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				@Observable
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesError_whenRootTypeIsNonisolated() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				nonisolated public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				nonisolated public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
				nonisolated public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_producesError_whenRootTypeIsPreconcurrency() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				@preconcurrency public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				@preconcurrency public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
				@preconcurrency public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_producesError_whenRootInitializerSpellsModuleQualifiedMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @_Concurrency.MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @_Concurrency.MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
				public final class Root: Instantiable {
				    @_Concurrency.MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootInitializerIsBoundToAnotherGlobalActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    @DatabaseActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @DatabaseActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootInitializerIsPreconcurrencyMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @preconcurrency @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @preconcurrency @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootInitializerIsNonisolated() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true) @MainActor
				public final class Root: Instantiable {
				    nonisolated public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				@MainActor
				public final class Root: Instantiable {
				    nonisolated public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenConformanceListNamesAnotherTypeThatCanBindTheGlobalActor() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class RootViewController: UIViewController, Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class RootViewController: UIViewController, Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenMockedTypeSubclassesAnotherClass() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				public final class Presenter: Base, Instantiable {
				    @MainActor public init() {
				        super.init(name: "")
				    }
				}
				""",
				expandedSource: """
				public final class Presenter: Base, Instantiable {
				    @MainActor public init() {
				        super.init(name: "")
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: Seams

		@Test
		func declaration_producesErrorAddingGeneratedInitializerAttributes_whenSeamInitializerIsMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Feature: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Feature: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Feature`’s initializer is `@MainActor`, and the initializers SafeDI generates for this type with `generateDependencyTree: true` call it, so they must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes` and `mockAttributes`"),
						],
					),
					DiagnosticSpec(
						message: "`Feature`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateDependencyTree: true, generatedInitializerAttributes: "@MainActor", mockAttributes: "@MainActor", generateMock: true)
				public final class Feature: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_producesOneFixItAddingGeneratedAttributesOnce_whenSeamInitializerAndMockAreMainActorAndGeneratedAttributesStateNoIsolation() {
			assertMacroExpansion(
				"""
				@Instantiable(generateDependencyTree: true, generatedAttributes: "@available(macOS 14, *)", generateMock: true)
				public final class Feature: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Feature: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Feature`’s initializer is `@MainActor`, and the initializers SafeDI generates for this type with `generateDependencyTree: true` call it, so they must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedAttributes`"),
						],
					),
					DiagnosticSpec(
						message: "`Feature`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedAttributes`.",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateDependencyTree: true, generatedAttributes: "@MainActor @available(macOS 14, *)", generateMock: true)
				public final class Feature: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_fixItEditsOnlyTheAttribute_whenAnotherFixItEditsTheTypesMembers() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter = Presenter()
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter = Presenter()
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`presenter` must not have a default value: SafeDI passes every @Instantiated, @Received, and @Forwarded property in through the initializer. Remove `= Presenter()`.",
						line: 7,
						column: 5,
						fixIts: [
							FixItSpec(message: "Remove `= Presenter()`"),
						],
					),
					DiagnosticSpec(
						message: "`Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedInitializerAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenRootTypeSpellsItsGlobalActorInsideIfConfig() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, generateMock: true)
				#if os(iOS)
				@MainActor
				#endif
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				#if os(iOS)
				@MainActor
				#endif
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenSeamThatInstantiatesNothingHasMainActorInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Feature: Instantiable {
				    @MainActor public init(name: String) {
				        self.name = name
				    }

				    @Received private let name: String
				}
				""",
				expandedSource: """
				public final class Feature: Instantiable {
				    @MainActor public init(name: String) {
				        self.name = name
				    }

				    private let name: String
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenSeamConformsToAProtocolThatCanBindTheGlobalActor() {
			assertMacroExpansion(
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Feature: FeatureProtocol, Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				expandedSource: """
				public final class Feature: FeatureProtocol, Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    private let presenter: Presenter
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: Mocks

		@Test
		func declaration_producesErrorAddingMockAttributesBeforeGenerateMock_whenMockedInitializerIsMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
				expandedSource: """
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Presenter`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `mockAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
			)
		}

		@Test
		func declaration_producesErrorAddingToGeneratedAttributes_whenMockedInitializerIsMainActorAndGeneratedAttributesStateNoIsolation() {
			assertMacroExpansion(
				"""
				@Instantiable(generatedAttributes: "@available(macOS 14, *)", generateMock: .public)
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
				expandedSource: """
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`Presenter`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `generatedAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generatedAttributes: "@MainActor @available(macOS 14, *)", generateMock: .public)
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
			)
		}

		@Test
		func declaration_producesErrorNamingHandWrittenMock_whenCustomMockIsMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct Presenter: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Presenter { Presenter() }
				}
				""",
				expandedSource: """
				public struct Presenter: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Presenter { Presenter() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The hand-written mock `customMock(…)` is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `@MainActor` to `mockAttributes`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockAttributes: "@MainActor", generateMock: true, customMockName: "customMock")
				public struct Presenter: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Presenter { Presenter() }
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenInitializerIsMainActorAndGeneratedMockCallsNonisolatedCustomMock() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct Presenter: Instantiable {
				    @MainActor public init() {}

				    public static func customMock() -> Presenter { fatalError() }
				}
				""",
				expandedSource: """
				public struct Presenter: Instantiable {
				    @MainActor public init() {}

				    public static func customMock() -> Presenter { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenMockOnlyMockIsMainActor() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct Presenter {
				    @MainActor public static func mock() -> Presenter { fatalError() }
				}
				""",
				expandedSource: """
				public struct Presenter {
				    @MainActor public static func mock() -> Presenter { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenTypeWithMainActorInitializerGeneratesNothing() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
				expandedSource: """
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenInstantiateIsMainActorAndMockIsGenerated() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				extension Presenter: Instantiable {
				    @MainActor public static func instantiate() -> Presenter { fatalError() }
				}
				""",
				expandedSource: """
				extension Presenter: Instantiable {
				    @MainActor public static func instantiate() -> Presenter { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}
	}
#endif
