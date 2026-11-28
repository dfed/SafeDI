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

/// The oracle of the `Sendable` configurations fold: the concrete types whose configuration each mock root's tree reads in a
/// `Sendable` scope, which mock generation takes from the fold over the root's world (`TypeFactsSendableConfigurations`), must
/// equal those the walk of the root's generator tree finds (`TypeFactsSendableConfigurationsObservation.comparesWalk`), on
/// every test and fuzzer graph.
enum TypeFactsSendableConfigurationsChecks {
	/// Runs `operation` while comparing the `Sendable` configurations of every mock root it lowers, handing each comparison
	/// to `enclosingObserver` too, and records an issue for each mock root whose two sets differ.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (TypeFactsSendableConfigurationsComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: TypeFactsSendableConfigurationsComparison.self)
		let result = try await TypeFactsSendableConfigurationsObservation.$comparesWalk.withValue(TaskLocalFunction { comparison in
			continuation.yield(comparison)
			enclosingObserver?(comparison)
		}) {
			try await operation()
		}
		continuation.finish()
		for await comparison in comparisons where comparison.foldedTypeNames != comparison.walkedTypeNames {
			Issue.record(Comment(rawValue: """
			The Sendable configurations fold of \(comparison.root) differs from the walk of its generator tree:
			only folded: \(comparison.foldedTypeNames.subtracting(comparison.walkedTypeNames).sorted())
			only walked: \(comparison.walkedTypeNames.subtracting(comparison.foldedTypeNames).sorted())
			"""))
		}
		return result
	}
}
