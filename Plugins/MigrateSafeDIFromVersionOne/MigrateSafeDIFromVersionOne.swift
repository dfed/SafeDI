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

@main
struct MigrateSafeDIFromVersionOne: CommandPlugin {
	func performCommand(
		context: PackagePlugin.PluginContext,
		arguments: [String],
	) throws {
		// Parse --target argument.
		guard let targetIndex = arguments.firstIndex(of: "--target"),
		      arguments.index(after: targetIndex) < arguments.endIndex
		else {
			let availableTargets = context.package.targets.map(\.name).joined(separator: ", ")
			Diagnostics.error("Missing required --target argument. Available targets: \(availableTargets)")
			return
		}
		let targetName = arguments[arguments.index(after: targetIndex)]

		guard let target = context.package.targets.first(where: { $0.name == targetName }) else {
			let availableTargets = context.package.targets.map(\.name).joined(separator: ", ")
			Diagnostics.error("Target '\(targetName)' not found. Available targets: \(availableTargets)")
			return
		}

		// Validate swift-tools-version >= 6.3.
		let packageSwiftURL = context.package.directoryURL.appending(component: "Package.swift")
		let packageSwiftContents = try String(contentsOf: packageSwiftURL, encoding: .utf8)
		guard let firstLine = packageSwiftContents.components(separatedBy: .newlines).first,
		      let versionMatch = try? /swift-tools-version:\s*(\d+)\.(\d+)/.firstMatch(in: firstLine),
		      let major = Int(versionMatch.output.1),
		      let minor = Int(versionMatch.output.2)
		else {
			Diagnostics.error("Could not parse swift-tools-version from Package.swift")
			return
		}
		guard major > 6 || (major == 6 && minor >= 3) else {
			Diagnostics.error("SafeDI 2.x requires swift-tools-version 6.3 or later. Found \(major).\(minor). Update your Package.swift before migrating.")
			return
		}

		let targetDirectoryURL = target.directoryURL
		let safediFolder = context.package.directoryURL.appending(component: ".safedi")
		let configurationFolder = safediFolder.appending(component: "configuration")

		// Check for existing #SafeDIConfiguration in target sources.
		let existingConfigurationFile = findExistingSafeDIConfiguration(in: targetDirectoryURL)

		// Read CSV files if they exist.
		let includeCSV = configurationFolder.appending(component: "include.csv")
		let additionalImportedModulesCSV = configurationFolder.appending(component: "additionalImportedModules.csv")
		let includeValues = readCSV(at: includeCSV)
		let additionalImportedModulesValues = readCSV(at: additionalImportedModulesCSV)

		// Create SafeDIConfiguration.swift if one doesn't already exist.
		if let existingConfigurationFile {
			Diagnostics.warning("#SafeDIConfiguration already exists at \(existingConfigurationFile.path(percentEncoded: false)). Skipping file creation.")
			if includeValues != nil || additionalImportedModulesValues != nil {
				Diagnostics.warning("CSV configuration files were found but a #SafeDIConfiguration file already exists. Please manually migrate CSV values into your existing #SafeDIConfiguration and delete the CSV files.")
			}
		} else {
			let configurationFileContent = generateSafeDIConfigurationFile(
				additionalImportedModules: additionalImportedModulesValues ?? [],
				additionalDirectoriesToInclude: includeValues ?? [],
			)
			let outputURL = targetDirectoryURL.appending(component: "SafeDIConfiguration.swift")
			try configurationFileContent.write(
				to: outputURL,
				atomically: true,
				encoding: .utf8,
			)
			Diagnostics.remark("Created \(outputURL.path(percentEncoded: false))")

			// Only delete CSV files when we successfully created the new configuration file.
			// If an existing #SafeDIConfiguration was found, the user must manually migrate
			// and delete the CSV files themselves.
			var deletedCSVFiles = [String]()
			if includeValues != nil {
				try FileManager.default.removeItem(at: includeCSV)
				deletedCSVFiles.append(includeCSV.path(percentEncoded: false))
			}
			if additionalImportedModulesValues != nil {
				try FileManager.default.removeItem(at: additionalImportedModulesCSV)
				deletedCSVFiles.append(additionalImportedModulesCSV.path(percentEncoded: false))
			}
			if !deletedCSVFiles.isEmpty {
				Diagnostics.remark("Deleted CSV configuration files: \(deletedCSVFiles.joined(separator: ", "))")
			}
		}
	}

	// MARK: Private

	private func findExistingSafeDIConfiguration(in directoryURL: URL) -> URL? {
		guard let enumerator = FileManager.default.enumerator(
			at: directoryURL,
			includingPropertiesForKeys: nil,
			options: [.skipsHiddenFiles],
		) else {
			return nil
		}
		for case let fileURL as URL in enumerator {
			guard fileURL.pathExtension == "swift" else { continue }
			guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
			if contents.contains("#SafeDIConfiguration") || contents.contains("@SafeDIConfiguration") {
				return fileURL
			}
		}
		return nil
	}

	private func readCSV(at url: URL) -> [String]? {
		guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
		      let contents = try? String(contentsOf: url, encoding: .utf8)
		else {
			return nil
		}
		return contents
			.components(separatedBy: CharacterSet(arrayLiteral: ","))
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
	}

	private func generateSafeDIConfigurationFile(
		additionalImportedModules: [String],
		additionalDirectoriesToInclude: [String],
	) -> String {
		var arguments = [String]()
		if !additionalImportedModules.isEmpty {
			let formatted = additionalImportedModules.map { "\"\($0)\"" }.joined(separator: ", ")
			arguments.append("\tadditionalImportedModules: [\(formatted)]")
		}
		if !additionalDirectoriesToInclude.isEmpty {
			let formatted = additionalDirectoriesToInclude.map { "\"\($0)\"" }.joined(separator: ", ")
			arguments.append("\tadditionalDirectoriesToInclude: [\(formatted)]")
		}
		if arguments.isEmpty {
			return """
			import SafeDI

			#SafeDIConfiguration()
			"""
		} else {
			return """
			import SafeDI

			#SafeDIConfiguration(
			\(arguments.joined(separator: ",\n"))
			)
			"""
		}
	}
}
