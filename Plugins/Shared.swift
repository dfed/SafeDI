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

/// Find the unqualified type names of all `@Instantiable(isRoot: true)` declarations in the given Swift files.
func findRootTypeNames(in swiftFiles: [URL]) -> [String] {
	var rootTypeNames = [String]()
	for fileURL in swiftFiles {
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
		guard content.contains("isRoot") else { continue }
		// Find @Instantiable(...isRoot: true...) occurrences.
		guard let instantiableRootRegex = try? Regex(#"@Instantiable\s*\([^)]*isRoot\s*:\s*true[^)]*\)"#) else { continue }
		// Find the type declaration keyword and name following the macro.
		guard let typeDeclRegex = try? Regex(#"(?:class|struct|actor)\s+(\w+)"#) else { continue }
		for match in content.matches(of: instantiableRootRegex) {
			let afterMacro = content[match.range.upperBound...]
			if let typeMatch = afterMacro.firstMatch(of: typeDeclRegex),
			   let nameRange = typeMatch.output[1].range
			{
				rootTypeNames.append(String(content[nameRange]))
			}
		}
	}
	return rootTypeNames
}

/// Compute output file names for a list of root type names, handling collisions with count suffixes.
/// Both the plugin and the SafeDITool must use the same convention to agree on output file names.
func outputFileNames(for rootTypeNames: [String]) -> [String] {
	let sorted = rootTypeNames.sorted()
	var nameCount = [String: Int]()
	for name in sorted {
		nameCount[name, default: 0] += 1
	}
	var nameIndex = [String: Int]()
	return sorted.map { name in
		let index = nameIndex[name, default: 0]
		nameIndex[name] = index + 1
		if index == 0 {
			return "\(name)+SafeDI.swift"
		} else {
			return "\(name)\(index + 1)+SafeDI.swift"
		}
	}
}
