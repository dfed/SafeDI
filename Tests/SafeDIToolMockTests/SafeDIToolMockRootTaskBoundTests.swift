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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// How many of a module's mock roots `generate` reads at once. Each mock root's job holds the root's whole parameter tree,
/// a node per path, until it ends, so a module that started every root's job at once held every root's tree together, and
/// its peak memory grew with its mock roots.
struct SafeDIToolMockRootTaskBoundTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNoMoreMockRootsAtOnceThanItsBound_whenModuleGeneratesManyMocks() async throws {
		let mockRootCount = 4 * BoundedConcurrency.mockRootWidth
		let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
		try await BoundedTaskStart.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: (0..<mockRootCount).map { index in
					"""
					@Instantiable(generateMock: true)
					public struct Screen\(index): Instantiable {
					    public init() {}
					}
					"""
				},
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: ["DEBUG"],
			)
		}
		continuation.finish()
		var startCount = 0
		var mostJobsRunning = 0
		for await jobsRunning in stream {
			startCount += 1
			mostJobsRunning = max(mostJobsRunning, jobsRunning)
		}
		// Every root's job starts through the bound, once in each phase that reads the roots.
		#expect(startCount >= mockRootCount, "\(startCount) bounded starts for \(mockRootCount) mock roots: some roots' jobs start unbounded")
		#expect(mostJobsRunning <= BoundedConcurrency.mockRootWidth, "\(mostJobsRunning) mock roots read at once, over the bound of \(BoundedConcurrency.mockRootWidth)")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
