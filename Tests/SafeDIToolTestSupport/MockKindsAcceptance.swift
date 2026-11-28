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

/// The acceptance cells of the mock kinds: a graph's mock is generated with its internal mock roots laid out from node
/// records (`NodeRecordsObservation.laysOutMockRoots`) and as the mock's walk writes them, both are compiled, and what
/// each builds for the cell's probes is compared, the walk being the known-right path. A root node records refuse is
/// written by the walk in both, so its values hold today and keep holding when a kind frees it. Whether a root was laid
/// out is not asserted: where `SAFEDI_MOCK_KINDS_CELLS_LIST` names a file, each cell appends to it a line per mock root
/// (the cell, the root, `laid out` or every refusal its world holds) and the values the laid out mock built for each
/// probe, which show the place each lap entered. A kind's own commit adds the assertion that its cells are laid out.
///
/// Under the sweep's switch (`SAFEDI_NODE_RECORDS_LAY_OUT_MOCKS`), both paths lay out, so the cells run without it.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum MockKindsAcceptance {
	/// Generates the mock of `fixtureFiles` both ways and records an issue for each probe whose values differ.
	static func expectLaidOutValuesEqualWalks(
		fixtureFiles: [String: String],
		probes: [DifferentialValueProbe],
		filesToDelete: inout [URL],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let walk = try await NodeRecordsObservation.$laysOutMockRoots.withValue(false) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let (reportStream, reportContinuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		let laidOut = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { reportContinuation.yield($0) }) {
				try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		reportContinuation.finish()
		var mockRootReports = [NodeRecordsReport]()
		for await report in reportStream where report.isMockRoot {
			mockRootReports.append(report)
		}
		guard let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(laidOut.generatedFiles, sourceLocation: sourceLocation)),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(walk.generatedFiles, sourceLocation: sourceLocation)),
			probes: probes,
			filesToDelete: &filesToDelete,
		) else { return }
		for difference in comparison.differences {
			Issue.record(
				"The mock laid out from node records builds other values than the mock’s walk for \(difference)\n\(comparison.report)",
				sourceLocation: sourceLocation,
			)
		}
		appendToCellsList(reports: mockRootReports, laidOutValues: comparison.featureDescription, agrees: comparison.differences.isEmpty)
	}

	/// Appends a cell's outcome to the file `SAFEDI_MOCK_KINDS_CELLS_LIST` names, where it names one.
	private static func appendToCellsList(reports: [NodeRecordsReport], laidOutValues: String, agrees: Bool) {
		guard let path = ProcessInfo.processInfo.environment["SAFEDI_MOCK_KINDS_CELLS_LIST"] else { return }
		let cell = Test.current?.name ?? "unknown cell"
		var text = ""
		for report in reports.sorted(by: { $0.root < $1.root }) {
			let outcome = report.isLaidOutFromNodeRecords ? "laid out" : "held: " + (report.everyRefusal.isEmpty ? report.refusal ?? "unknown" : report.everyRefusal.joined(separator: ","))
			text += "CELL\t\(cell)\t\(report.root)\t\(outcome)\t\(agrees ? "values agree" : "VALUES DIFFER")\n"
		}
		text += laidOutValues.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n") + "\n"
		appendLine(text, toFileAt: path)
	}

	private static func appendLine(_ text: String, toFileAt path: String) {
		if !FileManager.default.fileExists(atPath: path) {
			_ = FileManager.default.createFile(atPath: path, contents: nil)
		}
		guard let handle = FileHandle(forWritingAtPath: path) else { return }
		defer { try? handle.close() }
		_ = try? handle.seekToEnd()
		try? handle.write(contentsOf: Data(text.utf8))
	}
}
