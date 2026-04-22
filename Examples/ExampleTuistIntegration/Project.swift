import ProjectDescription

// Absolute-ish input/output paths keep Xcode's incremental-build tracking
// precise. Globs aren't supported in script input/output path lists.
let subprojectSources: [String] = [
	"$(SRCROOT)/Subproject/SafeDIConfiguration.swift",
	"$(SRCROOT)/Subproject/User.swift",
	"$(SRCROOT)/Subproject/InMemoryStorage.swift",
	"$(SRCROOT)/Subproject/NoteStorage.swift",
	"$(SRCROOT)/Subproject/StringStorage.swift",
	"$(SRCROOT)/Subproject/UserService.swift",
]

let hostSources: [String] = [
	"$(SRCROOT)/ExampleTuistIntegration/SafeDIConfiguration.swift",
	"$(SRCROOT)/ExampleTuistIntegration/Views/LoggedInView.swift",
	"$(SRCROOT)/ExampleTuistIntegration/Views/NameEntryView.swift",
	"$(SRCROOT)/ExampleTuistIntegration/Views/NotesApp.swift",
]

// The Subproject emits a `.safedi` artifact that the host module reads to
// build its dependency tree. Written under BUILT_PRODUCTS_DIR so the path
// is shared across targets of a given configuration.
let subprojectSafediArtifact = "$(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi"

// The host module's generated Swift is written under a `Generated/`
// directory that Tuist's source glob picks up. Stub files are committed so
// the glob resolves on a fresh `tuist generate`; the script overwrites them
// on every build.
let hostGeneratedFiles: [String] = [
	"$(SRCROOT)/ExampleTuistIntegration/Generated/NotesApp+SafeDI.swift",
	"$(SRCROOT)/ExampleTuistIntegration/Generated/LoggedInView+SafeDIMock.swift",
	"$(SRCROOT)/ExampleTuistIntegration/Generated/NameEntryView+SafeDIMock.swift",
	"$(SRCROOT)/ExampleTuistIntegration/Generated/SafeDIMockConfiguration.swift",
]

let project = Project(
	name: "ExampleTuistIntegration",
	targets: [
		.target(
			name: "Subproject",
			destinations: [.mac],
			product: .framework,
			bundleId: "com.safedi.ExampleTuistIntegration.Subproject",
			deploymentTargets: .macOS("11.0"),
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
					outputPaths: [subprojectSafediArtifact],
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
			deploymentTargets: .macOS("11.0"),
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
					inputPaths: hostSources + [subprojectSafediArtifact],
					outputPaths: hostGeneratedFiles,
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
