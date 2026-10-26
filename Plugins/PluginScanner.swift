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
		let allSwiftFiles = swiftFiles + additionalInputFiles
		let sortedSwiftFiles = allSwiftFiles.sorted {
			relativePath(for: $0, relativeTo: projectRoot) < relativePath(for: $1, relativeTo: projectRoot)
		}
		let rootFiles = sortedSwiftFiles.filter { fileContainsRoot(at: $0) }
		let rootOutputFileNames = outputFileNames(for: rootFiles, relativeTo: projectRoot)

		let sortedMockFiles = mockScopedSwiftFiles.sorted {
			relativePath(for: $0, relativeTo: projectRoot) < relativePath(for: $1, relativeTo: projectRoot)
		}
		let mockFiles = sortedMockFiles.filter { fileContainsGenerateMockTrue(at: $0) }
		let mockOutputFileNames = outputFileNames(for: mockFiles, relativeTo: projectRoot, suffix: "+SafeDIMock.swift")

		let additionalMockOutputFiles = additionalMocksToGenerate.map {
			outputDirectory.appendingPathComponent("\($0)+SafeDIMock.swift")
		}

		var outputFiles = rootOutputFileNames.map { outputDirectory.appendingPathComponent($0) }
			+ mockOutputFileNames.map { outputDirectory.appendingPathComponent($0) }
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

	private static func outputFileNames(
		for inputURLs: [URL],
		relativeTo baseURL: URL,
		suffix: String = "+SafeDI.swift",
	) -> [String] {
		struct FileInfo {
			let baseName: String
			let parentComponents: [String]
		}

		let fileInfo = inputURLs.map { inputURL in
			let relPath = relativePath(for: inputURL, relativeTo: baseURL)
			let relativeDirectory = (relPath as NSString).deletingLastPathComponent
			let parentComponents: [String] = if relativeDirectory.isEmpty || relativeDirectory == "." {
				[]
			} else {
				relativeDirectory.split(separator: "/").map(String.init)
			}
			return FileInfo(
				baseName: inputURL.deletingPathExtension().lastPathComponent,
				parentComponents: parentComponents,
			)
		}

		var outputFileNames = Array(repeating: "", count: fileInfo.count)
		let groups = Dictionary(grouping: Array(fileInfo.enumerated()), by: \.element.baseName)

		for (baseName, entries) in groups {
			guard entries.count > 1 else {
				outputFileNames[entries[0].offset] = "\(baseName)\(suffix)"
				continue
			}

			var namesByIndex = entries.reduce(into: [Int: String]()) { partialResult, entry in
				partialResult[entry.offset] = baseName
			}

			var maxParentDepth = 0
			for entry in entries {
				maxParentDepth = max(maxParentDepth, entry.element.parentComponents.count)
			}
			if maxParentDepth > 0 {
				for parentDepth in 1...maxParentDepth where Set(namesByIndex.values).count < entries.count {
					for entry in entries {
						let prefix = entry.element.parentComponents
							.suffix(parentDepth)
							.joined(separator: "_")
						namesByIndex[entry.offset] = prefix.isEmpty ? baseName : "\(prefix)_\(baseName)"
					}
				}
			}

			for entry in entries {
				let name = namesByIndex[entry.offset, default: baseName]
				outputFileNames[entry.offset] = "\(name)\(suffix)"
			}
		}

		return outputFileNames
	}
}
