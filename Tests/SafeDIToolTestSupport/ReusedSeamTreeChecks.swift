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

/// The oracle of seam tree reuse: the tree of every seam that emission makes again from its first signature pass's tree
/// (`SeamTreeReuseObservation.comparesBuiltTrees`) must generate the same code as the tree emission builds anew for
/// every other seam, built beside it from the same final signature.
enum ReusedSeamTreeChecks {
	/// Runs `operation` while observing every reused seam tree, handing each to `enclosingObserver` too, then records an
	/// issue for each whose code differs from the tree built anew.
	static func comparing<Result>(handingOn enclosingObserver: TaskLocalFunction<@Sendable (ReusedSeamTree) -> Void>?, _ operation: () async throws -> Result) async throws -> Result {
		let (reusedTrees, continuation) = AsyncStream.makeStream(of: ReusedSeamTree.self)
		let result = try await SeamTreeReuseObservation.$comparesBuiltTrees.withValue(TaskLocalFunction { reusedTree in
			continuation.yield(reusedTree)
			enclosingObserver?(reusedTree)
		}) {
			try await operation()
		}
		continuation.finish()
		for await reusedTree in reusedTrees {
			let reusedTreeCode = try await reusedTree.reusedTreeCode()
			let builtTreeCode = try await reusedTree.builtTreeCode()
			if reusedTreeCode != builtTreeCode {
				Issue.record(Comment(rawValue: """
				The tree of \(reusedTree.signature.seamType.asSource) made again from its first signature pass generated other code than the tree built anew:
				made again:
				\(reusedTreeCode)
				built anew:
				\(builtTreeCode)
				"""))
			}
		}
		return result
	}
}
