import ProjectDescription
import SafeDITuist

// SafeDI codegen is wired up via the SafeDITuist plugin (declared in
// Tuist.swift). Each target uses two helpers:
//
//   - `SafeDI.preCompileScript(...)` — pre-compile shell phase that
//     runs `SafeDITool generate --combined-output` at build time.
//   - `SafeDI.generatedSource` — the single `.generated(...)` source
//     entry pointing at `$(DERIVED_FILE_DIR)/SafeDIGenerated.swift`.
//
// Adding/removing `@Instantiable` declarations changes the contents
// of `SafeDIGenerated.swift` but not its path, so Xcode picks them
// up on the next build. No `tuist generate` round-trip required.
//
// Bumping SafeDI: edit `Tuist/Package.swift` only.

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
			sources: SourceFilesList(globs: [
				.glob("Subproject/**/*.swift"),
				SafeDI.generatedSource,
			]),
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
				SafeDI.generatedSource,
			]),
			resources: [
				"ExampleTuistIntegration/Assets.xcassets",
				"ExampleTuistIntegration/Preview Content/**",
			],
			entitlements: "ExampleTuistIntegration/ExampleTuistIntegration.entitlements",
			scripts: [
				SafeDI.preCompileScript(
					module: "ExampleTuistIntegration",
					dependents: ["Subproject"],
				),
			],
			dependencies: [
				.target(name: "Subproject"),
				.external(name: "SafeDI"),
			],
		),
	],
)
