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

/// The DOT graph of every tree a test or fuzzer graph builds, unfolded from the declarations of its world's graph, must be
/// the bytes its places draw (`TypeFactsReport.DOT`): the check that lets the DOT graph stay one line per path once the
/// tree of places is gone.
///
/// DOT 1. The unfolded text equals the tree's.
/// DOT 2. Every place of one declaration draws the same edges, but for fills a call passes on, so one column stands for
/// the declaration.
///
/// Findings are recorded as issues only where `SAFEDI_TYPE_FACTS_STRICT` is set, until every graph passes; a run that sets
/// `SAFEDI_TYPE_FACTS_DOT_LOG` to a file appends a line per tree to it, for a sweep.
enum TypeFactsDOTChecks {
	static func check(_ report: TypeFactsReport) {
		let findings = findings(of: report.dot)
		let environment = ProcessInfo.processInfo.environment
		if environment["SAFEDI_TYPE_FACTS_STRICT"] != nil {
			for (check, finding) in findings {
				Issue.record(Comment(rawValue: "Type facts DOT check \(check), root \(report.root): \(finding)"))
			}
		}
		if let path = environment["SAFEDI_TYPE_FACTS_DOT_LOG"], !path.isEmpty {
			var line = "root=\(report.root) mock=\(report.forMockGeneration) nodes=\(report.nodes.count) places=\(report.places.count) lines=\(report.dot.drawnByTree.isEmpty ? 0 : report.dot.drawnByTree.split(separator: "\n", omittingEmptySubsequences: false).count)"
			line.append(" dot1=\(findings.contains { $0.check == 1 } ? 1 : 0) dot2=\(report.dot.declarationsDrawnPerPath.count)")
			for (check, finding) in findings {
				line.append(" firstDOT\(check)=«\(finding.replacingOccurrences(of: "\n", with: " ⏎ "))»")
			}
			append(line + "\n", toFileAt: path)
		}
	}

	static func findings(of dot: TypeFactsReport.DOT) -> [(check: Int, finding: String)] {
		var findings = [(check: Int, finding: String)]()
		if !dot.drawnByTree.utf8.elementsEqual(dot.unfolded.utf8) {
			let drawn = dot.drawnByTree.split(separator: "\n", omittingEmptySubsequences: false)
			let unfolded = dot.unfolded.split(separator: "\n", omittingEmptySubsequences: false)
			let index = Array(zip(drawn, unfolded)).firstIndex { !$0.utf8.elementsEqual($1.utf8) } ?? min(drawn.count, unfolded.count)
			let drawnLine = index < drawn.count ? String(drawn[index]) : "(end)"
			let unfoldedLine = index < unfolded.count ? String(unfolded[index]) : "(end)"
			findings.append((1, "the unfolded DOT graph differs at line \(index + 1) of \(drawn.count): tree «\(drawnLine)», unfolded «\(unfoldedLine)» (\(unfolded.count) lines)"))
		}
		if let first = dot.declarationsDrawnPerPath.first {
			findings.append((2, "\(dot.declarationsDrawnPerPath.count) declarations draw otherwise at two places, first \(first)"))
		}
		return findings
	}

	private static func append(_ line: String, toFileAt path: String) {
		let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard descriptor >= 0 else { return }
		defer { close(descriptor) }
		let bytes = Array(line.utf8)
		_ = bytes.withUnsafeBufferPointer { write(descriptor, $0.baseAddress, $0.count) }
	}
}
