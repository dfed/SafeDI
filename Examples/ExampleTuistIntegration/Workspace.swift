import ProjectDescription

// The app's project sits at the workspace's root, beside `Tuist.swift` and
// `Tuist/Package.swift`, and the `Subproject` framework's project in a
// subdirectory, as in a workspace with a project per module.

let workspace = Workspace(
	name: "ExampleTuistIntegration",
	projects: [
		".",
		"Projects/Subproject",
	],
)
