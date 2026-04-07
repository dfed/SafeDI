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
		func expansion_expandsWithoutIssue_whenNoArguments() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration()
				""",
				expandedSource: "",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_expandsWithoutIssue_whenAllArguments() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    additionalImportedModules: ["MyModule"],
				    additionalDirectoriesToInclude: ["DirA"],
				    mockConditionalCompilation: "DEBUG"
				)
				""",
				expandedSource: "",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_expandsWithoutIssue_whenEmptyArrays() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    additionalImportedModules: [],
				    additionalDirectoriesToInclude: []
				)
				""",
				expandedSource: "",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_expandsWithoutIssue_whenMockConditionalCompilationIsNil() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    mockConditionalCompilation: nil
				)
				""",
				expandedSource: "",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_expandsWithoutIssue_whenCustomMockConditionalCompilation() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    mockConditionalCompilation: "TESTING"
				)
				""",
				expandedSource: "",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_expandsWithoutIssue_whenMultipleValues() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    additionalImportedModules: ["ModuleA", "ModuleB"],
				    additionalDirectoriesToInclude: ["DirA", "DirB"]
				)
				""",
				expandedSource: "",
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_expandsWithoutIssue_whenOnlyAdditionalImportedModules() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    additionalImportedModules: ["MyModule"]
				)
				""",
				expandedSource: "",
				macros: safeDIConfigurationTestMacros,
			)
		}

		// MARK: Error Tests

		@Test
		func expansion_throwsError_whenAdditionalImportedModulesHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    additionalImportedModules: someVariable
				)
				""",
				expandedSource: """
				#SafeDIConfiguration(
				    additionalImportedModules: someVariable
				)
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalImportedModules` argument must be an array of string literals",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_throwsError_whenAdditionalDirectoriesToIncludeHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: someVariable
				)
				""",
				expandedSource: """
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: someVariable
				)
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalDirectoriesToInclude` argument must be an array of string literals",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_throwsError_whenAdditionalImportedModulesContainsInterpolation() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    additionalImportedModules: ["\\(someVar)"]
				)
				""",
				expandedSource: """
				#SafeDIConfiguration(
				    additionalImportedModules: ["\\(someVar)"]
				)
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `additionalImportedModules` argument must be an array of string literals",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_throwsError_whenMockConditionalCompilationHasNonLiteralValue() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    mockConditionalCompilation: someVariable
				)
				""",
				expandedSource: """
				#SafeDIConfiguration(
				    mockConditionalCompilation: someVariable
				)
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `mockConditionalCompilation` argument must be a string literal or `nil`",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}

		@Test
		func expansion_throwsError_whenMockConditionalCompilationHasInterpolation() {
			assertMacroExpansion(
				"""
				#SafeDIConfiguration(
				    mockConditionalCompilation: "\\(flag)"
				)
				""",
				expandedSource: """
				#SafeDIConfiguration(
				    mockConditionalCompilation: "\\(flag)"
				)
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The `mockConditionalCompilation` argument must be a string literal or `nil`",
						line: 1,
						column: 1,
					),
				],
				macros: safeDIConfigurationTestMacros,
			)
		}
	}
#endif
