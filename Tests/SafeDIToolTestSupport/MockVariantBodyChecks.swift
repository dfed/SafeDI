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

/// Checks, for every mock root that reaches a cycle, that each place of its tree passes `nil` to the receives its body
/// passes `nil` to, and that the bodies its plan builds include the body each place of today's tree takes, as
/// `VariantBodyChecks` and `PlanBodiesChecks` check a production root's.
enum MockVariantBodyChecks {
	/// Runs `operation` while comparing, handing each comparison to the enclosing observers too, and records an issue for
	/// each place whose body passes `nil` otherwise and each mock root one of whose places takes a body the plan lacks.
	static func comparing<Result>(_ operation: () async throws -> Result) async throws -> Result {
		let enclosingObserver = MockVariantBodyObservation.observer
		let enclosingPlanObserver = MockVariantBodyObservation.planObserver
		return try await MockVariantBodyObservation.$observer.withValue({ mockRoot, place, todaysUnavailableProperties, bodysUnavailableProperties in
			if todaysUnavailableProperties != bodysUnavailableProperties {
				Issue.record(Comment(rawValue: """
				The body of \(place) in the mock of \(mockRoot) passes nil to other receives than today's build of the place:
				today: \(todaysUnavailableProperties)
				body: \(bodysUnavailableProperties)
				"""))
			}
			enclosingObserver?(mockRoot, place, todaysUnavailableProperties, bodysUnavailableProperties)
		}) {
			try await MockVariantBodyObservation.$planObserver.withValue({ mockRoot, bodiesOfPlan, todaysBodiesPlanLacks in
				if !todaysBodiesPlanLacks.isEmpty {
					Issue.record(Comment(rawValue: """
					The plan of the mock of \(mockRoot) builds no body that places of today's tree take:
					lacking: \(todaysBodiesPlanLacks)
					built: \(bodiesOfPlan)
					"""))
				}
				enclosingPlanObserver?(mockRoot, bodiesOfPlan, todaysBodiesPlanLacks)
			}) {
				try await operation()
			}
		}
	}
}
