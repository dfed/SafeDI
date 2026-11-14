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

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif
import Foundation

/// A phase of the graph fuzzer's oracle whose cost the long run reports (`cpu`).
enum GraphFuzzerPhase: String, CaseIterable, Sendable {
	/// Running the tool in the test process over each graph: twice, under each renaming, and the other runs the
	/// corpus's oracles make (a seam graph without its seam, a read twin, …), but not the multi-module runs.
	case toolRuns = "tool-runs"
	/// Running the tool in the test process over each base corpus graph split across modules, through both
	/// multi-module integrations (`GraphFuzzerMultiModuleProperty`).
	case multiModule = "multi-module"
	/// Compiling each batch's fixtures with their generated code, once per module role, and again to attribute a
	/// failure (`GraphFuzzerOracle.compilationFailures(of:definesDebug:)`).
	case compiles
	/// The value oracles' batches: compiling each path, linking it, and running the probes
	/// (`GraphFuzzerOracle.valueComparisons(of:isolatingValueGraphsOf:)`).
	case valueComparisons = "value"
	/// Running the `SafeDITool` executable in two processes over every 50th seed
	/// (`GraphFuzzerOracle.crossProcessFailure(of:)`).
	case crossProcess = "cross-process"
}

/// What each `GraphFuzzerPhase` of a long run cost: the seconds batches spent in it, and the CPU seconds of the
/// processes it ran.
///
/// The processes' CPU time is exact: `runProcess` reaps each process with `wait4`, which reports the CPU time it and
/// the processes it waited for used, and adds it to the phase of the task that ran it (`current`). The tool runs in
/// the test process, whose concurrent batches share one CPU clock, so a phase's in-process cost is reported as the
/// seconds batches spent in it, summed over batches; the test process's CPU time is reported as a whole.
actor GraphFuzzerPhaseAccount {
	/// The account a task's processes are added to, and the phase the task is in, if any.
	struct Context: Sendable {
		let account: GraphFuzzerPhaseAccount
		let phase: GraphFuzzerPhase?
	}

	/// The account and phase of the running task; `nil` outside a long run, which then accounts for nothing.
	@TaskLocal static var current: Context?

	/// Runs `body` in `phase`, adding the time it takes to the phase, and taking it from the phase it runs inside, so
	/// that each second is counted once, in the innermost phase.
	static func measuring<Result>(_ phase: GraphFuzzerPhase, _ body: () async throws -> Result) async rethrows -> Result {
		guard let context = current else {
			return try await body()
		}
		let startNanoseconds = DispatchTime.now().uptimeNanoseconds
		let result = try await $current.withValue(Context(account: context.account, phase: phase)) {
			try await body()
		}
		await context.account.addBusySeconds(Double(DispatchTime.now().uptimeNanoseconds - startNanoseconds) / 1e9, to: phase, takingFrom: context.phase)
		return result
	}

	/// Adds a process's CPU time to the phase of the running task.
	static func recordProcess(cpuSeconds: Double) async {
		guard let context = current, let phase = context.phase else { return }
		await context.account.addProcess(cpuSeconds: cpuSeconds, to: phase)
	}

	/// The user and system CPU seconds the test process has used.
	static func processCPUSeconds() -> Double {
		var usage = rusage()
		#if canImport(Glibc)
			// Glibc's `RUSAGE_SELF` is imported as a case of an enumeration that its `getrusage` does not take.
			getrusage(__rusage_who_t(truncatingIfNeeded: RUSAGE_SELF.rawValue), &usage)
		#else
			getrusage(RUSAGE_SELF, &usage)
		#endif
		return seconds(of: usage)
	}

	/// The user and system CPU seconds the test process's reaped child processes have used.
	static func childProcessCPUSeconds() -> Double {
		var usage = rusage()
		#if canImport(Glibc)
			// `RUSAGE_CHILDREN` is -1, which an unsigned raw value holds as its bit pattern.
			getrusage(__rusage_who_t(truncatingIfNeeded: RUSAGE_CHILDREN.rawValue), &usage)
		#else
			getrusage(RUSAGE_CHILDREN, &usage)
		#endif
		return seconds(of: usage)
	}

	private(set) var busySeconds = [GraphFuzzerPhase: Double]()
	private(set) var processCPUSeconds = [GraphFuzzerPhase: Double]()
	private(set) var processCounts = [GraphFuzzerPhase: Int]()

	/// Each phase as `<phase>=<busy seconds>:<process CPU seconds>:<processes>`, comma-separated, in declaration order.
	var reportField: String {
		GraphFuzzerPhase.allCases.map { phase in
			"\(phase.rawValue)=\(Self.formatted(busySeconds[phase, default: 0])):\(Self.formatted(processCPUSeconds[phase, default: 0])):\(processCounts[phase, default: 0])"
		}.joined(separator: ",")
	}

	static func formatted(_ seconds: Double) -> String {
		String(format: "%.1f", seconds)
	}

	private func addBusySeconds(_ seconds: Double, to phase: GraphFuzzerPhase, takingFrom enclosingPhase: GraphFuzzerPhase?) {
		busySeconds[phase, default: 0] += seconds
		if let enclosingPhase {
			busySeconds[enclosingPhase, default: 0] -= seconds
		}
	}

	private func addProcess(cpuSeconds: Double, to phase: GraphFuzzerPhase) {
		processCPUSeconds[phase, default: 0] += cpuSeconds
		processCounts[phase, default: 0] += 1
	}

	private static func seconds(of usage: rusage) -> Double {
		var seconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
		seconds += Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
		return seconds
	}
}
