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
@testable import SafeDICore
@testable import SafeDIToolTestSupport

/// The v3 engine draws (`GraphFuzzerV3EngineDraw`) with their configured probes (`GraphFuzzerV3DrawnProbes`), and O3
/// (layout parity between `.v2` and `.v3Unstable`). Written before v3 is laid out on the shared engine: the tests that run the tool on a
/// `.v3Unstable` graph pass once the tree's tool generates `.v3Unstable` mocks with the type key on.
struct SafeDIToolGraphFuzzerV3EngineTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Draws

	@Test
	func drawnCounts_matchPins_whenAgreementCorpusIsDrawnWithoutTheTool() {
		// The draw is deterministic, so a change in a shape's share is a reviewed diff of these pins.
		let counts = GraphFuzzerV3EngineDraw.drawnCounts(forSeeds: 0..<Self.agreementCorpusSeedCount)
		#expect(counts == Self.drawnCountPins)
	}

	@Test
	func draws_drawEachVariantInTenGraphs_whenAgreementCorpusIsDrawn() {
		// Each variant stands in for its matrix cell's sibling unit tests only while ten graphs or more draw it.
		let draws = (0..<Self.agreementCorpusSeedCount).map(GraphFuzzerV3EngineDraw.init(seed:))
		for rightPlace in GraphFuzzerV3EngineDraw.RightPlace.allCases {
			#expect(draws.count { $0.configuredTypeUnderTwoParents?.rightPlace == rightPlace } >= 10, "\(rightPlace)")
		}
		for configuredPlaces in GraphFuzzerV3EngineDraw.ConfiguredPlaces.allCases {
			#expect(draws.count { $0.configuredTypeUnderTwoParents?.configuredPlaces == configuredPlaces } >= 10, "\(configuredPlaces)")
		}
		for isInstantiator in [false, true] {
			#expect(draws.count { $0.unbuildableValueAtTwoPlaces?.rightPlaceIsInstantiator == isInstantiator } >= 10, "\(isInstantiator)")
		}
		for secondCloser in GraphFuzzerV3EngineDraw.SecondCloser.allCases {
			#expect(draws.count { $0.twoClosersOfOneCycleTarget?.secondCloser == secondCloser } >= 10, "\(secondCloser)")
		}
		#expect(draws.count { $0.twoClosersOfOneCycleTarget?.laterPassConfiguresSecondCloser == true } >= 10)
	}

	@Test
	func smokeSeeds_drawEveryShape() {
		let shapes = Set(Self.drawSmokeSeeds.flatMap { GraphFuzzerV3EngineDraw(seed: $0).shapes })
		#expect(shapes == Set(GraphFuzzerV3EngineDraw.Shape.allCases))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func draws_areAcceptedAndCompile_whenGraphIsGeneratedAsV2() async throws {
		// The appended types are ones a person writes: the tool accepts them under `.v2`, and their mocks compile, in every
		// smoke seed whose own graph the tool accepts. The pinned `.v2` agreement classes are not moved by the draw.
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		for seed in Self.drawSmokeSeeds {
			let drawn = GraphFuzzerAPIVersionAgreement.fixture(forSeed: seed)
			let undrawn = GraphFuzzerGenerator.fixture(forSeed: seed, storingEveryParameter: true).mockingEveryClass.addingTwiceBuiltUnbuildableOwner
			let drawnRun = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: drawn, filesToDelete: &filesToDelete)
			let undrawnRun = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: undrawn, filesToDelete: &filesToDelete)
			switch (undrawnRun.outcome, drawnRun.outcome) {
			case (.rejected, _):
				continue
			case let (.compiled, .compiled(_, _, compilation)):
				#expect(compilation.exitCode == 0, "seed \(seed): \(compilation.stderr)")
			case let (.compiled, .rejected(diagnostics)):
				Issue.record("seed \(seed): the tool rejects the graph only with the v3 engine draws: \(diagnostics)")
			}
		}
	}

	// MARK: O3

	@Test
	func differences_reportEachKind_whenLayoutOutcomesDiffer() {
		let differences = GraphFuzzerV3LayoutParity.differences(
			v2: ["A": "laidOut", "B": "unrecorded:threw:x", "C": "unrecorded:threw:x", "D": "laidOut", "E": "laidOut"],
			v3: ["A": "unrecorded:threw:x", "B": "laidOut", "C": "unrecorded:threw:y", "D": "laidOut", "F": "laidOut"],
		)
		#expect(differences.map(\.kind) == [.v3FallsBackWhereV2LaysOut, .v3LaysOutWhereV2FallsBack, .fallbackReasonsDiffer, .mockReportedUnderOneVersionOnly, .mockReportedUnderOneVersionOnly])
		#expect(differences.map(\.mockedType) == ["A", "B", "C", "E", "F"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func layoutOutcomes_differ_whenOneRunKeepsTheWalksBody() async throws {
		// The oracle reads the tool's own report: a run whose mocks keep the walk's body reports nothing, so every mock the
		// engine lays out under the other run differs. The stand-in for O3's hand mutation until `.v3Unstable` runs on the engine.
		let fixture = GraphFuzzerAPIVersionAgreement.fixture(forSeed: Self.drawSmokeSeeds[0])
		let engine = try await GraphFuzzerV3LayoutParity.layoutOutcomes(of: fixture)
		let walk = try await MockLowering.$laysOutWithTypeKey.withValue(false) {
			try await GraphFuzzerV3LayoutParity.layoutOutcomes(of: fixture)
		}
		#expect(engine.toolAccepted && walk.toolAccepted)
		#expect(engine.outcomes.values.contains("laidOut"))
		let differences = GraphFuzzerV3LayoutParity.differences(v2: engine.outcomes, v3: walk.outcomes)
		#expect(differences.count == engine.outcomes.count)
		#expect(differences.allSatisfy { $0.kind == .mockReportedUnderOneVersionOnly })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func layoutParity_laysOutEveryMockV2LaysOut_forAgreementSmokeAndDrawSeeds() async throws {
		var judged = 0
		var laidOut = 0
		var laidOutOnlyUnderV3 = [String: [String]]()
		var keptByBothForOtherReasons = [String: [String]]()
		for seed in Self.paritySeeds {
			let parity = try await GraphFuzzerV3LayoutParity.parity(ofSeed: seed)
			guard parity.judged else { continue }
			judged += 1
			laidOut += parity.laidOutUnderV2
			for difference in parity.differences {
				switch difference.kind {
				case .v3FallsBackWhereV2LaysOut, .mockReportedUnderOneVersionOnly:
					Issue.record("seed \(seed): \(difference)")
				case .v3LaysOutWhereV2FallsBack:
					laidOutOnlyUnderV3[difference.v2FallbackKind ?? "", default: []].append(difference.mockedType)
				case .fallbackReasonsDiffer:
					keptByBothForOtherReasons[difference.reasonPair, default: []].append(difference.mockedType)
				}
			}
		}
		// The oracle judges only graphs both versions accept, and only where the engine lays some mock out.
		#expect(judged >= 10)
		#expect(laidOut >= 10)
		// The roots `.v3Unstable` lays out where `.v2` keeps the walk's body, by `.v2`'s reason: a change to `.v2` that lays
		// one out moves a pin.
		#expect(laidOutOnlyUnderV3.mapValues(\.count) == Self.laidOutOnlyUnderV3Pins, "\(laidOutOnlyUnderV3.sorted { $0.key < $1.key })")
		// The roots both keep the walk's body for, for different reasons, by the pair of reasons.
		#expect(keptByBothForOtherReasons.mapValues(\.count) == Self.keptByBothForOtherReasonsPins, "\(keptByBothForOtherReasons.sorted { $0.key < $1.key })")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func requiredArgumentProbes_callMocksTakingRequiredOptionalsInstantiatorsAndUnbuildableValues_forSeeds33And59() async throws {
		// `S33_T2.mock()` takes a required `t5: S33_T5?`, and `S59_T2.mock()` a required `items: Instantiator<S59_Value>`
		// beside values it cannot build: neither has a probe of the comparator's own, and each is a mock `.v3Unstable` lays
		// out where `.v2` keeps the walk's body.
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		var probes = [DifferentialValueProbe]()
		for seed: UInt64 in [33, 59] {
			let v2Fixture = GraphFuzzerAPIVersionAgreement.fixture(forSeed: seed)
			let v3Fixture = v2Fixture.declaringUnbuildableBuilderCalls.selectingAPIVersion(.v3Unstable)
			let v2Run = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: v2Fixture, filesToDelete: &filesToDelete)
			let v3Run = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: v3Fixture, filesToDelete: &filesToDelete)
			guard case let .compiled(v2Files, _, _) = v2Run.outcome, case let .compiled(v3Files, _, _) = v3Run.outcome else {
				Issue.record("seed \(seed): both versions compile the graph")
				continue
			}
			probes += v2Fixture.requiredArgumentProbes(v2GeneratedFiles: v2Files, v3GeneratedFiles: v3Files).filter { $0.name.hasPrefix("S33_T2.") || $0.name.hasPrefix("S59_T2.") }
		}
		#expect(probes == [
			DifferentialValueProbe(
				name: "S33_T2.mock(t5: nil)",
				expression: "{ () -> Any in S33_T2.mock(t5: nil) }()",
				knownRightExpression: "{ () -> Any in S33_T2.mock(t5: nil) }()",
			),
			DifferentialValueProbe(
				name: "S59_T2.mock(items: instantiator, t2: value, t3: value)",
				expression: "{ () -> Any in let t2 = S59_Unbuildable0(); let t3 = S59_Unbuildable0(); return S59_T2.mock(items: Instantiator<S59_Value> { S59_Value() }, t2: { t2 }, t3: { t3 }) }()",
				knownRightExpression: "{ () -> Any in let t2 = S59_Unbuildable0(); let t3 = S59_Unbuildable0(); return S59_T2.mock(items: Instantiator<S59_Value> { S59_Value() }, t2: t2, t3: t3) }()",
			),
		])
	}

	// MARK: O1 on the draws

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func agreement_classesDrawSmokeSeedsB_whenV3MocksTakeTheDrawnOverrides() async throws {
		// Each configured probe is compared with the tree built by hand under the Manual's rule for v3 overrides, beside the
		// agreement oracle's `.v2` comparison. Seeds 99, 383, 584, 764, 786, 1496 and 1758, step 2's regressions, are among them.
		let verdicts = try await GraphFuzzerAPIVersionAgreement.verdicts(forSeeds: Self.drawSmokeSeeds)
		for verdict in verdicts {
			#expect(verdict.verdict.verdictClass == .valuesAgree, "seed \(verdict.seed): \(verdict.verdict)")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The agreement corpus: the base corpus's seeds.
	private static let agreementCorpusSeedCount: UInt64 = 5_000

	/// Graphs of the agreement corpus that draw each shape, by `GraphFuzzerV3EngineDraw.drawnCounts(forSeeds:)`.
	private static let drawnCountPins: [GraphFuzzerV3EngineDraw.Shape: Int] = [
		.configuredTypeUnderTwoParents: 1_504,
		.unbuildableValueAtTwoPlaces: 1_534,
		.twoClosersOfOneCycleTarget: 1_514,
	]

	/// Seeds whose own graph the tool accepts and that together draw every shape and every right place, configured places
	/// and second closer, plus step 2's regression seeds, which must stay class B.
	private static let drawSmokeSeeds: [UInt64] = [0, 2, 13, 14, 15, 33, 35, 36, 38, 51, 59, 64, 68, 99, 383, 584, 764, 786, 1_496, 1_758]

	/// O3's seeds: the agreement oracle's smoke seeds and the draws' smoke seeds, each once.
	private static let paritySeeds: [UInt64] = (GraphFuzzerAPIVersionAgreement.smokeSeeds + drawSmokeSeeds).reduce(into: []) { seeds, seed in
		if !seeds.contains(seed) {
			seeds.append(seed)
		}
	}

	/// The roots of O3's seeds `.v3Unstable` lays out where `.v2` keeps the walk's body, counted by `.v2`'s reason. The
	/// agreement oracle compares the values of all sixteen with `.v2`'s walk, and hand mutations of `.v3Unstable`'s laid-out
	/// bodies fail seven of them: calling each builder of a value the mock cannot build twice fails seeds 99 and 584 at
	/// `S99_T3`, `S99_T7`, `S584_T7` and `S584_ZTwiceHost`; building a root binding read twice once more for its last
	/// reader fails seed 0 at `S0_WrapKindsHost`; and, through the probes of mocks that take required arguments
	/// (`requiredArgumentProbes`), reading `S59_T2`'s builder of `t2` for `t3` fails seed 59, and handing `S33_T2` the
	/// `S33_T5` its `t4` holds for its `lazyT5` fails seed 33. None of the three mutations tried on every laid-out body
	/// (those two, and every laid-out builder function's first result reused for its later calls) changes the values of
	/// `S23_T4`, `S64_Root0` or `S786_T7`, which call no builder twice and whose bindings the second reaches nowhere a probe
	/// reads; their probes are compared all the same. Seed 93's `S93_T7`, `S93_T8` and `S93_T9`, and seed 212's
	/// `S212_T2`, `S212_T3` and `S212_WrapKindsHost`, smoke seeds for the loop of builders that keeps the walk's body where
	/// its text reads a configuration around it (`recordLoopUnit`), are not mutation-tested; their probes are compared.
	private static let laidOutOnlyUnderV3Pins: [String: Int] = [
		"engineRefused": 2,
		"namedApart": 6,
		"readUnresolved": 1,
		"unplannedLines": 7,
	]

	/// The roots of O3's seeds both versions keep the walk's body for, for different reasons, by `.v2`'s reason and then
	/// `.v3Unstable`'s: both build what the walk builds, so they are pinned, not failed.
	private static let keptByBothForOtherReasonsPins: [String: Int] = [
		"unrecorded:unplannedLines:overrideExtraction | unrecorded:unplannedLines:rebindings": 3,
	]
}
