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

/// Sharing between a module's mock worlds (`MockWorldSharingObservation`): the records of the declarations several mock
/// roots reach are made once, as rows of one module-wide shared graph, and every world that reaches a row takes its one
/// record. Each test reads the report the mock worlds' pre-pass hands the observer, and every test requires that sharing
/// changes no record: each world's records with sharing equal the records of the same world built whole
/// (`MockWorldSharingReport.differences`).
///
/// These tests are the specification of the pre-pass: until it exists, each fails only because no report arrives.
struct SafeDIToolMockWorldSharingTests: ~Copyable {
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
	mutating func generate_buildsSharedSubtreeOnce_whenTwoMockRootsInstantiateIt() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct AlphaScreen: Instantiable {
					    public init(store: SessionStore) {
					        self.store = store
					    }

					    @Instantiated let store: SessionStore
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct BetaScreen: Instantiable {
					    public init(store: SessionStore) {
					        self.store = store
					    }

					    @Instantiated let store: SessionStore
					}
					""",
					"""
					@Instantiable
					public struct SessionStore: Instantiable {
					    public init(clock: Clock) {
					        self.clock = clock
					    }

					    @Instantiated let clock: Clock
					}
					""",
					"""
					@Instantiable
					public struct Clock: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `store` and `clock` are the same two declarations in both worlds: two rows, `store`'s record holding `clock`'s.
		// Each world takes `store`'s row and makes no record of its own, where built whole it makes both.
		#expect(report.printed == """
		rows:
		0: store: SessionStore, every parent the root
		1: clock: Clock
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 2
		BetaScreen: clean, own 0, shared 1, built whole 2
		differences:
		""")
	}

	@Test(arguments: [2, 4, 8])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSharedRecordsOnceAndOnlyTopRecordsPerWorld_whenMockRootsShareSubtree(rootCount: Int) async throws {
		var declarations = (0..<rootCount).map { index in
			"""
			@Instantiable(generateMock: true)
			public struct Screen\(index): Instantiable {
			    public init(shared: Shared) {
			        self.shared = shared
			    }

			    @Instantiated let shared: Shared
			}
			"""
		}
		declarations += [
			"""
			@Instantiable
			public struct Shared: Instantiable {
			    public init(first: First) {
			        self.first = first
			    }

			    @Instantiated let first: First
			}
			""",
			"""
			@Instantiable
			public struct First: Instantiable {
			    public init(second: Second) {
			        self.second = second
			    }

			    @Instantiated let second: Second
			}
			""",
			"""
			@Instantiable
			public struct Second: Instantiable {
			    public init(third: Third) {
			        self.third = third
			    }

			    @Instantiated let third: Third
			}
			""",
			"""
			@Instantiable
			public struct Third: Instantiable {
			    public init() {}
			}
			""",
		]
		let source = declarations.joined(separator: "\n\n")
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: ["Screens.swift": source],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// The work counted: the subtree's four records are made once for the run however many worlds share it, and each
		// world makes none of its own and takes one, while built whole each world makes all four, so the records made
		// without sharing grow with the roots and those made with it do not.
		#expect(report.rows.map(\.printed) == [
			"0: shared: Shared, every parent the root",
			"1: first: First",
			"2: second: Second",
			"3: third: Third",
		])
		#expect(report.worlds.map(\.printed) == (0..<rootCount).map { "Screen\($0): clean, own 0, shared 1, built whole 4" })
		#expect(report.rows.count + report.worlds.map(\.ownRecordCount).reduce(0, +) == 4)
		#expect(report.worlds.map(\.recordCountBuiltWhole).reduce(0, +) == 4 * rootCount)
		#expect(report.differences == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfLazyWrapper_whenSharedSubtreeInstantiatesLazily() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(session: LazilyInstantiated<Session>) {
					        self.session = session
					    }

					    @Instantiated let session: LazilyInstantiated<Session>
					}
					""",
					"""
					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: session: LazilyInstantiated<Session>
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 2
		BetaScreen: clean, own 0, shared 1, built whole 2
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfSendableInstantiator_whenSharedSubtreeInstantiatesSendableBuilder() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(tileBuilder: SendableInstantiator<Tile>) {
					        self.tileBuilder = tileBuilder
					    }

					    @Instantiated let tileBuilder: SendableInstantiator<Tile>
					}
					""",
					"""
					@Instantiable
					public struct Tile: Instantiable, Sendable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: tileBuilder: SendableInstantiator<Tile>
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 2
		BetaScreen: clean, own 0, shared 1, built whole 2
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfDefaultValuedParameter_whenSharedSubtreeBuildsTypeWithDefaultValuedParameter() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(leaf: Leaf) {
					        self.leaf = leaf
					    }

					    @Instantiated let leaf: Leaf
					}
					""",
					"""
					@Instantiable
					public struct Leaf: Instantiable {
					    public init(level: Int = 1) {
					        self.level = level
					    }

					    let level: Int
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// The default-valued parameter is a field of `leaf`'s configuration, the same in both worlds, so `leaf`'s record
		// reads no name of a root's.
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: leaf: Leaf
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 2
		BetaScreen: clean, own 0, shared 1, built whole 2
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfOnlyIfAvailableReceiver_whenSharedSubtreeReceivesOnlyIfAvailable() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(footer: Footer, badge: Badge) {
					        self.footer = footer
					        self.badge = badge
					    }

					    @Instantiated let footer: Footer
					    @Instantiated let badge: Badge
					}
					""",
					"""
					@Instantiable
					public struct Footer: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    public init(footer: Footer?) {
					        self.footer = footer
					    }

					    @Received(onlyIfAvailable: true) let footer: Footer?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: footer: Footer
		2: badge: Badge
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 3
		BetaScreen: clean, own 0, shared 1, built whole 3
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfOnlyIfAvailableLazyReceiver_whenSharedSubtreeReceivesLazyWrapperOnlyIfAvailable() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(session: LazilyInstantiated<Session>, badge: Badge) {
					        self.session = session
					        self.badge = badge
					    }

					    @Instantiated let session: LazilyInstantiated<Session>
					    @Instantiated let badge: Badge
					}
					""",
					"""
					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    public init(session: LazilyInstantiated<Session>?) {
					        self.session = session
					    }

					    @Received(onlyIfAvailable: true) let session: LazilyInstantiated<Session>?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: session: LazilyInstantiated<Session>
		2: badge: Badge
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 3
		BetaScreen: clean, own 0, shared 1, built whole 3
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfErasedProperty_whenSharedSubtreeInstantiatesErasedToConcreteExistential() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(leaf: AnyLeaf) {
					        self.leaf = leaf
					    }

					    @Instantiated(fulfilledByType: "Leaf", erasedToConcreteExistential: true) let leaf: AnyLeaf
					}
					""",
					"""
					@Instantiable
					public struct Leaf: Instantiable {
					    public init() {}
					}
					""",
					"""
					public struct AnyLeaf {
					    public init(_ leaf: Leaf) {
					        self.leaf = leaf
					    }

					    let leaf: Leaf
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: leaf: AnyLeaf
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 2
		BetaScreen: clean, own 0, shared 1, built whole 2
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfHandWrittenMock_whenSharedSubtreeBuildsTypeWithItsMock() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(sign: Sign) {
					        self.sign = sign
					    }

					    @Instantiated let sign: Sign
					}
					""",
					"""
					@Instantiable
					public struct Sign: Instantiable {
					    public init() {
					        depth = 0
					    }

					    init(depth: Int) {
					        self.depth = depth
					    }

					    public static func mock(depth: Int = 3) -> Sign {
					        Sign(depth: depth)
					    }

					    let depth: Int
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: sign: Sign
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 2
		BetaScreen: clean, own 0, shared 1, built whole 2
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfRenamingReceiver_whenSharedSubtreeRenamesDependency() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(service: Service, consumer: Consumer) {
					        self.service = service
					        self.consumer = consumer
					    }

					    @Instantiated let service: Service
					    @Instantiated let consumer: Consumer
					}
					""",
					"""
					@Instantiable
					public struct Service: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Consumer: Instantiable {
					    public init(source: Service) {
					        self.source = source
					    }

					    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let source: Service
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: service: Service
		2: consumer: Consumer
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 3
		BetaScreen: clean, own 0, shared 1, built whole 3
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesRecordOfActor_whenSharedSubtreeInstantiatesActor() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.screensInstantiatingPanel + [
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(worker: Worker) {
					        self.worker = worker
					    }

					    @Instantiated let worker: Worker
					}
					""",
					"""
					@Instantiable
					public actor Worker: Instantiable {
					    public init(clock: Clock) {
					        self.clock = clock
					    }

					    @Instantiated let clock: Clock
					}
					""",
					"""
					@Instantiable
					public struct Clock: Instantiable, Sendable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(report.printed == """
		rows:
		0: panel: Panel, every parent the root
		1: worker: Worker
		2: clock: Clock
		worlds:
		AlphaScreen: clean, own 0, shared 1, built whole 3
		BetaScreen: clean, own 0, shared 1, built whole 3
		differences:
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRowsOfDeepNodeApart_whenTwoRootsNameItsParameterApart() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct AlphaScreen: Instantiable {
					    public init(panel: Panel) {
					        self.panel = panel
					    }

					    @Instantiated let panel: Panel
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct BetaScreen: Instantiable {
					    public init(panel: Panel, badge: Badge) {
					        self.panel = panel
					        self.badge = badge
					    }

					    @Instantiated let panel: Panel
					    @Instantiated let badge: Badge
					}
					""",
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(gauge: Gauge) {
					        self.gauge = gauge
					    }

					    @Instantiated let gauge: Gauge
					}
					""",
					"""
					@Instantiable
					public struct Gauge: Instantiable {
					    public init(service: ServiceA) {
					        self.service = service
					    }

					    @Received let service: ServiceA
					}
					""",
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    public init(service: ServiceB) {
					        self.service = service
					    }

					    @Received let service: ServiceB
					}
					""",
					"""
					public struct ServiceA {}
					""",
					"""
					public struct ServiceB {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Nothing in either tree builds `service`, so each mock takes it as a parameter: `AlphaScreen.mock(service:)`, and,
		// since `BetaScreen`'s tree receives `service` in two types, `BetaScreen.mock(service_ServiceA:service_ServiceB:)`.
		// `gauge`'s record reads the name its root gives its parameter, so the two worlds cannot take one record of it:
		// either `gauge` is two rows that read different names, or `BetaScreen`'s world is built whole. Which one, and the
		// full report, is the implementation's to show; sharing must change no record either way.
		#expect(report.differences == [])
		let gaugeRows = report.rows.filter { $0.label == "gauge" }
		let betaScreen = try #require(report.worlds.first { $0.mockedType == "BetaScreen" })
		let rowsReadNamesApart = gaugeRows.count == 2 && !gaugeRows[0].namesRead.isEmpty && gaugeRows[0].namesRead != gaugeRows[1].namesRead
		#expect(rowsReadNamesApart || betaScreen.builtWholeReason != nil, "\(report.printed)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoRecord_whenBuilderLoopIsWhollyInsideSharedSubtree() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct NorthShell: Instantiable {
					    public init(pane: Pane) {
					        self.pane = pane
					    }

					    @Instantiated let pane: Pane
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct SouthShell: Instantiable {
					    public init(pane: Pane) {
					        self.pane = pane
					    }

					    @Instantiated let pane: Pane
					}
					""",
					"""
					@Instantiable
					public struct Alpha: Instantiable {
					    public init(betaBuilder: Instantiator<Beta>, clock: Clock) {
					        self.betaBuilder = betaBuilder
					        self.clock = clock
					    }

					    @Received let betaBuilder: Instantiator<Beta>
					    @Instantiated let clock: Clock
					}
					""",
					"""
					@Instantiable
					public struct Beta: Instantiable {
					    public init(alphaBuilder: Instantiator<Alpha>, ticker: Ticker) {
					        self.alphaBuilder = alphaBuilder
					        self.ticker = ticker
					    }

					    @Received let alphaBuilder: Instantiator<Alpha>
					    @Instantiated let ticker: Ticker
					}
					""",
					"""
					@Instantiable
					public struct Ticker: Instantiable {
					    public init(alphaBuilder: Instantiator<Alpha>) {
					        self.alphaBuilder = alphaBuilder
					    }

					    @Received let alphaBuilder: Instantiator<Alpha>
					}
					""",
					"""
					@Instantiable
					public struct Clock: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Pane: Instantiable {
					    public init(alphaBuilder: Instantiator<Alpha>, betaBuilder: Instantiator<Beta>) {
					        self.alphaBuilder = alphaBuilder
					        self.betaBuilder = betaBuilder
					    }

					    @Instantiated let alphaBuilder: Instantiator<Alpha>
					    @Instantiated let betaBuilder: Instantiator<Beta>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `pane` holds the loop of `alphaBuilder` and `betaBuilder`, and `ticker`, beneath `betaBuilder`, receives
		// `alphaBuilder`, which `betaBuilder`'s rebinding answers. Loop members become rows in a later step, once the
		// made-again facts are part of a shared variant's key; until then which of the subtree's declarations are rows
		// is left open, and only what holds either way is asserted: sharing changes no record, every row is one of the
		// subtree's declarations, only `pane`'s has the root as every parent, and the two worlds, which build the same
		// subtree, make as many records each when built whole.
		#expect(report.differences == [])
		#expect(report.rows.allSatisfy { ["pane", "alphaBuilder", "betaBuilder", "clock", "ticker"].contains($0.label) }, "\(report.printed)")
		#expect(report.rows.filter(\.isEveryParentTheRoot).allSatisfy { $0.label == "pane" }, "\(report.printed)")
		#expect(report.worlds.map(\.mockedType) == ["NorthShell", "SouthShell"])
		#expect(Set(report.worlds.map(\.recordCountBuiltWhole)).count == 1, "\(report.printed)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoRecord_whenBuilderLoopIsAboveSharedSubtree() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable {
					    public init(alphaBuilder: Instantiator<Alpha>, betaBuilder: Instantiator<Beta>) {
					        self.alphaBuilder = alphaBuilder
					        self.betaBuilder = betaBuilder
					    }

					    @Instantiated let alphaBuilder: Instantiator<Alpha>
					    @Instantiated let betaBuilder: Instantiator<Beta>
					}
					""",
					"""
					@Instantiable
					public struct Alpha: Instantiable {
					    public init(betaBuilder: Instantiator<Beta>, clock: Clock) {
					        self.betaBuilder = betaBuilder
					        self.clock = clock
					    }

					    @Received let betaBuilder: Instantiator<Beta>
					    @Instantiated let clock: Clock
					}
					""",
					"""
					@Instantiable
					public struct Beta: Instantiable {
					    public init(alphaBuilder: Instantiator<Alpha>) {
					        self.alphaBuilder = alphaBuilder
					    }

					    @Received let alphaBuilder: Instantiator<Alpha>
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Other: Instantiable {
					    public init(helper: Helper) {
					        self.helper = helper
					    }

					    @Instantiated let helper: Helper
					}
					""",
					"""
					@Instantiable
					public struct Helper: Instantiable {
					    public init(clock: Clock) {
					        self.clock = clock
					    }

					    @Instantiated let clock: Clock
					}
					""",
					"""
					@Instantiable
					public struct Clock: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `alphaBuilder` and `betaBuilder` are a loop of builders beneath `Root`, which stays in `Root`'s world's top
		// graph, and the sharing frontier runs beneath it: `clock`, beneath `alphaBuilder`, is the declaration `Other`'s
		// world reaches beneath `helper`. Loop members become rows in a later step; until then only what holds either way
		// is asserted: sharing changes no record, every row is a declaration both worlds or `Other`'s alone reach, and
		// `Other`'s world, which holds no loop, takes rows.
		#expect(report.differences == [])
		#expect(report.rows.allSatisfy { ["helper", "clock", "alphaBuilder", "betaBuilder"].contains($0.label) }, "\(report.printed)")
		let other = try #require(report.worlds.first { $0.mockedType == "Other" })
		#expect(other.builtWholeReason == nil && other.sharedRecordCount > 0, "\(report.printed)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsWorldWhole_whenCycleRunsThroughItsRoot() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Dashboard: Instantiable {
					    public init(detailBuilder: Instantiator<Detail>, banner: Banner) {
					        self.detailBuilder = detailBuilder
					        self.banner = banner
					    }

					    @Instantiated let detailBuilder: Instantiator<Detail>
					    @Instantiated let banner: Banner
					}
					""",
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(dashboardBuilder: Instantiator<Dashboard>) {
					        self.dashboardBuilder = dashboardBuilder
					    }

					    @Instantiated let dashboardBuilder: Instantiator<Dashboard>
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Sidebar: Instantiable {
					    public init(banner: Banner) {
					        self.banner = banner
					    }

					    @Instantiated let banner: Banner
					}
					""",
					"""
					@Instantiable
					public struct Banner: Instantiable {
					    public init(icon: Icon) {
					        self.icon = icon
					    }

					    @Instantiated let icon: Icon
					}
					""",
					"""
					@Instantiable
					public struct Icon: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `Dashboard`'s root is on the cycle through `detailBuilder` and `dashboardBuilder`, a cycle that is its world's
		// own, so its world takes no row: it makes every record itself, as it does built whole. `Sidebar`'s world takes
		// `banner`'s row.
		#expect(report.differences == [])
		#expect(report.rows.map(\.printed) == ["0: banner: Banner, every parent the root", "1: icon: Icon"])
		#expect(report.worlds.map(\.mockedType) == ["Dashboard", "Sidebar"])
		let dashboard = try #require(report.worlds.first)
		#expect(dashboard.builtWholeReason == .rootOnCycle)
		#expect(dashboard.sharedRecordCount == 0)
		#expect(dashboard.ownRecordCount == dashboard.recordCountBuiltWhole)
		#expect(report.worlds.last?.printed == "Sidebar: clean, own 0, shared 1, built whole 2")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsWorldWhole_whenPublicMockRootReachesHole() async throws {
		let report = try await Self.sharingReport(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Screen: Instantiable {
					    public init(panel: Panel, badge: Badge) {
					        self.panel = panel
					        self.badge = badge
					    }

					    @Instantiated let panel: Panel
					    @Instantiated let badge: Badge
					}
					""",
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(gadget: Gadget) {
					        self.gadget = gadget
					    }

					    @Instantiated let gadget: Gadget
					}
					""",
					"""
					public struct Gadget {}
					""",
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Sidebar: Instantiable {
					    public init(badge: Badge) {
					        self.badge = badge
					    }

					    @Instantiated let badge: Badge
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Nothing the module sees fulfills `gadget`, so the public mock's world holds it as a hole, which its builder
		// fills: the world is built whole and takes no row. `Sidebar`'s world takes `badge`'s row.
		#expect(report.differences == [])
		#expect(report.rows.map(\.printed) == ["0: badge: Badge, every parent the root"])
		#expect(report.worlds.map(\.mockedType) == ["Screen", "Sidebar"])
		let screen = try #require(report.worlds.first)
		#expect(screen.builtWholeReason == .rootReachesHole)
		#expect(screen.sharedRecordCount == 0)
		#expect(screen.ownRecordCount == screen.recordCountBuiltWhole)
		#expect(report.worlds.last?.printed == "Sidebar: clean, own 0, shared 1, built whole 1")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Two mock roots, `AlphaScreen` and `BetaScreen`, each instantiating `panel: Panel`, the top of the subtree they
	/// share, which each test declares.
	private static let screensInstantiatingPanel = [
		"""
		@Instantiable(generateMock: true)
		public struct AlphaScreen: Instantiable {
		    public init(panel: Panel) {
		        self.panel = panel
		    }

		    @Instantiated let panel: Panel
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public struct BetaScreen: Instantiable {
		    public init(panel: Panel) {
		        self.panel = panel
		    }

		    @Instantiated let panel: Panel
		}
		""",
	]

	/// The one sharing report the module's mock generation hands the observer while `body` runs.
	private static func sharingReport(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> some Any,
	) async throws -> MockWorldSharingReport {
		let (stream, continuation) = AsyncStream.makeStream(of: MockWorldSharingReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		_ = try await MockWorldSharingObservation.$observer.withValue({ continuation.yield($0) }) {
			try await body(&filesMade)
		}
		continuation.finish()
		var reports = [MockWorldSharingReport]()
		for await report in stream {
			reports.append(report)
		}
		#expect(reports.count <= 1, "The module’s mock generation handed the sharing observer \(reports.count) reports")
		return try #require(reports.first, "The mock worlds’ pre-pass never called the sharing observer")
	}
}

extension MockWorldSharingReport {
	/// The report as the tests compare it: its rows, its worlds and its differences, a line each, under a heading each.
	fileprivate var printed: String {
		var lines = ["rows:"]
		lines.append(contentsOf: rows.map(\.printed))
		lines.append("worlds:")
		lines.append(contentsOf: worlds.map(\.printed))
		lines.append("differences:")
		lines.append(contentsOf: differences)
		return lines.joined(separator: "\n")
	}
}

extension MockWorldSharingReport.Row {
	/// `<declaration>: <label>: <type>`, then `, every parent the root` where every parent is the root, then
	/// `, reading <name>, <name>` where the record read names of a root's.
	fileprivate var printed: String {
		var line = "\(declaration): \(label): \(type)"
		if isEveryParentTheRoot {
			line += ", every parent the root"
		}
		if !namesRead.isEmpty {
			line += ", reading \(namesRead.joined(separator: ", "))"
		}
		return line
	}
}

extension MockWorldSharingReport.World {
	/// `<mocked type>: clean` or `built whole (<reason>)`, then the records it made, took, and makes built whole.
	fileprivate var printed: String {
		let state = builtWholeReason.map { "built whole (\($0.rawValue))" } ?? "clean"
		return "\(mockedType): \(state), own \(ownRecordCount), shared \(sharedRecordCount), built whole \(recordCountBuiltWhole)"
	}
}
