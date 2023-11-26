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

public struct DependenciesMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
    {
        guard declaration.modifiers.containsPublic else {
            throw DependenciesError.notPublic // TODO: add fixit instead.
        }

        guard let structDelcaration = StructDeclSyntax(declaration) else {
            throw DependenciesError.notStruct // TODO: add fixit instead
        }

        guard structDelcaration.name.text == Self.decoratedStructName else {
            throw DependenciesError.notNamedDependencies // TODO: add fixit instead
        }

        let dependenciesVisitor = DependenciesVisitor()
        dependenciesVisitor.walk(structDelcaration)
        for diagnostic in dependenciesVisitor.diagnostics {
            context.diagnose(diagnostic)
        }

        guard dependenciesVisitor.didFindBuildMethod else {
            var memberWithDependencies = structDelcaration.memberBlock.members
            memberWithDependencies.append(
                MemberBlockItemSyntax(
                    leadingTrivia: .newline,
                    decl: FunctionDeclSyntax.buildTemplate
                )
            )
            context.diagnose(Diagnostic(
                node: structDelcaration,
                error: FixableDependenciesError.missingBuildMethod,
                changes: [
                    .replace(
                        oldNode: Syntax(structDelcaration.memberBlock.members),
                        newNode: Syntax(memberWithDependencies)
                    )
                ]
            ))

            return []
        }

        return [
            """
            public init(\(dependenciesVisitor.dependencies.invariantParameterList)) {
                \(raw: dependenciesVisitor.dependencies.invariantAssignmentExpressionList)
            }
            """
        ]
    }

    static let name = "dependencies"
    static let decoratedStructName = "Dependencies"
    static let buildMethodName = "build"

    // MARK: - DependenciesError

    private enum DependenciesError: Error, CustomStringConvertible {
        case notPublic
        case notStruct
        case notNamedDependencies

        var description: String {
            switch self {
            case .notPublic:
                return "@\(DependenciesMacro.name) struct must be `public`"
            case .notStruct:
                return "@\(DependenciesMacro.name) must decorate a `struct`"
            case .notNamedDependencies:
                return "@\(DependenciesMacro.name) must decorate a `struct` with the name `Dependencies`"
            }
        }
    }
}
