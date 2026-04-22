import ProjectDescription

// Pin the SafeDI runtime library to the same release Tuist/Package.swift
// pins the SafeDITool CLI binary to. When bumping SafeDI, update both:
//   - safediVersion here
//   - url + checksum in Tuist/Package.swift
let safediVersion = "2.0.0-beta-5"

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

// Single timestamp marker stands in for the generated-swift output set.
// Xcode's dep-analysis only needs one output file to decide whether to
// re-run the script; the actual .swift outputs are picked up by the
// host target's source glob. This lets the manifest stay agnostic of
// which concrete files SafeDITool will emit — the tool decides based on
// what @Instantiable(isRoot:)/generateMock:true declarations it finds.
let hostGeneratedMarker: Path = "$(DERIVED_FILE_DIR)/safedi-generated.marker"

let project = Project(
	name: "ExampleTuistIntegration",
	packages: [
		.package(
			url: "https://github.com/dfed/SafeDI.git",
			.upToNextMajor(from: "\(safediVersion)"),
		),
	],
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
				.package(product: "SafeDI"),
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
					outputPaths: [hostGeneratedMarker],
					basedOnDependencyAnalysis: true,
				),
			],
			dependencies: [
				.target(name: "Subproject"),
				.package(product: "SafeDI"),
			],
		),
	],
)
