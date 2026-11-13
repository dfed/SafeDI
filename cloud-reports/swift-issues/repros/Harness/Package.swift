// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "Harness",
	platforms: [.macOS(.v13)],
	dependencies: [
		.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
	],
	targets: [
		.macro(
			name: "NoopMacrosPlugin",
			dependencies: [
				.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
				.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
				.product(name: "_SwiftCompilerPluginMessageHandling", package: "swift-syntax"),
			],
		),
		.target(name: "NoopMacros", dependencies: ["NoopMacrosPlugin"]),
		.target(name: "Client", dependencies: ["NoopMacros"]),
		.executableTarget(
			name: "DecodeBench",
			dependencies: [
				.product(name: "_SwiftCompilerPluginMessageHandling", package: "swift-syntax"),
				.product(name: "SwiftIfConfig", package: "swift-syntax"),
			],
		),
	],
)
