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

extension Array where Element: Sendable {
	/// These elements, each transformed by `transform`, in their order. The elements are split into
	/// `concurrentRunCount` runs, each transformed on a task of its own, and the runs are put back in order whichever
	/// finishes first, so the result is the same as `map(_:)`'s. For work on each element that depends on nothing else
	/// the caller holds, such as spelling or stamping a module's thousands of paths.
	func concurrentlyMapped<Transformed: Sendable>(_ transform: @escaping @Sendable (Element) -> Transformed) async -> [Transformed] {
		let runLength = Swift.max(1, (count + Self.concurrentRunCount - 1) / Self.concurrentRunCount)
		return await withTaskGroup(of: (start: Int, transformed: [Transformed]).self) { taskGroup in
			for start in stride(from: 0, to: count, by: runLength) {
				let run = self[start..<Swift.min(start + runLength, count)]
				taskGroup.addTask {
					(start, run.map(transform))
				}
			}
			var transformedRuns = [(start: Int, transformed: [Transformed])]()
			for await transformedRun in taskGroup {
				transformedRuns.append(transformedRun)
			}
			return transformedRuns.sorted { $0.start < $1.start }.flatMap(\.transformed)
		}
	}

	/// How many runs `concurrentlyMapped(_:)` splits the elements into. Spelling a path and stamping a file take locks
	/// in the file system: on a ten-core Mac, spelling a module's 3,068 paths took 20 ms, and 20 ms of CPU time, in one
	/// run; 7 ms, and 28 ms of CPU time, in four; and still 7 ms, but 53 ms of CPU time, in ten, where the runs wait on
	/// each other.
	private static var concurrentRunCount: Int {
		4
	}
}
