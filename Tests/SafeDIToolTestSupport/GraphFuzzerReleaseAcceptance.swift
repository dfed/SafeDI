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

// MARK: - Release acceptance

/// A SafeDI release that release acceptance runs a graph through: its tool, and the runtime and macros its generated
/// code compiles against. SafeDI measures breaking changes from its last stable release, so release acceptance runs
/// each graph through an older release and through this tree, and judges what this tree builds against what the older
/// release built (`GraphFuzzerReleaseAcceptance`). The older release is a parameter, so a later release candidate can
/// be compared with a beta the same way.
struct GraphFuzzerRelease: Hashable, Sendable {
	/// How a release's tool runs over a graph.
	enum Tool: Hashable, Sendable {
		/// This tree's generator, in the test process, as the corpus runs it (`GraphFuzzerOracle.toolOutcome(of:)`).
		case inProcess
		/// A release's built `SafeDITool`, as that release's SwiftPM plugin runs it: `scan`, then `generate` with the
		/// manifest `scan` wrote.
		case executable(URL)
	}

	/// - Parameters:
	///   - name: The release's name in reports, such as `2.3.0`.
	///   - tool: How its tool runs.
	///   - runtimeSource: Its runtime and macros, or `nil` for this tree's.
	init(name: String, tool: Tool, runtimeSource: DifferentialValueRuntimeSource?) {
		self.name = name
		self.tool = tool
		self.runtimeSource = runtimeSource
	}

	let name: String
	let tool: Tool
	let runtimeSource: DifferentialValueRuntimeSource?

	/// This tree: its generator in the test process, compiled against its own runtime and macros.
	static let currentTree = GraphFuzzerRelease(name: "this tree", tool: .inProcess, runtimeSource: nil)
}

/// A corpus release acceptance draws its graphs from: the base corpus, the seam corpus (`generateDependencyTree`) or the
/// public mock corpus (`generateMockPublic`), each drawn as the graph fuzzer draws it.
enum GraphFuzzerReleaseAcceptanceCorpus: String, CaseIterable, Sendable {
	case base
	case seam
	case publicMock = "public-mock"

	/// The generator features that draw the corpus's graphs.
	var features: Set<GraphFuzzerGeneratorFeature> {
		switch self {
		case .base:
			[]
		case .seam:
			[.generateDependencyTree]
		case .publicMock:
			[.generateMockPublic]
		}
	}

	/// The samples each instantiator with forwarded properties is called with in `fixture`, a graph of the corpus drawn
	/// storing every parameter: the base corpus value oracle's, or those the seam and public mock corpora's value
	/// oracles register for the draws whose instantiators forward a value.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func forwardedPropertiesSamples(of fixture: GraphFuzzerFixture) -> [DifferentialValueSample] {
		switch self {
		case .base:
			GraphFuzzerSampleValues(fixture: fixture, model: GraphFuzzerMockMirrorModel(fixture: fixture)).forwardedPropertiesSamples
		case .seam:
			fixture.holeDrawForwardedPropertiesSamples + fixture.forwardedLabelAcrossSeamCallSamples
		case .publicMock:
			fixture.placeInFillInnerScreenSamples
		}
	}
}

/// What a release did with a graph: the tool rejected it, or it generated files, which were compiled with the fixture
/// against the release's runtime and macros.
struct GraphFuzzerReleaseRun: Equatable {
	enum Outcome: Equatable {
		case rejected(diagnostics: String)
		case compiled(generatedFiles: [String: String], toolWarnings: [String], compilation: GraphFuzzerReleaseCompilation)
	}

	let outcome: Outcome
}

/// The compile of a graph's fixture and generated files: its exit status and what the compiler reported, the fixture's
/// files under `fixtureDirectoryName` and the generated files under `generatedDirectoryName`, so that each diagnostic
/// tells by its path which it is about. Generated code a `#sourceLocation` directive attributes to a fixture's line is
/// located under `sourceLocationDirectoryName`, and is generated code too.
struct GraphFuzzerReleaseCompilation: Equatable {
	let exitCode: Int32
	let stderr: String

	static let fixtureDirectoryName = "Fixture"
	static let generatedDirectoryName = "Generated"
	static let sourceLocationDirectoryName = "SourceLocation"
	/// What precedes each fixture file's name in the compile, so that a `#sourceLocation` directive naming the fixture
	/// file produces a `#fileID` no compiled file has.
	static let fixtureFileNamePrefix = "fixture_"

	/// The message of each error or warning the compiler located in a fixture file (`inGeneratedFiles: false`) or a
	/// generated file, without its path, line and column, which differ between compiles. A continuation line of a
	/// multi-line diagnostic names no path, so it is never counted.
	func messages(ofSeverity severity: GraphFuzzerReleaseDiagnosticSeverity, inGeneratedFiles: Bool) -> [String] {
		let directories = inGeneratedFiles ? [Self.generatedDirectoryName, Self.sourceLocationDirectoryName] : [Self.fixtureDirectoryName]
		let marker = ": \(severity.rawValue): "
		return stderr.split(separator: "\n").compactMap { line -> String? in
			guard line.hasPrefix("/"), directories.contains(where: { line.contains("/\($0)/") }), let range = line.range(of: marker) else { return nil }
			return String(line[range.upperBound...])
		}
	}
}

enum GraphFuzzerReleaseDiagnosticSeverity: String {
	case error
	case warning
}

/// Release acceptance's verdict on one graph. The classes are assigned first match in this order: A, C, D, E, then F
/// or B from the values.
enum GraphFuzzerReleaseAcceptanceClass: String, CaseIterable, Comparable, Sendable {
	/// A: the older release rejects the graph – its tool, its macros, or the compile of its generated code. A graph the
	/// older release rejects cannot be a break.
	case olderReleaseRejects = "A"
	/// B: both accept the graph and every probe builds equal values.
	case valuesAgree = "B"
	/// C: this tree's tool rejects a graph the older release accepts.
	case currentRejects = "C"
	/// D: this tree's generated code, or the fixture under its macros, does not compile where the older release's did.
	case currentDoesNotCompile = "D"
	/// E: this tree's generated code draws a warning the older release's did not.
	case currentDrawsNewGeneratedWarning = "E"
	/// F: a probe builds other values with this tree than with the older release.
	case valuesDiffer = "F"
	/// The comparator could not describe the graph's values on one path: a harness failure, never a verdict.
	case valuesNotCompared = "X"

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	/// Whether the class is a break: a graph the older release accepts that this tree no longer accepts, compiles,
	/// compiles cleanly, or builds the same values for.
	var isBreak: Bool {
		switch self {
		case .currentRejects, .currentDoesNotCompile, .currentDrawsNewGeneratedWarning, .valuesDiffer:
			true
		case .olderReleaseRejects, .valuesAgree, .valuesNotCompared:
			false
		}
	}
}

/// Why the older release rejected a graph (class A).
enum GraphFuzzerReleaseRejection: String, CaseIterable, Sendable {
	/// Its tool reported an error.
	case toolError = "tool"
	/// Its macros rejected the fixture: an error located in a fixture file.
	case macroError = "macro"
	/// Its generated code did not compile.
	case compileFailure = "compile"
}

/// A fact about a graph that is no break on its own.
enum GraphFuzzerReleaseAnnotation: String, CaseIterable, Comparable, Sendable {
	/// This tree's tool or macros report a warning about the fixture that the older release's did not, such as a
	/// deprecation: something a user sees and can act on in source they own.
	case newSourceDiagnostic = "new-source-diagnostic"
	/// Both releases' generated code draws a warning: no break, but a defect the older release shares.
	case sharedGeneratedWarning = "shared-generated-warning"

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// Why a probe of one release's generated code was not compared: the other release generated no such probe.
enum GraphFuzzerReleaseProbeSkip: String, CaseIterable, Comparable, Sendable {
	/// Only this tree generates the probe, such as a mock whose parameters all gained defaults.
	case onlyCurrentGenerates = "only-current"
	/// Only the older release generates the probe.
	case onlyOlderReleaseGenerates = "only-older-release"

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// Release acceptance's verdict on one graph, with what it compared.
struct GraphFuzzerReleaseVerdict: Equatable {
	var verdictClass: GraphFuzzerReleaseAcceptanceClass
	var rejection: GraphFuzzerReleaseRejection?
	var annotations: [GraphFuzzerReleaseAnnotation] = []
	/// The root probes and mock probes both releases generated, which the values compare.
	var rootProbeCount = 0
	var mockProbeCount = 0
	var skippedProbeCounts: [GraphFuzzerReleaseProbeSkip: Int] = [:]
	/// The mock probes called again with an override at every place of the older release's configuration tree
	/// (`ReleaseOverrideProbe`), the places they override, and the places they leave to the mock.
	var overrideProbeCount = 0
	var overriddenPlaceCount = 0
	var skippedOverridePlaceCount = 0
	/// What the verdict rests on: the first diagnostics of a rejection or failed compile, the new warnings, or the
	/// differing values.
	var details = ""

	/// The verdict's class, with the older release's rejection reason after a slash.
	var classDescription: String {
		if let rejection {
			"\(verdictClass.rawValue)/\(rejection.rawValue)"
		} else {
			verdictClass.rawValue
		}
	}
}

/// What release acceptance needs from both releases before it compares values: either the verdict, or the probes the
/// value comparison is to describe.
enum GraphFuzzerReleaseClassification: Equatable {
	case decided(GraphFuzzerReleaseVerdict)
	/// Both releases accept the graph and compile its code cleanly: the values decide between B and F. The verdict holds
	/// the annotations and probe counts so far.
	case comparesValues(GraphFuzzerReleaseVerdict, probes: [DifferentialValueProbe])
}

enum GraphFuzzerReleaseAcceptance {
	/// The number of diagnostic lines a verdict's details quote from each side.
	private static let quotedLineCount = 3

	/// Classifies a graph from what each release did with it, before values: A, C, D, E, or the probes to compare.
	/// - Parameters:
	///   - older: The older release's run.
	///   - current: This tree's run.
	///   - probes: The probes each release's generated files have (`GraphFuzzerFixture.differentialValueProbes`).
	static func classify(
		older: GraphFuzzerReleaseRun,
		current: GraphFuzzerReleaseRun,
		probes: (_ generatedFiles: [String: String]) -> [DifferentialValueProbe],
	) -> GraphFuzzerReleaseClassification {
		let olderGeneratedFiles: [String: String]
		let olderToolWarnings: [String]
		let olderCompilation: GraphFuzzerReleaseCompilation
		switch older.outcome {
		case let .rejected(diagnostics):
			return .decided(GraphFuzzerReleaseVerdict(verdictClass: .olderReleaseRejects, rejection: .toolError, details: quoted(errorLinesOf: diagnostics)))
		case let .compiled(generatedFiles, toolWarnings, compilation):
			guard compilation.exitCode == 0 else {
				let fixtureErrors = compilation.messages(ofSeverity: .error, inGeneratedFiles: false)
				let generatedErrors = compilation.messages(ofSeverity: .error, inGeneratedFiles: true)
				return .decided(GraphFuzzerReleaseVerdict(
					verdictClass: .olderReleaseRejects,
					rejection: fixtureErrors.isEmpty ? .compileFailure : .macroError,
					details: quoted(fixtureErrors.isEmpty ? generatedErrors : fixtureErrors),
				))
			}
			olderGeneratedFiles = generatedFiles
			olderToolWarnings = toolWarnings
			olderCompilation = compilation
		}
		switch current.outcome {
		case let .rejected(diagnostics):
			return .decided(GraphFuzzerReleaseVerdict(verdictClass: .currentRejects, details: quoted(errorLinesOf: diagnostics)))
		case let .compiled(generatedFiles, toolWarnings, compilation):
			guard compilation.exitCode == 0 else {
				return .decided(GraphFuzzerReleaseVerdict(
					verdictClass: .currentDoesNotCompile,
					details: quoted(compilation.messages(ofSeverity: .error, inGeneratedFiles: false) + compilation.messages(ofSeverity: .error, inGeneratedFiles: true)),
				))
			}
			var verdict = GraphFuzzerReleaseVerdict(verdictClass: .valuesAgree)
			let newSourceDiagnostics = messages(
				compilation.messages(ofSeverity: .warning, inGeneratedFiles: false) + toolWarnings.map(warningMessage(of:)),
				notIn: olderCompilation.messages(ofSeverity: .warning, inGeneratedFiles: false) + olderToolWarnings.map(warningMessage(of:)),
			)
			if !newSourceDiagnostics.isEmpty {
				verdict.annotations.append(.newSourceDiagnostic)
			}
			let generatedWarnings = compilation.messages(ofSeverity: .warning, inGeneratedFiles: true)
			let newGeneratedWarnings = messages(generatedWarnings, notIn: olderCompilation.messages(ofSeverity: .warning, inGeneratedFiles: true))
			guard newGeneratedWarnings.isEmpty else {
				verdict.verdictClass = .currentDrawsNewGeneratedWarning
				verdict.details = quoted(newGeneratedWarnings)
				return .decided(verdict)
			}
			if !generatedWarnings.isEmpty {
				verdict.annotations.append(.sharedGeneratedWarning)
			}
			let currentProbes = probes(generatedFiles)
			let olderProbes = probes(olderGeneratedFiles)
			let olderProbeNames = Set(olderProbes.map(\.name))
			let currentProbeNames = Set(currentProbes.map(\.name))
			let comparedProbes = currentProbes.filter { olderProbeNames.contains($0.name) }
			for skip in GraphFuzzerReleaseProbeSkip.allCases {
				let count = switch skip {
				case .onlyCurrentGenerates:
					currentProbeNames.subtracting(olderProbeNames).count
				case .onlyOlderReleaseGenerates:
					olderProbeNames.subtracting(currentProbeNames).count
				}
				if count > 0 {
					verdict.skippedProbeCounts[skip] = count
				}
			}
			verdict.mockProbeCount = comparedProbes.count(where: isMockProbe)
			verdict.rootProbeCount = comparedProbes.count - verdict.mockProbeCount
			return .comparesValues(verdict, probes: comparedProbes)
		}
	}

	/// Completes a verdict that compared values with the comparison's result: B when no probe differs, F when one does,
	/// and X when the comparator could not describe a path.
	static func verdict(
		_ verdict: GraphFuzzerReleaseVerdict,
		comparing result: Result<DifferentialValueComparison, DifferentialValueOracleError>,
	) -> GraphFuzzerReleaseVerdict {
		var verdict = verdict
		switch result {
		case let .success(comparison):
			if comparison.differences.isEmpty {
				verdict.verdictClass = .valuesAgree
			} else {
				verdict.verdictClass = .valuesDiffer
				verdict.details = comparison.differences.map(\.description).joined(separator: "\n")
			}
		case let .failure(error):
			verdict.verdictClass = .valuesNotCompared
			verdict.details = "\(error)"
		}
		return verdict
	}

	/// `classification` with, when it compares values, a probe for each compared `mock()` that takes no argument, calling
	/// it with an override at every place of the configuration tree the older release generated
	/// (`ReleaseOverrideProbe`): an adopter's test is written against that release's `SafeDIOverrides`, so both releases'
	/// mocks are called with the same overrides, and an override one release ignores, applies at another place, or calls
	/// another number of times is a difference.
	static func withOverrideProbes(
		_ classification: GraphFuzzerReleaseClassification,
		fixtureFiles: [String],
		older: GraphFuzzerReleaseRun,
	) -> GraphFuzzerReleaseClassification {
		guard case let .comparesValues(verdict, probes) = classification,
		      case let .compiled(olderGeneratedFiles, _, _) = older.outcome
		else { return classification }
		let mockedTypeNames = probes.compactMap { probe -> String? in
			guard probe.knownRightExpression == nil, probe.expression.hasSuffix(".mock()") else { return nil }
			let typeName = String(probe.expression.dropLast(".mock()".count))
			return typeName.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." } ? typeName : nil
		}
		guard !mockedTypeNames.isEmpty else { return classification }
		let tree = ReleaseMockConfigurationTree(generatedFiles: olderGeneratedFiles)
		let constructors = ReleaseOverrideConstructors(fixtureFiles: fixtureFiles)
		var verdictWithOverrides = verdict
		var overrideProbes = [DifferentialValueProbe]()
		for typeName in mockedTypeNames {
			guard let overrideProbe = ReleaseOverrideProbe.probe(mockedTypeName: typeName, tree: tree, constructors: constructors) else { continue }
			overrideProbes.append(overrideProbe.probe)
			verdictWithOverrides.overrideProbeCount += 1
			verdictWithOverrides.overriddenPlaceCount += overrideProbe.placeCount
			verdictWithOverrides.skippedOverridePlaceCount += overrideProbe.skippedPlaceCount
		}
		return .comparesValues(verdictWithOverrides, probes: probes + overrideProbes)
	}

	/// Whether a probe calls a generated mock rather than building a root.
	static func isMockProbe(_ probe: DifferentialValueProbe) -> Bool {
		probe.expression.contains(".mock(")
	}

	/// Runs `release` over `fixture` and, when its tool accepts the graph, compiles the fixture and the generated files
	/// against the release's runtime and macros.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func run(
		_ release: GraphFuzzerRelease,
		over fixture: GraphFuzzerFixture,
		filesToDelete: inout [URL],
	) async throws -> GraphFuzzerReleaseRun {
		let toolOutcome: GraphFuzzerToolOutcome = switch release.tool {
		case .inProcess:
			// A hand-written fixture's files each name themselves on their first line, which the harness names a corpus
			// graph's files by only where they declare no `@Instantiable` type.
			try await GraphFuzzerOracle.toolOutcome(
				of: fixture,
				fileNames: fixture.swiftFileContent.allSatisfy { $0.hasPrefix(GraphFuzzerFixture.fileNameMarker) } ? fixture.fileNames : nil,
			)
		case let .executable(toolURL):
			if let modules = fixture.modules {
				try await executableSplitToolOutcome(of: fixture, modules: modules, toolURL: toolURL, filesToDelete: &filesToDelete)
			} else {
				try await executableToolOutcome(of: fixture, toolURL: toolURL, filesToDelete: &filesToDelete)
			}
		}
		switch toolOutcome {
		case let .rejected(diagnostics):
			return GraphFuzzerReleaseRun(outcome: .rejected(diagnostics: diagnostics))
		case let .accepted(generatedFiles, warnings):
			let compilation = try await compile(fixture, generatedFiles: generatedFiles, runtimeSource: release.runtimeSource, filesToDelete: &filesToDelete)
			return GraphFuzzerReleaseRun(outcome: .compiled(generatedFiles: generatedFiles, toolWarnings: warnings, compilation: compilation))
		}
	}

	/// The value graph of a graph both releases accept: this tree's generated code as the feature path, the older
	/// release's, compiled against its runtime, as the known-right path, and the samples each instantiator with
	/// forwarded properties is called with.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func valueGraph(
		of fixture: GraphFuzzerFixture,
		corpus: GraphFuzzerReleaseAcceptanceCorpus = .base,
		older: (release: GraphFuzzerRelease, generatedFiles: [String: String]),
		current: (release: GraphFuzzerRelease, generatedFiles: [String: String]),
		probes: [DifferentialValueProbe],
	) -> DifferentialValueGraph {
		func path(_ side: (release: GraphFuzzerRelease, generatedFiles: [String: String])) -> DifferentialValuePath {
			DifferentialValuePath(modules: DifferentialValuePath(fixture: fixture, generatedFiles: side.generatedFiles).modules, runtimeSource: side.release.runtimeSource)
		}
		return DifferentialValueGraph(
			name: "seed \(fixture.seed)",
			feature: path(current),
			knownRight: path(older),
			probes: probes,
			samples: corpus.forwardedPropertiesSamples(of: fixture),
		)
	}

	/// Judges `seeds` of `corpus`, each graph drawn storing every parameter, `older` against `current`, running the
	/// graphs of each batch concurrently and comparing a batch's values in one comparison, under `batchLimits`; a graph
	/// whose probe spends those traversals is compared again on its own under `DifferentialValueLimits.isolatedFuzzerGraph`.
	/// The verdicts are in seed order.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func verdicts(
		forSeeds seeds: [UInt64],
		of corpus: GraphFuzzerReleaseAcceptanceCorpus = .base,
		older: GraphFuzzerRelease,
		current: GraphFuzzerRelease = .currentTree,
		drawsEveryFeature: Bool = false,
		fixtureFilesBySeed: [UInt64: [String]]? = nil,
		batchSize: Int = 25,
		batchLimits: DifferentialValueLimits = DifferentialValueLimits(),
	) async throws -> [(seed: UInt64, verdict: GraphFuzzerReleaseVerdict)] {
		await ProcessSlots.shared.takePlaceInLine(for: Test.current?.id)
		// Hand-written fixtures share no type-name prefix, so each compiles in a batch of its own.
		let batchSize = fixtureFilesBySeed == nil ? batchSize : 1
		let batches = stride(from: 0, to: seeds.count, by: batchSize).map { Array(seeds[$0..<min($0 + batchSize, seeds.count)]) }
		var verdicts = [(seed: UInt64, verdict: GraphFuzzerReleaseVerdict)]()
		try await withThrowingTaskGroup(of: [(seed: UInt64, verdict: GraphFuzzerReleaseVerdict)].self) { group in
			for batch in batches {
				group.addTask {
					try await batchVerdicts(forSeeds: batch, of: corpus, older: older, current: current, drawsEveryFeature: drawsEveryFeature, fixtureFilesBySeed: fixtureFilesBySeed, limits: batchLimits)
				}
			}
			for try await batchVerdicts in group {
				verdicts += batchVerdicts
			}
		}
		return verdicts.sorted { $0.seed < $1.seed }
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func batchVerdicts(
		forSeeds seeds: [UInt64],
		of corpus: GraphFuzzerReleaseAcceptanceCorpus,
		older: GraphFuzzerRelease,
		current: GraphFuzzerRelease,
		drawsEveryFeature: Bool,
		fixtureFilesBySeed: [UInt64: [String]]?,
		limits: DifferentialValueLimits,
	) async throws -> [(seed: UInt64, verdict: GraphFuzzerReleaseVerdict)] {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		let classifications = try await withThrowingTaskGroup(of: (seed: UInt64, classification: GraphFuzzerReleaseClassification, graph: DifferentialValueGraph?, filesToDelete: [URL]).self) { group in
			for seed in seeds {
				group.addTask {
					var filesToDelete = [URL]()
					let fixture = fixtureFilesBySeed?[seed].map { GraphFuzzerFixture(seed: seed, swiftFileContent: $0) }
						?? GraphFuzzerGenerator.releaseAcceptanceFixture(forSeed: seed, features: corpus.features, omitsDrawsOlderReleasesReject: !drawsEveryFeature)
					let olderRun = try await run(older, over: fixture, filesToDelete: &filesToDelete)
					let currentRun = try await run(current, over: fixture, filesToDelete: &filesToDelete)
					let classification = withOverrideProbes(
						classify(older: olderRun, current: currentRun) { fixture.differentialValueProbes(generatedFiles: $0) },
						fixtureFiles: fixture.swiftFileContent,
						older: olderRun,
					)
					guard case let .comparesValues(_, probes) = classification,
					      case let .compiled(olderGeneratedFiles, _, _) = olderRun.outcome,
					      case let .compiled(currentGeneratedFiles, _, _) = currentRun.outcome
					else {
						return (seed, classification, nil, filesToDelete)
					}
					let graph = valueGraph(of: fixture, corpus: corpus, older: (older, olderGeneratedFiles), current: (current, currentGeneratedFiles), probes: probes)
					return (seed, classification, graph, filesToDelete)
				}
			}
			var classifications = [(seed: UInt64, classification: GraphFuzzerReleaseClassification, graph: DifferentialValueGraph?)]()
			for try await result in group {
				filesToDelete += result.filesToDelete
				classifications.append((result.seed, result.classification, result.graph))
			}
			return classifications.sorted { $0.seed < $1.seed }
		}
		let graphs = classifications.compactMap(\.graph)
		let comparisons = graphs.isEmpty ? [] : try await DifferentialValueOracle.compare(graphs: graphs, limits: limits, filesToDelete: &filesToDelete) ?? []
		var comparisonByName = [String: Result<DifferentialValueComparison, DifferentialValueOracleError>]()
		for comparison in comparisons {
			comparisonByName[comparison.name] = comparison.result
		}
		// A graph whose probe spent the batch's traversals is compared again on its own with the budget the corpora give
		// the seeds they isolate (`DifferentialValueLimits.isolatedFuzzerGraph`), so that its verdict is a comparison
		// rather than a harness failure, while every other graph keeps the batch's budget and speed.
		let graphsSpendingTraversals = graphs.filter { graph in
			guard case let .failure(error) = comparisonByName[graph.name] else { return false }
			return error.spentTraversals
		}
		if !graphsSpendingTraversals.isEmpty {
			let isolatedComparisons = try await withThrowingTaskGroup(of: (name: String, result: Result<DifferentialValueComparison, DifferentialValueOracleError>?, filesToDelete: [URL]).self) { group in
				for graph in graphsSpendingTraversals {
					group.addTask {
						var filesToDelete = [URL]()
						let comparison = try await DifferentialValueOracle.compare(graphs: [graph], limits: .isolatedFuzzerGraph, filesToDelete: &filesToDelete)?.first
						return (graph.name, comparison?.result, filesToDelete)
					}
				}
				var isolatedComparisons = [(name: String, result: Result<DifferentialValueComparison, DifferentialValueOracleError>?)]()
				for try await isolated in group {
					filesToDelete += isolated.filesToDelete
					isolatedComparisons.append((isolated.name, isolated.result))
				}
				return isolatedComparisons
			}
			for (name, result) in isolatedComparisons {
				if let result {
					comparisonByName[name] = result
				}
			}
		}
		return classifications.map { seed, classification, graph in
			switch classification {
			case let .decided(verdict):
				return (seed, verdict)
			case let .comparesValues(verdict, _):
				guard let graph, let result = comparisonByName[graph.name] else {
					var verdict = verdict
					verdict.verdictClass = .valuesNotCompared
					verdict.details = "The comparator returned no comparison: compile verification is off (SAFEDI_SKIP_COMPILE_CHECK)."
					return (seed, verdict)
				}
				return (seed, Self.verdict(verdict, comparing: result))
			}
		}
	}

	// MARK: Running a release

	/// Runs a release's built `SafeDITool` over `fixture` as that release's SwiftPM plugin runs it: `scan` over a CSV of
	/// the fixture's files, every file mock-scoped, then `generate` with the manifest `scan` wrote, which writes one
	/// file per root and per mock into the output directory.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func executableToolOutcome(of fixture: GraphFuzzerFixture, toolURL: URL, filesToDelete: inout [URL]) async throws -> GraphFuzzerToolOutcome {
		guard FileManager.default.isExecutableFile(atPath: toolURL.path) else {
			throw GraphFuzzerInfrastructureError(description: "No SafeDITool executable at \(toolURL.path).")
		}
		let directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-release-acceptance-tool-")
		filesToDelete.append(directory)
		let fixtureDirectory = directory.appendingPathComponent(GraphFuzzerReleaseCompilation.fixtureDirectoryName)
		let outputDirectory = directory.appendingPathComponent("Output")
		try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		var paths = [String]()
		for (fileName, content) in zip(fixture.fileNames, fixture.swiftFileContent) {
			let file = fixtureDirectory.appendingPathComponent(fileName)
			try content.write(to: file, atomically: true, encoding: .utf8)
			paths.append(file.path)
		}
		let inputsFile = directory.appendingPathComponent("inputs.csv")
		try paths.joined(separator: ",").write(to: inputsFile, atomically: true, encoding: .utf8)
		let manifestFile = directory.appendingPathComponent("manifest.json")
		let scan = try await runProcess(toolURL, arguments: [
			"scan",
			"--input-sources-file", inputsFile.path,
			"--project-root", directory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
			"--mock-scoped-files",
		] + paths)
		let normalize = GraphFuzzerOracle.normalizer(fixtureDirectory: fixtureDirectory.path)
		guard scan.exitCode == 0 else {
			return .rejected(diagnostics: normalize(scan.stderr))
		}
		let generate = try await runProcess(toolURL, arguments: ["generate", inputsFile.path, "--swift-manifest", manifestFile.path])
		guard generate.exitCode == 0 else {
			return .rejected(diagnostics: normalize(generate.stderr))
		}
		var generatedFiles = [String: String]()
		for fileName in try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).sorted() where fileName.hasSuffix(".swift") {
			generatedFiles[fileName] = try normalize(String(contentsOf: outputDirectory.appendingPathComponent(fileName), encoding: .utf8))
		}
		let warnings = (scan.stderr + generate.stderr).split(separator: "\n").filter { $0.contains("warning:") }.map { normalize(String($0)) }
		// The callers this tree's run adds (`GraphFuzzerOracle.toolRun(of:)`), so that both releases' code is compiled with
		// the same hand-written calls of what it generated.
		return .accepted(generatedFiles: GraphFuzzerOracle.addingSeamCallers(to: generatedFiles, seamTypeAccess: fixture.seamTypeAccess), warnings: warnings)
	}

	/// Runs a release's built `SafeDITool` over `fixture`, a graph split across modules, as Bazel runs it and as this
	/// tree's run does (`GraphFuzzerOracle.toolRun(of:)`, `.moduleInfo`): one `generate` per module, in dependency order,
	/// over a CSV of the module's files, naming its module and, unless the module has none, its package, writing one
	/// combined output and the module's `.safedi`, and reading the `.safedi` of each module the module lists
	/// (`GraphFuzzerFixture.dependencyLists(modules:integration:listsTransitiveDependencies:)`). Each combined output is
	/// decomposed into the files one module writes, keyed by the module's name and the file's (`FuzzFeature/Type+SafeDI.swift`),
	/// and given the callers this tree's run adds. The first module whose `generate` fails rejects the graph.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func executableSplitToolOutcome(of fixture: GraphFuzzerFixture, modules: [GraphFuzzerModule], toolURL: URL, filesToDelete: inout [URL]) async throws -> GraphFuzzerToolOutcome {
		guard FileManager.default.isExecutableFile(atPath: toolURL.path) else {
			throw GraphFuzzerInfrastructureError(description: "No SafeDITool executable at \(toolURL.path).")
		}
		let directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-release-acceptance-tool-")
		filesToDelete.append(directory)
		let moduleInfoDirectory = directory.appendingPathComponent("ModuleInfo")
		let inputsDirectory = directory.appendingPathComponent("Inputs")
		let outputDirectory = directory.appendingPathComponent("Output")
		for subdirectory in [moduleInfoDirectory, inputsDirectory, outputDirectory] {
			try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
		}
		let normalize = GraphFuzzerOracle.normalizer(fixtureDirectory: directory.path)
		let presentModules = Set(modules)
		let dependencyLists = fixture.dependencyLists(modules: modules, integration: .moduleInfo, listsTransitiveDependencies: false)
		var generatedFiles = [String: String]()
		var warnings = [String]()
		for module in GraphFuzzerModule.allCases where presentModules.contains(module) {
			// Laid out as the multi-module harness lays a module out, so that the paths the generated code cites are spelled
			// alike under both releases.
			let sourceDirectory = directory.appendingPathComponent(module.packageName).appendingPathComponent("Sources").appendingPathComponent(module.name)
			var paths = [String]()
			for index in modules.indices where modules[index] == module {
				let file = sourceDirectory.appendingPathComponent(fixture.fileNames[index])
				try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
				try fixture.swiftFileContent[index].write(to: file, atomically: true, encoding: .utf8)
				paths.append(file.path)
			}
			let inputsFile = inputsDirectory.appendingPathComponent("\(module.name).csv")
			try paths.joined(separator: ",").write(to: inputsFile, atomically: true, encoding: .utf8)
			let combinedOutput = outputDirectory.appendingPathComponent("\(module.name).swift")
			var arguments = [
				"generate", inputsFile.path,
				"--combined-output", combinedOutput.path,
				"--compiler-receives-input-paths-unchanged",
				"--module-info-output", moduleInfoDirectory.appendingPathComponent("\(module.name).safedi").path,
				"--module-name", module.name,
			]
			if !fixture.modulesOmittingPackageName.contains(module) {
				arguments += ["--package-name", module.packageName]
			}
			let dependencies = dependencyLists[module] ?? []
			if !dependencies.isEmpty {
				let dependenciesFile = moduleInfoDirectory.appendingPathComponent("\(module.name)-dependencies.csv")
				try dependencies
					.map { moduleInfoDirectory.appendingPathComponent("\($0.name).safedi").path }
					.joined(separator: ",")
					.write(to: dependenciesFile, atomically: true, encoding: .utf8)
				arguments += ["--dependent-module-info-file-path", dependenciesFile.path]
			}
			let generate = try await runProcess(toolURL, arguments: arguments)
			guard generate.exitCode == 0 else {
				return .rejected(diagnostics: normalize(generate.stderr))
			}
			for (fileName, contents) in GraphFuzzerOracle.decomposingCombinedOutput(normalize(try String(contentsOf: combinedOutput, encoding: .utf8))) {
				generatedFiles["\(module.name)/\(fileName)"] = contents
			}
			warnings += generate.stderr.split(separator: "\n").filter { $0.contains("warning:") }.map { normalize(String($0)) }
		}
		return .accepted(
			generatedFiles: GraphFuzzerOracle.addingOverrideClosureCallers(
				to: GraphFuzzerOracle.addingPublicMockCallers(
					to: GraphFuzzerOracle.addingSeamCallers(to: generatedFiles, seamTypeAccess: fixture.seamTypeAccess, modules: presentModules),
					of: fixture,
				),
				of: fixture,
			),
			warnings: warnings,
		)
	}

	/// Compiles `fixture` and `generatedFiles` against `runtimeSource`'s runtime and macros, the runtime the value
	/// comparator compiles, so that a release's code compiles against that release's `SafeDI`: each module of the graph
	/// as the value comparator compiles it (`DifferentialValuePath(fixture:generatedFiles:)`: its package, or none, its
	/// conditions, and the modules beneath it), in dependency order, into an object file, until one does not compile. A
	/// graph in one module is one module, in the seam module's package.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func compile(
		_ fixture: GraphFuzzerFixture,
		generatedFiles: [String: String],
		runtimeSource: DifferentialValueRuntimeSource?,
		filesToDelete: inout [URL],
	) async throws -> GraphFuzzerReleaseCompilation {
		let artifacts = try await DifferentialValueOracle.runtimeArtifacts(for: runtimeSource)
		let directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-release-acceptance-compile-")
		filesToDelete.append(directory)
		// A generated file's `#sourceLocation` names the fixture file it was generated from, which the tool's run spelled
		// `<fixture-directory>/…`: spelled under a directory of its own, so that what the compiler reports there is told
		// apart as generated code, and under the fixture file's own name, which no compiled file has.
		let sourceLocationDirectory = directory.appendingPathComponent(GraphFuzzerReleaseCompilation.sourceLocationDirectoryName).path
		let path = DifferentialValuePath(fixture: fixture, generatedFiles: generatedFiles)
		var moduleDirectoriesByName = [String: URL]()
		var stderr = ""
		for module in path.modules {
			let moduleDirectory = directory.appendingPathComponent(module.name)
			var sources = [URL]()
			for (subdirectory, files) in [
				(GraphFuzzerReleaseCompilation.fixtureDirectoryName, module.fixtureFiles.sorted { $0.key < $1.key }.map { (GraphFuzzerReleaseCompilation.fixtureFileNamePrefix + $0.key, $0.value) }),
				(GraphFuzzerReleaseCompilation.generatedDirectoryName, module.generatedFiles.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }),
			] {
				let subdirectoryURL = moduleDirectory.appendingPathComponent(subdirectory)
				try FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true)
				for (fileName, content) in files {
					let file = subdirectoryURL.appendingPathComponent(fileName.replacingOccurrences(of: "/", with: "_"))
					let resolvedContent = content.replacingOccurrences(of: "<fixture-directory>", with: sourceLocationDirectory)
					try ("import SafeDI\n" + resolvedContent).write(to: file, atomically: true, encoding: .utf8)
					sources.append(file)
				}
			}
			let result = try await compileSwift(
				sources: sources,
				outputDirectory: moduleDirectory,
				artifacts: artifacts,
				activeCompilationConditions: module.activeCompilationConditions + [module.mockConditionalCompilation].compactMap(\.self),
				moduleName: module.name,
				packageName: module.packageName,
				emitsModule: true,
				moduleSearchPaths: path.moduleNames(dependedOnBy: module).compactMap { moduleDirectoriesByName[$0] },
				parsesAsLibrary: true,
			)
			stderr += result.stderr
			// A module that does not compile leaves the modules above it nothing to import.
			guard result.exitCode == 0 else {
				return GraphFuzzerReleaseCompilation(exitCode: result.exitCode, stderr: stderr)
			}
			moduleDirectoriesByName[module.name] = moduleDirectory
		}
		return GraphFuzzerReleaseCompilation(exitCode: 0, stderr: stderr)
	}

	// MARK: Diagnostics

	/// `lines` without each line that is in `others`, counting repeats: the messages one compile reports more often.
	private static func messages(_ lines: [String], notIn others: [String]) -> [String] {
		var remaining = [String: Int]()
		for other in others {
			remaining[other, default: 0] += 1
		}
		return lines.filter { line in
			guard let count = remaining[line], count > 0 else { return true }
			remaining[line] = count - 1
			return false
		}
	}

	/// A tool warning's message: without the location before `warning: ` where a release's executable printed it, and
	/// the `message` of the `SourceDiagnostic` this tree's run describes (`SourceDiagnostic(severity: …, message: "…",
	/// fixIts: […])`), unescaped, so that a warning both releases report is one message.
	static func warningMessage(of warning: String) -> String {
		let messageMarker = "message: \""
		let fixItsMarker = "\", fixIts: "
		if warning.hasPrefix("SourceDiagnostic("), let messageStart = warning.range(of: messageMarker), let messageEnd = warning.range(of: fixItsMarker, options: .backwards), messageStart.upperBound <= messageEnd.lowerBound {
			return String(warning[messageStart.upperBound..<messageEnd.lowerBound])
				.replacingOccurrences(of: "\\\"", with: "\"")
				.replacingOccurrences(of: "\\\\", with: "\\")
		} else {
			return warning.range(of: "warning: ").map { String(warning[$0.upperBound...]) } ?? warning
		}
	}

	private static func quoted(errorLinesOf diagnostics: String) -> String {
		let errorLines = diagnostics.split(separator: "\n").filter { $0.contains("error") }.map(String.init)
		return quoted(errorLines.isEmpty ? diagnostics.split(separator: "\n").map(String.init) : errorLines)
	}

	private static func quoted(_ lines: [String]) -> String {
		lines.prefix(quotedLineCount).joined(separator: "\n")
	}
}
