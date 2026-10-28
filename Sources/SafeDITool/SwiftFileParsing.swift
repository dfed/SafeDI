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
}

/// More than one `#SafeDIConfiguration` was declared among a module's own files.
struct MultipleConfigurationsError: Error, CustomStringConvertible {
	let sourceFilePaths: [String]

	var description: String {
		"Found \(sourceFilePaths.count) #\(SafeDIConfigurationVisitor.macroName) declarations in this module. Each module must have at most one #\(SafeDIConfigurationVisitor.macroName). Found in:\n\t\(sourceFilePaths.joined(separator: "\n\t"))"
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
							"Could not create file enumerator for directory '\(directory)'"
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
	let conventionalConfigurations = conventionalConfigurationFileScans.flatMap(\.fileScan.configurations)
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
		.map(\.fileScan)
		.filter { configurationFilePaths.contains($0.path) }
		.flatMap(\.configurations)
	guard configurations.count <= 1 else {
		throw MultipleConfigurationsError(sourceFilePaths: configurations.compactMap(\.sourceFilePath).sorted())
	}
	let configuration = configurations.first
	let evaluator = conditionalCompilationEvaluator(
		activeCompilationConditions: activeCompilationConditions,
		configuration: configuration,
	)

	return try await ParsedModuleFiles(
		walkedFileScans: evaluator == firstPassEvaluator
			? fileScans
			// Only a configuration outside `SafeDIConfiguration.swift` that changes the mock condition gets here.
			: walkFiles(named: Set(fileScans.map(\.fileScan.path)), conditionalCompilation: evaluator).fileScans,
		typeNamesByFileWithoutSafeDIContent: typeNamesByFileWithoutSafeDIContent,
		configuration: configuration,
		conditionalCompilationEvaluator: evaluator,
	)
}

/// A module's parsed input files, before the nested type declarations SafeDI keeps are known.
struct ParsedModuleFiles {
	fileprivate init(
		walkedFileScans: [WalkedFileScan],
		typeNamesByFileWithoutSafeDIContent: [String: DeclaredTypeNames],
		configuration: SafeDIConfiguration?,
		conditionalCompilationEvaluator: ConditionalCompilationEvaluator,
	) {
		self.walkedFileScans = walkedFileScans
		self.typeNamesByFileWithoutSafeDIContent = typeNamesByFileWithoutSafeDIContent
		self.configuration = configuration
		self.conditionalCompilationEvaluator = conditionalCompilationEvaluator
	}

	/// What each file that mentions SafeDI contributes, recording every nested type it declares.
	var fileScans: [FileScan] {
		walkedFileScans.map(\.fileScan)
	}

	/// The type names in the text of each file that mentions no SafeDI declaration.
	let typeNamesByFileWithoutSafeDIContent: [String: DeclaredTypeNames]
	/// The module's `#SafeDIConfiguration`, found among the configuration file paths it was parsed with.
	let configuration: SafeDIConfiguration?
	/// The evaluator the files were scanned with.
	let conditionalCompilationEvaluator: ConditionalCompilationEvaluator
	private let walkedFileScans: [WalkedFileScan]

	/// The module's file scans, and those of the files reached through `additionalDirectoriesToInclude`, keeping the
	/// nested type declarations that the lookups of their instantiables reach, with what each file that mentions no
	/// SafeDI declaration but declares such a nested type contributes added to the module's file scans.
	///
	/// A file that declares a type at a path a lookup asks about, `Feature.Settings.Configuration`, declares or
	/// extends that path's outermost type, `Feature`, and declares a type or generic parameter named
	/// `Configuration`, so only a file whose text names both is parsed. Neither depends on a condition, so
	/// `generate` reuses scan's choice for the lookups it makes.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func resolvingNestedTypeDeclarations(
		additionalFileScans: [CachedFileScan],
	) async throws -> (fileScans: [FileScan], additionalFileScans: [CachedFileScan]) {
		let lookups = NestedTypeLookups(instantiables: (fileScans + additionalFileScans.map(\.fileScan)).flatMap(\.instantiables))
		let filePathsDeclaringLookedUpTypes = typeNamesByFileWithoutSafeDIContent.compactMap { filePath, typeNames in
			typeNames.canDeclareType(lookedUpBy: lookups) ? filePath : nil
		}
		let fileScansDeclaringOnlyNestedTypes = try await walkNestedTypeDeclarations(
			inFilesAt: Set(filePathsDeclaringLookedUpTypes),
			conditionalCompilation: conditionalCompilationEvaluator,
		)
		.map { $0.resolvingNestedTypeDeclarations(for: lookups) }
		// A file that declares no such type under any conditions contributes nothing.
		.filter { !$0.nestedTypeDeclarations.isEmpty || !$0.consultedCompilationConditions.isEmpty }
		return (
			walkedFileScans.map { $0.resolvingNestedTypeDeclarations(for: lookups) } + fileScansDeclaringOnlyNestedTypes,
			// Their scans already consult the conditions of every block that declares a type.
			additionalFileScans.map { $0.restrictingNestedTypeDeclarations(to: lookups) },
		)
	}
}

/// Parses files that belong to an already-configured module, such as those reached through
/// `#SafeDIConfiguration(additionalDirectoriesToInclude:)`, with the module's evaluator.
/// - Returns: What each file that mentions SafeDI contributes to the module, recording every nested type it declares
///   and consulting the conditions of every `#if` block that declares a type, whichever lookups the module makes.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFiles(
	_ filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await walkFiles(named: filePaths, conditionalCompilation: evaluator).fileScans.map(\.consultingEveryTypeDeclaringBlock)
}

/// The nested types at the paths `lookups` asks about that the files at `filePaths` declare, parsing only the files
/// whose text can declare one, as `ParsedModuleFiles.resolvingNestedTypeDeclarations(additionalFileScans:)` does.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func nestedTypeDeclarations(
	lookedUpBy lookups: NestedTypeLookups,
	inFilesAt filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> NestedTypeDeclarations {
	try await withThrowingTaskGroup(
		of: NestedTypeDeclarations.self,
		returning: NestedTypeDeclarations.self,
	) { taskGroup in
		for filePath in filePaths {
			taskGroup.addTask {
				var content = try String(contentsOfFile: filePath, encoding: .utf8)
				guard content.withUTF8(DeclaredTypeNames.init(source:)).canDeclareType(lookedUpBy: lookups) else {
					return NestedTypeDeclarations()
				}
				return walk(Parser.parse(source: content), at: filePath, conditionalCompilation: evaluator, reportingUnexpectedNodes: false)
					.fileScan
					.nestedTypeDeclarations
					.restricted(to: lookups)
			}
		}
		return try await taskGroup.reduce(into: NestedTypeDeclarations()) { $0.formUnion($1) }
	}
}

/// Parses files that mention no SafeDI declaration but were parsed for the nested types they declare, as
/// `ParsedModuleFiles.resolvingNestedTypeDeclarations(additionalFileScans:)` parses them.
/// - Returns: What each file contributes to the module, recording every nested type it declares.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFilesDeclaringOnlyNestedTypes(
	_ filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await walkNestedTypeDeclarations(inFilesAt: filePaths, conditionalCompilation: evaluator).map(\.consultingEveryTypeDeclaringBlock)
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
	/// The nested types the file declares: every one when the file has just been walked, and once its scan is
	/// resolved, those that the module's lookups reach.
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

	/// This scan, keeping the nested type declarations `lookups` reach.
	func restrictingNestedTypeDeclarations(to lookups: NestedTypeLookups) -> FileScan {
		// Most files that mention SafeDI declare no nested type.
		nestedTypeDeclarations.isEmpty ? self : replacing(nestedTypeDeclarations: nestedTypeDeclarations.restricted(to: lookups))
	}

	/// This scan, consulting `conditions` too.
	fileprivate func consulting(_ conditions: Set<String>) -> FileScan {
		conditions.isEmpty ? self : replacing(consultedCompilationConditions: consultedCompilationConditions.union(conditions))
	}

	private func replacing(
		consultedCompilationConditions: Set<String>? = nil,
		nestedTypeDeclarations: NestedTypeDeclarations? = nil,
	) -> FileScan {
		FileScan(
			path: path,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			encounteredUnexpectedNodes: encounteredUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			consultedCompilationConditions: consultedCompilationConditions ?? self.consultedCompilationConditions,
			importSegments: importSegments,
			importOnlyConsultedCompilationConditions: importOnlyConsultedCompilationConditions,
			outputFileDeclarations: outputFileDeclarations,
			nestedTypeDeclarations: nestedTypeDeclarations ?? self.nestedTypeDeclarations,
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

	/// This module, with `nestedTypeDeclarations` in place of its nested type declarations.
	func replacingNestedTypeDeclarations(with nestedTypeDeclarations: NestedTypeDeclarations) -> ModuleInfo {
		ModuleInfo(
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			nestedTypeDeclarations: nestedTypeDeclarations,
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
			conditionalCompilationDecisions: fileScans.flatMap(\.conditionalCompilationDecisions),
			nestedTypeDeclarations: fileScans.reduce(into: NestedTypeDeclarations()) { $0.formUnion($1.nestedTypeDeclarations) },
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
) async throws -> (fileScans: [WalkedFileScan], typeNamesByFileWithoutSafeDIContent: [String: DeclaredTypeNames]) {
	try await withThrowingTaskGroup(
		of: (path: String, walkedFile: WalkedFile).self,
		returning: ([WalkedFileScan], [String: DeclaredTypeNames]).self,
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

		var fileScans = [WalkedFileScan]()
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
	case scanned(WalkedFileScan)
	/// The file mentions no SafeDI declaration, and these are the type names in its text.
	case declaringNoSafeDIContent(DeclaredTypeNames)
}

/// Parses and walks the files at `filePaths`, which mention no SafeDI declaration, in parallel.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkNestedTypeDeclarations(
	inFilesAt filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [WalkedFileScan] {
	try await withThrowingTaskGroup(
		of: WalkedFileScan.self,
		returning: [WalkedFileScan].self,
	) { taskGroup in
		for filePath in filePaths {
			taskGroup.addTask {
				let syntaxTree = try Parser.parse(source: String(contentsOfFile: filePath, encoding: .utf8))
				// SafeDI reports syntax errors only in files that declare SafeDI content.
				return walk(syntaxTree, at: filePath, conditionalCompilation: evaluator, reportingUnexpectedNodes: false)
			}
		}

		var fileScans = [WalkedFileScan]()
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
	let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
	let containsConfiguration = content.contains("#\(SafeDIConfigurationVisitor.macroName)")
	return if containsInstantiable || containsConfiguration {
		.declaringSafeDIContent(Parser.parse(source: content))
	} else {
		.declaringNoSafeDIContent(content.withUTF8(DeclaredTypeNames.init(source:)))
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
) -> WalkedFileScan {
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
	return WalkedFileScan(
		fileScan: fileScan.declaresSafeDIContent ? fileScan : fileScan.replacingImports(with: [], mockImports: []),
		conditionallyDeclaredTypes: fileVisitor.conditionallyDeclaredTypes,
	)
}

/// What walking one file found: what the file contributes, recording every nested type it declares, and what each
/// of its `#if` blocks declares, which decides the conditions its scan consults once the module's lookups are known.
private struct WalkedFileScan {
	let fileScan: FileScan
	let conditionallyDeclaredTypes: [ConditionallyDeclaredTypes]

	/// The file's scan, keeping the nested type declarations `lookups` reach, and consulting the conditions that
	/// decided which of those the file declares.
	func resolvingNestedTypeDeclarations(for lookups: NestedTypeLookups) -> FileScan {
		fileScan
			.restrictingNestedTypeDeclarations(to: lookups)
			.consulting(conditionallyDeclaredTypes.consultedCompilationConditions(decidingDeclarationsFor: lookups))
	}

	/// The file's scan, consulting the conditions of every `#if` block that declares a type, which decide which
	/// nested types it records whatever lookups the module makes.
	var consultingEveryTypeDeclaringBlock: FileScan {
		fileScan.consulting(conditionallyDeclaredTypes.reduce(into: Set<String>()) { $0.formUnion($1.consultedCompilationConditions) })
	}
}

/// The names a file's text gives the types it can declare or extend, found without parsing it.
///
/// A file declares a type at a path such as `Feature.Settings.Configuration` only inside a declaration or an
/// extension of `Feature`, so its text names `Feature` right after `struct`, `enum`, `class`, `actor`, or
/// `extension`, and names `Configuration` right after a declaration keyword, or among the generic parameters that
/// follow a declared name. Comments and string literals are not skipped, so the names are a superset of those the
/// file declares or extends, and a file whose names include no path's outermost type or no path's last name declares
/// no type at any of those paths.
struct DeclaredTypeNames: Sendable {
	init(source: UnsafeBufferPointer<UInt8>) {
		guard let start = source.baseAddress else { return }
		// Arrays, which may repeat a name, rather than sets, whose hashing would cost more than all the rest.
		var declaredNames = [String]()
		var extendedNames = [String]()
		Scanner.identifierByteTable.withUnsafeBufferPointer { identifierBytes in
			var scanner = Scanner(position: start, end: start + source.count, identifierBytes: identifierBytes)
			while let keyword = scanner.nextDeclarationKeyword() {
				switch keyword {
				case .declaration:
					declaredNames.append(scanner.nameAfterKeyword())
					// Generic parameters follow the declared name.
					declaredNames.append(contentsOf: scanner.genericParameterNames())
				case .extension:
					extendedNames.append(scanner.nameAfterKeyword())
				}
			}
		}
		self.declaredNames = declaredNames
		self.extendedNames = extendedNames
	}

	/// Each name after a `struct`, `enum`, `class`, `actor`, `protocol`, or `typealias` keyword, and each identifier
	/// among the generic parameters after such a name.
	private(set) var declaredNames = [String]()
	/// The first name after each `extension` keyword.
	private(set) var extendedNames = [String]()

	/// Whether the file can declare a type or generic parameter at a path `lookups` asks about.
	func canDeclareType(lookedUpBy lookups: NestedTypeLookups) -> Bool {
		declaredNames.contains(where: lookups.names.contains)
			&& (declaredNames.contains(where: lookups.outermostTypeNames.contains) || extendedNames.contains(where: lookups.outermostTypeNames.contains))
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

		/// The next keyword that names a type right after it, or `nil` at the end of the source.
		mutating func nextDeclarationKeyword() -> DeclarationKeyword? {
			// Reads and writes locals rather than this scanner's properties, which the compiler would otherwise load
			// and store at every byte.
			var position = position
			defer { self.position = position }
			let identifierBytes = identifierBytes
			while position < end {
				while position < end, !identifierBytes[Int(position.pointee)] {
					position += 1
				}
				let identifierStart = position
				while position < end, identifierBytes[Int(position.pointee)] {
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
				default: nil
				}
				if let keyword, memcmp(identifierStart, keyword.spelling.utf8Start, length) == 0 {
					return keyword.keyword
				}
			}
			return nil
		}

		/// The name right after a keyword, past whitespace and comments, without backticks, which is empty when no
		/// name follows the keyword.
		mutating func nameAfterKeyword() -> String {
			skipWhitespaceAndComments()
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

		/// Every identifier in the generic parameter clause right after a declared name, if there is one.
		mutating func genericParameterNames() -> [String] {
			skipWhitespaceAndComments()
			guard position < end, position.pointee == UInt8(ascii: "<") else { return [] }
			position += 1
			var names = [String]()
			var depth = 1
			while depth > 0, position < end {
				switch position.pointee {
				case UInt8(ascii: "<"):
					depth += 1
					position += 1
				case UInt8(ascii: ">"):
					depth -= 1
					position += 1
				case let byte where isIdentifierByte(byte):
					let nameStart = position
					skipIdentifier()
					names.append(String(decoding: UnsafeBufferPointer(start: nameStart, count: position - nameStart), as: UTF8.self))
				default:
					position += 1
				}
			}
			return names
		}

		/// Whether each byte can be part of an identifier: letters, digits, underscores, and every byte of a
		/// non-ASCII scalar.
		static let identifierByteTable = (0...UInt8.max).map { byte in
			byte >= 0x80
				|| byte == UInt8(ascii: "_")
				|| (byte | 0x20 >= UInt8(ascii: "a") && byte | 0x20 <= UInt8(ascii: "z"))
				|| (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
		}

		/// `identifierByteTable`, read without checking for its initialization at each byte.
		let identifierBytes: UnsafeBufferPointer<Bool>

		private func isIdentifierByte(_ byte: UInt8) -> Bool {
			identifierBytes[Int(byte)]
		}

		private mutating func skipIdentifier() {
			while position < end, isIdentifierByte(position.pointee) {
				position += 1
			}
		}

		/// Whether the source continues with `first` and then `second`.
		private func continues(with first: Unicode.Scalar, _ second: Unicode.Scalar) -> Bool {
			position + 1 < end && position.pointee == UInt8(ascii: first) && position[1] == UInt8(ascii: second)
		}

		private mutating func skipWhitespaceAndComments() {
			while position < end {
				if position.pointee == UInt8(ascii: " ") || position.pointee == UInt8(ascii: "\t") || position.pointee == UInt8(ascii: "\n") || position.pointee == UInt8(ascii: "\r") {
					position += 1
				} else if continues(with: "/", "/") {
					while position < end, position.pointee != UInt8(ascii: "\n") {
						position += 1
					}
				} else if continues(with: "/", "*") {
					// Block comments nest.
					position += 2
					var depth = 1
					while depth > 0, position < end {
						if continues(with: "/", "*") {
							depth += 1
							position += 2
						} else if continues(with: "*", "/") {
							depth -= 1
							position += 2
						} else {
							position += 1
						}
					}
				} else {
					return
				}
			}
		}
	}
}
