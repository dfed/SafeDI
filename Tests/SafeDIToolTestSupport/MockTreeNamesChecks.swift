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

import Foundation
import SafeDICore
import Testing

/// A sweep of the tree names a mock root's world answers (`MockTreeNamesObservation`): where `SAFEDI_MOCK_TREE_NAMES_REPORT`
/// names a file, each mock root's comparison is appended to it as a line, the test, the root, `refused <reason>`,
/// `equal`, or `differs` followed by each field that differs with both values, so that a run of a suite counts the roots
/// compared, refused and differing. It records no issue: the world's names are not yet what `mock()` reads, and a
/// difference is a finding to report. A run that names no file compares nothing.
enum MockTreeNamesChecks {
	static func sweeping<Result>(_ body: () async throws -> Result) async rethrows -> Result {
		guard let reportPath = ProcessInfo.processInfo.environment["SAFEDI_MOCK_TREE_NAMES_REPORT"] else {
			return try await body()
		}
		let testName = Test.current?.name ?? "unknown test"
		let enclosingObserver = MockTreeNamesObservation.observer
		return try await MockTreeNamesObservation.$observer.withValue(TaskLocalFunction { report in
			let outcome = if let refusal = report.refusal {
				"refused \(refusal)"
			} else if report.differences.isEmpty {
				"equal"
			} else {
				"differs " + report.differences.map { "\($0.field): tree [\($0.tree)] world [\($0.world)]" }.joined(separator: " | ")
			}
			TreeForcerSweep.append("\(testName)\t\(report.root)\t\(outcome)\n", toFileAt: reportPath)
			enclosingObserver?(report)
		}) {
			try await body()
		}
	}
}
