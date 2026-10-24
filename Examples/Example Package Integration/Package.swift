// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "ExamplePackageIntegration",
	platforms: [
		.macOS(.v11),
		.iOS(.v15),
		.tvOS(.v15),
		.watchOS(.v8),
		.macCatalyst(.v15),
		.visionOS(.v1),
	],
	products: [
		// Products define the executables and libraries a package produces, making them visible to other packages.
		.library(
			name: "ExamplePackageIntegration",
			targets: ["RootModule"],
		),
	],
	dependencies: [
		// The "sourceBuild" trait builds SafeDITool from source. This is used for local
		// development and adopting unreleased versions. Consumers using a published release
		// should omit the traits parameter to use the faster prebuilt binary.
		.package(path: "../../", traits: ["sourceBuild"]),
	],
	targets: [
		// Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "RootModule",
			dependencies: [
				"SafeDI",
				"SharedModule",
				"ChildAModule",
				"ChildBModule",
				"ChildCModule",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
				// The SafeDIGenerator plugin forwards this target's compilation conditions to
				// SafeDITool, but SwiftPM's implicit `DEBUG` is not among them. Declaring it
				// here lets SafeDITool evaluate the `#if DEBUG` in `EventLogger.swift`.
				.define("DEBUG", .when(configuration: .debug)),
			],
			plugins: [
				.plugin(name: "SafeDIGenerator", package: "SafeDI"),
			],
		),
		.target(
			name: "ChildAModule",
			dependencies: [
				"SafeDI",
				"SharedModule",
				"GrandchildrenModule",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
			plugins: [
				.plugin(name: "SafeDIGenerator", package: "SafeDI"),
			],
		),
		.target(
			name: "ChildBModule",
			dependencies: [
				"SafeDI",
				"SharedModule",
				"GrandchildrenModule",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
			plugins: [
				.plugin(name: "SafeDIGenerator", package: "SafeDI"),
			],
		),
		.target(
			name: "ChildCModule",
			dependencies: [
				"SafeDI",
				"SharedModule",
				"GrandchildrenModule",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
			plugins: [
				.plugin(name: "SafeDIGenerator", package: "SafeDI"),
			],
		),
		.target(
			name: "GrandchildrenModule",
			dependencies: [
				"SafeDI",
				"SharedModule",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
			plugins: [
				.plugin(name: "SafeDIGenerator", package: "SafeDI"),
			],
		),
		.target(
			name: "SharedModule",
			dependencies: ["SafeDI"],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
			plugins: [
				.plugin(name: "SafeDIGenerator", package: "SafeDI"),
			],
		),
	],
)
