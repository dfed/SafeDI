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

/// Lets the task of a body's child that started last finish first, each time every task in flight has planned its code,
/// so a body that plans its children at once sees them finish out of order on every run: of 20 children planned four at
/// a time, 3, 4, …, 19, then 2, 1, 0. Set as `ConcurrentChildCode.ordering` by the tests.
public actor LatestStartedChildCodeFinishesFirst: ConcurrentChildCodeOrdering {
	/// - Parameter childrenInFlight: The most children a body plans at once (`ConcurrentChildCode.maximumChildrenAtOnce`).
	public init(childrenInFlight: Int) {
		self.childrenInFlight = childrenInFlight
	}

	public func waitForTurn(ofChildAt position: Int, childCount: Int) async {
		await withCheckedContinuation { continuation in
			waiting[position] = continuation
			releaseWhenEveryTaskInFlightWaits(childCount: childCount)
		}
	}

	/// The positions of the children whose tasks finished, in the order they finished.
	public func finishingOrder() -> [Int] {
		finished
	}

	// MARK: Private

	private let childrenInFlight: Int
	private var waiting = [Int: CheckedContinuation<Void, Never>]()
	private var finished = [Int]()

	private func releaseWhenEveryTaskInFlightWaits(childCount: Int) {
		// Once the group has no child left to add, the tasks in flight finish one after another, latest first.
		while waiting.count == min(childrenInFlight, childCount - finished.count), let latest = waiting.keys.max(), let continuation = waiting.removeValue(forKey: latest) {
			finished.append(latest)
			continuation.resume()
		}
	}
}
