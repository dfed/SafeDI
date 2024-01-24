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

public struct Initializer: Codable, Hashable {

    // MARK: Initialization

    init(_ node: InitializerDeclSyntax) {
        isPublicOrOpen = node.modifiers.containsPublicOrOpen
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

    init(_ node: FunctionDeclSyntax) {
        isPublicOrOpen = node.modifiers.containsPublicOrOpen
        isOptional = false
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

    init(
        isPublicOrOpen: Bool = true,
        isOptional: Bool = false,
        isAsync: Bool = false,
        doesThrow: Bool = false,
        hasGenericParameter: Bool = false,
        hasGenericWhereClause: Bool = false,
        arguments: [Initializer.Argument])
    {
        self.isPublicOrOpen = isPublicOrOpen
        self.isOptional = isOptional
        self.isAsync = isAsync
        self.doesThrow = doesThrow
        self.hasGenericParameter = hasGenericParameter
        self.hasGenericWhereClause = hasGenericWhereClause
        self.arguments = arguments
    }

    // MARK: Public

    public let isPublicOrOpen: Bool
    public let isOptional: Bool
    public let isAsync: Bool
    public let doesThrow: Bool
    public let hasGenericParameter: Bool
    public let hasGenericWhereClause: Bool
    public let arguments: [Argument]

    public func isValid(forFulfilling dependencies: [Dependency]) -> Bool {
        do {
            try validate(fulfilling: dependencies)
            return true
        } catch {
            return false
        }
    }

    public func validate(fulfilling dependencies: [Dependency]) throws {
        guard isPublicOrOpen else {
            throw GenerationError.inaccessibleInitializer
        }
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

        let dependencyAndArgumentBinding = try createDependencyAndArgumentBinding(given: dependencies)

        let initializerFulfulledDependencies = Set(dependencyAndArgumentBinding.map(\.dependency))
        let missingArguments = Set(dependencies).subtracting(initializerFulfulledDependencies)

        guard missingArguments.isEmpty else {
            throw GenerationError.missingArguments(missingArguments.map(\.property.asSource))
        }

        // We're good!
    }

    public static func generateRequiredInitializer(
        for dependencies: [Dependency],
        declarationType: ConcreteDeclType,
        andAdditionalPropertiesWithLabels additionalPropertyLabels: [String] = []
    ) -> InitializerDeclSyntax {
        InitializerDeclSyntax(
            modifiers: declarationType.initializerModifiers,
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
                    CodeBlockItemSyntax(
                        item: .expr(ExprSyntax(InfixOperatorExprSyntax(
                            leadingTrivia: .newline,
                            leftOperand: MemberAccessExprSyntax(
                                base: DeclReferenceExprSyntax(baseName: TokenSyntax.keyword(.`self`)),
                                name: TokenSyntax.identifier(dependency.property.label)),
                            operator: AssignmentExprSyntax(
                                leadingTrivia: .space,
                                trailingTrivia: .space),
                            rightOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier(dependency.property.label))
                        )))
                    )
                }
                for additionalPropertyLabel in additionalPropertyLabels {
                    CodeBlockItemSyntax(
                        item: .expr(ExprSyntax(InfixOperatorExprSyntax(
                            leadingTrivia: .newline,
                            leftOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier(additionalPropertyLabel)),
                            operator: AssignmentExprSyntax(
                                leadingTrivia: .space,
                                trailingTrivia: .space),
                            rightOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier("<#T##assign_\(additionalPropertyLabel)#>")),
                            trailingTrivia: additionalPropertyLabel == additionalPropertyLabels.last ? .newline : nil
                        )))
                    )
                }
            }
        )
    }

    // MARK: - Internal

    func createDependencyAndArgumentBinding(given dependencies: [Dependency]) throws -> [(dependency: Dependency, argument: Argument)] {
        try arguments.reduce(into: [(dependency: Dependency, argument: Argument)]()) { partialResult, argument in
            guard let dependency = dependencies.first(where: {
                $0.property.label == argument.innerLabel
                && $0.property.typeDescription.isEqualToFunctionArgument(argument.typeDescription)
            }) else {
                throw GenerationError.unexpectedArgument(argument.asProperty.asSource)
            }
            partialResult.append((dependency: dependency, argument: argument))
        }
    }

    func createInitializerArgumentList(given dependencies: [Dependency]) throws -> String {
        try createDependencyAndArgumentBinding(given: dependencies)
            .map { "\($0.argument.label): \($0.argument.innerLabel)" }
            .joined(separator: ", ")
    }

    // MARK: - GenerationError

    public enum GenerationError: Error, Equatable {
        case inaccessibleInitializer
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

    public struct Argument: Codable, Hashable {
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

// MARK: - ConcreteDeclType

extension ConcreteDeclType {
    fileprivate var initializerModifiers: DeclModifierListSyntax {
        switch self {
        case .actorType:
            DeclModifierListSyntax(
                arrayLiteral: DeclModifierSyntax(
                    name: TokenSyntax(
                        TokenKind.identifier("public"),
                        presence: .present
                    ),
                    trailingTrivia: .space
                )
            )
        case .classType, .structType:
            DeclModifierListSyntax(
                arrayLiteral: DeclModifierSyntax(
                    name: TokenSyntax(
                        TokenKind.identifier("nonisolated"),
                        presence: .present
                    ),
                    trailingTrivia: .space
                ),
                DeclModifierSyntax(
                    name: TokenSyntax(
                        TokenKind.identifier("public"),
                        presence: .present
                    ),
                    trailingTrivia: .space
                )
            )
        }
    }
}

// MARK: - TypeDescription

extension TypeDescription {
    fileprivate func isEqualToFunctionArgument(_ argument: TypeDescription) -> Bool {
        switch argument {
        case let .attributed(argumentTypeDescription, argumentSpecifier, argumentAttributes):
            switch self {
            case .simple,
                    .nested,
                    .composition,
                    .optional,
                    .implicitlyUnwrappedOptional,
                    .some,
                    .any,
                    .metatype,
                    .array,
                    .dictionary,
                    .tuple,
                    .closure,
                    .unknown:
                return self == argumentTypeDescription
                && argumentSpecifier == nil
                && (argumentAttributes ?? []).contains("escaping")
            case let .attributed(parameterTypeDescription, parameterSpecifier, parameterAttributes):
                return parameterTypeDescription == argumentTypeDescription
                && parameterSpecifier == argumentSpecifier
                && Set(argumentAttributes ?? []).subtracting(parameterAttributes ?? []) == ["escaping"]
            }
        case .simple,
                .nested,
                .composition,
                .optional,
                .implicitlyUnwrappedOptional,
                .some,
                .any,
                .metatype,
                .closure,
                .array,
                .dictionary,
                .tuple,
                .unknown:
            return self == argument
        }
    }
}
