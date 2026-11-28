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

/// Checks, for every scope the validation walk asks about, that the labels `LabelsReadFromAbove` finds it reads from
/// above, component by component, are the labels an independent computation finds by repeating passes over the same
/// scopes until none changes.
enum LabelsReadFromAboveChecks {
	/// Runs `operation` while comparing the two computations for every scope asked about, handing each answer to
	/// `enclosingObserver` too, and records an issue for each scope whose answers differ.
	static func comparing<Result>(
		handingOn enclosingObserver: (@Sendable (_ type: String, _ remembered: [String], _ byComponent: [String], _ byPasses: [String]) -> Void)?,
		_ operation: () async throws -> Result,
	) async throws -> Result {
		try await LabelsReadFromAboveObservation.$observer.withValue({ type, remembered, byComponent, byPasses in
			if byComponent != byPasses {
				Issue.record(Comment(rawValue: """
				The labels \(type) reads from above differ between the two computations:
				by component: \(byComponent)
				by passes: \(byPasses)
				"""))
			}
			enclosingObserver?(type, remembered, byComponent, byPasses)
		}) {
			try await operation()
		}
	}
}
