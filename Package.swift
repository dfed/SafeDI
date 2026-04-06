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
		/// A SafeDI plugin that must be run on the root source module in a project that does not build SwiftSyntax from source.
		.plugin(
			name: "SafeDIPrebuiltGenerator",
			targets: ["SafeDIPrebuiltGenerator"],
		),
		.plugin(
			name: "InstallSafeDITool",
			targets: ["InstallSafeDITool"],
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
			name: "InstallSafeDITool",
			capability: .command(
				intent: .custom(
					verb: "safedi-release-install",
					description: "Installs a release version of the SafeDITool build plugin executable.",
				),
				permissions: [
					.writeToPackageDirectory(reason: "Downloads the SafeDI release build plugin executable into your project directory."),
					.allowNetworkConnections(scope: .all(ports: []), reason: "Downloads the SafeDI release build plugin executable from GitHub."),
				],
			),
			dependencies: [],
		),

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
				"SafeDITool",
			],
		),
		// A lightweight library containing root scanning and output file naming logic.
		// Used by SafeDIRootScanner (executable), SafeDITool, and plugins (via symlinks).
		.target(
			name: "SafeDIRootScannerCore",
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		// A lightweight executable that performs lexical root discovery without SwiftSyntax.
		// SPM plugins run this in-process via symlinked sources.
		// This target exists as a standalone executable for non-SPM build systems (e.g. Buck, Bazel)
		// that need to invoke root scanning as a separate process.
		.executableTarget(
			name: "SafeDIRootScanner",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				"SafeDIRootScannerCore",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		.testTarget(
			name: "SafeDIRootScannerTests",
			dependencies: [
				"SafeDICore",
				"SafeDIRootScanner",
				"SafeDIRootScannerCore",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
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
				"SafeDIRootScannerCore",
				"SafeDITool",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),

		.plugin(
			name: "SafeDIPrebuiltGenerator",
			capability: .buildTool(),
			dependencies: [],
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
