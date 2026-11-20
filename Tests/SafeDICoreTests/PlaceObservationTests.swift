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

import Testing
@testable import SafeDICore

/// The place oracle reads a body's plan and fails each place that does not hold what its kind holds. The emitter never
/// writes such a plan, so each test writes the plan a mutation of the emitter would write.
struct PlaceObservationTests {
	@Test
	func places_numbersEachReachOfSharedCode_whenTwoPlacesHoldOneScopesCode() {
		let shared = GeneratedCode.place(PlacePlan(kind: .builtByFunction, functionNames: ["__safeDI_t"], closedOnFunctionName: nil, code: .text("t")))
		let code = GeneratedCode.lines([
			.place(PlacePlan(kind: .builtByFunction, functionNames: ["__safeDI_a"], closedOnFunctionName: nil, code: .indented(shared, by: "\t"))),
			.place(PlacePlan(kind: .builtByFunction, functionNames: ["__safeDI_b"], closedOnFunctionName: nil, code: .indented(shared, by: "\t"))),
		])
		let places = code.places()
		#expect(places.map(\.identity.firstReachIndex) == [0, 1, 2, 3])
		#expect(places.map(\.functionNames) == [["__safeDI_a"], ["__safeDI_t"], ["__safeDI_b"], ["__safeDI_t"]])
		#expect(places.map(\.enclosingFunctionNames) == [[], ["__safeDI_a"], [], ["__safeDI_b"]])
		#expect(places.map(\.placeCountBeneath) == [1, 0, 1, 0])
	}

	@Test
	func init_reportsNoViolation_whenEveryPlaceHoldsWhatItsKindHolds() {
		let code = GeneratedCode.place(PlacePlan(kind: .loopMemberWithCycleParameters, functionNames: ["__safeDI_a", "__safeDI_a_received"], closedOnFunctionName: nil, code: .sequence([
			.place(PlacePlan(kind: .closesCycle, functionNames: [], closedOnFunctionName: "__safeDI_a", code: .text("a"))),
			.place(PlacePlan(kind: .loopMemberClosingCycle, functionNames: ["__safeDI_e_received"], closedOnFunctionName: "__safeDI_a", code: .text("e"))),
			.place(PlacePlan(kind: .constantBuiltInPlace, functionNames: [], closedOnFunctionName: nil, code: .text("b"))),
			.place(PlacePlan(kind: .alias, functionNames: [], closedOnFunctionName: nil, code: .text("c"))),
			.place(PlacePlan(kind: .hostedSeamCode, functionNames: [], closedOnFunctionName: nil, code: .text("d"))),
		])))
		let observation = PlaceObservation(of: code.places())
		#expect(observation.violations == [])
		#expect(observation.placeCountByKind == [.loopMemberWithCycleParameters: 1, .closesCycle: 1, .loopMemberClosingCycle: 1, .constantBuiltInPlace: 1, .alias: 1, .hostedSeamCode: 1])
	}

	@Test
	func init_reportsViolation_whenCycleCloserDeclaresFunction() {
		// M2: a cycle closer treated as a node declares a function of its own.
		let code = GeneratedCode.place(PlacePlan(kind: .builtByFunction, functionNames: ["__safeDI_a"], closedOnFunctionName: nil, code:
			.place(PlacePlan(kind: .closesCycle, functionNames: ["__safeDI_a"], closedOnFunctionName: "__safeDI_a", code: .text("a")))))
		#expect(PlaceObservation(of: code.places()).violations == ["Place 1 (closesCycle) declares 1 builder functions [\"__safeDI_a\"], not 0"])
	}

	@Test
	func init_reportsViolation_whenLoopMemberDropsItsReceivedFunction() {
		// M3: a loop member with cycle parameters writes its function and not its `_received` function.
		let code = GeneratedCode.place(PlacePlan(kind: .loopMemberWithCycleParameters, functionNames: ["__safeDI_a"], closedOnFunctionName: nil, code: .text("a")))
		#expect(PlaceObservation(of: code.places()).violations == ["Place 0 (loopMemberWithCycleParameters) declares 1 builder functions [\"__safeDI_a\"], not 2"])
	}

	@Test
	func init_reportsViolation_whenCycleCloserClosesOnFunctionNoEnclosingPlaceDeclares() {
		let code = GeneratedCode.lines([
			.place(PlacePlan(kind: .builtByFunction, functionNames: ["__safeDI_a"], closedOnFunctionName: nil, code: .text("a"))),
			.place(PlacePlan(kind: .closesCycle, functionNames: [], closedOnFunctionName: "__safeDI_a", code: .text("b"))),
		])
		#expect(PlaceObservation(of: code.places()).violations == ["Place 1 (closesCycle) closes on __safeDI_a, which no enclosing place declares"])
	}

	@Test
	func init_reportsViolation_whenCycleCloserClosesOnNoFunction() {
		let code = GeneratedCode.place(PlacePlan(kind: .closesCycle, functionNames: [], closedOnFunctionName: nil, code: .text("a")))
		#expect(PlaceObservation(of: code.places()).violations == ["Place 0 (closesCycle) closes on no function"])
	}

	@Test
	func init_reportsViolation_whenPlaceThatClosesNoCycleNamesClosedOnFunction() {
		let code = GeneratedCode.place(PlacePlan(kind: .alias, functionNames: [], closedOnFunctionName: "__safeDI_a", code: .text("a")))
		#expect(PlaceObservation(of: code.places()).violations == ["Place 0 (alias) closes on __safeDI_a, but only a cycle-closing place does"])
	}

	@Test
	func init_reportsViolation_whenHostedSeamCodeHoldsPlace() {
		let code = GeneratedCode.place(PlacePlan(kind: .hostedSeamCode, functionNames: [], closedOnFunctionName: nil, code:
			.place(PlacePlan(kind: .alias, functionNames: [], closedOnFunctionName: nil, code: .text("a")))))
		#expect(PlaceObservation(of: code.places()).violations == ["Place 0 (hostedSeamCode) holds 1 places beneath it"])
	}
}
