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

/// Questions about the `@Instantiable` types in a set of modules. Each question is a subcommand, so that further
/// questions – the dependents of a type, the provider of a type in a root – join without changing this one.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct Query: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Answer a question about the `@Instantiable` types in a set of modules (beta).",
		subcommands: [QueryNeeds.self],
	)
}

/// Reports what `@Instantiable` types need, so that a project can be assembled from exactly the modules one type
/// needs: a focused app that builds the type, or its mock, with mock data.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct QueryNeeds: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "needs",
		abstract: "Report what types need: the modules whose declarations build each and its dependencies, the `@Forwarded` parameters it takes, the dependencies no `@Instantiable` declaration fulfills, and what its mock needs.",
		discussion: "Reads the modules named with `--include` and `--module-info` once, builds each type with every dependency it receives provided by an `@Instantiable` declaration, as its mock does, and reports the modules those declarations are in. It then reports the same for the type's mock: the `mock()` the project generates, the hand-written mock that stands in when the project generates none, or the `mock()` a `#SafeDIConfiguration` listing the type in `additionalMocksToGenerate` would generate. A project that depends on the reported modules alone builds the type, or its mock, from them. With `--json`, the report and any error are printed as JSON, in the format the manual documents. This command is in beta: its options, text, and JSON may change in any release, which the JSON's `formatVersion` of 0 says; 1 will be the first stable format.",
	)

	@Argument(help: "The names of `@Instantiable` types: each its own name, as `additionalMocksToGenerate` would list it, not a type it fulfills. The modules are read once for all of them.") var typeNames: [String]

	@Option(parsing: .upToNextOption, help: "Directories containing Swift files to include, relative to the executing directory, as `generate` takes them. Each directory is a module holding the Swift files found in it recursively, named after its last path component, or after as many trailing components as tell it apart from the other modules (`Home/Sources`); a Swift file named directly belongs to its directory's module. The files are read as `generate` reads a module's own files: the module's `#SafeDIConfiguration` applies to them, and its `additionalDirectoriesToInclude` is not followed, since every module is named here.") var include: [String] = []

	@Option(parsing: .upToNextOption, help: "`.safedi` module info files to include, relative to the executing directory, as `generate --module-info-output` writes them. Each file is a module holding the declarations its build read, named after the file without its `.safedi` extension and without a trailing `_safedi` (`App_safedi.safedi`, which the Bazel macro writes for a library named `App`, is the module `App`), or after as many trailing path components as tell it apart from the other modules. A file is read as `generate --dependent-module-info-file-path` reads one, with what its build read under that build's compilation conditions, so `--active-compilation-conditions` does not apply to it.") var moduleInfo: [String] = []

	@Option(parsing: .upToNextOption, help: "The compilation conditions that are active for the build, matching the compiler's -D flags. SafeDI declarations in `#if` blocks of the files under `--include` are read only when the block's condition evaluates to true.") var activeCompilationConditions: [String] = []

	@Flag(help: "Print the report, or the error, as JSON rather than as text.") var json = false

	func run() async throws {
		do {
			let report = try await query()
			if json {
				try print(report.json())
			} else {
				print(report.formatted)
			}
		} catch let error as any SourceLocatedError where !json {
			// Print located errors in the compiler's format, as `generate` does.
			FileHandle.standardError.write(Data("\(error.sourceDiagnostics.map(\.formatted).joined(separator: "\n"))\n".utf8))
			throw ExitCode.failure
		} catch where json {
			// A script reads the error from the same stream as the report, as data.
			try print(QueryErrorReport(error).json())
			throw ExitCode.failure
		}
	}

	/// Reads the modules and reports what each type needs.
	/// Throws errors as-is so tests can inspect them; `run()` formats them.
	func query() async throws -> QueryReport {
		let includedModules = IncludedModule.modules(including: include, moduleInfo: moduleInfo)
		guard !includedModules.isEmpty else {
			throw QueryError.noModuleIncluded
		}
		let activeCompilationConditions = Set(activeCompilationConditions)

		// Each module is read as `generate` reads it: a directory as a module's own files, with its own
		// configuration, and a module info file as a dependent module's.
		let parsedModules = try await withThrowingTaskGroup(
			of: ParsedQueryModule.self,
			returning: [ParsedQueryModule].self,
		) { taskGroup in
			for includedModule in includedModules {
				taskGroup.addTask {
					try await ParsedQueryModule(reading: includedModule, activeCompilationConditions: activeCompilationConditions)
				}
			}
			var parsedModules = [ParsedQueryModule]()
			for try await parsedModule in taskGroup {
				parsedModules.append(parsedModule)
			}
			// Modules are combined in name order, whatever order their reads finished in.
			return parsedModules.sorted { $0.includedModule.name < $1.includedModule.name }
		}

		// Every declaration the query reports was read from one of these files, under this spelling.
		var attributionsByFilePath = [String: FileAttribution]()
		for parsedModule in parsedModules {
			for (filePath, attribution) in parsedModule.fileAttributions {
				if let otherModuleName = attributionsByFilePath[filePath]?.moduleName {
					throw QueryError.fileInTwoModules(filePath: filePath, moduleNames: [otherModuleName, parsedModule.includedModule.name])
				} else {
					attributionsByFilePath[filePath] = attribution
				}
			}
		}
		let filesWithUnexpectedNodes = parsedModules.flatMap { $0.moduleInfo.filesWithUnexpectedNodes ?? [] }
		guard filesWithUnexpectedNodes.isEmpty else {
			throw QueryError.filesWithUnexpectedNodes(filesWithUnexpectedNodes)
		}

		let typeDescriptionToFulfillingInstantiableMap = try resolveSafeDIFulfilledTypes(
			instantiables: normalizingInstantiableTypes(of: parsedModules.flatMap(\.moduleInfo.instantiables)),
		)
		func generator(over typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]) -> DependencyTreeGenerator {
			DependencyTreeGenerator(
				importStatements: [],
				mockImportStatements: [],
				typeDescriptionToFulfillingInstantiableMap: typeDescriptionToFulfillingInstantiableMap,
				// No code is generated, so no alias declaration is referenced.
				aliasDeclarationReferences: AliasDeclarationReferences(
					declarationFilePaths: [],
					compilerFilePaths: nil,
					commentFilePath: { $0 },
				),
			)
		}
		let mockGenerator = generator(over: typeDescriptionToFulfillingInstantiableMap)
		// What a type needs in production is built from the declarations with every hand-written mock removed, and
		// without the declarations that exist only for mocks.
		let productionGenerator = generator(over: typeDescriptionToFulfillingInstantiableMap.compactMapValues { $0.mockOnly ? nil : $0.withoutHandWrittenMock })

		var typeReports = [TypeReport]()
		var reportedTypeNames = Set<String>()
		for typeName in typeNames where reportedTypeNames.insert(typeName).inserted {
			let declarationsOfType = typeDescriptionToFulfillingInstantiableMap.values.filter { $0.concreteInstantiable.asSource == typeName }
			// The modules that generate `mock()` for the type: the module of each declaration that sets
			// `generateMock: true`, and each module whose configuration lists the type.
			let generatingModuleNames = Set(
				declarationsOfType.filter(\.generateMock).map { FileAttribution.attribution(ofFileAt: $0.sourceFilePath, in: attributionsByFilePath).moduleName }
					+ parsedModules.filter { $0.configuration?.additionalMocksToGenerate.contains(typeName) == true }.map(\.includedModule.name),
			).sorted()
			// A mock root is built from the entry under the type's own key (`mockRootInstantiable`), so that entry's
			// hand-written mock is the one the root calls. A hand-written method named `mock` on another entry for the
			// type returns another type, which kept it off that entry, and collides with a generated `mock()`.
			let rootDeclaration = declarationsOfType.map(\.concreteInstantiable).min().flatMap { typeDescriptionToFulfillingInstantiableMap[$0] }
			let handWrittenMockName: String? = if rootDeclaration?.mockInitializer != nil {
				rootDeclaration?.customMockName ?? InstantiableVisitor.mockMethodName
			} else {
				nil
			}
			let hasHandWrittenMethodNamedMock = declarationsOfType.contains { $0.mockInitializer != nil && $0.customMockName == nil }
			// The mock reported, and its method: `nil` when SafeDI can build no mock for the type.
			let (mockKind, mockMethodName): (TypeReport.Mock.Kind?, String) = if !generatingModuleNames.isEmpty {
				(.generated, InstantiableVisitor.mockMethodName)
			} else if let handWrittenMockName {
				(.handWritten, handWrittenMockName)
			} else if hasHandWrittenMethodNamedMock {
				(nil, InstantiableVisitor.mockMethodName)
			} else {
				(.wouldBeGenerated, InstantiableVisitor.mockMethodName)
			}
			// A hand-written mock is the root's mock only when the project generates none; otherwise a method named
			// `mock` is rejected, as `generate` rejects it.
			let generatesMock = mockKind != .handWritten
			// What the type's mock needs, or would need: built from every declaration.
			let mockReport: TypeReport.MockReport
			if let mockKind {
				guard let mockRequirements = try await mockGenerator.requirements(forTypeNamed: typeName, generatesMock: generatesMock) else {
					let fulfilledBy = Set(typeDescriptionToFulfillingInstantiableMap.filter { $0.key.asSource == typeName }.map(\.value.concreteInstantiable.asSource)).sorted()
					throw QueryError.noInstantiableNamed(
						typeName,
						fulfilledBy: fulfilledBy,
						similarlyNamed: Self.similarlyNamedTypes(to: typeName, among: typeDescriptionToFulfillingInstantiableMap, excluding: fulfilledBy),
					)
				}
				mockReport = .mock(TypeReport.Mock(
					kind: mockKind,
					methodName: mockMethodName,
					generatedIn: mockKind == .generated ? generatingModuleNames : nil,
					requirements: mockRequirements,
					attributionsByFilePath: attributionsByFilePath,
				))
			} else {
				mockReport = .none(TypeReport.NoMock(
					reasonKind: .handWrittenMockNamedMockReturnsAnotherType,
					reason: "`\(typeName)` has no mock: no module generates `\(typeName).\(InstantiableVisitor.mockMethodName)()`, and a hand-written `\(typeName).\(InstantiableVisitor.mockMethodName)` that returns another type would collide with a generated one, so no #\(SafeDIConfigurationVisitor.macroName) can list `\(typeName)` in `additionalMocksToGenerate`.",
				))
			}
			guard let productionRequirements = try await productionGenerator.requirements(forTypeNamed: typeName, generatesMock: generatesMock) else {
				throw QueryError.onlyMockOnlyDeclarationNamed(typeName)
			}
			typeReports.append(TypeReport(productionRequirements, mockReport: mockReport, attributionsByFilePath: attributionsByFilePath))
		}
		return QueryReport(types: typeReports)
	}

	/// The names of the concrete types that contain `typeName` or that it contains, ignoring case – the likeliest
	/// misspellings – closest in length first, at most five, leaving out the `excluded` names.
	private static func similarlyNamedTypes(to typeName: String, among typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable], excluding excluded: [String]) -> [String] {
		let loweredTypeName = typeName.lowercased()
		return Array(
			Set(typeDescriptionToFulfillingInstantiableMap.values.map(\.concreteInstantiable.asSource))
				.subtracting(excluded)
				.filter { name in
					let loweredName = name.lowercased()
					return loweredName != loweredTypeName && (loweredName.contains(loweredTypeName) || loweredTypeName.contains(loweredName))
				}
				.sorted { (abs($0.count - typeName.count), $0) < (abs($1.count - typeName.count), $1) }
				.prefix(5),
		)
	}
}

/// A module named with `--include` or `--module-info`: what it is read from, and the arguments that name it.
struct IncludedModule: Equatable {
	/// The last component of the module's path, or as many of its trailing components as tell it apart from the
	/// other modules, joined by `/`. A directory's path is the directory; a module info file's is its directory and
	/// its file name without the `.safedi` extension and a trailing `_safedi`. A module info file whose path so
	/// reads the same as another module's is named by its file name as spelled.
	let name: String
	let source: Source
	/// The arguments that name the module, in the order they were given.
	let paths: [String]

	/// What a module is read from.
	enum Source: Hashable {
		/// The Swift files under a directory named with `--include`, or named directly: the directory, and the
		/// directory as the first of `paths` spelled it, under which the module's files are reported.
		case directory(NormalizedFilePath, spelling: String)
		/// A `.safedi` module info file named with `--module-info`.
		case moduleInfo(NormalizedFilePath)
	}

	/// The extension of a module info file.
	static let moduleInfoPathExtension = ".safedi"
	/// What the Bazel macro appends to a library's name to name the rule that writes its module info file, and so
	/// the file: a `safedi_swift_library` named `App` writes `App_safedi.safedi`.
	static let bazelModuleInfoNameSuffix = "_safedi"

	/// The modules the arguments name, ordered by name. Arguments naming one directory, or one file, are one module.
	static func modules(including directoryPaths: [String], moduleInfo moduleInfoPaths: [String]) -> [IncludedModule] {
		struct Entry {
			let source: Source
			var paths: [String]
			/// The components the module is named from, the last of which names the module on its own.
			let nameComponents: [String]
			/// The name that tells the module apart when every component of `nameComponents` is another module's.
			let fallbackName: String
		}
		var entries = [Entry]()
		var entryIndexesBySource = [Source: Int]()
		func add(_ path: String, source: Source, nameComponents: [String], fallbackName: String) {
			if let index = entryIndexesBySource[source] {
				entries[index].paths.append(path)
			} else {
				entryIndexesBySource[source] = entries.count
				entries.append(Entry(source: source, paths: [path], nameComponents: nameComponents, fallbackName: fallbackName))
			}
		}
		for path in directoryPaths {
			// `generate --include` reads a Swift file named directly, as it reads the files of a directory.
			let directorySpelling = path.hasSuffix(".swift") ? (path as NSString).deletingLastPathComponent : path
			let spelling = directorySpelling.isEmpty ? "." : directorySpelling
			let directory = NormalizedFilePath(spelling)
			let components = directory.path.split(separator: "/").map(String.init)
			add(path, source: .directory(directory, spelling: spelling), nameComponents: components, fallbackName: components.last ?? directory.path)
		}
		for path in moduleInfoPaths {
			let file = NormalizedFilePath(path)
			var components = file.path.split(separator: "/").map(String.init)
			let fileName = components.popLast() ?? file.path
			add(path, source: .moduleInfo(file), nameComponents: components + [Self.moduleName(ofModuleInfoFileNamed: fileName)], fallbackName: fileName)
		}
		// Two layouts need more than the last component: `Modules/Home/Sources` and `Modules/Settings/Sources`
		// are `Home/Sources` and `Settings/Sources`. Distinct paths differ in some component, except a directory and
		// a module info file that read alike (`Home` and `Home.safedi`), which the file's name as spelled tells apart.
		func name(of components: [String], length: Int) -> String {
			components.suffix(length).joined(separator: "/")
		}
		let longestNameComponentCount = entries.map(\.nameComponents.count).max() ?? 0
		return entries
			.map { entry in
				var length = 1
				while length < longestNameComponentCount,
				      entries.filter({ name(of: $0.nameComponents, length: length) == name(of: entry.nameComponents, length: length) }).count > 1
				{
					length += 1
				}
				let isNamedApart = entries.filter { name(of: $0.nameComponents, length: length) == name(of: entry.nameComponents, length: length) }.count == 1
				return IncludedModule(
					name: isNamedApart ? name(of: entry.nameComponents, length: length) : entry.fallbackName,
					source: entry.source,
					paths: entry.paths,
				)
			}
			.sorted { $0.name < $1.name }
	}

	/// The module a module info file is named for: the file name without its `.safedi` extension, and without the
	/// `_safedi` the Bazel macro appends. A file named by either alone keeps its name.
	static func moduleName(ofModuleInfoFileNamed fileName: String) -> String {
		var name = fileName
		if name.hasSuffix(moduleInfoPathExtension), name.count > moduleInfoPathExtension.count {
			name.removeLast(moduleInfoPathExtension.count)
		}
		if name.hasSuffix(bazelModuleInfoNameSuffix), name.count > bazelModuleInfoNameSuffix.count {
			name.removeLast(bazelModuleInfoNameSuffix.count)
		}
		return name
	}
}

/// A module `QueryNeeds` read.
private struct ParsedQueryModule {
	/// Reads the module as `generate` reads it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	init(reading includedModule: IncludedModule, activeCompilationConditions: Set<String>) async throws {
		self.includedModule = includedModule
		switch includedModule.source {
		case let .directory(directory, spelling):
			let filePaths = try await findSwiftFiles(inDirectories: includedModule.paths)
			// A directory that holds no Swift file is most likely misspelled: one that does not exist enumerates as empty.
			guard !filePaths.isEmpty else {
				throw QueryError.moduleHasNoSwiftFiles(name: includedModule.name, paths: includedModule.paths)
			}
			let parsed = try await parseModule(
				filePaths: Set(filePaths.map(\.path)),
				configurationFilePaths: Set(filePaths.map(\.path)),
				activeCompilationConditions: activeCompilationConditions,
			)
			// Every file the directory holds belongs to the module, whose package the query does not know.
			moduleInfo = parsed.module.moduleInfo.declaringEveryInstantiable(in: DeclaringModule(moduleName: includedModule.name, packageName: nil))
			configuration = parsed.module.configuration
			// Each file is reported under the `--include` argument that named the module, as that argument was given.
			fileAttributions = filePaths.sorted().map { filePath in
				(
					filePath: filePath.path,
					attribution: FileAttribution(
						moduleName: includedModule.name,
						modulePaths: includedModule.paths,
						filePath: filePath.path(under: directory, spelled: spelling),
					),
				)
			}
		case .moduleInfo:
			let path = includedModule.paths[0]
			guard FileManager.default.fileExists(atPath: path) else {
				throw QueryError.moduleInfoNotReadable(path: path, reason: "No file exists at that path.")
			}
			// A file that cannot be opened reports the file system's error as `generate` does.
			let data = try Data(contentsOf: path.asFileURL)
			let readModuleInfo: ModuleInfo
			do {
				readModuleInfo = try ModuleInfo(moduleInfoData: data)
			} catch {
				throw QueryError.moduleInfoNotReadable(path: path, reason: "\(error) \(BinaryFile.unreadableFileExplanation)")
			}
			// Every declaration the file holds belongs to the module, named as the build that wrote the file named it, if
			// that build did. The query does not know the module's package.
			moduleInfo = readModuleInfo.declaringEveryInstantiable(in: DeclaringModule(moduleName: readModuleInfo.moduleName ?? includedModule.name, packageName: nil))
			// `parseModule` rejects a module with more than one configuration, so a module info file holds at most one.
			configuration = moduleInfo.configurations.first
			// A module info file names each file as the build that wrote it did, so the module's declarations are
			// attributed, and reported, by those names.
			fileAttributions = Set(moduleInfo.instantiables.flatMap { instantiable in
				[instantiable.sourceFilePath, instantiable.declarationLocation?.filePath, instantiable.mockDeclarationLocation?.filePath].compactMap(\.self)
			})
			.sorted()
			.map { filePath in
				(filePath: filePath, attribution: FileAttribution(moduleName: includedModule.name, modulePaths: includedModule.paths, filePath: filePath))
			}
		}
	}

	let includedModule: IncludedModule
	let moduleInfo: ModuleInfo
	let configuration: SafeDIConfiguration?
	/// The files whose declarations the module holds, each with how the report attributes it, sorted by path.
	let fileAttributions: [(filePath: String, attribution: FileAttribution)]
}

/// The module a file the query read belongs to, and how the report spells the file.
struct FileAttribution {
	let moduleName: String
	/// The `--include` or `--module-info` arguments that name the module, as given.
	let modulePaths: [String]
	/// The file's path as the report spells it: under the `--include` argument that named its module, as that
	/// argument was given, or as the `--module-info` file that named its module records it.
	let filePath: String

	/// The attribution of the file, which is one of the files the query read: every declaration the query reports
	/// was read from a file of an included module, under the spelling `attributionsByFilePath` keys. `nil` and
	/// unknown paths are reported under a module of their own, since the model allows them.
	static func attribution(ofFileAt filePath: String?, in attributionsByFilePath: [String: FileAttribution]) -> FileAttribution {
		filePath.flatMap { attributionsByFilePath[$0] }
			?? FileAttribution(moduleName: "(outside the included modules)", modulePaths: [], filePath: filePath ?? "")
	}
}

enum QueryError: Error, CustomStringConvertible, Equatable {
	case noModuleIncluded
	case moduleHasNoSwiftFiles(name: String, paths: [String])
	/// The `--module-info` file at `path`, as given, could not be read, for `reason`.
	case moduleInfoNotReadable(path: String, reason: String)
	case fileInTwoModules(filePath: String, moduleNames: [String])
	case filesWithUnexpectedNodes([String])
	/// No declaration has the name. `fulfilledBy` holds the concrete types of the declarations that fulfill a type
	/// of that name, and `similarlyNamed` the concrete types named most like it, both sorted.
	case noInstantiableNamed(String, fulfilledBy: [String], similarlyNamed: [String])
	case onlyMockOnlyDeclarationNamed(String)

	var description: String {
		switch self {
		case .noModuleIncluded:
			"Name at least one module: a directory of Swift files with --include, or a `.safedi` module info file with --module-info."
		case let .moduleHasNoSwiftFiles(name, paths):
			"The module '\(name)' has no Swift files at \(paths.map { "'\($0)'" }.joined(separator: ", ")). Include a directory that holds the module's Swift files, or a Swift file; a `.safedi` module info file is named with --module-info."
		case let .moduleInfoNotReadable(path, reason):
			"Could not read the SafeDI module info file at '\(path)': \(reason)"
		case let .fileInTwoModules(filePath, moduleNames):
			"The file '\(filePath)' is in two modules: \(moduleNames.map { "'\($0)'" }.joined(separator: " and ")). A file belongs to one module, so include directories and module info files that do not overlap."
		case let .filesWithUnexpectedNodes(filePaths):
			"Compiler errors prevent SafeDI from reading these files:\n\t\(filePaths.joined(separator: "\n\t"))"
		case let .noInstantiableNamed(typeName, fulfilledBy, similarlyNamed):
			"No @\(InstantiableVisitor.macroName) declaration in the included modules declares a type named `\(typeName)`."
				+ (fulfilledBy.isEmpty ? "" : " \(Self.backticked(fulfilledBy)) \(fulfilledBy.count == 1 ? "fulfills" : "fulfill") `\(typeName)`: query \(fulfilledBy.count == 1 ? "that type" : "one of those types") instead.")
				+ (similarlyNamed.isEmpty ? "" : " Similarly named types: \(Self.backticked(similarlyNamed)).")
				+ " Name the type as `additionalMocksToGenerate` would: by its own name, not by a type it fulfills."
		case let .onlyMockOnlyDeclarationNamed(typeName):
			"`\(typeName)` is declared only with `mockOnly: true`, which builds nothing in production. Name a type that an @\(InstantiableVisitor.macroName) declaration without `mockOnly` declares."
		}
	}

	/// The error's kind as the JSON report names it.
	var kind: String {
		switch self {
		case .noModuleIncluded:
			"noModuleIncluded"
		case .moduleHasNoSwiftFiles:
			"moduleHasNoSwiftFiles"
		case .moduleInfoNotReadable:
			"moduleInfoNotReadable"
		case .fileInTwoModules:
			"fileInTwoModules"
		case .filesWithUnexpectedNodes:
			"filesWithUnexpectedNodes"
		case .noInstantiableNamed:
			"noInstantiableNamed"
		case .onlyMockOnlyDeclarationNamed:
			"onlyMockOnlyDeclarationNamed"
		}
	}

	private static func backticked(_ names: [String]) -> String {
		names.map { "`\($0)`" }.joined(separator: ", ")
	}
}

/// What `QueryNeeds` reports: one report per type named, in the order named.
struct QueryReport: Encodable, Equatable {
	/// The version of the JSON format, so that a script can refuse a shape it does not know. `0` while the command
	/// is in beta: the shape may change in any release without raising it. `1` is the first stable format, from which
	/// it is raised when a key is renamed, removed, or changes meaning, and not when a key is added.
	static let formatVersion = 0

	let types: [TypeReport]

	/// The report as text: each type's report, in the order named.
	var formatted: String {
		types.map(\.formatted).joined(separator: "\n\n")
	}

	/// The report as JSON, with its keys sorted. The format is documented in the manual.
	func json() throws -> String {
		try Self.json(of: self)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(Self.formatVersion, forKey: .formatVersion)
		try container.encode(types, forKey: .types)
	}

	/// `value` as JSON with its keys sorted, as every JSON the query prints is.
	static func json(of value: some Encodable) throws -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		return String(decoding: try encoder.encode(value), as: UTF8.self)
	}

	private enum CodingKeys: String, CodingKey {
		case formatVersion
		case types
	}
}

/// An error `QueryNeeds` prints as JSON, with the same version as a report, a `kind` a script can match, and what
/// the text report would have said.
struct QueryErrorReport: Encodable {
	init(_ error: any Error) {
		self.error = error
	}

	let error: any Error

	func json() throws -> String {
		try QueryReport.json(of: self)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(QueryReport.formatVersion, forKey: .formatVersion)
		var errorContainer = container.nestedContainer(keyedBy: ErrorCodingKeys.self, forKey: .error)
		if let queryError = error as? QueryError {
			try errorContainer.encode(queryError.kind, forKey: .kind)
			try errorContainer.encode(queryError.description, forKey: .message)
			switch queryError {
			case let .noInstantiableNamed(typeName, fulfilledBy, similarlyNamed):
				try errorContainer.encode(typeName, forKey: .typeName)
				try errorContainer.encode(fulfilledBy, forKey: .fulfilledBy)
				try errorContainer.encode(similarlyNamed, forKey: .similarlyNamed)
			case let .onlyMockOnlyDeclarationNamed(typeName):
				try errorContainer.encode(typeName, forKey: .typeName)
			case let .moduleHasNoSwiftFiles(_, paths):
				try errorContainer.encode(paths, forKey: .paths)
			case let .moduleInfoNotReadable(path, _):
				try errorContainer.encode([path], forKey: .paths)
			case let .fileInTwoModules(filePath, _):
				try errorContainer.encode([filePath], forKey: .paths)
			case let .filesWithUnexpectedNodes(filePaths):
				try errorContainer.encode(filePaths, forKey: .paths)
			case .noModuleIncluded:
				break
			}
		} else if let sourceLocatedError = error as? any SourceLocatedError {
			// What `generate` would print for the same declarations, each diagnostic with its location.
			try errorContainer.encode("diagnostics", forKey: .kind)
			try errorContainer.encode(sourceLocatedError.sourceDiagnostics.map(\.formatted).joined(separator: "\n"), forKey: .message)
			try errorContainer.encode(sourceLocatedError.sourceDiagnostics.map(Diagnostic.init), forKey: .diagnostics)
		} else {
			try errorContainer.encode("other", forKey: .kind)
			try errorContainer.encode("\(error)", forKey: .message)
		}
	}

	/// A located diagnostic, as `generate` prints it.
	struct Diagnostic: Encodable {
		init(_ diagnostic: SourceDiagnostic) {
			severity = diagnostic.severity.rawValue
			filePath = diagnostic.location?.filePath
			line = diagnostic.location?.line
			column = diagnostic.location?.column
			message = diagnostic.message
		}

		let severity: String
		let filePath: String?
		let line: Int?
		let column: Int?
		let message: String
	}

	private enum CodingKeys: String, CodingKey {
		case formatVersion
		case error
	}

	private enum ErrorCodingKeys: String, CodingKey {
		case kind
		case message
		case typeName
		case fulfilledBy
		case similarlyNamed
		case paths
		case diagnostics
	}
}

/// What one type needs, with each declaration attributed to the module that holds it, and what its mock needs.
struct TypeReport: Encodable, Equatable {
	// MARK: Initialization

	/// - Parameters:
	///   - requirements: What the type needs in production.
	///   - mockReport: What the type's mock needs, or why it has none.
	///   - attributionsByFilePath: The module and reported spelling of each file the query read.
	init(_ requirements: TypeRequirements, mockReport: MockReport, attributionsByFilePath: [String: FileAttribution]) {
		typeName = requirements.typeDescription.asSource
		modules = Module.modules(holding: requirements, attributionsByFilePath: attributionsByFilePath)
		// Production passes every forwarded value: a default on the initializer serves only mocks.
		forwardedParameters = requirements.forwardedParameters.map {
			ForwardedParameter(label: $0.label, type: $0.typeDescription.asFunctionParameter.asSource, defaultExpression: nil)
		}
		unfulfilledDependencies = requirements.requiredParameters.map(UnfulfilledDependency.init)
		self.mockReport = mockReport
	}

	// MARK: Internal

	/// The concrete type the report is about.
	let typeName: String
	/// The modules the type and its dependencies are built from in production, by name.
	let modules: [Module]
	/// The `@Forwarded` parameters of the type, in the order `mock()` declares them.
	let forwardedParameters: [ForwardedParameter]
	/// The dependencies of the type, and of the dependencies built beside it, that no `@Instantiable`
	/// declaration fulfills, which the project provides by hand.
	let unfulfilledDependencies: [UnfulfilledDependency]
	/// What the type's mock needs, or why it has none.
	let mockReport: MockReport

	/// What a type's mock needs, or why SafeDI can build no mock for it.
	enum MockReport: Equatable {
		/// What the mock needs: the `mock()` the project generates, the hand-written mock when the project
		/// generates none, or the `mock()` a `#SafeDIConfiguration` listing the type would generate.
		case mock(Mock)
		/// Why the type has no mock.
		case none(NoMock)
	}

	/// What a type's mock needs.
	struct Mock: Encodable, Equatable {
		init(kind: Kind, methodName: String, generatedIn: [String]?, requirements: TypeRequirements, attributionsByFilePath: [String: FileAttribution]) {
			self.kind = kind
			self.methodName = methodName
			self.generatedIn = generatedIn
			modules = Module.modules(holding: requirements, attributionsByFilePath: attributionsByFilePath)
			forwardedParameters = requirements.forwardedParameters.map {
				ForwardedParameter(label: $0.label, type: $0.typeDescription.asFunctionParameter.asSource, defaultExpression: $0.defaultExpression)
			}
			unfulfilledDependencies = requirements.requiredParameters.map(UnfulfilledDependency.init)
		}

		let kind: Kind
		/// The mock method's name: `mock` unless the hand-written mock is the type's mock.
		let methodName: String
		/// The modules that generate the mock, sorted: the module of each declaration that sets `generateMock: true`,
		/// and each module whose `#SafeDIConfiguration` lists the type. `nil` unless `kind` is `generated`.
		let generatedIn: [String]?
		/// The modules the mock is built from, by name.
		let modules: [Module]
		/// The `@Forwarded` parameters of the mock, in order, with the defaults the mock gives them.
		let forwardedParameters: [ForwardedParameter]
		/// The dependencies no `@Instantiable` declaration fulfills, which the mock takes as parameters, in order.
		let unfulfilledDependencies: [UnfulfilledDependency]

		enum Kind: String, Encodable {
			/// The project generates `mock()` for the type: a declaration sets `generateMock: true`, or a
			/// `#SafeDIConfiguration` lists the type in `additionalMocksToGenerate`.
			case generated
			/// The project generates no `mock()` for the type, and a hand-written mock stands in.
			case handWritten
			/// Nothing gives the type a mock; the report is for the `mock()` a `#SafeDIConfiguration` listing the
			/// type in `additionalMocksToGenerate` would generate.
			case wouldBeGenerated
		}
	}

	/// Why SafeDI can build no mock for a type.
	struct NoMock: Encodable, Equatable {
		let reasonKind: ReasonKind
		/// The reason as the text report states it.
		let reason: String

		enum ReasonKind: String, Encodable {
			/// A hand-written method named `mock` that returns another type is declared for the type, which keeps
			/// it off the type's own entry and would collide with a generated `mock()`.
			case handWrittenMockNamedMockReturnsAnotherType
		}
	}

	struct Module: Encodable, Equatable {
		let name: String
		/// The `--include` or `--module-info` arguments that name the module, as given.
		let paths: [String]
		let declarations: [Declaration]

		/// The modules `requirements`' declarations are in, by name, each with its declarations.
		fileprivate static func modules(holding requirements: TypeRequirements, attributionsByFilePath: [String: FileAttribution]) -> [Module] {
			func attribution(ofFileAt filePath: String?) -> FileAttribution {
				FileAttribution.attribution(ofFileAt: filePath, in: attributionsByFilePath)
			}
			var pathsByModuleName = [String: [String]]()
			var declarationsByModuleName = [String: [Declaration]]()
			func add(_ declaration: Declaration, to attribution: FileAttribution) {
				pathsByModuleName[attribution.moduleName] = attribution.modulePaths
				declarationsByModuleName[attribution.moduleName, default: []].append(declaration)
			}
			for declaration in requirements.declarations {
				let attribution = attribution(ofFileAt: declaration.sourceFilePath)
				add(Declaration(declaration, filePath: declaration.sourceFilePath.map { _ in attribution.filePath }), to: attribution)
			}
			// An erasure is built wherever any of its declarations is visible, so it costs a module only when
			// none of them is in a module already needed. Otherwise the first module by name is named, and the
			// rest are reported beside it.
			for erasure in requirements.erasures {
				let candidates = erasure.declarations.map { (attribution: attribution(ofFileAt: $0.sourceFilePath), declaration: $0) }
				if let chosen = candidates.first(where: { declarationsByModuleName[$0.attribution.moduleName] != nil })
					?? candidates.min(by: { $0.attribution.moduleName < $1.attribution.moduleName })
				{
					add(
						Declaration(
							kind: .erasure,
							typeName: chosen.declaration.declaringType.asSource,
							filePath: chosen.declaration.sourceFilePath.map { _ in chosen.attribution.filePath },
							methodName: nil,
							erasure: Declaration.Erasure(
								property: chosen.declaration.property.asSource,
								erasedTypeName: erasure.property.typeDescription.asSource,
								concreteTypeName: erasure.concreteType.asSource,
								alsoDeclaredInModules: Set(candidates.map(\.attribution.moduleName)).subtracting([chosen.attribution.moduleName]).sorted(),
							),
						),
						to: chosen.attribution,
					)
				}
			}
			return declarationsByModuleName
				.sorted { $0.key < $1.key }
				.map { Module(name: $0.key, paths: pathsByModuleName[$0.key, default: []], declarations: $0.value.sorted { $0.sortKey.lexicographicallyPrecedes($1.sortKey) }) }
		}
	}

	struct Declaration: Encodable, Equatable {
		let kind: Kind
		/// The type declared: the `@Instantiable` type, the type of the hand-written mock, or the type that
		/// declares the erasing property.
		let typeName: String
		/// The file that holds the declaration: under the `--include` argument that named its module, or as the
		/// `--module-info` file that named its module records it.
		let filePath: String?
		/// The hand-written mock's name.
		let methodName: String?
		let erasure: Erasure?

		enum Kind: String, Encodable {
			case instantiable
			case handWrittenMock
			case erasure

			/// The order in which a module lists declarations of one type: what builds it, then what it calls.
			var order: Int {
				switch self {
				case .instantiable:
					0
				case .handWrittenMock:
					1
				case .erasure:
					2
				}
			}
		}

		struct Erasure: Encodable, Equatable {
			/// The `@Instantiated(erasedToConcreteExistential: true)` property, as declared.
			let property: String
			/// The received type built by erasure.
			let erasedTypeName: String
			/// The concrete type built and erased.
			let concreteTypeName: String
			/// The other modules that declare the same erasure, any of which would do instead, sorted.
			let alsoDeclaredInModules: [String]
		}
	}

	struct ForwardedParameter: Encodable, Equatable {
		let label: String
		/// The parameter's type as `mock()` spells it.
		let type: String
		/// The parameter's default, or `nil` when the caller passes it.
		let defaultExpression: String?
	}

	/// A dependency no `@Instantiable` declaration fulfills, which a mock takes as a parameter.
	struct UnfulfilledDependency: Encodable, Equatable {
		let label: String
		/// The value's type as `mock()` spells it.
		let type: String
		let reasonKind: ReasonKind
		/// The reason as the text report states it.
		let reason: String

		enum ReasonKind: String, Encodable {
			case noInstantiableFulfillsType
			case typeHasForwardedProperties
			case erasedToMultipleConcreteTypes
		}
	}

	/// The report as text.
	var formatted: String {
		var lines = [String]()
		lines.append("`\(typeName)` is built from declarations in \(Self.formattedCount(of: modules)):")
		lines.append(contentsOf: Self.formattedModules(modules))
		lines.append("")
		lines.append("@\(Dependency.Source.forwardedRawValue) parameters of `\(typeName)`:")
		lines.append(contentsOf: Self.formattedList(forwardedParameters.map { "\($0.label): \($0.type)" }))
		lines.append("")
		lines.append("Dependencies of `\(typeName)` no @\(InstantiableVisitor.macroName) declaration fulfills:")
		lines.append(contentsOf: Self.formattedList(unfulfilledDependencies.flatMap { ["\($0.label): \($0.type)", "  \($0.reason)"] }))
		lines.append("")
		switch mockReport {
		case let .mock(mock):
			let mockName = "`\(typeName).\(mock.methodName)()`"
			let listing = "`\(typeName)` in `additionalMocksToGenerate`"
			let builtFromSameDeclarations = mock.modules == modules
			let builtFrom = builtFromSameDeclarations ? "the same declarations." : "declarations in \(Self.formattedCount(of: mock.modules)):"
			let generatedIn = mock.generatedIn ?? []
			switch mock.kind {
			case .generated:
				lines.append("\(mockName) is generated in \(generatedIn.joined(separator: " and ")) from \(builtFrom)")
			case .handWritten:
				lines.append("\(mockName) is a hand-written mock built from \(builtFrom)")
			case .wouldBeGenerated:
				lines.append("No module generates \(mockName); a #\(SafeDIConfigurationVisitor.macroName) that lists \(listing) would generate it from \(builtFrom)")
			}
			if !builtFromSameDeclarations {
				lines.append(contentsOf: Self.formattedModules(mock.modules))
			}
			// A project that leaves out every module that generates the mock generates it itself.
			if mock.kind == .generated, !generatedIn.contains(where: { name in mock.modules.contains { $0.name == name } }) {
				lines.append("")
				lines.append("A project without \(generatedIn.joined(separator: " or ")) generates \(mockName) by listing \(listing) of a #\(SafeDIConfigurationVisitor.macroName).")
			}
			lines.append("")
			lines.append("Required @\(Dependency.Source.forwardedRawValue) parameters of \(mockName):")
			lines.append(contentsOf: Self.formattedList(mock.forwardedParameters.filter { $0.defaultExpression == nil }.map { "\($0.label): \($0.type)" }))
			lines.append("")
			lines.append("Defaulted @\(Dependency.Source.forwardedRawValue) parameters of \(mockName):")
			lines.append(contentsOf: Self.formattedList(mock.forwardedParameters.compactMap { parameter in
				parameter.defaultExpression.map { "\(parameter.label): \(parameter.type) = \($0)" }
			}))
			lines.append("")
			lines.append("Required parameters of \(mockName) that no @\(InstantiableVisitor.macroName) declaration removes:")
			lines.append(contentsOf: Self.formattedList(mock.unfulfilledDependencies.flatMap { ["\($0.label): \($0.type)", "  \($0.reason)"] }))
		case let .none(noMock):
			lines.append(noMock.reason)
		}
		return lines.joined(separator: "\n")
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(typeName, forKey: .typeName)
		try container.encode(modules, forKey: .modules)
		try container.encode(forwardedParameters, forKey: .forwardedParameters)
		try container.encode(unfulfilledDependencies, forKey: .unfulfilledDependencies)
		switch mockReport {
		case let .mock(mock):
			try container.encode(mock, forKey: .mock)
		case let .none(noMock):
			try container.encode(noMock, forKey: .noMock)
		}
	}

	// MARK: Private

	private enum CodingKeys: String, CodingKey {
		case typeName
		case modules
		case forwardedParameters
		case unfulfilledDependencies
		case mock
		case noMock
	}

	private static func formattedCount(of modules: [Module]) -> String {
		"\(modules.count) module\(modules.count == 1 ? "" : "s")"
	}

	private static func formattedModules(_ modules: [Module]) -> [String] {
		modules.flatMap { module in
			["", module.name] + module.declarations.map { "  \($0.formatted)" }
		}
	}

	private static func formattedList(_ items: [String]) -> [String] {
		items.isEmpty ? ["  (none)"] : items.map { "  \($0)" }
	}
}

extension TypeReport.Declaration {
	fileprivate init(_ declaration: TypeRequirements.Declaration, filePath: String?) {
		switch declaration.kind {
		case .instantiable:
			self.init(kind: .instantiable, typeName: declaration.typeDescription.asSource, filePath: filePath, methodName: nil, erasure: nil)
		case let .handWrittenMock(methodName):
			self.init(kind: .handWrittenMock, typeName: declaration.typeDescription.asSource, filePath: filePath, methodName: methodName, erasure: nil)
		}
	}

	/// Orders a module's declarations by type, then by kind, then by what distinguishes two of one kind.
	fileprivate var sortKey: [String] {
		[typeName, String(kind.order), methodName ?? "", erasure?.property ?? ""]
	}

	/// The declaration as the report lists it, by what it carries: an erasure, a hand-written mock's name, or neither.
	fileprivate var formatted: String {
		if let erasure {
			"@\(Dependency.Source.instantiatedRawValue)(erasedToConcreteExistential: true) \(erasure.property) on \(typeName), which builds \(erasure.erasedTypeName) as \(erasure.concreteTypeName)"
				+ (erasure.alsoDeclaredInModules.isEmpty ? "" : "; also declared in \(erasure.alsoDeclaredInModules.joined(separator: ", "))")
		} else if let methodName {
			"hand-written mock \(typeName).\(methodName)"
		} else {
			"@\(InstantiableVisitor.macroName) \(typeName)"
		}
	}
}

extension TypeReport.UnfulfilledDependency {
	fileprivate init(_ requiredParameter: TypeRequirements.RequiredParameter) {
		self.init(
			label: requiredParameter.label,
			type: requiredParameter.typeSource,
			reasonKind: requiredParameter.reason.kind,
			reason: requiredParameter.reason.description,
		)
	}
}

extension TypeRequirements.RequiredParameter.Reason {
	/// The reason as the report states it.
	fileprivate var description: String {
		switch self {
		case let .noInstantiableFulfillsType(typeDescription):
			"No @\(InstantiableVisitor.macroName) declaration fulfills `\(typeDescription.asSource)`."
		case let .typeHasForwardedProperties(typeDescription, forwardedProperties):
			"`\(typeDescription.asSource)` declares @\(Dependency.Source.forwardedRawValue) properties (\(forwardedProperties.map { "`\($0.asSource)`" }.joined(separator: ", "))), so only an `Instantiator` handed their values can build it."
		case let .erasedToMultipleConcreteTypes(typeDescription, concreteTypes):
			"`\(typeDescription.asSource)` is erased from more than one concrete type (\(concreteTypes.map { "`\($0.asSource)`" }.joined(separator: ", "))), so nothing says which one to build."
		}
	}

	/// The reason's kind as the JSON report names it.
	fileprivate var kind: TypeReport.UnfulfilledDependency.ReasonKind {
		switch self {
		case .noInstantiableFulfillsType:
			.noInstantiableFulfillsType
		case .typeHasForwardedProperties:
			.typeHasForwardedProperties
		case .erasedToMultipleConcreteTypes:
			.erasedToMultipleConcreteTypes
		}
	}
}
