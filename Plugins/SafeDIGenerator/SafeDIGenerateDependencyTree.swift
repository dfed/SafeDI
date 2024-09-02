// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

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

            let toolLocation: URL = if let toolLocation = context.downloadedToolLocation {
                toolLocation
            } else {
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

            let armMacBrewInstallLocation = "/opt/homebrew/bin/safeditool"
            let intelMacBrewInstallLocation = "/usr/local/bin/safeditool"
            let toolLocation: PackagePlugin.Path = if FileManager.default.fileExists(atPath: Self.armMacBrewInstallLocation) {
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
                executable: toolLocation,
                arguments: arguments,
                environment: [:],
                inputFiles: targetSwiftFiles + dependenciesSourceFiles,
                outputFiles: [outputSwiftFile]
            ),
        ]
    }
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
            #if compiler(>=6.0)
                // As of Xcode 15.0.1, Swift Package Plugins in Xcode are unable
                // to inspect target dependencies. As a result, this Xcode plugin
                // only works if it is running on a single-module project, or if
                // all `@Instantiable`-decorated types are in the target module.
                // https://github.com/apple/swift-package-manager/issues/6003
                let inputSwiftFiles = target
                    .inputFiles
                    .filter { $0.url.pathExtension == "swift" }
                    .map(\.url)
                guard !inputSwiftFiles.isEmpty else {
                    // There are no Swift files in this module!
                    return []
                }

                let outputSwiftFile = context.pluginWorkDirectoryURL.appending(path: "SafeDI.swift")
                let inputSourcesFilePath = context.pluginWorkDirectoryURL.appending(path: "InputSwiftFiles.csv").path()
                try Data(
                    inputSwiftFiles
                        .map { $0.path() }
                        .joined(separator: ",")
                        .utf8
                )
                .write(toPath: inputSourcesFilePath)
                let arguments = [
                    inputSourcesFilePath,
                    "--dependency-tree-output",
                    outputSwiftFile.path(),
                ]

                return try [
                    .buildCommand(
                        displayName: "SafeDIGenerateDependencyTree",
                        executable: context.tool(named: "SafeDITool").url,
                        arguments: arguments,
                        environment: [:],
                        inputFiles: inputSwiftFiles,
                        outputFiles: [outputSwiftFile]
                    ),
                ]
            #else
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
            #endif
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

#if compiler(>=6.0)
    extension PackagePlugin.PluginContext {
        var safeDIVersion: String? {
            guard let safeDIOrigin = package.dependencies.first(where: { $0.package.displayName == "SafeDI" })?.package.origin else {
                return nil
            }
            switch safeDIOrigin {
            case let .repository(_, displayVersion, _):
                return displayVersion
            case .registry, .root, .local:
                fallthrough
            @unknown default:
                return nil
            }
        }

        var downloadedToolLocation: URL? {
            guard let safeDIVersion else { return nil }
            let location = package.directoryURL.appending(
                components: ".safedi",
                safeDIVersion,
                "safeditool"
            )
            guard FileManager.default.fileExists(atPath: location.path()) else { return nil }
            return location
        }
    }
#endif
