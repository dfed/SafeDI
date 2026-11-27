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
/// internal or `.public` caller, a plain or deferred place). Every cell passes: the seam built again, the one outcome rule 7
/// lists apart, by building what the same types build inline.
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
		Self.expectMirrorsTwin(result)
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
		#expect(result.passUps.isEmpty)
		Self.expectMirrorsTwin(result)
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
		let graph = Self.innerSeamGraph(named: "a fill receiving the outer seam's value", tests: Self.fillReadingOuterSeamsValue, expectedTwinErrorSite: ("Tests/TestsTypes.swift", "@Received let database: Database"))

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "Tests/TestsTypes.swift", line: 8, declaration: "@Received let database: Database"),
			GraphFuzzerDiagnosticSite(severity: "note", file: "FeatureModule/FeatureModuleTypes.swift", line: 12, declaration: "@Instantiated public let database: Database"),
		])
		Self.expectMirrorsTwin(result)
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
		Self.expectMirrorsTwin(result)
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
		Self.expectMirrorsTwin(result)
	}

	/// The outcome rule 7 lists apart: the twin reports that `X`'s second build of `Service` passes the builder on unchanged,
	/// and the calling mock, which builds `Service` inline, is accepted, and agrees only by building what the same types
	/// build inline, each `LiveGadget` the `logger` nearest it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsInlineValues_whenFillReadsValueOfLevelBetweenBuildsOfSeam() async throws {
		let graph = Self.seamBuiltAgainGraph

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinSites == [
			GraphFuzzerDiagnosticSite(severity: "error", file: "App/AppTypes.swift", line: 7, declaration: "@Received let logger: Logger"),
			GraphFuzzerDiagnosticSite(severity: "note", file: "Feature/FeatureTypes.swift", line: 20, declaration: "@Instantiated let logger: Logger"),
		])
		#expect(result.twinDiagnostics.map(GraphFuzzerCallingMockCheck.reportsOnlySeamBuiltAgain) == true)
		#expect(result.mockSites == nil)
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues == compileVerificationIsEnabled)
		Self.expectMirrorsTwin(result)
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
		#expect(compilation.failure == nil)
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
		Self.expectMirrorsTwin(result)
	}

	/// Expects the twin to give the graph's intended outcome and the calling mock to mirror it.
	private static func expectMirrorsTwin(_ result: GraphFuzzerCallingMockResult, sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")", sourceLocation: sourceLocation)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")", sourceLocation: sourceLocation)
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

	/// The known-right half of every drawn probe, compiled and run alone against the first graph of each probed cell that
	/// states probes, so a probe that names no declaration of its known-right path fails here by name rather than as a
	/// harness error of the cell test: the twin's for the cells whose twin is accepted, and the same types built inline for
	/// the seam built again and the cells whose graphs compare values with inline (`comparesValuesWithInline`). A graph whose
	/// mock passes its place up whole states none (`CallerLazyValue.reentersCalledType`), unless it joins a filled call
	/// (`joinsFilledCall`), as seed 737, its cell's first, does.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func drawnValueProbes_describeKnownRight_inFirstGraphOfEachProbedCell() async throws {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }
		let seeds = GraphFuzzerCallingMockCell.all.compactMap { cell in
			draws.first { $0.cell == cell && $0.valueProbes != nil }?.seed
		}
		#expect(seeds == [8, 9, 10, 11, 16, 17, 18, 19, 24, 25, 26, 27, 284, 285, 288, 289, 292, 293, 450, 451, 452, 453, 530, 531, 610, 611, 612, 613, 614, 615, 670, 671, 672, 673, 674, 675, 730, 737, 738, 733, 734, 735, 790, 791, 792, 793, 794, 795, 1_030, 1_031, 1_032, 1_033, 1_034, 1_035, 1_090, 1_091, 1_092, 1_120, 1_121, 1_122, 1_123, 1_124, 1_125, 1_180, 1_181, 1_182, 1_183, 1_184, 1_185, 1_240, 1_241, 1_242])
		for seed in seeds {
			var filesToDelete = [URL]()
			defer {
				for file in filesToDelete {
					try? FileManager.default.removeItem(at: file)
				}
			}
			let draw = GraphFuzzerCallingMockDraw(seed: seed)
			let graph = draw.graph
			let knownRightModules = draw.twinRejects || graph.comparesValuesWithInline ? graph.inlineModules : graph.modules(.twin)
			let output = try await executeSafeDIToolMultiModuleTest(modules: knownRightModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let knownRightPath = try DifferentialValuePath(output: output, modules: knownRightModules)
			let knownRightProbes = try #require(graph.valueProbes).map { DifferentialValueProbe(name: $0.name, expression: $0.knownRightExpression ?? $0.expression) }

			let description = try await DifferentialValueOracle.describe(knownRightPath, probes: knownRightProbes, filesToDelete: &filesToDelete)

			#expect(description?.contains("probe \(knownRightProbes[0].name)") == true, "seed \(seed)")
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
	func check_reportsOtherValuesThanInline_whenMocksFillBuildsValueInlineFillReceives() async throws {
		// The twin reports that the seam built again passes its builder on unchanged; the mock's fill builds a `Logger` of its
		// own, which any tool accepts, where the same types built inline hand each fill the `logger` nearest it.
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock of a seam built again whose fill builds what inline's receives",
			mockFiles: Self.seamBuiltAgainGraph.mockFiles.map { file in
				GraphFuzzerCallingMockGraph.File(
					module: file.module,
					dependencies: file.dependencies,
					content: file.content.replacingOccurrences(of: "    @Received let logger: Logger", with: "    @Instantiated let logger: Logger"),
				)
			},
			twinFiles: Self.seamBuiltAgainGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: ("App/AppTypes.swift", "@Received let logger: Logger"),
			valueProbes: Self.seamBuiltAgainGraph.valueProbes,
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(graph.mockFiles.map(\.content) != Self.seamBuiltAgainGraph.mockFiles.map(\.content))
		#expect(result.twinHasIntendedOutcome)
		#expect(result.mockSites == nil)
		#expect(result.comparedValues)
		#expect(result.failure?.kind == .callingMockBuildsOtherValuesThanInline)
		// Each fill the mock builds holds a `Logger` of its own, where inline's holds the nearest one: the caller's for the
		// outer place, the level between's for each place built again.
		#expect(result.failure?.valueDifferences == [
			"probe `App.Host` at <1> Host > service > gadget > logger:\n  feature:     logger: <5> Logger\n  known right: logger: <2> Logger (seen, first at <1> Host > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() > gadget > logger:\n  feature:     logger: <12> Logger\n  known right: logger: <7> Logger (seen, first at <1> Host > service > xBuilder > instantiate() > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() > xBuilder > instantiate() > serviceBuilder > instantiate() > gadget > logger:\n  feature:     logger: <19> Logger\n  known right: logger: <13> Logger (seen, first at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() > xBuilder > instantiate() > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() > xBuilder > instantiate() > serviceBuilder > instantiate() again > gadget > logger:\n  feature:     logger: <23> Logger\n  known right: logger: <13> Logger (seen, first at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() > xBuilder > instantiate() > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() > xBuilder > instantiate() again > serviceBuilder > instantiate() > gadget > logger:\n  feature:     logger: <30> Logger\n  known right: logger: <22> Logger (seen, first at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() > xBuilder > instantiate() again > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() again > gadget > logger:\n  feature:     logger: <34> Logger\n  known right: logger: <7> Logger (seen, first at <1> Host > service > xBuilder > instantiate() > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() again > xBuilder > instantiate() > serviceBuilder > instantiate() > gadget > logger:\n  feature:     logger: <41> Logger\n  known right: logger: <31> Logger (seen, first at <1> Host > service > xBuilder > instantiate() > serviceBuilder > instantiate() again > xBuilder > instantiate() > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() again > serviceBuilder > instantiate() > gadget > logger:\n  feature:     logger: <48> Logger\n  known right: logger: <37> Logger (seen, first at <1> Host > service > xBuilder > instantiate() again > logger)",
			"probe `App.Host` at <1> Host > service > xBuilder > instantiate() again > serviceBuilder > instantiate() > xBuilder > instantiate() > serviceBuilder > instantiate() > gadget > logger:\n  feature:     logger: <55> Logger\n  known right: logger: <43> Logger (seen, first at <1> Host > service > xBuilder > instantiate() again > serviceBuilder > instantiate() > xBuilder > instantiate() > logger)",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsOtherValuesThanInline_whenGraphComparesAcceptedTwinsMockWithInline() async throws {
		// The twin is accepted, and the graph compares its mock with the same types built inline, whose fill receives the
		// caller's `Database` where the mock's builds one of its own.
		let mockGraph = Self.innerSeamGraph(named: "the mock's fill", tests: Self.fillReadingNothing.replacingOccurrences(
			of: "    init() {}\n}",
			with: "    init(database: Database) { self.database = database }\n    @Instantiated let database: Database\n}",
		), expectedTwinErrorSite: nil)
		let twinGraph = Self.innerSeamGraph(named: "the twin's fill", tests: Self.fillReadingNothing.replacingOccurrences(
			of: "    init() {}\n}",
			with: "    init(database: Database) { self.database = database }\n    @Received let database: Database\n}",
		), expectedTwinErrorSite: nil)
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock whose fill builds what inline's receives",
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
			comparesValuesWithInline: true,
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(result.twinHasIntendedOutcome)
		#expect(result.twinSites == nil)
		#expect(result.comparedValues)
		#expect(result.failure?.kind == .callingMockBuildsOtherValuesThanInline)
		#expect(result.failure?.valueDifferences == [
			"probe `Host` at <1> Host > inner > api > database:\n  feature:     database: <5> Database\n  known right: database: <2> Database (seen, first at <1> Host > database)",
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_throws_whenSameTypesBuiltInlineDoNotCompile() async throws {
		// `Host` receives a `Token` nothing builds: the twin, a seam, takes it as a parameter and reports only that the seam
		// built again passes its builder on unchanged, and the mock takes it as a parameter, while the same types built
		// inline make `Host` a root, which the macro rejects for receiving it. A graph whose baseline does not build is the
		// harness's to fix, as a twin that does not compile is.
		let graph = GraphFuzzerCallingMockGraph(
			handWrittenNamed: "a seam built again beneath a caller that receives what nothing builds",
			mockFiles: Self.seamBuiltAgainGraph.mockFiles.map { file in
				GraphFuzzerCallingMockGraph.File(
					module: file.module,
					dependencies: file.dependencies,
					content: file.content
						.replacingOccurrences(of: "import Feature\n", with: "import Feature\n\npublic struct Token {}\n")
						.replacingOccurrences(
							of: "    init(logger: Logger, service: Service) { self.logger = logger; self.service = service }\n",
							with: "    init(token: Token, logger: Logger, service: Service) { self.token = token; self.logger = logger; self.service = service }\n    @Received let token: Token\n",
						),
				)
			},
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: ["token"],
			expectedTwinErrorSite: ("App/AppTypes.swift", "@Received let logger: Logger"),
			valueProbes: [DifferentialValueProbe(name: "App.Host", expression: "App.Host.mock(token: App.Token())", knownRightExpression: "App.Host()")],
		)

		await #expect(throws: GraphFuzzerCallingMockCheck.HarnessError.self) {
			try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsAcceptance_whenGraphOfSeamBuiltAgainStatesNoProbes() async throws {
		// The outcome rule 7 lists apart agrees only by values, which a graph without probes cannot compare.
		let graph = GraphFuzzerCallingMockGraph(
			name: "a seam built again without probes",
			mockFiles: Self.seamBuiltAgainGraph.mockFiles,
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

		#expect(graph.valueProbes == nil)
		#expect(result.twinHasIntendedOutcome)
		#expect(result.mockSites == nil)
		#expect(result.failure?.kind == .callingMockAcceptedWhereTwinReportsShapeError)
	}

	@Test
	func reportsOnlySeamBuiltAgain_isFalse_whenAnotherErrorIsBesideIt() {
		let builtAgain = "/a/App/AppTypes.swift:7:5: error: `LiveGadget` receives `logger: Logger`, which `Service`’s tree builds where it instantiates `Service` again, but that call passes the builder `Service` takes for `Service`’s `gadget` on unchanged, so the caller that fills it cannot hand it those values."
		let note = "/a/Feature/FeatureTypes.swift:20:5: note: `X` declares `logger: Logger` here."
		let other = "/a/App/AppTypes.swift:9:5: error: Dependency cycle: `A` -> `B` -> `A`."

		#expect(GraphFuzzerCallingMockCheck.reportsOnlySeamBuiltAgain([builtAgain, note].joined(separator: "\n")))
		#expect(!GraphFuzzerCallingMockCheck.reportsOnlySeamBuiltAgain([builtAgain, note, other].joined(separator: "\n")))
		#expect(!GraphFuzzerCallingMockCheck.reportsOnlySeamBuiltAgain(note))
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
		// The shape whose mock condition is inactive has the twin of `fillInstantiatesTypeNoDeclarationCanFulfill`, so its
		// twin reports that shape's error.
		for seed in GraphFuzzerCallingMockCell.firstSeeds where GraphFuzzerCallingMockDraw(seed: seed).twinRejects && GraphFuzzerCallingMockDraw(seed: seed).cell.shape != .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive {
			let shape = GraphFuzzerCallingMockDraw(seed: seed).cell.shape
			await sitesByShape[shape, default: []].append(try GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockDraw(seed: seed).graph, seed: seed).twinSites)
		}

		#expect(sitesByShape.keys.sorted() == [.outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillConstructsTypeCallerModuleCannotReach])
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

	@Test
	func initializerParameterLabels_readOnlyTheTypesOwnInitializers_whenItsExtensionNestsABuilderStruct() {
		let generatedFile = """
		extension Host {
		    public enum SafeDIScope_FeedService {
		        public struct __safeDI_Builder<T> {
		            public init(panel: @escaping () -> T) {}
		            public init(__safeDI_noScope: @escaping () -> T) {}
		        }
		    }
		    public init(__safeDI_feedServiceBuilder: SafeDIScope_FeedService.__safeDI_Builder<any FeedService>) {}
		}
		"""
		#expect(GraphFuzzerCallingMockCheck.initializerParameterLabels(ofType: "Host", inGeneratedFile: generatedFile) == ["feedServiceBuilder"])
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
		// The mock's fill reads nothing, so any tool accepts it, while the twin's fill reads the outer seam's `database`, which
		// the twin reports, an error other than the seam built again's, so no value comparison stands for it.
		let twinGraph = Self.innerSeamGraph(named: "the twin", tests: Self.fillReadingOuterSeamsValue, expectedTwinErrorSite: ("Tests/TestsTypes.swift", "@Received let database: Database"))
		let mockGraph = Self.innerSeamGraph(named: "the mock", tests: Self.fillReadingOuterSeamsValue.replacingOccurrences(
			of: "    init(database: Database) { self.database = database }\n    @Received let database: Database",
			with: "    init() {}",
		), expectedTwinErrorSite: nil)
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock accepted where its twin reports a shape error",
			mockFiles: mockGraph.mockFiles,
			twinFiles: twinGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: ("Tests/TestsTypes.swift", "@Received let database: Database"),
			valueProbes: [Self.hostProbe],
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(mockGraph.mockFiles.map(\.content) != twinGraph.mockFiles.map(\.content))
		#expect(result.twinHasIntendedOutcome)
		#expect(result.twinDiagnostics.map(GraphFuzzerCallingMockCheck.reportsOnlySeamBuiltAgain) == false)
		#expect(result.mockSites == nil)
		#expect(!result.comparedValues)
		#expect(result.failure?.kind == .callingMockAcceptedWhereTwinReportsShapeError)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func check_reportsRejection_whenMockIsRejectedWhereMockConditionIsInactive() async throws {
		// The fill receives the outer seam's `database`, which any tool reports in any build, so the mock is rejected in a
		// release build, where the graph wrongly says its twin's error is one the tool checks only where the generated mocks
		// compile.
		let twinGraph = Self.innerSeamGraph(named: "a mock rejected in a release build", tests: Self.fillReadingOuterSeamsValue, expectedTwinErrorSite: ("Tests/TestsTypes.swift", "@Received let database: Database"))
		let graph = GraphFuzzerCallingMockGraph(
			name: "a mock rejected in a release build",
			mockFiles: twinGraph.mockFiles,
			twinFiles: twinGraph.twinFiles,
			callerTypeName: "Host",
			callerIsPublic: false,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: ("Tests/TestsTypes.swift", "@Received let database: Database"),
			mockBuild: .release,
			twinErrorIsCheckedOnlyWhereMocksCompile: true,
		)

		let result = try await GraphFuzzerCallingMockCheck.run(graph, seed: 0)

		#expect(graph.mockSkipsTwinsError)
		#expect(result.twinHasIntendedOutcome)
		#expect(result.mockSites == result.twinSites)
		#expect(result.failure?.kind == .callingMockRejectedWhereMockConditionIsInactive)
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
			if draw.passesUpExactlyTheExpectedLabels {
				#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels, "seed \(seed) (\(draw.cell))")
			}
			switch (result.failure, knownIssue) {
			case (nil, nil):
				break
			case let (nil, knownIssue?):
				// A mock that does not compile shows only where the run compiles it.
				if compileVerificationIsEnabled || !knownIssue.signatures.allSatisfy({ $0 == .callingMockDoesNotCompile }) {
					Issue.record("Stale known issue: calling-mock seed \(seed) (\(draw.cell)) passes, so remove it from the entry “\(knownIssue.reason)”")
				}
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

	/// Seed 450 draws the first graph of `fillInstantiatesWhatNothingFulfills/internal/plain`, the first of its block: an
	/// internal calling mock whose fill's implementation instantiates what nothing in its module fulfills. It takes the
	/// twin's builders and fills the place, where it passed the place up before (`DependencyTreeGenerator.holesFilled`),
	/// which the check reports as an unclassified pass-up.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_takesTwinsBuilders_whenDrawnFillInstantiatesWhatNothingFulfills() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 450)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 450)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillInstantiatesWhatNothingFulfills, caller: .internal, place: .plain))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(!draw.expectedPassUpLabels.isEmpty)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 490 draws the first graph of `fillInstantiatesTypeNoDeclarationCanFulfill/internal/plain`, the first of its block:
	/// an internal calling mock whose fill's implementation instantiates a type spelled as no hole can be, which no
	/// declaration fulfills. It reports production's error at the same site, where it passed the place up before
	/// (`DependencyTreeGenerator.validateFillsInstantiateOnlyWhatCanBeFulfilled`), which the check reports as acceptance where
	/// the twin is rejected.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsError_whenDrawnFillInstantiatesTypeNoDeclarationCanFulfill() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 490)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 490)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillInstantiatesTypeNoDeclarationCanFulfill, caller: .internal, place: .plain))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.mockSites != nil && result.mockSites == result.twinSites)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose fill instantiates a type no declaration can fulfill draw each spelling no hole can have
	/// in the pinned number of graphs, and both caller kinds in twenty.
	@Test
	func fillInstantiatesTypeNoDeclarationCanFulfillDraw_drawsEachSpelling_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillInstantiatesTypeNoDeclarationCanFulfill }
		var counts = [String: Int]()
		for draw in draws {
			counts[draw.fillHoles?.spellingNoHoleCanHave?.type ?? "none", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
		}
		print("calling-mock spellings no hole can have \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == ["[String]": 11, "[String: Int]": 11, "() -> Int": 7, "(Int, Int)": 11, "internal": 20, "public": 20])
	}

	/// Seed 550 draws the first graph of `fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive/internal/
	/// plain`, the first of its block: seed 490's shape, in a build that does not tell the tool the mock condition is
	/// active. The tool checks the fill production rejects only where the generated mocks compile
	/// (`DependencyTreeGenerator.validateFillsInstantiateOnlyWhatCanBeFulfilled`, under `compilesGeneratedMocks`), so the
	/// mock passes the place up, where its twin reports the error; with the check run in every build, the mock reports it,
	/// which the check reports as `callingMockRejectedWhereMockConditionIsInactive`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_passesPlaceUp_whenDrawnFillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 550)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 550)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, caller: .internal, place: .plain))
		#expect(draw.graph.mockSkipsTwinsError)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.mockSites == nil)
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(result.passUps.map(\.reason) == [.mockConditionIsInactive])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose fill instantiates a type no declaration can fulfill where the mock condition is
	/// inactive draw each build that leaves it inactive, each spelling no hole can have, and each caller kind, in the
	/// pinned number of graphs, and the tool skips the twin's error in the mock, which the cell test then requires to pass
	/// the place up, in the pinned number, at least ten.
	@Test
	func fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactiveDraw_drawsEachBuild_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive }
		var counts = [String: Int]()
		for draw in draws {
			counts["\(draw.mockBuild)", default: 0] += 1
			if draw.graph.mockSkipsTwinsError {
				counts["mockSkipsTwinsError", default: 0] += 1
				counts["mockSkipsTwinsError \(draw.mockBuild)", default: 0] += 1
			}
			counts[draw.fillHoles?.spellingNoHoleCanHave?.type ?? "none", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
		}
		print("calling-mock builds where the mock condition is inactive \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"debugWithoutMockCondition": 33,
			"release": 27,
			"mockSkipsTwinsError": 30,
			"mockSkipsTwinsError debugWithoutMockCondition": 14,
			"mockSkipsTwinsError release": 16,
			"[String]": 21,
			"[String: Int]": 10,
			"() -> Int": 19,
			"(Int, Int)": 10,
			"internal": 20,
			"public": 20,
			"listed": 20,
		])
		#expect(GraphFuzzerCallingMockDraw(seed: 0).mockBuild == .compilesGeneratedMocks)
	}

	/// Seed 910 draws the first graph of `fillCallsMockTakingGuardedValueWhereMockConditionIsInactive/internal/plain`, the
	/// first of its block: the fill that receives the caller's own value, whose hand-written mock also takes a value the
	/// fill declares only inside an `#if` clause the build does not select, in a build that does not tell the tool the mock
	/// condition is active. The tool reports that parameter only where the generated mocks compile, so the mock fills the
	/// place with a call of the hand-written mock, as its twin fills it with the fill's initializer. With the fill's call
	/// generated from the dependencies alone again (`Initializer.createInitializerArgumentList`), the mock stops at the
	/// unlocated `unexpectedArgument`, which the check reports as `callingMockRejectsWhereTwinAccepts`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlace_whenDrawnFillCallsMockTakingGuardedValueWhereMockConditionIsInactive() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 910)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 910)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, caller: .internal, place: .plain))
		#expect(!draw.mockBuild.compilesGeneratedMocks)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.mockSites == nil)
		#expect(result.passUps.isEmpty)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose fill's hand-written mock takes a value only an inactive clause declares draw each
	/// build that leaves the mock condition inactive, each condition of the clause, each caller kind and each place, in the
	/// pinned number of graphs, each at least ten.
	@Test
	func fillCallsMockTakingGuardedValueWhereMockConditionIsInactiveDraw_drawsEachBuild_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive }
		var counts = [String: Int]()
		for draw in draws {
			counts["\(draw.mockBuild)", default: 0] += 1
			counts["#if \(draw.guardedValueCondition ?? "none")", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
		}
		print("calling-mock fills whose mock takes a guarded value \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"debugWithoutMockCondition": 33,
			"release": 27,
			"#if FUZZ_GUARD": 23,
			"#if DEBUG": 37,
			"internal": 20,
			"public": 20,
			"listed": 20,
			"plain": 30,
			"deferred": 30,
		])
		#expect(counts.values.allSatisfy { $0 >= 10 })
		#expect(GraphFuzzerCallingMockDraw(seed: 0).guardedValueCondition == nil)
	}

	/// Seed 1030 draws the first graph of `calledTypeReceivesValueOnlyIfAvailableNothingProvides/internal/plain`, the first
	/// of its block: an internal calling mock whose called type's tree receives, only if available, a value nothing in the
	/// calling tree provides. Its twin's seam takes the value as a parameter, and the mock takes an override for it, which the
	/// probe hands a value the twin is handed too, so both build one tree. It fails with the override reverted
	/// (`ScopeGenerator.receivedOnlyByPublicMockCallsLeftOut`), when the probe passes an override `mock()` does not take.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_passesOverrideToCall_whenDrawnCalledTypeReceivesValueOnlyIfAvailableNothingProvides() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 1_030)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 1_030)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .calledTypeReceivesValueOnlyIfAvailableNothingProvides, caller: .internal, place: .plain))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose called type receives only if available a value nothing in the calling tree provides
	/// draw each receiver, each caller kind and each place, in the pinned number of graphs, each at least ten.
	@Test
	func calledTypeReceivesValueOnlyIfAvailableNothingProvidesDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .calledTypeReceivesValueOnlyIfAvailableNothingProvides }
		var counts = [String: Int]()
		for draw in draws {
			counts[draw.valueNothingProvides?.receiverIsBeneathCalledType == true ? "beneathCalledType" : "calledType", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
		}
		print("calling-mock called types receiving a value nothing provides \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"calledType": 21,
			"beneathCalledType": 39,
			"internal": 20,
			"public": 20,
			"listed": 20,
			"plain": 30,
			"deferred": 30,
		])
		#expect(counts.values.allSatisfy { $0 >= 10 })
		#expect(GraphFuzzerCallingMockDraw(seed: 0).valueNothingProvides == nil)
	}

	/// Seed 1090 draws the first graph of `calledTypeHoldsPlaceLazily/internal/plain`, the first of its block: an internal
	/// calling mock whose called type holds its place in a `LazilyInstantiated` beside a place by value, which one fill of
	/// the caller's module fills, reading the caller's value. Its twin fills both places, and so does the mock, whose values
	/// the probe compares with the twin's. It fails with a place held in a lazy wrapper left unfilled
	/// (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)` skipping a hole whose property is a `LazilyInstantiated` or
	/// `SendableLazilyInstantiated`), when the mock passes up `feedServiceBuilder`, which no reason explains.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsLazyPlaceAsTwin_whenDrawnCalledTypeHoldsPlaceLazily() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 1_090)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 1_090)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .calledTypeHoldsPlaceLazily, caller: .internal, place: .plain))
		#expect(draw.lazyPlace?.wrapper == "LazilyInstantiated")
		#expect(draw.lazyPlace?.besideByValuePlace == true)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose called type holds its place lazily draw each wrapper, with and without a place by
	/// value beside it, and each caller kind, in the pinned number of graphs, each at least ten. The block draws only a
	/// plain place: the lazy wrapper is the place's deferral.
	@Test
	func calledTypeHoldsPlaceLazilyDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .calledTypeHoldsPlaceLazily }
		var counts = [String: Int]()
		for draw in draws {
			counts[draw.lazyPlace?.wrapper ?? "none", default: 0] += 1
			counts[draw.lazyPlace?.besideByValuePlace == true ? "besideByValuePlace" : "alone", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
		}
		print("calling-mock called types holding places lazily \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"LazilyInstantiated": 15,
			"SendableLazilyInstantiated": 15,
			"besideByValuePlace": 18,
			"alone": 12,
			"internal": 10,
			"public": 10,
			"listed": 10,
			"plain": 30,
		])
		#expect(counts.values.allSatisfy { $0 >= 10 })
		#expect(GraphFuzzerCallingMockDraw(seed: 0).lazyPlace == nil)
	}

	/// Seed 1120 draws the first graph of `calledTypeHoldsSecondHoleType/internal/plain`, the first of its block: an
	/// internal calling mock whose called type holds a place of a second hole type, `MeterService`, beside the first, each
	/// filled by a type of the caller's module. Its twin fills both, and so does the mock, whose values the probe compares
	/// with the twin's. It fails with only the first hole type of each call filled
	/// (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)` skipping every hole whose instantiated type is not the call's
	/// first hole's), when the mock passes up `meterServiceBuilder`, which no reason explains.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsSecondHoleTypeAsTwin_whenDrawnCalledTypeHoldsSecondHoleType() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 1_120)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 1_120)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .calledTypeHoldsSecondHoleType, caller: .internal, place: .plain))
		#expect(draw.secondHole?.fill != .invisible)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose called type holds a place of a second hole type draw each fill of it, the place before
	/// and after the first hole's, each caller kind and each place, in the pinned number of graphs, each at least ten.
	@Test
	func calledTypeHoldsSecondHoleTypeDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .calledTypeHoldsSecondHoleType }
		var counts = [String: Int]()
		for draw in draws {
			counts[draw.secondHole?.fill.rawValue ?? "none", default: 0] += 1
			counts[draw.secondHole?.isBeforeFirstPlace == true ? "beforeFirstPlace" : "afterFirstPlace", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
		}
		print("calling-mock called types holding a second hole type \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"readsValue": 21,
			"readsNothing": 23,
			"invisible": 16,
			"beforeFirstPlace": 29,
			"afterFirstPlace": 31,
			"internal": 20,
			"public": 20,
			"listed": 20,
			"plain": 30,
			"deferred": 30,
		])
		#expect(counts.values.allSatisfy { $0 >= 10 })
		#expect(GraphFuzzerCallingMockDraw(seed: 0).secondHole == nil)
	}

	/// Seed 1180 draws the first graph of `callerForwardsValueFillReads/internal/plain`, the first of its block: an internal
	/// calling mock whose caller forwards `database`, which the fill of the called type's place reads. Its twin fills the
	/// place from its forwarded value, and so does the mock, from the value its `mock()` is passed, which the probe compares
	/// with the twin's. It fails with a place whose fill receives anything beside its place's fields passed up
	/// (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)` skipping such a fill), when the mock passes up
	/// `trackerServiceBuilder`, which no reason explains.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlaceFromForwardedValue_whenDrawnCallerForwardsValueFillReads() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 1_180)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 1_180)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .callerForwardsValueFillReads, caller: .internal, place: .plain))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose caller forwards the value its fill reads draw a required and an only-if-available
	/// read, each caller kind and each place, in the pinned number of graphs, each at least ten.
	@Test
	func callerForwardsValueFillReadsDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .callerForwardsValueFillReads }
		var counts = [String: Int]()
		for draw in draws {
			counts[draw.forwardedValue?.fillReceivesOnlyIfAvailable == true ? "onlyIfAvailable" : "required", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
		}
		print("calling-mock callers forwarding the value their fill reads \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"required": 25,
			"onlyIfAvailable": 35,
			"internal": 20,
			"public": 20,
			"listed": 20,
			"plain": 30,
			"deferred": 30,
		])
		#expect(counts.values.allSatisfy { $0 >= 10 })
		#expect(GraphFuzzerCallingMockDraw(seed: 0).forwardedValue == nil)
	}

	/// Seed 1240 draws the first graph of `placeInstantiatedOnlyIfAvailable/internal/plain`, the first of its block: an
	/// internal calling mock whose called type instantiates its place only if available, with a type of the caller's
	/// module that fulfills it. Its twin fills the place, and so does the mock, which the probe compares with the twin's.
	/// It fails with the called public mock binding the place `nil` rather than taking a builder for it
	/// (`createMockTypeDescriptionToScopeMapping` lowering it as `unavailableDependency` where the map builds holes), when
	/// the mock's place is `nil` where the twin's holds the fill.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlace_whenDrawnPlaceInstantiatedOnlyIfAvailableWithVisibleImplementation() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 1_240)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 1_240)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .placeInstantiatedOnlyIfAvailable, caller: .internal, place: .plain))
		#expect(draw.optionalPlace?.implementationIsVisible == true)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 1243 draws the second graph of the same cell, in which no type of the caller's module fulfills the place: the
	/// twin takes the place's optional builder, and the mock passes up exactly that builder, which defaults to `{ nil }`,
	/// so the mock called with no argument holds what the twin handed `{ nil }` holds. It fails with that same change, when
	/// the mock passes nothing up.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_passesUpOptionalBuilder_whenDrawnPlaceInstantiatedOnlyIfAvailableWithoutVisibleImplementation() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 1_243)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 1_243)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .placeInstantiatedOnlyIfAvailable, caller: .internal, place: .plain))
		#expect(draw.optionalPlace?.implementationIsVisible == false)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == draw.graph.expectedPassUpLabels)
		#expect(result.passUps.allSatisfy { $0.reason == .noVisibleImplementation })
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose called type instantiates its place only if available draw a caller's module with and
	/// without a type that fulfills the place, and each caller kind, in the pinned number of graphs, each at least ten. The
	/// block draws only a plain place.
	@Test
	func placeInstantiatedOnlyIfAvailableDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .placeInstantiatedOnlyIfAvailable }
		var counts = [String: Int]()
		for draw in draws {
			counts[draw.optionalPlace?.implementationIsVisible == true ? "visible" : "invisible", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
		}
		print("calling-mock places instantiated only if available \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"visible": 15,
			"invisible": 15,
			"internal": 10,
			"public": 10,
			"listed": 10,
			"plain": 30,
		])
		#expect(counts.values.allSatisfy { $0 >= 10 })
		#expect(GraphFuzzerCallingMockDraw(seed: 0).optionalPlace == nil)
	}

	/// Seed 970 draws the first graph of `fillConstructsTypeCallerModuleCannotReach/internal/plain`, the first of its block:
	/// an internal calling mock whose fill instantiates a protocol only a type of the outer module fulfills, which the
	/// caller's module cannot reach, in a build that compiles the generated mocks. Its twin reports the access error, and
	/// so does the mock, at the same declarations, where it passed the place up before
	/// (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)`), which the check reports as acceptance where the twin is rejected.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsAccessErrors_whenDrawnFillConstructsTypeCallerModuleCannotReach() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 970)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 970)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillConstructsTypeCallerModuleCannotReach, caller: .internal, place: .plain))
		#expect(draw.mockBuild == .compilesGeneratedMocks)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.mockSites != nil && result.mockSites == result.twinSites)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 971 draws the first graph of the shape whose fill constructs a type the caller's module cannot reach in a build
	/// that leaves the mock condition inactive, `fillConstructsTypeCallerModuleCannotReach/internal/deferred` in a release
	/// build, which compiles no generated mock: the mock is accepted and passes the place up, where its twin reports the
	/// access error. With the fill made in every build, the mock reports the error, which the check reports as
	/// `callingMockRejectedWhereMockConditionIsInactive`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_passesPlaceUp_whenDrawnFillConstructsTypeCallerModuleCannotReachWhereMockConditionIsInactive() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 971)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 971)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillConstructsTypeCallerModuleCannotReach, caller: .internal, place: .deferred))
		#expect(draw.graph.mockSkipsTwinsError)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.mockSites == nil)
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(result.passUps.map(\.reason) == [.mockConditionIsInactive])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 977 draws the first graph of `fillConstructsTypeCallerModuleCannotReach` whose type is out of reach only
	/// through its hand-written mock, in a build that compiles the generated mocks, `internal/deferred`: the type and its
	/// initializer are `public` and its mock `internal`, in a module of the caller's package. Its twin, which calls the
	/// initializer, is accepted; the mock's fill calls the hand-written mock, which its module cannot reach, so the mock
	/// reports that mock's access, an error of its own (contract rule 7). With the fill passed up in every build, as before
	/// (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)`), the mock is accepted, which the check reports as
	/// `callingMockAcceptedWhereItsFillCallsMockItCannotReach`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsHandWrittenMocksAccessError_whenDrawnFillCallsMockCallerModuleCannotReach() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 977)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 977)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillConstructsTypeCallerModuleCannotReach, caller: .internal, place: .deferred))
		#expect(draw.mockBuild == .compilesGeneratedMocks)
		#expect(draw.unreachableConstruction?.access == .internalMockInCallersPackage)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.twinSites == nil)
		#expect(result.mockSites?.map(\.declaration) == draw.unreachableConstruction?.mockMethodLine.map { [$0] })
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose fill constructs a type the caller's module cannot reach draw each declaration of the
	/// type, each place of it in the fill's tree, each build, each caller kind and each place, in the pinned number of
	/// graphs, each at least ten, and the tool skips the twin's error in the mock, which the cell test then requires to pass
	/// the place up, in the pinned number, at least ten. The type out of reach only through its hand-written mock is drawn
	/// in builds that compile the generated mocks and in builds that do not, at least ten of each.
	@Test
	func fillConstructsTypeCallerModuleCannotReachDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillConstructsTypeCallerModuleCannotReach }
		var counts = [String: Int]()
		for draw in draws {
			counts["\(draw.mockBuild)", default: 0] += 1
			if draw.graph.mockSkipsTwinsError {
				counts["mockSkipsTwinsError", default: 0] += 1
			}
			counts[draw.unreachableConstruction?.access.rawValue ?? "none", default: 0] += 1
			if draw.unreachableConstruction?.access == .internalMockInCallersPackage {
				counts["internalMockInCallersPackage \(draw.graph.mockSkipsTwinsError ? "mockSkipsTwinsError" : "\(draw.mockBuild)")", default: 0] += 1
			}
			counts[draw.unreachableConstruction?.isBeneathFill == true ? "beneathFill" : "inFill", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
		}
		print("calling-mock fills constructing a type the caller's module cannot reach \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"compilesGeneratedMocks": 28,
			"debugWithoutMockCondition": 18,
			"release": 14,
			"mockSkipsTwinsError": 32,
			"internalInCallersPackage": 18,
			"packageInAnotherPackage": 17,
			"internalMockInCallersPackage": 25,
			"internalMockInCallersPackage compilesGeneratedMocks": 15,
			"internalMockInCallersPackage mockSkipsTwinsError": 10,
			"inFill": 34,
			"beneathFill": 26,
			"internal": 20,
			"public": 20,
			"listed": 20,
			"plain": 30,
			"deferred": 30,
		])
		#expect(counts.values.allSatisfy { $0 >= 10 })
		#expect(GraphFuzzerCallingMockDraw(seed: 0).unreachableConstruction == nil)
	}

	/// Seed 730 draws the first graph of `fillReceivesCallersLazyValueBelowCalledRoot/internal/plain`, the first of its
	/// block: an internal calling mock whose call's place is a level below the called type's root, filled by a type that
	/// receives the caller's lazily held value, which the called type's tree also receives, only if available. The caller
	/// holds the value beside a mocked intermediate type, which receives the value too and calls the called type. Its twin
	/// fills the place, handing the fill the caller's own wrapper, as the same types built inline do, so the mock must
	/// build their values. It fails with the fill's reading of the caller's own value reverted, when the mock's module
	/// names a builder it does not take and does not compile.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsInlineValues_whenDrawnFillReceivesCallersLazyValueBelowCalledRoot() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 730)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 730)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillReceivesCallersLazyValueBelowCalledRoot, caller: .internal, place: .plain))
		#expect(draw.callerLazyValue?.call == .mockedIntermediateReceivingValueCalls)
		#expect(draw.callerLazyValue?.receivesOnlyIfAvailable == true)
		#expect(draw.graph.comparesValuesWithInline)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 763 draws a graph of `fillReceivesCallersLazyValueBelowCalledRoot/public/deferred` whose called type also holds a
	/// second level with a second place, whose fill reads nothing and builds the called type again
	/// (`CallerLazyValue.secondPlaceCallsAgain`), so the called type is re-entered, and the place's fill reads the caller's
	/// wrapper beside its fields: the mock passes the place up whole, and then the second place, whose fill calls the
	/// called type, where the twin fills both (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`).
	/// It fails with that gate reverted, when the mock fills both places and passes nothing up.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_passesPlacesUpWhole_whenDrawnSecondPlacesFillCallsCalledTypeAgain() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 763)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 763)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillReceivesCallersLazyValueBelowCalledRoot, caller: .public, place: .deferred))
		#expect(draw.callerLazyValue?.call == .callerCalls)
		#expect(draw.callerLazyValue?.secondPlaceCallsAgain == true)
		#expect(draw.callerLazyValue?.buildsPlaceInSendableFunctionToo == false)
		#expect(draw.callerLazyValue?.fillReadsInstanceCalledTypeDoesNotHold == false)
		#expect(draw.callerLazyValue?.secondPlaceFillDeclaresValueAgain == false)
		#expect(draw.graph.fillGatePassesUp)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(result.passUps.map(\.reason) == [.fillOfReenteredCallReadsLazyValue, .fillOfReenteredCallReadsLazyValue])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 766 draws a graph of `fillReceivesCallersLazyValueBelowCalledRoot/internal/plain` whose fill reads the caller's
	/// value by value while the called type holds no copy of it, and whose second place's fill reads none of it and builds
	/// the called type again (`CallerLazyValue.fillReadsInstanceCalledTypeDoesNotHold`): the re-entered call's root level
	/// function takes the value, which the second place's fill holds only as the caller's wrapper, so the mock passes the
	/// place up whole, and then the second place, where the twin fills both
	/// (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`). It fails with that gate reverted,
	/// when the mock fills both places and passes nothing up.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_passesPlacesUpWhole_whenDrawnSecondPlacesFillLeavesValueHeldLazilyUnreadAndCallsCalledTypeAgain() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 766)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 766)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillReceivesCallersLazyValueBelowCalledRoot, caller: .internal, place: .plain))
		#expect(draw.callerLazyValue?.call == .callerCalls)
		#expect(draw.callerLazyValue?.secondPlaceCallsAgain == true)
		#expect(draw.callerLazyValue?.fillReadsInstanceCalledTypeDoesNotHold == true)
		#expect(draw.graph.fillGatePassesUp)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(result.passUps.map(\.reason) == [.fillOfReenteredCallReadsLazyValue, .fillOfReenteredCallReadsLazyValue])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 790 draws the first graph of `fillHoldsBuilderOfEnclosingCalledType/internal/plain`, the first of its block: an
	/// internal calling mock whose fill of the enclosing called type's place builds a third module's type, whose public mock
	/// holds a builder of the enclosing called type. The calling mock's call inside the fill re-enters the root level
	/// function of the call that encloses it, as the twin's call re-enters the enclosing seam call's, so it passes up no
	/// place, and the called type the third module's type builds through its builder, which runs the re-entered level
	/// function, holds the caller's instance of the `LazilyInstantiated` value the graph also draws, as the twin's does
	/// (`enclosingCalledTypeLazyValueWrapper`).
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reentersEnclosingCallsRootLevel_whenDrawnFillHoldsBuilderOfEnclosingCalledType() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 790)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 790)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillHoldsBuilderOfEnclosingCalledType, caller: .internal, place: .plain))
		#expect(draw.enclosingBuilder == .instantiator)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == [])
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 793 draws the first `.public` graph of `fillHoldsBuilderOfEnclosingCalledType` whose fill also instantiates
	/// `beacon: any Beacon`, which no declaration fulfills (`reenteringFillInstantiatesWhatNothingFulfills`): the `.public`
	/// calling mock takes `beaconBuilder`, as the twin does, and hands it through the struct of its own level, which the
	/// call of the third module's public mock inside the fill hands on to the root level function it re-enters, as the
	/// twin's call of the third module's seam does. It fails with that struct not handed on, the mock then calling the
	/// re-entered level function without it, and with the gate that passed such a place up instead, the mock then passing
	/// up a place the twin fills.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_handsCallersStructThroughReentry_whenDrawnReenteringFillInstantiatesWhatNothingFulfills() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 793)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 793)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillHoldsBuilderOfEnclosingCalledType, caller: .public, place: .deferred))
		#expect(draw.reenteringFillInstantiatesWhatNothingFulfills)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == ["beaconBuilder"])
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 804 draws the first `.public` graph of `fillHoldsBuilderOfEnclosingCalledType` whose third module's type holds
	/// the enclosing called type in a `SendableInstantiator` and whose fill also instantiates `beacon: any Beacon`, which no
	/// declaration fulfills: the fill is built in the `@Sendable` function of that builder, so the twin and the calling mock
	/// take `beaconSendableBuilder`, and the no-scope initializer of the fill's level, of the plain family, whose member for
	/// the call inside the fill returns the third module's `@Sendable` family's struct, takes a `@Sendable` builder. It fails
	/// with that initializer taking a builder that is not `@Sendable`: neither the twin nor the mock compiles.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_takesSendableBuilderThroughReentry_whenDrawnReenteringFillIsHeldInSendableInstantiator() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 804)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 804)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillHoldsBuilderOfEnclosingCalledType, caller: .public, place: .plain))
		#expect(draw.enclosingBuilder == .sendableInstantiator)
		#expect(draw.reenteringFillInstantiatesWhatNothingFulfills)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == ["beaconSendableBuilder"])
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose fill holds a builder of the enclosing called type draw each builder, each caller kind
	/// and each place in the pinned number of graphs, and, for each caller kind, a fill that also instantiates what nothing
	/// fulfills and an enclosing called type that receives the caller's value in each wrapper only if available, each wrapper
	/// in at least ten graphs. A `LazilyInstantiated` builder is drawn beside a deferred place only, and a `LazilyInstantiated`
	/// value never beside a `SendableInstantiator`.
	@Test
	func fillHoldsBuilderOfEnclosingCalledTypeDraw_drawsEachBuilder_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillHoldsBuilderOfEnclosingCalledType }
		var counts = [String: Int]()
		for draw in draws {
			counts["\(draw.enclosingBuilder?.rawValue ?? "none") \(draw.cell.place.rawValue)", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			if draw.reenteringFillInstantiatesWhatNothingFulfills {
				counts["reenteringFillInstantiatesWhatNothingFulfills \(draw.cell.caller.rawValue)", default: 0] += 1
			}
			if let wrapper = draw.enclosingCalledTypeLazyValueWrapper {
				counts["value \(wrapper) \(draw.cell.caller.rawValue)", default: 0] += 1
			}
		}
		print("calling-mock builders of the enclosing called type \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == ["instantiator plain": 18, "instantiator deferred": 11, "sendableInstantiator plain": 12, "sendableInstantiator deferred": 11, "lazilyInstantiated deferred": 8, "internal": 20, "public": 20, "listed": 20, "reenteringFillInstantiatesWhatNothingFulfills internal": 13, "reenteringFillInstantiatesWhatNothingFulfills public": 12, "reenteringFillInstantiatesWhatNothingFulfills listed": 11, "value LazilyInstantiated internal": 5, "value LazilyInstantiated public": 6, "value LazilyInstantiated listed": 5, "value SendableLazilyInstantiated internal": 8, "value SendableLazilyInstantiated public": 5, "value SendableLazilyInstantiated listed": 8])
		#expect(GraphFuzzerCallingMockDraw(seed: 0).enclosingBuilder == nil)
		#expect(!GraphFuzzerCallingMockDraw(seed: 0).reenteringFillInstantiatesWhatNothingFulfills)
		#expect(GraphFuzzerCallingMockDraw(seed: 0).enclosingCalledTypeLazyValueWrapper == nil)
		for wrapper in ["LazilyInstantiated", "SendableLazilyInstantiated"] {
			#expect(draws.filter { $0.enclosingCalledTypeLazyValueWrapper == wrapper }.count >= 10, "\(wrapper)")
		}
		#expect(!draws.contains { $0.enclosingBuilder == .sendableInstantiator && $0.enclosingCalledTypeLazyValueWrapper == "LazilyInstantiated" })
	}

	/// Seeds 790 and 794 draw the first graphs of `fillHoldsBuilderOfEnclosingCalledType` whose enclosing called type receives
	/// the caller's value only if available (`enclosingCalledTypeLazyValueWrapper`), in a `LazilyInstantiated` and a
	/// `SendableLazilyInstantiated`: the call of the third module's public mock inside the fill passes it the caller's
	/// wrapper, which the called mock takes as it is, so the called type the third module's type builds again holds the
	/// caller's value, as the twin's does. Seed 794's fill also instantiates what nothing fulfills, so its mock takes
	/// `beaconBuilder`. Each fails where the call passes `nil` instead, as it did before a public mock took the wrapper.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: [UInt64(790), 794])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_handsCalledTypeBuiltAgainCallersInstance_whenDrawnEnclosingCalledTypeReceivesCallersLazyValueOnlyIfAvailable(seed: UInt64) async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: seed)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: seed)

		#expect(draw.cell.shape == .fillHoldsBuilderOfEnclosingCalledType)
		#expect(draw.enclosingCalledTypeLazyValueWrapper == (seed == 790 ? "LazilyInstantiated" : "SendableLazilyInstantiated"))
		#expect(draw.reenteringFillInstantiatesWhatNothingFulfills == (seed == 794))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == (seed == 794 ? ["beaconBuilder"] : []))
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 850 draws the first graph of `fillRequiresValueCalledTypeReceivesInOptionalWrapper/internal/plain`, the first of
	/// its block: an internal calling mock whose fill requires the value the called type's tree receives only if available
	/// in a lazy wrapper. It reports, at the twin's sites, that the called mock hands the fill only that optional wrapper.
	/// It fails with that report removed (`findingsOfFill`'s `publicMockHandsOptionalWrapperOfRequiredValue`), when the mock
	/// is accepted, and its fill passes the wrapper where the fill requires its instance.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsErrorAtTwinsSites_whenDrawnFillRequiresValueCalledTypeReceivesInOptionalWrapper() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 850)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 850)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillRequiresValueCalledTypeReceivesInOptionalWrapper, caller: .internal, place: .plain))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.mockSites != nil && result.mockSites == result.twinSites)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 858 draws the first graph of `fillRequiresValueCalledTypeReceivesInOptionalWrapper` whose called type and the
	/// sibling it instantiates both receive the value only if available (`calledTypeReceivesBesideSibling`): the twin’s seam
	/// takes the called type’s own property as its parameter, which the sibling receives from the called type, so its notes
	/// name the called type and the fill, and the calling mock’s must too. It fails with the mock’s notes naming the sibling
	/// as well, as they did before a public mock’s root level left out the receivers of a form the mocked type provides
	/// (`DependencyTreeGenerator.publicMockRootLevel`).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsNotes_whenDrawnCalledTypeAndSiblingReceiveValueInOptionalWrapper() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 858)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 858)

		#expect(draw.optionalWrapperValue?.calledTypeReceivesBesideSibling == true)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.mockSites != nil && result.mockSites == result.twinSites)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose fill requires a value the called type receives only if available in a lazy wrapper draw
	/// each wrapper, each receiver and each fill, with and without a build of the called type again, in the pinned number
	/// of graphs, and each caller kind in twenty.
	@Test
	func fillRequiresValueCalledTypeReceivesInOptionalWrapperDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillRequiresValueCalledTypeReceivesInOptionalWrapper }
		var counts = [String: Int]()
		for draw in draws {
			let value = draw.optionalWrapperValue
			let receiver = value?.siblingReceives == true ? (value?.calledTypeReceivesBesideSibling == true ? "calledTypeAndSibling" : "sibling") : "calledType"
			counts["\(value?.wrapper ?? "none") \(receiver) \(value?.fillCallsAgain == true ? "callsAgain" : "callsOnce")", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
		}
		print("calling-mock fills requiring a value received in an optional wrapper \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == ["LazilyInstantiated calledType callsAgain": 13, "LazilyInstantiated calledType callsOnce": 8, "LazilyInstantiated sibling callsAgain": 5, "LazilyInstantiated sibling callsOnce": 2, "LazilyInstantiated calledTypeAndSibling callsAgain": 1, "LazilyInstantiated calledTypeAndSibling callsOnce": 1, "SendableLazilyInstantiated calledType callsAgain": 7, "SendableLazilyInstantiated calledType callsOnce": 12, "SendableLazilyInstantiated sibling callsAgain": 4, "SendableLazilyInstantiated sibling callsOnce": 4, "SendableLazilyInstantiated calledTypeAndSibling callsAgain": 2, "SendableLazilyInstantiated calledTypeAndSibling callsOnce": 1, "internal": 20, "public": 20, "listed": 20])
		#expect(GraphFuzzerCallingMockDraw(seed: 0).optionalWrapperValue == nil)
		#expect(draws.first { $0.optionalWrapperValue?.calledTypeReceivesBesideSibling == true }?.seed == 858)
	}

	/// Seed 762 draws a graph of `fillReceivesCallersLazyValueBelowCalledRoot/public/plain` whose called type holds a second
	/// place whose fill instantiates a value of its own under the value's label and builds the called type again, while
	/// the place's fill reads the value's instance and the called type keeps its copy
	/// (`CallerLazyValue.secondPlaceFillDeclaresValueAgain`): both places are filled, and the mock, compared with its twin,
	/// builds what the twin builds, the second place's value in the called type built again. It fails with the twin's level
	/// function of the place handing that build's fill the enclosing value rather than the memo of the build
	/// (`ScopeGenerator.FillDispatcher`'s `structDeclaration`), when the twin builds other values.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsTwinsValues_whenDrawnSecondPlacesFillDeclaresValueAgainAndCallsCalledTypeAgain() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 762)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 762)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillReceivesCallersLazyValueBelowCalledRoot, caller: .public, place: .plain))
		#expect(draw.callerLazyValue?.call == .callerCalls)
		#expect(draw.callerLazyValue?.secondPlaceFillDeclaresValueAgain == true)
		#expect(!draw.graph.fillGatePassesUp)
		#expect(!draw.graph.comparesValuesWithInline)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 734 draws the first graph of `fillReceivesCallersLazyValueBelowCalledRoot/listed/plain`, whose called type
	/// receives the value only if available and also builds the place inside a `SendableInstantiator`'s `@Sendable`
	/// function (`CallerLazyValue.buildsPlaceInSendableFunctionToo`), where the place carries no field of the value. It fails
	/// with that place counted as the caller's own only where it carries a declaration bound from the caller's argument,
	/// when the fill keeps a field no level hands it, and the mock names a builder it does not take.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsInlineValues_whenDrawnCalledTypeReceivingValueOnlyIfAvailableAlsoBuildsPlaceInSendableFunction() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 734)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 734)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillReceivesCallersLazyValueBelowCalledRoot, caller: .listed, place: .plain))
		#expect(draw.callerLazyValue?.receivesOnlyIfAvailable == true)
		#expect(draw.callerLazyValue?.buildsPlaceInSendableFunctionToo == true)
		#expect(draw.callerLazyValue?.secondPlaceCallsAgain == false)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The graphs of the shape whose fill receives the caller's lazy value below the called type's root draw each wrapper,
	/// each way the called type's tree receives the value, each call (`CallerLazyValue.Call`), each caller kind, each place,
	/// a second place whose fill calls the called type again, and, for the `Sendable` wrapper, a place built in a
	/// `@Sendable` function too, in the pinned number of graphs, each in at least ten; the pinned number pass their place up
	/// whole, where a fill calls the called type again (`CallerLazyValue.reentersCalledType`), which states no probes; and
	/// the cell test compiles and compares the pinned number of the others, each call with each place among them, and each
	/// later variation.
	@Test
	func fillReceivesCallersLazyValueBelowCalledRootDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillReceivesCallersLazyValueBelowCalledRoot }
		var counts = [String: Int]()
		for draw in draws {
			let variation = "\(draw.callerLazyValue?.wrapper ?? "none") \(draw.callerLazyValue?.receivesOnlyIfAvailable == true ? "onlyIfAvailable" : "byValue")"
			counts[variation, default: 0] += 1
			counts[draw.callerLazyValue?.wrapper ?? "none", default: 0] += 1
			counts[draw.callerLazyValue?.receivesOnlyIfAvailable == true ? "onlyIfAvailable" : "byValue", default: 0] += 1
			counts[draw.callerLazyValue?.call.rawValue ?? "none", default: 0] += 1
			counts["\(draw.callerLazyValue?.call.rawValue ?? "none") \(draw.cell.caller.rawValue)", default: 0] += 1
			counts[draw.callerLazyValue?.intermediate ?? "no intermediate", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
			for laterVariation in Self.callerLazyValueVariationsDrawnAfterTheCall(of: draw) {
				counts[laterVariation, default: 0] += 1
				counts["\(laterVariation) \(draw.cell.caller.rawValue)", default: 0] += 1
				counts["\(laterVariation) \(draw.cell.place.rawValue)", default: 0] += 1
			}
			if draw.callerLazyValue?.buildsPlaceInSendableFunctionToo == true {
				counts["buildsPlaceInSendableFunctionToo \(draw.callerLazyValue?.receivesOnlyIfAvailable == true ? "onlyIfAvailable" : "byValue")", default: 0] += 1
			}
			if draw.callerLazyValue?.reentersCalledType == true {
				counts["passesPlaceUpWhole", default: 0] += 1
			}
			if draw.joinsFilledCall {
				// Counted by `fillReceivesCallersLazyValueBelowCalledRootDraw_joinsFilledCall_inPinnedNumberOfGraphs`.
				counts["joinsFilledCall", default: 0] += 1
			} else if Self.comparesValues(ofSeed: draw.seed) {
				counts["compared", default: 0] += 1
				counts["compared \(variation)", default: 0] += 1
				counts["compared \(draw.callerLazyValue?.call.rawValue ?? "none")", default: 0] += 1
				counts["compared \(draw.callerLazyValue?.call.rawValue ?? "none") \(draw.cell.place.rawValue)", default: 0] += 1
				for laterVariation in Self.callerLazyValueVariationsDrawnAfterTheCall(of: draw) {
					counts["compared \(laterVariation)", default: 0] += 1
					counts["compared \(laterVariation) \(draw.cell.place.rawValue)", default: 0] += 1
				}
			}
		}
		print("calling-mock caller lazy values \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"Flow": 16,
			"LazilyInstantiated": 35,
			"LazilyInstantiated byValue": 18,
			"LazilyInstantiated onlyIfAvailable": 17,
			"Router": 11,
			"SendableLazilyInstantiated": 25,
			"SendableLazilyInstantiated byValue": 14,
			"SendableLazilyInstantiated onlyIfAvailable": 11,
			"buildsPlaceInSendableFunctionToo": 13,
			"buildsPlaceInSendableFunctionToo byValue": 7,
			"buildsPlaceInSendableFunctionToo deferred": 5,
			"buildsPlaceInSendableFunctionToo internal": 7,
			"buildsPlaceInSendableFunctionToo listed": 5,
			"buildsPlaceInSendableFunctionToo onlyIfAvailable": 6,
			"buildsPlaceInSendableFunctionToo plain": 8,
			"buildsPlaceInSendableFunctionToo public": 1,
			"byValue": 32,
			"callerCalls": 19,
			"callerCalls internal": 6,
			"callerCalls listed": 7,
			"callerCalls public": 6,
			"deferred": 30,
			"fillCallsAgain": 14,
			"fillCallsAgain internal": 4,
			"fillCallsAgain listed": 7,
			"fillCallsAgain public": 3,
			"fillReadsInstanceCalledTypeDoesNotHold": 13,
			"fillReadsInstanceCalledTypeDoesNotHold deferred": 8,
			"fillReadsInstanceCalledTypeDoesNotHold internal": 4,
			"fillReadsInstanceCalledTypeDoesNotHold listed": 3,
			"fillReadsInstanceCalledTypeDoesNotHold plain": 5,
			"fillReadsInstanceCalledTypeDoesNotHold public": 6,
			"internal": 20,
			"listed": 20,
			"mockedIntermediateCalls": 12,
			"mockedIntermediateCalls internal": 6,
			"mockedIntermediateCalls listed": 1,
			"mockedIntermediateCalls public": 5,
			"mockedIntermediateReceivingValueCalls": 15,
			"mockedIntermediateReceivingValueCalls internal": 4,
			"mockedIntermediateReceivingValueCalls listed": 5,
			"mockedIntermediateReceivingValueCalls public": 6,
			"no intermediate": 33,
			"onlyIfAvailable": 28,
			"plain": 30,
			"public": 20,
			"secondPlaceCallsAgain": 30,
			"secondPlaceCallsAgain deferred": 18,
			"secondPlaceCallsAgain internal": 13,
			"secondPlaceCallsAgain listed": 6,
			"secondPlaceCallsAgain plain": 12,
			"secondPlaceCallsAgain public": 11,
			"secondPlaceFillDeclaresValueAgain": 13,
			"secondPlaceFillDeclaresValueAgain deferred": 7,
			"secondPlaceFillDeclaresValueAgain internal": 4,
			"secondPlaceFillDeclaresValueAgain listed": 6,
			"secondPlaceFillDeclaresValueAgain plain": 6,
			"secondPlaceFillDeclaresValueAgain public": 3,
			"compared": 22,
			"compared LazilyInstantiated byValue": 10,
			"compared LazilyInstantiated onlyIfAvailable": 5,
			"compared SendableLazilyInstantiated byValue": 5,
			"compared SendableLazilyInstantiated onlyIfAvailable": 2,
			"compared buildsPlaceInSendableFunctionToo": 4,
			"compared buildsPlaceInSendableFunctionToo deferred": 1,
			"compared buildsPlaceInSendableFunctionToo plain": 3,
			"compared callerCalls": 9,
			"compared callerCalls deferred": 4,
			"compared callerCalls plain": 5,
			"compared mockedIntermediateCalls": 3,
			"compared mockedIntermediateCalls deferred": 1,
			"compared mockedIntermediateCalls plain": 2,
			"compared mockedIntermediateReceivingValueCalls": 10,
			"compared mockedIntermediateReceivingValueCalls deferred": 4,
			"compared mockedIntermediateReceivingValueCalls plain": 6,
			"compared secondPlaceCallsAgain": 5,
			"compared secondPlaceCallsAgain deferred": 3,
			"compared secondPlaceCallsAgain plain": 2,
			"compared secondPlaceFillDeclaresValueAgain": 11,
			"compared secondPlaceFillDeclaresValueAgain deferred": 5,
			"compared secondPlaceFillDeclaresValueAgain plain": 6,
			"passesPlaceUpWhole": 31,
			"joinsFilledCall": 11,
		])
		#expect(GraphFuzzerCallingMockDraw(seed: 0).callerLazyValue == nil)
	}

	/// Seed 530 draws the first graph of `seamCallerFillSharesBuilder/internal/plain`, the first of its block: a seam's own
	/// internal mock whose fill instantiates what nothing in its module fulfills, beside places of its own of the same hole
	/// types. It takes the twin's builders, one for a hole type and family its own places and the fill's share.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_takesTwinsBuilders_whenDrawnSeamCallersFillSharesBuilderWithItsOwnPlaces() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 530)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 530)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .seamCallerFillSharesBuilder, caller: .internal, place: .plain))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(draw.expectedBuilders.count < (draw.fillHoles?.builders.count ?? 0) + (draw.fillHoles?.protocols.count ?? 0))
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// Seed 610 draws the first graph of `fillReceivesValueOnlyInnerMockRequires/internal/plain`, the first of its block: the
	/// fill receives the caller's value, which in the called type's tree only a call of an inner public mock requires. The
	/// called type's public mock binds the value it is passed and its root level holds it (`mockRootBinding(ofChild:of:)`),
	/// so the calling mock fills the place as the twin does, where it reported that the values struct carries the value only
	/// optionally before.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsPlaceAsTwin_whenDrawnFillReceivesValueOnlyInnerPublicMockRequires() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 610)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 610)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillReceivesValueOnlyInnerMockRequires, caller: .internal, place: .plain))
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues == compileVerificationIsEnabled)
		Self.expectMirrorsTwin(result)
	}

	/// Seed 670 draws the first graph of `calledTypesReceivedValueInSendablePlace/internal/plain`, the first of its block: an
	/// internal calling mock whose call of a public mock fills a place the called type builds inside a `@Sendable` function,
	/// with a fill that reads a value the called type receives. The called mock binds at its root the value the calling mock
	/// passes it, its own, so the fill reads that value as the twin's does, where the calling mock reported the value as
	/// bound outside that function before (`SeamSignature.Hole.UncarriedDeclaration.isBoundFromCallersArgument`), which the
	/// check reports as a mock rejected where its twin is accepted.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_fillsTwinsValue_whenDrawnFillInSendablePlaceReadsValueCalledTypeReceives() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 670)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 670)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .calledTypesReceivedValueInSendablePlace, caller: .internal, place: .plain))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == [])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
		#expect(result.comparedValues == compileVerificationIsEnabled)
	}

	/// The control's graphs call a second public mock that holds the hole in another form (`callsMixedFormMock`) in the
	/// pinned number of its sixty graphs, at least ten of each place, so the cell test, which requires each control graph's
	/// mock to pass up exactly the twin's one builder, judges both forms of each.
	@Test
	func noVisibleImplementationDraw_callsMixedFormMock_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .noVisibleImplementation }
		let counts = [
			"graphs": draws.count,
			"plain": draws.count { $0.callsMixedFormMock && $0.cell.place == .plain },
			"deferred": draws.count { $0.callsMixedFormMock && $0.cell.place == .deferred },
		]
		let firstSeed = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).first { GraphFuzzerCallingMockDraw(seed: $0).callsMixedFormMock }
		print("calling-mock control mixed forms counts=\(counts.sorted { $0.key < $1.key }) firstSeed=\(firstSeed.map(String.init) ?? "none")")

		#expect(counts == ["graphs": 60, "plain": 12, "deferred": 15])
		#expect(firstSeed == 20)
	}

	/// The caller's own value's graphs hand the calling mock the optional builder of the hole type its call fills, an
	/// override of the called type, or both (`filledHoleBuilderPass`) in the pinned number of its sixty graphs, at least ten
	/// of each, so the probes judge each: the place holds what the builder builds, and the override is handed the builder.
	@Test
	func callersOwnValueDraw_drawsEachFilledHoleBuilderPass_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .callersOwnValue }
		var counts = ["graphs": draws.count]
		for pass in GraphFuzzerCallingMockDraw.FilledHoleBuilderPass.allCases {
			counts["\(pass)"] = draws.count { $0.filledHoleBuilderPass == pass }
		}
		let firstSeeds = GraphFuzzerCallingMockDraw.FilledHoleBuilderPass.allCases.map { pass in
			"\(pass) \(draws.first { $0.filledHoleBuilderPass == pass }.map { String($0.seed) } ?? "none")"
		}
		print("calling-mock filled hole builder pass counts=\(counts.sorted { $0.key < $1.key }) firstSeeds=\(firstSeeds)")

		#expect(counts == ["graphs": 60, "none": 19, "builder": 12, "override": 15, "builderAndOverride": 14])
		#expect(firstSeeds == ["none 16", "builder 17", "override 46", "builderAndOverride 19"])
	}

	/// The graphs of the fill that receives the caller's lazy value below the called type's root whose second place's fill
	/// calls the called type again, passing its hole type up whole, also call `Dock`, whose place of that hole type the mock
	/// fills, in the pinned number of graphs (`joinsFilledCall`), so the probes judge the join: the call reads the required
	/// builder. Of them, the pinned number build `Dock` inline (`buildsDockInline`), so the probe judges the inline-built
	/// place's read of the required builder, by value or in an `ErasedInstantiator`.
	@Test
	func fillReceivesCallersLazyValueBelowCalledRootDraw_joinsFilledCall_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillReceivesCallersLazyValueBelowCalledRoot }
		let counts = [
			"graphs": draws.count,
			"eligible": draws.count { $0.callerLazyValue.map { $0.secondPlaceCallsAgain && $0.reentersCalledType && $0.call != .fillCallsAgain } == true },
			"joins": draws.count(where: \.joinsFilledCall),
			"joinsPlain": draws.count { $0.joinsFilledCall && $0.cell.place == .plain },
			"joinsDeferred": draws.count { $0.joinsFilledCall && $0.cell.place == .deferred },
			"buildsDockInline": draws.count(where: \.buildsDockInline),
			"buildsDockInlinePlain": draws.count { $0.buildsDockInline && $0.cell.place == .plain },
		]
		let firstSeed = draws.first(where: \.joinsFilledCall)?.seed
		let firstInlineSeed = draws.first(where: \.buildsDockInline)?.seed
		let firstCalledSeed = draws.first { $0.joinsFilledCall && !$0.buildsDockInline }?.seed
		print("calling-mock joined call counts=\(counts.sorted { $0.key < $1.key }) firstSeed=\(firstSeed.map(String.init) ?? "none") firstInlineSeed=\(firstInlineSeed.map(String.init) ?? "none") firstCalledSeed=\(firstCalledSeed.map(String.init) ?? "none")")

		#expect(counts == ["graphs": 60, "eligible": 17, "joins": 11, "joinsPlain": 4, "joinsDeferred": 7, "buildsDockInline": 6, "buildsDockInlinePlain": 1])
		#expect(firstSeed == 737)
		#expect(firstInlineSeed == 737)
		#expect(firstCalledSeed == 751)
	}

	/// Seed 751 draws the first graph that joins a filled call (`joinsFilledCall`) and calls `Dock`'s mock: its mock passes
	/// the hole type of the called type up whole, and its call of `Dock`, which fills a place of that hole type, reads the
	/// required builder, so `Dock`'s place holds what that builder builds. It fails with the joined call reading the fill
	/// (`FillPlaceBindings.HoleBuilder.structValue`).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_handsRequiredBuilderToFilledCall_whenDrawnGraphJoinsFilledCall() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 751)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 751)

		#expect(draw.joinsFilledCall)
		#expect(!draw.buildsDockInline)
		#expect(Self.comparesValues(ofSeed: 751))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
		#expect(result.comparedValues == compileVerificationIsEnabled)
	}

	/// Seeds 737 and 766 draw the first graphs that build `Dock` inline (`buildsDockInline`), with a deferred place and a
	/// plain one, each the first of its cell to join a filled call, so compared: the calling mock builds `Dock` inline, and
	/// its place, a hole of `Dock`'s module, reads the required builder of its hole type, wrapped in the place's
	/// `ErasedInstantiator` or by value, so it holds what that builder builds. Seed 766 fails with the inline place reading
	/// no builder (`ScopeGenerator.holeBuildersByInlinePlace`), and seed 737 with the wrapper made without it
	/// (`generateInstantiatorBinding`).
	@Test(arguments: [UInt64(737), 766])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_handsRequiredBuilderToInlineBuiltPlace_whenDrawnGraphBuildsDockInline(seed: UInt64) async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: seed)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: seed)

		#expect(draw.buildsDockInline)
		#expect(Self.comparesValues(ofSeed: seed))
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == draw.expectedPassUpLabels)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
		#expect(result.comparedValues == compileVerificationIsEnabled)
	}

	/// Seeds 17, 46 and 19 are the caller's own value's first graphs whose probes hand the calling mock the optional builder
	/// of the filled hole type, an override of the called type, and both (`filledHoleBuilderPass`): the place holds what the
	/// builder builds, and the override, which calls the called mock with the builder it is handed, builds what the twin
	/// does. Seed 17 fails with the call's struct reading no builder (`FillPlaceBindings.HoleBuilder.structValue`), and
	/// seed 19, whose place is deferred, with the override handed the fill's builder (`wrapperBuilderValue`).
	@Test(arguments: [UInt64(17), 46, 19])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsWhatPassedBuilderBuilds_whenDrawnProbeHandsFilledHoleTypesBuilderOrOverride(seed: UInt64) async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: seed)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: seed)

		#expect(draw.cell.shape == .callersOwnValue)
		#expect(draw.filledHoleBuilderPass != GraphFuzzerCallingMockDraw.FilledHoleBuilderPass.none)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == [])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
		#expect(result.comparedValues == compileVerificationIsEnabled)
	}

	/// Seed 20 draws the first control graph that also calls `Echo`, a public mock holding the hole in another form: the
	/// calling mock takes one builder for both calls' places, as its twin does, where it took one per form before.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_takesTwinsOneBuilder_whenDrawnControlCallsMockHoldingHoleInAnotherForm() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 20)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 20)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .noVisibleImplementation, caller: .internal, place: .plain))
		#expect(draw.callsMixedFormMock)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == [draw.holeBuilderLabel])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
	}

	/// The seam caller's graphs share a builder between the caller's own places and the fill's, a fill that instantiates
	/// its places as plain values outside every `@Sendable` function, in the pinned number of its twenty graphs.
	@Test
	func seamCallerFillSharesBuilderDraw_sharesABuilder_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .seamCallerFillSharesBuilder }
		let sharing = draws.filter { draw in
			guard let fillHoles = draw.fillHoles else { return false }
			return draw.expectedBuilders.count < fillHoles.builders.count + fillHoles.protocols.count
		}
		print("calling-mock seam callers graphs=\(draws.count) sharing=\(sharing.count)")

		#expect(draws.count == 20)
		#expect(sharing.count == 10)
	}

	/// The graphs of the shape whose fill instantiates what nothing fulfills draw each of its variations (`FillHoles`) in
	/// the pinned number of graphs, each value in at least ten, so that the cell test, which requires every graph's mock to
	/// take its twin's builders, judges each.
	@Test
	func fillInstantiatesWhatNothingFulfillsDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let fillHoles = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillInstantiatesWhatNothingFulfills }.compactMap(\.fillHoles)
		let counts = [
			"graphs": fillHoles.count,
			"fulfillerIsSeam": fillHoles.count(where: \.fulfillerIsSeam),
			"calledTypeIsSeam": fillHoles.count(where: \.calledTypeIsSeam),
			"depthTwo": fillHoles.count { $0.depth == 2 },
			"insideSendableFunction": fillHoles.count(where: \.isInsideSendableFunction),
			"erasedInstantiator": fillHoles.count(where: \.isErasedInstantiator),
			"twoPlaces": fillHoles.count { $0.placeCount == 2 },
			"twoHoleTypes": fillHoles.count { $0.holeTypeCount == 2 },
		]
		print("calling-mock fill holes \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == ["graphs": 40, "fulfillerIsSeam": 20, "calledTypeIsSeam": 25, "depthTwo": 22, "insideSendableFunction": 11, "erasedInstantiator": 17, "twoPlaces": 17, "twoHoleTypes": 21])
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

	/// Each probed cell compares one graph of each leaf position it draws, a cell that draws a call (`CallerLazyValue.Call`)
	/// also compares one graph of each call it draws and of each variation drawn after it, among its graphs that state
	/// probes, and a cell that draws a builder of the enclosing called type one graph of each builder and, for each builder,
	/// one whose fill also instantiates what nothing fulfills: its compared graphs are the first of each position, the first
	/// of each call and the first of each such variation, or the first of each position, the first of each builder and the
	/// first such fill beside each builder; a cell of the shapes whose called type holds its place lazily or a place of a
	/// second hole type, or whose caller forwards the value its fill reads, also compares the first graph of each variation
	/// of its shape (`shapeVariation(of:)`) that it holds.
	/// The caller's own value's cells also compare the first graph of each pass (`filledHoleBuilderPass`), and a cell
	/// whose graphs join a filled call the first that does (`joinsFilledCall`).
	@Test
	func comparesValues_comparesFirstGraphOfEachLeafPosition_inEachProbedCell() {
		for cell in GraphFuzzerCallingMockCell.drawnCells {
			// A graph of the shape that draws a call whose mock passes its place up whole states no probes.
			let cellDraws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell == cell }
			// A graph that joins a filled call is compared on its own: the first of its cell.
			let joinedDraws = cellDraws.filter(\.joinsFilledCall)
			#expect(joinedDraws.filter { Self.comparesValues(ofSeed: $0.seed) }.map(\.seed) == joinedDraws.prefix(1).map(\.seed), "\(cell)")
			let draws = cellDraws.filter { !$0.joinsFilledCall && ($0.valueProbes != nil || $0.callerLazyValue == nil) }
			guard draws.first?.valueProbes != nil else { continue }
			let compared = draws.filter { Self.comparesValues(ofSeed: $0.seed) }
			let calls = draws.compactMap { $0.callerLazyValue?.call.rawValue }

			let builders = draws.compactMap { $0.enclosingBuilder?.rawValue }
			if !builders.isEmpty {
				var firstSeeds = Set<UInt64>()
				for position in Set(draws.map { "\($0.tickerPosition)" }) {
					if let first = draws.first(where: { position == "\($0.tickerPosition)" }) {
						firstSeeds.insert(first.seed)
					}
				}
				for builder in Set(builders) {
					if let first = draws.first(where: { $0.enclosingBuilder?.rawValue == builder }) {
						firstSeeds.insert(first.seed)
					}
				}
				var buildersOfReenteringFillsInstantiatingWhatNothingFulfills = Set<String>()
				for builder in Set(builders) {
					if let first = draws.first(where: { $0.enclosingBuilder?.rawValue == builder && $0.reenteringFillInstantiatesWhatNothingFulfills }) {
						firstSeeds.insert(first.seed)
						buildersOfReenteringFillsInstantiatingWhatNothingFulfills.insert(builder)
					}
				}
				let wrappers = Set(draws.compactMap(\.enclosingCalledTypeLazyValueWrapper))
				for wrapper in wrappers {
					if let first = draws.first(where: { $0.enclosingCalledTypeLazyValueWrapper == wrapper }) {
						firstSeeds.insert(first.seed)
					}
				}
				#expect(Set(compared.compactMap(\.enclosingCalledTypeLazyValueWrapper)) == wrappers, "\(cell)")
				#expect(Set(compared.compactMap { $0.enclosingBuilder?.rawValue }) == Set(builders), "\(cell)")
				#expect(Set(compared.filter(\.reenteringFillInstantiatesWhatNothingFulfills).compactMap { $0.enclosingBuilder?.rawValue }) == buildersOfReenteringFillsInstantiatingWhatNothingFulfills, "\(cell)")
				#expect(Set(compared.map(\.seed)) == firstSeeds, "\(cell)")
			} else if draws.contains(where: { Self.shapeVariation(of: $0) != nil }) {
				// The first graph of each variation, across the shape's cells, is compared beside the first of each position.
				var seenVariations = Set<String>()
				let firstSeedsOfVariations = Set((UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).filter { seed in
					Self.shapeVariation(of: GraphFuzzerCallingMockDraw(seed: seed)).map { seenVariations.insert($0).inserted } ?? false
				})
				var firstSeeds = Set<UInt64>()
				for position in Set(draws.map { "\($0.tickerPosition)" }) {
					if let first = draws.first(where: { position == "\($0.tickerPosition)" }) {
						firstSeeds.insert(first.seed)
					}
				}
				firstSeeds.formUnion(draws.map(\.seed).filter(firstSeedsOfVariations.contains))
				#expect(Set(compared.map { "\($0.tickerPosition)" }) == Set(draws.map { "\($0.tickerPosition)" }), "\(cell)")
				#expect(Set(compared.map(\.seed)) == firstSeeds, "\(cell)")
			} else if calls.isEmpty {
				// The first of each position, and, of the caller's own value's shape, the first of each pass
				// (`filledHoleBuilderPass`).
				var firstSeeds = Set<UInt64>()
				for position in Set(draws.map { "\($0.tickerPosition)" }) {
					if let first = draws.first(where: { position == "\($0.tickerPosition)" }) {
						firstSeeds.insert(first.seed)
					}
				}
				for pass in Set(draws.compactMap { $0.filledHoleBuilderPass.map { "\($0)" } }) {
					if let first = draws.first(where: { $0.filledHoleBuilderPass.map { "\($0)" } == pass }) {
						firstSeeds.insert(first.seed)
					}
				}
				#expect(Set(compared.map(\.seed)) == firstSeeds, "\(cell)")
			} else {
				var firstSeeds = Set<UInt64>()
				for position in Set(draws.map { "\($0.tickerPosition)" }) {
					if let first = draws.first(where: { position == "\($0.tickerPosition)" }) {
						firstSeeds.insert(first.seed)
					}
				}
				for call in Set(calls) {
					if let first = draws.first(where: { $0.callerLazyValue?.call.rawValue == call }) {
						firstSeeds.insert(first.seed)
					}
				}
				let variations = Set(draws.flatMap(Self.callerLazyValueVariationsDrawnAfterTheCall(of:)))
				for variation in variations {
					if let first = draws.first(where: { Self.callerLazyValueVariationsDrawnAfterTheCall(of: $0).contains(variation) }) {
						firstSeeds.insert(first.seed)
					}
				}
				#expect(Set(compared.map { "\($0.tickerPosition)" }) == Set(draws.map { "\($0.tickerPosition)" }), "\(cell)")
				#expect(Set(compared.compactMap { $0.callerLazyValue?.call.rawValue }) == Set(calls), "\(cell)")
				#expect(Set(compared.flatMap(Self.callerLazyValueVariationsDrawnAfterTheCall(of:))) == variations, "\(cell)")
				#expect(Set(compared.map(\.seed)) == firstSeeds, "\(cell)")
			}
		}
	}

	@Test
	func drawnCells_coverEveryCell_whenCorpusDrawsTenGraphsPerCell() {
		#expect(GraphFuzzerCallingMockCell.all.count == 127)
		#expect(GraphFuzzerCallingMockCell.drawnCells == GraphFuzzerCallingMockCell.all)
		#expect(Self.callingMockCorpusSeedCount == GraphFuzzerCallingMockCell.drawnCells.count * 10)
		#expect(GraphFuzzerCallingMockCell.firstSeeds.map(GraphFuzzerCallingMockCell.cell(ofSeed:)) == GraphFuzzerCallingMockCell.all)
	}

	/// The listed callers' block, added after the internal and `.public` callers', draws no earlier seed anew: seeds
	/// `0..<280` draw the cells they drew before it, `drawnCells[s % 28]`, and seeds `280..<420` the listed callers' cells,
	/// before the block of the fill that receives the value building the call.
	@Test
	func listedCallersBlock_leavesEarlierSeedsCells_whenAddedAfterThem() {
		let earlierCells = Array(GraphFuzzerCallingMockCell.all.prefix(28))

		#expect((UInt64(0)..<280).allSatisfy { GraphFuzzerCallingMockCell.cell(ofSeed: $0) == earlierCells[Int($0 % 28)] })
		#expect(Set(earlierCells.map(\.caller)) == [.internal, .public])
		#expect((UInt64(280)..<420).allSatisfy { GraphFuzzerCallingMockCell.cell(ofSeed: $0).caller == .listed })
		#expect(GraphFuzzerCallingMockCell.cell(ofSeed: 284).description == "seamBuiltAgain/listed/plain")
		#expect((UInt64(420)..<450).allSatisfy { GraphFuzzerCallingMockCell.cell(ofSeed: $0).shape == .fillReceivesValueBuildingTheCall })
	}

	/// The roll for a listed caller's cycle through a fill: the fill receives the `Relay` whose tree calls the seam, and the
	/// listed mock reports the twin's cycle, which it accepted, with code that did not compile, before listed callers' trees
	/// were walked for cycles over the trees built inline.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_reportsTwinsCycle_whenListedCallersFillReceivesValueBuildingTheCall() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 422)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 422)

		#expect(draw.cell.description == "fillReceivesValueBuildingTheCall/listed/plain")
		#expect(draw.mockConfiguration != nil)
		#expect(result.twinSites?.first?.declaration == "@Received let \(draw.names.sibling.prefix(1).lowercased())\(draw.names.sibling.dropFirst()): \(draw.names.sibling)")
		Self.expectMirrorsTwin(result)
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

	/// A fill that receives the `database` the outer seam `Feature` builds, which the twin reports.
	private static let fillReadingOuterSeamsValue = """
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
		// Against the same types built inline, in module `App`.
		valueProbes: [DifferentialValueProbe(name: "App.Host", expression: "App.Host.mock()", knownRightExpression: "App.Host()")],
	)

	private static func description(of graph: GraphFuzzerCallingMockGraph) -> String {
		graph.mockFiles.map { "// module \($0.module)\n\($0.content)" }.joined(separator: "\n\n")
	}

	// MARK: Known issues

	/// Ten graphs per drawn cell: seed `s` draws `GraphFuzzerCallingMockCell.cell(ofSeed: s)`.
	static let callingMockCorpusSeedCount = GraphFuzzerCallingMockCell.all.count * GraphFuzzerCallingMockCell.graphsPerCell

	/// Whether the cell test compiles seed `seed`'s graph and compares its values: the first graph of each cell with each
	/// leaf position the cell draws, since each comparison compiles every module of both forms, and the leaf moves the
	/// caller's other property and parameter; in the shape whose fill receives the caller's lazy value below the called
	/// type's root, the first graph of each cell with each call it draws (`CallerLazyValue.Call`), and the first that draws
	/// a second place whose fill calls the called type again, and a place built in a `@Sendable` function too, whose mocks
	/// only a compile judges; and, in the shape whose fill holds a builder of the enclosing called type, the first graph of
	/// each cell with each builder it draws (`GraphFuzzerCallingMockDraw.EnclosingBuilder`), the first with each builder
	/// whose fill also instantiates what nothing fulfills (`reenteringFillInstantiatesWhatNothingFulfills`), whose
	/// re-entered level function, and, beside a `SendableInstantiator`, the no-scope initializer of the fill's plain level,
	/// only a compile judges, and the first whose enclosing called type receives the caller's value in each wrapper
	/// (`enclosingCalledTypeLazyValueWrapper`), whose instance only the values show; and, in the shapes whose called type
	/// holds its place lazily or a place of a second hole type, and whose caller forwards the value its fill reads, the
	/// first graph with each of their variations (`comparedSeeds`). The other graphs of a probed cell
	/// differ from a compared one only in names and in variations the tool run alone judges, and pass on their tool runs
	/// alone, the seam built again's too.
	static func comparesValues(ofSeed seed: UInt64) -> Bool {
		comparedSeeds.contains(seed)
	}

	/// The first seed of each cell and leaf position, and of each cell and call of the shape that draws one, and of each
	/// cell and variation of that shape drawn after the call, in the corpus, among that shape's graphs that state probes;
	/// the first of each cell and builder of the shape whose fill holds a builder of the enclosing called type, the first
	/// of each cell and builder of that shape whose fill also instantiates what nothing fulfills, and the first of each cell
	/// of that shape whose enclosing called type receives the caller's value in each wrapper; and, keyed by shape rather
	/// than by cell, since the cell's leaf position already varies the caller, the first that draws each wrapper with and
	/// without a place by value beside it, of the shape whose called type holds its place lazily; each place, fill and
	/// position of the second hole type, of the shape whose called type holds one; each place and read, of the shape
	/// whose caller forwards the value its fill reads; with and without a type that fulfills the place, of the shape whose
	/// called type instantiates it only if available; and the first of each
	/// cell of the caller's own value's shape and what a probe hands its mock (`filledHoleBuilderPass`).
	static let comparedSeeds: Set<UInt64> = {
		var seenCellsAndPositions = Set<String>()
		var seenCellsAndCalls = Set<String>()
		var seeds = Set<UInt64>()
		for seed in UInt64(0)..<UInt64(callingMockCorpusSeedCount) {
			let draw = GraphFuzzerCallingMockDraw(seed: seed)
			// A graph whose call of `Dock` reads the required builder of a hole type passed up whole is compared on its own,
			// the first of each cell, so the graphs compared before it was drawn stay compared.
			if draw.joinsFilledCall {
				if seenCellsAndCalls.insert("\(draw.cell) joinsFilledCall").inserted {
					seeds.insert(seed)
				}
				continue
			}
			// A graph whose mock passes its place up whole states no probes (`CallerLazyValue.reentersCalledType`).
			guard draw.valueProbes != nil || draw.callerLazyValue == nil else { continue }
			if seenCellsAndPositions.insert("\(draw.cell) \(draw.tickerPosition)").inserted {
				seeds.insert(seed)
			}
			if let call = draw.callerLazyValue?.call, seenCellsAndCalls.insert("\(draw.cell) \(call)").inserted {
				seeds.insert(seed)
			}
			for variation in callerLazyValueVariationsDrawnAfterTheCall(of: draw) where seenCellsAndCalls.insert("\(draw.cell) \(variation)").inserted {
				seeds.insert(seed)
			}
			if let builder = draw.enclosingBuilder, seenCellsAndCalls.insert("\(draw.cell) \(builder)").inserted {
				seeds.insert(seed)
			}
			if draw.reenteringFillInstantiatesWhatNothingFulfills, let builder = draw.enclosingBuilder, seenCellsAndCalls.insert("\(draw.cell) \(builder) reenteringFillInstantiatesWhatNothingFulfills").inserted {
				seeds.insert(seed)
			}
			if let wrapper = draw.enclosingCalledTypeLazyValueWrapper, seenCellsAndCalls.insert("\(draw.cell) \(wrapper)").inserted {
				seeds.insert(seed)
			}
			if let pass = draw.filledHoleBuilderPass, seenCellsAndCalls.insert("\(draw.cell) \(pass)").inserted {
				seeds.insert(seed)
			}
			if let variation = shapeVariation(of: draw), seenCellsAndCalls.insert(variation).inserted {
				seeds.insert(seed)
			}
		}
		return seeds
	}()

	/// The variation `draw` draws of the shapes whose called type holds its place lazily, a place of a second hole type, or
	/// a place instantiated only if available, and whose caller forwards the value its fill reads, keyed by shape rather than by cell, since the cell's leaf
	/// position already varies the caller; `nil` for a draw of another shape.
	static func shapeVariation(of draw: GraphFuzzerCallingMockDraw) -> String? {
		if let lazyPlace = draw.lazyPlace {
			"\(draw.cell.shape) \(lazyPlace.wrapper) \(lazyPlace.besideByValuePlace)"
		} else if let secondHole = draw.secondHole {
			"\(draw.cell.shape) \(draw.cell.place) \(secondHole.fill) \(secondHole.isBeforeFirstPlace)"
		} else if let forwardedValue = draw.forwardedValue {
			"\(draw.cell.shape) \(draw.cell.place) \(forwardedValue.fillReceivesOnlyIfAvailable)"
		} else if let optionalPlace = draw.optionalPlace {
			"\(draw.cell.shape) \(optionalPlace.implementationIsVisible)"
		} else {
			nil
		}
	}

	/// The variations `draw` draws after the call, of the shape whose fill receives the caller's lazy value below the called
	/// type's root (`CallerLazyValue.secondPlaceCallsAgain`, `buildsPlaceInSendableFunctionToo`).
	static func callerLazyValueVariationsDrawnAfterTheCall(of draw: GraphFuzzerCallingMockDraw) -> [String] {
		var variations = [String]()
		if draw.callerLazyValue?.secondPlaceCallsAgain == true {
			variations.append("secondPlaceCallsAgain")
		}
		if draw.callerLazyValue?.buildsPlaceInSendableFunctionToo == true {
			variations.append("buildsPlaceInSendableFunctionToo")
		}
		if draw.callerLazyValue?.fillReadsInstanceCalledTypeDoesNotHold == true {
			variations.append("fillReadsInstanceCalledTypeDoesNotHold")
		}
		if draw.callerLazyValue?.secondPlaceFillDeclaresValueAgain == true {
			variations.append("secondPlaceFillDeclaresValueAgain")
		}
		return variations
	}

	/// One entry per cell that fails, with the cell's seeds: none fails.
	static let callingMockKnownIssues: [GraphFuzzerKnownIssue] = []
}
