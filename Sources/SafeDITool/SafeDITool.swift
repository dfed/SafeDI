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
struct SafeDITool: AsyncParsableCommand {

    // MARK: Arguments

    @Argument(help: "The Swift files to parse.")
    var swiftFilePaths: [String] = []

    @Option(help: "A path to a file containing newline-separated Swift files to parse.")
    var swiftFilePathsFilePath: String?

    @Option(parsing: .upToNextOption, help: "The names of modules to import in the generated dependency tree. This list is in addition to the import statements found in files that declare @Instantiable types.")
    var additionalImportedModules: [String] = []

    @Option(help: "The desired output location of a file a SafeDI representation of this module. Only include this option when running on a project‘s non-root module")
    var moduleInfoOutput: String?

    @Option(parsing: .upToNextOption, help: "File paths to SafeDI representations of other modules. Only include this option when running on a project‘s root module.")
    var moduleInfoPaths: [String] = []

    @Option(help: "The desired output location of the Swift dependency injection tree. Only include this option when running on a project‘s root module.")
    var dependencyTreeOutput: String?

    // MARK: Internal

    @MainActor
    func run() async throws {
        async let dependentModuleInfo = try Self.findSafeDIModuleInfo(
            atModuleInfoURLs: moduleInfoPaths.map(\.asFileURL)
        )
        async let swiftFiles = try loadSwiftFiles()
        let output = try await Self.run(
            swiftFileContent: swiftFiles,
            dependentImportStatements: dependentModuleInfo.flatMap(\.imports)
            + additionalImportedModules.map { ImportStatement(moduleName: $0) },
            dependentInstantiables: dependentModuleInfo.flatMap(\.instantiables),
            buildDependencyTreeOutput: dependencyTreeOutput != nil
        )

        if let moduleInfoOutput {
            try JSONEncoder().encode(ModuleInfo(
                imports: output.imports,
                instantiables: output.instantiables
            )).write(toPath: moduleInfoOutput)
        }

        if let dependencyTreeOutput, let generatedCode = output.dependencyTree {
            try generatedCode.write(toPath: dependencyTreeOutput)
        }
    }

    @MainActor
    static func run(
        swiftFileContent: [String],
        dependentImportStatements: [ImportStatement],
        dependentInstantiables: [Instantiable],
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
                importStatements: dependentImportStatements + module.imports,
                typeDescriptionToFulfillingInstantiableMap: try resolveSafeDIFulfilledTypes(
                    instantiables: dependentInstantiables + module.instantiables
                )
            )
            .generate()
        } else {
            dependencyTree = nil
        }

        return Output(
            imports: module.imports,
            instantiables: module.instantiables,
            dependencyTree: dependencyTree
        )
    }

    struct Output {
        let imports: [ImportStatement]
        let instantiables: [Instantiable]
        let dependencyTree: String?
    }

    // MARK: Private

    private func loadSwiftFiles() async throws -> [String] {
        try await withThrowingTaskGroup(
            of: String.self,
            returning: [String].self
        ) { taskGroup in
            let swiftFilePaths: [String]
            if let swiftFilePathsFilePath {
                swiftFilePaths = try String(contentsOfFile: swiftFilePathsFilePath)
                    .components(separatedBy: .newlines)
                + self.swiftFilePaths
            } else {
                swiftFilePaths = self.swiftFilePaths
            }
            for filePath in swiftFilePaths {
                taskGroup.addTask {
                    let swiftFile = try String(contentsOfFile: filePath)
                    if swiftFile.contains("@\(InstantiableVisitor.macroName)") {
                        return swiftFile
                    } else {
                        // We don't care about this file.
                        return ""
                    }
                }
            }
            var swiftFiles = [String]()
            for try await swiftFile in taskGroup {
                if !swiftFile.isEmpty {
                    swiftFiles.append(swiftFile)
                }
            }
            return swiftFiles
        }
    }

    private static func parsedModule(_ swiftFileContent: [String]) -> ParsedModule {
        var imports = [ImportStatement]()
        var instantiables = [Instantiable]()
        var nestedInstantiableDecoratedTypeDescriptions = [TypeDescription]()
        for content in swiftFileContent {
            let fileVisitor = FileVisitor()
            fileVisitor.walk(Parser.parse(source: content))
            nestedInstantiableDecoratedTypeDescriptions.append(
                contentsOf: fileVisitor.nestedInstantiableDecoratedTypeDescriptions
            )
            if !fileVisitor.instantiables.isEmpty {
                imports.append(contentsOf: fileVisitor.imports)
                instantiables.append(contentsOf: fileVisitor.instantiables)
            }

        }

        return ParsedModule(
            imports: imports,
            instantiables: instantiables,
            nestedInstantiableDecoratedTypeDescriptions: nestedInstantiableDecoratedTypeDescriptions
        )
    }

    private static func findSafeDIModuleInfo(atModuleInfoURLs moduleInfoURLs: [URL]) async throws -> [ModuleInfo] {
        try await withThrowingTaskGroup(
            of: ModuleInfo.self,
            returning: [ModuleInfo].self
        ) { taskGroup in
            let decoder = ZippyJSONDecoder()
            for moduleInfoURL in moduleInfoURLs {
                taskGroup.addTask {
                    try decoder.decode(
                        ModuleInfo.self,
                        from: Data(contentsOf: moduleInfoURL)
                    )
                }
            }
            var allModuleInfo = [ModuleInfo]()
            for try await moduleInfo in taskGroup {
                allModuleInfo.append(moduleInfo)
            }

            return allModuleInfo
        }
    }

    private static func resolveSafeDIFulfilledTypes(instantiables: [Instantiable]) throws -> [TypeDescription: Instantiable] {
        var typeDescriptionToFulfillingInstantiableMap = [TypeDescription: Instantiable]()
        for instantiable in instantiables {
            for instantiableType in instantiable.instantiableTypes {
                if typeDescriptionToFulfillingInstantiableMap[instantiableType] != nil {
                    throw CollectInstantiablesError.foundDuplicateInstantiable(instantiableType.asSource)
                }
                typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
            }
        }
        return typeDescriptionToFulfillingInstantiableMap
    }

    private struct ModuleInfo: Codable {
        let imports: [ImportStatement]
        let instantiables: [Instantiable]
    }

    private struct ParsedModule {
        let imports: [ImportStatement]
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
                "@\(InstantiableVisitor.macroName)-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `\(duplicateInstantiable)`"
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
