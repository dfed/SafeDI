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

/// A syntax visitor that can read an entire file.
public final class FileVisitor: SyntaxVisitor {
    // MARK: Initialization

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        imports.append(node.asImportStatement)
        return .skipChildren
    }

    public override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visitPost(_: ClassDeclSyntax) {
        exitType()
    }

    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visitPost(_: ActorDeclSyntax) {
        exitType()
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visitPost(_: StructDeclSyntax) {
        exitType()
    }

    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        // Enums can't be instantiable because they can't have `let` properties.
        // However, they can have nested types within them that are instantiable.
        enterTypeNamed(node.name.text)
        return .visitChildren
    }

    public override func visitPost(_: EnumDeclSyntax) {
        exitType()
    }

    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let instantiableVisitor = InstantiableVisitor(
            declarationType: .extensionDecl,
            parentType: nil
        )
        instantiableVisitor.walk(node)
        for instantiable in instantiableVisitor.instantiables {
            instantiables.append(instantiable)
        }

        // Extensions are always top-level.
        parentType = node.extendedType.typeDescription

        // Continue to find child types.
        return .visitChildren
    }

    public override func visitPost(_: ExtensionDeclSyntax) {
        // Extensions are always top-level.
        parentType = nil
    }

    // MARK: Public

    public private(set) var imports = [ImportStatement]()
    public private(set) var instantiables = [Instantiable]()

    // MARK: Private

    private var parentType: TypeDescription?

    private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
        let instantiableVisitor = InstantiableVisitor(
            declarationType: .concreteDecl,
            parentType: parentType
        )
        instantiableVisitor.walk(node)
        for instantiable in instantiableVisitor.instantiables {
            instantiables.append(instantiable)
        }

        // Keep track of how nested we are.
        enterTypeNamed(node.name.text)

        // Continue to find child types.
        return .visitChildren
    }

    private func enterTypeNamed(_ name: String) {
        if let parentType {
            self.parentType = .nested(name: name, parentType: parentType)
        } else {
            parentType = .simple(name: name)
        }
    }

    private func exitType() {
        parentType = parentType?.popNested
    }
}
