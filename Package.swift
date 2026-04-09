// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

// Set to `true` by the publish workflow after computing the artifact bundle checksum.
// When `true`, SafeDIGenerator uses a prebuilt binary and does not compile SafeDITool from source.
// When `false`, SafeDIGenerator compiles SafeDITool from source (slower but works for local development).
let usePrebuiltBinary = false

let safeDICoreDependencies: [PackageDescription.Target.Dependency] = [
	.product(name: "SwiftDiagnostics", package: "swift-syntax"),
	.product(name: "SwiftSyntax", package: "swift-syntax"),
	.product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
]

let safeDIGeneratorDependencies: [PackageDescription.Target.Dependency] = if usePrebuiltBinary {
	[.target(name: "SafeDIToolBinary")]
} else {
	[.target(name: "SafeDITool")]
}

var targets: [PackageDescription.Target] = [
	// Macros
	.target(
		name: "SafeDI",
		dependencies: ["SafeDIMacros"],
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),
	.testTarget(
		name: "SafeDITests",
		dependencies: [
			"SafeDI",
			"SafeDICore",
		],
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),
	.macro(
		name: "SafeDIMacros",
		dependencies: [
			.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
			.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
		] + safeDICoreDependencies,
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),
	.testTarget(
		name: "SafeDIMacrosTests",
		dependencies: [
			"SafeDIMacros",
			.product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
		],
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),

	// Plugins
	.plugin(
		name: "MigrateSafeDIFromVersionOne",
		capability: .command(
			intent: .custom(
				verb: "safedi-v1-to-v2",
				description: "Migrates a project from SafeDI 1.x to 2.x.",
			),
			permissions: [
				.writeToPackageDirectory(reason: "Creates a SafeDIConfiguration.swift file and removes obsolete CSV configuration files."),
			],
		),
		dependencies: [],
	),

	.plugin(
		name: "SafeDIGenerator",
		capability: .buildTool(),
		dependencies: safeDIGeneratorDependencies,
	),
	.executableTarget(
		name: "SafeDITool",
		dependencies: [
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
			.product(name: "SwiftParser", package: "swift-syntax"),
			"SafeDICore",
		],
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),
	.testTarget(
		name: "SafeDIToolTests",
		dependencies: [
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
			"SafeDITool",
		],
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),

	// Core
	.target(
		name: "SafeDICore",
		dependencies: safeDICoreDependencies,
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),
	.testTarget(
		name: "SafeDICoreTests",
		dependencies: ["SafeDICore"],
		swiftSettings: [
			.swiftLanguageMode(.v6),
		],
	),
]

if usePrebuiltBinary {
	targets.append(
		.binaryTarget(
			name: "SafeDIToolBinary",
			url: "https://github.com/dfed/SafeDI/releases/download/2.0.0/SafeDITool.artifactbundle.zip",
			checksum: "PLACEHOLDER_CHECKSUM_UPDATED_BY_PUBLISH_WORKFLOW",
		),
	)
}

let package = Package(
	name: "SafeDI",
	platforms: [
		.macOS(.v11),
		.iOS(.v15),
		.tvOS(.v15),
		.watchOS(.v8),
		.macCatalyst(.v15),
		.visionOS(.v1),
	],
	products: [
		/// A library containing SafeDI macros, property wrappers, and types.
		.library(
			name: "SafeDI",
			targets: ["SafeDI"],
		),
		/// A SafeDI plugin that must be run on the root source module in a project.
		.plugin(
			name: "SafeDIGenerator",
			targets: ["SafeDIGenerator"],
		),
		.plugin(
			name: "MigrateSafeDIFromVersionOne",
			targets: ["MigrateSafeDIFromVersionOne"],
		),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
		.package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.0"..<"605.0.0"),
	],
	targets: targets,
)
