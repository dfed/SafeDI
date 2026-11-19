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
import SafeDICore

/// The time, CPU and peak memory of each span of a `generate` run, written to the file the environment variable
/// `SAFEDI_PHASE_TIMES_OUTPUT` names: one line per span, `<name>\t<wall seconds>\t<CPU seconds>\t<peak RSS bytes>`,
/// written as the span ends. An environment variable rather than an option, for measuring the generator; nothing
/// appears in help.
///
/// The process's CPU over a span is that span's alone only when no task outlives the span that started it, which does
/// not hold yet: a production generator starts its code on a detached task when it is created, and a mock root's
/// parameter tree runs on an unstructured task its first reader starts. Wall per span is exact.
enum PhaseTimes {
	/// The environment variable that names the file.
	static let outputVariableName = "SAFEDI_PHASE_TIMES_OUTPUT"

	/// Runs `operation`, recording its spans to the file `environment` names, if any. The file is opened once, for
	/// appending, and closed when `operation` returns or throws. Each line is one `write` call, so lines several
	/// processes write to one file never interleave. When the file cannot be opened, nothing is recorded and
	/// `operation` runs as it would without the variable.
	static func recording<Result>(
		environment: [String: String],
		_ operation: () async throws -> Result,
	) async throws -> Result {
		guard let path = environment[outputVariableName], !path.isEmpty else {
			return try await operation()
		}
		let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard descriptor >= 0 else {
			return try await operation()
		}
		defer { close(descriptor) }
		return try await GenerationPhaseObservation.$observer.withValue(observer(writingTo: descriptor)) {
			try await operation()
		}
	}

	// MARK: Private

	/// The observer that writes each span's line to `descriptor`. It reads the clocks as a span starts, and the closure
	/// it returns holds those readings as values, so no reading is state that tasks share.
	private static func observer(writingTo descriptor: Int32) -> @Sendable ([GenerationPhase]) -> @Sendable () -> Void {
		{ phases in
			let start = Reading()
			return {
				let end = Reading()
				let name = GenerationPhase.allCases.filter(phases.contains).map(\.rawValue).joined(separator: " + ")
				let line = "\(name)\t\(seconds(end.wallSeconds - start.wallSeconds))\t\(seconds(end.processorSeconds - start.processorSeconds))\t\(end.peakResidentBytes)\n"
				let bytes = Array(line.utf8)
				_ = bytes.withUnsafeBytes { buffer in
					write(descriptor, buffer.baseAddress, buffer.count)
				}
			}
		}
	}

	/// `value` with six decimal places.
	private static func seconds(_ value: Double) -> String {
		String(format: "%.6f", value)
	}

	/// The clocks, read once.
	private struct Reading {
		init() {
			var time = timespec()
			clock_gettime(CLOCK_MONOTONIC, &time)
			wallSeconds = Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
			var usage = rusage()
			getrusage(PhaseTimes.thisProcess, &usage)
			processorSeconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
				+ Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
			#if canImport(Darwin)
				// Darwin reports the peak resident size in bytes.
				peakResidentBytes = Int(usage.ru_maxrss)
			#else
				// Linux reports it in kilobytes.
				peakResidentBytes = Int(usage.ru_maxrss) * 1_024
			#endif
		}

		/// The monotonic clock, in seconds.
		let wallSeconds: Double
		/// The process's user and system time so far, in seconds.
		let processorSeconds: Double
		/// The process's peak resident size so far, in bytes.
		let peakResidentBytes: Int
	}

	#if canImport(Glibc)
		/// Glibc imports `RUSAGE_SELF` as a case of the enumeration `__rusage_who`, which `getrusage` takes as
		/// `__rusage_who_t`: an alias of the enumeration or of `Int32`, depending on the headers' mode.
		private static let thisProcess = __rusage_who_t(RUSAGE_SELF.rawValue)
	#else
		private static let thisProcess = RUSAGE_SELF
	#endif
}
