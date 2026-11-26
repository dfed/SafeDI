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

/// The differential of shared hole subtrees, kept until review: every signature pass of every seam is computed once more
/// over a tree built with no construction memo (`SeamSignatureObservation.comparesUnsharedTrees`), which shares no
/// generator between the paths of the seam's tree, and the two must encode to the same bytes, or throw the same error.
enum UnsharedTreeChecks {
	/// An observer that records an issue for each pass whose unshared computation found another signature or another
	/// error, then hands the comparison to `enclosingObserver`.
	static func recordingDifferences(handingOn enclosingObserver: (@Sendable (UnsharedTreeComparison) -> Void)?) -> @Sendable (UnsharedTreeComparison) -> Void {
		{ comparison in
			let shared = spelled(comparison.shared)
			let unshared = spelled(comparison.unshared)
			if shared != unshared {
				Issue.record(Comment(rawValue: """
				A signature pass of \(comparison.seamType.asSource) found otherwise over a tree that shares no hole subtree:
				shared:   \(shared)
				unshared: \(unshared)
				"""))
			}
			enclosingObserver?(comparison)
		}
	}

	private static func spelled(_ outcome: UnsharedTreeComparison.Outcome) -> String {
		switch outcome {
		case let .found(signature):
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			// A signature encodes whatever it holds; an encoding failure is itself a difference worth seeing.
			guard let data = try? encoder.encode(signature) else { return "(unencodable)" }
			return String(decoding: data, as: UTF8.self)
		case let .threw(description):
			return "threw \(description)"
		}
	}
}
