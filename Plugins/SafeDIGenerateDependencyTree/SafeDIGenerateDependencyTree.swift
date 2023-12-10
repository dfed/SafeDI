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

        let outputSwiftFile = context.pluginWorkDirectory.appending(subpath: "SafeDI.swift")
        // Swift Package Plugins do not (as of Swift 5.9) allow for
        // creating dependencies between plugin output. Since our
        // current build system does not support depending on the
        // output of other plugins, we must forgo searching for
        // `.safeDI` files and instead parse the entire project at once.
        let targetSwiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift").map(\.path)
        let dependenciesSourceFiles = sourceTarget
            .sourceModuleRecursiveDependencies
            .flatMap {
                $0
                    .sourceFiles(withSuffix: ".swift")
                    .map(\.path)
            }

        let arguments = (targetSwiftFiles + dependenciesSourceFiles).map(\.string)
        + ["--dependency-tree-output", outputSwiftFile.string]

        return [
            .buildCommand(
                displayName: "SafeDIGenerateDependencyTree",
                executable: try context.tool(named: "SafeDIPlugin").path,
                arguments: arguments,
                environment: [:],
                inputFiles: targetSwiftFiles + dependenciesSourceFiles,
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
        // As of Xcode 15.0.1, Swift Package Plugins in Xcode are unable
        // to inspect target dependencies. As a result, this Xcode plugin
        // only works if it is running on a single-module project, or if
        // all `@Instantiable`-decorated types are in the target module.
        // https://github.com/apple/swift-package-manager/issues/6003
        let inputSwiftFiles = target
            .inputFiles
            .filter { $0.path.extension == "swift" }
            .map(\.path)
        guard !inputSwiftFiles.isEmpty else {
            // There are no Swift files in this module!
            return []
        }

        let outputSwiftFile = context.pluginWorkDirectory.appending(subpath: "SafeDI.swift")
        let arguments = inputSwiftFiles
            .map(\.string)
        + [
            "--dependency-tree-output",
            outputSwiftFile.string
        ]

        return [
            .buildCommand(
                displayName: "SafeDIGenerateDependencyTree",
                executable: try context.tool(named: "SafeDIPlugin").path,
                arguments: arguments,
                environment: [:],
                inputFiles: inputSwiftFiles,
                outputFiles: [outputSwiftFile])
        ]
    }
}
#endif
