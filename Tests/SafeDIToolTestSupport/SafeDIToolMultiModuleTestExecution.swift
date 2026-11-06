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
@testable import SafeDIToolLibrary

/// A module of a multi-module test: its name, the package it belongs to, its Swift files, and the modules it
/// depends on. Its files are written to `<fixture root>/<packageName>/Sources/<name>/` (or under
/// `<fixture root>/checkouts/` for a checkout package), named as `executeSafeDIToolTest` names its fixtures,
/// and must declare their own `import <Dependency>` lines: a module sees nothing of another module's
/// declarations until it imports the module, as in any build. `$FIXTURE_ROOT` in a file's content is replaced
/// by the fixture root's path, so a configuration can name another package's directory.
struct ModuleFixture {
	/// - Parameters:
	///   - name: The module's name, unique across every package of the test, as Swift requires.
	///   - packageName: The name of the package the module belongs to, which every module of the package shares.
	///   - swiftFileContent: Each file's content, named after the `@Instantiable` type it declares, as
	///     `executeSafeDIToolTest` names its fixtures.
	///   - swiftFileContentByFilePath: Each file's content at the path it is given, relative to the module's
	///     source directory, for a file whose name matters, such as `SafeDIConfiguration.swift`.
	///   - dependencies: The names of the modules this one depends on directly, each given before it. Each flow
	///     derives from them what its build system derives: `.moduleInfo` reads exactly these modules' `.safedi`,
	///     as Bazel lists a target's direct `deps`, so a module two levels down whose types this module's own trees
	///     build must be listed, as a Bazel or Tuist user lists a module the module imports, while a module a seam or
	///     public mock of a listed module needs reaches it in that module's `.safedi`; `.swiftPackagePlugin` lists the transitive closure's files in the CSV, as
	///     SwiftPM's `sourceModuleRecursiveDependencies` does. The module's compile can import the transitive
	///     closure, as rules_swift propagates module visibility.
	///   - isCheckoutPackage: Whether the module's package is one SwiftPM fetched, laid out under
	///     `<fixture root>/checkouts/<packageName>/`. The plugin treats a module as third-party when the one
	///     path component above its package directory is `checkouts` (a checkout target nested deeper slips
	///     past that check, as the example builds showed) and leaves its files out of the CSV of a consumer in another
	///     package, so such a consumer reads its declarations only through a configuration's
	///     `additionalDirectoriesToInclude`; a consumer that is a module of the same checkout package reads them.
	///     The harness lays such a module out to match and applies the rule by this flag. Bazel knows no
	///     checkouts: `.moduleInfo` reads the module's `.safedi` as it does any dependency's.
	///   - activeCompilationConditions: The conditions the tool is given as `--active-compilation-conditions`:
	///     the `scan` and `generate` of `.swiftPackagePlugin`, and the `generate` of `.moduleInfo`.
	///   - buildSettingArguments: The build-setting arguments the `generate` of `.swiftPackagePlugin` is given
	///     in place of the literal, unexpanded pair the plugin writes, which SwiftPM's native build system hands
	///     the tool as written; pass `swiftBuildExpandedBuildSettingArguments` to model Swift Build.
	///     `.moduleInfo` passes neither, as Bazel passes neither.
	///   - verificationCompilationConditions: The conditions the compile defines, or `nil` to define
	///     `activeCompilationConditions`.
	///   - mockConditionalCompilation: The condition the module's `#SafeDIConfiguration` wraps its mocks in, when
	///     it names one other than `DEBUG`, which the compile always defines. The compile defines it so the mocks
	///     compile too, and each integration checks it against the configuration the tool found: `.moduleInfo`
	///     in the module's `.safedi`, `.swiftPackagePlugin` in what `scan` cached.
	///   - isReleaseConfiguration: Whether the module is built as a release build is, as Bazel's `opt` mode builds it:
	///     the tool is given `NDEBUG` among its conditions in place of `DEBUG`, and the compile defines neither `DEBUG`
	///     nor the mock condition, so mock-only content and generated mocks are not compiled.
	///   - deletesSwiftFilesAfterRunning: Whether the harness deletes the module's Swift files once the tool has run
	///     for it, as a sandboxed Bazel action hands the modules that depend on it its `.safedi` but not its files. The
	///     module's files then cannot be compiled, so a test that deletes them skips compile verification.
	///   - runsSafeDI: Whether the tool runs for the module at all. A module that does not run SafeDI – one a Bazel or
	///     Tuist project builds without SafeDI's rule or script – is still compiled, and the modules that depend on it
	///     can import it, but under `.moduleInfo` no `.safedi` of it exists, so they read none of its declarations.
	///     Under `.swiftPackagePlugin` the plugin reads every first-party module's files, so the module SafeDI does not
	///     read is a checkout package's (`isCheckoutPackage`), whose own run plans nothing.
	///   - compilerSettings: The language mode, upcoming features, and staging of the module's compile.
	init(
		name: String,
		packageName: String,
		swiftFileContent: [String] = [],
		swiftFileContentByFilePath: [String: String] = [:],
		dependencies: [String] = [],
		isCheckoutPackage: Bool = false,
		activeCompilationConditions: [String] = [],
		buildSettingArguments: [String]? = nil,
		verificationCompilationConditions: [String]? = nil,
		mockConditionalCompilation: String? = nil,
		deletesSwiftFilesAfterRunning: Bool = false,
		omitsModuleName: Bool = false,
		omitsPackageName: Bool = false,
		isReleaseConfiguration: Bool = false,
		runsSafeDI: Bool = true,
		compilerSettings: VerificationCompilerSettings = VerificationCompilerSettings(),
	) {
		self.name = name
		self.compilerSettings = compilerSettings
		self.runsSafeDI = runsSafeDI
		self.isReleaseConfiguration = isReleaseConfiguration
		self.omitsModuleName = omitsModuleName
		self.omitsPackageName = omitsPackageName
		self.packageName = packageName
		self.swiftFileContent = swiftFileContent
		self.swiftFileContentByFilePath = swiftFileContentByFilePath
		self.dependencies = dependencies
		self.isCheckoutPackage = isCheckoutPackage
		self.activeCompilationConditions = activeCompilationConditions
		self.buildSettingArguments = buildSettingArguments
		self.verificationCompilationConditions = verificationCompilationConditions
		self.mockConditionalCompilation = mockConditionalCompilation
		self.deletesSwiftFilesAfterRunning = deletesSwiftFilesAfterRunning
	}

	let name: String
	let packageName: String
	let swiftFileContent: [String]
	let swiftFileContentByFilePath: [String: String]
	let dependencies: [String]
	let isCheckoutPackage: Bool
	let activeCompilationConditions: [String]
	let buildSettingArguments: [String]?
	let verificationCompilationConditions: [String]?
	let mockConditionalCompilation: String?
	let deletesSwiftFilesAfterRunning: Bool
	/// Whether `.moduleInfo` runs the module's `generate` without `--module-name`, as the Xcode project plugin runs it
	/// for a target, so it writes no `.safedi`, which names its module: only a module no other module of the test
	/// depends on can omit its name.
	let omitsModuleName: Bool
	/// Whether the module has no package under `.moduleInfo`: its `generate` runs without `--package-name` and its compile
	/// passes no `-package-name`, as Bazel builds a library without `package_name` and Tuist a target without
	/// `SWIFT_PACKAGE_NAME`. `.swiftPackagePlugin` reads the package from the target graph and compiles the module in it,
	/// since SwiftPM gives every module a package.
	let omitsPackageName: Bool
	/// Whether the module is built as a release build is: see `init`.
	let isReleaseConfiguration: Bool
	/// Whether the tool runs for the module: see `init`.
	let runsSafeDI: Bool
	/// The language mode, upcoming features, and staging of the module's compile.
	let compilerSettings: VerificationCompilerSettings

	/// The conditions the tool is given: `activeCompilationConditions`, with `NDEBUG` in place of `DEBUG` in a release
	/// build.
	var toolCompilationConditions: [String] {
		isReleaseConfiguration
			? activeCompilationConditions.filter { $0 != "DEBUG" } + (activeCompilationConditions.contains("NDEBUG") ? [] : ["NDEBUG"])
			: activeCompilationConditions
	}

	/// The same module for `executeSafeDIToolQuery`, which names the module after its directory and reads its
	/// files from there.
	var queryTestModule: QueryTestModule {
		QueryTestModule(name, swiftFileContent, swiftFileContentByFilePath: swiftFileContentByFilePath)
	}
}

/// How a build system runs the tool over several modules, which decides what each module's `generate` reads
/// and how it spells the files it cites.
enum MultiModuleIntegration: CaseIterable {
	/// Bazel's invocation of `generate` (`bazel/safedi.bzl`): one run per module, with no `scan`, reading a CSV
	/// of the module's own files, writing one combined file and the module's `.safedi`, reading the `.safedi` of
	/// each module in its `dependencies` (Bazel's rule lists a target's direct `deps`; a Tuist user lists modules
	/// by name), naming the module and its package with `--module-name` and `--package-name`, and passing
	/// `--compiler-receives-input-paths-unchanged`. Tuist differs only by
	/// omitting that flag and passing `$SRCROOT`-relative paths. The harness names the combined file `<module name>.swift`, where
	/// Bazel names both outputs after the rule label and Tuist writes `SafeDIGenerated.swift`, and its CSV names
	/// each file by the absolute, unresolved path the harness created it under, where Bazel's entries are
	/// execroot-relative and Tuist's `$SRCROOT`-relative: that changes only the text of `#sourceLocation`
	/// directives, of diagnostics and of the paths the `.safedi` stores, never the tree or mock code. In
	/// combined mode `generate()` normalizes no path and `run()` respells paths only when printing, so a
	/// diagnostic cites the CSV's path and an alias's declaration is referenced by a `#sourceLocation`
	/// directive naming it.
	case moduleInfo
	/// The SwiftPM plugin's invocations (`SafeDIGenerateDependencyTree.swift`): `scan` while planning the build
	/// and, only when the manifest plans an output, `generate` with that manifest, as the plugin adds a build
	/// command only then. Each reads one CSV holding the module's own files and every transitive first-party
	/// dependency's files – another checkout package's are left out – each relative to the module's package directory
	/// when it lies inside it and spelled whole otherwise, with only the module's own files mock-scoped, the
	/// package directory reported with its symbolic links resolved, and no `.safedi` anywhere. Beside the CSV lies
	/// the target graph the plugin writes: the module and each module whose files the CSV lists, with its package
	/// (the fixture's package name, which stands in for SwiftPM's package identity), its files spelled as the CSV
	/// spells them, and the modules it depends on directly. The build system
	/// spells a file to the compiler as the reported package directory joined with the CSV's relative path
	/// (`FixturePaths.compilerPath(of:)`): an alias's declaration is referenced by a `#sourceLocation` directive
	/// naming that spelling, a found additional file outside the package is listed by its normalized path, and a
	/// diagnostic `generate()` throws cites the path the file was parsed under, the compiler's spelling
	/// normalized (`NormalizedFilePath`), which `run()` respells as the build system's before printing it.
	case swiftPackagePlugin

	/// The comment, after a space, that a generated call of `type`'s seam or public mock, which the module named
	/// `declaringModule` declares, carries under this integration.
	func seamCallComment(type: String, declaringModule: String) -> String {
		switch self {
		case .moduleInfo:
			" // If this line does not compile, compile the code SafeDI generates for module \(declaringModule) into \(declaringModule): under Bazel, add \(declaringModule)'s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."
		case .swiftPackagePlugin:
			" // If this line does not compile, add the SafeDI plugin to the target that declares \(type)."
		}
	}
}

/// Whether `executeSafeDIToolMultiModuleTest` compiles the modules, and what it does when one does not compile.
enum MultiModuleCompileVerification {
	/// Compiles the modules in order, stopping at the first failure, and records an `Issue` for a failure or a
	/// warning in generated code, as `executeSafeDIToolTest` does.
	case recordingIssues
	/// Compiles the modules in order, stopping at the first failure, and returns the outcome without recording an
	/// `Issue`, for a test that expects a module not to compile.
	case returningOutcomeOnly
	/// Does not compile.
	case skipped
}

/// What one module's run produced.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct ModuleTestOutput {
	/// Whether `generate` ran: always under `.moduleInfo`, and under `.swiftPackagePlugin` only when `scan`
	/// planned an output, as the plugin adds a build command only then.
	let generateRan: Bool
	/// The module's `.safedi`, which only `.moduleInfo` writes.
	let moduleInfoFile: ModuleInfoFile?
	/// The module `moduleInfoFile` describes.
	var moduleInfo: ModuleInfo? {
		moduleInfoFile?.module
	}

	let moduleInfoOutputPath: String?
	/// The manifest `scan` wrote, which only `.swiftPackagePlugin` runs.
	let scanManifest: SafeDIToolManifest?
	/// The module's fixture files, looked up by file name.
	let fixtures: FixturePaths
	/// The non-fatal diagnostics `generate` reported.
	let warnings: [SourceDiagnostic]
	/// The Swift files in the module's output directory, by name: under `.swiftPackagePlugin` the manifest's
	/// outputs, and under `.moduleInfo` the one combined file, `<module name>.swift`.
	let generatedFiles: [String: String]
	/// What `generate` read, when it ran: the module it generated code for, whose declarations under
	/// `.swiftPackagePlugin` include those of every module the CSV lists, and the dependent modules' `.safedi`.
	let generateOutput: Generate.Output?
	/// The DOT tree `generate` wrote (`--dot-file-output`), when the test asked for one under `.moduleInfo`.
	var dotTree: String?
}

/// What `executeSafeDIToolMultiModuleTest` produced: each module's output and, when the modules were compiled,
/// how that went.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct MultiModuleTestOutput {
	/// Each module's output, by module name.
	let modules: [String: ModuleTestOutput]
	/// The modules' names, in the order they were given and processed.
	let moduleNames: [String]
	/// How the modules compiled, or `nil` when they were not compiled: verification was skipped or disabled, or
	/// the build artifacts could not be found.
	let compilation: MultiModuleCompileOutcome?
	/// The temporary directory everything the test wrote lies under.
	let fixtureRoot: URL
}

/// An error thrown by `executeSafeDIToolMultiModuleTest` when a module's `generate` fails. Carries the fixture
/// paths of every module the tool ran for, the failing one included, so diagnostics that cite those paths can
/// be asserted in full, and the output of every module processed before the failing one.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct SafeDIToolMultiModuleTestError: Error, CustomStringConvertible {
	let underlyingError: any Error
	/// The module whose `generate` failed.
	let moduleName: String
	/// The fixtures of every module the tool ran for, by module name.
	let fixtures: [String: FixturePaths]
	/// The output of each module processed before the failing one, by module name: the harness stops at the
	/// first module whose `generate` fails, so the modules after it have none.
	let outputs: [String: ModuleTestOutput]

	var description: String {
		"\(underlyingError)"
	}
}

/// Asserts that `block` throws because `generate` failed for the module named `expectedModuleName`, with an error
/// whose description – the compiler-formatted diagnostics for a `SourceLocatedError` – exactly matches
/// `expectedDiagnostics`, which is given every module's fixture files so it can cite their paths, and hands the
/// outputs of the modules processed before the failing one to `inspectingOutputs`.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func assertThrowsMultiModuleError(
	inModule expectedModuleName: String,
	diagnostics expectedDiagnostics: (_ fixtures: [String: FixturePaths]) -> String,
	inspectingOutputs: (_ outputs: [String: ModuleTestOutput]) -> Void = { _ in },
	sourceLocation: SourceLocation = #_sourceLocation,
	block: () async throws -> some Sendable,
) async {
	do {
		_ = try await block()
		Issue.record("Did not throw error!", sourceLocation: sourceLocation)
	} catch let error as SafeDIToolMultiModuleTestError {
		#expect(error.moduleName == expectedModuleName, sourceLocation: sourceLocation)
		#expect(expectedDiagnostics(error.fixtures) == "\(error.underlyingError)", sourceLocation: sourceLocation)
		inspectingOutputs(error.outputs)
	} catch {
		Issue.record("Threw an error that does not carry fixture paths: \(error)", sourceLocation: sourceLocation)
	}
}

/// An error in how a test's modules are declared, found before anything is written.
struct MultiModuleFixtureError: Error, CustomStringConvertible {
	let description: String
}

/// Writes each of `modules` into a package directory of its own under one temporary root, runs the tool for
/// each in the order given as `integration` would, and then compiles each module against the modules it depends
/// on with `verifyModulesCompile`, in order, stopping at the first failure, every module whether or not it
/// generated anything.
///
/// The tool finds files on disk, as a build does. Under `.swiftPackagePlugin`, each module's scan cache is
/// checked to read back exactly what `scan` wrote, as `executeSafeDIToolTest` checks it.
///
/// - Parameters:
///   - modules: The modules in dependency order: each names only modules before it as `dependencies`.
///   - writesTargetGraph: Whether `.swiftPackagePlugin` writes the target graph beside each module's CSV, as the
///     SafeDIGenerator plugin does for a Swift package. Without it, as for the Xcode project plugin, the tool knows
///     no module.
///   - scansDuringGenerate: Whether `.swiftPackagePlugin` runs no `scan` and has `generate --output-directory` scan
///     for itself, naming the module's own files with `--mock-scoped-files`, as a plugin that cannot scan while it
///     plans the build does. The CSV then names every file by its absolute path.
///   - moduleInfoOverrides: Under `.moduleInfo`, the `.safedi` file to give the other modules for each named
///     module instead of running the tool for it – one an earlier run wrote, so a dependent reads module info written
///     against other declarations than this run's. The module's files are still written, so a consumer's CSV can list
///     them. Such a run is not compiled.
///   - writesDOTTrees: Whether `.moduleInfo` has `generate` write each module's DOT tree (`--dot-file-output`), which
///     `ModuleTestOutput.dotTree` holds.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func executeSafeDIToolMultiModuleTest(
	modules: [ModuleFixture],
	integration: MultiModuleIntegration,
	compileVerification: MultiModuleCompileVerification = .recordingIssues,
	writesTargetGraph: Bool = true,
	scansDuringGenerate: Bool = false,
	moduleInfoOverrides: [String: String] = [:],
	writesDOTTrees: Bool = false,
	filesToDelete: inout [URL],
	sourceLocation: SourceLocation = #_sourceLocation,
) async throws -> MultiModuleTestOutput {
	let transitiveDependencies = try transitiveDependenciesByModuleName(of: modules)

	let fixtureRoot = (TestFixtureLocation.parentDirectory ?? FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
	filesToDelete.append(fixtureRoot)
	let moduleInfoDirectory = fixtureRoot.appendingPathComponent("ModuleInfo")

	// Every module's files are written before any module runs, since a module's CSV may list a dependency's.
	// A dependency's own directory is never worth naming in a consumer's `additionalDirectoriesToInclude`:
	// under the plugin flow the dependency's files are already inputs of the consumer's CSV, so including its
	// directory changes nothing, and under Bazel's invocation the consumer reads the dependency's `.safedi` as
	// well, so every `@Instantiable` the directory declares is found twice and rejected as a duplicate. The real
	// use is a checkout package's directory, whose files the plugin leaves out of the CSV.
	var writtenModules = [WrittenModule]()
	for module in modules {
		let packageDirectory = (module.isCheckoutPackage ? fixtureRoot.appendingPathComponent("checkouts") : fixtureRoot)
			.appendingPathComponent(module.packageName)
		let sourceDirectory = packageDirectory.appendingPathComponent("Sources").appendingPathComponent(module.name)
		try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
		func resolvingPlaceholders(in content: String) -> String {
			content.replacingOccurrences(of: "$FIXTURE_ROOT", with: fixtureRoot.path)
		}
		let contentNamedSwiftFiles = try createSwiftFixtureFiles(from: module.swiftFileContent.map(resolvingPlaceholders(in:)), in: sourceDirectory)
		let pathNamedSwiftFiles = try createSwiftFixtureFiles(
			atFilePaths: module.swiftFileContentByFilePath.mapValues(resolvingPlaceholders(in:)),
			in: sourceDirectory,
			alongside: contentNamedSwiftFiles,
		)
		writtenModules.append(WrittenModule(
			fixture: module,
			packageDirectory: packageDirectory,
			swiftFiles: contentNamedSwiftFiles + pathNamedSwiftFiles,
			fileNames: contentNamedSwiftFiles.map(\.lastPathComponent) + module.swiftFileContentByFilePath.keys.sorted(),
			transitiveDependencies: transitiveDependencies[module.name, default: []],
		))
	}
	let writtenModulesByName = Dictionary(uniqueKeysWithValues: writtenModules.map { ($0.fixture.name, $0) })

	var outputs = [String: ModuleTestOutput]()
	for module in writtenModules {
		let moduleName = module.fixture.name
		let swiftFileCSV = fixtureRoot.appendingPathComponent("Inputs").appendingPathComponent("\(moduleName).csv")
		let outputDirectory = fixtureRoot.appendingPathComponent("Output").appendingPathComponent(moduleName)
		for directory in [swiftFileCSV.deletingLastPathComponent(), outputDirectory] {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		let activeCompilationConditionArguments = module.fixture.toolCompilationConditions.isEmpty
			? []
			: ["--active-compilation-conditions"] + module.fixture.toolCompilationConditions

		// The module's files as the CSV spells them, and as the build system spells them to the compiler.
		let inputSwiftFilePaths: [String]
		let compilerSwiftFilePaths: [String]
		var generateArguments: [String]?
		let moduleInfoOutput: URL?
		var scanManifest: SafeDIToolManifest?
		guard module.fixture.runsSafeDI else {
			// The module is compiled, but nothing runs for it, and no `.safedi` of it exists.
			outputs[moduleName] = ModuleTestOutput(
				generateRan: false,
				moduleInfoFile: nil,
				moduleInfoOutputPath: nil,
				scanManifest: nil,
				fixtures: FixturePaths(fileNames: module.fileNames, paths: module.swiftFiles.map(\.path), compilerPaths: module.swiftFiles.map(\.path)),
				warnings: [],
				generatedFiles: [:],
				generateOutput: nil,
			)
			continue
		}
		switch integration {
		case .moduleInfo:
			inputSwiftFilePaths = module.swiftFiles.map(\.path)
			compilerSwiftFilePaths = inputSwiftFilePaths
			try inputSwiftFilePaths.joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
			// Named after the module, so the tool, which reads dependent module info in path order, combines
			// the dependencies' declarations in module name order whatever order the test lists them in.
			try FileManager.default.createDirectory(at: moduleInfoDirectory, withIntermediateDirectories: true)
			let output = moduleInfoDirectory.appendingPathComponent("\(moduleName).safedi")
			moduleInfoOutput = module.fixture.omitsModuleName ? nil : output
			if let overridePath = moduleInfoOverrides[moduleName] {
				// The module's info comes from the earlier run: nothing runs for it.
				try FileManager.default.copyItem(atPath: overridePath, toPath: output.path)
				outputs[moduleName] = ModuleTestOutput(
					generateRan: false,
					moduleInfoFile: try ModuleInfoFile(moduleInfoData: Data(contentsOf: output)),
					moduleInfoOutputPath: output.path,
					scanManifest: nil,
					fixtures: FixturePaths(fileNames: module.fileNames, paths: inputSwiftFilePaths, compilerPaths: compilerSwiftFilePaths),
					warnings: [],
					generatedFiles: [:],
					generateOutput: nil,
				)
				continue
			}
			var arguments: [String] = [
				swiftFileCSV.path,
				"--combined-output", outputDirectory.appendingPathComponent("\(moduleName).swift").path,
			]
			if writesDOTTrees {
				arguments += ["--dot-file-output", outputDirectory.appendingPathComponent("\(moduleName).dot").path]
			}
			arguments.append("--compiler-receives-input-paths-unchanged")
			if !module.fixture.omitsModuleName {
				arguments += ["--module-info-output", output.path, "--module-name", moduleName]
			}
			if !module.fixture.omitsPackageName {
				arguments += ["--package-name", module.fixture.packageName]
			}
			arguments += activeCompilationConditionArguments
			// A dependency that does not run SafeDI has no `.safedi` to read.
			let dependenciesRunningSafeDI = module.fixture.dependencies.filter { writtenModulesByName[$0]?.fixture.runsSafeDI != false }
			if !dependenciesRunningSafeDI.isEmpty {
				let dependentModuleInfoFileCSV = moduleInfoDirectory.appendingPathComponent("\(moduleName)-dependencies.csv")
				try dependenciesRunningSafeDI
					.map { moduleInfoDirectory.appendingPathComponent("\($0).safedi").path }
					.joined(separator: ",")
					.write(to: dependentModuleInfoFileCSV, atomically: true, encoding: .utf8)
				arguments += ["--dependent-module-info-file-path", dependentModuleInfoFileCSV.path]
			}
			generateArguments = arguments
		case .swiftPackagePlugin:
			// The package directory as SwiftPM reports it to the plugin: with its symbolic links resolved.
			let reportedPackageDirectory = try realPath(of: module.packageDirectory)
			let normalizedPackageDirectory = NormalizedFilePath(reportedPackageDirectory)
			// As the plugin's `writeInputSwiftFilesCSV` spells each file: relative to the package directory when it
			// lies inside it, and whole otherwise. A `generate` that scans for itself reads paths from its working
			// directory, so each is whole.
			func csvEntry(of file: URL) -> String {
				scansDuringGenerate
					? "\(reportedPackageDirectory)/\(NormalizedFilePath(file.path).path(relativeTo: normalizedPackageDirectory))"
					: NormalizedFilePath(file.path).path(relativeTo: normalizedPackageDirectory)
			}
			inputSwiftFilePaths = module.swiftFiles.map(csvEntry(of:))
			compilerSwiftFilePaths = scansDuringGenerate ? inputSwiftFilePaths : inputSwiftFilePaths.map { "\(reportedPackageDirectory)/\($0)" }
			// As the plugin's `sourceModuleRecursiveDependencies`: every transitive dependency not under `checkouts`,
			// and every one of the module's own package, which is under `checkouts` when that package is fetched.
			let firstPartyDependencies = module.transitiveDependencies
				.map { writtenModulesByName[$0]! }
				.filter { !$0.fixture.isCheckoutPackage || $0.packageDirectory.path == module.packageDirectory.path }
			let csvEntries = inputSwiftFilePaths + firstPartyDependencies.flatMap { $0.swiftFiles.map(csvEntry(of:)) }
			try csvEntries.joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
			if writesTargetGraph {
				// As the plugin's `writeTargetGraph`, beside the CSV.
				let encoder = JSONEncoder()
				encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
				try encoder.encode(PluginTargetGraph(
					target: module.graphTarget(spellingFilesAs: csvEntry(of:)),
					dependencyTargets: firstPartyDependencies.map { $0.graphTarget(spellingFilesAs: csvEntry(of:)) }.sorted { $0.moduleName < $1.moduleName },
				)).write(to: URL(fileURLWithPath: swiftFileCSV.path + PluginTargetGraph.fileNameSuffix))
			}
			if scansDuringGenerate {
				moduleInfoOutput = nil
				generateArguments = [swiftFileCSV.path, "--output-directory", outputDirectory.path, "--mock-scoped-files"]
					+ compilerSwiftFilePaths
					+ activeCompilationConditionArguments
				break
			}
			let manifestFile = fixtureRoot.appendingPathComponent("Manifests").appendingPathComponent("\(moduleName).json")
			try FileManager.default.createDirectory(at: manifestFile.deletingLastPathComponent(), withIntermediateDirectories: true)
			// The scan cache lies under `fixtureRoot`, which is already registered for deletion.
			var filesUnderFixtureRoot = [URL]()
			let scannedModuleInfo = try await performScanCheckingCache(
				inputSourcesFile: swiftFileCSV.path,
				projectFilePaths: ProjectFilePaths(projectRoot: reportedPackageDirectory),
				outputDirectory: outputDirectory.path,
				manifestFile: manifestFile.path,
				mockScopedFiles: compilerSwiftFilePaths,
				activeCompilationConditions: Set(module.fixture.toolCompilationConditions),
				filesToDelete: &filesUnderFixtureRoot,
				sourceLocation: sourceLocation,
			)
			let manifest = try JSONDecoder().decode(SafeDIToolManifest.self, from: Data(contentsOf: manifestFile))
			scanManifest = manifest
			moduleInfoOutput = nil
			// The module's configuration, chosen as `generate` chooses it from the cache: the first by path among
			// those in the manifest's configuration files.
			let configuredCondition = (scannedModuleInfo.moduleInfo.configurations + scannedModuleInfo.conditionSensitiveFileScans.flatMap(\.fileScan.configurations))
				.filter { configuration in configuration.sourceFilePath.map(manifest.configurationFilePaths.contains) == true }
				.sorted { ($0.sourceFilePath ?? "") < ($1.sourceFilePath ?? "") }
				.first?
				.mockConditionalCompilation
			expectMockConditionAgrees(configured: configuredCondition, fixture: module.fixture, sourceLocation: sourceLocation)
			// The plugin adds a build command only when the manifest plans an output.
			let plansAnOutput = !manifest.dependencyTreeGeneration.isEmpty || !manifest.mockGeneration.isEmpty || manifest.mockConfigurationOutputFilePath != nil
			if plansAnOutput {
				// The manifest already records the conditions; the plugin repeats them so the command changes when
				// they change, and adds the build-setting arguments for the build system to expand.
				generateArguments = [swiftFileCSV.path, "--swift-manifest", manifestFile.path]
					+ activeCompilationConditionArguments
					+ (module.fixture.buildSettingArguments ?? buildSettingCompilationConditionArguments)
			} else {
				generateArguments = nil
			}
		}
		let fixtures = FixturePaths(fileNames: module.fileNames, paths: inputSwiftFilePaths, compilerPaths: compilerSwiftFilePaths)

		var generateOutput: Generate.Output?
		if let generateArguments {
			let tool = try Generate.parse(generateArguments)
			// Call `generate()` rather than `run()`: `run()` prints located errors in compiler format and
			// rethrows them as an `ExitCode`, which would hide the error from the assertion helpers.
			do {
				generateOutput = try await tool.generate()
			} catch {
				var fixturesByModuleName = outputs.mapValues(\.fixtures)
				fixturesByModuleName[moduleName] = fixtures
				throw SafeDIToolMultiModuleTestError(underlyingError: error, moduleName: moduleName, fixtures: fixturesByModuleName, outputs: outputs)
			}
		}

		let moduleInfoFile = try moduleInfoOutput.map { try ModuleInfoFile(moduleInfoData: Data(contentsOf: $0)) }
		if let moduleInfo = moduleInfoFile?.module {
			expectMockConditionAgrees(configured: moduleInfo.configurations.first?.mockConditionalCompilation, fixture: module.fixture, sourceLocation: sourceLocation)
		}
		if module.fixture.deletesSwiftFilesAfterRunning {
			for swiftFile in module.swiftFiles {
				try FileManager.default.removeItem(at: swiftFile)
			}
		}
		outputs[moduleName] = ModuleTestOutput(
			generateRan: generateArguments != nil,
			moduleInfoFile: moduleInfoFile,
			moduleInfoOutputPath: moduleInfoOutput?.path,
			scanManifest: scanManifest,
			fixtures: fixtures,
			warnings: generateOutput?.warnings ?? [],
			generatedFiles: try generatedSwiftFiles(in: outputDirectory),
			generateOutput: generateOutput,
			dotTree: writesDOTTrees ? try String(contentsOf: outputDirectory.appendingPathComponent("\(moduleName).dot"), encoding: .utf8) : nil,
		)
	}

	let compilation: MultiModuleCompileOutcome? = switch compileVerification {
	case .recordingIssues, .returningOutcomeOnly:
		// A run given another run's module info is not compiled: it has no code for that module.
		moduleInfoOverrides.isEmpty ? try verifyModulesCompile(
			writtenModules.map { module in
				ModuleCompileSources(
					moduleName: module.fixture.name,
					packageName: integration == .moduleInfo && module.fixture.omitsPackageName ? nil : module.fixture.packageName,
					dependencyModuleNames: module.transitiveDependencies,
					inputSwiftFiles: module.swiftFiles,
					generatedFiles: outputs[module.fixture.name]!.generatedFiles,
					activeCompilationConditions: module.fixture.verificationCompilationConditions ?? module.fixture.toolCompilationConditions,
					mockConditionalCompilation: module.fixture.mockConditionalCompilation,
					definesDebug: !module.fixture.isReleaseConfiguration,
					compilerSettings: module.fixture.compilerSettings,
				)
			},
			recordsIssues: compileVerification == .recordingIssues,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		) : nil
	case .skipped:
		nil
	}

	return MultiModuleTestOutput(
		modules: outputs,
		moduleNames: modules.map(\.name),
		compilation: compilation,
		fixtureRoot: fixtureRoot,
	)
}

/// The literal build-setting arguments the SwiftPM plugin adds to its `generate` command, which SwiftPM's native
/// build system hands the tool as written and Swift Build expands.
let buildSettingCompilationConditionArguments = [
	"--build-setting-active-compilation-conditions=[${SWIFT_ACTIVE_COMPILATION_CONDITIONS}]",
	"--build-setting-other-swift-flags=[${OTHER_SWIFT_FLAGS}]",
]

/// The same pair as Swift Build expands it for a debug build of a package, as captured from `swift build
/// --build-system swiftbuild`: a leading space inside each pair of brackets, `DEBUG` twice, `-DXcode` among the
/// flags, which the tool reads as the condition `Xcode`, and a `-plugin-path` whose separate path argument is
/// not a condition. The path stands in for the toolchain's. The conditions the pair reports replace those
/// `scan` was given.
let swiftBuildExpandedBuildSettingArguments = [
	"--build-setting-active-compilation-conditions=[ SWIFT_PACKAGE DEBUG SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE DEBUG]",
	"--build-setting-other-swift-flags=[ -DXcode -warnings-as-errors -plugin-path /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing]",
]

/// Expects the condition the tool's configuration wraps mocks in to be the one the fixture names, since the
/// compile defines the fixture's. Both `nil` and `DEBUG` mean the condition the compile always defines.
private func expectMockConditionAgrees(configured configuredCondition: String?, fixture: ModuleFixture, sourceLocation: SourceLocation) {
	#expect(
		Set([configuredCondition].compactMap(\.self)).subtracting(["DEBUG"]) == Set([fixture.mockConditionalCompilation].compactMap(\.self)).subtracting(["DEBUG"]),
		"Module \(fixture.name)'s configuration wraps mocks in \(configuredCondition ?? "no condition"), but its fixture names \(fixture.mockConditionalCompilation ?? "none").",
		sourceLocation: sourceLocation,
	)
}

/// A module's fixture files as written, and what the harness computed for it.
private struct WrittenModule {
	let fixture: ModuleFixture
	/// `<fixture root>/<packageName>`, or `<fixture root>/checkouts/<packageName>` for a checkout package.
	let packageDirectory: URL
	let swiftFiles: [URL]
	let fileNames: [String]
	/// The names of every module this one depends on, directly or through another, in the order the modules
	/// were given.
	let transitiveDependencies: [String]

	/// The module as the plugin's target graph describes it: its files, each spelled by `csvEntry` as the CSV spells
	/// it, sorted, and the modules it depends on directly, sorted.
	func graphTarget(spellingFilesAs csvEntry: (URL) -> String) -> PluginTargetGraph.Target {
		PluginTargetGraph.Target(
			moduleName: fixture.name,
			packageID: fixture.packageName,
			sourceFilePaths: swiftFiles.map(csvEntry).sorted(),
			dependencyModuleNames: fixture.dependencies.sorted(),
		)
	}
}

/// The transitive dependencies of each of `modules`, by module name, each in the order the modules were given.
/// Throws when a module's name repeats, or a dependency does not name a module given before it or names one that omits
/// its module name.
private func transitiveDependenciesByModuleName(of modules: [ModuleFixture]) throws -> [String: [String]] {
	let moduleNames = modules.map(\.name)
	var transitiveDependencies = [String: [String]]()
	for module in modules {
		guard transitiveDependencies[module.name] == nil else {
			throw MultiModuleFixtureError(description: "Module \(module.name) is declared twice.")
		}
		var dependencies = Set<String>()
		for dependency in module.dependencies {
			guard let dependencyDependencies = transitiveDependencies[dependency] else {
				throw MultiModuleFixtureError(description: "Module \(module.name) depends on \(dependency), which must be listed before it.")
			}
			guard modules.first(where: { $0.name == dependency })?.omitsModuleName != true else {
				throw MultiModuleFixtureError(description: "Module \(module.name) depends on \(dependency), which omits its module name and so writes no module info.")
			}
			dependencies.insert(dependency)
			dependencies.formUnion(dependencyDependencies)
		}
		transitiveDependencies[module.name] = moduleNames.filter(dependencies.contains)
	}
	return transitiveDependencies
}

/// The `.swift` files in `outputDirectory`, by name.
private func generatedSwiftFiles(in outputDirectory: URL) throws -> [String: String] {
	var generatedFiles = [String: String]()
	for fileName in try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path) where fileName.hasSuffix(".swift") {
		generatedFiles[fileName] = try String(contentsOf: outputDirectory.appendingPathComponent(fileName), encoding: .utf8)
	}
	return generatedFiles
}
