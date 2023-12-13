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

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
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
                let fulfillingTypeDescription: TypeDescription? = if
                    let fulfilledByTypeExpression = node.attributes.instantiatedMacro?.fulfilledByType,
                    let stringLiteral = StringLiteralExprSyntax(fulfilledByTypeExpression),
                    let fulfilledByType = stringLiteral.segments.firstStringSegment
                {
                    TypeSyntax(stringLiteral: fulfilledByType).typeDescription
                } else {
                    nil
                }

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
                            case .lazyInstantiated:
                                Property(
                                    label: "\(label)\(Dependency.instantiatorType)",
                                    // TODO: fully qualify this type with `SafeDI.` member prefix
                                    typeDescription: .simple(
                                        name: Dependency.instantiatorType,
                                        generics: [typeDescription]
                                    )
                                )
                            }
                        }(),
                        source: dependencySource,
                        fulfillingTypeDescription: fulfillingTypeDescription
                    )
                )
            }
        }

        return .skipChildren
    }

    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        initializers.append(Initializer(node))
        return .skipChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
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

    // MARK: Public

    public private(set) var dependencies = [Dependency]()
    public private(set) var initializers = [Initializer]()
    public private(set) var instantiableType: TypeDescription?
    public private(set) var additionalInstantiableTypes: [TypeDescription]?
    public private(set) var diagnostics = [Diagnostic]()

    public static let macroName = "Instantiable"

    // MARK: Internal

    var instantiable: Instantiable? {
        guard
            let instantiableType,
            let topLevelDeclarationType
        else { return nil }
        return Instantiable(
            instantiableType: instantiableType,
            initializer: initializers.first(where: { $0.isValid(forFulfilling: dependencies) }),
            additionalInstantiableTypes: additionalInstantiableTypes,
            dependencies: dependencies,
            declarationType: topLevelDeclarationType.asDeclarationType
        )
    }

    // MARK: Private

    private var isInTopLevelDeclaration = false
    private var topLevelDeclarationType: ConcreteDeclType?

    private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
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
}
