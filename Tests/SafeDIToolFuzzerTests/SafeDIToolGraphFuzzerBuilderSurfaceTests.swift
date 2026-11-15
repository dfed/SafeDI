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

/// The builder surface (`GraphFuzzerBuilderSurface`): what a person writes against a seam's readable initializers and a
/// `mock()` names no type SafeDI generates, and keeps compiling across the edits that keep a builder's supply. See
/// "Builders a person writes" in `.claude/rules/seam-and-mock-contract.md`.
struct SafeDIToolGraphFuzzerBuilderSurfaceTests {
	// MARK: The base check

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generatedTypeNamed_returnsEachGeneratedType_whenParameterNamesOne() {
		#expect(GraphFuzzerBuilderSurface.generatedTypeNamed(by: "serviceBuilder: @escaping (Seam.SafeDIScope_Service) -> any Service") == "SafeDIScope_Service")
		#expect(GraphFuzzerBuilderSurface.generatedTypeNamed(by: "serviceBuilder: @escaping @Sendable (Feed.SafeDISendableMockScope_Service) -> Service") == "SafeDISendableMockScope_Service")
		#expect(GraphFuzzerBuilderSurface.generatedTypeNamed(by: "values: Seam.Owner_Scope.service_Values") == "service_Values")
		#expect(GraphFuzzerBuilderSurface.generatedTypeNamed(by: "serviceBuilder: __safeDI_Builder_Service") == "__safeDI_Builder_Service")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generatedTypeNamed_returnsNil_whenParameterTakesOnlyWhatItsPlaceForwards() {
		#expect(GraphFuzzerBuilderSurface.generatedTypeNamed(by: "serviceBuilder: @escaping () -> any Service") == nil)
		#expect(GraphFuzzerBuilderSurface.generatedTypeNamed(by: "screenBuilder: Instantiator<Screen>.Builder") == nil)
		#expect(GraphFuzzerBuilderSurface.generatedTypeNamed(by: "scopeName: String") == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func readableInitializerFindings_reportEveryScopeBuilder_whenSeamCorpusGraphHasHole() async throws {
		guard case let .accepted(generatedFiles, _) = try await GraphFuzzerOracle.toolOutcome(of: GraphFuzzerGenerator.fixture(forSeed: 15, features: [.generateDependencyTree])) else {
			Issue.record("Seam corpus seed 15 is no longer accepted")
			return
		}
		let findings = GraphFuzzerBuilderSurface.readableInitializerFindings(in: generatedFiles)
		#expect(!findings.isEmpty)
		#expect(findings.allSatisfy { $0.reason.hasPrefix("names the generated type `SafeDI") })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func readableInitializerFindings_reportNothing_whenBuildersTakeNoScope() async throws {
		// The hand mutation: seed 15's generated files with every builder rewritten to take nothing, as the planned builder
		// structs' readable initializers will, pass the check that the files as generated fail.
		guard case let .accepted(generatedFiles, _) = try await GraphFuzzerOracle.toolOutcome(of: GraphFuzzerGenerator.fixture(forSeed: 15, features: [.generateDependencyTree])) else {
			Issue.record("Seam corpus seed 15 is no longer accepted")
			return
		}
		let withoutScopes = generatedFiles.mapValues {
			$0.replacingOccurrences(of: #"\([\w.]*SafeDI\w*Scope_\w+\) -> "#, with: "() -> ", options: .regularExpression)
		}
		#expect(!GraphFuzzerBuilderSurface.readableInitializerFindings(in: generatedFiles).isEmpty)
		#expect(GraphFuzzerBuilderSurface.readableInitializerFindings(in: withoutScopes) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func mockFindings_reportScopeBuilder_whenPublicMockCorpusGraphHasHole() async throws {
		guard case let .accepted(generatedFiles, _) = try await GraphFuzzerOracle.toolOutcome(of: GraphFuzzerGenerator.fixture(forSeed: 2, features: [.generateMockPublic])) else {
			Issue.record("Public mock corpus seed 2 is no longer accepted")
			return
		}
		#expect(GraphFuzzerBuilderSurface.mockFindings(in: generatedFiles).contains { $0.reason.contains("SafeDIMockScope_") || $0.reason.contains("SafeDISendableMockScope_") })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func isBuilder_takesBuilderTypes_whenLabelNamesBuilder() {
		for parameter in ["serviceBuilder: @escaping () -> any Service", "serviceBuilder: @escaping @Sendable (Int) -> any Service", "screenBuilder: Instantiator<Screen>.Builder"] {
			#expect(GraphFuzzerBuilderSurface.isBuilder(GraphFuzzerBuilderSurface.Parameter(parameter)), "\(parameter)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func isBuilder_rejectsWrapper_whenItsForwardedTupleHoldsClosure() {
		// A mock's parameter for an erased instantiator it cannot build, which base corpus seed 2611 draws.
		#expect(!GraphFuzzerBuilderSurface.isBuilder(GraphFuzzerBuilderSurface.Parameter("childBuilder: SendableErasedInstantiator<(first: @Sendable () -> Void, second: Int), AnyChild>")))
	}

	// MARK: Which builders a parameter accepts

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private static let service = GraphFuzzerBuilderSurface.BuilderFacts(fillingType: "ServiceImpl", returnedType: "any Service", isSendable: false)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private static let sendableService = GraphFuzzerBuilderSurface.BuilderFacts(fillingType: "ServiceImpl", returnedType: "any Service", isSendable: true)

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private static let forwardingService = GraphFuzzerBuilderSurface.BuilderFacts(fillingType: "ServiceImpl", returnedType: "any Service", isSendable: false, forwardedType: "Int")

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_takesEachFormForwardingNothing_whenParameterTypeForwardsNothing() {
		for parameterType in ["@escaping () -> any Service", "Instantiator<any Service>.Builder", "ErasedInstantiator<(), any Service>.Builder", "ErasedInstantiator<Void, any Service>.Builder"] {
			for form in GraphFuzzerBuilderSurface.BuilderForm.formsForwardingNothing {
				#expect(GraphFuzzerBuilderSurface.accepts(parameterType: parameterType, facts: Self.service, form: form), "\(parameterType) \(form)")
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_rejectsForwardingClosure_whenParameterTypeForwardsNothing() {
		for parameterType in ["@escaping () -> any Service", "ErasedInstantiator<(), any Service>.Builder"] {
			#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: parameterType, facts: Self.forwardingService, form: .forwardingClosure), "\(parameterType)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_takesForwardingClosureAndStoredClosure_whenParameterTypeForwardsTheBuildersValue() {
		for parameterType in ["@escaping (Int) -> any Service", "ErasedInstantiator<Int, any Service>.Builder", "@escaping @Sendable (Int) -> any Service"] {
			#expect(GraphFuzzerBuilderSurface.accepts(parameterType: parameterType, facts: Self.forwardingService, form: .forwardingClosure), "\(parameterType)")
		}
		#expect(GraphFuzzerBuilderSurface.accepts(parameterType: "ErasedInstantiator<Int, any Service>.Builder", facts: Self.forwardingService, form: .storedClosure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_rejectsEveryForm_whenParameterTypeForwardsOtherValues() {
		for form in GraphFuzzerBuilderSurface.BuilderForm.allCases {
			#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping (String) -> any Service", facts: Self.forwardingService, form: form))
			#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "ErasedInstantiator<String, any Service>.Builder", facts: Self.forwardingService, form: form))
			#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "ErasedInstantiator<Int, any Service>.Builder", facts: Self.service, form: form))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_rejectsEveryForm_whenParameterTypeTakesScope() {
		for form in GraphFuzzerBuilderSurface.BuilderForm.allCases {
			#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping (Seam.SafeDIScope_ServiceImpl) -> any Service", facts: Self.service, form: form))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_rejectsStoredClosure_whenSendabilityDiffers() {
		#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping @Sendable () -> any Service", facts: Self.service, form: .storedClosure))
		#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping () -> any Service", facts: Self.sendableService, form: .storedClosure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_takesStoredClosure_whenSendabilityMatches() {
		#expect(GraphFuzzerBuilderSurface.accepts(parameterType: "SendableInstantiator<any Service>.Builder", facts: Self.sendableService, form: .storedClosure))
		#expect(GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping () -> any Service", facts: Self.service, form: .storedClosure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_takesClosure_whenParameterIsSendable() {
		// A closure literal is inferred `@Sendable` where the parameter asks for it.
		#expect(GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping @Sendable () -> any Service", facts: Self.service, form: .closure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_rejectsEveryForm_whenParameterReturnsAnotherType() {
		for form in GraphFuzzerBuilderSurface.BuilderForm.allCases {
			#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping () -> ServiceImpl", facts: Self.service, form: form))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func contractLabel_namesReturnedTypeAndFamily_whenTheyDifferFromFillingType() {
		#expect(GraphFuzzerBuilderSurface.BuilderFacts(fillingType: "ServiceImpl", returnedType: "ServiceImpl", isSendable: false).contractLabel == "serviceImplBuilder")
		#expect(Self.service.contractLabel == "serviceImpl_ServiceBuilder")
		#expect(Self.sendableService.contractLabel == "serviceImpl_ServiceSendableBuilder")
	}

	// MARK: Problems of a call

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func problems_reportNothing_whenCallMatchesItsCallable() {
		let callables = [GraphFuzzerBuilderSurface.Callable(key: "Feature public Seam.init", parameters: [
			GraphFuzzerBuilderSurface.Parameter("user: User"),
			GraphFuzzerBuilderSurface.Parameter("serviceImpl_ServiceBuilder: @escaping () -> any Service"),
			GraphFuzzerBuilderSurface.Parameter("theme: Theme? = nil"),
		])]
		let call = GraphFuzzerBuilderSurface.calls(against: callables, seed: 0)
		#expect(call.map(\.arguments.count) == [2])
		#expect(call.flatMap { GraphFuzzerBuilderSurface.problems(of: $0, against: callables) } == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func problems_reportNothing_whenInstantiatorBuilderCallMeetsPlainClosure() {
		// An `Instantiator<Screen>.Builder` names `Screen.ForwardedProperties` whether or not `Screen` forwards anything, so
		// the call writes a builder that forwards nothing, which a place moved to a plain place keeps taking.
		let drawn = [GraphFuzzerBuilderSurface.Callable(key: "Feature public Seam.mock", parameters: [GraphFuzzerBuilderSurface.Parameter("screenBuilder: Instantiator<Screen>.Builder")])]
		let edited = [GraphFuzzerBuilderSurface.Callable(key: "Feature public Seam.mock", parameters: [GraphFuzzerBuilderSurface.Parameter("screenBuilder: @escaping () -> Screen")])]
		for seed in UInt64(0)..<3 {
			#expect(GraphFuzzerBuilderSurface.calls(against: drawn, seed: seed).flatMap { GraphFuzzerBuilderSurface.problems(of: $0, against: edited) } == [], "seed \(seed)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func problems_reportRenamedBuilderAndNewRequiredParameter_whenEditedSurfaceChangesThem() {
		let drawn = [GraphFuzzerBuilderSurface.Callable(key: "Feature public Seam.init", parameters: [
			GraphFuzzerBuilderSurface.Parameter("serviceImplBuilder: @escaping () -> ServiceImpl"),
		])]
		let edited = [GraphFuzzerBuilderSurface.Callable(key: "Feature public Seam.init", parameters: [
			GraphFuzzerBuilderSurface.Parameter("serviceImpl_ServiceImplBuilder: @escaping () -> ServiceImpl"),
			GraphFuzzerBuilderSurface.Parameter("service: ServiceImpl"),
		])]
		let calls = GraphFuzzerBuilderSurface.calls(against: drawn, seed: 0)
		#expect(calls.flatMap { GraphFuzzerBuilderSurface.problems(of: $0, against: edited) } == [
			"Feature public Seam.init takes no `serviceImplBuilder` after the arguments before it",
			"Feature public Seam.init requires `serviceImpl_ServiceImplBuilder: @escaping () -> ServiceImpl`, which the call does not pass",
			"Feature public Seam.init requires `service: ServiceImpl`, which the call does not pass",
		])
	}

	// MARK: Judgments of hand-built outcomes

	/// An accepted outcome whose one generated file declares `Seam.mock(…)` with `parameters`, as SafeDI writes a mock.
	private static func acceptedMock(_ parameters: [String]) -> GraphFuzzerToolOutcome {
		let lines = ["extension Seam {", "\tpublic static func mock("] + parameters.map { "\t\t\($0)," } + ["\t) -> Seam {", "\t\tSeam()", "\t}", "}"]
		return .accepted(generatedFiles: ["Feature/Seam+SafeDIMock.swift": lines.joined(separator: "\n")], warnings: [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sameSupplyJudgment_reportsNothing_whenEditedSurfaceKeepsBuilder() {
		let drawn = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		let edited = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl", "theme: Theme? = nil"])
		#expect(GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: drawn, edited: edited, seed: 0) == .init(isJudged: true, problems: []))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sameSupplyJudgment_reportsProblemOnlyEditedSurfaceHas_whenEditChangesBuilderType() {
		let drawn = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		let edited = Self.acceptedMock(["serviceImplBuilder: ServiceImpl"])
		#expect(GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: drawn, edited: edited, seed: 0) == .init(isJudged: true, problems: [
			"Feature public Seam.mock takes `serviceImplBuilder: ServiceImpl`, which does not accept serviceImplBuilder: { ServiceImpl() }, in Feature public Seam.mock(serviceImplBuilder: { ServiceImpl() })",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sameSupplyJudgment_reportsRejectionUnjudged_whenToolRejectsEditedGraph() {
		let drawn = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		#expect(GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: drawn, edited: .rejected(diagnostics: "Seam.swift:3:2: error: Cycle"), seed: 0) == .init(isJudged: false, problems: [
			"The tool rejects the edited graph:\nSeam.swift:3:2: error: Cycle",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sameSupplyJudgment_judgesNothing_whenDrawnGraphIsRejected() {
		let edited = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		#expect(GraphFuzzerBuilderSurface.sameSupplyJudgment(drawn: .rejected(diagnostics: "error"), edited: edited, seed: 0) == .init(isJudged: false, problems: []))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addedSupplyJudgment_reportsNothing_whenNewBuilderFollowsExistingOnes() {
		let without = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		let with = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl", "serviceImpl_AnyServiceBuilder: @escaping () -> AnyService"])
		#expect(GraphFuzzerBuilderSurface.addedSupplyJudgment(without: without, with: with) == .init(isJudged: true, problems: []))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addedSupplyJudgment_reportsRenamedBuilder_whenAddedSupplyRenamesExistingBuilder() {
		let without = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		let with = Self.acceptedMock(["serviceImpl_ServiceImplBuilder: @escaping () -> ServiceImpl", "serviceImpl_AnyServiceBuilder: @escaping () -> AnyService"])
		#expect(GraphFuzzerBuilderSurface.addedSupplyJudgment(without: without, with: with) == .init(isJudged: true, problems: [
			"Feature public Seam.mock no longer takes `serviceImplBuilder: @escaping () -> ServiceImpl`; its builders are now `serviceImpl_ServiceImplBuilder`, `serviceImpl_AnyServiceBuilder`",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addedSupplyJudgment_reportsOrder_whenAddedSupplyReordersExistingBuilders() {
		let without = Self.acceptedMock(["gadgetBuilder: @escaping () -> Gadget", "serviceBuilder: @escaping () -> Service"])
		let with = Self.acceptedMock(["serviceBuilder: @escaping () -> Service", "gadgetBuilder: @escaping () -> Gadget"])
		#expect(GraphFuzzerBuilderSurface.addedSupplyJudgment(without: without, with: with) == .init(isJudged: true, problems: [
			"Feature public Seam.mock takes its builders in another order: `serviceBuilder`, `gadgetBuilder`",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addedSupplyJudgment_reportsRejectionUnjudged_whenToolRejectsGraphWithAddedPlaces() {
		let without = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		#expect(GraphFuzzerBuilderSurface.addedSupplyJudgment(without: without, with: .rejected(diagnostics: "Seam.swift:3:2: error: Cycle")) == .init(isJudged: false, problems: [
			"The tool rejects the edited graph:\nSeam.swift:3:2: error: Cycle",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyBuildersJudgment_reportsAddedBuilder_whenRemedyAddsBuilderBesideDrawnOne() {
		let drawn = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		let remedied = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl", "serviceImplForwardingBuilder: @escaping () -> ServiceImpl"])
		let judgment = GraphFuzzerBuilderSurface.remedyBuildersJudgment(drawn: drawn, remedied: remedied)
		#expect(judgment == .init(isJudged: true, problems: [
			"Feature public Seam.mock takes builders `serviceImplBuilder: @escaping () -> ServiceImpl`, `serviceImplForwardingBuilder: @escaping () -> ServiceImpl` with the remedy and `serviceImplBuilder: @escaping () -> ServiceImpl` without it, so the remedied place is not a place of the drawn builder",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyBuildersJudgment_reportsNothing_whenRemedyKeepsDrawnBuilders() {
		let drawn = Self.acceptedMock(["serviceImplBuilder: @escaping () -> ServiceImpl"])
		#expect(GraphFuzzerBuilderSurface.remedyBuildersJudgment(drawn: drawn, remedied: drawn) == .init(isJudged: true, problems: []))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func rejectionJudgment_reportsRejectionElsewhere_whenMeetingModuleReportsNoError() {
		let judgment = GraphFuzzerBuilderSurface.rejectionJudgment(unremedied: .rejected(diagnostics: "Fuzz/FuzzApp/Caller.swift:3:2: error: Forwards other values"), meetingModule: .seamModule)
		#expect(judgment == .init(isJudged: true, problems: [
			"The tool rejects a builder whose places forward other values only outside FuzzFeature, where they meet:\nFuzz/FuzzApp/Caller.swift:3:2: error: Forwards other values",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyJudgment_reportsRejectionUnjudged_whenToolRejectsRemedy() {
		#expect(GraphFuzzerBuilderSurface.remedyJudgment(remedied: .rejected(diagnostics: "Seam.swift:3:2: error: Cycle")) == .init(isJudged: false, problems: [
			"The tool rejects the remedied graph, whose places forward the same values:\nSeam.swift:3:2: error: Cycle",
		]))
	}

	// MARK: Labels

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func labelFindings_reportBuilder_whenLabelNamesNeitherReturnedTypeNorFillingType() {
		guard case let .accepted(generatedFiles, _) = Self.acceptedMock(["holeBuilder: @escaping () -> any Service"]) else { return }
		#expect(GraphFuzzerBuilderSurface.labelFindings(in: generatedFiles).map(\.description) == [
			"Feature public Seam.mock takes `holeBuilder: @escaping () -> any Service`, which contract rule 8 labels `serviceBuilder`",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func labelFindings_reportNothing_whenLabelsFollowContract() {
		guard case let .accepted(generatedFiles, _) = Self.acceptedMock([
			"__safeDI_serviceBuilder: @escaping () -> any Service",
			"serviceImpl_ServiceSendableBuilder: @escaping @Sendable () -> any Service",
			"screenBuilder: Instantiator<Screen>.Builder",
		]) else { return }
		#expect(GraphFuzzerBuilderSurface.labelFindings(in: generatedFiles) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func labelFindings_reportScopeBuilder_whenLabelLeavesOutReturnedType() {
		guard case let .accepted(generatedFiles, _) = Self.acceptedMock(["holeFillBuilder: @escaping (Seam.SafeDIMockScope_HoleFill_AnyHole) -> AnyHole"]) else { return }
		#expect(GraphFuzzerBuilderSurface.labelFindings(in: generatedFiles).map(\.description) == [
			"Feature public Seam.mock takes `holeFillBuilder: @escaping (Seam.SafeDIMockScope_HoleFill_AnyHole) -> AnyHole`, which contract rule 8 labels `holeFill_AnyHoleBuilder`",
		])
	}

	// MARK: Findings

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportLaterFailure_whenKnownBuilderSurfaceFailureDoesNotDocumentIt() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Surface", signatures: [.builderSurface(.builderSurfaceNamesGeneratedType)], seeds: [7])
		let surface = GraphFuzzerFailure(seed: 7, kind: .builderSurfaceNamesGeneratedType, details: "surface")
		let later = GraphFuzzerFailure(seed: 7, kind: .sameSupplyCallStopsCompiling, details: "same supply")
		#expect(GraphFuzzerFinding.findings(failure: surface, laterFailures: [later], knownIssue: knownIssue) == [.failure(later)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportMisfiledSeed_whenGraphDoesNotShowListedBuilderSurfaceKind() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Surface", signatures: [.builderSurface(.builderSurfaceNamesGeneratedType), .builderSurface(.builderLabelBreaksContract)], seeds: [7])
		let surface = GraphFuzzerFailure(seed: 7, kind: .builderSurfaceNamesGeneratedType, details: "surface")
		let findings = GraphFuzzerFinding.findings(failure: surface, knownIssue: knownIssue)
		#expect(findings == [.knownIssue(knownIssue, surface), .staleBuilderSurfaceSignature(knownIssue, .builderLabelBreaksContract)])
		#expect(findings.last?.reportLine(seed: 7) == "misfiled 7 Surface: the graph does not show \(GraphFuzzerFailure.Kind.builderLabelBreaksContract.rawValue); list the seed under the entry that names exactly what it shows")
	}

	// MARK: Edits

	@Test(arguments: [
		(GraphFuzzerBuilderSurfaceEdit.secondPlaceInAnotherType, GraphFuzzerGeneratorFeature.generateDependencyTree, UInt64(15)),
		(.placeBehindLazilyInstantiated, .generateDependencyTree, 15),
		(.placeForwardingOtherValuesRemedied, .generateDependencyTree, 15),
		(.secondPlaceInInnerSeamOfAnotherModule, .generateDependencyTree, 15),
		(.holderMovedToInnerSeamOfAnotherModule, .generateDependencyTree, 15),
		(.placeOfNewBuilderInInnerSeamOfAnotherModule, .generateDependencyTree, 15),
		(.placeForwardingOtherValuesInInnerSeamOfAnotherModuleRemedied, .generateDependencyTree, 15),
		(.placeBehindLazilyInstantiated, .generateMockPublic, 3),
		(.instantiatorPlaceMovedToPlainPlace, .generateMockPublic, 18),
		(.instantiatorChangedToErasedInstantiator, .generateMockPublic, 18),
		(.placeOfNewBuilderOfExistingFillingType, .generateMockPublic, 2),
		(.placeForwardingOtherValuesRemedied, .generateMockPublic, 3),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_drawsEditTheToolAccepts_whenEditAppliesToGraph(edit: GraphFuzzerBuilderSurfaceEdit, feature: GraphFuzzerGeneratorFeature, seed: UInt64) async throws {
		let fixture = try #require(GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature], builderSurfaceEdit: edit))
		#expect(fixture.swiftFileContent != GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature]).swiftFileContent)
		guard case .accepted = try await GraphFuzzerOracle.toolOutcome(of: fixture, listsTransitiveDependencies: edit.listsTransitiveDependencies) else {
			Issue.record("The tool rejects seed \(seed)'s \(edit.rawValue) edit")
			return
		}
	}

	/// Part (iii)'s judgment of `seed`'s graph with a place forwarding other values.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func forwardingOtherValuesJudgment(feature: GraphFuzzerGeneratorFeature, seed: UInt64) async throws -> GraphFuzzerBuilderSurface.PairJudgment {
		let fixture = try #require(GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature], builderSurfaceEdit: .placeForwardingOtherValues))
		return try await GraphFuzzerBuilderSurface.rejectionJudgment(
			unremedied: GraphFuzzerOracle.toolOutcome(of: fixture),
			meetingModule: .seamModule,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func rejectionJudgment_reportsAcceptance_whenSeamCorpusPlacesForwardOtherValues() async throws {
		// Part (iii)'s finding on main: places of one builder that forward other values are merged into one builder, where
		// the contract asks for a rejection, which `GraphFuzzerToolRuns.forwardedValuesFailure` reports. The builder-struct
		// slice that rejects them changes this line to none.
		#expect(try await Self.forwardingOtherValuesJudgment(feature: .generateDependencyTree, seed: 15) == .init(isJudged: true, problems: [
			"The tool accepts a builder whose places forward other values",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func rejectionJudgment_reportsAcceptance_whenPublicMockCorpusPlacesForwardOtherValues() async throws {
		// As in the seam corpus: the builder-struct slice that rejects them changes this line to none.
		#expect(try await Self.forwardingOtherValuesJudgment(feature: .generateMockPublic, seed: 3) == .init(isJudged: true, problems: [
			"The tool accepts a builder whose places forward other values",
		]))
	}

	// MARK: Known issues

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func adding_listsEachSeedOnce_whenShapeSharesSeedsWithEntry() {
		let issues = GraphFuzzerKnownIssue.adding(.builderSurface(.builderSurfaceNamesGeneratedType), reason: "Surface", seeds: [2, 3, 9], to: [
			GraphFuzzerKnownIssue(reason: "Order", signatures: [.compilerCrashInGeneratedMock], seeds: [1, 2, 3, 4]),
		])
		#expect(issues.map(\.reason) == ["Order", "Order; and Surface", "Surface"])
		#expect(issues.map(\.seeds) == [[1, 4], [2, 3], [9]])
		#expect(issues.map(\.signatures) == [[.compilerCrashInGeneratedMock], [.compilerCrashInGeneratedMock, .builderSurface(.builderSurfaceNamesGeneratedType)], [.builderSurface(.builderSurfaceNamesGeneratedType)]])
	}
}
