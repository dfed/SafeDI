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

enum PerTypePlanDetectorChecks {
	/// An observer that records an issue for each production tree whose plan's detectors answer `false` where today's tree
	/// finds what they stand for, then hands the answers to `enclosingObserver`: such a plan would build the root once per
	/// type and lose the diagnostic.
	static func recordingMisses(
		handingOn enclosingObserver: (@Sendable (PerTypePlanDetectorObservation.Answers) -> Void)?,
	) -> @Sendable (PerTypePlanDetectorObservation.Answers) -> Void {
		{ answers in
			if !answers.mayHoldUnpassableCycleLabel, !answers.unpassableCycleLabelsInTree.isEmpty {
				Issue.record(Comment(rawValue: "The plan of `\(answers.rootType)`’s tree does not detect the unpassable cycle labels \(answers.unpassableCycleLabelsInTree) its tree holds."))
			}
			enclosingObserver?(answers)
		}
	}
}
