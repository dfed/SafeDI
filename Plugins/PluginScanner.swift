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
		var additionalInputFiles = [URL]()
		var additionalMocksToGenerate = [String]()
		for swiftFile in mockScopedSwiftFiles {
			guard let content = try? String(contentsOf: swiftFile, encoding: .utf8),
			      content.contains("#SafeDIConfiguration")
			else { continue }
			let directories = extractArrayArgument(named: "additionalDirectoriesToInclude", in: content)
			additionalMocksToGenerate = extractArrayArgument(named: "additionalMocksToGenerate", in: content)
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
			// Use only the first configuration found.
			break
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

	/// Removes Swift line comments (`//`…EOL), block comments (`/* … */`,
	/// nesting supported), and string literals (single and triple-quoted),
	/// preserving line structure so regex line anchors still behave.
	/// Non-comment/non-string characters and newlines pass through unchanged.
	///
	/// This is deliberately a lexer-lite: it matches Swift tokens well enough
	/// that a mention of `@Instantiable(...)` inside a comment or string is
	/// excluded from the scanner's regex. It is NOT a full Swift parser — but
	/// the real parser (`SafeDITool`) runs at build time and is authoritative.
	static func stripSwiftCommentsAndStrings(from source: String) -> String {
		var result = ""
		result.reserveCapacity(source.count)
		let chars = Array(source)
		var index = 0
		while index < chars.count {
			let character = chars[index]
			let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil

			// Line comment: skip through end-of-line, keeping the newline.
			if character == "/", next == "/" {
				while index < chars.count, chars[index] != "\n" {
					index += 1
				}
				continue
			}

			// Block comment (nested): skip through the matching `*/`.
			if character == "/", next == "*" {
				index += 2
				var depth = 1
				while index < chars.count, depth > 0 {
					let openerNext: Character? = index + 1 < chars.count ? chars[index + 1] : nil
					if chars[index] == "/", openerNext == "*" {
						depth += 1
						index += 2
					} else if chars[index] == "*", openerNext == "/" {
						depth -= 1
						index += 2
					} else {
						if chars[index] == "\n" {
							result.append("\n")
						}
						index += 1
					}
				}
				continue
			}

			// Triple-quoted string: skip through closing `"""`. Newlines inside
			// are preserved so downstream regexes see consistent line positions.
			if character == "\"", next == "\"", index + 2 < chars.count, chars[index + 2] == "\"" {
				index += 3
				while index < chars.count {
					if chars[index] == "\\", index + 1 < chars.count {
						if chars[index + 1] == "\n" {
							result.append("\n")
						}
						index += 2
						continue
					}
					if chars[index] == "\"",
					   index + 2 < chars.count,
					   chars[index + 1] == "\"",
					   chars[index + 2] == "\""
					{
						index += 3
						break
					}
					if chars[index] == "\n" {
						result.append("\n")
					}
					index += 1
				}
				continue
			}

			// Single-quoted string: skip through closing `"` on the same line.
			if character == "\"" {
				index += 1
				while index < chars.count {
					if chars[index] == "\\", index + 1 < chars.count {
						index += 2
						continue
					}
					if chars[index] == "\"" || chars[index] == "\n" {
						if chars[index] == "\n" {
							result.append("\n")
						} else {
							index += 1
						}
						break
					}
					index += 1
				}
				continue
			}

			result.append(character)
			index += 1
		}
		return result
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
		while index < source.endIndex, source[index] != "[" {
			index = source.index(after: index)
		}
		guard index < source.endIndex else { return [] }
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
