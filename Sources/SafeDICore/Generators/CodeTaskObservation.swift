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

/// A task on which the code of a dependency tree’s scopes starts generating as soon as the tree exists, rather than when
/// the scope above each asks for it. A running task holds its code’s async frames, so starting every scope’s code at
/// once ran the frames of most of a tree together; the tests count the tasks to check that only scopes of large
/// subtrees start early, each on a task of its own, and the small subtrees directly beneath them in groups, one task
/// each. Handed to `observer`, which the tests set, never the tool.
public enum CodeTaskStart {
	/// Called once for each task that starts scopes’ code early, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable () -> Void)?

	/// Tells `observer`, when set, that a task started scopes’ code early.
	static func record() {
		if let observer {
			observer()
		}
	}

	/// Orders the early starts, when set: by the tests, never by the tool, which check that the order in which the
	/// early starts finish never reaches what `generate` reports.
	@TaskLocal public static var ordering: (any CodeTaskStartOrdering)?
}

/// Holds each early start until its turn, and the roots’ code until every early start has finished, so a test can
/// force the order in which the early starts finish. Set as `CodeTaskStart.ordering` by the tests, never by the tool.
public protocol CodeTaskStartOrdering: Sendable {
	/// Called once for each scope whose code starts early, as it starts.
	func registerStart()
	/// Awaited by each early start before it generates its code; `finish` is called once it has.
	func waitForTurn() async -> Int
	/// Called once the early start that `waitForTurn` returned `turn` to has generated its code, or thrown.
	func finish(_ turn: Int) async
	/// Awaited before the roots’ code is asked for: lets each registered start take its turn, in the order the test
	/// chooses, and returns once every one has finished.
	func runEveryStart() async
}

/// The code tasks the generators of a root’s dependency tree still hold once its code is generated. A task keeps the
/// memory its async frames took until it is released, so a generator that kept each finished task held that memory for
/// every scope of the tree until the tree’s code was done. A scope that starts its code early starts it for the context
/// of a root; where the scope above asks for another, the early task finishes on its own and releases itself, and the
/// count includes it while it runs. Handed to `observer`, which the tests set, never the tool.
public enum HeldCodeTasks {
	/// Called with the count for each root’s tree, in the order of the roots, once every root’s code is generated, when
	/// set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (Int) -> Void)?
}

/// Whether a mock root’s body was written by the production emitter, through its override hook, or by the mock’s own
/// walk. The tests read it to show that a body they pin is the production emitter’s. Handed to `observer`, which the
/// tests set, never the tool.
public enum MockBodyRouting {
	/// Called once for each mock root’s body, with `true` where the production emitter wrote it, when set: by the tests,
	/// never by the tool.
	@TaskLocal public static var observer: (@Sendable (Bool) -> Void)?

	/// Tells `observer`, when set, which emitter wrote a mock root’s body.
	static func record(routed: Bool) {
		if let observer {
			observer(routed)
		}
	}
}
