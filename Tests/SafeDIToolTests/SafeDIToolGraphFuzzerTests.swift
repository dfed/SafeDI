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
		#expect(Set(GraphFuzzerFeature.allCases).subtracting(features).subtracting(GraphFuzzerFeature.awaitingMacroSupport).sorted() == [])
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
	func knownIssues_listEachSeedOnceInIncreasingOrder_belowCorpusSeedCount() {
		#expect(Self.knownIssueListProblems() == [])
	}

	@Test
	func knownIssueListProblems_reportEachProblem_whenListIsMalformed() {
		let knownIssues = [
			GraphFuzzerKnownIssue(reason: "Unordered", signatures: [.compilerCrashInGeneratedMock], seeds: [20, 10]),
			GraphFuzzerKnownIssue(reason: "Repeated and out of range", signatures: [.compilerCrashInGeneratedMock], seeds: [10, 5_000]),
			GraphFuzzerKnownIssue(reason: "Unsigned", signatures: [], seeds: [30]),
		]

		#expect(Self.knownIssueListProblems(knownIssues) == [
			"The seeds of \"Unordered\" are not in increasing order.",
			"Seed 10 is listed as a known issue more than once.",
			"Seed 5000 is a known issue outside the corpus, seeds 0..<5000.",
			"The known issue \"Unsigned\" lists no seeds or no signatures.",
		])
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
	func finding_isKnownIssue_whenMacroRejectsKnownIssueSeedsFixtureAsDocumented() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape the macro rejects",
			signatures: [.macroRejectsFixture(containing: "require use of the argument `fulfilledByType`")],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .fixtureDoesNotCompile,
			details: "S12_T1.swift:9:2: error: `ErasedInstantiator` and `SendableErasedInstantiator` require use of the argument `fulfilledByType`",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
	}

	@Test
	func finding_isFailure_whenMacroRejectionKnownIssueSeedsGeneratedCodeFailsToCompile() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape the macro rejects",
			signatures: [.macroRejectsFixture(containing: "require use of the argument `fulfilledByType`")],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .generatedCodeDoesNotCompile,
			details: "S12_Root0+SafeDI.swift:3:5: error: `ErasedInstantiator` and `SendableErasedInstantiator` require use of the argument `fulfilledByType`",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .failure(failure))
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

	// MARK: Rename invariance

	@Test
	func renaming_reversesTypeNamesAndLabelsWhereverTheyAppear_andRestoresThem() {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: 12)
		let text = "S12_T1 S12_T3Protocol S12_AnyT2 S12_Root0 S12_Missing1 S12_Value t1Builder __safeDI_t3Builder lazyAnyT2 anyT4 missing0 items t4_S12_T4"
		let renaming = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: true, reversesFileNames: false)

		#expect(renaming.rename(text, typeNamePrefix: prefix) == "S12_T8 S12_T6Protocol S12_AnyT7 S12_Root9 S12_Missing8 S12_Value t8Builder __safeDI_t6Builder lazyAnyT7 anyT5 missing9 items t5_S12_T5")
		#expect(renaming.restore(renaming.rename(text, typeNamePrefix: prefix), typeNamePrefix: prefix) == text)
	}

	@Test
	func renaming_renamesOnlyTheOrderItReverses() {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: 12)
		let text = "S12_T1 t1Builder"

		#expect(GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: false, reversesFileNames: false).rename(text, typeNamePrefix: prefix) == "S12_T8 t1Builder")
		#expect(GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: true, reversesFileNames: false).rename(text, typeNamePrefix: prefix) == "S12_T1 t8Builder")
		#expect(GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: true).rename(text, typeNamePrefix: prefix) == text)
	}

	@Test
	func renaming_reversesFileOrder_andRestoresFileNames() throws {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			"@Instantiable\npublic final class S12_T1: Instantiable {\n\tpublic init() {}\n}\n",
			"@Instantiable\npublic final class S12_T0: Instantiable {\n\tpublic init() {}\n}\n",
		])
		let renaming = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: true)

		let fileNames = try #require(renaming.fileNames(of: fixture))

		#expect(fileNames == ["F98_S12_T1.swift", "F99_S12_T0.swift"])
		#expect(renaming.restore("/tmp/<fixture-directory>/F98_S12_T1.swift:1:1: error", typeNamePrefix: fixture.typeNamePrefix) == "/tmp/<fixture-directory>/S12_T1.swift:1:1: error")
	}

	@Test
	func renamedGraphFailures_reportCodeThatDiffers_butNotDiagnosticsInAnotherOrder() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [])
		let renaming = GraphFuzzerRenaming.all[0]
		let diagnostics = GraphFuzzerToolOutcome.rejected(diagnostics: "/a/<fixture-directory>/S12_T0.swift:1:1: error: first\n/a/<fixture-directory>/S12_T1.swift:1:1: error: second")
		let reorderedDiagnostics = GraphFuzzerToolOutcome.rejected(diagnostics: "/b/<fixture-directory>/S12_T1.swift:1:1: error: second\n/b/<fixture-directory>/S12_T0.swift:1:1: error: first")
		let code = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let a = 1\nlet b = 2\n"], warnings: [])
		let reorderedCode = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S12_T0+SafeDIMock.swift": "let b = 2\nlet a = 1\n"], warnings: [])

		let diagnosticFailures = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: diagnostics, secondOutcome: diagnostics, renamedOutcomes: [(renaming, reorderedDiagnostics)]).renamedGraphFailures
		let codeFailures = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: code, secondOutcome: code, renamedOutcomes: [(renaming, reorderedCode)]).renamedGraphFailures

		#expect(diagnosticFailures == [])
		#expect(codeFailures.map { $0.details.prefix { $0 != "\n" } } == ["Reversing its type names changes its generated mock code, in S12_T0+SafeDIMock.swift."])
	}

	@Test
	func finding_isKnownIssue_whenRenamedGraphDiffersAsDocumented() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape whose mock follows the order of names",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock code")],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .renamedGraphDiffers,
			details: "Reversing its labels changes its generated mock code, in S12_T0+SafeDIMock.swift.\nThis graph:\n…",
		)
		let diagnosticsFailure = GraphFuzzerFailure(
			seed: 12,
			kind: .renamedGraphDiffers,
			details: "Reversing its labels changes its diagnostics.\nThis graph:\nchanges its generated mock code",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
		#expect(GraphFuzzerFinding(failure: diagnosticsFailure, knownIssue: knownIssue) == .failure(diagnosticsFailure))
	}

	// MARK: Reproducibility

	@Test
	func randomNumberGenerator_producesSplitMix64ReferenceSequence_forSeedZero() {
		var random = GraphFuzzerRandomNumberGenerator(seed: 0)
		#expect([random.next(), random.next(), random.next()] == [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F])
	}

	@Test
	func seedSetSum_addsUpAcrossShards_whicheverOrderSeedsAreAdded() {
		var whole = GraphFuzzerSeedSetSum()
		for seed in [UInt64(3), 1, 4, 1_000, 59] {
			whole.add(seed)
		}
		var firstShard = GraphFuzzerSeedSetSum()
		var secondShard = GraphFuzzerSeedSetSum()
		for seed in [UInt64(59), 1] {
			firstShard.add(seed)
		}
		for seed in [UInt64(1_000), 3, 4] {
			secondShard.add(seed)
		}

		#expect(firstShard.value &+ secondShard.value == whole.value)
		#expect(firstShard.value != whole.value)
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
			reportProblem("SAFEDI_GRAPH_FUZZER_ITERATIONS must be a positive integer or `corpus`.")
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
		var generatedCorpusHash = GraphFuzzerHash()
		for seed in 0..<UInt64(Self.corpusSeedCount) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed)
			generatedCorpusHash.combine(fixture.description)
			let reservedLabels = fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap { line -> String? in
				guard case let .property(_, label, _) = line, label.hasPrefix("__safeDI_") else { return nil }
				return label
			}
			if !reservedLabels.isEmpty {
				reportProblem("Seed \(seed)'s graph uses \(reservedLabels), which begin with `__safeDI_`, the prefix of generated builder functions.")
			}
		}
		if generatedCorpusHash.value != Self.corpusFixtureHash {
			reportProblem("The generator's graphs for seeds 0..<\(Self.corpusSeedCount) changed (fixture hash \(Self.hexadecimal(generatedCorpusHash.value)), pinned \(Self.hexadecimal(Self.corpusFixtureHash))). Re-derive the known issues, smoke seeds, and pinned values.")
		}

		var graphCount = 0
		var acceptedCount = 0
		var acceptedSeedsSum = GraphFuzzerSeedSetSum()
		var knownIssueCount = 0
		var failureCount = 0
		// Batches run concurrently, one per core, but their findings are recorded in seed order, so the report and
		// the issues are the same on every run. A batch's seeds are all finished when its results arrive.
		let batchStarts = Array(stride(from: 0, to: configuration.iterations, by: Self.longRunBatchSize))
		let concurrentBatchCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
		do {
			try await withThrowingTaskGroup(of: (Int, [GraphFuzzerResult]).self) { group in
				var nextBatchIndex = 0
				func addNextBatch() {
					guard nextBatchIndex < batchStarts.count else { return }
					let batchIndex = nextBatchIndex
					let batchStart = batchStarts[batchIndex]
					let seeds = (batchStart..<min(batchStart + Self.longRunBatchSize, configuration.iterations))
						.map { configuration.startingSeed &+ UInt64($0) }
					nextBatchIndex += 1
					group.addTask {
						var results = try await GraphFuzzerOracle.results(forSeeds: seeds) { seed in
							report.append("seed \(seed)")
						}
						for index in results.indices where results[index].failure == nil
							&& results[index].fixture.seed % Self.crossProcessSampleInterval == 0
						{
							results[index] = try GraphFuzzerResult(
								fixture: results[index].fixture,
								outcome: results[index].outcome,
								failure: GraphFuzzerOracle.crossProcessFailure(of: results[index].fixture),
								renamedGraphFailures: results[index].renamedGraphFailures,
							)
						}
						for result in results {
							report.append("finished \(result.fixture.seed)")
						}
						return (batchIndex, results)
					}
				}
				for _ in 0..<concurrentBatchCount {
					addNextBatch()
				}
				var finishedBatches = [Int: [GraphFuzzerResult]]()
				var nextBatchToRecord = 0
				while let (batchIndex, results) = try await group.next() {
					finishedBatches[batchIndex] = results
					addNextBatch()
					while let results = finishedBatches.removeValue(forKey: nextBatchToRecord) {
						nextBatchToRecord += 1
						for result in results {
							let seed = result.fixture.seed
							graphCount += 1
							if result.isAccepted {
								acceptedCount += 1
								acceptedSeedsSum.add(seed)
							}
							// Counted whether or not the graph also fails another way.
							for renamedGraphFailure in result.renamedGraphFailures {
								report.append("renamed \(seed) \(renamedGraphFailure.details.prefix { $0 != "\n" })")
							}
							let finding = GraphFuzzerFinding(failure: result.failure, knownIssue: knownIssuesBySeed[seed])
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
				}
			}
		} catch {
			reportProblem("The long run stopped after \(graphCount) graphs: \(error)")
			return
		}

		// The oracle accepts any error the tool reports, so pin which graphs the tool accepts: a change that makes
		// it reject valid graphs changes this. A shard of the corpus reports its part, which ci.yml's combine job
		// adds up, and a run of the whole corpus checks the pins itself.
		report.append("shard \(configuration.startingSeed) \(configuration.iterations) \(acceptedCount) \(Self.hexadecimal(acceptedSeedsSum.value))")
		report.append("corpus \(Self.corpusSeedCount) \(Self.corpusAcceptedSeedCount) \(Self.hexadecimal(Self.corpusAcceptedSeedsSum))")
		if configuration.startingSeed == 0, configuration.iterations == Self.corpusSeedCount,
		   acceptedCount != Self.corpusAcceptedSeedCount || acceptedSeedsSum.value != Self.corpusAcceptedSeedsSum
		{
			reportProblem("The tool accepted \(acceptedCount) of seeds 0..<\(Self.corpusSeedCount) (sum \(Self.hexadecimal(acceptedSeedsSum.value))), but \(Self.corpusAcceptedSeedCount) are pinned (sum \(Self.hexadecimal(Self.corpusAcceptedSeedsSum))). A tool change that rejects or accepts different graphs must update the pinned values deliberately.")
		}
		report.append("completed \(graphCount) graphs, \(acceptedCount) accepted, \(knownIssueCount) known issues, \(failureCount) unknown failures")
		#expect(graphCount == configuration.iterations)
	}

	// MARK: Seeds

	/// The ordinary suite's batch: seeds 62, 348, 582, and 1286, whose graphs the tool accepts, with the same
	/// results under every `GraphFuzzerRenaming`, and which between them exercise every feature but those in
	/// `GraphFuzzerFeature.awaitingMacroSupport`, and seed 14, whose graph it rejects. It is small because compiling generated code is what
	/// the fuzzer costs; ci.yml fuzzes the whole corpus on every pull request. Compiling the batch is one `swiftc`
	/// invocation when nothing fails.
	static let smokeSeeds: [UInt64] = [14, 62, 348, 582, 1_286]

	static let smokeAndKnownIssueFixtureHash: UInt64 = 0x6EB966A06DF46F4B

	/// The corpus, seeds `0..<corpusSeedCount`, which ci.yml fuzzes on every pull request and push to main and
	/// `SAFEDI_GRAPH_FUZZER_ITERATIONS=corpus` selects. `knownIssues` lists every one that fails.
	static let corpusSeedCount = 5_000

	static let corpusFixtureHash: UInt64 = 0x37DDE478EAB2E8EA

	/// How many of the corpus's graphs the tool accepts, and which ones, as a `GraphFuzzerSeedSetSum`, which
	/// shards of the corpus can add up.
	static let corpusAcceptedSeedCount = 2_455
	static let corpusAcceptedSeedsSum: UInt64 = 0xC73E20E5D0F80AE8

	/// Seeds in `0..<corpusSeedCount` whose graphs fail today, grouped by shape. Every fix first adds a graph of
	/// its shape, reduced, as a hand-written regression test; removing the seeds is the last step of the fix.
	static let knownIssues: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: "The macro rejects a received or forwarded erased instantiator until PR 438 makes it accept them",
			signatures: [.macroRejectsFixture(containing: "must name the type it builds with the argument `fulfilledByType`")],
			seeds: [
				3, 5, 6, 15, 23, 26, 31, 32, 45, 47, 54, 55, 64, 69, 70, 76,
				87, 91, 93, 95, 96, 97, 101, 112, 114, 125, 132, 134, 136, 137, 138, 144,
				152, 155, 161, 162, 167, 173, 176, 177, 179, 184, 190, 191, 194, 196, 200, 212,
				224, 226, 228, 233, 234, 242, 243, 244, 255, 257, 266, 267, 272, 274, 288, 292,
				294, 295, 304, 305, 310, 316, 317, 322, 324, 325, 326, 330, 339, 340, 346, 347,
				349, 351, 352, 356, 358, 359, 360, 365, 369, 376, 380, 382, 383, 387, 389, 390,
				394, 397, 403, 412, 414, 424, 425, 426, 428, 431, 438, 443, 445, 452, 456, 458,
				474, 475, 477, 478, 479, 481, 493, 496, 497, 519, 524, 526, 537, 553, 554, 560,
				567, 568, 569, 571, 576, 580, 585, 591, 595, 597, 605, 608, 617, 624, 628, 630,
				637, 640, 644, 651, 655, 656, 658, 660, 663, 671, 674, 676, 680, 682, 683, 684,
				689, 691, 693, 694, 695, 696, 707, 717, 719, 722, 724, 725, 728, 730, 733, 734,
				737, 741, 742, 747, 752, 753, 754, 757, 758, 760, 761, 764, 774, 779, 781, 782,
				784, 785, 786, 792, 795, 805, 806, 809, 815, 822, 825, 828, 829, 830, 831, 832,
				837, 838, 840, 844, 847, 848, 856, 860, 867, 873, 874, 882, 889, 897, 900, 901,
				902, 905, 907, 908, 909, 914, 916, 917, 918, 922, 924, 930, 938, 944, 949, 951,
				956, 957, 962, 963, 974, 976, 992, 993, 998, 1_002, 1_007, 1_009, 1_010, 1_011, 1_013, 1_015,
				1_016, 1_018, 1_019, 1_031, 1_032, 1_034, 1_037, 1_043, 1_047, 1_048, 1_051, 1_057, 1_061, 1_065, 1_080, 1_082,
				1_086, 1_095, 1_100, 1_102, 1_103, 1_110, 1_112, 1_116, 1_132, 1_142, 1_146, 1_155, 1_158, 1_165, 1_166, 1_167,
				1_170, 1_171, 1_177, 1_187, 1_191, 1_193, 1_201, 1_202, 1_203, 1_206, 1_208, 1_209, 1_210, 1_213, 1_214, 1_216,
				1_221, 1_225, 1_227, 1_228, 1_232, 1_233, 1_240, 1_241, 1_246, 1_247, 1_253, 1_254, 1_262, 1_272, 1_276, 1_280,
				1_282, 1_284, 1_292, 1_293, 1_295, 1_298, 1_300, 1_311, 1_312, 1_320, 1_321, 1_322, 1_324, 1_325, 1_332, 1_335,
				1_338, 1_352, 1_356, 1_363, 1_372, 1_376, 1_379, 1_397, 1_398, 1_399, 1_400, 1_406, 1_407, 1_409, 1_410, 1_413,
				1_414, 1_415, 1_416, 1_418, 1_426, 1_430, 1_431, 1_432, 1_434, 1_436, 1_437, 1_439, 1_446, 1_454, 1_456, 1_458,
				1_461, 1_463, 1_465, 1_466, 1_470, 1_473, 1_474, 1_475, 1_476, 1_480, 1_483, 1_484, 1_485, 1_494, 1_495, 1_497,
				1_503, 1_504, 1_511, 1_512, 1_513, 1_520, 1_528, 1_529, 1_541, 1_543, 1_545, 1_546, 1_547, 1_548, 1_550, 1_553,
				1_565, 1_570, 1_580, 1_581, 1_586, 1_593, 1_599, 1_600, 1_603, 1_607, 1_608, 1_610, 1_612, 1_615, 1_618, 1_625,
				1_626, 1_627, 1_631, 1_636, 1_637, 1_644, 1_650, 1_652, 1_659, 1_660, 1_662, 1_672, 1_676, 1_679, 1_680, 1_682,
				1_686, 1_689, 1_691, 1_693, 1_694, 1_695, 1_697, 1_699, 1_708, 1_712, 1_718, 1_719, 1_722, 1_724, 1_731, 1_732,
				1_735, 1_736, 1_741, 1_743, 1_748, 1_751, 1_756, 1_768, 1_772, 1_783, 1_784, 1_785, 1_786, 1_788, 1_790, 1_794,
				1_796, 1_799, 1_809, 1_813, 1_818, 1_820, 1_823, 1_824, 1_827, 1_830, 1_831, 1_837, 1_838, 1_853, 1_857, 1_867,
				1_869, 1_876, 1_882, 1_884, 1_885, 1_888, 1_889, 1_893, 1_894, 1_901, 1_911, 1_912, 1_913, 1_914, 1_920, 1_929,
				1_934, 1_937, 1_938, 1_940, 1_941, 1_942, 1_946, 1_951, 1_953, 1_954, 1_957, 1_958, 1_964, 1_966, 1_971, 1_974,
				1_982, 1_984, 1_989, 1_995, 2_001, 2_006, 2_020, 2_025, 2_027, 2_028, 2_030, 2_032, 2_037, 2_038, 2_039, 2_053,
				2_054, 2_057, 2_064, 2_069, 2_073, 2_077, 2_088, 2_091, 2_093, 2_095, 2_099, 2_100, 2_101, 2_102, 2_109, 2_110,
				2_112, 2_116, 2_121, 2_125, 2_126, 2_133, 2_135, 2_136, 2_137, 2_138, 2_151, 2_166, 2_167, 2_168, 2_172, 2_174,
				2_178, 2_179, 2_185, 2_197, 2_203, 2_206, 2_207, 2_209, 2_217, 2_219, 2_222, 2_223, 2_224, 2_226, 2_229, 2_232,
				2_233, 2_239, 2_240, 2_246, 2_249, 2_250, 2_251, 2_257, 2_265, 2_267, 2_268, 2_269, 2_272, 2_274, 2_275, 2_279,
				2_294, 2_296, 2_298, 2_301, 2_302, 2_310, 2_315, 2_317, 2_319, 2_320, 2_325, 2_327, 2_334, 2_343, 2_346, 2_356,
				2_361, 2_364, 2_365, 2_369, 2_372, 2_374, 2_375, 2_381, 2_386, 2_389, 2_391, 2_392, 2_394, 2_400, 2_403, 2_407,
				2_410, 2_415, 2_416, 2_417, 2_418, 2_421, 2_426, 2_433, 2_437, 2_440, 2_441, 2_446, 2_451, 2_455, 2_461, 2_462,
				2_467, 2_472, 2_474, 2_479, 2_482, 2_485, 2_487, 2_497, 2_499, 2_500, 2_502, 2_506, 2_508, 2_511, 2_513, 2_516,
				2_531, 2_533, 2_534, 2_541, 2_543, 2_552, 2_554, 2_560, 2_561, 2_568, 2_572, 2_578, 2_579, 2_583, 2_588, 2_591,
				2_592, 2_595, 2_602, 2_603, 2_605, 2_618, 2_620, 2_623, 2_624, 2_630, 2_631, 2_633, 2_638, 2_639, 2_641, 2_642,
				2_647, 2_652, 2_670, 2_674, 2_678, 2_684, 2_693, 2_694, 2_698, 2_701, 2_704, 2_706, 2_707, 2_711, 2_714, 2_715,
				2_716, 2_719, 2_728, 2_729, 2_730, 2_734, 2_735, 2_737, 2_738, 2_740, 2_742, 2_753, 2_758, 2_760, 2_764, 2_767,
				2_770, 2_776, 2_781, 2_787, 2_792, 2_794, 2_795, 2_797, 2_799, 2_812, 2_815, 2_816, 2_819, 2_820, 2_825, 2_831,
				2_834, 2_840, 2_848, 2_850, 2_851, 2_852, 2_857, 2_868, 2_873, 2_874, 2_877, 2_882, 2_884, 2_888, 2_889, 2_894,
				2_896, 2_897, 2_898, 2_899, 2_901, 2_904, 2_911, 2_912, 2_914, 2_917, 2_919, 2_922, 2_925, 2_927, 2_931, 2_932,
				2_935, 2_936, 2_941, 2_946, 2_947, 2_955, 2_956, 2_959, 2_961, 2_963, 2_972, 2_973, 2_985, 2_986, 2_987, 2_988,
				2_989, 2_990, 2_994, 2_995, 2_997, 2_998, 3_000, 3_010, 3_011, 3_025, 3_028, 3_029, 3_038, 3_039, 3_041, 3_048,
				3_051, 3_058, 3_059, 3_060, 3_061, 3_069, 3_074, 3_077, 3_081, 3_082, 3_084, 3_087, 3_092, 3_096, 3_100, 3_101,
				3_108, 3_115, 3_119, 3_121, 3_123, 3_125, 3_128, 3_134, 3_136, 3_137, 3_145, 3_150, 3_154, 3_160, 3_167, 3_168,
				3_174, 3_182, 3_186, 3_190, 3_196, 3_197, 3_198, 3_204, 3_205, 3_207, 3_212, 3_216, 3_217, 3_220, 3_221, 3_222,
				3_224, 3_225, 3_229, 3_231, 3_239, 3_240, 3_245, 3_248, 3_254, 3_260, 3_263, 3_268, 3_270, 3_273, 3_281, 3_288,
				3_291, 3_292, 3_302, 3_310, 3_312, 3_315, 3_316, 3_323, 3_325, 3_328, 3_329, 3_333, 3_336, 3_353, 3_359, 3_368,
				3_371, 3_375, 3_376, 3_381, 3_388, 3_392, 3_396, 3_398, 3_403, 3_410, 3_412, 3_419, 3_423, 3_427, 3_428, 3_430,
				3_433, 3_439, 3_440, 3_443, 3_446, 3_448, 3_449, 3_452, 3_457, 3_469, 3_473, 3_475, 3_476, 3_477, 3_485, 3_488,
				3_490, 3_493, 3_494, 3_499, 3_502, 3_504, 3_505, 3_507, 3_508, 3_509, 3_510, 3_511, 3_513, 3_516, 3_517, 3_522,
				3_524, 3_532, 3_540, 3_545, 3_547, 3_549, 3_560, 3_561, 3_565, 3_569, 3_574, 3_575, 3_578, 3_579, 3_582, 3_586,
				3_591, 3_593, 3_599, 3_609, 3_613, 3_615, 3_618, 3_620, 3_623, 3_625, 3_627, 3_632, 3_641, 3_643, 3_645, 3_646,
				3_647, 3_648, 3_649, 3_656, 3_657, 3_665, 3_674, 3_678, 3_681, 3_689, 3_694, 3_699, 3_703, 3_704, 3_710, 3_715,
				3_716, 3_721, 3_723, 3_724, 3_725, 3_738, 3_740, 3_742, 3_743, 3_748, 3_749, 3_751, 3_756, 3_764, 3_771, 3_775,
				3_783, 3_786, 3_795, 3_800, 3_801, 3_802, 3_803, 3_806, 3_811, 3_814, 3_819, 3_839, 3_843, 3_844, 3_848, 3_852,
				3_853, 3_870, 3_873, 3_875, 3_876, 3_879, 3_883, 3_887, 3_891, 3_893, 3_894, 3_899, 3_900, 3_915, 3_919, 3_921,
				3_928, 3_931, 3_932, 3_934, 3_935, 3_940, 3_948, 3_949, 3_955, 3_963, 3_968, 3_971, 3_974, 3_979, 3_980, 3_985,
				3_988, 3_991, 3_992, 3_993, 3_994, 3_995, 3_997, 3_998, 4_001, 4_002, 4_003, 4_004, 4_006, 4_012, 4_018, 4_019,
				4_020, 4_025, 4_026, 4_029, 4_038, 4_040, 4_046, 4_050, 4_057, 4_058, 4_060, 4_064, 4_069, 4_074, 4_080, 4_085,
				4_087, 4_090, 4_093, 4_095, 4_099, 4_104, 4_112, 4_122, 4_131, 4_134, 4_147, 4_149, 4_152, 4_153, 4_154, 4_157,
				4_158, 4_159, 4_161, 4_163, 4_165, 4_167, 4_169, 4_170, 4_171, 4_172, 4_175, 4_177, 4_180, 4_189, 4_190, 4_193,
				4_194, 4_196, 4_200, 4_201, 4_202, 4_203, 4_210, 4_211, 4_212, 4_216, 4_218, 4_221, 4_222, 4_229, 4_230, 4_235,
				4_240, 4_242, 4_246, 4_247, 4_251, 4_254, 4_257, 4_258, 4_273, 4_275, 4_285, 4_286, 4_287, 4_289, 4_292, 4_298,
				4_299, 4_300, 4_305, 4_309, 4_310, 4_311, 4_312, 4_323, 4_325, 4_328, 4_331, 4_341, 4_342, 4_354, 4_359, 4_360,
				4_372, 4_381, 4_382, 4_384, 4_388, 4_389, 4_393, 4_399, 4_403, 4_409, 4_411, 4_423, 4_424, 4_425, 4_429, 4_434,
				4_445, 4_446, 4_448, 4_449, 4_452, 4_457, 4_475, 4_476, 4_477, 4_484, 4_488, 4_496, 4_498, 4_500, 4_503, 4_519,
				4_521, 4_522, 4_524, 4_525, 4_526, 4_531, 4_532, 4_533, 4_536, 4_546, 4_547, 4_558, 4_561, 4_563, 4_566, 4_567,
				4_568, 4_576, 4_585, 4_590, 4_592, 4_595, 4_606, 4_613, 4_616, 4_624, 4_625, 4_626, 4_632, 4_635, 4_636, 4_644,
				4_651, 4_653, 4_654, 4_657, 4_660, 4_667, 4_672, 4_674, 4_680, 4_689, 4_691, 4_701, 4_709, 4_720, 4_724, 4_725,
				4_727, 4_730, 4_731, 4_734, 4_740, 4_743, 4_744, 4_745, 4_748, 4_751, 4_752, 4_760, 4_762, 4_767, 4_768, 4_771,
				4_780, 4_782, 4_785, 4_787, 4_788, 4_790, 4_792, 4_794, 4_798, 4_807, 4_809, 4_814, 4_817, 4_823, 4_829, 4_835,
				4_838, 4_840, 4_845, 4_847, 4_849, 4_850, 4_855, 4_859, 4_862, 4_863, 4_864, 4_869, 4_882, 4_883, 4_884, 4_889,
				4_892, 4_902, 4_905, 4_907, 4_908, 4_909, 4_911, 4_913, 4_930, 4_938, 4_942, 4_944, 4_947, 4_966, 4_974, 4_975,
				4_977, 4_985, 4_987, 4_991, 4_992, 4_997,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "A mock's API follows the order of type names or labels: which back-edge of a lazy cycle loses its override, which promoted sibling is passed nil, and the order of overrides",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock code")],
			seeds: [
				9, 35, 37, 53, 74, 77, 83, 107, 131, 139, 156, 157, 163, 164, 168, 241,
				245, 262, 281, 309, 311, 364, 371, 381, 418, 420, 434, 437, 439, 448, 450, 473,
				515, 545, 548, 550, 579, 593, 632, 642, 652, 688, 712, 714, 732, 743, 751, 759,
				768, 808, 836, 883, 903, 912, 927, 940, 948, 975, 987, 1_022, 1_029, 1_035, 1_042, 1_044,
				1_064, 1_066, 1_072, 1_075, 1_084, 1_085, 1_090, 1_092, 1_096, 1_107, 1_108, 1_118, 1_121, 1_125, 1_126, 1_139,
				1_145, 1_147, 1_185, 1_199, 1_200, 1_204, 1_215, 1_236, 1_289, 1_302, 1_329, 1_343, 1_358, 1_362, 1_412, 1_425,
				1_433, 1_441, 1_453, 1_464, 1_492, 1_496, 1_502, 1_524, 1_525, 1_531, 1_567, 1_573, 1_602, 1_633, 1_646, 1_664,
				1_675, 1_692, 1_711, 1_742, 1_745, 1_752, 1_781, 1_782, 1_795, 1_804, 1_815, 1_843, 1_851, 1_883, 1_896, 1_898,
				1_925, 1_967, 1_970, 1_972, 1_981, 1_996, 2_005, 2_017, 2_029, 2_047, 2_051, 2_062, 2_083, 2_084, 2_117, 2_123,
				2_144, 2_149, 2_152, 2_165, 2_201, 2_211, 2_234, 2_245, 2_248, 2_270, 2_277, 2_284, 2_286, 2_287, 2_316, 2_323,
				2_335, 2_337, 2_348, 2_377, 2_430, 2_432, 2_444, 2_452, 2_456, 2_488, 2_515, 2_518, 2_536, 2_553, 2_555, 2_577,
				2_610, 2_637, 2_667, 2_727, 2_731, 2_732, 2_741, 2_752, 2_791, 2_801, 2_808, 2_835, 2_839, 2_841, 2_845, 2_870,
				2_916, 2_940, 2_968, 2_980, 2_996, 3_004, 3_023, 3_054, 3_064, 3_071, 3_073, 3_075, 3_076, 3_091, 3_106, 3_132,
				3_149, 3_180, 3_183, 3_184, 3_214, 3_215, 3_241, 3_252, 3_298, 3_306, 3_344, 3_361, 3_362, 3_378, 3_391, 3_397,
				3_409, 3_424, 3_436, 3_460, 3_491, 3_506, 3_528, 3_533, 3_534, 3_537, 3_588, 3_596, 3_600, 3_602, 3_651, 3_655,
				3_661, 3_664, 3_677, 3_707, 3_713, 3_741, 3_750, 3_761, 3_776, 3_805, 3_821, 3_823, 3_845, 3_886, 3_908, 3_942,
				3_964, 3_972, 3_996, 4_044, 4_055, 4_068, 4_094, 4_102, 4_107, 4_110, 4_117, 4_125, 4_133, 4_156, 4_192, 4_213,
				4_215, 4_217, 4_227, 4_260, 4_266, 4_281, 4_296, 4_304, 4_344, 4_352, 4_371, 4_378, 4_404, 4_420, 4_428, 4_458,
				4_504, 4_514, 4_515, 4_516, 4_534, 4_541, 4_543, 4_545, 4_618, 4_619, 4_629, 4_634, 4_637, 4_640, 4_642, 4_646,
				4_648, 4_664, 4_666, 4_707, 4_716, 4_717, 4_729, 4_775, 4_776, 4_781, 4_795, 4_822, 4_834, 4_861, 4_865, 4_872,
				4_904, 4_918, 4_922, 4_932, 4_934, 4_945, 4_955, 4_963, 4_996,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "Which errors SafeDI reports, and the root and chain each names, follow the order of type names or labels",
			signatures: [.renamedGraphDiffers(containing: "changes its diagnostics")],
			seeds: [
				46, 79, 106, 127, 293, 335, 377, 411, 417, 463, 485, 557, 603, 607, 615, 661,
				679, 862, 896, 943, 972, 979, 1_101, 1_122, 1_131, 1_222, 1_230, 1_342, 1_345, 1_353, 1_354, 1_404,
				1_419, 1_438, 1_460, 1_498, 1_562, 1_611, 1_638, 1_749, 1_765, 1_774, 1_808, 1_846, 1_864, 1_923, 1_928, 1_960,
				2_012, 2_050, 2_092, 2_190, 2_191, 2_200, 2_260, 2_263, 2_293, 2_342, 2_359, 2_379, 2_423, 2_466, 2_495, 2_523,
				2_569, 2_574, 2_673, 2_675, 2_676, 2_695, 2_713, 2_718, 2_757, 2_768, 2_777, 2_778, 2_811, 2_822, 2_823, 2_915,
				2_944, 2_958, 3_009, 3_020, 3_036, 3_072, 3_111, 3_126, 3_161, 3_202, 3_209, 3_237, 3_253, 3_321, 3_332, 3_374,
				3_377, 3_389, 3_395, 3_538, 3_542, 3_581, 3_652, 3_659, 3_809, 3_812, 3_816, 3_911, 3_960, 3_965, 4_028, 4_031,
				4_092, 4_097, 4_140, 4_148, 4_238, 4_264, 4_271, 4_374, 4_406, 4_483, 4_494, 4_506, 4_528, 4_559, 4_614, 4_621,
				4_622, 4_638, 4_693, 4_700, 4_726, 4_810, 4_820, 4_888, 4_941, 4_948,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "SafeDIMockConfiguration.swift declares its extensions in the order of the roots that reach them",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock configuration code")],
			seeds: [
				1_992, 2_186, 2_254, 4_643, 4_747,
			],
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
	static func knownIssueListProblems(_ knownIssues: [GraphFuzzerKnownIssue] = knownIssues) -> [String] {
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
				if seed >= UInt64(corpusSeedCount) {
					problems.append("Seed \(seed) is a known issue outside the corpus, seeds 0..<\(corpusSeedCount).")
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

	/// `nil` unless `SAFEDI_GRAPH_FUZZER_ITERATIONS` is set: to a count of seeds, or to `corpus` for
	/// `corpusSeedCount` seeds. Anything else becomes zero, which the run reports.
	static var current: GraphFuzzerLongRunConfiguration? {
		let environment = ProcessInfo.processInfo.environment
		guard let iterations = environment["SAFEDI_GRAPH_FUZZER_ITERATIONS"] else { return nil }
		return GraphFuzzerLongRunConfiguration(
			iterations: iterations == "corpus" ? SafeDIToolGraphFuzzerTests.corpusSeedCount : Int(iterations) ?? 0,
			startingSeed: environment["SAFEDI_GRAPH_FUZZER_STARTING_SEED"].flatMap { UInt64($0) } ?? 0,
			reportPath: environment["SAFEDI_GRAPH_FUZZER_REPORT"],
		)
	}
}

/// An append-only progress log. Each line is written as it happens, so the log survives a crash of the process.
/// Batches run concurrently, so appends are serialized.
final class GraphFuzzerReport: Sendable {
	init(path: String?) {
		self.path = path
	}

	let path: String?

	func append(_ line: String) {
		guard let path else { return }
		lock.withLock {
			if !FileManager.default.fileExists(atPath: path) {
				FileManager.default.createFile(atPath: path, contents: nil)
			}
			guard let fileHandle = FileHandle(forWritingAtPath: path) else { return }
			defer { try? fileHandle.close() }
			_ = try? fileHandle.seekToEnd()
			try? fileHandle.write(contentsOf: Data((line + "\n").utf8))
		}
	}

	private let lock = NSLock()
}
