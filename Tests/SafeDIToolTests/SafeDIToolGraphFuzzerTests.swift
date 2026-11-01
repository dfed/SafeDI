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
		// Features are read from the emitted source, so a generator that stops emitting one fails here. A generator
		// feature's own feature is drawn only with the generator feature on, which the seam smoke batch checks.
		let features = try await smokeResults.value
			.filter { $0.isAccepted && $0.failure == nil }
			.reduce(into: Set<GraphFuzzerFeature>()) { $0.formUnion(GraphFuzzerFeature.features(of: $1.fixture)) }
		#expect(Set(GraphFuzzerFeature.baseCases).subtracting(features).sorted() == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamSmokeSeeds_produceNoFailures_whenRunThroughToolAndCompiler() async throws {
		for result in try await seamSmokeResults.value {
			if let failure = result.failure {
				Issue.record(failure.issueComment(fixture: result.fixture))
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamSmokeSeeds_exerciseSeamFeature_inGraphsTheToolAccepts() async throws {
		// A graph drawn with the `generateDependencyTree` feature declares a seam, and the smoke batch holds graphs the
		// tool accepts whose generated code, read from what the oracle compiled, between them shows every
		// `GraphFuzzerSeamOutputFeature`, and one graph it rejects.
		let results = try await seamSmokeResults.value
		let acceptedResults = results.filter { $0.isAccepted && $0.failure == nil }

		#expect(acceptedResults.allSatisfy { GraphFuzzerFeature.features(of: $0.fixture).contains(.generateDependencyTree) })
		#expect(acceptedResults.count >= 2, "Accepted \(acceptedResults.count) of \(Self.seamSmokeSeeds.count) graphs")
		let outputFeatures = acceptedResults.reduce(into: Set<GraphFuzzerSeamOutputFeature>()) { features, result in
			if case let .accepted(generatedFiles, _) = result.outcome {
				features.formUnion(GraphFuzzerFeature.seamOutputFeatures(of: result.fixture, generatedFiles: generatedFiles))
			}
		}
		#expect(Set(GraphFuzzerSeamOutputFeature.allCases).subtracting(outputFeatures).sorted() == [])
		// Graphs with a hole whose generated code shows every `GraphFuzzerHoleOutputFeature`.
		let holeOutputFeatures = acceptedResults.reduce(into: Set<GraphFuzzerHoleOutputFeature>()) { features, result in
			if case let .accepted(generatedFiles, _) = result.outcome {
				features.formUnion(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: generatedFiles))
			}
		}
		#expect(Set(GraphFuzzerHoleOutputFeature.allCases).subtracting(holeOutputFeatures).sorted() == [])
		// Graphs split across modules – with a caller in another package, and with a caller or a seam's module run without
		// its package's name – among those the tool accepts, so that the batch compiles each module of a split graph and
		// the callers of each package configuration.
		let drawFeatures = acceptedResults.reduce(into: Set<GraphFuzzerSeamDrawFeature>()) { $0.formUnion(GraphFuzzerFeature.seamDrawFeatures(of: $1.fixture)) }
		#expect(Set([GraphFuzzerSeamDrawFeature.moduleSplit, .otherPackageCaller, .samePackageCallerRunWithoutPackageName, .seamModuleRunWithoutPackageName]).subtracting(drawFeatures).sorted() == [])
		#expect(results.contains { !$0.isAccepted && $0.failure == nil }, "Rejected none of \(Self.seamSmokeSeeds.count) graphs")
	}

	@Test
	func seamCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool() throws {
		// Each shape `addingSeam` draws lands in exactly the pinned number of the seam corpus's graphs, read from
		// their source: the draw is deterministic, so a change in a shape's share is a reviewed diff, as the
		// accepted-seed pins are, and a draw that stops landing – a filter that empties its sources, a roll that
		// never fires – fails here rather than in a review of the corpus. Every shape has a pin.
		var counts = [GraphFuzzerSeamDrawFeature: Int]()
		for seed in 0..<UInt64(Self.seamCorpusSeedCount) {
			for feature in GraphFuzzerFeature.seamDrawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])) {
				counts[feature, default: 0] += 1
			}
		}
		for feature in GraphFuzzerSeamDrawFeature.allCases {
			let pinnedCount = try #require(Self.seamCorpusDrawFeatureCounts[feature], "\(feature.rawValue) has no pinned count")
			#expect(counts[feature, default: 0] == pinnedCount, "\(feature.rawValue) drawn in \(counts[feature, default: 0]) graphs")
		}
	}

	@Test
	func isSeamOnlyRejection_tellsSeamsOwnErrorsFromInlinedValidations_whenDiagnosticsAreClassified() {
		// The differential oracle counts a rejection as a seam's own only when every error is reported about the
		// seam's generated initializer or a call of it.
		let collision = "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.\n/F/A.swift:7:5: note: `A` receives `x: X` here."
		let missingModuleInfo = "/F/Screen.swift:1:1: error: SafeDI cannot generate a call to the initializer SafeDI generated for `Screen` in module `Core`: that initializer takes what the type's dependency tree needs from the declarations `Core` sees, which include module `Base`'s, and this run was not given `Base`'s SafeDI module info."
		let unfulfillable = "/F/A.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Screen -> A."
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: collision, seamTypeNames: ["Screen"]))
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: missingModuleInfo, seamTypeNames: ["Screen"]))
		let parameterCapture = "/F/Detail.swift:7:5: error: @Received property `cache: LazilyInstantiated<Cache>?` cannot be received inside a `@Sendable` function in chain: Screen -> Detail. SafeDI builds `detailBuilder: SendableInstantiator<Detail>` on `Screen` in a `@Sendable` function, which cannot capture `cache: LazilyInstantiated<Cache>?`, which the tree of `Screen` receives from outside it, because `LazilyInstantiated<Cache>` is not `Sendable`."
		let declaredCapture = "/F/Detail.swift:7:5: error: @Received property `cache: Cache` cannot be received inside a `@Sendable` function in chain: Root -> Detail. SafeDI builds `detailBuilder: SendableInstantiator<Detail>` on `Root` in a `@Sendable` function, which cannot capture `cache: LazilyInstantiated<Cache>` on `Root`, because `LazilyInstantiated<Cache>` is not `Sendable`."
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: parameterCapture, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: declaredCapture, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: unfulfillable, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: "\(collision)\n\(unfulfillable)", seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: "", seamTypeNames: ["Screen"]))
		// A caller's error that it holds a value its tier omits is a seam's own only in a graph split across modules: a
		// seam a graph in one module calls is called at its narrowest tier, which omits nothing.
		let omittedValue = "/F/Host.swift:3:2: error: `Host` provides `theme: Theme`, but the `public` initializer SafeDI generated for `Screen` in module `Feature`, the narrowest one module `App` can call, does not take it."
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: omittedValue, seamTypeNames: ["Screen"]))
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: omittedValue, seamTypeNames: ["Screen"], excusingOmittedValues: true))
		// A hidden-label error in a chain that starts at a seam is the seam's: inline reports it only from a root that
		// provides the property, so a caller that holds nothing builds the graph inline.
		let hiddenAtSeam = "/F/Reader.swift:7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix."
		let hiddenAtRoot = "/F/Reader.swift:7:5: error: @Received property `token: Secret?` is hidden in chain: Root -> Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix."
		#expect(GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: hiddenAtSeam, seamTypeNames: ["Screen"]))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: hiddenAtSeam, seamTypeNames: []))
		#expect(!GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: hiddenAtRoot, seamTypeNames: ["Screen"]))
	}

	@Test
	func differentialFailure_reportsSeed_whenSeamRejectsGraphWithInlinedValidationsErrorAndInlineAccepts() {
		// A graph the tool rejects with the seam declared, with an error of the inlined validation, and accepts with
		// no seam is a defect of the seam world; one it rejects with a seam's own error is what the seam rules
		// reject, and one it rejects inline too is no seam's doing.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0, features: [.generateDependencyTree])
		let unfulfillable = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/A.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Screen -> A.")
		let collision = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.")
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let defect = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: unfulfillable, secondOutcome: unfulfillable, inlineOutcome: accepted)
		#expect(defect.differentialFailure?.kind == .seamRejectsGraphInlineAccepts)
		#expect(defect.differentialFailure?.details == "With the seam:\n/F/A.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Screen -> A.\nWithout it, the tool accepts the graph.")
		let seamsOwnError = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: collision, secondOutcome: collision, inlineOutcome: accepted)
		#expect(seamsOwnError.differentialFailure == nil)
		let rejectedInlineToo = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: unfulfillable, secondOutcome: unfulfillable, inlineOutcome: unfulfillable)
		#expect(rejectedInlineToo.differentialFailure == nil)
		let accepted2 = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: accepted, secondOutcome: accepted)
		#expect(accepted2.differentialFailure == nil)
	}

	@Test
	func nilArgumentFailure_reportsArgument_whenSeamPassesLiteralNilWhereInlinePassesValue() {
		// The nil count counts, over every generated file, the literal `nil` arguments of each construction of a type
		// of the graph: one more with the seam than without it is a receiver that loses a value. A seam type's own
		// constructions are not counted, so the `nil` a wider tier passes for what it omits is no failure – and so a
		// call of a tier that passes `nil` for a value the caller holds is not counted either, which the differential
		// value comparator sees; the sound case therefore passes the value at the call.
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"@Instantiable(generateDependencyTree: true)\npublic final class S7_Screen: Instantiable {\n\tpublic init(reader: S7_Reader) {\n\t\tself.reader = reader\n\t}\n\n\t@Instantiated let reader: S7_Reader\n}\n",
		])
		let inline = GraphFuzzerToolOutcome.accepted(generatedFiles: ["S7_Root+SafeDI.swift": "let reader = S7_Reader(token: token, user: nil)\nreturn S7_Screen(reader: reader)"], warnings: [])
		let seamPassingNil = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"S7_Root+SafeDI.swift": "return S7_Screen(token: nil)",
			"S7_Screen+SafeDI.swift": "public init(token: S7_Token? = nil) {\n    let reader = S7_Reader(token: nil, user: nil)\n    self.init(reader: reader)\n}",
		], warnings: [])
		let defect = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seamPassingNil, secondOutcome: seamPassingNil, inlineOutcome: inline)
		#expect(defect.nilArgumentFailure?.kind == .seamPassesNilWhereInlinePassesValue)
		#expect(defect.nilArgumentFailure?.details.prefix { $0 != "\n" } == "`S7_Reader(token:)` is passed `nil` 1 times with the seam and 0 without it.")
		let seamPassingValue = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"S7_Root+SafeDI.swift": "let token = S7_Token()\nreturn S7_Screen(token: token)",
			"S7_Screen+SafeDI.swift": "public init(token: S7_Token? = nil) {\n    let reader = S7_Reader(token: token, user: nil)\n    self.init(reader: reader)\n}",
		], warnings: [])
		let sound = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seamPassingValue, secondOutcome: seamPassingValue, inlineOutcome: inline)
		#expect(sound.nilArgumentFailure == nil)
		#expect(sound.isInspectedByValueOracle)
		let rejected = GraphFuzzerToolOutcome.rejected(diagnostics: "error")
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: rejected, secondOutcome: rejected, inlineOutcome: inline).isInspectedByValueOracle == false)
	}

	@Test
	func tiersWiderThanParameterTypes_reportsTier_whenTierIsWiderThanTypeItsParameterNames() {
		// The ground truth: a tier a seam proved from the wrong declaration names a type narrower than itself, such as
		// a `public` tier taking a type the generator declared `package`. A tier as narrow as the type is sound.
		let unsoundTier = """
		extension S1_ProofSeam {
		    public convenience init(proofTheme: S1_ProofTheme? = nil) {
		        self.init(proofTheme: proofTheme)
		    }

		    package convenience init(proofCrate: S1_ProofSpace.S1_ProofCrate, proofTheme: S1_ProofTheme? = nil) {
		        let proofBadge = S1_ProofBadge(proofTheme: proofTheme)
		        self.init(proofBadge: proofBadge)
		    }
		}

		extension S1_ProofSeam {
		    public enum __safeDI_S1_ProofSeam_0123456789ABCDEF {}
		}
		"""
		let typeAccess: [String: GraphFuzzerGenerator.AccessLevel] = ["S1_ProofTheme": .package, "S1_ProofSpace.S1_ProofCrate": .internal]

		#expect(GraphFuzzerOracle.tiersWiderThanParameterTypes(in: ["S1_ProofSeam+SafeDI.swift": unsoundTier], typeAccess: typeAccess) == [
			"S1_ProofSeam+SafeDI.swift: `S1_ProofSeam`'s `public` initializer takes `proofTheme: S1_ProofTheme? = nil`, but `S1_ProofTheme` is `package`.",
			"S1_ProofSeam+SafeDI.swift: `S1_ProofSeam`'s `package` initializer takes `proofCrate: S1_ProofSpace.S1_ProofCrate`, but `S1_ProofSpace.S1_ProofCrate` is `internal`.",
		])
		#expect(GraphFuzzerOracle.tiersWiderThanParameterTypes(in: ["S1_ProofSeam+SafeDI.swift": unsoundTier], typeAccess: ["S1_ProofTheme": .package, "S1_ProofSpace.S1_ProofCrate": .package]) == [
			"S1_ProofSeam+SafeDI.swift: `S1_ProofSeam`'s `public` initializer takes `proofTheme: S1_ProofTheme? = nil`, but `S1_ProofTheme` is `package`.",
		])
	}

	@Test(arguments: [
		// The provider's declaration, where the error is reported.
		"/F/Host.swift:3:2: error: `Host` provides `theme: Theme`, but the `public` initializer SafeDI generated for `Screen` in module `Feature`, the narrowest one module `App` can call, does not take it.",
		// The provider's file cannot be read, so the error is reported where the module refers to the call, naming the
		// provider's module.
		"/F/Root.swift:11:5: error: `Host` in module `Base` provides `theme: Theme`, but the `public` initializer SafeDI generated for `Screen` in module `Feature`, the narrowest one module `App` can call, does not take it.",
		// The caller is an outer seam that takes the value from its own callers, as R5 says of a pass-through.
		"/F/Outer.swift:3:1: error: `Outer` takes `theme: Theme?` from its callers, but the `public` initializer SafeDI generated for `Service` in module `Base`, the narrowest one module `Mid` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline.",
	])
	func omittedValueLabel_readsLabel_whenErrorNamesProviderOrOuterSeamTakingIt(error: String) {
		// The omitted-value oracle recognizes an error that a caller holds a value its tier omits in each of its forms.
		#expect(GraphFuzzerOracle.isOmittedValueError(Substring(error)))
		#expect(GraphFuzzerOracle.omittedValueLabel(of: Substring(error)) == "theme")
	}

	@Test
	func omittedValueFailure_reportsOmission_whenCallOmitsParameterInlineBuildPassesAValue() {
		// A caller in another module calls the public tier, which omits `proofTheme`: inline, its module passes
		// `S1_ProofBadge` the value it holds, so the tool must report it; inline passing `nil`, the omission is sound.
		let runs = Self.omittedValueRuns(seamOutcome: .accepted(generatedFiles: Self.omittingCall, warnings: []), inlinePassing: "proofTheme")
		#expect(runs.omittedValueFailure?.kind == .seamTierOmitsValueInlinePasses)
		#expect(runs.omittedValueFailure?.details.prefix { $0 != "\n" } == "FuzzOther/S1_ProofOtherRoot+SafeDI.swift calls `S1_ProofSeam` without `proofTheme`, which the inline build of FuzzOther passes a receiver a value for, and the tool reports no error.")
		#expect(Self.omittedValueRuns(seamOutcome: .accepted(generatedFiles: Self.omittingCall, warnings: []), inlinePassing: "nil").omittedValueFailure == nil)
	}

	@Test
	func omittedValueFailure_reportsError_whenToolReportsOmittedValueInlineBuildPassesNil() {
		// The tool reports that the caller holds `proofTheme`, which its tier omits: inline, its module passes
		// `S1_ProofBadge` `nil`, so no receiver would lose a value; inline passing the value, the error is right.
		let error = GraphFuzzerToolOutcome.rejected(diagnostics: "/x/<fixture-directory>/other/Sources/FuzzOther/S1_ProofOtherHost.swift:3:2: error: `S1_ProofOtherHost` provides `proofTheme: S1_ProofTheme`, but the `public` initializer SafeDI generated for `S1_ProofSeam` in module `FuzzFeature`, the narrowest one module `FuzzOther` can call, does not take it.")
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "nil").omittedValueFailure?.kind == .seamTierOmitsProvidedValueReportedWhereInlinePassesNil)
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "proofTheme").omittedValueFailure == nil)
		// A split graph's omitted-value error is a seam's own, which this oracle judges, not an inlined validation's.
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "proofTheme").differentialFailure == nil)
	}

	@Test
	func isEagerInstanceRead_exemptsOnlyTheMarkedRead_whenSeamCallReadsInstanceEarlierThanInline() {
		// The eager read of a wrapper's instance at a seam call, which the Manual lists under "Where a seam differs from
		// building its tree inline": the seam build describes the instance with the marker, and otherwise exactly as the
		// inline build does. Another instance is a defect, marker or not.
		let eagerRead = DifferentialValueDifference(probe: "S1_Root0()", path: ["<13>.instance"], feature: "<13>.instance: <11> S1_User (built before the probe's value) (seen)", knownRight: "<13>.instance: <11> S1_User (seen)")
		let otherInstance = DifferentialValueDifference(probe: "S1_Root0()", path: ["<13>.instance"], feature: "<13>.instance: <12> S1_User (built before the probe's value)", knownRight: "<13>.instance: <11> S1_User (seen)")
		let otherValue = DifferentialValueDifference(probe: "S1_Root0()", path: ["<1> S1_Root0", "user"], feature: "user: <2> S1_User (built before the probe's value)", knownRight: "user: <2> S1_User")
		#expect(GraphFuzzerOracle.isEagerInstanceRead(eagerRead))
		#expect(!GraphFuzzerOracle.isEagerInstanceRead(otherInstance))
		#expect(!GraphFuzzerOracle.isEagerInstanceRead(otherValue))
	}

	@Test
	func omittedValueFailure_reportsNothing_whenOuterSeamThatTakesValueFromItsCallersReportsOmission() {
		// An outer seam that takes `proofTheme` from its callers reports that its call omits it whatever its callers hold:
		// the oracle takes it for a seam's own error, and does not judge it by what this graph's inline build passes.
		let error = GraphFuzzerToolOutcome.rejected(diagnostics: "/x/<fixture-directory>/other/Sources/FuzzOther/S1_ProofOtherHost.swift:3:1: error: `S1_ProofOtherHost` takes `proofTheme: S1_ProofTheme?` from its callers, but the `public` initializer SafeDI generated for `S1_ProofSeam` in module `FuzzFeature`, the narrowest one module `FuzzOther` can call, does not take it.")
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "nil").omittedValueFailure == nil)
		#expect(Self.omittedValueRuns(seamOutcome: error, inlinePassing: "nil").differentialFailure == nil)
	}

	/// The runs of a graph split across modules whose `S1_ProofBadge`, in the seam's tree, receives `proofTheme` only
	/// if available, with the inline build of the caller in another package passing it `argument`.
	private static func omittedValueRuns(seamOutcome: GraphFuzzerToolOutcome, inlinePassing argument: String) -> GraphFuzzerToolRuns {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"// module: FuzzFeature\n\n@Instantiable\npublic final class S1_ProofBadge: Instantiable {\n\tpackage init(proofTheme: S1_ProofTheme?) {\n\t\tself.proofTheme = proofTheme\n\t}\n\n\t@Received(onlyIfAvailable: true) let proofTheme: S1_ProofTheme?\n}\n",
		])
		let inline = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"FuzzOther/S1_ProofOtherRoot+SafeDI.swift": "extension S1_ProofOtherRoot {\n    public convenience init() {\n        let proofBadge = S1_ProofBadge(proofTheme: \(argument))\n        self.init(proofSeam: S1_ProofSeam(proofBadge: proofBadge))\n    }\n}\n",
		], warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: seamOutcome, secondOutcome: seamOutcome, inlineOutcome: inline)
	}

	/// A seam's tiers and a call of its public tier from a caller in another package.
	private static let omittingCall = [
		"FuzzFeature/S1_ProofSeam+SafeDI.swift": "extension S1_ProofSeam {\n    public convenience init() {\n        self.init(proofTheme: nil)\n    }\n\n    package convenience init(proofTheme: S1_ProofTheme? = nil) {\n        self.init(proofBadge: S1_ProofBadge(proofTheme: proofTheme))\n    }\n}\n\nextension S1_ProofSeam {\n    public enum __safeDI_S1_ProofSeam_0123456789ABCDEF {}\n}\n",
		"FuzzOther/S1_ProofOtherRoot+SafeDI.swift": "extension S1_ProofOtherRoot {\n    public convenience init() {\n        func __safeDI_proofSeam() -> S1_ProofSeam {\n            _ = S1_ProofSeam.__safeDI_S1_ProofSeam_0123456789ABCDEF.self\n            return S1_ProofSeam()\n        }\n        self.init(proofSeam: __safeDI_proofSeam())\n    }\n}\n",
	]

	@Test
	func uncreatedAliasBindingReads_reportEachRead_whenSeamReadsAliasOfParameterThatMayBeNil() {
		// The structural oracle: an `onlyIfAvailable` alias bound from a parameter that defaults to `nil` is read only by
		// the construction of the type that declares it. The seam outputs of an alias of such an alias, `onlyIfAvailable`
		// and required, as the rule's first draft generated them, read it again.
		let aliasOfAlias = { (attribute: String) in
			"""
			extension Screen {
			    public convenience init(token: Token? = nil) {
			        func __safeDI_left() -> Left {
			            func __safeDI_detail() -> Detail {
			                #sourceLocation(file: "/F/Types.swift", line: 32)
			                let authToken: Token? = token
			                #sourceLocation()
			                #sourceLocation(file: "/F/Types.swift", line: 33)
			                let bearer: Token? = authToken\(attribute)
			                #sourceLocation()
			                return Detail(authToken: authToken, bearer: bearer)
			            }
			            let detail: Detail = __safeDI_detail()
			            return Left(detail: detail)
			        }
			        let left: Left = __safeDI_left()
			        self.init(left: left)
			    }
			}
			"""
		}
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": aliasOfAlias("")]) == ["Screen+SafeDI.swift: `let bearer: Token? = authToken` reads `authToken`."])
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": aliasOfAlias(" // Declared at Types.swift:33")]) == ["Screen+SafeDI.swift: `let bearer: Token? = authToken` reads `authToken`."])
		// A receiver beneath, built in a builder function of its own.
		let readerBeneath = """
		extension Screen {
		    public init(token: Token? = nil) {
		        func __safeDI_detail() -> Detail {
		            let authToken: Token? = token
		            func __safeDI_reader() -> Reader {
		                return Reader(authToken: authToken)
		            }
		            let reader: Reader = __safeDI_reader()
		            return Detail(authToken: authToken, reader: reader)
		        }
		        let detail: Detail = __safeDI_detail()
		        self.init(detail: detail)
		    }
		}
		"""
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": readerBeneath]) == ["Screen+SafeDI.swift: `return Reader(authToken: authToken)` reads `authToken`."])
		// The canonical alias, read by its declaring type alone; the seam's own alias, read by `self.init`; an alias of a
		// local that shadows the parameter, whose readers read the local's alias; and a reader beneath a nearer declaration
		// of the alias's label.
		let sound = """
		extension Screen {
		    public init(authToken: Token? = nil, token: Token? = nil) {
		        let own: Token? = token
		        func __safeDI_left() -> Left {
		            let token = Token()
		            func __safeDI_detail() -> Detail {
		                let authToken: Token? = token
		                let reader = Reader(authToken: authToken)
		                return Detail(authToken: authToken, reader: reader)
		            }
		            let detail: Detail = __safeDI_detail()
		            return Left(token: token, detail: detail)
		        }
		        let left: Left = __safeDI_left()
		        func __safeDI_other() -> Other {
		            let alias: Token? = token
		            func __safeDI_mid() -> Mid {
		                let alias = Token()
		                let reader = Reader(alias: alias)
		                return Mid(alias: alias, reader: reader)
		            }
		            let mid: Mid = __safeDI_mid()
		            return Other(alias: alias, mid: mid)
		        }
		        let other: Other = __safeDI_other()
		        self.init(own: own, left: left, other: other)
		    }
		}
		"""
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": sound]) == [])
	}

	@Test
	func uncreatedAliasBindingReads_reportEachRead_whenTierCarriesAttributesBeforeItsModifier() {
		// A seam's tiers carry the seam's generated-initializer attributes before the access modifier, with spaces
		// inside an attribute's arguments; the oracle recognizes the initializer by its modifier followed by `init(`.
		let attributed = """
		extension Screen {
		    @MainActor public convenience init(token: Token? = nil) {
		        let authToken: Token? = token
		        func __safeDI_reader() -> Reader {
		            return Reader(authToken: authToken)
		        }
		        let reader: Reader = __safeDI_reader()
		        self.init(authToken: authToken, reader: reader)
		    }

		    @available(iOS 17, *) internal init(session: Session? = nil) {
		        let bearer: Session? = session
		        let panel = Panel(bearer: bearer)
		        self.init(bearer: bearer, panel: panel)
		    }
		}
		"""
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": attributed]) == [
			"Screen+SafeDI.swift: `return Reader(authToken: authToken)` reads `authToken`.",
			"Screen+SafeDI.swift: `let panel = Panel(bearer: bearer)` reads `bearer`.",
		])
		// A line that mentions `init(` after something other than a modifier is not an initializer.
		let notAnInitializer = """
		extension Screen {
		    public static func callTier0(token: Token? = nil) -> Screen {
		        let authToken: Token? = token
		        return Screen.init(token: authToken)
		    }
		}
		"""
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": notAnInitializer]) == [])
	}

	@Test
	func uncreatedAliasRejectionFailure_reportsSeed_whenUncreatedAliasDrawsSeamIsRejectedWithAnotherError() {
		// The uncreated-alias draw's seam has no shape another seam rule rejects, so any other seam error about it is a
		// defect; an uncreated alias's own error, or another seam's error, is not.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0, features: [.generateDependencyTree])
		let aliasSeam = "\(fixture.typeNamePrefix)AliasSeam"
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let uncreatedAliasRead = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Reader.swift:7:5: error: SafeDI cannot generate the dependency tree of `\(aliasSeam)`: `Reader` receives `aliasAuth: Value?` beneath the `onlyIfAvailable` alias `aliasAuth` that `Detail` declares, which is not created where `aliasToken: Value` is unavailable.")
		let collision = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `\(aliasSeam)`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`.")
		let otherSeamsCollision = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Screen.swift:1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `x` as `x: X` on `A` and `x: Y?` on `B`.")
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: collision, secondOutcome: collision, inlineOutcome: accepted).uncreatedAliasRejectionFailure?.kind == .uncreatedAliasSeamRejectedOtherwise)
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: uncreatedAliasRead, secondOutcome: uncreatedAliasRead, inlineOutcome: accepted).uncreatedAliasRejectionFailure == nil)
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: otherSeamsCollision, secondOutcome: otherSeamsCollision, inlineOutcome: accepted).uncreatedAliasRejectionFailure == nil)
		#expect(GraphFuzzerToolRuns(fixture: fixture, firstOutcome: collision, secondOutcome: collision, inlineOutcome: collision).uncreatedAliasRejectionFailure == nil)
	}

	@Test
	func uncreatedAliasRejectionFailure_reportsExactFormAliasRejected_whenToolRejectsAliasOfRequiredOptionalParameterSpelledWithItsOptionalForm() {
		// The exact-form alias of a required optional parameter is always created, so an uncreated-alias error naming
		// it is an over-rejection the rejection-kind oracle would otherwise take for the uncreated alias's own error;
		// the unwrapped-form alias of such a parameter may be uncreated, and its error stands.
		func seed(drawing wanted: Set<GraphFuzzerSeamDrawFeature>, not unwanted: Set<GraphFuzzerSeamDrawFeature>) -> UInt64 {
			(0..<UInt64(Self.seamCorpusSeedCount)).first { seed in
				let features = GraphFuzzerFeature.seamDrawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree]))
				return features.isSuperset(of: wanted) && features.isDisjoint(with: unwanted)
			}!
		}
		let exactFormFixture = GraphFuzzerGenerator.fixture(forSeed: seed(drawing: [.uncreatedAliasExactFormAlias, .uncreatedAliasRequiredOptionalParameter], not: []), features: [.generateDependencyTree])
		let unwrappedFormFixture = GraphFuzzerGenerator.fixture(forSeed: seed(drawing: [.uncreatedAliasRequiredOptionalParameter], not: [.uncreatedAliasExactFormAlias]), features: [.generateDependencyTree])
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		func rejection(of fixture: GraphFuzzerFixture) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/F/Reader.swift:7:5: error: SafeDI cannot generate the dependency tree of `\(fixture.typeNamePrefix)AliasSeam`: `Reader` receives `aliasAuth: Value?` beneath the `onlyIfAvailable` alias `aliasAuth` that `Detail` declares, which is not created where `aliasToken: Value` is unavailable.")
		}
		let exactFormRejected = GraphFuzzerToolRuns(fixture: exactFormFixture, firstOutcome: rejection(of: exactFormFixture), secondOutcome: rejection(of: exactFormFixture), inlineOutcome: accepted)
		#expect(exactFormRejected.uncreatedAliasRejectionFailure?.kind == .uncreatedAliasExactFormAliasRejected)
		let unwrappedFormRejected = GraphFuzzerToolRuns(fixture: unwrappedFormFixture, firstOutcome: rejection(of: unwrappedFormFixture), secondOutcome: rejection(of: unwrappedFormFixture), inlineOutcome: accepted)
		#expect(unwrappedFormRejected.uncreatedAliasRejectionFailure == nil)
	}

	@Test
	func uncreatedAliasRejectionFailure_reportsAliasReadingItself_whenToolRejectsLabelKeepingAliasAsReadingItself() throws {
		// An alias that keeps its fulfilling property's label is not an alias of itself, so an uncreated-alias error
		// saying the type that declares it aliases it under its own label is an over-rejection the rejection-kind oracle
		// would otherwise take for the uncreated alias's own error; the same words about an alias of it under another
		// label on the same type, or about a label-keeping alias beneath it, stand.
		let seed = try #require((0..<UInt64(Self.seamCorpusSeedCount)).first { seed in
			GraphFuzzerFeature.seamDrawFeatures(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])).contains(.uncreatedAliasLabelKeepingOptionalAlias)
		})
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let aliasSeam = "\(fixture.typeNamePrefix)AliasSeam"
		let accepted = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		func runs(_ message: String) -> GraphFuzzerToolRuns {
			let outcome = GraphFuzzerToolOutcome.rejected(diagnostics: "/F/Detail.swift:7:2: error: SafeDI cannot generate the dependency tree of `\(aliasSeam)`: \(message)")
			return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, inlineOutcome: accepted)
		}
		let readsItself = runs("`Detail` aliases `aliasToken: Value` as `aliasToken`, and `aliasToken` is an `onlyIfAvailable` alias that is not created where `aliasToken: Value` is unavailable.")
		#expect(readsItself.uncreatedAliasRejectionFailure?.kind == .uncreatedAliasReadsItself)
		let aliasOfAliasOnSameType = runs("`Detail` aliases `aliasToken: Value?` as `aliasBearer`, and `aliasToken` is an `onlyIfAvailable` alias that is not created where `aliasToken: Value` is unavailable.")
		#expect(aliasOfAliasOnSameType.uncreatedAliasRejectionFailure == nil)
		let labelKeepingAliasBeneath = runs("`Reader` aliases `aliasToken: Value?` as `aliasToken`, and `aliasToken` is an `onlyIfAvailable` alias that `Detail` declares, which is not created where `aliasToken: Value` is unavailable.")
		#expect(labelKeepingAliasBeneath.uncreatedAliasRejectionFailure == nil)
	}

	@Test
	func uncreatedAliasBindingReads_reportRead_whenAliasOfRequiredOptionalParameterIsReadAndThatParameterIsTracked() {
		// The unwrapped-form alias of a required optional parameter may be uncreated as an alias of a parameter that
		// defaults to `nil` may, so its binding's reads are reported when the parameter is named; the exact-form alias
		// is always created, so the parameter is not named for it and its reads pass.
		let seam = """
		extension Screen {
		    public convenience init(aliasToken: Value?) {
		        func __safeDI_detail() -> Detail {
		            let aliasAuth: Value? = aliasToken
		            let reader = Reader(aliasAuth: aliasAuth)
		            return Detail(aliasAuth: aliasAuth, reader: reader)
		        }
		        let detail: Detail = __safeDI_detail()
		        self.init(aliasToken: aliasToken, detail: detail)
		    }
		}
		"""
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": seam], requiredOptionalParameters: ["aliasToken"]) == ["Screen+SafeDI.swift: `let reader = Reader(aliasAuth: aliasAuth)` reads `aliasAuth`."])
		#expect(GraphFuzzerOracle.uncreatedAliasBindingReads(in: ["Screen+SafeDI.swift": seam]) == [])
	}

	@Test
	func finding_isKnownIssue_whenEveryValueDifferenceMatchesAValueSignature() {
		let knownIssue = Self.valueDivergenceKnownIssue
		let failure = GraphFuzzerFailure(seed: 430, kind: .seamBuildsOtherValuesThanInline, details: Self.documentedDifference + "\nFeature path:\n…", valueDifferences: [Self.documentedDifference])

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .knownIssue(knownIssue, failure))
	}

	@Test
	func finding_isFailure_whenValueFailureHoldsDifferenceNoValueSignatureMatchesBesideOneThatMatches() {
		// A documented divergence beside an undocumented difference is a new failure: the shape's signature documents
		// the first difference, not the graph.
		let knownIssue = Self.valueDivergenceKnownIssue
		let failure = GraphFuzzerFailure(seed: 430, kind: .seamBuildsOtherValuesThanInline, details: Self.documentedDifference + "\n" + Self.undocumentedDifference + "\nFeature path:\n…", valueDifferences: [Self.documentedDifference, Self.undocumentedDifference])

		#expect(GraphFuzzerFinding(failure: failure, knownIssue: knownIssue) == .failure(failure))
	}

	@Test
	func finding_isFailure_whenKnownValueFailureIsFollowedByFailureTheKnownIssueDoesNotDocument() {
		// A known value failure masks nothing: the failures after it in the oracle's chain are reported as they would
		// be alone.
		let knownIssue = Self.valueDivergenceKnownIssue
		let known = GraphFuzzerFailure(seed: 430, kind: .seamBuildsOtherValuesThanInline, details: Self.documentedDifference, valueDifferences: [Self.documentedDifference])
		let renamed = GraphFuzzerFailure(seed: 430, kind: .renamedGraphDiffers, details: "Reversing its labels changes its generated mock code, in Root+SafeDIMock.swift.\nThis graph:\n…")

		#expect(GraphFuzzerFinding(failure: known, laterFailures: [renamed], knownIssue: knownIssue) == .failure(renamed))
		#expect(GraphFuzzerFinding(failure: known, laterFailures: [], knownIssue: knownIssue) == .knownIssue(knownIssue, known))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueFailures_reportsOtherValues_whenSeamBuildPassesNilWhereInlineBuildPassesValue() async throws {
		// The seam build of a smoke graph, with the root's call of a tier passing `nil` for a parameter that defaults to
		// `nil` where it passed a value, builds other values than the inline build: the receiver beneath gets `nil`.
		let (runs, seamFiles, warnings) = try await Self.valueProbeRuns()
		let perturbed = try #require(Self.passingNil(forADefaultedParameterIn: seamFiles, of: runs.fixture), "No smoke seam graph passes a value for a parameter that defaults to nil")
		let perturbedRuns = GraphFuzzerToolRuns(fixture: runs.fixture, firstOutcome: .accepted(generatedFiles: perturbed.files, warnings: warnings), secondOutcome: .accepted(generatedFiles: perturbed.files, warnings: warnings), inlineOutcome: runs.inlineOutcome)

		let failures = try GraphFuzzerOracle.valueFailures(of: [perturbedRuns])

		let failure = try #require(failures[runs.fixture.seed])
		#expect(failure.kind == .seamBuildsOtherValuesThanInline, Comment(rawValue: failure.details))
		// Seed 16's receiver beneath the spelling's seam gets `nil` where inline it gets the value its host forwards.
		#expect(failure.valueDifferences.first == "probe `S16_Root0().spellHostBuilder.instantiate(S16_SpellOuter.Item())` at <1> S16_SpellHost > spellSeam > spellChild > \(perturbed.label):\n  feature:     \(perturbed.label): nil\n  known right: \(perturbed.label): <2> S16_SpellOuter.Item (seen, first at <1> S16_SpellHost > spelled)")
		#expect(failure.valueDifferences.count == 1, "\(failure.valueDifferences)")
		#expect(failure.details.hasPrefix(failure.valueDifferences.joined(separator: "\n") + "\n"))
		#expect(try GraphFuzzerOracle.valueFailures(of: [runs]).isEmpty)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The value comparator compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueFailures_reportsComparatorCouldNotDescribeGraph_whenSeamBuildDoesNotCompile() async throws {
		let (runs, seamFiles, warnings) = try await Self.valueProbeRuns()
		let fileName = try #require(seamFiles.keys.sorted().first)
		var brokenFiles = seamFiles
		brokenFiles[fileName] = (seamFiles[fileName] ?? "") + "\nfunc broken() -> Int { \"not an integer\" }\n"
		let brokenRuns = GraphFuzzerToolRuns(fixture: runs.fixture, firstOutcome: .accepted(generatedFiles: brokenFiles, warnings: warnings), secondOutcome: .accepted(generatedFiles: brokenFiles, warnings: warnings), inlineOutcome: runs.inlineOutcome)

		let failures = try GraphFuzzerOracle.valueFailures(of: [brokenRuns])

		let failure = try #require(failures[runs.fixture.seed])
		#expect(failure.kind == .valueComparatorCouldNotDescribeGraph)
		#expect(failure.details.contains("not an integer"))
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
	func seamKnownIssues_listEachSeedOnceInIncreasingOrder_belowSeamCorpusSeedCount() {
		#expect(Self.knownIssueListProblems(Self.seamKnownIssues, corpusSeedCount: Self.seamCorpusSeedCount) == [])
		// A seed left out of the inherited shapes must be one of theirs, or the entry filters nothing.
		#expect(Self.seamCorpusSeedsOfOtherShapes.subtracting(Self.knownIssues.flatMap(\.seeds)) == [])
		// A seed added to an inherited shape must name a shape, and be one its list lacks, or the entry adds nothing.
		#expect(Set(Self.seamCorpusSeedsAddedToInheritedShapes.keys).subtracting(Self.knownIssues.map(\.reason)) == [])
		#expect(Set(Self.seamCorpusSeedsAddedToInheritedShapes.values.joined()).intersection(Self.knownIssues.flatMap(\.seeds)) == [])
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
	func finding_isKnownIssue_whenKnownIssueSeedDrawsDocumentedWarning() {
		let knownIssue = Self.compilerWarningKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDrawsWarning,
			details: "S84_Root0+SafeDI.swift:6:13: warning: initialization of immutable value '__safeDI_t1_fallback' was never used",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .knownIssue(knownIssue, failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "known \(knownIssue.seeds[0]) \(knownIssue.reason)")
	}

	@Test
	func finding_isFailure_whenCompilerWarningKnownIssueSeedFailsToCompileWithDocumentedText() {
		let knownIssue = Self.compilerWarningKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDoesNotCompile,
			details: "S84_Root0+SafeDI.swift:6:13: error: initialization of immutable value '__safeDI_t1_fallback' was never used",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) generated code does not compile")
	}

	@Test
	func finding_isFailure_whenCompilerErrorKnownIssueSeedDrawsWarningWithDocumentedText() {
		let knownIssue = Self.compilerErrorKnownIssue
		let failure = GraphFuzzerFailure(
			seed: knownIssue.seeds[0],
			kind: .generatedCodeDrawsWarning,
			details: "T4+SafeDIMock.swift:13:13: warning: invalid redeclaration of 't5'",
		)

		let finding = GraphFuzzerFinding(failure: failure, knownIssue: knownIssue)

		#expect(finding == .failure(failure))
		#expect(finding.reportLine(seed: knownIssue.seeds[0]) == "failure \(knownIssue.seeds[0]) generated code draws a compiler warning")
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
	func compilationFailures_reportEachBrokenGraph_whenGeneratedCodeFailsToTypeCheckOrToLowerOrDrawsWarning() throws {
		// Each graph is one small type, so the four compiler invocations this takes stay cheap; the smoke batch
		// already compiles real graphs.
		let typeErrorSeed: UInt64 = 1_000_000_001
		let loweringErrorSeed: UInt64 = 1_000_000_002
		let warningSeed: UInt64 = 1_000_000_003
		let redirectedWarningSeed: UInt64 = 1_000_000_004
		let fixtureWarningSeed: UInt64 = 1_000_000_005
		let redirectedWarningPrefix = GraphFuzzerFixture.typeNamePrefix(forSeed: redirectedWarningSeed)
		let fixtureWarningPrefix = GraphFuzzerFixture.typeNamePrefix(forSeed: fixtureWarningSeed)
		let toolRuns = [
			// A type error, which the type checker reports.
			Self.probeGraph(seed: typeErrorSeed, generatedCode: "func broken() -> Int { \"not an integer\" }\n"),
			// A closure that captures a local declared after it, which only lowering to SIL reports, and which a
			// type error elsewhere in the same compilation would hide.
			Self.probeGraph(seed: loweringErrorSeed, generatedCode: """
			func brokenWhenLowered() -> Int {
				func read() -> Int { value }
				let value = read()
				return value
			}

			"""),
			// A warning in the generated file, which compiles.
			Self.probeGraph(seed: warningSeed, generatedCode: "func drawsWarning() {\n\tlet unused = 1\n}\n"),
			// A warning the compiler reports at the fixture's declaration, where a `#sourceLocation` directive in
			// the generated file attributes the line, as the tool's directives name the fixtures it was given.
			Self.probeGraph(seed: redirectedWarningSeed, generatedCode: """
			func drawsWarningAtDeclaration() {
				#sourceLocation(file: "/fuzzer/<fixture-directory>/\(redirectedWarningPrefix)Probe.swift", line: 3)
				let unused = 1
				#sourceLocation()
			}

			"""),
			// A warning the fixture draws too, which is not the generated code's to avoid. The two graphs above draw the
			// same message in their generated code and still fail, which pins that only a graph's own fixture excuses
			// its warning, although every graph is in the one compile.
			Self.probeGraph(
				seed: fixtureWarningSeed,
				fixtureDeclarations: "func \(fixtureWarningPrefix)drawsWarning() {\n\tlet unused = 1\n}\n",
				generatedCode: "func \(fixtureWarningPrefix)generatedDrawsWarning() {\n\tlet unused = 1\n}\n",
			),
		]

		let failures = try GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [typeErrorSeed, loweringErrorSeed, warningSeed, redirectedWarningSeed])
		#expect(failures[typeErrorSeed]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[loweringErrorSeed]?.kind == .generatedCodeDoesNotCompile)
		#expect(failures[warningSeed]?.kind == .generatedCodeDrawsWarning)
		#expect(failures[warningSeed]?.details.contains("Broken.swift:3:6: warning: initialization of immutable value 'unused' was never used") == true)
		#expect(failures[redirectedWarningSeed]?.kind == .generatedCodeDrawsWarning)
		#expect(failures[redirectedWarningSeed]?.details.hasPrefix("/fuzzer/<fixture-directory>/\(redirectedWarningPrefix)Probe.swift:3:6: warning: initialization of immutable value 'unused' was never used") == true)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportWarning_whenGraphCompilesOnItsOwnAfterAnErrorThatNamesNoGraph() throws {
		// The fixture's type name lacks its seed's prefix, so no graph's file is named in the error it draws, and the
		// oracle compiles each graph on its own.
		let unattributedErrorSeed: UInt64 = 1_000_000_006
		let warningSeed: UInt64 = 1_000_000_007
		let rejected = GraphFuzzerToolOutcome.rejected(diagnostics: "")
		let toolRuns = [
			GraphFuzzerToolRuns(
				fixture: GraphFuzzerFixture(seed: unattributedErrorSeed, swiftFileContent: [
					"@Instantiable\npublic final class UnprefixedProbe: Instantiable {\n\tpublic init() {}\n}\nfunc unprefixedBroken() -> Int { \"not an integer\" }\n",
				]),
				firstOutcome: rejected,
				secondOutcome: rejected,
			),
			Self.probeGraph(seed: warningSeed, generatedCode: "func drawsWarning() {\n\tlet unused = 1\n}\n"),
		]

		let failures = try GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [unattributedErrorSeed, warningSeed])
		#expect(failures[unattributedErrorSeed]?.kind == .fixtureDoesNotCompile)
		#expect(failures[warningSeed]?.kind == .generatedCodeDrawsWarning)
	}

	/// A graph of one small type whose fixture also declares `fixtureDeclarations`, which the tool accepted with
	/// `generatedCode` as its one generated file.
	private static func probeGraph(seed: UInt64, fixtureDeclarations: String = "", generatedCode: String) -> GraphFuzzerToolRuns {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: [
			"@Instantiable\npublic final class \(prefix)Probe: Instantiable {\n\tpublic init() {}\n}\n" + fixtureDeclarations,
		])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["\(prefix)Broken.swift": generatedCode], warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
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
		let seed: UInt64 = 1_000_000_008
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
	func difference_isNil_whenDiagnosticsListTheSameProvingDeclarationsInAnotherOrder() {
		// SafeDI lists the declarations that prove a seam parameter's access in source order, which a file-name
		// reversal reverses; the same declarations in another order are the same diagnostic, and a missing one is not.
		func diagnostics(provers: String) -> GraphFuzzerToolOutcome {
			.rejected(diagnostics: "/a/<fixture-directory>/S1_Seam.swift:1:1: error: SafeDI cannot generate the dependency tree of `S1_Seam`: … `S1_Key` is `package` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (\(provers)). …")
		}

		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(provers: "`S1_Host.init(key:seam:)`, `S1_Vault.init(key:)`"), and: diagnostics(provers: "`S1_Vault.init(key:)`, `S1_Host.init(key:seam:)`")) == nil)
		#expect(GraphFuzzerToolOutcome.difference(between: diagnostics(provers: "`S1_Host.init(key:seam:)`, `S1_Vault.init(key:)`"), and: diagnostics(provers: "`S1_Vault.init(key:)`")) == "its diagnostics")
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
		let seamSeeds = Self.seamSmokeSeeds + Self.seamKnownIssues.flatMap(\.seeds)
		#expect(Self.fixtureHash(forSeeds: seamSeeds, features: [.generateDependencyTree]) == Self.seamSmokeAndKnownIssueFixtureHash)
		let publicMockSeeds = Self.publicMockSmokeSeeds + Self.publicMockKnownIssues.flatMap(\.seeds)
		#expect(Self.fixtureHash(forSeeds: publicMockSeeds, features: [.generateMockPublic]) == Self.publicMockSmokeAndKnownIssueFixtureHash)
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
		guard let features = configuration.features else {
			reportProblem("SAFEDI_GRAPH_FUZZER_FEATURES must name generator features: \(GraphFuzzerGeneratorFeature.allCases.map(\.rawValue).joined(separator: ", ")).")
			return
		}
		guard configuration.iterations > 0 else {
			reportProblem("SAFEDI_GRAPH_FUZZER_ITERATIONS must be a positive integer or `corpus`.")
			return
		}
		let corpus = Self.corpus(for: features)
		let knownIssueListProblems = Self.knownIssueListProblems(corpus.knownIssues, corpusSeedCount: corpus.seedCount)
		guard knownIssueListProblems.isEmpty else {
			knownIssueListProblems.forEach(reportProblem)
			return
		}
		let knownIssuesBySeed = Dictionary(uniqueKeysWithValues: corpus.knownIssues.flatMap { knownIssue in
			knownIssue.seeds.map { ($0, knownIssue) }
		})

		// Pin the whole corpus the long run covers, which the ordinary suite's hash covers only a sample of, and the
		// partition of every graph of it across modules, and check that no graph uses a label beginning with
		// `__safeDI_`, which the generated builder functions use.
		var generatedCorpusHash = GraphFuzzerHash()
		// The partition is pinned for the base corpus, whose graphs declare no seam and no public mock: the graphs
		// `GraphFuzzerOracle.toolRuns(of:renamings:multiModuleRenamings:)` splits.
		let isPartitioned = corpus.features.isEmpty
		var partitionedCorpusHash = GraphFuzzerHash()
		var graphCountByModuleCount = [Int](repeating: 0, count: GraphFuzzerPartition.moduleNames.count + 1)
		// The graphs whose two integrations combine declarations in different orders: see `GraphFuzzerPartition.moduleNames`.
		var deltaDependsOnGammaCount = 0
		for seed in 0..<UInt64(corpus.seedCount) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: corpus.features)
			generatedCorpusHash.combine(fixture.description)
			if isPartitioned {
				let partition = GraphFuzzerPartition.partition(of: fixture)
				partitionedCorpusHash.combine(partition.description)
				graphCountByModuleCount[partition.modules.count] += 1
				if partition.modules.last?.name == "Delta", partition.modules.last?.dependencies.contains("Gamma") == true {
					deltaDependsOnGammaCount += 1
				}
			}
			let reservedLabels = fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap { line -> String? in
				guard case let .property(_, label, _) = line, label.hasPrefix("__safeDI_") else { return nil }
				return label
			}
			if !reservedLabels.isEmpty {
				reportProblem("Seed \(seed)'s graph uses \(reservedLabels), which begin with `__safeDI_`, the prefix of generated builder functions.")
			}
		}
		if generatedCorpusHash.value != corpus.fixtureHash {
			reportProblem("The generator's graphs for seeds 0..<\(corpus.seedCount) of the \(corpus.name) corpus changed (fixture hash \(Self.hexadecimal(generatedCorpusHash.value)), pinned \(Self.hexadecimal(corpus.fixtureHash))). Re-derive the known issues, smoke seeds, and pinned values.")
		}
		if isPartitioned {
			if partitionedCorpusHash.value != Self.corpusPartitionHash {
				reportProblem("The partition of the graphs for seeds 0..<\(corpus.seedCount) across modules changed (partition hash \(Self.hexadecimal(partitionedCorpusHash.value)), pinned \(Self.hexadecimal(Self.corpusPartitionHash))). Re-derive the known issues and the pinned partition hashes.")
			}
			report.append("partitions " + graphCountByModuleCount.indices.dropFirst().map { "\($0):\(graphCountByModuleCount[$0])" }.joined(separator: " ") + " delta-depends-on-gamma:\(deltaDependsOnGammaCount)")
		}

		var graphCount = 0
		var acceptedCount = 0
		var acceptedSeedsSum = GraphFuzzerSeedSetSum()
		var valueOracleInspectedCount = 0
		var valueOracleComparedCount = 0
		var acceptedSpellingDrawFeatures = Set<GraphFuzzerSeamDrawFeature>()
		var omittedValueGraphCount = 0
		var publicMockOutputFeatureCounts = [GraphFuzzerPublicMockOutputFeature: Int]()
		var publicMockOnlyErrorCounts = [String: Int]()
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
						var results = try await GraphFuzzerOracle.results(forSeeds: seeds, features: corpus.features) { seed in
							report.append("seed \(seed)")
						}
						for index in results.indices where results[index].failure == nil
							&& results[index].fixture.seed % Self.crossProcessSampleInterval == 0
						{
							results[index] = try GraphFuzzerResult(
								fixture: results[index].fixture,
								outcome: results[index].outcome,
								failure: GraphFuzzerOracle.crossProcessFailure(of: results[index].fixture),
								laterFailures: results[index].laterFailures,
								renamedGraphFailures: results[index].renamedGraphFailures,
								multiModuleRuns: results[index].multiModuleRuns,
								isInspectedByValueOracle: results[index].isInspectedByValueOracle,
								isComparedByValueOracle: results[index].isComparedByValueOracle,
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
								if result.failure == nil {
									acceptedSpellingDrawFeatures.formUnion(GraphFuzzerFeature.seamDrawFeatures(of: result.fixture).intersection(corpus.spellingDrawFeatures))
									if corpus.features.contains(.generateMockPublic), case let .accepted(generatedFiles, _) = result.outcome {
										for feature in GraphFuzzerPublicMockDraw.outputFeatures(of: result.fixture, generatedFiles: generatedFiles) {
											publicMockOutputFeatureCounts[feature, default: 0] += 1
										}
									}
								}
							}
							if result.isInspectedByValueOracle {
								valueOracleInspectedCount += 1
							}
							if case let .rejected(diagnostics) = result.outcome, diagnostics.split(separator: "\n").contains(where: GraphFuzzerOracle.isOmittedValueError) {
								omittedValueGraphCount += 1
							}
							// The graphs each of a public mock's own errors rejects, which the public mock's commits pin.
							if corpus.features.contains(.generateMockPublic), case let .rejected(diagnostics) = result.outcome {
								for marker in GraphFuzzerOracle.publicMockOnlyErrorMarkers where diagnostics.contains(marker) {
									publicMockOnlyErrorCounts[marker, default: 0] += 1
								}
							}
							if result.isComparedByValueOracle {
								valueOracleComparedCount += 1
							}
							// Counted whether or not the graph also fails another way.
							for renamedGraphFailure in result.renamedGraphFailures {
								report.append("renamed \(seed) \(renamedGraphFailure.details.prefix { $0 != "\n" })")
							}
							for multiModuleFailure in result.multiModuleFailures {
								report.append("multimodule \(seed) \(multiModuleFailure.details.prefix { $0 != "\n" })")
							}
							let finding = GraphFuzzerFinding(failure: result.failure, laterFailures: result.laterFailures, knownIssue: knownIssuesBySeed[seed])
							if let reportLine = finding.reportLine(seed: seed) {
								// A stale line carries the remedy, chosen by the stale issue's shape, for the summary.
								if case let .staleKnownIssue(knownIssue) = finding {
									report.append("\(reportLine); \(corpus.staleSeedRemedy(knownIssue, seed))")
								} else {
									report.append(reportLine)
								}
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
		report.append("shard \(configuration.startingSeed) \(configuration.iterations) \(acceptedCount) \(Self.hexadecimal(acceptedSeedsSum.value)) \(corpus.name)")
		report.append("corpus \(corpus.seedCount) \(corpus.acceptedSeedCount) \(Self.hexadecimal(corpus.acceptedSeedsSum)) \(corpus.name)")
		// The value oracle's inspected graphs and the spellings drawn in accepted graphs, which ci.yml's combine job adds
		// up across shards: a draw that stops landing in accepted graphs, or an oracle that stops inspecting, fails it.
		report.append("inspected \(valueOracleInspectedCount) \(corpus.valueOracleInspectedGraphCount) \(corpus.name)")
		// The graphs the comparator compared, which a compilation failure (a known warning among them) keeps below the
		// inspected count: read from the report rather than derived.
		report.append("compared \(valueOracleComparedCount) \(corpus.name)")
		// The graphs the tool rejects because a caller holds a value its tier omits, which ci.yml's combine job adds up.
		report.append("omitted-values \(omittedValueGraphCount) \(corpus.omittedValueGraphCount) \(corpus.name)")
		report.append("spellings \(corpus.name) \(corpus.spellingDrawFeatures.map(\.rawValue).sorted().joined(separator: ",")) \(acceptedSpellingDrawFeatures.map(\.rawValue).sorted().joined(separator: ","))")
		// The output features of the accepted graphs that pass, with each pinned minimum share as a percentage of the
		// corpus's accepted graphs, which ci.yml's combine job adds up and checks; and how many graphs each of a public
		// mock's own errors rejects.
		if corpus.features.contains(.generateMockPublic) {
			let counts = GraphFuzzerPublicMockOutputFeature.allCases.map { "\($0.rawValue)=\(publicMockOutputFeatureCounts[$0, default: 0])" }.joined(separator: ",")
			let minimums = corpus.outputFeatureMinimumShares.sorted { $0.key < $1.key }.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: ",")
			report.append("outputs \(corpus.name) \(counts) \(minimums)")
			let errorCounts = GraphFuzzerOracle.publicMockOnlyErrorMarkers.map { publicMockOnlyErrorCounts[$0, default: 0] }
			report.append("public-mock-errors \(corpus.name) \(errorCounts.map(String.init).joined(separator: ",")) \(corpus.publicMockErrorGraphCounts.map(String.init).joined(separator: ","))")
		}
		// Every corpus that exists, so the combine job can tell a corpus whose shards left no report from none.
		report.append("corpora \(([Self.baseCorpus] + GraphFuzzerGeneratorFeature.allCases.map { Self.corpus(for: [$0]) }).map(\.name).joined(separator: " "))")
		if configuration.startingSeed == 0, configuration.iterations == corpus.seedCount,
		   acceptedCount != corpus.acceptedSeedCount || acceptedSeedsSum.value != corpus.acceptedSeedsSum
		{
			reportProblem("The tool accepted \(acceptedCount) of seeds 0..<\(corpus.seedCount) of the \(corpus.name) corpus (sum \(Self.hexadecimal(acceptedSeedsSum.value))), but \(corpus.acceptedSeedCount) are pinned (sum \(Self.hexadecimal(corpus.acceptedSeedsSum))). A tool change that rejects or accepts different graphs must update the pinned values deliberately.")
		}
		if configuration.startingSeed == 0, configuration.iterations == corpus.seedCount {
			if valueOracleInspectedCount != corpus.valueOracleInspectedGraphCount {
				reportProblem("The value oracle inspected \(valueOracleInspectedCount) graphs of the \(corpus.name) corpus, but \(corpus.valueOracleInspectedGraphCount) are pinned.")
			}
			if omittedValueGraphCount != corpus.omittedValueGraphCount {
				reportProblem("The tool rejected \(omittedValueGraphCount) graphs of the \(corpus.name) corpus because a caller holds a value its tier omits, but \(corpus.omittedValueGraphCount) are pinned.")
			}
			let missingSpellings = corpus.spellingDrawFeatures.subtracting(acceptedSpellingDrawFeatures)
			if !missingSpellings.isEmpty {
				reportProblem("No accepted graph of the \(corpus.name) corpus draws \(missingSpellings.map(\.rawValue).sorted().joined(separator: ", ")).")
			}
			let errorCounts = GraphFuzzerOracle.publicMockOnlyErrorMarkers.map { publicMockOnlyErrorCounts[$0, default: 0] }
			if corpus.features.contains(.generateMockPublic), errorCounts != corpus.publicMockErrorGraphCounts {
				reportProblem("The tool rejected \(errorCounts) graphs of the \(corpus.name) corpus with each of a public mock's own errors (`publicMockOnlyErrorMarkers`), but \(corpus.publicMockErrorGraphCounts) are pinned.")
			}
			for (feature, minimumShare) in corpus.outputFeatureMinimumShares.sorted(by: { $0.key < $1.key }) where publicMockOutputFeatureCounts[feature, default: 0] * 100 < minimumShare * acceptedCount {
				reportProblem("The generated code of \(publicMockOutputFeatureCounts[feature, default: 0]) of the \(acceptedCount) graphs of the \(corpus.name) corpus the tool accepts shows \(feature.rawValue), fewer than the pinned \(minimumShare) percent.")
			}
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

	static let smokeAndKnownIssueFixtureHash: UInt64 = 0x36C0529696F414

	/// The `GraphFuzzerPartition` of the smoke and known-issue seeds' graphs, as `partitionHash(forSeeds:)` hashes
	/// them; `corpusPartitionHash` pins the whole corpus's. The partition draws nothing from the seed, so changing it
	/// changes neither the graphs nor the pins on them: these pins make a change to the partition deliberate. They
	/// move with the generator and, this one, with the smoke and known-issue seeds too, as the fixture hashes do.
	static let smokeAndKnownIssuePartitionHash: UInt64 = 0x360DEF628EA25689

	/// The corpus, seeds `0..<corpusSeedCount`, which ci.yml fuzzes on every pull request and push to main and
	/// `SAFEDI_GRAPH_FUZZER_ITERATIONS=corpus` selects. `knownIssues` lists every one that fails.
	static let corpusSeedCount = 5_000

	static let corpusFixtureHash: UInt64 = 0xDD638CCC778015F8

	static let corpusPartitionHash: UInt64 = 0x62485457537CD9EC

	/// How many of the corpus's graphs the tool accepts, and which ones, as a `GraphFuzzerSeedSetSum`, which
	/// shards of the corpus can add up.
	static let corpusAcceptedSeedCount = 2_299
	static let corpusAcceptedSeedsSum: UInt64 = 0x62F41F76B0229D38

	/// The graphs of seeds `0..<seedCount` drawn with `features`, and what is pinned about them. Each generator
	/// feature has a corpus of its own, so that turning a feature on changes no graph of the corpus drawn without it.
	struct Corpus {
		/// The name the long run's report lines carry, which ci.yml's combine job groups shards by.
		let name: String
		let features: Set<GraphFuzzerGeneratorFeature>
		let seedCount: Int
		let fixtureHash: UInt64
		let acceptedSeedCount: Int
		let acceptedSeedsSum: UInt64
		let knownIssues: [GraphFuzzerKnownIssue]
		/// The name of the list `knownIssues` is read from, which a stale entry's message names.
		let knownIssuesName: String
		/// What to edit when a seed of `knownIssues` no longer fails in this corpus, by the shape it was listed under
		/// and the list that put the seed there.
		let staleSeedRemedy: @Sendable (GraphFuzzerKnownIssue, UInt64) -> String
		/// How many graphs the value oracle compares with their inline build: those the tool accepts with a seam and
		/// without it.
		let valueOracleInspectedGraphCount: Int
		/// The spellings each of which some graph the tool accepts must draw.
		let spellingDrawFeatures: Set<GraphFuzzerSeamDrawFeature>
		/// How many graphs the tool rejects with an error that a caller in another module holds a value the seam tier it
		/// calls omits, which the omitted-value oracle judges against the inline build.
		let omittedValueGraphCount: Int
		/// The least share, in percent of the graphs the tool accepts, of the graphs whose generated code shows each public
		/// mock output feature, for the features that have one.
		var outputFeatureMinimumShares = [GraphFuzzerPublicMockOutputFeature: Int]()
		/// How many graphs the tool rejects with each of a public mock's own errors, in the order of
		/// `GraphFuzzerOracle.publicMockOnlyErrorMarkers`.
		var publicMockErrorGraphCounts = [Int]()
	}

	static let baseCorpus = Corpus(
		name: "base",
		features: [],
		seedCount: corpusSeedCount,
		fixtureHash: corpusFixtureHash,
		acceptedSeedCount: corpusAcceptedSeedCount,
		acceptedSeedsSum: corpusAcceptedSeedsSum,
		knownIssues: knownIssues,
		knownIssuesName: "knownIssues",
		staleSeedRemedy: { _, _ in "remove it from `knownIssues`, and from `seamCorpusSeedsOfOtherShapes` when it is listed there" },
		valueOracleInspectedGraphCount: 0,
		spellingDrawFeatures: [],
		omittedValueGraphCount: 0,
	)

	/// The corpus drawn with the `generateDependencyTree` feature: seeds `0..<seamCorpusSeedCount`, each graph with
	/// one type a root reaches declared as a seam. Smaller than the base corpus while the feature settles.
	static let seamCorpus = Corpus(
		name: GraphFuzzerGeneratorFeature.generateDependencyTree.rawValue,
		features: [.generateDependencyTree],
		seedCount: seamCorpusSeedCount,
		fixtureHash: seamCorpusFixtureHash,
		acceptedSeedCount: seamCorpusAcceptedSeedCount,
		acceptedSeedsSum: seamCorpusAcceptedSeedsSum,
		knownIssues: seamKnownIssues,
		knownIssuesName: "seamKnownIssues",
		// A label-sorted seed leaves its own list; an inherited seed leaves `knownIssues` when the base corpus reports
		// it stale too, and is otherwise one the seam's draw changed.
		staleSeedRemedy: { knownIssue, seed in
			if knownIssue.reason == labelSortedPassThroughReason {
				"remove it from `labelSortedPassThroughSeeds`"
			} else if seamCorpusSeedsAddedToInheritedShapes[knownIssue.reason]?.contains(seed) == true {
				"remove it from `seamCorpusSeedsAddedToInheritedShapes`"
			} else {
				"remove it from `knownIssues` if the base corpus reports it stale too, else add it to `seamCorpusSeedsOfOtherShapes`"
			}
		},
		valueOracleInspectedGraphCount: seamCorpusValueOracleInspectedGraphCount,
		spellingDrawFeatures: Set(GraphFuzzerSpelling.allCases.map(\.drawFeature)),
		omittedValueGraphCount: seamCorpusOmittedValueGraphCount,
	)

	static let seamCorpusSeedCount = 1_000
	static let seamCorpusFixtureHash: UInt64 = 0x73FE9571CEC308EC
	static let seamCorpusAcceptedSeedCount = 253
	static let seamCorpusAcceptedSeedsSum: UInt64 = 0xD0EC42E39AD4EF47
	/// How many of the seam corpus's graphs the tool accepts with their seams and without them, which the value
	/// oracle compares.
	static let seamCorpusValueOracleInspectedGraphCount = 204
	/// How many of the seam corpus's graphs the tool rejects because a caller holds a value the tier it calls omits.
	static let seamCorpusOmittedValueGraphCount = 18

	/// The ordinary suite's batch of the seam corpus: graphs the tool accepts whose generated code, between them, shows
	/// every `GraphFuzzerSeamOutputFeature` – both kinds of pass-through, a call reading `.instance`, an `@escaping`
	/// closure parameter, an `@escaping @Sendable` one, and an optional closure – graphs split across modules, with a
	/// caller in another package (seed 31), a caller in the same package run without its package's name (seed 609) and a
	/// seam's module run so (seed 98), the last two also accepted inline, so the batch compiles every module, judges an
	/// omitted value and compares a split graph's values; graphs with a hole whose code, between them, shows every
	/// `GraphFuzzerHoleOutputFeature` – a passed-up builder whose fill re-enters the inner seam (seed 196) and a staged
	/// builder whose fill re-enters its seam (seed 277); and a graph it rejects, which
	/// `seamSmokeSeeds_exerciseSeamFeature_inGraphsTheToolAccepts` checks. Pinned by `seamSmokeAndKnownIssueFixtureHash`.
	static let seamSmokeSeeds: [UInt64] = [0, 1, 16, 31, 92, 98, 196, 277, 609]

	static let seamSmokeAndKnownIssueFixtureHash: UInt64 = 0x78529BE9E3EAD44B

	/// How many of the seam corpus's graphs each shape of `addingSeam` lands in, exactly, as the corpus run observed,
	/// so a draw that stops landing, or a change in a shape's share, fails
	/// `seamCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool`.
	static let seamCorpusDrawFeatureCounts: [GraphFuzzerSeamDrawFeature: Int] = [
		.collidingFormsBeneathSeam: 71,
		.innerSeam: 337,
		.instanceHeldByCaller: 392,
		.instanceReceiveBeneathSeam: 242,
		.otherKindWrapperReceiveBeneathSeam: 32,
		.renameAboveSeam: 19,
		.renameOnSeamOrChild: 392,
		.requiredWrapperProvidingByValueForm: 157,
		.spelledAliasFulfillingProperty: 153,
		.spelledArray: 65,
		.spelledClosure: 69,
		.spelledClosureTakingExistential: 62,
		.spelledClosureWithParameterAndReturn: 68,
		.spelledExistential: 57,
		.spelledNestedType: 53,
		.spelledOnlyIfAvailablePassThrough: 94,
		.spelledOptionalClosure: 42,
		.spelledOptionalSendableClosure: 64,
		.spelledOwnForwarded: 242,
		.spelledOwnReceived: 197,
		.spelledRequiredPassThrough: 195,
		.spelledResult: 56,
		.spelledSendableClosure: 69,
		.spelledTupleWithClosure: 54,
		.spelledTypealias: 69,
		.synthesizedChild: 338,
		.synthesizedHeldProvider: 350,
		.synthesizedLazyProvider: 486,
		.synthesizedSharedProvider: 890,
		.uncreatedAliasAliasOfAlias: 28,
		.uncreatedAliasDeclarationAbove: 81,
		.uncreatedAliasFulfillingPropertyPruned: 46,
		.uncreatedAliasLabelHeldByCaller: 131,
		.uncreatedAliasLabelParameter: 110,
		.uncreatedAliasOtherTypeBeside: 45,
		.uncreatedAliasReader: 50,
		.uncreatedAliasSamePropertyBeside: 34,
		.uncreatedAliasWrapperBeside: 78,
		.spelledOptionalFormOnSibling: 226,
		.spelledTreeMocked: 231,
		.uncreatedAliasFulfillingPropertyHeldByCaller: 224,
		.uncreatedAliasRequiredReader: 7,
		.uncreatedAliasLabelKeepingAliasReader: 34,
		.uncreatedAliasReaderInsideWrapper: 13,
		.uncreatedAliasReaderInsideNestedSeam: 21,
		.uncreatedAliasDeeperReader: 54,
		.uncreatedAliasRequiredAliasOfAlias: 12,
		.uncreatedAliasOnSeamItself: 30,
		.uncreatedAliasFulfillingPropertyGeneratedAfterLabelKeepingAlias: 5,
		.uncreatedAliasFulfillingPropertyBeingBuilt: 30,
		.uncreatedAliasFulfillingPropertyGeneratedLater: 31,
		.uncreatedAliasRequiredOptionalParameter: 119,
		.uncreatedAliasExactFormAlias: 128,
		.uncreatedAliasAcceptedTwin: 117,
		.uncreatedAliasLabelKeepingOptionalAlias: 37,
		.wrapperReceiveBeneathSeam: 581,
		.seamTypeNarrowerThanPublic: 255,
		.receiverNarrowerThanType: 316,
		.receiverTypeNarrowerThanItsInitializer: 102,
		.ownInitializerNarrowerWithNoPassThrough: 74,
		.ownInitializerNarrowerWithOnlyOptionalNarrowerPassThroughs: 85,
		.ownInitializerNarrowerThanTwoParameterLevels: 50,
		.requiredParameterNarrowerThanSeamType: 53,
		.ownOnlyIfAvailableParameter: 115,
		.ownOnlyIfAvailableParameterNarrowerThanSeam: 39,
		.providedValueHeldByCaller: 96,
		.providedValueHeldByNoCaller: 26,
		.unprovenAliasType: 21,
		.unprovenAliasTypeOnlyIfAvailable: 22,
		.aliasOfNarrowerInstantiableType: 25,
		.aliasFulfillingTypeAlsoReceived: 22,
		.namespaceExtensionUnspelled: 64,
		.namespaceExtensionSpelled: 37,
		.publicNamespace: 20,
		.namespaceTypeOnlyThroughExistential: 61,
		.instantiableExtensionOfNarrowerType: 55,
		.qualifiedAllowlistMention: 14,
		.mockCappedByItsExtension: 52,
		.mockCapRaisedByUnreachedMention: 30,
		.mockInInstantiableExtension: 25,
		.typeInExtensionOfSeam: 41,
		.typeInExtensionOfNarrowerRecordedType: 39,
		.valueDeclaredAfterSeam: 69,
		.moduleSplit: 484,
		.otherPackageCaller: 221,
		.samePackageCallerRunWithoutPackageName: 53,
		.seamModuleRunWithoutPackageName: 38,
		.hole: 331,
		.holeOwnedBySeam: 75,
		.holeBeneathConstant: 60,
		.holeBeneathInstantiator: 89,
		.holeBeneathSendableInstantiator: 44,
		.holeBeneathLazilyInstantiated: 55,
		.holeBeneathSendableLazilyInstantiated: 8,
		.holeOwnerReachedAtTwoSites: 56,
		.holeReadsField: 167,
		.holeReadsCallerValue: 92,
		.holePassedUp: 84,
		.holeReentersSeam: 43,
		.holeReentersSeamBeneathRedeclaredLabel: 7,
		.holeReentersInnerSeamOfPassedUpBuilder: 13,
		.holeSeamReentersItself: 19,
		.holeSeamReentersItselfBeneathBoundLabel: 2,
		.uncreatedAliasLabelLazilyInstantiatedBeside: 26,
		.uncreatedAliasLabelReceivedBeside: 17,
		.uncreatedAliasLabelOnMid: 9,
		.uncreatedAliasSeamRequiresLabel: 7,
		.uncreatedAliasSeamReceivesLabelAsAnotherType: 6,
		.uncreatedAliasLabelAliasesOtherParameter: 10,
		.uncreatedAliasLabelDeclaredAfterDetail: 41,
		.uncreatedAliasLabelDeclaredBesideAndAbove: 21,
		.uncreatedAliasClientReceivesWrapper: 17,
		.uncreatedAliasAliasOfAliasOnSeam: 10,
		.uncreatedAliasReaderOfAliasOfAlias: 10,
		.uncreatedAliasRequiredLabelKeepingAliasReader: 12,
		.uncreatedAliasReaderRedeclaresAlias: 8,
		.uncreatedAliasLabelGeneratedAfterDetail: 59,
		.uncreatedAliasSeamReceivesFulfillingPropertyOnlyIfAvailable: 31,
		.uncreatedAliasFulfillingPropertyRequiredBeside: 32,
		.uncreatedAliasAcrossModules: 111,
		.spelledAcrossModules: 175,
		.formsAcrossModules: 145,
		.formsSeam: 499,
		.formsByValueReceive: 271,
		.formsWrapperReceive: 346,
		.formsRequiredOptionalReceive: 86,
		.formsOptionalWrapperReceive: 109,
		.formsSeamOwnReceive: 57,
		.formsDetailInSendableBuilder: 31,
		.formsCallerHoldsInstance: 64,
		.formsCallerHoldsWrapper: 220,
		.formsCallerForwardsOptionalForm: 71,
		.formsCallerHoldsNearerOptionalInstance: 36,
		.formsInstanceTreeBuildsSeam: 25,
		.formsInstanceTreeReceivesSeamOnlyIfAvailable: 48,
		.formsCallerHoldsNothing: 35,
		.formsUserDeclaredAfterSeam: 161,
		.foundationQualifiedAllowlistMention: 22,
		.mockOnlyFakeMentionsReceivedType: 57,
		.lazilyInstantiatedProvider: 24,
		.hostReceivesValuesOnlyIfAvailable: 49,
		.seamReachedThroughHolder: 110,
		.samePackageHostIsSeam: 171,
		.otherPackageHostIsSeam: 47,
	]

	/// Seeds in `0..<seamCorpusSeedCount` whose graphs fail today. The 1 000-seed run of this corpus found that each
	/// shape of `knownIssues` fails the same seeds here, below the corpus's size, but those the seam's own draw
	/// changes (`seamCorpusSeedsOfOtherShapes`), and fails some the base corpus does not list under it
	/// (`seamCorpusSeedsAddedToInheritedShapes`): the inherited shapes are listed from `knownIssues` with those
	/// adjustments, a shape left with no seed dropped, so that a fix there is a fix here, and the long run reports a
	/// seed that diverges as stale or new. The seam's own shape follows them. Each seed is listed once.
	static let seamKnownIssues: [GraphFuzzerKnownIssue] = knownIssues.compactMap { knownIssue in
		let seeds = (knownIssue.seeds.filter { $0 < UInt64(seamCorpusSeedCount) && !seamCorpusSeedsOfOtherShapes.contains($0) }
			+ (seamCorpusSeedsAddedToInheritedShapes[knownIssue.reason] ?? [])).sorted()
		return seeds.isEmpty ? nil : GraphFuzzerKnownIssue(reason: knownIssue.reason, signatures: knownIssue.signatures, seeds: seeds)
	} + [
		GraphFuzzerKnownIssue(
			reason: labelSortedPassThroughReason,
			signatures: [.renamedGraphDiffers(containing: "changes its generated dependency tree code")],
			seeds: labelSortedPassThroughSeeds,
		),
		// The Manual's first two documented divergences, each a shape whose signatures every difference of a listed graph
		// must match; a graph that also fails an inherited shape stays listed there, its documented difference exempted
		// exactly (`documentedSeamValueDivergences`), as is every eager read of the third, which has no shape.
		GraphFuzzerKnownIssue(
			reason: "A caller whose tree holds only the optional form of an alias's fulfilling property passes it, and the seam creates the alias from it, where inline the alias is not created (the Manual's first documented divergence)",
			signatures: [.seamBuildsOtherValuesThanInline(containing: "_Root0 > aliasSource)\n  known right: aliasAuth: nil"), .seamBuildsOtherValuesThanInline(containing: "_Root0 > aliasSource)\n  known right: aliasBearer: nil"), .seamBuildsOtherValuesThanInline(containing: "> aliasDetail > aliasToken:\n  feature:     aliasToken: <13> S843_AliasValue (seen, first at <1> S843_Root0 > aliasSource)\n  known right: aliasToken: nil")],
			seeds: [430, 923, 924],
		),
		GraphFuzzerKnownIssue(
			reason: "The seam's own onlyIfAvailable alias is bound from its fulfilling parameter, where inline the seam is passed the property of the alias's label that the scope building the seam creates (the Manual's second documented divergence)",
			signatures: [.seamBuildsOtherValuesThanInline(containing: "> aliasSeam > aliasAuth:\n  feature:     aliasAuth: nil")],
			seeds: [698],
		),
		// A seed `knownIssues` lists under another shape, whose graph the seam's draw changes so that it fails this one.
		GraphFuzzerKnownIssue(
			reason: "SafeDIMockConfiguration.swift declares its extensions in the order of the roots that reach them, in a graph the base corpus lists under another shape",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock configuration code")],
			seeds: [311],
		),
	]

	private static let labelSortedPassThroughReason = "A seam's pass-through parameters are sorted by label, so reversing the labels reorders its generated initializer and the calls of it"

	/// Seeds of `knownIssues` that the seam corpus's run observed failing with the seam's own shape, or not failing
	/// at all, since the seam's draw changed their graphs; the inherited lists leave them out. Observed, not
	/// derived: a seed here that a run finds failing its inherited shape again is a new failure, and goes back.
	private static let seamCorpusSeedsOfOtherShapes: Set<UInt64> = [35, 45, 107, 114, 309, 310, 311, 364, 371, 381, 393, 431, 434, 448, 471, 476, 545, 593, 632, 714, 728, 768, 774, 786, 808, 847, 903, 975]

	/// Seeds that `knownIssues` does not list under an inherited shape, whose graphs the seam's draw changes so that
	/// they fail it, by the shape's reason. Observed, not derived, as `seamCorpusSeedsOfOtherShapes` is.
	private static let seamCorpusSeedsAddedToInheritedShapes: [String: [UInt64]] = [
		"SafeDIMockConfiguration.swift declares its extensions in the order of the roots that reach them": [93, 594, 794],
	]

	/// Seeds whose seam has two or more pass-throughs. They are sorted by label – kept by ruling: a parameter order
	/// that follows label order is how mocks and initializers already work – so the oracle's label reversal
	/// reorders them, which is expected, not a defect, as the mock's label-sorted parameters are in `knownIssues`.
	/// A seed whose type-name reversal changes its mock code first fails the inherited shape and stays listed there.
	private static let labelSortedPassThroughSeeds: [UInt64] = [371, 381, 604, 788, 809, 816, 928]

	/// The corpus drawn with `features`: the base corpus when there are none, and a feature's corpus for that
	/// feature. Every feature has a corpus, so the two are the only ones.
	static func corpus(for features: Set<GraphFuzzerGeneratorFeature>) -> Corpus {
		if features.contains(.generateMockPublic) {
			publicMockCorpus
		} else if features.contains(.generateDependencyTree) {
			seamCorpus
		} else {
			baseCorpus
		}
	}

	/// The corpus drawn with the `generateMockPublic` feature: seeds `0..<publicMockCorpusSeedCount`, each a graph of its
	/// own (`GraphFuzzerPublicMockDraw`) with types declared `generateMock: .public` and the consumers that reach them.
	static let publicMockCorpus = Corpus(
		name: GraphFuzzerGeneratorFeature.generateMockPublic.rawValue,
		features: [.generateMockPublic],
		seedCount: publicMockCorpusSeedCount,
		fixtureHash: publicMockCorpusFixtureHash,
		acceptedSeedCount: publicMockCorpusAcceptedSeedCount,
		acceptedSeedsSum: publicMockCorpusAcceptedSeedsSum,
		knownIssues: publicMockKnownIssues,
		knownIssuesName: "publicMockKnownIssues",
		staleSeedRemedy: { _, _ in "remove it from `publicMockKnownIssues`" },
		valueOracleInspectedGraphCount: publicMockCorpusValueOracleInspectedGraphCount,
		spellingDrawFeatures: [],
		omittedValueGraphCount: publicMockCorpusOmittedValueGraphCount,
		outputFeatureMinimumShares: publicMockCorpusOutputFeatureMinimumShares,
		publicMockErrorGraphCounts: publicMockCorpusErrorGraphCounts,
	)

	/// The least share of the public mock corpus's accepted graphs whose generated code shows each output feature, in
	/// percent: the floor of the share the corpus run observed, for each feature the generated code shows today. The
	/// commits that make another feature show pin it in turn.
	static let publicMockCorpusOutputFeatureMinimumShares: [GraphFuzzerPublicMockOutputFeature: Int] = [
		.allNonPublicConfiguration: 30,
		.configurationStruct: 21,
		.constructionFunction: 50,
		.consumerCall: 52,
		.consumerErasedCall: 13,
		.consumerErasedInline: 2,
		.consumerFillReentersPublicMock: 0,
		.consumerFillsHole: 2,
		.consumerInline: 22,
		.consumerPassesHoleBuilderUp: 7,
		.consumerPassesInstance: 18,
		.consumerSendableFactory: 10,
		.defaultRewritten: 54,
		.forwardedProvider: 1,
		.holeBuilder: 24,
		.isolatedConstruction: 1,
		.moduleConfiguration: 50,
		.publicTier: 65,
		.secondTier: 48,
		.stagedHoleBuilder: 1,
		.thirdTier: 3,
	]

	static let publicMockCorpusSeedCount = 1_000
	static let publicMockCorpusFixtureHash: UInt64 = 0x4C64A1EAB031F06B
	static let publicMockCorpusAcceptedSeedCount = 747
	static let publicMockCorpusAcceptedSeedsSum: UInt64 = 0x49F6381819B5B6A9
	/// How many of the public mock corpus's graphs the tool accepts as drawn and as their known-right path, which the
	/// value oracle compares.
	static let publicMockCorpusValueOracleInspectedGraphCount = 747
	/// How many of the public mock corpus's graphs the tool rejects because a caller provides a value the tier of the public
	/// mock it calls omits (`leafTierOmitsProvidedValue`), which the long run counts as it counts the seam's.
	static let publicMockCorpusOmittedValueGraphCount = 97
	/// How many of the public mock corpus's graphs the tool rejects with each of a public mock's own errors, in the order
	/// of `GraphFuzzerOracle.publicMockOnlyErrorMarkers`: the public tier, a narrower enclosing type, a leaf tier and a
	/// nested leaf tier omitting a provided value, the mock condition, the by-name check, and the view that cannot call.
	static let publicMockCorpusErrorGraphCounts = [123, 0, 97, 0, 36, 0, 0]

	/// The ordinary suite's batch of the public mock corpus: graphs the tool accepts – a consumer in the same package
	/// calling a public mock with `analytics.instance` of the wrapper it holds, M8.32's stated divergence, of a `@MainActor`
	/// type whose public tier passes its own provider-defaulted parameter on (seed 0); a third tier, with a consumer in the
	/// same package only (seed 43); a `Sendable` wrapper above the leaf, a construction function isolated as the initializer
	/// it calls, and a leaf reached through an `ErasedInstantiator` (seed 46); both consumer modules, a differing mock
	/// condition and a configuration whose members are all narrower than `public` (seed 142); two leaves that each build
	/// the `session` their caller cannot name, M8.9b's, a leaf reached through an erased constant, and a hole's builder
	/// passed up (seed 151); a consumer in another package filling a hole whose fill builds the `.public` type again
	/// through an `Instantiator`, a fully lazy cycle (seed 197); a staged builder for a hole beneath a `Sendable` wrapper
	/// (seed 211); a consumer in another package only and a differing mock condition (seed 253); a configuration's
	/// module-level forwarder of a default's provider, and a hole's builder passed up into a `@Sendable` builder function
	/// (seed 551) – a graph the public tier rejects (seed 7), and a graph of the configuration order's known issue (seed
	/// 23). Between them its passing graphs show every output feature `publicMockCorpusOutputFeatureMinimumShares` pins,
	/// which `publicMockSmokeSeeds_exercisePublicMockFeature_inGraphsTheToolAccepts` checks. Pinned by
	/// `publicMockSmokeAndKnownIssueFixtureHash`.
	static let publicMockSmokeSeeds: [UInt64] = [0, 7, 23, 43, 46, 142, 151, 197, 211, 253, 551]

	static let publicMockSmokeAndKnownIssueFixtureHash: UInt64 = 0x44F5B09789F791E4

	/// Seeds in `0..<publicMockCorpusSeedCount` whose graphs fail today, by shape. Every seed is the feature's own: the
	/// draw shares no graph with the base corpus.
	static let publicMockKnownIssues: [GraphFuzzerKnownIssue] = [
		GraphFuzzerKnownIssue(
			reason: "SafeDIMockConfiguration.swift declares its configurations (public mocks' module-level structs among them) in the order of the roots that reach them",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock configuration code")],
			seeds: [
				2, 5, 8, 16, 21, 23, 26, 28, 29, 42, 48, 50, 56, 58, 59, 63,
				64, 65, 71, 79, 88, 90, 99, 101, 103, 110, 111, 115, 131, 133, 137, 146,
				148, 150, 152, 157, 158, 168, 175, 178, 192, 199, 204, 209, 219, 220, 225, 231,
				240, 241, 242, 247, 248, 256, 257, 259, 267, 269, 270, 274, 275, 276, 282, 289,
				295, 297, 301, 306, 308, 309, 310, 314, 325, 333, 336, 338, 349, 351, 360, 365,
				367, 368, 369, 374, 378, 380, 381, 389, 398, 402, 405, 412, 414, 415, 417, 419,
				421, 426, 428, 435, 436, 441, 451, 456, 459, 469, 475, 477, 479, 482, 492, 496,
				497, 498, 504, 511, 515, 523, 525, 527, 529, 530, 542, 549, 553, 555, 562, 564,
				580, 584, 586, 587, 592, 597, 598, 600, 603, 610, 611, 613, 615, 618, 619, 623,
				624, 625, 627, 632, 635, 637, 639, 642, 645, 651, 652, 668, 671, 672, 673, 681,
				683, 684, 690, 691, 693, 697, 700, 706, 709, 714, 716, 721, 723, 726, 727, 732,
				735, 738, 740, 745, 747, 748, 751, 753, 754, 755, 756, 759, 760, 762, 765, 772,
				773, 774, 777, 783, 784, 790, 793, 798, 805, 817, 821, 825, 827, 828, 837, 845,
				846, 848, 851, 854, 862, 868, 873, 878, 880, 881, 889, 891, 895, 896, 901, 907,
				909, 911, 912, 923, 925, 932, 936, 937, 945, 946, 958, 959, 964, 968, 970, 976,
				978, 979, 984, 985, 991, 993, 995,
			],
		),
		GraphFuzzerKnownIssue(
			reason: "A public mock's parameters are sorted by label (decision 27), so reversing the labels reorders a `.public` consumer's `mock()` and the parameters it surfaces from its leaves",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock code")],
			seeds: [106, 251, 407, 708, 771, 947],
		),
		// The base corpus's shape, in a consumer that builds a `.public` type's tree inline with a fill that closes a lazy
		// cycle through it.
		GraphFuzzerKnownIssue(
			reason: "A mock's API follows the order of type names or labels: which back-edge of a lazy cycle loses its override, which promoted sibling is passed nil, and the order of overrides",
			signatures: [.renamedGraphDiffers(containing: "changes its generated mock code")],
			seeds: [33, 832],
		),
		// The base corpus's shape, a main defect, in the known-right path's inline mock: the comparator cannot compile it.
		GraphFuzzerKnownIssue(
			reason: "A type receives a label as one type while a type built inside it receives the label as another, and the mock rebinds the first under the label inside the receiver's builder function, where the second then reads it",
			signatures: [.valueComparatorCouldNotDescribeGraph(containing: "cannot convert value of type")],
			seeds: [574],
		),
	]

	/// How many of the public mock corpus's graphs each shape of `GraphFuzzerPublicMockDraw` lands in, exactly, so a draw
	/// that stops landing, or a change in a shape's share, fails
	/// `publicMockCorpus_drawsEachShapeInThePinnedNumberOfGraphs_whenFixturesAreGeneratedWithoutTheTool`.
	static let publicMockCorpusDrawFeatureCounts: [GraphFuzzerPublicMockDrawFeature: Int] = [
		.allNonPublicConfiguration: 307,
		.allowlistedParameterType: 138,
		.bothConsumerModules: 393,
		.childDefaultNamingOwnStaticMember: 452,
		.closureDefault: 225,
		.consumerHoldsLazilyInstantiatedWrapper: 378,
		.consumerHoldsOmittedValue: 220,
		.consumerInstantiatesLeaf: 655,
		.consumerReachesHoleTypeWithFill: 155,
		.consumerReachesHoleTypeWithoutFill: 166,
		.consumerReceivesLeaf: 550,
		.customMockName: 369,
		.declaringModuleConfigurationFile: 30,
		.erasedConstantLeaf: 119,
		.erasedInstantiatorLeaf: 116,
		.extensionBasedInstantiable: 212,
		.fakeExtensionPackage: 165,
		.fakeMockDefaultedParameter: 344,
		.fakeMockDependencyBoundParameter: 221,
		.fakeTypeInternal: 344,
		.holderlessOmittedValue: 66,
		.holeBeneathInstantiator: 67,
		.holeBeneathLazilyInstantiated: 82,
		.holeBeneathSendableWrapper: 21,
		.holeCallerInOtherPackage: 278,
		.holeCallerInSamePackage: 120,
		.holeDeclaredAsErasedConstant: 77,
		.holeDeclaredAsErasedInstantiator: 73,
		.holeDeclaredAsExistential: 86,
		.holeDeclaredAsInstantiator: 34,
		.holeFillClosesLazyCycle: 15,
		.holeFillReceivesField: 24,
		.holeFillReceivesNonField: 58,
		.holeOnPublicMockType: 228,
		.holeScopeHoldsPackageValue: 103,
		.holeScopeHoldsPublicValue: 140,
		.instantiableParameterType: 235,
		.internalInitializer: 520,
		.lazilyInstantiatedOmittedValueProvider: 68,
		.lazilyReceivedLabelWithOnlyIfAvailableByValueReceive: 227,
		.mainActorChildInitializerSpellsIsolation: 66,
		.mainActorChildIsolatedInitializer: 141,
		.mainActorChildNonisolatedInitializer: 40,
		.mockConditionDiffers: 103,
		.namespaceExtensionPackage: 93,
		.namespaceExtensionPublic: 44,
		.namespaceExtensionUnspelled: 78,
		.narrowerTreeType: 878,
		.nonOptionalDefault: 694,
		.omittedValueProviderAfterLeaf: 119,
		.omittedValueProviderAndLeafReceiveEachOther: 64,
		.omittedValueProviderBeforeLeaf: 120,
		.omittedValueProviderUnderSendableBuilder: 36,
		.onePublicMockType: 369,
		.optionalDefaultOfPackageType: 282,
		.optionalDefaultOfPublicType: 267,
		.optionalDefaultOfUnprovenType: 325,
		.otherPackageConsumerModuleOnly: 301,
		.packageInitializer: 797,
		.plainTypeOnlyDefaultArgumentsName: 325,
		.plainTypeOnlyPackageInitializersTake: 214,
		.plainTypePublicInitializerTakes: 200,
		.protocolSlotFilledByFake: 686,
		.publicConsumer: 331,
		.publicConsumerLeavesLeafLabelUnprovided: 103,
		.qualifiedAllowlistedParameterType: 93,
		.requiredParameterNarrowerThanPublic: 96,
		.samePackageConsumerModuleOnly: 306,
		.sendableErasedInstantiatorLeaf: 15,
		.sendableWrapperAboveLeaf: 189,
		.spelledChildDefault: 147,
		.spelledClosure: 84,
		.spelledConsumerPasses: 109,
		.spelledExistential: 129,
		.spelledForwarded: 157,
		.spelledGeneric: 145,
		.spelledNested: 128,
		.spelledNonOptionalDefault: 150,
		.spelledOnlyIfAvailableReceive: 159,
		.spelledOptionalClosure: 136,
		.spelledOptionalDefault: 169,
		.spelledPlain: 118,
		.spelledRequiredReceive: 213,
		.spelledSendableClosure: 123,
		.spelledTuple: 120,
		.spelledTypealias: 127,
		.threePublicMockTypes: 332,
		.twoLeavesReceiveUnnameableDependency: 43,
		.twoPublicMockTypes: 299,
		.typeInExtensionOfInstantiable: 219,
	]

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
		GraphFuzzerKnownIssue(
			reason: "A mock promotes the optional form of the mocked type's own alias, which a promoted dependency's tree requires, and builds a node and an override that nothing reads, since the receiver is handed the alias",
			signatures: [.compilerWarning(containing: "was never used")],
			seeds: [916],
		),
	]

	/// Known issues for the tests of `GraphFuzzerFinding`, which must not depend on what `knownIssues` lists today.
	private static let valueDivergenceKnownIssue = GraphFuzzerKnownIssue(
		reason: "A documented divergence",
		signatures: [.seamBuildsOtherValuesThanInline(containing: "known right: aliasAuth: nil")],
		seeds: [430],
	)
	private static let documentedDifference = "probe `Root()` at <1> Root > aliasSeam > aliasDetail > aliasAuth:\n  feature:     aliasAuth: <2> Value (seen, first at <1> Root > aliasSource)\n  known right: aliasAuth: nil"
	private static let undocumentedDifference = "probe `Root()` at <1> Root > aliasSeam > aliasRight > aliasToken:\n  feature:     aliasToken: nil\n  known right: aliasToken: <3> Value"

	/// The runs of the first seam smoke graph the tool accepts with its seam and without it whose root passes a value
	/// for a tier parameter that defaults to `nil`, with its seam build's files and warnings.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func valueProbeRuns() async throws -> (runs: GraphFuzzerToolRuns, seamFiles: [String: String], warnings: [String]) {
		for seed in seamSmokeSeeds {
			let runs = try await GraphFuzzerOracle.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree]), renamings: [])
			guard case let .accepted(seamFiles, warnings) = runs.firstOutcome, case .accepted = runs.inlineOutcome, passingNil(forADefaultedParameterIn: seamFiles, of: runs.fixture) != nil else { continue }
			return (runs, seamFiles, warnings)
		}
		throw GraphFuzzerTestError.noSmokeGraphPassesValueForDefaultedParameter
	}

	/// `seamFiles` with the first call, in a root's file, of a seam tier's parameter that defaults to `nil` passing
	/// `nil` instead of the value it passed, with the parameter's label; or `nil` when no root's call passes a value
	/// for such a parameter.
	private static func passingNil(forADefaultedParameterIn seamFiles: [String: String], of fixture: GraphFuzzerFixture) -> (files: [String: String], label: String)? {
		for (_, contents) in seamFiles.sorted(by: { $0.key < $1.key }) where contents.contains("public enum __safeDI_") {
			for initializer in GraphFuzzerOracle.seamInitializerParameters(inGeneratedFile: contents) {
				for parameter in initializer.parameters where parameter.hasSuffix("= nil") {
					let label = parameter.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
					for (rootFileName, rootContents) in seamFiles.sorted(by: { $0.key < $1.key }) where rootFileName.hasPrefix("\(fixture.typeNamePrefix)Root") {
						// The arguments of the first call of the seam: up to the parenthesis that closes it.
						guard let callRange = rootContents.range(of: "\(initializer.seamTypeName)(") else { continue }
						var depth = 1
						var callEnd = callRange.upperBound
						while depth > 0, callEnd < rootContents.endIndex {
							switch rootContents[callEnd] {
							case "(": depth += 1
							case ")": depth -= 1
							default: break
							}
							callEnd = rootContents.index(after: callEnd)
						}
						guard let argument = rootContents[callRange.upperBound..<callEnd].range(of: "\(label): \(label)") else { continue }
						var files = seamFiles
						files[rootFileName] = rootContents.replacingCharacters(in: argument, with: "\(label): nil")
						return (files, label)
					}
				}
			}
		}
		return nil
	}

	private static let compilerErrorKnownIssue = GraphFuzzerKnownIssue(
		reason: "A shape whose generated code redeclares a label",
		signatures: [.compilerError(containing: "invalid redeclaration")],
		seeds: [84],
	)
	private static let compilerWarningKnownIssue = GraphFuzzerKnownIssue(
		reason: "A shape whose generated code binds a value it never reads",
		signatures: [.compilerWarning(containing: "was never used")],
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
	static func knownIssueListProblems(_ knownIssues: [GraphFuzzerKnownIssue] = knownIssues, corpusSeedCount: Int = corpusSeedCount) -> [String] {
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

	static func fixtureHash(forSeeds seeds: [UInt64], features: Set<GraphFuzzerGeneratorFeature> = []) -> UInt64 {
		var hash = GraphFuzzerHash()
		for seed in seeds {
			hash.combine(GraphFuzzerGenerator.fixture(forSeed: seed, features: features).description)
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
			withKnownIssue("Seed \(fixture.seed) no longer fails, so \(Self.corpus(for: GraphFuzzerGeneratorFeature.features(drawnIn: fixture)).staleSeedRemedy(knownIssue, fixture.seed)): \(knownIssue.reason)") {}
		case let .failure(failure):
			Issue.record(failure.issueComment(fixture: fixture))
		}
	}
}

/// The smoke batch's results, computed once per process and shared by the tests that check them.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let smokeResults = Task {
	try await GraphFuzzerOracle.results(forSeeds: SafeDIToolGraphFuzzerTests.smokeSeeds)
}

/// The seam smoke batch's results, drawn with the `generateDependencyTree` feature, computed once per process.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let seamSmokeResults = Task {
	try await GraphFuzzerOracle.results(forSeeds: SafeDIToolGraphFuzzerTests.seamSmokeSeeds, features: [.generateDependencyTree])
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
	/// The generator features the run's graphs are drawn with, which select the corpus and its pins, or `nil` when
	/// `SAFEDI_GRAPH_FUZZER_FEATURES` names a feature that does not exist, which the run reports.
	let features: Set<GraphFuzzerGeneratorFeature>?
	/// A file the run appends its progress to, which `graph-fuzzer.yml` reads: `seed <n>` before the tool first
	/// runs each graph; `failure <seed> <kind>`, `known <seed> <reason>`, or `stale <seed> <reason>` for each
	/// finding; `renamed <seed> <summary>` and `multimodule <seed> <summary>` for each renamed or partitioned run
	/// that gives other results, whether or not the graph fails another way; `problem <text>` for anything wrong
	/// with the run itself; `partitions …` with how many base corpus graphs are split into each number of modules and
	/// how many have a `Delta` depending on `Gamma`, whose two integrations combine declarations in different orders; and
	/// `completed …` at the end.
	let reportPath: String?

	/// `nil` unless `SAFEDI_GRAPH_FUZZER_ITERATIONS` is set: to a count of seeds, or to `corpus` for the seed count
	/// of the corpus `SAFEDI_GRAPH_FUZZER_FEATURES` selects – a comma-separated list of `GraphFuzzerGeneratorFeature`
	/// names, or unset for the corpus drawn without features. Anything else becomes zero, which the run reports.
	static var current: GraphFuzzerLongRunConfiguration? {
		let environment = ProcessInfo.processInfo.environment
		guard let iterations = environment["SAFEDI_GRAPH_FUZZER_ITERATIONS"] else { return nil }
		let featureNames = (environment["SAFEDI_GRAPH_FUZZER_FEATURES"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
		let features = featureNames.compactMap(GraphFuzzerGeneratorFeature.init(rawValue:))
		let validFeatures: Set<GraphFuzzerGeneratorFeature>? = features.count == featureNames.count ? Set(features) : nil
		return GraphFuzzerLongRunConfiguration(
			iterations: iterations == "corpus" ? validFeatures.map { SafeDIToolGraphFuzzerTests.corpus(for: $0).seedCount } ?? 0 : Int(iterations) ?? 0,
			startingSeed: environment["SAFEDI_GRAPH_FUZZER_STARTING_SEED"].flatMap { UInt64($0) } ?? 0,
			features: validFeatures,
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

private enum GraphFuzzerTestError: Error {
	case noSmokeGraphPassesValueForDefaultedParameter
}
