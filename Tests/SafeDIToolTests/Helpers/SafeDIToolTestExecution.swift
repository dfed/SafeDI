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
import SafeDIScannerCore
import Testing
@testable import SafeDITool

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func executeSafeDIToolTest(
	swiftFileContent: [String],
	additionalDirectorySwiftFileContent: [String] = [],
	dependentModuleInfoPaths: [String] = [],
	additionalImportedModules: [String] = [],
	buildSwiftOutputDirectory: Bool = false,
	buildDOTFileOutput: Bool = false,
	filesToDelete: inout [URL],
	includeFolders: [String] = [],
) async throws -> TestOutput {
	// Create additional directory first so its path can be substituted into target file content.
	var additionalDirectoryFiles = [URL]()
	var additionalFixtureDirectory: URL?
	if !additionalDirectorySwiftFileContent.isEmpty {
		let additionalDirectory = URL.temporaryFile
		try FileManager.default.createDirectory(at: additionalDirectory, withIntermediateDirectories: true)
		additionalFixtureDirectory = additionalDirectory
		additionalDirectoryFiles = try createSwiftFixtureFiles(
			from: additionalDirectorySwiftFileContent,
			in: additionalDirectory,
		)
	}

	let swiftFileCSV = URL.temporaryFile
	let swiftFixtureDirectory = URL.temporaryFile
	try FileManager.default.createDirectory(at: swiftFixtureDirectory, withIntermediateDirectories: true)

	// Replace directory placeholders in target file content with real paths.
	let resolvedSwiftFileContent = swiftFileContent.map { content in
		var resolved = content.replacingOccurrences(
			of: "$TARGET_DIRECTORY",
			with: swiftFixtureDirectory.path,
		)
		if let additionalFixtureDirectory {
			resolved = resolved.replacingOccurrences(
				of: "$ADDITIONAL_DIRECTORY",
				with: additionalFixtureDirectory.path,
			)
		}
		return resolved
	}

	let swiftFiles = try createSwiftFixtureFiles(
		from: resolvedSwiftFileContent,
		in: swiftFixtureDirectory,
	)
	try swiftFiles
		.map(\.relativePath)
		.joined(separator: ",")
		.write(to: swiftFileCSV, atomically: true, encoding: .utf8)

	let dependentModuleInfoFileCSV = URL.temporaryFile
	try dependentModuleInfoPaths
		.joined(separator: ",")
		.write(to: dependentModuleInfoFileCSV, atomically: true, encoding: .utf8)

	let moduleInfoOutput = URL.temporaryFile.appendingPathExtension("safedi")
	let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	let manifestFile = URL.temporaryFile.appendingPathExtension("json")
	let dotTreeOutput = URL.temporaryFile.appendingPathExtension("dot")

	// Build the StubFileFinder. When additional directory files exist, make it
	// directory-aware so it returns only files under the enumerated root.
	let fileFinder = if !additionalDirectoryFiles.isEmpty {
		StubFileFinder(filesByDirectory: [
			swiftFixtureDirectory: swiftFiles,
			additionalFixtureDirectory!: additionalDirectoryFiles,
		])
	} else {
		StubFileFinder(files: swiftFiles)
	}

	return try await SafeDITool.$fileFinder.withValue(fileFinder) {
		// Build the manifest by scanning for roots. Discover additional
		// directory files from the target module's own #SafeDIConfiguration
		// only, matching real plugin behavior (discoverAdditionalDirectorySwiftFiles
		// scans only the current module's files, not dependencies).
		var manifestPath: String?
		if buildSwiftOutputDirectory {
			try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
			let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

			// Only scan target files (swiftFiles) for config — not dependency files.
			// Stop after the first config found, matching configurations.first.
			let additionalScanFiles: [URL] = {
				for swiftFile in swiftFiles {
					guard let content = try? String(contentsOf: swiftFile, encoding: .utf8) else { continue }
					let directories = SafeDIScanner.extractAdditionalDirectoriesToInclude(in: content)
					guard !directories.isEmpty else { continue }
					return directories.flatMap { directory -> [URL] in
						let directoryURL = URL(fileURLWithPath: directory)
						guard let enumerator = FileManager.default.enumerator(
							at: directoryURL,
							includingPropertiesForKeys: nil,
							options: [.skipsHiddenFiles],
						) else { return [] }
						return enumerator.compactMap { ($0 as? URL).flatMap { $0.pathExtension == "swift" ? $0 : nil } }
					}
				}
				return []
			}()
			let allSwiftFilesForScan = swiftFiles + additionalScanFiles

			let scanResult = try SafeDIScanner().scan(
				swiftFiles: allSwiftFilesForScan,
				relativeTo: projectRoot,
				outputDirectory: outputDirectory,
			)
			try scanResult.writeManifest(to: manifestFile)
			manifestPath = manifestFile.relativePath
		}

		var tool = SafeDITool()
		tool.swiftSourcesFilePath = swiftFileCSV.relativePath
		tool.showVersion = false
		tool.include = includeFolders
		tool.additionalImportedModules = additionalImportedModules
		tool.moduleInfoOutput = moduleInfoOutput.relativePath
		tool.dependentModuleInfoFilePath = dependentModuleInfoPaths.isEmpty ? nil : dependentModuleInfoFileCSV.relativePath
		tool.swiftManifest = manifestPath
		tool.dotFileOutput = buildDOTFileOutput ? dotTreeOutput.relativePath : nil
		try await tool.run()

		filesToDelete.append(swiftFileCSV)
		filesToDelete.append(swiftFixtureDirectory)
		filesToDelete.append(moduleInfoOutput)
		if let additionalFixtureDirectory {
			filesToDelete.append(additionalFixtureDirectory)
		}
		if buildSwiftOutputDirectory {
			filesToDelete.append(outputDirectory)
			filesToDelete.append(manifestFile)
		}
		if buildDOTFileOutput {
			filesToDelete.append(dotTreeOutput)
		}

		// Read generated files from the output directory.
		let generatedFiles: [String: String]? = if buildSwiftOutputDirectory {
			{
				guard let fileNames = try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.relativePath) else { return [:] }
				var result = [String: String]()
				for fileName in fileNames where fileName.hasSuffix(".swift") {
					let filePath = (outputDirectory.relativePath as NSString).appendingPathComponent(fileName)
					result[fileName] = try? String(contentsOfFile: filePath, encoding: .utf8)
				}
				return result
			}()
		} else {
			nil
		}

		return try TestOutput(
			moduleInfo: JSONDecoder().decode(SafeDITool.ModuleInfo.self, from: Data(contentsOf: moduleInfoOutput)),
			moduleInfoOutputPath: moduleInfoOutput.relativePath,
			generatedFiles: generatedFiles,
			dotTree: buildDOTFileOutput ? String(data: Data(contentsOf: dotTreeOutput), encoding: .utf8) : nil,
		)
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct TestOutput {
	let moduleInfo: SafeDITool.ModuleInfo
	let moduleInfoOutputPath: String
	let generatedFiles: [String: String]?
	let dotTree: String?

	var dependencyTreeFiles: [String: String] {
		generatedFiles?.filter { $0.key.hasSuffix("+SafeDI.swift") } ?? [:]
	}

	var mockFiles: [String: String] {
		generatedFiles?.filter { $0.key.hasSuffix("+SafeDIMock.swift") } ?? [:]
	}

	var mockConfigurationFile: String? {
		generatedFiles?["SafeDIMockConfiguration.swift"]
	}
}

extension URL {
	fileprivate static var temporaryFile: URL {
		#if os(Linux)
			return FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		#else
			guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
				return FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			}
			return URL.temporaryDirectory.appending(path: UUID().uuidString)
		#endif
	}
}

struct StubFileFinder: FileFinder {
	/// Creates a file finder that returns the same files regardless of which directory is enumerated.
	init(files: [URL]) {
		filesByDirectory = nil
		fallbackFiles = files
	}

	/// Creates a directory-aware file finder that returns only files under the enumerated root.
	init(filesByDirectory: [URL: [URL]]) {
		self.filesByDirectory = filesByDirectory
		fallbackFiles = []
	}

	func enumerator(
		at url: URL,
		includingPropertiesForKeys _: [URLResourceKey]?,
		options _: FileManager.DirectoryEnumerationOptions,
		errorHandler _: ((URL, any Error) -> Bool)?,
	) -> FileManager.DirectoryEnumerator? {
		let matchedFiles: [URL]
		if let filesByDirectory {
			let standardizedPath = url.standardizedFileURL.path
			matchedFiles = filesByDirectory.first(where: { directory, _ in
				directory.standardizedFileURL.path == standardizedPath
			})?.value ?? []
		} else {
			matchedFiles = fallbackFiles
		}
		return StubDirectoryEnumerator(files: matchedFiles)
	}

	final class StubDirectoryEnumerator: FileManager.DirectoryEnumerator {
		init(files: [URL]) {
			self.files = files
				// Also include a random file in the glob.
				+ [URL.temporaryFile]
		}

		override func nextObject() -> Any? {
			if files.isEmpty {
				nil
			} else {
				files.removeFirst()
			}
		}

		var files: [URL]
	}

	private let filesByDirectory: [URL: [URL]]?
	private let fallbackFiles: [URL]
}

func assertThrowsError(
	_ errorDescription: String,
	sourceLocation: SourceLocation = #_sourceLocation,
	block: () async throws -> some Sendable,
) async {
	do {
		_ = try await block()
		Issue.record("Did not throw error!", sourceLocation: sourceLocation)
	} catch {
		#expect(errorDescription == "\(error)", sourceLocation: sourceLocation)
	}
}

private func createSwiftFixtureFiles(
	from swiftFileContent: [String],
	in directory: URL,
) throws -> [URL] {
	let instantiableRegex = try Regex(#"@Instantiable(?:\s*\([^)]*\))?"#)
	let instantiableTypeRegex = try Regex(#"(?:class|struct|actor|enum)\s+(\w+)"#)
	let firstTypeRegex = try Regex(#"(?:class|struct|actor|enum|protocol)\s+(\w+)"#)
	var fileNameCounts = [String: Int]()

	return try swiftFileContent.map { content in
		let baseName: String
		if let instantiableMatch = content.firstMatch(of: instantiableRegex) {
			let contentAfterInstantiable = content[instantiableMatch.range.upperBound...]
			if let typeMatch = contentAfterInstantiable.firstMatch(of: instantiableTypeRegex),
			   let nameRange = typeMatch.output[1].range
			{
				baseName = String(contentAfterInstantiable[nameRange])
			} else if let match = content.firstMatch(of: firstTypeRegex),
			          let nameRange = match.output[1].range
			{
				baseName = String(content[nameRange])
			} else {
				baseName = "File"
			}
		} else if let match = content.firstMatch(of: firstTypeRegex),
		          let nameRange = match.output[1].range
		{
			baseName = String(content[nameRange])
		} else {
			baseName = "File"
		}
		fileNameCounts[baseName, default: 0] += 1
		let fileNameSuffix = fileNameCounts[baseName, default: 1] == 1 ? "" : "_\(fileNameCounts[baseName, default: 1])"
		let fileURL = directory.appendingPathComponent("\(baseName)\(fileNameSuffix).swift")
		try content.write(to: fileURL, atomically: true, encoding: .utf8)
		return fileURL
	}
}
