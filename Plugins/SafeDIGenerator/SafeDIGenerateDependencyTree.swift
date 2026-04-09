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

		let tool = try context.tool(named: "SafeDITool").url
		let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "SafeDIOutput")
		let targetSwiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift").map(\.url)
		let dependenciesSourceFiles = sourceTarget
			.sourceModuleRecursiveDependencies
			.flatMap {
				$0
					.sourceFiles(withSuffix: ".swift")
					.map(\.url)
			}

		let allSwiftFiles = targetSwiftFiles + dependenciesSourceFiles
		let packageRoot = context.package.directoryURL
		let inputSourcesFile = context.pluginWorkDirectoryURL.appending(path: "InputSwiftFiles.csv")
		try writeInputSwiftFilesCSV(
			allSwiftFiles,
			relativeTo: packageRoot,
			to: inputSourcesFile,
		)

		let manifestFile = context.pluginWorkDirectoryURL.appending(path: "SafeDIManifest.json")

		// Shell out to SafeDITool scan to build the manifest.
		try runSafeDITool(
			at: tool,
			arguments: [
				"scan",
				"--input-sources-file", inputSourcesFile.path(percentEncoded: false),
				"--project-root", packageRoot.path(percentEncoded: false),
				"--output-directory", outputDirectory.path(percentEncoded: false),
				"--manifest-file", manifestFile.path(percentEncoded: false),
				"--mock-scoped-files",
			] + targetSwiftFiles.map { $0.path(percentEncoded: false) },
		)

		let manifest = try JSONDecoder().decode(
			ScanManifest.self,
			from: Data(contentsOf: manifestFile),
		)

		let outputFiles = (manifest.dependencyTreeGeneration + manifest.mockGeneration)
			.map { URL(fileURLWithPath: $0.outputFilePath) }
			+ (manifest.mockConfigurationOutputFilePath.map { [URL(fileURLWithPath: $0)] } ?? [])
		let additionalInputFiles = manifest.additionalInputFiles.map { URL(fileURLWithPath: $0) }

		guard !outputFiles.isEmpty else {
			return []
		}

		return [
			.buildCommand(
				displayName: "SafeDIGenerateDependencyTree",
				executable: tool,
				arguments: [
					inputSourcesFile.path(percentEncoded: false),
					"--swift-manifest",
					manifestFile.path(percentEncoded: false),
				],
				environment: [:],
				inputFiles: allSwiftFiles + additionalInputFiles,
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
			let tool = try context.tool(named: "SafeDITool").url
			let inputSwiftFiles = target
				.inputFiles
				.filter { $0.url.pathExtension == "swift" }
				.map(\.url)
			guard !inputSwiftFiles.isEmpty else {
				return []
			}

			let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "SafeDIOutput")
			let projectRoot = context.xcodeProject.directoryURL
			let inputSourcesFile = context.pluginWorkDirectoryURL.appending(path: "InputSwiftFiles.csv")
			try writeInputSwiftFilesCSV(
				inputSwiftFiles,
				relativeTo: projectRoot,
				to: inputSourcesFile,
			)

			// In Xcode, context.tool(named:) returns paths with unresolved build
			// variables (e.g. ${BUILD_DIR}/${CONFIGURATION}/SafeDITool) that are only
			// valid at build-command execution time, not during createBuildCommands.
			// Use a single prebuild command that lets SafeDITool scan and generate
			// in one pass via the --output-directory flag.
			return [
				.prebuildCommand(
					displayName: "SafeDIGenerateDependencyTree",
					executable: tool,
					arguments: [
						inputSourcesFile.path(percentEncoded: false),
						"--output-directory", outputDirectory.path(percentEncoded: false),
						"--mock-scoped-files",
					] + inputSwiftFiles.map { $0.path(percentEncoded: false) },
					outputFilesDirectory: outputDirectory,
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
