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

/// Forces the order in which the jobs of `GenerationJobs` calls complete, through `GenerationJobs.completionObserver`,
/// for calls whose jobs are all in flight at once: it holds each job of a call as the job completes until all
/// `jobCount` are held, then releases them in `releaseOrder`, and does the same for the next call. Every call it observes
/// must have `jobCount` jobs, at a width of at least `jobCount`, and the calls must run one after another.
actor ForcedCompletionOrder {
	init(jobCount: Int, releaseOrder: [Int]) {
		self.jobCount = jobCount
		self.releaseOrder = releaseOrder
	}

	/// The orders a test of a choice among `jobCount` jobs forces, by name: index order, reverse order, and five orders
	/// drawn by seed.
	static func orders(ofJobCount jobCount: Int) -> [(name: String, releaseOrder: [Int])] {
		var orders = [
			(name: "index order", releaseOrder: Array(0..<jobCount)),
			(name: "reverse order", releaseOrder: Array((0..<jobCount).reversed())),
		]
		for seed in UInt64(1)...5 {
			var generator = SeededGenerator(seed: seed)
			orders.append((name: "order drawn by seed \(seed)", releaseOrder: Array(0..<jobCount).shuffled(using: &generator)))
		}
		return orders
	}

	/// The completion observer.
	nonisolated func arrive(_ path: [Int]) async {
		await hold(path)
	}

	// MARK: Private

	private let jobCount: Int
	private let releaseOrder: [Int]
	private var held = [Int: CheckedContinuation<Void, Never>]()

	private func hold(_ path: [Int]) async {
		guard let index = path.last else { return }
		await withCheckedContinuation { continuation in
			held[index] = continuation
			if held.count == jobCount {
				let batch = held
				held = [:]
				for index in releaseOrder {
					batch[index]?.resume()
				}
			}
		}
	}
}

/// A generator whose draws repeat for a seed (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
	init(seed: UInt64) {
		state = seed
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var value = state
		value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
		value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
		return value ^ (value >> 31)
	}

	private var state: UInt64
}
