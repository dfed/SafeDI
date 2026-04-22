// swift-tools-version: 6.3
import PackageDescription

#if TUIST
	import struct ProjectDescription.PackageSettings

	// Tuist consumes SafeDI as a local SPM package. The `prebuilt` trait
	// (SafeDI's default) pulls in the published SafeDITool artifact bundle,
	// but this example does not use the SafeDIGenerator build-tool plugin
	// at all — it invokes SafeDITool directly from a script build phase so
	// each target can emit/consume `.safedi` module-info files. The
	// `SafeDIGenerator` plugin product is therefore ignored here.
	let packageSettings = PackageSettings()
#endif

let package = Package(
	name: "ExampleTuistIntegration",
	dependencies: [
		.package(path: "../../.."),
	],
)
