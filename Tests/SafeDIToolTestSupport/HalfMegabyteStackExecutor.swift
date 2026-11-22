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

import Dispatch
import Foundation
import Synchronization

/// A task executor that runs every job on one thread whose stack is half a megabyte, the stack of a secondary thread and
/// a concurrency thread on Apple platforms. Linux gives its threads eight, so a walk that recurses per level of a tree
/// passes there at a depth that overflows on a Mac; run under `withHalfMegabyteStack(_:)`, it overflows on both.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class HalfMegabyteStackExecutor: TaskExecutor {
	init() {
		let thread = Thread { [self] in
			while let job = nextJob() {
				job.runSynchronously(on: asUnownedTaskExecutor())
			}
		}
		thread.stackSize = 512 * 1_024
		thread.start()
	}

	func enqueue(_ job: consuming ExecutorJob) {
		let job = UnownedJob(job)
		state.withLock { $0.jobs.append(job) }
		jobAvailable.signal()
	}

	/// Lets the thread end once it has run every job enqueued.
	func finish() {
		state.withLock { $0.isFinished = true }
		jobAvailable.signal()
	}

	private struct State {
		var jobs = [UnownedJob]()
		var isFinished = false
	}

	private let state = Mutex(State())
	private let jobAvailable = DispatchSemaphore(value: 0)

	/// The next job to run, waiting for one, or `nil` once the executor is finished and every job has run.
	private func nextJob() -> UnownedJob? {
		while true {
			let next: UnownedJob?? = state.withLock { state in
				if !state.jobs.isEmpty {
					state.jobs.removeFirst()
				} else if state.isFinished {
					.some(nil)
				} else {
					nil
				}
			}
			if let next {
				return next
			} else {
				jobAvailable.wait()
			}
		}
	}
}

/// Runs `operation`, and every task it starts that is not detached, on a thread whose stack is half a megabyte
/// (`HalfMegabyteStackExecutor`).
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
func withHalfMegabyteStack<T>(_ operation: () async throws -> T) async rethrows -> T {
	let executor = HalfMegabyteStackExecutor()
	defer { executor.finish() }
	return try await withTaskExecutorPreference(executor, operation: operation)
}
