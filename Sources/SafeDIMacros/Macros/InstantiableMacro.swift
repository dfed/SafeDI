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

public struct InstantiableMacro: MemberMacro {
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
            throw InstantiableError.decoratingIncompatibleType
        }

        let visitor = InstantiableVisitor()
        visitor.walk(concreteDeclaration)
        for diagnostic in visitor.diagnostics {
            context.diagnose(diagnostic)
        }

        guard visitor.dependencies.filter({ $0.source == .forwarded }).count <= 1 else {
            throw InstantiableError.tooManyForwardedProperties
        }

        let hasMemberwiseInitializerForInjectableProperties = visitor
            .initializers
            .contains(where: { $0.isValid(forFulfilling: visitor.dependencies) })
        guard hasMemberwiseInitializerForInjectableProperties else {
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
                error: FixableInstantiableError.missingRequiredInitializer,
                changes: [
                    .replace(
                        oldNode: Syntax(declaration.memberBlock.members),
                        newNode: Syntax(membersWithInitializer))
                ]
            ))
            return []
        }

        // TODO: consider generating a memberwise initializer if none exists.
        return []
    }

    // MARK: - BuilderError

    private enum InstantiableError: Error, CustomStringConvertible {
        case decoratingIncompatibleType
        case tooManyForwardedProperties

        var description: String {
            switch self {
            case .decoratingIncompatibleType:
                "@\(InstantiableVisitor.macroName) must decorate a class, struct, or actor"
            case .tooManyForwardedProperties:
                "An @\(InstantiableVisitor.macroName) type must have at most one @\(Dependency.Source.forwarded.rawValue) property"
            }
        }
    }

}
