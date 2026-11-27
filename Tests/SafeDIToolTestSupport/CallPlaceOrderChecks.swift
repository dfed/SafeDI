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

import SafeDICore
import Testing

/// Checks, for every scope of a production root's tree that reaches a cycle, that the scope builds its children in the
/// same order where each child on a cycle is a call place, a leaf that receives what the child's whole tree receives
/// from above, as it does in today's tree (`CallPlaceOrderObservation`).
enum CallPlaceOrderChecks {
	/// Runs `operation` while comparing the two orders of every scope observed, handing each to `enclosingObserver` too,
	/// and records an issue for each scope whose orders differ.
	static func comparing<Result>(
		handingOn enclosingObserver: (@Sendable (_ scope: String, _ todaysOrder: [Int], _ callPlaceOrder: [Int]) -> Void)?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		// A test that observes no comparison of a plan with today's tree compares only the roots whose shape the plan admits.
		let observesNoComparison = enclosingObserver == nil
			&& VariantBodyObservation.observer == nil
			&& PlanBodiesObservation.observer == nil
			&& PlanCallsObservation.observer == nil
			&& TwinIdentityObservation.observer == nil
			&& PlanCodeObservation.observer == nil
			&& PlanSendableObservation.observer == nil
			&& MockVariantBodyObservation.observer == nil
			&& MockVariantBodyObservation.planObserver == nil
		return try await RootTreeChoiceObservation.$comparesOnlyRootsThePlanAdmits.withValue(observesNoComparison || RootTreeChoiceObservation.comparesOnlyRootsThePlanAdmits) {
			try await Self.comparingEveryScope(handingOn: enclosingObserver, operation)
		}
	}

	private static func comparingEveryScope<Result>(
		handingOn enclosingObserver: (@Sendable (_ scope: String, _ todaysOrder: [Int], _ callPlaceOrder: [Int]) -> Void)?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await CallPlaceOrderObservation.$observer.withValue({ scope, todaysOrder, callPlaceOrder in
			if todaysOrder != callPlaceOrder {
				Issue.record(Comment(rawValue: """
				\(scope) builds its children in another order where its children on a cycle are call places:
				today: \(todaysOrder)
				with call places: \(callPlaceOrder)
				"""))
			}
			enclosingObserver?(scope, todaysOrder, callPlaceOrder)
		}) {
			try await operation()
		}
	}
}
