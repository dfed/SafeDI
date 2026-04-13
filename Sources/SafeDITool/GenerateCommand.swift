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

	@Option(help: "The desired output location of the DOT file expressing the Swift dependency injection tree. Only include this option when running on a project’s root module.") var dotFileOutput: String?

	// MARK: Internal

	func run() async throws {
		if swiftSourcesFilePath == nil, include.isEmpty {
			throw ValidationError("Must provide 'swift-sources-file-path' or '--include'.")
		}

		// When --output-directory is provided without --swift-manifest, run an
		// inline scan to discover roots/mocks and build the manifest automatically.
		var resolvedSwiftManifest = swiftManifest
		if resolvedSwiftManifest == nil, let outputDirectory {
			guard let swiftSourcesFilePath else {
				throw ValidationError("--output-directory requires 'swift-sources-file-path'.")
			}
			let manifestPath = (outputDirectory as NSString).appendingPathComponent("SafeDIManifest.json")
			try await performScan(
				inputSourcesFile: swiftSourcesFilePath,
				projectRoot: FileManager.default.currentDirectoryPath,
				outputDirectory: outputDirectory,
				manifestFile: manifestPath,
				mockScopedFiles: mockScopedFiles,
			)
			resolvedSwiftManifest = manifestPath
		}

		let (dependentModuleInfo, initialModule) = try await (
			loadSafeDIModuleInfo(),
			parsedModule(),
		)

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
		// find and parse swift files in those directories and merge with initial results.
		let module: ModuleInfo
		if let sourceConfiguration, !sourceConfiguration.additionalDirectoriesToInclude.isEmpty {
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
				for entry in manifest.dependencyTreeGeneration {
					try errorContent.write(toPath: entry.outputFilePath)
				}
				for entry in manifest.mockGeneration {
					try errorContent.write(toPath: entry.outputFilePath)
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

				// Write dependency tree output files.
				for entry in manifest.dependencyTreeGeneration {
					let code: String = if let extensions = sourceFileToExtensions[entry.inputFilePath] {
						fileHeader + extensions.sorted().joined(separator: "\n\n")
					} else {
						fileHeader
					}
					// Only update the file if the content has changed.
					let existingContent = try? String(contentsOfFile: entry.outputFilePath, encoding: .utf8)
					if existingContent != code {
						try code.write(toPath: entry.outputFilePath)
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
						let code = fileHeader + (extensions?.sorted().joined(separator: "\n\n") ?? "")
						let existingContent = try? String(contentsOfFile: entry.outputFilePath, encoding: .utf8)
						if existingContent != code {
							try code.write(toPath: entry.outputFilePath)
						}
					}

					// Write shared mock configuration file.
					// Always write the file when the path is set, even if empty,
					// because the build system expects the declared output to exist.
					if let mockConfigurationOutputFilePath = manifest.mockConfigurationOutputFilePath {
						let code = fileHeader + (mockResult.mockConfigurationCode ?? "")
						let existingContent = try? String(contentsOfFile: mockConfigurationOutputFilePath, encoding: .utf8)
						if existingContent != code {
							try code.write(toPath: mockConfigurationOutputFilePath)
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

	private func parsedModule() async throws -> ModuleInfo {
		try await parseSwiftFiles(findGenerateSwiftFiles())
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
						if typesWithMockOnlyMerge.contains(instantiableType) {
							throw CollectInstantiablesError.duplicateMockProvider(instantiableType.asSource)
						}
						typesWithMockOnlyMerge.insert(instantiableType)
						// Keep existing production info. If it lacks a mock, merge
						// in mock info from the mockOnly type.
						let existingHasMock = existing.generateMock || existing.mockInitializer != nil
						if !existingHasMock {
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = existing.mergedWithMockProvider(instantiable)
						}
					case (true, false):
						// The existing entry is mockOnly — record it so a second
						// mockOnly for the same type is still rejected.
						typesWithMockOnlyMerge.insert(instantiableType)
						// Replace with production info. If it lacks a mock, merge
						// in mock info from the existing mockOnly type.
						let newHasMock = instantiable.generateMock || instantiable.mockInitializer != nil
						if newHasMock {
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
						} else {
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable.mergedWithMockProvider(existing)
						}
					case (false, false):
						throw CollectInstantiablesError.foundDuplicateInstantiable(instantiableType.asSource)
					}
				} else {
					typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
				}
			}
		}
		// Propagate mock state so all entries with the same concreteInstantiable
		// are consistent. Two directions:
		// 1. Entries missing mock info get it from a merged mockOnly provider.
		// 2. Stale mockOnly entries get their mock info cleared when the production
		//    type has generateMock (so they don't pollute forwardedParameterMockDefaults).
		var mockProviderByConcreteType = [TypeDescription: Instantiable]()
		var generateMockConcreteTypes = Set<TypeDescription>()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			if instantiable.mockInitializer != nil {
				mockProviderByConcreteType[instantiable.concreteInstantiable] = instantiable
			}
			if instantiable.generateMock {
				generateMockConcreteTypes.insert(instantiable.concreteInstantiable)
			}
		}
		for (typeDescription, instantiable) in typeDescriptionToFulfillingInstantiableMap {
			let concreteType = instantiable.concreteInstantiable
			if instantiable.mockInitializer == nil,
			   !instantiable.generateMock,
			   let mockProvider = mockProviderByConcreteType[concreteType]
			{
				// Propagate mock info onto stale entries missing it.
				typeDescriptionToFulfillingInstantiableMap[typeDescription] = instantiable.mergedWithMockProvider(mockProvider)
			} else if instantiable.mockOnly,
			          instantiable.mockInitializer != nil,
			          generateMockConcreteTypes.contains(concreteType)
			{
				// Clear stale mockOnly mock info when the production type has
				// generateMock — the generated mock takes priority.
				var cleared = instantiable
				cleared.mockInitializer = nil
				cleared.mockReturnType = nil
				cleared.customMockName = nil
				typeDescriptionToFulfillingInstantiableMap[typeDescription] = cleared
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
				"Found multiple `mockOnly: true` declarations for `\(duplicateInstantiable)`. A type can have at most one `mockOnly` declaration."
			}
		}
	}
}
