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

/// The oracle of the receivers column: the receives that leave every seam's root as its world's facts find them
/// (`TypeFactsGraph.receiversLeavingRoot`), with where each is declared, must equal, in order, those the walk of the seam's
/// generator tree finds (`TypeFactsRootReceiversObservation.comparesWalk`), on every signature pass of every test and
/// fuzzer graph.
enum TypeFactsRootReceiversChecks {
	/// Runs `operation` while comparing the receivers of every seam it computes a signature of, handing each comparison to
	/// `enclosingObserver` too, and records an issue for each seam pass whose two lists differ.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (TypeFactsRootReceiversComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: TypeFactsRootReceiversComparison.self)
		let result = try await TypeFactsRootReceiversObservation.$comparesWalk.withValue({ comparison in
			continuation.yield(comparison)
			enclosingObserver?(comparison)
		}) {
			try await operation()
		}
		continuation.finish()
		for await comparison in comparisons where comparison.facts != comparison.walked {
			Issue.record(Comment(rawValue: """
			The receivers the facts find leaving \(comparison.seam) differ from the walk of its generator tree:
			facts: \(comparison.facts)
			walked: \(comparison.walked)
			"""))
		}
		return result
	}
}
