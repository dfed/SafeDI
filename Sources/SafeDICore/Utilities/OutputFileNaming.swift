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

/// Compute output file names for the given input URLs, deduplicating basenames
/// by prepending parent directory components when collisions occur.
public func outputFileNames(
	for inputURLs: [URL],
	relativeTo baseURL: URL,
	suffix: String = "+SafeDI.swift",
) -> [String] {
	struct FileInfo {
		let relativePath: String
		let baseName: String
		let parentComponents: [String]
	}

	let fileInfo = inputURLs.map { inputURL in
		let relPath = relativePath(for: inputURL, relativeTo: baseURL)
		let relativeDirectory = (relPath as NSString).deletingLastPathComponent
		let parentComponents: [String] = if relativeDirectory.isEmpty || relativeDirectory == "." {
			[]
		} else {
			relativeDirectory
				.split(separator: "/")
				.map(String.init)
		}
		return FileInfo(
			relativePath: relPath,
			baseName: inputURL.deletingPathExtension().lastPathComponent,
			parentComponents: parentComponents,
		)
	}

	var outputFileNames = Array(repeating: "", count: fileInfo.count)
	let groups = Dictionary(grouping: Array(fileInfo.enumerated()), by: \.element.baseName)

	for (baseName, entries) in groups {
		guard entries.count > 1 else {
			let entry = entries[0]
			outputFileNames[entry.offset] = "\(baseName)\(suffix)"
			continue
		}

		var namesByIndex = entries.reduce(into: [Int: String]()) { partialResult, entry in
			partialResult[entry.offset] = baseName
		}

		var maxParentDepth = 0
		for entry in entries {
			maxParentDepth = max(maxParentDepth, entry.element.parentComponents.count)
		}
		if maxParentDepth > 0 {
			for parentDepth in 1...maxParentDepth where Set(namesByIndex.values).count < entries.count {
				for entry in entries {
					let prefix = entry.element.parentComponents
						.suffix(parentDepth)
						.joined(separator: "_")
					namesByIndex[entry.offset] = prefix.isEmpty ? baseName : "\(prefix)_\(baseName)"
				}
			}
		}

		for entry in entries {
			let name = namesByIndex[entry.offset, default: baseName]
			outputFileNames[entry.offset] = "\(name)\(suffix)"
		}
	}

	return outputFileNames
}

/// Compute output file names for mock generation output files.
public func mockOutputFileNames(
	for inputURLs: [URL],
	relativeTo baseURL: URL,
) -> [String] {
	outputFileNames(for: inputURLs, relativeTo: baseURL, suffix: "+SafeDIMock.swift")
}
