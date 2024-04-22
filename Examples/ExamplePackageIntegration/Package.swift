// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ExamplePackageIntegration",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ExamplePackageIntegration",
            targets: ["RootModule"]
        ),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RootModule",
            dependencies: [
                "SafeDI",
                "SharedModule",
                "ChildAModule",
                "ChildBModule",
                "ChildCModule",
            ],
            plugins: [
                .plugin(name: "SafeDIGenerator", package: "SafeDI"),
            ]
        ),
        .target(
            name: "ChildAModule",
            dependencies: [
                "SafeDI",
                "SharedModule",
                "GrandchildrenModule",
            ]
        ),
        .target(
            name: "ChildBModule",
            dependencies: [
                "SafeDI",
                "SharedModule",
                "GrandchildrenModule",
            ]
        ),
        .target(
            name: "ChildCModule",
            dependencies: [
                "SafeDI",
                "SharedModule",
                "GrandchildrenModule",
            ]
        ),
        .target(
            name: "GrandchildrenModule",
            dependencies: [
                "SafeDI",
                "SharedModule",
            ]
        ),
        .target(
            name: "SharedModule",
            dependencies: ["SafeDI"]
        ),
    ]
)
