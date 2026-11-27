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
/// refusal's kind, the count of differences, every refusal the world holds, and `mock` for a mock's root. Where
/// `SAFEDI_NODE_RECORDS_LAY_OUT` is `1`, every production root node records accept is laid out from them, and where
/// `SAFEDI_NODE_RECORDS_LAY_OUT_MOCKS` is `1`, every internal mock root: a sweep's switches, under which a test that
/// compares a file with a function fails on the other text, and what is read is what does not compile.
enum NodeRecordsChecks {
	/// Whether a run lays out from node records every production root they accept: a test said so, or the sweep's switch
	/// did. A run started outside `checking(_:)`, as the run over split module info files is, reads it too, so that it
	/// generates in the mode of the run it is compared with.
	static var laysOutRoots: Bool {
		NodeRecordsObservation.laysOutRoots || ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_LAY_OUT"] == "1"
	}

	/// Whether a run lays out from node records every internal mock root they accept, as `laysOutRoots` says of
	/// production roots.
	static var laysOutMockRoots: Bool {
		NodeRecordsObservation.laysOutMockRoots || ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_LAY_OUT_MOCKS"] == "1"
	}

	static func checking<Result>(_ body: () async throws -> Result) async rethrows -> Result {
		let reportPath = ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_REPORT"]
		let testName = Test.current?.name ?? "unknown test"
		let laysOutRoots = laysOutRoots
		let laysOutMockRoots = laysOutMockRoots
		let enclosingObserver = NodeRecordsObservation.observer
		let enclosingSeamCallObserver = SeamCallRecordObservation.observer
		// A seam call's record, as the engine is to spell it, must list what its text reads, binds and declares, and spell
		// the text's guard line and builder arguments.
		let seamCallObserver: @Sendable (SeamCallRecordObservation) -> Void = { call in
			if let boundNames = call.boundNames {
				for mismatch in HoleSiteRecordObservation.recordMismatches(text: call.text, readNames: call.readNames, boundNames: boundNames, place: "a seam call") {
					Issue.record(Comment(rawValue: mismatch))
				}
			}
			for (spelled, written) in zip(call.spelledFromRecord, call.written) where spelled != written {
				Issue.record(Comment(rawValue: "The record of a seam call spells `\(spelled)` where its text writes `\(written)`:\n\(call.text)"))
			}
			if call.spelledFromRecord.count != call.written.count {
				Issue.record(Comment(rawValue: "The record of a seam call spells \(call.spelledFromRecord.count) statements and arguments where its text writes \(call.written.count):\n\(call.text)"))
			}
			enclosingSeamCallObserver?(call)
		}
		let enclosingDispatcherObserver = DispatcherRecordObservation.observer
		// A dispatcher's declaration, spelled from the call's records alone, must be the text the tree writes.
		let dispatcherObserver: @Sendable (DispatcherRecordObservation) -> Void = { dispatcher in
			if dispatcher.spelledFromRecord != dispatcher.text {
				Issue.record(Comment(rawValue: "The records of a dispatcher spell\n\(dispatcher.spelledFromRecord)\nwhere the tree writes\n\(dispatcher.text)"))
			}
			enclosingDispatcherObserver?(dispatcher)
		}
		let enclosingFillObserver = FillSignatureObservation.observer
		// A fill's function, up to its tree, spelled from the fill's record alone, must be the text the tree writes.
		let fillObserver: @Sendable (FillSignatureObservation) -> Void = { fill in
			if fill.spelledFromRecord != fill.written {
				Issue.record(Comment(rawValue: "The record of a fill spells\n\(fill.spelledFromRecord.joined(separator: "\n"))\nwhere the tree writes\n\(fill.written.joined(separator: "\n"))"))
			}
			enclosingFillObserver?(fill)
		}
		return try await SeamCallRecordObservation.$observer.withValue(seamCallObserver) {
			try await DispatcherRecordObservation.$observer.withValue(dispatcherObserver) {
				try await FillSignatureObservation.$observer.withValue(fillObserver) {
					try await checkingNodeRecords(laysOutRoots: laysOutRoots, laysOutMockRoots: laysOutMockRoots, reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
				}
			}
		}
	}

	private static func checkingNodeRecords<Result>(laysOutRoots: Bool, laysOutMockRoots: Bool, reportPath: String?, testName: String, enclosingObserver: (@Sendable (NodeRecordsReport) -> Void)?, _ body: () async throws -> Result) async rethrows -> Result {
		try await NodeRecordsObservation.$laysOutRoots.withValue(laysOutRoots) {
			try await NodeRecordsObservation.$laysOutMockRoots.withValue(laysOutMockRoots) {
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
