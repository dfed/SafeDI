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

/// Checks, for every production root that reaches a cycle, that the bodies its plan builds with no tree of today's (the
/// root's, then the body of each call place a body holds) include the body each place of today's tree takes.
enum PlanBodiesChecks {
	/// Runs `operation` while comparing the two, handing each comparison to `enclosingObserver` too, and records an issue
	/// for each root one of whose places today takes a body the plan does not build.
	static func comparing<Result>(
		handingOn enclosingObserver: TaskLocalFunction<@Sendable (_ root: String, _ bodiesOfPlan: [String], _ todaysBodiesPlanLacks: [String], _ twinValues: [String]) -> Void>?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
			if !todaysBodiesPlanLacks.isEmpty {
				Issue.record(Comment(rawValue: """
				The plan of \(root) builds no body that places of today's tree take:
				lacking: \(todaysBodiesPlanLacks)
				built: \(bodiesOfPlan)
				"""))
			}
			enclosingObserver?(root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues)
		}) {
			try await operation()
		}
	}
}
