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
@testable import SafeDIToolTestSupport

/// The long run's cost report (`GraphFuzzerPhaseAccount`, the report's `cpu` line) and its shards
/// (`SAFEDI_GRAPH_FUZZER_SHARD`).
struct SafeDIToolGraphFuzzerPhaseAccountTests {
	// MARK: Tests – Phase account

	@Test
	func recordProcess_addsProcessCPUSecondsToPhaseOfRunningTask_whenRunInsideLongRunAccount() async throws {
		let account = GraphFuzzerPhaseAccount()
		// A loop the shell runs itself, so the process uses measurable CPU time.
		let result = try await GraphFuzzerPhaseAccount.$current.withValue(GraphFuzzerPhaseAccount.Context(account: account, phase: nil)) {
			try await GraphFuzzerPhaseAccount.measuring(.compiles) {
				try await runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "i=0; while [ $i -lt 200000 ]; do i=$((i + 1)); done"])
			}
		}

		#expect(result.exitCode == 0)
		#expect(await account.processCounts == [.compiles: 1])
		#expect(await account.processCPUSeconds[.compiles, default: 0] > 0)
	}

	@Test
	func measuring_countsSecondsOfNestedPhaseOnlyInNestedPhase() async throws {
		// Bounds that hold however long the suite's other tests make each step take: the account's clock reads fall
		// inside the test's outer pair and outside its inner pair.
		let account = GraphFuzzerPhaseAccount()
		var nestedSeconds = 0.0
		let outerStart = DispatchTime.now().uptimeNanoseconds
		try await GraphFuzzerPhaseAccount.$current.withValue(GraphFuzzerPhaseAccount.Context(account: account, phase: nil)) {
			try await GraphFuzzerPhaseAccount.measuring(.toolRuns) {
				try await GraphFuzzerPhaseAccount.measuring(.multiModule) {
					let nestedStart = DispatchTime.now().uptimeNanoseconds
					try await Task.sleep(nanoseconds: 20_000_000)
					nestedSeconds = Double(DispatchTime.now().uptimeNanoseconds - nestedStart) / 1e9
				}
			}
		}
		let outerSeconds = Double(DispatchTime.now().uptimeNanoseconds - outerStart) / 1e9

		let busySeconds = await account.busySeconds
		#expect(busySeconds[.multiModule, default: 0] >= nestedSeconds)
		// The nested phase's seconds are not counted again in the phase around it.
		#expect(busySeconds[.toolRuns, default: 0] <= outerSeconds - nestedSeconds + 1e-6)
	}

	@Test
	func reportField_listsEveryPhaseInDeclarationOrder() async throws {
		let account = GraphFuzzerPhaseAccount()
		try await GraphFuzzerPhaseAccount.$current.withValue(GraphFuzzerPhaseAccount.Context(account: account, phase: nil)) {
			try await GraphFuzzerPhaseAccount.measuring(.valueComparisons) {
				_ = try await runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 0"])
			}
		}

		let fields = await account.reportField.split(separator: ",")
		#expect(fields.map { $0.split(separator: "=")[0] } == ["tool-runs", "multi-module", "compiles", "value", "cross-process"])
		#expect(fields[0] == "tool-runs=0.0:0.0:0")
		#expect(fields[3].hasPrefix("value=") && fields[3].hasSuffix(":1"))
		#expect(fields[4] == "cross-process=0.0:0.0:0")
	}

	// MARK: Tests – Shards

	@Test
	func shard_splitsSeedsIntoConsecutiveShardsCoveringEachSeedOnce_whenCountDoesNotDivideIterations() throws {
		let shards = try (0..<3).map { try #require(GraphFuzzerLongRunConfiguration.shard($0, of: 3, startingSeed: 7, iterations: 1_000)) }

		#expect(shards.map(\.startingSeed) == [7, 341, 674])
		#expect(shards.map(\.iterations) == [334, 333, 333])
	}

	@Test
	func shard_returnsWholeRange_whenCountIsOne() throws {
		let shard = try #require(GraphFuzzerLongRunConfiguration.shard(0, of: 1, startingSeed: 0, iterations: 1_000))

		#expect(shard.startingSeed == 0)
		#expect(shard.iterations == 1_000)
	}

	@Test
	func shard_returnsNil_whenIndexIsNotBelowCount() {
		#expect(GraphFuzzerLongRunConfiguration.shard(2, of: 2, startingSeed: 0, iterations: 1_000)?.iterations == nil)
		#expect(GraphFuzzerLongRunConfiguration.shard(-1, of: 2, startingSeed: 0, iterations: 1_000)?.iterations == nil)
		#expect(GraphFuzzerLongRunConfiguration.shard(0, of: 0, startingSeed: 0, iterations: 1_000)?.iterations == nil)
	}
}
