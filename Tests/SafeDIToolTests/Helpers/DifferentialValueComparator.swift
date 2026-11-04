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

// MARK: - Paths

/// One module of a path the differential value comparator builds: the module's fixture, the code SafeDI generated
/// for it, and how the compiler names it, as `ModuleCompileSources` describes a module the verifier compiles, with
/// the fixture given as file contents rather than files.
struct DifferentialValueModule {
	/// - Parameters:
	///   - name: The module's name, which the probes import.
	///   - dependencyModuleNames: The names of the path's modules this one imports, each listed before it in the path.
	///   - fixtureFiles: The fixture's files by name. `import SafeDI` is prepended to each, as the verifier does.
	///   - generatedFiles: The files SafeDI generated for the module, by name.
	///   - mockConditionalCompilation: The condition the module's generated mocks are wrapped in, which the compile
	///     defines so the mocks compile too. `DEBUG` is always defined.
	init(
		name: String,
		packageName: String? = nil,
		dependencyModuleNames: [String] = [],
		fixtureFiles: [String: String],
		generatedFiles: [String: String] = [:],
		activeCompilationConditions: [String] = [],
		mockConditionalCompilation: String? = nil,
	) {
		self.name = name
		self.packageName = packageName
		self.dependencyModuleNames = dependencyModuleNames
		self.fixtureFiles = fixtureFiles
		self.generatedFiles = generatedFiles
		self.activeCompilationConditions = activeCompilationConditions
		self.mockConditionalCompilation = mockConditionalCompilation
	}

	var name: String
	var packageName: String?
	var dependencyModuleNames: [String]
	var fixtureFiles: [String: String]
	var generatedFiles: [String: String]
	var activeCompilationConditions: [String]
	var mockConditionalCompilation: String?

	/// Everything about the module but its files: the modules of graphs whose paths have one layout compile as one.
	fileprivate struct Layout: Hashable {
		let name: String
		let packageName: String?
		let dependencyModuleNames: [String]
		let activeCompilationConditions: [String]
		let mockConditionalCompilation: String?
	}

	fileprivate var layout: Layout {
		Layout(
			name: name,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
			activeCompilationConditions: activeCompilationConditions,
			mockConditionalCompilation: mockConditionalCompilation,
		)
	}
}

/// One way of building a graph: its modules in dependency order, each with its fixture and generated code. A
/// feature's path and the known-right path are each compiled into an executable of their own, so their modules may
/// share names, and a path split across modules compares against the same graph in one module.
///
/// The comparator sees only stored properties, a type's own and its superclasses'. A fixture it can judge stores
/// every dependency and every default-valued parameter a type takes, and an extension's `instantiate(…)` passes each
/// of its parameters to the type it returns, which stores them; each of its classes stores a creation stamp, so that
/// the comparator sees an instance a lazily instantiated wrapper's closure captures, built before the wrapper
/// (`DifferentialValueCreationStamp`). `GraphFuzzerGenerator.fixture(forSeed:storingEveryParameter:)` gives the
/// fuzzer's graphs that shape. A stored closure is described as `(Function)`,
/// whatever it does, so two closures always agree and only a closure against `nil` is a difference: a fixture that
/// needs a closure judged stores what the closure determines, such as what it returns. A set, or a dictionary whose
/// keys or values hold class instances, is compared by kind and count only: a fixture that needs its elements judged
/// stores them in an array.
struct DifferentialValuePath {
	init(modules: [DifferentialValueModule]) {
		self.modules = modules
	}

	/// A path of one module, named as the standalone verifier names the module it compiles.
	init(
		fixtureFiles: [String: String],
		generatedFiles: [String: String] = [:],
		activeCompilationConditions: [String] = [],
		mockConditionalCompilation: String? = nil,
	) {
		self.init(modules: [
			DifferentialValueModule(
				name: standaloneVerificationModuleName,
				fixtureFiles: fixtureFiles,
				generatedFiles: generatedFiles,
				activeCompilationConditions: activeCompilationConditions,
				mockConditionalCompilation: mockConditionalCompilation,
			),
		])
	}

	let modules: [DifferentialValueModule]
}

/// The contract a fixture follows so that the comparator sees whether the generated code built a lazily instantiated
/// wrapper's instance up front, by capturing an instance built before the wrapper or by reading the wrapper early: a
/// fixture declares one counter per path (`counterDeclaration(named:)`), in a module every stamped type's module
/// imports, and each class it declares stores a stamp drawn from it (`property(counterNamed:)`), a stored property
/// labeled `label` of type `Int`. The describer never prints the stamp. When it reads a wrapper's instance last, it
/// marks the instance `(built before the probe's value)` if the instance is a class instance stamped before the
/// probe's value that the value does not hold through stored properties, wherever the description first showed it.
/// A stored property's initial value is set when the initializer begins, after its arguments are built, so generated
/// code stamps the probe's value after everything it builds for it, and everything the describer builds, calling an
/// instantiator or reading an instance, is stamped after the value. An instance the value holds is built up front
/// by design, as a mock builds one the mocked type takes by value, and two paths differ on it by identity. Where the
/// probe's value is stamped, a `LazilyInstantiated` wrapper's line does not say `already instantiated`, since the
/// probe's own instantiator calls can read the instance before the wrapper is met; the instance's mark says it
/// instead, so one early build is one mark.
///
/// What the stamps leave unseen: the dependencies of a lazily built instance, and the class instances a lazily built
/// value that is not a class holds, are not judged, because a mock builds the dependencies its tree receives up
/// front by design and hands them to lazily built instances (`let x = X(); LazilyInstantiated { B(x: x) }`), so
/// judging them would mark correct paths; an instance built early inside an instantiator the probe calls is stamped
/// after the probe's value and passes; and a probe whose value is not a stamped class, such as a struct, gets no
/// stamp marks, and its wrappers say `already instantiated` as an unstamped fixture's do. A fixture without stamps is
/// described as before. `GraphFuzzerGenerator.fixture(forSeed:storingEveryParameter: true)` stamps every class of
/// the graph.
enum DifferentialValueCreationStamp {
	/// The label of the stored property that holds a type's stamp.
	static let label = "differentialValueCreationStamp"

	/// The stored property each stamped class declares, drawing its stamp from the counter `counterName` declares.
	static func property(counterNamed counterName: String) -> String {
		"let \(label) = \(counterName).next()"
	}

	/// The counter a fixture declares once, which every stamped class of a path draws from.
	static func counterDeclaration(named counterName: String) -> String {
		"""
		public enum \(counterName) {
			nonisolated(unsafe) private static var lastStamp = 0

			public static func next() -> Int {
				lastStamp += 1
				return lastStamp
			}
		}
		"""
	}
}

/// A Swift expression the comparator evaluates in each path, such as `Root()` or `Feature.mock()`, whose value it
/// describes under `name`. The expression is compiled in a module that `@testable import`s every module of the
/// path, so it may name internal declarations, such as a generated `mock()`.
struct DifferentialValueProbe: Equatable {
	/// A probe named by its expression.
	init(_ expression: String) {
		self.init(name: expression, expression: expression)
	}

	init(name: String, expression: String) {
		self.name = name
		self.expression = expression
	}

	let name: String
	let expression: String
}

/// One graph of a batch: its two paths, the probes that describe what each builds, and the differences between them
/// that the comparison exempts. A batch compiles the graphs whose paths have one layout into one executable per path,
/// so their declarations must not clash, as the graph fuzzer's per-seed type-name prefixes keep them apart; their
/// files may share names. A module that every graph of the batch holds alike, with the same files, is compiled once,
/// so the graphs share its declarations and the instances its static properties hold, as they would share an
/// instance from a module outside the path.
struct DifferentialValueGraph {
	init(
		name: String,
		feature: DifferentialValuePath,
		knownRight: DifferentialValuePath,
		probes: [DifferentialValueProbe],
		exemptions: [DifferentialValueDifference] = [],
	) {
		self.name = name
		self.feature = feature
		self.knownRight = knownRight
		self.probes = probes
		self.exemptions = exemptions
	}

	let name: String
	let feature: DifferentialValuePath
	let knownRight: DifferentialValuePath
	let probes: [DifferentialValueProbe]
	let exemptions: [DifferentialValueDifference]
}

/// How far the comparator lets each probe run.
struct DifferentialValueLimits: Equatable {
	/// - Parameters:
	///   - probeTimeLimitInSeconds: How long a probe may run before the probe executable is stopped, which fails the
	///     path's description: far longer than any fuzzer graph's probe takes.
	///   - traversalsPerProbe: How many wrappers a probe traverses at most, so that a description cannot grow
	///     exponentially with the builders each type holds: about eleven times what the busiest probe of the fuzzer's
	///     corpus traverses, 908. A probe that spends them on either path fails its graph's comparison, unless an
	///     exemption accepts each node where it did.
	init(probeTimeLimitInSeconds: Int = 60, traversalsPerProbe: Int = 10_000) {
		self.probeTimeLimitInSeconds = probeTimeLimitInSeconds
		self.traversalsPerProbe = traversalsPerProbe
	}

	let probeTimeLimitInSeconds: Int
	let traversalsPerProbe: Int
}

// MARK: - Results

/// A node at which a probe's two descriptions differ: the probe, the path of labels from the probe's value to the
/// node, and the node's line in each description, or `(absent)` where a description has no such node. A `(seen)`
/// line names where the instance it refers to was first seen. What lies beneath a node that differs is part of
/// that difference and is not compared: the contents of a second instance where one was shared, for example. An
/// exemption is a difference equal to this one: the comparator matches it by content, never by text that appears in
/// its message.
struct DifferentialValueDifference: Equatable, CustomStringConvertible {
	let probe: String
	let path: [String]
	let feature: String
	let knownRight: String

	var description: String {
		"probe `\(probe)` at \(path.joined(separator: " > ")):\n  feature:     \(feature)\n  known right: \(knownRight)"
	}
}

/// What the comparator found: each path's canonical description, and every difference between them that the
/// comparison does not exempt, probe by probe. The paths agree when there is none.
struct DifferentialValueComparison {
	let featureDescription: String
	let knownRightDescription: String
	let differences: [DifferentialValueDifference]

	/// The differences that are not among `exemptions`: an exemption removes exactly the differences equal to it,
	/// with everything beneath its node, and every other difference remains.
	func differences(exempting exemptions: [DifferentialValueDifference]) -> [DifferentialValueDifference] {
		differences.filter { !exemptions.contains($0) }
	}

	/// Both descriptions, for a message that shows the whole of what each path built.
	var report: String {
		"Feature path:\n\(featureDescription)Known-right path:\n\(knownRightDescription)"
	}
}

/// What the comparator found for one graph of a batch: the comparison of its probes, or why one of its paths could
/// not be described on its own.
struct DifferentialValueGraphComparison {
	let name: String
	let result: Result<DifferentialValueComparison, DifferentialValueOracleError>
}

/// Which of a comparison's paths something belongs to.
enum DifferentialValuePathRole: String, Equatable {
	case feature
	case knownRight

	/// How a message names the path.
	var name: String {
		switch self {
		case .feature:
			"feature"
		case .knownRight:
			"known-right"
		}
	}
}

/// Why the comparator could not describe or compare a path: the SafeDI runtime or a module of the path does not
/// compile, the probes do not compile, the probes did not run to completion, such as a probe that trapped or ran past
/// the time limit, or a probe spent its traversals at a node no exemption accepts, beneath which nothing is compared.
struct DifferentialValueOracleError: Error, CustomStringConvertible {
	enum Stage: Equatable {
		case locatingBuildArtifacts
		case compilingRuntime
		case compilingModule(String)
		case compilingProbes
		case runningProbes
	}

	/// The path the error belongs to, or `nil` for one that belongs to no path: locating the build artifacts or
	/// compiling the runtime, which every path shares, describing a path on its own, or a probe that spent its
	/// traversals at the same node on both paths.
	let path: DifferentialValuePathRole?
	let stage: Stage
	let description: String
}

// MARK: - Oracle

/// Compares what two paths build for one graph by value: each path is compiled, with the SafeDI runtime, into an
/// executable that evaluates each probe and prints a canonical description of its value, and the two descriptions
/// are compared node by node.
///
/// The description shows a value's stored properties in declaration order, a superclass's first, each by its label
/// and: for a class instance, an identity numbered by first visit within its probe (`<2> A`, then `<2> A (seen)`),
/// so two references to one instance print the same number and a second instance a new one, with `(seen in probe
/// …)` on an instance an earlier probe of the same graph held; `nil` for an optional without a value, and the value
/// of one with a value; the type and children of a struct, tuple, collection, or enum; and a leaf's dynamic type and
/// its `String(reflecting:)` (`String "default"`). Some values are described otherwise, so that every run describes
/// them alike: an `AnyHashable` as the value it wraps, `Data` by its bytes, and a pointer or `ObjectIdentifier` as
/// `(address)`. A type is named without a leading qualifier that names one of the path's modules, and without the
/// `(extension in App):` the runtime writes before a type declared in an extension in one of them, and a private,
/// fileprivate, or local type with `(private)` where the runtime prints an address, so a graph split across modules
/// compares against the same graph in one module. The elements of a set or dictionary that hold no class instance
/// are described in the order of their own descriptions.
///
/// Stated limits: a closure is described as `(Function)`, so closures compare only as present or `nil`; a set, or a
/// dictionary whose keys or values hold class instances, is described as `(not compared: set of 3 class instances)`,
/// compared by kind and count only, since which of several alike instances is described first would follow hash
/// order; an instance an earlier probe held is identified by that probe alone, so two such instances agree; another
/// leaf whose debug description holds an address or a hash-ordered collection is not canonical; an
/// `ErasedInstantiator`, a `SendableErasedInstantiator`, or an instantiator with forwarded properties is not
/// traversed; how often an instance was built, and in what order, is not seen, so an instance built and discarded
/// is invisible, as is a reordering; when an instance was built is judged only for a lazily built class instance
/// itself, against the probe's value, as `DifferentialValueCreationStamp` states with what that leaves unseen; and in
/// a fixture without creation stamps, an instance a `LazilyInstantiated` or `SendableLazilyInstantiated` closure
/// captures, built before the wrapper, and a `SendableLazilyInstantiated` instance read before the describer met the
/// wrapper pass too, unless something else holds that instance, which its identity then shows.
///
/// SafeDI's wrappers are classes, numbered as such. An `Instantiator` or `SendableInstantiator` with no forwarded
/// properties is called twice, and each instance it returns described beneath it (`instantiate()`, `instantiate()
/// again`), so a builder that hands out one instance, or that captures one built outside it, differs from one that
/// builds anew on each call; beneath a second call each instantiator is called once. The instance of a
/// `LazilyInstantiated` or `SendableLazilyInstantiated` is read after the rest of the probe's value (`<4>.instance:
/// <8> C`), under the calls on the path where its wrapper was met. Where the probe's value stores a creation stamp,
/// an instance read last that was built before that value, and that the value does not hold, says so (`<4>.instance:
/// <8> C (built before the probe's value)`), so that one early read, or one instance a closure captures, is one
/// difference at that line, whichever wrapper kind built it. Otherwise a `LazilyInstantiated` whose instance was
/// read before the describer met it says so (`(already instantiated, instance read last)`), and a
/// `SendableLazilyInstantiated` keeps its state in a `Mutex`, which `Mirror` cannot see into. A wrapper whose owner
/// type and property are on the path twice already is not traversed
/// (`(not called: …)`), so a cycle, through instantiators or lazily instantiated wrappers, is unrolled once and its
/// cycle-closing builder called. Each probe traverses at most `DifferentialValueLimits.traversalsPerProbe` wrappers,
/// past which a wrapper is reported as not traversed, so a description cannot grow exponentially with the builders
/// each type holds; and a probe that runs past `DifferentialValueLimits.probeTimeLimitInSeconds` stops the probe
/// executable, which fails its path's description and, in a batch, its graph alone.
///
/// Two descriptions are compared node by node, children by label, with each identity one path numbers paired with
/// the identity the other path numbers at the same node: every node whose line differs is a difference, and what
/// lies beneath it is not compared, so a difference that adds or removes an instance renumbers nothing after it. Two
/// lines that differ only in when an instance was built, by `already instantiated` or `(built before the probe's value)`,
/// still pair, and what lies beneath them, the instance a wrapper refers to, and every later reference to either are
/// compared as usual, so an exemption of the line accepts the early build alone. A node at which a probe spent its
/// traversals, on either path, has nothing beneath it to compare, so it fails its graph's comparison with a
/// `DifferentialValueOracleError`, unless an exemption equal to the difference there accepts it: the node's two
/// lines, which agree when both paths spent their traversals there. One beneath a difference is part of that
/// difference.
///
/// Nothing is compiled when `compileVerificationIsEnabled` is `false`: `compare` and `describe` then return `nil`.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum DifferentialValueOracle {
	/// Describes `probes` in each path and compares the descriptions, exempting `exemptions`.
	/// - Returns: The comparison, or `nil` when compile verification is disabled.
	static func compare(
		feature: DifferentialValuePath,
		knownRight: DifferentialValuePath,
		probes: [DifferentialValueProbe],
		exempting exemptions: [DifferentialValueDifference] = [],
		limits: DifferentialValueLimits = DifferentialValueLimits(),
		filesToDelete: inout [URL],
	) throws -> DifferentialValueComparison? {
		guard compileVerificationIsEnabled else { return nil }
		let graph = DifferentialValueGraph(name: "", feature: feature, knownRight: knownRight, probes: probes, exemptions: exemptions)
		return try results(of: [graph], limits: limits, filesToDelete: &filesToDelete)[0].get()
	}

	/// Compares each of `graphs`, exempting its exemptions, compiling the graphs whose paths have one layout into one
	/// executable per path, so that a batch costs one compile and link of each path beside its graphs' own code, and a
	/// graph added to a batch costs a fraction of comparing it on its own. Each graph's probes are described as on their
	/// own: numbering and every `(seen …)` mark start afresh at each graph. When a batch does not compile or run, each
	/// of its graphs is compared on its own, so that a failure is its graph's, at the cost of comparing each alone; a
	/// graph whose probe spent its traversals fails alone, without the batch being compared again.
	/// - Returns: Each graph's comparison, in the order of `graphs`, or `nil` when compile verification is disabled.
	static func compare(
		graphs: [DifferentialValueGraph],
		limits: DifferentialValueLimits = DifferentialValueLimits(),
		filesToDelete: inout [URL],
	) throws -> [DifferentialValueGraphComparison]? {
		guard compileVerificationIsEnabled else { return nil }
		var comparisons = [(index: Int, comparison: DifferentialValueGraphComparison)]()
		for batch in batchesByLayout(of: graphs) {
			let batchResults = try results(of: batch.map { graphs[$0] }, limits: limits, filesToDelete: &filesToDelete)
			for (index, result) in zip(batch, batchResults) {
				comparisons.append((index, DifferentialValueGraphComparison(name: graphs[index].name, result: result)))
			}
		}
		return comparisons.sorted { $0.index < $1.index }.map(\.comparison)
	}

	/// Describes `probes` in `path`, for a test that pins what one path builds.
	/// - Returns: The description, or `nil` when compile verification is disabled.
	static func describe(
		_ path: DifferentialValuePath,
		probes: [DifferentialValueProbe],
		limits: DifferentialValueLimits = DifferentialValueLimits(),
		filesToDelete: inout [URL],
	) throws -> String? {
		guard compileVerificationIsEnabled else { return nil }
		return try describe(path, role: nil, probeGroups: [probes], limits: limits, filesToDelete: &filesToDelete)
	}

	// MARK: Private

	private struct Runtime {
		/// The directory holding `SafeDI.swiftmodule`, `SafeDI.o`, and the describer's module and object file.
		let directory: URL
		let macrosToolPath: URL
	}

	/// The modules of two graphs' paths, by layout: graphs with the same compile in one batch.
	private struct GraphLayout: Hashable {
		let feature: [DifferentialValueModule.Layout]
		let knownRight: [DifferentialValueModule.Layout]
	}

	/// The module that holds the describer, which every probe executable imports.
	private static let describerModuleName = "DifferentialValueDescriber"

	/// The SafeDI runtime and the describer, compiled once per process into a directory removed when the process
	/// exits. The SafeDI runtime is compiled from `Sources/SafeDI` because no build layout provides its object file in
	/// one place: SwiftPM's build systems put the module's objects in different places, and the test bundle the graph
	/// fuzzer's CI shards run carries only the `.swiftmodule`.
	private static let runtime = Result { try compileRuntime() }

	private static func compileRuntime() throws -> Runtime {
		guard let artifacts = SafeDIBuildArtifactLocator.locate() else {
			throw DifferentialValueOracleError(
				path: nil,
				stage: .locatingBuildArtifacts,
				description: "Could not locate SafeDI build artifacts for the differential value comparator. Build the package before running tests.",
			)
		}
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-differential-runtime-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		runtimeDirectoryToRemoveAtExit = directory
		atexit {
			if let directory = runtimeDirectoryToRemoveAtExit {
				try? FileManager.default.removeItem(at: directory)
			}
		}
		let describerFile = directory.appendingPathComponent("\(describerModuleName).swift")
		try describerSource.write(to: describerFile, atomically: true, encoding: .utf8)
		for (moduleName, sources) in [("SafeDI", try runtimeSources()), (describerModuleName, [describerFile])] {
			let result = try compileSwift(
				sources: sources,
				outputDirectory: directory,
				artifacts: SafeDIBuildArtifacts(swiftModuleSearchPath: directory, safeDIMacrosToolPath: artifacts.safeDIMacrosToolPath),
				moduleName: moduleName,
				emitsModule: true,
				parsesAsLibrary: true,
			)
			guard result.exitCode == 0 else {
				throw DifferentialValueOracleError(
					path: nil,
					stage: .compilingRuntime,
					description: "The differential value comparator's `\(moduleName)` module does not compile:\n\(result.stderr)",
				)
			}
		}
		return Runtime(directory: directory, macrosToolPath: artifacts.safeDIMacrosToolPath)
	}

	/// The Swift files of the `SafeDI` target, found from this file's location in the package.
	private static func runtimeSources() throws -> [URL] {
		let packageRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let runtimeDirectory = packageRoot.appendingPathComponent("Sources").appendingPathComponent("SafeDI")
		return try FileManager.default
			.subpathsOfDirectory(atPath: runtimeDirectory.path)
			.filter { $0.hasSuffix(".swift") }
			.sorted()
			.map { runtimeDirectory.appendingPathComponent($0) }
	}

	/// The indices of `graphs`, grouped by the layout of their paths, each group in the order of `graphs` and the
	/// groups in the order of their first graph.
	private static func batchesByLayout(of graphs: [DifferentialValueGraph]) -> [[Int]] {
		var batches = [[Int]]()
		var batchIndexByLayout = [GraphLayout: Int]()
		for (index, graph) in graphs.enumerated() {
			let layout = GraphLayout(feature: graph.feature.modules.map(\.layout), knownRight: graph.knownRight.modules.map(\.layout))
			if let batchIndex = batchIndexByLayout[layout] {
				batches[batchIndex].append(index)
			} else {
				batchIndexByLayout[layout] = batches.count
				batches.append([index])
			}
		}
		return batches
	}

	/// Compares `graphs`, whose paths have one layout, in one executable per path, or, when that fails to compile
	/// or run, each graph on its own.
	private static func results(
		of graphs: [DifferentialValueGraph],
		limits: DifferentialValueLimits,
		filesToDelete: inout [URL],
	) throws -> [Result<DifferentialValueComparison, DifferentialValueOracleError>] {
		do {
			let probeGroups = graphs.map(\.probes)
			let featureProbes = try describedProbes(of: merging(graphs.map(\.feature)), role: .feature, probeGroups: probeGroups, limits: limits, filesToDelete: &filesToDelete)
			let knownRightProbes = try describedProbes(of: merging(graphs.map(\.knownRight)), role: .knownRight, probeGroups: probeGroups, limits: limits, filesToDelete: &filesToDelete)
			var start = 0
			return graphs.map { graph in
				let range = start..<(start + graph.probes.count)
				start = range.upperBound
				let probeComparisons = zip(featureProbes[range], knownRightProbes[range]).map { feature, knownRight in
					var comparison = ProbeComparison(feature: feature, knownRight: knownRight)
					comparison.compare()
					return comparison
				}
				let spentTraversals = probeComparisons.flatMap(\.spentTraversals).filter { !graph.exemptions.contains($0.difference) }
				if let firstSpentTraversal = spentTraversals.first {
					return .failure(error(spending: firstSpentTraversal, otherSpentTraversalCount: spentTraversals.count - 1, limits: limits))
				} else {
					return .success(DifferentialValueComparison(
						featureDescription: featureProbes[range].map(\.text).joined(),
						knownRightDescription: knownRightProbes[range].map(\.text).joined(),
						differences: probeComparisons.flatMap(\.differences).filter { !graph.exemptions.contains($0) },
					))
				}
			}
		} catch let error as DifferentialValueOracleError where error.path != nil {
			guard graphs.count > 1 else { return [.failure(error)] }
			var resultsOfEachGraph = [Result<DifferentialValueComparison, DifferentialValueOracleError>]()
			for graph in graphs {
				resultsOfEachGraph += try results(of: [graph], limits: limits, filesToDelete: &filesToDelete)
			}
			return resultsOfEachGraph
		}
	}

	/// The paths of graphs with one layout as one path, each graph's files named apart by its place among them, except
	/// in a module every graph holds alike, whose files are compiled once.
	private static func merging(_ paths: [DifferentialValuePath]) -> DifferentialValuePath {
		DifferentialValuePath(modules: paths[0].modules.indices.map { moduleIndex in
			var module = paths[0].modules[moduleIndex]
			let isHeldAlikeByEveryGraph = paths.allSatisfy { path in
				path.modules[moduleIndex].fixtureFiles == module.fixtureFiles && path.modules[moduleIndex].generatedFiles == module.generatedFiles
			}
			guard !isHeldAlikeByEveryGraph else {
				return module
			}
			module.fixtureFiles = [:]
			module.generatedFiles = [:]
			for (graphIndex, path) in paths.enumerated() {
				for (fileName, contents) in path.modules[moduleIndex].fixtureFiles {
					module.fixtureFiles["\(graphIndex)_\(fileName)"] = contents
				}
				for (fileName, contents) in path.modules[moduleIndex].generatedFiles {
					module.generatedFiles["\(graphIndex)_\(fileName)"] = contents
				}
			}
			return module
		})
	}

	/// The error of a graph whose probe spent its traversals at a node no exemption accepts, the first in probe order and
	/// then in the order the descriptions print their nodes, beneath which nothing is compared.
	private static func error(
		spending spentTraversal: ProbeComparison.SpentTraversal,
		otherSpentTraversalCount: Int,
		limits: DifferentialValueLimits,
	) -> DifferentialValueOracleError {
		let pathName = switch spentTraversal.path {
		case .feature:
			"The feature path's"
		case .knownRight:
			"The known-right path's"
		case nil:
			"Both paths'"
		}
		let difference = spentTraversal.difference
		let others = otherSpentTraversalCount > 0
			? "\nOther nodes where the graph's probes spent their traversals, each accepted only by an exemption of its own: \(otherSpentTraversalCount)"
			: ""
		return DifferentialValueOracleError(
			path: spentTraversal.path,
			stage: .runningProbes,
			description: "\(pathName) probe `\(difference.probe)` spent its \(limits.traversalsPerProbe) traversals at \(difference.path.joined(separator: " > ")), so nothing beneath it is compared. Raise `DifferentialValueLimits.traversalsPerProbe`, or accept it with an exemption equal to this difference:\n\(difference)\(others)",
		)
	}

	/// Describes `path` and parses its description into each probe's section, named as the probe is, failing when the
	/// description does not hold one section per probe.
	private static func describedProbes(
		of path: DifferentialValuePath,
		role: DifferentialValuePathRole,
		probeGroups: [[DifferentialValueProbe]],
		limits: DifferentialValueLimits,
		filesToDelete: inout [URL],
	) throws -> [DescribedProbe] {
		let probes = probeGroups.flatMap(\.self)
		let description = try describe(path, role: role, probeGroups: probeGroups, limits: limits, filesToDelete: &filesToDelete)
		let sections = DescribedProbe.sections(of: description)
		guard sections.count == probes.count else {
			throw DifferentialValueOracleError(
				path: role,
				stage: .runningProbes,
				description: "The \(role.name) path's probes printed \(sections.count) probe headings for \(probes.count) probes, as when a fixture prints one:\n\(lastLines(of: description))",
			)
		}
		return zip(probes, sections).map { probe, section in
			DescribedProbe(name: probe.name, heading: section.heading, rawLines: section.lines)
		}
	}

	/// Compiles each module of `path` against the runtime, with testing enabled so that the probes can name internal
	/// declarations, then compiles and links the probes into an executable, runs it, and returns what it printed.
	private static func describe(
		_ path: DifferentialValuePath,
		role: DifferentialValuePathRole?,
		probeGroups: [[DifferentialValueProbe]],
		limits: DifferentialValueLimits,
		filesToDelete: inout [URL],
	) throws -> String {
		let runtime = try runtime.get()
		let pathName = role.map { "\($0.name) path" } ?? "path"
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-differential-\(role?.rawValue ?? "path")-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)

		var moduleDirectoriesByName = [String: URL]()
		var objectFiles = [URL]()
		for module in path.modules {
			let moduleDirectory = directory.appendingPathComponent(module.name)
			try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
			var sources = [URL]()
			for (fileName, contents) in module.fixtureFiles.sorted(by: { $0.key < $1.key }) {
				let file = moduleDirectory.appendingPathComponent("fixture_\(fileName.replacingOccurrences(of: "/", with: "_"))")
				try ("import SafeDI\n" + contents).write(to: file, atomically: true, encoding: .utf8)
				sources.append(file)
			}
			for (fileName, contents) in module.generatedFiles.sorted(by: { $0.key < $1.key }) {
				let file = moduleDirectory.appendingPathComponent(fileName.replacingOccurrences(of: "/", with: "_"))
				try ("import SafeDI\n" + contents).write(to: file, atomically: true, encoding: .utf8)
				sources.append(file)
			}
			let result = try compileSwift(
				sources: sources,
				outputDirectory: moduleDirectory,
				artifacts: SafeDIBuildArtifacts(swiftModuleSearchPath: runtime.directory, safeDIMacrosToolPath: runtime.macrosToolPath),
				activeCompilationConditions: module.activeCompilationConditions + [module.mockConditionalCompilation].compactMap(\.self),
				moduleName: module.name,
				packageName: module.packageName,
				emitsModule: true,
				moduleSearchPaths: module.dependencyModuleNames.compactMap { moduleDirectoriesByName[$0] },
				enablesTesting: true,
				parsesAsLibrary: true,
			)
			guard result.exitCode == 0 else {
				throw DifferentialValueOracleError(
					path: role,
					stage: .compilingModule(module.name),
					description: "The \(pathName)'s module `\(module.name)` does not compile:\n\(result.stderr)",
				)
			}
			moduleDirectoriesByName[module.name] = moduleDirectory
			objectFiles.append(moduleDirectory.appendingPathComponent("\(module.name).o"))
		}

		let probesFile = directory.appendingPathComponent("main.swift")
		try probesSource(moduleNames: path.modules.map(\.name), probeGroups: probeGroups, limits: limits).write(to: probesFile, atomically: true, encoding: .utf8)
		let executable = directory.appendingPathComponent("probes")
		var linkArguments = swiftCompilerCommand.arguments + [
			"-o", executable.path,
			"-module-name", "DifferentialValueProbes",
			"-swift-version", "6",
			"-I", runtime.directory.path,
		]
		for module in path.modules {
			linkArguments.append(contentsOf: ["-I", moduleDirectoriesByName[module.name]!.path])
		}
		linkArguments.append(probesFile.path)
		linkArguments.append(contentsOf: objectFiles.map(\.path))
		linkArguments.append(runtime.directory.appendingPathComponent("SafeDI.o").path)
		linkArguments.append(runtime.directory.appendingPathComponent("\(describerModuleName).o").path)
		let link = try runProcess(swiftCompilerCommand.executable, arguments: linkArguments)
		guard link.exitCode == 0 else {
			throw DifferentialValueOracleError(
				path: role,
				stage: .compilingProbes,
				description: "The \(pathName)'s probes do not compile:\n\(link.stderr)",
			)
		}

		let run = try runProcess(executable, arguments: [])
		guard run.exitCode == 0 else {
			// The describer sets an alarm for each probe, so a probe that runs past its time limit ends the process with
			// `SIGALRM`, after the heading of the probe that was running.
			let headingCount = run.stdout.split(separator: "\n").count { $0.hasPrefix("probe ") }
			let runningProbe = probeGroups.flatMap(\.self).prefix(headingCount).last.map(\.name) ?? ""
			let failure = run.exitCode == SIGALRM
				? "probe `\(runningProbe)` did not finish within its time limit, \(limits.probeTimeLimitInSeconds) s"
				: "probes did not run to completion (exit status \(run.exitCode))"
			throw DifferentialValueOracleError(
				path: role,
				stage: .runningProbes,
				description: "The \(pathName)'s \(failure):\n\(run.stderr.trimmingCharacters(in: .newlines))\nDescribed before it stopped:\n\(lastLines(of: run.stdout))",
			)
		}
		return run.stdout
	}

	/// The last hundred lines of `output`, which a probe that never finishes can make enormous.
	private static func lastLines(of output: String) -> String {
		let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
		let lineCount = 100
		return lines.count > lineCount + 1
			? "(\(lines.count - lineCount - 1) earlier lines left out)\n" + lines.suffix(lineCount + 1).joined(separator: "\n")
			: output
	}

	/// The `main.swift` of a path's probe executable: a call describing each probe, each graph's probes after a call
	/// that begins the graph.
	private static func probesSource(moduleNames: [String], probeGroups: [[DifferentialValueProbe]], limits: DifferentialValueLimits) -> String {
		let imports = moduleNames.map { "@testable import \($0)" }.joined(separator: "\n")
		let moduleNameLiterals = moduleNames.map(swiftStringLiteral(of:)).joined(separator: ", ")
		let probeCalls = probeGroups.map { probes in
			(["describer.beginGraph()"] + probes.map { probe in
				"describer.describe(probe: \(swiftStringLiteral(of: probe.name))) { (\(probe.expression)) as Any }"
			}).joined(separator: "\n")
		}.joined(separator: "\n")
		return """
		import SafeDI
		import \(describerModuleName)
		\(imports)

		let describer = Describer(moduleNames: [\(moduleNameLiterals)], probeTimeLimitInSeconds: \(limits.probeTimeLimitInSeconds), traversalsPerProbe: \(limits.traversalsPerProbe))
		\(probeCalls)

		"""
	}

	/// `string` as a Swift string literal on one line.
	private static func swiftStringLiteral(of string: String) -> String {
		"\"" + string
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\t", with: "\\t")
			+ "\""
	}

	/// The describer's module, compiled once per process and imported by every probe executable. It writes every line
	/// to standard output as it is made, with `write(2)`, which buffers nothing, so that a probe that traps leaves the
	/// description up to it. It names no C stream: Glibc imports `stdout` as a mutable global, which Swift 6 rejects.
	private static let describerSource = #"""
	import SafeDI
	#if canImport(Glibc)
	import Glibc
	#elseif canImport(Darwin)
	import Darwin
	#endif

	/// How the describer traverses a SafeDI wrapper it meets.
	enum WrapperTraversal {
		case instantiate(() -> Any)
		/// Reads the wrapper's instance after the rest of the probe's value. `isInstantiated` is whether the instance
		/// was read before the describer met the wrapper.
		case readInstanceLast(() -> Any, isInstantiated: Bool)
		case notTraversed(String?)
	}

	protocol DescribedWrapper: AnyObject {
		var wrapperTraversal: WrapperTraversal { get }
	}

	extension Instantiator: DescribedWrapper {
		var wrapperTraversal: WrapperTraversal {
			guard let noForwardedProperties = () as? T.ForwardedProperties else { return .notTraversed("forwarded arguments") }
			return .instantiate { self.instantiate(noForwardedProperties) }
		}
	}

	extension SendableInstantiator: DescribedWrapper {
		var wrapperTraversal: WrapperTraversal {
			guard let noForwardedProperties = () as? T.ForwardedProperties else { return .notTraversed("forwarded arguments") }
			return .instantiate { self.instantiate(noForwardedProperties) }
		}
	}

	extension ErasedInstantiator: DescribedWrapper {
		var wrapperTraversal: WrapperTraversal {
			.notTraversed(nil)
		}
	}

	extension SendableErasedInstantiator: DescribedWrapper {
		var wrapperTraversal: WrapperTraversal {
			.notTraversed(nil)
		}
	}

	extension LazilyInstantiated: DescribedWrapper {
		var wrapperTraversal: WrapperTraversal {
			// `Mirror` shows the wrapper's private `state`, whose case is `instantiated` once the instance was read.
			let state = Mirror(reflecting: self).descendant("state")
			let isInstantiated = state.map { Mirror(reflecting: $0).children.first?.label == "instantiated" } ?? false
			return .readInstanceLast({ self.instance }, isInstantiated: isInstantiated)
		}
	}

	extension SendableLazilyInstantiated: DescribedWrapper {
		var wrapperTraversal: WrapperTraversal {
			// The wrapper keeps its state in a `Mutex`, which `Mirror` cannot see into.
			.readInstanceLast({ self.instance }, isInstantiated: false)
		}
	}

	/// Describes the value of each probe, writing each line to standard output as it is made. A describer that renders
	/// an element of a set or dictionary, to order the collection's elements, keeps its lines instead.
	public final class Describer {
		/// - Parameters:
		///   - moduleNames: The path's modules, whose leading qualifiers type names leave out.
		///   - probeTimeLimitInSeconds: How long each probe may run before `SIGALRM` stops the process.
		///   - traversalsPerProbe: How many wrappers each probe traverses at most.
		public init(moduleNames: [String], probeTimeLimitInSeconds: UInt32, traversalsPerProbe: Int) {
			moduleQualifiers = (["Swift", "SafeDI"] + moduleNames).map { "\($0)." }
			self.probeTimeLimitInSeconds = probeTimeLimitInSeconds
			self.traversalsPerProbe = traversalsPerProbe
			writesToStandardOutput = true
			Self.letTheAlarmStopTheProcess()
		}

		/// Unblocks `SIGALRM` and restores its default action, which stops the process. A process starts with the
		/// signal mask of the thread that spawned it, and with the signals its parent ignored still ignored. Apple's
		/// Foundation resets both when it spawns a process; swift-corelibs-foundation does not, and on Linux the tests
		/// spawn this executable from Swift concurrency's threads, each of which libdispatch has block every signal but
		/// a few faults. The alarm would then stay pending, and a probe that never finishes would never stop.
		private static func letTheAlarmStopTheProcess() {
			var alarmSignal = sigset_t()
			sigemptyset(&alarmSignal)
			sigaddset(&alarmSignal, SIGALRM)
			pthread_sigmask(SIG_UNBLOCK, &alarmSignal, nil)
			_ = signal(SIGALRM, SIG_DFL)
		}

		private init(renderingFor describer: Describer) {
			moduleQualifiers = describer.moduleQualifiers
			probeTimeLimitInSeconds = 0
			traversalsPerProbe = 0
			writesToStandardOutput = false
		}

		/// Begins a graph's probes: no instance an earlier graph's probe held is marked as seen in its probes.
		public func beginGraph() {
			probeByIdentity.removeAll()
		}

		public func describe(probe name: String, value: () -> Any) {
			alarm(probeTimeLimitInSeconds)
			probeName = name
			numbersByIdentity.removeAll()
			traversalsLeft = traversalsPerProbe
			emit("probe \(Self.oneLine(name))")
			let probeValue = value()
			self.probeValue = probeValue
			probeStamp = Self.creationStamp(of: probeValue)
			objectsTheProbesValueHolds = nil
			describe(probeValue, label: "", owner: "probe", indent: 0)
			describeDeferredInstances()
			self.probeValue = nil
		}

		/// An instance of a `LazilyInstantiated` wrapper to read after the rest of the probe's value, with the calls in
		/// force where the wrapper was met.
		private struct DeferredInstance {
			let number: Int
			let read: () -> Any
			let callsOnPath: [String]
			let isInsideSecondCall: Bool
		}

		/// The label of the stored property that holds a fixture class's creation stamp, which is never described.
		private static let creationStampLabel = "\#(DifferentialValueCreationStamp.label)"

		/// What the line of an instance read last adds when the instance was built before the probe's value.
		private static let builtBeforeProbesValueNote = "\#(DescribedLine.builtBeforeProbesValueNote)"

		private let moduleQualifiers: [String]
		private let probeTimeLimitInSeconds: UInt32
		private let traversalsPerProbe: Int
		private let writesToStandardOutput: Bool
		/// A rendering describer's lines.
		private var renderedLines = [String]()
		private var probeName = ""
		/// Each object met in the current probe, numbered by first visit.
		private var numbersByIdentity = [ObjectIdentifier: Int]()
		/// Every object numbered in any probe, kept alive so that no later object takes its identifier.
		private var numberedObjects = [AnyObject]()
		/// The probe of the current graph whose value each object was first met in.
		private var probeByIdentity = [ObjectIdentifier: String]()
		private var deferredInstances = [DeferredInstance]()
		/// The wrappers being traversed, each as `<owner type>.<label>`.
		private var callsOnPath = [String]()
		/// Whether an instantiator's second call is being described, beneath which each instantiator is called once.
		private var isInsideSecondCall = false
		private var traversalsLeft = 0
		/// The current probe's value, which the generated code under comparison built.
		private var probeValue: Any?
		/// The creation stamp of the current probe's value, when it is a class instance that stores one. Generated code
		/// builds what the value holds before the value, and the describer builds everything it builds after it.
		private var probeStamp: Int?
		/// The class instances the current probe's value holds through stored properties, without calling an
		/// instantiator or reading a lazily instantiated instance, found when first needed.
		private var objectsTheProbesValueHolds: Set<ObjectIdentifier>?

		/// Describes `value`, adding `note` to the line of the class instance it is, or holds as an optional.
		private func describe(_ value: Any, label: String, owner: String, indent: Int, note: String = "") {
			let prefix = String(repeating: "  ", count: indent) + (label.isEmpty ? "" : "\(label): ")
			if type(of: value) == AnyHashable.self, let hashable = value as? AnyHashable {
				// An `AnyHashable` is described as the value it wraps, so that a set it wraps is described in order.
				describe(hashable.base, label: label, owner: owner, indent: indent, note: note)
			} else if let wrapper = value as? any DescribedWrapper {
				describe(wrapper: wrapper, prefix: prefix, label: label, owner: owner, indent: indent)
			} else {
				describe(nonWrapper: value, prefix: prefix, label: label, owner: owner, indent: indent, note: note)
			}
		}

		private func describe(wrapper: any DescribedWrapper, prefix: String, label: String, owner: String, indent: Int) {
			// An optional wrapper casts to the wrapper it holds, whose type names it.
			let typeName = typeName(of: wrapper)
			let (number, isFirstVisit, annotation) = identity(of: wrapper)
			let call = "\(owner).\(label)"
			guard isFirstVisit else {
				emit("\(prefix)<\(number)> \(typeName) (seen)")
				return
			}
			switch wrapper.wrapperTraversal {
			case let .instantiate(instantiate):
				if let reason = reasonNotToTraverse(call, verb: "called") {
					emit("\(prefix)<\(number)> \(typeName)\(annotation) (not called: \(reason))")
				} else {
					emit("\(prefix)<\(number)> \(typeName)\(annotation)")
					traversalsLeft -= 1
					callsOnPath.append(call)
					describe(instantiate(), label: "instantiate()", owner: typeName, indent: indent + 1)
					if !isInsideSecondCall {
						isInsideSecondCall = true
						describe(instantiate(), label: "instantiate() again", owner: typeName, indent: indent + 1)
						isInsideSecondCall = false
					}
					callsOnPath.removeLast()
				}
			case let .readInstanceLast(read, isInstantiated):
				// Where the probe's value is stamped, its instance's stamp tells whether it was built early, and the state
				// is not written: the probe's own instantiator calls can have read the instance before the wrapper is met.
				let state = isInstantiated && probeStamp == nil ? "already instantiated, " : ""
				if let reason = reasonNotToTraverse(call, verb: "read") {
					emit("\(prefix)<\(number)> \(typeName)\(annotation) (\(state)instance not read: \(reason))")
				} else {
					emit("\(prefix)<\(number)> \(typeName)\(annotation) (\(state)instance read last)")
					traversalsLeft -= 1
					deferredInstances.append(DeferredInstance(number: number, read: read, callsOnPath: callsOnPath + [call], isInsideSecondCall: isInsideSecondCall))
				}
			case let .notTraversed(reason):
				emit("\(prefix)<\(number)> \(typeName)\(annotation) (not traversed\(reason.map { ": \($0)" } ?? ""))")
			}
		}

		/// Why a wrapper met as `call` is not traversed: it is being traversed twice on the path already, or the probe's
		/// traversals are spent, which the oracle finds by the line's end, `DescribedLine.spentTraversalsSuffix`.
		private func reasonNotToTraverse(_ call: String, verb: String) -> String? {
			if callsOnPath.filter({ $0 == call }).count >= 2 {
				"\(call) is being \(verb) twice on this path"
			} else if traversalsLeft <= 0 {
				"the probe's \(traversalsPerProbe) traversals are spent"
			} else {
				nil
			}
		}

		private func describe(nonWrapper value: Any, prefix: String, label: String, owner: String, indent: Int, note: String) {
			let typeName = typeName(of: value)
			if Self.namesAnAddress(typeName) {
				emit("\(prefix)\(typeName) (address)")
			} else if Self.dataTypeNames.contains(String(reflecting: type(of: value))), let bytes = value as? any Collection<UInt8> {
				emit("\(prefix)Data \(bytes.count) bytes \(Self.hexadecimal(Array(bytes)))")
			} else {
				describe(mirrored: value, typeName: typeName, prefix: prefix, label: label, owner: owner, indent: indent, note: note)
			}
		}

		private func describe(mirrored value: Any, typeName: String, prefix: String, label: String, owner: String, indent: Int, note: String) {
			let mirror = Mirror(reflecting: value)
			switch mirror.displayStyle {
			case .class, .foreignReference:
				let (number, isFirstVisit, annotation) = identity(of: value as AnyObject)
				if isFirstVisit {
					emit("\(prefix)<\(number)> \(typeName)\(annotation)\(note)")
					describe(children: storedProperties(of: mirror), owner: typeName, indent: indent + 1)
				} else {
					emit("\(prefix)<\(number)> \(typeName)\(note) (seen)")
				}
			case .optional:
				if let some = mirror.children.first {
					describe(some.value, label: label, owner: owner, indent: indent, note: note)
				} else {
					emit("\(prefix)nil")
				}
			case .struct, .tuple, .collection:
				emit("\(prefix)\(typeName)")
				describe(children: Array(mirror.children), owner: typeName, indent: indent + 1)
			case .set:
				describe(unorderedChildren: Array(mirror.children), kind: "set", typeName: typeName, prefix: prefix, indent: indent)
			case .dictionary:
				describe(unorderedChildren: Array(mirror.children), kind: "dictionary", typeName: typeName, prefix: prefix, indent: indent)
			case .enum:
				if let payload = mirror.children.first {
					emit("\(prefix)\(typeName).\(payload.label ?? "")")
					describe(payload.value, label: payload.label ?? "", owner: typeName, indent: indent + 1)
				} else {
					emit("\(prefix)\(typeName).\(String(describing: value))")
				}
			case nil:
				if value is Any.Type {
					emit(prefix + unqualified(String(reflecting: value)))
				} else {
					emit("\(prefix)\(typeName) \(String(reflecting: value))")
				}
			@unknown default:
				// `Mirror.DisplayStyle` is not frozen: a style this describer does not know shows its value as a leaf.
				emit("\(prefix)\(typeName) \(String(reflecting: value))")
			}
		}

		/// A class instance's stored properties: its superclasses', the root class's first, then its own, without its
		/// creation stamp.
		private func storedProperties(of mirror: Mirror) -> [Mirror.Child] {
			Self.mirrorsOfClassHierarchy(startingAt: mirror)
				.reversed()
				.flatMap { Array($0.children) }
				.filter { $0.label != Self.creationStampLabel }
		}

		/// The mirror of a class instance, then the mirror of each of its superclasses.
		private static func mirrorsOfClassHierarchy(startingAt mirror: Mirror) -> [Mirror] {
			var mirrors = [mirror]
			while let superclassMirror = mirrors[mirrors.count - 1].superclassMirror {
				mirrors.append(superclassMirror)
			}
			return mirrors
		}

		/// The class instance `value` is, or holds as an optional.
		private static func classInstance(of value: Any) -> AnyObject? {
			let mirror = Mirror(reflecting: value)
			switch mirror.displayStyle {
			case .class:
				return value as AnyObject
			case .optional:
				return mirror.children.first.flatMap { classInstance(of: $0.value) }
			case .foreignReference, .struct, .tuple, .collection, .set, .dictionary, .enum, nil:
				return nil
			@unknown default:
				return nil
			}
		}

		/// The creation stamp of the class instance `value` is, or holds as an optional, if its class stores one.
		private static func creationStamp(of value: Any) -> Int? {
			classInstance(of: value).flatMap { object in
				mirrorsOfClassHierarchy(startingAt: Mirror(reflecting: object))
					.lazy
					.compactMap { $0.children.first { $0.label == creationStampLabel }?.value as? Int }
					.first
			}
		}

		/// Whether `instance`, the instance of a lazily instantiated wrapper read last, is a class instance built before
		/// the probe's value that the value does not hold. Generated code builds such an instance when the wrapper is
		/// first read, which the describer's own instantiator calls and reads do after the value was built. An instance
		/// the value holds is built up front by design, as a mock builds one the mocked type takes by value, and a path
		/// that holds it differs from one that does not by its identity.
		private func isBuiltBeforeTheProbesValue(_ instance: Any) -> Bool {
			guard let probeStamp, let object = Self.classInstance(of: instance), let stamp = Self.creationStamp(of: object), stamp < probeStamp else {
				return false
			}
			return !objectsHeldByTheProbesValue().contains(ObjectIdentifier(object))
		}

		private func objectsHeldByTheProbesValue() -> Set<ObjectIdentifier> {
			if let objectsTheProbesValueHolds {
				return objectsTheProbesValueHolds
			} else {
				var objects = Set<ObjectIdentifier>()
				if let probeValue {
					Self.collectObjects(heldBy: probeValue, into: &objects)
				}
				objectsTheProbesValueHolds = objects
				return objects
			}
		}

		/// Adds the class instances `value` is or holds through stored properties to `objects`, stopping at SafeDI's
		/// wrappers, whose instances only calling or reading them reaches.
		private static func collectObjects(heldBy value: Any, into objects: inout Set<ObjectIdentifier>) {
			if value is any DescribedWrapper {
				// The wrapper's builder or instance is the describer's to reach.
			} else if type(of: value) == AnyHashable.self, let hashable = value as? AnyHashable {
				collectObjects(heldBy: hashable.base, into: &objects)
			} else {
				let mirror = Mirror(reflecting: value)
				switch mirror.displayStyle {
				case .class, .foreignReference:
					guard objects.insert(ObjectIdentifier(value as AnyObject)).inserted else { return }
					for child in mirrorsOfClassHierarchy(startingAt: mirror).flatMap({ Array($0.children) }) {
						collectObjects(heldBy: child.value, into: &objects)
					}
				case .optional, .struct, .tuple, .collection, .set, .dictionary, .enum, nil:
					for child in mirror.children {
						collectObjects(heldBy: child.value, into: &objects)
					}
				@unknown default:
					for child in mirror.children {
						collectObjects(heldBy: child.value, into: &objects)
					}
				}
			}
		}

		private func describe(children: [Mirror.Child], owner: String, indent: Int) {
			for (index, child) in children.enumerated() {
				describe(child.value, label: child.label ?? "\(index)", owner: owner, indent: indent)
			}
		}

		/// The elements of a set or dictionary. When they hold no class instance, they are described in the order of
		/// their descriptions, each labeled by its place in that order. Otherwise they are not compared: which of several
		/// alike instances is described first, and so how each is numbered, would follow hash order.
		private func describe(unorderedChildren children: [Mirror.Child], kind: String, typeName: String, prefix: String, indent: Int) {
			if children.contains(where: { holdsClassInstance($0.value) }) {
				emit("\(prefix)\(typeName) (not compared: \(kind) of \(children.count) class instances)")
			} else {
				emit("\(prefix)\(typeName)")
				let elements = children
					.map { (value: $0.value, rendering: rendering(of: $0.value)) }
					.sorted { $0.rendering < $1.rendering }
				for (index, element) in elements.enumerated() {
					describe(element.value, label: "\(index)", owner: typeName, indent: indent + 1)
				}
			}
		}

		/// Whether `value` is, or holds, a class instance, a SafeDI wrapper among them.
		private func holdsClassInstance(_ value: Any) -> Bool {
			let mirror = Mirror(reflecting: value)
			switch mirror.displayStyle {
			case .class, .foreignReference:
				return true
			case .optional, .struct, .tuple, .collection, .set, .dictionary, .enum, nil:
				return mirror.children.contains { holdsClassInstance($0.value) }
			@unknown default:
				return mirror.children.contains { holdsClassInstance($0.value) }
			}
		}

		/// What a value that holds no class instance is described as, alone.
		private func rendering(of value: Any) -> String {
			let renderer = Describer(renderingFor: self)
			renderer.describe(value, label: "", owner: "element", indent: 0)
			return renderer.renderedLines.joined(separator: "\n")
		}

		private func describeDeferredInstances() {
			var index = 0
			while index < deferredInstances.count {
				let deferred = deferredInstances[index]
				index += 1
				callsOnPath = deferred.callsOnPath
				isInsideSecondCall = deferred.isInsideSecondCall
				let instance = deferred.read()
				// Marked here, where it is read last, whichever line saw it first, so that one early build is one
				// difference at one line.
				let note = isBuiltBeforeTheProbesValue(instance) ? Self.builtBeforeProbesValueNote : ""
				describe(instance, label: "<\(deferred.number)>.instance", owner: "<\(deferred.number)>", indent: 0, note: note)
			}
			callsOnPath = []
			isInsideSecondCall = false
			deferredInstances.removeAll()
		}

		/// The number of `object` in the current probe, whether this visit is its first, and what a first visit adds:
		/// the earlier probe of the graph whose value held it.
		private func identity(of object: AnyObject) -> (number: Int, isFirstVisit: Bool, annotation: String) {
			let identifier = ObjectIdentifier(object)
			if let number = numbersByIdentity[identifier] {
				return (number, false, "")
			} else {
				let number = numbersByIdentity.count + 1
				numbersByIdentity[identifier] = number
				numberedObjects.append(object)
				let earlierProbe = probeByIdentity[identifier]
				probeByIdentity[identifier] = earlierProbe ?? probeName
				return (number, true, earlierProbe.map { " (seen in probe \(Self.oneLine($0)))" } ?? "")
			}
		}

		private func typeName(of value: Any) -> String {
			unqualified(String(reflecting: type(of: value)))
		}

		/// `qualifiedName` without a leading qualifier that names a module of the path, without the runtime's
		/// `(extension in <module>):` before a type declared in an extension in such a module, and with `(private)` where
		/// the runtime names the context of a private, fileprivate, or local type by its address:
		/// `Swift.Array<App.Outer.Inner>` is `Array<Outer.Inner>`, `App.App.Inner` is `App.Inner`,
		/// `(extension in App):Core.Thing.Inner` is `Thing.Inner`, `(extension in Foundation):Swift.String.Encoding` is
		/// `(extension in Foundation):String.Encoding`, and `App.(unknown context at $1021957f0).Helper` is
		/// `(private).Helper`.
		private func unqualified(_ qualifiedName: String) -> String {
			let extensionPrefix = "(extension in "
			var result = ""
			var remaining = Substring(qualifiedName)
			var startsQualifiedName = true
			while let character = remaining.first {
				if remaining.hasPrefix("(unknown context at $"), let end = remaining.firstIndex(of: ")") {
					result += "(private)"
					remaining = remaining[remaining.index(after: end)...]
					startsQualifiedName = false
				} else if startsQualifiedName, remaining.hasPrefix(extensionPrefix), let end = remaining.firstIndex(of: ")"), remaining[end...].hasPrefix("):") {
					// The extension's module, then the extended type's qualified name, which may begin with another extension.
					let extensionEnd = remaining.index(end, offsetBy: 2)
					if !moduleQualifiers.contains("\(remaining[remaining.index(remaining.startIndex, offsetBy: extensionPrefix.count)..<end]).") {
						result += remaining[..<extensionEnd]
					}
					remaining = remaining[extensionEnd...]
				} else if startsQualifiedName, let qualifier = moduleQualifiers.first(where: { remaining.hasPrefix($0) }) {
					remaining = remaining.dropFirst(qualifier.count)
					startsQualifiedName = false
				} else {
					result.append(character)
					startsQualifiedName = !(character.isLetter || character.isNumber || character == "_" || character == ".")
					remaining = remaining.dropFirst()
				}
			}
			return result
		}

		/// The names Foundation's `Data` has: on Apple platforms, and in swift-foundation, which Linux's Foundation
		/// re-exports.
		private static let dataTypeNames: Set<String> = ["Foundation.Data", "FoundationEssentials.Data"]

		/// Whether a value of the type named `typeName` is an address, which differs from run to run.
		private static func namesAnAddress(_ typeName: String) -> Bool {
			typeName == "ObjectIdentifier"
				|| typeName == "OpaquePointer"
				|| (typeName.hasPrefix("Unsafe") && typeName.contains("Pointer"))
				|| typeName.hasPrefix("AutoreleasingUnsafeMutablePointer")
		}

		private static func hexadecimal(_ bytes: [UInt8]) -> String {
			let digits = Array("0123456789abcdef")
			return String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0xF)]] })
		}

		/// `name` on one line, its line breaks and tabs escaped.
		private static func oneLine(_ name: String) -> String {
			name
				.replacing("\\", with: "\\\\")
				.replacing("\n", with: "\\n")
				.replacing("\r", with: "\\r")
				.replacing("\t", with: "\\t")
		}

		private func emit(_ line: String) {
			guard writesToStandardOutput else {
				renderedLines.append(line)
				return
			}
			let bytes = Array((line + "\n").utf8)
			var offset = 0
			while offset < bytes.count {
				let written = bytes.withUnsafeBufferPointer { write(STDOUT_FILENO, $0.baseAddress! + offset, $0.count - offset) }
				if written > 0 {
					offset += written
				} else if written < 0, errno == EINTR {
					continue
				} else {
					// A description that loses a line would compare as another value: end the run as a failure instead.
					exit(74)
				}
			}
		}
	}

	"""#
}

/// The directory `DifferentialValueOracle` compiled the SafeDI runtime into, removed when the process exits.
nonisolated(unsafe) private var runtimeDirectoryToRemoveAtExit: URL?

// MARK: - Comparing descriptions

/// A line of a description: `<indentation><label>: <value>`, or, first in its probe, the probe's value alone.
private struct DescribedLine {
	init(_ line: Substring, isProbeValue: Bool) {
		let indentation = line.prefix { $0 == " " }.count
		let text = line.dropFirst(indentation)
		let separator = isProbeValue ? nil : text.range(of: ": ")
		let value = separator.map { text[$0.upperBound...] } ?? text
		indent = indentation / 2
		self.text = text
		label = separator.map { String(text[..<$0.lowerBound]) } ?? ""
		if value.hasPrefix("<"), let end = value.firstIndex(of: ">") {
			let afterIdentity = value[value.index(after: end)...].dropFirst()
			let isSeen = afterIdentity.hasSuffix(Self.seenSuffix)
			identity = String(value[value.index(after: value.startIndex)..<end])
			self.isSeen = isSeen
			rest = isSeen ? afterIdentity.dropLast(Self.seenSuffix.count) : afterIdentity
		} else {
			identity = nil
			isSeen = false
			rest = value
		}
	}

	static let seenSuffix = " (seen)"
	/// How the describer ends the line of a wrapper it does not traverse because the probe's traversals are spent.
	static let spentTraversalsSuffix = " traversals are spent)"

	let indent: Int
	/// The line without its indentation.
	let text: Substring
	let label: String
	/// The number of the identity the value begins with: `4` in `<4> A`.
	let identity: String?
	/// Whether the value refers to an instance seen earlier in its probe.
	let isSeen: Bool
	/// The value without its identity and `(seen)`.
	let rest: Substring

	/// Whether the line is a wrapper the describer did not traverse because the probe's traversals were spent, so that
	/// nothing beneath it is described.
	var spendsTraversals: Bool {
		identity != nil && rest.hasSuffix(Self.spentTraversalsSuffix)
	}

	/// The value without its identity, `(seen)`, and what the describer writes about when an instance was built: the
	/// `already instantiated, ` of a lazily instantiated wrapper whose instance was read before it was described, and
	/// the `(built before the probe's value)` of an instance read last.
	var restWithoutWhenBuilt: String {
		String(rest)
			.replacing(" (already instantiated, instance ", with: " (instance ")
			.replacing(Self.builtBeforeProbesValueNote, with: "")
	}

	/// What the describer adds to the line of an instance read last that was built before the probe's value, before
	/// any `(seen)`.
	static let builtBeforeProbesValueNote = " (built before the probe's value)"

	/// The number of the wrapper whose instance a line read last describes: `6` for `<6>.instance`.
	var deferredWrapperToken: String {
		String(label.dropFirst().prefix { $0 != ">" })
	}
}

/// A probe's section of a description, as a tree of its lines: the probe's value, then each instance read last.
private struct DescribedProbe {
	/// A description split at its `probe <name>` headings.
	static func sections(of description: String) -> [(heading: Substring, lines: [Substring])] {
		var sections = [(heading: Substring, lines: [Substring])]()
		for line in description.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
			if line.hasPrefix("probe ") {
				sections.append((line, []))
			} else if !sections.isEmpty {
				sections[sections.count - 1].lines.append(line)
			}
		}
		return sections
	}

	/// - Parameters:
	///   - name: The probe's name, which its heading prints on one line.
	///   - heading: The section's heading as printed.
	init(name: String, heading: Substring, rawLines: [Substring]) {
		self.name = name
		text = ([heading] + rawLines).map { "\($0)\n" }.joined()
		var lines = [DescribedLine]()
		var children = [[Int]]()
		var paths = [[String]]()
		var topLevel = [Int]()
		var firstVisitPathByToken = [String: [String]]()
		var enclosing = [(indent: Int, index: Int)]()
		for rawLine in rawLines {
			let line = DescribedLine(rawLine, isProbeValue: lines.isEmpty)
			let index = lines.count
			while let last = enclosing.last, last.indent >= line.indent {
				enclosing.removeLast()
			}
			if let parent = enclosing.last {
				children[parent.index].append(index)
				paths.append(paths[parent.index] + [line.label])
			} else {
				topLevel.append(index)
				paths.append([line.label.isEmpty ? String(line.text) : line.label])
			}
			if let identity = line.identity, !line.isSeen {
				firstVisitPathByToken[identity] = paths[index]
			}
			lines.append(line)
			children.append([])
			enclosing.append((line.indent, index))
		}
		self.lines = lines
		self.children = children
		self.paths = paths
		self.topLevel = topLevel
		self.firstVisitPathByToken = firstVisitPathByToken
	}

	/// A child of a line, keyed by its label and how many earlier children have that label.
	struct ChildKey: Hashable {
		let label: String
		let occurrence: Int
	}

	let name: String
	/// The section as the description printed it, heading included.
	let text: String
	let lines: [DescribedLine]
	let children: [[Int]]
	/// The labels from the probe's value to each line, the top-level line named by its text or its label.
	let paths: [[String]]
	/// The probe's value, then each instance read last.
	let topLevel: [Int]
	/// The path to the first visit of each identity.
	let firstVisitPathByToken: [String: [String]]

	func keyedChildren(of index: Int) -> [(key: ChildKey, index: Int)] {
		var occurrences = [String: Int]()
		return children[index].map { childIndex in
			let label = lines[childIndex].label
			let occurrence = occurrences[label, default: 0]
			occurrences[label] = occurrence + 1
			return (ChildKey(label: label, occurrence: occurrence), childIndex)
		}
	}

	/// A line as a difference shows it: a `(seen)` line names where the instance it refers to was first seen.
	func differenceText(of index: Int) -> String {
		let line = lines[index]
		guard line.isSeen, let identity = line.identity else { return String(line.text) }
		let firstVisit = firstVisitPathByToken[identity].map { ", first at \($0.joined(separator: " > "))" } ?? ""
		return "\(line.text.dropLast(DescribedLine.seenSuffix.count)) (seen\(firstVisit))"
	}
}

/// Compares one probe's two descriptions node by node, children by label, pairing the identity each path numbers at
/// a node with the identity the other numbers there.
private struct ProbeComparison {
	init(feature: DescribedProbe, knownRight: DescribedProbe) {
		self.feature = feature
		self.knownRight = knownRight
	}

	/// A compared node at which the probe spent its traversals, on one path or both, so nothing beneath it is compared.
	struct SpentTraversal {
		/// The node's lines on each path, which agree when the probe spent its traversals there on both.
		let difference: DifferentialValueDifference
		/// The path that spent its traversals there, or `nil` for both.
		let path: DifferentialValuePathRole?
	}

	private(set) var differences = [DifferentialValueDifference]()
	/// The compared nodes at which the probe spent its traversals, in the order the descriptions print them. A node
	/// beneath a difference is not compared, so one there is part of that difference.
	private(set) var spentTraversals = [SpentTraversal]()

	mutating func compare() {
		compareTrees(from: .both(feature.topLevel[0], knownRight.topLevel[0]))
		// An instance read last pairs with the other path's instance of the wrapper its wrapper paired with. One whose
		// wrapper paired with nothing lies beneath a difference already recorded. A line a fixture printed has no
		// wrapper and pairs with nothing.
		let featureDeferredIndexByToken = Dictionary(feature.topLevel.dropFirst().map { (feature.lines[$0].deferredWrapperToken, $0) }, uniquingKeysWith: { first, _ in first })
		for knownRightIndex in knownRight.topLevel.dropFirst() {
			let featureToken = featureTokenByKnownRightToken[knownRight.lines[knownRightIndex].deferredWrapperToken]
			if let featureIndex = featureToken.flatMap({ featureDeferredIndexByToken[$0] }) {
				compareTrees(from: .both(featureIndex, knownRightIndex))
			}
		}
	}

	// MARK: Private

	private enum NodePair {
		case both(Int, Int)
		case featureOnly(Int)
		case knownRightOnly(Int)
	}

	private let feature: DescribedProbe
	private let knownRight: DescribedProbe
	private var knownRightTokenByFeatureToken = [String: String]()
	private var featureTokenByKnownRightToken = [String: String]()

	/// Compares the trees beneath `root` in the order the describer printed them, so that each identity is paired at
	/// its first visit before a reference to it is compared.
	private mutating func compareTrees(from root: NodePair) {
		var pairs = [root]
		while let pair = pairs.popLast() {
			switch pair {
			case let .both(featureIndex, knownRightIndex):
				let agreement = agreement(featureIndex, knownRightIndex)
				let featureSpends = feature.lines[featureIndex].spendsTraversals
				let knownRightSpends = knownRight.lines[knownRightIndex].spendsTraversals
				if featureSpends || knownRightSpends {
					spentTraversals.append(SpentTraversal(
						difference: difference(at: pair),
						path: featureSpends == knownRightSpends ? nil : featureSpends ? .feature : .knownRight,
					))
				} else {
					switch agreement {
					case .agree:
						pairs += alignedChildren(of: featureIndex, and: knownRightIndex).reversed()
					case .differOnlyInWhenBuilt:
						differences.append(difference(at: pair))
						pairs += alignedChildren(of: featureIndex, and: knownRightIndex).reversed()
					case .differ:
						differences.append(difference(at: pair))
					}
				}
			case .featureOnly, .knownRightOnly:
				differences.append(difference(at: pair))
			}
		}
	}

	private enum Agreement {
		case agree
		/// The lines differ only in what the describer writes about when an instance was built, a difference at the
		/// line alone: what lies beneath it, the instance a wrapper's line refers to, and every later reference to
		/// either are compared as usual.
		case differOnlyInWhenBuilt
		case differ
	}

	/// How two lines agree, pairing their identities when both are first visits that agree, or that differ only in
	/// when an instance was built.
	private mutating func agreement(_ featureIndex: Int, _ knownRightIndex: Int) -> Agreement {
		let featureLine = feature.lines[featureIndex]
		let knownRightLine = knownRight.lines[knownRightIndex]
		switch (featureLine.identity, knownRightLine.identity) {
		case (nil, nil):
			return featureLine.rest == knownRightLine.rest ? .agree : .differ
		case let (featureToken?, knownRightToken?):
			guard featureLine.isSeen == knownRightLine.isSeen else { return .differ }
			if featureLine.isSeen {
				guard featureLine.restWithoutWhenBuilt == knownRightLine.restWithoutWhenBuilt, knownRightTokenByFeatureToken[featureToken] == knownRightToken else {
					return .differ
				}
				return featureLine.rest == knownRightLine.rest ? .agree : .differOnlyInWhenBuilt
			} else if featureLine.restWithoutWhenBuilt == knownRightLine.restWithoutWhenBuilt {
				knownRightTokenByFeatureToken[featureToken] = knownRightToken
				featureTokenByKnownRightToken[knownRightToken] = featureToken
				return featureLine.rest == knownRightLine.rest ? .agree : .differOnlyInWhenBuilt
			} else {
				return .differ
			}
		case (_?, nil), (nil, _?):
			return .differ
		}
	}

	/// The children of two lines that agree, paired by key in the known-right path's order, then the feature path's
	/// children it has no child for.
	private func alignedChildren(of featureIndex: Int, and knownRightIndex: Int) -> [NodePair] {
		let featureChildren = feature.keyedChildren(of: featureIndex)
		let knownRightChildren = knownRight.keyedChildren(of: knownRightIndex)
		let featureIndexByKey = Dictionary(uniqueKeysWithValues: featureChildren.map { ($0.key, $0.index) })
		let knownRightKeys = Set(knownRightChildren.map(\.key))
		return knownRightChildren.map { child in
			featureIndexByKey[child.key].map { .both($0, child.index) } ?? .knownRightOnly(child.index)
		} + featureChildren.filter { !knownRightKeys.contains($0.key) }.map { .featureOnly($0.index) }
	}

	/// The difference a node pair shows: each path's line, or `(absent)` where a path has no such node.
	private func difference(at pair: NodePair) -> DifferentialValueDifference {
		let absent = "(absent)"
		return switch pair {
		case let .both(featureIndex, knownRightIndex):
			DifferentialValueDifference(probe: knownRight.name, path: knownRight.paths[knownRightIndex], feature: feature.differenceText(of: featureIndex), knownRight: knownRight.differenceText(of: knownRightIndex))
		case let .featureOnly(featureIndex):
			DifferentialValueDifference(probe: knownRight.name, path: feature.paths[featureIndex], feature: feature.differenceText(of: featureIndex), knownRight: absent)
		case let .knownRightOnly(knownRightIndex):
			DifferentialValueDifference(probe: knownRight.name, path: knownRight.paths[knownRightIndex], feature: absent, knownRight: knownRight.differenceText(of: knownRightIndex))
		}
	}
}

// MARK: - Assertion

/// Records an `Issue` for each difference between what the feature path and the known-right path build for
/// `probes`, except those equal to one of `exemptions`, with both descriptions, and throws when a probe spends its
/// `limits`' traversals at a node no exemption accepts. Use it beside a full `==` comparison of the generated code: a
/// value the feature path builds differently is a defect the code comparison can pass.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func expectDifferentialValuesAgree(
	feature: DifferentialValuePath,
	knownRight: DifferentialValuePath,
	probes: [DifferentialValueProbe],
	exempting exemptions: [DifferentialValueDifference] = [],
	limits: DifferentialValueLimits = DifferentialValueLimits(),
	filesToDelete: inout [URL],
	sourceLocation: SourceLocation = #_sourceLocation,
) throws {
	guard let comparison = try DifferentialValueOracle.compare(feature: feature, knownRight: knownRight, probes: probes, exempting: exemptions, limits: limits, filesToDelete: &filesToDelete) else { return }
	for difference in comparison.differences {
		Issue.record(
			"The feature path builds other values than the known-right path for \(difference)\n\(comparison.report)",
			sourceLocation: sourceLocation,
		)
	}
}

// MARK: - Graph fuzzer

extension DifferentialValuePath {
	/// One module holding a fuzzer graph's fixture, with its files named as `executeSafeDIToolTest` names them, and
	/// the files the tool generated for it.
	init(fixture: GraphFuzzerFixture, generatedFiles: [String: String]) {
		self.init(fixtureFiles: Dictionary(uniqueKeysWithValues: zip(fixture.fileNames, fixture.swiftFileContent)), generatedFiles: generatedFiles)
	}
}

extension GraphFuzzerFixture {
	/// A probe constructing each root of the graph, in declaration order, then one calling the generated `mock()` of
	/// each mocked type whose parameters, if it has any, all have default values, in file name order. A mock with a
	/// required parameter has no probe: the comparator has no value to pass it, and a feature that needs one judged
	/// passes probes of its own.
	/// A root's builder of a tree the comparator does not traverse – `spellSeamBuilder`, `spellHostBuilder` and
	/// `aliasSeamBuilder`, instantiators whose types forward a value – gets a probe calling it with a sample value,
	/// so that the seam's tree beneath, and the seam call's arguments, are judged too.
	func differentialValueProbes(generatedFiles: [String: String]) -> [DifferentialValueProbe] {
		var probes = [DifferentialValueProbe]()
		let spelledType = swiftFileContent.lazy.flatMap(GraphFuzzerSourceLine.lines).compactMap { line -> String? in
			guard case let .property(attribute, label, type) = line, attribute == "@Forwarded", label == GraphFuzzerSpelling.label else { return nil }
			return type
		}.first
		let spelledSample = spelledType.flatMap(GraphFuzzerSpelling.spelling(ofType:))?.sampleExpression(prefix: typeNamePrefix)
		for content in swiftFileContent {
			var previousAttributeDeclaresRoot = false
			var rootName: String?
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .instantiableAttribute(arguments):
					previousAttributeDeclaresRoot = arguments.contains("isRoot: true")
					rootName = nil
				case let .typeDeclaration(name):
					if previousAttributeDeclaresRoot {
						probes.append(DifferentialValueProbe("\(name)()"))
						rootName = name
					}
					previousAttributeDeclaresRoot = false
				case let .property(_, label, _):
					previousAttributeDeclaresRoot = false
					guard let rootName else { continue }
					switch label {
					case "spellSeamBuilder", "spellHostBuilder":
						if let spelledSample {
							probes.append(DifferentialValueProbe("\(rootName)().\(label).instantiate(\(spelledSample))"))
						}
					case "aliasSeamBuilder":
						probes.append(DifferentialValueProbe("\(rootName)().\(label).instantiate(\(typeNamePrefix)AliasValue())"))
					default:
						continue
					}
				case .instantiateMethod, .other:
					previousAttributeDeclaresRoot = false
				}
			}
		}
		let mockFileSuffix = "+SafeDIMock.swift"
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where fileName.hasSuffix(mockFileSuffix) && Self.mockTakesNoRequiredParameter(contents) {
			probes.append(DifferentialValueProbe("\(fileName.dropLast(mockFileSuffix.count)).mock()"))
		}
		return probes
	}

	/// Whether the generated `mock()` in `contents` takes no parameter without a default value. A mock without
	/// parameters is declared on one line, `static func mock() -> T {`; one with parameters lists them a line each.
	private static func mockTakesNoRequiredParameter(_ contents: String) -> Bool {
		let lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
		let signature = lines.drop { !$0.contains("static func mock(") }
		let parameters = signature.first?.hasSuffix("static func mock(") == true
			? signature.dropFirst().prefix { !$0.hasPrefix(")") }
			: []
		return parameters.allSatisfy { $0.contains(" = ") }
	}
}
