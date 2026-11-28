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

enum PlanCaptureChecks {
	/// Runs `operation` while recording an issue for each root laid out from its per-type plan whose tree per path holds a
	/// capture of a wrapper that is not `Sendable` in a `@Sendable` function, which no walk then reports, and hands each
	/// root to `enclosingObserver` too.
	static func comparing<Result>(
		handingOn enclosingObserver: (@Sendable (_ root: String, _ todaysWalkFindsCapture: Bool) -> Void)?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await PlanCaptureObservation.$observer.withValue({ root, todaysWalkFindsCapture in
			if todaysWalkFindsCapture {
				Issue.record(Comment(rawValue: """
				Today's tree of \(root) captures a wrapper that is not `Sendable` in a `@Sendable` function, but its code is \
				laid out from its per-type plan, which no walk reads.
				"""))
			}
			enclosingObserver?(root, todaysWalkFindsCapture)
		}) {
			try await operation()
		}
	}
}
