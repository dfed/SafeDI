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

struct SafeDIToolReleaseAcceptanceTests {
	// MARK: Known breaks

	/// A seed whose break from an older release is expected: a release-noted behavior change (a known break), or a
	/// defect of the older release this tree fixed (an exemption).
	struct ListedSeed {
		enum Kind: String {
			case knownBreak = "known-break"
			case exemption = "exempted"
			/// A graph whose probe spends even `DifferentialValueLimits.isolatedFuzzerGraph`'s traversals on both releases,
			/// so the comparator describes none of its values beneath that node: class X, as the corpus's own known issue
			/// lists the seed.
			case beyondComparator = "beyond-comparator"
		}

		let corpus: GraphFuzzerReleaseAcceptanceCorpus
		let seed: UInt64
		let kind: Kind
		let verdictClass: GraphFuzzerReleaseAcceptanceClass
		let reason: String
	}

	/// The seeds whose break from each older release is expected, by the release's name, each of its corpus. A seed of
	/// another class, or one that no longer breaks, fails the run as stale. Each is attributed, never listed to make a
	/// run pass: a break is release-noted, or a defect of the older release this tree fixed, and lists the seed in the
	/// change that makes it.
	static let listedSeedsByRelease: [String: [ListedSeed]] = [
		"2.3.0": [
			ListedSeed(corpus: .base, seed: 8, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 9, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 91, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 116, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 133, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 141, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 165, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 175, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 195, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 206, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 207, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 210, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 227, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 252, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 290, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 295, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 296, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 351, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 352, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 362, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 434, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 515, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 531, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 556, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 565, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 576, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 626, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 635, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 644, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 711, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 731, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 881, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 928, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 976, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_053, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_180, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 1_248, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_269, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 1_283, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_307, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_401, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 1_602, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_678, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_746, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 1_938, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_013, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_016, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_152, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_157, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_254, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 2_270, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 2_298, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 2_388, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 2_413, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 2_420, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_611, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_618, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_637, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 2_674, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 2_706, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_735, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_762, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_790, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_824, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_832, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_837, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_881, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_891, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 2_964, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_012, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_042, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 3_102, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_225, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_269, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_286, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_288, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_302, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 3_344, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_405, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 3_434, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_599, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_608, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 3_854, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_864, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 3_924, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_085, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_087, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_166, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_169, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_179, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_204, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_207, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_211, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_212, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_227, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 4_356, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_358, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_365, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_387, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_418, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_420, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 4_522, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 4_548, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 4_549, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_551, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_613, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_664, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 4_690, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_692, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 4_732, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_746, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_803, kind: .knownBreak, verdictClass: .valuesDiffer, reason: mockPassesNilAsProductionDoesReason),
			ListedSeed(corpus: .base, seed: 4_875, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_883, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_885, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_890, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .base, seed: 4_993, kind: .exemption, verdictClass: .valuesDiffer, reason: nearestDeclarationInNestedCycleReason),
			ListedSeed(corpus: .seam, seed: 391, kind: .beyondComparator, verdictClass: .valuesNotCompared, reason: beyondComparatorReason),
			ListedSeed(corpus: .seam, seed: 1_311, kind: .beyondComparator, verdictClass: .valuesNotCompared, reason: beyondComparatorReason),
		],
	]

	/// #892: a mock passes `nil`, as production does, to a receive only if available of the other `LazilyInstantiated`
	/// kind beside a required wrapper of the same instance, where 2.3.0's mock handed it a wrapper it made.
	/// Seam seeds 391 and 1311, whose `Root0()` spends even a graph's own traversals through chains of hole draws that
	/// re-enter `HoleSeam` (`HoleLoop`, `HoleDeep`, and `HoleInner2` or `HoleRelay` and `HolePing`) on both releases, as the
	/// seam corpus's known issue of them says.
	static let beyondComparatorReason = "the comparator cannot describe the graph's values within its isolated traversal budget"

	static let mockPassesNilAsProductionDoesReason = "#892, a 2.3.0 mock defect fixed and release-noted"

	/// A type built again through a second lazy cycle received the outer declaration of a label where the nearest one is in scope. Each seed draws that shape (`S<seed>_NestRoot`), and its only difference is that label’s value.
	static let nearestDeclarationInNestedCycleReason = "#1065, a 2.3.0 defect fixed: a type a second lazy cycle builds again received the outer declaration of a label"

	@Test(arguments: GraphFuzzerReleaseAcceptanceCorpus.allCases)
	func releaseAcceptanceFixture_drawsTheCorpusGraphWithoutFeaturesOlderReleaseRejects_whenDrawnForComparison(corpus: GraphFuzzerReleaseAcceptanceCorpus) {
		// 2.3.0 rejects `@Instantiated(onlyIfAvailable: true)` and the `@Instantiable` actors `addingActorArgumentShapes`
		// draws, and every release rejects the shapes `addingPlaceStoodForShapes` draws, so a graph drawing any of them
		// would be class A, compared by nothing.
		func drawsFeatureOlderReleaseRejects(_ fixture: GraphFuzzerFixture) -> Bool {
			let text = fixture.swiftFileContent.joined(separator: "\n")
			return text.contains("@Instantiated(onlyIfAvailable: true") || text.range(of: #"actor \w+: Instantiable"#, options: .regularExpression) != nil || text.contains("_StoodForHome: Instantiable")
		}
		var corpusGraphsDrawingOne = 0
		for seed in UInt64(0)..<300 {
			let corpusFixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: corpus.features, storingEveryParameter: true)
			let comparedFixture = GraphFuzzerGenerator.releaseAcceptanceFixture(forSeed: seed, features: corpus.features)
			#expect(!drawsFeatureOlderReleaseRejects(comparedFixture), "seed \(seed)")
			if drawsFeatureOlderReleaseRejects(corpusFixture) {
				corpusGraphsDrawingOne += 1
			} else {
				// Each left-out draw has a stream of its own, so a graph that draws none of them is the corpus's.
				#expect(comparedFixture.swiftFileContent == corpusFixture.swiftFileContent, "seed \(seed)")
			}
		}
		#expect(corpusGraphsDrawingOne >= 10, "\(corpus)")
	}

	@Test
	func listedSeeds_listEachSeedOnceAsABreak_forEachRelease() {
		for (release, listedSeeds) in Self.listedSeedsByRelease {
			for corpus in GraphFuzzerReleaseAcceptanceCorpus.allCases {
				let seeds = listedSeeds.filter { $0.corpus == corpus }.map(\.seed)
				#expect(seeds == seeds.sorted(), "\(release) \(corpus)")
				#expect(Set(seeds).count == seeds.count, "\(release) \(corpus)")
			}
			#expect(listedSeeds.allSatisfy { ($0.kind == .beyondComparator ? $0.verdictClass == .valuesNotCompared : $0.verdictClass.isBreak) && $0.seed < UInt64(ReleaseAcceptanceLongRunConfiguration.seedCount(of: $0.corpus)) }, "\(release)")
		}
	}

	// MARK: Classes

	@Test
	func classify_reportsOlderReleaseRejects_whenOlderToolReportsAnError() {
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .rejectedRun, current: .cleanRun(), probes: Self.noProbes)
		#expect(classification == .decided(GraphFuzzerReleaseVerdict(verdictClass: .olderReleaseRejects, rejection: .toolError, details: "error: Dependency cycle detected")))
	}

	@Test
	func classify_reportsOlderReleaseRejects_whenOlderMacrosRejectFixture() {
		let older = GraphFuzzerReleaseRun.compiledRun(exitCode: 1, stderr: "/scratch/Fixture/S0_Root0.swift:3:2: error: @Instantiated property must be a stored property")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: older, current: .cleanRun(), probes: Self.noProbes)
		#expect(classification == .decided(GraphFuzzerReleaseVerdict(verdictClass: .olderReleaseRejects, rejection: .macroError, details: "@Instantiated property must be a stored property")))
	}

	@Test
	func classify_reportsOlderReleaseRejects_whenOlderGeneratedCodeDoesNotCompile() {
		let older = GraphFuzzerReleaseRun.compiledRun(exitCode: 1, stderr: "/scratch/Generated/S0_Root0+SafeDI.swift:9:4: error: cannot find 'tBuilder' in scope")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: older, current: .cleanRun(), probes: Self.noProbes)
		#expect(classification == .decided(GraphFuzzerReleaseVerdict(verdictClass: .olderReleaseRejects, rejection: .compileFailure, details: "cannot find 'tBuilder' in scope")))
	}

	@Test
	func classify_reportsCurrentRejects_whenOnlyCurrentToolReportsAnError() {
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(), current: .rejectedRun, probes: Self.noProbes)
		#expect(classification == .decided(GraphFuzzerReleaseVerdict(verdictClass: .currentRejects, details: "error: Dependency cycle detected")))
	}

	@Test
	func classify_reportsCurrentDoesNotCompile_whenOnlyCurrentGeneratedCodeFailsToCompile() {
		let current = GraphFuzzerReleaseRun.compiledRun(exitCode: 1, stderr: "/scratch/Generated/S0_Root0+SafeDI.swift:9:4: error: cannot find 'tBuilder' in scope")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(), current: current, probes: Self.noProbes)
		#expect(classification == .decided(GraphFuzzerReleaseVerdict(verdictClass: .currentDoesNotCompile, details: "cannot find 'tBuilder' in scope")))
	}

	@Test
	func classify_reportsCurrentDrawsNewGeneratedWarning_whenOnlyCurrentGeneratedCodeDrawsAWarning() {
		let current = GraphFuzzerReleaseRun.compiledRun(stderr: "/scratch/Generated/S0_Root0+SafeDIMock.swift:12:7: warning: initialization of immutable value 't7Builder' was never used")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(), current: current, probes: Self.noProbes)
		#expect(classification == .comparesValues(GraphFuzzerReleaseVerdict(verdictClass: .currentDrawsNewGeneratedWarning, details: "initialization of immutable value 't7Builder' was never used"), probes: []))
	}

	@Test
	func classify_reportsCurrentDrawsNewGeneratedWarning_whenWarningIsAtFixtureLineASourceLocationDirectiveAttributesGeneratedCodeTo() {
		let current = GraphFuzzerReleaseRun.compiledRun(stderr: "/scratch/SourceLocation/S0_T1.swift:6:3: warning: variable 't3' was never mutated")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(), current: current, probes: Self.noProbes)
		#expect(classification == .comparesValues(GraphFuzzerReleaseVerdict(verdictClass: .currentDrawsNewGeneratedWarning, details: "variable 't3' was never mutated"), probes: []))
	}

	@Test
	func classify_comparesValuesOfProbesBothGenerate_whenBothCompileCleanly() {
		let probes = [DifferentialValueProbe("S0_Root0()"), DifferentialValueProbe("S0_T1.mock()"), DifferentialValueProbe("S0_T2.mock()")]
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(generatedFiles: ["Old.swift": ""]), current: .cleanRun()) { generatedFiles in
			generatedFiles["Old.swift"] == nil ? probes : Array(probes.prefix(2))
		}
		#expect(classification == .comparesValues(
			GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree, rootProbeCount: 1, mockProbeCount: 1, skippedProbeCounts: [.onlyCurrentGenerates: 1]),
			probes: Array(probes.prefix(2)),
		))
	}

	@Test
	func verdict_reportsValuesAgree_whenComparisonFindsNoDifference() {
		let verdict = GraphFuzzerReleaseAcceptance.verdict(GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree), comparing: .success(DifferentialValueComparison(featureDescription: "", knownRightDescription: "", differences: [])))
		#expect(verdict == GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree))
	}

	@Test
	func verdict_reportsValuesDiffer_whenComparisonFindsADifference() {
		let difference = DifferentialValueDifference(probe: "S0_Root0()", path: ["S0_Root0", "t1"], feature: "<2> S0_T1", knownRight: "nil")
		let verdict = GraphFuzzerReleaseAcceptance.verdict(GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree), comparing: .success(DifferentialValueComparison(featureDescription: "", knownRightDescription: "", differences: [difference])))
		#expect(verdict == GraphFuzzerReleaseVerdict(verdictClass: .valuesDiffer, details: difference.description))
	}

	@Test
	func verdict_reportsValuesNotCompared_whenComparatorCannotDescribeAPath() {
		let error = DifferentialValueOracleError(path: .knownRight, stage: .runningProbes, description: "The probe executable crashed.")
		let verdict = GraphFuzzerReleaseAcceptance.verdict(GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree), comparing: .failure(error))
		#expect(verdict == GraphFuzzerReleaseVerdict(verdictClass: .valuesNotCompared, details: "\(error)"))
	}

	// MARK: Annotations

	@Test
	func classify_annotatesNewSourceDiagnostic_whenOnlyCurrentMacrosWarnAboutFixture() {
		let current = GraphFuzzerReleaseRun.compiledRun(stderr: "/scratch/Fixture/S0_T1.swift:4:2: warning: 'customMockName' is deprecated")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(), current: current, probes: Self.noProbes)
		#expect(classification == .comparesValues(GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree, annotations: [.newSourceDiagnostic]), probes: []))
	}

	@Test
	func classify_annotatesNewSourceDiagnostic_whenOnlyCurrentToolWarns() {
		let current = GraphFuzzerReleaseRun(outcome: .compiled(
			generatedFiles: [:],
			toolWarnings: ["<fixture-directory>/S0_T1.swift:4:2: warning: Received property is never read"],
			compilation: GraphFuzzerReleaseCompilation(exitCode: 0, stderr: ""),
		))
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(), current: current, probes: Self.noProbes)
		#expect(classification == .comparesValues(GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree, annotations: [.newSourceDiagnostic]), probes: []))
	}

	@Test
	func classify_annotatesNothing_whenBothToolsReportOneWarningInTheirOwnForms() {
		let message = "This #SafeDIConfiguration sets `mockConditionalCompilation` and is not in a file named `SafeDIConfiguration.swift`, so SafeDI had to scan this module’s files twice."
		let older = GraphFuzzerReleaseRun(outcome: .compiled(generatedFiles: [:], toolWarnings: ["<fixture-directory>/shop/Sources/FuzzFeature/S1_Plain.swift:22:1: warning: \(message)"], compilation: GraphFuzzerReleaseCompilation(exitCode: 0, stderr: "")))
		let current = GraphFuzzerReleaseRun(outcome: .compiled(generatedFiles: [:], toolWarnings: ["SourceDiagnostic(severity: SafeDICore.SourceDiagnostic.Severity.warning, location: nil, message: \"\(message)\", fixIts: [])"], compilation: GraphFuzzerReleaseCompilation(exitCode: 0, stderr: "")))
		let classification = GraphFuzzerReleaseAcceptance.classify(older: older, current: current, probes: Self.noProbes)
		#expect(classification == .comparesValues(GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree), probes: []))
	}

	@Test
	func classify_annotatesSharedGeneratedWarning_whenBothGeneratedCodesDrawTheWarning() {
		let warning = "/scratch/Generated/S0_Root0+SafeDI.swift:12:7: warning: variable 't3' was never mutated"
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .compiledRun(stderr: warning), current: .compiledRun(stderr: warning.replacingOccurrences(of: ":12:", with: ":14:")), probes: Self.noProbes)
		#expect(classification == .comparesValues(GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree, annotations: [.sharedGeneratedWarning]), probes: []))
	}

	// MARK: Values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verdicts_reportNoBreak_whenCurrentTreeIsComparedWithItself() async throws {
		guard compileVerificationIsEnabled else { return }
		let verdicts = try await GraphFuzzerReleaseAcceptance.verdicts(forSeeds: [0, 1, 2, 3], older: .currentTree)
		#expect(verdicts.map(\.seed) == [0, 1, 2, 3])
		#expect(verdicts.allSatisfy { !$0.verdict.verdictClass.isBreak && $0.verdict.verdictClass != .valuesNotCompared }, "\(verdicts)")
		#expect(verdicts.count(where: { $0.verdict.verdictClass == .valuesAgree }) >= 3, "\(verdicts)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verdicts_compareGraphOnItsOwnWithIsolatedBudget_whenItsProbeSpendsTheBatchsTraversals() async throws {
		guard compileVerificationIsEnabled else { return }
		// Seed 0's probes traverse more than one wrapper, so a batch budget of one traversal spends it, and only the
		// comparison on its own under `DifferentialValueLimits.isolatedFuzzerGraph` gives the graph a verdict. Without that
		// second comparison the verdict is class X.
		let verdicts = try await GraphFuzzerReleaseAcceptance.verdicts(
			forSeeds: [0],
			older: .currentTree,
			batchLimits: DifferentialValueLimits(probeTimeLimitInSeconds: 60, traversalsPerProbe: 1),
		)
		#expect(verdicts.map(\.seed) == [0])
		#expect(verdicts.allSatisfy { $0.verdict.verdictClass == .valuesAgree }, "\(verdicts)")
	}

	@Test(arguments: [GraphFuzzerReleaseAcceptanceCorpus.seam, .publicMock])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verdicts_reportNoBreak_whenCurrentTreeIsComparedWithItselfOverGraphsSplitAcrossModules(corpus: GraphFuzzerReleaseAcceptanceCorpus) async throws {
		guard compileVerificationIsEnabled else { return }
		let seeds = Self.splitSeeds[corpus] ?? []
		#expect(seeds.allSatisfy { GraphFuzzerGenerator.releaseAcceptanceFixture(forSeed: $0, features: corpus.features).modules != nil })
		let verdicts = try await GraphFuzzerReleaseAcceptance.verdicts(forSeeds: seeds, of: corpus, older: .currentTree)
		#expect(verdicts.map(\.seed) == seeds)
		#expect(verdicts.allSatisfy { $0.verdict.verdictClass == .valuesAgree }, "\(verdicts)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func verdict_reportsTheOneDifferentValue_whenGeneratedFilesPassAnotherValue() async throws {
		guard compileVerificationIsEnabled else { return }
		let fixture = GraphFuzzerFixture(seed: 9_000, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class S9000_Root0: Instantiable {
				public init(t1: S9000_T1) {
					self.t1 = t1
				}

				@Instantiated let t1: S9000_T1
			}
			""",
			"""
			@Instantiable
			public final class S9000_T1: Instantiable {
				public init(count: Int = 1) {
					self.count = count
				}

				let count: Int
			}
			""",
		])
		func generatedFiles(passingCount count: String) -> [String: String] {
			["S9000_Root0+SafeDI.swift": """
			extension S9000_Root0 {
				public convenience init() {
					let t1 = S9000_T1(\(count))
					self.init(t1: t1)
				}
			}
			"""]
		}
		let older = generatedFiles(passingCount: "")
		let current = generatedFiles(passingCount: "count: 2")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(generatedFiles: older), current: .cleanRun(generatedFiles: current)) {
			fixture.differentialValueProbes(generatedFiles: $0)
		}
		guard case let .comparesValues(verdict, probes) = classification else {
			Issue.record("\(classification)")
			return
		}
		let graph = GraphFuzzerReleaseAcceptance.valueGraph(of: fixture, older: (.currentTree, older), current: (.currentTree, current), probes: probes)
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let comparisons = try #require(try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete))
		let finalVerdict = GraphFuzzerReleaseAcceptance.verdict(verdict, comparing: try #require(comparisons.first).result)
		#expect(finalVerdict == GraphFuzzerReleaseVerdict(
			verdictClass: .valuesDiffer,
			rootProbeCount: 1,
			details: DifferentialValueDifference(probe: "S9000_Root0()", path: ["<1> S9000_Root0", "t1", "count"], feature: "count: Int 2", knownRight: "count: Int 1").description,
		))
	}

	// MARK: Long run

	@Test(.enabled(if: ReleaseAcceptanceLongRunConfiguration.isRequested, "Set SAFEDI_RELEASE_ACCEPTANCE_RELEASE to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_findsNoUnlistedBreak_whenEnabledByEnvironment() async throws {
		let configuration: ReleaseAcceptanceLongRunConfiguration
		switch ReleaseAcceptanceLongRunConfiguration.current {
		case let .success(current):
			configuration = current
		case let .failure(problem):
			// The run was requested, so a missing input fails it rather than skipping it.
			Issue.record(Comment(rawValue: problem.description))
			return
		}
		let report = GraphFuzzerReport(path: configuration.reportPath)
		func reportProblem(_ problem: String) {
			report.append("problem \(problem)")
			Issue.record(Comment(rawValue: problem))
		}
		report.append("release-acceptance release=\(configuration.release.name) current=\(configuration.current.name) draws-every-feature=\(configuration.drawsEveryFeature) corpus=\(configuration.corpus.rawValue) seeds=\(configuration.seeds.lowerBound)..<\(configuration.seeds.upperBound)")
		guard compileVerificationIsEnabled else {
			reportProblem("Release acceptance compiles generated code. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			return
		}
		let start = Date()
		for (index, directory) in configuration.fixtureDirectories.enumerated() {
			report.append("fixture \(index) \(directory)")
		}
		let verdicts = try await GraphFuzzerReleaseAcceptance.verdicts(
			forSeeds: Array(configuration.seeds),
			of: configuration.corpus,
			older: configuration.release,
			current: configuration.current,
			drawsEveryFeature: configuration.drawsEveryFeature,
			fixtureFilesBySeed: configuration.fixtureFilesBySeed,
		)
		let listedSeeds = (Self.listedSeedsByRelease[configuration.release.name] ?? []).filter { $0.corpus == configuration.corpus }
		let listedSeedBySeed = Dictionary(grouping: listedSeeds, by: \.seed).compactMapValues(\.first)
		var classCounts = [GraphFuzzerReleaseAcceptanceClass: Int]()
		var rejectionCounts = [GraphFuzzerReleaseRejection: Int]()
		var annotationCounts = [GraphFuzzerReleaseAnnotation: Int]()
		var skipCounts = [GraphFuzzerReleaseProbeSkip: Int]()
		var rootProbeCount = 0
		var mockProbeCount = 0
		var overrideProbeCount = 0
		var overriddenPlaceCount = 0
		var skippedOverridePlaceCount = 0
		var comparedSeedSum = GraphFuzzerSeedSetSum()
		var comparedSeedCount = 0
		for (seed, verdict) in verdicts {
			classCounts[verdict.verdictClass, default: 0] += 1
			if let rejection = verdict.rejection {
				rejectionCounts[rejection, default: 0] += 1
			}
			for annotation in verdict.annotations {
				annotationCounts[annotation, default: 0] += 1
			}
			for (skip, count) in verdict.skippedProbeCounts {
				skipCounts[skip, default: 0] += count
			}
			rootProbeCount += verdict.rootProbeCount
			mockProbeCount += verdict.mockProbeCount
			overrideProbeCount += verdict.overrideProbeCount
			overriddenPlaceCount += verdict.overriddenPlaceCount
			skippedOverridePlaceCount += verdict.skippedOverridePlaceCount
			if verdict.verdictClass == .valuesAgree || verdict.verdictClass == .valuesDiffer {
				comparedSeedSum.add(seed)
				comparedSeedCount += 1
			}
			var line = "seed \(seed) \(verdict.classDescription)"
			if !verdict.annotations.isEmpty {
				line += " annotations=\(verdict.annotations.sorted().map(\.rawValue).joined(separator: ","))"
			}
			line += " roots=\(verdict.rootProbeCount) mocks=\(verdict.mockProbeCount)"
			if verdict.overrideProbeCount > 0 {
				line += " overrides=\(verdict.overrideProbeCount)/\(verdict.overriddenPlaceCount)"
			}
			if !verdict.skippedProbeCounts.isEmpty {
				line += " skips=\(verdict.skippedProbeCounts.sorted { $0.key < $1.key }.map { "\($0.key.rawValue):\($0.value)" }.joined(separator: ","))"
			}
			report.append(line)
			let listedSeed = listedSeedBySeed[seed]
			if verdict.verdictClass.isBreak || verdict.verdictClass == .valuesNotCompared {
				for detailLine in verdict.details.split(separator: "\n") {
					report.append("    \(detailLine)")
				}
				if let listedSeed, listedSeed.verdictClass == verdict.verdictClass {
					report.append("\(listedSeed.kind.rawValue) \(seed) \(listedSeed.reason)")
				} else {
					let failure = "failure \(seed) \(verdict.verdictClass.rawValue) \(verdict.details.split(separator: "\n").first ?? "")"
					report.append(failure)
					Issue.record(Comment(rawValue: "Seed \(seed) of the \(configuration.corpus.rawValue) corpus's release acceptance against \(configuration.release.name): class \(verdict.verdictClass.rawValue)\n\(verdict.details)"))
				}
			} else if let listedSeed {
				report.append("stale \(seed) \(listedSeed.verdictClass.rawValue) \(listedSeed.reason)")
				Issue.record(Comment(rawValue: "Seed \(seed) is listed as \(listedSeed.kind.rawValue) of class \(listedSeed.verdictClass.rawValue) against \(configuration.release.name), but is class \(verdict.verdictClass.rawValue). Remove it from the list."))
			}
		}
		report.append("classes " + GraphFuzzerReleaseAcceptanceClass.allCases.sorted().map { "\($0.rawValue)=\(classCounts[$0, default: 0])" }.joined(separator: " "))
		report.append("rejections " + GraphFuzzerReleaseRejection.allCases.map { "\($0.rawValue)=\(rejectionCounts[$0, default: 0])" }.joined(separator: " "))
		report.append("annotations " + GraphFuzzerReleaseAnnotation.allCases.map { "\($0.rawValue)=\(annotationCounts[$0, default: 0])" }.joined(separator: " "))
		report.append("probes roots=\(rootProbeCount) mocks=\(mockProbeCount)")
		report.append("overrides probes=\(overrideProbeCount) places=\(overriddenPlaceCount) skipped-places=\(skippedOverridePlaceCount)")
		report.append("skips " + GraphFuzzerReleaseProbeSkip.allCases.map { "\($0.rawValue)=\(skipCounts[$0, default: 0])" }.joined(separator: " "))
		report.append("compared count=\(comparedSeedCount) sum=\(comparedSeedSum.value)")
		report.append("cpu wall=\(Int(Date().timeIntervalSince(start).rounded()))")
		report.append("completed \(verdicts.count)")
		if verdicts.count != configuration.seeds.count {
			reportProblem("Release acceptance judged \(verdicts.count) of \(configuration.seeds.count) seeds.")
		}
	}

	// MARK: Helpers

	/// Seeds of the seam and public mock corpora whose graphs are split across modules and accepted, so that a
	/// self-comparison runs every module's tool, compile and probes.
	private static let splitSeeds: [GraphFuzzerReleaseAcceptanceCorpus: [UInt64]] = [
		.seam: [18, 24],
		.publicMock: [0, 2],
	]

	private static func noProbes(_: [String: String]) -> [DifferentialValueProbe] {
		[]
	}
}

/// The long run's configuration, from the environment `graph-fuzzer.yml`'s release acceptance shards set.
struct ReleaseAcceptanceLongRunConfiguration {
	struct Problem: Error, CustomStringConvertible {
		let description: String
	}

	let release: GraphFuzzerRelease
	/// The release judged against `release`: this tree, or a built `SafeDITool` another branch's head built.
	let current: GraphFuzzerRelease
	/// Whether each graph is drawn with the features 2.3.0 rejects too (`SAFEDI_RELEASE_ACCEPTANCE_DRAWS_EVERY_FEATURE`),
	/// for an older release that accepts them.
	let drawsEveryFeature: Bool
	/// Directories of hand-written fixtures judged in place of the corpus (`SAFEDI_RELEASE_ACCEPTANCE_FIXTURES`, separated
	/// by `:`), each one module of the files its `l.csv` lists or, without one, of every `.swift` file directly in it but
	/// `main.swift` and generated `*.gen.swift` files, judged as seed `<index>`; empty for the corpus.
	let fixtureDirectories: [String]
	let fixtureFilesBySeed: [UInt64: [String]]?
	let corpus: GraphFuzzerReleaseAcceptanceCorpus
	let seeds: Range<UInt64>
	let reportPath: String

	/// Whether the run is requested: `SAFEDI_RELEASE_ACCEPTANCE_RELEASE` names the older release.
	static var isRequested: Bool {
		ProcessInfo.processInfo.environment["SAFEDI_RELEASE_ACCEPTANCE_RELEASE"] != nil
	}

	/// The configuration a requested run reads, or the problem that keeps it from running: `SAFEDI_RELEASE_ACCEPTANCE_TOOL`
	/// (the older release's built `SafeDITool`), `SAFEDI_RELEASE_ACCEPTANCE_MACROS_TOOL` (its `SafeDIMacros-tool`),
	/// `SAFEDI_RELEASE_ACCEPTANCE_RUNTIME_SOURCES` (its `Sources/SafeDI`) and `SAFEDI_RELEASE_ACCEPTANCE_REPORT` must
	/// each be set and exist (the report's directory, for the report); `SAFEDI_RELEASE_ACCEPTANCE_CORPUS`, when set, names
	/// the corpus (`base`, `seam` or `public-mock`; `base` when unset); `SAFEDI_RELEASE_ACCEPTANCE_SHARD`, when set to
	/// `<index>/<count>`, runs only that shard of the corpus's seeds. `SAFEDI_RELEASE_ACCEPTANCE_CURRENT_TOOL`, when set,
	/// judges that built `SafeDITool` in place of this tree, its generated code compiled against
	/// `SAFEDI_RELEASE_ACCEPTANCE_CURRENT_MACROS_TOOL` and `SAFEDI_RELEASE_ACCEPTANCE_CURRENT_RUNTIME_SOURCES`, which must
	/// then be set too, so that a branch's head is judged by its tool alone, whatever test sources it holds.
	static var current: Result<ReleaseAcceptanceLongRunConfiguration, Problem> {
		let environment = ProcessInfo.processInfo.environment
		var problems = [String]()
		func existingPath(_ name: String, isDirectory: Bool = false) -> URL? {
			guard let path = environment[name], !path.isEmpty else {
				problems.append("\(name) is not set.")
				return nil
			}
			var isActuallyDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: path, isDirectory: &isActuallyDirectory), isActuallyDirectory.boolValue == isDirectory else {
				problems.append("\(name) names no \(isDirectory ? "directory" : "file") at \(path).")
				return nil
			}
			return URL(fileURLWithPath: path)
		}
		let name = environment["SAFEDI_RELEASE_ACCEPTANCE_RELEASE"] ?? ""
		if name.isEmpty {
			problems.append("SAFEDI_RELEASE_ACCEPTANCE_RELEASE must name the older release.")
		}
		let tool = existingPath("SAFEDI_RELEASE_ACCEPTANCE_TOOL")
		let macrosTool = existingPath("SAFEDI_RELEASE_ACCEPTANCE_MACROS_TOOL")
		let runtimeSources = existingPath("SAFEDI_RELEASE_ACCEPTANCE_RUNTIME_SOURCES", isDirectory: true)
		let reportPath = environment["SAFEDI_RELEASE_ACCEPTANCE_REPORT"] ?? ""
		if reportPath.isEmpty || !FileManager.default.fileExists(atPath: URL(fileURLWithPath: reportPath).deletingLastPathComponent().path) {
			problems.append("SAFEDI_RELEASE_ACCEPTANCE_REPORT must name a file in a directory that exists.")
		}
		var corpus = GraphFuzzerReleaseAcceptanceCorpus.base
		if let corpusName = environment["SAFEDI_RELEASE_ACCEPTANCE_CORPUS"], !corpusName.isEmpty {
			if let namedCorpus = GraphFuzzerReleaseAcceptanceCorpus(rawValue: corpusName) {
				corpus = namedCorpus
			} else {
				problems.append("SAFEDI_RELEASE_ACCEPTANCE_CORPUS must be one of \(GraphFuzzerReleaseAcceptanceCorpus.allCases.map(\.rawValue).joined(separator: ", ")).")
			}
		}
		let corpusSeedCount = seedCount(of: corpus)
		var seeds = UInt64(0)..<UInt64(corpusSeedCount)
		if let shardDescription = environment["SAFEDI_RELEASE_ACCEPTANCE_SHARD"] {
			let parts = shardDescription.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) }
			if parts.count == 2, let index = parts[0], let count = parts[1], let shard = GraphFuzzerLongRunConfiguration.shard(index, of: count, startingSeed: 0, iterations: corpusSeedCount), shard.iterations > 0 {
				seeds = shard.startingSeed..<(shard.startingSeed + UInt64(shard.iterations))
			} else {
				problems.append("SAFEDI_RELEASE_ACCEPTANCE_SHARD must be `<index>/<count>` naming a shard with at least one seed.")
			}
		}
		var fixtureDirectories = [String]()
		var fixtureFilesBySeed: [UInt64: [String]]?
		if let fixturesDescription = environment["SAFEDI_RELEASE_ACCEPTANCE_FIXTURES"], !fixturesDescription.isEmpty {
			var filesBySeed = [UInt64: [String]]()
			for directory in fixturesDescription.split(separator: ":").map(String.init) {
				// A directory whose `l.csv` lists the files a probe's tool was handed holds those files, by name, beside
				// the probe's own outputs; any other directory holds its fixture's files alone.
				let listedNames = (try? String(contentsOfFile: "\(directory)/l.csv", encoding: .utf8)).map { list in
					list.split(whereSeparator: { $0 == "\n" || $0 == "," }).compactMap { $0.split(separator: "/").last.map(String.init) }
				}
				let names = listedNames ?? ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
					.filter { $0.hasSuffix(".swift") && $0 != "main.swift" && !$0.hasSuffix(".gen.swift") && !$0.hasPrefix(".") }
					.sorted()
				// Each file names itself on its first line (`GraphFuzzerFixture.fileNameMarker`), since a hand-written
				// file need not spell its first type's `@Instantiable` on a line of its own, by which the harness names one.
				let files = names.compactMap { name in
					(try? String(contentsOfFile: "\(directory)/\(name)", encoding: .utf8)).map { GraphFuzzerFixture.fileNameMarker + name + "\n" + $0 }
				}
				guard !files.isEmpty, files.count == names.count else {
					problems.append("SAFEDI_RELEASE_ACCEPTANCE_FIXTURES names \(directory), which holds no readable fixture file.")
					continue
				}
				filesBySeed[UInt64(fixtureDirectories.count)] = files
				fixtureDirectories.append(directory)
			}
			fixtureFilesBySeed = filesBySeed
			seeds = 0..<UInt64(fixtureDirectories.count)
		}
		var current = GraphFuzzerRelease.currentTree
		if environment["SAFEDI_RELEASE_ACCEPTANCE_CURRENT_TOOL"] != nil {
			if let currentTool = existingPath("SAFEDI_RELEASE_ACCEPTANCE_CURRENT_TOOL"),
			   let currentMacrosTool = existingPath("SAFEDI_RELEASE_ACCEPTANCE_CURRENT_MACROS_TOOL"),
			   let currentRuntimeSources = existingPath("SAFEDI_RELEASE_ACCEPTANCE_CURRENT_RUNTIME_SOURCES", isDirectory: true)
			{
				current = GraphFuzzerRelease(
					name: environment["SAFEDI_RELEASE_ACCEPTANCE_CURRENT_NAME"] ?? currentTool.path,
					tool: .executable(currentTool),
					runtimeSource: DifferentialValueRuntimeSource(runtimeSourcesDirectory: currentRuntimeSources, macrosToolPath: currentMacrosTool),
				)
			}
		}
		guard problems.isEmpty, let tool, let macrosTool, let runtimeSources else {
			return .failure(Problem(description: problems.joined(separator: "\n")))
		}
		return .success(ReleaseAcceptanceLongRunConfiguration(
			release: GraphFuzzerRelease(
				name: name,
				tool: .executable(tool),
				runtimeSource: DifferentialValueRuntimeSource(runtimeSourcesDirectory: runtimeSources, macrosToolPath: macrosTool),
			),
			current: current,
			drawsEveryFeature: environment["SAFEDI_RELEASE_ACCEPTANCE_DRAWS_EVERY_FEATURE"] == "1",
			fixtureDirectories: fixtureDirectories,
			fixtureFilesBySeed: fixtureFilesBySeed,
			corpus: corpus,
			seeds: seeds,
			reportPath: reportPath,
		))
	}

	/// The number of seeds of `corpus`, as the graph fuzzer's long run judges it.
	static func seedCount(of corpus: GraphFuzzerReleaseAcceptanceCorpus) -> Int {
		switch corpus {
		case .base:
			SafeDIToolGraphFuzzerTests.corpusSeedCount
		case .seam:
			SafeDIToolGraphFuzzerTests.seamCorpusSeedCount
		case .publicMock:
			SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount
		}
	}
}

extension GraphFuzzerReleaseRun {
	/// A run whose tool reported an error.
	fileprivate static let rejectedRun = GraphFuzzerReleaseRun(outcome: .rejected(diagnostics: "error: Dependency cycle detected"))

	/// A run whose tool accepted the graph and whose compile reported nothing.
	fileprivate static func cleanRun(generatedFiles: [String: String] = [:]) -> GraphFuzzerReleaseRun {
		compiledRun(generatedFiles: generatedFiles, stderr: "")
	}

	/// A run whose tool accepted the graph and whose compile reported `stderr`.
	fileprivate static func compiledRun(generatedFiles: [String: String] = [:], exitCode: Int32 = 0, stderr: String) -> GraphFuzzerReleaseRun {
		GraphFuzzerReleaseRun(outcome: .compiled(generatedFiles: generatedFiles, toolWarnings: [], compilation: GraphFuzzerReleaseCompilation(exitCode: exitCode, stderr: stderr)))
	}
}
