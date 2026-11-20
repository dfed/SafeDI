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

// SPIKE ONLY (in-tree parallel construction, 2026-11-20). The forced-interleaving harness run against MEM1's
// `BoundedConcurrency.map`, as PR 10's jobs would use it. The cells marked known issues are what PR 10 needs from the
// helper and MEM1's helper does not do yet (design note §2 step 4; lane 5's item 2).

import Testing
@testable import SafeDICore

struct BoundedConcurrencyInterleavingTests {
	// MARK: What the helper does today, under every completion order

	@Test(arguments: [1, 2, 3, 6])
	func map_returnsResultsInElementOrder_underEveryCompletionOrderOfSix(width: Int) async throws {
		for order in ForcedCompletionOrder.Order.every(count: 6) {
			let harness = ForcedCompletionOrder(count: 6, width: width, order: order)
			let results = try await BoundedConcurrency.map(Array(0..<6), width: width, harness.transform())
			#expect(results == [0, 10, 20, 30, 40, 50], "order \(order)")
			#expect(await harness.violations == [], "order \(order)")
			#expect(await harness.mostInFlight <= width, "order \(order)")
		}
	}

	@Test
	func harness_releasesInScriptedOrder_whenEveryJobIsAdmittedAtOnce() async throws {
		// At full width every job is at the gate before the first release, so the release order is the script exactly.
		for order in ForcedCompletionOrder.Order.every(count: 6) {
			let harness = ForcedCompletionOrder(count: 6, width: 6, order: order)
			_ = try await BoundedConcurrency.map(Array(0..<6), width: 6, harness.transform())
			let ranks = order.ranks(count: 6)
			let expected = (0..<6).sorted { ranks[$0] < ranks[$1] }
			#expect(await harness.released == expected, "order \(order)")
		}
	}

	@Test
	func harness_catchesJoinInArrivalOrder_onEveryOrderButNatural() async throws {
		// The hand mutation the harness exists for: a join that appends results as jobs finish. Under the harness it
		// differs from element order on every one of the 719 non-natural orders of six, every run.
		var caught = 0
		for order in ForcedCompletionOrder.Order.every(count: 6) {
			let harness = ForcedCompletionOrder(count: 6, width: 6, order: order)
			let results = try await Self.mapJoiningInArrivalOrder(Array(0..<6), width: 6, harness.transform())
			if results != [0, 10, 20, 30, 40, 50] {
				caught += 1
			}
		}
		#expect(caught == 719)
	}

	/// `BoundedConcurrency.map` with its join mutated to append in arrival order.
	private static func mapJoiningInArrivalOrder(
		_ elements: [Int],
		width: Int,
		_ transform: @escaping @Sendable (Int) async throws -> Int,
	) async throws -> [Int] {
		try await withThrowingTaskGroup(of: Int.self, returning: [Int].self) { taskGroup in
			var results = [Int]()
			var nextIndex = 0
			for element in elements.prefix(width) {
				taskGroup.addTask { try await transform(element) }
				nextIndex += 1
			}
			while let result = try await taskGroup.next() {
				results.append(result)
				if nextIndex < elements.count {
					let element = elements[nextIndex]
					taskGroup.addTask { try await transform(element) }
					nextIndex += 1
				}
			}
			return results
		}
	}

	@Test(arguments: [UInt64(1), 2, 3, 4, 5, 6, 7, 8])
	func map_returnsResultsInElementOrder_underSeededOrdersOfForty(seed: UInt64) async throws {
		let harness = ForcedCompletionOrder(count: 40, width: 4, order: .seeded(seed))
		let results = try await BoundedConcurrency.map(Array(0..<40), width: 4, harness.transform())
		#expect(results == (0..<40).map { $0 * 10 })
		#expect(await harness.violations == [])
	}

	@Test
	func map_admitsNoLaterElement_whenAnElementFails() async throws {
		// Element 1 fails first; at width 2 only elements 0 and 1 are admitted, and nothing after the failure.
		let harness = ForcedCompletionOrder(count: 8, width: 2, order: .ranked([7, 0, 1, 2, 3, 4, 5, 6]))
		await #expect(throws: ForcedCompletionOrder.Failure(element: 1)) {
			try await BoundedConcurrency.map(Array(0..<8), width: 2, harness.transform(failing: [1]))
		}
		#expect(await harness.released == [1])
		#expect(await harness.violations == [])
	}

	// MARK: What PR 10 needs (known issues on MEM1's helper at ba1f1bd6)

	@Test
	func map_throwsFirstFailureInElementOrder_whenLaterElementFailsFirst() async {
		// Elements 2 and 5 fail; 5 completes first. PR 10 reports a tree's first failure in walk order: element 2's.
		let harness = ForcedCompletionOrder(count: 6, width: 6, order: .reversed)
		await withKnownIssue("MEM1's helper throws the first failure to arrive, and cancels element 2 before it fails") {
			await #expect(throws: ForcedCompletionOrder.Failure(element: 2)) {
				try await BoundedConcurrency.map(Array(0..<6), width: 6, harness.transform(failing: [2, 5]))
			}
		}
	}

	@Test
	func map_runsEveryEarlierElement_whenLaterElementFailsFirst() async throws {
		// Element 5 fails first. Lane 5's item 2: earlier slots still run, so 0 through 4 each end, none cancelled.
		let harness = ForcedCompletionOrder(count: 6, width: 6, order: .reversed)
		await #expect(throws: ForcedCompletionOrder.Failure(element: 5)) {
			try await BoundedConcurrency.map(Array(0..<6), width: 6, harness.transform(failing: [5]))
		}
		let cancelled = await harness.cancelledAtGate
		await withKnownIssue("MEM1's helper cancels the jobs still running when one throws") {
			#expect(cancelled.isEmpty, "cancelled at the gate: \(cancelled.sorted())")
			#expect(await harness.succeeded.sorted() == [0, 1, 2, 3, 4])
		}
	}
}
