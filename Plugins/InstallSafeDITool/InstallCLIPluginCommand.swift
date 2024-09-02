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
struct InstallSafeDITool: CommandPlugin {
    func performCommand(
        context: PackagePlugin.PluginContext,
        arguments _: [String]
    ) async throws {
        guard let safeDIOrigin = context.package.dependencies.first(where: { $0.package.displayName == "SafeDI" })?.package.origin else {
            print("No package origin found for SafeDI package")
            return
        }
        switch safeDIOrigin {
        case let .repository(url, displayVersion, _):
            guard let versionMatch = try /Optional\((.*?)\)|^(.*?)$/.firstMatch(in: displayVersion),
                  let version = versionMatch.output.1 ?? versionMatch.output.2
            else {
                print("could not extract version for SafeDI")
                return
            }
            let expectedToolFolder = context.package.directoryURL.appending(
                components: ".safedi",
                String(version)
            )
            let expectedToolLocation = expectedToolFolder.appending(component: "safeditool")

            guard let url = URL(string: url)?.deletingPathExtension() else {
                print("No package origin found for SafeDI package")
                return
            }
            #if arch(arm64)
                let toolName = "SafeDITool-arm64"
            #elseif arch(x86_64)
                let toolName = "SafeDITool-x86_64"
            #else
                print("Unexpected architecture type")
                return
            #endif

            let downloadURL = url.appending(
                components: "releases",
                "download",
                displayVersion,
                toolName
            )
            let (downloadedURL, _) = try await URLSession.shared.download(
                for: URLRequest(url: downloadURL)
            )
            let downloadedFileAttributes = try FileManager.default.attributesOfItem(atPath: downloadedURL.path())
            guard let currentPermissions = downloadedFileAttributes[.posixPermissions] as? NSNumber,
                  // Add executable attributes to the downloaded file.
                  chmod(downloadedURL.path(), mode_t(currentPermissions.uint16Value | S_IXUSR | S_IXGRP | S_IXOTH)) == 0
            else {
                print("Failed to make downloaded file executable")
                return
            }
            try FileManager.default.createDirectory(
                at: expectedToolFolder,
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(
                at: downloadedURL,
                to: expectedToolLocation
            )
            let gitIgnoreLocation = expectedToolFolder.appending(component: ".gitignore")
            if !FileManager.default.fileExists(atPath: gitIgnoreLocation.path()) {
                try """
                \(expectedToolLocation.lastPathComponent)
                """.write(
                    to: gitIgnoreLocation,
                    atomically: true,
                    encoding: .utf8
                )
            }

        case .registry, .root, .local:
            fallthrough

        @unknown default:
            print("Cannot download SafeDITool from \(safeDIOrigin)")
        }
    }
}
