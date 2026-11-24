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

	/// The graph with every module selecting `version`, since the tool requires one API version across the modules it
	/// reads: the argument added to the `#SafeDIConfiguration` a module declares, or a configuration of its own after the
	/// declarations of the module's first file. A file of a split graph that names no module is the same-package
	/// caller's, as `enablingPlainDependencyTreeInitializers(in:)` reads it.
	func selectingAPIVersion(_ version: GraphFuzzerAPIVersion) -> GraphFuzzerFixture {
		let argument = "apiVersion: .\(version.rawValue)"
		let isSplit = swiftFileContent.contains { GraphFuzzerModule(declaredIn: $0) != nil }
		var moduleOrder = [GraphFuzzerModule?]()
		var indicesByModule = [GraphFuzzerModule?: [Int]]()
		for (index, content) in swiftFileContent.enumerated() {
			let module: GraphFuzzerModule? = isSplit ? (GraphFuzzerModule(declaredIn: content) ?? .samePackageCaller) : nil
			if indicesByModule[module] == nil {
				moduleOrder.append(module)
			}
			indicesByModule[module, default: []].append(index)
		}
		var contents = swiftFileContent
		for module in moduleOrder {
			let indices = indicesByModule[module] ?? []
			if let index = indices.first(where: { contents[$0].contains("#SafeDIConfiguration(") }) {
				var lines = contents[index].components(separatedBy: "\n")
				for lineIndex in lines.indices where lines[lineIndex].hasPrefix("#SafeDIConfiguration(") {
					let line = lines[lineIndex]
					lines[lineIndex] = line.hasSuffix("()") ? "#SafeDIConfiguration(\(argument))" : String(line.dropLast()) + ", \(argument))"
					break
				}
				contents[index] = lines.joined(separator: "\n")
			} else if let index = indices.first {
				contents[index] += "\n#SafeDIConfiguration(\(argument))\n"
			}
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

	/// The fixture both sides start from: the corpus's graph drawn storing every parameter. A base corpus graph also has
	/// every class mocked and a type that builds an owner of an unbuildable dependency twice; a public mock corpus graph
	/// is drawn as it is, since its mocks are what the corpus draws.
	static func fixture(forSeed seed: UInt64, in corpus: GraphFuzzerReleaseAcceptanceCorpus = .base) -> GraphFuzzerFixture {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: corpus.features, storingEveryParameter: true)
		switch corpus {
		case .base:
			return fixture.mockingEveryClass.addingTwiceBuiltUnbuildableOwner
		case .seam, .publicMock:
			return fixture
		}
	}

	/// Judges `seeds`, running the graphs of each batch concurrently and comparing a batch's values in one comparison;
	/// a graph whose probe spends the batch's traversals is compared again on its own under
	/// `DifferentialValueLimits.isolatedFuzzerGraph`. The verdicts are in seed order.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func verdicts(
		forSeeds seeds: [UInt64],
		of corpus: GraphFuzzerReleaseAcceptanceCorpus = .base,
		batchSize: Int = 25,
		batchLimits: DifferentialValueLimits = DifferentialValueLimits(),
	) async throws -> [SeedVerdict] {
		await ProcessSlots.shared.takePlaceInLine(for: Test.current?.id)
		let batches = stride(from: 0, to: seeds.count, by: batchSize).map { Array(seeds[$0..<min($0 + batchSize, seeds.count)]) }
		var verdicts = [SeedVerdict]()
		try await withThrowingTaskGroup(of: [SeedVerdict].self) { group in
			for batch in batches {
				group.addTask {
					try await batchVerdicts(forSeeds: batch, of: corpus, limits: batchLimits)
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
	private static func seedRun(_ seed: UInt64, of corpus: GraphFuzzerReleaseAcceptanceCorpus) async throws -> SeedRun {
		var filesToDelete = [URL]()
		let v2Fixture = fixture(forSeed: seed, in: corpus)
		// Only the base corpus draws the dependencies a mock cannot build that the D12 probes call with builders.
		let judgesUnbuildableBuilders = corpus == .base
		let v3Fixture = (judgesUnbuildableBuilders ? v2Fixture.declaringUnbuildableBuilderCalls : v2Fixture).selectingAPIVersion(.v3Unstable)
		let v2Run = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: v2Fixture, filesToDelete: &filesToDelete)
		let v3Run = try await GraphFuzzerReleaseAcceptance.run(.currentTree, over: v3Fixture, filesToDelete: &filesToDelete)
		let classification = GraphFuzzerReleaseAcceptance.classify(older: v2Run, current: v3Run) { v2Fixture.differentialValueProbes(generatedFiles: $0.filter { !$0.key.hasSuffix("+SafeDIMock.swift") || $0.value.contains("static func mock(") }).map(Self.callingV3Mock(_:)) }
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
		let samples = corpus.forwardedPropertiesSamples(of: v2Fixture)
		var graphs = [DifferentialValueGraph(
			name: "seed \(seed)",
			feature: DifferentialValuePath(fixture: v3Fixture, generatedFiles: v3GeneratedFiles),
			knownRight: DifferentialValuePath(fixture: v2Fixture, generatedFiles: v2GeneratedFiles),
			probes: probes,
			samples: samples,
		)]
		var unbuildableBuilderProbeCount = 0
		let unbuildableBuilderProbes = judgesUnbuildableBuilders ? v3Fixture.unbuildableBuilderProbes(v3GeneratedFiles: v3GeneratedFiles) : []
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

	/// `probe` with its `.v3Unstable` side passing what a `.v2` probe hands a mock as `.v3Unstable` takes it: a mock's own
	/// optional default, `T.mock(name: v)`, in its overrides, `T.mock(safeDIOverrides: .init(name: v))`, and a value the
	/// mock cannot build, `T.mock(label: v)`, as a builder, `T.mock(label: { v })` (D12). Every other probe calls `mock()`
	/// with no argument, or a root, and is left as it is. The `.v2` side calls the mock as the probe does.
	static func callingV3Mock(_ probe: DifferentialValueProbe) -> DifferentialValueProbe {
		let expression = probe.expression
		guard probe.knownRightExpression == nil,
		      expression.hasSuffix(")"),
		      let call = expression.range(of: ".mock("),
		      let colon = expression[call.upperBound...].range(of: ": ")
		else { return probe }
		let label = expression[call.upperBound..<colon.lowerBound]
		guard !label.isEmpty, label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return probe }
		let value = expression[colon.upperBound..<expression.index(before: expression.endIndex)]
		let callee = expression[..<call.upperBound]
		let v3Expression = label == "name" ? "\(callee)safeDIOverrides: .init(name: \(value)))" : "\(callee)\(label): { \(value) })"
		return DifferentialValueProbe(name: probe.name, expression: v3Expression, knownRightExpression: expression)
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func batchVerdicts(forSeeds seeds: [UInt64], of corpus: GraphFuzzerReleaseAcceptanceCorpus, limits: DifferentialValueLimits) async throws -> [SeedVerdict] {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let runs = try await withThrowingTaskGroup(of: SeedRun.self) { group in
			for seed in seeds {
				group.addTask { try await seedRun(seed, of: corpus) }
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

	static let pendingShapes: [PendingShape] = []

	/// The public mock corpus's pending seeds, one entry per first error of the `.v3Unstable` side, as a run of seeds
	/// `0..<1000` on e602503 classed them (class D, generated code that does not compile, but for the shared-construction
	/// entry, class C).
	static let publicMockPendingShapes = [
		PendingShape(
			reason: "A consumer's `.v3Unstable` mock reads its own property `tN` as a static member (`instance member tN cannot be used on type T7/T8`)",
			seeds: [0, 5, 17, 21, 25, 29, 67, 80, 91, 94, 95, 97, 98, 105, 110, 114, 125, 133, 147, 149, 169, 202, 215, 217, 234, 237, 249, 269, 276, 290, 295, 321, 324, 328, 375, 376, 378, 382, 393, 408, 419, 437, 464, 472, 486, 496, 529, 554, 569, 578, 582, 590, 596, 603, 626, 672, 683, 704, 706, 714, 718, 726, 736, 756, 759, 773, 793, 810, 857, 860, 862, 868, 871, 873, 888, 889, 900, 913, 924, 925, 939, 949, 950, 955, 960, 972, 990],
		),
		PendingShape(
			reason: "A mock names `HoleHost.SafeDIOverrides`, which `HoleHost` does not declare",
			seeds: [2, 12, 18, 22, 37, 56, 65, 83, 88, 92, 101, 137, 151, 167, 211, 221, 225, 281, 313, 326, 330, 344, 386, 424, 459, 474, 542, 561, 565, 584, 587, 591, 597, 629, 653, 658, 663, 677, 681, 708, 723, 724, 748, 797, 814, 824, 833, 863, 886, 909, 983],
		),
		PendingShape(
			reason: "A mock names `SelfStep.SafeDIOverrides`, which `SelfStep` does not declare",
			seeds: [3, 47, 55, 60, 99, 104, 112, 124, 194, 195, 213, 231, 233, 243, 265, 267, 268, 271, 287, 340, 353, 388, 401, 412, 429, 452, 494, 551, 572, 594, 595, 618, 627, 699, 737, 768, 776, 787, 823, 825, 883, 884, 897, 934, 944],
		),
		PendingShape(
			reason: "A call hands a module-level configuration where `SelfNode.SafeDIOverrides` is expected",
			seeds: [4, 8, 13, 24, 42, 43, 44, 69, 77, 87, 115, 130, 138, 146, 177, 178, 192, 196, 200, 226, 227, 239, 256, 257, 270, 273, 289, 297, 300, 307, 309, 314, 337, 342, 346, 349, 361, 368, 369, 379, 392, 413, 418, 421, 431, 434, 442, 453, 467, 481, 484, 488, 516, 522, 526, 532, 536, 540, 543, 550, 571, 580, 605, 622, 624, 639, 642, 651, 670, 671, 679, 691, 711, 739, 741, 753, 767, 770, 775, 783, 784, 789, 801, 803, 806, 807, 839, 845, 850, 851, 854, 861, 865, 880, 896, 899, 902, 903, 910, 911, 912, 915, 926, 943, 946, 951, 958, 959, 961, 962, 963, 965, 969, 978, 991],
		),
		PendingShape(
			reason: "A call passes the hole builder `HoleProtocolBuilder` that the called mock does not take",
			seeds: [10, 73, 150, 219, 228, 310, 316, 318, 331, 420, 427, 513, 563, 593, 604, 666, 765, 812, 827, 853, 881, 885, 917],
		),
		PendingShape(
			reason: "A self-building public mock reads `.instance` of an optional `Instantiator` (`Instantiator<SelfNode>? has no member instance`)",
			seeds: [15, 28, 33, 48, 49, 54, 57, 58, 62, 63, 64, 75, 84, 103, 109, 122, 129, 136, 160, 162, 165, 171, 181, 183, 185, 186, 190, 199, 204, 207, 223, 224, 238, 242, 244, 245, 248, 261, 266, 274, 277, 280, 282, 283, 285, 296, 302, 304, 312, 319, 327, 333, 335, 336, 347, 350, 351, 352, 360, 366, 371, 383, 387, 389, 395, 398, 411, 416, 423, 428, 433, 438, 441, 445, 455, 456, 465, 466, 468, 471, 477, 482, 507, 510, 519, 521, 525, 527, 528, 539, 541, 556, 559, 575, 576, 589, 602, 606, 608, 610, 632, 640, 643, 646, 647, 659, 660, 664, 669, 678, 685, 692, 693, 701, 703, 713, 717, 730, 731, 733, 734, 735, 757, 766, 772, 777, 778, 799, 820, 821, 828, 840, 846, 847, 848, 849, 852, 872, 879, 891, 898, 927, 931, 935, 940, 941, 947, 953, 971, 973, 974, 975, 979, 985, 989, 992, 998],
		),
		PendingShape(
			reason: "A call passes the erased hole builder `HoleFill_S_AnyHoleBuilder` that the called mock does not take",
			seeds: [19, 20, 34, 89, 93, 108, 168, 176, 180, 197, 210, 229, 311, 372, 415, 436, 469, 499, 500, 547, 581, 592, 601, 611, 614, 631, 636, 695, 728, 781, 798, 804, 830, 844, 866, 875, 895, 942, 996],
		),
		PendingShape(
			reason: "A `.v3Unstable` mock names a module-level configuration nothing declares",
			seeds: [23, 26, 36, 41, 46, 53, 70, 78, 90, 111, 127, 128, 134, 145, 154, 175, 187, 201, 216, 218, 220, 246, 252, 259, 275, 284, 288, 292, 294, 299, 301, 315, 338, 339, 343, 355, 365, 374, 377, 380, 391, 399, 425, 460, 490, 504, 506, 508, 509, 511, 520, 523, 546, 557, 600, 641, 648, 676, 684, 696, 719, 720, 740, 745, 758, 771, 774, 790, 795, 800, 818, 832, 867, 869, 882, 914, 932, 964, 966, 976, 987],
		),
		PendingShape(
			reason: "A call labels the hole builder `sN_HoleBuilder` where the called mock takes `holeBuilder`",
			seeds: [35],
		),
		PendingShape(
			reason: "A `@Sendable` function captures a non-`Sendable` module-level configuration (`tNBuilderConfiguration`)",
			seeds: [39, 45, 81, 132, 164, 279, 293, 364, 384, 470, 560, 567, 780, 858],
		),
		PendingShape(
			reason: "A call passes the `@Sendable` hole builder `HoleSendableBuilder` that the called mock does not take",
			seeds: [59, 716],
		),
		PendingShape(
			reason: "`.v3Unstable` rejects the shared-construction draw, `ShareService` built with its hand-written mock and its initializer under one configuration, which `.v2` accepts",
			seeds: [66, 96, 131, 148, 161, 184, 214, 260, 263, 325, 332, 341, 348, 356, 397, 405, 406, 407, 409, 432, 448, 478, 498, 538, 558, 566, 570, 574, 583, 598, 599, 612, 616, 619, 649, 661, 697, 707, 721, 727, 751, 755, 779, 786, 794, 805, 819, 836, 838, 841, 859, 864, 870, 887, 901, 907, 930, 982, 993],
		),
		PendingShape(
			reason: "A `.v3Unstable` configuration evaluates a main actor-isolated default in a nonisolated context",
			seeds: [79, 152, 188, 240, 247, 272, 381, 390, 396, 444, 483, 485, 585, 615, 621, 623, 650, 662, 668, 689, 702, 725, 744, 749, 754, 816, 834, 919, 977, 995],
		),
		PendingShape(
			reason: "A mock reads `.instance` of an optional `T1` or `HoleHost`",
			seeds: [106, 306, 322, 514, 680, 747],
		),
		PendingShape(
			reason: "A call passes the hole builder `HoleBuilder` that the called mock does not take",
			seeds: [107, 117, 119, 166, 230, 251, 262, 402, 417, 435, 449, 463, 489, 497, 562, 634, 635, 644, 743, 876, 892, 904, 906, 936],
		),
		PendingShape(
			reason: "A self-building public mock reads `.instance` of an optional `SendableInstantiator`",
			seeds: [143, 156, 189, 222, 250, 264, 308, 317, 370, 394, 479, 537, 564, 652, 673, 715, 918, 923],
		),
		PendingShape(
			reason: "A `.v3Unstable` mock reads a default provider `defaultCapacity` nothing declares",
			seeds: [258],
		),
		PendingShape(
			reason: "A `.v3Unstable` mock's expression is ambiguous without a type annotation",
			seeds: [320],
		),
		PendingShape(
			reason: "A mock reads `.instance` of an optional `T0`",
			seeds: [524, 630],
		),
		PendingShape(
			reason: "A call of a `.v3Unstable` public mock matches no `mock` overload",
			seeds: [577],
		),
	]

	/// The pending shapes of `corpus`.
	static func pendingShapes(of corpus: GraphFuzzerReleaseAcceptanceCorpus) -> [PendingShape] {
		switch corpus {
		case .base:
			pendingShapes
		case .publicMock:
			publicMockPendingShapes
		case .seam:
			[]
		}
	}

	/// The reason `seed` of `corpus` is pending, if it is.
	static func pendingReason(ofSeed seed: UInt64, in corpus: GraphFuzzerReleaseAcceptanceCorpus = .base) -> String? {
		pendingShapes(of: corpus).first { $0.seeds.contains(seed) }?.reason
	}

	/// Seeds of the ordinary suite's gate: graphs whose `.v2` and `.v3Unstable` mocks agree, together holding at least ten
	/// compared graphs and ten D12 probes. A hand mutation that has `.v3Unstable` pass `nil` to the mocked type's receives
	/// only if available fails seeds 23, 85 and 88 as values that differ; one whose `.v3Unstable` builder of an unbuildable
	/// dependency is called twice per instance fails seeds 2, 7, 13, 45, 62, 73 and 90 in their D12 graphs; one whose
	/// builder is called once and its value handed to every instance fails seeds 2, 7, 13, 45, 62 and 73, whose
	/// `ZTwiceHost` builds the owner twice (`addingTwiceBuiltUnbuildableOwner`).
	static let smokeSeeds: [UInt64] = [2, 7, 13, 23, 45, 62, 64, 73, 85, 88, 90, 117]

	/// The public mock corpus's smoke seeds: graphs whose `.v2` and `.v3Unstable` public mocks agree, together holding at
	/// least ten compared graphs, among them seeds whose probes pass a leaf its own `name` (31) or a consumer a value its mock
	/// cannot build (6, 9), each spelled the `.v3Unstable` way by `callingV3Mock(_:)`.
	/// A hand mutation that has a `.v3Unstable` public mock ignore `safeDIOverrides` for its type's own optional-typed default
	/// (`PublicMockGeneration`'s `v3RootDefaultMembers`, binding the default provider in place of the member) fails seeds 31
	/// and 440 as values that differ and seed 329 as generated code that does not compile.
	static let publicMockSmokeSeeds: [UInt64] = [6, 9, 31, 118, 123, 139, 158, 182, 191, 208, 329, 440]

	/// The smoke seeds of `corpus`.
	static func smokeSeeds(of corpus: GraphFuzzerReleaseAcceptanceCorpus) -> [UInt64] {
		switch corpus {
		case .base:
			smokeSeeds
		case .publicMock:
			publicMockSmokeSeeds
		case .seam:
			[]
		}
	}
}
