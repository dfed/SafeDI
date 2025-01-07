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

@preconcurrency import SwiftSyntax
import SwiftSyntaxBuilder

public struct Initializer: Codable, Hashable, Sendable {
    // MARK: Initialization

    init(_ node: InitializerDeclSyntax) {
        isPublicOrOpen = node.modifiers.containsPublicOrOpen
        isOptional = node.optionalMark != nil
        isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
        doesThrow = node.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
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
        doesThrow = node.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
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
        arguments: [Initializer.Argument]
    ) {
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

    public func mapArguments(_ transform: (Argument) -> Argument) -> Self? {
        .init(
            isPublicOrOpen: isPublicOrOpen,
            isOptional: isOptional,
            isAsync: isAsync,
            doesThrow: doesThrow,
            hasGenericParameter: hasGenericParameter,
            hasGenericWhereClause: hasGenericWhereClause,
            arguments: arguments.map(transform)
        )
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
                        for functionParameter in dependencies.initializerFunctionParameters.enumerated().map({ index, parameter in
                            var parameter = parameter
                            if dependencies.initializerFunctionParameters.endIndex > 1 {
                                if index == 0 {
                                    parameter.leadingTrivia = .newline
                                }
                                parameter.trailingTrivia = .newline
                            }
                            return parameter
                        }) {
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
                                name: TokenSyntax.identifier(dependency.property.label)
                            ),
                            operator: AssignmentExprSyntax(
                                leadingTrivia: .space,
                                trailingTrivia: .space
                            ),
                            rightOperand: DeclReferenceExprSyntax(
                                baseName: TokenSyntax.identifier(dependency.property.label),
                                trailingTrivia: dependency == dependencies.last ? .newline : nil
                            )
                        )))
                    )
                }
                for (index, additionalPropertyLabel) in additionalPropertyLabels.enumerated() {
                    CodeBlockItemSyntax(
                        item: .expr(ExprSyntax(InfixOperatorExprSyntax(
                            leadingTrivia: Trivia(
                                pieces: [TriviaPiece.newlines(1)]
                                    + (index == 0 ? [
                                        .lineComment("// The following properties are not decorated with the @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue) macros, do not have default values, and are not computed properties."),
                                        TriviaPiece.newlines(1)
                                    ] : [])
                            ),
                            leftOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier(additionalPropertyLabel)),
                            operator: AssignmentExprSyntax(
                                leadingTrivia: .space,
                                trailingTrivia: .space
                            ),
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
                guard argument.hasDefaultValue else {
                    throw GenerationError.unexpectedArgument(argument.asProperty.asSource)
                }
                // We do not care about this argument because it has a default value.
                return
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

    public struct Argument: Codable, Hashable, Sendable {
        /// The outer label, if one exists, by which the argument is referenced at the call site.
        public let outerLabel: String?
        /// The label by which the argument is referenced.
        public let innerLabel: String
        /// The type to which the property conforms.
        public let typeDescription: TypeDescription
        /// Whether the argument has a default value.
        public let hasDefaultValue: Bool
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
            hasDefaultValue = node.defaultValue != nil
        }

        init(outerLabel: String? = nil, innerLabel: String, typeDescription: TypeDescription, hasDefaultValue: Bool) {
            self.outerLabel = outerLabel
            self.innerLabel = innerLabel
            self.typeDescription = typeDescription
            self.hasDefaultValue = hasDefaultValue
        }

        public func withUpdatedTypeDescription(_ typeDescription: TypeDescription) -> Self {
            .init(
                outerLabel: outerLabel,
                innerLabel: innerLabel,
                typeDescription: typeDescription,
                hasDefaultValue: hasDefaultValue
            )
        }

        static let dependenciesArgumentName: TokenSyntax = .identifier("buildSafeDIDependencies")
    }

    static let dependenciesToken: TokenSyntax = .identifier("dependencies")
}

// MARK: - ConcreteDeclType

extension ConcreteDeclType {
    fileprivate var initializerModifiers: DeclModifierListSyntax {
        DeclModifierListSyntax(
            arrayLiteral: DeclModifierSyntax(
                name: TokenSyntax(
                    TokenKind.identifier("public"),
                    presence: .present
                ),
                trailingTrivia: .space
            )
        )
    }
}

// MARK: - TypeDescription

extension TypeDescription {
    fileprivate func isEqualToFunctionArgument(_ argument: TypeDescription) -> Bool {
        switch argument {
        case let .attributed(argumentTypeDescription, argumentSpecifiers, argumentAttributes):
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
                 .unknown,
                 .void:
                self == argumentTypeDescription
                    && argumentSpecifiers?.isEmpty ?? true
                    && (argumentAttributes ?? []).contains("escaping")
            case let .attributed(parameterTypeDescription, parameterSpecifiers, parameterAttributes):
                parameterTypeDescription == argumentTypeDescription
                    && Set(parameterSpecifiers ?? []) == Set(argumentSpecifiers ?? [])
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
             .unknown,
             .void:
            self == argument
        }
    }
}
