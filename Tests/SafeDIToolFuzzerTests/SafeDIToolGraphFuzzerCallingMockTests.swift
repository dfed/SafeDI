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
/// internal or `.public` caller, a plain or deferred place). Main fails every shape cell, each a known issue the change that
/// makes a calling mock mirror its production tree, which lands before 2.3.0, empties.
struct SafeDIToolGraphFuzzerCallingMockTests {
	// MARK: Hand-written shapes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlaceFromCallersOwnValue_whenItsTwinFillsIt() async throws {
		let graph = Self.innerSeamGraph(named: "the caller's own value", tests: """
		import SafeDI
		import InnerModule
		import FeatureModule

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init(database: Database) { self.database = database }
		    @Received let database: Database
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
		    @Instantiated let database: Database
		    @Instantiated let inner: Inner
		}
		""", expectedTwinErrorSite: nil)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.twinInitializerLabels == [])
		withKnownIssue("\(Self.callersOwnValueReason)") {
			#expect(result.failure == nil)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlaceFromValueItTakes_whenItsTwinTakesThatValueAndFillsIt() async throws {
		let graph = GraphFuzzerCallingMockGraph(
			handWrittenNamed: "a fill receiving what nothing builds",
			mockFiles: [
				.init(module: "InnerModule", dependencies: [], content: Self.innerModule),
				.init(module: "FeatureModule", dependencies: ["InnerModule"], content: Self.featureModule),
				.init(module: "Tests", dependencies: ["InnerModule", "FeatureModule"], content: """
				import SafeDI
				import InnerModule
				import FeatureModule

				public struct Token {}

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				final class Fake: Api, Instantiable {
				    init(token: Token) { self.token = token }
				    @Received let token: Token
				}

				@Instantiable(generateMock: true)
				final class Host: Instantiable {
				    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
				    @Instantiated let database: Database
				    @Instantiated let inner: Inner
				}
				"""),
			],
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: ["token"],
			expectedTwinInitializerLabels: ["token"],
			expectedTwinErrorSite: nil,
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.twinInitializerLabels == ["token"])
		withKnownIssue("\(Self.passesUpPlaceItsTwinFillsFromParameterReason)") {
			#expect(result.passUps.isEmpty)
			#expect(result.failure == nil)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlace_whenFillReadsNothingBesideCallersOwnValue() async throws {
		let graph = Self.innerSeamGraph(named: "a fill reading nothing beside the caller's own value", tests: """
		import SafeDI
		import InnerModule
		import FeatureModule

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init() {}
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
		    @Instantiated let database: Database
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
		import InnerModule
		import FeatureModule

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init() {}
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(feature: Feature) { self.feature = feature }
		    @Instantiated let feature: Feature
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
		import InnerModule
		import FeatureModule

		@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
		final class Fake: Api, Instantiable {
		    init(database: Database) { self.database = database }
		    @Received let database: Database
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(feature: Feature) { self.feature = feature }
		    @Instantiated let feature: Feature
		}
		""", expectedTwinErrorSite: ("Tests/TestsTypes.swift", "@Received let database: Database"))

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "Tests/TestsTypes.swift", line: 8, declaration: "@Received let database: Database"),
			GraphFuzzerDiagnosticSite(severity: "note", file: "FeatureModule/FeatureModuleTypes.swift", line: 12, declaration: "@Instantiated public let database: Database"),
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
	func callingMock_reportsTwinsCycle_whenAppOnlyScreenBuiltByValueReceivesBuilderOfScreenThatReceivesIt() async throws {
		let graph = GraphFuzzerCallingMockGraph(
			handWrittenNamed: "an app-only screen built by value in a loop of the seam's screens",
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
				    init(user: User, settings: any SettingsPage) { self.user = user; self.settings = settings }
				    @Received private let user: User
				    @Received private let settings: any SettingsPage
				}

				@Instantiable(generateDependencyTree: true, generateMock: .public)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settings: any SettingsPage) { self.user = user; self.feedBuilder = feedBuilder; self.settings = settings }
				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let settings: any SettingsPage
				}
				"""),
				.init(module: "App", dependencies: ["Feature"], content: """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [(any SettingsPage).self])
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
	/// own `logger`, one level away from the builder function it builds in, and its generated code does not compile. Where
	/// compile verification is off (`SAFEDI_SKIP_COMPILE_CHECK`), `.returningOutcomeOnly` compiles nothing, so the test
	/// does not run there rather than pass for a compile that never ran.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
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

		let compilation = try #require(output.compilation)
		withKnownIssue("\(Self.seamBuiltAgainReason)") {
			#expect(compilation.failure == nil)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsError_whenFillReceivesSiblingThatReceivesInnerSeamsBuilder() async throws {
		let graph = GraphFuzzerCallingMockGraph(
			handWrittenNamed: "a loop through the inner seam's builder",
			mockFiles: [
				.init(module: "InnerModule", dependencies: [], content: Self.innerModule),
				.init(module: "FeatureModule", dependencies: ["InnerModule"], content: """
				import SafeDI
				import InnerModule

				@Instantiable(generateDependencyTree: true, generateMock: .public)
				public final class Feature: Instantiable {
				    init(innerBuilder: Instantiator<Inner>, sibling: Sibling) { self.innerBuilder = innerBuilder; self.sibling = sibling }
				    @Instantiated public let innerBuilder: Instantiator<Inner>
				    @Instantiated public let sibling: Sibling
				}

				@Instantiable
				public final class Sibling: Instantiable {
				    init(innerBuilder: Instantiator<Inner>) { self.innerBuilder = innerBuilder }
				    @Received let innerBuilder: Instantiator<Inner>
				}
				"""),
				.init(module: "Tests", dependencies: ["InnerModule", "FeatureModule"], content: """
				import SafeDI
				import InnerModule
				import FeatureModule

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				final class Fake: Api, Instantiable {
				    init(sibling: Sibling) { self.sibling = sibling }
				    @Received let sibling: Sibling
				}

				@Instantiable(generateMock: true)
				final class Host: Instantiable {
				    init(feature: Feature) { self.feature = feature }
				    @Instantiated let feature: Feature
				}
				"""),
			],
			callerTypeName: "Host",
			callerIsPublic: false,
			expectedTwinErrorSite: ("FeatureModule/FeatureModuleTypes.swift", "@Received let innerBuilder: Instantiator<Inner>"),
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "FeatureModule/FeatureModuleTypes.swift", line: 14, declaration: "@Received let innerBuilder: Instantiator<Inner>"),
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
	func diagnosticSites_match_whenOnlyMessageTextAndDirectoryDiffer() {
		#expect(Self.sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") == Self.sites("/b/Sources/Tests/TestsTypes.swift:4:5: error: another remedy"))
	}

	@Test
	func diagnosticSites_differ_whenErrorIsOnAnotherLine() {
		#expect(Self.sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") != Self.sites("/a/Sources/Tests/TestsTypes.swift:5:5: error: one remedy"))
	}

	@Test
	func diagnosticSites_differ_whenOneRunAddsNote() {
		#expect(Self.sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") != Self.sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy\n/a/Sources/Tests/TestsTypes.swift:5:5: note: here"))
	}

	@Test
	func diagnosticSites_nameModuleFileLineAndDeclaration_whenPathEndsInFixtureFile() {
		#expect(Self.sites("/a/Sources/Tests/TestsTypes.swift:4:5: error: one remedy") == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "Tests/TestsTypes.swift", line: 4, declaration: "@Received let database: Database"),
		])
	}

	private static func sites(_ diagnostics: String) -> [GraphFuzzerDiagnosticSite] {
		GraphFuzzerDiagnosticSite.sites(
			inDiagnostics: diagnostics,
			contentByRelativePath: ["Tests/TestsTypes.swift": "import SafeDI\n\nfinal class Fake {\n    @Received let database: Database\n    @Received let id: Int\n}"],
		)
	}

	// MARK: The check's failures

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsOtherError_whenMockReportsTwinsErrorOnAnotherLine() async throws {
		let twinFiles = Self.seamBuiltAgainGraph.twinFiles
		let mockFiles = twinFiles.enumerated().map { index, file in
			guard index == twinFiles.count - 1 else { return file }
			return GraphFuzzerCallingMockGraph.File(
				module: file.module,
				dependencies: file.dependencies,
				content: file.content.replacingOccurrences(of: "    @Received let logger: Logger", with: "    // A line that moves the error.\n    @Received let logger: Logger"),
			)
		}
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock rejected one line below its twin",
			mockFiles: mockFiles,
			twinFiles: twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: ("App/AppTypes.swift", "@Received let logger: Logger"),
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.failure?.kind == .callingMockReportsOtherErrorThanTwin)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsRejection_whenMockIsRejectedWhereTwinIsAccepted() async throws {
		let rejectedFiles = Self.seamBuiltAgainGraph.twinFiles
		let acceptedFiles = rejectedFiles.map { file in
			GraphFuzzerCallingMockGraph.File(
				module: file.module,
				dependencies: file.dependencies,
				content: file.content.replacingOccurrences(
					of: "    init(logger: Logger) { self.logger = logger }\n    @Received let logger: Logger",
					with: "    init() {}",
				),
			)
		}
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock rejected where its twin is accepted",
			mockFiles: rejectedFiles,
			twinFiles: acceptedFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(acceptedFiles.map(\.content) != rejectedFiles.map(\.content))
		#expect(result.twinHasIntendedOutcome)
		#expect(result.failure?.kind == .callingMockRejectsWhereTwinAccepts)
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
			if draw.cell.shape.isControl {
				#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels, "seed \(seed) (\(draw.cell))")
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
	func drawnCells_coverEveryCell_whenCorpusDrawsTenGraphsPerCell() {
		#expect(GraphFuzzerCallingMockCell.all.count == 28)
		#expect(GraphFuzzerCallingMockCell.drawnCells == GraphFuzzerCallingMockCell.all)
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
		#expect(listedCells == Set(GraphFuzzerCallingMockCell.drawnCells.filter { !$0.shape.isControl }))
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
	import InnerModule

	@Instantiable
	public final class Database: Instantiable {
	    public init() {}
	}

	@Instantiable(generateDependencyTree: true, generateMock: .public)
	public final class Feature: Instantiable {
	    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
	    @Instantiated public let database: Database
	    @Instantiated public let inner: Inner
	}
	"""

	/// `Inner`'s hole in module `InnerModule`, `Feature` calling it in module `FeatureModule`, and `tests` in module `Tests`.
	private static func innerSeamGraph(named name: String, tests: String, expectedTwinErrorSite: (file: String, declaration: String)?) -> GraphFuzzerCallingMockGraph {
		GraphFuzzerCallingMockGraph(
			handWrittenNamed: name,
			mockFiles: [
				.init(module: "InnerModule", dependencies: [], content: innerModule),
				.init(module: "FeatureModule", dependencies: ["InnerModule"], content: featureModule),
				.init(module: "Tests", dependencies: ["InnerModule", "FeatureModule"], content: tests),
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

	/// Ten graphs per drawn cell: seed `s` draws `GraphFuzzerCallingMockCell.drawnCells[s % 28]`.
	static let callingMockCorpusSeedCount = 280

	static let outerSeamValueReason = "A calling mock fills, or passes up as a required builder, a place whose fill receives a value an outer seam builds, where its production twin reports that the outer seam passes the builder on from its own caller; the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock report the same error"
	static let appOnlyScreenInLoopReason = "A calling mock passes up the place of an app-only screen in a loop of the seam's screens, where its production twin reports the loop (the seam's tree builds the screen's received builder only after it calls the screen's builder, or, for a screen built by value, a constant cycle); the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock report the same error"
	static let seamBuiltAgainReason = "A calling mock fills or passes up a place of a seam its tree builds again, whose fill reads a value of the level in between, where its production twin reports that the second build passes the builder on unchanged; main's internal mock fills it from the caller's own value and does not compile; the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock report the same error"
	static let loopThroughInnerSeamBuilderReason = "A calling mock passes up a place whose fill receives a sibling that receives the inner seam's builder, where its production twin reports the loop as a dependency cycle; the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock report the same error"
	static let callersOwnValueReason = "A calling mock passes up as a required builder a place whose fill receives a value the caller itself builds, where its production twin fills the place from that value; the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock fill it"
	static let passesUpPlaceItsTwinFillsFromParameterReason = "A calling mock passes up a place whose fill receives a value nothing in its tree builds, where its production twin takes that value as a parameter and fills the place from it; no permanent reason explains it; the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock fill it"

	/// One entry per cell that fails on main, with the cell's ten seeds.
	static let callingMockKnownIssues: [GraphFuzzerKnownIssue] = [
		// outerSeamValue/internal/plain
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [0, 28, 56, 84, 112, 140, 168, 196, 224, 252]),
		// outerSeamValue/internal/deferred
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [1, 29, 57, 85, 113, 141, 169, 197, 225, 253]),
		// outerSeamValue/public/plain
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [2, 30, 58, 86, 114, 142, 170, 198, 226, 254]),
		// outerSeamValue/public/deferred
		GraphFuzzerKnownIssue(reason: outerSeamValueReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [3, 31, 59, 87, 115, 143, 171, 199, 227, 255]),
		// appOnlyScreenInLoop/internal/plain
		GraphFuzzerKnownIssue(reason: appOnlyScreenInLoopReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [4, 32, 60, 88, 116, 144, 172, 200, 228, 256]),
		// appOnlyScreenInLoop/internal/deferred
		GraphFuzzerKnownIssue(reason: appOnlyScreenInLoopReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [5, 33, 61, 89, 117, 145, 173, 201, 229, 257]),
		// appOnlyScreenInLoop/public/plain
		GraphFuzzerKnownIssue(reason: appOnlyScreenInLoopReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [6, 34, 62, 90, 118, 146, 174, 202, 230, 258]),
		// appOnlyScreenInLoop/public/deferred
		GraphFuzzerKnownIssue(reason: appOnlyScreenInLoopReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [7, 35, 63, 91, 119, 147, 175, 203, 231, 259]),
		// seamBuiltAgain/internal/plain
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [8, 36, 64, 92, 120, 148, 176, 204, 232, 260]),
		// seamBuiltAgain/internal/deferred
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [9, 37, 65, 93, 121, 149, 177, 205, 233, 261]),
		// seamBuiltAgain/public/plain
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [10, 38, 66, 94, 122, 150, 178, 206, 234, 262]),
		// seamBuiltAgain/public/deferred
		GraphFuzzerKnownIssue(reason: seamBuiltAgainReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [11, 39, 67, 95, 123, 151, 179, 207, 235, 263]),
		// loopThroughInnerSeamBuilder/internal/plain
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [12, 40, 68, 96, 124, 152, 180, 208, 236, 264]),
		// loopThroughInnerSeamBuilder/internal/deferred
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [13, 41, 69, 97, 125, 153, 181, 209, 237, 265]),
		// loopThroughInnerSeamBuilder/public/plain
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [14, 42, 70, 98, 126, 154, 182, 210, 238, 266]),
		// loopThroughInnerSeamBuilder/public/deferred
		GraphFuzzerKnownIssue(reason: loopThroughInnerSeamBuilderReason, signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [15, 43, 71, 99, 127, 155, 183, 211, 239, 267]),
		// callersOwnValue/internal/plain
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [16, 44, 72, 100, 128, 156, 184, 212, 240, 268]),
		// callersOwnValue/internal/deferred
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [17, 45, 73, 101, 129, 157, 185, 213, 241, 269]),
		// callersOwnValue/public/plain
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [18, 46, 74, 102, 130, 158, 186, 214, 242, 270]),
		// callersOwnValue/public/deferred
		GraphFuzzerKnownIssue(reason: callersOwnValueReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [19, 47, 75, 103, 131, 159, 187, 215, 243, 271]),
		// implementationReceivesWhatNothingProvides/internal/plain
		GraphFuzzerKnownIssue(reason: passesUpPlaceItsTwinFillsFromParameterReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [24, 52, 80, 108, 136, 164, 192, 220, 248, 276]),
		// implementationReceivesWhatNothingProvides/internal/deferred
		GraphFuzzerKnownIssue(reason: passesUpPlaceItsTwinFillsFromParameterReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [25, 53, 81, 109, 137, 165, 193, 221, 249, 277]),
		// implementationReceivesWhatNothingProvides/public/plain
		GraphFuzzerKnownIssue(reason: passesUpPlaceItsTwinFillsFromParameterReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [26, 54, 82, 110, 138, 166, 194, 222, 250, 278]),
		// implementationReceivesWhatNothingProvides/public/deferred
		GraphFuzzerKnownIssue(reason: passesUpPlaceItsTwinFillsFromParameterReason, signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [27, 55, 83, 111, 139, 167, 195, 223, 251, 279]),
	]
}
