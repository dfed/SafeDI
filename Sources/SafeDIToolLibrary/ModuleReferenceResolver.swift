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
/// run was given, or else one `--transitive-module-info-file-path` lists. The first time a reference names a module the
/// given files do not describe, the resolver reads the first fields of every listed file (`ModuleInfoFile.Head`) to learn
/// which module each describes, and then reads whole, without its view, only each file a reference resolves to.
actor ModuleReferenceResolver {
	init(transitiveModuleInfoListPath: String?) {
		self.transitiveModuleInfoListPath = transitiveModuleInfoListPath
	}

	/// Every file the resolver read whole to resolve a reference, as the transitive list spells it.
	private(set) var openedPaths = Set<String>()
	/// Every file of the transitive list whose first fields the resolver read to learn which module it describes, as the
	/// list spells it. Its module name is all the run took from such a file.
	private(set) var headReadPaths = Set<String>()

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
		if !referringPathsByUnresolvedName.isEmpty {
			let pathsByModuleName = try await transitivePathsByModuleName()
			let pathsToRead = referringPathsByUnresolvedName.keys.compactMap { pathsByModuleName[$0] }.sorted()
			for (listedPath, (file, path)) in try await zip(pathsToRead, Generate.loadSafeDIModuleInfo(at: pathsToRead, readingViews: false)) {
				openedPaths.insert(listedPath)
				if ownEntries[file.moduleName] == nil {
					ownEntries[file.moduleName] = OwnEntry(file: file, path: path)
				}
			}
		}
		if let (moduleName, referringPaths) = referringPathsByUnresolvedName
			.filter({ ownEntries[$0.key] == nil })
			.min(by: { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) })
		{
			throw UnresolvableModuleReferenceError(moduleName: moduleName, referringFilePaths: Set(referringPaths).sorted())
		}
		return try files.map { file, path in
			guard !file.view.references.isEmpty else {
				return (file, path)
			}
			var declarations = file.view.declarations
			for reference in file.view.references {
				// safedi-source-rule: allow forceUnwrap — every reference's module was resolved above, or the run threw.
				let ownEntry = ownEntries[reference.moduleName]!
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
			checksum = file.ownEntryChecksum ?? entry.checksum
			self.path = path
		}

		let entry: ViewedModule
		let checksum: UInt64
		let path: String
	}

	private let transitiveModuleInfoListPath: String?
	private var ownEntries = [String: OwnEntry]()
	private var cachedTransitivePathsByModuleName: [String: String]?

	/// The path of each module's file among those the transitive list names, read once: the first in path order where two
	/// files describe one module, as a module given twice is read once.
	private func transitivePathsByModuleName() async throws -> [String: String] {
		if let cachedTransitivePathsByModuleName {
			return cachedTransitivePathsByModuleName
		}
		var pathsByModuleName = [String: String]()
		if let transitiveModuleInfoListPath {
			let paths = try Set(String(contentsOfFile: transitiveModuleInfoListPath, encoding: .utf8).parsedPathListCSV()).sorted()
			let heads = try await withThrowingTaskGroup(of: (index: Int, head: ModuleInfoFile.Head).self) { taskGroup in
				for (index, path) in paths.enumerated() {
					taskGroup.addTask {
						do {
							return try (index, ModuleInfoFile.Head(moduleInfoData: Data(contentsOf: path.asFileURL)))
						} catch let error as BinaryFileReadError {
							throw UnreadableModuleInfoError(path: path.asFileURL.path, reason: error)
						}
					}
				}
				var heads = [(index: Int, head: ModuleInfoFile.Head)]()
				for try await head in taskGroup {
					heads.append(head)
				}
				return heads.sorted { $0.index < $1.index }
			}
			for (index, head) in heads where pathsByModuleName[head.moduleName] == nil {
				pathsByModuleName[head.moduleName] = paths[index]
			}
			headReadPaths = Set(paths)
		}
		cachedTransitivePathsByModuleName = pathsByModuleName
		return pathsByModuleName
	}
}
