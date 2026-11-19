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

/// One job of a `GenerationJobs` call: the value the job is handed, and the slots it holds while it runs.
public struct GenerationJob<Input: Sendable>: Sendable {
	/// The value the job's work is handed, and owns. The helper keeps no reference to it once it admits the job.
	public var input: Input
	/// The slots the job holds while it runs. A nested call the job makes runs at this width.
	public var cost: Int

	public init(_ input: Input, cost: Int = 1) {
		self.input = input
		self.cost = cost
	}
}

/// The bounded, ordered fan-out through which every task group in SafeDICore runs.
///
/// A call admits its jobs in index order, and only while the costs of the jobs in flight plus the next job's cost are
/// at most its width; it never admits a later job past one that waits for slots. Each job runs with `width` set to its
/// own cost, so a call it makes runs on the slots it holds while it waits, and on no others: there is no pool of slots
/// that tasks share, and so nothing two calls could wait on each other for. The outcomes come back by index, never in
/// the order the jobs complete. One job's failure cancels no other job; only the calling task's cancellation cancels the
/// call's jobs, and then the call returns nothing.
public enum GenerationJobs {
	/// The width of a call made in this task: the most cost its jobs may hold in flight at once. The process's width is
	/// the active processor count. Each job runs with its own cost as its width.
	@TaskLocal public static var width: Int = ProcessInfo.processInfo.activeProcessorCount

	/// Called, when set, with a job's path after the job's work returns or throws and before the helper collects its
	/// outcome. A path is the job's index at each nesting level of the helper, outermost first. Set by tests, which
	/// force an order of completion with it; never by the tool.
	@TaskLocal public static var completionObserver: (@Sendable (_ path: [Int]) async -> Void)?

	/// Runs every job of `jobs`, and returns each job's result, in the order of `jobs`.
	/// - Throws: `CancellationError`, and nothing else, when the calling task is cancelled. Then it returns nothing.
	public static func results<Input: Sendable, Success: Sendable, Failure: Error>(
		of jobs: consuming [GenerationJob<Input>],
		_ work: @escaping @Sendable (consuming Input) async throws(Failure) -> Success,
	) async throws -> [Result<Success, Failure>] {
		// A call that never stops admits every job, so every outcome is there.
		try await outcomes(of: jobs, stoppingAtFirstFailure: false, work).compactMap(\.self)
	}

	/// Runs the jobs of `jobs` in order, admitting none after the first failure it collects, and returns each job's
	/// result in the order of `jobs`: `nil` for a job it never admitted.
	/// - Throws: `CancellationError`, and nothing else, when the calling task is cancelled. Then it returns nothing.
	public static func resultsStoppingAtFirstFailure<Input: Sendable, Success: Sendable, Failure: Error>(
		of jobs: consuming [GenerationJob<Input>],
		_ work: @escaping @Sendable (consuming Input) async throws(Failure) -> Success,
	) async throws -> [Result<Success, Failure>?] {
		try await outcomes(of: jobs, stoppingAtFirstFailure: true, work)
	}

	// MARK: Private

	/// The job the calling task runs, as the index of the job at each nesting level of the helper, outermost first.
	/// Empty outside any job.
	@TaskLocal private static var path: [Int] = []

	/// The input of one admitted job, which the job's task takes out before the job's work runs. The helper hands the
	/// box to the job and keeps no reference to the input, so the input's last reference is the work's own, and dies
	/// on the job's task when the work is done with it, whenever the box itself, or the closure that holds it, is freed.
	/// Not `Sendable`: a box is made for one job and handed to it, which is all the job's task needs.
	private final class InputBox<Input: Sendable> {
		init(_ job: consuming GenerationJob<Input>) {
			inputs = [job.input]
		}

		/// The job's input until the job takes it: one element, or none.
		var inputs: [Input]
	}

	/// The outcome of each job of `jobs`, by index: `nil` for a job not admitted, which only a call that stops at its first
	/// failure leaves.
	private static func outcomes<Input: Sendable, Success: Sendable, Failure: Error>(
		of jobs: consuming [GenerationJob<Input>],
		stoppingAtFirstFailure: Bool,
		_ work: @escaping @Sendable (consuming Input) async throws(Failure) -> Success,
	) async throws -> [Result<Success, Failure>?] {
		// A width below 1 counts as 1, so that no call waits forever; a cost is clamped into 1 through the width.
		let width = max(1, width)
		let callerPath = path
		let costs = jobs.map { min(max(1, $0.cost), width) }
		// Reversed, so that admitting a job takes it off the end: the call keeps no reference to an admitted job's input.
		var pendingJobs = consume jobs
		pendingJobs.reverse()
		var outcomes = [Result<Success, Failure>?](repeating: nil, count: costs.count)
		var admitsMoreJobs = true
		if width == 1 {
			// In the caller's own task, one job after another: a nested call made by a job of cost 1 runs here too, so it
			// waits for no slot anyone else holds.
			var index = 0
			while admitsMoreJobs, let job = pendingJobs.popLast() {
				try Task.checkCancellation()
				let outcome = await run(InputBox(consume job), path: callerPath + [index], cost: costs[index], work)
				if stoppingAtFirstFailure, case .failure? = outcome {
					admitsMoreJobs = false
				}
				outcomes[index] = outcome
				index += 1
			}
		} else {
			await withTaskGroup(of: (index: Int, outcome: Result<Success, Failure>?).self) { group in
				var nextIndex = 0
				var costInFlight = 0
				while true {
					while admitsMoreJobs, nextIndex < costs.count, costInFlight + costs[nextIndex] <= width, let job = pendingJobs.popLast() {
						let index = nextIndex
						let cost = costs[index]
						let box = InputBox(consume job)
						let admitted = group.addTaskUnlessCancelled {
							await (index: index, outcome: run(box, path: callerPath + [index], cost: cost, work))
						}
						if admitted {
							costInFlight += cost
							nextIndex += 1
						} else {
							// The calling task is cancelled: admit nothing more, and wait for the jobs in flight.
							admitsMoreJobs = false
							group.cancelAll()
						}
					}
					guard let completion = await group.next() else { break }
					// Only this task writes the outcomes, each at its job's index, so the order the jobs complete in
					// reaches nothing.
					outcomes[completion.index] = completion.outcome
					costInFlight -= costs[completion.index]
					if stoppingAtFirstFailure, case .failure? = completion.outcome {
						admitsMoreJobs = false
					}
				}
			}
		}
		// A cancelled call returns no outcomes, even when every job finished: what a cancelled run would report
		// depends on timing.
		try Task.checkCancellation()
		return outcomes
	}

	/// Runs the work of the job whose input `box` holds, at `path`, with `width` set to `cost`, and tells the completion
	/// observer. The job's input is moved out of the box and into the work, so it dies with the work, on this task.
	private static func run<Input: Sendable, Success: Sendable, Failure: Error>(
		_ box: InputBox<Input>,
		path: [Int],
		cost: Int,
		_ work: @Sendable (consuming Input) async throws(Failure) -> Success,
	) async -> Result<Success, Failure>? {
		let outcomes = await $path.withValue(path) {
			await $width.withValue(cost) {
				var inputs = [Input]()
				swap(&inputs, &box.inputs)
				var outcomes = [Result<Success, Failure>]()
				while let input = inputs.popLast() {
					do throws(Failure) {
						try await outcomes.append(.success(work(consume input)))
					} catch {
						outcomes.append(.failure(error))
					}
				}
				return outcomes
			}
		}
		if let completionObserver {
			await completionObserver(path)
		}
		return outcomes.first
	}
}
