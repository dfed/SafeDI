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
struct Scan: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Scan Swift files to discover SafeDI roots and mocks, producing a manifest for code generation.",
	)

	@Option(help: "A path to a CSV file containing paths of Swift files to scan.") var inputSourcesFile: String

	@Option(help: "The root directory of the project, used to compute relative paths.") var projectRoot: String

	@Option(help: "The directory where generated output files will be written.") var outputDirectory: String

	@Option(help: "The path where the manifest JSON file will be written.") var manifestFile: String

	@Option(parsing: .upToNextOption, help: "Swift file paths scoped to the current target for mock generation. When provided, only these files are scanned for generateMock and #SafeDIConfiguration.") var mockScopedFiles: [String] = []

	func run() async throws {
		let projectRootURL = projectRoot.asFileURL
		let outputDirectoryURL = outputDirectory.asFileURL

		// Read CSV and resolve file paths relative to project root.
		let inputFilePaths = try String(contentsOfFile: inputSourcesFile, encoding: .utf8)
			.components(separatedBy: CharacterSet(arrayLiteral: ","))
			.removingEmpty()

		let directoryBaseURL = if projectRootURL.hasDirectoryPath {
			projectRootURL
		} else {
			projectRootURL.appendingPathComponent("", isDirectory: true)
		}

		let allSwiftFiles = inputFilePaths.map {
			URL(fileURLWithPath: $0, relativeTo: directoryBaseURL).standardizedFileURL
		}

		// Parse all files to find roots.
		let allFilePaths = Set(allSwiftFiles.map(\.relativePath))
		let allModuleInfo = try await parseSwiftFiles(allFilePaths)

		// Determine which files are scoped for mock scanning.
		let filesForMockScan: [URL] = if mockScopedFiles.isEmpty {
			allSwiftFiles
		} else {
			mockScopedFiles.map {
				URL(fileURLWithPath: $0, relativeTo: directoryBaseURL).standardizedFileURL
			}
		}
		let mockScopedFilePaths = Set(filesForMockScan.map(\.relativePath))

		// Parse mock-scoped files for configuration and mock info.
		let mockScopedModuleInfo = try await parseSwiftFiles(mockScopedFilePaths)

		// Find configuration from the scoped files (first one only, matching current behavior).
		let configuration = mockScopedModuleInfo.configurations.first

		// Discover additional directories from configuration.
		var additionalInputFiles = [String]()
		var combinedModuleInfo = allModuleInfo
		if let configuration, !configuration.additionalDirectoriesToInclude.isEmpty {
			let additionalFiles = try await findSwiftFiles(inDirectories: configuration.additionalDirectoriesToInclude)
			let additionalModuleInfo = try await parseSwiftFiles(additionalFiles)

			// Record the additional files for the plugin to use as build inputs.
			additionalInputFiles = additionalFiles.sorted().map { filePath in
				URL(fileURLWithPath: filePath, relativeTo: directoryBaseURL).standardizedFileURL.path
			}

			// Merge additional roots/mocks into the combined results.
			combinedModuleInfo = ModuleInfo(
				imports: allModuleInfo.imports + additionalModuleInfo.imports,
				instantiables: allModuleInfo.instantiables + additionalModuleInfo.instantiables,
				configurations: allModuleInfo.configurations,
				filesWithUnexpectedNodes: allModuleInfo.filesWithUnexpectedNodes.map { $0 + (additionalModuleInfo.filesWithUnexpectedNodes ?? []) } ?? additionalModuleInfo.filesWithUnexpectedNodes,
			)
		}

		// Collect root files and compute output file names.
		let rootInstantiables = combinedModuleInfo.instantiables.filter(\.isRoot)
		let rootFileURLs = rootInstantiables.compactMap { instantiable -> URL? in
			guard let sourceFilePath = instantiable.sourceFilePath else { return nil }
			return URL(fileURLWithPath: sourceFilePath, relativeTo: directoryBaseURL).standardizedFileURL
		}
		let sortedRootFileURLs = rootFileURLs.sorted {
			relativePath(for: $0, relativeTo: projectRootURL) < relativePath(for: $1, relativeTo: projectRootURL)
		}
		// Deduplicate: multiple roots in the same file should only produce one output entry.
		let uniqueRootFileURLs = sortedRootFileURLs.reduce(into: [URL]()) { result, url in
			if result.last != url {
				result.append(url)
			}
		}
		let rootOutputNames = outputFileNames(for: uniqueRootFileURLs, relativeTo: projectRootURL)

		// Collect mock files (only from scoped files) and compute output file names.
		let mockInstantiables = mockScopedModuleInfo.instantiables.filter(\.generateMock)
		let mockFileURLs = mockInstantiables.compactMap { instantiable -> URL? in
			guard let sourceFilePath = instantiable.sourceFilePath else { return nil }
			return URL(fileURLWithPath: sourceFilePath, relativeTo: directoryBaseURL).standardizedFileURL
		}
		let sortedMockFileURLs = mockFileURLs.sorted {
			relativePath(for: $0, relativeTo: projectRootURL) < relativePath(for: $1, relativeTo: projectRootURL)
		}
		let uniqueMockFileURLs = sortedMockFileURLs.reduce(into: [URL]()) { result, url in
			if result.last != url {
				result.append(url)
			}
		}
		let mockOutputNames = mockOutputFileNames(for: uniqueMockFileURLs, relativeTo: projectRootURL)

		// Extract additional mocks to generate from configuration.
		let additionalMocksToGenerate = configuration?.additionalMocksToGenerate ?? []

		// Build additional mock output entries.
		let additionalMockEntries: [SafeDIToolManifest.InputOutputMap] = additionalMocksToGenerate.map { typeName in
			.init(
				inputFilePath: typeName,
				outputFilePath: outputDirectoryURL
					.appendingPathComponent("\(typeName)+SafeDIMock.swift")
					.path,
			)
		}

		// Compute configuration file paths (relative to project root, matching Generate's expectations).
		let configurationFilePaths = mockScopedModuleInfo.configurations.compactMap(\.sourceFilePath).map { path in
			relativePath(for: URL(fileURLWithPath: path, relativeTo: directoryBaseURL).standardizedFileURL, relativeTo: projectRootURL)
		}

		// Determine mock configuration output file path.
		let hasMockEntries = !uniqueMockFileURLs.isEmpty || !additionalMockEntries.isEmpty
		let mockConfigurationOutputFilePath: String? = if hasMockEntries {
			outputDirectoryURL
				.appendingPathComponent("SafeDIMockConfiguration.swift")
				.path
		} else {
			nil
		}

		// Build and write the manifest.
		let manifest = SafeDIToolManifest(
			dependencyTreeGeneration: zip(uniqueRootFileURLs, rootOutputNames).map { inputURL, outputFileName in
				.init(
					inputFilePath: relativePath(for: inputURL, relativeTo: projectRootURL),
					outputFilePath: outputDirectoryURL
						.appendingPathComponent(outputFileName)
						.path,
				)
			},
			mockGeneration: zip(uniqueMockFileURLs, mockOutputNames).map { inputURL, outputFileName in
				.init(
					inputFilePath: relativePath(for: inputURL, relativeTo: projectRootURL),
					outputFilePath: outputDirectoryURL
						.appendingPathComponent(outputFileName)
						.path,
				)
			} + additionalMockEntries,
			configurationFilePaths: configurationFilePaths,
			mockConfigurationOutputFilePath: mockConfigurationOutputFilePath,
			additionalMocksToGenerate: additionalMocksToGenerate,
			additionalInputFiles: additionalInputFiles,
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		try encoder.encode(manifest).write(to: manifestFile.asFileURL)
	}
}
