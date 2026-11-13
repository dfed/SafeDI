// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "RuleCheck",
	platforms: [.macOS(.v13)],
	dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")],
	targets: [
		.macro(name: "RuleMacrosPlugin", dependencies: [
			.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
			.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
		]),
		.target(name: "RuleMacros", dependencies: ["RuleMacrosPlugin"]),
		.target(name: "RuleClient", dependencies: ["RuleMacros"]),
	],
)
