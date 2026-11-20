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

struct BoundedConcurrencyTests {
	@Test(arguments: [1, 4])
	func outcomes_keepsEachOutcomeAtItsJobsIndex_whenJobsFinishInAnyOrder(width: Int) async {
		let outcomes = await BoundedConcurrency.outcomes(of: Array(0..<30), width: width, failurePolicy: .runAll) { element, _ in
			// Later jobs yield less, so they tend to finish before earlier ones.
			for _ in 0..<(30 - element) {
				await Task.yield()
			}
			return element * 2
		}

		#expect(outcomes.map { Self.description(of: $0) } == (0..<30).map { "finished \($0 * 2)" })
	}

	@Test(arguments: [1, 3])
	func outcomes_runsEveryJob_whenPolicyRunsAll(width: Int) async {
		let outcomes = await BoundedConcurrency.outcomes(of: Array(0..<20), width: width, failurePolicy: .runAll) { element, _ in
			guard element % 5 != 0 else { throw JobError(index: element) }
			return element
		}

		#expect(outcomes.map { Self.description(of: $0) } == (0..<20).map { $0 % 5 == 0 ? "failed \($0)" : "finished \($0)" })
	}

	@Test
	func outcomes_admitsNoJobAfterAFailure_whenWidthIsOneAndPolicyStopsAtFirstFailure() async {
		let outcomes = await BoundedConcurrency.outcomes(of: Array(0..<6), width: 1, failurePolicy: .stopAdmittingAtFirstFailure) { element, _ in
			guard element != 2 else { throw JobError(index: element) }
			return element
		}

		#expect(outcomes.map { Self.description(of: $0) } == ["finished 0", "finished 1", "failed 2", "not admitted", "not admitted", "not admitted"])
	}

	@Test
	func outcomes_admitsNoJobAfterAFailure_whenTheNextJobWaitsForTheFailedJobsShareOfTheWidth() async {
		// The second job takes the whole width, so it is admitted only once the first has ended, by which time the
		// first has failed.
		let outcomes = await BoundedConcurrency.outcomes(
			of: Array(0..<4),
			width: 2,
			cost: { $0 == 1 ? 2 : 1 },
			failurePolicy: .stopAdmittingAtFirstFailure,
		) { element, _ in
			guard element != 0 else { throw JobError(index: element) }
			return element
		}

		#expect(outcomes.map { Self.description(of: $0) } == ["failed 0", "not admitted", "not admitted", "not admitted"])
	}

	@Test
	func outcomes_grantsEachJobItsCostClampedToTheWidth_whenCostsFallOutsideTheWidth() async {
		let outcomes = await BoundedConcurrency.outcomes(of: [0, 2, 9], width: 4, cost: { $0 }, failurePolicy: .runAll) { _, grantedWidth in
			grantedWidth
		}

		#expect(outcomes.map { Self.description(of: $0) } == ["finished 1", "finished 2", "finished 4"])
	}

	@Test
	func outcomes_neverRunsMoreCostThanTheWidth_whenJobsCostDifferentShares() async {
		let gauge = RunningCostGauge()
		let costs = (0..<40).map { $0 % 3 + 1 }
		_ = await BoundedConcurrency.outcomes(of: costs, width: 4, cost: { $0 }, failurePolicy: .runAll) { cost, grantedWidth in
			await gauge.start(cost: grantedWidth)
			for _ in 0..<5 {
				await Task.yield()
			}
			await gauge.end(cost: grantedWidth)
			return cost
		}

		#expect((2...4).contains(await gauge.largestRunningCost))
	}

	@Test
	func outcomes_runsEveryJobInTheCallersTask_whenWidthIsOne() async {
		let callersTask = withUnsafeCurrentTask { $0?.hashValue }
		let outcomes = await BoundedConcurrency.outcomes(of: Array(0..<3), width: 1, failurePolicy: .runAll) { _, _ in
			withUnsafeCurrentTask { $0?.hashValue } == callersTask
		}

		#expect(outcomes.map { Self.description(of: $0) } == ["finished true", "finished true", "finished true"])
	}

	@Test(arguments: [1, 2])
	func outcomes_releasesEachJobsInput_whenTheJobEnds(width: Int) async {
		let registry = ReleaseRegistry()
		var inputs = [Input]()
		for index in 0..<5 {
			let input = Input(index: index)
			await registry.watch(input)
			inputs.append(input)
		}
		// Each job but the first takes the whole width, so it starts only once the one before it has ended. The call is
		// handed the only copy of the inputs.
		let outcomes = await BoundedConcurrency.outcomes(of: consume inputs, width: width, cost: { $0.index == 0 ? 1 : width }, failurePolicy: .runAll) { input, _ in
			await registry.releasedIndices(before: input.index)
		}

		#expect(outcomes.map { Self.description(of: $0) } == (0..<5).map { "finished \(Array(0..<$0))" })
	}

	@Test
	func map_throwsTheErrorOfTheFailedJobWithTheLowestIndex_whenALaterJobFailsFirst() async {
		let gate = Gate()
		await #expect(throws: JobError(index: 0)) {
			try await BoundedConcurrency.map(Array(0..<4), width: 4) { element, _ in
				if element == 0 {
					await gate.waitUntilOpen()
					for _ in 0..<20 {
						await Task.yield()
					}
					throw JobError(index: element)
				} else if element == 3 {
					await gate.open()
					throw JobError(index: element)
				} else {
					return element
				}
			}
		}
	}

	@Test
	func map_throwsTheSameError_whenTwentyFourJobsFailInRandomOrderOfCompletion() async {
		// Jobs 5 and later fail, each after a random number of yields, so the order failures arrive in changes from one
		// round to the next; the error thrown never does.
		for _ in 0..<20 {
			let yieldCounts = (0..<24).map { _ in Int.random(in: 0..<40) }
			await #expect(throws: JobError(index: 5)) {
				try await BoundedConcurrency.map(Array(0..<24), width: 4) { element, _ in
					for _ in 0..<yieldCounts[element] {
						await Task.yield()
					}
					guard element < 5 else { throw JobError(index: element) }
					return element
				}
			}
		}
	}

	@Test
	func map_returnsEachJobsValueInOrder_whenNoJobFails() async throws {
		let values = try await BoundedConcurrency.map(Array(0..<12), width: 3) { element, _ in
			element + 100
		}

		#expect(values == Array(100..<112))
	}

	// MARK: Private

	private struct JobError: Error, Equatable {
		let index: Int
	}

	private final class Input: Sendable {
		init(index: Int) {
			self.index = index
		}

		let index: Int
	}

	private actor ReleaseRegistry {
		func watch(_ input: Input) {
			references.append(WeakInput(input: input))
		}

		func releasedIndices(before index: Int) -> [Int] {
			references.prefix(index).enumerated().compactMap { $0.element.input == nil ? $0.offset : nil }
		}

		private struct WeakInput {
			weak var input: Input?
		}

		private var references = [WeakInput]()
	}

	private actor RunningCostGauge {
		func start(cost: Int) {
			runningCost += cost
			largestRunningCost = max(largestRunningCost, runningCost)
		}

		func end(cost: Int) {
			runningCost -= cost
		}

		private(set) var largestRunningCost = 0
		private var runningCost = 0
	}

	private actor Gate {
		func open() {
			isOpen = true
			for waiter in waiters {
				waiter.resume()
			}
			waiters.removeAll()
		}

		func waitUntilOpen() async {
			guard !isOpen else { return }
			await withCheckedContinuation { waiters.append($0) }
		}

		private var isOpen = false
		private var waiters = [CheckedContinuation<Void, Never>]()
	}

	private static func description(of outcome: BoundedConcurrency.Outcome<some Sendable>) -> String {
		switch outcome {
		case let .finished(value):
			"finished \(value)"
		case let .failed(error):
			"failed \((error as? JobError)?.index ?? -1)"
		case .notAdmitted:
			"not admitted"
		}
	}
}
