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
	func readableInitializerFindings_nameGeneratedScopeType_whenSeamCorpusGraphHasHole() async throws {
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
		// the call writes a builder that forwards nothing, and stores one as a `() -> Screen` value, which a place moved to a
		// plain place keeps taking.
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
	func rejectionJudgment_reportsRejectionElsewhere_whenAnotherModuleRejectsAtMeetingModulesDeclaration() {
		// The error's path names the meeting module, where the place is declared, but another module's `generate` rejects
		// the graph: the places' meeting module accepted them.
		let judgment = GraphFuzzerBuilderSurface.rejectionJudgment(unremedied: .rejected(diagnostics: "Fuzz/FuzzFeature/Seam.swift:3:2: error: Forwards other values"), rejectingModuleName: "FuzzApp", meetingModule: .seamModule)
		#expect(judgment == .init(isJudged: true, problems: [
			"FuzzApp, not FuzzFeature, where the places meet, rejects a builder whose places forward other values:\nFuzz/FuzzFeature/Seam.swift:3:2: error: Forwards other values",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func rejectionJudgment_reportsNothing_whenMeetingModuleRejectsAtAnotherModulesDeclaration() {
		// The meeting module's `generate` rejects the graph with an error at a place declared in the inner seam's module.
		let judgment = GraphFuzzerBuilderSurface.rejectionJudgment(unremedied: .rejected(diagnostics: "Fuzz/FuzzSession/Inner.swift:3:2: error: Forwards other values"), rejectingModuleName: "FuzzFeature", meetingModule: .seamModule)
		#expect(judgment == .init(isJudged: true, problems: []))
	}

	/// A graph split into `FuzzFeature`, which declares `S1_Feature`, and `FuzzApp`, whose root instantiates `S1_Feature`,
	/// with `S1_Missing`, which no module declares, instantiated in `missingModule`, by a root of that module, so that its
	/// own `generate` reports it.
	private static func fixtureMissingType(in missingModule: GraphFuzzerModule) -> GraphFuzzerFixture {
		let missingProperty = "\n\n\t@Instantiated let missing: S1_Missing"
		let feature = """
		// module: FuzzFeature
		import SafeDI

		@Instantiable\(missingModule == .seamModule ? "(isRoot: true)" : "")
		public final class S1_Feature: Instantiable {
			public init(\(missingModule == .seamModule ? "missing: S1_Missing" : "")) {\(missingModule == .seamModule ? "\n\t\tself.missing = missing" : "")
			}\(missingModule == .seamModule ? missingProperty : "")
		}
		"""
		let app = """
		// module: FuzzApp
		import FuzzFeature
		import SafeDI

		@Instantiable(isRoot: true)
		public final class S1_Root: Instantiable {
			public init(feature: S1_Feature\(missingModule == .samePackageCaller ? ", missing: S1_Missing" : "")) {
				self.feature = feature\(missingModule == .samePackageCaller ? "\n\t\tself.missing = missing" : "")
			}

			@Instantiated let feature: S1_Feature\(missingModule == .samePackageCaller ? missingProperty : "")
		}
		"""
		return GraphFuzzerFixture(seed: 1, swiftFileContent: [feature, app])
	}

	@Test(arguments: [GraphFuzzerModule.seamModule, .samePackageCaller])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRun_namesModuleWhoseGenerateRejectsSplitGraph_whenOneModuleInstantiatesMissingType(missingModule: GraphFuzzerModule) async throws {
		let run = try await GraphFuzzerOracle.toolRun(of: Self.fixtureMissingType(in: missingModule))
		guard case .rejected = run.outcome else {
			Issue.record("The tool accepts a graph whose \(missingModule.name) instantiates a type no module declares")
			return
		}
		#expect(run.rejectingModuleName == missingModule.name)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func remedyJudgment_reportsRejectionUnjudged_whenToolRejectsRemedy() {
		#expect(GraphFuzzerBuilderSurface.remedyJudgment(remedied: .rejected(diagnostics: "Seam.swift:3:2: error: Cycle")) == .init(isJudged: false, problems: [
			"The tool rejects the remedied graph, whose places forward the same values:\nSeam.swift:3:2: error: Cycle",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func argumentDescription_spellsStoredClosureForwardingNothing_whenInstantiatorBuilderNamesForwardedProperties() {
		// An `Instantiator<Screen>.Builder` names `Screen.ForwardedProperties`, which the surface reads as forwarding nothing,
		// so the call stores a `() -> Screen` value, not a value of the wrapper's `Builder`.
		let facts = GraphFuzzerBuilderSurface.BuilderFacts(fillingType: "Screen", returnedType: "Screen", isSendable: false, surfaceLabel: "screenBuilder", forwardedType: "Screen.ForwardedProperties")
		#expect(GraphFuzzerBuilderSurface.Argument.builder(label: "screenBuilder", facts: facts, form: .storedClosure).description == "screenBuilder: <() -> Screen>")
	}

	/// Tool runs of a graph whose second place of a hole is `place`, whose calling mock takes `withoutParameters` without the
	/// place and `withParameters` with it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func secondPlaceRuns(place: String, withoutParameters: [String], withParameters: [String]) -> GraphFuzzerToolRuns {
		let with = Self.acceptedMock(withParameters)
		return GraphFuzzerToolRuns(
			fixture: GraphFuzzerFixture(seed: 7, swiftFileContent: []),
			firstOutcome: with,
			secondOutcome: with,
			withoutSecondHolePlaceOutcome: (place: place, outcome: Self.acceptedMock(withoutParameters)),
		)
	}

	@Test(arguments: ["t6Twin", "t6Second"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callingMockFailure_reportsAddedBuilder_whenSecondCallOfPublicMockAddsRequiredBuilder(place: String) throws {
		// A second call of a public mock of the hole's type is a second place of the same filling type, returned type and
		// family: the calling mock takes no builder more for it. Added supply would let the new builder through.
		let runs = Self.secondPlaceRuns(place: place, withoutParameters: ["holeBuilder: @escaping () -> Hole"], withParameters: ["holeBuilder: @escaping () -> Hole", "holeBuilder_T6Twin: @escaping () -> Hole"])
		let failure = try #require(runs.callingMockFailure)
		#expect(failure.kind == .callingMockChangesBuilder)
		#expect(failure.details.hasPrefix("secondCallOfPublicMock: Feature public Seam.mock requires `holeBuilder_T6Twin: @escaping () -> Hole`, which the call does not pass, in Feature public Seam.mock(holeBuilder: "))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addedSupplyFailure_reportsNothing_whenSecondErasureAddsBuilderOfExistingFillingType() {
		// A second erasure is a new builder of an existing filling type, which added supply lets through.
		let runs = Self.secondPlaceRuns(place: "holeGadgetOther", withoutParameters: ["holeGadgetImpl_AnyBuilder: @escaping () -> Any"], withParameters: ["holeGadgetImpl_AnyBuilder: @escaping () -> Any", "holeGadgetImpl_AnyOtherBuilder: @escaping () -> AnyOther"])
		#expect(runs.addedSupplyFailure == nil)
	}

	/// Tool runs of a graph with the `@Sendable` twins' base edit, `instantiatorMadeSendable`, whose outcome is `base`, and
	/// the twin `sendableInstantiatorPlaceMovedToPlainPlace`, which the tool accepts.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func sendableTwinRuns(base: GraphFuzzerToolOutcome) -> GraphFuzzerToolRuns {
		let drawn = Self.acceptedMock(["holeBuilder: Instantiator<Hole>"])
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: drawn, secondOutcome: drawn, builderSurfaceRuns: [
			GraphFuzzerBuilderSurfaceRun(edit: .instantiatorMadeSendable, fixture: fixture, outcome: base),
			GraphFuzzerBuilderSurfaceRun(edit: .sendableInstantiatorPlaceMovedToPlainPlace, fixture: fixture, outcome: Self.acceptedMock(["hole: @escaping @Sendable () -> Hole"])),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sameSupplyEditRejectedFailure_reportsNothing_whenToolRejectsSendableFamilyForValueNotSendable() {
		// Public mock corpus seed 333's rejection: a fill receives a `LazilyInstantiated`, which a `@Sendable` function cannot
		// capture, so making the place's `Instantiator` a `SendableInstantiator` is rightly rejected, and the twins pass.
		let runs = Self.sendableTwinRuns(base: .rejected(diagnostics: "<fixture-directory>/FuzzApp/S333_HoleFill.swift:7:33: error: @Received property `holeSession: LazilyInstantiated<S333_HoleSession>` cannot be received inside a `@Sendable` function in chain: S333_T7 -> S333_T6 -> S333_Hole."))
		#expect(runs.sameSupplyEditRejectedFailure == nil)
		#expect(runs.builderSurfaceJudgments.map(\.judgment) == [.init(isJudged: false, problems: [])])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sameSupplyEditRejectedFailure_reportsRejection_whenToolRejectsSendableFamilyOtherwise() throws {
		let runs = Self.sendableTwinRuns(base: .rejected(diagnostics: "<fixture-directory>/FuzzApp/S333_HoleFill.swift:7:33: error: Cycle"))
		let failure = try #require(runs.sameSupplyEditRejectedFailure)
		#expect(failure.details.hasPrefix("sendableInstantiatorPlaceMovedToPlainPlace: The tool rejects the edited graph:\n<fixture-directory>/FuzzApp/S333_HoleFill.swift:7:33: error: Cycle\n"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func builderSurfaceJudgments_judgeLazilyInstantiatedPlaceMovedBack_whenEditMovesPlaceBehindLazilyInstantiated() {
		// The calls written against the edited graph, whose place is behind `LazilyInstantiated`, judged against the drawn
		// graph: a mock that takes the wrapper where the drawn mock takes the value fails both ways.
		let drawn = Self.acceptedMock(["hole: Hole"])
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [])
		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: drawn, secondOutcome: drawn, builderSurfaceRuns: [
			GraphFuzzerBuilderSurfaceRun(edit: .placeBehindLazilyInstantiated, fixture: fixture, outcome: Self.acceptedMock(["hole: LazilyInstantiated<Hole>"])),
		])
		#expect(runs.builderSurfaceJudgments.map(\.kind) == ["placeBehindLazilyInstantiated", "lazilyInstantiatedPlaceMovedBack"])
		#expect(runs.builderSurfaceJudgments.last?.judgment == .init(isJudged: true, problems: [
			"Feature public Seam.mock takes `hole: Hole` where the call passes a `LazilyInstantiated<Hole>`, in Feature public Seam.mock(hole: <LazilyInstantiated<Hole>>)",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func floorKinds_listEveryPairKindTheLongRunCounts_whenReported() {
		#expect(GraphFuzzerBuilderSurface.floorKinds.contains(GraphFuzzerToolRuns.remedyBuildersPairKind))
		#expect(GraphFuzzerBuilderSurface.floorKinds.contains(GraphFuzzerToolRuns.lazilyInstantiatedPlaceMovedBackPairKind))
	}

	// MARK: Hole kinds

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func holeKinds_countLazyAndForwarding_whenBuilderReturnsDrawnPlacesType() {
		guard case let .accepted(generatedFiles, _) = Self.acceptedMock([
			"holeImplBuilder: @escaping (Seam.SafeDIMockScope_HoleImpl_HoleService) -> any S1_HoleService",
			"holeTicketImplBuilder: @escaping @Sendable (Seam.SafeDISendableMockScope_HoleTicketImpl_HoleTicketService) -> any S1_HoleTicketService",
		]) else { return }
		let drawnHolePlaces = [
			GraphFuzzerDrawnHolePlace(kind: .lazy, returnedTypeName: "S1_HoleService"),
			GraphFuzzerDrawnHolePlace(kind: .forwarding, returnedTypeName: "S1_HoleTicketService"),
		]
		#expect(GraphFuzzerBuilderSurface.holeKinds(drawnHolePlaces: drawnHolePlaces, generatedFiles: generatedFiles) == [.plain, .lazy, .forwarding, .sendable])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func holeKinds_countNoLazyPlace_whenOnlyAnotherValueIsLazilyInstantiated() {
		// A public mock's root-level `LazilyInstantiated<HoleSession>` is no hole's place: the draw records no lazy place, so
		// the graph counts toward the plain kind alone, though its fixture spells a lazily instantiated `Hole…` type.
		guard case let .accepted(generatedFiles, _) = Self.acceptedMock([
			"holeBuilder: @escaping (Seam.SafeDIMockScope_HoleFill_AnyHole) -> S1_AnyHole",
			"holeSession: LazilyInstantiated<S1_HoleSession>",
		]) else { return }
		#expect(GraphFuzzerBuilderSurface.holeKinds(drawnHolePlaces: [], generatedFiles: generatedFiles) == [.plain])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func holeKinds_countNoLazyPlace_whenNoJudgedBuilderReturnsDrawnPlacesType() {
		guard case let .accepted(generatedFiles, _) = Self.acceptedMock(["holeBuilder: @escaping (Seam.SafeDIMockScope_HoleFill_AnyHole) -> S1_AnyHole"]) else { return }
		#expect(GraphFuzzerBuilderSurface.holeKinds(drawnHolePlaces: [GraphFuzzerDrawnHolePlace(kind: .lazy, returnedTypeName: "S1_HoleService")], generatedFiles: generatedFiles) == [.plain])
	}

	@Test(arguments: [GraphFuzzerGeneratorFeature.generateMockPublic, .generateDependencyTree])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func drawnHolePlaces_recordEachKindOfPlaceTheFixtureDeclares_whenCorpusDrawsHoles(feature: GraphFuzzerGeneratorFeature) {
		var recordedKinds = [GraphFuzzerDrawnHolePlace.Kind]()
		for seed in UInt64(0)..<100 {
			let source = GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature]).swiftFileContent.joined(separator: "\n")
			for place in GraphFuzzerGenerator.drawnHolePlaces(forSeed: seed, features: [feature]) {
				recordedKinds.append(place.kind)
				#expect(source.contains(place.returnedTypeName), "seed \(seed): \(place)")
			}
		}
		#expect(recordedKinds.contains(.lazy))
		#expect(recordedKinds.contains(.forwarding))
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

	@Test(arguments: [GraphFuzzerFailure.Kind.sameSupplyCallStopsCompiling, .callingMockChangesBuilder, .remedyOfPlacesForwardingOtherValuesRejected, .remedyAddsBuilder])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportLaterBuilderSurfaceFailure_whenKnownHoleNameFailureComesFirst(laterKind: GraphFuzzerFailure.Kind) {
		// A hole name that changes with a second place is checked before the builder surface, and its known failure masks the
		// later failures it does not list; none of the builder surface's, which judge the tool's output alone.
		let knownIssue = GraphFuzzerKnownIssue(reason: "Names", signatures: [.holeNamesChangeWithSecondPlace(containing: "t6Twin")], seeds: [7])
		let names = GraphFuzzerFailure(seed: 7, kind: .holeNamesChangeWithSecondPlace, details: "t6Twin renames a builder")
		let later = GraphFuzzerFailure(seed: 7, kind: laterKind, details: "builder surface")
		#expect(GraphFuzzerFinding.findings(failure: names, laterFailures: [later], knownIssue: knownIssue) == [.failure(later)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportStaleLeakEntry_whenCombinedEntrysLeakIsGoneAndBuilderSurfaceStillFails() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Leak; and Surface", signatures: [.seamRetainsWhatInlineFrees(containing: "_HoleImpl alive"), .builderSurface(.builderSurfaceNamesGeneratedType)], seeds: [7])
		let surface = GraphFuzzerFailure(seed: 7, kind: .builderSurfaceNamesGeneratedType, details: "surface")
		let findings = GraphFuzzerFinding.findings(failure: surface, knownIssue: knownIssue, retentionIsJudged: true)
		#expect(findings == [.knownIssue(knownIssue, surface), .staleLeakEntry(knownIssue)])
		#expect(findings.last?.reportLine(seed: 7) == "stale 7 Leak; and Surface: the graph no longer keeps alive what its leak's entry lists, though it still fails what the seed's other entries list; remove the seed from the leak's entry")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportNoStaleLeakEntry_whenRetentionOracleDidNotJudgeGraph() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Leak; and Surface", signatures: [.seamRetainsWhatInlineFrees(containing: "_HoleImpl alive"), .builderSurface(.builderSurfaceNamesGeneratedType)], seeds: [7])
		let surface = GraphFuzzerFailure(seed: 7, kind: .builderSurfaceNamesGeneratedType, details: "surface")
		#expect(GraphFuzzerFinding.findings(failure: surface, knownIssue: knownIssue, retentionIsJudged: false) == [.knownIssue(knownIssue, surface)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportNoStaleLeakEntry_whenGraphStillLeaks() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Leak; and Surface", signatures: [.seamRetainsWhatInlineFrees(containing: "_HoleImpl alive"), .builderSurface(.builderSurfaceNamesGeneratedType)], seeds: [7])
		let surface = GraphFuzzerFailure(seed: 7, kind: .builderSurfaceNamesGeneratedType, details: "surface")
		let leak = GraphFuzzerFailure(seed: 7, kind: .seamRetainsWhatInlineFrees, details: "leak")
		#expect(GraphFuzzerFinding.findings(failure: surface, laterFailures: [leak], knownIssue: knownIssue, retentionIsJudged: true).contains(.staleLeakEntry(knownIssue)) == false)
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
		// Seed 15 holds `HoleHanded`, which forwards nothing, in an `Instantiator` on `HoleHandedHolder`.
		(.instantiatorPlaceMovedToPlainPlace, .generateDependencyTree, 15),
		(.instantiatorChangedToErasedInstantiator, .generateDependencyTree, 15),
		(.instantiatorMadeSendable, .generateDependencyTree, 15),
		(.sendableInstantiatorPlaceMovedToPlainPlace, .generateDependencyTree, 15),
		(.sendableInstantiatorChangedToSendableErasedInstantiator, .generateDependencyTree, 15),
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
		let run = try await GraphFuzzerOracle.toolRun(of: fixture)
		return GraphFuzzerBuilderSurface.rejectionJudgment(unremedied: run.outcome, rejectingModuleName: run.rejectingModuleName, meetingModule: .seamModule)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func rejectionJudgment_reportsNoProblem_whenSeamCorpusPlacesForwardOtherValues() async throws {
		// The seam's module rejects places of one builder that forward other values, as the contract asks, where the rejected
		// edit's error is reported: the judgment runs and finds nothing for `GraphFuzzerToolRuns.forwardedValuesFailure` to
		// report.
		#expect(try await Self.forwardingOtherValuesJudgment(feature: .generateDependencyTree, seed: 15) == .init(isJudged: true, problems: []))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func rejectionJudgment_reportsAcceptance_whenPublicMockCorpusPlacesForwardOtherValues() async throws {
		// Public mocks still merge such places into one builder; the change that rejects them there changes this line to none.
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
