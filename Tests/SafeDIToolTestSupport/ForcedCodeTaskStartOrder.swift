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


import SafeDICore
import Synchronization

/// Forces the order in which the early starts of a run of `generate` finish: each early start waits for its turn, and
/// the turns go, one finished start after another, in the order `order` gives the starts' arrival positions.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class ForcedCodeTaskStartOrder: CodeTaskStartOrdering {
	/// - Parameter order: Given how many starts arrived, the arrival positions in the order their turns go.
	init(order: @escaping @Sendable (Int) -> [Int]) {
		self.order = order
	}

	func registerStart() {
		registeredStartCount.withLock { $0 += 1 }
	}

	func waitForTurn() async -> Int {
		await gate.arrive()
	}

	func finish(_ turn: Int) async {
		await gate.finish(turn)
	}

	func runEveryStart() async {
		await gate.run(startCount: registeredStartCount.withLock { $0 }, order: order)
	}

	/// The order the turns of the last run went in, by arrival position.
	func turnsTaken() async -> [Int] {
		await gate.turnsTaken
	}

	private let order: @Sendable (Int) -> [Int]
	private let registeredStartCount = Mutex(0)
	private let gate = Gate()

	private actor Gate {
		func arrive() async -> Int {
			await withCheckedContinuation { continuation in
				waitingStarts.append(continuation)
				if let arrivalsAwaited, waitingStarts.count == arrivalsAwaited.count {
					self.arrivalsAwaited = nil
					arrivalsAwaited.continuation.resume()
				}
			}
		}

		func finish(_ turn: Int) {
			finishAwaited?.resume()
			finishAwaited = nil
			turnsTaken.append(turn)
		}

		func run(startCount: Int, order: @Sendable (Int) -> [Int]) async {
			if waitingStarts.count < startCount {
				await withCheckedContinuation { arrivalsAwaited = (startCount, $0) }
			}
			let starts = waitingStarts
			waitingStarts = []
			for position in order(starts.count) {
				await withCheckedContinuation { continuation in
					finishAwaited = continuation
					starts[position].resume(returning: position)
				}
			}
		}

		private(set) var turnsTaken = [Int]()
		private var waitingStarts = [CheckedContinuation<Int, Never>]()
		private var arrivalsAwaited: (count: Int, continuation: CheckedContinuation<Void, Never>)?
		private var finishAwaited: CheckedContinuation<Void, Never>?
	}
}
