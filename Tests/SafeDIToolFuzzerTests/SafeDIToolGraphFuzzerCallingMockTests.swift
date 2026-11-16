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

		#expect(result.twinInitializerLabels == [])
		Self.expectMirrorsTwin(result, failingOnMainAs: .callingMockPassesUpUnclassifiedPlace, reason: Self.callersOwnValueReason)
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

		#expect(result.twinInitializerLabels == ["token"])
		withKnownIssue("\(Self.passesUpPlaceItsTwinFillsFromParameterReason)") {
			#expect(result.passUps.isEmpty)
		}
		Self.expectMirrorsTwin(result, failingOnMainAs: .callingMockPassesUpUnclassifiedPlace, reason: Self.passesUpPlaceItsTwinFillsFromParameterReason)
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
		Self.expectMirrorsTwin(result, failingOnMainAs: .callingMockAcceptedWhereTwinReportsShapeError, reason: Self.outerSeamValueReason)
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
		Self.expectMirrorsTwin(result, failingOnMainAs: .callingMockAcceptedWhereTwinReportsShapeError, reason: Self.appOnlyScreenInLoopReason)
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
		Self.expectMirrorsTwin(result, failingOnMainAs: .callingMockAcceptedWhereTwinReportsShapeError, reason: Self.appOnlyScreenBuiltByValueReason)
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
		Self.expectMirrorsTwin(result, failingOnMainAs: .callingMockAcceptedWhereTwinReportsShapeError, reason: Self.seamBuiltAgainReason)
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
		Self.expectMirrorsTwin(result, failingOnMainAs: .callingMockAcceptedWhereTwinReportsShapeError, reason: Self.loopThroughInnerSeamBuilderReason)
	}

	/// Expects the twin to give the graph's intended outcome and the calling mock to mirror it, which main's does not: until
	/// the fix, the mock must fail as `knownKind`, the kind the shape's known issue lists, so a mock that begins to fail
	/// another way is not absorbed as the known issue.
	private static func expectMirrorsTwin(
		_ result: GraphFuzzerCallingMockResult,
		failingOnMainAs knownKind: GraphFuzzerFailure.Kind,
		reason: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) {
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")", sourceLocation: sourceLocation)
		#expect(result.failure == nil || result.failure?.kind == knownKind, "\(result.failure?.details ?? "")", sourceLocation: sourceLocation)
		withKnownIssue("\(reason)", sourceLocation: sourceLocation) {
			#expect(result.failure == nil, sourceLocation: sourceLocation)
		}
	}

	// MARK: Values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsTwinsValues_whenFillReadsNothing() async throws {
		let graph = Self.innerSeamGraph(named: "a fill reading nothing", tests: Self.fillReadingNothing, expectedTwinErrorSite: nil, valueProbes: [Self.hostProbe])

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues == compileVerificationIsEnabled)
		#expect(result.failure == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsTwinsValues_whenDeferredFillReadsNothing() async throws {
		let graph = Self.innerSeamGraph(named: "a deferred fill reading nothing", innerModule: Self.deferredInnerModule, tests: """
		import SafeDI
		import InnerModule
		import FeatureModule

		@Instantiable
		final class Fake: Api, Instantiable {
		    init(id: Int) { self.id = id }
		    @Forwarded let id: Int
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
		    @Instantiated let database: Database
		    @Instantiated let inner: Inner
		}
		""", expectedTwinErrorSite: nil, valueProbes: [Self.hostAndFillProbe])

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues == compileVerificationIsEnabled)
		#expect(result.failure == nil)
	}

	/// On main no drawn graph reaches the value comparison, since each cell whose mock fills its place passes it up first,
	/// so the twin half of every drawn probe is compiled and run here, against the first graph of each probed cell; the
	/// mock half runs once a calling mock fills its place.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func drawnValueProbes_describeTwin_inFirstGraphOfEachProbedCell() async throws {
		let seeds = (UInt64(0)..<UInt64(GraphFuzzerCallingMockCell.drawnCells.count)).filter { GraphFuzzerCallingMockDraw(seed: $0).valueProbes != nil }
		#expect(seeds == [16, 17, 18, 19, 24, 25, 26, 27])
		for seed in seeds {
			var filesToDelete = [URL]()
			defer {
				for file in filesToDelete {
					try? FileManager.default.removeItem(at: file)
				}
			}
			let graph = GraphFuzzerCallingMockDraw(seed: seed).graph
			let output = try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.twin), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let twinPath = try DifferentialValuePath(output: output, modules: graph.modules(.twin))
			let twinProbes = try #require(graph.valueProbes).map { DifferentialValueProbe(name: $0.name, expression: $0.knownRightExpression ?? $0.expression) }

			let description = try await DifferentialValueOracle.describe(twinPath, probes: twinProbes, filesToDelete: &filesToDelete)

			#expect(description?.contains("probe \(twinProbes[0].name)") == true, "seed \(seed)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_comparesNoValues_whenRunIsNotAskedTo() async throws {
		let graph = Self.innerSeamGraph(named: "a fill reading nothing", tests: Self.fillReadingNothing, expectedTwinErrorSite: nil, valueProbes: [Self.hostProbe])

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0, comparesValues: false)

		#expect(!result.comparedValues)
		#expect(result.failure == nil)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsOtherValues_whenMocksFillBuildsValueTwinsFillReceivesFromCaller() async throws {
		// The mock's fill builds a `Database` of its own, and the twin's receives the caller's: two instances against one.
		let mockGraph = Self.innerSeamGraph(named: "the mock's fill", tests: Self.fillReadingNothing.replacingOccurrences(
			of: "    init() {}\n}",
			with: "    init(database: Database) { self.database = database }\n    @Instantiated let database: Database\n}",
		), expectedTwinErrorSite: nil)
		let twinGraph = Self.innerSeamGraph(named: "the twin's fill", tests: Self.fillReadingNothing.replacingOccurrences(
			of: "    init() {}\n}",
			with: "    init(database: Database) { self.database = database }\n    @Received let database: Database\n}",
		), expectedTwinErrorSite: nil)
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock whose fill builds what its twin's receives",
			mockFiles: mockGraph.mockFiles,
			twinFiles: twinGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: [Self.hostProbe],
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(mockGraph.mockFiles.map(\.content) != twinGraph.mockFiles.map(\.content))
		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure?.kind == .callingMockBuildsOtherValuesThanTwin)
		#expect(result.failure?.valueDifferences == [
			"probe `Host` at <1> Host > inner > api > database:\n  feature:     database: <5> Database\n  known right: database: <2> Database (seen, first at <1> Host > database)",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsOtherValues_whenMocksDeferredFillBuildsValueTwinsFillReceivesFromCaller() async throws {
		// The fill is built only when its builder is called, so the probe must describe the caller and the fill together for
		// the twin's fill to show the caller's `Database` and the mock's a second one.
		let mockGraph = Self.innerSeamGraph(named: "the mock's fill", innerModule: Self.deferredInnerModule, tests: Self.deferredFillReading(database: "@Instantiated"), expectedTwinErrorSite: nil)
		let twinGraph = Self.innerSeamGraph(named: "the twin's fill", innerModule: Self.deferredInnerModule, tests: Self.deferredFillReading(database: "@Received"), expectedTwinErrorSite: nil)
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock whose deferred fill builds what its twin's receives",
			mockFiles: mockGraph.mockFiles,
			twinFiles: twinGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: [Self.hostAndFillProbe],
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure?.kind == .callingMockBuildsOtherValuesThanTwin)
		#expect(result.failure?.valueDifferences == [
			"probe `(Host, Host.inner.apiBuilder.instantiate(7))` at (Host, Api) > .1 > database:\n  feature:     database: <6> Database\n  known right: database: <2> Database (seen, first at (Host, Api) > .0 > database)",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsMockFailsWhenRun_whenMocksFillTraps() async throws {
		// Both forms compile; only the mock's fill traps when it is built.
		let twinGraph = Self.innerSeamGraph(named: "the twin", tests: Self.fillReadingNothing, expectedTwinErrorSite: nil)
		let mockGraph = Self.innerSeamGraph(named: "the mock", tests: Self.fillReadingNothing.replacingOccurrences(of: "    init() {}\n}", with: "    init() { fatalError(\"A planted trap\") }\n}"), expectedTwinErrorSite: nil)
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock whose fill traps",
			mockFiles: mockGraph.mockFiles,
			twinFiles: twinGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: [Self.hostProbe],
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(mockGraph.mockFiles.map(\.content) != twinGraph.mockFiles.map(\.content))
		#expect(result.twinHasIntendedOutcome)
		#expect(result.comparedValues)
		#expect(result.failure?.kind == .callingMockFailsWhenRun)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsMockDoesNotCompile_whenMocksModuleDoesNotCompile() async throws {
		// The tool reads no expression, so it accepts both forms; only the mock's module holds one that does not compile.
		let twinGraph = Self.innerSeamGraph(named: "the twin", tests: Self.fillReadingNothing, expectedTwinErrorSite: nil)
		let mockGraph = Self.innerSeamGraph(named: "the mock", tests: Self.fillReadingNothing + "\n\nlet notAnInteger: Int = \"text\"", expectedTwinErrorSite: nil)
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock whose module does not compile",
			mockFiles: mockGraph.mockFiles,
			twinFiles: twinGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: [Self.hostProbe],
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure?.kind == .callingMockDoesNotCompile)
		#expect(result.failure?.details.contains("cannot convert value of type 'String' to specified type 'Int'") == true)
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

	@Test
	func passUps_areEmpty_whenMockDeclaresNoPlaceParameter() throws {
		let generatedFile = "extension Host {\n    static func mock(safeDIOverrides: SafeDIOverrides = .init()) -> Host { fatalError() }\n}"

		#expect(try GraphFuzzerCallingMockCheck.passUpsOf(Self.seamBuiltAgainGraph, inGeneratedFile: generatedFile).isEmpty)
	}

	@Test
	func passUps_throw_whenGeneratedFileDeclaresNoMockOfCaller() {
		let generatedFile = "extension Service {\n    static func mock(safeDIOverrides: SafeDIOverrides = .init()) -> Service { fatalError() }\n}"

		#expect(throws: GraphFuzzerCallingMockCheck.HarnessError.self) {
			try GraphFuzzerCallingMockCheck.passUpsOf(Self.seamBuiltAgainGraph, inGeneratedFile: generatedFile)
		}
	}

	@Test
	func initializerParameterLabels_areNil_whenGeneratedFileDeclaresNoInitializerOfCaller() {
		#expect(GraphFuzzerCallingMockCheck.initializerParameterLabels(ofType: "Host", inGeneratedFile: "extension Service {\n    init() {}\n}") == nil)
		#expect(GraphFuzzerCallingMockCheck.initializerParameterLabels(ofType: "Host", inGeneratedFile: "extension Host {\n    init() {}\n}") == [])
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsAcceptance_whenMockIsAcceptedWhereTwinReportsShapeError() async throws {
		// The mock's fill reads nothing, so any tool accepts it, while the twin's fill reads the level between.
		let acceptedMockFiles = Self.seamBuiltAgainGraph.mockFiles.map { file in
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
			name: "a mock accepted where its twin reports a shape error",
			mockFiles: acceptedMockFiles,
			twinFiles: Self.seamBuiltAgainGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: ("App/AppTypes.swift", "@Received let logger: Logger"),
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(acceptedMockFiles.map(\.content) != Self.seamBuiltAgainGraph.mockFiles.map(\.content))
		#expect(result.twinHasIntendedOutcome)
		#expect(result.mockSites == nil)
		#expect(result.failure?.kind == .callingMockAcceptedWhereTwinReportsShapeError)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsUnclassifiedPassUp_whenGraphSaysImplementationIsVisibleButNoneIs() async throws {
		// No type in module `Tests` fulfills `Api`, so any tool's mock passes the place up; the graph wrongly says an
		// implementation is visible, so no reason classifies the pass-up.
		let graph = Self.innerSeamGraph(named: "a pass-up the graph does not classify", tests: """
		import SafeDI
		import InnerModule
		import FeatureModule

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
		    @Instantiated let database: Database
		    @Instantiated let inner: Inner
		}
		""", expectedTwinErrorSite: nil)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(graph.implementationIsVisible)
		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.count == 1)
		#expect(result.passUps.map(\.reason) == [nil])
		#expect(result.failure?.kind == .callingMockPassesUpUnclassifiedPlace)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsMissingFlatParameter_whenGraphSaysMockTakesValueItDoesNot() async throws {
		// The fill reads nothing, so any tool's mock takes no `token`; the graph says the tree cannot build one.
		let graph = Self.innerSeamGraph(named: "a flat parameter the mock does not take", tests: Self.fillReadingNothing, expectedTwinErrorSite: nil, flatParameterLabels: ["token"])

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0, comparesValues: false)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.passUps.isEmpty)
		#expect(result.failure?.kind == .callingMockLacksFlatParameter)
		#expect(result.failure?.details == "a flat parameter the mock does not take: the calling mock takes no parameter token, a value its tree cannot build")
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
				group.addTask { await (seed, try GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockDraw(seed: seed).graph, seed: seed, comparesValues: Self.comparesValues(ofSeed: seed))) }
			}
			while let (seed, result) = try await group.next() {
				results[seed] = result
				if let next = seeds.next() {
					group.addTask { await (next, try GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockDraw(seed: next).graph, seed: next, comparesValues: Self.comparesValues(ofSeed: next))) }
				}
			}
			return results
		}

		var intendedGraphsByCell = [GraphFuzzerCallingMockCell: Int]()
		var passUpCountsByReason = [String: Int]()
		var comparedGraphCount = 0
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
			if result.comparedValues {
				comparedGraphCount += 1
			}
			let knownIssue = Self.callingMockKnownIssues.first { $0.seeds.contains(seed) }
			for problem in Self.comparisonProblems(ofSeed: seed, draw: draw, result: result, isListed: knownIssue != nil) {
				Issue.record("\(problem)")
			}
			for passUp in result.passUps {
				passUpCountsByReason[passUp.reason?.rawValue ?? "unclassified", default: 0] += 1
			}
			if draw.cell.shape.isControl {
				#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels, "seed \(seed) (\(draw.cell))")
			}
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
		print("calling-mock pass-ups \(GraphFuzzerCallingMockPassUpReason.allCases.map { "\($0.rawValue)=\(passUpCountsByReason[$0.rawValue, default: 0])" }.joined(separator: " ")) unclassified=\(passUpCountsByReason["unclassified", default: 0]) values-compared=\(comparedGraphCount)")

		#expect(GraphFuzzerCallingMockCell.drawnCells.filter { intendedGraphsByCell[$0, default: 0] < 10 } == [])
	}

	/// The plain app-only screen cells draw the canonical loop: the seam's settings builder forwards nothing, so the twin
	/// reports the screen's receive of the feed's builder with a note at the seam's feed builder, which a screen built by
	/// value, a constant cycle, does not add.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func appOnlyScreenInLoopDraw_twinReportsLoopWithNoteAtSeamsFeedBuilder_whenSettingsBuilderForwardsNothing() async throws {
		for seed: UInt64 in [4, 6] {
			let draw = GraphFuzzerCallingMockDraw(seed: seed)
			let feed = draw.names.feed
			let feedBuilder = "\(feed.prefix(1).lowercased())\(feed.dropFirst())Builder: ErasedInstantiator<(), any \(draw.names.feedPage)>"

			let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: seed, comparesValues: false)

			#expect(draw.cell.shape == .appOnlyScreenInLoop && draw.cell.place == .plain)
			#expect(result.twinSites == [
				GraphFuzzerDiagnosticSite(severity: "error", file: "App/AppTypes.swift", line: 7, declaration: "@Received private let \(feedBuilder)"),
				GraphFuzzerDiagnosticSite(severity: "note", file: "Feature/FeatureTypes.swift", line: 22, declaration: "@Instantiated(fulfilledByType: \"\(feed)\") private let \(feedBuilder)"),
			], "seed \(seed)")
		}
	}

	/// Why seed `seed`'s run should have compared values and did not: a seed the cell test compares whose graph states
	/// probes and that passes, unlisted, compares its values wherever compile verification is on, so a change that stops
	/// the comparison cannot leave the cell test passing with nothing compiled.
	static func comparisonProblems(ofSeed seed: UInt64, draw: GraphFuzzerCallingMockDraw, result: GraphFuzzerCallingMockResult, isListed: Bool) -> [String] {
		guard comparesValues(ofSeed: seed), draw.valueProbes != nil, result.failure == nil, !isListed, result.comparedValues != compileVerificationIsEnabled else { return [] }
		return ["Calling-mock seed \(seed) (\(draw.cell)) passes without comparing its values"]
	}

	@Test
	func comparisonProblems_reportSeed_whenPassingProbedSeedComparesNoValues() {
		let draw = GraphFuzzerCallingMockDraw(seed: 16)
		let uncompared = GraphFuzzerCallingMockResult(twinSites: nil, mockSites: nil, twinDiagnostics: nil, twinInitializerLabels: [], passUps: [], drawingDefect: nil, comparedValues: !compileVerificationIsEnabled, failure: nil)
		let compared = GraphFuzzerCallingMockResult(twinSites: nil, mockSites: nil, twinDiagnostics: nil, twinInitializerLabels: [], passUps: [], drawingDefect: nil, comparedValues: compileVerificationIsEnabled, failure: nil)

		#expect(Self.comparesValues(ofSeed: 16))
		#expect(Self.comparisonProblems(ofSeed: 16, draw: draw, result: uncompared, isListed: false) == ["Calling-mock seed 16 (callersOwnValue/internal/plain) passes without comparing its values"])
		#expect(Self.comparisonProblems(ofSeed: 16, draw: draw, result: uncompared, isListed: true) == [])
		#expect(Self.comparisonProblems(ofSeed: 16, draw: draw, result: compared, isListed: false) == [])
	}

	@Test
	func comparesValues_coversEachLeafPositionOnce_inEachProbedCell() {
		for cell in GraphFuzzerCallingMockCell.drawnCells {
			let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell == cell }
			guard draws.first?.valueProbes != nil else { continue }
			let comparedPositions = draws.filter { Self.comparesValues(ofSeed: $0.seed) }.map { "\($0.tickerPosition)" }

			#expect(comparedPositions.sorted() == Set(draws.map { "\($0.tickerPosition)" }).sorted(), "\(cell)")
		}
	}

	@Test
	func drawnCells_coverEveryCell_whenCorpusDrawsTenGraphsPerCell() {
		#expect(GraphFuzzerCallingMockCell.all.count == 28)
		#expect(GraphFuzzerCallingMockCell.drawnCells == GraphFuzzerCallingMockCell.all)
		#expect(Self.callingMockCorpusSeedCount == GraphFuzzerCallingMockCell.drawnCells.count * 10)
	}

	@Test
	func callingMockKnownIssues_listOneShapeCellsSeedsPerEntry_inIncreasingOrder() {
		#expect(Self.callingMockKnownIssueListProblems(Self.callingMockKnownIssues) == [])
	}

	@Test
	func callingMockKnownIssueListProblems_reportNothing_whenFixDeletesSomeOfCellsSeeds() {
		let partlyFixed = GraphFuzzerKnownIssue(reason: "A shape", signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [16, 72, 240])
		let fixedCellDeleted = [GraphFuzzerKnownIssue(reason: "A shape", signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [0, 28])]

		#expect(GraphFuzzerCallingMockDraw(seed: 16).cell.description == "callersOwnValue/internal/plain")
		#expect(Self.callingMockKnownIssueListProblems([partlyFixed]) == [])
		#expect(Self.callingMockKnownIssueListProblems(fixedCellDeleted) == [])
	}

	@Test
	func callingMockKnownIssueListProblems_reportEntry_whenItListsTwoCells() {
		let twoCells = GraphFuzzerKnownIssue(reason: "Two cells", signatures: [.callingMockAcceptedWhereTwinReportsShapeError], seeds: [0, 1])

		#expect(Self.callingMockKnownIssueListProblems([twoCells]) == ["The known issue \"Two cells\" lists the seeds of 2 cells: outerSeamValue/internal/deferred, outerSeamValue/internal/plain."])
	}

	@Test
	func callingMockKnownIssueListProblems_reportEntry_whenItListsControlCell() {
		let control = GraphFuzzerKnownIssue(reason: "The control", signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [20])

		#expect(GraphFuzzerCallingMockDraw(seed: 20).cell.description == "noVisibleImplementation/internal/plain")
		#expect(Self.callingMockKnownIssueListProblems([control]) == ["The known issue \"The control\" lists seeds of the control, noVisibleImplementation/internal/plain, which passes on main."])
	}

	@Test
	func callingMockKnownIssueListProblems_reportEntry_whenItListsNoSeeds() {
		let noSeeds = GraphFuzzerKnownIssue(reason: "No seeds", signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [])

		#expect(Self.callingMockKnownIssueListProblems([noSeeds]) == ["The known issue \"No seeds\" lists no seeds or no signatures."])
	}

	@Test
	func callingMockKnownIssueListProblems_reportEntry_whenItsSeedsDecrease() {
		let decreasing = GraphFuzzerKnownIssue(reason: "Decreasing", signatures: [.callingMockPassesUpUnclassifiedPlace], seeds: [44, 16])

		#expect(Self.callingMockKnownIssueListProblems([decreasing]) == ["The seeds of \"Decreasing\" are not in increasing order."])
	}

	/// What is wrong with `knownIssues` as a list of the calling-mock check's known issues: each entry lists seeds, in
	/// increasing order, of one shape cell, never of the control. A fix that mends some of a cell's graphs deletes their
	/// seeds, and one that mends a cell deletes its entry, so no count of seeds or of entries is required.
	static func callingMockKnownIssueListProblems(_ knownIssues: [GraphFuzzerKnownIssue]) -> [String] {
		var problems = SafeDIToolGraphFuzzerTests.knownIssueListProblems(knownIssues, corpusSeedCount: callingMockCorpusSeedCount)
		for knownIssue in knownIssues {
			let cells = Set(knownIssue.seeds.map { GraphFuzzerCallingMockDraw(seed: $0).cell }).sorted()
			if cells.count > 1 {
				problems.append("The known issue \"\(knownIssue.reason)\" lists the seeds of \(cells.count) cells: \(cells.map(\.description).joined(separator: ", ")).")
			}
			for cell in cells where cell.shape.isControl {
				problems.append("The known issue \"\(knownIssue.reason)\" lists seeds of the control, \(cell), which passes on main.")
			}
		}
		return problems
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
	private static func innerSeamGraph(
		named name: String,
		innerModule: String = innerModule,
		tests: String,
		expectedTwinErrorSite: (file: String, declaration: String)?,
		flatParameterLabels: Set<String> = [],
		valueProbes: [DifferentialValueProbe]? = nil,
	) -> GraphFuzzerCallingMockGraph {
		GraphFuzzerCallingMockGraph(
			handWrittenNamed: name,
			mockFiles: [
				.init(module: "InnerModule", dependencies: [], content: innerModule),
				.init(module: "FeatureModule", dependencies: ["InnerModule"], content: featureModule),
				.init(module: "Tests", dependencies: ["InnerModule", "FeatureModule"], content: tests),
			],
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: flatParameterLabels,
			expectedTwinErrorSite: expectedTwinErrorSite,
			valueProbes: valueProbes,
		)
	}

	/// `innerModule` with the hole's place deferred: `apiBuilder`, an `ErasedInstantiator<Int, any Api>` that `Fake`
	/// fulfills.
	private static let deferredInnerModule = """
	import SafeDI

	public protocol Api: AnyObject {}

	@Instantiable(generateDependencyTree: true, generateMock: .public)
	public final class Inner: Instantiable {
	    init(apiBuilder: ErasedInstantiator<Int, any Api>) { self.apiBuilder = apiBuilder }
	    @Instantiated(fulfilledByType: "Fake") public let apiBuilder: ErasedInstantiator<Int, any Api>
	}
	"""

	/// A fill that reads nothing beside the caller's own `database`, which the calling mock fills where its twin does.
	private static let fillReadingNothing = """
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
	"""

	/// `Host` and what its `inner.apiBuilder` builds for `id` 7, in one probe, as the draw describes a deferred place.
	private static var hostAndFillProbe: DifferentialValueProbe {
		DifferentialValueProbe(
			name: "(Host, Host.inner.apiBuilder.instantiate(7))",
			expression: GraphFuzzerCallingMockDraw.callerAndFill(of: "Tests.Host.mock()", place: "inner.apiBuilder"),
			knownRightExpression: GraphFuzzerCallingMockDraw.callerAndFill(of: "Tests.Host()", place: "inner.apiBuilder"),
		)
	}

	/// A deferred fill forwarding `id` that reads the caller's `database`: `@Received` in the twin, `@Instantiated` in the
	/// mock.
	private static func deferredFillReading(database attribute: String) -> String {
		"""
		import SafeDI
		import InnerModule
		import FeatureModule

		@Instantiable
		final class Fake: Api, Instantiable {
		    init(id: Int, database: Database) { self.id = id; self.database = database }
		    @Forwarded let id: Int
		    \(attribute) let database: Database
		}

		@Instantiable(generateMock: true)
		final class Host: Instantiable {
		    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
		    @Instantiated let database: Database
		    @Instantiated let inner: Inner
		}
		"""
	}

	private static var hostProbe: DifferentialValueProbe {
		// Qualified by its module: Foundation, which the probe executable imports, declares `Host` on macOS.
		DifferentialValueProbe(name: "Host", expression: "Tests.Host.mock()", knownRightExpression: "Tests.Host()")
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

	/// Whether the cell test compiles seed `seed`'s graph and compares its values: the first graph of each cell with each
	/// leaf position the cell draws, since each comparison compiles every module of both forms, and the leaf moves the
	/// caller's other property and parameter. On main no graph is compared: every cell whose mock fills its place fails
	/// earlier, by passing the place up.
	static func comparesValues(ofSeed seed: UInt64) -> Bool {
		comparedSeeds.contains(seed)
	}

	/// The first seed of each cell and leaf position, in the corpus.
	static let comparedSeeds: Set<UInt64> = {
		var seenCellsAndPositions = Set<String>()
		var seeds = Set<UInt64>()
		for seed in UInt64(0)..<UInt64(callingMockCorpusSeedCount) {
			let draw = GraphFuzzerCallingMockDraw(seed: seed)
			if seenCellsAndPositions.insert("\(draw.cell) \(draw.tickerPosition)").inserted {
				seeds.insert(seed)
			}
		}
		return seeds
	}()

	static let outerSeamValueReason = "A calling mock fills, or passes up as a required builder, a place whose fill receives a value an outer seam builds, where its production twin reports that the outer seam passes the builder on from its own caller; the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock report the same error"
	static let appOnlyScreenInLoopReason = "A calling mock passes up the place of an app-only screen in a loop of the seam's screens, where its production twin reports the loop (the seam's tree builds the screen's received builder only after it calls the screen's builder); the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock report the same error"
	static let appOnlyScreenBuiltByValueReason = "A calling mock passes up the place of an app-only screen built by value whose loop through the seam's screens is a constant cycle, where its production twin reports the cycle; the change that makes a calling mock mirror its production tree, which lands before 2.3.0, makes the mock report the same error"
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
