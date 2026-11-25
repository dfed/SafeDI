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

/// The graph fuzzer's `generateMockPublic` corpus (`GraphFuzzerPublicMockDraw`) and its oracles. See "Graph fuzzer" in
/// CLAUDE.md.
struct SafeDIToolGraphFuzzerPublicMockTests {
	// MARK: Smoke batch

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func publicMockSmokeSeeds_produceNoUnknownFailures_whenRunThroughToolAndCompiler() async throws {
		// Today's tool generates `.public` as `true`, so most of the corpus is a known issue: the smoke batch holds a seed
		// of each shape it shows, which must fail exactly as listed (`publicMockSmokeKnownIssues`), and graphs that must pass.
		let knownIssuesBySeed = Dictionary(uniqueKeysWithValues: SafeDIToolGraphFuzzerTests.publicMockSmokeKnownIssues.flatMap { knownIssue in knownIssue.seeds.map { ($0, knownIssue) } })
		for result in try await publicMockSmokeResults.value {
			for finding in GraphFuzzerFinding.findings(failure: result.failure, laterFailures: result.laterFailures, knownIssue: knownIssuesBySeed[result.fixture.seed], retentionIsJudged: result.isJudgedForRetention) {
				switch finding {
				case .passed, .knownIssue:
					break
				case let .staleKnownIssue(knownIssue):
					Issue.record("Seed \(result.fixture.seed) no longer fails: \(knownIssue.reason)")
				case let .staleRenamedGraphDifference(knownIssue, aspect):
					Issue.record("Seed \(result.fixture.seed) sits on \"\(knownIssue.reason)\", which lists \(aspect.rawValue), but its renamed graphs do not show it.")
				case let .staleBuilderSurfaceSignature(knownIssue, kind):
					Issue.record("Seed \(result.fixture.seed) sits on \"\(knownIssue.reason)\", which lists \(kind.rawValue), but the graph does not show it.")
				case let .staleLeakEntry(knownIssue):
					Issue.record("Seed \(result.fixture.seed) sits on \"\(knownIssue.reason)\", which lists a leak the graph no longer shows.")
				case let .failure(failure):
					Issue.record(failure.issueComment(fixture: result.fixture))
				}
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func publicMockSmokeSeeds_exercisePublicMockFeature_inGraphsTheToolAccepts() async throws {
		// The batch's accepted graphs that pass show every output feature with a pinned minimum, read from the generated
		// code the oracle compiled and compared by value, with both consumer modules between them; and it holds a graph
		// the tool rejects today.
		let results = try await publicMockSmokeResults.value
		let passingResults = results.filter { $0.isAccepted && $0.passesBesidesBuilderSurface }
		#expect(passingResults.allSatisfy(\.isComparedByValueOracle) || !compileVerificationIsEnabled)
		// A graph with a hole whose retention the retention oracle judged.
		#expect(results.contains(where: \.isJudgedForRetention) || !compileVerificationIsEnabled)
		// Every graph is split across modules, with every package name given, so the SwiftPM plugin flow agreed on each with
		// the module-info flow.
		#expect(passingResults.filter { !$0.isComparedAcrossIntegrations }.map(\.fixture.seed) == [])
		let outputFeatures = passingResults.reduce(into: Set<GraphFuzzerPublicMockOutputFeature>()) { features, result in
			if case let .accepted(generatedFiles, _) = result.outcome {
				features.formUnion(GraphFuzzerPublicMockDraw.outputFeatures(of: result.fixture, generatedFiles: generatedFiles))
			}
		}
		#expect(Set(SafeDIToolGraphFuzzerTests.publicMockCorpusOutputFeatureMinimumShares.keys).subtracting(outputFeatures).sorted() == [])
		// A graph whose generated code carries the comment naming a type no declaration SafeDI reads declares, which agreed
		// with its read twin under both flows.
		#expect(passingResults.contains { result in
			guard result.isComparedWithReadTwin, case let .accepted(generatedFiles, _) = result.outcome else { return false }
			return GraphFuzzerPublicMockDraw.outputFeatures(of: result.fixture, generatedFiles: generatedFiles).contains(.unreadTypeComment)
		})
		let drawFeatures = passingResults.reduce(into: Set<GraphFuzzerPublicMockDrawFeature>()) { $0.formUnion(GraphFuzzerPublicMockDraw.drawFeatures(of: $1.fixture)) }
		#expect(Set([GraphFuzzerPublicMockDrawFeature.bothConsumerModules, .otherPackageConsumerModuleOnly, .samePackageConsumerModuleOnly, .sendableWrapperAboveLeaf, .mockConditionDiffers, .seamDependency, .seamDependencyChain, .holeInsideLoop]).subtracting(drawFeatures).sorted() == [])
		#expect(results.contains { !$0.isAccepted }, "Rejected none of \(SafeDIToolGraphFuzzerTests.publicMockSmokeSeeds.count) graphs")
	}

	// MARK: Draw

	@Test
	func publicMockCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool() {
		// Each shape the draw draws lands in exactly the pinned number of the corpus's graphs, read from their source:
		// the draw is deterministic, so a change in a shape's share is a reviewed diff, and a draw that stops landing
		// fails here. Every shape has a pin.
		var counts = [GraphFuzzerPublicMockDrawFeature: Int]()
		for seed in 0..<UInt64(SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount) {
			for feature in GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])) {
				counts[feature, default: 0] += 1
			}
		}
		for feature in GraphFuzzerPublicMockDrawFeature.allCases {
			#expect(counts[feature, default: 0] == SafeDIToolGraphFuzzerTests.publicMockCorpusDrawFeatureCounts[feature], "\(feature.rawValue) drawn in \(counts[feature, default: 0]) graphs")
		}
	}

	@Test
	func publicMockCorpus_drawsTenGraphsOfEachSide_whenFillUnderHoleLoopReadsHoleContext() {
		// The loop around `T6`'s hole is drawn with a fill reading `holeContext` both where `HoleLoop` declares it again,
		// which the tool rejects, and where it does not, the accepted neighbour the value differential compares: at least
		// ten graphs of each.
		let fillUnderLoopReadsField: Set<GraphFuzzerPublicMockDrawFeature> = [.holeInsideLoop, .holeFillReceivesField, .consumerReachesHoleTypeWithFill]
		var staleReadCount = 0
		var neighbourCount = 0
		for seed in 0..<UInt64(SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount) {
			let features = GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
			guard features.isSuperset(of: fillUnderLoopReadsField) else { continue }
			if features.contains(.holeLoopDeclaresContextAgain) {
				staleReadCount += 1
			} else {
				neighbourCount += 1
			}
		}
		#expect(staleReadCount >= 10, "\(staleReadCount) graphs read `holeContext` the loop declares again")
		#expect(neighbourCount >= 10, "\(neighbourCount) graphs read `holeContext` the loop does not declare again")
	}

	@Test
	func publicMockCorpus_drawsTenGraphsOfEachForm_whenHoleReceiverReceivesHoleHost() {
		// The hole beneath `HoleHost` that `HoleReceiver` receives, which `T6`'s mock promotes to its root (the adopter's M2),
		// is drawn as itself, through an `Instantiator`, and through a `SendableInstantiator`: at least ten graphs of each.
		let forms: [GraphFuzzerPublicMockDrawFeature] = [.holeHostReceivedByValue, .holeHostReceivedThroughInstantiator, .holeHostReceivedThroughSendableInstantiator]
		var counts = [GraphFuzzerPublicMockDrawFeature: Int]()
		for seed in 0..<UInt64(SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount) {
			let features = GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
			for form in forms where features.contains(form) {
				counts[form, default: 0] += 1
			}
		}
		for form in forms {
			#expect(counts[form, default: 0] >= 10, "\(form.rawValue) drawn in \(counts[form, default: 0]) graphs")
		}
	}

	@Test
	func publicMockCorpus_drawsTenGraphsOfAdoptersShape_whenSelfBuildingPublicMockReceivesItsBuilder() {
		// The shape #702 fixed with its builder received through a `SendableInstantiator` by `SelfPart`, which holds the
		// place, as the adopter's screen receives its own builder (M2): at least ten graphs.
		let adoptersShape: Set<GraphFuzzerPublicMockDrawFeature> = [.selfBuildingPublicMockReceivesBuilder, .selfBuildingPublicMockThroughSendableInstantiator, .selfBuildingPublicMockPlaceBeneath]
		let count = (0..<UInt64(SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount)).filter { seed in
			GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])).isSuperset(of: adoptersShape)
		}.count
		#expect(count >= 10, "\(count) graphs receive `SelfNode`’s `SendableInstantiator` in `SelfPart`")
	}

	@Test
	func publicMockKnownIssues_listEachSeedOnceInIncreasingOrder_belowPublicMockCorpusSeedCount() {
		#expect(SafeDIToolGraphFuzzerTests.knownIssueListProblems(SafeDIToolGraphFuzzerTests.publicMockKnownIssues, corpusSeedCount: SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount) == [])
	}

	@Test
	func knownRightPublicMockFixture_spellsEveryDeclarationPublicAndEveryPublicMockTrue_forEachSmokeSeed() {
		// The known-right path is the drawn graph with nothing but its access levels and its `.public` mocks changed: no
		// `package` or unspelled declaration, and no `.public`, is left, and with those spellings undone the files agree.
		for seed in SafeDIToolGraphFuzzerTests.publicMockSmokeSeeds {
			let drawn = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]).swiftFileContent
			let knownRight = GraphFuzzerGenerator.knownRightPublicMockFixture(forSeed: seed).swiftFileContent
			#expect(drawn.count == knownRight.count)
			for (drawnFile, knownRightFile) in zip(drawn, knownRight) {
				#expect(!knownRightFile.contains("generateMock: .public"))
				#expect(!knownRightFile.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("package ") })
				#expect(Self.erasingAccess(of: drawnFile) == Self.erasingAccess(of: knownRightFile))
			}
		}
	}

	// MARK: Acceptance oracle

	@Test
	func isPublicMockOnlyRejection_tellsPublicMocksOwnErrorsFromOthers_whenDiagnosticsAreClassified() {
		let omittedRequired = "/F/Service.swift:1:15: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `user: User`."
		let omittedProvided = "/F/Screen.swift:3:2: error: `Screen` provides `filter: Filter`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it."
		let omittedNested = "/F/Screen.swift:3:2: error: `Screen` provides `filter: Filter`, but no mock SafeDI generated for `Board` takes it: `Board`’s mock tree calls the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, which does not take it."
		let conditionMismatch = "/F/Screen.swift:3:2: error: `Service.mock()` is generated under `#if DEBUG` in `Core`, but this module’s mocks are unconditional. Give both modules one `mockConditionalCompilation`."
		let inaccessible = "/F/Session.swift:4:12: error: `Session` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Session` `public` to fix."
		let narrowerEnclosingType = "/F/X.swift:2:33: error: `Internals.X` cannot have a public mock because `Internals` is `internal`. Make `Internals` `public`, or use `generateMock: .internal`."
		let notCallableFromRunNamingNoModule = "/F/Service.swift:4:1: error: `TokenCache` is `internal`, so the mock of `Screen`, which builds `Service`’s tree here, cannot construct it: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it. Make `TokenCache` `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages. To call `Service.mock()` instead, build these mocks in a Swift package target, or, in a SafeDITool run by hand, list the `.safedi` file of `Service`’s module, written with `--module-name` and `--module-info-output`, in the file you pass to `--dependent-module-info-file-path`."
		let notCallableFromNamedModule = "/F/Service.swift:4:1: error: `Service` has a public `mock()`, but it cannot be called from a module whose module info names no module, and `TokenCache` is `internal`. Generate the module info of the module that declares `Service` with `--module-name`."
		#expect(GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: omittedRequired))
		#expect(GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: narrowerEnclosingType))
		#expect(GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: notCallableFromRunNamingNoModule))
		#expect(GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: notCallableFromNamedModule))
		#expect(GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: "\(omittedRequired)\n\(omittedProvided)"))
		#expect(GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: omittedNested))
		#expect(GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: conditionMismatch))
		#expect(!GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: inaccessible))
		#expect(!GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: "\(omittedRequired)\n\(inaccessible)"))
		#expect(!GraphFuzzerOracle.isPublicMockOnlyRejection(diagnostics: ""))
	}

	@Test
	func publicMockAcceptanceFailure_reportsDisagreement_whenOnlyOnePathIsAccepted() {
		// The drawn path may reject a graph its known-right path accepts only with a public mock's own errors; it may
		// never accept a graph its known-right path rejects.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0, features: [.generateMockPublic])
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let inaccessible = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Session.swift:4:12: error: `Session` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates.")
		let omittedRequired = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Service.swift:1:15: error: SafeDI cannot generate the public mock of `Service`: its `public` tier cannot take `user: User`.")
		func runs(_ drawn: GraphFuzzerToolOutcome, _ knownRight: GraphFuzzerToolOutcome) -> GraphFuzzerToolRuns {
			GraphFuzzerToolRuns(fixture: fixture, firstOutcome: drawn, secondOutcome: drawn, knownRightOutcome: knownRight)
		}
		#expect(runs(inaccessible, accepted).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
		#expect(runs(omittedRequired, accepted).publicMockAcceptanceFailure == nil)
		#expect(runs(accepted, inaccessible).publicMockAcceptanceFailure?.kind == .knownRightRejectsGraphPublicMockAccepts)
		#expect(runs(inaccessible, inaccessible).publicMockAcceptanceFailure == nil)
		#expect(runs(accepted, accepted).publicMockAcceptanceFailure == nil)
	}

	@Test
	func publicMockAcceptanceFailure_allowsStaleValueError_onlyWhereGraphDrawsFillReadingValueLoopDeclaresAgain() {
		// Seed 50 draws a fill that reads `holeContext`, which the loop around `T6`'s hole declares again; seed 28 draws
		// the loop declaring it again with no fill that reads it; seed 0 draws no loop. Only the first may report the error,
		// and only about `holeContext` and its `HoleLoop`.
		let staleValue = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/HoleFill.swift:3:2: error: `S50_Hole` receives `holeContext: S50_HoleContext`, which `S50_HoleLoop` declares between where `S50_T6` instantiates `holeHostBuilder: Instantiator<S50_HoleHost>` and where `S50_HoleLoop` instantiates it again. Inline, the `S50_HoleHost` built again receives `S50_HoleLoop`’s `holeContext`, but SafeDI hands the builder for `S50_HoleHost`’s `holeBuilder: Instantiator<S50_Hole>` (`holeBuilder` of `s50_HoleBuilder`) the same values at every level of that cycle. Declare `@Received let holeContext: S50_HoleContext` on `S50_HoleHost`, so each `S50_HoleHost` receives the `holeContext` of its own level and hands it on, or declare an @Instantiable type that fulfills `S50_Hole` in module `FuzzFeature` or a module it lists among its SafeDI dependencies.")
		let inaccessible = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Session.swift:4:12: error: `Session` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates.")
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let staleValueOfOtherLabel = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/HoleFill.swift:3:2: error: `S50_Hole` receives `session: S50_Session`, which `S50_HoleLoop` declares between where `S50_T6` instantiates `holeHostBuilder: Instantiator<S50_HoleHost>` and where `S50_HoleLoop` instantiates it again. Inline, the `S50_HoleHost` built again receives `S50_HoleLoop`’s `session`, but SafeDI hands the builder for `S50_HoleHost`’s `holeBuilder: Instantiator<S50_Hole>` (`holeBuilder` of `s50_HoleBuilder`) the same values at every level of that cycle. Declare `@Received let session: S50_Session` on `S50_HoleHost`, so each `S50_HoleHost` receives the `session` of its own level and hands it on, or declare an @Instantiable type that fulfills `S50_Hole` in module `FuzzFeature` or a module it lists among its SafeDI dependencies.")
		func features(ofSeed seed: UInt64) -> Set<GraphFuzzerPublicMockDrawFeature> {
			GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		}
		let staleRead: Set<GraphFuzzerPublicMockDrawFeature> = [.holeLoopDeclaresContextAgain, .holeFillReceivesField, .consumerReachesHoleTypeWithFill]
		#expect(features(ofSeed: 50).isSuperset(of: staleRead))
		#expect(features(ofSeed: 28).contains(.holeLoopDeclaresContextAgain))
		#expect(!features(ofSeed: 28).isSuperset(of: staleRead))
		#expect(!features(ofSeed: 0).contains(.holeInsideLoop))
		func runs(seed: UInt64, _ drawn: GraphFuzzerToolOutcome) -> GraphFuzzerToolRuns {
			GraphFuzzerToolRuns(fixture: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]), firstOutcome: drawn, secondOutcome: drawn, knownRightOutcome: accepted)
		}
		#expect(runs(seed: 50, staleValue).publicMockAcceptanceFailure == nil)
		#expect(runs(seed: 50, staleValueOfOtherLabel).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
		#expect(runs(seed: 50, inaccessible).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
		#expect(runs(seed: 28, staleValue).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
		#expect(runs(seed: 0, staleValue).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
	}

	@Test
	func publicMockAcceptanceFailure_allowsSendableFunctionCarryError_onlyWhereFillOfCalledMockReadsContextBoundOutsideSendableFunction() {
		// Seed 157's fill, in a module that cannot build `T6` inline and so calls its public mock, reads `holeContext`, which
		// `T6` instantiates outside the `@Sendable` function that builds `holeHost: SendableLazilyInstantiated<HoleHost>`: the
		// error its production twin reports (contract rule 7). Seed 978's fill makes the same read beneath the same wrapper, in
		// a module that builds `T6` inline, which reads it as the known-right path does; seed 370's fill reads `holeExtra`
		// beneath the wrapper, seed 59 draws the wrapper with no fill, and seed 0 draws no wrapper. Only the first may report
		// the error, and only about `holeContext`, `T6` and that function.
		func error(seed: UInt64, label: String = "holeContext", declaringType: String = "T6", function: String = "holeHost: SendableLazilyInstantiated") -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/F/S\(seed)_HoleFill.swift:7:33: error: `S\(seed)_Hole` receives `\(label): S\(seed)_HoleContext`, which `S\(seed)_\(declaringType)` declares outside the `@Sendable` function that builds `\(function)<S\(seed)_HoleHost>`, and SafeDI hands the builder for `S\(seed)_HoleHost`’s `holeBuilder: Instantiator<S\(seed)_Hole>` (`holeBuilder` of `s\(seed)_HoleSendableBuilder`) only what that function binds. Instantiate `\(label)` outside `S\(seed)_\(declaringType)` and declare `@Received let \(label): S\(seed)_HoleContext` on `S\(seed)_\(declaringType)`, so the builder’s caller reads its own, or declare an @Instantiable type that fulfills `S\(seed)_Hole` in module `FuzzFeature` or a module it lists among its SafeDI dependencies.\n/F/S\(seed)_T6.swift:15:2: note: `S\(seed)_\(declaringType)` declares `\(label): S\(seed)_HoleContext` here.")
		}
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		func runs(seed: UInt64, _ drawn: GraphFuzzerToolOutcome) -> GraphFuzzerToolRuns {
			GraphFuzzerToolRuns(fixture: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]), firstOutcome: drawn, secondOutcome: drawn, knownRightOutcome: accepted)
		}
		func features(seed: UInt64) -> Set<GraphFuzzerPublicMockDrawFeature> {
			GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		}
		#expect(features(seed: 157).contains(.holeFillReadsContextBoundOutsideSendableFunction))
		#expect(features(seed: 978).isSuperset(of: [.holeBeneathSendableWrapper, .holeFillReceivesField, .consumerReachesHoleTypeWithFill]))
		#expect(features(seed: 370).isSuperset(of: [.holeBeneathSendableWrapper, .holeFillReceivesNonField, .consumerReachesHoleTypeWithFill]))
		#expect(features(seed: 59).contains(.holeBeneathSendableWrapper))
		#expect(!features(seed: 59).contains(.consumerReachesHoleTypeWithFill))
		#expect(!features(seed: 0).contains(.holeBeneathSendableWrapper))
		for seed: UInt64 in [978, 370, 59, 0] {
			#expect(!features(seed: seed).contains(.holeFillReadsContextBoundOutsideSendableFunction), "seed \(seed)")
		}
		#expect(runs(seed: 157, error(seed: 157)).publicMockAcceptanceFailure == nil)
		#expect(runs(seed: 157, error(seed: 157, label: "holeExtra")).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
		#expect(runs(seed: 157, error(seed: 157, declaringType: "HoleHost")).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
		#expect(runs(seed: 157, error(seed: 157, function: "holeHostBuilder: SendableInstantiator")).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts)
		for seed: UInt64 in [978, 370, 59, 0] {
			#expect(runs(seed: seed, error(seed: seed)).publicMockAcceptanceFailure?.kind == .publicMockRejectsGraphKnownRightAccepts, "seed \(seed)")
		}
	}

	// MARK: Ground-truth access oracle

	@Test
	func declarationsWiderThanNamedTypes_reportsEachDeclaration_whenPublicOrPackageDeclarationNamesNarrowerType() {
		// Every `public` or `package` declaration generated code holds – a tier spanning several lines, an override's
		// initializer and members – is no wider than each type it names, a nested type's qualified name and its
		// enclosing types included; an unspelled declaration, or one as wide as its types, is not reported.
		let generatedFile = """
		extension S1_Service {
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            session: S1_Session? = nil,
		            theme: S1_Theme? = nil
		        ) {
		            self.session = session
		        }

		        package let session: S1_Session?
		        public let shelf: S1_Space.S1_Shelf?
		        let policy: S1_Policy?
		    }

		    public enum __safeDI_S1_Service_mock_0123456789ABCDEF {}

		    @MainActor public static func mock(
		        theme: S1_Theme? = nil,
		        session: S1_Session? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> S1_Service {
		        S1_Service(theme: theme)
		    }

		    package static func mock(policy: S1_Policy? = nil) -> S1_Service {
		        S1_Service()
		    }
		}
		"""
		let findings = GraphFuzzerOracle.declarationsWiderThanNamedTypes(
			in: ["FuzzFeature/S1_Service+SafeDIMock.swift": generatedFile],
			typeAccess: ["S1_Session": .package, "S1_Space.S1_Shelf": .internal, "S1_Policy": .internal],
		)
		#expect(findings == [
			"FuzzFeature/S1_Service+SafeDIMock.swift: `public init( session: S1_Session? = nil, theme: S1_Theme? = nil )` is `public`, but `S1_Session` is `package`.",
			"FuzzFeature/S1_Service+SafeDIMock.swift: `public let shelf: S1_Space.S1_Shelf?` is `public`, but `S1_Space.S1_Shelf` is `internal`.",
			"FuzzFeature/S1_Service+SafeDIMock.swift: `@MainActor public static func mock( theme: S1_Theme? = nil, session: S1_Session? = nil, safeDIOverrides: SafeDIOverrides = .init() ) -> S1_Service` is `public`, but `S1_Session` is `package`.",
			"FuzzFeature/S1_Service+SafeDIMock.swift: `package static func mock(policy: S1_Policy? = nil) -> S1_Service` is `package`, but `S1_Policy` is `internal`.",
		])
	}

	@Test
	func declarationsWiderThanNamedTypes_ignoresDefaultValueOfPackageDeclaration_whenItNamesInternalType() {
		// Swift checks the names in a default argument's value only for a `public` declaration: a `package` initializer's
		// default may name an `internal` type's provider, as a module-level configuration's does once its member's type is
		// proven `package`, while its parameter types, and a `public` declaration's defaults, are still checked.
		let generatedFile = """
		nonisolated public struct __safeDI_FuzzFeature_S1_T4_MockConfiguration {
		    package init(
		        policy: S1_Policy? = S1_T4.__safeDI_mockDefault_policy(),
		        tag: S1_Tag? = nil
		    ) {
		        self.policy = policy
		    }

		    public init(capacity: Int = S1_T4.defaultCapacity()) {}
		}
		"""
		let findings = GraphFuzzerOracle.declarationsWiderThanNamedTypes(
			in: ["FuzzFeature/SafeDIMockConfiguration.swift": generatedFile],
			typeAccess: ["S1_Policy": .package, "S1_Tag": .internal, "S1_T4": .internal],
		)
		#expect(findings == [
			"FuzzFeature/SafeDIMockConfiguration.swift: `package init( policy: S1_Policy? = S1_T4.__safeDI_mockDefault_policy(), tag: S1_Tag? = nil )` is `package`, but `S1_Tag` is `internal`.",
			"FuzzFeature/SafeDIMockConfiguration.swift: `public init(capacity: Int = S1_T4.defaultCapacity())` is `public`, but `S1_T4` is `internal`.",
		])
	}

	@Test
	func publicMockAccessFailure_reportsDeclaration_whenAcceptedGraphGeneratesPublicFieldNamingPackageType() throws {
		// The oracle reads the access the draw gave each type: a generated public field naming one of the draw's package
		// types fails the graph.
		let seed = try #require((UInt64(0)..<1_000).first { GraphFuzzerGenerator.narrowerTypeAccess(forSeed: $0, features: [.generateMockPublic]).values.contains(.package) })
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let packageTypeName = try #require(GraphFuzzerGenerator.narrowerTypeAccess(forSeed: seed, features: [.generateMockPublic]).filter { $0.value == .package }.keys.sorted().first)
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S\(seed)_T0+SafeDIMock.swift": "extension S\(seed)_T0 {\n    public struct SafeDIOverrides {\n        public let field: \(packageTypeName)?\n    }\n}\n"], warnings: [])
		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: accepted, secondOutcome: accepted, knownRightOutcome: accepted)
		#expect(runs.publicMockAccessFailure?.kind == .publicMockDeclarationWiderThanNamedType)
		let internalField = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S\(seed)_T0+SafeDIMock.swift": "extension S\(seed)_T0 {\n    struct SafeDIOverrides {\n        let field: \(packageTypeName)?\n    }\n}\n"], warnings: [])
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: internalField, secondOutcome: internalField, knownRightOutcome: internalField).publicMockAccessFailure == nil)
	}

	@Test
	func publicMockRootLevelFailure_reportsConsumer_whenConsumerInFillsModuleTakesBuilderOfPlaceItsFillCanFillFromRootLevel() {
		// Seed 10's fill, in `FuzzOther`, reads only what `T6`'s mock binds before its tree: `T8.mock` taking a builder of `T6`'s
		// places fails the graph; a field of `SafeDIOverrides` that spells the builder's type inside its own does not.
		let seed: UInt64 = 10
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		#expect(GraphFuzzerPublicMockDraw.drawFeatures(of: fixture).contains(.holeFillReceivesRootLevelValue))
		let builderType = "@escaping (S\(seed)_T6.SafeDIMockScope_S\(seed)_Hole) -> S\(seed)_Hole"
		func runs(consumerMock: String) -> GraphFuzzerToolRuns {
			let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzOther/S\(seed)_T8+SafeDIMock.swift": consumerMock], warnings: [])
			return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: accepted, secondOutcome: accepted, knownRightOutcome: accepted)
		}
		let passingUp = runs(consumerMock: "extension S\(seed)_T8 {\n    static func mock(\n        s\(seed)_HoleBuilder: \(builderType)\n    ) -> S\(seed)_T8 {\n    }\n}\n")
		#expect(passingUp.publicMockRootLevelFailure?.kind == .publicMockPassesUpPlaceItsRootLevelFills)
		let overriding = runs(consumerMock: "extension S\(seed)_T8 {\n    struct SafeDIOverrides {\n        let t6: ((\(builderType)) -> S\(seed)_T6)?\n    }\n\n    static func mock(\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> S\(seed)_T8 {\n    }\n}\n")
		#expect(overriding.publicMockRootLevelFailure == nil)
	}

	/// The runs of `seed`'s public mock graph, accepted with `consumerMock` as `OverriddenScreen`'s generated mock in `FuzzApp`.
	private func overrideClosureRuns(seed: UInt64, consumerMock: String) -> GraphFuzzerToolRuns {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzApp/S\(seed)_OverriddenScreen+SafeDIMock.swift": consumerMock], warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: accepted, secondOutcome: accepted, knownRightOutcome: accepted)
	}

	/// `OverriddenScreen`'s generated mock, whose overrides hold `members`.
	private func overriddenScreenMock(seed: UInt64, members: [String]) -> String {
		"extension S\(seed)_OverriddenScreen {\n    public struct SafeDIOverrides {\n        public init() {}\n\(members.map { "        \($0)\n" }.joined())    }\n}\n"
	}

	@Test
	func publicMockOverrideClosureFailure_reportsOfferedClosure_whenCallCannotHandBuilderPersonWrites() throws {
		// A graph whose call of `OverriddenDetail` cannot hand its override closure a builder a person writes fails when the
		// consumer's overrides hold the closure, and passes when they do not; a graph that does not draw the call passes either
		// way.
		let seed = try #require((UInt64(0)..<1_000).first { !GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateMockPublic])).isDisjoint(with: GraphFuzzerPublicMockDrawFeature.overrideClosureCannotHandShapes) })
		let member = "public let overriddenDetailBuilder: ((S\(seed)_OverriddenSession, @escaping () -> any S\(seed)_OverriddenPlace1Api) -> S\(seed)_OverriddenDetail)?"
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: [member])).publicMockOverrideClosureFailure?.kind == .publicMockOffersOverrideClosureItsCallCannotHand)
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: [])).publicMockOverrideClosureFailure == nil)
		let otherSeed = try #require((UInt64(0)..<1_000).first { !GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateMockPublic])).contains(.overrideClosureCall) })
		#expect(overrideClosureRuns(seed: otherSeed, consumerMock: overriddenScreenMock(seed: otherSeed, members: [member])).publicMockOverrideClosureFailure == nil)
	}

	@Test
	func publicMockOverrideClosureFailure_reportsDroppedClosure_whenCallCanHandBuilderPersonWrites() throws {
		// A graph whose call of `OverriddenDetail` can hand its override closure a builder a person writes for each place fails
		// when the consumer's overrides hold no closure, and passes when they hold one, by value or through an instantiator.
		let seed = try #require((UInt64(0)..<1_000).first { GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateMockPublic])).contains(.overrideClosureCallCanHand) })
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: [])).publicMockOverrideClosureFailure?.kind == .publicMockDropsOverrideClosureItsCallCanHand)
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: ["public let overriddenDetail: ((@escaping () -> any S\(seed)_OverriddenPlace1Api) -> S\(seed)_OverriddenDetail)?"])).publicMockOverrideClosureFailure == nil)
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: ["let overriddenDetailBuilder: ((@escaping () -> any S\(seed)_OverriddenPlace1Api) -> S\(seed)_OverriddenDetail)?"])).publicMockOverrideClosureFailure == nil)
	}

	@Test
	func publicMockOverrideClosureFailure_reportsDroppedClosure_whenFillReadsSessionConsumerBuilds() {
		// Seed 55's `OverriddenLive` reads `overriddenSession`, which `OverriddenDetail` does not receive: its `.public` consumer
		// fills the place with the session it builds, as its production twin does (contract rule 7), so its overrides keep the
		// closure, handed a function over that fill.
		let seed: UInt64 = 55
		let features = GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		#expect(features.isSuperset(of: [.overrideClosureCallFillReadsConsumersValue, .overrideClosureCallCanHand]))
		#expect(!features.contains(.overrideClosureCallPublicCallerPassesPlaceUp))
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: [])).publicMockOverrideClosureFailure?.kind == .publicMockDropsOverrideClosureItsCallCanHand)
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: ["public let overriddenDetailBuilder: ((@escaping () -> any S\(seed)_OverriddenPlace1Api) -> S\(seed)_OverriddenDetail)?"])).publicMockOverrideClosureFailure == nil)
	}

	@Test
	func publicMockOverrideClosureFailure_reportsOfferedClosure_whenFillReadsOtherPlaceBesideSessionConsumerBuilds() {
		// Seed 170's `OverriddenLive` reads `overriddenSession`, which `OverriddenDetail` does not receive, and the call's other
		// place: its internal consumer fills the place, so the fill reads a value the called mock binds itself, and its
		// overrides hold no closure.
		let seed: UInt64 = 170
		let features = GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		#expect(features.isSuperset(of: [.overrideClosureCallFillReadsConsumersValue, .overrideClosureCallFillReadsCalledMocksOtherPlace]))
		#expect(!features.contains(.overrideClosureCallCanHand))
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: [])).publicMockOverrideClosureFailure == nil)
		#expect(overrideClosureRuns(seed: seed, consumerMock: overriddenScreenMock(seed: seed, members: ["let overriddenDetail: ((@escaping () -> any S\(seed)_OverriddenPlace1Api, @escaping () -> any S\(seed)_OverriddenPlace1Store) -> S\(seed)_OverriddenDetail)?"])).publicMockOverrideClosureFailure?.kind == .publicMockOffersOverrideClosureItsCallCannotHand)
	}

	/// The runs of `seed`'s public mock graph, accepted with `generatedFile` as the declaring module's generated file.
	private func carrierOrderRuns(seed: UInt64, generatedFile: String) -> GraphFuzzerToolRuns {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: ["FuzzFeature/S\(seed)_CarrierHome+SafeDIMock.swift": generatedFile], warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: accepted, secondOutcome: accepted, knownRightOutcome: accepted)
	}

	/// The first public mock corpus seed that draws `drawCarrierBeforeSiblingPublicMock`'s holder before a sibling, beneath
	/// `CarrierShelf` or not, with the labels its declaring type declares.
	private func carrierBeforeSiblingSeed(beneathConfiguredChild: Bool) throws -> (seed: UInt64, labels: [String]) {
		let seed = try #require((UInt64(0)..<1_000).first { seed in
			let features = GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
			return features.contains(.carrierBeforeSibling) && features.contains(.carrierBeforeSiblingBeneathConfiguredChild) == beneathConfiguredChild
		})
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let labels = try #require(GraphFuzzerPublicMockDraw.carrierBeforeSiblingDeclaredLabels(in: GraphFuzzerPublicMockDraw.DeclaredTypes(of: fixture), prefix: fixture.typeNamePrefix))
		return (seed, labels)
	}

	/// `CarrierHome`'s generated mock, whose overrides' initializer takes `labels` in order, after a scope struct's initializer.
	private func carrierHomeMock(seed: UInt64, labels: [String]) -> String {
		"extension S\(seed)_CarrierHome {\n    nonisolated public struct carrierStore_Values {\n        public init(\n            carrierStore: S\(seed)_CarrierStore\n        ) {}\n    }\n\n    nonisolated public struct SafeDIOverrides {\n        public init(\n\(labels.map { "            \($0): (() -> Int)? = nil,\n" }.joined())        ) {}\n    }\n}\n"
	}

	@Test
	func publicMockOverridesOrderFailure_reportsBuildOrder_whenHolderOfPlaceIsDeclaredBeforeSibling() throws {
		// A graph that declares the holder of a place before a sibling fails when `CarrierHome`'s overrides take the holder after
		// its siblings, as the mock builds them, and passes when they take the three in declaration order; a graph that does not
		// draw the holder passes either way.
		let (seed, labels) = try carrierBeforeSiblingSeed(beneathConfiguredChild: false)
		let holderLabel = try #require(labels.first { $0 != "carrierStore" && $0 != "carrierCart" })
		let buildOrder = labels.filter { $0 != holderLabel } + [holderLabel]
		#expect(carrierOrderRuns(seed: seed, generatedFile: carrierHomeMock(seed: seed, labels: buildOrder)).publicMockOverridesOrderFailure?.kind == .publicMockOverridesFollowBuildOrder)
		#expect(carrierOrderRuns(seed: seed, generatedFile: carrierHomeMock(seed: seed, labels: labels)).publicMockOverridesOrderFailure == nil)
		let otherSeed = try #require((UInt64(0)..<1_000).first { !GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateMockPublic])).contains(.carrierBeforeSibling) })
		#expect(carrierOrderRuns(seed: otherSeed, generatedFile: carrierHomeMock(seed: otherSeed, labels: buildOrder)).publicMockOverridesOrderFailure == nil)
	}

	@Test
	func publicMockOverridesOrderFailure_reportsBuildOrder_whenConfiguredChildDeclaresHolderOfPlaceBeforeSibling() throws {
		// Where `CarrierShelf` declares the three, its module-level configuration takes them in declaration order, beside the
		// unlabeled builder; `CarrierHome`'s overrides, which take the configuration, are not read.
		let (seed, labels) = try carrierBeforeSiblingSeed(beneathConfiguredChild: true)
		let holderLabel = try #require(labels.first { $0 != "carrierStore" && $0 != "carrierCart" })
		/// The configuration, whose initializer takes `labels` in order.
		func configuration(labels: [String]) -> String {
			"nonisolated public struct __safeDI_FuzzFeature_S\(seed)_CarrierShelf_MockConfiguration {\n    public init(\n\(labels.map { "        \($0): (() -> Int)? = nil,\n" }.joined())        _ safeDIBuilder: (() -> S\(seed)_CarrierShelf)? = nil\n    ) {}\n}\n"
		}
		let homeMock = carrierHomeMock(seed: seed, labels: ["carrierShelf"])
		#expect(carrierOrderRuns(seed: seed, generatedFile: homeMock + configuration(labels: labels.filter { $0 != holderLabel } + [holderLabel])).publicMockOverridesOrderFailure?.kind == .publicMockOverridesFollowBuildOrder)
		#expect(carrierOrderRuns(seed: seed, generatedFile: homeMock + configuration(labels: labels)).publicMockOverridesOrderFailure == nil)
		#expect(carrierOrderRuns(seed: seed, generatedFile: homeMock).publicMockOverridesOrderFailure?.kind == .publicMockOverridesFollowBuildOrder)
	}

	/// The first public mock corpus seed whose call of `OverriddenDetail` can hand its override closure a builder a person
	/// writes, with the place held as an erased instantiator.
	private func overrideClosureCanHandErasedInstantiatorSeed() throws -> UInt64 {
		try #require((UInt64(0)..<1_000).first { GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateMockPublic])).isSuperset(of: [.overrideClosureCallCanHand, .overrideClosureCallPlaceIsErasedInstantiator]) })
	}

	/// `OverriddenDetail`'s generated file, whose `public` `mock()` takes the session, the erased instantiator's builder, and a
	/// defaulted value, in that order, and whose `package` one takes the builder alone.
	private func overriddenDetailMock(seed: UInt64) -> String {
		"extension S\(seed)_OverriddenDetail {\n    public static func mock(\n        overriddenSession: S\(seed)_OverriddenSession,\n        s\(seed)_OverriddenPlace1Live_S\(seed)_OverriddenPlace1ApiBuilder: @escaping ErasedInstantiator<(), any S\(seed)_OverriddenPlace1Api>.Builder,\n        overriddenFlag: Bool = false\n    ) -> S\(seed)_OverriddenDetail {\n    }\n\n    package static func mock(\n        s\(seed)_OverriddenPlace1Live_S\(seed)_OverriddenPlace1ApiBuilder: @escaping ErasedInstantiator<(), any S\(seed)_OverriddenPlace1Api>.Builder\n    ) -> S\(seed)_OverriddenDetail {\n    }\n}\n"
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingOverrideClosureCallers_passesEachHandedValueOnUnderTheLabelOfItsType_whenCallCanHandBuilders() throws {
		// The consumer's overrides hand the closure the builder before the session; the public `mock()` takes them the other
		// way around, beside a defaulted value, so the closure passes each on by its type, in the mock's order.
		let seed = try overrideClosureCanHandErasedInstantiatorSeed()
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let generatedFiles = [
			"FuzzApp/S\(seed)_OverriddenScreen+SafeDIMock.swift": overriddenScreenMock(seed: seed, members: ["public let overriddenDetail: ((ErasedInstantiator<(), any S\(seed)_OverriddenPlace1Api>.Builder, S\(seed)_OverriddenSession) -> S\(seed)_OverriddenDetail)?"]),
			"FuzzFeature/S\(seed)_OverriddenDetail+SafeDIMock.swift": overriddenDetailMock(seed: seed),
		]
		#expect(GraphFuzzerOracle.addingOverrideClosureCallers(to: generatedFiles, of: fixture) == generatedFiles.merging([
			"FuzzApp/S\(seed)_OverriddenScreen+SafeDIPublicMockCaller.swift": "import FuzzFeature\n\n#if DEBUG\nenum S\(seed)_OverriddenScreenOverrideClosureCaller {\n\tstatic func overrides() -> S\(seed)_OverriddenScreen.SafeDIOverrides {\n\t\t.init(overriddenDetail: { overriddenArgument0, overriddenArgument1 in S\(seed)_OverriddenDetail.mock(overriddenSession: overriddenArgument1, s\(seed)_OverriddenPlace1Live_S\(seed)_OverriddenPlace1ApiBuilder: overriddenArgument0) })\n\t}\n}\n#endif\n",
		]) { $1 })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingOverrideClosureCallers_addsNoCaller_whenOverridesHoldNoClosure() throws {
		let seed = try overrideClosureCanHandErasedInstantiatorSeed()
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let generatedFiles = [
			"FuzzApp/S\(seed)_OverriddenScreen+SafeDIMock.swift": overriddenScreenMock(seed: seed, members: []),
			"FuzzFeature/S\(seed)_OverriddenDetail+SafeDIMock.swift": overriddenDetailMock(seed: seed),
		]
		#expect(GraphFuzzerOracle.addingOverrideClosureCallers(to: generatedFiles, of: fixture) == generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingOverrideClosureCallers_addsNoCaller_whenFixtureIsKnownRight() throws {
		// The known-right path spells every mock `true`, so it gets no caller.
		let seed = try overrideClosureCanHandErasedInstantiatorSeed()
		let generatedFiles = [
			"FuzzApp/S\(seed)_OverriddenScreen+SafeDIMock.swift": overriddenScreenMock(seed: seed, members: ["let overriddenDetail: ((@escaping ErasedInstantiator<(), any S\(seed)_OverriddenPlace1Api>.Builder) -> S\(seed)_OverriddenDetail)?"]),
			"FuzzFeature/S\(seed)_OverriddenDetail+SafeDIMock.swift": overriddenDetailMock(seed: seed),
		]
		#expect(GraphFuzzerOracle.addingOverrideClosureCallers(to: generatedFiles, of: GraphFuzzerGenerator.knownRightPublicMockFixture(forSeed: seed)) == generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingOverrideClosureCallers_addsCallerUnderRenamedNames_whenGraphMovesTypeNamesAcrossWrapperNames() throws {
		// A renamed graph's names are read from its generated code, so its caller is the drawn graph's, renamed: restoring the
		// renaming gives the drawn graph's file.
		let seed = try overrideClosureCanHandErasedInstantiatorSeed()
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let renaming = try #require(GraphFuzzerRenaming.all.first { $0.movesTypeNamesAcrossWrapperNames })
		let prefix = fixture.typeNamePrefix
		let renamedFixture = fixture.renamed(by: renaming)
		let generatedFiles = [
			"FuzzApp/S\(seed)_OverriddenScreen+SafeDIMock.swift": overriddenScreenMock(seed: seed, members: ["let overriddenDetail: ((@escaping ErasedInstantiator<(), any S\(seed)_OverriddenPlace1Api>.Builder) -> S\(seed)_OverriddenDetail)?"]),
			"FuzzFeature/S\(seed)_OverriddenDetail+SafeDIMock.swift": overriddenDetailMock(seed: seed).replacingOccurrences(of: "overriddenSession: S\(seed)_OverriddenSession,\n        ", with: ""),
		]
		let renamedFiles = Dictionary(uniqueKeysWithValues: generatedFiles.map { (renaming.rename($0.key, typeNamePrefix: prefix), renaming.rename($0.value, typeNamePrefix: prefix)) })
		let callerFileName = "FuzzApp/S\(seed)_OverriddenScreen+SafeDIPublicMockCaller.swift"
		let caller = try #require(GraphFuzzerOracle.addingOverrideClosureCallers(to: generatedFiles, of: fixture)[callerFileName])
		let renamedCaller = try #require(GraphFuzzerOracle.addingOverrideClosureCallers(to: renamedFiles, of: renamedFixture)[renaming.rename(callerFileName, typeNamePrefix: prefix)])
		#expect(renaming.restore(renamedCaller, typeNamePrefix: prefix) == caller)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingOverrideClosureCallers_recordsIssue_whenNoMockTakesWhatTheClosureIsHanded() throws {
		let seed = try overrideClosureCanHandErasedInstantiatorSeed()
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic])
		let generatedFiles = [
			"FuzzApp/S\(seed)_OverriddenScreen+SafeDIMock.swift": overriddenScreenMock(seed: seed, members: ["let overriddenDetail: ((@escaping () -> any S\(seed)_OverriddenPlace1Api) -> S\(seed)_OverriddenDetail)?"]),
			"FuzzFeature/S\(seed)_OverriddenDetail+SafeDIMock.swift": overriddenDetailMock(seed: seed),
		]
		withKnownIssue {
			_ = GraphFuzzerOracle.addingOverrideClosureCallers(to: generatedFiles, of: fixture)
		}
	}

	// MARK: Builder structs

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_passesClosureThatTakesNothing_whenGeneratedMockTakesBuilderAsClosureThatTakesNothing() {
		// The draw writes `{ _ in … }`; `mock()` takes `S1_HoleBuilder` as `() -> S1_Hole`, so the caller passes `{ … }`.
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })"
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		let switched = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        s1_HoleBuilder: @escaping () -> S1_Hole\n    ) -> S1_T6 {\n    }\n}\n"]
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: switched, of: drawn)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\t\tS1_T6.mock(s1_HoleBuilder: { S1_Hole() })\n") == true)
		let kept = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        s1_HoleBuilder: @escaping (S1_T6.SafeDIMockScope_S1_Hole) -> S1_Hole\n    ) -> S1_T6 {\n    }\n}\n"]
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: kept, of: drawn)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\t\t\(call)\n") == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_convertsEachBuilderByItsLabel_whenCallPassesTwoBuildersToMockThatTakesClosuresThatTakeNothing() {
		// Each builder the mock takes as a closure that takes nothing is converted where the call passes it, however many
		// the mock takes, so a mock that takes one per filling type is called as one that takes one per hole type is.
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() }, s1_OtherBuilder: { _ in S1_Other() })"
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: Self.mockTakingTwoBuilders, of: drawn)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\t\tS1_T6.mock(s1_HoleBuilder: { S1_Hole() }, s1_OtherBuilder: { S1_Other() })\n") == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_convertsTheBuilderTheCallPasses_whenPublicMockTakesAnotherBuilderTheCallDoesNotPass() {
		// A builder surface edit gives the mock a builder after the draw wrote the call, which the same-supply judgment
		// judges instead; the builder the call passes is converted as ever.
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })"
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: Self.mockTakingTwoBuilders, of: drawn)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\t\tS1_T6.mock(s1_HoleBuilder: { S1_Hole() })\n") == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_convertsEachBuilderByItsForm_whenCallPassesNoneOfTheMocksLabels() {
		// A graph renamed to change an order renames the mock's labels, spelled from type names, but not the drawn call. A
		// label one of the mock's labels ends is not one of them: the conversion reads whole labels.
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })"
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		let renamedMock = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        HoleBuilder: @escaping () -> S1_Hole\n    ) -> S1_T6 {\n    }\n}\n"]
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: renamedMock, of: drawn)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\t\tS1_T6.mock(s1_HoleBuilder: { S1_Hole() })\n") == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_callsFromMainActor_whenMockedTypeSpellsMainActorMockAttributes() {
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })"
		let switched = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    @MainActor public static func mock(\n        s1_HoleBuilder: @escaping () -> S1_Hole\n    ) -> S1_T6 {\n    }\n}\n"]
		let isolated = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(mockAttributes: \"@MainActor\", generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: switched, of: isolated)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\t@MainActor public static func call() -> S1_T6 {\n") == true)
		// A mocked type without the attribute, or with it on another type of the file, is called from a nonisolated function.
		let plain = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(mockAttributes: \"@MainActor\", generateMock: .public)\npublic final class S1_T6Twin: Instantiable {}\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: switched, of: plain)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\tpublic static func call() -> S1_T6 {\n") == true)
	}

	/// `S1_T6`'s generated file, whose `public` `mock()` takes two closures that take nothing.
	private static let mockTakingTwoBuilders = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        s1_HoleBuilder: @escaping () -> S1_Hole,\n        s1_OtherBuilder: @escaping () -> S1_Other\n    ) -> S1_T6 {\n    }\n}\n"]

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_recordsIssue_whenCallPassesNoBuilderInTheFormItConverts() {
		let call = "S1_T6.mock(s1_HoleBuilder: { scope in S1_Hole() })"
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		let switched = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        s1_HoleBuilder: @escaping () -> S1_Hole\n    ) -> S1_T6 {\n    }\n}\n"]
		withKnownIssue {
			_ = GraphFuzzerOracle.addingPublicMockCallers(to: switched, of: drawn)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func handWrittenBuilderFindings_reportsOnlyCallsPassingClosureOverEnum_whenCallerFilesHoldHandWrittenCalls() {
		let switched = Self.callerFile(calling: "S1_T6.mock(s1_HoleBuilder: { S1_Hole() })").merging(Self.mockTaking(["s1_HoleBuilder: @escaping () -> S1_Hole"])) { $1 }
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: switched).isEmpty)
		let kept = Self.callerFile(calling: "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })").merging(Self.mockTaking(["s1_HoleBuilder: @escaping (S1_T6.SafeDIMockScope_S1_Hole) -> S1_Hole"])) { $1 }
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: kept) == [
			GraphFuzzerBuilderSurface.Finding(declaration: "the hand-written call `S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })`", parameter: "s1_HoleBuilder: { _ in", reason: "takes a scope its place does not forward"),
		])
	}

	@Test(arguments: [
		"@escaping Instantiator<S1_Hole>.Builder",
		"@escaping SendableInstantiator<S1_Hole>.Builder",
		"@escaping ErasedInstantiator<Int, S1_AnyHole>.Builder",
		"@escaping SendableErasedInstantiator<Int, S1_AnyHole>.Builder",
		"@escaping ErasedInstantiator<(id: Int, name: String), S1_AnyHole>.Builder",
		"@escaping ErasedInstantiator<Swift.Int, Dictionary<String, Int>>.Builder",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func handWrittenBuilderFindings_reportsNothing_whenMockTakesWrapperBuilderOfPlaceThatForwardsValue(builderType: String) {
		// The builder takes what the place forwards – an `Instantiator<T>`'s `T.ForwardedProperties`, which the module cannot
		// see is `()` for a type that conforms to `Instantiable` by hand, or an erased instantiator's named value – so the
		// call's `{ _ in … }` takes no scope.
		let files = Self.callerFile(calling: "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })").merging(Self.mockTaking(["s1_HoleBuilder: \(builderType)"])) { $1 }
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: files) == [])
	}

	@Test(arguments: [
		"@escaping ErasedInstantiator<(), S1_AnyHole>.Builder",
		"@escaping SendableErasedInstantiator<Void, S1_AnyHole>.Builder",
		"@escaping () -> S1_Hole",
		"@escaping @Sendable () -> S1_Hole",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func handWrittenBuilderFindings_reportsClosureThatTakesAValue_whenMockTakesBuilderOfPlaceThatForwardsNothing(builderType: String) {
		// A place that forwards nothing takes `() -> T`; a builder that takes `()` is the form the fold removed.
		let files = Self.callerFile(calling: "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })").merging(Self.mockTaking(["s1_HoleBuilder: \(builderType)"])) { $1 }
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: files) == [
			GraphFuzzerBuilderSurface.Finding(declaration: "the hand-written call `S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })`", parameter: "s1_HoleBuilder: { _ in", reason: "takes a scope its place does not forward"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func handWrittenBuilderFindings_reportsEachBuilderThatTakesAScope_whenCallPassesBuilderOfForwardingPlaceFirst() {
		// Every builder of the call is judged by its own label, not only the first the call passes.
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() }, s1_OtherBuilder: { _ in S1_Other() })"
		let files = Self.callerFile(calling: call).merging(Self.mockTaking(["s1_HoleBuilder: @escaping Instantiator<S1_Hole>.Builder", "s1_OtherBuilder: @escaping () -> S1_Other"])) { $1 }
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: files) == [
			GraphFuzzerBuilderSurface.Finding(declaration: "the hand-written call `\(call)`", parameter: "s1_OtherBuilder: { _ in", reason: "takes a scope its place does not forward"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func handWrittenBuilderFindings_reportsBuilder_whenAnyTierOfMockTakesItsLabelAsBuilderOfPlaceThatForwardsNothing() {
		// The call reaches the widest tier it can see; a narrower tier that spells the builder otherwise is judged too.
		let files = Self.callerFile(calling: "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })").merging([
			"FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        s1_HoleBuilder: @escaping Instantiator<S1_Hole>.Builder\n    ) -> S1_T6 {\n    }\n\n    package static func mock(\n        s1_HoleBuilder: @escaping ErasedInstantiator<(), S1_Hole>.Builder,\n        holeToken: S1_HoleToken\n    ) -> S1_T6 {\n    }\n}\n",
		]) { $1 }
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: files) == [
			GraphFuzzerBuilderSurface.Finding(declaration: "the hand-written call `S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })`", parameter: "s1_HoleBuilder: { _ in", reason: "takes a scope its place does not forward"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func handWrittenBuilderFindings_reportsBuilder_whenNoGeneratedMockOfCalledTypeTakesItsLabel() {
		// A builder whose form the generated surface does not show is judged as taking a scope, as the judgment did before it
		// read the surface: the mock of another type that takes the label is not the called type's.
		let files = Self.callerFile(calling: "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })").merging([
			"FuzzFeature/S1_T5+SafeDIMock.swift": "extension S1_T5 {\n    public static func mock(\n        s1_HoleBuilder: @escaping Instantiator<S1_Hole>.Builder\n    ) -> S1_T5 {\n    }\n}\n",
		]) { $1 }
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: files) == [
			GraphFuzzerBuilderSurface.Finding(declaration: "the hand-written call `S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })`", parameter: "s1_HoleBuilder: { _ in", reason: "takes a scope its place does not forward"),
		])
	}

	/// A caller file the oracle adds in `FuzzOther` holding `call`.
	private static func callerFile(calling call: String) -> [String: String] {
		["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift": "public enum S1_T6PublicMockCaller {\n\tpublic static func call() -> S1_T6 {\n\t\t\(call)\n\t}\n}\n"]
	}

	/// `S1_T6`'s generated file, whose `public` `mock()` takes `parameters`.
	private static func mockTaking(_ parameters: [String]) -> [String: String] {
		["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        \(parameters.joined(separator: ",\n        "))\n    ) -> S1_T6 {\n    }\n}\n"]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func outputFeatures_readBuilderStructsAndTheCallsThatPassThem_whenPublicMockTakesBuilderStruct() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let generatedFiles = [
			"FuzzFeature/S1_T6+SafeDIMock.swift": """
			extension S1_T6 {
			    public static func mock(
			        s1_HoleBuilder: @escaping () -> S1_Hole
			    ) -> S1_T6 {
			        S1_T6.__safeDI_mock(s1_HoleBuilder: .init(__safeDI_noScope: s1_HoleBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        s1_HoleBuilder __safeDI_s1_HoleBuilder: S1_T6.SafeDIMockScope_S1_Hole.__safeDI_Builder<S1_Hole>
			    ) -> S1_T6 {
			        let holeLoopBuilder = Instantiator<S1_HoleLoop>(__safeDI_holeLoopBuilder)
			    }
			}
			""",
			"FuzzApp/S1_T7+SafeDIMock.swift": """
			extension S1_T7 {
			    static func mock() -> S1_T7 {
			        func __safeDI_s1_HoleBuilder_S1_T6() -> S1_T6.SafeDIMockScope_S1_Hole.__safeDI_Builder<S1_Hole> {
			        }
			        let t6 = S1_T6.__safeDI_mock(s1_HoleBuilder: __safeDI_s1_HoleBuilder_S1_T6())
			    }
			}
			""",
		]
		let features = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: generatedFiles)
		#expect(features.isSuperset(of: [.holeBuilder, .generatedOnlyMockFunction, .holeLoopBuilder, .holeLoopBuilderOfBuilderStruct, .consumerCall, .consumerFillsHole, .consumerPassesLevelFunctionsStruct]))
		#expect(!features.contains(.constructionFunction))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func outputFeatures_readIsolatedGeneratedOnlyFunction_whenMockAttributesIsolateMockToMainActor() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let isolated = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: [
			"FuzzFeature/S1_T6+SafeDIMock.swift": """
			extension S1_T6 {
			    @MainActor public static func mock(
			        s1_HoleBuilder: @escaping () -> S1_Hole
			    ) -> S1_T6 {
			        S1_T6.__safeDI_mock(s1_HoleBuilder: .init(__safeDI_noScope: s1_HoleBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    @MainActor public static func __safeDI_mock(
			        s1_HoleBuilder __safeDI_s1_HoleBuilder: S1_T6.SafeDIMockScope_S1_Hole.__safeDI_Builder<S1_Hole>
			    ) -> S1_T6 {
			    }
			}
			""",
		])
		#expect(isolated.isSuperset(of: [.generatedOnlyMockFunction, .isolatedGeneratedOnlyMockFunction]))
		// The same function without the attribute, and an isolated construction function, are not it.
		let nonisolated = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: [
			"FuzzFeature/S1_T6+SafeDIMock.swift": """
			extension S1_T6 {
			    public static func __safeDI_mock(
			        s1_HoleBuilder __safeDI_s1_HoleBuilder: S1_T6.SafeDIMockScope_S1_Hole.__safeDI_Builder<S1_Hole>
			    ) -> S1_T6 {
			    }

			    @MainActor static func __safeDI_mock(hole: S1_Hole, safeDIBuilder: ((S1_Hole) -> S1_T6)?) -> S1_T6 {
			    }
			}
			""",
		])
		#expect(nonisolated.contains(.generatedOnlyMockFunction))
		#expect(!nonisolated.contains(.isolatedGeneratedOnlyMockFunction))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func outputFeatures_readGeneratedOnlyFunctionBesideConstructionFunction_whenOneTypeDeclaresBoth() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let generatedOnly = """
		extension S1_T6 {
		    public static func __safeDI_mock(
		        s1_HoleBuilder __safeDI_s1_HoleBuilder: S1_T6.SafeDIMockScope_S1_Hole.__safeDI_Builder<S1_Hole>
		    ) -> S1_T6 {
		    }
		}
		"""
		let both = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: [
			"FuzzFeature/S1_T6+SafeDIMock.swift": generatedOnly,
			"FuzzFeature/S1_T6Deck+SafeDIMock.swift": "extension S1_T6 {\n    static func __safeDI_mock(hole: S1_Hole, safeDIBuilder: ((S1_Hole) -> S1_T6)?) -> S1_T6 {\n    }\n}\n",
		])
		#expect(both.isSuperset(of: [.generatedOnlyMockFunction, .constructionFunction, .generatedOnlyMockFunctionBesideConstructionFunction]))
		// Each function on a type of its own is not it.
		let apart = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: [
			"FuzzFeature/S1_T6+SafeDIMock.swift": generatedOnly,
			"FuzzFeature/S1_T0+SafeDIMock.swift": "extension S1_T0 {\n    static func __safeDI_mock(t3: S1_T3, safeDIBuilder: ((S1_T3) -> S1_T0)?) -> S1_T0 {\n    }\n}\n",
		])
		#expect(apart.isSuperset(of: [.generatedOnlyMockFunction, .constructionFunction]))
		#expect(!apart.contains(.generatedOnlyMockFunctionBesideConstructionFunction))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func outputFeatures_readPlacesPassedUpWithoutScope_whenConsumersPassBuildersAPersonWritesAndMembersOfTheirOwnStruct() {
		// A consumer that passes a place up takes the builder a person writes and hands the called mock a level function over
		// it, the builder wrapped as it is, or a member of its own struct; a `@Sendable` builder struct and `@Sendable`
		// level functions are read as the plain ones are.
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let features = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: [
			"FuzzFeature/S1_T6+SafeDIMock.swift": """
			extension S1_T6 {
			    public static func __safeDI_mock(
			        s1_HoleSendableBuilder __safeDI_s1_HoleSendableBuilder: S1_T6.SafeDISendableMockScope_S1_Hole.__safeDI_Builder<S1_Hole>
			    ) -> S1_T6 {
			    }
			}
			""",
			"FuzzApp/S1_T7+SafeDIMock.swift": """
			extension S1_T7 {
			    static func mock(
			        s1_HoleBuilder: @escaping () -> S1_Hole,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> S1_T7 {
			        func __safeDI_t6() -> S1_T6 {
			            @Sendable nonisolated func __safeDI_s1_HoleBuilder_S1_T6(up: S1_T6.SafeDIMockScope_S1_Hole.__safeDI_Builder<S1_Hole>) -> S1_T6.SafeDIMockScope_S1_Hole.__safeDI_Builder<S1_Hole> {
			            }
			            return S1_T6.__safeDI_mock(s1_HoleBuilder: __safeDI_s1_HoleBuilder_S1_T6(up: .init(__safeDI_noScope: s1_HoleBuilder)), safeDIOverrides: safeDIOverrides.t6)
			        }
			    }
			}
			""",
		])
		#expect(features.isSuperset(of: [.holeBuilder, .sendableHoleBuilder, .consumerPassesHoleBuilderUp, .consumerFillsHole, .consumerPassesPlaceUpWithoutScope]))
		let member = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: [
			"FuzzOther/S1_T8+SafeDIMock.swift": "extension S1_T8 {\n    public static func __safeDI_mock(\n    ) -> S1_T8 {\n        let t6 = S1_T6.__safeDI_mock(s1_HoleBuilder: __safeDI_s1_HoleBuilder.t6(SafeDIMockScope_S1_Hole.t6_Values()))\n    }\n}\n",
		])
		#expect(member.contains(.consumerPassesPlaceUpWithoutScope))
	}

	@Test
	func drawFeatures_readHoleMockAttributesAndHandWrittenMock_whenSeedsDrawThem() {
		func features(ofSeed seed: UInt64) -> Set<GraphFuzzerPublicMockDrawFeature> {
			GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		}
		let drawn: Set<GraphFuzzerPublicMockDrawFeature> = [.holeMockIsolatedToMainActor, .holeHandWrittenMockBuiltInPublicMock, .holeHandWrittenMockTakesNoOverrides]
		// Seed 7 isolates `T6`'s mock alone; seed 18 builds `T6` with its hand-written mock in `T6Deck` where `T6` builds a
		// tree of its own; seed 63 draws all three, `T6` instantiating nothing but its hole; seed 0 draws none.
		#expect(features(ofSeed: 7).intersection(drawn) == [.holeMockIsolatedToMainActor])
		#expect(features(ofSeed: 18).intersection(drawn) == [.holeHandWrittenMockBuiltInPublicMock])
		#expect(features(ofSeed: 63).isSuperset(of: drawn))
		#expect(features(ofSeed: 0).isDisjoint(with: drawn))
	}

	@Test
	func drawFeatures_readUnbuildableValueShapes_whenSeedsDrawThem() {
		func features(ofSeed seed: UInt64) -> Set<GraphFuzzerPublicMockDrawFeature> {
			GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		}
		let drawn: Set<GraphFuzzerPublicMockDrawFeature> = [.unbuildableValuePublicMockCall, .unbuildableValuePublicMockCallPublicTier, .unbuildableValuePublicMockCallTierOmits]
		// Seed 5 passes a public class to the public tier; seed 155's consumer in another package reaches a public tier that
		// omits `[3 of Int]`, the roll that fails with the omission walk's declarations reverted; seed 0 draws none.
		#expect(features(ofSeed: 5).intersection(drawn) == [.unbuildableValuePublicMockCall, .unbuildableValuePublicMockCallPublicTier])
		#expect(features(ofSeed: 155).intersection(drawn) == [.unbuildableValuePublicMockCall, .unbuildableValuePublicMockCallTierOmits])
		#expect(features(ofSeed: 0).isDisjoint(with: drawn))
	}

	@Test
	func drawFeatures_readOuterFulfillerShape_whenSeedsDrawIt() {
		func features(ofSeed seed: UInt64) -> Set<GraphFuzzerPublicMockDrawFeature> {
			GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		}
		#expect((0..<60).filter { features(ofSeed: $0).contains(.outerFulfillerPublicMockCall) } == [2, 5, 11, 23, 25, 47, 57])
	}

	@Test
	func drawFeatures_readHoleLabelShapes_whenSeedsDrawThem() {
		func features(ofSeed seed: UInt64) -> Set<GraphFuzzerPublicMockDrawFeature> {
			GraphFuzzerPublicMockDraw.drawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateMockPublic]))
		}
		let drawn: Set<GraphFuzzerPublicMockDrawFeature> = [.holeLabelReceivedByPromotedSibling, .holeLabelReceivedByPromotedSiblingHeldInInstantiator, .holeLabelReceivedByPromotedSiblingHeldInLazilyInstantiated, .holeLabelReceivedByPromotedSiblingEqualsGeneratedName]
		// Seed 981 holds the hole as itself, seed 937 in an `Instantiator`, seed 815 in a `LazilyInstantiated`; the tool
		// rejects each, and each is accepted and fails to compile with `publicMockHoleSiteBoundApartFinding` reverted. Seeds
		// 663 (the hole as itself) and 528 (in a `LazilyInstantiated`) label the hole with the name SafeDI generates for the
		// `LazilyInstantiated` it wraps; the tool rejects each, and each is accepted and fails to compile where the finding
		// is dropped for a label no type receives. Seed 1 draws none.
		#expect(features(ofSeed: 981).intersection(drawn) == [.holeLabelReceivedByPromotedSibling])
		#expect(features(ofSeed: 937).intersection(drawn) == [.holeLabelReceivedByPromotedSibling, .holeLabelReceivedByPromotedSiblingHeldInInstantiator])
		#expect(features(ofSeed: 815).intersection(drawn) == [.holeLabelReceivedByPromotedSibling, .holeLabelReceivedByPromotedSiblingHeldInLazilyInstantiated])
		#expect(features(ofSeed: 663).intersection(drawn) == [.holeLabelReceivedByPromotedSibling, .holeLabelReceivedByPromotedSiblingEqualsGeneratedName])
		#expect(features(ofSeed: 528).intersection(drawn) == [.holeLabelReceivedByPromotedSibling, .holeLabelReceivedByPromotedSiblingHeldInLazilyInstantiated, .holeLabelReceivedByPromotedSiblingEqualsGeneratedName])
		#expect(features(ofSeed: 1).isDisjoint(with: drawn))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func outputFeatures_readNoBuilderStruct_whenPublicMockKeepsClosureOverEnum() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let generatedFiles = [
			"FuzzFeature/S1_T6+SafeDIMock.swift": """
			extension S1_T6 {
			    public static func mock(
			        s1_HoleBuilder: @escaping (S1_T6.SafeDIMockScope_S1_Hole) -> S1_Hole
			    ) -> S1_T6 {
			        let holeLoopBuilder = Instantiator<S1_HoleLoop>(__safeDI_holeLoopBuilder)
			    }
			}

			extension S1_Card {
			    static func __safeDI_mock(api: any Api, safeDIBuilder: ((any Api) -> S1_Card)?) -> S1_Card {
			    }
			}
			""",
			"FuzzApp/S1_T7+SafeDIMock.swift": """
			extension S1_T7 {
			    static func mock() -> S1_T7 {
			        let t6 = S1_T6.mock(s1_HoleBuilder: __safeDI_s1_HoleBuilder_S1_T6)
			    }
			}
			""",
		]
		let features = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: generatedFiles)
		#expect(features.isSuperset(of: [.holeBuilder, .holeLoopBuilder, .consumerCall, .constructionFunction]))
		#expect(features.isDisjoint(with: [.generatedOnlyMockFunction, .holeLoopBuilderOfBuilderStruct, .consumerPassesLevelFunctionsStruct]))
	}

	@Test
	func seamOwnMockTakesBuilder_readsSeamsMockOnly_whenMockTakesClosureThatTakesNothing() {
		let seamMock = "extension S1_Home {\n    static func mock(\n        s1_ApiBuilder: @escaping () -> any S1_Api,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> S1_Home {\n    }\n}\n"
		#expect(GraphFuzzerFeature.seamOwnMockTakesBuilder(in: seamMock, seamTypeNames: ["S1_Home"]))
		// Another type's mock, and a seam's mock that takes a value for its place, take no such builder.
		#expect(!GraphFuzzerFeature.seamOwnMockTakesBuilder(in: seamMock, seamTypeNames: ["S1_Other"]))
		let valueMock = "extension S1_Home {\n    static func mock(\n        s1_Api: S1_Api,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> S1_Home {\n    }\n}\n"
		#expect(!GraphFuzzerFeature.seamOwnMockTakesBuilder(in: valueMock, seamTypeNames: ["S1_Home"]))
	}

	// MARK: Hand-written caller

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_addsCallInCallersModule_whenFileDeclaringPublicMockHoldsCallerMarker() {
		// The drawn path's file declaring `T6` names the caller's module and the call, which becomes a function in that
		// module; the known-right path spells the mock `true`, so it gets no caller.
		let call = "S1_T6.mock(holeBuilder: { (_: S1_T6.SafeDIMockScope_S1_T6_hole) in S1_Hole() })"
		let declaration = "@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {\n\tpublic init(hole: S1_Hole) {\n\t\tself.hole = hole\n\t}\n\n\t@Instantiated let hole: S1_Hole\n}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"
		let generatedFiles = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {}\n"]
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n" + declaration])
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: generatedFiles, of: drawn) == generatedFiles.merging([
			"FuzzOther/S1_T6+SafeDIPublicMockCaller.swift": "import FuzzFeature\n\n#if DEBUG\npublic enum S1_T6PublicMockCaller {\n\tpublic static func call() -> S1_T6 {\n\t\t\(call)\n\t}\n}\n#endif\n",
		]) { $1 })
		let knownRight = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n" + declaration.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")])
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: generatedFiles, of: knownRight) == generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func leafCalls_labelLeafByEraserLabel_whenConsumerWrapsCallInEraser() {
		// A consumer that reaches `T0` through its eraser holds it under `anyT0`, the label a described path names, and
		// one that reaches `T1` directly holds it under `t1`.
		let mock = "import FuzzFeature\n\nextension S1_T7 {\n    static func mock() -> S1_T7 {\n        let anyT0 = S1_AnyT0(S1_T0.mock(theme: nil))\n        let t1 = S1_T1.mock(theme: theme)\n        return S1_T7(anyT0: anyT0, t1: t1)\n    }\n}\n"
		#expect(GraphFuzzerOracle.leafCalls(ofMockedType: "S1_T7", in: ["FuzzApp/S1_T7+SafeDIMock.swift": mock], prefix: "S1_") == [
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "anyT0", passedLabels: [], instanceLabels: []),
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "t1", passedLabels: ["theme"], instanceLabels: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func leafCalls_readCallOfGeneratedOnlyMockFunction_whenCalledMockTakesBuilders() {
		// A consumer calls a public mock that takes builders through its function only generated code calls, directly
		// (`t6`) or inside the leaf's eraser (`anyT0`), handing it a wrapper's instance as `mock(` would.
		let mock = "import FuzzFeature\n\nextension S1_T8 {\n    static func mock() -> S1_T8 {\n        let holeSession = LazilyInstantiated<S1_HoleSession>(__safeDI_holeSession)\n        let anyT0 = S1_AnyT0(S1_T0.__safeDI_mock(theme: nil, s1_HoleBuilder: __safeDI_s1_HoleBuilder_S1_T0()))\n        let t6 = S1_T6.__safeDI_mock(holeSession: holeSession.instance, s1_HoleBuilder: __safeDI_s1_HoleBuilder_S1_T6(), safeDIOverrides: safeDIOverrides.t6)\n        return S1_T8(anyT0: anyT0, t6: t6, holeSession: holeSession)\n    }\n}\n"
		#expect(GraphFuzzerOracle.leafCalls(ofMockedType: "S1_T8", in: ["FuzzOther/S1_T8+SafeDIMock.swift": mock], prefix: "S1_") == [
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "anyT0", passedLabels: ["s1_HoleBuilder"], instanceLabels: []),
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "t6", passedLabels: ["holeSession", "s1_HoleBuilder"], instanceLabels: ["holeSession"]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func leafCalls_readCallOfPromotingPublicMock_whenConsumerBuildsPromoteNode() {
		// A consumer that builds `PromoteNode` calls its public mock, which promotes the `PromoteOther` its tree receives
		// lazily, handing it the instance of the wrapper the consumer's mock binds.
		let mock = "import FuzzFeature\n\nextension S1_PromoteScreen {\n    static func mock() -> S1_PromoteScreen {\n        let promoteOther = LazilyInstantiated<S1_PromoteOther>(__safeDI_promoteOther)\n        let promoteNode = S1_PromoteNode.__safeDI_mock(promoteApiBuilder: __safeDI_promoteApiBuilder_PromoteNode(), promoteOther: promoteOther.instance, safeDIOverrides: safeDIOverrides.promoteNode)\n        return S1_PromoteScreen(promoteNode: promoteNode)\n    }\n}\n"
		#expect(GraphFuzzerOracle.leafCalls(ofMockedType: "S1_PromoteScreen", in: ["FuzzApp/S1_PromoteScreen+SafeDIMock.swift": mock], prefix: "S1_") == [
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "promoteNode", passedLabels: ["promoteApiBuilder", "promoteOther"], instanceLabels: ["promoteOther"]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func leafCalls_labelLeafBySecondLabel_whenConsumerBuildsT6UnderT6Second() {
		// A consumer that builds `T6` under its second label calls its public mock inside that label's builder function,
		// whose calls are the `t6Second` leaf's.
		let mock = "extension S1_T8 {\n    static func mock() -> S1_T8 {\n        func __safeDI_t6() -> S1_T6 {\n            return S1_T6.__safeDI_mock(s1_HoleBuilder: __safeDI_b(), safeDIOverrides: safeDIOverrides.t6)\n        }\n        let t6: S1_T6 = __safeDI_t6()\n        func __safeDI_t6Second() -> S1_T6 {\n            return S1_T6.__safeDI_mock(s1_HoleBuilder: __safeDI_b(), safeDIOverrides: safeDIOverrides.t6Second)\n        }\n        let t6Second: S1_T6 = __safeDI_t6Second()\n        return S1_T8(t6: t6, t6Second: t6Second)\n    }\n}\n"
		#expect(GraphFuzzerOracle.leafCalls(ofMockedType: "S1_T8", in: ["FuzzOther/S1_T8+SafeDIMock.swift": mock], prefix: "S1_") == [
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "t6", passedLabels: ["s1_HoleBuilder"], instanceLabels: []),
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "t6Second", passedLabels: ["s1_HoleBuilder"], instanceLabels: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func leafCalls_readCallOfSecondCalledMock_whenConsumerBuildsT6Twin() {
		// A consumer that reaches the hole type through `T6Twin` too calls that public mock under `t6Twin`.
		let mock = "extension S1_T8 {\n    static func mock() -> S1_T8 {\n        let t6 = S1_T6.mock(theme: theme)\n        let t6Twin = S1_T6Twin.mock(theme: theme)\n        return S1_T8(t6: t6, t6Twin: t6Twin)\n    }\n}\n"
		#expect(GraphFuzzerOracle.leafCalls(ofMockedType: "S1_T8", in: ["FuzzOther/S1_T8+SafeDIMock.swift": mock], prefix: "S1_") == [
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "t6", passedLabels: ["theme"], instanceLabels: []),
			GraphFuzzerOracle.PublicMockLeafCall(leafLabel: "t6Twin", passedLabels: ["theme"], instanceLabels: []),
		])
	}

	// MARK: Compiler oracle

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportGraph_whenPublicTierNamesPackageType() async throws {
		// A public tier that names a package type does not compile in the declaring module, which the oracle reports as
		// generated code that does not compile; the same tier at `package` compiles.
		func runs(seed: UInt64, tierAccess: String) -> GraphFuzzerToolRuns {
			let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
			let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: [
				"// module: FuzzFeature\n\n@Instantiable\npackage final class \(prefix)Session: Instantiable {\n\tpackage init() {}\n}\n",
				"// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class \(prefix)Service: Instantiable {\n\tpackage init(session: \(prefix)Session) {\n\t\tself.session = session\n\t}\n\n\t@Received let session: \(prefix)Session\n}\n",
			])
			let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [
				"FuzzFeature/\(prefix)Service+SafeDIMock.swift": "extension \(prefix)Service {\n    \(tierAccess) static func mock(session: \(prefix)Session? = nil) -> \(prefix)Service {\n        \(prefix)Service(session: session ?? \(prefix)Session())\n    }\n}\n",
			], warnings: [])
			return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
		}
		let failures = try await GraphFuzzerOracle.compilationFailures(of: [runs(seed: 1, tierAccess: "public"), runs(seed: 2, tierAccess: "package")])
		#expect(failures[1]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[1]?.details.contains("cannot be declared public because its parameter uses a package type") == true)
		#expect(failures[2] == nil)
	}

	// MARK: Value oracle

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOracle_reportsDifferences_whenHandWrittenPublicTierLosesValueOrSharesNothingOrIgnoresOverride() async throws {
		// Section 5's self-tests: a public tier that drops a value its consumer holds, one that builds a second instance
		// of a dependency the consumer shares, and one whose body ignores an override field each build other values than
		// the known-right path.
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		let comparisons = try #require(try await DifferentialValueOracle.compare(graphs: [
			Self.droppedHeldValueGraph,
			Self.secondInstanceGraph,
			Self.ignoredOverrideGraph,
		], filesToDelete: &filesToDelete))
		let differences = try comparisons.map { try $0.result.get().differences }
		#expect(differences[0] == [DifferentialValueDifference(probe: "G1_Screen.mock()", path: ["<1> G1_Screen", "service", "theme"], feature: "theme: nil", knownRight: "theme: <2> G1_Theme (seen, first at <1> G1_Screen > theme)")])
		#expect(differences[1] == [DifferentialValueDifference(probe: "G2_Screen.mock()", path: ["<1> G2_Screen", "service", "analytics"], feature: "analytics: <4> G2_Analytics", knownRight: "analytics: <2> G2_Analytics (seen, first at <1> G2_Screen > analytics)")])
		#expect(differences[2] == [DifferentialValueDifference(probe: "G3_Service.mock(safeDIOverrides: .init(retries: 5))", path: ["<1> G3_Service", "retries"], feature: "retries: Int 3", knownRight: "retries: Int 5")])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func statedPublicMockValueDivergences_exemptOnlyWhatLeafCallsExplain_whenConsumerCallsPublicMocks() async throws {
		// The two divergences section 5 states, derived from the leaf calls of graphs shaped as the fuzzer draws them.
		// M8.32, in the gap where a public mock still takes a lazily received value as its instance: a consumer passes
		// `analytics.instance` of the wrapper it holds; the leaf's re-made wrapper, which the value
		// comparator compares by its instance, agrees, and the early read is exempt (seed 901), through a call of the
		// function only generated code calls too (seed 906) – unless the leaf wraps a new instance, which still fails
		// (seed 902). M8.9b: two
		// leaves each build the `session` their caller in another package cannot name (seed 903), or one builds it and the
		// other, receiving it only if available, holds `nil` (seed 905) – but a caller that holds `session` itself and passes
		// it to neither leaf still fails (seed 904).
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		let cases = [
			Self.heldWrapperCase(seed: 901, leafWrapsHeldInstance: true),
			Self.heldWrapperCase(seed: 902, leafWrapsHeldInstance: false),
			Self.instancePerLeafCase(seed: 903, callerHoldsSession: false),
			Self.instancePerLeafCase(seed: 904, callerHoldsSession: true),
			Self.instancePerLeafCase(seed: 905, callerHoldsSession: false, secondLeafReceivesOnlyIfAvailable: true),
			Self.heldWrapperCase(seed: 906, leafWrapsHeldInstance: true, callsGeneratedOnlyFunction: true),
		]
		let comparisons = try #require(try await DifferentialValueOracle.compare(graphs: cases.map(\.graph), filesToDelete: &filesToDelete))
		let remaining = try zip(cases, comparisons).map { testCase, comparison in
			let valueComparison = try comparison.result.get()
			#expect(!valueComparison.differences.isEmpty, "\(testCase.graph.name) builds what the known-right path builds")
			let stated = GraphFuzzerOracle.statedPublicMockValueDivergences(in: valueComparison, of: testCase.runs)
			return valueComparison.differences.filter { !stated.contains($0) }
		}
		#expect(remaining[0] == [])
		#expect(remaining[1] == [DifferentialValueDifference(probe: "S902_T8.mock()", path: ["<3>.instance"], feature: "<3>.instance: <9> S902_Analytics", knownRight: "<3>.instance: <6> S902_Analytics (seen, first at <1> S902_T8 > t0 > t3Builder > instantiate() > analytics)")])
		#expect(remaining[2] == [])
		#expect(remaining[4] == [])
		#expect(remaining[5] == [])
		#expect(remaining[3] == [DifferentialValueDifference(probe: "S904_T7.mock()", path: ["<1> S904_T7", "t0", "session"], feature: "session: <4> S904_Session", knownRight: "session: <2> S904_Session (seen, first at <1> S904_T7 > session)"), DifferentialValueDifference(probe: "S904_T7.mock()", path: ["<1> S904_T7", "t1", "session"], feature: "session: <6> S904_Session", knownRight: "session: <2> S904_Session (seen, first at <1> S904_T7 > session)")])
	}

	// MARK: Private

	/// `file` with every access modifier and every `generateMock:` argument erased, and each line trimmed.
	private static func erasingAccess(of file: String) -> String {
		file.split(separator: "\n").map { line in
			line.trimmingCharacters(in: .whitespaces)
				.replacingOccurrences(of: #"\b(public|package) "#, with: "", options: .regularExpression)
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}.joined(separator: "\n")
	}

	/// A path whose declaring module, `FuzzFeature`, holds `feature` and the hand-written mocks `featureMocks`, and whose
	/// consumer module in another package, `FuzzOther`, holds `consumer` and `consumerMocks`.
	private static func path(feature: String, featureMocks: String, consumer: String, consumerMocks: String) -> DifferentialValuePath {
		DifferentialValuePath(modules: [
			DifferentialValueModule(name: "FuzzFeature", packageName: "shop", fixtureFiles: ["Feature.swift": feature], generatedFiles: ["FeatureMocks.swift": featureMocks]),
			DifferentialValueModule(name: "FuzzOther", packageName: "other", dependencyModuleNames: ["FuzzFeature"], fixtureFiles: ["Consumer.swift": "import FuzzFeature\n\n" + consumer], generatedFiles: ["ConsumerMocks.swift": "import FuzzFeature\n\n" + consumerMocks]),
		])
	}

	/// A consumer holds `theme`, which the public tier it calls drops.
	private static let droppedHeldValueGraph = DifferentialValueGraph(
		name: "dropped held value",
		feature: path(
			feature: "public final class G1_Theme {\n\tpublic init() {}\n}\n\npublic final class G1_Service {\n\tpublic init(theme: G1_Theme?) {\n\t\tself.theme = theme\n\t}\n\n\tpublic let theme: G1_Theme?\n}\n",
			featureMocks: "extension G1_Service {\n\tpublic static func mock(theme: G1_Theme? = nil) -> G1_Service {\n\t\tG1_Service(theme: nil)\n\t}\n}\n",
			consumer: "public final class G1_Screen {\n\tpublic init(theme: G1_Theme, service: G1_Service) {\n\t\tself.theme = theme\n\t\tself.service = service\n\t}\n\n\tpublic let theme: G1_Theme\n\tpublic let service: G1_Service\n}\n",
			consumerMocks: "extension G1_Screen {\n\tstatic func mock() -> G1_Screen {\n\t\tlet theme = G1_Theme()\n\t\treturn G1_Screen(theme: theme, service: G1_Service.mock(theme: theme))\n\t}\n}\n",
		),
		knownRight: path(
			feature: "public final class G1_Theme {\n\tpublic init() {}\n}\n\npublic final class G1_Service {\n\tpublic init(theme: G1_Theme?) {\n\t\tself.theme = theme\n\t}\n\n\tpublic let theme: G1_Theme?\n}\n",
			featureMocks: "",
			consumer: "public final class G1_Screen {\n\tpublic init(theme: G1_Theme, service: G1_Service) {\n\t\tself.theme = theme\n\t\tself.service = service\n\t}\n\n\tpublic let theme: G1_Theme\n\tpublic let service: G1_Service\n}\n",
			consumerMocks: "extension G1_Screen {\n\tstatic func mock() -> G1_Screen {\n\t\tlet theme = G1_Theme()\n\t\treturn G1_Screen(theme: theme, service: G1_Service(theme: theme))\n\t}\n}\n",
		),
		probes: [DifferentialValueProbe("G1_Screen.mock()")],
	)

	/// A consumer shares `analytics` with the leaf it reaches, whose public tier builds another.
	private static let secondInstanceGraph = DifferentialValueGraph(
		name: "second instance",
		feature: path(
			feature: "public final class G2_Analytics {\n\tpublic init() {}\n}\n\npublic final class G2_Service {\n\tpublic init(analytics: G2_Analytics) {\n\t\tself.analytics = analytics\n\t}\n\n\tpublic let analytics: G2_Analytics\n}\n",
			featureMocks: "extension G2_Service {\n\tpublic static func mock(analytics: G2_Analytics? = nil) -> G2_Service {\n\t\tG2_Service(analytics: analytics ?? G2_Analytics())\n\t}\n}\n",
			consumer: "public final class G2_Screen {\n\tpublic init(analytics: G2_Analytics, service: G2_Service) {\n\t\tself.analytics = analytics\n\t\tself.service = service\n\t}\n\n\tpublic let analytics: G2_Analytics\n\tpublic let service: G2_Service\n}\n",
			consumerMocks: "extension G2_Screen {\n\tstatic func mock() -> G2_Screen {\n\t\tlet analytics = G2_Analytics()\n\t\treturn G2_Screen(analytics: analytics, service: G2_Service.mock())\n\t}\n}\n",
		),
		knownRight: path(
			feature: "public final class G2_Analytics {\n\tpublic init() {}\n}\n\npublic final class G2_Service {\n\tpublic init(analytics: G2_Analytics) {\n\t\tself.analytics = analytics\n\t}\n\n\tpublic let analytics: G2_Analytics\n}\n",
			featureMocks: "",
			consumer: "public final class G2_Screen {\n\tpublic init(analytics: G2_Analytics, service: G2_Service) {\n\t\tself.analytics = analytics\n\t\tself.service = service\n\t}\n\n\tpublic let analytics: G2_Analytics\n\tpublic let service: G2_Service\n}\n",
			consumerMocks: "extension G2_Screen {\n\tstatic func mock() -> G2_Screen {\n\t\tlet analytics = G2_Analytics()\n\t\treturn G2_Screen(analytics: analytics, service: G2_Service(analytics: analytics))\n\t}\n}\n",
		),
		probes: [DifferentialValueProbe("G2_Screen.mock()")],
	)

	/// A public tier whose body ignores its override's `retries` field.
	private static let ignoredOverrideGraph = DifferentialValueGraph(
		name: "ignored override",
		feature: path(
			feature: "public final class G3_Service {\n\tpublic init(retries: Int) {\n\t\tself.retries = retries\n\t}\n\n\tpublic let retries: Int\n}\n",
			featureMocks: "extension G3_Service {\n\tpublic struct SafeDIOverrides {\n\t\tpublic init(retries: Int? = nil) {\n\t\t\tself.retries = retries\n\t\t}\n\n\t\tpublic let retries: Int?\n\t}\n\n\tpublic static func mock(safeDIOverrides: SafeDIOverrides = .init()) -> G3_Service {\n\t\tG3_Service(retries: 3)\n\t}\n}\n",
			consumer: "",
			consumerMocks: "",
		),
		knownRight: path(
			feature: "public final class G3_Service {\n\tpublic init(retries: Int) {\n\t\tself.retries = retries\n\t}\n\n\tpublic let retries: Int\n}\n",
			featureMocks: "extension G3_Service {\n\tpublic struct SafeDIOverrides {\n\t\tpublic init(retries: Int? = nil) {\n\t\t\tself.retries = retries\n\t\t}\n\n\t\tpublic let retries: Int?\n\t}\n\n\tpublic static func mock(safeDIOverrides: SafeDIOverrides = .init()) -> G3_Service {\n\t\tG3_Service(retries: safeDIOverrides.retries ?? 3)\n\t}\n}\n",
			consumer: "",
			consumerMocks: "",
		),
		probes: [DifferentialValueProbe("G3_Service.mock(safeDIOverrides: .init(retries: 5))")],
	)

	/// A graph shaped as the fuzzer draws it, with hand-written generated code: the runs the derivation reads and the
	/// comparator's graph of them, probing `probe` alone.
	private struct StatedDivergenceCase {
		let runs: GraphFuzzerToolRuns
		let graph: DifferentialValueGraph
	}

	/// A stamped graph of `files` (`// module:` marked contents, the counter in the first) whose drawn path generated
	/// `featureFiles` and whose known-right path, `knownRightFiles` (rendered with every declaration `public`), generated
	/// `knownRightGeneratedFiles`.
	private static func statedDivergenceCase(seed: UInt64, files: [String], knownRightFiles: [String], featureFiles: [String: String], knownRightGeneratedFiles: [String: String], probe: String) -> StatedDivergenceCase {
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: files)
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: featureFiles, warnings: [])
		return StatedDivergenceCase(
			runs: GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, knownRightOutcome: .accepted(generatedFiles: knownRightGeneratedFiles, warnings: [])),
			graph: DifferentialValueGraph(
				name: "seed \(seed)",
				feature: DifferentialValuePath(fixture: fixture, generatedFiles: featureFiles),
				knownRight: DifferentialValuePath(fixture: GraphFuzzerFixture(seed: seed, swiftFileContent: knownRightFiles), generatedFiles: knownRightGeneratedFiles),
				probes: [DifferentialValueProbe(probe)],
			),
		)
	}

	/// M8.32, in the gap where a public mock still takes a lazily received value as its instance ("A lazy value a public
	/// mock takes", `public-mock-builders.md`): `T8`, in another package, holds `analytics` lazily and receives `T0`, which
	/// receives the wrapper only if available and builds `T3` through an `Instantiator`, which receives the value by value only
	/// if available, so
	/// `T0`'s public mock takes `analytics: Analytics? = nil`. `T8` calls it with `analytics.instance`, which the mock wraps
	/// again – around the instance it is passed, or, unless `leafWrapsHeldInstance`, around a new one. When
	/// `callsGeneratedOnlyFunction`, the mock is the function only generated code calls, `__safeDI_mock(`, as a call of a mock
	/// that takes builders is.
	private static func heldWrapperCase(seed: UInt64, leafWrapsHeldInstance: Bool, callsGeneratedOnlyFunction: Bool = false) -> StatedDivergenceCase {
		let p = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "\(p)Counter")
		let files = [
			"// module: FuzzFeature\n\n@Instantiable\npublic final class \(p)Analytics: Instantiable {\n\t\(stamp)\n\n\tpublic init() {}\n}\n\n" + DifferentialValueCreationStamp.counterDeclaration(named: "\(p)Counter") + "\n",
			"// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class \(p)T0: Instantiable {\n\t\(stamp)\n\n\tpublic init(analytics: LazilyInstantiated<\(p)Analytics>?, t3Builder: Instantiator<\(p)T3>) {\n\t\tself.analytics = analytics\n\t\tself.t3Builder = t3Builder\n\t}\n\n\t@Received(onlyIfAvailable: true) let analytics: LazilyInstantiated<\(p)Analytics>?\n\t@Instantiated let t3Builder: Instantiator<\(p)T3>\n}\n",
			"// module: FuzzFeature\n\n@Instantiable\npublic final class \(p)T3: Instantiable {\n\t\(stamp)\n\n\tpublic init(analytics: \(p)Analytics?) {\n\t\tself.analytics = analytics\n\t}\n\n\t@Received(onlyIfAvailable: true) let analytics: \(p)Analytics?\n}\n",
			"// module: FuzzOther\nimport FuzzFeature\n\n@Instantiable(generateMock: true)\npublic final class \(p)T8: Instantiable {\n\t\(stamp)\n\n\tpublic init(t0: \(p)T0, analytics: LazilyInstantiated<\(p)Analytics>) {\n\t\tself.t0 = t0\n\t\tself.analytics = analytics\n\t}\n\n\t@Received let t0: \(p)T0\n\t@Instantiated let analytics: LazilyInstantiated<\(p)Analytics>\n}\n",
		]
		let reWrapped = leafWrapsHeldInstance ? "instance" : "\(p)Analytics()"
		let mockFunction = callsGeneratedOnlyFunction ? "__safeDI_mock" : "mock"
		return statedDivergenceCase(
			seed: seed,
			files: files,
			knownRightFiles: files.map { $0.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true") },
			featureFiles: [
				"FuzzFeature/\(p)T0+SafeDIMock.swift": "extension \(p)T0 {\n    public static func \(mockFunction)(analytics: \(p)Analytics? = nil) -> \(p)T0 {\n        let analytics_lazilyInstantiated = analytics.map { instance in LazilyInstantiated<\(p)Analytics> { \(reWrapped) } }\n        let t3Builder = Instantiator<\(p)T3> { \(p)T3(analytics: analytics) }\n        return \(p)T0(analytics: analytics_lazilyInstantiated, t3Builder: t3Builder)\n    }\n}\n",
				"FuzzOther/\(p)T8+SafeDIMock.swift": "import FuzzFeature\n\nextension \(p)T8 {\n    static func mock() -> \(p)T8 {\n        let analytics = LazilyInstantiated<\(p)Analytics> { \(p)Analytics() }\n        let t0 = \(p)T0.\(mockFunction)(analytics: analytics.instance)\n        return \(p)T8(t0: t0, analytics: analytics)\n    }\n}\n",
			],
			knownRightGeneratedFiles: [
				"FuzzOther/\(p)T8+SafeDIMock.swift": "import FuzzFeature\n\nextension \(p)T8 {\n    static func mock() -> \(p)T8 {\n        let analytics = LazilyInstantiated<\(p)Analytics> { \(p)Analytics() }\n        return \(p)T8(t0: \(p)T0(analytics: analytics, t3Builder: Instantiator<\(p)T3> { \(p)T3(analytics: analytics.instance) }), analytics: analytics)\n    }\n}\n",
			],
			probe: "\(p)T8.mock()",
		)
	}

	/// M8.9b: two leaves, `T0` and `T1`, receive a package `session`, which their public mocks build – or which `T1`, when
	/// `secondLeafReceivesOnlyIfAvailable`, receives only if available and its mock leaves `nil` – and a caller calls both
	/// without passing it: `T8` in another package, or, when `callerHoldsSession`, `T7` in the same package holding
	/// `session` itself.
	private static func instancePerLeafCase(seed: UInt64, callerHoldsSession: Bool, secondLeafReceivesOnlyIfAvailable: Bool = false) -> StatedDivergenceCase {
		let p = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "\(p)Counter")
		func leaf(_ index: Int, access: String) -> String {
			let isOnlyIfAvailable = secondLeafReceivesOnlyIfAvailable && index == 1
			let type = isOnlyIfAvailable ? "\(p)Session?" : "\(p)Session"
			let attribute = isOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
			return "// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class \(p)T\(index): Instantiable {\n\t\(stamp)\n\n\t\(access) init(session: \(type)) {\n\t\tself.session = session\n\t}\n\n\t\(attribute) let session: \(type)\n}\n"
		}
		func files(sessionAccess: String) -> [String] {
			let consumer = callerHoldsSession
				? "// module: FuzzApp\nimport FuzzFeature\n\n@Instantiable(generateMock: true)\npublic final class \(p)T7: Instantiable {\n\t\(stamp)\n\n\tpackage init(session: \(p)Session, t0: \(p)T0, t1: \(p)T1) {\n\t\tself.session = session\n\t\tself.t0 = t0\n\t\tself.t1 = t1\n\t}\n\n\t@Instantiated let session: \(p)Session\n\t@Received let t0: \(p)T0\n\t@Received let t1: \(p)T1\n}\n"
				: "// module: FuzzOther\nimport FuzzFeature\n\n@Instantiable(generateMock: true)\npublic final class \(p)T8: Instantiable {\n\t\(stamp)\n\n\tpublic init(t0: \(p)T0, t1: \(p)T1) {\n\t\tself.t0 = t0\n\t\tself.t1 = t1\n\t}\n\n\t@Received let t0: \(p)T0\n\t@Received let t1: \(p)T1\n}\n"
			return [
				"// module: FuzzFeature\n\n@Instantiable\n\(sessionAccess) final class \(p)Session: Instantiable {\n\t\(stamp)\n\n\t\(sessionAccess) init() {}\n}\n\n" + DifferentialValueCreationStamp.counterDeclaration(named: "\(p)Counter") + "\n",
				leaf(0, access: sessionAccess),
				leaf(1, access: sessionAccess),
				consumer,
			]
		}
		let callerModule = callerHoldsSession ? "FuzzApp" : "FuzzOther"
		let caller = callerHoldsSession ? "\(p)T7" : "\(p)T8"
		let callerArguments = callerHoldsSession ? "session: session, t0: t0, t1: t1" : "t0: t0, t1: t1"
		let heldSession = callerHoldsSession ? "        let session = \(p)Session()\n" : ""
		return statedDivergenceCase(
			seed: seed,
			files: files(sessionAccess: "package"),
			knownRightFiles: files(sessionAccess: "public"),
			featureFiles: [
				"FuzzFeature/\(p)T0+SafeDIMock.swift": "extension \(p)T0 {\n    public static func mock() -> \(p)T0 {\n        \(p)T0(session: \(p)Session())\n    }\n}\n",
				"FuzzFeature/\(p)T1+SafeDIMock.swift": "extension \(p)T1 {\n    public static func mock() -> \(p)T1 {\n        \(p)T1(session: \(secondLeafReceivesOnlyIfAvailable ? "nil" : "\(p)Session()"))\n    }\n}\n",
				"\(callerModule)/\(caller)+SafeDIMock.swift": "import FuzzFeature\n\nextension \(caller) {\n    static func mock() -> \(caller) {\n\(heldSession)        let t0 = \(p)T0.mock()\n        let t1 = \(p)T1.mock()\n        return \(caller)(\(callerArguments))\n    }\n}\n",
			],
			knownRightGeneratedFiles: [
				"\(callerModule)/\(caller)+SafeDIMock.swift": "import FuzzFeature\n\nextension \(caller) {\n    static func mock() -> \(caller) {\n        let session = \(p)Session()\n        return \(caller)(\(callerHoldsSession ? "session: session, " : "")t0: \(p)T0(session: session), t1: \(p)T1(session: session))\n    }\n}\n",
			],
			probe: "\(caller).mock()",
		)
	}
}

/// The public mock smoke batch's results, drawn with the `generateMockPublic` feature, computed once per process.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let publicMockSmokeResults = SharedTestWork {
	try await GraphFuzzerOracle.results(forSeeds: SafeDIToolGraphFuzzerTests.publicMockSmokeSeeds, features: [.generateMockPublic])
}
