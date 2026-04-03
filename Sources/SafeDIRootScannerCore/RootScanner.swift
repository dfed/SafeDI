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

public struct RootScanner {
	public struct Manifest: Codable, Equatable {
		public struct InputOutputMap: Codable, Equatable {
			// These field names must stay in sync with SafeDIToolManifest.InputOutputMap.
			public var inputFilePath: String
			public var outputFilePath: String

			public init(inputFilePath: String, outputFilePath: String) {
				self.inputFilePath = inputFilePath
				self.outputFilePath = outputFilePath
			}
		}

		public var dependencyTreeGeneration: [InputOutputMap]

		public init(dependencyTreeGeneration: [InputOutputMap]) {
			self.dependencyTreeGeneration = dependencyTreeGeneration
		}
	}

	public struct Result: Equatable {
		public init(manifest: Manifest) {
			self.manifest = manifest
		}

		public let manifest: Manifest

		public var outputFiles: [URL] {
			manifest.dependencyTreeGeneration.map {
				URL(fileURLWithPath: $0.outputFilePath)
			}
		}

		public func writeManifest(to manifestURL: URL) throws {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			try encoder.encode(manifest).write(to: manifestURL)
		}
	}

	public init() {}

	public func scan(
		inputFilePaths: [String],
		relativeTo baseURL: URL,
		outputDirectory: URL,
	) throws -> Result {
		let directoryBaseURL = baseURL.hasDirectoryPath
			? baseURL
			: baseURL.appendingPathComponent("", isDirectory: true)
		return try scan(
			swiftFiles: inputFilePaths.map { inputFilePath in
				URL(fileURLWithPath: inputFilePath, relativeTo: directoryBaseURL).standardizedFileURL
			},
			relativeTo: baseURL,
			outputDirectory: outputDirectory,
		)
	}

	public func scan(
		swiftFiles: [URL],
		relativeTo baseURL: URL,
		outputDirectory: URL,
	) throws -> Result {
		let sortedSwiftFiles = swiftFiles.sorted {
			relativePath(for: $0, relativeTo: baseURL) < relativePath(for: $1, relativeTo: baseURL)
		}
		let rootFiles = try sortedSwiftFiles.filter(Self.fileContainsRoot(at:))
		let outputFileNames = Self.outputFileNames(for: rootFiles, relativeTo: baseURL)

		return Result(
			manifest: Manifest(
				dependencyTreeGeneration: zip(rootFiles, outputFileNames).map { inputURL, outputFileName in
					.init(
						inputFilePath: relativePath(for: inputURL, relativeTo: baseURL),
						outputFilePath: outputDirectory
							.appendingPathComponent(outputFileName)
							.path,
					)
				},
			),
		)
	}

	public static func inputFilePaths(from csvURL: URL) throws -> [String] {
		try String(contentsOf: csvURL, encoding: .utf8)
			.components(separatedBy: CharacterSet(arrayLiteral: ","))
			.filter { !$0.isEmpty }
	}

	public static func fileContainsRoot(at fileURL: URL) throws -> Bool {
		containsRoot(in: try String(contentsOf: fileURL, encoding: .utf8))
	}

	public static func containsRoot(in source: String) -> Bool {
		let sanitizedSource = sanitize(source: source)
		let macroName = "@Instantiable"
		var searchStart = sanitizedSource.startIndex

		while let macroRange = sanitizedSource[searchStart...].range(of: macroName) {
			var index = macroRange.upperBound
			if index < sanitizedSource.endIndex,
			   isIdentifierContinuation(sanitizedSource[index])
			{
				searchStart = index
				continue
			}

			skipWhitespace(in: sanitizedSource, index: &index)
			guard index < sanitizedSource.endIndex,
			      sanitizedSource[index] == "(",
			      let closingParenIndex = matchingParenIndex(
			      	in: sanitizedSource,
			      	openingParenIndex: index,
			      )
			else {
				searchStart = macroRange.upperBound
				continue
			}

			let arguments = sanitizedSource[sanitizedSource.index(after: index)..<closingParenIndex]
			if containsRootArgument(in: arguments) {
				return true
			}

			searchStart = sanitizedSource.index(after: closingParenIndex)
		}

		return false
	}

	/// Extracts `additionalDirectoriesToInclude` paths from a source file
	/// containing `@SafeDIConfiguration`. Uses text-based scanning (no SwiftSyntax).
	/// Returns an empty array if the file does not contain a configuration.
	public static func extractAdditionalDirectoriesToInclude(in source: String) -> [String] {
		let sanitizedSource = sanitize(source: source)
		guard sanitizedSource.contains("@SafeDIConfiguration") else { return [] }
		let propertyName = "additionalDirectoriesToInclude"
		guard let propRange = sanitizedSource.range(of: propertyName) else { return [] }

		// Convert the sanitized-source index to an index in the original source.
		// The sanitizer preserves character count, so offsets are equivalent.
		let offset = sanitizedSource.distance(from: sanitizedSource.startIndex, to: propRange.upperBound)
		var index = source.index(source.startIndex, offsetBy: offset)

		// Skip past the type annotation (e.g., `: [StaticString]`) to the `=` sign.
		while index < source.endIndex, source[index] != "=" {
			index = source.index(after: index)
		}
		guard index < source.endIndex else { return [] }
		index = source.index(after: index) // skip '='

		// Find the opening bracket of the array literal.
		while index < source.endIndex, source[index] != "[" {
			index = source.index(after: index)
		}
		guard index < source.endIndex else { return [] }

		// Find the matching closing bracket.
		var depth = 0
		var closingIndex = index
		while closingIndex < source.endIndex {
			switch source[closingIndex] {
			case "[": depth += 1
			case "]":
				depth -= 1
				if depth == 0 {
					// Extract string literals from the array content.
					let arrayContent = source[source.index(after: index)..<closingIndex]
					return extractStringLiterals(from: arrayContent)
				}
			default: break
			}
			closingIndex = source.index(after: closingIndex)
		}
		return []
	}

	/// Extracts quoted string literal values from the interior of an array expression.
	private static func extractStringLiterals<S: StringProtocol>(from arrayContent: S) -> [String] {
		var results = [String]()
		var searchIndex = arrayContent.startIndex
		while searchIndex < arrayContent.endIndex {
			guard let openQuote = arrayContent[searchIndex...].firstIndex(of: "\"") else { break }
			let contentStart = arrayContent.index(after: openQuote)
			guard contentStart < arrayContent.endIndex,
			      let closeQuote = arrayContent[contentStart...].firstIndex(of: "\"")
			else { break }
			results.append(String(arrayContent[contentStart..<closeQuote]))
			searchIndex = arrayContent.index(after: closeQuote)
		}
		return results
	}

	private static func outputFileNames(
		for inputURLs: [URL],
		relativeTo baseURL: URL,
	) -> [String] {
		struct FileInfo {
			let relativePath: String
			let baseName: String
			let parentComponents: [String]
		}

		let fileInfo = inputURLs.map { inputURL in
			let relPath = relativePath(for: inputURL, relativeTo: baseURL)
			let relativeDirectory = (relPath as NSString).deletingLastPathComponent
			let parentComponents: [String] = if relativeDirectory.isEmpty || relativeDirectory == "." {
				[]
			} else {
				relativeDirectory
					.split(separator: "/")
					.map(String.init)
			}
			return FileInfo(
				relativePath: relPath,
				baseName: inputURL.deletingPathExtension().lastPathComponent,
				parentComponents: parentComponents,
			)
		}

		var outputFileNames = Array(repeating: "", count: fileInfo.count)
		let groups = Dictionary(grouping: Array(fileInfo.enumerated()), by: \.element.baseName)

		for (baseName, entries) in groups {
			guard entries.count > 1 else {
				let entry = entries[0]
				outputFileNames[entry.offset] = "\(baseName)+SafeDI.swift"
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
				outputFileNames[entry.offset] = "\(name)+SafeDI.swift"
			}
		}

		return outputFileNames
	}

	private static func containsRootArgument(in arguments: Substring) -> Bool {
		var clauseStart = arguments.startIndex
		var parenthesisDepth = 0
		var bracketDepth = 0
		var braceDepth = 0
		var index = arguments.startIndex

		while index < arguments.endIndex {
			switch arguments[index] {
			case "(":
				parenthesisDepth += 1
			case ")":
				parenthesisDepth -= 1
			case "[":
				bracketDepth += 1
			case "]":
				bracketDepth -= 1
			case "{":
				braceDepth += 1
			case "}":
				braceDepth -= 1
			case "," where parenthesisDepth == 0 && bracketDepth == 0 && braceDepth == 0:
				if isRootClause(arguments[clauseStart..<index]) {
					return true
				}
				clauseStart = arguments.index(after: index)
			default:
				break
			}
			index = arguments.index(after: index)
		}

		return isRootClause(arguments[clauseStart..<arguments.endIndex])
	}

	private static func isRootClause(_ clause: Substring) -> Bool {
		let trimmedClause = clause.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmedClause.hasPrefix("isRoot") else { return false }

		var index = trimmedClause.index(trimmedClause.startIndex, offsetBy: "isRoot".count)
		if index < trimmedClause.endIndex,
		   isIdentifierContinuation(trimmedClause[index])
		{
			return false
		}

		skipWhitespace(in: trimmedClause, index: &index)
		guard index < trimmedClause.endIndex,
		      trimmedClause[index] == ":"
		else {
			return false
		}

		index = trimmedClause.index(after: index)
		skipWhitespace(in: trimmedClause, index: &index)

		guard trimmedClause[index...].hasPrefix("true") else { return false }
		index = trimmedClause.index(index, offsetBy: "true".count)
		if index < trimmedClause.endIndex,
		   isIdentifierContinuation(trimmedClause[index])
		{
			return false
		}

		skipWhitespace(in: trimmedClause, index: &index)
		return index == trimmedClause.endIndex
	}

	private static func matchingParenIndex(
		in source: String,
		openingParenIndex: String.Index,
	) -> String.Index? {
		var depth = 0
		var index = openingParenIndex

		while index < source.endIndex {
			switch source[index] {
			case "(":
				depth += 1
			case ")":
				depth -= 1
				if depth == 0 {
					return index
				}
			default:
				break
			}
			index = source.index(after: index)
		}

		return nil
	}

	private static func sanitize(source: String) -> String {
		enum State {
			case code
			case lineComment
			case blockComment(depth: Int)
			case string(hashCount: Int, multiline: Bool)
		}

		var sanitized = ""
		sanitized.reserveCapacity(source.count)
		var state = State.code
		var index = source.startIndex

		while index < source.endIndex {
			switch state {
			case .code:
				if hasPrefix("//", in: source, at: index) {
					sanitized += "  "
					index = source.index(index, offsetBy: 2)
					state = .lineComment
				} else if hasPrefix("/*", in: source, at: index) {
					sanitized += "  "
					index = source.index(index, offsetBy: 2)
					state = .blockComment(depth: 1)
				} else if let delimiter = stringDelimiterStart(in: source, at: index) {
					sanitized += String(repeating: " ", count: delimiter.length)
					index = source.index(index, offsetBy: delimiter.length)
					state = .string(hashCount: delimiter.hashCount, multiline: delimiter.multiline)
				} else {
					sanitized.append(source[index])
					index = source.index(after: index)
				}

			case .lineComment:
				if source[index] == "\n" {
					sanitized.append("\n")
					index = source.index(after: index)
					state = .code
				} else {
					sanitized.append(" ")
					index = source.index(after: index)
				}

			case let .blockComment(depth):
				if hasPrefix("/*", in: source, at: index) {
					sanitized += "  "
					index = source.index(index, offsetBy: 2)
					state = .blockComment(depth: depth + 1)
				} else if hasPrefix("*/", in: source, at: index) {
					sanitized += "  "
					index = source.index(index, offsetBy: 2)
					state = depth == 1 ? .code : .blockComment(depth: depth - 1)
				} else {
					sanitized.append(source[index] == "\n" ? "\n" : " ")
					index = source.index(after: index)
				}

			case let .string(hashCount, multiline):
				if let delimiterLength = stringDelimiterEnd(
					in: source,
					at: index,
					hashCount: hashCount,
					multiline: multiline,
				) {
					sanitized += String(repeating: " ", count: delimiterLength)
					index = source.index(index, offsetBy: delimiterLength)
					state = .code
				} else {
					sanitized.append(source[index] == "\n" ? "\n" : " ")
					index = source.index(after: index)
				}
			}
		}

		return sanitized
	}

	private struct StringDelimiter {
		let hashCount: Int
		let multiline: Bool
		let length: Int
	}

	private static func stringDelimiterStart(
		in source: String,
		at index: String.Index,
	) -> StringDelimiter? {
		var hashCount = 0
		var currentIndex = index

		while currentIndex < source.endIndex, source[currentIndex] == "#" {
			hashCount += 1
			currentIndex = source.index(after: currentIndex)
		}

		guard currentIndex < source.endIndex,
		      source[currentIndex] == "\""
		else {
			return nil
		}

		let multiline = hasPrefix("\"\"\"", in: source, at: currentIndex)
		return StringDelimiter(
			hashCount: hashCount,
			multiline: multiline,
			length: hashCount + (multiline ? 3 : 1),
		)
	}

	private static func stringDelimiterEnd(
		in source: String,
		at index: String.Index,
		hashCount: Int,
		multiline: Bool,
	) -> Int? {
		if multiline {
			guard hasPrefix("\"\"\"", in: source, at: index) else { return nil }
			if hashCount == 0 {
				guard !isEscapedQuote(in: source, at: index) else { return nil }
				return 3
			}
			let hashStart = source.index(index, offsetBy: 3)
			guard hasPrefix(String(repeating: "#", count: hashCount), in: source, at: hashStart) else {
				return nil
			}
			return hashCount + 3
		}

		guard source[index] == "\"" else { return nil }
		if hashCount == 0 {
			guard !isEscapedQuote(in: source, at: index) else { return nil }
			return 1
		}
		let hashStart = source.index(after: index)
		guard hasPrefix(String(repeating: "#", count: hashCount), in: source, at: hashStart) else {
			return nil
		}
		return hashCount + 1
	}

	private static func isEscapedQuote(in source: String, at index: String.Index) -> Bool {
		var backslashCount = 0
		var currentIndex = index

		while currentIndex > source.startIndex {
			let previousIndex = source.index(before: currentIndex)
			guard source[previousIndex] == "\\" else { break }
			backslashCount += 1
			currentIndex = previousIndex
		}

		return !backslashCount.isMultiple(of: 2)
	}

	private static func hasPrefix(
		_ prefix: String,
		in source: String,
		at index: String.Index,
	) -> Bool {
		source[index...].hasPrefix(prefix)
	}

	private static func skipWhitespace<S: StringProtocol>(
		in source: S,
		index: inout S.Index,
	) {
		while index < source.endIndex,
		      source[index].isWhitespace
		{
			index = source.index(after: index)
		}
	}

	private static func isIdentifierContinuation(_ character: Character) -> Bool {
		character == "_" || character.isLetter || character.isNumber
	}
}
