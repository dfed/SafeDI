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

/// A child task of the task group in which a scope of a large subtree generates its children’s code concurrently
/// (`ScopeGenerator.concurrentlyGeneratedCode(of:)`). A running task holds its code’s async frames, so generating every
/// scope’s children at once ran the frames of most of a tree together; the tests count the child tasks to check that only
/// scopes of large subtrees generate their children concurrently. Handed to `observer`, which the tests set, never the
/// tool.
public enum CodeTaskStart {
	/// Called once for each child task of a scope that generates its children concurrently, when set: by the tests, never
	/// by the tool.
	@TaskLocal public static var observer: (@Sendable () -> Void)?

	/// Tells `observer`, when set, that a child task started.
	static func record() {
		if let observer {
			observer()
		}
	}
}

/// The code tasks the generators of a root’s dependency tree still hold once its code is generated. A task keeps the
/// memory its async frames took until it is released, so a generator that kept each finished task held that memory for
/// every scope of the tree until the tree’s code was done. Handed to `observer`, which the tests set, never the tool.
public enum HeldCodeTasks {
	/// Called with the count for each root’s tree, in the order of the roots, once every root’s code is generated, when
	/// set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (Int) -> Void)?
}
