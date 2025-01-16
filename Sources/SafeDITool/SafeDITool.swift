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
#if canImport(ZippyJSON)
    import ZippyJSON
#endif

@main
struct SafeDITool: AsyncParsableCommand, Sendable {
    // MARK: Arguments

    @Argument(help: "A path to a CSV file containing paths of Swift files to parse.") var swiftSourcesFilePath: String?

    @Option(parsing: .upToNextOption, help: "Directories containing Swift files to include, relative to the executing directory.") var include: [String] = []

    @Option(help: "A path to a CSV file comprising directories containing Swift files to include, relative to the executing directory.") var includeFilePath: String?

    @Option(parsing: .upToNextOption, help: "The names of modules to import in the generated dependency tree. This list is in addition to the import statements found in files that declare @Instantiable types.") var additionalImportedModules: [String] = []

    @Option(help: "A path to a CSV file comprising the names of modules to import in the generated dependency tree. This list is in addition to the import statements found in files that declare @Instantiable types.") var additionalImportedModulesFilePath: String?

    @Option(help: "The desired output location of a file a SafeDI representation of this module. Only include this option when running on a project‘s non-root module. Must have a `.safedi` suffix.") var moduleInfoOutput: String?

    @Option(help: "A path to a CSV file containing paths of SafeDI representations of other modules to parse.") var dependentModuleInfoFilePath: String?

    @Option(help: "The desired output location of the Swift dependency injection tree. Only include this option when running on a project‘s root module.") var dependencyTreeOutput: String?

    @Option(help: "The desired output location of the DOT file expressing the Swift dependency injection tree. Only include this option when running on a project‘s root module.") var dotFileOutput: String?

    // MARK: Internal

    func run() async throws {
        if swiftSourcesFilePath == nil, include.isEmpty, includeFilePath == nil {
            throw ValidationError("Must provide 'swift-sources-file-path', '--include', or '--include-file-path'.")
        }

        let (dependentModuleInfo, module) = try await (
            loadSafeDIModuleInfo(),
            parsedModule()
        )

        let unnormalizedInstantiables = dependentModuleInfo.flatMap(\.instantiables) + module.instantiables
        let instantiableTypes = Set(unnormalizedInstantiables.flatMap(\.instantiableTypes))
        let normalizedInstantiables = unnormalizedInstantiables.map { unnormalizedInstantiable in
            let unnormalizedToNormalizedTypeMap = unnormalizedInstantiable.dependencies.reduce(
                into: [TypeDescription: TypeDescription]()
            ) { partialResult, nextDependency in
                if let bestTypeDescription = TypeDescription.nestedOptions(
                    referencedType: nextDependency.property.typeDescription,
                    within: unnormalizedInstantiable.concreteInstantiable
                ).first(where: { instantiableTypes.contains($0) }) {
                    partialResult[nextDependency.property.typeDescription] = bestTypeDescription
                }
            }

            let normalizedDependencies = unnormalizedInstantiable.dependencies.map {
                if let bestTypeDescription = unnormalizedToNormalizedTypeMap[$0.property.typeDescription] {
                    Dependency(
                        property: $0.property.withUpdatedTypeDescription(bestTypeDescription),
                        source: $0.source
                    )
                } else {
                    // Default to what was in the code – we'll probably error later
                    $0
                }
            }
            let normalizedInitializer = unnormalizedInstantiable.initializer?.mapArguments {
                $0.withUpdatedTypeDescription(unnormalizedToNormalizedTypeMap[$0.typeDescription, default: $0.typeDescription])
            }
            let normalizedAdditionalInstantiables = unnormalizedInstantiable.instantiableTypes.dropFirst().map {
                if let enclosingType = unnormalizedInstantiable.concreteInstantiable.popNested,
                   let bestTypeDescription = TypeDescription.nestedOptions(
                       referencedType: $0,
                       within: enclosingType
                   ).first(where: { instantiableTypes.contains($0) })
                {
                    bestTypeDescription
                } else {
                    // Default to what was in the code – we'll probably error later
                    $0
                }
            }
            return Instantiable(
                instantiableType: unnormalizedInstantiable.concreteInstantiable,
                isRoot: unnormalizedInstantiable.isRoot,
                initializer: normalizedInitializer,
                additionalInstantiables: normalizedAdditionalInstantiables,
                dependencies: normalizedDependencies,
                declarationType: unnormalizedInstantiable.declarationType
            )
        }
        let generator = try DependencyTreeGenerator(
            importStatements: dependentModuleInfo.flatMap(\.imports) + allAdditionalImportedModules.map { ImportStatement(moduleName: $0) } + module.imports,
            typeDescriptionToFulfillingInstantiableMap: resolveSafeDIFulfilledTypes(
                instantiables: normalizedInstantiables
            )
        )
        async let generatedCode: String? = try dependencyTreeOutput != nil
            ? generator.generateCodeTree()
            : nil

        if let moduleInfoOutput {
            try JSONEncoder().encode(ModuleInfo(
                imports: module.imports,
                instantiables: module.instantiables
            )).write(toPath: moduleInfoOutput)
        }

        if let dependencyTreeOutput, let generatedCode = try await generatedCode {
            try generatedCode.write(toPath: dependencyTreeOutput)
        }

        if let dotFileOutput {
            let dotGraph = try await generator.generateDOTTree()
            try """
            graph SafeDI {
                ranksep=2
            \(dotGraph)
            }
            """.write(toPath: dotFileOutput)
        }
    }

    struct ModuleInfo: Codable, Sendable {
        let imports: [ImportStatement]
        let instantiables: [Instantiable]
    }

    // MARK: Private

    private func findSwiftFiles() async throws -> Set<String> {
        try await withThrowingTaskGroup(
            of: [String].self,
            returning: Set<String>.self
        ) { taskGroup in
            taskGroup.addTask {
                if let swiftSourcesFilePath {
                    try String(contentsOfFile: swiftSourcesFilePath, encoding: .utf8)
                        .components(separatedBy: CharacterSet(arrayLiteral: ","))
                        .removingEmpty()
                } else {
                    []
                }
            }
            let fileFinder = await fileFinder
            for included in try allDirectoriesToIncludes {
                taskGroup.addTask {
                    let includedURL = included.asFileURL
                    let includedFileEnumerator = fileFinder
                        .enumerator(
                            at: includedURL,
                            includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles],
                            errorHandler: nil
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

    private func parsedModule() async throws -> ParsedModule {
        try await withThrowingTaskGroup(
            of: (imports: [ImportStatement], instantiables: [Instantiable])?.self,
            returning: ParsedModule.self
        ) { taskGroup in
            var imports = [ImportStatement]()
            var instantiables = [Instantiable]()
            for filePath in try await findSwiftFiles() where !filePath.isEmpty {
                taskGroup.addTask {
                    let content = try String(contentsOfFile: filePath, encoding: .utf8)
                    guard content.contains("@\(InstantiableVisitor.macroName)") else { return nil }
                    let fileVisitor = FileVisitor()
                    fileVisitor.walk(Parser.parse(source: content))
                    guard !fileVisitor.instantiables.isEmpty else { return nil }
                    return (imports: fileVisitor.imports, instantiables: fileVisitor.instantiables)
                }
            }

            for try await fileInfo in taskGroup {
                if let fileInfo {
                    imports.append(contentsOf: fileInfo.imports)
                    instantiables.append(contentsOf: fileInfo.instantiables)
                }
            }

            return ParsedModule(
                imports: imports,
                instantiables: instantiables
            )
        }
    }

    private var allDirectoriesToIncludes: [String] {
        get throws {
            if let includeFilePath {
                try include + String(contentsOfFile: includeFilePath, encoding: .utf8)
                    .components(separatedBy: CharacterSet(arrayLiteral: ","))
                    .removingEmpty()
            } else {
                include
            }
        }
    }

    private var allAdditionalImportedModules: [String] {
        get throws {
            if let additionalImportedModulesFilePath {
                try additionalImportedModules + String(contentsOfFile: additionalImportedModulesFilePath, encoding: .utf8)
                    .components(separatedBy: CharacterSet(arrayLiteral: ","))
                    .removingEmpty()
            } else {
                additionalImportedModules
            }
        }
    }

    private var moduleInfoURLs: Set<URL> {
        get throws {
            if let dependentModuleInfoFilePath {
                try .init(
                    String(contentsOfFile: dependentModuleInfoFilePath, encoding: .utf8)
                        .components(separatedBy: CharacterSet(arrayLiteral: ","))
                        .removingEmpty()
                        .map(\.asFileURL)
                )
            } else {
                []
            }
        }
    }

    private func loadSafeDIModuleInfo() async throws -> [ModuleInfo] {
        try await withThrowingTaskGroup(
            of: ModuleInfo.self,
            returning: [ModuleInfo].self
        ) { taskGroup in
            let moduleInfoURLs = try moduleInfoURLs
            guard !moduleInfoURLs.isEmpty else { return [] }
            for moduleInfoURL in moduleInfoURLs {
                taskGroup.addTask {
                    #if canImport(ZippyJSON)
                        let decoder = ZippyJSONDecoder()
                    #else
                        let decoder = JSONDecoder()
                    #endif
                    return try decoder.decode(
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

    private func resolveSafeDIFulfilledTypes(instantiables: [Instantiable]) throws -> [TypeDescription: Instantiable] {
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

    private struct ParsedModule {
        let imports: [ImportStatement]
        let instantiables: [Instantiable]
    }

    private enum CollectInstantiablesError: Error, CustomStringConvertible {
        case foundDuplicateInstantiable(String)

        var description: String {
            switch self {
            case let .foundDuplicateInstantiable(duplicateInstantiable):
                "@\(InstantiableVisitor.macroName)-decorated types and extensions must have globally unique type names and fulfill globally unqiue types. Found multiple types or extensions fulfilling `\(duplicateInstantiable)`"
            }
        }
    }
}

extension Data {
    fileprivate func write(toPath filePath: String) throws {
        try write(to: filePath.asFileURL)
    }
}

extension String {
    fileprivate func write(toPath filePath: String) throws {
        try Data(utf8).write(toPath: filePath)
    }

    fileprivate var asFileURL: URL {
        #if os(Linux)
            return URL(fileURLWithPath: self)
        #else
            guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
                return URL(fileURLWithPath: self)
            }
            return URL(filePath: self)
        #endif
    }
}

protocol FileFinder: Sendable {
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions,
        errorHandler handler: ((URL, any Error) -> Bool)?
    ) -> FileManager.DirectoryEnumerator?
}

extension FileManager: FileFinder {}
extension FileManager: @retroactive @unchecked Sendable {
    // FileManager is thread safe:
    // https://developer.apple.com/documentation/foundation/nsfilemanager#1651181
}

@MainActor var fileFinder: FileFinder = FileManager.default
