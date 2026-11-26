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

/// The check before a seam's `SeamHoles` is answered by node and edge of the seam's graph rather than by path: every path
/// that ends on one node and edge must read the same answer. Runs only where `SAFEDI_SEAM_PATH_ANSWERS_DIR` names a
/// directory, into which it writes one report per run that reads any answer: a line of counts, then each node and edge
/// whose paths disagree, with every answer and the paths that read it.
enum SeamHolesPathAgreementChecks {
	/// A key of the widened answers: node, edge and the innermost enclosing fill, beside the column.
	struct Key: Hashable, Comparable, Sendable {
		let seamType: String
		let node: String
		let edge: String
		let fill: String
		let column: String

		static func < (lhs: Key, rhs: Key) -> Bool {
			(lhs.seamType, lhs.node, lhs.edge, lhs.fill, lhs.column) < (rhs.seamType, rhs.node, rhs.edge, rhs.fill, rhs.column)
		}
	}

	/// The answers each key read, each with its paths, the families it was read in and the outer fills around it.
	struct Answers: Sendable {
		var pathsByAnswerByKey = [Key: [String: Set<String>]]()
		var familiesByAnswerByKey = [Key: [String: Set<Bool>]]()
		var outerFillsByAnswerByKey = [Key: [String: Set<String>]]()
		/// The keys whose answers differ once the innermost fill leaves the key, for the count of the narrow key.
		var narrowKeys = [Key: Set<String>]()

		mutating func add(_ answer: SeamHolesPathAnswer) {
			let key = Key(seamType: answer.seamType, node: answer.node, edge: answer.edge, fill: answer.fill, column: answer.column)
			pathsByAnswerByKey[key, default: [:]][answer.answer, default: []].insert(answer.path)
			familiesByAnswerByKey[key, default: [:]][answer.answer, default: []].insert(answer.isInsideSendableWrapper)
			outerFillsByAnswerByKey[key, default: [:]][answer.answer, default: []].insert(answer.outerFills)
			narrowKeys[Key(seamType: answer.seamType, node: answer.node, edge: answer.edge, fill: "", column: answer.column), default: []].insert(answer.answer)
		}

		/// The keys whose answers differ after family joins the key: what the widened key, with family, leaves.
		var keysDisagreeingWithFamily: [Key] {
			pathsByAnswerByKey.keys.filter { key in
				let families = familiesByAnswerByKey[key, default: [:]]
				return families.count > 1 && !(families.values.allSatisfy { $0.count == 1 } && Set(families.values.compactMap(\.first)).count == families.count)
			}.sorted()
		}
	}

	/// Handed the answers of each run of `generate` a test makes, when set (`runs(of:)`).
	@TaskLocal static var runCollector: (@Sendable (Answers) -> Void)?

	/// The answers of each run of `generate` that `operation` makes, one per run, since each run is a graph of its own.
	static func runs(of operation: () async throws -> Void) async throws -> [Answers] {
		let (stream, continuation) = AsyncStream.makeStream(of: Answers.self)
		try await $runCollector.withValue({ continuation.yield($0) }) {
			try await operation()
		}
		continuation.finish()
		var runs = [Answers]()
		for await run in stream {
			runs.append(run)
		}
		return runs
	}

	static func recording<Result>(fixturePaths: [String], _ operation: () async throws -> Result) async throws -> Result {
		let directory = ProcessInfo.processInfo.environment["SAFEDI_SEAM_PATH_ANSWERS_DIR"].flatMap { $0.isEmpty ? nil : $0 }
		guard directory != nil || runCollector != nil else {
			return try await operation()
		}
		let (result, answers) = try await collecting(operation)
		runCollector?(answers)
		guard let directory, !answers.pathsByAnswerByKey.isEmpty else { return result }
		var fixtureSize = 0
		for path in fixturePaths {
			fixtureSize += (try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? 0
		}
		let disagreeing = answers.pathsByAnswerByKey.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
		let disagreeingWithFamily = Set(answers.keysDisagreeingWithFamily)
		let narrowDisagreeing = answers.narrowKeys.values.count(where: { $0.count > 1 })
		let longestPath = answers.pathsByAnswerByKey.values.flatMap(\.values).flatMap(\.self).map { $0.components(separatedBy: " / ").count }.max() ?? 0
		let deepestFill = answers.outerFillsByAnswerByKey.values.flatMap(\.values).flatMap(\.self).map { $0.isEmpty ? 0 : $0.components(separatedBy: " <- ").count }.max() ?? 0
		var report = "test \(Test.current?.name ?? "?") | fixture bytes \(fixtureSize) | longest path \(longestPath) | outer fills at most \(deepestFill) | keys \(answers.pathsByAnswerByKey.count) | narrow keys disagreeing \(narrowDisagreeing) | disagreeing \(disagreeing.count) | disagreeing with family \(disagreeingWithFamily.count)\n"
		for (key, pathsByAnswer) in disagreeing {
			let families = answers.familiesByAnswerByKey[key, default: [:]]
			let outerFills = answers.outerFillsByAnswerByKey[key, default: [:]]
			let isExplainedByOuterFills = outerFills.values.allSatisfy { $0.count == 1 } && Set(outerFills.values.compactMap(\.first)).count == outerFills.count
			report += "DISAGREE seam \(key.seamType) | node \(key.node) | edge \(key.edge) | fill \(key.fill) | column \(key.column) | explained by family: \(!disagreeingWithFamily.contains(key)) | explained by outer fills: \(isExplainedByOuterFills)\n"
			for (answer, paths) in pathsByAnswer.sorted(by: { $0.key < $1.key }) {
				report += "  answer (sendable wrapper above: \(families[answer, default: []].map(String.init(describing:)).sorted()), outer fills: \(outerFills[answer, default: []].sorted())):\n"
				report += answer.split(separator: "\n", omittingEmptySubsequences: false).map { "    | \($0)" }.joined(separator: "\n") + "\n"
				for path in paths.sorted() {
					report += "    path \(path)\n"
				}
			}
		}
		let file = URL(fileURLWithPath: directory).appendingPathComponent("\(disagreeing.isEmpty ? "agree" : disagreeingWithFamily.isEmpty ? "FAMILY" : "DISAGREE")-\(UUID().uuidString).txt")
		try? report.write(to: file, atomically: true, encoding: .utf8)
		return result
	}

	/// Runs `operation` with every answer recorded.
	static func collecting<Result>(_ operation: () async throws -> Result) async throws -> (Result, Answers) {
		let (stream, continuation) = AsyncStream.makeStream(of: SeamHolesPathAnswer.self)
		let result = try await SeamHolesPathAnswer.$observer.withValue({ answer in
			continuation.yield(answer)
		}) {
			try await operation()
		}
		continuation.finish()
		var answers = Answers()
		for await answer in stream {
			answers.add(answer)
		}
		return (result, answers)
	}
}
