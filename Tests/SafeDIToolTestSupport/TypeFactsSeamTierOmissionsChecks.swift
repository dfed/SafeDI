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

/// The oracle of the tier omissions fold: the values each root's tree holds for parameters the seam tiers it calls
/// omit, which `generate` reads from the root's per-type graph (`TypeFactsSeamTierOmissions`), must equal, as sets,
/// those the walk of the root's generator tree finds (`TypeFactsSeamTierOmissionsObservation.comparesWalk`), on every
/// test graph.
enum TypeFactsSeamTierOmissionsChecks {
	/// Runs `operation` while comparing the omissions of every root it validates, handing each comparison to
	/// `enclosingObserver` too, and records an issue for each root whose fold and walk differ.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (TypeFactsSeamTierOmissionsComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: TypeFactsSeamTierOmissionsComparison.self)
		let result: Result
		do {
			result = try await TypeFactsSeamTierOmissionsObservation.$comparesWalk.withValue({ comparison in
				continuation.yield(comparison)
				enclosingObserver?(comparison)
			}) {
				try await operation()
			}
		} catch {
			continuation.finish()
			await recordDifferences(in: comparisons)
			throw error
		}
		continuation.finish()
		await recordDifferences(in: comparisons)
		return result
	}

	private static func recordDifferences(in comparisons: AsyncStream<TypeFactsSeamTierOmissionsComparison>) async {
		for await comparison in comparisons {
			let folded = Set(comparison.folded)
			let walked = Set(comparison.walked)
			guard folded != walked else { continue }
			Issue.record(Comment(rawValue: """
			The tier omissions fold of \(comparison.root) differs from the walk of its generator tree:
			only folded: \(folded.subtracting(walked).sorted())
			only walked: \(walked.subtracting(folded).sorted())
			"""))
		}
	}
}
