import ProjectDescription
import SafeDITuist

// A project in a subdirectory of the workspace, as in a workspace with a
// project per module. Its `$SRCROOT` is this directory, so the
// `SafeDITuist` plugin's script finds the `SafeDITool` that `tuist install`
// unpacks into the workspace root's `Tuist/.build`: it looks in the nearest
// directory, from `$SRCROOT` up, that holds `Tuist/Package.swift`.

let project = Project(
	name: "Subproject",
	// Treating warnings as errors makes CI fail on a warning in SafeDI's generated code.
	settings: .settings(base: ["SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES"]),
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
	],
)
