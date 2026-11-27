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

/// The oracle of a mock root's tree checks read from its scopes (`MockRootTreeChecks`): a check the scopes say needs no
/// tree must find nothing in the tree (`MockRootTreeChecksObservation.comparesTree`), on every test graph.
enum MockRootTreeChecksOracle {
	/// Runs `operation` while comparing the tree checks of every mock root it makes, handing each comparison to
	/// `enclosingObserver` too, and records an issue for each check the scopes left out that finds something in the tree.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (MockRootTreeChecksComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: MockRootTreeChecksComparison.self)
		// A run that throws is compared too: the comparisons are made before any mock root's tree is validated.
		let result: Swift.Result<Result, any Error>
		do {
			result = try await .success(MockRootTreeChecksObservation.$comparesTree.withValue({ comparison in
				continuation.yield(comparison)
				enclosingObserver?(comparison)
			}) {
				try await operation()
			})
		} catch {
			result = .failure(error)
		}
		continuation.finish()
		for await comparison in comparisons where !comparison.findingInTreeWithoutNeed.isEmpty {
			Issue.record(Comment(rawValue: """
			The scopes of the mock of \(comparison.root) said these checks need no tree, but each finds something in it: \
			\(comparison.findingInTreeWithoutNeed.map(\.rawValue).sorted())
			"""))
		}
		return try result.get()
	}
}
