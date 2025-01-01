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
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    )
        throws -> [DeclSyntax]
    {
        guard let variableDecl = VariableDeclSyntax(declaration) else {
            throw InjectableError.notDecoratingBinding
        }

        guard variableDecl.modifiers.staticModifier == nil else {
            throw InjectableError.decoratingStatic
        }

        let macroWithParameters = variableDecl.attributes.instantiatedMacro ?? variableDecl.attributes.receivedMacro
        if let fulfilledByType = macroWithParameters?.fulfilledByType {
            let decoratesInstantiator = variableDecl
                .bindings
                .compactMap(\.typeAnnotation)
                .contains(where: \.type.typeDescription.propertyType.isInstantiator)
            if decoratesInstantiator {
                throw InjectableError.fulfilledByTypeUseOnInstantiator
            }

            if let stringLiteralExpression = StringLiteralExprSyntax(fulfilledByType),
               stringLiteralExpression.segments.count == 1,
               case let .stringSegment(stringLiteral) = stringLiteralExpression.segments.first
            {
                switch TypeSyntax(stringLiteral: stringLiteral.content.text).typeDescription {
                case .simple, .nested:
                    break
                case .composition, .optional, .implicitlyUnwrappedOptional, .some, .any, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .unknown, .void:
                    throw InjectableError.fulfilledByTypeArgumentInvalidTypeDescription
                }
            } else {
                throw InjectableError.fulfilledByTypeArgumentInvalidType
            }
        } else {
            let decoratesErasedInstantiator = variableDecl
                .bindings
                .compactMap(\.typeAnnotation)
                .contains(where: \.type.typeDescription.propertyType.isErasedInstantiator)
            if decoratesErasedInstantiator {
                throw InjectableError.erasedInstantiatorUsedWithoutFulfilledByType
            }
        }

        if let fulfilledByDependencyNamed = macroWithParameters?.fulfilledByDependencyNamed {
            guard let stringLiteralExpression = StringLiteralExprSyntax(fulfilledByDependencyNamed),
                  stringLiteralExpression.segments.count == 1
            else {
                throw InjectableError.fulfilledByDependencyNamedInvalidType
            }
        }

        if let fulfilledByType = macroWithParameters?.ofType {
            if case .unknown = fulfilledByType.typeDescription {
                throw InjectableError.ofTypeArgumentInvalidType
            }
        }

        if let erasedToConcreteExistential = macroWithParameters?.erasedToConcreteExistential {
            if BooleanLiteralExprSyntax(erasedToConcreteExistential) == nil {
                throw InjectableError.erasedToConcreteExistentialInvalidType
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
                    ),
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
        case fulfilledByTypeUseOnInstantiator
        case ofTypeArgumentInvalidType
        case erasedToConcreteExistentialInvalidType
        case erasedInstantiatorUsedWithoutFulfilledByType

        var description: String {
            switch self {
            case .notDecoratingBinding:
                "This macro must decorate a instance variable"
            case .decoratingStatic:
                "This macro can not decorate `static` variables"
            case .fulfilledByTypeArgumentInvalidType:
                "The argument `fulfilledByType` must be a string literal"
            case .fulfilledByTypeArgumentInvalidTypeDescription:
                "The argument `fulfilledByType` must refer to a simple type"
            case .fulfilledByDependencyNamedInvalidType:
                "The argument `fulfilledByDependencyNamed` must be a string literal"
            case .fulfilledByTypeUseOnInstantiator:
                "The argument `fulfilledByType` can not be used on an `Instantiator` or `SendableInstantiator`. Use an `ErasedInstantiator` or `SendableErasedInstantiator` instead"
            case .ofTypeArgumentInvalidType:
                "The argument `ofType` must be a type literal"
            case .erasedToConcreteExistentialInvalidType:
                "The argument `erasedToConcreteExistential` must be a bool literal"
            case .erasedInstantiatorUsedWithoutFulfilledByType:
                "`ErasedInstantiator` and `SendableErasedInstantiator` require use of the argument `fulfilledByType`"
            }
        }
    }
}
