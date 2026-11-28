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

/// A place's construction log refers to the frozen segment of each place beneath it, so the segments of a chain of places
/// form a chain as deep as the tree. Releasing one segment from within the deinitializer of the segment above would nest
/// a deinitializer per level, which a chain this deep overflows on a thread of half a megabyte, the stack of a secondary
/// thread and a concurrency thread on Apple platforms.
struct ConstructionLogReleaseTests {
	@Test
	func deinit_releasesEverySegmentWithoutNesting_whenChainOfSegmentsOutgrowsHalfMegabyteStack() async {
		let (elementCountsKept, continuation) = AsyncStream.makeStream(of: Int.self)
		await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
			let thread = Thread {
				ConstructionLogStorage.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
					// Every read is answered above the tree, so each place keeps all of them, more than a copied run holds,
					// and freezes its log into a segment that refers to the segment of the place beneath. Each place reads a
					// label of its own first, so telling its log from a copied run reads only the places nearest it.
					var log = ConstructionLog()
					for index in 0..<33 {
						log.record(.nearestDeclaration("label\(index)"), answer: .nearestDeclaration(nil), depth: -1)
					}
					for depth in (0..<Self.chainDepth).reversed() {
						var parentLog = ConstructionLog()
						parentLog.record(.nearestDeclaration("place\(depth)"), answer: .nearestDeclaration(nil), depth: -1)
						parentLog.formUnion(log.reads(answeredAbove: depth))
						log = parentLog
					}
					// Replacing the chain releases all of it on this thread.
					log = ConstructionLog()
				}
				continuation.finish()
				finished.resume()
			}
			thread.stackSize = 512 * 1_024
			thread.start()
		}
		var elementCounts = [Int: Int]()
		for await elementCount in elementCountsKept {
			elementCounts[elementCount, default: 0] += 1
		}
		// The deepest place froze the 33 reads; every place above kept its own read and one segment that refers to the one
		// beneath, never a copy of the reads.
		#expect(elementCounts == [33: 1, 2: Self.chainDepth - 1])
	}

	private static let chainDepth = 10_000
}
