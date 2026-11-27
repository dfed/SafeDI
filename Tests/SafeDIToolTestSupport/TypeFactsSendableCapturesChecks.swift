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

/// The oracle of the capture fold: the captures of each root the fold reads (`TypeFactsSendableCaptures`) must equal, as
/// sets of what an error reports but for its chain and builder, those the walk of the root's generator tree finds
/// (`TypeFactsSendableCapturesObservation.comparesWalk`), on every test graph. A root the fold refuses is read by the walk
/// and compared with nothing. Where `SAFEDI_SENDABLE_CAPTURES_REPORT` names a file, each root's outcome is appended to it
/// as a line, as node records report theirs: the test, the root, `folded` or the first refusal, whether the two differ,
/// and every refusal.
enum TypeFactsSendableCapturesChecks {
	/// Runs `operation` while comparing the captures of every root it validates, handing each comparison to
	/// `enclosingObserver` too, and records an issue for each root whose fold and walk differ.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (TypeFactsSendableCapturesComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: TypeFactsSendableCapturesComparison.self)
		let result: Result
		do {
			result = try await TypeFactsSendableCapturesObservation.$comparesWalk.withValue({ comparison in
				continuation.yield(comparison)
				enclosingObserver?(comparison)
			}) {
				try await operation()
			}
		} catch {
			continuation.finish()
			await recordDifferences(in: comparisons)
			throw error
		}
		continuation.finish()
		await recordDifferences(in: comparisons)
		return result
	}

	private static func recordDifferences(in comparisons: AsyncStream<TypeFactsSendableCapturesComparison>) async {
		let reportPath = ProcessInfo.processInfo.environment["SAFEDI_SENDABLE_CAPTURES_REPORT"]
		let testName = Test.current?.name ?? "unknown test"
		for await comparison in comparisons {
			let folded = Set(comparison.folded)
			let walked = Set(comparison.walked)
			let differs = comparison.refusals.isEmpty && folded != walked
			if let reportPath {
				append("\(testName)\t\(comparison.root)\t\(comparison.refusals.first ?? "folded")\t\(differs ? "differs" : "equal")\t\(comparison.refusals.joined(separator: ","))\n", toFileAt: reportPath)
			}
			guard differs else { continue }
			Issue.record(Comment(rawValue: """
			The capture fold of \(comparison.root) differs from the walk of its generator tree:
			only folded: \(folded.subtracting(walked).sorted())
			only walked: \(walked.subtracting(folded).sorted())
			"""))
		}
	}

	private static func append(_ line: String, toFileAt path: String) {
		if !FileManager.default.fileExists(atPath: path) {
			_ = FileManager.default.createFile(atPath: path, contents: nil)
		}
		guard let handle = FileHandle(forWritingAtPath: path) else { return }
		defer { try? handle.close() }
		_ = try? handle.seekToEnd()
		try? handle.write(contentsOf: Data(line.utf8))
	}
}
