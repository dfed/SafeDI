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

import XCTest

@testable import SafeDI

final class InstantiatorTests: XCTestCase {
    @MainActor
    func test_instantiate_returnsNewObjectEachTime() {
        let systemUnderTest = Instantiator() { BuiltProduct() }
        let firstBuiltProduct = systemUnderTest.instantiate()
        let secondBuiltProduct = systemUnderTest.instantiate()
        XCTAssertNotEqual(firstBuiltProduct, secondBuiltProduct)
    }

    @MainActor
    func test_instantiate_withForwardedArgument_returnsNewObjectEachTime() {
        let systemUnderTest = Instantiator() { id in BuiltProductWithForwardedArgument(id: id) }
        let firstBuiltProduct = systemUnderTest.instantiate("12345")
        let secondBuiltProduct = systemUnderTest.instantiate("54321")
        XCTAssertNotEqual(firstBuiltProduct, secondBuiltProduct)
    }

    private final class BuiltProduct: Equatable, Identifiable, Instantiable {
        static func == (lhs: BuiltProduct, rhs: BuiltProduct) -> Bool {
            lhs.id == rhs.id
        }

        let id = UUID().uuidString
    }

    private final class BuiltProductWithForwardedArgument: Equatable, Identifiable, Instantiable {
        init(id: String) {
            self.id = id
        }

        typealias ForwardedProperties = String

        static func == (lhs: BuiltProductWithForwardedArgument, rhs: BuiltProductWithForwardedArgument) -> Bool {
            lhs.id == rhs.id
        }

        @Forwarded
        let id: String
    }
}
