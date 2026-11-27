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
import Testing
@testable import SafeDIToolTestSupport

struct SafeDIToolBaseComparisonTests {
	// MARK: Comparing one tool with itself

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compare_findsNoDifference_whenBaseAndHeadAreOneTool() async throws {
		let tool = try GraphFuzzerBaseComparison.builtTool()
		var results = [GraphFuzzerBaseComparison.Result]()
		for (features, seeds) in Self.graphsOfEveryFlow {
			for seed in seeds {
				await results.append(try GraphFuzzerBaseComparison.compare(GraphFuzzerGenerator.fixture(forSeed: seed, features: features), base: tool, head: tool))
			}
		}
		#expect(results.flatMap(\.differences) == [])
		#expect(results.compactMap(\.problem) == [])
		#expect(Set(results.map(\.flow)) == [.plugin, .moduleInfo])
		let filePaths = results.flatMap(\.filePaths)
		#expect(filePaths.contains("manifest.json"))
		#expect(filePaths.contains { $0.hasPrefix("Output/") && $0.hasSuffix("+SafeDI.swift") })
		#expect(filePaths.contains { $0.hasPrefix("ModuleInfo/") && $0.hasSuffix(".safedi") })
		#expect(filePaths.contains { $0.hasPrefix("Output/Fuzz") && $0.hasSuffix(".swift") })
		#expect(filePaths.contains("Output/graph.dot"))
		#expect(filePaths.contains { $0.hasPrefix("Output/Fuzz") && $0.hasSuffix(".dot") })
	}

	// MARK: Comparing two tools

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compare_reportsProblemAndNoDifference_whenBaseToolRejectsArguments() async throws {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let base = try Self.script("echo \"Error: Unknown option '--mock-scoped-files'\" >&2\nexit 64", filesToDelete: &filesToDelete)
		let result = try await GraphFuzzerBaseComparison.compare(GraphFuzzerGenerator.fixture(forSeed: 0), base: base, head: GraphFuzzerBaseComparison.builtTool())
		#expect(result.differences == [])
		#expect(result.problem == "the base tool rejected the arguments of scan: Error: Unknown option '--mock-scoped-files'")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compare_reportsDiagnosticsOfEveryStep_whenHeadToolPrintsMore() async throws {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let tool = try GraphFuzzerBaseComparison.builtTool()
		let head = try Self.script("\"\(tool.path)\" \"$@\"\nstatus=$?\necho \"warning: one more\" >&2\nexit $status", filesToDelete: &filesToDelete)
		// Seed 0 of the base corpus is in one module and accepted, so both steps run on both sides.
		let result = try await GraphFuzzerBaseComparison.compare(GraphFuzzerGenerator.fixture(forSeed: 0), base: tool, head: head)
		#expect(result.problem == nil)
		#expect(result.differences == [
			.diagnostics(step: "scan", base: "", head: "warning: one more\n"),
			.diagnostics(step: "generate", base: "", head: "warning: one more\n"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compare_reportsStandardOutputOfEveryStep_whenHeadToolPrintsToIt() async throws {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let tool = try GraphFuzzerBaseComparison.builtTool()
		let head = try Self.script("\"\(tool.path)\" \"$@\"\nstatus=$?\necho \"one more\"\nexit $status", filesToDelete: &filesToDelete)
		// Seed 0 of the base corpus is in one module and accepted, so both steps run on both sides.
		let result = try await GraphFuzzerBaseComparison.compare(GraphFuzzerGenerator.fixture(forSeed: 0), base: tool, head: head)
		#expect(result.problem == nil)
		#expect(result.differences == [
			.standardOutput(step: "scan", base: "", head: "one more\n"),
			.standardOutput(step: "generate", base: "", head: "one more\n"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compare_reportsChangedFile_whenHeadToolWritesOtherBytes() async throws {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let tool = try GraphFuzzerBaseComparison.builtTool()
		// Appends a line to the combined output a module-info run names after `--combined-output`.
		let head = try Self.script(
			"""
			"\(tool.path)" "$@" || exit $?
			while [ $# -gt 0 ]; do
				if [ "$1" = "--combined-output" ]; then echo "// one more" >> "$2"; fi
				shift
			done
			""",
			filesToDelete: &filesToDelete,
		)
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0, features: [.generateMockPublic])
		let result = try await GraphFuzzerBaseComparison.compare(fixture, base: tool, head: head)
		#expect(result.flow == .moduleInfo)
		#expect(result.problem == nil)
		let changedPaths = result.differences.map { difference -> String? in
			guard case let .fileBytes(path, _, _) = difference else { return nil }
			return path
		}
		#expect(!changedPaths.isEmpty)
		#expect(changedPaths.allSatisfy { $0?.hasPrefix("Output/") == true && $0?.hasSuffix(".swift") == true })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compare_reportsChangedDOTGraph_whenHeadToolDrawsOtherLines() async throws {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let tool = try GraphFuzzerBaseComparison.builtTool()
		// Appends a line to the DOT graph a run names after `--dot-file-output`.
		let head = try Self.script(
			"""
			"\(tool.path)" "$@" || exit $?
			while [ $# -gt 0 ]; do
				if [ "$1" = "--dot-file-output" ]; then echo "    A -- B" >> "$2"; fi
				shift
			done
			""",
			filesToDelete: &filesToDelete,
		)
		// Seed 0 of the base corpus is in one module and accepted, so `generate` writes its graph on both sides.
		let result = try await GraphFuzzerBaseComparison.compare(GraphFuzzerGenerator.fixture(forSeed: 0), base: tool, head: head)
		#expect(result.problem == nil)
		let changedPaths = result.differences.map { difference -> String? in
			guard case let .fileBytes(path, _, _) = difference else { return nil }
			return path
		}
		#expect(changedPaths == ["Output/graph.dot"])
	}

	// MARK: Differences between records

	@Test
	func differences_areEmpty_whenRecordsAreEqual() {
		let record = Self.record(steps: [("scan", 0, "")], outputs: ["manifest.json": "{}"])
		#expect(GraphFuzzerBaseComparison.differences(base: record, head: record) == [])
	}

	@Test
	func differences_reportSteps_whenOneToolStopsWhereTheOtherGoesOn() {
		let base = Self.record(steps: [("generate FuzzFeature", 1, "error: x\n")], outputs: [:])
		let head = Self.record(steps: [("generate FuzzFeature", 0, ""), ("generate FuzzApp", 0, "")], outputs: [:])
		#expect(GraphFuzzerBaseComparison.differences(base: base, head: head) == [
			.steps(base: ["generate FuzzFeature"], head: ["generate FuzzFeature", "generate FuzzApp"]),
			.exitStatus(step: "generate FuzzFeature", base: 1, head: 0),
			.diagnostics(step: "generate FuzzFeature", base: "error: x\n", head: ""),
		])
	}

	@Test
	func differences_reportExitStatusAlone_whenOnlyTheStatusDiffers() {
		let base = Self.record(steps: [("generate", 1, "error: x\n")], outputs: [:])
		let head = Self.record(steps: [("generate", 2, "error: x\n")], outputs: [:])
		#expect(GraphFuzzerBaseComparison.differences(base: base, head: head) == [.exitStatus(step: "generate", base: 1, head: 2)])
	}

	@Test
	func differences_reportEachFile_whenItDiffersOrOneSideAloneWroteIt() {
		let base = Self.record(steps: [], outputs: ["A.swift": "a", "B.swift": "b", "Module.safedi": "1"])
		let head = Self.record(steps: [], outputs: ["B.swift": "b", "C.swift": "c", "Module.safedi": "2"])
		#expect(GraphFuzzerBaseComparison.differences(base: base, head: head) == [
			.fileOnlyInBase(path: "A.swift"),
			.fileOnlyInHead(path: "C.swift"),
			.fileBytes(path: "Module.safedi", base: Data("1".utf8), head: Data("2".utf8)),
		])
	}

	@Test
	func description_namesFirstDifferingLine_whenTextFilesDiffer() {
		let difference = GraphFuzzerBaseComparison.Difference.fileBytes(path: "Output/A.swift", base: Data("one\ntwo\n".utf8), head: Data("one\nthree\n".utf8))
		#expect(difference.description == "file Output/A.swift: line 2: base `two`, head `three`")
	}

	@Test
	func description_namesFirstDifferingByte_whenFilesAreNotText() {
		let difference = GraphFuzzerBaseComparison.Difference.fileBytes(path: "ModuleInfo/A.safedi", base: Data([0, 1, 0xFF]), head: Data([0, 2, 0xFF, 3]))
		#expect(difference.description == "file ModuleInfo/A.safedi: 3 bytes in the base, 4 in the head, first differing at byte 1")
	}

	// MARK: Long run

	@Test(.enabled(if: BaseComparisonLongRunConfiguration.isRequested, "Set SAFEDI_BASE_COMPARISON_BASE_TOOL to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_reportsEveryDifference_whenEnabledByEnvironment() async throws {
		let configuration: BaseComparisonLongRunConfiguration
		switch BaseComparisonLongRunConfiguration.current {
		case let .success(current):
			configuration = current
		case let .failure(problem):
			// The run was requested, so a missing input fails it rather than skipping it.
			Issue.record(Comment(rawValue: problem.description))
			return
		}
		let report = GraphFuzzerReport(path: configuration.reportPath)
		report.append("base-comparison corpus=\(configuration.corpusName) seeds=\(configuration.seeds.lowerBound)..<\(configuration.seeds.upperBound) corpus-seeds=\(configuration.corpusSeedCount)")
		let start = Date()
		// Each graph's two runs are sequential, in one directory; graphs run side by side, a few more than the
		// processes `runProcess` allows at once, so a graph's fixture is written while another's tool runs.
		let concurrentGraphCount = ProcessInfo.processInfo.activeProcessorCount * 2
		var results = [GraphFuzzerBaseComparison.Result]()
		try await withThrowingTaskGroup(of: GraphFuzzerBaseComparison.Result.self) { group in
			var pendingSeeds = Array(configuration.seeds.reversed())
			var inFlightCount = 0
			while inFlightCount > 0 || !pendingSeeds.isEmpty {
				while inFlightCount < concurrentGraphCount, let seed = pendingSeeds.popLast() {
					inFlightCount += 1
					group.addTask {
						try await GraphFuzzerBaseComparison.compare(
							GraphFuzzerGenerator.fixture(forSeed: seed, features: configuration.features),
							base: configuration.baseTool,
							head: configuration.headTool,
						)
					}
				}
				if let result = try await group.next() {
					results.append(result)
				}
				inFlightCount -= 1
			}
		}
		results.sort { $0.seed < $1.seed }
		var flowCounts = [GraphFuzzerBaseComparison.Flow: Int]()
		for result in results {
			flowCounts[result.flow, default: 0] += 1
			if let problem = result.problem {
				report.append("problem \(result.seed) \(problem)")
			} else if let first = result.differences.first {
				report.append("difference \(result.seed) \(result.flow.rawValue) \(first) (\(result.differences.count) in all)")
				for difference in result.differences.dropFirst().prefix(9) {
					report.append("    \(difference)")
				}
			}
		}
		let differingCount = results.count { $0.problem == nil && !$0.differences.isEmpty }
		let problemCount = results.count { $0.problem != nil }
		report.append("summary compared=\(results.count - problemCount) differing=\(differingCount) problems=\(problemCount) plugin=\(flowCounts[.plugin, default: 0]) module-info=\(flowCounts[.moduleInfo, default: 0]) files=\(results.reduce(0) { $0 + $1.filePaths.count })")
		report.append("cpu wall=\(Int(Date().timeIntervalSince(start).rounded()))")
		report.append("completed \(results.count)")
		// Differences and problems are the combine job's to judge, by what the pull request says it changes; the run
		// fails only when it did not compare every seed it was given.
		#expect(results.count == configuration.seeds.count)
	}

	// MARK: Helpers

	/// Graphs of the base, seam and public mock corpora, among them graphs in one module and graphs split across
	/// modules, accepted and rejected.
	private static let graphsOfEveryFlow: [(features: Set<GraphFuzzerGeneratorFeature>, seeds: [UInt64])] = [
		([], [0, 1, 2]),
		([.generateDependencyTree], [0, 1, 2]),
		([.generateMockPublic], [0, 1]),
	]

	private static func record(steps: [(String, Int32, String)], outputs: [String: String]) -> GraphFuzzerBaseComparison.Record {
		GraphFuzzerBaseComparison.Record(
			steps: steps.map { GraphFuzzerBaseComparison.Record.Step(name: $0.0, exitCode: $0.1, stderr: $0.2) },
			outputs: outputs.mapValues { Data($0.utf8) },
		)
	}

	/// An executable shell script running `body`.
	///
	/// It is written under another name through a descriptor that closes on `exec`, and takes its name once that
	/// descriptor is closed. Linux refuses to execute a file that any process holds open for writing ("Text file
	/// busy"), and a process that another test spawns while the script is being written inherits every descriptor of
	/// the test process that does not close on `exec`, for as long as it runs. Foundation's atomic write opens one
	/// that does not, so a script written with it once failed to start, with a compile another test had started
	/// holding it open.
	private static func script(_ body: String, filesToDelete: inout [URL]) throws -> URL {
		let file = TestTemporaryDirectory.uniquePath(prefix: "safedi-base-comparison-tool-", pathExtension: "sh")
		let fileBeingWritten = file.appendingPathExtension("writing")
		filesToDelete.append(file)
		filesToDelete.append(fileBeingWritten)
		try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		let descriptor = open(fileBeingWritten.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o755)
		guard descriptor >= 0 else {
			throw ProcessSpawnError(executablePath: fileBeingWritten.path, operation: "open", errorNumber: errno)
		}
		let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
		do {
			try handle.write(contentsOf: Data(("#!/bin/sh\n" + body + "\n").utf8))
			try handle.close()
		} catch {
			try? handle.close()
			throw error
		}
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileBeingWritten.path)
		try FileManager.default.moveItem(at: fileBeingWritten, to: file)
		return file
	}
}

/// The long run's configuration, from the environment `ci.yml`'s fuzzer shards set when the pull request's base tool
/// built.
struct BaseComparisonLongRunConfiguration {
	struct Problem: Error, CustomStringConvertible {
		let description: String
	}

	let baseTool: URL
	let headTool: URL
	let features: Set<GraphFuzzerGeneratorFeature>
	let seeds: Range<UInt64>
	/// How many seeds the corpus holds, which the combine job checks the shards cover exactly once.
	let corpusSeedCount: Int
	let reportPath: String

	/// The corpus's name in the report: its features, or `base`.
	var corpusName: String {
		features.isEmpty ? "base" : features.map(\.rawValue).sorted().joined(separator: ",")
	}

	/// Whether the run is requested: `SAFEDI_BASE_COMPARISON_BASE_TOOL` names the base's tool.
	static var isRequested: Bool {
		ProcessInfo.processInfo.environment["SAFEDI_BASE_COMPARISON_BASE_TOOL"] != nil
	}

	/// The configuration a requested run reads, or the problem that keeps it from running:
	/// `SAFEDI_BASE_COMPARISON_BASE_TOOL` and `SAFEDI_BASE_COMPARISON_HEAD_TOOL` must name executables and
	/// `SAFEDI_BASE_COMPARISON_REPORT` a file in a directory that exists; `SAFEDI_BASE_COMPARISON_FEATURES` names the
	/// corpus as `SAFEDI_GRAPH_FUZZER_FEATURES` does, and `SAFEDI_BASE_COMPARISON_STARTING_SEED` and
	/// `SAFEDI_BASE_COMPARISON_ITERATIONS` the seeds, the whole corpus when both are unset.
	static var current: Result<BaseComparisonLongRunConfiguration, Problem> {
		let environment = ProcessInfo.processInfo.environment
		var problems = [String]()
		func executable(_ name: String) -> URL? {
			guard let path = environment[name], FileManager.default.isExecutableFile(atPath: path) else {
				problems.append("\(name) names no executable.")
				return nil
			}
			return URL(fileURLWithPath: path)
		}
		let baseTool = executable("SAFEDI_BASE_COMPARISON_BASE_TOOL")
		let headTool = executable("SAFEDI_BASE_COMPARISON_HEAD_TOOL")
		let reportPath = environment["SAFEDI_BASE_COMPARISON_REPORT"] ?? ""
		if reportPath.isEmpty || !FileManager.default.fileExists(atPath: URL(fileURLWithPath: reportPath).deletingLastPathComponent().path) {
			problems.append("SAFEDI_BASE_COMPARISON_REPORT must name a file in a directory that exists.")
		}
		let featureNames = (environment["SAFEDI_BASE_COMPARISON_FEATURES"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
		let features = featureNames.compactMap(GraphFuzzerGeneratorFeature.init(rawValue:))
		if features.count != featureNames.count {
			problems.append("SAFEDI_BASE_COMPARISON_FEATURES names a feature that does not exist.")
		}
		let corpusSeedCount = SafeDIToolGraphFuzzerTests.corpus(for: Set(features)).seedCount
		let startingSeed = environment["SAFEDI_BASE_COMPARISON_STARTING_SEED"].map { UInt64($0) } ?? 0
		let iterations = environment["SAFEDI_BASE_COMPARISON_ITERATIONS"].map { Int($0) } ?? corpusSeedCount
		guard let startingSeed, let iterations, iterations > 0 else {
			problems.append("SAFEDI_BASE_COMPARISON_STARTING_SEED and SAFEDI_BASE_COMPARISON_ITERATIONS must name at least one seed.")
			return .failure(Problem(description: problems.joined(separator: "\n")))
		}
		guard problems.isEmpty, let baseTool, let headTool else {
			return .failure(Problem(description: problems.joined(separator: "\n")))
		}
		return .success(BaseComparisonLongRunConfiguration(
			baseTool: baseTool,
			headTool: headTool,
			features: Set(features),
			seeds: startingSeed..<(startingSeed + UInt64(iterations)),
			corpusSeedCount: corpusSeedCount,
			reportPath: reportPath,
		))
	}
}
