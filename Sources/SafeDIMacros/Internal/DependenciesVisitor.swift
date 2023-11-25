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

final class DependenciesVisitor: SyntaxVisitor {

    // MARK: Initialization

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check attributes and extract dependency source.
        let dependencySources = node.attributes.dependencySources
        guard dependencySources.isEmpty || dependencySources.count == 1 else {
            let replacementNode: Syntax
            if let firstDependencySourceNode = dependencySources.first?.node {
                replacementNode = Syntax(firstDependencySourceNode)
            } else {
                replacementNode = Syntax(AttributeSyntax(
                    attributeName: IdentifierTypeSyntax(
                        name: TokenSyntax(
                            TokenKind.identifier(ConstructedMacro.name),
                            presence: .present
                        )
                    )
                ))
            }
            diagnostics.append(Diagnostic(
                node: node.attributes,
                error: FixableDependenciesError.dependencyHasTooManyAttributes,
                changes: [
                    .replace(
                        oldNode: Syntax(node.attributes),
                        newNode: replacementNode
                    )
                ]
            ))
            return .skipChildren
        }
        let dependencySource = dependencySources.first?.source ?? .providedInvariant

        // Check modifiers.
        if let staticModifier = node.modifiers.staticModifier {
            diagnostics.append(Diagnostic(
                node: node.attributes,
                error: FixableDependenciesError.dependencyIsStatic,
                changes: [
                    .replace(
                        oldNode: Syntax(node.modifiers),
                        newNode: Syntax(node.modifiers.filter {
                            $0 != staticModifier
                        })
                    )
                ]
            ))
        }

        if node.modifiers.count != 1,
           node.modifiers.first?.name.text != "private"
        {
            diagnostics.append(Diagnostic(
                node: node.modifiers,
                error: FixableDependenciesError.dependencyIsNotPrivate,
                changes: [
                    .replace(
                        oldNode: Syntax(node.modifiers),
                        newNode: Syntax(DeclModifierSyntax(
                            name: TokenSyntax(
                                TokenKind.identifier("private"),
                                presence: .present
                            )
                        ))
                    )
                ]
            ))
            return .skipChildren
        }

        // Check the binding specifier.
        if node.bindingSpecifier.text == "var" {
            diagnostics.append(Diagnostic(
                node: node.modifiers,
                error: FixableDependenciesError.dependencyIsMutable,
                changes: [
                    .replace(
                        oldNode: Syntax(node.bindingSpecifier),
                        newNode: Syntax(TokenSyntax(TokenKind.keyword(.var), presence: .present))
                    )
                ]
            ))
        }

        for binding in node.bindings {
            // Check that each variable has no initializer.
            if binding.initializer != nil {
                var bindingWithoutInitializer = binding
                bindingWithoutInitializer.initializer = nil
                diagnostics.append(Diagnostic(
                    node: node.modifiers,
                    error: FixableDependenciesError.unexpectedInitializer,
                    changes: [
                        .replace(
                            oldNode: Syntax(binding),
                            newNode: Syntax(bindingWithoutInitializer)
                        )
                    ]
                ))
            }

            if
                let variableName = IdentifierPatternSyntax(binding.pattern)?.identifier.text,
                let type = binding.typeAnnotation?.type
            {
                addDependency(
                    Dependency(
                        variableName: variableName,
                        type: type.description,
                        source: dependencySource
                    ),
                    derivedFrom: Syntax(node)
                )
            }
        }

        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        diagnostics.append(Diagnostic(
            node: node.modifiers,
            error: FixableDependenciesError.unexpectedInitializer,
            changes: [
                .replace(
                    oldNode: Syntax(node),
                    newNode: .empty
                )
            ]
        ))
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == DependenciesMacro.buildMethodName {
            if didFindBuildMethod {
                // We've already found a `build` method!
                diagnostics.append(Diagnostic(
                    node: node.modifiers,
                    error: FixableDependenciesError.multipleBuildMethods,
                    changes: [
                        .replace(
                            oldNode: Syntax(node),
                            newNode: .empty
                        )
                    ]
                ))

            } else {
                didFindBuildMethod = true
                for parameter in node.signature.parameterClause.parameters {
                    addDependency(
                        Dependency(
                            variableName: parameter.secondName?.text ?? parameter.firstName.text,
                            type: parameter.type.trimmedDescription,
                            source: .variant
                        ),
                        derivedFrom: Syntax(node)
                    )
                }

                if let returnClause = node.signature.returnClause {
                    builtType = returnClause.type.trimmedDescription
                } else {
                    var signatureWithReturnClause = node.signature
                    signatureWithReturnClause.returnClause = FunctionDeclSyntax.returnClauseTemplate
                    diagnostics.append(Diagnostic(
                        node: node.modifiers,
                        error: FixableDependenciesError.missingBuildMethodReturnClause,
                        changes: [
                            .replace(
                                oldNode: Syntax(node.signature),
                                newNode: Syntax(signatureWithReturnClause)
                            )
                        ]
                    ))
                }
            }
        }

        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == DependenciesMacro.decoratedStructName {
            guard node.modifiers.containsPublic else {
                diagnostics.append(Diagnostic(
                    node: node.attributes,
                    error: FixableDependenciesError.missingPublicAttributeOnDependencies,
                    changes: [
                        .replace(
                            oldNode: Syntax(node.modifiers),
                            newNode: Syntax(DeclModifierSyntax(
                                name: TokenSyntax(
                                    TokenKind.keyword(.public),
                                    presence: .present
                                )
                            ))
                        )
                    ]
                ))
                return .skipChildren
            }

            guard node.attributes.isDecoratedWithDependenciesMacro else {
                var newAttributes = node.attributes
                newAttributes.append(.attribute(
                    AttributeSyntax(
                        attributeName: IdentifierTypeSyntax(
                            name: .identifier(DependenciesMacro.decoratedStructName)
                        )
                    )
                ))

                diagnostics.append(Diagnostic(
                    node: node.attributes,
                    error: FixableDependenciesError.missingDependenciesAttribute,
                    changes: [
                        .replace(
                            oldNode: Syntax(node.attributes),
                            newNode: Syntax(newAttributes)
                        )
                    ]
                ))
                return .skipChildren
            }

            return .visitChildren
        } else {
            return .skipChildren
        }
    }

    // MARK: Internal

    private(set) var didFindBuildMethod = false
    private(set) var dependencies = [Dependency]()
    private(set) var builtType: String?
    private(set) var diagnostics = [Diagnostic]()

    // MARK: Private

    private var dependencyVariableNames = Set<String>()

    private func addDependency(_ dependency: Dependency, derivedFrom node: Syntax) {
        guard !dependencyVariableNames.contains(dependency.variableName) else {
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableDependenciesError.duplicateDependency,
                changes: [
                    .replace(
                        oldNode: node,
                        newNode: .empty)
                ]
            ))
            return
        }
        dependencyVariableNames.insert(dependency.variableName)
        dependencies.append(dependency)
    }
}
