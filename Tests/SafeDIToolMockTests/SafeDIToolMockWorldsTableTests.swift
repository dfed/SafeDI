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

/// The mock worlds' table (`MockWorldsTable`): one entry per distinct declaration of a module's mock worlds, which of
/// them a world may take from the graph every world shares, and what each world keeps in its own graph, read through
/// `MockWorldsTableObservation`.
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
					Self.type("AlphaScreen", mocked: true, instantiating: [("panel", "Panel")]),
					Self.type("BetaScreen", mocked: true, instantiating: [("panel", "Panel")]),
					Self.type("GammaScreen", mocked: true, instantiating: [("panel", "Panel")]),
					Self.type("Panel", instantiating: [("store", "SessionStore")]),
					Self.type("SessionStore", instantiating: [("clock", "Clock")]),
					Self.type("Clock"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Each world holds its root, `panel`, `store` and `clock`, of which the last three are the same in every world. A
		// world builds its root and what its root builds itself, `panel`, and calls the shared `store` from `panel`. The
		// shared graph holds `store` and `clock` once, a variant each, and every world's call lands on `store`'s.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 6,
				sharedDeclarationCount: 2,
				sharedVariantCount: 2,
				shareableDeclarations: ["1: panel: Panel", "2: store: SessionStore", "3: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 2, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 1", "1 ← shared 0"]),
					.init(mockedType: "BetaScreen", rootDeclaration: 4, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 2, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 1", "1 ← shared 0"]),
					.init(mockedType: "GammaScreen", rootDeclaration: 5, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 2, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 1", "1 ← shared 0"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesVariantOnlyBetweenWorldsWhoseCallsHandItOneKey_whenWorldsDeclareValueItReadsInOtherForms() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("AlphaScreen", mocked: true, instantiating: [("theme", "Theme"), ("panel", "Panel")]),
					Self.type("BetaScreen", mocked: true, instantiating: [("theme", "LazilyInstantiated<Theme>"), ("panel", "Panel")]),
					Self.type("GammaScreen", mocked: true, instantiating: [("theme", "Theme"), ("panel", "Panel")]),
					Self.type("Panel", instantiating: [("store", "Store")]),
					Self.type("Store", receiving: [("theme", "Theme")]),
					Self.type("Theme"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `store` reads `theme` from above, which `AlphaScreen` and `GammaScreen` declare by value and `BetaScreen` lazily:
		// their calls of `store` hand it two keys, so the shared graph holds two variants of it, the first of which both
		// worlds that declare `theme` by value call.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 7,
				sharedDeclarationCount: 1,
				sharedVariantCount: 2,
				shareableDeclarations: ["1: theme: Theme", "2: panel: Panel", "3: store: Store", "5: theme: LazilyInstantiated<Theme>"],
				differences: [],
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 3, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 2"]),
					.init(mockedType: "BetaScreen", rootDeclaration: 4, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 3, frontierDeclarationCount: 1, sharedVariantsCalled: [1], sharedDeclarationParents: ["0 ← top 2"]),
					.init(mockedType: "GammaScreen", rootDeclaration: 6, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 3, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 2"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsDeclarationInTopGraphOnlyOfWorldWhoseRootBuildsIt_whenAnotherWorldBuildsItDeeper() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("AlphaScreen", mocked: true, instantiating: [("panel", "Panel")]),
					Self.type("BetaScreen", mocked: true, instantiating: [("store", "SessionStore")]),
					Self.type("Panel", instantiating: [("store", "SessionStore")]),
					Self.type("SessionStore", instantiating: [("clock", "Clock")]),
					Self.type("Clock"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `store` is shareable: `AlphaScreen`'s world calls it from `panel`, while `BetaScreen`'s root builds it itself and
		// calls the shared `clock` from it.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 5,
				sharedDeclarationCount: 2,
				sharedVariantCount: 2,
				shareableDeclarations: ["1: panel: Panel", "2: store: SessionStore", "3: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 2, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 1", "1 ← shared 0"]),
					.init(mockedType: "BetaScreen", rootDeclaration: 4, declarationCount: 3, shareableDeclarationCount: 2, topDeclarationCount: 2, frontierDeclarationCount: 1, sharedVariantsCalled: [1], sharedDeclarationParents: ["1 ← top 2"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesDeclarationsOnBeneathAndReachingCycleUnshareable_whenSubtreeHoldsCycle() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("Dashboard", mocked: true, instantiating: [("holder", "Holder"), ("banner", "Banner")]),
					Self.type("Holder", instantiating: [("editor", "Editor")]),
					Self.type("Editor", instantiating: [("previewBuilder", "Instantiator<Preview>"), ("chart", "Chart")]),
					Self.type("Preview", instantiating: [("editor", "Editor")]),
					Self.type("Chart", instantiating: [("legend", "Legend")]),
					Self.type("Legend"),
					Self.type("Banner", instantiating: [("icon", "Icon")]),
					Self.type("Icon", instantiating: [("badge", "Badge")]),
					Self.type("Badge"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `editor` and `previewBuilder` form the cycle, which `holder` reaches; `chart` and `legend` are beneath it. Only
		// `banner`'s subtree is shareable, and the world calls `icon` from `banner`, which its root builds.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 9,
				sharedDeclarationCount: 2,
				sharedVariantCount: 2,
				shareableDeclarations: ["6: banner: Banner", "7: icon: Icon", "8: badge: Badge"],
				differences: [],
				worlds: [
					.init(mockedType: "Dashboard", rootDeclaration: 0, declarationCount: 9, shareableDeclarationCount: 3, topDeclarationCount: 7, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 6", "1 ← shared 0"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesNothingOfWorld_whenPublicMockHoldsHole() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Screen: Instantiable {
					    public init(panel: Panel, banner: Banner) {
					        self.panel = panel
					        self.banner = banner
					    }

					    @Instantiated let panel: Panel
					    @Instantiated let banner: Banner
					}
					""",
					Self.type("Panel", instantiating: [("gadget", "Gadget")]),
					"""
					public struct Gadget {}
					""",
					Self.type("Banner", instantiating: [("icon", "Icon")]),
					Self.type("Icon"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Nothing the module sees fulfills `gadget`, so the public mock's world holds it as a hole, a place its mock's
		// builder fills; whether a child starts as a carrier is a fact of its type over the whole world, so not even
		// `banner`'s subtree, which reaches no hole, is shared.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 5,
				sharedDeclarationCount: 0,
				sharedVariantCount: 0,
				shareableDeclarations: [],
				differences: [],
				worlds: [
					.init(mockedType: "Screen", rootDeclaration: 0, declarationCount: 5, shareableDeclarationCount: 0, topDeclarationCount: 5, frontierDeclarationCount: 0, sharedVariantsCalled: [], sharedDeclarationParents: []),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsLoopMembersUnshareable_whenBuilderLoopIsAboveSharedSubtree() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("Root", mocked: true, instantiating: [("alphaBuilder", "Instantiator<Alpha>"), ("betaBuilder", "Instantiator<Beta>")]),
					Self.type("Alpha", instantiating: [("helper", "Helper")], receiving: [("betaBuilder", "Instantiator<Beta>")]),
					Self.type("Beta", receiving: [("alphaBuilder", "Instantiator<Alpha>")]),
					Self.type("Other", mocked: true, instantiating: [("panel", "Panel")]),
					Self.type("Panel", instantiating: [("helper", "Helper")]),
					Self.type("Helper", instantiating: [("clock", "Clock")]),
					Self.type("Clock"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `alphaBuilder` and `betaBuilder` are a loop of builders beneath `Root`, so neither is shareable; `helper` and
		// `clock`, merely beneath `alphaBuilder` and reading nothing a member rebinds, are the declarations `Other`'s world
		// calls from `panel`, and `Root`'s calls from `alphaBuilder`.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 7,
				sharedDeclarationCount: 2,
				sharedVariantCount: 2,
				shareableDeclarations: ["1: panel: Panel", "2: helper: Helper", "3: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "Other", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 2, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 1", "1 ← shared 0"]),
					.init(mockedType: "Root", rootDeclaration: 4, declarationCount: 5, shareableDeclarationCount: 2, topDeclarationCount: 3, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 5", "1 ← shared 0"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesFillAndCallUnshareable_whenMockCallsAnotherModulesPublicMock() async throws {
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

					@Instantiable
					public final class Page: Instantiable {
					    public init(panel: Panel) { self.panel = panel }
					    @Instantiated let panel: Panel
					}

					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    public init(page: Page) { self.page = page }
					    @Instantiated let page: Page
					}
					"""], dependencies: ["Feature"], activeCompilationConditions: ["DEBUG"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		// `Feature`'s run: `api` is a hole of `Panel`'s public mock. `App`'s run: `Root`'s mock calls `Panel`'s from `page`,
		// passing a fill that builds `LiveApi`, which reads the scope of the call, so the call, the fill and `page` are built
		// per world, and only `clock`, beneath the fill, is shareable.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 2,
				sharedDeclarationCount: 0,
				sharedVariantCount: 0,
				shareableDeclarations: [],
				differences: [],
				worlds: [
					.init(mockedType: "Panel", rootDeclaration: 0, declarationCount: 2, shareableDeclarationCount: 0, topDeclarationCount: 2, frontierDeclarationCount: 0, sharedVariantsCalled: [], sharedDeclarationParents: []),
				],
			),
			MockWorldsTableReport(
				declarationCount: 5,
				sharedDeclarationCount: 1,
				sharedVariantCount: 1,
				shareableDeclarations: ["4: clock: Clock"],
				differences: [],
				worlds: [
					.init(mockedType: "Root", rootDeclaration: 0, declarationCount: 5, shareableDeclarationCount: 1, topDeclarationCount: 4, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 3"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesDeclarationUnshareable_whenItsSubtreeReceivesOnlyIfAvailableLabelMockRootMayPin() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("Screen", mocked: true, instantiating: [("page", "Page")]),
					Self.type("Page", instantiating: [("panel", "Panel")]),
					Self.type("Panel", instantiating: [("session", "Session"), ("widget", "Widget"), ("feed", "Feed")]),
					Self.type("Widget", receivingOnlyIfAvailable: [("session", "Session")]),
					Self.type("Feed", receiving: [("session", "Session")]),
					Self.type("Session"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `feed` requires `session` and `widget` receives it only if available, so a mock root may pin a receive of it:
		// `widget`'s mock read is answered by a world's pins, so `widget` and everything above it, `panel` and `page`, are
		// built per world. `feed` and `session` are shareable, and the world calls each from `panel`, table ID 2.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 6,
				sharedDeclarationCount: 2,
				sharedVariantCount: 2,
				shareableDeclarations: ["3: session: Session", "5: feed: Feed"],
				differences: [],
				worlds: [
					.init(mockedType: "Screen", rootDeclaration: 0, declarationCount: 6, shareableDeclarationCount: 2, topDeclarationCount: 4, frontierDeclarationCount: 2, sharedVariantsCalled: [0, 1], sharedDeclarationParents: ["0 ← top 2", "1 ← top 2"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesDeclarationUnshareable_whenItReceivesOnlyIfAvailableLabelModuleDeclaresLazily() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("Screen", mocked: true, instantiating: [("page", "Page")]),
					Self.type("Page", instantiating: [("panel", "Panel")]),
					Self.type("Panel", instantiating: [("session", "LazilyInstantiated<Session>"), ("widget", "Widget")]),
					Self.type("Widget", receivingOnlyIfAvailable: [("session", "Session")]),
					Self.type("Session"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `widget` receives `session` only if available, which `panel` declares lazily: what a `nil` answer keys as there
		// is folded over the world's calls, so `widget` and everything above it are built per world, and only `session`
		// is shareable.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 5,
				sharedDeclarationCount: 1,
				sharedVariantCount: 1,
				shareableDeclarations: ["3: session: LazilyInstantiated<Session>"],
				differences: [],
				worlds: [
					.init(mockedType: "Screen", rootDeclaration: 0, declarationCount: 5, shareableDeclarationCount: 1, topDeclarationCount: 4, frontierDeclarationCount: 1, sharedVariantsCalled: [0], sharedDeclarationParents: ["0 ← top 2"]),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootsChildInTopGraph_whenWorldFirstReachesItBeneathAnotherChild() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("Screen", mocked: true, instantiating: [("page", "Page"), ("session", "LazilyInstantiated<Session>"), ("clock", "Clock")]),
					Self.type("Page", instantiating: [("clock", "Clock")], receivingOnlyIfAvailable: [("session", "Session")]),
					Self.type("Session"),
					Self.type("Clock"),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `page` receives `session` only if available, which the module declares lazily, so it is built per world. The walk
		// first reaches the shareable `clock` beneath `page`, but the root builds `clock` itself too, so the world keeps it
		// in its own graph, and calls nothing in the shared one.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 4,
				sharedDeclarationCount: 0,
				sharedVariantCount: 0,
				shareableDeclarations: ["2: clock: Clock", "3: session: LazilyInstantiated<Session>"],
				differences: [],
				worlds: [
					.init(mockedType: "Screen", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 2, topDeclarationCount: 4, frontierDeclarationCount: 0, sharedVariantsCalled: [], sharedDeclarationParents: []),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesSameTableInMockRootOrder_whenSourceOrderIsReversed() async throws {
		// Twenty-two mock roots: the even ones build `store`, the odd ones `feed`, each through a `page`, and both build
		// `clock`.
		var declarations = (0..<22).map { index in
			Self.type("Screen" + (index < 10 ? "0" : "") + String(index), mocked: true, instantiating: [index.isMultiple(of: 2) ? ("storePage", "StorePage") : ("feedPage", "FeedPage")])
		}
		declarations.append(Self.type("StorePage", instantiating: [("store", "Store")]))
		declarations.append(Self.type("FeedPage", instantiating: [("feed", "Feed")]))
		declarations.append(Self.type("Store", instantiating: [("clock", "Clock")]))
		declarations.append(Self.type("Feed", instantiating: [("clock", "Clock")]))
		declarations.append(Self.type("Clock"))
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
		// The first world meets its root, `storePage`, `store` and `clock`, the second its root, `feedPage` and `feed`, and
		// every later world only its root, in the order the mock roots are lowered.
		var worlds = [MockWorldsTableReport.World]()
		for index in 0..<22 {
			let rootDeclaration = switch index {
			case 0: 0
			case 1: 4
			default: index + 5
			}
			worlds.append(.init(mockedType: "Screen" + (index < 10 ? "0" : "") + String(index), rootDeclaration: rootDeclaration, declarationCount: 4, shareableDeclarationCount: 3, topDeclarationCount: 2, frontierDeclarationCount: 1, sharedVariantsCalled: [index.isMultiple(of: 2) ? 0 : 1], sharedDeclarationParents: index.isMultiple(of: 2) ? ["0 ← top 1", "1 ← shared 0"] : ["2 ← top 5", "1 ← shared 2"]))
		}
		let expected = [MockWorldsTableReport(
			declarationCount: 27,
			sharedDeclarationCount: 3,
			sharedVariantCount: 3,
			shareableDeclarations: ["1: storePage: StorePage", "2: store: Store", "3: clock: Clock", "5: feedPage: FeedPage", "6: feed: Feed"],
			differences: [],
			worlds: worlds,
		)]
		#expect(reports == [expected, expected])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The source of an `@Instantiable` struct `name` that instantiates, receives and receives only if available the given
	/// labels and types, with a mock generated where `mocked` holds.
	private static func type(
		_ name: String,
		mocked: Bool = false,
		instantiating instantiated: [(label: String, type: String)] = [],
		receiving received: [(label: String, type: String)] = [],
		receivingOnlyIfAvailable receivedOnlyIfAvailable: [(label: String, type: String)] = [],
	) -> String {
		var parameters = [String]()
		var assignments = [String]()
		var properties = [String]()
		for (label, type) in instantiated {
			parameters.append("\(label): \(type)")
			assignments.append("        self.\(label) = \(label)")
			properties.append("    @Instantiated let \(label): \(type)")
		}
		for (label, type) in received {
			parameters.append("\(label): \(type)")
			assignments.append("        self.\(label) = \(label)")
			properties.append("    @Received let \(label): \(type)")
		}
		for (label, type) in receivedOnlyIfAvailable {
			parameters.append("\(label): \(type)?")
			assignments.append("        self.\(label) = \(label)")
			properties.append("    @Received(onlyIfAvailable: true) let \(label): \(type)?")
		}
		var lines = [
			mocked ? "@Instantiable(generateMock: true)" : "@Instantiable",
			"public struct \(name): Instantiable {",
		]
		if parameters.isEmpty {
			lines.append("    public init() {}")
		} else {
			lines.append("    public init(\(parameters.joined(separator: ", "))) {")
			lines += assignments
			lines.append("    }")
			lines.append("")
			lines += properties
		}
		lines.append("}")
		return lines.joined(separator: "\n")
	}

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
