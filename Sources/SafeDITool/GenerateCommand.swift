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

	@Flag(help: "States that the compiler is handed every input Swift file, including the files behind dependent module info, at exactly the path this tool is handed. Generated code then wraps each `@Received(fulfilledByDependencyNamed:ofType:)` assignment in a `#sourceLocation` directive naming that path, so the compiler reports a type mismatch at the declaration. Without this flag, and without a build tool plugin’s manifest, the assignment names the declaration in a comment instead, because the compiler warns at a directive whose path differs from the one it was handed.") var compilerReceivesInputPathsUnchanged = false

	// MARK: Internal

	func run() async throws {
		let buildLog = BuildLog()
		do {
			let warnings = try await generate(buildLog: buildLog)
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

	/// Parses, validates, and writes the configured outputs.
	/// Throws `SourceLocatedError`s as-is so tests can inspect their diagnostics; `run()` formats them for the build log.
	/// - Parameter buildLog: Learns how the project spells its files, which decides how `run()` prints diagnostics.
	/// - Returns: Warnings about the module, which do not stop generation. `run()` prints them.
	@discardableResult
	func generate(buildLog: BuildLog = BuildLog()) async throws -> [SourceDiagnostic] {
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

		let resolvedAdditionalImportedModules: [String] = if let sourceConfiguration {
			additionalImportedModules + sourceConfiguration.additionalImportedModules
		} else {
			additionalImportedModules
		}

		// If the source configuration specifies additional directories to include,
		// find and parse swift files in those directories and merge with initial
		// results. Skipped when the initial module came from scan's cache —
		// scan already merged the additional directories into the cached
		// ModuleInfo, so re-parsing would be wasted work.
		let module: ModuleInfo
		if !initialModuleIsFromCache,
		   let sourceConfiguration,
		   !sourceConfiguration.additionalDirectoriesToInclude.isEmpty
		{
			// Paths are compared as scan compared them: inputs relative to the manifest's project root, or else to
			// the working directory. Each additional file is named as scan names it in the manifest, so the
			// manifest lists the roots it declares; without a project root, files are named as found.
			// Without a project root, paths compare as the working directory spells them.
			let comparisonFilePaths = projectFilePaths ?? ProjectFilePaths(projectRoot: FileManager.default.currentDirectoryPath)
			let additionalFileScans = try await parseAdditionalDirectoryFiles(
				Set(findSwiftFiles(inDirectories: sourceConfiguration.additionalDirectoriesToInclude).map(comparisonFilePaths.projectFilePath(of:))),
				excludingInputFilesAt: Set(inputFilePaths.map(comparisonFilePaths.projectFilePath(of:))),
				namedBy: projectFilePaths,
				conditionalCompilation: evaluator,
			)
			module = initialModule.including(ModuleInfo(additionalFileScans.map(\.fileScan)))
		} else {
			module = initialModule
		}

		// Each module's instantiables are already ordered by `parseSwiftFiles`, so the
		// combined order depends only on the caller's dependent-module list.
		let unnormalizedInstantiables = dependentModuleInfo.flatMap(\.instantiables) + module.instantiables
		let instantiableTypes = Set(unnormalizedInstantiables.flatMap(\.instantiableTypes))
		let normalizedInstantiables = unnormalizedInstantiables.map { unnormalizedInstantiable in
			func normalized(_ typeDescription: TypeDescription) -> TypeDescription? {
				typeDescription.qualifyingInstantiatedType(
					within: unnormalizedInstantiable.concreteInstantiable,
					amongInstantiableTypes: instantiableTypes,
				)
			}
			let unnormalizedToNormalizedTypeMap = unnormalizedInstantiable.dependencies.reduce(
				into: [TypeDescription: TypeDescription](),
			) { partialResult, nextDependency in
				if let bestTypeDescription = normalized(nextDependency.property.typeDescription) {
					partialResult[nextDependency.property.typeDescription] = bestTypeDescription
				}
			}

			let normalizedDependencies = unnormalizedInstantiable.dependencies.map { dependency in
				// The type that fulfills an instantiated or aliased dependency is written where the property is.
				let normalizedSource: Dependency.Source? = switch dependency.source {
				case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
					fulfillingTypeDescription.flatMap(normalized).map {
						.instantiated(
							fulfillingTypeDescription: $0,
							erasedToConcreteExistential: erasedToConcreteExistential,
						)
					}
				case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
					normalized(fulfillingProperty.typeDescription).map {
						.aliased(
							fulfillingProperty: fulfillingProperty.withUpdatedTypeDescription($0),
							erasedToConcreteExistential: erasedToConcreteExistential,
							onlyIfAvailable: onlyIfAvailable,
						)
					}
				case .forwarded, .received:
					nil
				}
				let normalizedTypeDescription = unnormalizedToNormalizedTypeMap[dependency.property.typeDescription]
				guard normalizedSource != nil || normalizedTypeDescription != nil else {
					// Default to what was in the code – we'll probably error later
					return dependency
				}
				return Dependency(
					property: normalizedTypeDescription.map(dependency.property.withUpdatedTypeDescription) ?? dependency.property,
					source: normalizedSource ?? dependency.source,
					declarationLocation: dependency.declarationLocation,
					identifierRange: dependency.identifierRange,
					typeAnnotationRange: dependency.typeAnnotationRange,
					bareAttributeRange: dependency.bareAttributeRange,
				)
			}
			let normalizedInitializer = unnormalizedInstantiable.initializer?.mapArguments {
				$0.withUpdatedTypeDescription(unnormalizedToNormalizedTypeMap[$0.typeDescription, default: $0.typeDescription])
			}
			let normalizedAdditionalInstantiables = unnormalizedInstantiable.instantiableTypes.dropFirst().map {
				if let enclosingType = unnormalizedInstantiable.concreteInstantiable.popNested,
				   let bestTypeDescription = TypeDescription.nestedOptions(
				   	referencedType: $0,
				   	within: enclosingType,
				   ).first(where: { instantiableTypes.contains($0) })
				{
					bestTypeDescription
				} else {
					// Default to what was in the code – we'll probably error later
					$0
				}
			}
			var normalized = Instantiable(
				instantiableType: unnormalizedInstantiable.concreteInstantiable,
				isRoot: unnormalizedInstantiable.isRoot,
				initializer: normalizedInitializer,
				additionalInstantiables: normalizedAdditionalInstantiables,
				dependencies: normalizedDependencies,
				declarationType: unnormalizedInstantiable.declarationType,
				mockAttributes: unnormalizedInstantiable.mockAttributes,
				generateMock: unnormalizedInstantiable.generateMock,
				mockOnly: unnormalizedInstantiable.mockOnly,
				// A hand-written mock's arguments are matched to dependencies by type. A `mockOnly` declaration has no
				// dependencies of its own to map them by, and its mock is matched to those of the declaration it merges
				// into, so each argument's type is qualified on its own.
				mockInitializer: unnormalizedInstantiable.mockInitializer?.mapArguments {
					$0.withUpdatedTypeDescription(normalized($0.typeDescription) ?? $0.typeDescription)
				},
				// The macro requires a hand-written mock to return `Self` or the type's name as its declaration spells
				// it, so a nested type's mock returns its unqualified name.
				mockReturnType: unnormalizedInstantiable.mockReturnType.map { normalized($0) ?? $0 },
				customMockName: unnormalizedInstantiable.customMockName,
				mockDeclarationLocation: unnormalizedInstantiable.mockDeclarationLocation,
				declarationLocation: unnormalizedInstantiable.declarationLocation,
			)
			normalized.sourceFilePath = unnormalizedInstantiable.sourceFilePath
			return normalized
		}
		let additionalImportStatements = resolvedAdditionalImportedModules.map { ImportStatement(moduleName: $0) }
		let generator = try DependencyTreeGenerator(
			importStatements: dependentModuleInfo.flatMap(\.imports) + additionalImportStatements + module.imports,
			// A dependent module's mock-only declarations reach this module's mocks, so its mock imports do too.
			mockImportStatements: dependentModuleInfo.flatMap(\.mockImports) + additionalImportStatements + module.mockImports,
			typeDescriptionToFulfillingInstantiableMap: resolveSafeDIFulfilledTypes(
				instantiables: normalizedInstantiables,
			),
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
				Compiler errors prevented the generation of the dependency tree. Files with errors:
					\(filesWithUnexpectedNodes.joined(separator: "\n\t"))
				\""")
				"""
				if let combinedOutput {
					try errorContent.write(toPath: combinedOutput)
				} else if let manifest {
					for entry in manifest.dependencyTreeGeneration {
						try errorContent.write(toPath: entry.outputFilePath)
					}
					for entry in manifest.mockGeneration {
						try errorContent.write(toPath: entry.outputFilePath)
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
							throw ValidationError("Manifest contains duplicate dependencyTreeGeneration inputFilePath: \(entry.inputFilePath)")
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

					if let manifest {
						let additionalMockTypeNames = Set(manifest.additionalMocksToGenerate)
						for entry in manifest.mockGeneration {
							let extensions: [String]? = if additionalMockTypeNames.contains(entry.inputFilePath) {
								typeNameToMockExtensions[entry.inputFilePath]
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
						let currentModuleMockSourceFileSet = Set(currentModuleMockSourceFiles)
						let typeNamesEmittedBySource = Set(
							mockResult.generatedRoots
								.filter { $0.sourceFilePath.map(currentModuleMockSourceFileSet.contains) ?? false }
								.map(\.typeDescription.asSource),
						)
						for sourceFile in currentModuleMockSourceFiles {
							writes.append((
								destination: nil,
								header: mockFileHeader,
								body: sourceFileToMockExtensions[sourceFile]?.sorted().joined(separator: "\n\n") ?? "",
							))
						}
						// Skip types already emitted via the per-source
						// loop — a type declared locally with
						// `generateMock: true` AND listed in
						// `additionalMocksToGenerate` otherwise emits
						// twice and fails to compile.
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
		return warnings
	}

	// MARK: Private

	/// The manifest names the files `generate` writes, and `scan` chose them before the build ran: a file for
	/// each declaration that decides which files exist, in any clause of any `#if` block. `generate` writes a
	/// file without code for a declaration these conditions leave inactive, but it cannot write a file the
	/// manifest does not name, which happens when a source file gained such a declaration after `scan` ran,
	/// or when a hand-written manifest omits it. These errors say so instead of omitting code, and reject a
	/// hand-written manifest whose paths `generate` cannot match.
	private enum ManifestError: Error, CustomStringConvertible {
		case rootNotInManifest(sourceFilePath: String)
		case mockNotInManifest(typeName: String, sourceFilePath: String)
		case configurationNotInManifest(sourceFilePath: String)
		case additionalMockNotInManifest(typeName: String)
		case mockScopedFileListedUnderTwoSpellings(firstSpelling: String, secondSpelling: String)

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
			}
		}

		private static let planningExplanation = "SafeDI decides which files to generate before the build runs, listing every file that declares a root, a type that sets `generateMock: true`, or a #\(SafeDIConfigurationVisitor.macroName) in any clause of its `#if` blocks, so the file most likely changed after that decision; building again lists it."
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
			let currentAdditionalFiles = await (try? findSwiftFiles(inDirectories: cached.additionalDirectories)) ?? []
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

	private func resolveSafeDIFulfilledTypes(instantiables: [Instantiable]) throws -> [TypeDescription: Instantiable] {
		// Errors cite every declaration claiming the type rather than the pair that collided: a merged entry
		// no longer knows which declaration it came from, and the pair would depend on collection order.
		func productionDeclarationLocations(fulfilling instantiableType: TypeDescription) -> [Dependency.DeclarationLocation?] {
			instantiables
				.filter { !$0.mockOnly && $0.instantiableTypes.contains(instantiableType) }
				.map(\.declarationLocation)
		}
		func mockProviderDeclarationLocations(fulfilling instantiableType: TypeDescription) -> [Dependency.DeclarationLocation?] {
			instantiables
				.filter { ($0.mockOnly || $0.mockInitializer != nil) && $0.instantiableTypes.contains(instantiableType) }
				.map(\.declarationLocation)
		}
		var typeDescriptionToFulfillingInstantiableMap = [TypeDescription: Instantiable]()
		// Track types that have already had a mockOnly merged in, so a second
		// mockOnly is rejected even after the merged entry appears non-mockOnly.
		var typesWithMockOnlyMerge = Set<TypeDescription>()
		for instantiable in instantiables {
			for instantiableType in instantiable.instantiableTypes {
				if let existing = typeDescriptionToFulfillingInstantiableMap[instantiableType] {
					// Allow one mockOnly and one non-mockOnly for the same type.
					switch (existing.mockOnly, instantiable.mockOnly) {
					case (true, true):
						throw CollectInstantiablesError.duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
					case (false, true):
						guard !typesWithMockOnlyMerge.contains(instantiableType) else {
							throw CollectInstantiablesError.duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
						}
						typesWithMockOnlyMerge.insert(instantiableType)
						if existing.concreteInstantiable == instantiable.concreteInstantiable {
							// Same concrete type: two hand-written mocks is ambiguous.
							guard existing.mockInitializer == nil else {
								throw CollectInstantiablesError.duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
							}
							// Only merge if the mockOnly's return type is compatible
							// with this slot. Check against instantiableType (the key)
							// so a mock returning ServiceProtocol merges for the
							// ServiceProtocol slot but not the MyService slot.
							if instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiableType) {
								typeDescriptionToFulfillingInstantiableMap[instantiableType] = existing.mergedWithMockProvider(instantiable)
							}
						} else {
							// Different concrete types: non-mockOnly already holds the
							// slot, so the mockOnly is not registered here.
						}
					case (true, false):
						typesWithMockOnlyMerge.insert(instantiableType)
						if existing.concreteInstantiable == instantiable.concreteInstantiable {
							// Same concrete type: two hand-written mocks is ambiguous.
							guard instantiable.mockInitializer == nil else {
								throw CollectInstantiablesError.duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
							}
							// Only merge if the mockOnly's return type is compatible
							// with this slot.
							if existing.mockReturnTypeIsCompatible(withPropertyType: instantiableType) {
								typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable.mergedWithMockProvider(existing)
							} else {
								// mockOnly's mock returns incompatible type — replace
								// with production entry (no mock merge).
								typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
							}
						} else {
							// Different concrete types: non-mockOnly wins the slot.
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
						}
					case (false, false):
						throw CollectInstantiablesError.foundDuplicateInstantiable(instantiableType, declaredAt: productionDeclarationLocations(fulfilling: instantiableType))
					}
				} else {
					typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
				}
			}
		}

		// Propagate merged mock info to sibling entries: when a mockOnly merged
		// into one key for a concreteInstantiable, other keys for the same
		// concreteInstantiable (from fulfillingAdditionalTypes) may still lack
		// the mock info. Copy it so all entries are consistent.
		// Only propagate when the mock return type is compatible with the
		// target entry's concrete type — a mock returning ServiceProtocol
		// should not spread to the MyService slot.
		var mockProviderByConcreteType = [TypeDescription: Instantiable]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values
			where !instantiable.mockOnly && instantiable.mockInitializer != nil
		{
			mockProviderByConcreteType[instantiable.concreteInstantiable] = instantiable
		}
		for (typeDescription, instantiable) in typeDescriptionToFulfillingInstantiableMap {
			if !instantiable.mockOnly,
			   instantiable.mockInitializer == nil,
			   let mockProvider = mockProviderByConcreteType[instantiable.concreteInstantiable],
			   mockProvider.mockReturnTypeIsCompatible(withPropertyType: instantiable.concreteInstantiable)
			{
				typeDescriptionToFulfillingInstantiableMap[typeDescription] = instantiable.mergedWithMockProvider(mockProvider)
			}
		}

		return typeDescriptionToFulfillingInstantiableMap
	}

	private enum CollectInstantiablesError: SourceLocatedError {
		case foundDuplicateInstantiable(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])
		case duplicateMockProvider(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])

		var sourceDiagnostics: [SourceDiagnostic] {
			let message: String
			let declarationLocations: [Dependency.DeclarationLocation?]
			switch self {
			case let .foundDuplicateInstantiable(duplicateInstantiable, declaredAt):
				message = "@\(InstantiableVisitor.macroName)-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `\(duplicateInstantiable.asSource)`"
				declarationLocations = declaredAt
			case let .duplicateMockProvider(duplicateInstantiable, declaredAt):
				message = "Found multiple hand-written mock providers for `\(duplicateInstantiable.asSource)`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both."
				declarationLocations = declaredAt
			}
			// Sorted by location so the output does not depend on collection order.
			return declarationLocations
				.map { declarationLocation in
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: message,
					)
				}
				.sorted(by: SourceDiagnostic.precedesInSourceOrder)
		}
	}
}

/// A `.safedi` file named by `--dependent-module-info-file-path` that this SafeDITool cannot read.
struct UnreadableModuleInfoError: Error, CustomStringConvertible {
	let path: String
	let reason: BinaryFileReadError

	var description: String {
		"Could not read the SafeDI module info file at \(path): \(reason) A different version of SafeDI most likely wrote this file, or its write was interrupted. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the module that wrote the file regenerates it."
	}
}
