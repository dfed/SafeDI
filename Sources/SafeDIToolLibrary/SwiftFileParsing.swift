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
public struct ModuleInfo: Codable, Sendable {
	/// A module with `imports`, `mockImports`, `filesWithUnexpectedNodes`, `conditionalCompilationDecisions`,
	/// `instantiableTypeNamesInAnyClause`, and `dependencyModuleNames` sorted, whatever order they are given in, and all
	/// but `filesWithUnexpectedNodes` without duplicates.
	init(
		imports: [ImportStatement],
		mockImports: [ImportStatement],
		instantiables: [Instantiable],
		configurations: [SafeDIConfiguration],
		filesWithUnexpectedNodes: [String]?,
		conditionalCompilationDecisions: [ConditionalCompilationDecision],
		instantiableTypeNamesInAnyClause: [String],
		moduleName: String? = nil,
		packageName: String? = nil,
		dependencyModuleNames: [String] = [],
		plainTypeDeclarations: [PlainTypeDeclaration],
	) {
		self.imports = imports.sortedWithoutDuplicates()
		self.mockImports = mockImports.sortedWithoutDuplicates()
		self.instantiables = instantiables
		self.configurations = configurations
		self.filesWithUnexpectedNodes = filesWithUnexpectedNodes?.sorted()
		self.conditionalCompilationDecisions = Set(conditionalCompilationDecisions).sorted()
		self.instantiableTypeNamesInAnyClause = Set(instantiableTypeNamesInAnyClause).sorted()
		self.moduleName = moduleName
		self.packageName = packageName
		self.dependencyModuleNames = Set(dependencyModuleNames).sorted()
		self.plainTypeDeclarations = plainTypeDeclarations
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
	public let configurations: [SafeDIConfiguration]
	/// The files with syntax errors, sorted.
	let filesWithUnexpectedNodes: [String]?
	/// How each `#if` condition guarding SafeDI declarations, or a plain type declaration the module keeps, was evaluated,
	/// sorted and without duplicates. Generated code asserts these at compile time.
	let conditionalCompilationDecisions: [ConditionalCompilationDecision]
	/// The type each `@Instantiable` declaration in the module's files declares, in any clause of any `#if` block
	/// whatever the conditions, sorted and without duplicates. Unlike `instantiables`, these include the declarations
	/// the conditions leave inactive, so `generate` can tell an `additionalMocksToGenerate` entry that names such a
	/// type, whose mock file it writes without code, from one that names no type at all. They are the same whatever
	/// the conditions, which is why scan's cache needs no condition to reuse them.
	let instantiableTypeNamesInAnyClause: [String]
	/// The module `generate` generated code for from these files, or `nil` when the build system did not say. Each of
	/// `instantiables` records the module that declares it, which in a build tool plugin's input set is often another.
	let moduleName: String?
	/// The package of the module `generate` generated code for, as `Instantiable.packageName` names a package, or `nil`
	/// when the build system did not say.
	let packageName: String?
	/// The names of the modules the module `generate` generated code for depends on directly, as the build system
	/// lists them, sorted and without duplicates. Empty when the build system did not say.
	let dependencyModuleNames: [String]
	/// The declarations of types that are not `@Instantiable`, outside every `#if` block or in a clause the conditions
	/// select, directly inside an extension or not, of the types whose declarations SafeDI reads (`parseModule`), in the
	/// files SafeDI parses and in each file it would otherwise skip that may declare one, ordered as `instantiables` is.
	/// Each records the module that declares it.
	let plainTypeDeclarations: [PlainTypeDeclaration]
}

/// A module's parsed input files together with the configuration that governed the parse.
public struct ParsedModule: Sendable {
	public let moduleInfo: ModuleInfo
	/// The module's `#SafeDIConfiguration`, found among the configuration file paths it was parsed with.
	let configuration: SafeDIConfiguration?
	/// The evaluator the files were scanned with. Files parsed later for the same module, such as
	/// those in `configuration.additionalDirectoriesToInclude`, must be scanned with it too.
	let conditionalCompilationEvaluator: ConditionalCompilationEvaluator
	/// The entries of `configuration.additionalDirectoriesToInclude`, each with the path its files were found at.
	let additionalDirectories: [AdditionalDirectory]
}

/// An entry of a `#SafeDIConfiguration(additionalDirectoriesToInclude:)`, and the absolute path SafeDI looked for
/// Swift files at: the entry itself when absolute, and otherwise the entry relative to the working directory of the
/// SafeDITool that looked, exactly as `findSwiftFiles(inDirectories:)` resolves it.
struct AdditionalDirectory: Codable, Hashable {
	/// The entry resolved against this SafeDITool's working directory.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	init(entry: String) {
		self.entry = entry
		path = entry.asFileURL.path
	}

	/// An entry as another SafeDITool, whose working directory may differ, resolved it.
	init(entry: String, path: String) {
		self.entry = entry
		self.path = path
	}

	/// The entry as the configuration writes it.
	let entry: String
	/// The absolute path the entry names.
	let path: String

	/// A warning when SafeDI can read no Swift file from `path`: nothing exists there, or a file other than a Swift
	/// file does. A directory, even an empty one, and a Swift file are what an entry is for.
	func unreadableWarning(at location: Dependency.DeclarationLocation?) -> SourceDiagnostic? {
		let unreadableDescription: String
		var isDirectory: ObjCBool = false
		if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
			let relativePathExplanation = (entry as NSString).isAbsolutePath ? "" : " SafeDI resolves a relative path against the directory SafeDITool runs in."
			unreadableDescription = "nothing exists at `\(path)`, so SafeDI reads no Swift files from it.\(relativePathExplanation) Correct the path"
		} else if !isDirectory.boolValue, URL(fileURLWithPath: path).pathExtension != "swift" {
			unreadableDescription = "`\(path)` is neither a directory nor a Swift file, so SafeDI reads no Swift files from it. List a directory or a Swift file"
		} else {
			return nil
		}
		return SourceDiagnostic(
			severity: .warning,
			location: location,
			message: "This #\(SafeDIConfigurationVisitor.macroName) lists `\(entry)` in \(SafeDIConfigurationVisitor.additionalDirectoriesToIncludeArgumentLabel), but \(unreadableDescription), or remove it from \(SafeDIConfigurationVisitor.additionalDirectoriesToIncludeArgumentLabel).",
		)
	}
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

	/// A warning for each of `additionalDirectories`, this configuration's entries as SafeDI resolved them, from which
	/// SafeDI can read no Swift file, once per entry, in the order the configuration lists them.
	func unreadableAdditionalDirectoryWarnings(for additionalDirectories: [AdditionalDirectory]) -> [SourceDiagnostic] {
		var judgedAdditionalDirectories = Set<AdditionalDirectory>()
		return additionalDirectories.compactMap { additionalDirectory in
			guard judgedAdditionalDirectories.insert(additionalDirectory).inserted else { return nil }
			return additionalDirectory.unreadableWarning(at: declarationLocation)
		}
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

/// The normalized paths of the Swift files in `directories`, each absolute or relative to the working directory. An
/// entry may also name a single Swift file. An entry that names nothing contributes no files.
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
				// An entry may name a single Swift file. One that names nothing contributes no files, as a missing
				// directory does, rather than failing when the file is read: `generate` warns about it.
				let includedFile = FileManager.default.fileExists(atPath: includedURL.path) ? [includedURL] : []
				return (files + includedFile).compactMap {
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
/// - Parameters:
///   - filePaths: Every file to parse.
///   - configurationFilePaths: The files that belong to the module itself, which are the only ones whose
///     `#SafeDIConfiguration` applies. In a multi-module input set these are the current target's files.
///   - activeCompilationConditions: The conditions supplied on the command line and through the manifest.
///   - keepsTypeDeclarationsOtherModulesCanName: Whether the module's plain type declarations that a module reading its
///     info needs – `package` ones, and nested ones `public` or `open` at every level of their chain
///     (`isKeptForModulesReadingModuleInfo(level:isNested:)`) – are kept too, wherever they are and whatever the module's
///     declarations mention, for a run that writes the module's info without a target graph.
///   - isReadingModuleFile: Whether the file at a path among `filePaths` is one of the module's own files, rather than one
///     of a module it depends on: a mention in the module names an `internal` declaration of its own files only, so a
///     decision about another module's is that module's to assert.
/// - Returns: The module, and what each file contributed to it.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public func parseModule(
	filePaths: Set<String>,
	configurationFilePaths: Set<String>,
	activeCompilationConditions: Set<String>,
	keepsTypeDeclarationsOtherModulesCanName: Bool = false,
	isReadingModuleFile: (String) -> Bool = { _ in true },
) async throws -> (module: ParsedModule, fileScans: [FileScan]) {
	let defaultEvaluator = ConditionalCompilationEvaluator(activeCompilationConditions: activeCompilationConditions)

	let conventionalConfigurationFilePaths = filePaths.filter { filePath in
		configurationFilePaths.contains(filePath) && SafeDIConfiguration.isInConventionalFile(atPath: filePath)
	}
	let conventionalConfigurationFileReads = try conventionalConfigurationFilePaths.sorted().map { filePath in
		try (path: filePath, read: readSwiftFile(atPath: filePath, findingDeclarationsModulesReadingModuleInfoNeed: keepsTypeDeclarationsOtherModulesCanName))
	}
	let conventionalConfigurationFiles = conventionalConfigurationFileReads.compactMap { file in
		file.read.syntaxTree.map { (path: file.path, syntaxTree: $0) }
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
	let walkedFiles = try await walkFiles(
		named: filePaths.subtracting(conventionalConfigurationFilePaths),
		conditionalCompilation: firstPassEvaluator,
		findingDeclarationsModulesReadingModuleInfoNeed: keepsTypeDeclarationsOtherModulesCanName,
	)
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

	let finalFileScans = try await evaluator == firstPassEvaluator
		? fileScans
		// Only a configuration outside `SafeDIConfiguration.swift` that changes the mock condition gets here.
		: walkFiles(named: Set(fileScans.map(\.path)), conditionalCompilation: evaluator).fileScans
	// A file whose text mentions no SafeDI marker is not parsed, but it can declare a type whose plain declaration
	// SafeDI reads: one an extension holding SafeDI content extends, whose access bounds the types that extension
	// declares – a namespace enum in a file of its own – and one a declaration's dependencies or members mention, whose
	// access proves the access of a generated parameter that names it. The extended types' names, and the outermost
	// types enclosing `@Instantiable` types, whose nested types a member names unqualified, come from every clause of
	// every `#if` block; the mentioned types' names from the declarations these conditions select, which `generate`
	// checks scan's names cover (`keptPlainTypeNames(of:)`). Only the declarations of those types, and of the types
	// nested in them, are kept, and only the decisions of the blocks that could declare one are asserted: no other plain
	// declaration bounds or proves anything.
	let keptTypeNames = keptPlainTypeNames(of: finalFileScans)
	var mayDeclareTypesNamedBySkippedFilePath = walkedFiles.mayDeclareTypesNamedBySkippedFilePath
	for file in conventionalConfigurationFileReads {
		// A file that was parsed may declare no type of a name, and is not parsed again.
		mayDeclareTypesNamedBySkippedFilePath[file.path] = file.read.mayDeclareTypesNamed
	}
	// A file that may declare a type a module reading the module's info needs is parsed whatever names the text search
	// found in it: the search misses a name behind a comment, which such a declaration can have.
	let skippedFilePathsThatMayDeclareTypesModulesReadingModuleInfoNeed = walkedFiles.skippedFilePathsThatMayDeclareTypesModulesReadingModuleInfoNeed
		.union(conventionalConfigurationFileReads.filter(\.read.mayDeclareTypeModulesReadingModuleInfoNeed).map(\.path))
	let moduleFileScans = try await (finalFileScans + walkFilesDeclaringTypes(
		among: Set(mayDeclareTypesNamedBySkippedFilePath.filter { !$0.value.isDisjoint(with: keptTypeNames.outermostTypeNames) }.map(\.key))
			.union(skippedFilePathsThatMayDeclareTypesModulesReadingModuleInfoNeed)
			.sorted(),
		conditionalCompilation: evaluator,
	))
	.map { fileScan in
		fileScan.keepingPlainTypeDeclarations(
			ofTypesWithin: keptTypeNames,
			keepingThoseOtherModulesCanName: keepsTypeDeclarationsOtherModulesCanName,
			isInReadingModule: isReadingModuleFile(fileScan.path),
		)
	}
	return (
		ParsedModule(
			moduleInfo: ModuleInfo(moduleFileScans),
			configuration: configuration,
			conditionalCompilationEvaluator: evaluator,
			additionalDirectories: configuration?.additionalDirectoriesToInclude.map(AdditionalDirectory.init(entry:)) ?? [],
		),
		moduleFileScans,
	)
}

/// Parses files that belong to an already-configured module, such as those reached through
/// `#SafeDIConfiguration(additionalDirectoriesToInclude:)` or those of the module whose scan `generate` walks again, with
/// the module's evaluator, and the files among them that mention no SafeDI marker but may declare a type the module or
/// the parsed files mention: one whose plain declaration proves the access of a parameter SafeDI generates, which a type
/// of another module SafeDI reads no declaration of would count as `public`. Each file keeps the plain declarations of
/// those types alone, as `parseModule` keeps them.
/// - Parameters:
///   - moduleTypeNames: The names of the types the module's other declarations mention (`keptPlainTypeNames(of:)`).
///   - keepsTypeDeclarationsOtherModulesCanName: Whether the plain declarations that a module reading the module's info
///     needs are kept too, wherever they are, as `parseModule` keeps them for a run that writes the module's info without
///     a target graph.
///   - isReadingModuleFile: Whether the file at a path among `filePaths` is one of the module's own files, as
///     `parseModule` asks it.
/// - Returns: What each file that mentions SafeDI, or declares such a type, contributes to the module.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFilesDeclaringTypes(
	_ filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
	keepingDeclarationsOfTypesNamed moduleTypeNames: KeptPlainTypeNames,
	keepsTypeDeclarationsOtherModulesCanName: Bool = false,
	isReadingModuleFile: (String) -> Bool,
) async throws -> [FileScan] {
	let walkedFiles = try await walkFiles(named: filePaths, conditionalCompilation: evaluator, findingDeclarationsModulesReadingModuleInfoNeed: keepsTypeDeclarationsOtherModulesCanName)
	let keptTypeNames = moduleTypeNames.union(keptPlainTypeNames(of: walkedFiles.fileScans))
	return try await (walkedFiles.fileScans + walkFilesDeclaringTypes(
		among: Set(walkedFiles.mayDeclareTypesNamedBySkippedFilePath.filter { !$0.value.isDisjoint(with: keptTypeNames.outermostTypeNames) }.map(\.key))
			.union(walkedFiles.skippedFilePathsThatMayDeclareTypesModulesReadingModuleInfoNeed)
			.sorted(),
		conditionalCompilation: evaluator,
	))
	.map { fileScan in
		fileScan.keepingPlainTypeDeclarations(
			ofTypesWithin: keptTypeNames,
			keepingThoseOtherModulesCanName: keepsTypeDeclarationsOtherModulesCanName,
			isInReadingModule: isReadingModuleFile(fileScan.path),
		)
	}
}

// MARK: - Private

/// The modules the file at `filePath` imports in the clauses `evaluator` selects, or `nil` when the file cannot be read.
/// Read only on the path of an error, so the file is read and parsed again rather than kept from the module's scan.
func importedModuleNames(ofFileAt filePath: String, conditionalCompilation evaluator: ConditionalCompilationEvaluator) -> Set<String>? {
	(try? String(contentsOfFile: filePath, encoding: .utf8)).map { source in
		let fileVisitor = FileVisitor(conditionalCompilationEvaluator: evaluator)
		fileVisitor.walk(Parser.parse(source: source))
		return Set(fileVisitor.imports.map(\.moduleName))
	}
}

/// What one file contributed to the module.
public struct FileScan: Codable, Sendable {
	let path: String
	let imports: [ImportStatement]
	let mockImports: [ImportStatement]
	let instantiables: [Instantiable]
	public let configurations: [SafeDIConfiguration]
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
	/// The file's declarations of types that are not `@Instantiable` (`FileVisitor.plainTypeDeclarations`), outside every
	/// `#if` block and in the clauses the conditions select, which `consultedCompilationConditions` cover once the module
	/// keeps them (`keepingPlainTypeDeclarations(ofTypesWithin:keepingThoseOtherModulesCanName:isInReadingModule:)`).
	let plainTypeDeclarations: [PlainTypeDeclaration]
	/// How the conditions of the file's `#if` blocks that declare a plain type and guard nothing else SafeDI reads were
	/// evaluated, with the conditions each consulted and the types it declares (`FileVisitor.plainTypeDeclarationDecisions`),
	/// until `keepingPlainTypeDeclarations(ofTypesWithin:keepingThoseOtherModulesCanName:isInReadingModule:)` adds
	/// the conditions of the blocks that could declare a declaration the module keeps to `consultedCompilationConditions`
	/// and asserts the decisions a read resolves by, among `conditionalCompilationDecisions`, and drops the rest.
	let plainTypeDeclarationDecisions: [GuardedPlainTypeNames]
	/// The own name of each type that a block of `plainTypeDeclarationDecisions` with decisions declares, in any clause,
	/// whose declaration the module keeps, sorted and without duplicates: whether a declaration mentions that name decides
	/// whether the block's decisions are asserted (`KeptPlainTypeNames.assertsDecisions(about:isInReadingModule:)`), so
	/// `generate` parses the module afresh when a mention of one appears or goes away, even of a name a top-level
	/// `@Instantiable` type shares. Empty until the module keeps its plain declarations.
	let keptGuardedPlainTypeNames: [String]

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

	/// This scan, with the imports and mock imports `evaluator` finds in `importSegments`.
	func withImports(evaluatedWith evaluator: ConditionalCompilationEvaluator) -> FileScan {
		guard declaresSafeDIContent else {
			return replacingImports(with: [], mockImports: [])
		}
		let segmentImports = importSegments.map { $0.imports(evaluatedWith: evaluator) }
		return replacingImports(
			with: segmentImports.flatMap(\.imports).map { $0.spelled(in: path) },
			mockImports: segmentImports.flatMap(\.mockImports).map { $0.spelled(in: path) },
		)
	}

	/// This scan, keeping the declarations of `plainTypeDeclarations` of the types `keptTypeNames` keeps, and, when
	/// `keepingThoseOtherModulesCanName`, those a module that reads the module's info needs whatever the module's
	/// declarations mention (`isKeptForModulesReadingModuleInfo(level:isNested:)`).
	///
	/// Each block of `plainTypeDeclarationDecisions` that declares, in any clause, a type such a declaration could be of
	/// decides which of them are read, so its conditions join `consultedCompilationConditions`; the conditions of the rest
	/// decide nothing the module reads. Its decisions are asserted, among `conditionalCompilationDecisions`, when a read
	/// the access check makes can resolve to such a declaration (`KeptPlainTypeNames.assertsDecisions(about:isInReadingModule:)`),
	/// or, when `keepingThoseOtherModulesCanName`, the declaration is one a module that reads the module's info needs.
	/// - Parameter isInReadingModule: Whether the file is one of the module's own, whose `internal` declarations a mention
	///   in the module names; a mention in another module names only a declaration that is `package` or wider.
	func keepingPlainTypeDeclarations(ofTypesWithin keptTypeNames: KeptPlainTypeNames, keepingThoseOtherModulesCanName: Bool, isInReadingModule: Bool) -> FileScan {
		var decisions = conditionalCompilationDecisions
		var consultedCompilationConditions = consultedCompilationConditions
		var keptGuardedTypeNames = Set(keptGuardedPlainTypeNames)
		for guardedNames in plainTypeDeclarationDecisions {
			let keptTypes = guardedNames.declaredTypes.filter { declaredType in
				keptTypeNames.outermostTypeNames.contains(declaredType.outermostName)
					|| (keepingThoseOtherModulesCanName && isKeptForModulesReadingModuleInfo(level: declaredType.level, isNested: declaredType.isNested))
			}
			guard !keptTypes.isEmpty else { continue }
			consultedCompilationConditions.formUnion(guardedNames.consultedConditions)
			if !guardedNames.decisions.isEmpty {
				keptGuardedTypeNames.formUnion(keptTypes.map(\.name))
			}
			guard keptTypes.contains(where: { declaredType in
				keptTypeNames.assertsDecisions(about: declaredType, isInReadingModule: isInReadingModule)
					|| (keepingThoseOtherModulesCanName && isKeptForModulesReadingModuleInfo(level: declaredType.level, isNested: declaredType.isNested))
			}) else { continue }
			for decision in guardedNames.decisions where !decisions.contains(decision) {
				decisions.append(decision)
			}
		}
		return FileScan(
			path: path,
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			encounteredUnexpectedNodes: encounteredUnexpectedNodes,
			conditionalCompilationDecisions: decisions,
			consultedCompilationConditions: consultedCompilationConditions,
			importSegments: importSegments,
			importOnlyConsultedCompilationConditions: importOnlyConsultedCompilationConditions,
			outputFileDeclarations: outputFileDeclarations,
			plainTypeDeclarations: plainTypeDeclarations.filter { plainTypeDeclaration in
				plainTypeDeclaration.typeDescription.outermostTypeName.map { keptTypeNames.outermostTypeNames.contains($0.spelledWithoutBackticks) } == true
					|| (keepingThoseOtherModulesCanName && isKeptForModulesReadingModuleInfo(
						level: TypeAccessProof.normalized(plainTypeDeclaration.levelBeforeExtendedTypeCap),
						isNested: plainTypeDeclaration.isNested,
					))
			},
			plainTypeDeclarationDecisions: [],
			keptGuardedPlainTypeNames: keptGuardedTypeNames.sorted(),
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
			plainTypeDeclarations: plainTypeDeclarations,
			plainTypeDeclarationDecisions: plainTypeDeclarationDecisions,
			keptGuardedPlainTypeNames: keptGuardedPlainTypeNames,
		)
	}

	/// This scan, with the file and everything declared in it named by `path`, the imports that spell a level included.
	func relocated(to path: String) -> FileScan {
		FileScan(
			path: path,
			imports: imports.map { $0.spelled(in: path) },
			mockImports: mockImports.map { $0.spelled(in: path) },
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
			plainTypeDeclarations: plainTypeDeclarations.map {
				var plainTypeDeclaration = $0
				plainTypeDeclaration.sourceFilePath = path
				return plainTypeDeclaration
			},
			plainTypeDeclarationDecisions: plainTypeDeclarationDecisions,
			keptGuardedPlainTypeNames: keptGuardedPlainTypeNames,
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
			instantiableTypeNamesInAnyClause: instantiableTypeNamesInAnyClause + additionalModuleInfo.instantiableTypeNamesInAnyClause,
			moduleName: moduleName,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
			plainTypeDeclarations: plainTypeDeclarations + additionalModuleInfo.plainTypeDeclarations,
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
			instantiableTypeNamesInAnyClause: instantiableTypeNamesInAnyClause + addedModuleInfo.instantiableTypeNamesInAnyClause,
			moduleName: moduleName,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
			plainTypeDeclarations: (plainTypeDeclarations + addedModuleInfo.plainTypeDeclarations).sortedByDeclaration(),
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
			instantiableTypeNamesInAnyClause: fileScans.flatMap(\.outputFileDeclarations.instantiableTypeNames),
			plainTypeDeclarations: fileScans.flatMap(\.plainTypeDeclarations),
		)
	}
}

extension [ImportStatement] {
	/// These imports, each listed once, in an order that depends only on the imports themselves.
	fileprivate func sortedWithoutDuplicates() -> [ImportStatement] {
		Set(self).sorted { $0.sortKey.lexicographicallyPrecedes($1.sortKey) }
	}
}

extension ImportStatement {
	/// What orders imports: every field, so that the order depends only on the imports themselves.
	fileprivate var sortKey: [String] {
		let accessLevel: String = accessLevel?.spelling ?? ""
		let sourceFilePath: String = sourceFilePath ?? ""
		return [moduleName, type, kind, attribute, accessLevel, sourceFilePath]
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

/// The names of the types whose plain declarations a module parsed into `fileScans` keeps, and of those a read the access
/// check makes resolves by (`KeptPlainTypeNames`).
func keptPlainTypeNames(of fileScans: [FileScan]) -> KeptPlainTypeNames {
	let outputFileDeclarations = fileScans.map(\.outputFileDeclarations)
	return KeptPlainTypeNames(
		extendedTypeNames: Set(outputFileDeclarations.flatMap(\.extendedTypeNames).map(\.spelledWithoutBackticks)),
		instantiableChainTypeNames: Set(outputFileDeclarations.flatMap(\.instantiableTypeNames).flatMap(namesBoundingType(named:))),
		mentionedTypeNames: mentionedTypeNames(of: fileScans.flatMap(\.instantiables)),
	)
}

/// Whether a run that writes a module's info without a target graph keeps a plain declaration of the module at `level`,
/// normalized (`TypeAccessProof.normalized(_:)`), whatever the module's declarations mention: the modules that read that
/// info cannot tell which of its types they will name. It keeps one only another module of the package can name, wherever
/// it is, and one nested in another type (`PlainTypeDeclaration.isNested`) that every module can name, `public` or `open`
/// at every level of its chain: a module that extends the type enclosing it names it unqualified, and qualifies the name
/// only by its record (`TypeAccessProof.NestedTypeQualifier`). A top-level `public` or `open` declaration needs no record:
/// a type no declaration SafeDI reads declares counts as `public` (`TypeAccessProof`), and a mention spells it by its own
/// name.
func isKeptForModulesReadingModuleInfo(level: AccessLevel, isNested: Bool) -> Bool {
	switch level {
	case .package:
		true
	case .open, .public:
		isNested
	case .internal, .fileprivate, .private:
		false
	}
}

/// The names of the types whose plain declarations a module keeps, and of those a read the access check makes resolves by,
/// each spelled without the backticks it was written with: Swift reads `` `Token` `` and `Token` as one name, so a
/// declaration and a mention that spell it differently match (`GuardedPlainTypeNames.DeclaredType`, and
/// `TypeDescription.plainDeclarationKey`, by which a declaration is looked up).
struct KeptPlainTypeNames: Codable, Equatable, Sendable {
	/// - Parameters:
	///   - extendedTypeNames: The outermost name of each type an extension that is or holds an `@Instantiable`
	///     declaration extends, in any clause (`OutputFileDeclarations.extendedTypeNames`).
	///   - instantiableChainTypeNames: The names along the chain of each `@Instantiable` type that can bound it, in any
	///     clause: the outermost type enclosing it, or its own name when nothing does, and each type nested between.
	///   - mentionedTypeNames: Every name of each type the module's declarations mention (`mentionedTypeNames(of:)`).
	init(extendedTypeNames: Set<String>, instantiableChainTypeNames: Set<String>, mentionedTypeNames: Set<String>) {
		self.init(
			outermostTypeNames: extendedTypeNames.union(instantiableChainTypeNames).union(mentionedTypeNames),
			mentionedTypeNames: mentionedTypeNames,
			extendedTypeNames: extendedTypeNames,
		)
	}

	/// - Parameters:
	///   - outermostTypeNames: The outermost names of the types whose plain declarations the module keeps, which hold
	///     `mentionedTypeNames` and `extendedTypeNames`.
	///   - mentionedTypeNames: Every name of each type the module's declarations mention.
	///   - extendedTypeNames: The outermost name of each type an extension that is or holds an `@Instantiable`
	///     declaration extends.
	init(outermostTypeNames: Set<String>, mentionedTypeNames: Set<String>, extendedTypeNames: Set<String>) {
		self.outermostTypeNames = outermostTypeNames
		self.mentionedTypeNames = mentionedTypeNames
		self.extendedTypeNames = extendedTypeNames
	}

	/// The names of the types whose plain declarations the module keeps when only `mentionedTypeNames` are mentioned: the
	/// declarations a mention can resolve to.
	init(mentioning mentionedTypeNames: Set<String>) {
		self.init(extendedTypeNames: [], instantiableChainTypeNames: [], mentionedTypeNames: mentionedTypeNames)
	}

	/// The outermost names of the types whose plain declarations the module keeps, with the types nested in them: each
	/// type an extension that is or holds an `@Instantiable` extends and the outermost type enclosing each `@Instantiable`
	/// type, in any clause, and each type its declarations mention. A member of an `@Instantiable` type can name a type
	/// nested in it, or in a type enclosing it, by the nested type's own name, which normalization qualifies from that
	/// type's declaration (`TypeAccessProof.NestedTypeQualifier`). A file without
	/// a SafeDI marker is parsed when it may declare a type of one of these names (`parseModule`), so they also hold each
	/// name between the outermost and each `@Instantiable` type: a namespace an extension declaring the type extends can
	/// be declared inside another extension, in a file that names only the namespace, and bounds the type
	/// (`DependencyTreeGenerator.extendedTypeAccessNeeds(of:in:)`).
	let outermostTypeNames: Set<String>
	/// Every name of each type the module's declarations mention, the outermost and each nested one: the names a mention
	/// resolves to a plain declaration by.
	let mentionedTypeNames: Set<String>
	/// The outermost name of each type an extension that is or holds an `@Instantiable` declaration extends, in any
	/// clause: a declaration of it, or of a type nested in it, bounds the types the extension declares.
	let extendedTypeNames: Set<String>

	/// These names and those of `other`.
	func union(_ other: KeptPlainTypeNames) -> KeptPlainTypeNames {
		KeptPlainTypeNames(
			outermostTypeNames: outermostTypeNames.union(other.outermostTypeNames),
			mentionedTypeNames: mentionedTypeNames.union(other.mentionedTypeNames),
			extendedTypeNames: extendedTypeNames.union(other.extendedTypeNames),
		)
	}

	/// Whether a read the access check makes can resolve to a kept declaration of `declaredType`, so that the decisions
	/// that select the clause declaring it are asserted: a mention of its own name, or the extension of a type it is or is
	/// nested in. A mention in the module names the module's own declarations, and another module's only when they are
	/// `package` or wider, so a declaration in another module's file (`isInReadingModule` false) that is narrower is no
	/// declaration this module's reads resolve to: that module's own run asserts its decisions.
	func assertsDecisions(about declaredType: GuardedPlainTypeNames.DeclaredType, isInReadingModule: Bool) -> Bool {
		outermostTypeNames.contains(declaredType.outermostName)
			&& (mentionedTypeNames.contains(declaredType.name) || extendedTypeNames.contains(declaredType.outermostName))
			&& (declaredType.level >= .package || isInReadingModule)
	}
}

/// The names along the chain of the type `typeName` spells, as `OutputFileDeclarations.instantiableTypeNames` records a
/// type, that can bound it: the outermost type's and each nested type's, without its own unless it is the outermost. The
/// construction check reads a declaration of each type enclosing it, never another declaration of its own name
/// (`DependencyTreeGenerator.extendedTypeAccessNeeds(of:in:)`), and a top-level type's name keeps the declarations of
/// the types nested in it.
private func namesBoundingType(named typeName: String) -> [String] {
	var parser = Parser(typeName)
	var names = [String]()
	var remainingType: TypeDescription? = TypeSyntax.parse(from: &parser).typeDescription
	while let type = remainingType, let name = type.outermostTypeName {
		names.append(name.spelledWithoutBackticks)
		remainingType = type.droppingOutermostType
	}
	return names.count > 1 ? Array(names.dropLast()) : names
}

/// Every name of each type the dependencies – an alias's fulfilling property among them –, initializer or
/// `instantiate(…)` method, or hand-written mock method of each of `instantiables` mentions
/// (`TypeAccessProof.mentionedTypes(in:)`), the outermost and each nested one: the types whose plain declarations can
/// prove the access of a parameter SafeDI generates. A nested name is what a file declaring the type inside an extension
/// of the type enclosing it shows (`extension Space.Inner { struct Config {} }`), and the second name of a mention
/// qualified by a module's name (`Core.Theme`) is the type's. An alias's fulfilling property is one: a seam whose tree
/// receives it takes it. Each name is spelled without the backticks it was written with (`KeptPlainTypeNames`).
func mentionedTypeNames(of instantiables: [Instantiable]) -> Set<String> {
	var mentionedTypeNames = Set<String>()
	for instantiable in instantiables {
		let mentioningTypes = instantiable.dependencies.flatMap { dependency in
			switch dependency.source {
			case let .aliased(fulfillingProperty, _, _):
				[dependency.property.typeDescription, fulfillingProperty.typeDescription]
			case .instantiated, .received, .forwarded:
				[dependency.property.typeDescription]
			}
		}
			+ (instantiable.initializer?.arguments ?? []).map(\.typeDescription)
			+ (instantiable.mockInitializer?.arguments ?? []).map(\.typeDescription)
		for mentioningType in mentioningTypes {
			for mentionedType in TypeAccessProof.mentionedTypes(in: mentioningType) {
				var remainingType: TypeDescription? = mentionedType.withoutGenericArguments
				while let type = remainingType, let name = type.outermostTypeName {
					mentionedTypeNames.insert(name.spelledWithoutBackticks)
					remainingType = type.droppingOutermostType
				}
			}
		}
	}
	return mentionedTypeNames
}

/// What `walkFiles(named:conditionalCompilation:findingDeclarationsModulesReadingModuleInfoNeed:)` found.
private struct WalkedFiles {
	/// What each file that mentions SafeDI contributes.
	var fileScans = [FileScan]()
	/// The names each file that mentions no SafeDI marker may declare a type of (`ReadSwiftFile.mentionsNoSafeDI`), for
	/// each such file that may declare one.
	var mayDeclareTypesNamedBySkippedFilePath = [String: Set<String>]()
	/// The files that mention no SafeDI marker and may declare a type a module reading the module's info needs
	/// (`ReadSwiftFile.mayDeclareTypeModulesReadingModuleInfoNeed`).
	var skippedFilePathsThatMayDeclareTypesModulesReadingModuleInfoNeed = Set<String>()
}

/// Reads, parses, and walks every file in parallel under its path, keeping what each file that mentions SafeDI
/// contributes, and the names of the types each other file may declare, and, when
/// `findingDeclarationsModulesReadingModuleInfoNeed`, whether it may declare one a module reading the module's info needs.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkFiles(
	named filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
	findingDeclarationsModulesReadingModuleInfoNeed: Bool = false,
) async throws -> WalkedFiles {
	try await withThrowingTaskGroup(
		of: (path: String, read: WalkedSwiftFile).self,
		returning: WalkedFiles.self,
	) { taskGroup in
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				let read = try readSwiftFile(atPath: filePath, findingDeclarationsModulesReadingModuleInfoNeed: findingDeclarationsModulesReadingModuleInfoNeed)
				return if let syntaxTree = read.syntaxTree {
					(filePath, .scanned(walk(syntaxTree, at: filePath, conditionalCompilation: evaluator)))
				} else {
					(filePath, .skipped(mayDeclareTypesNamed: read.mayDeclareTypesNamed, mayDeclareTypeModulesReadingModuleInfoNeed: read.mayDeclareTypeModulesReadingModuleInfoNeed))
				}
			}
		}

		var walkedFiles = WalkedFiles()
		for try await file in taskGroup {
			switch file.read {
			case let .scanned(fileScan):
				walkedFiles.fileScans.append(fileScan)
			case let .skipped(mayDeclareTypesNamed, mayDeclareTypeModulesReadingModuleInfoNeed):
				if !mayDeclareTypesNamed.isEmpty {
					walkedFiles.mayDeclareTypesNamedBySkippedFilePath[file.path] = mayDeclareTypesNamed
				}
				if mayDeclareTypeModulesReadingModuleInfoNeed {
					walkedFiles.skippedFilePathsThatMayDeclareTypesModulesReadingModuleInfoNeed.insert(file.path)
				}
			}
		}
		return walkedFiles
	}
}

/// What `walkFiles(named:conditionalCompilation:findingDeclarationsModulesReadingModuleInfoNeed:)` found in one file.
private enum WalkedSwiftFile: Sendable {
	/// The file mentions SafeDI, and contributes this.
	case scanned(FileScan)
	/// The file mentions no SafeDI marker, and may declare types of these names, and one a module reading the module's
	/// info needs.
	case skipped(mayDeclareTypesNamed: Set<String>, mayDeclareTypeModulesReadingModuleInfoNeed: Bool)
}

/// What each file at `filePaths` contributes: files `walkFiles(named:conditionalCompilation:findingDeclarationsModulesReadingModuleInfoNeed:)`
/// did not parse, since their text mentions no SafeDI marker, but whose text may declare a type whose plain declaration
/// SafeDI reads.
/// Each contributes its declarations of types that are not `@Instantiable` (`FileVisitor.plainTypeDeclarations`) in the
/// clauses the conditions select, with the conditions and decisions that selected them. Nothing else is taken from such a
/// file, not even its syntax errors, as SafeDI otherwise reads nothing of it.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkFilesDeclaringTypes(
	among filePaths: [String],
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await withThrowingTaskGroup(
		of: FileScan.self,
		returning: [FileScan].self,
	) { taskGroup in
		for filePath in filePaths {
			taskGroup.addTask {
				let syntaxTree = try Parser.parse(source: String(contentsOfFile: filePath, encoding: .utf8))
				let fileVisitor = FileVisitor(
					conditionalCompilationEvaluator: evaluator,
					sourceLocationConverter: SourceLocationConverter(fileName: filePath, tree: syntaxTree),
				)
				fileVisitor.walk(syntaxTree)
				return FileScan(
					path: filePath,
					imports: [],
					mockImports: [],
					instantiables: [],
					configurations: [],
					encounteredUnexpectedNodes: false,
					conditionalCompilationDecisions: [],
					consultedCompilationConditions: fileVisitor.consultedCompilationConditions,
					importSegments: [],
					importOnlyConsultedCompilationConditions: [],
					outputFileDeclarations: OutputFileDeclarations(),
					plainTypeDeclarations: fileVisitor.plainTypeDeclarations,
					plainTypeDeclarationDecisions: fileVisitor.plainTypeDeclarationDecisions,
					keptGuardedPlainTypeNames: [],
				)
				.relocated(to: filePath)
			}
		}

		var fileScans = [FileScan]()
		for try await fileScan in taskGroup {
			fileScans.append(fileScan)
		}
		return fileScans
	}
}

/// What reading a Swift file found.
private struct ReadSwiftFile {
	/// The file's syntax tree, when its text mentions a SafeDI marker, so it was parsed.
	let syntaxTree: SourceFileSyntax?
	/// When its text mentions no SafeDI marker, so it was not parsed, the names of the types it may declare: each name
	/// that follows `enum`, `struct`, `class`, `actor`, `protocol`, or `typealias` and whitespace in it
	/// (`TypeDeclarationWords.namesFollowingKeywords`), a superset of the names of the types it declares, which a parse
	/// decides exactly. A declaration with a comment between the keyword and the name is not found. Empty for a parsed
	/// file.
	let mayDeclareTypesNamed: Set<String>
	/// When its text mentions no SafeDI marker, and it was read for the declarations a module reading the module's info
	/// needs (`isKeptForModulesReadingModuleInfo(level:isNested:)`), whether it may declare one
	/// (`UnsafeBufferPointer<UInt8>.mayDeclareTypeModulesReadingModuleInfoNeed(holdingWords:)`). `false` otherwise.
	var mayDeclareTypeModulesReadingModuleInfoNeed = false
}

/// Reads the file at `filePath`, and parses it when its text shows it can declare something SafeDI scans for. When
/// `findingDeclarationsModulesReadingModuleInfoNeed`, a file it does not parse also records whether its text may declare
/// a type a module reading the module's info needs.
private func readSwiftFile(atPath filePath: String, findingDeclarationsModulesReadingModuleInfoNeed: Bool) throws -> ReadSwiftFile {
	var content = try String(contentsOfFile: filePath, encoding: .utf8)
	// Searching the bytes rather than the characters is many times faster, and finds the markers wherever a
	// character search does: no other sequence of characters is equivalent to these ASCII ones. It also finds a
	// marker whose last character a combining mark changes, which a character search does not.
	let mentionsSafeDI = content.withUTF8 { source in
		safeDIMarkers.contains(where: source.containsBytes(of:))
	}
	return if mentionsSafeDI {
		ReadSwiftFile(syntaxTree: Parser.parse(source: content), mayDeclareTypesNamed: [])
	} else {
		// A closure rather than a key path: SwiftFormat's `redundantFileprivate` rule does not see a key path's use, and
		// would make the property `private`.
		content.withUTF8 { source in
			let words = source.typeDeclarationWords
			return ReadSwiftFile(
				syntaxTree: nil,
				mayDeclareTypesNamed: words.namesFollowingKeywords,
				mayDeclareTypeModulesReadingModuleInfoNeed: findingDeclarationsModulesReadingModuleInfoNeed
					&& source.mayDeclareTypeModulesReadingModuleInfoNeed(holdingWords: words),
			)
		}
	}
}

/// The keywords that introduce a declaration of a type whose access SafeDI reads.
private let typeDeclarationKeywords = ["enum", "struct", "class", "actor", "protocol", "typealias"].map { Array($0.utf8) }

/// The access modifier with which only another module of the same package can name a declaration.
private let packageAccessModifier = Array("package".utf8)

/// What `UnsafeBufferPointer<UInt8>.typeDeclarationWords` found in a file's text.
struct TypeDeclarationWords {
	/// Each name that follows `enum`, `struct`, `class`, `actor`, `protocol`, or `typealias` and whitespace, the keyword a
	/// whole word too: a word, or a name in backticks without them, as a mention of the type spells it
	/// (`mentionedTypeNames(of:)`). A superset of the names of the types the text declares.
	var namesFollowingKeywords = Set<String>()
	/// Whether the text holds the word `package`, which every declaration only another module of the package can name
	/// holds – on itself, on a type enclosing it, or on the extension it is directly inside – wherever comments put it. A
	/// comment or a string literal can hold the word too, so this is `true` whenever the text declares such a type, a
	/// superset that a parse decides.
	var holdsPackageAccessModifier = false
}

extension UInt8 {
	/// Whether this byte can be part of an identifier: an ASCII letter, digit, or underscore, or a byte of a non-ASCII
	/// character.
	fileprivate var isIdentifierByte: Bool {
		switch self {
		case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), 0x80...:
			true
		default:
			false
		}
	}

	/// Whether this byte is ASCII whitespace.
	fileprivate var isWhitespaceByte: Bool {
		self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
	}

	/// Whether this byte ends a line of Swift source: a line feed or a carriage return.
	fileprivate var isLineBreakByte: Bool {
		self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
	}

	/// Whether this byte separates tokens in Swift source without being one: whitespace, a vertical tab, a form feed, or
	/// a null byte, which the compiler reads as whitespace.
	fileprivate var separatesTokens: Bool {
		isWhitespaceByte || self == 0x0B || self == 0x0C || self == 0x00
	}
}

/// The byte of a backtick, which encloses a name: 0x60.
private let backtickByte: UInt8 = 0x60

/// The bytes of a byte order mark, U+FEFF, in UTF-8.
private let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

/// The access modifiers with which every module can name a declaration: `public` and `open`.
private let accessModifiersEveryModuleCanName = ["public", "open"].map { Array($0.utf8) }

/// The keyword that introduces an extension.
private let extensionKeyword = Array("extension".utf8)

/// The keyword that introduces a class, and modifies a member a subclass can override.
private let classKeyword = Array("class".utf8)

/// The words after which `class` modifies a member rather than introducing a class: reserved words, which a class can be
/// named only in backticks.
private let membersClassModifies = ["func", "var", "let", "subscript"].map { Array($0.utf8) }

/// The conditional compilation directives that start, continue, and end an `#if` block, without their `#`.
private let conditionalCompilationBlockStart = Array("if".utf8)
private let conditionalCompilationClauseStarts = ["elseif", "else"].map { Array($0.utf8) }
private let conditionalCompilationBlockEnd = Array("endif".utf8)

/// Where a byte of Swift source is, as `UnsafeBufferPointer<UInt8>.mayDeclareNestedTypeEveryModuleCanName` reads it.
private enum NestedTypeSearchContext {
	/// Certainly code: no comment, string literal, or regex literal holds the byte.
	case code
	/// A comment that ends at the end of its line.
	case lineComment
	/// A comment that ends after as many `*/` as `nesting`: block comments nest.
	case blockComment(nesting: Int)
	/// A single-line string literal that is not raw, outside its interpolations.
	case string
	/// A multi-line string literal that is not raw, outside its interpolations.
	case multilineString
	/// Bytes whose context the search does not know, to the end of their line: a regex literal, a string interpolation,
	/// or what follows either can hold them. `mayContinuePastLine` is whether a delimiter that opens a region that can
	/// continue onto the next line – `"""`, `/*`, or `#/` – is among them.
	case unknownToEndOfLine(mayContinuePastLine: Bool)
	/// Bytes whose context the search does not know, to the end of the text.
	case unknownToEndOfText
}

/// What a word is to `UnsafeBufferPointer<UInt8>.mayDeclareNestedTypeEveryModuleCanName`.
private enum NestedTypeSearchWord {
	/// `public` or `open`.
	case accessModifierEveryModuleCanName
	/// `extension`.
	case extensionKeyword
	/// A keyword that introduces a type declaration whose access SafeDI reads (`typeDeclarationKeywords`).
	case typeDeclarationKeyword
	/// Any other word.
	case other
}

/// The text that every file declaring SafeDI content contains.
private let safeDIMarkers = [
	"@\(InstantiableVisitor.macroName)",
	"#\(SafeDIConfigurationVisitor.macroName)",
].map { Array($0.utf8) }

extension UnsafeBufferPointer<UInt8> {
	/// The words of these bytes, Swift source, that type declarations may begin with (`TypeDeclarationWords`): a word is
	/// a run of ASCII letters, digits, and underscores, and bytes of non-ASCII characters, the bytes an identifier is
	/// spelled with, and a name in backticks is what a backtick and the closing backtick on its line enclose, a space of a
	/// raw identifier included. A name in backticks is never a keyword: `` `class` `` introduces nothing. A backtick
	/// without a closing one on its line is an ordinary byte, so the words after it on its line are still read.
	var typeDeclarationWords: TypeDeclarationWords {
		var found = TypeDeclarationWords()
		// A byte order mark that starts the text is no part of the first word. Foundation removes it when reading a file
		// on Apple platforms; skipping it here keeps the search independent of whether every platform's does.
		var index = starts(with: byteOrderMark) ? startIndex + byteOrderMark.count : startIndex
		// Whether the last word introduces a type declaration, and only whitespace followed it since.
		var followsTypeKeyword = false
		while index < endIndex {
			if self[index].isIdentifierByte {
				let wordStart = index
				repeat {
					index += 1
				} while index < endIndex && self[index].isIdentifierByte
				let word = UnsafeBufferPointer(rebasing: self[wordStart..<index])
				if followsTypeKeyword {
					found.namesFollowingKeywords.insert(String(decoding: word, as: UTF8.self))
				}
				// Most words are not four to nine bytes long, which the comparisons need not see.
				followsTypeKeyword = (4...9).contains(word.count) && typeDeclarationKeywords.contains { $0.elementsEqual(word) }
				if word.count == packageAccessModifier.count, packageAccessModifier.elementsEqual(word) {
					found.holdsPackageAccessModifier = true
				}
			} else if self[index] == backtickByte, let nameEnd = closingBacktickIndexOnLine(ofBacktickAt: index) {
				if followsTypeKeyword {
					found.namesFollowingKeywords.insert(String(decoding: UnsafeBufferPointer(rebasing: self[(index + 1)..<nameEnd]), as: UTF8.self))
				}
				followsTypeKeyword = false
				index = nameEnd + 1
			} else {
				followsTypeKeyword = followsTypeKeyword && self[index].isWhitespaceByte
				index += 1
			}
		}
		return found
	}

	/// The index of the backtick that closes the one at `openingIndex` on the same line, or `nil` when the line has none:
	/// a name in backticks spans no line break and holds no backtick, so a backtick without a closing one on its line, as
	/// in a string literal holding one, encloses nothing.
	private func closingBacktickIndexOnLine(ofBacktickAt openingIndex: Int) -> Int? {
		var index = openingIndex + 1
		while index < endIndex, self[index] != UInt8(ascii: "\n") {
			if self[index] == backtickByte {
				return index
			} else {
				index += 1
			}
		}
		return nil
	}

	/// Whether these bytes, Swift source whose words are `words` (`typeDeclarationWords`), may declare a type a module
	/// reading the module's info needs (`isKeptForModulesReadingModuleInfo(level:isNested:)`): they hold the word
	/// `package`, or may declare a nested type that is `public` or `open` (`mayDeclareNestedTypeEveryModuleCanName`).
	func mayDeclareTypeModulesReadingModuleInfoNeed(holdingWords words: TypeDeclarationWords) -> Bool {
		words.holdsPackageAccessModifier || mayDeclareNestedTypeEveryModuleCanName
	}

	/// Whether these bytes, Swift source, may declare a type nested in another that is `public` or `open` by its own
	/// level: a type declaration keyword (`typeDeclarationKeywords`) inside braces that follows `public` or `open` with
	/// only other modifiers, whitespace, and comments between, or that follows a `public` or `open` extension anywhere
	/// before it. A superset, which a parse decides, of the texts that declare one, since such a declaration's keyword is
	/// inside the braces of the type or extension enclosing it, and its own modifier – or, when it spells none, that of
	/// the extension it is directly inside – is `public` or `open`. Attributes come before modifiers, so none is between.
	///
	/// The search reads comments and string literals, so that a brace or a word inside one counts for nothing, and the
	/// depth of braces it counts bounds the depth in code from above: every `{` that may be code opens a brace, and only
	/// a `}` that is certainly code closes one. Bytes it cannot place – after a `/` that may begin a regex literal, which
	/// cannot begin with whitespace, or in a string interpolation that holds more than names, numbers, and operators –
	/// may be code that closes no brace and ends no list of modifiers, to the end of their line, which no regex literal
	/// without `#` and no interpolation of a single-line string literal continues past. When the line may open a region
	/// that does (`"""`, `/*`, or `#/`), or the text holds a raw string literal or an extended regex literal, that
	/// is so to the end of the text.
	var mayDeclareNestedTypeEveryModuleCanName: Bool {
		var context = NestedTypeSearchContext.code
		// The upper bound of the depth of braces in code.
		var braceDepthBound = 0
		// The bound at the start of each `#if` block the search is in. Each clause of a block the compiler parses holds as
		// many `}` as `{` in code, and starts at the depth of the block. A clause it does not parse, such as one
		// `#if compiler(>=99)` guards, need not, so no `}` lowers the bound below the block's, and each clause restores it.
		var braceDepthBoundsAtConditionalCompilationBlocks = [Int]()
		// Whether `public` or `open` came after the last byte in code that ends a list of modifiers.
		var followsAccessModifierEveryModuleCanName = false
		// Whether a `public` or `open` extension came before: a member of it that spells no access is `public`.
		var followsExtensionEveryModuleCanName = false
		/// Reads `word`, which `isCertainlyCode` when the search knows its context, and returns whether it may introduce a
		/// nested type declaration that is `public` or `open`.
		func mayIntroduceNestedTypeEveryModuleCanName(_ word: NestedTypeSearchWord, isCertainlyCode: Bool) -> Bool {
			switch word {
			case .accessModifierEveryModuleCanName:
				followsAccessModifierEveryModuleCanName = true
				return false
			case .extensionKeyword:
				followsExtensionEveryModuleCanName = followsExtensionEveryModuleCanName || followsAccessModifierEveryModuleCanName
				// A keyword in code ends the list of modifiers before it.
				followsAccessModifierEveryModuleCanName = followsAccessModifierEveryModuleCanName && !isCertainlyCode
				return false
			case .typeDeclarationKeyword:
				let mayIntroduce = braceDepthBound > 0 && (followsAccessModifierEveryModuleCanName || followsExtensionEveryModuleCanName)
				followsAccessModifierEveryModuleCanName = followsAccessModifierEveryModuleCanName && !isCertainlyCode
				return mayIntroduce
			case .other:
				return false
			}
		}

		var index = starts(with: byteOrderMark) ? startIndex + byteOrderMark.count : startIndex
		while index < endIndex {
			let byte = self[index]
			switch context {
			case .code:
				if byte.isIdentifierByte {
					let wordEnd = endOfWord(startingAt: index)
					guard !mayIntroduceNestedTypeEveryModuleCanName(nestedTypeSearchWord(from: index, to: wordEnd), isCertainlyCode: true) else {
						return true
					}
					index = wordEnd
				} else if byte == UInt8(ascii: "{") {
					braceDepthBound += 1
					followsAccessModifierEveryModuleCanName = false
					index += 1
				} else if byte == UInt8(ascii: "}") {
					braceDepthBound = Swift.max(braceDepthBound - 1, braceDepthBoundsAtConditionalCompilationBlocks.last ?? 0)
					followsAccessModifierEveryModuleCanName = false
					index += 1
				} else if byte == UInt8(ascii: "/") {
					let nextByte = index + 1 < endIndex ? self[index + 1] : nil
					if nextByte == UInt8(ascii: "/") {
						context = .lineComment
						index += 2
					} else if nextByte == UInt8(ascii: "*") {
						context = .blockComment(nesting: 1)
						index += 2
					} else if nextByte?.isWhitespaceByte ?? true {
						// An operator: a regex literal cannot begin with whitespace.
						followsAccessModifierEveryModuleCanName = false
						index += 1
					} else {
						context = .unknownToEndOfLine(mayContinuePastLine: false)
						index += 1
					}
				} else if byte == UInt8(ascii: "\"") {
					let opensMultilineString = holdsMultilineStringDelimiter(at: index)
					context = opensMultilineString ? .multilineString : .string
					index += opensMultilineString ? 3 : 1
				} else if byte == UInt8(ascii: "#") {
					let directiveStart = index + 1
					if directiveStart < endIndex, [UInt8(ascii: "#"), UInt8(ascii: "\""), UInt8(ascii: "/")].contains(self[directiveStart]) {
						// A raw string literal or an extended regex literal, either of which can span lines.
						context = .unknownToEndOfText
						index += 1
					} else {
						let directiveEnd = endOfWord(startingAt: directiveStart)
						let directive = UnsafeBufferPointer(rebasing: self[directiveStart..<directiveEnd])
						if conditionalCompilationBlockStart.elementsEqual(directive) {
							braceDepthBoundsAtConditionalCompilationBlocks.append(braceDepthBound)
						} else if conditionalCompilationClauseStarts.contains(where: { $0.elementsEqual(directive) }) {
							braceDepthBound = Swift.max(braceDepthBound, braceDepthBoundsAtConditionalCompilationBlocks.last ?? 0)
						} else if conditionalCompilationBlockEnd.elementsEqual(directive) {
							braceDepthBound = Swift.max(braceDepthBound, braceDepthBoundsAtConditionalCompilationBlocks.popLast() ?? 0)
						}
						index = directiveEnd
					}
				} else if byte == backtickByte {
					// A name in backticks introduces nothing; a backtick without a closing one on its line encloses nothing.
					index = closingBacktickIndexOnLine(ofBacktickAt: index).map { $0 + 1 } ?? index + 1
				} else {
					// Only whitespace, and the parentheses of a modifier's argument, can be between two modifiers.
					if !byte.separatesTokens, byte != UInt8(ascii: "("), byte != UInt8(ascii: ")") {
						followsAccessModifierEveryModuleCanName = false
					}
					index += 1
				}
			case .lineComment:
				if byte.isLineBreakByte {
					context = .code
				}
				index += 1
			case let .blockComment(nesting):
				let nextByte = index + 1 < endIndex ? self[index + 1] : nil
				if byte == UInt8(ascii: "/"), nextByte == UInt8(ascii: "*") {
					context = .blockComment(nesting: nesting + 1)
					index += 2
				} else if byte == UInt8(ascii: "*"), nextByte == UInt8(ascii: "/") {
					context = nesting > 1 ? .blockComment(nesting: nesting - 1) : .code
					index += 2
				} else {
					index += 1
				}
			case .string:
				if byte == UInt8(ascii: "\"") {
					context = .code
					index += 1
				} else if byte == UInt8(ascii: "\\"), index + 1 < endIndex, self[index + 1] == UInt8(ascii: "(") {
					if let interpolationEnd = endOfInterpolationOfNamesNumbersAndOperators(openingParenthesisAt: index + 1) {
						index = interpolationEnd + 1
					} else {
						context = .unknownToEndOfLine(mayContinuePastLine: false)
						index += 1
					}
				} else if byte == UInt8(ascii: "\\"), index + 1 < endIndex, !self[index + 1].isLineBreakByte {
					// An escaped character.
					index += 2
				} else if byte.isLineBreakByte || byte == UInt8(ascii: "\\") {
					// A single-line string literal ends on its line, so the text is not Swift the search can read.
					context = .unknownToEndOfText
					index += 1
				} else {
					index += 1
				}
			case .multilineString:
				if holdsMultilineStringDelimiter(at: index) {
					context = .code
					index += 3
				} else if byte == UInt8(ascii: "\\"), index + 1 < endIndex, self[index + 1] == UInt8(ascii: "(") {
					if let interpolationEnd = endOfInterpolationOfNamesNumbersAndOperators(openingParenthesisAt: index + 1) {
						index = interpolationEnd + 1
					} else {
						// An interpolation can hold a multi-line string literal of its own, whose delimiter would end this one.
						context = .unknownToEndOfText
						index += 1
					}
				} else if byte == UInt8(ascii: "\\") {
					// An escaped character, or a line break the backslash leaves out.
					index += 2
				} else {
					index += 1
				}
			case let .unknownToEndOfLine(mayContinuePastLine):
				if byte.isLineBreakByte {
					context = mayContinuePastLine ? .unknownToEndOfText : .code
					index += 1
				} else if byte.isIdentifierByte {
					let wordEnd = endOfWord(startingAt: index)
					guard !mayIntroduceNestedTypeEveryModuleCanName(nestedTypeSearchWord(from: index, to: wordEnd), isCertainlyCode: false) else {
						return true
					}
					index = wordEnd
				} else {
					braceDepthBound += byte == UInt8(ascii: "{") ? 1 : 0
					if opensRegionThatCanContinuePastLine(at: index) {
						context = .unknownToEndOfLine(mayContinuePastLine: true)
					}
					index += 1
				}
			case .unknownToEndOfText:
				if byte.isIdentifierByte {
					let wordEnd = endOfWord(startingAt: index)
					guard !mayIntroduceNestedTypeEveryModuleCanName(nestedTypeSearchWord(from: index, to: wordEnd), isCertainlyCode: false) else {
						return true
					}
					index = wordEnd
				} else {
					braceDepthBound += byte == UInt8(ascii: "{") ? 1 : 0
					index += 1
				}
			}
		}
		return false
	}

	/// The index after the word that starts at `wordStart`: the run of identifier bytes there.
	private func endOfWord(startingAt wordStart: Int) -> Int {
		var wordEnd = wordStart
		while wordEnd < endIndex, self[wordEnd].isIdentifierByte {
			wordEnd += 1
		}
		return wordEnd
	}

	/// What the word from `wordStart` to `wordEnd` is to `mayDeclareNestedTypeEveryModuleCanName`. `class` before `func`,
	/// `var`, `let`, or `subscript` and whitespace modifies a member, and introduces no type.
	private func nestedTypeSearchWord(from wordStart: Int, to wordEnd: Int) -> NestedTypeSearchWord {
		let word = UnsafeBufferPointer(rebasing: self[wordStart..<wordEnd])
		// Most words are not four to nine bytes long, which the comparisons need not see.
		return if !(4...9).contains(word.count) {
			.other
		} else if accessModifiersEveryModuleCanName.contains(where: { $0.elementsEqual(word) }) {
			.accessModifierEveryModuleCanName
		} else if extensionKeyword.elementsEqual(word) {
			.extensionKeyword
		} else if typeDeclarationKeywords.contains(where: { $0.elementsEqual(word) }),
		          !classKeyword.elementsEqual(word) || !isMemberClassModifies(followingWhitespaceAfter: wordEnd)
		{
			.typeDeclarationKeyword
		} else {
			.other
		}
	}

	/// Whether the word after `index` and the whitespace there is one `class` modifies (`membersClassModifies`).
	private func isMemberClassModifies(followingWhitespaceAfter index: Int) -> Bool {
		var wordStart = index
		while wordStart < endIndex, self[wordStart].isWhitespaceByte {
			wordStart += 1
		}
		let word = UnsafeBufferPointer(rebasing: self[wordStart..<endOfWord(startingAt: wordStart)])
		return membersClassModifies.contains { $0.elementsEqual(word) }
	}

	/// Whether the bytes at `index` are `"""`, which opens and closes a multi-line string literal.
	private func holdsMultilineStringDelimiter(at index: Int) -> Bool {
		index + 2 < endIndex
			&& self[index] == UInt8(ascii: "\"")
			&& self[index + 1] == UInt8(ascii: "\"")
			&& self[index + 2] == UInt8(ascii: "\"")
	}

	/// Whether the bytes at `index` open a region that can continue onto the next line, were they code: `"""`, a
	/// multi-line string literal, `/*`, a block comment, or `#/`, an extended regex literal.
	private func opensRegionThatCanContinuePastLine(at index: Int) -> Bool {
		guard index + 1 < endIndex else { return false }
		return holdsMultilineStringDelimiter(at: index)
			|| (self[index] == UInt8(ascii: "/") && self[index + 1] == UInt8(ascii: "*"))
			|| (self[index] == UInt8(ascii: "#") && self[index + 1] == UInt8(ascii: "/"))
	}

	/// The index of the `)` that closes the string interpolation whose `(` is at `openingIndex`, when what the
	/// interpolation encloses holds only names, numbers, whitespace other than line breaks, and punctuation other than
	/// `"`, `/`, `#`, `\`, backticks, and braces – no string literal, comment, regex literal, raw identifier, or closure
	/// – so that its parentheses alone tell where it ends; `nil` otherwise.
	private func endOfInterpolationOfNamesNumbersAndOperators(openingParenthesisAt openingIndex: Int) -> Int? {
		var parenthesisDepth = 0
		var index = openingIndex
		while index < endIndex {
			let byte = self[index]
			if byte == UInt8(ascii: "(") {
				parenthesisDepth += 1
			} else if byte == UInt8(ascii: ")") {
				parenthesisDepth -= 1
				guard parenthesisDepth > 0 else { return index }
			} else if [UInt8(ascii: "\""), UInt8(ascii: "/"), UInt8(ascii: "#"), UInt8(ascii: "\\"), backtickByte, UInt8(ascii: "{"), UInt8(ascii: "}")].contains(byte) || byte.isLineBreakByte {
				return nil
			}
			index += 1
		}
		return nil
	}

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
private func walk(
	_ syntaxTree: SourceFileSyntax,
	at filePath: String,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
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
		encounteredUnexpectedNodes: fileVisitor.encounteredUnexpectedNodesSyntax,
		conditionalCompilationDecisions: fileVisitor.conditionalCompilationDecisions,
		consultedCompilationConditions: fileVisitor.consultedCompilationConditions,
		importSegments: fileVisitor.importOnlyConsultedCompilationConditions.isEmpty ? [] : fileVisitor.importSegments,
		importOnlyConsultedCompilationConditions: fileVisitor.importOnlyConsultedCompilationConditions,
		outputFileDeclarations: fileVisitor.outputFileDeclarations,
		plainTypeDeclarations: fileVisitor.plainTypeDeclarations,
		plainTypeDeclarationDecisions: fileVisitor.plainTypeDeclarationDecisions,
		keptGuardedPlainTypeNames: [],
	)
	.relocated(to: filePath)
	return fileScan.declaresSafeDIContent ? fileScan : fileScan.replacingImports(with: [], mockImports: [])
}
