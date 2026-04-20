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

/// Downloads the prebuilt SafeDITool release binary for the current SafeDI
/// version into `<package>/.safedi/<version>/safeditool` (or the Xcode
/// project's equivalent directory). The build plugin prefers this path over
/// the SPM-provided tool because:
///
/// 1. **Xcode + sourceBuild trait**: `context.tool(named:)` returns an
///    unresolved `${BUILD_DIR}/${CONFIGURATION}/SafeDITool` template path
///    at plugin-setup time that can't be executed, forcing a fall back to
///    the lossy regex-based `PluginScanner`. A downloaded prebuilt gives
///    the plugin-setup scan the real parser's output.
/// 2. **swift build + sourceBuild trait**: SafeDITool is built in DEBUG
///    config, which is ~15× slower than the release binary. Downloading
///    the prebuilt release restores prod-speed codegen.
@main
struct InstallSafeDITool: CommandPlugin {
	func performCommand(
		context: PackagePlugin.PluginContext,
		arguments _: [String],
	) async throws {
		guard let safeDIOrigin = context.package.dependencies.first(where: { $0.package.displayName == "SafeDI" })?.package.origin else {
			Diagnostics.error("No package origin found for SafeDI package.")
			exit(1)
		}
		guard let version = context.safeDIVersion,
		      let expectedToolFolder = context.expectedToolFolder,
		      let expectedToolLocation = context.expectedToolLocation
		else {
			Diagnostics.error("Could not extract version for SafeDI. The install plugin only works when SafeDI is consumed via a versioned release (not a local or root package reference).")
			exit(1)
		}

		switch safeDIOrigin {
		case let .repository(url, _, _):
			guard let originURL = URL(string: url)?.deletingPathExtension() else {
				Diagnostics.error("No package URL found for SafeDI package.")
				exit(1)
			}
			try await downloadTool(
				originURL: originURL,
				version: version,
				expectedToolFolder: expectedToolFolder,
				expectedToolLocation: expectedToolLocation,
				safediFolder: context.safediFolder,
			)

		case .registry, .root, .local:
			fallthrough

		@unknown default:
			Diagnostics.error("Cannot download SafeDITool from \(safeDIOrigin) — downloading only works when using a versioned release of SafeDI.")
			exit(1)
		}
	}
}

#if canImport(XcodeProjectPlugin)
	import XcodeProjectPlugin

	extension InstallSafeDITool: XcodeCommandPlugin {
		func performCommand(
			context: XcodeProjectPlugin.XcodePluginContext,
			arguments _: [String],
		) throws {
			let version = context.safeDIVersion
			let safediFolder = context.safediFolder
			let expectedToolFolder = context.expectedToolFolder
			let expectedToolLocation = context.expectedToolLocation
			let safeDIOrigin = context.safeDIOrigin

			// `XcodeCommandPlugin.performCommand` is synchronous. Bridge to
			// the async `downloadTool` helper via a dispatch group so the
			// command doesn't return until the download finishes.
			let dispatchGroup = DispatchGroup()
			dispatchGroup.enter()
			var capturedError: Error?
			Task.detached {
				defer { dispatchGroup.leave() }
				do {
					try await downloadTool(
						originURL: safeDIOrigin,
						version: version,
						expectedToolFolder: expectedToolFolder,
						expectedToolLocation: expectedToolLocation,
						safediFolder: safediFolder,
					)
				} catch {
					capturedError = error
				}
			}
			dispatchGroup.wait()
			if let capturedError {
				Diagnostics.error("\(capturedError)")
				exit(1)
			}
		}
	}
#endif

/// Downloads the correct architecture's prebuilt binary from GitHub
/// Releases, marks it executable, and moves it into the expected
/// per-version location. Also writes a `.gitignore` inside `.safedi/`
/// (on first run) that excludes the per-version binaries from source
/// control — the binary is per-machine and shouldn't be committed.
private func downloadTool(
	originURL: URL,
	version: String,
	expectedToolFolder: URL,
	expectedToolLocation: URL,
	safediFolder: URL,
) async throws {
	#if arch(arm64)
		let toolName = "SafeDITool-macos-arm64"
	#elseif arch(x86_64)
		let toolName = "SafeDITool-macos-x86_64"
	#else
		throw UnsupportedArchitectureError()
	#endif

	let githubDownloadURL = originURL.appending(
		components: "releases",
		"download",
		version,
		toolName,
	)
	let (downloadedURL, _) = try await URLSession.shared.download(
		for: URLRequest(url: githubDownloadURL),
	)
	let downloadedFileAttributes = try FileManager.default.attributesOfItem(atPath: downloadedURL.path(percentEncoded: false))
	guard let currentPermissions = downloadedFileAttributes[.posixPermissions] as? NSNumber,
	      chmod(downloadedURL.path(percentEncoded: false), mode_t(currentPermissions.uint32Value) | S_IXUSR | S_IXGRP | S_IXOTH) == 0
	else {
		throw CouldNotMakeExecutableError(path: downloadedURL.path(percentEncoded: false))
	}
	try FileManager.default.createDirectory(at: expectedToolFolder, withIntermediateDirectories: true)
	if FileManager.default.fileExists(atPath: expectedToolLocation.path(percentEncoded: false)) {
		try FileManager.default.removeItem(at: expectedToolLocation)
	}
	try FileManager.default.moveItem(at: downloadedURL, to: expectedToolLocation)

	let gitIgnoreLocation = safediFolder.appending(component: ".gitignore")
	if !FileManager.default.fileExists(atPath: gitIgnoreLocation.path(percentEncoded: false)) {
		// Each version gets its own subfolder (`<version>/safeditool`) so
		// the glob `*/safeditool` catches every installed binary.
		try """
		*/\(expectedToolLocation.lastPathComponent)
		""".write(
			to: gitIgnoreLocation,
			atomically: true,
			encoding: .utf8,
		)
	}
}

private struct UnsupportedArchitectureError: Error, CustomStringConvertible {
	var description: String {
		"Unsupported host architecture for SafeDITool download."
	}
}

private struct CouldNotMakeExecutableError: Error, CustomStringConvertible {
	let path: String
	var description: String {
		"Could not make downloaded file executable: \(path)"
	}
}
