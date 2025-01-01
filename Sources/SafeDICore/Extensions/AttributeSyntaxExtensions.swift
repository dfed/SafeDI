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
              let firstLabeledExpression = labeledExpressionList.first,
              firstLabeledExpression.label?.text == "isRoot"
        else {
            return nil
        }

        return firstLabeledExpression.expression
    }

    public var fulfillingAdditionalTypes: ExprSyntax? {
        guard let arguments,
              let labeledExpressionList = LabeledExprListSyntax(arguments),
              let firstLabeledExpression = labeledExpressionList.first(where: {
                  // In `@Instantiatable`, the `fulfillingAdditionalTypes` parameter is the second parameter, though the first parameter has a default.
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
                  // In `@Instantiated`, the `conformsElsewhere` parameter is the second parameter, though the first parameter has a default.
                  $0.label?.text == "conformsElsewhere"
              })
        else {
            return nil
        }

        return firstLabeledExpression.expression
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

    public var fulfillingPropertyName: String? {
        guard let fulfilledByDependencyNamed,
              let stringLiteral = StringLiteralExprSyntax(fulfilledByDependencyNamed),
              case let .stringSegment(firstSegment) = stringLiteral.segments.first
        else {
            return nil
        }

        return firstSegment.content.text
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

    public var erasedToConcreteExistentialType: Bool {
        guard let erasedToConcreteExistential,
              let erasedToConcreteExistentialType = BooleanLiteralExprSyntax(erasedToConcreteExistential)
        else {
            // Default value for the `erasedToConcreteExistential` parameter is `false`.
            return false
        }
        return erasedToConcreteExistentialType.literal.text == "true"
    }
}
