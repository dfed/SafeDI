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

/// Downloads the prebuilt SafeDITool release binary for the current SafeDI
/// version into `<xcodeProject>/.safedi/<version>/safeditool`. The Xcode
/// build plugin prefers this path over the SPM-provided tool because
/// `context.tool(named:)` returns an unresolved
/// `${BUILD_DIR}/${CONFIGURATION}/SafeDITool` template path at plugin-setup
/// time that can't be executed, forcing a fall back to the lossy
/// regex-based `PluginScanner`. A downloaded prebuilt gives the
/// plugin-setup scan the real parser's output.
///
/// This plugin is Xcode-only. Users who build via `swift build` already get
/// the prebuilt binary through the default `prebuilt` trait (or
/// intentionally build from source with `--traits sourceBuild`).
@main
struct InstallSafeDITool: CommandPlugin {
	func performCommand(
		context _: PackagePlugin.PluginContext,
		arguments _: [String],
	) async throws {
		Diagnostics.error("safedi-release-install is an Xcode-only command plugin. swift build users get the prebuilt binary via the default `prebuilt` trait, and `--traits sourceBuild` builds SafeDITool from source on purpose.")
		exit(1)
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
			// the async `downloadTool` helper via a dispatch group. On
			// failure the task reports the diagnostic and calls `exit(1)`,
			// which terminates the process — the `defer { dispatchGroup.leave() }`
			// never runs in that path, but the hard kill makes that moot.
			// The indirection (vs. capturing a mutable `Error?` across
			// Sendable) sidesteps Swift 6 data-race diagnostics.
			let dispatchGroup = DispatchGroup()
			dispatchGroup.enter()
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
					Diagnostics.error("\(error)")
					exit(1)
				}
			}
			dispatchGroup.wait()
		}
	}
#endif

/// Downloads the correct architecture's prebuilt binary from GitHub
/// Releases, marks it executable, and moves it into the expected
/// per-version location. Also writes a `.gitignore` inside `.safedi/`
/// (on first run) that excludes the per-version binaries from source
/// control — the binary is per-machine and shouldn't be committed.
///
/// Entire body gated on macOS — Linux Foundation doesn't ship
/// `URLSession.shared` without `FoundationNetworking`, and the Xcode
/// template-path problem this plugin exists to work around is
/// macOS-only anyway. The whole plugin can't be excluded from the
/// build (the `.command` target in Package.swift is unconditional),
/// so non-macOS compilation produces a function that just throws.
private func downloadTool(
	originURL: URL,
	version: String,
	expectedToolFolder: URL,
	expectedToolLocation: URL,
	safediFolder: URL,
) async throws {
	#if os(macOS)
		// GitHub releases publish `SafeDITool-macos-<arch>` assets. Pick the
		// one matching the host the installer runs on — consumers invoke
		// this command on their dev machine, and the resulting binary has
		// to run on that same host later when the build plugin launches it.
		#if arch(arm64)
			let toolName = "SafeDITool-macos-arm64"
		#elseif arch(x86_64)
			let toolName = "SafeDITool-macos-x86_64"
		#else
			throw UnsupportedHostError()
		#endif

		let githubDownloadURL = originURL.appending(
			components: "releases",
			"download",
			version,
			toolName,
		)
		let downloadedURL: URL
		let response: URLResponse
		do {
			(downloadedURL, response) = try await URLSession.shared.download(
				for: URLRequest(url: githubDownloadURL),
			)
		} catch {
			// URLSession errors stringify to a useless Foundation
			// generic (`The operation couldn't be completed. ...`).
			// Wrap with the URL + the underlying message so offline /
			// GitHub-down / DNS cases surface something actionable.
			throw DownloadRequestFailedError(url: githubDownloadURL, underlying: error)
		}
		// `URLSession.download(for:)` reports success for HTTP error pages
		// (404, 500, etc.), so without this check we'd `chmod +x` and install
		// the error body as the tool — the next build would fail opaquely.
		if let httpResponse = response as? HTTPURLResponse {
			guard (200..<300).contains(httpResponse.statusCode) else {
				try? FileManager.default.removeItem(at: downloadedURL)
				throw DownloadFailedError(
					url: githubDownloadURL,
					statusCode: httpResponse.statusCode,
				)
			}
		}
		let downloadedFileAttributes = try FileManager.default.attributesOfItem(atPath: downloadedURL.path(percentEncoded: false))
		guard let currentPermissions = downloadedFileAttributes[.posixPermissions] as? NSNumber,
		      chmod(downloadedURL.path(percentEncoded: false), mode_t(currentPermissions.uint32Value) | S_IXUSR | S_IXGRP | S_IXOTH) == 0
		else {
			throw CouldNotMakeExecutableError(path: downloadedURL.path(percentEncoded: false))
		}
		try FileManager.default.createDirectory(at: expectedToolFolder, withIntermediateDirectories: true)
		if FileManager.default.fileExists(atPath: expectedToolLocation.path(percentEncoded: false)) {
			// `replaceItemAt` is atomic on HFS+/APFS: the new inode replaces
			// the old via rename, so concurrent installs can't leave the
			// destination in a half-replaced state. `moveItem` + prior
			// `removeItem` is a two-step race — two processes interleaving
			// could both `removeItem`, then one `moveItem` wins and the
			// other fails because the destination exists again.
			_ = try FileManager.default.replaceItemAt(expectedToolLocation, withItemAt: downloadedURL)
		} else {
			try FileManager.default.moveItem(at: downloadedURL, to: expectedToolLocation)
		}

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
	#else
		throw UnsupportedHostError()
	#endif
}

private struct UnsupportedHostError: Error, CustomStringConvertible {
	var description: String {
		"Unsupported host OS/architecture for SafeDITool download. Supported: macOS on arm64 or x86_64."
	}
}

private struct DownloadFailedError: Error, CustomStringConvertible {
	let url: URL
	let statusCode: Int
	var description: String {
		"Failed to download SafeDITool from \(url.absoluteString): HTTP \(statusCode). Verify the SafeDI version matches a published release."
	}
}

private struct CouldNotMakeExecutableError: Error, CustomStringConvertible {
	let path: String
	var description: String {
		"Could not make downloaded file executable: \(path)"
	}
}

private struct DownloadRequestFailedError: Error, CustomStringConvertible {
	let url: URL
	let underlying: any Error
	var description: String {
		"Failed to reach \(url.absoluteString): \(underlying.localizedDescription). Check network connectivity and that the release tag exists."
	}
}
