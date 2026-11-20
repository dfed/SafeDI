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

/// The tables construction reads (`ScopeTable`): each map is frozen once, and the order of its records follows from what
/// the map holds, never from the order its entries arrive in.
struct SafeDIToolScopeTableTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freezesTheSameTables_whenMapEntriesArriveInAnyOrder() async throws {
		// Two concrete types are each held by two scopes of the mock map: each is built by `init` under its own type and by
		// the hand-written mock of the `mockOnly` extension merged into it, which leaves out the dependency the mock is not
		// passed, under the protocol that mock returns. A third scope of one type would need a second hand-written mock of it,
		// which `generate` rejects ("Found multiple hand-written mocks"). Each run builds every scope afresh, at new
		// addresses, and takes the map's entries in another order; every run freezes the same tables. The first table is the
		// production map's, which holds no root.
		var projectionsBySeed = [UInt64: [String]]()
		for seed in UInt64(1)...20 {
			let (stream, continuation) = AsyncStream.makeStream(of: String.self)
			try await ScopeTableObservation.$entryOrder.withValue({ entryCount in
				Self.shuffledPositions(count: entryCount, seed: seed)
			}) {
				try await ScopeTableObservation.$observer.withValue({ projection in
					continuation.yield(projection)
				}) {
					_ = try await executeSafeDIToolTest(
						swiftFileContent: [Self.clocks, Self.root],
						buildSwiftOutputDirectory: true,
						filesToDelete: &filesToDelete,
					)
				}
			}
			continuation.finish()
			var projections = [String]()
			for await projection in stream {
				projections.append(projection)
			}
			projectionsBySeed[seed] = projections
		}
		let firstProjections = try #require(projectionsBySeed[1])
		for seed in UInt64(2)...20 {
			#expect(projectionsBySeed[seed] == firstProjections, "seed \(seed)")
		}
		#expect(firstProjections == [
			"",
			"""
			0: Root keys [Root] clock -> 1 systemClock -> 2 systemTimer -> 3 ticker -> 4
			1: SystemClock keys [Clock]
			2: SystemClock keys [SystemClock] zone -> 5
			3: SystemTimer keys [SystemTimer] zone -> 5
			4: SystemTimer keys [Ticker]
			5: Zone keys [Zone]
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_overlaysOnlyTheCallsEachPassesSeamsReach_whenSeamsCallEachOtherInAChain() async throws {
		// Each seam calls the next through a type of its own tree. The pass map of the first seam's component holds the call
		// scopes of every seam after it, which the first seam's tree does not reach: only its own call of the second seam is
		// recorded again from the pass.
		let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
		try await ScopeTableObservation.$overlaidCallRecords.withValue({ calledTypes in
			continuation.yield(calledTypes)
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [Self.chain],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var overlaidCallRecords = [[String]]()
		for await calledTypes in stream {
			overlaidCallRecords.append(calledTypes)
		}
		#expect(overlaidCallRecords.sorted { $0.joined(separator: ",") < $1.joined(separator: ",") } == [
			[],
			["SecondSeam"],
			["ThirdSeam"],
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A permutation of `0..<count`, which `seed` decides alone (Fisher–Yates over SplitMix64).
	private static func shuffledPositions(count: Int, seed: UInt64) -> [Int] {
		var positions = Array(0..<count)
		var random = GraphFuzzerRandomNumberGenerator(seed: seed)
		for index in positions.indices.dropLast().reversed() {
			positions.swapAt(index, random.integer(in: index...(count - 1)))
		}
		return positions
	}

	private static let chain = """
	@Instantiable
	public final class Root: Instantiable {
		public init(firstSeam: FirstSeam) {
			self.firstSeam = firstSeam
		}

		@Instantiated let firstSeam: FirstSeam
	}

	@Instantiable(generateDependencyTree: true)
	public final class FirstSeam: Instantiable {
		public init(firstStep: FirstStep) {
			self.firstStep = firstStep
		}

		@Instantiated let firstStep: FirstStep
	}

	@Instantiable
	public final class FirstStep: Instantiable {
		public init(secondSeam: SecondSeam) {
			self.secondSeam = secondSeam
		}

		@Instantiated let secondSeam: SecondSeam
	}

	@Instantiable(generateDependencyTree: true)
	public final class SecondSeam: Instantiable {
		public init(secondStep: SecondStep) {
			self.secondStep = secondStep
		}

		@Instantiated let secondStep: SecondStep
	}

	@Instantiable
	public final class SecondStep: Instantiable {
		public init(thirdSeam: ThirdSeam) {
			self.thirdSeam = thirdSeam
		}

		@Instantiated let thirdSeam: ThirdSeam
	}

	@Instantiable(generateDependencyTree: true)
	public final class ThirdSeam: Instantiable {
		public init(leaf: Leaf) {
			self.leaf = leaf
		}

		@Instantiated let leaf: Leaf
	}

	@Instantiable
	public final class Leaf: Instantiable {
		public init() {}
	}
	"""

	private static let clocks = """
	public protocol Clock {}
	public protocol Ticker {}

	@Instantiable
	public final class SystemClock: Clock, Instantiable {
		public init(zone: Zone) {
			self.zone = zone
		}

		@Instantiated let zone: Zone
	}

	@Instantiable(fulfillingAdditionalTypes: [Clock.self], mockOnly: true, customMockName: "fakeClock")
	extension SystemClock {
		public static func fakeClock() -> any Clock {
			SystemClock(zone: Zone())
		}
	}

	@Instantiable
	public final class SystemTimer: Ticker, Instantiable {
		public init(zone: Zone) {
			self.zone = zone
		}

		@Instantiated let zone: Zone
	}

	@Instantiable(fulfillingAdditionalTypes: [Ticker.self], mockOnly: true, customMockName: "fakeTicker")
	extension SystemTimer {
		public static func fakeTicker() -> any Ticker {
			SystemTimer(zone: Zone())
		}
	}

	@Instantiable
	public final class Zone: Instantiable {
		public init() {}
	}
	"""

	private static let root = """
	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
		public init(clock: any Clock, systemClock: SystemClock, systemTimer: SystemTimer, ticker: any Ticker) {
			self.clock = clock
			self.systemClock = systemClock
			self.systemTimer = systemTimer
			self.ticker = ticker
		}

		@Instantiated let clock: any Clock
		@Instantiated let systemClock: SystemClock
		@Instantiated let systemTimer: SystemTimer
		@Instantiated let ticker: any Ticker
	}
	"""
}
