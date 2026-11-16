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
		// of each shape it shows, which must fail exactly as listed, and graphs that must pass.
		let knownIssuesBySeed = Dictionary(uniqueKeysWithValues: SafeDIToolGraphFuzzerTests.publicMockKnownIssues.flatMap { knownIssue in knownIssue.seeds.map { ($0, knownIssue) } })
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
		let staleValue = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/HoleFill.swift:3:2: error: `S50_Hole` receives `holeContext: S50_HoleContext`, which `S50_HoleLoop` declares between where `S50_T6` instantiates `holeHostBuilder: Instantiator<S50_HoleHost>` and where `S50_HoleLoop` instantiates it again. Inline, the `S50_HoleHost` built again receives `S50_HoleLoop`’s `holeContext`, but the scope SafeDI hands the builder for `S50_HoleHost`’s `holeBuilder: Instantiator<S50_Hole>` (case `S50_HoleHost_Scope.holeBuilder` of `s50_HoleBuilder`) holds the same values at every level of that cycle. Give `holeContext` on `S50_HoleLoop` another label, or declare an @Instantiable type that fulfills `S50_Hole` in module `FuzzFeature` or a module it lists among its SafeDI dependencies.")
		let inaccessible = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Session.swift:4:12: error: `Session` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates.")
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let staleValueOfOtherLabel = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/HoleFill.swift:3:2: error: `S50_Hole` receives `session: S50_Session`, which `S50_HoleLoop` declares between where `S50_T6` instantiates `holeHostBuilder: Instantiator<S50_HoleHost>` and where `S50_HoleLoop` instantiates it again. Inline, the `S50_HoleHost` built again receives `S50_HoleLoop`’s `session`, but the scope SafeDI hands the builder for `S50_HoleHost`’s `holeBuilder: Instantiator<S50_Hole>` (case `S50_HoleHost_Scope.holeBuilder` of `s50_HoleBuilder`) holds the same values at every level of that cycle. Give `session` on `S50_HoleLoop` another label, or declare an @Instantiable type that fulfills `S50_Hole` in module `FuzzFeature` or a module it lists among its SafeDI dependencies.")
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
	func addingPublicMockCallers_recordsIssue_whenCallPassesTwoBuildersToMockThatTakesClosuresThatTakeNothing() {
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() }, s1_OtherBuilder: { _ in S1_Other() })"
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		let switched = ["FuzzFeature/S1_T6+SafeDIMock.swift": "extension S1_T6 {\n    public static func mock(\n        s1_HoleBuilder: @escaping () -> S1_Hole,\n        s1_OtherBuilder: @escaping () -> S1_Other\n    ) -> S1_T6 {\n    }\n}\n"]
		withKnownIssue {
			_ = GraphFuzzerOracle.addingPublicMockCallers(to: switched, of: drawn)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_recordsIssue_whenPublicMockTakesBuilderTheDrawnCallDoesNotPass() {
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })"
		let drawn = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"])
		withKnownIssue {
			_ = GraphFuzzerOracle.addingPublicMockCallers(to: Self.mockTakingTwoBuilders, of: drawn)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingPublicMockCallers_convertsTheCallsBuilder_whenBuilderSurfaceEditGivesPublicMockAnotherBuilder() {
		// The edit adds a builder after the draw wrote the call, which the same-supply judgment judges instead.
		let call = "S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })"
		let edited = GraphFuzzerFixture(seed: 1, swiftFileContent: ["// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class S1_T6: Instantiable {}\n\n\(GraphFuzzerPublicMockDraw.publicMockCallerMarker)FuzzOther: \(call)\n"], isBuilderSurfaceEdit: true)
		#expect(GraphFuzzerOracle.addingPublicMockCallers(to: Self.mockTakingTwoBuilders, of: edited)["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift"]?.contains("\t\tS1_T6.mock(s1_HoleBuilder: { S1_Hole() })\n") == true)
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
		let switched = ["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift": "public enum S1_T6PublicMockCaller {\n\tpublic static func call() -> S1_T6 {\n\t\tS1_T6.mock(s1_HoleBuilder: { S1_Hole() })\n\t}\n}\n"]
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: switched).isEmpty)
		let kept = ["FuzzOther/S1_T6+SafeDIPublicMockCaller.swift": "public enum S1_T6PublicMockCaller {\n\tpublic static func call() -> S1_T6 {\n\t\tS1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })\n\t}\n}\n"]
		#expect(GraphFuzzerBuilderSurface.handWrittenBuilderFindings(in: kept) == [
			GraphFuzzerBuilderSurface.Finding(declaration: "the hand-written call `S1_T6.mock(s1_HoleBuilder: { _ in S1_Hole() })`", parameter: "s1_HoleBuilder: { _ in", reason: "takes a scope its place does not forward"),
		])
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
			        func __safeDI_s1_HoleBuilder_S1_T6_S1_HoleHost_Scope(_ __safeDI_s1_HoleBuilder_S1_T6_wrap: @escaping (S1_T6.SafeDIMockScope_S1_Hole.S1_HoleHost_Scope) -> S1_T6.SafeDIMockScope_S1_Hole) -> S1_T6.SafeDIMockScope_S1_Hole.S1_HoleHost_Scope.__safeDI_Builder<S1_Hole> {
			        }
			        let t6 = S1_T6.__safeDI_mock(s1_HoleBuilder: __safeDI_s1_HoleBuilder_S1_T6())
			        let t6Second = S1_T6.__safeDI_mock(s1_HoleBuilder: .init(s1_Hole: { __safeDI_s1_HoleValues in s1_HoleBuilder(.s1_Hole(__safeDI_s1_HoleValues)) }))
			    }
			}
			""",
		]
		let features = GraphFuzzerPublicMockDraw.outputFeatures(of: fixture, generatedFiles: generatedFiles)
		#expect(features.isSuperset(of: [.holeBuilder, .generatedOnlyMockFunction, .holeLoopBuilder, .holeLoopBuilderOfBuilderStruct, .consumerCall, .consumerFillsHole, .consumerPassesLevelFunctionsStruct, .consumerConvertsClosureOverEnum, .consumerConvertsOverReopenedLevel]))
		#expect(!features.contains(.constructionFunction))
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
		#expect(features.isDisjoint(with: [.generatedOnlyMockFunction, .holeLoopBuilderOfBuilderStruct, .consumerPassesLevelFunctionsStruct, .consumerConvertsClosureOverEnum, .consumerConvertsOverReopenedLevel]))
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
		// M8.32: a consumer passes `analytics.instance` of the wrapper it holds; the leaf's re-made wrapper and the early
		// read are exempt (seed 901) – unless the leaf wraps a new instance, whose wrapper still fails (seed 902). M8.9b: two
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
		]
		let comparisons = try #require(try await DifferentialValueOracle.compare(graphs: cases.map(\.graph), filesToDelete: &filesToDelete))
		let remaining = try zip(cases, comparisons).map { testCase, comparison in
			let valueComparison = try comparison.result.get()
			#expect(!valueComparison.differences.isEmpty, "\(testCase.graph.name) builds what the known-right path builds")
			let stated = GraphFuzzerOracle.statedPublicMockValueDivergences(in: valueComparison, of: testCase.runs)
			return valueComparison.differences.filter { !stated.contains($0) }
		}
		#expect(remaining[0] == [])
		#expect(remaining[1] == [DifferentialValueDifference(probe: "S902_T8.mock()", path: ["<1> S902_T8", "analytics"], feature: "analytics: <4> LazilyInstantiated<S902_Analytics> (instance read last)", knownRight: "analytics: <3> LazilyInstantiated<S902_Analytics> (seen, first at <1> S902_T8 > t0 > analytics)")])
		#expect(remaining[2] == [])
		#expect(remaining[4] == [])
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

	/// M8.32: `T8`, in another package, holds `analytics` lazily, receives `T0`, which receives the wrapper, and calls
	/// `T0`'s public mock with `analytics.instance`, which the mock wraps again – around the instance it is passed, or,
	/// unless `leafWrapsHeldInstance`, around a new one.
	private static func heldWrapperCase(seed: UInt64, leafWrapsHeldInstance: Bool) -> StatedDivergenceCase {
		let p = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "\(p)Counter")
		let files = [
			"// module: FuzzFeature\n\n@Instantiable\npublic final class \(p)Analytics: Instantiable {\n\t\(stamp)\n\n\tpublic init() {}\n}\n\n" + DifferentialValueCreationStamp.counterDeclaration(named: "\(p)Counter") + "\n",
			"// module: FuzzFeature\n\n@Instantiable(generateMock: .public)\npublic final class \(p)T0: Instantiable {\n\t\(stamp)\n\n\tpublic init(analytics: LazilyInstantiated<\(p)Analytics>) {\n\t\tself.analytics = analytics\n\t}\n\n\t@Received let analytics: LazilyInstantiated<\(p)Analytics>\n}\n",
			"// module: FuzzOther\nimport FuzzFeature\n\n@Instantiable(generateMock: true)\npublic final class \(p)T8: Instantiable {\n\t\(stamp)\n\n\tpublic init(t0: \(p)T0, analytics: LazilyInstantiated<\(p)Analytics>) {\n\t\tself.t0 = t0\n\t\tself.analytics = analytics\n\t}\n\n\t@Received let t0: \(p)T0\n\t@Instantiated let analytics: LazilyInstantiated<\(p)Analytics>\n}\n",
		]
		let reWrapped = leafWrapsHeldInstance ? "analytics ?? \(p)Analytics()" : "\(p)Analytics()"
		return statedDivergenceCase(
			seed: seed,
			files: files,
			knownRightFiles: files.map { $0.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true") },
			featureFiles: [
				"FuzzFeature/\(p)T0+SafeDIMock.swift": "extension \(p)T0 {\n    public static func mock(analytics: \(p)Analytics? = nil) -> \(p)T0 {\n        \(p)T0(analytics: LazilyInstantiated { \(reWrapped) })\n    }\n}\n",
				"FuzzOther/\(p)T8+SafeDIMock.swift": "import FuzzFeature\n\nextension \(p)T8 {\n    static func mock() -> \(p)T8 {\n        let analytics = LazilyInstantiated<\(p)Analytics> { \(p)Analytics() }\n        let t0 = \(p)T0.mock(analytics: analytics.instance)\n        return \(p)T8(t0: t0, analytics: analytics)\n    }\n}\n",
			],
			knownRightGeneratedFiles: [
				"FuzzOther/\(p)T8+SafeDIMock.swift": "import FuzzFeature\n\nextension \(p)T8 {\n    static func mock() -> \(p)T8 {\n        let analytics = LazilyInstantiated<\(p)Analytics> { \(p)Analytics() }\n        return \(p)T8(t0: \(p)T0(analytics: analytics), analytics: analytics)\n    }\n}\n",
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
