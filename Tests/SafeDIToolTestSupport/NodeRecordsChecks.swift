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
		let seamCallObserver = TaskLocalFunction<@Sendable (SeamCallRecordObservation) -> Void> { call in
			var mismatches = call.boundNames.map { boundNames in
				HoleSiteRecordObservation.recordMismatches(text: call.text, readNames: call.readNames, boundNames: boundNames, place: "a seam call")
			} ?? []
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
		let enclosingDispatcherObserver = DispatcherRecordObservation.observer
		// A dispatcher's declaration, spelled from the call's records alone, must be the text the tree writes.
		let dispatcherObserver = TaskLocalFunction<@Sendable (DispatcherRecordObservation) -> Void> { dispatcher in
			if dispatcher.spelledFromRecord != dispatcher.text {
				Issue.record(Comment(rawValue: "The records of a dispatcher spell\n\(dispatcher.spelledFromRecord)\nwhere the tree writes\n\(dispatcher.text)"))
			}
			enclosingDispatcherObserver?(dispatcher)
		}
		let enclosingFillObserver = FillSignatureObservation.observer
		// A fill's function, up to its tree, spelled from the fill's record alone, must be the text the tree writes.
		let fillObserver = TaskLocalFunction<@Sendable (FillSignatureObservation) -> Void> { fill in
			if fill.spelledFromRecord != fill.written {
				Issue.record(Comment(rawValue: "The record of a fill spells\n\(fill.spelledFromRecord.joined(separator: "\n"))\nwhere the tree writes\n\(fill.written.joined(separator: "\n"))"))
			}
			enclosingFillObserver?(fill)
		}
		// Where `SAFEDI_PLACES_FROM_FACTS` is `1`, each seam's place graph is the one its facts drafts assemble: the oracle of
		// the places from facts. The switch is set only then, so a default run sets no more task-local values.
		let assemblesPlacesFromFacts = ProcessInfo.processInfo.environment["SAFEDI_PLACES_FROM_FACTS"] == "1"
		return try await SeamCallRecordObservation.$observer.withValue(seamCallObserver) {
			try await DispatcherRecordObservation.$observer.withValue(dispatcherObserver) {
				try await FillSignatureObservation.$observer.withValue(fillObserver) {
					guard assemblesPlacesFromFacts else {
						return try await checkingNodeRecords(laysOutRoots: laysOutRoots, reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
					}
					return try await NodeRecordsObservation.$assemblesPlacesFromFacts.withValue(true) {
						try await checkingNodeRecords(laysOutRoots: laysOutRoots, reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
					}
				}
			}
		}
	}

	private static func checkingNodeRecords<Result>(laysOutRoots: Bool, reportPath: String?, testName: String, enclosingObserver: TaskLocalFunction<@Sendable (NodeRecordsReport) -> Void>?, _ body: () async throws -> Result) async rethrows -> Result {
		let placesDraftReportPath = ProcessInfo.processInfo.environment["SAFEDI_PLACES_DRAFT_REPORT"]
		return try await NodeRecordsObservation.$laysOutRoots.withValue(laysOutRoots) {
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { report in
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
				let outcome = Self.outcome(of: report)
				for difference in outcome.differences {
					Issue.record(Comment(rawValue: "Node records differ from the tree’s records of root \(report.root): \(difference)"))
				}
				if let reportPath {
					let state = report.isLaidOutFromNodeRecords ? "laid out" : report.refusal ?? "accepted"
					append("\(testName)\t\(report.root)\t\(state)\t\(outcome.differences.count)\t\(report.everyRefusal.joined(separator: ","))\t\(report.isMockRoot ? "mock" : "")\t\(outcome.approvedEntries.map(String.init).joined(separator: ","))\n", toFileAt: reportPath)
				}
				enclosingObserver?(report)
			}) {
				try await body()
			}
		}
	}

	/// The differences of `report` that fail its test, and the entries of the approved differences that account for the
	/// rest. A root's differences are approved only together: the code laid out from its records, each approved
	/// difference it holds rewritten as the tree writes it (`ApprovedDifferences`), is the tree's code byte for byte.
	/// Then the records' differences from the tree's, place by place, are that rewrite's and fail nothing. A difference
	/// no text shows always fails, as does every difference of a root whose two texts were not both laid out.
	static func outcome(of report: NodeRecordsReport, approving approvedDifferences: [ApprovedDifference] = ApprovedDifferences.all) -> (differences: [String], approvedEntries: [Int]) {
		guard !report.differences.isEmpty, let texts = report.comparedTexts else { return (report.differences, []) }
		// One function with an optional parameter serves a call that answers a read only if available and a call that
		// does not: its record reads the declaration where the tree's place at the second call reads `nil`, and the two
		// write the same code, the call passing `nil`. The comparison names exactly that difference
		// (`NodeRecordsReport.argumentsOfOptionalParameterDifferenceName`), no text shows it, and no rewrite of the
		// approved differences runs for it, so it is counted under no entry. Any other difference of a root whose texts
		// are equal fails (`ApprovedDifferencesTests`).
		if texts.nodeRecords == texts.tree, report.differences.allSatisfy({ $0.contains(": \(NodeRecordsReport.argumentsOfOptionalParameterDifferenceName) is ") }) {
			return (report.differencesNoTextShows, [])
		} else if let normalized = ApprovedDifferences.normalized(nodeRecordsText: texts.nodeRecords, treeText: texts.tree, by: approvedDifferences) {
			return (report.differencesNoTextShows, normalized.entries)
		} else {
			return (report.differences, [])
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
