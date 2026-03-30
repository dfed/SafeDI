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
struct SafeDIGenerateDependencyTree: BuildToolPlugin {
	func createBuildCommands(
		context: PluginContext,
		target: Target,
	) async throws -> [Command] {
		guard let sourceTarget = target as? SourceModuleTarget else {
			return []
		}

		let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "SafeDIOutput")
		// Swift Package Plugins did not (as of Swift 5.9) allow for
		// creating dependencies between plugin output at the time of writing.
		// Since our current build system did not support depending on the
		// output of other plugins, we must forgo searching for `.safeDI` files
		// and instead parse the entire project at once.
		// TODO: https://github.com/dfed/SafeDI/issues/92
		let targetSwiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift").map(\.url)
		let dependenciesSourceFiles = sourceTarget
			.sourceModuleRecursiveDependencies
			.flatMap {
				$0
					.sourceFiles(withSuffix: ".swift")
					.map(\.url)
			}

		let allSwiftFiles = targetSwiftFiles + dependenciesSourceFiles
		let rootFiles = findFilesWithRoots(in: allSwiftFiles)
		guard !rootFiles.isEmpty else {
			return []
		}

		let outputFiles = rootFiles.map {
			outputDirectory.appending(path: outputFileName(for: $0))
		}

		let inputSourcesFile = context.pluginWorkDirectoryURL.appending(path: "InputSwiftFiles.csv")
		try allSwiftFiles
			.map { $0.path(percentEncoded: false) }
			.joined(separator: ",")
			.write(
				to: inputSourcesFile,
				atomically: true,
				encoding: .utf8,
			)

		let manifestFile = context.pluginWorkDirectoryURL.appending(path: "SafeDIManifest.json")
		try writeManifest(
			dependencyTreeInputFiles: rootFiles,
			outputDirectory: outputDirectory,
			to: manifestFile,
			relativeTo: context.package.directoryURL,
		)

		let arguments = [
			inputSourcesFile.path(percentEncoded: false),
			"--swift-manifest",
			manifestFile.path(percentEncoded: false),
		]

		let downloadedToolLocation = context.downloadedToolLocation
		let safeDIVersion = context.safeDIVersion
		if downloadedToolLocation == nil, let safeDIVersion {
			Diagnostics.warning("""
			Using a debug SafeDITool binary, which is 15x slower than the release version.

			To install the release SafeDITool binary for version \(safeDIVersion), run:
			\tswift package --package-path "\(context.package.directoryURL.path(percentEncoded: false))" --allow-network-connections all --allow-writing-to-package-directory safedi-release-install
			""")
		}

		let toolLocation = if let downloadedToolLocation {
			downloadedToolLocation
		} else {
			try context.tool(named: "SafeDITool").url
		}

		return [
			.buildCommand(
				displayName: "SafeDIGenerateDependencyTree",
				executable: toolLocation,
				arguments: arguments,
				environment: [:],
				inputFiles: allSwiftFiles,
				outputFiles: outputFiles,
			),
		]
	}
}

extension Target {
	var sourceModuleRecursiveDependencies: [SwiftSourceModuleTarget] {
		recursiveTargetDependencies.compactMap { target in
			// Since we only understand Swift files, we only care about SwiftSourceModuleTargets.
			guard let swiftModule = target as? SwiftSourceModuleTarget else {
				return nil
			}

			// We only care about first-party code. Ignore third-party dependencies.
			guard swiftModule
				.directoryURL
				.pathComponents
				// Removing the module name.
				.dropLast()
				// Removing 'Sources'.
				.dropLast(ifEquals: "Sources")
				// Removing the package name.
				.dropLast()
				.last != "checkouts"
			else {
				return nil
			}
			return swiftModule
		}
	}
}

#if canImport(XcodeProjectPlugin)
	import XcodeProjectPlugin

	extension SafeDIGenerateDependencyTree: XcodeBuildToolPlugin {
		func createBuildCommands(
			context: XcodeProjectPlugin.XcodePluginContext,
			target: XcodeProjectPlugin.XcodeTarget,
		) throws -> [PackagePlugin.Command] {
			// As of Xcode 15.0.1, Swift Package Plugins in Xcode are unable
			// to inspect target dependencies. As a result, this Xcode plugin
			// only works if it is running on a single-module project, or if
			// all `@Instantiable`-decorated types are in the target module,
			// or if a @SafeDIConfiguration type's `additionalDirectoriesToInclude`
			// directs the plugin to search additional modules for Swift files.
			// https://github.com/apple/swift-package-manager/issues/6003
			let inputSwiftFiles = target
				.inputFiles
				.filter { $0.url.pathExtension == "swift" }
				.map(\.url)
			guard !inputSwiftFiles.isEmpty else {
				// There are no Swift files in this module!
				return []
			}

			let rootFiles = findFilesWithRoots(in: inputSwiftFiles)
			guard !rootFiles.isEmpty else {
				return []
			}

			let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "SafeDIOutput")
			let outputFiles = rootFiles.map {
				outputDirectory.appending(path: outputFileName(for: $0))
			}

			let inputSourcesFile = context.pluginWorkDirectoryURL.appending(path: "InputSwiftFiles.csv")
			try inputSwiftFiles
				.map { $0.path(percentEncoded: false) }
				.joined(separator: ",")
				.write(
					to: inputSourcesFile,
					atomically: true,
					encoding: .utf8,
				)

			let manifestFile = context.pluginWorkDirectoryURL.appending(path: "SafeDIManifest.json")
			try writeManifest(
				dependencyTreeInputFiles: rootFiles,
				outputDirectory: outputDirectory,
				to: manifestFile,
				relativeTo: context.pluginWorkDirectoryURL,
			)

			let arguments = [
				inputSourcesFile.path(percentEncoded: false),
				"--swift-manifest",
				manifestFile.path(percentEncoded: false),
			]

			let downloadedToolLocation = context.downloadedToolLocation
			if downloadedToolLocation == nil {
				Diagnostics.warning("""
				Using a debug SafeDITool binary, which is 15x slower than the release version.

				To install the release SafeDITool binary for this version, run the `InstallSafeDITool` command plugin.
				""")
			}
			let toolLocation = if let downloadedToolLocation {
				downloadedToolLocation
			} else {
				try context.tool(named: "SafeDITool").url
			}

			return [
				.buildCommand(
					displayName: "SafeDIGenerateDependencyTree",
					executable: toolLocation,
					arguments: arguments,
					environment: [:],
					inputFiles: inputSwiftFiles,
					outputFiles: outputFiles,
				),
			]
		}
	}
#endif

extension Array where Element: Equatable {
	public func dropLast(ifEquals value: Element) -> [Element] {
		if last == value {
			dropLast()
		} else {
			self
		}
	}
}
