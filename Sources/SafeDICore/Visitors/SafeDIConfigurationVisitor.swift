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

	public override func visit(_: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		nestingDepth += 1
		return .visitChildren
	}

	public override func visitPost(_: StructDeclSyntax) {
		nestingDepth -= 1
	}

	public override func visit(_: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		nestingDepth += 1
		return .visitChildren
	}

	public override func visitPost(_: ClassDeclSyntax) {
		nestingDepth -= 1
	}

	public override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		nestingDepth += 1
		return .visitChildren
	}

	public override func visitPost(_: EnumDeclSyntax) {
		nestingDepth -= 1
	}

	public override func visit(_: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		nestingDepth += 1
		return .visitChildren
	}

	public override func visitPost(_: ActorDeclSyntax) {
		nestingDepth -= 1
	}

	public override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
		nestingDepth += 1
		return .visitChildren
	}

	public override func visitPost(_: ProtocolDeclSyntax) {
		nestingDepth -= 1
	}

	public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		guard nestingDepth <= 1 else { return .skipChildren }
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
			} else if name == Self.generateMocksPropertyName {
				foundGenerateMocks = true
				if let value = extractBoolLiteral(from: binding) {
					generateMocks = value
				} else {
					generateMocksIsValid = false
				}
			} else if name == Self.mockConditionalCompilationPropertyName {
				foundMockConditionalCompilation = true
				if let value = extractOptionalStringLiteral(from: binding) {
					mockConditionalCompilation = value
				} else {
					mockConditionalCompilationIsValid = false
				}
			}
		}
		return .skipChildren
	}

	// MARK: Public

	public static let macroName = "SafeDIConfiguration"
	public static let additionalImportedModulesPropertyName = "additionalImportedModules"
	public static let additionalDirectoriesToIncludePropertyName = "additionalDirectoriesToInclude"
	public static let generateMocksPropertyName = "generateMocks"
	public static let mockConditionalCompilationPropertyName = "mockConditionalCompilation"

	public private(set) var additionalImportedModules = [String]()
	public private(set) var additionalDirectoriesToInclude = [String]()
	public private(set) var generateMocks = true
	public private(set) var mockConditionalCompilation: String? = "DEBUG"
	public private(set) var foundAdditionalImportedModules = false
	public private(set) var foundAdditionalDirectoriesToInclude = false
	public private(set) var foundGenerateMocks = false
	public private(set) var foundMockConditionalCompilation = false
	public private(set) var additionalImportedModulesIsValid = true
	public private(set) var additionalDirectoriesToIncludeIsValid = true
	public private(set) var generateMocksIsValid = true
	public private(set) var mockConditionalCompilationIsValid = true

	public var configuration: SafeDIConfiguration {
		SafeDIConfiguration(
			additionalImportedModules: additionalImportedModules,
			additionalDirectoriesToInclude: additionalDirectoriesToInclude,
			generateMocks: generateMocks,
			mockConditionalCompilation: mockConditionalCompilation,
		)
	}

	// MARK: Private

	/// Tracks nesting depth to ignore variables declared inside nested types.
	/// Starts at 0; the config enum itself bumps it to 1; nested types bump it further.
	private var nestingDepth = 0

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

	private func extractBoolLiteral(from binding: PatternBindingSyntax) -> Bool? {
		guard let initializer = binding.initializer,
		      let boolLiteral = BooleanLiteralExprSyntax(initializer.value)
		else {
			return nil
		}
		return boolLiteral.literal.tokenKind == .keyword(.true)
	}

	/// Extracts a `String?` from a binding initialized with a string literal or `nil`.
	/// Returns a `.some(.some(string))` for a string literal, `.some(.none)` for `nil`,
	/// and `nil` if the initializer is not a valid literal.
	private func extractOptionalStringLiteral(from binding: PatternBindingSyntax) -> String?? {
		guard let initializer = binding.initializer else {
			return nil
		}
		if NilLiteralExprSyntax(initializer.value) != nil {
			return .some(nil)
		}
		if let stringLiteral = StringLiteralExprSyntax(initializer.value),
		   stringLiteral.segments.count == 1,
		   case let .stringSegment(segment) = stringLiteral.segments.first
		{
			return .some(segment.content.text)
		}
		return nil
	}
}
