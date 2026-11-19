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
import Synchronization
import Testing
@testable import SafeDICore

struct GenerationJobsTests {
	// MARK: Admission, stopping and nesting

	@Test(arguments: [0, 1, 7, 13, 19])
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func resultsStoppingAtFirstFailure_admitsNoLaterJob_whenOneOfTwentyJobsFails(failingIndex: Int) async throws {
		var runs: [(width: Int, order: CompletionOrder)] = [(width: 1, order: .index), (width: 4, order: .index), (width: 4, order: .reverse)]
		runs += (1...5).map { (width: 4, order: .seeded(UInt64($0))) }
		for (width, order) in runs {
			// A job holds every slot one or two places after the failing job: it is admitted only once every job before it
			// is collected, so it is admitted when the call fails to stop, and no job a collection before the failure's
			// could admit is left to make the jobs admitted depend on which of the released jobs the helper collects
			// first. In index order the job after the failing one is in flight when it fails, and keeps its outcome.
			let blockingIndex = order == .index && failingIndex + 2 < 20 ? failingIndex + 2 : failingIndex + 1
			let costs = (0..<20).map { $0 == blockingIndex ? 4 : 1 }
			let shape = CallShape(costs: costs.map { min($0, width) }, width: width, stopsAtFirstFailure: true, failingIndices: [failingIndex])
			let gate = CompletionGate(order: order) { _ in shape }
			let outcomes = try await GenerationJobs.$width.withValue(width) {
				try await GenerationJobs.$completionObserver.withValue(gate.arrive) {
					try await GenerationJobs.resultsStoppingAtFirstFailure(of: costs.enumerated().map { GenerationJob($0.offset, cost: $0.element) }) { (index: consuming Int) throws(JobFailure) -> Int in
						let index = index
						await gate.start([index])
						if index == failingIndex {
							throw JobFailure(index: index)
						}
						return index
					}
				}
			}

			let admittedCount = await gate.admittedCount(of: [])
			#expect(await gate.violations == [], "width \(width), \(order)")
			// The jobs that ran are exactly those admitted before the failure was collected, and the failing job is among them.
			#expect(await Set(gate.arrivals(of: [])) == Set(0..<admittedCount), "width \(width), \(order)")
			#expect(admittedCount == (order == .index && width > 1 && blockingIndex == failingIndex + 2 ? failingIndex + 2 : failingIndex + 1), "width \(width), \(order)")
			for (index, outcome) in outcomes.enumerated() {
				switch outcome {
				case let .success(value)?:
					#expect(index < admittedCount && index != failingIndex && value == index, "width \(width), \(order)")
				case let .failure(failure)?:
					#expect(index == failingIndex && failure.index == index, "width \(width), \(order)")
				case nil:
					#expect(index >= admittedCount, "width \(width), \(order)")
				}
			}
			// The error a caller reports, the failure of the lowest index, is the failing job's.
			let firstFailure = outcomes.lazy.compactMap { outcome -> JobFailure? in
				if case let .failure(failure)? = outcome {
					failure
				} else {
					nil
				}
			}.first
			#expect(firstFailure == JobFailure(index: failingIndex), "width \(width), \(order)")
		}
	}

	@Test(arguments: [CompletionOrder.index, .reverse, .seeded(1), .seeded(2), .seeded(3)])
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func resultsStoppingAtFirstFailure_stopsNoJobOfAnotherUnit_whenAJobOfOneUnitFails(order: CompletionOrder) async throws {
		// Two units of cost 2 at width 4, each making a nested stopping call over twenty jobs; job 3 of unit 0 fails, and
		// job 4 holds both of the unit's slots, so that no job the failure must stop can be admitted before it is collected.
		let nestedCosts = (0..<20).map { $0 == 4 ? 2 : 1 }
		let gate = CompletionGate(order: order) { call in
			call.isEmpty
				? CallShape(costs: [2, 2], width: 4, stopsAtFirstFailure: false, failingIndices: [])
				: CallShape(costs: nestedCosts, width: 2, stopsAtFirstFailure: true, failingIndices: call == [0] ? [3] : [])
		}
		let outcomes = try await GenerationJobs.$width.withValue(4) {
			try await GenerationJobs.$completionObserver.withValue(gate.arrive) {
				try await GenerationJobs.results(of: [GenerationJob(0, cost: 2), GenerationJob(1, cost: 2)]) { (unit: consuming Int) async throws -> [Result<Int, JobFailure>?] in
					let failingIndex = unit == 0 ? 3 : nil
					return try await GenerationJobs.resultsStoppingAtFirstFailure(of: nestedCosts.enumerated().map { GenerationJob($0.offset, cost: $0.element) }) { (index: consuming Int) throws(JobFailure) -> Int in
						if index == failingIndex {
							throw JobFailure(index: index)
						}
						return index
					}
				}
			}
		}

		#expect(await gate.violations == [])
		let failingUnitOutcomes = try outcomes[0].get()
		let otherUnitOutcomes = try outcomes[1].get()
		#expect(otherUnitOutcomes.map { outcome in outcome.flatMap { try? $0.get() } } == (0..<20).map(Optional.some))
		#expect(failingUnitOutcomes.prefix(3).map { outcome in outcome.flatMap { try? $0.get() } } == [0, 1, 2])
		#expect(await gate.admittedCount(of: [0]) == 4)
		#expect(failingUnitOutcomes.suffix(from: 4).allSatisfy { $0 == nil })
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func results_runsEveryJobInTheCallersTask_whenNestingAtWidthOne() async throws {
		let recorder = JobRecorder()
		let callerTask = withUnsafeCurrentTask { $0?.hashValue }
		let outcomes = try await GenerationJobs.$width.withValue(1) {
			try await GenerationJobs.results(of: (0..<3).map { GenerationJob($0) }) { (unit: consuming Int) async throws -> [Int] in
				let unit = unit
				recorder.enter(task: withUnsafeCurrentTask { $0?.hashValue })
				recorder.leave()
				let nestedOutcomes = try await GenerationJobs.results(of: (0..<3).map { GenerationJob(unit * 3 + $0) }) { (job: consuming Int) in
					let job = job
					recorder.enter(task: withUnsafeCurrentTask { $0?.hashValue })
					await Task.yield()
					recorder.record(job)
					recorder.leave()
					return job
				}
				return nestedOutcomes.map { $0.get() }
			}
		}

		#expect(outcomes.flatMap { (try? $0.get()) ?? [] } == Array(0..<9))
		#expect(recorder.completedJobs == Array(0..<9))
		#expect(recorder.mostRunningAtOnce == 1)
		#expect(recorder.tasks.count == 12)
		#expect(recorder.tasks.allSatisfy { $0 == callerTask })
	}

	@Test(arguments: [CompletionOrder.index, .reverse, .seeded(1), .seeded(2), .seeded(3)])
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func results_holdsAtMostTheWidthInFlightAtEveryLevel_whenUnitsOfDrawnCostsNest(order: CompletionOrder) async throws {
		var generator = SplitMix64(seed: 646)
		var costs = (0..<20).map { _ in Int.random(in: 1...4, using: &generator) }
		// A unit of cost 3 that must wait while 2 slots are free, followed by a unit of cost 1 that would fit.
		costs[0] = 2
		costs[1] = 3
		costs[2] = 1
		let unitCosts = costs
		let gate = CompletionGate(order: order) { call in
			call.isEmpty
				? CallShape(costs: unitCosts, width: 4, stopsAtFirstFailure: false, failingIndices: [])
				: CallShape(costs: Array(repeating: 1, count: 20), width: unitCosts[call[0]], stopsAtFirstFailure: false, failingIndices: [])
		}
		let occupancy = Occupancy()
		let outcomes = try await GenerationJobs.$width.withValue(4) {
			try await GenerationJobs.$completionObserver.withValue(gate.arrive) {
				try await GenerationJobs.results(of: unitCosts.enumerated().map { GenerationJob($0.offset, cost: $0.element) }) { (unit: consuming Int) async throws -> [Int] in
					let unit = unit
					await gate.start([unit])
					occupancy.enter(call: [], cost: unitCosts[unit])
					defer { occupancy.leave(call: [], cost: unitCosts[unit]) }
					#expect(GenerationJobs.width == unitCosts[unit])
					let nestedOutcomes = try await GenerationJobs.results(of: (0..<20).map { GenerationJob($0) }) { (job: consuming Int) in
						let job = job
						await gate.start([unit, job])
						occupancy.enter(call: [unit], cost: 1, runsJobCode: true)
						await Task.yield()
						occupancy.leave(call: [unit], cost: 1, runsJobCode: true)
						return unit * 20 + job
					}
					return nestedOutcomes.map { $0.get() }
				}
			}
		}

		#expect(await gate.violations == [])
		#expect(outcomes.flatMap { (try? $0.get()) ?? [] } == Array(0..<400))
		#expect(occupancy.mostCostInFlight(of: []) <= 4)
		for unit in 0..<20 {
			#expect(occupancy.mostCostInFlight(of: [unit]) <= unitCosts[unit])
		}
		#expect(occupancy.mostRunningJobCode <= 4)
		// Every unit started and completed while the admission rule admitted it: the unit of cost 1 after the unit of cost 3
		// is not admitted while the unit of cost 3 waits for its slots.
		#expect(await gate.arrivals(of: []).count == 20)
	}

	// MARK: Cancellation

	@Test(arguments: [(width: 4, jobCount: 20), (width: 4, jobCount: 3), (width: 1, jobCount: 3), (width: 1, jobCount: 2)])
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func results_throwsCancellationErrorAfterEveryStartedJobFinishes_whenTheCallingTaskIsCancelledMidCall(width: Int, jobCount: Int) async {
		// At width 4 every job in flight is held; at width 1, the last job of the first two. Job 0 fails before the call is
		// cancelled, so a failure is collected and still reported nowhere.
		let heldJobCount = width == 1 ? 1 : min(width, jobCount)
		let holder = JobHolder(holding: width == 1 ? [1] : Set(0..<heldJobCount))
		let recorder = JobRecorder()
		// The call's outcome comes back as the child task's result rather than through a captured `Mutex`: Swift 6.2
		// rejects a closure passed to `addTask` that captures a local `Mutex` ("passing closure as a 'sending' parameter
		// risks causing data races"), since it captures the noncopyable value by reference.
		let callOutcome = await withTaskGroup(of: Result<[Result<Int, JobFailure>], any Error>.self) { testGroup in
			testGroup.addTask {
				do {
					return try await .success(GenerationJobs.$width.withValue(width) {
						try await GenerationJobs.$completionObserver.withValue(holder.arrive) {
							try await GenerationJobs.results(of: (0..<jobCount).map { GenerationJob($0) }) { (job: consuming Int) throws(JobFailure) -> Int in
								let job = job
								recorder.record(started: job)
								defer { recorder.record(job) }
								if job == 0 {
									throw JobFailure(index: job)
								}
								return job
							}
						}
					})
				} catch {
					return .failure(error)
				}
			}
			await holder.waitUntilHeld(heldJobCount)
			testGroup.cancelAll()
			await holder.releaseAll()
			return await testGroup.next()
		}

		let startedJobs = width == 1 ? [0, 1] : Array(0..<heldJobCount)
		// The call returned nothing, and threw `CancellationError`.
		#expect(throws: CancellationError.self) { try callOutcome?.get() }
		#expect(recorder.startedJobs.sorted() == startedJobs)
		#expect(recorder.completedJobs.sorted() == startedJobs)
	}

	// MARK: Release

	@Test(arguments: [(width: 1, order: CompletionOrder.index), (width: 4, order: .index), (width: 4, order: .reverse), (width: 4, order: .seeded(1)), (width: 4, order: .seeded(2))])
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func results_releasesEachInputOnItsJobsTaskBeforeItsOutcomeIsCollected_whenTheJobEnds(width: Int, order: CompletionOrder) async throws {
		let releases = ReleaseRecorder()
		let shape = CallShape(costs: [1, 1, 1], width: width, stopsAtFirstFailure: false, failingIndices: [])
		let gate = CompletionGate(order: order) { _ in shape }
		let checks = Mutex([String]())
		let observer: @Sendable ([Int]) async -> Void = { path in
			// The job's work has returned, and the helper has not collected its outcome.
			if let index = path.last {
				let release = releases.release(of: index)
				if release == nil {
					checks.withLock { $0.append("input \(index) is alive when its outcome is collected") }
				} else if release != releases.jobTask(of: index) {
					checks.withLock { $0.append("input \(index) was released on another task than its job’s") }
				}
			}
			await gate.arrive(path)
		}
		let outcomes = try await GenerationJobs.$width.withValue(width) {
			try await GenerationJobs.$completionObserver.withValue(observer) {
				try await GenerationJobs.results(of: (0..<3).map { GenerationJob(TrackedInput(index: $0, releases: releases)) }) { (input: consuming TrackedInput) -> Int in
					let index = input.index
					releases.record(jobTask: withUnsafeCurrentTask { $0?.hashValue }, of: index)
					if width == 1, index > 0, releases.release(of: index - 1) == nil {
						checks.withLock { $0.append("input \(index - 1) is alive when job \(index) starts") }
					}
					return index
				}
			}
		}

		#expect(outcomes.map { $0.get() } == [0, 1, 2])
		#expect(checks.withLock { $0 } == [])
		#expect(await gate.violations == [])
		#expect((0..<3).allSatisfy { releases.release(of: $0) != nil })
	}

	// MARK: Width and cost

	@Test(arguments: [0, -3])
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func results_runsJobsOneAtATimeInTheCallersTask_whenWidthIsBelowOne(width: Int) async throws {
		let callerTask = withUnsafeCurrentTask { $0?.hashValue }
		let outcomes = try await GenerationJobs.$width.withValue(width) {
			try await GenerationJobs.results(of: (0..<3).map { GenerationJob($0, cost: 5) }) { (job: consuming Int) -> (job: Int, width: Int, task: Int?) in
				(job: job, width: GenerationJobs.width, task: withUnsafeCurrentTask { $0?.hashValue })
			}
		}

		#expect(outcomes.map { $0.get().job } == [0, 1, 2])
		#expect(outcomes.map { $0.get().width } == [1, 1, 1])
		#expect(outcomes.allSatisfy { $0.get().task == callerTask })
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func results_runsEachJobAtItsCostClampedToTheWidth_whenCostsLieOutsideOneThroughTheWidth() async throws {
		let outcomes = try await GenerationJobs.$width.withValue(3) {
			try await GenerationJobs.results(of: [GenerationJob(0, cost: 0), GenerationJob(1, cost: -2), GenerationJob(2, cost: 2), GenerationJob(3, cost: 9)]) { (_: consuming Int) in
				GenerationJobs.width
			}
		}

		#expect(outcomes.map { $0.get() } == [1, 1, 2, 3])
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
	func results_returnsNoOutcomes_whenGivenNoJobs() async throws {
		for width in [1, 4] {
			let outcomes = try await GenerationJobs.$width.withValue(width) {
				try await GenerationJobs.results(of: [GenerationJob<Int>]()) { (job: consuming Int) in job }
			}
			#expect(outcomes.isEmpty)
		}
	}
}

// MARK: - Helpers

/// A failure a job throws, naming the job.
private struct JobFailure: Error, Equatable {
	let index: Int
}

/// An order of completion a `CompletionGate` forces among the jobs in flight.
enum CompletionOrder: Equatable, Sendable, CustomTestStringConvertible {
	/// The lowest index in flight first.
	case index
	/// The highest index in flight first.
	case reverse
	/// One drawn from those in flight by a generator seeded with the value, separately for each call.
	case seeded(UInt64)

	var testDescription: String {
		switch self {
		case .index: "index order"
		case .reverse: "reverse order"
		case let .seeded(seed): "order drawn by seed \(seed)"
		}
	}
}

/// A generator whose draws repeat for a seed.
struct SplitMix64: RandomNumberGenerator {
	init(seed: UInt64) {
		state = seed
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E3779B97F4A7C15
		var value = state
		value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
		value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
		return value ^ (value >> 31)
	}

	private var state: UInt64
}

/// One helper call as the helper's rules admit its jobs: their costs, its width, and whether it stops at the first
/// failure it collects, which `failingIndices` names.
struct CallShape: Sendable {
	let costs: [Int]
	let width: Int
	let stopsAtFirstFailure: Bool
	let failingIndices: Set<Int>
}

/// Holds each job as the helper reports its completion, and releases the jobs of one call one at a time, in a chosen
/// order, once every job the admission rule puts in flight is held: so an order among the jobs in flight is forced
/// without timing, and a job that arrives while the rule does not admit it is recorded as a violation.
///
/// The jobs the rule puts in flight follow from the jobs released: admission is in index order, while the costs of the
/// admitted jobs not yet released plus the next job's cost are at most the width, and, in a call that stops at its first
/// failure, never after a failing job is released.
actor CompletionGate {
	init(order: CompletionOrder, shape: @escaping @Sendable (_ call: [Int]) -> CallShape) {
		self.order = order
		self.shape = shape
	}

	/// Each violation of the admission rule seen.
	private(set) var violations = [String]()

	/// The completion observer: holds the job at `path` until its turn.
	nonisolated func arrive(_ path: [Int]) async {
		await hold(path)
	}

	/// Records a violation when the job at `path` starts while the admission rule does not admit it.
	func start(_ path: [Int]) {
		guard let index = path.last else {
			violations.append("a job started with an empty path")
			return
		}
		let jobsInFlight = jobsInFlight(of: Array(path.dropLast()))
		if !jobsInFlight.contains(index) {
			violations.append("job \(path) started while the rule admits only \(jobsInFlight.sorted()) of its call")
		}
	}

	/// The jobs of the call at `call` that reported completion, in the order they did.
	func arrivals(of call: [Int]) -> [Int] {
		arrivalsByCall[call, default: []]
	}

	/// How many jobs of the call at `call` the rule has admitted.
	func admittedCount(of call: [Int]) -> Int {
		admittedCountByCall[call, default: 0]
	}

	// MARK: Private

	private let order: CompletionOrder
	private let shape: @Sendable ([Int]) -> CallShape
	private var heldByCall = [[Int]: [Int: CheckedContinuation<Void, Never>]]()
	private var releasedByCall = [[Int]: Set<Int>]()
	private var admittedCountByCall = [[Int]: Int]()
	private var stoppedCalls = Set<[Int]>()
	private var arrivalsByCall = [[Int]: [Int]]()
	private var generatorsByCall = [[Int]: SplitMix64]()

	private func hold(_ path: [Int]) async {
		guard let index = path.last else {
			violations.append("a job reported an empty path")
			return
		}
		let call = Array(path.dropLast())
		arrivalsByCall[call, default: []].append(index)
		let jobsInFlight = jobsInFlight(of: call)
		guard jobsInFlight.contains(index) else {
			// Not held, so that the call ends and the test reports the violation.
			violations.append("job \(path) completed while the rule admits only \(jobsInFlight.sorted()) of its call")
			return
		}
		await withCheckedContinuation { continuation in
			heldByCall[call, default: [:]][index] = continuation
			releaseWhileEveryJobInFlightIsHeld(of: call)
		}
	}

	private func jobsInFlight(of call: [Int]) -> Set<Int> {
		let shape = shape(call)
		let released = releasedByCall[call, default: []]
		var admittedCount = admittedCountByCall[call, default: 0]
		if !stoppedCalls.contains(call) {
			while admittedCount < shape.costs.count,
			      (0..<admittedCount).filter({ !released.contains($0) }).map({ shape.costs[$0] }).reduce(0, +) + shape.costs[admittedCount] <= shape.width
			{
				admittedCount += 1
			}
			admittedCountByCall[call] = admittedCount
		}
		return Set((0..<admittedCount).filter { !released.contains($0) })
	}

	private func releaseWhileEveryJobInFlightIsHeld(of call: [Int]) {
		while true {
			let jobsInFlight = jobsInFlight(of: call).sorted()
			let held = heldByCall[call, default: [:]]
			guard !jobsInFlight.isEmpty, jobsInFlight.allSatisfy({ held[$0] != nil }) else { return }
			let chosen: Int
			switch order {
			case .index:
				chosen = jobsInFlight[0]
			case .reverse:
				chosen = jobsInFlight[jobsInFlight.count - 1]
			case let .seeded(seed):
				var generator = generatorsByCall[call] ?? SplitMix64(seed: call.reduce(seed) { $0 &* 31 &+ UInt64($1) })
				chosen = jobsInFlight[Int.random(in: 0..<jobsInFlight.count, using: &generator)]
				generatorsByCall[call] = generator
			}
			releasedByCall[call, default: []].insert(chosen)
			let shape = shape(call)
			if shape.stopsAtFirstFailure, shape.failingIndices.contains(chosen) {
				stoppedCalls.insert(call)
			}
			heldByCall[call]?[chosen] = nil
			held[chosen]?.resume()
		}
	}
}

/// Holds the jobs it is told to, as they report completion, until `releaseAll()`; lets every other job through.
actor JobHolder {
	init(holding jobsToHold: Set<Int>) {
		self.jobsToHold = jobsToHold
	}

	nonisolated func arrive(_ path: [Int]) async {
		await hold(path)
	}

	func waitUntilHeld(_ count: Int) async {
		guard held.count < count else { return }
		await withCheckedContinuation { continuation in
			heldCountWaiter = (count, continuation)
		}
	}

	func releaseAll() {
		isReleased = true
		for continuation in held {
			continuation.resume()
		}
		held = []
	}

	// MARK: Private

	private let jobsToHold: Set<Int>
	private var held = [CheckedContinuation<Void, Never>]()
	private var heldCountWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
	private var isReleased = false

	private func hold(_ path: [Int]) async {
		guard !isReleased, let index = path.last, jobsToHold.contains(index) else { return }
		await withCheckedContinuation { continuation in
			held.append(continuation)
			if let heldCountWaiter, held.count >= heldCountWaiter.count {
				self.heldCountWaiter = nil
				heldCountWaiter.continuation.resume()
			}
		}
	}
}

/// What the jobs of a test did, from any task.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class JobRecorder: Sendable {
	func enter(task: Int?) {
		state.withLock { state in
			state.tasks.append(task)
			state.running += 1
			state.mostRunningAtOnce = max(state.mostRunningAtOnce, state.running)
		}
	}

	func leave() {
		state.withLock { $0.running -= 1 }
	}

	func record(started job: Int) {
		state.withLock { $0.startedJobs.append(job) }
	}

	func record(_ completedJob: Int) {
		state.withLock { $0.completedJobs.append(completedJob) }
	}

	var tasks: [Int?] {
		state.withLock(\.tasks)
	}

	var mostRunningAtOnce: Int {
		state.withLock(\.mostRunningAtOnce)
	}

	var startedJobs: [Int] {
		state.withLock(\.startedJobs)
	}

	var completedJobs: [Int] {
		state.withLock(\.completedJobs)
	}

	private struct State {
		var tasks = [Int?]()
		var running = 0
		var mostRunningAtOnce = 0
		var startedJobs = [Int]()
		var completedJobs = [Int]()
	}

	private let state = Mutex(State())
}

/// The cost each call holds in jobs that run, and the jobs that run job code, at once, at their most.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class Occupancy: Sendable {
	func enter(call: [Int], cost: Int, runsJobCode: Bool = false) {
		state.withLock { state in
			state.costInFlight[call, default: 0] += cost
			state.mostCostInFlight[call] = max(state.mostCostInFlight[call, default: 0], state.costInFlight[call, default: 0])
			if runsJobCode {
				state.runningJobCode += 1
				state.mostRunningJobCode = max(state.mostRunningJobCode, state.runningJobCode)
			}
		}
	}

	func leave(call: [Int], cost: Int, runsJobCode: Bool = false) {
		state.withLock { state in
			state.costInFlight[call, default: 0] -= cost
			if runsJobCode {
				state.runningJobCode -= 1
			}
		}
	}

	func mostCostInFlight(of call: [Int]) -> Int {
		state.withLock { $0.mostCostInFlight[call, default: 0] }
	}

	var mostRunningJobCode: Int {
		state.withLock(\.mostRunningJobCode)
	}

	private struct State {
		var costInFlight = [[Int]: Int]()
		var mostCostInFlight = [[Int]: Int]()
		var runningJobCode = 0
		var mostRunningJobCode = 0
	}

	private let state = Mutex(State())
}

/// The task each job ran on, and the task each job's input was released on.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class ReleaseRecorder: Sendable {
	func record(jobTask: Int?, of index: Int) {
		state.withLock { $0.jobTasks[index] = jobTask ?? 0 }
	}

	func record(releaseTask: Int?, of index: Int) {
		state.withLock { $0.releaseTasks[index] = releaseTask ?? 0 }
	}

	func jobTask(of index: Int) -> Int? {
		state.withLock { $0.jobTasks[index] }
	}

	func release(of index: Int) -> Int? {
		state.withLock { $0.releaseTasks[index] }
	}

	private struct State {
		var jobTasks = [Int: Int]()
		var releaseTasks = [Int: Int]()
	}

	private let state = Mutex(State())
}

/// An input whose release is recorded, with the task it happened on.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class TrackedInput: Sendable {
	init(index: Int, releases: ReleaseRecorder) {
		self.index = index
		self.releases = releases
	}

	deinit {
		releases.record(releaseTask: withUnsafeCurrentTask { $0?.hashValue }, of: index)
	}

	let index: Int

	private let releases: ReleaseRecorder
}
