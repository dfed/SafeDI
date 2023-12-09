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
        .macCatalyst(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ExamplePackageIntegration",
            targets: ["RootModule"]),
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .rootTarget(
            name: "RootModule",
            dependencies: [
                "SharedModule",
                "ChildAModule",
                "ChildBModule",
                "ChildCModule",
            ]
        ),
        .nonRootTarget(
            name: "ChildAModule",
            dependencies: [
                "SharedModule",
                "GrandchildrenModule",
            ]
        ),
        .nonRootTarget(
            name: "ChildBModule",
            dependencies: [
                "SharedModule",
                "GrandchildrenModule",
            ]
        ),
        .nonRootTarget(
            name: "ChildCModule",
            dependencies: [
                "SharedModule",
                "GrandchildrenModule",
            ]
        ),
        .nonRootTarget(
            name: "GrandchildrenModule",
            dependencies: [
                "SharedModule"
            ]
        ),
        .nonRootTarget(name: "SharedModule"),
    ]
)

extension Target {
    static func rootTarget(name: String, dependencies: [Target.Dependency] = []) -> Target {
        .target(
            name: name,
            dependencies: [
                "SafeDI",
            ] + dependencies,
            plugins: [
                .plugin(name: "SafeDIGenerateDependencyTree", package: "SafeDI"),
            ]
        )
    }

    static func nonRootTarget(name: String, dependencies: [Target.Dependency] = []) -> Target {
        .target(
            name: name,
            dependencies: [
                "SafeDI",
            ] + dependencies,
            plugins: [
                .plugin(name: "SafeDICollectInstantiables", package: "SafeDI"),
            ]
        )
    }
}
