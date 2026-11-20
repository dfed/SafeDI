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

/// Replaces the references a view holds with the entries they refer to, each read from its module's own file: a file the
/// run was given, or else one `--transitive-module-info-file-path` lists, all of which are read, without their views,
/// the first time a reference names a module the given files do not describe.
actor ModuleReferenceResolver {
	init(transitiveModuleInfoListPath: String?) {
		self.transitiveModuleInfoListPath = transitiveModuleInfoListPath
	}

	/// Every file this resolver opened to find a referenced module, as the transitive list spells it.
	private(set) var openedPaths = Set<String>()

	/// `files` with every reference in their views replaced by the entry it refers to.
	/// - Throws: `UnresolvableModuleReferenceError` when no file describes a referenced module, and
	///   `ModuleInfoDisagreementError` when the file that does describes it differently from the reference.
	func resolvingReferences(in files: [(file: ModuleInfoFile, path: String)]) async throws -> [(file: ModuleInfoFile, path: String)] {
		guard files.contains(where: { !$0.file.view.references.isEmpty }) else {
			return files
		}
		for (file, path) in files where ownEntries[file.moduleName] == nil {
			ownEntries[file.moduleName] = OwnEntry(file: file, path: path)
		}
		var referringPathsByUnresolvedName = [String: [String]]()
		for (file, path) in files {
			for reference in file.view.references where ownEntries[reference.moduleName] == nil {
				referringPathsByUnresolvedName[reference.moduleName, default: []].append(path)
			}
		}
		if !referringPathsByUnresolvedName.isEmpty, !hasReadTransitiveFiles {
			hasReadTransitiveFiles = true
			if let transitiveModuleInfoListPath {
				let paths = try Set(String(contentsOfFile: transitiveModuleInfoListPath, encoding: .utf8).parsedPathListCSV()).sorted()
				// Every file opened counts as an input the run used, spelled as the list spells it, whether or not it
				// resolves a reference: which module a file describes is known only once it is open.
				for (listedPath, (file, path)) in try await zip(paths, Generate.loadSafeDIModuleInfo(at: paths, readingViews: false)) {
					openedPaths.insert(listedPath)
					if ownEntries[file.moduleName] == nil {
						ownEntries[file.moduleName] = OwnEntry(file: file, path: path)
					}
				}
			}
		}
		if let (moduleName, referringPaths) = referringPathsByUnresolvedName.min(by: { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }),
		   ownEntries[moduleName] == nil
		{
			throw UnresolvableModuleReferenceError(moduleName: moduleName, referringFilePaths: Set(referringPaths).sorted())
		}
		return try files.map { file, path in
			guard !file.view.references.isEmpty else {
				return (file, path)
			}
			var declarations = file.view.declarations
			for reference in file.view.references {
				guard let ownEntry = ownEntries[reference.moduleName] else {
					throw UnresolvableModuleReferenceError(moduleName: reference.moduleName, referringFilePaths: [path])
				}
				guard ownEntry.checksum == reference.checksum else {
					throw ModuleInfoDisagreementError(moduleName: reference.moduleName, filePaths: [path, ownEntry.path])
				}
				declarations.append(ownEntry.entry)
			}
			return (
				file.replacingView(with: ModuleInfoView(moduleGraph: file.view.moduleGraph, declarations: declarations)),
				path,
			)
		}
	}

	// MARK: Private

	private struct OwnEntry {
		init(file: ModuleInfoFile, path: String) {
			entry = file.ownEntry
			checksum = MergedModuleInfoView.encoded(entry).withUnsafeBytes(BinaryFile.checksum(of:))
			self.path = path
		}

		let entry: ViewedModule
		let checksum: UInt64
		let path: String
	}

	private let transitiveModuleInfoListPath: String?
	private var ownEntries = [String: OwnEntry]()
	private var hasReadTransitiveFiles = false
}
