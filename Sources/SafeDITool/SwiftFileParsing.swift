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
	let imports: [ImportStatement]
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

/// The evaluator for a module's `#if` blocks.
///
/// - Parameters:
///   - activeCompilationConditions: The conditions supplied on the command line and through the manifest.
///   - configuration: The module's `#SafeDIConfiguration`, whose `activeCompilationConditions` are also active
///     and whose `mockConditionalCompilation` guards the generated mock code. A module without a configuration
///     wraps its mocks in `DEBUG`.
func conditionalCompilationEvaluator(
	activeCompilationConditions: Set<String>,
	configuration: SafeDIConfiguration?,
) -> ConditionalCompilationEvaluator {
	ConditionalCompilationEvaluator(
		activeCompilationConditions: activeCompilationConditions.union(configuration?.activeCompilationConditions ?? []),
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

/// Parses a module's input files, reading and parsing each file once.
///
/// The module's `#SafeDIConfiguration` decides how `#if` blocks are evaluated, so the files named
/// by `configurationFilePaths` are parsed first to find it, and every file is then scanned with the
/// resulting evaluator. A configuration file's syntax tree is kept for that scan rather than parsed again.
///
/// - Parameters:
///   - filePaths: Every file to parse.
///   - configurationFilePaths: The files that belong to the module itself, which are the only ones whose
///     `#SafeDIConfiguration` applies. In a multi-module input set these are the current target's files.
///   - activeCompilationConditions: The conditions supplied on the command line and through the manifest.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseModule(
	filePaths: Set<String>,
	configurationFilePaths: Set<String>,
	activeCompilationConditions: Set<String>,
) async throws -> ParsedModule {
	let relevantFiles = try await readRelevantFiles(filePaths)

	// Only the module's own files can declare its configuration, and the string check that gates
	// parsing already ran, so this parses at most the handful of files that mention the macro.
	var configurations = [SafeDIConfiguration]()
	var parsedConfigurationFiles = [String: SourceFileSyntax]()
	for file in relevantFiles where configurationFilePaths.contains(file.path) && file.containsConfiguration {
		let syntaxTree = Parser.parse(source: file.content)
		parsedConfigurationFiles[file.path] = syntaxTree
		let fileVisitor = FileVisitor(
			conditionalCompilationEvaluator: ConditionalCompilationEvaluator(activeCompilationConditions: activeCompilationConditions),
		)
		fileVisitor.walk(syntaxTree)
		configurations.append(contentsOf: fileVisitor.configurations.map {
			var configuration = $0
			configuration.sourceFilePath = file.path
			return configuration
		})
	}
	guard configurations.count <= 1 else {
		throw MultipleConfigurationsError(sourceFilePaths: configurations.compactMap(\.sourceFilePath).sorted())
	}
	let configuration = configurations.first
	let evaluator = conditionalCompilationEvaluator(
		activeCompilationConditions: activeCompilationConditions,
		configuration: configuration,
	)

	let moduleInfo = try await scan(
		relevantFiles.map { file in
			(path: file.path, content: file.content, syntaxTree: parsedConfigurationFiles[file.path])
		},
		conditionalCompilation: evaluator,
	)
	return ParsedModule(
		moduleInfo: moduleInfo,
		configuration: configuration,
		conditionalCompilationEvaluator: evaluator,
	)
}

/// Parses files that belong to an already-configured module, such as those reached through
/// `#SafeDIConfiguration(additionalDirectoriesToInclude:)`, with the module's evaluator.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFiles(
	_ filePaths: Set<String>,
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> ModuleInfo {
	try await scan(
		readRelevantFiles(filePaths).map { file in
			(path: file.path, content: file.content, syntaxTree: nil)
		},
		conditionalCompilation: evaluator,
	)
}

// MARK: - Private

private struct RelevantFile {
	let path: String
	let content: String
	/// Whether the content mentions `#SafeDIConfiguration`.
	let containsConfiguration: Bool
}

/// Reads every file and keeps the content of those that can contain SafeDI declarations.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func readRelevantFiles(_ filePaths: Set<String>) async throws -> [RelevantFile] {
	try await withThrowingTaskGroup(
		of: RelevantFile?.self,
		returning: [RelevantFile].self,
	) { taskGroup in
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				let content = try String(contentsOfFile: filePath, encoding: .utf8)
				let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
				let containsConfiguration = content.contains("#\(SafeDIConfigurationVisitor.macroName)")
				guard containsInstantiable || containsConfiguration else { return nil }
				return RelevantFile(path: filePath, content: content, containsConfiguration: containsConfiguration)
			}
		}

		var relevantFiles = [RelevantFile]()
		for try await relevantFile in taskGroup {
			if let relevantFile {
				relevantFiles.append(relevantFile)
			}
		}
		return relevantFiles
	}
}

/// Scans already-read files in parallel, parsing each unless its syntax tree is supplied.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func scan(
	_ files: [(path: String, content: String, syntaxTree: SourceFileSyntax?)],
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> ModuleInfo {
	try await withThrowingTaskGroup(
		of: (
			imports: [ImportStatement],
			instantiables: [Instantiable],
			configurations: [SafeDIConfiguration],
			encounteredUnexpectedNodeInFile: String?,
			conditionalCompilationDecisions: [ConditionalCompilationDecision],
		)?.self,
		returning: ModuleInfo.self,
	) { taskGroup in
		var imports = [ImportStatement]()
		var instantiables = [Instantiable]()
		var configurations = [SafeDIConfiguration]()
		var filesWithUnexpectedNodes = [String]()
		var conditionalCompilationDecisions = Set<ConditionalCompilationDecision>()
		for file in files {
			taskGroup.addTask {
				let syntaxTree = file.syntaxTree ?? Parser.parse(source: file.content)
				let fileVisitor = FileVisitor(
					conditionalCompilationEvaluator: evaluator,
					sourceLocationConverter: SourceLocationConverter(fileName: file.path, tree: syntaxTree),
				)
				fileVisitor.walk(syntaxTree)
				let declaresSafeDIContent = !fileVisitor.instantiables.isEmpty
					|| !fileVisitor.configurations.isEmpty
					|| fileVisitor.encounteredUnexpectedNodesSyntax
				guard declaresSafeDIContent || !fileVisitor.conditionalCompilationDecisions.isEmpty else { return nil }
				let instantiables = fileVisitor.instantiables.map {
					var instantiable = $0
					instantiable.sourceFilePath = file.path
					return instantiable
				}
				let configurations = fileVisitor.configurations.map {
					var configuration = $0
					configuration.sourceFilePath = file.path
					return configuration
				}
				return (
					// A file whose only SafeDI content was skipped contributes nothing to generated
					// code, so its imports stay out of the generated dependency tree.
					imports: declaresSafeDIContent ? fileVisitor.imports : [],
					instantiables: instantiables,
					configurations: configurations,
					encounteredUnexpectedNodeInFile: fileVisitor.encounteredUnexpectedNodesSyntax ? file.path : nil,
					conditionalCompilationDecisions: fileVisitor.conditionalCompilationDecisions,
				)
			}
		}

		for try await fileInfo in taskGroup {
			if let fileInfo {
				imports.append(contentsOf: fileInfo.imports)
				instantiables.append(contentsOf: fileInfo.instantiables)
				configurations.append(contentsOf: fileInfo.configurations)
				if let filePath = fileInfo.encounteredUnexpectedNodeInFile {
					filesWithUnexpectedNodes.append(filePath)
				}
				conditionalCompilationDecisions.formUnion(fileInfo.conditionalCompilationDecisions)
			}
		}

		return ModuleInfo(
			imports: imports,
			instantiables: instantiables.sortedByDeclaration(),
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.isEmpty ? nil : filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions.sorted(),
		)
	}
}
