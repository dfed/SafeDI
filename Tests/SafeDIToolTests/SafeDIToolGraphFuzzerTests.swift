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

	@Test
	func wrapperParameterFailure_reportsParameter_whenMockTakesLazilyInstantiatedParameterForReceive() {
		let runs = Self.mockedProbe(declaring: "@Received let value: LazilyInstantiated<S1_Value>", mockParameter: "value: LazilyInstantiated<S1_Value>")

		#expect(runs.wrapperParameterFailure?.kind == .mockTakesWrapperParameterForReceive)
		#expect(runs.wrapperParameterFailure?.details.prefix { $0 != "\n" } == "`S1_Probe.mock` takes `value: LazilyInstantiated<S1_Value>`.")
	}

	@Test
	func wrapperParameterFailure_isNil_whenMockTakesLazilyInstantiatedPropertyTheMockedTypeForwards() {
		let runs = Self.mockedProbe(declaring: "@Forwarded let value: LazilyInstantiated<S1_Value>", mockParameter: "value: LazilyInstantiated<S1_Value>")

		#expect(runs.wrapperParameterFailure == nil)
	}

	/// The runs of a graph of one mocked type, `S1_Probe`, that declares `property`, whose generated mock takes
	/// `mockParameter`.
	private static func mockedProbe(declaring property: String, mockParameter: String) -> GraphFuzzerToolRuns {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"@Instantiable(generateMock: true)\npublic final class S1_Probe: Instantiable {\n\t\(property)\n}\n",
		])
		let outcome = GraphFuzzerToolOutcome.accepted(
			generatedFiles: ["S1_Probe+SafeDIMock.swift": "extension S1_Probe {\n    static func mock(\n        \(mockParameter),\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> S1_Probe {}\n}\n"],
			warnings: [],
		)
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func results_reportIntegrationsDiffer_whenRenamedGraphAndSplitGraphBothGiveOtherResults() throws {
		// One small type, so the compile this takes stays cheap, as in `compilationFailures_reportEachBrokenGraph…`.
		let seed: UInt64 = 1_000_000_003
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: [
			"@Instantiable\npublic final class \(prefix)Probe: Instantiable {\n\tpublic init() {}\n}\n",
		])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let multiModuleRuns = GraphFuzzerMultiModuleRuns(
			seed: seed,
			partition: GraphFuzzerPartition.partition(of: fixture),
			renaming: nil,
			moduleInfoOutcome: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .accepted(GraphFuzzerGeneratedModule(units: [:], importsByFileName: ["Alpha.swift": []], warnings: [])))]),
			pluginOutcome: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .rejected(diagnostics: "error"))]),
			regeneratedRoots: [],
		)
		let toolRuns = GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: outcome,
			secondOutcome: outcome,
			renamedOutcomes: [(GraphFuzzerRenaming.all[0], .rejected(diagnostics: "renamed"))],
			multiModuleRuns: [multiModuleRuns],
		)

		let results = try GraphFuzzerOracle.results(of: [toolRuns])

		#expect(results.map(\.failure?.kind) == [.integrationsDiffer])
		#expect(results.map { $0.renamedGraphFailures.map(\.kind) } == [[.renamedGraphDiffers]])
		#expect(results.map { $0.multiModuleFailures.map(\.kind) } == [[.integrationsDiffer]])
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

	// MARK: Sibling alias chains

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_declaresChainOfAliasesThroughOnlyIfAvailableAliasOfSiblingsOptionalFormBeneathOtherSibling_forSeed731() async throws {
		// `Root0` instantiates `t1: T1` and `lazyT0`, which builds `T0`. `T0` renames `t1` by its optional form only if
		// available and renames that alias as required; `Link0`, which only `T0` instantiates, renames the second alias
		// as required; and `Link1`, which only `Link0` instantiates, receives the third. So `t1` must be built before
		// `lazyT0`. `S731_Ext.instantiate` receives `lazyT0`'s instance, but nothing `t1` builds receives `lazyT0`, so
		// the tool accepts the graph, creates the whole chain from `t1`, and the smoke batch compiles it.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 731)

		#expect(Self.propertyDeclarations(of: "S731_Root0", in: fixture).prefix(2) == [
			"@Instantiated let t1: S731_T1",
			"@Instantiated let lazyT0: SendableLazilyInstantiated<S731_T0>",
		])
		#expect(Self.propertyDeclarations(of: "S731_T0", in: fixture).suffix(3) == [
			"@Received(fulfilledByDependencyNamed: \"t1\", ofType: S731_T1?.self, onlyIfAvailable: true) let t1Alias: S731_T1?",
			"@Received(fulfilledByDependencyNamed: \"t1Alias\", ofType: S731_T1?.self) let t1AliasAlias: S731_T1?",
			"@Instantiated let link0: S731_Link0",
		])
		#expect(Self.propertyDeclarations(of: "S731_Link0", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t1AliasAlias\", ofType: S731_T1?.self) let t1AliasAliasAlias: S731_T1?",
			"@Instantiated let link1: S731_Link1",
		])
		#expect(Self.propertyDeclarations(of: "S731_Link1", in: fixture) == ["@Received let t1AliasAliasAlias: S731_T1?"])
		#expect(Self.propertyDeclarations(of: "S731_T1", in: fixture) == [])
		#expect(GraphFuzzerFeature.features(of: fixture).isSuperset(of: [.aliasOfOptionalFormOfProperty, .aliasOfOnlyIfAvailableAlias, .onlyIfAvailableAlias, .requiredAlias]))
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 731 })
		#expect(result.failure == nil)
		#expect(Self.generatedFiles(of: result.outcome)["S731_Root0+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension S731_Root0 {
		    public convenience init() {
		        let t1 = S731_T1()
		        @Sendable func __safeDI_lazyT0() -> S731_T0 {
		            #sourceLocation(file: "S731_T0.swift", line: 10)
		            let anyT1Alias: S731_AnyT1? = S731_AnyT1(t1)
		            #sourceLocation()
		            #sourceLocation(file: "S731_T0.swift", line: 11)
		            let t1Alias: S731_T1? = t1
		            #sourceLocation()
		            #sourceLocation(file: "S731_T0.swift", line: 12)
		            let t1AliasAlias: S731_T1? = t1Alias
		            #sourceLocation()
		            func __safeDI_link0() -> S731_Link0 {
		                #sourceLocation(file: "S731_Link0.swift", line: 8)
		                let t1AliasAliasAlias: S731_T1? = t1AliasAlias
		                #sourceLocation()
		                let link1 = S731_Link1(t1AliasAliasAlias: t1AliasAliasAlias)
		                return S731_Link0(t1AliasAliasAlias: t1AliasAliasAlias, link1: link1)
		            }
		            let link0: S731_Link0 = __safeDI_link0()
		            return S731_T0(anyT1Alias: anyT1Alias, t1Alias: t1Alias, t1AliasAlias: t1AliasAlias, link0: link0)
		        }
		        let lazyT0 = SendableLazilyInstantiated<S731_T0>(__safeDI_lazyT0)
		        func __safeDI_t2Builder() -> S731_T2 {
		            #sourceLocation(file: "S731_T2.swift", line: 7)
		            let t1Alias: S731_T1? = t1
		            #sourceLocation()
		            return S731_T2(t1Alias: t1Alias)
		        }
		        let t2Builder = Instantiator<S731_T2>(__safeDI_t2Builder)
		        let ext: S731_Ext = S731_Ext.instantiate(lazyT0: lazyT0.instance)
		        self.init(t1: t1, lazyT0: lazyT0, t2Builder: t2Builder, ext: ext)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_declaresChainOfAliasesThroughChildScopeBeneathOtherSibling_forSeed2420() async throws {
		// `T0`, which no root reaches, so that only its mock builds it, instantiates `t6: T6` and `t2: T2`. `T2` renames
		// `t6` only if available and renames that alias only if available; `Link0`, which only `T2` instantiates,
		// renames the second alias only if available – a chain through a child scope – and renames the third as
		// required, which is created whether or not anything receives it. So `t6` must be built before `t2`, and
		// nothing stops it: the tool accepts the graph, `T0`'s mock creates the whole chain from `t6`, and the smoke
		// batch compiles it.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 2_420)

		#expect(Self.propertyDeclarations(of: "S2420_T0", in: fixture).prefix(2) == [
			"@Instantiated let t6: S2420_T6",
			"@Instantiated let t2: S2420_T2",
		])
		#expect(Self.propertyDeclarations(of: "S2420_T2", in: fixture).suffix(3) == [
			"@Received(fulfilledByDependencyNamed: \"t6\", ofType: S2420_T6.self, onlyIfAvailable: true) let t6Alias: S2420_T6?",
			"@Received(fulfilledByDependencyNamed: \"t6Alias\", ofType: S2420_T6?.self, onlyIfAvailable: true) let t6AliasAlias: S2420_T6?",
			"@Instantiated let link0: S2420_Link0",
		])
		#expect(Self.propertyDeclarations(of: "S2420_Link0", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t6AliasAlias\", ofType: S2420_T6?.self, onlyIfAvailable: true) let t6AliasAliasAlias: S2420_T6?",
			"@Received(fulfilledByDependencyNamed: \"t6AliasAliasAlias\", ofType: S2420_T6?.self) let t6AliasAliasAliasAlias: S2420_T6?",
		])
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 2_420 })
		#expect(result.failure == nil)
		#expect(Self.generatedFiles(of: result.outcome)["S2420_T0+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension S2420_T0 {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            t6: (() -> S2420_T6)? = nil,
		            t2: S2420_T2.SafeDIMockConfiguration = .init(),
		            anyT1: (() -> S2420_AnyT1)? = nil,
		            t1Builder: (() -> S2420_T1)? = nil
		        ) {
		            self.t6 = t6
		            self.t2 = t2
		            self.anyT1 = anyT1
		            self.t1Builder = t1Builder
		        }

		        let t6: (() -> S2420_T6)?
		        let t2: S2420_T2.SafeDIMockConfiguration
		        let anyT1: (() -> S2420_AnyT1)?
		        let t1Builder: (() -> S2420_T1)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> S2420_T0 {
		        let t6 = if let safeDIBuilder = safeDIOverrides.t6 { safeDIBuilder() } else { S2420_T6() }
		        func __safeDI_t2() -> S2420_T2 {
		            func __safeDI_t1Builder() -> S2420_T1 {
		                if let safeDIBuilder = safeDIOverrides.t2.t1Builder { safeDIBuilder() } else { S2420_T1() }
		            }
		            let t1Builder = Instantiator<S2420_T1>(__safeDI_t1Builder)
		            #sourceLocation(file: "S2420_T2.swift", line: 11)
		            let t6Alias: S2420_T6? = t6
		            #sourceLocation()
		            #sourceLocation(file: "S2420_T2.swift", line: 12)
		            let t6AliasAlias: S2420_T6? = t6Alias
		            #sourceLocation()
		            func __safeDI_link0() -> S2420_Link0 {
		                #sourceLocation(file: "S2420_Link0.swift", line: 8)
		                let t6AliasAliasAlias: S2420_T6? = t6AliasAlias
		                #sourceLocation()
		                #sourceLocation(file: "S2420_Link0.swift", line: 9)
		                let t6AliasAliasAliasAlias: S2420_T6? = t6AliasAliasAlias
		                #sourceLocation()
		                return if let safeDIBuilder = safeDIOverrides.t2.link0 { safeDIBuilder(t6AliasAliasAlias, t6AliasAliasAliasAlias) } else { S2420_Link0(t6AliasAliasAlias: t6AliasAliasAlias, t6AliasAliasAliasAlias: t6AliasAliasAliasAlias) }
		            }
		            let link0: S2420_Link0 = __safeDI_link0()
		            return if let safeDIBuilder = safeDIOverrides.t2.safeDIBuilder { safeDIBuilder(t1Builder, t6Alias, t6AliasAlias, link0) } else { S2420_T2(t1Builder: t1Builder, t6Alias: t6Alias, t6AliasAlias: t6AliasAlias, link0: link0) }
		        }
		        let t2: S2420_T2 = __safeDI_t2()
		        let anyT1 = if let safeDIBuilder = safeDIOverrides.anyT1 { safeDIBuilder() } else { S2420_AnyT1(S2420_T1()) }
		        func __safeDI_t1Builder() -> S2420_T1 {
		            if let safeDIBuilder = safeDIOverrides.t1Builder { safeDIBuilder() } else { S2420_T1() }
		        }
		        let t1Builder = Instantiator<S2420_T1>(__safeDI_t1Builder)
		        return S2420_T0(t6: t6, t2: t2, anyT1: anyT1, t1Builder: t1Builder)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_makesSiblingsTypeReceiveTheOtherSibling_forSeed4224() async throws {
		// `Root0` instantiates `t1: T1` and `t2: T2`. `T1` renames `t2` by its optional form only if available;
		// `Link0`, which only `T1` instantiates, renames that alias only if available – a chain through a child scope –
		// renames the second alias only if available, and renames the third as required. So `t2` must be built before
		// `t1`, and `T2` receives `t1`, so it cannot be: the tool rejects the graph with the dependency cycle at that
		// receive.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 4_224)

		#expect(Self.propertyDeclarations(of: "S4224_Root0", in: fixture).prefix(2) == [
			"@Instantiated let t1: S4224_T1",
			"@Instantiated let t2: S4224_T2",
		])
		#expect(Self.propertyDeclarations(of: "S4224_T1", in: fixture).suffix(2) == [
			"@Received(fulfilledByDependencyNamed: \"t2\", ofType: S4224_T2?.self, onlyIfAvailable: true) let t2Alias: S4224_T2?",
			"@Instantiated let link0: S4224_Link0",
		])
		#expect(Self.propertyDeclarations(of: "S4224_Link0", in: fixture) == [
			"@Received(fulfilledByDependencyNamed: \"t2Alias\", ofType: S4224_T2?.self, onlyIfAvailable: true) let t2AliasAlias: S4224_T2?",
			"@Received(fulfilledByDependencyNamed: \"t2AliasAlias\", ofType: S4224_T2?.self, onlyIfAvailable: true) let t2AliasAliasAlias: S4224_T2?",
			"@Received(fulfilledByDependencyNamed: \"t2AliasAliasAlias\", ofType: S4224_T2?.self) let t2AliasAliasAliasAlias: S4224_T2?",
		])
		#expect(Self.propertyDeclarations(of: "S4224_T2", in: fixture).last == "@Received let t1: S4224_T1")
		let result = try #require(try await smokeResults.value.first { $0.fixture.seed == 4_224 })
		#expect(result.failure == nil)
		#expect(Self.diagnostics(of: result.outcome) == "S4224_T2.swift:10:2: error: Dependency cycle: @Instantiated `t1: S4224_T1` -> @Received `t2: S4224_T2?` -> @Received `t1: S4224_T1`. `t1: S4224_T1` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.")
	}

	/// The properties the type named `typeName` declares in `fixture`, each as `<attribute> let <label>: <type>`.
	private static func propertyDeclarations(of typeName: String, in fixture: GraphFuzzerFixture) -> [String] {
		var currentTypeName = ""
		return fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap { line in
			switch line {
			case let .typeDeclaration(name):
				currentTypeName = name
				return nil
			case let .property(attribute, label, type):
				return currentTypeName == typeName ? "\(attribute) let \(label): \(type)" : nil
			case .instantiableAttribute, .instantiateMethod, .other:
				return nil
			}
		}
	}

	/// The files the tool generated, with each path to a fixture file reduced to the file's name, which is the same on
	/// every machine.
	private static func generatedFiles(of outcome: GraphFuzzerToolOutcome) -> [String: String] {
		switch outcome {
		case let .accepted(generatedFiles, _):
			generatedFiles.mapValues(GraphFuzzerRenaming.reducingFixturePathsToFileNames(in:))
		case .rejected:
			[:]
		}
	}

	/// The tool's diagnostics, with each path to a fixture file reduced to the file's name.
	private static func diagnostics(of outcome: GraphFuzzerToolOutcome) -> String? {
		switch outcome {
		case .accepted:
			nil
		case let .rejected(diagnostics):
			GraphFuzzerRenaming.reducingFixturePathsToFileNames(in: diagnostics)
		}
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
	func difference_isNil_whenDiagnosticsSuggestTheSamePropertiesInAnotherOrder() {
		let diagnostics = GraphFuzzerToolOutcome.rejected(diagnostics: "/a/<fixture-directory>/S12_T1.swift:7:2: error: @Received property `t4: S12_T3` is not @Instantiated or @Forwarded in chain: S12_Root0 -> S12_T1. Did you mean one of `t3: S12_T3`, `t4: Instantiator<S12_T3>`, `t6: S12_T3`?")
		let reorderedSuggestions = GraphFuzzerToolOutcome.rejected(diagnostics: "/b/<fixture-directory>/S12_T1.swift:7:2: error: @Received property `t4: S12_T3` is not @Instantiated or @Forwarded in chain: S12_Root0 -> S12_T1. Did you mean one of `t6: S12_T3`, `t4: Instantiator<S12_T3>`, `t3: S12_T3`?")

		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics, and: reorderedSuggestions) == nil)
	}

	@Test
	func difference_reportsDiagnostics_whenDiagnosticsDifferInMoreThanTheOrderOfTheirSuggestions() {
		func diagnostics(chain: String, suggestions: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/a/<fixture-directory>/S12_T1.swift:7:2: error: @Received property `t4: S12_T3` is not @Instantiated or @Forwarded in chain: \(chain). Did you mean one of \(suggestions)?")
		}
		let original = diagnostics(chain: "S12_Root0 -> S12_T1", suggestions: "`t3: S12_T3`, `t6: S12_T3`")

		// Another suggestion, one more suggestion, and the same suggestions in another order in another message.
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(chain: "S12_Root0 -> S12_T1", suggestions: "`t3: S12_T3`, `t5: S12_T3`")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(chain: "S12_Root0 -> S12_T1", suggestions: "`t3: S12_T3`, `t4: Instantiator<S12_T3>`, `t6: S12_T3`")) == "its diagnostics")
		#expect(GraphFuzzerToolOutcome.difference(between: original, and: diagnostics(chain: "S12_Root1 -> S12_T1", suggestions: "`t6: S12_T3`, `t3: S12_T3`")) == "its diagnostics")
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

	// MARK: Multi-module partition

	@Test
	func partition_keepsLazyCycleInOneModule_whenInstantiatorsCloseIt() {
		// `Root0` instantiates `T1`, which instantiates `T2` through an instantiator, which instantiates `T1` through
		// one: a lazy cycle, whose types must share a module. `T3` refers to nothing and nothing refers to it.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2Builder: Instantiator<S12_T2>"]),
			Self.typeSource(named: "S12_T2", properties: ["@Instantiated let t1Builder: Instantiator<S12_T1>"]),
			Self.typeSource(named: "S12_T3", properties: []),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 4)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1, 2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [3], referencedModuleNames: [], dependencies: []),
		])
		#expect(partition.importedModuleNamesByFileIndex == [["Alpha"], [], [], []])
	}

	@Test
	func partitionDescription_listsEachModuleWithItsDependenciesAndFilesImports_whenModulesDependOnOneAnother() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2Builder: Instantiator<S12_T2>"]),
			Self.typeSource(named: "S12_T2", properties: ["@Instantiated let t1Builder: Instantiator<S12_T1>"]),
			Self.typeSource(named: "S12_T3", properties: []),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 4)

		#expect(partition.description == """
		Alpha: S12_T1.swift, S12_T2.swift
		Beta (depends on Alpha): S12_Root0.swift importing Alpha
		Gamma: S12_T3.swift
		""")
	}

	@Test
	func partition_listsEveryModuleATreeReachesAsDependency_whenModulesFormChain() {
		// `Root0`'s tree reaches `T2` through `T1`, so `Root0`'s module must read `T2`'s `.safedi` as well as `T1`'s,
		// as a Bazel user must list it, while its file imports only `T1`'s module.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T2", properties: []),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 3)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [1], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [0], referencedModuleNames: ["Beta"], dependencies: ["Alpha", "Beta"]),
		])
		#expect(partition.importedModuleNamesByFileIndex == [["Beta"], ["Alpha"], []])
	}

	@Test
	func partition_dealsComponentsOutToFewerModules_whenModuleCountIsBelowComponentCount() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T2", properties: []),
		])

		// The three components, `T2`, `T1`, and `Root0`, are dealt out in that order: the first two to `Alpha`.
		#expect(GraphFuzzerPartition.partition(of: fixture, moduleCount: 2).modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1, 2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
		#expect(GraphFuzzerPartition.partition(of: fixture, moduleCount: 1).modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [0, 1, 2], referencedModuleNames: [], dependencies: []),
		])
	}

	@Test
	func partition_refersToModuleDeclaringErasedType_whenFileNamesOnlyTheErasedType() {
		// `T1` receives `T2`'s erased type, declared beside `T2`, and nothing names `T2` itself.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_T1", properties: ["@Received let anyT2: S12_AnyT2"]),
			Self.typeSource(named: "S12_T2", properties: [], declaresHelperTypes: true),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
	}

	@Test
	func partition_refersToModuleDeclaringProtocol_whenFileNamesOnlyTheProtocol() {
		// `T1` aliases `t2` as `T2`'s protocol, declared beside `T2`, and nothing names `T2` itself.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_T1", properties: ["@Received(fulfilledByDependencyNamed: \"t2\", ofType: S12_T2Protocol.self) let t2Protocol: S12_T2Protocol"]),
			Self.typeSource(named: "S12_T2", properties: [], declaresHelperTypes: true),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)

		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [1], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [0], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
	}

	@Test
	func partition_movesHelperTypesIntoTheirOwnFile_whenRootFileDeclaresThem() {
		// The generator declares `Value` and `Unbuildable<n>` in `Root0`'s file. `T1` names `Value`, so left there, `T1`
		// and `Root0` would refer to each other and share a module; moved, the helper file lands first and the root's
		// module depends on `T1`'s.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"])
				+ "\npublic final class S12_Value: Instantiable {}\n\npublic final class S12_Unbuildable0 {}\n",
			Self.typeSource(named: "S12_T1", properties: ["@Received let items: Instantiator<S12_Value>"]),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 3)

		#expect(partition.fileNames == ["S12_Root0.swift", "S12_T1.swift", "S12_Helpers.swift"])
		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [2], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [1], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [0], referencedModuleNames: ["Beta"], dependencies: ["Alpha", "Beta"]),
		])
		let modules = partition.moduleFixtures(of: fixture)
		#expect(modules.map(\.swiftFileContent) == [[], ["import Alpha\n\n" + fixture.swiftFileContent[1]], ["import Beta\n\n" + Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"])]])
		#expect(modules.map(\.swiftFileContentByFilePath) == [["S12_Helpers.swift": "public final class S12_Value: Instantiable {}\n\npublic final class S12_Unbuildable0 {}\n"], [:], [:]])
	}

	@Test
	func partition_putsHelperFileInFirstModule_whenOnlyATypeNoRootReachesNamesIt() {
		// Visited in file order, the helper file would be met from `T2`, after the roots' components; visited first, it
		// is the first component wherever it is named from.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"])
				+ "\npublic final class S12_Value: Instantiable {}\n",
			Self.typeSource(named: "S12_T1", properties: []),
			Self.typeSource(named: "S12_T2", properties: ["@Received let items: Instantiator<S12_Value>"]),
		])

		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 4)

		#expect(partition.fileNames == ["S12_Root0.swift", "S12_T1.swift", "S12_T2.swift", "S12_Helpers.swift"])
		#expect(partition.modules == [
			GraphFuzzerPartition.Module(name: "Alpha", fileIndices: [3], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Beta", fileIndices: [1], referencedModuleNames: [], dependencies: []),
			GraphFuzzerPartition.Module(name: "Gamma", fileIndices: [0], referencedModuleNames: ["Beta"], dependencies: ["Beta"]),
			GraphFuzzerPartition.Module(name: "Delta", fileIndices: [2], referencedModuleNames: ["Alpha"], dependencies: ["Alpha"]),
		])
	}

	@Test
	func moduleFixtures_prependImportOfEachReferencedModule_whenFilesReferToOtherModules() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1", "@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T1", properties: []),
			Self.typeSource(named: "S12_T2", properties: []),
		])
		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 3)

		let modules = partition.moduleFixtures(of: fixture)

		#expect(modules.map(\.name) == ["Alpha", "Beta", "Gamma"])
		#expect(modules.map(\.packageName) == ["Graph", "Graph", "Graph"])
		#expect(modules.map(\.dependencies) == [[], [], ["Alpha", "Beta"]])
		#expect(modules.map(\.swiftFileContent) == [
			[fixture.swiftFileContent[1]],
			[fixture.swiftFileContent[2]],
			["import Alpha\nimport Beta\n\n" + fixture.swiftFileContent[0]],
		])
		#expect(modules.map(\.swiftFileContentByFilePath) == [[:], [:], [:]])
	}

	@Test
	func moduleFixtures_keepEachFileInItsModuleUnderRenamedNames_whenRenamingReversesTypeAndFileNames() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_T1", properties: ["@Instantiated let t2: S12_T2"]),
			Self.typeSource(named: "S12_T2", properties: []),
		])
		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)
		let renaming = GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: false, reversesFileNames: true)

		let modules = partition.moduleFixtures(of: fixture, renamedBy: renaming)

		// `T2`, in `Alpha`, becomes `T7`, and `T1`, in `Beta`, becomes `T8`; the files are named to reverse their order.
		#expect(modules.map(\.name) == ["Alpha", "Beta"])
		#expect(modules.map(\.swiftFileContent) == [[], []])
		#expect(modules[0].swiftFileContentByFilePath == ["F99_S12_T7.swift": Self.typeSource(named: "S12_T7", properties: [])])
		#expect(modules[1].swiftFileContentByFilePath == ["F98_S12_T8.swift": "import Alpha\n\n" + Self.typeSource(named: "S12_T8", properties: ["@Instantiated let t2: S12_T7"])])
	}

	@Test
	func moduleCount_variesWithTheGraph_acrossSmokeSeeds() {
		// Chosen from the graph's text, so that single-module graphs stay in the corpus beside the others.
		let moduleCounts = Set(Self.smokeSeeds.map { seed in
			GraphFuzzerPartition.partition(of: GraphFuzzerGenerator.fixture(forSeed: seed)).modules.count
		})

		#expect(moduleCounts.contains(1))
		#expect(moduleCounts.contains(2))
		#expect(moduleCounts.contains { $0 >= 3 })
		#expect(moduleCounts.allSatisfy { (1...GraphFuzzerPartition.moduleNames.count).contains($0) })
	}

	@Test
	func partition_matchesReferenceHash_forSmokeAndKnownIssueSeeds() {
		// The partition draws nothing from the seed, so a change to it changes neither the graphs nor the pins on
		// them; this pins the partition itself, so a change to it is deliberate. The long run pins it for the corpus.
		let seeds = Self.smokeSeeds + Self.knownIssues.flatMap(\.seeds)
		#expect(Self.partitionHash(forSeeds: seeds) == Self.smokeAndKnownIssuePartitionHash)
	}

	@Test
	func generatedModule_splitsCombinedFileIntoUnitsNamedAsThePluginNamesItsFiles_whenFileHoldsATreeMocksAndConfigurations() {
		var module = GraphFuzzerGeneratedModule(units: [:], importsByFileName: [:], warnings: [])

		GraphFuzzerGeneratedModule.parsingGeneratedFile("""
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Alpha)
		import Alpha
		#endif
		#if canImport(Beta)
		import Beta
		#endif

		extension S12_Root0 {
		    public convenience init() {
		        let t1 = S12_T1()
		        self.init(t1: t1)
		    }
		}

		#if DEBUG
		extension S12_T1 {
		    static func mock(
		    ) -> S12_T1 {
		        S12_T1()
		    }
		}
		#endif

		#if DEBUG
		extension S12_T1 {
		    struct SafeDIMockConfiguration {
		    }
		}
		#endif

		#if DEBUG
		extension S12_T2 {
		    struct SafeDIMockConfiguration {
		    }
		}

		extension S12_T3 {
		    struct SafeDIMockConfiguration {
		    }
		}
		#endif

		""", named: "Gamma.swift", into: &module)

		#expect(module.importsByFileName == ["Gamma.swift": ["import Alpha", "import Beta"]])
		#expect(module.units == [
			"S12_Root0+SafeDI.swift": """
			extension S12_Root0 {
			    public convenience init() {
			        let t1 = S12_T1()
			        self.init(t1: t1)
			    }
			}
			""",
			"S12_T1+SafeDIMock.swift": """
			#if DEBUG
			extension S12_T1 {
			    static func mock(
			    ) -> S12_T1 {
			        S12_T1()
			    }
			}
			#endif
			""",
			"S12_T1+SafeDIMockConfiguration.swift": """
			#if DEBUG
			extension S12_T1 {
			    struct SafeDIMockConfiguration {
			    }
			}
			#endif
			""",
			"S12_T2+SafeDIMockConfiguration.swift": """
			#if DEBUG
			extension S12_T2 {
			    struct SafeDIMockConfiguration {
			    }
			}
			#endif
			""",
			"S12_T3+SafeDIMockConfiguration.swift": """
			#if DEBUG
			extension S12_T3 {
			    struct SafeDIMockConfiguration {
			    }
			}
			#endif
			""",
		])
	}

	@Test
	func generatedModule_unitesUnitsAndKeepsImportsPerFile_whenSeveralFilesAreParsedOneAfterAnother() {
		var module = GraphFuzzerGeneratedModule(units: [:], importsByFileName: [:], warnings: [])

		GraphFuzzerGeneratedModule.parsingGeneratedFile("#if canImport(Alpha)\nimport Alpha\n#endif\n\nextension S12_Root0 {\n}\n", named: "S12_Root0+SafeDI.swift", into: &module)
		GraphFuzzerGeneratedModule.parsingGeneratedFile("#if canImport(Alpha)\nimport Alpha\n#endif\n#if canImport(Beta)\nimport Beta\n#endif\n\n#if DEBUG\nextension S12_T1 {\n    static func mock() -> S12_T1 {\n    }\n}\n#endif\n", named: "S12_T1+SafeDIMock.swift", into: &module)
		GraphFuzzerGeneratedModule.parsingGeneratedFile("#if canImport(Alpha)\nimport Alpha\n#endif\n", named: "SafeDIMockConfiguration.swift", into: &module)

		#expect(module.importsByFileName == [
			"S12_Root0+SafeDI.swift": ["import Alpha"],
			"S12_T1+SafeDIMock.swift": ["import Alpha", "import Beta"],
			"SafeDIMockConfiguration.swift": ["import Alpha"],
		])
		#expect(module.units.keys.sorted() == ["S12_Root0+SafeDI.swift", "S12_T1+SafeDIMock.swift"])
	}

	@Test
	func multiModuleDifference_isNil_whenPluginReportsSkippedModulesDiagnosticsAtFirstConsumerThatGenerates() {
		let diagnostics = "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`."
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: diagnostics)),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Gamma", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])

		// `Beta` does not depend on `Alpha`, so its generate never reads `Alpha`'s files; `Gamma`'s is the first that does.
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == nil)
	}

	@Test
	func multiModuleDifference_reportsVerdict_whenConsumerThatDependsOnSkippedModuleAcceptsIt() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:]))),
		])

		// `Beta` depends on `Alpha`, so its generate read `Alpha`'s files and should have reported the defect.
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], ["Alpha"]])) == "its verdict for module Alpha (.moduleInfo rejects it, while .swiftPackagePlugin plans no output for it and accepts module Beta, which depends on it)")
	}

	@Test
	func multiModuleDifference_isNil_whenNoModuleThePluginGeneratesDependsOnTheModuleItSkipsAndModuleInfoRejects() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}"]))),
			.init(moduleName: "Beta", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Beta/S12_T7.swift:1:1: error: Found multiple")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}"]))),
			.init(moduleName: "Beta", kind: .skipped),
			.init(moduleName: "Gamma", kind: .accepted(Self.generatedModule(units: [:]))),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == nil)
	}

	@Test
	func multiModuleDifference_namesFirstModuleAndUnitWhoseCodeDiffers_whenUnitsOfSeveralModulesDiffer() {
		let rootCode = "extension S12_Root0 {\n    public convenience init() {\n    }\n}"
		let mockCode = "#if DEBUG\nextension S12_T1 {\n    static func mock() -> S12_T1 {\n    }\n}\n#endif"
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_T1+SafeDIMock.swift": mockCode]))),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
		])
		func pluginOutcome(mockCode: String, rootCode: String) -> GraphFuzzerMultiModuleOutcome {
			GraphFuzzerMultiModuleOutcome(verdicts: [
				.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_T1+SafeDIMock.swift": mockCode]))),
				.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
			])
		}
		let modules = Self.chainOfModules(dependencies: [[], ["Alpha"]])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockCode: mockCode, rootCode: rootCode), modules: modules) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockCode: mockCode + "\n", rootCode: rootCode + "\n"), modules: modules) == "the generated mock code of module Alpha, in S12_T1+SafeDIMock.swift")
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockCode: mockCode, rootCode: rootCode + "\n"), modules: modules) == "the generated dependency tree code of module Beta, in S12_Root0+SafeDI.swift")
	}

	@Test
	func multiModuleDifference_namesPluginFileWhoseImportsDiffer_whenOneOfTwoPluginFilesLacksAnImport() {
		// The combined file imports what the dependency trees and the mocks need together; without `#if`, every one of
		// the plugin's files must import the same, so a mock file lacking an import is not covered by a tree file having it.
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:], importsByFileName: ["Beta.swift": ["import Alpha"]]))),
		])
		func pluginOutcome(mockFileImports: [String]) -> GraphFuzzerMultiModuleOutcome {
			GraphFuzzerMultiModuleOutcome(verdicts: [
				.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
				.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:], importsByFileName: [
					"S12_Root0+SafeDI.swift": ["import Alpha"],
					"S12_T1+SafeDIMock.swift": mockFileImports,
				]))),
			])
		}
		let modules = Self.chainOfModules(dependencies: [[], ["Alpha"]])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockFileImports: ["import Alpha"]), modules: modules) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome(mockFileImports: []), modules: modules) == "the imports of module Beta's generated file S12_T1+SafeDIMock.swift ( under .swiftPackagePlugin, against import Alpha under .moduleInfo)")
	}

	@Test
	func multiModuleDifference_reportsModuleThePluginSkips_onlyWhenModuleInfoGeneratesCodeForIt() {
		let modules = Self.chainOfModules(dependencies: [[]])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .skipped)])

		#expect(GraphFuzzerMultiModuleOutcome.difference(
			betweenModuleInfo: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:])))]),
			andPlugin: pluginOutcome,
			modules: modules,
		) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(
			betweenModuleInfo: GraphFuzzerMultiModuleOutcome(verdicts: [.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_T1+SafeDIMock.swift": "#if DEBUG\nextension S12_T1 {\n}\n#endif"])))]),
			andPlugin: pluginOutcome,
			modules: modules,
		) == "the generated units of module Alpha (S12_T1+SafeDIMock.swift under .moduleInfo, while .swiftPackagePlugin plans no output for it)")
	}

	@Test
	func multiModuleDifference_reportsVerdict_whenOnlyOneIntegrationRejectsAModule() {
		let modules = Self.chainOfModules(dependencies: [[], ["Alpha"]])
		let accepted = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:]))),
		])
		let rejectedBeta = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Beta", kind: .rejected(diagnostics: "error")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: accepted, andPlugin: rejectedBeta, modules: modules) == "its verdict for module Beta (.moduleInfo accepts it, .swiftPackagePlugin rejects it)")
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: rejectedBeta, andPlugin: accepted, modules: modules) == "its verdict for module Beta (.moduleInfo rejects it, .swiftPackagePlugin accepts it)")
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: rejectedBeta, andPlugin: rejectedBeta, modules: modules) == nil)
	}

	@Test
	func multiModuleDifference_namesUnitsOfBothIntegrations_whenOnlyThePluginGeneratesAUnit() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}"]))),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [
				"S12_Root0+SafeDI.swift": "extension S12_Root0 {\n}",
				"S12_T1+SafeDIMock.swift": "#if DEBUG\nextension S12_T1 {\n}\n#endif",
			]))),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[]])) == "the generated units of module Alpha (S12_Root0+SafeDI.swift under .moduleInfo, S12_Root0+SafeDI.swift, S12_T1+SafeDIMock.swift under .swiftPackagePlugin)")
	}

	@Test
	func multiModuleDifference_reportsWarnings_whenOnlyTheWarningsDiffer() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:], warnings: ["<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: warning: one", "<fixture-directory>/Graph/Sources/Alpha/S12_T2.swift:8:2: warning: two"]))),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:], warnings: ["<fixture-directory>/Graph/Sources/Alpha/S12_T2.swift:8:2: warning: two", "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: warning: one"]))),
		])
		let otherWarningsPluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:], warnings: ["<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: warning: one"]))),
		])
		let modules = Self.chainOfModules(dependencies: [[]])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: modules) == nil)
		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: otherWarningsPluginOutcome, modules: modules) == "the warnings of module Alpha")
	}

	@Test
	func multiModuleDifference_reportsDiagnostics_whenBothIntegrationsRejectAModuleWithOtherDiagnostics() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:7:2: error: first")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:7:2: error: second")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[]])) == "the diagnostics of module Alpha")
	}

	@Test
	func multiModuleDifference_reportsDiagnosticsNamingConsumer_whenConsumerReportsOtherDiagnosticsForSkippedModule() {
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .skipped),
			.init(moduleName: "Gamma", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Gamma/S12_Root0.swift:8:2: error: another")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == "the diagnostics of module Alpha (which .swiftPackagePlugin reports in module Gamma)")
	}

	@Test
	func multiModuleDifference_isNil_whenPluginRejectsModuleNotDependingOnSkippedOneBeforeAnyConsumerGenerates() {
		// `Beta` does not depend on `Alpha`, and the module-info integration never ran it, so its rejection is not
		// compared, and `Gamma`, the consumer that would report `Alpha`'s defect, was never reached.
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Beta/S12_Root0.swift:8:2: error: another")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], [], ["Alpha"]])) == nil)
	}

	@Test
	func multiModuleDifference_comparesFirstConsumerThatGenerates_whenAnEarlierConsumerIsSkipped() {
		// `Beta` depends on `Alpha` but plans no output, so the plugin first reads `Alpha`'s files in `Gamma`'s generate.
		let moduleInfoOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .rejected(diagnostics: "/a/<fixture-directory>/Graph/Sources/Alpha/S12_T7.swift:1:1: error: Found multiple @Instantiable types or extensions that fulfill `S12_T7Protocol`.")),
		])
		let pluginOutcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .skipped),
			.init(moduleName: "Beta", kind: .skipped),
			.init(moduleName: "Gamma", kind: .rejected(diagnostics: "/b/<fixture-directory>/Graph/Sources/Gamma/S12_Root0.swift:8:2: error: another")),
		])

		#expect(GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: Self.chainOfModules(dependencies: [[], ["Alpha"], ["Alpha", "Beta"]])) == "the diagnostics of module Alpha (which .swiftPackagePlugin reports in module Gamma)")
	}

	@Test
	func failure_reportsIntegrationsDiffer_whenPluginWritesADependencysRootAgainWithOtherCode() {
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: []),
		])
		let rootCode = "extension S12_Root0 {\n    public convenience init() {\n    }\n}"
		let outcome = GraphFuzzerMultiModuleOutcome(verdicts: [
			.init(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: [:]))),
			.init(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
		])
		let runs = GraphFuzzerMultiModuleRuns(
			seed: 12,
			partition: GraphFuzzerPartition.partition(of: fixture, moduleCount: 2),
			renaming: nil,
			moduleInfoOutcome: outcome,
			pluginOutcome: outcome,
			regeneratedRoots: [GraphFuzzerRegeneratedRoot(
				consumerModuleName: "Beta",
				declaringModuleName: "Alpha",
				rootTypeName: "S12_Root0",
				difference: "has Alpha's root S12_Root0 written again by the .swiftPackagePlugin integration in module Beta with other code than Alpha's own:\n\(rootCode)\n\nagainst\n\(rootCode)",
			)],
		)

		let failure = runs.failure

		#expect(failure?.kind == .integrationsDiffer)
		#expect(failure.map { String($0.details.prefix { $0 != "\n" }) } == "Split into modules, the graph has Alpha's root S12_Root0 written again by the .swiftPackagePlugin integration in module Beta with other code than Alpha's own:")
	}

	@Test
	func removingRegeneratedRoots_removesRootWithoutDifference_whenConsumerWritesDeclaringModulesRootAgainIdentically() {
		let rootCode = "extension S12_Root0 {\n    public convenience init() {\n    }\n}"
		var verdicts = [
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode, "S12_Root1+SafeDI.swift": "extension S12_Root1 {\n}"]))),
		]

		let regeneratedRoots = GraphFuzzerMultiModuleProperty.removingRegeneratedRoots(
			from: &verdicts,
			moduleNameByDeclaredTypeName: ["S12_Root0": "Alpha", "S12_Root1": "Beta"],
			dependenciesByModuleName: ["Alpha": [], "Beta": ["Alpha"]],
		)

		#expect(regeneratedRoots == [GraphFuzzerRegeneratedRoot(consumerModuleName: "Beta", declaringModuleName: "Alpha", rootTypeName: "S12_Root0", difference: nil)])
		#expect(verdicts == [
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root1+SafeDI.swift": "extension S12_Root1 {\n}"]))),
		])
	}

	@Test
	func removingRegeneratedRoots_reportsDifferenceNamingRootAndBothModules_whenConsumerWritesRootWithOtherCode() {
		let rootCode = "extension S12_Root0 {\n    public convenience init() {\n    }\n}"
		var verdicts = [
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode + "\n"]))),
		]

		let regeneratedRoots = GraphFuzzerMultiModuleProperty.removingRegeneratedRoots(
			from: &verdicts,
			moduleNameByDeclaredTypeName: ["S12_Root0": "Alpha"],
			dependenciesByModuleName: ["Alpha": [], "Beta": ["Alpha"]],
		)

		#expect(regeneratedRoots == [GraphFuzzerRegeneratedRoot(
			consumerModuleName: "Beta",
			declaringModuleName: "Alpha",
			rootTypeName: "S12_Root0",
			difference: "has Alpha's root S12_Root0 written again by the .swiftPackagePlugin integration in module Beta with other code than Alpha's own:\n\(rootCode)\n\nagainst\n\(rootCode)",
		)])
		#expect(verdicts[1] == GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: [:]))))
	}

	@Test
	func removingRegeneratedRoots_keepsRoot_whenDeclaringModuleIsNotADependencyOfTheConsumer() {
		let rootCode = "extension S12_Root0 {\n    public convenience init() {\n    }\n}"
		var verdicts = [
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Alpha", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
			GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: "Beta", kind: .accepted(Self.generatedModule(units: ["S12_Root0+SafeDI.swift": rootCode]))),
		]
		let verdictsBefore = verdicts

		let regeneratedRoots = GraphFuzzerMultiModuleProperty.removingRegeneratedRoots(
			from: &verdicts,
			moduleNameByDeclaredTypeName: ["S12_Root0": "Alpha"],
			dependenciesByModuleName: ["Alpha": [], "Beta": []],
		)

		#expect(regeneratedRoots == [])
		#expect(verdicts == verdictsBefore)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func multiModuleProperty_meetsAndRemovesRegeneratedRoot_whenDependencyDeclaresARoot() async throws {
		// `Root0` and `T1` share `Alpha`; `Root1`, in `Beta`, instantiates `T1`, so under the plugin `Beta`'s CSV holds
		// `Alpha`'s files and its `scan` plans `Root0`'s dependency tree again.
		let fixture = GraphFuzzerFixture(seed: 12, swiftFileContent: [
			Self.typeSource(named: "S12_Root0", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_Root1", arguments: "isRoot: true", properties: ["@Instantiated let t1: S12_T1"]),
			Self.typeSource(named: "S12_T1", properties: []),
		])
		let partition = GraphFuzzerPartition.partition(of: fixture, moduleCount: 2)
		#expect(partition.modules.map(\.fileIndices) == [[0, 2], [1]])

		let runs = try await GraphFuzzerMultiModuleProperty.runs(of: fixture, partition: partition)

		#expect(runs.regeneratedRoots == [GraphFuzzerRegeneratedRoot(consumerModuleName: "Beta", declaringModuleName: "Alpha", rootTypeName: "S12_Root0", difference: nil)])
		#expect(runs.failure == nil)
		#expect(Self.unitNamesByModuleName(of: runs.pluginOutcome) == ["Alpha": ["S12_Root0+SafeDI.swift"], "Beta": ["S12_Root1+SafeDI.swift"]])
		#expect(Self.unitNamesByModuleName(of: runs.moduleInfoOutcome) == ["Alpha": ["S12_Root0+SafeDI.swift"], "Beta": ["S12_Root1+SafeDI.swift"]])
	}

	@Test
	func reducingFixtureRootPaths_reducesEachSpellingOfTheFixtureRoot_whereverAPathAppears() {
		let unresolved = "/var/folders/1f/3dqdr7xs2yn_90rwj5xxhh780000gn/T/72FAAFF2-C685-4DE6-A860-FA097D2CFDB8/Graph/Sources/Alpha/S12_T1.swift"
		let resolved = "/private/var/folders/1f/3dqdr7xs2yn_90rwj5xxhh780000gn/T/72FAAFF2-C685-4DE6-A860-FA097D2CFDB8/Graph/Sources/Alpha/S12_T1.swift"
		let linux = "/tmp/72FAAFF2-C685-4DE6-A860-FA097D2CFDB8/Graph/Sources/Alpha/S12_T1.swift"

		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "\(unresolved):8:2: error: one") == "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "\(resolved):8:2: error: one") == "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "\(linux):8:2: error: one") == "<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "            #sourceLocation(file: \"\(resolved)\", line: 8)") == "            #sourceLocation(file: \"<fixture-directory>/Graph/Sources/Alpha/S12_T1.swift\", line: 8)")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "chain: S12_Root0 -> S12_T1 at \(unresolved) and \(resolved)") == "chain: S12_Root0 -> S12_T1 at <fixture-directory>/Graph/Sources/Alpha/S12_T1.swift and <fixture-directory>/Graph/Sources/Alpha/S12_T1.swift")
		#expect(GraphFuzzerMultiModuleProperty.reducingFixtureRootPaths(in: "/Users/someone/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one") == "/Users/someone/Graph/Sources/Alpha/S12_T1.swift:8:2: error: one")
	}

	@Test
	func finding_isKnownIssue_whenIntegrationsDifferAsDocumented() {
		let knownIssue = GraphFuzzerKnownIssue(
			reason: "A shape whose mock differs between the integrations",
			signatures: [.integrationsDiffer(containing: "the generated mock code")],
			seeds: [12],
		)
		let failure = GraphFuzzerFailure(
			seed: 12,
			kind: .integrationsDiffer,
			details: "Split into modules, the graph differs between the .moduleInfo and .swiftPackagePlugin integrations in the generated mock code of module Alpha, in S12_T0+SafeDIMock.swift.\nModules:\n…",
		)
		let verdictFailure = GraphFuzzerFailure(
			seed: 12,
			kind: .integrationsDiffer,
			details: "Split into modules, the graph differs between the .moduleInfo and .swiftPackagePlugin integrations in its verdict for module Alpha.\nModules:\nthe generated mock code",
		)

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
		#expect(GraphFuzzerFinding(failure: verdictFailure, knownIssue: knownIssue) == .failure(verdictFailure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_generateTheSameCodeUnderBothMultiModuleIntegrations_whenSplitAcrossModules() async throws {
		for result in try await smokeResults.value {
			#expect(result.multiModuleRuns.count == GraphFuzzerOracle.multiModuleRenamings.count)
			for failure in result.multiModuleFailures {
				Issue.record(failure.issueComment(fixture: result.fixture))
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_includeAcceptedAndRejectedGraphsSplitIntoSeveralModules_whenRunThroughMultiModuleIntegrations() async throws {
		let runs = try await smokeResults.value.flatMap(\.multiModuleRuns).filter { $0.renaming == nil }

		// Some graphs are rejected with several modules, so that the diagnostics of a split graph are compared too.
		#expect(runs.contains { $0.isAccepted && $0.partition.modules.count > 1 })
		#expect(runs.contains { !$0.isAccepted && $0.partition.modules.count > 1 })
	}

	/// The source of a `final class` `@Instantiable` type, as the generator emits one, with its helper types when asked.
	private static func typeSource(named name: String, arguments: String? = nil, properties: [String], declaresHelperTypes: Bool = false) -> String {
		var lines = [arguments.map { "@Instantiable(\($0))" } ?? "@Instantiable", "public final class \(name): Instantiable {"]
		if properties.isEmpty {
			lines.append("\tpublic init() {}")
		} else {
			let parameters = properties.map { $0.components(separatedBy: " let ")[1] }
			lines.append("\tpublic init(\(parameters.joined(separator: ", "))) {")
			lines += parameters.map { "\t\tself.\($0.prefix { $0 != ":" }) = \($0.prefix { $0 != ":" })" }
			lines.append("\t}")
			lines.append("")
			lines += properties.map { "\t\($0)" }
		}
		lines.append("}")
		if declaresHelperTypes {
			let erasedName = name.replacingOccurrences(of: "_T", with: "_AnyT")
			lines += ["", "public protocol \(name)Protocol: AnyObject {}", "", "public final class \(erasedName) {", "\tpublic init(_ value: \(name)) {", "\t\tself.value = value", "\t}", "", "\tpublic let value: \(name)", "}"]
		}
		return lines.joined(separator: "\n") + "\n"
	}

	private static func generatedModule(units: [String: String], importsByFileName: [String: [String]] = [:], warnings: [String] = []) -> GraphFuzzerGeneratedModule {
		GraphFuzzerGeneratedModule(units: units, importsByFileName: importsByFileName, warnings: warnings)
	}

	/// The names of the units each module's generated code holds, for a module the integration generated.
	private static func unitNamesByModuleName(of outcome: GraphFuzzerMultiModuleOutcome) -> [String: [String]] {
		Dictionary(uniqueKeysWithValues: outcome.verdicts.compactMap { verdict in
			switch verdict.kind {
			case let .accepted(module):
				(verdict.moduleName, module.units.keys.sorted())
			case .skipped, .rejected:
				nil
			}
		})
	}

	/// Modules `Alpha`, `Beta`, … with the given dependencies, each a closure over the modules before it.
	private static func chainOfModules(dependencies: [[String]]) -> [GraphFuzzerPartition.Module] {
		dependencies.enumerated().map { index, dependencies in
			GraphFuzzerPartition.Module(name: GraphFuzzerPartition.moduleNames[index], fileIndices: [index], referencedModuleNames: dependencies, dependencies: dependencies)
		}
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

		// Pin the whole corpus the long run covers, which the ordinary suite's hash covers only a sample of, and the
		// partition of every graph of it across modules, and check that no graph uses a label beginning with
		// `__safeDI_`, which the generated builder functions use.
		var generatedCorpusHash = GraphFuzzerHash()
		var partitionedCorpusHash = GraphFuzzerHash()
		var graphCountByModuleCount = [Int](repeating: 0, count: GraphFuzzerPartition.moduleNames.count + 1)
		// The graphs whose two integrations combine declarations in different orders: see `GraphFuzzerPartition.moduleNames`.
		var deltaDependsOnGammaCount = 0
		for seed in 0..<UInt64(Self.corpusSeedCount) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed)
			generatedCorpusHash.combine(fixture.description)
			let partition = GraphFuzzerPartition.partition(of: fixture)
			partitionedCorpusHash.combine(partition.description)
			graphCountByModuleCount[partition.modules.count] += 1
			if partition.modules.last?.name == "Delta", partition.modules.last?.dependencies.contains("Gamma") == true {
				deltaDependsOnGammaCount += 1
			}
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
		if partitionedCorpusHash.value != Self.corpusPartitionHash {
			reportProblem("The partition of the graphs for seeds 0..<\(Self.corpusSeedCount) across modules changed (partition hash \(Self.hexadecimal(partitionedCorpusHash.value)), pinned \(Self.hexadecimal(Self.corpusPartitionHash))). Re-derive the known issues and the pinned partition hashes.")
		}
		report.append("partitions " + graphCountByModuleCount.indices.dropFirst().map { "\($0):\(graphCountByModuleCount[$0])" }.joined(separator: " ") + " delta-depends-on-gamma:\(deltaDependsOnGammaCount)")

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
								multiModuleRuns: results[index].multiModuleRuns,
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
							for multiModuleFailure in result.multiModuleFailures {
								report.append("multimodule \(seed) \(multiModuleFailure.details.prefix { $0 != "\n" })")
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

	/// The ordinary suite's batch: seeds 12, 25, 62, 582, 691, 705, 731, 930, 2420, and 2611, whose graphs the tool accepts,
	/// with the same results under every `GraphFuzzerRenaming`, and which between them exercise every feature (seed 25's
	/// graph has a chain of aliases through an `onlyIfAvailable` alias; seed 731's has a chain through an
	/// `onlyIfAvailable` alias of a sibling's optional form; seed 2420's has such a chain through a child scope; the graphs of
	/// seeds 582 and 705 receive a constant of a type that is not `@Instantiable` beneath the type that instantiates it;
	/// the mocked owner of such a constant in seed 2611 receives a type that receives it as a `LazilyInstantiated`, and
	/// in seed 12 lazily instantiates it as one wrapper while the type it receives receives the other kind), and
	/// seeds 14, 4224, and 4516, whose graphs it rejects (seed 4224's with the dependency cycle through a chain through a
	/// child scope, because the sibling's type receives the other sibling; seed 4516's because a declaration in the tree
	/// of a dependency a mock builds beside the mocked type hides a receive beneath it). It is small because compiling
	/// generated code is what the fuzzer costs; ci.yml fuzzes the whole corpus on every pull request. Compiling the batch
	/// is one `swiftc` invocation when nothing fails.
	static let smokeSeeds: [UInt64] = [12, 14, 25, 62, 582, 691, 705, 731, 930, 2_420, 2_611, 4_224, 4_516]

	static let smokeAndKnownIssueFixtureHash: UInt64 = 0x14EAA9C0A0F05B57

	/// The `GraphFuzzerPartition` of the smoke and known-issue seeds' graphs, as `partitionHash(forSeeds:)` hashes
	/// them; `corpusPartitionHash` pins the whole corpus's. The partition draws nothing from the seed, so changing it
	/// changes neither the graphs nor the pins on them: these pins make a change to the partition deliberate. They
	/// move with the generator and, this one, with the smoke and known-issue seeds too, as the fixture hashes do.
	static let smokeAndKnownIssuePartitionHash: UInt64 = 0xB135ED5AA7AC45A5

	/// The corpus, seeds `0..<corpusSeedCount`, which ci.yml fuzzes on every pull request and push to main and
	/// `SAFEDI_GRAPH_FUZZER_ITERATIONS=corpus` selects. `knownIssues` lists every one that fails.
	static let corpusSeedCount = 5_000

	static let corpusFixtureHash: UInt64 = 0xDD638CCC778015F8

	static let corpusPartitionHash: UInt64 = 0x8D735CCBE377A592

	/// How many of the corpus's graphs the tool accepts, and which ones, as a `GraphFuzzerSeedSetSum`, which
	/// shards of the corpus can add up.
	static let corpusAcceptedSeedCount = 2_299
	static let corpusAcceptedSeedsSum: UInt64 = 0x62F41F76B0229D38

	/// Seeds in `0..<corpusSeedCount` whose graphs fail today, grouped by shape. Every fix first adds a graph of
	/// its shape, reduced, as a hand-written regression test; removing the seeds is the last step of the fix.
	static let knownIssues: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: "A mock's API follows the order of type names or labels: which back-edge of a lazy cycle loses its override, which promoted sibling is passed nil, and the order of overrides",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock code")],
			seeds: [
				3, 35, 36, 45, 55, 77, 107, 114, 131, 157, 168, 209, 223, 233, 241, 281,
				309, 311, 364, 371, 380, 381, 383, 390, 431, 448, 450, 473, 476, 515, 545, 548,
				567, 593, 617, 630, 632, 680, 714, 728, 732, 751, 768, 774, 785, 786, 808, 833,
				836, 847, 886, 903, 912, 940, 948, 975, 987, 1_004, 1_029, 1_035, 1_042, 1_044, 1_061, 1_064,
				1_072, 1_075, 1_084, 1_092, 1_139, 1_140, 1_145, 1_147, 1_215, 1_236, 1_289, 1_300, 1_322, 1_329, 1_335, 1_352,
				1_362, 1_369, 1_372, 1_432, 1_433, 1_441, 1_453, 1_464, 1_492, 1_496, 1_504, 1_524, 1_525, 1_531, 1_535, 1_563,
				1_567, 1_602, 1_633, 1_646, 1_664, 1_675, 1_695, 1_742, 1_781, 1_784, 1_804, 1_817, 1_853, 1_857, 1_867, 1_896,
				1_938, 1_970, 1_972, 2_017, 2_051, 2_057, 2_083, 2_084, 2_123, 2_149, 2_152, 2_165, 2_201, 2_211, 2_234, 2_249,
				2_270, 2_277, 2_287, 2_296, 2_316, 2_325, 2_335, 2_337, 2_348, 2_389, 2_403, 2_430, 2_432, 2_437, 2_444, 2_456,
				2_484, 2_518, 2_553, 2_555, 2_577, 2_630, 2_637, 2_667, 2_704, 2_731, 2_741, 2_791, 2_808, 2_835, 2_841, 2_845,
				2_874, 2_902, 2_914, 2_916, 3_004, 3_023, 3_064, 3_074, 3_075, 3_091, 3_132, 3_134, 3_180, 3_183, 3_215, 3_221,
				3_225, 3_241, 3_252, 3_298, 3_306, 3_329, 3_344, 3_361, 3_397, 3_430, 3_439, 3_470, 3_491, 3_504, 3_506, 3_513,
				3_526, 3_533, 3_534, 3_537, 3_577, 3_582, 3_588, 3_596, 3_600, 3_602, 3_620, 3_645, 3_648, 3_661, 3_692, 3_699,
				3_707, 3_715, 3_723, 3_741, 3_750, 3_775, 3_776, 3_805, 3_823, 3_843, 3_894, 3_915, 3_994, 4_044, 4_068, 4_102,
				4_107, 4_110, 4_117, 4_122, 4_125, 4_156, 4_177, 4_191, 4_192, 4_196, 4_206, 4_213, 4_217, 4_227, 4_254, 4_260,
				4_266, 4_281, 4_304, 4_344, 4_371, 4_378, 4_393, 4_404, 4_420, 4_424, 4_428, 4_496, 4_515, 4_534, 4_541, 4_545,
				4_567, 4_619, 4_634, 4_637, 4_640, 4_642, 4_648, 4_664, 4_666, 4_707, 4_716, 4_717, 4_729, 4_775, 4_776, 4_781,
				4_783, 4_786, 4_795, 4_834, 4_857, 4_859, 4_891, 4_904, 4_918, 4_922, 4_944, 4_947, 4_955, 4_963, 4_996,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "SafeDIMockConfiguration.swift declares its extensions in the order of the roots that reach them",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock configuration code")],
			seeds: [
				69, 170, 173, 310, 348, 393, 434, 471, 497, 595, 790, 929, 1_138, 1_185, 1_202, 1_400,
				1_560, 1_571, 1_650, 1_660, 1_691, 1_730, 1_769, 1_786, 1_790, 1_836, 1_992, 2_011, 2_054, 2_186, 2_254, 2_937,
				3_028, 3_482, 3_510, 3_702, 3_789, 3_847, 3_931, 3_966, 4_535, 4_602, 4_613, 4_631, 4_643, 4_974, 4_975,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "A type receives a label as one type while a type built inside it receives the label as another, and the mock rebinds the first under the label inside the receiver's builder function, where the second then reads it",
			signatures: [.compilerError(containing: "cannot convert value of type")],
			seeds: [4_747],
		),
		GraphFuzzerKnownIssue(
			reason: "A required receive in the tree of a dependency a mock promotes is handed the mocked type's onlyIfAvailable alias of that property, which is optional",
			signatures: [.compilerError(containing: "must be unwrapped to a value of type")],
			seeds: [4_628],
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

	static func partitionHash(forSeeds seeds: [UInt64]) -> UInt64 {
		var hash = GraphFuzzerHash()
		for seed in seeds {
			hash.combine(GraphFuzzerPartition.partition(of: GraphFuzzerGenerator.fixture(forSeed: seed)).description)
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
	/// finding; `renamed <seed> <summary>` and `multimodule <seed> <summary>` for each renamed or partitioned run
	/// that gives other results, whether or not the graph fails another way; `problem <text>` for anything wrong
	/// with the run itself; `partitions …` with how many corpus graphs are split into each number of modules and how
	/// many have a `Delta` depending on `Gamma`, whose two integrations combine declarations in different orders; and
	/// `completed …` at the end.
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
