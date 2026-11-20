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

/// Exports the `@Instantiable` declarations of a set of modules, and how SafeDI resolves the types they name, as one
/// JSON document, so that a tool or an agent can answer its own questions about the graph.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct QueryGraph: AsyncParsableCommand {
	public init() {}

	public static let configuration = CommandConfiguration(
		commandName: "graph",
		abstract: "Export every `@Instantiable` declaration, its dependencies, and the type that fulfills each type they name, as JSON (alpha).",
		discussion: "Reads the modules named with `--include` and `--module-info` once, as `query needs` reads them, and prints one JSON document: each production `@Instantiable` type with its module, file and line, each of its dependencies as an edge with its kind and the type that fulfills what it builds, and which type fulfills each type. Each type and edge appears once, however many trees reach it. The same inputs give the same bytes. When two declarations fulfill one type, the declarations are still exported, `resolved` is false, and the error is listed; the command still succeeds. This command is in alpha: its options and JSON may change in any release, which the JSON’s `formatVersion` of 0 says. SafeDI’s Documentation/QueryGraph.md documents the format.",
	)

	@Option(parsing: .upToNextOption, help: "Directories containing Swift files to include, as `query needs` takes them.") var include: [String] = []

	@Option(parsing: .upToNextOption, help: "`.safedi` module info files to include, as `query needs` takes them.") var moduleInfo: [String] = []

	@Option(parsing: .upToNextOption, help: "The compilation conditions that are active for the build, matching the compiler’s -D flags, as `query needs` takes them.") var activeCompilationConditions: [String] = []

	@Option(help: "A file to write the JSON to instead of printing it. The file is written only when its bytes would change, so that a build system or a file watcher sees a change only when the graph changed.") var output: String?

	public func run() async throws {
		do {
			let json = try await graph().json()
			if let output {
				let data = Data(json.utf8)
				let url = output.asFileURL
				if (try? Data(contentsOf: url)) != data {
					try data.write(to: url)
				}
			} else {
				print(json)
			}
		} catch {
			// A script reads the error from the same stream as the graph, as data.
			try print(QueryErrorReport(error).json())
			throw ExitCode.failure
		}
	}

	/// Reads the modules and exports their graph.
	/// Throws errors as-is so tests can inspect them; `run()` formats them.
	public func graph() async throws -> QueryGraphReport {
		let parsedModules = try await QueryNeeds.readIncludedModules(
			including: include,
			moduleInfo: moduleInfo,
			activeCompilationConditions: activeCompilationConditions,
		)
		let attributionsByFilePath = try QueryNeeds.attributionsByFilePath(of: parsedModules)
		let instantiables = normalizingInstantiableTypes(
			of: parsedModules.flatMap(\.moduleInfo.instantiables),
			plainTypeDeclarations: parsedModules.flatMap(\.moduleInfo.plainTypeDeclarations),
			// The query has no emitting module, and `--include` directories record no package.
			reach: .unknown,
		)
		// The declarations are exported whether or not they resolve, so that a graph mid-edit still answers questions.
		let resolvedMap: [TypeDescription: Instantiable]?
		let resolutionDiagnostics: [SourceDiagnostic]
		do {
			resolvedMap = try resolveSafeDIFulfilledTypes(instantiables: instantiables)
			resolutionDiagnostics = []
		} catch let error as any SourceLocatedError {
			resolvedMap = nil
			resolutionDiagnostics = error.sourceDiagnostics
		}
		return QueryGraphReport(
			moduleNames: parsedModules.map(\.includedModule.name),
			instantiables: instantiables,
			resolvedMap: resolvedMap,
			resolutionDiagnostics: resolutionDiagnostics,
			attributionsByFilePath: attributionsByFilePath,
		)
	}
}

/// What `QueryGraph` exports: the production declarations of the modules it read, their dependencies, and which type
/// fulfills each type, each once. The format is documented in `Documentation/QueryGraph.md`.
public struct QueryGraphReport: Encodable, Equatable, Sendable {
	init(
		moduleNames: [String],
		instantiables: [Instantiable],
		resolvedMap: [TypeDescription: Instantiable]?,
		resolutionDiagnostics: [SourceDiagnostic],
		attributionsByFilePath: [String: FileAttribution],
	) {
		modules = moduleNames
		resolved = resolvedMap != nil
		// Only production declarations: a `mockOnly` declaration describes a mock, which the graph leaves out.
		let productionInstantiables = instantiables.filter { !$0.mockOnly }
		let resolvedMap = resolvedMap?.filter { !$0.value.mockOnly }

		func id(of instantiable: Instantiable) -> String {
			Self.id(ofTypeSpelled: instantiable.concreteInstantiable.asSource, moduleName: instantiable.moduleName)
		}
		func fulfillingTypeID(of typeDescription: TypeDescription) -> String? {
			resolvedMap?[typeDescription].map(id(of:))
		}
		func attribution(of filePath: String?) -> String? {
			filePath.map { FileAttribution.attribution(ofFileAt: $0, in: attributionsByFilePath).filePath }
		}

		errors = resolutionDiagnostics.map { diagnostic in
			GraphError(message: diagnostic.message, filePath: attribution(of: diagnostic.location?.filePath), line: diagnostic.location?.line)
		}
		types = productionInstantiables.map { instantiable in
			GraphType(
				id: id(of: instantiable),
				name: instantiable.concreteInstantiable.asSource,
				module: instantiable.moduleName,
				filePath: attribution(of: instantiable.declarationLocation?.filePath ?? instantiable.sourceFilePath),
				line: instantiable.declarationLocation?.line,
				declarationKind: GraphType.DeclarationKind(instantiable.declarationType),
				fulfills: instantiable.instantiableTypes.map(\.asSource),
				isRoot: instantiable.isRoot,
				isSeam: instantiable.generatesDependencyTree,
				edges: instantiable.dependencies.map { dependency in
					GraphEdge(
						dependency,
						fulfilledBy: fulfillingTypeID(of: dependency.asInstantiatedType),
						filePath: attribution(of: dependency.declarationLocation?.filePath),
					)
				},
			)
		}
		// Sorted by module, then name, then line: never by file path, whose spelling depends on how a module was read.
		.sorted { lhs, rhs in
			(lhs.module ?? "", lhs.name, lhs.line ?? 0) < (rhs.module ?? "", rhs.name, rhs.line ?? 0)
		}

		fulfillment = (resolvedMap ?? [:])
			.map { typeDescription, instantiable in
				Fulfillment(type: typeDescription.asSource, fulfilledBy: id(of: instantiable))
			}
			// Two keys can share a spelling only where `==` ignores an `any`, so the provider breaks the tie.
			.sorted { ($0.type, $0.fulfilledBy) < ($1.type, $1.fulfilledBy) }
	}

	/// The version of the JSON format. `0` while the command is in alpha: the shape may change in any release.
	static let formatVersion = 0

	/// The modules read, by name, in name order.
	public let modules: [String]
	/// Whether SafeDI resolved which type fulfills each type. When it did not, `errors` says why, and neither
	/// `fulfillment` nor any edge's `fulfilledBy` is present.
	public let resolved: Bool
	/// The errors that kept SafeDI from resolving the graph.
	public let errors: [GraphError]
	/// Each production `@Instantiable` declaration, by module, then name, then line.
	public let types: [GraphType]
	/// The type that fulfills each type SafeDI can build, by the fulfilled type's spelling.
	public let fulfillment: [Fulfillment]

	/// The report as JSON, with its keys sorted.
	public func json() throws -> String {
		try QueryReport.json(of: self)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(Self.formatVersion, forKey: .formatVersion)
		try container.encode(modules, forKey: .modules)
		try container.encode(resolved, forKey: .resolved)
		try container.encode(errors, forKey: .errors)
		try container.encode(types, forKey: .types)
		try container.encode(fulfillment, forKey: .fulfillment)
	}

	/// A type's id: its name, after its module's. Every module the query reads names its declarations, so the module is
	/// always known. Opaque to a reader, who matches it whole.
	static func id(ofTypeSpelled typeName: String, moduleName: String?) -> String {
		[moduleName, typeName].compactMap(\.self).joined(separator: ".")
	}

	private enum CodingKeys: String, CodingKey {
		case formatVersion
		case modules
		case resolved
		case errors
		case types
		case fulfillment
	}

	/// An error that kept SafeDI from resolving the graph, located where `generate` would report it.
	public struct GraphError: Encodable, Equatable, Sendable {
		let message: String
		let filePath: String?
		let line: Int?
	}

	/// The type that fulfills a type.
	public struct Fulfillment: Encodable, Equatable, Sendable {
		/// The fulfilled type, as declarations spell it.
		let type: String
		/// The id of the type that fulfills it.
		let fulfilledBy: String
	}
}

/// A production `@Instantiable` declaration.
public struct GraphType: Encodable, Equatable, Sendable {
	let id: String
	/// The type's name, nested types qualified by the types that enclose them.
	let name: String
	let module: String?
	let filePath: String?
	let line: Int?
	let declarationKind: DeclarationKind
	/// The types the declaration fulfills, its own first.
	let fulfills: [String]
	let isRoot: Bool
	/// Whether the type is declared with `generateDependencyTree: true`.
	let isSeam: Bool
	/// The type's dependencies, in declaration order.
	let edges: [GraphEdge]

	enum DeclarationKind: String, Encodable, Equatable, Sendable {
		case `class`
		case actor
		case `struct`
		case `extension`

		init(_ declarationType: Instantiable.DeclarationType) {
			switch declarationType {
			case .classType:
				self = .class
			case .actorType:
				self = .actor
			case .structType:
				self = .struct
			case .extensionType:
				self = .extension
			}
		}
	}
}

/// A dependency a type declares.
public struct GraphEdge: Encodable, Equatable, Sendable {
	init(_ dependency: Dependency, fulfilledBy: String?, filePath: String?) {
		label = dependency.property.label
		type = dependency.property.typeDescription.asSource
		wrapper = dependency.property.typeDescription.propertyType.wrapperTypeName
		self.filePath = filePath
		line = dependency.declarationLocation?.line
		switch dependency.source {
		case let .instantiated(_, erasedToConcreteExistential):
			kind = Kind(builtAs: dependency.property.typeDescription.propertyType)
			builds = dependency.asInstantiatedType.asSource
			self.fulfilledBy = fulfilledBy
			erased = erasedToConcreteExistential ? true : nil
			onlyIfAvailable = nil
			aliasOf = nil
		case let .received(isOnlyIfAvailable):
			kind = .received
			builds = nil
			self.fulfilledBy = nil
			erased = nil
			onlyIfAvailable = isOnlyIfAvailable ? true : nil
			aliasOf = nil
		case let .aliased(fulfillingProperty, erasedToConcreteExistential, isOnlyIfAvailable):
			kind = .alias
			builds = nil
			self.fulfilledBy = nil
			erased = erasedToConcreteExistential ? true : nil
			onlyIfAvailable = isOnlyIfAvailable ? true : nil
			aliasOf = AliasOf(label: fulfillingProperty.label, type: fulfillingProperty.typeDescription.asSource)
		case .forwarded:
			kind = .forwarded
			builds = nil
			self.fulfilledBy = nil
			erased = nil
			onlyIfAvailable = nil
			aliasOf = nil
		}
	}

	let kind: Kind
	let label: String
	/// The property's type, as declared.
	let type: String
	/// The SafeDI wrapper the property is held in, when it is held in one.
	let wrapper: String?
	/// For an instantiated edge, the type it builds, as SafeDI looks it up: `fulfilledByType:`, or the property's type
	/// without its wrapper.
	let builds: String?
	/// For an instantiated edge in a resolved graph, the id of the type that fulfills `builds`; absent when no
	/// production declaration does.
	let fulfilledBy: String?
	let erased: Bool?
	let onlyIfAvailable: Bool?
	/// For an alias, the property it renames.
	let aliasOf: AliasOf?
	let filePath: String?
	let line: Int?

	enum Kind: String, Encodable, Equatable, Sendable {
		/// `@Instantiated`, built when its owner is.
		case instantiated
		/// `@Instantiated` in a `LazilyInstantiated` or `SendableLazilyInstantiated`: built once, when first read.
		case lazy
		/// `@Instantiated` in an instantiator: built each time it is asked.
		case builder
		case forwarded
		case received
		/// `@Received(fulfilledByDependencyNamed:ofType:)`.
		case alias

		init(builtAs propertyType: Property.PropertyType) {
			switch propertyType {
			case .constant:
				self = .instantiated
			case .lazilyInstantiated, .sendableLazilyInstantiated:
				self = .lazy
			case .instantiator, .erasedInstantiator, .sendableInstantiator, .sendableErasedInstantiator:
				self = .builder
			}
		}
	}

	struct AliasOf: Encodable, Equatable, Sendable {
		let label: String
		let type: String
	}
}
