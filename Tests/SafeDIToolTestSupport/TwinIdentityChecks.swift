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

/// Checks, for every production root whose tree holds a value two properties build, that each call today's tree makes of
/// a function a cycle closes on runs the function the plan's call names (`VariantAnswers.functionThePlanCalls`), so that
/// a body maps to one function. The two rules' twin values (`CallPlaceShadow.twinValues`, `PerTypePlan.twins`) are
/// handed on, never compared: they differ where a twin's constant is off the cycle its lazy twin is on, and generation
/// closes on the identity whatever rule names the twins.
enum TwinIdentityChecks {
	/// Runs `operation` while checking each root's calls, handing each root's observation to `enclosingObserver` too, and
	/// records an issue for each root a call of which runs another function than the plan's.
	static func comparing<Result>(
		handingOn enclosingObserver: TaskLocalFunction<@Sendable (_ root: String, _ shadowsTwinValues: [String], _ plansTwinValues: [String], _ callsOfOtherFunction: [String]) -> Void>?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await TwinIdentityObservation.$observer.withValue(TaskLocalFunction { root, shadowsTwinValues, plansTwinValues, callsOfOtherFunction in
			if !callsOfOtherFunction.isEmpty {
				Issue.record(Comment(rawValue: """
				Calls in the tree of \(root) run another function than the plan's call of the twin value names:
				\(callsOfOtherFunction)
				"""))
			}
			enclosingObserver?(root, shadowsTwinValues, plansTwinValues, callsOfOtherFunction)
		}) {
			try await operation()
		}
	}
}
