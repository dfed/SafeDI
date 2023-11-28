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

public struct ConstructableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
    {
        guard
            let concreteDeclaration: ConcreteDeclSyntaxProtocol 
                = ActorDeclSyntax(declaration)
                ?? ClassDeclSyntax(declaration)
                ?? StructDeclSyntax(declaration) else {
            throw ConstructableError.decoratingIncompatibleType
        }

        let visitor = ConstructableVisitor()
        visitor.walk(concreteDeclaration)
        for diagnostic in visitor.diagnostics {
            context.diagnose(diagnostic)
        }

        let initializerAndResultPairs = visitor.initializers.map { initializer in
            (initializer: initializer, result: Result {
                try initializer.generateSafeDIInitializer(
                    fulfilling: visitor.dependencies,
                    typeIsClass: concreteDeclaration.isClass
                )
            })
        }

        guard
            let generatedInitializer = initializerAndResultPairs
                .compactMap({ try? $0.result.get() })
                .first
        else {
            if initializerAndResultPairs.isEmpty {
                var membersWithInitializer = declaration.memberBlock.members
                membersWithInitializer.insert(
                    MemberBlockItemSyntax(
                        leadingTrivia: .newline,
                        decl: Initializer.generateRequiredInitializer(for: visitor.dependencies),
                        trailingTrivia: .newline
                    ),
                    at: membersWithInitializer.startIndex
                )
                context.diagnose(Diagnostic(
                    node: Syntax(declaration.memberBlock),
                    error: FixableConstructableError.missingRequiredInitializer,
                    changes: [
                        .replace(
                            oldNode: Syntax(declaration.memberBlock.members),
                            newNode: Syntax(membersWithInitializer))
                    ]))
            }
            return []
        }

        return [
            DeclSyntax(generatedInitializer)
        ]
    }

    // MARK: - BuilderError

    private enum ConstructableError: Error, CustomStringConvertible {
        case decoratingIncompatibleType

        var description: String {
            switch self {
            case .decoratingIncompatibleType:
                return "@\(ConstructableVisitor.macroName) must decorate a class, struct, or actor"
            }
        }
    }

}
