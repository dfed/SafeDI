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

/// Checks, for every production root of a module without seams, that the gate read from the scopes the root reaches
/// lets the capture walk run wherever today's walk finds a capture (`SendableCaptureGateObservation`): a root the gate
/// holds back needs no tree of today's for the walk only if the walk would find nothing.
enum SendableCaptureGateChecks {
	/// Runs `operation` while checking each root observed, handing each to `enclosingObserver` too, and records an issue
	/// for each root today's walk finds a capture in that the gate holds back.
	static func comparing<Result>(
		handingOn enclosingObserver: (@Sendable (_ root: String, _ gateLetsWalkRun: Bool, _ todaysWalkFindsCapture: Bool) -> Void)?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await SendableCaptureGateObservation.$observer.withValue({ root, gateLetsWalkRun, todaysWalkFindsCapture in
			if todaysWalkFindsCapture, !gateLetsWalkRun {
				Issue.record(Comment(rawValue: "\(root)’s tree holds a capture of a non-`Sendable` wrapper, but the scopes it reaches do not name both kinds of wrapper"))
			}
			enclosingObserver?(root, gateLetsWalkRun, todaysWalkFindsCapture)
		}) {
			try await operation()
		}
	}
}
