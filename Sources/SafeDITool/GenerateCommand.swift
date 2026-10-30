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

import ArgumentParser
import Foundation
import SafeDICore

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct Generate: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Generate SafeDI dependency tree and mock code.",
	)

	// MARK: Arguments

	@Argument(help: "A path to a CSV file containing paths of Swift files to parse.") var swiftSourcesFilePath: String?

	@Option(parsing: .upToNextOption, help: "Directories containing Swift files to include, relative to the executing directory.") var include: [String] = []

	@Option(parsing: .upToNextOption, help: "The names of modules to import in the generated dependency tree. This list is in addition to the import statements found in files that declare @Instantiable types.") var additionalImportedModules: [String] = []

	@Option(help: "The desired output location of a file a SafeDI representation of this module. Only include this option when running on a project’s non-root module. Must have a `.safedi` suffix.") var moduleInfoOutput: String?

	@Option(help: "A path to a CSV file containing paths of SafeDI representations of other modules to parse.") var dependentModuleInfoFilePath: String?

	@Option(help: "A path to a JSON manifest file describing the desired Swift output files. The manifest maps input file paths to output file paths. See SafeDIToolManifest for the expected format.") var swiftManifest: String?

	@Option(help: "The directory where generated output files will be written. When provided without --swift-manifest, the tool scans for roots and mocks, generates a manifest internally, and writes all output files.") var outputDirectory: String?

	@Option(parsing: .upToNextOption, help: "Swift file paths scoped to the current target for mock generation. Only used when --output-directory is provided without --swift-manifest.") var mockScopedFiles: [String] = []

	@Option(parsing: .upToNextOption, help: "The compilation conditions that are active for this build, matching the compiler's -D flags, in addition to any recorded in the manifest by `scan`, unless the build-setting options arrive expanded. SafeDI declarations in `#if` blocks are scanned only when the block's condition evaluates to true, and the generated code asserts each such evaluation at compile time.") var activeCompilationConditions: [String] = []

	@Option(name: .customLong(BuildSettingCompilationConditions.activeCompilationConditionsOptionName), help: "The target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS` build setting wrapped in square brackets, written as the literal `[${SWIFT_ACTIVE_COMPILATION_CONDITIONS}]` for the build system to expand when it runs the command. When both build-setting options arrive expanded, their conditions replace those from `--active-compilation-conditions` and the manifest. When either arrives unexpanded, as SwiftPM's native build system passes them, both are ignored.") var buildSettingActiveCompilationConditions: String?

	@Option(name: .customLong(BuildSettingCompilationConditions.otherSwiftFlagsOptionName), help: "The target's `OTHER_SWIFT_FLAGS` build setting wrapped in square brackets, written as the literal `[${OTHER_SWIFT_FLAGS}]`. Its `-D` flags are active conditions. Used only together with `--build-setting-active-compilation-conditions`.") var buildSettingOtherSwiftFlags: String?

	@Option(help: "When set, SafeDITool concatenates every generated Swift file (dependency trees + mocks + mock configuration) into this one path — one header, bodies joined in source-file order, deterministic for stable inputs. Intended for build systems that need rule outputs statically declared at analysis time (Bazel, Buck2). Requires 'swift-sources-file-path' or '--include'. Cannot be combined with '--output-directory' or '--swift-manifest' — those are per-file emission modes. May be combined with '--module-info-output'. The combined file is always rewritten on every run, even when content would be unchanged.") var combinedOutput: String?

	@Option(help: "The desired output location of the DOT file expressing the Swift dependency injection tree. Only include this option when running on a project’s root module.") var dotFileOutput: String?

	@Option(help: "The name of the module this run generates code for: the module that compiles the files the input CSV and '--include' name. Each of those files' declarations, and the '--module-info-output' file, record it, so a module that reads the file knows which module declares each type. Files reached through a #SafeDIConfiguration's additionalDirectoriesToInclude belong to another module. The '--module-info-output' file also records, as the modules this one depends on, the module each '--dependent-module-info-file-path' file records. Without this option, '--package-name', and dependent module info that names a module, a run with '--swift-manifest' or '--output-directory' reads the module of each file from the target graph the SafeDIGenerator plugin writes beside its input CSV.") var moduleName: String?

	@Option(help: "The package of the module this run generates code for, as the compiler's '-package-name' names it, recorded as '--module-name' is. Omit it when the compiler receives no '-package-name'.") var packageName: String?

	@Flag(help: "States that the compiler is handed every input Swift file, including the files behind dependent module info, at exactly the path this tool is handed. Generated code then wraps each `@Received(fulfilledByDependencyNamed:ofType:)` assignment in a `#sourceLocation` directive naming that path, so the compiler reports a type mismatch at the declaration. Without this flag, and without a build tool plugin’s manifest, the assignment names the declaration in a comment instead, because the compiler warns at a directive whose path differs from the one it was handed.") var compilerReceivesInputPathsUnchanged = false

	// MARK: Internal

	func run() async throws {
		let buildLog = BuildLog()
		do {
			let warnings = try await generate(buildLog: buildLog).warnings
			if !warnings.isEmpty {
				FileHandle.standardError.write(Data("\(buildLog.formatted(warnings))\n".utf8))
			}
		} catch let error as any SourceLocatedError {
			// Print located errors ourselves. ArgumentParser would print `Error: ` ahead of the first line,
			// which stops Xcode and SwiftPM from recognizing the `<path>:<line>:<column>: error:` format.
			// Throwing an `ExitCode` makes ArgumentParser exit non-zero without printing anything further.
			FileHandle.standardError.write(Data("\(buildLog.formatted(error.sourceDiagnostics))\n".utf8))
			throw ExitCode.failure
		}
	}

	/// How `run()` prints diagnostics, which `generate` tells it as soon as it knows how the project spells its files.
	final class BuildLog {
		/// `diagnostics` formatted for the build log, each file named as the build system spells it, so an IDE maps
		/// the diagnostic to the file it has open and a reader finds it wherever the log is read. Build systems hand
		/// the tool paths relative to its working directory, so a relative path is made absolute against it first.
		func formatted(_ diagnostics: [SourceDiagnostic]) -> String {
			let workingDirectory = FileManager.default.currentDirectoryPath
			return diagnostics
				.map { diagnostic in
					diagnostic.respellingFilePath { [projectFilePaths] filePath in
						let absolutePath = NormalizedFilePath(filePath, relativeTo: workingDirectory)
						return projectFilePaths.map { $0.buildSystemPath(of: $0.projectFilePath(of: absolutePath)) } ?? absolutePath.path
					}.formatted
				}
				.joined(separator: "\n")
		}

		/// How the project `generate` runs for spells its files, or `nil` before `generate` knows or without a project root.
		fileprivate(set) var projectFilePaths: ProjectFilePaths?
	}

	/// What a run of `generate` read and reported.
	struct Output {
		/// Warnings about the module, which do not stop generation. `run()` prints them.
		let warnings: [SourceDiagnostic]
		/// The module this run generated code for, with the module that declares each of its declarations.
		let module: ModuleInfo
		/// The dependent modules' info, in the order this run combined their declarations.
		let dependentModules: [ModuleInfo]
	}

	/// Parses, validates, and writes the configured outputs.
	/// Throws `SourceLocatedError`s as-is so tests can inspect their diagnostics; `run()` formats them for the build log.
	/// - Parameter buildLog: Learns how the project spells its files, which decides how `run()` prints diagnostics.
	/// - Returns: Warnings about the module, which do not stop generation, and the modules this run read.
	@discardableResult
	func generate(buildLog: BuildLog = BuildLog()) async throws -> Output {
		if swiftSourcesFilePath == nil, include.isEmpty {
			throw ValidationError("Must provide 'swift-sources-file-path' or '--include'.")
		}

		// --combined-output is a single-file emission mode. The other
		// emission flags (--output-directory, --swift-manifest) are
		// per-file modes, and the manifest-per-file-paths aren't
		// needed (or meaningful) when the whole output is one file.
		if combinedOutput != nil, outputDirectory != nil || swiftManifest != nil {
			throw ValidationError("--combined-output is mutually exclusive with --output-directory and --swift-manifest. Use --combined-output alone for a single output file, or one of the others for per-file outputs.")
		}

		// The conditions the compiler receives, when the build system expanded them into this command's
		// arguments. They replace rather than add to the conditions supplied on the command line and
		// through the manifest, which a build tool plugin collects before the build and which can name
		// conditions the compiler does not define: Xcode hands plugins a package's debug-configuration
		// defines in Release too.
		let buildSettingConditions = try BuildSettingCompilationConditions.conditions(
			activeCompilationConditions: buildSettingActiveCompilationConditions,
			otherSwiftFlags: buildSettingOtherSwiftFlags,
		)

		// When --output-directory is provided without --swift-manifest, run an
		// inline scan to discover roots/mocks and build the manifest automatically.
		var resolvedSwiftManifest = swiftManifest
		// How the project spells its files, resolved once per run.
		var scannedProjectFilePaths: ProjectFilePaths?
		if resolvedSwiftManifest == nil, let outputDirectory {
			guard let swiftSourcesFilePath else {
				throw ValidationError("--output-directory requires 'swift-sources-file-path'.")
			}
			let manifestPath = (outputDirectory as NSString).appendingPathComponent("SafeDIManifest.json")
			let projectFilePaths = ProjectFilePaths(projectRoot: FileManager.default.currentDirectoryPath)
			scannedProjectFilePaths = projectFilePaths
			try await performScan(
				inputSourcesFile: swiftSourcesFilePath,
				projectFilePaths: projectFilePaths,
				outputDirectory: outputDirectory,
				manifestFile: manifestPath,
				mockScopedFiles: mockScopedFiles,
				activeCompilationConditions: buildSettingConditions ?? Set(activeCompilationConditions),
			)
			resolvedSwiftManifest = manifestPath
		}
		let manifest: SafeDIToolManifest? = try resolvedSwiftManifest.map { resolvedSwiftManifest in
			try JSONDecoder().decode(
				SafeDIToolManifest.self,
				from: Data(contentsOf: resolvedSwiftManifest.asFileURL),
			)
		}
		if let manifest {
			try Self.validateEachOutputIsWrittenOnce(by: manifest)
		}

		// A manifest without a project root, which only a hand-written manifest lacks, names files as written.
		let projectFilePaths = scannedProjectFilePaths ?? manifest?.projectRoot.map(ProjectFilePaths.init(projectRoot:))
		buildLog.projectFilePaths = projectFilePaths
		let inputFilePaths = try await findGenerateSwiftFiles()
		let suppliedCompilationConditions = buildSettingConditions
			?? Set(activeCompilationConditions).union(manifest?.activeCompilationConditions ?? [])

		let (dependentModuleInfo, parsed) = try await (
			loadSafeDIModuleInfo(),
			parsedModule(
				inputFilePaths: inputFilePaths,
				manifestPath: resolvedSwiftManifest,
				manifest: manifest,
				projectFilePaths: projectFilePaths,
				activeCompilationConditions: suppliedCompilationConditions,
			),
		)
		let initialModule = parsed.module.moduleInfo
		let initialModuleIsFromCache = parsed.isFromCache
		let sourceConfiguration = parsed.module.configuration
		let evaluator = parsed.module.conditionalCompilationEvaluator
		// Derived from the configuration rather than from how this run parsed, so a module loaded from
		// scan's cache warns too. Only `generate` warns, so a build that runs `scan` first warns once.
		var warnings = [sourceConfiguration?.placementWarning].compactMap(\.self)
			// Judged at the paths the module's additional files were found at: as scan resolved them when the module
			// comes from scan's cache, and as this run resolved them otherwise.
			+ (sourceConfiguration?.unreadableAdditionalDirectoryWarnings(for: parsed.module.additionalDirectories) ?? [])

		let resolvedAdditionalImportedModules: [String] = if let sourceConfiguration {
			additionalImportedModules + sourceConfiguration.additionalImportedModules
		} else {
			additionalImportedModules
		}

		// Paths are compared as scan compared them: inputs relative to the manifest's project root, or else to the
		// working directory. Without a project root, paths compare as the working directory spells them.
		let comparisonFilePaths = projectFilePaths ?? ProjectFilePaths(projectRoot: FileManager.default.currentDirectoryPath)

		// If the source configuration specifies additional directories to include,
		// find and parse swift files in those directories and merge with initial
		// results. Skipped when the initial module came from scan's cache —
		// scan already merged the additional directories into the cached
		// ModuleInfo, so re-parsing would be wasted work.
		let parsedModuleInfo: ModuleInfo
		if !initialModuleIsFromCache,
		   let sourceConfiguration,
		   !sourceConfiguration.additionalDirectoriesToInclude.isEmpty
		{
			// Each additional file is named as scan names it in the manifest, so the manifest lists the roots it
			// declares; without a project root, files are named as found.
			let additionalFileScans = try await parseAdditionalDirectoryFiles(
				Set(findSwiftFiles(inDirectories: sourceConfiguration.additionalDirectoriesToInclude).map(comparisonFilePaths.projectFilePath(of:))),
				excludingInputFilesAt: Set(inputFilePaths.map(comparisonFilePaths.projectFilePath(of:))),
				namedBy: projectFilePaths,
				conditionalCompilation: evaluator,
			)
			parsedModuleInfo = initialModule.including(ModuleInfo(additionalFileScans.map(\.fileScan)))
		} else {
			parsedModuleInfo = initialModule
		}
		// Each declaration with the module that declares its file, as the build system tells this run, if it does.
		let module = try moduleMembership(
			readsTargetGraph: resolvedSwiftManifest != nil,
			// The modules whose module info this run reads are the ones this module depends on directly, as the build
			// system lists them, named as each file records its module.
			dependencyModuleNames: Set(dependentModuleInfo.compactMap(\.moduleName)).sorted(),
			inputFilePaths: inputFilePaths,
			comparisonFilePaths: comparisonFilePaths,
		).map { parsedModuleInfo.declared(by: $0) } ?? parsedModuleInfo

		// Each module's instantiables are already ordered by `parseSwiftFiles`, so the
		// combined order depends only on the caller's dependent-module list.
		let normalizedInstantiables = normalizingInstantiableTypes(of: dependentModuleInfo.flatMap(\.instantiables) + module.instantiables)
		let additionalImportStatements = resolvedAdditionalImportedModules.map { ImportStatement(moduleName: $0) }
		let typeDescriptionToFulfillingInstantiableMap = try resolveSafeDIFulfilledTypes(instantiables: normalizedInstantiables)
		let generator = DependencyTreeGenerator(
			importStatements: dependentModuleInfo.flatMap(\.imports) + additionalImportStatements + module.imports,
			// A dependent module's mock-only declarations reach this module's mocks, so its mock imports do too.
			mockImportStatements: dependentModuleInfo.flatMap(\.mockImports) + additionalImportStatements + module.mockImports,
			typeDescriptionToFulfillingInstantiableMap: typeDescriptionToFulfillingInstantiableMap,
			aliasDeclarationReferences: AliasDeclarationReferences(
				declarationFilePaths: Set(normalizedInstantiables.flatMap { instantiable in
					instantiable.dependencies.compactMap { dependency in
						switch dependency.source {
						case .aliased:
							dependency.declarationLocation?.filePath
						case .forwarded, .instantiated, .received:
							nil
						}
					}
				}),
				compilerFilePaths: compilerFilePaths(manifest: manifest, projectFilePaths: projectFilePaths, inputFilePaths: inputFilePaths),
				// A plugin's paths relative to its project root, and any other integration's paths as it wrote them.
				commentFilePath: { [projectFilePaths] filePath in
					projectFilePaths.map { $0.manifestPath(of: $0.projectFilePath(of: filePath)) } ?? filePath
				},
			),
		)
		if let moduleInfoOutput {
			try module.moduleInfoData.write(toPath: moduleInfoOutput)
		}

		if manifest != nil || combinedOutput != nil {
			let filesWithUnexpectedNodes = dependentModuleInfo.compactMap(\.filesWithUnexpectedNodes).flatMap(\.self) + (module.filesWithUnexpectedNodes ?? [])
			if !filesWithUnexpectedNodes.isEmpty {
				// Write `#error(…)` instead of generated Swift so the
				// build surfaces the parse failure at the compile step.
				let errorContent = """
				// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
				// Any modifications made to this file will be overwritten on subsequent builds.
				// Please refrain from editing this file directly.

				#error(\"""
				SafeDI could not generate code because these files have syntax errors. Fix them and build again:
					\(filesWithUnexpectedNodes.joined(separator: "\n\t"))
				\""")
				"""
				if let combinedOutput {
					try errorContent.write(toPath: combinedOutput)
				} else if let manifest {
					// Every planned output, so that none is missing or keeps the code of an earlier build.
					for outputFilePath in (manifest.dependencyTreeGeneration + manifest.mockGeneration).map(\.outputFilePath) + [manifest.mockConfigurationOutputFilePath].compactMap(\.self) {
						try errorContent.write(toPath: outputFilePath)
					}
				}
			} else {
				let generatedRoots = try await generator.generatePerRootCodeTrees()
				await warnings.append(contentsOf: generator.generateWarnings())
				// Every generated file asserts how `#if` conditions were evaluated, so a build
				// whose compiler disagrees fails here with a message naming the condition.
				let compileTimeAssertions = ConditionalCompilationDecision.compileTimeAssertions(for: module.conditionalCompilationDecisions)
				let fileHeader = await generator.fileHeader + compileTimeAssertions
				// Generated mocks compile only where the mock condition is active, so they import
				// what the module's `#if` blocks select there.
				let mockFileHeader = await generator.mockFileHeader + compileTimeAssertions

				// Build a map from source file path → extension code(s).
				var sourceFileToExtensions = [String: [String]]()
				for root in generatedRoots {
					if let sourceFilePath = root.sourceFilePath, !root.code.isEmpty {
						sourceFileToExtensions[sourceFilePath, default: []].append(root.code)
					}
				}

				// The additional mocks that get a file. `scan` lists those of every configuration in every
				// clause, and this run generates the ones the configuration these conditions select lists.
				let listedAdditionalMocksToGenerate = manifest?.additionalMocksToGenerate ?? sourceConfiguration?.additionalMocksToGenerate ?? []
				var additionalMocksToGenerate = listedAdditionalMocksToGenerate

				// `scan` lists a file for every root and mock that any clause of any `#if` block declares, so
				// every declaration found here has its file unless its source changed since `scan` ran or a
				// hand-written manifest omits it. Validate before writing any output (manifest mode only).
				// Combined mode has no manifest to validate against.
				if let manifest {
					let manifestInputPaths = Set(manifest.dependencyTreeGeneration.map(\.inputFilePath))
					if let sourceFilePath = Set(module.instantiables.filter(\.isRoot).compactMap(\.sourceFilePath)).subtracting(manifestInputPaths).min() {
						throw ManifestError.rootNotInManifest(sourceFilePath: sourceFilePath)
					}
					if let mockScopedFilePaths = manifest.mockScopedFilePaths {
						// Paths are compared as scan wrote them, since this parse may name files as the CSV does.
						// Normalizing a path is far costlier than the comparisons, and this runs over every
						// mock-generating type in every module the target depends on, so a path is normalized
						// only when it could matter: normalizing never changes a file name, and naming a path
						// already written as scan writes it returns it unchanged.
						let manifestMockInputPaths = Set(manifest.mockGeneration.map(\.inputFilePath))
						// Only a module file sharing its name with a configuration's file, or with a mock-generating
						// declaration's file the manifest does not list by this parse's name, needs matching.
						let matchedSourceFilePaths = module.instantiables.filter(\.generateMock).compactMap(\.sourceFilePath).filter { !manifestMockInputPaths.contains($0) }
							+ module.configurations.compactMap(\.sourceFilePath)
						let matchedFileNames = Set(matchedSourceFilePaths.map { ($0 as NSString).lastPathComponent })
						let candidateMockScopedFilePaths = mockScopedFilePaths.filter { matchedFileNames.contains(($0 as NSString).lastPathComponent) }
						let candidateFileNames = Set(candidateMockScopedFilePaths.map { ($0 as NSString).lastPathComponent })
						// The manifest's name for a module file, matched by its comparable path, or for a manifest
						// without a project root, as written.
						let mockScopedManifestPath: (String) -> String?
						if let projectFilePaths {
							// The name found here is compared as written with configurationFilePaths and mockGeneration,
							// so a file listed under two spellings has no one name to compare.
							let mockScopedManifestPathsByFilePath = try Dictionary(
								candidateMockScopedFilePaths.map { (projectFilePaths.projectFilePath(of: $0), $0) },
								uniquingKeysWith: { firstSpelling, secondSpelling in
									guard firstSpelling == secondSpelling else {
										throw ManifestError.mockScopedFileListedUnderTwoSpellings(firstSpelling: min(firstSpelling, secondSpelling), secondSpelling: max(firstSpelling, secondSpelling))
									}
									return firstSpelling
								},
							)
							mockScopedManifestPath = { sourceFilePath in
								mockScopedManifestPathsByFilePath[projectFilePaths.projectFilePath(of: sourceFilePath)]
							}
						} else {
							let mockScopedFilePathSet = Set(candidateMockScopedFilePaths)
							mockScopedManifestPath = { sourceFilePath in
								mockScopedFilePathSet.contains(sourceFilePath) ? sourceFilePath : nil
							}
						}
						func mockScopedFilePath(resolving sourceFilePath: String) -> String? {
							guard candidateFileNames.contains((sourceFilePath as NSString).lastPathComponent) else { return nil }
							return mockScopedManifestPath(sourceFilePath)
						}
						for instantiable in module.instantiables where instantiable.generateMock {
							if let sourceFilePath = instantiable.sourceFilePath,
							   !manifestMockInputPaths.contains(sourceFilePath),
							   let mockScopedFilePath = mockScopedFilePath(resolving: sourceFilePath),
							   !manifestMockInputPaths.contains(mockScopedFilePath)
							{
								throw ManifestError.mockNotInManifest(typeName: instantiable.concreteInstantiable.asSource, sourceFilePath: mockScopedFilePath)
							}
						}
						let configurationFilePaths = Set(module.configurations.compactMap(\.sourceFilePath).compactMap(mockScopedFilePath(resolving:)))
						if let sourceFilePath = configurationFilePaths.subtracting(manifest.configurationFilePaths).min() {
							throw ManifestError.configurationNotInManifest(sourceFilePath: sourceFilePath)
						}
						// Only the mocks the selected configuration lists are generated; the files of the others
						// are written without code.
						let configuredAdditionalMocksToGenerate = sourceConfiguration?.additionalMocksToGenerate ?? []
						if let typeName = Set(configuredAdditionalMocksToGenerate).subtracting(manifest.additionalMocksToGenerate).min() {
							throw ManifestError.additionalMockNotInManifest(typeName: typeName)
						}
						additionalMocksToGenerate = configuredAdditionalMocksToGenerate
					}
				}
				// Only the configuration these conditions select is judged: `scan` lists the mocks of every
				// configuration, and those of the others are written without code. So is the mock of a listed
				// type that is declared only in clauses these conditions leave inactive.
				try sourceConfiguration?.validateAdditionalMocksToGenerate(
					fulfilledBy: typeDescriptionToFulfillingInstantiableMap,
					orDeclaredAmong: Set(dependentModuleInfo.flatMap(\.instantiableTypeNamesInAnyClause) + module.instantiableTypeNamesInAnyClause),
				)

				// Accumulate every emission as a `(destination, header, body)`
				// triple. `destination == nil` means the write is combined-
				// only (no standalone file). A manifest-driven run
				// populates destinations from the manifest; a
				// combined-output run leaves them all nil and lets the
				// concat step below do the emission under one header.
				var writes: [(destination: URL?, header: String, body: String)] = []

				// ---- Dependency tree ----
				let dependencyTreeDestinationsBySource: [String: URL]
				let dependencyTreeSourcesInOrder: [String]
				if let manifest {
					var destinations = [String: URL]()
					for entry in manifest.dependencyTreeGeneration {
						guard destinations[entry.inputFilePath] == nil else {
							throw ValidationError("Manifest contains duplicate dependencyTreeGeneration inputFilePath: \(entry.inputFilePath). List each input file once.")
						}
						destinations[entry.inputFilePath] = URL(fileURLWithPath: entry.outputFilePath)
					}
					dependencyTreeDestinationsBySource = destinations
					dependencyTreeSourcesInOrder = manifest.dependencyTreeGeneration.map(\.inputFilePath)
				} else {
					// Combined mode: enumerate current-module roots.
					// Sort by source file path so the concatenated
					// output is stable for stable inputs.
					dependencyTreeDestinationsBySource = [:]
					dependencyTreeSourcesInOrder = Set(
						module.instantiables.filter(\.isRoot).compactMap(\.sourceFilePath),
					).sorted()
				}
				for sourceFile in dependencyTreeSourcesInOrder {
					writes.append((
						destination: dependencyTreeDestinationsBySource[sourceFile],
						header: fileHeader,
						body: sourceFileToExtensions[sourceFile]?.sorted().joined(separator: "\n\n") ?? "",
					))
				}

				// ---- Mocks ----
				let currentModuleMockSourceFiles: [String]
				if let manifest {
					let additionalMockTypeNames = Set(manifest.additionalMocksToGenerate)
					currentModuleMockSourceFiles = manifest.mockGeneration
						.map(\.inputFilePath)
						.filter { !additionalMockTypeNames.contains($0) }
				} else {
					// Sorted for deterministic combined output.
					currentModuleMockSourceFiles = Set(
						module.instantiables.filter(\.generateMock).compactMap(\.sourceFilePath),
					).sorted()
				}
				let hasAnyMockGeneration = !currentModuleMockSourceFiles.isEmpty
					|| !listedAdditionalMocksToGenerate.isEmpty

				if hasAnyMockGeneration {
					// Use the config's mockConditionalCompilation if a config exists;
					// default to "DEBUG" when no config exists (per-type opt-in without config).
					let mockConditionalCompilation: String? = if let sourceConfiguration {
						sourceConfiguration.mockConditionalCompilation
					} else {
						"DEBUG"
					}
					let currentModuleSourceFilePaths: Set<String> = if let manifest {
						Set(manifest.mockGeneration.map(\.inputFilePath))
					} else {
						Set(currentModuleMockSourceFiles)
					}
					let mockResult = try await generator.generateMockCode(
						mockConditionalCompilation: mockConditionalCompilation,
						currentModuleSourceFilePaths: currentModuleSourceFilePaths,
						additionalMocksToGenerate: Set(additionalMocksToGenerate),
					)

					var sourceFileToMockExtensions = [String: [String]]()
					var typeNameToMockExtensions = [String: [String]]()
					for mock in mockResult.generatedRoots {
						if let sourceFilePath = mock.sourceFilePath {
							sourceFileToMockExtensions[sourceFilePath, default: []].append(mock.code)
						}
						typeNameToMockExtensions[mock.typeDescription.asSource, default: []].append(mock.code)
					}
					// A type declared here with `generateMock: true` and also listed in
					// `additionalMocksToGenerate` gets its mock only once, where its source file's
					// mock goes: emitting it twice fails to compile.
					let currentModuleMockSourceFileSet = Set(currentModuleMockSourceFiles)
					let typeNamesEmittedBySource = Set(
						mockResult.generatedRoots
							.filter { $0.sourceFilePath.map(currentModuleMockSourceFileSet.contains) ?? false }
							.map(\.typeDescription.asSource),
					)

					if let manifest {
						let additionalMockTypeNames = Set(manifest.additionalMocksToGenerate)
						for entry in manifest.mockGeneration {
							let extensions: [String]? = if additionalMockTypeNames.contains(entry.inputFilePath) {
								typeNamesEmittedBySource.contains(entry.inputFilePath) ? nil : typeNameToMockExtensions[entry.inputFilePath]
							} else {
								sourceFileToMockExtensions[entry.inputFilePath]
							}
							writes.append((
								destination: URL(fileURLWithPath: entry.outputFilePath),
								header: mockFileHeader,
								body: extensions?.sorted().joined(separator: "\n\n") ?? "",
							))
						}
						// Shared mock-configuration file. Declared even
						// when empty — the build system expects the
						// output to exist.
						if let mockConfigurationOutputFilePath = manifest.mockConfigurationOutputFilePath {
							writes.append((
								destination: URL(fileURLWithPath: mockConfigurationOutputFilePath),
								header: mockFileHeader,
								body: mockResult.mockConfigurationCode ?? "",
							))
						}
					} else {
						// Combined mode: per-source mocks sorted, then
						// per-type-name additional mocks sorted.
						for sourceFile in currentModuleMockSourceFiles {
							writes.append((
								destination: nil,
								header: mockFileHeader,
								body: sourceFileToMockExtensions[sourceFile]?.sorted().joined(separator: "\n\n") ?? "",
							))
						}
						// Skip types already emitted via the per-source loop.
						for typeName in Set(additionalMocksToGenerate).sorted()
							where !typeNamesEmittedBySource.contains(typeName)
						{
							writes.append((
								destination: nil,
								header: mockFileHeader,
								body: typeNameToMockExtensions[typeName]?.sorted().joined(separator: "\n\n") ?? "",
							))
						}
						if let mockConfigurationCode = mockResult.mockConfigurationCode,
						   !mockConfigurationCode.isEmpty
						{
							writes.append((destination: nil, header: mockFileHeader, body: mockConfigurationCode))
						}
					}
				}

				// ---- Emission ----
				if let combinedOutput {
					// Concat every non-empty body under a single header,
					// with one blank line between each body. An empty
					// module (no roots, no mocks) still writes the
					// header-only file so the build system's declared
					// output is populated. A file that holds mocks imports
					// what both the dependency tree and the mocks need.
					let combinedFileHeader = hasAnyMockGeneration
						? await generator.dependencyTreeAndMockFileHeader + compileTimeAssertions
						: fileHeader
					let bodies = writes.map(\.body).filter { !$0.isEmpty }
					let code = combinedFileHeader + bodies.joined(separator: "\n\n")
					// Always write — this flag is used to support Bazel and Buck2, which content-hash their inputs, so a stat-identical re-write costs them nothing. Moreover, these tools require that genrules write the outputs that are expected.
					try code.write(toPath: combinedOutput)
				} else {
					for write in writes {
						guard let destination = write.destination else { continue }
						let content = write.header + write.body
						let existingContent = try? String(contentsOf: destination, encoding: .utf8)
						if existingContent != content {
							try content.write(to: destination, atomically: true, encoding: .utf8)
						}
					}
				}
			}
		}

		if let dotFileOutput {
			let dotGraph = try await generator.generateDOTTree()
			try """
			graph SafeDI {
			    ranksep=2
			\(dotGraph)
			}
			""".write(toPath: dotFileOutput)
		}
		return Output(warnings: warnings, module: module, dependentModules: dependentModuleInfo)
	}

	// MARK: Private

	/// The manifest names the files `generate` writes, and `scan` chose them before the build ran: a file for
	/// each declaration that decides which files exist, in any clause of any `#if` block. `generate` writes a
	/// file without code for a declaration these conditions leave inactive, but it cannot write a file the
	/// manifest does not name, which happens when a source file gained such a declaration after `scan` ran,
	/// or when a hand-written manifest omits it. These errors say so instead of omitting code, and reject a
	/// hand-written manifest whose paths `generate` cannot match or whose outputs would overwrite one another.
	private enum ManifestError: Error, CustomStringConvertible {
		case rootNotInManifest(sourceFilePath: String)
		case mockNotInManifest(typeName: String, sourceFilePath: String)
		case configurationNotInManifest(sourceFilePath: String)
		case additionalMockNotInManifest(typeName: String)
		case mockScopedFileListedUnderTwoSpellings(firstSpelling: String, secondSpelling: String)
		case outputWrittenTwice(outputFilePath: String, firstOutput: ManifestOutput, secondOutput: ManifestOutput)
		case outputWrittenTwiceIgnoringLetterCase(firstOutputFilePath: String, secondOutputFilePath: String, firstOutput: ManifestOutput, secondOutput: ManifestOutput)

		var description: String {
			switch self {
			case let .rootNotInManifest(sourceFilePath):
				"Found @\(InstantiableVisitor.macroName)(isRoot: true) in '\(sourceFilePath)', but this file is not listed in the manifest’s dependencyTreeGeneration. \(Self.planningExplanation) A hand-written manifest must list the file, or the type must not be a root."
			case let .mockNotInManifest(typeName, sourceFilePath):
				"Found @\(InstantiableVisitor.macroName)(generateMock: true) on `\(typeName)` in '\(sourceFilePath)', but this file is not listed in the manifest’s mockGeneration. \(Self.planningExplanation) A hand-written manifest must list the file, or the type must not set `generateMock: true`."
			case let .configurationNotInManifest(sourceFilePath):
				"Found #\(SafeDIConfigurationVisitor.macroName) in '\(sourceFilePath)', but this file is not listed in the manifest’s configurationFilePaths. \(Self.planningExplanation) A hand-written manifest must list the file."
			case let .additionalMockNotInManifest(typeName):
				"The #\(SafeDIConfigurationVisitor.macroName) lists `\(typeName)` in additionalMocksToGenerate, but the manifest’s additionalMocksToGenerate does not. \(Self.planningExplanation) A hand-written manifest must list the type in additionalMocksToGenerate and mockGeneration."
			case let .mockScopedFileListedUnderTwoSpellings(firstSpelling, secondSpelling):
				"The manifest’s mockScopedFilePaths lists one file as both '\(firstSpelling)' and '\(secondSpelling)'. A hand-written manifest must list each file once, spelled as its configurationFilePaths and mockGeneration spell it."
			case let .outputWrittenTwice(outputFilePath, firstOutput, secondOutput):
				"The manifest’s \(firstOutput) and its \(secondOutput) both write '\(outputFilePath)'. A hand-written manifest must name a different file for each."
			case let .outputWrittenTwiceIgnoringLetterCase(firstOutputFilePath, secondOutputFilePath, firstOutput, secondOutput):
				"The manifest’s \(firstOutput) and its \(secondOutput) write '\(firstOutputFilePath)' and '\(secondOutputFilePath)', which name one file on a volume that ignores letter case or Unicode normalization, as macOS’s does by default. A hand-written manifest must name a different file for each, ignoring letter case."
			}
		}

		private static let planningExplanation = "SafeDI decides which files to generate before the build runs, listing every file that declares a root, a type that sets `generateMock: true`, or a #\(SafeDIConfigurationVisitor.macroName) in any clause of its `#if` blocks, so the file most likely changed after that decision; building again lists it."
	}

	/// A file a manifest tells `generate` to write.
	private enum ManifestOutput: Equatable, CustomStringConvertible {
		case dependencyTree(inputFilePath: String)
		case mock(inputFilePath: String)
		case mockConfiguration

		var description: String {
			switch self {
			case let .dependencyTree(inputFilePath):
				"dependencyTreeGeneration entry for '\(inputFilePath)'"
			case let .mock(inputFilePath):
				"mockGeneration entry for '\(inputFilePath)'"
			case .mockConfiguration:
				"mockConfigurationOutputFilePath"
			}
		}
	}

	/// Throws when two of `manifest`'s outputs name one file, since the one written last would replace the
	/// other's code: two spellings of one path, two paths through a symbolic link to one directory, or two paths that
	/// differ only in letter case, which a volume that ignores letter case holds as one file. Like `scan`'s output
	/// names, the last is rejected on every platform. `scan` gives each output its own file, so only a hand-written
	/// manifest can do this. An entry listed twice writes the same code twice, so it is not rejected here.
	private static func validateEachOutputIsWrittenOnce(by manifest: SafeDIToolManifest) throws {
		let outputs: [(output: ManifestOutput, outputFilePath: String)] = manifest.dependencyTreeGeneration.map { (.dependencyTree(inputFilePath: $0.inputFilePath), $0.outputFilePath) }
			+ manifest.mockGeneration.map { (.mock(inputFilePath: $0.inputFilePath), $0.outputFilePath) }
			+ (manifest.mockConfigurationOutputFilePath.map { [(.mockConfiguration, $0)] } ?? [])
		// Files are written at their paths relative to the working directory, so two spellings can name one file.
		var outputFilePaths = OutputFilePaths()
		var outputsByFilePath = [OutputFilePath: (output: ManifestOutput, outputFilePath: String, filePath: OutputFilePath)]()
		for (output, outputFilePath) in outputs {
			let filePath = outputFilePaths.outputFilePath(of: outputFilePath)
			if let firstOutput = outputsByFilePath[filePath] {
				guard firstOutput.output == output else {
					if firstOutput.filePath.path == filePath.path {
						throw ManifestError.outputWrittenTwice(outputFilePath: firstOutput.outputFilePath, firstOutput: firstOutput.output, secondOutput: output)
					} else {
						throw ManifestError.outputWrittenTwiceIgnoringLetterCase(
							firstOutputFilePath: firstOutput.outputFilePath,
							secondOutputFilePath: outputFilePath,
							firstOutput: firstOutput.output,
							secondOutput: output,
						)
					}
				}
			} else {
				outputsByFilePath[filePath] = (output, outputFilePath, filePath)
			}
		}
	}

	/// What the build system tells this run about modules, or `nil` when it tells nothing. The options, and the module
	/// names dependent module info records, when any is given, describe a build system that runs `generate` once per
	/// module. Otherwise a run with a manifest, which each of the SafeDIGenerator plugin's runs is, reads the target
	/// graph the plugin writes beside its input CSV, when there is one.
	/// - Parameters:
	///   - readsTargetGraph: Whether this run has a manifest, which it was given or scanned for itself.
	///   - dependencyModuleNames: The modules the dependent module info this run reads records, sorted.
	///   - inputFilePaths: The files the input CSV and `--include` name.
	///   - comparisonFilePaths: How this run compares paths.
	private func moduleMembership(
		readsTargetGraph: Bool,
		dependencyModuleNames: [String],
		inputFilePaths: Set<String>,
		comparisonFilePaths: ProjectFilePaths,
	) throws -> ModuleMembership? {
		if moduleName != nil || packageName != nil || !dependencyModuleNames.isEmpty {
			return ModuleMembership(
				moduleName: moduleName,
				packageName: packageName,
				dependencyModuleNames: dependencyModuleNames,
				inputFilePaths: Set(inputFilePaths.map(comparisonFilePaths.projectFilePath(of:))),
				filePathsSpelledBy: comparisonFilePaths,
			)
		} else if readsTargetGraph,
		          let swiftSourcesFilePath,
		          let targetGraph = try PluginTargetGraph(besideInputSourcesFileAt: swiftSourcesFilePath)
		{
			return ModuleMembership(targetGraph: targetGraph)
		} else {
			return nil
		}
	}

	private func findGenerateSwiftFiles() async throws -> Set<String> {
		try await findGenerateSwiftFiles(additionalDirectories: include)
	}

	private func findGenerateSwiftFiles(additionalDirectories: [String]) async throws -> Set<String> {
		var swiftFiles = try await Set(findSwiftFiles(inDirectories: additionalDirectories).map(\.path))
		if let swiftSourcesFilePath {
			let sourcesFromFile = try String(contentsOfFile: swiftSourcesFilePath, encoding: .utf8)
				.parsedPathListCSV()
			swiftFiles.formUnion(sourcesFromFile)
		}
		return swiftFiles
	}

	/// Loads the parsed `ModuleInfo` for this module. When scan ran earlier
	/// (plugin-setup subprocess of this same build, or this command's own
	/// scan for `--output-directory`), it persisted the parsed result
	/// alongside the manifest; reading that JSON is dramatically cheaper
	/// than re-parsing every Swift file through SwiftParser.
	///
	/// Returns `(module, isFromCache)`. On a cache hit the returned module
	/// already includes files discovered through
	/// `#SafeDIConfiguration.additionalDirectoriesToInclude`, so the caller
	/// should skip its additional-directory re-parse.
	///
	/// Cache is only consulted when `include` is empty — CLI callers who
	/// pass `--include` expect those directories scanned afresh, and scan
	/// doesn't see `--include`.
	///
	/// The cache is also bypassed when any file scan read reports
	/// modification times other than those scan recorded before reading it —
	/// e.g. a manual `generate` invocation after a source edit without
	/// rerunning `scan` would otherwise consume stale parse results and emit
	/// stale code. Plugin-driven builds rerun `scan` every build, so this
	/// check passes on the fast path, at one or two system calls per input.
	///
	/// A cache that cannot be read (cut short, corrupted, or written by a
	/// SafeDITool whose cached types are laid out differently; see
	/// `BinaryFile`) falls through to a fresh parse rather than aborting
	/// the build — the cache is an optimization sidecar, not a correctness
	/// requirement.
	///
	/// - Parameters:
	///   - inputFilePaths: The files `generate` was given, which with `include` empty are exactly the CSV's paths.
	///   - manifestPath: The path of the manifest `generate` runs with: the one passed with `--swift-manifest`, or,
	///     with `--output-directory`, the one the inline scan just wrote, whose cache spares parsing every file twice.
	///   - manifest: The manifest `generate` runs with, whose `configurationFilePaths` name the files that can
	///     declare this module's configuration. In multi-module builds the CSV includes every module's files, so
	///     several configurations may be present; without a manifest every input file belongs to this module.
	///   - projectFilePaths: How the manifest's project spells its files, or `nil` without a project root.
	///   - activeCompilationConditions: The conditions supplied on the command line and through the manifest.
	private func parsedModule(
		inputFilePaths: Set<String>,
		manifestPath: String?,
		manifest: SafeDIToolManifest?,
		projectFilePaths: ProjectFilePaths?,
		activeCompilationConditions: Set<String>,
	) async throws -> (module: ParsedModule, isFromCache: Bool) {
		// Only `scan` writes a cache, beside a manifest that records its project root.
		if include.isEmpty,
		   let manifestPath,
		   let manifest,
		   let projectFilePaths,
		   let cached = try await loadCachedModule(
		   	manifestPath: manifestPath,
		   	inputFilePaths: inputFilePaths,
		   	// The cached `ModuleInfo` names files as scan recorded them in the manifest.
		   	configurationFilePaths: Set(manifest.configurationFilePaths),
		   	projectFilePaths: projectFilePaths,
		   	activeCompilationConditions: activeCompilationConditions,
		   )
		{
			(cached, true)
		} else {
			try await (
				parseModule(
					filePaths: inputFilePaths,
					// A fresh parse names files as the CSV does, so the manifest's configuration
					// files are matched among the CSV's paths.
					configurationFilePaths: manifest.map { $0.configurationFilePaths(among: inputFilePaths, in: projectFilePaths) } ?? inputFilePaths,
					activeCompilationConditions: activeCompilationConditions,
				).module,
				false,
			)
		}
	}

	private func loadCachedModule(
		manifestPath: String,
		inputFilePaths: Set<String>,
		configurationFilePaths: Set<String>,
		projectFilePaths: ProjectFilePaths,
		activeCompilationConditions: Set<String>,
	) async throws -> ParsedModule? {
		let cacheURL = scannedModuleInfoURL(forManifestPath: manifestPath)

		// Treat a missing cache and one that cannot be read as cache misses, not hard errors — the
		// cache may be corrupted or have been written by a SafeDITool whose cached types are laid
		// out differently, such as one that recorded no modification times.
		guard let data = try? Data(contentsOf: cacheURL),
		      let cached = try? CachedScannedModuleInfo(scanCacheData: data)
		else { return nil }

		// Bypass the cache if the current CSV's file set differs from what
		// scan observed — a custom script could reuse a manifest path with a
		// changed CSV, in which case the cached ModuleInfo is for the wrong
		// input set. Plugin-driven builds always pair scan+generate with the
		// same CSV, so this check is effectively free on the fast path.
		// (An unreadable CSV never reaches here: `run` reads it first and
		// surfaces the missing-file error.)
		guard inputFilePaths == Set(cached.csvInputPaths) else {
			return nil
		}

		// Bypass the cache if new Swift files have been added to any of the
		// `additionalDirectoriesToInclude` directories since scan ran. The
		// modification-time check below only catches files scan already knew
		// about — it would miss a newly-added file whose path doesn't appear in
		// `cached.scannedInputs`.
		if !cached.additionalDirectories.isEmpty {
			let currentAdditionalFiles = await (try? findSwiftFiles(inDirectories: cached.additionalDirectories.map(\.path))) ?? []
			// Compared as scan compared the files it found with the inputs.
			guard Set(currentAdditionalFiles.map(projectFilePaths.projectFilePath(of:)))
				== Set(cached.additionalInputAbsolutePaths.map(projectFilePaths.projectFilePath(of:)))
			else {
				return nil
			}
		}

		// Bypass the cache if any file scan read reports different
		// modification times than scan recorded before reading it: edited,
		// touched, moved back in time, deleted, or a symbolic link pointed
		// elsewhere. We check every path scan read (including files reached
		// through `#SafeDIConfiguration.additionalDirectoriesToInclude`,
		// which don't appear in `findGenerateSwiftFiles()`'s output).
		guard cached.scannedInputs.allSatisfy({ scannedInput in
			FileModificationStamp(ofFileAtPath: scannedInput.path) == scannedInput.modificationStamp
		}) else {
			return nil
		}
		// Scan rejected more than one configuration in scope, so the first by path is the module's.
		let configuration = (cached.moduleInfo.configurations + cached.conditionSensitiveFileScans.flatMap(\.fileScan.configurations))
			.filter { configuration in
				guard let sourceFilePath = configuration.sourceFilePath else { return false }
				return configurationFilePaths.contains(sourceFilePath)
			}
			.sorted { ($0.sourceFilePath ?? "") < ($1.sourceFilePath ?? "") }
			.first
		let evaluator = conditionalCompilationEvaluator(
			activeCompilationConditions: activeCompilationConditions,
			configuration: configuration,
		)
		guard let fileScans = try await refreshed(cached.conditionSensitiveFileScans, from: cached, activeCompilationConditions: activeCompilationConditions, evaluator: evaluator),
		      let additionalFileScans = try await refreshed(cached.additionalConditionSensitiveFileScans, from: cached, activeCompilationConditions: activeCompilationConditions, evaluator: evaluator)
		else {
			return nil
		}
		return ParsedModule(
			moduleInfo: cached.moduleInfo.adding(fileScans).including(cached.additionalModuleInfo.adding(additionalFileScans)),
			configuration: configuration,
			conditionalCompilationEvaluator: evaluator,
			additionalDirectories: cached.additionalDirectories,
		)
	}

	/// What each file in `cachedFileScans` contributes under `activeCompilationConditions`, or `nil` when
	/// the module must be parsed afresh.
	///
	/// A file's scan records every bare condition whose value decided what the file contributed, so a
	/// file is walked again only when one of those has a different value now. The build settings
	/// usually report more conditions than the build tool plugin handed `scan`, such as `DEBUG` and
	/// `SWIFT_PACKAGE`, and only the files whose `#if` blocks consult them are walked again. Each is
	/// walked under the name scan gave it, so the locations it records read as scan's do.
	///
	/// A file that declares a configuration in any clause of its `#if` blocks could declare a different one
	/// now, or one where it declared none, which would change the evaluator every file is walked with, so
	/// then the whole module is parsed afresh.
	private func refreshed(
		_ cachedFileScans: [CachedFileScan],
		from cached: CachedScannedModuleInfo,
		activeCompilationConditions: Set<String>,
		evaluator: ConditionalCompilationEvaluator,
	) async throws -> [FileScan]? {
		let scanActiveCompilationConditions = Set(cached.activeCompilationConditions)
		func hasChangedValue(_ condition: String) -> Bool {
			scanActiveCompilationConditions.contains(condition) != activeCompilationConditions.contains(condition)
		}
		let staleFileScans = cachedFileScans.filter { cachedFileScan in
			cachedFileScan.fileScan.consultedCompilationConditions.contains(where: hasChangedValue)
		}
		guard !staleFileScans.contains(where: \.fileScan.outputFileDeclarations.declaresConfiguration) else {
			return nil
		}
		// Scan parsed every file under its absolute path, so the file is read from the name it is parsed under.
		let rescans = try await parseSwiftFiles(Set(staleFileScans.map(\.scannedPath)), conditionalCompilation: evaluator)
		let rescanByScannedPath = Dictionary(uniqueKeysWithValues: rescans.map { ($0.path, $0) })
		let staleScannedPaths = Set(staleFileScans.map(\.scannedPath))
		// A file that no longer mentions SafeDI is not walked, so it contributes nothing, as in a fresh parse.
		return cachedFileScans.compactMap { cachedFileScan in
			if staleScannedPaths.contains(cachedFileScan.scannedPath) {
				rescanByScannedPath[cachedFileScan.scannedPath]?.relocated(to: cachedFileScan.fileScan.path)
			} else if cachedFileScan.fileScan.importOnlyConsultedCompilationConditions.contains(where: hasChangedValue) {
				// Only the file's imports depend on a changed condition, and its import segments hold them.
				cachedFileScan.fileScan.withImports(evaluatedWith: evaluator)
			} else {
				cachedFileScan.fileScan
			}
		}
	}

	/// How the compiler spells the paths this tool was handed, or `nil` when this tool does not know.
	///
	/// A build tool plugin records its project root in the manifest and writes each input path relative to it,
	/// and the build system hands the compiler the absolute path it reported to the plugin. The plugin names the
	/// target's own files exactly as the build system reported them with `--mock-scoped-files` when `generate`
	/// scans for itself, and relative to the project root in the manifest otherwise. An integration that passes
	/// `--compiler-receives-input-paths-unchanged`, such as the Bazel rule, hands the compiler every input path
	/// as written. Any other integration may not: the Tuist plugin hands this tool paths relative to `$SRCROOT`,
	/// and Xcode hands the compiler absolute ones.
	///
	/// A build system that reports the project root through a symbolic link may hand the compiler either
	/// spelling: Xcode reports a package under `/tmp` to its plugin as `/tmp/…` and hands the compiler
	/// `/private/tmp/…`, and a plugin that runs `scan` while it plans the build records only the first. This tool
	/// then does not know how the compiler spells any path.
	private func compilerFilePaths(
		manifest: SafeDIToolManifest?,
		projectFilePaths: ProjectFilePaths?,
		inputFilePaths: Set<String>,
	) -> AliasDeclarationReferences.CompilerFilePaths? {
		if let manifest, let projectFilePaths {
			guard projectFilePaths.reportsResolvedProjectRoot else { return nil }
			let compilerFilePath = { (filePath: String) in projectFilePaths.buildSystemPath(of: projectFilePaths.projectFilePath(of: filePath)) }
			if swiftManifest == nil, !mockScopedFiles.isEmpty {
				return .init(filePath: compilerFilePath, moduleFilePaths: Set(mockScopedFiles), moduleFilePath: { $0 })
			} else {
				return .init(
					filePath: compilerFilePath,
					moduleFilePaths: manifest.mockScopedFilePaths.map(Set.init) ?? inputFilePaths,
					moduleFilePath: compilerFilePath,
				)
			}
		} else if compilerReceivesInputPathsUnchanged {
			return .init(filePath: { $0 }, moduleFilePaths: inputFilePaths, moduleFilePath: { $0 })
		} else {
			return nil
		}
	}

	/// The dependent modules' info files, each listed once, in path order. Their order is the order in which
	/// their declarations are combined, which decides which duplicate declaration is reported and the order of
	/// the files with errors that generated code lists. Path order is the order in which a module's own files
	/// are combined, and it does not change when a build system lists a target's dependencies in another order.
	private var moduleInfoURLs: [URL] {
		get throws {
			if let dependentModuleInfoFilePath {
				try Set(
					String(contentsOfFile: dependentModuleInfoFilePath, encoding: .utf8)
						.parsedPathListCSV(),
				)
				.sorted()
				.map(\.asFileURL)
			} else {
				[]
			}
		}
	}

	/// The dependent modules' info, in the order of `moduleInfoURLs` whatever order the parallel reads finish in.
	private func loadSafeDIModuleInfo() async throws -> [ModuleInfo] {
		let moduleInfoURLs = try moduleInfoURLs
		return try await withThrowingTaskGroup(
			of: (index: Int, moduleInfo: ModuleInfo).self,
			returning: [ModuleInfo].self,
		) { taskGroup in
			for (index, moduleInfoURL) in moduleInfoURLs.enumerated() {
				taskGroup.addTask {
					do {
						return try (index: index, moduleInfo: ModuleInfo(moduleInfoData: Data(contentsOf: moduleInfoURL)))
					} catch let error as BinaryFileReadError {
						throw UnreadableModuleInfoError(path: moduleInfoURL.path, reason: error)
					}
				}
			}
			var indexedModuleInfo = [(index: Int, moduleInfo: ModuleInfo)]()
			for try await moduleInfo in taskGroup {
				indexedModuleInfo.append(moduleInfo)
			}
			return indexedModuleInfo
				.sorted { $0.index < $1.index }
				.map(\.moduleInfo)
		}
	}
}

extension SafeDIConfiguration {
	/// Throws when an `additionalMocksToGenerate` entry names no type an `@Instantiable` declaration declares in any
	/// clause of any `#if` block, whose mock can then never be generated. An entry that names a type declared only in
	/// clauses the conditions leave inactive is no mistake: its mock's file is written without code, as the file of
	/// any other declaration the conditions leave inactive is. Mock generation matches an entry to the declared type
	/// that the entry spells exactly, so each error also names the declared types that differ from the entry only in
	/// leading components, and the declared type that fulfills the entry when an `@Instantiable` fulfills it as an
	/// additional type.
	///
	/// - Parameters:
	///   - typeDescriptionToFulfillingInstantiableMap: Every type the active `@Instantiable` declarations SafeDI read
	///     fulfill, mapped to the declaration that fulfills it.
	///   - instantiableTypeNamesInAnyClause: The type each `@Instantiable` declaration SafeDI read declares, whether
	///     or not the conditions leave the declaration active.
	func validateAdditionalMocksToGenerate(
		fulfilledBy typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
		orDeclaredAmong instantiableTypeNamesInAnyClause: Set<String>,
	) throws(AdditionalMocksNameNoInstantiableError) {
		let declaredTypeNames = Set(typeDescriptionToFulfillingInstantiableMap.values.map(\.concreteInstantiable.asSource))
			.union(instantiableTypeNamesInAnyClause)
		let undeclaredTypeNames = Set(additionalMocksToGenerate).subtracting(declaredTypeNames).sorted()
		guard !undeclaredTypeNames.isEmpty else { return }
		throw AdditionalMocksNameNoInstantiableError(sourceDiagnostics: undeclaredTypeNames.map { typeName in
			let similarTypeNames = declaredTypeNames
				.filter { $0.hasSuffix(".\(typeName)") || typeName.hasSuffix(".\($0)") }
				.sorted()
			let similarTypeNamesDescription = similarTypeNames.isEmpty
				? ""
				: " SafeDI read @\(InstantiableVisitor.macroName) types with similar names: \(similarTypeNames.map { "`\($0)`" }.joined(separator: ", "))."
			let fulfillingTypeNameDescription = typeDescriptionToFulfillingInstantiableMap
				.filter { $0.key.asSource == typeName }
				.map(\.value.concreteInstantiable.asSource)
				.min()
				.map { " `\(typeName)` is fulfilled by the @\(InstantiableVisitor.macroName) type `\($0)`." }
				?? ""
			return SourceDiagnostic(
				severity: .error,
				location: declarationLocation,
				message: "This #\(SafeDIConfigurationVisitor.macroName) lists `\(typeName)` in \(SafeDIConfigurationVisitor.additionalMocksToGenerateArgumentLabel), but no @\(InstantiableVisitor.macroName) declaration SafeDI read declares `\(typeName)`, so SafeDI cannot generate its mock.\(fulfillingTypeNameDescription)\(similarTypeNamesDescription) Correct the name to that of an @\(InstantiableVisitor.macroName) type, or remove `\(typeName)` from \(SafeDIConfigurationVisitor.additionalMocksToGenerateArgumentLabel).",
			)
		})
	}
}

/// A `#SafeDIConfiguration` lists, in `additionalMocksToGenerate`, types no `@Instantiable` declaration declares.
/// Each diagnostic names one such type, in name order.
struct AdditionalMocksNameNoInstantiableError: SourceLocatedError {
	let sourceDiagnostics: [SourceDiagnostic]
}

/// A `.safedi` file named by `--dependent-module-info-file-path` that this SafeDITool cannot read.
struct UnreadableModuleInfoError: Error, CustomStringConvertible {
	let path: String
	let reason: BinaryFileReadError

	var description: String {
		"Could not read the SafeDI module info file at \(path): \(reason) \(BinaryFile.unreadableFileExplanation)"
	}
}
