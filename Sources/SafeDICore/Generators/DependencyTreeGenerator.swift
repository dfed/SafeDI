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

	/// Generates mock code for all `@Instantiable` types.
	public func generateMockCode(
		mockConditionalCompilation: String?,
		currentModuleSourceFilePaths: Set<String>? = nil,
		additionalMocksToGenerate: Set<String> = [],
	) async throws -> MockGenerationResult {
		// Build a map of erased wrapper types → concrete fulfilling types.
		// This lets mocks construct types like AnyUserService(DefaultUserService())
		// even when the erased type isn't directly @Instantiable.
		var erasedToConcreteTypeMap = [TypeDescription: TypeDescription]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			for dependency in instantiable.dependencies {
				if case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential) = dependency.source,
				   erasedToConcreteExistential,
				   let concreteType = fulfillingTypeDescription?.asInstantiatedType
				{
					erasedToConcreteTypeMap[dependency.property.typeDescription] = concreteType
				}
			}
		}

		// Build mock scope mapping — like production but includes all types and
		// promotes received dependencies as instantiated children.
		let typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping()

		// Validate mock scopes for cycles. Mock-only types (generateMock: true without
		// isRoot) bypass root validation but can still have partially-lazy cycles.
		// Uses cyclesOnly to skip unfulfillable property checks — mock-only types
		// have unfulfillable received properties by design (they become mock parameters).
		try validatePropertiesAreFulfillable(
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
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
			let instantiable = typeDescriptionToFulfillingInstantiableMap[instantiable.concreteInstantiable] ?? instantiable
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
				if let childScope {
					try validateNoForwardedProperties(
						for: dependency,
						instantiable: childScope.instantiable,
						parent: scope.instantiable,
					)
				}
			}

			let mockRoot = try createMockRootScopeGenerator(
				for: instantiable,
				scope: scope,
				typeDescriptionToScopeMap: typeDescriptionToScopeMap,
				erasedToConcreteTypeMap: erasedToConcreteTypeMap,
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
			of: (root: GeneratedRoot, configurationTypes: [(typeName: String, structCode: String)]).self,
			returning: [(root: GeneratedRoot, configurationTypes: [(typeName: String, structCode: String)])].self,
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
					async let configurationTypes = mockRoot.collectConfigurationTypes(
						cycleEdges: cycleEdges,
						sendableConfigurationTypeNames: sendableConfigurationTypeNames,
					)
					return try await (
						root: GeneratedRoot(
							typeDescription: instantiable.concreteInstantiable,
							sourceFilePath: instantiable.sourceFilePath,
							code: code,
						),
						configurationTypes: configurationTypes,
					)
				}
			}
			var results = [(root: GeneratedRoot, configurationTypes: [(typeName: String, structCode: String)])]()
			for try await result in taskGroup {
				results.append(result)
			}
			return results
		}

		let rootedTypeNames = Set(generatedRoots.map(\.root.typeDescription.asSource))
		// Deduplicate configuration types by type name across all roots.
		// With cycleEdges applied uniformly, every root produces the same struct
		// for a given type, so first-wins by alphabetical root order is stable.
		var seenTypeNames = Set<String>()
		var rootedConfigurationExtensions = [String: String]()
		var sharedConfigurationExtensions = [(typeName: String, structCode: String)]()
		for result in generatedRoots.sorted(by: { $0.root.typeDescription < $1.root.typeDescription }) {
			for configType in result.configurationTypes {
				if seenTypeNames.insert(configType.typeName).inserted {
					if rootedTypeNames.contains(configType.typeName) {
						rootedConfigurationExtensions[configType.typeName] = configType.structCode
					} else {
						sharedConfigurationExtensions.append(configType)
					}
				}
			}
		}

		let mergedGeneratedRoots = generatedRoots.map { result in
			let configurationCode = rootedConfigurationExtensions[result.root.typeDescription.asSource].map { structCode in
				generateMockConfigurationCode(
					configurationExtensions: [(typeName: result.root.typeDescription.asSource, structCode: structCode)],
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

	private func generateMockConfigurationCode(
		configurationExtensions: [(typeName: String, structCode: String)],
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
		case noInstantiableFound(TypeDescription, referencedAt: [Dependency.DeclarationLocation?])
		case unfulfillableProperties([UnfulfillableProperty])
		case instantiableHasForwardedProperty(property: Property, declarationLocation: Dependency.DeclarationLocation?, instantiableWithForwardedProperty: Instantiable, forwardedDeclarations: [LocatedProperty], parent: Instantiable)
		/// Reported at the dependency declaration that closes the cycle – the `@Instantiated` or `@Received`
		/// property whose type is already on the instantiation stack – with a note at each member type’s
		/// `@Instantiable` declaration. See `DependencyCycle`.
		case constantDependencyCycleDetected(DependencyCycle)
		/// Reported at the dependency declaration that closes the cycle, with a note at each member type’s
		/// `@Instantiable` declaration. See `DependencyCycle`.
		case partiallyLazyDependencyCycleDetected(DependencyCycle)
		/// Reported at the `@Received` declaration on `directParent` that closes the cycle, with a note at each
		/// member type’s `@Instantiable` declaration. See `DependencyCycle`.
		case receivedInstantiatorDependencyCycleDetected(property: Property, directParent: TypeDescription, cycle: DependencyCycle)
		/// Reported at the `@Received` declaration that closes the chain: the one that receives `instantiated` back
		/// inside the tree `instantiated` creates. No notes; the chain is spelled out in the message.
		case receivedConstantCycleDetected(instantiated: Property, receivedPropertyChain: [Property], declarationLocation: Dependency.DeclarationLocation?)
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
			case let .noInstantiableFound(typeDescription, referencedAt):
				// Sorted by location so the order never depends on map iteration.
				referencedAt.map {
					SourceDiagnostic(
						severity: .error,
						location: $0,
						message: "No `@\(InstantiableVisitor.macroName)`-decorated type or extension found to fulfill `@\(Dependency.Source.instantiatedRawValue)`-decorated property with type `\(typeDescription.asSource)`",
					)
				}
				.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .unfulfillableProperties(unfulfillableProperties):
				unfulfillableProperties
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .instantiableHasForwardedProperty(property, declarationLocation, instantiable, forwardedDeclarations, parent):
				[
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "Property `\(property.asSource)` on \(parent.concreteInstantiable.asSource) has at least one @\(Dependency.Source.forwardedRawValue) property. Property should instead be of type `\(Dependency.instantiatorType)<\(instantiable.concreteInstantiable.asSource)>`.",
					),
				] + forwardedDeclarations.map {
					SourceDiagnostic(
						severity: .note,
						location: $0.declarationLocation,
						message: "@\(Dependency.Source.forwardedRawValue) property `\($0.property.asSource)` is declared here",
					)
				}
			case let .constantDependencyCycleDetected(cycle):
				cycle.sourceDiagnostics(summary: "Dependency cycle detected: \(cycle.asSource)")
			case let .partiallyLazyDependencyCycleDetected(cycle):
				cycle.sourceDiagnostics(summary: "Dependency cycle detected. Cycles with a mix of constant and lazy (Instantiator) dependencies cannot be resolved. Make all dependencies in the cycle lazy by using Instantiator: \(cycle.asSource)")
			case let .receivedInstantiatorDependencyCycleDetected(property, directParent, cycle):
				cycle.sourceDiagnostics(summary: "Dependency cycle detected! @\(Dependency.Source.instantiatedRawValue) `\(property.asSource)` is @\(Dependency.Source.receivedRawValue) in tree created by @\(Dependency.Source.instantiatedRawValue) `\(property.asSource)`. Declare @\(Dependency.Source.receivedRawValue) `\(property.asSource)` on `\(directParent.asSource)` as @\(Dependency.Source.instantiatedRawValue) to fix. Full cycle: \(cycle.asSource)")
			case let .receivedConstantCycleDetected(instantiated, receivedPropertyChain, declarationLocation):
				[
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "Dependency received in same chain it is instantiated: "
							+ "@\(Dependency.Source.instantiatedRawValue) \(instantiated.asSource) -> "
							+ receivedPropertyChain
							.map { "@\(Dependency.Source.receivedRawValue) \($0.asSource)" }
							.joined(separator: " -> "),
					),
				]
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

		/// A property together with where it is declared.
		struct LocatedProperty: Hashable {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
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

			/// A single `error:` line. The suggestion or fix hint is folded into it rather than emitted as a
			/// `note:` because it belongs at the same location, and Xcode drops notes from build-tool output.
			var sourceDiagnostics: [SourceDiagnostic] {
				let chain = ([instantiable.concreteInstantiable] + parentStack + [root]).reversed()
				let summary = "@\(Dependency.Source.receivedRawValue) property `\(property.asSource)` is not @\(Dependency.Source.instantiatedRawValue) or @\(Dependency.Source.forwardedRawValue) in chain: \(chain.map(\.asSource).joined(separator: " -> "))"
				// A diagnostic carries at most one fix-it – Xcode offers no Apply at all for a diagnostic with several –
				// and a fix-it is offered only when it is exactly the repair the hint names.
				let hint: String
				let fixIts: [SourceDiagnostic.FixIt]
				if property.typeDescription.isOptional,
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

			var asSource: String {
				members
					.map(\.typeDescription.asSource)
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

	private var rootScopeGenerators: [RootScopeInfo] {
		get throws {
			let rootScopeGenerators: [RootScopeInfo] = try {
				try validateReachableTypeDescriptions()

				let typeDescriptionToScopeMap = try createTypeDescriptionToScopeMapping()
				try validatePropertiesAreFulfillable(typeDescriptionToScopeMap: typeDescriptionToScopeMap, cyclesOnly: false)
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
				if let wholeModuleImport = $0.value.first(where: {
					$0.kind.isEmpty
						&& $0.type.isEmpty
				}) {
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
	private func createMockRootScopeGenerator(
		for instantiable: Instantiable,
		scope: Scope,
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		erasedToConcreteTypeMap: [TypeDescription: TypeDescription],
	) throws -> ScopeGenerator {
		// Recursively collect all transitive received properties from the scope tree
		// and any promoted scopes' subtrees. Results are cached per Scope identity
		// (via ObjectIdentifier) so each scope is visited at most once — O(total_scopes).
		var cache = [ObjectIdentifier: (received: Set<Property>, onlyIfAvailable: Set<Property>)]()
		let (initialReceived, initialOnlyIfAvailable) = Self.collectReceivedProperties(
			from: scope,
			cache: &cache,
		)

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

		while let property = worklist.popLast() {
			var dependencyType = property.typeDescription.asInstantiatedType
			if typeDescriptionToScopeMap[dependencyType] == nil,
			   let concreteType = erasedToConcreteTypeMap[property.typeDescription]
			{
				dependencyType = concreteType
			}
			guard let promotedScope = typeDescriptionToScopeMap[dependencyType],
			      visitedTypes.insert(dependencyType).inserted
			else { continue }

			let (scopeReceived, scopeOnlyIfAvailable) = Self.collectReceivedProperties(
				from: promotedScope,
				cache: &cache,
			)
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
		let forwardedProperties = Set(
			instantiable.dependencies
				.filter { $0.source == .forwarded }
				.map(\.property),
		)
		let mockRootScope = Scope(instantiable: instantiable)
		mockRootScope.propertiesToGenerate = scope.propertiesToGenerate

		// Track promoted (label, type) pairs to prevent duplicate promotions when
		// both required and onlyIfAvailable versions of the same dep exist.
		// Property.< sorts non-optional before optional, so the required version
		// wins and the optional version is skipped.
		var promotedLabelAndTypes = Set<String>()
		for receivedProperty in allReceived.sorted() {
			guard !allOnlyIfAvailable.contains(receivedProperty),
			      !forwardedProperties.contains(receivedProperty)
			else { continue }

			let labelAndType = "\(receivedProperty.label):\(receivedProperty.typeDescription.asInstantiatedType.asSource)"
			guard promotedLabelAndTypes.insert(labelAndType).inserted else { continue }

			var dependencyType = receivedProperty.typeDescription.asInstantiatedType
			var erasedToConcreteExistential = false
			if typeDescriptionToScopeMap[dependencyType] == nil,
			   let concreteType = erasedToConcreteTypeMap[receivedProperty.typeDescription]
			{
				dependencyType = concreteType
				erasedToConcreteExistential = true
			}
			guard let receivedScope = typeDescriptionToScopeMap[dependencyType] else {
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
		try validatePropertiesAreFulfillable(
			onRootScopes: Self.childrenRequireEachOther(in: mockRootScope, cache: &cache) ? [mockRootScope] : [],
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: true,
		)

		// Build the final ScopeGenerator once. The mock root binds every received
		// property it does not promote — as a `mock()` parameter or a `SafeDIOverrides`
		// entry — so each is receivable throughout the tree.
		return try mockRootScope.createScopeGenerator(
			for: nil,
			propertyStack: [],
			receivableProperties: allReceived,
			erasedToConcreteExistential: false,
			forMockGeneration: true,
		)
	}

	/// Walks a post-promotion mock root scope for dependency cycles.
	/// The mock root scope has @Received dependencies promoted as children,
	/// which can create cycles not visible in the pre-promotion scope.
	private func validateMockRootScopeForCycles(
		_ scope: Scope,
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		propertyStack: [Property] = [],
	) throws {
		// Check dependencies for cycles (catches @Received references back to ancestors).
		// Skip forwarded dependencies — they're runtime Instantiator closure parameters.
		for dependency in scope.instantiable.dependencies where dependency.source != .forwarded {
			let propertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
			guard let cycleIndex = propertyStack.firstIndex(of: propertyForDependency) else {
				continue
			}
			let typesInCycle = (
				[propertyForDependency]
					+ propertyStack[0...cycleIndex],
			).map(\.typeDescription)
			try throwIfInvalidCycle(
				typesInCycle: typesInCycle,
				property: propertyForDependency,
				declarationLocation: dependency.declarationLocation,
				directParent: scope.instantiable.concreteInstantiable,
				isReceived: dependency.source.isReceived,
			)
		}

		// Recurse into children.
		for childPropertyToGenerate in scope.propertiesToGenerate {
			switch childPropertyToGenerate {
			case let .instantiated(childProperty, childScope, _):
				guard !propertyStack.contains(childProperty) else { continue }
				let nextStack = [childProperty] + propertyStack
				try validateMockRootScopeForCycles(
					childScope,
					typeDescriptionToScopeMap: typeDescriptionToScopeMap,
					propertyStack: nextStack,
				)
			case .aliased:
				break
			}
		}
	}

	/// Whether the instantiated children of `scope` require one another in a cycle:
	/// each child's subtree requires (not `onlyIfAvailable`) a sibling that,
	/// directly or through other siblings, requires it. Such children cannot be
	/// ordered so that each is built after the siblings it receives.
	private static func childrenRequireEachOther(
		in scope: Scope,
		cache: inout [ObjectIdentifier: (received: Set<Property>, onlyIfAvailable: Set<Property>)],
	) -> Bool {
		var children = [(property: Property, scope: Scope)]()
		for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
			children.append((property, childScope))
		}
		var childIndexByProperty = [Property: Int]()
		for (index, child) in children.enumerated() {
			childIndexByProperty[child.property] = index
		}
		let requiredSiblingIndices = children.map { child in
			let (received, onlyIfAvailable) = collectReceivedProperties(from: child.scope, cache: &cache)
			return received.compactMap { property in
				property != child.property && !onlyIfAvailable.contains(property)
					? childIndexByProperty[property]
					: nil
			}
		}
		// Depth-first search for a back edge.
		var visitingIndices = Set<Int>()
		var visitedIndices = Set<Int>()
		func reachesVisitingIndex(from index: Int) -> Bool {
			guard visitedIndices.insert(index).inserted else {
				return visitingIndices.contains(index)
			}
			visitingIndices.insert(index)
			defer { visitingIndices.remove(index) }
			return requiredSiblingIndices[index].contains(where: reachesVisitingIndex(from:))
		}
		return children.indices.contains(where: reachesVisitingIndex(from:))
	}

	/// Classifies a detected cycle and throws the appropriate error, or
	/// returns silently if the cycle is valid. Called from both
	/// `validatePropertiesAreFulfillable` (production graph, and a mock root whose
	/// children require one another) and `validateMockRootScopeForCycles` (mock
	/// graph after `@Received` promotion).
	///
	/// Rejected:
	/// - Constant entry point in a fully-constant cycle → `.constantDependencyCycleDetected`.
	/// - Constant entry point with any lazy hop → `.partiallyLazyDependencyCycleDetected`.
	/// - Non-constant entry point that originated from an `@Received` → `.receivedInstantiatorDependencyCycleDetected`.
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
	private func throwIfInvalidCycle(
		typesInCycle: [TypeDescription],
		property: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		directParent: TypeDescription,
		isReceived: Bool,
	) throws {
		let cycle = DependencyTreeGeneratorError.DependencyCycle(
			declarationLocation: declarationLocation,
			members: typesInCycle.map { typeDescription in
				DependencyTreeGeneratorError.DependencyCycle.Member(
					typeDescription: typeDescription,
					declarationLocation: typeDescriptionToFulfillingInstantiableMap[typeDescription.asInstantiatedType]?.declarationLocation,
				)
			},
		)
		if property.propertyType.isConstant {
			let hasLazyHop = typesInCycle.contains(where: { !$0.propertyType.isConstant })
			if hasLazyHop {
				throw DependencyTreeGeneratorError.partiallyLazyDependencyCycleDetected(cycle)
			} else {
				throw DependencyTreeGeneratorError.constantDependencyCycleDetected(cycle)
			}
		} else if isReceived {
			throw DependencyTreeGeneratorError.receivedInstantiatorDependencyCycleDetected(
				property: property,
				directParent: directParent,
				cycle: cycle,
			)
		}
		// Fully-lazy cycle (Instantiator entry, not received) — valid, no error.
	}

	/// Mirrors ScopeGenerator's `receivedProperties` and `onlyIfAvailableUnwrappedReceivedProperties`
	/// computation but operates on Scope objects directly, with memoization for O(1) revisits.
	///
	/// - Returns: `received`, every property the subtree needs from an ancestor, and
	///   `onlyIfAvailable`, those of them that every receiver in the subtree receives only if
	///   available. A property some receiver requires is not in `onlyIfAvailable`.
	private static func collectReceivedProperties(
		from scope: Scope,
		cache: inout [ObjectIdentifier: (received: Set<Property>, onlyIfAvailable: Set<Property>)],
	) -> (received: Set<Property>, onlyIfAvailable: Set<Property>) {
		let id = ObjectIdentifier(scope)
		if let cached = cache[id] {
			return cached
		}
		// Cycle sentinel — re-entrant calls return empty (cycles contribute no new received).
		cache[id] = ([], [])

		// Properties declared at this scope (instantiated/aliased children).
		let propertiesToDeclare = Set(scope.propertiesToGenerate.compactMap { propertyToGenerate -> Property? in
			switch propertyToGenerate {
			case let .instantiated(property, _, _): property
			case let .aliased(property, _, _, _, _): property
			}
		})

		// Forwarded properties at this scope.
		let forwardedProperties = Set(
			scope.instantiable.dependencies
				.filter { $0.source == .forwarded }
				.map(\.property),
		)

		var received = Set<Property>()
		var onlyIfAvailable = Set<Property>()
		// Received properties some receiver in this subtree requires. A property can be
		// received both ways — e.g. a required `x: X` and an `onlyIfAvailable` alias
		// fulfilled by `x: X` — and a required receive wins.
		var required = Set<Property>()

		// Collect from instantiated children — mirrors ScopeGenerator's receivedProperties aggregation.
		// Aliases are handled below in the own-dependency loop: alias children's receivedProperties
		// = [fulfillingProperty], but the own-dependency union unconditionally adds the same
		// fulfillingProperty, making the child-path subtraction/filter redundant.
		for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
			let (childReceived, childOnlyIfAvailable) = collectReceivedProperties(
				from: childScope,
				cache: &cache,
			)
			let childReceivedFromAncestors = childReceived
				.subtracting(propertiesToDeclare)
				.filter { property in
					!property.typeDescription.isOptional
						|| !propertiesToDeclare.contains(property.asUnwrappedProperty)
				}
				.subtracting(forwardedProperties)
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
				// @Instantiated sibling), the alias resolves against that local binding —
				// it's not a received dependency that needs promoting.
				guard !propertiesToDeclare.contains(fulfillingProperty) else { break }
				received.insert(fulfillingProperty)
				if isOnlyIfAvailable {
					onlyIfAvailable.insert(fulfillingProperty)
				} else {
					required.insert(fulfillingProperty)
				}
			case .instantiated, .forwarded:
				break
			}
		}

		let result = (received, onlyIfAvailable.subtracting(required))
		cache[id] = result
		return result
	}

	/// Builds a scope mapping for mock generation. Similar to `createTypeDescriptionToScopeMapping`
	/// but includes ALL types (not just reachable from roots). Received dependencies are NOT
	/// promoted here — they're promoted at the root level in `createMockRootScopeGenerator`.
	private func createMockTypeDescriptionToScopeMapping() -> [TypeDescription: Scope] {
		// Create scopes for all types. Process non-mockOnly types first so they
		// claim additional-type slots. mockOnly types then overwrite slots whose
		// existing scope lacks a compatible hand-written mock.
		// Multiple map entries can share a concreteInstantiable but have different
		// instantiableTypes (e.g., a mockOnly with extra fulfillingAdditionalTypes).
		// Reuse the same scope for all entries sharing a concreteInstantiable so
		// every instantiableType is mapped.
		var visitedConcreteTypeToScope = [TypeDescription: Scope]()
		let typeDescriptionToScopeMap: [TypeDescription: Scope] = typeDescriptionToFulfillingInstantiableMap.values
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

		// Populate the propertiesToGenerate on each scope.
		for scope in Set(typeDescriptionToScopeMap.values) {
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case let .instantiated(_, erasedToConcreteExistential):
					let instantiatedType = dependency.asInstantiatedType
					if let instantiable = typeDescriptionToFulfillingInstantiableMap[instantiatedType],
					   let instantiatedScope = typeDescriptionToScopeMap[instantiatedType]
					{
						try validateNoForwardedProperties(
							for: dependency,
							instantiable: instantiable,
							parent: scope.instantiable,
						)
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
		return typeDescriptionToScopeMap
	}

	/// Validates that a constant `@Instantiated` dependency has no `@Forwarded` properties.
	private func validateNoForwardedProperties(
		for dependency: Dependency,
		instantiable: Instantiable,
		parent: Instantiable,
	) throws {
		if dependency.property.propertyType.isConstant {
			let forwardedDependencies = instantiable.dependencies.filter(\.isForwarded)
			guard forwardedDependencies.isEmpty else {
				throw DependencyTreeGeneratorError
					.instantiableHasForwardedProperty(
						property: dependency.property,
						declarationLocation: dependency.declarationLocation,
						instantiableWithForwardedProperty: instantiable,
						forwardedDeclarations: forwardedDependencies.map {
							DependencyTreeGeneratorError.LocatedProperty(property: $0.property, declarationLocation: $0.declarationLocation)
						},
						parent: parent,
					)
			}
		}
	}

	/// Validates scopes for cycles and optionally for unfulfillable properties.
	/// When `cyclesOnly` is true, unfulfillable property collection is skipped —
	/// used for mock-only types where unfulfillable received properties are expected
	/// (they become required mock parameters).
	private func validatePropertiesAreFulfillable(
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		cyclesOnly: Bool,
	) throws {
		var rootScopes = rootInstantiables.compactMap { typeDescriptionToScopeMap[$0] }
		// When checking cycles only (mock validation), also validate non-root types
		// that have generateMock enabled — they bypass root entry points.
		if cyclesOnly {
			let rootInstantiableSet = Set(rootInstantiables)
			for scope in Set(typeDescriptionToScopeMap.values)
				where scope.instantiable.generateMock && !rootInstantiableSet.contains(scope.instantiable.concreteInstantiable)
			{
				rootScopes.append(scope)
			}
		}
		try validatePropertiesAreFulfillable(
			onRootScopes: rootScopes,
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: cyclesOnly,
		)
	}

	/// Validates the trees rooted at `rootScopes` for cycles and optionally for
	/// unfulfillable properties. See `validatePropertiesAreFulfillable(typeDescriptionToScopeMap:cyclesOnly:)`.
	private func validatePropertiesAreFulfillable(
		onRootScopes rootScopes: [Scope],
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		cyclesOnly: Bool,
	) throws {
		var unfulfillableProperties = Set<DependencyTreeGeneratorError.UnfulfillableProperty>()
		func validatePropertiesAreFulfillable(
			on scope: Scope,
			receivableProperties: Set<Property>,
			property: Property?,
			propertyStack: [Property],
			root: TypeDescription,
		) throws {
			if let property {
				// Scopes whose received properties have all been walked, transitively, without throwing
				// and without bailing out on a cycle that isn't ours. Nothing reachable from such a scope
				// can complete a cycle back to the scopes on the current walk, so walking it again —
				// whatever received-property stack leads there — would also return without throwing.
				// Skipping those walks keeps this linear in the received-dependency graph rather than
				// exponential in the number of paths through it.
				var fullyWalkedScopes = Set<ObjectIdentifier>()
				/// - Returns: `true` when every received property reachable from `scope` was walked, or
				///   `false` when the walk bailed out on a cycle that isn't ours and so may be incomplete.
				func validateNoCycleInReceivedProperties(
					scope: Scope,
					receivedPropertyStack: [Property],
					instantiationStack: [Property],
				) throws -> Bool {
					let scopeIdentifier = ObjectIdentifier(scope)
					guard !fullyWalkedScopes.contains(scopeIdentifier) else {
						return true
					}
					var walkedEveryReceivedProperty = true
					for requiredReceivedProperty in scope.requiredReceivedProperties {
						let childProperty = requiredReceivedProperty.property
						guard childProperty != property else {
							throw DependencyTreeGeneratorError.receivedConstantCycleDetected(
								instantiated: property,
								receivedPropertyChain: receivedPropertyStack + [childProperty],
								declarationLocation: requiredReceivedProperty.declarationLocation,
							)
						}
						guard !receivedPropertyStack.contains(childProperty) else {
							// We've found a cycle, but it's not our cycle. Bail and let a future loop find this.
							// The remaining received properties on this scope go unwalked, so a later visit
							// through a different received-property stack must walk this scope again.
							return false
						}
						if let cycleIndex = instantiationStack.firstIndex(of: childProperty) {
							let instantiationProperties = Array(instantiationStack[0...cycleIndex])
							let typesInCycle = (
								[childProperty]
									+ receivedPropertyStack.reversed()
									+ instantiationProperties,
							).map(\.typeDescription)
							try throwIfInvalidCycle(
								typesInCycle: typesInCycle,
								property: childProperty,
								declarationLocation: requiredReceivedProperty.declarationLocation,
								directParent: scope.instantiable.concreteInstantiable,
								isReceived: !childProperty.propertyType.isConstant,
							)
						} else if let receivedPropertyScope = typeDescriptionToScopeMap[childProperty.typeDescription] {
							var childPropertyStack = receivedPropertyStack
							childPropertyStack.append(childProperty)
							let walkedEveryChildReceivedProperty = try validateNoCycleInReceivedProperties(
								scope: receivedPropertyScope,
								receivedPropertyStack: childPropertyStack,
								instantiationStack: instantiationStack,
							)
							walkedEveryReceivedProperty = walkedEveryReceivedProperty && walkedEveryChildReceivedProperty
						}
					}
					guard walkedEveryReceivedProperty else {
						return false
					}
					fullyWalkedScopes.insert(scopeIdentifier)
					return true
				}
				let instantiationStack: [Property] = [property] + propertyStack
				_ = try validateNoCycleInReceivedProperties(
					scope: scope,
					receivedPropertyStack: [],
					instantiationStack: instantiationStack,
				)
			}

			if !cyclesOnly {
				for requiredReceivedProperty in scope.requiredReceivedProperties {
					let receivedProperty = requiredReceivedProperty.property
					let parentContainsProperty = receivableProperties.contains(receivedProperty)
					let propertyIsCreatedAtThisScope = scope.createdProperties.contains(receivedProperty)
					if !parentContainsProperty, !propertyIsCreatedAtThisScope, property != nil {
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
						))
					}
				}
			}

			// Check children for cycles.
			// Skip forwarded dependencies — they're runtime parameters passed through
			// the Instantiator closure, not scope-level dependencies that create cycles.
			var childPropertyStack = propertyStack
			if let property {
				childPropertyStack.insert(property, at: 0)
			}
			for dependency in scope.instantiable.dependencies where dependency.source != .forwarded {
				let propertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
				guard let cycleIndex = childPropertyStack.firstIndex(of: propertyForDependency) else {
					continue
				}
				let typesInCycle = (
					[propertyForDependency]
						+ childPropertyStack[0...cycleIndex],
				).map(\.typeDescription)
				try throwIfInvalidCycle(
					typesInCycle: typesInCycle,
					property: propertyForDependency,
					declarationLocation: dependency.declarationLocation,
					directParent: scope.instantiable.concreteInstantiable,
					isReceived: dependency.source.isReceived,
				)
			}

			for childPropertyToGenerate in scope.propertiesToGenerate {
				switch childPropertyToGenerate {
				case let .instantiated(childProperty, childScope, _):
					guard !childPropertyStack.contains(childProperty) else {
						// There is a cycle in our scope tree. Do not re-enter it.
						continue
					}
					try validatePropertiesAreFulfillable(
						on: childScope,
						receivableProperties: receivableProperties
							.union(scope.properties)
							.removing(childProperty),
						property: childProperty,
						propertyStack: childPropertyStack,
						root: root,
					)
				case .aliased:
					break
				}
			}
		}

		for rootScope in rootScopes {
			try validatePropertiesAreFulfillable(
				on: rootScope,
				receivableProperties: Set(rootScope.properties),
				property: nil,
				propertyStack: [],
				root: rootScope.instantiable.concreteInstantiable,
			)
		}

		if !unfulfillableProperties.isEmpty {
			throw DependencyTreeGeneratorError.unfulfillableProperties(Array(unfulfillableProperties))
		}
	}

	/// Validates that every reachable type description has a corresponding `@Instantiable`.
	private func validateReachableTypeDescriptions() throws {
		for reachableTypeDescription in reachableTypeDescriptions.sorted() {
			if typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] == nil {
				// The map's values can hold the same instantiable under several keys, so collect into a set.
				let referencingDeclarationLocations = Set(
					typeDescriptionToFulfillingInstantiableMap.values.flatMap { instantiable in
						instantiable.dependencies
							.filter { $0.isInstantiated && $0.asInstantiatedType == reachableTypeDescription }
							.map(\.declarationLocation)
					},
				)
				throw DependencyTreeGeneratorError.noInstantiableFound(
					reachableTypeDescription,
					referencedAt: Array(referencingDeclarationLocations),
				)
			}
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
}

// MARK: - Set

extension Set {
	fileprivate func removing(_ element: Element) -> Self {
		var setWithoutElement = self
		setWithoutElement.remove(element)
		return setWithoutElement
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
