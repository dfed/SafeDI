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

/// The oracle of a seam signature read from the per-type facts: on every signature pass of every seam, the fields the
/// facts of the seam's tree produce must equal what the tree holds (`SeamTreeReadsObservation`), on every test and fuzzer
/// graph. With a field emptied (`SeamTreeReadsObservation.perturbsFactsField`), `SafeDIToolSeamTreeReadsTests`'
/// `generate_reportsDifference_whenFactsFieldIsPerturbed` cells fail here.
enum SeamTreeReadsChecks {
	/// Runs `operation` while comparing the reads of every seam it computes, handing each comparison to
	/// `enclosingObserver` too, and records an issue for each comparison that holds a difference, also where `operation`
	/// throws, as a test of an error makes it: the signature passes before the error compared their seams too.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (SeamTreeReadsComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		let result: Swift.Result<Result, any Error>
		do {
			result = try await .success(SeamTreeReadsObservation.$comparesFacts.withValue({ comparison in
				continuation.yield(comparison)
				enclosingObserver?(comparison)
			}) {
				try await operation()
			})
		} catch {
			result = .failure(error)
		}
		continuation.finish()
		for await comparison in comparisons where !comparison.differences.isEmpty {
			Issue.record(Comment(rawValue: """
			The facts of \(comparison.seam)’s signature tree differ from the tree:
			\(comparison.differences.map { "\($0.field): tree \($0.tree), facts \($0.facts)" }.joined(separator: "\n"))
			"""))
		}
		return try result.get()
	}
}
