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

/// Work spread over child tasks with at most a fixed number running at once.
enum BoundedConcurrency {
	/// How many of a module's mock roots `generateMockCode` reads at once: one per processor the process may run on, so the
	/// processors stay busy while only that many roots' parameter trees are alive, each of which holds a node per path.
	static var mockRootWidth: Int {
		max(1, ProcessInfo.processInfo.activeProcessorCount)
	}

	/// `transform` applied to each of `elements`, in their order, in child tasks of which at most `width` run at once.
	/// The first error a task throws is thrown, and the tasks still running are cancelled.
	static func map<Element: Sendable, Transformed: Sendable>(
		_ elements: [Element],
		width: Int,
		_ transform: @escaping @Sendable (Element) async throws -> Transformed,
	) async throws -> [Transformed] {
		try await withThrowingTaskGroup(
			of: (index: Int, transformed: Transformed).self,
			returning: [Transformed].self,
		) { taskGroup in
			var results = [Transformed?](repeating: nil, count: elements.count)
			var nextIndex = 0
			for (index, element) in elements.enumerated().prefix(width) {
				taskGroup.addTask { try await (index: index, transformed: transform(element)) }
				nextIndex = index + 1
			}
			while let result = try await taskGroup.next() {
				results[result.index] = result.transformed
				if nextIndex < elements.count {
					let index = nextIndex
					let element = elements[index]
					taskGroup.addTask { try await (index: index, transformed: transform(element)) }
					nextIndex += 1
				}
			}
			return results.compactMap(\.self)
		}
	}
}
