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

import SwiftSyntax

/// Extracts configuration from a `#SafeDIConfiguration(...)` freestanding macro invocation.
public enum SafeDIConfigurationVisitor {
	// MARK: Public

	public static let macroName = "SafeDIConfiguration"
	public static let additionalImportedModulesArgumentLabel = "additionalImportedModules"
	public static let additionalDirectoriesToIncludeArgumentLabel = "additionalDirectoriesToInclude"
	public static let additionalMocksToGenerateArgumentLabel = "additionalMocksToGenerate"
	public static let mockConditionalCompilationArgumentLabel = "mockConditionalCompilation"

	/// Extracts a `SafeDIConfiguration` from a `MacroExpansionDeclSyntax` node
	/// representing a `#SafeDIConfiguration(...)` invocation.
	public static func extractConfiguration(from node: some FreestandingMacroExpansionSyntax) -> SafeDIConfiguration {
		var additionalImportedModules = [String]()
		var additionalDirectoriesToInclude = [String]()
		var additionalMocksToGenerate = [String]()
		var mockConditionalCompilation: String? = "DEBUG"

		for argument in node.arguments {
			guard let label = argument.label?.text else {
				continue
			}
			switch label {
			case additionalImportedModulesArgumentLabel:
				if let values = extractStringLiterals(from: argument.expression) {
					additionalImportedModules = values
				}
			case additionalDirectoriesToIncludeArgumentLabel:
				if let values = extractStringLiterals(from: argument.expression) {
					additionalDirectoriesToInclude = values
				}
			case additionalMocksToGenerateArgumentLabel:
				if let values = extractStringLiterals(from: argument.expression) {
					additionalMocksToGenerate = values
				}
			case mockConditionalCompilationArgumentLabel:
				if let value = extractOptionalStringLiteral(from: argument.expression) {
					mockConditionalCompilation = value
				}
			default:
				continue
			}
		}

		return SafeDIConfiguration(
			additionalImportedModules: additionalImportedModules,
			additionalDirectoriesToInclude: additionalDirectoriesToInclude,
			additionalMocksToGenerate: additionalMocksToGenerate,
			mockConditionalCompilation: mockConditionalCompilation,
		)
	}

	// MARK: Private

	private static func extractStringLiterals(from expression: ExprSyntax) -> [String]? {
		guard let arrayExpr = ArrayExprSyntax(expression) else {
			return nil
		}
		var values = [String]()
		for element in arrayExpr.elements {
			guard let stringLiteral = StringLiteralExprSyntax(element.expression),
			      stringLiteral.segments.count == 1,
			      case let .stringSegment(segment) = stringLiteral.segments.first
			else {
				return nil
			}
			values.append(segment.content.text)
		}
		return values
	}

	/// Extracts a `String?` from an expression that is a string literal or `nil`.
	/// Returns `.some(.some(string))` for a string literal, `.some(.none)` for `nil`,
	/// and `nil` if the expression is not a valid literal.
	private static func extractOptionalStringLiteral(from expression: ExprSyntax) -> String?? {
		if NilLiteralExprSyntax(expression) != nil {
			.some(nil)
		} else {
			if let stringLiteral = StringLiteralExprSyntax(expression),
			   stringLiteral.segments.count == 1,
			   case let .stringSegment(segment) = stringLiteral.segments.first
			{
				.some(segment.content.text)
			} else {
				nil
			}
		}
	}
}
