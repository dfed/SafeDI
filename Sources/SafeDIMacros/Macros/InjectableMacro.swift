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

public struct InjectableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
    {
        guard let variableDecl = VariableDeclSyntax(declaration) else {
            throw InjectableError.notDecoratingBinding
        }

        guard variableDecl.modifiers.staticModifier == nil else {
            throw InjectableError.decoratingStatic
        }

        if let fulfilledByType = variableDecl.attributes.instantiatedMacro?.fulfilledByType {
            if
                let stringLiteralExpression = StringLiteralExprSyntax(fulfilledByType),
                stringLiteralExpression.segments.count == 1,
                let stringLiteral = stringLiteralExpression.segments.firstStringSegment
            {
                switch TypeSyntax(stringLiteral: stringLiteral).typeDescription {
                case .simple:
                    break
                case .nested, .composition, .optional, .implicitlyUnwrappedOptional, .some, .any, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .unknown:
                    throw InjectableError.fulfilledByTypeArgumentInvalidTypeDescription
                }
            } else {
                throw InjectableError.fulfilledByTypeArgumentInvalidType
            }
        }

        if let fulfilledByDependencyNamed = variableDecl.attributes.receivedMacro?.fulfilledByDependencyNamed {
            guard
                let stringLiteralExpression = StringLiteralExprSyntax(fulfilledByDependencyNamed),
                stringLiteralExpression.segments.count == 1
            else {
                throw InjectableError.fulfilledByDependencyNamedInvalidType
            }
        }

        if let fulfilledByType = variableDecl.attributes.receivedMacro?.ofType {
            if case .unknown = fulfilledByType.typeDescription {
                throw InjectableError.ofTypeArgumentInvalidType
            }
        }

        if variableDecl.bindingSpecifier.text != TokenSyntax.keyword(.let).text,
           // If there is only one attribute, we know the variable is not decorated with a property wrapper.
            variableDecl.attributes.count == 1
        {
            context.diagnose(Diagnostic(
                node: variableDecl.bindingSpecifier,
                error: FixableInjectableError.unexpectedMutable,
                changes: [
                    .replace(
                        oldNode: Syntax(variableDecl.bindingSpecifier),
                        newNode: Syntax(TokenSyntax.keyword(
                            .let,
                            leadingTrivia: .space,
                            trailingTrivia: .space
                        ))
                    )
                ]
            ))
        }

        // This macro purposefully does not expand.
        // This macro serves as a decorator, nothing more.
        return []
    }

    // MARK: - InjectableError

    private enum InjectableError: Error, CustomStringConvertible {
        case notDecoratingBinding
        case decoratingStatic
        case fulfilledByTypeArgumentInvalidType
        case fulfilledByTypeArgumentInvalidTypeDescription
        case fulfilledByDependencyNamedInvalidType
        case ofTypeArgumentInvalidType

        var description: String {
            switch self {
            case .notDecoratingBinding:
                "This macro must decorate a instance variable"
            case .decoratingStatic:
                "This macro can not decorate `static` variables"
            case .fulfilledByTypeArgumentInvalidType:
                "The argument `fulfilledByType` must be a string literal"
            case .fulfilledByTypeArgumentInvalidTypeDescription:
                "The argument `fulfilledByType` must refer to a simple, unnested type"
            case .fulfilledByDependencyNamedInvalidType:
                "The argument `fulfilledByDependencyNamed` must be a string literal"
            case .ofTypeArgumentInvalidType:
                "The argument `ofType` must be a type literal"
            }
        }
    }
}
