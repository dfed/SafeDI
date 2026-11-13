// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "MacroRepro",
	platforms: [.macOS(.v13)],
	dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")],
	targets: [
		.macro(name: "NoopMacrosPlugin", dependencies: [
			.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
			.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
		]),
		.target(name: "NoopMacros", dependencies: ["NoopMacrosPlugin"]),
		.target(name: "Client", dependencies: ["NoopMacros"]),
	],
)
