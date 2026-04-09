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

/// Lightweight text-based scanner used by the plugin to discover output files
/// without needing SwiftSyntax. This runs in the plugin process during
/// `createBuildCommands` and only determines what output files will be generated.
/// The actual code generation is done by SafeDITool at build time.
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
		let sortedSwiftFiles = swiftFiles.sorted {
			relativePath(for: $0, relativeTo: projectRoot) < relativePath(for: $1, relativeTo: projectRoot)
		}
		let rootFiles = sortedSwiftFiles.filter { fileContainsRoot(at: $0) }
		let rootOutputFileNames = outputFileNames(for: rootFiles, relativeTo: projectRoot)

		let sortedMockFiles = mockScopedSwiftFiles.sorted {
			relativePath(for: $0, relativeTo: projectRoot) < relativePath(for: $1, relativeTo: projectRoot)
		}
		let mockFiles = sortedMockFiles.filter { fileContainsGenerateMockTrue(at: $0) }
		let mockOutputFileNames = outputFileNames(for: mockFiles, relativeTo: projectRoot, suffix: "+SafeDIMock.swift")

		var outputFiles = rootOutputFileNames.map { outputDirectory.appendingPathComponent($0) }
			+ mockOutputFileNames.map { outputDirectory.appendingPathComponent($0) }

		if !mockFiles.isEmpty {
			outputFiles.append(outputDirectory.appendingPathComponent("SafeDIMockConfiguration.swift"))
		}

		// Discover additional directories from configuration.
		var additionalInputFiles = [URL]()
		for swiftFile in mockScopedSwiftFiles {
			guard let content = try? String(contentsOf: swiftFile, encoding: .utf8),
			      content.contains("#SafeDIConfiguration")
			else { continue }
			let directories = extractArrayArgument(named: "additionalDirectoriesToInclude", in: content)
			guard !directories.isEmpty else { break }
			let directoryBaseURL = projectRoot.hasDirectoryPath
				? projectRoot
				: projectRoot.appendingPathComponent("", isDirectory: true)
			for directory in directories {
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
			break
		}

		return ScanResult(outputFiles: outputFiles, additionalInputFiles: additionalInputFiles)
	}

	// MARK: - Private

	private static func fileContainsRoot(at fileURL: URL) -> Bool {
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
		return content.contains("@Instantiable") && content.contains("isRoot") && content.contains("true")
	}

	private static func fileContainsGenerateMockTrue(at fileURL: URL) -> Bool {
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
		return content.contains("@Instantiable") && content.contains("generateMock") && content.contains("true")
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

	private static func extractArrayArgument(named argumentLabel: String, in source: String) -> [String] {
		guard let labelRange = source.range(of: argumentLabel) else { return [] }
		var index = labelRange.upperBound
		// Find opening bracket.
		while index < source.endIndex, source[index] != "[" {
			index = source.index(after: index)
		}
		guard index < source.endIndex else { return [] }
		// Find closing bracket.
		var depth = 0
		var closingIndex = index
		while closingIndex < source.endIndex {
			switch source[closingIndex] {
			case "[": depth += 1
			case "]":
				depth -= 1
				if depth == 0 {
					let content = source[source.index(after: index)..<closingIndex]
					return extractStringLiterals(from: content)
				}
			default: break
			}
			closingIndex = source.index(after: closingIndex)
		}
		return []
	}

	private static func extractStringLiterals(from content: some StringProtocol) -> [String] {
		var results = [String]()
		var searchIndex = content.startIndex
		while searchIndex < content.endIndex {
			guard let openQuote = content[searchIndex...].firstIndex(of: "\"") else { break }
			let contentStart = content.index(after: openQuote)
			guard contentStart < content.endIndex,
			      let closeQuote = content[contentStart...].firstIndex(of: "\"")
			else { break }
			results.append(String(content[contentStart..<closeQuote]))
			searchIndex = content.index(after: closeQuote)
		}
		return results
	}
}
