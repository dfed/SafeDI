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
	) {
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
}

/// A module's parsed input files together with the configuration that governed the parse.
struct ParsedModule {
	let moduleInfo: ModuleInfo
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
/// - Parameters:
///   - filePaths: Every file to parse.
///   - configurationFilePaths: The files that belong to the module itself, which are the only ones whose
///     `#SafeDIConfiguration` applies. In a multi-module input set these are the current target's files.
///   - activeCompilationConditions: The conditions supplied on the command line and through the manifest.
/// - Returns: The module, and what each file contributed to it.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseModule(
	filePaths: Set<String>,
	configurationFilePaths: Set<String>,
	activeCompilationConditions: Set<String>,
) async throws -> (module: ParsedModule, fileScans: [FileScan]) {
	let defaultEvaluator = ConditionalCompilationEvaluator(activeCompilationConditions: activeCompilationConditions)

	let conventionalConfigurationFilePaths = filePaths.filter { filePath in
		configurationFilePaths.contains(filePath) && SafeDIConfiguration.isInConventionalFile(atPath: filePath)
	}
	let conventionalConfigurationFiles = try conventionalConfigurationFilePaths.sorted().compactMap { filePath in
		try parseFileDeclaringSafeDIContent(atPath: filePath).map { (path: filePath, syntaxTree: $0) }
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
	let fileScans = try await (firstPassEvaluator == defaultEvaluator
		? conventionalConfigurationFileScans
		: conventionalConfigurationFiles.map { file in
			walk(file.syntaxTree, at: file.path, conditionalCompilation: firstPassEvaluator)
		})
		+ walkFiles(named: filePaths.subtracting(conventionalConfigurationFilePaths), conditionalCompilation: firstPassEvaluator)

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
		: walkFiles(named: Set(fileScans.map(\.path)), conditionalCompilation: evaluator)
	return (
		ParsedModule(
			moduleInfo: ModuleInfo(finalFileScans),
			configuration: configuration,
			conditionalCompilationEvaluator: evaluator,
			additionalDirectories: configuration?.additionalDirectoriesToInclude.map(AdditionalDirectory.init(entry:)) ?? [],
		),
		finalFileScans,
	)
}

/// Parses files that belong to an already-configured module, such as those reached through
/// `#SafeDIConfiguration(additionalDirectoriesToInclude:)`, with the module's evaluator.
/// - Returns: What each file that mentions SafeDI contributes to the module.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFiles(
	_ filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await walkFiles(named: filePaths, conditionalCompilation: evaluator)
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
/// contributes.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkFiles(
	named filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await withThrowingTaskGroup(
		of: FileScan?.self,
		returning: [FileScan].self,
	) { taskGroup in
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				try parseFileDeclaringSafeDIContent(atPath: filePath).map { syntaxTree in
					walk(syntaxTree, at: filePath, conditionalCompilation: evaluator)
				}
			}
		}

		var fileScans = [FileScan]()
		for try await fileScan in taskGroup {
			if let fileScan {
				fileScans.append(fileScan)
			}
		}
		return fileScans
	}
}

/// Reads and parses the file at `filePath`, or returns `nil` without parsing when its text shows it
/// declares nothing SafeDI scans for.
private func parseFileDeclaringSafeDIContent(atPath filePath: String) throws -> SourceFileSyntax? {
	var content = try String(contentsOfFile: filePath, encoding: .utf8)
	// Searching the bytes rather than the characters is many times faster, and finds the markers wherever a
	// character search does: no other sequence of characters is equivalent to these ASCII ones. It also finds a
	// marker whose last character a combining mark changes, which a character search does not.
	let mentionsSafeDI = content.withUTF8 { source in
		safeDIMarkers.contains(where: source.containsBytes(of:))
	}
	return if mentionsSafeDI {
		Parser.parse(source: content)
	} else {
		nil
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
	)
	.relocated(to: filePath)
	return fileScan.declaresSafeDIContent ? fileScan : fileScan.replacingImports(with: [], mockImports: [])
}
