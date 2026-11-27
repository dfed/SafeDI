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
import Synchronization
import Testing

/// Soundness rule 1 of node records: at every place of every production root they accept, node records' record of the
/// place's node equals the record the tree's place made (`NodeRecordsObservation`). Where `SAFEDI_NODE_RECORDS_REPORT`
/// names a file, each root's outcome is appended to it as a line: the test, the root, `laid out`, `accepted`, or the
/// refusal's kind, the count of differences, every refusal the world holds, and `mock` for a mock's root. Where `SAFEDI_NODE_RECORDS_LAY_OUT` is `1`, every root node records accept is laid out from them.
enum NodeRecordsChecks {
	static func checking<Result>(_ body: () async throws -> Result) async rethrows -> Result {
		let reportPath = ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_REPORT"]
		let testName = Test.current?.name ?? "unknown test"
		let laysOutRoots = NodeRecordsObservation.laysOutRoots || ProcessInfo.processInfo.environment["SAFEDI_NODE_RECORDS_LAY_OUT"] == "1"
		let enclosingObserver = NodeRecordsObservation.observer
		let enclosingSeamCallObserver = SeamCallRecordObservation.observer
		// What the tree writes of each filled call's functions and closure arguments, and what node records spell of them,
		// compared once the body has run.
		let filledCalls = FilledCallTexts()
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
			filledCalls.addTree(call.written)
			if call.spelledFromRecord.count != call.written.count {
				Issue.record(Comment(rawValue: "The record of a seam call spells \(call.spelledFromRecord.count) statements and arguments where its text writes \(call.written.count):\n\(call.text)"))
			}
			enclosingSeamCallObserver?(call)
		}
		let enclosingDispatcherObserver = DispatcherRecordObservation.observer
		// A dispatcher's declaration, spelled from the call's records alone, must be the text the tree writes.
		let dispatcherObserver: @Sendable (DispatcherRecordObservation) -> Void = { dispatcher in
			filledCalls.addTree([FilledCallTexts.normalized(dispatcher.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))])
			if dispatcher.spelledFromRecord != dispatcher.text {
				Issue.record(Comment(rawValue: "The records of a dispatcher spell\n\(dispatcher.spelledFromRecord)\nwhere the tree writes\n\(dispatcher.text)"))
			}
			enclosingDispatcherObserver?(dispatcher)
		}
		let enclosingFillObserver = FillSignatureObservation.observer
		// A fill's function, up to its tree, spelled from the fill's record alone, must be the text the tree writes.
		let fillObserver: @Sendable (FillSignatureObservation) -> Void = { fill in
			filledCalls.addTree([FilledCallTexts.normalized(fill.written)])
			if fill.spelledFromRecord != fill.written {
				Issue.record(Comment(rawValue: "The record of a fill spells\n\(fill.spelledFromRecord.joined(separator: "\n"))\nwhere the tree writes\n\(fill.written.joined(separator: "\n"))"))
			}
			if fill.scopeParameterNameFromRecord != fill.writtenScopeParameterName {
				Issue.record(Comment(rawValue: "A fill’s record names its scope parameter `\(fill.scopeParameterNameFromRecord)` where the tree names it `\(fill.writtenScopeParameterName)`:\n\(fill.written.joined(separator: "\n"))"))
			}
			enclosingFillObserver?(fill)
		}
		let enclosingDecisionsObserver = FillEmissionDecisionsObservation.observer
		// A root's seam call decides which of its fills and dispatchers are `@Sendable`, held in place, or root functions from
		// their records alone as the tree decides them.
		let decisionsObserver: @Sendable (FillEmissionDecisionsObservation) -> Void = { decisions in
			if let decisionsReportPath = ProcessInfo.processInfo.environment["SAFEDI_FILL_DECISIONS_REPORT"] {
				append("\(testName)\t\(decisions.fromRecords == decisions.tree ? "agree" : "differ")\t\(decisions.tree.replacingOccurrences(of: "\n", with: " | "))\n", toFileAt: decisionsReportPath)
			}
			if decisions.fromRecords != decisions.tree {
				Issue.record(Comment(rawValue: "The records of a seam call's fills and dispatchers decide\n\(decisions.fromRecords)\nwhere the tree decides\n\(decisions.tree)"))
			}
			enclosingDecisionsObserver?(decisions)
		}
		let enclosingFillFactsObserver = FillFactsObservation.observer
		// Each fill of a root's seam call no fill encloses binds, takes and reads, as node records make its facts from the
		// world, what the tree builds it with.
		let fillFactsObserver: @Sendable (FillFactsObservation) -> Void = { facts in
			if let fillFactsReportPath = ProcessInfo.processInfo.environment["SAFEDI_FILL_FACTS_REPORT"] {
				let agreeing = facts.fromRecords.filter { facts.tree[$0.key] == $0.value }.count
				append("\(testName)\t\(facts.root)\t\(agreeing)/\(facts.fromRecords.count)\t\(facts.refusals.joined(separator: ","))\n", toFileAt: fillFactsReportPath)
			}
			for (key, projection) in facts.fromRecords.sorted(by: { $0.key < $1.key }) where facts.tree[key] != projection {
				Issue.record(Comment(rawValue: "Root \(facts.root)’s fill \(key) has the facts\n\(projection)\nfrom node records where the tree builds it with\n\(facts.tree[key] ?? "no fill")"))
			}
			if facts.refusals.isEmpty {
				for key in facts.tree.keys.sorted() where facts.fromRecords[key] == nil {
					Issue.record(Comment(rawValue: "Root \(facts.root)’s fill \(key) has no facts from node records"))
				}
			}
			enclosingFillFactsObserver?(facts)
		}
		let enclosingNamesObserver = FillNamesObservation.observer
		// A call's names for its fills' and dispatchers' functions, made from its records alone, must be the names it claims.
		let namesObserver: @Sendable (FillNamesObservation) -> Void = { names in
			if names.fromRecords != names.claimed {
				Issue.record(Comment(rawValue: "A call’s records name its fills and dispatchers \(names.fromRecords) where the call claims \(names.claimed)"))
			}
			enclosingNamesObserver?(names)
		}
		let enclosingFilledCallObserver = FilledCallRecordsObservation.observer
		let filledCallObserver: @Sendable (FilledCallRecordsObservation) -> Void = { records in
			filledCalls.addRecords(records)
			enclosingFilledCallObserver?(records)
		}
		let result = try await FilledCallRecordsObservation.$observer.withValue(filledCallObserver) {
			try await checkingFills(seamCallObserver: seamCallObserver, dispatcherObserver: dispatcherObserver, fillObserver: fillObserver, decisionsObserver: decisionsObserver, fillFactsObserver: fillFactsObserver, namesObserver: namesObserver) {
				try await checkingNodeRecords(laysOutRoots: laysOutRoots, reportPath: reportPath, testName: testName, enclosingObserver: enclosingObserver, body)
			}
		}
		// Each function and closure argument node records spell of a root's filled call is one the tree writes.
		for mismatch in filledCalls.mismatches() {
			Issue.record(Comment(rawValue: mismatch))
		}
		if let filledCallsReportPath = ProcessInfo.processInfo.environment["SAFEDI_FILLED_CALLS_REPORT"] {
			append("\(testName)\t\(filledCalls.summary)\n", toFileAt: filledCallsReportPath)
		}
		return result
	}

	private static func checkingFills<Result>(
		seamCallObserver: @escaping @Sendable (SeamCallRecordObservation) -> Void,
		dispatcherObserver: @escaping @Sendable (DispatcherRecordObservation) -> Void,
		fillObserver: @escaping @Sendable (FillSignatureObservation) -> Void,
		decisionsObserver: @escaping @Sendable (FillEmissionDecisionsObservation) -> Void,
		fillFactsObserver: @escaping @Sendable (FillFactsObservation) -> Void,
		namesObserver: @escaping @Sendable (FillNamesObservation) -> Void,
		_ body: () async throws -> Result,
	) async rethrows -> Result {
		try await FillFactsObservation.$observer.withValue(fillFactsObserver) {
			try await SeamCallRecordObservation.$observer.withValue(seamCallObserver) {
				try await DispatcherRecordObservation.$observer.withValue(dispatcherObserver) {
					try await FillSignatureObservation.$observer.withValue(fillObserver) {
						try await FillEmissionDecisionsObservation.$observer.withValue(decisionsObserver) {
							try await FillNamesObservation.$observer.withValue(namesObserver) {
								try await body()
							}
						}
					}
				}
			}
		}
	}

	private static func checkingNodeRecords<Result>(laysOutRoots: Bool, reportPath: String?, testName: String, enclosingObserver: (@Sendable (NodeRecordsReport) -> Void)?, _ body: () async throws -> Result) async rethrows -> Result {
		try await NodeRecordsObservation.$laysOutRoots.withValue(laysOutRoots) {
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

/// What the tree writes of a test's filled seam calls, and what node records spell of them (`FilledCallRecordsObservation`),
/// each function as its lines with no indentation, joined.
private final class FilledCallTexts: Sendable {
	private struct State {
		var tree = Set<String>()
		var records = [(root: String, text: String)]()
	}

	private let state = Mutex(State())

	static func normalized(_ lines: [String]) -> String {
		lines.map { String($0.drop { $0 == " " || $0 == "\t" }) }.joined(separator: "\n")
	}

	func addTree(_ texts: [String]) {
		state.withLock { $0.tree.formUnion(texts) }
	}

	func addRecords(_ records: FilledCallRecordsObservation) {
		state.withLock { state in
			for (_, lines) in records.functions.sorted(by: { $0.key < $1.key }) {
				state.records.append((records.root, Self.normalized(lines)))
			}
			for argument in records.closureArguments {
				state.records.append((records.root, argument))
			}
		}
	}

	func mismatches() -> [String] {
		state.withLock { state in
			state.records.filter { !state.tree.contains($0.text) }.map { "Root \($0.root)’s filled call spells, from node records,\n\($0.text)\nwhich the tree writes nowhere" }
		}
	}

	var summary: String {
		state.withLock { state in
			"\(state.records.filter { state.tree.contains($0.text) }.count)/\(state.records.count)"
		}
	}
}
