// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let safeDICoreDependencies: [PackageDescription.Target.Dependency] = [
	.product(name: "SwiftDiagnostics", package: "swift-syntax"),
	.product(name: "SwiftParser", package: "swift-syntax"),
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
		.package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"605.0.0"),
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
			// Every project that uses SafeDI compiles this macro plugin from source, and no file that uses SafeDI's
			// macros can compile until it is built, so its compile time adds to every clean build. The macros compile
			// SafeDICore's sources through the `SafeDICore` symbolic link. This list leaves out the ones only
			// SafeDITool uses: most of SafeDICore, and most of this target's compile time.
			// Sources/SafeDICore/BUILD.bazel excludes the same files. `MacroTargetSourceTests` fails when the two
			// lists differ, or when this target compiles a SafeDICore file missing from its list of the files the
			// macros use, so that a new file gets sorted into one list or the other.
			exclude: [
				"SafeDICore/Generators",
				"SafeDICore/Utilities",
				"SafeDICore/Extensions/ImportDeclSyntaxExtensions.swift",
				"SafeDICore/Models/AliasDeclarationReferences.swift",
				"SafeDICore/Models/CycleParameter.swift",
				"SafeDICore/Models/ImportStatement.swift",
				"SafeDICore/Models/SafeDIToolManifest.swift",
				"SafeDICore/Models/Scope.swift",
				"SafeDICore/Models/SeamSignature.swift",
				"SafeDICore/Models/SourceDiagnostic.swift",
				"SafeDICore/Models/TypeAccessProof.swift",
				"SafeDICore/Models/TypeRequirements.swift",
				"SafeDICore/Models/WithoutPositions.swift",
				"SafeDICore/Visitors/FileVisitor.swift",
			],
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
		// `<xcodeProject>/.safedi/<version>/safeditool`. Xcode-only — avoids
		// the `${BUILD_DIR}`-in-tool-path problem that forces Xcode users
		// onto the regex-based `PluginScanner` fallback.
		.plugin(
			name: "InstallSafeDITool",
			capability: .command(
				intent: .custom(
					verb: "safedi-release-install",
					description: "Xcode-only: downloads the SafeDITool prebuilt release binary for the current SafeDI version into .safedi/<version>/safeditool next to the .xcodeproj. swift build users get the prebuilt tool via the default `prebuilt` trait and don't need this.",
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
			url: "https://github.com/dfed/SafeDI/releases/download/2.3.0-alpha-3/SafeDITool.artifactbundle.zip",
			checksum: "46ce6676a5156aa2859a9aa89410ad928abbcce41223a41fce3564d2c34cbe56",
		),
		// The tool's commands live in a library, and the executable only runs them, so that
		// what tests the commands depends on a library, which every build system builds
		// before the targets that import it. In the graph SwiftPM hands the Swift Build
		// backend (Xcode, `--build-system swiftbuild`, the default from Swift 6.4), only a
		// test target that nothing depends on is ordered after an executable target's module
		// it imports, so `SafeDIToolTestSupport` would compile alongside that module rather
		// than after it. The executable target keeps the name `SafeDITool`, which names the
		// tool the plugin asks for and the binary the release ships, so the library's module
		// is `SafeDIToolLibrary`.
		.executableTarget(
			name: "SafeDITool",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				"SafeDIToolLibrary",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		.target(
			name: "SafeDIToolLibrary",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "SwiftParser", package: "swift-syntax"),
				"SafeDICore",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),

		// The `SafeDITool` tests are split across five test targets, so that a release
		// whole-module build compiles them in parallel: a whole-module compile grows
		// faster than its line count, and one module of every test was the longest
		// step of CI's build. Their shared helpers (`executeSafeDIToolTest`, the
		// compile verifier, the graph fuzzer, the differential value comparator) live
		// in `SafeDIToolTestSupport`, which declares no tests and which each test
		// target reaches through `@testable import`, as it reaches `SafeDIToolLibrary`.
		// It is a regular target rather than a test target because Xcode 26 rejects a
		// test target that depends on another test target. No product lists it, so a
		// package that depends on SafeDI never builds it, and Xcode's `SafeDI-Package`
		// scheme, which builds products, leaves it alone; a plain `swift build` of this
		// package builds it, in release without `-enable-testing`, so the helpers
		// import `SafeDIToolLibrary` without `@testable`, through the declarations the
		// library makes `public` for them. (`package` would need a package name, which
		// the `SafeDIGenerator` plugin, compiling `PluginTargetGraph.swift` through a
		// symbolic link, does not have.) SwiftPM compiles a regular target for the
		// package's `platforms` rather than for the host, as it does a test target, so
		// the helpers mark what uses macOS 13 API `@available`.
		.target(
			name: "SafeDIToolTestSupport",
			dependencies: [
				"SafeDIToolLibrary",
				"SafeDICore",
			],
			path: "Tests/SafeDIToolTestSupport",
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		.testTarget(
			name: "SafeDIToolTests",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				"SafeDIToolLibrary",
				"SafeDIToolTestSupport",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		.testTarget(
			name: "SafeDIToolDependencyTreeTests",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				"SafeDIToolLibrary",
				"SafeDIToolTestSupport",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		.testTarget(
			name: "SafeDIToolMockTests",
			dependencies: [
				"SafeDIToolLibrary",
				"SafeDIToolTestSupport",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		.testTarget(
			name: "SafeDIToolSeamTests",
			dependencies: [
				"SafeDIToolLibrary",
				"SafeDIToolTestSupport",
			],
			swiftSettings: [
				.swiftLanguageMode(.v6),
			],
		),
		.testTarget(
			name: "SafeDIToolFuzzerTests",
			dependencies: [
				"SafeDIToolLibrary",
				"SafeDIToolTestSupport",
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
		// has the same symlink, so both targets share the source. The
		// target also checks rules SafeDI's own sources follow, which it
		// parses with SwiftSyntax.
		.testTarget(
			name: "SafeDIGeneratorPluginTests",
			dependencies: [
				.product(name: "SwiftParser", package: "swift-syntax"),
				.product(name: "SwiftSyntax", package: "swift-syntax"),
			],
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
