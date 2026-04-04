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
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct SafeDIConfigurationMacro: PeerMacro {
	public static func expansion(
		of _: AttributeSyntax,
		providingPeersOf declaration: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext,
	) throws -> [DeclSyntax] {
		guard let enumDecl = EnumDeclSyntax(declaration) else {
			throw SafeDIConfigurationError.decoratingNonEnum
		}

		let visitor = SafeDIConfigurationVisitor()
		visitor.walk(enumDecl)

		var hasMissingProperties = false

		if !visitor.foundAdditionalImportedModules {
			hasMissingProperties = true
		} else if !visitor.additionalImportedModulesIsValid {
			throw SafeDIConfigurationError.additionalImportedModulesNotStringLiteralArray
		}

		if !visitor.foundAdditionalDirectoriesToInclude {
			hasMissingProperties = true
		} else if !visitor.additionalDirectoriesToIncludeIsValid {
			throw SafeDIConfigurationError.additionalDirectoriesToIncludeNotStringLiteralArray
		}

		if !visitor.foundGenerateMocks {
			hasMissingProperties = true
		} else if !visitor.generateMocksIsValid {
			throw SafeDIConfigurationError.generateMocksNotBoolLiteral
		}

		if !visitor.foundMockConditionalCompilation {
			hasMissingProperties = true
		} else if !visitor.mockConditionalCompilationIsValid {
			throw SafeDIConfigurationError.mockConditionalCompilationNotStringLiteralOrNil
		}

		if hasMissingProperties {
			var modifiedDecl = enumDecl
			var membersToInsert = [MemberBlockItemSyntax]()
			if !visitor.foundAdditionalImportedModules {
				membersToInsert.append(MemberBlockItemSyntax(
					leadingTrivia: .newline,
					decl: DeclSyntax("""
					/// The names of modules to import in the generated dependency tree.
					/// This list is in addition to the import statements found in files that declare @Instantiable types.
					static let \(raw: SafeDIConfigurationVisitor.additionalImportedModulesPropertyName): [StaticString] = []
					"""),
				))
			}
			if !visitor.foundAdditionalDirectoriesToInclude {
				membersToInsert.append(MemberBlockItemSyntax(
					leadingTrivia: .newline,
					decl: DeclSyntax("""
					/// Directories containing Swift files to include, relative to the executing directory.
					/// This property only applies to SafeDI repos that utilize the SPM plugin via an Xcode project.
					static let \(raw: SafeDIConfigurationVisitor.additionalDirectoriesToIncludePropertyName): [StaticString] = []
					"""),
				))
			}
			if !visitor.foundGenerateMocks {
				membersToInsert.append(MemberBlockItemSyntax(
					leadingTrivia: .newline,
					decl: DeclSyntax("""
					/// Whether to generate `mock()` methods for `@Instantiable` types.
					static let \(raw: SafeDIConfigurationVisitor.generateMocksPropertyName): Bool = true
					"""),
				))
			}
			if !visitor.foundMockConditionalCompilation {
				membersToInsert.append(MemberBlockItemSyntax(
					leadingTrivia: .newline,
					decl: DeclSyntax("""
					/// The conditional compilation flag to wrap generated mock code in (e.g. `"DEBUG"`).
					/// Set to `nil` to generate mocks without conditional compilation.
					static let \(raw: SafeDIConfigurationVisitor.mockConditionalCompilationPropertyName): StaticString? = "DEBUG"
					"""),
				))
			}
			for member in membersToInsert.reversed() {
				modifiedDecl.memberBlock.members.insert(
					member,
					at: modifiedDecl.memberBlock.members.startIndex,
				)
			}
			let missingPropertyError: FixableSafeDIConfigurationError = if !visitor.foundAdditionalImportedModules {
				.missingAdditionalImportedModulesProperty
			} else if !visitor.foundAdditionalDirectoriesToInclude {
				.missingAdditionalDirectoriesToIncludeProperty
			} else if !visitor.foundGenerateMocks {
				.missingGenerateMocksProperty
			} else {
				.missingMockConditionalCompilationProperty
			}
			context.diagnose(Diagnostic(
				node: Syntax(enumDecl.memberBlock),
				error: missingPropertyError,
				changes: [
					.replace(
						oldNode: Syntax(enumDecl),
						newNode: Syntax(modifiedDecl),
					),
				],
			))
		}

		// This macro purposefully does not expand.
		// This macro serves as a validator, nothing more.
		return []
	}

	// MARK: - SafeDIConfigurationError

	private enum SafeDIConfigurationError: Error, CustomStringConvertible {
		case decoratingNonEnum
		case additionalImportedModulesNotStringLiteralArray
		case additionalDirectoriesToIncludeNotStringLiteralArray
		case generateMocksNotBoolLiteral
		case mockConditionalCompilationNotStringLiteralOrNil

		var description: String {
			switch self {
			case .decoratingNonEnum:
				"@\(SafeDIConfigurationVisitor.macroName) must decorate an enum"
			case .additionalImportedModulesNotStringLiteralArray:
				"The `\(SafeDIConfigurationVisitor.additionalImportedModulesPropertyName)` property must be initialized with an array of string literals"
			case .additionalDirectoriesToIncludeNotStringLiteralArray:
				"The `\(SafeDIConfigurationVisitor.additionalDirectoriesToIncludePropertyName)` property must be initialized with an array of string literals"
			case .generateMocksNotBoolLiteral:
				"The `\(SafeDIConfigurationVisitor.generateMocksPropertyName)` property must be initialized with a Bool literal (`true` or `false`)"
			case .mockConditionalCompilationNotStringLiteralOrNil:
				"The `\(SafeDIConfigurationVisitor.mockConditionalCompilationPropertyName)` property must be initialized with a string literal or `nil`"
			}
		}
	}
}
