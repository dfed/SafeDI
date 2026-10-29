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

public actor DependencyTreeGenerator {
	// MARK: Initialization

	/// - Parameters:
	///   - importStatements: The imports generated dependency-tree code needs.
	///   - mockImportStatements: The imports generated mock code needs.
	public init(
		importStatements: [ImportStatement],
		mockImportStatements: [ImportStatement],
		typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
		aliasDeclarationReferences: AliasDeclarationReferences,
	) {
		self.importStatements = importStatements
		self.mockImportStatements = mockImportStatements
		self.typeDescriptionToFulfillingInstantiableMap = typeDescriptionToFulfillingInstantiableMap
		self.aliasDeclarationReferences = aliasDeclarationReferences
	}

	// MARK: Public

	public struct GeneratedRoot: Sendable {
		public let typeDescription: TypeDescription
		public let sourceFilePath: String?
		/// The generated extension code for this root, without the file header.
		public let code: String
	}

	public struct MockGenerationResult: Sendable {
		public let generatedRoots: [GeneratedRoot]
		public let mockConfigurationCode: String?
	}

	/// The file header to prepend to each generated dependency-tree file.
	public var fileHeader: String {
		Self.fileHeader(importing: importStatements)
	}

	/// The file header to prepend to each generated mock file and to the shared mock configuration file.
	public var mockFileHeader: String {
		Self.fileHeader(importing: mockImportStatements)
	}

	/// The file header to prepend to one file that holds both generated dependency-tree code and generated mock code.
	public var dependencyTreeAndMockFileHeader: String {
		Self.fileHeader(importing: importStatements + mockImportStatements)
	}

	public func generatePerRootCodeTrees() async throws -> [GeneratedRoot] {
		let rootScopeGenerators = try rootScopeGenerators

		return try await withThrowingTaskGroup(
			of: GeneratedRoot?.self,
			returning: [GeneratedRoot].self,
		) { taskGroup in
			for rootInfo in rootScopeGenerators {
				taskGroup.addTask {
					let code = try await rootInfo.scopeGenerator.generateCode()
					return GeneratedRoot(
						typeDescription: rootInfo.typeDescription,
						sourceFilePath: rootInfo.sourceFilePath,
						code: code,
					)
				}
			}
			var generatedRoots = [GeneratedRoot]()
			for try await generatedRoot in taskGroup {
				if let generatedRoot {
					generatedRoots.append(generatedRoot)
				}
			}
			return generatedRoots
		}
	}

	/// Warnings about a dependency tree that generates successfully. `SafeDITool generate` returns them rather
	/// than throwing them. Call after `generatePerRootCodeTrees()`, which validates the tree.
	///
	/// There is one warning: a `LazilyInstantiated` dependency that is instantiated whenever the type that
	/// declares it is created, because a type created along with that one reads its instance. Nothing is lazy
	/// about such a dependency, and nothing else says so.
	public func generateWarnings() -> [SourceDiagnostic] {
		// The analysis visits every scope, so only a tree that lazily instantiates something pays for it.
		guard typeDescriptionToFulfillingInstantiableMap.values.contains(where: { instantiable in
			instantiable.dependencies.contains { $0.isInstantiated && $0.property.propertyType.isLazilyInstantiated }
		}) else {
			return []
		}
		var cache = [ObjectIdentifier: InstantiationAnalysis]()
		return validatedScopes
			.flatMap { scope in
				Self.instantiationAnalysis(of: scope, cache: &cache).lazilyInstantiatedPropertiesInstantiatedWithOwner.map {
					$0.warning(owner: scope.instantiable)
				}
			}
			// Sorted by location so the order never depends on set iteration.
			.sorted(by: SourceDiagnostic.precedesInSourceOrder)
	}

	/// Generates mock code for all `@Instantiable` types.
	public func generateMockCode(
		mockConditionalCompilation: String?,
		currentModuleSourceFilePaths: Set<String>? = nil,
		additionalMocksToGenerate: Set<String> = [],
	) async throws -> MockGenerationResult {
		// Build a map of erased wrapper types → concrete fulfilling types.
		// This lets mocks construct types like AnyUserService(DefaultUserService())
		// even when the erased type isn't directly @Instantiable. An erased type
		// that declarations erase different concrete types to is left out: nothing
		// says which one a mock should build, so a received property of that type
		// stays a required mock parameter.
		let erasedToConcreteTypeMap = typeDescriptionToFulfillingInstantiableMap.values
			.reduce(into: [TypeDescription: Set<TypeDescription>]()) { partialResult, instantiable in
				for dependency in instantiable.dependencies {
					if case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential) = dependency.source,
					   erasedToConcreteExistential,
					   let concreteType = fulfillingTypeDescription?.asInstantiatedType
					{
						partialResult[dependency.property.typeDescription, default: []].insert(concreteType)
						// A lazily instantiated dependency is also received by value, with the type of its instance.
						if let instanceProperty = dependency.property.asLazilyInstantiatedInstanceProperty {
							partialResult[instanceProperty.typeDescription, default: []].insert(concreteType)
						}
					}
				}
			}
			.compactMapValues { concreteTypes in
				concreteTypes.count == 1 ? concreteTypes.first : nil
			}

		// Build mock scope mapping — like production but includes all types and
		// promotes received dependencies as instantiated children.
		let typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping()

		// Validate mock scopes for cycles. Mock-only types (generateMock: true without
		// isRoot) bypass root validation but can still have partially-lazy cycles.
		// Uses cyclesOnly to skip unfulfillable property checks — mock-only types
		// have unfulfillable received properties by design (they become mock parameters).
		// `collectReceivedProperties` gives a scope the same complete result however it is
		// reached, every scope it caches is in `typeDescriptionToScopeMap`, which lives through
		// this method, and only complete results outlive a walk, so one cache serves this
		// validation and every mock root.
		var receivedPropertiesCache = ReceivedPropertiesCache()
		try validatePropertiesAreFulfillable(
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			// The scopes of the types the mock-root loop below generates a mock for because they are listed.
			additionalMockRootScopes: additionalMocksToGenerate.isEmpty ? [] : Set(
				typeDescriptionToFulfillingInstantiableMap.values.compactMap { instantiable in
					additionalMocksToGenerate.contains(instantiable.concreteInstantiable.asSource)
						? typeDescriptionToScopeMap[instantiable.concreteInstantiable]
						: nil
				},
			),
			receivedPropertiesCache: &receivedPropertiesCache,
			cyclesOnly: true,
		)

		// Compute types with hand-written mocks that can be called with zero arguments,
		// suitable for use as default values in forwarded mock parameters. This includes
		// standalone mockOnly types AND merged entries where a mockOnly declaration's mock
		// was copied onto a production entry (which may also have generateMock). Types
		// whose mock method has required parameters are excluded. The mock return type
		// must be compatible with the concrete type — extension mocks returning a
		// protocol type are not valid defaults for concrete-type forwarded parameters.
		let forwardedParameterMockDefaults: [TypeDescription: String] = typeDescriptionToFulfillingInstantiableMap.values
			.reduce(into: [TypeDescription: String]()) { result, instantiable in
				guard let mockInitializer = instantiable.mockInitializer,
				      mockInitializer.arguments.allSatisfy(\.hasDefaultValue),
				      instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiable.concreteInstantiable)
				else { return }
				result[instantiable.concreteInstantiable] = instantiable.customMockName ?? InstantiableVisitor.mockMethodName
			}

		// Locate the hand-written methods named `mock` (no `customMockName`) for
		// each concrete type. Several map entries can carry the same method
		// (merged and unmerged mockOnly slots), so locations are deduplicated.
		let handWrittenMockLocationsByConcreteType: [TypeDescription: Set<Dependency.DeclarationLocation?>] = typeDescriptionToFulfillingInstantiableMap.values
			.reduce(into: [TypeDescription: Set<Dependency.DeclarationLocation?>]()) { result, instantiable in
				guard instantiable.mockInitializer != nil,
				      instantiable.customMockName == nil
				else { return }
				result[instantiable.concreteInstantiable, default: []].insert(instantiable.mockDeclarationLocation)
			}

		// Create mock-root ScopeGenerators using the production Scope tree.
		var seen = Set<TypeDescription>()
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation(scopes: typeDescriptionToScopeMap.values)
		var mockRoots = [(instantiable: Instantiable, scopeGenerator: ScopeGenerator)]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values
			.sorted(by: { $0.concreteInstantiable < $1.concreteInstantiable })
		{
			let isAdditionalMock = additionalMocksToGenerate.contains(instantiable.concreteInstantiable.asSource)
			// Skip types where generateMock is not enabled (unless explicitly listed
			// in additionalMocksToGenerate), duplicates, and types not in the scope map.
			// Types from dependent modules are skipped unless they appear in
			// additionalMocksToGenerate. When generateMock is true and a hand-written
			// mock exists, the generated mock calls through to the hand-written one
			// (which must have a different name specified by customMockName).
			guard instantiable.generateMock || isAdditionalMock,
			      seen.insert(instantiable.concreteInstantiable).inserted,
			      let scope = typeDescriptionToScopeMap[instantiable.concreteInstantiable]
			else { continue }
			// Canonicalize: slot-specific merges can produce different entries
			// for the same concreteInstantiable (e.g., the ServiceProtocol key
			// has a protocol-returning mock but the MyService key does not).
			// Always use the concrete-type key entry so mock root generation
			// uses the correct mock info for the concrete type.
			// The mock root declares the dependencies its scope builds, which leaves out those its hand-written
			// mock is not passed (see `createMockTypeDescriptionToScopeMapping`).
			let instantiable = (typeDescriptionToFulfillingInstantiableMap[instantiable.concreteInstantiable] ?? instantiable)
				.keepingDependencies { !scope.dependenciesLeftOut.contains($0) }
			// Without module scoping, every type belongs to the current module.
			let isDeclaredInCurrentModule = currentModuleSourceFilePaths.map { currentModuleSourceFilePaths in
				instantiable.sourceFilePath.map(currentModuleSourceFilePaths.contains) ?? false
			} ?? true
			guard isAdditionalMock || isDeclaredInCurrentModule else { continue }

			// A hand-written method also named `mock` can be confused with the
			// generated `mock()`: identical signatures redeclare, overlapping ones
			// make calls ambiguous or silently pick the generated method, and a
			// mockOnly extension's mock defaults every parameter, so even a
			// generated `mock(safeDIOverrides:)` leaves `Type.mock()` ambiguous.
			// The macro rejects the pair within one declaration; this extends the
			// rule across declarations and modules.
			let handWrittenMockLocations = handWrittenMockLocationsByConcreteType[instantiable.concreteInstantiable, default: []]
			guard handWrittenMockLocations.isEmpty else {
				throw DependencyTreeGeneratorError.handWrittenMockSharesGeneratedMockName(
					instantiable.concreteInstantiable,
					declaredAt: Array(handWrittenMockLocations),
					// A `generateMock: true` type declared in this module gets its mock whether
					// or not it is listed; any other type reaching here is generated only
					// because it is listed, so removing it from the list is also a fix.
					isGeneratedForAdditionalMocksToGenerate: !(instantiable.generateMock && isDeclaredInCurrentModule),
				)
			}

			// Validate that this type's constant @Instantiated children have no @Forwarded properties.
			// Use the mock scope map (not typeDescriptionToFulfillingInstantiableMap) because
			// mockOnly types can win additional-type slots and may have different @Forwarded properties.
			// For fulfilledByType deps, validate against the declared type (same as mock resolution).
			for dependency in scope.instantiable.dependencies {
				guard case let .instantiated(fulfillingTypeDescription, _) = dependency.source else { continue }
				let instantiatedType = dependency.asInstantiatedType
				let childScope: Scope? = if fulfillingTypeDescription != nil {
					typeDescriptionToScopeMap[dependency.property.typeDescription.asInstantiatedType]
						?? typeDescriptionToScopeMap[instantiatedType]
				} else {
					typeDescriptionToScopeMap[instantiatedType]
				}
				if let childScope,
				   let error = forwardedPropertyError(
				   	for: dependency,
				   	instantiable: childScope.instantiable,
				   	parent: scope.instantiable,
				   )
				{
					throw error
				}
			}

			let mockRoot = try createMockRootScopeGenerator(
				for: instantiable,
				scope: scope,
				typeDescriptionToScopeMap: typeDescriptionToScopeMap,
				erasedToConcreteTypeMap: erasedToConcreteTypeMap,
				receivedPropertiesCache: &receivedPropertiesCache,
				childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
			)
			mockRoots.append((instantiable: instantiable, scopeGenerator: mockRoot))
		}

		// Compute the global cycle edges across all mock-reachable types. Per-tree
		// cycle detection (`isPropertyCycle`) breaks at a different edge depending
		// on which root is being walked — fine for breaking infinite tree descent
		// but not for `SafeDIMockConfiguration` struct shape, which must agree
		// across every root's view of a given type. The SCC-derived feedback arc
		// set guarantees the same back-edges are filtered everywhere.
		let cycleEdges = Self.computeCycleEdges(in: typeDescriptionToScopeMap)

		// Pre-pass: union the set of concrete type names whose
		// `SafeDIMockConfiguration` struct must be `@Sendable`-typed. A struct is
		// shared across every root that references the type, so the annotation
		// has to agree — union all roots' sendable references once, then pass it
		// down to each root's emission.
		let sendableConfigurationTypeNames: Set<String> = await withTaskGroup(
			of: Set<String>.self,
			returning: Set<String>.self,
		) { taskGroup in
			for (_, mockRoot) in mockRoots {
				taskGroup.addTask {
					await mockRoot.collectSendableConfigurationTypeNames()
				}
			}
			var union = Set<String>()
			for await result in taskGroup {
				union.formUnion(result)
			}
			return union
		}

		// Generate mock code and collect configuration types in parallel.
		let generatedRoots = try await withThrowingTaskGroup(
			of: GeneratedMockRoot.self,
			returning: [GeneratedMockRoot].self,
		) { taskGroup in
			for (instantiable, mockRoot) in mockRoots {
				taskGroup.addTask {
					async let code = mockRoot.generateCode(
						codeGeneration: .mock(ScopeGenerator.MockContext(
							mockConditionalCompilation: mockConditionalCompilation,
							forwardedParameterMockDefaults: forwardedParameterMockDefaults,
							cycleEdges: cycleEdges,
						)),
					)
					async let configurationTypes = mockRoot.collectConfigurationTypes()
					return try await GeneratedMockRoot(
						root: GeneratedRoot(
							typeDescription: instantiable.concreteInstantiable,
							sourceFilePath: instantiable.sourceFilePath,
							code: code,
						),
						configurationTypes: configurationTypes,
					)
				}
			}
			var results = [GeneratedMockRoot]()
			for try await result in taskGroup {
				results.append(result)
			}
			return results
		}

		let rootedTypeNames = Set(generatedRoots.map(\.root.typeDescription.asSource))
		// Deduplicate configuration types by type name across all roots.
		// With cycleEdges applied uniformly, every root produces the same struct
		// for a given type, so first-wins by alphabetical root order is stable.
		// Each type's struct is generated once, from the first root that reaches it:
		// the struct first-wins keeps, so the structs other roots would generate are
		// never generated.
		var seenTypeNames = Set<String>()
		var rootedConfigurationExtensions = [String: String]()
		var sharedConfigurationExtensions = [ConfigurationExtension]()
		for result in generatedRoots.sorted(by: { $0.root.typeDescription < $1.root.typeDescription }) {
			for configurationType in result.configurationTypes {
				let typeName = configurationType.concreteType.asSource
				if seenTypeNames.insert(typeName).inserted {
					let structCode = ScopeGenerator.generateConfigurationStruct(
						for: configurationType,
						cycleEdges: cycleEdges,
						sendableConfigurationTypeNames: sendableConfigurationTypeNames,
					)
					if rootedTypeNames.contains(typeName) {
						rootedConfigurationExtensions[typeName] = structCode
					} else {
						sharedConfigurationExtensions.append(ConfigurationExtension(typeName: typeName, structCode: structCode))
					}
				}
			}
		}

		let mergedGeneratedRoots = generatedRoots.map { result in
			let configurationCode = rootedConfigurationExtensions[result.root.typeDescription.asSource].map { structCode in
				generateMockConfigurationCode(
					configurationExtensions: [ConfigurationExtension(typeName: result.root.typeDescription.asSource, structCode: structCode)],
					mockConditionalCompilation: mockConditionalCompilation,
				)
			}
			let code = if let configurationCode, !configurationCode.isEmpty {
				result.root.code + "\n\n" + configurationCode.trimmingCharacters(in: .whitespacesAndNewlines)
			} else {
				result.root.code
			}
			return GeneratedRoot(
				typeDescription: result.root.typeDescription,
				sourceFilePath: result.root.sourceFilePath,
				code: code,
			)
		}

		let mockConfigurationCode: String? = if sharedConfigurationExtensions.isEmpty {
			nil
		} else {
			generateMockConfigurationCode(
				configurationExtensions: sharedConfigurationExtensions,
				mockConditionalCompilation: mockConditionalCompilation,
			)
		}

		return MockGenerationResult(
			generatedRoots: mergedGeneratedRoots,
			mockConfigurationCode: mockConfigurationCode,
		)
	}

	/// A mock root's generated code, with the nodes of the types whose `SafeDIMockConfiguration`
	/// struct its tree needs, in the order the root reaches them.
	private struct GeneratedMockRoot {
		let root: GeneratedRoot
		let configurationTypes: [ScopeGenerator.MockParameterNode]
	}

	/// A type's `SafeDIMockConfiguration` struct, emitted in an extension of the type.
	private struct ConfigurationExtension {
		let typeName: String
		let structCode: String
	}

	private func generateMockConfigurationCode(
		configurationExtensions: [ConfigurationExtension],
		mockConditionalCompilation: String?,
	) -> String {
		let extensions = configurationExtensions.map { configurationExtension in
			"extension \(configurationExtension.typeName) {\n\(configurationExtension.structCode)\n}"
		}
		let body = extensions.joined(separator: "\n\n")
		if let mockConditionalCompilation {
			return "#if \(mockConditionalCompilation)\n\(body)\n#endif\n"
		} else {
			return "\(body)\n"
		}
	}

	/// Computes the set of `(parent, child)` type-reference edges that, when removed,
	/// makes the global type graph acyclic. Walks the graph with a recursive DFS,
	/// starting from each node in alphabetical order; any edge into a node already
	/// on the active DFS stack is recorded as a back-edge. Determinism comes from
	/// sorted iteration over both roots and successors. Type graphs are typically
	/// shallow, so a recursive driver is fine; if very deep graphs surface in the
	/// future, switch to an iterative driver.
	private static func computeCycleEdges(
		in scopeMap: [TypeDescription: Scope],
	) -> Set<ScopeGenerator.CycleEdge> {
		var adjacency = [TypeDescription: [TypeDescription]]()
		for scope in Set(scopeMap.values) {
			let parent = scope.instantiable.concreteInstantiable
			for property in scope.propertiesToGenerate {
				if case let .instantiated(_, childScope, _) = property {
					adjacency[parent, default: []].append(childScope.instantiable.concreteInstantiable)
				}
			}
		}
		for key in adjacency.keys {
			adjacency[key] = adjacency[key]!.sorted { $0.asSource < $1.asSource }
		}

		let allNodes = Set(adjacency.keys)
			.union(adjacency.values.flatMap(\.self))
			.sorted { $0.asSource < $1.asSource }

		var visited = Set<TypeDescription>()
		var onStack = Set<TypeDescription>()
		var edges = Set<ScopeGenerator.CycleEdge>()

		func visit(_ node: TypeDescription) {
			visited.insert(node)
			onStack.insert(node)
			for neighbor in adjacency[node] ?? [] {
				if onStack.contains(neighbor) {
					edges.insert(ScopeGenerator.CycleEdge(
						parent: node.asSource,
						child: neighbor.asSource,
					))
				} else if !visited.contains(neighbor) {
					visit(neighbor)
				}
			}
			onStack.remove(node)
		}

		for node in allNodes where !visited.contains(node) {
			visit(node)
		}
		return edges
	}

	public func generateDOTTree() async throws -> String {
		let rootScopeGenerators = try rootScopeGenerators

		let dependencyTree = try await withThrowingTaskGroup(
			of: String.self,
			returning: String.self,
		) { taskGroup in
			for rootInfo in rootScopeGenerators {
				taskGroup.addTask { try await rootInfo.scopeGenerator.generateDOT() }
			}
			var generatedRoots = [String]()
			for try await generatedRoot in taskGroup {
				generatedRoots.append(generatedRoot)
			}
			return generatedRoots.removingEmpty().sorted().joined(separator: "\n\n")
		}

		return """
		\(dependencyTree)
		"""
	}

	// MARK: - DependencyTreeGeneratorError

	private enum DependencyTreeGeneratorError: SourceLocatedError {
		/// `fulfilledByMockOnlyDeclaration` is set when only a `mockOnly` declaration fulfills the type.
		case noInstantiableFound(TypeDescription, referencedBy: [LocatedProperty], fulfilledByMockOnlyDeclaration: Bool)
		case unfulfillableProperties([UnfulfillableProperty])
		/// Reported at each `@Received` declaration whose dependency a closer ancestor hides, with a note at the
		/// hiding declaration. See `HiddenReceivedProperty`.
		case hiddenReceivedProperties([HiddenReceivedProperty])
		case instantiableHasForwardedProperty(ForwardedPropertyViolation)
		/// Reported at the dependency declaration that closes the cycle – the `@Instantiated` or `@Received`
		/// property whose type is already on the instantiation stack, and which is not an `@Instantiated`
		/// instantiator – with a note at each member type’s `@Instantiable` declaration. See `DependencyCycle`.
		case constantDependencyCycleDetected(DependencyCycle, closingDependency: ClosingDependency)
		/// Reported at the `@Received` declaration on `directParent` that closes the cycle, with a note at each
		/// member type’s `@Instantiable` declaration. See `DependencyCycle`. `aliasProperty` is the declared property
		/// when that declaration is a `@Received(fulfilledByDependencyNamed:ofType:)` alias that `property` fulfills.
		case receivedInstantiatorDependencyCycleDetected(property: Property, aliasProperty: Property?, directParent: TypeDescription, cycle: DependencyCycle)
		/// Reported at the `@Received` declaration that closes the chain: the one that receives `instantiated` back
		/// inside the tree `instantiated` creates, or inside the tree of a sibling that the chain reaches. The
		/// properties can be of any type, `Instantiator`s included. No notes; the chain is spelled out in the message.
		/// `requiredOnlyIfAvailableAliases` are the `onlyIfAvailable` aliases a receive in the chain requires, in chain order.
		case dependencyReceivedInSameChainItIsInstantiated(instantiated: Property, receivedPropertyChain: [Property], declarationLocation: Dependency.DeclarationLocation?, lazilyInstantiatedProperties: [Property], requiredOnlyIfAvailableAliases: [RequiredOnlyIfAvailableAlias])
		/// Reported at the aliased dependency that closes the cycle: the one fulfilled by the first property in
		/// `aliasChain`, in which each aliased dependency of one type is fulfilled by the next and the last is the
		/// first again. No notes; the chain is spelled out in the message.
		case aliasedDependenciesFulfillOneAnother(aliasChain: [Property], declarationLocation: Dependency.DeclarationLocation?)
		/// Reported at the hand-written `mock` method of a type whose `mock()` this module also generates.
		case handWrittenMockSharesGeneratedMockName(TypeDescription, declaredAt: [Dependency.DeclarationLocation?], isGeneratedForAdditionalMocksToGenerate: Bool)

		var sourceDiagnostics: [SourceDiagnostic] {
			switch self {
			case let .handWrittenMockSharesGeneratedMockName(typeDescription, declaredAt, isGeneratedForAdditionalMocksToGenerate):
				// Sorted by location so the order never depends on map iteration.
				declaredAt
					.map {
						SourceDiagnostic(
							severity: .error,
							location: $0,
							message: Self.handWrittenMockSharesGeneratedMockNameMessage(
								typeDescription: typeDescription,
								isGeneratedForAdditionalMocksToGenerate: isGeneratedForAdditionalMocksToGenerate,
							),
						)
					}
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .noInstantiableFound(typeDescription, referencedBy, fulfilledByMockOnlyDeclaration):
				// Sorted by location so the order never depends on map iteration.
				referencedBy.map {
					SourceDiagnostic(
						severity: .error,
						location: $0.declarationLocation,
						message: Self.noInstantiableFoundMessage(
							typeDescription: typeDescription,
							referencingProperty: $0.property,
							fulfilledByMockOnlyDeclaration: fulfilledByMockOnlyDeclaration,
						),
					)
				}
				.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .unfulfillableProperties(unfulfillableProperties):
				unfulfillableProperties
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .hiddenReceivedProperties(hiddenReceivedProperties):
				hiddenReceivedProperties
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .instantiableHasForwardedProperty(violation):
				violation.sourceDiagnostics
			case let .constantDependencyCycleDetected(cycle, closingDependency):
				cycle.sourceDiagnostics(summary: "Dependency cycle: \(cycle.asSource). \(closingDependency.remedy)\(Self.lazilyInstantiatedHint(for: cycle.lazilyInstantiatedProperties))")
			case let .receivedInstantiatorDependencyCycleDetected(property, aliasProperty, directParent, cycle):
				if let aliasProperty {
					// The alias, not a declaration of `property`, is what `directParent` would declare as instantiated.
					cycle.sourceDiagnostics(summary: "Dependency cycle: \(cycle.asSource). `\(directParent.asSource)` receives `\(property.asSource)` as `\(aliasProperty.asSource)` inside the tree that `\(property.label)` builds. Declare `\(aliasProperty.asSource)` on `\(directParent.asSource)` as @\(Dependency.Source.instantiatedRawValue) instead of @\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:).")
				} else {
					cycle.sourceDiagnostics(summary: "Dependency cycle: \(cycle.asSource). `\(directParent.asSource)` receives `\(property.asSource)` inside the tree that `\(property.label)` builds. Declare `\(property.asSource)` on `\(directParent.asSource)` as @\(Dependency.Source.instantiatedRawValue) instead of @\(Dependency.Source.receivedRawValue).")
				}
			case let .dependencyReceivedInSameChainItIsInstantiated(instantiated, receivedPropertyChain, declarationLocation, lazilyInstantiatedProperties, requiredOnlyIfAvailableAliases):
				[
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "Dependency cycle: "
							+ "@\(Dependency.Source.instantiatedRawValue) `\(instantiated.asSource)` -> "
							+ receivedPropertyChain
							.map { "@\(Dependency.Source.receivedRawValue) `\($0.asSource)`" }
							.joined(separator: " -> ")
							+ ". `\(instantiated.asSource)` is received while it is still being instantiated. "
							// An alias received only if available says how to break the cycle at that alias.
							+ (requiredOnlyIfAvailableAliases.isEmpty
								? Self.onlyIfAvailableRemedy
								: requiredOnlyIfAvailableAliases.map(\.hint).joined(separator: " "))
							+ Self.lazilyInstantiatedHint(for: lazilyInstantiatedProperties),
					),
				]
			case let .aliasedDependenciesFulfillOneAnother(aliasChain, declarationLocation):
				[
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "Dependency cycle: each @\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:) dependency is fulfilled by the next: "
							+ aliasChain.map { "`\($0.asSource)`" }.joined(separator: " -> ")
							+ ". Change one of them to be fulfilled by a property outside this cycle.",
					),
				]
			}
		}

		/// How to break a cycle closed by a receive of a property that is still being built.
		fileprivate static let onlyIfAvailableRemedy = "Remove this @\(Dependency.Source.receivedRawValue) property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required."

		/// A sentence to end a cycle diagnostic with when lazily instantiated properties are on the cycle, or an
		/// empty string when none are. Cycle validation sees such a property as the constant it stands for, so the
		/// path in the diagnostic names that constant; this says so, and why the property does not break the cycle.
		private static func lazilyInstantiatedHint(for lazilyInstantiatedProperties: [Property]) -> String {
			guard !lazilyInstantiatedProperties.isEmpty else { return "" }
			let validatedAs = lazilyInstantiatedProperties
				.map { "`\($0.asSource)` is validated as `\($0.asValidatedForDependencyCycles.asSource)`" }
				.joined(separator: ", ")
			return " A lazily instantiated dependency is created once, so it cannot break a dependency cycle: \(validatedAs)."
		}

		private static func noInstantiableFoundMessage(
			typeDescription: TypeDescription,
			referencingProperty: Property,
			fulfilledByMockOnlyDeclaration: Bool,
		) -> String {
			let typeName = typeDescription.asSource
			let reference = "`\(typeName)`, which @\(Dependency.Source.instantiatedRawValue) property `\(referencingProperty.asSource)` instantiates"
			return if fulfilledByMockOnlyDeclaration {
				"No production @\(InstantiableVisitor.macroName) declaration fulfills \(reference). A `mockOnly: true` declaration fulfills it, but is used only to generate mocks. Add a production @\(InstantiableVisitor.macroName) declaration that fulfills `\(typeName)`."
			} else {
				"No @\(InstantiableVisitor.macroName) type or extension fulfills \(reference). Decorate `\(typeName)`, or an extension of it, with @\(InstantiableVisitor.macroName); list `\(typeName)` in the `fulfillingAdditionalTypes` of an @\(InstantiableVisitor.macroName) type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target."
			}
		}

		private static func handWrittenMockSharesGeneratedMockNameMessage(
			typeDescription: TypeDescription,
			isGeneratedForAdditionalMocksToGenerate: Bool,
		) -> String {
			let typeName = typeDescription.asSource
			return if isGeneratedForAdditionalMocksToGenerate {
				"`\(typeName)` cannot have a hand-written `mock()` method because this module generates a `mock()` method for it (it is listed in `additionalMocksToGenerate`), and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@\(InstantiableVisitor.macroName)` that declares it, or remove `\(typeName)` from `additionalMocksToGenerate`."
			} else {
				"`\(typeName)` cannot have a hand-written `mock()` method because it is decorated with `@\(InstantiableVisitor.macroName)(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@\(InstantiableVisitor.macroName)` that declares it."
			}
		}

		/// A constant or lazily instantiated `@Instantiated` dependency whose type has `@Forwarded` properties, which
		/// only an instantiator is passed.
		struct ForwardedPropertyViolation {
			let dependency: Dependency
			/// The type the dependency builds.
			let instantiable: Instantiable
			/// The type with which the dependency can instead build `instantiable`.
			let suggestedPropertyType: TypeDescription
			let forwardedDeclarations: [LocatedProperty]
			/// The type that declares the dependency.
			let parent: TypeDescription

			/// An `error:` line at the dependency, and a `note:` at each `@Forwarded` declaration.
			var sourceDiagnostics: [SourceDiagnostic] {
				[
					SourceDiagnostic(
						severity: .error,
						location: dependency.declarationLocation,
						message: "`\(dependency.property.asSource)` on `\(parent.asSource)` cannot build `\(instantiable.concreteInstantiable.asSource)`, which has @\(Dependency.Source.forwardedRawValue) properties that only an instantiator is passed. Declare it as `\(suggestedPropertyType.asSource)`.",
					),
				] + forwardedDeclarations.map {
					SourceDiagnostic(
						severity: .note,
						location: $0.declarationLocation,
						message: "@\(Dependency.Source.forwardedRawValue) property `\($0.property.asSource)` is declared here",
					)
				}
			}
		}

		/// A property together with where it is declared.
		struct LocatedProperty: Hashable {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
		}

		/// A `@Received(fulfilledByDependencyNamed:ofType:onlyIfAvailable: true)` property that a type receives without
		/// `onlyIfAvailable`. That receive needs the alias created, so the type is built after `fulfillingProperty`.
		struct RequiredOnlyIfAvailableAlias: Hashable {
			let property: Property
			let fulfillingProperty: Property

			/// The sentences that end the error for a cycle the receive closes, in place of the general remedy, and say
			/// how to break it: received only if available, the alias is `nil` where its fulfilling property is not
			/// built first, as the manual describes.
			var hint: String {
				"`\(property.asSource)` renames `\(fulfillingProperty.asSource)` only if available, so a type that receives `\(property.label)` without `onlyIfAvailable` must be built after `\(fulfillingProperty.asSource)`. Receive `\(property.label)` with `@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)` to be passed `nil` where `\(fulfillingProperty.asSource)` cannot be built first."
			}
		}

		struct UnfulfillableProperty: Hashable {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The range of the declared identifier, which a fix-it renames when exactly one near-match has the same type.
			let identifierRange: Dependency.SourceRange?
			/// The range of the declared type, which a fix-it rewrites when exactly one near-match has the same label.
			let typeAnnotationRange: Dependency.SourceRange?
			/// The range of a bare `@Received` attribute, which a fix-it rewrites to `@Received(onlyIfAvailable: true)`.
			let bareAttributeRange: Dependency.SourceRange?
			let instantiable: Instantiable
			/// The types that instantiate `instantiable`, innermost first, excluding `root`.
			let parentStack: [TypeDescription]
			let root: TypeDescription
			let suggestedAlternatives: [Property]
			/// The `@Received(onlyIfAvailable: true)` alias that declares `property` where `instantiable` receives it,
			/// when that alias is not created because its fulfilling property is unavailable. `nil` otherwise.
			let uncreatedAlias: UncreatedAlias?

			/// An `@Received(onlyIfAvailable: true)` alias that is not created because its fulfilling property is unavailable.
			struct UncreatedAlias: Hashable {
				/// The type that declares the alias.
				let declaringType: TypeDescription
				let fulfillingProperty: Property
			}

			/// A single `error:` line. The suggestion or fix hint is folded into it rather than emitted as a
			/// `note:` because it belongs at the same location, and Xcode drops notes from build-tool output.
			var sourceDiagnostics: [SourceDiagnostic] {
				let chain = ([instantiable.concreteInstantiable] + parentStack + [root]).reversed()
				let summary = "@\(Dependency.Source.receivedRawValue) property `\(property.asSource)` is not @\(Dependency.Source.instantiatedRawValue) or @\(Dependency.Source.forwardedRawValue) in chain: \(chain.map(\.asSource).joined(separator: " -> "))"
				// A diagnostic carries at most one fix-it – Xcode offers no Apply at all for a diagnostic with several –
				// and a fix-it is offered only when it is exactly the repair the hint names.
				let hint: String
				let fixIts: [SourceDiagnostic.FixIt]
				if let uncreatedAlias {
					// The alias's property is optional, as `onlyIfAvailable` requires, so a receive of it can be `onlyIfAvailable` too.
					hint = "`\(property.asSource)` is created by `\(uncreatedAlias.declaringType.asSource)` only if `\(uncreatedAlias.fulfillingProperty.asSource)` is available, and `\(uncreatedAlias.fulfillingProperty.asSource)` is not @\(Dependency.Source.instantiatedRawValue) or @\(Dependency.Source.forwardedRawValue) in chain. Did you mean to receive this property with `onlyIfAvailable: true`?"
					// The range is recorded only for a bare attribute, so rewriting it never discards arguments the user wrote.
					fixIts = if let bareAttributeRange {
						[SourceDiagnostic.FixIt(range: bareAttributeRange, replacement: "@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)")]
					} else {
						[]
					}
				} else if property.typeDescription.isOptional,
				          let nonOptionalAlternative = suggestedAlternatives.first(where: { alternative in
				          	alternative.label == property.label
				          		&& alternative.typeDescription == property.typeDescription.unwrapped
				          })
				{
					let onlyIfAvailableAttribute = "@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)"
					hint = "The non-optional `\(nonOptionalAlternative.asSource)` is available in chain. Did you mean to decorate this property with `\(onlyIfAvailableAttribute)`?"
					// The range is recorded only for a bare attribute, so rewriting it never discards arguments the user wrote.
					fixIts = if let bareAttributeRange {
						[SourceDiagnostic.FixIt(range: bareAttributeRange, replacement: onlyIfAvailableAttribute)]
					} else {
						[]
					}
				} else if suggestedAlternatives.isEmpty {
					hint = "Declare `@\(Dependency.Source.instantiatedRawValue) let \(property.asSource)` on `\(root.asSource)` or on another type in the chain to fix."
					fixIts = []
				} else if suggestedAlternatives.count == 1 {
					let suggestedAlternative = suggestedAlternatives[0]
					hint = "Did you mean `\(suggestedAlternative.asSource)`?"
					// The suggestion list mixes same-type and same-label near-matches, and a single-token edit repairs the
					// property only when exactly one of label and type differs: a differing label is renamed and a differing
					// type is rewritten. Both differing gets no fix-it, and neither differing cannot happen, since the property
					// would then be fulfilled. A rename is offered only when the type is exactly what fulfillment compares
					// after normalization – a module-qualified spelling is not unified by normalization, so a rename there
					// would leave the property unfulfilled.
					fixIts = if suggestedAlternative.label != property.label,
					            suggestedAlternative.typeDescription == property.typeDescription,
					            let identifierRange
					{
						[SourceDiagnostic.FixIt(range: identifierRange, replacement: suggestedAlternative.label)]
					} else if suggestedAlternative.label == property.label,
					          let typeAnnotationRange
					{
						[SourceDiagnostic.FixIt(range: typeAnnotationRange, replacement: suggestedAlternative.typeDescription.asSource)]
					} else {
						[]
					}
				} else {
					hint = "Did you mean one of \(suggestedAlternatives.map { "`\($0.asSource)`" }.joined(separator: ", "))?"
					// Several candidates leave the choice to the user.
					fixIts = []
				}
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "\(summary). \(hint)",
						fixIts: fixIts,
					),
				]
			}
		}

		/// A property an ancestor declares, which the generated code names by its label everywhere below that ancestor.
		struct LabelDeclaration: Hashable {
			let property: Property
			/// The by-value property with which types further down the tree receive the instance of `property`,
			/// when `property` is lazily instantiated and offers one.
			let lazilyInstantiatedInstanceProperty: Property?
			let declarationLocation: Dependency.DeclarationLocation?
			let declaringType: TypeDescription
		}

		/// A received dependency the generated code cannot pass, because a closer ancestor declares another property
		/// with the same label – for example, an alias that retypes the dependency and keeps its label – and the generated
		/// code names a dependency by its label.
		struct HiddenReceivedProperty: Hashable {
			/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The closest declaration of the label, whose property differs from `property`.
			let hidingDeclaration: LabelDeclaration
			let receiver: TypeDescription
			/// The types that instantiate `receiver`, innermost first, excluding `root`.
			let parentStack: [TypeDescription]
			let root: TypeDescription

			/// An `error:` line that names the hiding declaration, since Xcode drops notes from build-tool output, and
			/// a `note:` at the hiding declaration so command-line builds can navigate to it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let chain = ([receiver] + parentStack + [root]).reversed()
				let hidingProperty = hidingDeclaration.property.asSource
				let declaringType = hidingDeclaration.declaringType.asSource
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue) property `\(property.asSource)` is hidden in chain: \(chain.map(\.asSource).joined(separator: " -> ")). `\(declaringType)` declares `\(hidingProperty)` with the same label, so the types below `\(declaringType)` receive `\(hidingProperty)` instead. Give `\(hidingProperty)` on `\(declaringType)` a different label to fix.",
					),
					SourceDiagnostic(
						severity: .note,
						location: hidingDeclaration.declarationLocation,
						message: "`\(hidingProperty)` is declared here",
					),
				]
			}
		}

		/// The dependency declaration that closes a constant dependency cycle, at which the cycle is reported.
		enum ClosingDependency {
			/// A dependency the declaring type instantiates, as declared.
			case instantiated(Property)
			/// A dependency `receiver` receives, as declared, while the property it is fulfilled by is still being built.
			case received(Property, receiver: TypeDescription)

			/// The sentence that tells the user how to break the cycle at this declaration.
			var remedy: String {
				switch self {
				case let .instantiated(property):
					"SafeDI accepts a dependency cycle only if the dependency that closes it is an @\(Dependency.Source.instantiatedRawValue) instantiator, such as an `\(Dependency.instantiatorType)` or `\(Dependency.erasedInstantiatorType)`, which builds its type each time it is called. Change `\(property.asSource)` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too."
				case let .received(property, receiver):
					"`\(receiver.asSource)` receives `\(property.asSource)`, which is still being built when `\(receiver.asSource)` is built. \(DependencyTreeGeneratorError.onlyIfAvailableRemedy)"
				}
			}
		}

		/// A dependency cycle. The error is reported at the dependency declaration that closes the cycle – the edge
		/// whose target type is already on the instantiation stack when validation reaches it – because that is the
		/// property the user changes (to an `Instantiator`, or from `@Received` to `@Instantiated`) to break the cycle.
		/// Each member type gets a note at its `@Instantiable` declaration so every file involved is navigable.
		struct DependencyCycle {
			/// The location of the dependency declaration whose target type is already on the instantiation stack.
			let declarationLocation: Dependency.DeclarationLocation?
			/// A type in the cycle together with the location of the `@Instantiable` declaration fulfilling it.
			struct Member: Hashable {
				let typeDescription: TypeDescription
				/// `nil` when no `@Instantiable` is registered for the type.
				let declarationLocation: Dependency.DeclarationLocation?
			}

			/// The property types in the cycle, innermost first.
			let members: [Member]
			/// The lazily instantiated properties on the cycle as they are declared, outermost first.
			/// Validation sees each as the constant it stands for, which is what `members` holds.
			let lazilyInstantiatedProperties: [Property]

			var asSource: String {
				members
					.map { "`\($0.typeDescription.asSource)`" }
					.reversed()
					.joined(separator: " -> ")
			}

			func sourceDiagnostics(summary: String) -> [SourceDiagnostic] {
				var notedDeclarationLocations = Set<Dependency.DeclarationLocation>()
				let notes: [SourceDiagnostic] = members.reversed().compactMap { member in
					guard let declarationLocation = member.declarationLocation,
					      notedDeclarationLocations.insert(declarationLocation).inserted
					else { return nil }
					return SourceDiagnostic(
						severity: .note,
						location: declarationLocation,
						message: "`\(member.typeDescription.asInstantiatedType.asSource)` is part of the cycle",
					)
				}
				return [SourceDiagnostic(severity: .error, location: declarationLocation, message: summary)] + notes
			}
		}
	}

	// MARK: Private

	private let importStatements: [ImportStatement]
	private let mockImportStatements: [ImportStatement]
	private let typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
	private let aliasDeclarationReferences: AliasDeclarationReferences
	private struct RootScopeInfo {
		let typeDescription: TypeDescription
		let sourceFilePath: String?
		let scopeGenerator: ScopeGenerator
	}

	/// The scopes of the dependency tree `rootScopeGenerators` last built and validated, which
	/// `generateWarnings()` analyzes. Empty until the tree has been generated.
	private var validatedScopes = Set<Scope>()

	private var rootScopeGenerators: [RootScopeInfo] {
		get throws {
			let rootScopeGenerators: [RootScopeInfo] = try {
				try validateReachableTypeDescriptions()

				let typeDescriptionToScopeMap = try createTypeDescriptionToScopeMapping()
				var receivedPropertiesCache = ReceivedPropertiesCache()
				try validatePropertiesAreFulfillable(
					typeDescriptionToScopeMap: typeDescriptionToScopeMap,
					receivedPropertiesCache: &receivedPropertiesCache,
					cyclesOnly: false,
				)
				// The walk above does not follow a received `Instantiator` to the scope it builds,
				// so it misses siblings that capture one another; report them now that it has passed.
				// A root is enclosed by no scope.
				var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation(scopes: typeDescriptionToScopeMap.values)
				try Self.validateChildrenDoNotRequireEachOther(
					inTreesRootedAt: rootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] }.map { ($0, []) },
					cache: &receivedPropertiesCache,
					validation: &childrenRequiringEachOtherValidation,
				)
				self.validatedScopes = Set(typeDescriptionToScopeMap.values)
				return try rootInstantiables
					.sorted()
					.compactMap { typeDescription in
						try typeDescriptionToScopeMap[typeDescription].map { scope in
							try RootScopeInfo(
								typeDescription: typeDescription,
								sourceFilePath: typeDescriptionToFulfillingInstantiableMap[typeDescription]?.sourceFilePath,
								scopeGenerator: scope.createScopeGenerator(
									for: nil,
									propertyStack: [],
									receivableProperties: [],
									lazilyInstantiatedInstanceProperties: [],
									erasedToConcreteExistential: false,
								),
							)
						}
					}
			}()
			return rootScopeGenerators
		}
	}

	private static func fileHeader(importing importStatements: [ImportStatement]) -> String {
		let imports = imports(importStatements)
		let importsWhitespace = imports.isEmpty ? "" : "\n"
		return "// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.\n// Any modifications made to this file will be overwritten on subsequent builds.\n// Please refrain from editing this file directly.\n\(importsWhitespace)\(imports)\(importsWhitespace)\n"
	}

	private static func imports(_ importStatements: [ImportStatement]) -> String {
		importStatements
			.reduce(into: [String: Set<ImportStatement>]()) { partialResult, importStatement in
				var importsForModuleName = partialResult[importStatement.moduleName, default: []]
				importsForModuleName.insert(importStatement)
				partialResult[importStatement.moduleName] = importsForModuleName
			}
			.flatMap {
				// A module imported whole in several ways is imported the way that asks for least: without
				// attributes if any file imports it so, and otherwise with the attributes that sort first,
				// which puts `@testable`, an error where the module is not built for testing, after the others.
				if let wholeModuleImport = $0.value
					.filter({ $0.kind.isEmpty && $0.type.isEmpty })
					.min(by: { $0.attributeToGenerate < $1.attributeToGenerate })
				{
					[wholeModuleImport]
				} else {
					Array($0.value)
				}
			}
			.map {
				"""
				#if canImport(\($0.moduleName))
				\($0.asSource)
				#endif
				"""
			}
			.sorted()
			.joined(separator: "\n")
	}

	/// Creates a mock-root ScopeGenerator using the production Scope tree.
	/// Unsatisfied received dependencies are promoted as root-level children
	/// on a NEW Scope (the shared Scope is never mutated).
	/// - Parameter cache: The results of `collectReceivedProperties` for scopes of `typeDescriptionToScopeMap`,
	///   shared across mock roots. The mock root's own scope never enters it: nothing instantiates the mock
	///   root, so only its children's results are collected.
	/// - Parameter childrenRequiringEachOtherValidation: The scopes whose children are already known not to
	///   require one another; see `validateChildrenDoNotRequireEachOther`.
	private func createMockRootScopeGenerator(
		for instantiable: Instantiable,
		scope: Scope,
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		erasedToConcreteTypeMap: [TypeDescription: TypeDescription],
		receivedPropertiesCache cache: inout ReceivedPropertiesCache,
		childrenRequiringEachOtherValidation: inout ChildrenRequiringEachOtherValidation,
	) throws -> ScopeGenerator {
		// Recursively collect all transitive received properties from the scope tree
		// and any promoted scopes' subtrees. Results are cached per Scope identity
		// (via ObjectIdentifier) so each scope outside a cycle is visited at most once.
		let initialReceivedProperties = Self.collectReceivedProperties(
			from: scope,
			cache: &cache,
		)
		let initialReceived = initialReceivedProperties.received
		let initialOnlyIfAvailable = initialReceivedProperties.onlyIfAvailable

		// Worklist: promoted scopes may introduce additional transitive received properties.
		// Only required properties are walked: a property received only if available becomes
		// an optional mock parameter with no default construction, so its transitive
		// dependencies don't need promoting. A property is required when any receiver in the
		// root's tree or in a promoted scope's tree requires it, even if others receive it
		// only if available.
		var allReceived = initialReceived
		var allOnlyIfAvailable = initialOnlyIfAvailable
		var allRequired = initialReceived.subtracting(initialOnlyIfAvailable)
		var visitedTypes = Set<TypeDescription>()
		var worklist = Array(allRequired)

		/// The concrete type the mock builds `property` from when no `@Instantiable` fulfills its type. A lazily
		/// instantiated property is built from the type its instance is erased from, whichever form declares
		/// the erasure and whether or not the property is optional.
		func concreteTypeErased(to property: Property) -> TypeDescription? {
			erasedToConcreteTypeMap[property.typeDescription]
				?? property.asLazilyInstantiatedInstanceProperty.flatMap { erasedToConcreteTypeMap[$0.typeDescription] }
		}
		while let property = worklist.popLast() {
			var dependencyType = property.typeDescription.asInstantiatedType
			if typeDescriptionToScopeMap[dependencyType] == nil,
			   let concreteType = concreteTypeErased(to: property)
			{
				dependencyType = concreteType
			}
			guard let promotedScope = typeDescriptionToScopeMap[dependencyType],
			      Self.mockCanBuild(property, from: promotedScope),
			      visitedTypes.insert(dependencyType).inserted
			else { continue }

			let scopeReceivedProperties = Self.collectReceivedProperties(
				from: promotedScope,
				cache: &cache,
			)
			let scopeReceived = scopeReceivedProperties.received
			let scopeOnlyIfAvailable = scopeReceivedProperties.onlyIfAvailable
			allReceived.formUnion(scopeReceived)
			allOnlyIfAvailable.formUnion(scopeOnlyIfAvailable)
			for newProperty in scopeReceived.subtracting(scopeOnlyIfAvailable) where allRequired.insert(newProperty).inserted {
				worklist.append(newProperty)
			}
		}
		allOnlyIfAvailable.subtract(allRequired)

		// Promote all received properties that have scopes.
		// onlyIfAvailable dependencies are NOT promoted — they become optional
		// mock parameters with no default.
		// Filter out forwarded properties — they're bare mock parameters, not promoted children.
		// ScopeData.root doesn't carry forwardedProperties, so receivedProperties doesn't
		// subtract them. We filter them here instead.
		// A forwarded lazily instantiated property also provides the by-value property that reads its instance.
		let forwardedProperties = instantiable.forwardedReceivableProperties
		let mockRootScope = Scope(instantiable: instantiable)
		mockRootScope.propertiesToGenerate = scope.propertiesToGenerate

		/// The scope that builds a received property promoted to the mock root, when the mock can build one.
		/// A received dependency the mock cannot build stays received: the root's `mock()` takes it as a parameter.
		func scopeToPromote(for receivedProperty: Property) -> (scope: Scope, erasedToConcreteExistential: Bool)? {
			let dependencyType = receivedProperty.typeDescription.asInstantiatedType
			let scopeOfReceivedProperty: (scope: Scope, erasedToConcreteExistential: Bool)? = if let receivedScope = typeDescriptionToScopeMap[dependencyType] {
				(receivedScope, false)
			} else if let concreteType = concreteTypeErased(to: receivedProperty),
			          let receivedScope = typeDescriptionToScopeMap[concreteType]
			{
				(receivedScope, true)
			} else {
				nil
			}
			guard let scopeOfReceivedProperty, Self.mockCanBuild(receivedProperty, from: scopeOfReceivedProperty.scope) else {
				return nil
			}
			return scopeOfReceivedProperty
		}

		// A dependency the tree receives both as `LazilyInstantiated` and by value is one dependency. It is
		// promoted once, as the lazily instantiated property, whenever any receiver requires it in either form;
		// receivers of its instance read it from that property. The same holds for a lazily instantiated
		// property the mock root declares itself, which needs no promotion.
		var lazilyInstantiatedPropertiesToPromote = Set<Property>()
		var instancePropertiesOfLazilyInstantiatedProperties = Set(scope.propertiesToGenerate.compactMap(\.lazilyInstantiatedInstanceProperty))
		for receivedProperty in allReceived {
			guard let instanceProperty = receivedProperty.asLazilyInstantiatedInstanceProperty else { continue }
			let lazilyInstantiatedProperty = receivedProperty.asUnwrappedProperty
			guard allRequired.contains(lazilyInstantiatedProperty) || allRequired.contains(instanceProperty),
			      scopeToPromote(for: lazilyInstantiatedProperty) != nil
			else { continue }
			lazilyInstantiatedPropertiesToPromote.insert(lazilyInstantiatedProperty)
			instancePropertiesOfLazilyInstantiatedProperties.insert(instanceProperty)
		}

		// Track promoted (label, type) pairs to prevent duplicate promotions when
		// both required and onlyIfAvailable versions of the same dep exist.
		// Property.< sorts non-optional before optional, so the required version
		// wins and the optional version is skipped.
		var promotedLabelAndTypes = Set<String>()
		for receivedProperty in allReceived.union(lazilyInstantiatedPropertiesToPromote).sorted() {
			// A forwarded `x: X` fulfills an `x: X?` too.
			guard lazilyInstantiatedPropertiesToPromote.contains(receivedProperty) || !allOnlyIfAvailable.contains(receivedProperty),
			      !forwardedProperties.contains(receivedProperty),
			      !forwardedProperties.contains(receivedProperty.asUnwrappedProperty),
			      !instancePropertiesOfLazilyInstantiatedProperties.contains(receivedProperty)
			else { continue }

			let labelAndType = "\(receivedProperty.label):\(receivedProperty.typeDescription.asInstantiatedType.asSource)"
			guard promotedLabelAndTypes.insert(labelAndType).inserted else { continue }

			guard let (receivedScope, erasedToConcreteExistential) = scopeToPromote(for: receivedProperty) else {
				continue
			}
			mockRootScope.propertiesToGenerate.append(.instantiated(
				receivedProperty,
				receivedScope,
				erasedToConcreteExistential: erasedToConcreteExistential,
			))
		}

		// Validate the promoted mock scope for cycles before generating code.
		// This catches cycles that only become visible after @Received dependencies
		// are promoted to the mock root (e.g., B @Receives Instantiator<A> where A
		// instantiates B — the promotion creates a cycle in the mock root scope).
		try validateMockRootScopeForCycles(
			mockRootScope,
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
		)
		// Promotion can also make the mock root's children require one another
		// (e.g., C @Receives B while B's subtree @Receives C — each must be built
		// first), which no ancestor stack shows. Detecting that is cheap; production's
		// walk, which follows received dependencies between scopes, then reports the
		// cycle. Running that walk on every mock root instead would add a
		// received-dependency walk for every node of every mock tree.
		// The mock root binds every received property it does not promote, which encloses its whole tree.
		let mockRootEnclosingProvidedProperties = childrenRequiringEachOtherValidation.enclosingProvidedProperties(
			ofMockRoot: mockRootScope,
			receivedProperties: allReceived,
		)
		let mockRootChildrenRequiringEachOther = Self.childrenRequiringEachOther(
			in: mockRootScope,
			enclosingProvidedProperties: mockRootEnclosingProvidedProperties,
			cache: &cache,
		)
		try validatePropertiesAreFulfillable(
			onRootScopes: mockRootChildrenRequiringEachOther != nil ? [ValidatedRootScope(scope: mockRootScope, boundProperties: allReceived)] : [],
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: true,
		)
		// That walk does not follow a received `Instantiator` to the scope it builds, and
		// promoted scopes' trees are walked by no validation, so report what it leaves:
		// aliases that fulfill one another and children, here or anywhere in the mock tree,
		// that require one another, in the order `validateChildrenDoNotRequireEachOther`
		// checks them. The mock root's own children were checked above, so only their
		// trees are left.
		if let aliasesFulfillingOneAnother = Self.aliasesFulfillingOneAnother(in: mockRootScope) {
			throw aliasesFulfillingOneAnother.error
		} else if let mockRootChildrenRequiringEachOther {
			throw mockRootChildrenRequiringEachOther.error
		} else {
			var mockRootChildScopes = [(scope: Scope, enclosingProvidedProperties: Set<Property>)]()
			for case let .instantiated(childProperty, childScope, _) in mockRootScope.propertiesToGenerate {
				mockRootChildScopes.append((
					childScope,
					childrenRequiringEachOtherValidation.enclosingProvidedProperties(
						ofChild: childProperty,
						of: mockRootScope,
						enclosingProvidedProperties: mockRootEnclosingProvidedProperties,
					),
				))
			}
			try Self.validateChildrenDoNotRequireEachOther(
				inTreesRootedAt: mockRootChildScopes,
				cache: &cache,
				validation: &childrenRequiringEachOtherValidation,
			)
		}

		// Build the final ScopeGenerator once. The mock root binds every received
		// property it does not promote — as a `mock()` parameter or a `SafeDIOverrides`
		// entry — so each is receivable throughout the tree.
		return try mockRootScope.createScopeGenerator(
			for: nil,
			propertyStack: [],
			receivableProperties: [],
			lazilyInstantiatedInstanceProperties: [],
			boundProperties: allReceived,
			erasedToConcreteExistential: false,
			forMockGeneration: true,
		)
	}

	/// Whether a mock can build the received `property` from `scope` when it promotes the property to a
	/// child of the mock root. A type with `@Forwarded` properties can be built only by an `Instantiator`
	/// that is handed the forwarded values, so a mock cannot build a constant of that type, or lazily
	/// instantiate one: as in production, where such a property is never `@Instantiated`, it must be received.
	private static func mockCanBuild(_ property: Property, from scope: Scope) -> Bool {
		!(property.propertyType.isConstant || property.propertyType.isLazilyInstantiated)
			|| !scope.instantiable.dependencies.contains(where: \.isForwarded)
	}

	/// Walks a post-promotion mock root scope for dependency cycles.
	/// The mock root scope has @Received dependencies promoted as children,
	/// which can create cycles not visible in the pre-promotion scope.
	private func validateMockRootScopeForCycles(
		_ scope: Scope,
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		propertyStack: [Property] = [],
		lazilyInstantiatedDeclarations: [Property: Property] = [:],
	) throws {
		// Check dependencies for cycles (catches @Received references back to ancestors).
		for dependency in scope.instantiable.dependencies where dependency.canCloseDependencyCycle {
			let declaredPropertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
			let propertyForDependency = declaredPropertyForDependency.asValidatedForDependencyCycles
			guard let cycleIndex = propertyStack.firstIndex(of: propertyForDependency) else {
				continue
			}
			let propertiesInCycle = [propertyForDependency] + propertyStack[0...cycleIndex]
			let closingReceive = Self.closingReceive(of: dependency, in: scope)
			try throwIfInvalidCycle(
				typesInCycle: propertiesInCycle.map(\.typeDescription),
				property: propertyForDependency,
				// A receive is reported as declared; an instantiation as the property it instantiates.
				declaredProperty: closingReceive == nil ? declaredPropertyForDependency : dependency.property,
				declarationLocation: dependency.declarationLocation,
				directParent: scope.instantiable.concreteInstantiable,
				closingReceive: closingReceive,
				lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
					closingCycleWith: declaredPropertyForDependency,
					validatedPropertiesInCycle: propertiesInCycle,
					lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
				),
			)
		}

		// Recurse into children.
		for childPropertyToGenerate in scope.propertiesToGenerate {
			switch childPropertyToGenerate {
			case let .instantiated(declaredChildProperty, childScope, _):
				let childProperty = declaredChildProperty.asValidatedForDependencyCycles
				guard !propertyStack.contains(childProperty) else { continue }
				let nextStack = [childProperty] + propertyStack
				try validateMockRootScopeForCycles(
					childScope,
					typeDescriptionToScopeMap: typeDescriptionToScopeMap,
					propertyStack: nextStack,
					lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
				)
			case .aliased:
				break
			}
		}
	}

	/// Instantiated children of one scope that require one another in a cycle: each child's tree requires
	/// (not `onlyIfAvailable`) the next child, and the last child's tree requires the first.
	private struct ChildrenRequiringEachOther {
		/// The first child in the cycle.
		let instantiated: Property
		/// The property through which each child's tree receives the next child, ending with the one through
		/// which the last child's tree receives the first: the next child's property, or an alias of it that
		/// the scope declares.
		let receivedPropertyChain: [Property]
		/// The scope of the last child in the cycle, whose tree receives the first child.
		let lastChildScope: Scope
		/// The `onlyIfAvailable` aliases the scope declares that `receivedPropertyChain` holds, in chain order.
		let requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]

		/// The error reporting these children, at the receiver found by `requiredReceiver`. When the last
		/// child's tree receives the first child through an alias or unwrapped, the chain ends with the
		/// first child's own property, so it reads back to where it started.
		var error: DependencyTreeGeneratorError {
			DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
				instantiated: instantiated,
				receivedPropertyChain: receivedPropertyChain + (receivedPropertyChain[receivedPropertyChain.count - 1] == instantiated ? [] : [instantiated]),
				declarationLocation: DependencyTreeGenerator.requiredReceiver(
					of: receivedPropertyChain[receivedPropertyChain.count - 1],
					inTreeOf: lastChildScope,
				)?.declarationLocation,
				// The chain names every property as it is declared, so there is nothing to explain.
				lazilyInstantiatedProperties: [],
				requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases,
			)
		}
	}

	/// What `childrenRequiringEachOther` needs to know about the scopes enclosing a scope: which of the properties
	/// in `onlyIfAvailableAliasProperties` they provide to it. An `onlyIfAvailable` alias a scope declares is created
	/// for a receiver that requires it, after its fulfilling property, only when no enclosing scope provides its
	/// property; otherwise the receiver is handed the enclosing scope's property, as
	/// `Scope.createScopeGenerator`'s `isProvidedByEnclosingScope` has generation do.
	private struct ChildrenRequiringEachOtherValidation {
		/// The property of every `onlyIfAvailable` alias of the scopes validated, and its unwrapped form. Only these
		/// are recorded as provided by enclosing scopes, so that a scope is validated once for each way its
		/// enclosing scopes can affect the result, rather than once for every path that reaches it.
		let onlyIfAvailableAliasProperties: Set<Property>
		/// The scopes whose children, and whose trees' children, are known not to require one another, each with
		/// the `onlyIfAvailableAliasProperties` its enclosing scopes provide to it.
		var validatedScopes = Set<ValidatedScope>()

		init(scopes: some Sequence<Scope>) {
			var onlyIfAvailableAliasProperties = Set<Property>()
			for scope in scopes {
				for case let (property, .aliased(_, _, onlyIfAvailable: true)) in scope.instantiable.dependencies.lazy.map({ ($0.property, $0.source) }) {
					onlyIfAvailableAliasProperties.insert(property)
					onlyIfAvailableAliasProperties.insert(property.asUnwrappedProperty)
				}
			}
			self.onlyIfAvailableAliasProperties = onlyIfAvailableAliasProperties
		}

		/// The `onlyIfAvailableAliasProperties` that the mock root `mockRootScope`, whose tree and promoted scopes'
		/// trees receive `receivedProperties`, binds. Promotion collects what a promoted scope's tree receives without
		/// subtracting what the mock root declares, and the mock root binds nothing for a property it declares itself.
		func enclosingProvidedProperties(
			ofMockRoot mockRootScope: Scope,
			receivedProperties: Set<Property>,
		) -> Set<Property> {
			onlyIfAvailableAliasProperties
				.intersection(receivedProperties)
				.subtracting(mockRootScope.createdProperties)
		}

		/// The `onlyIfAvailableAliasProperties` provided to the child `childProperty` of `scope`, to which
		/// `scope`'s enclosing scopes provide `enclosingProvidedProperties`: those and the ones `scope` creates,
		/// except the child's own, which is still being built inside it. The instance of a lazily instantiated
		/// property does not count: it is read from that property, which an alias's label hides.
		func enclosingProvidedProperties(
			ofChild childProperty: Property,
			of scope: Scope,
			enclosingProvidedProperties: Set<Property>,
		) -> Set<Property> {
			enclosingProvidedProperties
				.union(scope.createdProperties.intersection(onlyIfAvailableAliasProperties))
				.subtracting(scope.instantiable.dependencies.compactMap(\.lazilyInstantiatedInstanceProperty))
				.subtracting([childProperty])
		}

		struct ValidatedScope: Hashable {
			let scope: Scope
			let enclosingProvidedProperties: Set<Property>
		}
	}

	/// The instantiated children of `scope` that require one another in a cycle, if any:
	/// each child's tree requires (not `onlyIfAvailable`) a sibling that, directly or
	/// through other siblings, requires it. Such children cannot be ordered so that each
	/// is built after the siblings it receives — whatever their property types, since an
	/// `Instantiator` captures what its tree receives when it is created.
	/// - Parameter enclosingProvidedProperties: The properties of `onlyIfAvailable` aliases, and their unwrapped
	///   forms, that the scopes enclosing `scope` provide to it (see `ChildrenRequiringEachOtherValidation`).
	private static func childrenRequiringEachOther(
		in scope: Scope,
		enclosingProvidedProperties: Set<Property>,
		cache: inout ReceivedPropertiesCache,
	) -> ChildrenRequiringEachOther? {
		var children = [(property: Property, scope: Scope)]()
		for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
			children.append((property, childScope))
		}
		// A lazily instantiated child is also received by value, as the instance it creates.
		var childIndexByProperty = [Property: Int]()
		for (index, child) in children.enumerated() {
			childIndexByProperty[child.property] = index
			if let instanceProperty = child.property.asLazilyInstantiatedInstanceProperty {
				childIndexByProperty[instanceProperty] = index
			}
		}
		// A child's tree that requires an alias the scope declares requires the child the alias is assigned
		// from, directly or through other aliases the scope declares. An `onlyIfAvailable` alias is created for
		// a receiver that requires it, so it is assigned after that child too, unless an enclosing scope provides
		// its property, which the receiver is then handed instead.
		var aliases = [AliasedDependency]()
		var onlyIfAvailableAliasFulfillingPropertyByProperty = [Property: Property]()
		for case let .aliased(property, fulfillingProperty, _, onlyIfAvailable, _) in scope.propertiesToGenerate
			where !onlyIfAvailable || enclosingProvidedProperties.isDisjoint(with: [property, property.asUnwrappedProperty])
		{
			aliases.append(AliasedDependency(property: property, fulfillingProperty: fulfillingProperty))
			if onlyIfAvailable {
				onlyIfAvailableAliasFulfillingPropertyByProperty[property] = fulfillingProperty
			}
		}
		var aliasedChildIndexByProperty = [Property: Int]()
		var resolvedAnAlias = true
		while resolvedAnAlias {
			resolvedAnAlias = false
			for alias in aliases where aliasedChildIndexByProperty[alias.property] == nil {
				if let index = childIndexByProperty[alias.fulfillingProperty] ?? aliasedChildIndexByProperty[alias.fulfillingProperty] {
					aliasedChildIndexByProperty[alias.property] = index
					resolvedAnAlias = true
				}
			}
		}
		func childIndex(declaring property: Property) -> Int? {
			childIndexByProperty[property] ?? aliasedChildIndexByProperty[property]
		}
		/// The child declaring the unwrapped form of `property`, which fulfills a required receive of `property`.
		/// A tree can list an optional property it receives only if available as neither, beneath a scope that
		/// forwards its unwrapped form, so a receiver that requires it is looked for.
		func childIndex(declaringUnwrapped property: Property, requiredInTreeOf childScope: Scope) -> Int? {
			guard let index = childIndex(declaring: property.asUnwrappedProperty),
			      requiredReceiver(of: property, inTreeOf: childScope) != nil
			else { return nil }
			return index
		}
		// The siblings each child requires, in sibling order, each with the first (sorted) property through which it is received.
		// A child that receives its own property is reported by the received walk or the ancestor check, but one that
		// receives it through an alias or unwrapped requires itself here. Only the received properties that name a
		// sibling are kept, so nothing is sorted on the common path.
		let requiredSiblings = children.map { child in
			let receivedProperties = collectReceivedProperties(from: child.scope, cache: &cache)
			var firstReceivedPropertyBySiblingIndex = [Int: Property]()
			// A property received only if available is still required when it fulfills an `onlyIfAvailable` alias that a receiver requires.
			for property in receivedProperties.received
				where property != child.property
				&& property != child.property.asLazilyInstantiatedInstanceProperty
				&& (!receivedProperties.onlyIfAvailable.contains(property) || receivedProperties.requiredAliasFulfilling.contains(property))
			{
				if let index = childIndex(declaring: property) ?? childIndex(declaringUnwrapped: property, requiredInTreeOf: child.scope),
				   firstReceivedPropertyBySiblingIndex[index].map({ property < $0 }) ?? true
				{
					firstReceivedPropertyBySiblingIndex[index] = property
				}
			}
			return firstReceivedPropertyBySiblingIndex
				.map { (index: $0.key, receivedProperty: $0.value) }
				.sorted { $0.index < $1.index }
		}
		// Depth-first search, in sibling order, for a back edge.
		var visitedIndices = Set<Int>()
		var pathIndices = [Int]()
		// The property through which each child on the path receives the next one.
		var pathReceivedProperties = [Property]()
		func cycleOfChildren(reachedFrom index: Int) -> ChildrenRequiringEachOther? {
			visitedIndices.insert(index)
			pathIndices.append(index)
			defer { pathIndices.removeLast() }
			var foundCycle: ChildrenRequiringEachOther?
			for requiredSibling in requiredSiblings[index] where foundCycle == nil {
				if let pathPosition = pathIndices.firstIndex(of: requiredSibling.index) {
					let receivedPropertyChain = Array(pathReceivedProperties[pathPosition...]) + [requiredSibling.receivedProperty]
					foundCycle = ChildrenRequiringEachOther(
						instantiated: children[requiredSibling.index].property,
						receivedPropertyChain: receivedPropertyChain,
						lastChildScope: children[index].scope,
						requiredOnlyIfAvailableAliases: receivedPropertyChain.compactMap { property in
							onlyIfAvailableAliasFulfillingPropertyByProperty[property].map {
								.init(property: property, fulfillingProperty: $0)
							}
						},
					)
				} else if !visitedIndices.contains(requiredSibling.index) {
					pathReceivedProperties.append(requiredSibling.receivedProperty)
					foundCycle = cycleOfChildren(reachedFrom: requiredSibling.index)
					pathReceivedProperties.removeLast()
				}
			}
			return foundCycle
		}
		var foundCycle: ChildrenRequiringEachOther?
		for index in children.indices where foundCycle == nil && !visitedIndices.contains(index) {
			foundCycle = cycleOfChildren(reachedFrom: index)
		}
		return foundCycle
	}

	/// Validates that no scope in the trees rooted at `rootScopes` has instantiated
	/// children that require one another (see `childrenRequiringEachOther`). Such
	/// children would be generated with one of them referring to a sibling declared
	/// after it, which no compiler stage before SIL rejects. Scopes in `validation`'s
	/// `validatedScopes` are skipped along with their trees, and every scope validated is added to it.
	/// - Parameter rootScopes: The roots of the trees, each with the properties of `onlyIfAvailable` aliases that
	///   the scopes enclosing it provide to it (see `ChildrenRequiringEachOtherValidation`).
	private static func validateChildrenDoNotRequireEachOther(
		inTreesRootedAt rootScopes: [(scope: Scope, enclosingProvidedProperties: Set<Property>)],
		cache: inout ReceivedPropertiesCache,
		validation: inout ChildrenRequiringEachOtherValidation,
	) throws {
		func validateChildrenDoNotRequireEachOther(inTreeRootedAt scope: Scope, enclosingProvidedProperties: Set<Property>) throws {
			guard validation.validatedScopes.insert(.init(scope: scope, enclosingProvidedProperties: enclosingProvidedProperties)).inserted else { return }
			if let aliasesFulfillingOneAnother = aliasesFulfillingOneAnother(in: scope) {
				throw aliasesFulfillingOneAnother.error
			} else if let childrenRequiringEachOther = childrenRequiringEachOther(in: scope, enclosingProvidedProperties: enclosingProvidedProperties, cache: &cache) {
				throw childrenRequiringEachOther.error
			} else {
				for case let .instantiated(childProperty, childScope, _) in scope.propertiesToGenerate {
					try validateChildrenDoNotRequireEachOther(
						inTreeRootedAt: childScope,
						enclosingProvidedProperties: validation.enclosingProvidedProperties(
							ofChild: childProperty,
							of: scope,
							enclosingProvidedProperties: enclosingProvidedProperties,
						),
					)
				}
			}
		}
		for rootScope in rootScopes {
			try validateChildrenDoNotRequireEachOther(inTreeRootedAt: rootScope.scope, enclosingProvidedProperties: rootScope.enclosingProvidedProperties)
		}
	}

	/// An aliased dependency a scope declares: `property`, assigned from `fulfillingProperty`.
	private struct AliasedDependency {
		let property: Property
		let fulfillingProperty: Property
		/// Where the alias is declared, when it is known.
		var declarationLocation: Dependency.DeclarationLocation?
	}

	/// Aliased dependencies of one scope that are each fulfilled by the next one.
	private struct AliasesFulfillingOneAnother {
		/// The aliases, starting and ending with the same one.
		let aliasChain: [Property]
		/// The declaration of the alias fulfilled by the first, which closes the cycle.
		let closingDeclarationLocation: Dependency.DeclarationLocation?

		/// The error reporting these aliases, at the one that closes the cycle.
		var error: DependencyTreeGeneratorError {
			DependencyTreeGeneratorError.aliasedDependenciesFulfillOneAnother(
				aliasChain: aliasChain,
				declarationLocation: closingDeclarationLocation,
			)
		}
	}

	/// The first cycle, in declaration order, of aliased dependencies of `scope` that are each fulfilled by
	/// the next one. An alias resolves against a property declared beside it, so such aliases would each be
	/// assigned from one not yet declared.
	private static func aliasesFulfillingOneAnother(
		in scope: Scope,
	) -> AliasesFulfillingOneAnother? {
		let aliases = scope.instantiable.dependencies.compactMap { dependency -> AliasedDependency? in
			switch dependency.source {
			case let .aliased(fulfillingProperty, _, _):
				AliasedDependency(
					property: dependency.property,
					fulfillingProperty: fulfillingProperty,
					declarationLocation: dependency.declarationLocation,
				)
			case .instantiated, .received, .forwarded:
				nil
			}
		}
		var aliasByProperty = [Property: AliasedDependency]()
		for alias in aliases {
			aliasByProperty[alias.property] = alias
		}
		for start in aliases {
			// A chain longer than the aliases has entered a cycle that does not return to `start`.
			var chain = [start]
			while chain.count <= aliases.count, let next = aliasByProperty[chain[chain.count - 1].fulfillingProperty] {
				if next.property == start.property {
					return AliasesFulfillingOneAnother(
						aliasChain: chain.map(\.property) + [start.property],
						closingDeclarationLocation: chain[chain.count - 1].declarationLocation,
					)
				} else {
					chain.append(next)
				}
			}
		}
		return nil
	}

	/// The first dependency, in declaration order and then child order, in the tree that
	/// `scope` creates that requires `property` from outside the tree — a dependency
	/// through which `collectReceivedProperties` finds the tree requires `property`.
	private static func requiredReceiver(
		of property: Property,
		inTreeOf scope: Scope,
	) -> Dependency? {
		var visitedScopes = Set<ObjectIdentifier>()
		func requiredReceiver(inTreeOf scope: Scope) -> Dependency? {
			guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { return nil }
			let propertiesToDeclare = propertiesToDeclare(in: scope)
			let forwardedProperties = scope.instantiable.forwardedReceivableProperties
			if let receiver = scope.instantiable.dependencies.first(where: { dependency in
				switch dependency.source {
				case let .received(onlyIfAvailable):
					!onlyIfAvailable && dependency.property == property
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					!onlyIfAvailable && fulfillingProperty == property && !propertiesToDeclare.contains(fulfillingProperty)
				case .instantiated, .forwarded:
					false
				}
			}) {
				return receiver
			} else if propertiesToDeclare.contains(property)
				|| (property.typeDescription.isOptional && propertiesToDeclare.contains(property.asUnwrappedProperty))
				|| forwardedProperties.contains(property)
				|| (property.typeDescription.isOptional && forwardedProperties.contains(property.asUnwrappedProperty))
			{
				// The trees of this scope's children receive this scope's `property`.
				return nil
			} else {
				var receiver: Dependency?
				for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate where receiver == nil {
					receiver = requiredReceiver(inTreeOf: childScope)
				}
				return receiver
			}
		}
		return requiredReceiver(inTreeOf: scope)
	}

	/// The properties `scope` declares for its children: those it instantiates and the aliases it assigns.
	/// A lazily instantiated property also declares the property that receives its instance by value.
	private static func propertiesToDeclare(in scope: Scope) -> Set<Property> {
		Set(scope.propertiesToGenerate.flatMap(\.receivableProperties))
	}

	/// Classifies a detected cycle and throws the appropriate error, or
	/// returns silently if the cycle is valid. Called from both
	/// `validatePropertiesAreFulfillable` (production graph, and a mock root whose
	/// children require one another) and `validateMockRootScopeForCycles` (mock
	/// graph after `@Received` promotion).
	///
	/// Rejected:
	/// - Constant entry point, whether or not the cycle has a lazy hop → `.constantDependencyCycleDetected`.
	/// - Non-constant entry point that originated from a receive (`closingReceive` is not `nil`) → `.receivedInstantiatorDependencyCycleDetected`.
	///
	/// Accepted (returns without throwing):
	/// - Fully-lazy cycles entered via an `Instantiator` that is NOT received.
	///   The cycle compiles because each hop defers construction; pruning via
	///   `cycleEdges` is what breaks the self-referencing config-struct shape
	///   so the generated code typechecks.
	///
	/// Key implication for downstream code: any mock tree node reached
	/// through a constant-typed property CANNOT be on a pruned back-edge —
	/// this function would have rejected the cycle before code generation.
	/// See the `erasedToConcreteExistential` matrix in CLAUDE.md's "Common
	/// Pitfalls" for how this interacts with erased properties.
	/// - Parameter declaredProperty: The property of the dependency that closes the cycle, as declared at
	///   `declarationLocation`: the property instantiated, or the property received – the alias for an alias.
	private func throwIfInvalidCycle(
		typesInCycle: [TypeDescription],
		property: Property,
		declaredProperty: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		directParent: TypeDescription,
		closingReceive: CycleClosingReceive?,
		lazilyInstantiatedProperties: [Property],
	) throws {
		if property.propertyType.isConstant || closingReceive != nil {
			throw invalidCycleError(
				typesInCycle: typesInCycle,
				property: property,
				declaredProperty: declaredProperty,
				declarationLocation: declarationLocation,
				directParent: directParent,
				closingReceive: closingReceive,
				lazilyInstantiatedProperties: lazilyInstantiatedProperties,
			)
		}
		// Fully-lazy cycle (Instantiator entry, not received) — valid, no error.
	}

	/// The error `throwIfInvalidCycle` throws for a cycle through `property` that is constant or received:
	/// a constant cycle when `property` is constant, and a received-`Instantiator` cycle otherwise.
	/// - Parameter declaredProperty: See `throwIfInvalidCycle`.
	/// - Parameter closingReceive: The receive that closes the cycle, or `nil` when an instantiation closes it.
	private func invalidCycleError(
		typesInCycle: [TypeDescription],
		property: Property,
		declaredProperty: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		directParent: TypeDescription,
		closingReceive: CycleClosingReceive?,
		lazilyInstantiatedProperties: [Property],
	) -> DependencyTreeGeneratorError {
		let cycle = DependencyTreeGeneratorError.DependencyCycle(
			declarationLocation: declarationLocation,
			members: typesInCycle.map { typeDescription in
				DependencyTreeGeneratorError.DependencyCycle.Member(
					typeDescription: typeDescription,
					declarationLocation: typeDescriptionToFulfillingInstantiableMap[typeDescription.asInstantiatedType]?.declarationLocation,
				)
			},
			lazilyInstantiatedProperties: lazilyInstantiatedProperties,
		)
		if property.propertyType.isConstant {
			return .constantDependencyCycleDetected(
				cycle,
				closingDependency: closingReceive == nil
					? .instantiated(declaredProperty)
					: .received(declaredProperty, receiver: directParent),
			)
		} else {
			return .receivedInstantiatorDependencyCycleDetected(
				property: property,
				aliasProperty: closingReceive?.aliasProperty,
				directParent: directParent,
				cycle: cycle,
			)
		}
	}

	/// The receive that closes a cycle: a dependency that receives a property in the cycle that is still being built.
	private struct CycleClosingReceive {
		/// The declared property when the dependency is a `@Received(fulfilledByDependencyNamed:ofType:)` alias that the
		/// property in the cycle fulfills, and `nil` when the dependency receives that property as declared.
		let aliasProperty: Property?
	}

	/// The receive by which `dependency` of `scope` closes a cycle through the property it is fulfilled by
	/// (`dependency.source.fulfillingProperty ?? dependency.property`), which is still being built, or `nil` when
	/// `dependency` does not receive that property. Production's walk of received properties counts a required
	/// alias the same way, since `Scope.requiredReceivedProperties` lists its fulfilling property unless `scope`
	/// instantiates or is forwarded it.
	private static func closingReceive(of dependency: Dependency, in scope: Scope) -> CycleClosingReceive? {
		switch dependency.source {
		case .received:
			CycleClosingReceive(aliasProperty: nil)
		case let .aliased(fulfillingProperty, _, onlyIfAvailable):
			// An alias receives its fulfilling property, unless it is `onlyIfAvailable` – generation does not create it
			// while that property is still being built, and passes `nil` in its place – or `scope` creates the property,
			// which the alias then refers to, so the dependency that creates it is what closes the cycle.
			if onlyIfAvailable || scope.createdProperties.contains(fulfillingProperty) {
				nil
			} else {
				CycleClosingReceive(aliasProperty: dependency.property)
			}
		case .instantiated, .forwarded:
			nil
		}
	}

	/// What a scope's subtree receives from its ancestors.
	private struct ReceivedProperties {
		/// Every property the subtree needs from an ancestor.
		let received: Set<Property>
		/// Those of `received` that every receiver in the subtree receives only if available.
		/// A property some receiver requires is not in `onlyIfAvailable`.
		let onlyIfAvailable: Set<Property>
		/// The properties the subtree receives only if available to fulfill an `onlyIfAvailable` alias
		/// that a receiver in the subtree requires.
		let requiredAliasFulfilling: Set<Property>
	}

	/// Memoizes `collectReceivedProperties` across the mock roots of one mock scope map.
	///
	/// A walk that re-enters a scope whose own walk is unfinished – a cycle of `Instantiator`s – takes
	/// nothing from it, since that scope's walk accounts for what it receives. A result computed that
	/// way lacks what the unfinished scope receives, so it is reused only until that scope's walk
	/// finishes. Reusing it later, from a subtree that reaches the cycle another way, would drop what
	/// the cycle receives from that subtree's view, and which subtree walks the cycle first can follow
	/// set iteration order.
	private struct ReceivedPropertiesCache {
		/// Results that lack nothing, which are the same however the scope is reached.
		var complete = [ObjectIdentifier: ReceivedProperties]()
		/// The depth of each scope whose walk is unfinished.
		var unfinishedWalkDepths = [ObjectIdentifier: Int]()
		/// Results that lack what a scope whose walk is unfinished receives.
		var incomplete = [ObjectIdentifier: WalkedReceivedProperties]()
	}

	/// A scope's received properties as one walk found them.
	private struct WalkedReceivedProperties {
		let receivedProperties: ReceivedProperties
		/// The depth of the shallowest scope whose walk was unfinished and whose received properties
		/// `receivedProperties` therefore lacks, or `nil` when it lacks none.
		let shallowestUnfinishedWalkDepth: Int?
	}

	/// Mirrors ScopeGenerator's `receivedProperties` and `onlyIfAvailableUnwrappedReceivedProperties`
	/// computation but operates on Scope objects directly, with memoization for O(1) revisits.
	///
	/// - Returns: The subtree's received properties. Its `requiredAliasFulfilling` mirrors
	///   ScopeGenerator's `requiredAliasFulfillingProperties`, except that it does not leave out an
	///   alias an enclosing scope's property stands in for.
	private static func collectReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> ReceivedProperties {
		walkReceivedProperties(from: scope, cache: &cache).receivedProperties
	}

	private static func walkReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> WalkedReceivedProperties {
		let id = ObjectIdentifier(scope)
		if let complete = cache.complete[id] {
			return WalkedReceivedProperties(receivedProperties: complete, shallowestUnfinishedWalkDepth: nil)
		} else if let unfinishedWalkDepth = cache.unfinishedWalkDepths[id] {
			// A cycle re-entered this scope. Its unfinished walk accounts for what it receives.
			return WalkedReceivedProperties(
				receivedProperties: ReceivedProperties(received: [], onlyIfAvailable: [], requiredAliasFulfilling: []),
				shallowestUnfinishedWalkDepth: unfinishedWalkDepth,
			)
		} else if let incomplete = cache.incomplete[id] {
			return incomplete
		}
		let walkDepth = cache.unfinishedWalkDepths.count
		cache.unfinishedWalkDepths[id] = walkDepth
		var shallowestUnfinishedWalkDepth: Int?

		// Properties declared at this scope (instantiated/aliased children). A lazily instantiated
		// property also declares the property that receives its instance by value.
		let propertiesToDeclare = propertiesToDeclare(in: scope)

		// Forwarded properties at this scope. A lazily instantiated one is also received by value.
		let forwardedProperties = scope.instantiable.forwardedReceivableProperties

		var received = Set<Property>()
		var onlyIfAvailable = Set<Property>()
		// Received properties some receiver in this subtree requires. A property can be
		// received both ways — e.g. a required `x: X` and an `onlyIfAvailable` alias
		// fulfilled by `x: X` — and a required receive wins.
		var required = Set<Property>()
		// Properties the instantiated children's subtrees require, including those this scope declares.
		var childRequiredReceived = Set<Property>()
		var requiredAliasFulfilling = Set<Property>()

		// Collect from instantiated children — mirrors ScopeGenerator's receivedProperties aggregation.
		// Aliases are handled below in the own-dependency loop: alias children's receivedProperties
		// = [fulfillingProperty], but the own-dependency union unconditionally adds the same
		// fulfillingProperty, making the child-path subtraction/filter redundant.
		for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
			let walkedChild = walkReceivedProperties(
				from: childScope,
				cache: &cache,
			)
			shallowestUnfinishedWalkDepth = [shallowestUnfinishedWalkDepth, walkedChild.shallowestUnfinishedWalkDepth].compactMap(\.self).min()
			let childReceived = walkedChild.receivedProperties.received
			let childOnlyIfAvailable = walkedChild.receivedProperties.onlyIfAvailable
			childRequiredReceived.formUnion(childReceived.subtracting(childOnlyIfAvailable))
			requiredAliasFulfilling.formUnion(walkedChild.receivedProperties.requiredAliasFulfilling)
			// A forwarded `x: X` fulfills an `x: X?` beneath it, as a declared one does.
			let childReceivedFromAncestors = childReceived
				.subtracting(propertiesToDeclare)
				.subtracting(forwardedProperties)
				.filter { property in
					!property.typeDescription.isOptional
						|| (!propertiesToDeclare.contains(property.asUnwrappedProperty) && !forwardedProperties.contains(property.asUnwrappedProperty))
				}
			received.formUnion(childReceivedFromAncestors)
			required.formUnion(childReceivedFromAncestors.subtracting(childOnlyIfAvailable))
			// Subtract by unwrapped form — a declared `x: X` satisfies onlyIfAvailable `x: X?`.
			onlyIfAvailable.formUnion(
				childOnlyIfAvailable.filter { property in
					!propertiesToDeclare.contains(property.asUnwrappedProperty)
						&& !forwardedProperties.contains(property.asUnwrappedProperty)
				},
			)
		}

		// This scope's own received/aliased dependencies.
		// Store exact properties (not unwrapped) in onlyIfAvailable. This avoids
		// collisions between a required `x: X` and an onlyIfAvailable `x: X?` —
		// they are distinct Properties. The subtraction above uses unwrapped comparison
		// to correctly subtract when a declared property satisfies an optional one.
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case let .received(isOnlyIfAvailable):
				received.insert(dependency.property)
				if isOnlyIfAvailable {
					onlyIfAvailable.insert(dependency.property)
				} else {
					required.insert(dependency.property)
				}
			case let .aliased(fulfillingProperty, _, isOnlyIfAvailable):
				// If the fulfilling property is also locally declared here (e.g., as an
				// @Instantiated sibling) or forwarded, the alias resolves against that local
				// binding — it's not a received dependency that needs promoting.
				guard !propertiesToDeclare.contains(fulfillingProperty),
				      !forwardedProperties.contains(fulfillingProperty)
				else { break }
				received.insert(fulfillingProperty)
				if isOnlyIfAvailable {
					onlyIfAvailable.insert(fulfillingProperty)
					if childRequiredReceived.contains(dependency.property) {
						requiredAliasFulfilling.insert(fulfillingProperty)
					}
				} else {
					required.insert(fulfillingProperty)
				}
			case .instantiated, .forwarded:
				break
			}
		}

		cache.unfinishedWalkDepths[id] = nil
		if !cache.incomplete.isEmpty {
			// Results that lack what this scope receives are stale now that its walk has finished.
			cache.incomplete = cache.incomplete.filter { $0.value.shallowestUnfinishedWalkDepth != walkDepth }
		}
		let receivedProperties = ReceivedProperties(
			received: received,
			onlyIfAvailable: onlyIfAvailable.subtracting(required),
			requiredAliasFulfilling: requiredAliasFulfilling
				.subtracting(propertiesToDeclare)
				.subtracting(forwardedProperties),
		)
		if let shallowestUnfinishedWalkDepth, shallowestUnfinishedWalkDepth < walkDepth {
			let walkedReceivedProperties = WalkedReceivedProperties(
				receivedProperties: receivedProperties,
				shallowestUnfinishedWalkDepth: shallowestUnfinishedWalkDepth,
			)
			cache.incomplete[id] = walkedReceivedProperties
			return walkedReceivedProperties
		} else {
			// Every walk that re-entered this scope is accounted for in this one.
			cache.complete[id] = receivedProperties
			return WalkedReceivedProperties(receivedProperties: receivedProperties, shallowestUnfinishedWalkDepth: nil)
		}
	}

	/// Builds a scope mapping for mock generation. Similar to `createTypeDescriptionToScopeMapping`
	/// but includes ALL types (not just reachable from roots). Received dependencies are NOT
	/// promoted here — they're promoted at the root level in `createMockRootScopeGenerator`.
	///
	/// A type that a mock builds by calling its hand-written mock is built from what that method is passed.
	/// The dependencies it is not passed are left out of the mock tree: nothing reads them, so a mock that
	/// built one would declare a value it never uses. One of them is still built when a dependency the method
	/// is passed receives it, which is known only once the scopes exist, so the scopes are built again until
	/// no type's tree receives a dependency the type left out.
	private func createMockTypeDescriptionToScopeMapping() -> [TypeDescription: Scope] {
		var dependenciesBuiltForOtherDependencies = [TypeDescription: Set<Dependency>]()
		var typeDescriptionToScopeMap: [TypeDescription: Scope]
		var foundDependencyToBuild: Bool
		repeat {
			typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping(
				dependenciesBuiltForOtherDependencies: dependenciesBuiltForOtherDependencies,
			)
			var receivedPropertiesCache = ReceivedPropertiesCache()
			foundDependencyToBuild = false
			// Each match only joins a set, so neither the order of the scopes nor a scope mapped from
			// several types changes the outcome.
			for scope in typeDescriptionToScopeMap.values where !scope.dependenciesLeftOut.isEmpty {
				let receivedLabels = Set(Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received.map(\.label))
				for dependency in scope.dependenciesLeftOut where receivedLabels.contains(dependency.property.label) {
					switch dependency.source {
					case .instantiated, .aliased:
						dependenciesBuiltForOtherDependencies[scope.instantiable.concreteInstantiable, default: []].insert(dependency)
						foundDependencyToBuild = true
					case .received, .forwarded:
						// The type does not provide this dependency, so its tree receives it from an ancestor either way.
						continue
					}
				}
			}
		} while foundDependencyToBuild
		return typeDescriptionToScopeMap
	}

	/// - Parameter dependenciesBuiltForOtherDependencies: For each concrete type, the dependencies its
	///   hand-written mock is not passed that a mock builds all the same.
	private func createMockTypeDescriptionToScopeMapping(
		dependenciesBuiltForOtherDependencies: [TypeDescription: Set<Dependency>],
	) -> [TypeDescription: Scope] {
		// Create scopes for all types. Process non-mockOnly types first so they
		// claim additional-type slots. mockOnly types then overwrite slots whose
		// existing scope lacks a compatible hand-written mock.
		// Multiple map entries can share a concreteInstantiable but have different
		// instantiableTypes (e.g., a mockOnly with extra fulfillingAdditionalTypes).
		// Reuse the same scope for all entries sharing a concreteInstantiable so
		// every instantiableType is mapped.
		var visitedConcreteTypeToScope = [TypeDescription: Scope]()
		let typeDescriptionToCompleteScopeMap: [TypeDescription: Scope] = typeDescriptionToFulfillingInstantiableMap.values
			.sorted { lhs, rhs in
				// Non-mockOnly before mockOnly (production claims slots first).
				if lhs.mockOnly != rhs.mockOnly {
					return !lhs.mockOnly
				} else {
					// Within the same mockOnly tier, prefer entries with mock info
					// so scope-reuse creates scopes from mock-capable entries.
					// Hand-written mocks (mockInitializer) before generateMock,
					// since hand-written mocks take priority.
					let lhsHasHandWrittenMock = lhs.mockInitializer != nil
					let rhsHasHandWrittenMock = rhs.mockInitializer != nil
					if lhsHasHandWrittenMock != rhsHasHandWrittenMock {
						return lhsHasHandWrittenMock
					} else {
						let lhsHasMock = lhs.generateMock || lhsHasHandWrittenMock
						let rhsHasMock = rhs.generateMock || rhsHasHandWrittenMock
						if lhsHasMock != rhsHasMock {
							return lhsHasMock
						} else {
							// Stable tiebreaker: sort by concrete type name so scope-reuse
							// selects the same entry across runs.
							return lhs.concreteInstantiable < rhs.concreteInstantiable
						}
					}
				}
			}
			.reduce(into: [TypeDescription: Scope]()) { partialResult, instantiable in
				let scope = visitedConcreteTypeToScope[instantiable.concreteInstantiable] ?? Scope(instantiable: instantiable)
				visitedConcreteTypeToScope[instantiable.concreteInstantiable] = scope
				for instantiableType in instantiable.instantiableTypes {
					guard let existingScope = partialResult[instantiableType] else {
						// When a mockOnly entry adds a new slot and the reused scope
						// lacks mock metadata, use a scope built from the mockOnly's
						// instantiable so the slot retains the hand-written mock info.
						// Only when the mock return type is compatible with this slot.
						if instantiable.mockOnly,
						   instantiable.mockInitializer != nil,
						   instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiableType),
						   scope.instantiable.mockInitializer == nil
						{
							partialResult[instantiableType] = Scope(instantiable: instantiable)
						} else {
							partialResult[instantiableType] = scope
						}
						continue
					}
					// A mockOnly hand-written mock overwrites a scope that lacks
					// its own hand-written mock. generateMock (which wraps init)
					// does not count — hand-written mocks take priority.
					// Check compatibility against both the concrete type and the
					// slot type — extension mocks can validly return a protocol
					// from fulfillingAdditionalTypes. Also verify the incoming
					// mockOnly's mock is usable for this slot (its return type
					// must match the slot type or its own concrete type).
					if instantiable.mockOnly,
					   instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiableType),
					   !existingScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: existingScope.instantiable.concreteInstantiable),
					   !existingScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiableType)
					{
						partialResult[instantiableType] = scope
					}
				}
			}

		// A property is built with its type's hand-written mock when that method returns a type the property
		// accepts, so a type whose mock returns one of the additional types it fulfills is built with the mock
		// for properties of that type and with `init` for the others. Each kind of property gets a scope that
		// declares what builds it.
		var scopesBuiltByHandWrittenMock = [ObjectIdentifier: Scope]()
		let typeDescriptionToScopeMap = typeDescriptionToCompleteScopeMap.reduce(into: [TypeDescription: Scope]()) { partialResult, entry in
			let (instantiableType, scope) = entry
			let instantiable = scope.instantiable
			guard let mockInitializer = instantiable.mockInitializer,
			      instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiableType)
			else {
				partialResult[instantiableType] = scope
				return
			}
			if let scopeBuiltByHandWrittenMock = scopesBuiltByHandWrittenMock[ObjectIdentifier(scope)] {
				partialResult[instantiableType] = scopeBuiltByHandWrittenMock
			} else {
				let dependenciesToBuild = dependenciesBuiltForOtherDependencies[instantiable.concreteInstantiable, default: []]
				let dependenciesLeftOut = instantiable.dependenciesNotPassed(to: mockInitializer).filter { !dependenciesToBuild.contains($0) }
				let scopeBuiltByHandWrittenMock = if dependenciesLeftOut.isEmpty {
					scope
				} else {
					Scope(
						instantiable: instantiable.keepingDependencies { !dependenciesLeftOut.contains($0) },
						dependenciesLeftOut: dependenciesLeftOut,
					)
				}
				scopesBuiltByHandWrittenMock[ObjectIdentifier(scope)] = scopeBuiltByHandWrittenMock
				partialResult[instantiableType] = scopeBuiltByHandWrittenMock
			}
		}

		// Populate propertiesToGenerate on each scope.
		for scope in Set(typeDescriptionToScopeMap.values) {
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
					// For fulfilledByType deps, prefer the declared type for mock
					// resolution — fulfilledByType is a production-only directive.
					// The scope map's priority rules determine the best mock for
					// the declared type. Fall back to the fulfilling type if the
					// declared type isn't in the scope map.
					let instantiatedType = dependency.asInstantiatedType
					let declaredType = dependency.property.typeDescription.asInstantiatedType
					let instantiatedScope: Scope? = if fulfillingTypeDescription != nil {
						typeDescriptionToScopeMap[declaredType] ?? typeDescriptionToScopeMap[instantiatedType]
					} else {
						typeDescriptionToScopeMap[instantiatedType]
					}
					if let instantiatedScope {
						scope.propertiesToGenerate.append(.instantiated(
							dependency.property,
							instantiatedScope,
							erasedToConcreteExistential: erasedToConcreteExistential,
						))
					}
				case .received:
					// Received dependencies are NOT promoted on individual scopes.
					// They bubble up through receivedProperties to the mock root,
					// where they're promoted as root-level children.
					continue
				case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
					scope.propertiesToGenerate.append(.aliased(
						dependency.property,
						fulfilledBy: fulfillingProperty,
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
						declarationReference: dependency.declarationLocation.map(aliasDeclarationReferences.reference(to:)),
					))
				case .forwarded:
					continue
				}
			}
		}
		return typeDescriptionToScopeMap
	}

	/// A collection of `@Instantiable`-decorated types that are at the roots of their respective dependency trees.
	private lazy var rootInstantiables: Set<TypeDescription> = Set(
		typeDescriptionToFulfillingInstantiableMap
			.values
			.filter(\.isRoot)
			.map(\.concreteInstantiable),
	)

	/// A collection of `@Instantiable`-decorated types that are instantiated by at least one other
	/// `@Instantiable`-decorated type or do not explicitly receive dependencies.
	private lazy var reachableTypeDescriptions: Set<TypeDescription> = {
		var reachableTypeDescriptions = Set<TypeDescription>()

		func recordReachableTypeDescription(_ reachableTypeDescription: TypeDescription) {
			guard !reachableTypeDescriptions.contains(reachableTypeDescription) else {
				// We've visited this tree already. Ignore.
				return
			}
			reachableTypeDescriptions.insert(reachableTypeDescription)
			guard let instantiable = typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] else {
				// We can't find an instantiable for this type.
				// This is bad, but we'll handle this error in `validateReachableTypeDescriptions()`.
				return
			}
			let reachableChildTypeDescriptions = instantiable
				.dependencies
				.filter(\.isInstantiated)
				.map(\.asInstantiatedType)
			for reachableChildTypeDescription in reachableChildTypeDescriptions {
				recordReachableTypeDescription(reachableChildTypeDescription)
			}
		}

		for reachableTypeDescription in rootInstantiables {
			recordReachableTypeDescription(reachableTypeDescription)
		}

		return reachableTypeDescriptions
	}()

	private func createTypeDescriptionToScopeMapping() throws -> [TypeDescription: Scope] {
		// Create the mapping.
		let typeDescriptionToScopeMap: [TypeDescription: Scope] = reachableTypeDescriptions
			.reduce(into: [TypeDescription: Scope]()) { partialResult, typeDescription in
				if let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription],
				   partialResult[instantiable.concreteInstantiable] == nil
				{
					let scope = Scope(instantiable: instantiable)
					for instantiableType in instantiable.instantiableTypes {
						partialResult[instantiableType] = scope
					}
				}
			}

		// Populate the propertiesToGenerate on each scope. Scopes hash by identity, so they are
		// visited in an order that changes from run to run, and of the dependencies that cannot
		// be instantiated, the one reported is the first on the type whose name sorts first.
		var firstForwardedPropertyError: ForwardedPropertyError?
		for scope in Set(typeDescriptionToScopeMap.values) {
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case let .instantiated(_, erasedToConcreteExistential):
					let instantiatedType = dependency.asInstantiatedType
					if let instantiable = typeDescriptionToFulfillingInstantiableMap[instantiatedType],
					   let instantiatedScope = typeDescriptionToScopeMap[instantiatedType]
					{
						if let error = forwardedPropertyError(
						   	for: dependency,
						   	instantiable: instantiable,
						   	parent: scope.instantiable,
						   ),
						   firstForwardedPropertyError.map({ scope.instantiable.concreteInstantiable < $0.parent }) ?? true
						{
							firstForwardedPropertyError = ForwardedPropertyError(
								parent: scope.instantiable.concreteInstantiable,
								error: error,
							)
						}
						scope.propertiesToGenerate.append(.instantiated(
							dependency.property,
							instantiatedScope,
							erasedToConcreteExistential: erasedToConcreteExistential,
						))
					}
				case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
					scope.propertiesToGenerate.append(.aliased(
						dependency.property,
						fulfilledBy: fulfillingProperty,
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
						declarationReference: dependency.declarationLocation.map(aliasDeclarationReferences.reference(to:)),
					))
				case .forwarded, .received:
					continue
				}
			}
		}
		if let firstForwardedPropertyError {
			throw firstForwardedPropertyError.error
		}
		return typeDescriptionToScopeMap
	}

	/// What creating an instance of an `@Instantiable` type reads by value, for `generateWarnings()`.
	///
	/// Creating a type creates its constant dependencies along with it, and theirs. A dependency behind an
	/// `Instantiator` is created later, when asked for. A lazily instantiated dependency is created along with
	/// the type only if something that is created along with it reads the dependency’s instance.
	private struct InstantiationAnalysis {
		/// A type that reads a dependency by value while it is created.
		struct Reader {
			let instantiable: Instantiable
			/// The property with which that type declares the dependency.
			let property: Property
			/// The label of the dependency that type receives: `property`'s own, or for an alias the label it renames.
			let receivedLabel: String
		}

		/// A lazily instantiated dependency that is instantiated whenever the type declaring it is created.
		struct LazilyInstantiatedPropertyInstantiatedWithOwner {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The property that receives the dependency’s instance by value.
			let instanceProperty: Property
			/// The first type, in declaration order, whose creation reads the instance.
			let reader: Reader

			func warning(owner: Instantiable) -> SourceDiagnostic {
				let ownerName = owner.concreteInstantiable.asSource
				let cause = if reader.instantiable.concreteInstantiable == owner.concreteInstantiable {
					"`\(ownerName)` renames the instance to `\(reader.property.asSource)`. Declare `\(instanceProperty.asSource)` instead, or read `\(property.label).\(Dependency.lazilyInstantiatedInstancePropertyName)` where `\(ownerName)` needs it."
				} else {
					"`\(reader.instantiable.concreteInstantiable.asSource)` is created with `\(ownerName)` and receives the instance as `\(reader.property.asSource)`. To instantiate it lazily, receive `\(reader.receivedLabel): \(property.typeDescription.unwrapped.asSource)` on `\(reader.instantiable.concreteInstantiable.asSource)`."
				}
				return SourceDiagnostic(
					severity: .warning,
					location: declarationLocation,
					message: "@\(Dependency.Source.instantiatedRawValue) property `\(property.asSource)` is instantiated whenever `\(ownerName)` is created: \(cause)",
				)
			}
		}

		/// The dependencies the type’s creation reads by value from further up the tree, keyed by the property
		/// that receives each, with the type that reads it.
		var readFromAncestors = [Property: Reader]()
		/// The type’s own lazily instantiated dependencies that its creation instantiates, in declaration order.
		var lazilyInstantiatedPropertiesInstantiatedWithOwner = [LazilyInstantiatedPropertyInstantiatedWithOwner]()
	}

	/// - Returns: What creating an instance of `scope`’s type reads by value. See `InstantiationAnalysis`.
	private static func instantiationAnalysis(
		of scope: Scope,
		cache: inout [ObjectIdentifier: InstantiationAnalysis],
	) -> InstantiationAnalysis {
		let scopeIdentifier = ObjectIdentifier(scope)
		if let cachedAnalysis = cache[scopeIdentifier] {
			return cachedAnalysis
		} else {
			let instantiable = scope.instantiable
			var declarationLocations = [Property: Dependency.DeclarationLocation]()
			// A receive binds to the nearest declaration of its label, so nothing this type declares is read from further up.
			var declaredLabels = Set<String>()
			// Every by-value read made while this type is created, whether of its own dependencies or of an ancestor’s.
			var readWhileCreated = [Property: InstantiationAnalysis.Reader]()
			// Reading the instance of a lazily instantiated property this type renames reads the instance of the
			// property it renames. Keyed by the by-value property of the alias.
			var renamedInstanceProperties = [Property: Property]()
			for dependency in instantiable.dependencies {
				declarationLocations[dependency.property] = dependency.declarationLocation
				switch dependency.source {
				case .instantiated, .forwarded:
					declaredLabels.insert(dependency.property.label)
				case .received:
					break
				case let .aliased(fulfillingProperty, _, _):
					declaredLabels.insert(dependency.property.label)
					if let instanceProperty = dependency.lazilyInstantiatedInstanceProperty,
					   let fulfillingInstanceProperty = fulfillingProperty.asLazilyInstantiatedInstanceProperty
					{
						renamedInstanceProperties[instanceProperty] = fulfillingInstanceProperty
					}
				}
			}
			/// The property whose instance a read of `property` reads. A renamed property can itself be
			/// renamed, so this follows the type's renamings back to where they start.
			func propertyRead(by property: Property) -> Property {
				var readProperty = property
				while let renamedProperty = renamedInstanceProperties[readProperty] {
					readProperty = renamedProperty
				}
				return readProperty
			}
			func recordReads(whileCreating childScope: Scope) {
				// Sorted so that which reader is reported never depends on dictionary iteration.
				for (property, reader) in instantiationAnalysis(of: childScope, cache: &cache).readFromAncestors.sorted(by: { $0.key < $1.key }) {
					let readProperty = propertyRead(by: property)
					if readWhileCreated[readProperty] == nil {
						readWhileCreated[readProperty] = reader
					}
				}
			}

			for dependency in instantiable.dependencies {
				switch dependency.source {
				case .instantiated, .forwarded:
					break
				case let .received(onlyIfAvailable):
					// Whether an `onlyIfAvailable` receive reads the instance depends on the order in which
					// siblings are generated, so it is never taken as the reason a dependency is instantiated.
					if !onlyIfAvailable, dependency.property.propertyType.isConstant {
						readWhileCreated[dependency.property] = .init(instantiable: instantiable, property: dependency.property, receivedLabel: dependency.property.label)
					}
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					if !onlyIfAvailable, fulfillingProperty.propertyType.isConstant {
						readWhileCreated[propertyRead(by: fulfillingProperty)] = .init(instantiable: instantiable, property: dependency.property, receivedLabel: fulfillingProperty.label)
					}
				}
			}

			var lazilyInstantiatedChildren = [(property: Property, instanceProperty: Property, scope: Scope)]()
			// A dependency behind an `Instantiator` is created when asked for, not along with this type.
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
				if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
					lazilyInstantiatedChildren.append((property, instanceProperty, childScope))
				} else if property.propertyType.isConstant {
					recordReads(whileCreating: childScope)
				}
			}

			// Instantiating one lazily instantiated dependency can read another’s instance, so look again after each.
			var analysis = InstantiationAnalysis()
			while let (child, reader) = lazilyInstantiatedChildren.lazy.compactMap({ child in
				readWhileCreated[child.instanceProperty].map { (child, $0) }
			}).first {
				analysis.lazilyInstantiatedPropertiesInstantiatedWithOwner.append(.init(
					property: child.property,
					declarationLocation: declarationLocations[child.property],
					instanceProperty: child.instanceProperty,
					reader: reader,
				))
				lazilyInstantiatedChildren.removeAll { $0.property == child.property }
				recordReads(whileCreating: child.scope)
			}

			analysis.readFromAncestors = readWhileCreated.filter { !declaredLabels.contains($0.key.label) }
			cache[scopeIdentifier] = analysis
			return analysis
		}
	}

	/// A constant or lazily instantiated `@Instantiated` dependency whose type has `@Forwarded` properties, and
	/// the type that declares it.
	private struct ForwardedPropertyError {
		let parent: TypeDescription
		let error: DependencyTreeGeneratorError
	}

	/// The error for a constant or lazily instantiated `@Instantiated` dependency on `parent` whose `instantiable`
	/// has `@Forwarded` properties, or `nil` when the dependency is valid.
	private func forwardedPropertyError(
		for dependency: Dependency,
		instantiable: Instantiable,
		parent: Instantiable,
	) -> DependencyTreeGeneratorError? {
		guard dependency.property.propertyType.isConstant || dependency.property.propertyType.isLazilyInstantiated else { return nil }
		let forwardedDependencies = instantiable.dependencies.filter(\.isForwarded)
		guard !forwardedDependencies.isEmpty else { return nil }
		return .instantiableHasForwardedProperty(.init(
			dependency: dependency,
			instantiable: instantiable,
			suggestedPropertyType: Self.instantiatorType(
				building: instantiable,
				forwarding: forwardedDependencies.map(\.property),
				for: dependency,
			),
			forwardedDeclarations: forwardedDependencies.map {
				DependencyTreeGeneratorError.LocatedProperty(property: $0.property, declarationLocation: $0.declarationLocation)
			},
			parent: parent.concreteInstantiable,
		))
	}

	/// The type with which `dependency`, a constant or lazily instantiated `@Instantiated` property, can instead
	/// build `instantiable` when it is asked for, which `instantiable`’s `@Forwarded` properties require:
	/// `Instantiator<Child>` for `child: Child` or `child: LazilyInstantiated<Child>`. `fulfilledByType` cannot
	/// be used on an `Instantiator`, so a property with that argument gets an `ErasedInstantiator` of the type the
	/// property declares, such as `ErasedInstantiator<String, AnyChild>` for `child: AnyChild` when `Child`
	/// forwards a `String`. The forwarded properties are spelled out rather than as `Child.ForwardedProperties`,
	/// which the module that declares the property may not be able to see. The suggestion is `Sendable` when the
	/// property is, and the type an erased instantiator builds is not optional.
	private static func instantiatorType(
		building instantiable: Instantiable,
		forwarding forwardedProperties: [Property],
		for dependency: Dependency,
	) -> TypeDescription {
		let propertyType = dependency.property.propertyType
		if case .instantiated(fulfillingTypeDescription: .some, _) = dependency.source {
			let declaredType = dependency.property.typeDescription.unwrapped
			let builtType = declaredType.lazilyInstantiatedInstanceType?.unwrapped ?? declaredType
			return .simple(
				name: propertyType.isSendable ? Dependency.sendableErasedInstantiatorType : Dependency.erasedInstantiatorType,
				generics: [
					forwardedProperties.asForwardedPropertiesType.typeDescription,
					builtType,
				],
			)
		} else {
			return .simple(
				name: propertyType.isSendable ? Dependency.sendableInstantiatorType : Dependency.instantiatorType,
				generics: [instantiable.concreteInstantiable],
			)
		}
	}

	/// The lazily instantiated properties on a cycle as they are declared, outermost first, for the diagnostic.
	///
	/// - Parameters:
	///   - declaredProperty: The dependency that closes the cycle, as it is declared.
	///   - validatedPropertiesInCycle: The properties on the cycle as cycle validation sees them, innermost first.
	///   - lazilyInstantiatedDeclarations: The lazily instantiated properties being instantiated, keyed by the
	///     constant each is validated as.
	///   - receivedProperties: The dependencies received between the outermost property and the one that
	///     closes the cycle, as they are declared.
	private static func lazilyInstantiatedProperties(
		closingCycleWith declaredProperty: Property,
		validatedPropertiesInCycle: some Collection<Property>,
		lazilyInstantiatedDeclarations: [Property: Property],
		receivedProperties: [Property] = [],
	) -> [Property] {
		var listedProperties = Set<Property>()
		return (validatedPropertiesInCycle.reversed().compactMap { lazilyInstantiatedDeclarations[$0] } + receivedProperties + [declaredProperty])
			.filter { $0.propertyType.isLazilyInstantiated && listedProperties.insert($0).inserted }
	}

	/// Validates scopes for cycles and optionally for unfulfillable properties.
	/// When `cyclesOnly` is true, unfulfillable property collection is skipped —
	/// used for mock-only types where unfulfillable received properties are expected
	/// (they become required mock parameters).
	/// - Parameters:
	///   - additionalMockRootScopes: The scopes of types whose mock is generated because `additionalMocksToGenerate`
	///     lists them. Their trees are validated for hidden received dependencies only.
	///   - receivedPropertiesCache: The results of `collectReceivedProperties` for scopes of
	///     `typeDescriptionToScopeMap`, which the mock validation fills.
	private func validatePropertiesAreFulfillable(
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		additionalMockRootScopes: Set<Scope> = [],
		receivedPropertiesCache: inout ReceivedPropertiesCache,
		cyclesOnly: Bool,
	) throws {
		// Validate in type order, so that the error reported when several trees have one
		// does not depend on set iteration order. A root receives nothing, so its tree binds
		// nothing above its own properties.
		var rootScopes = rootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] }.map { ValidatedRootScope(scope: $0, boundProperties: []) }
		// When checking cycles only (mock validation), also validate non-root types
		// that have generateMock enabled — they bypass root entry points. Each one's
		// mock binds every property its tree receives from above it.
		if cyclesOnly {
			let rootInstantiableSet = Set(rootInstantiables)
			rootScopes += Set(typeDescriptionToScopeMap.values)
				.filter { scope in
					scope.instantiable.generateMock && !rootInstantiableSet.contains(scope.instantiable.concreteInstantiable)
				}
				.sorted { $0.instantiable.concreteInstantiable < $1.instantiable.concreteInstantiable }
				.map { scope in ValidatedRootScope(scope: scope, boundProperties: Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received) }
		}
		try validatePropertiesAreFulfillable(
			onRootScopes: rootScopes,
			additionalMockRootScopes: additionalMockRootScopes
				.sorted { $0.instantiable.concreteInstantiable < $1.instantiable.concreteInstantiable }
				.map { scope in ValidatedRootScope(scope: scope, boundProperties: Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received) },
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: cyclesOnly,
		)
	}

	/// An alias that a receive of its property resolves to: the nearest scope above the receiver that provides the
	/// property declares it with `@Received(fulfilledByDependencyNamed:ofType:)`.
	private struct ReceivableAlias {
		let fulfillingProperty: Property
		let onlyIfAvailable: Bool
		/// Whether the fulfilling property is provided where the alias is declared, or is an ancestor still being
		/// built there. Only an `onlyIfAvailable` alias can lack it, and it is then not created.
		let isFulfillingPropertyAvailable: Bool
		/// The type that declares the alias.
		let declaringType: TypeDescription
		/// The property of the scope that declares the alias, followed by the properties of the scopes it is built
		/// inside, innermost first. Empty when a root declares the alias.
		let declaringInstantiationStack: [Property]
	}

	/// The scope at the root of a tree that `validatePropertiesAreFulfillable` walks.
	private struct ValidatedRootScope {
		let scope: Scope
		/// The received properties the root's mock binds — as children it promotes, `mock()`
		/// parameters, or `SafeDIOverrides` entries — which enclose its whole tree. Empty for a
		/// root of the dependency tree, which receives nothing.
		let boundProperties: Set<Property>
	}

	/// Validates the trees rooted at `rootScopes` for cycles and optionally for
	/// unfulfillable properties. See `validatePropertiesAreFulfillable(typeDescriptionToScopeMap:cyclesOnly:)`.
	/// Also validates, in production trees and in the trees of types that generate a mock, that no received
	/// dependency is hidden by a closer ancestor's property with the same label.
	/// - Parameter additionalMockRootScopes: The scopes of types whose mock is generated because
	///   `additionalMocksToGenerate` lists them. Their trees are validated for hidden received dependencies only.
	private func validatePropertiesAreFulfillable(
		onRootScopes rootScopes: [ValidatedRootScope],
		additionalMockRootScopes: [ValidatedRootScope] = [],
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		cyclesOnly: Bool,
	) throws {
		var unfulfillableProperties = Set<DependencyTreeGeneratorError.UnfulfillableProperty>()
		var hiddenReceivedProperties = Set<DependencyTreeGeneratorError.HiddenReceivedProperty>()
		/// Walks `requiredReceivedProperties`, which `directParent` requires, and, transitively, the required received
		/// properties of the scopes that fulfill them, throwing when one is `property` or is on `instantiationStack`.
		///
		/// `stackPropertiesReliedOnByWalkedProperty` holds the received properties whose walk returned without
		/// throwing, each with the properties already on the received-property stack that the walk relied on: those
		/// it bailed out on as a cycle that isn't ours, and those that a skipped walk beneath it relied on. Walking
		/// such a property again along a stack that holds all of them checks a subset of what its first walk checked,
		/// because the stacks differ only in properties received before it, and any other property there can only
		/// make the walk bail out sooner. So that walk would also return without throwing, and skipping it reports the
		/// same error, from the same stack, as walking every path would. A property can rely only on properties that
		/// share a received cycle with it, so a property on no received cycle is walked once, rather than once for
		/// every path that leads to it.
		/// - Parameters:
		///   - declaredReceivedPropertyStack: The lazily instantiated properties on `receivedPropertyStack`, as
		///     they are declared. The walk sees each as the constant it stands for; the diagnostic names them.
		///   - lazilyInstantiatedDeclarations: The lazily instantiated properties on `instantiationStack`, keyed
		///     by the constant each is validated as.
		/// - Returns: The properties in `receivedPropertyStack` that the walk relied on.
		func validateNoCycleInReceivedProperties(
			_ requiredReceivedProperties: [Scope.RequiredReceivedProperty],
			directParent: TypeDescription,
			receivedPropertyStack: [Property],
			declaredReceivedPropertyStack: [Property],
			property: Property,
			instantiationStack: [Property],
			lazilyInstantiatedDeclarations: [Property: Property],
			stackPropertiesReliedOnByWalkedProperty: inout [Property: Set<Property>],
		) throws -> Set<Property> {
			var stackPropertiesReliedOn = Set<Property>()
			for requiredReceivedProperty in requiredReceivedProperties {
				let childProperty = requiredReceivedProperty.property.asValidatedForDependencyCycles
				guard childProperty != property else {
					throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
						instantiated: property,
						receivedPropertyChain: receivedPropertyStack + [childProperty],
						declarationLocation: requiredReceivedProperty.declarationLocation,
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: requiredReceivedProperty.property,
							validatedPropertiesInCycle: [property],
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: declaredReceivedPropertyStack,
						),
						requiredOnlyIfAvailableAliases: [],
					)
				}
				guard !receivedPropertyStack.contains(childProperty) else {
					// We've found a cycle, but it's not our cycle. Bail and let a future loop find this.
					// The remaining received properties on this scope go unwalked, so a later visit
					// along a stack without `childProperty` must walk this scope again.
					stackPropertiesReliedOn.insert(childProperty)
					return stackPropertiesReliedOn
				}
				let memoizedStackPropertiesReliedOn = stackPropertiesReliedOnByWalkedProperty[childProperty]
				if let cycleIndex = instantiationStack.firstIndex(of: childProperty) {
					let instantiationProperties = Array(instantiationStack[0...cycleIndex])
					let propertiesInCycle = [childProperty]
						+ receivedPropertyStack.reversed()
						+ instantiationProperties
					try throwIfInvalidCycle(
						typesInCycle: propertiesInCycle.map(\.typeDescription),
						property: childProperty,
						declaredProperty: requiredReceivedProperty.aliasProperty ?? requiredReceivedProperty.property,
						declarationLocation: requiredReceivedProperty.declarationLocation,
						directParent: directParent,
						closingReceive: CycleClosingReceive(aliasProperty: requiredReceivedProperty.aliasProperty),
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: requiredReceivedProperty.property,
							validatedPropertiesInCycle: propertiesInCycle,
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: declaredReceivedPropertyStack,
						),
					)
				} else if let memoizedStackPropertiesReliedOn, memoizedStackPropertiesReliedOn.isSubset(of: receivedPropertyStack) {
					stackPropertiesReliedOn.formUnion(memoizedStackPropertiesReliedOn)
				} else if let receivedPropertyScope = typeDescriptionToScopeMap[childProperty.typeDescription] {
					var childPropertyStack = receivedPropertyStack
					childPropertyStack.append(childProperty)
					// A cycle back to `childProperty` itself lies within its walk, wherever that walk starts.
					let childStackPropertiesReliedOn = try validateNoCycleInReceivedProperties(
						receivedPropertyScope.requiredReceivedProperties,
						directParent: receivedPropertyScope.instantiable.concreteInstantiable,
						receivedPropertyStack: childPropertyStack,
						// Only the lazily instantiated receives are named by the diagnostic.
						declaredReceivedPropertyStack: childProperty == requiredReceivedProperty.property
							? declaredReceivedPropertyStack
							: declaredReceivedPropertyStack + [requiredReceivedProperty.property],
						property: property,
						instantiationStack: instantiationStack,
						lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
						stackPropertiesReliedOnByWalkedProperty: &stackPropertiesReliedOnByWalkedProperty,
					).subtracting([childProperty])
					stackPropertiesReliedOnByWalkedProperty[childProperty] = childStackPropertiesReliedOn
					stackPropertiesReliedOn.formUnion(childStackPropertiesReliedOn)
				}
			}
			return stackPropertiesReliedOn
		}
		/// The fulfilling properties of the `onlyIfAvailable` aliases already walked by
		/// `validateNoCycleInReceivedProperties`, each followed by its declaring scope's instantiation stack.
		var walkedAliasFulfillingProperties = Set<[Property]>()
		/// - Parameters:
		///   - closestDeclarationByLabel: The property each label names in `scope`: the one declared by the closest
		///     ancestor that declares the label.
		///   - validatesCycles: Whether to validate the tree for dependency cycles and unfulfillable received
		///     properties. `false` only for a tree validated for hidden received dependencies alone.
		///   - validatesHiddenProperties: Whether to record received dependencies a closer declaration hides.
		func validatePropertiesAreFulfillable(
			on scope: Scope,
			receivableProperties: Set<Property>,
			receivableAliases: [Property: ReceivableAlias],
			boundProperties: Set<Property>,
			closestDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration],
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
			property: Property?,
			propertyStack: [Property],
			lazilyInstantiatedDeclarations: [Property: Property],
			root: TypeDescription,
		) throws {
			let instantiationStack: [Property] = if let property {
				[property] + propertyStack
			} else {
				[]
			}
			if validatesCycles, let property {
				var stackPropertiesReliedOnByWalkedProperty = [Property: Set<Property>]()
				_ = try validateNoCycleInReceivedProperties(
					scope.requiredReceivedProperties,
					directParent: scope.instantiable.concreteInstantiable,
					receivedPropertyStack: [],
					declaredReceivedPropertyStack: [],
					property: property,
					instantiationStack: instantiationStack,
					lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
					stackPropertiesReliedOnByWalkedProperty: &stackPropertiesReliedOnByWalkedProperty,
				)
			}

			// The aliases this scope declares that a receive of their property resolves to. An `onlyIfAvailable`
			// alias of a property an enclosing scope also provides, or a mock binds, is not one: when the alias is not
			// created, the receive resolves to that property instead, as `Scope.createScopeGenerator`'s
			// `isProvidedByEnclosingScope` has generation do. When such an alias is never created, it does not shadow
			// an alias above it either.
			var declaredAliases = [Property: ReceivableAlias]()
			var uncreatedAliasPropertiesProvidedByEnclosingScope = Set<Property>()
			for case let (aliasDependency, .aliased(fulfillingProperty, _, onlyIfAvailable)) in scope.instantiable.dependencies.lazy.map({ ($0, $0.source) }) {
				let aliasProperty = aliasDependency.property
				let isFulfillingPropertyProvided = receivableProperties.containsPropertyOrItsUnwrappedForm(fulfillingProperty)
					|| scope.providedProperties.containsPropertyOrItsUnwrappedForm(fulfillingProperty)
				// The instance of a lazily instantiated property does not stand in for an alias that is not created:
				// it is read from that property, which the alias's label hides.
				let isAliasPropertyProvidedByEnclosingScope = (
					receivableProperties.containsPropertyOrItsUnwrappedForm(aliasProperty)
						|| boundProperties.containsPropertyOrItsUnwrappedForm(aliasProperty),
				) && closestDeclarationByLabel[aliasProperty.label]?.lazilyInstantiatedInstanceProperty != aliasProperty.asUnwrappedProperty
				if !onlyIfAvailable || !isAliasPropertyProvidedByEnclosingScope {
					// The instantiation stack holds a lazily instantiated property as the constant it stands for.
					let validatedFulfillingProperty = fulfillingProperty.asValidatedForDependencyCycles
					let alias = ReceivableAlias(
						fulfillingProperty: fulfillingProperty,
						onlyIfAvailable: onlyIfAvailable,
						// An ancestor still being built counts as available: a receive inside it is a cycle, reported below.
						isFulfillingPropertyAvailable: isFulfillingPropertyProvided
							|| [validatedFulfillingProperty, validatedFulfillingProperty.asUnwrappedProperty].contains(where: instantiationStack.contains),
						declaringType: scope.instantiable.concreteInstantiable,
						declaringInstantiationStack: instantiationStack,
					)
					declaredAliases[aliasProperty] = alias
					// A lazily instantiated alias is also received by value, as the instance it creates.
					if let aliasInstanceProperty = aliasDependency.lazilyInstantiatedInstanceProperty {
						declaredAliases[aliasInstanceProperty] = alias
					}
				} else if !isFulfillingPropertyProvided {
					uncreatedAliasPropertiesProvidedByEnclosingScope.insert(aliasProperty)
				}
			}
			// A required receive of an alias needs the alias created, so it needs the alias's fulfilling property,
			// as the scope that declares the alias would if the alias were not `onlyIfAvailable`.
			for case let (requiredReceivedProperty, alias?) in scope.requiredReceivedProperties.lazy.map({
				($0, declaredAliases[$0.property] ?? receivableAliases[$0.property])
			}) where validatesCycles {
				let receivedProperty = requiredReceivedProperty.property
				let fulfillingProperty = alias.fulfillingProperty
				// The instantiation stack holds a lazily instantiated property as the constant it stands for.
				let validatedFulfillingProperty = fulfillingProperty.asValidatedForDependencyCycles
				if let fulfillingPropertyBeingBuilt = [validatedFulfillingProperty, validatedFulfillingProperty.asUnwrappedProperty].first(where: instantiationStack.contains) {
					// This scope is built inside the alias's fulfilling property, so the alias cannot be created before it.
					throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
						instantiated: fulfillingPropertyBeingBuilt,
						receivedPropertyChain: [receivedProperty.asValidatedForDependencyCycles, fulfillingPropertyBeingBuilt],
						declarationLocation: requiredReceivedProperty.declarationLocation,
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: fulfillingProperty,
							validatedPropertiesInCycle: [fulfillingPropertyBeingBuilt],
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: [receivedProperty],
						),
						requiredOnlyIfAvailableAliases: alias.onlyIfAvailable ? [.init(property: receivedProperty, fulfillingProperty: fulfillingProperty)] : [],
					)
				} else if alias.onlyIfAvailable, !alias.isFulfillingPropertyAvailable {
					if !cyclesOnly, property != nil {
						unfulfillableProperties.insert(.init(
							property: receivedProperty,
							declarationLocation: requiredReceivedProperty.declarationLocation,
							identifierRange: requiredReceivedProperty.identifierRange,
							typeAnnotationRange: requiredReceivedProperty.typeAnnotationRange,
							bareAttributeRange: requiredReceivedProperty.bareAttributeRange,
							instantiable: scope.instantiable,
							parentStack: propertyStack.map(\.typeDescription),
							root: root,
							suggestedAlternatives: [],
							uncreatedAlias: .init(
								declaringType: alias.declaringType,
								fulfillingProperty: fulfillingProperty,
							),
						))
					}
				} else if alias.onlyIfAvailable,
				          let declaringProperty = alias.declaringInstantiationStack.first,
				          walkedAliasFulfillingProperties.insert([fulfillingProperty] + alias.declaringInstantiationStack).inserted
				{
					// A required alias's fulfilling property is walked where the alias is declared. Walk this
					// one there too, since the receive requires it.
					var stackPropertiesReliedOnByWalkedProperty = [Property: Set<Property>]()
					do {
						_ = try validateNoCycleInReceivedProperties(
							[Scope.RequiredReceivedProperty(
								property: fulfillingProperty,
								aliasProperty: receivedProperty,
								declarationLocation: requiredReceivedProperty.declarationLocation,
								identifierRange: nil,
								typeAnnotationRange: nil,
								bareAttributeRange: nil,
							)],
							directParent: alias.declaringType,
							receivedPropertyStack: [receivedProperty.asValidatedForDependencyCycles],
							declaredReceivedPropertyStack: receivedProperty.propertyType.isLazilyInstantiated ? [receivedProperty] : [],
							property: declaringProperty,
							instantiationStack: alias.declaringInstantiationStack,
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							stackPropertiesReliedOnByWalkedProperty: &stackPropertiesReliedOnByWalkedProperty,
						)
					} catch let DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(instantiated, receivedPropertyChain, declarationLocation, lazilyInstantiatedProperties, _) {
						// The chain starts with this receive, which closes it only because it requires the alias.
						throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
							instantiated: instantiated,
							receivedPropertyChain: receivedPropertyChain,
							declarationLocation: declarationLocation,
							lazilyInstantiatedProperties: lazilyInstantiatedProperties,
							requiredOnlyIfAvailableAliases: [.init(property: receivedProperty, fulfillingProperty: fulfillingProperty)],
						)
					}
				}
			}

			/// The first required optional receive this scope can resolve only to the property's non-optional form,
			/// still being built, with that form's index on `instantiationStack`. It is a cycle, thrown after the
			/// cycles below, which match only exact properties, so it is reported as a non-optional receive would be.
			var optionalReceiveOfPropertyBeingBuilt: (receive: Scope.RequiredReceivedProperty, beingBuiltIndex: Int)?
			for requiredReceivedProperty in scope.requiredReceivedProperties where validatesCycles {
				let receivedProperty = requiredReceivedProperty.property
				let parentContainsProperty = receivableProperties.contains(receivedProperty)
				let propertyIsCreatedAtThisScope = scope.createdProperties.contains(receivedProperty)
				guard !parentContainsProperty, !propertyIsCreatedAtThisScope, property != nil else { continue }
				// The instantiation stack holds a lazily instantiated property as the constant it stands for.
				let beingBuiltIndex = receivableProperties.contains(receivedProperty.asUnwrappedProperty)
					? nil
					: instantiationStack.firstIndex(of: receivedProperty.asUnwrappedProperty.asValidatedForDependencyCycles)
				if receivedProperty.typeDescription.isOptional, let beingBuiltIndex {
					optionalReceiveOfPropertyBeingBuilt = optionalReceiveOfPropertyBeingBuilt ?? (requiredReceivedProperty, beingBuiltIndex)
				} else if !cyclesOnly || beingBuiltIndex != nil {
					// A mock binds every property its tree receives from above it, so there only a property still
					// being built is unfulfillable. A non-optional one is a cycle, reported below.
					// This property is in a dependency tree and is unfulfillable. Record the problem.
					unfulfillableProperties.insert(.init(
						property: receivedProperty,
						declarationLocation: requiredReceivedProperty.declarationLocation,
						identifierRange: requiredReceivedProperty.identifierRange,
						typeAnnotationRange: requiredReceivedProperty.typeAnnotationRange,
						bareAttributeRange: requiredReceivedProperty.bareAttributeRange,
						instantiable: scope.instantiable,
						parentStack: propertyStack.map(\.typeDescription),
						root: root,
						suggestedAlternatives: receivableProperties.filter {
							receivedProperty.typeDescription.leastQualifiedTypeDescription == $0.typeDescription.leastQualifiedTypeDescription
								|| receivedProperty.label == $0.label
						}.sorted(),
						uncreatedAlias: nil,
					))
				}
			}

			if validatesHiddenProperties {
				// The generated code passes a received dependency by its label, which resolves to the closest
				// ancestor's declaration of that label. A different property there is passed in its place.
				for dependency in scope.instantiable.dependencies {
					let receivedProperty: Property
					switch dependency.source {
					case .received:
						receivedProperty = dependency.property
					case let .aliased(fulfillingProperty, _, _):
						receivedProperty = fulfillingProperty
					case .instantiated, .forwarded:
						continue
					}
					// A receive of an optional property, required or `onlyIfAvailable`, resolves to its non-optional
					// form too.
					let acceptedProperties: Set<Property> = [receivedProperty, receivedProperty.asUnwrappedProperty]
					guard let closestDeclaration = closestDeclarationByLabel[receivedProperty.label],
					      !acceptedProperties.contains(closestDeclaration.property),
					      // A lazily instantiated declaration also fulfills a by-value receive of its instance.
					      closestDeclaration.lazilyInstantiatedInstanceProperty.map({ !acceptedProperties.contains($0) }) ?? true,
					      // An alias of a property this scope declares refers to that declaration.
					      acceptedProperties.isDisjoint(with: scope.createdProperties),
					      // Production passes `nil` for an `onlyIfAvailable` dependency no ancestor provides. A mock
					      // declares every received dependency at its root, above every hiding declaration.
					      cyclesOnly || !acceptedProperties.isDisjoint(with: receivableProperties)
					else {
						continue
					}
					hiddenReceivedProperties.insert(.init(
						property: receivedProperty,
						declarationLocation: dependency.declarationLocation,
						hidingDeclaration: closestDeclaration,
						receiver: scope.instantiable.concreteInstantiable,
						parentStack: propertyStack.map(\.typeDescription),
						root: root,
					))
				}
			}

			// Check children for cycles.
			var childPropertyStack = propertyStack
			if let property {
				childPropertyStack.insert(property, at: 0)
			}
			for dependency in scope.instantiable.dependencies where validatesCycles && dependency.canCloseDependencyCycle {
				let declaredPropertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
				let propertyForDependency = declaredPropertyForDependency.asValidatedForDependencyCycles
				guard let cycleIndex = childPropertyStack.firstIndex(of: propertyForDependency) else {
					continue
				}
				let propertiesInCycle = [propertyForDependency] + childPropertyStack[0...cycleIndex]
				let closingReceive = Self.closingReceive(of: dependency, in: scope)
				try throwIfInvalidCycle(
					typesInCycle: propertiesInCycle.map(\.typeDescription),
					property: propertyForDependency,
					// A receive is reported as declared; an instantiation as the property it instantiates.
					declaredProperty: closingReceive == nil ? declaredPropertyForDependency : dependency.property,
					declarationLocation: dependency.declarationLocation,
					directParent: scope.instantiable.concreteInstantiable,
					closingReceive: closingReceive,
					lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
						closingCycleWith: declaredPropertyForDependency,
						validatedPropertiesInCycle: propertiesInCycle,
						lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
					),
				)
			}
			if case let (receive, beingBuiltIndex)? = optionalReceiveOfPropertyBeingBuilt {
				let beingBuiltProperty = instantiationStack[beingBuiltIndex]
				let validatedReceivedProperty = receive.property.asValidatedForDependencyCycles
				let lazilyInstantiatedProperties = Self.lazilyInstantiatedProperties(
					closingCycleWith: receive.property,
					validatedPropertiesInCycle: instantiationStack[0...beingBuiltIndex],
					lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
				)
				if beingBuiltIndex == 0 {
					throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
						instantiated: beingBuiltProperty,
						receivedPropertyChain: [validatedReceivedProperty],
						declarationLocation: receive.declarationLocation,
						lazilyInstantiatedProperties: lazilyInstantiatedProperties,
						requiredOnlyIfAvailableAliases: [],
					)
				} else {
					// A received cycle is never valid.
					throw invalidCycleError(
						typesInCycle: ([validatedReceivedProperty] + instantiationStack[0...beingBuiltIndex]).map(\.typeDescription),
						property: beingBuiltProperty,
						declaredProperty: receive.aliasProperty ?? receive.property,
						declarationLocation: receive.declarationLocation,
						directParent: scope.instantiable.concreteInstantiable,
						closingReceive: CycleClosingReceive(aliasProperty: receive.aliasProperty),
						lazilyInstantiatedProperties: lazilyInstantiatedProperties,
					)
				}
			}

			var childClosestDeclarationByLabel = closestDeclarationByLabel
			for dependency in scope.instantiable.dependencies where scope.createdProperties.contains(dependency.property) {
				childClosestDeclarationByLabel[dependency.property.label] = .init(
					property: dependency.property,
					lazilyInstantiatedInstanceProperty: dependency.lazilyInstantiatedInstanceProperty,
					declarationLocation: dependency.declarationLocation,
					declaringType: scope.instantiable.concreteInstantiable,
				)
			}
			// A property this scope provides shadows an alias of it declared above, unless this scope's alias of it is
			// never created.
			var childReceivableAliases = receivableAliases.filter {
				!scope.providedProperties.containsPropertyOrItsUnwrappedForm($0.key)
					|| uncreatedAliasPropertiesProvidedByEnclosingScope.contains($0.key)
			}
			for (aliasProperty, alias) in declaredAliases {
				childReceivableAliases[aliasProperty] = alias
			}
			lazy var childReceivableProperties: Set<Property> = {
				// An `onlyIfAvailable` receive that is unavailable here is passed `nil`, so it provides nothing to the
				// scopes below. Availability mirrors `Scope.createScopeGenerator`'s: in a mock, only a property that is
				// still being built is unavailable.
				func isAvailable(_ onlyIfAvailableProperty: Property) -> Bool {
					// The instantiation stack holds a lazily instantiated property as the constant it stands for.
					if cyclesOnly {
						![onlyIfAvailableProperty, onlyIfAvailableProperty.asUnwrappedProperty].contains {
							instantiationStack.contains($0.asValidatedForDependencyCycles)
						}
					} else {
						[onlyIfAvailableProperty, onlyIfAvailableProperty.asUnwrappedProperty].contains {
							receivableProperties.contains($0) && !instantiationStack.contains($0.asValidatedForDependencyCycles)
						}
					}
				}
				var childReceivableProperties = receivableProperties
				for dependency in scope.instantiable.dependencies {
					switch dependency.source {
					case let .received(onlyIfAvailable):
						if !onlyIfAvailable || isAvailable(dependency.property) {
							childReceivableProperties.insert(dependency.property)
						}
					case .instantiated, .forwarded, .aliased:
						childReceivableProperties.insert(dependency.property)
						// A lazily instantiated property can also be received by value, as the instance it creates.
						if let instanceProperty = dependency.lazilyInstantiatedInstanceProperty {
							childReceivableProperties.insert(instanceProperty)
						}
					}
				}
				// A mock root also provides the received dependencies it promotes.
				childReceivableProperties.formUnion(scope.providedProperties)
				return childReceivableProperties
			}()
			for childPropertyToGenerate in scope.propertiesToGenerate {
				switch childPropertyToGenerate {
				case let .instantiated(declaredChildProperty, childScope, _):
					// A lazily instantiated property is validated as the constant it stands for.
					let childProperty = declaredChildProperty.asValidatedForDependencyCycles
					guard !childPropertyStack.contains(childProperty) else {
						// There is a cycle in our scope tree. Do not re-enter it.
						continue
					}
					// Neither the child nor, when it is lazily instantiated, its instance can be received in the tree it creates.
					var receivablePropertiesInChildTree = childReceivableProperties
					receivablePropertiesInChildTree.remove(declaredChildProperty)
					if let instanceProperty = childPropertyToGenerate.lazilyInstantiatedInstanceProperty {
						receivablePropertiesInChildTree.remove(instanceProperty)
					}
					try validatePropertiesAreFulfillable(
						on: childScope,
						receivableProperties: receivablePropertiesInChildTree,
						receivableAliases: childReceivableAliases,
						boundProperties: boundProperties,
						closestDeclarationByLabel: childClosestDeclarationByLabel,
						validatesCycles: validatesCycles,
						validatesHiddenProperties: validatesHiddenProperties,
						property: childProperty,
						propertyStack: childPropertyStack,
						lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
						root: root,
					)
				case .aliased:
					break
				}
			}
		}

		for rootScope in rootScopes {
			try validatePropertiesAreFulfillable(
				on: rootScope.scope,
				receivableProperties: Set(rootScope.scope.properties),
				receivableAliases: [:],
				boundProperties: rootScope.boundProperties,
				closestDeclarationByLabel: [:],
				validatesCycles: true,
				// A production root without a mock is validated for production; only mocks generate its tree here.
				validatesHiddenProperties: !cyclesOnly
					|| rootScope.scope.instantiable.generateMock
					|| additionalMockRootScopes.contains { $0.scope == rootScope.scope },
				property: nil,
				propertyStack: [],
				lazilyInstantiatedDeclarations: [:],
				root: rootScope.scope.instantiable.concreteInstantiable,
			)
		}
		// Walking the other additional mock roots for cycles here could reject a mock that compiles today. Their
		// mocks are validated for cycles after promotion, in `createMockRootScopeGenerator`.
		for rootScope in additionalMockRootScopes where !rootScopes.contains(where: { $0.scope == rootScope.scope }) {
			try validatePropertiesAreFulfillable(
				on: rootScope.scope,
				receivableProperties: Set(rootScope.scope.properties),
				receivableAliases: [:],
				boundProperties: rootScope.boundProperties,
				closestDeclarationByLabel: [:],
				validatesCycles: false,
				validatesHiddenProperties: true,
				property: nil,
				propertyStack: [],
				lazilyInstantiatedDeclarations: [:],
				root: rootScope.scope.instantiable.concreteInstantiable,
			)
		}

		if !unfulfillableProperties.isEmpty {
			throw DependencyTreeGeneratorError.unfulfillableProperties(Array(unfulfillableProperties))
		}
		if !hiddenReceivedProperties.isEmpty {
			throw DependencyTreeGeneratorError.hiddenReceivedProperties(Array(hiddenReceivedProperties))
		}
	}

	/// Validates that every reachable type description has a corresponding `@Instantiable` that production
	/// code can build, reporting the first missing type in type order. A `mockOnly` declaration exists solely
	/// for mock generation, so it does not count. Were it counted, a type it fulfills that shares a concrete
	/// type with a production declaration would be built from whichever declaration a set iteration reached first.
	private func validateReachableTypeDescriptions() throws {
		if let unbuildableTypeDescription = reachableTypeDescriptions
			.filter({ typeDescriptionToFulfillingInstantiableMap[$0]?.mockOnly != false })
			.min()
		{
			// The map's values can hold the same instantiable under several keys, so collect into a set.
			let referencingProperties = Set(
				typeDescriptionToFulfillingInstantiableMap.values.flatMap { instantiable in
					instantiable.dependencies
						.filter { $0.isInstantiated && $0.asInstantiatedType == unbuildableTypeDescription }
						.map { DependencyTreeGeneratorError.LocatedProperty(property: $0.property, declarationLocation: $0.declarationLocation) }
				},
			)
			throw DependencyTreeGeneratorError.noInstantiableFound(
				unbuildableTypeDescription,
				referencedBy: Array(referencingProperties),
				fulfilledByMockOnlyDeclaration: typeDescriptionToFulfillingInstantiableMap[unbuildableTypeDescription] != nil,
			)
		}
	}
}

// MARK: - Dependency

extension Dependency {
	fileprivate var isInstantiated: Bool {
		switch source {
		case .instantiated:
			true
		case .aliased, .forwarded, .received:
			false
		}
	}

	fileprivate var isForwarded: Bool {
		switch source {
		case .forwarded:
			true
		case .aliased, .instantiated, .received:
			false
		}
	}

	/// Whether the dependency can close a dependency cycle through the property it is fulfilled by. A forwarded
	/// dependency cannot: it is an argument of the `Instantiator` that builds its type. Nor can a
	/// `@Received(onlyIfAvailable: true)` dependency: generation passes it `nil` while the property is still being
	/// built, whatever kind of property that is, as it does when the property is the non-optional form of the one
	/// received.
	fileprivate var canCloseDependencyCycle: Bool {
		switch source {
		case let .received(onlyIfAvailable):
			!onlyIfAvailable
		case .instantiated, .aliased:
			true
		case .forwarded:
			false
		}
	}
}

// MARK: - Set

extension Set<Property> {
	/// Whether the set contains `property` or, for an optional `property`, its non-optional form.
	fileprivate func containsPropertyOrItsUnwrappedForm(_ property: Property) -> Bool {
		contains(property) || contains(property.asUnwrappedProperty)
	}
}

// MARK: - TypeDescription

extension TypeDescription {
	fileprivate var leastQualifiedTypeDescription: TypeDescription {
		switch self {
		case let .nested(name, _, generics):
			.simple(name: name, generics: generics)
		case let .any(typeDescription),
		     let .implicitlyUnwrappedOptional(typeDescription),
		     let .optional(typeDescription),
		     let .some(typeDescription):
			typeDescription.leastQualifiedTypeDescription
		case .array,
		     .attributed,
		     .closure,
		     .composition,
		     .dictionary,
		     .metatype,
		     .simple,
		     .tuple,
		     .unknown,
		     .void:
			self
		}
	}
}

// MARK: - [Property: Property]

extension [Property: Property] {
	/// The lazily instantiated properties being instantiated, keyed by the constant each is validated as,
	/// with `declaredProperty` added when it is lazily instantiated.
	fileprivate func recordingLazilyInstantiated(_ declaredProperty: Property) -> Self {
		guard declaredProperty.propertyType.isLazilyInstantiated else { return self }
		var lazilyInstantiatedDeclarations = self
		lazilyInstantiatedDeclarations[declaredProperty.asValidatedForDependencyCycles] = declaredProperty
		return lazilyInstantiatedDeclarations
	}
}
