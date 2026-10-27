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

/// Random dependency graphs, run through SafeDITool and the compiler. See "Graph fuzzer" in CLAUDE.md.
struct SafeDIToolGraphFuzzerTests {
	// MARK: Smoke batch

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_produceNoFailures_whenRunThroughToolAndCompiler() async throws {
		for result in try await smokeResults.value {
			if let failure = result.failure {
				Issue.record(failure.issueComment(fixture: result.fixture))
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_exerciseEveryFeature_inGraphsTheToolAccepts() async throws {
		// Features are read from the emitted source, so a generator that stops emitting one fails here.
		let features = try await smokeResults.value
			.filter { $0.isAccepted && $0.failure == nil }
			.reduce(into: Set<GraphFuzzerFeature>()) { $0.formUnion(GraphFuzzerFeature.features(of: $1.fixture)) }
		#expect(Set(GraphFuzzerFeature.allCases).subtracting(features).sorted() == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_includeAcceptedAndRejectedGraphs_whenRunThroughTool() async throws {
		let results = try await smokeResults.value
		let acceptedCount = results.count(where: { $0.isAccepted && $0.failure == nil })
		let rejectedCount = results.count(where: { !$0.isAccepted && $0.failure == nil })
		// Enough of both that a generator change which makes nearly every graph valid, or nearly every graph
		// invalid, fails here rather than quietly testing less.
		#expect(acceptedCount >= Self.smokeSeeds.count / 4, "Accepted \(acceptedCount) of \(Self.smokeSeeds.count) graphs")
		#expect(rejectedCount >= Self.smokeSeeds.count / 4, "Rejected \(rejectedCount) of \(Self.smokeSeeds.count) graphs")
	}

	// MARK: Known issues

	@Test(.enabled(if: compileVerificationIsEnabled, "Known issues are generated code that does not compile"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func knownIssueSeeds_stillFail_whenRunThroughToolAndCompiler() async throws {
		// One seed of each shape keeps the cost to a couple of compiler invocations; the long run checks the rest.
		let results = try await GraphFuzzerOracle.results(forSeeds: Self.knownIssues.map(\.seeds[0]))
		for (knownIssue, result) in zip(Self.knownIssues, results) {
			withKnownIssue("Seed \(result.fixture.seed): \(knownIssue.reason)") {
				if let failure = result.failure {
					Issue.record(failure.issueComment(fixture: result.fixture))
				}
			} matching: { issue in
				issue.isGraphFuzzerFailure(ofKind: .generatedCodeDoesNotCompile)
			}
		}
	}

	// MARK: Oracle sensitivity

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportEachBrokenGraph_whenGeneratedCodeFailsToTypeCheckOrToLower() async throws {
		let seeds = try await acceptedSmokeSeeds(count: 3)
		var toolRuns = [GraphFuzzerToolRuns]()
		for seed in seeds {
			try await toolRuns.append(GraphFuzzerOracle.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed)))
		}
		let prefix = { (seed: UInt64) in GraphFuzzerFixture.typeNamePrefix(forSeed: seed) }
		// A type error, which the type checker reports.
		toolRuns[1] = toolRuns[1].addingGeneratedFile(
			named: "\(prefix(seeds[1]))Broken.swift",
			contents: "func \(prefix(seeds[1]))broken() -> Int { \"not an integer\" }\n",
		)
		// A closure that captures a local declared after it, which only lowering to SIL reports, and which a type
		// error elsewhere in the same compilation would hide.
		toolRuns[2] = toolRuns[2].addingGeneratedFile(
			named: "\(prefix(seeds[2]))Broken.swift",
			contents: """
			func \(prefix(seeds[2]))broken() -> Int {
				func read() -> Int { value }
				let value = read()
				return value
			}

			""",
		)

		let failures = try GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [seeds[1], seeds[2]])
		#expect(failures[seeds[1]]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[seeds[2]]?.kind == .generatedCodeDoesNotCompile)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func runsDifferFailure_isReported_whenTwoRunsProduceDifferentOutput() async throws {
		let seed = try await acceptedSmokeSeeds(count: 1)[0]
		let runs = try await GraphFuzzerOracle.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed))
		let differingRuns = GraphFuzzerToolRuns(
			fixture: runs.fixture,
			firstOutcome: runs.firstOutcome,
			secondOutcome: runs.addingGeneratedFile(named: "Extra.swift", contents: "\n").firstOutcome,
		)

		#expect(runs.runsDifferFailure == nil)
		#expect(differingRuns.runsDifferFailure?.kind == .runsDiffer)
	}

	// MARK: Reproducibility

	@Test
	func randomNumberGenerator_producesSplitMix64ReferenceSequence_forSeedZero() {
		var random = GraphFuzzerRandomNumberGenerator(seed: 0)
		#expect([random.next(), random.next(), random.next()] == [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F])
	}

	@Test
	func fixture_matchesReferenceHash_forSmokeSeeds() {
		// Every platform must generate the same graph for a seed, or a seed reported by the scheduled run would
		// not reproduce elsewhere. Changing the generator changes this hash, and changes which graph every seed
		// names, so re-derive the known issues' seeds when it changes.
		var hash: UInt64 = 0xCBF29CE484222325
		for fixture in Self.smokeSeeds.map(GraphFuzzerGenerator.fixture(forSeed:)) {
			for byte in fixture.description.utf8 {
				hash = (hash ^ UInt64(byte)) &* 0x00000100000001B3
			}
		}
		#expect(hash == Self.smokeFixtureHash)
	}

	// MARK: Long run

	@Test(.enabled(if: GraphFuzzerLongRunConfiguration.current != nil, "Set SAFEDI_GRAPH_FUZZER_ITERATIONS to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_findsNoUnknownFailures_whenEnabledByEnvironment() async throws {
		let configuration = try #require(GraphFuzzerLongRunConfiguration.current)
		let report = GraphFuzzerReport(path: configuration.reportPath)
		guard compileVerificationIsEnabled else {
			Issue.record("The graph fuzzer checks generated code by compiling it. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			return
		}
		guard configuration.iterations > 0 else {
			Issue.record("SAFEDI_GRAPH_FUZZER_ITERATIONS must be a positive integer.")
			return
		}
		let knownIssuesBySeed = Dictionary(uniqueKeysWithValues: Self.knownIssues.flatMap { knownIssue in
			knownIssue.seeds.map { ($0, knownIssue) }
		})
		var graphCount = 0
		var acceptedCount = 0
		var failureCount = 0
		for batchStart in stride(from: 0, to: configuration.iterations, by: Self.longRunBatchSize) {
			let seeds = (batchStart..<min(batchStart + Self.longRunBatchSize, configuration.iterations))
				.map { configuration.startingSeed &+ UInt64($0) }
			let results = try await GraphFuzzerOracle.results(forSeeds: seeds) { seed in
				report.append("seed \(seed)")
			}
			graphCount += results.count
			acceptedCount += results.count(where: \.isAccepted)
			for result in results {
				if let knownIssue = knownIssuesBySeed[result.fixture.seed] {
					report.append("\(result.failure == nil ? "stale" : "known") \(result.fixture.seed) \(knownIssue.reason)")
					withKnownIssue("Seed \(result.fixture.seed): \(knownIssue.reason)") {
						if let failure = result.failure {
							Issue.record(failure.issueComment(fixture: result.fixture))
						}
					} matching: { issue in
						issue.isGraphFuzzerFailure(ofKind: .generatedCodeDoesNotCompile)
					}
				} else if let failure = result.failure {
					failureCount += 1
					report.append("failure \(failure.seed) \(failure.kind.rawValue)")
					Issue.record(failure.issueComment(fixture: result.fixture))
				}
			}
		}
		report.append("completed \(graphCount) graphs, \(acceptedCount) accepted, \(failureCount) unknown failures")
		#expect(graphCount == configuration.iterations)
	}

	// MARK: Seeds

	/// The ordinary suite's batch: seeds 0 through 11 but 9, a known issue, and seed 33, whose graph the tool accepts
	/// with a label that names properties of different types. Compiling the batch is one `swiftc` invocation.
	static let smokeSeeds: [UInt64] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 33]

	static let smokeFixtureHash: UInt64 = 0xF80DF42C1884CC80

	/// The seeds the scheduled workflow runs, `0..<scheduledSeedCount`. `knownIssues` lists every one that fails.
	static let scheduledSeedCount = 5_000

	/// Seeds in `0..<scheduledSeedCount` whose graphs fail today, grouped by shape. Every fix first adds a graph of
	/// its shape, reduced, as a hand-written regression test; removing the seeds is the last step of the fix.
	static let knownIssues: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: "Two types instantiate instantiators of different types under one label in a lazy cycle, and the generated builder closure for one is passed where the other is expected",
			seeds: [9, 321, 1_075, 1_334, 1_567, 1_599, 1_627, 1_681, 2_026, 2_101, 2_147, 2_903, 3_309, 3_741, 4_571, 4_652, 4_795],
		),
		GraphFuzzerKnownIssue(
			reason: "A mock passes an onlyIfAvailable receive the value of a property in the mock's tree that has the same label and a different type",
			seeds: [1_225, 1_877, 2_016, 2_810, 2_896, 3_128, 3_254, 3_403, 3_514, 3_638, 3_692, 4_330],
		),
		GraphFuzzerKnownIssue(
			reason: "A mock declares one label twice for onlyIfAvailable receives of that label with different types",
			seeds: [84, 96, 768, 3_952, 4_696],
		),
		GraphFuzzerKnownIssue(
			reason: "A mock reads a label before declaring it when an onlyIfAvailable receive of that label has a different type than a required receive of it",
			seeds: [2_306, 2_626],
		),
		GraphFuzzerKnownIssue(
			reason: "A mock root requires an instantiator of its own type through an alias, or a promoted dependency's subtree requires the mock root's alias of that dependency, and the mock captures the closure before declaring it",
			seeds: [705, 1_062, 3_004],
		),
	]

	private static let longRunBatchSize = 20

	/// The first `count` smoke seeds whose graphs the tool accepts.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func acceptedSmokeSeeds(count: Int) async throws -> [UInt64] {
		var seeds = [UInt64]()
		for seed in Self.smokeSeeds where seeds.count < count {
			let runs = try await GraphFuzzerOracle.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed))
			if !runs.generatedFiles.isEmpty {
				seeds.append(seed)
			}
		}
		try #require(seeds.count == count)
		return seeds
	}
}

/// The smoke batch's results, computed once per process and shared by the tests that check them.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let smokeResults = Task {
	try await GraphFuzzerOracle.results(forSeeds: SafeDIToolGraphFuzzerTests.smokeSeeds)
}

extension Issue {
	/// Whether this is the issue the fuzzer records for a failure of `kind`. A known issue matches only the kind of
	/// failure it documents, so that, say, a fixture the fuzzer got wrong still fails the test.
	fileprivate func isGraphFuzzerFailure(ofKind kind: GraphFuzzerFailure.Kind) -> Bool {
		comments.contains { $0.rawValue.hasPrefix("Graph fuzzer seed ") && $0.rawValue.contains(": \(kind.rawValue).") }
	}
}

extension GraphFuzzerToolRuns {
	/// These runs, with one more generated file in both outcomes when the tool accepted the graph.
	func addingGeneratedFile(named fileName: String, contents: String) -> GraphFuzzerToolRuns {
		func adding(to outcome: GraphFuzzerToolOutcome) -> GraphFuzzerToolOutcome {
			switch outcome {
			case let .accepted(generatedFiles, warnings):
				.accepted(generatedFiles: generatedFiles.merging([fileName: contents]) { $1 }, warnings: warnings)
			case .rejected:
				outcome
			}
		}
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: adding(to: firstOutcome), secondOutcome: adding(to: secondOutcome))
	}
}

/// The long run's settings, read from the environment.
struct GraphFuzzerLongRunConfiguration {
	let iterations: Int
	let startingSeed: UInt64
	/// A file the run appends its progress to, which the scheduled workflow reads: `seed <n>` before the tool
	/// first runs each graph, `failure`, `known`, or `stale` lines for each finding, and `completed …` at the end.
	let reportPath: String?

	/// `nil` unless `SAFEDI_GRAPH_FUZZER_ITERATIONS` is set. An unparsable count becomes zero, which the run reports.
	static var current: GraphFuzzerLongRunConfiguration? {
		let environment = ProcessInfo.processInfo.environment
		guard let iterations = environment["SAFEDI_GRAPH_FUZZER_ITERATIONS"] else { return nil }
		return GraphFuzzerLongRunConfiguration(
			iterations: Int(iterations) ?? 0,
			startingSeed: environment["SAFEDI_GRAPH_FUZZER_STARTING_SEED"].flatMap { UInt64($0) } ?? 0,
			reportPath: environment["SAFEDI_GRAPH_FUZZER_REPORT"],
		)
	}
}

/// An append-only progress log. Each line is written as it happens, so the log survives a crash of the process.
struct GraphFuzzerReport {
	let path: String?

	func append(_ line: String) {
		guard let path else { return }
		if !FileManager.default.fileExists(atPath: path) {
			FileManager.default.createFile(atPath: path, contents: nil)
		}
		guard let fileHandle = FileHandle(forWritingAtPath: path) else { return }
		defer { try? fileHandle.close() }
		_ = try? fileHandle.seekToEnd()
		try? fileHandle.write(contentsOf: Data((line + "\n").utf8))
	}
}
