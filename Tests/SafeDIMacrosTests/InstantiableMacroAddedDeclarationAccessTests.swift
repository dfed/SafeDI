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

	/// The access of the declarations the `@Instantiable` macro's fix-its add: a construction initializer, an
	/// `instantiate()` method, and a hand-written mock method.
	struct InstantiableMacroAddedDeclarationAccessTests {
		// MARK: Initializer

		@Test(arguments: TypeAccessCell.all)
		func declaration_fixitAddsInitializerWithTheTypesAccess_whenTypeSpellsAccessLevel(_ cell: TypeAccessCell) {
			assertMacroExpansion(
				"""
				@Instantiable
				\(cell.introducer) Feature: Instantiable {
				    @Received let helper: Helper
				}
				""",
				expandedSource: """
				\(cell.introducer) Feature: Instantiable {
				    let helper: Helper
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: "\(cell.introducer) Feature: Instantiable ".count + 1,
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
				\(cell.introducer) Feature: Instantiable {
				\(cell.addedModifiers)init(helper: Helper) {
				self.helper = helper
				}

				    @Received let helper: Helper
				}
				""",
			)
		}

		@Test
		func declaration_fixitAddsInitializerWithoutAccessModifier_whenTypeIsFileprivate() {
			// The macro also offers to remove `fileprivate`; the initializer it adds is `internal`, which generated code in
			// another file can call once the type is no longer `fileprivate`.
			assertMacroExpansion(
				"""
				@Instantiable
				fileprivate final class Feature: Instantiable {
				    @Received let helper: Helper
				}
				""",
				expandedSource: """
				fileprivate final class Feature: Instantiable {
				    let helper: Helper
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must not be `fileprivate`: SafeDI constructs it in a generated file, where a `fileprivate` type is not visible. Remove `fileprivate`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove `fileprivate` modifier"),
						],
					),
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 47,
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
				fileprivate final class Feature: Instantiable {
				init(helper: Helper) {
				self.helper = helper
				}

				    @Received let helper: Helper
				}
				""",
			)
		}

		@Test(arguments: NestedDependencyTypeCell.all)
		func declaration_fixitAddsInitializerNoWiderThanNestedType_whenDependencyNamesTypeDeclaredInside(_ cell: NestedDependencyTypeCell) {
			assertMacroExpansion(
				"""
				@Instantiable
				\(cell.introducer) Feature: Instantiable {
				    \(cell.nestedDeclaration)

				    @Received let configuration: \(cell.propertyType)
				}
				""",
				expandedSource: """
				\(cell.introducer) Feature: Instantiable {
				    \(cell.nestedDeclaration)

				    let configuration: \(cell.propertyType)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: "\(cell.introducer) Feature: Instantiable ".count + 1,
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
				\(cell.introducer) Feature: Instantiable {
				\(cell.addedModifiers)init(configuration: \(cell.propertyType)) {
				self.configuration = configuration
				}

				    \(cell.nestedDeclaration)

				    @Received let configuration: \(cell.propertyType)
				}
				""",
			)
		}

		@Test(arguments: ["Configuration", "Self.Configuration"])
		func declaration_fixitAddsInitializerNoWiderThanNestedType_whenDependencyNamesTypeDeclaredInsideWithoutQualifyingIt(spelling: String) {
			// A class cannot spell a stored property’s type through `Self`, so the type is a struct.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Feature: Instantiable {
				    struct Configuration {}

				    @Received let configuration: \(spelling)
				}
				""",
				expandedSource: """
				public struct Feature: Instantiable {
				    struct Configuration {}

				    let configuration: \(spelling)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `configuration` lives in another type’s extension, where `\(spelling)`, declared in `Feature`, does not resolve. Write it as `Feature.Configuration`.",
						line: 5,
						column: 34,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `\(spelling)` with `Feature.Configuration`")],
					),
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 37,
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
				public struct Feature: Instantiable {
				init(configuration: \(spelling)) {
				self.configuration = configuration
				}

				    struct Configuration {}

				    @Received let configuration: \(spelling)
				}
				""",
			)
		}

		@Test(arguments: EnclosingDeclarationCell.all)
		func declaration_fixitAddsInitializerWithTheTypesEffectiveAccess_whenTypeIsDeclaredInsideAnotherDeclaration(_ cell: EnclosingDeclarationCell) {
			assertMacroExpansion(
				"""
				\(cell.enclosingIntroducer) Outer {
				    @Instantiable
				    \(cell.introducer) Feature: Instantiable {
				        @Received let helper: Helper
				    }
				}
				""",
				expandedSource: """
				\(cell.enclosingIntroducer) Outer {
				    \(cell.introducer) Feature: Instantiable {
				        let helper: Helper
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: "    \(cell.introducer) Feature: Instantiable ".count + 1,
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
				\(cell.enclosingIntroducer) Outer {
				    @Instantiable
				    \(cell.introducer) Feature: Instantiable {
				\(cell.addedModifiers)init(helper: Helper) {
				self.helper = helper
				}

				        @Received let helper: Helper
				    }
				}
				""",
			)
		}

		@Test
		func declaration_fixitAddsInitializerWithoutAccessModifier_whenTypeIsPublicInsidePublicTypeInsideInternalType() {
			assertMacroExpansion(
				"""
				enum Outer {
				    public enum Middle {
				        @Instantiable
				        public final class Feature: Instantiable {
				            @Received let helper: Helper
				        }
				    }
				}
				""",
				expandedSource: """
				enum Outer {
				    public enum Middle {
				        public final class Feature: Instantiable {
				            let helper: Helper
				        }
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 4,
						column: 50,
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
				enum Outer {
				    public enum Middle {
				        @Instantiable
				        public final class Feature: Instantiable {
				init(helper: Helper) {
				self.helper = helper
				}

				            @Received let helper: Helper
				        }
				    }
				}
				""",
			)
		}

		@Test
		func declaration_fixitAddsInitializerWithTheTypesAccess_whenDependencyNamesNarrowerTypeTheEnclosingTypeDeclares() {
			// The lexical context the compiler hands the macro carries each enclosing declaration without its members, so
			// the macro cannot see that `Outer.Configuration` is `package`: the added `public init` does not compile until
			// its access is narrowed, as for a narrower type declared in another file.
			assertMacroExpansion(
				"""
				public enum Outer {
				    package struct Configuration {}

				    @Instantiable
				    public final class Feature: Instantiable {
				        @Received let configuration: Outer.Configuration
				    }
				}
				""",
				expandedSource: """
				public enum Outer {
				    package struct Configuration {}
				    public final class Feature: Instantiable {
				        let configuration: Outer.Configuration
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 5,
						column: 46,
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
				public enum Outer {
				    package struct Configuration {}

				    @Instantiable
				    public final class Feature: Instantiable {
				public init(configuration: Outer.Configuration) {
				self.configuration = configuration
				}

				        @Received let configuration: Outer.Configuration
				    }
				}
				""",
			)
		}

		// MARK: instantiate()

		@Test(arguments: ExtensionAccessCell.all)
		func extension_fixitAddsInstantiateMethodWithTheExtensionsAccess_whenExtensionSpellsAccessLevel(_ cell: ExtensionAccessCell) {
			assertMacroExpansion(
				"""
				@Instantiable(conformsElsewhere: true)
				\(cell.introducer) ExampleService {
				}
				""",
				expandedSource: """
				\(cell.introducer) ExampleService {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension of `ExampleService` must have a `static func instantiate() -> ExampleService` method.",
						line: 2,
						column: "\(cell.introducer) ExampleService {".count + 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `\(cell.addedModifiers)static func instantiate() -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `\(cell.addedModifiers)static func instantiate() -> ExampleService` method",
				],
				fixedSource: """
				@Instantiable(conformsElsewhere: true)
				\(cell.introducer) ExampleService {
				\(cell.addedModifiers)static func instantiate() -> ExampleService
				{}


				}
				""",
			)
		}

		// MARK: Mock methods

		@Test(arguments: TypeAccessCell.mockOnly)
		func declaration_fixitAddsMockMethodWithTheTypesAccess_whenMockOnlyTypeSpellsAccessLevel(_ cell: TypeAccessCell) {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				\(cell.introducer) ExampleService {
				    @Received let helper: Helper
				}
				""",
				expandedSource: """
				\(cell.introducer) ExampleService {
				    let helper: Helper
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `static func mock(…) -> ExampleService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `\(cell.addedModifiers)static func mock(…) -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				\(cell.introducer) ExampleService {
				    @Received let helper: Helper
				\(cell.addedModifiers)static func mock(helper: Helper) -> ExampleService {ExampleService(helper: helper)}


				}
				""",
			)
		}

		@Test
		func declaration_fixitAddsMockMethodNoWiderThanNestedType_whenMockOnlyTypeReceivesTypeDeclaredInside() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    package struct Configuration {}

				    @Received let configuration: ExampleService.Configuration
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    package struct Configuration {}

				    let configuration: ExampleService.Configuration
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `static func mock(…) -> ExampleService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `package static func mock(…) -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    package struct Configuration {}

				    @Received let configuration: ExampleService.Configuration
				package static func mock(configuration: ExampleService.Configuration) -> ExampleService {ExampleService(configuration: configuration)}


				}
				""",
			)
		}

		@Test
		func declaration_fixitAddsCustomMockMethodWithTheTypesAccess_whenPackageTypeLacksMethodCustomMockNameNames() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "preview")
				package final class ExampleService: Instantiable {
				    package init(helper: Helper) {
				        self.helper = helper
				    }

				    @Received let helper: Helper
				}
				""",
				expandedSource: """
				package final class ExampleService: Instantiable {
				    package init(helper: Helper) {
				        self.helper = helper
				    }

				    let helper: Helper
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` names `preview`, but this declaration has no method named `preview`. Add a `static func preview(…)` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `package static func preview(…)` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "preview")
				package final class ExampleService: Instantiable {
				    package init(helper: Helper) {
				        self.helper = helper
				    }

				    @Received let helper: Helper
				package static func preview(helper: Helper) -> ExampleService {ExampleService(helper: helper)}


				}
				""",
			)
		}

		@Test(arguments: [
			ExtensionAccessCell(introducer: "extension", addedModifiers: ""),
			ExtensionAccessCell(introducer: "public extension", addedModifiers: ""),
		])
		func extension_fixitAddsMockMethodWithTheExtensionsAccess_whenMockOnlyExtensionLacksMockMethod(_ cell: ExtensionAccessCell) {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				\(cell.introducer) ExternalService {
				}
				""",
				expandedSource: """
				\(cell.introducer) ExternalService {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `static func mock(…) -> ExternalService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `static func mock(…) -> ExternalService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				\(cell.introducer) ExternalService {
				static func mock() -> ExternalService {ExternalService.instantiate()}


				}
				""",
			)
		}

		@Test(arguments: [
			InstantiateMethodAccessCell(instantiateModifiers: "", addedModifiers: ""),
			InstantiateMethodAccessCell(instantiateModifiers: "internal ", addedModifiers: ""),
			InstantiateMethodAccessCell(instantiateModifiers: "package ", addedModifiers: "package "),
			InstantiateMethodAccessCell(instantiateModifiers: "public ", addedModifiers: "public "),
		])
		func extension_fixitAddsCustomMockMethodWithTheInstantiateMethodsAccess_whenExtensionLacksMethodCustomMockNameNames(_ cell: InstantiateMethodAccessCell) {
			// The extended type is declared elsewhere, so the `instantiate()` method the mock stands in for shows its access.
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "preview")
				extension ExampleService: Instantiable {
				    \(cell.instantiateModifiers)static func instantiate(helper: Helper) -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    \(cell.instantiateModifiers)static func instantiate(helper: Helper) -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` names `preview`, but this declaration has no method named `preview`. Add a `static func preview(…)` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `\(cell.addedModifiers)static func preview(…)` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "preview")
				extension ExampleService: Instantiable {
				    \(cell.instantiateModifiers)static func instantiate(helper: Helper) -> ExampleService { fatalError() }
				\(cell.addedModifiers)static func preview(helper: Helper) -> ExampleService {ExampleService.instantiate(helper: helper)}


				}
				""",
			)
		}

		// MARK: TypeAccessCell

		/// A type declaration's introducer, which spells its access, and the modifiers of a declaration a fix-it adds to it.
		struct TypeAccessCell: CustomTestStringConvertible, Sendable {
			let introducer: String
			let addedModifiers: String

			var testDescription: String {
				introducer
			}

			static let all = [
				TypeAccessCell(introducer: "public final class", addedModifiers: "public "),
				TypeAccessCell(introducer: "open class", addedModifiers: "public "),
				TypeAccessCell(introducer: "package final class", addedModifiers: "package "),
				TypeAccessCell(introducer: "internal final class", addedModifiers: ""),
				TypeAccessCell(introducer: "final class", addedModifiers: ""),
				TypeAccessCell(introducer: "package struct", addedModifiers: "package "),
				TypeAccessCell(introducer: "package actor", addedModifiers: "package "),
			]

			static let mockOnly = [
				TypeAccessCell(introducer: "public struct", addedModifiers: "public "),
				TypeAccessCell(introducer: "package struct", addedModifiers: "package "),
				TypeAccessCell(introducer: "struct", addedModifiers: ""),
			]
		}

		// MARK: NestedDependencyTypeCell

		/// A type declaration's introducer, a type declared inside it, a dependency type that may name that type, and the
		/// modifiers of the initializer a fix-it adds.
		struct NestedDependencyTypeCell: CustomTestStringConvertible, Sendable {
			let introducer: String
			let nestedDeclaration: String
			let propertyType: String
			let addedModifiers: String

			var testDescription: String {
				"\(introducer) Feature { \(nestedDeclaration) } receiving \(propertyType)"
			}

			static let all = [
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "public struct Configuration {}", propertyType: "Feature.Configuration", addedModifiers: "public "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "package struct Configuration {}", propertyType: "Feature.Configuration", addedModifiers: "package "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "struct Configuration {}", propertyType: "Feature.Configuration", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "internal struct Configuration {}", propertyType: "Feature.Configuration", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "package final class", nestedDeclaration: "public struct Configuration {}", propertyType: "Feature.Configuration", addedModifiers: "package "),
				NestedDependencyTypeCell(introducer: "package final class", nestedDeclaration: "struct Configuration {}", propertyType: "Feature.Configuration", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "struct Configuration {}", propertyType: "[Feature.Configuration]", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "struct Configuration {}", propertyType: "Feature.Configuration?", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "struct Configuration {}", propertyType: "[String: Feature.Configuration]", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "package final class Configuration: Instantiable {}", propertyType: "Instantiator<Feature.Configuration>", addedModifiers: "package "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "package typealias Configuration = [String: Int]", propertyType: "Feature.Configuration", addedModifiers: "package "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "package protocol Configuration {}", propertyType: "any Feature.Configuration", addedModifiers: "package "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "package enum Configuration {}", propertyType: "Feature.Configuration", addedModifiers: "package "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "package actor Configuration {}", propertyType: "Feature.Configuration", addedModifiers: "package "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "public struct Configuration {\n        enum Mode {}\n    }", propertyType: "Feature.Configuration.Mode", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "struct Configuration {\n        public enum Mode {}\n    }", propertyType: "Feature.Configuration.Mode", addedModifiers: ""),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "public struct Configuration {\n        public enum Mode {}\n    }", propertyType: "Feature.Configuration.Mode", addedModifiers: "public "),
				// A type of the same name that another type declares is not the nested type.
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "struct Configuration {}", propertyType: "Other.Configuration", addedModifiers: "public "),
				NestedDependencyTypeCell(introducer: "public final class", nestedDeclaration: "struct Configuration {}", propertyType: "Other.Feature.Configuration", addedModifiers: "public "),
				// A type declared in every clause of an `#if` block caps the initializer by its narrowest declaration.
				NestedDependencyTypeCell(
					introducer: "public final class",
					nestedDeclaration: "#if DEBUG\n    package struct Configuration {}\n    #else\n    public struct Configuration {}\n    #endif",
					propertyType: "Feature.Configuration",
					addedModifiers: "package ",
				),
			]
		}

		// MARK: EnclosingDeclarationCell

		/// A declaration enclosing a type declaration, the type declaration's introducer, and the modifiers of the
		/// initializer a fix-it adds to the type.
		struct EnclosingDeclarationCell: CustomTestStringConvertible, Sendable {
			let enclosingIntroducer: String
			let introducer: String
			let addedModifiers: String

			var testDescription: String {
				"\(introducer) in \(enclosingIntroducer)"
			}

			static let all = [
				EnclosingDeclarationCell(enclosingIntroducer: "public enum", introducer: "final class", addedModifiers: ""),
				EnclosingDeclarationCell(enclosingIntroducer: "public enum", introducer: "public final class", addedModifiers: "public "),
				EnclosingDeclarationCell(enclosingIntroducer: "public enum", introducer: "package final class", addedModifiers: "package "),
				EnclosingDeclarationCell(enclosingIntroducer: "public struct", introducer: "open class", addedModifiers: "public "),
				// A type is no more visible than the type it is declared in.
				EnclosingDeclarationCell(enclosingIntroducer: "enum", introducer: "public final class", addedModifiers: ""),
				EnclosingDeclarationCell(enclosingIntroducer: "package enum", introducer: "public final class", addedModifiers: "package "),
				// A type that spells no access takes the access of the extension it is directly inside, and an extension
				// caps nothing.
				EnclosingDeclarationCell(enclosingIntroducer: "public extension", introducer: "final class", addedModifiers: "public "),
				EnclosingDeclarationCell(enclosingIntroducer: "package extension", introducer: "final class", addedModifiers: "package "),
				EnclosingDeclarationCell(enclosingIntroducer: "extension", introducer: "final class", addedModifiers: ""),
				EnclosingDeclarationCell(enclosingIntroducer: "extension", introducer: "public final class", addedModifiers: "public "),
				EnclosingDeclarationCell(enclosingIntroducer: "public extension", introducer: "internal final class", addedModifiers: ""),
			]
		}

		// MARK: InstantiateMethodAccessCell

		/// The modifiers of an extension's `instantiate()` method, and of a mock method a fix-it adds beside it.
		struct InstantiateMethodAccessCell: CustomTestStringConvertible, Sendable {
			let instantiateModifiers: String
			let addedModifiers: String

			var testDescription: String {
				"\(instantiateModifiers)static func instantiate"
			}
		}

		// MARK: ExtensionAccessCell

		/// An extension's introducer, which spells its access, and the modifiers of a declaration a fix-it adds to it.
		struct ExtensionAccessCell: CustomTestStringConvertible, Sendable {
			let introducer: String
			let addedModifiers: String

			var testDescription: String {
				introducer
			}

			static let all = [
				ExtensionAccessCell(introducer: "extension", addedModifiers: ""),
				ExtensionAccessCell(introducer: "public extension", addedModifiers: ""),
				ExtensionAccessCell(introducer: "package extension", addedModifiers: ""),
				ExtensionAccessCell(introducer: "internal extension", addedModifiers: ""),
				// A member of a `private` or `fileprivate` extension defaults to `fileprivate`, which generated code in
				// another file cannot call.
				ExtensionAccessCell(introducer: "fileprivate extension", addedModifiers: "internal "),
				ExtensionAccessCell(introducer: "private extension", addedModifiers: "internal "),
			]
		}
	}
#endif
