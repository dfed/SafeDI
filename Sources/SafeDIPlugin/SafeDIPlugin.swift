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

import ArgumentParser
import Foundation
import SafeDICore
import SwiftParser
import ZippyJSON

@main
struct SafeDIPlugin: AsyncParsableCommand {

    @Argument(help: "The swift files to parse")
    var swiftFilePaths: [String]

    @Option(help: "The desired output location of the <ModuleName>.safeDI file")
    var instantiablesOutput: String?

    @Option(parsing: .upToNextOption, help: "The <ModuleName>.safeDI files from dependent targets")
    var instantiablesPaths: [String] = []

    @Option(help: "The desired output location of the swift dependency injection tree")
    var dependencyTreeOutput: String?

    func run() async throws {
        let output = try await Self.run(
            swiftFileContent: try await loadSwiftFiles(),
            dependentModuleNames: Array(Set(instantiablesPaths.map { $0.asFileURL.deletingPathExtension().lastPathComponent })),
            dependentInstantiables: Self.findSafeDIFulfilledTypes(atInstantiablesPaths: instantiablesPaths),
            buildDependencyTreeOutput: dependencyTreeOutput != nil
        )

        if let instantiablesOutput {
            try Self.writeInstantiables(output.instantiables, toPath: instantiablesOutput)
        }

        if let dependencyTreeOutput, let generatedCode = output.dependencyTree {
            try generatedCode.write(toPath: dependencyTreeOutput)
        }
    }

    static func run(
        swiftFileContent: [String],
        dependentModuleNames: [String],
        dependentInstantiables: [[Instantiable]],
        buildDependencyTreeOutput: Bool
    ) async throws -> Output {
        let module = parsedModule(swiftFileContent)
        if !module.nestedInstantiableDecoratedTypeDescriptions.isEmpty {
            throw CollectInstantiablesError
                .foundNestedInstantiables(
                    module
                        .nestedInstantiableDecoratedTypeDescriptions
                        .map(\.asSource)
                        .sorted()
                )
        }

        let dependencyTree: String?
        if buildDependencyTreeOutput {
            dependencyTree = try await DependencyTreeGenerator(
                moduleNames: dependentModuleNames,
                typeDescriptionToFulfillingInstantiableMap: try resolveSafeDIFulfilledTypes(dependentInstantiables: dependentInstantiables + [module.instantiables])
            )
            .generate()
        } else {
            dependencyTree = nil
        }

        return Output(
            instantiables: module.instantiables,
            dependencyTree: dependencyTree
        )
    }

    struct Output {
        let instantiables: [Instantiable]
        let dependencyTree: String?
    }

    private func loadSwiftFiles() async throws -> [String] {
        try await withThrowingTaskGroup(
            of: String.self,
            returning: [String].self
        ) { taskGroup in
            for filePath in swiftFilePaths {
                taskGroup.addTask {
                    try String(contentsOfFile: filePath)
                }
            }
            var swiftFiles = [String]()
            for try await swiftFile in taskGroup {
                swiftFiles.append(swiftFile)
            }
            return swiftFiles
        }
    }

    private static func parsedModule(_ swiftFileContent: [String]) -> ParsedModule {
        let fileVisitor = FileVisitor()
        for swiftFileContent in swiftFileContent {
            fileVisitor.walk(Parser.parse(source: swiftFileContent))
        }
        return ParsedModule(
            instantiables: fileVisitor.instantiables,
            nestedInstantiableDecoratedTypeDescriptions: fileVisitor.nestedInstantiableDecoratedTypeDescriptions)
    }

    private static func writeInstantiables(_ instantiables: [Instantiable], toPath path: String) throws {
        try JSONEncoder().encode(instantiables).write(toPath: path)
    }

    private static func findSafeDIFulfilledTypes(atInstantiablesPaths instantiablesPaths: [String]) async throws -> [[Instantiable]] {
        try await withThrowingTaskGroup(
            of: [Instantiable].self,
            returning: [[Instantiable]].self
        ) { taskGroup in
            let decoder = ZippyJSONDecoder()
            let instantiablesURLs = instantiablesPaths.map(\.asFileURL)
            for instantiablesURL in instantiablesURLs {
                taskGroup.addTask {
                    if FileManager.default.fileExists(atPath: instantiablesURL.absoluteString) {
                        try decoder.decode([Instantiable].self, from: Data(contentsOf: instantiablesURL))
                    } else {
                        []
                    }
                }
            }
            var dependentInstantiables = [[Instantiable]]()
            for try await moduleInstantiables in taskGroup {
                dependentInstantiables.append(moduleInstantiables)
            }

            return dependentInstantiables
        }
    }

    private static func resolveSafeDIFulfilledTypes(dependentInstantiables: [[Instantiable]]) throws -> [TypeDescription: Instantiable] {
        var typeDescriptionToFulfillingInstantiableMap = [TypeDescription: Instantiable]()
        for moduleInstantiables in dependentInstantiables {
            for instantiable in moduleInstantiables {
                for instantiableType in instantiable.instantiableTypes {
                    if typeDescriptionToFulfillingInstantiableMap[instantiableType] != nil {
                        throw CollectInstantiablesError.foundDuplicateInstantiable(instantiableType.asSource)
                    }
                    typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
                }
            }
        }
        return typeDescriptionToFulfillingInstantiableMap
    }

    private struct ParsedModule {
        let instantiables: [Instantiable]
        let nestedInstantiableDecoratedTypeDescriptions: [TypeDescription]
    }

    private enum CollectInstantiablesError: Error, CustomStringConvertible {
        case foundNestedInstantiables([String])
        case foundDuplicateInstantiable(String)

        var description: String {
            switch self {
            case let .foundNestedInstantiables(nestedInstantiables):
                "@\(InstantiableVisitor.macroName) types must be top-level declarations. Found the following nested @\(InstantiableVisitor.macroName) types: \(nestedInstantiables.joined(separator: ", "))"
            case let .foundDuplicateInstantiable(duplicateInstantiable):
                "@\(InstantiableVisitor.macroName)-decorated types must have globally unique type names and fulfill globally unqiue types. Found multiple @\(InstantiableVisitor.macroName)-decorated types fulfilling `\(duplicateInstantiable)`"
            }
        }
    }
}

extension Data {
    fileprivate func write(toPath filePath: String) throws {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            try write(to: URL(filePath: filePath))
        } else {
            try write(to: URL(fileURLWithPath: filePath))
        }
    }
}

extension String {
    fileprivate func write(toPath filePath: String) throws {
        try Data(utf8).write(toPath: filePath)
    }

    fileprivate var asFileURL: URL {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            URL(filePath: self)
        } else {
            URL(fileURLWithPath: self)
        }
    }
}
