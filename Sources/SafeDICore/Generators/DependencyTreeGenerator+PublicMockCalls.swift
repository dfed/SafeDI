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

/// Plans of public mocks, each computed by a generator over the declarations of the module that generates the mock, as
/// that module computes it: each type's plan, `nil` when its module could not generate it, or the error computing it
/// threw. A value of the call that computes them, which keeps each plan once.
struct PublicMockPlans: Sendable {
	/// Whether the plan of `type`'s public mock was computed.
	func hasPlan(of type: TypeDescription) -> Bool {
		plansByType[type] != nil
	}

	/// The plan of `type`'s public mock, or `nil` when none was computed or its module could not generate it; throws what
	/// computing it threw.
	func plan(of type: TypeDescription) throws -> StoredPublicMockPlan? {
		try plansByType[type]?.get()
	}

	/// The place graph of the plan of `type`'s public mock, with the plan's places, or `nil` when the run holds no plan of
	/// it.
	func called(of type: TypeDescription) -> SeamSignature.Places.Called? {
		var called: SeamSignature.Places.Called?
		if case let .success(plan)? = plansByType[type] {
			called = plan.map { SeamSignature.Places.Called(places: $0.places, holes: $0.holes, caseIndexByHole: $0.caseIndexByHole) }
		}
		return called
	}

	mutating func add(plan: StoredPublicMockPlan?, of type: TypeDescription) {
		plansByType[type] = .success(plan)
	}

	mutating func add(error: any Error, of type: TypeDescription) {
		plansByType[type] = .failure(error)
	}

	/// Adds every plan of `plans`, which are of types no plan of this value is of.
	mutating func add(_ plans: PublicMockPlans) {
		plansByType.merge(plans.plansByType) { _, added in added }
	}

	private var plansByType = [TypeDescription: Result<StoredPublicMockPlan?, any Error>]()
}

extension DependencyTreeGenerator {
	/// The types the trees of the `.public` mocks of the module named `moduleName` build: each such type's tree, and the tree
	/// of each dependency it receives that its mock can build, every type on them included.
	static func typesReached(
		byPublicMocksOf moduleName: String?,
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
		receivedPropertiesCache: inout ReceivedPropertiesCache,
	) -> Set<TypeDescription> {
		var reached = Set<TypeDescription>()
		var visitedScopes = Set<ObjectIdentifier>()
		var scopesToVisit = [Scope]()
		for (type, scope) in typeDescriptionToScopeMap where scope.instantiable.concreteInstantiable == type && scope.instantiable.generateMock == .public && scope.instantiable.moduleName == moduleName {
			scopesToVisit.append(scope)
			let receivedProperties = collectReceivedProperties(from: scope, cache: &receivedPropertiesCache)
			for property in receivedProperties.received {
				guard let receivedScope = typeDescriptionToScopeMap[property.typeDescription.asInstantiatedType], mockCanBuild(property, from: receivedScope) else { continue }
				scopesToVisit.append(receivedScope)
			}
		}
		while let scope = scopesToVisit.popLast() {
			guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
			reached.insert(scope.instantiable.concreteInstantiable)
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
				scopesToVisit.append(childScope)
			}
		}
		return reached
	}

	/// The public mock another module generated for each type this module's mock trees reach but cannot build: a type
	/// declared with `generateMock: .public` in a module SafeDI knows, whose tree, as this module would build it inline
	/// – the public mocks of other types in it called, as they are wherever they cannot be built – constructs a
	/// declaration this module cannot reach. A tree this module can build is built inline, as before public mocks.
	/// - Parameter foreignPublicMockPlans: The plans of the public mocks of other modules the caller has computed, to which
	///   this adds the plans it computes: one call of each module's generator computes every plan that module is asked for.
	func publicMockCalls(
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
		foreignPublicMockPlans: inout PublicMockPlans,
	) async throws -> [TypeDescription: PublicMockCall] {
		guard !seams.foreignPublicMocks.isEmpty, let emittingModule = emittingModuleToCheck else { return [:] }
		let foreignPublicMockTypes = Set(seams.foreignPublicMocks.keys)
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let typesReachedByOwnPublicMocks = Self.typesReached(
			byPublicMocksOf: emittingModule.identity.moduleName,
			in: typeDescriptionToScopeMap,
			receivedPropertiesCache: &receivedPropertiesCache,
		)
		// The types whose trees construct a declaration this module cannot reach, in type order, each with the public mock
		// that is called instead.
		var calledTypes = [(type: TypeDescription, foreignPublicMock: SeamResolution.ForeignPublicMock)]()
		for type in foreignPublicMockTypes.sorted() {
			guard let foreignPublicMock = seams.foreignPublicMocks[type],
			      let scope = typeDescriptionToScopeMap[type],
			      scope.instantiable.concreteInstantiable == type
			else { continue }
			// What building the type inline constructs: its tree, with its hand-written mock where the mock would build it
			// with one (its own `customMockName` method, or a `mockOnly` mock this module sees), and the tree of each
			// dependency its tree requires that the mock would build beside it. Other modules' public mock types are left
			// out: each is built inline where it can be and called where it cannot.
			let typesLeftOut = foreignPublicMockTypes.subtracting([type])
			var constructions = Self.constructions(
				inTreeRootedAt: scope,
				rootIsConstructedWithMockMethod: scope.instantiable.mockInitializer != nil,
				rootReferenceLocation: nil,
				isMock: true,
				emittingModule: emittingModule,
				extendedTypes: extendedTypeDeclarations,
				leavingOut: typesLeftOut,
			)
			let receivedProperties = Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache)
			for property in receivedProperties.received.subtracting(receivedProperties.onlyIfAvailable).sorted() {
				guard let receivedScope = typeDescriptionToScopeMap[property.typeDescription.asInstantiatedType],
				      !foreignPublicMockTypes.contains(receivedScope.instantiable.concreteInstantiable),
				      Self.mockCanBuild(property, from: receivedScope)
				else { continue }
				constructions += Self.constructions(
					inTreeRootedAt: receivedScope,
					rootIsConstructedWithMockMethod: receivedScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType),
					rootReferenceLocation: nil,
					isMock: true,
					emittingModule: emittingModule,
					extendedTypes: extendedTypeDeclarations,
					leavingOut: typesLeftOut,
				)
			}
			// A type the module can build is still called where a `.public` mock of the module reaches it and its tree holds a
			// place its own module cannot fill: the `.public` mock takes the builder of that place's hole type as a struct with a
			// member for each place its calls hold, and none for a place it builds inline, so only a call honors the builder a
			// caller passes. Its values are those of the tree built inline.
			// Only where each such place's fill receives from the type's tree nothing that the tree declares – only what the
			// type's caller hands the tree: a fill that receives a value the tree declares could read one the call cannot hand
			// it – declared outside a `@Sendable` function that builds the place, say – where the tree built inline hands it
			// every value, so such a type stays built inline, and the `.public` mock fills the place itself, as it fills every
			// place it builds inline.
			// Nor where the declaring module generates the mock under a condition this module's mocks do not compile under,
			// which no call of the mock compiles in (`PublicMockCall.mockConditionsAgree`): the type stays built inline there too.
			let isCalledToHonorPublicMocksBuilders: Bool
			if typesReachedByOwnPublicMocks.contains(type), PublicMockCall.mockConditionsAgree(declaringModuleMockCondition: foreignPublicMock.declaringModuleMockCondition, callerModuleMockCondition: seams.currentModuleMockCondition) {
				// Resolved only for a type a `.public` mock reaches.
				let instantiables = try foreignPublicMock.visibleDeclarations().instantiables
				let receivedFromTheCaller = Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received
				var fillsAPlace = false
				var fillReceivesFromTheTree = false
				for construction in constructions where instantiables[construction.instantiable.concreteInstantiable] == nil {
					fillsAPlace = true
					if let fillScope = typeDescriptionToScopeMap[construction.instantiable.concreteInstantiable],
					   !Self.collectReceivedProperties(from: fillScope, cache: &receivedPropertiesCache).received.isSubset(of: receivedFromTheCaller)
					{
						fillReceivesFromTheTree = true
					}
				}
				isCalledToHonorPublicMocksBuilders = fillsAPlace && !fillReceivesFromTheTree
			} else {
				isCalledToHonorPublicMocksBuilders = false
			}
			guard isCalledToHonorPublicMocksBuilders || !Self.inaccessibleConstructions(constructions, from: emittingModule, extendedTypes: extendedTypeDeclarations).isEmpty else { continue }
			calledTypes.append((type, foreignPublicMock))
		}
		try await computePublicMockPlans(of: calledTypes, into: &foreignPublicMockPlans, modulesReadByRunOfModule: emittingModule.modulesReadByRunOfModule)
		var publicMockCalls = [TypeDescription: PublicMockCall]()
		// The plans a case of a place passed up through two public mocks is resolved in.
		let plansOfCalledMocks = foreignPublicMockPlans
		// The first type in type order whose plan its module cannot compute reports its error.
		for (type, foreignPublicMock) in calledTypes {
			guard let plan = try foreignPublicMockPlans.plan(of: type) else { continue }
			// The leaf's dependencies are declared where this run reads the mocked type's declaration.
			let declarationLocation = typeDescriptionToScopeMap[type]?.instantiable.declarationLocation
			let requirement = AccessLevel.required(toConstructFrom: emittingModule.identity, declaredIn: foreignPublicMock.declaringModule, isOwnFile: false)
			// The narrowest tier the module reaches: every module reaches the `public` one.
			let tier = plan.tiers.last { $0.satisfies(requirement) } ?? .public
			let tierParameters = plan.parameters(ofTier: tier)
			publicMockCalls[type] = PublicMockCall(
				type: type,
				tier: tier,
				passedParameters: tierParameters.compactMap { parameter in
					switch parameter.role {
					case let .forwarded(property):
						PublicMockCall.PassedParameter(name: parameter.name, type: parameter.type, dependency: Dependency(property: property, source: .forwarded, declarationLocation: declarationLocation), isBuiltWhenNil: false, builder: nil)
					case let .received(property, isRequired):
						// A required parameter the declaring module named apart from another of its label – a dependency it cannot
						// build – has no default to leave it to, so the leaf receives it under the parameter's name, which the
						// calling mock then takes it by.
						PublicMockCall.PassedParameter(
							name: parameter.name,
							type: parameter.type,
							dependency: Dependency(
								property: isRequired && parameter.name != property.label ? Property(label: parameter.name, typeDescription: property.typeDescription) : property,
								source: .received(onlyIfAvailable: !isRequired),
								declarationLocation: declarationLocation,
							),
							isBuiltWhenNil: parameter.isBuiltWhenNil,
							builtWrapper: parameter.builtWrapper,
							builder: parameter.builder,
						)
					case .constructionDefault, .overrides, .optionalBuilder:
						nil
					}
				},
				// Every parameter a narrower tier takes is a received dependency or a default-valued parameter: a narrower
				// required one keeps the public tier from being generated.
				omittedParameters: plan.parameters.filter { parameter in
					guard parameter.access < tier, case .received = parameter.role else { return false }
					return true
				} + plan.noTierParameters,
				takesOverrides: tierParameters.contains { parameter in
					if case .overrides = parameter.role {
						true
					} else {
						false
					}
				},
				guardTypeName: plan.guardTypeName,
				comment: foreignPublicMock.callComment,
				declaringModule: foreignPublicMock.declaringModule,
				callerModule: emittingModule.identity,
				requirement: requirement,
				declaringModuleMockCondition: foreignPublicMock.declaringModuleMockCondition,
				callerModuleMockCondition: seams.currentModuleMockCondition,
				receiversByLabel: plan.receiversByLabel,
				// A builder's `Builder` type, which a calling internal mock that passes its places up takes, is a function too.
				typesDeclaredEscaping: Set(plan.typesDeclaredEscaping).intersection(tierParameters.map(\.type)).union(tierParameters.compactMap { $0.builder?.readableParameterType.nameDeclaredEscaping }),
				calledBuilders: CalledBuilders(
					holes: plan.holes.map { $0.atTier(tier) },
					builders: plan.builders.map { $0.atTier(tier) },
					scopeEnums: plan.scopeEnums,
					places: plan.places,
					caseIndexByHole: plan.caseIndexByHole,
					placesOfSeamsBeneath: { plansOfCalledMocks.called(of: $0.seamType) },
				),
			)
		}
		return publicMockCalls
	}

	/// Computes the plan of the public mock each module of `calledTypes` generated for each of its types `plans` lacks,
	/// as that module computed it, from the declarations it sees: one call of a generator over each module's declarations
	/// builds that module's mock world once, for all of its types. A module SafeDI knows no name of has no plan.
	/// Under module info a module's file carries the plans its own run computed (`ForeignPublicMock.storedPlans`), as it
	/// carries a seam's signature (`computeForeignSeamRoots()`), and those are read rather than computed; the SwiftPM
	/// plugin's target graph reads no module info, so it computes.
	/// - Parameter modulesReadByRunOfModule: See `EmittingModule.init`.
	private func computePublicMockPlans(
		of calledTypes: [(type: TypeDescription, foreignPublicMock: SeamResolution.ForeignPublicMock)],
		into plans: inout PublicMockPlans,
		modulesReadByRunOfModule: (@Sendable (_ moduleName: String) -> TypeAccessProof.ModuleReach.ModulesRead)?,
	) async throws {
		// The module's generator is made from the public mock of the first of its types, in type order.
		var typesByModuleName = [String: (foreignPublicMock: SeamResolution.ForeignPublicMock, types: [TypeDescription])]()
		for (type, foreignPublicMock) in calledTypes where !plans.hasPlan(of: type) {
			guard let moduleName = foreignPublicMock.declaringModule.moduleName else { continue }
			typesByModuleName[moduleName, default: (foreignPublicMock, [])].types.append(type)
		}
		for (moduleName, calls) in typesByModuleName.sorted(by: { $0.key < $1.key }) {
			let foreignPublicMock = calls.foreignPublicMock
			// The plans the module's own run computed, which its module info carries, are read rather than computed again:
			// computing one builds the module's mock world, and each plan beneath it in turn. A plan depends on whether its
			// run compiles the mocks it generates, so a run that differs from the module's in that computes it.
			var storedPlansByType = [TypeDescription: StoredPublicMockPlan]()
			if let storedPlans = foreignPublicMock.storedPlans, storedPlans.compilesGeneratedMocks == compilesGeneratedMocks {
				storedPlansByType = try Dictionary(storedPlans.read().map { ($0.mockedType, $0) }) { first, _ in first }
			}
			for type in calls.types {
				guard let storedPlan = storedPlansByType[type] else { continue }
				plans.add(plan: storedPlan, of: type)
			}
			let typesToCompute = calls.types.filter { storedPlansByType[$0] == nil }
			guard !typesToCompute.isEmpty else { continue }
			// Resolved only for a module whose public mock a plan needs, once per module.
			let visible = try foreignPublicMock.visibleDeclarations()
			let generator = DependencyTreeGenerator(
				importStatements: [],
				mockImportStatements: [],
				typeDescriptionToFulfillingInstantiableMap: visible.instantiables,
				compilesGeneratedMocks: compilesGeneratedMocks,
				// The declaring module's files are not this run's own: its declarations record its name.
				emittingModule: EmittingModule(
					identity: foreignPublicMock.declaringModule,
					isOwnFile: { _ in false },
					isReadableFile: { _ in false },
					additionalMocksToGenerateLocation: nil,
					modulesReadByRunOfModule: modulesReadByRunOfModule,
				),
				// The public mocks of the modules the declaring module sees, which its mock trees call in turn.
				seams: SeamResolution(
					currentModule: foreignPublicMock.declaringModule,
					currentModuleMockCondition: foreignPublicMock.declaringModuleMockCondition,
					generatedSeams: [],
					foreignSeams: [:],
					// Read from that module's view of the modules it depends on, or, under the target graph, from every
					// module's.
					foreignPublicMocks: seams.foreignDeclarations(seenByModuleNamed: moduleName).publicMocks.filter { entry in
						entry.value.declaringModule.moduleName != moduleName && visible.instantiables[entry.key] != nil
					},
					// The views of every module, so that the plans this one computes in turn read what each of those modules
					// saw, never what this module's filter left: under module info a public mock two modules beneath this one
					// is not among the public mocks this module sees.
					foreignDeclarationsSeenByModule: seams.foreignDeclarationsSeenByModule,
				),
				plainTypeDeclarations: visible.plainTypeDeclarations,
			)
			// The generator computes for this run, or for the run this generator computes for in turn.
			let run = GenerationLayerObservation.runOfOtherModulesGenerator ?? GenerationLayerObservation.Run(moduleName: seams.currentModule.moduleName)
			let modulePlans = await GenerationLayerObservation.$runOfOtherModulesGenerator.withValue(run) {
				await generator.publicMockPlans(ofOwnTypes: typesToCompute)
			}
			plans.add(modulePlans)
		}
	}

	/// The finding that the modules calling the public mock of `instantiable` compute another signature for it, when
	/// the declarations they see differ from this run's (`SeamResolution.callersVisibleInstantiables`), as a seam's
	/// callers' view is checked: the mock is computed again over the callers' view, as they compute it, and a mock whose
	/// guard – which hashes what every call depends on – they compute otherwise is reported, naming
	/// a declaration they cannot see, in a seam's three tiers: the earliest by source location of those that declare a
	/// receiver of a parameter the callers would not take as such, else of those that fulfill such a parameter's type,
	/// else of those the mock's tree reaches. `nil` when the callers compute the same guard, or see every declaration
	/// the tree reaches.
	/// - Parameters:
	///   - publicMockContext: The context the module's public mocks share.
	///   - ownPlanScopes: The mock scopes the plans of the module's own public mocks are built from, once an earlier call
	///     built them, which this call builds when none did.
	///   - foreignPublicMockPlans: The plans of the public mocks of other modules the caller has computed.
	func callersViewFinding(
		of instantiable: Instantiable,
		publicMockContext: PublicMockContext,
		ownPlanScopes: inout MockScopes?,
		foreignPublicMockPlans: inout PublicMockPlans,
	) async throws -> PublicMockFinding? {
		guard let callersVisibleInstantiables = seams.callersVisibleInstantiables else { return nil }
		let type = instantiable.concreteInstantiable
		guard let ownPlan = try await publicMockPlan(ofOwnType: type, mockScopes: &ownPlanScopes, publicMockContext: publicMockContext, foreignPublicMockPlans: &foreignPublicMockPlans) else { return nil }
		let callersGenerator = DependencyTreeGenerator(
			importStatements: [],
			mockImportStatements: [],
			typeDescriptionToFulfillingInstantiableMap: callersVisibleInstantiables,
			compilesGeneratedMocks: compilesGeneratedMocks,
			emittingModule: emittingModule,
			seams: seams,
			plainTypeDeclarations: seams.callersVisiblePlainTypeDeclarations,
		)
		// A computation over the callers' view that fails reports its own error, as the callers' generation would.
		let callersPlan = try await callersGenerator.publicMockPlan(ofOwnType: type)
		guard callersPlan?.plan.guardTypeName != ownPlan.plan.guardTypeName else { return nil }
		struct ParameterShape: Hashable {
			let name: String
			let type: String
			let access: AccessLevel
			let defaultKind: PublicMockParameter.DefaultKind
			init(_ parameter: PublicMockParameter) {
				name = parameter.name
				type = parameter.type.withoutAny.asSource
				access = parameter.access
				defaultKind = parameter.defaultKind
			}
		}
		let callersShapes = Set((callersPlan?.plan.parameters ?? []).map(ParameterShape.init))
		let differingParameters = ownPlan.plan.parameters.filter { !callersShapes.contains(ParameterShape($0)) }
		let unseenTypes = Set(typeDescriptionToFulfillingInstantiableMap.values.map(\.concreteInstantiable))
			.subtracting(callersVisibleInstantiables.values.map(\.concreteInstantiable))
		func earliest(_ types: some Sequence<TypeDescription>) -> TypeDescription? {
			types
				.filter(unseenTypes.contains)
				.compactMap { typeDescriptionToFulfillingInstantiableMap[$0] }
				.min { Dependency.DeclarationLocation.precedesInSourceOrder($0.declarationLocation, $1.declarationLocation) }?
				.concreteInstantiable
		}
		let receivingTypes = differingParameters.flatMap { ownPlan.receiversByLabel[$0.name, default: []].map(\.declaringType) }
		let fulfillingTypes = differingParameters.compactMap { typeDescriptionToFulfillingInstantiableMap[$0.type.unwrapped.asInstantiatedType]?.concreteInstantiable }
		// A type the tree reaches is built as the declaration that fulfills it, which can be another type: a protocol's
		// fulfiller, which builds a place of this mock's tree or of a public mock it calls.
		let reachedTypes = Self.typesReachable(fromRoots: [type], in: typeDescriptionToFulfillingInstantiableMap)
			.compactMap { typeDescriptionToFulfillingInstantiableMap[$0]?.concreteInstantiable }
		return if let declaration = earliest(receivingTypes) ?? earliest(fulfillingTypes) ?? earliest(reachedTypes) {
			PublicMockFinding.callersCannotSee(declaration, of: instantiable)
		} else {
			// Without a plain declaration that proves a parameter, the callers count its type as one SafeDI reads no
			// declaration of.
			Self.earliestUnseenPlainDeclaration(provingAnyOf: differingParameters.map(\.accessCause)).map {
				PublicMockFinding.callersCannotSeePlainDeclaration($0, of: instantiable)
			}
		}
	}

	/// The plan of the public mock of each of `types`, declared with `generateMock: .public` among this generator's
	/// declarations, as its module computes it (`publicMockPlan(ofOwnType:mockScopes:publicMockContext:foreignPublicMockPlans:)`),
	/// each the plan or the error computing it threw. The mock world the plans are built from is built once, for all of
	/// them, as is the context they share; nothing outlives the call.
	func publicMockPlans(ofOwnTypes types: [TypeDescription]) async -> PublicMockPlans {
		var plans = PublicMockPlans()
		var mockScopes: MockScopes?
		let publicMockContext = makePublicMockContext(proof: ownAccessProof().proof)
		var foreignPublicMockPlans = PublicMockPlans()
		for type in types {
			do {
				let plan = try await publicMockPlan(ofOwnType: type, mockScopes: &mockScopes, publicMockContext: publicMockContext, foreignPublicMockPlans: &foreignPublicMockPlans)
				plans.add(plan: plan.map(StoredPublicMockPlan.init), of: type)
			} catch {
				plans.add(error: error, of: type)
			}
		}
		return plans
	}

	/// The plan of the public mock of `type`, declared with `generateMock: .public` among this generator's
	/// declarations, as its module computes it: the type's mock root is built as `generateMockCode` builds it. The
	/// module's own run reports what keeps its public mock from being generated.
	/// - Parameters:
	///   - builtMockScopes: The mock scopes the plans are built from, once an earlier call of the same caller built them;
	///     this call builds them when none did, and hands them back.
	///   - publicMockContext: The context the module's public mocks share.
	///   - foreignPublicMockPlans: The plans of the public mocks of other modules the caller has computed.
	func publicMockPlan(
		ofOwnType type: TypeDescription,
		mockScopes builtMockScopes: inout MockScopes?,
		publicMockContext: PublicMockContext,
		foreignPublicMockPlans: inout PublicMockPlans,
	) async throws -> OwnPublicMockPlan? {
		guard let declaredInstantiable = typeDescriptionToFulfillingInstantiableMap[type],
		      declaredInstantiable.generateMock == .public
		else { return nil }
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let mockScopes: MockScopes
		if let builtMockScopes {
			mockScopes = builtMockScopes
		} else {
			mockScopes = try await self.mockScopes(additionalMocksToGenerate: [], mockEmittingModule: emittingModuleToCheck, receivedPropertiesCache: &receivedPropertiesCache, foreignPublicMockPlans: &foreignPublicMockPlans)
			builtMockScopes = mockScopes
		}
		let rootMockScopes = mockScopes.forMockRoot(declaredInstantiable)
		guard let scope = rootMockScopes.typeDescriptionToScopeMap[declaredInstantiable.concreteInstantiable] else { return nil }
		let instantiable = mockRootInstantiable(for: declaredInstantiable, scope: scope)
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
		var promotedScopesValidatedForHiddenReceives = Set<ObjectIdentifier>()
		var scopesWithValidatedDeclarations = Set<ObjectIdentifier>()
		var constructionMemo = ConstructionMemo()
		let mockRoot = try await createMockRoot(
			for: instantiable,
			scope: scope,
			generatedMockReason: .generateMock,
			mockScopes: rootMockScopes,
			publicMockContext: publicMockContext,
			// The mock promotes what the declaring module can construct, as that module's own run decided it, so the plan
			// is of the mock that run generates. That run checked its constructions.
			emittingModule: emittingModuleToCheck,
			checksConstructions: false,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
			promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
			scopesWithValidatedDeclarations: &scopesWithValidatedDeclarations,
			constructionMemo: &constructionMemo,
		)
		return await Self.ownPublicMockPlan(of: instantiable, mockRoot: mockRoot, mockDefaults: mockScopes.flatParameterMockDefaults, publicMockContext: publicMockContext)
	}

	/// The whole plan of the public mock of one of this generator's own types, which the callers' view compares with the
	/// module's own: the plan of `publicMockPlans(ofOwnTypes:)` before it is reduced to what a calling module reads.
	private func publicMockPlan(ofOwnType type: TypeDescription) async throws -> OwnPublicMockPlan? {
		var mockScopes: MockScopes?
		var foreignPublicMockPlans = PublicMockPlans()
		return try await publicMockPlan(
			ofOwnType: type,
			mockScopes: &mockScopes,
			publicMockContext: makePublicMockContext(proof: ownAccessProof().proof),
			foreignPublicMockPlans: &foreignPublicMockPlans,
		)
	}

	/// The plan of the public mock of `instantiable`, whose mock root is `mockRoot`, as its module computes it for the
	/// modules that call the mock.
	static func ownPublicMockPlan(
		of instantiable: Instantiable,
		mockRoot: ScopeGenerator,
		mockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault],
		publicMockContext: PublicMockContext,
	) async -> OwnPublicMockPlan {
		let parameters = await mockRoot.mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults)
		return OwnPublicMockPlan(
			instantiable: instantiable,
			plan: ScopeGenerator.publicMockPlan(
				of: instantiable,
				parameters: parameters,
				parameterNames: ScopeGenerator.mockRootParameterNames(of: parameters),
				context: publicMockContext,
			),
			receiversByLabel: ScopeGenerator.receivers(in: parameters.treeNames.propertyNodes, mockedType: instantiable),
			typesDeclaredEscaping: parameters.typesDeclaredEscaping,
		)
	}

	/// The instantiable of the leaf scope through which a mock tree calls `publicMockCall`: `instantiable`, declaring
	/// the whole signature as its dependencies – the parameters of the tier the call reaches as the dependencies they
	/// stand for, and each parameter that tier omits as a receive only if available – and built by a mock method that
	/// takes the tier's parameters. One dependency per label: a required parameter the declaring module named apart is
	/// declared under its name (`publicMockCalls(in:)`), and a second form of a label that has a default is left to it.
	/// - Parameter takesBuildersFromOwnEnums: Whether the leaf is in a public mock's tree, which hands each place it does not
	///   fill up in a case of its own enums (`Scope.builderCallArguments`), so it receives no builder; an internal mock's
	///   receives each builder that reaches a place the call does not fill, which the mock takes as a parameter.
	static func publicMockLeafInstantiable(of instantiable: Instantiable, calling publicMockCall: PublicMockCall, takesBuildersFromOwnEnums: Bool) -> Instantiable {
		var dependencies = [Dependency]()
		var arguments = [Initializer.Argument]()
		var labels = Set<String>()
		let passedUpBuilderLabels = takesBuildersFromOwnEnums ? [] : Set(publicMockCall.passedUpBuilders.map(\.label))
		for parameter in publicMockCall.passedParameters where labels.insert(parameter.dependency.property.label).inserted {
			// A builder the call fills is passed its fill or dispatcher (`ScopeGenerator.BuilderCallArgument`), so the leaf
			// receives nothing for it.
			if parameter.builder.map({ passedUpBuilderLabels.contains($0.label) }) ?? true {
				dependencies.append(parameter.dependency)
			}
			arguments.append(Initializer.Argument(outerLabel: parameter.name, innerLabel: parameter.dependency.property.label, typeDescription: parameter.type))
		}
		for parameter in publicMockCall.omittedParameters {
			guard case let .received(property, _) = parameter.role, labels.insert(property.label).inserted else { continue }
			dependencies.append(Dependency(
				property: property.typeDescription.isOptional ? property : property.asOptionalProperty,
				source: .received(onlyIfAvailable: true),
				declarationLocation: instantiable.declarationLocation,
			))
		}
		var leaf = Instantiable(
			instantiableType: instantiable.concreteInstantiable,
			isRoot: false,
			initializer: instantiable.initializer,
			additionalInstantiables: Array(instantiable.instantiableTypes.dropFirst()),
			dependencies: dependencies,
			declarationType: instantiable.declarationType,
			access: instantiable.access,
			enclosingTypeAccess: instantiable.enclosingTypeAccess,
			enclosingExtensionAccess: instantiable.enclosingExtensionAccess,
			mockInitializer: Initializer(access: AccessDeclaration(level: publicMockCall.tier), arguments: arguments),
			mockReturnType: instantiable.concreteInstantiable,
			// The tiers are declared in an extension of the type in the declaring module's generated file.
			mockDeclarationAccess: AccessDeclaration(level: .internal, isExtension: true),
			mockDeclarationModuleName: publicMockCall.declaringModule.moduleName,
			mockDeclarationPackageName: publicMockCall.declaringModule.packageName,
			declarationLocation: instantiable.declarationLocation,
			moduleName: instantiable.moduleName,
			packageName: instantiable.packageName,
		)
		leaf.sourceFilePath = instantiable.sourceFilePath
		return leaf
	}

	/// An error for each declaration that keeps one of `constructions` from compiling in `emittingModule`.
	/// - Parameters:
	///   - extendedTypes: The declarations the module reads, among which the declaration of a type an extension
	///     extends bounds the types declared in or by that extension.
	///   - mockRoot: The type whose mock makes the constructions, which the error names, or `nil` for production
	///     code.
	static func inaccessibleConstructions(
		_ constructions: [Construction],
		from emittingModule: EmittingModule,
		extendedTypes: ExtendedTypeDeclarations,
		mockRoot: DependencyTreeGeneratorError.InaccessibleConstruction.MockRoot? = nil,
	) -> [DependencyTreeGeneratorError.InaccessibleConstruction] {
		var inaccessibleConstructions = [DependencyTreeGeneratorError.InaccessibleConstruction]()
		for construction in constructions {
			let instantiable = construction.instantiable
			let accessNeeds = construction.accessNeeds
			// Nearly every construction is of `public` declarations, which need nothing more.
			guard !accessNeeds.allSatisfy({ $0.level.satisfies(.public) }) else { continue }
			for accessNeed in accessNeeds {
				let declaringModule = emittingModule.declaringModule(of: accessNeed, constructing: instantiable)
				let requirement = emittingModule.requirement(of: accessNeed, constructing: instantiable)
				guard !accessNeed.level.satisfies(requirement) else { continue }
				inaccessibleConstructions.append(DependencyTreeGeneratorError.InaccessibleConstruction(
					constructedType: instantiable.concreteInstantiable,
					constructedTypeDeclaredName: instantiable.declaredName,
					accessNeed: accessNeed,
					requirement: requirement,
					emittingModule: emittingModule.identity,
					declaringModule: declaringModule,
					readableDeclarationLocation: accessNeed.access.declarationStartLocation.flatMap { declarationStartLocation in
						emittingModule.isReadableFile(declarationStartLocation.filePath) ? declarationStartLocation : nil
					},
					referenceLocation: construction.referenceLocation,
					constructedTypeDeclarationLocation: instantiable.declarationLocation,
					seamRemedy: construction.seamCandidateOnPaths.candidate.flatMap { candidate in
						Self.seamRemedy(offeredBy: candidate, toWiden: accessNeed, declaredIn: declaringModule, extendedTypes: extendedTypes)
					},
					inlineSeam: construction.inlineSeam,
					publicMockCandidate: construction.publicMockCandidate,
					mockRoot: mockRoot,
				))
			}
		}
		return inaccessibleConstructions
	}

	/// The comment on a production construction of `instantiable` when it is a seam that every tree of this run builds
	/// inline because SafeDI does not know which module declares it – one neither this module generates nor another
	/// module's run generated the initializer of (`SeamResolution.foreignSeams`) – so the initializer SafeDI generates
	/// for the seam is called only by hand-written code; `nil` otherwise. A mock builds every seam's tree inline whether
	/// or not SafeDI knows the seam's module, so the cause the comment gives would be wrong there, and a mock's
	/// constructions carry none.
	func builtInlineSeamComment(for instantiable: Instantiable) -> String? {
		Self.builtInlineSeamComment(for: instantiable, seams: seams)
	}

	/// See `builtInlineSeamComment(for:)`.
	static func builtInlineSeamComment(for instantiable: Instantiable, seams: SeamResolution) -> String? {
		guard instantiable.generatesDependencyTree,
		      seams.foreignSeams[instantiable.concreteInstantiable] == nil,
		      !seams.generatedSeams.contains(instantiable.concreteInstantiable)
		else { return nil }
		return "// Built inline: SafeDI does not know which module declares `\(instantiable.concreteInstantiable.asSource)`, so this tree cannot call the initializer SafeDI generates for it."
	}
}
