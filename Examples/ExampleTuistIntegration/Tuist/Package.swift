// swift-tools-version: 6.2
//
// Consumed by `tuist install`, which invokes SPM to resolve this
// manifest. Declaring SafeDI here gives Tuist's SPM integration a
// single source of truth for the version pin, and it sidecar-
// downloads `SafeDIToolBinary` (the published
// `SafeDITool.artifactbundle.zip`) because SafeDI's default trait
// chain pulls it in for the `SafeDIGenerator` plugin.
//
// The `SafeDITuist` plugin's script reads the unpacked binary directly
// from SPM's cache, beside this manifest, from any project of the
// workspace (it looks from the project's directory up):
//
//   Tuist/.build/artifacts/safedi/SafeDIToolBinary/
//       SafeDITool.artifactbundle/<host-variant>/bin/SafeDITool
//
// Bump SafeDI by editing the version below; both the runtime library
// (via `.external(name: "SafeDI")` in Project.swift) and the CLI
// binary move in lock step.

import PackageDescription

#if TUIST
	import struct ProjectDescription.PackageSettings

	let packageSettings = PackageSettings()
#endif

let package = Package(
	name: "ExampleTuistIntegration",
	dependencies: [
		.package(url: "https://github.com/dfed/SafeDI.git", exact: "2.3.0-alpha-4"),
	],
)
