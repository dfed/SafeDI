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
import SwiftParser

@main
struct SafeDITool: AsyncParsableCommand {
	// MARK: Arguments

	@Argument(help: "A path to a CSV file containing paths of Swift files to parse.") var swiftSourcesFilePath: String?

	@Flag(name: .customLong("version"), help: "Print the SafeDITool version and exit.") var showVersion = false

	@Option(parsing: .upToNextOption, help: "Directories containing Swift files to include, relative to the executing directory.") var include: [String] = []

	@Option(parsing: .upToNextOption, help: "The names of modules to import in the generated dependency tree. This list is in addition to the import statements found in files that declare @Instantiable types.") var additionalImportedModules: [String] = []

	@Option(help: "The desired output location of a file a SafeDI representation of this module. Only include this option when running on a project‘s non-root module. Must have a `.safedi` suffix.") var moduleInfoOutput: String?

	@Option(help: "A path to a CSV file containing paths of SafeDI representations of other modules to parse.") var dependentModuleInfoFilePath: String?

	@Option(help: "A path to a JSON manifest file describing the desired Swift output files. The manifest maps input file paths to output file paths. See SafeDIToolManifest for the expected format.") var swiftManifest: String?

	@Option(help: "The desired output location of the DOT file expressing the Swift dependency injection tree. Only include this option when running on a project‘s root module.") var dotFileOutput: String?

	// MARK: Internal

	static var currentVersion: String {
		"2.0.0"
	}

	func run() async throws {
		guard !showVersion else {
			print(Self.currentVersion)
			return
		}

		if swiftSourcesFilePath == nil, include.isEmpty {
			throw ValidationError("Must provide 'swift-sources-file-path' or '--include'.")
		}

		let (dependentModuleInfo, initialModule) = try await (
			loadSafeDIModuleInfo(),
			parsedModule(),
		)

		// In multi-module builds, the CSV includes all modules' files, so multiple
		// configs may be present. Scope to the current module using the manifest's
		// configurationFilePaths (which lists only this target's own config files).
		let currentModuleConfigurations: [SafeDIConfiguration]
		if let swiftManifest {
			let manifest = try JSONDecoder().decode(
				SafeDIToolManifest.self,
				from: Data(contentsOf: swiftManifest.asFileURL),
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
			throw ValidationError("Found \(currentModuleConfigurations.count) @\(SafeDIConfigurationVisitor.macroName) declarations in this module. Each module must have at most one @\(SafeDIConfigurationVisitor.macroName). Found in:\n\t\(configPaths)")
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
			let additionalFiles = try await Self.findSwiftFiles(inDirectories: sourceConfiguration.additionalDirectoriesToInclude)
			let additionalModule = try await Self.parseSwiftFiles(additionalFiles)
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
				mockInitializer: unnormalizedInstantiable.mockInitializer,
			)
			normalized.sourceFilePath = unnormalizedInstantiable.sourceFilePath
			normalized.imports = unnormalizedInstantiable.imports
			return normalized
		}
		let globalImportStatements = dependentModuleInfo.flatMap(\.imports) + resolvedAdditionalImportedModules.map { ImportStatement(moduleName: $0) }
		let generator = try DependencyTreeGenerator(
			importStatements: globalImportStatements + module.imports,
			globalImportStatements: globalImportStatements,
			typeDescriptionToFulfillingInstantiableMap: resolveSafeDIFulfilledTypes(
				instantiables: normalizedInstantiables,
			),
		)
		if let moduleInfoOutput {
			try JSONEncoder().encode(module).write(toPath: moduleInfoOutput)
		}

		if let swiftManifest {
			let manifest = try JSONDecoder().decode(
				SafeDIToolManifest.self,
				from: Data(contentsOf: swiftManifest.asFileURL),
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
				let generateMocks = sourceConfiguration?.generateMocks ?? false
				if !manifest.mockGeneration.isEmpty {
					if generateMocks {
						// sourceConfiguration is guaranteed non-nil here because
						// generateMocks defaults to false when no configuration exists.
						let mockConditionalCompilation = sourceConfiguration.flatMap(\.mockConditionalCompilation)
						let currentModuleSourceFilePaths = Set(manifest.mockGeneration.map(\.inputFilePath))
						let generatedMocks = try await generator.generateMockCode(
							mockConditionalCompilation: mockConditionalCompilation,
							currentModuleSourceFilePaths: currentModuleSourceFilePaths,
						)

						var sourceFileToMockInfo = [String: (imports: Set<ImportStatement>, extensions: [String])]()
						for mock in generatedMocks {
							if let sourceFilePath = mock.sourceFilePath {
								var info = sourceFileToMockInfo[sourceFilePath, default: (imports: [], extensions: [])]
								info.imports.formUnion(mock.imports)
								info.extensions.append(mock.code)
								sourceFileToMockInfo[sourceFilePath] = info
							}
						}

						for entry in manifest.mockGeneration {
							let info = sourceFileToMockInfo[entry.inputFilePath]
							let mockHeader = await generator.mockFileHeader(perTypeImports: info?.imports ?? [])
							let code = mockHeader + (info?.extensions.sorted().joined(separator: "\n\n") ?? "")
							let existingContent = try? String(contentsOfFile: entry.outputFilePath, encoding: .utf8)
							if existingContent != code {
								try code.write(toPath: entry.outputFilePath)
							}
						}
					} else {
						// generateMocks is false — write empty files so build system has its expected outputs.
						let emptyMockHeader = await generator.mockFileHeader(perTypeImports: [])
						for entry in manifest.mockGeneration {
							let existingContent = try? String(contentsOfFile: entry.outputFilePath, encoding: .utf8)
							if existingContent != emptyMockHeader {
								try emptyMockHeader.write(toPath: entry.outputFilePath)
							}
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

	private enum ManifestError: Error, CustomStringConvertible {
		case noRootFound(inputPath: String)
		case rootNotInManifest(sourceFilePath: String)

		var description: String {
			switch self {
			case let .noRootFound(inputPath):
				"Manifest lists '\(inputPath)' as containing a dependency tree root, but no @\(InstantiableVisitor.macroName)(isRoot: true) was found in that file."
			case let .rootNotInManifest(sourceFilePath):
				"Found @\(InstantiableVisitor.macroName)(isRoot: true) in '\(sourceFilePath)', but this file is not listed in the manifest's dependencyTreeGeneration. Add it to the manifest or remove the isRoot annotation."
			}
		}
	}

	struct ModuleInfo: Codable {
		let imports: [ImportStatement]
		let instantiables: [Instantiable]
		let configurations: [SafeDIConfiguration]
		let filesWithUnexpectedNodes: [String]?
	}

	@TaskLocal static var fileFinder: FileFinder = FileManager.default

	// MARK: Private

	private func findSwiftFiles() async throws -> Set<String> {
		try await findSwiftFiles(additionalDirectories: include)
	}

	private func findSwiftFiles(additionalDirectories: [String]) async throws -> Set<String> {
		var swiftFiles = try await Self.findSwiftFiles(inDirectories: additionalDirectories)
		if let swiftSourcesFilePath {
			let sourcesFromFile = try String(contentsOfFile: swiftSourcesFilePath, encoding: .utf8)
				.components(separatedBy: CharacterSet(arrayLiteral: ","))
				.removingEmpty()
			swiftFiles.formUnion(sourcesFromFile)
		}
		return swiftFiles
	}

	private static func findSwiftFiles(inDirectories directories: [String]) async throws -> Set<String> {
		try await withThrowingTaskGroup(
			of: [String].self,
			returning: Set<String>.self,
		) { taskGroup in
			for included in directories {
				taskGroup.addTask {
					let includedURL = included.asFileURL
					let includedFileEnumerator = Self.fileFinder
						.enumerator(
							at: includedURL,
							includingPropertiesForKeys: nil,
							options: [.skipsHiddenFiles],
							errorHandler: nil,
						)
					guard let files = includedFileEnumerator?.compactMap({ $0 as? URL }) else {
						struct CouldNotEnumerateDirectoryError: Error, CustomStringConvertible {
							let directory: String

							var description: String {
								"Could not create file enumerator for directory '\(directory)'"
							}
						}
						throw CouldNotEnumerateDirectoryError(directory: included)
					}
					return (files + [includedURL]).compactMap {
						if $0.pathExtension == "swift" {
							$0.standardizedFileURL.relativePath
						} else {
							nil
						}
					}
				}
			}

			var swiftFiles = Set<String>()
			for try await includedFiles in taskGroup {
				swiftFiles.formUnion(includedFiles)
			}

			return swiftFiles
		}
	}

	private static func parseSwiftFiles(_ filePaths: Set<String>) async throws -> ModuleInfo {
		try await withThrowingTaskGroup(
			of: (
				imports: [ImportStatement],
				instantiables: [Instantiable],
				configurations: [SafeDIConfiguration],
				encounteredUnexpectedNodeInFile: String?,
			)?.self,
			returning: ModuleInfo.self,
		) { taskGroup in
			var imports = [ImportStatement]()
			var instantiables = [Instantiable]()
			var configurations = [SafeDIConfiguration]()
			var filesWithUnexpectedNodes = [String]()
			for filePath in filePaths where !filePath.isEmpty {
				taskGroup.addTask {
					let content = try String(contentsOfFile: filePath, encoding: .utf8)
					let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
					let containsConfiguration = content.contains("@\(SafeDIConfigurationVisitor.macroName)")
					guard containsInstantiable || containsConfiguration else { return nil }
					let fileVisitor = FileVisitor()
					fileVisitor.walk(Parser.parse(source: content))
					guard !fileVisitor.instantiables.isEmpty
						|| !fileVisitor.configurations.isEmpty
						|| fileVisitor.encounteredUnexpectedNodesSyntax
					else { return nil }
					let instantiables = fileVisitor.instantiables.map {
						var instantiable = $0
						instantiable.sourceFilePath = filePath
						instantiable.imports = fileVisitor.imports
						return instantiable
					}
					let configurations = fileVisitor.configurations.map {
						var configuration = $0
						configuration.sourceFilePath = filePath
						return configuration
					}
					return (
						imports: fileVisitor.imports,
						instantiables: instantiables,
						configurations: configurations,
						encounteredUnexpectedNodeInFile: fileVisitor.encounteredUnexpectedNodesSyntax ? filePath : nil,
					)
				}
			}

			for try await fileInfo in taskGroup {
				if let fileInfo {
					imports.append(contentsOf: fileInfo.imports)
					instantiables.append(contentsOf: fileInfo.instantiables)
					configurations.append(contentsOf: fileInfo.configurations)
					if let filePath = fileInfo.encounteredUnexpectedNodeInFile {
						filesWithUnexpectedNodes.append(filePath)
					}
				}
			}

			return ModuleInfo(
				imports: imports,
				instantiables: instantiables,
				configurations: configurations,
				filesWithUnexpectedNodes: filesWithUnexpectedNodes.isEmpty ? nil : filesWithUnexpectedNodes,
			)
		}
	}

	private func parsedModule() async throws -> ModuleInfo {
		try await Self.parseSwiftFiles(findSwiftFiles())
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
		for instantiable in instantiables {
			for instantiableType in instantiable.instantiableTypes {
				if typeDescriptionToFulfillingInstantiableMap[instantiableType] != nil {
					throw CollectInstantiablesError.foundDuplicateInstantiable(instantiableType.asSource)
				}
				typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
			}
		}
		return typeDescriptionToFulfillingInstantiableMap
	}

	private enum CollectInstantiablesError: Error, CustomStringConvertible {
		case foundDuplicateInstantiable(String)

		var description: String {
			switch self {
			case let .foundDuplicateInstantiable(duplicateInstantiable):
				"@\(InstantiableVisitor.macroName)-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `\(duplicateInstantiable)`"
			}
		}
	}
}

extension Data {
	fileprivate func write(toPath filePath: String) throws {
		try write(to: filePath.asFileURL)
	}
}

extension String {
	fileprivate func write(toPath filePath: String) throws {
		try Data(utf8).write(toPath: filePath)
	}

	fileprivate var asFileURL: URL {
		#if os(Linux)
			return URL(fileURLWithPath: self)
		#else
			guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
				return URL(fileURLWithPath: self)
			}
			return URL(filePath: self)
		#endif
	}
}

protocol FileFinder: Sendable {
	func enumerator(
		at url: URL,
		includingPropertiesForKeys keys: [URLResourceKey]?,
		options mask: FileManager.DirectoryEnumerationOptions,
		errorHandler handler: ((URL, any Error) -> Bool)?,
	) -> FileManager.DirectoryEnumerator?
}

extension FileManager: FileFinder {}
extension FileManager: @retroactive @unchecked Sendable {
	// FileManager is thread safe:
	// https://developer.apple.com/documentation/foundation/nsfilemanager#1651181
}
