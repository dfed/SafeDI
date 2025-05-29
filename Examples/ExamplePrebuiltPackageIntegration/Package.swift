// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "ExamplePackageIntegration",
	platforms: [
		.macOS(.v10_15),
		.iOS(.v13),
		.tvOS(.v13),
		.watchOS(.v6),
		.macCatalyst(.v13),
	],
	products: [
		// Products define the executables and libraries a package produces, making them visible to other packages.
		.library(
			name: "ExamplePackageIntegration",
			targets: ["RootModule"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/dfed/SafeDI.git", exact: "1.2.0-alpha-4"),
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
			],
			plugins: [
				.plugin(name: "SafeDIPrebuiltGenerator", package: "SafeDI"),
			]
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
			]
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
			]
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
			]
		),
		.target(
			name: "GrandchildrenModule",
			dependencies: [
				"SafeDI",
				"SharedModule",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			]
		),
		.target(
			name: "SharedModule",
			dependencies: ["SafeDI"],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			]
		),
	]
)
