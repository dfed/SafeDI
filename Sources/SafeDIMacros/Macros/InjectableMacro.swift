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
import SwiftSyntaxMacros

public struct InjectableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
    {
        guard let variableDecl = VariableDeclSyntax(declaration) else {
            throw InjectableError.notDecoratingBinding
        }

        guard variableDecl.modifiers.staticModifier == nil else {
            throw InjectableError.decoratingStatic
        }

        if variableDecl.bindingSpecifier.text != TokenSyntax.keyword(.let).text {
            context.diagnose(Diagnostic(
                node: variableDecl.bindingSpecifier,
                error: FixableInjectableError.unexpectedMutable,
                changes: [
                    .replace(
                        oldNode: Syntax(variableDecl.bindingSpecifier),
                        newNode: Syntax(TokenSyntax.keyword(
                            .let,
                            leadingTrivia: .space,
                            trailingTrivia: .space
                        ))
                    )
                ]
            ))
        }

        // This macro purposefully does not expand.
        // This macro serves as a decorator, nothing more.
        return []
    }

    // MARK: - InjectableError

    private enum InjectableError: Error, CustomStringConvertible {
        case notDecoratingBinding
        case decoratingStatic

        var description: String {
            switch self {
            case .notDecoratingBinding:
                return "This macro must decorate a instance variable"
            case .decoratingStatic:
                return "This macro can not decorate `static` variables"
            }
        }
    }
}
