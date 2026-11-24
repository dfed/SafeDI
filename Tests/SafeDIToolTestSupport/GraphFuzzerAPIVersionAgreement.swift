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

// MARK: - API version agreement

/// The form of mock API a graph's `#SafeDIConfiguration(apiVersion:)` selects, as the fixture spells it.
enum GraphFuzzerAPIVersion: String, CaseIterable, Sendable {
	case v2
	case v3Unstable
}

extension GraphFuzzerFixture {
	/// The graph with `generateMock: true` on every `final class` the graph declares with `@Instantiable` that neither
	/// generates a mock nor is only a mock, so that every type's mock is compared under both API versions. A file that
	/// holds a hand-written `mock` or names a `customMockName` is left as it is, since a generated mock beside it would
	/// collide with it.
	var mockingEveryClass: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: seed, swiftFileContent: swiftFileContent.map { content in
			guard !content.contains("func mock("), !content.contains("customMockName") else { return content }
			var lines = content.components(separatedBy: "\n")
			for index in lines.indices.dropLast() where lines[index].hasPrefix("@Instantiable") && lines[index + 1].contains("final class ") {
				let attribute = lines[index]
				guard !attribute.contains("generateMock"), !attribute.contains("mockOnly") else { continue }
				if attribute == "@Instantiable" {
					lines[index] = "@Instantiable(generateMock: true)"
				} else if attribute.hasPrefix("@Instantiable("), attribute.hasSuffix(")") {
					lines[index] = String(attribute.dropLast()) + ", generateMock: true)"
				}
			}
			return lines.joined(separator: "\n")
		})
	}

	/// The graph with its module selecting `version`: the argument added to the `#SafeDIConfiguration` the graph
	/// declares, or a configuration of its own after the first file's declarations. A graph in one module only.
	func selectingAPIVersion(_ version: GraphFuzzerAPIVersion) -> GraphFuzzerFixture {
		let argument = "apiVersion: .\(version.rawValue)"
		var contents = swiftFileContent
		if let index = contents.firstIndex(where: { $0.contains("#SafeDIConfiguration(") }) {
			var lines = contents[index].components(separatedBy: "\n")
			for lineIndex in lines.indices where lines[lineIndex].hasPrefix("#SafeDIConfiguration(") {
				let line = lines[lineIndex]
				lines[lineIndex] = line.hasSuffix("()") ? "#SafeDIConfiguration(\(argument))" : String(line.dropLast()) + ", \(argument))"
				break
			}
			contents[index] = lines.joined(separator: "\n")
		} else if !contents.isEmpty {
			contents[0] += "\n#SafeDIConfiguration(\(argument))\n"
		}
		return GraphFuzzerFixture(seed: seed, swiftFileContent: contents)
	}

	/// The names of the types `addingDependenciesMocksCannotBuild` drew, which are not `@Instantiable`, so a mock takes
	/// each instance its tree instantiates as a parameter.
	var unbuildableTypeNames: [String] {
		(0..<10).map { "\(typeNamePrefix)Unbuildable\($0)" }.filter { name in
			swiftFileContent.contains { $0.contains("public final class \(name)") }
		}
	}

	/// The name of the counter the twin's unbuildable types count their initializations with.
	var unbuildableInitializationCounterName: String {
		"\(typeNamePrefix)UnbuildableInitializations"
	}

	/// The name of the class a D12 probe counts the calls of the builders it passes with.
	var unbuildableBuilderCallsName: String {
		"\(typeNamePrefix)UnbuildableBuilderCalls"
	}

	/// The graph with each type a mock cannot build (`unbuildableTypeNames`) made `@Instantiable` with an initializer
	/// that counts its calls, so that a mock builds each instance itself, once at each place that creates one, as
	/// production builds an `@Instantiable` type: the known-right path of the D12 per-instance oracle. `nil` when the graph
	/// draws no such type.
	var makingUnbuildableTypesInstantiable: GraphFuzzerFixture? {
		let names = unbuildableTypeNames
		guard !names.isEmpty else { return nil }
		let initializer = "\tpublic init() {\n\t\t\(unbuildableInitializationCounterName).count += 1\n\t}"
		let contents = swiftFileContent.map { content in
			content.components(separatedBy: "\n").map { line in
				for name in names {
					for (header, isSendable) in [("public final class \(name): Sendable {", true), ("public final class \(name) {", false)] where line.hasPrefix(header) {
						let declaration = "@Instantiable\npublic final class \(name): Instantiable\(isSendable ? ", Sendable" : "") {\n\(initializer)"
						// A declaration on one line, `{}`, closes its body on it.
						return line == header + "}" ? declaration + "\n}" : declaration + "\n"
					}
				}
				return line
			}.joined(separator: "\n")
		}
		return GraphFuzzerFixture(seed: seed, swiftFileContent: contents + [Self.counterSource(named: unbuildableInitializationCounterName)])
	}

	/// The name of the type `addingTwiceBuiltUnbuildableOwner` adds.
	var twiceBuiltUnbuildableOwnerHostName: String {
		"\(typeNamePrefix)ZTwiceHost"
	}

	/// The graph with a mocked type of its own, `ZTwiceHost`, that builds the first type instantiating a dependency a mock
	/// cannot build (`unbuildableTypeNames`) through an `Instantiator`, which the value comparator calls twice: so a mock
	/// of the host builds that owner twice, and a `.v3Unstable` mock that calls the builder it takes for the dependency
	/// once and hands both owners its value differs from the twin, whose owners each build their own. The graph as drawn
	/// where no such owner forwards nothing. Its name sorts after every type of the graph, and nothing else names it, so
	/// every other mock is generated as before.
	var addingTwiceBuiltUnbuildableOwner: GraphFuzzerFixture {
		let unbuildable = Set(unbuildableTypeNames)
		guard !unbuildable.isEmpty else { return self }
		var ownerName: String?
		search: for content in swiftFileContent where !content.contains("@Forwarded") {
			var currentClassName: String?
			for line in content.components(separatedBy: "\n") {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				if trimmed.hasPrefix("public final class "), let name = trimmed.dropFirst("public final class ".count).split(whereSeparator: { $0 == ":" || $0 == " " || $0 == "{" }).first {
					currentClassName = String(name)
				} else if trimmed.hasPrefix("@Instantiated let "), let type = trimmed.split(separator: ":").last?.trimmingCharacters(in: .whitespaces), unbuildable.contains(type), let currentClassName {
					ownerName = currentClassName
					break search
				}
			}
		}
		guard let ownerName else { return self }
		let host = twiceBuiltUnbuildableOwnerHostName
		return GraphFuzzerFixture(seed: seed, swiftFileContent: swiftFileContent + [
			"""
			@Instantiable(generateMock: true)
			public final class \(host): Instantiable {
			\tlet differentialValueCreationStamp = \(typeNamePrefix)CreationStamp.next()

			\tpublic init(zTwiceOwnerBuilder: Instantiator<\(ownerName)>) {
			\t\tself.zTwiceOwnerBuilder = zTwiceOwnerBuilder
			\t}

			\t@Instantiated let zTwiceOwnerBuilder: Instantiator<\(ownerName)>
			}

			""",
		])
	}

	/// The graph with the class a D12 probe counts its builders' calls with: the feature path of the D12 per-instance
	/// oracle.
	var declaringUnbuildableBuilderCalls: GraphFuzzerFixture {
		GraphFuzzerFixture(seed: seed, swiftFileContent: swiftFileContent + [
			"// file: \(unbuildableBuilderCallsName).swift\n\npublic final class \(unbuildableBuilderCallsName): @unchecked Sendable {\n\tpublic init() {}\n\n\tpublic var count = 0\n}\n",
		])
	}

	private static func counterSource(named name: String) -> String {
		"// file: \(name).swift\n\npublic enum \(name) {\n\tnonisolated(unsafe) public static var count = 0\n}\n"
	}

	/// The D12 probes of the graph's `.v3Unstable` generated files: each generated mock whose every required parameter
	/// is a builder of a type the mock cannot build (`label: @escaping () -> T`), called with builders that count their
	/// calls and build a new instance each, beside the same mock of the twin that makes those types `@Instantiable`,
	/// which builds each instance itself (`makingUnbuildableTypesInstantiable`). Each probe's value is the mock's value
	/// and how many instances it built, so the two agree only when the mock calls its builder once per instance and
	/// puts each instance where production would put an instance it builds.
	func unbuildableBuilderProbes(v3GeneratedFiles: [String: String]) -> [DifferentialValueProbe] {
		let unbuildable = Set(unbuildableTypeNames)
		let mockFileSuffix = "+SafeDIMock.swift"
		var probes = [DifferentialValueProbe]()
		for (fileName, contents) in v3GeneratedFiles.sorted(by: { $0.key < $1.key }) where fileName.hasSuffix(mockFileSuffix) {
			let required = GraphFuzzerMockOverrides.requiredParameters(contents)
			guard !required.isEmpty else { continue }
			let builders = required.compactMap { parameter -> (label: String, type: String)? in
				let type = parameter.type.replacingOccurrences(of: "@Sendable ", with: "")
				guard type.hasPrefix("() -> ") else { return nil }
				let builtType = String(type.dropFirst("() -> ".count))
				return unbuildable.contains(builtType) ? (parameter.label, builtType) : nil
			}
			guard builders.count == required.count else { continue }
			let mockedType = String(fileName.dropLast(mockFileSuffix.count).split(separator: "/").last ?? "")
			let arguments = builders.map { "\($0.label): { calls.count += 1; return \($0.type)() }" }.joined(separator: ", ")
			probes.append(DifferentialValueProbe(
				name: "\(mockedType).mock(\(builders.map { "\($0.label): builder" }.joined(separator: ", ")))",
				expression: "{ () -> (Any, Int) in let calls = \(unbuildableBuilderCallsName)(); let value = \(mockedType).mock(\(arguments)); return (value, calls.count) }()",
				knownRightExpression: "{ () -> (Any, Int) in let before = \(unbuildableInitializationCounterName).count; let value = \(mockedType).mock(); return (value, \(unbuildableInitializationCounterName).count - before) }()",
			))
		}
		return probes
	}
}

/// The v2/v3 value-agreement oracle and the D12 per-instance oracle, over the base corpus.
///
/// Each seed's graph, drawn storing every parameter with every class mocked (`mockingEveryClass`), runs through this
/// tree's tool twice, as drawn (`.v2`) and selecting `.v3Unstable` (`selectingAPIVersion`), and each side's generated
/// code compiles with the fixture as release acceptance compiles it (`GraphFuzzerReleaseAcceptance.run`). The verdict
/// reuses release acceptance's classes, with `.v2` as the older release and `.v3Unstable` as this tree: A, `.v2` rejects
/// the graph; C, only `.v3Unstable` rejects it; D, only its code does not compile; E, only its code draws a warning; F,
/// a root or a mock both generate builds other values; B, every probe agrees. Every mock probe calls `mock()` with no
/// argument, so it compares the two API versions' defaults: what each mock builds when nothing is configured.
///
/// Where `.v3Unstable` takes a builder for a dependency the mock cannot build, the D12 per-instance oracle calls that
/// mock with builders that build a new instance per call (`unbuildableBuilderProbes`), against the twin graph that makes
/// the type `@Instantiable` (`makingUnbuildableTypesInstantiable`): a difference, in the values or in how many instances
/// were built, is class F too, with the probe named `T.mock(label: builder)`.
enum GraphFuzzerAPIVersionAgreement {
	/// One seed's verdict, and how many D12 probes it compared.
	struct SeedVerdict {
		let seed: UInt64
		var verdict: GraphFuzzerReleaseVerdict
		var unbuildableBuilderProbeCount = 0
	}

	/// The fixture both sides start from: the base corpus graph drawn storing every parameter, with every class mocked.
	static func fixture(forSeed seed: UInt64) -> GraphFuzzerFixture {
		GraphFuzzerGenerator.fixture(forSeed: seed, storingEveryParameter: true).mockingEveryClass.addingTwiceBuiltUnbuildableOwner
	}

	/// Judges `seeds`, running the graphs of each batch concurrently and comparing a batch's values in one comparison;
	/// a graph whose probe spends the batch's traversals is compared again on its own under
	/// `DifferentialValueLimits.isolatedFuzzerGraph`. The verdicts are in seed order.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func verdicts(
		forSeeds seeds: [UInt64],
		batchSize: Int = 25,
		batchLimits: DifferentialValueLimits = DifferentialValueLimits(),
	) async throws -> [SeedVerdict] {
		await ProcessSlots.shared.takePlaceInLine(for: Test.current?.id)
		let batches = stride(from: 0, to: seeds.count, by: batchSize).map { Array(seeds[$0..<min($0 + batchSize, seeds.count)]) }
		var verdicts = [SeedVerdict]()
		try await withThrowingTaskGroup(of: [SeedVerdict].self) { group in
			for batch in batches {
				group.addTask {
					try await batchVerdicts(forSeeds: batch, limits: batchLimits)
				}
			}
			for try await batchVerdicts in group {
				verdicts += batchVerdicts
			}
		}
		return verdicts.sorted { $0.seed < $1.seed }
	}

	private struct SeedRun {
		let seed: UInt64
		let classification: GraphFuzzerReleaseClassification
		let graphs: [DifferentialValueGraph]
		let unbuildableBuilderProbeCount: Int
		let filesToDelete: [URL]
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func seedRun(_ seed: UInt64) async throws -> SeedRun {
		var filesToDelete = [URL]()
		let v2Fixture = fixture(forSeed: seed)
		let v3Fixture = v2Fixture.declaringUnbuildableBuilderCalls.selectingAPIVersion(.v3Unstable)
		let v2Run = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: v2Fixture, filesToDelete: &filesToDelete)
		let v3Run = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: v3Fixture, filesToDelete: &filesToDelete)
		let classification = GraphFuzzerReleaseAcceptance.classify(older: v2Run, current: v3Run) { v2Fixture.differentialValueProbes(generatedFiles: $0.filter { !$0.key.hasSuffix("+SafeDIMock.swift") || $0.value.contains("static func mock(") }) }
		// `SAFEDI_API_VERSION_AGREEMENT_DUMP` names a directory to write each seed's `.v3Unstable` fixture, both sides'
		// generated files and their compiles' output into, to read a disagreement by hand.
		if let dump = ProcessInfo.processInfo.environment["SAFEDI_API_VERSION_AGREEMENT_DUMP"] {
			let directory = URL(fileURLWithPath: dump).appendingPathComponent("\(seed)")
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			for (index, content) in v3Fixture.swiftFileContent.enumerated() {
				try? content.write(to: directory.appendingPathComponent("fixture-\(index).swift"), atomically: true, encoding: .utf8)
			}
			for (version, run) in [("v2", v2Run), ("v3", v3Run)] {
				switch run.outcome {
				case let .rejected(diagnostics): try? diagnostics.write(to: directory.appendingPathComponent("\(version)-rejected.txt"), atomically: true, encoding: .utf8)
				case let .compiled(files, _, compilation):
					for (name, content) in files {
						try? content.write(to: directory.appendingPathComponent("\(version)-" + name.replacingOccurrences(of: "/", with: "_")), atomically: true, encoding: .utf8)
					}
					try? compilation.stderr.write(to: directory.appendingPathComponent("\(version)-stderr.txt"), atomically: true, encoding: .utf8)
				}
			}
		}
		guard case let .comparesValues(_, probes) = classification,
		      case let .compiled(v2GeneratedFiles, _, _) = v2Run.outcome,
		      case let .compiled(v3GeneratedFiles, _, _) = v3Run.outcome
		else {
			return SeedRun(seed: seed, classification: classification, graphs: [], unbuildableBuilderProbeCount: 0, filesToDelete: filesToDelete)
		}
		let samples = GraphFuzzerReleaseAcceptanceCorpus.base.forwardedPropertiesSamples(of: v2Fixture)
		var graphs = [DifferentialValueGraph(
			name: "seed \(seed)",
			feature: DifferentialValuePath(fixture: v3Fixture, generatedFiles: v3GeneratedFiles),
			knownRight: DifferentialValuePath(fixture: v2Fixture, generatedFiles: v2GeneratedFiles),
			probes: probes,
			samples: samples,
		)]
		var unbuildableBuilderProbeCount = 0
		let unbuildableBuilderProbes = v3Fixture.unbuildableBuilderProbes(v3GeneratedFiles: v3GeneratedFiles)
		if !unbuildableBuilderProbes.isEmpty, let twin = v2Fixture.makingUnbuildableTypesInstantiable?.selectingAPIVersion(.v3Unstable) {
			let twinRun = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: twin, filesToDelete: &filesToDelete)
			switch twinRun.outcome {
			case let .compiled(twinGeneratedFiles, _, compilation) where compilation.exitCode == 0:
				unbuildableBuilderProbeCount = unbuildableBuilderProbes.count
				graphs.append(DifferentialValueGraph(
					name: "seed \(seed) D12",
					feature: DifferentialValuePath(fixture: v3Fixture, generatedFiles: v3GeneratedFiles),
					knownRight: DifferentialValuePath(fixture: twin, generatedFiles: twinGeneratedFiles),
					probes: unbuildableBuilderProbes,
					samples: samples,
				))
			case .compiled, .rejected:
				// The twin is the known-right path: one the tool rejects, or whose code does not compile, judges nothing.
				break
			}
		}
		return SeedRun(seed: seed, classification: classification, graphs: graphs, unbuildableBuilderProbeCount: unbuildableBuilderProbeCount, filesToDelete: filesToDelete)
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func batchVerdicts(forSeeds seeds: [UInt64], limits: DifferentialValueLimits) async throws -> [SeedVerdict] {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let runs = try await withThrowingTaskGroup(of: SeedRun.self) { group in
			for seed in seeds {
				group.addTask { try await seedRun(seed) }
			}
			var runs = [SeedRun]()
			for try await run in group {
				filesToDelete += run.filesToDelete
				runs.append(run)
			}
			return runs.sorted { $0.seed < $1.seed }
		}
		let graphs = runs.flatMap(\.graphs)
		let comparisons = graphs.isEmpty ? [] : try await DifferentialValueOracle.compare(graphs: graphs, limits: limits, filesToDelete: &filesToDelete) ?? []
		var comparisonByName = [String: Result<DifferentialValueComparison, DifferentialValueOracleError>]()
		for comparison in comparisons {
			comparisonByName[comparison.name] = comparison.result
		}
		// A graph whose probe spent the batch's traversals is compared again on its own, as release acceptance does.
		for graph in graphs {
			guard case let .failure(error) = comparisonByName[graph.name], error.spentTraversals else { continue }
			if let result = try await DifferentialValueOracle.compare(graphs: [graph], limits: .isolatedFuzzerGraph, filesToDelete: &filesToDelete)?.first?.result {
				comparisonByName[graph.name] = result
			}
		}
		return runs.map { run in
			switch run.classification {
			case let .decided(verdict):
				return SeedVerdict(seed: run.seed, verdict: verdict)
			case let .comparesValues(verdict, _):
				var verdict = verdict
				for graph in run.graphs {
					guard let result = comparisonByName[graph.name] else {
						verdict.verdictClass = .valuesNotCompared
						verdict.details = "The comparator returned no comparison: compile verification is off (SAFEDI_SKIP_COMPILE_CHECK)."
						break
					}
					let judged = GraphFuzzerReleaseAcceptance.verdict(verdict, comparing: result)
					// The first graph that does not agree decides; the D12 graph's details name its probes.
					if judged.verdictClass != .valuesAgree || verdict.verdictClass != .valuesAgree, verdict.verdictClass == .valuesAgree {
						verdict = judged
					}
				}
				return SeedVerdict(seed: run.seed, verdict: verdict, unbuildableBuilderProbeCount: run.unbuildableBuilderProbeCount)
			}
		}
	}
}

extension GraphFuzzerAPIVersionAgreement {
	/// Seeds whose `.v3Unstable` mocks do not compile yet, by the shape the v3 work has still to lower. The long run expects
	/// each to be `.currentDoesNotCompile` and reports one that agrees as stale, so the step that lowers a shape removes
	/// its seeds.
	struct PendingShape: Sendable {
		let reason: String
		let seeds: [UInt64]
	}

	static let pendingShapes = [
		PendingShape(
			reason: "A `@Sendable` function captures the mocked type's `SafeDIOverrides`, which is not `Sendable`",
			seeds: [55, 74, 78, 116, 184, 185, 204, 295],
		),
	]

	/// The reason `seed` is pending, if it is.
	static func pendingReason(ofSeed seed: UInt64) -> String? {
		pendingShapes.first { $0.seeds.contains(seed) }?.reason
	}

	/// Seeds of the ordinary suite's gate: graphs whose `.v2` and `.v3Unstable` mocks agree, together holding at least ten
	/// compared graphs and ten D12 probes. A hand mutation that has `.v3Unstable` pass `nil` to the mocked type's receives
	/// only if available fails seeds 23, 85 and 88 as values that differ; one whose `.v3Unstable` builder of an unbuildable
	/// dependency is called twice per instance fails seeds 2, 7, 13, 45, 62, 73 and 90 in their D12 graphs; one whose
	/// builder is called once and its value handed to every instance fails seeds 2, 7, 13, 45, 62 and 73, whose
	/// `ZTwiceHost` builds the owner twice (`addingTwiceBuiltUnbuildableOwner`).
	static let smokeSeeds: [UInt64] = [2, 7, 13, 23, 45, 62, 64, 73, 85, 88, 90, 117]
}
