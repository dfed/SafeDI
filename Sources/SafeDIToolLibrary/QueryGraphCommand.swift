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
		abstract: "Export every `@Instantiable` declaration, its dependencies, which declaration fulfills each one and which declarations each fulfills, and where each received dependency’s value comes from, as JSON (alpha).",
		discussion: "Reads the modules named with `--include` and `--module-info` once, as `query needs` reads them, and prints one JSON document: each production `@Instantiable` declaration with its module, file and line, the dependencies it declares, each with its type as declared and as a plain type and an instantiated one with the `fulfilledByType:` it names, the declaration that fulfills each instantiated dependency (`fulfilledBy`) and, on each declaration, the dependencies it fulfills (`constructedBy`), the declaration that fulfills each type, and, read from the trees `generate` builds, each declaration whose value a received dependency is handed, or why it is handed `nil` (`provenance`). Each declaration and dependency appears once, however many trees reach it. The same inputs give the same bytes. `completeness` says how much SafeDI worked out: when two declarations fulfill one type, only the declarations are exported; when the trees are not valid, no provenance is; `errors` says why, and the command still succeeds. This command is in alpha: its options and JSON may change in any release, which the JSON’s `formatVersion` of 0 says. SafeDI’s Documentation/QueryGraph.md documents the format.",
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
		// What each receive is handed is read from the trees `generate` builds of the production declarations, which the
		// export reports only when they are valid.
		var supplies: ReceivedValueSupplies?
		var treeDiagnostics = [SourceDiagnostic]()
		if let resolvedMap {
			let generator = DependencyTreeGenerator(
				importStatements: [],
				mockImportStatements: [],
				typeDescriptionToFulfillingInstantiableMap: resolvedMap.compactMapValues { $0.mockOnly ? nil : $0.withoutHandWrittenMock },
				// No code is generated, so no alias declaration is referenced.
				aliasDeclarationReferences: AliasDeclarationReferences(
					declarationFilePaths: [],
					compilerFilePaths: nil,
					commentFilePath: { $0 },
				),
				compilesGeneratedMocks: false,
			)
			do {
				supplies = try await generator.receivedValueSupplies()
			} catch let error as any SourceLocatedError {
				treeDiagnostics = error.sourceDiagnostics
			}
		}
		return QueryGraphReport(
			includedModules: parsedModules.map(\.includedModule),
			instantiables: instantiables,
			resolvedMap: resolvedMap,
			resolutionDiagnostics: resolutionDiagnostics + treeDiagnostics,
			supplies: supplies,
			attributionsByFilePath: attributionsByFilePath,
		)
	}
}

/// What `QueryGraph` exports: the production declarations of the modules it read, their dependencies, and which type
/// fulfills each type, each once. The format is documented in `Documentation/QueryGraph.md`.
public struct QueryGraphReport: Encodable, Equatable, Sendable {
	init(
		includedModules: [IncludedModule],
		instantiables: [Instantiable],
		resolvedMap: [TypeDescription: Instantiable]?,
		resolutionDiagnostics: [SourceDiagnostic],
		supplies: ReceivedValueSupplies?,
		attributionsByFilePath: [String: FileAttribution],
	) {
		modules = includedModules.map { GraphModule(name: $0.name, paths: $0.paths) }
		completeness = if resolvedMap == nil {
			.declarations
		} else if supplies == nil {
			.fulfillment
		} else {
			.trees
		}
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
		// The trees are built from the production declarations, which, once SafeDI resolved them, are each the only
		// declaration of its concrete type.
		var idByConcreteType = [TypeDescription: String]()
		for instantiable in productionInstantiables {
			idByConcreteType[instantiable.concreteInstantiable] = id(of: instantiable)
		}
		var provenanceByReceive = [GraphDependency.Receive: Set<GraphDependency.Provenance>]()
		for supply in supplies?.supplies ?? [] {
			let provenance: GraphDependency.Provenance = switch supply.value {
			case let .declaration(supplier):
				.declaration(declaredBy: idByConcreteType[supplier.declaringType] ?? supplier.declaringType.asSource, label: supplier.label)
			case let .passedNil(reason):
				.passedNil(GraphDependency.NilReason(reason, receivingTypeName: supply.receivingType.asSource, label: supply.label))
			}
			provenanceByReceive[GraphDependency.Receive(type: supply.receivingType, label: supply.label), default: []].insert(provenance)
		}
		let constructedTypes = supplies.map { Set($0.constructedTypes) }

		// Each instantiated dependency points down at the declaration that fulfills it; each declaration points back up
		// at the dependencies it fulfills.
		var constructedByByID = [String: [GraphDeclaration.Constructor]]()
		var dependenciesByID = [String: [GraphDependency]]()
		for instantiable in productionInstantiables {
			let declarationID = id(of: instantiable)
			dependenciesByID[declarationID] = instantiable.dependencies.map { dependency in
				let fulfilledBy = fulfillingTypeID(of: dependency.asInstantiatedType)
				if case .instantiated = dependency.source, let fulfilledBy {
					constructedByByID[fulfilledBy, default: []].append(GraphDeclaration.Constructor(declaredBy: declarationID, label: dependency.property.label))
				}
				let isReached = constructedTypes?.contains(instantiable.concreteInstantiable) == true
				return GraphDependency(
					dependency,
					fulfilledBy: fulfilledBy,
					provenance: isReached ? provenanceByReceive[GraphDependency.Receive(type: instantiable.concreteInstantiable, label: dependency.property.label)] ?? [] : nil,
					filePath: attribution(of: dependency.declarationLocation?.filePath),
				)
			}
		}

		errors = resolutionDiagnostics.map { diagnostic in
			GraphError(message: diagnostic.message, filePath: attribution(of: diagnostic.location?.filePath), line: diagnostic.location?.lineAndColumn?.line)
		}
		declarations = productionInstantiables.map { instantiable in
			let declarationID = id(of: instantiable)
			return GraphDeclaration(
				id: declarationID,
				typeName: instantiable.concreteInstantiable.asSource,
				module: instantiable.moduleName,
				filePath: attribution(of: instantiable.declarationLocation?.filePath ?? instantiable.sourceFilePath),
				line: instantiable.declarationLocation?.lineAndColumn?.line,
				declarationKind: GraphDeclaration.DeclarationKind(instantiable.declarationType),
				fulfills: instantiable.instantiableTypes.map(\.asSource),
				isRoot: instantiable.isRoot,
				generatesDependencyTree: instantiable.generatesDependencyTree,
				isReachedByRoot: constructedTypes.map { $0.contains(instantiable.concreteInstantiable) },
				constructedBy: resolvedMap.map { _ in (constructedByByID[declarationID] ?? []).sorted() },
				dependencies: dependenciesByID[declarationID] ?? [],
			)
		}
		// Sorted by module, then name, then line: never by file path, whose spelling depends on how a module was read.
		.sorted { lhs, rhs in
			(lhs.module ?? "", lhs.typeName, lhs.line ?? 0) < (rhs.module ?? "", rhs.typeName, rhs.line ?? 0)
		}

		fulfillments = (resolvedMap ?? [:])
			.map { typeDescription, instantiable in
				Fulfillment(plainType: typeDescription.plainType.asSource, fulfilledBy: id(of: instantiable))
			}
			// The declaration breaks a tie between two keys of one plain type, so no dictionary order reaches the output.
			.sorted { ($0.plainType, $0.fulfilledBy) < ($1.plainType, $1.fulfilledBy) }
	}

	/// The version of the JSON format. `0` while the command is in alpha: the shape may change in any release.
	static let formatVersion = 0

	/// The modules read, in name order.
	public let modules: [GraphModule]
	/// How much of the graph SafeDI could work out: the declarations alone, which type fulfills each type too, or the
	/// trees of the roots too. `errors` says why it stopped short.
	public let completeness: Completeness
	/// The errors that kept SafeDI from resolving the graph or from building its trees.
	public let errors: [GraphError]
	/// Each production `@Instantiable` declaration, by module, then name, then line.
	public let declarations: [GraphDeclaration]
	/// The declaration that fulfills each type SafeDI can build, by the fulfilled type's plain type.
	public let fulfillments: [Fulfillment]

	/// The report as JSON, with its keys sorted.
	public func json() throws -> String {
		try QueryReport.json(of: self)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode("graph", forKey: .command)
		try container.encode(Self.formatVersion, forKey: .formatVersion)
		try container.encode(completeness, forKey: .completeness)
		try container.encode(modules, forKey: .modules)
		try container.encode(errors, forKey: .errors)
		try container.encode(declarations, forKey: .declarations)
		try container.encode(fulfillments, forKey: .fulfillments)
	}

	/// A declaration's id: its type's name, after its module's. Every module the query reads names its declarations, so
	/// the module is always known. Opaque to a reader, who matches it whole.
	static func id(ofTypeSpelled typeName: String, moduleName: String?) -> String {
		[moduleName, typeName].compactMap(\.self).joined(separator: ".")
	}

	private enum CodingKeys: String, CodingKey {
		case command
		case formatVersion
		case completeness
		case modules
		case errors
		case declarations
		case fulfillments
	}

	/// How much of the graph SafeDI worked out.
	public enum Completeness: String, Encodable, Equatable, Sendable {
		/// Two declarations fulfill one type, so only the declarations are exported: no `fulfilledBy`, `constructedBy`
		/// or `fulfillments`.
		case declarations
		/// Which declaration fulfills each type is exported, but the trees are not valid, so no `isReachedByRoot` or
		/// `provenance`.
		case fulfillment
		/// Everything is exported.
		case trees
	}

	/// A module the query read.
	public struct GraphModule: Encodable, Equatable, Sendable {
		let name: String
		/// The `--include` directories or `--module-info` files that name the module, as given.
		let paths: [String]
	}

	/// An error that kept SafeDI from resolving the graph, located where `generate` would report it.
	public struct GraphError: Encodable, Equatable, Sendable {
		let message: String
		let filePath: String?
		let line: Int?
	}

	/// The declaration that fulfills a type.
	public struct Fulfillment: Encodable, Equatable, Sendable {
		/// The fulfilled type, as a plain type.
		let plainType: String
		/// The id of the declaration that fulfills it.
		let fulfilledBy: String
	}
}

/// A production `@Instantiable` declaration.
public struct GraphDeclaration: Encodable, Equatable, Sendable {
	let id: String
	/// The type's name, nested types qualified by the types that enclose them.
	let typeName: String
	let module: String?
	let filePath: String?
	let line: Int?
	let declarationKind: DeclarationKind
	/// The types the declaration fulfills, its own first.
	let fulfills: [String]
	let isRoot: Bool
	/// Whether the type is declared with `generateDependencyTree: true`.
	let generatesDependencyTree: Bool
	/// Once the trees are built, whether some root's tree builds the type.
	let isReachedByRoot: Bool?
	/// In a resolved graph, each instantiated dependency this declaration fulfills, by the id of the declaration that
	/// declares it and its label, sorted.
	let constructedBy: [Constructor]?
	/// The type's dependencies, in declaration order.
	let dependencies: [GraphDependency]

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

	/// An instantiated dependency that a declaration fulfills.
	struct Constructor: Encodable, Comparable, Sendable {
		/// The id of the declaration that declares the dependency.
		let declaredBy: String
		let label: String

		static func < (lhs: Self, rhs: Self) -> Bool {
			(lhs.declaredBy, lhs.label) < (rhs.declaredBy, rhs.label)
		}
	}
}

/// A dependency a declaration declares.
public struct GraphDependency: Encodable, Equatable, Sendable {
	init(_ dependency: Dependency, fulfilledBy: String?, provenance: Set<Provenance>?, filePath: String?) {
		label = dependency.property.label
		type = dependency.property.typeDescription.asSource
		wrapper = dependency.property.typeDescription.propertyType.wrapperTypeName
		self.filePath = filePath
		line = dependency.declarationLocation?.lineAndColumn?.line
		switch dependency.source {
		case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
			source = .instantiated
			lifetime = Lifetime(builtAs: dependency.property.typeDescription.propertyType)
			plainType = dependency.property.typeDescription.plainType.asSource
			// `asInstantiatedType` is the `fulfilledByType:` type as normalization qualified it.
			fulfilledByType = fulfillingTypeDescription == nil ? nil : dependency.asInstantiatedType.plainType.asSource
			self.fulfilledBy = fulfilledBy
			isErased = erasedToConcreteExistential
			isOnlyIfAvailable = dependency.isInstantiatedOnlyIfAvailable
			aliasOf = nil
			self.provenance = nil
		case let .received(onlyIfAvailable):
			source = .received
			lifetime = nil
			plainType = dependency.property.typeDescription.plainType.asSource
			fulfilledByType = nil
			self.fulfilledBy = nil
			isErased = false
			isOnlyIfAvailable = onlyIfAvailable
			aliasOf = nil
			self.provenance = provenance.map { $0.sorted() }
		case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
			source = .received
			lifetime = nil
			plainType = dependency.property.typeDescription.plainType.asSource
			fulfilledByType = nil
			self.fulfilledBy = nil
			isErased = erasedToConcreteExistential
			isOnlyIfAvailable = onlyIfAvailable
			aliasOf = AliasOf(
				label: fulfillingProperty.label,
				type: fulfillingProperty.typeDescription.asSource,
				plainType: fulfillingProperty.typeDescription.plainType.asSource,
			)
			self.provenance = provenance.map { $0.sorted() }
		case .forwarded:
			source = .forwarded
			lifetime = nil
			plainType = dependency.property.typeDescription.plainType.asSource
			fulfilledByType = nil
			self.fulfilledBy = nil
			isErased = false
			isOnlyIfAvailable = false
			aliasOf = nil
			self.provenance = nil
		}
	}

	let label: String
	let source: Source
	/// For an instantiated dependency, when its value is built.
	let lifetime: Lifetime?
	/// The property's type, as declared.
	let type: String
	/// The type of the value the dependency holds, with no optional, wrapper or `any`.
	let plainType: String
	/// For an instantiated dependency that names the type SafeDI builds with `fulfilledByType:`, that type, with no
	/// optional, wrapper or `any`.
	let fulfilledByType: String?
	/// The SafeDI wrapper the property is held in, when it is held in one.
	let wrapper: String?
	/// For an instantiated dependency in a resolved graph, the id of the declaration that fulfills the type SafeDI
	/// builds (`fulfilledByType`, else `plainType`); absent
	/// when no production declaration does.
	let fulfilledBy: String?
	let isErased: Bool
	let isOnlyIfAvailable: Bool
	/// For an alias, the property it renames.
	let aliasOf: AliasOf?
	/// For a received dependency or an alias of a type some root's tree builds, once the trees are built: each value the
	/// trees hand it, wherever they build its type.
	let provenance: [Provenance]?
	let filePath: String?
	let line: Int?

	/// Where a dependency's value comes from.
	enum Source: String, Encodable, Equatable, Sendable {
		/// `@Instantiated`: the declaration builds it.
		case instantiated
		/// `@Received`, or `@Received(fulfilledByDependencyNamed:ofType:)`, an alias: a declaration above hands it.
		case received
		/// `@Forwarded`: whoever builds the declaration hands it.
		case forwarded
	}

	/// When an instantiated dependency's value is built.
	enum Lifetime: String, Encodable, Equatable, Sendable {
		/// Built when its owner is.
		case eager
		/// In a `LazilyInstantiated` or `SendableLazilyInstantiated`: built once, when first read.
		case lazy
		/// In an instantiator: built each time it is asked.
		case builder

		init(builtAs propertyType: Property.PropertyType) {
			switch propertyType {
			case .constant:
				self = .eager
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
		let plainType: String
	}

	/// A value the trees hand a received dependency: a declaration's, or `nil`.
	enum Provenance: Encodable, Hashable, Comparable, Sendable {
		/// The value of a dependency the declaration with id `declaredBy` instantiates, forwards or aliases.
		case declaration(declaredBy: String, label: String)
		/// `nil`, which generated code hands a dependency received only if available.
		case passedNil(NilReason)

		static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.sortKey < rhs.sortKey
		}

		/// Declarations by id, then label, before `nil` by reason.
		private var sortKey: (Int, String, String) {
			switch self {
			case let .declaration(declaredBy, label):
				(0, declaredBy, label)
			case let .passedNil(reason):
				(1, reason.kind.rawValue, "")
			}
		}

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			switch self {
			case let .declaration(declaredBy, label):
				try container.encode("declaration", forKey: .source)
				try container.encode(declaredBy, forKey: .declaredBy)
				try container.encode(label, forKey: .label)
			case let .passedNil(reason):
				try container.encode("nil", forKey: .source)
				try container.encode(reason, forKey: .reason)
			}
		}

		private enum CodingKeys: String, CodingKey {
			case source
			case declaredBy
			case label
			case reason
		}
	}

	/// Why generated code hands a dependency `nil`.
	struct NilReason: Encodable, Hashable, Sendable {
		init(_ reason: ReceivedValueSupply.NilReason, receivingTypeName: String, label: String) {
			switch reason {
			case .noProvidingDeclaration:
				kind = .noProvidingDeclaration
				message = "No declaration in scope where `\(receivingTypeName)` is built provides the `\(label)` it receives."
			case .providerNotYetBuilt:
				kind = .providerNotYetBuilt
				message = "The nearest declaration that provides `\(label)` is built after `\(receivingTypeName)`, or is still being built where `\(receivingTypeName)` is built inside it."
			}
		}

		let kind: Kind
		let message: String

		enum Kind: String, Encodable, Sendable {
			case noProvidingDeclaration
			case providerNotYetBuilt
		}
	}

	/// A receive: the type that declares it, and its label.
	struct Receive: Hashable {
		let type: TypeDescription
		let label: String
	}
}
