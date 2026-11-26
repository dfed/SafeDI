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
	func layoutParity_laysOutTheSameMocks_forAgreementSmokeAndDrawSeeds() async throws {
		var judged = 0
		var laidOut = 0
		for seed in Self.paritySeeds {
			let parity = try await GraphFuzzerV3LayoutParity.parity(ofSeed: seed)
			guard parity.judged else { continue }
			judged += 1
			laidOut += parity.laidOutUnderV2
			for difference in parity.differences {
				Issue.record("seed \(seed): \(difference)")
			}
		}
		// The oracle judges only graphs both versions accept, and only where the engine lays some mock out.
		#expect(judged >= 10)
		#expect(laidOut >= 10)
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

	/// O3's seeds: the agreement oracle's smoke seeds and the draws' smoke seeds.
	private static let paritySeeds: [UInt64] = GraphFuzzerAPIVersionAgreement.smokeSeeds + drawSmokeSeeds
}
