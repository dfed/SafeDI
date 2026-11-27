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
/// place's node equals the record the tree's place made (`NodeRecordsObservation`); and every mock world built from the
/// mock worlds' table holds the records it builds without it (`MockWorldsTableReport.differences`). Where `SAFEDI_NODE_RECORDS_REPORT`
/// names a file, each root's outcome is appended to it as a line: the test, the root, `laid out`, `accepted`, or the
/// refusal's kind, the count of differences, every refusal the world holds, and `mock` for a mock's root. Where `SAFEDI_NODE_RECORDS_LAY_OUT` is `1`, every root node records accept is laid out from them.
enum NodeRecordsChecks {
	/// Whether `executeSafeDIToolTest` observes node records, which builds every mock root's world. Off only where a test
	/// shows what a run that no test observes builds.
	@TaskLocal static var observesNodeRecords = true

	static func checking<Result>(_ body: () async throws -> Result) async rethrows -> Result {
		let reportPath = ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_REPORT"]
		let testName = Test.current?.name ?? "unknown test"
		let laysOutRoots = NodeRecordsObservation.laysOutRoots || ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_LAY_OUT"] == "1"
		let enclosingObserver = NodeRecordsObservation.observer
		let enclosingSeamCallObserver = SeamCallRecordObservation.observer
		// A seam call's record, as the engine is to spell it, must list what its text reads, binds and declares, and spell
		// the text's guard line and builder arguments.
		let seamCallObserver: @Sendable (SeamCallRecordObservation) -> Void = { call in
			for mismatch in HoleSiteRecordObservation.recordMismatches(text: call.text, readNames: call.readNames, boundNames: call.boundNames, place: "a seam call") {
				Issue.record(Comment(rawValue: mismatch))
			}
			for (spelled, written) in zip(call.spelledFromRecord, call.written) where spelled != written {
				Issue.record(Comment(rawValue: "The record of a seam call spells `\(spelled)` where its text writes `\(written)`:\n\(call.text)"))
			}
			if call.spelledFromRecord.count != call.written.count {
				Issue.record(Comment(rawValue: "The record of a seam call spells \(call.spelledFromRecord.count) statements and arguments where its text writes \(call.written.count):\n\(call.text)"))
			}
			enclosingSeamCallObserver?(call)
		}
		return try await SeamCallRecordObservation.$observer.withValue(seamCallObserver) {
			try await checkingNodeRecords(laysOutRoots: laysOutRoots, reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
		}
	}

	private static func checkingNodeRecords<Result>(laysOutRoots: Bool, reportPath: String?, testName: String, enclosingObserver: (@Sendable (NodeRecordsReport) -> Void)?, _ body: () async throws -> Result) async rethrows -> Result {
		guard observesNodeRecords else {
			return try await NodeRecordsObservation.$observer.withValue(nil) {
				try await body()
			}
		}
		// Every mock world built from the mock worlds' table must hold, field for field, the records it builds without it.
		let enclosingTableObserver = MockWorldsTableObservation.observer
		let tableObserver: @Sendable (MockWorldsTableReport) -> Void = { report in
			for difference in report.differences {
				Issue.record(Comment(rawValue: "A mock world’s records built from the mock worlds’ table differ from those it builds without it: \(difference)"))
			}
			enclosingTableObserver?(report)
		}
		return try await NodeRecordsObservation.$laysOutRoots.withValue(laysOutRoots) {
			try await MockWorldsTableObservation.$observer.withValue(tableObserver) {
				try await checkingNodeRecordsOfRoots(reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
			}
		}
	}

	private static func checkingNodeRecordsOfRoots<Result>(reportPath: String?, testName: String, enclosingObserver: (@Sendable (NodeRecordsReport) -> Void)?, _ body: () async throws -> Result) async rethrows -> Result {
		try await NodeRecordsObservation.$observer.withValue({ report in
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
