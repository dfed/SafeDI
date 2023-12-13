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

public struct ExternalInstantiableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
    {
        guard let extensionDeclaration = ExtensionDeclSyntax(declaration) else {
            throw ExternalInstantiableError.decoratingIncompatibleDeclaration
        }

        if let fulfillingAdditionalTypesArgument = extensionDeclaration.attributes.externalInstantiableMacro?.fulfillingAdditionalTypes {
            if ArrayExprSyntax(fulfillingAdditionalTypesArgument) == nil {
                throw ExternalInstantiableError.fulfillingAdditionalTypesArgumentInvalid
            }
        }

        if extensionDeclaration.genericWhereClause != nil {
            var modifiedDeclaration = extensionDeclaration
            modifiedDeclaration.genericWhereClause = nil
            context.diagnose(Diagnostic(
                node: node,
                error: FixableExternalInstantiableError.disallowedGenericWhereClause,
                changes: [
                    .replace(
                        oldNode: Syntax(extensionDeclaration),
                        newNode: Syntax(modifiedDeclaration)
                    )
                ]
            ))
        }

        let visitor = ExternalInstantiableVisitor()
        visitor.walk(extensionDeclaration)
        for diagnostic in visitor.diagnostics {
            context.diagnose(diagnostic)
        }

        let initializersCount = visitor.initializers.count
        if initializersCount > 1 {
            throw ExternalInstantiableError.tooManyInstantiateMethods
        } else if initializersCount == 0 {
            let extendedTypeName = extensionDeclaration.extendedType.typeDescription.asSource
            var membersWithInitializer = declaration.memberBlock.members
            membersWithInitializer.insert(
                MemberBlockItemSyntax(
                    leadingTrivia: .newline,
                    decl: FunctionDeclSyntax(
                        modifiers: DeclModifierListSyntax(
                            arrayLiteral: DeclModifierSyntax(
                                name: TokenSyntax(
                                    TokenKind.keyword(.public),
                                    presence: .present
                                ),
                                trailingTrivia: .space
                            ),
                            DeclModifierSyntax(
                                name: TokenSyntax(
                                    TokenKind.keyword(.static),
                                    presence: .present
                                ),
                                trailingTrivia: .space
                            )
                        ),
                        name: TokenSyntax(
                            TokenKind.identifier(ExternalInstantiableVisitor.instantiateMethodName), 
                            leadingTrivia: .space,
                            presence: .present
                        ),
                        signature: FunctionSignatureSyntax(
                            parameterClause: FunctionParameterClauseSyntax(
                                parameters: FunctionParameterListSyntax([])
                            ),
                            returnClause: ReturnClauseSyntax(
                                arrow: .arrowToken(
                                    leadingTrivia: .space,
                                    trailingTrivia: .space
                                ),
                                type: IdentifierTypeSyntax(
                                    name: .identifier(extendedTypeName)
                                )
                            )
                        ),
                        body: CodeBlockSyntax(
                            leadingTrivia: .newline,
                            statements: CodeBlockItemListSyntax([]),
                            trailingTrivia: .newline
                        )
                    ),
                    trailingTrivia: .newline
                ),
                at: membersWithInitializer.startIndex
            )
            context.diagnose(Diagnostic(
                node: Syntax(extensionDeclaration.memberBlock.members),
                error: FixableExternalInstantiableError.missingRequiredInstantiateMethod(
                    typeName: extendedTypeName
                ),
                changes: [
                    .replace(
                        oldNode: Syntax(declaration.memberBlock.members),
                        newNode: Syntax(membersWithInitializer))
                ]
            ))
        }

        return []
    }

    // MARK: - ExternalInstantiableError

    private enum ExternalInstantiableError: Error, CustomStringConvertible {
        case decoratingIncompatibleDeclaration
        case fulfillingAdditionalTypesArgumentInvalid
        case tooManyInstantiateMethods

        var description: String {
            switch self {
            case .decoratingIncompatibleDeclaration:
                "@\(ExternalInstantiableVisitor.macroName) must decorate an extension"
            case .fulfillingAdditionalTypesArgumentInvalid:
                "The argument `fulfillingAdditionalTypes` must be an inlined array"
            case .tooManyInstantiateMethods:
                "@\(ExternalInstantiableVisitor.macroName)-decorated extension must have a single `instantiate()` method"
            }
        }
    }

}
