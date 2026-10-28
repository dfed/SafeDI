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

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif
import Foundation
import SafeDICore
import SwiftParser
import SwiftSyntax

/// What a module's files declare. Every list is ordered by what the files declare, never by the order in
/// which parallel parsing finished the files or by how `generate` assembled the module, so the module info
/// `generate` writes for the same files is the same bytes every time.
struct ModuleInfo: Codable {
	/// A module with `imports`, `mockImports`, `filesWithUnexpectedNodes`, and `conditionalCompilationDecisions`
	/// sorted, whatever order they are given in, and all but `filesWithUnexpectedNodes` without duplicates.
	init(
		imports: [ImportStatement],
		mockImports: [ImportStatement],
		instantiables: [Instantiable],
		configurations: [SafeDIConfiguration],
		filesWithUnexpectedNodes: [String]?,
		conditionalCompilationDecisions: [ConditionalCompilationDecision],
		nestedTypeDeclarations: NestedTypeDeclarations,
	) {
		self.nestedTypeDeclarations = nestedTypeDeclarations
		self.imports = imports.sortedWithoutDuplicates()
		self.mockImports = mockImports.sortedWithoutDuplicates()
		self.instantiables = instantiables
		self.configurations = configurations
		self.filesWithUnexpectedNodes = filesWithUnexpectedNodes?.sorted()
		self.conditionalCompilationDecisions = Set(conditionalCompilationDecisions).sorted()
	}

	/// The imports generated dependency-tree code needs, from every file that declares SafeDI content,
	/// sorted and without duplicates.
	let imports: [ImportStatement]
	/// The imports generated mock code needs, found by evaluating each `#if` block that guards only imports
	/// as if the module's mock condition were active, sorted and without duplicates. A module that depends on
	/// this one generates mocks that reference this module's mock-only declarations, so it imports these into
	/// its own mocks.
	let mockImports: [ImportStatement]
	/// Ordered by file path and, within each file, by declaration order. Those found in files reached through
	/// `#SafeDIConfiguration(additionalDirectoriesToInclude:)` follow those of the module's own files.
	let instantiables: [Instantiable]
	/// Ordered by file path and, within each file, by declaration order.
	let configurations: [SafeDIConfiguration]
	/// The files with syntax errors, sorted.
	let filesWithUnexpectedNodes: [String]?
	/// How each `#if` condition guarding SafeDI declarations was evaluated, sorted and without duplicates.
	/// Generated code asserts these at compile time.
	let conditionalCompilationDecisions: [ConditionalCompilationDecision]
	/// The nested types the module's files declare. A module that depends on this one generates code that spells
	/// this module's dependency types, so it qualifies the nested names among them with these.
	let nestedTypeDeclarations: NestedTypeDeclarations
}

/// A module's parsed input files together with the configuration that governed the parse.
struct ParsedModule {
	let moduleInfo: ModuleInfo
	/// The module's `#SafeDIConfiguration`, found among the configuration file paths it was parsed with.
	let configuration: SafeDIConfiguration?
	/// The evaluator the files were scanned with. Files parsed later for the same module, such as
	/// those in `configuration.additionalDirectoriesToInclude`, must be scanned with it too.
	let conditionalCompilationEvaluator: ConditionalCompilationEvaluator
	/// The input files, named as `moduleInfo` names them, that belong to the modules this module depends on, which a
	/// build tool plugin hands `SafeDITool` together with the module's own. Empty when every input is the module's.
	let dependencyFilePaths: Set<String>
}

/// More than one `#SafeDIConfiguration` was declared among a module's own files.
/// More than one `#SafeDIConfiguration` in a module, reported at each of them.
struct MultipleConfigurationsError: SourceLocatedError {
	let declarationLocations: [Dependency.DeclarationLocation?]

	var sourceDiagnostics: [SourceDiagnostic] {
		declarationLocations
			.map {
				SourceDiagnostic(
					severity: .error,
					location: $0,
					message: "This module declares #\(SafeDIConfigurationVisitor.macroName) \(declarationLocations.count) times, but a module can declare it at most once. Keep one and remove the others.",
				)
			}
			.sorted(by: SourceDiagnostic.precedesInSourceOrder)
	}
}

extension SafeDIConfiguration {
	/// The name of the file SafeDI reads before the rest of a module, so that the configuration it declares
	/// decides how every other file is scanned.
	static let conventionalFileName = "\(SafeDIConfigurationVisitor.macroName).swift"

	/// Whether the file at `filePath` is named `SafeDIConfiguration.swift`.
	static func isInConventionalFile(atPath filePath: String) -> Bool {
		(filePath as NSString).lastPathComponent == conventionalFileName
	}

	/// A warning when this configuration slows scanning down: it changes the mock condition from the
	/// default, so a module that declares it outside `SafeDIConfiguration.swift` is scanned twice.
	var placementWarning: SourceDiagnostic? {
		guard mockConditionalCompilation != "DEBUG",
		      sourceFilePath.map(Self.isInConventionalFile(atPath:)) != true
		else { return nil }
		return SourceDiagnostic(
			severity: .warning,
			location: declarationLocation,
			message: "This #\(SafeDIConfigurationVisitor.macroName) sets `\(SafeDIConfigurationVisitor.mockConditionalCompilationArgumentLabel)` and is not in a file named `\(Self.conventionalFileName)`, so SafeDI had to scan this module’s files twice. Move it to a file named `\(Self.conventionalFileName)` so SafeDI can read it first.",
		)
	}
}

/// The evaluator for a module's `#if` blocks.
///
/// - Parameters:
///   - activeCompilationConditions: The conditions supplied on the command line and through the manifest.
///   - configuration: The module's `#SafeDIConfiguration`, whose `mockConditionalCompilation` guards the
///     generated mock code. A module without a configuration wraps its mocks in `DEBUG`.
func conditionalCompilationEvaluator(
	activeCompilationConditions: Set<String>,
	configuration: SafeDIConfiguration?,
) -> ConditionalCompilationEvaluator {
	ConditionalCompilationEvaluator(
		activeCompilationConditions: activeCompilationConditions,
		mockConditionalCompilation: configuration.map(\.mockConditionalCompilation) ?? "DEBUG",
	)
}

/// The normalized paths of the Swift files in `directories`, each absolute or relative to the working directory.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func findSwiftFiles(inDirectories directories: [String]) async throws -> Set<NormalizedFilePath> {
	try await withThrowingTaskGroup(
		of: [NormalizedFilePath].self,
		returning: Set<NormalizedFilePath>.self,
	) { taskGroup in
		for included in directories {
			taskGroup.addTask {
				let includedURL = included.asFileURL
				let includedFileEnumerator = SafeDITool.fileFinder
					.enumerator(
						at: includedURL,
						includingPropertiesForKeys: nil,
						options: [.skipsHiddenFiles],
						errorHandler: nil,
					)
				guard let files = includedFileEnumerator?.compactMap({ $0 as? URL }) else {
					struct CouldNotEnumerateDirectoryError: Error, CustomStringConvertible {
						let directory: String

						var description: String {
							"Could not list the Swift files in directory '\(directory)'. Check that the directory exists and is readable."
						}
					}
					throw CouldNotEnumerateDirectoryError(directory: included)
				}
				return (files + [includedURL]).compactMap {
					if $0.pathExtension == "swift" {
						NormalizedFilePath($0.path)
					} else {
						nil
					}
				}
			}
		}

		var swiftFiles = Set<NormalizedFilePath>()
		for try await includedFiles in taskGroup {
			swiftFiles.formUnion(includedFiles)
		}

		return swiftFiles
	}
}

/// Parses a module's input files, parsing each file once when the module's configuration is in
/// `SafeDIConfiguration.swift`.
///
/// The module's `#SafeDIConfiguration(mockConditionalCompilation:)` decides how `#if` blocks guarding
/// mock-only declarations are evaluated, and it is the only part of the module's evaluator not known up
/// front. The module's own files named `SafeDIConfiguration.swift` are therefore parsed first, found by
/// path alone, and the configuration they declare decides the evaluator every other file is walked with.
/// A configuration is production content, whose `#if` blocks are evaluated with the supplied conditions
/// alone, so finding it never depends on the mock condition.
///
/// A module whose configuration is in another file is walked assuming the default mock condition, which
/// also finds the configuration. Most modules keep the default, and that walk is final. When the
/// configuration names another mock condition, every file that declared SafeDI content is read, parsed,
/// and walked again. Every syntax tree but those of `SafeDIConfiguration.swift` files is released as soon
/// as it is walked, so memory scales with concurrency rather than module size.
///
/// The file scans it returns record every nested type the files that mention SafeDI declare, and the module's
/// files that mention no SafeDI declaration are only read: `ParsedModuleFiles.resolvingNestedTypeDeclarations(additionalFileScans:)` keeps the
/// nested types that lookups reach once every instantiable of the module is known, and parses only those other
/// files whose text can declare one of them.
///
/// - Parameters:
///   - filePaths: Every file to parse.
///   - configurationFilePaths: The files that belong to the module itself, which are the only ones whose
///     `#SafeDIConfiguration` applies. In a multi-module input set these are the current target's files.
///   - activeCompilationConditions: The conditions supplied on the command line and through the manifest.
/// - Returns: The module's files.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseModule(
	filePaths: Set<String>,
	configurationFilePaths: Set<String>,
	activeCompilationConditions: Set<String>,
) async throws -> ParsedModuleFiles {
	let defaultEvaluator = ConditionalCompilationEvaluator(activeCompilationConditions: activeCompilationConditions)

	let conventionalConfigurationFilePaths = filePaths.filter { filePath in
		configurationFilePaths.contains(filePath) && SafeDIConfiguration.isInConventionalFile(atPath: filePath)
	}
	var typeNamesByFileWithoutSafeDIContent = [String: DeclaredTypeNames]()
	let conventionalConfigurationFiles = try conventionalConfigurationFilePaths.sorted().compactMap { filePath -> (path: String, syntaxTree: SourceFileSyntax)? in
		switch try readFile(atPath: filePath) {
		case let .declaringSafeDIContent(syntaxTree):
			return (path: filePath, syntaxTree: syntaxTree)
		case let .declaringNoSafeDIContent(typeNames):
			typeNamesByFileWithoutSafeDIContent[filePath] = typeNames
			return nil
		}
	}
	let conventionalConfigurationFileScans = conventionalConfigurationFiles.map { file in
		walk(file.syntaxTree, at: file.path, conditionalCompilation: defaultEvaluator)
	}
	let conventionalConfigurations = conventionalConfigurationFileScans.flatMap(\.configurations)
	// More than one configuration is rejected below, once every file has been walked, so the error lists
	// them all. Until then such a module is walked as if its configuration were elsewhere.
	let firstPassEvaluator = conditionalCompilationEvaluator(
		activeCompilationConditions: activeCompilationConditions,
		configuration: conventionalConfigurations.count == 1 ? conventionalConfigurations.first : nil,
	)
	let walkedFiles = try await walkFiles(named: filePaths.subtracting(conventionalConfigurationFilePaths), conditionalCompilation: firstPassEvaluator)
	typeNamesByFileWithoutSafeDIContent.merge(walkedFiles.typeNamesByFileWithoutSafeDIContent) { first, _ in first }
	let fileScans = (firstPassEvaluator == defaultEvaluator
		? conventionalConfigurationFileScans
		: conventionalConfigurationFiles.map { file in
			walk(file.syntaxTree, at: file.path, conditionalCompilation: firstPassEvaluator)
		})
		+ walkedFiles.fileScans

	let configurations = fileScans
		.filter { configurationFilePaths.contains($0.path) }
		.flatMap(\.configurations)
	guard configurations.count <= 1 else {
		throw MultipleConfigurationsError(declarationLocations: configurations.map(\.declarationLocation))
	}
	let configuration = configurations.first
	let evaluator = conditionalCompilationEvaluator(
		activeCompilationConditions: activeCompilationConditions,
		configuration: configuration,
	)

	return try await ParsedModuleFiles(
		fileScans: evaluator == firstPassEvaluator
			? fileScans
			// Only a configuration outside `SafeDIConfiguration.swift` that changes the mock condition gets here.
			: walkFiles(named: Set(fileScans.map(\.path)), conditionalCompilation: evaluator).fileScans,
		typeNamesByFileWithoutSafeDIContent: typeNamesByFileWithoutSafeDIContent,
		configuration: configuration,
		conditionalCompilationEvaluator: evaluator,
	)
}

/// A module's parsed input files, before the nested type declarations SafeDI keeps are known.
struct ParsedModuleFiles {
	/// What each file that mentions SafeDI contributes, recording every nested type it declares.
	let fileScans: [FileScan]
	/// The type names in the text of each file that mentions no SafeDI declaration.
	let typeNamesByFileWithoutSafeDIContent: [String: DeclaredTypeNames]
	/// The module's `#SafeDIConfiguration`, found among the configuration file paths it was parsed with.
	let configuration: SafeDIConfiguration?
	/// The evaluator the files were scanned with.
	let conditionalCompilationEvaluator: ConditionalCompilationEvaluator

	/// The module's file scans, and those of the files reached through `additionalDirectoriesToInclude`, keeping the
	/// declarations that the lookups of their instantiables read, with what each file that mentions no SafeDI
	/// declaration but declares such a declaration contributes added to the module's file scans.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func resolvingNestedTypeDeclarations(
		additionalFileScans: [CachedFileScan],
	) async throws -> (fileScans: [FileScan], additionalFileScans: [CachedFileScan]) {
		let knownFileScans = fileScans + additionalFileScans.map(\.fileScan)
		let (lookups, discoveredFileScans) = try await discoverNestedTypeDeclarations(
			lookedUpBy: knownFileScans.flatMap(\.instantiables),
			knownDeclarations: knownFileScans.reduce(into: NestedTypeDeclarations()) { $0.formUnion($1.nestedTypeDeclarations) },
			amongFilesWithTypeNames: typeNamesByFileWithoutSafeDIContent,
			conditionalCompilation: conditionalCompilationEvaluator,
		)
		return (
			fileScans.map { $0.resolvingNestedTypeDeclarations(for: lookups) }
				+ discoveredFileScans
				.map { $0.resolvingNestedTypeDeclarations(for: lookups) }
				// A file that declares nothing lookups read, under any conditions, contributes nothing.
				.filter { !$0.nestedTypeDeclarations.isEmpty },
			additionalFileScans.map { $0.resolvingNestedTypeDeclarations(for: lookups) },
		)
	}
}

/// The lookups `instantiables` make, and the scans of the files among `candidateFiles` that can declare what those
/// lookups read, parsed and walked.
///
/// A file declares something at a path a lookup reads, such as `Feature.Settings.Configuration`, only when its text
/// names that path's outermost type, `Feature`, right after a declaration keyword or `extension`, and names its last
/// name, `Configuration`, right after a declaration keyword, among the generic parameters after a declared name, or
/// in the path after `extension`. Only such files are parsed. The declarations they hold can make lookups follow
/// more inheritance clauses, so files are parsed until no more can matter. Neither test depends on a condition.
/// - Parameters:
///   - knownDeclarations: The declarations of the files already walked.
///   - candidateFiles: The type names in the text of each file that may hold more declarations.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func discoverNestedTypeDeclarations(
	lookedUpBy instantiables: [Instantiable],
	knownDeclarations: NestedTypeDeclarations,
	amongFilesWithTypeNames candidateFiles: [String: DeclaredTypeNames],
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> (lookups: NestedTypeLookups, fileScans: [FileScan]) {
	var declarations = knownDeclarations
	var lookups = NestedTypeLookups(instantiables: instantiables, declarations: declarations)
	var unparsedFiles = candidateFiles
	var discoveredFileScans = [FileScan]()
	while case let filePaths = Set(unparsedFiles.keys.filter { unparsedFiles[$0]?.canDeclare(lookedUpBy: lookups) == true }), !filePaths.isEmpty {
		for filePath in filePaths {
			unparsedFiles[filePath] = nil
		}
		let fileScans = try await walkNestedTypeDeclarations(inFilesAt: filePaths, conditionalCompilation: evaluator)
		discoveredFileScans += fileScans
		for fileScan in fileScans {
			declarations.formUnion(fileScan.nestedTypeDeclarations)
		}
		lookups = NestedTypeLookups(instantiables: instantiables, declarations: declarations)
	}
	return (lookups, discoveredFileScans)
}

/// Parses files that belong to an already-configured module, such as those reached through
/// `#SafeDIConfiguration(additionalDirectoriesToInclude:)`, with the module's evaluator.
/// - Returns: What each file that mentions SafeDI contributes to the module, recording every nested type it declares.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFiles(
	_ filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await walkFiles(named: filePaths, conditionalCompilation: evaluator).fileScans
}

/// The type names in the text of each file at `filePaths`.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func readTypeNames(inFilesAt filePaths: Set<String>) async throws -> [String: DeclaredTypeNames] {
	try await withThrowingTaskGroup(
		of: (String, DeclaredTypeNames).self,
		returning: [String: DeclaredTypeNames].self,
	) { taskGroup in
		for filePath in filePaths {
			taskGroup.addTask {
				var content = try String(contentsOfFile: filePath, encoding: .utf8)
				return (filePath, content.withUTF8(DeclaredTypeNames.init(source:)))
			}
		}
		return try await taskGroup.reduce(into: [:]) { $0[$1.0] = $1.1 }
	}
}

/// Parses files that mention no SafeDI declaration but were parsed for the nested types they declare, as
/// `discoverNestedTypeDeclarations` parses them.
/// - Returns: What each file contributes to the module, recording every nested type it declares.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFilesDeclaringOnlyNestedTypes(
	_ filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await walkNestedTypeDeclarations(inFilesAt: filePaths, conditionalCompilation: evaluator)
}

// MARK: - Private

/// What one file contributed to the module.
struct FileScan: Codable, Sendable {
	let path: String
	let imports: [ImportStatement]
	let mockImports: [ImportStatement]
	let instantiables: [Instantiable]
	let configurations: [SafeDIConfiguration]
	let encounteredUnexpectedNodes: Bool
	let conditionalCompilationDecisions: [ConditionalCompilationDecision]
	/// Every bare condition whose value decided what this file contributed, except the imports and mock
	/// imports `importSegments` can find again. Walking the file with any evaluator that gives each of these
	/// the same value, and has the same mock condition, contributes the same.
	let consultedCompilationConditions: Set<String>
	/// The file's imports, kept only when an `#if` block that guards nothing but imports consults a
	/// condition, so `imports` and `mockImports` can be found again without the file when that condition changes.
	let importSegments: [FileVisitor.ImportSegment]
	/// Every bare condition whose value decided which imports `importSegments` hold, for either list.
	let importOnlyConsultedCompilationConditions: Set<String>
	/// The declarations in every clause of the file's `#if` blocks that decide which files SafeDI generates,
	/// which are the same whatever the conditions.
	let outputFileDeclarations: OutputFileDeclarations
	/// The declarations lookup of type names can read that the file holds: every one when the file has just been
	/// walked, and once its scan is resolved, those the module's lookups read.
	let nestedTypeDeclarations: NestedTypeDeclarations

	/// Whether any compilation condition decided what the file contributed. A file whose scan consults
	/// none contributes the same whatever conditions are supplied.
	var consultsCompilationConditions: Bool {
		!consultedCompilationConditions.isEmpty || !importOnlyConsultedCompilationConditions.isEmpty
	}

	/// Whether the file declares anything SafeDI generates code for. A file whose only SafeDI content
	/// was skipped contributes nothing to generated code, so its imports stay out of the generated code.
	var declaresSafeDIContent: Bool {
		!instantiables.isEmpty || !configurations.isEmpty || encounteredUnexpectedNodes
	}

	/// This scan, keeping the declarations `lookups` read, and consulting the conditions that decided whether they
	/// exist, which decide generated code.
	func resolvingNestedTypeDeclarations(for lookups: NestedTypeLookups) -> FileScan {
		// Most files that mention SafeDI declare nothing lookups read.
		guard !nestedTypeDeclarations.isEmpty else { return self }
		let nestedTypeDeclarations = nestedTypeDeclarations.restricted(to: lookups)
		return FileScan(
			path: path,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			encounteredUnexpectedNodes: encounteredUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			consultedCompilationConditions: consultedCompilationConditions.union(nestedTypeDeclarations.consultedCompilationConditions),
			importSegments: importSegments,
			importOnlyConsultedCompilationConditions: importOnlyConsultedCompilationConditions,
			outputFileDeclarations: outputFileDeclarations,
			nestedTypeDeclarations: nestedTypeDeclarations,
		)
	}

	/// This scan, with the imports and mock imports `evaluator` finds in `importSegments`.
	func withImports(evaluatedWith evaluator: ConditionalCompilationEvaluator) -> FileScan {
		guard declaresSafeDIContent else {
			return replacingImports(with: [], mockImports: [])
		}
		let segmentImports = importSegments.map { $0.imports(evaluatedWith: evaluator) }
		return replacingImports(
			with: segmentImports.flatMap(\.imports),
			mockImports: segmentImports.flatMap(\.mockImports),
		)
	}

	/// This scan, contributing `imports` and `mockImports`.
	fileprivate func replacingImports(with imports: [ImportStatement], mockImports: [ImportStatement]) -> FileScan {
		FileScan(
			path: path,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			encounteredUnexpectedNodes: encounteredUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			consultedCompilationConditions: consultedCompilationConditions,
			importSegments: importSegments,
			importOnlyConsultedCompilationConditions: importOnlyConsultedCompilationConditions,
			outputFileDeclarations: outputFileDeclarations,
			nestedTypeDeclarations: nestedTypeDeclarations,
		)
	}

	/// This scan, with the file and everything declared in it named by `path`.
	func relocated(to path: String) -> FileScan {
		FileScan(
			path: path,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables.map {
				var instantiable = $0
				instantiable.sourceFilePath = path
				return instantiable
			},
			configurations: configurations.map {
				var configuration = $0
				configuration.sourceFilePath = path
				return configuration
			},
			encounteredUnexpectedNodes: encounteredUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			consultedCompilationConditions: consultedCompilationConditions,
			importSegments: importSegments,
			importOnlyConsultedCompilationConditions: importOnlyConsultedCompilationConditions,
			outputFileDeclarations: outputFileDeclarations,
			nestedTypeDeclarations: nestedTypeDeclarations,
		)
	}
}

extension FileVisitor.ImportSegment {
	/// The imports and mock imports this segment holds when evaluated with `evaluator`.
	fileprivate func imports(evaluatedWith evaluator: ConditionalCompilationEvaluator) -> (imports: [ImportStatement], mockImports: [ImportStatement]) {
		switch self {
		case let .imports(importStatements):
			return (importStatements, importStatements)
		case let .conditionalImports(source):
			let fileVisitor = FileVisitor(conditionalCompilationEvaluator: evaluator)
			fileVisitor.walk(Parser.parse(source: source))
			return (fileVisitor.imports, fileVisitor.mockImports)
		}
	}
}

extension ModuleInfo {
	/// This module with the declarations found in files reached through
	/// `#SafeDIConfiguration(additionalDirectoriesToInclude:)`, whose configurations do not apply.
	func including(_ additionalModuleInfo: ModuleInfo) -> ModuleInfo {
		ModuleInfo(
			imports: imports + additionalModuleInfo.imports,
			mockImports: mockImports + additionalModuleInfo.mockImports,
			instantiables: instantiables + additionalModuleInfo.instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.map { $0 + (additionalModuleInfo.filesWithUnexpectedNodes ?? []) } ?? additionalModuleInfo.filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions + additionalModuleInfo.conditionalCompilationDecisions,
			nestedTypeDeclarations: nestedTypeDeclarations.union(additionalModuleInfo.nestedTypeDeclarations),
		)
	}

	/// This module, parsed from some of a module's files, with what the rest of its files contributed:
	/// the module `ModuleInfo(_:)` makes from every file's scan.
	func adding(_ fileScans: [FileScan]) -> ModuleInfo {
		let addedModuleInfo = ModuleInfo(fileScans)
		return ModuleInfo(
			imports: imports + addedModuleInfo.imports,
			mockImports: mockImports + addedModuleInfo.mockImports,
			// Each file's declarations are all in one of the two lists, so sorting keeps each file's declaration order.
			instantiables: (instantiables + addedModuleInfo.instantiables).sortedByDeclaration(),
			configurations: (configurations + addedModuleInfo.configurations).sortedByDeclaration(),
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.map { $0 + (addedModuleInfo.filesWithUnexpectedNodes ?? []) } ?? addedModuleInfo.filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions + addedModuleInfo.conditionalCompilationDecisions,
			nestedTypeDeclarations: nestedTypeDeclarations.union(addedModuleInfo.nestedTypeDeclarations),
		)
	}

	/// This module, keeping the declarations `lookups` read, with `addedDeclarations` and the decisions they rest on.
	/// The declarations of the files whose scans consult no condition rest on no decision.
	func restrictingNestedTypeDeclarations(to lookups: NestedTypeLookups, adding addedDeclarations: NestedTypeDeclarations) -> ModuleInfo {
		let addedDeclarations = addedDeclarations.restricted(to: lookups)
		return ModuleInfo(
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions + addedDeclarations.conditionalCompilationDecisions,
			nestedTypeDeclarations: nestedTypeDeclarations.restricted(to: lookups).union(addedDeclarations),
		)
	}

	/// The module the files contributed to, in file path order whatever order `fileScans` is in.
	init(_ fileScans: [FileScan]) {
		// Files are parsed in parallel, so `fileScans` arrive in the order their parses finished.
		let fileScans = fileScans.sorted { $0.path < $1.path }
		let filesWithUnexpectedNodes = fileScans.filter(\.encounteredUnexpectedNodes).map(\.path)
		self.init(
			imports: fileScans.flatMap(\.imports),
			mockImports: fileScans.flatMap(\.mockImports),
			instantiables: fileScans.flatMap(\.instantiables),
			configurations: fileScans.flatMap(\.configurations),
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.isEmpty ? nil : filesWithUnexpectedNodes,
			// A declaration a lookup reads decides generated code as much as an instantiable does.
			conditionalCompilationDecisions: fileScans.flatMap(\.conditionalCompilationDecisions)
				+ fileScans.flatMap(\.nestedTypeDeclarations.conditionalCompilationDecisions),
			nestedTypeDeclarations: fileScans.reduce(into: NestedTypeDeclarations()) { $0.formUnion($1.nestedTypeDeclarations.located(at: $1.path)) },
		)
	}
}

extension [ImportStatement] {
	/// These imports, each listed once, in an order that depends only on the imports themselves.
	fileprivate func sortedWithoutDuplicates() -> [ImportStatement] {
		Set(self).sorted {
			($0.moduleName, $0.type, $0.kind, $0.attribute) < ($1.moduleName, $1.type, $1.kind, $1.attribute)
		}
	}
}

extension [SafeDIConfiguration] {
	/// These configurations ordered by file path, keeping the declaration order of configurations in the same file.
	fileprivate func sortedByDeclaration() -> [SafeDIConfiguration] {
		enumerated()
			.sorted { lhs, rhs in
				(lhs.element.sourceFilePath ?? "", lhs.offset) < (rhs.element.sourceFilePath ?? "", rhs.offset)
			}
			.map(\.element)
	}
}

/// Reads, parses, and walks every file in parallel under its path, keeping what each file that mentions SafeDI
/// contributes, and the type names in the text of each other file.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkFiles(
	named filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> (fileScans: [FileScan], typeNamesByFileWithoutSafeDIContent: [String: DeclaredTypeNames]) {
	try await withThrowingTaskGroup(
		of: (path: String, walkedFile: WalkedFile).self,
		returning: ([FileScan], [String: DeclaredTypeNames]).self,
	) { taskGroup in
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				switch try readFile(atPath: filePath) {
				case let .declaringSafeDIContent(syntaxTree):
					(path: filePath, walkedFile: .scanned(walk(syntaxTree, at: filePath, conditionalCompilation: evaluator)))
				case let .declaringNoSafeDIContent(typeNames):
					(path: filePath, walkedFile: .declaringNoSafeDIContent(typeNames))
				}
			}
		}

		var fileScans = [FileScan]()
		var typeNamesByFileWithoutSafeDIContent = [String: DeclaredTypeNames]()
		for try await (path, walkedFile) in taskGroup {
			switch walkedFile {
			case let .scanned(fileScan):
				fileScans.append(fileScan)
			case let .declaringNoSafeDIContent(typeNames):
				typeNamesByFileWithoutSafeDIContent[path] = typeNames
			}
		}
		return (fileScans, typeNamesByFileWithoutSafeDIContent)
	}
}

/// What walking one file found.
private enum WalkedFile {
	/// The file mentions SafeDI, and this is what walking it found.
	case scanned(FileScan)
	/// The file mentions no SafeDI declaration, and these are the type names in its text.
	case declaringNoSafeDIContent(DeclaredTypeNames)
}

/// Parses and walks the files at `filePaths`, which mention no SafeDI declaration, in parallel.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkNestedTypeDeclarations(
	inFilesAt filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await withThrowingTaskGroup(
		of: FileScan.self,
		returning: [FileScan].self,
	) { taskGroup in
		for filePath in filePaths {
			taskGroup.addTask {
				let syntaxTree = try Parser.parse(source: String(contentsOfFile: filePath, encoding: .utf8))
				// SafeDI reports syntax errors only in files that declare SafeDI content.
				return walk(syntaxTree, at: filePath, conditionalCompilation: evaluator, reportingUnexpectedNodes: false)
			}
		}

		var fileScans = [FileScan]()
		for try await fileScan in taskGroup {
			fileScans.append(fileScan)
		}
		return fileScans
	}
}

/// What reading one file found.
private enum ReadFile {
	/// The file's text mentions a SafeDI declaration, and this is its syntax tree.
	case declaringSafeDIContent(SourceFileSyntax)
	/// The file's text mentions no SafeDI declaration, and it was not parsed. These are the type names in its text.
	case declaringNoSafeDIContent(DeclaredTypeNames)
}

/// Reads the file at `filePath` and parses it, or, without parsing, finds the type names in its text when its
/// text shows it declares nothing SafeDI scans for.
private func readFile(atPath filePath: String) throws -> ReadFile {
	var content = try String(contentsOfFile: filePath, encoding: .utf8)
	// Searching the bytes rather than the characters is many times faster, and finds the markers wherever a
	// character search does: no other sequence of characters is equivalent to these ASCII ones. It also finds a
	// marker whose last character a combining mark changes, which a character search does not.
	let mentionsSafeDI = content.withUTF8 { source in
		safeDIMarkers.contains(where: source.containsBytes(of:))
	}
	return if mentionsSafeDI {
		.declaringSafeDIContent(Parser.parse(source: content))
	} else {
		.declaringNoSafeDIContent(content.withUTF8(DeclaredTypeNames.init(source:)))
	}
}

/// The text that every file declaring SafeDI content contains.
private let safeDIMarkers = [
	"@\(InstantiableVisitor.macroName)",
	"#\(SafeDIConfigurationVisitor.macroName)",
].map { Array($0.utf8) }

extension UnsafeBufferPointer<UInt8> {
	/// Whether these bytes contain `bytes`, which must not be empty, in a row.
	fileprivate func containsBytes(of bytes: [UInt8]) -> Bool {
		guard var position = baseAddress else { return false }
		let end = position + count
		return bytes.withUnsafeBufferPointer { bytes in
			// Each occurrence of the first byte, with room for the rest after it, is a candidate.
			while end - position >= bytes.count,
			      let candidate = memchr(position, Int32(bytes[0]), end - position - bytes.count + 1)?.assumingMemoryBound(to: UInt8.self)
			{
				if UnsafeBufferPointer(start: candidate, count: bytes.count).elementsEqual(bytes) {
					return true
				} else {
					position = UnsafePointer(candidate) + 1
				}
			}
			return false
		}
	}
}

/// Walks one parsed file.
/// - Parameter reportsUnexpectedNodes: Whether the scan reports the syntax errors the file contains.
/// - Returns: What the file contributes, recording every nested type it declares.
private func walk(
	_ syntaxTree: SourceFileSyntax,
	at filePath: String,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
	reportingUnexpectedNodes reportsUnexpectedNodes: Bool = true,
) -> FileScan {
	let fileVisitor = FileVisitor(
		conditionalCompilationEvaluator: evaluator,
		sourceLocationConverter: SourceLocationConverter(fileName: filePath, tree: syntaxTree),
	)
	fileVisitor.walk(syntaxTree)
	let fileScan = FileScan(
		path: filePath,
		imports: fileVisitor.imports,
		mockImports: fileVisitor.mockImports,
		instantiables: fileVisitor.instantiables,
		configurations: fileVisitor.configurations,
		encounteredUnexpectedNodes: reportsUnexpectedNodes && fileVisitor.encounteredUnexpectedNodesSyntax,
		conditionalCompilationDecisions: fileVisitor.conditionalCompilationDecisions,
		consultedCompilationConditions: fileVisitor.consultedCompilationConditions,
		importSegments: fileVisitor.importOnlyConsultedCompilationConditions.isEmpty ? [] : fileVisitor.importSegments,
		importOnlyConsultedCompilationConditions: fileVisitor.importOnlyConsultedCompilationConditions,
		outputFileDeclarations: fileVisitor.outputFileDeclarations,
		nestedTypeDeclarations: fileVisitor.nestedTypeDeclarations,
	)
	.relocated(to: filePath)
	return fileScan.declaresSafeDIContent ? fileScan : fileScan.replacingImports(with: [], mockImports: [])
}

/// The names a file's text gives the types it can declare or extend, found without parsing it.
///
/// A file declares something at a path a lookup reads, such as `Feature.Settings.Configuration`, only inside a
/// declaration or an extension of `Feature`, so its text names `Feature` right after `struct`, `enum`, `class`,
/// `actor`, `protocol`, or `extension`, and names `Configuration` right after a declaration keyword, among the
/// generic parameters that follow a declared name, or in the path after `extension`. Comments and string literals
/// are not skipped, so the names are a superset of those the file declares or extends, and a file whose names include
/// no looked-up path's outermost type or no looked-up name declares nothing a lookup reads.
struct DeclaredTypeNames: Sendable {
	init(source: UnsafeBufferPointer<UInt8>) {
		guard let start = source.baseAddress else { return }
		// Arrays, which may repeat a name, rather than sets, whose hashing would cost more than all the rest.
		var names = [String]()
		Scanner.identifierByteTable.withUnsafeBufferPointer { identifierBytes in
			var scanner = Scanner(position: start, end: start + source.count, identifierBytes: identifierBytes)
			while let keyword = scanner.nextDeclarationKeyword() {
				switch keyword {
				case .declaration:
					names.append(scanner.nameAfterKeyword())
					// Generic parameters follow the declared name.
					names.append(contentsOf: scanner.genericParameterNames())
				case .extension:
					names.append(contentsOf: scanner.pathAfterKeyword())
				}
			}
		}
		self.names = names
	}

	/// Each name after a `struct`, `enum`, `class`, `actor`, `protocol`, `typealias`, or `associatedtype` keyword,
	/// each identifier among the generic parameters after such a name, and each name in the path after `extension`.
	private(set) var names = [String]()

	/// Whether the file can declare something `lookups` read.
	func canDeclare(lookedUpBy lookups: NestedTypeLookups) -> Bool {
		names.contains(where: lookups.declarationNames.contains) && names.contains(where: lookups.outermostTypeNames.contains)
	}

	/// A keyword that names a type right after it.
	private enum DeclarationKeyword {
		/// A keyword that declares a type.
		case declaration
		case `extension`
	}

	/// Reads identifiers, whitespace, and comments from Swift source, a byte at a time.
	private struct Scanner {
		/// The next byte to read.
		var position: UnsafePointer<UInt8>
		/// The address after the last byte.
		let end: UnsafePointer<UInt8>
		/// `identifierByteTable`, read without checking for its initialization at each byte.
		let identifierBytes: UnsafeBufferPointer<Bool>

		/// The next keyword that names a type right after it, or `nil` at the end of the source.
		mutating func nextDeclarationKeyword() -> DeclarationKeyword? {
			// Reads and writes locals rather than this scanner's properties, which the compiler would otherwise load
			// and store at every byte.
			var position = position
			defer { self.position = position }
			while position < end {
				while position < end, !isIdentifierByte(at: position) {
					position += 1
				}
				let identifierStart = position
				while position < end, isIdentifierByte(at: position) {
					position += 1
				}
				// Every keyword is at least four bytes long, and most identifiers are ruled out by their length and first
				// byte alone.
				let length = position - identifierStart
				guard length >= 4 else { continue }
				let keyword: (spelling: StaticString, keyword: DeclarationKeyword)? = switch (length, identifierStart.pointee) {
				case (4, UInt8(ascii: "e")): ("enum", .declaration)
				case (5, UInt8(ascii: "a")): ("actor", .declaration)
				case (5, UInt8(ascii: "c")): ("class", .declaration)
				case (6, UInt8(ascii: "s")): ("struct", .declaration)
				case (8, UInt8(ascii: "p")): ("protocol", .declaration)
				case (9, UInt8(ascii: "e")): ("extension", .extension)
				case (9, UInt8(ascii: "t")): ("typealias", .declaration)
				case (14, UInt8(ascii: "a")): ("associatedtype", .declaration)
				default: nil
				}
				if let keyword, UnsafeBufferPointer(start: identifierStart, count: length).elementsEqual(UnsafeBufferPointer(start: keyword.spelling.utf8Start, count: length)) {
					return keyword.keyword
				}
			}
			return nil
		}

		/// The name right after a keyword, past whitespace and comments, without backticks, which is empty when no
		/// name follows the keyword.
		mutating func nameAfterKeyword() -> String {
			skipTrivia()
			if position < end, position.pointee == UInt8(ascii: "`") {
				// A backticked name may hold any character but a backtick.
				position += 1
				let nameStart = position
				while position < end, position.pointee != UInt8(ascii: "`") {
					position += 1
				}
				defer { position = min(position + 1, end) }
				return String(decoding: UnsafeBufferPointer(start: nameStart, count: position - nameStart), as: UTF8.self)
			} else {
				let nameStart = position
				skipIdentifier()
				return String(decoding: UnsafeBufferPointer(start: nameStart, count: position - nameStart), as: UTF8.self)
			}
		}

		/// Each name in the dotted path right after a keyword, such as `Feature` and `Settings` in
		/// `extension Feature.Settings`.
		mutating func pathAfterKeyword() -> [String] {
			var names = [nameAfterKeyword()]
			skipTrivia()
			while position < end, position.pointee == UInt8(ascii: ".") {
				position += 1
				names.append(nameAfterKeyword())
				skipTrivia()
			}
			return names
		}

		/// Every identifier in the generic parameter clause right after a declared name, if there is one.
		mutating func genericParameterNames() -> [String] {
			skipTrivia()
			guard position < end, position.pointee == UInt8(ascii: "<") else { return [] }
			position += 1
			var names = [String]()
			var depth = 1
			while depth > 0, position < end {
				if position.pointee == UInt8(ascii: "<") {
					depth += 1
					position += 1
				} else if position.pointee == UInt8(ascii: ">") {
					depth -= 1
					position += 1
				} else if isIdentifierByte(at: position) {
					let nameStart = position
					skipIdentifier()
					names.append(String(decoding: UnsafeBufferPointer(start: nameStart, count: position - nameStart), as: UTF8.self))
				} else {
					position += 1
				}
			}
			return names
		}

		/// Whether each byte can be part of an identifier: letters, digits, underscores, and every byte of a
		/// non-ASCII scalar.
		static let identifierByteTable: [Bool] = (0...UInt8.max).map { Self.isIdentifierByte($0) }

		private static func isIdentifierByte(_ byte: UInt8) -> Bool {
			let lowercased: UInt8 = byte | 0x20
			let isLetter: Bool = lowercased >= UInt8(ascii: "a") && lowercased <= UInt8(ascii: "z")
			let isDigit: Bool = byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
			let isUnderscore: Bool = byte == UInt8(ascii: "_")
			let isNonASCII: Bool = byte >= 0x80
			return isLetter || isDigit || isUnderscore || isNonASCII
		}

		/// Whether the byte at `position` is part of an identifier. A non-breaking space is whitespace to Swift's lexer,
		/// though its bytes are not ASCII. A byte-order mark is too only at the start of a file, which reading the file
		/// into a string removes, and anywhere else is part of an identifier.
		private func isIdentifierByte(at position: UnsafePointer<UInt8>) -> Bool {
			identifierBytes[Int(position.pointee)] && !(position.pointee == 0xC2 && isNonBreakingSpace(at: position))
		}

		private func isNonBreakingSpace(at position: UnsafePointer<UInt8>) -> Bool {
			continues(at: position, with: 0xC2, 0xA0)
		}

		/// Whether the source continues at `position` with `first` and then `second`.
		private func continues(at position: UnsafePointer<UInt8>, with first: UInt8, _ second: UInt8) -> Bool {
			end - position >= 2 && position[0] == first && position[1] == second
		}

		private mutating func skipIdentifier() {
			while position < end, isIdentifierByte(at: position) {
				position += 1
			}
		}

		/// Skips what Swift's lexer treats as trivia: whitespace, including vertical tab, form feed, NUL, and the
		/// non-breaking space, and comments.
		private mutating func skipTrivia() {
			while position < end {
				switch position.pointee {
				case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), 0x0B, 0x0C, 0x00:
					position += 1
				case 0xC2:
					guard isNonBreakingSpace(at: position) else { return }
					position += 2
				case UInt8(ascii: "/"):
					if continues(at: position, with: UInt8(ascii: "/"), UInt8(ascii: "/")) {
						// A line comment ends at either line break.
						while position < end, position.pointee != UInt8(ascii: "\n"), position.pointee != UInt8(ascii: "\r") {
							position += 1
						}
					} else if continues(at: position, with: UInt8(ascii: "/"), UInt8(ascii: "*")) {
						// Block comments nest.
						position += 2
						var depth = 1
						while depth > 0, position < end {
							if continues(at: position, with: UInt8(ascii: "/"), UInt8(ascii: "*")) {
								depth += 1
								position += 2
							} else if continues(at: position, with: UInt8(ascii: "*"), UInt8(ascii: "/")) {
								depth -= 1
								position += 2
							} else {
								position += 1
							}
						}
					} else {
						return
					}
				default:
					return
				}
			}
		}
	}
}
