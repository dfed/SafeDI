import Foundation
import ProjectDescription

// Run SafeDI codegen during `tuist generate` so the host target's
// `Generated/` directory is populated by the time Tuist evaluates the
// source glob. Without this, a fresh checkout would generate a project
// whose pbxproj contains zero references to the SafeDI-generated Swift
// files — `Generated/` is `.gitignore`d, nothing's on disk, Tuist's
// glob matches nothing, Xcode's compile phase doesn't know about the
// generated files, and the app fails to link when it tries to reference
// SafeDI-synthesized initializers.
//
// Running the script here mirrors what the per-target Xcode script
// phases (declared below) do at build time; the two invocations are
// idempotent with respect to each other. SafeDITool is already on
// disk at this point because `tuist install` fetched it via SafeDI's
// `prebuilt` trait chain.
let manifestDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let codegenScript = manifestDirectory.appendingPathComponent("Scripts/generate-safedi.sh")
if FileManager.default.fileExists(atPath: codegenScript.path) {
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/bin/bash")
	process.arguments = [codegenScript.path, "all"]
	process.currentDirectoryURL = manifestDirectory
	try? process.run()
	process.waitUntilExit()
}

// Tuist expands glob patterns in `sources` and script `inputPaths` at
// `tuist generate` time, baking a literal file list into the .xcodeproj.
// That means adding or removing a `.swift` source is a `tuist generate`
// away; nothing in this manifest or in `Scripts/generate-safedi.sh`
// needs a hand edit.
//
// The host-target glob excludes `Generated/**` because those files are
// the script's outputs. Feeding outputs back as inputs would make Xcode
// re-run the script on every build.
let subprojectSources: [FileListGlob] = [
	"Subproject/**/*.swift",
]

let hostSources: [FileListGlob] = [
	.glob(
		"ExampleTuistIntegration/**/*.swift",
		excluding: ["ExampleTuistIntegration/Generated/**"],
	),
]

// The Subproject emits a `.safedi` artifact that the host module reads to
// build its dependency tree. Written under BUILT_PRODUCTS_DIR so the path
// is shared across targets of a given configuration.
let subprojectSafediArtifactAsInput: FileListGlob = "$(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi"
let subprojectSafediArtifactAsOutput: Path = "$(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi"

// Enumerate the host's generated output files on disk — the codegen above
// populated `Generated/` so every file SafeDITool will emit exists now.
// Feeding these as the host script phase's `outputPaths` gives Xcode
// precise per-file dep-analysis without hardcoding filenames in the
// manifest.
let hostGeneratedDirectory = manifestDirectory
	.appendingPathComponent("ExampleTuistIntegration/Generated")
let hostGeneratedOutputs: [Path] = (try? FileManager.default
	.contentsOfDirectory(at: hostGeneratedDirectory, includingPropertiesForKeys: nil))?
	.filter { $0.pathExtension == "swift" }
	.map(\.lastPathComponent)
	.sorted()
	.map { Path("$(SRCROOT)/ExampleTuistIntegration/Generated/\($0)") }
	?? []

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
					"$SRCROOT/Scripts/generate-safedi.sh" subproject
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
			// Generated/ is populated by the `tuist generate`-time
			// codegen at the top of this file; the regular glob picks
			// it up on first and all subsequent generates.
			sources: ["ExampleTuistIntegration/**/*.swift"],
			resources: [
				"ExampleTuistIntegration/Assets.xcassets",
				"ExampleTuistIntegration/Preview Content/**",
			],
			entitlements: "ExampleTuistIntegration/ExampleTuistIntegration.entitlements",
			scripts: [
				.pre(
					script: #"""
					set -euo pipefail
					"$SRCROOT/Scripts/generate-safedi.sh" host
					"""#,
					name: "Generate SafeDI",
					inputPaths: hostSources + [subprojectSafediArtifactAsInput],
					outputPaths: hostGeneratedOutputs,
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
