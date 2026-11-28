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

/// The mock worlds' table (`MockWorldsTable`): one entry per distinct declaration of a module's mock worlds, and which
/// of them a world may take from the table, read through `MockWorldsTableObservation`.
struct SafeDIToolMockWorldsTableTests: ~Copyable {
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
	mutating func generate_countsEachSharedDeclarationOnce_whenMockRootsShareSubtree() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
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
					@Instantiable(generateMock: true)
					public struct GammaScreen: Instantiable {
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
		// Each world holds its root, `store` and `clock`: nine declarations, of which `store` and `clock` are the same two
		// in every world, whose two records every world shares. A world holds `store`'s shared record, which holds `clock`'s,
		// where without the table it builds both.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 5,
				shareableDeclarationCount: 2,
				sharedGraphDeclarations: [1, 2], sharedVariantCount: 2, graphDeclarationCounts: [2, 2, 2],
				sharedRecordCount: 2,
				rows: ["1: store: SessionStore, every parent the root", "2: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 3, shareableDeclarationCount: 2, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 2, declarationKeys: [1, 3, 4]),
					.init(mockedType: "BetaScreen", rootDeclaration: 3, declarationCount: 3, shareableDeclarationCount: 2, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 2, declarationKeys: [7, 3, 4]),
					.init(mockedType: "GammaScreen", rootDeclaration: 4, declarationCount: 3, shareableDeclarationCount: 2, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 2, declarationKeys: [9, 3, 4]),
				],
			),
		])
		#expect(reports.map { $0.worlds.map(\.declarationCount).reduce(0, +) } == [9])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesExactlyDeclarationsReachingCycleUnshareable_whenSubtreeHoldsCycle() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Dashboard: Instantiable {
					    public init(holder: Holder, banner: Banner) {
					        self.holder = holder
					        self.banner = banner
					    }

					    @Instantiated let holder: Holder
					    @Instantiated let banner: Banner
					}
					""",
					"""
					@Instantiable
					public struct Holder: Instantiable {
					    public init(editor: Editor) {
					        self.editor = editor
					    }

					    @Instantiated let editor: Editor
					}
					""",
					"""
					@Instantiable
					public struct Editor: Instantiable {
					    public init(previewBuilder: Instantiator<Preview>) {
					        self.previewBuilder = previewBuilder
					    }

					    @Instantiated let previewBuilder: Instantiator<Preview>
					}
					""",
					"""
					@Instantiable
					public struct Preview: Instantiable {
					    public init(editor: Editor) {
					        self.editor = editor
					    }

					    @Instantiated let editor: Editor
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
		// `editor` and `previewBuilder` form the cycle, which `holder` reaches; `banner` and `icon` reach none, and the root
		// is its world's own. The cycle refuses the world's records, but `banner` and `icon` are rows all the same.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 6,
				shareableDeclarationCount: 2,
				sharedGraphDeclarations: [4, 5], sharedVariantCount: 2, graphDeclarationCounts: [5],
				sharedRecordCount: 2,
				rows: ["4: banner: Banner, every parent the root", "5: icon: Icon"],
				differences: [],
				worlds: [
					.init(mockedType: "Dashboard", rootDeclaration: 0, declarationCount: 6, shareableDeclarationCount: 2, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 9, 4, 10, 6]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesDeclarationsReachingHoleUnshareable_whenPublicMockHoldsHole() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
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
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Nothing the module sees fulfills `gadget`, so the public mock's world holds it as a hole, a place its mock's
		// builder fills: `panel` reaches it, and only `badge` is shareable. The world is built whole, so its graph holds its
		// four declarations, it calls no variant of the shared graph, and no row is made of `badge`.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 4,
				shareableDeclarationCount: 1,
				sharedGraphDeclarations: [3],
				sharedVariantCount: 0,
				graphDeclarationCounts: [4],
				sharedRecordCount: 0,
				rows: [],
				differences: [],
				worlds: [
					.init(mockedType: "Screen", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 7, 4]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesSameCountsAndIDsInMockRootOrder_whenTypesSourceOrderIsReversed() async throws {
		// Twenty-two mock roots: the even ones build `store`, the odd ones `feed`, and both build `clock`.
		var declarations = (0..<22).map { index in
			let name = "Screen" + (index < 10 ? "0" : "") + String(index)
			let (label, type) = index.isMultiple(of: 2) ? ("store", "Store") : ("feed", "Feed")
			return """
			@Instantiable(generateMock: true)
			public struct \(name): Instantiable {
			    public init(\(label): \(type)) {
			        self.\(label) = \(label)
			    }

			    @Instantiated let \(label): \(type)
			}
			"""
		}
		for type in ["Store", "Feed"] {
			declarations.append("""
			@Instantiable
			public struct \(type): Instantiable {
			    public init(clock: Clock) {
			        self.clock = clock
			    }

			    @Instantiated let clock: Clock
			}
			""")
		}
		declarations.append("""
		@Instantiable
		public struct Clock: Instantiable {
		    public init() {}
		}
		""")
		var reports = [[MockWorldsTableReport]]()
		for orderedDeclarations in [declarations, declarations.reversed()] {
			let source = orderedDeclarations.joined(separator: "\n\n")
			await reports.append(try Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: ["Screens.swift": source],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			})
		}
		// The first world meets its root, `store` and `clock`, the second its root and `feed`, and every later world only
		// its root, in the order the mock roots are lowered.
		var worlds = [MockWorldsTableReport.World]()
		for index in 0..<22 {
			let rootDeclaration = switch index {
			case 0: 0
			case 1: 3
			default: index + 3
			}
			let rootKey = Int32(rootDeclaration * 2 + 1)
			let childKey: Int32 = index.isMultiple(of: 2) ? 3 : 9
			worlds.append(.init(mockedType: "Screen" + (index < 10 ? "0" : "") + String(index), rootDeclaration: rootDeclaration, declarationCount: 3, shareableDeclarationCount: 2, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 2, declarationKeys: [rootKey, childKey, 4]))
		}
		// `store` and `feed` are each only their root's child, and `clock` never is: three rows.
		let expected = [MockWorldsTableReport(declarationCount: 25, shareableDeclarationCount: 3, sharedGraphDeclarations: [1, 2, 4], sharedVariantCount: 3, graphDeclarationCounts: Array(repeating: 2, count: 22), sharedRecordCount: 3, rows: ["1: store: Store, every parent the root", "2: clock: Clock", "4: feed: Feed, every parent the root"], differences: [], worlds: worlds)]
		#expect(reports == [expected, expected])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachSharedRecordOnceForTheRun_whenEightMockRootsShareSubtree() async throws {
		var declarations = (0..<8).map { index in
			"""
			@Instantiable(generateMock: true)
			public struct Screen\(index): Instantiable {
			    public init(store: SessionStore) {
			        self.store = store
			    }

			    @Instantiated let store: SessionStore
			}
			"""
		}
		declarations += [
			"""
			@Instantiable
			public struct SessionStore: Instantiable {
			    public init(clock: Clock, logger: Logger) {
			        self.clock = clock
			        self.logger = logger
			    }

			    @Instantiated let clock: Clock
			    @Instantiated let logger: Logger
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
			public struct Logger: Instantiable {
			    public init() {}
			}
			""",
		]
		let source = declarations.joined(separator: "\n\n")
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: ["Screens.swift": source],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `store`, `clock` and `logger` are three rows, each record built once for the run; each world holds `store`'s,
		// which holds the other two, where without the table each world builds all three.
		var worlds = [MockWorldsTableReport.World]()
		for index in 0..<8 {
			let rootDeclaration = index == 0 ? 0 : index + 3
			let rootKey = Int32(rootDeclaration * 2 + 1)
			worlds.append(MockWorldsTableReport.World(mockedType: "Screen\(index)", rootDeclaration: rootDeclaration, declarationCount: 4, shareableDeclarationCount: 3, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 3, declarationKeys: [rootKey, 3, 4, 6]))
		}
		#expect(reports == [MockWorldsTableReport(declarationCount: 11, shareableDeclarationCount: 3, sharedGraphDeclarations: [1, 2, 3], sharedVariantCount: 3, graphDeclarationCounts: [2, 2, 2, 2, 2, 2, 2, 2], sharedRecordCount: 3, rows: ["1: store: SessionStore, every parent the root", "2: clock: Clock", "3: logger: Logger"], differences: [], worlds: worlds)])
		#expect(reports.map { $0.sharedRecordCount + $0.worlds.map { $0.recordCount - $0.sharedRecordCount }.reduce(0, +) } == [3])
		#expect(reports.map { $0.worlds.map(\.recordCountWithoutTable).reduce(0, +) } == [24])
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
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: ["Screens.swift": source],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// The subtree is four rows, `shared`, `first`, `second` and `third`, whose records are built once for the run however
		// many worlds share them; each world's graph holds its root and the frontier `shared`, and the world makes no record
		// of its own, taking `shared`'s, while without the table each world builds all four.
		#expect(reports.map(\.sharedRecordCount) == [4])
		#expect(reports.map(\.sharedVariantCount) == [4])
		#expect(reports.map(\.rows) == [["1: shared: Shared, every parent the root", "2: first: First", "3: second: Second", "4: third: Third"]])
		#expect(reports.map(\.graphDeclarationCounts) == [Array(repeating: 2, count: rootCount)])
		#expect(reports.map { $0.worlds.map { $0.recordCount - $0.sharedRecordCount } } == [Array(repeating: 0, count: rootCount)])
		#expect(reports.map { $0.worlds.map(\.sharedRecordCount) } == [Array(repeating: 1, count: rootCount)])
		#expect(reports.map { $0.worlds.map(\.recordCountWithoutTable).reduce(0, +) } == [4 * rootCount])
		#expect(reports.map(\.differences) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsNoMockWorldsTableReport_whenNoTestObservesTheTable() async throws {
		let reports = try await NodeRecordsChecks.$observesMockWorldsTable.withValue(false) {
			try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
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
		}
		#expect(reports.isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesTwoRowsOfOneDeclaration_whenOneWorldBuildsItAtItsRootAndAnotherDeeper() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct AlphaScreen: Instantiable {
					    public init(clock: Clock) {
					        self.clock = clock
					    }

					    @Instantiated let clock: Clock
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
		// `clock` is one declaration, the root's child in `AlphaScreen`'s world and `store`'s in `BetaScreen`'s: two rows,
		// beside `store`'s.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 4,
				shareableDeclarationCount: 2,
				sharedGraphDeclarations: [1, 3], sharedVariantCount: 2, graphDeclarationCounts: [2, 2],
				sharedRecordCount: 3,
				rows: ["1: clock: Clock, every parent the root", "3: store: SessionStore, every parent the root", "1: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 2, shareableDeclarationCount: 1, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 1, declarationKeys: [1, 3]),
					.init(mockedType: "BetaScreen", rootDeclaration: 2, declarationCount: 3, shareableDeclarationCount: 2, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 2, declarationKeys: [5, 7, 2]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsLoopMembersOutOfRows_whenBuilderLoopIsAboveSharedSubtree() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
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
		// The table sees no cycle, but `alphaBuilder` and `betaBuilder` are a loop of builders beneath `Root`, so neither is
		// shareable and `Root`'s world's top graph holds both; `clock`, beneath `alphaBuilder`, is the row `Other`'s world's
		// `clock` is. The loop refuses `Root`'s world's records, so only `Other`'s world takes rows: `helper`'s, holding
		// `clock`'s.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 6,
				shareableDeclarationCount: 2,
				sharedGraphDeclarations: [1, 2], sharedVariantCount: 2, graphDeclarationCounts: [2, 4],
				sharedRecordCount: 2,
				rows: ["1: helper: Helper, every parent the root", "2: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "Other", rootDeclaration: 0, declarationCount: 3, shareableDeclarationCount: 2, recordCount: 1, sharedRecordCount: 1, recordCountWithoutTable: 2, declarationKeys: [1, 3, 4]),
					.init(mockedType: "Root", rootDeclaration: 3, declarationCount: 4, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [7, 9, 11, 4]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesLoopWithItsParent_whenBuilderLoopIsWhollyInsideSharedSubtree() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.loopFixtures(.whollyInsidePane),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `pane`, which holds the loop of `alphaBuilder` and `betaBuilder`, is shareable by every other condition and each
		// member has `pane` alone as its parent, so the loop is shared whole with it: `pane`, both members, `clock` and
		// `ticker` are the shared graph's, each in one variant, whose made-again calls and the answer `betaBuilder`'s
		// rebinding gives `ticker` the shared graph finds as each world's graph does. A mock world's loop member is refused
		// (`builderLoop`), with or without the table, so neither member is a row and `pane`, which calls them, is none:
		// the rows are `clock`'s and `ticker`'s, and neither world takes a record.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 7,
				shareableDeclarationCount: 5,
				sharedGraphDeclarations: [1, 2, 3, 4, 5], sharedVariantCount: 5, graphDeclarationCounts: [2, 2],
				sharedRecordCount: 2,
				rows: ["3: clock: Clock", "5: ticker: Ticker"],
				differences: [],
				worlds: [
					.init(mockedType: "NorthShell", rootDeclaration: 0, declarationCount: 6, shareableDeclarationCount: 5, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 4, 8, 6, 10]),
					.init(mockedType: "SouthShell", rootDeclaration: 6, declarationCount: 6, shareableDeclarationCount: 5, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [13, 3, 4, 8, 6, 10]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsLoopMembersOutOfSharedGraph_whenLoopsParentIsOnCycle() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.loopFixtures(.paneOnCycle),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `pane` is on a cycle through `gizmoBuilder`, so it stays in each world's top graph, and its loop with it: neither
		// member is shareable, though nothing beneath them reaches a cycle, so no loop crosses the frontier. Only `clock` is
		// shared, and is the one row.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 8,
				shareableDeclarationCount: 1,
				sharedGraphDeclarations: [3], sharedVariantCount: 1, graphDeclarationCounts: [7, 7],
				sharedRecordCount: 1,
				rows: ["3: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "NorthShell", rootDeclaration: 0, declarationCount: 7, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 4, 8, 10, 6, 12]),
					.init(mockedType: "SouthShell", rootDeclaration: 7, declarationCount: 7, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [15, 3, 4, 8, 10, 6, 12]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsLoopMembersOutOfSharedGraph_whenMemberHasSecondParent() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.loopFixtures(.memberBuiltWithoutLoopToo),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `alphaBuilder` has two parents: `pane`, whose loop makes `betaBuilder` again in it, and `dock`, under which it is
		// no member. A world reaching both would share it apart and one reaching one would not, so `pane`'s loop stays in
		// each world's top graph. Only `clock` is shared, and is the one row.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 8,
				shareableDeclarationCount: 1,
				sharedGraphDeclarations: [3], sharedVariantCount: 1, graphDeclarationCounts: [5, 5, 4],
				sharedRecordCount: 1,
				rows: ["3: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "NorthShell", rootDeclaration: 0, declarationCount: 5, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 4, 8, 6]),
					.init(mockedType: "SouthShell", rootDeclaration: 5, declarationCount: 5, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [11, 3, 4, 8, 6]),
					.init(mockedType: "WestShell", rootDeclaration: 6, declarationCount: 4, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [13, 15, 4, 6]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsOuterLoopOutOfSharedGraph_whenInnerLoopBeneathItIsUnshared() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.loopFixtures(.innerLoopMemberBuiltByMockRootToo),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `hub`'s loop of `deltaBuilder` and `epsilonBuilder` is `WestShell`'s mock root's loop too, so it stays unshared,
		// and `alphaBuilder`, which reaches `hub`, is unshareable. `pane` was shareable by every other condition, but now
		// reaches an unshared loop, so its own loop stays in each world's top graph too: `betaBuilder`, which reaches no
		// unshared loop, is no frontier beneath a top-graph loop parent. Nothing is shared.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 9,
				shareableDeclarationCount: 0,
				sharedGraphDeclarations: [], sharedVariantCount: 0, graphDeclarationCounts: [7, 7, 3],
				sharedRecordCount: 0,
				rows: [],
				differences: [],
				worlds: [
					.init(mockedType: "NorthShell", rootDeclaration: 0, declarationCount: 7, shareableDeclarationCount: 0, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 4, 12, 6, 8, 10]),
					.init(mockedType: "SouthShell", rootDeclaration: 7, declarationCount: 7, shareableDeclarationCount: 0, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [15, 3, 4, 12, 6, 8, 10]),
					.init(mockedType: "WestShell", rootDeclaration: 8, declarationCount: 3, shareableDeclarationCount: 0, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [17, 9, 11]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesFillUnshareable_whenMockCallsAnotherModulesPublicMock() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: ["FeatureTypes.swift": """
					import SafeDI

					public protocol Api: AnyObject {}

					@Instantiable(generateMock: .public)
					public final class Panel: Instantiable {
					    init(api: any Api) { self.api = api }
					    @Instantiated public let api: any Api
					}
					"""]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": """
					import Feature
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Api.self])
					public final class LiveApi: Api, Instantiable {
					    public init(clock: Clock) { self.clock = clock }
					    @Instantiated let clock: Clock
					}

					@Instantiable
					public final class Clock: Instantiable {
					    public init() {}
					}

					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    public init(panel: Panel) { self.panel = panel }
					    @Instantiated let panel: Panel
					}
					"""], dependencies: ["Feature"], activeCompilationConditions: ["DEBUG"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		// `Feature`'s run: `api` is a hole of `Panel`'s public mock. `App`'s run: `Root`'s mock calls `Panel`'s, passing a fill
		// that builds `LiveApi`, which reads the scope of the call, so the fill and `panel` are built per world, and only
		// `clock`, beneath the fill, is shareable.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 2,
				shareableDeclarationCount: 0,
				sharedGraphDeclarations: [], sharedVariantCount: 0, graphDeclarationCounts: [2],
				sharedRecordCount: 0,
				rows: [],
				differences: [],
				worlds: [
					.init(mockedType: "Panel", rootDeclaration: 0, declarationCount: 2, shareableDeclarationCount: 0, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3]),
				],
			),
			MockWorldsTableReport(
				declarationCount: 4,
				shareableDeclarationCount: 1,
				sharedGraphDeclarations: [3], sharedVariantCount: 1, graphDeclarationCounts: [4],
				sharedRecordCount: 1,
				rows: ["3: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "Root", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 1, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 4, 6]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsRecordsApart_whenTestClaimsSharedDeclaration() async throws {
		let reports = try await NodeRecordsObservation.$claimsForTesting.withValue(["Clock": []]) {
			try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
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
		}
		// A claim makes `clock` no mock construction, so it is no row, nor is `store`, which calls it: the world builds both
		// records itself, as it does without the table.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 3,
				shareableDeclarationCount: 2,
				sharedGraphDeclarations: [1, 2], sharedVariantCount: 2, graphDeclarationCounts: [2],
				sharedRecordCount: 0,
				rows: [],
				differences: [],
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 3, shareableDeclarationCount: 2, recordCount: 2, sharedRecordCount: 0, recordCountWithoutTable: 2, declarationKeys: [1, 3, 4]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesDeclarationOnCycleOneKeyInEveryWorld_whenTwoMockRootsReachTheCycle() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct AlphaScreen: Instantiable {
					    public init(holder: Holder) {
					        self.holder = holder
					    }

					    @Instantiated let holder: Holder
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct BetaScreen: Instantiable {
					    public init(holder: Holder) {
					        self.holder = holder
					    }

					    @Instantiated let holder: Holder
					}
					""",
					"""
					@Instantiable
					public struct Holder: Instantiable {
					    public init(editor: Editor) {
					        self.editor = editor
					    }

					    @Instantiated let editor: Editor
					}
					""",
					"""
					@Instantiable
					public struct Editor: Instantiable {
					    public init(previewBuilder: Instantiator<Preview>) {
					        self.previewBuilder = previewBuilder
					    }

					    @Instantiated let previewBuilder: Instantiator<Preview>
					}
					""",
					"""
					@Instantiable
					public struct Preview: Instantiable {
					    public init(editor: Editor) {
					        self.editor = editor
					    }

					    @Instantiated let editor: Editor
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `editor` and `previewBuilder` form a cycle, so nothing is shareable and no variant is a row, yet every variant has
		// a key, and `editor`, on the cycle, has the key 4 (declaration 2, beneath `holder`) in both worlds, as do `holder`
		// (3) and `previewBuilder` (6). Only the roots' keys differ.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 5,
				shareableDeclarationCount: 0,
				sharedGraphDeclarations: [], sharedVariantCount: 0, graphDeclarationCounts: [4, 4],
				sharedRecordCount: 0,
				rows: [],
				differences: [],
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 0, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [1, 3, 4, 6]),
					.init(mockedType: "BetaScreen", rootDeclaration: 4, declarationCount: 4, shareableDeclarationCount: 0, recordCount: 0, sharedRecordCount: 0, recordCountWithoutTable: 0, declarationKeys: [9, 3, 4, 6]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsNoMockWorldsTable_whenNoTestObservesNodeRecords() async throws {
		let reports = try await NodeRecordsChecks.$observesNodeRecords.withValue(false) {
			try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						@Instantiable(generateMock: true)
						public struct AlphaScreen: Instantiable {
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
		}
		#expect(reports.isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsEachShareableDeclarationOnceInSharedGraph_whenEightMockRootsShareSubtree() async throws {
		let source = Self.eightScreensSharingSessionStore
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: ["Screens.swift": source],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// The worlds hold 24 shareable declarations between them, three distinct ones, which the shared graph holds once each,
		// and each world's facts of each equal the shared graph's.
		#expect(reports.map { $0.worlds.map(\.shareableDeclarationCount).reduce(0, +) } == [24])
		#expect(reports.map(\.sharedGraphDeclarations) == [[1, 2, 3]])
		#expect(reports.map(\.differences) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsOnlyTopAndFrontierInEachWorldsGraph_whenEightMockRootsShareSubtree() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: ["Screens.swift": Self.eightScreensSharingSessionStore],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Each world's graph holds its root and the frontier beneath it, `store`, of the four declarations the world holds;
		// the shared graph holds one variant of each of its three declarations, which every world calls alike, and each
		// world's dense view equals its graph built whole.
		#expect(reports.map { $0.worlds.map(\.declarationCount) } == [Array(repeating: 4, count: 8)])
		#expect(reports.map(\.graphDeclarationCounts) == [Array(repeating: 2, count: 8)])
		#expect(reports.map(\.sharedVariantCount) == [3])
		#expect(reports.map(\.differences) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsSharedDeclarationOnceWithEqualFacts_whenTwoWorldsAnswerItsReadApart() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.twoScreensAnsweringTokenApart,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `store` reads `token`, which `AlphaScreen`'s world answers with a value and `BetaScreen`'s with a lazy wrapper's
		// instance: its facts are its subtree's alone, so the shared graph holds it once, as each world computes it.
		#expect(reports.map(\.sharedGraphDeclarations) == [[1, 2, 3, 5]])
		#expect(reports.map(\.differences) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesSharedDeclarationTwoVariants_whenTwoWorldsAnswerItsReadApart() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.twoScreensAnsweringTokenApart,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `AlphaScreen` calls `store` with its `token` answered by a value and `BetaScreen` by a lazy wrapper: two variants
		// of `store`, beside one each of the two `token`s and `clock`, and each world's dense view equals its graph built
		// whole.
		#expect(reports.map(\.sharedGraphDeclarations) == [[1, 2, 3, 5]])
		#expect(reports.map(\.sharedVariantCount) == [5])
		#expect(reports.map(\.differences) == [[]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesSameSharedGraph_whenSixMockRootsAreDeclaredInEachOfThreeOrders() async throws {
		let declarations = [
			("Feed", "Clock"), ("Store", "Clock"), ("Inbox", "Logger"), ("Cart", "Logger"), ("Search", "Clock"), ("Profile", "Logger"),
		].enumerated().flatMap { index, pair in
			let (type, child) = pair
			let label = type.prefix(1).lowercased() + type.dropFirst()
			let childLabel = child.prefix(1).lowercased() + child.dropFirst()
			return [
				"""
				@Instantiable(generateMock: true)
				public struct Screen\(index): Instantiable {
				    public init(\(label): \(type)) {
				        self.\(label) = \(label)
				    }

				    @Instantiated let \(label): \(type)
				}
				""",
				"""
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(childLabel): \(child)) {
				        self.\(childLabel) = \(childLabel)
				    }

				    @Instantiated let \(childLabel): \(child)
				}
				""",
			]
		} + [
			"""
			@Instantiable
			public struct Clock: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public struct Logger: Instantiable {
			    public init() {}
			}
			""",
		]
		// The declarations as written, reversed, and in a fixed shuffle.
		let shuffle = [7, 2, 11, 0, 13, 5, 9, 1, 12, 4, 6, 10, 3, 8]
		var reports = [[MockWorldsTableReport]]()
		for orderedDeclarations in [declarations, declarations.reversed(), shuffle.map { declarations[$0] }] {
			let source = orderedDeclarations.joined(separator: "\n\n")
			await reports.append(try Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: ["Screens.swift": source],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			})
		}
		// Each mock root's child is a root of the shared graph, in the order the mock roots are lowered, and each child's
		// `clock` or `logger` follows the first child that reaches it.
		#expect(reports.map { $0.map(\.sharedGraphDeclarations) } == [[[1, 2, 4, 6, 7, 9, 11, 13]], [[1, 2, 4, 6, 7, 9, 11, 13]], [[1, 2, 4, 6, 7, 9, 11, 13]]])
		#expect(reports[1] == reports[0])
		#expect(reports[2] == reports[0])
	}

	// MARK: Private

	/// Eight mock roots that each instantiate `SessionStore`, which instantiates `Clock` and `Logger`.
	private static var eightScreensSharingSessionStore: String {
		var declarations = (0..<8).map { index in
			"""
			@Instantiable(generateMock: true)
			public struct Screen\(index): Instantiable {
			    public init(store: SessionStore) {
			        self.store = store
			    }

			    @Instantiated let store: SessionStore
			}
			"""
		}
		declarations += [
			"""
			@Instantiable
			public struct SessionStore: Instantiable {
			    public init(clock: Clock, logger: Logger) {
			        self.clock = clock
			        self.logger = logger
			    }

			    @Instantiated let clock: Clock
			    @Instantiated let logger: Logger
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
			public struct Logger: Instantiable {
			    public init() {}
			}
			""",
		]
		return declarations.joined(separator: "\n\n")
	}

	/// Two mock roots that instantiate `token` apart, as a value and as a lazy wrapper, and each a `SessionStore` that
	/// receives it.
	private static let twoScreensAnsweringTokenApart = [
		"""
		@Instantiable(generateMock: true)
		public struct AlphaScreen: Instantiable {
		    public init(token: Token, store: SessionStore) {
		        self.token = token
		        self.store = store
		    }

		    @Instantiated let token: Token
		    @Instantiated let store: SessionStore
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public struct BetaScreen: Instantiable {
		    public init(token: LazilyInstantiated<Token>, store: SessionStore) {
		        self.token = token
		        self.store = store
		    }

		    @Instantiated let token: LazilyInstantiated<Token>
		    @Instantiated let store: SessionStore
		}
		""",
		"""
		@Instantiable
		public struct SessionStore: Instantiable {
		    public init(token: Token, clock: Clock) {
		        self.token = token
		        self.clock = clock
		    }

		    @Received let token: Token
		    @Instantiated let clock: Clock
		}
		""",
		"""
		@Instantiable
		public struct Token: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public struct Clock: Instantiable {
		    public init() {}
		}
		""",
	]

	/// Where a loop of builders sits in the fixtures of the loop tests: `Pane`, which two mock roots instantiate, holds the
	/// loop of `alphaBuilder` and `betaBuilder`.
	private enum LoopShape {
		/// The loop and everything beneath it are wholly inside `Pane`'s subtree, where `Ticker`, beneath `betaBuilder`,
		/// receives `alphaBuilder`, which `betaBuilder`'s rebinding answers.
		case whollyInsidePane
		/// `Pane` is on a cycle through `Gizmo`, so it stays in each world's top graph.
		case paneOnCycle
		/// `Alpha` receives `betaBuilder` only if available, and a third mock root, `WestShell`, instantiates `Dock`, which
		/// instantiates `alphaBuilder` with no `betaBuilder` beside it: the member has a second parent, under which it is no
		/// member of a loop and its `betaBuilder` is `nil`.
		case memberBuiltWithoutLoopToo
		/// `Alpha` instantiates `Hub`, which holds a loop of `deltaBuilder` and `epsilonBuilder` that `WestShell`, a third
		/// mock root, instantiates too.
		case innerLoopMemberBuiltByMockRootToo
	}

	private static func loopFixtures(_ shape: LoopShape) -> [String] {
		switch shape {
		case .whollyInsidePane:
			[
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
			]
		case .paneOnCycle:
			[
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
			    public init(alphaBuilder: Instantiator<Alpha>, betaBuilder: Instantiator<Beta>, gizmoBuilder: Instantiator<Gizmo>) {
			        self.alphaBuilder = alphaBuilder
			        self.betaBuilder = betaBuilder
			        self.gizmoBuilder = gizmoBuilder
			    }

			    @Instantiated let alphaBuilder: Instantiator<Alpha>
			    @Instantiated let betaBuilder: Instantiator<Beta>
			    @Instantiated let gizmoBuilder: Instantiator<Gizmo>
			}
			""",
			"""
			@Instantiable
			public struct Gizmo: Instantiable {
			    public init(paneBuilder: Instantiator<Pane>) {
			        self.paneBuilder = paneBuilder
			    }

			    @Instantiated let paneBuilder: Instantiator<Pane>
			}
			""",
			]
		case .memberBuiltWithoutLoopToo:
			[
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
			    public init(betaBuilder: Instantiator<Beta>?, clock: Clock) {
			        self.betaBuilder = betaBuilder
			        self.clock = clock
			    }

			    @Received(onlyIfAvailable: true) let betaBuilder: Instantiator<Beta>?
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
			"""
			@Instantiable(generateMock: true)
			public struct WestShell: Instantiable {
			    public init(dock: Dock) {
			        self.dock = dock
			    }

			    @Instantiated let dock: Dock
			}
			""",
			"""
			@Instantiable
			public struct Dock: Instantiable {
			    public init(alphaBuilder: Instantiator<Alpha>) {
			        self.alphaBuilder = alphaBuilder
			    }

			    @Instantiated let alphaBuilder: Instantiator<Alpha>
			}
			""",
		]
		case .innerLoopMemberBuiltByMockRootToo:
			[
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
			    public init(betaBuilder: Instantiator<Beta>, hub: Hub) {
			        self.betaBuilder = betaBuilder
			        self.hub = hub
			    }

			    @Received let betaBuilder: Instantiator<Beta>
			    @Instantiated let hub: Hub
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
			"""
			@Instantiable
			public struct Hub: Instantiable {
			    public init(deltaBuilder: Instantiator<Delta>, epsilonBuilder: Instantiator<Epsilon>) {
			        self.deltaBuilder = deltaBuilder
			        self.epsilonBuilder = epsilonBuilder
			    }

			    @Instantiated let deltaBuilder: Instantiator<Delta>
			    @Instantiated let epsilonBuilder: Instantiator<Epsilon>
			}
			""",
			"""
			@Instantiable
			public struct Delta: Instantiable {
			    public init(epsilonBuilder: Instantiator<Epsilon>) {
			        self.epsilonBuilder = epsilonBuilder
			    }

			    @Received let epsilonBuilder: Instantiator<Epsilon>
			}
			""",
			"""
			@Instantiable
			public struct Epsilon: Instantiable {
			    public init(deltaBuilder: Instantiator<Delta>) {
			        self.deltaBuilder = deltaBuilder
			    }

			    @Received let deltaBuilder: Instantiator<Delta>
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public struct WestShell: Instantiable {
			    public init(deltaBuilder: Instantiator<Delta>, epsilonBuilder: Instantiator<Epsilon>) {
			        self.deltaBuilder = deltaBuilder
			        self.epsilonBuilder = epsilonBuilder
			    }

			    @Instantiated let deltaBuilder: Instantiator<Delta>
			    @Instantiated let epsilonBuilder: Instantiator<Epsilon>
			}
			""",
			]
		}
	}

	private var filesToDelete: [URL]

	/// The reports of the mock worlds' table `body`'s runs hand the observer.
	private static func tableReports(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> some Any,
	) async throws -> [MockWorldsTableReport] {
		let (stream, continuation) = AsyncStream.makeStream(of: MockWorldsTableReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		_ = try await MockWorldsTableObservation.$observer.withValue({ continuation.yield($0) }) {
			try await body(&filesMade)
		}
		continuation.finish()
		var reports = [MockWorldsTableReport]()
		for await report in stream {
			reports.append(report)
		}
		return reports
	}
}
