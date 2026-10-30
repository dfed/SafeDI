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
		guard let sourceTarget = target as? SwiftSourceModuleTarget else {
			return []
		}
		// The target's active compilation conditions (`-D` flags from `swiftSettings`
		// and traits, resolved for the current configuration) are all a plugin can see
		// while it plans the build. `scan` decides which files to generate with them.
		// SwiftPM's implicit `DEBUG` is not among them, and Xcode reports debug-configuration
		// defines in Release too, so `generate` replaces them with the conditions the build
		// settings report when the build system expands them (see
		// `buildSettingCompilationConditionArguments`).
		let activeCompilationConditionArguments = activeCompilationConditionArguments(sourceTarget.compilationConditions)

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
		// Every form of the `generate` command below reads it, to record the module and package that declare each file.
		try writeTargetGraph(
			of: sourceTarget,
			dependencyTargets: sourceTarget.sourceModuleRecursiveDependencies,
			in: context.package,
			besideInputSourcesFile: inputSourcesFile,
		)

		let manifestFile = context.pluginWorkDirectoryURL.appending(path: "SafeDIManifest.json")

		// Try to shell out to SafeDITool to build the manifest. When Xcode
		// builds an SPM package, context.tool(named:) may return a path with
		// unresolved build variables (e.g. /${BUILD_DIR}/${CONFIGURATION}/SafeDITool)
		// that cannot be executed during createBuildCommands. In that case, fall
		// back to the lightweight in-process PluginScanner.
		do {
			try runSafeDITool(
				at: tool,
				arguments: [
					"scan",
					"--input-sources-file", inputSourcesFile.path(percentEncoded: false),
					"--project-root", packageRoot.path(percentEncoded: false),
					"--output-directory", outputDirectory.path(percentEncoded: false),
					"--manifest-file", manifestFile.path(percentEncoded: false),
					"--mock-scoped-files",
				] + targetSwiftFiles.map { $0.path(percentEncoded: false) }
					+ activeCompilationConditionArguments,
			)
		} catch let error as SafeDIToolLaunchError {
			Diagnostics.warning(
				"SafeDITool could not be launched while planning this target’s build (\(error)), so SafeDI planned "
					+ "the target’s generated files with a simpler scanner instead. The build continues, and may include "
					+ "generated files that contain no code.",
			)
			return try createBuildCommandsWithPluginScanner(
				tool: tool,
				targetSwiftFiles: targetSwiftFiles,
				allSwiftFiles: allSwiftFiles,
				packageRoot: packageRoot,
				inputSourcesFile: inputSourcesFile,
				outputDirectory: outputDirectory,
				activeCompilationConditionArguments: activeCompilationConditionArguments,
			)
		}

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
				]
					// The manifest already records these conditions, but it is neither an argument nor an
					// input of this command. Repeating them here changes the command when they change, so a
					// build in another configuration regenerates instead of reusing the previous output.
					+ activeCompilationConditionArguments
					+ buildSettingCompilationConditionArguments,
				environment: [:],
				inputFiles: allSwiftFiles + additionalInputFiles,
				outputFiles: outputFiles,
			),
		]
	}

	/// Fallback when SafeDITool cannot be executed during plugin setup.
	/// Uses lightweight in-process scanning to discover output files, then
	/// returns a build command that does the full scan+generate at build time
	/// via the --output-directory flag.
	private func createBuildCommandsWithPluginScanner(
		tool: URL,
		targetSwiftFiles: [URL],
		allSwiftFiles: [URL],
		packageRoot: URL,
		inputSourcesFile: URL,
		outputDirectory: URL,
		activeCompilationConditionArguments: [String],
	) throws -> [Command] {
		let scanResult = PluginScanner.scan(
			swiftFiles: allSwiftFiles,
			mockScopedSwiftFiles: targetSwiftFiles,
			relativeTo: packageRoot,
			outputDirectory: outputDirectory,
		)

		guard !scanResult.outputFiles.isEmpty else {
			return []
		}

		return [
			.buildCommand(
				displayName: "SafeDIGenerateDependencyTree",
				executable: tool,
				arguments: [
					inputSourcesFile.path(percentEncoded: false),
					"--output-directory", outputDirectory.path(percentEncoded: false),
					"--mock-scoped-files",
				] + targetSwiftFiles.map { $0.path(percentEncoded: false) }
					+ activeCompilationConditionArguments
					+ buildSettingCompilationConditionArguments,
				environment: [:],
				inputFiles: allSwiftFiles + scanResult.additionalInputFiles,
				outputFiles: scanResult.outputFiles,
			),
		]
	}

	/// The `--active-compilation-conditions` arguments for `conditions`, or none when there
	/// are no conditions: the option requires at least one value.
	private func activeCompilationConditionArguments(_ conditions: [String]) -> [String] {
		if conditions.isEmpty {
			[]
		} else {
			["--active-compilation-conditions"] + conditions
		}
	}
}

/// Arguments that let SafeDITool read the compilation conditions the compiler receives.
///
/// Build tool plugins cannot read those conditions while they plan the build. These arguments name
/// build settings instead: Swift Build, which runs plugin commands for Xcode and for SwiftPM's
/// `swiftbuild` backend, expands `${…}` references in a command's arguments to the target's settings
/// when the command runs, and Xcode project builds run each plugin command through a shell script
/// that does the same. SwiftPM's native backend passes the references through unexpanded, and
/// SafeDITool then falls back to the conditions this plugin reported. The `=` form keeps a value that
/// starts with `-` from parsing as an option, and the brackets keep an empty setting from reading as
/// a missing value. The braced form matters: the shell treats `$(…)` as a command to run.
let buildSettingCompilationConditionArguments = [
	"--build-setting-active-compilation-conditions=[${SWIFT_ACTIVE_COMPILATION_CONDITIONS}]",
	"--build-setting-other-swift-flags=[${OTHER_SWIFT_FLAGS}]",
]

/// Writes `swiftFiles` to `inputSourcesFile` as SafeDITool reads its input CSV, each relative to `base` when it lies
/// inside it. `NormalizedFilePath` comes from SafeDICore's `FilePathSpelling.swift`, which this plugin compiles
/// through a symbolic link.
func writeInputSwiftFilesCSV(
	_ swiftFiles: [URL],
	relativeTo base: URL,
	to inputSourcesFile: URL,
) throws {
	let normalizedBase = NormalizedFilePath(base.path(percentEncoded: false))
	try swiftFiles
		.map { NormalizedFilePath($0.path(percentEncoded: false)).path(relativeTo: normalizedBase) }
		.joined(separator: ",")
		.write(
			to: inputSourcesFile,
			atomically: true,
			encoding: .utf8,
		)
}

/// Writes the target graph of `target`, whose input CSV lists its own files and those of `dependencyTargets`, beside
/// `inputSourcesFile`, for `generate` to read the module and package that declare each file.
///
/// The plugin API reports which package declares a target only by listing the package's targets, so each target's
/// package is found among `package` and the packages it depends on, directly or through another. The API does not
/// report which plugins a target applies, so the graph does not say whether a dependency target applies this one.
func writeTargetGraph(
	of target: SwiftSourceModuleTarget,
	dependencyTargets: [SwiftSourceModuleTarget],
	in package: Package,
	besideInputSourcesFile inputSourcesFile: URL,
) throws {
	var packageIDsByTargetID = [String: Package.ID]()
	var visitedPackageIDs = Set<Package.ID>()
	var packagesToVisit = [package]
	while let packageToVisit = packagesToVisit.popLast() {
		if visitedPackageIDs.insert(packageToVisit.id).inserted {
			for packageTarget in packageToVisit.targets {
				packageIDsByTargetID[packageTarget.id] = packageToVisit.id
			}
			packagesToVisit += packageToVisit.dependencies.map(\.package)
		}
	}
	func moduleName(of target: any Target) -> String {
		(target as? any SourceModuleTarget)?.moduleName ?? target.name
	}
	func graphTarget(_ target: SwiftSourceModuleTarget) -> TargetGraph.Target {
		TargetGraph.Target(
			moduleName: target.moduleName,
			packageID: packageIDsByTargetID[target.id],
			directoryPath: target.directoryURL.path(percentEncoded: false),
			dependencyModuleNames: Set(target.dependencies.flatMap { dependency in
				switch dependency {
				case let .target(dependencyTarget):
					[moduleName(of: dependencyTarget)]
				case let .product(product):
					product.targets.map(moduleName(of:))
				@unknown default:
					[String]()
				}
			}).sorted(),
		)
	}
	let targetGraph = TargetGraph(
		target: graphTarget(target),
		dependencyTargets: dependencyTargets.map(graphTarget).sorted {
			($0.moduleName, $0.packageID ?? "", $0.directoryPath) < ($1.moduleName, $1.packageID ?? "", $1.directoryPath)
		},
	)
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	try encoder.encode(targetGraph).write(
		to: URL(fileURLWithPath: inputSourcesFile.path(percentEncoded: false) + TargetGraph.fileNameSuffix),
		options: .atomic,
	)
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
			// Prefer the user-downloaded prebuilt tool at
			// `.safedi/<version>/safeditool` when available AND runnable on
			// this host. The SPM-provided tool path arrives as
			// `${BUILD_DIR}/${CONFIGURATION}/SafeDITool` in Xcode, which
			// can't be executed at plugin-setup time and forces the
			// regex-based PluginScanner fallback. Verifying runnability
			// avoids trusting a cached binary that can't actually launch
			// (wrong platform, corrupted, missing exec bit).
			let tool: URL
			let runsRealScan: Bool
			if let downloaded = verifiedDownloadedToolLocation(context.downloadedToolLocation, expectedVersion: context.safeDIVersion) {
				tool = downloaded
				runsRealScan = true
			} else {
				tool = try context.tool(named: "SafeDITool").url
				runsRealScan = false
				Diagnostics.warning("""
				SafeDI is planning this target’s generated files with a simpler scanner, \
				because Xcode does not give build plugins a runnable SafeDITool. To install \
				the prebuilt SafeDITool \(context.safeDIVersion), right-click the project \
				in Xcode and choose SafeDI → Safedi Release Install.
				""")
			}
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

			let manifestFile = context.pluginWorkDirectoryURL.appending(path: "SafeDIManifest.json")

			// With a downloaded prebuilt tool we can invoke the real scan
			// subcommand, which produces an authoritative manifest.
			// `buildCommandsUsingRealScan` returns nil on a recoverable
			// launch failure (wrong platform, corrupted binary) — in that
			// case we fall back to the lightweight in-process `PluginScanner`.
			// SafeDITool process-level errors (parse / validation failures)
			// bubble up from the helper without masking.
			if runsRealScan,
			   let commands = try buildCommandsUsingRealScan(
			   	tool: tool,
			   	inputSwiftFiles: inputSwiftFiles,
			   	inputSourcesFile: inputSourcesFile,
			   	projectRoot: projectRoot,
			   	outputDirectory: outputDirectory,
			   	manifestFile: manifestFile,
			   )
			{
				return commands
			} else {
				return buildCommandsUsingPluginScanner(
					tool: tool,
					inputSwiftFiles: inputSwiftFiles,
					inputSourcesFile: inputSourcesFile,
					projectRoot: projectRoot,
					outputDirectory: outputDirectory,
				)
			}
		}

		private func buildCommandsUsingRealScan(
			tool: URL,
			inputSwiftFiles: [URL],
			inputSourcesFile: URL,
			projectRoot: URL,
			outputDirectory: URL,
			manifestFile: URL,
		) throws -> [PackagePlugin.Command]? {
			do {
				try runSafeDITool(
					at: tool,
					arguments: [
						"scan",
						"--input-sources-file", inputSourcesFile.path(percentEncoded: false),
						"--project-root", projectRoot.path(percentEncoded: false),
						"--output-directory", outputDirectory.path(percentEncoded: false),
						"--manifest-file", manifestFile.path(percentEncoded: false),
						"--mock-scoped-files",
					] + inputSwiftFiles.map { $0.path(percentEncoded: false) },
				)
			} catch let error as SafeDIToolLaunchError {
				// Binary couldn't launch (wrong platform, corrupted, etc).
				// Signal to the caller that the PluginScanner fallback
				// should run by returning nil. SafeDIToolProcessError
				// (scan exited non-zero — parse/validation error) is not
				// caught here; it propagates so real errors surface
				// instead of being masked by a regex-based fallback.
				Diagnostics.warning("The SafeDITool binary in .safedi/ could not be launched (\(error)), so SafeDI planned this target’s generated files with a simpler scanner. To reinstall it, right-click the project in Xcode and choose SafeDI → Safedi Release Install.")
				return nil
			}
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
					] + buildSettingCompilationConditionArguments,
					environment: [:],
					inputFiles: inputSwiftFiles + additionalInputFiles,
					outputFiles: outputFiles,
				),
			]
		}

		private func buildCommandsUsingPluginScanner(
			tool: URL,
			inputSwiftFiles: [URL],
			inputSourcesFile: URL,
			projectRoot: URL,
			outputDirectory: URL,
		) -> [PackagePlugin.Command] {
			let scanResult = PluginScanner.scan(
				swiftFiles: inputSwiftFiles,
				mockScopedSwiftFiles: inputSwiftFiles,
				relativeTo: projectRoot,
				outputDirectory: outputDirectory,
			)
			guard !scanResult.outputFiles.isEmpty else {
				return []
			}
			return [
				.buildCommand(
					displayName: "SafeDIGenerateDependencyTree",
					executable: tool,
					arguments: [
						inputSourcesFile.path(percentEncoded: false),
						"--output-directory", outputDirectory.path(percentEncoded: false),
						"--mock-scoped-files",
					] + inputSwiftFiles.map { $0.path(percentEncoded: false) }
						+ buildSettingCompilationConditionArguments,
					environment: [:],
					inputFiles: inputSwiftFiles + scanResult.additionalInputFiles,
					outputFiles: scanResult.outputFiles,
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
