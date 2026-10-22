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

/// Parses only the files that can declare `#SafeDIConfiguration`, so a module's configuration is
/// known before its other files are parsed. Every clause of every `#if` block is scanned here, since
/// the conditions that decide which clause is active are not known until the configuration is.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func discoverConfigurations(in filePaths: Set<String>) async throws -> [SafeDIConfiguration] {
	try await withThrowingTaskGroup(
		of: [SafeDIConfiguration].self,
		returning: [SafeDIConfiguration].self,
	) { taskGroup in
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				let content = try String(contentsOfFile: filePath, encoding: .utf8)
				guard content.contains("#\(SafeDIConfigurationVisitor.macroName)") else { return [] }
				let fileVisitor = FileVisitor(conditionalCompilation: .scanAllClauses)
				fileVisitor.walk(Parser.parse(source: content))
				return fileVisitor.configurations.map {
					var configuration = $0
					configuration.sourceFilePath = filePath
					return configuration
				}
			}
		}

		var configurations = [SafeDIConfiguration]()
		for try await fileConfigurations in taskGroup {
			configurations.append(contentsOf: fileConfigurations)
		}
		return configurations
	}
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

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func parseSwiftFiles(
	_ filePaths: Set<String>,
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
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				let content = try String(contentsOfFile: filePath, encoding: .utf8)
				let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
				let containsConfiguration = content.contains("#\(SafeDIConfigurationVisitor.macroName)")
				guard containsInstantiable || containsConfiguration else { return nil }
				let syntaxTree = Parser.parse(source: content)
				let fileVisitor = FileVisitor(
					conditionalCompilation: .evaluate(evaluator),
					sourceLocationConverter: SourceLocationConverter(fileName: filePath, tree: syntaxTree),
				)
				fileVisitor.walk(syntaxTree)
				guard !fileVisitor.instantiables.isEmpty
					|| !fileVisitor.configurations.isEmpty
					|| fileVisitor.encounteredUnexpectedNodesSyntax
					|| !fileVisitor.conditionalCompilationDecisions.isEmpty
				else { return nil }
				let instantiables = fileVisitor.instantiables.map {
					var instantiable = $0
					instantiable.sourceFilePath = filePath
					return instantiable
				}
				let configurations = fileVisitor.configurations.map {
					var configuration = $0
					configuration.sourceFilePath = filePath
					return configuration
				}
				return (
					imports: fileVisitor.imports,
					instantiables: instantiables,
					configurations: configurations,
					encounteredUnexpectedNodeInFile: fileVisitor.encounteredUnexpectedNodesSyntax ? filePath : nil,
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
