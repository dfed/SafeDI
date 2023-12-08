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

/// A visitor that can read entire files. A single `FileVisitor` can be used to walk every file in a module.
public final class FileVisitor: SyntaxVisitor {

    // MARK: Initialization

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: SyntaxVisitor

    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
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

    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declSyntaxParentCount += 1
        return .visitChildren // Make sure there aren't `@Instantiable`s declared within an enum.
    }

    public override func visitPost(_ node: EnumDeclSyntax) {
        declSyntaxParentCount -= 1
    }

    // MARK: Public

    public var instantiables = [Instantiable]()
    public var nestedInstantiableDecoratedTypeDescriptions = [TypeDescription]()

    // MARK: Private

    private var declSyntaxParentCount = 0

    private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
        // TODO: Allow Instantiable to be nested types. Accomplishing this task will require understanding when other nested types are being referenced.
        defer { declSyntaxParentCount += 1 }
        guard declSyntaxParentCount == 0 else {
            let instantiableVisitor = InstantiableVisitor()
            instantiableVisitor.walk(node)
            if let instantiableType = instantiableVisitor.instantiableType {
                nestedInstantiableDecoratedTypeDescriptions.append(instantiableType)
            }
            return .visitChildren
        }

        let instantiableVisitor = InstantiableVisitor()
        instantiableVisitor.walk(node)
        if let instantiable = instantiableVisitor.instantiable {
            instantiables.append(instantiable)
        }

        // Find nested Instantiable types.
        return .visitChildren
    }

    private func visitPostDecl(_ node: some ConcreteDeclSyntaxProtocol) {
        declSyntaxParentCount -= 1
    }
}
