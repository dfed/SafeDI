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
import SwiftSyntaxBuilder

extension Array where Element == Dependency {

    var variantUnlabeledParameterList: FunctionParameterListSyntax {
        FunctionParameterListSyntax(
            filter { $0.source == .variant }
                .map { "\(raw: $0.property.type)" }
                .transformUntilLast {
                    var functionPamameterSyntax = $0
                    functionPamameterSyntax.trailingComma = TokenSyntax(.comma, presence: .present)
                    functionPamameterSyntax.trailingTrivia = .space
                    return functionPamameterSyntax
                }
        )
    }

    var variantParameterList: FunctionParameterListSyntax {
        FunctionParameterListSyntax(
            filter { $0.source == .variant }
                .map { "\(raw: $0.property.label): \(raw: $0.property.type)" }
                .transformUntilLast {
                    var functionPamameterSyntax = $0
                    functionPamameterSyntax.trailingComma = TokenSyntax(.comma, presence: .present)
                    functionPamameterSyntax.trailingTrivia = .space
                    return functionPamameterSyntax
                }
        )
    }

    var variantUnlabeledExpressionList: String {
        filter { $0.isVariant }
            .map { "\($0.property.label)" }
            .joined(separator: ", ")
    }

    var variantLabeledExpressionList: String {
        filter { $0.isVariant }
            .map { "\($0.property.label): \($0.property.label)" }
            .joined(separator: ", ")
    }

    var invariantParameterList: FunctionParameterListSyntax {
        FunctionParameterListSyntax(
            filter { $0.isInvariant }
                .map { "\(raw: $0.property.label): \(raw: $0.property.type)" }
                .transformUntilLast {
                    var functionPamameterSyntax = $0
                    functionPamameterSyntax.trailingComma = TokenSyntax(.comma, presence: .present)
                    functionPamameterSyntax.trailingTrivia = .space
                    return functionPamameterSyntax
                }
        )
    }

    var invariantAssignmentExpressionList: String {
        """
        \(filter(\.isInvariant)
        .map { "self.\($0.property.label) = \($0.property.label)" }
        .joined(separator: "\n"))
        """
    }

}

extension Array {
    
    /// Returns an array with all of the items in the array except for the last transformed.
    /// - Parameter transform: A transforming closure. `transform` accepts an element of this sequence as its parameter and returns a transformed value of the same type.
    /// - Returns: An array containing the transformed elements of this sequence, plus the untransfomred last element.
    func transformUntilLast(_ transform: (Element) throws -> Element) rethrows -> [Element] {
        var arrayToTransform = self
        guard let lastItem = arrayToTransform.popLast() else {
            // Array is empty.
            return self
        }
        return try arrayToTransform.map { try transform($0) } + [lastItem]
    }
}
