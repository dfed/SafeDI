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
#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif
import PackagePlugin

@main
struct InstallSafeDITool: CommandPlugin {
	func performCommand(
		context: PackagePlugin.PluginContext,
		arguments _: [String]
	) async throws {
		guard let safeDIOrigin = context.package.dependencies.first(where: { $0.package.displayName == "SafeDI" })?.package.origin else {
			Diagnostics.error("No package origin found for SafeDI package")
			exit(1)
		}

		guard let version = context.safeDIVersion,
		      let expectedToolFolder = context.expectedToolFolder,
		      let expectedToolLocation = context.expectedToolLocation
		else {
			Diagnostics.error("Could not extract version for SafeDI")
			exit(1)
		}

		switch safeDIOrigin {
		case let .repository(url, _, _):
			guard let url = URL(string: url)?.deletingPathExtension() else {
				Diagnostics.error("No package url found for SafeDI package")
				exit(1)
			}
			#if arch(arm64)
				let toolName = "SafeDITool-arm64"
			#elseif arch(x86_64)
				let toolName = "SafeDITool-x86_64"
			#else
				Diagnostics.error("Unexpected architecture type")
				exit(1)
			#endif

			let githubDownloadURL = url.appending(
				components: "releases",
				"download",
				version,
				toolName
			)
			let (downloadedURL, _) = try await URLSession.shared.download(
				for: URLRequest(url: githubDownloadURL)
			)
			let downloadedFileAttributes = try FileManager.default.attributesOfItem(atPath: downloadedURL.path())
			guard let currentPermissions = downloadedFileAttributes[.posixPermissions] as? NSNumber,
			      // Add executable attributes to the downloaded file.
			      chmod(downloadedURL.path(), mode_t(currentPermissions.uint32Value) | S_IXUSR | S_IXGRP | S_IXOTH) == 0
			else {
				Diagnostics.error("Failed to make downloaded file \(downloadedURL.path()) executable")
				exit(1)
			}
			try FileManager.default.createDirectory(
				at: expectedToolFolder,
				withIntermediateDirectories: true
			)
			try FileManager.default.moveItem(
				at: downloadedURL,
				to: expectedToolLocation
			)
			let gitIgnoreLocation = context.safediFolder.appending(component: ".gitignore")
			if !FileManager.default.fileExists(atPath: gitIgnoreLocation.path()) {
				try """
				*/\(expectedToolLocation.lastPathComponent)
				""".write(
					to: gitIgnoreLocation,
					atomically: true,
					encoding: .utf8
				)
			}

		case .registry, .root, .local:
			fallthrough

		@unknown default:
			Diagnostics.error("Cannot download SafeDITool from \(safeDIOrigin) – downloading only works when using a versioned release of SafeDI")
			exit(1)
		}
	}
}

#if canImport(XcodeProjectPlugin)
	import XcodeProjectPlugin

	extension InstallSafeDITool: XcodeCommandPlugin {
		func performCommand(
			context: XcodeProjectPlugin.XcodePluginContext,
			arguments _: [String]
		) throws {
			let version = context.safeDIVersion
			let safediFolder = context.safediFolder
			let expectedToolFolder = context.expectedToolFolder
			let expectedToolLocation = context.expectedToolLocation

			#if arch(arm64)
				let toolName = "SafeDITool-arm64"
			#elseif arch(x86_64)
				let toolName = "SafeDITool-x86_64"
			#else
				Diagnostics.error("Unexpected architecture type")
				exit(1)
			#endif

			let githubDownloadURL = context.safeDIOrigin.appending(
				components: "releases",
				"download",
				version,
				toolName
			)

			let dispatchGroup = DispatchGroup()
			dispatchGroup.enter()
			Task.detached {
				defer { dispatchGroup.leave() }
				let (downloadedURL, _) = try await URLSession.shared.download(
					for: URLRequest(url: githubDownloadURL)
				)
				let downloadedFileAttributes = try FileManager.default.attributesOfItem(atPath: downloadedURL.path())
				guard let currentPermissions = downloadedFileAttributes[.posixPermissions] as? NSNumber,
				      // Add executable attributes to the downloaded file.
				      chmod(downloadedURL.path(), mode_t(currentPermissions.uint32Value) | S_IXUSR | S_IXGRP | S_IXOTH) == 0
				else {
					Diagnostics.error("Failed to make downloaded file \(downloadedURL.path()) executable")
					exit(1)
				}
				try FileManager.default.createDirectory(
					at: expectedToolFolder,
					withIntermediateDirectories: true
				)
				try FileManager.default.moveItem(
					at: downloadedURL,
					to: expectedToolLocation
				)
				let gitIgnoreLocation = safediFolder.appending(component: ".gitignore")
				if !FileManager.default.fileExists(atPath: gitIgnoreLocation.path()) {
					try """
					*/\(expectedToolLocation.lastPathComponent)
					""".write(
						to: gitIgnoreLocation,
						atomically: true,
						encoding: .utf8
					)
				}
			}
			// Force the command to wait until the async work is done.
			dispatchGroup.wait()
		}
	}
#endif
