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
	private struct Key: Hashable {
		let seamType: String
		let node: String
		let edge: String
		let column: String
	}

	static func recording<Result>(fixturePaths: [String], _ operation: () async throws -> Result) async throws -> Result {
		guard let directory = ProcessInfo.processInfo.environment["SAFEDI_SEAM_PATH_ANSWERS_DIR"], !directory.isEmpty else {
			return try await operation()
		}
		let (answers, continuation) = AsyncStream.makeStream(of: SeamHolesPathAnswer.self)
		let result = try await SeamHolesPathAnswer.$observer.withValue({ answer in
			continuation.yield(answer)
		}) {
			try await operation()
		}
		continuation.finish()
		var pathsByAnswerByKey = [Key: [String: Set<String>]]()
		var familiesByAnswerByKey = [Key: [String: Set<Bool>]]()
		for await answer in answers {
			let key = Key(seamType: answer.seamType, node: answer.node, edge: answer.edge, column: answer.column)
			pathsByAnswerByKey[key, default: [:]][answer.answer, default: []].insert(answer.path)
			familiesByAnswerByKey[key, default: [:]][answer.answer, default: []].insert(answer.isInsideSendableWrapper)
		}
		guard !pathsByAnswerByKey.isEmpty else { return result }
		var fixtureSize = 0
		for path in fixturePaths {
			fixtureSize += (try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? 0
		}
		let multiPathKeys = pathsByAnswerByKey.filter { $0.value.values.reduce(0) { $0 + $1.count } > 1 }
		let disagreeing = pathsByAnswerByKey.filter { $0.value.count > 1 }.sorted {
			($0.key.seamType, $0.key.node, $0.key.edge, $0.key.column) < ($1.key.seamType, $1.key.node, $1.key.edge, $1.key.column)
		}
		var report = "test \(Test.current?.name ?? "?") | fixture bytes \(fixtureSize) | keys \(pathsByAnswerByKey.count) | keys with several paths \(multiPathKeys.count) | disagreeing \(disagreeing.count)\n"
		for (key, pathsByAnswer) in disagreeing {
			// Whether the answers would agree once the family (a `Sendable` wrapper above the edge) joins the key.
			let families = familiesByAnswerByKey[key, default: [:]]
			let isExplainedByFamily = Set(families.values.compactMap { $0.count == 1 ? $0.first : nil }).count == pathsByAnswer.count && families.values.allSatisfy { $0.count == 1 }
			report += "DISAGREE seam \(key.seamType) | node \(key.node) | edge \(key.edge) | column \(key.column) | explained by family: \(isExplainedByFamily)\n"
			for (answer, paths) in pathsByAnswer.sorted(by: { $0.key < $1.key }) {
				report += "  answer (sendable wrapper above: \(families[answer, default: []].map(String.init(describing:)).sorted())):\n"
				report += answer.split(separator: "\n", omittingEmptySubsequences: false).map { "    | \($0)" }.joined(separator: "\n") + "\n"
				for path in paths.sorted() {
					report += "    path \(path)\n"
				}
			}
		}
		let file = URL(fileURLWithPath: directory).appendingPathComponent("\(disagreeing.isEmpty ? "agree" : "DISAGREE")-\(UUID().uuidString).txt")
		try? report.write(to: file, atomically: true, encoding: .utf8)
		return result
	}
}
