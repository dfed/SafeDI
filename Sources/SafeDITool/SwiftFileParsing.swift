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

struct ModuleInfo: Codable {
	let imports: [ImportStatement]
	let instantiables: [Instantiable]
	let configurations: [SafeDIConfiguration]
	let filesWithUnexpectedNodes: [String]?
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
func parseSwiftFiles(_ filePaths: Set<String>) async throws -> ModuleInfo {
	try await withThrowingTaskGroup(
		of: (
			imports: [ImportStatement],
			instantiables: [Instantiable],
			configurations: [SafeDIConfiguration],
			encounteredUnexpectedNodeInFile: String?,
		)?.self,
		returning: ModuleInfo.self,
	) { taskGroup in
		var imports = [ImportStatement]()
		var instantiables = [Instantiable]()
		var configurations = [SafeDIConfiguration]()
		var filesWithUnexpectedNodes = [String]()
		for filePath in filePaths where !filePath.isEmpty {
			taskGroup.addTask {
				let content = try String(contentsOfFile: filePath, encoding: .utf8)
				let containsInstantiable = content.contains("@\(InstantiableVisitor.macroName)")
				let containsConfiguration = content.contains("#\(SafeDIConfigurationVisitor.macroName)")
				guard containsInstantiable || containsConfiguration else { return nil }
				let fileVisitor = FileVisitor()
				fileVisitor.walk(Parser.parse(source: content))
				guard !fileVisitor.instantiables.isEmpty
					|| !fileVisitor.configurations.isEmpty
					|| fileVisitor.encounteredUnexpectedNodesSyntax
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
			}
		}

		return ModuleInfo(
			imports: imports,
			instantiables: instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes.isEmpty ? nil : filesWithUnexpectedNodes,
		)
	}
}
