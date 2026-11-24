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

struct SafeDIToolBaseValueComparisonTests {
	// MARK: Comparing one tool with itself

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func prepare_findsByteIdenticalGraphs_whenBaseAndHeadAreOneTool() async throws {
		let tool = try GraphFuzzerBaseComparison.builtTool()
		var outcomes = [GraphFuzzerBaseValueComparison.Outcome]()
		for (features, seeds) in Self.graphsOfEveryCorpus {
			for seed in seeds {
				switch try await GraphFuzzerBaseValueComparison.prepare(GraphFuzzerGenerator.fixture(forSeed: seed, features: features), base: tool, head: tool) {
				case let .ended(verdict):
					outcomes.append(verdict.outcome)
				case let .pending(pending):
					Issue.record("Seed \(pending.seed) was left to compare by value, though one tool generated its code twice.")
				}
			}
		}
		#expect(outcomes.contains(.byteIdentical))
		#expect(outcomes.allSatisfy { outcome in
			switch outcome {
			case .byteIdentical, .skipped(.rejectedByBoth), .skipped(.mirrorModelDisagrees), .skipped(.valueOracleFixtureRejected):
				true
			case .matchingValues, .skipped, .finding:
				false
			}
		})
	}

	// MARK: Comparing two tools

	/// A head whose mocks ignore every override – a builder a shared builder function is handed in place of the one its
	/// place passes – builds other values than the base where the value oracle passes an override.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compare_reportsValueDifference_whenHeadMocksIgnoreTheirOverrides() async throws {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let tool = try GraphFuzzerBaseComparison.builtTool()
		let head = try Self.mutatingTool(
			tool,
			sedExpression: "s/if let safeDIBuilder = safeDIOverrides/if false, let safeDIBuilder = safeDIOverrides/g",
			filesToDelete: &filesToDelete,
		)
		// Seed 1's value oracle passes `S1_Root0.mock()` an override of `t0`, which the base builds and the head ignores.
		let verdicts = try await Self.verdicts(ofSeeds: [1], features: [], base: tool, head: head)
		#expect(verdicts.map(\.outcome) == [
			.finding(.valueDifference(
				first: "probe `S1_Root0.mock(safeDIOverrides: .init(t0: sentinel))` at (S1_Root0, Optional<Any>) > .1: base `.1: <4> S1_T0 (seen, first at (S1_Root0, Optional<Any>) > .0 > t0)`, head `.1: nil`",
				count: 1,
			)),
		])
	}

	// MARK: Outcomes

	@Test
	func outcome_isMatchingValues_whenComparisonHasNoDifference() {
		let comparison = DifferentialValueComparison(featureDescription: "a", knownRightDescription: "a", differences: [])
		#expect(GraphFuzzerBaseValueComparison.outcome(of: .success(comparison)) == .matchingValues)
	}

	@Test
	func outcome_namesFirstDifferenceAndCount_whenHeadBuildsOtherValues() {
		let comparison = DifferentialValueComparison(featureDescription: "", knownRightDescription: "", differences: [
			DifferentialValueDifference(probe: "S1_A.mock()", path: ["(value)", "b"], feature: "<2> S1_B", knownRight: "<1> S1_B (seen)"),
			DifferentialValueDifference(probe: "S1_A.mock()", path: ["(value)", "c"], feature: "nil", knownRight: "<3> S1_C"),
		])
		#expect(GraphFuzzerBaseValueComparison.outcome(of: .success(comparison)) == .finding(.valueDifference(
			first: "probe `S1_A.mock()` at (value) > b: base `<1> S1_B (seen)`, head `<2> S1_B`",
			count: 2,
		)))
	}

	@Test
	func outcome_isFinding_whenHeadAloneIsNotDescribed() {
		let error = DifferentialValueOracleError(path: .feature, stage: .compilingModule("App"), description: "error: cannot find 'x'\nmore")
		#expect(GraphFuzzerBaseValueComparison.outcome(of: .failure(error)) == .finding(.headNotDescribed("error: cannot find 'x'\nmore")))
		#expect(GraphFuzzerBaseValueComparison.Finding.headNotDescribed("error: cannot find 'x'\nmore").description == "head not described: error: cannot find 'x'")
	}

	@Test
	func outcome_isSkipped_whenBaseIsNotDescribedOrBothSpendTheirTraversals() {
		let baseError = DifferentialValueOracleError(path: .knownRight, stage: .runningProbes, description: "trap")
		var spent = DifferentialValueOracleError(path: nil, stage: .runningProbes, description: "spent")
		spent.spentTraversals = true
		#expect(GraphFuzzerBaseValueComparison.outcome(of: .failure(baseError)) == .skipped(.baseNotDescribed))
		#expect(GraphFuzzerBaseValueComparison.outcome(of: .failure(spent)) == .skipped(.traversalsSpent))
	}

	@Test
	func counts_reportEachOutcome_inOneSummaryLine() {
		let counts = GraphFuzzerBaseValueComparison.Counts([
			.init(seed: 3, outcome: .matchingValues),
			.init(seed: 1, outcome: .byteIdentical),
			.init(seed: 2, outcome: .skipped(.rejectedByBoth)),
			.init(seed: 4, outcome: .finding(.valueDifference(first: "x", count: 2))),
			.init(seed: 5, outcome: .finding(.acceptanceDiffers(base: true, head: false, fixture: "graph"))),
		])
		#expect(counts.summary == "graphs=5 byte-identical=1 compared-by-value=2 matching-values=1 findings=2 skip.argumentProblem=0 skip.rejectedByBoth=1 skip.mirrorModelDisagrees=0 skip.valueOracleFixtureRejected=0 skip.noProbe=0 skip.baseNotDescribed=0 skip.traversalsSpent=0 skip.compileVerificationDisabled=0")
		#expect(counts.findings.map { "\($0.seed) \($0.finding)" } == ["4 value x (2 in all)", "5 acceptance of the graph: base accepts, head rejects"])
	}

	// MARK: Long run

	@Test(.enabled(if: BaseComparisonLongRunConfiguration.isRequested(environmentPrefix: Self.environmentPrefix), "Set SAFEDI_BASE_VALUE_COMPARISON_BASE_TOOL to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_reportsEveryValueDifference_whenEnabledByEnvironment() async throws {
		let configuration: BaseComparisonLongRunConfiguration
		switch BaseComparisonLongRunConfiguration.current(environmentPrefix: Self.environmentPrefix) {
		case let .success(current):
			configuration = current
		case let .failure(problem):
			// The run was requested, so a missing input fails it rather than skipping it.
			Issue.record(Comment(rawValue: problem.description))
			return
		}
		let report = GraphFuzzerReport(path: configuration.reportPath)
		report.append("base-value-comparison corpus=\(configuration.corpusName) seeds=\(configuration.seeds.lowerBound)..<\(configuration.seeds.upperBound) corpus-seeds=\(configuration.corpusSeedCount)")
		let start = Date()
		let verdicts = try await Self.verdicts(ofSeeds: Array(configuration.seeds), features: configuration.features, base: configuration.baseTool, head: configuration.headTool)
		let counts = GraphFuzzerBaseValueComparison.Counts(verdicts)
		for (seed, finding) in counts.findings {
			report.append("finding \(seed) \(finding)")
			Issue.record("Seed \(seed) of the \(configuration.corpusName) corpus: \(finding)")
		}
		report.append("summary \(counts.summary)")
		report.append("cpu wall=\(Int(Date().timeIntervalSince(start).rounded()))")
		report.append("completed \(verdicts.count)")
		#expect(verdicts.count == configuration.seeds.count)
	}

	// MARK: Helpers

	private static let environmentPrefix = "SAFEDI_BASE_VALUE_COMPARISON"

	/// Graphs of the base, seam and public mock corpora, accepted and rejected.
	private static let graphsOfEveryCorpus: [(features: Set<GraphFuzzerGeneratorFeature>, seeds: [UInt64])] = [
		([], [0, 1]),
		([.generateDependencyTree], [0]),
		([.generateMockPublic], [0]),
	]

	/// Every seed's verdict, in seed order: each graph runs through both tools, a few graphs side by side, and the graphs
	/// whose code differs are compared by value in batches.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func verdicts(ofSeeds seeds: [UInt64], features: Set<GraphFuzzerGeneratorFeature>, base: URL, head: URL) async throws -> [GraphFuzzerBaseValueComparison.Verdict] {
		let concurrentGraphCount = ProcessInfo.processInfo.activeProcessorCount * 2
		var verdicts = [GraphFuzzerBaseValueComparison.Verdict]()
		var pending = [GraphFuzzerBaseValueComparison.PendingComparison]()
		try await withThrowingTaskGroup(of: GraphFuzzerBaseValueComparison.Either.self) { group in
			var pendingSeeds = Array(seeds.reversed())
			var inFlightCount = 0
			while inFlightCount > 0 || !pendingSeeds.isEmpty {
				while inFlightCount < concurrentGraphCount, let seed = pendingSeeds.popLast() {
					inFlightCount += 1
					group.addTask {
						try await GraphFuzzerBaseValueComparison.prepare(GraphFuzzerGenerator.fixture(forSeed: seed, features: features), base: base, head: head)
					}
				}
				switch try await group.next() {
				case let .ended(verdict):
					verdicts.append(verdict)
				case let .pending(comparison):
					pending.append(comparison)
				case nil:
					break
				}
				inFlightCount -= 1
			}
		}
		pending.sort { $0.seed < $1.seed }
		verdicts += try await GraphFuzzerBaseValueComparison.compare(pending)
		return verdicts.sorted { $0.seed < $1.seed }
	}

	/// An executable shell script that runs `tool` and then edits every Swift file the run wrote with `sedExpression`.
	private static func mutatingTool(_ tool: URL, sedExpression: String, filesToDelete: inout [URL]) throws -> URL {
		let file = TestTemporaryDirectory.uniquePath(prefix: "safedi-base-value-comparison-tool-", pathExtension: "sh")
		filesToDelete.append(file)
		try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		// The plugin flow's `generate` writes into `Output` beside the manifest
		// (`GraphFuzzerBaseComparison.Layout`); the module-info flow names its combined output. `sed` writes a copy, since
		// BSD's and GNU's `sed -i` take their arguments differently.
		let body = """
		#!/bin/sh
		"\(tool.path)" "$@" || exit $?
		output=""
		previous=""
		for argument in "$@"; do
			if [ "$previous" = "--combined-output" ]; then output="$argument"; fi
			if [ "$previous" = "--swift-manifest" ]; then output="$(dirname "$argument")/Output"; fi
			previous="$argument"
		done
		[ -n "$output" ] || exit 0
		for file in $(find "$output" -name '*.swift'); do
			sed -e '\(sedExpression)' "$file" > "$file.edited" && mv "$file.edited" "$file"
		done

		"""
		try body.write(to: file, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
		return file
	}
}
