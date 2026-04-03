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

public final class SafeDIConfigurationVisitor: SyntaxVisitor {
	// MARK: Initialization

	public init() {
		super.init(viewMode: .sourceAccurate)
	}

	// MARK: SyntaxVisitor

	public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		for binding in node.bindings {
			guard let identifierPattern = IdentifierPatternSyntax(binding.pattern) else {
				continue
			}
			let name = identifierPattern.identifier.text
			if name == Self.additionalImportedModulesPropertyName {
				foundAdditionalImportedModules = true
				if let values = extractStringLiterals(from: binding) {
					additionalImportedModules = values
				} else {
					additionalImportedModulesIsValid = false
				}
			} else if name == Self.additionalDirectoriesToIncludePropertyName {
				foundAdditionalDirectoriesToInclude = true
				if let values = extractStringLiterals(from: binding) {
					additionalDirectoriesToInclude = values
				} else {
					additionalDirectoriesToIncludeIsValid = false
				}
			}
		}
		return .skipChildren
	}

	// MARK: Public

	public static let macroName = "SafeDIConfiguration"
	public static let additionalImportedModulesPropertyName = "additionalImportedModules"
	public static let additionalDirectoriesToIncludePropertyName = "additionalDirectoriesToInclude"

	public private(set) var additionalImportedModules = [String]()
	public private(set) var additionalDirectoriesToInclude = [String]()
	public private(set) var foundAdditionalImportedModules = false
	public private(set) var foundAdditionalDirectoriesToInclude = false
	public private(set) var additionalImportedModulesIsValid = true
	public private(set) var additionalDirectoriesToIncludeIsValid = true

	public var configuration: SafeDIConfiguration {
		SafeDIConfiguration(
			additionalImportedModules: additionalImportedModules,
			additionalDirectoriesToInclude: additionalDirectoriesToInclude,
		)
	}

	// MARK: Private

	private func extractStringLiterals(from binding: PatternBindingSyntax) -> [String]? {
		guard let initializer = binding.initializer,
		      let arrayExpr = ArrayExprSyntax(initializer.value)
		else {
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
}
