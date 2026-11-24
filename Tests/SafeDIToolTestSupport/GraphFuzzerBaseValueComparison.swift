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

// MARK: - Base value comparison

/// Compares what two built `SafeDITool` executables generate for a fuzzer graph by the values the generated code builds,
/// rather than by its bytes (`GraphFuzzerBaseComparison`): a change that lays mock bodies out anew, such as one builder
/// function per class of places in place of one per place, changes bytes on purpose and must change no value.
///
/// Each graph runs through both tools as the byte comparison runs it (`GraphFuzzerBaseComparison.Layout`). A graph both
/// tools accept whose generated code differs is compiled twice, once with each tool's code, by the differential value
/// comparator, and the head's descriptions are compared with the base's, probe by probe: the head is the feature path
/// and the base the known-right one. A base corpus graph is compared as its value-oracle fixture
/// (`GraphFuzzerValueOraclePlan`, which both tools run again): every root's `mock()`, every mirrored mock with the samples
/// its pair hands it, and every override oracle's probe, a mock called with one override, in the feature expressions the
/// value oracle compares with production. A seam or public mock corpus graph is compared as the seam oracles compare it
/// (`GraphFuzzerFixture.differentialValueProbes(generatedFiles:)`): each root and each mock without a required parameter.
/// The probes are planned from the base's code, so both paths describe the same expressions.
///
/// Nothing of this lives in `Sources`: both tools are run as processes, so the base is any commit whose tool takes these
/// arguments.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerBaseValueComparison {
	/// Why a graph was not compared by value.
	enum SkipReason: String, CaseIterable, Comparable, Sendable {
		/// A tool rejected the arguments it was given (`GraphFuzzerBaseComparison.argumentErrorExitCode`).
		case argumentProblem
		/// Both tools reject the graph, so there is no code to compare.
		case rejectedByBoth
		/// The mirror model disagrees with the base's mocks, so the base corpus's value-oracle fixture has no plan.
		case mirrorModelDisagrees
		/// The base rejects the base corpus graph's value-oracle fixture, which the corpus run judges.
		case valueOracleFixtureRejected
		/// The graph's code has no probe: no root and no mock without a required parameter.
		case noProbe
		/// The base's code does not compile or run with the graph, which the corpus run judges.
		case baseNotDescribed
		/// A probe spent its traversals on both paths at one node, below which nothing is compared.
		case traversalsSpent
		/// Compile verification is off (`SAFEDI_SKIP_COMPILE_CHECK`), so nothing is compiled.
		case compileVerificationDisabled

		static func < (lhs: SkipReason, rhs: SkipReason) -> Bool {
			lhs.rawValue < rhs.rawValue
		}
	}

	/// What the comparison found wrong with the head.
	enum Finding: Equatable, Sendable, CustomStringConvertible {
		/// The head builds another value than the base: the first difference, and how many the graph has in all.
		case valueDifference(first: String, count: Int)
		/// One tool accepts a graph or value-oracle fixture the other rejects.
		case acceptanceDiffers(base: Bool, head: Bool, fixture: String)
		/// The head's code does not compile or run with the graph where the base's does.
		case headNotDescribed(String)

		var description: String {
			switch self {
			case let .valueDifference(first, count):
				"value \(first) (\(count) in all)"
			case let .acceptanceDiffers(base, head, fixture):
				"acceptance of the \(fixture): base \(base ? "accepts" : "rejects"), head \(head ? "accepts" : "rejects")"
			case let .headNotDescribed(error):
				// The compiler's first error, without the path of the file it is in, else the error's first line.
				if let errorLine = error.split(separator: "\n").first(where: { $0.contains("error: ") }), let range = errorLine.range(of: "error: ") {
					"head not described: \(errorLine[range.lowerBound...])"
				} else {
					"head not described: \(error.split(separator: "\n").first ?? "")"
				}
			}
		}
	}

	/// How one graph ended.
	enum Outcome: Equatable, Sendable {
		/// Both tools generated the same bytes for the compared fixture.
		case byteIdentical
		/// The bytes differ and every probe describes the same values.
		case matchingValues
		case skipped(SkipReason)
		case finding(Finding)
	}

	/// How one graph, named by its seed, ended.
	struct Verdict: Equatable, Sendable {
		let seed: UInt64
		let outcome: Outcome
	}

	/// What the long run reports: graphs compared by value, byte-identical, differing in bytes but matching in values,
	/// skipped by reason, and each finding.
	struct Counts: Equatable {
		var graphs = 0
		var byteIdentical = 0
		var matchingValues = 0
		var skips = [SkipReason: Int]()
		var findings = [(seed: UInt64, finding: Finding)]()

		init(_ results: [Verdict]) {
			for result in results.sorted(by: { $0.seed < $1.seed }) {
				graphs += 1
				switch result.outcome {
				case .byteIdentical:
					byteIdentical += 1
				case .matchingValues:
					matchingValues += 1
				case let .skipped(reason):
					skips[reason, default: 0] += 1
				case let .finding(finding):
					findings.append((result.seed, finding))
				}
			}
		}

		/// The graphs whose values were compared: those whose bytes differ, with a verdict.
		var comparedByValue: Int {
			matchingValues + findings.count {
				if case .valueDifference = $0.finding {
					true
				} else {
					false
				}
			}
		}

		/// The counts as one report line.
		var summary: String {
			var fields = [
				"graphs=\(graphs)",
				"byte-identical=\(byteIdentical)",
				"compared-by-value=\(comparedByValue)",
				"matching-values=\(matchingValues)",
				"findings=\(findings.count)",
			]
			for reason in SkipReason.allCases {
				fields.append("skip.\(reason.rawValue)=\(skips[reason, default: 0])")
			}
			return fields.joined(separator: " ")
		}

		static func == (lhs: Counts, rhs: Counts) -> Bool {
			lhs.summary == rhs.summary && lhs.findings.map { "\($0.seed) \($0.finding)" } == rhs.findings.map { "\($0.seed) \($0.finding)" }
		}
	}

	/// A graph both tools accept whose code differs, with the value graph that compares the head's code with the base's.
	struct PendingComparison {
		let seed: UInt64
		let graph: DifferentialValueGraph
	}

	/// Runs `fixture` through `base` and `head` and returns how it ended, or the value graph still to compare.
	static func prepare(_ fixture: GraphFuzzerFixture, base: URL, head: URL) async throws -> Either {
		for tool in [base, head] where !FileManager.default.isExecutableFile(atPath: tool.path) {
			throw GraphFuzzerInfrastructureError(description: "No SafeDITool executable at \(tool.path).")
		}
		let directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-base-value-comparison-")
		defer { try? FileManager.default.removeItem(at: directory) }
		let baseFiles: [String: String]
		let headFiles: [String: String]
		switch try await run(fixture, base: base, head: head, in: directory.appendingPathComponent("Drawn")) {
		case let .ended(outcome):
			return .ended(Verdict(seed: fixture.seed, outcome: outcome))
		case let .accepted(baseGeneratedFiles, headGeneratedFiles):
			baseFiles = baseGeneratedFiles
			headFiles = headGeneratedFiles
		}
		let features = GraphFuzzerGeneratorFeature.features(drawnIn: fixture)
		guard compileVerificationIsEnabled else {
			return .ended(Verdict(seed: fixture.seed, outcome: baseFiles == headFiles ? .byteIdentical : .skipped(.compileVerificationDisabled)))
		}
		if features.isEmpty, fixture.modules == nil {
			// A base corpus graph is compared as its value-oracle fixture, whose root mocks, mirrored mocks and override
			// probes the value oracle compares with production.
			let plan = GraphFuzzerValueOraclePlan(fixture: fixture, generatedFiles: baseFiles)
			guard plan.modelFailures.isEmpty else { return .ended(Verdict(seed: fixture.seed, outcome: .skipped(.mirrorModelDisagrees))) }
			let valueOracle = try await run(plan.valueOracleFixture(storingEveryParameter: false), base: base, head: head, in: directory.appendingPathComponent("ValueOracle"), fixtureName: "value-oracle fixture")
			switch valueOracle {
			case let .ended(outcome):
				return .ended(Verdict(seed: fixture.seed, outcome: outcome == .skipped(.rejectedByBoth) ? .skipped(.valueOracleFixtureRejected) : outcome))
			case let .accepted(baseValueFiles, headValueFiles):
				guard baseValueFiles != headValueFiles else { return .ended(Verdict(seed: fixture.seed, outcome: .byteIdentical)) }
				let storingFixture = plan.valueOracleFixture(storingEveryParameter: true)
				let pairs = plan.probePairs + plan.overrideProbes(generatedFiles: baseValueFiles).map(\.pair)
				return .pending(PendingComparison(seed: fixture.seed, graph: DifferentialValueGraph(
					name: "seed \(fixture.seed), value oracle",
					feature: DifferentialValuePath(fixture: storingFixture, generatedFiles: headValueFiles),
					knownRight: DifferentialValuePath(fixture: storingFixture, generatedFiles: baseValueFiles),
					probes: pairs.map { DifferentialValueProbe(name: $0.name, expression: $0.featureExpression) },
					samples: plan.forwardedPropertiesSamples,
				)))
			}
		}
		guard baseFiles != headFiles else { return .ended(Verdict(seed: fixture.seed, outcome: .byteIdentical)) }
		let storingFixture = GraphFuzzerGenerator.fixture(forSeed: fixture.seed, features: features, storingEveryParameter: true)
		let probes = storingFixture.differentialValueProbes(generatedFiles: baseFiles)
		guard !probes.isEmpty else { return .ended(Verdict(seed: fixture.seed, outcome: .skipped(.noProbe))) }
		return .pending(PendingComparison(seed: fixture.seed, graph: DifferentialValueGraph(
			name: "seed \(fixture.seed)",
			feature: DifferentialValuePath(fixture: storingFixture, generatedFiles: headFiles),
			knownRight: DifferentialValuePath(fixture: storingFixture, generatedFiles: baseFiles),
			probes: probes,
			samples: storingFixture.holeDrawForwardedPropertiesSamples + storingFixture.forwardedLabelAcrossSeamCallSamples,
		)))
	}

	/// A graph that ended before its values were compared, or the comparison still to make.
	enum Either {
		case ended(Verdict)
		case pending(PendingComparison)
	}

	/// Compares the pending graphs by value, in batches of `batchSize`, each batch compiled as one executable per path.
	static func compare(_ pending: [PendingComparison], batchSize: Int = 40) async throws -> [Verdict] {
		var results = [Verdict]()
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		var start = 0
		while start < pending.count {
			let batch = Array(pending[start..<min(start + batchSize, pending.count)])
			start += batchSize
			guard let comparisons = try await DifferentialValueOracle.compare(graphs: batch.map(\.graph), filesToDelete: &filesToDelete) else {
				results += batch.map { Verdict(seed: $0.seed, outcome: .skipped(.compileVerificationDisabled)) }
				continue
			}
			for (comparison, graph) in zip(comparisons, batch) {
				results.append(Verdict(seed: graph.seed, outcome: outcome(of: comparison.result)))
			}
		}
		return results
	}

	/// How a graph's value comparison ends: matching values, the head's first difference, or why it judged nothing.
	static func outcome(of result: Result<DifferentialValueComparison, DifferentialValueOracleError>) -> Outcome {
		switch result {
		case let .success(comparison):
			guard let first = comparison.differences.first else { return .matchingValues }
			return .finding(.valueDifference(first: firstLine(of: first), count: comparison.differences.count))
		case let .failure(error):
			switch error.path {
			case .feature:
				return .finding(.headNotDescribed(error.description))
			case .knownRight:
				return .skipped(.baseNotDescribed)
			case nil:
				return error.spentTraversals ? .skipped(.traversalsSpent) : .skipped(.baseNotDescribed)
			}
		}
	}

	/// The first description line at which the head differs from the base, with the probe and the path to it.
	static func firstLine(of difference: DifferentialValueDifference) -> String {
		"probe `\(difference.probe)` at \(difference.path.joined(separator: " > ")): base `\(difference.knownRight)`, head `\(difference.feature)`"
	}

	// MARK: Private

	/// What both tools did with one fixture.
	private enum Run {
		case ended(Outcome)
		case accepted(base: [String: String], head: [String: String])
	}

	/// Runs `fixture` through both tools in `directory`, and returns each tool's generated files where both accept it.
	private static func run(_ fixture: GraphFuzzerFixture, base: URL, head: URL, in directory: URL, fixtureName: String = "graph") async throws -> Run {
		let layout = try GraphFuzzerBaseComparison.Layout(writing: fixture, into: directory)
		let baseRecord = try await layout.record(running: base)
		let headRecord = try await layout.record(running: head)
		if (GraphFuzzerBaseComparison.argumentProblem(in: baseRecord, side: "base") ?? GraphFuzzerBaseComparison.argumentProblem(in: headRecord, side: "head")) != nil {
			return .ended(.skipped(.argumentProblem))
		}
		let baseAccepts = layout.accepts(baseRecord)
		let headAccepts = layout.accepts(headRecord)
		switch (baseAccepts, headAccepts) {
		case (true, true):
			return .accepted(base: layout.generatedFiles(of: baseRecord), head: layout.generatedFiles(of: headRecord))
		case (false, false):
			return .ended(.skipped(.rejectedByBoth))
		case (true, false), (false, true):
			return .ended(.finding(.acceptanceDiffers(base: baseAccepts, head: headAccepts, fixture: fixtureName)))
		}
	}
}

extension GraphFuzzerBaseComparison.Layout {
	/// Whether every step of the flow ran and succeeded.
	func accepts(_ record: GraphFuzzerBaseComparison.Record) -> Bool {
		record.steps.count == commands.count && record.steps.allSatisfy { $0.exitCode == 0 }
	}

	/// The Swift files `record`'s steps generated, keyed as the fuzzer's own runs key them: a graph in one module by the
	/// name the plugin flow gives each file, and a graph split across modules by its module's name and the name of each
	/// file its combined output decomposes into (`GraphFuzzerOracle.decomposingCombinedOutput`).
	func generatedFiles(of record: GraphFuzzerBaseComparison.Record) -> [String: String] {
		var files = [String: String]()
		for (path, data) in record.outputs where path.hasPrefix("Output/") && path.hasSuffix(".swift") {
			let fileName = String(path.dropFirst("Output/".count))
			let contents = String(decoding: data, as: UTF8.self)
			switch flow {
			case .plugin:
				files[fileName] = contents
			case .moduleInfo:
				let moduleName = String(fileName.dropLast(".swift".count))
				for (decomposedName, decomposedContents) in GraphFuzzerOracle.decomposingCombinedOutput(contents) {
					files["\(moduleName)/\(decomposedName)"] = decomposedContents
				}
			}
		}
		return files
	}
}
