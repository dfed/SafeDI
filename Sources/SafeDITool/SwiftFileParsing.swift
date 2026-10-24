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

/// Parses a module's input files, parsing each file once.
///
/// The module's `#SafeDIConfiguration(mockConditionalCompilation:)` decides how `#if` blocks guarding
/// mock-only declarations are evaluated, and it is the only part of the module's evaluator not known up
/// front. Every file is read once up front. A file the mock condition cannot affect is parsed and walked
/// right away. Any other file waits for the module's evaluator and is read again then, unless it may
/// declare the module's configuration: finding a configuration does not depend on the mock condition,
/// because a configuration is production content whose `#if` blocks are evaluated with the supplied
/// conditions alone, so such a file is parsed up front and its syntax tree is kept for its one walk with
/// the module's evaluator. Every other syntax tree is released as soon as it is walked, so memory scales
/// with concurrency rather than module size.
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
	let earlyFileScans = try await scanFilesBeforeEvaluatorIsKnown(
		filePaths,
		configurationFilePaths: configurationFilePaths,
		activeCompilationConditions: activeCompilationConditions,
	)
	var completeFileScans = [FileScan]()
	var filePathsAwaitingEvaluator = Set<String>()
	var configurationSyntaxTrees = [String: SourceFileSyntax]()
	var configurations = [SafeDIConfiguration]()
	for earlyFileScan in earlyFileScans {
		switch earlyFileScan {
		case let .complete(fileScan):
			completeFileScans.append(fileScan)
			if configurationFilePaths.contains(fileScan.path) {
				configurations += fileScan.configurations
			}
		case let .awaitingEvaluator(filePath, configurationFile):
			filePathsAwaitingEvaluator.insert(filePath)
			if let configurationFile {
				configurationSyntaxTrees[filePath] = configurationFile.syntaxTree
				configurations += configurationFile.configurations
			}
		}
	}
	guard configurations.count <= 1 else {
		throw MultipleConfigurationsError(sourceFilePaths: configurations.compactMap(\.sourceFilePath).sorted())
	}
	let configuration = configurations.first
	let evaluator = conditionalCompilationEvaluator(
		activeCompilationConditions: activeCompilationConditions,
		configuration: configuration,
	)
	let evaluatedFileScans = try await walkFiles(
		filePathsAwaitingEvaluator,
		parsedSyntaxTrees: configurationSyntaxTrees,
		conditionalCompilation: evaluator,
	)

	return ParsedModule(
		moduleInfo: ModuleInfo(completeFileScans + evaluatedFileScans),
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
	try await ModuleInfo(walkFiles(filePaths, parsedSyntaxTrees: [:], conditionalCompilation: evaluator))
}

// MARK: - Private

/// What one file contributed to the module.
private struct FileScan: Sendable {
	let path: String
	let imports: [ImportStatement]
	let instantiables: [Instantiable]
	let configurations: [SafeDIConfiguration]
	let encounteredUnexpectedNodes: Bool
	let conditionalCompilationDecisions: [ConditionalCompilationDecision]

	/// Whether the file declares nothing SafeDI scans for and no `#if` block was decided for it.
	var contributesNothing: Bool {
		instantiables.isEmpty
			&& configurations.isEmpty
			&& !encounteredUnexpectedNodes
			&& conditionalCompilationDecisions.isEmpty
	}
}

extension ModuleInfo {
	fileprivate init(_ fileScans: [FileScan]) {
		var conditionalCompilationDecisions = Set<ConditionalCompilationDecision>()
		for fileScan in fileScans {
			conditionalCompilationDecisions.formUnion(fileScan.conditionalCompilationDecisions)
		}
		let filesWithUnexpectedNodes = fileScans.filter(\.encounteredUnexpectedNodes).map(\.path)
		self.init(
			imports: fileScans.flatMap(\.imports),
			instantiables: fileScans.flatMap(\.instantiables).sortedByDeclaration(),
			configurations: fileScans.flatMap(\.configurations),
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.isEmpty ? nil : filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions.sorted(),
		)
	}
}

/// What reading a file yields before the module's evaluator is known.
private enum EarlyFileScan: Sendable {
	/// The module's mock condition cannot affect the file, so it was walked with the supplied conditions alone.
	case complete(FileScan)
	/// The module's mock condition may decide one of the file's `#if` blocks, so it must be walked with the module's evaluator.
	/// - Parameter configurationFile: When the file may declare the module's configuration, its syntax tree
	///   and the configurations found in it.
	case awaitingEvaluator(filePath: String, configurationFile: (syntaxTree: SourceFileSyntax, configurations: [SafeDIConfiguration])?)
}

/// Reads every file in parallel, walking those whose content cannot depend on the module's evaluator and
/// finding the module's configuration among the rest.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func scanFilesBeforeEvaluatorIsKnown(
	_ filePaths: Set<String>,
	configurationFilePaths: Set<String>,
	activeCompilationConditions: Set<String>,
) async throws -> [EarlyFileScan] {
	// The module's evaluator differs from this one at most in its mock condition. A file the mock
	// condition cannot affect extracts the same content under both, and a configuration is production
	// content, which the mock condition never decides. So this evaluator serves both purposes here.
	let evaluator = ConditionalCompilationEvaluator(activeCompilationConditions: activeCompilationConditions)
	return try await withThrowingTaskGroup(
		of: EarlyFileScan?.self,
		returning: [EarlyFileScan].self,
	) { taskGroup in
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				let content = try String(contentsOfFile: filePath, encoding: .utf8)
				let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
				let containsConfiguration = content.contains("#\(SafeDIConfigurationVisitor.macroName)")
				guard containsInstantiable || containsConfiguration else { return nil }
				// The mock condition decides only `#if` blocks guarding mock-only declarations: `mockOnly`
				// types and `mock()` or `customMockName` methods, none of which can be written without
				// the text `mock` or `Mock`.
				let mayDependOnMockCondition = content.contains("#if")
					&& (content.contains("mock") || content.contains("Mock"))
				if !mayDependOnMockCondition {
					return .complete(walk(Parser.parse(source: content), at: filePath, conditionalCompilation: evaluator))
				} else if containsConfiguration, configurationFilePaths.contains(filePath) {
					let syntaxTree = Parser.parse(source: content)
					let configurations = walk(syntaxTree, at: filePath, conditionalCompilation: evaluator).configurations
					return .awaitingEvaluator(filePath: filePath, configurationFile: (syntaxTree: syntaxTree, configurations: configurations))
				} else {
					return .awaitingEvaluator(filePath: filePath, configurationFile: nil)
				}
			}
		}

		var earlyFileScans = [EarlyFileScan]()
		for try await earlyFileScan in taskGroup {
			if let earlyFileScan {
				earlyFileScans.append(earlyFileScan)
			}
		}
		return earlyFileScans
	}
}

/// Reads, parses, and walks every file in parallel, keeping what each contributes.
/// - Parameter parsedSyntaxTrees: Files already parsed, keyed by path, which are walked without being read again.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func walkFiles(
	_ filePaths: Set<String>,
	parsedSyntaxTrees: [String: SourceFileSyntax],
	conditionalCompilation evaluator: ConditionalCompilationEvaluator,
) async throws -> [FileScan] {
	try await withThrowingTaskGroup(
		of: FileScan?.self,
		returning: [FileScan].self,
	) { taskGroup in
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				let syntaxTree: SourceFileSyntax
				if let parsedSyntaxTree = parsedSyntaxTrees[filePath] {
					syntaxTree = parsedSyntaxTree
				} else {
					let content = try String(contentsOfFile: filePath, encoding: .utf8)
					let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
					let containsConfiguration = content.contains("#\(SafeDIConfigurationVisitor.macroName)")
					guard containsInstantiable || containsConfiguration else { return nil }
					syntaxTree = Parser.parse(source: content)
				}
				let fileScan = walk(syntaxTree, at: filePath, conditionalCompilation: evaluator)
				return fileScan.contributesNothing ? nil : fileScan
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
	let declaresSafeDIContent = !fileVisitor.instantiables.isEmpty
		|| !fileVisitor.configurations.isEmpty
		|| fileVisitor.encounteredUnexpectedNodesSyntax
	return FileScan(
		path: filePath,
		// A file whose only SafeDI content was skipped contributes nothing to generated
		// code, so its imports stay out of the generated dependency tree.
		imports: declaresSafeDIContent ? fileVisitor.imports : [],
		instantiables: fileVisitor.instantiables.map {
			var instantiable = $0
			instantiable.sourceFilePath = filePath
			return instantiable
		},
		configurations: fileVisitor.configurations.map {
			var configuration = $0
			configuration.sourceFilePath = filePath
			return configuration
		},
		encounteredUnexpectedNodes: fileVisitor.encounteredUnexpectedNodesSyntax,
		conditionalCompilationDecisions: fileVisitor.conditionalCompilationDecisions,
	)
}
