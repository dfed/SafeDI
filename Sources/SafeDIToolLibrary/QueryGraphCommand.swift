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
		discussion: "Reads the modules named with `--include` and `--module-info` once, as `query needs` reads them, and prints one JSON document: each production `@Instantiable` declaration with its module, file and line, the dependencies it declares, each with its type as declared and as a plain type and an instantiated one with the `fulfilledByType:` it names, the declaration that fulfills each instantiated dependency (`fulfilledBy`) and, on each declaration, the dependencies it fulfills (`constructedBy`), the declaration that fulfills each type, and, read from the trees `generate` builds, each declaration whose value a received dependency is handed, or why it is handed `nil` (`provenance`). Each declaration and dependency appears once, however many trees reach it. The same inputs give the same bytes. `completeness` says how much SafeDI worked out: when two declarations fulfill one type, only the declarations are exported; when only dependencies that cannot be fulfilled keep the trees from being valid, those dependencies are marked `isUnfulfilled` and provenance is read from the trees built around them, with every declaration as written; when the trees are not valid otherwise, no provenance is; `errors` lists what `generate` reports, and the command still succeeds. This command is in alpha: its options and JSON may change in any release, which the JSON’s `formatVersion` of 0 says. SafeDI’s Documentation/QueryGraph.md documents the format.",
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
		// export reports only when they are valid, or when only dependencies that cannot be fulfilled keep them from being
		// valid: then from the trees built again of the same declarations, around those dependencies, which `generate`
		// never builds.
		var supplies: ReceivedValueSupplies?
		var treeDiagnostics = [SourceDiagnostic]()
		var unfulfilledDependencies = [UnfulfilledDependency]()
		if let resolvedMap {
			var productionMap = resolvedMap.compactMapValues { $0.mockOnly ? nil : $0.withoutHandWrittenMock }
			do {
				supplies = try await Self.generator(over: productionMap).receivedValueSupplies()
			} catch let error as any SourceLocatedError {
				treeDiagnostics = error.sourceDiagnostics
				// `generate` reports the types no declaration fulfills before any receive nothing provides, which it
				// reports once those types are declared. So the trees are built again at most twice: around the types,
				// then around the receives too. Any other error is not of a dependency that cannot be fulfilled, so no
				// provenance is read, and `generate`'s own error is the only one exported; nor is any read where a builder
				// function a lazy cycle closes on takes the label of one of those receives as a parameter the receive
				// reads or a call beneath it passes.
				var latestError: any Error = error
				var unfulfilledReceiveLocations = Set<Dependency.DeclarationLocation>()
				var reportedDependencies = [UnfulfilledDependency]()
				var reportedDiagnostics = [SourceDiagnostic]()
				for _ in 0..<2 {
					guard supplies == nil,
					      let absentDeclarations = DependencyTreeGenerator.absentDeclarations(ofDependenciesReportedBy: latestError, in: productionMap)
					else { break }
					productionMap = absentDeclarations.map
					unfulfilledReceiveLocations.formUnion(absentDeclarations.unfulfilledReceiveLocations)
					reportedDependencies.append(contentsOf: absentDeclarations.unfulfilledDependencies)
					do {
						guard let suppliesAroundDependencies = try await Self.generator(over: productionMap, unfulfilledReceiveLocations: unfulfilledReceiveLocations).receivedValueSupplies() else { break }
						supplies = suppliesAroundDependencies
					} catch let error as any SourceLocatedError {
						latestError = error
						reportedDiagnostics.append(contentsOf: error.sourceDiagnostics)
					}
				}
				if supplies != nil {
					unfulfilledDependencies = reportedDependencies
					treeDiagnostics.append(contentsOf: reportedDiagnostics)
				}
			}
		}
		return QueryGraphReport(
			includedModules: parsedModules.map(\.includedModule),
			instantiables: instantiables,
			resolvedMap: resolvedMap,
			resolutionDiagnostics: resolutionDiagnostics + treeDiagnostics,
			supplies: supplies,
			unfulfilledDependencies: Set(unfulfilledDependencies),
			attributionsByFilePath: attributionsByFilePath,
		)
	}

	/// A generator that builds the trees of `productionMap`'s roots and generates no code.
	/// - Parameter unfulfilledReceiveLocations: Where each received dependency and alias is declared that the trees are
	///   built around although nothing provides it.
	private static func generator(
		over productionMap: [TypeDescription: Instantiable],
		unfulfilledReceiveLocations: Set<Dependency.DeclarationLocation> = [],
	) -> DependencyTreeGenerator {
		DependencyTreeGenerator(
			importStatements: [],
			mockImportStatements: [],
			typeDescriptionToFulfillingInstantiableMap: productionMap,
			compilesGeneratedMocks: false,
			unfulfilledReceiveLocations: unfulfilledReceiveLocations,
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
		unfulfilledDependencies: Set<UnfulfilledDependency>,
		attributionsByFilePath: [String: FileAttribution],
	) {
		modules = includedModules.map { GraphModule(name: $0.name, paths: $0.paths) }
		completeness = if resolvedMap == nil {
			.declarations
		} else if supplies == nil {
			.fulfillment
		} else if !unfulfilledDependencies.isEmpty {
			.partialTrees
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
		// A dependency instantiated only if available that no production declaration fulfills is `nil`, and so is every
		// receive handed its value.
		var absentDependencies = Set<UnfulfilledDependency>()
		for instantiable in productionInstantiables {
			for dependency in instantiable.dependencies where dependency.isInstantiatedOnlyIfAvailable && fulfillingTypeID(of: dependency.asInstantiatedType) == nil {
				absentDependencies.insert(UnfulfilledDependency(declaringType: instantiable.concreteInstantiable, label: dependency.property.label))
			}
		}
		let dependencyByDeclaration = Self.dependencyByDeclaration(of: productionInstantiables)
		var provenanceByReceive = [GraphDependency.Receive: Set<GraphDependency.Provenance>]()
		for supply in supplies?.supplies ?? [] {
			let receivingTypeName = supply.receivingType.asSource
			let provenance: GraphDependency.Provenance
			switch supply.value {
			case let .declaration(supplier):
				let declaredBy = idByConcreteType[supplier.declaringType] ?? supplier.declaringType.asSource
				let declaration = UnfulfilledDependency(declaringType: supplier.declaringType, label: supplier.label)
				// A marked alias is a declaration still: the reader follows its own provenance to what it renames.
				provenance = if unfulfilledDependencies.contains(declaration), dependencyByDeclaration[declaration]?.source.fulfillingProperty == nil {
					.unfulfilled(GraphDependency.Unfulfilled(instantiatedBy: declaredBy, label: supplier.label))
				} else if absentDependencies.contains(declaration) {
					.passedNil(GraphDependency.NilReason(notInstantiatedBy: declaredBy, label: supplier.label))
				} else {
					.declaration(declaredBy: declaredBy, label: supplier.label)
				}
			case let .passedNil(reason):
				provenance = .passedNil(GraphDependency.NilReason(reason, receivingTypeName: receivingTypeName, label: supply.label))
			case let .unfulfilled(supplier?):
				provenance = .unfulfilled(GraphDependency.Unfulfilled(
					receivedBy: idByConcreteType[supplier.declaringType] ?? supplier.declaringType.asSource,
					label: supplier.label,
				))
			case .unfulfilled(nil):
				let fulfillingProperty = dependencyByDeclaration[UnfulfilledDependency(declaringType: supply.receivingType, label: supply.label)]?.source.fulfillingProperty
				provenance = .unfulfilled(GraphDependency.Unfulfilled(receivingTypeName: receivingTypeName, label: supply.label, renaming: fulfillingProperty?.label))
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
					isUnfulfilled: unfulfilledDependencies.contains(UnfulfilledDependency(declaringType: instantiable.concreteInstantiable, label: dependency.property.label)),
					fulfilledBy: fulfilledBy,
					provenance: isReached ? provenanceByReceive[GraphDependency.Receive(type: instantiable.concreteInstantiable, label: dependency.property.label)] ?? [] : nil,
					filePath: attribution(of: dependency.declarationLocation?.filePath),
				)
			}
		}

		errors = resolutionDiagnostics.map { diagnostic in
			GraphError(message: diagnostic.message, filePath: attribution(of: diagnostic.location?.filePath), line: diagnostic.location?.position?.line)
		}
		declarations = productionInstantiables.map { instantiable in
			let declarationID = id(of: instantiable)
			return GraphDeclaration(
				id: declarationID,
				typeName: instantiable.concreteInstantiable.asSource,
				module: instantiable.moduleName,
				filePath: attribution(of: instantiable.declarationLocation?.filePath ?? instantiable.sourceFilePath),
				line: instantiable.declarationLocation?.position?.line,
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

	/// Each production dependency of `instantiables` as declared, by the type that declares it and its label.
	private static func dependencyByDeclaration(of instantiables: some Sequence<Instantiable>) -> [UnfulfilledDependency: Dependency] {
		var dependencyByDeclaration = [UnfulfilledDependency: Dependency]()
		// A type's declaration is listed under each type it fulfills, each time with the same dependencies.
		for instantiable in instantiables where !instantiable.mockOnly {
			for dependency in instantiable.dependencies {
				dependencyByDeclaration[UnfulfilledDependency(declaringType: instantiable.concreteInstantiable, label: dependency.property.label)] = dependency
			}
		}
		return dependencyByDeclaration
	}

	/// The version of the JSON format. `0` while the command is in alpha: the shape may change in any release.
	static let formatVersion = 0

	/// The modules read, in name order.
	public let modules: [GraphModule]
	/// How much of the graph SafeDI could work out: the declarations alone, which type fulfills each type too, the trees
	/// of the roots built around the dependencies that cannot be fulfilled, or the trees of the roots. `errors` lists
	/// what `generate` reports of a graph it stopped short on.
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
		/// Only dependencies that cannot be fulfilled keep the trees from being valid: each is marked `isUnfulfilled`,
		/// and `isReachedByRoot` and `provenance` are read from the trees built around them, of the declarations as
		/// written: a type no declaration fulfills is built with no dependencies, and a receive nothing provides is
		/// handed nothing.
		case partialTrees
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
	init(_ dependency: Dependency, isUnfulfilled: Bool, fulfilledBy: String?, provenance: Set<Provenance>?, filePath: String?) {
		label = dependency.property.label
		self.isUnfulfilled = isUnfulfilled ? true : nil
		type = dependency.property.typeDescription.asSource
		wrapper = dependency.property.typeDescription.propertyType.wrapperTypeName
		self.filePath = filePath
		line = dependency.declarationLocation?.position?.line
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
	/// `true` when the dependency cannot be fulfilled and the export's `completeness` is `partialTrees`; absent otherwise.
	let isUnfulfilled: Bool?
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
		/// No value, since the dependency, or the one whose value it would be handed, cannot be fulfilled.
		case unfulfilled(Unfulfilled)

		static func < (lhs: Self, rhs: Self) -> Bool {
			lhs.sortKey < rhs.sortKey
		}

		/// Declarations by id, then label, before `nil` by reason, then by the declaration it names, before what cannot be
		/// fulfilled, the entry that names no declaration first, then by the declaration it names. A dependency has one
		/// entry of each key: it names a declaration once, and a reason that names none has one message.
		private var sortKey: (Int, String, String, String) {
			switch self {
			case let .declaration(declaredBy, label):
				(0, "", declaredBy, label)
			case let .passedNil(reason):
				(1, reason.kind.rawValue, reason.declaredBy ?? "", reason.label ?? "")
			case let .unfulfilled(unfulfilled):
				(2, "", unfulfilled.declaredBy ?? "", unfulfilled.label ?? "")
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
			case let .unfulfilled(unfulfilled):
				try container.encode("unfulfilled", forKey: .source)
				try container.encodeIfPresent(unfulfilled.declaredBy, forKey: .declaredBy)
				try container.encodeIfPresent(unfulfilled.label, forKey: .label)
				try container.encode(unfulfilled.message, forKey: .message)
			}
		}

		private enum CodingKeys: String, CodingKey {
			case source
			case declaredBy
			case label
			case reason
			case message
		}
	}

	/// Why a dependency has no value in an export whose `completeness` is `partialTrees`.
	struct Unfulfilled: Hashable, Sendable {
		/// The receive itself cannot be fulfilled: nothing provides it, or, for an alias, the `renaming` it renames.
		init(receivingTypeName: String, label: String, renaming fulfillingLabel: String?) {
			declaredBy = nil
			self.label = nil
			message = if let fulfillingLabel {
				"Nothing provides the `\(fulfillingLabel)` that `\(receivingTypeName)` renames `\(label)`."
			} else {
				"Nothing provides the `\(label)` that `\(receivingTypeName)` receives."
			}
		}

		/// The declaration whose value the receive would be handed instantiates a type no declaration fulfills.
		init(instantiatedBy declaredBy: String, label: String) {
			self.declaredBy = declaredBy
			self.label = label
			message = "`\(declaredBy)` instantiates `\(label)`, which no declaration fulfills."
		}

		/// The receive would be handed the value a receive above it is handed, which nothing provides.
		init(receivedBy declaredBy: String, label: String) {
			self.declaredBy = declaredBy
			self.label = label
			message = "`\(declaredBy)` receives `\(label)`, which nothing provides."
		}

		let declaredBy: String?
		let label: String?
		let message: String
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
			declaredBy = nil
			self.label = nil
		}

		/// The declaration whose value the receive is handed is instantiated only if available, and no declaration
		/// fulfills it.
		init(notInstantiatedBy declaredBy: String, label: String) {
			kind = .declarationNotInstantiated
			self.declaredBy = declaredBy
			self.label = label
			message = "`\(declaredBy)` instantiates `\(label)` only if available, and no declaration fulfills it."
		}

		let kind: Kind
		/// For `declarationNotInstantiated`, the id of the declaration whose dependency is not instantiated, and the
		/// dependency's label; absent otherwise.
		let declaredBy: String?
		let label: String?
		let message: String

		enum Kind: String, Encodable, Sendable {
			case noProvidingDeclaration
			case providerNotYetBuilt
			case declarationNotInstantiated
		}
	}

	/// A receive: the type that declares it, and its label.
	struct Receive: Hashable {
		let type: TypeDescription
		let label: String
	}
}
