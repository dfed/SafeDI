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
import SafeDICore
import Testing

/// The oracle of the seam callers' view: every run that computes the seams it generates over the declarations their
/// callers see (`SeamCallersViewObservation.comparesProducers`) computes that view once more, under the producer the
/// test selects, and the two must decide alike for each seam: whether the callers can compute it, the signature they
/// compute, encoded to the same bytes, and the error reported at the seam, with the declaration it names and its text.
enum SeamCallersViewChecks {
	/// Runs `operation` while observing every callers' view a run computes, handing each to `enclosingObserver` too, then
	/// records an issue for each whose computation again decides otherwise, also where `operation` throws, as a run does
	/// that reports the callers' view's error at a seam: the view was computed before the error was thrown.
	static func comparing<Result>(handingOn enclosingObserver: TaskLocalFunction<@Sendable (SeamCallersView) -> Void>?, _ operation: () async throws -> Result) async throws -> Result {
		let (views, continuation) = AsyncStream.makeStream(of: SeamCallersView.self)
		let result: Swift.Result<Result, any Error>
		do {
			result = try await .success(SeamCallersViewObservation.$comparesProducers.withValue(TaskLocalFunction { view in
				continuation.yield(view)
				enclosingObserver?(view)
			}) {
				try await operation()
			})
		} catch {
			result = .failure(error)
		}
		continuation.finish()
		for await view in views {
			let recomputed: [SeamCallersVerdict]
			do {
				recomputed = try await view.recomputed()
			} catch {
				Issue.record(Comment(rawValue: "The callers’ view of module \(view.moduleName ?? "(unnamed)") threw when computed again: \(error)"))
				continue
			}
			if let difference = difference(between: view.verdicts, and: recomputed) {
				Issue.record(Comment(rawValue: "The callers’ view of module \(view.moduleName ?? "(unnamed)") decided otherwise when computed again:\n\(difference)"))
			}
		}
		return try result.get()
	}

	/// Set only by the test that shows this oracle fires after a run that throws: the verdicts computed again lose their
	/// diagnostics, so a seam whose error the run reports is decided otherwise.
	@TaskLocal static var dropsRecomputedDiagnostics = false

	/// What `recomputed` decides otherwise than `verdicts`, one line per seam, or `nil` when the two decide alike.
	static func difference(between verdicts: [SeamCallersVerdict], and recomputed: [SeamCallersVerdict]) -> String? {
		let seams = verdicts.map(\.seamType.asSource)
		let recomputedSeams = recomputed.map(\.seamType.asSource)
		guard seams == recomputedSeams else {
			return "seams: \(seams) against \(recomputedSeams)"
		}
		var lines = [String]()
		for (verdict, other) in zip(verdicts, recomputed) {
			let seam = verdict.seamType.asSource
			if verdict.callersFailed != other.callersFailed {
				lines.append("\(seam): callers fail \(verdict.callersFailed) against \(other.callersFailed)")
			}
			let signature = encoded(verdict.callersSignature)
			let otherSignature = encoded(other.callersSignature)
			if signature != otherSignature {
				lines.append("\(seam): callers’ signature\n  \(signature)\nagainst\n  \(otherSignature)")
			}
			let otherDiagnostics = dropsRecomputedDiagnostics ? [] : other.diagnostics
			if verdict.diagnostics != otherDiagnostics {
				lines.append("\(seam): reported\n  \(verdict.diagnostics.map(\.formatted))\nagainst\n  \(otherDiagnostics.map(\.formatted))")
			}
		}
		return lines.isEmpty ? nil : lines.joined(separator: "\n")
	}

	private static func encoded(_ signature: StoredSeamSignature) -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		// A signature encodes whatever it holds; an encoding failure is itself a difference worth seeing.
		guard let data = try? encoder.encode(signature) else { return "(unencodable)" }
		return String(decoding: data, as: UTF8.self)
	}
}
