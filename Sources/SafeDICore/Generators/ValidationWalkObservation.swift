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

/// What the walk that validates a module's trees did (`DependencyTreeGenerator.validatePropertiesAreFulfillable(onRootScopes:…)`),
/// handed to `observer`, which the tests set, never the tool.
public enum ValidationWalkObservation: Sendable {
	/// The walk validated a scope of a tree, along one path.
	case validatedScope
	/// The walk skipped a scope's subtree, since a walk of it along a path that gives it an equal context completed and found
	/// nothing (see `cycle-validation.md`, "Clean subtrees").
	case skippedCleanSubtree
	/// A scope's received properties were collected from those of the scopes it creates, along one path or in one pass
	/// over a cycle (`DependencyTreeGenerator.collectReceivedProperties`).
	case collectedReceivedPropertiesOfScope
	/// The walk built the key of a scope's subtree, to skip it or to remember its walk. A scope that reaches a cycle of
	/// instantiators stops being keyed after a run of keys no remembered walk equals.
	case keyedSubtree
	/// A walk is about to validate its roots, whose world of per-type facts, built before any of them is validated
	/// (`TypeFactsGraph.init(roots:intern:)`), this is; `nil` where the walk has no root. Built only while an observer
	/// is set, so only on a test's path: the tool builds no such world yet.
	case unvalidatedWorld(TypeFactsRootsReport?)

	/// Called with what the walk did, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (ValidationWalkObservation) -> Void)?

	/// Whether the walk skips a subtree whose walk along an equal context completed and found nothing. `false` only where a
	/// test, or the graph fuzzer's oracle, compares what the walk reports with and without the skip.
	@TaskLocal public static var skipsCleanSubtrees = true

	/// Whether the received properties of the scopes of a cycle are completed in passes over the cycle, before any walk
	/// along its paths (see `cycle-generation.md`, "Walks"). `false` only where a test compares the two.
	@TaskLocal public static var completesReceivedPropertiesByComponent = true
}
