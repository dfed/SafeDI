// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

// TODO: Once https://github.com/michaeleisel/ZippyJSON/pull/67 is in a release, remove this conditional.
let isBuildingForCocoaPods = Context.environment["SAFEDI_MACRO_COCOAPODS_BUILD"] != nil

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
    products: [
        /// A library containing SafeDI macros, property wrappers, and types.
        .library(
            name: "SafeDI",
            targets: ["SafeDI"]
        ),
    ] + (isBuildingForCocoaPods ? [] : [
        /// A SafeDI plugin that must be run on the root source module in a project.
        .plugin(
            name: "SafeDIGenerator",
            targets: ["SafeDIGenerator"]
        ),
        .plugin(
            name: "InstallSafeDITool",
            targets: ["InstallSafeDITool"]
        ),
    ]),
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.5.0"),
    ] + (isBuildingForCocoaPods ? [] : [
        .package(url: "https://github.com/michaeleisel/ZippyJSON.git", from: "1.2.0"),
    ]),
    targets: [
        // Macros
        .target(
            name: "SafeDI",
            dependencies: ["SafeDIMacros"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SafeDITests",
            dependencies: [
                "SafeDI",
                "SafeDICore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
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
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SafeDIMacrosTests",
            dependencies: [
                "SafeDIMacros",
                "SafeDICore",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // Plugins
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
        ),

        // Core
        .target(
            name: "SafeDICore",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SafeDICoreTests",
            dependencies: ["SafeDICore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ] + (isBuildingForCocoaPods ? [] : [
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
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SafeDIToolTests",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .byNameItem(name: "ZippyJSON", condition: .when(platforms: [.iOS, .tvOS, .macOS])),
                "SafeDITool",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ])
)
