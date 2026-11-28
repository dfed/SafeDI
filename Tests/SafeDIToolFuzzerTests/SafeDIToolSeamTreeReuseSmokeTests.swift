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
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

struct SafeDIToolSeamTreeReuseSmokeTests {
	/// Every run through the test executors compares each reused seam tree with one built anew (`ReusedSeamTreeChecks`);
	/// this test makes that check non-vacuous over the seam smoke seeds: the tool reuses trees there, of seams with holes
	/// among them.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_reusesTreesOfSeamsWithHoles_whenSeamSmokeSeedsRun() async throws {
		let (stream, continuation) = AsyncStream.makeStream(of: ReusedSeamTree.self)
		try await SeamTreeReuseObservation.$comparesBuiltTrees.withValue(TaskLocalFunction { continuation.yield($0) }) {
			for seed in SafeDIToolGraphFuzzerTests.seamSmokeSeeds {
				let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
				_ = try await GraphFuzzerOracle.toolOutcome(of: fixture)
			}
		}
		continuation.finish()
		var reusedTreeCount = 0
		var reusedTreesOfSeamsWithHolesCount = 0
		for await reusedTree in stream {
			reusedTreeCount += 1
			if reusedTree.signature.signature?.holes.isEmpty == false {
				reusedTreesOfSeamsWithHolesCount += 1
			}
		}
		#expect(reusedTreeCount > 0)
		#expect(reusedTreesOfSeamsWithHolesCount > 0)
	}
}
