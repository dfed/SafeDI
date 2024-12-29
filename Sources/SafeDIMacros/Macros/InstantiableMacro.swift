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
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InstantiableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if let fulfillingAdditionalTypesArgument = declaration
            .attributes
            .instantiableMacro?
            .fulfillingAdditionalTypes
        {
            if let arrayExpression = ArrayExprSyntax(fulfillingAdditionalTypesArgument) {
                if arrayExpression
                    .elements
                    .contains(where: \.expression.typeDescription.isOptional)
                {
                    throw InstantiableError.fulfillingAdditionalTypesContainsOptional
                }
            } else {
                throw InstantiableError.fulfillingAdditionalTypesArgumentInvalid
            }
        }

        if let concreteDeclaration: ConcreteDeclSyntaxProtocol
            = ActorDeclSyntax(declaration)
            ?? ClassDeclSyntax(declaration)
            ?? StructDeclSyntax(declaration)
        {
            lazy var extendsInstantiable = concreteDeclaration.inheritanceClause?.inheritedTypes.contains(where: \.type.typeDescription.isInstantiable) ?? false
            let mustExtendInstantiable = if let conformsElsewhereArgument = declaration.attributes.instantiableMacro?.conformsElsewhere,
                                            let boolExpression = BooleanLiteralExprSyntax(conformsElsewhereArgument)
            {
                boolExpression.literal.tokenKind == .keyword(.false)
            } else {
                true
            }

            if mustExtendInstantiable, !extendsInstantiable {
                var modifiedDeclaration = concreteDeclaration
                var inheritedType = InheritedTypeSyntax(
                    type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
                )
                if let existingInheritanceClause = modifiedDeclaration.inheritanceClause {
                    inheritedType.trailingTrivia = .space
                    modifiedDeclaration.inheritanceClause?.inheritedTypes = existingInheritanceClause.inheritedTypes.map { inhertiedType in
                        var modifiedInhertiedType = inhertiedType
                        if modifiedInhertiedType.trailingComma == nil {
                            modifiedInhertiedType.trailingComma = .commaToken(trailingTrivia: .space)
                            modifiedInhertiedType.type.trailingTrivia = []
                        }
                        return modifiedInhertiedType
                    } + [inheritedType]
                } else {
                    modifiedDeclaration.name.trailingTrivia = []
                    modifiedDeclaration.inheritanceClause = InheritanceClauseSyntax(
                        colon: .colonToken(trailingTrivia: .space),
                        inheritedTypes: InheritedTypeListSyntax(arrayLiteral: InheritedTypeSyntax(
                            type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
                        )),
                        trailingTrivia: .space
                    )
                }
                context.diagnose(Diagnostic(
                    node: node,
                    error: FixableInstantiableError.missingInstantiableConformance,
                    changes: [
                        .replace(
                            oldNode: Syntax(concreteDeclaration),
                            newNode: Syntax(modifiedDeclaration)
                        ),
                    ]
                ))
            }

            let visitor = InstantiableVisitor(declarationType: .concreteDecl)
            visitor.walk(concreteDeclaration)
            for diagnostic in visitor.diagnostics {
                context.diagnose(diagnostic)
            }

            if visitor.isRoot, let instantiableType = visitor.instantiableType {
                let inheritedDependencies = visitor.dependencies.filter {
                    switch $0.source {
                    case let .aliased(fulfillingProperty, _):
                        // Aliased properties must not be inherited from elsewhere.
                        !visitor.dependencies.contains { $0.property == fulfillingProperty }
                    case .instantiated:
                        false
                    case .forwarded, .received:
                        true
                    }
                }
                guard inheritedDependencies.isEmpty else {
                    throw InstantiableError.cannotBeRoot(
                        instantiableType,
                        violatingDependencies: inheritedDependencies
                    )
                }
            }

            let forwardedProperties = visitor
                .dependencies
                .filter { $0.source == .forwarded }
                .map(\.property)
            let hasMemberwiseInitializerForInjectableProperties = visitor
                .initializers
                .contains(where: { $0.isValid(forFulfilling: visitor.dependencies) })
            guard hasMemberwiseInitializerForInjectableProperties else {
                if visitor.uninitializedNonOptionalPropertyNames.isEmpty {
                    var declarationWithInitializer = declaration
                    declarationWithInitializer.memberBlock.members.insert(
                        MemberBlockItemSyntax(
                            leadingTrivia: .newline,
                            decl: Initializer.generateRequiredInitializer(
                                for: visitor.dependencies,
                                declarationType: concreteDeclaration.declType
                            ),
                            trailingTrivia: .newline
                        ),
                        at: declarationWithInitializer.memberBlock.members.startIndex
                    )
                    context.diagnose(Diagnostic(
                        node: Syntax(declaration.memberBlock),
                        error: FixableInstantiableError.missingRequiredInitializer(.hasOnlyInjectableProperties),
                        changes: [
                            .replace(
                                oldNode: Syntax(declaration),
                                newNode: Syntax(declarationWithInitializer)
                            ),
                        ]
                    ))
                    return []
                } else {
                    var declarationWithInitializer = declaration
                    declarationWithInitializer.memberBlock.members.insert(
                        MemberBlockItemSyntax(
                            leadingTrivia: .newline,
                            decl: Initializer.generateRequiredInitializer(
                                for: visitor.dependencies,
                                declarationType: concreteDeclaration.declType,
                                andAdditionalPropertiesWithLabels: visitor.uninitializedNonOptionalPropertyNames
                            ),
                            trailingTrivia: .newline
                        ),
                        at: declarationWithInitializer.memberBlock.members.startIndex
                    )
                    // TODO: Create separate fixit if just `public` or `open` are missing.
                    context.diagnose(Diagnostic(
                        node: Syntax(declaration.memberBlock),
                        error: FixableInstantiableError.missingRequiredInitializer(
                            visitor.dependencies.isEmpty ? .hasNoInjectableProperties : .hasInjectableAndNotInjectableProperties
                        ),
                        changes: [
                            .replace(
                                oldNode: Syntax(declaration),
                                newNode: Syntax(declarationWithInitializer)
                            ),
                        ]
                    ))
                    return []
                }
            }
            return generateForwardedProperties(from: forwardedProperties)

        } else if let extensionDeclaration = ExtensionDeclSyntax(declaration) {
            lazy var extendsInstantiable = extensionDeclaration.inheritanceClause?.inheritedTypes.contains(where: \.type.typeDescription.isInstantiable) ?? false
            let mustExtendInstantiable = if let conformsElsewhereArgument = declaration.attributes.instantiableMacro?.conformsElsewhere,
                                            let boolExpression = BooleanLiteralExprSyntax(conformsElsewhereArgument)
            {
                boolExpression.literal.tokenKind == .keyword(.false)
            } else {
                true
            }

            if mustExtendInstantiable, !extendsInstantiable {
                var modifiedDeclaration = extensionDeclaration
                var inheritedType = InheritedTypeSyntax(
                    type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
                )
                if let existingInheritanceClause = modifiedDeclaration.inheritanceClause {
                    inheritedType.trailingTrivia = .space
                    modifiedDeclaration.inheritanceClause?.inheritedTypes = existingInheritanceClause.inheritedTypes.map { inhertiedType in
                        var modifiedInhertiedType = inhertiedType
                        if modifiedInhertiedType.trailingComma == nil {
                            modifiedInhertiedType.trailingComma = .commaToken(trailingTrivia: .space)
                            modifiedInhertiedType.type.trailingTrivia = []
                        }
                        return modifiedInhertiedType
                    } + [inheritedType]
                } else {
                    modifiedDeclaration.extendedType.trailingTrivia = []
                    modifiedDeclaration.inheritanceClause = InheritanceClauseSyntax(
                        colon: .colonToken(trailingTrivia: .space),
                        inheritedTypes: InheritedTypeListSyntax(arrayLiteral: InheritedTypeSyntax(
                            type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
                        )),
                        trailingTrivia: .space
                    )
                }
                context.diagnose(Diagnostic(
                    node: node,
                    error: FixableInstantiableError.missingInstantiableConformance,
                    changes: [
                        .replace(
                            oldNode: Syntax(extensionDeclaration),
                            newNode: Syntax(modifiedDeclaration)
                        ),
                    ]
                ))
            }
            if extensionDeclaration.genericWhereClause != nil {
                var modifiedDeclaration = extensionDeclaration
                modifiedDeclaration.genericWhereClause = nil
                context.diagnose(Diagnostic(
                    node: node,
                    error: FixableInstantiableError.disallowedGenericWhereClause,
                    changes: [
                        .replace(
                            oldNode: Syntax(extensionDeclaration),
                            newNode: Syntax(modifiedDeclaration)
                        ),
                    ]
                ))
            }

            let visitor = InstantiableVisitor(declarationType: .extensionDecl)
            visitor.walk(extensionDeclaration)
            for diagnostic in visitor.diagnostics {
                context.diagnose(diagnostic)
            }

            if visitor.isRoot, let instantiableType = visitor.instantiableType {
                guard visitor.instantiables.flatMap(\.dependencies).isEmpty else {
                    throw InstantiableError.cannotBeRoot(
                        instantiableType,
                        violatingDependencies: visitor.instantiables.flatMap(\.dependencies)
                    )
                }
            }

            let instantiables = visitor.instantiables
            if instantiables.count > 1 {
                var concreteInstantiables = Set<TypeDescription>()
                for concreteInstantiable in instantiables.map(\.concreteInstantiable) {
                    if concreteInstantiables.contains(concreteInstantiable) {
                        throw InstantiableError.tooManyInstantiateMethods(concreteInstantiable)
                    } else {
                        concreteInstantiables.insert(concreteInstantiable)
                    }
                }
            } else if instantiables.isEmpty {
                let extendedTypeName = extensionDeclaration.extendedType.typeDescription.asSource
                var membersWithInitializer = declaration.memberBlock.members
                membersWithInitializer.insert(
                    MemberBlockItemSyntax(
                        leadingTrivia: .newline,
                        decl: FunctionDeclSyntax(
                            modifiers: DeclModifierListSyntax(
                                arrayLiteral: DeclModifierSyntax(
                                    name: TokenSyntax(
                                        TokenKind.keyword(.public),
                                        presence: .present
                                    ),
                                    trailingTrivia: .space
                                ),
                                DeclModifierSyntax(
                                    name: TokenSyntax(
                                        TokenKind.keyword(.static),
                                        presence: .present
                                    ),
                                    trailingTrivia: .space
                                )
                            ),
                            name: TokenSyntax(
                                TokenKind.identifier(InstantiableVisitor.instantiateMethodName),
                                leadingTrivia: .space,
                                presence: .present
                            ),
                            signature: FunctionSignatureSyntax(
                                parameterClause: FunctionParameterClauseSyntax(
                                    parameters: FunctionParameterListSyntax([])
                                ),
                                returnClause: ReturnClauseSyntax(
                                    arrow: .arrowToken(
                                        leadingTrivia: .space,
                                        trailingTrivia: .space
                                    ),
                                    type: IdentifierTypeSyntax(
                                        name: .identifier(extendedTypeName)
                                    )
                                )
                            ),
                            body: CodeBlockSyntax(
                                leadingTrivia: .newline,
                                statements: CodeBlockItemListSyntax([]),
                                trailingTrivia: .newline
                            )
                        ),
                        trailingTrivia: .newline
                    ),
                    at: membersWithInitializer.startIndex
                )
                context.diagnose(Diagnostic(
                    node: Syntax(extensionDeclaration.memberBlock.members),
                    error: FixableInstantiableError.missingRequiredInstantiateMethod(
                        typeName: extendedTypeName
                    ),
                    changes: [
                        .replace(
                            oldNode: Syntax(declaration.memberBlock.members),
                            newNode: Syntax(membersWithInitializer)
                        ),
                    ]
                ))
            }
            return []
        } else {
            throw InstantiableError.decoratingIncompatibleType
        }
    }

    private static func generateForwardedProperties(
        from forwardedProperties: [Property]
    ) -> [DeclSyntax] {
        if forwardedProperties.isEmpty {
            []
        } else if forwardedProperties.count == 1, let forwardedProperty = forwardedProperties.first {
            [
                DeclSyntax(
                    TypeAliasDeclSyntax(
                        modifiers: DeclModifierListSyntax(
                            arrayLiteral: DeclModifierSyntax(
                                name: TokenSyntax(
                                    TokenKind.identifier("public"),
                                    presence: .present
                                ),
                                trailingTrivia: .space
                            )
                        ),
                        name: .identifier("ForwardedProperties"),
                        initializer: TypeInitializerClauseSyntax(
                            value: IdentifierTypeSyntax(
                                name: .identifier(forwardedProperty.typeDescription.asSource)
                            )
                        )
                    )
                ),
            ]
        } else {
            [
                DeclSyntax(
                    TypeAliasDeclSyntax(
                        modifiers: DeclModifierListSyntax(
                            arrayLiteral: DeclModifierSyntax(
                                name: TokenSyntax(
                                    TokenKind.identifier("public"),
                                    presence: .present
                                ),
                                trailingTrivia: .space
                            )
                        ),
                        name: .identifier("ForwardedProperties"),
                        initializer: TypeInitializerClauseSyntax(value: forwardedProperties.asTuple)
                    )
                ),
            ]
        }
    }

    // MARK: - InstantiableError

    private enum InstantiableError: Error, CustomStringConvertible {
        case decoratingIncompatibleType
        case fulfillingAdditionalTypesContainsOptional
        case fulfillingAdditionalTypesArgumentInvalid
        case tooManyInstantiateMethods(TypeDescription)
        case cannotBeRoot(TypeDescription, violatingDependencies: [Dependency])

        var description: String {
            switch self {
            case .decoratingIncompatibleType:
                "@\(InstantiableVisitor.macroName) must decorate an extension on a type or a class, struct, or actor declaration"
            case .fulfillingAdditionalTypesContainsOptional:
                "The argument `fulfillingAdditionalTypes` must not include optionals"
            case .fulfillingAdditionalTypesArgumentInvalid:
                "The argument `fulfillingAdditionalTypes` must be an inlined array"
            case let .tooManyInstantiateMethods(type):
                "@\(InstantiableVisitor.macroName)-decorated extension must have a single `\(InstantiableVisitor.instantiateMethodName)(…)` method that returns `\(type.asSource)`"
            case let .cannotBeRoot(declaredRootType, violatingDependencies):
                """
                Types decorated with `@\(InstantiableVisitor.macroName)(isRoot: true)` must only have dependencies that are all `@\(Dependency.Source.instantiatedRawValue)` or `@\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@\(Dependency.Source.instantiatedRawValue)` or `@\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

                The following dependencies were found on \(declaredRootType.asSource) that violated this contract:
                \(violatingDependencies.map(\.property.asSource).joined(separator: "\n"))
                """
            }
        }
    }
}

// MARK: - TypeDescription

extension TypeDescription {
    fileprivate var isInstantiable: Bool {
        self == .simple(name: "Instantiable")
            || self == .nested(
                name: "Instantiable",
                parentType: .simple(name: "SafeDI")
            )
            || self == .attributed(
                .simple(name: "Instantiable"),
                specifiers: nil,
                attributes: ["retroactive"]
            )
            || self == .nested(
                name: "Instantiable",
                parentType: .attributed(
                    .simple(name: "SafeDI"),
                    specifiers: nil,
                    attributes: ["retroactive"]
                )
            )
    }
}
