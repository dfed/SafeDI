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
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct BuilderMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
    {
        guard declaration.parent == nil else {
            throw BuilderError.notTopLevelDeclaration
        }

        guard declaration.modifiers.containsPublic else {
            throw BuilderError.notPublic // TODO: add fixit instead.
        }

        guard let structDelcaration = StructDeclSyntax(declaration) else {
            throw BuilderError.notStruct // TODO: add fixit instead
        }

        let builderVisitor = BuilderVisitor()
        builderVisitor.walk(structDelcaration.memberBlock)
        for diagnostic in builderVisitor.diagnostics {
            context.diagnose(diagnostic)
        }

        guard
            let builderMacroArguments = node.arguments,
            let builtPropertyName = builderMacroArguments.string
        else {
            // Builder macro is misconfigured. Compiler will highlight the issue – just fail to expand.
            return []
        }

        guard builderVisitor.didFindDependencies else {
            var memberBlockWithDependencies = structDelcaration.memberBlock
            memberBlockWithDependencies.members.append(
                MemberBlockItemSyntax(decl: StructDeclSyntax.dependenciesTemplate)
            )
            context.diagnose(Diagnostic(
                node: structDelcaration,
                error: FixableBuilderError.missingDependencies,
                changes: [
                    .replace(
                        oldNode: Syntax(structDelcaration.memberBlock),
                        newNode: Syntax(memberBlockWithDependencies)
                    )
                ]
            ))
            return []
        }

        let variantParameterList = builderVisitor.dependencies.variantParameterList
        let variantLabeledExpressionList = builderVisitor.dependencies.variantLabeledExpressionList
        guard let builtType = builderVisitor.builtType else {
            return []
        }
        let builtPropertyDescription = "let \(builtPropertyName): \(builtType)"
        let builderPropertyDescription = "let \(builtPropertyName)\(Self.decoratedStructName): \(structDelcaration.name.text)"
        return [
            """
            // Inject this builder as a dependency by adding `\(raw: builderPropertyDescription)` to your @\(raw: DependenciesMacro.name) type
            public init(\(raw: Self.getDependenciesClosureName): @escaping (\(variantParameterList)) -> \(raw: DependenciesMacro.decoratedStructName)) {
                self.\(raw: Self.getDependenciesClosureName) = \(raw: Self.getDependenciesClosureName)
            }
            """,
            """
            // Inject this built product as a dependency by adding `\(raw: builtPropertyDescription)` to your @\(raw: DependenciesMacro.name) type
            public func build(\(variantParameterList)) -> \(raw: builtType) {
                \(raw: Self.getDependenciesClosureName)(\(raw: variantLabeledExpressionList)).build(\(raw: variantLabeledExpressionList))
            }
            """,
            """
            private let \(raw: Self.getDependenciesClosureName): (\(variantParameterList)) -> \(raw: DependenciesMacro.decoratedStructName)
            """,
        ]
    }

    static let name = "builder"
    static let decoratedStructName = "Builder"
    static let getDependenciesClosureName = "getDependencies"

    // MARK: - BuilderError

    private enum BuilderError: Error, CustomStringConvertible {
        case notTopLevelDeclaration
        case notPublic
        case notStruct
        
        var description: String {
            switch self {
            case .notPublic:
                return "@\(BuilderMacro.name) struct must be `public`"
            case .notStruct:
                return "@\(BuilderMacro.name) must decorate a `struct`"
            case .notTopLevelDeclaration:
                return "@\(BuilderMacro.name) struct is not declared at the top level"
            }
        }
    }
}
