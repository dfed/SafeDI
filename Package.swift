// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SafeDI",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13)
    ],
    products: [
        /// A library containing SafeDI macros, property wrappers, and types.
        .library(
            name: "SafeDI",
            targets: ["SafeDI"]
        ),
        /// A SafeDI plugin that must be run on non-root source modules in a project.
        .plugin(
            name: "SafeDICollectInstantiables",
            targets: ["SafeDICollectInstantiables"]
        ),
        /// A SafeDI plugin that must be run on the root source module in a project.
        .plugin(
            name: "SafeDIGenerateDependencyTree",
            targets: ["SafeDIGenerateDependencyTree"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/michaeleisel/ZippyJSON.git", from: "1.2.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.2.0"),
    ],
    targets: [
        // Macros
        .target(
            name: "SafeDI",
            dependencies: ["SafeDIMacros"]
        ),
        .testTarget(
            name: "SafeDITests",
            dependencies: [
                "SafeDI",
                "SafeDICore"
            ]
        ),
        .macro(
            name: "SafeDIMacros",
            dependencies: [
                "SafeDICore",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "SafeDIMacrosTests",
            dependencies: [
                "SafeDIMacros",
                "SafeDICore",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ]
        ),

        // Plugins
        .plugin(
            name: "SafeDICollectInstantiables",
            capability: .buildTool(),
            dependencies: ["SafeDIPlugin"]
        ),
        .plugin(
            name: "SafeDIGenerateDependencyTree",
            capability: .buildTool(),
            dependencies: ["SafeDIPlugin"]
        ),
        .executableTarget(
            name: "SafeDIPlugin",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                "ZippyJSON",
                "SafeDICore",
            ]
        ),
        .testTarget(
            name: "SafeDIPluginTests",
            dependencies: ["SafeDIPlugin"]
        ),

        // Core
        .target(
            name: "SafeDICore",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "SafeDICoreTests",
            dependencies: ["SafeDICore"]
        ),
    ]
)
