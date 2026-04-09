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

func runSafeDITool(
	at toolURL: URL,
	arguments: [String],
) throws {
	let process = Process()
	process.executableURL = toolURL
	process.arguments = arguments
	let errorPipe = Pipe()
	process.standardError = errorPipe
	try process.run()
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
