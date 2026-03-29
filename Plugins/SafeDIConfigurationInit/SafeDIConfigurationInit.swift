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
struct SafeDIConfigurationInit: CommandPlugin {
	func performCommand(
		context: PackagePlugin.PluginContext,
		arguments: [String]
	) throws {
		var argumentExtractor = ArgumentExtractor(arguments)
		let targetArguments = argumentExtractor.extractOption(named: "target")
		let target: Target
		if let targetName = targetArguments.first {
			guard let matchingTarget = try context.package.targets(named: [targetName]).first else {
				Diagnostics.error("No target named '\(targetName)' found in package")
				return
			}
			target = matchingTarget
		} else {
			guard let firstTarget = context.package.targets.first(where: { $0 is SourceModuleTarget }) else {
				Diagnostics.error("No source module target found in package")
				return
			}
			target = firstTarget
		}

		let outputURL = context.package.directoryURL.appending(components: "Sources", target.name, "SafeDIConfiguration.swift")
		try writeConfigurationFile(to: outputURL)
		Diagnostics.remark("Created SafeDIConfiguration.swift in \(target.name)")
	}
}

#if canImport(XcodeProjectPlugin)
	import XcodeProjectPlugin

	extension SafeDIConfigurationInit: XcodeCommandPlugin {
		func performCommand(
			context: XcodeProjectPlugin.XcodePluginContext,
			arguments: [String]
		) throws {
			var argumentExtractor = ArgumentExtractor(arguments)
			let targetArguments = argumentExtractor.extractOption(named: "target")
			let target: XcodeTarget
			if let targetName = targetArguments.first {
				guard let matchingTarget = context.xcodeProject.targets.first(where: { $0.displayName == targetName }) else {
					Diagnostics.error("No target named '\(targetName)' found in project")
					return
				}
				target = matchingTarget
			} else {
				guard let firstTarget = context.xcodeProject.targets.first else {
					Diagnostics.error("No target found in project")
					return
				}
				target = firstTarget
			}

			let outputURL = context.xcodeProject.directoryURL.appending(components: target.displayName, "SafeDIConfiguration.swift")
			try writeConfigurationFile(to: outputURL)
			Diagnostics.remark("Created SafeDIConfiguration.swift in \(target.displayName)")
		}
	}
#endif

private func writeConfigurationFile(to outputURL: URL) throws {
	guard !FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
		Diagnostics.error("SafeDIConfiguration.swift already exists at \(outputURL.path(percentEncoded: false)). To reconfigure SafeDI, edit the existing file.")
		return
	}

	try configurationFileContent.write(
		to: outputURL,
		atomically: true,
		encoding: .utf8
	)
}

private let configurationFileContent = """
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

import SafeDI

@SafeDIConfiguration
enum SafeDIConfiguration {
\t/// The names of modules to import in the generated dependency tree.
\t/// This list is in addition to the import statements found in files that declare @Instantiable types.
\tstatic let additionalImportedModules: [StaticString] = []

\t/// Directories containing Swift files to include, relative to the executing directory.
\t/// This property only applies to SafeDI repos that utilize the SPM plugin via an Xcode project.
\tstatic let additionalDirectoriesToInclude: [StaticString] = []
}

"""
