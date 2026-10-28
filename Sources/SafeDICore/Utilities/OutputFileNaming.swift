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

/// Compute output file names for the given input files, each named relative to the project root (or absolute for a
/// file outside it), deduplicating basenames by prepending the components of their directories when collisions occur.
///
/// Every returned name is unique. When files that share a name still collide once their directories are prepended –
/// or a prepended name matches another file's name, as `Feature/Root.swift` and `Feature_Root.swift` both become
/// `Feature_Root` – the file whose path sorts first keeps the name, and each other file, in path order, takes the
/// name followed by the smallest `_2`, `_3`, … that no other file's name uses. The result depends only on the set of
/// input paths, not their order.
public func outputFileNames(
	forFilesAt inputFilePaths: [String],
	suffix: String = "+SafeDI.swift",
) -> [String] {
	struct FileInfo {
		let baseName: String
		let parentComponents: [String]
	}

	let fileInfo = inputFilePaths.map { inputFilePath in
		let relativeDirectory = (inputFilePath as NSString).deletingLastPathComponent
		let parentComponents: [String] = if relativeDirectory.isEmpty || relativeDirectory == "." {
			[]
		} else {
			relativeDirectory
				.split(separator: "/")
				.map(String.init)
		}
		return FileInfo(
			baseName: ((inputFilePath as NSString).lastPathComponent as NSString).deletingPathExtension,
			parentComponents: parentComponents,
		)
	}

	var names = Array(repeating: "", count: fileInfo.count)
	let groups = Dictionary(grouping: Array(fileInfo.enumerated()), by: \.element.baseName)

	for (baseName, entries) in groups {
		guard entries.count > 1 else {
			let entry = entries[0]
			names[entry.offset] = baseName
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
			names[entry.offset] = namesByIndex[entry.offset, default: baseName]
		}
	}

	// Files whose names still collide, within a group or across groups, keep the name only for the first path.
	var usedNames = Set(names)
	let indicesByName = Dictionary(grouping: names.indices, by: { names[$0] })
	for (name, indices) in indicesByName.sorted(by: { $0.key < $1.key }) {
		var nameSuffixNumber = 2
		for index in indices.sorted(by: { inputFilePaths[$0] < inputFilePaths[$1] }).dropFirst() {
			while usedNames.contains("\(name)_\(nameSuffixNumber)") {
				nameSuffixNumber += 1
			}
			names[index] = "\(name)_\(nameSuffixNumber)"
			usedNames.insert(names[index])
		}
	}

	return names.map { "\($0)\(suffix)" }
}

/// Compute output file names for mock generation output files.
public func mockOutputFileNames(forFilesAt inputFilePaths: [String]) -> [String] {
	outputFileNames(forFilesAt: inputFilePaths, suffix: "+SafeDIMock.swift")
}
