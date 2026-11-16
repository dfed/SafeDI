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
		}

		let seed: UInt64
		let kind: Kind
		let verdictClass: GraphFuzzerReleaseAcceptanceClass
		let reason: String
	}

	/// #649: an instantiator received only if available inside its own loop of instantiators is that instantiator,
	/// where 2.2.0 passed `nil`, and each receiver holds a wrapper of its own.
	static let releaseNotedLoopOfInstantiatorsReason = "#649, a release-noted behavior change"

	/// #649's second commit: an instantiator received only if available inside a `@Sendable` builder's loop, which
	/// 2.2.0 passed `nil` and the same receive outside a loop was already an error.
	static let releaseNotedSendableLoopReceiveReason = "#649, a release-noted rejection"

	/// #593 and #597: a label received in two forms along one branch of a mock's tree, either required, which no
	/// production tree builds or where production always passes `nil` and 2.2.0's mock passed a built value.
	static let releaseNotedHiddenReceiveInMockTreeReason = "#593/#597, a release-noted rejection of a mock production cannot build"

	/// #718: seeds whose 2.2.0 mock compiled with production's `nil` defaults plus an override, which this tree rejects
	/// as a receive hidden in the mock's tree: kept in 2.3.0 by the maintainer's ruling, to be fixed in 2.3.1.
	static let mockAlwaysNilReceiveRejectionReason = "#718, kept in 2.3.0 by ruling; fixed in 2.3.1"

	/// #533: a type a lazy cycle builds again receives each property from the nearest declaration above it, where 2.2.0
	/// passed the declaration above the cycle, or `nil`.
	static let nearestDeclarationInLazyCycleReason = "#533, a 2.2.0 defect fixed and release-noted"

	/// #571: a type built inside a dependency it receives, beneath a type forwarding that dependency, is passed the
	/// forwarded value, where 2.2.0 passed `nil` to a receive only if available.
	static let forwardedValueInCycleReason = "#571, a 2.2.0 defect fixed and release-noted"

	/// #572: a receive only if available of an instantiator its builder's own scope declares is passed that instantiator
	/// at every depth of the cycle, where 2.2.0 passed `nil` below the first.
	static let instantiatorAtEveryDepthReason = "#572, a 2.2.0 defect fixed and release-noted"

	/// The seeds of the base corpus whose break from each older release is expected, by the release's name. A seed of
	/// another class, or one that no longer breaks, fails the run as stale. Each is attributed, never listed to make a
	/// run pass. 2.2.0's #649 seeds are the graphs whose values differ and whose generated code shows a loop through
	/// received instantiators (`GraphFuzzerFeature.buildersReceivingEachOther` and its siblings, read from this tree's
	/// output), where 2.2.0 passed `nil` or shared one wrapper among the loop's receivers. Each other 2.2.0 seed was
	/// reduced and bisected to the pull request its reason names, whose change was ruled a fix of 2.2.0's behavior.
	static let listedSeedsByRelease: [String: [ListedSeed]] = [
		"2.2.0": [
			ListedSeed(seed: 1, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 107, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 114, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 257, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 294, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 371, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 450, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 496, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 604, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 626, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 653, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 662, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 672, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 710, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 715, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 760, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 774, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 824, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 871, kind: .knownBreak, verdictClass: .currentRejects, reason: mockAlwaysNilReceiveRejectionReason),
			ListedSeed(seed: 892, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 897, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 957, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 963, kind: .knownBreak, verdictClass: .currentRejects, reason: releaseNotedHiddenReceiveInMockTreeReason),
			ListedSeed(seed: 1_005, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_015, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_021, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_025, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_042, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_056, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_095, kind: .knownBreak, verdictClass: .currentRejects, reason: mockAlwaysNilReceiveRejectionReason),
			ListedSeed(seed: 1_117, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_138, kind: .knownBreak, verdictClass: .currentRejects, reason: mockAlwaysNilReceiveRejectionReason),
			ListedSeed(seed: 1_142, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_178, kind: .knownBreak, verdictClass: .currentRejects, reason: releaseNotedSendableLoopReceiveReason),
			ListedSeed(seed: 1_225, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 1_328, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_379, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_393, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_406, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_473, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_477, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_525, kind: .knownBreak, verdictClass: .currentRejects, reason: mockAlwaysNilReceiveRejectionReason),
			ListedSeed(seed: 1_545, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_548, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_553, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_571, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_717, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_738, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 1_742, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 1_812, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_837, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_853, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_902, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_943, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 1_995, kind: .knownBreak, verdictClass: .currentRejects, reason: releaseNotedHiddenReceiveInMockTreeReason),
			ListedSeed(seed: 2_129, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_155, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_229, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_258, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_325, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_348, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 2_444, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_467, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_475, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_483, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_514, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 2_590, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_598, kind: .knownBreak, verdictClass: .currentRejects, reason: mockAlwaysNilReceiveRejectionReason),
			ListedSeed(seed: 2_655, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_739, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_754, kind: .knownBreak, verdictClass: .currentRejects, reason: mockAlwaysNilReceiveRejectionReason),
			ListedSeed(seed: 2_773, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 2_775, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 2_783, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_794, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_937, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 2_983, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_025, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_048, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_113, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_142, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_239, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_267, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_487, kind: .knownBreak, verdictClass: .valuesDiffer, reason: forwardedValueInCycleReason),
			ListedSeed(seed: 3_563, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_599, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_641, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_687, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_719, kind: .knownBreak, verdictClass: .currentRejects, reason: releaseNotedHiddenReceiveInMockTreeReason),
			ListedSeed(seed: 3_843, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_868, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_907, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_924, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_957, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 3_985, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_044, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_056, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_147, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_257, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_279, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_297, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_311, kind: .knownBreak, verdictClass: .currentRejects, reason: mockAlwaysNilReceiveRejectionReason),
			ListedSeed(seed: 4_424, kind: .knownBreak, verdictClass: .currentRejects, reason: releaseNotedHiddenReceiveInMockTreeReason),
			ListedSeed(seed: 4_515, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_530, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_538, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_550, kind: .knownBreak, verdictClass: .currentRejects, reason: releaseNotedHiddenReceiveInMockTreeReason),
			ListedSeed(seed: 4_628, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_662, kind: .knownBreak, verdictClass: .valuesDiffer, reason: nearestDeclarationInLazyCycleReason),
			ListedSeed(seed: 4_692, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_749, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_803, kind: .knownBreak, verdictClass: .valuesDiffer, reason: releaseNotedLoopOfInstantiatorsReason),
			ListedSeed(seed: 4_990, kind: .knownBreak, verdictClass: .valuesDiffer, reason: instantiatorAtEveryDepthReason),
		],
	]

	@Test
	func listedSeeds_listEachSeedOnceAsABreak_forEachRelease() {
		for (release, listedSeeds) in Self.listedSeedsByRelease {
			let seeds = listedSeeds.map(\.seed)
			#expect(seeds == seeds.sorted(), "\(release)")
			#expect(Set(seeds).count == seeds.count, "\(release)")
			#expect(listedSeeds.allSatisfy { $0.verdictClass.isBreak && $0.seed < UInt64(SafeDIToolGraphFuzzerTests.corpusSeedCount) }, "\(release)")
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
		#expect(classification == .decided(GraphFuzzerReleaseVerdict(verdictClass: .currentDrawsNewGeneratedWarning, details: "initialization of immutable value 't7Builder' was never used")))
	}

	@Test
	func classify_reportsCurrentDrawsNewGeneratedWarning_whenWarningIsAtFixtureLineASourceLocationDirectiveAttributesGeneratedCodeTo() {
		let current = GraphFuzzerReleaseRun.compiledRun(stderr: "/scratch/SourceLocation/S0_T1.swift:6:3: warning: variable 't3' was never mutated")
		let classification = GraphFuzzerReleaseAcceptance.classify(older: .cleanRun(), current: current, probes: Self.noProbes)
		#expect(classification == .decided(GraphFuzzerReleaseVerdict(verdictClass: .currentDrawsNewGeneratedWarning, details: "variable 't3' was never mutated")))
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
		report.append("release-acceptance release=\(configuration.release.name) seeds=\(configuration.seeds.lowerBound)..<\(configuration.seeds.upperBound)")
		guard compileVerificationIsEnabled else {
			reportProblem("Release acceptance compiles generated code. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			return
		}
		let start = Date()
		let verdicts = try await GraphFuzzerReleaseAcceptance.verdicts(forSeeds: Array(configuration.seeds), older: configuration.release)
		let listedSeeds = Self.listedSeedsByRelease[configuration.release.name] ?? []
		let listedSeedBySeed = Dictionary(grouping: listedSeeds, by: \.seed).compactMapValues(\.first)
		var classCounts = [GraphFuzzerReleaseAcceptanceClass: Int]()
		var rejectionCounts = [GraphFuzzerReleaseRejection: Int]()
		var annotationCounts = [GraphFuzzerReleaseAnnotation: Int]()
		var skipCounts = [GraphFuzzerReleaseProbeSkip: Int]()
		var rootProbeCount = 0
		var mockProbeCount = 0
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
			if verdict.verdictClass == .valuesAgree || verdict.verdictClass == .valuesDiffer {
				comparedSeedSum.add(seed)
				comparedSeedCount += 1
			}
			var line = "seed \(seed) \(verdict.classDescription)"
			if !verdict.annotations.isEmpty {
				line += " annotations=\(verdict.annotations.sorted().map(\.rawValue).joined(separator: ","))"
			}
			line += " roots=\(verdict.rootProbeCount) mocks=\(verdict.mockProbeCount)"
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
					Issue.record(Comment(rawValue: "Seed \(seed) of release acceptance against \(configuration.release.name): class \(verdict.verdictClass.rawValue)\n\(verdict.details)"))
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
		report.append("skips " + GraphFuzzerReleaseProbeSkip.allCases.map { "\($0.rawValue)=\(skipCounts[$0, default: 0])" }.joined(separator: " "))
		report.append("compared count=\(comparedSeedCount) sum=\(comparedSeedSum.value)")
		report.append("cpu wall=\(Int(Date().timeIntervalSince(start).rounded()))")
		report.append("completed \(verdicts.count)")
		if verdicts.count != configuration.seeds.count {
			reportProblem("Release acceptance judged \(verdicts.count) of \(configuration.seeds.count) seeds.")
		}
	}

	// MARK: Helpers

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
	let seeds: Range<UInt64>
	let reportPath: String

	/// Whether the run is requested: `SAFEDI_RELEASE_ACCEPTANCE_RELEASE` names the older release.
	static var isRequested: Bool {
		ProcessInfo.processInfo.environment["SAFEDI_RELEASE_ACCEPTANCE_RELEASE"] != nil
	}

	/// The configuration a requested run reads, or the problem that keeps it from running: `SAFEDI_RELEASE_ACCEPTANCE_TOOL`
	/// (the older release's built `SafeDITool`), `SAFEDI_RELEASE_ACCEPTANCE_MACROS_TOOL` (its `SafeDIMacros-tool`),
	/// `SAFEDI_RELEASE_ACCEPTANCE_RUNTIME_SOURCES` (its `Sources/SafeDI`) and `SAFEDI_RELEASE_ACCEPTANCE_REPORT` must
	/// each be set and exist (the report's directory, for the report); `SAFEDI_RELEASE_ACCEPTANCE_SHARD`, when set to
	/// `<index>/<count>`, runs only that shard of the base corpus's seeds.
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
		let corpusSeedCount = SafeDIToolGraphFuzzerTests.corpusSeedCount
		// Local exploration beyond the corpus: SAFEDI_RELEASE_ACCEPTANCE_START and _COUNT.
		let explorationStart = environment["SAFEDI_RELEASE_ACCEPTANCE_START"].flatMap { Int($0) } ?? 0
		let explorationCount = environment["SAFEDI_RELEASE_ACCEPTANCE_COUNT"].flatMap { Int($0) } ?? corpusSeedCount
		var seeds = UInt64(explorationStart)..<UInt64(explorationStart + explorationCount)
		if let shardDescription = environment["SAFEDI_RELEASE_ACCEPTANCE_SHARD"] {
			let parts = shardDescription.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) }
			if parts.count == 2, let index = parts[0], let count = parts[1], let shard = GraphFuzzerLongRunConfiguration.shard(index, of: count, startingSeed: UInt64(explorationStart), iterations: explorationCount), shard.iterations > 0 {
				seeds = shard.startingSeed..<(shard.startingSeed + UInt64(shard.iterations))
			} else {
				problems.append("SAFEDI_RELEASE_ACCEPTANCE_SHARD must be `<index>/<count>` naming a shard with at least one seed.")
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
			seeds: seeds,
			reportPath: reportPath,
		))
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
