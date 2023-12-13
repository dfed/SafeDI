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

public final class ExternalInstantiableVisitor: SyntaxVisitor {

    // MARK: Initialization

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let externalInstantiableMacro = node.attributes.externalInstantiableMacro else {
            // Not an external instantiable type. We do not care.
            return .skipChildren
        }

        instantiableType = node.extendedType.typeDescription
        processAttributes(node.attributes, on: externalInstantiableMacro)

        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
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
                error: FixableExternalInstantiableError.incorrectReturnType,
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
                error: FixableExternalInstantiableError.missingAttributes,
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
                error: FixableExternalInstantiableError.disallowedEffectSpecifiers,
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
                error: FixableExternalInstantiableError.disallowedGenericParameter,
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
                error: FixableExternalInstantiableError.disallowedGenericWhereClause,
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

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
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

    public static let macroName = "ExternalInstantiable"
    public static let instantiateMethodName = "instantiate"

    // MARK: Internal

    var instantiable: Instantiable? {
        guard let instantiableType else { return nil }
        return Instantiable(
            instantiableType: instantiableType,
            // If we have more than one initializer this isn't a valid extension.
            initializer: initializers.count > 1 ? nil : initializers.first,
            additionalInstantiableTypes: additionalInstantiableTypes,
            dependencies: dependencies,
            declarationType: .extensionType)
    }

    // MARK: Private

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
}
