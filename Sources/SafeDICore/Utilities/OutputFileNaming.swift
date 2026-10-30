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
/// Every returned name is unique ignoring letter case and Unicode normalization (`CaseInsensitiveFileName`), on every
/// platform, so that a volume that ignores letter case – macOS's default – holds each output as its own file: names
/// that differ only in letter case collide, as `A/Root.swift` and `B/root.swift` do, and are told apart by their
/// directories as `A_Root` and `B_root`. Each name keeps its file's spelling. When files that share a name still
/// collide once their directories are prepended – or a prepended name matches another file's name, as
/// `Feature/Root.swift` and `Feature_Root.swift` both become `Feature_Root` – the file whose path sorts first keeps
/// the name, and each other file, in path order, takes the name followed by the smallest `_2`, `_3`, … that no other
/// file's name uses. The result depends only on the set of input paths, not their order.
public func outputFileNames(forFilesAt inputFilePaths: [String]) -> [String] {
	uniqueOutputFileNameStems(forFilesAt: inputFilePaths).map { "\($0)+SafeDI.swift" }
}

/// Compute output file names for mock generation output files: one for each input file, named as
/// `outputFileNames(forFilesAt:)` names it, and one for each type `additionalMocksToGenerate` lists.
///
/// A listed type's mock is named after the type unless that name is a file's, or that of a listed type that comes
/// before it in type name order: then, in type name order, it takes the type name followed by the smallest `_2`,
/// `_3`, … that no other mock's name uses, so `Service` beside `Service.swift` (or `service.swift`) gets
/// `Service_2+SafeDIMock.swift`. Names are compared ignoring letter case and Unicode normalization; type name order
/// does not ignore letter case, so of the listed types `Service` and `service`, `service` gets
/// `service_2+SafeDIMock.swift`.
/// Listing a type therefore never renames a file's mock, and the result depends only on the set of input paths and
/// the set of type names, not their order.
public func mockOutputFileNames(
	forFilesAt inputFilePaths: [String],
	additionalMocksToGenerate: [String],
) -> (mockFiles: [String], additionalMocks: [String]) {
	let fileNameStems = uniqueOutputFileNameStems(forFilesAt: inputFilePaths)
	var usedNames = Set((fileNameStems + additionalMocksToGenerate).map(CaseInsensitiveFileName.init))
	var namesClaimedUnsuffixed = Set(fileNameStems.map(CaseInsensitiveFileName.init))
	var nameStemsByTypeName = [String: String]()
	for typeName in Set(additionalMocksToGenerate).sorted() {
		let keepsItsName = namesClaimedUnsuffixed.insert(CaseInsensitiveFileName(typeName)).inserted
		if !keepsItsName {
			nameStemsByTypeName[typeName] = claimSuffixedName(for: typeName, avoiding: &usedNames)
		}
	}
	return (
		mockFiles: fileNameStems.map { "\($0)+SafeDIMock.swift" },
		additionalMocks: additionalMocksToGenerate.map { "\(nameStemsByTypeName[$0] ?? $0)+SafeDIMock.swift" },
	)
}

/// A file name, or a path, as a volume that ignores letter case and Unicode normalization compares it, such as
/// macOS's default APFS volume: canonically decomposed and case folded. Two spellings that differ only in letter case,
/// or in how an accented letter is encoded, are equal. Output files are named apart under this comparison on every
/// platform, so the files a project generates do not depend on the volume that builds it.
struct CaseInsensitiveFileName: Hashable, Comparable, Sendable {
	init(_ name: String) {
		// Unicode's canonical caseless match decomposes before folding; `String` compares the folded result by
		// canonical equivalence.
		foldedName = name.decomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
	}

	static func < (lhs: CaseInsensitiveFileName, rhs: CaseInsensitiveFileName) -> Bool {
		lhs.foldedName < rhs.foldedName
	}

	private let foldedName: String
}

/// The output file name of each input file, without an extension, unique across the input files ignoring letter case
/// and Unicode normalization.
private func uniqueOutputFileNameStems(forFilesAt inputFilePaths: [String]) -> [String] {
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
	let groups = Dictionary(grouping: Array(fileInfo.enumerated()), by: { CaseInsensitiveFileName($0.element.baseName) })

	for entries in groups.values {
		guard entries.count > 1 else {
			let entry = entries[0]
			names[entry.offset] = entry.element.baseName
			continue
		}

		var namesByIndex = entries.reduce(into: [Int: String]()) { partialResult, entry in
			partialResult[entry.offset] = entry.element.baseName
		}

		var maxParentDepth = 0
		for entry in entries {
			maxParentDepth = max(maxParentDepth, entry.element.parentComponents.count)
		}
		if maxParentDepth > 0 {
			for parentDepth in 1...maxParentDepth where Set(namesByIndex.values.map(CaseInsensitiveFileName.init)).count < entries.count {
				for entry in entries {
					let prefix = entry.element.parentComponents
						.suffix(parentDepth)
						.joined(separator: "_")
					namesByIndex[entry.offset] = prefix.isEmpty ? entry.element.baseName : "\(prefix)_\(entry.element.baseName)"
				}
			}
		}

		for entry in entries {
			names[entry.offset] = namesByIndex[entry.offset, default: entry.element.baseName]
		}
	}

	// Files whose names still collide, within a group or across groups, keep the name only for the first path.
	var usedNames = Set(names.map(CaseInsensitiveFileName.init))
	let indicesByName = Dictionary(grouping: names.indices, by: { CaseInsensitiveFileName(names[$0]) })
	for (_, indices) in indicesByName.sorted(by: { $0.key < $1.key }) {
		for index in indices.sorted(by: { inputFilePaths[$0] < inputFilePaths[$1] }).dropFirst() {
			names[index] = claimSuffixedName(for: names[index], avoiding: &usedNames)
		}
	}

	return names
}

/// `name` followed by the smallest `_2`, `_3`, … that `usedNames` does not contain, ignoring letter case and Unicode
/// normalization, which is added to `usedNames`.
private func claimSuffixedName(for name: String, avoiding usedNames: inout Set<CaseInsensitiveFileName>) -> String {
	var nameSuffixNumber = 2
	while usedNames.contains(CaseInsensitiveFileName("\(name)_\(nameSuffixNumber)")) {
		nameSuffixNumber += 1
	}
	let suffixedName = "\(name)_\(nameSuffixNumber)"
	usedNames.insert(CaseInsensitiveFileName(suffixedName))
	return suffixedName
}
