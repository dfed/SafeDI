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

extension Collection<Dependency> {
    var initializerFunctionParameters: [FunctionParameterSyntax] {
        map(\.property)
            .initializerFunctionParameters
    }
}

extension Collection<Property> {
    public var asTuple: TupleTypeSyntax {
        let tupleElements = sorted()
            .map(\.asTupleElement)
            .transformUntilLast {
                var node = $0
                node.trailingComma = .commaToken(trailingTrivia: .space)
                return node
            }
        var tuple = TupleTypeSyntax(elements: TupleTypeElementListSyntax())
        for element in tupleElements {
            tuple.elements.append(element)
        }
        return tuple
    }

    var asTupleTypeDescription: TypeDescription {
        TypeSyntax(asTuple).typeDescription
    }

    var initializerFunctionParameters: [FunctionParameterSyntax] {
        map(\.asFunctionParamter)
            .transformUntilLast {
                var node = $0
                node.trailingComma = .commaToken(trailingTrivia: .space)
                return node
            }
    }
}

extension Collection {
    private func transformUntilLast(_ transform: (Element) throws -> Element) rethrows -> [Element] {
        var arrayToTransform = Array(self)
        guard let lastItem = arrayToTransform.popLast() else {
            // Array is empty.
            return []
        }
        return try arrayToTransform.map { try transform($0) } + [lastItem]
    }
}

extension Collection<String> {
    public func removingEmpty() -> [Element] {
        filter { !$0.isEmpty }
    }
}
