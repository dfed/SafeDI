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

/// Checks, for every production root that reaches a cycle, that the bodies its plan marks `@Sendable` are the bodies
/// the type key lays out as `@Sendable`: the two are computed apart until one of them is removed.
enum PlanSendableChecks {
	/// Runs `operation` while comparing the two, handing each comparison to `enclosingObserver` too, and records an issue
	/// for each root whose plan and layout mark other bodies.
	static func comparing<Result>(
		handingOn enclosingObserver: TaskLocalFunction<@Sendable (_ root: String, _ marksOfPlan: [Bool], _ familyOfLayout: [Bool]) -> Void>?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await PlanSendableObservation.$observer.withValue(TaskLocalFunction { root, marksOfPlan, familyOfLayout in
			if marksOfPlan != familyOfLayout {
				Issue.record(Comment(rawValue: """
				The plan of \(root) marks other bodies `@Sendable` than the type key lays out so:
				plan: \(marksOfPlan)
				layout: \(familyOfLayout)
				"""))
			}
			enclosingObserver?(root, marksOfPlan, familyOfLayout)
		}) {
			try await operation()
		}
	}
}
