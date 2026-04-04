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

import SafeDICore
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(SafeDIMacros)
	@testable import SafeDIMacros

	let safeDIConfigurationTestMacros: [String: Macro.Type] = [
		SafeDIConfigurationVisitor.macroName: SafeDIConfigurationMacro.self,
	]

	struct SafeDIConfigurationMacroTests {
		// MARK: Behavior Tests

		@Test
		func providingMacros_containsSafeDIConfiguration() {
			#expect(SafeDIMacroPlugin().providingMacros.contains(where: { $0 == SafeDIConfigurationMacro.self }))
		}

		@Test
		func expandsWithoutIssueWhenAllPropertiesArePresent() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = ["MyModule"]
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = ["MyModule"]
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expandsWithoutIssueWhenAllPropertiesAreDefaults() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expandsWithoutIssueWhenMockConditionalCompilationIsNil() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = nil
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = nil
				}
				""",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expandsWithoutIssueWhenMockConditionalCompilationIsCustomValue() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "TESTING"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "TESTING"
				}
				""",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expandsWithoutIssueWhenArrayPropertiesHaveMultipleValues() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = ["ModuleA", "ModuleB"]
				    static let additionalDirectoriesToInclude: [StaticString] = ["DirA", "DirB"]
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = ["ModuleA", "ModuleB"]
				    static let additionalDirectoriesToInclude: [StaticString] = ["DirA", "DirB"]
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				macros: safeDIConfigurationTestMacros,
			)
		}

		// MARK: Error Tests

		@Test
		func throwsErrorWhenDecoratingClass() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				class MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				class MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration must decorate an enum",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func throwsErrorWhenDecoratingStruct() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration must decorate an enum",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func throwsErrorWhenAdditionalImportedModulesHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = someVariable
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = someVariable
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalImportedModules` property must be initialized with an array of string literals",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func throwsErrorWhenAdditionalDirectoriesToIncludeHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = someVariable
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = someVariable
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalDirectoriesToInclude` property must be initialized with an array of string literals",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func throwsErrorWhenAdditionalImportedModulesContainsInterpolation() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = ["\\(someVar)"]
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = ["\\(someVar)"]
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalImportedModules` property must be initialized with an array of string literals",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func throwsErrorWhenMockConditionalCompilationHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = someVariable
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = someVariable
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `mockConditionalCompilation` property must be initialized with a string literal or `nil`",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		// MARK: Fix-It Tests

		@Test
		func fixItAddsAllMissingProperties() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration-decorated type must have a `static let additionalImportedModules: [StaticString]` property",
						line: 2,
						column: 22,
						fixIts: [
							FixItSpec(message: "Add `static let additionalImportedModules: [StaticString]` property"),
						],
					),
				],
				macros: safeDIConfigurationTestMacros,
				applyFixIts: [
					"Add `static let additionalImportedModules: [StaticString]` property",
				],
				fixedSource: """
				@SafeDIConfiguration
				enum MyConfiguration {
				/// The names of modules to import in the generated dependency tree.
				/// This list is in addition to the import statements found in files that declare @Instantiable types.
				static let additionalImportedModules: [StaticString] = []
				/// Directories containing Swift files to include, relative to the executing directory.
				/// This property only applies to SafeDI repos that utilize the SPM plugin via an Xcode project.
				static let additionalDirectoriesToInclude: [StaticString] = []
				/// The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`).
				/// Set to `nil` to generate mocks without conditional compilation.
				static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
			)
		}

		@Test
		func fixItAddsOnlyMissingMockConditionalCompilation() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration-decorated type must have a `static let mockConditionalCompilation: StaticString?` property",
						line: 2,
						column: 22,
						fixIts: [
							FixItSpec(message: "Add `static let mockConditionalCompilation: StaticString?` property"),
						],
					),
				],
				macros: safeDIConfigurationTestMacros,
				applyFixIts: [
					"Add `static let mockConditionalCompilation: StaticString?` property",
				],
				fixedSource: """
				@SafeDIConfiguration
				enum MyConfiguration {
				/// The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`).
				/// Set to `nil` to generate mocks without conditional compilation.
				static let mockConditionalCompilation: StaticString? = "DEBUG"
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
			)
		}

		@Test
		func fixItAddsOnlyMissingAdditionalDirectoriesToInclude() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration-decorated type must have a `static let additionalDirectoriesToInclude: [StaticString]` property",
						line: 2,
						column: 22,
						fixIts: [
							FixItSpec(message: "Add `static let additionalDirectoriesToInclude: [StaticString]` property"),
						],
					),
				],
				macros: safeDIConfigurationTestMacros,
				applyFixIts: [
					"Add `static let additionalDirectoriesToInclude: [StaticString]` property",
				],
				fixedSource: """
				@SafeDIConfiguration
				enum MyConfiguration {
				/// Directories containing Swift files to include, relative to the executing directory.
				/// This property only applies to SafeDI repos that utilize the SPM plugin via an Xcode project.
				static let additionalDirectoriesToInclude: [StaticString] = []
				    static let additionalImportedModules: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
			)
		}

		@Test
		func fixItAddsOnlyMissingAdditionalImportedModules() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration-decorated type must have a `static let additionalImportedModules: [StaticString]` property",
						line: 2,
						column: 22,
						fixIts: [
							FixItSpec(message: "Add `static let additionalImportedModules: [StaticString]` property"),
						],
					),
				],
				macros: safeDIConfigurationTestMacros,
				applyFixIts: [
					"Add `static let additionalImportedModules: [StaticString]` property",
				],
				fixedSource: """
				@SafeDIConfiguration
				enum MyConfiguration {
				/// The names of modules to import in the generated dependency tree.
				/// This list is in addition to the import statements found in files that declare @Instantiable types.
				static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
			)
		}

		@Test
		func throwsErrorWhenMockConditionalCompilationHasNoInitializer() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString?
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `mockConditionalCompilation` property must be initialized with a string literal or `nil`",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func throwsErrorWhenMockConditionalCompilationHasInterpolation() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "\\(flag)"
				}
				""",
				expandedSource: """
				enum MyConfiguration {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let mockConditionalCompilation: StaticString? = "\\(flag)"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `mockConditionalCompilation` property must be initialized with a string literal or `nil`",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}
	}
#endif
