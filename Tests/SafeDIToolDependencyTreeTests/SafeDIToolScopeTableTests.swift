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
			try await ScopeTableObservation.$entryOrder.withValue(TaskLocalFunction { entryCount in
				Self.shuffledPositions(count: entryCount, seed: seed)
			}) {
				try await ScopeTableObservation.$observer.withValue(TaskLocalFunction { projection in
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
		try await ScopeTableObservation.$overlaidCallRecords.withValue(TaskLocalFunction { calledTypes in
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assemblesTheSamePassTables_whenPassMapEntriesArriveInAnyOrder() async throws {
		// Each seam pass overlays its own map on the base table, and every scope of its map is held under two keys, its own
		// type and the protocol it also fulfills. Each run builds every scope afresh and takes each map's entries, the pass
		// maps' included, in another order; every run freezes and assembles the same tables.
		var projectionsBySeed = [UInt64: [String]]()
		for seed in UInt64(1)...20 {
			let (stream, continuation) = AsyncStream.makeStream(of: String.self)
			try await ScopeTableObservation.$entryOrder.withValue(TaskLocalFunction { entryCount in
				Self.shuffledPositions(count: entryCount, seed: seed)
			}) {
				try await ScopeTableObservation.$observer.withValue(TaskLocalFunction { projection in
					continuation.yield(projection)
				}) {
					_ = try await executeSafeDIToolTest(
						swiftFileContent: [Self.twoKeyedChain],
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
			projectionsBySeed[seed] = projections.sorted()
		}
		let firstProjections = try #require(projectionsBySeed[1])
		#expect(firstProjections.count > 2)
		for seed in UInt64(2)...20 {
			#expect(projectionsBySeed[seed] == firstProjections, "seed \(seed)")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_freezesHolesAliasesAndFills_whenRootFillsHoleOfSeamInAnotherModule() async throws {
		// `Hub`, a seam of `Feature`, instantiates `api: any Api`, which nothing in `Feature` fulfills, so its tree holds a
		// hole there. `App`'s `Root` builds `Hub`, whose call fills the hole with `LiveApi`, and renames `hub`. Each table
		// spells every kind of property a record holds, and the fill of a call.
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		try await ScopeTableObservation.$observer.withValue(TaskLocalFunction { projection in
			continuation.yield(projection)
		}) {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.hub]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.app], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var projections = [String]()
		for await projection in stream {
			projections.append(projection)
		}
		// `Feature` freezes its maps and overlays each seam signature pass on them; `App` freezes its validated map and its
		// seam map, in which `Hub` is a call that fills its hole. Compared as a set: which tables are made is this test's
		// subject, not how many times each is made, which follows how many maps and signature passes a run freezes (a run
		// that reads another module's seam signatures from its module info makes no pass of its own over them).
		#expect(Set(projections) == [
			"0: Hub keys [Hub]",
			"0: Hub keys [Hub] api -> 1\n1: LiveApi keys [Api, LiveApi]\n2: Root keys [Root] hub -> 0 renamedHub = hub",
			"0: Hub keys [Hub] api -> hole",
			"0: Hub keys [Hub] fill api -> 1\n1: LiveApi keys [Api, LiveApi]\n2: Root keys [Root] hub -> 0 renamedHub = hub",
		])
	}

	/// A permutation of `0..<count`, which `seed` decides alone (Fisher–Yates over SplitMix64).
	private static func shuffledPositions(count: Int, seed: UInt64) -> [Int] {
		var positions = Array(0..<count)
		var random = GraphFuzzerRandomNumberGenerator(seed: seed)
		for index in positions.indices.dropLast().reversed() {
			positions.swapAt(index, random.integer(in: index...(count - 1)))
		}
		return positions
	}

	private static let hub = """
	public protocol Api {}

	@Instantiable(generateDependencyTree: true)
	public final class Hub: Instantiable {
		public init(api: any Api) {
			self.api = api
		}

		@Instantiated let api: any Api
	}
	"""

	private static let app = """
	import Feature

	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class LiveApi: Api, Instantiable {
		public init() {}
	}

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
		public init(hub: Hub, renamedHub: Hub) {
			self.hub = hub
			self.renamedHub = renamedHub
		}

		@Instantiated let hub: Hub
		@Received(fulfilledByDependencyNamed: "hub", ofType: Hub.self) let renamedHub: Hub
	}
	"""

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

	private static let twoKeyedChain = """
	@Instantiable
	public final class Root: Instantiable {
		public init(firstSeam: FirstSeam) {
			self.firstSeam = firstSeam
		}

		@Instantiated let firstSeam: FirstSeam
	}

	public protocol FirstSeamProtocol {}

	@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [FirstSeamProtocol.self])
	public final class FirstSeam: FirstSeamProtocol, Instantiable {
		public init(alpha: Alpha, bravo: Bravo, charlie: Charlie, delta: Delta, echo: Echo, secondSeam: SecondSeam) {
			self.alpha = alpha
			self.bravo = bravo
			self.charlie = charlie
			self.delta = delta
			self.echo = echo
			self.secondSeam = secondSeam
		}

		@Instantiated let alpha: Alpha
		@Instantiated let bravo: Bravo
		@Instantiated let charlie: Charlie
		@Instantiated let delta: Delta
		@Instantiated let echo: Echo
		@Instantiated let secondSeam: SecondSeam
	}

	public protocol SecondSeamProtocol {}

	@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [SecondSeamProtocol.self])
	public final class SecondSeam: SecondSeamProtocol, Instantiable {
		public init(foxtrot: Foxtrot, golf: Golf, hotel: Hotel, india: India, juliet: Juliet) {
			self.foxtrot = foxtrot
			self.golf = golf
			self.hotel = hotel
			self.india = india
			self.juliet = juliet
		}

		@Instantiated let foxtrot: Foxtrot
		@Instantiated let golf: Golf
		@Instantiated let hotel: Hotel
		@Instantiated let india: India
		@Instantiated let juliet: Juliet
	}

	public protocol AlphaProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [AlphaProtocol.self])
	public final class Alpha: AlphaProtocol, Instantiable {
		public init() {}
	}

	public protocol BravoProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [BravoProtocol.self])
	public final class Bravo: BravoProtocol, Instantiable {
		public init() {}
	}

	public protocol CharlieProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [CharlieProtocol.self])
	public final class Charlie: CharlieProtocol, Instantiable {
		public init() {}
	}

	public protocol DeltaProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [DeltaProtocol.self])
	public final class Delta: DeltaProtocol, Instantiable {
		public init() {}
	}

	public protocol EchoProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [EchoProtocol.self])
	public final class Echo: EchoProtocol, Instantiable {
		public init() {}
	}

	public protocol FoxtrotProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [FoxtrotProtocol.self])
	public final class Foxtrot: FoxtrotProtocol, Instantiable {
		public init() {}
	}

	public protocol GolfProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [GolfProtocol.self])
	public final class Golf: GolfProtocol, Instantiable {
		public init() {}
	}

	public protocol HotelProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [HotelProtocol.self])
	public final class Hotel: HotelProtocol, Instantiable {
		public init() {}
	}

	public protocol IndiaProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [IndiaProtocol.self])
	public final class India: IndiaProtocol, Instantiable {
		public init() {}
	}

	public protocol JulietProtocol {}

	@Instantiable(fulfillingAdditionalTypes: [JulietProtocol.self])
	public final class Juliet: JulietProtocol, Instantiable {
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
