import Foundation
import PackagePlugin

@main
struct SafeDIGenerateDependencyTree: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target)
    async throws -> [Command]
    {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let inputSwiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift").map(\.path)
        guard !inputSwiftFiles.isEmpty else {
            return []
        }

        let outputSwiftFile = context.pluginWorkDirectory.appending(subpath: "SafeDI.swift")
        let targetDependencySourceFiles = sourceTarget
            .sourceModuleRecursiveDependencies
            .flatMap {
                $0
                    .sourceFiles(withSuffix: ".swift")
                    .map(\.path)
            }

        let instantiablePaths = sourceTarget
            .sourceModuleRecursiveDependencies
            .map {
                context
                    .pluginWorkDirectory
                    .removingLastComponent() // Remove `SafeDICollectInstantiables` from path.
                    .removingLastComponent() // Remove current module name from path.
                    .appending([
                        $0.name, // Dependency module name.
                        "SafeDICollectInstantiables", // SafeDICollectInstantiables working directory
                        "\($0.name).safedi" // SafeDICollectInstantiables output file.
                    ])
            }
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        let instantiablePathsArguments: [String] = if !instantiablePaths.isEmpty {
            ["--instantiables-paths"]
            + instantiablePaths
        } else {
            []
        }
        let arguments = inputSwiftFiles
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        + instantiablePathsArguments
        + [
            "--dependency-tree-output",
            outputSwiftFile
                .string
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        ].compactMap { $0 }

        return [
            .buildCommand(
                displayName: "SafeDIGenerateDependencyTree",
                executable: try context.tool(named: "SafeDIPlugin").path,
                arguments: arguments,
                environment: [:],
                inputFiles: inputSwiftFiles + targetDependencySourceFiles,
                outputFiles: [outputSwiftFile])
        ]
    }
}

extension Target {

    var sourceModuleRecursiveDependencies: [SourceModuleTarget] {
        recursiveTargetDependencies.compactMap {
            $0 as? SourceModuleTarget
        }
    }

}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SafeDIGenerateDependencyTree: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodeProjectPlugin.XcodePluginContext,
        target: XcodeProjectPlugin.XcodeTarget)
    throws -> [PackagePlugin.Command]
    {
        let inputSwiftFiles = target
            .inputFiles
            .filter { $0.path.extension == "swift" }
            .map(\.path)
        guard !inputSwiftFiles.isEmpty else {
            // There are no Swift files in this module!
            return []
        }
        let targetDependencySourceFiles = target
            .sourceModuleRecursiveDependencies
            .flatMap {
                $0
                    .inputFiles
                    .filter { $0.path.extension == "swift" }
                    .map(\.path)
            }

        let outputSwiftFile = context.pluginWorkDirectory.appending(subpath: "SafeDI.swift")
        let instantiablePaths = (
            target
                .sourceModuleRecursiveDependencies
                .map {
                    context
                        .pluginWorkDirectory
                        .removingLastComponent() // Remove `SafeDICollectInstantiables` from path.
                        .removingLastComponent() // Remove current module name from path.
                        .appending([
                            $0.displayName, // Dependency module name.
                            "SafeDICollectInstantiables", // SafeDICollectInstantiables working directory
                            "\($0.displayName).safedi" // SafeDICollectInstantiables output file.
                        ])
                }
            + target
                .productRecursiveDependencies
                .map {
                    context
                        .pluginWorkDirectory
                        .removingLastComponent() // Remove `SafeDICollectInstantiables` from path.
                        .removingLastComponent() // Remove current module name from path.
                        .appending([
                            $0.name, // Dependency module name.
                            "SafeDICollectInstantiables", // SafeDICollectInstantiables working directory
                            "\($0.name).safedi" // SafeDICollectInstantiables output file.
                        ])
                }
        )
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        let instantiablePathsArguments: [String] = if !instantiablePaths.isEmpty {
            ["--instantiables-paths"]
            + instantiablePaths
        } else {
            []
        }
        let arguments = inputSwiftFiles
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        + instantiablePathsArguments
        + [
            "--dependency-tree-output",
            outputSwiftFile
                .string
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        ].compactMap { $0 }

        return [
            .buildCommand(
                displayName: "SafeDIGenerateDependencyTree",
                executable: try context.tool(named: "SafeDIPlugin").path,
                arguments: arguments,
                environment: [:],
                inputFiles: inputSwiftFiles + targetDependencySourceFiles,
                outputFiles: [outputSwiftFile])
        ]
    }
}

extension XcodeProjectPlugin.XcodeTarget {

    var sourceModuleRecursiveDependencies: [XcodeProjectPlugin.XcodeTarget] {
        dependencies
            .compactMap { dependency in
                switch dependency {
                case let .target(xcodeTarget):
                    return xcodeTarget
                case .product:
                    return nil
                @unknown default:
                    return nil
                }
            }
            .flatMap(\.sourceModuleRecursiveDependencies)
    }

    var productRecursiveDependencies: [PackagePlugin.Product] {
        sourceModuleRecursiveDependencies
            .flatMap(\.dependencies)
            .compactMap { dependency in
                switch dependency {
                case let .product(product):
                    return product
                case .target:
                    return nil
                @unknown default:
                    return nil
                }
            }
    }

}
#endif
