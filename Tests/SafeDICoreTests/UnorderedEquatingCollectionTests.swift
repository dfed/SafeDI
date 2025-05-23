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

import Foundation
import Testing

@testable import SafeDICore

struct UnorderedEquatingCollectionTests {
	@Test
	func makeIterator_iteratesInOrder() {
		for (index, value) in UnorderedEquatingCollection([1, 2, 3]).enumerated() {
			if index == 0 {
				#expect(value == 1)
			} else if index == 1 {
				#expect(value == 2)
			} else {
				#expect(index == 2)
				#expect(value == 3)
			}
		}
	}

	@Test
	func hashInto_hashesEquivalentCollectionsIdentically() {
		#expect(UnorderedEquatingCollection([1, 2, 3]).hashValue == UnorderedEquatingCollection([2, 1, 3]).hashValue)
	}

	@Test
	func codable_canDecodeFromEncodedValue() throws {
		let originalCollection = UnorderedEquatingCollection([1, 2, 3])
		let decodedCollection = try JSONDecoder().decode(
			UnorderedEquatingCollection<Int>.self,
			from: JSONEncoder().encode(originalCollection)
		)
		#expect(originalCollection == decodedCollection)
	}
}
