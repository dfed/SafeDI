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

@testable import SafeDICore

final class ListTests: XCTestCase {
    func test_insert_onFirstElementInList_insertsElementAfterFirstElement() {
        let systemUnderTest = List(1)
        systemUnderTest.insert(2)
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2]
        )
    }

    func test_insert_onLaterItemsInList_insertsElementAfterCurrentElement() {
        let systemUnderTest = List(1)
        var last = systemUnderTest.insert(2)
        last = last.insert(3)
        last = last.insert(4)
        last = last.insert(5)
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 4, 5]
        )
    }

    func test_prepend_insertsElementBeforeCurrentElementAndReturnsCurrentElement() {
        let systemUnderTest = List(1)
        XCTAssertEqual(
            systemUnderTest.prepend(0).map(\.value),
            [0, 1]
        )
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1]
        )
    }
}
