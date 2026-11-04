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

	@Option(name: .customLong(BuildSettingProductModuleName.optionName), help: "The target's `PRODUCT_MODULE_NAME` build setting wrapped in square brackets, written as the literal `[${PRODUCT_MODULE_NAME}]`, which the Xcode project plugin passes. Names the module that compiles this run's files for the imports generated code copies; it is not `--module-name`: the plugin cannot say which module declares the files a `#SafeDIConfiguration`'s `additionalDirectoriesToInclude` adds, so a run given only this option still knows no module.") var buildSettingProductModuleName: String?

	@Option(help: "When set, SafeDITool concatenates every generated Swift file (dependency trees + mocks + mock configuration) into this one path — one header, bodies joined in source-file order, deterministic for stable inputs. Intended for build systems that need rule outputs statically declared at analysis time (Bazel, Buck2). Requires 'swift-sources-file-path' or '--include'. Cannot be combined with '--output-directory' or '--swift-manifest' — those are per-file emission modes. May be combined with '--module-info-output'. The combined file is always rewritten on every run, even when content would be unchanged.") var combinedOutput: String?

	@Option(help: "The desired output location of the DOT file expressing the Swift dependency injection tree. Only include this option when running on a project’s root module.") var dotFileOutput: String?

	@Option(help: "The name of the module this run generates code for: the module that compiles the files the input CSV and '--include' name. Each of those files' declarations, and the '--module-info-output' file, record it, so a module that reads the file knows which module declares each type. Files reached through a #SafeDIConfiguration's additionalDirectoriesToInclude belong to another module. Without this option and '--package-name', a run with '--swift-manifest' or '--output-directory' reads the module of each file from the target graph the SafeDIGenerator plugin writes beside its input CSV. Either way, the '--module-info-output' file also records, as modules this one depends on, the module each '--dependent-module-info-file-path' file records.") var moduleName: String?

	@Option(help: "The package of the module this run generates code for, as the compiler's '-package-name' names it, recorded as '--module-name' is. Omit it when the compiler receives no '-package-name'.") var packageName: String?

	@Flag(help: "States that the compiler is handed every input Swift file, including the files behind dependent module info, at exactly the path this tool is handed. Generated code then wraps each `@Received(fulfilledByDependencyNamed:ofType:)` assignment in a `#sourceLocation` directive naming that path, so the compiler reports a type mismatch at the declaration. Without a build tool plugin’s manifest, this tool also prints each error and warning at the path it was handed, as the compiler prints its own. Without this flag, and without a build tool plugin’s manifest, the assignment names the declaration in a comment instead, because the compiler warns at a directive whose path differs from the one it was handed, and errors and warnings name each file by its absolute path.") var compilerReceivesInputPathsUnchanged = false

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

	/// How `run()` prints diagnostics, which `generate` tells it as soon as it knows how the build system spells its files.
	final class BuildLog {
		/// `diagnostics` formatted for the build log, each file named as the build system spells it, so an IDE maps
		/// the diagnostic to the file it has open and a reader finds it wherever the log is read. The compiler prints
		/// each path as it was handed, so when the build system hands the compiler every path unchanged, so does this.
		/// Otherwise build systems hand the tool paths relative to its working directory, so a relative path is made
		/// absolute against it first.
		func formatted(_ diagnostics: [SourceDiagnostic]) -> String {
			let workingDirectory = FileManager.default.currentDirectoryPath
			return diagnostics
				.map { diagnostic in
					diagnostic.respellingFilePath { [buildSystemFilePaths] filePath in
						switch buildSystemFilePaths {
						case let .underProjectRoot(projectFilePaths):
							projectFilePaths.buildSystemPath(of: projectFilePaths.projectFilePath(of: NormalizedFilePath(filePath, relativeTo: workingDirectory)))
						case .unchanged:
							filePath
						case nil:
							NormalizedFilePath(filePath, relativeTo: workingDirectory).path
						}
					}.formatted
				}
				.joined(separator: "\n")
		}

		/// How the build system spells the files `generate` runs for, or `nil` before `generate` knows or when it does not.
		fileprivate(set) var buildSystemFilePaths: BuildSystemFilePaths?
	}

	/// How the build system spells the files a run of `generate` was handed, which is how the compiler and an IDE
	/// name them.
	enum BuildSystemFilePaths {
		/// A build tool plugin's manifest records the project root, under which the build system spells each file
		/// inside the project as it reported the root.
		case underProjectRoot(ProjectFilePaths)
		/// The integration passed `--compiler-receives-input-paths-unchanged`: it hands the compiler every input path,
		/// including those behind dependent module info, exactly as it handed this tool.
		case unchanged

		/// The spelling a run with these options knows, or `nil` when it does not.
		init?(projectFilePaths: ProjectFilePaths?, compilerReceivesInputPathsUnchanged: Bool) {
			if let projectFilePaths {
				self = .underProjectRoot(projectFilePaths)
			} else if compilerReceivesInputPathsUnchanged {
				self = .unchanged
			} else {
				return nil
			}
		}
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
		// The module that compiles this run's files when the Xcode project plugin's build expanded it, which names no
		// module for `moduleMembership` and serves only to keep generated code from importing that module.
		let productModuleName = try BuildSettingProductModuleName.moduleName(buildSettingProductModuleName)

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
				keepsTypeDeclarationsOtherModulesCanName: writesModuleInfoWithoutTargetGraph,
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
		let buildSystemFilePaths = BuildSystemFilePaths(
			projectFilePaths: projectFilePaths,
			compilerReceivesInputPathsUnchanged: compilerReceivesInputPathsUnchanged,
		)
		buildLog.buildSystemFilePaths = buildSystemFilePaths
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
				// The proof reads a declaration of another module's file only where a mention names it.
				keepingDeclarationsOfTypesNamed: KeptPlainTypeNames(mentioning: mentionedTypeNames(of: initialModule.instantiables)),
			)
			parsedModuleInfo = initialModule.including(ModuleInfo(additionalFileScans.map(\.fileScan)))
		} else {
			parsedModuleInfo = initialModule
		}
		// Each declaration with the module that declares its file, as the build system tells this run, if it does. The
		// modules whose module info this run reads are ones this module depends on directly, as the build system lists
		// them, named as each file records its module, however this run learns which module its own files belong to.
		let membership = try moduleMembership(
			// Only a run with a manifest, which each of the SafeDIGenerator plugin's runs is, reads a target graph.
			targetGraphInputSourcesFilePath: resolvedSwiftManifest != nil ? swiftSourcesFilePath : nil,
			inputFilePaths: inputFilePaths,
			comparisonFilePaths: comparisonFilePaths,
		)
		let module = parsedModuleInfo.declared(
			by: membership,
			dependingOn: dependentModuleInfo.compactMap(\.moduleName),
		)

		// Each module's instantiables are already ordered by `parseSwiftFiles`, so the
		// combined order depends only on the caller's dependent-module list.
		let normalizedInstantiables = normalizingInstantiableTypes(of: dependentModuleInfo.flatMap(\.instantiables) + module.instantiables)
		let additionalImportStatements = resolvedAdditionalImportedModules.map { ImportStatement(moduleName: $0) }
		let typeDescriptionToFulfillingInstantiableMap = try resolveSafeDIFulfilledTypes(instantiables: normalizedInstantiables)
		// Generated code never imports the module it compiles in, which the compiler warns at: a file read from a module
		// above this one, through `additionalDirectoriesToInclude`, can import it. The `.safedi` keeps every import,
		// since a module that reads it imports this one rightly.
		let ownModuleName = module.moduleName ?? productModuleName
		func importingOtherModules(_ importStatements: [ImportStatement]) -> [ImportStatement] {
			importStatements.filter { $0.moduleName != ownModuleName }
		}
		// Why this run knows no module, which decides the remedy a diagnostic or comment about a seam built inline leads
		// with. Only the Xcode project plugin passes the product module name, expanded or not; the SwiftPM plugin writes
		// a target graph instead.
		let unnamedReason: DependencyTreeGenerator.EmittingModule.UnnamedReason? = if module.moduleName != nil {
			nil
		} else if buildSettingProductModuleName != nil {
			.xcodeProjectPlugin
		} else {
			.noModuleName
		}
		// The seams this run generates are those its own files declare; a seam another module declares is called
		// with the signature that module computed, from the declarations it saw. Which files are the module's own is
		// found only when a seam or a public mock exists, since a public mock another module declares is called with
		// the signature that module computed too: without the build system's word, finding them normalizes every input
		// path, which a project without either must not pay for, and nothing consults the set for any other declaration.
		let ownFilePaths: Set<String> = if normalizedInstantiables.contains(where: { $0.generatesDependencyTree || $0.generateMock == .public }) {
			Set(ownFilePaths(of: module, membership: membership, manifest: manifest, inputFilePaths: inputFilePaths, comparisonFilePaths: comparisonFilePaths))
		} else {
			[]
		}
		// The modules each module of the module info this run reads depends on directly, which that module's run read.
		let dependencyModuleNamesByModuleName = Dictionary(
			dependentModuleInfo.compactMap { dependentModule in dependentModule.moduleName.map { ($0, dependentModule.dependencyModuleNames) } },
			uniquingKeysWith: { first, _ in first },
		)
		let seamResolution = try seamResolution(
			normalizedInstantiables: normalizedInstantiables,
			ownFilePaths: ownFilePaths,
			module: module,
			configuration: sourceConfiguration,
			dependentModuleInfo: dependentModuleInfo,
			membership: membership,
		)
		let isOwnFile = Self.isOwnFile(
			manifest: manifest,
			inputFilePaths: inputFilePaths,
			comparisonFilePaths: comparisonFilePaths,
		)
		let generator = DependencyTreeGenerator(
			importStatements: importingOtherModules(dependentModuleInfo.flatMap(\.imports) + additionalImportStatements + module.imports),
			// A dependent module's mock-only declarations reach this module's mocks, so its mock imports do too.
			mockImportStatements: importingOtherModules(dependentModuleInfo.flatMap(\.mockImports) + additionalImportStatements + module.mockImports),
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
				compilerFilePaths: compilerFilePaths(manifest: manifest, buildSystemFilePaths: buildSystemFilePaths, inputFilePaths: inputFilePaths),
				// A plugin's paths relative to its project root, and any other integration's paths as it wrote them.
				commentFilePath: { [projectFilePaths] filePath in
					projectFilePaths.map { $0.manifestPath(of: $0.projectFilePath(of: filePath)) } ?? filePath
				},
			),
			emittingModule: DependencyTreeGenerator.EmittingModule(
				identity: ModuleIdentity(moduleName: module.moduleName, packageName: module.packageName),
				isOwnFile: isOwnFile,
				// A declaration records its file as this run named it: relative to the project root, or else to the
				// working directory, or absolute.
				isReadableFile: { filePath in
					FileManager.default.isReadableFile(atPath: comparisonFilePaths.projectFilePath(of: filePath).path)
				},
				additionalMocksToGenerateLocation: sourceConfiguration?.declarationLocation,
				unnamedReason: unnamedReason,
				moduleNamesReadByRunOfModule: { [membership] moduleName in
					Self.moduleNamesRead(byRunOfModuleNamed: moduleName, dependencyModuleNamesByModuleName: dependencyModuleNamesByModuleName, membership: membership)
				},
			),
			seams: seamResolution,
			plainTypeDeclarations: dependentModuleInfo.flatMap(\.plainTypeDeclarations) + module.plainTypeDeclarations,
			// The levels the module's own files spell apart from those of its dependencies' files: under the SwiftPM plugin,
			// the module's files include those of the modules it depends on, whose levels say nothing of its own imports.
			writtenImportAccessLevels: GeneratedImportAccess.WrittenLevels(
				ownImportStatements: module.imports + module.mockImports,
				importStatements: dependentModuleInfo.flatMap { $0.imports + $0.mockImports } + module.imports + module.mockImports,
				isOwnFile: isOwnFile,
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
					// A seam gets a file in the module that declares it, as `scan` plans one for the module's own files.
					// The first in declaration order, as the mock check chooses, never by type name.
					if let seam = module.instantiables
						.first(where: { $0.generatesDependencyTree && $0.sourceFilePath.map { ownFilePaths.contains($0) && !manifestInputPaths.contains($0) } == true }),
						let sourceFilePath = seam.sourceFilePath
					{
						throw ManifestError.dependencyTreeTypeNotInManifest(typeName: seam.concreteInstantiable.asSource, sourceFilePath: sourceFilePath)
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
						let matchedSourceFilePaths = module.instantiables.filter(\.generatesMock).compactMap(\.sourceFilePath).filter { !manifestMockInputPaths.contains($0) }
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
						for instantiable in module.instantiables where instantiable.generatesMock {
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
				// A type another module generates a public mock for is called there, never generated here.
				try sourceConfiguration?.validateAdditionalMocksToGenerate(
					namingPublicMocksOf: typeDescriptionToFulfillingInstantiableMap.values.filter { instantiable in
						instantiable.generateMock == .public && instantiable.moduleName != nil && instantiable.moduleName != module.moduleName
					},
				)

				// Accumulate every emission as a `(destination, holdsMockCode, body)`
				// triple. `destination == nil` means the write is combined-
				// only (no standalone file). A manifest-driven run
				// populates destinations from the manifest; a
				// combined-output run leaves them all nil and lets the
				// concat step below do the emission under one header.
				// Each file's header imports what its content needs, at the
				// levels its declarations need where they compile, so it is
				// made from its body. Generated mocks compile only where the
				// mock condition is active, so they import what the module's
				// `#if` blocks select there.
				var writes: [(destination: URL?, holdsMockCode: Bool, body: String)] = []

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
						module.instantiables
							.filter { $0.isRoot || ($0.generatesDependencyTree && $0.sourceFilePath.map(ownFilePaths.contains) == true) }
							.compactMap(\.sourceFilePath),
					).sorted()
				}
				for sourceFile in dependencyTreeSourcesInOrder {
					writes.append((
						destination: dependencyTreeDestinationsBySource[sourceFile],
						holdsMockCode: false,
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
						module.instantiables.filter(\.generatesMock).compactMap(\.sourceFilePath),
					).sorted()
				}
				let hasAnyMockGeneration = !currentModuleMockSourceFiles.isEmpty
					|| !listedAdditionalMocksToGenerate.isEmpty
				// Use the config's mockConditionalCompilation if a config exists;
				// default to "DEBUG" when no config exists (per-type opt-in without config).
				let mockConditionalCompilation: String? = if let sourceConfiguration {
					sourceConfiguration.mockConditionalCompilation
				} else {
					"DEBUG"
				}

				if hasAnyMockGeneration {
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
								holdsMockCode: true,
								body: extensions?.sorted().joined(separator: "\n\n") ?? "",
							))
						}
						// Shared mock-configuration file. Declared even
						// when empty — the build system expects the
						// output to exist.
						if let mockConfigurationOutputFilePath = manifest.mockConfigurationOutputFilePath {
							writes.append((
								destination: URL(fileURLWithPath: mockConfigurationOutputFilePath),
								holdsMockCode: true,
								body: mockResult.mockConfigurationCode ?? "",
							))
						}
					} else {
						// Combined mode: per-source mocks sorted, then
						// per-type-name additional mocks sorted.
						for sourceFile in currentModuleMockSourceFiles {
							writes.append((
								destination: nil,
								holdsMockCode: true,
								body: sourceFileToMockExtensions[sourceFile]?.sorted().joined(separator: "\n\n") ?? "",
							))
						}
						// Skip types already emitted via the per-source loop.
						for typeName in Set(additionalMocksToGenerate).sorted()
							where !typeNamesEmittedBySource.contains(typeName)
						{
							writes.append((
								destination: nil,
								holdsMockCode: true,
								body: typeNameToMockExtensions[typeName]?.sorted().joined(separator: "\n\n") ?? "",
							))
						}
						if let mockConfigurationCode = mockResult.mockConfigurationCode,
						   !mockConfigurationCode.isEmpty
						{
							writes.append((destination: nil, holdsMockCode: true, body: mockConfigurationCode))
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
					let bodies = writes.map(\.body).filter { !$0.isEmpty }
					// One comment names the types the file's `public` declarations name that SafeDI reads no declaration of.
					let combinedBody = UnreadTypeComment.resolvingMarkers(in: bodies.joined(separator: "\n\n"))
					// The header reads the dependency-tree code apart from the mock code, which compiles only under the mock
					// condition.
					let combinedContent: DependencyTreeGenerator.GeneratedFileContent = if hasAnyMockGeneration {
						.dependencyTreeAndMock(
							dependencyTreeCode: UnreadTypeComment.resolvingMarkers(in: writes.filter { !$0.holdsMockCode }.map(\.body).joined(separator: "\n\n")),
							mockCode: UnreadTypeComment.resolvingMarkers(in: writes.filter(\.holdsMockCode).map(\.body).joined(separator: "\n\n")),
							mockConditionalCompilation: mockConditionalCompilation,
						)
					} else {
						.dependencyTree(code: combinedBody)
					}
					let code = await generator.fileHeader(for: combinedContent) + compileTimeAssertions + combinedBody
					// Always write — this flag is used to support Bazel and Buck2, which content-hash their inputs, so a stat-identical re-write costs them nothing. Moreover, these tools require that genrules write the outputs that are expected.
					try code.write(toPath: combinedOutput)
				} else {
					for write in writes {
						guard let destination = write.destination else { continue }
						let fileContent: DependencyTreeGenerator.GeneratedFileContent = if write.holdsMockCode {
							.mock(code: write.body, mockConditionalCompilation: mockConditionalCompilation)
						} else {
							.dependencyTree(code: write.body)
						}
						let content = await generator.fileHeader(for: fileContent) + compileTimeAssertions + write.body
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
		case dependencyTreeTypeNotInManifest(typeName: String, sourceFilePath: String)
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
			case let .dependencyTreeTypeNotInManifest(typeName, sourceFilePath):
				"Found @\(InstantiableVisitor.macroName)(generateDependencyTree: true) on `\(typeName)` in '\(sourceFilePath)', but this file is not listed in the manifest’s dependencyTreeGeneration. \(Self.planningExplanation) A hand-written manifest must list the file, or the type must not set `generateDependencyTree: true`."
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

		private static let planningExplanation = "SafeDI decides which files to generate before the build runs, listing every file that declares a root, a type that sets `generateDependencyTree: true` or `generateMock: true`, or a #\(SafeDIConfigurationVisitor.macroName) in any clause of its `#if` blocks, so the file most likely changed after that decision; building again lists it."
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

	/// The module's own files, which the module this run generates code for compiles, as this run compares paths: the
	/// files the manifest's `mockScopedFilePaths` lists (a build tool plugin's target files, or `--mock-scoped-files`);
	/// and, without a manifest or with a hand-written one that lists none, the files the input CSV or `--include`
	/// names. A file reached through `additionalDirectoriesToInclude` is another module's. Both the access check
	/// (`isOwnFile`) and the seams (`ownFilePaths`, without a module name) read this one definition, as `scan` plans a
	/// seam's output for a mock-scoped file alone.
	/// - Parameter comparisonFilePaths: How this run compares paths, which spells a file the same way whichever
	///   spelling names it.
	private static func ownProjectFilePaths(
		manifest: SafeDIToolManifest?,
		inputFilePaths: Set<String>,
		comparisonFilePaths: ProjectFilePaths,
	) -> Set<ProjectFilePath> {
		Set((manifest?.mockScopedFilePaths ?? Array(inputFilePaths)).map(comparisonFilePaths.projectFilePath(of:)))
	}

	/// Whether a file a declaration records is one of the module's own files (see `ownProjectFilePaths`), so that the
	/// generated code needs only `internal` access to a declaration in it.
	private static func isOwnFile(
		manifest: SafeDIToolManifest?,
		inputFilePaths: Set<String>,
		comparisonFilePaths: ProjectFilePaths,
	) -> @Sendable (String) -> Bool {
		let ownFilePaths = ownProjectFilePaths(manifest: manifest, inputFilePaths: inputFilePaths, comparisonFilePaths: comparisonFilePaths)
		return { filePath in ownFilePaths.contains(comparisonFilePaths.projectFilePath(of: filePath)) }
	}

	/// The files of the module this run generates code for, spelled as the declarations read from them spell
	/// `sourceFilePath`: the files the build system attributes to that module when it attributes files to modules, and
	/// otherwise the module's own files (see `ownProjectFilePaths`).
	private func ownFilePaths(
		of module: ModuleInfo,
		membership: ModuleMembership?,
		manifest: SafeDIToolManifest?,
		inputFilePaths: Set<String>,
		comparisonFilePaths: ProjectFilePaths,
	) -> [String] {
		if let membership, let moduleName = membership.moduleName {
			return module.instantiables.filter { $0.moduleName == moduleName }.compactMap(\.sourceFilePath)
		} else {
			let ownProjectFilePaths = Self.ownProjectFilePaths(manifest: manifest, inputFilePaths: inputFilePaths, comparisonFilePaths: comparisonFilePaths)
			return module.instantiables
				.compactMap(\.sourceFilePath)
				.filter { ownProjectFilePaths.contains(comparisonFilePaths.projectFilePath(of: $0)) }
		}
	}

	/// How this run treats each seam among the declarations it read. A seam one of the module's own files declares is
	/// one this run generates. A seam another module declares is called with the signature that module computed, so
	/// this run computes it from the declarations that module saw: under a build system that runs `generate` once per
	/// module, its `.safedi` holds its own declarations and names the modules it depends on directly, whose `.safedi`
	/// this run must have been given too; under the SwiftPM plugin, the target graph names each target's direct
	/// dependencies, and the module's run read the files of every target it depends on, directly or through another.
	/// A seam whose module SafeDITool does not know is built inline, as any other type is. Under the target graph, this
	/// run read every module's files under its own mock condition, the one `configuration` names, so each foreign seam
	/// carries its module's, for the generator to compare.
	private func seamResolution(
		normalizedInstantiables: [Instantiable],
		ownFilePaths: Set<String>,
		module: ModuleInfo,
		configuration: SafeDIConfiguration?,
		dependentModuleInfo: [ModuleInfo],
		membership: ModuleMembership?,
	) throws -> SeamResolution {
		let seamInstantiables = normalizedInstantiables.filter(\.generatesDependencyTree)
		// The `generateMock: .public` types other modules declare, whose public mocks this module's mock trees call.
		let publicMockInstantiables = normalizedInstantiables.filter { $0.generateMock == .public && $0.sourceFilePath.map(ownFilePaths.contains) != true }
		// A module with a public mock of its own checks it over the declarations its callers see.
		let declaresPublicMock = module.instantiables.contains { $0.generateMock == .public }
		guard !seamInstantiables.isEmpty || !publicMockInstantiables.isEmpty || declaresPublicMock else { return .none }
		// A `mockOnly` declaration with `generateDependencyTree: true`, which the macro rejects, has no tree of its own:
		// reported here, as a plain error at the declaration, since every seam type the generator sees must be a
		// production declaration's concrete type, which the seam maps rely on.
		let mockOnlySeams = seamInstantiables.filter(\.mockOnly)
		if !mockOnlySeams.isEmpty {
			throw MockOnlySeamError(sourceDiagnostics: SourceDiagnostic.joiningInSourceOrder(mockOnlySeams.map { seam in
				[SourceDiagnostic(
					severity: .error,
					location: seam.declarationLocation,
					message: "`\(seam.concreteInstantiable.asSource)` is declared `mockOnly: true` and `generateDependencyTree: true`. The @Instantiable macro rejects that: a `mockOnly` declaration provides a hand-written mock and has no dependency tree. Remove `generateDependencyTree: true`.",
				)]
			}))
		}
		// The declarations as each module read them: normalization qualifies a nested type among the declarations a
		// run sees, so a module's seams are computed from its declarations normalized among what it saw.
		let unnormalizedInstantiables = dependentModuleInfo.flatMap(\.instantiables) + module.instantiables
		let plainTypeDeclarations = dependentModuleInfo.flatMap(\.plainTypeDeclarations) + module.plainTypeDeclarations
		let dependentModulesByName = Dictionary(
			dependentModuleInfo.compactMap { dependentModule in dependentModule.moduleName.map { ($0, dependentModule) } },
			uniquingKeysWith: { first, _ in first },
		)
		var generatedSeams = Set<TypeDescription>()
		var foreignSeams = [TypeDescription: SeamResolution.ForeignSeam]()
		var foreignPublicMocks = [TypeDescription: SeamResolution.ForeignPublicMock]()
		var visibleInstantiablesByModuleName = [String: VisibleDeclarations]()
		/// The declarations the module named `moduleName` sees, read once per module.
		func visibleDeclarations(ofModuleNamed moduleName: String) throws -> VisibleDeclarations {
			if let cached = visibleInstantiablesByModuleName[moduleName] {
				return cached
			}
			let visible: VisibleDeclarations
			if let dependentModule = dependentModulesByName[moduleName] {
				// A dependency this run was not given is recorded, and reported only for a seam a tree reaches.
				var instantiables = dependentModule.instantiables
				var visiblePlainTypeDeclarations = dependentModule.plainTypeDeclarations
				var missingDependencyModuleName: String?
				for dependencyModuleName in dependentModule.dependencyModuleNames {
					if let dependency = dependentModulesByName[dependencyModuleName] {
						instantiables += dependency.instantiables
						visiblePlainTypeDeclarations += dependency.plainTypeDeclarations
					} else if missingDependencyModuleName == nil {
						missingDependencyModuleName = dependencyModuleName
					}
				}
				// A module info holds the module's declarations as the module read them, and the configuration it read.
				visible = try VisibleDeclarations(
					instantiables: resolveSafeDIFulfilledTypes(instantiables: normalizingInstantiableTypes(of: instantiables)),
					plainTypeDeclarations: visiblePlainTypeDeclarations,
					readFromModuleInfo: true,
					missingDependencyModuleName: missingDependencyModuleName,
					mockCondition: Self.mockCondition(of: dependentModule.configurations.first),
				)
			} else {
				// The module is in the target graph: a declaration's module is named only by the graph, or by the
				// options, which name this run's own module.
				let visibleModuleNames = Self.visibleModuleNames(from: moduleName, in: membership)
				let instantiables = unnormalizedInstantiables.filter { $0.moduleName.map(visibleModuleNames.contains) == true }
				// This run read the module's files under its own mock condition, while the module reads them under
				// the one its own configuration names: of the configurations this run read, the one in a file the
				// graph attributes to the module.
				let moduleConfiguration = module.configurations.first { configuration in
					configuration.sourceFilePath.flatMap { membership?.declaringModule(ofFileAt: $0)?.moduleName } == moduleName
				}
				visible = try VisibleDeclarations(
					instantiables: resolveSafeDIFulfilledTypes(instantiables: normalizingInstantiableTypes(of: instantiables)),
					plainTypeDeclarations: plainTypeDeclarations.filter { $0.moduleName.map(visibleModuleNames.contains) == true },
					readFromModuleInfo: false,
					missingDependencyModuleName: nil,
					mockCondition: Self.mockCondition(of: moduleConfiguration),
				)
			}
			visibleInstantiablesByModuleName[moduleName] = visible
			return visible
		}
		// In declaration order, which decides nothing here: a module's visible declarations are read once, whichever
		// of its seams is met first.
		for seam in seamInstantiables {
			if seam.sourceFilePath.map(ownFilePaths.contains) == true {
				generatedSeams.insert(seam.concreteInstantiable)
			} else if let moduleName = seam.moduleName {
				let visible = try visibleDeclarations(ofModuleNamed: moduleName)
				foreignSeams[seam.concreteInstantiable] = SeamResolution.ForeignSeam(
					declaringModule: ModuleIdentity(moduleName: moduleName, packageName: seam.packageName),
					missingDependencyModuleName: visible.missingDependencyModuleName,
					visibleInstantiables: visible.instantiables,
					visiblePlainTypeDeclarations: visible.plainTypeDeclarations,
					callCarriesPluginComment: !visible.readFromModuleInfo,
					// A module info holds the module's declarations as the module read them.
					declaringModuleMockCondition: visible.readFromModuleInfo ? nil : visible.mockCondition,
				)
			}
		}
		for publicMock in publicMockInstantiables {
			guard let moduleName = publicMock.moduleName else { continue }
			let visible = try visibleDeclarations(ofModuleNamed: moduleName)
			foreignPublicMocks[publicMock.concreteInstantiable] = SeamResolution.ForeignPublicMock(
				declaringModule: ModuleIdentity(moduleName: moduleName, packageName: publicMock.packageName),
				missingDependencyModuleName: visible.missingDependencyModuleName,
				visibleInstantiables: visible.instantiables,
				visiblePlainTypeDeclarations: visible.plainTypeDeclarations,
				callCarriesPluginComment: !visible.readFromModuleInfo,
				declaringModuleMockCondition: visible.mockCondition,
			)
		}
		// Under the plugin's target graph, which names this module, callers compute this module's seams from the
		// files the graph lists, which leaves out the directories its configuration adds.
		let callersComputeFromTargetGraph = module.moduleName.map { membership?.dependencyModuleNames(ofModuleNamed: $0) != nil } ?? false
		// The declarations the callers of this module's seams see, when some declaration this run sees is not among
		// them: resolved as the callers resolve them, so a seam's signature can be computed over the callers' view and
		// compared with this run's. A module whose name is unknown has no callers computing a signature.
		let callersVisibleInstantiables: [TypeDescription: Instantiable]?
		// The callers see the plain type declarations of the modules they see, each with its module.
		var callersVisiblePlainTypeDeclarations = [PlainTypeDeclaration]()
		if !generatedSeams.isEmpty || declaresPublicMock, let moduleName = module.moduleName {
			if callersComputeFromTargetGraph {
				// A declaration the graph places in no module is in a directory the configuration adds.
				if unnormalizedInstantiables.contains(where: { $0.moduleName == nil }) || plainTypeDeclarations.contains(where: { $0.moduleName == nil }) {
					let callersVisibleModuleNames = Self.visibleModuleNames(from: moduleName, in: membership)
					callersVisibleInstantiables = try resolveSafeDIFulfilledTypes(instantiables: normalizingInstantiableTypes(of: unnormalizedInstantiables.filter { $0.moduleName.map(callersVisibleModuleNames.contains) == true }))
					callersVisiblePlainTypeDeclarations = plainTypeDeclarations.filter { $0.moduleName.map(callersVisibleModuleNames.contains) == true }
				} else {
					callersVisibleInstantiables = nil
				}
			} else if dependentModuleInfo.contains(where: { $0.moduleName == nil }) {
				callersVisibleInstantiables = try resolveSafeDIFulfilledTypes(instantiables: normalizingInstantiableTypes(of: dependentModuleInfo.filter { $0.moduleName != nil }.flatMap(\.instantiables) + module.instantiables))
				callersVisiblePlainTypeDeclarations = (dependentModuleInfo.filter { $0.moduleName != nil }.flatMap(\.plainTypeDeclarations) + module.plainTypeDeclarations)
					.filter { $0.moduleName != nil }
			} else {
				callersVisibleInstantiables = nil
			}
		} else {
			callersVisibleInstantiables = nil
		}
		return SeamResolution(
			currentModule: ModuleIdentity(moduleName: module.moduleName, packageName: module.packageName),
			currentModuleMockCondition: Self.mockCondition(of: configuration),
			generatedSeams: generatedSeams,
			foreignSeams: foreignSeams,
			foreignPublicMocks: foreignPublicMocks,
			callersComputeFromTargetGraph: callersComputeFromTargetGraph,
			callersVisibleInstantiables: callersVisibleInstantiables,
			callersVisiblePlainTypeDeclarations: callersVisiblePlainTypeDeclarations,
			// Every build tool plugin's run is given a manifest or an output directory. Any other run – Bazel's, Tuist's, a
			// custom script's – reads only the modules whose module info it is given.
			carriesUnreadTypeComment: swiftManifest == nil && outputDirectory == nil,
		)
	}

	/// The declarations a module sees, as `seamResolution` reads them for the seams and public mocks it declares.
	private struct VisibleDeclarations {
		let instantiables: [TypeDescription: Instantiable]
		/// The plain type declarations of the modules whose declarations `instantiables` holds.
		let plainTypeDeclarations: [PlainTypeDeclaration]
		/// Whether they were read from the module's module info rather than from the files the target graph lists.
		let readFromModuleInfo: Bool
		let missingDependencyModuleName: String?
		/// The condition the module guards its mocks with.
		let mockCondition: MockCondition
	}

	/// The condition a module whose configuration is `configuration` guards its mocks and mock-only declarations with,
	/// as the module's own run reads them: `DEBUG` for a module that declares no configuration.
	private static func mockCondition(of configuration: SafeDIConfiguration?) -> MockCondition {
		MockCondition(configuration.map(\.mockConditionalCompilation) ?? "DEBUG")
	}

	/// The modules whose declarations the run of `generate` for the module named `moduleName` reads, itself included, as
	/// this run knows them: the modules whose module info that run read, which the module info this run reads for the
	/// module names (`dependencyModuleNamesByModuleName`), or else, under the target graph, every module the module
	/// depends on, directly or not, whose files that run's input CSV lists (`visibleModuleNames(from:in:)`). These are
	/// the modules whose declarations `seamResolution` computes the signature of a seam the module declares from
	/// (`visibleDeclarations(ofModuleNamed:)`).
	private static func moduleNamesRead(
		byRunOfModuleNamed moduleName: String,
		dependencyModuleNamesByModuleName: [String: [String]],
		membership: ModuleMembership?,
	) -> Set<String> {
		if let dependencyModuleNames = dependencyModuleNamesByModuleName[moduleName] {
			Set([moduleName] + dependencyModuleNames)
		} else {
			visibleModuleNames(from: moduleName, in: membership)
		}
	}

	/// The modules whose declarations a module named `moduleName` sees under the target graph `membership` describes:
	/// itself and, transitively, the modules it depends on. The graph lists every module whose files it names
	/// (`ModuleMembership.dependencyModuleNames(ofModuleNamed:)`).
	private static func visibleModuleNames(from moduleName: String, in membership: ModuleMembership?) -> Set<String> {
		var visibleModuleNames: Set<String> = [moduleName]
		var moduleNamesToVisit = [moduleName]
		while let visitedModuleName = moduleNamesToVisit.popLast() {
			for dependencyModuleName in membership?.dependencyModuleNames(ofModuleNamed: visitedModuleName) ?? [] where visibleModuleNames.insert(dependencyModuleName).inserted {
				moduleNamesToVisit.append(dependencyModuleName)
			}
		}
		return visibleModuleNames
	}

	/// Which module this run's own files belong to, as the build system tells it, or `nil` when it tells nothing. The
	/// options, when either is given, describe a build system that runs `generate` once per module. Otherwise the target
	/// graph the SafeDIGenerator plugin writes beside its input CSV describes the files, when there is one.
	/// - Parameters:
	///   - targetGraphInputSourcesFilePath: The input CSV beside which a target graph is read, or `nil` for a run that
	///     reads none.
	///   - inputFilePaths: The files the input CSV and `--include` name.
	///   - comparisonFilePaths: How this run compares paths.
	private func moduleMembership(
		targetGraphInputSourcesFilePath: String?,
		inputFilePaths: Set<String>,
		comparisonFilePaths: ProjectFilePaths,
	) throws -> ModuleMembership? {
		if moduleName != nil || packageName != nil {
			ModuleMembership(
				moduleName: moduleName,
				packageName: packageName,
				inputFilePaths: Set(inputFilePaths.map(comparisonFilePaths.projectFilePath(of:))),
				filePathsSpelledBy: comparisonFilePaths,
			)
		} else if let targetGraphInputSourcesFilePath,
		          let targetGraph = try PluginTargetGraph(besideInputSourcesFileAt: targetGraphInputSourcesFilePath)
		{
			ModuleMembership(targetGraph: targetGraph)
		} else {
			nil
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

	/// Whether this run writes the module's info for other modules to read, and has no target graph that would tell it
	/// which of the module's types they name: a build system that runs `generate` once per module, such as the Bazel
	/// rule or the Tuist plugin. Such a run keeps every plain type declaration another module can name.
	private var writesModuleInfoWithoutTargetGraph: Bool {
		moduleInfoOutput != nil && swiftManifest == nil
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
		   	mockScopedFilePaths: manifest.mockScopedFilePaths.map(Set.init),
		   	projectFilePaths: projectFilePaths,
		   	activeCompilationConditions: activeCompilationConditions,
		   )
		{
			return (cached, true)
		} else {
			// Without a list of the module's own files, every input is one, which needs no path spelled for comparison.
			let isReadingModuleFile: (String) -> Bool = if manifest?.mockScopedFilePaths != nil {
				Self.isOwnFile(
					manifest: manifest,
					inputFilePaths: inputFilePaths,
					comparisonFilePaths: projectFilePaths ?? ProjectFilePaths(projectRoot: FileManager.default.currentDirectoryPath),
				)
			} else {
				{ _ in true }
			}
			return try await (
				parseModule(
					filePaths: inputFilePaths,
					// A fresh parse names files as the CSV does, so the manifest's configuration
					// files are matched among the CSV's paths.
					configurationFilePaths: manifest.map { $0.configurationFilePaths(among: inputFilePaths, in: projectFilePaths) } ?? inputFilePaths,
					activeCompilationConditions: activeCompilationConditions,
					keepsTypeDeclarationsOtherModulesCanName: writesModuleInfoWithoutTargetGraph,
					isReadingModuleFile: isReadingModuleFile,
				).module,
				false,
			)
		}
	}

	private func loadCachedModule(
		manifestPath: String,
		inputFilePaths: Set<String>,
		configurationFilePaths: Set<String>,
		mockScopedFilePaths: Set<String>?,
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
		// Scan kept the plain declarations of the types its walk's declarations mention, which these conditions can select
		// differently. The module's files are named as the manifest names them, which is how it lists its own files.
		guard let fileScans = try await refreshed(
		      	cached.conditionSensitiveFileScans,
		      	from: cached,
		      	activeCompilationConditions: activeCompilationConditions,
		      	evaluator: evaluator,
		      	keepingDeclarationsOfTypesNamed: cached.keptPlainTypeNames,
		      	mentionedByModuleInfo: cached.moduleInfo,
		      	keepsTypeDeclarationsOtherModulesCanName: writesModuleInfoWithoutTargetGraph,
		      	isReadingModuleFile: { mockScopedFilePaths?.contains($0) != false },
		      ),
		      let additionalFileScans = try await refreshed(
		      	cached.additionalConditionSensitiveFileScans,
		      	from: cached,
		      	activeCompilationConditions: activeCompilationConditions,
		      	evaluator: evaluator,
		      	keepingDeclarationsOfTypesNamed: cached.additionalKeptPlainTypeNames,
		      	mentionedByModuleInfo: nil,
		      	keepsTypeDeclarationsOtherModulesCanName: false,
		      	// A file reached through `additionalDirectoriesToInclude` is another module's.
		      	isReadingModuleFile: { _ in false },
		      )
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
	/// then the whole module is parsed afresh. So is a module whose declarations, once its files are walked again, mention
	/// other types than scan's did (`mentionedTypeNames(of:)`), when `mentionedByModuleInfo` gives the module's other
	/// files: scan kept the plain declarations of the types its walk's declarations mention, and asserted the decisions
	/// that select a clause declaring one a mention names, and a fresh parse keeps and asserts those of the types the
	/// module's declarations mention now, in another file as in a file walked again. A top-level `@Instantiable` type's
	/// name is left out of both sides: its own declaration proves it, so no plain declaration of its name is read, and a
	/// `#if DEBUG` declaration that mentions one, the usual case, keeps the cache. The name stays in when a plain declaration
	/// the module keeps under a block with decisions shares it (`FileScan.keptGuardedPlainTypeNames`), such as a nested
	/// type of that name: a mention of it decides whether that block's decisions are asserted.
	///
	/// A file walked again keeps the plain type declarations, and asserts the decisions about them, of the types scan
	/// kept (`keptTypeNames`), and, when `keepsTypeDeclarationsOtherModulesCanName`, the `package` ones, as a fresh parse
	/// keeps them. A file that mentions no SafeDI marker but declares such a type is parsed again too: the conditions of
	/// its blocks select which of its declarations are read.
	/// - Parameter isReadingModuleFile: Whether the file a cached scan names, as the manifest names it, is one of the
	///   module's own files (see `parseModule`).
	private func refreshed(
		_ cachedFileScans: [CachedFileScan],
		from cached: CachedScannedModuleInfo,
		activeCompilationConditions: Set<String>,
		evaluator: ConditionalCompilationEvaluator,
		keepingDeclarationsOfTypesNamed keptTypeNames: KeptPlainTypeNames,
		mentionedByModuleInfo moduleInfo: ModuleInfo?,
		keepsTypeDeclarationsOtherModulesCanName: Bool,
		isReadingModuleFile: (String) -> Bool,
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
		// safedi-source-rule: allow uniqueKeysWithValues — each cached scan names the file scan parsed under its own absolute path.
		let manifestPathByScannedPath = Dictionary(uniqueKeysWithValues: staleFileScans.map { ($0.scannedPath, $0.fileScan.path) })
		// Scan parsed every file under its absolute path, so the file is read from the name it is parsed under.
		let rescans = try await parseSwiftFilesDeclaringTypes(
			Set(staleFileScans.map(\.scannedPath)),
			conditionalCompilation: evaluator,
			keepingDeclarationsOfTypesNamed: keptTypeNames,
			keepsTypeDeclarationsOtherModulesCanName: keepsTypeDeclarationsOtherModulesCanName,
			isReadingModuleFile: { scannedPath in manifestPathByScannedPath[scannedPath].map(isReadingModuleFile) == true },
		)
		// safedi-source-rule: allow uniqueKeysWithValues — `parseSwiftFilesDeclaringTypes` walks or parses each path of a set once, and names each scan by the path it walked.
		let rescanByScannedPath = Dictionary(uniqueKeysWithValues: rescans.map { ($0.path, $0) })
		let staleScannedPaths = Set(staleFileScans.map(\.scannedPath))
		// A file that mentions no SafeDI marker and no longer declares a type scan kept contributes nothing, as in a fresh
		// parse.
		let refreshedFileScans = cachedFileScans.compactMap { cachedFileScan in
			if staleScannedPaths.contains(cachedFileScan.scannedPath) {
				rescanByScannedPath[cachedFileScan.scannedPath]?
					.relocated(to: cachedFileScan.fileScan.path)
			} else if cachedFileScan.fileScan.importOnlyConsultedCompilationConditions.contains(where: hasChangedValue) {
				// Only the file's imports depend on a changed condition, and its import segments hold them.
				cachedFileScan.fileScan.withImports(evaluatedWith: evaluator)
			} else {
				cachedFileScan.fileScan
			}
		}
		if let moduleInfo {
			// Scan kept the declarations, and asserted the decisions, of the types its declarations mentioned; a mention
			// that appeared or went away would change which a fresh parse keeps and asserts, in a file not walked again too.
			// Scan's names and these are both read without the top-level `@Instantiable` types of either walk, but for a
			// name a kept plain declaration under a block with decisions shares, whose decisions a mention of it decides.
			let guardedTypeNames = Set((cachedFileScans.map(\.fileScan) + refreshedFileScans).flatMap(\.keptGuardedPlainTypeNames))
			let exemptTypeNames = Set((moduleInfo.instantiables + cachedFileScans.flatMap(\.fileScan.instantiables) + refreshedFileScans.flatMap(\.instantiables)).compactMap { instantiable in
				instantiable.concreteInstantiable.popNested == nil ? instantiable.concreteInstantiable.outermostTypeName : nil
			}).subtracting(guardedTypeNames)
			guard mentionedTypeNames(of: moduleInfo.instantiables + refreshedFileScans.flatMap(\.instantiables)).subtracting(exemptTypeNames)
				== keptTypeNames.mentionedTypeNames.subtracting(exemptTypeNames)
			else {
				return nil
			}
		}
		return refreshedFileScans
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
		buildSystemFilePaths: BuildSystemFilePaths?,
		inputFilePaths: Set<String>,
	) -> AliasDeclarationReferences.CompilerFilePaths? {
		switch buildSystemFilePaths {
		case let .underProjectRoot(projectFilePaths):
			guard projectFilePaths.reportsResolvedProjectRoot else { return nil }
			let compilerFilePath = { (filePath: String) in projectFilePaths.buildSystemPath(of: projectFilePaths.projectFilePath(of: filePath)) }
			if swiftManifest == nil, !mockScopedFiles.isEmpty {
				return .init(filePath: compilerFilePath, moduleFilePaths: Set(mockScopedFiles), moduleFilePath: { $0 })
			} else {
				return .init(
					filePath: compilerFilePath,
					// A project root comes from a manifest, so `manifest` is present here.
					moduleFilePaths: manifest?.mockScopedFilePaths.map(Set.init) ?? inputFilePaths,
					moduleFilePath: compilerFilePath,
				)
			}
		case .unchanged:
			return .init(filePath: { $0 }, moduleFilePaths: inputFilePaths, moduleFilePath: { $0 })
		case nil:
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

extension SafeDIConfiguration {
	/// Reports each `additionalMocksToGenerate` entry that names a type whose public mock (`generateMock: .public`) another
	/// module generates: that module's `mock()` is the type's mock, and a second one here would make every call ambiguous.
	/// - Parameter publicMockTypes: The declarations of other modules that set `generateMock: .public`.
	func validateAdditionalMocksToGenerate(namingPublicMocksOf publicMockTypes: [Instantiable]) throws(AdditionalMocksNameNoInstantiableError) {
		let moduleNameByTypeName = publicMockTypes.reduce(into: [String: String]()) { result, instantiable in
			result[instantiable.concreteInstantiable.asSource] = instantiable.moduleName
		}
		let typeNames = Set(additionalMocksToGenerate).filter { moduleNameByTypeName[$0] != nil }.sorted()
		guard !typeNames.isEmpty else { return }
		throw AdditionalMocksNameNoInstantiableError(sourceDiagnostics: typeNames.map { typeName in
			SourceDiagnostic(
				severity: .error,
				location: declarationLocation,
				message: "`\(typeName)` already has a public `mock()` generated by `\(moduleNameByTypeName[typeName] ?? "")`. Remove it from \(SafeDIConfigurationVisitor.additionalMocksToGenerateArgumentLabel) and call `\(typeName).mock()`.",
			)
		})
	}
}

/// A `#SafeDIConfiguration` lists, in `additionalMocksToGenerate`, types no `@Instantiable` declaration declares.
/// Each diagnostic names one such type, in name order.
struct AdditionalMocksNameNoInstantiableError: SourceLocatedError {
	let sourceDiagnostics: [SourceDiagnostic]
}

/// A `mockOnly: true` declaration that is also `generateDependencyTree: true`, which the `@Instantiable` macro rejects:
/// `generate` runs before the compiler expands the macro, so it reports the shape plainly rather than relying on it.
struct MockOnlySeamError: SourceLocatedError {
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
