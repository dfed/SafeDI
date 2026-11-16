import Foundation
import Testing

@testable import SafeDIToolTestSupport

/// Local exploration only: prints, for each seed in SAFEDI_EXPLORE_LOOP_SEEDS, whether this tree's generated code for
/// the release acceptance fixture shows a loop through received instantiators (#649's signature).
struct ExplorationLoopFeatureTests {
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_LOOP_SEEDS"] != nil))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func printLoopFeatures() async throws {
		let seeds = (ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_LOOP_SEEDS"] ?? "").split(separator: ",").compactMap { UInt64($0) }
		let loopFeatures: Set<GraphFuzzerFeature> = [.buildersReceivingEachOther, .sendableBuildersReceivingEachOther, .builderReceivedInsideItsTree, .sendableBuilderReceivedInsideItsTree, .receivedLoopMemberWithCycleParameters, .sendableReceivedLoopMemberWithCycleParameters]
		var lines = [String]()
		for seed in seeds {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, storingEveryParameter: true)
			let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
			let found = GraphFuzzerFeature.features(of: fixture, outcome: outcome).intersection(loopFeatures).map { "\($0)" }.sorted()
			lines.append("loop \(seed) \(found.joined(separator: ","))")
		}
		try lines.joined(separator: "\n").write(toFile: ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_LOOP_REPORT"] ?? "/dev/stdout", atomically: false, encoding: .utf8)
	}
}
