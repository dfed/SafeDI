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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func knownIssueSeeds_remainAcceptedByTool_whenRunThroughTool() async throws {
		// Compiling known-issue graphs, and running the tool twice to compare, costs more than the ordinary suite can
		// afford, so the long run, which every publish and the weekly run execute, checks that they still fail to
		// compile. This catches the other way a fix ends a known issue at once: the tool rejecting the shape.
		for knownIssue in Self.knownIssues {
			let outcome = try await GraphFuzzerOracle.toolOutcome(of: GraphFuzzerGenerator.fixture(forSeed: knownIssue.seeds[0]))
			let isAccepted = if case .accepted = outcome {
				true
			} else {
				false
			}
			#expect(
				isAccepted,
				"The tool now rejects known-issue seed \(knownIssue.seeds[0]). If that is the fix for \"\(knownIssue.reason)\", remove its seeds from knownIssues after checking them with the long run.",
			)
		}
	}

	@Test
	func knownIssues_listEachSeedOnceInIncreasingOrder_belowScheduledSeedCount() {
		#expect(Self.knownIssueListProblems() == [])
	}

	@Test
	func finding_isFailure_whenKnownIssueSeedFailsAnotherWay() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(seed: knownIssue.seeds[0], kind: .runsDiffer, details: "First run: …")

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) two runs of the tool differ")
	}

	@Test
	func finding_isFailure_whenKnownIssueSeedReportsAnotherCompilerError() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDoesNotCompile,
			details: "Root+SafeDI.swift:3:5: error: cannot find 'missing' in scope",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) generated code does not compile")
	}

	@Test
	func finding_isKnownIssue_whenKnownIssueSeedFailsAsDocumented() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDoesNotCompile,
			details: "T4+SafeDIMock.swift:13:13: error: invalid redeclaration of 't5'",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .knownIssue(knownIssue, failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "known \(knownIssue.seeds[0]) \(knownIssue.reason)")
	}

	@Test
	func finding_isStaleKnownIssue_whenKnownIssueSeedNoLongerFails() {
		let knownIssue = Self.compilerErrorKnownIssue

		let finding = GraphFuzzerFinding(failure: nil, knownIssue: knownIssue)

		#expect(finding == .staleKnownIssue(knownIssue))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "stale \(knownIssue.seeds[0]) \(knownIssue.reason)")
	}

	@Test
	func finding_isKnownIssue_whenKnownIssueSeedCrashesCompilerInGeneratedMock() {
		let knownIssue = Self.compilerCrashKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .compilerCrashedOnGeneratedCode,
			details: "The Swift compiler crashed.\nIn mock(t4:t1:safeDIOverrides:) at S705_T1+SafeDIMock.swift:19:5.",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
	}

	@Test
	func finding_isFailure_whenKnownIssueSeedCrashesCompilerInShapeThatDoesNotCrash() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .compilerCrashedOnGeneratedCode,
			details: "The Swift compiler crashed.\nIn mock() at S9_Root0+SafeDIMock.swift:5:5.",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) the Swift compiler crashed on generated code")
	}

	@Test
	func compilerCrash_namesCrashingDeclarationWithoutStackFrames_whenStandardErrorHoldsStackDump() throws {
		let standardError = """
		terminate called after throwing an instance of 'std::out_of_range'
		  what():  map::at
		Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.
		Stack dump:
		0.\tProgram arguments: /usr/bin/swift-frontend -frontend -c /tmp/safedi-verify-1/input_0_S705_Root0.swift
		1.\tSwift version 6.2.4 (swift-6.2.4-RELEASE)
		2.\tCompiling with the current language version
		3.\tWhile running pass #1021 SILFunctionTransform "SendNonSendable" on SILFunction "@$s4mock".
		 for 'mock(t4:t1:safeDIOverrides:)' (at /tmp/safedi-verify-1/S705_T1+SafeDIMock.swift:19:5)
		 #0 0x00005630b6cd92d8 llvm::sys::PrintStackTrace(llvm::raw_ostream&, int) (/usr/bin/swift-frontend+0x731f2d8)
		 #1 0x00005630b6cd70ae llvm::sys::RunSignalHandlers() (/usr/bin/swift-frontend+0x731d0ae)
		"""

		let crash = try #require(GraphFuzzerCompilerCrash(standardError: standardError))

		#expect(crash.fileName == "S705_T1+SafeDIMock.swift")
		#expect(crash.summary == """
		The Swift compiler crashed.
		1.\tSwift version 6.2.4 (swift-6.2.4-RELEASE)
		2.\tCompiling with the current language version
		3.\tWhile running pass #1021 SILFunctionTransform "SendNonSendable" on SILFunction "@$s4mock".
		In mock(t4:t1:safeDIOverrides:) at S705_T1+SafeDIMock.swift:19:5.
		""")
	}

	// MARK: Oracle sensitivity

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportEachBrokenGraph_whenGeneratedCodeFailsToTypeCheckOrToLower() throws {
		// Each graph is one small type, so the three compiler invocations this takes stay cheap; the smoke batch
		// already compiles real graphs.
		func graph(seed: UInt64, brokenGeneratedCode: String) -> GraphFuzzerToolRuns {
			let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
			let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: [
				"@Instantiable\npublic final class \(prefix)Probe: Instantiable {\n\tpublic init() {}\n}\n",
			])
			let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["\(prefix)Broken.swift": brokenGeneratedCode], warnings: [])
			return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
		}
		let typeErrorSeed: UInt64 = 1_000_000_001
		let loweringErrorSeed: UInt64 = 1_000_000_002
		let toolRuns = [
			// A type error, which the type checker reports.
			graph(seed: typeErrorSeed, brokenGeneratedCode: "func broken() -> Int { \"not an integer\" }\n"),
			// A closure that captures a local declared after it, which only lowering to SIL reports, and which a
			// type error elsewhere in the same compilation would hide.
			graph(seed: loweringErrorSeed, brokenGeneratedCode: """
			func brokenWhenLowered() -> Int {
				func read() -> Int { value }
				let value = read()
				return value
			}

			"""),
		]

		let failures = try GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [typeErrorSeed, loweringErrorSeed])
		#expect(failures[typeErrorSeed]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[loweringErrorSeed]?.kind == .generatedCodeDoesNotCompile)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_reportRunsDiffer_whenTwoRunsProduceDifferentOutput() async throws {
		let accepted = try #require(try await smokeResults.value.first { $0.isAccepted && $0.failure == nil })
		let runs = GraphFuzzerToolRuns(fixture: accepted.fixture, firstOutcome: accepted.outcome, secondOutcome: accepted.outcome)
		let differingRuns = GraphFuzzerToolRuns(
			fixture: accepted.fixture,
			firstOutcome: accepted.outcome,
			secondOutcome: runs.addingGeneratedFile(named: "Extra.swift", contents: "\n").firstOutcome,
		)

		// Graphs whose runs differ are not compiled, so this costs no compiler invocation.
		let results = try GraphFuzzerOracle.results(of: [differingRuns])

		#expect(results.map(\.failure?.kind) == [.runsDiffer])
	}

	// MARK: Reproducibility

	@Test
	func randomNumberGenerator_producesSplitMix64ReferenceSequence_forSeedZero() {
		var random = GraphFuzzerRandomNumberGenerator(seed: 0)
		#expect([random.next(), random.next(), random.next()] == [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F])
	}

	@Test
	func fixture_matchesReferenceHash_forSmokeAndKnownIssueSeeds() {
		// Every platform must generate the same graph for a seed, or a seed reported by the long run would not
		// reproduce elsewhere. Changing the generator changes this hash and changes which graph every seed names, so
		// re-derive the smoke and known-issue seeds when it changes; the long run pins the rest of the corpus.
		let seeds = Self.smokeSeeds + Self.knownIssues.flatMap(\.seeds)
		#expect(Self.fixtureHash(forSeeds: seeds) == Self.smokeAndKnownIssueFixtureHash)
	}

	// MARK: Long run

	@Test(.enabled(if: GraphFuzzerLongRunConfiguration.current != nil, "Set SAFEDI_GRAPH_FUZZER_ITERATIONS to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_findsNoUnknownFailures_whenEnabledByEnvironment() async throws {
		let configuration = try #require(GraphFuzzerLongRunConfiguration.current)
		let report = GraphFuzzerReport(path: configuration.reportPath)
		func reportProblem(_ problem: String) {
			report.append("problem \(problem)")
			Issue.record(Comment(rawValue: problem))
		}
		guard compileVerificationIsEnabled else {
			reportProblem("The graph fuzzer checks generated code by compiling it. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			return
		}
		guard configuration.iterations > 0 else {
			reportProblem("SAFEDI_GRAPH_FUZZER_ITERATIONS must be a positive integer or `scheduled`.")
			return
		}
		let knownIssueListProblems = Self.knownIssueListProblems()
		guard knownIssueListProblems.isEmpty else {
			knownIssueListProblems.forEach(reportProblem)
			return
		}
		let knownIssuesBySeed = Dictionary(uniqueKeysWithValues: Self.knownIssues.flatMap { knownIssue in
			knownIssue.seeds.map { ($0, knownIssue) }
		})

		// Pin the whole corpus the long run covers, which the ordinary suite's hash covers only a sample of, and check
		// that no graph uses a label beginning with `__safeDI_`, which the generated builder functions use.
		var corpusFixtureHash = GraphFuzzerHash()
		for seed in 0..<UInt64(Self.scheduledSeedCount) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed)
			corpusFixtureHash.combine(fixture.description)
			let reservedLabels = fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap { line -> String? in
				guard case let .property(_, label, _) = line, label.hasPrefix("__safeDI_") else { return nil }
				return label
			}
			if !reservedLabels.isEmpty {
				reportProblem("Seed \(seed)'s graph uses \(reservedLabels), which begin with `__safeDI_`, the prefix of generated builder functions.")
			}
		}
		if corpusFixtureHash.value != Self.scheduledCorpusFixtureHash {
			reportProblem("The generator's graphs for seeds 0..<\(Self.scheduledSeedCount) changed (fixture hash \(Self.hexadecimal(corpusFixtureHash.value)), pinned \(Self.hexadecimal(Self.scheduledCorpusFixtureHash))). Re-derive the known issues, smoke seeds, and pinned values.")
		}

		var graphCount = 0
		var acceptedCount = 0
		var acceptedSeedsHash = GraphFuzzerHash()
		var knownIssueCount = 0
		var failureCount = 0
		do {
			for batchStart in stride(from: 0, to: configuration.iterations, by: Self.longRunBatchSize) {
				let seeds = (batchStart..<min(batchStart + Self.longRunBatchSize, configuration.iterations))
					.map { configuration.startingSeed &+ UInt64($0) }
				let results = try await GraphFuzzerOracle.results(forSeeds: seeds) { seed in
					report.append("seed \(seed)")
				}
				for result in results {
					let seed = result.fixture.seed
					graphCount += 1
					if result.isAccepted {
						acceptedCount += 1
						acceptedSeedsHash.combine(String(seed))
					}
					var failure = result.failure
					if failure == nil, seed % Self.crossProcessSampleInterval == 0 {
						failure = try GraphFuzzerOracle.crossProcessFailure(of: result.fixture)
					}
					let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssuesBySeed[seed])
					if let reportLine = finding.reportLine(seed: seed) {
						report.append(reportLine)
					}
					switch finding {
					case .knownIssue:
						knownIssueCount += 1
					case .failure:
						failureCount += 1
					case .passed, .staleKnownIssue:
						break
					}
					Self.record(finding, fixture: result.fixture)
				}
			}
		} catch {
			reportProblem("The long run stopped after \(graphCount) graphs: \(error)")
			return
		}

		// The oracle accepts any error the tool reports, so pin which graphs the tool accepts: a change that makes
		// it reject valid graphs changes this.
		if configuration.startingSeed == 0, configuration.iterations == Self.scheduledSeedCount,
		   acceptedCount != Self.scheduledAcceptedSeedCount || acceptedSeedsHash.value != Self.scheduledAcceptedSeedsHash
		{
			reportProblem("The tool accepted \(acceptedCount) of seeds 0..<\(Self.scheduledSeedCount) (hash \(Self.hexadecimal(acceptedSeedsHash.value))), but \(Self.scheduledAcceptedSeedCount) are pinned (hash \(Self.hexadecimal(Self.scheduledAcceptedSeedsHash))). A tool change that rejects or accepts different graphs must update the pinned values deliberately.")
		}
		report.append("completed \(graphCount) graphs, \(acceptedCount) accepted, \(knownIssueCount) known issues, \(failureCount) unknown failures")
		#expect(graphCount == configuration.iterations)
	}

	// MARK: Seeds

	/// The ordinary suite's batch: seeds 330 and 426, whose graphs the tool accepts and which between them exercise
	/// every feature, and seeds 5 and 6, whose graphs it rejects. It is small because compiling generated code is
	/// what the fuzzer costs; the long run pins the accepted set over the whole corpus. Compiling the batch is one
	/// `swiftc` invocation when nothing fails.
	static let smokeSeeds: [UInt64] = [5, 6, 330, 426]

	static let smokeAndKnownIssueFixtureHash: UInt64 = 0x9194EE53C9F61C98

	/// The seeds `graph-fuzzer.yml` runs before every release and weekly, `0..<scheduledSeedCount`, which
	/// `SAFEDI_GRAPH_FUZZER_ITERATIONS=scheduled` selects. `knownIssues` lists every one that fails.
	static let scheduledSeedCount = 5_000

	static let scheduledCorpusFixtureHash: UInt64 = 0x812957047246024D

	/// How many of the scheduled seeds' graphs the tool accepts, and a hash of which ones.
	static let scheduledAcceptedSeedCount = 2_814
	static let scheduledAcceptedSeedsHash: UInt64 = 0x289314064BABE7C2

	/// Seeds in `0..<scheduledSeedCount` whose graphs fail today, grouped by shape. Every fix first adds a graph of
	/// its shape, reduced, as a hand-written regression test; removing the seeds is the last step of the fix.
	static let knownIssues: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: "A mock root's own onlyIfAvailable receive and a dependency the mock root promotes and builds share a label with different types, and the mock binds both under that label",
			signatures: [.compilerError(containing: "invalid redeclaration")],
			seeds: [2_810],
		),
	]

	/// Known issues for the tests of `GraphFuzzerFinding`, which must not depend on what `knownIssues` lists today.
	private static let compilerErrorKnownIssue = GraphFuzzerKnownIssue(
		reason: "A shape whose generated code redeclares a label",
		signatures: [.compilerError(containing: "invalid redeclaration")],
		seeds: [84],
	)
	private static let compilerCrashKnownIssue = GraphFuzzerKnownIssue(
		reason: "A shape whose generated mock crashes the compiler, or captures a closure before declaring it",
		signatures: [.compilerError(containing: "before it is declared"), .compilerCrashInGeneratedMock],
		seeds: [705],
	)

	private static let longRunBatchSize = 20

	/// Every this many seeds, the long run also runs the `SafeDITool` executable in two processes and compares them.
	private static let crossProcessSampleInterval: UInt64 = 50

	/// What is wrong with `knownIssues`: a seed listed twice, a shape's seeds out of order, or a seed the long
	/// run's corpus does not cover.
	static func knownIssueListProblems() -> [String] {
		var problems = [String]()
		var seenSeeds = Set<UInt64>()
		for knownIssue in knownIssues {
			if knownIssue.seeds.isEmpty || knownIssue.signatures.isEmpty {
				problems.append("The known issue \"\(knownIssue.reason)\" lists no seeds or no signatures.")
			}
			if knownIssue.seeds != knownIssue.seeds.sorted() {
				problems.append("The seeds of \"\(knownIssue.reason)\" are not in increasing order.")
			}
			for seed in knownIssue.seeds {
				if !seenSeeds.insert(seed).inserted {
					problems.append("Seed \(seed) is listed as a known issue more than once.")
				}
				if seed >= UInt64(scheduledSeedCount) {
					problems.append("Seed \(seed) is a known issue outside the scheduled seeds 0..<\(scheduledSeedCount).")
				}
			}
		}
		return problems
	}

	static func fixtureHash(forSeeds seeds: [UInt64]) -> UInt64 {
		var hash = GraphFuzzerHash()
		for seed in seeds {
			hash.combine(GraphFuzzerGenerator.fixture(forSeed: seed).description)
		}
		return hash.value
	}

	private static func hexadecimal(_ value: UInt64) -> String {
		"0x" + String(value, radix: 16, uppercase: true)
	}

	/// Records `finding` as an issue: as a known issue when it is one, and as a known issue that was not recorded,
	/// which fails the test, when the seed no longer fails.
	private static func record(_ finding: GraphFuzzerFinding, fixture: GraphFuzzerFixture) {
		switch finding {
		case .passed:
			break
		case let .knownIssue(knownIssue, failure):
			withKnownIssue("Seed \(fixture.seed): \(knownIssue.reason)") {
				Issue.record(failure.issueComment(fixture: fixture))
			}
		case let .staleKnownIssue(knownIssue):
			withKnownIssue("Seed \(fixture.seed) no longer fails, so remove it from knownIssues: \(knownIssue.reason)") {}
		case let .failure(failure):
			Issue.record(failure.issueComment(fixture: fixture))
		}
	}
}

/// The smoke batch's results, computed once per process and shared by the tests that check them.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let smokeResults = Task {
	try await GraphFuzzerOracle.results(forSeeds: SafeDIToolGraphFuzzerTests.smokeSeeds)
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
	/// A file the run appends its progress to, which `graph-fuzzer.yml` reads: `seed <n>` before the tool first
	/// runs each graph; `failure <seed> <kind>`, `known <seed> <reason>`, or `stale <seed> <reason>` for each
	/// finding; `problem <text>` for anything wrong with the run itself; and `completed …` at the end.
	let reportPath: String?

	/// `nil` unless `SAFEDI_GRAPH_FUZZER_ITERATIONS` is set: to a count of seeds, or to `scheduled` for
	/// `scheduledSeedCount` seeds. Anything else becomes zero, which the run reports.
	static var current: GraphFuzzerLongRunConfiguration? {
		let environment = ProcessInfo.processInfo.environment
		guard let iterations = environment["SAFEDI_GRAPH_FUZZER_ITERATIONS"] else { return nil }
		return GraphFuzzerLongRunConfiguration(
			iterations: iterations == "scheduled" ? SafeDIToolGraphFuzzerTests.scheduledSeedCount : Int(iterations) ?? 0,
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
