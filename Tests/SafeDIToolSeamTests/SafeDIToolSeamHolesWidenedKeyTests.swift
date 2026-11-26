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
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The key `SeamHoles` is to answer by: a place's node and edge, the innermost fill enclosing it (the declaration of the call
/// whose builder it fills, and the case), and the family. Every answer generated code reads (`SeamHolesPathAnswer`, every
/// column but the whole hole, `site`, whose route and fields only a signature reads) must be the same on every path that
/// ends on one key. The first tests nest fills two and three deep under outer fills that differ, by call or by case, with
/// everything inside them equal, so an outer fill that mattered would show; the others run, under the key, the smallest
/// test of each kind of disagreement the path-keyed maps showed.
struct SafeDIToolSeamHolesWidenedKeyTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Nested fills

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func seamHoles_answerAlikeByInnermostFill_whenFillsNestTwoDeepUnderOuterFillsOfTwoCalls() async throws {
		// `Outer` calls `First` and `Second`, whose holes it fills with `ThingImpl`, which calls `Inner`; `Outer` fills `Inner`'s
		// hole with `ServiceImpl`, which holds `gizmo`, a place only `App` fills. The place is inside the fill of `Inner`'s
		// `service` at `c: Inner`, inside a fill of `First`'s or `Second`'s `thing`.
		let answers = try await answersOfOuter(
			base: Self.protocols + [
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "First", isSeam: true, declarations: ["@Instantiated public let thing: any Thing"]),
				seamFixtureType(named: "Second", isSeam: true, declarations: ["@Instantiated public let thing: any Thing"]),
			],
			top: [
				Self.fulfillingType(named: "ThingImpl", fulfilling: "Thing", declarations: ["@Instantiated public let c: Inner"]),
				Self.fulfillingType(named: "ServiceImpl", fulfilling: "Service", declarations: ["@Instantiated public let gizmo: any Gizmo"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let a: First", "@Instantiated public let b: Second"]),
			],
		)
		expectAgreement(of: answers, withOuterFillsAtLeast: 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func seamHoles_answerAlikeByInnermostFill_whenFillsNestThreeDeepUnderOuterFillsOfTwoCalls() async throws {
		// As above, one fill deeper: `ServiceImpl` calls `Deepest`, whose `part` `Outer` fills with `PartImpl`, which holds
		// `gizmo`.
		let answers = try await answersOfOuter(
			base: Self.protocols + [
				seamFixtureType(named: "Deepest", isSeam: true, declarations: ["@Instantiated public let part: any Part"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "First", isSeam: true, declarations: ["@Instantiated public let thing: any Thing"]),
				seamFixtureType(named: "Second", isSeam: true, declarations: ["@Instantiated public let thing: any Thing"]),
			],
			top: [
				Self.fulfillingType(named: "ThingImpl", fulfilling: "Thing", declarations: ["@Instantiated public let c: Inner"]),
				Self.fulfillingType(named: "ServiceImpl", fulfilling: "Service", declarations: ["@Instantiated public let d: Deepest"]),
				Self.fulfillingType(named: "PartImpl", fulfilling: "Part", declarations: ["@Instantiated public let gizmo: any Gizmo"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let a: First", "@Instantiated public let b: Second"]),
			],
		)
		expectAgreement(of: answers, withOuterFillsAtLeast: 2)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func seamHoles_answerAlikeByInnermostFill_whenFillsNestTwoDeepUnderTwoOuterCasesOfOneCall() async throws {
		// `First` holds two holes, `thing` and `other`, which `Outer` fills with types that each call `Inner`: the place inside
		// `Inner`'s fill sits under two cases of one outer call.
		let answers = try await answersOfOuter(
			base: Self.protocols + [
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
				seamFixtureType(named: "First", isSeam: true, declarations: ["@Instantiated public let thing: any Thing", "@Instantiated public let other: any Other"]),
			],
			top: [
				Self.fulfillingType(named: "ThingImpl", fulfilling: "Thing", declarations: ["@Instantiated public let c: Inner"]),
				Self.fulfillingType(named: "OtherImpl", fulfilling: "Other", declarations: ["@Instantiated public let c: Inner"]),
				Self.fulfillingType(named: "ServiceImpl", fulfilling: "Service", declarations: ["@Instantiated public let gizmo: any Gizmo"]),
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let a: First"]),
			],
		)
		expectAgreement(of: answers, withOuterFillsAtLeast: 1)
	}

	// MARK: The smallest test of each kind of disagreement

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamHoles_answerAlikeByInnermostFill_whenPlaceIsInsideFillsOfTwoCalls() async throws {
		// The call entry: one node and edge inside the fills of `inner` and `innerB`.
		var suite = SafeDIToolSeamDeferredParameterBesideReceivedWrapperTests()
		let answers = try await SeamHolesPathAgreementChecks.runs { try await suite.generate_throwsParametersShareLabelAtEachDeferringSeam_whenPlaceOfCaseNestedByTypeIsReachedThroughTwoDeferringSeams() }
		expectAgreement(of: answers, withOuterFillsAtLeast: 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamHoles_answerAlikeByFamily_whenPlaceIsReachedInsideAndOutsideSendableFunction() async throws {
		var suite = SafeDIToolSeamPlaceInsideFillTests()
		let answers = try await SeamHolesPathAgreementChecks.runs { try await suite.generate_holdsInnersSendableScopeInSendableCase_whenFillOfPlaceInsideSendableFunctionHoldsPlace() }
		expectAgreement(of: answers, withOuterFillsAtLeast: 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamHoles_answerAlikeByKey_whenPlaceCarriesOtherFieldsOnEachPath() async throws {
		// Per-path fields: `Model.userService` carries `desk` at the root and `token` under `Desk`.
		var suite = SafeDIToolSeamScopeByTypeFillValueTests()
		let answers = try await SeamHolesPathAgreementChecks.runs { try await suite.generate_handsFillCallersTokenInstance_whenCallerHoldsTokenLazilyBesideLevelsPlainToken() }
		expectAgreement(of: answers, withOuterFillsAtLeast: 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamHoles_answerAlikeByKey_whenRouteToPlaceDiffersBeforeItsLastStep() async throws {
		// `Cell.gadget` reached through `rowA` and `rowB`: the route differs before its last step, which only the whole hole holds.
		var suite = SafeDIToolSeamSendableMemberCallTests()
		let answers = try await SeamHolesPathAgreementChecks.runs { try await suite.generate_declaresBuilderFunctionOnce_whenTypeBuiltOnTwoPathsInsideSendableFunctionHoldsPlace() }
		expectAgreement(of: answers, withOuterFillsAtLeast: 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamHoles_answerAlikeByKey_whenScopeClosesCycleOnTheSameNodeAndEdge() async throws {
		var suite = SafeDIToolSeamPlaceLevelTests()
		let answers = try await SeamHolesPathAgreementChecks.runs { try await suite.holes_giveEveryBuildOfATypeTheSameLevels_whenTwoInstantiatorsCloseEachOthersCycle() }
		expectAgreement(of: answers, withOuterFillsAtLeast: 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamHoles_answerAlikeByKey_whenFillOfCaseEmitsNoCode() async throws {
		var suite = SafeDIToolSeamPlaceInsideFillTests()
		let answers = try await SeamHolesPathAgreementChecks.runs { try await suite.generate_readsValueThroughReaderOnRouteThatHoldsIt_whenFirstPlaceOfInnersCaseHoldsNone() }
		expectAgreement(of: answers, withOuterFillsAtLeast: 0)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let protocols = ["public protocol Service {}\npublic protocol Gadget {}\npublic protocol Thing {}\npublic protocol Other {}\npublic protocol Part {}\npublic protocol Gizmo {}"]

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// The answers `Outer`'s tree reads, in `Top`, over `Base`; `App` builds `Outer` and fills `Gizmo`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func answersOfOuter(base: [String], top: [String]) async throws -> [SeamHolesPathAgreementChecks.Answers] {
		let modules = [
			ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: base),
			ModuleFixture(name: "Top", packageName: "Other", swiftFileContent: top.map { "import Base\n\n" + $0 }, dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				Self.fulfillingType(named: "GizmoImpl", fulfilling: "Gizmo", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			].map { "import Base\nimport Top\n\n" + $0 }, dependencies: ["Base", "Top"]),
		]
		var filesToDelete = filesToDelete
		defer { self.filesToDelete = filesToDelete }
		return try await SeamHolesPathAgreementChecks.runs {
			_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	/// Expects every key, widened to the innermost fill and the family, to read one answer in each column generated code
	/// reads, and the fills to nest at least `minimumOuterFills` deep somewhere, so the shape is the one named.
	private func expectAgreement(of runs: [SeamHolesPathAgreementChecks.Answers], withOuterFillsAtLeast minimumOuterFills: Int, sourceLocation: SourceLocation = #_sourceLocation) {
		let deepestOuterFills = runs.flatMap { $0.outerFillsByAnswerByKey.values.flatMap(\.values).flatMap(\.self) }.map { $0.isEmpty ? 0 : $0.components(separatedBy: " <- ").count }.max() ?? 0
		#expect(deepestOuterFills >= minimumOuterFills, "fills nest \(deepestOuterFills) deep outside the innermost", sourceLocation: sourceLocation)
		#expect(runs.contains { !$0.pathsByAnswerByKey.isEmpty }, sourceLocation: sourceLocation)
		for answers in runs {
			expectAgreement(of: answers, sourceLocation: sourceLocation)
		}
	}

	private func expectAgreement(of answers: SeamHolesPathAgreementChecks.Answers, sourceLocation: SourceLocation) {
		let disagreeing = answers.keysDisagreeingWithFamily.filter { $0.column != "site" }
		for key in disagreeing {
			let answersByText = answers.pathsByAnswerByKey[key, default: [:]]
			Issue.record(Comment(rawValue: "\(key.seamType) | \(key.node) | \(key.edge) | \(key.fill) | \(key.column)\n" + answersByText.sorted { $0.key < $1.key }.map { "  \($0.key)\n    " + $0.value.sorted().joined(separator: "\n    ") }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
