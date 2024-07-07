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

    public override func visitPost(_ node: ClassDeclSyntax) {
        visitPostDecl(node)
    }

    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visitPost(_ node: ActorDeclSyntax) {
        visitPostDecl(node)
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDecl(node)
    }

    public override func visitPost(_ node: StructDeclSyntax) {
        visitPostDecl(node)
    }

    public override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declSyntaxParentCount += 1
        return .visitChildren // Make sure there aren't `@Instantiable`s declared within an enum.
    }

    public override func visitPost(_: EnumDeclSyntax) {
        declSyntaxParentCount -= 1
    }

    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let instantiableVisitor = InstantiableVisitor(declarationType: .extensionDecl)
        instantiableVisitor.walk(node)
        for instantiable in instantiableVisitor.instantiables {
            instantiables.append(instantiable)
        }

        return .skipChildren
    }

    // MARK: Public

    public private(set) var imports = [ImportStatement]()
    public private(set) var instantiables = [Instantiable]()
    public private(set) var nestedInstantiableDecoratedTypeDescriptions = [TypeDescription]()

    // MARK: Private

    private var declSyntaxParentCount = 0

    private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
        // TODO: Allow Instantiable to be nested types. Accomplishing this task will require understanding when other nested types are being referenced.
        defer { declSyntaxParentCount += 1 }
        guard declSyntaxParentCount == 0 else {
            let instantiableVisitor = InstantiableVisitor(declarationType: .concreteDecl)
            instantiableVisitor.walk(node)
            if let instantiableType = instantiableVisitor.instantiableType {
                nestedInstantiableDecoratedTypeDescriptions.append(instantiableType)
            }
            return .visitChildren
        }

        let instantiableVisitor = InstantiableVisitor(declarationType: .concreteDecl)
        instantiableVisitor.walk(node)
        for instantiable in instantiableVisitor.instantiables {
            instantiables.append(instantiable)
        }

        // Find nested Instantiable types.
        return .visitChildren
    }

    private func visitPostDecl(_: some ConcreteDeclSyntaxProtocol) {
        declSyntaxParentCount -= 1
    }
}
