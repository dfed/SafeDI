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
import SafeDICore

/// What a `.safedi` module info file holds: the module's own declarations, under the name of the module it describes,
/// and its view of the modules it depends on.
///
/// Under every integration that runs `generate` once per module, a module is given the `.safedi` of each module it
/// depends on – each module whose types its own trees build, so a module that declares a root is given every module
/// beneath it, which the Bazel rule collects (`--transitive-module-info-file-path`, of which the module reads what its
/// trees need), any other build lists, and a custom build may pass the same way – and never one only for another module's seam or public mock. A seam or public mock another module
/// declares is called with the signature that module's run computed, from the declarations it read, so each file
/// carries in its `view` what a module that depends on it needs to compute any such signature in its closure: the
/// name, package, dependencies and mock condition of every module in the closure, and the declarations – without
/// positions – of each module in it that declares a seam or a public mock and of the modules those depend on
/// directly.
public struct ModuleInfoFile: Codable, Sendable {
	init(
		moduleName: String,
		ownEntryChecksum: UInt64? = nil,
		packageName: String?,
		dependencyModuleNames: [String],
		imports: [ImportStatement],
		mockImports: [ImportStatement],
		instantiables: [Instantiable],
		configurations: [SafeDIConfiguration],
		filesWithUnexpectedNodes: [String]?,
		conditionalCompilationDecisions: [ConditionalCompilationDecision],
		instantiableTypeNamesInAnyClause: [String],
		plainTypeDeclarations: [PlainTypeDeclaration],
		seamSignatures: [StoredSeamSignature],
		view: ModuleInfoView,
	) {
		self.moduleName = moduleName
		self.ownEntryChecksum = ownEntryChecksum
		self.packageName = packageName
		self.dependencyModuleNames = dependencyModuleNames
		self.imports = imports
		self.mockImports = mockImports
		self.instantiables = instantiables
		self.configurations = configurations
		self.filesWithUnexpectedNodes = filesWithUnexpectedNodes
		self.conditionalCompilationDecisions = conditionalCompilationDecisions
		self.instantiableTypeNamesInAnyClause = instantiableTypeNamesInAnyClause
		self.plainTypeDeclarations = plainTypeDeclarations
		self.seamSignatures = seamSignatures
		self.view = view
	}

	/// The file of `module`, named `moduleName`, which a run that writes a module info file always knows.
	/// - Parameter storesOwnEntryChecksum: Whether the file stores the checksum of its own entry, which a view that refers to
	///   the module holds: written by a run whose view refers to modules, so that every file a reference can name has it.
	public init(module: ModuleInfo, moduleName: String, seamSignatures: [StoredSeamSignature], view: ModuleInfoView, storesOwnEntryChecksum: Bool = false) {
		self.init(
			moduleName: moduleName,
			packageName: module.packageName,
			dependencyModuleNames: module.dependencyModuleNames,
			imports: module.imports,
			mockImports: module.mockImports,
			instantiables: module.instantiables,
			configurations: module.configurations.map(\.asHeldByModuleInfoFile),
			filesWithUnexpectedNodes: module.filesWithUnexpectedNodes,
			conditionalCompilationDecisions: module.conditionalCompilationDecisions,
			instantiableTypeNamesInAnyClause: module.instantiableTypeNamesInAnyClause,
			plainTypeDeclarations: module.plainTypeDeclarations,
			seamSignatures: seamSignatures,
			view: view,
		)
		if storesOwnEntryChecksum {
			ownEntryChecksum = ownEntry.checksum
		}
	}

	/// The module the file describes.
	let moduleName: String
	/// The checksum of the bytes of `ownEntry`, which a view that refers to this module holds, when the run that wrote the
	/// file stored it. Written right after `moduleName`, so a reader finds both without reading the rest of the file
	/// (`ModuleInfoFile.Head`).
	private(set) var ownEntryChecksum: UInt64?
	/// See `ModuleInfo.packageName`.
	let packageName: String?
	/// See `ModuleInfo.dependencyModuleNames`.
	let dependencyModuleNames: [String]
	/// See `ModuleInfo.imports`.
	let imports: [ImportStatement]
	/// See `ModuleInfo.mockImports`.
	let mockImports: [ImportStatement]
	/// See `ModuleInfo.instantiables`.
	let instantiables: [Instantiable]
	/// See `ModuleInfo.configurations`.
	let configurations: [SafeDIConfiguration]
	/// See `ModuleInfo.filesWithUnexpectedNodes`.
	let filesWithUnexpectedNodes: [String]?
	/// See `ModuleInfo.conditionalCompilationDecisions`.
	let conditionalCompilationDecisions: [ConditionalCompilationDecision]
	/// See `ModuleInfo.instantiableTypeNamesInAnyClause`.
	let instantiableTypeNamesInAnyClause: [String]
	/// See `ModuleInfo.plainTypeDeclarations`.
	let plainTypeDeclarations: [PlainTypeDeclaration]
	/// The signature of each seam the module declares, sorted by seam, as the module's run computed it: a module that
	/// calls one reads it here rather than computing it again. Empty for a module that declares no seam.
	let seamSignatures: [StoredSeamSignature]
	/// What the module's dependents need of the modules it depends on, directly or not.
	let view: ModuleInfoView

	/// The module's own declarations.
	public var module: ModuleInfo {
		ModuleInfo(
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			instantiableTypeNamesInAnyClause: instantiableTypeNamesInAnyClause,
			moduleName: moduleName,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
			plainTypeDeclarations: plainTypeDeclarations,
		)
	}

	/// The module as its dependents' views name it.
	var ownIdentity: ViewedModuleIdentity {
		ViewedModuleIdentity(
			moduleName: moduleName,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
			// The condition the module's own run guards its mocks with: its configuration's, `DEBUG` without one.
			mockConditionalCompilation: configurations.first.map(\.mockConditionalCompilation) ?? "DEBUG",
		)
	}

	/// This file with `view` in place of its own.
	func replacingView(with view: ModuleInfoView) -> ModuleInfoFile {
		ModuleInfoFile(
			moduleName: moduleName,
			ownEntryChecksum: ownEntryChecksum,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			instantiableTypeNamesInAnyClause: instantiableTypeNamesInAnyClause,
			plainTypeDeclarations: plainTypeDeclarations,
			seamSignatures: seamSignatures,
			view: view,
		)
	}

	/// The module's declarations as its dependents' views hold them.
	var ownEntry: ViewedModule {
		ViewedModule(
			moduleName: moduleName,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables.map { $0.withoutPositions() },
			plainTypeDeclarations: plainTypeDeclarations.map { $0.withoutPositions() },
			seamSignatures: seamSignatures,
		)
	}

	/// This file without the seam signatures it and its view carry, which leaves each module that reads it to compute them
	/// from the declarations, as a run under the SwiftPM plugin's target graph does: the graph fuzzer compares the two.
	public var withoutSeamSignatures: ModuleInfoFile {
		ModuleInfoFile(
			moduleName: moduleName,
			ownEntryChecksum: ownEntryChecksum,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			instantiableTypeNamesInAnyClause: instantiableTypeNamesInAnyClause,
			plainTypeDeclarations: plainTypeDeclarations,
			seamSignatures: [],
			view: ModuleInfoView(
				moduleGraph: view.moduleGraph,
				declarations: view.declarations.map { ViewedModule(moduleName: $0.moduleName, imports: $0.imports, mockImports: $0.mockImports, instantiables: $0.instantiables, plainTypeDeclarations: $0.plainTypeDeclarations, seamSignatures: []) },
				references: view.references,
			),
		)
	}

	/// Whether the module declares a type whose signature a dependent computes from the modules this one depends on: a
	/// seam (`generateDependencyTree: true`) or a public mock (`generateMock: .public`).
	var declaresSeamOrPublicMock: Bool {
		instantiables.contains(where: \.declaresSeamOrPublicMock)
	}
}

/// What a `.safedi` file carries of the modules its module depends on, directly or not, each section sorted by module
/// name, compared by the bytes of its UTF-8 spelling.
public struct ModuleInfoView: Codable, Sendable {
	/// The modules of the closure, without their declarations: names only, so this changes when a module is added,
	/// renamed or depends on others, never on an edit.
	/// Always a copy, even where `references` stand for the declarations: a reference's checksum leaves out the seam
	/// signatures, which read the graph (`ViewedModule.checksum`).
	let moduleGraph: [ViewedModuleIdentity]
	/// The declarations of each module in the closure that declares a seam or a public mock, and of each module such a
	/// module depends on directly, each once.
	let declarations: [ViewedModule]
	/// The modules whose declarations the view carries by reference instead: each module's name and the checksum of its
	/// own entry, which a reader finds in that module's own file.
	let references: [ViewedModuleReference]

	init(moduleGraph: [ViewedModuleIdentity], declarations: [ViewedModule], references: [ViewedModuleReference] = []) {
		self.moduleGraph = moduleGraph
		self.declarations = declarations
		self.references = references
	}

	/// The view of a module that depends on nothing.
	public static let empty = ModuleInfoView(moduleGraph: [], declarations: [])
}

extension ViewedModule {
	/// The checksum a reference to this entry's module holds: of the bytes the entry is written as without its seam
	/// signatures. Each signature follows from the declarations of the module and of the modules its run read, the
	/// signatures of the seams it reaches, and the module graph (each module's dependencies, package and mock condition,
	/// which the access proofs read). A view that refers to this module refers to those modules as well, and carries the
	/// module graph as a copy, so a change that changes a signature changes some reference's checksum or the graph; and a
	/// file whose signatures are taken out (`ModuleInfoFile.withoutSeamSignatures`) keeps its references. A view that
	/// referred to the module graph instead would need this checksum to cover it.
	var checksum: UInt64 {
		MergedModuleInfoView.encoded(
			ViewedModule(moduleName: moduleName, imports: imports, mockImports: mockImports, instantiables: instantiables, plainTypeDeclarations: plainTypeDeclarations, seamSignatures: []),
		).withUnsafeBytes(BinaryFile.checksum(of:))
	}
}

/// A module whose declarations a view carries by reference: its name, and the checksum of the bytes of its own entry
/// (`ModuleInfoFile.ownEntry`), which has no positions, so a position-only edit leaves it unchanged.
struct ViewedModuleReference: Codable {
	let moduleName: String
	let checksum: UInt64
}

/// A module in a view's module graph.
struct ViewedModuleIdentity: Codable {
	let moduleName: String
	let packageName: String?
	/// The modules whose module info the module's run read: those it depends on directly and, in a module that generates
	/// a dependency tree under the Bazel rule, those beneath them that its trees need.
	let dependencyModuleNames: [String]
	/// The condition the module guards its mocks and mock-only declarations with, `nil` for a module whose mocks no
	/// condition guards.
	let mockConditionalCompilation: String?
}

/// The declarations of a module in a view, as the module recorded them, without positions. They are not normalized:
/// normalization qualifies a nested type among the declarations a run sees, which differ between the module that
/// reads the view and the module whose signature it computes.
struct ViewedModule: Codable {
	let moduleName: String
	let imports: [ImportStatement]
	let mockImports: [ImportStatement]
	let instantiables: [Instantiable]
	let plainTypeDeclarations: [PlainTypeDeclaration]
	/// See `ModuleInfoFile.seamSignatures`.
	let seamSignatures: [StoredSeamSignature]

	/// Whether the module declares a seam or a public mock.
	var declaresSeamOrPublicMock: Bool {
		instantiables.contains(where: \.declaresSeamOrPublicMock)
	}
}

extension Instantiable {
	/// Whether the declaration is of a type whose signature a module that calls it computes: a seam
	/// (`generateDependencyTree: true`) or a public mock (`generateMock: .public`).
	fileprivate var declaresSeamOrPublicMock: Bool {
		generatesDependencyTree || generateMock == .public
	}
}

extension ModuleInfoFile {
	/// Reads the module info file `data` holds.
	public init(moduleInfoData data: Data) throws(BinaryFileReadError) {
		self = try BinaryFile.value(.moduleInfo, from: data)
	}

	/// The fields a module info file writes first: the module it describes and, when stored, the checksum of its own
	/// entry. Read without the body's checksum or any later field, so finding which file describes a module costs little
	/// whatever the file holds; a file a reference resolves to is then read whole, which checks it.
	struct Head {
		let moduleName: String
		let ownEntryChecksum: UInt64?

		init(moduleInfoData data: Data) throws(BinaryFileReadError) {
			self = try BinaryFile.value(.moduleInfo, from: data, checksBody: false) { (reader: inout BinaryReader) throws(BinaryDecodingError) in
				try Head(moduleName: reader.read(), ownEntryChecksum: reader.read() as UInt64?)
			}
		}

		private init(moduleName: String, ownEntryChecksum: UInt64?) {
			self.moduleName = moduleName
			self.ownEntryChecksum = ownEntryChecksum
		}
	}

	/// Reads the module info file `data` holds without its view, which is left empty.
	init(moduleInfoDataWithoutView data: Data) throws(BinaryFileReadError) {
		self = try BinaryFile.value(.moduleInfo, from: data) { (reader: inout BinaryReader) throws(BinaryDecodingError) in
			try ModuleInfoFile(readingAllButViewFrom: &reader)
		}
	}

	/// This module as a module info file.
	public var moduleInfoData: Data {
		get throws(BinaryFileWriteError) {
			try BinaryFile.data(.moduleInfo, holding: self)
		}
	}
}

/// The modules a run of `generate` reads through the module info files it was given: each file's own module, and the
/// modules each file's view carries, each once.
struct MergedModuleInfoView {
	/// Merges the views of `directModules`, the files a run was given, in path order.
	/// - Parameters:
	///   - directModules: Each file with the path it was read from.
	///   - ownModuleDeclaresSeamOrPublicMock: Whether the module the run generates code for declares a seam or a public
	///     mock, whose signature its dependents compute from the modules it depends on directly.
	/// - Throws: `ModuleInfoDisagreementError` when two files describe one module differently.
	init(directModules: [(file: ModuleInfoFile, path: String)], ownModuleDeclaresSeamOrPublicMock: Bool, viewsReferToModules: Bool = false) throws(ModuleInfoDisagreementError) {
		var identities = [String: (identity: ViewedModuleIdentity, bytes: [UInt8], path: String)]()
		var declarations = [String: (entry: ViewedModule, bytes: [UInt8], path: String)]()
		var writtenDeclarationNames = Set<String>()
		func merge(_ identity: ViewedModuleIdentity, from path: String) throws(ModuleInfoDisagreementError) {
			let bytes = Self.encoded(identity)
			if let existing = identities[identity.moduleName] {
				guard existing.bytes == bytes else {
					throw ModuleInfoDisagreementError(moduleName: identity.moduleName, filePaths: [existing.path, path])
				}
			} else {
				identities[identity.moduleName] = (identity, bytes, path)
			}
		}
		func merge(_ entry: ViewedModule, from path: String) throws(ModuleInfoDisagreementError) {
			let bytes = Self.encoded(entry)
			if let existing = declarations[entry.moduleName] {
				guard existing.bytes == bytes else {
					throw ModuleInfoDisagreementError(moduleName: entry.moduleName, filePaths: [existing.path, path])
				}
			} else {
				declarations[entry.moduleName] = (entry, bytes, path)
			}
		}
		// A file's own module first, so a module given both directly and in a view is read from its own file.
		for (file, path) in directModules {
			try merge(file.ownIdentity, from: path)
			try merge(file.ownEntry, from: path)
			// A dependent of the run's module computes its signature from the modules it depends on directly, and a
			// dependent of a direct module that declares one computes that module's from this file.
			if file.declaresSeamOrPublicMock || ownModuleDeclaresSeamOrPublicMock {
				writtenDeclarationNames.insert(file.moduleName)
			}
		}
		for (file, path) in directModules {
			for identity in file.view.moduleGraph {
				try merge(identity, from: path)
			}
			for entry in file.view.declarations {
				try merge(entry, from: path)
				writtenDeclarationNames.insert(entry.moduleName)
			}
		}
		// A module's file and every view carry the same signatures of its seams, without positions.
		let directModuleNames = Set(directModules.map(\.file.moduleName))
		var storedSeamSignatures = [String: [StoredSeamSignature]]()
		for (moduleName, declaration) in declarations where !declaration.entry.seamSignatures.isEmpty {
			storedSeamSignatures[moduleName] = declaration.entry.seamSignatures
		}
		storedSeamSignaturesByModuleName = storedSeamSignatures
		identitiesByModuleName = identities.mapValues(\.identity)
		declarationsByModuleName = declarations.mapValues(\.entry)
		self.directModuleNames = directModuleNames
		let moduleGraph = identities.values.map(\.identity).sorted { Array($0.moduleName.utf8).lexicographicallyPrecedes(Array($1.moduleName.utf8)) }
		let writtenNames = writtenDeclarationNames.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
		view = if viewsReferToModules {
			ModuleInfoView(
				moduleGraph: moduleGraph,
				declarations: [],
				references: writtenNames.compactMap { name in
					declarations[name].map { ViewedModuleReference(moduleName: name, checksum: $0.entry.checksum) }
				},
			)
		} else {
			ModuleInfoView(
				moduleGraph: moduleGraph,
				declarations: writtenNames.compactMap { declarations[$0]?.entry },
			)
		}
	}

	/// Every module the files name or carry, by name.
	let identitiesByModuleName: [String: ViewedModuleIdentity]
	/// The declarations of each module the files carry, by name: every given file's own module, and each module a view
	/// carries the declarations of.
	let declarationsByModuleName: [String: ViewedModule]
	/// The modules whose files the run was given.
	let directModuleNames: Set<String>
	/// The signatures of the seams of each module the files carry the declarations of, by module name: the file's own,
	/// with positions, for a module whose file the run was given.
	let storedSeamSignaturesByModuleName: [String: [StoredSeamSignature]]
	/// The view the run's own module info file carries.
	let view: ModuleInfoView

	/// The declarations the views carry of modules whose files the run was not given, sorted by module name.
	var viewOnlyDeclarations: [ViewedModule] {
		declarationsByModuleName.values
			.filter { !directModuleNames.contains($0.moduleName) }
			.sorted { Array($0.moduleName.utf8).lexicographicallyPrecedes(Array($1.moduleName.utf8)) }
	}

	/// The bytes `value` is written as, which two entries for one module must share: `==` ignores `any` at every depth
	/// and the order inside an `UnorderedEquatingCollection`, which the bytes do not.
	static func encoded(_ value: some BinaryCodable) -> [UInt8] {
		var writer = BinaryWriter()
		writer.write(value)
		return writer.encoded
	}
}

/// Two module info files describe one module differently: a stale file beside a current one, or two builds of one
/// module.
struct ModuleInfoDisagreementError: Error, CustomStringConvertible {
	init(moduleName: String, filePaths: [String]) {
		self.moduleName = moduleName
		self.filePaths = filePaths.sorted()
	}

	let moduleName: String
	/// The two files, sorted.
	let filePaths: [String]

	var description: String {
		"SafeDI was given two module infos that describe module `\(moduleName)` differently: \(filePaths.map { "`\($0)`" }.joined(separator: " and ")) were written against two different builds of `\(moduleName)`. Build `\(moduleName)` and the modules that depend on it again, so that every module info is written against the current one."
	}
}

/// A view refers to a module whose own file the run was not given.
struct UnresolvableModuleReferenceError: Error, CustomStringConvertible {
	let moduleName: String
	/// The files whose views refer to the module, sorted.
	let referringFilePaths: [String]

	var description: String {
		"SafeDI could not find the module info of module `\(moduleName)`, which \(referringFilePaths.map { "`\($0)`" }.joined(separator: " and ")) \(referringFilePaths.count == 1 ? "refers" : "refer") to: a view that refers to modules is read with the module info of every module beneath, which SafeDI’s Bazel rule passes with `--transitive-module-info-file-path`. Pass the module info of `\(moduleName)` that way, or build the modules without `--module-info-views-refer-to-modules`."
	}
}
