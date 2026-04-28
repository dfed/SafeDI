import ProjectDescription
import SafeDITuist

// SafeDI codegen is wired up via the SafeDITuist plugin (declared in
// Tuist.swift). For each target the plugin returns a pre-compile
// `TargetScript` that runs `SafeDITool scan` + `generate` at build
// time, and a list of `.generated(...)` source entries that point
// at the build-time outputs in `$(DERIVED_FILE_DIR)`.
//
// Adding/removing a `.swift` file: just `tuist generate` — the plugin
// runs `SafeDITool scan` to refresh the generated-output list. No
// manifest edits.
//
// Bumping SafeDI: edit `Tuist/Package.swift` only. Both the runtime
// library (via `.external(name: "SafeDI")`) and the SafeDITool binary
// the plugin invokes follow from that single version pin.

let hostGeneratedSources = SafeDI.generatedSources(for: "ExampleTuistIntegration")

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
				SafeDI.preCompileScript(module: "Subproject"),
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
				SafeDI.preCompileScript(
					module: "ExampleTuistIntegration",
					dependents: ["Subproject"],
					generatedOutputs: hostGeneratedSources.map(\.glob),
				),
			],
			dependencies: [
				.target(name: "Subproject"),
				.external(name: "SafeDI"),
			],
		),
	],
)
