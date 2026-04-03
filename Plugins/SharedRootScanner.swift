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

func runRootScanner(
	inputSourcesFile: URL,
	projectRoot: URL,
	outputDirectory: URL,
	manifestFile: URL,
) throws -> [URL] {
	let inputFilePaths = try RootScanner.inputFilePaths(from: inputSourcesFile)

	// Check target files for @SafeDIConfiguration to discover additional directories.
	let directoryBaseURL = projectRoot.hasDirectoryPath
		? projectRoot
		: projectRoot.appendingPathComponent("", isDirectory: true)
	var additionalSwiftFiles = [URL]()
	for inputFilePath in inputFilePaths {
		let fileURL = URL(fileURLWithPath: inputFilePath, relativeTo: directoryBaseURL).standardizedFileURL
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
		let directories = RootScanner.extractAdditionalDirectoriesToInclude(in: content)
		for directory in directories {
			let directoryURL = URL(fileURLWithPath: directory, relativeTo: directoryBaseURL)
			guard let enumerator = FileManager.default.enumerator(
				at: directoryURL,
				includingPropertiesForKeys: nil,
				options: [.skipsHiddenFiles],
			) else { continue }
			for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
				additionalSwiftFiles.append(fileURL)
			}
		}
	}

	// Scan target files + additional directory files together for roots.
	let targetSwiftFiles = inputFilePaths.map {
		URL(fileURLWithPath: $0, relativeTo: directoryBaseURL).standardizedFileURL
	}
	let allSwiftFiles = targetSwiftFiles + additionalSwiftFiles
	let result = try RootScanner().scan(
		swiftFiles: allSwiftFiles,
		relativeTo: projectRoot,
		outputDirectory: outputDirectory,
	)
	try result.writeManifest(to: manifestFile)
	return result.outputFiles
}
