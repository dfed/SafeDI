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

/// Checks, for every place of a tree whose reads were logged, that its subtree read of the declarations above it only
/// labels the tree's plan by declaration says its declaration reads from above: a body shared between the places whose
/// paths answer those labels alike would otherwise read something its key does not hold.
enum PlaceReadsChecks {
	/// Runs `operation` while comparing each place's reads with its declaration's planned labels, handing each to
	/// `enclosingObserver` too, and records an issue for each place that read a label the plan does not hold.
	static func comparing<Result>(
		handingOn enclosingObserver: TaskLocalFunction<@Sendable (_ type: String, _ property: String, _ labelsRead: [String], _ labelsPlanned: [String]) -> Void>?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await PlaceReadsObservation.$observer.withValue(TaskLocalFunction { type, property, labelsRead, labelsPlanned in
			let unplannedLabels = labelsRead.filter { !labelsPlanned.contains($0) }
			if !unplannedLabels.isEmpty {
				Issue.record(Comment(rawValue: """
				The place that builds \(type) as \(property) read labels from above that the plan does not key its body by: \(unplannedLabels)
				read: \(labelsRead)
				planned: \(labelsPlanned)
				"""))
			}
			enclosingObserver?(type, property, labelsRead, labelsPlanned)
		}) {
			try await operation()
		}
	}
}
