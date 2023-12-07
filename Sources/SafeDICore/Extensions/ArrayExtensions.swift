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

    var removingDuplicateInitializerArguments: Self {
        var alreadySeenInitializerArgument = Set<Property>()
        return filter {
            let initializerArgument = $0.asInitializerArgument
            if alreadySeenInitializerArgument.contains(initializerArgument) {
                return false
            } else {
                alreadySeenInitializerArgument.insert(initializerArgument)
                return true
            }
        }
    }

    var initializerFunctionParameters: [FunctionParameterSyntax] {
        removingDuplicateInitializerArguments
            .map { $0.asInitializerArgument.asFunctionParamter }
            .transformUntilLast {
                var node = $0
                node.trailingComma = .commaToken(trailingTrivia: .space)
                return node
            }
    }
}

extension Array {
    fileprivate func transformUntilLast(_ transform: (Element) throws -> Element) rethrows -> [Element] {
        var arrayToTransform = self
        guard let lastItem = arrayToTransform.popLast() else {
            // Array is empty.
            return self
        }
        return try arrayToTransform.map { try transform($0) } + [lastItem]
    }
}
