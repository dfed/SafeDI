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

	/// The known-right half of every drawn probe, compiled and run alone against the first graph of each probed cell, so a
	/// probe that names no declaration of its known-right path fails here by name rather than as a harness error of the cell
	/// test: the twin's for the cells whose twin is accepted, and the same types built inline for the seam built again and
	/// the cells whose graphs compare values with inline (`comparesValuesWithInline`).
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func drawnValueProbes_describeKnownRight_inFirstGraphOfEachProbedCell() async throws {
		let seeds = GraphFuzzerCallingMockCell.firstSeeds.filter { GraphFuzzerCallingMockDraw(seed: $0).valueProbes != nil }
		#expect(seeds == [8, 9, 10, 11, 16, 17, 18, 19, 24, 25, 26, 27, 284, 285, 288, 289, 292, 293, 450, 451, 452, 453, 530, 531, 610, 611, 612, 613, 614, 615])
		for seed in seeds {
			var filesToDelete = [URL]()
			defer {
				for file in filesToDelete {
					try? FileManager.default.removeItem(at: file)
				}
			}
			let draw = GraphFuzzerCallingMockDraw(seed: seed)
			let graph = draw.graph
			let knownRightModules = draw.cell.shape.twinRejects || graph.comparesValuesWithInline ? graph.inlineModules : graph.modules(.twin)
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
		for seed in GraphFuzzerCallingMockCell.firstSeeds where GraphFuzzerCallingMockDraw(seed: seed).cell.shape.twinRejects && GraphFuzzerCallingMockDraw(seed: seed).cell.shape != .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive {
			let shape = GraphFuzzerCallingMockDraw(seed: seed).cell.shape
			await sitesByShape[shape, default: []].append(try GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockDraw(seed: seed).graph, seed: seed).twinSites)
		}

		#expect(sitesByShape.keys.sorted() == [.outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill])
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
			if draw.cell.shape.passesUpExactlyTheExpectedLabels {
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

	/// Seed 610 draws the first graph of `fillReceivesCallersLazyValueBelowCalledRoot/internal/plain`, the first of its
	/// block: an internal calling mock whose call's place is a level below the called type's root, filled by a type that
	/// receives the caller's lazily held value, which the called type's tree also receives by value. Its twin fills the
	/// place, handing the fill the caller's own wrapper, as the same types built inline do, so the mock must build their
	/// values. Its mock names a builder it does not take and does not compile, which `callingMockKnownIssues` lists until
	/// the fix, which removes the entry.
	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMock_buildsInlineValues_whenDrawnFillReceivesCallersLazyValueBelowCalledRoot() async throws {
		let draw = GraphFuzzerCallingMockDraw(seed: 610)

		let result = try await GraphFuzzerCallingMockCheck.run(draw.graph, seed: 610)

		#expect(draw.cell == GraphFuzzerCallingMockCell(shape: .fillReceivesCallersLazyValueBelowCalledRoot, caller: .internal, place: .plain))
		#expect(draw.graph.comparesValuesWithInline)
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.isEmpty)
		#expect(result.comparedValues)
		if let knownIssue = Self.callingMockKnownIssues.first(where: { $0.seeds.contains(610) }), let failure = result.failure, knownIssue.matches(failure) {
			withKnownIssue("\(knownIssue.reason)") {
				Issue.record("\(failure.kind.rawValue). \(failure.details)")
			}
		} else {
			#expect(result.failure == nil, "\(result.failure?.details ?? "")")
		}
	}

	/// The graphs of the shape whose fill receives the caller's lazy value below the called type's root draw each wrapper,
	/// each way the called type's tree receives the value, each caller kind and each place in the pinned number of graphs,
	/// each in at least ten, and the cell test compiles and compares the pinned number of them.
	@Test
	func fillReceivesCallersLazyValueBelowCalledRootDraw_drawsEachVariation_inPinnedNumberOfGraphs() {
		let draws = (UInt64(0)..<UInt64(Self.callingMockCorpusSeedCount)).map { GraphFuzzerCallingMockDraw(seed: $0) }.filter { $0.cell.shape == .fillReceivesCallersLazyValueBelowCalledRoot }
		var counts = [String: Int]()
		for draw in draws {
			let variation = "\(draw.callerLazyValue?.wrapper ?? "none") \(draw.callerLazyValue?.receivesOnlyIfAvailable == true ? "onlyIfAvailable" : "byValue")"
			counts[variation, default: 0] += 1
			counts[draw.callerLazyValue?.wrapper ?? "none", default: 0] += 1
			counts[draw.callerLazyValue?.receivesOnlyIfAvailable == true ? "onlyIfAvailable" : "byValue", default: 0] += 1
			counts[draw.cell.caller.rawValue, default: 0] += 1
			counts[draw.cell.place.rawValue, default: 0] += 1
			if Self.comparesValues(ofSeed: draw.seed) {
				counts["compared", default: 0] += 1
				counts["compared \(variation)", default: 0] += 1
			}
		}
		print("calling-mock caller lazy values \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")

		#expect(counts == [
			"LazilyInstantiated": 27,
			"LazilyInstantiated byValue": 14,
			"LazilyInstantiated onlyIfAvailable": 13,
			"SendableLazilyInstantiated": 33,
			"SendableLazilyInstantiated byValue": 15,
			"SendableLazilyInstantiated onlyIfAvailable": 18,
			"byValue": 29,
			"onlyIfAvailable": 31,
			"internal": 20,
			"public": 20,
			"listed": 20,
			"plain": 30,
			"deferred": 30,
			"compared": 18,
			"compared LazilyInstantiated byValue": 5,
			"compared LazilyInstantiated onlyIfAvailable": 4,
			"compared SendableLazilyInstantiated byValue": 5,
			"compared SendableLazilyInstantiated onlyIfAvailable": 4,
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
		#expect(GraphFuzzerCallingMockCell.all.count == 67)
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
	/// caller's other property and parameter. The other graphs of a probed cell, which differ only in names, pass on their
	/// tool runs alone, the seam built again's too.
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

	/// One entry per cell that fails, with the cell's seeds: only the cells of the fill that receives the caller's lazy value
	/// below the called type's root, whose compared seeds' mocks do not compile until the fix of the adopter's report M1,
	/// which removes these entries.
	static let callingMockKnownIssues: [GraphFuzzerKnownIssue] = [
		callerLazyValueBelowCalledRootIssue(caller: "an internal", place: "a plain", seeds: [610, 616, 634]),
		callerLazyValueBelowCalledRootIssue(caller: "an internal", place: "a deferred", seeds: [611, 617, 629]),
		callerLazyValueBelowCalledRootIssue(caller: "a public", place: "a plain", seeds: [612, 636, 660]),
		callerLazyValueBelowCalledRootIssue(caller: "a public", place: "a deferred", seeds: [613, 619, 631]),
		callerLazyValueBelowCalledRootIssue(caller: "a listed", place: "a plain", seeds: [614, 620, 650]),
		callerLazyValueBelowCalledRootIssue(caller: "a listed", place: "a deferred", seeds: [615, 621, 645]),
	]

	/// The entry of one cell of the fill that receives the caller's lazy value below the called type's root, the adopter's
	/// report M1, for `caller`'s mock and `place` place: the mock names a builder of the place it does not take, so it does
	/// not compile.
	private static func callerLazyValueBelowCalledRootIssue(caller: String, place: String, seeds: [UInt64]) -> GraphFuzzerKnownIssue {
		GraphFuzzerKnownIssue(
			reason: "M1: \(caller) calling mock whose call’s \(place) place below the called type’s root is filled by a type that receives the caller’s lazily held value names a builder of the place it does not take",
			signatures: [.callingMockDoesNotCompile],
			seeds: seeds,
		)
	}
}
