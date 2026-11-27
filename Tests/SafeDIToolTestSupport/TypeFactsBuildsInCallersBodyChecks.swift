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

/// The oracle of the graph's answer of whether each edge builds its child in its parent's body
/// (`TypeFactsBuildsInCallersBody`): wherever the graph decides, its answer must equal the layout's, at every place a
/// root's plan records as built (`TypeFactsBuildsInCallersBodyObservation.comparesLayout`), in both directions: built in
/// the caller's body exactly where the place has no function of its own. Where `SAFEDI_BUILDS_IN_CALLERS_BODY_REPORT`
/// names a file, each root's counts are appended to it as a line: the test, the root, the places answered in the
/// caller's body, in a function of their own, owed, the places that differ, and those no edge maps.
enum TypeFactsBuildsInCallersBodyChecks {
	/// Runs `operation` while comparing the answers of every root it plans, handing each comparison to `enclosingObserver`
	/// too, and records an issue for each place whose answer and layout differ.
	static func comparing<Result>(handingOn enclosingObserver: (@Sendable (TypeFactsBuildsInCallersBodyComparison) -> Void)?, _ operation: () async throws -> Result) async throws -> Result {
		let (comparisons, continuation) = AsyncStream.makeStream(of: TypeFactsBuildsInCallersBodyComparison.self)
		let result: Result
		do {
			result = try await TypeFactsBuildsInCallersBodyObservation.$comparesLayout.withValue({ comparison in
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

	/// Whether `place`'s answer disagrees with its layout: an answer decided either way must match whether the place has a
	/// function of its own.
	static func differs(_ place: TypeFactsBuildsInCallersBodyComparison.Place) -> Bool {
		switch place.answer {
		case "inCallersBody":
			place.hasFunction
		case "inOwnFunction":
			!place.hasFunction
		default:
			false
		}
	}

	private static func recordDifferences(in comparisons: AsyncStream<TypeFactsBuildsInCallersBodyComparison>) async {
		let reportPath = ProcessInfo.processInfo.environment["SAFEDI_BUILDS_IN_CALLERS_BODY_REPORT"]
		let testName = Test.current?.name ?? "unknown test"
		for await comparison in comparisons {
			let differing = comparison.places.filter(differs)
			if let reportPath {
				let counts = ["inCallersBody", "inOwnFunction", "owed"].map { answer in comparison.places.count { $0.answer == answer } }
				append("\(testName)\t\(comparison.root)\t\(counts.map(String.init).joined(separator: "\t"))\t\(differing.count)\t\(comparison.unmatchedPlaceCount)\n", toFileAt: reportPath)
			}
			for place in differing {
				Issue.record(Comment(rawValue: "The graph answers \(place.answer) for \(place.declaration) in \(comparison.root), whose place the layout gives \(place.hasFunction ? "a function of its own" : "no function")."))
			}
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
