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
	func renaming_movesTypeNamesAcrossWrapperNamesWhereverTheyAppear_andRestoresThem() {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: 12)
		let text = "S12_T1 S12_T2 S12_T2Protocol S12_AnyT2 S12_Root0 S12_Missing1 S12_Value S12_Leaf S12_Ext S12_Unbuildable0 t1_S12_T1 lazyAnyT2 Instantiator<S12_T1> x_SendableInstantiator__S12_T2 S12_T0+SafeDIMock.swift"
		let renaming = GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: false, movesTypeNamesAcrossWrapperNames: true)

		// A type and its protocol move together, and so does a name a generated name or a file name embeds; labels keep their indices.
		#expect(renaming.rename(text, typeNamePrefix: prefix) == "A12_T1 Z12_T2 Z12_T2Protocol Z12_AnyT2 A12_Root0 A12_Missing1 Z12_Value A12_Leaf Z12_Ext Z12_Unbuildable0 t1_A12_T1 lazyAnyT2 Instantiator<A12_T1> x_SendableInstantiator__Z12_T2 A12_T0+SafeDIMock.swift")
		#expect(renaming.restore(renaming.rename(text, typeNamePrefix: prefix), typeNamePrefix: prefix) == text)
	}

	@Test
	func renamedFixture_declaresTypesSortingBeforeAndAfterEveryWrapperName_whenRenamingMovesTypeNamesAcrossWrapperNames() throws {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 2)
		let renaming = try #require(GraphFuzzerRenaming.all.first { $0.movesTypeNamesAcrossWrapperNames })
		let wrapperNames = ["ErasedInstantiator<", "Instantiator<", "LazilyInstantiated<", "SendableErasedInstantiator<", "SendableInstantiator<", "SendableLazilyInstantiated<"]
		func declaredTypeNamesAmongWrapperNames(of fixture: GraphFuzzerFixture) -> [String] {
			(fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap(\.declaredTypeName) + wrapperNames).sorted()
		}

		// Every type name begins with `S2_`, which reversing indices keeps, so each sorts between the same two wrapper names.
		#expect(declaredTypeNamesAmongWrapperNames(of: fixture) == [
			"ErasedInstantiator<", "Instantiator<", "LazilyInstantiated<",
			"S2_Leaf", "S2_Root0", "S2_Root1", "S2_Root2", "S2_T0", "S2_T1", "S2_T2", "S2_T3",
			"SendableErasedInstantiator<", "SendableInstantiator<", "SendableLazilyInstantiated<",
		])
		// Moved, some sort before every wrapper name and the rest after every one, and `T0` and `T1` now sort after `T2` and `T3`.
		#expect(declaredTypeNamesAmongWrapperNames(of: fixture.renamed(by: renaming)) == [
			"A2_Root0", "A2_Root1", "A2_T2", "A2_T3",
			"ErasedInstantiator<", "Instantiator<", "LazilyInstantiated<", "SendableErasedInstantiator<", "SendableInstantiator<", "SendableLazilyInstantiated<",
			"Z2_Leaf", "Z2_Root2", "Z2_T0", "Z2_T1",
		])
	}

	@Test
	func renaming_restoresTypeNamesItMovesAcrossWrapperNames_whenItAlsoReversesEveryOrder() throws {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			"@Instantiable\npublic final class S12_T1: Instantiable {\n\tpublic init(t2: S12_T2) {\n\t\tself.t2 = t2\n\t}\n\n\t@Instantiated let t2: S12_T2\n}\n",
			"@Instantiable\npublic final class S12_T2: Instantiable {\n\tpublic init() {}\n}\n",
		])
		let renaming = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: true, reversesFileNames: true, movesTypeNamesAcrossWrapperNames: true)

		let fileNames = try #require(renaming.fileNames(of: fixture.renamed(by: renaming)))

		// `S12_T1` and `S12_T2` become `S12_T8` and `S12_T7`, which move to `A12_T8` and `Z12_T7`.
		#expect(fileNames == ["F98_Z12_T7.swift", "F99_A12_T8.swift"])
		#expect(renaming.restore("/tmp/<fixture-directory>/F99_A12_T8.swift:7:2: error: `t7: Z12_T7`", typeNamePrefix: fixture.typeNamePrefix) == "/tmp/<fixture-directory>/S12_T1.swift:7:2: error: `t2: S12_T2`")
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

	/// The ordinary suite's batch: seeds 62, 582, 691, 705, and 930, whose graphs the tool accepts, with the same
	/// results under every `GraphFuzzerRenaming`, and which between them exercise every feature, and seed 14, whose
	/// graph it rejects. It is small because compiling generated code is what the fuzzer costs; ci.yml fuzzes the
	/// whole corpus on every pull request. Compiling the batch is one `swiftc` invocation when nothing fails.
	static let smokeSeeds: [UInt64] = [14, 62, 582, 691, 705, 930]

	static let smokeAndKnownIssueFixtureHash: UInt64 = 0xC89C9908E3933AD9

	/// The corpus, seeds `0..<corpusSeedCount`, which ci.yml fuzzes on every pull request and push to main and
	/// `SAFEDI_GRAPH_FUZZER_ITERATIONS=corpus` selects. `knownIssues` lists every one that fails.
	static let corpusSeedCount = 5_000

	static let corpusFixtureHash: UInt64 = 0xFE5D9C52BB9D7A05

	/// How many of the corpus's graphs the tool accepts, and which ones, as a `GraphFuzzerSeedSetSum`, which
	/// shards of the corpus can add up.
	static let corpusAcceptedSeedCount = 2_445
	static let corpusAcceptedSeedsSum: UInt64 = 0xCCB739ABF9AC704A

	/// Seeds in `0..<corpusSeedCount` whose graphs fail today, grouped by shape. Every fix first adds a graph of
	/// its shape, reduced, as a hand-written regression test; removing the seeds is the last step of the fix.
	static let knownIssues: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: "A mock's API follows the order of type names or labels: which back-edge of a lazy cycle loses its override, which promoted sibling is passed nil, and the order of overrides",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock code")],
			seeds: [
				3, 35, 37, 45, 53, 55, 77, 107, 114, 131, 157, 168, 223, 233, 241, 281,
				309, 311, 364, 371, 381, 383, 390, 431, 434, 448, 450, 473, 515, 545, 567, 593,
				595, 617, 630, 632, 680, 688, 714, 728, 732, 751, 768, 774, 785, 786, 808, 833,
				836, 847, 903, 912, 940, 948, 956, 975, 987, 1_004, 1_029, 1_035, 1_042, 1_044, 1_061, 1_064,
				1_072, 1_075, 1_084, 1_092, 1_139, 1_145, 1_147, 1_185, 1_215, 1_236, 1_280, 1_289, 1_300, 1_329, 1_352, 1_362,
				1_372, 1_432, 1_433, 1_441, 1_453, 1_464, 1_492, 1_496, 1_502, 1_504, 1_524, 1_525, 1_531, 1_567, 1_602, 1_633,
				1_646, 1_664, 1_675, 1_695, 1_742, 1_752, 1_781, 1_784, 1_795, 1_804, 1_853, 1_857, 1_867, 1_896, 1_898, 1_919,
				1_920, 1_938, 1_970, 1_972, 2_005, 2_017, 2_051, 2_083, 2_084, 2_117, 2_123, 2_149, 2_152, 2_165, 2_201, 2_211,
				2_234, 2_245, 2_249, 2_270, 2_277, 2_287, 2_296, 2_316, 2_325, 2_335, 2_337, 2_348, 2_389, 2_403, 2_430, 2_432,
				2_437, 2_444, 2_456, 2_485, 2_515, 2_518, 2_553, 2_555, 2_577, 2_630, 2_637, 2_667, 2_704, 2_731, 2_732, 2_741,
				2_752, 2_791, 2_808, 2_835, 2_841, 2_845, 2_874, 2_902, 2_914, 2_916, 2_940, 2_968, 2_998, 3_004, 3_023, 3_064,
				3_074, 3_075, 3_091, 3_132, 3_134, 3_149, 3_180, 3_183, 3_214, 3_215, 3_221, 3_225, 3_241, 3_252, 3_298, 3_306,
				3_329, 3_344, 3_361, 3_362, 3_397, 3_430, 3_439, 3_460, 3_491, 3_504, 3_506, 3_526, 3_533, 3_534, 3_537, 3_577,
				3_582, 3_588, 3_596, 3_602, 3_604, 3_620, 3_645, 3_648, 3_661, 3_699, 3_707, 3_715, 3_723, 3_741, 3_750, 3_775,
				3_776, 3_805, 3_823, 3_843, 3_894, 3_915, 3_942, 4_044, 4_068, 4_102, 4_107, 4_110, 4_117, 4_122, 4_125, 4_156,
				4_177, 4_192, 4_196, 4_206, 4_213, 4_215, 4_217, 4_227, 4_254, 4_260, 4_266, 4_281, 4_304, 4_344, 4_360, 4_371,
				4_393, 4_404, 4_420, 4_428, 4_496, 4_504, 4_515, 4_534, 4_541, 4_545, 4_567, 4_613, 4_619, 4_634, 4_637, 4_640,
				4_642, 4_648, 4_664, 4_666, 4_707, 4_716, 4_717, 4_729, 4_775, 4_776, 4_781, 4_783, 4_786, 4_795, 4_834, 4_859,
				4_861, 4_865, 4_889, 4_904, 4_918, 4_922, 4_944, 4_947, 4_955, 4_963, 4_996,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "A diagnostic that suggests several properties lists them in the order of their labels and type names",
			signatures: [.renamedGraphDiffers(containing: "changes its diagnostics")],
			seeds: [
				417, 557, 1_013, 1_353, 1_638, 1_864, 2_423, 3_020, 3_036, 3_081, 3_111, 3_659, 4_097, 4_449, 4_506, 4_790,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "SafeDIMockConfiguration.swift declares its extensions in the order of the roots that reach them",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock configuration code")],
			seeds: [
				69, 1_992, 2_186, 2_254, 3_931, 4_643, 4_747, 4_974,
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
