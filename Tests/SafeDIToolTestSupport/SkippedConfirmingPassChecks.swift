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

/// The oracle of the skipped confirming pass: every seam the tool settles after its first signature pass is computed
/// once more by the pass the tool skips (`SeamSignatureObservation.confirmsSkippedPasses`), and the two signatures must
/// encode to the same bytes, `nil` included.
enum SkippedConfirmingPassChecks {
	/// An observer that records an issue for each skipped pass whose confirming pass threw or found another signature, then
	/// hands the pass to `enclosingObserver`.
	static func recordingDifferences(handingOn enclosingObserver: TaskLocalFunction<@Sendable (SkippedConfirmingPass) -> Void>?) -> TaskLocalFunction<@Sendable (SkippedConfirmingPass) -> Void> {
		TaskLocalFunction { skippedPass in
			if let difference = difference(in: skippedPass) {
				Issue.record(Comment(rawValue: difference))
			}
			enclosingObserver?(skippedPass)
		}
	}

	/// What the confirming pass found that the first did not, or `nil` when it found the same signature.
	static func difference(in skippedPass: SkippedConfirmingPass) -> String? {
		let seam = skippedPass.skipped.seamType.asSource
		guard !skippedPass.confirmingPassThrew else {
			return "The confirming signature pass the tool skipped for \(seam) threw."
		}
		let skipped = encoded(skippedPass.skipped)
		let confirmed = encoded(skippedPass.confirmed)
		guard skipped != confirmed else { return nil }
		return """
		The confirming signature pass the tool skipped for \(seam) found another signature:
		first pass:      \(skipped)
		confirming pass: \(confirmed)
		"""
	}

	private static func encoded(_ signature: StoredSeamSignature) -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		// A signature encodes whatever it holds; an encoding failure is itself a difference worth seeing.
		guard let data = try? encoder.encode(signature) else { return "(unencodable)" }
		return String(decoding: data, as: UTF8.self)
	}
}
