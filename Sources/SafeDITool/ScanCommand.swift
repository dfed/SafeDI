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

	@Option(parsing: .upToNextOption, help: "The compilation conditions that are active for this build, matching the compiler's -D flags. SafeDI declarations in `#if` blocks are scanned only when the block's condition evaluates to true. Conditions are recorded in the manifest so `generate` applies them too.") var activeCompilationConditions: [String] = []

	func run() async throws {
		try await performScan(
			inputSourcesFile: inputSourcesFile,
			projectRoot: projectRoot,
			outputDirectory: outputDirectory,
			manifestFile: manifestFile,
			mockScopedFiles: mockScopedFiles,
			activeCompilationConditions: Set(activeCompilationConditions),
		)
	}
}

/// Performs the scan operation, producing a manifest JSON file.
/// Shared by the `scan` subcommand and the `generate` subcommand's
/// `--output-directory` auto-scan mode.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func performScan(
	inputSourcesFile: String,
	projectRoot: String,
	outputDirectory: String,
	manifestFile: String,
	mockScopedFiles: [String] = [],
	activeCompilationConditions: Set<String> = [],
) async throws {
	let projectRootURL = projectRoot.asFileURL
	let outputDirectoryURL = outputDirectory.asFileURL

	// Read CSV and resolve file paths relative to project root.
	let inputFilePaths = try String(contentsOfFile: inputSourcesFile, encoding: .utf8)
		.parsedPathListCSV()

	let directoryBaseURL = projectRootURL.appendingPathComponent("", isDirectory: true)

	let allSwiftFiles = inputFilePaths.map {
		URL(fileURLWithPath: $0, relativeTo: directoryBaseURL).standardizedFileURL
	}
	let allFilePaths = Set(allSwiftFiles.map(\.relativePath))

	// Determine which files are scoped for mock scanning.
	let mockScopedFilePaths: Set<String> = if mockScopedFiles.isEmpty {
		allFilePaths
	} else {
		Set(mockScopedFiles.map {
			URL(fileURLWithPath: $0, relativeTo: directoryBaseURL).standardizedFileURL.relativePath
		})
	}

	// Parse all files once to find roots, mocks, and configurations. Only the
	// mock-scoped files can declare this module's configuration, which decides
	// how every file's `#if` blocks are evaluated, so they are searched for it first.
	let (parsedModule, fileScans) = try await parseModule(
		filePaths: allFilePaths,
		configurationFilePaths: mockScopedFilePaths,
		activeCompilationConditions: activeCompilationConditions,
	)
	let allModuleInfo = parsedModule.moduleInfo
	let evaluator = parsedModule.conditionalCompilationEvaluator

	// Filter the already-parsed results to the mock-scoped subset.
	let mockScopedInstantiables = allModuleInfo.instantiables.filter { instantiable in
		guard let sourceFilePath = instantiable.sourceFilePath else { return false }
		return mockScopedFilePaths.contains(sourceFilePath)
	}
	let mockScopedConfigurations = allModuleInfo.configurations.filter { configuration in
		guard let sourceFilePath = configuration.sourceFilePath else { return false }
		return mockScopedFilePaths.contains(sourceFilePath)
	}

	// The parse rejected more than one configuration among the scoped files.
	let configuration = parsedModule.configuration

	// Discover additional directories from configuration.
	var additionalInputFiles = [String]()
	var combinedModuleInfo = allModuleInfo
	var additionalFileScans = [FileScan]()
	if let configuration, !configuration.additionalDirectoriesToInclude.isEmpty {
		let additionalFiles = try await findSwiftFiles(inDirectories: configuration.additionalDirectoriesToInclude)

		// Record the additional files for the plugin to use as build inputs.
		additionalInputFiles = additionalFiles.sorted().map { filePath in
			URL(fileURLWithPath: filePath, relativeTo: directoryBaseURL).standardizedFileURL.path
		}

		// Exclude files already parsed via the CSV — re-parsing them would
		// produce duplicate `Instantiable` entries in `combinedModuleInfo`
		// and trip "multiple types fulfilling" validation downstream.
		let unparsedAdditionalFiles = additionalFiles.subtracting(allFilePaths)
		if !unparsedAdditionalFiles.isEmpty {
			additionalFileScans = try await parseSwiftFiles(unparsedAdditionalFiles, conditionalCompilation: evaluator)
			// Merge additional roots/mocks into the combined results.
			combinedModuleInfo = allModuleInfo.including(ModuleInfo(additionalFileScans))
		}
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
	let mockInstantiables = mockScopedInstantiables.filter(\.generateMock)
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
	let configurationFilePaths = mockScopedConfigurations.compactMap(\.sourceFilePath).map { path in
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
		activeCompilationConditions: activeCompilationConditions.sorted(),
		mockScopedFilePaths: mockScopedFilePaths.map { filePath in
			relativePath(for: URL(fileURLWithPath: filePath, relativeTo: directoryBaseURL).standardizedFileURL, relativeTo: projectRootURL)
		}.sorted(),
		acceptsBuildSettingCompilationConditions: true,
		projectRoot: projectRootURL.path,
	)

	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	try encoder.encode(manifest).write(to: manifestFile.asFileURL)

	// Also persist what each file contributed next to the manifest so `generate`
	// can skip re-parsing the same Swift files. Normalize each file's path
	// to project-relative form so the cached entries match both the
	// manifest's `inputFilePath` (also project-relative) and what Generate
	// would compute when parsing fresh from the same CSV.
	func normalized(_ fileScan: FileScan) -> FileScan {
		fileScan.relocated(to: relativePath(
			for: URL(fileURLWithPath: fileScan.path, relativeTo: directoryBaseURL).standardizedFileURL,
			relativeTo: projectRootURL,
		))
	}
	func cached(_ fileScan: FileScan) -> CachedFileScan {
		CachedFileScan(scannedPath: fileScan.path, fileScan: normalized(fileScan))
	}
	// Every path scan parsed for this module — CSV inputs plus any files
	// reached through `#SafeDIConfiguration.additionalDirectoriesToInclude`.
	// `generate` uses this list to validate cache freshness against the
	// exact file set `scan` observed, so edits to additional-directory
	// files correctly invalidate the cache too.
	//
	// Normalized to absolute paths so `generate`'s freshness check works
	// regardless of its CWD — `FileManager.attributesOfItem(atPath:)`
	// resolves relative paths against the process's CWD, which would
	// silently fail and invalidate the cache if `generate` runs from a
	// different directory than `scan`.
	let absoluteCSVPaths = allFilePaths.map { filePath in
		URL(fileURLWithPath: filePath, relativeTo: directoryBaseURL).standardizedFileURL.path
	}.sorted()
	let allScannedFilePaths = (Set(absoluteCSVPaths).union(
		// `additionalInputFiles` is already normalized to `.standardizedFileURL.path`.
		Set(additionalInputFiles),
	)).sorted()
	let additionalDirectories = configuration?.additionalDirectoriesToInclude.map { directory in
		URL(fileURLWithPath: directory, relativeTo: directoryBaseURL).standardizedFileURL.path
	}.sorted() ?? []
	let cached = CachedScannedModuleInfo(
		moduleInfo: ModuleInfo(fileScans.filter { !$0.consultsCompilationConditions }.map(normalized)),
		conditionSensitiveFileScans: fileScans.filter(\.consultsCompilationConditions).map(cached),
		additionalModuleInfo: ModuleInfo(additionalFileScans.filter { !$0.consultsCompilationConditions }.map(normalized)),
		additionalConditionSensitiveFileScans: additionalFileScans.filter(\.consultsCompilationConditions).map(cached),
		projectRoot: projectRootURL.path,
		scannedInputPaths: allScannedFilePaths,
		csvInputPaths: inputFilePaths.sorted(),
		additionalInputAbsolutePaths: additionalInputFiles.sorted(),
		additionalDirectories: additionalDirectories,
		activeCompilationConditions: activeCompilationConditions.sorted(),
	)
	let scannedModuleInfoURL = scannedModuleInfoURL(forManifestPath: manifestFile)
	// Cache write is best-effort. A full disk or other transient FS
	// failure shouldn't block the build — `generate` always falls back
	// to a fresh parse when the cache is missing or can't be decoded.
	// Fresh encoder rather than reusing the manifest's — the cache is
	// machine-read only, so the `.sortedKeys` formatting the manifest
	// needs for determinism isn't load-bearing here.
	try? JSONEncoder().encode(cached).write(to: scannedModuleInfoURL)
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SafeDIToolManifest {
	/// The members of `inputFilePaths` that are this module's configuration files.
	/// Input paths are resolved the way scan resolved them before matching. Resolving a path is
	/// far costlier than comparing its suffix, and the inputs are every file of every module the
	/// target depends on, so only an input that ends in a configuration file's name is resolved;
	/// resolving a path never changes its file name.
	func configurationFilePaths(among inputFilePaths: Set<String>) -> Set<String> {
		let configurationFileNames = configurationFilePaths.map { ($0 as NSString).lastPathComponent }
		return inputFilePaths.filter { inputFilePath in
			configurationFileNames.contains(where: inputFilePath.hasSuffix)
				&& configurationFilePaths.contains(resolvedPath(for: inputFilePath))
		}
	}

	/// `path` as scan would have recorded it: relative to the manifest's project root when the
	/// path lies under it, otherwise absolute. A manifest without a project root takes paths as written.
	func resolvedPath(for path: String) -> String {
		guard let projectRoot else { return path }
		let projectRootURL = projectRoot.asFileURL
		let directoryBaseURL = projectRootURL.appendingPathComponent("", isDirectory: true)
		return relativePath(
			for: URL(fileURLWithPath: path, relativeTo: directoryBaseURL).standardizedFileURL,
			relativeTo: projectRootURL,
		)
	}
}

/// Wrapper persisted alongside the manifest so `generate` can both
/// consume the parsed `ModuleInfo` AND validate cache freshness against
/// the exact file set `scan` observed (including
/// `additionalDirectoriesToInclude` files, which don't appear in the
/// `generate` CSV).
struct CachedScannedModuleInfo: Codable {
	/// What the input files whose scans consulted no compilation condition contributed, which is
	/// what they contribute whatever conditions `generate` uses.
	let moduleInfo: ModuleInfo
	/// What each input file whose scan consulted a compilation condition contributed.
	let conditionSensitiveFileScans: [CachedFileScan]
	/// What the files reached through `additionalDirectoriesToInclude` and absent from the input files
	/// contributed, kept the same way. Merged after the input files' module as a fresh parse merges them.
	let additionalModuleInfo: ModuleInfo
	let additionalConditionSensitiveFileScans: [CachedFileScan]
	/// The directory relative paths in the scans are relative to.
	let projectRoot: String
	/// Absolute paths of every file `scan` observed — CSV inputs plus
	/// additional-directory files. Drives the mtime freshness check.
	let scannedInputPaths: [String]
	/// Raw CSV file paths as `scan` read them. Drives the "current generate
	/// CSV matches the CSV that scan observed" check.
	let csvInputPaths: [String]
	/// Absolute paths of just the additional-directory files scan observed.
	/// Used by `generate`'s additional-directory freshness check to compare
	/// against the current on-disk enumeration without re-sorting the CSV.
	let additionalInputAbsolutePaths: [String]
	/// Absolute paths of `additionalDirectoriesToInclude` from the
	/// configuration that drove this scan. `generate` re-enumerates these
	/// during freshness checks so files added to those directories
	/// between scan and generate correctly invalidate the cache.
	let additionalDirectories: [String]
	/// Every compilation condition the scan treated as active. `generate` reuses a file's cached scan
	/// only when its own conditions give each of the scan's `consultedCompilationConditions` the value
	/// this set gives it, because walking the file again would then find the same. Other conditions
	/// may differ: a build tool plugin hands `scan` only the conditions it can see, while `generate`
	/// usually reads more from the build settings, such as `DEBUG` and `SWIFT_PACKAGE`.
	let activeCompilationConditions: [String]
}

/// What one file contributed to the module that `scan` cached.
struct CachedFileScan: Codable {
	init(scannedPath: String, fileScan: FileScan) {
		self.fileScan = fileScan
		differingScannedPath = scannedPath == fileScan.path ? nil : scannedPath
	}

	/// What the file contributed, with the file named relative to the project root as the manifest names files.
	let fileScan: FileScan

	/// The path `scan` parsed the file under, which the locations recorded in `fileScan` cite.
	var scannedPath: String {
		differingScannedPath ?? fileScan.path
	}

	/// `scannedPath` when it differs from `fileScan.path`, which it seldom does: omitting it keeps the
	/// cache, which `generate` decodes on every build, small.
	private let differingScannedPath: String?
}

/// Path alongside the manifest where `scan` persists the parsed
/// `ModuleInfo` and `generate` reads it to skip re-parsing. Derived from
/// the manifest path so concurrent runs writing to different manifests
/// don't collide.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func scannedModuleInfoURL(forManifestPath manifestPath: String) -> URL {
	let manifestURL = manifestPath.asFileURL
	let base = manifestURL.deletingPathExtension().lastPathComponent
	return manifestURL
		.deletingLastPathComponent()
		.appendingPathComponent("\(base).safediScannedModuleInfo.json")
}
