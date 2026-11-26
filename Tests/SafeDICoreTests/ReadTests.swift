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

import Testing
@testable import SafeDICore

struct ReadTests {
	@Test
	func description_namesChannelAndLabel_forEveryChannel() {
		let labels = ["a", "b", "c", "d", "e", "f", "g"]
		let reads = [
			Read(.value, label: 0), Read(.optional, label: 1), Read(.alias, label: 2), Read(.madeAgain, label: 3), Read(.mock, label: 4),
			Read(.carrier, label: 5), Read(.fill, label: 6), Read(.family), Read(.override),
		]

		#expect(reads.map { $0.description(labels: labels) } == ["value(a)", "optional(b)", "alias(c)", "madeAgain(d)", "mock(e)", "carrier(f)", "fill(g)", "family", "override"])
	}
}
