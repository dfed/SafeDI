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

    public init(
        declarationType: DeclarationType,
        parentType: TypeDescription? = nil
    ) {
        self.declarationType = declarationType
        self.parentType = parentType
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard declarationType.isTypeDefinition,
              node.modifiers.staticModifier == nil
        else {
            return .skipChildren
        }
        // Check attributes and extract dependency source.
        let dependencySources = node.attributes.dependencySources
        if dependencySources.count > 1 {
            diagnostics.append(Diagnostic(
                node: node.attributes,
                error: FixableInstantiableError.dependencyHasTooManyAttributes,
                changes: [
                    .replace(
                        oldNode: Syntax(node.attributes),
                        newNode: Syntax(dependencySources[0].node)
                    ),
                ]
            ))
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
                        ),
                    ]
                ))
            }

            if let label = IdentifierPatternSyntax(binding.pattern)?.identifier.text,
               let typeDescription = binding.typeAnnotation?.type.typeDescription
            {
                dependencies.append(
                    Dependency(
                        property: Property(
                            label: label,
                            typeDescription: typeDescription
                        ),
                        source: dependencySource
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

    public override func visit(_: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        instantiableType = node.extendedType.typeDescription
        if let instantiableMacro = node.attributes.instantiableMacro {
            processAttributes(node.attributes, on: instantiableMacro)
        }

        return .visitChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard declarationType.isExtension else {
            return .skipChildren
        }
        guard node.name.text == Self.instantiateMethodName else {
            // We don't care about this method.
            return .skipChildren
        }

        if let returnClause = node.signature.returnClause,
           returnClause.type.typeDescription.strippingGenerics != instantiableType?.strippingGenerics,
           let instantiableType
        {
            var modifiedSignature = node.signature
            modifiedSignature.returnClause = ReturnClauseSyntax(
                arrow: .arrowToken(
                    leadingTrivia: returnClause.arrow.leadingTrivia,
                    trailingTrivia: returnClause.arrow.trailingTrivia
                ),
                type: IdentifierTypeSyntax(
                    leadingTrivia: node.signature.leadingTrivia,
                    name: .identifier(instantiableType.strippingGenerics.asSource),
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
                    ),
                ]
            ))
        }

        let initializer = Initializer(node)
        if let instantiableType = node.signature.returnClause?.type.typeDescription {
            extensionInstantiables.append(.init(
                instantiableType: instantiableType,
                isRoot: false,
                initializer: initializer,
                additionalInstantiables: additionalInstantiables,
                dependencies: initializer.arguments.map {
                    Dependency(
                        property: $0.asProperty,
                        source: .received
                    )
                },
                declarationType: .extensionType
            ))
        }

        if !initializer.isPublicOrOpen || node.modifiers.staticModifier == nil {
            var modifiedNode = node
            modifiedNode.modifiers = DeclModifierListSyntax(
                arrayLiteral:
                DeclModifierSyntax(
                    name: TokenSyntax(
                        TokenKind.keyword(.public),
                        leadingTrivia: node.modifiers.first?.leadingTrivia ?? node.funcKeyword.leadingTrivia,
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
            modifiedNode.funcKeyword.leadingTrivia = []
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.missingAttributes,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(modifiedNode)
                    ),
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
                    ),
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
                    ),
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
                    ),
                ]
            ))
        }

        return .skipChildren
    }

    // MARK: Public

    public private(set) var isRoot = false
    public private(set) var dependencies = [Dependency]()
    public private(set) var initializers = [Initializer]()
    public private(set) var instantiableType: TypeDescription?
    public private(set) var additionalInstantiables: [TypeDescription]?
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

    public var instantiables: [Instantiable] {
        switch declarationType {
        case .concreteDecl:
            if let instantiableType, let instantiableDeclarationType {
                [
                    Instantiable(
                        instantiableType: instantiableType,
                        isRoot: isRoot,
                        initializer: initializers.first(where: { $0.isValid(forFulfilling: dependencies) }),
                        additionalInstantiables: additionalInstantiables,
                        dependencies: dependencies,
                        declarationType: instantiableDeclarationType.asDeclarationType
                    ),
                ]
            } else {
                []
            }
        case .extensionDecl:
            extensionInstantiables
        }
    }

    // MARK: Private

    private var hasFoundDeclaration = false
    private var instantiableDeclarationType: ConcreteDeclType?

    private var extensionInstantiables = [Instantiable]()

    private let declarationType: DeclarationType
    private let parentType: TypeDescription?

    private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
        let nodeDeclarationType: TypeDescription = if let parentType {
            .nested(
                name: node.name.text,
                parentType: parentType
            )
        } else {
            .simple(name: node.name.text)
        }
        guard declarationType.isTypeDefinition else {
            return .skipChildren
        }
        guard let macro = node.attributes.instantiableMacro else {
            // Not an instantiable type. We do not care.
            return .skipChildren
        }
        guard !hasFoundDeclaration else {
            return .skipChildren
        }
        hasFoundDeclaration = true
        instantiableDeclarationType = node.declType

        instantiableType = nodeDeclarationType
        processAttributes(node.attributes, on: macro)
        processModifiers(node.modifiers, on: node)

        return .visitChildren
    }

    private func processAttributes(_: AttributeListSyntax, on macro: AttributeSyntax) {
        func processIsRoot() {
            guard let isRootExpression = macro.isRoot,
                  let boolExpression = BooleanLiteralExprSyntax(isRootExpression)
            else {
                // Nothing to do here.
                return
            }

            isRoot = boolExpression.literal.tokenKind == .keyword(.true)
        }
        func processFulfillingAdditionalTypesParameter() {
            guard let fulfillingAdditionalTypesExpression = macro.fulfillingAdditionalTypes,
                  let fulfillingAdditionalTypesArray = ArrayExprSyntax(fulfillingAdditionalTypesExpression)
            else {
                // Nothing to do here.
                return
            }

            additionalInstantiables = fulfillingAdditionalTypesArray
                .elements
                .map(\.expression.typeDescription.asInstantiatedType)
        }

        processIsRoot()
        processFulfillingAdditionalTypesParameter()
    }

    private func processModifiers(_: DeclModifierListSyntax, on node: some ConcreteDeclSyntaxProtocol) {
        if !node.modifiers.containsPublicOrOpen {
            let publicModifier = DeclModifierSyntax(
                name: TokenSyntax(
                    TokenKind.keyword(.public),
                    leadingTrivia: node.modifiers.first?.leadingTrivia ?? .newline,
                    trailingTrivia: node.modifiers.first?.trailingTrivia ?? .space,
                    presence: .present
                )
            )
            var modifiedNode = node
            if var firstModifier = modifiedNode.modifiers.first {
                firstModifier.name.leadingTrivia = []
                modifiedNode.modifiers.replaceSubrange(
                    modifiedNode.modifiers.startIndex..<modifiedNode.attributes.index(after: modifiedNode.attributes.startIndex),
                    with: [publicModifier, firstModifier]
                )
                modifiedNode.modifiers = modifiedNode.modifiers.filter {
                    $0.name.text != "internal" && $0.name.text != "fileprivate" && $0.name.text != "private"
                }
            } else {
                modifiedNode.modifiers = [publicModifier]
                modifiedNode.keyword.leadingTrivia = []
            }
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableInstantiableError.missingPublicOrOpenAttribute,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(modifiedNode)
                    ),
                ]
            ))
        }
    }
}
