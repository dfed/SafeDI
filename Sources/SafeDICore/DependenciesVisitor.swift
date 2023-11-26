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

public final class DependenciesVisitor: SyntaxVisitor {

    // MARK: Initialization

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
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
                            TokenKind.identifier(Dependency.Source.constructedAttributeName),
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
        if node.modifiers.staticModifier != nil {
            var mutatedNode = node
            mutatedNode.modifiers = mutatedNode.modifiers.filter {
                $0.name.text != "static"
            }
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableDependenciesError.dependencyIsStatic,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(mutatedNode)
                    )
                ]
            ))
        }

        if node.modifiers.count != 1,
           node.modifiers.first?.name.text != "private"
        {
            let replacedModifiers = DeclModifierListSyntax(
                arrayLiteral: DeclModifierSyntax(
                    name: TokenSyntax(
                        TokenKind.identifier("private"),
                        presence: .present
                    )
                )
            )
            var modifiedNode = node
            modifiedNode.modifiers = replacedModifiers
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableDependenciesError.dependencyIsNotPrivate,
                changes: [
                    .replace(
                        oldNode: Syntax(node),
                        newNode: Syntax(modifiedNode)
                    )
                ]
            ))
            return .skipChildren
        }

        // Check the binding specifier.
        if node.bindingSpecifier.text == "var" {
            diagnostics.append(Diagnostic(
                node: node,
                error: FixableDependenciesError.dependencyIsMutable,
                changes: [
                    .replace(
                        oldNode: Syntax(node.bindingSpecifier),
                        newNode: Syntax(TokenSyntax(TokenKind.keyword(.let), presence: .present))
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
                    node: node,
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
                let label = IdentifierPatternSyntax(binding.pattern)?.identifier.text,
                let type = binding.typeAnnotation?.type
            {
                addDependency(
                    Dependency(
                        property: Property(
                            label: label,
                            type: type.description
                        ),
                        source: dependencySource
                    ),
                    derivedFrom: Syntax(node)
                )
            }
        }

        return .skipChildren
    }

    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard
            let parent = node.parent,
            let typedParent = MemberBlockItemSyntax(parent),
            let greatGrandparent = parent.parent?.parent,
            var modifiedGreatGrandparent = MemberBlockSyntax(greatGrandparent),
            let index = modifiedGreatGrandparent.members.index(of: typedParent)
        else {
            return .skipChildren
        }

        modifiedGreatGrandparent.members.remove(at: index)

        diagnostics.append(Diagnostic(
            node: node,
            error: FixableDependenciesError.unexpectedInitializer,
            changes: [
                .replace(
                    oldNode: greatGrandparent,
                    newNode: Syntax(modifiedGreatGrandparent)
                )
            ]
        ))
        return .skipChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == DependenciesVisitor.buildMethodName {
            if didFindBuildMethod {
                // We've already found a `build` method!
                if
                    let parent = node.parent,
                    let typedParent = MemberBlockItemSyntax(parent),
                    let greatGrandparent = parent.parent?.parent,
                    var modifiedGreatGrandparent = MemberBlockSyntax(greatGrandparent),
                    let index = modifiedGreatGrandparent.members.index(of: typedParent)
                {
                    modifiedGreatGrandparent.members.remove(at: index)
                    diagnostics.append(Diagnostic(
                        node: node,
                        error: FixableDependenciesError.multipleBuildMethods,
                        changes: [
                            .replace(
                                oldNode: Syntax(greatGrandparent),
                                newNode: Syntax(modifiedGreatGrandparent)
                            )
                        ]
                    ))
                } else {
                    assertionFailure("Found duplicate build method with unexpected properties \(node)")
                }

            } else {
                didFindBuildMethod = true
                for parameter in node.signature.parameterClause.parameters {
                    addDependency(
                        Dependency(
                            property: Property(
                                label: parameter.secondName?.text ?? parameter.firstName.text,
                                type: parameter.type.trimmedDescription
                            ),
                            source: .variant
                        ),
                        derivedFrom: Syntax(parameter)
                    )
                }

                if let returnClause = node.signature.returnClause {
                    builtType = returnClause.type.trimmedDescription
                } else {
                    var signatureWithReturnClause = node.signature
                    signatureWithReturnClause.returnClause = FunctionDeclSyntax.returnClauseTemplate
                    diagnostics.append(Diagnostic(
                        node: node,
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

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == DependenciesVisitor.decoratedStructName {
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
                            name: .identifier(DependenciesVisitor.decoratedStructName)
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

    // MARK: Public

    public private(set) var didFindBuildMethod = false
    public private(set) var dependencies = [Dependency]()
    public private(set) var builtType: String?
    public private(set) var diagnostics = [Diagnostic]()

    public static let macroName = "dependencies"
    public static let decoratedStructName = "Dependencies"
    public static let buildMethodName = "build"

    // MARK: Private

    private var dependencyVariableNames = Set<String>()

    private func addDependency(_ dependency: Dependency, derivedFrom node: Syntax) {
        guard !dependencyVariableNames.contains(dependency.property.label) else {
            if
                let typedNode = FunctionParameterSyntax(node),
                let parent = node.parent,
                let typedParent = FunctionParameterListSyntax(parent),
                let index = typedParent.index(of: typedNode)
            {
                var modifiedParent = typedParent
                modifiedParent.remove(at: index)
                diagnostics.append(Diagnostic(
                    node: node,
                    error: FixableDependenciesError.duplicateDependency,
                    changes: [
                        .replace(
                            oldNode: Syntax(typedParent),
                            newNode: Syntax(modifiedParent)
                        )
                    ]
                ))
            } else if
                let parent = node.parent,
                let typedParent = MemberBlockItemSyntax(parent),
                let greatGrandparent = parent.parent?.parent,
                var modifiedGreatGrandparent = MemberBlockSyntax(greatGrandparent),
                let index = modifiedGreatGrandparent.members.index(of: typedParent)
            {
                modifiedGreatGrandparent.members.remove(at: index)
                diagnostics.append(Diagnostic(
                    node: node,
                    error: FixableDependenciesError.duplicateDependency,
                    changes: [
                        .replace(
                            oldNode: Syntax(greatGrandparent),
                            newNode: Syntax(modifiedGreatGrandparent)
                        )
                    ]
                ))
            } else {
                assertionFailure("Unexpected node with duplicate dependency \(node)")
            }
            return
        }
        dependencyVariableNames.insert(dependency.property.label)
        dependencies.append(dependency)
    }
}
