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
import SwiftSyntaxBuilder

public struct Initializer: Codable, Equatable {

    // MARK: Initialization

    init(_ node: InitializerDeclSyntax) {
        isOptional = node.optionalMark != nil
        hasGenericParameter = node.genericParameterClause != nil
        hasGenericWhereClause = node.genericWhereClause != nil
        arguments = node
            .signature
            .parameterClause
            .parameters
            .map(Argument.init)
    }

    public init(
        isOptional: Bool,
        hasGenericParameter: Bool,
        hasGenericWhereClause: Bool,
        arguments: [Initializer.Argument])
    {
        self.isOptional = isOptional
        self.hasGenericParameter = hasGenericParameter
        self.hasGenericWhereClause = hasGenericWhereClause
        self.arguments = arguments
    }

    // MARK: Public

    public let isOptional: Bool
    public let hasGenericParameter: Bool
    public let hasGenericWhereClause: Bool
    public let arguments: [Argument]

    public func generateSafeDIInitializer(fulfilling dependencies: [Dependency], typeIsClass: Bool, trailingNewline: Bool = false) throws -> InitializerDeclSyntax {
        guard !isOptional else {
            throw GenerationError.optionalInitializer
        }
        guard !hasGenericParameter else {
            throw GenerationError.genericParameterInInitializer
        }
        guard !hasGenericWhereClause else {
            throw GenerationError.whereClauseOnInitializer
        }

        let propertyLabels = Set(dependencies.map(\.property.label))
        let argumentLabels = Set(arguments.map(\.innerLabel))
        let extraArguments = argumentLabels.subtracting(propertyLabels)
        guard extraArguments.isEmpty else {
            throw GenerationError.tooManyArguments(labels: extraArguments)
        }
        let missingArguments = propertyLabels.subtracting(argumentLabels)
        guard missingArguments.isEmpty else {
            throw GenerationError.missingArguments(labels: missingArguments)
        }
        guard !dependencies.isEmpty else {
            throw GenerationError.noDependencies
        }

        let modifiers: DeclModifierListSyntax
        let publicModifier = DeclModifierSyntax(
            name: TokenSyntax(
                TokenKind.identifier("public"),
                presence: .present
            ),
            trailingTrivia: .space
        )
        if typeIsClass {
            modifiers = DeclModifierListSyntax(
                arrayLiteral: publicModifier,
                DeclModifierSyntax(
                    name: TokenSyntax(
                        TokenKind.identifier("convenience"),
                        presence: .present
                    ),
                    trailingTrivia: .space
                )
            )
        } else {
            modifiers = DeclModifierListSyntax(arrayLiteral: publicModifier)
        }

        let initFunctionCall = FunctionCallExprSyntax(
            leadingTrivia: .spaces(4),
            calledExpression: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(
                    baseName: TokenSyntax.keyword(.`self`)
                ),
                name: TokenSyntax.keyword(.`init`)),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax {
                for (index, argument) in arguments.enumerated() {
                    if dependencies.count > 1 {
                        LabeledExprSyntax(
                            leadingTrivia: index == 0 ? nil : .space,
                            label: .identifier(argument.label),
                            colon: .colonToken(trailingTrivia: .space),
                            expression:
                                MemberAccessExprSyntax(
                                    base: DeclReferenceExprSyntax(baseName: Self.dependenciesToken),
                                    name: .identifier(argument.innerLabel)
                                )
                        )
                    } else {
                        LabeledExprSyntax(
                            leadingTrivia: index == 0 ? nil : .space,
                            label: .identifier(argument.label),
                            colon: .colonToken(trailingTrivia: .space),
                            expression: DeclReferenceExprSyntax(baseName: Self.dependenciesToken)
                        )
                    }
                }
            },
            rightParen: .rightParenToken()
        )
        return InitializerDeclSyntax(
            modifiers: modifiers,
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: FunctionParameterListSyntax(itemsBuilder: {
                        dependencies.buildDependenciesFunctionParameter
                        for propagatedVariantsFunctionParameter in dependencies.propagatedVariantsFunctionParameters {
                            propagatedVariantsFunctionParameter
                        }
                    })
                ),
                trailingTrivia: .space
            ),
            bodyBuilder: {
                CodeBlockItemSyntax(
                    leadingTrivia: .newline,
                    item: .decl(DeclSyntax(dependencies.dependenciesDeclaration))
                )
                CodeBlockItemSyntax(
                    item: .expr(ExprSyntax(initFunctionCall)),
                    trailingTrivia: trailingNewline ? .newline : nil
                )
            }
        )
    }

    public static func generateRequiredInitializer(for dependencies: [Dependency]) -> InitializerDeclSyntax {
        return InitializerDeclSyntax(
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: FunctionParameterListSyntax(itemsBuilder: {
                        for functionParameter in dependencies.functionParameters {
                            functionParameter
                        }
                    })
                ),
                trailingTrivia: .space
            ),
            bodyBuilder: {
                for dependency in dependencies {
                    CodeBlockItemSyntax(
                        item: .expr(ExprSyntax(InfixOperatorExprSyntax(
                            leadingTrivia: .newline,
                            leftOperand: MemberAccessExprSyntax(
                                base: DeclReferenceExprSyntax(baseName: TokenSyntax.keyword(.`self`)),
                                name: TokenSyntax.identifier(dependency.property.label)),
                            operator: AssignmentExprSyntax(
                                leadingTrivia: .space,
                                trailingTrivia: .space),
                            rightOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier(dependency.property.label)),
                            trailingTrivia: .newline
                        )))
                    )
                }
            }
        )
    }
    // MARK: - GenerationError

    public enum GenerationError: Error, Equatable {
        case noDependencies
        case optionalInitializer
        case genericParameterInInitializer
        case whereClauseOnInitializer
        /// The initializer is missing arguments for injected properties.
        case missingArguments(labels: Set<String>)
        /// The initializer has arguments that don't map to any injected properties.
        case tooManyArguments(labels: Set<String>)
    }

    // MARK: - Argument

    public struct Argument: Codable, Equatable {
        /// The outer label, if one exists, by which the argument is referenced at the call site.
        public let outerLabel: String?
        /// The label by which the argument is referenced.
        public let innerLabel: String
        /// The type to which the property conforms.
        public let type: String
        /// The label by which this argument is referenced at the call site.
        public var label: String {
            outerLabel ?? innerLabel
        }

        public var asProperty: Property {
            Property(
                label: innerLabel,
                type: type
            )
        }

        public init(property: Property) {
            outerLabel = nil
            innerLabel = property.label
            type = property.type
        }

        init(_ node: FunctionParameterSyntax) {
            if let secondName = node.secondName {
                outerLabel = node.firstName.text
                innerLabel = secondName.text
            } else {
                outerLabel = nil
                innerLabel = node.firstName.text
            }
            type = node.type.trimmedDescription
        }

        init(outerLabel: String? = nil, innerLabel: String, type: String) {
            self.outerLabel = outerLabel
            self.innerLabel = innerLabel
            self.type = type
        }

        static let dependenciesArgumentName: TokenSyntax = .identifier("buildSafeDIDependencies")
    }

    static let dependenciesToken: TokenSyntax = .identifier("dependencies")
}
