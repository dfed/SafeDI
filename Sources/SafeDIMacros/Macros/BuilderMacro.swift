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

public struct BuilderMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
    {
        guard declaration.modifiers.containsPublic else {
            throw BuilderError.notPublic // TODO: add fixit instead.
        }

        guard let structDelcaration = StructDeclSyntax(declaration) else {
            throw BuilderError.notStruct // TODO: add fixit instead
        }

        let builderVisitor = BuilderVisitor()
        builderVisitor.walk(structDelcaration)
        for diagnostic in builderVisitor.diagnostics {
            context.diagnose(diagnostic)
        }

        guard builderVisitor.didFindDependencies else {
            var membersWithDependencies = structDelcaration.memberBlock.members
            membersWithDependencies.append(
                MemberBlockItemSyntax(
                    leadingTrivia: .newline,
                    decl: StructDeclSyntax.dependenciesTemplate,
                    trailingTrivia: .newline
                )
            )
            context.diagnose(Diagnostic(
                node: structDelcaration,
                error: FixableBuilderError.missingDependencies,
                changes: [
                    .replace(
                        oldNode: Syntax(structDelcaration.memberBlock.members),
                        newNode: Syntax(membersWithDependencies)
                    )
                ]
            ))
            return []
        }

        guard let builder = builderVisitor.builder else {
            // Builder macro is misconfigured. Compiler will highlight the issue – just fail to expand.
            return []
        }

        let variantUnlabeledParameterList = builder.dependencies.variantUnlabeledParameterList
        let variantParameterList = builder.dependencies.variantParameterList
        let variantUnlabeledExpressionList = builder.dependencies.variantUnlabeledExpressionList
        let variantLabeledExpressionList = builder.dependencies.variantLabeledExpressionList
        let builtPropertyDescription = builder.builtProduct.asPropertyDeclaration
        let builderPropertyDescription = builder.builder.asPropertyDeclaration
        return [
            """
            // Inject this builder as a dependency by adding `\(raw: builderPropertyDescription)` to your @\(raw: DependenciesVisitor.macroName) type
            public init(\(raw: BuilderVisitor.getDependenciesClosureName): @escaping (\(variantUnlabeledParameterList)) -> \(raw: DependenciesVisitor.decoratedStructName)) {
                self.\(raw: BuilderVisitor.getDependenciesClosureName) = \(raw: BuilderVisitor.getDependenciesClosureName)
            }
            """,
            """
            // Inject this built product as a dependency by adding `\(raw: builtPropertyDescription)` to your @\(raw: DependenciesVisitor.macroName) type
            public func build(\(variantParameterList)) -> \(raw: builder.builtProduct.type) {
                \(raw: BuilderVisitor.getDependenciesClosureName)(\(raw: variantUnlabeledExpressionList)).build(\(raw: variantLabeledExpressionList))
            }
            """,
            """
            private let \(raw: BuilderVisitor.getDependenciesClosureName): (\(variantUnlabeledParameterList)) -> \(raw: DependenciesVisitor.decoratedStructName)
            """,
        ]
    }

    // MARK: - BuilderError

    private enum BuilderError: Error, CustomStringConvertible {
        case notPublic
        case notStruct
        
        var description: String {
            switch self {
            case .notPublic:
                return "@\(BuilderVisitor.macroName) struct must be `public`"
            case .notStruct:
                return "@\(BuilderVisitor.macroName) must decorate a `struct`"
            }
        }
    }
}
