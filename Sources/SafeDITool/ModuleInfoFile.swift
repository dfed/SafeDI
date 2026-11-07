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
/// A module is given the `.safedi` of each module it imports and no other, under every integration that runs
/// `generate` once per module. A seam or public mock another module declares is called with the signature that
/// module's run computed, from the declarations it read, so each file carries in its `view` what a module that
/// depends on it needs to compute any such signature in its closure: the name, package, dependencies and mock
/// condition of every module in the closure, and the declarations – without positions – of each module in it that
/// declares a seam or a public mock and of the modules those depend on directly.
struct ModuleInfoFile: Codable {
	init(
		moduleName: String,
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
		view: ModuleInfoView,
	) {
		self.moduleName = moduleName
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
		self.view = view
	}

	/// The file of `module`, named `moduleName`, which a run that writes a module info file always knows.
	init(module: ModuleInfo, moduleName: String, view: ModuleInfoView) {
		self.init(
			moduleName: moduleName,
			packageName: module.packageName,
			dependencyModuleNames: module.dependencyModuleNames,
			imports: module.imports,
			mockImports: module.mockImports,
			instantiables: module.instantiables,
			configurations: module.configurations,
			filesWithUnexpectedNodes: module.filesWithUnexpectedNodes,
			conditionalCompilationDecisions: module.conditionalCompilationDecisions,
			instantiableTypeNamesInAnyClause: module.instantiableTypeNamesInAnyClause,
			plainTypeDeclarations: module.plainTypeDeclarations,
			view: view,
		)
	}

	/// The module the file describes.
	let moduleName: String
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
	/// What the module's dependents need of the modules it depends on, directly or not.
	let view: ModuleInfoView

	/// The module's own declarations.
	var module: ModuleInfo {
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
struct ModuleInfoView: Codable {
	/// The modules of the closure, without their declarations: names only, so this changes when a module is added,
	/// renamed or depends on others, never on an edit.
	let moduleGraph: [ViewedModuleIdentity]
	/// The declarations of each module in the closure that declares a seam or a public mock, and of each module such a
	/// module depends on directly, each once.
	let declarations: [ViewedModule]

	/// The view of a module that depends on nothing.
	static let empty = ModuleInfoView(moduleGraph: [], declarations: [])
}

/// A module in a view's module graph.
struct ViewedModuleIdentity: Codable {
	let moduleName: String
	let packageName: String?
	/// The modules the module depends on directly, whose module info its run read.
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
	init(moduleInfoData data: Data) throws(BinaryFileReadError) {
		self = try BinaryFile.value(.moduleInfo, from: data)
	}

	/// This module as a module info file.
	var moduleInfoData: Data {
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
	init(directModules: [(file: ModuleInfoFile, path: String)], ownModuleDeclaresSeamOrPublicMock: Bool) throws(ModuleInfoDisagreementError) {
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
		identitiesByModuleName = identities.mapValues(\.identity)
		declarationsByModuleName = declarations.mapValues(\.entry)
		directModuleNames = Set(directModules.map(\.file.moduleName))
		view = ModuleInfoView(
			moduleGraph: identities.values.map(\.identity).sorted { Array($0.moduleName.utf8).lexicographicallyPrecedes(Array($1.moduleName.utf8)) },
			declarations: writtenDeclarationNames
				.compactMap { declarations[$0]?.entry }
				.sorted { Array($0.moduleName.utf8).lexicographicallyPrecedes(Array($1.moduleName.utf8)) },
		)
	}

	/// Every module the files name or carry, by name.
	let identitiesByModuleName: [String: ViewedModuleIdentity]
	/// The declarations of each module the files carry, by name: every given file's own module, and each module a view
	/// carries the declarations of.
	let declarationsByModuleName: [String: ViewedModule]
	/// The modules whose files the run was given.
	let directModuleNames: Set<String>
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
	private static func encoded(_ value: some BinaryCodable) -> [UInt8] {
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
