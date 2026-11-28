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
	/// Generates mock code for all `@Instantiable` types. A mock keeps its local functions inlinable, where a seam’s tree
	/// does not (`LocalFunctionInlining`).
	/// - Parameter publicMockContext: The context the module's public mocks share (`makePublicMockContext()`), or `nil`
	///   when the module declares no public mock.
	func generateMockCode(
		mockConditionalCompilation: String?,
		currentModuleSourceFilePaths: Set<String>?,
		additionalMocksToGenerate: Set<String>,
		storesPublicMockPlans: Bool,
		publicMockContext: PublicMockContext?,
	) async throws -> MockGenerationResult {
		// The tree names comparison reads the same roots (`MockTreeNamesObservation`).
		guard NodeRecordsObservation.observer != nil || MockTreeNamesObservation.observer != nil else {
			return try await generateMockCode(
				mockConditionalCompilation: mockConditionalCompilation,
				currentModuleSourceFilePaths: currentModuleSourceFilePaths,
				additionalMocksToGenerate: additionalMocksToGenerate,
				storesPublicMockPlans: storesPublicMockPlans,
				publicMockContext: publicMockContext,
				worldRootRecording: nil,
				pinsRecording: nil,
			)
		}
		// The root of each mock root's world, by mocked type, where a test observes node records: handed on through a task
		// local, so that a run no test observes threads nothing through the mock roots' construction.
		let worldRootRecording = AsyncStream.makeStream(of: (mockedType: TypeDescription, worldRoot: ConstructionScope).self)
		// The mocked types whose mocks pass `nil` to a receive a required one pins, which the tree names comparison refuses.
		let pinsRecording = AsyncStream.makeStream(of: TypeDescription.self)
		return try await NodeRecordsObservation.$recordsMockWorldRoot.withValue({ worldRootRecording.continuation.yield(($0, $1)) }) {
			try await MockTreeNamesObservation.$recordsMockRootPassingNilToPinnedReceives.withValue({ pinsRecording.continuation.yield($0) }) {
				try await generateMockCode(
					mockConditionalCompilation: mockConditionalCompilation,
					currentModuleSourceFilePaths: currentModuleSourceFilePaths,
					additionalMocksToGenerate: additionalMocksToGenerate,
					storesPublicMockPlans: storesPublicMockPlans,
					publicMockContext: publicMockContext,
					worldRootRecording: worldRootRecording,
					pinsRecording: pinsRecording,
				)
			}
		}
	}

	/// - Parameter worldRootRecording: Where the root of each mock root's world arrives, by mocked type, where a test
	///   observes node records.
	/// - Parameter pinsRecording: Where each mocked type arrives whose mock passes `nil` to a receive a required one pins,
	///   where a test observes node records.
	private func generateMockCode(
		mockConditionalCompilation: String?,
		currentModuleSourceFilePaths: Set<String>?,
		additionalMocksToGenerate: Set<String>,
		storesPublicMockPlans: Bool,
		publicMockContext: PublicMockContext?,
		worldRootRecording: (stream: AsyncStream<(mockedType: TypeDescription, worldRoot: ConstructionScope)>, continuation: AsyncStream<(mockedType: TypeDescription, worldRoot: ConstructionScope)>.Continuation)?,
		pinsRecording: (stream: AsyncStream<TypeDescription>, continuation: AsyncStream<TypeDescription>.Continuation)?,
	) async throws -> MockGenerationResult {
		var receivedPropertiesCache = ReceivedPropertiesCache()
		// The plans of the public mocks of other modules this module's mock trees call, computed once each.
		var foreignPublicMockPlans = PublicMockPlans()
		let mockScopes = try await mockScopes(
			additionalMocksToGenerate: additionalMocksToGenerate,
			mockEmittingModule: emittingModuleToCheck,
			receivedPropertiesCache: &receivedPropertiesCache,
			foreignPublicMockPlans: &foreignPublicMockPlans,
		)
		let typeDescriptionToScopeMap = mockScopes.typeDescriptionToScopeMap
		let flatParameterMockDefaults = mockScopes.flatParameterMockDefaults
		// The mock scopes the plans of the module's own public mocks are built from, as each module that calls one computes
		// it, once built (`publicMockPlan(ofOwnType:mockScopes:publicMockContext:foreignPublicMockPlans:)`).
		var ownPublicMockPlanScopes: MockScopes?

		// Create mock-root ScopeGenerators using the production Scope tree.
		var seen = Set<TypeDescription>()
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
		var promotedScopesValidatedForHiddenReceives = Set<ObjectIdentifier>()
		var scopesWithValidatedDeclarations = Set<ObjectIdentifier>()
		var mockRoots = [(instantiable: Instantiable, scopeGenerator: ScopeGenerator)]()
		// The public mocks the module's own files declare, whose plans its module info carries.
		var ownPublicMockTypes = Set<TypeDescription>()
		// One memo for the mock roots, shared between them as `sharingBetweenMockRoots` says.
		var constructionMemo = ConstructionMemo(sharing: ConstructionMemo.sharingBetweenMockRoots)
		var mockRootErrors = [DependencyTreeGeneratorError]()
		// Skip types where generateMock is not enabled (unless explicitly listed
		// in additionalMocksToGenerate), duplicates, and types not in the scope map.
		// Types from dependent modules are skipped unless they appear in
		// additionalMocksToGenerate. When generateMock is true and a hand-written
		// mock exists, the generated mock calls through to the hand-written one
		// (which must have a different name specified by customMockName).
		var mockRootCandidates = typeDescriptionToFulfillingInstantiableMap.values
			.sorted(by: { $0.concreteInstantiable < $1.concreteInstantiable })
			.filter { instantiable in
				(instantiable.generatesMock || additionalMocksToGenerate.contains(instantiable.concreteInstantiable.asSource))
					&& seen.insert(instantiable.concreteInstantiable).inserted
			}
		// The memo oracle builds the mock roots in reverse order too; `mockRoots` is put back in type order below.
		if ConstructionMemoOracle.buildsMockRootsInReverseOrder {
			mockRootCandidates.reverse()
		}
		for instantiable in mockRootCandidates {
			let isAdditionalMock = additionalMocksToGenerate.contains(instantiable.concreteInstantiable.asSource)
			// A public mock's tree is built from the scopes with holes.
			let rootMockScopes = mockScopes.forMockRoot(instantiable)
			guard let scope = rootMockScopes.typeDescriptionToScopeMap[instantiable.concreteInstantiable] else { continue }
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
					publicMockContext: publicMockContext,
					emittingModule: emittingModuleToCheck,
					receivedPropertiesCache: &receivedPropertiesCache,
					childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
					promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
					scopesWithValidatedDeclarations: &scopesWithValidatedDeclarations,
					constructionMemo: &constructionMemo,
				)
				if instantiable.generateMock == .public, let publicMockContext {
					var findings = await mockRoot.publicMockFindings(of: instantiable, context: publicMockContext, mockDefaults: flatParameterMockDefaults)
					if findings.isEmpty, let finding = try await callersViewFinding(
						of: instantiable,
						publicMockContext: publicMockContext,
						ownPlanScopes: &ownPublicMockPlanScopes,
						foreignPublicMockPlans: &foreignPublicMockPlans,
					) {
						findings.append(finding)
					}
					guard findings.isEmpty else {
						mockRootErrors.append(.publicMockCannotBeGenerated(findings))
						continue
					}
					if isDeclaredInCurrentModule {
						ownPublicMockTypes.insert(instantiable.concreteInstantiable)
					}
				}
				mockRoots.append((instantiable: instantiable, scopeGenerator: mockRoot))
			} catch let error as DependencyTreeGeneratorError {
				mockRootErrors.append(error)
			}
		}
		if ConstructionMemoOracle.buildsMockRootsInReverseOrder {
			mockRoots.reverse()
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
		// `requirements(of:)` deliberately does not run them. A check that
		// decides whether one root can be generated belongs in `createMockRoot`, which that method and the loop above
		// share.

		// A mock fills another module's public mock's holes as a tree fills a seam's, and the public mock hands each hole's
		// builder the same scope values at every level of a cycle, as a seam does, so its fills are judged as
		// `generatedCode(of:)` judges a seam's. The check judges each fill against the access the calling module
		// has, which `query needs` has no module to read, so the query does not run it.
		try Self.validateFills(
			inTreesRootedAt: mockRoots.map(\.scopeGenerator),
			callerModule: seams.currentModule,
			compilesGeneratedMocks: compilesGeneratedMocks,
		)
		try await validateSendableBuildersCaptureNoNonSendableWrapper(inTreesRootedAt: mockRoots)

		// Compute the global cycle edges across all mock-reachable types. Per-tree
		// cycle detection (`isPropertyCycle`) breaks at a different edge depending
		// on which root is being walked — fine for breaking infinite tree descent
		// but not for `SafeDIMockConfiguration` struct shape, which must agree
		// across every root's view of a given type. The SCC-derived feedback arc
		// set guarantees the same back-edges are filtered everywhere.
		let cycleEdges = Self.computeCycleEdges(in: typeDescriptionToScopeMap)

		// A type with a hand-written mock configures every property with the defaults the mock declares, whether
		// the property is built with the mock or with `init`: the struct is shared, so it cannot hold both. A
		// property built with `init` beneath a cycle edge, which no override reaches, passes the struct's default
		// for each of them too.
		// The mock's arguments are matched to the dependencies of the entry under the concrete type, which a
		// `mockOnly` declaration's mock is merged into, so a dependency's argument never counts as a default.
		let handWrittenMockDefaultParameters = typeDescriptionToFulfillingInstantiableMap.values
			.reduce(into: [TypeDescription: [ScopeGenerator.DefaultParameter]]()) { result, instantiable in
				guard let mockInitializer = instantiable.mockInitializer else { return }
				result[instantiable.concreteInstantiable] = ScopeGenerator.DefaultParameter.defaultParameters(
					of: mockInitializer,
					dependencies: (typeDescriptionToFulfillingInstantiableMap[instantiable.concreteInstantiable] ?? instantiable).dependencies,
				)
			}

		// Each root is lowered in one task, at most `BoundedConcurrency.mockRootWidth` roots at once, from its finished
		// generator tree (`ScopeGenerator.lowerMockRoot(context:)`), which records the configurations its tree reads.
		//
		// The sendable configuration types are unioned across every root before any root is lowered: a struct is shared
		// across every root that references the type, so the annotation has to agree, and each root's lowering reads the
		// union. They are read from the generator trees.
		let sendableConfigurationTypeNames = try await BoundedConcurrency.map(mockRoots, width: BoundedConcurrency.mockRootWidth) { instantiableAndMockRoot, _ in
			let (instantiable, mockRoot) = instantiableAndMockRoot
			return mockRoot.sendableConfigurationTypeNames(ofMockRootOf: instantiable)
		}.reduce(into: Set<String>()) { union, names in
			union.formUnion(names)
		}
		let mockDeclarationLocations = mockDeclarationLocationsOfTypesWithHandWrittenMocks()

		let foreignPublicMocks = seams.foreignPublicMocks
		let mockContext = ScopeGenerator.MockContext(
			mockConditionalCompilation: mockConditionalCompilation,
			flatParameterMockDefaults: flatParameterMockDefaults,
			cycleEdges: cycleEdges,
			handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
			sendableConfigurationTypeNames: sendableConfigurationTypeNames,
			publicMockContext: publicMockContext,
			foreignPublicMocks: foreignPublicMocks,
		)
		let fulfillingInstantiables = typeDescriptionToFulfillingInstantiableMap
		var recordedWorldRoots = [TypeDescription: ConstructionScope]()
		if let worldRootRecording {
			worldRootRecording.continuation.finish()
			for await (mockedType, worldRoot) in worldRootRecording.stream {
				recordedWorldRoots[mockedType] = worldRoot
			}
		}
		let worldRoots = recordedWorldRoots
		var recordedTypesPassingNilToPinnedReceives = Set<TypeDescription>()
		if let pinsRecording {
			pinsRecording.continuation.finish()
			for await mockedType in pinsRecording.stream {
				recordedTypesPassingNilToPinnedReceives.insert(mockedType)
			}
		}
		let typesPassingNilToPinnedReceives = recordedTypesPassingNilToPinnedReceives
		let loweredRoots = try await BoundedConcurrency.map(mockRoots, width: BoundedConcurrency.mockRootWidth) { instantiableAndMockRoot, _ in
			let (instantiable, mockRoot) = instantiableAndMockRoot
			async let fulfillers = mockRoot.fulfillersOfMock(mockDefaults: flatParameterMockDefaults)
			let lowered = try await mockRoot.lowerMockRoot(context: mockContext, worldRoot: worldRoots[instantiable.concreteInstantiable], passesNilToPinnedReceives: typesPassingNilToPinnedReceives.contains(instantiable.concreteInstantiable))
			return await (
				root: GeneratedRoot(
					typeDescription: instantiable.concreteInstantiable,
					sourceFilePath: instantiable.sourceFilePath,
					code: "",
					fulfillers: fulfillers,
				),
				lowered: MockLowering.LoweredRoot(
					mockedType: instantiable.concreteInstantiable,
					lowered: lowered,
					emittedMergedCode: "",
					mockedTypeFulfiller: fulfillingInstantiables[instantiable.concreteInstantiable].flatMap(FulfillerImports.Fulfiller.init(instantiable:)),
				),
			)
		}

		// The second whole-module gate, not run by `requirements(of:)`: a type whose constructions read its configuration
		// two ways is rejected, read from the records of every root's lowering. It runs after the roots are lowered, so
		// that an error lowering a root is reported first.
		let conflicts = MockLowering.configurationsBuiltTwoWays(
			of: loweredRoots.map { (mockedType: $0.lowered.mockedType, lowered: $0.lowered.lowered) },
			mockDeclarationLocations: mockDeclarationLocations,
		)
		if !conflicts.isEmpty {
			throw DependencyTreeGeneratorError.configurationBuiltTwoWays(conflicts)
		}

		let (mergedCodes, mockConfigurationCode, mockConfigurationFulfillers) = MockLowering.configurationCode(
			of: loweredRoots.map(\.lowered),
			mockConditionalCompilation: mockConditionalCompilation,
			sendableConfigurationTypeNames: sendableConfigurationTypeNames,
			publicMockContext: publicMockContext,
		)
		let generatedRoots = zip(loweredRoots.map(\.root), mergedCodes).map { root, code in
			GeneratedRoot(typeDescription: root.typeDescription, sourceFilePath: root.sourceFilePath, code: code, fulfillers: root.fulfillers)
		}

		// The plan of each of the module's own public mocks, as a module that calls the mock reads it, made from the mock
		// root this run built once every check has passed, so that no module above builds the mock's tree to compute it
		// (`computePublicMockPlans(of:into:modulesReadByRunOfModule:)`).
		var storedPublicMockPlans = [StoredPublicMockPlan]()
		if storesPublicMockPlans, let publicMockContext {
			for (instantiable, mockRoot) in mockRoots where ownPublicMockTypes.contains(instantiable.concreteInstantiable) {
				await storedPublicMockPlans.append(StoredPublicMockPlan(Self.ownPublicMockPlan(of: instantiable, mockRoot: mockRoot, mockDefaults: flatParameterMockDefaults, publicMockContext: publicMockContext)))
			}
		}

		// Freeing the mock roots' trees keeps a core busy for a while on a large module, and nothing generated waits for it.
		Self.releaseInBackground(mockRoots.map(\.scopeGenerator))
		mockRoots = []
		return MockGenerationResult(
			generatedRoots: generatedRoots,
			mockConfigurationCode: mockConfigurationCode,
			mockConfigurationFulfillers: mockConfigurationFulfillers,
			storedPublicMockPlans: storedPublicMockPlans,
		)
	}

	/// Releases `scopeGenerators` on a task of its own, so that freeing their trees delays no caller.
	private static func releaseInBackground(_ scopeGenerators: consuming [ScopeGenerator]) {
		Task.detached(priority: .background) { [scopeGenerators] in
			withExtendedLifetime(scopeGenerators) {}
		}
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

	/// The one proof of every type's access over the module's declarations, as this run's module mentions them, which a
	/// call that needs it makes once and hands to each reader: the public mock context, and the signatures of the seams
	/// this module generates. It is built the first time a reader asks for it, so a run whose module generates no seam
	/// and declares no public mock builds none.
	func ownAccessProof() -> OwnAccessProof {
		OwnAccessProof(
			instantiables: typeDescriptionToFulfillingInstantiableMap,
			plainTypeDeclarations: plainTypeDeclarations,
			emittingModule: emittingModule,
			runModuleName: seams.currentModule.moduleName,
		)
	}

	/// The proof of every type's access over a run's own declarations, built once, when first read (`ownAccessProof()`).
	/// A local of the call that makes it, never stored on the generator, and read only on the generator's actor.
	final class OwnAccessProof {
		init(instantiables: [TypeDescription: Instantiable], plainTypeDeclarations: [PlainTypeDeclaration], emittingModule: EmittingModule?, runModuleName: String?) {
			self.instantiables = instantiables
			self.plainTypeDeclarations = plainTypeDeclarations
			self.emittingModule = emittingModule
			self.runModuleName = runModuleName
		}

		/// The proof, over the declarations the module sees, with the module's own files and the modules each module
		/// reads as the run's module tells them.
		private(set) lazy var proof: TypeAccessProof = {
			GenerationLayerObservation.record(.accessProof(ofModule: runModuleName, inCallersView: false), inRunOf: runModuleName)
			return TypeAccessProof(
				instantiables: instantiables,
				plainTypeDeclarations: plainTypeDeclarations,
				isOwnFile: emittingModule?.isOwnFile,
				reach: DependencyTreeGenerator.moduleReach(viewedFrom: emittingModule?.identity, instantiables: instantiables, plainTypeDeclarations: plainTypeDeclarations, modulesReadByRunOfModule: emittingModule?.modulesReadByRunOfModule),
			)
		}()

		private let instantiables: [TypeDescription: Instantiable]
		private let plainTypeDeclarations: [PlainTypeDeclaration]
		private let emittingModule: EmittingModule?
		private let runModuleName: String?
	}

	/// The context every public mock of the module shares: the proof of every type's access over the module's
	/// declarations (`ownAccessProof()`), the module of each type, and the names of the module-level configurations; and
	/// the comment the `public` declarations this module generates carry, naming the types they name that it reads no
	/// declaration of, or `nil` when the run writes none (`SeamResolution.carriesUnreadTypeComment`). Made once by each
	/// call that needs it.
	func makePublicMockContext(proof: TypeAccessProof) -> PublicMockContext {
		var moduleNameByType = [TypeDescription: String]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			if let moduleName = instantiable.moduleName {
				moduleNameByType[instantiable.concreteInstantiable] = moduleName
			}
		}
		let moduleName = emittingModule?.identity.moduleName
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
			guard instantiable.generateMock == .public, let publicMockTypeDescriptionToScopeMap, let frozenPublicMockScopeMap else { return self }
			var mockScopes = self
			mockScopes.typeDescriptionToScopeMap = publicMockTypeDescriptionToScopeMap
			mockScopes.frozenScopeMap = frozenPublicMockScopeMap
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
		/// `typeDescriptionToScopeMap`, frozen, which every mock root's tree is built from.
		var frozenScopeMap: FrozenScopeMap
		/// `publicMockTypeDescriptionToScopeMap`, frozen.
		let frozenPublicMockScopeMap: FrozenScopeMap?
		/// The hand-written mock a flat parameter of `mock()` of each type defaults to
		/// (`flatParameterMockDefaults(in:emittingModule:)`).
		var flatParameterMockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault]
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
	///   - foreignPublicMockPlans: The plans of the public mocks of other modules the call has computed, which this adds to.
	func mockScopes(
		additionalMocksToGenerate: Set<String>,
		mockEmittingModule: EmittingModule?,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
		foreignPublicMockPlans: inout PublicMockPlans,
	) async throws -> MockScopes {
		GenerationLayerObservation.record(.mockScopes(ofModule: seams.currentModule.moduleName), inRunOf: seams.currentModule.moduleName)
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
		// Every type built inline, the types whose public mocks the trees call among them, with this module's fills.
		let inlineTypeDescriptionToScopeMap = typeDescriptionToScopeMap
		var publicMockCalls = try await publicMockCalls(in: typeDescriptionToScopeMap, foreignPublicMockPlans: &foreignPublicMockPlans)
		let generatesPublicMock = typeDescriptionToFulfillingInstantiableMap.values.contains(where: { $0.generateMock == .public })
		// Each kind of mock fills the same places and takes a builder for what a fill instantiates that nothing fulfills: a
		// public mock through a hole of its own tree, an internal mock as a seam's internal mock does
		// (`ScopeGenerator.seamMockBuilders`).
		if !publicMockCalls.isEmpty {
			typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping(publicMockCalls: publicMockCalls)
			let fills = holesFilled(byCallsOf: publicMockCalls, in: typeDescriptionToScopeMap)
			// A fill whose tree instantiates a type no declaration fulfills, spelled as no hole can be, is production's error
			// where a mock's tree reaches the call, in a build that compiles the generated mocks: the mocks are under the
			// module's mock condition, so a build that leaves it inactive never compiles the place the mock cannot fill, as
			// `validateHandWrittenMocksTakeOnlyFulfilledParameters` is checked only there.
			if compilesGeneratedMocks {
				try validateFillsInstantiateOnlyWhatCanBeFulfilled(fills.typesNoDeclarationCanFulfillByCalledType, additionalMocksToGenerate: additionalMocksToGenerate)
			}
			// A call that fills a builder declares no dependency for it, so the map is built again with the fills.
			if !fills.filledHoles.isEmpty {
				for (calledType, holes) in fills.filledHoles {
					publicMockCalls[calledType]?.filledHoles = holes
				}
				typeDescriptionToScopeMap = createMockTypeDescriptionToScopeMapping(publicMockCalls: publicMockCalls)
			}
		}

		// The scopes of the types the mock-root loop below generates a mock for because they are listed.
		let additionalMockRootScopes = scopes(ofTypesNamed: additionalMocksToGenerate, in: typeDescriptionToScopeMap)
		// The renames of the declarations the walk below reads are checked before it reads them, as production checks the
		// renames of its trees before it builds scopes. Each mock root's tree, promoted dependencies included, is checked
		// again where the root is created.
		try Self.validateRenamesAreSpelledAsTheMacroAccepts(
			inTreesRootedAt: validatedRootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] }
				+ typeDescriptionToScopeMap.values.filter(\.instantiable.generatesMock)
				+ Array(additionalMockRootScopes),
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
		)
		// A call of another module's public mock whose places this module fills is judged for cycles as production judges a
		// call of that type's seam: over the trees built inline with the fills, from the mock roots and from each called type's
		// root, so that a calling mock reports the cycle its production tree reports.
		try validateCyclesOfCallsWithPlaces(
			publicMockCalls: publicMockCalls,
			inlineTypeDescriptionToScopeMap: inlineTypeDescriptionToScopeMap,
			additionalMocksToGenerate: additionalMocksToGenerate,
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

		let publicMockTypeDescriptionToScopeMap = generatesPublicMock
			? createMockTypeDescriptionToScopeMapping(publicMockCalls: publicMockCalls, buildsHoles: true)
			: nil
		return MockScopes(
			erasureDeclarations: erasureDeclarations,
			erasedToConcreteTypeMap: erasedToConcreteTypeMap,
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			publicMockTypeDescriptionToScopeMap: publicMockTypeDescriptionToScopeMap,
			frozenScopeMap: FrozenScopeMap(freezing: typeDescriptionToScopeMap.lazy.map { (key: $0.key, scope: $0.value) }, interningIn: internerSpace),
			frozenPublicMockScopeMap: publicMockTypeDescriptionToScopeMap.map { map in FrozenScopeMap(freezing: map.lazy.map { (key: $0.key, scope: $0.value) }, interningIn: internerSpace) },
			flatParameterMockDefaults: flatParameterMockDefaults(in: typeDescriptionToScopeMap, emittingModule: mockEmittingModule),
			handWrittenMockLocationsByConcreteType: handWrittenMockLocationsByConcreteType,
		)
	}

	/// The scopes in `typeDescriptionToScopeMap` of the types named `typeNames`, as `additionalMocksToGenerate` names them.
	private func scopes(ofTypesNamed typeNames: Set<String>, in typeDescriptionToScopeMap: [TypeDescription: Scope]) -> Set<Scope> {
		typeNames.isEmpty ? [] : Set(
			typeDescriptionToFulfillingInstantiableMap.values.compactMap { instantiable in
				typeNames.contains(instantiable.concreteInstantiable.asSource)
					? typeDescriptionToScopeMap[instantiable.concreteInstantiable]
					: nil
			},
		)
	}

	/// Validates the tree of the type named `typeName` as `mockScopes` validates a listed type's, once `mockScopes` has
	/// built and validated the map for another listed type: only what listing `typeName` adds is checked, in the order
	/// `mockScopes` checks it – its renames, then its tree's cycles – since every other tree has passed. The query builds
	/// its generators with no seams, so no mock tree calls another module's public mock, and the checks `mockScopes` runs
	/// on such calls have nothing to check.
	func validateListedMockRoot(
		named typeName: String,
		mockScopes: MockScopes,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
	) throws {
		let listedScopes = scopes(ofTypesNamed: [typeName], in: mockScopes.typeDescriptionToScopeMap)
		try Self.validateRenamesAreSpelledAsTheMacroAccepts(inTreesRootedAt: Array(listedScopes), typeDescriptionToScopeMap: mockScopes.typeDescriptionToScopeMap)
		try validatePropertiesAreFulfillable(
			onRootScopes: [],
			additionalMockRootScopes: listedScopes
				.sorted { $0.instantiable.concreteInstantiable < $1.instantiable.concreteInstantiable }
				.map { scope in ValidatedRootScope(scope: scope, boundProperties: Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received, isMock: !scope.instantiable.isRoot) },
			typeDescriptionToScopeMap: mockScopes.typeDescriptionToScopeMap,
			cyclesOnly: true,
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
	/// `requirements(of:)` run the same ones; a pass that needs every mock
	/// root at once goes after `generateMockCode`'s loop instead.
	/// - Parameters:
	///   - generatedMockReason: Why the project generates `mock()` for the type, or `nil` when it does not, so that a
	///     hand-written method named `mock` is the type's mock rather than a collision.
	///   - emittingModule: The module the mock's code compiles in, whose access to each type the mock constructs is
	///     checked, or `nil` when no module emits the mock: `requirements(of:)`
	///     reports what a type needs, not what keeps one module from compiling its mock, so it checks no access. This is
	///     the one check of a single mock root that the two callers do not share; the access that decides which flat
	///     parameters default is asked of `mockScopes` instead, by both.
	///   - checksConstructions: See `createMockRootScopeGenerator`.
	///   - promotedScopesValidatedForHiddenReceives: See `createMockRootScopeGenerator`.
	///   - scopesWithValidatedDeclarations: See `createMockRootScopeGenerator`.
	func createMockRoot(
		for instantiable: Instantiable,
		scope: Scope,
		generatedMockReason: GeneratedMockReason?,
		mockScopes: MockScopes,
		publicMockContext: PublicMockContext?,
		emittingModule: EmittingModule?,
		checksConstructions: Bool = true,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
		childrenRequiringEachOtherValidation: inout ChildrenRequiringEachOtherValidation,
		promotedScopesValidatedForHiddenReceives: inout Set<ObjectIdentifier>,
		scopesWithValidatedDeclarations: inout Set<ObjectIdentifier>,
		constructionMemo: inout ConstructionMemo,
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

		return try await createMockRootScopeGenerator(
			for: instantiable,
			scope: scope,
			typeDescriptionToScopeMap: mockScopes.typeDescriptionToScopeMap,
			frozenScopeMap: mockScopes.frozenScopeMap,
			flatParameterMockDefaults: mockScopes.flatParameterMockDefaults,
			erasedToConcreteTypeMap: mockScopes.erasedToConcreteTypeMap,
			publicMockContext: publicMockContext,
			emittingModule: emittingModule,
			checksConstructions: checksConstructions,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
			promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
			scopesWithValidatedDeclarations: &scopesWithValidatedDeclarations,
			constructionMemo: &constructionMemo,
		)
	}

	/// Where each type with a hand-written mock declares it, by the type's concrete type.
	private func mockDeclarationLocationsOfTypesWithHandWrittenMocks() -> [TypeDescription: Set<Dependency.DeclarationLocation?>] {
		var mockDeclarationLocations = [TypeDescription: Set<Dependency.DeclarationLocation?>]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values where instantiable.mockInitializer != nil {
			mockDeclarationLocations[instantiable.concreteInstantiable, default: []].insert(instantiable.mockDeclarationLocation)
		}
		return mockDeclarationLocations
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
		// Each entry's order, spelled once: spelled inside a comparison, every type was spelled again for every pair compared.
		struct OrderedEntry {
			let instantiable: Instantiable
			let hasHandWrittenMock: Bool
			let hasMock: Bool
			let spellingWithoutAny: String
			let spelling: String
		}
		let typeDescriptionToCompleteScopeMap: [TypeDescription: Scope] = typeDescriptionToFulfillingInstantiableMap.values
			.map { instantiable in
				let hasHandWrittenMock = instantiable.mockInitializer != nil
				return OrderedEntry(
					instantiable: instantiable,
					hasHandWrittenMock: hasHandWrittenMock,
					hasMock: instantiable.generatesMock || hasHandWrittenMock,
					spellingWithoutAny: instantiable.concreteInstantiable.withoutAny.asSource,
					spelling: instantiable.concreteInstantiable.asSource,
				)
			}
			.sorted { lhs, rhs in
				// Non-mockOnly before mockOnly (production claims slots first).
				if lhs.instantiable.mockOnly != rhs.instantiable.mockOnly {
					!lhs.instantiable.mockOnly
				} else if lhs.hasHandWrittenMock != rhs.hasHandWrittenMock {
					// Within the same mockOnly tier, prefer entries with mock info
					// so scope-reuse creates scopes from mock-capable entries.
					// Hand-written mocks (mockInitializer) before generateMock,
					// since hand-written mocks take priority.
					lhs.hasHandWrittenMock
				} else if lhs.hasMock != rhs.hasMock {
					lhs.hasMock
				} else if lhs.spellingWithoutAny != rhs.spellingWithoutAny {
					// Stable tiebreaker: sort by concrete type name so scope-reuse
					// selects the same entry across runs, as `TypeDescription.<` orders them.
					lhs.spellingWithoutAny < rhs.spellingWithoutAny
				} else {
					lhs.spelling < rhs.spelling
				}
			}
			.map(\.instantiable)
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
					} else if dependency.isInstantiatedOnlyIfAvailable, !buildsHoles || !Self.canBeHole(dependency) {
						// No declaration the module sees fulfills the type, fake included: an internal mock binds the property
						// where production binds `nil`, from an override that defaults to `nil`. A public mock's is a hole
						// (below), whose builder defaults to one that returns `nil`, but for a type spelled as no hole can be.
						scope.propertiesToGenerate.append(Self.unavailableDependency(dependency))
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
						declarationReference: aliasDeclarationReferences.reference(to: dependency.declarationLocation),
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
	/// `typeDescriptionToScopeMap`, in which every call passes every builder up. A module fills a place where the same tree
	/// built for production fills it: where a declaration it sees fulfills the place, as the mock's tree built inline would
	/// build it (`fulfillingMockScope(of:in:)`: a hand-written mock or a `mockOnly` fake included), and the fill builds that
	/// tree as the inline mock would, hand-written mock methods included. A construction in it this module cannot reach is
	/// an access error, which the mock root whose tree reaches the call reports, in a build that compiles the generated
	/// mocks: production's, but where the fill calls a hand-written mock method that production does not call; a build
	/// that does not compile them passes such a place up. What the fill receives beside the values the place's scope
	/// struct carries is received from the calling mock's tree, as production's fill receives it from the caller's: a
	/// value the tree provides is handed to the fill, one nothing provides is a parameter of `mock()`, and one the called
	/// mock's tree binds where the fill cannot read it is the error production reports (`validateFills`). Every other
	/// place is passed up: the calling mock takes it, through a case of its own enum or as a parameter its caller passes.
	/// A place a route reaches without a value its fill reads is filled there with the caller's, as on every other route.
	///
	/// A type a fill's tree instantiates that no declaration the module sees fulfills is a place of a public mock's own tree,
	/// which is built with holes, and an internal mock's fill binds it from a builder `mock()` takes
	/// (`ScopeGenerator.seamMockBuilders`), as a seam's internal mock binds its hole, where its spelling can be a hole
	/// (`canBeHole`). Where a spelling cannot be one, which only hand-written code builds, the place is not filled, and the
	/// type is among `typesNoDeclarationCanFulfillByCalledType`, which production reports
	/// (`validateFillsInstantiateOnlyWhatCanBeFulfilled`).
	///
	/// Gates then pass a hole type of a called type up whole, every place of it, where the twin fills it: a re-entered called
	/// type whose fill reads a lazy value beside its place's fields; one whose fill below its root reads by value a value the
	/// module holds lazily, while a fill that builds it again reads none of it; and places of one hole type whose fills read
	/// different lazy values (`holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`). Contract rule 7 lists the difference
	/// (`seam-and-mock-contract.md`).
	private func holesFilled(
		byCallsOf publicMockCalls: [TypeDescription: PublicMockCall],
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
	) -> (filledHoles: [TypeDescription: [SeamSignature.Hole]], typesNoDeclarationCanFulfillByCalledType: [TypeDescription: Set<TypeDescription>]) {
		guard let emittingModule = emittingModuleToCheck else { return ([:], [:]) }
		var fills = [GatedFill]()
		var receivedPropertiesCache = ReceivedPropertiesCache()
		var typesNoDeclarationCanFulfillByCalledType = [TypeDescription: Set<TypeDescription>]()
		for calledType in publicMockCalls.keys.sorted() {
			guard let publicMockCall = publicMockCalls[calledType] else { continue }
			for hole in publicMockCall.holes {
				guard let fulfillingScope = Self.fulfillingMockScope(of: hole, in: typeDescriptionToScopeMap) else { continue }
				// A fill whose tree constructs a type this module cannot reach, such as an `internal` type of another module, is
				// filled, as its production twin fills it, and the mock root whose tree reaches the call reports the access error
				// of each construction the fill makes (`createMockRootScopeGenerator`, which walks the fills of the calls in its
				// tree): the twin's, but for a hand-written mock method the fill calls where the twin calls the initializer
				// (`constructions(inTreeRootedAt:…)`). The generated mocks are under the module's mock condition, so a build that
				// leaves it inactive, which never compiles the fill, passes the place up and reports nothing, as
				// `validateFillsInstantiateOnlyWhatCanBeFulfilled` is checked only where the mocks compile. An `if` rather than
				// `||`, whose autoclosure Swift 6.2 rejects for capturing the scope ("sending 'fulfillingScope' risks causing data
				// races").
				let isFilled = if compilesGeneratedMocks {
					true
				} else {
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
					).isEmpty
				}
				guard isFilled else { continue }
				let typesNoDeclarationCanFulfill = Self.typesThatCannotBeHoles(inTreeRootedAt: fulfillingScope)
				guard typesNoDeclarationCanFulfill.isEmpty else {
					typesNoDeclarationCanFulfillByCalledType[calledType, default: []].formUnion(typesNoDeclarationCanFulfill)
					continue
				}
				// A route on which no level binds a value the fill reads hands the fill the caller's, as production's root
				// dispatcher does (`PublicMockLevelFunctions`), so the place is filled on every route.
				fills.append(GatedFill(calledType: calledType, hole: hole, fulfillingScope: fulfillingScope, cache: &receivedPropertiesCache))
			}
		}
		// Each value a declaration of the module's mock trees holds in a `LazilyInstantiated` or `SendableLazilyInstantiated`,
		// by its label and instance type, whatever the declaration: one the module instantiates, or one a type receives whose
		// tree's root lives in a module that depends on this one.
		var lazilyHeldValues = Set<Property>()
		for scope in typeDescriptionToScopeMap.values {
			lazilyHeldValues.formUnion(scope.instantiable.dependencies.compactMap(\.property.asLazilyInstantiatedInstanceProperty))
		}
		let holeTypesPassedUp = Self.holeTypesTheFillGatesPassUp(of: fills, in: publicMockCalls, lazilyHeldValues: lazilyHeldValues)
		var filledHoles = [TypeDescription: [SeamSignature.Hole]]()
		for fill in fills where !holeTypesPassedUp.contains(fill.key) {
			filledHoles[fill.calledType, default: []].append(fill.hole)
		}
		return (filledHoles, typesNoDeclarationCanFulfillByCalledType)
	}

	/// A place `holesFilled(byCallsOf:in:)` would fill, with what its fill's tree reads and calls.
	private struct GatedFill {
		init(calledType: TypeDescription, hole: SeamSignature.Hole, fulfillingScope: Scope, cache: inout ReceivedPropertiesCache) {
			self.calledType = calledType
			self.hole = hole
			// A field is read by value, only if available, and as a lazily instantiated property's instance too.
			var fieldForms = Set<Property>()
			for field in hole.fields {
				for form in [field.property] + [field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding].compactMap(\.self) {
					fieldForms.insert(form)
					fieldForms.insert(form.asOptionalProperty)
				}
			}
			received = DependencyTreeGenerator.collectReceivedProperties(from: fulfillingScope, cache: &cache).received
			receivedBesideFields = received.subtracting(fieldForms)
			var calledTypes = Set<TypeDescription>()
			var visitedScopes = Set<ObjectIdentifier>()
			// A stack of its own, since a tree can be as deep as the module has types.
			var scopesToVisit = [fulfillingScope]
			while let scope = scopesToVisit.popLast() {
				guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
				if let publicMockCall = scope.publicMockCall {
					calledTypes.insert(publicMockCall.type)
				}
				for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
					scopesToVisit.append(childScope)
				}
			}
			calledTypesInTree = calledTypes
		}

		let calledType: TypeDescription
		let hole: SeamSignature.Hole
		/// Everything the fill's tree receives.
		let received: Set<Property>
		/// What the fill's tree receives beside the values the place's scope struct carries.
		let receivedBesideFields: Set<Property>
		/// The types whose public mocks the fill's tree calls.
		let calledTypesInTree: Set<TypeDescription>

		var key: HoleTypeOfCall {
			HoleTypeOfCall(calledType: calledType, holeType: hole.holeType)
		}

		/// The values the fill reads, beside the place's fields, held in a `LazilyInstantiated` or
		/// `SendableLazilyInstantiated`.
		var lazyValuesReadBesideFields: Set<Property> {
			receivedBesideFields.filter { $0.typeDescription.unwrapped.lazilyInstantiatedInstanceType != nil }
		}
	}

	/// A hole type of a called type, which a gate passes up whole.
	private struct HoleTypeOfCall: Hashable {
		let calledType: TypeDescription
		let holeType: SeamSignature.HoleType
	}

	/// The hole types of the called types that the calling mock passes up whole, every place of them, where its production
	/// twin fills them, the difference contract rule 7 lists (`seam-and-mock-contract.md`, `public-mock-builders.md`). The
	/// twin fills these places, but the calling mock cannot hand each route's fill the lazy value the twin hands it, so it
	/// takes the builder, as it did before its fills read the caller's values:
	/// - **Re-entry.** A called type is re-entered when the tree of a fill of one of its places calls its public mock again,
	///   or calls a public mock whose builders reach its places, itself or through the fills of the calls it makes, as where
	///   its fill calls a second called type whose own fill calls the first. A hole type of a re-entered called type is
	///   passed up when a fill of one of its places reads, beside the place's fields, a `LazilyInstantiated` or
	///   `SendableLazilyInstantiated` value: the called mock binds the value by value, so no level of the re-entered call
	///   holds the wrapper the twin hands that fill.
	/// - **A value held lazily that a fill building the called type again does not read.** A hole type of a re-entered
	///   called type is passed up when a fill of one of its places below the called type's root reads, beside the place's
	///   fields, by value or only if available, a value that a declaration of the module's mock trees holds in a
	///   `LazilyInstantiated` or `SendableLazilyInstantiated` (`lazilyHeldValues`, by label and instance type), and a fill of
	///   the called type that builds it again reads no form of that label. The levels below the root take the value from
	///   the re-entered call's root level function, and the fill that builds the called type again holds only its caller's
	///   wrapper, which it would hand that function. The gate decides for the whole module, as the others do, since it does
	///   not see the callers, so it also passes up places whose caller holds the value by value while another declaration
	///   holds it lazily, and places of a called type built again only through another called type's fill, which compile
	///   filled where the fill below the root reads the value by value, the stated cost of one rule, as before calling mocks
	///   filled their places.
	/// - **Places that disagree.** A hole type of a called type is passed up when two of its places' fills read different
	///   `LazilyInstantiated` or `SendableLazilyInstantiated` values beside their fields, as where one place is beneath a
	///   level that declares the value again and the called mock's by-value copy reaches the other: one fill serves every
	///   place of a hole type, and no level that holds only the copy can hand it the wrapper. The gate also passes up some
	///   places whose fills would build what inline builds, as a calling mock passed them up before its fills read the
	///   caller's values, the stated cost of one rule: where the called mock holds no copy of the value, so each route hands
	///   its fill the wrapper inline reads, and where the places hold the hole type in two builder forms, one of them an
	///   `ErasedInstantiator`.
	/// - Then, as a fill never passes a place up, a fill whose tree calls a public mock that now passes a builder up is not
	///   filled either, until none is: its hole type is passed up too.
	/// A hole type is never passed up in part, so no builder is half filled. Every other place is filled as before: a fill
	/// that reads only its place's fields, or values by value that no declaration holds lazily or that every fill building
	/// its called type again reads too, whether or not its called type is re-entered.
	private static func holeTypesTheFillGatesPassUp(of fills: [GatedFill], in publicMockCalls: [TypeDescription: PublicMockCall], lazilyHeldValues: Set<Property>) -> Set<HoleTypeOfCall> {
		var calledTypesByCalledType = [TypeDescription: Set<TypeDescription>]()
		for fill in fills {
			calledTypesByCalledType[fill.calledType, default: []].formUnion(fill.calledTypesInTree)
		}
		var passedUp = Set<HoleTypeOfCall>()
		for calledType in calledTypesByCalledType.keys {
			let sites = Set(publicMockCalls[calledType]?.holes.map(\.site) ?? [])
			/// Whether a tree that calls `calledTypesInTree` builds `calledType` again: one of them, those their fills call, and
			/// so on, is `calledType`, or a called type whose builders reach its places.
			func buildsCalledTypeAgain(_ calledTypesInTree: Set<TypeDescription>) -> Bool {
				var reachedCalledTypes = Set<TypeDescription>()
				var calledTypesToVisit = Array(calledTypesInTree)
				while let reachedCalledType = calledTypesToVisit.popLast() {
					guard reachedCalledTypes.insert(reachedCalledType).inserted else { continue }
					calledTypesToVisit.append(contentsOf: calledTypesByCalledType[reachedCalledType] ?? [])
				}
				return reachedCalledTypes.contains { reachedCalledType in
					reachedCalledType == calledType || publicMockCalls[reachedCalledType]?.holes.contains { sites.contains($0.site) } == true
				}
			}
			let fillsBuildingCalledTypeAgain = fills.filter { $0.calledType == calledType && buildsCalledTypeAgain($0.calledTypesInTree) }
			for fill in fills where fill.calledType == calledType && !fillsBuildingCalledTypeAgain.isEmpty {
				let readsLazyValue = !fill.lazyValuesReadBesideFields.isEmpty
				// A place below the called type's root, whose level takes the value from the root level function: its site path
				// holds the property of a level between.
				let readsLazilyHeldValueAFillBuildingCalledTypeAgainDoesNot = fill.hole.sitePath.count > 1 && fill.receivedBesideFields.contains { value in
					lazilyHeldValues.contains(value.asUnwrappedProperty) && fillsBuildingCalledTypeAgain.contains { !$0.received.contains { $0.label == value.label } }
				}
				if readsLazyValue || readsLazilyHeldValueAFillBuildingCalledTypeAgainDoesNot {
					passedUp.insert(fill.key)
				}
			}
		}
		var lazyValuesReadBesideFieldsByKey = [HoleTypeOfCall: Set<Property>]()
		for fill in fills {
			if let other = lazyValuesReadBesideFieldsByKey.updateValue(fill.lazyValuesReadBesideFields, forKey: fill.key), other != fill.lazyValuesReadBesideFields {
				passedUp.insert(fill.key)
			}
		}
		// The builders each call passes up with every fill filled, which a fill that calls the mock receives already.
		let builderPropertiesPassedUpByEveryFill = builderPropertiesPassedUp(by: fills, in: publicMockCalls)
		while !passedUp.isEmpty {
			let builderProperties = builderPropertiesPassedUp(by: fills.filter { !passedUp.contains($0.key) }, in: publicMockCalls).subtracting(builderPropertiesPassedUpByEveryFill)
			var passesUpMore = false
			for fill in fills where !fill.received.isDisjoint(with: builderProperties) && passedUp.insert(fill.key).inserted {
				passesUpMore = true
			}
			guard passesUpMore else { break }
		}
		return passedUp
	}

	/// The properties under which a fill's tree receives the builders the calls of `publicMockCalls` pass up when the places
	/// of `fills` are filled.
	private static func builderPropertiesPassedUp(by fills: [GatedFill], in publicMockCalls: [TypeDescription: PublicMockCall]) -> Set<Property> {
		var filledHolesByCalledType = [TypeDescription: [SeamSignature.Hole]]()
		for fill in fills {
			filledHolesByCalledType[fill.calledType, default: []].append(fill.hole)
		}
		var builderProperties = Set<Property>()
		for var publicMockCall in publicMockCalls.values {
			publicMockCall.filledHoles = filledHolesByCalledType[publicMockCall.type, default: []]
			let passedUpLabels = Set(publicMockCall.passedUpBuilders.map(\.label))
			for parameter in publicMockCall.passedParameters {
				if let builder = parameter.builder, passedUpLabels.contains(builder.label) {
					builderProperties.insert(parameter.dependency.property)
				}
			}
		}
		return builderProperties
	}

	/// The types the scopes of the mock tree rooted at `scope`, in a map built without holes, instantiate as properties no
	/// scope builds whose spelling cannot be a hole (`canBeHole`): types no declaration the module sees fulfills, which only
	/// hand-written code could build.
	private static func typesThatCannotBeHoles(inTreeRootedAt scope: Scope) -> Set<TypeDescription> {
		var typesThatCannotBeHoles = Set<TypeDescription>()
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
			for dependency in visitedScope.instantiable.dependencies where dependency.isInstantiated && !builtProperties.contains(dependency.property) && !canBeHole(dependency) {
				typesThatCannotBeHoles.insert(dependency.asInstantiatedType)
			}
		}
		return typesThatCannotBeHoles
	}

	/// Reports, as production reports a type its trees reach that no declaration fulfills (`noInstantiableFoundErrors(of:)`),
	/// each type a fill of a call of another module's public mock instantiates that no declaration can fulfill
	/// (`holesFilled(byCallsOf:in:)`), where a mock's tree reaches the call: the tree of a type that generates a mock, or that
	/// the module lists in `additionalMocksToGenerate`, the dependencies each receives included, which the mock root builds.
	private func validateFillsInstantiateOnlyWhatCanBeFulfilled(_ typesNoDeclarationCanFulfillByCalledType: [TypeDescription: Set<TypeDescription>], additionalMocksToGenerate: Set<String>) throws {
		guard !typesNoDeclarationCanFulfillByCalledType.isEmpty else { return }
		var typesToVisit = typeDescriptionToFulfillingInstantiableMap.values
			.filter { $0.generatesMock || additionalMocksToGenerate.contains($0.concreteInstantiable.asSource) }
			.map(\.concreteInstantiable)
		var reachedTypes = Set<TypeDescription>()
		var typesNoDeclarationCanFulfill = Set<TypeDescription>()
		while let typeDescription = typesToVisit.popLast() {
			guard reachedTypes.insert(typeDescription).inserted else { continue }
			typesNoDeclarationCanFulfill.formUnion(typesNoDeclarationCanFulfillByCalledType[typeDescription, default: []])
			for dependency in typeDescriptionToFulfillingInstantiableMap[typeDescription]?.dependencies ?? [] {
				switch dependency.source {
				case .instantiated, .received:
					typesToVisit.append(dependency.asInstantiatedType)
				case .aliased, .forwarded:
					continue
				}
			}
		}
		guard !typesNoDeclarationCanFulfill.isEmpty else { return }
		throw noInstantiableFoundErrors(of: typesNoDeclarationCanFulfill)
	}
}
