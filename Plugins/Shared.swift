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
import PackagePlugin

#if canImport(XcodeProjectPlugin)
	import XcodeProjectPlugin

	extension XcodeProjectPlugin.XcodePluginContext {
		var safeDIVersion: String {
			// As of Xcode 15.0, Xcode command plugins have no way to read the package manifest, therefore we must hardcode the version number.
			// It is okay for this number to be behind the most current release if the inputs and outputs to SafeDITool have not changed.
			// Unlike SPM plugins, Xcode plugins can not determine the current version number, so we must hardcode it.
			"2.0.0"
		}

		var safeDIOrigin: URL {
			// As of Xcode 15.0, Xcode command plugins have no way to read the package manifest, therefore we must hardcode the package.
			// This means that forks of this repository must update this URL manually to ensure their own release binary is downloaded by this tool.
			URL(string: "https://github.com/dfed/SafeDI")!
		}

		var safediFolder: URL {
			xcodeProject.directoryURL.appending(
				component: ".safedi",
			)
		}

		var expectedToolFolder: URL {
			safediFolder.appending(
				component: safeDIVersion,
			)
		}

		var expectedToolLocation: URL {
			expectedToolFolder.appending(
				component: "safeditool",
			)
		}

		var downloadedToolLocation: URL? {
			guard FileManager.default.fileExists(atPath: expectedToolLocation.path(percentEncoded: false)) else { return nil }
			return expectedToolLocation
		}
	}
#endif

extension PackagePlugin.PluginContext {
	var safeDIVersion: String? {
		guard let safeDIOrigin = package.dependencies.first(where: { $0.package.displayName == "SafeDI" })?.package.origin else {
			return nil
		}
		switch safeDIOrigin {
		case let .repository(_, displayVersion, _):
			// As of Xcode 16.0 Beta 6, the display version is of the form "Optional(version)".
			// This regular expression is duplicated by SafeDIGenerateDependencyTree since plugins can not share code.
			guard let versionMatch = try? /Optional\((.*?)\)|^(.*?)$/.firstMatch(in: displayVersion),
			      let version = versionMatch.output.1 ?? versionMatch.output.2
			else {
				return nil
			}
			return String(version)
		case .registry, .root, .local:
			fallthrough
		@unknown default:
			return nil
		}
	}

	var safediFolder: URL {
		package.directoryURL.appending(
			component: ".safedi",
		)
	}

	var expectedToolFolder: URL? {
		guard let safeDIVersion else { return nil }
		return safediFolder.appending(
			component: safeDIVersion,
		)
	}

	var expectedToolLocation: URL? {
		guard let expectedToolFolder else { return nil }
		return expectedToolFolder.appending(
			component: "safeditool",
		)
	}

	var downloadedToolLocation: URL? {
		guard let expectedToolLocation,
		      FileManager.default.fileExists(atPath: expectedToolLocation.path(percentEncoded: false))
		else { return nil }
		return expectedToolLocation
	}
}

/// Find Swift files that contain `@Instantiable(isRoot: true)` declarations.
func findFilesWithRoots(in swiftFiles: [URL]) -> [URL] {
	swiftFiles.filter { fileURL in
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
		guard content.contains("isRoot") else { return false }
		guard let regex = try? Regex(#"@Instantiable\s*\([^)]*isRoot\s*:\s*true[^)]*\)"#) else { return false }
		// Check each match is not inside a comment or backtick-quoted code span.
		for match in content.matches(of: regex) {
			let lineStart = content[content.startIndex..<match.range.lowerBound].lastIndex(of: "\n").map { content.index(after: $0) } ?? content.startIndex
			let linePrefix = content[lineStart..<match.range.lowerBound]
			// Skip matches inside single-line comments.
			if linePrefix.contains("//") { continue }
			// Skip matches inside backtick-quoted code spans.
			if linePrefix.contains("`") { continue }
			return true
		}
		return false
	}
}

/// Derive the output filename for a dependency tree generated from an input Swift file.
func outputFileName(for inputURL: URL) -> String {
	let baseName = inputURL.deletingPathExtension().lastPathComponent
	return "\(baseName)+SafeDI.swift"
}

/// Write a SafeDIToolManifest JSON file mapping input file paths to output file paths.
func writeManifest(
	dependencyTreeInputFiles: [URL],
	outputDirectory: URL,
	to manifestURL: URL,
) throws {
	var dependencyTreeGeneration = [String: String]()
	for inputURL in dependencyTreeInputFiles {
		let inputPath = inputURL.path(percentEncoded: false)
		let outputPath = outputDirectory.appending(path: outputFileName(for: inputURL)).path(percentEncoded: false)
		dependencyTreeGeneration[inputPath] = outputPath
	}
	let manifest = ["dependencyTreeGeneration": dependencyTreeGeneration]
	let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
	try data.write(to: manifestURL)
}
