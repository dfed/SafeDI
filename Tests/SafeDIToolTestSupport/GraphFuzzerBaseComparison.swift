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

// MARK: - Base comparison

/// Compares what two built `SafeDITool` executables do with a fuzzer graph: a pull request's base's and its head's.
///
/// A rewrite that means to change no output proves it here rather than by keeping the code it replaces in the tree
/// beside the new code: CI builds the base's tool, and each graph of the fuzzer's corpora runs through both tools with
/// the same arguments over the same files, in the same directories, one tool after the other. Everything either tool
/// writes, and how each run ends, is compared byte for byte: each step's exit status and standard error, every
/// generated file, the DOT graph of each `generate` (`--dot-file-output`, so a change that draws the graph another way
/// shows), every `.safedi` file, and the manifest `scan` writes. Only the scan cache is left out, which a run
/// reads to save work and which no build compiles or hands another module.
///
/// A graph in one module runs as the SwiftPM plugin runs the tool (`scan`, then `generate --swift-manifest`); a graph
/// split across modules (`GraphFuzzerFixture.modules`) runs as Bazel's rule runs it, one `generate` per module in
/// dependency order, each reading the `.safedi` files of the modules it lists, as the fuzzer's own module-info flow
/// lists them (`GraphFuzzerFixture.dependencyLists(modules:integration:listsTransitiveDependencies:)`), and stopping at
/// the first module the tool rejects, since a module that depends on it gets no `.safedi` to read.
///
/// Nothing of this lives in `Sources`: both tools are run as processes, so the base is any commit whose tool takes
/// these arguments. A base whose tool rejects an argument the head passes (or the reverse), which ArgumentParser
/// reports with exit status 64, is a problem of the comparison, not a difference (`GraphFuzzerBaseComparison.Result`).
enum GraphFuzzerBaseComparison {
	/// How the graph was run.
	enum Flow: String, Sendable {
		/// `scan`, then `generate --swift-manifest`, over one module.
		case plugin
		/// One `generate --combined-output --module-info-output` per module.
		case moduleInfo = "module-info"
	}

	/// What one tool did with a graph: each step it ran, in order, and every file the steps wrote.
	struct Record: Equatable, Sendable {
		struct Step: Equatable, Sendable {
			/// `scan`, `generate`, or `generate <Module>`.
			let name: String
			let exitCode: Int32
			/// The step's standard error, with the graph's directory reduced to `<graph>`.
			let stderr: String
			/// The step's standard output, reduced as `stderr` is.
			var stdout = ""
		}

		var steps: [Step]
		/// The bytes of every file the steps wrote, by its path relative to the directory the steps wrote into.
		var outputs: [String: Data]
	}

	/// One way two records differ.
	enum Difference: Equatable, Sendable, CustomStringConvertible {
		/// The tools ran other steps: one stopped where the other went on.
		case steps(base: [String], head: [String])
		case exitStatus(step: String, base: Int32, head: Int32)
		case diagnostics(step: String, base: String, head: String)
		case standardOutput(step: String, base: String, head: String)
		case fileOnlyInBase(path: String)
		case fileOnlyInHead(path: String)
		case fileBytes(path: String, base: Data, head: Data)

		var description: String {
			switch self {
			case let .steps(base, head):
				"steps: base ran \(base.joined(separator: ", ")); head ran \(head.joined(separator: ", "))"
			case let .exitStatus(step, base, head):
				"exit status of \(step): base \(base), head \(head)"
			case let .diagnostics(step, base, head):
				"diagnostics of \(step): \(Self.firstDifference(base: base, head: head))"
			case let .standardOutput(step, base, head):
				"standard output of \(step): \(Self.firstDifference(base: base, head: head))"
			case let .fileOnlyInBase(path):
				"file \(path): written by the base only"
			case let .fileOnlyInHead(path):
				"file \(path): written by the head only"
			case let .fileBytes(path, base, head):
				if let baseText = String(data: base, encoding: .utf8), let headText = String(data: head, encoding: .utf8) {
					"file \(path): \(Self.firstDifference(base: baseText, head: headText))"
				} else {
					"file \(path): \(base.count) bytes in the base, \(head.count) in the head, first differing at byte \(zip(base, head).prefix { $0 == $1 }.count)"
				}
			}
		}

		/// The first line at which `base` and `head` differ, with both lines.
		private static func firstDifference(base: String, head: String) -> String {
			let baseLines = base.components(separatedBy: "\n")
			let headLines = head.components(separatedBy: "\n")
			let index = zip(baseLines, headLines).prefix { $0 == $1 }.count
			let baseLine = index < baseLines.count ? "`\(baseLines[index])`" : "(none)"
			let headLine = index < headLines.count ? "`\(headLines[index])`" : "(none)"
			return "line \(index + 1): base \(baseLine), head \(headLine)"
		}
	}

	/// The comparison of one graph.
	struct Result: Equatable, Sendable {
		let seed: UInt64
		let flow: Flow
		/// Every way the two records differ, steps first, then files in path order.
		let differences: [Difference]
		/// Why the comparison could not judge the graph: a tool rejected the arguments it was given. A graph with a
		/// problem has no differences.
		let problem: String?
		/// The paths of the files the two tools wrote between them, relative to the directory they wrote into, in order.
		let filePaths: [String]
	}

	/// The `SafeDITool` this test process was built beside, which a run of the tests compares with itself.
	static func builtTool() throws -> URL {
		guard let artifacts = SafeDIBuildArtifactLocator.locate() else {
			throw GraphFuzzerInfrastructureError(description: "Could not locate SafeDI build artifacts to find the SafeDITool executable.")
		}
		return artifacts.safeDIMacrosToolPath.deletingLastPathComponent().appendingPathComponent("SafeDITool")
	}

	/// The exit status ArgumentParser gives a command line it cannot parse (`EX_USAGE`).
	static let argumentErrorExitCode: Int32 = 64

	/// Runs `fixture` through `base` and then `head`, in the same directories, and compares what each did.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func compare(_ fixture: GraphFuzzerFixture, base: URL, head: URL) async throws -> Result {
		for tool in [base, head] where !FileManager.default.isExecutableFile(atPath: tool.path) {
			throw GraphFuzzerInfrastructureError(description: "No SafeDITool executable at \(tool.path).")
		}
		let directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-base-comparison-")
		defer { try? FileManager.default.removeItem(at: directory) }
		let layout = try Layout(writing: fixture, into: directory)
		let baseRecord = try await layout.record(running: base)
		let headRecord = try await layout.record(running: head)
		if let problem = argumentProblem(in: baseRecord, side: "base") ?? argumentProblem(in: headRecord, side: "head") {
			return Result(seed: fixture.seed, flow: layout.flow, differences: [], problem: problem, filePaths: [])
		}
		return Result(
			seed: fixture.seed,
			flow: layout.flow,
			differences: differences(base: baseRecord, head: headRecord),
			problem: nil,
			filePaths: Set(baseRecord.outputs.keys).union(headRecord.outputs.keys).sorted(),
		)
	}

	/// Every way `base` and `head` differ: the steps they ran, then each step's exit status, diagnostics and standard
	/// output, then each
	/// file either wrote, in path order.
	static func differences(base: Record, head: Record) -> [Difference] {
		var differences = [Difference]()
		let baseStepNames = base.steps.map(\.name)
		let headStepNames = head.steps.map(\.name)
		if baseStepNames != headStepNames {
			differences.append(.steps(base: baseStepNames, head: headStepNames))
		}
		for (baseStep, headStep) in zip(base.steps, head.steps) where baseStep.name == headStep.name {
			if baseStep.exitCode != headStep.exitCode {
				differences.append(.exitStatus(step: baseStep.name, base: baseStep.exitCode, head: headStep.exitCode))
			}
			if baseStep.stderr != headStep.stderr {
				differences.append(.diagnostics(step: baseStep.name, base: baseStep.stderr, head: headStep.stderr))
			}
			if baseStep.stdout != headStep.stdout {
				differences.append(.standardOutput(step: baseStep.name, base: baseStep.stdout, head: headStep.stdout))
			}
		}
		for path in Set(base.outputs.keys).union(head.outputs.keys).sorted() {
			switch (base.outputs[path], head.outputs[path]) {
			case let (.some(baseBytes), .some(headBytes)):
				if baseBytes != headBytes {
					differences.append(.fileBytes(path: path, base: baseBytes, head: headBytes))
				}
			case (.some, .none):
				differences.append(.fileOnlyInBase(path: path))
			case (.none, .some):
				differences.append(.fileOnlyInHead(path: path))
			case (.none, .none):
				break
			}
		}
		return differences
	}

	/// Why `record` cannot be compared: a step whose command line the tool rejected.
	static func argumentProblem(in record: Record, side: String) -> String? {
		record.steps.first { $0.exitCode == argumentErrorExitCode }.map { step in
			"the \(side) tool rejected the arguments of \(step.name): \(step.stderr.split(separator: "\n").first ?? "")"
		}
	}

	/// A graph's files written to disk as one of the two flows reads them, and the steps that flow runs.
	private struct Layout {
		let flow: Flow
		let directory: URL
		/// Where every step writes, emptied before each tool runs.
		let workDirectory: URL
		let commands: [(name: String, arguments: [String])]

		init(writing fixture: GraphFuzzerFixture, into directory: URL) throws {
			let workDirectory = directory.appendingPathComponent("Work")
			let fixtureDirectory = directory.appendingPathComponent("Fixture")
			let inputsDirectory = directory.appendingPathComponent("Inputs")
			self.directory = directory
			self.workDirectory = workDirectory
			if let modules = fixture.modules {
				flow = .moduleInfo
				commands = try Self.moduleInfoCommands(of: fixture, modules: modules, fixtureDirectory: fixtureDirectory, workDirectory: workDirectory, inputsDirectory: inputsDirectory)
			} else {
				flow = .plugin
				commands = try Self.pluginCommands(of: fixture, fixtureDirectory: fixtureDirectory, workDirectory: workDirectory, inputsDirectory: inputsDirectory)
			}
		}

		/// Runs `tool` through every step, in an emptied work directory, and reads what the steps wrote.
		func record(running tool: URL) async throws -> Record {
			try? FileManager.default.removeItem(at: workDirectory)
			for outputDirectory in ["Output", "ModuleInfo"] {
				try FileManager.default.createDirectory(at: workDirectory.appendingPathComponent(outputDirectory), withIntermediateDirectories: true)
			}
			var steps = [Record.Step]()
			for command in commands {
				let result = try await runProcess(tool, arguments: command.arguments)
				steps.append(Record.Step(
					name: command.name,
					exitCode: result.exitCode,
					stderr: result.stderr.replacingOccurrences(of: directory.path, with: "<graph>"),
					stdout: result.stdout.replacingOccurrences(of: directory.path, with: "<graph>"),
				))
				guard result.exitCode == 0 else { break }
			}
			return Record(steps: steps, outputs: try Self.files(in: workDirectory))
		}

		/// Every file under `directory` but a scan cache, by its path relative to `directory`.
		private static func files(in directory: URL) throws -> [String: Data] {
			var files = [String: Data]()
			guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return files }
			let prefix = directory.resolvingSymlinksInPath().path + "/"
			for case let file as URL in enumerator where file.pathExtension != "safediScanCache" {
				guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
				let path = file.resolvingSymlinksInPath().path
				files[path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path] = try Data(contentsOf: file)
			}
			return files
		}

		/// The plugin's steps over a graph in one module: `scan` over a CSV of every file, each mock-scoped, then
		/// `generate` with the manifest `scan` wrote, each told the graph's conditions.
		private static func pluginCommands(of fixture: GraphFuzzerFixture, fixtureDirectory: URL, workDirectory: URL, inputsDirectory: URL) throws -> [(name: String, arguments: [String])] {
			var usedNames = Set<String>()
			var paths = [String]()
			for (index, (fileName, content)) in zip(fixture.fileNames, fixture.swiftFileContent).enumerated() {
				// Two files of one name would overwrite each other; the second is kept under a name of its own.
				let name = usedNames.insert(fileName).inserted ? fileName : "\(index)_\(fileName.replacingOccurrences(of: "/", with: "_"))"
				usedNames.insert(name)
				paths.append(try write(content, to: fixtureDirectory.appendingPathComponent(name)))
			}
			let inputsFile = inputsDirectory.appendingPathComponent("inputs.csv")
			_ = try write(paths.joined(separator: ","), to: inputsFile)
			let manifestFile = workDirectory.appendingPathComponent("manifest.json")
			let conditions = fixture.activeCompilationConditions.isEmpty ? [] : ["--active-compilation-conditions"] + fixture.activeCompilationConditions
			return [
				("scan", [
					"scan",
					"--input-sources-file", inputsFile.path,
					"--project-root", fixtureDirectory.path,
					"--output-directory", workDirectory.appendingPathComponent("Output").path,
					"--manifest-file", manifestFile.path,
					"--mock-scoped-files",
				] + paths + conditions),
				("generate", ["generate", inputsFile.path, "--swift-manifest", manifestFile.path, "--dot-file-output", workDirectory.appendingPathComponent("Output").appendingPathComponent("graph.dot").path] + conditions),
			]
		}

		/// Bazel's steps over a graph split across modules: per module, in dependency order, `generate` over a CSV of the
		/// module's files, naming the module and its package, reading the `.safedi` of each module it lists, and writing
		/// its own and one combined output.
		private static func moduleInfoCommands(of fixture: GraphFuzzerFixture, modules: [GraphFuzzerModule], fixtureDirectory: URL, workDirectory: URL, inputsDirectory: URL) throws -> [(name: String, arguments: [String])] {
			let presentModules = Set(modules)
			let dependencyLists = fixture.dependencyLists(modules: modules, integration: .moduleInfo, listsTransitiveDependencies: false)
			let fileNames = fixture.fileNames
			let moduleInfoDirectory = workDirectory.appendingPathComponent("ModuleInfo")
			var commands = [(name: String, arguments: [String])]()
			for module in GraphFuzzerModule.allCases where presentModules.contains(module) {
				let sourceDirectory = fixtureDirectory.appendingPathComponent(module.packageName).appendingPathComponent("Sources").appendingPathComponent(module.name)
				var contentByFileName = [String: String]()
				for index in modules.indices where modules[index] == module {
					contentByFileName[fileNames[index]] = fixture.swiftFileContent[index]
				}
				let paths = try contentByFileName.keys.sorted().map { fileName in
					try write(contentByFileName[fileName, default: ""], to: sourceDirectory.appendingPathComponent(fileName))
				}
				let inputsFile = inputsDirectory.appendingPathComponent("\(module.name).csv")
				_ = try write(paths.joined(separator: ","), to: inputsFile)
				var arguments = [
					"generate", inputsFile.path,
					"--combined-output", workDirectory.appendingPathComponent("Output").appendingPathComponent("\(module.name).swift").path,
					"--compiler-receives-input-paths-unchanged",
					"--module-info-output", moduleInfoDirectory.appendingPathComponent("\(module.name).safedi").path,
					"--module-name", module.name,
					"--dot-file-output", workDirectory.appendingPathComponent("Output").appendingPathComponent("\(module.name).dot").path,
				]
				if !fixture.modulesOmittingPackageName.contains(module) {
					arguments += ["--package-name", module.packageName]
				}
				let dependencies = dependencyLists[module] ?? []
				if !dependencies.isEmpty {
					let dependenciesFile = inputsDirectory.appendingPathComponent("\(module.name)-dependencies.csv")
					_ = try write(dependencies.map { moduleInfoDirectory.appendingPathComponent("\($0.name).safedi").path }.joined(separator: ","), to: dependenciesFile)
					arguments += ["--dependent-module-info-file-path", dependenciesFile.path]
				}
				commands.append(("generate \(module.name)", arguments))
			}
			return commands
		}

		/// Writes `content` to `file`, making its directory, and returns its path.
		private static func write(_ content: String, to file: URL) throws -> String {
			try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
			try content.write(to: file, atomically: true, encoding: .utf8)
			return file.path
		}
	}
}
