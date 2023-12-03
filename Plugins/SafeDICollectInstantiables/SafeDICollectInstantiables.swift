import Foundation
import PackagePlugin

@main
struct SafeDICollectInstantiables: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target)
    async throws -> [Command]
    {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let outputSafeDIFile = context.pluginWorkDirectory.appending(subpath: "\(sourceTarget.moduleName).safedi")
        let inputSwiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift").map(\.path)
        let arguments = inputSwiftFiles
            .map(\.string)
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        + [
            "--instantiables-output",
            outputSafeDIFile
                .string
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        ].compactMap { $0 }

        return [
            .buildCommand(
                displayName: "SafeDIPlugin",
                executable: try context.tool(named: "SafeDIPlugin").path,
                arguments: arguments,
                environment: [:],
                inputFiles: inputSwiftFiles,
                outputFiles: [outputSafeDIFile])
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SafeDICollectInstantiables: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodeProjectPlugin.XcodePluginContext,
        target: XcodeProjectPlugin.XcodeTarget)
    throws -> [PackagePlugin.Command]
    {
        [] // showstopper TODO: Support Xcode project plugin!
    }
}
#endif
