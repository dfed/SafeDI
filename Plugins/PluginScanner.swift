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

/// Lightweight text-based scanner used to discover output files without needing
/// SwiftSyntax. It runs in-process during `createBuildCommands` when the plugin
/// cannot shell out to `SafeDITool scan` (the XcodeProjectPlugin path, and the
/// SPM fallback when `context.tool(named:)` returns an unresolved path). Only
/// output-file discovery happens here — the real parse and code generation are
/// performed by SafeDITool at build time via the `--output-directory` flag.
/// Like `SafeDITool scan`, it ignores `#if` blocks and plans an output for a
/// declaration in any clause; `generate` writes a file without code for one
/// that the build's compilation conditions leave inactive.
enum PluginScanner {
	struct ScanResult {
		var outputFiles: [URL]
		var additionalInputFiles: [URL]
	}

	/// A Swift file this scan reads, with its path relative to the project root, or absolute when outside it.
	struct ScannedFile {
		let url: URL
		let relativePath: String
	}

	static func scan(
		swiftFiles: [URL],
		mockScopedSwiftFiles: [URL],
		relativeTo projectRoot: URL,
		outputDirectory: URL,
	) -> ScanResult {
		// Discover additional directories from configuration first,
		// so roots in those directories are included in output discovery.
		// Like `SafeDITool scan`, plan outputs for every configuration,
		// whichever `#if` clause declares it: the compilation conditions
		// that select a clause are known only when the build runs.
		var additionalDirectories = [String]()
		var additionalMocksToGenerate = [String]()
		for swiftFile in mockScopedSwiftFiles {
			guard let content = try? String(contentsOf: swiftFile, encoding: .utf8),
			      content.contains("#SafeDIConfiguration")
			else { continue }
			for directory in stringLiteralsInArrayArguments(labeled: "additionalDirectoriesToInclude", in: content)
				where !additionalDirectories.contains(directory)
			{
				additionalDirectories.append(directory)
			}
			for typeName in stringLiteralsInArrayArguments(labeled: "additionalMocksToGenerate", in: content)
				where !additionalMocksToGenerate.contains(typeName)
			{
				additionalMocksToGenerate.append(typeName)
			}
		}
		var additionalInputFiles = [URL]()
		let directoryBaseURL = projectRoot.hasDirectoryPath
			? projectRoot
			: projectRoot.appendingPathComponent("", isDirectory: true)
		for directory in additionalDirectories {
			let directoryURL = URL(fileURLWithPath: directory, relativeTo: directoryBaseURL)
			guard let enumerator = FileManager.default.enumerator(
				at: directoryURL,
				includingPropertiesForKeys: nil,
				options: [.skipsHiddenFiles],
			) else { continue }
			for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
				additionalInputFiles.append(fileURL)
			}
		}

		// Include additional directory files when scanning for roots.
		let normalizedProjectRoot = NormalizedFilePath(projectRoot.path(percentEncoded: false))
		/// `fileURLs`, sorted by their paths relative to the project root, as `SafeDITool scan` sorts them.
		func sortedByRelativePath(_ fileURLs: [URL]) -> [ScannedFile] {
			fileURLs
				.map { ScannedFile(url: $0, relativePath: NormalizedFilePath($0.path(percentEncoded: false)).path(relativeTo: normalizedProjectRoot)) }
				.sorted { $0.relativePath < $1.relativePath }
		}
		let rootFiles = sortedByRelativePath(swiftFiles + additionalInputFiles).filter { fileContainsRoot(at: $0.url) }
		let rootOutputFileNames = outputFileNames(forFilesAt: rootFiles.map(\.relativePath))

		let mockFiles = sortedByRelativePath(mockScopedSwiftFiles).filter { fileContainsGenerateMockTrue(at: $0.url) }
		let mockFileOutputFileNames = mockOutputFileNames(forFilesAt: mockFiles.map(\.relativePath))

		let additionalMockOutputFiles = additionalMocksToGenerate.map {
			outputDirectory.appendingPathComponent("\($0)+SafeDIMock.swift")
		}

		var outputFiles = rootOutputFileNames.map { outputDirectory.appendingPathComponent($0) }
			+ mockFileOutputFileNames.map { outputDirectory.appendingPathComponent($0) }
			+ additionalMockOutputFiles

		let hasMockEntries = !mockFiles.isEmpty || !additionalMocksToGenerate.isEmpty
		if hasMockEntries {
			outputFiles.append(outputDirectory.appendingPathComponent("SafeDIMockConfiguration.swift"))
		}

		return ScanResult(outputFiles: outputFiles, additionalInputFiles: additionalInputFiles)
	}

	// MARK: - Private

	/// Checks whether a file likely contains `@Instantiable(isRoot: true)`.
	/// Comments and string literals are stripped before matching so a mention
	/// of `@Instantiable(isRoot: true)` in a doc comment or string doesn't
	/// false-positive — the real parser in SafeDITool is authoritative, but
	/// that parser only runs at build time; this scan determines what output
	/// files the build is expected to produce.
	///
	/// The regex uses `(.|\n)*?` instead of `[^)]*` to handle parentheses inside
	/// string literal arguments (e.g. `mockAttributes: "@available(iOS 17, *)"`).
	private static func fileContainsRoot(at fileURL: URL) -> Bool {
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
		      content.contains("@Instantiable")
		else { return false }
		let stripped = stripSwiftCommentsAndStrings(from: content)
		return stripped.range(of: #"@Instantiable\s*\((.|\n)*?isRoot\s*:\s*true"#, options: .regularExpression) != nil
	}

	/// Checks whether a file likely contains `@Instantiable(generateMock: true)`.
	private static func fileContainsGenerateMockTrue(at fileURL: URL) -> Bool {
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
		      content.contains("@Instantiable")
		else { return false }
		let stripped = stripSwiftCommentsAndStrings(from: content)
		return stripped.range(of: #"@Instantiable\s*\((.|\n)*?generateMock\s*:\s*true"#, options: .regularExpression) != nil
	}
}
