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

	@Option(help: "When set, SafeDITool concatenates every generated Swift file (dependency trees + mocks + mock configuration) into this one path instead of emitting the per-root / per-mock files a manifest describes. Useful for build systems that need rule outputs statically declared at analysis time (Bazel, Buck2). Requires 'swift-sources-file-path' or '--include'. May be combined with '--swift-manifest' (manifest drives discovery; combined file gets written) or '--module-info-output'. Cannot be combined with '--output-directory' — use one or the other.") var combinedOutput: String?

	@Option(help: "The desired output location of the DOT file expressing the Swift dependency injection tree. Only include this option when running on a project’s root module.") var dotFileOutput: String?

	// MARK: Internal

	func run() async throws {
		if swiftSourcesFilePath == nil, include.isEmpty {
			throw ValidationError("Must provide 'swift-sources-file-path' or '--include'.")
		}

		// --combined-output is the "one emitted file" mode; --output-directory
		// is the "one emitted file per root/mock" mode. Mixing them is
		// ambiguous and would leave scan's scratch JSON in --output-directory
		// without emitting any of the Swift files it listed there. Fail loud.
		if combinedOutput != nil, outputDirectory != nil {
			throw ValidationError("--combined-output cannot be combined with --output-directory. Use --combined-output alone (optionally with --swift-manifest) to emit a single file, or --output-directory to emit per-file outputs.")
		}

		// When --combined-output is the only emission flag, synthesize a
		// scratch output directory so the inline-scan path below can
		// fire. The manifest's per-entry outputFilePath values are
		// discarded in favor of the combined file anyway, so the
		// scratch location is ephemeral.
		var syntheticOutputDirectory: String?
		if combinedOutput != nil, outputDirectory == nil, swiftManifest == nil {
			let scratch = FileManager.default.temporaryDirectory
				.appendingPathComponent("SafeDITool-\(UUID().uuidString)")
				.path
			try FileManager.default.createDirectory(
				atPath: scratch,
				withIntermediateDirectories: true,
			)
			syntheticOutputDirectory = scratch
		}
		// Register cleanup before any throwing work below so a
		// failure in the inline scan doesn't leak the scratch dir.
		defer {
			if let syntheticOutputDirectory {
				try? FileManager.default.removeItem(atPath: syntheticOutputDirectory)
			}
		}

		// When --output-directory is provided without --swift-manifest, run an
		// inline scan to discover roots/mocks and build the manifest automatically.
		var resolvedSwiftManifest = swiftManifest
		let resolvedOutputDirectory = outputDirectory ?? syntheticOutputDirectory
		if resolvedSwiftManifest == nil, let resolvedOutputDirectory {
			// Inline scan needs a CSV. Prefer an explicit
			// --swift-sources-file-path. When running on the
			// synthetic scratch directory (i.e. `--combined-output`
			// is driving the flow), also allow `--include` to seed
			// the inputs — enumerate the included directories and
			// write a scratch CSV so directory-driven workflows
			// (`generate --include src/ --combined-output out.swift`)
			// don't require the caller to pre-build a CSV. The
			// explicit `--output-directory` path still requires a
			// CSV so existing behavior is unchanged.
			let inputSourcesFilePath: String
			if let swiftSourcesFilePath {
				inputSourcesFilePath = swiftSourcesFilePath
			} else if syntheticOutputDirectory != nil, !include.isEmpty {
				let includedFiles = try await findSwiftFiles(inDirectories: include)
				let scratchCSV = (resolvedOutputDirectory as NSString).appendingPathComponent("SafeDIToolInputSources.csv")
				try includedFiles
					.sorted()
					.joined(separator: ",")
					.write(toPath: scratchCSV)
				inputSourcesFilePath = scratchCSV
			} else {
				throw ValidationError("--output-directory requires 'swift-sources-file-path'.")
			}
			let manifestPath = (resolvedOutputDirectory as NSString).appendingPathComponent("SafeDIManifest.json")
			try await performScan(
				inputSourcesFile: inputSourcesFilePath,
				projectRoot: FileManager.default.currentDirectoryPath,
				outputDirectory: resolvedOutputDirectory,
				manifestFile: manifestPath,
				mockScopedFiles: mockScopedFiles,
			)
			resolvedSwiftManifest = manifestPath
		}

		let (dependentModuleInfo, parsed) = try await (
			loadSafeDIModuleInfo(),
			parsedModule(),
		)
		let initialModule = parsed.module
		let initialModuleIsFromCache = parsed.isFromCache

		// In multi-module builds, the CSV includes all modules' files, so multiple
		// configs may be present. Scope to the current module using the manifest's
		// configurationFilePaths (which lists only this target's own config files).
		let currentModuleConfigurations: [SafeDIConfiguration]
		if let resolvedSwiftManifest {
			let manifest = try JSONDecoder().decode(
				SafeDIToolManifest.self,
				from: Data(contentsOf: resolvedSwiftManifest.asFileURL),
			)
			let configurationFilePaths = Set(manifest.configurationFilePaths)
			currentModuleConfigurations = initialModule.configurations.filter { configuration in
				guard let configPath = configuration.sourceFilePath else { return false }
				return configurationFilePaths.contains(configPath)
			}
		} else {
			currentModuleConfigurations = initialModule.configurations
		}
		guard currentModuleConfigurations.count <= 1 else {
			let configPaths = currentModuleConfigurations.compactMap(\.sourceFilePath).joined(separator: "\n\t")
			throw ValidationError("Found \(currentModuleConfigurations.count) #\(SafeDIConfigurationVisitor.macroName) declarations in this module. Each module must have at most one #\(SafeDIConfigurationVisitor.macroName). Found in:\n\t\(configPaths)")
		}
		let sourceConfiguration: SafeDIConfiguration? = currentModuleConfigurations.first

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
			let additionalFiles = try await findSwiftFiles(inDirectories: sourceConfiguration.additionalDirectoriesToInclude)
			let additionalModule = try await parseSwiftFiles(additionalFiles)
			module = ModuleInfo(
				imports: initialModule.imports + additionalModule.imports,
				instantiables: initialModule.instantiables + additionalModule.instantiables,
				configurations: initialModule.configurations,
				filesWithUnexpectedNodes: initialModule.filesWithUnexpectedNodes.map { $0 + (additionalModule.filesWithUnexpectedNodes ?? []) } ?? additionalModule.filesWithUnexpectedNodes,
			)
		} else {
			module = initialModule
		}

		let unnormalizedInstantiables = dependentModuleInfo.flatMap(\.instantiables) + module.instantiables
		let instantiableTypes = Set(unnormalizedInstantiables.flatMap(\.instantiableTypes))
		let normalizedInstantiables = unnormalizedInstantiables.map { unnormalizedInstantiable in
			let unnormalizedToNormalizedTypeMap = unnormalizedInstantiable.dependencies.reduce(
				into: [TypeDescription: TypeDescription](),
			) { partialResult, nextDependency in
				if let bestTypeDescription = TypeDescription.nestedOptions(
					referencedType: nextDependency.property.typeDescription,
					within: unnormalizedInstantiable.concreteInstantiable,
				).first(where: { instantiableTypes.contains($0) }) {
					partialResult[nextDependency.property.typeDescription] = bestTypeDescription
				}
			}

			let normalizedDependencies = unnormalizedInstantiable.dependencies.map {
				if let bestTypeDescription = unnormalizedToNormalizedTypeMap[$0.property.typeDescription] {
					Dependency(
						property: $0.property.withUpdatedTypeDescription(bestTypeDescription),
						source: $0.source,
					)
				} else {
					// Default to what was in the code – we'll probably error later
					$0
				}
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
				mockInitializer: unnormalizedInstantiable.mockInitializer,
				mockReturnType: unnormalizedInstantiable.mockReturnType,
				customMockName: unnormalizedInstantiable.customMockName,
			)
			normalized.sourceFilePath = unnormalizedInstantiable.sourceFilePath
			return normalized
		}
		let generator = try DependencyTreeGenerator(
			importStatements: dependentModuleInfo.flatMap(\.imports) + resolvedAdditionalImportedModules.map { ImportStatement(moduleName: $0) } + module.imports,
			typeDescriptionToFulfillingInstantiableMap: resolveSafeDIFulfilledTypes(
				instantiables: normalizedInstantiables,
			),
		)
		if let moduleInfoOutput {
			try JSONEncoder().encode(module).write(toPath: moduleInfoOutput)
		}

		if let resolvedSwiftManifest {
			let manifest = try JSONDecoder().decode(
				SafeDIToolManifest.self,
				from: Data(contentsOf: resolvedSwiftManifest.asFileURL),
			)

			let filesWithUnexpectedNodes = dependentModuleInfo.compactMap(\.filesWithUnexpectedNodes).flatMap(\.self) + (module.filesWithUnexpectedNodes ?? [])
			if !filesWithUnexpectedNodes.isEmpty {
				// Write error to all manifest output files (dependency tree AND mock).
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
					// In combined-output mode the build system only
					// declared this one path, so route the `#error(…)`
					// here instead of the manifest's per-entry paths.
					try errorContent.write(toPath: combinedOutput)
				} else {
					for entry in manifest.dependencyTreeGeneration {
						try errorContent.write(toPath: entry.outputFilePath)
					}
					for entry in manifest.mockGeneration {
						try errorContent.write(toPath: entry.outputFilePath)
					}
				}
			} else {
				let generatedRoots = try await generator.generatePerRootCodeTrees()
				let fileHeader = await generator.fileHeader

				// Build a map from source file path → extension code(s).
				var sourceFileToExtensions = [String: [String]]()
				for root in generatedRoots {
					if let sourceFilePath = root.sourceFilePath, !root.code.isEmpty {
						sourceFileToExtensions[sourceFilePath, default: []].append(root.code)
					}
				}

				// Validate manifest and roots are in sync before writing any output.
				// Only check current-module roots (not dependent-module roots, which
				// don't belong in this target's manifest).
				let currentModuleRootSourceFiles = Set(
					module.instantiables.filter(\.isRoot).compactMap(\.sourceFilePath),
				)
				let manifestInputPaths = Set(manifest.dependencyTreeGeneration.map(\.inputFilePath))
				for entry in manifest.dependencyTreeGeneration {
					guard currentModuleRootSourceFiles.contains(entry.inputFilePath) else {
						throw ManifestError.noRootFound(inputPath: entry.inputFilePath)
					}
				}
				for sourceFile in currentModuleRootSourceFiles {
					if !manifestInputPaths.contains(sourceFile) {
						throw ManifestError.rootNotInManifest(sourceFilePath: sourceFile)
					}
				}

				// Accumulates body blocks for `--combined-output`. One
				// shared fileHeader is emitted at the top of the
				// combined file; each entry's body (sans its own
				// duplicate header) is appended in discovery order —
				// roots first, then mocks, then mock configuration —
				// so the output layout mirrors what a reader would see
				// if they concatenated the per-file outputs by hand.
				var combinedOutputBodies: [String] = []

				// Write dependency tree output files.
				for entry in manifest.dependencyTreeGeneration {
					let body = sourceFileToExtensions[entry.inputFilePath]?.sorted().joined(separator: "\n\n") ?? ""
					if combinedOutput != nil {
						if !body.isEmpty {
							combinedOutputBodies.append(body)
						}
					} else {
						let code = body.isEmpty ? fileHeader : fileHeader + body
						// Only update the file if the content has changed.
						let existingContent = try? String(contentsOfFile: entry.outputFilePath, encoding: .utf8)
						if existingContent != code {
							try code.write(toPath: entry.outputFilePath)
						}
					}
				}

				// Generate and write mock output files.
				if !manifest.mockGeneration.isEmpty {
					// Use the config's mockConditionalCompilation if a config exists;
					// default to "DEBUG" when no config exists (per-type opt-in without config).
					let mockConditionalCompilation: String? = if let sourceConfiguration {
						sourceConfiguration.mockConditionalCompilation
					} else {
						"DEBUG"
					}
					let currentModuleSourceFilePaths = Set(manifest.mockGeneration.map(\.inputFilePath))
					let mockResult = try await generator.generateMockCode(
						mockConditionalCompilation: mockConditionalCompilation,
						currentModuleSourceFilePaths: currentModuleSourceFilePaths,
						additionalMocksToGenerate: Set(manifest.additionalMocksToGenerate),
					)

					var sourceFileToMockExtensions = [String: [String]]()
					var typeNameToMockExtensions = [String: [String]]()
					for mock in mockResult.generatedRoots {
						if let sourceFilePath = mock.sourceFilePath {
							sourceFileToMockExtensions[sourceFilePath, default: []].append(mock.code)
						}
						typeNameToMockExtensions[mock.typeDescription.asSource, default: []].append(mock.code)
					}

					let additionalMockTypeNames = Set(manifest.additionalMocksToGenerate)
					for entry in manifest.mockGeneration {
						let extensions: [String]? = if additionalMockTypeNames.contains(entry.inputFilePath) {
							// Additional mock: inputFilePath is the type name.
							typeNameToMockExtensions[entry.inputFilePath]
						} else {
							sourceFileToMockExtensions[entry.inputFilePath]
						}
						let body = extensions?.sorted().joined(separator: "\n\n") ?? ""
						if combinedOutput != nil {
							if !body.isEmpty {
								combinedOutputBodies.append(body)
							}
						} else {
							let code = fileHeader + body
							let existingContent = try? String(contentsOfFile: entry.outputFilePath, encoding: .utf8)
							if existingContent != code {
								try code.write(toPath: entry.outputFilePath)
							}
						}
					}

					// Write shared mock configuration file.
					// Always write the file when the path is set, even if empty,
					// because the build system expects the declared output to exist.
					if let mockConfigurationOutputFilePath = manifest.mockConfigurationOutputFilePath {
						let mockConfigurationBody = mockResult.mockConfigurationCode ?? ""
						if combinedOutput != nil {
							if !mockConfigurationBody.isEmpty {
								combinedOutputBodies.append(mockConfigurationBody)
							}
						} else {
							let code = fileHeader + mockConfigurationBody
							let existingContent = try? String(contentsOfFile: mockConfigurationOutputFilePath, encoding: .utf8)
							if existingContent != code {
								try code.write(toPath: mockConfigurationOutputFilePath)
							}
						}
					}
				}

				if let combinedOutput {
					// One fileHeader at the top, then each body. An
					// empty module (no roots, no mocks) still writes
					// the header-only file so build systems whose
					// declared output is this path find it populated.
					let code = combinedOutputBodies.isEmpty
						? fileHeader
						: fileHeader + combinedOutputBodies.joined(separator: "\n\n")
					let existingContent = try? String(contentsOfFile: combinedOutput, encoding: .utf8)
					if existingContent != code {
						try code.write(toPath: combinedOutput)
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
	}

	// MARK: Private

	private enum ManifestError: Error, CustomStringConvertible {
		case noRootFound(inputPath: String)
		case rootNotInManifest(sourceFilePath: String)

		var description: String {
			switch self {
			case let .noRootFound(inputPath):
				"Manifest lists '\(inputPath)' as containing a dependency tree root, but no @\(InstantiableVisitor.macroName)(isRoot: true) was found in that file."
			case let .rootNotInManifest(sourceFilePath):
				"Found @\(InstantiableVisitor.macroName)(isRoot: true) in '\(sourceFilePath)', but this file is not listed in the manifest’s dependencyTreeGeneration. Add it to the manifest or remove the isRoot annotation."
			}
		}
	}

	private func findGenerateSwiftFiles() async throws -> Set<String> {
		try await findGenerateSwiftFiles(additionalDirectories: include)
	}

	private func findGenerateSwiftFiles(additionalDirectories: [String]) async throws -> Set<String> {
		var swiftFiles = try await findSwiftFiles(inDirectories: additionalDirectories)
		if let swiftSourcesFilePath {
			let sourcesFromFile = try String(contentsOfFile: swiftSourcesFilePath, encoding: .utf8)
				.components(separatedBy: CharacterSet(arrayLiteral: ","))
				.removingEmpty()
			swiftFiles.formUnion(sourcesFromFile)
		}
		return swiftFiles
	}

	/// Loads the parsed `ModuleInfo` for this module. When scan ran earlier
	/// (plugin-setup subprocess of this same build), it persisted the parsed
	/// result alongside the manifest; reading that JSON is dramatically
	/// cheaper than re-parsing every Swift file through SwiftParser.
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
	/// The cache is also bypassed when any source file's mtime is newer
	/// than the cache file — e.g. a manual `generate` invocation after a
	/// source edit without rerunning `scan` would otherwise consume stale
	/// parse results and emit stale code. Plugin-driven builds rerun
	/// `scan` every build, so this check is effectively free on the fast
	/// path.
	///
	/// Decode failures (truncated file from an interrupted write,
	/// cross-version schema drift, etc.) fall through to a fresh parse
	/// rather than aborting the build — the cache is an optimization
	/// sidecar, not a correctness requirement.
	private func parsedModule() async throws -> (module: ModuleInfo, isFromCache: Bool) {
		if include.isEmpty,
		   let swiftManifest,
		   let cached = try await loadCachedModuleInfo(manifestPath: swiftManifest)
		{
			(cached, true)
		} else {
			try await (parseSwiftFiles(findGenerateSwiftFiles()), false)
		}
	}

	private func loadCachedModuleInfo(manifestPath: String) async throws -> ModuleInfo? {
		let cacheURL = scannedModuleInfoURL(forManifestPath: manifestPath)
		let fileManager = FileManager.default
		guard let cacheAttributes = try? fileManager.attributesOfItem(atPath: cacheURL.path),
		      let cacheModifiedAt = cacheAttributes[.modificationDate] as? Date
		else { return nil }

		// Treat decode failures as cache misses, not hard errors — the
		// cache may have been truncated by an interrupted write or carry
		// an older schema that a newer SafeDITool can no longer read.
		guard let data = try? Data(contentsOf: cacheURL),
		      let cached = try? JSONDecoder().decode(CachedScannedModuleInfo.self, from: data)
		else { return nil }

		// Bypass the cache if the current CSV's file set differs from what
		// scan observed — a custom script could reuse a manifest path with a
		// changed CSV, in which case the cached ModuleInfo is for the wrong
		// input set. Plugin-driven builds always pair scan+generate with the
		// same CSV, so this check is effectively free on the fast path.
		//
		// Failure to read the CSV also invalidates: we can't prove the
		// inputs match, and the fresh-parse fallback will surface a clearer
		// error (missing file) than silently reusing stale parse results.
		if let swiftSourcesFilePath {
			guard let currentCSVContent = try? String(contentsOfFile: swiftSourcesFilePath, encoding: .utf8) else {
				return nil
			}
			let currentCSVPaths = Set(
				currentCSVContent
					.components(separatedBy: CharacterSet(arrayLiteral: ","))
					.removingEmpty(),
			)
			guard currentCSVPaths == Set(cached.csvInputPaths) else {
				return nil
			}
		}

		// Bypass the cache if new Swift files have been added to any of the
		// `additionalDirectoriesToInclude` directories since scan ran. The
		// mtime check below only catches files scan already knew about — it
		// would miss a newly-added file whose path doesn't appear in
		// `cached.scannedInputPaths`.
		if !cached.additionalDirectories.isEmpty {
			let currentAdditionalFiles = await (try? findSwiftFiles(inDirectories: cached.additionalDirectories)) ?? []
			let currentAdditionalAbsolute = Set(currentAdditionalFiles.map { filePath in
				URL(fileURLWithPath: filePath).standardizedFileURL.path
			})
			guard currentAdditionalAbsolute == Set(cached.additionalInputAbsolutePaths) else {
				return nil
			}
		}

		// Bypass the cache if any input file scan observed has changed
		// since the cache was written — newer mtime OR missing-from-disk
		// both invalidate. We check every path scan parsed (including
		// files reached through `#SafeDIConfiguration.additionalDirectoriesToInclude`,
		// which don't appear in `findGenerateSwiftFiles()`'s output).
		guard !cached.scannedInputPaths.contains(where: { filePath in
			guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
			      let modifiedAt = attributes[.modificationDate] as? Date
			else {
				// File missing or unreadable — the scan-observed input set
				// doesn't match disk, so a fresh parse is safer than
				// trusting stale parse results.
				return true
			}
			return modifiedAt > cacheModifiedAt
		}) else {
			return nil
		}
		return cached.moduleInfo
	}

	private var moduleInfoURLs: Set<URL> {
		get throws {
			if let dependentModuleInfoFilePath {
				try .init(
					String(contentsOfFile: dependentModuleInfoFilePath, encoding: .utf8)
						.components(separatedBy: CharacterSet(arrayLiteral: ","))
						.removingEmpty()
						.map(\.asFileURL),
				)
			} else {
				[]
			}
		}
	}

	private func loadSafeDIModuleInfo() async throws -> [ModuleInfo] {
		try await withThrowingTaskGroup(
			of: ModuleInfo.self,
			returning: [ModuleInfo].self,
		) { taskGroup in
			let moduleInfoURLs = try moduleInfoURLs
			guard !moduleInfoURLs.isEmpty else { return [] }
			for moduleInfoURL in moduleInfoURLs {
				taskGroup.addTask {
					try JSONDecoder().decode(
						ModuleInfo.self,
						from: Data(contentsOf: moduleInfoURL),
					)
				}
			}
			var allModuleInfo = [ModuleInfo]()
			for try await moduleInfo in taskGroup {
				allModuleInfo.append(moduleInfo)
			}
			return allModuleInfo
		}
	}

	private func resolveSafeDIFulfilledTypes(instantiables: [Instantiable]) throws -> [TypeDescription: Instantiable] {
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
						throw CollectInstantiablesError.duplicateMockProvider(instantiableType.asSource)
					case (false, true):
						guard !typesWithMockOnlyMerge.contains(instantiableType) else {
							throw CollectInstantiablesError.duplicateMockProvider(instantiableType.asSource)
						}
						typesWithMockOnlyMerge.insert(instantiableType)
						if existing.concreteInstantiable == instantiable.concreteInstantiable {
							// Same concrete type: two hand-written mocks is ambiguous.
							guard existing.mockInitializer == nil else {
								throw CollectInstantiablesError.duplicateMockProvider(instantiableType.asSource)
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
								throw CollectInstantiablesError.duplicateMockProvider(instantiableType.asSource)
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
						throw CollectInstantiablesError.foundDuplicateInstantiable(instantiableType.asSource)
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

	private enum CollectInstantiablesError: Error, CustomStringConvertible {
		case foundDuplicateInstantiable(String)
		case duplicateMockProvider(String)

		var description: String {
			switch self {
			case let .foundDuplicateInstantiable(duplicateInstantiable):
				"@\(InstantiableVisitor.macroName)-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `\(duplicateInstantiable)`"
			case let .duplicateMockProvider(duplicateInstantiable):
				"Found multiple hand-written mock providers for `\(duplicateInstantiable)`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both."
			}
		}
	}
}
