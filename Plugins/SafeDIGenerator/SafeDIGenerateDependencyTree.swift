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

        let outputSwiftFile = context.pluginWorkDirectoryURL.appending(path: "SafeDI.swift")
        // Swift Package Plugins did not (as of Swift 5.9) allow for
        // creating dependencies between plugin output at the time of writing.
        // Since our current build system didnot support depending on the
        // output of other plugins, we must forgo searching for `.safeDI` files
        // and instead parse the entire project at once.
        // TODO: https://github.com/dfed/SafeDI/issues/92
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
            (targetSwiftFiles.map { $0.path(percentEncoded: false) } + dependenciesSourceFiles.map { $0.path(percentEncoded: false) })
                .joined(separator: ",")
                .utf8
        )
        .write(toPath: inputSourcesFilePath)
        let arguments = [
            inputSourcesFilePath,
            "--dependency-tree-output",
            outputSwiftFile.path(),
        ]

        let downloadedToolLocation = context.downloadedToolLocation
        let safeDIVersion = context.safeDIVersion
        if context.hasSafeDIFolder, let safeDIVersion, downloadedToolLocation == nil {
            Diagnostics.error("""
            \(context.safediFolder.path()) exists, but contains no SafeDITool binary for version \(safeDIVersion).

            To install the release SafeDITool binary for version \(safeDIVersion), run:
            \tswift package --package-path \(context.package.directoryURL.path()) --allow-network-connections all --allow-writing-to-package-directory safedi-release-install

            To use a debug SafeDITool binary instead, remove previous installs by running:
            \trm -rf \(context.safediFolder.path())
            """)
        } else if downloadedToolLocation == nil, let safeDIVersion {
            Diagnostics.warning("""
            Using a debug SafeDITool binary, which is 15x slower than the release version.

            To install the release SafeDITool binary for version \(safeDIVersion), run:
            \tswift package --package-path \(context.package.directoryURL.path()) --allow-network-connections all --allow-writing-to-package-directory safedi-release-install
            """)
        }

        let toolLocation = if let downloadedToolLocation {
            downloadedToolLocation
        } else {
            try context.tool(named: "SafeDITool").url
        }

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
                    .map { $0.path(percentEncoded: false) }
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

extension PackagePlugin.PluginContext {
    var safeDIVersion: String? {
        guard let safeDIOrigin = package.dependencies.first(where: { $0.package.displayName == "SafeDI" })?.package.origin else {
            return nil
        }
        switch safeDIOrigin {
        case let .repository(_, displayVersion, _):
            // This regular expression is duplicated by InstallSafeDITool since plugins can not share code.
            guard let versionMatch = try? /Optional\((.*?)\)|^(.*?)$/.firstMatch(in: displayVersion),
                  let version = versionMatch.output.1 ?? versionMatch.output.2
            else {
                return nil
            }
            return String(version)
        case .registry, .root, .local:
            fallthrough
        @unknown default:
            return nil
        }
    }

    var hasSafeDIFolder: Bool {
        FileManager.default.fileExists(atPath: safediFolder.path())
    }

    var safediFolder: URL {
        package.directoryURL.appending(
            component: ".safedi"
        )
    }

    var downloadedToolLocation: URL? {
        guard let safeDIVersion else { return nil }
        let location = safediFolder.appending(
            components: safeDIVersion,
            "safeditool"
        )
        guard FileManager.default.fileExists(atPath: location.path()) else { return nil }
        return location
    }
}
