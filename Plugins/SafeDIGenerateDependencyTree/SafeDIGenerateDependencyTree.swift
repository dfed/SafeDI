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
        let outputSwiftFile = context.pluginWorkDirectory.appending(subpath: "SafeDI.swift")
        let targetDependencySafeDIOutputFiles = sourceTarget
            .sourceModuleRecursiveDependencies
            .map {
                context
                    .pluginWorkDirectory
                    .removingLastComponent() // Remove `SafeDIGenerateDependencyTree` from path.
                    .removingLastComponent() // Remove current module name from path.
                    .appending([
                        $0.name, // Dependency module name.
                        "SafeDICollectInstantiables", // SafeDICollectInstantiables working directory
                        "\($0.name).safedi" // SafeDICollectInstantiables output file.
                    ])
            }
            .filter { FileManager.default.fileExists(atPath: $0.string) }

        let arguments = inputSwiftFiles
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        + ["--instantiables-paths"]
        + targetDependencySafeDIOutputFiles
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        + [
            "--dependency-tree-output",
            outputSwiftFile
                .string
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        ].compactMap { $0 }

        return [
            .buildCommand(
                displayName: "SafeDIGenerateDependencyTree",
                executable: try context.tool(named: "GenerateDependencyTree").path,
                arguments: arguments,
                environment: [:],
                inputFiles: inputSwiftFiles + targetDependencySafeDIOutputFiles,
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

        let outputSwiftFile = context.pluginWorkDirectory.appending(subpath: "SafeDI.swift")
        let targetDependencySafeDIOutputFiles = target
            .sourceModuleRecursiveDependencies
            .map {
                context
                    .pluginWorkDirectory
                    .removingLastComponent() // Remove `SafeDIGenerateDependencyTree` from path.
                    .removingLastComponent() // Remove current module name from path.
                    .appending([
                        $0.displayName, // Dependency module name.
                        "SafeDICollectInstantiables", // SafeDICollectInstantiables working directory
                        "\($0.displayName).safedi" // SafeDICollectInstantiables output file.
                    ])
            }
            .filter { FileManager.default.fileExists(atPath: $0.string) }

        let arguments = inputSwiftFiles
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        + ["--instantiables-paths"]
        + targetDependencySafeDIOutputFiles
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        + [
            "--dependency-tree-output",
            outputSwiftFile
                .string
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        ].compactMap { $0 }

        return [
            .buildCommand(
                displayName: "SafeDIGenerateDependencyTree",
                executable: try context.tool(named: "GenerateDependencyTree").path,
                arguments: arguments,
                environment: [:],
                inputFiles: inputSwiftFiles + targetDependencySafeDIOutputFiles,
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

}
#endif
