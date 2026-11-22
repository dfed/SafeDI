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

/// A chain of objects that each hold the next in a `DeferredReleaseSlot` is released one level at a time: releasing
/// one level from within the deinitializer of the level above would nest a deinitializer per level, which a chain this
/// deep overflows on any thread's stack.
struct DeferredReleaseSlotTests {
	@Test
	func deinit_releasesEveryLevelWithoutNesting_whenChainIsDeeperThanAnyStack() async {
		let deepestLinkIsReleased = await Task.detached {
			var chain = Link(next: [])
			weak var deepestLink = chain
			for _ in 0..<100_000 {
				chain = Link(next: [chain])
			}
			// Replacing the chain releases all of it on this concurrency thread.
			chain = Link(next: [])
			return deepestLink == nil
		}.value
		#expect(deepestLinkIsReleased)
	}

	@Test
	func value_returnsTheValuesTheSlotWasCreatedWith() {
		let first = Link(next: [])
		let second = Link(next: [])
		let link = Link(next: [first, second])
		#expect(link.next.count == 2)
		#expect(link.next.first === first)
		#expect(link.next.last === second)
	}

	private final class Link: Sendable {
		init(next: [Link]) {
			nextSlot = DeferredReleaseSlot(next)
		}

		var next: [Link] {
			nextSlot.value
		}

		private let nextSlot: DeferredReleaseSlot<[Link]>
	}
}
