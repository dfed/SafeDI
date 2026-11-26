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

/// The code tasks the generators of a root’s dependency tree still hold once its code is generated. A task keeps the
/// memory its async frames took until it is released, so a generator that kept each finished task held that memory for
/// every scope of the tree until the tree’s code was done. Handed to `observer`, which the tests set, never the tool.
public enum HeldCodeTasks {
	/// Called with the count for each root’s tree, in the order of the roots, once every root’s code is generated, when
	/// set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (Int) -> Void)?
}

/// The children a root's body plans at once, each on a task of its own
/// (`ScopeGenerator.appendConcurrentChildCode(to:codeGeneration:leadingMemberWhitespace:fillPlaceBindings:)`), the one
/// way a tree is planned in parallel. Each body's count is handed to `observer`, which the tests set, never the tool.
public enum ConcurrentChildCode {
	/// Whether the body being planned plans its children at once: set while a root of the dependency tree, or a seam's
	/// root in its own module where `seamRootsPlanChildrenAtOnce` holds, plans its children, and cleared for each of those
	/// children, whose bodies plan one child after another. A mock's tree plans one child after another throughout.
	@TaskLocal static var plansChildrenAtOnce = false

	/// Whether a seam's root, planned in its own module, plans its children at once: set where the module plans no more
	/// trees than `maximumChildrenAtOnce`, since each tree is planned on a task of its own and many trees already keep
	/// every processor busy.
	@TaskLocal static var seamRootsPlanChildrenAtOnce = false

	/// The most children a body plans at once. Every plan in flight holds its own frames, so a bound per processor would
	/// grow memory with the machine. Measured on E6d-600, E6d-600-inline and issue646-16, four in flight hold main's peak
	/// memory and plan as fast as eight or every child at once.
	static let maximumChildrenAtOnce = 4

	/// Called with the number of children of each body that plans more than one at once, when set: by the tests, never by
	/// the tool.
	@TaskLocal public static var observer: (@Sendable (Int) -> Void)?

	/// Tells `observer`, when set, that a body plans `childCount` children at once.
	static func record(childCount: Int) {
		if let observer {
			observer(childCount)
		}
	}

	/// Orders the tasks of a body that plans its children at once, when set: by the tests, never by the tool, which check
	/// that the order in which the tasks finish never reaches the code the body writes.
	@TaskLocal public static var ordering: (any ConcurrentChildCodeOrdering)?
}

/// Holds each task of a body that plans its children at once until its turn to finish, so a test can force the order in
/// which they finish. Set as `ConcurrentChildCode.ordering` by the tests, never by the tool.
public protocol ConcurrentChildCodeOrdering: Sendable {
	/// Awaited by the task of the child at `position` among the `childCount` children the body plans at once, once its code
	/// is planned; the task finishes when this returns.
	func waitForTurn(ofChildAt position: Int, childCount: Int) async
}
