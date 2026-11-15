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

	// MARK: Which builders a parameter accepts

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private static let service = GraphFuzzerBuilderSurface.BuilderFacts(fillingType: "ServiceImpl", returnedType: "any Service", isSendable: false)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private static let sendableService = GraphFuzzerBuilderSurface.BuilderFacts(fillingType: "ServiceImpl", returnedType: "any Service", isSendable: true)

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_takesEveryForm_whenParameterTypeForwardsNothing() {
		for parameterType in ["@escaping () -> any Service", "Instantiator<any Service>.Builder", "ErasedInstantiator<(), any Service>.Builder", "ErasedInstantiator<ServiceImpl.ForwardedProperties, any Service>.Builder"] {
			for form in GraphFuzzerBuilderSurface.BuilderForm.allCases {
				#expect(GraphFuzzerBuilderSurface.accepts(parameterType: parameterType, facts: Self.service, form: form), "\(parameterType) \(form)")
			}
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
		#expect(GraphFuzzerBuilderSurface.accepts(parameterType: "@escaping @Sendable () -> any Service", facts: Self.service, form: .closure))
		#expect(GraphFuzzerBuilderSurface.accepts(parameterType: "SendableInstantiator<any Service>.Builder", facts: Self.sendableService, form: .storedClosure))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func accepts_rejectsEveryForm_whenParameterForwardsValuesOrReturnsAnotherType() {
		for form in GraphFuzzerBuilderSurface.BuilderForm.allCases {
			#expect(!GraphFuzzerBuilderSurface.accepts(parameterType: "ErasedInstantiator<Int, any Service>.Builder", facts: Self.service, form: form))
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

	// MARK: Edits

	@Test(arguments: [
		(GraphFuzzerBuilderSurfaceEdit.secondPlaceInAnotherType, GraphFuzzerGeneratorFeature.generateDependencyTree, UInt64(15)),
		(.placeBehindLazilyInstantiated, .generateDependencyTree, 15),
		(.placeForwardingOtherValuesRemedied, .generateDependencyTree, 15),
		(.placeBehindLazilyInstantiated, .generateMockPublic, 3),
		(.instantiatorPlaceMovedToPlainPlace, .generateMockPublic, 18),
		(.instantiatorChangedToErasedInstantiator, .generateMockPublic, 18),
		(.placeOfNewBuilderOfExistingFillingType, .generateMockPublic, 2),
		(.placeForwardingOtherValuesRemedied, .generateMockPublic, 3),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_drawsEditTheToolAccepts_forNamedSeed(edit: GraphFuzzerBuilderSurfaceEdit, feature: GraphFuzzerGeneratorFeature, seed: UInt64) async throws {
		let fixture = try #require(GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature], builderSurfaceEdit: edit))
		#expect(fixture.swiftFileContent != GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature]).swiftFileContent)
		guard case .accepted = try await GraphFuzzerOracle.toolOutcome(of: fixture) else {
			Issue.record("The tool rejects seed \(seed)'s \(edit.rawValue) edit")
			return
		}
	}

	@Test(arguments: [(GraphFuzzerGeneratorFeature.generateDependencyTree, UInt64(15)), (.generateMockPublic, 3)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_drawsPlacesTheToolMergesToday_whenTheyForwardOtherValues(feature: GraphFuzzerGeneratorFeature, seed: UInt64) async throws {
		// Part (iii)'s finding on main: places of one builder that forward other values are accepted, where the contract
		// asks for a rejection, which `GraphFuzzerToolRuns.forwardedValuesFailure` reports.
		let fixture = try #require(GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature], builderSurfaceEdit: .placeForwardingOtherValues))
		let remedied = try #require(GraphFuzzerGenerator.fixture(forSeed: seed, features: [feature], builderSurfaceEdit: .placeForwardingOtherValuesRemedied))
		let judgment = try await GraphFuzzerBuilderSurface.rejectionJudgment(
			unremedied: GraphFuzzerOracle.toolOutcome(of: fixture),
			remedied: GraphFuzzerOracle.toolOutcome(of: remedied),
			declaringModule: .seamModule,
		)
		#expect(judgment.isJudged)
		#expect(!judgment.problems.isEmpty)
	}

	// MARK: Known issues

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func adding_listsEachSeedOnce_whenShapeSharesSeedsWithEntry() {
		let issues = GraphFuzzerKnownIssue.adding(.builderSurfaceNamesGeneratedType, reason: "Surface", seeds: [2, 3, 9], to: [
			GraphFuzzerKnownIssue(reason: "Order", signatures: [.compilerCrashInGeneratedMock], seeds: [1, 2, 3, 4]),
		])
		#expect(issues.map(\.reason) == ["Order", "Order; and Surface", "Surface"])
		#expect(issues.map(\.seeds) == [[1, 4], [2, 3], [9]])
		#expect(issues.map(\.signatures) == [[.compilerCrashInGeneratedMock], [.compilerCrashInGeneratedMock, .builderSurfaceNamesGeneratedType], [.builderSurfaceNamesGeneratedType]])
	}
}
