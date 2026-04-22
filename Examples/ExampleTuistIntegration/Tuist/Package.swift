// swift-tools-version: 6.3
//
// This manifest's only job is to fetch the prebuilt SafeDITool binary
// via SPM's built-in `.binaryTarget(url:checksum:)` mechanism. `tuist
// install` invokes SPM on this file, downloads the artifact bundle,
// and unpacks it to a stable location that Scripts/generate-safedi.sh
// reads from:
//
//   Tuist/.build/artifacts/tuist/SafeDITool/
//       SafeDITool.artifactbundle/<host-variant>/bin/SafeDITool
//
// The SafeDI runtime library (the one that provides `@Instantiable`
// and friends) is pulled separately through Project.swift's
// `Project.packages`, which routes through Xcode's built-in SPM client
// rather than Tuist's SPM integration — Tuist chokes on SafeDI's
// trait-gated internal targets otherwise. Keep the version on the URL
// below in lock-step with `safediVersion` in Project.swift.

import PackageDescription

#if TUIST
	import struct ProjectDescription.PackageSettings

	let packageSettings = PackageSettings()
#endif

let package = Package(
	name: "SafeDIToolHost",
	targets: [
		.binaryTarget(
			name: "SafeDITool",
			url: "https://github.com/dfed/SafeDI/releases/download/2.0.0-beta-5/SafeDITool.artifactbundle.zip",
			checksum: "4e95a9bb1c9ac0643d41563dd8fe125cbd72f319a16ff57160d5b4f9f40605a7",
		),
	],
)
