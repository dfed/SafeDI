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
	/// Generates mock code for all `@Instantiable` types.
	public func generateMockCode(
		mockConditionalCompilation: String?,
		currentModuleSourceFilePaths: Set<String>? = nil,
		additionalMocksToGenerate: Set<String> = [],
	) async throws -> MockGenerationResult {
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let mockScopes = try await mockScopes(
			additionalMocksToGenerate: additionalMocksToGenerate,
			mockEmittingModule: emittingModuleToCheck,
			receivedPropertiesCache: &receivedPropertiesCache,
		)
		let typeDescriptionToScopeMap = mockScopes.typeDescriptionToScopeMap
		let flatParameterMockDefaults = mockScopes.flatParameterMockDefaults

		// The public mocks of the module share one context, built only when the module declares one.
		let publicMockContext = typeDescriptionToFulfillingInstantiableMap.values.contains(where: { $0.generateMock == .public }) ? publicMockContext : nil

		// Create mock-root ScopeGenerators using the production Scope tree.
		var seen = Set<TypeDescription>()
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
		var promotedScopesValidatedForHiddenReceives = Set<ObjectIdentifier>()
		var scopesWithValidatedDeclarations = Set<ObjectIdentifier>()
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
			// A public mock's tree is built from the scopes with holes.
			let rootMockScopes = mockScopes.forMockRoot(instantiable)
			guard instantiable.generatesMock || isAdditionalMock,
			      seen.insert(instantiable.concreteInstantiable).inserted,
			      let scope = rootMockScopes.typeDescriptionToScopeMap[instantiable.concreteInstantiable]
			else { continue }
			let instantiable = mockRootInstantiable(for: instantiable, scope: scope)
			// Without module scoping, every type belongs to the current module.
			let isDeclaredInCurrentModule = currentModuleSourceFilePaths.map { currentModuleSourceFilePaths in
				instantiable.sourceFilePath.map(currentModuleSourceFilePaths.contains) ?? false
			} ?? true
			guard isAdditionalMock || isDeclaredInCurrentModule else { continue }

			// Each mock root reports the first error it finds, and the errors of every mock root are reported.
			do {
				let mockRoot = try await createMockRoot(
					for: instantiable,
					scope: scope,
					// A `generateMock: true` type declared in this module gets its mock whether
					// or not it is listed; any other type reaching here is generated only
					// because it is listed, so removing it from the list is also a fix.
					generatedMockReason: instantiable.generatesMock && isDeclaredInCurrentModule ? .generateMock : .additionalMocksToGenerate,
					mockScopes: rootMockScopes,
					emittingModule: emittingModuleToCheck,
					receivedPropertiesCache: &receivedPropertiesCache,
					childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
					promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
					scopesWithValidatedDeclarations: &scopesWithValidatedDeclarations,
				)
				if instantiable.generateMock == .public, let publicMockContext {
					var findings = await mockRoot.publicMockFindings(of: instantiable, context: publicMockContext, mockDefaults: flatParameterMockDefaults)
					if findings.isEmpty, let finding = try await callersViewFinding(of: instantiable) {
						findings.append(finding)
					}
					guard findings.isEmpty else {
						mockRootErrors.append(.publicMockCannotBeGenerated(findings))
						continue
					}
				}
				mockRoots.append((instantiable: instantiable, scopeGenerator: mockRoot))
			} catch let error as DependencyTreeGeneratorError {
				mockRootErrors.append(error)
			}
		}
		// A call of another module's public mock that would pass `nil` for a value the tree holds is rejected before any
		// code is generated, root by root in type order, and reported in source order, as is a hand-written method named
		// `mock` this module sees for such a type that its mocks reach, which would make every call ambiguous.
		if !seams.foreignPublicMocks.isEmpty {
			var reachedTypes = Set<TypeDescription>()
			for (_, mockRoot) in mockRoots {
				await reachedTypes.formUnion(mockRoot.concreteTypesOfTree())
			}
			for type in reachedTypes.intersection(seams.foreignPublicMocks.keys).sorted() {
				let handWrittenMockLocations = mockScopes.handWrittenMockLocationsByConcreteType[type, default: []]
				if !handWrittenMockLocations.isEmpty {
					mockRootErrors.append(.handWrittenMockSharesPublicMockName(type, declaringModuleName: seams.foreignPublicMocks[type]?.declaringModule.moduleName, declaredAt: Array(handWrittenMockLocations)))
				}
			}
			var callsUnderOtherMockCondition = [ScopeGenerator.PublicMockCallUnderOtherMockCondition]()
			var omissions = [ScopeGenerator.PublicMockTierOmission]()
			for (instantiable, mockRoot) in mockRoots {
				await callsUnderOtherMockCondition += mockRoot.publicMockCallsUnderOtherMockCondition(ofTreeRootedAt: instantiable)
				await omissions += mockRoot.publicMockTierOmissions(ofTreeRootedAt: instantiable)
			}
			if !callsUnderOtherMockCondition.isEmpty {
				mockRootErrors.append(.publicMockUnderOtherMockCondition(callsUnderOtherMockCondition))
			}
			if !omissions.isEmpty {
				mockRootErrors.append(.publicMockTierOmitsProvidedValue(omissions))
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: mockRootErrors) {
			throw error
		}
		// From here on, the module's mock roots are handled together. These passes gate emitting the module's
		// mocks and read nothing a single root's report needs, so
		// `requirements(forTypeNamed:generatesMock:mockEmittingModule:)` deliberately does not run them. A check that
		// decides whether one root can be generated belongs in `createMockRoot`, which that method and the loop above
		// share.

		// A mock fills another module's public mock's holes as a tree fills a seam's, and the public mock hands each hole's
		// builder the same scope values at every level of a cycle, as a seam does, so its fills are judged as
		// `generatePerRootCodeTrees` judges a seam's. The check judges each fill against the access the calling module
		// has, which `query needs` has no module to read, so the query does not run it.
		try Self.validateFills(
			inTreesRootedAt: mockRoots.map(\.scopeGenerator),
			callerModule: seams.currentModule,
		)
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
							flatParameterMockDefaults: flatParameterMockDefaults,
							cycleEdges: cycleEdges,
							handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
							sendableConfigurationTypeNames: sendableConfigurationTypeNames,
							publicMockContext: publicMockContext,
						)),
					)
					async let configurationTypes = mockRoot.collectConfigurationTypes()
					async let fulfillers = mockRoot.fulfillersOfMock(mockDefaults: flatParameterMockDefaults)
					return try await GeneratedMockRoot(
						root: GeneratedRoot(
							typeDescription: instantiable.concreteInstantiable,
							sourceFilePath: instantiable.sourceFilePath,
							code: code,
							fulfillers: fulfillers,
						),
						configurationTypes: configurationTypes,
						isPublicMock: instantiable.generateMock == .public,
					)
				}
			}
			var results = [GeneratedMockRoot]()
			for try await result in taskGroup {
				results.append(result)
			}
			return results
		}

		// The second whole-module gate, not run by `requirements(forTypeNamed:generatesMock:mockEmittingModule:)`; see
		// the note above `validateSendableBuildersCaptureNoNonSendableWrapper`.
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
		// The public mocks share one module-level configuration per type (`ScopeGenerator.publicConfigurationDeclarations`),
		// generated from the first public mock root that reaches the type, in type order, as the internal structs are.
		var seenPublicConfigurationTypes = Set<TypeDescription>()
		var publicConfigurationDeclarations = [String]()
		// The shared file extends each configured type, which the property it is built for need not name.
		var mockConfigurationFulfillers = Set<FulfillerImports.Fulfiller>()
		func recordFulfillers(configuredBy structNode: ScopeGenerator.MockParameterNode, inMockOf mockedType: TypeDescription) {
			if let instantiable = typeDescriptionToFulfillingInstantiableMap[structNode.concreteType] {
				mockConfigurationFulfillers.formUnion(FulfillerImports.Fulfiller.fulfillers(
					building: instantiable,
					forPropertyOfType: structNode.instantiatedTypeDescription,
					// The struct's parameters default to what the hand-written mock's do.
					callingHandWrittenMock: !handWrittenMockDefaultParameters[structNode.concreteType, default: []].isEmpty,
				))
			}
			// A mock listed in `additionalMocksToGenerate` extends a type of another module, whose other types its tree
			// configures, and no file of this module need import that module.
			if let fulfiller = typeDescriptionToFulfillingInstantiableMap[mockedType].flatMap(FulfillerImports.Fulfiller.init(instantiable:)) {
				mockConfigurationFulfillers.insert(fulfiller)
			}
		}
		for result in generatedRoots.sorted(by: { $0.root.typeDescription < $1.root.typeDescription }) where result.isPublicMock {
			guard let publicMockContext else { continue }
			for configurationType in result.configurationTypes where seenPublicConfigurationTypes.insert(configurationType.concreteType).inserted {
				guard let configurationTypeName = publicMockContext.configurationTypeNameByType[configurationType.concreteType] else { continue }
				let structNode = nodesReadingConfiguration[configurationType.concreteType].flatMap { nodeReadingConfiguration in
					nodeReadingConfiguration.configurationRequirements == configurationType.configurationRequirements ? nil : nodeReadingConfiguration
				} ?? configurationType
				publicConfigurationDeclarations.append(ScopeGenerator.publicConfigurationDeclarations(
					for: structNode,
					configurationTypeName: configurationTypeName,
					context: publicMockContext,
					cycleEdges: cycleEdges,
					requiresSendable: sendableConfigurationTypeNames.contains(configurationType.concreteType.asSource),
					handWrittenMockDefaultParameters: handWrittenMockDefaultParameters[configurationType.concreteType, default: []],
				))
				recordFulfillers(configuredBy: structNode, inMockOf: result.root.typeDescription)
			}
		}
		for result in generatedRoots.sorted(by: { $0.root.typeDescription < $1.root.typeDescription }) where !result.isPublicMock {
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
						recordFulfillers(configuredBy: structNode, inMockOf: result.root.typeDescription)
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
				fulfillers: result.root.fulfillers,
			)
		}

		let mockConfigurationCode: String? = if sharedConfigurationExtensions.isEmpty, publicConfigurationDeclarations.isEmpty {
			nil
		} else {
			generateMockConfigurationCode(
				configurationExtensions: sharedConfigurationExtensions,
				publicConfigurationDeclarations: publicConfigurationDeclarations,
				mockConditionalCompilation: mockConditionalCompilation,
			)
		}

		return MockGenerationResult(
			generatedRoots: mergedGeneratedRoots,
			mockConfigurationCode: mockConfigurationCode,
			mockConfigurationFulfillers: mockConfigurationFulfillers,
		)
	}

	/// The context every public mock of the module shares: one proof of every type's access over the module's
	/// declarations, the module of each type, and the names of the module-level configurations.
	/// `makePublicMockContext()`, made once.
	var publicMockContext: PublicMockContext {
		if let memoizedPublicMockContext {
			return memoizedPublicMockContext
		}
		let context = makePublicMockContext()
		memoizedPublicMockContext = context
		return context
	}

	/// The comment the `public` declarations this module generates carry, naming the types they name that it reads no
	/// declaration of, or `nil` when the run writes none (`SeamResolution.carriesUnreadTypeComment`). Over the
	/// declarations the module's own seams and public mocks are computed from, as `publicMockContext` reads them.
	var unreadTypeComment: UnreadTypeComment? {
		publicMockContext.unreadTypeComment
	}

	/// Which declarations a mention in each module of a view can name, the view being `viewer`'s, over `instantiables` and
	/// `plainTypeDeclarations`; every one when the run is not told what each module reads, or knows no viewer.
	static func moduleReach(
		viewedFrom viewer: ModuleIdentity?,
		instantiables: [TypeDescription: Instantiable],
		plainTypeDeclarations: [PlainTypeDeclaration],
		modulesReadByRunOfModule: (@Sendable (_ moduleName: String) -> TypeAccessProof.ModuleReach.ModulesRead)?,
	) -> TypeAccessProof.ModuleReach {
		guard let viewer, let modulesReadByRunOfModule else { return .unknown }
		return TypeAccessProof.ModuleReach(viewer: viewer, instantiables: instantiables.values, plainTypeDeclarations: plainTypeDeclarations, modulesReadByRunOfModule: modulesReadByRunOfModule)
	}

	private func makePublicMockContext() -> PublicMockContext {
		var moduleNameByType = [TypeDescription: String]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			if let moduleName = instantiable.moduleName {
				moduleNameByType[instantiable.concreteInstantiable] = moduleName
			}
		}
		let moduleName = emittingModule?.identity.moduleName
		let proof = TypeAccessProof(
			instantiables: typeDescriptionToFulfillingInstantiableMap,
			plainTypeDeclarations: plainTypeDeclarations,
			isOwnFile: emittingModule?.isOwnFile,
			reach: Self.moduleReach(viewedFrom: emittingModule?.identity, instantiables: typeDescriptionToFulfillingInstantiableMap, plainTypeDeclarations: plainTypeDeclarations, modulesReadByRunOfModule: emittingModule?.modulesReadByRunOfModule),
		)
		return PublicMockContext(
			proof: proof,
			unreadTypeComment: seams.carriesUnreadTypeComment ? UnreadTypeComment(proof: proof, mentioningModule: .generatedCode(ofModuleNamed: moduleName, isRunsOwnModule: true)) : nil,
			moduleNameByType: moduleNameByType,
			moduleName: moduleName,
			configurationTypeNameByType: PublicMockContext.configurationTypeNames(
				of: typeDescriptionToFulfillingInstantiableMap.values.map(\.concreteInstantiable),
				moduleName: moduleName,
			),
			extendedTypeAccessNeedsByType: typeDescriptionToFulfillingInstantiableMap.values.reduce(into: [TypeDescription: [AccessNeed]]()) { needsByType, instantiable in
				guard instantiable.generateMock == .public else { return }
				let needs = Self.extendedTypeAccessNeeds(of: instantiable, in: extendedTypeDeclarations)
				if !needs.isEmpty {
					needsByType[instantiable.concreteInstantiable] = needs
				}
			},
		)
	}

	/// What every mock root is built from: the scope of each type a mock can build, and what completes a mock
	/// root's tree.
	struct MockScopes {
		/// These scopes, with the tree of a public mock built from `publicMockTypeDescriptionToScopeMap`.
		func forMockRoot(_ instantiable: Instantiable) -> MockScopes {
			guard instantiable.generateMock == .public, let publicMockTypeDescriptionToScopeMap else { return self }
			var mockScopes = self
			mockScopes.typeDescriptionToScopeMap = publicMockTypeDescriptionToScopeMap
			return mockScopes
		}

		/// The `@Instantiated(erasedToConcreteExistential: true)` properties that erase a concrete type to each
		/// type, in any module, keyed by the property's type and, for a lazily instantiated property, by the
		/// type of its instance.
		let erasureDeclarations: [TypeDescription: Set<ErasureDeclaration>]
		/// The concrete type a mock builds an erased type from: the one concrete type `erasureDeclarations`
		/// erase to it.
		let erasedToConcreteTypeMap: [TypeDescription: TypeDescription]
		var typeDescriptionToScopeMap: [TypeDescription: Scope]
		/// The scopes a public mock's tree is built from: `typeDescriptionToScopeMap`'s, but with a hole wherever an
		/// `@Instantiated` property's type has no declaration (`createMockTypeDescriptionToScopeMapping`). `nil` when the
		/// module declares no public mock.
		var publicMockTypeDescriptionToScopeMap: [TypeDescription: Scope]?
		/// The hand-written mock a flat parameter of `mock()` of each type defaults to
		/// (`flatParameterMockDefaults(in:emittingModule:)`).
		let flatParameterMockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault]
		/// Where each concrete type's hand-written methods named `mock` are declared.
		let handWrittenMockLocationsByConcreteType: [TypeDescription: Set<Dependency.DeclarationLocation?>]
	}

	/// An `@Instantiated(erasedToConcreteExistential: true)` property, with the concrete type it erases.
	struct ErasureDeclaration: Hashable {
		let concreteType: TypeDescription
		let declaration: TypeRequirements.Erasure.Declaration
	}

	/// Builds the mock scope map and validates it, and collects what every mock root is built with.
	/// - Parameters:
	///   - additionalMocksToGenerate: The names of the types whose mocks are generated because they are listed.
	///   - mockEmittingModule: The module the mocks compile in, whose access to each hand-written mock decides which
	///     flat parameters default to one, or `nil` when no access needs checking (`emittingModuleToCheck`).
	func mockScopes(
		additionalMocksToGenerate: Set<String>,
		mockEmittingModule: EmittingModule?,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
	) async throws -> MockScopes {
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
		// promotes received dependencies as instantiated children. A type another module generates a public mock for,
		// whose tree this module cannot build, is a leaf that calls that mock, so the map is built again with those.
		var typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping(publicMockCalls: [:])
		var publicMockCalls = try await publicMockCalls(in: typeDescriptionToScopeMap)
		let generatesPublicMock = typeDescriptionToFulfillingInstantiableMap.values.contains(where: { $0.generateMock == .public })
		// A public mock's tree takes a builder for what a fill instantiates that nothing fulfills, where an internal mock's
		// fill would read a value nothing binds, so the trees of each kind of mock fill their own places.
		var publicMockCallsOfPublicMocks = publicMockCalls
		if !publicMockCalls.isEmpty {
			typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping(publicMockCalls: publicMockCalls)
			// A call that fills a builder declares no dependency for it, so the map is built again with the fills.
			if generatesPublicMock {
				for (calledType, filled) in holesFilled(byCallsOf: publicMockCalls, in: typeDescriptionToScopeMap, unfulfilledInstantiationsAreHoles: true) {
					publicMockCallsOfPublicMocks[calledType]?.filledHoles = filled.holes
					publicMockCallsOfPublicMocks[calledType]?.sitesPassedUpOnSomeRoute = filled.sitesPassedUpOnSomeRoute
				}
			}
			let filledHoles = holesFilled(byCallsOf: publicMockCalls, in: typeDescriptionToScopeMap, unfulfilledInstantiationsAreHoles: false)
			if !filledHoles.isEmpty {
				for (calledType, filled) in filledHoles {
					publicMockCalls[calledType]?.filledHoles = filled.holes
					publicMockCalls[calledType]?.sitesPassedUpOnSomeRoute = filled.sitesPassedUpOnSomeRoute
				}
				typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping(publicMockCalls: publicMockCalls)
			}
		}

		// The scopes of the types the mock-root loop below generates a mock for because they are listed.
		let additionalMockRootScopes: Set<Scope> = additionalMocksToGenerate.isEmpty ? [] : Set(
			typeDescriptionToFulfillingInstantiableMap.values.compactMap { instantiable in
				additionalMocksToGenerate.contains(instantiable.concreteInstantiable.asSource)
					? typeDescriptionToScopeMap[instantiable.concreteInstantiable]
					: nil
			},
		)
		// The renames of the declarations the walk below reads are checked before it reads them, as production checks the
		// renames of its trees before it builds scopes. Each mock root's tree, promoted dependencies included, is checked
		// again where the root is created.
		try Self.validateRenamesAreSpelledAsTheMacroAccepts(
			inTreesRootedAt: validatedRootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] }
				+ typeDescriptionToScopeMap.values.filter(\.instantiable.generatesMock)
				+ Array(additionalMockRootScopes),
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
		)
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
			additionalMockRootScopes: additionalMockRootScopes,
			receivedPropertiesCache: &receivedPropertiesCache,
			cyclesOnly: true,
		)

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
			publicMockTypeDescriptionToScopeMap: generatesPublicMock
				? createMockTypeDescriptionToScopeMapping(publicMockCalls: publicMockCallsOfPublicMocks, buildsHoles: true)
				: nil,
			flatParameterMockDefaults: flatParameterMockDefaults(in: typeDescriptionToScopeMap, emittingModule: mockEmittingModule),
			handWrittenMockLocationsByConcreteType: handWrittenMockLocationsByConcreteType,
		)
	}

	/// The hand-written mock a flat parameter of `mock()` – a `@Forwarded` property of the mocked type, or a received
	/// dependency the mock cannot build – defaults to, by the parameter's type: the one a mock tree builds a property of
	/// the type with, the scope map's hand-written mock for the type (the type's own, or a `mockOnly` declaration's that
	/// holds the slot), when it takes no required argument and `emittingModule` can call it, which is the check of every
	/// construction of a mock (`inaccessibleConstructions`), asked rather than reported. Another module's public mock that
	/// a tree calls in place of building the type is not hand-written, so no parameter defaults to it.
	/// - Parameters:
	///   - typeDescriptionToScopeMap: The mock scope map.
	///   - emittingModule: The module the mock compiles in, or `nil` when no construction needs checking.
	func flatParameterMockDefaults(in typeDescriptionToScopeMap: [TypeDescription: Scope], emittingModule: EmittingModule?) -> [TypeDescription: ScopeGenerator.FlatParameterMockDefault] {
		var flatParameterMockDefaults = [TypeDescription: ScopeGenerator.FlatParameterMockDefault]()
		// Each type's default is decided by its own scope, so the order of the map decides nothing.
		for (type, scope) in typeDescriptionToScopeMap {
			let instantiable = scope.instantiable
			guard scope.publicMockCall == nil,
			      let mockInitializer = instantiable.mockInitializer,
			      mockInitializer.arguments.allSatisfy(\.hasDefaultValue),
			      instantiable.mockReturnTypeIsCompatible(withPropertyType: type),
			      canConstructWithMockMethod(instantiable, from: emittingModule)
			else { continue }
			flatParameterMockDefaults[type] = ScopeGenerator.FlatParameterMockDefault(
				concreteType: instantiable.concreteInstantiable,
				methodName: instantiable.customMockName ?? InstantiableVisitor.mockMethodName,
				mockFilePath: instantiable.mockDeclarationLocation?.filePath,
				fulfillers: FulfillerImports.Fulfiller
					.fulfillers(building: instantiable, forPropertyOfType: type, callingHandWrittenMock: true)
					.filter { $0.moduleName != emittingModule?.identity.moduleName },
			)
		}
		return flatParameterMockDefaults
	}

	/// Whether `emittingModule` can construct `instantiable` with its hand-written mock method, as
	/// `inaccessibleConstructions` judges every construction: always, when no construction needs checking.
	private func canConstructWithMockMethod(_ instantiable: Instantiable, from emittingModule: EmittingModule?) -> Bool {
		guard let emittingModule else { return true }
		return Self.inaccessibleConstructions(
			[Construction(instantiable: instantiable, usesMockMethod: true, referenceLocation: nil, isSeamLeaf: false, extendedTypes: extendedTypeDeclarations)],
			from: emittingModule,
			extendedTypes: extendedTypeDeclarations,
		).isEmpty
	}

	/// The instantiable a mock root is built from: the entry of `scope`'s concrete type, declaring only the
	/// dependencies the scope builds.
	func mockRootInstantiable(for instantiable: Instantiable, scope: Scope) -> Instantiable {
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
	enum GeneratedMockReason {
		/// The type sets `generateMock: true`.
		case generateMock
		/// A `#SafeDIConfiguration` lists the type in `additionalMocksToGenerate`.
		case additionalMocksToGenerate
	}

	/// The mock root of `instantiable`, the instantiable `mockRootInstantiable(for:scope:)` returned for `scope`,
	/// once the type is known to be one a mock can be generated for. Every check that decides whether one mock
	/// root can be generated belongs here, so that `generateMockCode` and
	/// `requirements(forTypeNamed:generatesMock:mockEmittingModule:)` run the same ones; a pass that needs every mock
	/// root at once goes after `generateMockCode`'s loop instead.
	/// - Parameters:
	///   - generatedMockReason: Why the project generates `mock()` for the type, or `nil` when it does not, so that a
	///     hand-written method named `mock` is the type's mock rather than a collision.
	///   - emittingModule: The module the mock's code compiles in, whose access to each type the mock constructs is
	///     checked, or `nil` when no module emits the mock: `requirements(forTypeNamed:generatesMock:mockEmittingModule:)`
	///     reports what a type needs, not what keeps one module from compiling its mock, so it checks no access. This is
	///     the one check of a single mock root that the two callers do not share; the access that decides which flat
	///     parameters default is asked of `mockScopes` instead, by both.
	///   - promotedScopesValidatedForHiddenReceives: See `createMockRootScopeGenerator`.
	///   - scopesWithValidatedDeclarations: See `createMockRootScopeGenerator`.
	func createMockRoot(
		for instantiable: Instantiable,
		scope: Scope,
		generatedMockReason: GeneratedMockReason?,
		mockScopes: MockScopes,
		emittingModule: EmittingModule?,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
		childrenRequiringEachOtherValidation: inout ChildrenRequiringEachOtherValidation,
		promotedScopesValidatedForHiddenReceives: inout Set<ObjectIdentifier>,
		scopesWithValidatedDeclarations: inout Set<ObjectIdentifier>,
	) async throws -> ScopeGenerator {
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
		// Validate the scope a mock builds each dependency with (`mockScope(instantiating:as:in:)`).
		for dependency in scope.instantiable.dependencies {
			guard case .instantiated = dependency.source else { continue }
			let childScope = Self.mockScope(
				instantiating: dependency.property,
				as: dependency.asInstantiatedType,
				in: mockScopes.typeDescriptionToScopeMap,
			)
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

		return try await createMockRootScopeGenerator(
			for: instantiable,
			scope: scope,
			typeDescriptionToScopeMap: mockScopes.typeDescriptionToScopeMap,
			flatParameterMockDefaults: mockScopes.flatParameterMockDefaults,
			erasedToConcreteTypeMap: mockScopes.erasedToConcreteTypeMap,
			emittingModule: emittingModule,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
			promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
			scopesWithValidatedDeclarations: &scopesWithValidatedDeclarations,
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
		/// Whether the root's mock is public, whose tree reads module-level configurations rather than the types' own.
		let isPublicMock: Bool
	}

	/// A type's `SafeDIMockConfiguration` struct, emitted in an extension of the type.
	private struct ConfigurationExtension {
		let typeName: String
		let structCode: String
	}

	private func generateMockConfigurationCode(
		configurationExtensions: [ConfigurationExtension],
		publicConfigurationDeclarations: [String] = [],
		mockConditionalCompilation: String?,
	) -> String {
		let extensions = configurationExtensions.map { configurationExtension in
			"extension \(configurationExtension.typeName) {\n\(configurationExtension.structCode)\n}"
		}
		let body = (extensions + publicConfigurationDeclarations).joined(separator: "\n\n")
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
			adjacency[key]?.sort { $0.asSource < $1.asSource }
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

	/// Builds a scope mapping for mock generation. Similar to `createTypeDescriptionToScopeMapping`
	/// but includes ALL types (not just reachable from roots). Received dependencies are NOT
	/// promoted here — they're promoted at the root level in `createMockRootScopeGenerator`.
	///
	/// A type that a mock builds by calling its hand-written mock is built from what that method is passed.
	/// The dependencies it is not passed are left out of the mock tree: nothing reads them, so a mock that
	/// built one would declare a value it never uses. One of them is still built when a dependency the method
	/// is passed receives it, which is known only once the scopes exist, so the scopes are built again until
	/// no type's tree receives a dependency the type left out.
	/// - Parameter publicMockCalls: The types whose public mock, which another module generated, the map's mock trees
	///   call, each a leaf scope (see `Scope.publicMockCall`).
	///   - buildsHoles: Whether an `@Instantiated` property no declaration fulfills is a hole (`Scope.PropertyToGenerate.hole`),
	///     a site a public mock's builder builds, rather than left out for `mock()` to take as a parameter.
	private func createMockTypeDescriptionToScopeMapping(publicMockCalls: [TypeDescription: PublicMockCall], buildsHoles: Bool = false) -> [TypeDescription: Scope] {
		var dependenciesBuiltForOtherDependencies = [TypeDescription: Set<Dependency>]()
		var typeDescriptionToScopeMap: [TypeDescription: Scope]
		var foundDependencyToBuild: Bool
		repeat {
			typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping(
				dependenciesBuiltForOtherDependencies: dependenciesBuiltForOtherDependencies,
				publicMockCalls: publicMockCalls,
				buildsHoles: buildsHoles,
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
		publicMockCalls: [TypeDescription: PublicMockCall],
		buildsHoles: Bool,
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
						let lhsHasMock = lhs.generatesMock || lhsHasHandWrittenMock
						let rhsHasMock = rhs.generatesMock || rhsHasHandWrittenMock
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
				let scope = visitedConcreteTypeToScope[instantiable.concreteInstantiable] ?? publicMockCalls[instantiable.concreteInstantiable].map { publicMockCall in
					let leafInstantiable = Self.publicMockLeafInstantiable(of: instantiable, calling: publicMockCall, takesBuildersFromOwnEnums: buildsHoles)
					return Scope(instantiable: leafInstantiable, publicMockCall: publicMockCall)
				} ?? Scope(instantiable: instantiable)
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
			// A leaf that calls a public mock declares the mock's whole signature, which the call passes in part.
			guard scope.publicMockCall == nil,
			      let mockInitializer = instantiable.mockInitializer,
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
				case let .instantiated(_, erasedToConcreteExistential):
					if let instantiatedScope = Self.mockScope(
						instantiating: dependency.property,
						as: dependency.asInstantiatedType,
						in: typeDescriptionToScopeMap,
					) {
						scope.propertiesToGenerate.append(.instantiated(
							dependency.property,
							instantiatedScope,
							erasedToConcreteExistential: erasedToConcreteExistential,
						))
					} else if buildsHoles, Self.canBeHole(dependency) {
						// No declaration the module sees fulfills the type, fake included: a public mock takes a builder for
						// it, which this site calls with the values in scope here.
						scope.propertiesToGenerate.append(.hole(
							dependency.property,
							erasedToConcreteExistential: erasedToConcreteExistential,
							declarationLocation: dependency.declarationLocation,
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
			// A leaf fills each place it can with a function that builds the place's property as the type that fulfills it,
			// and passes every other place up.
			if let publicMockCall = scope.publicMockCall {
				let filledSites = Set(publicMockCall.filledHoles.map(\.site))
				scope.holeArguments = publicMockCall.holes.map { hole in
					if filledSites.contains(hole.site), let fulfillingScope = Self.fulfillingMockScope(of: hole, in: typeDescriptionToScopeMap) {
						.fill(hole, fulfillingScope)
					} else {
						.passUp(hole)
					}
				}
			}
		}
		// What each fill reads, once every scope's tree is complete: a fill's parameters take the forms it reads.
		var receivedPropertiesCache = ReceivedPropertiesCache()
		for scope in Set(typeDescriptionToScopeMap.values) where scope.publicMockCall != nil {
			for case let .fill(hole, fulfillingScope) in scope.holeArguments {
				scope.fillReceivedProperties[hole.site] = Self.collectReceivedProperties(from: fulfillingScope, cache: &receivedPropertiesCache).received
			}
		}
		return typeDescriptionToScopeMap
	}

	/// The scope a mock builds `hole`'s property with, in `typeDescriptionToScopeMap`, a mock scope map: the one the mock's
	/// tree built inline would build it with (`mockScope(instantiating:as:in:)`), so a hand-written mock, or a `mockOnly`
	/// fake that alone fulfills the hole, builds it. `nil` when no declaration the module sees fulfills the hole.
	private static func fulfillingMockScope(of hole: SeamSignature.Hole, in typeDescriptionToScopeMap: [TypeDescription: Scope]) -> Scope? {
		mockScope(instantiating: hole.property, as: hole.instantiatedType, in: typeDescriptionToScopeMap)
	}

	/// The scope in `typeDescriptionToScopeMap`, a mock scope map, that a mock builds the `@Instantiated` `property` with.
	///
	/// A property whose declaration names another type with `fulfilledByType:` is built as the type it names, as
	/// production builds it, not as another type that fulfills the property's type – unless the property's type's entry
	/// is a `mockOnly` declaration of another type, such as a fake of a protocol, which replaces whatever builds the
	/// protocol in production. A `mockOnly` extension of a type that also has a production declaration is merged into
	/// that declaration (`resolveSafeDIFulfilledTypes`), so it is that type's mock, and it is not used for a property the
	/// app builds as the named type. The property's type's entry also stands when the named type itself holds it, since
	/// that entry is built with the type's hand-written mock when the mock returns the property's type (a type whose mock
	/// returns one of its additional types). A `mockOnly` declaration of the named type is found under the named type,
	/// where it merges or replaces. When the module sees no declaration of the named type, which a module that inverts
	/// the dependency cannot, the property's type's entry stands, so the mock still builds the property rather than
	/// taking it as a parameter; with no such entry either, there is no scope: the mock takes the property as a
	/// parameter, or a public mock a builder.
	/// - Parameters:
	///   - property: The property, as its owner declares it.
	///   - instantiatedType: The type the property is built as: the dependency's `asInstantiatedType`, which is the type
	///     `fulfilledByType:` names, or the property's own instantiated type.
	///   - typeDescriptionToScopeMap: A mock scope map.
	private static func mockScope(
		instantiating property: Property,
		as instantiatedType: TypeDescription,
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
	) -> Scope? {
		let propertyInstantiatedType = property.typeDescription.asInstantiatedType
		let propertyTypeScope = typeDescriptionToScopeMap[propertyInstantiatedType]
		guard instantiatedType != propertyInstantiatedType else {
			return propertyTypeScope
		}
		if let propertyTypeScope,
		   propertyTypeScope.instantiable.mockOnly || propertyTypeScope.instantiable.concreteInstantiable == instantiatedType
		{
			return propertyTypeScope
		} else {
			return typeDescriptionToScopeMap[instantiatedType] ?? propertyTypeScope
		}
	}

	/// The places of the calls in `publicMockCalls` that this module fills, by called type, decided over
	/// `typeDescriptionToScopeMap`, in which every call passes every builder up. A module fills a place when a declaration
	/// it sees fulfills it, as the mock's tree built inline would build it (`fulfillingMockScope(of:in:)`: a hand-written
	/// mock or a `mockOnly` fake included), and the fill builds that tree as the inline mock would – every construction
	/// in it one this module can reach, hand-written mock methods included – from the values the place's scope struct
	/// carries and the builders of the public mocks it calls whose every place is filled. Starting from every such place,
	/// a place whose fill would read anything else is dropped, until none is: a fill never passes a place up. Every other
	/// place is passed up: the calling mock takes it, through a case of its own enum or as a parameter its caller passes.
	/// A place inside a fill of an inner seam's builder that some routes of the inner seam's enum lead to with a value its
	/// fill reads and others without is filled and passed up both (`InnerScopeReaders.passesUpOnSomeInnerRoute`).
	/// - Parameter unfulfilledInstantiationsAreHoles: Whether the fills are a public mock's, whose tree is built with holes,
	///   so a type a fill's tree instantiates that no declaration the module sees fulfills is a place of the mock's own. An
	///   internal mock's fill would read a value nothing binds there, so it does not fill the place.
	private func holesFilled(
		byCallsOf publicMockCalls: [TypeDescription: PublicMockCall],
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
		unfulfilledInstantiationsAreHoles: Bool,
	) -> [TypeDescription: (holes: [SeamSignature.Hole], sitesPassedUpOnSomeRoute: Set<SeamSignature.Hole.Site>)] {
		guard let emittingModule = emittingModuleToCheck else { return [:] }
		struct Candidate {
			let calledType: TypeDescription
			let hole: SeamSignature.Hole
			/// What the fill's tree receives that the scope struct does not carry.
			let receivedBesideFields: Set<Property>
			/// Whether a route of an inner seam's enum leads to the place without a value the fill reads.
			let passesUpOnSomeRoute: Bool
		}
		var receivedPropertiesCache = ReceivedPropertiesCache()
		var candidates = [Candidate]()
		for calledType in publicMockCalls.keys.sorted() {
			guard let publicMockCall = publicMockCalls[calledType] else { continue }
			let readers = InnerScopeReaders(enumsByKey: publicMockCall.calledBuilders.enumsByKey, nameByKey: [:])
			for hole in publicMockCall.holes {
				guard let fulfillingScope = Self.fulfillingMockScope(of: hole, in: typeDescriptionToScopeMap),
				      Self.inaccessibleConstructions(
				      	Self.constructions(
				      		inTreeRootedAt: fulfillingScope,
				      		rootIsConstructedWithMockMethod: fulfillingScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: hole.property.typeDescription.asInstantiatedType),
				      		rootReferenceLocation: nil,
				      		isMock: true,
				      		emittingModule: emittingModule,
				      		extendedTypes: extendedTypeDeclarations,
				      		leavingOut: Set(publicMockCalls.keys),
				      	),
				      	from: emittingModule,
				      	extendedTypes: extendedTypeDeclarations,
				      ).isEmpty,
				      unfulfilledInstantiationsAreHoles || !Self.instantiatesWhatNothingFulfills(inTreeRootedAt: fulfillingScope)
				else { continue }
				// A field is read by value, only if available, and as a lazily instantiated property's instance too.
				var fieldForms = Set<Property>()
				for field in hole.fields {
					for form in [field.property] + [field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding].compactMap(\.self) {
						fieldForms.insert(form)
						fieldForms.insert(form.asOptionalProperty)
					}
				}
				let received = Self.collectReceivedProperties(from: fulfillingScope, cache: &receivedPropertiesCache).received
				// The root enum the place's route starts at: of the seam whose enums hold it, its hole type's, of its family.
				let rootKey = SeamSignature.ScopeEnum.Key(seamType: hole.scopeSeamType, holeType: hole.holeType, isSendable: hole.enumPlace?.isBuiltBySendableBuilder ?? false)
				candidates.append(Candidate(
					calledType: calledType,
					hole: hole,
					receivedBesideFields: received.subtracting(fieldForms),
					passesUpOnSomeRoute: readers.passesUpOnSomeInnerRoute(hole, reading: received, from: rootKey),
				))
			}
		}
		// A fill may call a public mock whose every place another fill fills, its own included, which the call passes its
		// fills and dispatchers: each builder of that mock is then received by nothing.
		var filled = candidates
		while true {
			var filledBuilders = Set<Property>()
			for (calledType, calledCandidates) in Dictionary(grouping: filled, by: \.calledType) {
				guard var publicMockCall = publicMockCalls[calledType] else { continue }
				publicMockCall.filledHoles = calledCandidates.map(\.hole)
				publicMockCall.sitesPassedUpOnSomeRoute = Set(calledCandidates.filter(\.passesUpOnSomeRoute).map(\.hole.site))
				let passedUpLabels = Set(publicMockCall.passedUpBuilders.map(\.label))
				for parameter in publicMockCall.passedParameters {
					if let builder = parameter.builder, !passedUpLabels.contains(builder.label) {
						filledBuilders.insert(parameter.dependency.property)
					}
				}
			}
			let kept = filled.filter { $0.receivedBesideFields.isSubset(of: filledBuilders) }
			guard kept.count < filled.count else { break }
			filled = kept
		}
		return Dictionary(grouping: filled, by: \.calledType).mapValues { calledCandidates in
			(calledCandidates.map(\.hole), Set(calledCandidates.filter(\.passesUpOnSomeRoute).map(\.hole.site)))
		}
	}

	/// Whether a scope of the mock tree rooted at `scope`, in a map built without holes, instantiates a property no scope
	/// builds: one no declaration the module sees fulfills, which the inline mock takes as a parameter.
	private static func instantiatesWhatNothingFulfills(inTreeRootedAt scope: Scope) -> Bool {
		var visitedScopes = Set<ObjectIdentifier>()
		// A stack of its own, since a tree can be as deep as the module has types.
		var scopesToVisit = [scope]
		while let visitedScope = scopesToVisit.popLast() {
			guard visitedScopes.insert(ObjectIdentifier(visitedScope)).inserted else { continue }
			var builtProperties = Set<Property>()
			for case let .instantiated(property, childScope, _) in visitedScope.propertiesToGenerate {
				builtProperties.insert(property)
				scopesToVisit.append(childScope)
			}
			for dependency in visitedScope.instantiable.dependencies where dependency.isInstantiated && !builtProperties.contains(dependency.property) {
				return true
			}
		}
		return false
	}
}
