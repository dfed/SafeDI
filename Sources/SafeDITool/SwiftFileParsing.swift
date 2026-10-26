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
import SwiftParser
import SwiftSyntax

struct ModuleInfo: Codable {
	/// The imports generated dependency-tree code needs.
	let imports: [ImportStatement]
	/// The imports generated mock code needs, found by evaluating each `#if` block that guards only imports
	/// as if the module's mock condition were active. A module that depends on this one generates mocks
	/// that reference this module's mock-only declarations, so it imports these into its own mocks.
	let mockImports: [ImportStatement]
	let instantiables: [Instantiable]
	let configurations: [SafeDIConfiguration]
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

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func findSwiftFiles(inDirectories directories: [String]) async throws -> Set<String> {
	try await withThrowingTaskGroup(
		of: [String].self,
		returning: Set<String>.self,
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
						$0.standardizedFileURL.relativePath
					} else {
						nil
					}
				}
			}
		}

		var swiftFiles = Set<String>()
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
		throw MultipleConfigurationsError(sourceFilePaths: configurations.compactMap(\.sourceFilePath).sorted())
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

/// Parses files again under the names an earlier parse gave them, so every location recorded in the
/// result reads as it did then.
/// - Parameter filePathsByName: The path each file is read from, keyed by the name it is parsed under.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFiles(
	readingFilePathsByName filePathsByName: [String: String],
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await walkFiles(readingFilePathsByName: filePathsByName, conditionalCompilation: evaluator)
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
			conditionalCompilationDecisions: Set(conditionalCompilationDecisions + additionalModuleInfo.conditionalCompilationDecisions).sorted(),
		)
	}

	/// This module, parsed from some of a module's files, with what the rest of its files contributed:
	/// the module `ModuleInfo(_:)` makes from every file's scan.
	func adding(_ fileScans: [FileScan]) -> ModuleInfo {
		let addedModuleInfo = ModuleInfo(fileScans)
		return ModuleInfo(
			imports: imports + addedModuleInfo.imports,
			mockImports: mockImports + addedModuleInfo.mockImports,
			// Each file's instantiables are all in one of the two lists, so sorting keeps each file's declaration order.
			instantiables: (instantiables + addedModuleInfo.instantiables).sortedByDeclaration(),
			configurations: configurations + addedModuleInfo.configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.map { $0 + (addedModuleInfo.filesWithUnexpectedNodes ?? []) } ?? addedModuleInfo.filesWithUnexpectedNodes,
			conditionalCompilationDecisions: Set(conditionalCompilationDecisions + addedModuleInfo.conditionalCompilationDecisions).sorted(),
		)
	}

	/// The module the files contributed to, with instantiables in declaration order.
	init(_ fileScans: [FileScan]) {
		var conditionalCompilationDecisions = Set<ConditionalCompilationDecision>()
		for fileScan in fileScans {
			conditionalCompilationDecisions.formUnion(fileScan.conditionalCompilationDecisions)
		}
		let filesWithUnexpectedNodes = fileScans.filter(\.encounteredUnexpectedNodes).map(\.path)
		self.init(
			imports: fileScans.flatMap(\.imports),
			mockImports: fileScans.flatMap(\.mockImports),
			instantiables: fileScans.flatMap(\.instantiables).sortedByDeclaration(),
			configurations: fileScans.flatMap(\.configurations),
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.isEmpty ? nil : filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions.sorted(),
		)
	}
}

/// Reads, parses, and walks every file in parallel, keeping what each file that mentions SafeDI contributes.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkFiles(
	named filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await walkFiles(
		readingFilePathsByName: Dictionary(uniqueKeysWithValues: filePaths.map { ($0, $0) }),
		conditionalCompilation: evaluator,
	)
}

/// Reads each file from its value, and parses and walks it in parallel under its key.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkFiles(
	readingFilePathsByName filePathsByName: [String: String],
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await withThrowingTaskGroup(
		of: FileScan?.self,
		returning: [FileScan].self,
	) { taskGroup in
		for (name, filePath) in filePathsByName where !name.isEmpty {
			taskGroup.addTask {
				try parseFileDeclaringSafeDIContent(atPath: filePath).map { syntaxTree in
					walk(syntaxTree, at: name, conditionalCompilation: evaluator)
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
	let content = try String(contentsOfFile: filePath, encoding: .utf8)
	let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
	let containsConfiguration = content.contains("#\(SafeDIConfigurationVisitor.macroName)")
	return if containsInstantiable || containsConfiguration {
		Parser.parse(source: content)
	} else {
		nil
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
	)
	.relocated(to: filePath)
	return fileScan.declaresSafeDIContent ? fileScan : fileScan.replacingImports(with: [], mockImports: [])
}
