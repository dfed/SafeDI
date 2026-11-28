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

/// The check both test executors run on every validation of every graph they generate: the fold over the facts of each
/// type errs one way only. It may send trees that pass to the walk of every route, and must never find no route that may
/// fail in trees that walk rejects (`ValidationWalkObservation.foldComparison`, which makes the walk run either way).
enum FulfillmentFoldChecks {
	/// Whether the executors compare the fold with the walk, which makes the walk run on every graph. `false` only where
	/// a test counts what the tool does by itself: the walk then runs only where the fold finds a route that may fail.
	@TaskLocal static var comparesFoldWithWalk = true

	/// What the executors set as `ValidationWalkObservation.foldComparison`: the check below, or nothing where a test
	/// turned the comparison off.
	static func comparison(handingOn enclosingObserver: TaskLocalFunction<@Sendable (FulfillmentFoldComparison) -> Void>?) -> TaskLocalFunction<@Sendable (FulfillmentFoldComparison) -> Void>? {
		comparesFoldWithWalk ? recordingClearedRejections(handingOn: enclosingObserver) : nil
	}

	/// An observer that records an issue for each validation whose trees the walk rejected where the fold found no route
	/// that may fail, then hands the comparison to `enclosingObserver`.
	static func recordingClearedRejections(handingOn enclosingObserver: TaskLocalFunction<@Sendable (FulfillmentFoldComparison) -> Void>?) -> TaskLocalFunction<@Sendable (FulfillmentFoldComparison) -> Void> {
		TaskLocalFunction { comparison in
			if comparison.walkRejected, comparison.routeThatMayFail == nil {
				Issue.record("The fold over the facts of each type found no route that may fail in trees the walk of every route rejects.")
			}
			enclosingObserver?(comparison)
		}
	}
}
