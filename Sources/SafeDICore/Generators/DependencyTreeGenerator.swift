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
		try await validateSendableBuildersCaptureNoNonSendableWrapper(inTreesRootedAt: rootScopeGenerators.map { ($0.instantiable, $0.scopeGenerator) })

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
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let mockScopes = try mockScopes(additionalMocksToGenerate: additionalMocksToGenerate, receivedPropertiesCache: &receivedPropertiesCache)
		let typeDescriptionToScopeMap = mockScopes.typeDescriptionToScopeMap
		let forwardedParameterMockDefaults = mockScopes.forwardedParameterMockDefaults

		// Create mock-root ScopeGenerators using the production Scope tree.
		var seen = Set<TypeDescription>()
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation(scopes: typeDescriptionToScopeMap.values)
		var mockRoots = [(instantiable: Instantiable, scopeGenerator: ScopeGenerator)]()
		var mockRootErrors = [DependencyTreeGeneratorError]()
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
			let instantiable = mockRootInstantiable(for: instantiable, scope: scope)
			// Without module scoping, every type belongs to the current module.
			let isDeclaredInCurrentModule = currentModuleSourceFilePaths.map { currentModuleSourceFilePaths in
				instantiable.sourceFilePath.map(currentModuleSourceFilePaths.contains) ?? false
			} ?? true
			guard isAdditionalMock || isDeclaredInCurrentModule else { continue }

			// Each mock root reports the first error it finds, and the errors of every mock root are reported.
			do {
				let mockRoot = try createMockRoot(
					for: instantiable,
					scope: scope,
					// A `generateMock: true` type declared in this module gets its mock whether
					// or not it is listed; any other type reaching here is generated only
					// because it is listed, so removing it from the list is also a fix.
					generatedMockReason: instantiable.generateMock && isDeclaredInCurrentModule ? .generateMock : .additionalMocksToGenerate,
					mockScopes: mockScopes,
					receivedPropertiesCache: &receivedPropertiesCache,
					childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
				)
				mockRoots.append((instantiable: instantiable, scopeGenerator: mockRoot))
			} catch let error as DependencyTreeGeneratorError {
				mockRootErrors.append(error)
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: mockRootErrors) {
			throw error
		}
		// From here on, the module's mock roots are handled together. These passes gate emitting the module's
		// mocks and read nothing a single root's report needs, so `requirements(forTypeNamed:generatesMock:)`
		// deliberately does not run them. A check that decides whether one root can be generated belongs in
		// `createMockRoot`, which that method and the loop above share.
		try await validateSendableBuildersCaptureNoNonSendableWrapper(inTreesRootedAt: mockRoots)

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

		// A type with a hand-written mock configures every property with the defaults the mock declares, whether
		// the property is built with the mock or with `init`: the struct is shared, so it cannot hold both. A
		// property built with `init` beneath a cycle edge, which no override reaches, passes the struct's default
		// for each of them too.
		// The mock's arguments are matched to the dependencies of the entry under the concrete type, which a
		// `mockOnly` declaration's mock is merged into, so a dependency's argument never counts as a default.
		let handWrittenMockDefaultParameters = typeDescriptionToFulfillingInstantiableMap.values
			.reduce(into: [TypeDescription: [ScopeGenerator.MockParameterNode.DefaultParameter]]()) { result, instantiable in
				guard let mockInitializer = instantiable.mockInitializer else { return }
				result[instantiable.concreteInstantiable] = ScopeGenerator.MockParameterNode.DefaultParameter.defaultParameters(
					of: mockInitializer,
					dependencies: (typeDescriptionToFulfillingInstantiableMap[instantiable.concreteInstantiable] ?? instantiable).dependencies,
				)
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
							handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
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

		// The second whole-module gate, not run by `requirements(forTypeNamed:generatesMock:)`; see the note above
		// `validateSendableBuildersCaptureNoNonSendableWrapper`.
		let nodesReadingConfiguration = try await validateConfigurationsAreBuiltOneWay(mockRoots: mockRoots, cycleEdges: cycleEdges)

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
					// The first node can be one that reads no overrides from the struct, beneath a cycle edge, built
					// the other way from the nodes that read them. The struct must describe those that read them.
					let structNode = nodesReadingConfiguration[configurationType.concreteType].flatMap { nodeReadingConfiguration in
						nodeReadingConfiguration.configurationRequirements == configurationType.configurationRequirements ? nil : nodeReadingConfiguration
					} ?? configurationType
					let structCode = ScopeGenerator.generateConfigurationStruct(
						for: structNode,
						cycleEdges: cycleEdges,
						sendableConfigurationTypeNames: sendableConfigurationTypeNames,
						handWrittenMockDefaultParameters: handWrittenMockDefaultParameters[configurationType.concreteType, default: []],
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

	/// What building the `@Instantiable` type named `typeName` needs when every dependency it receives is provided
	/// beside it, or `nil` when no declaration this generator knows has a concrete type of that name. The type is
	/// built as the mock root `generateMockCode` builds for a type listed in `additionalMocksToGenerate`, from
	/// every declaration this generator knows, so over every declaration the result is what the type's mock needs
	/// (or would need, were it generated), and over the declarations with every hand-written mock removed it is
	/// what the type needs in production; see `TypeRequirements`. The type's tree is validated as
	/// `generateMockCode` validates a listed type's root, through the same `mockScopes` and `createMockRoot`, so
	/// the result throws what building that root throws. The passes `generateMockCode` runs over every mock root
	/// together once its loop is done – that no `@Sendable` builder captures a non-`Sendable` wrapper, and that
	/// each `SafeDIMockConfiguration` is built one way – gate emitting the module's mocks and change nothing in
	/// the report, so they are deliberately not run here: a module they reject has no generated mock for the
	/// report to disagree with, and `generate` reports them with their fix-its.
	/// - Parameter generatesMock: Whether `mock()` is generated for the type, so that a hand-written method named
	///   `mock` is rejected as `generateMockCode` rejects it. Otherwise such a method is the type's mock, which
	///   the root is built with.
	public func requirements(forTypeNamed typeName: String, generatesMock: Bool) async throws -> TypeRequirements? {
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let mockScopes = try mockScopes(additionalMocksToGenerate: [typeName], receivedPropertiesCache: &receivedPropertiesCache)
		// The type's own entry in the scope map, which `generateMockCode` builds each mock root from. The name is
		// matched as `additionalMocksToGenerate` matches it, and the entry is chosen by type, never by map order.
		guard let (concreteType, scope) = mockScopes.typeDescriptionToScopeMap
			.filter({ $0.key == $0.value.instantiable.concreteInstantiable && $0.key.asSource == typeName })
			.min(by: { $0.key < $1.key })
		else { return nil }
		let instantiable = mockRootInstantiable(for: scope.instantiable, scope: scope)
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation(scopes: mockScopes.typeDescriptionToScopeMap.values)
		let mockRoot = try createMockRoot(
			for: instantiable,
			scope: scope,
			// A type that sets `generateMock: true` fails to generate in its own module; any other generated mock
			// exists only because the type is listed, so removing it from the list is also a fix.
			generatedMockReason: generatesMock ? (instantiable.generateMock ? .generateMock : .additionalMocksToGenerate) : nil,
			mockScopes: mockScopes,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
		)
		let parameters = await mockRoot.mockRootParameters(instantiable: instantiable)

		// The declarations the mock calls, each once, in the order the mock reaches them.
		var declarations = [TypeRequirements.Declaration]()
		var recordedDeclarations = Set<TypeRequirements.Declaration>()
		func record(_ declaration: TypeRequirements.Declaration) {
			if recordedDeclarations.insert(declaration).inserted {
				declarations.append(declaration)
			}
		}
		record(TypeRequirements.Declaration(typeDescription: concreteType, sourceFilePath: instantiable.sourceFilePath, kind: .instantiable))
		// A mock root is constructed with its hand-written mock whenever it has one.
		if instantiable.mockInitializer != nil {
			record(TypeRequirements.Declaration(
				typeDescription: concreteType,
				sourceFilePath: instantiable.mockDeclarationLocation?.filePath,
				kind: .handWrittenMock(methodName: instantiable.customMockName ?? InstantiableVisitor.mockMethodName),
			))
		}
		// Each node before its children, depth first, with a stack of the items left to record, since a mock tree can be
		// as deep as the module has types.
		var itemsToRecord = Array(parameters.parameterTree.reversed())
		while let item = itemsToRecord.popLast() {
			guard case let .property(node) = item else { continue }
			record(TypeRequirements.Declaration(typeDescription: node.concreteType, sourceFilePath: node.sourceFilePath, kind: .instantiable))
			if node.useMockInitializer {
				record(TypeRequirements.Declaration(
					typeDescription: node.concreteType,
					sourceFilePath: node.mockDeclarationLocation?.filePath,
					kind: .handWrittenMock(methodName: node.customMockName ?? InstantiableVisitor.mockMethodName),
				))
			}
			// The item recorded next is the last one on the stack, so the first child goes last.
			itemsToRecord.append(contentsOf: node.children.reversed())
		}

		/// The declarations that erase a concrete type to the type of `property`, or to the type of its
		/// instance, which is how the mock root resolves an erasure.
		func erasureDeclarations(to property: Property) -> Set<ErasureDeclaration> {
			Set([property.typeDescription, property.asLazilyInstantiatedInstanceProperty?.typeDescription].compactMap(\.self)
				.flatMap { mockScopes.erasureDeclarations[$0] ?? [] })
		}
		// A received property the mock root builds by erasure is built from a concrete type some other
		// declaration erases to its type. The mocked type's own erased `@Instantiated` properties are its own
		// declarations, already recorded.
		let rootInstantiatedProperties = Set(instantiable.dependencies.filter(\.isInstantiated).map(\.property))
		var erasures = [TypeRequirements.Erasure]()
		for case let .property(node) in parameters.parameterTree
			where node.erasedToConcreteExistential && !rootInstantiatedProperties.contains(node.property)
		{
			erasures.append(TypeRequirements.Erasure(
				property: node.property,
				concreteType: node.concreteType,
				declarations: erasureDeclarations(to: node.property)
					.filter { $0.concreteType == node.concreteType }
					.map(\.declaration)
					.sorted { ($0.declaringType, $0.property) < ($1.declaringType, $1.property) },
			))
		}

		// Forwarded parameters default as `generateMockRootCode` defaults them: from the construction
		// initializer, else from a hand-written mock of the forwarded type that takes no arguments.
		var constructionDefaults = [String: String]()
		for argument in parameters.rootConstructionInitializer?.arguments ?? [] {
			if let defaultExpression = argument.defaultValueExpression {
				constructionDefaults[argument.innerLabel] = defaultExpression
			}
		}
		var forwardedParameters = [TypeRequirements.ForwardedParameter]()
		for dependency in parameters.forwardedDependencies {
			let property = dependency.property
			let defaultExpression: String?
			if let constructionDefault = constructionDefaults[property.label] {
				defaultExpression = constructionDefault
			} else if let mockMethodName = mockScopes.forwardedParameterMockDefaults[property.typeDescription] {
				defaultExpression = "\(property.typeDescription.asSource).\(mockMethodName)()"
				record(TypeRequirements.Declaration(
					typeDescription: property.typeDescription,
					sourceFilePath: handWrittenMockFilePath(of: property.typeDescription),
					kind: .handWrittenMock(methodName: mockMethodName),
				))
			} else {
				defaultExpression = nil
			}
			forwardedParameters.append(TypeRequirements.ForwardedParameter(
				label: property.label,
				typeDescription: property.typeDescription,
				defaultExpression: defaultExpression,
			))
		}

		// A received property is a flat parameter because the mock root did not promote it: its type has no
		// scope and no single erasure, or `mockCanBuild` rejected the scope it would be built from.
		func reason(forReceived property: Property) -> TypeRequirements.RequiredParameter.Reason {
			func typeHasForwardedProperties(_ scope: Scope) -> TypeRequirements.RequiredParameter.Reason {
				.typeHasForwardedProperties(
					scope.instantiable.concreteInstantiable,
					forwardedProperties: scope.instantiable.dependencies.filter(\.isForwarded).map(\.property),
				)
			}
			let instantiatedType = property.typeDescription.asInstantiatedType
			if let scope = mockScopes.typeDescriptionToScopeMap[instantiatedType] {
				return typeHasForwardedProperties(scope)
			} else if let concreteType = Self.concreteTypeErased(to: property, in: mockScopes.erasedToConcreteTypeMap) {
				if let scope = mockScopes.typeDescriptionToScopeMap[concreteType] {
					return typeHasForwardedProperties(scope)
				} else {
					return .noInstantiableFulfillsType(concreteType)
				}
			} else {
				let erasedConcreteTypes = Set(erasureDeclarations(to: property).map(\.concreteType))
				if erasedConcreteTypes.count > 1 {
					return .erasedToMultipleConcreteTypes(instantiatedType, concreteTypes: erasedConcreteTypes.sorted())
				} else {
					return .noInstantiableFulfillsType(instantiatedType)
				}
			}
		}
		var requiredParameters = [TypeRequirements.RequiredParameter]()
		for property in parameters.flatReceivedProperties {
			requiredParameters.append(TypeRequirements.RequiredParameter(
				label: property.label,
				typeSource: property.typeDescription.asFunctionParameter.asSource,
				reason: reason(forReceived: property),
			))
		}
		for uncoveredParameter in parameters.flatUncoveredParameters {
			requiredParameters.append(TypeRequirements.RequiredParameter(
				label: uncoveredParameter.label,
				typeSource: uncoveredParameter.typeSource,
				reason: .noInstantiableFulfillsType(uncoveredParameter.instantiatedType),
			))
		}

		return TypeRequirements(
			typeDescription: concreteType,
			declarations: declarations,
			erasures: erasures,
			forwardedParameters: forwardedParameters,
			requiredParameters: requiredParameters,
		)
	}

	/// The file that declares the hand-written mock of `concreteType`, which every map entry for the type carries.
	private func handWrittenMockFilePath(of concreteType: TypeDescription) -> String? {
		typeDescriptionToFulfillingInstantiableMap.values
			.lazy
			.filter { $0.concreteInstantiable == concreteType }
			.compactMap(\.mockDeclarationLocation?.filePath)
			.min()
	}

	/// What every mock root is built from: the scope of each type a mock can build, and what completes a mock
	/// root's tree.
	private struct MockScopes {
		/// The `@Instantiated(erasedToConcreteExistential: true)` properties that erase a concrete type to each
		/// type, in any module, keyed by the property's type and, for a lazily instantiated property, by the
		/// type of its instance.
		let erasureDeclarations: [TypeDescription: Set<ErasureDeclaration>]
		/// The concrete type a mock builds an erased type from: the one concrete type `erasureDeclarations`
		/// erase to it.
		let erasedToConcreteTypeMap: [TypeDescription: TypeDescription]
		let typeDescriptionToScopeMap: [TypeDescription: Scope]
		/// The name of the hand-written mock that can be called with no arguments, by concrete type.
		let forwardedParameterMockDefaults: [TypeDescription: String]
		/// Where each concrete type's hand-written methods named `mock` are declared.
		let handWrittenMockLocationsByConcreteType: [TypeDescription: Set<Dependency.DeclarationLocation?>]
	}

	/// An `@Instantiated(erasedToConcreteExistential: true)` property, with the concrete type it erases.
	private struct ErasureDeclaration: Hashable {
		let concreteType: TypeDescription
		let declaration: TypeRequirements.Erasure.Declaration
	}

	/// Builds the mock scope map and validates it, and collects what every mock root is built with.
	/// - Parameter additionalMocksToGenerate: The names of the types whose mocks are generated because they are listed.
	private func mockScopes(
		additionalMocksToGenerate: Set<String>,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
	) throws -> MockScopes {
		// Build a map of erased wrapper types → concrete fulfilling types.
		// This lets mocks construct types like AnyUserService(DefaultUserService())
		// even when the erased type isn't directly @Instantiable.
		let erasureDeclarations = typeDescriptionToFulfillingInstantiableMap.values
			.reduce(into: [TypeDescription: Set<ErasureDeclaration>]()) { partialResult, instantiable in
				for dependency in instantiable.dependencies {
					if case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential) = dependency.source,
					   erasedToConcreteExistential,
					   let concreteType = fulfillingTypeDescription?.asInstantiatedType
					{
						let erasureDeclaration = ErasureDeclaration(
							concreteType: concreteType,
							declaration: TypeRequirements.Erasure.Declaration(
								declaringType: instantiable.concreteInstantiable,
								property: dependency.property,
								sourceFilePath: instantiable.sourceFilePath,
							),
						)
						partialResult[dependency.property.typeDescription, default: []].insert(erasureDeclaration)
						// A lazily instantiated dependency is also received by value, with the type of its instance.
						if let instanceProperty = dependency.property.asLazilyInstantiatedInstanceProperty {
							partialResult[instanceProperty.typeDescription, default: []].insert(erasureDeclaration)
						}
					}
				}
			}
		// An erased type that declarations erase different concrete types to is left out: nothing
		// says which one a mock should build, so a received property of that type stays a
		// required mock parameter.
		let erasedToConcreteTypeMap = erasureDeclarations.compactMapValues { erasureDeclarations in
			let concreteTypes = Set(erasureDeclarations.map(\.concreteType))
			return concreteTypes.count == 1 ? concreteTypes.first : nil
		}

		// Build mock scope mapping — like production but includes all types and
		// promotes received dependencies as instantiated children.
		let typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping()

		// Validate mock scopes for cycles. Mock-only types (generateMock: true without
		// isRoot) bypass root validation but can still have partially-lazy cycles.
		// Uses cyclesOnly to skip unfulfillable property checks — mock-only types
		// have unfulfillable received properties by design (they become mock parameters).
		// `collectReceivedProperties` gives a scope the same complete result however it is
		// reached, every scope it caches is in `typeDescriptionToScopeMap`, which outlives
		// this method in the result, and only complete results outlive a walk, so the caller's
		// one cache serves this validation and every mock root.
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

		return MockScopes(
			erasureDeclarations: erasureDeclarations,
			erasedToConcreteTypeMap: erasedToConcreteTypeMap,
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			forwardedParameterMockDefaults: forwardedParameterMockDefaults,
			handWrittenMockLocationsByConcreteType: handWrittenMockLocationsByConcreteType,
		)
	}

	/// The instantiable a mock root is built from: the entry of `scope`'s concrete type, declaring only the
	/// dependencies the scope builds.
	private func mockRootInstantiable(for instantiable: Instantiable, scope: Scope) -> Instantiable {
		// Canonicalize: slot-specific merges can produce different entries
		// for the same concreteInstantiable (e.g., the ServiceProtocol key
		// has a protocol-returning mock but the MyService key does not).
		// Always use the concrete-type key entry so mock root generation
		// uses the correct mock info for the concrete type.
		// The mock root declares the dependencies its scope builds, which leaves out those its hand-written
		// mock is not passed (see `createMockTypeDescriptionToScopeMapping`).
		(typeDescriptionToFulfillingInstantiableMap[instantiable.concreteInstantiable] ?? instantiable)
			.keepingDependencies { !scope.dependenciesLeftOut.contains($0) }
	}

	/// Why the project generates `mock()` for a type, which decides the fix a diagnostic about a hand-written
	/// method named `mock` offers.
	private enum GeneratedMockReason {
		/// The type sets `generateMock: true`.
		case generateMock
		/// A `#SafeDIConfiguration` lists the type in `additionalMocksToGenerate`.
		case additionalMocksToGenerate
	}

	/// The mock root of `instantiable`, the instantiable `mockRootInstantiable(for:scope:)` returned for `scope`,
	/// once the type is known to be one a mock can be generated for. Every check that decides whether one mock
	/// root can be generated belongs here, so that `generateMockCode` and `requirements(forTypeNamed:generatesMock:)`
	/// run the same ones; a pass that needs every mock root at once goes after `generateMockCode`'s loop instead.
	/// - Parameter generatedMockReason: Why the project generates `mock()` for the type, or `nil` when it does
	///   not, so that a hand-written method named `mock` is the type's mock rather than a collision.
	private func createMockRoot(
		for instantiable: Instantiable,
		scope: Scope,
		generatedMockReason: GeneratedMockReason?,
		mockScopes: MockScopes,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
		childrenRequiringEachOtherValidation: inout ChildrenRequiringEachOtherValidation,
	) throws -> ScopeGenerator {
		// A hand-written method also named `mock` can be confused with the
		// generated `mock()`: identical signatures redeclare, overlapping ones
		// make calls ambiguous or silently pick the generated method, and a
		// mockOnly extension's mock defaults every parameter, so even a
		// generated `mock(safeDIOverrides:)` leaves `Type.mock()` ambiguous.
		// The macro rejects the pair within one declaration; this extends the
		// rule across declarations and modules.
		// A method named `mock` collides only with a generated `mock()`.
		if let generatedMockReason {
			let handWrittenMockLocations = mockScopes.handWrittenMockLocationsByConcreteType[instantiable.concreteInstantiable, default: []]
			guard handWrittenMockLocations.isEmpty else {
				throw DependencyTreeGeneratorError.handWrittenMockSharesGeneratedMockName(
					instantiable.concreteInstantiable,
					declaredAt: Array(handWrittenMockLocations),
					isGeneratedForAdditionalMocksToGenerate: generatedMockReason == .additionalMocksToGenerate,
				)
			}
		}

		// Validate that this type's constant @Instantiated children have no @Forwarded properties.
		// Use the mock scope map (not typeDescriptionToFulfillingInstantiableMap) because
		// mockOnly types can win additional-type slots and may have different @Forwarded properties.
		// For fulfilledByType deps, validate against the declared type (same as mock resolution).
		for dependency in scope.instantiable.dependencies {
			guard case let .instantiated(fulfillingTypeDescription, _) = dependency.source else { continue }
			let instantiatedType = dependency.asInstantiatedType
			let childScope: Scope? = if fulfillingTypeDescription != nil {
				mockScopes.typeDescriptionToScopeMap[dependency.property.typeDescription.asInstantiatedType]
					?? mockScopes.typeDescriptionToScopeMap[instantiatedType]
			} else {
				mockScopes.typeDescriptionToScopeMap[instantiatedType]
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

		return try createMockRootScopeGenerator(
			for: instantiable,
			scope: scope,
			typeDescriptionToScopeMap: mockScopes.typeDescriptionToScopeMap,
			erasedToConcreteTypeMap: mockScopes.erasedToConcreteTypeMap,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
		)
	}

	/// Rejects a type that generated mocks build both with its hand-written mock and without it, when the two
	/// constructions need different `SafeDIMockConfiguration` structs. Mocks generate one struct per type, so the
	/// construction the struct does not describe would not compile.
	///
	/// A property is built with its type's hand-written mock only when the mock returns a type the property accepts
	/// (see `createMockTypeDescriptionToScopeMapping`), so a mock that returns one of the type's additional types
	/// builds some of its properties and not others. A construction that needs no struct is built from a closure
	/// typed by its property, so it never conflicts.
	///
	/// A node beneath an edge in `cycleEdges` reads no overrides from its struct, so it is not compared (see
	/// `ScopeGenerator.collectConfigurationNodesByConstruction`).
	///
	/// - Parameter mockRoots: The mock roots in concrete type order, so the properties a diagnostic names are
	///   the same on every run.
	/// - Returns: For each type with a hand-written mock, the first node that reads its struct. When the type
	///   is built both ways, the two kinds of node read the same struct, so either describes it.
	private func validateConfigurationsAreBuiltOneWay(
		mockRoots: [(instantiable: Instantiable, scopeGenerator: ScopeGenerator)],
		cycleEdges: Set<ScopeGenerator.CycleEdge>,
	) async throws -> [TypeDescription: ScopeGenerator.MockParameterNode] {
		var mockDeclarationLocations = [TypeDescription: Set<Dependency.DeclarationLocation?>]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values where instantiable.mockInitializer != nil {
			mockDeclarationLocations[instantiable.concreteInstantiable, default: []].insert(instantiable.mockDeclarationLocation)
		}
		guard !mockDeclarationLocations.isEmpty else { return [:] }

		var firstNodes = [ScopeGenerator.ConstructedType: ScopeGenerator.BuiltMockParameterNode]()
		for (instantiable, mockRoot) in mockRoots {
			for builtNode in await mockRoot.collectConfigurationNodesByConstruction(
				of: Set(mockDeclarationLocations.keys),
				mockRoot: instantiable.concreteInstantiable,
				cycleEdges: cycleEdges,
			) {
				let constructedType = ScopeGenerator.ConstructedType(concreteType: builtNode.node.concreteType, usesMockInitializer: builtNode.node.useMockInitializer)
				firstNodes[constructedType] = firstNodes[constructedType] ?? builtNode
			}
		}

		let conflicts = mockDeclarationLocations.keys.compactMap { concreteType -> DependencyTreeGeneratorError.ConfigurationBuiltTwoWays? in
			guard let builtByMock = firstNodes[ScopeGenerator.ConstructedType(concreteType: concreteType, usesMockInitializer: true)],
			      let builtWithoutMock = firstNodes[ScopeGenerator.ConstructedType(concreteType: concreteType, usesMockInitializer: false)],
			      builtByMock.node.configurationRequirements != builtWithoutMock.node.configurationRequirements
			else { return nil }
			return DependencyTreeGeneratorError.ConfigurationBuiltTwoWays(
				concreteType: concreteType,
				mockDeclarationLocations: Array(mockDeclarationLocations[concreteType, default: []]),
				builtByMock: builtByMock,
				builtWithoutMock: builtWithoutMock,
			)
		}
		guard conflicts.isEmpty else {
			throw DependencyTreeGeneratorError.configurationBuiltTwoWays(conflicts)
		}
		// Without a conflict, a type built both ways reads one struct either way; prefer the `init`-built node so the
		// choice does not depend on dictionary order.
		return mockDeclarationLocations.keys.reduce(into: [TypeDescription: ScopeGenerator.MockParameterNode]()) { result, concreteType in
			let builtWithoutMock = firstNodes[ScopeGenerator.ConstructedType(concreteType: concreteType, usesMockInitializer: false)]
			let builtByMock = firstNodes[ScopeGenerator.ConstructedType(concreteType: concreteType, usesMockInitializer: true)]
			result[concreteType] = (builtWithoutMock ?? builtByMock)?.node
		}
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
	/// makes the global type graph acyclic. Walks the graph with a DFS, starting from
	/// each node in alphabetical order; any edge into a node already on the active DFS
	/// stack is recorded as a back-edge. Determinism comes from sorted iteration over
	/// both roots and successors. The DFS keeps its own stack, since a chain of types
	/// can be as long as the module has types.
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

		for startNode in allNodes where !visited.contains(startNode) {
			visited.insert(startNode)
			onStack.insert(startNode)
			// Each node on the DFS stack, with its neighbors and the index of the next one to look at.
			var path = [(node: startNode, neighbors: adjacency[startNode] ?? [], nextNeighborIndex: 0)]
			while let (node, neighbors, neighborIndex) = path.last {
				if neighborIndex < neighbors.count {
					path[path.count - 1].nextNeighborIndex += 1
					let neighbor = neighbors[neighborIndex]
					if onStack.contains(neighbor) {
						edges.insert(ScopeGenerator.CycleEdge(
							parent: node.asSource,
							child: neighbor.asSource,
						))
					} else if visited.insert(neighbor).inserted {
						onStack.insert(neighbor)
						path.append((node: neighbor, neighbors: adjacency[neighbor] ?? [], nextNeighborIndex: 0))
					}
				} else {
					onStack.remove(node)
					path.removeLast()
				}
			}
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
		/// Reported at a `@Received` declaration in the tree of a dependency a mock builds beside the mocked type, which
		/// the mocked type's forwarded property fulfills but another receive of its label hides, with a note at that
		/// receive. See `ForwardedPropertyHiddenInPromotedTree`.
		case forwardedPropertyHiddenInPromotedTree(ForwardedPropertyHiddenInPromotedTree)
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
		/// Reported at each dependency that a `@Sendable` builder function would read from an `Instantiator`,
		/// `ErasedInstantiator`, or `LazilyInstantiated` declared outside it, with a note at that wrapper when a type
		/// in the tree declares it.
		case nonSendableWrapperCapturedBySendableBuilder([ScopeGenerator.NonSendableWrapperCapture])
		/// Reported at the hand-written mock of each type that generated mocks build both with that mock and
		/// without it, in ways one `SafeDIMockConfiguration` struct cannot describe. See `ConfigurationBuiltTwoWays`.
		case configurationBuiltTwoWays([ConfigurationBuiltTwoWays])
		/// Errors that validations independent of one another found – those of different roots, for example – each
		/// reported as it would be alone, in source order. See `reportingAll(of:)`.
		case independentErrors([DependencyTreeGeneratorError])

		/// An error reporting every one of `errors`, or `nil` when there are none. The errors are reported in source
		/// order, so neither which are reported nor their order depends on the order of the validations that found
		/// them, which follows the names of what they validate. Each validation must keep nothing from one that threw
		/// that would let it skip work the one that threw did not finish, or which errors are found would depend on
		/// that order too.
		static func reportingAll(of errors: [DependencyTreeGeneratorError]) -> DependencyTreeGeneratorError? {
			if errors.count > 1 {
				.independentErrors(errors)
			} else {
				errors.first
			}
		}

		var sourceDiagnostics: [SourceDiagnostic] {
			switch self {
			case let .independentErrors(errors):
				SourceDiagnostic.joiningInSourceOrder(errors.map(\.sourceDiagnostics))
			case let .nonSendableWrapperCapturedBySendableBuilder(captures):
				// The captures arrive in set order. Two whose errors read the same name the same wrapper on the same
				// type, so their notes, at that declaration, read the same too, and the diagnostics come out the same.
				captures
					.map(Self.sourceDiagnostics(of:))
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .configurationBuiltTwoWays(configurationsBuiltTwoWays):
				// Sorted by location so the order never depends on map iteration.
				configurationsBuiltTwoWays
					.flatMap(\.sourceDiagnostics)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
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
			case let .forwardedPropertyHiddenInPromotedTree(forwardedPropertyHiddenInPromotedTree):
				forwardedPropertyHiddenInPromotedTree.sourceDiagnostics
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

		/// An `error:` line that names the type declaring the wrapper, since Xcode drops notes from build-tool
		/// output, and a `note:` at that declaration so command-line builds can navigate to it.
		private static func sourceDiagnostics(of capture: ScopeGenerator.NonSendableWrapperCapture) -> [SourceDiagnostic] {
			let wrapperProperty = capture.wrapperProperty
			let label = wrapperProperty.label
			let wrapperType = wrapperProperty.typeDescription.unwrapped
			// Each wrapper's `Sendable` twin is spelled with `Sendable` before its name.
			let sendableWrapperType = "Sendable\(wrapperType.asSource)"
			// A lazily instantiated property can also be received as its instance; the others only as themselves.
			let receivesWrapper = !capture.receivedProperty.propertyType.isConstant
			let capturedProperty: String
			let fix: String
			if let declaringType = capture.wrapperDeclaringType {
				capturedProperty = "`\(wrapperProperty.asSource)` on `\(declaringType.asSource)`"
				fix = receivesWrapper
					? "Declare `\(label)` on `\(declaringType.asSource)`, and this property, as `\(sendableWrapperType)` to fix."
					: "Declare `\(label)` on `\(declaringType.asSource)` as `\(sendableWrapperType)` to fix."
			} else {
				capturedProperty = "`\(wrapperProperty.asSource)`, which the tree of `\(capture.chain[0].asSource)` receives from outside it"
				fix = "Declare `\(label)` as `\(sendableWrapperType)` where it is declared and where it is received as `\(wrapperType.asSource)` to fix."
			}
			let requirement = if wrapperProperty.propertyType.isLazilyInstantiated {
				// The constant a lazily instantiated property stands for has the type of its instance.
				"A `\(Dependency.sendableLazilyInstantiatedType)` requires its instance type, `\(wrapperProperty.asUnwrappedProperty.asValidatedForDependencyCycles.typeDescription.asSource)`, to be `Sendable`."
			} else {
				"`\(sendableWrapperType)` builds `\(wrapperType.asInstantiatedType.asSource)` in a `@Sendable` function, so what the tree of `\(wrapperType.asInstantiatedType.asSource)` receives from outside that function must be `Sendable` too."
			}
			// A builder that is not a `Sendable` wrapper is built in a `@Sendable` function because a cycle builds it
			// again inside one.
			let sendableBuilderReason = if capture.sendableBuilder.propertyType.isSendable {
				""
			} else {
				" (a `@Sendable` builder function in the tree of `\(capture.sendableBuilder.typeDescription.asInstantiatedType.asSource)` builds it again)"
			}
			let error = SourceDiagnostic(
				severity: .error,
				location: capture.declarationLocation,
				message: "@\(Dependency.Source.receivedRawValue) property `\(capture.receivedProperty.asSource)` cannot be received inside a `@Sendable` function in chain: \(capture.chain.map(\.asSource).joined(separator: " -> ")). "
					+ "SafeDI builds `\(capture.sendableBuilder.asSource)` on `\(capture.sendableBuilderDeclaringType.asSource)` in a `@Sendable` function\(sendableBuilderReason), which cannot capture \(capturedProperty), because `\(wrapperType.asSource)` is not `Sendable`. "
					+ "\(fix) \(requirement)",
			)
			return if capture.wrapperDeclaringType != nil {
				[
					error,
					SourceDiagnostic(
						severity: .note,
						location: capture.wrapperDeclarationLocation,
						message: "`\(wrapperProperty.asSource)` is declared here",
					),
				]
			} else {
				[error]
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

		/// A type that generated mocks build with its hand-written mock for one property and without it for another,
		/// where the two constructions read different `SafeDIMockConfiguration` structs.
		struct ConfigurationBuiltTwoWays {
			let concreteType: TypeDescription
			/// Where the hand-written mock is declared. Several map entries can carry the same mock.
			let mockDeclarationLocations: [Dependency.DeclarationLocation?]
			/// The first node, in mock root order, that the hand-written mock builds.
			let builtByMock: ScopeGenerator.BuiltMockParameterNode
			/// The first node, in mock root order, built without the hand-written mock.
			let builtWithoutMock: ScopeGenerator.BuiltMockParameterNode

			var sourceDiagnostics: [SourceDiagnostic] {
				let typeName = "`\(concreteType.asSource)`"
				let mockName = "`\(builtByMock.node.customMockName ?? InstantiableVisitor.mockMethodName)`"
				// Built without its mock, a type declared by an extension calls its `instantiate(…)` method, whose
				// default-valued parameters are fields of the struct, as an initializer's are.
				let construction = if builtWithoutMock.node.isExtensionBased {
					"`\(InstantiableVisitor.instantiateMethodName)(…)` method"
				} else {
					"initializer"
				}
				let message = "Generated mocks build \(typeName) with its hand-written \(mockName) method for \(Self.describe(builtByMock)),"
					+ " and with its \(construction) for \(Self.describe(builtWithoutMock))."
					+ " The two take different parameters, but both properties are configured with one `\(concreteType.asSource).\(ScopeGenerator.MockParameterNode.configurationStructName)`."
					+ " Make \(mockName) return \(typeName), so that it builds both properties, or give \(mockName) exactly the parameters of \(typeName)’s \(construction), in the same order."
				return mockDeclarationLocations.map {
					SourceDiagnostic(severity: .error, location: $0, message: message)
				}
			}

			/// The property a node builds, the type that declares it, and the generated mock that builds it.
			private static func describe(_ builtNode: ScopeGenerator.BuiltMockParameterNode) -> String {
				"`\(builtNode.node.property.asSource)` on `\(builtNode.parent.asSource)` in `\(builtNode.mockRoot.asSource).\(InstantiableVisitor.mockMethodName)()`"
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
			/// The property of an enclosing type that a receiver of `property` is handed where the alias is not
			/// created, when there is one: the alias is then never required to be created, and the receiver
			/// requires that property instead (see `OnlyIfAvailableAliasRequirement`).
			var providedProperty: Property?

			/// The sentences that end the error for a cycle the receive closes, in place of the general remedy, and say
			/// how to break it: received only if available, the alias is `nil` where its fulfilling property is not
			/// built first, as the manual describes, unless an enclosing type's property stands in for it.
			var hint: String {
				if let providedProperty {
					"`\(property.asSource)` renames `\(fulfillingProperty.asSource)` only if available, and an enclosing type declares `\(providedProperty.asSource)`, so a type that receives `\(property.label)` without `onlyIfAvailable` is handed `\(providedProperty.asSource)` where `\(fulfillingProperty.asSource)` cannot be built first and must be built after it. Receive `\(property.label)` with `@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)` to be passed `nil` where neither can be built first."
				} else {
					"`\(property.asSource)` renames `\(fulfillingProperty.asSource)` only if available, so a type that receives `\(property.label)` without `onlyIfAvailable` must be built after `\(fulfillingProperty.asSource)`. Receive `\(property.label)` with `@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)` to be passed `nil` where `\(fulfillingProperty.asSource)` cannot be built first."
				}
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
					hint = if property.propertyType.isErasedInstantiator {
						// The `@Instantiated` macro requires an erased instantiator to name the type it builds.
						"Declare `@\(Dependency.Source.instantiatedRawValue)(fulfilledByType:) let \(property.asSource)`, naming the type it builds, on `\(root.asSource)` or on another type in the chain to fix."
					} else {
						"Declare `@\(Dependency.Source.instantiatedRawValue) let \(property.asSource)` on `\(root.asSource)` or on another type in the chain to fix."
					}
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

		/// A receive of a property the mocked type forwards, in the tree of a dependency the mock builds beside the
		/// mocked type, that a closer receive of the property's label in another form hides. The mock binds that form
		/// under a name of its own, since the forwarded parameter keeps the label, and passes it to its receiver under
		/// the label, inside the function that also builds the types beneath the receiver.
		struct ForwardedPropertyHiddenInPromotedTree {
			/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			let mockedType: TypeDescription
			let forwardedProperty: Property
			/// The other form of the label, which a type above the receiver receives.
			let hidingProperty: Property
			let hidingDeclarationLocation: Dependency.DeclarationLocation?
			/// The types from the one that receives `hidingProperty` to the one that receives `property`.
			let chain: [TypeDescription]

			/// An `error:` line that names the hiding receive, as `HiddenReceivedProperty`'s does, and a `note:` at it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let hidingProperty = hidingProperty.asSource
				let hidingType = chain[0].asSource
				let forwardedProperty = forwardedProperty.asSource
				let mockedType = mockedType.asSource
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue) property `\(property.asSource)` is hidden in chain: \(chain.map(\.asSource).joined(separator: " -> ")). In the mock of `\(mockedType)`, `\(chain[chain.count - 1].asSource)` is passed the `\(forwardedProperty)` that `\(mockedType)` forwards, but `\(hidingType)` receives `\(hidingProperty)` with the same label, so the types below `\(hidingType)` receive `\(hidingProperty)` instead. Give `\(forwardedProperty)` on `\(mockedType)` a different label to fix.",
					),
					SourceDiagnostic(
						severity: .note,
						location: hidingDeclarationLocation,
						message: "`\(hidingProperty)` is received here",
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
		let instantiable: Instantiable
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
					inTreesRootedAt: rootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] }.map { ($0, [], []) },
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
								instantiable: scope.instantiable,
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
		var visitedScopes = Set<ObjectIdentifier>()
		var worklist = Array(allRequired)

		func concreteTypeErased(to property: Property) -> TypeDescription? {
			Self.concreteTypeErased(to: property, in: erasedToConcreteTypeMap)
		}

		// A forwarded property is a bare mock parameter: the mock is passed it, so it neither promotes it nor walks the
		// tree of its type. `collectReceivedProperties` subtracts the mock root's forwarded properties only from the trees
		// of the mock root's own children, so the tree of a promoted scope can still receive one; the worklist and the
		// promotion below skip it instead. A forwarded lazily instantiated property also provides the by-value property
		// that reads its instance.
		let forwardedProperties = instantiable.forwardedReceivableProperties
		func isForwarded(_ property: Property) -> Bool {
			// A forwarded `x: X` fulfills an `x: X?` too.
			forwardedProperties.contains(property) || forwardedProperties.contains(property.asUnwrappedProperty)
		}

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

		// The scope the mock builds for each required property, which `inOrderTheMockTreeFirstReceives` walks too.
		var scopesBuiltForRequiredProperties = [Property: Scope]()
		while let property = worklist.popLast() {
			guard !isForwarded(property), let promotedScope = scopeToPromote(for: property)?.scope else { continue }
			scopesBuiltForRequiredProperties[property] = promotedScope
			guard visitedScopes.insert(ObjectIdentifier(promotedScope)).inserted else { continue }

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
		// mock parameters with no default. Nor are forwarded properties.
		let mockRootScope = Scope(instantiable: instantiable)
		// A property the tree creates is the instance of a `LazilyInstantiated` of its label that the tree receives, as in
		// production: the mocked type's own `x: X` and an `x: LazilyInstantiated<X>` its tree receives are one instance. The
		// mock builds that child as the `LazilyInstantiated`, whose instance it passes the mocked type. A forwarded `x: X`
		// comes from outside the tree, so it is never the instance of one.
		let lazilyInstantiatedPropertiesReceived = allReceived.lazy
			.map(\.asUnwrappedProperty)
			.filter { $0.typeDescription.lazilyInstantiatedInstanceType != nil }
		mockRootScope.propertiesToGenerate = scope.propertiesToGenerate.map { propertyToGenerate in
			guard case let .instantiated(property, childScope, erasedToConcreteExistential) = propertyToGenerate,
			      let lazilyInstantiatedProperty = lazilyInstantiatedPropertiesReceived
			      .filter({ $0.asLazilyInstantiatedInstanceProperty == property })
			      .min(by: { $0.precedesInMockOrder($1) })
			else { return propertyToGenerate }
			return .instantiated(lazilyInstantiatedProperty, childScope, erasedToConcreteExistential: erasedToConcreteExistential)
		}

		// A dependency the tree receives both as `LazilyInstantiated` and by value is one dependency. It is
		// promoted once, as the lazily instantiated property, whenever any receiver requires it in either form;
		// receivers of its instance read it from that property. The same holds for a lazily instantiated
		// property the mock root declares itself, which needs no promotion. A receive of the instance that a
		// forwarded property fulfills does not count: the forwarded value comes from outside the tree.
		var lazilyInstantiatedPropertiesToPromote = Set<Property>()
		var instancePropertiesOfLazilyInstantiatedProperties = Set(mockRootScope.propertiesToGenerate.compactMap(\.lazilyInstantiatedInstanceProperty))
		for receivedProperty in allReceived {
			guard let instanceProperty = receivedProperty.asLazilyInstantiatedInstanceProperty else { continue }
			let lazilyInstantiatedProperty = receivedProperty.asUnwrappedProperty
			guard allRequired.contains(lazilyInstantiatedProperty) || (allRequired.contains(instanceProperty) && !isForwarded(instanceProperty)),
			      scopeToPromote(for: lazilyInstantiatedProperty) != nil
			else { continue }
			lazilyInstantiatedPropertiesToPromote.insert(lazilyInstantiatedProperty)
			instancePropertiesOfLazilyInstantiatedProperties.insert(instanceProperty)
		}

		// Each form of a dependency the tree receives under one label is promoted on its own: `x: X`,
		// `x: Instantiator<X>` and `x: ErasedInstantiator<(), AnyX>` are each built, under a name of its own, for
		// the receivers of that form. Only an optional form is not promoted beside its non-optional form: the
		// mock binds what it builds to a non-optional value, which a receive of the optional form is handed too.
		let propertiesToPromote = allReceived.union(lazilyInstantiatedPropertiesToPromote).filter { receivedProperty in
			(lazilyInstantiatedPropertiesToPromote.contains(receivedProperty) || !allOnlyIfAvailable.contains(receivedProperty))
				&& !isForwarded(receivedProperty)
				&& !instancePropertiesOfLazilyInstantiatedProperties.contains(receivedProperty)
		}
		var promotedPropertiesToGenerate = [Scope.PropertyToGenerate]()
		for receivedProperty in propertiesToPromote.sorted()
			where receivedProperty.asUnwrappedProperty == receivedProperty || !propertiesToPromote.contains(receivedProperty.asUnwrappedProperty)
		{
			guard let (receivedScope, erasedToConcreteExistential) = scopeToPromote(for: receivedProperty) else {
				continue
			}
			promotedPropertiesToGenerate.append(.instantiated(
				receivedProperty,
				receivedScope,
				erasedToConcreteExistential: erasedToConcreteExistential,
			))
		}
		// The mock declares and validates the promoted children in the order its tree first receives them, after its
		// own children, so which promoted sibling is passed `nil` when two receive each other only if available, the
		// order of their overrides, and which error the mock root reports depend on where properties are declared,
		// never on their labels or type names.
		mockRootScope.propertiesToGenerate += Self.inOrderTheMockTreeFirstReceives(
			promotedPropertiesToGenerate,
			walkingFrom: scope,
			scopesBuiltForRequiredProperties: scopesBuiltForRequiredProperties,
		)

		// Validate the promoted mock scope for cycles before generating code.
		// This catches cycles that only become visible after @Received dependencies
		// are promoted to the mock root (e.g., B @Receives Instantiator<A> where A
		// instantiates B — the promotion creates a cycle in the mock root scope).
		let declaresOnlyIfAvailableAliasOfPropertyBeingBuilt = try validateMockRootScopeForCycles(mockRootScope)
		// Promotion can also make the mock root's children require one another
		// (e.g., C @Receives B while B's subtree @Receives C — each must be built
		// first), which no ancestor stack shows. Detecting that is cheap; production's
		// walk, which follows received dependencies between scopes, then reports the
		// cycle. Running that walk on every mock root instead would add a
		// received-dependency walk for every node of every mock tree. The walk also
		// reports a required receive of an `onlyIfAvailable` alias that is not created
		// because its fulfilling property is still being built, so it runs when the
		// walk above found such an alias too.
		// The mock root binds every received property it does not promote, which encloses its whole tree.
		let mockRootEnclosingProvidedProperties = childrenRequiringEachOtherValidation.enclosingProvidedProperties(
			ofMockRoot: mockRootScope,
			receivedProperties: allReceived,
		)
		// The properties the mock is passed, which are in scope throughout its tree: those its tree receives that it
		// neither builds – as a promoted property or one of its own, in some order – nor fulfills with the non-optional
		// form of one it builds, nor reads from a lazily instantiated property it builds.
		let mockRootBuiltProperties = Set(mockRootScope.propertiesToGenerate.map(\.property))
		let mockParameters = allReceived.filter { receivedProperty in
			!mockRootBuiltProperties.contains(receivedProperty)
				&& !mockRootBuiltProperties.contains(receivedProperty.asUnwrappedProperty)
				&& !instancePropertiesOfLazilyInstantiatedProperties.contains(receivedProperty)
		}
		let mockRootEnclosingForwardedProperties = childrenRequiringEachOtherValidation.enclosingForwardedProperties(ofMockRootPassed: mockParameters)
		let mockRootChildrenRequiringEachOther = Self.childrenRequiringEachOther(
			in: mockRootScope,
			enclosingProvidedProperties: mockRootEnclosingProvidedProperties,
			enclosingForwardedProperties: mockRootEnclosingForwardedProperties,
			cache: &cache,
		)
		try validatePropertiesAreFulfillable(
			onRootScopes: mockRootChildrenRequiringEachOther != nil || declaresOnlyIfAvailableAliasOfPropertyBeingBuilt
				? [ValidatedRootScope(scope: mockRootScope, boundProperties: allReceived)]
				: [],
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
			var mockRootChildScopes = [(scope: Scope, enclosingProvidedProperties: Set<Property>, enclosingForwardedProperties: Set<Property>)]()
			let mockRootChildEnclosingForwardedProperties = childrenRequiringEachOtherValidation.enclosingForwardedProperties(
				of: mockRootScope,
				enclosingForwardedProperties: mockRootEnclosingForwardedProperties,
			)
			for case let .instantiated(childProperty, childScope, _) in mockRootScope.propertiesToGenerate {
				mockRootChildScopes.append((
					childScope,
					childrenRequiringEachOtherValidation.enclosingProvidedProperties(
						ofChild: childProperty,
						of: mockRootScope,
						enclosingProvidedProperties: mockRootEnclosingProvidedProperties,
					),
					mockRootChildEnclosingForwardedProperties,
				))
			}
			try Self.validateChildrenDoNotRequireEachOther(
				inTreesRootedAt: mockRootChildScopes,
				cache: &cache,
				validation: &childrenRequiringEachOtherValidation,
			)
		}

		// A forwarded parameter keeps its label, so the mock binds every other property of that label under a name of its
		// own, and a type that receives one is passed it under the label inside the function that builds it. A type built
		// in that function that receives the forwarded property would read that binding instead. Only a promoted
		// dependency's tree can hold such a pair, and only when some type in it receives a forwarded label in another
		// form, which is rare, so the trees are walked only then. A `LazilyInstantiated` the mock does not build is passed
		// by name, never under its label.
		let promotedProperties = Set(promotedPropertiesToGenerate.map(\.property))
		func isReceivedUnderItsLabel(_ property: Property) -> Bool {
			property.typeDescription.lazilyInstantiatedInstanceType == nil || promotedProperties.contains(property.asUnwrappedProperty)
		}
		let forwardedDependencies = instantiable.dependencies.filter { dependency in
			dependency.isForwarded && allReceived.contains { receivedProperty in
				receivedProperty.label == dependency.property.label && !isForwarded(receivedProperty) && isReceivedUnderItsLabel(receivedProperty)
			}
		}
		if let forwardedPropertyHiddenInPromotedTree = Self.forwardedPropertyHiddenInPromotedTree(
			forwardedDependencies: forwardedDependencies,
			of: instantiable,
			promotedChildren: mockRootScope.propertiesToGenerate[scope.propertiesToGenerate.count...],
			isReceivedUnderItsLabel: isReceivedUnderItsLabel,
		) {
			throw DependencyTreeGeneratorError.forwardedPropertyHiddenInPromotedTree(forwardedPropertyHiddenInPromotedTree)
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
			alwaysAvailableProperties: mockParameters,
			erasedToConcreteExistential: false,
			forMockGeneration: true,
		)
	}

	/// The concrete type a mock builds `property` from when no `@Instantiable` fulfills its type, or `nil` when
	/// `erasedToConcreteTypeMap` names none. A lazily instantiated property is built from the type its instance
	/// is erased from, whichever form declares the erasure and whether or not the property is optional.
	private static func concreteTypeErased(to property: Property, in erasedToConcreteTypeMap: [TypeDescription: TypeDescription]) -> TypeDescription? {
		erasedToConcreteTypeMap[property.typeDescription]
			?? property.asLazilyInstantiatedInstanceProperty.flatMap { erasedToConcreteTypeMap[$0.typeDescription] }
	}

	/// Whether a mock can build the received `property` from `scope` when it promotes the property to a
	/// child of the mock root. A type with `@Forwarded` properties can be built only by an `Instantiator`
	/// that is handed the forwarded values, so a mock cannot build a constant of that type, or lazily
	/// instantiate one: as in production, where such a property is never `@Instantiated`, it must be received.
	/// Nor can it build an erased instantiator whose first generic argument is not the type's `@Forwarded`
	/// properties. Such a received property stays a `mock()` parameter; an `@Instantiated` declaration of the
	/// mismatched type is reported where a tree builds that declaration.
	private static func mockCanBuild(_ property: Property, from scope: Scope) -> Bool {
		guard property.firstGenericMatchesForwardedProperties(of: scope.instantiable) else { return false }
		return !(property.propertyType.isConstant || property.propertyType.isLazilyInstantiated)
			|| !scope.instantiable.dependencies.contains(where: \.isForwarded)
	}

	/// A scope that `forwardedPropertyHiddenInPromotedTree` has yet to walk.
	private struct ScopeToWalkForHiddenForwardedProperty {
		let scope: Scope
		/// The receive of the forwarded label in another form that hides the forwarded property in `scope`, with the
		/// types from the one that declares it to `scope`, or `nil` when none does.
		let hidingReceive: (dependency: Dependency, chain: [TypeDescription])?
	}

	/// The first receive, walking the trees of a mock root's promoted children depth first in declaration order, of a
	/// property in `forwardedDependencies` beneath a type that receives its label in another form. The mock binds that
	/// form under a name of its own and passes it to the type under the label, inside the function that builds the type
	/// and the types it builds, where the label then names that form rather than the forwarded parameter. `nil` when
	/// there is none. Production rejects the same pair of receives under any root, since the closer of the two
	/// declarations they need hides the other.
	/// - Parameters:
	///   - forwardedDependencies: The mocked type's `@Forwarded` dependencies to look for.
	///   - instantiable: The mocked type.
	///   - promotedChildren: The mock root's promoted children, in the order the mock declares them.
	///   - isReceivedUnderItsLabel: Whether the mock passes a receive of a property under its label, rather than by name.
	private static func forwardedPropertyHiddenInPromotedTree(
		forwardedDependencies: [Dependency],
		of instantiable: Instantiable,
		promotedChildren: ArraySlice<Scope.PropertyToGenerate>,
		isReceivedUnderItsLabel: (Property) -> Bool,
	) -> DependencyTreeGeneratorError.ForwardedPropertyHiddenInPromotedTree? {
		let forwardedProperties = instantiable.forwardedReceivableProperties
		/// The property a dependency receives from the scopes above it: the fulfilling property of an alias, the declared
		/// property of a receive, and `nil` for a property the type declares.
		func receivedProperty(of dependency: Dependency) -> Property? {
			switch dependency.source {
			case .received:
				dependency.property
			case let .aliased(fulfillingProperty, _, _):
				fulfillingProperty
			case .instantiated, .forwarded:
				nil
			}
		}
		for forwardedDependency in forwardedDependencies {
			let label = forwardedDependency.property.label
			/// Whether a receive of `property` is passed the forwarded property: its label's, of its type or of the
			/// optional form of its type, or the instance of a forwarded lazily instantiated property.
			func isForwardedProperty(_ property: Property) -> Bool {
				property.label == label && (forwardedProperties.contains(property) || forwardedProperties.contains(property.asUnwrappedProperty))
			}
			// Each scope is walked once beneath a hiding receive and once beneath none, which also ends a walk around a
			// cycle of `Instantiator`s.
			var walkedScopes = Set<ScopeVisit>()
			var promotedScopesToWalk = [ScopeToWalkForHiddenForwardedProperty]()
			for case let .instantiated(_, promotedScope, _) in promotedChildren
				where walkedScopes.insert(ScopeVisit(scope: ObjectIdentifier(promotedScope), isBeneathHidingReceive: false)).inserted
			{
				promotedScopesToWalk.append(ScopeToWalkForHiddenForwardedProperty(scope: promotedScope, hidingReceive: nil))
			}
			// The scope walked next is the last one on the stack, so the first goes last.
			var scopesToWalk = Array(promotedScopesToWalk.reversed())
			while let scopeToWalk = scopesToWalk.popLast() {
				let scope = scopeToWalk.scope
				if let hidingReceive = scopeToWalk.hidingReceive,
				   let hiddenReceive = scope.instantiable.dependencies.lazy
				   .compactMap({ dependency in receivedProperty(of: dependency).map { (dependency: dependency, property: $0) } })
				   .first(where: { isForwardedProperty($0.property) })
				{
					return .init(
						property: hiddenReceive.property,
						declarationLocation: hiddenReceive.dependency.declarationLocation,
						mockedType: instantiable.concreteInstantiable,
						forwardedProperty: forwardedDependency.property,
						hidingProperty: hidingReceive.dependency.property,
						hidingDeclarationLocation: hidingReceive.dependency.declarationLocation,
						chain: hidingReceive.chain,
					)
				} else {
					// The closest receive of the label in another form is what the types this scope builds read under it.
					let hidingReceive = scope.instantiable.dependencies
						.first { dependency in
							dependency.source.isReceived
								&& dependency.property.label == label
								&& !isForwardedProperty(dependency.property)
								&& isReceivedUnderItsLabel(dependency.property)
						}
						.map { (dependency: $0, chain: [scope.instantiable.concreteInstantiable]) }
						?? scopeToWalk.hidingReceive
					// A type that declares the label itself is what the types it builds receive under it, as in production.
					let declaresLabel = scope.instantiable.dependencies.contains { !$0.source.isReceived && $0.property.label == label }
					let firstChildIndex = scopesToWalk.endIndex
					for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate
						where !declaresLabel
						&& walkedScopes.insert(ScopeVisit(scope: ObjectIdentifier(childScope), isBeneathHidingReceive: hidingReceive != nil)).inserted
					{
						scopesToWalk.append(ScopeToWalkForHiddenForwardedProperty(
							scope: childScope,
							hidingReceive: hidingReceive.map { ($0.dependency, $0.chain + [childScope.instantiable.concreteInstantiable]) },
						))
					}
					// The scope walked next is the last one on the stack, so the first child goes last.
					scopesToWalk[firstChildIndex...].reverse()
				}
			}
		}
		return nil
	}

	/// A visit of a scope by `forwardedPropertyHiddenInPromotedTree`.
	private struct ScopeVisit: Hashable {
		let scope: ObjectIdentifier
		let isBeneathHidingReceive: Bool
	}

	/// A scope that `validateMockRootScopeForCycles` has yet to walk.
	private struct ScopeToWalkForCycles {
		let scope: Scope
		/// The properties of the scopes `scope` is built inside, innermost first, as cycle validation sees them.
		let propertyStack: [Property]
		/// The lazily instantiated properties on `propertyStack`, keyed by the constant each is validated as.
		let lazilyInstantiatedDeclarations: [Property: Property]
	}

	/// The children a mock root promotes, in the order its tree first receives them: the order in which a walk first
	/// meets a receive of each. The walk visits the mock root's own dependencies in declaration order, then the tree of
	/// each child it instantiates, depth first, each type's dependencies before its children's trees, all in
	/// declaration order. It then walks, in the order it first met them, the trees of the dependencies the mock builds
	/// for what its receivers require, which are where the mock tree receives the rest. A receive of a promoted child is
	/// one of its property, of the property's optional form, or of the instance of a lazily instantiated property.
	///
	/// The order depends only on where properties are declared and how they are nested, never on their labels or type
	/// names: when two promoted children receive each other only if available, the one received first is built second,
	/// as the property declared first is in production.
	/// - Parameters:
	///   - promotedChildren: The children the mock root promotes. The walk meets a receive of each, since each is a
	///     dependency that the mock root's tree, or the tree of a dependency the mock builds for a receiver, receives.
	///   - mockRootScope: The scope of the mocked type, without the promoted children.
	///   - scopesBuiltForRequiredProperties: The scope from which the mock builds each received property that a
	///     receiver requires, when it builds one: the scopes whose trees the promotion worklist walks.
	private static func inOrderTheMockTreeFirstReceives(
		_ promotedChildren: [Scope.PropertyToGenerate],
		walkingFrom mockRootScope: Scope,
		scopesBuiltForRequiredProperties: [Property: Scope],
	) -> [Scope.PropertyToGenerate] {
		var promotedChildIndexByReceivedProperty = [Property: Int]()
		for (index, promotedChild) in promotedChildren.enumerated() {
			for receivableProperty in promotedChild.receivableProperties {
				promotedChildIndexByReceivedProperty[receivableProperty.asUnwrappedProperty] = index
			}
		}
		var orderedIndices = [Int]()
		var orderedIndexSet = Set<Int>()
		var walkedScopes = Set<ObjectIdentifier>()
		// Every receive the walk meets, in order. The trees of the dependencies the mock builds for them are walked in
		// that order once the trees met before are walked, and only while a promoted child is left to order.
		var receivedProperties = [Property]()
		/// Walks the tree of `rootScope` depth first, each scope's dependencies before its children's trees, with a
		/// stack of the scopes left to walk, since a tree can be as deep as the module has types.
		func walk(_ rootScope: Scope) {
			var scopesToWalk = [rootScope]
			while let scope = scopesToWalk.popLast() {
				// Once every promoted child is ordered, nothing further can change the order.
				guard orderedIndices.count < promotedChildren.count else { return }
				guard walkedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
				for dependency in scope.instantiable.dependencies {
					let receivedProperty: Property? = switch dependency.source {
					case .received:
						dependency.property
					case let .aliased(fulfillingProperty, _, _):
						fulfillingProperty
					case .instantiated, .forwarded:
						nil
					}
					if let receivedProperty {
						receivedProperties.append(receivedProperty)
						if let index = promotedChildIndexByReceivedProperty[receivedProperty.asUnwrappedProperty],
						   orderedIndexSet.insert(index).inserted
						{
							orderedIndices.append(index)
						}
					}
				}
				let firstChildIndex = scopesToWalk.endIndex
				for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
					scopesToWalk.append(childScope)
				}
				// The scope walked next is the last one on the stack, so the first child goes last.
				scopesToWalk[firstChildIndex...].reverse()
			}
		}
		walk(mockRootScope)
		var receivedPropertyIndex = 0
		while orderedIndices.count < promotedChildren.count, receivedPropertyIndex < receivedProperties.count {
			if let builtScope = scopesBuiltForRequiredProperties[receivedProperties[receivedPropertyIndex]] {
				walk(builtScope)
			}
			receivedPropertyIndex += 1
		}
		return orderedIndices.map { promotedChildren[$0] }
	}

	/// Walks a post-promotion mock root scope for dependency cycles.
	/// The mock root scope has @Received dependencies promoted as children,
	/// which can create cycles not visible in the pre-promotion scope.
	/// The walk goes depth first, in the order each scope declares its children, and keeps its own stack of
	/// the scopes left to walk, since a tree can be as deep as the module has types.
	/// - Returns: Whether a scope in the tree declares an `onlyIfAvailable` alias whose fulfilling property is still
	///   being built there, so that the alias is not created.
	private func validateMockRootScopeForCycles(_ mockRootScope: Scope) throws -> Bool {
		var declaresOnlyIfAvailableAliasOfPropertyBeingBuilt = false
		var scopesToWalk = [ScopeToWalkForCycles(scope: mockRootScope, propertyStack: [], lazilyInstantiatedDeclarations: [:])]
		while let scopeToWalk = scopesToWalk.popLast() {
			let scope = scopeToWalk.scope
			let propertyStack = scopeToWalk.propertyStack
			// Check dependencies for cycles (catches @Received references back to ancestors).
			for dependency in scope.instantiable.dependencies where !dependency.isForwarded {
				let declaredPropertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
				let propertyForDependency = declaredPropertyForDependency.asValidatedForDependencyCycles
				// A mock promotes a received optional property as the non-optional value it builds, so a receive of the
				// non-optional form inside the tree it builds reaches it too.
				let receivedForms: [Property] = if dependency.isInstantiated {
					[propertyForDependency]
				} else {
					[propertyForDependency, Property(label: propertyForDependency.label, typeDescription: .optional(propertyForDependency.typeDescription))]
				}
				guard let cycleIndex = propertyStack.firstIndex(where: receivedForms.contains) else {
					continue
				}
				guard dependency.canCloseDependencyCycle else {
					// An `onlyIfAvailable` dependency is passed `nil` instead (`Dependency.canCloseDependencyCycle`). An
					// alias passed `nil` is not created; a required receive of it is reported by the walk that follows.
					if case .aliased(_, _, onlyIfAvailable: true) = dependency.source {
						declaresOnlyIfAvailableAliasOfPropertyBeingBuilt = true
					}
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
						lazilyInstantiatedDeclarations: scopeToWalk.lazilyInstantiatedDeclarations,
					),
				)
			}

			// Walk the children next.
			let firstChildIndex = scopesToWalk.endIndex
			for childPropertyToGenerate in scope.propertiesToGenerate {
				switch childPropertyToGenerate {
				case let .instantiated(declaredChildProperty, childScope, _):
					let childProperty = declaredChildProperty.asValidatedForDependencyCycles
					guard !propertyStack.contains(childProperty) else { continue }
					scopesToWalk.append(ScopeToWalkForCycles(
						scope: childScope,
						propertyStack: [childProperty] + propertyStack,
						lazilyInstantiatedDeclarations: scopeToWalk.lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
					))
				case .aliased:
					break
				}
			}
			// The scope walked next is the last one on the stack, so the first child goes last.
			scopesToWalk[firstChildIndex...].reverse()
		}
		return declaresOnlyIfAvailableAliasOfPropertyBeingBuilt
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
		/// The receiver in the last child's tree through which that tree requires the first child, found by
		/// `requiredReceiver` for the last property in `receivedPropertyChain`.
		let closingReceiver: RequiredReceiver?
		/// The `onlyIfAvailable` aliases the scope declares that `receivedPropertyChain` holds, in chain order.
		let requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]

		/// The error reporting these children, at `closingReceiver`. When the last child's tree receives the
		/// first child through an alias or unwrapped, the chain ends with the first child's own property, so
		/// it reads back to where it started. The `onlyIfAvailable` aliases in the last child's tree through
		/// which the closing receive requires the first child follow the scope's own, in chain order.
		var error: DependencyTreeGeneratorError {
			DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
				instantiated: instantiated,
				receivedPropertyChain: receivedPropertyChain + (receivedPropertyChain[receivedPropertyChain.count - 1] == instantiated ? [] : [instantiated]),
				declarationLocation: closingReceiver?.dependency.declarationLocation,
				// The chain names every property as it is declared, so there is nothing to explain.
				lazilyInstantiatedProperties: [],
				requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases + (closingReceiver?.requiredOnlyIfAvailableAliases ?? []),
			)
		}
	}

	/// A dependency through which a tree requires a property from outside the tree, found by `requiredReceiver`.
	private struct RequiredReceiver {
		let dependency: Dependency
		/// The `onlyIfAvailable` aliases the tree declares through which `dependency` requires the property, outermost
		/// first: each renames the property that the next, or `dependency`, requires. Empty when `dependency` receives
		/// the property itself.
		let requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
	}

	/// What a receiver in a tree requires through the `onlyIfAvailable` aliases declared in it, as
	/// `ScopeGenerator.orderedPropertiesToGenerate` orders the tree after it. The receiver receives the first alias's
	/// property, and each alias is fulfilled by the next's property; a required alias of an alias is always created, so
	/// it adds nothing. An `onlyIfAvailable` alias is created only where no enclosing scope provides its property, or
	/// its unwrapped form: there the receiver is handed the enclosing scope's property instead
	/// (`isProvidedByEnclosingScope` in `Scope.createScopeGenerator`), so it requires that property, and nothing of the
	/// aliases beyond it. Where every alias is created, the receiver requires the last alias's fulfilling property,
	/// unless a scope in the tree provides it (`requiresFulfillingProperty`): the alias is then created from that scope's
	/// property, and the receiver requires nothing of the scopes above, other than the property of a nearer alias one of
	/// them provides. An alias whose fulfilling property its own scope provides, or a scope in the tree forwards, is
	/// always created, so it is left out, as `ScopeGenerator` never orders the tree after an enclosing scope's property
	/// for it.
	private struct OnlyIfAvailableAliasRequirement: Hashable {
		/// The aliases, nearest the receiver first.
		let aliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
		/// Whether the receiver requires the last alias's fulfilling property where every alias is created.
		let requiresFulfillingProperty: Bool

		/// The index in `aliases` of the first alias whose property, or unwrapped form, `isProvided` finds a scope
		/// enclosing the tree provides: the receiver is handed that property. `nil` where every alias is created.
		func providedAliasIndex(isProvided: (Property) -> Bool) -> Int? {
			aliases.firstIndex { alias in
				isProvided(alias.property) || isProvided(alias.property.asUnwrappedProperty)
			}
		}
	}

	/// A child of a scope that a property names, with how directly it names the child: the lower `directness`, the
	/// more directly.
	private struct NamedChild {
		let index: Int
		let directness: Int
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
		/// The fulfilling property of every `onlyIfAvailable` alias of the scopes validated, and its unwrapped form.
		/// Only these are recorded as forwarded by enclosing scopes, or bound by a mock: an alias whose fulfilling
		/// property is forwarded or bound is always created, since the property is in scope wherever the alias is
		/// built, so a receiver beneath it is never handed an enclosing scope's property in its place.
		let onlyIfAvailableAliasFulfillingProperties: Set<Property>
		/// The scopes whose children, and whose trees' children, are known not to require one another, each with
		/// the `onlyIfAvailableAliasProperties` its enclosing scopes provide to it and the
		/// `onlyIfAvailableAliasFulfillingProperties` they forward to it.
		var validatedScopes = Set<ValidatedScope>()

		init(scopes: some Sequence<Scope>) {
			var onlyIfAvailableAliasProperties = Set<Property>()
			var onlyIfAvailableAliasFulfillingProperties = Set<Property>()
			for scope in scopes {
				for case let (property, .aliased(fulfillingProperty, _, onlyIfAvailable: true)) in scope.instantiable.dependencies.lazy.map({ ($0.property, $0.source) }) {
					onlyIfAvailableAliasProperties.insert(property)
					onlyIfAvailableAliasProperties.insert(property.asUnwrappedProperty)
					onlyIfAvailableAliasFulfillingProperties.insert(fulfillingProperty)
					onlyIfAvailableAliasFulfillingProperties.insert(fulfillingProperty.asUnwrappedProperty)
				}
			}
			self.onlyIfAvailableAliasProperties = onlyIfAvailableAliasProperties
			self.onlyIfAvailableAliasFulfillingProperties = onlyIfAvailableAliasFulfillingProperties
		}

		/// The `onlyIfAvailableAliasFulfillingProperties` among `mockParameters`, the properties a mock root is
		/// passed, which are in scope throughout its tree.
		func enclosingForwardedProperties(ofMockRootPassed mockParameters: Set<Property>) -> Set<Property> {
			onlyIfAvailableAliasFulfillingProperties.intersection(mockParameters)
		}

		/// The `onlyIfAvailableAliasFulfillingProperties` forwarded to the children of `scope`, whose enclosing scopes
		/// forward `enclosingForwardedProperties` to it: those and the ones `scope` forwards. Nearly every scope
		/// forwards none, so most share the set they were given.
		func enclosingForwardedProperties(
			of scope: Scope,
			enclosingForwardedProperties: Set<Property>,
		) -> Set<Property> {
			let forwardedProperties = scope.instantiable.forwardedReceivableProperties.intersection(onlyIfAvailableAliasFulfillingProperties)
			return forwardedProperties.isEmpty
				? enclosingForwardedProperties
				: enclosingForwardedProperties.union(forwardedProperties)
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
			let enclosingForwardedProperties: Set<Property>
		}
	}

	/// The instantiated children of `scope` that require one another in a cycle, if any:
	/// each child's tree requires (not `onlyIfAvailable`) a sibling that, directly or
	/// through other siblings, requires it. Such children cannot be ordered so that each
	/// is built after the siblings it receives — whatever their property types, since an
	/// `Instantiator` captures what its tree receives when it is created.
	/// - Parameters:
	///   - enclosingProvidedProperties: The properties of `onlyIfAvailable` aliases, and their unwrapped forms, that
	///     the scopes enclosing `scope` provide to it (see `ChildrenRequiringEachOtherValidation`).
	///   - enclosingForwardedProperties: The fulfilling properties of `onlyIfAvailable` aliases, and their unwrapped
	///     forms, that the scopes enclosing `scope` forward to it, or a mock binds.
	private static func childrenRequiringEachOther(
		in scope: Scope,
		enclosingProvidedProperties: Set<Property>,
		enclosingForwardedProperties: Set<Property>,
		cache: inout ReceivedPropertiesCache,
	) -> ChildrenRequiringEachOther? {
		var children = [(property: Property, scope: Scope)]()
		for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
			children.append((property, childScope))
		}
		// A property names a child most directly as the child's own property, then as the property that receives
		// its instance when it is lazily instantiated, then as an alias the scope declares, in declaration order.
		var childByProperty = [Property: NamedChild]()
		for (index, child) in children.enumerated() {
			childByProperty[child.property] = NamedChild(index: index, directness: 0)
			// A lazily instantiated child is also received by value, as the instance it creates.
			if let instanceProperty = child.property.asLazilyInstantiatedInstanceProperty {
				childByProperty[instanceProperty] = NamedChild(index: index, directness: 1)
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
		var aliasedChildByProperty = [Property: NamedChild]()
		var resolvedAnAlias = true
		while resolvedAnAlias {
			resolvedAnAlias = false
			for (aliasIndex, alias) in aliases.enumerated() where aliasedChildByProperty[alias.property] == nil {
				// An alias of a child's optional form is assigned from that child, as a required receive of it is fulfilled.
				let fulfillingProperties = alias.fulfillingProperty.typeDescription.isOptional
					? [alias.fulfillingProperty, alias.fulfillingProperty.asUnwrappedProperty]
					: [alias.fulfillingProperty]
				if let namedChild = fulfillingProperties.lazy.compactMap({ childByProperty[$0] ?? aliasedChildByProperty[$0] }).first {
					aliasedChildByProperty[alias.property] = NamedChild(index: namedChild.index, directness: 2 + aliasIndex)
					resolvedAnAlias = true
				}
			}
		}
		func namedChild(declaring property: Property) -> NamedChild? {
			childByProperty[property] ?? aliasedChildByProperty[property]
		}
		/// The child declaring the unwrapped form of `property`, which fulfills a required receive of `property`, and
		/// which `property` names less directly than any property the scope declares does.
		func namedChild(declaringUnwrapped property: Property) -> NamedChild? {
			namedChild(declaring: property.asUnwrappedProperty).map {
				NamedChild(index: $0.index, directness: $0.directness + 2 + aliases.count)
			}
		}
		// The properties the scopes enclosing each child provide to it: those its enclosing scopes provide to this
		// scope and those this scope creates, except the child's own, which is still being built inside it, and the
		// instance of a lazily instantiated property, which is read from that property (see
		// `ChildrenRequiringEachOtherValidation.enclosingProvidedProperties(ofChild:of:enclosingProvidedProperties:)`).
		let providedProperties = enclosingProvidedProperties
			.union(scope.createdProperties)
			.subtracting(scope.instantiable.dependencies.compactMap(\.lazilyInstantiatedInstanceProperty))
		// The properties in scope throughout each child's tree: those this scope and its enclosing scopes forward.
		let forwardedProperties = enclosingForwardedProperties.union(scope.instantiable.forwardedReceivableProperties)
		// The siblings each child requires, in sibling order, each with the property through which it is received that
		// names it most directly. A child that receives its own property is reported by the received walk or the ancestor
		// check, but one that receives it through an alias or unwrapped requires itself here. Only the received properties
		// that name a sibling are kept, so nothing is sorted on the common path.
		let requiredSiblings = children.map { child in
			let receivedProperties = collectReceivedProperties(from: child.scope, cache: &cache)
			var mostDirectReceivedPropertyBySiblingIndex = [Int: (property: Property, directness: Int)]()
			func recordRequiredProperty(_ property: Property) {
				// Two optional properties can name a child by one unwrapped form, so the property breaks the tie.
				if let namedChild = namedChild(declaring: property) ?? namedChild(declaringUnwrapped: property),
				   mostDirectReceivedPropertyBySiblingIndex[namedChild.index].map({ (namedChild.directness, property) < ($0.directness, $0.property) }) ?? true
				{
					mostDirectReceivedPropertyBySiblingIndex[namedChild.index] = (property, namedChild.directness)
				}
			}
			// What the child's tree requires through its `onlyIfAvailable` aliases of this scope and the scopes enclosing
			// it. The walk resolves a requirement against the scopes it has walked; this scope and its enclosing scopes
			// resolve what is left as `ScopeDeclarations` does: the last alias is always created where one of them
			// forwards its fulfilling property, and a receiver is handed the property of the first alias one of them
			// provides, other than through the child's own property, which is still being built inside the child. Where
			// every alias is created, the receiver is built after the last alias's fulfilling property.
			var createdAliasFulfillingProperties = Set<Property>()
			var providedAliasProperties = Set<Property>()
			for requirement in receivedProperties.requiredOnlyIfAvailableAliases {
				let aliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
				let requiresFulfillingProperty: Bool
				let lastFulfillingProperty = requirement.aliases[requirement.aliases.count - 1].fulfillingProperty
				if requirement.requiresFulfillingProperty,
				   forwardedProperties.contains(lastFulfillingProperty) || forwardedProperties.contains(lastFulfillingProperty.asUnwrappedProperty)
				{
					aliases = Array(requirement.aliases.dropLast())
					requiresFulfillingProperty = false
				} else {
					aliases = requirement.aliases
					requiresFulfillingProperty = requirement.requiresFulfillingProperty
				}
				if let providedAlias = aliases.first(where: { alias in
					[alias.property, alias.property.asUnwrappedProperty].contains { $0 != child.property && providedProperties.contains($0) }
				}) {
					providedAliasProperties.insert(providedAlias.property)
				} else if requiresFulfillingProperty {
					createdAliasFulfillingProperties.insert(aliases[aliases.count - 1].fulfillingProperty)
				}
			}
			// A property received only if available is still required when it fulfills an `onlyIfAvailable` alias that a
			// receiver requires and that is created.
			for property in receivedProperties.received
				where property != child.property
				&& property != child.property.asLazilyInstantiatedInstanceProperty
				&& (!receivedProperties.onlyIfAvailable.contains(property) || createdAliasFulfillingProperties.contains(property))
			{
				recordRequiredProperty(property)
			}
			// A receiver handed an enclosing scope's property in place of an alias requires that property, which the
			// child's tree does not otherwise receive: the alias's scope declares the alias.
			for property in providedAliasProperties {
				recordRequiredProperty(property)
			}
			return mostDirectReceivedPropertyBySiblingIndex
				.map { (index: $0.key, receivedProperty: $0.value.property) }
				.sorted { $0.index < $1.index }
		}
		// Depth-first search, in sibling order, for a back edge. The search keeps its own path, since a
		// scope can have as many children requiring one another in turn as the module has types.
		var visitedIndices = Set<Int>()
		func cycleOfChildren(reachedFrom startIndex: Int) -> ChildrenRequiringEachOther? {
			visitedIndices.insert(startIndex)
			// Each child on the path, with the position in its `requiredSiblings` of the next sibling to search from.
			var path = [(index: startIndex, nextRequiredSiblingPosition: 0)]
			// The property through which each child on the path receives the next one.
			var pathReceivedProperties = [Property]()
			while let (index, requiredSiblingPosition) = path.last {
				if requiredSiblingPosition < requiredSiblings[index].count {
					path[path.count - 1].nextRequiredSiblingPosition += 1
					let requiredSibling = requiredSiblings[index][requiredSiblingPosition]
					if let pathPosition = path.firstIndex(where: { $0.index == requiredSibling.index }) {
						let receivedPropertyChain = Array(pathReceivedProperties[pathPosition...]) + [requiredSibling.receivedProperty]
						return ChildrenRequiringEachOther(
							instantiated: children[requiredSibling.index].property,
							receivedPropertyChain: receivedPropertyChain,
							closingReceiver: requiredReceiver(
								of: requiredSibling.receivedProperty,
								inTreeOf: children[index].scope,
								enclosingProvidedProperties: providedProperties.subtracting([children[index].property]),
								enclosingForwardedProperties: forwardedProperties,
								cache: &cache,
							),
							requiredOnlyIfAvailableAliases: receivedPropertyChain.compactMap { property in
								onlyIfAvailableAliasFulfillingPropertyByProperty[property].map {
									.init(property: property, fulfillingProperty: $0)
								}
							},
						)
					} else if visitedIndices.insert(requiredSibling.index).inserted {
						pathReceivedProperties.append(requiredSibling.receivedProperty)
						path.append((index: requiredSibling.index, nextRequiredSiblingPosition: 0))
					}
				} else {
					path.removeLast()
					// The child the path started from was reached through no property.
					if !path.isEmpty {
						pathReceivedProperties.removeLast()
					}
				}
			}
			return nil
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
	/// after it, which no compiler stage before SIL rejects. Each tree reports the first
	/// error it finds, and the errors of every tree are reported. Scopes in `validation`'s
	/// `validatedScopes` are skipped along with their trees, and every scope whose tree is
	/// validated without error is added to it. Each tree is validated depth first, in the
	/// order each scope declares its children, with a stack of the scopes left to validate,
	/// since a tree can be as deep as the module has types.
	/// - Parameter rootScopes: The roots of the trees, each with the properties of `onlyIfAvailable` aliases that
	///   the scopes enclosing it provide to it and the fulfilling properties of `onlyIfAvailable` aliases they
	///   forward to it (see `ChildrenRequiringEachOtherValidation`).
	private static func validateChildrenDoNotRequireEachOther(
		inTreesRootedAt rootScopes: [(scope: Scope, enclosingProvidedProperties: Set<Property>, enclosingForwardedProperties: Set<Property>)],
		cache: inout ReceivedPropertiesCache,
		validation: inout ChildrenRequiringEachOtherValidation,
	) throws {
		var treeErrors = [DependencyTreeGeneratorError]()
		for rootScope in rootScopes {
			// The scopes of this tree validated so far, each with the index here of the scope that instantiates it.
			var walkedScopes = [(validatedScope: ChildrenRequiringEachOtherValidation.ValidatedScope, parentIndex: Int?)]()
			var scopesToValidate: [(validatedScope: ChildrenRequiringEachOtherValidation.ValidatedScope, parentIndex: Int?)] = [
				(
					validatedScope: ChildrenRequiringEachOtherValidation.ValidatedScope(
						scope: rootScope.scope,
						enclosingProvidedProperties: rootScope.enclosingProvidedProperties,
						enclosingForwardedProperties: rootScope.enclosingForwardedProperties,
					),
					parentIndex: nil,
				),
			]
			do {
				while let (validatedScope, parentIndex) = scopesToValidate.popLast() {
					guard validation.validatedScopes.insert(validatedScope).inserted else { continue }
					let scope = validatedScope.scope
					walkedScopes.append((validatedScope: validatedScope, parentIndex: parentIndex))
					let walkedScopeIndex = walkedScopes.count - 1
					if let aliasesFulfillingOneAnother = aliasesFulfillingOneAnother(in: scope) {
						throw aliasesFulfillingOneAnother.error
					} else if let childrenRequiringEachOther = childrenRequiringEachOther(
						in: scope,
						enclosingProvidedProperties: validatedScope.enclosingProvidedProperties,
						enclosingForwardedProperties: validatedScope.enclosingForwardedProperties,
						cache: &cache,
					) {
						throw childrenRequiringEachOther.error
					} else {
						let firstChildIndex = scopesToValidate.endIndex
						let childEnclosingForwardedProperties = validation.enclosingForwardedProperties(
							of: scope,
							enclosingForwardedProperties: validatedScope.enclosingForwardedProperties,
						)
						for case let .instantiated(childProperty, childScope, _) in scope.propertiesToGenerate {
							scopesToValidate.append((
								validatedScope: ChildrenRequiringEachOtherValidation.ValidatedScope(
									scope: childScope,
									enclosingProvidedProperties: validation.enclosingProvidedProperties(
										ofChild: childProperty,
										of: scope,
										enclosingProvidedProperties: validatedScope.enclosingProvidedProperties,
									),
									enclosingForwardedProperties: childEnclosingForwardedProperties,
								),
								parentIndex: walkedScopeIndex,
							))
						}
						// The scope validated next is the last one on the stack, so the first child goes last.
						scopesToValidate[firstChildIndex...].reverse()
					}
				}
			} catch let error as DependencyTreeGeneratorError {
				// The next tree that reaches a scope on the path to the error validates it again, and reports the same
				// error, rather than skipping it and validating what this tree did not reach because it stopped there.
				// The scope that reported the error was the last one walked.
				var walkedScopeIndex = walkedScopes.indices.last
				while let index = walkedScopeIndex {
					validation.validatedScopes.remove(walkedScopes[index].validatedScope)
					walkedScopeIndex = walkedScopes[index].parentIndex
				}
				treeErrors.append(error)
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: treeErrors) {
			throw error
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

	/// A scope whose tree `requiredReceiver` has searched for a receiver of a property, given the properties the
	/// scopes enclosing it provide.
	private struct SearchedScope: Hashable {
		let scope: ObjectIdentifier
		let property: Property
		let enclosingProvidedProperties: Set<Property>
		let enclosingForwardedProperties: Set<Property>
	}

	/// The first dependency, in declaration order and then child order, in the tree that
	/// `scope` creates that requires `property` from outside the tree — a dependency
	/// through which `collectReceivedProperties` finds the tree requires `property`,
	/// which lists `property` in `received` and not in `onlyIfAvailable`, or as the fulfilling
	/// property of one of its `requiredOnlyIfAvailableAliases` that `childrenRequiringEachOther`
	/// finds is created. Such an alias counts: it is created for the receiver that requires
	/// it, so the tree is built after `property` (see `ScopeGenerator.orderedPropertiesToGenerate`),
	/// and the search goes on for the receiver of the alias's property: a required alias of it
	/// the same scope declares, which is that receiver; an `onlyIfAvailable` alias of it the
	/// same scope declares that is required in turn, through which the search goes on; or
	/// else beneath the scope, whose children's trees receive the alias's property. The
	/// aliases are the ones `ScopeDeclarations.requirements(childRequiredReceived:childRequirements:)`
	/// finds for the walk, so the search sees a requirement through any chain of aliases where
	/// the check does. An `onlyIfAvailable` alias whose property an enclosing scope provides
	/// is not created where its fulfilling property is unavailable, and the receiver beneath it
	/// that requires its property is handed the enclosing scope's property: `property` can be
	/// that alias's property, as `childrenRequiringEachOther` asks about it, and the search then
	/// goes on beneath the alias as it does for an alias that is required, with the enclosing
	/// scope's property in the hint. `enclosingProvidedProperties` holds
	/// what the scopes enclosing `scope` provide, and what each scope searched provides is
	/// added for its children, except the child being built. The tree is searched depth first
	/// with a stack of the scopes left to search, since it can be as deep as the module has
	/// types. `nil` when no dependency in the tree requires `property`, which
	/// `childrenRequiringEachOther` never asks about: the walk and the search decide what a
	/// scope provides by the same rules.
	private static func requiredReceiver(
		of property: Property,
		inTreeOf scope: Scope,
		enclosingProvidedProperties: Set<Property>,
		enclosingForwardedProperties: Set<Property>,
		cache: inout ReceivedPropertiesCache,
	) -> RequiredReceiver? {
		var searchedScopes = Set<SearchedScope>()
		var scopesToSearch = [(
			scope: scope,
			property: property,
			enclosingProvidedProperties: enclosingProvidedProperties,
			enclosingForwardedProperties: enclosingForwardedProperties,
			requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias](),
		)]
		var receiver: RequiredReceiver?
		while receiver == nil, let (scope, property, enclosingProvidedProperties, enclosingForwardedProperties, requiredOnlyIfAvailableAliases) = scopesToSearch.popLast() {
			guard searchedScopes.insert(SearchedScope(
				scope: ObjectIdentifier(scope),
				property: property,
				enclosingProvidedProperties: enclosingProvidedProperties,
				enclosingForwardedProperties: enclosingForwardedProperties,
			)).inserted else { continue }
			let declarations = ScopeDeclarations(scope: scope)
			// The properties in scope throughout the children's trees: those this scope and its enclosing scopes forward.
			let forwardedProperties = declarations.forwardedProperties.isEmpty
				? enclosingForwardedProperties
				: enclosingForwardedProperties.union(declarations.forwardedProperties)
			/// The properties the scopes enclosing the child `childProperty` provide to it.
			func propertiesProvided(toChild childProperty: Property) -> Set<Property> {
				enclosingProvidedProperties
					.union(scope.createdProperties)
					.subtracting(declarations.lazilyInstantiatedInstanceProperties)
					.subtracting([childProperty])
			}
			/// The properties of the `onlyIfAvailable` aliases the scope declares that a receiver requires be created, given
			/// what its children's trees require, as the walk finds them in `UnfinishedReceivedPropertiesWalk.finished`, and
			/// given what the enclosing scopes provide: an alias is created only where no scope enclosing it provides its
			/// property, or the property of an alias nearer the receiver that requires it. Computed once, when the scope
			/// declares an `onlyIfAvailable` alias of the searched property.
			var computedRequiredAliasProperties: Set<Property>?
			func requiredAliasProperties() -> Set<Property> {
				if let computedRequiredAliasProperties {
					return computedRequiredAliasProperties
				} else {
					var childRequiredReceived = Set<Property>()
					var childRequirements = Set<OnlyIfAvailableAliasRequirement>()
					for case let .instantiated(childProperty, childScope, _) in scope.propertiesToGenerate {
						let childReceivedProperties = collectReceivedProperties(from: childScope, cache: &cache)
						childRequiredReceived.formUnion(childReceivedProperties.received.subtracting(childReceivedProperties.onlyIfAvailable))
						childRequirements.formUnion(declarations.requirements(
							recordedFrom: childReceivedProperties.requiredOnlyIfAvailableAliases,
							ofChild: childProperty,
						))
					}
					var requiredAliasProperties = Set<Property>()
					for requirement in declarations.requirements(childRequiredReceived: childRequiredReceived, childRequirements: childRequirements) {
						for alias in requirement.aliases {
							guard enclosingProvidedProperties.isDisjoint(with: [alias.property, alias.property.asUnwrappedProperty]) else { break }
							if declarations.onlyIfAvailableAliases.contains(alias) {
								requiredAliasProperties.insert(alias.property)
							}
						}
					}
					computedRequiredAliasProperties = requiredAliasProperties
					return requiredAliasProperties
				}
			}
			// The property searched for in this scope: `property`, or the property of an `onlyIfAvailable` alias of
			// it that the scope declares and that is required, which the receiver then receives instead. A required
			// alias of the scope's own alias is its receiver, although it refers to a property the scope declares.
			// The chain follows each of the scope's aliases at most once: a type's properties have distinct labels,
			// so no alias renames one to another's property, and aliases that fulfill one another are never required
			// from above, since each is fulfilled by a property the scope declares.
			var searchedProperty = property
			var searchedPropertyIsOwnAlias = false
			var requiredOnlyIfAvailableAliases = requiredOnlyIfAvailableAliases
			var searchesBeneath = false
			while receiver == nil, !searchesBeneath {
				// An alias of a property the scope declares or forwards refers to that property, as
				// `collectReceivedProperties` has it.
				func receivesFromOutside(_ fulfillingProperty: Property) -> Bool {
					fulfillingProperty == searchedProperty
						&& (searchedPropertyIsOwnAlias || (!declarations.propertiesToDeclare.contains(fulfillingProperty) && !declarations.forwardedProperties.contains(fulfillingProperty)))
				}
				if let dependency = scope.instantiable.dependencies.first(where: { dependency in
					switch dependency.source {
					case let .received(onlyIfAvailable):
						!onlyIfAvailable && dependency.property == searchedProperty
					case let .aliased(fulfillingProperty, _, onlyIfAvailable):
						!onlyIfAvailable && receivesFromOutside(fulfillingProperty)
					case .instantiated, .forwarded:
						false
					}
				}) {
					receiver = RequiredReceiver(dependency: dependency, requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases)
				} else if !searchedPropertyIsOwnAlias,
				          let uncreatedAlias = declarations.onlyIfAvailableAliases.first(where: { $0.property == searchedProperty }),
				          enclosingForwardedProperties.isDisjoint(with: [uncreatedAlias.fulfillingProperty, uncreatedAlias.fulfillingProperty.asUnwrappedProperty]),
				          let providedProperty = [searchedProperty, searchedProperty.asUnwrappedProperty].first(where: enclosingProvidedProperties.contains)
				{
					// An `onlyIfAvailable` alias whose property an enclosing scope provides, and whose fulfilling property no
					// enclosing scope forwards, is not created where its fulfilling property is unavailable, and the receiver
					// beneath it that requires its property is handed the enclosing scope's property instead, so that receiver
					// is the one searched for: the search goes on as it does for the scope's own alias, with the enclosing
					// scope's property in the hint.
					requiredOnlyIfAvailableAliases.append(.init(
						property: uncreatedAlias.property,
						fulfillingProperty: uncreatedAlias.fulfillingProperty,
						providedProperty: providedProperty,
					))
					searchedPropertyIsOwnAlias = true
				} else if let requiredAlias = scope.instantiable.dependencies.first(where: { dependency in
					if case let .aliased(fulfillingProperty, _, onlyIfAvailable: true) = dependency.source {
						// An alias of a property the scope provides, exactly or by its unwrapped form, is created from it.
						fulfillingProperty == searchedProperty
							&& (searchedPropertyIsOwnAlias || !declarations.provides(fulfillingProperty))
							&& requiredAliasProperties().contains(dependency.property)
					} else {
						false
					}
				}) {
					// The receiver that requires the alias receives the alias's property, which the scope declares.
					requiredOnlyIfAvailableAliases.append(.init(property: requiredAlias.property, fulfillingProperty: searchedProperty))
					searchedProperty = requiredAlias.property
					searchedPropertyIsOwnAlias = true
				} else {
					searchesBeneath = true
				}
			}
			// A scope that declares `property` is not searched beneath: the trees of its children receive its own.
			if searchesBeneath, searchedPropertyIsOwnAlias || !declarations.provides(searchedProperty) {
				// The scope searched next is the last one on the stack, so the first child goes last.
				let firstChildIndex = scopesToSearch.endIndex
				for case let .instantiated(childProperty, childScope, _) in scope.propertiesToGenerate {
					scopesToSearch.append((childScope, searchedProperty, propertiesProvided(toChild: childProperty), forwardedProperties, requiredOnlyIfAvailableAliases))
				}
				scopesToSearch[firstChildIndex...].reverse()
			}
		}
		return receiver
	}

	/// What a scope declares, forwards, and aliases, as the walk of its received properties
	/// (`UnfinishedReceivedPropertiesWalk`) and the search of its tree (`requiredReceiver`) read it, with the rules by
	/// which both carry the `OnlyIfAvailableAliasRequirement`s of its children's trees through it, which
	/// `ScopeGenerator` mirrors in `isRequiredByChild`, `requiredOnlyIfAvailableAliasProperties`, and
	/// `onlyIfAvailableAliasPropertyProvidedByEnclosingScope` to decide what each tree is built after.
	private struct ScopeDeclarations {
		init(scope: Scope) {
			propertiesToDeclare = DependencyTreeGenerator.propertiesToDeclare(in: scope)
			forwardedProperties = scope.instantiable.forwardedReceivableProperties
			lazilyInstantiatedInstanceProperties = scope.instantiable.dependencies.compactMap(\.lazilyInstantiatedInstanceProperty)
			var onlyIfAvailableAliases = [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]()
			var requiredAliasFulfillingProperties = Set<Property>()
			for case let (property, .aliased(fulfillingProperty, _, onlyIfAvailable)) in scope.instantiable.dependencies.lazy.map({ ($0.property, $0.source) }) {
				if onlyIfAvailable {
					onlyIfAvailableAliases.append(.init(property: property, fulfillingProperty: fulfillingProperty))
				} else {
					requiredAliasFulfillingProperties.insert(fulfillingProperty)
				}
			}
			self.onlyIfAvailableAliases = onlyIfAvailableAliases
			self.requiredAliasFulfillingProperties = requiredAliasFulfillingProperties
		}

		/// The properties the scope declares for its children: those it instantiates and the aliases it assigns. A
		/// lazily instantiated property also declares the property that receives its instance by value.
		let propertiesToDeclare: Set<Property>
		/// The properties the scope forwards. A lazily instantiated one is also received by value.
		let forwardedProperties: Set<Property>
		/// The properties that receive the instances of the scope's lazily instantiated properties by value.
		let lazilyInstantiatedInstanceProperties: [Property]
		/// The `onlyIfAvailable` aliases the scope declares, in declaration order.
		let onlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
		/// The fulfilling properties of the required aliases the scope declares.
		let requiredAliasFulfillingProperties: Set<Property>

		/// Whether the scope provides `property` to the scopes beneath it, as `ScopeGenerator.provides` has it: it
		/// declares or forwards the property or, for an optional property, its unwrapped form.
		func provides(_ property: Property) -> Bool {
			propertiesToDeclare.contains(property)
				|| forwardedProperties.contains(property)
				|| (property.typeDescription.isOptional
					&& (propertiesToDeclare.contains(property.asUnwrappedProperty) || forwardedProperties.contains(property.asUnwrappedProperty)))
		}

		/// Whether the scope forwards `property`, or its unwrapped form, which is then in scope wherever the scope's
		/// tree is built.
		func forwards(_ property: Property) -> Bool {
			forwardedProperties.contains(property) || forwardedProperties.contains(property.asUnwrappedProperty)
		}

		/// Whether the scope provides `property` to its child `childProperty`, as `isProvidedByEnclosingScope` in
		/// `Scope.createScopeGenerator` has it. The child's own property is still being built inside the child, and
		/// the instance of a lazily instantiated property is read from that property, which a declaration with its
		/// label hides, so neither counts.
		func provides(_ property: Property, toChild childProperty: Property) -> Bool {
			property != childProperty
				&& !lazilyInstantiatedInstanceProperties.contains(property)
				&& (propertiesToDeclare.contains(property) || forwardedProperties.contains(property))
		}

		/// The requirements of the tree of the child `childProperty` as the scope records them. A requirement whose
		/// receiver is handed a property this scope provides to the child, in place of an alias, is cut at that alias.
		/// Where the scope provides the property through an `onlyIfAvailable` alias of its own, that alias is required
		/// through the aliases nearer the receiver, and the requirement goes on from it. Otherwise only the nearer
		/// aliases are kept, for a scope enclosing this one that provides one of their properties, and nothing is
		/// required of the aliases beyond.
		func requirements(
			recordedFrom childRequirements: Set<OnlyIfAvailableAliasRequirement>,
			ofChild childProperty: Property,
		) -> Set<OnlyIfAvailableAliasRequirement> {
			var requirements = Set<OnlyIfAvailableAliasRequirement>()
			for requirement in childRequirements {
				if let providedAliasIndex = requirement.providedAliasIndex(isProvided: { provides($0, toChild: childProperty) }) {
					let nearerAliases = Array(requirement.aliases[..<providedAliasIndex])
					let providedProperty = requirement.aliases[providedAliasIndex].property
					if let alias = onlyIfAvailableAliases.first(where: { $0.property == providedProperty }) {
						requirements.insert(.init(aliases: nearerAliases + [alias], requiresFulfillingProperty: true))
					} else if !nearerAliases.isEmpty {
						requirements.insert(.init(aliases: nearerAliases, requiresFulfillingProperty: false))
					}
				} else {
					requirements.insert(requirement)
				}
			}
			return requirements
		}

		/// The requirements the scope's tree has of the scopes enclosing it, given what its children's trees require:
		/// `childRequiredReceived`, the properties they require, and `childRequirements`, their requirements as
		/// `requirements(recordedFrom:ofChild:)` records them. An `onlyIfAvailable` alias the scope declares is
		/// required when a child's tree requires its property; when a required alias the scope declares is fulfilled by
		/// its property, which is always created; or when the last alias of a requirement is fulfilled by its property,
		/// through which that requirement then goes on. The last way chains through the scope's own aliases, so the
		/// aliases are found until a pass finds no more. An alias required several ways is listed once for each, since
		/// each depends on different aliases being created. A requirement whose last alias's fulfilling property the
		/// scope forwards loses that alias, which is always created; one whose last alias's fulfilling property the
		/// scope declares requires nothing of the scopes above but the property of a nearer alias one of them provides.
		func requirements(
			childRequiredReceived: Set<Property>,
			childRequirements: Set<OnlyIfAvailableAliasRequirement>,
		) -> Set<OnlyIfAvailableAliasRequirement> {
			var requirements = childRequirements
			if !onlyIfAvailableAliases.isEmpty {
				var foundRequirement = true
				while foundRequirement {
					foundRequirement = false
					for alias in onlyIfAvailableAliases {
						var requiringAliasChains = [[DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]]()
						if childRequiredReceived.contains(alias.property) || requiredAliasFulfillingProperties.contains(alias.property) {
							requiringAliasChains.append([])
						}
						// Aliases that fulfill one another are never required from above: each is fulfilled by a property
						// the scope declares. An alias already on the chain is not followed again.
						for requirement in requirements
							where requirement.requiresFulfillingProperty
							&& requirement.aliases[requirement.aliases.count - 1].fulfillingProperty == alias.property
							&& !requirement.aliases.contains(alias)
						{
							requiringAliasChains.append(requirement.aliases)
						}
						for requiringAliases in requiringAliasChains {
							if requirements.insert(.init(aliases: requiringAliases + [alias], requiresFulfillingProperty: true)).inserted {
								foundRequirement = true
							}
						}
					}
				}
			}
			guard !requirements.isEmpty else { return requirements }
			var resolvedRequirements = Set<OnlyIfAvailableAliasRequirement>()
			for requirement in requirements {
				let fulfillingProperty = requirement.aliases[requirement.aliases.count - 1].fulfillingProperty
				if !requirement.requiresFulfillingProperty {
					resolvedRequirements.insert(requirement)
				} else if forwards(fulfillingProperty) {
					if requirement.aliases.count > 1 {
						resolvedRequirements.insert(.init(aliases: Array(requirement.aliases.dropLast()), requiresFulfillingProperty: false))
					}
				} else if provides(fulfillingProperty) {
					resolvedRequirements.insert(.init(aliases: requirement.aliases, requiresFulfillingProperty: false))
				} else {
					resolvedRequirements.insert(requirement)
				}
			}
			return resolvedRequirements
		}
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
		case let .aliased(fulfillingProperty, _, _):
			// An alias receives its fulfilling property, unless `scope` creates the property, which the alias then
			// refers to, so the dependency that creates it is what closes the cycle. An `onlyIfAvailable` alias closes
			// no cycle (`Dependency.canCloseDependencyCycle`).
			if scope.createdProperties.contains(fulfillingProperty) {
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
		/// What receivers in the subtree require through the `onlyIfAvailable` aliases declared in it, of the scopes
		/// above the subtree (see `OnlyIfAvailableAliasRequirement`): the fulfilling property of the last alias, which
		/// the subtree receives only if available to create the alias, or the property of an alias that a scope above
		/// provides in the alias's place, as `ScopeDeclarations.requirements(recordedFrom:ofChild:)` cuts a requirement
		/// at the alias whose property a scope in the subtree provides.
		let requiredOnlyIfAvailableAliases: Set<OnlyIfAvailableAliasRequirement>
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
	/// - Returns: The subtree's received properties. The fulfilling properties of its
	///   `requiredOnlyIfAvailableAliases` mirror ScopeGenerator's `requiredAliasFulfillingProperties`,
	///   except that they do not leave out an alias whose property a scope enclosing the subtree
	///   provides, which the walk cannot see: `childrenRequiringEachOther` leaves those out.
	private static func collectReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> ReceivedProperties {
		walkReceivedProperties(from: scope, cache: &cache).receivedProperties
	}

	/// Walks the tree `scope` creates, children before the scopes that create them, with a stack of the scopes whose
	/// walk is unfinished, since a tree can be as deep as the module has types.
	private static func walkReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> WalkedReceivedProperties {
		var walks: [UnfinishedReceivedPropertiesWalk]
		switch startWalkingReceivedProperties(from: scope, cache: &cache) {
		case let .walked(walkedReceivedProperties):
			return walkedReceivedProperties
		case let .unfinished(walk):
			walks = [walk]
		}
		while true {
			let walkIndex = walks.count - 1
			let nextPropertyIndex = walks[walkIndex].nextPropertyIndex
			if nextPropertyIndex < walks[walkIndex].propertiesToGenerate.count {
				walks[walkIndex].nextPropertyIndex += 1
				// Aliases are handled in `UnfinishedReceivedPropertiesWalk.finished(cache:)`'s own-dependency loop.
				if case let .instantiated(_, childScope, _) = walks[walkIndex].propertiesToGenerate[nextPropertyIndex] {
					switch startWalkingReceivedProperties(from: childScope, cache: &cache) {
					case let .walked(walkedChild):
						walks[walkIndex].record(walkedChild)
					case let .unfinished(childWalk):
						walks.append(childWalk)
					}
				}
			} else {
				var finishedWalk = walks.removeLast()
				let walkedReceivedProperties = finishedWalk.finished(cache: &cache)
				if walks.isEmpty {
					return walkedReceivedProperties
				} else {
					walks[walks.count - 1].record(walkedReceivedProperties)
				}
			}
		}
	}

	/// How a walk of a scope's received properties starts: with a result it needs no walk for, or with a walk
	/// of the scope's tree.
	private enum ReceivedPropertiesWalkStart {
		case walked(WalkedReceivedProperties)
		case unfinished(UnfinishedReceivedPropertiesWalk)
	}

	private static func startWalkingReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> ReceivedPropertiesWalkStart {
		let id = ObjectIdentifier(scope)
		if let complete = cache.complete[id] {
			return .walked(WalkedReceivedProperties(receivedProperties: complete, shallowestUnfinishedWalkDepth: nil))
		} else if let unfinishedWalkDepth = cache.unfinishedWalkDepths[id] {
			// A cycle re-entered this scope. Its unfinished walk accounts for what it receives.
			return .walked(WalkedReceivedProperties(
				receivedProperties: ReceivedProperties(received: [], onlyIfAvailable: [], requiredOnlyIfAvailableAliases: []),
				shallowestUnfinishedWalkDepth: unfinishedWalkDepth,
			))
		} else if let incomplete = cache.incomplete[id] {
			return .walked(incomplete)
		} else {
			let walkDepth = cache.unfinishedWalkDepths.count
			cache.unfinishedWalkDepths[id] = walkDepth
			return .unfinished(UnfinishedReceivedPropertiesWalk(scope: scope, walkDepth: walkDepth))
		}
	}

	/// A scope whose received properties `walkReceivedProperties` is collecting, with what it has collected from
	/// the trees of the children walked so far.
	private struct UnfinishedReceivedPropertiesWalk {
		init(scope: Scope, walkDepth: Int) {
			self.scope = scope
			self.walkDepth = walkDepth
			propertiesToGenerate = scope.propertiesToGenerate
			declarations = ScopeDeclarations(scope: scope)
		}

		let scope: Scope
		let walkDepth: Int
		let propertiesToGenerate: [Scope.PropertyToGenerate]
		/// The index in `propertiesToGenerate` of the next property whose tree to walk.
		var nextPropertyIndex = 0

		let declarations: ScopeDeclarations
		// Properties declared at this scope (instantiated/aliased children). A lazily instantiated
		// property also declares the property that receives its instance by value.
		var propertiesToDeclare: Set<Property> {
			declarations.propertiesToDeclare
		}

		// Forwarded properties at this scope. A lazily instantiated one is also received by value.
		var forwardedProperties: Set<Property> {
			declarations.forwardedProperties
		}

		var received = Set<Property>()
		var onlyIfAvailable = Set<Property>()
		// Received properties some receiver in this subtree requires. A property can be
		// received both ways — e.g. a required `x: X` and an `onlyIfAvailable` alias
		// fulfilled by `x: X` — and a required receive wins.
		var required = Set<Property>()
		// Properties the instantiated children's subtrees require, including those this scope declares.
		var childRequiredReceived = Set<Property>()
		// The requirements of the instantiated children's subtrees, as this scope records them
		// (see `ScopeDeclarations.requirements(recordedFrom:ofChild:)`).
		var childRequirements = Set<OnlyIfAvailableAliasRequirement>()
		var shallowestUnfinishedWalkDepth: Int?

		/// Collects from an instantiated child — mirrors ScopeGenerator's receivedProperties aggregation.
		/// Aliases are handled in `finished(cache:)`'s own-dependency loop: alias children's receivedProperties
		/// = [fulfillingProperty], but the own-dependency union unconditionally adds the same
		/// fulfillingProperty, making the child-path subtraction/filter redundant.
		mutating func record(_ walkedChild: WalkedReceivedProperties) {
			shallowestUnfinishedWalkDepth = [shallowestUnfinishedWalkDepth, walkedChild.shallowestUnfinishedWalkDepth].compactMap(\.self).min()
			let childReceived = walkedChild.receivedProperties.received
			let childOnlyIfAvailable = walkedChild.receivedProperties.onlyIfAvailable
			childRequiredReceived.formUnion(childReceived.subtracting(childOnlyIfAvailable))
			if !walkedChild.receivedProperties.requiredOnlyIfAvailableAliases.isEmpty {
				// An alias whose property this scope provides to the child is not created: its receiver is handed this
				// scope's property, as `isProvidedByEnclosingScope` has generation do, and requires it. The child whose
				// tree was walked is the one before `nextPropertyIndex`.
				childRequirements.formUnion(declarations.requirements(
					recordedFrom: walkedChild.receivedProperties.requiredOnlyIfAvailableAliases,
					ofChild: propertiesToGenerate[nextPropertyIndex - 1].property,
				))
			}
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

		/// Ends the walk once every child's tree is walked, recording its result in `cache`.
		mutating func finished(cache: inout ReceivedPropertiesCache) -> WalkedReceivedProperties {
			// This scope's own received/aliased dependencies.
			// Store exact properties (not unwrapped) in onlyIfAvailable. This avoids
			// collisions between a required `x: X` and an onlyIfAvailable `x: X?` —
			// they are distinct Properties. The subtraction in `record(_:)` uses unwrapped comparison
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
					} else {
						required.insert(fulfillingProperty)
					}
				case .instantiated, .forwarded:
					break
				}
			}
			// The requirements this scope's tree has of the scopes enclosing it, through any chain of aliases, given
			// what the children's trees require.
			let requiredOnlyIfAvailableAliases = declarations.requirements(
				childRequiredReceived: childRequiredReceived,
				childRequirements: childRequirements,
			)

			let id = ObjectIdentifier(scope)
			cache.unfinishedWalkDepths[id] = nil
			if !cache.incomplete.isEmpty {
				// Results that lack what this scope receives are stale now that its walk has finished.
				let walkDepth = walkDepth
				cache.incomplete = cache.incomplete.filter { $0.value.shallowestUnfinishedWalkDepth != walkDepth }
			}
			let receivedProperties = ReceivedProperties(
				received: received,
				onlyIfAvailable: onlyIfAvailable.subtracting(required),
				requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases,
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
		// The types reached whose instantiated types are not yet recorded. A worklist rather than recursion,
		// since a chain of types can be as long as the module has types.
		var typeDescriptionsToVisit = Array(rootInstantiables)
		while let reachableTypeDescription = typeDescriptionsToVisit.popLast() {
			guard reachableTypeDescriptions.insert(reachableTypeDescription).inserted else {
				// We've visited this tree already. Ignore.
				continue
			}
			guard let instantiable = typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] else {
				// We can't find an instantiable for this type.
				// This is bad, but we'll handle this error in `validateReachableTypeDescriptions()`.
				continue
			}
			for dependency in instantiable.dependencies where dependency.isInstantiated {
				typeDescriptionsToVisit.append(dependency.asInstantiatedType)
			}
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
		// visited in an order that changes from run to run, and every dependency that cannot be
		// instantiated is reported, in source order.
		var forwardedPropertyErrors = [DependencyTreeGeneratorError]()
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
						) {
							forwardedPropertyErrors.append(error)
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
		if let error = DependencyTreeGeneratorError.reportingAll(of: forwardedPropertyErrors) {
			throw error
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
			/// Where that type declares `property`.
			let declarationLocation: Dependency.DeclarationLocation?
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
			// Analyze the scopes created along with this one first, each after those created along with it, so that
			// the analysis below reads theirs from the cache. A chain of them can be as long as the module has types.
			for createdScope in unanalyzedScopes(createdAlongWith: scope, cache: cache) {
				_ = instantiationAnalysis(of: createdScope, cache: &cache)
			}
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
				// Reads this type renames to one property are recorded as the read of the reader declared first. Sorted by
				// where each reader is declared, so which reader is reported never depends on dictionary iteration, or on
				// the labels of the aliases the reads are renamed through. Reads at one location have one reader.
				for (property, reader) in instantiationAnalysis(of: childScope, cache: &cache).readFromAncestors.sorted(by: {
					Dependency.DeclarationLocation.precedesInSourceOrder($0.value.declarationLocation, $1.value.declarationLocation)
				}) {
					let readProperty = propertyRead(by: property)
					if readWhileCreated[readProperty] == nil {
						readWhileCreated[readProperty] = reader
					}
				}
			}

			/// Records that creating this type reads `property` through `dependency`, unless a dependency declared
			/// earlier reads it, as two renamings of one instance do.
			func recordRead(of property: Property, by dependency: Dependency, receivedLabel: String) {
				if readWhileCreated[property] == nil {
					readWhileCreated[property] = .init(instantiable: instantiable, property: dependency.property, receivedLabel: receivedLabel, declarationLocation: dependency.declarationLocation)
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
						recordRead(of: dependency.property, by: dependency, receivedLabel: dependency.property.label)
					}
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					if !onlyIfAvailable, fulfillingProperty.propertyType.isConstant {
						recordRead(of: propertyRead(by: fulfillingProperty), by: dependency, receivedLabel: fulfillingProperty.label)
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

	/// The scopes created along with `scope` – those it instantiates as constants or lazily, and theirs in turn –
	/// whose analysis `cache` lacks, each listed after the scopes created along with it. `scope` is not listed.
	/// The search keeps its own path, since a chain of such scopes can be as long as the module has types.
	private static func unanalyzedScopes(
		createdAlongWith scope: Scope,
		cache: [ObjectIdentifier: InstantiationAnalysis],
	) -> [Scope] {
		/// The scopes `instantiationAnalysis` reads the analysis of when it analyzes `scope`.
		func scopesCreated(alongWith scope: Scope) -> [Scope] {
			var createdScopes = [Scope]()
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate
				where property.asLazilyInstantiatedInstanceProperty != nil || property.propertyType.isConstant
			{
				createdScopes.append(childScope)
			}
			return createdScopes
		}
		var unanalyzedScopes = [Scope]()
		var visitedScopes: Set<ObjectIdentifier> = [ObjectIdentifier(scope)]
		// Each scope on the path, with the scopes created along with it and the index of the next one to visit.
		var path = [(scope: scope, createdScopes: scopesCreated(alongWith: scope), nextIndex: 0)]
		while let (pathScope, createdScopes, nextIndex) = path.last {
			if nextIndex < createdScopes.count {
				path[path.count - 1].nextIndex += 1
				let createdScope = createdScopes[nextIndex]
				if cache[ObjectIdentifier(createdScope)] == nil, visitedScopes.insert(ObjectIdentifier(createdScope)).inserted {
					path.append((scope: createdScope, createdScopes: scopesCreated(alongWith: createdScope), nextIndex: 0))
				}
			} else {
				path.removeLast()
				// The scope the search starts from is the one being analyzed.
				if !path.isEmpty {
					unanalyzedScopes.append(pathScope)
				}
			}
		}
		return unanalyzedScopes
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
		// Every tree is validated, and the errors are reported in source order, so neither depends on the order of the
		// trees; they are validated in type order regardless. A root receives nothing, so its tree binds nothing above
		// its own properties.
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
				// A type whose hand-written mock is not passed some of its dependencies has two scopes, which only
				// identity tells apart: the full one first, then the one its hand-written mock builds.
				.sorted { ($0.instantiable.concreteInstantiable, $0.dependenciesLeftOut.count) < ($1.instantiable.concreteInstantiable, $1.dependenciesLeftOut.count) }
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

	/// A scope that `validatePropertiesAreFulfillable` has yet to validate, with what the scopes it is built inside
	/// give it.
	private struct ScopeToValidate {
		let scope: Scope
		/// The properties the scopes `scope` is built inside make available to it.
		let receivableProperties: Set<Property>
		/// The aliases declared above `scope` that a receive of their property resolves to.
		let receivableAliases: [Property: ReceivableAlias]
		/// The property each label names in `scope`: the one declared by the closest ancestor that declares the label.
		let closestDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration]
		/// The property `scope` is built for, as cycle validation sees it. `nil` at the root of the tree.
		let property: Property?
		/// The properties of the scopes `scope` is built inside, innermost first.
		let propertyStack: [Property]
		/// The lazily instantiated properties on the instantiation stack, keyed by the constant each is validated as.
		let lazilyInstantiatedDeclarations: [Property: Property]
	}

	/// A scope whose required received properties `validateNoCycleInReceivedProperties` is walking.
	private struct ReceivedPropertyWalk {
		let requiredReceivedProperties: [Scope.RequiredReceivedProperty]
		/// The index in `requiredReceivedProperties` of the next property to walk.
		var nextIndex = 0
		let directParent: TypeDescription
		/// The received property whose scope this is, which ends the received-property stack while it is walked.
		/// `nil` for the scope the walk starts from.
		let walkedProperty: Property?
		/// Whether walking `walkedProperty` added its declaration to the declared received-property stack.
		let addedDeclaredReceivedProperty: Bool
		/// The properties on the received-property stack that this scope's walk has relied on so far.
		var stackPropertiesReliedOn = Set<Property>()
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
		/// The walk descends depth first, in declaration order, and keeps its own stack of the scopes it is part way
		/// through, since a chain of received properties can be as long as the module has types.
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
		func validateNoCycleInReceivedProperties(
			_ requiredReceivedProperties: [Scope.RequiredReceivedProperty],
			directParent: TypeDescription,
			receivedPropertyStack: [Property],
			declaredReceivedPropertyStack: [Property],
			property: Property,
			instantiationStack: [Property],
			lazilyInstantiatedDeclarations: [Property: Property],
		) throws {
			// Most scopes require no received property.
			guard !requiredReceivedProperties.isEmpty else { return }
			// The stacks of the innermost walk, which each walk extends while it walks a received property's scope.
			var receivedPropertyStack = receivedPropertyStack
			var declaredReceivedPropertyStack = declaredReceivedPropertyStack
			var stackPropertiesReliedOnByWalkedProperty = [Property: Set<Property>]()
			var walks = [ReceivedPropertyWalk(
				requiredReceivedProperties: requiredReceivedProperties,
				directParent: directParent,
				walkedProperty: nil,
				addedDeclaredReceivedProperty: false,
			)]
			/// Ends the innermost walk, handing what it relied on to the walk that walked its property.
			func finishInnermostWalk() {
				let finishedWalk = walks.removeLast()
				if let walkedProperty = finishedWalk.walkedProperty {
					receivedPropertyStack.removeLast()
					if finishedWalk.addedDeclaredReceivedProperty {
						declaredReceivedPropertyStack.removeLast()
					}
					let childStackPropertiesReliedOn = finishedWalk.stackPropertiesReliedOn.subtracting([walkedProperty])
					stackPropertiesReliedOnByWalkedProperty[walkedProperty] = childStackPropertiesReliedOn
					walks[walks.count - 1].stackPropertiesReliedOn.formUnion(childStackPropertiesReliedOn)
				}
			}
			while !walks.isEmpty {
				let walkIndex = walks.count - 1
				let nextIndex = walks[walkIndex].nextIndex
				guard nextIndex < walks[walkIndex].requiredReceivedProperties.count else {
					finishInnermostWalk()
					continue
				}
				let requiredReceivedProperty = walks[walkIndex].requiredReceivedProperties[nextIndex]
				walks[walkIndex].nextIndex += 1
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
					walks[walkIndex].stackPropertiesReliedOn.insert(childProperty)
					finishInnermostWalk()
					continue
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
						directParent: walks[walkIndex].directParent,
						closingReceive: CycleClosingReceive(aliasProperty: requiredReceivedProperty.aliasProperty),
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: requiredReceivedProperty.property,
							validatedPropertiesInCycle: propertiesInCycle,
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: declaredReceivedPropertyStack,
						),
					)
				} else if let memoizedStackPropertiesReliedOn, memoizedStackPropertiesReliedOn.isSubset(of: receivedPropertyStack) {
					walks[walkIndex].stackPropertiesReliedOn.formUnion(memoizedStackPropertiesReliedOn)
				} else if let receivedPropertyScope = typeDescriptionToScopeMap[childProperty.typeDescription] {
					// A cycle back to `childProperty` itself lies within its walk, wherever that walk starts.
					receivedPropertyStack.append(childProperty)
					// Only the lazily instantiated receives are named by the diagnostic.
					let addsDeclaredReceivedProperty = childProperty != requiredReceivedProperty.property
					if addsDeclaredReceivedProperty {
						declaredReceivedPropertyStack.append(requiredReceivedProperty.property)
					}
					walks.append(ReceivedPropertyWalk(
						requiredReceivedProperties: receivedPropertyScope.requiredReceivedProperties,
						directParent: receivedPropertyScope.instantiable.concreteInstantiable,
						walkedProperty: childProperty,
						addedDeclaredReceivedProperty: addsDeclaredReceivedProperty,
					))
				}
			}
		}
		/// The forms in which an alias's fulfilling property, as cycle validation sees it, can be on an instantiation
		/// stack: as itself, unwrapped, and – in a mock, which promotes a received optional property as the
		/// non-optional value it builds – as the optional property promoted to build it.
		func formsOnStack(of validatedFulfillingProperty: Property) -> [Property] {
			let unwrappedProperty = validatedFulfillingProperty.asUnwrappedProperty
			return if cyclesOnly {
				[validatedFulfillingProperty, unwrappedProperty, Property(label: unwrappedProperty.label, typeDescription: .optional(unwrappedProperty.typeDescription))]
			} else {
				[validatedFulfillingProperty, unwrappedProperty]
			}
		}
		/// The fulfilling properties of the `onlyIfAvailable` aliases already walked by
		/// `validateNoCycleInReceivedProperties`, each followed by its declaring scope's instantiation stack.
		var walkedAliasFulfillingProperties = Set<[Property]>()
		/// Validates the tree rooted at `rootScope`, scope by scope, depth first in the order each scope declares its
		/// children. It keeps its own stack of the scopes left to validate, since a tree can be as deep as the module
		/// has types.
		/// - Parameters:
		///   - validatesCycles: Whether to validate the tree for dependency cycles and unfulfillable received
		///     properties. `false` only for a tree validated for hidden received dependencies alone.
		///   - validatesHiddenProperties: Whether to record received dependencies a closer declaration hides.
		func validatePropertiesAreFulfillable(
			inTreeRootedAt rootScope: ValidatedRootScope,
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
		) throws {
			var scopesToValidate = [ScopeToValidate(
				scope: rootScope.scope,
				receivableProperties: Set(rootScope.scope.properties),
				receivableAliases: [:],
				closestDeclarationByLabel: [:],
				property: nil,
				propertyStack: [],
				lazilyInstantiatedDeclarations: [:],
			)]
			while let scopeToValidate = scopesToValidate.popLast() {
				try validatePropertiesAreFulfillable(
					on: scopeToValidate,
					boundProperties: rootScope.boundProperties,
					validatesCycles: validatesCycles,
					validatesHiddenProperties: validatesHiddenProperties,
					root: rootScope.scope.instantiable.concreteInstantiable,
					scopesToValidate: &scopesToValidate,
				)
			}
		}
		/// Validates one scope of a tree, and adds the children to validate after it to `scopesToValidate`, the first
		/// child last.
		/// - Parameters:
		///   - scopeToValidate: The scope, with what the scopes it is built inside give it.
		///   - boundProperties: The received properties the tree's mock binds. See `ValidatedRootScope`.
		///   - validatesCycles: See `validatePropertiesAreFulfillable(inTreeRootedAt:validatesCycles:validatesHiddenProperties:)`.
		///   - validatesHiddenProperties: See `validatePropertiesAreFulfillable(inTreeRootedAt:validatesCycles:validatesHiddenProperties:)`.
		///   - root: The type at the root of the tree.
		func validatePropertiesAreFulfillable(
			on scopeToValidate: ScopeToValidate,
			boundProperties: Set<Property>,
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
			root: TypeDescription,
			scopesToValidate: inout [ScopeToValidate],
		) throws {
			let scope = scopeToValidate.scope
			let receivableProperties = scopeToValidate.receivableProperties
			let receivableAliases = scopeToValidate.receivableAliases
			let closestDeclarationByLabel = scopeToValidate.closestDeclarationByLabel
			let property = scopeToValidate.property
			let propertyStack = scopeToValidate.propertyStack
			let lazilyInstantiatedDeclarations = scopeToValidate.lazilyInstantiatedDeclarations
			let instantiationStack: [Property] = if let property {
				[property] + propertyStack
			} else {
				[]
			}
			if validatesCycles, let property {
				try validateNoCycleInReceivedProperties(
					scope.requiredReceivedProperties,
					directParent: scope.instantiable.concreteInstantiable,
					receivedPropertyStack: [],
					declaredReceivedPropertyStack: [],
					property: property,
					instantiationStack: instantiationStack,
					lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
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
							|| formsOnStack(of: validatedFulfillingProperty).contains(where: instantiationStack.contains),
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
				if let fulfillingPropertyBeingBuilt = formsOnStack(of: validatedFulfillingProperty).first(where: instantiationStack.contains) {
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
				          case let walkedAliasFulfillingProperty = [fulfillingProperty] + alias.declaringInstantiationStack,
				          walkedAliasFulfillingProperties.insert(walkedAliasFulfillingProperty).inserted
				{
					// A required alias's fulfilling property is walked where the alias is declared. Walk this
					// one there too, since the receive requires it.
					do {
						do {
							try validateNoCycleInReceivedProperties(
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
					} catch {
						// The next tree that reaches this alias walks it again, and reports the same error, rather than
						// skipping it and validating what this tree did not reach because it stopped here.
						walkedAliasFulfillingProperties.remove(walkedAliasFulfillingProperty)
						throw error
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
			let firstChildIndex = scopesToValidate.endIndex
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
					scopesToValidate.append(ScopeToValidate(
						scope: childScope,
						receivableProperties: receivablePropertiesInChildTree,
						receivableAliases: childReceivableAliases,
						closestDeclarationByLabel: childClosestDeclarationByLabel,
						property: childProperty,
						propertyStack: childPropertyStack,
						lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
					))
				case .aliased:
					break
				}
			}
			// The scope validated next is the last one on the stack, so the first child goes last.
			scopesToValidate[firstChildIndex...].reverse()
		}

		// Each tree reports the first error it throws, and the errors of every tree are reported, rather than the
		// unfulfillable and hidden properties the walks record.
		var rootErrors = [DependencyTreeGeneratorError]()
		for rootScope in rootScopes {
			do {
				try validatePropertiesAreFulfillable(
					inTreeRootedAt: rootScope,
					validatesCycles: true,
					// A production root without a mock is validated for production; only mocks generate its tree here.
					validatesHiddenProperties: !cyclesOnly
						|| rootScope.scope.instantiable.generateMock
						|| additionalMockRootScopes.contains { $0.scope == rootScope.scope },
				)
			} catch let error as DependencyTreeGeneratorError {
				rootErrors.append(error)
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: rootErrors) {
			throw error
		}
		// Walking the other additional mock roots for cycles here could reject a mock that compiles today. Their
		// mocks are validated for cycles after promotion, in `createMockRootScopeGenerator`.
		for rootScope in additionalMockRootScopes where !rootScopes.contains(where: { $0.scope == rootScope.scope }) {
			try validatePropertiesAreFulfillable(
				inTreeRootedAt: rootScope,
				validatesCycles: false,
				validatesHiddenProperties: true,
			)
		}

		if !unfulfillableProperties.isEmpty {
			throw DependencyTreeGeneratorError.unfulfillableProperties(Array(unfulfillableProperties))
		}
		if !hiddenReceivedProperties.isEmpty {
			throw DependencyTreeGeneratorError.hiddenReceivedProperties(Array(hiddenReceivedProperties))
		}
	}

	/// Validates that no `@Sendable` builder function in the trees rooted at `roots` would capture an
	/// `Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated` declared outside it, none of which is
	/// `Sendable`. See `ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`.
	///
	/// A receiver that several roots, or several paths through one tree, reach is reported once for each chain, as
	/// an unfulfillable dependency is, rather than once with the chain of whichever root sorts first: which root a
	/// diagnostic names must not depend on the order of names.
	private func validateSendableBuildersCaptureNoNonSendableWrapper(
		inTreesRootedAt roots: [(instantiable: Instantiable, scopeGenerator: ScopeGenerator)],
	) async throws {
		// Walking the trees costs a pass over every scope, so only a module whose types name both a wrapper
		// that is not `Sendable` and a `Sendable` builder pays for it.
		let dependencies = typeDescriptionToFulfillingInstantiableMap.values.lazy.flatMap(\.dependencies)
		guard dependencies.contains(where: { !$0.property.propertyType.isConstant && !$0.property.propertyType.isSendable }),
		      dependencies.contains(where: \.property.propertyType.isSendable)
		else { return }
		// Two paths can reach one receiver through the same chain of types, so identical captures are reported once.
		var captures = Set<ScopeGenerator.NonSendableWrapperCapture>()
		for root in roots {
			await captures.formUnion(root.scopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt: root.instantiable))
		}
		if !captures.isEmpty {
			throw DependencyTreeGeneratorError.nonSendableWrapperCapturedBySendableBuilder(Array(captures))
		}
	}

	/// Validates that every reachable type description has a corresponding `@Instantiable` that production
	/// code can build, reporting every missing type, in source order. A `mockOnly` declaration exists solely
	/// for mock generation, so it does not count. Were it counted, a type it fulfills that shares a concrete
	/// type with a production declaration would be built from whichever declaration a set iteration reached first.
	private func validateReachableTypeDescriptions() throws {
		let unbuildableTypeDescriptions = reachableTypeDescriptions
			.filter { typeDescriptionToFulfillingInstantiableMap[$0]?.mockOnly != false }
		guard !unbuildableTypeDescriptions.isEmpty else { return }
		// The map's values can hold the same instantiable under several keys, so collect into sets.
		var referencingPropertiesByType = [TypeDescription: Set<DependencyTreeGeneratorError.LocatedProperty>]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			for dependency in instantiable.dependencies where dependency.isInstantiated && unbuildableTypeDescriptions.contains(dependency.asInstantiatedType) {
				referencingPropertiesByType[dependency.asInstantiatedType, default: []].insert(
					DependencyTreeGeneratorError.LocatedProperty(property: dependency.property, declarationLocation: dependency.declarationLocation),
				)
			}
		}
		throw DependencyTreeGeneratorError.independentErrors(unbuildableTypeDescriptions.map { unbuildableTypeDescription in
			DependencyTreeGeneratorError.noInstantiableFound(
				unbuildableTypeDescription,
				referencedBy: Array(referencingPropertiesByType[unbuildableTypeDescription, default: []]),
				fulfilledByMockOnlyDeclaration: typeDescriptionToFulfillingInstantiableMap[unbuildableTypeDescription] != nil,
			)
		})
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
	/// dependency cannot: it is an argument of the `Instantiator` that builds its type. Nor can an `onlyIfAvailable`
	/// receive or alias: generation passes it `nil` while the property it receives is still being built, whatever
	/// kind of property that is, as it does when the property is the non-optional form of the one received.
	fileprivate var canCloseDependencyCycle: Bool {
		switch source {
		case let .received(onlyIfAvailable),
		     let .aliased(_, _, onlyIfAvailable):
			!onlyIfAvailable
		case .instantiated:
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
