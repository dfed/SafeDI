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

// SPIKE ONLY (in-tree parallel construction, 2026-11-20). The forced-interleaving harness PR 10's verdict needs: it holds
// each job of a bounded helper at a gate and lets exactly one run at a time, in a scripted order, so a test chooses
// which job completes first instead of hoping the scheduler does. It also checks the helper's admission as it goes.

/// Holds the jobs of one helper call at a gate and releases them one at a time, so they complete in a scripted order.
///
/// A job calls `enter(_:)` first and `leave(_:failed:)` last. While no released job is running, and every job the helper
/// should have admitted has arrived (`min(remaining, width)` of them), the harness releases the waiting job that ranks
/// first in `order`. After a job leaves failed, the helper may stop admitting, so the harness then releases whatever waits
/// without counting arrivals. A job cancelled at the gate is resumed with `false` and recorded.
actor ForcedCompletionOrder {
	enum Order: Sendable, CustomStringConvertible {
		/// Element order.
		case natural
		/// Last element first: the worst case for a join that appends in arrival order.
		case reversed
		/// A permutation drawn from a seed.
		case seeded(UInt64)
		/// `ranks[element]` is the element's place in the release order; lower releases first.
		case ranked([Int])

		func ranks(count: Int) -> [Int] {
			switch self {
			case .natural:
				Array(0..<count)
			case .reversed:
				Array((0..<count).reversed())
			case let .seeded(seed):
				Self.permutation(count: count, seed: seed)
			case let .ranked(ranks):
				ranks
			}
		}

		var description: String {
			switch self {
			case .natural: "natural"
			case .reversed: "reversed"
			case let .seeded(seed): "seeded(\(seed))"
			case let .ranked(ranks): "ranked(\(ranks))"
			}
		}

		/// Every order of `count` elements: `count`! of them. A permutation of six is the CLAUDE.md floor for choice-making code.
		static func every(count: Int) -> [Order] {
			var result = [Order]()
			var ranks = Array(0..<count)
			func permute(_ k: Int) {
				guard k < count else {
					result.append(.ranked(ranks))
					return
				}
				for index in k..<count {
					ranks.swapAt(k, index)
					permute(k + 1)
					ranks.swapAt(k, index)
				}
			}
			permute(0)
			return result
		}

		private static func permutation(count: Int, seed: UInt64) -> [Int] {
			var state = seed
			var ranks = Array(0..<count)
			for index in stride(from: count - 1, to: 0, by: -1) {
				// SplitMix64.
				state &+= 0x9E3779B97F4A7C15
				var mixed = state
				mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
				mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
				mixed ^= mixed >> 31
				ranks.swapAt(index, Int(mixed % UInt64(index + 1)))
			}
			return ranks
		}
	}

	struct Failure: Error, Equatable {
		let element: Int
	}

	init(count: Int, width: Int, order: Order) {
		self.count = count
		self.width = width
		ranks = order.ranks(count: count)
	}

	/// The order jobs were released in.
	private(set) var released = [Int]()
	/// Jobs that left without failing, in the order they left.
	private(set) var succeeded = [Int]()
	/// Jobs that left failed, in the order they left.
	private(set) var failed = [Int]()
	/// Jobs cancelled while held at the gate.
	private(set) var cancelledAtGate = [Int]()
	/// What the harness saw the helper do that no admission rule allows.
	private(set) var violations = [String]()
	/// The most jobs between `enter` and their end at once.
	private(set) var mostInFlight = 0

	/// A transform for `BoundedConcurrency.map` over `0..<count` that passes through this harness and throws
	/// `Failure(element)` for each element of `failing`.
	nonisolated func transform(failing: Set<Int> = []) -> @Sendable (Int) async throws -> Int {
		{ element in
			guard await self.enter(element) else {
				throw CancellationError()
			}
			let fails = failing.contains(element)
			await self.leave(element, failed: fails)
			if fails {
				throw Failure(element: element)
			}
			return element * 10
		}
	}

	/// Waits at the gate. `true` once released; `false` if the job was cancelled while held.
	func enter(_ element: Int) async -> Bool {
		inFlight += 1
		mostInFlight = max(mostInFlight, inFlight)
		if inFlight > width {
			violations.append("\(inFlight) jobs in flight at width \(width) when \(element) entered")
		}
		if entered.contains(element) {
			violations.append("\(element) entered twice")
		}
		entered.insert(element)
		let wasReleased = await withTaskCancellationHandler {
			await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
				if Task.isCancelled {
					continuation.resume(returning: false)
				} else {
					waiting[element] = continuation
					releaseIfSettled()
				}
			}
		} onCancel: {
			Task { await self.cancelAtGate(element) }
		}
		if !wasReleased {
			inFlight -= 1
			cancelledAtGate.append(element)
		}
		return wasReleased
	}

	func leave(_ element: Int, failed jobFailed: Bool) {
		if running != element {
			violations.append("\(element) left without being the running job")
		}
		running = nil
		inFlight -= 1
		left += 1
		if jobFailed {
			failed.append(element)
		} else {
			succeeded.append(element)
		}
		releaseIfSettled()
	}

	// MARK: Private

	private let count: Int
	private let width: Int
	private let ranks: [Int]
	private var waiting = [Int: CheckedContinuation<Bool, Never>]()
	private var entered = Set<Int>()
	private var running: Int?
	private var inFlight = 0
	private var left = 0

	private func cancelAtGate(_ element: Int) {
		guard let continuation = waiting.removeValue(forKey: element) else { return }
		continuation.resume(returning: false)
	}

	private func releaseIfSettled() {
		guard running == nil, !waiting.isEmpty else { return }
		guard failed.isEmpty else {
			// The helper may now be throwing and cancelling: give it a grace period to do so before releasing a held job,
			// so a job is never released into a race with the throw. A helper that keeps earlier jobs running gets them
			// released after the grace.
			guard !graceScheduled else { return }
			graceScheduled = true
			Task {
				try? await Task.sleep(nanoseconds: Self.graceNanoseconds)
				await self.releaseAfterGrace()
			}
			return
		}
		let expected = min(count - left - cancelledAtGate.count, width)
		if waiting.count > expected {
			violations.append("\(waiting.count) jobs waiting where the helper should have admitted \(expected)")
		}
		guard waiting.count >= expected else { return }
		releaseFirstRanked()
	}

	private static let graceNanoseconds: UInt64 = 50_000_000
	private var graceScheduled = false

	private func releaseAfterGrace() {
		graceScheduled = false
		guard running == nil, !waiting.isEmpty else { return }
		releaseFirstRanked()
	}

	private func releaseFirstRanked() {
		let element = waiting.keys.min { ranks[$0] < ranks[$1] }!
		let continuation = waiting.removeValue(forKey: element)!
		running = element
		released.append(element)
		continuation.resume(returning: true)
	}
}
