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

/// A representation of a property.
/// e.g. `let myProperty: MyProperty`
public struct Property: Codable, Hashable {

    // MARK: Initialization

    init(
        label: String,
        typeDescription: TypeDescription)
    {
        self.label = label
        self.typeDescription = typeDescription
    }

    // MARK: Public

    /// The label by which the property is referenced.
    public let label: String
    /// The type to which the property conforms.
    public var typeDescription: TypeDescription

    // MARK: Internal

    var asSource: String {
        "\(label): \(typeDescription.asSource)"
    }

    var asFunctionParamter: FunctionParameterSyntax {
        FunctionParameterSyntax(
            firstName: .identifier(label),
            colon: .colonToken(trailingTrivia: .space),
            type: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource))
        )
    }

    var asNamedTupleTypeElement: TupleTypeElementSyntax {
        TupleTypeElementSyntax(
            firstName: .identifier(label),
            colon: .colonToken(trailingTrivia: .space),
            type: IdentifierTypeSyntax(
                name: .identifier(typeDescription.asSource)
            )
        )
    }

    var asUnnamedTupleTypeElement: TupleTypeElementSyntax {
        TupleTypeElementSyntax(
            type: IdentifierTypeSyntax(
                name: .identifier(typeDescription.asSource)
            )
        )
    }

    var asUnnamedLabeledExpr: LabeledExprSyntax {
        LabeledExprSyntax(
            expression: DeclReferenceExprSyntax(
                baseName: .identifier(label)
            )
        )
    }
}
