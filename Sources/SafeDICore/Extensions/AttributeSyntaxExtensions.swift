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

extension AttributeSyntax {
	public var isRoot: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "isRoot"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var isRootValue: Bool {
		guard let isRoot,
		      let boolLiteral = BooleanLiteralExprSyntax(isRoot)
		else {
			return false
		}
		return boolLiteral.literal.tokenKind == .keyword(.true)
	}

	public var generateDependencyTree: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "generateDependencyTree"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var generatesDependencyTreeValue: Bool {
		guard let generateDependencyTree,
		      let boolLiteral = BooleanLiteralExprSyntax(generateDependencyTree)
		else {
			return false
		}
		return boolLiteral.literal.tokenKind == .keyword(.true)
	}

	public var fulfillingAdditionalTypes: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "fulfillingAdditionalTypes"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var conformsElsewhere: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "conformsElsewhere"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var mockAttributes: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "mockAttributes"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var generatedInitializerAttributes: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "generatedInitializerAttributes"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var generatedAttributes: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "generatedAttributes"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var mockOnly: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "mockOnly"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var mockOnlyValue: Bool {
		guard let mockOnly,
		      let boolLiteral = BooleanLiteralExprSyntax(mockOnly)
		else {
			return false
		}
		return boolLiteral.literal.tokenKind == .keyword(.true)
	}

	public var generateMock: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "generateMock"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	/// Whether the `generateMock:` argument asks for a generated `mock()`, with any access.
	public var generateMockValue: Bool {
		mockGenerationValue?.generatesMock ?? false
	}

	/// The `generateMock:` argument: `.none` when it is absent, and `nil` when it is spelled other than as a boolean
	/// literal, `.none`, `.internal`, `.public`, or `MockGeneration.` followed by one of those cases.
	public var mockGenerationValue: MockGeneration? {
		guard let generateMock else {
			return MockGeneration.none
		}
		return Self.mockGeneration(spelledAs: generateMock)
	}

	/// The `MockGeneration` an argument spells: a boolean literal, `.none`, `.internal`, `.public`, or `MockGeneration.`
	/// followed by one of those cases. `nil` for any other spelling.
	public static func mockGeneration(spelledAs expression: ExprSyntax) -> MockGeneration? {
		if let boolLiteral = BooleanLiteralExprSyntax(expression) {
			return boolLiteral.literal.tokenKind == .keyword(.true) ? .internal : MockGeneration.none
		}
		guard let memberAccess = MemberAccessExprSyntax(expression),
		      memberAccess.declName.argumentNames == nil
		else {
			return nil
		}
		if let base = memberAccess.base {
			guard let baseReference = DeclReferenceExprSyntax(base),
			      baseReference.argumentNames == nil,
			      baseReference.baseName.text == "MockGeneration"
			else {
				return nil
			}
		}
		return switch memberAccess.declName.baseName.text {
		case "none":
			MockGeneration.none
		case "internal":
			.internal
		case "public":
			.public
		default:
			nil
		}
	}

	public var customMockName: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first(where: {
		      	$0.label?.text == "customMockName"
		      })
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var customMockNameValue: String? {
		Self.text(ofStringLiteral: customMockName)
	}

	public var mockAttributesValue: String {
		Self.text(ofStringLiteral: mockAttributes) ?? ""
	}

	public var generatedInitializerAttributesValue: String {
		Self.text(ofStringLiteral: generatedInitializerAttributes) ?? ""
	}

	/// The text of `generatedAttributes`, or `nil` when the argument is not given as a string literal without
	/// interpolation. The macro's overloads never take it together with `generatedInitializerAttributes` or
	/// `mockAttributes`, for both of which it stands.
	public var generatedAttributesValue: String? {
		Self.text(ofStringLiteral: generatedAttributes)
	}

	/// The text of `expression` when it is a string literal without interpolation, or `nil`.
	private static func text(ofStringLiteral expression: ExprSyntax?) -> String? {
		guard let expression,
		      let stringLiteral = StringLiteralExprSyntax(expression),
		      stringLiteral.segments.count == 1,
		      case let .stringSegment(segment) = stringLiteral.segments.first
		else {
			return nil
		}
		return segment.content.text
	}

	public var fulfilledByDependencyNamed: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first,
		      firstLabeledExpression.label?.text == "fulfilledByDependencyNamed"
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	/// The name `fulfilledByDependencyNamed:` gives, in `spelledAsIdentifier` spelling.
	public var fulfillingPropertyName: String? {
		guard let fulfilledByDependencyNamed,
		      let stringLiteral = StringLiteralExprSyntax(fulfilledByDependencyNamed),
		      case let .stringSegment(firstSegment) = stringLiteral.segments.first
		else {
			return nil
		}

		return firstSegment.content.text.spelledAsIdentifier
	}

	public var fulfilledByType: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let firstLabeledExpression = labeledExpressionList.first,
		      firstLabeledExpression.label?.text == "fulfilledByType"
		else {
			return nil
		}

		return firstLabeledExpression.expression
	}

	public var ofType: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let expectedOfTypeLabeledExpression = labeledExpressionList.dropFirst().first,
		      expectedOfTypeLabeledExpression.label?.text == "ofType"
		else {
			return nil
		}

		return expectedOfTypeLabeledExpression.expression
	}

	public var erasedToConcreteExistential: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let erasedToConcreteExistentialLabeledExpression = labeledExpressionList.dropFirst().first(where: {
		      	// In `@Instantiated`, the `erasedToConcreteExistential` parameter is the second parameter.
		      	// In `@Received`, the `erasedToConcreteExistential` parameter is the third parameter.
		      	$0.label?.text == "erasedToConcreteExistential"
		      })
		else {
			return nil
		}

		return erasedToConcreteExistentialLabeledExpression.expression
	}

	public var onlyIfAvailable: ExprSyntax? {
		guard let arguments,
		      let labeledExpressionList = LabeledExprListSyntax(arguments),
		      let erasedToConcreteExistentialLabeledExpression = labeledExpressionList.reversed().first(where: {
		      	$0.label?.text == "onlyIfAvailable"
		      })
		else {
			return nil
		}

		return erasedToConcreteExistentialLabeledExpression.expression
	}

	public var fulfillingTypeDescription: TypeDescription? {
		if let expression = fulfilledByType,
		   let stringLiteral = StringLiteralExprSyntax(expression),
		   case let .stringSegment(firstSegment) = stringLiteral.segments.first
		{
			TypeSyntax(stringLiteral: firstSegment.content.text).typeDescription
		} else {
			ofType?.typeDescription
		}
	}

	public var erasedToConcreteExistentialValue: Bool {
		guard let erasedToConcreteExistential,
		      let erasedToConcreteExistentialType = BooleanLiteralExprSyntax(erasedToConcreteExistential)
		else {
			// Default value for the `erasedToConcreteExistential` parameter is `false`.
			return false
		}
		return erasedToConcreteExistentialType.literal.text == "true"
	}

	public var onlyIfAvailableValue: Bool {
		guard let onlyIfAvailable,
		      let onlyIfAvailable = BooleanLiteralExprSyntax(onlyIfAvailable)
		else {
			// Default value for the `onlyIfAvailable` parameter is `false`.
			return false
		}
		return onlyIfAvailable.literal.text == "true"
	}
}
