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
		// Every target treats warnings as errors so that CI fails on a warning in SafeDI's generated
		// code, such as a `#sourceLocation` directive whose path conflicts with the compiler's.
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
				.treatAllWarnings(as: .error),
				// Only `swift build` on SwiftPM's native backend needs this define. The native
				// backend is `swift build`'s default through Swift 6.2, the toolchain in
				// Xcode 26, and `--build-system native` selects it on later toolchains. There
				// SafeDITool sees only the conditions a plugin can read, which leave out
				// SwiftPM's implicit `DEBUG`. Xcode builds and `swift build` on the Swift Build
				// backend, the default in Swift 6.4, hand SafeDITool every condition the
				// compiler receives and ignore this define. The example can drop it once its
				// minimum toolchain's `swift build` defaults to Swift Build; Swift 6.4's does.
				// Without the define, a native-backend build stops at SafeDI's compile-time
				// assertion rather than generating the wrong code.
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
				.treatAllWarnings(as: .error),
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
				.treatAllWarnings(as: .error),
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
				.treatAllWarnings(as: .error),
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
				.treatAllWarnings(as: .error),
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
				.treatAllWarnings(as: .error),
			],
			plugins: [
				.plugin(name: "SafeDIGenerator", package: "SafeDI"),
			],
		),
	],
)
