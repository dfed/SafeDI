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

    public var fulfillingAdditionalTypes: ExprSyntax? {
        guard
            let arguments,
            let labeledExpressionList = LabeledExprListSyntax(arguments),
            let firstLabeledExpression = labeledExpressionList.first,
            firstLabeledExpression.label?.text == "fulfillingAdditionalTypes"
        else {
            return nil
        }

        return firstLabeledExpression.expression
    }

    public var fulfilledByDependencyNamed: ExprSyntax? {
        guard 
            let arguments,
            let labeledExpressionList = LabeledExprListSyntax(arguments),
            let firstLabeledExpression = labeledExpressionList.first,
            firstLabeledExpression.label?.text == "fulfilledByDependencyNamed"
        else {
            return nil
        }

        return firstLabeledExpression.expression
    }

    public var fulfillingPropertyName: String? {
        guard
            let fulfilledByDependencyNamed,
            let stringLiteral = StringLiteralExprSyntax(fulfilledByDependencyNamed)
        else {
            return nil
        }

        return stringLiteral.segments.firstStringSegment
    }

    public var fulfilledByType: ExprSyntax? {
        guard
            let arguments,
            let labeledExpressionList = LabeledExprListSyntax(arguments),
            let firstLabeledExpression = labeledExpressionList.first,
            firstLabeledExpression.label?.text == "fulfilledByType"
        else {
            return nil
        }

        return firstLabeledExpression.expression
    }

    public var ofType: ExprSyntax? {
        guard
            let arguments,
            let labeledExpressionList = LabeledExprListSyntax(arguments),
            let lastLabeledExpression = labeledExpressionList.last,
            lastLabeledExpression.label?.text == "ofType"
        else {
            return nil
        }

        return lastLabeledExpression.expression
    }

    public var fulfillingTypeDescription: TypeDescription? {
        if
            let expression = fulfilledByType,
            let stringLiteral = StringLiteralExprSyntax(expression),
            let firstStringSegement = stringLiteral.segments.firstStringSegment
        {
            return TypeSyntax(stringLiteral: firstStringSegement).typeDescription
        } else {
            return ofType?.typeDescription
        }
    }

}
