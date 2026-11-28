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
/// tree must find nothing in the tree (`MockRootTreeChecksObservation.comparesTree`), and the root's world must find a
/// `Sendable` capture wherever the tree does, on every test graph.
///
/// The world's capture check refuses the world, which then keeps its tree, so it need only be safe: a capture only the
/// world finds costs the tree and is no issue. A run that sets `SAFEDI_SENDABLE_CAPTURE_LOG` to a file appends a line to
/// it for each root, with what its world and its tree find, from which a sweep counts the roots only the world finds a
/// capture in down.
enum MockRootTreeChecksOracle {
	/// Runs `operation` while comparing the tree checks of every mock root it makes, handing each comparison to
	/// `enclosingObserver` too, and records an issue for each check the scopes left out that finds something in the tree,
	/// for each root whose tree finds a `Sendable` capture its world misses, and for each root whose world's check did
	/// not run.
	static func comparing<Result>(handingOn enclosingObserver: TaskLocalFunction<@Sendable (MockRootTreeChecksComparison) -> Void>?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: MockRootTreeChecksComparison.self)
		// A run that throws is compared too: the comparisons are made before any mock root's tree is validated.
		let result: Swift.Result<Result, any Error>
		do {
			result = try await .success(MockRootTreeChecksObservation.$comparesTree.withValue(TaskLocalFunction { comparison in
				continuation.yield(comparison)
				enclosingObserver?(comparison)
			}) {
				try await operation()
			})
		} catch {
			result = .failure(error)
		}
		continuation.finish()
		for await comparison in comparisons {
			if let path = ProcessInfo.processInfo.environment["SAFEDI_SENDABLE_CAPTURE_LOG"], !path.isEmpty {
				TypeFactsChecks.append("sendable capture world: \(comparison.sendableCaptureFinding.world.map(String.init) ?? "unchecked") tree: \(comparison.sendableCaptureFinding.tree) \(comparison.root)\n", toFileAt: path)
			}
			switch (world: comparison.sendableCaptureFinding.world, tree: comparison.sendableCaptureFinding.tree) {
			case (world: nil, tree: _):
				Issue.record(Comment(rawValue: "The world of the mock of \(comparison.root) was not checked for a Sendable capture"))
			case (world: false, tree: true):
				Issue.record(Comment(rawValue: "The tree of the mock of \(comparison.root) finds a Sendable capture its world misses"))
			case (world: true, tree: false), (world: true, tree: true), (world: false, tree: false):
				break
			}
			guard !comparison.findingInTreeWithoutNeed.isEmpty else { continue }
			Issue.record(Comment(rawValue: """
			The scopes of the mock of \(comparison.root) said these checks need no tree, but each finds something in it: \
			\(comparison.findingInTreeWithoutNeed.map(\.rawValue).sorted())
			"""))
		}
		return try result.get()
	}
}
