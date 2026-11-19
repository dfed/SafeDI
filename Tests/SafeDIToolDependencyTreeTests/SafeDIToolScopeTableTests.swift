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
		// Two concrete types are each held by two scopes of the mock map. `SystemClock` is built by `init` under `SystemClock`
		// and by its hand-written mock, which leaves out the dependency the mock is not passed, under `Clock`, which the mock
		// returns. `SystemTimer` is built by `init` under `SystemTimer` and by the `mockOnly` mock merged into it, under
		// `Ticker`, which that mock returns. A third scope of one type would need a second hand-written mock of it, which
		// `generate` rejects ("Found multiple hand-written mocks"). Each run builds every scope afresh, at new addresses, and
		// takes the map's entries in another order; every run freezes the same tables. The first table is the production
		// map's, which holds no root.
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

	private static let clocks = """
	public protocol Clock {}
	public protocol Ticker {}

	@Instantiable(fulfillingAdditionalTypes: [Clock.self], customMockName: "customMock")
	public final class SystemClock: Clock, Instantiable {
		public init(zone: Zone) {
			self.zone = zone
		}

		public static func customMock() -> Clock {
			SystemClock(zone: Zone())
		}

		@Instantiated let zone: Zone
	}

	@Instantiable
	public final class SystemTimer: Clock, Ticker, Instantiable {
		public init(zone: Zone) {
			self.zone = zone
		}

		@Instantiated let zone: Zone
	}

	@Instantiable(fulfillingAdditionalTypes: [Ticker.self], mockOnly: true, customMockName: "fakeTicker")
	extension SystemTimer {
		public static func fakeTicker() -> Ticker {
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
		public init(clock: Clock, systemClock: SystemClock, systemTimer: SystemTimer, ticker: Ticker) {
			self.clock = clock
			self.systemClock = systemClock
			self.systemTimer = systemTimer
			self.ticker = ticker
		}

		@Instantiated let clock: Clock
		@Instantiated let systemClock: SystemClock
		@Instantiated let systemTimer: SystemTimer
		@Instantiated let ticker: Ticker
	}
	"""
}
