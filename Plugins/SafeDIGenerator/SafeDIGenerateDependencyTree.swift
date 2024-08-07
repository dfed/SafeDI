import Foundation
import PackagePlugin

@main
struct SafeDIGenerateDependencyTree: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        #if compiler(>=6.0)
            let outputSwiftFile = context.pluginWorkDirectoryURL.appending(path: "SafeDI.swift")
            // Swift Package Plugins do not (as of Swift 5.9) allow for
            // creating dependencies between plugin output. Since our
            // current build system does not support depending on the
            // output of other plugins, we must forgo searching for
            // `.safeDI` files and instead parse the entire project at once.
            let targetSwiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift").map(\.url)
            let dependenciesSourceFiles = sourceTarget
                .sourceModuleRecursiveDependencies
                .flatMap {
                    $0
                        .sourceFiles(withSuffix: ".swift")
                        .map(\.url)
                }
            let inputSourcesFilePath = context.pluginWorkDirectoryURL.appending(path: "InputSwiftFiles.csv").path()
            try Data(
                (targetSwiftFiles.map { $0.path() } + dependenciesSourceFiles.map { $0.path() })
                    .joined(separator: ",")
                    .utf8
            )
            .write(toPath: inputSourcesFilePath)
            let arguments = [
                inputSourcesFilePath,
                "--dependency-tree-output",
                outputSwiftFile.path(),
            ]

            let toolPath: URL = if FileManager.default.fileExists(atPath: Self.armMacBrewInstallLocation) {
                // SafeDITool has been installed via homebrew on an ARM Mac.
                URL(filePath: Self.armMacBrewInstallLocation)
            } else if FileManager.default.fileExists(atPath: Self.intelMacBrewInstallLocation) {
                // SafeDITool has been installed via homebrew on an Intel Mac.
                URL(filePath: Self.intelMacBrewInstallLocation)
            } else {
                // Fall back to the just-in-time built tool.
                try context.tool(named: "SafeDITool").url
            }
        #else
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

            let inputSourcesFilePath = context.pluginWorkDirectory.appending(subpath: "InputSwiftFiles.csv").string
            try Data(
                (targetSwiftFiles + dependenciesSourceFiles)
                    .map(\.string)
                    .joined(separator: ",")
                    .utf8
            )
            .write(toPath: inputSourcesFilePath)
            let arguments = [
                inputSourcesFilePath,
                "--dependency-tree-output",
                outputSwiftFile.string,
            ]

            let toolPath: PackagePlugin.Path = if FileManager.default.fileExists(atPath: Self.armMacBrewInstallLocation) {
                // SafeDITool has been installed via homebrew on an ARM Mac.
                PackagePlugin.Path(Self.armMacBrewInstallLocation)
            } else if FileManager.default.fileExists(atPath: Self.intelMacBrewInstallLocation) {
                // SafeDITool has been installed via homebrew on an Intel Mac.
                PackagePlugin.Path(Self.intelMacBrewInstallLocation)
            } else {
                // Fall back to the just-in-time built tool.
                try context.tool(named: "SafeDITool").path
            }
        #endif

        return [
            .buildCommand(
                displayName: "SafeDIGenerateDependencyTree",
                executable: toolPath,
                arguments: arguments,
                environment: [:],
                inputFiles: targetSwiftFiles + dependenciesSourceFiles,
                outputFiles: [outputSwiftFile]
            ),
        ]
    }

    private static let armMacBrewInstallLocation = "/opt/homebrew/bin/safeditool"
    private static let intelMacBrewInstallLocation = "/usr/local/bin/safeditool"
}

extension Target {
    var sourceModuleRecursiveDependencies: [SwiftSourceModuleTarget] {
        recursiveTargetDependencies.compactMap { target in
            // Since we only understand Swift files, we only care about SwiftSourceModuleTargets.
            guard let swiftModule = target as? SwiftSourceModuleTarget else {
                return nil
            }

            // We only care about first-party code. Ignore third-party dependencies.
            #if compiler(>=6.0)
                guard
                    swiftModule
                    .directoryURL
                    .pathComponents
                    // Removing the module name.
                    .dropLast()
                    // Removing 'Sources'.
                    .dropLast()
                    // Removing the package name.
                    .dropLast()
                    .last != "checkouts"
                else {
                    return nil
                }
            #else
                guard
                    swiftModule
                    .directory
                    // Removing the module name.
                    .removingLastComponent()
                    // Removing 'Sources'.
                    .removingLastComponent()
                    // Removing the package name.
                    .removingLastComponent()
                    .lastComponent != "checkouts"
                else {
                    return nil
                }
            #endif
            return swiftModule
        }
    }
}

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SafeDIGenerateDependencyTree: XcodeBuildToolPlugin {
        func createBuildCommands(
            context: XcodeProjectPlugin.XcodePluginContext,
            target: XcodeProjectPlugin.XcodeTarget
        ) throws -> [PackagePlugin.Command] {
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
            let inputSourcesFilePath = context.pluginWorkDirectory.appending(subpath: "InputSwiftFiles.csv").string
            try Data(
                inputSwiftFiles
                    .map(\.string)
                    .joined(separator: ",")
                    .utf8
            )
            .write(toPath: inputSourcesFilePath)
            let arguments = [
                inputSourcesFilePath,
                "--dependency-tree-output",
                outputSwiftFile.string,
            ]

            return try [
                .buildCommand(
                    displayName: "SafeDIGenerateDependencyTree",
                    executable: context.tool(named: "SafeDITool").path,
                    arguments: arguments,
                    environment: [:],
                    inputFiles: inputSwiftFiles,
                    outputFiles: [outputSwiftFile]
                ),
            ]
        }
    }
#endif

extension Data {
    fileprivate func write(toPath filePath: String) throws {
        #if os(Linux)
            try write(to: URL(fileURLWithPath: filePath))
        #else
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                try write(to: URL(filePath: filePath))
            } else {
                try write(to: URL(fileURLWithPath: filePath))
            }
        #endif
    }
}
