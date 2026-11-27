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

/// The oracle of the received-values fold: the value each receive of every root's tree is handed, and the types the
/// tree constructs, which `query graph` reads from the root's per-type graph (`TypeFactsReceivedValueSupplies`), must
/// equal, as sets, those the walk of the root's generator tree finds
/// (`TypeFactsReceivedValueSuppliesObservation.comparesWalk`), on every test graph.
enum TypeFactsReceivedValueSuppliesChecks {
	/// Runs `operation` while comparing the supplies of every root it plans, handing each comparison to
	/// `enclosingObserver` too, and records an issue for each root whose fold and walk differ.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (TypeFactsReceivedValueSuppliesComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: TypeFactsReceivedValueSuppliesComparison.self)
		let result = try await TypeFactsReceivedValueSuppliesObservation.$comparesWalk.withValue({ comparison in
			continuation.yield(comparison)
			enclosingObserver?(comparison)
		}) {
			try await operation()
		}
		continuation.finish()
		for await comparison in comparisons {
			guard let walked = comparison.walked else {
				Issue.record(Comment(rawValue: "The walk of \(comparison.root)’s generator tree judged none of it, although `generate` planned it."))
				continue
			}
			let foldedSupplies = Set(comparison.folded.supplies)
			let walkedSupplies = Set(walked.supplies)
			let foldedTypes = Set(comparison.folded.constructedTypes)
			let walkedTypes = Set(walked.constructedTypes)
			guard foldedSupplies != walkedSupplies || foldedTypes != walkedTypes else { continue }
			Issue.record(Comment(rawValue: """
			The received-values fold of \(comparison.root) differs from the walk of its generator tree:
			only folded: \(foldedSupplies.subtracting(walkedSupplies).map { String(describing: $0) }.sorted())
			only walked: \(walkedSupplies.subtracting(foldedSupplies).map { String(describing: $0) }.sorted())
			types only folded: \(foldedTypes.subtracting(walkedTypes).map(\.asSource).sorted())
			types only walked: \(walkedTypes.subtracting(foldedTypes).map(\.asSource).sorted())
			"""))
		}
		return result
	}
}
