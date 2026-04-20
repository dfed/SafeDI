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
		.plugin(
			name: "InstallSafeDITool",
			targets: ["InstallSafeDITool"],
		),
	],
	traits: [
		.default(enabledTraits: ["prebuilt"]),
		.trait(name: "prebuilt", description: "Use a prebuilt SafeDITool binary from the artifact bundle (default)."),
		.trait(name: "sourceBuild", description: "Build SafeDITool from source. Intended for local development and adopting unreleased changes; typically set via `--traits sourceBuild` which replaces the default `prebuilt`."),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
		.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.3.0"),
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

		// Downloads the prebuilt SafeDITool release binary into
		// `<package>/.safedi/<version>/safeditool`. The build plugin prefers
		// that path over the SPM-provided tool — it avoids the
		// `${BUILD_DIR}`-in-tool-path problem that forces Xcode sourceBuild
		// users onto the regex-based `PluginScanner` fallback, and it avoids
		// the ~15× slower debug build that SPM produces when sourceBuild is
		// active.
		.plugin(
			name: "InstallSafeDITool",
			capability: .command(
				intent: .custom(
					verb: "safedi-install-tool",
					description: "Downloads the SafeDITool prebuilt release binary for the current SafeDI version.",
				),
				permissions: [
					.writeToPackageDirectory(reason: "Downloads the SafeDITool binary into .safedi/<version>/safeditool."),
					.allowNetworkConnections(scope: .all(ports: []), reason: "Downloads SafeDITool from the SafeDI GitHub release."),
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
			url: "https://github.com/dfed/SafeDI/releases/download/2.0.0-beta-4/SafeDITool.artifactbundle.zip",
			checksum: "ded85f7f8f7c72ad552d4fbe239ba68091b1d9af6b4f028423bce516d8189e9f",
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

		// Tests for the `SafeDIGenerator` build-tool plugin's in-process
		// helpers. The plugin target itself cannot be a test dependency
		// (SPM plugins can only depend on executable/binary targets), so
		// this target compiles the plugin helpers via symlink:
		// `Tests/SafeDIGeneratorPluginTests/PluginScannerStringUtilities.swift`
		// → `Plugins/PluginScannerStringUtilities.swift`. The plugin target
		// has the same symlink, so both targets share the source.
		.testTarget(
			name: "SafeDIGeneratorPluginTests",
			path: "Tests/SafeDIGeneratorPluginTests",
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
