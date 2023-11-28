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

public final class ConstructableVisitor: SyntaxVisitor {

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
                error: FixableConstructableError.dependencyHasTooManyAttributes,
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
                    error: FixableConstructableError.dependencyHasInitializer,
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
                let type = binding.typeAnnotation?.type
            {
                dependencies.append(
                    Dependency(
                        property: Property(
                            label: label,
                            type: type.description
                        ),
                        source: dependencySource
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

    // MARK: Public

    public private(set) var dependencies = [Dependency]()
    public private(set) var initializers = [Initializer]()
    public private(set) var constructableType: String?
    public private(set) var additionalConstructableTypes: [String]?
    public private(set) var diagnostics = [Diagnostic]()
    public var constructable: Constructable? {
        guard let constructableType else { return nil }
        return Constructable(
            constructableType: constructableType,
            additionalConstructableTypes: additionalConstructableTypes,
            dependencies: dependencies)
    }

    public static let macroName = "constructable"

    // MARK: Private

    private var isInTopLevelDeclaration = false

    private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
        guard !isInTopLevelDeclaration else {
            return .skipChildren
        }
        isInTopLevelDeclaration = true

        constructableType = node.name.text
        processAttributes(node.attributes, on: node)
        processModifiers(node.modifiers, on: node)

        return .visitChildren
    }

    private func processAttributes(_ attributes: AttributeListSyntax, on node: some ConcreteDeclSyntaxProtocol) {
        guard let macro = attributes.constructingMacro else {
            assertionFailure("Constructing macro not found despite processing top-level declaration")
            return
        }
        guard 
            let fulfillingAdditionalTypesArgument = macro.arguments,
            let fulfillingAdditionalTypesExpressionList = LabeledExprListSyntax(fulfillingAdditionalTypesArgument),
            let fulfillingAdditionalTypesExpression = fulfillingAdditionalTypesExpressionList.first?.expression,
            let fulfillingAdditionalTypesArray = ArrayExprSyntax(fulfillingAdditionalTypesExpression)
        else {
            // Nothing to do here.
            return
        }

        additionalConstructableTypes = fulfillingAdditionalTypesArray
            .elements
            .map { $0.expression }
            .compactMap { MemberAccessExprSyntax($0)?.base }
            .compactMap { DeclReferenceExprSyntax($0)?.baseName.text }
    }

    private func processModifiers(_ modifiers: DeclModifierListSyntax, on node: some ConcreteDeclSyntaxProtocol) {
        if !node.modifiers.containsPublicOrOpen {
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableConstructableError.missingPublicOrOpenAttribute,
                changes: [
                    .replace(
                        oldNode: Syntax(node.modifiers),
                        newNode: Syntax(DeclModifierListSyntax(
                            arrayLiteral:
                                DeclModifierSyntax(
                                    name: TokenSyntax(
                                        TokenKind.keyword(.public),
                                        leadingTrivia: .newline,
                                        trailingTrivia: .space,
                                        presence: .present
                                    )
                                )
                        ))
                    )
                ]
            ))
        }
    }
}
