// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let safeDICoreDependencies: [PackageDescription.Target.Dependency] = [
	.product(name: "SwiftDiagnostics", package: "swift-syntax"),
	.product(name: "SwiftSyntax", package: "swift-syntax"),
	.product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
]

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
	traits: [
		.default(enabledTraits: ["prebuilt"]),
		.trait(name: "prebuilt", description: "Use a prebuilt SafeDITool binary from the artifact bundle (default)."),
		.trait(name: "sourceBuild", description: "Build SafeDITool from source. Mutually exclusive with 'prebuilt'."),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
		.package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.0"..<"605.0.0"),
	],
	targets: [
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
			dependencies: [
				.target(name: "SafeDIToolBinary", condition: .when(traits: ["prebuilt"])),
				.target(name: "SafeDITool", condition: .when(traits: ["sourceBuild"])),
			],
		),
		.binaryTarget(
			name: "SafeDIToolBinary",
			url: "https://github.com/dfed/SafeDI/releases/download/2.0.0-alpha-13/SafeDITool.artifactbundle.zip",
			checksum: "b7cbb5b7b2a835cc929e0415dff6e14f4a1676c829fe25b4ba32ee0404e10c13",
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
	],
)
