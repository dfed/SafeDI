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

import SwiftSyntax

public protocol ConcreteDeclSyntaxProtocol: SyntaxProtocol {
    var attributes: AttributeListSyntax { get set }
    var modifiers: DeclModifierListSyntax { get set }
    var inheritanceClause: InheritanceClauseSyntax? { get set }
    var keyword: TokenSyntax { get set }
    var name: TokenSyntax { get set }
    var declType: ConcreteDeclType { get }
}

extension ActorDeclSyntax: ConcreteDeclSyntaxProtocol {
    public var keyword: SwiftSyntax.TokenSyntax {
        get {
            actorKeyword
        }
        set {
            actorKeyword = newValue
        }
    }

    public var declType: ConcreteDeclType { .actorType }
}

extension ClassDeclSyntax: ConcreteDeclSyntaxProtocol {
    public var keyword: SwiftSyntax.TokenSyntax {
        get {
            classKeyword
        }
        set {
            classKeyword = newValue
        }
    }

    public var declType: ConcreteDeclType { .classType }
}

extension StructDeclSyntax: ConcreteDeclSyntaxProtocol {
    public var keyword: SwiftSyntax.TokenSyntax {
        get {
            structKeyword
        }
        set {
            structKeyword = newValue
        }
    }

    public var declType: ConcreteDeclType { .structType }
}
