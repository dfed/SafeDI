// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let isBuildingForCocoapods = Context.environment["SAFEDI_COCOAPODS_PROTOCOL_PLUGIN"] != nil

let commonSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]
let safeDIMacrosDependencies: [Target.Dependency] = [
    "SafeDICore",
    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
    .product(name: "SwiftDiagnostics", package: "swift-syntax"),
    .product(name: "SwiftSyntax", package: "swift-syntax"),
    .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
]

let package = Package(
    name: "SafeDI",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13),
        .visionOS(.v1),
    ],
    products: [].appending(
        /// A library containing SafeDI macros, property wrappers, and types.
        .library(
            name: "SafeDI",
            targets: ["SafeDI"]
        ),
        /// A SafeDI plugin that must be run on the root source module in a project.
        .plugin(
            name: "SafeDIGenerator",
            targets: ["SafeDIGenerator"]
        ),
        .plugin(
            name: "InstallSafeDITool",
            targets: ["InstallSafeDITool"]
        ), if: !isBuildingForCocoapods
    )
    .appending(
        .executable(name: "SafeDIMacros", targets: ["SafeDIMacros"]),
        if: isBuildingForCocoapods
    ),
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.5.0"),
    ]
    .appending(
        .package(url: "https://github.com/michaeleisel/ZippyJSON.git", from: "1.2.0"),
        if: !isBuildingForCocoapods
    ),
    targets: [
        .target(
            name: "SafeDICore",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "SafeDICoreTests",
            dependencies: ["SafeDICore"],
            swiftSettings: commonSwiftSettings
        ),
    ]
    .appending(
        // Macros
        .target(
            name: "SafeDI",
            dependencies: ["SafeDIMacros"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "SafeDITests",
            dependencies: [
                "SafeDI",
                "SafeDICore",
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "SafeDIMacrosTests",
            dependencies: [
                "SafeDIMacros",
                "SafeDICore",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .macro(
            name: "SafeDIMacros",
            dependencies: safeDIMacrosDependencies,
            swiftSettings: commonSwiftSettings
        ),

        // Plugins
        .plugin(
            name: "SafeDIGenerator",
            capability: .buildTool(),
            dependencies: ["SafeDITool"]
        ),
        .executableTarget(
            name: "SafeDITool",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .byNameItem(name: "ZippyJSON", condition: .when(platforms: [.iOS, .tvOS, .macOS])),
                "SafeDICore",
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "SafeDIToolTests",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .byNameItem(name: "ZippyJSON", condition: .when(platforms: [.iOS, .tvOS, .macOS])),
                "SafeDITool",
            ],
            swiftSettings: commonSwiftSettings
        ),
        .plugin(
            name: "InstallSafeDITool",
            capability: .command(
                intent: .custom(
                    verb: "safedi-release-install",
                    description: "Installs a release version of the SafeDITool build plugin executable."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Downloads the SafeDI release build plugin executable into your project directory."),
                    .allowNetworkConnections(scope: .all(ports: []), reason: "Downloads the SafeDI release build plugin executable from GitHub."),
                ]
            ),
            dependencies: []
        ), if: !isBuildingForCocoapods
    )
    .appending(.executableTarget(
        name: "SafeDIMacros",
        dependencies: safeDIMacrosDependencies,
        swiftSettings: commonSwiftSettings
    ), if: isBuildingForCocoapods)
)

extension Array {
    func appending(_ elements: Element..., if condition: Bool) -> [Element] {
        if condition {
            self + elements
        } else {
            self
        }
    }
}
