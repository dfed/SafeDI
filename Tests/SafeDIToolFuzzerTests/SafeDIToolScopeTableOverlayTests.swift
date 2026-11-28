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
import Synchronization
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The overlay oracle: a seam signature pass's table, assembled from the base frozen once per declaration map and the
/// records of the seams the pass calls, gives every key of the pass's map the record frozen from that map, and no record
/// to a key outside it.
///
/// With `ScopeTable.id(forKey:)` answering from the base for a key outside the pass's map, every smoke seed fails, seed 0
/// first. The fill lookup in `FrozenScopeMap.overlaying` reads through that one function, but the mask cannot change its
/// answer on input SafeDI accepts: a pass's reachable types follow every `@Instantiated` dependency, a hole's own property
/// included, so the type that fills a hole of a call the pass makes is in the pass's map. With that lookup alone reading
/// the base unmasked, none of the seam corpus's seeds 0..<2000 fails.
struct SafeDIToolScopeTableOverlayTests {
	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
	func generate_assemblesEveryPassTableAsItsOwnMapFreezes_whenRunOverSeamSmokeSeeds() async throws {
		let passCount = Mutex(0)
		let mismatchesBySeed = Mutex([UInt64: [String]]())
		for seed in SafeDIToolGraphFuzzerTests.seamSmokeSeeds {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
			try await ScopeTableObservation.$overlayOracle.withValue(TaskLocalFunction { mismatches in
				passCount.withLock { $0 += 1 }
				if !mismatches.isEmpty {
					mismatchesBySeed.withLock { $0[seed, default: []].append(contentsOf: mismatches) }
				}
			}) {
				_ = try await GraphFuzzerOracle.toolOutcome(of: fixture)
			}
		}
		#expect(mismatchesBySeed.withLock { $0 } == [:])
		#expect(passCount.withLock { $0 } > 0)
	}
}
