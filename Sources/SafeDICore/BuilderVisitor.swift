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

public final class BuilderVisitor: SyntaxVisitor {

    // MARK: Initialization

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
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
            error: FixableBuilderError.unexpectedVariableDeclaration,
            changes: [
                .replace(
                    oldNode: greatGrandparent,
                    newNode: Syntax(modifiedGreatGrandparent)
                )
            ]
        ))
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
            error: FixableBuilderError.unexpectedInitializer,
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
            error: FixableBuilderError.unexpectedFuncationDeclaration,
            changes: [
                .replace(
                    oldNode: greatGrandparent,
                    newNode: Syntax(modifiedGreatGrandparent)
                )
            ]
        ))
        return .skipChildren
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == DependenciesVisitor.decoratedStructName {
            didFindDependencies = true
            dependenciesVisitor.walk(node)
        }
        return .skipChildren
    }

    // MARK: Public

    public var dependencies: [Dependency] {
        dependenciesVisitor.dependencies
    }
    public var builtType: String? {
        dependenciesVisitor.builtType
    }
    public private(set) var didFindDependencies = false
    public private(set) var diagnostics = [Diagnostic]()

    public static let macroName = "builder"
    public static let decoratedStructName = "Builder"
    public static let getDependenciesClosureName = "getDependencies"

    // MARK: Private

    private let dependenciesVisitor = DependenciesVisitor()
}
