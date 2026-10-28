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
			projectFilePaths: ProjectFilePaths(projectRoot: projectRoot),
			outputDirectory: outputDirectory,
			manifestFile: manifestFile,
			mockScopedFiles: mockScopedFiles,
			activeCompilationConditions: Set(activeCompilationConditions),
		)
	}
}

/// Performs the scan operation, producing a manifest JSON file and the scan cache beside it.
/// Shared by the `scan` subcommand and the `generate` subcommand's
/// `--output-directory` auto-scan mode.
/// - Returns: What the scan cache holds.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@discardableResult
func performScan(
	inputSourcesFile: String,
	projectFilePaths: ProjectFilePaths,
	outputDirectory: String,
	manifestFile: String,
	mockScopedFiles: [String] = [],
	activeCompilationConditions: Set<String> = [],
) async throws -> CachedScannedModuleInfo {
	let outputDirectoryURL = outputDirectory.asFileURL

	// Read CSV and resolve file paths relative to project root.
	let inputFilePaths = try String(contentsOfFile: inputSourcesFile, encoding: .utf8)
		.parsedPathListCSV()

	// Each input's comparable path, which names it in the parse and in every comparison.
	let allFilePaths = Set(inputFilePaths.map(projectFilePaths.projectFilePath(of:)))
	let allFilePathsByName = Dictionary(uniqueKeysWithValues: allFilePaths.map { ($0.path, $0) })

	// Each input's modification times, recorded before the input is read so that an edit made
	// while scan runs shows in `generate`'s comparison. Keyed by absolute path, so `generate`'s
	// freshness check works regardless of its working directory.
	var scannedInputStamps = [ProjectFilePath: FileModificationStamp]()
	for filePath in allFilePaths {
		scannedInputStamps[filePath] = FileModificationStamp(ofFileAtPath: filePath.path)
	}

	// Determine which files are scoped for mock scanning.
	let mockScopedFilePaths: Set<ProjectFilePath> = if mockScopedFiles.isEmpty {
		allFilePaths
	} else {
		Set(mockScopedFiles.map(projectFilePaths.projectFilePath(of:)))
	}
	/// Whether the input parsed under `name` is one of the module's own files.
	func isMockScoped(_ name: String) -> Bool {
		allFilePathsByName[name].map(mockScopedFilePaths.contains) == true
	}

	// Parse all files once to find roots, mocks, and configurations. Only the
	// mock-scoped files can declare this module's configuration, which decides
	// how every file's `#if` blocks are evaluated, so they are searched for it first.
	let (parsedModule, fileScans) = try await parseModule(
		filePaths: Set(allFilePathsByName.keys),
		configurationFilePaths: Set(allFilePathsByName.keys.filter(isMockScoped)),
		activeCompilationConditions: activeCompilationConditions,
	)
	let evaluator = parsedModule.conditionalCompilationEvaluator

	// The parse rejected more than one configuration among the scoped files.
	let configuration = parsedModule.configuration

	// A build system needs the list of output files before the build runs, while `generate` may be
	// handed other conditions than this scan, so outputs are planned for the declarations in every
	// clause of every `#if` block: `generate` writes a file without code for one that is inactive.
	// Only the module's own files decide its mocks and configuration.
	let mockScopedFileScans = fileScans.filter { isMockScoped($0.path) }
	let moduleOutputFileDeclarations = mockScopedFileScans.reduce(into: OutputFileDeclarations()) { moduleOutputFileDeclarations, fileScan in
		moduleOutputFileDeclarations.formUnion(fileScan.outputFileDeclarations)
	}

	// Discover additional directories from every configuration the module's files declare.
	var additionalInputFiles = [String]()
	var configuredAdditionalInputFiles = [String]()
	var additionalFileScans = [CachedFileScan]()
	var plannedOnlyAdditionalFileScans = [FileScan]()
	if !moduleOutputFileDeclarations.additionalDirectoriesToInclude.isEmpty {
		// The directories the active configuration lists, which `generate` reads too. Files found relative to
		// the working directory compare with the inputs only once spelled as the project spells them.
		let configuredDirectories = configuration?.additionalDirectoriesToInclude ?? []
		let configuredAdditionalFiles = try await Set(findSwiftFiles(inDirectories: configuredDirectories).map(projectFilePaths.projectFilePath(of:)))
		// Files only a configuration in an inactive clause reaches, which can declare roots `generate` finds
		// when other conditions select that configuration.
		let plannedOnlyAdditionalFiles = try await Set(findSwiftFiles(
			inDirectories: moduleOutputFileDeclarations.additionalDirectoriesToInclude.filter { !configuredDirectories.contains($0) },
		).map(projectFilePaths.projectFilePath(of:))).subtracting(configuredAdditionalFiles)

		// Record the additional files for the plugin to declare as build inputs, spelled as the build system
		// spells the project's other files.
		additionalInputFiles = configuredAdditionalFiles.union(plannedOnlyAdditionalFiles).sorted().map(projectFilePaths.buildSystemPath(of:))
		configuredAdditionalInputFiles = configuredAdditionalFiles.sorted().map(\.path)
		for filePath in configuredAdditionalFiles.union(plannedOnlyAdditionalFiles) where scannedInputStamps[filePath] == nil {
			scannedInputStamps[filePath] = FileModificationStamp(ofFileAtPath: filePath.path)
		}

		additionalFileScans = try await parseAdditionalDirectoryFiles(
			configuredAdditionalFiles,
			excludingInputFilesAt: allFilePaths,
			namedBy: projectFilePaths,
			conditionalCompilation: evaluator,
		)
		// Parsed only to plan outputs: the module these conditions select does not include them.
		plannedOnlyAdditionalFileScans = try await parseAdditionalDirectoryFiles(
			plannedOnlyAdditionalFiles,
			excludingInputFilesAt: allFilePaths,
			namedBy: projectFilePaths,
			conditionalCompilation: evaluator,
		).map(\.fileScan)
	}

	/// The manifest name of each file `fileScans` names, once each, sorted.
	func sortedUniqueManifestPaths(_ fileScans: [FileScan]) -> [String] {
		Set(fileScans.map { projectFilePaths.manifestPath(of: projectFilePaths.projectFilePath(of: $0.path)) }).sorted()
	}

	// Collect root files and compute output file names.
	let uniqueRootFilePaths = sortedUniqueManifestPaths(
		(fileScans + additionalFileScans.map(\.fileScan) + plannedOnlyAdditionalFileScans).filter(\.outputFileDeclarations.declaresRoot),
	)
	let rootOutputNames = outputFileNames(forFilesAt: uniqueRootFilePaths)

	// Collect mock files (only from scoped files) and compute output file names.
	let uniqueMockFilePaths = sortedUniqueManifestPaths(mockScopedFileScans.filter(\.outputFileDeclarations.declaresMockGeneratingType))
	let mockOutputNames = mockOutputFileNames(forFilesAt: uniqueMockFilePaths)

	// Extract additional mocks to generate from every configuration, those the active configuration
	// lists first and in its order.
	let configuredAdditionalMocksToGenerate = configuration?.additionalMocksToGenerate ?? []
	let additionalMocksToGenerate = configuredAdditionalMocksToGenerate
		+ moduleOutputFileDeclarations.additionalMocksToGenerate.filter { !configuredAdditionalMocksToGenerate.contains($0) }

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
	let configurationFilePaths = sortedUniqueManifestPaths(mockScopedFileScans.filter(\.outputFileDeclarations.declaresConfiguration))

	// Determine mock configuration output file path.
	let hasMockEntries = !uniqueMockFilePaths.isEmpty || !additionalMockEntries.isEmpty
	let mockConfigurationOutputFilePath: String? = if hasMockEntries {
		outputDirectoryURL
			.appendingPathComponent("SafeDIMockConfiguration.swift")
			.path
	} else {
		nil
	}

	// Build and write the manifest.
	let manifest = SafeDIToolManifest(
		dependencyTreeGeneration: zip(uniqueRootFilePaths, rootOutputNames).map { inputFilePath, outputFileName in
			.init(
				inputFilePath: inputFilePath,
				outputFilePath: outputDirectoryURL
					.appendingPathComponent(outputFileName)
					.path,
			)
		},
		mockGeneration: zip(uniqueMockFilePaths, mockOutputNames).map { inputFilePath, outputFileName in
			.init(
				inputFilePath: inputFilePath,
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
		mockScopedFilePaths: mockScopedFilePaths.map(projectFilePaths.manifestPath(of:)).sorted(),
		projectRoot: projectFilePaths.reportedProjectRoot,
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
		fileScan.relocated(to: projectFilePaths.manifestPath(of: projectFilePaths.projectFilePath(of: fileScan.path)))
	}
	func cached(_ fileScan: FileScan) -> CachedFileScan {
		CachedFileScan(scannedPath: fileScan.path, fileScan: normalized(fileScan))
	}
	// The directories as this scan resolved them, against its working directory, so `generate` finds the same files
	// and judges the entries as this scan read them. The configuration's order is deterministic.
	let additionalDirectories = configuration?.additionalDirectoriesToInclude.map(AdditionalDirectory.init(entry:)) ?? []
	// Files are parsed in parallel and their scans arrive in the order parsing finished. Ordering them by
	// path makes the cache the same bytes whenever the inputs are the same.
	let sortedFileScans = fileScans.sorted { $0.path < $1.path }
	let sortedAdditionalFileScans = additionalFileScans.sorted { $0.fileScan.path < $1.fileScan.path }
	let cached = CachedScannedModuleInfo(
		moduleInfo: ModuleInfo(sortedFileScans.filter { !$0.consultsCompilationConditions }.map(normalized)),
		conditionSensitiveFileScans: sortedFileScans.filter(\.consultsCompilationConditions).map(cached),
		additionalModuleInfo: ModuleInfo(sortedAdditionalFileScans.map(\.fileScan).filter { !$0.consultsCompilationConditions }),
		additionalConditionSensitiveFileScans: sortedAdditionalFileScans.filter(\.fileScan.consultsCompilationConditions),
		projectRoot: projectFilePaths.reportedProjectRoot,
		// Every file scan read for this module — CSV inputs plus any files reached through
		// `#SafeDIConfiguration.additionalDirectoriesToInclude` — so edits to either invalidate the cache.
		scannedInputs: scannedInputStamps
			.map { ScannedInput(path: $0.key.path, modificationStamp: $0.value) }
			.sorted { $0.path < $1.path },
		csvInputPaths: inputFilePaths.sorted(),
		additionalInputAbsolutePaths: configuredAdditionalInputFiles,
		additionalDirectories: additionalDirectories,
		activeCompilationConditions: activeCompilationConditions.sorted(),
	)
	// Cache write is best-effort. A full disk or other transient FS
	// failure shouldn't block the build — `generate` always falls back
	// to a fresh parse when the cache is missing or can't be read. The
	// write is atomic, so a `generate` never reads a partly written cache.
	try? cached.scanCacheData.write(to: scannedModuleInfoURL(forManifestPath: manifestFile), options: .atomic)
	return cached
}

/// What the Swift files found in a module's `#SafeDIConfiguration(additionalDirectoriesToInclude:)` directories and
/// absent from its input files contribute. `scan` and a `generate` that parses afresh both parse them here, so
/// `generate` names them, and cites them in the locations it records, as scan's manifest and cache do.
///
/// - Parameters:
///   - filePaths: The files found in the directories.
///   - inputFilePaths: The module's input files. A found file that is also an input is parsed only as an input:
///     parsing it again would declare its types twice.
///   - projectFilePaths: The paths of the project a manifest names files in, or `nil` to name each file by its
///     absolute path.
///   - evaluator: The evaluator the module's input files were parsed with.
/// - Returns: What each found file that is not an input contributes, parsed under its absolute path, so the
///   locations it records name the file wherever the tool runs, and named as the manifest names files.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseAdditionalDirectoryFiles(
	_ filePaths: Set<ProjectFilePath>,
	excludingInputFilesAt inputFilePaths: Set<ProjectFilePath>,
	namedBy projectFilePaths: ProjectFilePaths?,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [CachedFileScan] {
	let filePathsToParse = filePaths.subtracting(inputFilePaths)
	let fileScansByName = try await Dictionary(
		uniqueKeysWithValues: parseSwiftFiles(Set(filePathsToParse.map(\.path)), conditionalCompilation: evaluator).map { ($0.path, $0) },
	)
	// A file that does not mention SafeDI is not walked, so it contributes nothing.
	return filePathsToParse.compactMap { filePath in
		fileScansByName[filePath.path].map { fileScan in
			CachedFileScan(
				scannedPath: fileScan.path,
				fileScan: projectFilePaths.map { fileScan.relocated(to: $0.manifestPath(of: filePath)) } ?? fileScan,
			)
		}
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SafeDIToolManifest {
	/// The members of `inputFilePaths` that are this module's configuration files, matched by how scan named them:
	/// relative to `projectFilePaths`' project root, or, for a manifest without a project root, as written.
	/// Normalizing a path is far costlier than comparing its suffix, and the inputs are every file of every module
	/// the target depends on, so only an input that ends in a configuration file's name is normalized; normalizing
	/// a path never changes its file name.
	func configurationFilePaths(among inputFilePaths: Set<String>, in projectFilePaths: ProjectFilePaths?) -> Set<String> {
		let configurationFileNames = configurationFilePaths.map { ($0 as NSString).lastPathComponent }
		let isConfigurationFile: (String) -> Bool = if let projectFilePaths {
			{ [configurationFilePaths = Set(configurationFilePaths.map(projectFilePaths.projectFilePath(of:)))] inputFilePath in
				configurationFilePaths.contains(projectFilePaths.projectFilePath(of: inputFilePath))
			}
		} else {
			{ [configurationFilePaths = Set(configurationFilePaths)] inputFilePath in configurationFilePaths.contains(inputFilePath) }
		}
		return inputFilePaths.filter { inputFilePath in
			configurationFileNames.contains(where: inputFilePath.hasSuffix) && isConfigurationFile(inputFilePath)
		}
	}
}

/// Wrapper persisted alongside the manifest, in the format `BinaryFile` describes, so `generate` can both
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
	/// Every file `scan` read — CSV inputs plus additional-directory files — with the modification
	/// times it recorded before reading them. `generate` reuses this cache only while every one of them
	/// still reports the same times.
	let scannedInputs: [ScannedInput]
	/// Raw CSV file paths as `scan` read them. Drives the "current generate
	/// CSV matches the CSV that scan observed" check.
	let csvInputPaths: [String]
	/// Absolute paths of just the additional-directory files scan observed.
	/// Used by `generate`'s additional-directory freshness check to compare
	/// against the current on-disk enumeration without re-sorting the CSV.
	let additionalInputAbsolutePaths: [String]
	/// The `additionalDirectoriesToInclude` entries of the configuration that drove this scan, in the order it
	/// lists them, each with the absolute path scan found its files at. `generate` re-enumerates these paths
	/// during freshness checks so files added to those directories between scan and generate correctly
	/// invalidate the cache, and warns about an entry from which scan could read no Swift file.
	let additionalDirectories: [AdditionalDirectory]
	/// Every compilation condition the scan treated as active. `generate` reuses a file's cached scan
	/// only when its own conditions give each of the scan's `consultedCompilationConditions` the value
	/// this set gives it, because walking the file again would then find the same. Other conditions
	/// may differ: a build tool plugin hands `scan` only the conditions it can see, while `generate`
	/// usually reads more from the build settings, such as `DEBUG` and `SWIFT_PACKAGE`.
	let activeCompilationConditions: [String]
}

/// A file `scan` read, and its modification times when scan read it.
struct ScannedInput: Codable {
	/// The file's absolute path.
	let path: String
	let modificationStamp: FileModificationStamp
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

	private init(fileScan: FileScan, differingScannedPath: String?) {
		self.fileScan = fileScan
		self.differingScannedPath = differingScannedPath
	}
}

extension CachedFileScan: BinarySchemaMember {
	static let binaryLayout = [
		"fileScan",
		"differingScannedPath",
	]

	init(readingFrom reader: inout BinaryReader) throws(BinaryDecodingError) {
		try self.init(
			fileScan: reader.read(),
			differingScannedPath: reader.read() as String?,
		)
	}

	func write(to writer: inout BinaryWriter) {
		writer.write(fileScan)
		writer.write(differingScannedPath)
	}
}

/// Path alongside the manifest where `scan` persists the parsed
/// `ModuleInfo` and `generate` reads it to skip re-parsing: the manifest's
/// name with the extension `safediScanCache`, in the format `BinaryFile`
/// describes. Derived from the manifest path so concurrent runs writing to
/// different manifests don't collide.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func scannedModuleInfoURL(forManifestPath manifestPath: String) -> URL {
	let manifestURL = manifestPath.asFileURL
	let base = manifestURL.deletingPathExtension().lastPathComponent
	return manifestURL
		.deletingLastPathComponent()
		.appendingPathComponent("\(base).safediScanCache")
}
