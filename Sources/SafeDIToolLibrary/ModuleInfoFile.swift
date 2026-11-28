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
		seamSignatures: ModuleSeamSignatures,
		publicMockPlans: ModulePublicMockPlans = .empty,
		view: ModuleInfoView,
		locationCountsByFilePath: [String: Int] = [:],
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
		self.publicMockPlans = publicMockPlans
		self.view = view
		self.locationCountsByFilePath = locationCountsByFilePath
	}

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
		self.init(
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
			seamSignatures: ModuleSeamSignatures(seamSignatures),
			view: view,
		)
	}

	/// The file of `module`, named `moduleName`, which a run that writes a module info file always knows.
	/// - Parameter storesOwnEntryChecksum: Whether the file stores the checksum of its own entry, which a view that refers to
	///   the module holds: written by a run whose view refers to modules, so that every file a reference can name has it.
	/// - Parameter publicMockPlans: The plan the run computed of each public mock the module declares, and whether the
	///   run compiles the mocks it generates, which the plans depend on.
	public init(
		module: ModuleInfo,
		moduleName: String,
		seamSignatures: [StoredSeamSignature],
		publicMockPlans: [StoredPublicMockPlan] = [],
		compilesGeneratedMocks: Bool = false,
		view: ModuleInfoView,
		storesOwnEntryChecksum: Bool = false,
	) {
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
			seamSignatures: ModuleSeamSignatures(seamSignatures),
			publicMockPlans: ModulePublicMockPlans(publicMockPlans, compilesGeneratedMocks: compilesGeneratedMocks),
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
	let seamSignatures: ModuleSeamSignatures
	/// The plan of each public mock the module declares, sorted by mocked type, as the module's run computed it: a module
	/// whose mocks call one reads it here rather than computing it again. Empty for a module that declares no public mock.
	let publicMockPlans: ModulePublicMockPlans
	/// What the module's dependents need of the modules it depends on, directly or not.
	let view: ModuleInfoView
	/// For each file of the module's own declarations, the number of distinct locations the module recorded there, as a
	/// read of the file finds it: the highest rank it read in that file (`Dependency.DeclarationLocation.order`). The file
	/// stores no line or column, so a run that reads a declaration's file again to locate it can check that the file still
	/// holds as many. Empty for a file not read from a module info file. Not written: it follows from the locations.
	var locationCountsByFilePath = [String: Int]()

	/// Every field `dump` prints: the fields the file is written as.
	private enum CodingKeys: String, CodingKey {
		case moduleName
		case ownEntryChecksum
		case packageName
		case dependencyModuleNames
		case imports
		case mockImports
		case instantiables
		case configurations
		case filesWithUnexpectedNodes
		case conditionalCompilationDecisions
		case instantiableTypeNamesInAnyClause
		case plainTypeDeclarations
		case seamSignatures
		case publicMockPlans
		case view
	}

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

	/// The module's declarations as its dependents' views hold them.
	var ownEntry: ViewedModule {
		ViewedModule(
			moduleName: moduleName,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables.map { $0.withoutPositions() },
			plainTypeDeclarations: plainTypeDeclarations.map { $0.withoutPositions() },
			seamSignatures: seamSignatures,
			publicMockPlans: publicMockPlans,
		)
	}

	/// This file without the seam signatures and public mock plans it and its view carry, which leaves each module that
	/// reads it to compute them from the declarations, as a run under the SwiftPM plugin's target graph does: the graph fuzzer compares the two.
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
			seamSignatures: .empty,
			view: ModuleInfoView(
				moduleGraph: view.moduleGraph,
				declarations: view.declarations.map { ViewedModule(moduleName: $0.moduleName, imports: $0.imports, mockImports: $0.mockImports, instantiables: $0.instantiables, plainTypeDeclarations: $0.plainTypeDeclarations, seamSignatures: .empty, publicMockPlans: .empty) },
				references: view.references,
			),
			locationCountsByFilePath: locationCountsByFilePath,
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
	/// signatures and public mock plans. Each signature, and each plan alike, follows from the declarations of the module and of the modules its run read, the
	/// signatures of the seams it reaches, and the module graph (each module's dependencies, package and mock condition,
	/// which the access proofs read). A view that refers to this module refers to those modules as well, and carries the
	/// module graph as a copy, so a change that changes a signature changes some reference's checksum or the graph; and a
	/// file whose signatures are taken out (`ModuleInfoFile.withoutSeamSignatures`) keeps its references. A view that
	/// referred to the module graph instead would need this checksum to cover it.
	var checksum: UInt64 {
		MergedModuleInfoView.encoded(withoutSeamSignatures).withUnsafeBytes(BinaryFile.checksum(of:))
	}

	/// This entry with no seam signatures and no public mock plans.
	var withoutSeamSignatures: ViewedModule {
		ViewedModule(moduleName: moduleName, imports: imports, mockImports: mockImports, instantiables: instantiables, plainTypeDeclarations: plainTypeDeclarations, seamSignatures: .empty, publicMockPlans: .empty)
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
	let seamSignatures: ModuleSeamSignatures
	/// See `ModuleInfoFile.publicMockPlans`.
	let publicMockPlans: ModulePublicMockPlans

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

	/// This module as a module info file: the one way a run writes one, in every integration. Each location of the
	/// module's own declarations is written as its file and its rank among the distinct locations the module records in
	/// that file (`Dependency.DeclarationLocation.order`), which orders the locations as their lines and columns do, and
	/// each range without its lines and columns, so a line moved in a module leaves every byte of its file, and so of every
	/// file above it, unchanged. A diagnostic about another module's declaration then prints its file without a line.
	///
	/// The seam signatures and public mock plans a run computes carry the positions of the declarations they name, which
	/// the file writes as absent (``BinaryWriter/writingPositionsAsAbsent(_:)``). Copying every signature without them
	/// instead allocated several times the file's size at the run's end, on pages the run had not used yet, which raised its
	/// peak resident memory by a third on a module of two hundred seams although its peak heap held.
	public var moduleInfoData: Data {
		get throws(BinaryFileWriteError) {
			// Every location the file writes is one of the module's own declarations: a view holds none, and the signatures
			// and plans are written without them.
			let locationRanks = LocationRanks(ranking: BinaryWriter.collectingLocations { writer in
				writeFieldsBeforeSeamSignatures(to: &writer)
			})
			return try BinaryFile.data(.moduleInfo) { writer in
				writer.locationRanks = locationRanks
				write(to: &writer) { writer in
					writer.writingPositionsAsAbsent { writer in
						writer.write(seamSignatures)
						writer.write(publicMockPlans)
					}
				}
			}
		}
	}

	/// The module info file `data` holds.
	/// - Parameter readingView: Whether to read the file's view, which `false` leaves empty: a file's view grows with the
	///   modules beneath the file's module.
	/// - Throws: When `data` is not a module info file.
	static func reading(moduleInfoData data: Data, readingView: Bool) throws(BinaryFileReadError) -> ModuleInfoFile {
		try BinaryFile.value(.moduleInfo, from: data) { (reader: inout BinaryReader) throws(BinaryDecodingError) in
			guard readingView else {
				return try ModuleInfoFile(readingAllButViewFrom: &reader)
			}
			let file = try ModuleInfoFile(readingFrom: &reader)
			try reader.finish()
			return file
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
	///   - references: The entries the references of the files' views resolve to.
	/// - Throws: `ModuleInfoDisagreementError` when two files describe one module differently.
	init(directModules: [(file: ModuleInfoFile, path: String)], ownModuleDeclaresSeamOrPublicMock: Bool, viewsReferToModules: Bool = false, references: ResolvedModuleReferences) throws(ModuleInfoDisagreementError) {
		// Two entries of one module are compared by the bytes they are written as, which are computed only once a module's
		// name repeats, and then once for the entry kept: most modules are named once.
		var identities = [String: (identity: ViewedModuleIdentity, path: String)]()
		var identityBytes = [String: [UInt8]]()
		var declarations = [String: (entry: ViewedModule, path: String, checksum: UInt64?)]()
		var writtenDeclarationNames = Set<String>()
		func merge(_ identity: ViewedModuleIdentity, from path: String) throws(ModuleInfoDisagreementError) {
			if let existing = identities[identity.moduleName] {
				let existingBytes = identityBytes[identity.moduleName] ?? Self.encoded(existing.identity)
				identityBytes[identity.moduleName] = existingBytes
				guard existingBytes == Self.encoded(identity) else {
					throw ModuleInfoDisagreementError(moduleName: identity.moduleName, filePaths: [existing.path, path])
				}
			} else {
				identities[identity.moduleName] = (identity, path)
			}
		}
		// Two entries of one module are compared by their checksums (`ViewedModule.checksum`), of the bytes they are
		// written as without their seam signatures, which follow from what the comparison covers: a signature is the bulk
		// of an entry, as large as its seam's tree has paths, and a module above a chain of seams reads each module's entry
		// from every file beneath it. A reference and a file's own entry carry their checksum, so under views that refer
		// to modules no entry is encoded; a copy's is computed only once its module's name repeats, and then once for
		// the entry kept.
		func merge(_ viewed: ViewedModuleEntry, from path: String) throws(ModuleInfoDisagreementError) {
			let moduleName = viewed.entry.moduleName
			if let existing = declarations[moduleName] {
				let existingChecksum = existing.checksum ?? existing.entry.checksum
				declarations[moduleName]?.checksum = existingChecksum
				guard existingChecksum == viewed.checksum ?? viewed.entry.checksum else {
					throw ModuleInfoDisagreementError(moduleName: moduleName, filePaths: [existing.path, path])
				}
			} else {
				declarations[moduleName] = (viewed.entry, path, viewed.checksum)
			}
		}
		// A file's own module first, so a module given both directly and in a view is read from its own file.
		for (file, path) in directModules {
			try merge(file.ownIdentity, from: path)
			try merge(ViewedModuleEntry(entry: file.ownEntry, checksum: file.ownEntryChecksum), from: path)
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
			for viewed in references.entries(of: file.view) {
				try merge(viewed, from: path)
				writtenDeclarationNames.insert(viewed.entry.moduleName)
			}
		}
		// A module's file and every view carry the same signatures of its seams, without positions.
		let directModuleNames = Set(directModules.map(\.file.moduleName))
		// Each module's signatures stay as read, undecoded, until a run reaches one of the module's seams.
		storedSeamSignaturesByModuleName = declarations
			.filter { !$0.value.entry.seamSignatures.isEmpty }
			.mapValues(\.entry.seamSignatures)
		// Each module's public mock plans alike, until a run's mocks call one of the module's public mocks.
		storedPublicMockPlansByModuleName = declarations
			.filter { !$0.value.entry.publicMockPlans.isEmpty }
			.mapValues(\.entry.publicMockPlans)
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
					declarations[name].map { ViewedModuleReference(moduleName: name, checksum: $0.checksum ?? $0.entry.checksum) }
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
	/// The signatures of the seams of each module the files carry the declarations of, by module name: the file's own for a
	/// module whose file the run was given.
	let storedSeamSignaturesByModuleName: [String: ModuleSeamSignatures]
	/// The plans each module's own run computed of the public mocks it declares, by module name, for the modules that
	/// declare one: read from the module's own file or from a view's copy of its entry.
	let storedPublicMockPlansByModuleName: [String: ModulePublicMockPlans]
	/// The view the run's own module info file carries.
	let view: ModuleInfoView

	/// The declarations the views carry of modules whose files the run was not given, sorted by module name.
	var viewOnlyDeclarations: [ViewedModule] {
		declarationsByModuleName.values
			.filter { !directModuleNames.contains($0.moduleName) }
			.sorted { Array($0.moduleName.utf8).lexicographicallyPrecedes(Array($1.moduleName.utf8)) }
	}

	/// The bytes `value` is written as, with each string where it is written, which two entries for one module must
	/// share: `==` ignores `any` at every depth and the order inside an `UnorderedEquatingCollection`, which the bytes
	/// do not.
	static func encoded(_ value: some BinaryCodable) -> [UInt8] {
		var writer = BinaryWriter.writingStringsInline()
		writer.write(value)
		return writer.bytes
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

/// The blocks a module info file stores as encodings of their own, which a run decodes only when it needs one, and
/// which threw when a run decoded them. A run that throws after reading a stored block runs again computing everything
/// (`Generate.generate(buildLog:)`), so a block that never decodes changes no output: only this tells a test that the
/// run read nothing it stored. Handed to `failureObserver`, which the tests set, never the tool.
public enum StoredBlockDecodeObservation {
	/// A kind of stored block.
	public enum Block: Hashable, Sendable {
		/// A module's seam signatures (`ModuleSeamSignatures`).
		case seamSignatures
		/// A module's public mock plans (`ModulePublicMockPlans`).
		case publicMockPlans
	}

	/// Called once for each stored block whose decoding threw, when set: by the tests, never by the tool.
	@TaskLocal public static var failureObserver: TaskLocalFunction<@Sendable (Block) -> Void>?

	/// Returns what `read` decodes of a stored `block`, and tells `failureObserver` when it throws.
	static func reading<Value>(_ block: Block, _ read: () throws(BinaryDecodingError) -> Value) throws(BinaryDecodingError) -> Value {
		do {
			return try read()
		} catch {
			failureObserver?(block)
			throw error
		}
	}
}

extension ModuleInfoFile {
	/// A stored block of a file, with the bytes the tool writes of what the block decodes to.
	public struct StoredBlockEncoding: Sendable {
		public let block: StoredBlockDecodeObservation.Block
		/// The encoding the file holds.
		public let held: [UInt8]
		/// The encoding of the values `held` decodes to.
		public let ofDecodedValues: [UInt8]
	}

	/// The signatures this file holds of its module's seams, decoded as a run of a module above decodes them. The tests
	/// ask this of every file a run writes, to compare each seam's place graph with the graph the run computed; the tool
	/// never does.
	public var seamSignaturesReadBack: [StoredSeamSignature] {
		get throws {
			try seamSignatures.decoded
		}
	}

	/// The plans this file holds of its module's public mocks, decoded as a run of a module whose mocks call one decodes
	/// them. The tests ask this of every file a run writes, as they ask `seamSignaturesReadBack`; the tool never does.
	public var publicMockPlansReadBack: [StoredPublicMockPlan] {
		get throws {
			try publicMockPlans.decoded
		}
	}

	/// Each stored block of this file's own module, decoded and encoded again: the two encodings of a block are the same
	/// bytes for a file SafeDITool wrote, since one layout writes and reads a block. The tests ask this of every file a
	/// run writes, with real signatures and plans; the tool never does.
	public var storedBlockEncodings: [StoredBlockEncoding] {
		get throws {
			try [
				StoredBlockEncoding(
					block: .seamSignatures,
					held: seamSignatures.encoding(writingPositionsAsAbsent: true),
					ofDecodedValues: ModuleSeamSignatures(seamSignatures.decoded).encoding(writingPositionsAsAbsent: true),
				),
				StoredBlockEncoding(
					block: .publicMockPlans,
					held: publicMockPlans.encoding(writingPositionsAsAbsent: true),
					ofDecodedValues: ModulePublicMockPlans(publicMockPlans.decoded, compilesGeneratedMocks: publicMockPlans.compilesGeneratedMocks).encoding(writingPositionsAsAbsent: true),
				),
			]
		}
	}
}

/// The signatures a module info file holds of its module's seams (`ModuleInfoFile.seamSignatures`): the seams, read with
/// the file, and their signatures, which the file holds as an encoding of their own (``BinaryWriter/writeEncoding(_:)``)
/// that a run decodes only when it reaches one of the module's seams. A module's file and every view that copies its
/// declarations carry its signatures, and the module that reads them calls the seams of few of the modules it reads.
struct ModuleSeamSignatures: Sendable {
	init(_ signatures: [StoredSeamSignature]) {
		seamTypes = signatures.map(\.seamType)
		storage = .decoded(signatures)
	}

	init(seamTypes: [TypeDescription], encoding: [UInt8]) {
		self.seamTypes = seamTypes
		storage = .encoded(encoding)
	}

	static let empty = ModuleSeamSignatures([])

	/// The seam of each signature, in the order of the signatures.
	let seamTypes: [TypeDescription]

	var isEmpty: Bool {
		seamTypes.isEmpty
	}

	/// The signatures, decoded each time this is read from a file's encoding.
	var decoded: [StoredSeamSignature] {
		get throws(BinaryDecodingError) {
			switch storage {
			case let .decoded(signatures):
				signatures
			case let .encoded(encoding):
				try Self.signatures(decodingFrom: encoding)
			}
		}
	}

	/// The signatures as a run that reaches one of the module's seams reads them. The file's body checksum covers the
	/// encoding, so only a SafeDITool that wrote a malformed one makes the read throw, never trap; a run that throws after
	/// reading a stored signature runs again computing every signature (`Generate.generate(buildLog:)`).
	var stored: StoredSeamSignatures {
		StoredSeamSignatures { try StoredBlockDecodeObservation.reading(.seamSignatures) { () throws(BinaryDecodingError) in try decoded } }
	}

	/// The encoding the file holds: the bytes read, written back unchanged, or the signatures encoded each type
	/// description and repeated field once (``BinaryWriter/writeSharingSignatureValues(_:)``), their positions absent when
	/// `writesPositionsAsAbsent`. Only a run's own signatures hold positions: a file is written with them absent.
	func encoding(writingPositionsAsAbsent writesPositionsAsAbsent: Bool) -> [UInt8] {
		switch storage {
		case let .decoded(signatures):
			var writer = BinaryWriter()
			if writesPositionsAsAbsent {
				writer.writingPositionsAsAbsent { writer in
					writer.writeSharingSignatureValues { $0.write(signatures) }
				}
			} else {
				writer.writeSharingSignatureValues { $0.write(signatures) }
			}
			return writer.encoded
		case let .encoded(encoding):
			return encoding
		}
	}

	// MARK: Private

	private enum Storage: Sendable {
		case decoded([StoredSeamSignature])
		case encoded([UInt8])
	}

	private let storage: Storage

	private static func signatures(decodingFrom encoding: [UInt8]) throws(BinaryDecodingError) -> [StoredSeamSignature] {
		// `withUnsafeBytes` rethrows untyped, so the read is carried out of it as a result.
		try encoding.withUnsafeBytes { bytes in
			Result { () throws(BinaryDecodingError) in
				var reader = try BinaryReader(bytes: bytes)
				let signatures = try reader.readSharingSignatureValues { reader throws(BinaryDecodingError) in
					try reader.read() as [StoredSeamSignature]
				}
				try reader.finish()
				return signatures
			}
		}.get()
	}
}

/// The plans a module info file holds of its module's public mocks (`ModuleInfoFile.publicMockPlans`): the mocked types
/// and whether the module's run compiled the mocks it generated, read with the file, and the plans, which the file holds
/// as an encoding of their own (``BinaryWriter/writeEncoding(_:)``) that a run decodes only when one of its mocks calls
/// one of the module's public mocks, as it decodes a module's seam signatures (`ModuleSeamSignatures`).
struct ModulePublicMockPlans: Sendable {
	/// - Parameter compilesGeneratedMocks: Whether the run that computed `plans` compiles the mocks it generates
	///   (`ConditionalCompilationEvaluator.compilesGeneratedMocks`), which a plan depends on. A module with no plan
	///   records `false`, so that its file's bytes do not depend on the build's conditions.
	///
	/// A plan that names a type nested more deeply than a ``BinaryReader`` reads is left out, so that a module calling
	/// the mock computes it and the file stays one every run reads: a parameter that takes a type nested as deeply as a
	/// declaration may as `T? = nil` nests one level deeper. Each plan is checked alone only when the plans together
	/// nest too deeply.
	init(_ plans: [StoredPublicMockPlan], compilesGeneratedMocks: Bool) {
		var readablePlans = plans
		var encoded = Self.encoding(of: plans, writingPositionsAsAbsent: true)
		if encoded.nestsTooDeeply {
			readablePlans = plans.filter { !Self.encoding(of: [$0], writingPositionsAsAbsent: true).nestsTooDeeply }
			encoded = Self.encoding(of: readablePlans, writingPositionsAsAbsent: true)
		}
		mockedTypes = readablePlans.map(\.mockedType)
		self.compilesGeneratedMocks = compilesGeneratedMocks && !readablePlans.isEmpty
		storage = .decoded(readablePlans, encodingWithoutPositions: encoded.bytes)
	}

	init(mockedTypes: [TypeDescription], compilesGeneratedMocks: Bool, encoding: [UInt8]) {
		self.mockedTypes = mockedTypes
		self.compilesGeneratedMocks = compilesGeneratedMocks
		storage = .encoded(encoding)
	}

	static let empty = ModulePublicMockPlans([], compilesGeneratedMocks: false)

	/// The mocked type of each plan, in the order of the plans.
	let mockedTypes: [TypeDescription]
	/// Whether the run that computed the plans compiles the mocks it generates. A run that differs in this computes the
	/// plans itself.
	let compilesGeneratedMocks: Bool

	var isEmpty: Bool {
		mockedTypes.isEmpty
	}

	/// The plans, decoded each time this is read from a file's encoding.
	var decoded: [StoredPublicMockPlan] {
		get throws(BinaryDecodingError) {
			switch storage {
			case let .decoded(plans, _):
				plans
			case let .encoded(encoding):
				try Self.plans(decodingFrom: encoding)
			}
		}
	}

	/// The plans as a run whose mocks call one of the module's public mocks reads them. The file's body checksum covers
	/// the encoding, so only a SafeDITool that wrote a malformed one makes the read throw, never trap; a run that throws
	/// after it was handed a stored plan runs again computing every plan (`Generate.generate(buildLog:)`).
	var stored: StoredPublicMockPlans {
		StoredPublicMockPlans(compilesGeneratedMocks: compilesGeneratedMocks) { try StoredBlockDecodeObservation.reading(.publicMockPlans) { () throws(BinaryDecodingError) in try decoded } }
	}

	/// The encoding the file holds: the bytes read, written back unchanged, or the plans encoded each type description
	/// and repeated field once (``BinaryWriter/writeSharingSignatureValues(_:)``), their positions absent when
	/// `writesPositionsAsAbsent`. Only a run's own plans hold positions: a file is written with them absent.
	func encoding(writingPositionsAsAbsent writesPositionsAsAbsent: Bool) -> [UInt8] {
		switch storage {
		case let .decoded(plans, encodingWithoutPositions):
			writesPositionsAsAbsent ? encodingWithoutPositions : Self.encoding(of: plans, writingPositionsAsAbsent: false).bytes
		case let .encoded(encoding):
			encoding
		}
	}

	// MARK: Private

	private enum Storage: Sendable {
		/// The plans a run computed, with the encoding a file holds of them, made once.
		case decoded([StoredPublicMockPlan], encodingWithoutPositions: [UInt8])
		case encoded([UInt8])
	}

	private let storage: Storage

	/// The encoding of `plans`, each type description and repeated field written once
	/// (``BinaryWriter/writeSharingSignatureValues(_:)``), and whether it holds a value nested more deeply than a
	/// ``BinaryReader`` reads.
	private static func encoding(of plans: [StoredPublicMockPlan], writingPositionsAsAbsent writesPositionsAsAbsent: Bool) -> (bytes: [UInt8], nestsTooDeeply: Bool) {
		var writer = BinaryWriter()
		if writesPositionsAsAbsent {
			writer.writingPositionsAsAbsent { writer in
				writer.writeSharingSignatureValues { $0.write(plans) }
			}
		} else {
			writer.writeSharingSignatureValues { $0.write(plans) }
		}
		return (writer.encoded, writer.isNestedTooDeeply)
	}

	private static func plans(decodingFrom encoding: [UInt8]) throws(BinaryDecodingError) -> [StoredPublicMockPlan] {
		// `withUnsafeBytes` rethrows untyped, so the read is carried out of it as a result.
		try encoding.withUnsafeBytes { bytes in
			Result { () throws(BinaryDecodingError) in
				var reader = try BinaryReader(bytes: bytes)
				let plans = try reader.readSharingSignatureValues { reader throws(BinaryDecodingError) in
					try reader.read() as [StoredPublicMockPlan]
				}
				try reader.finish()
				return plans
			}
		}.get()
	}
}

extension ModulePublicMockPlans: Codable {
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		try self.init(container.decode([StoredPublicMockPlan].self, forKey: .plans), compilesGeneratedMocks: container.decode(Bool.self, forKey: .compilesGeneratedMocks))
	}

	/// Encodes the plans, as `SafeDITool dump` prints them.
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(compilesGeneratedMocks, forKey: .compilesGeneratedMocks)
		try container.encode(decoded, forKey: .plans)
	}

	private enum CodingKeys: String, CodingKey {
		case compilesGeneratedMocks
		case plans
	}
}

extension ModuleSeamSignatures: Codable {
	init(from decoder: any Decoder) throws {
		try self.init(decoder.singleValueContainer().decode([StoredSeamSignature].self))
	}

	/// Encodes the signatures, as `SafeDITool dump` prints them.
	func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(decoded)
	}
}
