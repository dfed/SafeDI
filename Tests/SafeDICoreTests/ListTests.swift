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

    func test_nonEmptyInit_createsListFromCollection() throws {
        XCTAssertEqual(
            try XCTUnwrap(List([1, 2, 3, 4, 5])).map(\.value),
            [1, 2, 3, 4, 5]
        )
    }

    func test_insert_onFirstElementInList_insertsElementAfterFirstElement() throws {
        let systemUnderTest = try XCTUnwrap(List([1, 3, 4, 5]))
        systemUnderTest.insert(2)
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 4, 5]
        )
    }

    func test_insert_onLaterItemsInList_insertsElementAfterCurrentElement() {
        let systemUnderTest = List(value: 1)
        var last = systemUnderTest.insert(2)
        last = last.insert(3)
        last = last.insert(4)
        last = last.insert(5)
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 4, 5]
        )
    }

    func test_remove_onFirstElementInList_removesFirstElementAndReturnsNewFirstElement() throws {
        let systemUnderTest = try XCTUnwrap(List([1, 2, 3, 4, 5]))
        XCTAssertEqual(
            systemUnderTest.remove()?.map(\.value),
            [2, 3, 4, 5]
        )
    }

    func test_remove_onItemThatWasInsertedAfterListCreation_removesItem() {
        let systemUnderTest = List(value: 1)
        let two = systemUnderTest.insert(2)
        let four = two.insert(4)
        four.insert(5)
        two.insert(3).remove()

        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 4, 5]
        )
    }

    func test_remove_onItemBeforeItemInsertedAfterListCreation_removesItem() {
        let systemUnderTest = List(value: 1)
        let two = systemUnderTest.insert(2)
        let four = two.insert(4)
        four.insert(5)
        two.insert(3)
        two.remove()

        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 3, 4, 5]
        )
    }

    func test_remove_onItemAfterItemInsertedAfterListCreation_removesItem() {
        let systemUnderTest = List(value: 1)
        let two = systemUnderTest.insert(2)
        let four = two.insert(4)
        four.insert(5)
        two.insert(3)
        four.remove()

        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 5]
        )
    }

    func test_remove_onLaterItemsInList_removesElementAndReturnsNil() {
        let systemUnderTest = List(value: 1)
        let two = systemUnderTest.insert(2)
        let three = two.insert(3)
        let four = three.insert(4)
        four.insert(5)
        XCTAssertNil(four.remove())
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 5]
        )
    }

    func test_remove_onLastInList_removesElement() throws {
        let systemUnderTest = try XCTUnwrap(List([1, 2, 3, 4]))
        let lastElement = systemUnderTest.insert(5)
        lastElement.remove()
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 4]
        )
    }

    func test_insert_andThenRemoveItemBeforeInsertion_insertsAndThenRemoves() {
        let systemUnderTest = List(value: 1)
        let two = systemUnderTest.insert(2)
        let three = two.insert(3)
        let four = three.insert(4)
        let secondFour = four.insert(4)
        secondFour.insert(5)
        four.remove()
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 4, 5]
        )
    }

    func test_insert_andThenRemoveItem_insertsAndThenRemoves() {
        let systemUnderTest = List(value: 1)
        let two = systemUnderTest.insert(2)
        let three = two.insert(3)
        let four = three.insert(4)
        four.remove()
        three.insert(5)
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 5]
        )
    }

    func test_insert_andThenRemoveItemAfterInsertion_insertsAndThenRemoves() {
        let systemUnderTest = List(value: 1)
        let two = systemUnderTest.insert(2)
        let three = two.insert(3)
        let four = three.insert(4)
        four.insert(5)
        four.remove()
        three.insert(4)
        XCTAssertEqual(
            systemUnderTest.map(\.value),
            [1, 2, 3, 4, 5]
        )
    }
}
