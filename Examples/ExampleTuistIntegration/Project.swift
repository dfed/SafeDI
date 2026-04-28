import Foundation
import ProjectDescription

// MARK: - Input globs

// Tuist expands these glob patterns at `tuist generate` time, baking a
// literal file list into the .xcodeproj. Adding or removing a `.swift`
// source is a `tuist generate` away; nothing in this manifest or in
// `Scripts/generate-safedi.sh` needs a hand edit.
let subprojectSources: [FileListGlob] = [
	"Subproject/**/*.swift",
]

let hostSources: [FileListGlob] = [
	"ExampleTuistIntegration/**/*.swift",
]

// Each target emits a `<TargetName>.safedi` module-info artifact that
// downstream targets consume to build their dependency tree. Written
// under BUILT_PRODUCTS_DIR so the path is shared across targets of a
// given configuration.
let subprojectSafediArtifactAsInput: FileListGlob = "$(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi"
let subprojectSafediArtifactAsOutput: Path = "$(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi"
let hostSafediArtifactAsOutput: Path = "$(BUILT_PRODUCTS_DIR)/SafeDI/ExampleTuistIntegration.safedi"

// MARK: - Generated-output discovery

// Ask `SafeDITool scan` at `tuist generate` time which Swift files
// SafeDI will emit for the host target. The tool is the authority on
// its own naming rules (see
// Sources/SafeDICore/Utilities/OutputFileNaming.swift), so this avoids
// any drift risk from re-implementing those rules in Project.swift.
//
// `scan` is fast (manifest-write only; no code gen). Those outputs are
// registered below as `.generated(...)` entries against
// `$(DERIVED_FILE_DIR)`, so the actual code generation stays where it
// belongs — inside the Xcode pre-compile script phase — while Xcode
// still knows to compile whatever files land there.
let manifestDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

// Manifest-time failures (missing binary, scan errors, unreadable
// output) should stop `tuist generate` rather than silently produce a
// pbxproj with no `.generated(…)` entries. An empty outputs list would
// surface later as a hard-to-diagnose build failure ("cannot find
// initializer…"), far from the root cause.
func fatal(_ message: String) -> Never {
	FileHandle.standardError.write(Data("error: \(message)\n".utf8))
	exit(1)
}

enum SafeDIOutputDiscovery {
	static func outputs(forModuleAt moduleDirectory: URL) -> [Path] {
		guard let tool = resolvedSafeDIToolURL() else {
			fatal("""
			SafeDITool binary not found under Tuist/.build/artifacts/…
			Run `tuist install` before `tuist generate`.
			""")
		}
		let scratch = manifestDirectory.appendingPathComponent(".build/tuist-manifest-scan", isDirectory: true)
		let moduleScratch = scratch.appendingPathComponent(moduleDirectory.lastPathComponent, isDirectory: true)
		do {
			try FileManager.default.createDirectory(at: moduleScratch, withIntermediateDirectories: true)
		} catch {
			fatal("Failed to create SafeDI scan scratch dir at \(moduleScratch.path): \(error).")
		}

		let inputCSV = moduleScratch.appendingPathComponent("InputSwiftFiles.csv")
		let sources = swiftSourcePaths(relativeTo: manifestDirectory, in: moduleDirectory)
		guard !sources.isEmpty else {
			fatal("No .swift sources found under \(moduleDirectory.path).")
		}
		do {
			try sources.joined(separator: ",").write(to: inputCSV, atomically: true, encoding: .utf8)
		} catch {
			fatal("Failed to write SafeDI input CSV at \(inputCSV.path): \(error).")
		}

		let manifestFile = moduleScratch.appendingPathComponent("SafeDIManifest.json")

		let process = Process()
		process.executableURL = tool
		process.currentDirectoryURL = manifestDirectory
		process.arguments = [
			"scan",
			"--input-sources-file", inputCSV.path,
			"--project-root", manifestDirectory.path,
			"--output-directory", moduleScratch.path,
			"--manifest-file", manifestFile.path,
		]
		// Capture stderr so a scan failure surfaces in the `tuist generate`
		// log rather than silently falling through to an empty output list.
		let stderrPipe = Pipe()
		process.standardError = stderrPipe
		do {
			try process.run()
		} catch {
			fatal("Failed to launch SafeDITool scan: \(error).")
		}
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			let stderr = String(
				data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
				encoding: .utf8,
			) ?? "<unavailable>"
			fatal("""
			SafeDITool scan exited \(process.terminationStatus):
			\(stderr)
			""")
		}
		guard let data = try? Data(contentsOf: manifestFile),
		      let manifest = try? JSONDecoder().decode(ScanManifest.self, from: data)
		else {
			fatal("SafeDITool scan succeeded but its manifest at \(manifestFile.path) is unreadable.")
		}

		// The outputFilePaths in the manifest point into `moduleScratch`
		// because that's the `--output-directory` scan was given. Keep
		// only the basenames and rebuild against $(DERIVED_FILE_DIR) —
		// that's where the build-phase script writes at build time.
		var outputs: [Path] = []
		for entry in manifest.dependencyTreeGeneration + manifest.mockGeneration {
			let basename = (entry.outputFilePath as NSString).lastPathComponent
			outputs.append("$(DERIVED_FILE_DIR)/\(basename)")
		}
		if let mockConfiguration = manifest.mockConfigurationOutputFilePath {
			let basename = (mockConfiguration as NSString).lastPathComponent
			outputs.append("$(DERIVED_FILE_DIR)/\(basename)")
		}
		return outputs
	}

	private static func resolvedSafeDIToolURL() -> URL? {
		#if arch(arm64)
			let variant = "SafeDITool-macos-arm64"
		#else
			let variant = "SafeDITool-macos-x86_64"
		#endif
		let tool = manifestDirectory
			.appendingPathComponent("Tuist/.build/artifacts/safedi/SafeDIToolBinary", isDirectory: true)
			.appendingPathComponent("SafeDITool.artifactbundle", isDirectory: true)
			.appendingPathComponent("\(variant)/bin/SafeDITool")
		return FileManager.default.isExecutableFile(atPath: tool.path) ? tool : nil
	}

	private static func swiftSourcePaths(relativeTo base: URL, in directory: URL) -> [String] {
		guard let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: nil,
		) else { return [] }
		var results = [String]()
		let basePath = base.standardizedFileURL.path
		for case let url as URL in enumerator where url.pathExtension == "swift" {
			let absolute = url.standardizedFileURL.path
			if absolute.hasPrefix(basePath + "/") {
				results.append(String(absolute.dropFirst(basePath.count + 1)))
			}
		}
		return results.sorted()
	}

	private struct ScanManifest: Decodable {
		struct Entry: Decodable { let outputFilePath: String }
		let dependencyTreeGeneration: [Entry]
		let mockGeneration: [Entry]
		let mockConfigurationOutputFilePath: String?
	}
}

let hostGeneratedSources: [SourceFileGlob] = SafeDIOutputDiscovery
	.outputs(forModuleAt: manifestDirectory.appendingPathComponent("ExampleTuistIntegration"))
	.map { .generated($0) }

// MARK: - Project

let project = Project(
	name: "ExampleTuistIntegration",
	targets: [
		.target(
			name: "Subproject",
			destinations: [.mac],
			product: .framework,
			bundleId: "com.safedi.ExampleTuistIntegration.Subproject",
			deploymentTargets: .macOS("14.0"),
			infoPlist: .default,
			sources: ["Subproject/**/*.swift"],
			scripts: [
				.pre(
					script: #"""
					set -euo pipefail
					"$SRCROOT/Scripts/generate-safedi.sh" Subproject
					"""#,
					name: "Generate SafeDI",
					inputPaths: subprojectSources,
					outputPaths: [subprojectSafediArtifactAsOutput],
					basedOnDependencyAnalysis: true,
				),
			],
			dependencies: [
				.external(name: "SafeDI"),
			],
		),
		.target(
			name: "ExampleTuistIntegration",
			destinations: [.mac],
			product: .app,
			bundleId: "com.safedi.ExampleTuistIntegration",
			deploymentTargets: .macOS("14.0"),
			infoPlist: .extendingDefault(with: [
				"CFBundleDisplayName": "Example Tuist Integration",
				"LSApplicationCategoryType": "public.app-category.productivity",
			]),
			sources: SourceFilesList(globs: [
				.glob("ExampleTuistIntegration/**/*.swift"),
			] + hostGeneratedSources),
			resources: [
				"ExampleTuistIntegration/Assets.xcassets",
				"ExampleTuistIntegration/Preview Content/**",
			],
			entitlements: "ExampleTuistIntegration/ExampleTuistIntegration.entitlements",
			scripts: [
				.pre(
					script: #"""
					set -euo pipefail
					"$SRCROOT/Scripts/generate-safedi.sh" ExampleTuistIntegration Subproject
					"""#,
					name: "Generate SafeDI",
					inputPaths: hostSources + [subprojectSafediArtifactAsInput],
					outputPaths: hostGeneratedSources.map(\.glob) + [hostSafediArtifactAsOutput],
					basedOnDependencyAnalysis: true,
				),
			],
			dependencies: [
				.target(name: "Subproject"),
				.external(name: "SafeDI"),
			],
		),
	],
)
