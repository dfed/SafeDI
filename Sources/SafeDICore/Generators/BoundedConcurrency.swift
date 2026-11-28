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

/// Jobs run in child tasks with at most a fixed width of them running at once, their outcomes kept by index.
///
/// The contract every caller relies on:
/// - **Admission is in index order.** A job starts only once every job before it has started, and only when its cost
///   fits in what the running jobs leave of the width. So when a job is admitted, every job before it was too.
/// - **Nothing is cancelled.** `stopAdmittingAtFirstFailure` stops admitting jobs once one fails; the jobs already
///   running finish, and the jobs never admitted are `.notAdmitted`.
/// - **The reported failure is chosen by index, never by time.** `map` throws the error of the failed job with the
///   lowest index. Since admission is in index order and nothing is cancelled, every job before that one ran to its end,
///   so which error is thrown depends only on what the jobs do, never on which finished first. That lowest failure is
///   the only outcome under `stopAdmittingAtFirstFailure` that does not depend on timing: which later jobs ran, which
///   of them failed, and which were never admitted depend on when the first failure arrived.
/// - **Cancellation is not checked.** A cancelled caller's jobs see the cancellation as their own, since they run in its
///   child tasks, but the helper keeps admitting and waits for every admitted job; a job that should stop early checks
///   `Task.isCancelled` itself.
/// - **A job's input is released when the job ends.** The elements are held by the jobs not yet admitted and by the
///   running ones, never for the whole call; a caller that wants the memory back passes its only copy of the array.
/// - **A width of 1 runs in the caller's task**, one job after another, with no child task.
/// - **Nesting.** A job is handed the width it was granted, its cost, so a call it makes inside takes that as its width
///   and the nested calls never run more jobs at once than the outer call's width.
enum BoundedConcurrency {
	/// How many of a module's mock roots `generateMockCode` reads at once. Only that many roots' lowered trees are alive
	/// at a time, each of which holds a node per path, so each root more in flight raises peak memory: on issue #646's
	/// 12-screen mock graph, by about 10 MB. A measured constant, not the processor count, which would let a machine with
	/// many cores hold more trees than 2.2.0's peak allows. On 4 processors, reading 1, 2 and 4 roots at once took
	/// 8.4 s, 6.6 s and 5.6 s of wall time, at 275, 304 and 326 MB of peak memory.
	static let mockRootWidth = 4

	/// What became of one job.
	enum Outcome<Transformed: Sendable>: Sendable {
		/// The job returned this value.
		case finished(Transformed)
		/// The job threw this error.
		case failed(any Error)
		/// The job never started, since an earlier job failed under `stopAdmittingAtFirstFailure`.
		case notAdmitted
	}

	/// What a job's task returns: its index, the cost it holds of the width, and its outcome. A struct, never a tuple
	/// (`taskGroupTupleElement` in `.claude/rules/source-rules.md`).
	private struct FinishedJob<Transformed: Sendable>: Sendable {
		let index: Int
		let cost: Int
		let outcome: Outcome<Transformed>
	}

	/// Whether a failure stops the jobs not yet admitted.
	enum FailurePolicy: Sendable {
		/// Every job runs, whatever the others do.
		case runAll
		/// Once a job fails, no job is admitted after it; the running jobs finish.
		case stopAdmittingAtFirstFailure
	}

	/// The outcome of `transform` on each of `elements`, by index, with the jobs running in child tasks whose costs
	/// together never exceed `width`.
	/// - Parameters:
	///   - elements: The jobs' inputs. Each is released when its job ends.
	///   - width: The most cost running at once. Under 1 counts as 1; a width of 1 runs every job in the caller's task.
	///   - cost: A job's share of the width, which `transform` is handed as the width of any call it makes inside. Clamped
	///     to between 1 and `width`.
	///   - failurePolicy: Whether a failure stops admitting jobs.
	///   - transform: The job, handed its input and its granted width.
	static func outcomes<Element: Sendable, Transformed: Sendable>(
		of elements: consuming [Element],
		width: Int,
		cost: (Element) -> Int = { _ in 1 },
		failurePolicy: FailurePolicy,
		_ transform: @escaping @Sendable (Element, _ grantedWidth: Int) async throws -> Transformed,
	) async -> [Outcome<Transformed>] {
		let width = max(1, width)
		let count = elements.count
		// The inputs not yet admitted, last first, so admitting one pops it and the array holds only those left.
		var remaining = consume elements
		remaining.reverse()
		var outcomes = [Outcome<Transformed>](repeating: .notAdmitted, count: count)
		guard width > 1 else {
			var index = 0
			while let element = remaining.popLast() {
				BoundedTaskStart.record(jobsRunning: 1)
				do {
					outcomes[index] = try await .finished(transform(element, 1))
				} catch {
					outcomes[index] = .failed(error)
					guard case .runAll = failurePolicy else {
						return outcomes
					}
				}
				index += 1
			}
			return outcomes
		}
		return await withTaskGroup(
			of: FinishedJob<Transformed>.self,
			returning: [Outcome<Transformed>].self,
		) { taskGroup in
			var nextIndex = 0
			var runningCost = 0
			var jobsRunning = 0
			var admits = true
			// The cost of the next job to admit, once asked, so a job that waits for room is asked its cost only once.
			var nextJobCost: Int?
			func admitWhatFits() {
				while admits, let element = remaining.last {
					let jobCost = nextJobCost ?? min(width, max(1, cost(element)))
					guard runningCost + jobCost <= width else {
						nextJobCost = jobCost
						return
					}
					nextJobCost = nil
					remaining.removeLast()
					let index = nextIndex
					nextIndex += 1
					runningCost += jobCost
					taskGroup.addTask {
						do {
							return try await FinishedJob(index: index, cost: jobCost, outcome: .finished(transform(element, jobCost)))
						} catch {
							return FinishedJob(index: index, cost: jobCost, outcome: .failed(error))
						}
					}
					jobsRunning += 1
					BoundedTaskStart.record(jobsRunning: jobsRunning)
				}
			}
			admitWhatFits()
			while let result = await taskGroup.next() {
				outcomes[result.index] = result.outcome
				runningCost -= result.cost
				jobsRunning -= 1
				if case .failed = result.outcome, case .stopAdmittingAtFirstFailure = failurePolicy {
					admits = false
				}
				admitWhatFits()
			}
			return outcomes
		}
	}

	/// `transform` applied to each of `elements`, in their order, as `outcomes(of:…)` runs it, admitting no job once one
	/// fails. Throws the error of the failed job with the lowest index.
	static func map<Element: Sendable, Transformed: Sendable>(
		_ elements: consuming [Element],
		width: Int,
		cost: (Element) -> Int = { _ in 1 },
		_ transform: @escaping @Sendable (Element, _ grantedWidth: Int) async throws -> Transformed,
	) async throws -> [Transformed] {
		let outcomes = await outcomes(of: elements, width: width, cost: cost, failurePolicy: .stopAdmittingAtFirstFailure, transform)
		var results = [Transformed]()
		results.reserveCapacity(outcomes.count)
		var lowestFailure: (any Error)?
		for outcome in outcomes {
			switch outcome {
			case let .finished(transformed):
				results.append(transformed)
			case let .failed(error):
				lowestFailure = lowestFailure ?? error
			case .notAdmitted:
				// Admission is in index order and stops only after a failure, so a job not admitted follows a failure.
				continue
			}
		}
		if let lowestFailure {
			throw lowestFailure
		} else {
			return results
		}
	}
}

/// A job `BoundedConcurrency` starts, with the jobs of the same call then running. Each of a module's mock roots holds its
/// whole lowered tree while its job runs, so starting every root's job at once held every root's tree together, and peak
/// memory grew with the mock roots. The tests check that the jobs running never exceed the bound. Handed to
/// `observer`, which the tests set, never the tool.
public enum BoundedTaskStart {
	/// Called each time a job starts, with the jobs then running, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (_ jobsRunning: Int) -> Void>?

	/// Tells `observer`, when set, that a job started with `jobsRunning` running.
	static func record(jobsRunning: Int) {
		if let observer {
			observer(jobsRunning)
		}
	}
}
