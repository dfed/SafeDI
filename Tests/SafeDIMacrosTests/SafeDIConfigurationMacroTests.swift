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

import SafeDICore

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
		func expandsWithoutIssueWhenBothPropertiesArePresent() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = ["MyModule"]
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = ["MyModule"]
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				macros: safeDIConfigurationTestMacros
			)
		}

		@Test
		func expandsWithoutIssueWhenBothPropertiesAreEmptyArrays() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				macros: safeDIConfigurationTestMacros
			)
		}

		@Test
		func expandsWithoutIssueWhenBothPropertiesHaveMultipleValues() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = ["ModuleA", "ModuleB"]
				    let additionalDirectoriesToInclude: [StaticString] = ["DirA", "DirB"]
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = ["ModuleA", "ModuleB"]
				    let additionalDirectoriesToInclude: [StaticString] = ["DirA", "DirB"]
				}
				""",
				macros: safeDIConfigurationTestMacros
			)
		}

		// MARK: Error Tests

		@Test
		func throwsErrorWhenDecoratingClass() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				class MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				expandedSource: """
				class MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration must decorate a struct",
						line: 1,
						column: 1
					),
				],
				macros: safeDIConfigurationTestMacros
			)
		}

		@Test
		func throwsErrorWhenDecoratingEnum() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				enum MyConfiguration {}
				""",
				expandedSource: """
				enum MyConfiguration {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration must decorate a struct",
						line: 1,
						column: 1
					),
				],
				macros: safeDIConfigurationTestMacros
			)
		}

		@Test
		func throwsErrorWhenAdditionalImportedModulesHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = someVariable
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = someVariable
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalImportedModules` property must be initialized with an array of string literals",
						line: 1,
						column: 1
					),
				],
				macros: safeDIConfigurationTestMacros
			)
		}

		@Test
		func throwsErrorWhenAdditionalDirectoriesToIncludeHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				    let additionalDirectoriesToInclude: [StaticString] = someVariable
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				    let additionalDirectoriesToInclude: [StaticString] = someVariable
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalDirectoriesToInclude` property must be initialized with an array of string literals",
						line: 1,
						column: 1
					),
				],
				macros: safeDIConfigurationTestMacros
			)
		}

		@Test
		func throwsErrorWhenAdditionalImportedModulesContainsInterpolation() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = ["\\(someVar)"]
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = ["\\(someVar)"]
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalImportedModules` property must be initialized with an array of string literals",
						line: 1,
						column: 1
					),
				],
				macros: safeDIConfigurationTestMacros
			)
		}

		// MARK: Fix-It Tests

		@Test
		func fixItAddsBothMissingProperties() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration-decorated type must have a `let additionalImportedModules: [StaticString]` property",
						line: 2,
						column: 24,
						fixIts: [
							FixItSpec(message: "Add `let additionalImportedModules: [StaticString]` property"),
						]
					),
				],
				macros: safeDIConfigurationTestMacros,
				applyFixIts: [
					"Add `let additionalImportedModules: [StaticString]` property",
				],
				fixedSource: """
				@SafeDIConfiguration
				struct MyConfiguration {
				/// The names of modules to import in the generated dependency tree.
				/// This list is in addition to the import statements found in files that declare @Instantiable types.
				let additionalImportedModules: [StaticString] = []
				/// Directories containing Swift files to include, relative to the executing directory.
				/// This property only applies to SafeDI repos that utilize the SPM plugin via an Xcode project.
				let additionalDirectoriesToInclude: [StaticString] = []
				}
				"""
			)
		}

		@Test
		func fixItAddsOnlyMissingAdditionalDirectoriesToInclude() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalImportedModules: [StaticString] = []
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration-decorated type must have a `let additionalDirectoriesToInclude: [StaticString]` property",
						line: 2,
						column: 24,
						fixIts: [
							FixItSpec(message: "Add `let additionalDirectoriesToInclude: [StaticString]` property"),
						]
					),
				],
				macros: safeDIConfigurationTestMacros,
				applyFixIts: [
					"Add `let additionalDirectoriesToInclude: [StaticString]` property",
				],
				fixedSource: """
				@SafeDIConfiguration
				struct MyConfiguration {
				/// Directories containing Swift files to include, relative to the executing directory.
				/// This property only applies to SafeDI repos that utilize the SPM plugin via an Xcode project.
				let additionalDirectoriesToInclude: [StaticString] = []
				    let additionalImportedModules: [StaticString] = []
				}
				"""
			)
		}

		@Test
		func fixItAddsOnlyMissingAdditionalImportedModules() {
			assertMacroExpansion(
				"""
				@SafeDIConfiguration
				struct MyConfiguration {
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				expandedSource: """
				struct MyConfiguration {
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@SafeDIConfiguration-decorated type must have a `let additionalImportedModules: [StaticString]` property",
						line: 2,
						column: 24,
						fixIts: [
							FixItSpec(message: "Add `let additionalImportedModules: [StaticString]` property"),
						]
					),
				],
				macros: safeDIConfigurationTestMacros,
				applyFixIts: [
					"Add `let additionalImportedModules: [StaticString]` property",
				],
				fixedSource: """
				@SafeDIConfiguration
				struct MyConfiguration {
				/// The names of modules to import in the generated dependency tree.
				/// This list is in addition to the import statements found in files that declare @Instantiable types.
				let additionalImportedModules: [StaticString] = []
				    let additionalDirectoriesToInclude: [StaticString] = []
				}
				"""
			)
		}
	}
#endif
