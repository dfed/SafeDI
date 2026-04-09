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
import SwiftSyntax
import SwiftSyntaxMacros

public struct SafeDIConfigurationMacro: DeclarationMacro {
	public static func expansion(
		of node: some FreestandingMacroExpansionSyntax,
		in _: some MacroExpansionContext,
	) throws -> [DeclSyntax] {
		for argument in node.arguments {
			guard let label = argument.label?.text else {
				throw SafeDIConfigurationError.unexpectedUnlabeledArgument
			}
			switch label {
			case SafeDIConfigurationVisitor.additionalImportedModulesArgumentLabel:
				guard isArrayOfStringLiterals(argument.expression) else {
					throw SafeDIConfigurationError.additionalImportedModulesNotStringLiteralArray
				}
			case SafeDIConfigurationVisitor.additionalDirectoriesToIncludeArgumentLabel:
				guard isArrayOfStringLiterals(argument.expression) else {
					throw SafeDIConfigurationError.additionalDirectoriesToIncludeNotStringLiteralArray
				}
			case SafeDIConfigurationVisitor.additionalMocksToGenerateArgumentLabel:
				guard isArrayOfStringLiterals(argument.expression) else {
					throw SafeDIConfigurationError.additionalMocksToGenerateNotStringLiteralArray
				}
			case SafeDIConfigurationVisitor.mockConditionalCompilationArgumentLabel:
				guard isStringLiteralOrNil(argument.expression) else {
					throw SafeDIConfigurationError.mockConditionalCompilationNotStringLiteralOrNil
				}
			case let unknownLabel:
				throw SafeDIConfigurationError.unexpectedArgument(unknownLabel)
			}
		}

		// This macro purposefully does not expand.
		// This macro serves as a validator, nothing more.
		return []
	}

	// MARK: Private

	private static func isArrayOfStringLiterals(_ expression: ExprSyntax) -> Bool {
		guard let arrayExpr = ArrayExprSyntax(expression) else {
			return false
		}
		for element in arrayExpr.elements {
			guard let stringLiteral = StringLiteralExprSyntax(element.expression),
			      stringLiteral.segments.count == 1,
			      case .stringSegment = stringLiteral.segments.first
			else {
				return false
			}
		}
		return true
	}

	private static func isStringLiteralOrNil(_ expression: ExprSyntax) -> Bool {
		if NilLiteralExprSyntax(expression) != nil {
			true
		} else if let stringLiteral = StringLiteralExprSyntax(expression),
		          stringLiteral.segments.count == 1,
		          case .stringSegment = stringLiteral.segments.first
		{
			true
		} else {
			false
		}
	}

	// MARK: - SafeDIConfigurationError

	private enum SafeDIConfigurationError: Error, CustomStringConvertible {
		case additionalImportedModulesNotStringLiteralArray
		case additionalDirectoriesToIncludeNotStringLiteralArray
		case additionalMocksToGenerateNotStringLiteralArray
		case mockConditionalCompilationNotStringLiteralOrNil
		case unexpectedUnlabeledArgument
		case unexpectedArgument(String)

		var description: String {
			switch self {
			case .additionalImportedModulesNotStringLiteralArray:
				"The `\(SafeDIConfigurationVisitor.additionalImportedModulesArgumentLabel)` argument must be an array of string literals"
			case .additionalDirectoriesToIncludeNotStringLiteralArray:
				"The `\(SafeDIConfigurationVisitor.additionalDirectoriesToIncludeArgumentLabel)` argument must be an array of string literals"
			case .additionalMocksToGenerateNotStringLiteralArray:
				"The `\(SafeDIConfigurationVisitor.additionalMocksToGenerateArgumentLabel)` argument must be an array of string literals"
			case .mockConditionalCompilationNotStringLiteralOrNil:
				"The `\(SafeDIConfigurationVisitor.mockConditionalCompilationArgumentLabel)` argument must be a string literal or `nil`"
			case .unexpectedUnlabeledArgument:
				"#\(SafeDIConfigurationVisitor.macroName) does not accept unlabeled arguments"
			case let .unexpectedArgument(label):
				"#\(SafeDIConfigurationVisitor.macroName) does not accept an argument labeled `\(label)`"
			}
		}
	}
}
