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

extension DependencyTreeGenerator {
	/// One type `requirements(of:)` is asked about.
	public struct RequirementsQuery: Sendable {
		public init(typeName: String, generatesMock: Bool, mockEmittingModule: EmittingModule?) {
			self.typeName = typeName
			self.generatesMock = generatesMock
			self.mockEmittingModule = mockEmittingModule
		}

		/// The name of the type.
		public let typeName: String
		/// Whether `mock()` is generated for the type, so that a hand-written method named `mock` is rejected as
		/// `generateMockCode` rejects it. Otherwise such a method is the type's mock, which the root is built with.
		public let generatesMock: Bool
		/// The module that generates the type's mock, whose access to each hand-written mock decides, as in that module's
		/// `generateMockCode`, which flat parameters of `mock()` default to one (`flatParameterMockDefaults(in:emittingModule:)`),
		/// or `nil` when no one module is known to generate it: every hand-written mock is then taken to be callable. No other
		/// access is checked.
		public let mockEmittingModule: EmittingModule?
	}

	/// What building each type `queries` names needs when every dependency it receives is provided beside it, in the
	/// order of `queries`: for each, `nil` when no declaration this generator knows has a concrete type of that name.
	/// Each type is built as the mock root `generateMockCode` builds for a type listed in `additionalMocksToGenerate`,
	/// from every declaration this generator knows, so over every declaration the result is what the type's mock needs
	/// (or would need, were it generated), and over the declarations with every hand-written mock removed it is what the
	/// type needs in production; see `TypeRequirements`. The type's tree is validated as `generateMockCode` validates a
	/// listed type's root, through the same `mockScopes` and `createMockRoot`, so the result is the error building that
	/// root throws. The passes `generateMockCode` runs over every mock root together once its loop is done – that no
	/// `@Sendable` builder captures a non-`Sendable` wrapper, and that each `SafeDIMockConfiguration` is built one way –
	/// gate emitting the module's mocks and change nothing in the report, so they are deliberately not run here: a module
	/// they reject has no generated mock for the report to disagree with, and `generate` reports them with their fix-its.
	///
	/// The mock scope map reads no type the query names, so it is built once, with the first type listed, and every
	/// later type is validated on its own (`validateListedMockRoot(named:mockScopes:receivedPropertiesCache:)`):
	/// once the first type's call succeeds, every tree but a later type's own has passed, so each type reports what a
	/// call that listed it alone reports. No type after the first that throws is built: each reports that type's error,
	/// since the caller reports that error and nothing after it.
	public func requirements(of queries: [RequirementsQuery]) async -> [Result<TypeRequirements?, any Error>] {
		var results = [Result<TypeRequirements?, any Error>]()
		// What every type's mock root is built from, once the first type's call has built it.
		// `defaultsReadEmittingModule` says whether its flat parameter defaults were decided by a module's access.
		var built: (mockScopes: MockScopes, receivedPropertiesCache: ReceivedPropertiesCache, defaultsReadEmittingModule: Bool)?
		for (index, query) in queries.enumerated() {
			do {
				let mockEmittingModule = constructsOnlyPublicDeclarations ? nil : query.mockEmittingModule
				var mockScopes: MockScopes
				var receivedPropertiesCache: ReceivedPropertiesCache
				if let built {
					(mockScopes, receivedPropertiesCache, _) = built
					try validateListedMockRoot(
						named: query.typeName,
						mockScopes: mockScopes,
						receivedPropertiesCache: &receivedPropertiesCache,
					)
					// Which flat parameters default is decided by the module that emits this type's mock.
					if mockEmittingModule != nil || built.defaultsReadEmittingModule {
						mockScopes.flatParameterMockDefaults = flatParameterMockDefaults(in: mockScopes.typeDescriptionToScopeMap, emittingModule: mockEmittingModule)
					}
				} else {
					receivedPropertiesCache = ReceivedPropertiesCache()
					// The plans of other modules' public mocks are needed only while the map is built.
					var foreignPublicMockPlans = PublicMockPlans()
					mockScopes = try await self.mockScopes(
						additionalMocksToGenerate: [query.typeName],
						mockEmittingModule: mockEmittingModule,
						receivedPropertiesCache: &receivedPropertiesCache,
						foreignPublicMockPlans: &foreignPublicMockPlans,
					)
				}
				let requirements = try await requirements(
					forTypeNamed: query.typeName,
					generatesMock: query.generatesMock,
					mockScopes: mockScopes,
					receivedPropertiesCache: &receivedPropertiesCache,
				)
				// Only complete results outlive a walk, so the cache serves every later type.
				built = (mockScopes, receivedPropertiesCache, mockEmittingModule != nil)
				results.append(.success(requirements))
			} catch {
				results += Array(repeating: .failure(error), count: queries.count - index)
				break
			}
		}
		return results
	}

	/// What building the type named `typeName` needs, built from `mockScopes`, which validated the type's tree; see
	/// `requirements(of:)`.
	private func requirements(
		forTypeNamed typeName: String,
		generatesMock: Bool,
		mockScopes: MockScopes,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
	) async throws -> TypeRequirements? {
		// The type's own entry in the scope map, which `generateMockCode` builds each mock root from. The name is
		// matched as `additionalMocksToGenerate` matches it, and the entry is chosen by type, never by map order.
		guard let (concreteType, scope) = mockScopes.typeDescriptionToScopeMap
			.filter({ $0.key == $0.value.instantiable.concreteInstantiable && $0.key.asSource == typeName })
			.min(by: { $0.key < $1.key })
		else { return nil }
		let instantiable = mockRootInstantiable(for: scope.instantiable, scope: scope)
		// The context a public mock's root reads, made only for one.
		let publicMockContext = instantiable.generateMock == .public ? makePublicMockContext(proof: ownAccessProof().proof) : nil
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
		var promotedScopesValidatedForHiddenReceives = Set<ObjectIdentifier>()
		var scopesWithValidatedDeclarations = Set<ObjectIdentifier>()
		var constructionMemo = ConstructionMemo()
		let mockRoot = try await createMockRoot(
			for: instantiable,
			scope: scope,
			// A type that sets `generateMock: true` fails to generate in its own module; any other generated mock
			// exists only because the type is listed, so removing it from the list is also a fix.
			generatedMockReason: generatesMock ? (instantiable.generatesMock ? .generateMock : .additionalMocksToGenerate) : nil,
			mockScopes: mockScopes,
			publicMockContext: publicMockContext,
			// The query reports what a type needs, not what keeps a module from compiling its mock, so it checks no
			// module's access here; `mockEmittingModule` decides only which flat parameters default.
			emittingModule: nil,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
			promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
			scopesWithValidatedDeclarations: &scopesWithValidatedDeclarations,
			constructionMemo: &constructionMemo,
		).generator
		// Whether a public mock can be generated is decided for one root and needs no emitting module, as
		// `generateMockCode` decides it, so the query reports it too.
		if generatesMock, let publicMockContext {
			let findings = await mockRoot.publicMockFindings(of: instantiable, context: publicMockContext, mockDefaults: mockScopes.flatParameterMockDefaults)
			guard findings.isEmpty else {
				throw DependencyTreeGeneratorError.publicMockCannotBeGenerated(findings)
			}
		}
		let parameters = await mockRoot.mockRootParameters(instantiable: instantiable, mockDefaults: mockScopes.flatParameterMockDefaults)
		let treeNodes = parameters.treeNames.propertyNodes
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
		// Each node before its children, depth first, as the tree's nodes are listed.
		for node in treeNodes {
			let nodeInstantiable = node.instantiable
			record(TypeRequirements.Declaration(typeDescription: nodeInstantiable.concreteInstantiable, sourceFilePath: nodeInstantiable.sourceFilePath, kind: .instantiable))
			if node.usesMockInitializer {
				record(TypeRequirements.Declaration(
					typeDescription: nodeInstantiable.concreteInstantiable,
					sourceFilePath: nodeInstantiable.mockDeclarationLocation?.filePath,
					kind: .handWrittenMock(methodName: nodeInstantiable.customMockName ?? InstantiableVisitor.mockMethodName),
				))
			}
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
		for node in treeNodes
			where node.parentIndex == nil && node.erasedToConcreteExistential && !rootInstantiatedProperties.contains(node.property)
		{
			let nodeConcreteType = node.instantiable.concreteInstantiable
			erasures.append(TypeRequirements.Erasure(
				property: node.property,
				concreteType: nodeConcreteType,
				declarations: erasureDeclarations(to: node.property)
					.filter { $0.concreteType == nodeConcreteType }
					.map(\.declaration)
					.sorted { ($0.declaringType, $0.property) < ($1.declaringType, $1.property) },
			))
		}

		// Flat parameters default as `generateMockRootCode` defaults them (`MockRootParameters`), and the mock calls the
		// hand-written mock each defaults to.
		func recordHandWrittenMock(of mockDefault: ScopeGenerator.FlatParameterMockDefault) {
			record(TypeRequirements.Declaration(
				typeDescription: mockDefault.concreteType,
				sourceFilePath: mockDefault.mockFilePath,
				kind: .handWrittenMock(methodName: mockDefault.methodName),
			))
		}
		var forwardedParameters = [TypeRequirements.ForwardedParameter]()
		for dependency in parameters.forwardedDependencies {
			let property = dependency.property
			let forwardedParameterDefault = parameters.forwardedParameterDefaults[property.label]
			if case let .handWrittenMock(mockDefault) = forwardedParameterDefault {
				recordHandWrittenMock(of: mockDefault)
			}
			forwardedParameters.append(TypeRequirements.ForwardedParameter(
				label: property.label,
				typeDescription: property.typeDescription,
				defaultExpression: forwardedParameterDefault?.expression,
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
			let mockDefault = parameters.flatReceivedParameterMockDefaults[property]
			if let mockDefault {
				recordHandWrittenMock(of: mockDefault)
			}
			requiredParameters.append(TypeRequirements.RequiredParameter(
				label: property.label,
				typeSource: property.typeDescription.asFunctionParameter.asSource,
				defaultExpression: mockDefault?.expression,
				reason: reason(forReceived: property),
			))
		}
		// A dependency instantiated only if available that nothing fulfills is none of these: a mock binds it from an override
		// that defaults to `nil`, the value production binds (`MockRootParameters.unavailableDependencyOverrideProperties`).
		for uncoveredParameter in parameters.flatUncoveredParameters {
			requiredParameters.append(TypeRequirements.RequiredParameter(
				label: uncoveredParameter.label,
				typeSource: uncoveredParameter.typeSource,
				defaultExpression: nil,
				reason: .noInstantiableFulfillsType(uncoveredParameter.instantiatedType),
			))
		}
		// The builders the internal mock of a type that generates its dependency tree takes in place of its places' parameters;
		// a builder it takes optional, for places its calls fill, is no requirement.
		for builder in parameters.seamMockBuilders where !builder.isOptional {
			requiredParameters.append(TypeRequirements.RequiredParameter(
				label: builder.label,
				typeSource: builder.parameterType.strippingEscaping.asSource,
				defaultExpression: nil,
				reason: .noInstantiableFulfillsType(builder.places.first?.instantiatedType ?? builder.family.holeType.instantiatedType),
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
}
