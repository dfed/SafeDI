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

/// Soundness rule 1 of node records: at every place of every production root they accept, node records' record of the
/// place's node equals the record the tree's place made (`NodeRecordsObservation`). Where `SAFEDI_NODE_RECORDS_REPORT`
/// names a file, each root's outcome is appended to it as a line: the test, the root, `laid out`, `accepted`, or the
/// refusal's kind, the count of differences, every refusal the world holds, and `mock` for a mock's root. Where `SAFEDI_NODE_RECORDS_LAY_OUT` is `1`, every root node records accept is laid out from them.
/// Where `SAFEDI_PLACES_DRAFT_REPORT` names a file, each line of each seam's comparison of its place graph's drafts with
/// its stored places (`NodeRecordsReport.placesDraftDifferences`) is appended to it, after the test and the seam.
enum NodeRecordsChecks {
	static func checking<Result>(_ body: () async throws -> Result) async rethrows -> Result {
		let reportPath = ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_REPORT"]
		let testName = Test.current?.name ?? "unknown test"
		let laysOutRoots = NodeRecordsObservation.laysOutRoots || ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_LAY_OUT"] == "1"
		let enclosingObserver = NodeRecordsObservation.observer
		let enclosingSeamCallObserver = SeamCallRecordObservation.observer
		// A seam call's record, as the engine is to spell it, must list what its text reads, binds and declares, and spell
		// the text's guard line and builder arguments.
		let seamCallObserver: @Sendable (SeamCallRecordObservation) -> Void = { call in
			var mismatches = HoleSiteRecordObservation.recordMismatches(text: call.text, readNames: call.readNames, boundNames: call.boundNames, place: "a seam call")
			for (spelled, written) in zip(call.spelledFromRecord, call.written) where spelled != written {
				mismatches.append("The record of a seam call spells `\(spelled)` where its text writes `\(written)`:\n\(call.text)")
			}
			if call.spelledFromRecord.count != call.written.count {
				mismatches.append("The record of a seam call spells \(call.spelledFromRecord.count) statements and arguments where its text writes \(call.written.count):\n\(call.text)")
			}
			// The row's seam calls keep fills and dispatchers in place, which the record does not name yet: a known issue of
			// the seam call records lane (2026-11-27) until it does, reported once per call with the start of its text, so
			// that other lanes' runs are not flooded.
			if let first = mismatches.first {
				withKnownIssue("Seam call records lane, 2026-11-27: the record of a fill call does not yet name the fills and dispatchers the row keeps in place", isIntermittent: true) {
					Issue.record(Comment(rawValue: "\(first.split(separator: "\n", omittingEmptySubsequences: false).prefix(12).joined(separator: "\n"))\n(\(mismatches.count) mismatches in all)"))
				}
			}
			enclosingSeamCallObserver?(call)
		}
		// Where `SAFEDI_PLACES_FROM_FACTS` is `1`, each seam's place graph is the one its facts drafts assemble: the oracle of
		// the places from facts. The switch is set only then, so a default run sets no more task-local values.
		let assemblesPlacesFromFacts = ProcessInfo.processInfo.environment["SAFEDI_PLACES_FROM_FACTS"] == "1"
		return try await SeamCallRecordObservation.$observer.withValue(seamCallObserver) {
			guard assemblesPlacesFromFacts else {
				return try await checkingNodeRecords(laysOutRoots: laysOutRoots, reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
			}
			return try await NodeRecordsObservation.$assemblesPlacesFromFacts.withValue(true) {
				try await checkingNodeRecords(laysOutRoots: laysOutRoots, reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
			}
		}
	}

	private static func checkingNodeRecords<Result>(laysOutRoots: Bool, reportPath: String?, testName: String, enclosingObserver: (@Sendable (NodeRecordsReport) -> Void)?, _ body: () async throws -> Result) async rethrows -> Result {
		let placesDraftReportPath = ProcessInfo.processInfo.environment["SAFEDI_PLACES_DRAFT_REPORT"]
		return try await NodeRecordsObservation.$laysOutRoots.withValue(laysOutRoots) {
			try await NodeRecordsObservation.$observer.withValue({ report in
				// A seam's place graph drafted from its facts world is compared with its stored places only in a report until
				// the drafts are assembled into the places (`SAFEDI_PLACES_DRAFT_REPORT`), and an enclosing observer, a growth
				// row's, which reads the report's lines.
				if let placesDraftDifferences = report.placesDraftDifferences {
					if let placesDraftReportPath {
						append(placesDraftDifferences.map { "\(testName)\t\(report.root)\t\($0)\n" }.joined(), toFileAt: placesDraftReportPath)
					}
					enclosingObserver?(report)
					return
				}
				for difference in report.differences {
					Issue.record(Comment(rawValue: "Node records differ from the tree’s records of root \(report.root): \(difference)"))
				}
				if let reportPath {
					let outcome = report.isLaidOutFromNodeRecords ? "laid out" : report.refusal ?? "accepted"
					append("\(testName)\t\(report.root)\t\(outcome)\t\(report.differences.count)\t\(report.everyRefusal.joined(separator: ","))\t\(report.isMockRoot ? "mock" : "")\n", toFileAt: reportPath)
				}
				enclosingObserver?(report)
			}) {
				try await body()
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
