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
@testable import SafeDIToolTestSupport

/// A calling mock – a generated `mock()` whose tree calls another module's public mock – mirrors its production tree
/// (contract rule 7's calling-mock clause): it fills a place wherever the same tree built for production fills it, reports
/// production's error wherever production reports one, and passes a place up only for a permanent reason. The production
/// twin is the same sources with the caller declared `@Instantiable(generateDependencyTree: true)`.
/// `GraphFuzzerCallingMockCheck` judges a graph; `GraphFuzzerCallingMockDraw` draws ten graphs of each cell (a shape, an
/// internal or `.public` caller, a plain or deferred place). Main fails every shape cell, each a known issue the mock work
/// empties.
struct SafeDIToolGraphFuzzerCallingMockTests {
	// MARK: Hand-written shapes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlaceFromCallersOwnValue_whenItsTwinFillsIt() async throws {
		let graph = Self.innerSeamGraph(named: "the caller's own value", tests: """
		import SafeDI
		import In
		import Feat

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init(db: Db) { self.db = db }
		    @Received let db: Db
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(db: Db, inner: Inner) { self.db = db; self.inner = inner }
		    @Instantiated let db: Db
		    @Instantiated let inner: Inner
		}
		""", expectedTwinErrorSite: nil)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		withKnownIssue("\(Self.callersOwnValueReason)") {
			#expect(result.failure == nil)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlace_whenFillReadsNothingBesideCallersOwnValue() async throws {
		let graph = Self.innerSeamGraph(named: "a fill reading nothing beside the caller's own value", tests: """
		import SafeDI
		import In
		import Feat

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init() {}
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(db: Db, inner: Inner) { self.db = db; self.inner = inner }
		    @Instantiated let db: Db
		    @Instantiated let inner: Inner
		}
		""", expectedTwinErrorSite: nil)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.failure == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlace_whenFillReadsNothingThroughOuterSeam() async throws {
		let graph = Self.innerSeamGraph(named: "a fill reading nothing through the outer seam", tests: """
		import SafeDI
		import In
		import Feat

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init() {}
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(f: Feature) { self.f = f }
		    @Instantiated let f: Feature
		}
		""", expectedTwinErrorSite: nil)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.failure == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsError_whenFillReceivesValueOfOuterSeam() async throws {
		let graph = Self.innerSeamGraph(named: "a fill receiving the outer seam's value", tests: """
		import SafeDI
		import In
		import Feat

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init(db: Db) { self.db = db }
		    @Received let db: Db
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(f: Feature) { self.f = f }
		    @Instantiated let f: Feature
		}
		""", expectedTwinErrorSite: ("Tests/TestsTypes.swift", "@Received let db: Db"))

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "Tests/TestsTypes.swift", line: 8, declaration: "@Received let db: Db"),
			GraphFuzzerDiagnosticSite(severity: "note", file: "Feat/FeatTypes.swift", line: 12, declaration: "@Instantiated public let db: Db"),
		])
		withKnownIssue("\(Self.outerSeamValueReason)") {
			#expect(result.failure == nil)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsError_whenAppOnlyScreenIsInLoopOfSeamsScreens() async throws {
		let graph = GraphFuzzerCallingMockGraph(
			handWrittenNamed: "an app-only screen in a loop of the seam's screens",
			mockFiles: [
				.init(module: "Feature", dependencies: [], content: """
				import SafeDI

				public protocol FeedPage {}
				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) { self.name = name }
				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) { self.user = user; self.settingsBuilder = settingsBuilder }
				    @Received private let user: User
				    @Received private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}

				@Instantiable(generateDependencyTree: true, generateMock: .public)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) { self.user = user; self.feedBuilder = feedBuilder; self.settingsBuilder = settingsBuilder }
				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated(fulfilledByType: "AppSettings") private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}
				"""),
				.init(module: "App", dependencies: ["Feature"], content: """
				import SafeDI
				import Feature

				@Instantiable
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>) { self.feedBuilder = feedBuilder }
				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				}

				@Instantiable(generateMock: true)
				final class Host: Instantiable {
				    init(signedInBuilder: Instantiator<SignedIn>) { self.signedInBuilder = signedInBuilder }
				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				"""),
			],
			callerTypeName: "Host",
			callerIsPublic: false,
			expectedTwinErrorSite: ("App/AppTypes.swift", "@Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>"),
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "App/AppTypes.swift", line: 7, declaration: "@Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>"),
			GraphFuzzerDiagnosticSite(severity: "note", file: "Feature/FeatureTypes.swift", line: 22, declaration: "@Instantiated(fulfilledByType: \"Feed\") private let feedBuilder: ErasedInstantiator<(), any FeedPage>"),
		])
		withKnownIssue("\(Self.appOnlyScreenInLoopReason)") {
			#expect(result.failure == nil)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsError_whenFillReadsValueOfLevelBetweenBuildsOfSeam() async throws {
		let graph = Self.seamBuiltAgainGraph

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "App/AppTypes.swift", line: 7, declaration: "@Received let logger: Logger"),
			GraphFuzzerDiagnosticSite(severity: "note", file: "Feature/FeatureTypes.swift", line: 20, declaration: "@Instantiated let logger: Logger"),
		])
		withKnownIssue("\(Self.seamBuiltAgainReason)") {
			#expect(result.failure == nil)
		}
	}

	/// Main's calling mock fills the place a seam built again passes up with `LiveGadget(logger: logger)` from the caller's
	/// own `logger`, one level away from the builder function it builds in, and its generated code does not compile.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_compiles_whenFillReadsValueOfLevelBetweenBuildsOfSeam() async throws {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamBuiltAgainGraph.modules(.mock),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)

		withKnownIssue("\(Self.seamBuiltAgainReason)") {
			#expect(output.compilation?.failure == nil)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsError_whenFillReceivesSiblingThatReceivesInnerSeamsBuilder() async throws {
		let graph = GraphFuzzerCallingMockGraph(
			handWrittenNamed: "a loop through the inner seam's builder",
			mockFiles: [
				.init(module: "In", dependencies: [], content: Self.innerModule),
				.init(module: "Feat", dependencies: ["In"], content: """
				import SafeDI
				import In

				@Instantiable(generateDependencyTree: true, generateMock: .public)
				public final class Feature: Instantiable {
				    init(innerBuilder: Instantiator<Inner>, s: S) { self.innerBuilder = innerBuilder; self.s = s }
				    @Instantiated public let innerBuilder: Instantiator<Inner>
				    @Instantiated public let s: S
				}

				@Instantiable
				public final class S: Instantiable {
				    init(innerBuilder: Instantiator<Inner>) { self.innerBuilder = innerBuilder }
				    @Received let innerBuilder: Instantiator<Inner>
				}
				"""),
				.init(module: "Tests", dependencies: ["In", "Feat"], content: """
				import SafeDI
				import In
				import Feat

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				final class Fake: Api, Instantiable {
				    init(s: S) { self.s = s }
				    @Received let s: S
				}

				@Instantiable(generateMock: true)
				final class Host: Instantiable {
				    init(f: Feature) { self.f = f }
				    @Instantiated let f: Feature
				}
				"""),
			],
			callerTypeName: "Host",
			callerIsPublic: false,
			expectedTwinErrorSite: ("Feat/FeatTypes.swift", "@Received let innerBuilder: Instantiator<Inner>"),
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "Feat/FeatTypes.swift", line: 14, declaration: "@Received let innerBuilder: Instantiator<Inner>"),
		])
		withKnownIssue("\(Self.loopThroughInnerSeamBuilderReason)") {
			#expect(result.failure == nil)
		}
	}

	// MARK: The comparator

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func diagnosticSites_match_whenOneTwinErrorIsReportedByTwoRuns() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 0)

		let first = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 0)
		let second = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 0)

		#expect(first.twinSites != nil)
		#expect(first.twinSites == second.twinSites)
		// The two runs write their fixtures under different directories, so the diagnostics' text differs.
		#expect(first.twinDiagnostics != second.twinDiagnostics)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func diagnosticSites_differ_whenTwinsOfTwoShapesReportTheirErrors() async throws {
		var sitesByShape = [GraphFuzzerCallingMockShape: [[GraphFuzzerDiagnosticSite]?]]()
		for seed in UInt64(0)..<UInt64(GraphFuzzerCallingMockCell.drawnCells.count) where GraphFuzzerCallingMockDraw(seed: seed).cell.shape.twinRejects {
			let shape = GraphFuzzerCallingMockDraw(seed: seed).cell.shape
			await sitesByShape[shape, default: []].append(try GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockDraw(seed: seed).graph, seed: seed).twinSites)
		}

		#expect(sitesByShape.keys.sorted() == [.outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder])
		#expect(sitesByShape.values.allSatisfy { $0.allSatisfy { $0 != nil } })
		for (shape, sites) in sitesByShape {
			for (otherShape, otherSites) in sitesByShape where otherShape != shape {
				#expect(Set(sites).isDisjoint(with: otherSites))
			}
		}
	}

	@Test
	func diagnosticSites_ignoreMessageText_andTellLinesAndDeclarationsApart() {
		let content = ["Tests/TestsTypes.swift": "import SafeDI\n\nfinal class Fake {\n    @Received let db: Db\n    @Received let id: Int\n}"]
		func sites(_ diagnostics: String) -> [GraphFuzzerDiagnosticSite] {
			GraphFuzzerDiagnosticSite.sites(inDiagnostics: diagnostics, contentByRelativePath: content)
		}

		#expect(sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") == sites("/b/Sources/Tests/TestsTypes.swift:4:5: error: another remedy"))
		#expect(sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") != sites("/a/Sources/Tests/TestsTypes.swift:5:5: error: one remedy"))
		#expect(sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") != sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy\n/a/Sources/Tests/TestsTypes.swift:5:5: note: here"))
		#expect(sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "Tests/TestsTypes.swift", line: 4, declaration: "@Received let db: Db"),
		])
	}

	// MARK: The cells

	/// Every drawn graph gives its cell's intended twin outcome, ten graphs per cell, and the calling mock mirrors its twin
	/// or fails as its cell's known issue lists. Prints the count of each pass-up reason.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMockCells_mirrorProductionTwin_inEveryDrawnGraph() async throws {
		let results = try await withThrowingTaskGroup(of: (UInt64, GraphFuzzerCallingMockResult).self) { group in
			var results = [UInt64: GraphFuzzerCallingMockResult]()
			var seeds = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).makeIterator()
			for _ in 0..<8 {
				guard let seed = seeds.next() else { break }
				group.addTask { await (seed, try GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockDraw(seed: seed).graph, seed: seed)) }
			}
			while let (seed, result) = try await group.next() {
				results[seed] = result
				if let next = seeds.next() {
					group.addTask { await (next, try GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockDraw(seed: next).graph, seed: next)) }
				}
			}
			return results
		}

		var intendedGraphsByCell = [GraphFuzzerCallingMockCell: Int]()
		var passUpCountsByReason = [String: Int]()
		for seed in UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount) {
			let draw = GraphFuzzerCallingMockDraw(seed: seed)
			guard let result = results[seed] else {
				Issue.record("No result for seed \(seed)")
				continue
			}
			if let drawingDefect = result.drawingDefect {
				Issue.record("Drawing defect: \(drawingDefect)")
			} else {
				intendedGraphsByCell[draw.cell, default: 0] += 1
			}
			for passUp in result.passUps {
				passUpCountsByReason[passUp.reason?.rawValue ?? "unclassified", default: 0] += 1
			}
			let knownIssue = Self.callingMockKnownIssues.first { $0.seeds.contains(seed) }
			switch (result.failure, knownIssue) {
			case (nil, nil):
				break
			case let (nil, knownIssue?):
				Issue.record("Stale known issue: calling-mock seed \(seed) (\(draw.cell)) passes, so remove it from the entry “\(knownIssue.reason)”")
			case let (failure?, nil):
				Issue.record("Calling-mock seed \(seed) (\(draw.cell)): \(failure.kind.rawValue). \(failure.details)\n\(Self.description(of: draw.graph))")
			case let (failure?, knownIssue?):
				if knownIssue.matches(failure) {
					withKnownIssue("\(knownIssue.reason)") {
						Issue.record("Calling-mock seed \(seed) (\(draw.cell)): \(failure.kind.rawValue). \(failure.details)")
					}
				} else {
					Issue.record("Calling-mock seed \(seed) (\(draw.cell)) fails otherwise than its known issue lists: \(failure.kind.rawValue). \(failure.details)")
				}
			}
		}
		print("calling-mock pass-ups \(GraphFuzzerCallingMockPassUpReason.allCases.map { "\($0.rawValue)=\(passUpCountsByReason[$0.rawValue, default: 0])" }.joined(separator: " ")) unclassified=\(passUpCountsByReason["unclassified", default: 0])")

		#expect(GraphFuzzerCallingMockCell.drawnCells.filter { intendedGraphsByCell[$0, default: 0] < 10 } == [])
	}

	@Test
	func callingMockCells_areAllCellsButThoseNoGraphFits() {
		#expect(GraphFuzzerCallingMockCell.all.count == 28)
		#expect(GraphFuzzerCallingMockCell.all.filter { $0.impossibility != nil }.map(\.description) == [
			"appOnlyScreenInLoop/internal/plain",
			"appOnlyScreenInLoop/public/plain",
		])
		#expect(Self.callingMockCorpusSeedCount == GraphFuzzerCallingMockCell.drawnCells.count * 10)
	}

	@Test
	func callingMockKnownIssues_listEachShapeCellsSeeds_inIncreasingOrder() {
		#expect(SafeDIToolGraphFuzzerTests.knownIssueListProblems(Self.callingMockKnownIssues, corpusSeedCount: Self.callingMockCorpusSeedCount) == [])
		for knownIssue in Self.callingMockKnownIssues {
			let cells = Set(knownIssue.seeds.map { GraphFuzzerCallingMockDraw(seed: $0).cell })
			#expect(cells.count == 1)
			#expect(knownIssue.seeds.count == 10)
		}
		let listedCells = Set(Self.callingMockKnownIssues.flatMap { $0.seeds.map { GraphFuzzerCallingMockDraw(seed: $0).cell } })
		#expect(listedCells == Set(GraphFuzzerCallingMockCell.drawnCells.filter { !$0.shape.isControl || ($0.shape == .implementationReceivesWhatNothingProvides && $0.callerIsPublic) }))
	}

	// MARK: The public mock corpus

	/// Report only: over the public mock corpus's seeds, the mocked consumers whose production twin reports one of the four
	/// shape errors while the tool accepts the graph, for the rule for mirrored rejections. Set
	/// `SAFEDI_GRAPH_FUZZER_CALLING_MOCK_TWIN_REPORT` to run it; it prints its count and seeds and fails nothing.
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_GRAPH_FUZZER_CALLING_MOCK_TWIN_REPORT"] != nil))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func publicMockCorpusCallingMocks_reportTwinsShapeErrors() async throws {
		var findings = [GraphFuzzerCallingMockTwinReport.Finding]()
		for seed in UInt64(0)..<UInt64(SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount) {
			findings += try await GraphFuzzerCallingMockTwinReport.findings(in: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		}
		let shapeFindings = findings.filter { $0.shape != nil }
		print("calling-mock twins shape-errors=\(shapeFindings.count) seeds=\(Set(shapeFindings.map(\.seed)).sorted()) other-errors=\(findings.count - shapeFindings.count)")
		for finding in findings {
			print("calling-mock twin \(finding)")
		}
	}

	// MARK: Fixtures

	private static let innerModule = """
	import SafeDI

	public protocol Api: AnyObject {}

	@Instantiable(generateDependencyTree: true, generateMock: .public)
	public final class Inner: Instantiable {
	    init(api: any Api) { self.api = api }
	    @Instantiated public let api: any Api
	}
	"""

	private static let featureModule = """
	import SafeDI
	import In

	@Instantiable
	public final class Db: Instantiable {
	    public init() {}
	}

	@Instantiable(generateDependencyTree: true, generateMock: .public)
	public final class Feature: Instantiable {
	    init(db: Db, inner: Inner) { self.db = db; self.inner = inner }
	    @Instantiated public let db: Db
	    @Instantiated public let inner: Inner
	}
	"""

	/// `Inner`'s hole in module `In`, `Feature` calling it in module `Feat`, and `tests` in module `Tests`.
	private static func innerSeamGraph(named name: String, tests: String, expectedTwinErrorSite: (file: String, declaration: String)?) -> GraphFuzzerCallingMockGraph {
		GraphFuzzerCallingMockGraph(
			handWrittenNamed: name,
			mockFiles: [
				.init(module: "In", dependencies: [], content: innerModule),
				.init(module: "Feat", dependencies: ["In"], content: featureModule),
				.init(module: "Tests", dependencies: ["In", "Feat"], content: tests),
			],
			callerTypeName: "Host",
			callerIsPublic: false,
			expectedTwinErrorSite: expectedTwinErrorSite,
		)
	}

	private static let seamBuiltAgainGraph = GraphFuzzerCallingMockGraph(
		handWrittenNamed: "a seam built again",
		mockFiles: [
			.init(module: "Feature", dependencies: [], content: """
			import SafeDI

			public protocol Gadget {}

			@Instantiable
			public final class Logger: Instantiable {
			    public init() {}
			}

			@Instantiable(generateDependencyTree: true, generateMock: .public)
			public final class Service: Instantiable {
			    init(gadget: any Gadget, xBuilder: Instantiator<X>) { self.gadget = gadget; self.xBuilder = xBuilder }
			    @Instantiated let gadget: any Gadget
			    @Instantiated let xBuilder: Instantiator<X>
			}

			@Instantiable
			public final class X: Instantiable {
			    init(logger: Logger, serviceBuilder: Instantiator<Service>) { self.logger = logger; self.serviceBuilder = serviceBuilder }
			    @Instantiated let logger: Logger
			    @Instantiated let serviceBuilder: Instantiator<Service>
			}
			"""),
			.init(module: "App", dependencies: ["Feature"], content: """
			import SafeDI
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [(any Gadget).self])
			final class LiveGadget: Gadget, Instantiable {
			    init(logger: Logger) { self.logger = logger }
			    @Received let logger: Logger
			}

			@Instantiable(generateMock: true)
			final class Host: Instantiable {
			    init(logger: Logger, service: Service) { self.logger = logger; self.service = service }
			    @Instantiated let logger: Logger
			    @Instantiated let service: Service
			}
			"""),
		],
		callerTypeName: "Host",
		callerIsPublic: false,
		expectedTwinErrorSite: ("App/AppTypes.swift", "@Received let logger: Logger"),
	)

	private static func description(of graph: GraphFuzzerCallingMockGraph) -> String {
		graph.mockFiles.map { "// module \($0.module)\n\($0.content)" }.joined(separator: "\n\n")
	}

	// MARK: Known issues

	/// Ten graphs per drawn cell: seed `s` draws `GraphFuzzerCallingMockCell.drawnCells[s % 26]`.
	static let callingMockCorpusSeedCount = 260

	static let outerSeamValueReason = "A calling mock fills, or passes up as a required builder, a place whose fill receives a value an outer seam builds, where its production twin reports that the outer seam passes the builder on from its own caller; the mock work makes the mock report the same error"
	static let appOnlyScreenInLoopReason = "A calling mock passes up the builder of an app-only screen in a loop of the seam's screens, where its production twin reports that the seam's tree builds the screen's received builder only after it calls the screen's builder; the mock work makes the mock report the same error"
	static let seamBuiltAgainReason = "A calling mock fills or passes up a place of a seam its tree builds again, whose fill reads a value of the level in between, where its production twin reports that the second build passes the builder on unchanged; main's internal mock fills it from the caller's own value and does not compile; the mock work makes the mock report the same error"
	static let loopThroughInnerSeamBuilderReason = "A calling mock passes up a place whose fill receives a sibling that receives the inner seam's builder, where its production twin reports the loop as a dependency cycle; the mock work makes the mock report the same error"
	static let callersOwnValueReason = "A calling mock passes up as a required builder a place whose fill receives a value the caller itself builds, where its production twin fills the place from that value; the mock work makes the mock fill it"
	static let publicCallerPassesUpWhatItsTwinFillsReason = "A `.public` calling mock passes up a place whose fill receives a value nothing in its tree provides, where its production twin takes that value as a parameter and fills the place; no permanent reason explains it (reason 2 is an internal mock's); awaiting a ruling"

	/// One entry per cell that fails on main, with the cell's ten seeds.
	static let callingMockKnownIssues: [GraphFuzzerKnownIssue] = [
		// outerSeamValue/internal/plain
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [0, 26, 52, 78, 104, 130, 156, 182, 208, 234]),
		// outerSeamValue/internal/deferred
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [1, 27, 53, 79, 105, 131, 157, 183, 209, 235]),
		// outerSeamValue/public/plain
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [2, 28, 54, 80, 106, 132, 158, 184, 210, 236]),
		// outerSeamValue/public/deferred
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [3, 29, 55, 81, 107, 133, 159, 185, 211, 237]),
		// appOnlyScreenInLoop/internal/deferred
		GraphFuzzerKnownIssue(reason: appOnlyScreenInLoopReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [4, 30, 56, 82, 108, 134, 160, 186, 212, 238]),
		// appOnlyScreenInLoop/public/deferred
		GraphFuzzerKnownIssue(reason: appOnlyScreenInLoopReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [5, 31, 57, 83, 109, 135, 161, 187, 213, 239]),
		// seamBuiltAgain/internal/plain
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [6, 32, 58, 84, 110, 136, 162, 188, 214, 240]),
		// seamBuiltAgain/internal/deferred
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [7, 33, 59, 85, 111, 137, 163, 189, 215, 241]),
		// seamBuiltAgain/public/plain
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [8, 34, 60, 86, 112, 138, 164, 190, 216, 242]),
		// seamBuiltAgain/public/deferred
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [9, 35, 61, 87, 113, 139, 165, 191, 217, 243]),
		// loopThroughInnerSeamBuilder/internal/plain
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [10, 36, 62, 88, 114, 140, 166, 192, 218, 244]),
		// loopThroughInnerSeamBuilder/internal/deferred
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [11, 37, 63, 89, 115, 141, 167, 193, 219, 245]),
		// loopThroughInnerSeamBuilder/public/plain
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [12, 38, 64, 90, 116, 142, 168, 194, 220, 246]),
		// loopThroughInnerSeamBuilder/public/deferred
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [13, 39, 65, 91, 117, 143, 169, 195, 221, 247]),
		// callersOwnValue/internal/plain
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [14, 40, 66, 92, 118, 144, 170, 196, 222, 248]),
		// callersOwnValue/internal/deferred
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [15, 41, 67, 93, 119, 145, 171, 197, 223, 249]),
		// callersOwnValue/public/plain
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [16, 42, 68, 94, 120, 146, 172, 198, 224, 250]),
		// callersOwnValue/public/deferred
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [17, 43, 69, 95, 121, 147, 173, 199, 225, 251]),
		// implementationReceivesWhatNothingProvides/public/plain
		GraphFuzzerKnownIssue(reason: publicCallerPassesUpWhatItsTwinFillsReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [24, 50, 76, 102, 128, 154, 180, 206, 232, 258]),
		// implementationReceivesWhatNothingProvides/public/deferred
		GraphFuzzerKnownIssue(reason: publicCallerPassesUpWhatItsTwinFillsReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [25, 51, 77, 103, 129, 155, 181, 207, 233, 259]),
	]
}
