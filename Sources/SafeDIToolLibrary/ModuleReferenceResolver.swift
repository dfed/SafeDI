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

/// Resolves the references views hold to the entries they refer to, each read once from its module's own file: a file the
/// run was given, or else one `--transitive-module-info-file-path` lists. The first time a reference names a module the
/// given files do not describe, the resolver reads the first fields of every listed file (`ModuleInfoFile.Head`) to learn
/// which module each describes, and then reads whole, without its view, only each file a reference resolves to.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
actor ModuleReferenceResolver {
	init(transitiveModuleInfoListPath: String?) {
		self.transitiveModuleInfoListPath = transitiveModuleInfoListPath
	}

	/// Every file the resolver read whole to resolve a reference, as the transitive list spells it: the run reads its
	/// declarations and seam signatures, so a change to it can change the run's output.
	private(set) var openedPaths = Set<String>()
	/// Every file of the transitive list whose first fields the resolver read to learn which module it describes, as the
	/// list spells it. Its module name is all the run took from such a file.
	private(set) var headReadPaths = Set<String>()

	/// The entry each reference in the views of `files` resolves to, with those of the resolver's earlier calls: each
	/// module's once, outside any file's view, so that a module many views refer to is held, and compared, once.
	/// - Throws: `UnresolvableModuleReferenceError` when no file describes a referenced module, and
	///   `ModuleInfoDisagreementError` when the file that does describes it differently from the reference.
	func resolvingReferences(in files: [(file: ModuleInfoFile, path: String)]) async throws -> ResolvedModuleReferences {
		guard files.contains(where: { !$0.file.view.references.isEmpty }) else {
			return ResolvedModuleReferences(entriesByModuleName: ownEntries)
		}
		for (file, path) in files where ownEntries[file.moduleName] == nil {
			ownEntries[file.moduleName] = ResolvedModuleReferences.OwnEntry(file: file, path: path)
		}
		var referringPathsByUnresolvedName = [String: [String]]()
		for (file, path) in files {
			for reference in file.view.references where ownEntries[reference.moduleName] == nil {
				referringPathsByUnresolvedName[reference.moduleName, default: []].append(path)
			}
		}
		if !referringPathsByUnresolvedName.isEmpty {
			let headsByModuleName = try await transitiveHeadsByModuleName()
			var pathsToRead = [String]()
			for moduleName in referringPathsByUnresolvedName.keys.sorted(by: { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }) {
				guard let heads = headsByModuleName[moduleName] else {
					continue
				}
				// Two files that name a referenced module and describe it differently are reported, as two given files of
				// one module are, rather than one of them chosen.
				if let differing = heads.first(where: { $0.ownEntryChecksum != heads[0].ownEntryChecksum }) {
					throw ModuleInfoDisagreementError(moduleName: moduleName, filePaths: [heads[0].path, differing.path])
				}
				pathsToRead.append(heads[0].path)
			}
			pathsToRead.sort()
			for (listedPath, (file, path)) in try await zip(pathsToRead, Generate.loadSafeDIModuleInfo(at: pathsToRead, readingViews: false)) {
				openedPaths.insert(listedPath)
				if ownEntries[file.moduleName] == nil {
					ownEntries[file.moduleName] = ResolvedModuleReferences.OwnEntry(file: file, path: path)
				}
			}
		}
		if let (moduleName, referringPaths) = referringPathsByUnresolvedName
			.filter({ ownEntries[$0.key] == nil })
			.min(by: { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) })
		{
			throw UnresolvableModuleReferenceError(moduleName: moduleName, referringFilePaths: Set(referringPaths).sorted())
		}
		for (file, path) in files {
			for reference in file.view.references {
				// safedi-source-rule: allow forceUnwrap — every reference's module was resolved above, or the run threw.
				let ownEntry = ownEntries[reference.moduleName]!
				guard ownEntry.checksum == reference.checksum else {
					throw ModuleInfoDisagreementError(moduleName: reference.moduleName, filePaths: [path, ownEntry.path])
				}
			}
		}
		return ResolvedModuleReferences(entriesByModuleName: ownEntries)
	}

	// MARK: Private

	private let transitiveModuleInfoListPath: String?
	private var ownEntries = [String: ResolvedModuleReferences.OwnEntry]()
	private var cachedTransitiveHeadsByModuleName: [String: [(path: String, ownEntryChecksum: UInt64?)]]?

	/// The read of the head of the transitive list's file at `index`. A struct, never a tuple
	/// (`taskGroupTupleElement` in `.claude/rules/source-rules.md`).
	private struct HeadRead: Sendable {
		let index: Int
		let read: Result<ModuleInfoFile.Head, UnreadableModuleInfoError>
	}

	/// The files the transitive list names, as it spells them, with each one's own-entry checksum, by the module each names,
	/// in path order: read once, so which file a reference resolves to follows the module's name and the paths alone,
	/// never the order the reads finished in.
	private func transitiveHeadsByModuleName() async throws -> [String: [(path: String, ownEntryChecksum: UInt64?)]] {
		if let cachedTransitiveHeadsByModuleName {
			return cachedTransitiveHeadsByModuleName
		}
		var headsByModuleName = [String: [(path: String, ownEntryChecksum: UInt64?)]]()
		if let transitiveModuleInfoListPath {
			let paths = try Set(String(contentsOfFile: transitiveModuleInfoListPath, encoding: .utf8).parsedPathListCSV()).sorted()
			let reads = await withTaskGroup(
				of: HeadRead.self,
				returning: [HeadRead].self,
			) { taskGroup in
				for (index, path) in paths.enumerated() {
					taskGroup.addTask {
						HeadRead(index: index, read: Result { () throws(UnreadableModuleInfoError) in try UnreadableModuleInfoError.readingHead(path.asFileURL) })
					}
				}
				var reads = [HeadRead]()
				for await read in taskGroup {
					reads.append(read)
				}
				return reads
			}
			// The files are read in parallel, so their failures arrive in any order: the one reported is that of the first path.
			for headRead in reads.sorted(by: { $0.index < $1.index }) {
				let head = try headRead.read.get()
				headsByModuleName[head.moduleName, default: []].append((path: paths[headRead.index], ownEntryChecksum: head.ownEntryChecksum))
			}
			headReadPaths = Set(paths)
		}
		cachedTransitiveHeadsByModuleName = headsByModuleName
		return headsByModuleName
	}
}

/// The entries the references of a run's views resolve to, each module's read once from its own file, by module name.
/// Holds those entries, which the run's given files hold too, for as long as the run reads the views.
struct ResolvedModuleReferences: Sendable {
	/// A module's entry as its own file holds it, with the checksum of its bytes, which a reference to it holds.
	struct OwnEntry: Sendable {
		init(file: ModuleInfoFile, path: String) {
			entry = file.ownEntry
			checksum = file.ownEntryChecksum ?? entry.checksum
			self.path = path
		}

		let entry: ViewedModule
		let checksum: UInt64
		let path: String
	}

	let entriesByModuleName: [String: OwnEntry]

	/// The declarations `view` carries: its copies, then the entry each of its references resolves to, each with the
	/// checksum it is known by, which a copy is not.
	func entries(of view: ModuleInfoView) -> [ViewedModuleEntry] {
		view.declarations.map { ViewedModuleEntry(entry: $0, checksum: nil) }
			+ view.references.compactMap { entriesByModuleName[$0.moduleName].map { ViewedModuleEntry(entry: $0.entry, checksum: $0.checksum) } }
	}
}

/// A module's declarations as a view carries them, with the checksum of their bytes (`ViewedModule.checksum`) when it is
/// known without encoding them: a reference's, or a file's stored checksum of its own entry.
struct ViewedModuleEntry: Sendable {
	let entry: ViewedModule
	let checksum: UInt64?
}
