// swift-tools-version: 6.3
//
// Declares SafeDI as an SPM dependency so `rules_swift_package_manager`
// can pull it into Bazel via MODULE.bazel's `swift_deps` extension.
// This example uses no runtime products from SPM beyond SafeDI itself;
// the SafeDITool CLI is fetched separately as a binary artifact
// (`safeditool_bundle` in MODULE.bazel).
import PackageDescription

let package = Package(
	name: "ExampleBazelIntegration",
	dependencies: [
		.package(url: "https://github.com/dfed/SafeDI.git", from: "2.0.0-beta-5"),
	],
)
