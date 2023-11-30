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
        isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
        doesThrow = node.signature.effectSpecifiers?.throwsSpecifier != nil
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
        isAsync: Bool,
        doesThrow: Bool,
        hasGenericParameter: Bool,
        hasGenericWhereClause: Bool,
        arguments: [Initializer.Argument])
    {
        self.isOptional = isOptional
        self.isAsync = isAsync
        self.doesThrow = doesThrow
        self.hasGenericParameter = hasGenericParameter
        self.hasGenericWhereClause = hasGenericWhereClause
        self.arguments = arguments
    }

    // MARK: Public

    public let isOptional: Bool
    public let isAsync: Bool
    public let doesThrow: Bool
    public let hasGenericParameter: Bool
    public let hasGenericWhereClause: Bool
    public let arguments: [Argument]

    public func generateSafeDIInitializer(fulfilling dependencies: [Dependency], typeIsClass: Bool, trailingNewline: Bool = false) throws -> InitializerDeclSyntax {
        guard !isOptional else {
            throw GenerationError.optionalInitializer
        }
        guard !isAsync else {
            throw GenerationError.asyncInitializer
        }
        guard !doesThrow else {
            throw GenerationError.throwingInitializer
        }
        guard !hasGenericParameter else {
            throw GenerationError.genericParameterInInitializer
        }
        guard !hasGenericWhereClause else {
            throw GenerationError.whereClauseOnInitializer
        }

        let dependencyAndArgumentBinding = try arguments.reduce(into: [(dependency: Dependency, argument: Argument)]()) { partialResult, argument in
            guard let dependency = dependencies.first(where: {
                $0.asInitializerArgument.label == argument.innerLabel
                && $0.asInitializerArgument.typeDescription == argument.typeDescription
            }) else {
                throw GenerationError.unexpectedArgument(argument.asProperty.asSource)
            }
            partialResult.append((dependency: dependency, argument: argument))
        }

        let dependenciesWithDuplicateInitializerArgumentsRemoved = dependencies.removingDuplicateInitializerArguments
        let initializerFulfulledDependencies = Set(dependencyAndArgumentBinding.map(\.dependency))
        let missingArguments = Set(dependenciesWithDuplicateInitializerArgumentsRemoved).subtracting(initializerFulfulledDependencies)
        guard missingArguments.isEmpty else {
            throw GenerationError.missingArguments(missingArguments.map(\.asInitializerArgument.asSource))
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
                for (index, dependencyAndArgument) in dependencyAndArgumentBinding.enumerated() {
                    if dependenciesWithDuplicateInitializerArgumentsRemoved.count > 1 {
                        LabeledExprSyntax(
                            leadingTrivia: index == 0 ? nil : .space,
                            label: .identifier(dependencyAndArgument.argument.label),
                            colon: .colonToken(trailingTrivia: .space),
                            expression:
                                MemberAccessExprSyntax(
                                    base: DeclReferenceExprSyntax(baseName: Self.dependenciesToken),
                                    name: .identifier(dependencyAndArgument.argument.innerLabel)
                                )
                        )
                    } else {
                        LabeledExprSyntax(
                            leadingTrivia: index == 0 ? nil : .space,
                            label: .identifier(dependencyAndArgument.argument.label),
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
                        dependenciesWithDuplicateInitializerArgumentsRemoved.buildDependenciesFunctionParameter
                        for forwardedFunctionParameter in dependencies.forwardedFunctionParameters {
                            forwardedFunctionParameter
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
                        for functionParameter in dependencies.initializerFunctionParameters {
                            functionParameter
                        }
                    })
                ),
                trailingTrivia: .space
            ),
            bodyBuilder: {
                for dependency in dependencies {
                    switch dependency.source {
                    case .instantiated,
                            .inherited,
                            .singleton,
                            .forwarded:
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
                                trailingTrivia: dependency == dependencies.last ? .newline : nil
                            )))
                        )
                    case .lazyInstantiated:
                        CodeBlockItemSyntax(
                            item: .expr(ExprSyntax(InfixOperatorExprSyntax(
                                leadingTrivia: .newline,
                                leftOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier("_\(dependency.property.label)")),
                                operator: AssignmentExprSyntax(
                                    leadingTrivia: .space,
                                    trailingTrivia: .space),
                                rightOperand: FunctionCallExprSyntax(
                                    calledExpression: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier(Dependency.Source.lazyInstantiated.rawValue)),
                                    leftParen: .leftParenToken(),
                                    arguments: LabeledExprListSyntax {
                                        LabeledExprSyntax(
                                            expression: DeclReferenceExprSyntax(
                                                baseName: TokenSyntax.identifier(dependency.asInitializerArgument.label)
                                            )
                                        )
                                    },
                                    rightParen: .rightParenToken()
                                ),
                                trailingTrivia: dependency == dependencies.last ? .newline : nil
                            )))
                        )
                    }
                }
            }
        )
    }
    // MARK: - GenerationError

    public enum GenerationError: Error, Equatable {
        case noDependencies
        case asyncInitializer
        case throwingInitializer
        case optionalInitializer
        case genericParameterInInitializer
        case whereClauseOnInitializer
        /// The initializer is missing arguments for injected properties.
        case missingArguments([String])
        /// The initializer has an argument that does not map to any injected properties.
        case unexpectedArgument(String)
    }

    // MARK: - Argument

    public struct Argument: Codable, Equatable {
        /// The outer label, if one exists, by which the argument is referenced at the call site.
        public let outerLabel: String?
        /// The label by which the argument is referenced.
        public let innerLabel: String
        /// The type to which the property conforms.
        public let typeDescription: TypeDescription
        /// The label by which this argument is referenced at the call site.
        public var label: String {
            outerLabel ?? innerLabel
        }

        public var asProperty: Property {
            Property(
                label: innerLabel,
                typeDescription: typeDescription
            )
        }

        public init(property: Property) {
            outerLabel = nil
            innerLabel = property.label
            typeDescription = property.typeDescription
        }

        init(_ node: FunctionParameterSyntax) {
            if let secondName = node.secondName {
                outerLabel = node.firstName.text
                innerLabel = secondName.text
            } else {
                outerLabel = nil
                innerLabel = node.firstName.text
            }
            typeDescription = node.type.typeDescription
        }

        init(outerLabel: String? = nil, innerLabel: String, typeDescription: TypeDescription) {
            self.outerLabel = outerLabel
            self.innerLabel = innerLabel
            self.typeDescription = typeDescription
        }

        static let dependenciesArgumentName: TokenSyntax = .identifier("buildSafeDIDependencies")
    }

    static let dependenciesToken: TokenSyntax = .identifier("dependencies")
}
