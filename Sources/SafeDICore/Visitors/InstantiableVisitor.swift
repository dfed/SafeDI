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

import SwiftDiagnostics
import SwiftSyntax

public final class InstantiableVisitor: SyntaxVisitor {

    // MARK: Initialization

    public init(declarationType: DeclarationType) {
        self.declarationType = declarationType
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard
            declarationType.isTypeDefinition
                && node.modifiers.staticModifier == nil
        else {
            return .skipChildren
        }
        // Check attributes and extract dependency source.
        let dependencySources = node.attributes.dependencySources
        guard dependencySources.isEmpty || dependencySources.count == 1 else {
            diagnostics.append(Diagnostic(
                node: node.attributes,
                error: FixableInstantiableError.dependencyHasTooManyAttributes,
                changes: [
                    .replace(
                        oldNode: Syntax(node.attributes),
                        newNode: Syntax(dependencySources[0].node)
                    )
                ]
            ))
            return .skipChildren
        }
        guard let dependencySource = dependencySources.first?.source else {
            // This dependency is not part of the DI system.
            // If this variable declaration is missing a binding and is non-optional, we need a custom initializer.
            let patterns = node
                .bindings
                .filter {
                    $0.accessorBlock == nil
                    && !$0.isOptionalOrInitialized
                }
                .map(\.pattern)
            uninitializedNonOptionalPropertyNames += patterns
                .compactMap(IdentifierPatternSyntax.init)
                .map(\.identifier.text)
            + patterns
                .compactMap(TuplePatternSyntax.init)
                .map(\.trimmedDescription)
            return .skipChildren
        }

        // Check the bindings.
        for binding in node.bindings {
            // Check that each variable has no initializer.
            if binding.initializer != nil {
                var bindingWithoutInitializer = binding
                bindingWithoutInitializer.initializer = nil
                diagnostics.append(Diagnostic(
                    node: node,
                    error: FixableInstantiableError.dependencyHasInitializer,
                    changes: [
                        .replace(
                            oldNode: Syntax(binding),
                            newNode: Syntax(bindingWithoutInitializer)
                        )
                    ]
                ))
            }

            if
                let label = IdentifierPatternSyntax(binding.pattern)?.identifier.text,
                let typeDescription = binding.typeAnnotation?.type.typeDescription
            {
                let fulfillingPropertyName = node.attributes.receivedMacro?.fulfillingPropertyName
                let fulfillingTypeDescription: TypeDescription? = node
                    .attributes
                    .instantiatedMacro?
                    .fulfillingTypeDescription
                ?? node
                    .attributes
                    .receivedMacro?
                    .fulfillingTypeDescription

                dependencies.append(
                    Dependency(
                        property: { 
                            switch dependencySource {
                            case .instantiated,
                                    .received,
                                    .forwarded:
                                Property(
                                    label: label,
                                    typeDescription: typeDescription
                                )
                            }
                        }(),
                        source: dependencySource,
                        fulfillingPropertyName: fulfillingPropertyName,
                        fulfillingTypeDescription: fulfillingTypeDescription
                    )
                )
            }
        }

        return .skipChildren
    }

    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard declarationType.isTypeDefinition else {
            return .skipChildren
        }
        initializers.append(Initializer(node))
        return .skipChildren
    }


    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard declarationType.isExtension else {
            return .skipChildren
        }
        guard let instantiableMacro = node.attributes.instantiableMacro else {
            // Not an external instantiable type. We do not care.
            return .skipChildren
        }

        instantiableType = node.extendedType.typeDescription
        processAttributes(node.attributes, on: instantiableMacro)

        return .visitChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard declarationType.isExtension else {
            return .skipChildren
        }
        guard let instantiableType else {
            // We're being called on code that will not compile.
            // We are visiting a function but we haven't visited the extension yet.
            // Just move on.
            return .skipChildren
        }
        guard node.name.text == Self.instantiateMethodName else {
            // We don't care about this method.
            return .skipChildren
        }

        if
            let returnClause = node.signature.returnClause,
            returnClause.type.typeDescription != instantiableType {
            var modifiedSignature = node.signature
            modifiedSignature.returnClause = ReturnClauseSyntax(
                arrow: .arrowToken(
                    leadingTrivia: returnClause.arrow.leadingTrivia,
                    trailingTrivia: returnClause.arrow.trailingTrivia
                ),
                type: IdentifierTypeSyntax(
                    leadingTrivia: node.signature.leadingTrivia,
                    name: .identifier(instantiableType.asSource),
                    trailingTrivia: node.signature.trailingTrivia
                )
            )
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.incorrectReturnType,
                changes: [
                    .replace(
                        oldNode: Syntax(node.signature),
                        newNode: Syntax(modifiedSignature)
                    )
                ]
            ))
        }

        let initializer = Initializer(node)
        initializers.append(initializer)
        // We should only have a single `instantiate` method, so we set rather than append to dependencies.
        dependencies = initializer.arguments.map {
            Dependency(
                property: $0.asProperty,
                source: .received,
                // We do not support type injecting renamed properties into external instantiable's initializer method.
                // We can add this functionality in the future, possibly with a freestanding macro used to declare an argument within the method declaration.
                fulfillingPropertyName: nil,
                // We do not support type injecting type-erased properties into external instantiable's initializer method.
                // We can add this functionality in the future, possibly with a freestanding macro used to declare an argument within the method declaration.
                fulfillingTypeDescription: nil
            )
        }

        if !initializer.isPublicOrOpen || node.modifiers.staticModifier == nil {
            var modifiedNode = node
            modifiedNode.modifiers = DeclModifierListSyntax(
                arrayLiteral:
                    DeclModifierSyntax(
                        name: TokenSyntax(
                            TokenKind.keyword(.public),
                            leadingTrivia: .newline,
                            presence: .present
                        )
                    ),
                DeclModifierSyntax(
                    name: TokenSyntax(
                        TokenKind.keyword(.static),
                        leadingTrivia: .space,
                        trailingTrivia: .space,
                        presence: .present
                    )
                )
            )
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.missingAttributes,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(modifiedNode)
                    )
                ]
            ))
        }
        if initializer.isAsync || initializer.doesThrow {
            var modifiedSignature = node.signature
            modifiedSignature.effectSpecifiers = nil
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.disallowedEffectSpecifiers,
                changes: [
                    .replace(
                        oldNode: Syntax(node.signature),
                        newNode: Syntax(modifiedSignature)
                    )
                ]
            ))
        }
        if initializer.hasGenericParameter {
            var modifiedNode = node
            modifiedNode.genericParameterClause = nil
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.disallowedGenericParameter,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(modifiedNode)
                    )
                ]
            ))
        }
        if initializer.hasGenericWhereClause {
            var modifiedNode = node
            modifiedNode.genericWhereClause = nil
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.disallowedGenericWhereClause,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(modifiedNode)
                    )
                ]
            ))
        }

        return .skipChildren
    }

    // MARK: Public

    public private(set) var dependencies = [Dependency]()
    public private(set) var initializers = [Initializer]()
    public private(set) var instantiableType: TypeDescription?
    public private(set) var additionalInstantiableTypes: [TypeDescription]?
    public private(set) var diagnostics = [Diagnostic]()
    public private(set) var uninitializedNonOptionalPropertyNames = [String]()

    public static let macroName = "Instantiable"
    public static let instantiateMethodName = "instantiate"

    // MARK: DeclarationType

    public enum DeclarationType {
        /// A concrete type declaration.
        case concreteDecl
        /// An extension declaration.
        case extensionDecl

        var isTypeDefinition: Bool {
            switch self {
            case .concreteDecl:
                true
            case .extensionDecl:
                false
            }
        }

        var isExtension: Bool {
            switch self {
            case .concreteDecl:
                false
            case .extensionDecl:
                true
            }
        }
    }

    // MARK: Internal

    var instantiable: Instantiable? {
        guard let instantiableType else { return nil }
        switch declarationType {
        case .concreteDecl:
            guard let topLevelDeclarationType else { return nil }
            return Instantiable(
                instantiableType: instantiableType,
                initializer: initializers.first(where: { $0.isValid(forFulfilling: dependencies) }) ?? initializerToGenerate(),
                additionalInstantiableTypes: additionalInstantiableTypes,
                dependencies: dependencies,
                declarationType: topLevelDeclarationType.asDeclarationType
            )
        case .extensionDecl:
            return Instantiable(
                instantiableType: instantiableType,
                // If we have more than one initializer this isn't a valid extension.
                initializer: initializers.count > 1 ? nil : initializers.first,
                additionalInstantiableTypes: additionalInstantiableTypes,
                dependencies: dependencies,
                declarationType: .extensionType
            )
        }
    }

    // MARK: Private

    private var isInTopLevelDeclaration = false
    private var topLevelDeclarationType: ConcreteDeclType?

    private let declarationType: DeclarationType

    private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
        guard declarationType.isTypeDefinition else {
            return .skipChildren
        }
        guard let macro = node.attributes.instantiableMacro else {
            // Not an instantiable type. We do not care.
            return .skipChildren
        }
        guard !isInTopLevelDeclaration else {
            return .skipChildren
        }
        isInTopLevelDeclaration = true
        topLevelDeclarationType = node.declType

        instantiableType = .simple(
            name: node.name.text,
            generics: []
        )
        processAttributes(node.attributes, on: macro)
        processModifiers(node.modifiers, on: node)

        return .visitChildren
    }

    private func processAttributes(_ attributes: AttributeListSyntax, on macro: AttributeSyntax) {
        guard
            let fulfillingAdditionalTypesExpression = macro.fulfillingAdditionalTypes,
            let fulfillingAdditionalTypesArray = ArrayExprSyntax(fulfillingAdditionalTypesExpression)
        else {
            // Nothing to do here.
            return
        }

        additionalInstantiableTypes = fulfillingAdditionalTypesArray
            .elements
            .map { $0.expression.typeDescription }
    }

    private func processModifiers(_ modifiers: DeclModifierListSyntax, on node: some ConcreteDeclSyntaxProtocol) {
        if !node.modifiers.containsPublicOrOpen {
            var modifiedNode = node
            modifiedNode.modifiers = DeclModifierListSyntax(
                arrayLiteral:
                    DeclModifierSyntax(
                        name: TokenSyntax(
                            TokenKind.keyword(.public),
                            leadingTrivia: .newline,
                            trailingTrivia: .space,
                            presence: .present
                        )
                    )
            )
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.missingPublicOrOpenAttribute,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(modifiedNode)
                    )
                ]
            ))
        }
    }

    private func initializerToGenerate() -> Initializer? {
        guard uninitializedNonOptionalPropertyNames.isEmpty else {
            // There's an uninitialized property, so we can't generate an initializer.
            return nil
        }
        return Initializer(arguments: dependencies.map {
            Initializer.Argument(
                innerLabel: $0.property.label,
                typeDescription: $0.property.typeDescription
            )
        })
    }
}
