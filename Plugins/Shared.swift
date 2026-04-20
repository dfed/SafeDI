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

// MARK: - Prebuilt Tool Location

// Plugin context helpers for locating a prebuilt SafeDITool binary at a
// fixed per-project path (`.safedi/<version>/safeditool`). Consumers of
// SafeDI in Xcode hit a `context.tool(named:)` template-path problem when
// the `sourceBuild` trait is active — the plugin-setup phase can't execute
// the tool. A user-downloaded prebuilt at the known location sidesteps that
// and also speeds up plugin-setup scans. See `InstallSafeDITool` for the
// companion Xcode command plugin that downloads the binary.

#if canImport(XcodeProjectPlugin)
	import XcodeProjectPlugin

	extension XcodeProjectPlugin.XcodePluginContext {
		/// Hardcoded because Xcode command plugins can't read the package
		/// manifest. OK to lag behind the latest release as long as
		/// SafeDITool's CLI surface hasn't changed in ways that break older
		/// callers — the binary format is forward-compatible within a minor
		/// release line.
		var safeDIVersion: String {
			"2.0.0-beta-4"
		}

		/// Hardcoded source repo (forks must update this to point at their
		/// own releases for the downloader to work for their users).
		var safeDIOrigin: URL {
			URL(string: "https://github.com/dfed/SafeDI")!
		}

		var safediFolder: URL {
			xcodeProject.directoryURL.appending(component: ".safedi")
		}

		var expectedToolFolder: URL {
			safediFolder.appending(component: safeDIVersion)
		}

		var expectedToolLocation: URL {
			expectedToolFolder.appending(component: "safeditool")
		}

		var downloadedToolLocation: URL? {
			guard FileManager.default.fileExists(atPath: expectedToolLocation.path(percentEncoded: false)) else { return nil }
			return expectedToolLocation
		}
	}

	/// Verifies a cached SafeDITool binary both runs on the host AND
	/// matches the expected SafeDI version. Launches it with `--version`
	/// and compares the trimmed stdout to `expectedVersion`. Returns the
	/// URL when the binary is usable and version-matched, or `nil`
	/// otherwise — caller falls back to the SPM-provided tool.
	///
	/// The version check catches the "stale binary from an earlier
	/// SafeDI version left in `.safedi/`" case: the binary might still
	/// launch cleanly but produce output incompatible with the current
	/// SafeDI release. Without this check, a user bumping SafeDI would
	/// silently keep running the old tool until they re-ran the install
	/// command or manually cleared `.safedi/`.
	func verifiedDownloadedToolLocation(_ toolURL: URL?, expectedVersion: String) -> URL? {
		guard let toolURL else { return nil }
		let process = Process()
		process.executableURL = toolURL
		process.arguments = ["--version"]
		let outPipe = Pipe()
		process.standardOutput = outPipe
		// Discard stderr instead of piping it — an unread pipe deadlocks
		// `waitUntilExit()` once its buffer fills (~64 KB), and this
		// helper blocks the plugin-setup thread. `FileHandle.nullDevice`
		// routes stderr to /dev/null without any read-side coupling.
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
		} catch {
			return nil
		}
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { return nil }
		let data = outPipe.fileHandleForReading.readDataToEndOfFile()
		guard let reportedVersion = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
		      reportedVersion == expectedVersion
		else { return nil }
		return toolURL
	}
#endif

// MARK: - CSV Writing

func writeInputSwiftFilesCSV(
	_ swiftFiles: [URL],
	relativeTo base: URL,
	to inputSourcesFile: URL,
) throws {
	try swiftFiles
		.map { relativePath(for: $0, relativeTo: base) }
		.joined(separator: ",")
		.write(
			to: inputSourcesFile,
			atomically: true,
			encoding: .utf8,
		)
}

// MARK: - Relative Path

/// Compute a path string relative to a base directory.
/// Falls back to the absolute path if the URL is not under the base directory.
func relativePath(for url: URL, relativeTo base: URL) -> String {
	let urlPath = url.standardizedFileURL.path
	let standardizedBasePath = base.standardizedFileURL.path
	let basePath = standardizedBasePath.hasSuffix("/")
		? standardizedBasePath
		: standardizedBasePath + "/"

	if urlPath.hasPrefix(basePath) {
		return String(urlPath.dropFirst(basePath.count))
	} else {
		return urlPath
	}
}

// MARK: - Scan Manifest

/// A Codable struct matching the JSON output of `SafeDITool scan`.
/// Plugins cannot import SafeDICore, so this is defined locally.
struct ScanManifest: Codable {
	struct InputOutputMap: Codable {
		var inputFilePath: String
		var outputFilePath: String
	}

	var dependencyTreeGeneration: [InputOutputMap]
	var mockGeneration: [InputOutputMap]
	var configurationFilePaths: [String]
	var mockConfigurationOutputFilePath: String?
	var additionalMocksToGenerate: [String]
	var additionalInputFiles: [String]
}

// MARK: - Process Runner

struct SafeDIToolProcessError: Error, CustomStringConvertible {
	let terminationStatus: Int32
	let standardError: String

	var description: String {
		if standardError.isEmpty {
			"SafeDITool exited with status \(terminationStatus)"
		} else {
			"SafeDITool exited with status \(terminationStatus): \(standardError)"
		}
	}
}

struct SafeDIToolLaunchError: Error, CustomStringConvertible {
	let underlyingError: Error

	var description: String {
		underlyingError.localizedDescription
	}
}

func runSafeDITool(
	at toolURL: URL,
	arguments: [String],
) throws {
	let process = Process()
	process.executableURL = toolURL
	process.arguments = arguments
	let errorPipe = Pipe()
	process.standardError = errorPipe
	do {
		try process.run()
	} catch {
		throw SafeDIToolLaunchError(underlyingError: error)
	}
	process.waitUntilExit()
	guard process.terminationStatus == 0 else {
		let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
		let errorString = String(data: errorData, encoding: .utf8) ?? ""
		throw SafeDIToolProcessError(
			terminationStatus: process.terminationStatus,
			standardError: errorString,
		)
	}
}
