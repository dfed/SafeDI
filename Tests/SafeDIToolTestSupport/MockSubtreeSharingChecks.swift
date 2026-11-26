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

enum MockSubtreeSharingChecks {
	/// An observer that records an issue for each subject (a mock's lowering and its configurations)
	/// whose result with shared work differs from the same subject computed with no work shared, then hands the comparison
	/// to `enclosingObserver`. The key of a shared subtree must hold every part of the walk state the subtree's records read:
	/// a part it misses gives a later meeting the first meeting's records where the path would have made others.
	static func recordingDifferences(handingOn enclosingObserver: (@Sendable (String, String, String) -> Void)?) -> @Sendable (String, String, String) -> Void {
		{ subject, shared, unshared in
			if shared != unshared {
				let sharedLines = shared.split(separator: "\n", omittingEmptySubsequences: false)
				let unsharedLines = unshared.split(separator: "\n", omittingEmptySubsequences: false)
				let firstDifference = zip(sharedLines, unsharedLines).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(sharedLines.count, unsharedLines.count)
				let sharedLine = firstDifference < sharedLines.count ? String(sharedLines[firstDifference]) : "<end>"
				let unsharedLine = firstDifference < unsharedLines.count ? String(unsharedLines[firstDifference]) : "<end>"
				Issue.record(Comment(rawValue: "\(subject)\(runDescription) computed with shared work differs from the walk of every path at line \(firstDifference + 1):\n  shared:   \(sharedLine)\n  unshared: \(unsharedLine)"))
			}
			enclosingObserver?(subject, shared, unshared)
		}
	}

	/// The graph fuzzer's seed of the graph whose run recorded an issue, or nothing outside the fuzzer, where the test that
	/// records it names the run (`StoredBlockDecodeChecks.runDescription`).
	private static var runDescription: String {
		StoredBlockDecodeChecks.runDescription.map { " (\($0))" } ?? ""
	}
}
