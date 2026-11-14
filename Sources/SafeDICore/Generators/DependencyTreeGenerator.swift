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
	///   - emittingModule: The module the generated code compiles in, which decides what access each declaration the
	///     generated code constructs needs, or `nil` to check no access, as `SafeDITool query` does.
	///   - seams: The seams among the declarations – the types declared with `generateDependencyTree: true` – whose
	///     generated initializers this module generates or calls. Validation inlines every seam's tree; generation
	///     builds each generated seam's tree in its own initializer and calls the initializer wherever a tree
	///     reaches the seam.
	///   - plainTypeDeclarations: The declarations of types that are not `@Instantiable` in the modules whose
	///     declarations SafeDITool read, each with the module that declares it, among which the declaration of a type
	///     an extension extends bounds the types declared in or by that extension.
	///   - writtenImportAccessLevels: The access levels the files SafeDI read spell on their imports, the module's own
	///     apart from its dependencies', which decide the level each generated import spells.
	///   - unreadImports: What the run knows of the modules a file imports that it read nothing of, or `nil` when it
	///     cannot tell which modules it could have read.
	///   - readOwnFiles: Reads what the module's own files say that decides an import added for a fulfiller, or `nil` when
	///     the run cannot read them. Called at most once, the first time a generated file would gain such an import apart
	///     from a type of the module that shadows the fulfiller, which only what this reads can find.
	///   - viewInstantiablesByModuleName: The declarations the module infos this run was given carry of modules whose
	///     module info it was not given, by module, which a seam or public mock of another module is computed from. They
	///     never fulfill a type of this module's trees: they attribute the types generated code names to the modules that
	///     declare them, and tell an error whether listing a module would fill a builder.
	///   - viewPlainTypeDeclarations: The plain type declarations of those modules, which attribute types too.
	///   - viewDeclaringModules: The module each type those declarations fulfill is declared in, with the module this
	///     module reaches it through, which an error about a type no declaration this module reads fulfills names.
	public init(
		importStatements: [ImportStatement],
		mockImportStatements: [ImportStatement],
		typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
		aliasDeclarationReferences: AliasDeclarationReferences,
		emittingModule: EmittingModule? = nil,
		seams: SeamResolution = .none,
		plainTypeDeclarations: [PlainTypeDeclaration] = [],
		writtenImportAccessLevels: GeneratedImportAccess.WrittenLevels = .none,
		unreadImports: UnreadImports? = nil,
		readOwnFiles: (@Sendable () async -> FulfillerImports.OwnFiles)? = nil,
		viewInstantiablesByModuleName: [String: [Instantiable]] = [:],
		viewPlainTypeDeclarations: [PlainTypeDeclaration] = [],
		viewDeclaringModules: [TypeDescription: ViewDeclaringModule] = [:],
	) {
		self.unreadImports = unreadImports
		self.viewInstantiablesByModuleName = viewInstantiablesByModuleName
		self.viewDeclaringModules = viewDeclaringModules
		let viewInstantiables = Array(viewInstantiablesByModuleName.values.joined())
		self.importStatements = importStatements
		self.mockImportStatements = mockImportStatements
		let importAccessSpellingOwnLevels: @Sendable ([String: Set<AccessLevel>]) -> GeneratedImportAccess = { ownLevelsByModuleName in
			GeneratedImportAccess(
				writtenLevels: writtenImportAccessLevels.addingOwnLevels(ownLevelsByModuleName),
				instantiables: Array(typeDescriptionToFulfillingInstantiableMap.values) + viewInstantiables,
				plainTypeDeclarations: plainTypeDeclarations + viewPlainTypeDeclarations,
				emittingModuleName: emittingModule?.identity.moduleName,
				isOwnFile: emittingModule?.isOwnFile,
			)
		}
		self.importAccessSpellingOwnLevels = importAccessSpellingOwnLevels
		importAccess = importAccessSpellingOwnLevels([:])
		self.readOwnFiles = readOwnFiles
		self.typeDescriptionToFulfillingInstantiableMap = typeDescriptionToFulfillingInstantiableMap
		self.aliasDeclarationReferences = aliasDeclarationReferences
		self.emittingModule = emittingModule
		self.seams = seams
		self.plainTypeDeclarations = plainTypeDeclarations
		declaredTypeNames = Self.namesOfTypesDeclaredAtFileScope(
			instantiables: Array(typeDescriptionToFulfillingInstantiableMap.values) + viewInstantiables,
			plainTypeDeclarations: plainTypeDeclarations + viewPlainTypeDeclarations,
		)
		extendedTypeDeclarations = ExtendedTypeDeclarations(
			instantiables: typeDescriptionToFulfillingInstantiableMap,
			plainTypeDeclarations: plainTypeDeclarations,
		)
	}

	// MARK: Public

	/// What a run of `generate` knows of the modules a file imports that it read nothing of. A type no declaration the run
	/// read fulfills may be declared in such a module, which the build did not give the run, so the error at a file that
	/// instantiates the type says how the run's integration reads one more module. The error names none of the file's
	/// modules: a file imports the SDK's and the toolchain's modules too, which SafeDI cannot tell from the user's.
	public struct UnreadImports: Sendable {
		/// How the run learns of the modules it reads, which decides how to give it one more.
		public enum Integration: Hashable, Sendable {
			/// The run reads the module info of the modules the build system lists: Bazel's, Tuist's, a custom build's.
			case moduleInfo
			/// The run reads the files of the targets in the SwiftPM plugin's target graph.
			case targetGraph
		}

		/// - Parameter importsModuleNotRead: Whether the file at a path, as the run names the file, imports a module the run
		///   read nothing of, or `nil` when the run does not know what the file imports. Called only on the path of an error.
		public init(integration: Integration, importsModuleNotRead: @escaping @Sendable (_ filePath: String) -> Bool?) {
			self.integration = integration
			self.importsModuleNotRead = importsModuleNotRead
		}

		public let integration: Integration
		public let importsModuleNotRead: @Sendable (_ filePath: String) -> Bool?
	}

	/// A module whose declarations a module info's view carries, which this module depends on through another module but
	/// does not list, so none of its declarations fulfills a type of this module's trees.
	public struct ViewDeclaringModule: Hashable, Sendable {
		public init(moduleName: String, throughModuleName: String) {
			self.moduleName = moduleName
			self.throughModuleName = throughModuleName
		}

		/// The module that declares the type.
		public let moduleName: String
		/// The module this module lists whose module info carries that module's declarations.
		public let throughModuleName: String
	}

	/// The module the generated code compiles in, which decides what access each declaration the generated code
	/// constructs needs.
	public struct EmittingModule: Sendable {
		/// - Parameters:
		///   - identity: The module, as far as SafeDITool knows it.
		///   - isOwnFile: Whether a file a declaration records is one of the module's own files, which the module
		///     compiles: a construction of a declaration in such a file needs `internal` access only.
		///   - isReadableFile: Whether a file a declaration records can be read at the path it records, so that an
		///     error can be reported at the declaration with a fix-it that edits it.
		///   - additionalMocksToGenerateLocation: Where the `#SafeDIConfiguration` that lists the module's
		///     `additionalMocksToGenerate` is declared, at which an error about a construction in a listed type's
		///     generated mock is reported when the declaration that must change cannot be read.
		///   - modulesReadByRunOfModule: The modules whose declarations the run of `generate` for the named module
		///     reads, itself included, from which it would build the tree of a seam it declares: a seam candidate's
		///     module keeps a construction out of this module only when it reads the declaration of every type on the
		///     path from the candidate to it (`SeamCandidateOnPaths`); and whether SafeDI knows the module can import no
		///     other, which lets a proof drop a declaration of a module the mentioning module does not read
		///     (`TypeAccessProof.ModuleReach`). `nil` when SafeDI is not told, as `query needs` is not: no candidate's
		///     module then reads another, and every mention reads every module.
		public init(
			identity: ModuleIdentity,
			isOwnFile: @escaping @Sendable (String) -> Bool,
			isReadableFile: @escaping @Sendable (String) -> Bool,
			additionalMocksToGenerateLocation: Dependency.DeclarationLocation?,
			modulesReadByRunOfModule: (@Sendable (_ moduleName: String) -> TypeAccessProof.ModuleReach.ModulesRead)?,
		) {
			self.identity = identity
			self.isOwnFile = isOwnFile
			self.isReadableFile = isReadableFile
			self.additionalMocksToGenerateLocation = additionalMocksToGenerateLocation
			self.modulesReadByRunOfModule = modulesReadByRunOfModule
		}

		let identity: ModuleIdentity
		let isOwnFile: @Sendable (String) -> Bool
		let isReadableFile: @Sendable (String) -> Bool
		let additionalMocksToGenerateLocation: Dependency.DeclarationLocation?
		let modulesReadByRunOfModule: (@Sendable (_ moduleName: String) -> TypeAccessProof.ModuleReach.ModulesRead)?
	}

	public struct GeneratedRoot: Sendable {
		public let typeDescription: TypeDescription
		public let sourceFilePath: String?
		/// The generated extension code for this root, without the file header.
		public let code: String
		/// The types `code` builds that the properties it builds them for do not name, whose modules the header can need.
		public let fulfillers: Set<FulfillerImports.Fulfiller>
	}

	public struct MockGenerationResult: Sendable {
		public let generatedRoots: [GeneratedRoot]
		public let mockConfigurationCode: String?
		/// The types whose configurations `mockConfigurationCode` declares that the properties they are built for do not
		/// name, whose modules the header can need.
		public let mockConfigurationFulfillers: Set<FulfillerImports.Fulfiller>
	}

	/// The code a generated file holds, which decides what its header imports.
	public enum GeneratedFileContent: Sendable {
		/// Dependency-tree code.
		case dependencyTree(code: String)
		/// Mock code, as each generated mock file and the shared mock configuration file hold, which only builds in
		/// which `mockConditionalCompilation` is active compile, or every build when it is `nil`.
		case mock(code: String, mockConditionalCompilation: String?)
		/// Both dependency-tree code and mock code, as one file that holds a module's whole output does.
		case dependencyTreeAndMock(dependencyTreeCode: String, mockCode: String, mockConditionalCompilation: String?)
	}

	/// The file header to prepend to a generated file whose code is `content`: the imports `content` needs, each spelling
	/// the access level the file's declarations need where they compile (`GeneratedImportAccess`).
	/// - Parameter fulfillers: The types the trees the file holds build that the properties they are built for do not name.
	public func fileHeader(for content: GeneratedFileContent, building fulfillers: Set<FulfillerImports.Fulfiller>) async -> String {
		switch content {
		case let .dependencyTree(code):
			await Self.fileHeader(importing: imports(importStatements, building: fulfillers, forUnconditionalCode: code, mockCode: nil))
		case let .mock(code, mockConditionalCompilation):
			if let mockConditionalCompilation {
				await Self.fileHeader(importing: imports(mockImportStatements, building: fulfillers, forUnconditionalCode: "", mockCode: (code, mockConditionalCompilation)))
			} else {
				await Self.fileHeader(importing: imports(mockImportStatements, building: fulfillers, forUnconditionalCode: code, mockCode: nil))
			}
		case let .dependencyTreeAndMock(dependencyTreeCode, mockCode, mockConditionalCompilation):
			if let mockConditionalCompilation {
				await Self.fileHeader(importing: imports(importStatements + mockImportStatements, building: fulfillers, forUnconditionalCode: dependencyTreeCode, mockCode: (mockCode, mockConditionalCompilation)))
			} else {
				await Self.fileHeader(importing: imports(importStatements + mockImportStatements, building: fulfillers, forUnconditionalCode: dependencyTreeCode + "\n\n" + mockCode, mockCode: nil))
			}
		}
	}

	public func generatePerRootCodeTrees() async throws -> [GeneratedRoot] {
		let rootScopeGenerators = try rootScopeGenerators
		try Self.validateFills(
			inTreesRootedAt: rootScopeGenerators.map(\.scopeGenerator),
			callerModule: seams.currentModule,
		)
		try await validateSendableBuildersCaptureNoNonSendableWrapper(inTreesRootedAt: rootScopeGenerators.map { ($0.instantiable, $0.scopeGenerator) })
		try await validateNoSeamTierOmitsProvidedValue(inTreesRootedAt: rootScopeGenerators)

		let generatedRoots = try await withThrowingTaskGroup(
			of: GeneratedRoot?.self,
			returning: [GeneratedRoot].self,
		) { taskGroup in
			for rootInfo in rootScopeGenerators {
				taskGroup.addTask {
					let code = try await rootInfo.scopeGenerator.generateCode()
					return await GeneratedRoot(
						typeDescription: rootInfo.typeDescription,
						sourceFilePath: rootInfo.sourceFilePath,
						code: code,
						fulfillers: rootInfo.scopeGenerator.fulfillersOfTree(buildingMock: false),
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
		// The file `scan` plans for a root another module declares holds no code: that module generates the root's
		// `init()`, so the file says where, and what to do when that module does not run SafeDI. A root without
		// dependencies gets no `init()` in its own module either, so its file says nothing.
		return generatedRoots + rootsOfOtherModules.map { root in
			let rootType = root.concreteInstantiable.asSource
			// Type and module names are written bare in generated comments, as the root's is.
			let declaringModule = root.moduleName.map { "\($0), the module that declares \(rootType)" } ?? "the module that declares \(rootType)"
			return GeneratedRoot(
				typeDescription: root.concreteInstantiable,
				sourceFilePath: root.sourceFilePath,
				code: root.dependencies.isEmpty
					? ""
					: "// SafeDI generates \(rootType)'s init() only in \(declaringModule). If \(rootType)() does not compile, add the SafeDI plugin to the target that declares \(rootType).",
				fulfillers: [],
			)
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
	private var publicMockContext: PublicMockContext {
		if let memoizedPublicMockContext {
			return memoizedPublicMockContext
		}
		let context = makePublicMockContext()
		memoizedPublicMockContext = context
		return context
	}

	/// `publicMockContext`, once made.
	private var memoizedPublicMockContext: PublicMockContext?

	/// The comment the `public` declarations this module generates carry, naming the types they name that it reads no
	/// declaration of, or `nil` when the run writes none (`SeamResolution.carriesUnreadTypeComment`). Over the
	/// declarations the module's own seams and public mocks are computed from, as `publicMockContext` reads them.
	private var unreadTypeComment: UnreadTypeComment? {
		publicMockContext.unreadTypeComment
	}

	/// Which declarations a mention in each module of a view can name, the view being `viewer`'s, over `instantiables` and
	/// `plainTypeDeclarations`; every one when the run is not told what each module reads, or knows no viewer.
	private static func moduleReach(
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
	/// - Parameters:
	///   - generatesMock: Whether `mock()` is generated for the type, so that a hand-written method named `mock` is
	///     rejected as `generateMockCode` rejects it. Otherwise such a method is the type's mock, which the root is
	///     built with.
	///   - mockEmittingModule: The module that generates the type's mock, whose access to each hand-written mock
	///     decides, as in that module's `generateMockCode`, which flat parameters of `mock()` default to one
	///     (`flatParameterMockDefaults(in:emittingModule:)`), or `nil` when no one module is known to generate it: every
	///     hand-written mock is then taken to be callable. No other access is checked.
	public func requirements(forTypeNamed typeName: String, generatesMock: Bool, mockEmittingModule: EmittingModule?) async throws -> TypeRequirements? {
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let mockScopes = try await mockScopes(
			additionalMocksToGenerate: [typeName],
			mockEmittingModule: constructsOnlyPublicDeclarations ? nil : mockEmittingModule,
			receivedPropertiesCache: &receivedPropertiesCache,
		)
		// The type's own entry in the scope map, which `generateMockCode` builds each mock root from. The name is
		// matched as `additionalMocksToGenerate` matches it, and the entry is chosen by type, never by map order.
		guard let (concreteType, scope) = mockScopes.typeDescriptionToScopeMap
			.filter({ $0.key == $0.value.instantiable.concreteInstantiable && $0.key.asSource == typeName })
			.min(by: { $0.key < $1.key })
		else { return nil }
		let instantiable = mockRootInstantiable(for: scope.instantiable, scope: scope)
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
		var promotedScopesValidatedForHiddenReceives = Set<ObjectIdentifier>()
		let mockRoot = try await createMockRoot(
			for: instantiable,
			scope: scope,
			// A type that sets `generateMock: true` fails to generate in its own module; any other generated mock
			// exists only because the type is listed, so removing it from the list is also a fix.
			generatedMockReason: generatesMock ? (instantiable.generatesMock ? .generateMock : .additionalMocksToGenerate) : nil,
			mockScopes: mockScopes,
			// The query reports what a type needs, not what keeps a module from compiling its mock, so it checks no
			// module's access here; `mockEmittingModule` decides only which flat parameters default.
			emittingModule: nil,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
			promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
		)
		// Whether a public mock can be generated is decided for one root and needs no emitting module, as
		// `generateMockCode` decides it, so the query reports it too.
		if generatesMock, instantiable.generateMock == .public {
			let findings = await mockRoot.publicMockFindings(of: instantiable, context: publicMockContext, mockDefaults: mockScopes.flatParameterMockDefaults)
			guard findings.isEmpty else {
				throw DependencyTreeGeneratorError.publicMockCannotBeGenerated(findings)
			}
		}
		let parameters = await mockRoot.mockRootParameters(instantiable: instantiable, mockDefaults: mockScopes.flatParameterMockDefaults)

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
		for uncoveredParameter in parameters.flatUncoveredParameters {
			requiredParameters.append(TypeRequirements.RequiredParameter(
				label: uncoveredParameter.label,
				typeSource: uncoveredParameter.typeSource,
				defaultExpression: nil,
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

	/// What every mock root is built from: the scope of each type a mock can build, and what completes a mock
	/// root's tree.
	private struct MockScopes {
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
	private struct ErasureDeclaration: Hashable {
		let concreteType: TypeDescription
		let declaration: TypeRequirements.Erasure.Declaration
	}

	/// Builds the mock scope map and validates it, and collects what every mock root is built with.
	/// - Parameters:
	///   - additionalMocksToGenerate: The names of the types whose mocks are generated because they are listed.
	///   - mockEmittingModule: The module the mocks compile in, whose access to each hand-written mock decides which
	///     flat parameters default to one, or `nil` when no access needs checking (`emittingModuleToCheck`).
	private func mockScopes(
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
				for (calledType, holes) in holesFilled(byCallsOf: publicMockCalls, in: typeDescriptionToScopeMap, unfulfilledInstantiationsAreHoles: true) {
					publicMockCallsOfPublicMocks[calledType]?.filledHoles = holes
				}
			}
			let filledHoles = holesFilled(byCallsOf: publicMockCalls, in: typeDescriptionToScopeMap, unfulfilledInstantiationsAreHoles: false)
			if !filledHoles.isEmpty {
				for (calledType, holes) in filledHoles {
					publicMockCalls[calledType]?.filledHoles = holes
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
	private func flatParameterMockDefaults(in typeDescriptionToScopeMap: [TypeDescription: Scope], emittingModule: EmittingModule?) -> [TypeDescription: ScopeGenerator.FlatParameterMockDefault] {
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
	private func createMockRoot(
		for instantiable: Instantiable,
		scope: Scope,
		generatedMockReason: GeneratedMockReason?,
		mockScopes: MockScopes,
		emittingModule: EmittingModule?,
		receivedPropertiesCache: inout ReceivedPropertiesCache,
		childrenRequiringEachOtherValidation: inout ChildrenRequiringEachOtherValidation,
		promotedScopesValidatedForHiddenReceives: inout Set<ObjectIdentifier>,
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

	enum DependencyTreeGeneratorError: SourceLocatedError {
		/// No production declaration fulfills a type that properties instantiate. `fulfilledByMockOnlyDeclaration` is set
		/// when a `mockOnly` declaration fulfills it; `unreadImports` names, for each file that declares such a property,
		/// the modules it imports that the run read nothing of, or is `nil` when the run cannot tell.
		/// `viewDeclaringModule`, when set, is a module this module depends on through another, whose declaration of the
		/// type a module info's view carries, though the module lists only the module it reaches it through.
		case noInstantiableFound(TypeDescription, referencedBy: [LocatedProperty], fulfilledByMockOnlyDeclaration: Bool, unreadImports: UnreadImportsOfFiles?, viewDeclaringModule: ViewDeclaringModule?)
		case unfulfillableProperties([UnfulfillableProperty])
		/// Reported at the dependency of a root through which its tree calls a seam whose builder for a hole it cannot
		/// fill, with a note at the hole's declaration where its file can be read. See `UnfilledHole`.
		case unfilledHoles([UnfilledHole])
		/// Reported at each receive in a fill's tree, or each repeat of a property on a seam's path in it, that the fill
		/// cannot give inline's value, with a note at the declaration inline would read. See `FillFinding`.
		case fillFindings([FillFinding])
		/// Reported at each `@Instantiated` declaration in the tree of a seam whose module SafeDI does not know that no
		/// production declaration fulfills. See `HoleInSeamOfUnnamedModule`.
		case holesInSeamsOfUnnamedModule([HoleInSeamOfUnnamedModule])
		/// Reported at each `@Received` declaration whose dependency a closer ancestor hides, with a note at the
		/// hiding declaration. See `HiddenReceivedProperty`.
		case hiddenReceivedProperties([HiddenReceivedProperty])
		/// Reported at each `@Received(fulfilledByDependencyNamed:ofType:)` declaration whose label its own type declares
		/// with another type, with a note at that declaration. See `RenameContradictingOwnProperty`.
		case renamesContradictingOwnProperties([RenameContradictingOwnProperty])
		/// Reported at a `@Received` declaration in the tree of a dependency a mock builds beside the mocked type, which
		/// the mocked type's forwarded property fulfills but another receive of its label hides, with a note at that
		/// receive. See `ForwardedPropertyHiddenInPromotedTree`.
		case forwardedPropertyHiddenInPromotedTree(ForwardedPropertyHiddenInPromotedTree)
		/// Reported at a `@Received` declaration in a mock's tree – the mocked type's own, or that of a dependency the mock
		/// builds beside the mocked type – beneath a type in that tree that receives its label in a form no one declaration
		/// provides together with it, with a note at that receive. See `ReceivedPropertyHiddenInMockTree`.
		case receivedPropertyHiddenInMockTree(ReceivedPropertyHiddenInMockTree)
		/// Reported at the first receive of a label that a type a dependency cycle builds again receives in forms the one
		/// value SafeDI hands it cannot provide together, with a note at the declaration of the label the cycle builds the
		/// type again beneath. See `UnpassableCycleLabel`.
		case unpassableCycleLabel(UnpassableCycleLabel)
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
		/// Reported at the hand-written `mock` method of a type whose `mock()` this module also generates.
		case handWrittenMockSharesGeneratedMockName(TypeDescription, declaredAt: [Dependency.DeclarationLocation?], isGeneratedForAdditionalMocksToGenerate: Bool)
		/// Reported at a hand-written `mock` method this module sees for a type another module generates a public mock
		/// for, which this module's mocks reach: `Type.mock()` would be ambiguous.
		case handWrittenMockSharesPublicMockName(TypeDescription, declaringModuleName: String?, declaredAt: [Dependency.DeclarationLocation?])
		/// Reported at the `generateMock:` argument of a `generateMock: .public` type whose public mock cannot be
		/// generated: an enclosing type is narrower than `public`, or a required parameter is (`PublicMockFinding`).
		case publicMockCannotBeGenerated([PublicMockFinding])
		/// Reported at each dependency that a `@Sendable` builder function would read from an `Instantiator`,
		/// `ErasedInstantiator`, or `LazilyInstantiated` declared outside it, with a note at that wrapper when a type
		/// in the tree declares it.
		case nonSendableWrapperCapturedBySendableBuilder([ScopeGenerator.NonSendableWrapperCapture])
		/// Reported at each declaration whose value a call of a seam's generated initializer would drop: the tier the
		/// call reaches omits the parameter it would pass, which the tree built inline would hand on. A note at each
		/// receive of the parameter inside the seam. `callingType` is the type at the root of the tree that makes the
		/// call.
		case seamTierOmitsProvidedValue([ProvidedValueOmission])
		/// A mock tree holds a value for a parameter that the tier of a public mock it calls omits
		/// (`leafTierOmitsProvidedValue`), so the call would pass `nil` where the tree built inline hands the value on.
		case publicMockTierOmitsProvidedValue([ScopeGenerator.PublicMockTierOmission])
		/// A mock tree calls another module's public mock that is generated under another mock condition.
		case publicMockUnderOtherMockCondition([ScopeGenerator.PublicMockCallUnderOtherMockCondition])
		/// Reported at the dependency of a tree this module generates that calls a seam of another module whose files
		/// this run read under a mock condition that module does not guard its mock-only declarations with. See
		/// `SeamModuleMockConditionDifference`.
		case seamModuleMockConditionDiffers([SeamModuleMockConditionDifference])
		/// Reported at the hand-written mock of each type that generated mocks build both with that mock and
		/// without it, in ways one `SafeDIMockConfiguration` struct cannot describe. See `ConfigurationBuiltTwoWays`.
		case configurationBuiltTwoWays([ConfigurationBuiltTwoWays])
		/// Reported at each dependency of one declaration whose label `String` equates with an earlier dependency's.
		/// See `RepeatedDependencyLabel`.
		case repeatedDependencyLabels([RepeatedDependencyLabel])
		/// Reported at each `@Received(fulfilledByDependencyNamed:ofType:)` declaration spelled as the `@Instantiable` macro
		/// rejects. See `RejectedRename`.
		case rejectedRenames([RejectedRename])
		/// Reported at each declaration whose access keeps the generated code from constructing a type, or, when the
		/// declaration's file cannot be read, where this module refers to the construction. See `InaccessibleConstruction`.
		case inaccessibleConstructions([InaccessibleConstruction])
		/// Reported at the declaration of a seam whose generated initializer SafeDI cannot write. See `SeamError`.
		case seam(SeamError)
		/// An error located in source that building a seam's tree threw – an `ErasedInstantiator` whose first generic
		/// argument is not the built type's forwarded properties – collected with the seam errors so each is reported.
		case sourceLocated(any SourceLocatedError)
		/// Errors that validations independent of one another found – those of different roots, for example – each
		/// reported as it would be alone, in source order. See `reportingAll(of:)`.
		case independentErrors([DependencyTreeGeneratorError])

		/// An error reporting every one of `errors`, or `nil` when there are none. The errors are reported in source
		/// order, so neither which are reported nor their order depends on the order of the validations that found
		/// them, which follows the names of what they validate. Each validation must keep nothing from one that threw
		/// that would let it skip work the one that threw did not finish, or which errors are found would depend on
		/// that order too.
		static func reportingAll(of errors: [DependencyTreeGeneratorError]) -> DependencyTreeGeneratorError? {
			// An error that joins errors already is joined error by error, so that an error two joins share – one label
			// that the trees of two mock roots each find unpassable – is reported once.
			let errors = errors.flatMap { error -> [DependencyTreeGeneratorError] in
				if case let .independentErrors(errors) = error {
					errors
				} else {
					[error]
				}
			}
			return if errors.count > 1 {
				.independentErrors(errors)
			} else {
				errors.first
			}
		}

		/// The diagnostics of this error in the groups `independentErrors` joins, leaving out those of the constructions
		/// an `inaccessibleConstructions` error reports, which `independentErrors` merges across the errors it joins.
		/// Every validation that finds inaccessible constructions throws them as an `inaccessibleConstructions` error
		/// of its own, which `reportingAll(of:)` joins directly.
		private var sourceDiagnosticGroupsOtherThanInaccessibleConstructions: [[SourceDiagnostic]] {
			if case .inaccessibleConstructions = self {
				[]
			} else {
				[sourceDiagnostics]
			}
		}

		/// The constructions this error reports as inaccessible, if it is an `inaccessibleConstructions` error.
		private var reportedInaccessibleConstructions: [InaccessibleConstruction] {
			if case let .inaccessibleConstructions(inaccessibleConstructions) = self {
				inaccessibleConstructions
			} else {
				[]
			}
		}

		var sourceDiagnostics: [SourceDiagnostic] {
			switch self {
			case let .independentErrors(errors):
				// The trees of several mock roots can each need one declaration to widen, which is reported once.
				SourceDiagnostic.joiningInSourceOrder(
					errors.flatMap(\.sourceDiagnosticGroupsOtherThanInaccessibleConstructions)
						+ InaccessibleConstruction.sourceDiagnosticGroups(of: errors.flatMap(\.reportedInaccessibleConstructions)),
				)
			case let .inaccessibleConstructions(inaccessibleConstructions):
				// A declaration that several constructions need to widen the same way is reported once.
				SourceDiagnostic.joiningInSourceOrder(InaccessibleConstruction.sourceDiagnosticGroups(of: inaccessibleConstructions))
			case let .seam(seamError):
				seamError.sourceDiagnostics
			case let .sourceLocated(error):
				error.sourceDiagnostics
			case let .seamModuleMockConditionDiffers(differences):
				differences
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .seamTierOmitsProvidedValue(omissions):
				// Each root's omissions arrive in generation order, and the roots in type order; they are reported in
				// source order. Two calls of one seam that drop one provider's value for the same receivers – the calls of
				// two types a tree builds – read the same, so the error is reported once.
				omissions
					.map { providedValueOmission in
						let omission = providedValueOmission.omission
						// A signature records no receiver of the seam's own property, which the call's leaf declares as
						// the seam declares it: that receive is the note.
						let ownReceive = omission.parameter.isPassThrough ? nil : omission.seam.dependencies.first { $0.property == omission.parameter.property }
						// The receives in the calling seam's tree that make the provider its parameter come first, then the
						// receives the call would pass `nil` to, each declaration once.
						let receivers = (omission.providerReceivers + omission.parameter.receivers)
							.map { NotedReceive(declaringType: $0.declaringType, property: $0.property, declarationLocation: $0.declarationLocation) }
							.uniqued()
							+ (ownReceive.map { [NotedReceive(declaringType: omission.seam.concreteInstantiable, property: $0.property, declarationLocation: $0.declarationLocation)] } ?? [])
						return [SourceDiagnostic(
							severity: .error,
							location: providedValueOmission.location,
							message: SeamAccessExplanation.providedValueMessage(omission, callingType: providedValueOmission.callingType, unreadableProviderModuleName: providedValueOmission.unreadableProviderModuleName),
						)] + SeamAccessExplanation.declarationNotes(for: omission.parameter.accessCause, neededLevel: SeamAccessExplanation.neededLevel(for: omission)) + receivers.map { receiver in
							SourceDiagnostic(
								severity: .note,
								location: receiver.declarationLocation,
								message: "`\(receiver.declaringType.asSource)` receives `\(receiver.property.asSource)` here.",
							)
						}
					}
					.uniqued()
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .nonSendableWrapperCapturedBySendableBuilder(captures):
				// The captures arrive in set order. Two whose errors read the same name the same wrapper on the same
				// type, so their notes, at that declaration, read the same too, and the diagnostics come out the same.
				captures
					.map(Self.sourceDiagnostics(of:))
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .repeatedDependencyLabels(repeatedDependencyLabels):
				repeatedDependencyLabels
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .rejectedRenames(rejectedRenames):
				rejectedRenames
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .configurationBuiltTwoWays(configurationsBuiltTwoWays):
				// Sorted by location so the order never depends on map iteration.
				configurationsBuiltTwoWays
					.flatMap(\.sourceDiagnostics)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .publicMockCannotBeGenerated(findings):
				SourceDiagnostic.joiningInSourceOrder(findings.map(\.sourceDiagnostics))
			case let .publicMockUnderOtherMockCondition(calls):
				// One diagnostic per dependency that leads to such a call, in source order.
				calls
					.map(\.sourceDiagnostic)
					.uniqued()
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .publicMockTierOmitsProvidedValue(omissions):
				// Two calls that drop one provider's value for the same receivers read the same, and are reported once.
				omissions
					.map(\.sourceDiagnostics)
					.uniqued()
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .handWrittenMockSharesPublicMockName(typeDescription, declaringModuleName, declaredAt):
				// Sorted by location so the order never depends on map iteration.
				declaredAt
					.map {
						SourceDiagnostic(
							severity: .error,
							location: $0,
							message: "`\(typeDescription.asSource)` has a public `mock()` generated by \(declaringModuleName.map { "`\($0)`" } ?? "its module"); a hand-written `mock` here makes every call ambiguous. Give it another name and pass it as `customMockName`.",
						)
					}
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
			case let .noInstantiableFound(typeDescription, referencedBy, fulfilledByMockOnlyDeclaration, unreadImports, viewDeclaringModule):
				// Sorted by location so the order never depends on map iteration.
				referencedBy.map { locatedProperty in
					SourceDiagnostic(
						severity: .error,
						location: locatedProperty.declarationLocation,
						message: Self.noInstantiableFoundMessage(
							typeDescription: typeDescription,
							referencingProperty: locatedProperty.property,
							fulfilledByMockOnlyDeclaration: fulfilledByMockOnlyDeclaration,
							unreadImports: unreadImports.map { unreadImports in
								(
									integration: unreadImports.integration,
									importsModuleNotRead: locatedProperty.declarationLocation.flatMap { unreadImports.importsModuleNotReadByFilePath[$0.filePath] },
								)
							},
							viewDeclaringModule: viewDeclaringModule,
						),
					)
				}
				.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .holesInSeamsOfUnnamedModule(holes):
				holes
					.map(\.sourceDiagnostic)
					.sorted(by: SourceDiagnostic.precedesInSourceOrder)
			case let .fillFindings(fillFindings):
				fillFindings
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .unfilledHoles(unfilledHoles):
				unfilledHoles
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
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
			case let .renamesContradictingOwnProperties(renamesContradictingOwnProperties):
				renamesContradictingOwnProperties
					.map(\.sourceDiagnostics)
					.sorted { SourceDiagnostic.precedesInSourceOrder($0[0], $1[0]) }
					.flatMap(\.self)
			case let .forwardedPropertyHiddenInPromotedTree(forwardedPropertyHiddenInPromotedTree):
				forwardedPropertyHiddenInPromotedTree.sourceDiagnostics
			case let .receivedPropertyHiddenInMockTree(receivedPropertyHiddenInMockTree):
				receivedPropertyHiddenInMockTree.sourceDiagnostics
			case let .unpassableCycleLabel(unpassableCycleLabel):
				Self.sourceDiagnostics(of: unpassableCycleLabel)
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
			}
		}

		/// What each integration whose modules are listed by hand does to list a module an error has just named.
		static let listModuleRemedy = "list its `<name>_safedi` target in this target’s `safedi_deps` under Bazel, list its module in the `dependencies:` of this target’s `SafeDI.preCompileScript` under Tuist, or list its `.safedi` file in the file you pass to `--dependent-module-info-file-path` in a custom build."

		/// The last remedy for a type no `@Instantiable` declaration a seam's caller can see fulfills: what each
		/// integration does to read the module that declares one.
		static let fulfillingDeclarationInAnotherModuleRemedy = "or, if such a declaration is in another module, make that module one SafeDI reads for this target: add its target to this target's `dependencies` in `Package.swift`, declare that module with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target's `safedi_deps` under Bazel, or give its target `SafeDI.preCompileScript` and list its module in the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist."

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

		/// Whether each file that instantiates a type no declaration fulfills imports a module the run read nothing of, and
		/// how the run learns of the modules it reads.
		struct UnreadImportsOfFiles {
			let integration: UnreadImports.Integration
			/// Whether each file imports a module the run read nothing of, by the file's path, for each file whose imports
			/// the run knows.
			let importsModuleNotReadByFilePath: [String: Bool]
		}

		/// - Parameter unreadImports: How the run learns of the modules it reads, with whether the file that declares
		///   `referencingProperty` imports a module the run read nothing of (`nil` when the run does not know what the file
		///   imports, as for another module's file), or `nil` when the run cannot tell which modules it could have read (the
		///   Xcode project plugin's, or one run by hand).
		private static func noInstantiableFoundMessage(
			typeDescription: TypeDescription,
			referencingProperty: Property,
			fulfilledByMockOnlyDeclaration: Bool,
			unreadImports: (integration: UnreadImports.Integration, importsModuleNotRead: Bool?)?,
			viewDeclaringModule: ViewDeclaringModule?,
		) -> String {
			let typeName = typeDescription.asSource
			let reference = "`\(typeName)`, which @\(Dependency.Source.instantiatedRawValue) property `\(referencingProperty.asSource)` instantiates"
			if let viewDeclaringModule {
				// A module info's view names the module, though it fulfills no type of this module's trees: list it.
				return "No @\(InstantiableVisitor.macroName) declaration of a module this module lists fulfills \(reference). `\(typeName)` is declared in `\(viewDeclaringModule.moduleName)`, which this module reaches only through `\(viewDeclaringModule.throughModuleName)`. Add `\(viewDeclaringModule.moduleName)` beside `\(viewDeclaringModule.throughModuleName)` among this module’s SafeDI dependencies: \(listModuleRemedy)"
			} else if fulfilledByMockOnlyDeclaration {
				return "No production @\(InstantiableVisitor.macroName) declaration fulfills \(reference). A `mockOnly: true` declaration fulfills it, but is used only to generate mocks. Add a production @\(InstantiableVisitor.macroName) declaration that fulfills `\(typeName)`."
			} else {
				// The usual cause, a declaration SafeDI reads that is not decorated, leads.
				var message = "No @\(InstantiableVisitor.macroName) type or extension fulfills \(reference). Decorate `\(typeName)`, or an extension of it, with @\(InstantiableVisitor.macroName), or list `\(typeName)` in the `fulfillingAdditionalTypes` of an @\(InstantiableVisitor.macroName) type that conforms to it."
				if let unreadImports {
					// A file that imports only modules the run read names no type of a module the run could be given.
					if unreadImports.importsModuleNotRead ?? true {
						message += " " + fulfillingDeclarationInModuleNotReadRemedy(typeName: typeName, integration: unreadImports.integration)
					}
				} else {
					message += " " + fulfillingDeclarationInTargetNotReadRemedy(typeName: typeName)
				}
				return message
			}
		}

		/// The sentences that say how `integration` gives the run the module that declares a type that fulfills the type
		/// named `typeName`, when that module is one the run read nothing of. They name none of the modules the file
		/// imports: a file imports the SDK's and the toolchain's modules too, which SafeDI cannot tell from the user's.
		private static func fulfillingDeclarationInModuleNotReadRemedy(typeName: String, integration: UnreadImports.Integration) -> String {
			switch integration {
			case .moduleInfo:
				"If a declaration that fulfills `\(typeName)` is in another module, run SafeDI on that module and list it among this module’s SafeDI dependencies: under Bazel, declare it with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target’s `safedi_deps`; under Tuist, give its target `SafeDI.preCompileScript` and list it in the `dependencies:` of this target’s `SafeDI.preCompileScript`; in a custom build, list its `.safedi` file in the file you pass to `--dependent-module-info-file-path`."
			case .targetGraph:
				"If a declaration that fulfills `\(typeName)` is in another target, add that target to this target’s `dependencies` in `Package.swift`: SafeDI reads only the targets this target depends on. For a target of a package fetched from a URL, add the package’s checkout directory to `additionalDirectoriesToInclude` in a `#\(SafeDIConfigurationVisitor.macroName)` instead."
			}
		}

		/// The sentence that says how a run that cannot tell which modules it could have read (the Xcode project plugin's,
		/// or one run by hand) reads the target that declares a type that fulfills the type named `typeName`.
		private static func fulfillingDeclarationInTargetNotReadRemedy(typeName: String) -> String {
			"If a declaration that fulfills `\(typeName)` is in another target, add that target’s folder to `additionalDirectoriesToInclude` in this target’s `#\(SafeDIConfigurationVisitor.macroName)`, or, in a SafeDITool run by hand, list the `.safedi` file of its module in the file you pass to `--dependent-module-info-file-path`."
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
			// A seam's generated initializer that takes the property as a `@Sendable` closure captures what the call passes, as
			// the `@Sendable` builder function inside the seam's tree that reads it would built inline.
			let capturingFunction = if let seamType = capture.capturingSeamType {
				"`\(seamType.asSource)`'s generated initializer takes `\(capture.receivedProperty.label)` as a `@Sendable` closure, because a `@Sendable` function inside `\(seamType.asSource)`'s tree reads it, and that closure"
			} else if capture.capturingFillIsPassedOn {
				"The function SafeDI generates to fill the builder for `\(capture.sendableBuilder.asSource)` on `\(capture.sendableBuilderDeclaringType.asSource)` is passed to a seam from inside a `@Sendable` function, or to a seam that takes it `@Sendable`, so it is `@Sendable` too, and it"
			} else if let fillSeamType = capture.capturingFillSeamType {
				"`\(fillSeamType.asSource)`'s tree builds `\(capture.sendableBuilder.asSource)` on `\(capture.sendableBuilderDeclaringType.asSource)` inside a `@Sendable` function, so the function SafeDI generates to fill its builder is `@Sendable` too, and it"
			} else {
				"SafeDI builds `\(capture.sendableBuilder.asSource)` on `\(capture.sendableBuilderDeclaringType.asSource)` in a `@Sendable` function\(sendableBuilderReason), which"
			}
			let error = SourceDiagnostic(
				severity: .error,
				location: capture.declarationLocation,
				message: "@\(Dependency.Source.receivedRawValue) property `\(capture.receivedProperty.asSource)` cannot be received inside a `@Sendable` function in chain: \(capture.chain.map(\.asSource).joined(separator: " -> ")). "
					+ "\(capturingFunction) cannot capture \(capturedProperty), because `\(wrapperType.asSource)` is not `Sendable`. "
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

		/// A declaration whose access keeps the code SafeDI generates in one module from constructing a type: the type,
		/// a type that encloses it, the method that constructs it, or an extension one of those takes its level from.
		struct InaccessibleConstruction: Hashable {
			/// The type the generated code constructs.
			let constructedType: TypeDescription
			/// The name the declaring module gives `constructedType`, when this run spells it with the module's name because
			/// another module declares a type of that name (`Instantiable.declaredName`). Widening such a type can make the
			/// two compete in this module, so the error leads with a remedy that keeps it from this module, when there is one.
			let constructedTypeDeclaredName: TypeDescription?
			/// The declaration that must widen, with the level it has.
			let accessNeed: AccessNeed
			/// What the generated code needs of the declaration.
			let requirement: AccessRequirement
			/// The module the generated code compiles in.
			let emittingModule: ModuleIdentity
			/// The module that declares the declaration.
			let declaringModule: ModuleIdentity
			/// Where the declaration begins, when its file can be read where it is recorded, so an editor can open it.
			let readableDeclarationLocation: Dependency.DeclarationLocation?
			/// Where this module refers to what leads to the construction.
			let referenceLocation: Dependency.DeclarationLocation?
			/// Where the constructed type is declared.
			let constructedTypeDeclarationLocation: Dependency.DeclarationLocation?
			/// In a production tree, the type another module declares whose module could construct the declaration
			/// instead, were the type declared with `generateDependencyTree: true`, which the fix offers.
			var seamRemedy: SeamRemedy?
			/// In a production tree of a module SafeDI cannot name, the seam another module declares whose tree the module
			/// builds inline, which leads to the construction.
			var inlineSeam: InlineSeam?

			/// In a mock's tree, what the outermost type another module declares on the path to the construction offers
			/// (`Construction.publicMockCandidate`), which the fix says.
			var publicMockCandidate: PublicMockCandidate?
			/// The type whose mock makes the construction, with where it is declared, or `nil` for production code.
			var mockRoot: MockRoot?

			/// A type another module declares, and that module, which would build the type's tree, and construct the
			/// declaration there, were the type declared with `generateDependencyTree: true`: see
			/// `DependencyTreeGenerator.seamRemedy(offeredBy:toWiden:declaredIn:extendedTypes:)`.
			struct SeamRemedy: Hashable {
				let type: TypeDescription
				let moduleName: String
			}

			/// A seam another module declares that a production tree builds inline because SafeDI cannot name the module
			/// the tree is generated in – a run given no module name, as a target the Xcode project plugin builds is – so
			/// the tree cannot call the initializer generated for the seam, with where the module refers to what leads to
			/// the seam.
			struct InlineSeam: Hashable {
				let type: TypeDescription
				let referenceLocation: Dependency.DeclarationLocation?
			}

			/// The type whose mock makes a construction.
			struct MockRoot: Hashable {
				let type: TypeDescription
				let declarationLocation: Dependency.DeclarationLocation?
			}

			/// The diagnostics of `inaccessibleConstructions`, each in a group of its own: one error for each declaration to
			/// widen (`merging(_:)`), and one for each seam that the trees build inline (`InlineSeam`) where a construction in
			/// its tree is inaccessible, at the earliest reference to it in source order, which says why the tree is built
			/// inline and names the first declaration in source order in the seam's tree that keeps it from compiling, of
			/// a type other than the seam where there is one. Neither depends on the order of `inaccessibleConstructions`.
			static func sourceDiagnosticGroups(of inaccessibleConstructions: [InaccessibleConstruction]) -> [[SourceDiagnostic]] {
				var inlineSeamErrors = [TypeDescription: (referenceLocation: Dependency.DeclarationLocation?, namedConstruction: InaccessibleConstruction)]()
				for case let (inaccessibleConstruction, inlineSeam?) in inaccessibleConstructions.map({ ($0, $0.inlineSeam) }) {
					inlineSeamErrors[inlineSeam.type] = inlineSeamErrors[inlineSeam.type].map { error in
						(
							referenceLocation: Dependency.DeclarationLocation.precedesInSourceOrder(inlineSeam.referenceLocation, error.referenceLocation) ? inlineSeam.referenceLocation : error.referenceLocation,
							namedConstruction: inaccessibleConstruction.isNamedBefore(error.namedConstruction, inTreeOf: inlineSeam.type) ? inaccessibleConstruction : error.namedConstruction,
						)
					} ?? (referenceLocation: inlineSeam.referenceLocation, namedConstruction: inaccessibleConstruction)
				}
				return merging(inaccessibleConstructions).map { [$0.sourceDiagnostic] }
					+ inlineSeamErrors.map { seamType, error in
						[error.namedConstruction.inlineSeamDiagnostic(of: seamType, at: error.referenceLocation)]
					}
			}

			/// Whether an error about the seam `seamType`, built inline, names this construction rather than `other`: one of
			/// a type other than the seam before one of the seam itself, then the one whose declaration to widen comes first
			/// in source order, then the one whose constructed type is declared first. Two constructions that tie need one
			/// declaration to widen for one type, and the error reads the same whichever it names.
			private func isNamedBefore(_ other: InaccessibleConstruction, inTreeOf seamType: TypeDescription) -> Bool {
				// Whether the construction is of the seam, then each location's file and its line and column as one number.
				func sortKey(of construction: InaccessibleConstruction) -> (Int, String, Int, String, Int) {
					let declarationLocation = construction.accessNeed.access.declarationStartLocation
					let typeLocation = construction.constructedTypeDeclarationLocation
					return (
						construction.constructedType == seamType ? 1 : 0,
						declarationLocation?.filePath ?? "",
						((declarationLocation?.line ?? 0) << 32) | (declarationLocation?.column ?? 0),
						typeLocation?.filePath ?? "",
						((typeLocation?.line ?? 0) << 32) | (typeLocation?.column ?? 0),
					)
				}
				return sortKey(of: self) < sortKey(of: other)
			}

			/// The error about the seam `seamType`, which a production tree builds inline because SafeDI cannot name the
			/// module the tree is generated in, at `referenceLocation`, where this module refers to what leads to the seam,
			/// naming the declaration this construction needs to widen and the level it has, in a sentence of its own, since
			/// the declaration's subject phrase can be an enclosing type's or an extension's. It leads with the remedy every
			/// such run can apply, widening the tree's declarations as the error at each declaration says, and then says how
			/// SafeDI comes to know the seam's module. Only a run that names no module reports this, which is one of the Xcode
			/// project plugin or a SafeDITool run by hand: the Swift package plugin's target graph, Bazel's required
			/// `module_name`, and the Tuist script's `--module-name` name every module. A run by hand needs only the seam's
			/// module named, since a run that names no module calls the initializer of a seam a module info file records. A
			/// single `error:` line, since Xcode drops notes from build-tool output.
			private func inlineSeamDiagnostic(
				of seamType: TypeDescription,
				at referenceLocation: Dependency.DeclarationLocation?,
			) -> SourceDiagnostic {
				let seamName = "`\(seamType.asSource)`"
				let reachedDeclaration = "\(declarationPhrases.subject) is `\(accessNeed.level.spelling)`, so that tree cannot be built here."
				return SourceDiagnostic(
					severity: .error,
					location: referenceLocation,
					message: "\(seamName) is declared with `generateDependencyTree: true`, but SafeDI does not know which module declares \(seamName), so this run builds \(seamName)’s tree inline. \(reachedDeclaration) Make the types in \(seamName)’s tree and their initializers `\(AccessLevel.package.spelling)`, \(DependencyTreeGenerator.DependencyTreeGeneratorError.unverifiedPackageAccessNeed), or `\(AccessLevel.public.spelling)` where their module and this one are in different packages. For this module to call the initializer SafeDI generates for \(seamName) instead, SafeDI must know \(seamName)’s module. \(DependencyTreeGenerator.DependencyTreeGeneratorError.xcodeProjectPluginCannotNameModules) In a SafeDITool run by hand, list the `.safedi` file of \(seamName)’s module, written with `--module-name` and `--module-info-output`, in the file you pass to `--dependent-module-info-file-path`.",
				)
			}

			/// `inaccessibleConstructions`, in no particular order, with those that need one declaration to widen the
			/// same way – the constructions of several roots' trees, or of several types the declaration encloses –
			/// merged into the one with the earliest reference in source order, or, of those with one reference, the one
			/// whose constructed type is declared first. An error at a reference therefore names the type that reference
			/// constructs, and neither which roots reach the declaration nor the order in which they are checked changes
			/// what is reported.
			static func merging(_ inaccessibleConstructions: [InaccessibleConstruction]) -> [InaccessibleConstruction] {
				var mergedByDeclaration = [MergeKey: InaccessibleConstruction]()
				for inaccessibleConstruction in inaccessibleConstructions {
					let key = MergeKey(
						access: inaccessibleConstruction.accessNeed.access,
						requirement: inaccessibleConstruction.requirement,
						declaringModule: inaccessibleConstruction.declaringModule,
					)
					mergedByDeclaration[key] = mergedByDeclaration[key].map { $0.merged(with: inaccessibleConstruction) } ?? inaccessibleConstruction
				}
				return Array(mergedByDeclaration.values)
			}

			/// What identifies the declaration an inaccessible construction needs to widen, and how. The access
			/// declaration records where the declaration begins, which no other declaration shares.
			private struct MergeKey: Hashable {
				let access: AccessDeclaration
				let requirement: AccessRequirement
				let declaringModule: ModuleIdentity
			}

			/// Of this construction and `other`, which needs the same declaration to widen the same way, the one an error
			/// about the declaration reports. Two constructions whose types are declared at one location construct one
			/// type and report the same error. The error offers a seam only when both offer the same one: declaring one
			/// type a seam must keep every construction it reports out of this module.
			private func merged(with other: InaccessibleConstruction) -> InaccessibleConstruction {
				let otherIsReportedFirst = if other.referenceLocation == referenceLocation {
					if other.constructedTypeDeclarationLocation == constructedTypeDeclarationLocation {
						// The trees of two mock roots reach the construction through one reference: the error names the mock
						// declared first.
						Dependency.DeclarationLocation.precedesInSourceOrder(other.mockRoot?.declarationLocation, mockRoot?.declarationLocation)
					} else {
						Dependency.DeclarationLocation.precedesInSourceOrder(other.constructedTypeDeclarationLocation, constructedTypeDeclarationLocation)
					}
				} else {
					Dependency.DeclarationLocation.precedesInSourceOrder(other.referenceLocation, referenceLocation)
				}
				var merged = otherIsReportedFirst ? other : self
				merged.seamRemedy = seamRemedy == other.seamRemedy ? seamRemedy : nil
				return merged
			}

			/// How an error names the declaration that must widen (`subject`), says what the generated code cannot do
			/// without it (`inability`), and names it in the fix (`fixedDeclaration`).
			private var declarationPhrases: (subject: String, inability: String, fixedDeclaration: String) {
				let constructedTypeName = "`\(constructedType.asSource)`"
				func name(of member: AccessNeed.Member) -> String {
					switch member {
					case .initializer:
						"\(constructedTypeName)’s initializer"
					case .instantiateMethod:
						"`\(constructedType.asSource).\(InstantiableVisitor.instantiateMethodName)()`"
					case let .mockMethod(name):
						"`\(constructedType.asSource).\(name)()`"
					}
				}
				let subject: String
				let inability: String
				let fixedDeclaration: String
				switch accessNeed.declaration {
				case let .type(type):
					if type == constructedType || type == constructedTypeDeclaredName {
						subject = constructedTypeName
						inability = "construct it"
						fixedDeclaration = constructedTypeName
					} else {
						subject = "`\(type.asSource)`, which encloses \(constructedTypeName),"
						inability = "construct \(constructedTypeName)"
						fixedDeclaration = "`\(type.asSource)`"
					}
				case let .extensionDeclaringType(type):
					subject = type == constructedType
						? "The extension that declares \(constructedTypeName)"
						: "The extension that declares `\(type.asSource)`, which encloses \(constructedTypeName),"
					inability = "construct \(constructedTypeName)"
					fixedDeclaration = "the extension"
				case let .extensionDeclaringMember(member):
					subject = "The extension that declares \(name(of: member))"
					inability = "call \(name(of: member))"
					fixedDeclaration = "the extension"
				case let .member(member):
					subject = name(of: member)
					inability = "call it"
					fixedDeclaration = member == .initializer ? "the initializer" : name(of: member)
				}
				return (subject, inability, fixedDeclaration)
			}

			/// A single `error:` line, since Xcode drops notes from build-tool output. When the declaration's file can
			/// be read, it is reported there, with a fix-it that gives the declaration the level the generated code
			/// needs. Otherwise – in a build that hands SafeDITool another module's declarations but not its files,
			/// such as a sandboxed Bazel action, or a `.safedi` file from another machine – it is reported where this
			/// module refers to the construction, and names the module that must change.
			var sourceDiagnostic: SourceDiagnostic {
				let (subject, inability, fixedDeclaration) = declarationPhrases
				let module = emittingModule.moduleName.map { "module `\($0)`" } ?? "this module"
				// A mock's construction names the mock, whose tree the user did not write.
				let emitter = mockRoot.map { "the mock of `\($0.type.asSource)`, generated in \(module)," } ?? "\(module),"
				let reason = switch requirement {
				case .internal:
					if let mockRoot {
						"the mock of `\(mockRoot.type.asSource)`, which SafeDI generates in another file of \(module), cannot \(inability)"
					} else {
						"the code SafeDI generates in another file of \(module) cannot \(inability)"
					}
				case .package:
					"\(emitter) another module of the same package, cannot \(inability) in the code SafeDI generates"
				case .public:
					// Across a named module SafeDI is told no package of, SafeDI cannot say the two are in different packages.
					if ModuleIdentity.namesOfModulesWithoutPackage(emitter: emittingModule, declarer: declaringModule, requirement: requirement).isEmpty {
						"\(emitter) in another package, cannot \(inability) in the code SafeDI generates"
					} else {
						"\(emitter) which SafeDI is not told is in the same package, cannot \(inability) in the code SafeDI generates"
					}
				case .packageUnverified:
					"\(emitter) which SafeDI cannot tell is in the same package, cannot \(inability) in the code SafeDI generates"
				}
				let level = AccessLevel.spelling(satisfying: requirement)
				// Reported in this module, the error names the module whose declaration must change.
				let declaringModuleName = readableDeclarationLocation == nil ? declaringModule.moduleName.map { " in module `\($0)`" } ?? "" : ""
				// A type another module declares could have that module build its tree, which reaches the declaration.
				let seamRemedyClause = seamRemedy.map { "declare `\($0.type.asSource)` with `generateDependencyTree: true`, so that module `\($0.moduleName)` generates its tree and this module calls the initializer it generates" }
				let seamRemedyText = seamRemedyClause.map { ", or \($0)" } ?? ""
				// A mock could call a public mock of the type another module declares instead of building its tree.
				let publicMockRemedyClause: String? = if case let .withoutMock(type, declaringModuleName, needsPublicDeclaration, isSeam)? = publicMockCandidate {
					(needsPublicDeclaration
						? "declare `\(type.asSource)` `public` with `generateMock: .public`"
						: "give `\(type.asSource)` a public mock: `generateMock: .public`, or a hand-written public `mock`")
						// A seam's tree is one a mock builds inline, which the user may not expect.
						+ (isSeam ? ": mocks build a seam's tree inline, and this mock would call the mock \(declaringModuleName.map { "`\($0)`" } ?? "its module") generates instead" : "")
				} else {
					nil
				}
				let publicMockRemedy = publicMockRemedyClause.map { ", or \($0)" } ?? ""
				// Widening one of several types of a name lets the module name it, and widening a second makes them
				// compete, so the remedy that keeps the type out of this module comes first, and no fix-it widens it.
				if let constructedTypeDeclaredName, let leadingRemedy = publicMockRemedyClause ?? seamRemedyClause {
					return SourceDiagnostic(
						severity: .error,
						location: readableDeclarationLocation ?? referenceLocation,
						message: "\(subject) is `\(accessNeed.level.spelling)`\(declaringModuleName), so \(reason). \(leadingRemedy.prefix(1).uppercased())\(leadingRemedy.dropFirst()). Making \(fixedDeclaration) `\(level)` instead also needs a new name, if \(module) can then name another type called `\(constructedTypeDeclaredName.asSource)`.",
					)
				}
				let fix = switch requirement {
				case .internal, .package:
					"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix\(seamRemedyText)\(publicMockRemedy)."
				case .public:
					// Across a named module SafeDI is told no package of, a `package` declaration needs `public` unless the
					// module belongs in the other's package, which the declaration's level makes the likelier fix. A
					// narrower declaration needs widening either way, so `public`, which its fix-it inserts, comes first.
					if let packageNameRemedy = ModuleIdentity.packageNameRemedy(emitter: emittingModule, declarer: declaringModule, requirement: requirement, declaredLevel: accessNeed.level) {
						"\(packageNameRemedy.prefix(1).uppercased())\(packageNameRemedy.dropFirst()), or make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix\(seamRemedyText)\(publicMockRemedy)."
					} else if let packageNameAndAccessRemedy = ModuleIdentity.packageNameAndAccessRemedy(emitter: emittingModule, declarer: declaringModule, requirement: requirement, declaredLevel: accessNeed.level), seamRemedyClause == nil, publicMockRemedyClause == nil {
						"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix, or, \(packageNameAndAccessRemedy)."
					} else if let packageNameAndAccessRemedy = ModuleIdentity.packageNameAndAccessRemedy(emitter: emittingModule, declarer: declaringModule, requirement: requirement, declaredLevel: accessNeed.level) {
						// A remedy after the package-name remedy would read as part of its "if" clause, so three or more
						// remedies are joined with semicolons.
						SeamAccessExplanation.joined(["make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix", packageNameAndAccessRemedy] + [seamRemedyClause, publicMockRemedyClause].compactMap(\.self))
					} else {
						"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix\(seamRemedyText)\(publicMockRemedy)."
					}
				case .packageUnverified:
					"Make \(fixedDeclaration) `\(level)`\(declaringModuleName) to fix, \(DependencyTreeGeneratorError.unverifiedPackageAccessNeed), or `\(AccessLevel.public.spelling)` if the two modules are in different packages\(seamRemedyText)\(publicMockRemedy)."
				}
				let message: String
				// Only a mock's construction has a `.publicMockOfUnknownModule` candidate, and it is explained with its mock root.
				if case let .publicMockOfUnknownModule(type, emittingModuleIsUnknown)? = publicMockCandidate, let mockRoot {
					// `publicMockNotCallableFromThisView`: the type's public mock is the fix, which SafeDI cannot call here.
					let typeName = "`\(type.asSource)`"
					let mockReason = "the mock of `\(mockRoot.type.asSource)`, which builds \(typeName)’s tree here, cannot \(inability): \(typeName) has a public `mock()`, but SafeDI does not know which module declares \(typeName), so this run cannot call it"
					// Whether a mock can call the public mock depends on the declaring module's name alone: a run that names no
					// module calls the public mock of a module whose module info names it, and naming this run would not name
					// the declaring module. A Swift package target's run reads that name from the target graph. A run that
					// names its module reaches such a type only through a directory a `#SafeDIConfiguration` adds, or a file
					// no target of the plugin's graph lists, since every module info names its module.
					if emittingModuleIsUnknown {
						// Widening works as for any construction, so that remedy and its fix-it come first.
						message = "\(subject) is `\(accessNeed.level.spelling)`\(declaringModuleName), so \(mockReason). \(fix) To call `\(type.asSource).mock()` instead, build these mocks in a Swift package target, or, in a SafeDITool run by hand, list the `.safedi` file of \(typeName)’s module, written with `--module-name` and `--module-info-output`, in the file you pass to `--dependent-module-info-file-path`."
					} else {
						let access = "\(subject.hasPrefix("The ") ? "the " + subject.dropFirst(4) : subject) is `\(accessNeed.level.spelling)`"
						return SourceDiagnostic(
							severity: .error,
							location: readableDeclarationLocation ?? referenceLocation,
							message: "\(typeName) has a public `mock()`, but SafeDI does not know which module declares \(typeName), so this run cannot call it, and \(access): it is declared in a directory a `#SafeDIConfiguration` adds, or in a file no target of the plugin's graph lists. Declare it in a file of a module SafeDI knows.",
						)
					}
				} else {
					message = "\(subject) is `\(accessNeed.level.spelling)`\(declaringModuleName), so \(reason). \(fix)"
				}

				if let readableDeclarationLocation {
					// A modifier is replaced, and one is inserted where the declaration begins when it spells none.
					let fixIt = accessNeed.access.modifierRange.map { SourceDiagnostic.FixIt(range: $0, replacement: level) }
						?? SourceDiagnostic.FixIt(
							range: Dependency.SourceRange(
								startLine: readableDeclarationLocation.line,
								startColumn: readableDeclarationLocation.column,
								endLine: readableDeclarationLocation.line,
								endColumn: readableDeclarationLocation.column,
							),
							replacement: "\(level) ",
						)
					return SourceDiagnostic(severity: .error, location: readableDeclarationLocation, message: message, fixIts: [fixIt])
				} else {
					return SourceDiagnostic(severity: .error, location: referenceLocation, message: message)
				}
			}
		}

		/// A receive a diagnostic notes: the type that declares it, the property it receives, and where.
		private struct NotedReceive: Hashable {
			let declaringType: TypeDescription
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
		}

		/// A value a call of a seam's generated initializer would drop (`ScopeGenerator.SeamTierOmission`), as reported.
		struct ProvidedValueOmission {
			let omission: ScopeGenerator.SeamTierOmission
			/// The type at the root of the tree that makes the call.
			let callingType: TypeDescription
			/// Where the error is reported: the provider's declaration, or, when its file cannot be read, where the
			/// module refers to what leads to the call.
			let location: Dependency.DeclarationLocation?
			/// The module that declares the provider, when the provider's file cannot be read and that module is known.
			let unreadableProviderModuleName: String?
		}

		/// A call of the initializer SafeDI generated for a seam of another module, whose signature this run computed
		/// from that module's files as it parsed them, under its own mock condition, while the module computed it under
		/// another: a mock method in a block that only one of the conditions selects can prove a parameter's type, so
		/// the two signatures can differ. Reported at the dependency that calls the seam.
		struct SeamModuleMockConditionDifference {
			let seam: TypeDescription
			let seamModule: ModuleIdentity
			let seamModuleMockCondition: MockCondition
			let callingModule: ModuleIdentity
			let callingModuleMockCondition: MockCondition
			/// The first dependency, in source order, that instantiates the seam in a tree this module generates.
			let callingDependencyLocation: Dependency.DeclarationLocation?

			var sourceDiagnostic: SourceDiagnostic {
				func name(of module: ModuleIdentity) -> String {
					module.moduleName.map { "`\($0)`" } ?? "this module"
				}
				func spelling(of mockCondition: MockCondition) -> String {
					mockCondition.conditionalCompilation.map { "`\($0)`" } ?? "no condition"
				}
				let seamModuleName = name(of: seamModule)
				let callingModuleName = name(of: callingModule)
				return SourceDiagnostic(
					severity: .error,
					location: callingDependencyLocation,
					message: "\(callingModuleName) calls the initializer SafeDI generated for `\(seam.asSource)` in module \(seamModuleName), whose signature SafeDI computes from \(seamModuleName)'s declarations as \(seamModuleName) reads them, mock-only declarations under \(seamModuleName)'s mock condition included. \(seamModuleName) guards its mocks with \(spelling(of: seamModuleMockCondition)) and \(callingModuleName) with \(spelling(of: callingModuleMockCondition)), so \(callingModuleName) cannot read them as \(seamModuleName) does. Use the same `mockConditionalCompilation` in both modules.",
				)
			}
		}

		/// A seam whose generated initializer SafeDI cannot write, reported at the seam's declaration with a note at
		/// each receive involved.
		struct SeamError {
			/// A receive in the seam's tree, as the seam's signature sees it.
			struct Receiver: Hashable {
				/// The property the receive takes from outside the seam: the received property, or an alias's
				/// fulfilling property.
				let property: Property
				/// The type that declares the receive.
				let declaringType: TypeDescription
				let declarationLocation: Dependency.DeclarationLocation?
				/// The alias's own property when the receive is an alias's fulfilling property, else `nil`.
				let aliasProperty: Property?
				/// Whether the receive is a parameter of an extension's `instantiate(…)` method, which has no
				/// only-if-available form.
				let isInstantiateMethodParameter: Bool

				var asExplanationReceiver: SeamAccessExplanation.Receiver {
					SeamAccessExplanation.Receiver(declaringType: declaringType, aliasProperty: aliasProperty, isInstantiateMethodParameter: isInstantiateMethodParameter)
				}
			}

			/// Which of the seam's own properties an omitted parameter is, or `none` for a pass-through.
			enum OwnParameter: Equatable {
				case none
				case forwarded
				case required
			}

			/// What a label collision's message says to do.
			enum LabelCollisionRemedy: Equatable {
				/// The forms are of different types (`User` beside `Name`, or beside `Instantiator<User>`, which no form
				/// of `User` provides): rename one, or instantiate one inside the tree.
				case rename
				/// The forms name two wrapper kinds: receive one kind everywhere.
				case receiveOneWrapperKind
				/// Receive the label the same way everywhere; no form the inlined validation accepts provides the others
				/// (a required optional by-value receive beside a wrapper: the wrapper's instance is non-optional).
				case receiveTheSameWay
				/// Receive the label the same way everywhere, or declare the form that provides the others on the seam,
				/// spelled as a receiver spells it: the wrapper of the one kind received, else the by-value property.
				case declareProvidingForm(String)
			}

			/// Why the seam's generated initializer cannot take the parameters its tree needs. Each case names the
			/// parameters involved, which `parameterLabels(namedBy:about:)` reads; no other kind names one.
			enum ParameterKind {
				/// Two receives of one label with different types, which the seam's generated initializer cannot both
				/// take as parameters: it passes each dependency to its receivers by label, as a root's does.
				case parametersShareLabel(label: String, receivers: [Receiver], remedy: LabelCollisionRemedy)
				/// A tier of the generated initializer is wider than the access SafeDI can prove for a required
				/// parameter's type (`TypeAccessProof`), so it cannot take the parameter, and cannot leave it out either:
				/// a pass-through some receiver requires, or the seam's own required `@Received` or `@Forwarded`
				/// property. `tier` is the widest tier, at the seam type's access; `parameterLevel` is the parameter's own
				/// tier access, and `cause` how its narrowest type is proven.
				case tierOmitsRequiredParameter(parameter: Property, tier: AccessLevel, parameterLevel: AccessLevel, receivers: [Receiver], ownParameter: OwnParameter, cause: TypeAccessProof.Cause?)
				/// The seam declares an initializer that can be called with the argument labels of a tier of the generated
				/// initializer, whose parameters are `parameters`: a call with those labels resolves to the hand-written
				/// initializer or is ambiguous, whatever the types. The macro cannot report it: it cannot see the
				/// pass-throughs.
				case initializerCollides(parameters: [SeamSignature.Parameter], builderLabels: [String], handWrittenInitializer: Initializer)
			}

			enum Kind {
				/// The seam's generated initializer cannot take the parameters its tree needs, for the reason given.
				case parameters(ParameterKind)
				/// The signatures of `seams`, which reach one another, changed on every pass up to the limit
				/// (`seamSignatureComputationLimit(forComponentOf:)`), which the argument in `seamSignatures` says no
				/// input reaches: a guard against a shape the argument misses, which is then reported rather than
				/// computed with a stale signature.
				case signaturesDidNotSettle(seams: [TypeDescription])
				/// The seam's signature, computed over the declarations the modules that call it see, differs from the one
				/// computed over what this run sees, and `declaration` is one the callers cannot see: the build system's
				/// target graph attributes it to no module, since it is in a directory this module's configuration adds.
				case treeReachesDeclarationCallersCannotSee(declaration: TypeDescription)
				/// As `treeReachesDeclarationCallersCannotSee`, where what the callers cannot see is the plain declaration
				/// (`PlainTypeDeclaration`) that proves the type of a parameter they would take otherwise: without it, they
				/// count the type as one SafeDI reads no declaration of, which is `public`. Reported at the declaration.
				case treeReachesPlainDeclarationCallersCannotSee(declaration: PlainTypeDeclaration)
				/// A tier of the generated initializer is wider than `hole`'s builder, which every tier takes, as far as the
				/// proof of the builder's type (`Hole.accessCause`) goes. Not a `ParameterKind`: a builder is no member of
				/// `SeamSignature.parameters`, whose labels are what `parameterLabels(namedBy:about:)` names.
				case tierOmitsBuilder(hole: SeamSignature.Hole, builder: SeamSignature.Builder?, tier: AccessLevel)
				/// A builder narrower than a tier only because of an inner seam whose enum it holds.
				case tierOmitsBuilderHoldingInnerSeam(builder: SeamSignature.Builder, innerSeam: TypeDescription, tier: AccessLevel)
			}

			let seam: Instantiable
			let kind: Kind

			/// What requires `tier`, the tier an omission is reported at: the seam's access, in a clause of the error's first
			/// sentence, or its `generateMock: .public`, which no narrower seam removes, in a sentence of its own.
			private func tierRequirement(_ tier: AccessLevel) -> (isRequiredByPublicMock: Bool, requiredByClause: String, publicMockSentence: String) {
				if seam.generateMock == .public, tier == .public {
					(true, "", " " + SeamAccessExplanation.publicMockRequirementSentence(seam: seam.concreteInstantiable))
				} else {
					(false, ", which `\(seam.concreteInstantiable.asSource)`'s `\(tier.spelledOnGeneratedDeclaration)` access requires,", "")
				}
			}

			var sourceDiagnostics: [SourceDiagnostic] {
				let seamName = "`\(seam.concreteInstantiable.asSource)`"
				let message: String
				let receivers: [Receiver]
				var location = seam.declarationLocation
				// The plain declarations that keep a parameter's type narrower than its tier, each with a fix-it.
				var declarationNotes = [SourceDiagnostic]()
				switch kind {
				case let .parameters(.parametersShareLabel(label, labelReceivers, remedy)):
					receivers = labelReceivers
					let forms = labelReceivers.map { "`\($0.property.asSource)` on `\($0.declaringType.asSource)`" }.joined(separator: " and ")
					let remedyText = switch remedy {
					case .rename:
						"Rename one of the properties, or @\(Dependency.Source.instantiatedRawValue) one of them inside the tree."
					case .receiveOneWrapperKind:
						"Receive `\(label)` as one wrapper kind in every type of the tree."
					case .receiveTheSameWay:
						"Receive `\(label)` the same way in every type of the tree."
					case let .declareProvidingForm(providingForm):
						"Receive `\(label)` the same way in every type of the tree, or declare it on \(seamName) as the form that provides the others: `@\(Dependency.Source.receivedRawValue) let \(label): \(providingForm)`."
					}
					message = "SafeDI cannot generate the dependency tree of \(seamName): its tree receives `\(label)` as \(forms), and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. \(remedyText)"
				case let .parameters(.tierOmitsRequiredParameter(parameter, tier, parameterLevel, parameterReceivers, ownParameter, cause)):
					receivers = parameterReceivers
					let treeReceivers = parameterReceivers.filter { $0.declaringType != seam.concreteInstantiable }
					// Who takes the parameter: the seam's own initializer, the seam itself, or the receivers in its tree.
					let receiverNames = treeReceivers.map { receiver in
						receiver.isInstantiateMethodParameter
							? "`\(receiver.declaringType.asSource)`'s `instantiate(…)`"
							: "`\(receiver.declaringType.asSource)`"
					}.uniqued()
					let takers: String = switch ownParameter {
					case .forwarded:
						"\(seamName)'s own initializer takes"
					case .required:
						receiverNames.isEmpty ? "\(seamName) receives" : "\(([seamName] + receiverNames).joinedAsList) receive"
					case .none:
						// A pass-through the seam's own alias receives names the seam; one only the seam's own aliases
						// receive, the seam too.
						if let receiver = parameterReceivers.first, parameterReceivers.count == 1, let aliasProperty = receiver.aliasProperty {
							"`\(receiver.declaringType.asSource)` receives through its alias `\(aliasProperty.label)` (`fulfilledByDependencyNamed: \"\(parameter.label)\"`)"
						} else {
							receiverNames.count > 1 ? "\(receiverNames.joinedAsList) receive" : "\(receiverNames.first ?? seamName) receives"
						}
					}
					let parameterKind: SeamAccessExplanation.ParameterKind = switch ownParameter {
					case .none:
						.passThrough
					case .forwarded:
						.ownForwarded
					case .required:
						.ownReceived
					}
					let (isRequiredByPublicMock, requiredBy, publicMockRequirement) = tierRequirement(tier)
					let causeText = cause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: treeReceivers.map(\.asExplanationReceiver)) } ?? ""
					let remedies = SeamAccessExplanation.tierRemedies(
						cause: cause,
						neededLevel: tier,
						parameterLevel: parameterLevel,
						seam: seam.concreteInstantiable,
						parameter: parameter,
						receivers: treeReceivers.map(\.asExplanationReceiver),
						parameterKind: parameterKind,
						seamAccessIsRequiredByPublicMock: isRequiredByPublicMock,
					)
					message = "SafeDI cannot generate the dependency tree of \(seamName): its generated `\(tier.spelledOnGeneratedDeclaration)` initializer\(requiredBy) cannot take `\(parameter.asSource)`, which \(takers), and cannot pass `nil` for it, since it is required.\(publicMockRequirement)\(causeText) \(remedies)"
					declarationNotes = SeamAccessExplanation.declarationNotes(for: cause, neededLevel: tier)
				case let .signaturesDidNotSettle(seams):
					receivers = []
					message = "SafeDI cannot generate the dependency tree of \(seamName): the generated initializers of \(seams.map { "`\($0.asSource)`" }.joined(separator: ", ")), which reach one another, took a parameter from one another on every pass up to the limit. This is a defect in SafeDI; report it with these types' declarations."
				case let .treeReachesDeclarationCallersCannotSee(declaration):
					receivers = []
					message = "SafeDI cannot generate the dependency tree of \(seamName): the initializer SafeDI generates for it depends on `\(declaration.asSource)`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `\(declaration.asSource)` in a file of this module, or of a module it depends on."
				case let .treeReachesPlainDeclarationCallersCannotSee(declaration):
					receivers = []
					location = declaration.access.declarationStartLocation ?? location
					let typeName = "`\(declaration.typeDescription.asSource)`"
					message = "SafeDI cannot generate the dependency tree of \(seamName): the initializer SafeDI generates for it takes its parameters at the access this declaration of \(typeName) proves, which is in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see it, so they would count \(typeName) as `public`, and their calls would not match the initializer. Declare \(typeName) in a file of this module, or of a module it depends on."
				case let .tierOmitsBuilderHoldingInnerSeam(builder, innerSeam, tier):
					receivers = []
					let (_, requiredBy, publicMockRequirement) = tierRequirement(tier)
					let causeText = builder.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: []) } ?? ""
					message = "SafeDI cannot generate the dependency tree of \(seamName): its generated `\(tier.spelledOnGeneratedDeclaration)` initializer\(requiredBy) cannot take `\(builder.label(inTierAt: tier)): \(builder.parameterType.asSource)`, whose scope holds the builders of `\(innerSeam.asSource)`, a seam visible only at `\(builder.tierAccess.spelledOnGeneratedDeclaration)` access.\(publicMockRequirement)\(causeText) Declare \(seamName) at `\(builder.tierAccess.spelledOnGeneratedDeclaration)` access, or make `\(innerSeam.asSource)` `\(tier.spelledOnGeneratedDeclaration)`."
				case let .tierOmitsBuilder(hole, builder, tier):
					// Explained as a required parameter's omission is, by the shared formatter, with the builder's remedy in
					// the place of a pass-through's.
					receivers = []
					let module = seam.moduleName.map { "module `\($0)`" } ?? "this module"
					let (isRequiredByPublicMock, requiredBy, publicMockRequirement) = tierRequirement(tier)
					let causeText = hole.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: []) } ?? ""
					let remedies = SeamAccessExplanation.tierRemedies(
						cause: hole.accessCause,
						neededLevel: tier,
						parameterLevel: hole.tierAccess,
						seam: seam.concreteInstantiable,
						parameter: Property(label: builder?.label(inTierAt: tier) ?? hole.builderLabel(inTierAt: tier), typeDescription: builder?.parameterType ?? hole.builderType(qualifiedBy: hole.scopeSeamType)),
						receivers: [],
						parameterKind: .builder(fulfilledType: hole.instantiatedType, seamModuleName: seam.moduleName, isPassedUp: hole.innerSeamType != nil),
						seamAccessIsRequiredByPublicMock: isRequiredByPublicMock,
					)
					message = "SafeDI cannot generate the dependency tree of \(seamName): its generated `\(tier.spelledOnGeneratedDeclaration)` initializer\(requiredBy) cannot take `\(builder?.label(inTierAt: tier) ?? hole.builderLabel(inTierAt: tier)): \((builder?.parameterType ?? hole.builderType(qualifiedBy: hole.scopeSeamType)).asSource)`, the builder for `\(hole.ownerType.asSource)`'s `\(hole.property.asSource)`, which no @Instantiable declaration that \(module) can see fulfills.\(publicMockRequirement)\(causeText) \(remedies)"
					declarationNotes = SeamAccessExplanation.declarationNotes(for: hole.accessCause, neededLevel: tier)
				case let .parameters(.initializerCollides(parameters, builderLabels, handWrittenInitializer)):
					receivers = []
					let handWrittenSignature = "init(\(handWrittenInitializer.arguments.map { "\($0.label):" }.joined()))"
					let generatedLabels = parameters.map(\.property.label) + builderLabels
					let generatedSignature = "init(\(generatedLabels.map { "\($0):" }.joined()))"
					// Reported at the hand-written initializer, which the remedy calls "this initializer".
					location = handWrittenInitializer.access.declarationStartLocation ?? location
					// A tier that takes no argument is `init()` whatever the module sets, so only the hand-written initializer
					// can give way; a labelled tier collides only where the module generates the plain initializer.
					let remedy = if generatedLabels.isEmpty {
						"Remove this initializer, or give it a parameter that has no default value, so that `\(seam.concreteInstantiable.asSource)()` can mean only the generated initializer."
					} else {
						"Rename this initializer’s argument labels; remove it; or, while code you write still calls it, remove `\(SafeDIConfigurationVisitor.generatePlainDependencyTreeInitializersArgumentLabel): true` from this module’s `#\(SafeDIConfigurationVisitor.macroName)`."
					}
					message = "SafeDI cannot generate the dependency tree of \(seamName): it declares `\(handWrittenSignature)`, which can be called with the argument labels of its generated initializer, `\(generatedSignature)`. Because the labels match, a call meant for one initializer can run the other instead, or the code can fail to compile. \(remedy)"
				}
				// The notes follow the receivers in the order the tree declares them, which no name decides.
				return [SourceDiagnostic(severity: .error, location: location, message: message)]
					+ declarationNotes
					+ receivers.map { receiver in
						SourceDiagnostic(
							severity: .note,
							location: receiver.declarationLocation,
							message: "`\(receiver.declaringType.asSource)` receives `\(receiver.property.asSource)` here.",
						)
					}
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

		/// A dependency of a declaration whose label `String` equates with an earlier dependency's label, which generation,
		/// keying a declaration's dependencies by label, cannot tell apart. The `@Instantiable` macro rejects the ways one
		/// clause can do this that the compiler accepts, but every build runs SafeDITool before the compiler expands the
		/// macro, so SafeDITool reports them too, plainly. A dependency declared once in each clause of an `#if` that only
		/// the compiler decides is another way, which the macro and the compiler accept.
		struct RepeatedDependencyLabel {
			/// The type that declares both dependencies.
			let declaringType: TypeDescription
			let earlierDependency: Dependency
			let laterDependency: Dependency

			/// An `error:` line at the later dependency.
			var sourceDiagnostic: SourceDiagnostic {
				SourceDiagnostic(
					severity: .error,
					location: laterDependency.declarationLocation,
					message: message,
				)
			}

			private var message: String {
				let earlierName = earlierDependency.property.label.spelledWithoutBackticks
				let laterName = laterDependency.property.label.spelledWithoutBackticks
				return if laterName == "_" {
					"`\(declaringType.asSource)` has more than one dependency named `_`. SafeDI names an `instantiate(…)` dependency by its parameter’s name, and the @\(InstantiableVisitor.macroName) macro rejects a dependency parameter named `_`. Name the parameter."
				} else if !earlierName.utf8.elementsEqual(laterName.utf8) {
					"`\(declaringType.asSource)` has dependencies `\(earlierName)` (\(earlierName.codePoints)) and `\(laterName)` (\(laterName.codePoints)), which look the same but are encoded differently, so SafeDI cannot tell them apart. The @\(InstantiableVisitor.macroName) macro rejects such names. Rename one of them."
				} else {
					// One wording for both causes, since a dependency does not record whether an `#if` encloses it: a copy-paste,
					// which the compiler rejects too, and one declaration in each clause of an `#if` only the compiler decides.
					"`\(declaringType.asSource)` declares the dependency `\(laterName)` more than once. Declare it once: if each clause of an `#if` that only the compiler decides, such as `#if os(iOS)`, declares it, declare it outside the `#if`, since SafeDI reads every clause."
				}
			}
		}

		/// A `@Received(fulfilledByDependencyNamed:ofType:)` declaration spelled as the `@Instantiable` macro rejects: a
		/// rename of another rename of the same declaration, or a rename of a dependency to itself. Every build runs
		/// SafeDITool before the compiler expands the macro, so SafeDITool reports them too, plainly, wherever its
		/// evaluation of `#if` blocks forms one – also where the macro, which cannot tell which clauses are active,
		/// accepts it: two renames in two `#if` blocks that are both active, or in two clauses of a block only the
		/// compiler decides, such as `#if os(iOS)`, every clause of which SafeDITool reads.
		struct RejectedRename {
			enum Spelling {
				/// The rename is fulfilled by `sourceLabel`, which `declaringType` also renames.
				case renameOfRename(sourceLabel: String, declaringType: TypeDescription)
				/// The rename is fulfilled by its own label with its own type.
				case renameOfItselfWithSameType
				/// The rename is fulfilled by its own label with its own type made non-optional, or kept, only if available.
				case renameOfItselfOnlyIfAvailable
			}

			let property: Property
			let spelling: Spelling
			let declarationLocation: Dependency.DeclarationLocation?

			/// An `error:` line at the rename.
			var sourceDiagnostic: SourceDiagnostic {
				SourceDiagnostic(
					severity: .error,
					location: declarationLocation,
					message: message,
				)
			}

			private var message: String {
				switch spelling {
				case let .renameOfRename(sourceLabel, declaringType):
					"`\(property.asSource)` is renamed from `\(sourceLabel.spelledWithoutBackticks)`, which `\(declaringType.asSource)` also renames. The @\(InstantiableVisitor.macroName) macro rejects a rename of another rename of the same declaration. Rename the property the renames start from instead. SafeDITool also rejects such renames where `#if` blocks that are active together declare them, or clauses of a condition only the compiler decides, such as `os(iOS)`, which SafeDITool reads together; there, give the rename `\(sourceLabel.spelledWithoutBackticks)` another label."
				case .renameOfItselfWithSameType:
					"`\(property.asSource)` is renamed from itself with the same type, which renames nothing. The @\(InstantiableVisitor.macroName) macro rejects this rename. Receive it with @\(Dependency.Source.receivedRawValue) instead."
				case .renameOfItselfOnlyIfAvailable:
					"`\(property.asSource)` is renamed from itself only if available. The @\(InstantiableVisitor.macroName) macro rejects this spelling of @\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true). Receive it with @\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true) instead."
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
			/// Whether an `@Instantiated` declaration of `property` could fulfill it, which decides whether the hint
			/// suggests one.
			let instantiatedDeclaration: InstantiatedDeclaration

			/// Whether an `@Instantiated` declaration of a received property's non-optional form could fulfill it. The
			/// macro rejects an optional `@Instantiated` property, and a declaration of the non-optional form provides
			/// a receive of the optional one, so the hint always suggests the non-optional form.
			enum InstantiatedDeclaration: Hashable {
				/// It could, as far as SafeDI checks: the non-optional form is not a constant, or a declaration without
				/// `@Forwarded` properties fulfills its type.
				case possible
				/// The non-optional form is a constant of a type whose declaration has `@Forwarded` properties, which only
				/// an `Instantiator` can build.
				case typeHasForwardedProperties
				/// The non-optional form is a constant of a type no `@Instantiable` declaration fulfills.
				case typeIsNotInstantiable

				/// Whether an `@Instantiated` declaration of `property`'s non-optional form could fulfill it, among the
				/// declarations of `fulfillingInstantiables`.
				static func of(_ property: Property, among fulfillingInstantiables: [TypeDescription: Instantiable]) -> Self {
					let suggestedProperty = property.asUnwrappedProperty
					guard suggestedProperty.propertyType.isConstant else { return .possible }
					guard let fulfillingInstantiable = fulfillingInstantiables[suggestedProperty.typeDescription.asInstantiatedType] else {
						return .typeIsNotInstantiable
					}
					return fulfillingInstantiable.dependencies.contains { $0.source == .forwarded } ? .typeHasForwardedProperties : .possible
				}
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
					// The macro rejects an optional `@Instantiated` property, and a declaration of the non-optional form
					// provides a receive of the optional one (`ScopeGenerator.provides`).
					let suggestedProperty = property.asUnwrappedProperty
					let typeName = suggestedProperty.typeDescription.asSource
					let forwardingRemedy = "Declare `@\(Dependency.Source.forwardedRawValue) let \(suggestedProperty.asSource)` on a type below `\(root.asSource)` in the chain, and pass the value to the `Instantiator` that builds that type"
					hint = if suggestedProperty.propertyType.isErasedInstantiator {
						// The `@Instantiated` macro requires an erased instantiator to name the type it builds.
						"Declare `@\(Dependency.Source.instantiatedRawValue)(fulfilledByType:) let \(suggestedProperty.asSource)`, naming the type it builds, on `\(root.asSource)` or on another type in the chain to fix."
					} else {
						switch instantiatedDeclaration {
						case .possible:
							"Declare `@\(Dependency.Source.instantiatedRawValue) let \(suggestedProperty.asSource)` on `\(root.asSource)` or on another type in the chain to fix."
						case .typeHasForwardedProperties:
							"`\(typeName)` has @\(Dependency.Source.forwardedRawValue) properties, so SafeDI builds it only through an `Instantiator`, never as an @\(Dependency.Source.instantiatedRawValue) constant. \(forwardingRemedy), to fix."
						case .typeIsNotInstantiable:
							"No @\(InstantiableVisitor.macroName) declaration fulfills `\(typeName)`, so SafeDI cannot instantiate it. \(forwardingRemedy); or decorate `\(typeName)`, or an extension of it, with @\(InstantiableVisitor.macroName) and declare `@\(Dependency.Source.instantiatedRawValue) let \(suggestedProperty.asSource)` on `\(root.asSource)` or on another type in the chain, to fix."
						}
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
			/// Whether `declaringType` is forwarded `property`, which the tree is then handed rather than builds.
			let isForwarded: Bool
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
			/// The types of the properties the chain's scopes are built for (`ScreenProtocol`, `Instantiator<Screen>`),
			/// innermost first, excluding `root`.
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

		/// A rename whose `fulfilledByDependencyNamed:` label its own type also declares – as a property it instantiates
		/// or forwards, or as another rename – with a type that the rename's `ofType:` does not name. A rename refers to
		/// the property of that name on its own type, so it cannot name a property of another type further up the tree.
		struct RenameContradictingOwnProperty: Hashable {
			/// The rename, as declared.
			let aliasProperty: Property
			/// The property the rename's `fulfilledByDependencyNamed:` and `ofType:` name.
			let fulfillingProperty: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The property of the rename's label that `renamingType` declares.
			let ownProperty: Property
			let ownPropertyDeclarationLocation: Dependency.DeclarationLocation?
			let renamingType: TypeDescription

			/// An `error:` line that names the type's own property, since Xcode drops notes from build-tool output, and a
			/// `note:` at that property's declaration so command-line builds can navigate to it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let ownPropertyTypeLiteral = ownProperty.typeDescription.asTypeLiteralSource
				let ownProperty = ownProperty.asSource
				let fulfillingProperty = fulfillingProperty.asSource
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:) property `\(aliasProperty.asSource)` renames `\(fulfillingProperty)`, but `\(renamingType.asSource)` declares `\(ownProperty)`, and a rename refers to the property of that name on its own type. Write `ofType: \(ownPropertyTypeLiteral)` to rename `\(ownProperty)`, or give `\(ownProperty)` on `\(renamingType.asSource)` a different label to rename `\(fulfillingProperty)` from further up the tree.",
					),
					SourceDiagnostic(
						severity: .note,
						location: ownPropertyDeclarationLocation,
						message: "`\(ownProperty)` is declared here",
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
				let property = property.asSource
				let hidingProperty = hidingProperty.asSource
				let hidingType = chain[0].asSource
				let receivingType = chain[chain.count - 1].asSource
				let forwardedProperty = forwardedProperty.asSource
				let mockedType = mockedType.asSource
				// Giving the forwarded property another label leaves the receive hidden wherever `hidingType` holds a
				// form of the label the mock cannot derive from the receiver's, so the remedy separates the two receives.
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue) property `\(property)` is hidden in chain: \(chain.map(\.asSource).joined(separator: " -> ")). In the mock of `\(mockedType)`, `\(receivingType)` is passed the `\(forwardedProperty)` that `\(mockedType)` forwards, but `\(hidingType)` receives `\(hidingProperty)` with the same label, so the types below `\(hidingType)` receive `\(hidingProperty)` instead. Receive `\(property)` on `\(receivingType)` and `\(hidingProperty)` on `\(hidingType)` under different labels to fix.",
					),
					SourceDiagnostic(
						severity: .note,
						location: hidingDeclarationLocation,
						message: "`\(hidingProperty)` is received here",
					),
				]
			}
		}

		/// An `error:` line at the first receive of `unpassableCycleLabel`'s label, which names every form the type built again
		/// and the types it builds receive, and a `note:` at the declaration of the label it is built again beneath.
		private static func sourceDiagnostics(of unpassableCycleLabel: UnpassableCycleLabel) -> [SourceDiagnostic] {
			let receiver = unpassableCycleLabel.receiver
			let redeclaration = unpassableCycleLabel.redeclaration
			let label = receiver.property.label
			let builtType = "`\(unpassableCycleLabel.builtType.asSource)`"
			let forms = unpassableCycleLabel.forms.map { "`\($0.asSource)`" }.joinedAsList
			return [
				SourceDiagnostic(
					severity: .error,
					location: receiver.declarationLocation,
					message: "@\(Dependency.Source.receivedRawValue) property `\(receiver.property.asSource)` is received in chain: \(receiver.chain.map(\.asSource).joined(separator: " -> ")). A dependency cycle builds \(builtType) again beneath `\(redeclaration.declaringType.asSource)`, which declares `\(redeclaration.property.asSource)` with the same label, and SafeDI hands each \(builtType) one value of `\(label)`. \(builtType) and the types it builds receive `\(label)` as \(forms), which one value cannot carry together. Receive \(forms) under different labels to fix.",
				),
				SourceDiagnostic(
					severity: .note,
					location: redeclaration.declarationLocation,
					message: "`\(redeclaration.property.asSource)` is declared here",
				),
			]
		}

		/// A receive in a mock's tree, beneath or beside a receive of its label, on a type in that tree, in a form no one
		/// declaration provides together with it, where either receive is required. In production both receives resolve to
		/// the closest declaration of the label above the tree: above the mocked type for its own tree, and above the tree
		/// of a dependency the mock promotes, which is built above the mocked type.
		struct ReceivedPropertyHiddenInMockTree {
			/// The tree of a mock that holds both receives.
			enum Tree {
				/// The mocked type's own tree.
				case mockedType
				/// The tree of a dependency the mock promotes, of the given type.
				case promotedDependency(TypeDescription)
			}

			/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			let mockedType: TypeDescription
			let tree: Tree
			/// The other form of the label, which `hidingType` receives.
			let hidingProperty: Property
			let hidingDeclarationLocation: Dependency.DeclarationLocation?
			let hidingType: TypeDescription
			/// Whether the type that receives `property` is `hidingType`, which declares both receives.
			let isHiddenOnItsOwnType: Bool
			/// The types from the type at the top of `tree` to the one that receives `property`.
			let chain: [TypeDescription]

			/// An `error:` line in the words of `HiddenReceivedProperty`'s, which names the hiding receive, and a `note:` at it.
			var sourceDiagnostics: [SourceDiagnostic] {
				let property = property.asSource
				let hidingProperty = hidingProperty.asSource
				let hidingType = hidingType.asSource
				let mockedType = mockedType.asSource
				let receivingTypes = isHiddenOnItsOwnType
					? "`\(hidingType)` and the types below it"
					: "the types below `\(hidingType)`"
				let (treeClause, builtType) = switch tree {
				case .mockedType:
					("", mockedType)
				case let .promotedDependency(promotedType):
					("`\(promotedType.asSource)` stands for a dependency built above `\(mockedType)`, and ", promotedType.asSource)
				}
				return [
					SourceDiagnostic(
						severity: .error,
						location: declarationLocation,
						message: "@\(Dependency.Source.receivedRawValue) property `\(property)` is hidden in chain: \(chain.map(\.asSource).joined(separator: " -> ")). In the mock of `\(mockedType)`, \(treeClause)`\(hidingType)` receives `\(hidingProperty)` with the same label, so \(receivingTypes) receive `\(hidingProperty)` instead, as they do wherever `\(builtType)` is built. Receive `\(property)` and `\(hidingProperty)` under different labels to fix.",
					),
					SourceDiagnostic(
						severity: .note,
						location: hidingDeclarationLocation,
						message: "`\(hidingProperty)` is received here",
					),
				]
			}
		}

		/// The dependency declaration that closes a dependency cycle no instantiator defers, or that receives a property
		/// still being built, at which the cycle is reported.
		enum ClosingDependency {
			/// A dependency the declaring type instantiates, closing a cycle along which no dependency is an instantiator:
			/// `hops`, the instantiated dependencies along the cycle as validation sees them (a lazily instantiated
			/// dependency as the constant it stands for), outermost first, the closing dependency among them.
			case instantiated(hops: [Property])
			/// A dependency `receiver` receives, as declared, while the property it is fulfilled by is still being built.
			case received(Property, receiver: TypeDescription)

			/// The sentence that tells the user how to break the cycle at this declaration.
			var remedy: String {
				switch self {
				case let .instantiated(hops):
					"SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @\(Dependency.Source.instantiatedRawValue) instantiator, such as an `\(Dependency.instantiatorType)` or `\(Dependency.erasedInstantiatorType)`, which builds its type each time it is called. Change \(hops.count == 1 ? "" : "one of ")\(hops.map { "`\($0.asSource)`" }.joined(separator: ", ")) to an instantiator."
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
	/// How the imports of each generated file spell their access levels.
	private let importAccess: GeneratedImportAccess
	/// How the imports of a generated file spell their access levels once the module's own files are known to spell the
	/// given ones, which `importAccess` is without any.
	private let importAccessSpellingOwnLevels: @Sendable ([String: Set<AccessLevel>]) -> GeneratedImportAccess
	private let readOwnFiles: (@Sendable () async -> FulfillerImports.OwnFiles)?
	/// What the first generated file that would gain an import had read, since every later one asks the same.
	private var ownFilesRead: OwnFilesRead?
	private let typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
	private let aliasDeclarationReferences: AliasDeclarationReferences
	private let emittingModule: EmittingModule?
	private let unreadImports: UnreadImports?
	private let seams: SeamResolution
	/// The declarations of types that are not `@Instantiable` this generator was given, which a generator computing
	/// another module's view is given too.
	private let plainTypeDeclarations: [PlainTypeDeclaration]
	/// The names the modules SafeDI read declare types by at file scope (`namesOfTypesDeclaredAtFileScope`).
	private let declaredTypeNames: DeclaredTypeNames
	/// See `init`'s `viewInstantiablesByModuleName`.
	private let viewInstantiablesByModuleName: [String: [Instantiable]]
	/// See `init`'s `viewDeclaringModules`.
	private let viewDeclaringModules: [TypeDescription: ViewDeclaringModule]
	/// The declarations among which the declaration of a type an extension extends bounds the types declared in or by
	/// that extension.
	private let extendedTypeDeclarations: ExtendedTypeDeclarations
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
			// The trees of the foreign seams with holes, built inline with the fills this module generates.
			var inlineForeignSeamTrees = [ScopeGenerator]()
			let rootScopeGenerators: [RootScopeInfo] = try {
				// The roots' trees and the generated seams' trees build exactly the reachable types, the foreign seams
				// their trees call included. First, before any seam signature is computed: a seam's parameters are keyed
				// by property, so a seam that repeats a label is reported here rather than generating a tier that
				// repeats it.
				try Self.validateDependencyLabelsAreDistinct(in: reachableTypeDescriptions.compactMap { typeDescriptionToFulfillingInstantiableMap[$0] })
				try Self.validateRenamesAreSpelledAsTheMacroAccepts(in: reachableTypeDescriptions.compactMap { typeDescriptionToFulfillingInstantiableMap[$0] })
				// A foreign seam whose module's files this run read under another mock condition is reported before
				// its signature is computed from them.
				try validateCalledSeamModulesShareMockCondition()
				// A foreign seam's module info this run lacks is reported before the inlined trees, which reach that
				// module's declarations, are found unfulfillable.
				_ = try foreignSeamRoots.get()
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
				var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
				try Self.validateChildrenDoNotRequireEachOther(
					inTreesRootedAt: validatedRootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] },
					cache: &receivedPropertiesCache,
					validation: &childrenRequiringEachOtherValidation,
				)
				try validateCyclesFromRootsOfForeignSeamsWithHoles(in: typeDescriptionToScopeMap, receivedPropertiesCache: &receivedPropertiesCache)
				inlineForeignSeamTrees = try inlineTreesOfForeignSeamsWithHoles(in: typeDescriptionToScopeMap)
				self.validatedScopes = Set(typeDescriptionToScopeMap.values)
				// A module whose declarations hold no seam generates from the validated scopes, as it always has.
				// One that holds a seam generates from a second map, in which every reach of a seam is a call to
				// its generated initializer, built once the validated scopes have been checked. Each construction is
				// checked where it is generated, so the validated scopes decide nothing about access in a module
				// that holds a seam: a root's tree constructs the seam with its generated initializer, and the
				// seam's tree compiles in the module that declares the seam.
				guard !seams.isEmpty else {
					// Creating a generator starts generating its code, so every construction must be known to compile first.
					let rootScopesToGenerate = try rootScopesThisModuleGenerates(
						from: rootInstantiables.sorted().compactMap { typeDescription in
							typeDescriptionToScopeMap[typeDescription].map { (typeDescription: typeDescription, scope: $0) }
						},
					)
					return try rootScopesToGenerate.map { typeDescription, scope in
						try RootScopeInfo(
							typeDescription: typeDescription,
							instantiable: scope.instantiable,
							sourceFilePath: typeDescriptionToFulfillingInstantiableMap[typeDescription]?.sourceFilePath,
							scopeGenerator: scope.createScopeGenerator(
								for: nil,
								lazilyInstantiatedInstanceProperties: [],
								erasedToConcreteExistential: false,
								declaredTypeNames: declaredTypeNames,
							),
						)
					}
				}
				return try seamWorldRootScopeGenerators()
			}()
			try Self.validateCycleLabelsArePassable(inTreesRootedAt: rootScopeGenerators.map(\.scopeGenerator) + inlineForeignSeamTrees)
			return rootScopeGenerators
		}
	}

	/// Rejects each label that a type a dependency cycle builds again, in the trees `generators` root, receives in forms
	/// no one value SafeDI hands it can provide together (see `UnpassableCycleLabel`). Each is reported once, in source
	/// order, whichever trees hold it: the trees of several roots, production or mock, can each build the function whose
	/// label it is, and so can the inline tree of a foreign seam with holes (`inlineTreesOfForeignSeamsWithHoles(in:)`).
	private static func validateCycleLabelsArePassable(inTreesRootedAt generators: [ScopeGenerator]) throws {
		let unpassableCycleLabels = generators.flatMap(\.unpassableCycleLabelsInTree).uniqued()
		if let error = DependencyTreeGeneratorError.reportingAll(of: unpassableCycleLabels.map(DependencyTreeGeneratorError.unpassableCycleLabel)) {
			throw error
		}
	}

	/// Whether every declaration any generated code could construct, with any of the methods that construct it, is
	/// `public` or `open` where it is declared, which code in every module can use. No construction then needs to be
	/// checked, which is the case for a project whose types are all `public`.
	private lazy var constructsOnlyPublicDeclarations: Bool = typeDescriptionToFulfillingInstantiableMap.values.allSatisfy { instantiable in
		Self.isPubliclyConstructible(instantiable, withMockMethod: false, extendedTypes: extendedTypeDeclarations)
			&& (instantiable.mockInitializer == nil || Self.isPubliclyConstructible(instantiable, withMockMethod: true, extendedTypes: extendedTypeDeclarations))
	}

	/// The emitting module whose constructions need checking, or `nil` when none do: no module was given, or every
	/// declaration any generated code could construct is `public` or `open`.
	private lazy var emittingModuleToCheck: EmittingModule? = constructsOnlyPublicDeclarations ? nil : emittingModule

	/// The roots whose trees this module generates code for, from `rootScopes`, the module's roots in type order: those
	/// declared in one of the module's own files. Each is generated once every construction in its tree is known to
	/// compile in the module; otherwise one error reports each declaration that keeps a construction from compiling,
	/// however many of the roots' trees construct it. A root declared elsewhere – a file of another module that the
	/// build tool plugin's input or `additionalDirectoriesToInclude` reaches, or a module info file – is generated only
	/// by the module that declares it, which `rootsOfOtherModules` records, so nothing is reported about it here.
	/// - Parameters:
	///   - rootScopes: The module's roots in type order, each with the scope its tree is generated from.
	///   - seamTrees: The seams this module generates an initializer for, each with the scope its tree is generated
	///     from. A seam is declared in one of the module's own files, so its tree's constructions are checked as an
	///     own root's are, and reported together with the roots'.
	private func rootScopesThisModuleGenerates(
		from rootScopes: [(typeDescription: TypeDescription, scope: Scope)],
		checkingSeamTrees seamTrees: [(instantiable: Instantiable, scope: Scope)] = [],
	) throws -> [(typeDescription: TypeDescription, scope: Scope)] {
		guard let emittingModule else { return rootScopes }
		// A project whose types are all `public` has no construction to check.
		let checksConstructions = !constructsOnlyPublicDeclarations
		var rootScopesToGenerate = [(typeDescription: TypeDescription, scope: Scope)]()
		var rootsOfOtherModules = [Instantiable]()
		var inaccessibleConstructions = [DependencyTreeGeneratorError.InaccessibleConstruction]()
		for seamTree in seamTrees where checksConstructions {
			inaccessibleConstructions += Self.inaccessibleConstructions(
				Self.constructions(
					inTreeRootedAt: seamTree.scope,
					rootIsConstructedWithMockMethod: false,
					rootReferenceLocation: seamTree.instantiable.declarationLocation,
					isMock: false,
					emittingModule: emittingModule,
					extendedTypes: extendedTypeDeclarations,
				),
				from: emittingModule,
				extendedTypes: extendedTypeDeclarations,
			)
		}
		for rootScope in rootScopes {
			let rootInstantiable = rootScope.scope.instantiable
			guard rootInstantiable.sourceFilePath.map(emittingModule.isOwnFile) == true else {
				rootsOfOtherModules.append(rootInstantiable)
				continue
			}
			if checksConstructions {
				inaccessibleConstructions += Self.inaccessibleConstructions(
					Self.constructions(
						inTreeRootedAt: rootScope.scope,
						rootIsConstructedWithMockMethod: false,
						rootReferenceLocation: rootInstantiable.declarationLocation,
						isMock: false,
						emittingModule: emittingModule,
						extendedTypes: extendedTypeDeclarations,
					),
					from: emittingModule,
					extendedTypes: extendedTypeDeclarations,
				)
			}
			rootScopesToGenerate.append(rootScope)
		}
		guard inaccessibleConstructions.isEmpty else {
			throw DependencyTreeGeneratorError.inaccessibleConstructions(inaccessibleConstructions)
		}
		self.rootsOfOtherModules = rootsOfOtherModules
		return rootScopesToGenerate
	}

	/// The roots another module declares, in type order, whose `init()` that module generates rather than this one.
	/// Empty until the tree has been generated.
	private var rootsOfOtherModules = [Instantiable]()

	/// Whether code in every module can construct `instantiable` with its hand-written mock method when
	/// `withMockMethod` is set, and otherwise with its initializer or `instantiate()` method, among `extendedTypes`,
	/// which bound a type declared in or by an extension.
	private static func isPubliclyConstructible(_ instantiable: Instantiable, withMockMethod: Bool, extendedTypes: ExtendedTypeDeclarations) -> Bool {
		(instantiable.accessNeeds(constructingWithMockMethod: withMockMethod) + extendedTypeAccessNeeds(of: instantiable, in: extendedTypes))
			.allSatisfy { $0.level.satisfies(.public) }
	}

	/// The outermost `public` type another module declares on the path to a construction in a mock's tree, which a
	/// mock of this module builds inline (see `Construction.publicMockCandidate`).
	enum PublicMockCandidate: Hashable {
		/// The type has neither a hand-written nor a public mock: one would spare this module building its tree.
		/// - `declaringModuleName`: The module that declares the type and would generate its public mock.
		/// - `needsPublicDeclaration`: Whether the type is narrower than `public`, which a public mock requires.
		/// - `isSeam`: Whether the type is a seam (`generateDependencyTree: true`), whose tree a mock builds inline.
		case withoutMock(TypeDescription, declaringModuleName: String?, needsPublicDeclaration: Bool, isSeam: Bool)
		/// The type has a public mock, but SafeDI does not know which module declares it, and therefore cannot call it: the
		/// type was read from a file no target graph or module name assigns to a module – as a target the Xcode project
		/// plugin builds reads every other target's types, and as a directory a `#SafeDIConfiguration` adds is read.
		/// `emittingModuleIsUnknown`, whether this run names no module, decides only the error's wording.
		case publicMockOfUnknownModule(TypeDescription, emittingModuleIsUnknown: Bool)
	}

	/// A type the generated code constructs, with how it constructs it.
	private struct Construction {
		/// - Parameter extendedTypes: The declarations the module reads, among which the declaration of a type an
		///   extension extends bounds the types declared in or by that extension.
		init(
			instantiable: Instantiable,
			usesMockMethod: Bool,
			referenceLocation: Dependency.DeclarationLocation?,
			isSeamLeaf: Bool,
			extendedTypes: ExtendedTypeDeclarations,
			publicMockCandidate: PublicMockCandidate? = nil,
			seamCandidateOnPaths: SeamCandidateOnPaths = .agreed(nil),
			inlineSeam: DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam? = nil,
		) {
			self.instantiable = instantiable
			self.usesMockMethod = usesMockMethod
			self.referenceLocation = referenceLocation
			self.isSeamLeaf = isSeamLeaf
			self.publicMockCandidate = publicMockCandidate
			extendedTypeAccessNeeds = DependencyTreeGenerator.extendedTypeAccessNeeds(of: instantiable, in: extendedTypes)
			self.seamCandidateOnPaths = seamCandidateOnPaths
			self.inlineSeam = inlineSeam
		}

		/// In a mock's tree, what the outermost type on the path to the construction that another module declares
		/// offers instead of building its tree here, which an error about the construction says.
		let publicMockCandidate: PublicMockCandidate?

		let instantiable: Instantiable
		/// Whether the type is constructed with its hand-written mock method rather than with its initializer or
		/// `instantiate()` method.
		let usesMockMethod: Bool
		/// Where this module refers to what leads to the construction: the first, in source order, of the dependencies
		/// declared in the module's own files on a path to it, or the declaration of the tree's root. An error about
		/// the construction is reported there when the declaration that must change cannot be read.
		let referenceLocation: Dependency.DeclarationLocation?
		/// Whether the construction calls an initializer SafeDI generates for a seam, which is at most as visible as the
		/// seam's type: only the type's declaration, and those enclosing it, can keep it from compiling.
		let isSeamLeaf: Bool
		/// The declarations of the type an extension extends that bound the constructed type, when it is declared in or
		/// by that extension (`extendedTypeAccessNeeds(of:in:)`): code that names the type names the extended type too.
		let extendedTypeAccessNeeds: [AccessNeed]

		/// In a production tree, what the paths to the construction decide about the type whose generated initializer
		/// the tree could call instead of building the type's tree, were the type declared with
		/// `generateDependencyTree: true`: see `SeamCandidateOnPaths`.
		let seamCandidateOnPaths: SeamCandidateOnPaths
		/// In a production tree of a module SafeDI cannot name, the outermost seam on the path to the construction that
		/// another module declares, which the tree builds inline because it cannot call the seam's generated initializer.
		/// The path with the earliest reference location decides it, as it decides `referenceLocation`.
		let inlineSeam: DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam?

		/// The declarations whose access decides whether the construction compiles, which the check of every
		/// construction reads.
		var accessNeeds: [AccessNeed] {
			(isSeamLeaf
				? DependencyTreeGenerator.seamLeafAccessNeeds(of: instantiable)
				: instantiable.accessNeeds(constructingWithMockMethod: usesMockMethod)) + extendedTypeAccessNeeds
		}
	}

	/// The declarations of the type an extension extends that bound a type the extension declares – a type declared
	/// inside the extension, or the type an `@Instantiable` extension declares – when the extended type is declared in
	/// the same module: the code that names the declared type names the extended type too, so the extended type's
	/// declaration, and those enclosing it in its file, must be as visible as the construction needs, and so must the
	/// declarations that bound the extended type when it is declared inside an extension itself, and so on
	/// (`ExtendedTypeDeclarations.accessNeeds(boundingTypesAnExtensionOf:declaresInModuleNamed:fromFileAt:)`), outermost
	/// first. Empty for any other declaration.
	fileprivate static func extendedTypeAccessNeeds(of instantiable: Instantiable, in extendedTypes: ExtendedTypeDeclarations) -> [AccessNeed] {
		guard let extendedType = instantiable.extendedType, let moduleName = instantiable.moduleName else { return [] }
		return extendedTypes.accessNeeds(boundingTypesAnExtensionOf: extendedType, declaresInModuleNamed: moduleName, fromFileAt: instantiable.sourceFilePath)
	}

	/// The declarations whose access decides whether a call of a seam's generated initializer compiles: the seam's type
	/// and the types enclosing it, never the generated initializer, whose access is at most the type's, nor the seam's
	/// own initializer, which the generated initializer calls inside the seam's module.
	fileprivate static func seamLeafAccessNeeds(of leaf: Instantiable) -> [AccessNeed] {
		leaf.accessNeeds(constructingWithMockMethod: false).filter { $0.declaration.declaredType != nil }
	}

	/// What the paths from a production tree's root to a construction decide about its seam candidate: on each path,
	/// the outermost type – the first met from the root, the construction's own type included – that a module SafeDI
	/// knows, other than this one, declares. Declaring that type with `generateDependencyTree: true` has its module
	/// build the type's tree, and this module call the initializer generated for it, so it keeps the construction out
	/// of this module only when every path passes through it, and only when that module's own run of `generate` reads
	/// the declaration of every type on each path from the candidate to the construction, the construction's own type
	/// included (`EmittingModule.modulesReadByRunOfModule`): it builds the tree from those declarations, as this
	/// run computes the seam's signature from them, and takes a builder for a type it does not see, which this module
	/// fills, building that type and its tree itself. That initializer's widest tier is at the candidate type's
	/// access, and it builds the tree, calls the candidate's own initializer, and takes each property the tree receives
	/// from above the candidate as a parameter as visible as the types it names, capped at the candidate's type, so
	/// every initializer of the tree, the one of a type that receives such a property included, is called inside the
	/// candidate's module (`seamRemedy(offeredBy:toWiden:declaredIn:extendedTypes:)`). Nothing beneath a type is
	/// constructed unless the type instantiates it, which neither a seam whose module SafeDI knows (this module calls its
	/// generated initializer and builds none of its tree), a leaf, nor a type an extension declares (whose dependencies
	/// are all received) does, so none of them is ever a candidate for another construction, and none needs excluding,
	/// though the macro rejects `generateDependencyTree` on an extension. A leaf or a type an extension declares can be
	/// its own construction's candidate, but it builds no tree, so SafeDI would generate no initializer for it, and its
	/// construction's errors offer no remedy. A `mockOnly` declaration is in no production tree. Mocks build every tree
	/// inline, so a mock's constructions have no candidate.
	private enum SeamCandidateOnPaths: Equatable {
		/// Every path walked so far has this candidate, whose module reads every type on the path from it, or none has
		/// one (`nil`).
		case agreed(Instantiable?)
		/// Two paths have different candidates, one has a candidate and another none, or a path from its candidate builds
		/// a type whose declaration the candidate's module does not read.
		case disagreed

		/// The candidate every path has, if any.
		var candidate: Instantiable? {
			switch self {
			case let .agreed(candidate):
				candidate
			case .disagreed:
				nil
			}
		}

		/// What the paths through a scope decide for its child `child`, which is a candidate on a path that has none
		/// above it when `childIsCandidate` is set, and whose declaration a candidate's module reads when
		/// `candidatesModuleReads` says so.
		func extended(
			to child: Instantiable,
			childIsCandidate: Bool,
			candidatesModuleReads: (_ child: Instantiable, _ candidate: Instantiable) -> Bool,
		) -> SeamCandidateOnPaths {
			switch self {
			case let .agreed(.some(candidate)):
				candidatesModuleReads(child, candidate) ? self : .disagreed
			case .agreed(.none):
				.agreed(childIsCandidate ? child : nil)
			case .disagreed:
				.disagreed
			}
		}

		/// What the paths of this and of `other` together decide. Candidates compare as declarations, so two map entries
		/// of one type would disagree, which withholds the remedy and never offers a wrong one.
		func merged(with other: SeamCandidateOnPaths) -> SeamCandidateOnPaths {
			switch (self, other) {
			case let (.agreed(candidate), .agreed(otherCandidate)) where candidate == otherCandidate:
				.agreed(candidate)
			case (.agreed, .agreed), (.agreed, .disagreed), (.disagreed, .agreed), (.disagreed, .disagreed):
				.disagreed
			}
		}
	}

	/// The seam an error about `accessNeed`, declared in `declaringModule`, offers when `candidate` is the seam candidate
	/// of every construction that needs it, or `nil` when declaring the candidate a seam would not let this module
	/// leave the declaration alone. That is so when the declaration is one a call of the initializer generated for the
	/// candidate relies on, as `Construction.accessNeeds` reads it for a seam leaf: the candidate's type, a type
	/// enclosing it, an extension one of those takes its level from, or the type an extension that declares the
	/// candidate extends, of which the generated initializer is no more visible. It is so for any declaration when the
	/// candidate builds no tree (`buildsTree(_:)`): SafeDI then generates no initializer for it, and its callers call its
	/// own; such a candidate, a leaf or a type an extension declares, is the candidate of its own construction alone. And
	/// it is so for a declaration the candidate's module cannot reach. A path from the candidate through a type whose
	/// declaration the candidate's module does not read, such as an implementation of a protocol that a module depending
	/// on it provides, decides no candidate (`SeamCandidateOnPaths`): the seam would take a builder for that type, which
	/// this module fills. Any other declaration – the candidate's own initializer, or one of a type in its tree, in the
	/// candidate's module or another it reads, including one that receives a property from above the candidate – is
	/// called only inside the candidate's module. A required parameter whose type
	/// is narrower than the candidate's type makes the declared seam an error in its own module
	/// (`tierOmitsRequiredParameter`), which says what to narrow or widen, never at this declaration.
	/// - Parameter extendedTypes: The declarations the module reads, among which the declaration of a type an extension
	///   extends bounds the types declared in or by that extension.
	private static func seamRemedy(
		offeredBy candidate: Instantiable,
		toWiden accessNeed: AccessNeed,
		declaredIn declaringModule: ModuleIdentity,
		extendedTypes: ExtendedTypeDeclarations,
	) -> DependencyTreeGeneratorError.InaccessibleConstruction.SeamRemedy? {
		guard buildsTree(candidate),
		      let moduleName = candidate.moduleName,
		      !(seamLeafAccessNeeds(of: candidate) + extendedTypeAccessNeeds(of: candidate, in: extendedTypes)).contains(where: { $0.access == accessNeed.access }),
		      accessNeed.level.satisfies(AccessLevel.required(
		      	toConstructFrom: ModuleIdentity(moduleName: moduleName, packageName: candidate.packageName),
		      	declaredIn: declaringModule,
		      	isOwnFile: false,
		      ))
		else { return nil }
		return .init(type: candidate.concreteInstantiable, moduleName: moduleName)
	}

	/// What identifies a construction while walking a tree: the scope that builds it, and how it builds it.
	private struct ConstructionKey: Hashable {
		let scope: ObjectIdentifier
		let usesMockMethod: Bool
	}

	/// The constructions the code generated for the tree rooted at `rootScope` emits: the root's own, and each scope
	/// the tree instantiates, transitively – the trees of the fills of each seam call it makes included – once each, in
	/// no particular order.
	/// - Parameters:
	///   - rootIsConstructedWithMockMethod: Whether the root is constructed with its hand-written mock method.
	///   - rootReferenceLocation: Where this module refers to the root.
	///   - isMock: Whether the tree is a mock's, which constructs each type it builds with its hand-written mock method
	///     where that method returns a type the property accepts, as `ScopeGenerator` builds it.
	///   - emittingModule: The module the generated code compiles in, whose own files hold the dependencies that refer
	///     to a construction.
	///   - extendedTypes: The declarations the module reads, among which the declaration of a type an extension
	///     extends bounds the types declared in or by that extension.
	private static func constructions(
		inTreeRootedAt rootScope: Scope,
		rootIsConstructedWithMockMethod: Bool,
		rootReferenceLocation: Dependency.DeclarationLocation?,
		isMock: Bool,
		emittingModule: EmittingModule,
		extendedTypes: ExtendedTypeDeclarations,
		leavingOut typesLeftOut: Set<TypeDescription> = [],
	) -> [Construction] {
		var constructionsByKey = [ConstructionKey: Construction]()
		// A scope can be reached along several paths, and the first reference location in source order is kept,
		// whichever path is walked first, with that path's public mock candidate, while every path has its say in the
		// seam candidate. A scope is walked again only when it is reached with an earlier reference location or what its
		// paths decide about the seam candidate changes, which only narrows, so the walk ends, and a worklist rather than
		// recursion walks it, since a tree can be as deep as the module has types.
		/// Whether `instantiable` is a seam candidate on a path that has none above it: see `SeamCandidateOnPaths`.
		func isSeamCandidate(_ instantiable: Instantiable) -> Bool {
			guard !isMock, let moduleName = instantiable.moduleName else { return false }
			return moduleName != emittingModule.identity.moduleName
		}
		var moduleNamesReadByModuleName = [String: Set<String>]()
		/// Whether the run of `generate` for `candidate`'s module reads the declaration of `child`, a type on a path from
		/// `candidate`: see `SeamCandidateOnPaths`. A type whose module SafeDI does not know is read by no other module.
		func candidatesModuleReads(_ child: Instantiable, _ candidate: Instantiable) -> Bool {
			guard let childModuleName = child.moduleName, let candidateModuleName = candidate.moduleName else { return false }
			let moduleNamesRead = moduleNamesReadByModuleName[candidateModuleName] ?? emittingModule.modulesReadByRunOfModule?(candidateModuleName).moduleNames ?? []
			moduleNamesReadByModuleName[candidateModuleName] = moduleNamesRead
			return moduleNamesRead.contains(childModuleName)
		}
		/// The seam that `scope` builds inline, referred to at `referenceLocation`, when the tree is a production tree of a
		/// module SafeDI cannot name and another module declares the seam: see `Construction.inlineSeam`.
		func inlineSeam(builtBy scope: Scope, referencedAt referenceLocation: Dependency.DeclarationLocation?) -> DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam? {
			guard !isMock,
			      emittingModule.identity.moduleName == nil,
			      scope.instantiable.generatesDependencyTree,
			      scope.seamCall == nil,
			      !(scope.instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false)
			else { return nil }
			return .init(type: scope.instantiable.concreteInstantiable, referenceLocation: referenceLocation)
		}
		/// What a type another module declares, `instantiable`, offers a mock of this module that builds its tree: `nil`
		/// for a type with a hand-written mock, which the mock calls, one this module declares, or one that cannot have a
		/// public mock as it is declared: an extension's, which the macro rejects `generateMock: .public` on, or one an
		/// enclosing type, or the type an enclosing extension extends, keeps narrower than `public`.
		func candidate(of instantiable: Instantiable) -> PublicMockCandidate? {
			guard isMock,
			      !instantiable.declarationType.isExtension,
			      instantiable.mockInitializer == nil,
			      !(instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false),
			      instantiable.enclosingTypeAccess.enumerated().allSatisfy({ enclosingType in
			      	AccessLevel.ownLevel(of: enclosingType.element, directlyInside: enclosingType.offset == 0 ? instantiable.enclosingExtensionAccess : nil).satisfies(.public)
			      }),
			      Self.extendedTypeAccessNeeds(of: instantiable, in: extendedTypes).allSatisfy({ $0.level.satisfies(.public) })
			else { return nil }
			let isPublic = AccessLevel.effective(ofTypeDeclaredBy: instantiable).satisfies(.public)
			if let moduleName = instantiable.moduleName {
				// A public mock of a type of a module SafeDI knows is called wherever the tree cannot be built; a type narrower
				// than `public` – a seam under adoption is usually `package` – needs that declaration widened too.
				return moduleName != emittingModule.identity.moduleName && instantiable.generateMock != .public
					? .withoutMock(instantiable.concreteInstantiable, declaringModuleName: moduleName, needsPublicDeclaration: !isPublic, isSeam: instantiable.generatesDependencyTree)
					: nil
			} else {
				guard isPublic else { return nil }
				return instantiable.generateMock == .public
					? .publicMockOfUnknownModule(instantiable.concreteInstantiable, emittingModuleIsUnknown: emittingModule.identity.moduleName == nil)
					: .withoutMock(instantiable.concreteInstantiable, declaringModuleName: nil, needsPublicDeclaration: false, isSeam: instantiable.generatesDependencyTree)
			}
		}
		// The root is the module's own, or a mock's, so it is neither a seam candidate nor a seam built inline.
		var scopesToWalk = [(scope: rootScope, usesMockMethod: rootIsConstructedWithMockMethod, referenceLocation: rootReferenceLocation, seamCandidateOnPaths: SeamCandidateOnPaths.agreed(nil), inlineSeamOnPath: DependencyTreeGeneratorError.InaccessibleConstruction.InlineSeam?.none, publicMockCandidate: candidate(of: rootScope.instantiable))]
		while let (scope, usesMockMethod, referenceLocation, seamCandidateOnPaths, inlineSeamOnPath, publicMockCandidate) = scopesToWalk.popLast() {
			let key = ConstructionKey(scope: ObjectIdentifier(scope), usesMockMethod: usesMockMethod)
			let walkedConstruction = constructionsByKey[key]
			let isEarliestPath = walkedConstruction.map { Dependency.DeclarationLocation.precedesInSourceOrder(referenceLocation, $0.referenceLocation) } ?? true
			let mergedSeamCandidateOnPaths = walkedConstruction.map { $0.seamCandidateOnPaths.merged(with: seamCandidateOnPaths) } ?? seamCandidateOnPaths
			guard isEarliestPath || mergedSeamCandidateOnPaths != walkedConstruction?.seamCandidateOnPaths else {
				continue
			}
			constructionsByKey[key] = Construction(
				instantiable: scope.instantiable,
				usesMockMethod: usesMockMethod,
				referenceLocation: isEarliestPath ? referenceLocation : walkedConstruction?.referenceLocation,
				isSeamLeaf: scope.seamCall != nil,
				extendedTypes: extendedTypes,
				publicMockCandidate: isEarliestPath ? publicMockCandidate : walkedConstruction?.publicMockCandidate,
				seamCandidateOnPaths: mergedSeamCandidateOnPaths,
				inlineSeam: isEarliestPath ? inlineSeamOnPath : walkedConstruction?.inlineSeam,
			)
			let isDeclaredInOwnFile = scope.instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate
				where !typesLeftOut.contains(childScope.instantiable.concreteInstantiable)
			{
				// A dependency the mock promotes to its root, or retypes there, is declared by no type of the tree.
				let childReferenceLocation = isDeclaredInOwnFile
					? scope.instantiable.dependencies.first(where: { $0.property == property })?.declarationLocation ?? referenceLocation
					: referenceLocation
				scopesToWalk.append((
					scope: childScope,
					usesMockMethod: isMock && childScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType),
					referenceLocation: childReferenceLocation,
					// Every path to the child through this scope extends a path to this scope.
					seamCandidateOnPaths: mergedSeamCandidateOnPaths.extended(to: childScope.instantiable, childIsCandidate: isSeamCandidate(childScope.instantiable), candidatesModuleReads: candidatesModuleReads),
					inlineSeamOnPath: inlineSeamOnPath ?? inlineSeam(builtBy: childScope, referencedAt: childReferenceLocation),
					publicMockCandidate: publicMockCandidate ?? candidate(of: childScope.instantiable),
				))
			}
			// A seam call's fills are constructions of this module's code: the fulfilling type and its tree, built with
			// their initializers as the type's own module builds them, reached where the call is. A mock's tree calls no
			// seam's generated initializer, and fills another module's public mock's builder only where every construction
			// of the fill is one this module can reach (`holesFilled(byCallsOf:in:)`), so only a production tree's fills
			// are walked. A fill starts a path of its own, whose candidate is the fill's type when another module SafeDI
			// knows declares it: declared a seam, that module builds the type's tree and the fill calls the initializer
			// generated for it. No candidate above the seam reaches the fill: a type above the seam declared a seam would
			// pass the builder up to this module whenever its own module cannot see the fulfilling type, so it would keep
			// the fill out of this module for no path.
			if !isMock {
				for case let .fill(_, fillScope) in scope.holeArguments {
					scopesToWalk.append((
						scope: fillScope,
						usesMockMethod: false,
						referenceLocation: referenceLocation,
						seamCandidateOnPaths: SeamCandidateOnPaths.agreed(nil).extended(to: fillScope.instantiable, childIsCandidate: isSeamCandidate(fillScope.instantiable), candidatesModuleReads: candidatesModuleReads),
						inlineSeamOnPath: inlineSeamOnPath ?? inlineSeam(builtBy: fillScope, referencedAt: referenceLocation),
						publicMockCandidate: nil,
					))
				}
			}
		}
		return Array(constructionsByKey.values)
	}

	// MARK: Public mocks of other modules

	/// The public mock another module generated for each type this module's mock trees reach but cannot build: a type
	/// declared with `generateMock: .public` in a module SafeDI knows, whose tree, as this module would build it inline
	/// – the public mocks of other types in it called, as they are wherever they cannot be built – constructs a
	/// declaration this module cannot reach. A tree this module can build is built inline, as before public mocks.
	private func publicMockCalls(in typeDescriptionToScopeMap: [TypeDescription: Scope]) async throws -> [TypeDescription: PublicMockCall] {
		guard !seams.foreignPublicMocks.isEmpty, let emittingModule = emittingModuleToCheck else { return [:] }
		let foreignPublicMockTypes = Set(seams.foreignPublicMocks.keys)
		var publicMockCalls = [TypeDescription: PublicMockCall]()
		var receivedPropertiesCache = ReceivedPropertiesCache()
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
			guard !Self.inaccessibleConstructions(constructions, from: emittingModule, extendedTypes: extendedTypeDeclarations).isEmpty, let ownPlan = try await foreignPublicMockPlan(of: type, declaredBy: foreignPublicMock, modulesReadByRunOfModule: emittingModule.modulesReadByRunOfModule) else { continue }
			let requirement = AccessLevel.required(toConstructFrom: emittingModule.identity, declaredIn: foreignPublicMock.declaringModule, isOwnFile: false)
			// The narrowest tier the module reaches: every module reaches the `public` one.
			let tier = ownPlan.plan.tiers.last { $0.satisfies(requirement) } ?? .public
			let tierParameters = ownPlan.plan.parameters(ofTier: tier)
			publicMockCalls[type] = PublicMockCall(
				type: type,
				tier: tier,
				passedParameters: tierParameters.compactMap { parameter in
					switch parameter.role {
					case let .forwarded(property):
						PublicMockCall.PassedParameter(name: parameter.name, type: parameter.type, dependency: Dependency(property: property, source: .forwarded, declarationLocation: ownPlan.instantiable.declarationLocation), isBuiltWhenNil: false, builder: nil)
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
								declarationLocation: ownPlan.instantiable.declarationLocation,
							),
							isBuiltWhenNil: parameter.isBuiltWhenNil,
							builtWrapper: parameter.builtWrapper,
							builder: parameter.builder,
						)
					case .constructionDefault, .overrides:
						nil
					}
				},
				// Every parameter a narrower tier takes is a received dependency or a default-valued parameter: a narrower
				// required one keeps the public tier from being generated.
				omittedParameters: ownPlan.plan.parameters.filter { parameter in
					guard parameter.access < tier, case .received = parameter.role else { return false }
					return true
				} + ownPlan.plan.noTierParameters,
				takesOverrides: tierParameters.contains { parameter in
					if case .overrides = parameter.role {
						true
					} else {
						false
					}
				},
				guardTypeName: ownPlan.plan.guardTypeName,
				comment: foreignPublicMock.callComment,
				declaringModule: foreignPublicMock.declaringModule,
				callerModule: emittingModule.identity,
				requirement: requirement,
				declaringModuleMockCondition: foreignPublicMock.declaringModuleMockCondition,
				callerModuleMockCondition: seams.currentModuleMockCondition,
				receiversByLabel: ownPlan.receiversByLabel,
				typesDeclaredEscaping: ownPlan.typesDeclaredEscaping.intersection(tierParameters.map(\.type)),
				holes: (ownPlan.plan.holes + ownPlan.plan.unpresentedHoles).map { $0.atTier(tier) },
				builders: ownPlan.plan.builders.map { $0.atTier(tier) },
				scopeEnums: ownPlan.plan.scopeEnums,
			)
		}
		return publicMockCalls
	}

	/// The plan of the public mock that `foreignPublicMock`'s module generated for `type`, computed as that module
	/// computed it, from the declarations it sees; `nil` when that module could not generate it, which its own run
	/// reports.
	/// - Parameter modulesReadByRunOfModule: See `EmittingModule.init`.
	private func foreignPublicMockPlan(
		of type: TypeDescription,
		declaredBy foreignPublicMock: SeamResolution.ForeignPublicMock,
		modulesReadByRunOfModule: (@Sendable (_ moduleName: String) -> TypeAccessProof.ModuleReach.ModulesRead)?,
	) async throws -> OwnPublicMockPlan? {
		guard let moduleName = foreignPublicMock.declaringModule.moduleName else { return nil }
		let generator: DependencyTreeGenerator
		if let existingGenerator = publicMockGeneratorsByModuleName[moduleName] {
			generator = existingGenerator
		} else {
			generator = DependencyTreeGenerator(
				importStatements: [],
				mockImportStatements: [],
				typeDescriptionToFulfillingInstantiableMap: foreignPublicMock.visibleInstantiables,
				aliasDeclarationReferences: aliasDeclarationReferences,
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
						entry.value.declaringModule.moduleName != moduleName && foreignPublicMock.visibleInstantiables[entry.key] != nil
					},
					// The views of every module, so that the plans this one computes in turn read what each of those modules
					// saw, never what this module's filter left: under module info a public mock two modules beneath this one
					// is not among the public mocks this module sees.
					foreignDeclarationsSeenByModule: seams.foreignDeclarationsSeenByModule,
				),
				plainTypeDeclarations: foreignPublicMock.visiblePlainTypeDeclarations,
			)
			publicMockGeneratorsByModuleName[moduleName] = generator
		}
		return try await generator.publicMockPlan(ofOwnType: type)
	}

	/// The finding that the modules calling the public mock of `instantiable` compute another signature for it, when
	/// the declarations they see differ from this run's (`SeamResolution.callersVisibleInstantiables`), as a seam's
	/// callers' view is checked: the mock is computed again over the callers' view, as they compute it, and a mock whose
	/// guard – which hashes what every call depends on – they compute otherwise is reported, naming
	/// a declaration they cannot see, in a seam's three tiers: the earliest by source location of those that declare a
	/// receiver of a parameter the callers would not take as such, else of those that fulfill such a parameter's type,
	/// else of those the mock's tree reaches. `nil` when the callers compute the same guard, or see every declaration
	/// the tree reaches.
	private func callersViewFinding(of instantiable: Instantiable) async throws -> PublicMockFinding? {
		guard let callersVisibleInstantiables = seams.callersVisibleInstantiables else { return nil }
		let type = instantiable.concreteInstantiable
		guard let ownPlan = try await publicMockPlan(ofOwnType: type) else { return nil }
		let callersGenerator = DependencyTreeGenerator(
			importStatements: [],
			mockImportStatements: [],
			typeDescriptionToFulfillingInstantiableMap: callersVisibleInstantiables,
			aliasDeclarationReferences: aliasDeclarationReferences,
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

	/// The generators of the modules whose public mocks this module's mock trees call, by module name.
	private var publicMockGeneratorsByModuleName = [String: DependencyTreeGenerator]()

	/// The mock scopes `publicMockPlan(ofOwnType:)` builds its mock roots from, once built.
	private var memoizedPublicMockPlanScopes: MockScopes?

	/// The plan of the public mock of `type`, declared with `generateMock: .public` among this generator's
	/// declarations, as its module computes it: the type's mock root is built as `generateMockCode` builds it. The
	/// module's own run reports what keeps its public mock from being generated.
	private func publicMockPlan(ofOwnType type: TypeDescription) async throws -> OwnPublicMockPlan? {
		guard let declaredInstantiable = typeDescriptionToFulfillingInstantiableMap[type],
		      declaredInstantiable.generateMock == .public
		else { return nil }
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let mockScopes: MockScopes
		if let memoizedPublicMockPlanScopes {
			mockScopes = memoizedPublicMockPlanScopes
		} else {
			mockScopes = try await self.mockScopes(additionalMocksToGenerate: [], mockEmittingModule: emittingModuleToCheck, receivedPropertiesCache: &receivedPropertiesCache)
			memoizedPublicMockPlanScopes = mockScopes
		}
		let rootMockScopes = mockScopes.forMockRoot(declaredInstantiable)
		guard let scope = rootMockScopes.typeDescriptionToScopeMap[declaredInstantiable.concreteInstantiable] else { return nil }
		let instantiable = mockRootInstantiable(for: declaredInstantiable, scope: scope)
		var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
		var promotedScopesValidatedForHiddenReceives = Set<ObjectIdentifier>()
		let mockRoot = try await createMockRoot(
			for: instantiable,
			scope: scope,
			generatedMockReason: .generateMock,
			mockScopes: rootMockScopes,
			// The declaring module's own run checked its constructions.
			emittingModule: nil,
			receivedPropertiesCache: &receivedPropertiesCache,
			childrenRequiringEachOtherValidation: &childrenRequiringEachOtherValidation,
			promotedScopesValidatedForHiddenReceives: &promotedScopesValidatedForHiddenReceives,
		)
		let context = publicMockContext
		let parameters = await mockRoot.mockRootParameters(instantiable: instantiable, mockDefaults: mockScopes.flatParameterMockDefaults)
		return OwnPublicMockPlan(
			instantiable: instantiable,
			plan: ScopeGenerator.publicMockPlan(
				of: instantiable,
				parameters: parameters,
				parameterNames: ScopeGenerator.mockRootParameterNames(of: parameters),
				context: context,
			),
			receiversByLabel: ScopeGenerator.receivers(in: parameters.parameterTree, mockedType: instantiable),
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
	private static func publicMockLeafInstantiable(of instantiable: Instantiable, calling publicMockCall: PublicMockCall, takesBuildersFromOwnEnums: Bool) -> Instantiable {
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
	private static func inaccessibleConstructions(
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
	private func builtInlineSeamComment(for instantiable: Instantiable) -> String? {
		guard instantiable.generatesDependencyTree,
		      seams.foreignSeams[instantiable.concreteInstantiable] == nil,
		      !seams.generatedSeams.contains(instantiable.concreteInstantiable)
		else { return nil }
		return "// Built inline: SafeDI does not know which module declares `\(instantiable.concreteInstantiable.asSource)`, so this tree cannot call the initializer SafeDI generates for it."
	}

	// MARK: Seams

	/// The concrete types of the seams this module generates the initializers of: those declared in its own files,
	/// among the declarations it reads.
	private lazy var generatedSeamTypes: Set<TypeDescription> = Set(
		typeDescriptionToFulfillingInstantiableMap
			.values
			.filter { $0.generatesDependencyTree && seams.generatedSeams.contains($0.concreteInstantiable) }
			.map(\.concreteInstantiable),
	)

	/// The types at the roots of the trees validation walks: the roots of the dependency tree and the seams this
	/// module generates, whose trees it validates as it validates a root's, with what each tree receives from outside
	/// the seam fulfilled by the seam's parameters.
	private lazy var validatedRootInstantiables: Set<TypeDescription> = rootInstantiables.union(generatedSeamTypes)

	/// A module declaring seams that this module's trees, or a computed module's visible trees, reach: its name and
	/// its seams, in type order.
	private struct ReachedForeignModule {
		let moduleName: String
		let seams: [(type: TypeDescription, seam: SeamResolution.ForeignSeam)]
	}

	/// Validates that this run reads each seam of another module that the trees it generates call as that module reads
	/// it. Under the SwiftPM plugin's target graph, this run computes such a seam's signature from the module's files as
	/// it parsed them, under its own mock condition, which selects the module's mock-only declarations – whose mock
	/// methods can prove a parameter's type – as the module's own run does only when the two conditions are spelled the
	/// same. A seam whose module's condition is spelled otherwise is reported at the first dependency, in source order,
	/// that instantiates it in a tree this module generates: an own root's, since a root another module declares is left
	/// to that module, or an own seam's, without entering another module's seam, whose tree that module generates.
	private func validateCalledSeamModulesShareMockCondition() throws {
		var seamModuleMockConditionBySeam = [TypeDescription: (seam: SeamResolution.ForeignSeam, mockCondition: MockCondition)]()
		for (seamType, foreignSeam) in seams.foreignSeams {
			if let mockCondition = foreignSeam.declaringModuleMockCondition, mockCondition != seams.currentModuleMockCondition {
				seamModuleMockConditionBySeam[seamType] = (foreignSeam, mockCondition)
			}
		}
		// A run that reads another module's files under its own mock condition knows its module.
		guard let emittingModule, !seamModuleMockConditionBySeam.isEmpty else { return }
		let ownRoots = rootInstantiables.filter { root in
			typeDescriptionToFulfillingInstantiableMap[root]?.sourceFilePath.map(emittingModule.isOwnFile) == true
		}
		var differenceBySeam = [TypeDescription: DependencyTreeGeneratorError.SeamModuleMockConditionDifference]()
		var visitedTypes = Set<TypeDescription>()
		// A worklist rather than recursion, since a chain of types can be as long as the module has types.
		var typesToVisit = Array(ownRoots.union(generatedSeamTypes))
		while let visitedType = typesToVisit.popLast() {
			guard visitedTypes.insert(visitedType).inserted,
			      let instantiable = typeDescriptionToFulfillingInstantiableMap[visitedType]
			else { continue }
			for dependency in instantiable.dependencies where dependency.isInstantiated {
				let instantiatedType = dependency.asInstantiatedType
				guard let seamType = typeDescriptionToFulfillingInstantiableMap[instantiatedType]?.concreteInstantiable else { continue }
				if seams.foreignSeams[seamType] == nil {
					typesToVisit.append(instantiatedType)
				} else if let (foreignSeam, mockCondition) = seamModuleMockConditionBySeam[seamType],
				          differenceBySeam[seamType].map({ Self.declarationPrecedes(dependency.declarationLocation, $0.callingDependencyLocation) }) ?? true
				{
					differenceBySeam[seamType] = DependencyTreeGeneratorError.SeamModuleMockConditionDifference(
						seam: seamType,
						seamModule: foreignSeam.declaringModule,
						seamModuleMockCondition: mockCondition,
						callingModule: seams.currentModule,
						callingModuleMockCondition: seams.currentModuleMockCondition,
						callingDependencyLocation: dependency.declarationLocation,
					)
				}
			}
		}
		if !differenceBySeam.isEmpty {
			throw DependencyTreeGeneratorError.seamModuleMockConditionDiffers(Array(differenceBySeam.values))
		}
	}

	/// The signature of each foreign seam this module's trees reach, by concrete type, or `nil` for a seam whose
	/// generated signature equals its own initializer's (see `seamRoots`), computed before the inlined trees are
	/// validated: a module info this run lacks is then reported with its remedy, rather than as the dependencies
	/// that module's declarations would have fulfilled.
	///
	/// Memoized by hand rather than declared `lazy`, as is `seamRoots`: inside a closure, a lazy initializer of an
	/// actor's property cannot call an actor-isolated function on every supported compiler. Swift 6.2.0 rejects a
	/// call to a local function that captures `self` ("actor-isolated default value in a actor-isolated context"),
	/// and Swift 6.4 a call to a method or a computed property ("cannot use default value from different instance").
	private var foreignSeamRoots: Result<[TypeDescription: ScopeGenerator.SeamRoot?], any Error> {
		let foreignSeamRoots = memoizedForeignSeamRoots ?? Result { try computeForeignSeamRoots() }
		memoizedForeignSeamRoots = foreignSeamRoots
		return foreignSeamRoots
	}

	/// `foreignSeamRoots`, once computed.
	private var memoizedForeignSeamRoots: Result<[TypeDescription: ScopeGenerator.SeamRoot?], any Error>?

	/// Computes `foreignSeamRoots`.
	private func computeForeignSeamRoots() throws -> [TypeDescription: ScopeGenerator.SeamRoot?] {
		var seamRoots = [TypeDescription: ScopeGenerator.SeamRoot?]()
		var errors = [DependencyTreeGeneratorError]()
		// Only the foreign seams this module's trees reach are computed, each from what its module sees, and a seam
		// of a third module that such a module's visible trees reach before it, so the modules are computed in
		// dependency order, each once, from an explicit stack: a module is pushed back under the modules it needs.
		// A module's own trees find the seams of the modules it sees, which are this run's direct dependencies' for
		// this module's trees, and the declaring module's, from its view, for a computed module's: a seam this module
		// reads only in a view is never matched against this module's own types.
		var seamsByModuleName = [String: [TypeDescription: SeamResolution.ForeignSeam]]()
		// A module's seams are read from one declaration of each, so every map that holds one holds the same.
		let seenModuleMaps = (seams.foreignDeclarationsSeenByModule ?? [:]).sorted { $0.key < $1.key }.map(\.value.seams)
		for foreignSeams in [seams.foreignSeams] + seenModuleMaps {
			for (type, seam) in foreignSeams {
				if let moduleName = seam.declaringModule.moduleName {
					seamsByModuleName[moduleName, default: [:]][type] = seam
				}
			}
		}
		let foreignModulesByName = seamsByModuleName.map { moduleName, seamsByType in
			ReachedForeignModule(moduleName: moduleName, seams: seamsByType.sorted { $0.key < $1.key }.map { (type: $0.key, seam: $0.value) })
		}
		func foreignModules(reachedFrom roots: Set<TypeDescription>, in instantiables: [TypeDescription: Instantiable], seenBy moduleName: String?) -> [ReachedForeignModule] {
			let foreignSeams = moduleName.map { seams.foreignDeclarations(seenByModuleNamed: $0).seams } ?? seams.foreignSeams
			// A reached key is looked up through the map, so a seam reached as one of its additional types counts,
			// and a key the map does not hold – a type the module cannot see – reaches nothing.
			let reachedModuleNames = Set(Self.typesReachable(fromRoots: roots, in: instantiables).compactMap { instantiables[$0].flatMap { foreignSeams[$0.concreteInstantiable]?.declaringModule.moduleName } }).subtracting([moduleName].compactMap(\.self))
			return foreignModulesByName.filter { reachedModuleNames.contains($0.moduleName) }.sorted { $0.moduleName < $1.moduleName }
		}
		var computedModules = Set<String>()
		var expandedModules = Set<String>()
		var modulesToCompute = Array(foreignModules(reachedFrom: reachableTypeDescriptions, in: typeDescriptionToFulfillingInstantiableMap, seenBy: nil).reversed())
		while let module = modulesToCompute.last {
			guard !computedModules.contains(module.moduleName) else {
				modulesToCompute.removeLast()
				continue
			}
			let moduleSeam = module.seams[0].seam
			// A module's reached modules are pushed above it on its first visit only; on its second it is computed
			// with the signatures found by then, so the loop ends whatever the module infos claim to reach.
			if expandedModules.insert(module.moduleName).inserted {
				let dependencies = foreignModules(reachedFrom: Set(module.seams.map(\.type)), in: moduleSeam.visibleInstantiables, seenBy: module.moduleName)
					.filter { !computedModules.contains($0.moduleName) }
				if !dependencies.isEmpty {
					modulesToCompute.append(contentsOf: dependencies.reversed())
					continue
				}
			}
			modulesToCompute.removeLast()
			computedModules.insert(module.moduleName)
			// A module info a build wrote holds seams that module's own run validated from the declarations it saw,
			// which this run reads the same way; one from a run that failed, or that was given other declarations,
			// can hold a tree this run cannot build, which is reported with the other seam errors.
			let computation = try Self.seamSignatures(
				forSeams: Set(module.seams.map(\.type)),
				in: moduleSeam.visibleInstantiables,
				plainTypeDeclarations: moduleSeam.visiblePlainTypeDeclarations,
				aliasDeclarationReferences: aliasDeclarationReferences,
				fixedSignatures: seamRoots.compactMapValues(\.self),
				callerModule: moduleSeam.declaringModule,
				seams: seams.resolution(seenByModuleNamed: module.moduleName),
				// Another module's own run checks its constructions; whether that check reports a call is not known
				// here, so an omission such a call would let its seam skip is reported.
				checkingModule: nil,
				// Another module's seams are computed from its named module's declarations.
				isOwnFile: nil,
				modulesReadByRunOfModule: emittingModule?.modulesReadByRunOfModule,
			)
			errors += computation.errors
			for (seamType, seamRoot) in computation.seamRoots where !computation.failedSeams.contains(seamType) {
				seamRoots[seamType] = seamRoot
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
		return seamRoots
	}

	/// The signature of each seam this module generates or calls, by concrete type, or `nil` for a seam whose
	/// generated signature would equal its own initializer's – one with no `@Instantiated` or aliased dependency and
	/// no pass-through – which is built with that initializer wherever a tree reaches it, as any other type is, and
	/// whose file holds no code. Memoized by hand rather than declared `lazy`, for the reason `foreignSeamRoots` gives:
	/// `generateDOTTree()`, run after `generatePerRootCodeTrees()`, reads it again.
	private var seamRoots: Result<[TypeDescription: ScopeGenerator.SeamRoot?], any Error> {
		let seamRoots = memoizedSeamRoots ?? Result { try computeSeamRoots() }
		memoizedSeamRoots = seamRoots
		return seamRoots
	}

	/// `seamRoots`, once computed.
	private var memoizedSeamRoots: Result<[TypeDescription: ScopeGenerator.SeamRoot?], any Error>?

	/// Computes `seamRoots`.
	private func computeSeamRoots() throws -> [TypeDescription: ScopeGenerator.SeamRoot?] {
		var seamRoots = try foreignSeamRoots.get()
		let ownComputation = try Self.seamSignatures(
			forSeams: generatedSeamTypes,
			in: typeDescriptionToFulfillingInstantiableMap,
			plainTypeDeclarations: plainTypeDeclarations,
			aliasDeclarationReferences: aliasDeclarationReferences,
			fixedSignatures: seamRoots.compactMapValues(\.self),
			callerModule: seams.currentModule,
			seams: seams,
			checkingModule: emittingModuleToCheck,
			isOwnFile: emittingModule?.isOwnFile,
			modulesReadByRunOfModule: emittingModule?.modulesReadByRunOfModule,
		)
		var errors = ownComputation.errors
		// Each generated seam is computed again over the declarations its callers see, when those differ from this
		// run's (under the target graph, a directory the configuration adds). A seam whose call shape – what a call depends on, and the guard hashes: each parameter's label, type,
		// tier access and default, and the tiers, never the receivers or the uncapped access – the callers compute
		// otherwise, or cannot compute, is reported at the seam, naming a declaration the callers cannot see: one that
		// declares a receiver of a parameter the callers would not take – where they could not compute it, one the
		// error they hit names – else one that fulfills such a parameter's type, else one the seam's tree reaches, the
		// first by source location in each. A seam whose call shape the callers compute the same is not reported,
		// whatever its tree reaches, and a seam this run could not compute is reported with its own error alone.
		// `reportingAll` orders the errors by source location.
		if let callersVisibleInstantiables = seams.callersVisibleInstantiables, !ownComputation.seamRoots.isEmpty {
			let unseenDeclarations = Set(typeDescriptionToFulfillingInstantiableMap.values.map(\.concreteInstantiable))
				.subtracting(callersVisibleInstantiables.values.map(\.concreteInstantiable))
			let callersComputation = try Self.seamSignatures(
				forSeams: generatedSeamTypes,
				in: callersVisibleInstantiables,
				plainTypeDeclarations: seams.callersVisiblePlainTypeDeclarations,
				aliasDeclarationReferences: aliasDeclarationReferences,
				fixedSignatures: seamRoots.compactMapValues(\.self),
				callerModule: seams.currentModule,
				seams: seams,
				checkingModule: emittingModuleToCheck,
				isOwnFile: emittingModule?.isOwnFile,
				modulesReadByRunOfModule: emittingModule?.modulesReadByRunOfModule,
			)
			for seamType in generatedSeamTypes.sorted() {
				guard let seam = typeDescriptionToFulfillingInstantiableMap[seamType],
				      !ownComputation.failedSeams.contains(seamType),
				      let ownSeamRoot = ownComputation.seamRoots[seamType]
				else { continue }
				let ownSignature = ownSeamRoot?.signature
				let callersFailed = callersComputation.failedSeams.contains(seamType)
				let callersSignature: SeamSignature? = callersFailed ? nil : (callersComputation.seamRoots[seamType] ?? nil)?.signature
				guard callersFailed || ownSignature?.callShape != callersSignature?.callShape else { continue }
				let labelsCallersFailedOn = callersFailed ? Self.parameterLabels(namedBy: callersComputation.errors, about: seam) : nil
				if let declaration = Self.unseenDeclarationToName(
					for: seam,
					ownSignature: ownSignature,
					callersSignature: callersSignature,
					labelsCallersFailedOn: labelsCallersFailedOn,
					unseenDeclarations: unseenDeclarations,
					in: typeDescriptionToFulfillingInstantiableMap,
					proof: ownComputation.proof,
				) {
					errors.append(.seam(.init(seam: seam, kind: .treeReachesDeclarationCallersCannotSee(declaration: declaration))))
				} else if let plainDeclaration = Self.unseenPlainDeclarationToName(
					ownSignature: ownSignature,
					callersSignature: callersSignature,
					labelsCallersFailedOn: labelsCallersFailedOn,
				) {
					errors.append(.seam(.init(
						seam: seam,
						kind: .treeReachesPlainDeclarationCallersCannotSee(declaration: plainDeclaration),
					)))
				}
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
		for (seamType, seamRoot) in ownComputation.seamRoots {
			seamRoots[seamType] = seamRoot
		}
		return seamRoots
	}

	/// The parameters of `ownSignature` a seam's callers would not pass as this run declares them: those
	/// `labelsCallersFailedOn` names, where the callers could not compute the signature and the error they hit names a
	/// parameter, else those whose call shape `callersSignature` does not hold.
	private static func differingParameters(
		ownSignature: SeamSignature?,
		callersSignature: SeamSignature?,
		labelsCallersFailedOn: Set<String>?,
	) -> [SeamSignature.Parameter] {
		let callersParameterShapes = Set(callersSignature?.callShape.parameters ?? [])
		return (ownSignature?.parameters ?? []).filter { parameter in
			if let labelsCallersFailedOn, !labelsCallersFailedOn.isEmpty {
				labelsCallersFailedOn.contains(parameter.property.label)
			} else {
				!callersParameterShapes.contains(SeamSignature.CallShape.Parameter(parameter))
			}
		}
	}

	/// The declaration the callers of `seam` cannot see that a report of the seam names, from `unseenDeclarations`, in
	/// three tiers: the earliest by source location of those that declare a receiver of a parameter of `ownSignature`
	/// the callers would not take as such – one whose call shape `callersSignature` lacks, or, when the callers'
	/// computation threw, one whose label the thrown error names (`labelsCallersFailedOn`; every parameter when it
	/// names none); only if there is none, the earliest of those that fulfill such a parameter's type; only if there is
	/// none, the earliest the seam's tree reaches. So a name decides nothing, and a declaration whose absence alone
	/// changes nothing is named only when no other can be. `nil` when the callers see every declaration the seam
	/// reaches.
	private static func unseenDeclarationToName(
		for seam: Instantiable,
		ownSignature: SeamSignature?,
		callersSignature: SeamSignature?,
		labelsCallersFailedOn: Set<String>?,
		unseenDeclarations: Set<TypeDescription>,
		in typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
		proof: TypeAccessProof,
	) -> TypeDescription? {
		let differingParameters = differingParameters(ownSignature: ownSignature, callersSignature: callersSignature, labelsCallersFailedOn: labelsCallersFailedOn)
		func declarationPrecedes(_ left: TypeDescription, _ right: TypeDescription) -> Bool {
			Self.declarationPrecedes(typeDescriptionToFulfillingInstantiableMap[left]?.declarationLocation, typeDescriptionToFulfillingInstantiableMap[right]?.declarationLocation)
		}
		func earliestUnseen(_ types: [TypeDescription]) -> TypeDescription? {
			types.filter { unseenDeclarations.contains($0) }.min { left, right in
				declarationPrecedes(left, right) || (!declarationPrecedes(right, left) && left < right)
			}
		}
		if let receiver = earliestUnseen(differingParameters.flatMap { $0.receivers.map(\.declaringType) }) {
			return receiver
		} else if let provingDeclaration = earliestUnseen(differingParameters.flatMap { parameter in
			// The declarations a parameter's access depends on: the entries of the types it names, and the declarations
			// whose members mention those types, transitively through an extension's raised type.
			let admittedModules = Set([seam.moduleName] + parameter.receivers.map { typeDescriptionToFulfillingInstantiableMap[$0.declaringType]?.moduleName })
			let namedTypes = TypeAccessProof.mentionedTypes(in: parameter.property.typeDescription).compactMap { typeDescriptionToFulfillingInstantiableMap[$0]?.concreteInstantiable }
			return (namedTypes + proof.declarationsProving(typesNamedBy: parameter.property.typeDescription, admittedModules: admittedModules)).sorted()
		}) {
			return provingDeclaration
		} else {
			let reachedTypes = Self.typesReachable(fromRoots: [seam.concreteInstantiable], in: typeDescriptionToFulfillingInstantiableMap)
			return earliestUnseen(reachedTypes.compactMap { typeDescriptionToFulfillingInstantiableMap[$0]?.concreteInstantiable })
		}
	}

	/// The plain declaration the callers of a seam cannot see that a report of the seam names when no `@Instantiable`
	/// declaration explains why they compute its signature otherwise: the earliest by source location of the plain
	/// declarations whose module SafeDI knows no name of – which the callers' view drops – that prove a parameter of
	/// `ownSignature` the callers would not take as such (`unseenDeclarationToName(for:…)` decides which). Without it,
	/// the callers count the parameter's type as one SafeDI reads no declaration of, which is `public`. `nil` when no
	/// such declaration proves one.
	private static func unseenPlainDeclarationToName(
		ownSignature: SeamSignature?,
		callersSignature: SeamSignature?,
		labelsCallersFailedOn: Set<String>?,
	) -> PlainTypeDeclaration? {
		earliestUnseenPlainDeclaration(provingAnyOf: differingParameters(ownSignature: ownSignature, callersSignature: callersSignature, labelsCallersFailedOn: labelsCallersFailedOn).map(\.accessCause))
	}

	/// The earliest by source location of the plain declarations whose module SafeDI knows no name of – which a
	/// callers' view drops – that prove one of `causes`; `nil` when none does.
	static func earliestUnseenPlainDeclaration(provingAnyOf causes: [TypeAccessProof.Cause?]) -> PlainTypeDeclaration? {
		causes
			.flatMap { $0?.provingPlainDeclarations ?? [] }
			.filter { $0.moduleName == nil }
			.min { left, right in
				Dependency.DeclarationLocation.precedesInSourceOrder(left.access.declarationStartLocation, right.access.declarationStartLocation)
			}
	}

	/// The labels of the parameters of `seam` that `errors` – what a computation of the module's seams threw – name: the
	/// parameter a tier omits, the label two receives share, and the parameters of an initializer a tier would
	/// redeclare. Only a `SeamError.ParameterKind` names a parameter.
	private static func parameterLabels(namedBy errors: [DependencyTreeGeneratorError], about seam: Instantiable) -> Set<String> {
		var labels = Set<String>()
		var errorsToRead = errors
		while let error = errorsToRead.popLast() {
			if case let .independentErrors(errors) = error {
				errorsToRead += errors
			} else if case let .seam(seamError) = error,
			          seamError.seam.concreteInstantiable == seam.concreteInstantiable,
			          case let .parameters(parameterKind) = seamError.kind
			{
				switch parameterKind {
				case let .parametersShareLabel(label, _, _):
					labels.insert(label)
				case let .tierOmitsRequiredParameter(parameter, _, _, _, _, _):
					labels.insert(parameter.label)
				case let .initializerCollides(parameters, _, _):
					labels.formUnion(parameters.map(\.property.label))
				}
			}
		}
		return labels
	}

	/// Whether a declaration at `leftLocation` comes before one at `rightLocation` in source: by file path, then
	/// line, then column, with a declaration whose location is unknown – which none read from a file is – after every
	/// known one.
	private static func declarationPrecedes(_ leftLocation: Dependency.DeclarationLocation?, _ rightLocation: Dependency.DeclarationLocation?) -> Bool {
		func sortKey(of location: Dependency.DeclarationLocation?) -> (unknownLocationsLast: Int, filePath: String, line: Int, column: Int) {
			(location == nil ? 1 : 0, location?.filePath ?? "", location?.line ?? 0, location?.column ?? 0)
		}
		return sortKey(of: leftLocation) < sortKey(of: rightLocation)
	}

	/// The generators of the trees this module generates, in a world where every reach of a seam calls its generated
	/// initializer: the roots of the dependency tree, then the seams this module generates, each with its signature.
	private func seamWorldRootScopeGenerators() throws -> [RootScopeInfo] {
		let seamRoots = try seamRoots.get()
		// The generated code ends each construction with the comment the validated scopes would carry, the call of a
		// seam's tier included, whose construction the leaf's initializer at the tier's level describes.
		let seamScopeMap = Self.createSeamScopeMapping(
			in: typeDescriptionToFulfillingInstantiableMap,
			reachableTypeDescriptions: reachableTypeDescriptions,
			seamRoots: seamRoots,
			ownSeamTypes: generatedSeamTypes,
			callerModule: seams.currentModule,
			seams: seams,
			aliasDeclarationReferences: aliasDeclarationReferences,
			checkingModule: emittingModuleToCheck,
			builtInlineSeamComment: { self.builtInlineSeamComment(for: $0) },
		)
		// A root that calls a seam whose builder it cannot fill is reported before any tree is generated.
		try Self.validateRootsFillEveryHole(
			roots: rootInstantiables.sorted().compactMap { seamScopeMap[$0] },
			callerModuleName: seams.currentModule.moduleName,
			instantiables: typeDescriptionToFulfillingInstantiableMap,
			viewInstantiablesByModuleName: viewInstantiablesByModuleName,
			isReadableFile: emittingModule?.isReadableFile,
		)
		// A seam whose signature equals its own initializer's generates no code: its file holds the header alone.
		var generatedSeams = [(seam: Instantiable, seamRoot: ScopeGenerator.SeamRoot, rootScope: Scope)]()
		for seamType in generatedSeamTypes.sorted() {
			guard let seam = typeDescriptionToFulfillingInstantiableMap[seamType],
			      let seamRoot = seamRoots[seamType] ?? nil
			else { continue }
			generatedSeams.append((seam, seamRoot, Self.seamRootScope(of: seam, in: seamScopeMap, aliasDeclarationReferences: aliasDeclarationReferences)))
		}
		// Creating a generator starts generating its code, so every construction must be known to compile first: a
		// root's tree constructs a seam with the tier of its generated initializer the root's module can reach, and a
		// seam's tree compiles in this module, which declares the seam.
		let rootScopesToGenerate = try rootScopesThisModuleGenerates(
			from: rootInstantiables.sorted().compactMap { typeDescription in
				seamScopeMap[typeDescription].map { (typeDescription: typeDescription, scope: $0) }
			},
			checkingSeamTrees: generatedSeams.map { (instantiable: $0.seam, scope: $0.rootScope) },
		)
		var rootScopeGenerators = try rootScopesToGenerate.map { typeDescription, scope in
			try RootScopeInfo(
				typeDescription: typeDescription,
				instantiable: scope.instantiable,
				sourceFilePath: typeDescriptionToFulfillingInstantiableMap[typeDescription]?.sourceFilePath,
				scopeGenerator: scope.createScopeGenerator(
					for: nil,
					lazilyInstantiatedInstanceProperties: [],
					erasedToConcreteExistential: false,
					declaredTypeNames: declaredTypeNames,
				),
			)
		}
		for (seam, seamRoot, seamRootScope) in generatedSeams {
			var seamRoot = seamRoot
			seamRoot.unreadTypeComment = unreadTypeComment
			seamRoot.generatesPlainInitializers = seams.generatesPlainDependencyTreeInitializers
			rootScopeGenerators.append(try RootScopeInfo(
				typeDescription: seam.concreteInstantiable,
				instantiable: seam,
				sourceFilePath: seam.sourceFilePath,
				scopeGenerator: Self.seamRootGenerator(
					rootScope: seamRootScope,
					seamRoot: seamRoot,
					startsCodeGeneration: true,
					declaredTypeNames: declaredTypeNames,
				),
			))
		}
		return rootScopeGenerators
	}

	/// The declaration a receiver is: one type's receive of one property, declared at one location.
	private struct ReceiverDeclaration: Hashable {
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		let property: Property
	}

	/// A receive in a seam's tree, as `seamRoot(of:rootScope:generator:)` sees it: the property the tree receives
	/// from outside the seam – the received property, or an alias's fulfilling property – and the type that declares
	/// the receive, whose initializer bounds how widely the property's type is visible.
	private struct SeamReceiver {
		let property: Property
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		/// The access a parameter that passes the receive takes, for a receive inside a nested seam the access that
		/// seam's signature gives it; `seamRoot` proves each parameter again over its own computation's declarations.
		var access: AccessLevel
		/// The module of the type that declares the receive, whose declarations prove a type with no entry of its own.
		let moduleName: String?
		/// Whether the receive is a parameter of an extension's `instantiate(…)` method, which has no only-if-available
		/// form.
		let isInstantiateMethodParameter: Bool
		/// Whether the receive reaches this seam only through a nested seam's call that omits it, so no tier of this seam
		/// can pass it on (`SeamSignature.noTierParameters`).
		var isNoTier = false
		/// For a no-tier receive, the level of the nested seam's tier that omits it: the level that seam would have to
		/// take it at.
		var noTierCallTier: AccessLevel?
		/// For a no-tier receive, the nested seam call that omits it.
		var nestedSeamCall: SeamSignature.NestedSeamCall?
		/// The alias's own property when the receive is an alias's fulfilling property, else `nil`. See
		/// `SeamSignature.Receiver.aliasProperty`.
		let aliasProperty: Property?
		/// Whether the receive reaches this seam through a nested seam call that the module building the tree reaches
		/// no tier of and that the check of every construction is certain to report: it then reports the nested seam's
		/// type, whose widening makes a tier of that seam reachable, with its fix-it, so a tier of this seam that omits
		/// the parameter reports no omission for it (`SeamCall.unreachableTierIsReported`). A declaration reached on
		/// several paths is from such a call only when every path reaches it through one.
		var isFromReportedSeamCall: Bool

		init(property: Property, instantiable: Instantiable, declarationLocation: Dependency.DeclarationLocation?, access: AccessLevel, aliasProperty: Property? = nil, isFromReportedSeamCall: Bool = false) {
			self.property = property
			declaringType = instantiable.concreteInstantiable
			self.declarationLocation = declarationLocation
			self.access = access
			moduleName = instantiable.moduleName
			isInstantiateMethodParameter = aliasProperty == nil && instantiable.declarationType.isExtension
			self.aliasProperty = aliasProperty
			self.isFromReportedSeamCall = isFromReportedSeamCall
		}

		/// A receive inside a nested seam, which that seam's signature carries on the parameter passing it.
		init(_ receiver: SeamSignature.Receiver, moduleName: String?, isFromReportedSeamCall: Bool = false) {
			property = receiver.property
			declaringType = receiver.declaringType
			declarationLocation = receiver.declarationLocation
			access = receiver.access
			self.moduleName = moduleName
			isInstantiateMethodParameter = receiver.isInstantiateMethodParameter
			aliasProperty = receiver.aliasProperty
			self.isFromReportedSeamCall = isFromReportedSeamCall
		}

		var asErrorReceiver: DependencyTreeGeneratorError.SeamError.Receiver {
			.init(property: property, declaringType: declaringType, declarationLocation: declarationLocation, aliasProperty: aliasProperty, isInstantiateMethodParameter: isInstantiateMethodParameter)
		}

		/// The receive with `access`, the access the proof gives the parameter that passes it.
		func with(access: AccessLevel) -> SeamReceiver {
			var receiver = self
			receiver.access = access
			return receiver
		}

		var asSignatureReceiver: SeamSignature.Receiver {
			.init(property: property, declaringType: declaringType, declarationLocation: declarationLocation, access: access, aliasProperty: aliasProperty, isInstantiateMethodParameter: isInstantiateMethodParameter)
		}
	}

	/// The passes a strongly connected component of `seamCount` seams may take to settle before
	/// `signaturesDidNotSettle` is reported. Each pass adds at least one parameter or receiver to the component's
	/// signatures, or strengthens a parameter's form, or ends the computation (see `seamSignatures`), so a
	/// component settles in as many passes as it has things to add: a cycle of nine seams, each with a dependency of
	/// its own, takes nine. Eight per seam and eight more is a guard against a shape that argument misses, which is
	/// then reported rather than computed with a stale signature; the argument says no input reaches it, so a test
	/// reaches it by lowering the limit (`seamSignatureComputationLimitOverride`).
	private static func seamSignatureComputationLimit(forComponentOf seamCount: Int) -> Int {
		seamSignatureComputationLimitOverride ?? 8 * (seamCount + 1)
	}

	/// The passes every component may take to settle, in the task that sets it, in place of the bound
	/// `seamSignatureComputationLimit(forComponentOf:)` computes; `nil`, as outside a test, keeps that bound.
	@TaskLocal static var seamSignatureComputationLimitOverride: Int?

	/// The signatures of `seamTypes`, the seams one module declares, computed over `instantiables`, the declarations
	/// that module sees, with the seams of other modules among them built from `fixedSignatures`. The module's seams
	/// can reach one another, and a seam's parameters change what its tree receives, so each is computed from trees
	/// built with the signatures found so far, until none changes. A seam whose
	/// signature equals its own initializer's – no `@Instantiated` or aliased dependency, no pass-through – is `nil`:
	/// it is built with that initializer, and its file holds no code.
	/// - Parameter callerModule: The module whose seams are computed, which decides the tier each tree calls of a seam
	///   another module declares.
	private static func seamSignatures(
		forSeams seamTypes: Set<TypeDescription>,
		in instantiables: [TypeDescription: Instantiable],
		plainTypeDeclarations: [PlainTypeDeclaration],
		aliasDeclarationReferences: AliasDeclarationReferences,
		fixedSignatures: [TypeDescription: ScopeGenerator.SeamRoot],
		callerModule: ModuleIdentity,
		seams: SeamResolution,
		checkingModule: EmittingModule?,
		isOwnFile: (@Sendable (String) -> Bool)?,
		modulesReadByRunOfModule: (@Sendable (_ moduleName: String) -> TypeAccessProof.ModuleReach.ModulesRead)?,
	) throws -> SeamSignatureComputation {
		let seamInstantiables = seamTypes.sorted().compactMap { instantiables[$0] }.filter(\.generatesDependencyTree)
		// One proof of every type's access per declaration map, which every seam of the computation reads.
		let proof = TypeAccessProof(
			instantiables: instantiables,
			plainTypeDeclarations: plainTypeDeclarations,
			isOwnFile: isOwnFile,
			reach: moduleReach(viewedFrom: callerModule, instantiables: instantiables, plainTypeDeclarations: plainTypeDeclarations, modulesReadByRunOfModule: modulesReadByRunOfModule),
		)
		guard !seamInstantiables.isEmpty else { return SeamSignatureComputation(seamRoots: [:], errors: [], failedSeams: [], proof: proof) }
		let ownSeamTypes = Set(seamInstantiables.map(\.concreteInstantiable))
		let declaredTypeNames = namesOfTypesDeclaredAtFileScope(instantiables: Array(instantiables.values), plainTypeDeclarations: plainTypeDeclarations)
		func initialSeamRoot(of seam: Instantiable) -> ScopeGenerator.SeamRoot {
			let parameters = Self.ownParameters(of: seam, proof: proof)
			return ScopeGenerator.SeamRoot(
				signature: SeamSignature(seamType: seam.concreteInstantiable, parameters: parameters, tiers: Self.tiers(of: seam, parameters: parameters)),
			)
		}
		// Until a seam's signature is computed, a tree that reaches it calls an initializer taking the seam's own
		// `@Received` and `@Forwarded` properties alone. Each seam type is the concrete type of a production declaration
		// (`seamResolution` rejects a `mockOnly` seam), which `resolveSafeDIFulfilledTypes` keeps under its own concrete
		// type in every map this is given – two production declarations fulfilling one type throw there, and a
		// `mockOnly` declaration merges into the slot or loses it – so no key repeats.
		var seamRoots: [TypeDescription: ScopeGenerator.SeamRoot?] = Dictionary(seamInstantiables.map { ($0.concreteInstantiable, initialSeamRoot(of: $0)) }, uniquingKeysWith: { first, _ in first })
		var errors = [DependencyTreeGeneratorError]()
		var failedSeams = Set<TypeDescription>()
		// A seam's parameters depend on the signatures of the seams its tree reaches, so the seams are settled inner
		// first: each strongly connected component of the seam-reaches-seam graph, in reverse topological order, sees
		// the final signatures of the seams it reaches outside it, and only seams that reach one another are
		// computed again until none changes.
		for component in Self.stronglyConnectedComponents(of: seamInstantiables, in: instantiables, among: ownSeamTypes) {
			let componentSeams = seamInstantiables.filter { component.contains($0.concreteInstantiable) }
			let reachableTypeDescriptions = Self.typesReachable(fromRoots: component, in: instantiables)
			// A component settles in a fixed point in which every input to `seamRoot` only grows: a tree built with more
			// parameters in scope receives no less from outside it, each label's form only strengthens (`X?` received
			// only if available, then a required `X?`, `X`, a wrapper), a parameter that stops being received only if
			// available never is again, and the receivers of each parameter only accumulate. Nothing else a pass finds
			// feeds the next: an alias bound from a parameter that may be `nil` is bound from that parameter alone, as an
			// optional value passed to its declaring type, and every other read of it is rejected before emission, so it
			// adds no parameter. The computation ends when a pass changes no signature's content – never the receivers'
			// order, which a tree carrying the receivers of a seam that carries its own meets differently on every pass –
			// or at the limit, which no input reaches by the argument above and which reports the component if one does. The
			// argument needs each pass to read the component's other seams as one pass left them: an enum a seam's builders
			// reach is read from the seam that declares it (`ownScopeEnums`), since copies of different ages, each carried
			// by a different neighbor, would differ on every pass around a cycle of four seams.
			var errorsOfLastPass = [DependencyTreeGeneratorError]()
			var failedSeamsOfLastPass = Set<TypeDescription>()
			var settled = false
			for _ in 0..<Self.seamSignatureComputationLimit(forComponentOf: component.count) {
				var knownSeamRoots = fixedSignatures.mapValues { Optional($0) }
				for (seamType, seamRoot) in seamRoots {
					knownSeamRoots[seamType] = seamRoot
				}
				// Every enum a seam's builders reach is read from the signature of the seam that declares it, as this pass's
				// trees were built from: a copy another seam carries can be from an earlier pass, and copies of different
				// ages taken from different neighbors would keep a cycle of seams from settling.
				var ownScopeEnums = [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]()
				for case let seamRoot? in knownSeamRoots.values {
					for scopeEnum in seamRoot.signature.scopeEnums where scopeEnum.key.seamType == seamRoot.signature.seamType {
						ownScopeEnums[scopeEnum.key] = scopeEnum
					}
				}
				let scopeMap = Self.createSeamScopeMapping(
					in: instantiables,
					reachableTypeDescriptions: reachableTypeDescriptions,
					seamRoots: knownSeamRoots,
					ownSeamTypes: ownSeamTypes,
					callerModule: callerModule,
					seams: seams,
					aliasDeclarationReferences: aliasDeclarationReferences,
					checkingModule: checkingModule,
				)
				var changed = false
				var passErrors = [DependencyTreeGeneratorError]()
				var passFailedSeams = Set<TypeDescription>()
				for seam in componentSeams {
					let rootScope = Self.seamRootScope(of: seam, in: scopeMap, aliasDeclarationReferences: aliasDeclarationReferences)
					// A seam found to equal its own initializer is computed again from that initializer's parameters:
					// a change to the trees of the module's other seams can make it a seam after all.
					let previousSeamRoot = seamRoots[seam.concreteInstantiable] ?? nil
					do {
						let generator = try Self.seamRootGenerator(
							rootScope: rootScope,
							seamRoot: previousSeamRoot ?? initialSeamRoot(of: seam),
							startsCodeGeneration: false,
							declaredTypeNames: declaredTypeNames,
						)
						let seamRoot = try Self.seamRoot(
							of: seam,
							generator: generator,
							proof: proof,
							instantiables: instantiables,
							ownScopeEnums: ownScopeEnums,
							generatesPlainInitializers: seams.generatesPlainDependencyTreeInitializers,
						)
						if seamRoot?.signature.settledContent != previousSeamRoot?.signature.settledContent {
							changed = true
						}
						seamRoots[seam.concreteInstantiable] = seamRoot
					} catch let error as DependencyTreeGeneratorError {
						// A seam with an error keeps the signature it had, so the others' errors are found too.
						passErrors.append(error)
						passFailedSeams.insert(seam.concreteInstantiable)
					} catch let error as any SourceLocatedError {
						// Building the tree threw: an erased instantiator whose generic argument mismatches its type.
						passErrors.append(.sourceLocated(error))
						passFailedSeams.insert(seam.concreteInstantiable)
					}
				}
				if !changed {
					errorsOfLastPass = passErrors
					failedSeamsOfLastPass = passFailedSeams
					settled = true
					break
				}
			}
			if !settled {
				// A component holds at least one seam, so the first by location exists.
				if let firstSeam = componentSeams.min(by: { left, right in
					guard let left = left.declarationLocation, let right = right.declarationLocation else { return left.declarationLocation != nil }
					return (left.filePath, left.line, left.column) < (right.filePath, right.line, right.column)
				}) {
					errorsOfLastPass = [.seam(.init(seam: firstSeam, kind: .signaturesDidNotSettle(seams: component.sorted())))]
				}
				failedSeamsOfLastPass = component
			}
			errors += errorsOfLastPass
			failedSeams.formUnion(failedSeamsOfLastPass)
		}
		// Every enum of a cycle is generated by one module, whose seams are the ones settled here.
		let seamTypesInOrder = seamRoots.keys.sorted()
		let markedSeamRoots = Self.markingIndirectCases(in: seamTypesInOrder.map { seamRoots[$0] ?? nil })
		for (seamType, seamRoot) in zip(seamTypesInOrder, markedSeamRoots) {
			seamRoots[seamType] = seamRoot
		}
		return SeamSignatureComputation(seamRoots: seamRoots, errors: errors, failedSeams: failedSeams, proof: proof)
	}

	/// What `seamSignatures` computed: each seam's signature, the errors of the last pass of each component, and the
	/// seams those errors belong to, which keep the signature they had.
	private struct SeamSignatureComputation {
		let seamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]
		let errors: [DependencyTreeGeneratorError]
		let failedSeams: Set<TypeDescription>
		/// The proof of every type's access the computation read, which says what a parameter's access depends on.
		let proof: TypeAccessProof
	}

	/// The strongly connected components of the graph in which a seam reaches another when its tree, built from
	/// `instantiables` without entering any seam of `seamTypes`, instantiates it, in reverse topological order: a
	/// component after every component it reaches. Tarjan's algorithm on an explicit stack.
	private static func stronglyConnectedComponents(of seams: [Instantiable], in instantiables: [TypeDescription: Instantiable], among seamTypes: Set<TypeDescription>) -> [Set<TypeDescription>] {
		var reachedSeamsBySeam = [TypeDescription: [TypeDescription]]()
		for seam in seams {
			var reachedSeams = Set<TypeDescription>()
			var visited: Set<TypeDescription> = [seam.concreteInstantiable]
			var typesToVisit = [seam.concreteInstantiable]
			while let type = typesToVisit.popLast() {
				guard let instantiable = instantiables[type] else { continue }
				for dependency in instantiable.dependencies where dependency.isInstantiated {
					let instantiatedType = dependency.asInstantiatedType
					guard let instantiated = instantiables[instantiatedType] else { continue }
					if seamTypes.contains(instantiated.concreteInstantiable) {
						reachedSeams.insert(instantiated.concreteInstantiable)
					} else if visited.insert(instantiated.concreteInstantiable).inserted {
						typesToVisit.append(instantiated.concreteInstantiable)
					}
				}
			}
			reachedSeamsBySeam[seam.concreteInstantiable] = reachedSeams.sorted()
		}
		return stronglyConnectedComponents(of: seams.map(\.concreteInstantiable), edges: { reachedSeamsBySeam[$0, default: []] })
	}

	/// The strongly connected components of a graph, in reverse topological order: a component after every component it
	/// reaches. Tarjan's algorithm on an explicit stack, so that no walk recurses per node.
	static func stronglyConnectedComponents<Node: Hashable>(of nodes: [Node], edges: (Node) -> [Node]) -> [Set<Node>] {
		var index = 0
		var indices = [Node: Int]()
		var lowLinks = [Node: Int]()
		var onStack = Set<Node>()
		var stack = [Node]()
		var components = [Set<Node>]()
		for node in nodes where indices[node] == nil {
			// Each frame is a seam and the index of the next reached seam to visit.
			var frames: [(node: Node, nextReached: Int)] = [(node, 0)]
			indices[node] = index
			lowLinks[node] = index
			index += 1
			stack.append(node)
			onStack.insert(node)
			while let frame = frames.last {
				let reached = edges(frame.node)
				if frame.nextReached < reached.count {
					let reachedNode = reached[frame.nextReached]
					frames[frames.count - 1].nextReached += 1
					if indices[reachedNode] == nil {
						indices[reachedNode] = index
						lowLinks[reachedNode] = index
						index += 1
						stack.append(reachedNode)
						onStack.insert(reachedNode)
						frames.append((reachedNode, 0))
					} else if onStack.contains(reachedNode) {
						lowLinks[frame.node] = min(lowLinks[frame.node, default: 0], indices[reachedNode, default: 0])
					}
				} else {
					frames.removeLast()
					if let parent = frames.last {
						lowLinks[parent.node] = min(lowLinks[parent.node, default: 0], lowLinks[frame.node, default: 0])
					}
					if lowLinks[frame.node] == indices[frame.node] {
						var component = Set<Node>()
						while let member = stack.popLast() {
							onStack.remove(member)
							component.insert(member)
							if member == frame.node {
								break
							}
						}
						components.append(component)
					}
				}
			}
		}
		return components
	}

	/// Whether a seam declared as `instantiable` builds a tree: it instantiates or renames a dependency. A seam that
	/// builds none passes nothing through either, so SafeDI generates no initializer for it, and its callers call its
	/// own, which both the seam's signature and the seam remedy of an error about that initializer read.
	private static func buildsTree(_ instantiable: Instantiable) -> Bool {
		instantiable.dependencies.contains { dependency in
			switch dependency.source {
			case .instantiated, .aliased:
				true
			case .received, .forwarded:
				false
			}
		}
	}

	/// The parameters that pass a seam's own `@Received` and `@Forwarded` properties, in declaration order, each as
	/// visible as `proof` shows its type to be – the seam's own initializer, which takes it, among the members that
	/// prove it – and capped at the seam's type. One received only if available is a parameter received only if
	/// available, like a property the tree receives only if available; a required `@Received` and a `@Forwarded`
	/// property are not. Read from `dependencies` rather than through `forwardedReceivableProperties` or
	/// `propertiesToDeclare(in:)`: those are unordered sets that hold the by-value form of each wrapper beside it, while
	/// a parameter is one property in declaration order.
	private static func ownParameters(of seam: Instantiable, proof: TypeAccessProof) -> [SeamSignature.Parameter] {
		let typeLevel = parameterAccess(seam.effectiveTypeAccess)
		return seam.dependencies.compactMap { dependency in
			switch dependency.source {
			case let .received(onlyIfAvailable):
				ownParameter(dependency.property, of: seam, typeLevel: typeLevel, isOnlyIfAvailable: onlyIfAvailable, proof: proof)
			case .forwarded:
				ownParameter(dependency.property, of: seam, typeLevel: typeLevel, isOnlyIfAvailable: false, proof: proof)
			case .instantiated, .aliased:
				nil
			}
		}
	}

	private static func ownParameter(_ property: Property, of seam: Instantiable, typeLevel: AccessLevel, isOnlyIfAvailable: Bool, proof: TypeAccessProof) -> SeamSignature.Parameter {
		let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: [seam.moduleName])
		// Widening the seam's own initializer, which a remedy may offer, needs each of its other arguments' types to be as
		// visible.
		let otherInitializerArgumentsAccess = (seam.initializer?.arguments ?? [])
			.filter { $0.innerLabel != property.label }
			.map { proof.access(ofParameterTyped: $0.typeDescription, mentionedFrom: .declaration(seam), admittedModules: [seam.moduleName]).level }
			.min() ?? .public
		return SeamSignature.Parameter(property: property, isPassThrough: false, access: access.level, tierAccess: min(access.level, typeLevel), isOnlyIfAvailable: isOnlyIfAvailable, accessCause: access.cause, otherInitializerArgumentsAccess: otherInitializerArgumentsAccess)
	}

	/// The tiers of a seam's generated initializer, widest first: one at the seam type's effective access, as its
	/// enclosing types limit it, and one at each narrower tier access among `parameters`. Each narrower tier takes a
	/// parameter the next wider one omits, so no two take the same parameters; the seam's own initializer's level is
	/// no tier, since the narrowest tier calls it whatever its level.
	private static func tiers(of seam: Instantiable, parameters: [SeamSignature.Parameter]) -> [AccessLevel] {
		let typeLevel = parameterAccess(seam.effectiveTypeAccess)
		return [typeLevel] + Set(parameters.map(\.tierAccess)).filter { $0 < typeLevel }.sorted(by: >)
	}

	/// The access a seam parameter takes from `initializerAccess`, the effective access of the initializer that
	/// declares its receive: `open` counts as `public`, since a generated initializer is never `open`; a declaration
	/// SafeDI could not read an initializer of, which the macro has already rejected, counts as `internal`; and so
	/// does a `fileprivate` or `private` initializer, or a seam's type at one of those levels, since generated code
	/// in another file cannot construct such a declaration, which the check of every construction reports at it, so
	/// no tier at those levels is ever generated.
	static func parameterAccess(_ initializerAccess: AccessLevel?) -> AccessLevel {
		switch initializerAccess {
		case .open, .public:
			.public
		case .package:
			.package
		case .internal, .fileprivate, .private, nil:
			.internal
		}
	}

	/// The types the trees rooted at `roots` reach among `instantiables`, each seam's included: a seam's signature is
	/// computed from the trees beneath the seams it reaches too.
	private static func typesReachable(fromRoots roots: Set<TypeDescription>, in instantiables: [TypeDescription: Instantiable]) -> Set<TypeDescription> {
		var reachableTypeDescriptions = Set<TypeDescription>()
		var typeDescriptionsToVisit = Array(roots)
		while let reachableTypeDescription = typeDescriptionsToVisit.popLast() {
			guard reachableTypeDescriptions.insert(reachableTypeDescription).inserted,
			      let instantiable = instantiables[reachableTypeDescription]
			else { continue }
			for dependency in instantiable.dependencies where dependency.isInstantiated {
				typeDescriptionsToVisit.append(dependency.asInstantiatedType)
			}
		}
		return reachableTypeDescriptions
	}

	/// The scopes of the world in which every reach of a seam with a signature calls its generated initializer: each
	/// such seam's scope declares the parameters of the tier the caller's trees call as its dependencies and builds
	/// nothing, and every other scope builds its type as `createTypeDescriptionToScopeMapping` has it. Nothing is
	/// validated here: the validated scopes, which inline every seam, were checked first.
	/// - Parameters:
	///   - seamRoots: The signature of each seam, or `nil` for one built with its own initializer.
	///   - ownSeamTypes: The seams of the caller's module, whose narrowest tier its trees call; the tier called of any
	///     other seam is the narrowest its module can reach.
	///   - checkingModule: The caller, as its check of every construction knows it (`emittingModuleToCheck`), or
	///     `nil` where the caller runs no check: a caller SafeDI was not told the identity of, one every declaration
	///     of which is `public`, or another module, whose own run checks its constructions.
	///   - builtInlineSeamComment: The comment the generated code ends each construction of a scope's type with
	///     (`DependencyTreeGenerator.builtInlineSeamComment(for:)`). None where the map only computes signatures, which
	///     emits nothing.
	private static func createSeamScopeMapping(
		in instantiables: [TypeDescription: Instantiable],
		reachableTypeDescriptions: Set<TypeDescription>,
		seamRoots: [TypeDescription: ScopeGenerator.SeamRoot?],
		ownSeamTypes: Set<TypeDescription>,
		callerModule: ModuleIdentity,
		seams: SeamResolution,
		aliasDeclarationReferences: AliasDeclarationReferences,
		checkingModule: EmittingModule?,
		builtInlineSeamComment: (Instantiable) -> String? = { _ in nil },
	) -> [TypeDescription: Scope] {
		var typeDescriptionToScopeMap = [TypeDescription: Scope]()
		var scopes = [Scope]()
		// Visited in type order: a type the map holds under several keys gets one scope whichever key is met first.
		for typeDescription in reachableTypeDescriptions.sorted() {
			guard let instantiable = instantiables[typeDescription], typeDescriptionToScopeMap[instantiable.concreteInstantiable] == nil else { continue }
			let scope: Scope
			if instantiable.generatesDependencyTree, let seamRoot = seamRoots[instantiable.concreteInstantiable] ?? nil {
				let signature = seamRoot.signature
				let isOwnSeam = ownSeamTypes.contains(instantiable.concreteInstantiable)
				let requirement = AccessLevel.required(
					toConstructFrom: callerModule,
					declaredIn: (isOwnSeam ? callerModule : seams.foreignSeams[instantiable.concreteInstantiable]?.declaringModule) ?? ModuleIdentity(moduleName: nil, packageName: nil),
					isOwnFile: isOwnSeam,
				)
				// The narrowest tier the generated code can reach. The widest tier is at the seam type's access, so code that
				// can construct the type reaches a tier; code that cannot calls the widest, and the check of every
				// construction reports the type's declaration with its fix-it, never a generated initializer
				// (`Construction.isSeamLeaf`).
				let reachedTier = signature.tiers.last(where: { $0.satisfies(requirement) })
				let tier = reachedTier ?? signature.tiers[0]
				let leafInstantiable = Self.seamLeafInstantiable(
					of: instantiable,
					signature: signature,
					tier: tier,
					initializerAccess: AccessDeclaration(level: tier),
				)
				// Whether the check of every construction is certain to report the call it cannot reach a tier of: it reports
				// the seam's type or a type enclosing it, which every tier's access is capped at. The check asks the type's
				// own requirement, which is the call's: both are asked of the caller's module and the module that declares
				// the seam. The widest tier is at the type's effective access, the narrowest of its own level and its
				// enclosing types', each of which the check reads (`seamLeafAccessNeeds(of:)`), so a caller that reaches no
				// tier fails the check of one of them. No construction can be checked where the caller runs no check.
				// A module whose name SafeDI does not know assumes `package` access reaches another module's declarations
				// (`AccessRequirement.packageUnverified`) and builds another module's tree inline rather than calling a tier
				// or a public mock; from outside that package the generated code does not compile (row 4b's B4.10b,
				// M8.35b): a stated limit, never pinned.
				let unreachableTierIsReported = reachedTier == nil && checkingModule != nil
				scope = Scope(
					instantiable: leafInstantiable,
					builtInlineSeamComment: builtInlineSeamComment(leafInstantiable),
					seamCall: SeamCall(
						parameters: signature.parameters(ofTierAt: tier),
						holes: signature.holes.map { $0.atTier(tier) },
						builders: signature.builders.map { $0.atTier(tier) },
						scopeEnums: signature.scopeEnums,
						guardTypeName: signature.guardTypeName,
						comment: seams.foreignSeams[instantiable.concreteInstantiable]?.callComment ?? .noComment,
						unreachableTierIsReported: unreachableTierIsReported,
						omittedParameters: signature.parameters.filter { $0.tierAccess < tier },
						noTierParameters: signature.noTierParameters,
						typesDeclaredEscaping: signature.typesDeclaredEscaping,
						tier: tier,
						requirement: requirement,
						seamModuleName: instantiable.moduleName,
						callerModuleName: callerModule.moduleName,
						seamPackageName: instantiable.packageName,
						callerPackageName: callerModule.packageName,
					),
				)
			} else {
				scope = Scope(instantiable: instantiable, builtInlineSeamComment: builtInlineSeamComment(instantiable))
			}
			scopes.append(scope)
			for instantiableType in instantiable.instantiableTypes {
				typeDescriptionToScopeMap[instantiableType] = scope
			}
		}
		// Each scope once: the map holds a scope under every type it fulfills.
		for scope in scopes {
			if let seamCall = scope.seamCall {
				// A call fills each builder with the type that fulfills the hole in these declarations, or, when none does,
				// passes up the builder of the seam whose tree makes the call (a root's tree cannot: an error).
				scope.holeArguments = seamCall.holes.map { hole in
					if let fulfillingInstantiable = Self.fulfillingInstantiable(of: hole, in: instantiables),
					   let fulfillingScope = typeDescriptionToScopeMap[fulfillingInstantiable.concreteInstantiable]
					{
						.fill(hole, fulfillingScope)
					} else {
						.passUp(hole)
					}
				}
			} else {
				Self.populatePropertiesToGenerate(of: scope, from: typeDescriptionToScopeMap, instantiables: instantiables, aliasDeclarationReferences: aliasDeclarationReferences)
			}
		}
		return typeDescriptionToScopeMap
	}

	/// Fills `scope.propertiesToGenerate` from `typeDescriptionToScopeMap`, as `createTypeDescriptionToScopeMapping`
	/// fills a validated scope's. A dependency whose type the map lacks is left out, as it is there.
	private static func populatePropertiesToGenerate(
		of scope: Scope,
		from typeDescriptionToScopeMap: [TypeDescription: Scope],
		instantiables: [TypeDescription: Instantiable],
		aliasDeclarationReferences: AliasDeclarationReferences,
	) {
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case let .instantiated(_, erasedToConcreteExistential):
				let instantiatedType = dependency.asInstantiatedType
				if let instantiable = instantiables[instantiatedType], !instantiable.mockOnly, let instantiatedScope = typeDescriptionToScopeMap[instantiatedType] {
					scope.propertiesToGenerate.append(.instantiated(
						dependency.property,
						instantiatedScope,
						erasedToConcreteExistential: erasedToConcreteExistential,
					))
				} else if Self.canBeHole(dependency) {
					// No production declaration these declarations hold fulfills the type, which validation accepts only
					// in a seam's tree: the seam's generated initializer takes a builder for it.
					scope.propertiesToGenerate.append(.hole(
						dependency.property,
						erasedToConcreteExistential: erasedToConcreteExistential,
						declarationLocation: dependency.declarationLocation,
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

	/// The scope at the root of `seam`'s own tree, which builds the seam's dependencies from `typeDescriptionToScopeMap`,
	/// where every reach of a seam – the seam itself included – calls a generated initializer. It is not in the map:
	/// the map holds the scope that calls the seam.
	private static func seamRootScope(
		of seam: Instantiable,
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
		aliasDeclarationReferences: AliasDeclarationReferences,
	) -> Scope {
		let rootScope = Scope(instantiable: seam)
		populatePropertiesToGenerate(
			of: rootScope,
			from: typeDescriptionToScopeMap,
			instantiables: typeDescriptionToScopeMap.mapValues(\.instantiable),
			aliasDeclarationReferences: aliasDeclarationReferences,
		)
		return rootScope
	}

	/// The generator of `seam`'s tree, rooted at `rootScope`, with the parameters of `signature` in scope throughout:
	/// each by its own form and its unwrapped form; a non-optional `LazilyInstantiated` parameter also by its
	/// instance, which a by-value receiver reads, as it reads a forwarded wrapper's (an optional wrapper offers
	/// nothing but itself); and every optional parameter, required or received only if available, as a property that
	/// may be `nil`, from which an `onlyIfAvailable` alias is bound as an optional value. No receive in the tree is
	/// beneath a declaration of its label that does not provide it: `validatePropertiesAreFulfillable` has reported each
	/// as hidden, from the seam's own chain.
	private static func seamRootGenerator(
		rootScope: Scope,
		seamRoot: ScopeGenerator.SeamRoot,
		startsCodeGeneration: Bool,
		declaredTypeNames: DeclaredTypeNames,
	) throws -> ScopeGenerator {
		var nearestDeclarations = NearestDeclarations()
		var lazilyInstantiatedInstanceProperties = Set<Property>()
		let autoclosureCallByLabel = seamRoot.autoclosureCallByLabel(of: rootScope.instantiable)
		for parameter in seamRoot.signature.parameters {
			let property = parameter.property
			// Each parameter is the nearest declaration of its label in the seam's tree. An optional one also stands for the
			// non-optional form it is made from, which the tree reads as a value that may be `nil`. A non-optional wrapper
			// parameter offers its instance, as a received wrapper does inline; an optional one offers nothing but itself.
			var providedForms = CycleParameter.forms(providedBy: property)
			providedForms.insert(property.asUnwrappedProperty)
			nearestDeclarations.replace(property, providing: providedForms)
			if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				lazilyInstantiatedInstanceProperties.insert(instanceProperty)
			}
			// A deferred parameter is held in a `LazilyInstantiated` under its label, whose instance the tree reads wherever
			// it reads the label, as it reads a received wrapper's instance – except one the seam's own alias of its label
			// reads from the autoclosure (`SeamRoot.autoclosureCallByLabel`). The memo provides only the by-value forms.
			if parameter.isDeferred, autoclosureCallByLabel[property.label] == nil {
				lazilyInstantiatedInstanceProperties.insert(property.asUnwrappedProperty)
			}
		}
		return try rootScope.createScopeGenerator(
			for: nil,
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			erasedToConcreteExistential: false,
			startsCodeGeneration: startsCodeGeneration,
			declaredTypeNames: declaredTypeNames,
		)
	}

	/// Every receive in the tree `generator` roots, `seam`'s, that leaves the seam – each `@Received` dependency and
	/// each alias's fulfilling property that no scope between the receiver and the root provides, exactly, in
	/// unwrapped form, or as a wrapper's instance, as `ScopeGenerator.provides` decides – with the type that
	/// declares it, in the order the tree declares them, each declaration once, and, for an alias's fulfilling
	/// property, the alias's own property. An alias of a property its own scope provides – instantiates or is
	/// forwarded – binds to that declaration, as `ScopeGenerator.init` decides, so it leaves the seam no more
	/// than one an ancestor provides. A receive a scope inside the tree fulfills is passed nothing, so it proves
	/// nothing about a parameter's access and is named by no error. The generator tree is walked rather than the scopes, which a tree
	/// can reach under several parents: a receive leaves the seam on one path and not on another, and each path is a
	/// branch of the generator tree, which also closes every cycle. A receive that leaves the seam on several paths
	/// is one declaration, kept where the tree first reaches it: an error names it once, the access it proves is the
	/// same on every path, and it is from a reported seam call only when every path reaches it through one. A scope
	/// that closes a property cycle is built for a property on the stack, so its
	/// type's declaration is an ancestor's, already kept. No receive is beneath a declaration of its label that does
	/// not provide it, which validation reports as hidden, so a receive the scopes above do not provide leaves the
	/// seam.
	///
	/// Beside the receivers, what decides whether a by-value pass-through is deferred, and `@Sendable`: the reads of
	/// labels whose nearest declaration is outside the tree – a parameter – where the tree reads them
	/// (`parameterReads`). A parameter no read reaches, whose label a declaration inside the tree hides from every
	/// receiver, is taken by value, so no `LazilyInstantiated` goes unread. Whether a function is `@Sendable` is read
	/// from the facts the emitters decorate from: `buildsInSendableFunction` and `ScopeGenerator.sendableStages(ofFill:)`.
	private static func receivers(in generator: ScopeGenerator, of _: Instantiable, instantiables: [TypeDescription: Instantiable]) -> (receivers: [SeamReceiver], parameterReads: ParameterReads) {
		var receivers = [SeamReceiver]()
		var keptDeclarationIndices = [ReceiverDeclaration: Int]()
		var parameterReads = ParameterReads()
		/// A generator to visit, with what the scopes enclosing it provide, whether it is built inside a `@Sendable`
		/// function, and the labels the scopes enclosing it declare or forward.
		struct Frame {
			let generator: ScopeGenerator
			let providedProperties: Set<Property>
			let insideSendable: Bool
			let declaredLabels: Set<String>
		}
		var generatorsToVisit = [Frame(generator: generator, providedProperties: [], insideSendable: false, declaredLabels: [])]
		while let frame = generatorsToVisit.popLast() {
			let visited = frame.generator
			let providedProperties = frame.providedProperties
			/// Records a read of `label` in this scope's code, inside a `@Sendable` function when `insideSendable` holds,
			/// that reaches a parameter when no scope enclosing the read declares the label.
			func recordRead(of label: String, insideSendable: Bool, declaredLabels: Set<String> = frame.declaredLabels) {
				guard !declaredLabels.contains(label) else { return }
				parameterReads.labelsRead.insert(label)
				if insideSendable {
					parameterReads.labelsReadInsideSendableFunction.insert(label)
				}
			}
			// A nested seam that takes a parameter `@Sendable` reads it inside a `@Sendable` function, wherever this tree
			// calls it.
			for parameter in visited.seamCallParameters ?? [] where parameter.deferral == .deferred(isSendable: true) {
				recordRead(of: parameter.property.label, insideSendable: true)
			}
			// A site reads every parameter whose label no scope enclosing it declares, and never inside a `@Sendable` function:
			// it reads them at the site or at the call of a staged builder's first stage, which is made before the first
			// `@Sendable` function on the site's path.
			if visited.holeSite != nil {
				parameterReads.siteDeclaredLabels.append(frame.declaredLabels)
			}
			if visited.closesPropertyCycle {
				// A scope that closes a lazy cycle passes the function it refers to each parameter's nearest declaration.
				for parameter in visited.cycleParameters {
					recordRead(of: parameter.property.label, insideSendable: frame.insideSendable)
				}
			}
			// A seam call the module reaches no tier of and the check of every construction is certain to report: it
			// reports the seam's type, whose widening makes a tier reachable, so the receives the call folds into this
			// seam report no omission here.
			let callsReportedSeam = visited.seamCall?.unreachableTierIsReported ?? false
			// A nested seam's call passes `nil` for the parameters it omits, which its leaf declares as receives only if
			// available: the receives inside that seam they stand for are no-tier receives of this seam.
			let omittedByCall = visited.seamCall.map { seamCall in
				Dictionary(grouping: seamCall.omittedParameters + seamCall.noTierParameters, by: \.property.label).compactMapValues(\.first)
			} ?? [:]
			// An alias declares no dependency of its own.
			if let instantiable = visited.builtInstantiable {
				func isProvided(_ property: Property, by providedProperties: Set<Property>) -> Bool {
					providedProperties.contains(property)
						|| (property.typeDescription.isOptional && providedProperties.contains(property.asUnwrappedProperty))
				}
				let initializerAccess = parameterAccess(instantiable.effectiveInitializerAccess)
				/// The parameter of the seam this scope calls that passes `property`, if the scope calls one.
				func seamCallParameter(passing property: Property) -> SeamSignature.Parameter? {
					visited.seamCallParameters?.first { $0.property == property }
				}
				func keep(_ receiver: SeamReceiver) {
					let declaration = ReceiverDeclaration(declaringType: receiver.declaringType, declarationLocation: receiver.declarationLocation, property: receiver.property)
					if let keptIndex = keptDeclarationIndices[declaration] {
						receivers[keptIndex].isFromReportedSeamCall = receivers[keptIndex].isFromReportedSeamCall && receiver.isFromReportedSeamCall
					} else {
						keptDeclarationIndices[declaration] = receivers.endIndex
						receivers.append(receiver)
					}
				}
				let visitedLabels = Set(visited.providedProperties.map(\.label))
				for dependency in instantiable.dependencies {
					switch dependency.source {
					case .received:
						recordRead(of: dependency.property.label, insideSendable: frame.insideSendable)
						guard !isProvided(dependency.property, by: providedProperties) else { continue }
						// A nested seam's pass-through stands for the receives inside that seam, which its signature
						// carries, so an error notes the receives inside the nested seam rather than the seam.
						if let omitted = omittedByCall[dependency.property.label] {
							let noTierReceivers = omitted.receivers.isEmpty
								? [SeamReceiver(property: dependency.property, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: omitted.access, isFromReportedSeamCall: callsReportedSeam)]
								: omitted.receivers.map { SeamReceiver($0, moduleName: instantiables[$0.declaringType]?.moduleName, isFromReportedSeamCall: callsReportedSeam) }
							let nestedSeamCall = visited.seamCall.map { seamCall in
								SeamSignature.NestedSeamCall(
									seamType: instantiable.concreteInstantiable,
									seamModuleName: seamCall.seamModuleName,
									tier: seamCall.tier,
									requirement: seamCall.requirement,
									callerModuleName: seamCall.callerModuleName,
									parameterTierAccess: seamCall.omittedParameters.contains { $0.property.label == dependency.property.label } ? omitted.tierAccess : nil,
									receivingTypes: noTierReceivers.map(\.declaringType).uniqued(),
								)
							}
							for var receiver in noTierReceivers {
								receiver.isNoTier = true
								receiver.noTierCallTier = visited.seamCall?.tier
								receiver.nestedSeamCall = nestedSeamCall
								keep(receiver)
							}
						} else if let parameter = seamCallParameter(passing: dependency.property) {
							if parameter.receivers.isEmpty {
								keep(SeamReceiver(property: dependency.property, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: parameter.access, isFromReportedSeamCall: callsReportedSeam))
							} else {
								parameter.receivers.map { SeamReceiver($0, moduleName: instantiables[$0.declaringType]?.moduleName, isFromReportedSeamCall: callsReportedSeam) }.forEach(keep)
							}
						} else {
							keep(SeamReceiver(property: dependency.property, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: initializerAccess))
						}
					case let .aliased(fulfillingProperty, _, _):
						// The alias is bound in this scope's code, where the declarations of this scope are in scope too, but an
						// alias that keeps its fulfilling property's label is not in scope where that property is read.
						if fulfillingProperty.label == dependency.property.label || !visitedLabels.contains(fulfillingProperty.label) {
							recordRead(of: fulfillingProperty.label, insideSendable: frame.insideSendable)
						}
						guard !isProvided(fulfillingProperty, by: providedProperties.union(visited.providedProperties)) else { continue }
						keep(SeamReceiver(property: fulfillingProperty, instantiable: instantiable, declarationLocation: dependency.declarationLocation, access: initializerAccess, aliasProperty: dependency.property))
					case .instantiated, .forwarded:
						continue
					}
				}
			}
			// The scope's children receive what it creates – its instantiated, aliased, and forwarded properties, with
			// the instance of each lazily instantiated one – beside what encloses it.
			let childProvidedProperties = providedProperties.union(visited.providedProperties)
			let childDeclaredLabels = frame.declaredLabels.union(visited.providedProperties.map(\.label))
			let firstChildIndex = generatorsToVisit.endIndex
			for child in visited.children {
				// A fill binds the fields of the hole's struct its tree reads, which hide every declaration of their labels
				// above it, but for those bound from a deferred parameter, which it reads from the caller's scope.
				let fillFieldLabels = child.fillStructBoundLabels
				generatorsToVisit.append(Frame(
					generator: child,
					providedProperties: childProvidedProperties,
					insideSendable: frame.insideSendable || child.buildsInSendableFunction || visited.buildsInSendableFunction(ofFill: child),
					declaredLabels: fillFieldLabels.isEmpty ? childDeclaredLabels : childDeclaredLabels.union(fillFieldLabels),
				))
			}
			generatorsToVisit[firstChildIndex...].reverse()
		}
		return (receivers, parameterReads)
	}

	/// The reads of a seam's parameters its tree makes, by label: what `receivers(in:of:instantiables:)` finds beside the
	/// receivers.
	struct ParameterReads {
		/// The labels the tree reads where no declaration inside it hides the label.
		var labelsRead = Set<String>()
		/// Of those, the labels read inside a `@Sendable` function, or handed to a nested seam that takes them `@Sendable`.
		var labelsReadInsideSendableFunction = Set<String>()
		/// For each site of a hole, the labels the scopes enclosing it declare: the site reads every parameter whose label
		/// none of them declares.
		var siteDeclaredLabels = [Set<String>]()

		/// Whether the tree reads the parameter labeled `label`.
		func reads(_ label: String) -> Bool {
			labelsRead.contains(label) || siteDeclaredLabels.contains { !$0.contains(label) }
		}

		/// Whether the tree reads the parameter labeled `label` inside a `@Sendable` function.
		func readsInsideSendableFunction(_ label: String) -> Bool {
			labelsReadInsideSendableFunction.contains(label)
		}
	}

	/// What `seam`'s root generator emits, read from `generator`, the generator of its tree: its signature, with the
	/// seam's own `@Received` and `@Forwarded` properties first, in declaration order, then the pass-throughs in label
	/// order – each form of a label the tree receives that no parameter provides, as `formsProvided(by:)` decides:
	/// a required non-optional wrapper provides every by-value form and the optional form of its kind, a by-value
	/// property its optional form, and an optional wrapper nothing but itself. Two parameters under one label are
	/// `parametersShareLabel`. `nil` when the signature would equal the seam's own initializer's.
	/// - Parameter ownScopeEnums: Each seam's own enums, by key, as the signatures the pass's trees were built from hold
	///   them: what `shapedBuilders` reads an enum the seam's builders reach from, never a copy another seam carries.
	/// - Parameter generatesPlainInitializers: Whether the seam's tiers have plain initializers, which a hand-written
	///   initializer callable with their labels would collide with: the module's `SeamResolution.generatesPlainDependencyTreeInitializers`.
	private static func seamRoot(of seam: Instantiable, generator: ScopeGenerator, proof: TypeAccessProof, instantiables: [TypeDescription: Instantiable], ownScopeEnums: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum], generatesPlainInitializers: Bool) throws -> ScopeGenerator.SeamRoot? {
		let ownParameters = ownParameters(of: seam, proof: proof)
		// The seam's own properties are parameters as declared, and provide forms as any parameter does.
		var ownLabels = Set<String>()
		var providedByOwnProperties = Set<Property>()
		for dependency in seam.dependencies {
			switch dependency.source {
			case .received, .forwarded:
				ownLabels.insert(dependency.property.label)
				providedByOwnProperties.formUnion(Self.formsProvided(by: dependency.property))
			case .instantiated, .aliased:
				continue
			}
		}
		// A property required only through an `onlyIfAvailable` alias of it (`requiredAliasFulfillingProperties`) is
		// not required of the caller: the alias binds `nil` where the caller holds nothing. The caller must still build
		// it first where it holds it, so the parameter carries `requiredThroughAlias`.
		let requiredProperties = generator.requiredReceivedProperties
		let (treeReceivers, parameterReads) = Self.receivers(in: generator, of: seam, instantiables: instantiables)
		func receivers(ofLabel label: String) -> [SeamReceiver] {
			treeReceivers.filter { $0.property.label == label }
		}
		/// The receivers a parameter passes its value to: those of `forms`, by unwrapped type, and of the instance of a
		/// wrapper among them. A receive of the label with another type, which a label collision reports, proves
		/// nothing about the parameter's type.
		func receivers(of forms: [Property]) -> [SeamReceiver] {
			treeReceivers.filter { receiver in
				forms.contains { form in
					form.label == receiver.property.label
						&& (form.asUnwrappedProperty == receiver.property.asUnwrappedProperty
							|| form.typeDescription.unwrapped.lazilyInstantiatedInstanceType == receiver.property.typeDescription.unwrapped)
				}
			}
		}
		// Every label's collision and every tier's omission is collected, so the seam reports each of its errors.
		var errors = [DependencyTreeGeneratorError]()
		func labelCollision(_ label: String, among collidingReceivers: [SeamReceiver]) -> DependencyTreeGeneratorError {
			.seam(.init(seam: seam, kind: .parameters(.parametersShareLabel(
				label: label,
				receivers: collidingReceivers.map(\.asErrorReceiver),
				remedy: Self.labelCollisionRemedy(among: collidingReceivers.map(\.property), requiredProperties: requiredProperties),
			))))
		}

		// The forms the tree receives, from the receives that leave the seam on some path. Every tree receiver is a
		// parameter candidate: a receive beneath a declaration of its label that does not provide it never reaches
		// here, since validation reports it as the inline hidden-label error from the seam's chain.
		let receivedProperties = Set(treeReceivers.map(\.property))
		// In sorted order, so that which of two spellings `==` calls equal (`any P` and `P`) a parameter takes is the
		// same in every process, in the seam's module and in each caller's. An `onlyIfAvailable` alias's fulfilling
		// property is spelled non-optional (`ofType: X.self`) and received only if available: it is the optional form,
		// which the parameter its optional receives take provides, and from which the alias is bound.
		var formsByLabel = [String: [Property]]()
		for receivedProperty in receivedProperties.sorted() {
			let property = requiredProperties.contains(receivedProperty) || receivedProperty.typeDescription.isOptional
				? receivedProperty
				: receivedProperty.asOptionalProperty
			guard !providedByOwnProperties.contains(property) else { continue }
			formsByLabel[property.label, default: []].append(property)
		}
		var passThroughs = [SeamSignature.Parameter]()
		var noTierParameters = [SeamSignature.Parameter]()
		for label in formsByLabel.keys.sorted() {
			let forms = formsByLabel[label, default: []]
			// A label the tree receives only through nested seam calls that omit it is a parameter on no tier: each call
			// passes `nil` for it, as no tier of this seam can pass it on, so a caller holding a value for it is told.
			let labelReceivers = receivers(ofLabel: label)
			if !ownLabels.contains(label), !labelReceivers.isEmpty, labelReceivers.allSatisfy(\.isNoTier), let form = forms.first {
				let property = form.typeDescription.isOptional ? form : form.asOptionalProperty
				let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName] + labelReceivers.map(\.moduleName)))
				// A parameter on no tier is taken by none, so its tier access records the level of the nested seam's tier that
				// omits it instead: what that seam would have to take it at, which a caller holding a value is told.
				// Of the nested calls that omit it, the one an error names is one at the widest tier, the first by seam type.
				let nestedSeamCall = labelReceivers.compactMap(\.nestedSeamCall).min { left, right in
					left.tier != right.tier ? left.tier > right.tier : left.seamType < right.seamType
				}
				noTierParameters.append(SeamSignature.Parameter(
					property: property,
					isPassThrough: true,
					access: access.level,
					tierAccess: labelReceivers.compactMap(\.noTierCallTier).max() ?? access.level,
					isOnlyIfAvailable: true,
					receivers: labelReceivers.map { $0.with(access: access.level).asSignatureReceiver },
					accessCause: access.cause,
					nestedSeamCall: nestedSeamCall,
				))
				continue
			}
			// A form the seam's own property of the label does not provide is a second parameter under the label.
			guard !ownLabels.contains(label) else {
				errors.append(labelCollision(label, among: receivers(ofLabel: label)))
				continue
			}
			let wrappers = forms.filter { $0.typeDescription.unwrapped.lazilyInstantiatedInstanceType != nil }
			let unwrappedWrappers = Set(wrappers.map(\.asUnwrappedProperty))
			let unwrappedValues = Set(forms.filter { $0.typeDescription.unwrapped.lazilyInstantiatedInstanceType == nil }.map(\.asUnwrappedProperty))
			let parameterProperty: Property
			let isRequired: Bool
			var deferral = SeamSignature.Parameter.Deferral.none
			if let requiredWrapper = wrappers.filter({ !$0.typeDescription.isOptional }).sorted().first {
				// A required non-optional wrapper (a wrapper received only if available is optional) provides every
				// by-value form and the optional form of its kind; any other form is a second parameter.
				guard unwrappedWrappers == [requiredWrapper],
				      unwrappedValues.allSatisfy({ $0.typeDescription == requiredWrapper.typeDescription.lazilyInstantiatedInstanceType })
				else {
					errors.append(labelCollision(label, among: receivers(ofLabel: label)))
					continue
				}
				parameterProperty = requiredWrapper
				isRequired = true
			} else if unwrappedWrappers.isEmpty {
				// One by-value property and its optional form are one parameter: the unwrapped form where a receiver
				// requires a non-optional form, and otherwise the optional type, required where some receiver requires
				// it, since the property the caller's tree declares may be optional too (a forwarded `x: X?`).
				guard unwrappedValues.count == 1, let value = unwrappedValues.first else {
					errors.append(labelCollision(label, among: receivers(ofLabel: label)))
					continue
				}
				let takesUnwrappedForm = requiredProperties.contains(value)
				parameterProperty = takesUnwrappedForm ? value : Property(label: label, typeDescription: .optional(value.typeDescription))
				isRequired = takesUnwrappedForm || forms.contains(where: requiredProperties.contains)
				// A by-value pass-through the tree reads is deferred: the tree reads it where it would read the caller's value
				// inline, when a receiver is first built. An instantiator is a value whose instantiation is deferred already,
				// which the caller hands on as inline. It is `@Sendable` where a `@Sendable` function inside the tree reads it.
				if parameterProperty.asUnwrappedProperty.propertyType.isConstant, parameterReads.reads(label) {
					deferral = .deferred(isSendable: parameterReads.readsInsideSendableFunction(label))
				}
			} else {
				// An optional wrapper provides nothing but itself: a by-value form or another kind beside it is a second
				// parameter.
				guard unwrappedValues.isEmpty, unwrappedWrappers.count == 1, let wrapper = unwrappedWrappers.first else {
					errors.append(labelCollision(label, among: receivers(ofLabel: label)))
					continue
				}
				parameterProperty = Property(label: label, typeDescription: .optional(wrapper.typeDescription))
				isRequired = requiredProperties.contains(parameterProperty)
			}
			// The parameter is as visible as the narrowest type it names, as the declarations of the seam's module and of
			// its receivers' modules prove it; each receiver records that access, at which a seam that reaches this one
			// passes it on.
			let parameterReceivers = receivers(of: forms)
			let access = proof.access(ofParameterTyped: parameterProperty.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName] + parameterReceivers.map(\.moduleName)))
			// A requirement through an `onlyIfAvailable` alias that reaches the seam's root – no scope in the tree declares
			// its label – is satisfied by this parameter, the tree's nearest declaration of the label, where the parameter
			// provides a form the alias reads; otherwise the alias is `nil`, and nothing is required.
			let requiredThroughAlias = !isRequired && generator.requiredAliasFulfillingProperties.contains { requiredProperty in
				requiredProperty.label == label && ScopeGenerator.provides(parameterProperty, aFormReadBy: requiredProperty)
			}
			passThroughs.append(SeamSignature.Parameter(
				property: parameterProperty,
				isPassThrough: true,
				access: access.level,
				isOnlyIfAvailable: !isRequired,
				requiredThroughAlias: requiredThroughAlias,
				deferral: deferral,
				receivers: parameterReceivers.map { $0.with(access: access.level).asSignatureReceiver },
				accessCause: access.cause,
			))
		}
		passThroughs.sort { $0.property.label < $1.property.label }

		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
		guard Self.buildsTree(seam) || !passThroughs.isEmpty || !noTierParameters.isEmpty else {
			return nil
		}
		// No tier is wider than the seam's type, so each parameter's access is capped there. The widest tier is at the
		// seam type's access, and each narrower tier at a narrower parameter access; the narrowest tier takes every
		// parameter and calls the seam's own initializer, which may be narrower than it: Swift checks a member's
		// signature against its access, never its body. A required parameter narrower than the seam's type is
		// omitted by the widest tier, which cannot pass `nil` for it: reported once, at the widest tier.
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		// A deferred parameter's autoclosure is named apart from every builder function the tree declares, which, being a
		// local function, is in scope throughout the initializer's body and would hide it, and from every other deferred
		// parameter's; the holes' builders are named apart from these names in turn.
		let builderFunctionNames = Self.builderFunctionNamesOfProperties(in: generator)
		var takenInternalNames = builderFunctionNames
		let parameters = (ownParameters + passThroughs).map { parameter in
			var internalName = ScopeGenerator.functionName(toBuildPropertyNamed: parameter.property.label)
			if parameter.isDeferred {
				while !takenInternalNames.insert(internalName).inserted {
					internalName = "\(internalName)_".spelledAsJoinedIdentifier
				}
			}
			return SeamSignature.Parameter(property: parameter.property, isPassThrough: parameter.isPassThrough, access: parameter.access, tierAccess: min(parameter.access, seamTypeAccess), isOnlyIfAvailable: parameter.isOnlyIfAvailable, requiredThroughAlias: parameter.requiredThroughAlias, deferral: parameter.deferral, internalName: internalName, receivers: parameter.receivers, accessCause: parameter.accessCause, otherInitializerArgumentsAccess: parameter.otherInitializerArgumentsAccess)
		}
		let shapedBuilders = Self.shapedBuilders(
			of: seam,
			generator: generator,
			holes: Self.holes(of: seam, generator: generator, parameters: parameters, proof: proof, instantiables: instantiables),
			parameters: parameters,
			treeFunctionNames: Self.builderFunctionNamesOfProperties(in: generator, includingHoleSites: false),
			proof: proof,
			instantiables: instantiables,
			ownScopeEnums: ownScopeEnums,
		)
		let holes = shapedBuilders.holes
		let tiers = Self.tiers(of: seam, parameters: parameters)
		for omitted in parameters where omitted.tierAccess < seamTypeAccess && !omitted.isOnlyIfAvailable {
			// A pass-through that reaches this seam only through a nested seam call the module reaches no tier of,
			// and that the check of every construction is certain to report, is no omission of this seam's: the check
			// reports the nested seam's type, whose widening makes a tier of that seam reachable, with its fix-it, and
			// this seam is rejected with it. A parameter some receiver of this seam's own tree needs, or one of a call
			// the check may pass, is reported here.
			let omittedReceivers = receivers(ofLabel: omitted.property.label)
			guard omittedReceivers.isEmpty || !omittedReceivers.allSatisfy(\.isFromReportedSeamCall) else { continue }
			// An omitted own `@Received` property is a required one: the loop leaves out one received only if available
			// (`ownParameters(of:)`), for which a wider tier passes `nil`.
			let ownParameter: DependencyTreeGeneratorError.SeamError.OwnParameter = switch seam.dependencies.first(where: { $0.property == omitted.property })?.source {
			case .forwarded:
				.forwarded
			case .received:
				.required
			case .instantiated, .aliased, nil:
				.none
			}
			errors.append(.seam(.init(
				seam: seam,
				kind: .parameters(.tierOmitsRequiredParameter(
					parameter: omitted.property,
					tier: seamTypeAccess,
					parameterLevel: omitted.tierAccess,
					receivers: omittedReceivers.map(\.asErrorReceiver),
					ownParameter: ownParameter,
					cause: omitted.accessCause,
				)),
			)))
		}
		// Every tier takes every builder, since a hole is required: a hole narrower than a tier is reported once per
		// declaration of its property, however many sites the tree builds it at, at the widest tier that omits it.
		var reportedHoleDeclarations = Set<OwnedHoleDeclaration>()
		for hole in holes {
			guard let tier = tiers.first(where: { $0 > hole.tierAccess }),
			      reportedHoleDeclarations.insert(OwnedHoleDeclaration(owner: hole.ownerType, property: hole.property)).inserted
			else { continue }
			errors.append(.seam(.init(seam: seam, kind: .tierOmitsBuilder(hole: hole, builder: shapedBuilders.builderBySite[hole.site], tier: tier))))
		}
		// A builder can be narrower than every place it builds where an inner seam whose enum it holds is.
		for builder in shapedBuilders.builders {
			if let innerSeam = builder.narrowingInnerSeam, let tier = tiers.first(where: { $0 > builder.tierAccess }),
			   !holes.contains(where: { hole in hole.tierAccess < tier && shapedBuilders.builderBySite[hole.site]?.label == builder.label })
			{
				errors.append(.seam(.init(seam: seam, kind: .tierOmitsBuilderHoldingInnerSeam(builder: builder, innerSeam: innerSeam, tier: tier))))
			}
		}
		// A hand-written initializer that a call with a tier's argument labels can reach – its labels hold the tier's in
		// order, and every other argument has a default value – is rejected whatever its types: because the labels match,
		// a call meant for one initializer can run the other instead, or the code can fail to compile. Beside a
		// non-optional generated parameter, a twin taking `Any`, an existential, a generic, a defaulted parameter or a
		// closure loses to the generated initializer; beside an optional parameter, the twin takes the call from a caller
		// holding the value. No comparison of types SafeDI can make tells a twin that takes a call from one that loses it.
		// A tier's readable labels are checked only where the seam's module generates the plain initializer that takes
		// them; a tier that takes no argument has one `init()` whatever the module sets. The check rejects a seam and
		// changes no signature, so another module's computation of the seam's signature, which does not know the setting
		// and skips the check, reaches the signature the seam's own module generates. It reads only the initializers of
		// the declaration SafeDI reads: a hand-written twin in an extension SafeDI does not read is a redeclaration the
		// compiler reports.
		for tier in tiers {
			let tierParameters = parameters.filter { $0.tierAccess >= tier }
			let builderLabels = shapedBuilders.builders.map { $0.label(inTierAt: tier) }
			let tierLabels = tierParameters.map(\.property.label) + builderLabels
			if generatesPlainInitializers || tierLabels.isEmpty,
			   let handWrittenInitializer = seam.otherInitializers.first(where: { Self.initializer($0, isCallableWithLabels: tierLabels) })
			{
				errors.append(.seam(.init(
					seam: seam,
					kind: .parameters(.initializerCollides(parameters: tierParameters, builderLabels: builderLabels, handWrittenInitializer: handWrittenInitializer)),
				)))
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
		return ScopeGenerator.SeamRoot(signature: SeamSignature(
			seamType: seam.concreteInstantiable,
			parameters: parameters,
			tiers: tiers,
			noTierParameters: noTierParameters,
			holes: holes,
			builders: shapedBuilders.builders,
			scopeEnums: shapedBuilders.scopeEnums,
			typesDeclaredEscaping: generator.typesDeclaredEscaping.intersection(parameters.map(\.property.typeDescription)),
		))
	}

	/// Whether a call of `initializer` can pass exactly `labels`, in order: they match its arguments' labels in order,
	/// and every argument they leave out has a default value.
	private static func initializer(_ initializer: Initializer, isCallableWithLabels labels: [String]) -> Bool {
		// `matches[labelCount]` is whether the arguments read so far can take the first `labelCount` labels.
		var matches = [true] + Array(repeating: false, count: labels.count)
		for argument in initializer.arguments {
			var nextMatches = Array(repeating: false, count: labels.count + 1)
			for labelCount in matches.indices where matches[labelCount] {
				if argument.hasDefaultValue {
					nextMatches[labelCount] = true
				}
				if labelCount < labels.count, labels[labelCount] == argument.label {
					nextMatches[labelCount + 1] = true
				}
			}
			matches = nextMatches
		}
		return matches[labels.count]
	}

	/// The declaration of a hole's property, by which a hole's errors are reported once however many sites it has.
	private struct OwnedHoleDeclaration: Hashable {
		let owner: TypeDescription
		let property: Property
	}

	/// What a collision of `forms`, the properties the receivers of one label declare, says to do. Forms of one
	/// by-value type – a wrapper's instance type, else the unwrapped type, so `Instantiator<User>` is another type
	/// than `User`, which no form of `User` provides – of one wrapper kind, and without a required optional by-value
	/// receive beside a wrapper, which the inlined validation accepts under no providing form (the wrapper's
	/// instance is non-optional), are received the same way or declared on the seam as the form that provides the
	/// others, spelled as the first receiver of that form spells it.
	private static func labelCollisionRemedy(among forms: [Property], requiredProperties: Set<Property>) -> DependencyTreeGeneratorError.SeamError.LabelCollisionRemedy {
		func isWrapper(_ form: Property) -> Bool {
			form.typeDescription.unwrapped.lazilyInstantiatedInstanceType != nil
		}
		let valueTypes = Set(forms.map { $0.typeDescription.unwrapped.lazilyInstantiatedInstanceType ?? $0.typeDescription.unwrapped })
		guard valueTypes.count == 1 else { return .rename }
		let wrapperKinds = Set(forms.filter(isWrapper).map { String($0.typeDescription.unwrapped.asSource.prefix { $0 != "<" }) })
		guard wrapperKinds.count <= 1 else { return .receiveOneWrapperKind }
		let hasRequiredOptionalValue = forms.contains { !isWrapper($0) && $0.typeDescription.isOptional && requiredProperties.contains($0) }
		guard wrapperKinds.isEmpty || !hasRequiredOptionalValue else { return .receiveTheSameWay }
		let providingForm = forms.first(where: isWrapper) ?? forms[0]
		return .declareProvidingForm(providingForm.typeDescription.unwrapped.asSource)
	}

	/// The forms of `parameter`'s label that a seam parameter of that property provides to the seam's tree, which then
	/// add no parameter: a non-optional `LazilyInstantiated` or `SendableLazilyInstantiated` provides its optional form
	/// and the by-value forms of its instance, as a wrapper a type receives offers its instance to the types beneath
	/// it; a by-value property provides its optional form; an optional wrapper provides nothing but itself.
	private static func formsProvided(by parameter: Property) -> Set<Property> {
		var forms: Set<Property> = [parameter]
		if !parameter.typeDescription.isOptional {
			forms.insert(parameter.asOptionalProperty)
		}
		if let instanceProperty = parameter.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
			forms.insert(instanceProperty)
			forms.insert(instanceProperty.asOptionalProperty)
		}
		return forms
	}

	/// The scope that calls `seam`'s generated initializer wherever a tree reaches it, which declares the whole
	/// signature: the parameters of `tier` – the seam's own `@Received` and `@Forwarded` properties as the seam declares
	/// them, and each pass-through as a `@Received` property, received only if available when the parameter is –
	/// which the tier's initializer takes, and every parameter the tier omits or no tier takes, as an only-if-available
	/// receive the call never passes but which orders the leaf among its siblings as the receivers built inline would.
	/// - Parameter initializerAccess: The access the leaf's initializer carries, the tier's level: the check of every
	///   construction reads only the seam's type for a leaf (`Construction.isSeamLeaf`).
	private static func seamLeafInstantiable(of seam: Instantiable, signature: SeamSignature, tier: AccessLevel, initializerAccess: AccessDeclaration) -> Instantiable {
		let parameters = signature.parameters(ofTierAt: tier)
		let ownDependencies = seam.dependencies.filter { dependency in
			switch dependency.source {
			case .received, .forwarded:
				true
			case .instantiated, .aliased:
				false
			}
		}
		var leaf = Instantiable(
			instantiableType: seam.concreteInstantiable,
			isRoot: false,
			generatesDependencyTree: true,
			initializer: Initializer(
				access: initializerAccess,
				// Spelled as a parsed initializer, and the generated tier, spell each parameter – a closure `@escaping` –
				// so a dependency matches it as it matches a hand-written initializer's argument. The dependencies keep
				// the property as declared. A generated call calls the initializer only generated code calls, under its
				// prefixed labels.
				arguments: parameters.map { parameter in
					Initializer.Argument(
						outerLabel: parameter.generatedOnlyArgumentLabel,
						innerLabel: parameter.property.label,
						typeDescription: parameter.property.asFunctionParamter.typeDescription,
						defaultValueExpression: nil,
					)
				},
			),
			additionalInstantiables: Array(seam.instantiableTypes.dropFirst()),
			// The leaf declares the whole signature: the tier's parameters as the tier takes them, and every parameter the
			// tier omits or no tier takes as an only-if-available receive, which the call never passes but which orders
			// the leaf among its siblings, and reaches the trees that call it, exactly as the receivers built inline would.
			dependencies: parameters.map { parameter in
				if let ownDependency = ownDependencies.first(where: { $0.property == parameter.property }) {
					ownDependency
				} else {
					Dependency(
						property: parameter.property,
						source: .received(onlyIfAvailable: parameter.isOnlyIfAvailable),
						declarationLocation: seam.declarationLocation,
					)
				}
			} + (signature.parameters.filter { $0.tierAccess < tier } + signature.noTierParameters).map { parameter in
				if let ownDependency = ownDependencies.first(where: { $0.property == parameter.property }), ownDependency.source == .received(onlyIfAvailable: true) {
					ownDependency
				} else {
					Dependency(
						property: parameter.property.typeDescription.isOptional ? parameter.property : parameter.property.asOptionalProperty,
						source: .received(onlyIfAvailable: true),
						declarationLocation: seam.declarationLocation,
					)
				}
			},
			declarationType: seam.declarationType,
			access: seam.access,
			enclosingTypeAccess: seam.enclosingTypeAccess,
			enclosingExtensionAccess: seam.enclosingExtensionAccess,
			mockAttributes: seam.mockAttributes,
			declarationLocation: seam.declarationLocation,
			moduleName: seam.moduleName,
			packageName: seam.packageName,
		)
		leaf.sourceFilePath = seam.sourceFilePath
		return leaf
	}

	private static func fileHeader(importing imports: String) -> String {
		let importsWhitespace = imports.isEmpty ? "" : "\n"
		return "// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.\n// Any modifications made to this file will be overwritten on subsequent builds.\n// Please refrain from editing this file directly.\n\(importsWhitespace)\(imports)\(importsWhitespace)\n"
	}

	/// The imports of a generated file whose code is `unconditionalCode`, which every build compiles, and `mockCode`, which
	/// only builds in which its condition is active compile, from `importStatements`, each spelling the access level
	/// `importAccess` decides.
	private func imports(
		_ importStatements: [ImportStatement],
		building fulfillers: Set<FulfillerImports.Fulfiller>,
		forUnconditionalCode unconditionalCode: String,
		mockCode: (code: String, condition: String)?,
	) async -> String {
		let fulfillersToImport = FulfillerImports.fulfillers(among: fulfillers, notMadeVisibleBy: importStatements, emittingModuleName: emittingModule?.identity.moduleName)
		let ownFilesRead = fulfillersToImport.isEmpty ? nil : await readOwnFilesOnce()
		let fulfillerImportStatements = ownFilesRead.map { FulfillerImports.importStatements(for: fulfillersToImport, ownFiles: $0.ownFiles) } ?? []
		let moduleNamesImportedForFulfillers = Set(fulfillerImportStatements.map(\.moduleName))
		// The compiler compares each import with those of every file of the module, including the files SafeDI read nothing
		// of, so an import added for a fulfiller takes account of what those spell. Only that import does: nothing else
		// about the generated file changes for what a file that declares no SafeDI content spells.
		let moduleNamesSpellingOwnFilesLevels = moduleNamesImportedForFulfillers.filter { ownFilesRead?.ownFiles.levelsByModuleName[$0] != nil }
		// An import's level is the generated file's to decide, so imports that differ only in level are one.
		let importStatementsByModuleName = (importStatements + fulfillerImportStatements).reduce(into: [String: Set<ImportStatement>]()) { partialResult, importStatement in
			partialResult[importStatement.moduleName, default: []].insert(importStatement.withoutAccessLevel)
		}
		let namedTypes: GeneratedImportAccess.FileNamedTypes? = if importAccess.spellsAccessLevels || !moduleNamesSpellingOwnFilesLevels.isEmpty {
			GeneratedImportAccess.FileNamedTypes(
				unconditional: importAccess.namedTypes(inGeneratedCode: unconditionalCode),
				underMockCondition: mockCode.map { mockCode in (mockCode.condition, importAccess.namedTypes(inGeneratedCode: mockCode.code)) },
			)
		} else {
			nil
		}
		let importedModuleNames = Set(importStatementsByModuleName.keys)
		return importStatementsByModuleName
			.flatMap { moduleName, importStatements in
				// A module imported whole in several ways is imported the way that asks for least: without
				// attributes if any file imports it so, and otherwise with the attributes that sort first,
				// which puts `@testable`, an error where the module is not built for testing, after the others.
				// A whole-module import added for a fulfiller stands beside the by-type imports files spell, whose
				// attributes it lacks, and which can tell their types from those of the same names in other modules.
				let writtenImportStatements = if !moduleNamesImportedForFulfillers.contains(moduleName),
				                                 let wholeModuleImport = importStatements
				                                 	.filter({ $0.kind.isEmpty && $0.type.isEmpty })
				                                 	.min(by: { $0.attributeToGenerate < $1.attributeToGenerate })
				{
					[wholeModuleImport]
				} else {
					Array(importStatements)
				}
				let moduleImportAccess = moduleNamesSpellingOwnFilesLevels.contains(moduleName) ? ownFilesRead?.importAccess ?? importAccess : importAccess
				// Every import of one module in a file spells the same level, as the compiler requires.
				let spelling: GeneratedImportAccess.Spelling = if moduleImportAccess.spellsAccessLevels, let namedTypes {
					moduleImportAccess.spelling(
						ofImportOf: moduleName,
						isExported: writtenImportStatements.contains(where: \.isExported),
						namedTypes: namedTypes,
						importedModuleNames: importedModuleNames,
					)
				} else {
					.noLevel
				}
				return writtenImportStatements.map(spelling.source(of:))
			}
			.sorted()
			.joined(separator: "\n")
	}

	/// What the module's own files say, and how an import added for a fulfiller spells its level given that.
	private struct OwnFilesRead {
		let ownFiles: FulfillerImports.OwnFiles
		let importAccess: GeneratedImportAccess
	}

	/// What the module's own files say, read the first time a generated file would gain an import apart from a type of the
	/// module that shadows the fulfiller, which only this read can find, and kept for the next.
	private func readOwnFilesOnce() async -> OwnFilesRead {
		if let ownFilesRead {
			return ownFilesRead
		} else {
			let ownFiles = await readOwnFiles?() ?? FulfillerImports.OwnFiles(typeNames: [], importStatements: [])
			let ownFilesRead = OwnFilesRead(ownFiles: ownFiles, importAccess: importAccessSpellingOwnLevels(ownFiles.levelsByModuleName))
			self.ownFilesRead = ownFilesRead
			return ownFilesRead
		}
	}

	/// Creates a mock-root ScopeGenerator using the production Scope tree.
	/// Unsatisfied received dependencies are promoted as root-level children
	/// on a NEW Scope (the shared Scope is never mutated).
	/// - Parameter cache: The results of `collectReceivedProperties` for scopes of `typeDescriptionToScopeMap`,
	///   shared across mock roots. The mock root's own scope never enters it: nothing instantiates the mock
	///   root, so only its children's results are collected.
	/// - Parameter childrenRequiringEachOtherValidation: The scopes whose children are already known not to
	///   require one another; see `validateChildrenDoNotRequireEachOther`.
	/// - Parameter promotedScopesValidatedForHiddenReceives: The scopes of `typeDescriptionToScopeMap` whose trees are
	///   already known to hide no received dependency, shared across mock roots: a scope's tree is validated the same
	///   way whichever mock root promotes it.
	/// - Parameter emittingModule: The module the mock's code compiles in, whose access to each type the mock constructs
	///   is checked, or `nil` to check none.
	private func createMockRootScopeGenerator(
		for instantiable: Instantiable,
		scope: Scope,
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		flatParameterMockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault],
		erasedToConcreteTypeMap: [TypeDescription: TypeDescription],
		emittingModule: EmittingModule?,
		receivedPropertiesCache cache: inout ReceivedPropertiesCache,
		childrenRequiringEachOtherValidation: inout ChildrenRequiringEachOtherValidation,
		promotedScopesValidatedForHiddenReceives: inout Set<ObjectIdentifier>,
	) async throws -> ScopeGenerator {
		// Recursively collect all transitive received properties from the scope tree
		// and any promoted scopes' subtrees. Results are cached per Scope identity
		// (via ObjectIdentifier) so each scope outside a cycle is visited at most once.
		let initialReceivedProperties = Self.collectReceivedProperties(
			from: scope,
			cache: &cache,
		)
		let initialReceived = initialReceivedProperties.received
		let initialOnlyIfAvailable = initialReceivedProperties.onlyIfAvailable
		// What the calls of other modules' public mocks in the tree and in the promoted scopes' trees pass, and, of that,
		// how many calls pass each the called mock builds when passed `nil`.
		var passedByPublicMockCalls = initialReceivedProperties.passedByPublicMockCalls
		var builtWhenNilByPublicMockCalls = initialReceivedProperties.builtWhenNilByPublicMockCalls
		// A promoted scope is built beside the mocked type's own children, so a call in its tree is passed what the mocked
		// type declares, as a call in the mocked type's own tree is, whose walk above leaves it out. The walk of a promoted
		// scope's tree does not, so its results leave it out here: otherwise the mock would build a second instance of
		// what the mocked type creates for the call, or a public mock would take it as a parameter.
		let mockRootDeclarations = ScopeDeclarations(scope: scope)

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

		// The mocked type's own aliases are bound at the mock root, beside the dependencies it promotes, so a receive in a
		// promoted tree that one of them provides, as a scope provides a property to the scopes beneath it, reads that
		// alias: its exact property, or the unwrapped form of an optional receive. The mock promotes nothing for such a
		// receive, which would build a node and an override nothing reads, nor walks the tree of its type.
		var mockedTypeAliasProperties = Set<Property>()
		for case let .aliased(aliasProperty, _, _, _, _) in scope.propertiesToGenerate {
			mockedTypeAliasProperties.insert(aliasProperty)
		}
		func isProvidedByMockedTypeAlias(_ property: Property) -> Bool {
			!mockedTypeAliasProperties.isEmpty
				&& ScopeGenerator.provides(property, declaredProperties: mockedTypeAliasProperties, forwardedProperties: [])
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
		repeat {
			while let property = worklist.popLast() {
				guard !isForwarded(property),
				      !isProvidedByMockedTypeAlias(property),
				      let promotedScope = scopeToPromote(for: property)?.scope
				else { continue }
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
				passedByPublicMockCalls.formUnion(scopeReceivedProperties.passedByPublicMockCalls.filter { !mockRootDeclarations.providesWhatPublicMockCallPasses($0) })
				builtWhenNilByPublicMockCalls.formUnion(scopeReceivedProperties.builtWhenNilByPublicMockCalls.filter { !mockRootDeclarations.providesWhatPublicMockCallBuildsWhenNil($0) })
			}
			// A dependency the public mock another module generated builds when its call passes `nil` is built once here
			// and passed to every call – each call an `Instantiator` makes included – and every receiver that receives it
			// only if available, as the inline mock promotes it, where this module can build it (M8.8b). One this module
			// cannot build is each called mock's to build.
			for property in builtWhenNilByPublicMockCalls.sorted() where !allRequired.contains(property) {
				guard !isForwarded(property), let promotedScope = scopeToPromote(for: property)?.scope else { continue }
				if let emittingModule {
					let constructions = Self.constructions(
						inTreeRootedAt: promotedScope,
						rootIsConstructedWithMockMethod: promotedScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType),
						rootReferenceLocation: nil,
						isMock: true,
						emittingModule: emittingModule,
						extendedTypes: extendedTypeDeclarations,
					)
					guard Self.inaccessibleConstructions(constructions, from: emittingModule, extendedTypes: extendedTypeDeclarations).isEmpty else { continue }
				}
				allReceived.insert(property)
				allRequired.insert(property)
				worklist.append(property)
			}
		} while !worklist.isEmpty
		// A public mock takes what the calls of other modules' public mocks in its tree pass and nothing else in its tree
		// receives, as a parameter that defaults to `nil`, which it passes on.
		if instantiable.generateMock == .public {
			// A wrapper promoted for them stands for its instance too.
			let surfacedByPublicMockCalls = passedByPublicMockCalls.subtracting(allReceived).subtracting(allReceived.compactMap(\.asLazilyInstantiatedInstanceProperty))
			allReceived.formUnion(surfacedByPublicMockCalls)
			allOnlyIfAvailable.formUnion(surfacedByPublicMockCalls)
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
		// promoted once, as the lazily instantiated property, whenever any receiver requires it or its instance,
		// optional or not; receivers of its instance, and of the optional instance, read it from that property.
		// The same holds for a lazily instantiated property the mock root declares itself, which needs no promotion.
		// A receive of the instance, or of the optional instance, that a forwarded property fulfills does not count:
		// the forwarded value comes from outside the tree. A required `x: LazilyInstantiated<X>?` beside no required
		// instance is promoted below as it is, as any optional form is when nothing requires its non-optional form.
		var lazilyInstantiatedPropertiesToPromote = Set<Property>()
		var instancePropertiesOfLazilyInstantiatedProperties = Set(mockRootScope.propertiesToGenerate.compactMap(\.lazilyInstantiatedInstanceProperty))
		for receivedProperty in allReceived {
			guard let instanceProperty = receivedProperty.asLazilyInstantiatedInstanceProperty else { continue }
			let lazilyInstantiatedProperty = receivedProperty.asUnwrappedProperty
			let optionalInstanceProperty = Property(label: instanceProperty.label, typeDescription: .optional(instanceProperty.typeDescription))
			guard allRequired.contains(lazilyInstantiatedProperty)
				|| (allRequired.contains(instanceProperty) && !isForwarded(instanceProperty))
				|| (allRequired.contains(optionalInstanceProperty) && !isForwarded(optionalInstanceProperty)),
				scopeToPromote(for: lazilyInstantiatedProperty) != nil
			else { continue }
			lazilyInstantiatedPropertiesToPromote.insert(lazilyInstantiatedProperty)
			instancePropertiesOfLazilyInstantiatedProperties.insert(instanceProperty)
		}

		// Each form of a dependency the tree receives under one label is promoted on its own: `x: X`,
		// `x: Instantiator<X>` and `x: ErasedInstantiator<(), AnyX>` are each built, under a name of its own, for
		// the receivers of that form. Only an optional form is not promoted beside its non-optional form: the
		// mock binds what it builds to a non-optional value, which a receive of the optional form is handed too.
		// Nor is the instance of a promoted lazily instantiated property, optional or not.
		let propertiesToPromote = allReceived.union(lazilyInstantiatedPropertiesToPromote).filter { receivedProperty in
			(lazilyInstantiatedPropertiesToPromote.contains(receivedProperty) || !allOnlyIfAvailable.contains(receivedProperty))
				&& !isForwarded(receivedProperty)
				&& !isProvidedByMockedTypeAlias(receivedProperty)
				&& !instancePropertiesOfLazilyInstantiatedProperties.contains(receivedProperty.asUnwrappedProperty)
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

		// The mock's tree builds the type of each scope the mock root's scope reaches.
		var instantiablesInMockTree = [Instantiable]()
		var visitedScopesInMockTree = Set<ObjectIdentifier>()
		var scopesInMockTreeToVisit = [mockRootScope]
		while let scopeToVisit = scopesInMockTreeToVisit.popLast() {
			guard visitedScopesInMockTree.insert(ObjectIdentifier(scopeToVisit)).inserted else { continue }
			instantiablesInMockTree.append(scopeToVisit.instantiable)
			for case let .instantiated(_, childScope, _) in scopeToVisit.propertiesToGenerate {
				scopesInMockTreeToVisit.append(childScope)
			}
		}
		try Self.validateDependencyLabelsAreDistinct(in: instantiablesInMockTree)
		try Self.validateRenamesAreSpelledAsTheMacroAccepts(in: instantiablesInMockTree)

		// Validate the promoted mock scope for cycles before generating code.
		// This catches cycles that only become visible after @Received dependencies
		// are promoted to the mock root (e.g., B @Receives Instantiator<A> where A
		// instantiates B — the promotion creates a cycle in the mock root scope).
		try validateMockRootScopeForCycles(mockRootScope)
		// Promotion can also make the mock root's children require one another
		// (e.g., C @Receives B while B's subtree @Receives C — each must be built
		// first), which no ancestor stack shows. Detecting that is cheap; production's
		// walk, which follows received dependencies between scopes, then reports the
		// cycle. Running that walk on every mock root instead would add a
		// received-dependency walk for every node of every mock tree.
		let mockRootChildrenRequiringEachOther = Self.childrenRequiringEachOther(in: mockRootScope, cache: &cache)
		try validatePropertiesAreFulfillable(
			onRootScopes: mockRootChildrenRequiringEachOther != nil
				? [ValidatedRootScope(scope: mockRootScope, boundProperties: allReceived, isMock: !instantiable.isRoot)]
				: [],
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: true,
		)
		// That walk does not follow a received `Instantiator` to the scope it builds, and
		// promoted scopes' trees are walked by no cycle validation (below, each is walked for
		// hidden received dependencies alone), so report what it leaves: children, here or
		// anywhere in the mock tree, that require one another, in the order
		// `validateChildrenDoNotRequireEachOther` checks them. The mock root's own children
		// were checked above, so only their trees are left.
		if let mockRootChildrenRequiringEachOther {
			throw mockRootChildrenRequiringEachOther.error
		} else {
			var mockRootChildScopes = [Scope]()
			for case let .instantiated(_, childScope, _) in mockRootScope.propertiesToGenerate {
				mockRootChildScopes.append(childScope)
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
		// Every receive of a label in a mock's tree, back to a type in it that declares the label, resolves in production to
		// the one declaration of the label above that tree – above the mocked type for its own tree, and above the tree of a
		// promoted dependency, which is built above the mocked type – so two receives of it there, one beneath or beside the
		// other, of which one is required, must be fulfillable by one declaration, through an alias or by name alike. The
		// required receive pins that declaration to its type, so production cannot build the other receive, or always
		// passes it `nil`, while the mock binds the forms of the label apart and offers the other a value production never
		// passes, or passes one form under the label where the other would read it. Two `onlyIfAvailable` receives pin
		// nothing: production fulfills each where it is built beneath a declaration of its type, and the mock offers each
		// its own override, as it does for siblings. One rule covers every tree the mock builds inline, at every depth, so
		// whether a mock is accepted never depends on how it binds names. Only a label the mock binds in several forms can
		// hold such a pair, so the trees are walked only for those.
		var formsByLabel = [String: Set<Property>]()
		for receivedProperty in allReceived {
			formsByLabel[receivedProperty.label, default: []].insert(receivedProperty.asUnwrappedProperty)
		}
		for dependency in instantiable.dependencies where !dependency.source.isReceived {
			formsByLabel[dependency.property.label, default: []].insert(dependency.property.asUnwrappedProperty)
		}
		let labelsBoundInSeveralForms = Set(formsByLabel.lazy.filter { $0.value.count > 1 }.map(\.key))
		if !labelsBoundInSeveralForms.isEmpty,
		   let receivedPropertyHiddenInMockTree = Self.receivedPropertyHiddenInMockTree(
		   	labels: labelsBoundInSeveralForms,
		   	of: instantiable,
		   	scope: scope,
		   	promotedChildren: mockRootScope.propertiesToGenerate[scope.propertiesToGenerate.count...],
		   )
		{
			throw DependencyTreeGeneratorError.receivedPropertyHiddenInMockTree(receivedPropertyHiddenInMockTree)
		}

		// A promoted dependency stands for one the mocked type receives from above it, so in production its tree is built
		// above the mocked type, wherever the dependency is built. A receive in that tree that a closer declaration in it
		// hides is rejected there, so the mock rejects it too, as it rejects one in the mocked type's own tree: the
		// validation of an additional mock's tree, run from the promoted dependency as from that mock's type, which
		// declares nothing above it, so that the mocked type's own declarations hide nothing in it, and whose tree's
		// received properties the mock binds. Each promoted scope's tree that passes is validated once; one that fails
		// is walked again by every mock root that promotes it, so that each reports the error whatever order the mock
		// roots are created in.
		var promotedScopesToValidate = [ValidatedRootScope]()
		var promotedScopeIdentifiersToValidate = Set<ObjectIdentifier>()
		for case let .instantiated(_, promotedScope, _) in mockRootScope.propertiesToGenerate[scope.propertiesToGenerate.count...]
			where !promotedScopesValidatedForHiddenReceives.contains(ObjectIdentifier(promotedScope))
			&& promotedScopeIdentifiersToValidate.insert(ObjectIdentifier(promotedScope)).inserted
		{
			promotedScopesToValidate.append(ValidatedRootScope(
				scope: promotedScope,
				boundProperties: Self.collectReceivedProperties(from: promotedScope, cache: &cache).received,
				isMock: true,
			))
		}
		if !promotedScopesToValidate.isEmpty {
			try validatePropertiesAreFulfillable(
				onRootScopes: [],
				additionalMockRootScopes: promotedScopesToValidate,
				typeDescriptionToScopeMap: typeDescriptionToScopeMap,
				cyclesOnly: true,
			)
			promotedScopesValidatedForHiddenReceives.formUnion(promotedScopeIdentifiersToValidate)
		}

		// `mock()` defaults a flat parameter only to a hand-written mock this module can call
		// (`flatParameterMockDefaults(in:emittingModule:)`), so the defaults construct nothing that is checked here.
		if let emittingModule {
			// The mock of a type declared in this module refers to its tree from the type's declaration; the mock of a
			// type this module lists in `additionalMocksToGenerate`, from the `#SafeDIConfiguration` that lists it.
			let rootReferenceLocation = instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false
				? instantiable.declarationLocation
				: emittingModule.additionalMocksToGenerateLocation
			// A mock constructs its root with the root's hand-written mock whenever it has one.
			let constructions = Self.constructions(
				inTreeRootedAt: mockRootScope,
				rootIsConstructedWithMockMethod: instantiable.mockInitializer != nil,
				rootReferenceLocation: rootReferenceLocation,
				isMock: true,
				emittingModule: emittingModule,
				extendedTypes: extendedTypeDeclarations,
			)
			let inaccessibleConstructions = Self.inaccessibleConstructions(
				constructions,
				from: emittingModule,
				extendedTypes: extendedTypeDeclarations,
				mockRoot: DependencyTreeGeneratorError.InaccessibleConstruction.MockRoot(type: instantiable.concreteInstantiable, declarationLocation: instantiable.declarationLocation),
			)
			guard inaccessibleConstructions.isEmpty else {
				throw DependencyTreeGeneratorError.inaccessibleConstructions(inaccessibleConstructions)
			}
		}

		// Build the final ScopeGenerator once. The mock root binds every received
		// property it does not promote — as a `mock()` parameter or a `SafeDIOverrides`
		// entry — so each is receivable throughout the tree.
		func mockRootGenerator(builders: ShapedBuilders?) throws -> ScopeGenerator {
			try mockRootScope.createScopeGenerator(
				for: nil,
				// The mock root binds every received property it does not promote, which encloses its whole tree.
				nearestDeclarations: .binding(allReceived),
				lazilyInstantiatedInstanceProperties: [],
				mockBuilders: builders,
				erasedToConcreteExistential: false,
				forMockGeneration: true,
				declaredTypeNames: declaredTypeNames,
			)
		}
		let generator = try mockRootGenerator(builders: nil)
		try Self.validateCycleLabelsArePassable(inTreesRootedAt: [generator])
		// A public mock's tree holds a site for each hole (see `createMockTypeDescriptionToScopeMapping`), and a call of
		// another module's public mock passes up the places it cannot fill: `mock()` takes builders for them, shaped as a
		// seam's are. The sites' fields are what is in scope there, read from the tree as a seam's are, and the tree is built
		// again so that each site calls its builder, and each call hands its builders up.
		guard instantiable.generateMock == .public, generator.containsBuildSite || generator.passesUpBuilder else { return generator }
		let holes = Self.holes(
			of: instantiable,
			generator: generator,
			parameters: [],
			proof: publicMockContext.proof,
			instantiables: typeDescriptionToFulfillingInstantiableMap,
		)
		let treeFunctionNames = Self.builderFunctionNamesOfProperties(in: generator, includingHoleSites: false)
		func shapedBuilders(namedApartFrom otherParameters: [(label: String, access: AccessLevel)]) -> ShapedBuilders {
			Self.shapedBuilders(
				of: instantiable,
				generator: generator,
				holes: holes,
				parameters: [],
				otherParameters: otherParameters,
				treeFunctionNames: treeFunctionNames,
				proof: publicMockContext.proof,
				instantiables: typeDescriptionToFulfillingInstantiableMap,
				ownScopeEnums: [:],
				scopeTypeNames: .publicMock,
			)
		}
		let builders = shapedBuilders(namedApartFrom: [])
		let builtGenerator = try mockRootGenerator(builders: builders)
		// The builders follow every other parameter, and each tier's are named apart from the parameters it takes as a seam's
		// are. A builder's name changes no other parameter's, so the tree is built again only when a builder takes another
		// name in some tier.
		let parameters = await builtGenerator.mockRootParameters(instantiable: instantiable, mockDefaults: flatParameterMockDefaults)
		let otherParameters = ScopeGenerator.publicMockPlan(
			of: instantiable,
			parameters: parameters,
			parameterNames: ScopeGenerator.mockRootParameterNames(of: parameters),
			context: publicMockContext,
		).parameters.filter { $0.builder == nil }.map { (label: $0.name, access: $0.access) }
		let buildersNamedApart = shapedBuilders(namedApartFrom: otherParameters)
		guard buildersNamedApart.builders.map(SeamSignature.CallShape.Builder.init) != builders.builders.map(SeamSignature.CallShape.Builder.init) else { return builtGenerator }
		return try mockRootGenerator(builders: buildersNamedApart)
	}

	/// The names `instantiables` and `plainTypeDeclarations` declare types by at file scope. A type of such a name hides the
	/// standard library's type or the module of that name, so comparing an erased instantiator's first generic argument with
	/// a built type's forwarded properties does not see through it. An extension declares no type of the name it extends.
	private static func namesOfTypesDeclaredAtFileScope(instantiables: [Instantiable], plainTypeDeclarations: [PlainTypeDeclaration]) -> DeclaredTypeNames {
		var moduleNamesByTypeName = [String: Set<String?>]()
		for instantiable in instantiables where !instantiable.declarationType.isExtension {
			if case let .simple(name, _) = instantiable.concreteInstantiable {
				moduleNamesByTypeName[name, default: []].insert(instantiable.moduleName)
			}
		}
		for declaration in plainTypeDeclarations where declaration.extendedType == nil {
			if case let .simple(name, _) = declaration.typeDescription {
				moduleNamesByTypeName[name, default: []].insert(declaration.moduleName)
			}
		}
		return DeclaredTypeNames(moduleNamesByTypeName: moduleNamesByTypeName)
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
	/// properties, or is a tuple of them whose elements are not each one bare name (`Property.mockBuildsFirstGeneric(of:)`).
	/// Such a received property stays a `mock()` parameter; an `@Instantiated` declaration of a mismatched type is reported
	/// where a tree builds that declaration, and the tuple is built where a tree declares it.
	private static func mockCanBuild(_ property: Property, from scope: Scope) -> Bool {
		guard property.mockBuildsFirstGeneric(of: scope.instantiable) else { return false }
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

	/// A receive of a label, in the tree of a dependency a mock root promotes, from above the type that declares it.
	private struct HidingReceive {
		let dependency: Dependency
		/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
		let property: Property
		/// Whether `dependency` requires `property`: it is not `onlyIfAvailable`.
		let isRequired: Bool
		/// The type that declares `dependency`.
		let hidingType: TypeDescription

		/// What `dependency` reads, which decides what it hides.
		var propertiesRead: Set<Property> {
			DependencyTreeGenerator.propertiesRead(byReceiveOf: dependency)
		}
	}

	/// A scope that `receivedPropertyHiddenInMockTree` has yet to walk.
	private struct ScopeToWalkForHiddenReceivedProperty {
		let scope: Scope
		/// The tree of the mock that holds `scope`.
		let tree: DependencyTreeGeneratorError.ReceivedPropertyHiddenInMockTree.Tree
		/// The types from the type at the top of `tree` to the type of `scope`.
		let chain: [TypeDescription]
		/// The receives of each label walked by the closest type above `scope` that receives it, when no type between
		/// declares it, in declaration order.
		let hidingReceivesByLabel: [String: [HidingReceive]]
		/// The labels walked that a type above `scope` declares, whose receives beneath resolve to that declaration.
		let declaredLabels: Set<String>
	}

	/// A visit of a scope by `receivedPropertyHiddenInMockTree`: what the walk carries into it decides what it finds.
	private struct HiddenReceivedPropertyScopeVisit: Hashable {
		let scope: ObjectIdentifier
		let hidingPropertiesReadByLabel: [String: [Set<Property>]]
		let declaredLabels: Set<String>
	}

	/// The first receive, walking the mocked type's own tree and then the trees of a mock root's promoted children, each
	/// depth first in declaration order, of one of `labels` beneath a type that receives that label in a form no one
	/// declaration provides together with it, or after such a receive on its own type, where either receive is required.
	/// `nil` when there is none. In production every receive of the label in such a tree resolves to the closest
	/// declaration of the label above that tree – above the mocked type for its own tree, and above a promoted
	/// dependency's tree, which is built above the mocked type – which cannot fulfill both, so the required receive leaves
	/// production unable to build the other or passing it `nil` wherever the tree is built. The mock offers that receive a
	/// value, passes one of the two forms under the label where the other would read it, or binds it in a scope where the
	/// other is read. A type that declares the label is what the types it builds receive under it, as in production, and the
	/// validation of each tree reports what that declaration hides.
	/// - Parameters:
	///   - labels: The labels the mock binds in several forms, the only ones that can hold such a pair.
	///   - instantiable: The mocked type.
	///   - scope: The scope of the mocked type, without the promoted children.
	///   - promotedChildren: The mock root's promoted children, in the order the mock declares them.
	private static func receivedPropertyHiddenInMockTree(
		labels: Set<String>,
		of instantiable: Instantiable,
		scope mockedTypeScope: Scope,
		promotedChildren: ArraySlice<Scope.PropertyToGenerate>,
	) -> DependencyTreeGeneratorError.ReceivedPropertyHiddenInMockTree? {
		var walkedScopes = Set<HiddenReceivedPropertyScopeVisit>()
		var scopesToWalk = [ScopeToWalkForHiddenReceivedProperty]()
		// The mocked type's own tree is walked first: it is what the mock builds above its promoted children's trees.
		walkedScopes.insert(HiddenReceivedPropertyScopeVisit(scope: ObjectIdentifier(mockedTypeScope), hidingPropertiesReadByLabel: [:], declaredLabels: []))
		scopesToWalk.append(ScopeToWalkForHiddenReceivedProperty(
			scope: mockedTypeScope,
			tree: .mockedType,
			chain: [mockedTypeScope.instantiable.concreteInstantiable],
			hidingReceivesByLabel: [:],
			declaredLabels: [],
		))
		for case let .instantiated(_, promotedScope, _) in promotedChildren
			where walkedScopes.insert(HiddenReceivedPropertyScopeVisit(scope: ObjectIdentifier(promotedScope), hidingPropertiesReadByLabel: [:], declaredLabels: [])).inserted
		{
			let promotedType = promotedScope.instantiable.concreteInstantiable
			scopesToWalk.append(ScopeToWalkForHiddenReceivedProperty(
				scope: promotedScope,
				tree: .promotedDependency(promotedType),
				chain: [promotedType],
				hidingReceivesByLabel: [:],
				declaredLabels: [],
			))
		}
		// The scope walked next is the last one on the stack, so the first goes last.
		scopesToWalk.reverse()
		while let scopeToWalk = scopesToWalk.popLast() {
			let scope = scopeToWalk.scope
			let scopeType = scope.instantiable.concreteInstantiable
			// The labels the type declares, which the types it builds receive under them, and which its own aliases of
			// them rename.
			let labelsDeclaredByScope = Set(scope.instantiable.dependencies.lazy.filter { !$0.source.isReceived }.map(\.property.label))
			// A builder passed up to the mock's own parameter is read there, which the mock names apart from every label.
			let receives = scope.instantiable.dependencies.compactMap { dependency -> HidingReceive? in
				guard !(scope.publicMockCall?.passesUpBuilder(receivedAs: dependency.property) ?? false) else { return nil }
				return Self.propertyReceivedFromAbove(byReceiveOf: dependency, onTypeDeclaring: labelsDeclaredByScope).map {
					HidingReceive(dependency: dependency, property: $0.property, isRequired: $0.isRequired, hidingType: scopeType)
				}
			}
			var receivesByLabel = [String: [HidingReceive]]()
			for receive in receives
				where labels.contains(receive.property.label) && !scopeToWalk.declaredLabels.contains(receive.property.label)
			{
				// Every receive of the label above, back to the closest type that receives it, and every earlier receive
				// of it on this type, resolve to the declaration this receive resolves to.
				let receivesAbove = scopeToWalk.hidingReceivesByLabel[receive.property.label, default: []]
				let earlierReceives = receivesAbove + receivesByLabel[receive.property.label, default: []]
				let propertiesRead = receive.propertiesRead
				// A required receive pins the declaration both resolve to to its own type, so production cannot build the
				// other receive, or always passes it `nil` where the mock would offer a value. Two `onlyIfAvailable`
				// receives pin nothing: production fulfills each where it is built beneath a declaration of its type, and
				// the mock offers each its own override, as it does for siblings.
				if let hidingReceiveIndex = earlierReceives.firstIndex(where: { earlierReceive in
					(receive.isRequired || earlierReceive.isRequired)
						&& !Self.oneDeclarationFulfills(propertiesRead, and: earlierReceive.propertiesRead)
				}) {
					let hidingReceive = earlierReceives[hidingReceiveIndex]
					return .init(
						property: receive.property,
						declarationLocation: receive.dependency.declarationLocation,
						mockedType: instantiable.concreteInstantiable,
						tree: scopeToWalk.tree,
						hidingProperty: hidingReceive.property,
						hidingDeclarationLocation: hidingReceive.dependency.declarationLocation,
						hidingType: hidingReceive.hidingType,
						isHiddenOnItsOwnType: hidingReceiveIndex >= receivesAbove.count,
						chain: scopeToWalk.chain,
					)
				} else {
					receivesByLabel[receive.property.label, default: []].append(receive)
				}
			}
			var hidingReceivesByLabel = scopeToWalk.hidingReceivesByLabel.merging(receivesByLabel) { _, receivesOfScope in receivesOfScope }
			var declaredLabels = scopeToWalk.declaredLabels
			for label in labelsDeclaredByScope where labels.contains(label) {
				// A type that declares the label is what the types it builds receive under it, as in production.
				declaredLabels.insert(label)
				hidingReceivesByLabel[label] = nil
			}
			let hidingPropertiesReadByLabel = hidingReceivesByLabel.mapValues { $0.map(\.propertiesRead) }
			let firstChildIndex = scopesToWalk.endIndex
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate
				where walkedScopes.insert(HiddenReceivedPropertyScopeVisit(scope: ObjectIdentifier(childScope), hidingPropertiesReadByLabel: hidingPropertiesReadByLabel, declaredLabels: declaredLabels)).inserted
			{
				scopesToWalk.append(ScopeToWalkForHiddenReceivedProperty(
					scope: childScope,
					tree: scopeToWalk.tree,
					chain: scopeToWalk.chain + [childScope.instantiable.concreteInstantiable],
					hidingReceivesByLabel: hidingReceivesByLabel,
					declaredLabels: declaredLabels,
				))
			}
			// The scope walked next is the last one on the stack, so the first child goes last.
			scopesToWalk[firstChildIndex...].reverse()
		}
		return nil
	}

	/// The property a receive of `dependency` reads from above the type that declares it, which declares
	/// `labelsDeclaredByType`: the received property, or an alias's fulfilling property, with whether the receive
	/// requires it. `nil` for a dependency the type creates, and for an alias of a label the type declares, which renames
	/// that property, unless the alias keeps the label it renames.
	private static func propertyReceivedFromAbove(
		byReceiveOf dependency: Dependency,
		onTypeDeclaring labelsDeclaredByType: Set<String>,
	) -> (property: Property, isRequired: Bool)? {
		switch dependency.source {
		case let .received(onlyIfAvailable):
			(dependency.property, !onlyIfAvailable)
		case let .aliased(fulfillingProperty, _, onlyIfAvailable):
			fulfillingProperty.label == dependency.property.label || !labelsDeclaredByType.contains(fulfillingProperty.label)
				? (fulfillingProperty, !onlyIfAvailable)
				: nil
		case .instantiated, .forwarded:
			nil
		}
	}

	/// The properties a receive of `dependency` reads, as the validation of hidden received properties judges them: a
	/// receive of an optional property reads its non-optional form too, and an `onlyIfAvailable` alias reads the
	/// optional form of its fulfilling property.
	private static func propertiesRead(byReceiveOf dependency: Dependency) -> Set<Property> {
		switch dependency.source {
		case let .aliased(fulfillingProperty, _, onlyIfAvailable):
			onlyIfAvailable
				? Set(fulfillingProperty.formsReadByOnlyIfAvailableReceive)
				: [fulfillingProperty, fulfillingProperty.asUnwrappedProperty]
		case .received, .instantiated, .forwarded:
			[dependency.property, dependency.property.asUnwrappedProperty]
		}
	}

	/// Whether one declaration can fulfill two receives that read `properties` and `otherProperties`: a declaration
	/// fulfills a receive that reads it, or, when it is lazily instantiated, the instance it provides. A declaration that
	/// fulfills both is therefore among the properties one of them reads.
	private static func oneDeclarationFulfills(_ properties: Set<Property>, and otherProperties: Set<Property>) -> Bool {
		func fulfills(_ declaredProperty: Property, _ propertiesRead: Set<Property>) -> Bool {
			propertiesRead.contains(declaredProperty)
				|| declaredProperty.asLazilyInstantiatedInstanceProperty.map(propertiesRead.contains) ?? false
		}
		return properties.union(otherProperties).contains { fulfills($0, properties) && fulfills($0, otherProperties) }
	}

	/// A scope that `validateMockRootScopeForCycles` has yet to walk.
	private struct ScopeToWalkForCycles {
		let scope: Scope
		/// The properties of the scopes `scope` is built inside, innermost first, as cycle validation sees them.
		let propertyStack: [Property]
		/// The concrete types of the scopes `scope` is built inside, innermost first, beside `propertyStack`.
		let concreteTypeStack: [TypeDescription]
		/// The lazily instantiated properties on `propertyStack`, keyed by the constant each is validated as.
		let lazilyInstantiatedDeclarations: [Property: Property]
		/// The properties the nearest declarations of each label above `scope` declare, as cycle validation sees them, with
		/// how many scopes the declaring scope is built inside: `0` for the mock root, which declares the properties it
		/// creates and the dependencies it promotes, several forms of one label among them.
		let nearestDeclarationByLabel: [String: (properties: [Property], depth: Int)]
	}

	/// The children a mock root promotes, in the order its tree first receives them: the order in which a walk first
	/// meets a receive of each. The walk visits the mock root's own dependencies in declaration order, then the tree of
	/// each child it instantiates, depth first, each type's dependencies before its children's trees, all in
	/// declaration order. It then walks, in the order it first met them, the trees of the dependencies the mock builds
	/// for what its receivers require, which are where the mock tree receives the rest, and, once those are walked, the
	/// trees of the fills the calls of other modules' public mocks it met pass, in the order it met the calls: a call
	/// inside a fill can be the only receiver of a dependency its called mock builds when passed `nil`, which the mock
	/// promotes (`builtWhenNilByPublicMockCalls`). A receive of a promoted child is one of its property, of the property's
	/// optional form, or of the instance of a lazily instantiated property.
	///
	/// The order depends only on where properties are declared and how they are nested, never on their labels or type
	/// names: when two promoted children receive each other only if available, the one received first is built second,
	/// as the property declared first is in production.
	/// - Parameters:
	///   - promotedChildren: The children the mock root promotes. The walk meets a receive of each, since each is a
	///     dependency that the mock root's tree, the tree of a dependency the mock builds for a receiver, or the tree of a
	///     fill in either, receives.
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
		// The fills of the calls of other modules' public mocks the walk meets, in order, whose trees are walked last.
		var fillScopes = [Scope]()
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
				if scope.publicMockCall != nil {
					for case let .fill(_, fillScope) in scope.holeArguments {
						fillScopes.append(fillScope)
					}
				}
			}
		}
		walk(mockRootScope)
		var receivedPropertyIndex = 0
		var fillScopeIndex = 0
		while orderedIndices.count < promotedChildren.count,
		      receivedPropertyIndex < receivedProperties.count || fillScopeIndex < fillScopes.count
		{
			if receivedPropertyIndex < receivedProperties.count {
				if let builtScope = scopesBuiltForRequiredProperties[receivedProperties[receivedPropertyIndex]] {
					walk(builtScope)
				}
				receivedPropertyIndex += 1
			} else {
				walk(fillScopes[fillScopeIndex])
				fillScopeIndex += 1
			}
		}
		return orderedIndices.map { promotedChildren[$0] }
	}

	/// Walks a post-promotion mock root scope for dependency cycles.
	/// The mock root scope has @Received dependencies promoted as children,
	/// which can create cycles not visible in the pre-promotion scope.
	/// The walk goes depth first, in the order each scope declares its children, and keeps its own stack of
	/// the scopes left to walk, since a tree can be as deep as the module has types.
	private func validateMockRootScopeForCycles(_ mockRootScope: Scope) throws {
		var scopesToWalk = [ScopeToWalkForCycles(scope: mockRootScope, propertyStack: [], concreteTypeStack: [], lazilyInstantiatedDeclarations: [:], nearestDeclarationByLabel: [:])]
		while let scopeToWalk = scopesToWalk.popLast() {
			let scope = scopeToWalk.scope
			let propertyStack = scopeToWalk.propertyStack
			// Check dependencies for cycles (catches @Received references back to ancestors).
			for dependency in scope.instantiable.dependencies where !dependency.isForwarded {
				let declaredPropertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
				let propertyForDependency = declaredPropertyForDependency.asValidatedForDependencyCycles
				// An `onlyIfAvailable` dependency is passed `nil` instead (`Dependency.canCloseDependencyCycle`), and an
				// `onlyIfAvailable` alias is bound to `nil`, which a receive of it reads.
				guard dependency.canCloseDependencyCycle else { continue }
				// A mock promotes a received optional property as the non-optional value it builds, so a receive of the
				// non-optional form inside the tree it builds reaches it too.
				let receivedForms: [Property] = if dependency.isInstantiated {
					[propertyForDependency]
				} else {
					[propertyForDependency, Property(label: propertyForDependency.label, typeDescription: .optional(propertyForDependency.typeDescription))]
				}
				let closingReceive = Self.closingReceive(of: dependency, in: scope)
				guard let cycleIndex = Self.indexOfEntryClosedOn(
					by: declaredPropertyForDependency,
					of: scope,
					receivedForms: receivedForms,
					closesByReceive: closingReceive != nil,
					propertyStack: propertyStack,
					concreteTypeStack: scopeToWalk.concreteTypeStack,
					nearestDeclaration: { scopeToWalk.nearestDeclarationByLabel[$0] },
				) else {
					continue
				}
				let propertiesInCycle = [propertyForDependency] + propertyStack[0...cycleIndex]
				try throwIfInvalidCycle(
					propertiesInCycle: propertiesInCycle,
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

			// Walk the children next. They see what this scope declares as the nearest declaration of its labels: what it
			// creates, and at the mock root the dependencies it promotes.
			var childNearestDeclarationByLabel = scopeToWalk.nearestDeclarationByLabel
			var labelsDeclaredHere = Set<String>()
			func declare(_ property: Property) {
				if labelsDeclaredHere.insert(property.label).inserted {
					childNearestDeclarationByLabel[property.label] = ([property.asValidatedForDependencyCycles], propertyStack.count)
				} else {
					childNearestDeclarationByLabel[property.label]?.properties.append(property.asValidatedForDependencyCycles)
				}
			}
			for dependency in scope.instantiable.dependencies where scope.createdProperties.contains(dependency.property) {
				declare(dependency.property)
			}
			for propertyToGenerate in scope.propertiesToGenerate where !scope.createdProperties.contains(propertyToGenerate.property) {
				declare(propertyToGenerate.property)
			}
			let firstChildIndex = scopesToWalk.endIndex
			for childPropertyToGenerate in scope.propertiesToGenerate {
				switch childPropertyToGenerate {
				case let .instantiated(declaredChildProperty, childScope, _):
					let childProperty = declaredChildProperty.asValidatedForDependencyCycles
					let childConcreteType = childScope.instantiable.concreteInstantiable
					guard !propertyStack.indices.contains(where: { propertyStack[$0] == childProperty && scopeToWalk.concreteTypeStack[$0] == childConcreteType }) else { continue }
					scopesToWalk.append(ScopeToWalkForCycles(
						scope: childScope,
						propertyStack: [childProperty] + propertyStack,
						concreteTypeStack: [childConcreteType] + scopeToWalk.concreteTypeStack,
						lazilyInstantiatedDeclarations: scopeToWalk.lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
						nearestDeclarationByLabel: childNearestDeclarationByLabel,
					))
				case .aliased, .hole:
					// A hole's tree is a fill's, which a mock never builds: a mock's scopes hold no hole.
					break
				}
			}
			// The scope walked next is the last one on the stack, so the first child goes last.
			scopesToWalk[firstChildIndex...].reverse()
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

	/// A child of a scope that a property names, with how directly it names the child: the lower `directness`, the
	/// more directly.
	private struct NamedChild {
		let index: Int
		let directness: Int
	}

	/// The scopes `validateChildrenDoNotRequireEachOther` has validated across the trees it is given.
	private struct ChildrenRequiringEachOtherValidation {
		/// The scopes whose children, and whose trees' children, are known not to require one another. Which children of
		/// a scope require one another depends on the scope's tree alone: a requirement through an `onlyIfAvailable` alias
		/// stops at the nearest declaration of its label, wherever the scope is built.
		var validatedScopes = Set<Scope>()
	}

	/// The instantiated children of `scope` that require one another in a cycle, if any:
	/// each child's tree requires (not `onlyIfAvailable`) a sibling that, directly or
	/// through other siblings, requires it. Such children cannot be ordered so that each
	/// is built after the siblings it receives — whatever their property types, since an
	/// `Instantiator` captures what its tree receives when it is created. A child's tree requires the
	/// property an `onlyIfAvailable` alias in it is bound from when a receiver requires the alias, where
	/// the nearest declaration of that property's label is a sibling (see
	/// `ScopeGenerator.requiredAliasFulfillingProperties`).
	private static func childrenRequiringEachOther(
		in scope: Scope,
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
		/// The child that declares the label of `fulfillingProperty`, which an `onlyIfAvailable` alias of it is bound
		/// from where that child provides a form the alias reads (see `ScopeGenerator.provides(_:aFormReadBy:)`).
		func childBindingOnlyIfAvailableAlias(of fulfillingProperty: Property) -> NamedChild? {
			for (index, child) in children.enumerated()
				where child.property.label == fulfillingProperty.label && ScopeGenerator.provides(child.property, aFormReadBy: fulfillingProperty)
			{
				return NamedChild(index: index, directness: child.property == fulfillingProperty ? 0 : 1)
			}
			return nil
		}
		// A child's tree that requires an alias the scope declares requires the child the alias is assigned from. No
		// alias of the scope renames another (SafeDITool rejects that before it validates a tree that builds the
		// scope). An `onlyIfAvailable` alias is bound for a receiver that requires it from the child that declares
		// its fulfilling property's label, so it is assigned after that child too.
		var aliasCount = 0
		var onlyIfAvailableAliasFulfillingPropertyByProperty = [Property: Property]()
		var aliasedChildByProperty = [Property: NamedChild]()
		for case let .aliased(property, fulfillingProperty, _, onlyIfAvailable, _) in scope.propertiesToGenerate {
			let namedChild: NamedChild?
			if onlyIfAvailable {
				onlyIfAvailableAliasFulfillingPropertyByProperty[property] = fulfillingProperty
				namedChild = childBindingOnlyIfAvailableAlias(of: fulfillingProperty)
			} else {
				// An alias of a child's optional form is assigned from that child, as a required receive of it is fulfilled.
				let fulfillingProperties = fulfillingProperty.typeDescription.isOptional
					? [fulfillingProperty, fulfillingProperty.asUnwrappedProperty]
					: [fulfillingProperty]
				namedChild = fulfillingProperties.lazy.compactMap { childByProperty[$0] }.first
			}
			if let namedChild {
				aliasedChildByProperty[property] = NamedChild(index: namedChild.index, directness: 2 + aliasCount)
			}
			aliasCount += 1
		}
		func namedChild(declaring property: Property) -> NamedChild? {
			childByProperty[property] ?? aliasedChildByProperty[property]
		}
		/// The child declaring the unwrapped form of `property`, which fulfills a required receive of `property`, and
		/// which `property` names less directly than any property the scope declares does.
		func namedChild(declaringUnwrapped property: Property) -> NamedChild? {
			namedChild(declaring: property.asUnwrappedProperty).map {
				NamedChild(index: $0.index, directness: $0.directness + 2 + aliasCount)
			}
		}
		// The siblings each child requires, in sibling order, each with the property through which it is received that
		// names it most directly. A child that receives its own property is reported by the received walk or the ancestor
		// check, but one that receives it through an alias or unwrapped requires itself here. Only the received properties
		// that name a sibling are kept, so nothing is sorted on the common path.
		let requiredSiblings = children.enumerated().map { index, child in
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
			// A property received only if available is still required when an `onlyIfAvailable` alias that a receiver
			// requires is bound from it: the child's tree requires it through the alias where a sibling declares its label.
			for property in receivedProperties.received
				where property != child.property
				&& property != child.property.asLazilyInstantiatedInstanceProperty
				&& !receivedProperties.onlyIfAvailable.contains(property)
			{
				recordRequiredProperty(property)
			}
			// The child's tree requires the property an `onlyIfAvailable` alias in it is bound from, where a sibling declares
			// its label. The child's own property is still being built inside its tree, so an alias there is `nil` and
			// requires nothing of it.
			for property in receivedProperties.requiredAliasFulfillingProperties.sorted() {
				if let namedChild = childBindingOnlyIfAvailableAlias(of: property),
				   namedChild.index != index,
				   mostDirectReceivedPropertyBySiblingIndex[namedChild.index].map({ (namedChild.directness, property) < ($0.directness, $0.property) }) ?? true
				{
					mostDirectReceivedPropertyBySiblingIndex[namedChild.index] = (property, namedChild.directness)
				}
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
	private static func validateChildrenDoNotRequireEachOther(
		inTreesRootedAt rootScopes: [Scope],
		cache: inout ReceivedPropertiesCache,
		validation: inout ChildrenRequiringEachOtherValidation,
	) throws {
		var treeErrors = [DependencyTreeGeneratorError]()
		for rootScope in rootScopes {
			// The scopes of this tree validated so far, each with the index here of the scope that instantiates it.
			var walkedScopes = [(scope: Scope, parentIndex: Int?)]()
			var scopesToValidate: [(scope: Scope, parentIndex: Int?)] = [(scope: rootScope, parentIndex: nil)]
			do {
				while let (scope, parentIndex) = scopesToValidate.popLast() {
					guard validation.validatedScopes.insert(scope).inserted else { continue }
					walkedScopes.append((scope: scope, parentIndex: parentIndex))
					let walkedScopeIndex = walkedScopes.count - 1
					if case let renamesContradictingOwnProperties = renamesContradictingOwnProperties(in: scope),
					   !renamesContradictingOwnProperties.isEmpty
					{
						// The walk in `validatePropertiesAreFulfillable` reports these for every scope it reaches, so only a
						// scope in the tree of a dependency a mock promotes, which that walk does not reach, reports them here.
						throw DependencyTreeGeneratorError.renamesContradictingOwnProperties(renamesContradictingOwnProperties)
					} else if let childrenRequiringEachOther = childrenRequiringEachOther(in: scope, cache: &cache) {
						throw childrenRequiringEachOther.error
					} else {
						let firstChildIndex = scopesToValidate.endIndex
						for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
							scopesToValidate.append((scope: childScope, parentIndex: walkedScopeIndex))
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
					validation.validatedScopes.remove(walkedScopes[index].scope)
					walkedScopeIndex = walkedScopes[index].parentIndex
				}
				treeErrors.append(error)
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: treeErrors) {
			throw error
		}
	}

	/// The renames of `scope`'s type, in declaration order, whose `fulfilledByDependencyNamed:` label the type also
	/// declares – as a property it instantiates or forwards – with a type their `ofType:` does not name. A rename
	/// refers to the property of that name on its own type. One whose `ofType:` names that property is built after it
	/// and assigned from it; one that names another type would be assigned from whichever declaration of its label is
	/// in scope where it is built, which depends on the order of the type's declarations. So `ofType:` must name the
	/// type's property exactly, or, when it is lazily instantiated, the instance it offers by value. A rename of
	/// another rename of the type is rejected before scopes are built (`RejectedRename`), and a rename of its own
	/// label refers to no other property.
	private static func renamesContradictingOwnProperties(
		in scope: Scope,
	) -> [DependencyTreeGeneratorError.RenameContradictingOwnProperty] {
		var ownDependencyByLabel = [String: Dependency]()
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				ownDependencyByLabel[dependency.property.label] = dependency
			case .aliased, .received:
				continue
			}
		}
		return scope.instantiable.dependencies.compactMap { dependency in
			guard case let .aliased(fulfillingProperty, _, _) = dependency.source,
			      let ownDependency = ownDependencyByLabel[fulfillingProperty.label],
			      !ownDependency.receivableProperties.contains(fulfillingProperty)
			else { return nil }
			return DependencyTreeGeneratorError.RenameContradictingOwnProperty(
				aliasProperty: dependency.property,
				fulfillingProperty: fulfillingProperty,
				declarationLocation: dependency.declarationLocation,
				ownProperty: ownDependency.property,
				ownPropertyDeclarationLocation: ownDependency.declarationLocation,
				renamingType: scope.instantiable.concreteInstantiable,
			)
		}
	}

	/// A scope whose tree `requiredReceiver` has searched for a receiver of a property.
	private struct SearchedScope: Hashable {
		let scope: ObjectIdentifier
		let property: Property
	}

	/// The first dependency, in declaration order and then child order, in the tree that
	/// `scope` creates that requires `property` from outside the tree — a dependency
	/// through which `collectReceivedProperties` finds the tree requires `property`,
	/// which lists `property` in `received` and not in `onlyIfAvailable`, or in
	/// `requiredAliasFulfillingProperties`: a dependency that requires an `onlyIfAvailable`
	/// alias bound from `property` (see `ScopeDeclarations.requiredOnlyIfAvailableAliases`).
	/// Such an alias counts: the tree is built after the property it is bound from (see
	/// `ScopeGenerator.orderedPropertiesToGenerate`), and the search goes on for the receiver of
	/// the alias's property beneath the scope, whose children's trees receive it: no alias of the
	/// scope renames another, since SafeDITool rejects that before it validates a tree that builds
	/// the scope. The tree is searched depth first with a stack of the scopes left to search, since
	/// it can be as deep as the module has types. `nil` when no dependency in the tree requires
	/// `property`, which `childrenRequiringEachOther` never asks about: the walk and the search
	/// decide what a scope provides by the same rules.
	private static func requiredReceiver(
		of property: Property,
		inTreeOf scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> RequiredReceiver? {
		var searchedScopes = Set<SearchedScope>()
		var scopesToSearch = [(
			scope: scope,
			property: property,
			requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias](),
		)]
		var receiver: RequiredReceiver?
		while receiver == nil, let (scope, property, requiredOnlyIfAvailableAliases) = scopesToSearch.popLast() {
			guard searchedScopes.insert(SearchedScope(scope: ObjectIdentifier(scope), property: property)).inserted else { continue }
			let declarations = ScopeDeclarations(scope: scope)
			/// The properties of the `onlyIfAvailable` aliases the scope declares that a receiver in a child's tree requires,
			/// as the walk finds them in `UnfinishedReceivedPropertiesWalk.finished`. Computed once, when the scope declares
			/// an `onlyIfAvailable` alias bound from the searched property.
			var computedRequiredAliasProperties: Set<Property>?
			func requiredAliasProperties() -> Set<Property> {
				if let computedRequiredAliasProperties {
					return computedRequiredAliasProperties
				} else {
					var childRequiredReceived = Set<Property>()
					var childRequiredAliasFulfillingProperties = Set<Property>()
					for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
						let childReceivedProperties = collectReceivedProperties(from: childScope, cache: &cache)
						childRequiredReceived.formUnion(childReceivedProperties.received.subtracting(childReceivedProperties.onlyIfAvailable))
						childRequiredAliasFulfillingProperties.formUnion(childReceivedProperties.requiredAliasFulfillingProperties)
					}
					let requiredAliasProperties = Set(declarations.requiredOnlyIfAvailableAliases(
						childRequiredReceived: childRequiredReceived,
						childRequiredAliasFulfillingProperties: childRequiredAliasFulfillingProperties,
					).map(\.property))
					computedRequiredAliasProperties = requiredAliasProperties
					return requiredAliasProperties
				}
			}
			// The property searched for beneath this scope: `property`, or the property of an `onlyIfAvailable` alias
			// bound from it that the scope declares and that is required, which the receiver then receives instead.
			var searchedProperty = property
			var searchedPropertyIsOwnAlias = false
			var requiredOnlyIfAvailableAliases = requiredOnlyIfAvailableAliases
			if let dependency = scope.instantiable.dependencies.first(where: { dependency in
				switch dependency.source {
				case let .received(onlyIfAvailable):
					!onlyIfAvailable && dependency.property == property
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					// An alias of a property the scope declares or forwards refers to that property, as
					// `collectReceivedProperties` has it.
					!onlyIfAvailable
						&& fulfillingProperty == property
						&& !declarations.propertiesToDeclare.contains(fulfillingProperty)
						&& !declarations.forwardedProperties.contains(fulfillingProperty)
				case .instantiated, .forwarded:
					false
				}
			}) {
				receiver = RequiredReceiver(dependency: dependency, requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases)
			} else if let requiredAlias = declarations.onlyIfAvailableAliases.first(where: { alias in
				// An alias bound from a property the scope declares or forwards is bound from that declaration.
				alias.fulfillingProperty.label == property.label
					&& ScopeGenerator.provides(property, aFormReadBy: alias.fulfillingProperty)
					&& !declarations.declaredLabels.contains(property.label)
					&& requiredAliasProperties().contains(alias.property)
			}) {
				// The receiver that requires the alias receives the alias's property, which the scope declares.
				requiredOnlyIfAvailableAliases.append(requiredAlias)
				searchedProperty = requiredAlias.property
				searchedPropertyIsOwnAlias = true
			}
			// A scope that declares `property` is not searched beneath: the trees of its children receive its own.
			if receiver == nil, searchedPropertyIsOwnAlias || !declarations.provides(searchedProperty) {
				// The scope searched next is the last one on the stack, so the first child goes last.
				let firstChildIndex = scopesToSearch.endIndex
				for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
					scopesToSearch.append((childScope, searchedProperty, requiredOnlyIfAvailableAliases))
				}
				scopesToSearch[firstChildIndex...].reverse()
			}
		}
		return receiver
	}

	/// What a scope declares, forwards, and aliases, as the walk of its received properties
	/// (`UnfinishedReceivedPropertiesWalk`) and the search of its tree (`requiredReceiver`) read it, with the rule by
	/// which both carry what its children's trees require through `onlyIfAvailable` aliases through it, which
	/// `ScopeGenerator` mirrors in `isRequiredByChild`, `requiredOnlyIfAvailableAliasProperties`, and
	/// `requiredAliasFulfillingProperties` to decide what each tree is built after.
	private struct ScopeDeclarations {
		init(scope: Scope) {
			propertiesToDeclare = scope.propertiesToDeclare
			forwardedProperties = scope.instantiable.forwardedReceivableProperties
			var onlyIfAvailableAliases = [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]()
			for case let (property, .aliased(fulfillingProperty, _, onlyIfAvailable: true)) in scope.instantiable.dependencies.lazy.map({ ($0.property, $0.source) }) {
				onlyIfAvailableAliases.append(.init(property: property, fulfillingProperty: fulfillingProperty))
			}
			self.onlyIfAvailableAliases = onlyIfAvailableAliases
			declaredLabels = Set(propertiesToDeclare.map(\.label)).union(forwardedProperties.map(\.label))
		}

		/// The properties the scope declares for its children: those it instantiates, whether or not a scope builds
		/// them, and the aliases it assigns (see `Scope.propertiesToDeclare`). A lazily instantiated property also
		/// declares the property that receives its instance by value.
		let propertiesToDeclare: Set<Property>
		/// The properties the scope forwards. A lazily instantiated one is also received by value.
		let forwardedProperties: Set<Property>
		/// The `onlyIfAvailable` aliases the scope declares, in declaration order.
		let onlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
		/// The labels of `propertiesToDeclare` and `forwardedProperties`: the scope's declaration of each is the nearest
		/// one for the scopes beneath it.
		let declaredLabels: Set<String>

		/// Whether the scope provides `property` to the scopes beneath it, as `ScopeGenerator.provides` has it: it
		/// declares or forwards the property or, for an optional property, its unwrapped form.
		func provides(_ property: Property) -> Bool {
			propertiesToDeclare.contains(property)
				|| forwardedProperties.contains(property)
				|| (property.typeDescription.isOptional
					&& (propertiesToDeclare.contains(property.asUnwrappedProperty) || forwardedProperties.contains(property.asUnwrappedProperty)))
		}

		/// Whether the scope declares or forwards a form of `property` that a receive of it only if available reads (see
		/// `Property.formsReadByOnlyIfAvailableReceive`), as `ScopeGenerator`'s
		/// `providesAFormReadByOnlyIfAvailableReceive(of:)` has it.
		func providesAFormReadByOnlyIfAvailableReceive(of property: Property) -> Bool {
			property.formsReadByOnlyIfAvailableReceive.contains { propertiesToDeclare.contains($0) || forwardedProperties.contains($0) }
		}

		/// Whether the scope provides `property`, which a call of another module's public mock in a tree beneath it passes
		/// (`ReceivedProperties.passedByPublicMockCalls`): the call is passed the scope's declaration, so nothing above
		/// the scope binds the property for it.
		func providesWhatPublicMockCallPasses(_ property: Property) -> Bool {
			propertiesToDeclare.contains(property.asUnwrappedProperty) || forwardedProperties.contains(property.asUnwrappedProperty)
		}

		/// Whether the scope provides `property`, which a call of another module's public mock in a tree beneath it builds
		/// when passed `nil` (`ReceivedProperties.builtWhenNilByPublicMockCalls`): the call is passed the scope's
		/// declaration, so no mock builds the property for it. A wrapper a called mock builds is passed by the instance
		/// it holds.
		func providesWhatPublicMockCallBuildsWhenNil(_ property: Property) -> Bool {
			let passedForm = (property.asLazilyInstantiatedInstanceProperty ?? property).asUnwrappedProperty
			return propertiesToDeclare.contains(passedForm) || forwardedProperties.contains(passedForm)
		}

		/// The `onlyIfAvailable` aliases the scope declares that a receiver in a child's tree requires, given what the
		/// children's trees require: `childRequiredReceived`, the properties they require, and
		/// `childRequiredAliasFulfillingProperties`, those they require through `onlyIfAvailable` aliases, which an alias
		/// here provides where it has their label and a form they read.
		func requiredOnlyIfAvailableAliases(
			childRequiredReceived: Set<Property>,
			childRequiredAliasFulfillingProperties: Set<Property>,
		) -> [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias] {
			onlyIfAvailableAliases.filter { alias in
				childRequiredReceived.contains(alias.property)
					|| childRequiredAliasFulfillingProperties.contains { $0.label == alias.property.label && ScopeGenerator.provides(alias.property, aFormReadBy: $0) }
			}
		}

		/// The properties the scope's tree requires through `onlyIfAvailable` aliases of the scopes enclosing it, given
		/// what its children's trees require (see `requiredOnlyIfAvailableAliases`): those of the children's trees and the
		/// fulfilling properties of the scope's own required aliases, without those whose label the scope declares or
		/// forwards, whose nearest declaration is the scope's.
		func requiredAliasFulfillingProperties(
			childRequiredReceived: Set<Property>,
			childRequiredAliasFulfillingProperties: Set<Property>,
		) -> Set<Property> {
			var requiredAliasFulfillingProperties = childRequiredAliasFulfillingProperties
			for alias in requiredOnlyIfAvailableAliases(
				childRequiredReceived: childRequiredReceived,
				childRequiredAliasFulfillingProperties: childRequiredAliasFulfillingProperties,
			) {
				requiredAliasFulfillingProperties.insert(alias.fulfillingProperty)
			}
			return requiredAliasFulfillingProperties.filter { !declaredLabels.contains($0.label) }
		}
	}

	/// Judges a detected cycle, not the property that closes it, and throws the appropriate error, or returns silently if
	/// the cycle is valid. Called from both `validatePropertiesAreFulfillable` (production graph, and a mock root whose
	/// children require one another) and `validateMockRootScopeForCycles` (mock graph after `@Received` promotion).
	///
	/// Rejected:
	/// - A cycle closed by a receive (`closingReceive` is not `nil`), whatever its hops: the property received is still
	///   being built → `.constantDependencyCycleDetected` for a constant, `.receivedInstantiatorDependencyCycleDetected`
	///   otherwise.
	/// - A cycle closed by an instantiation along which no hop is deferred → `.constantDependencyCycleDetected`, naming
	///   the hops.
	///
	/// Accepted (returns without throwing): a cycle closed by an instantiation, of any kind, along which some hop is an
	/// instantiator (`Instantiator`, `ErasedInstantiator`, or a `Sendable` twin), wherever the tree enters it. A lazily
	/// instantiated hop is never deferred: validation holds it as the constant it stands for. Generation closes such a
	/// cycle at the same property, which calls the builder function of the declaration it repeats; pruning via
	/// `cycleEdges` is what breaks the self-referencing config-struct shape so the generated mocks typecheck.
	/// - Parameters:
	///   - propertiesInCycle: The cycle as validation sees it: the closing property, then the instantiation stack,
	///     innermost first, up to and including the entry it repeats (with the receives between, in the walk of
	///     received properties).
	///   - declaredProperty: The property of the dependency that closes the cycle, as declared at
	///     `declarationLocation`: the property instantiated, or the property received – the alias for an alias.
	private func throwIfInvalidCycle(
		propertiesInCycle: [Property],
		property: Property,
		declaredProperty: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		directParent: TypeDescription,
		closingReceive: CycleClosingReceive?,
		lazilyInstantiatedProperties: [Property],
	) throws {
		if closingReceive != nil || propertiesInCycle.allSatisfy(\.propertyType.isConstant) {
			throw invalidCycleError(
				propertiesInCycle: propertiesInCycle,
				property: property,
				declaredProperty: declaredProperty,
				declarationLocation: declarationLocation,
				directParent: directParent,
				closingReceive: closingReceive,
				lazilyInstantiatedProperties: lazilyInstantiatedProperties,
			)
		}
	}

	/// The error `throwIfInvalidCycle` throws for a cycle through `property` that no instantiator defers or that a receive
	/// closes: a cycle naming its hops when an instantiation closes it, and otherwise a received constant cycle when
	/// `property` is constant and a received-`Instantiator` cycle when it is not.
	/// - Parameters:
	///   - propertiesInCycle: See `throwIfInvalidCycle`.
	///   - declaredProperty: See `throwIfInvalidCycle`.
	///   - closingReceive: The receive that closes the cycle, or `nil` when an instantiation closes it.
	private func invalidCycleError(
		propertiesInCycle: [Property],
		property: Property,
		declaredProperty: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		directParent: TypeDescription,
		closingReceive: CycleClosingReceive?,
		lazilyInstantiatedProperties: [Property],
	) -> DependencyTreeGeneratorError {
		let cycle = DependencyTreeGeneratorError.DependencyCycle(
			declarationLocation: declarationLocation,
			members: propertiesInCycle.map(\.typeDescription).map { typeDescription in
				DependencyTreeGeneratorError.DependencyCycle.Member(
					typeDescription: typeDescription,
					declarationLocation: typeDescriptionToFulfillingInstantiableMap[typeDescription.asInstantiatedType]?.declarationLocation,
				)
			},
			lazilyInstantiatedProperties: lazilyInstantiatedProperties,
		)
		if closingReceive == nil {
			// The walk lists the closing property first, then the stack up to the entry it repeats, which is the closing
			// property again: the hops, outermost first, are the stack's entries.
			return .constantDependencyCycleDetected(cycle, closingDependency: .instantiated(hops: propertiesInCycle.reversed().dropLast()))
		} else if property.propertyType.isConstant {
			return .constantDependencyCycleDetected(cycle, closingDependency: .received(declaredProperty, receiver: directParent))
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

	/// The index on `propertyStack` of the entry a dependency of `scope` closes a cycle on, or `nil` when it closes none. A cycle repeats a declaration: an instantiation repeats the entry of the same property, as
	/// cycle validation sees it, built for the same concrete type, so two declarations of one label and type that
	/// `fulfilledByType:` resolves to different types are two declarations. A receive repeats the entry of the property it
	/// receives, in any of `receivedForms`, only when that entry's declaration is the nearest declaration of the label: one
	/// nearer – a declaration that closes a cycle itself, or one built beside the tree being built – is what the generated
	/// code passes, so it fulfills the receive.
	/// - Parameters:
	///   - fulfillingProperty: The property `dependency` instantiates, or the property it receives: the fulfilling
	///     property of an alias.
	///   - receivedForms: The forms of `fulfillingProperty`, as cycle validation sees them, that a stack entry matches,
	///     the first the property itself.
	///   - closesByReceive: Whether `dependency` closes a cycle by receiving (see `closingReceive(of:in:)`).
	///   - propertyStack: The properties of `scope` and of the scopes it is built inside, innermost first, as cycle
	///     validation sees them.
	///   - concreteTypeStack: The concrete types of those scopes, beside `propertyStack`.
	///   - nearestDeclaration: The properties the nearest declarations of a label above `scope` declare, as cycle
	///     validation sees them – one, but for a mock root's promoted forms of one label – with how many scopes the declaring
	///     scope is built inside, or `nil` when no scope above declares the label. The entry at index `i` of `propertyStack`
	///     is declared by a scope built inside `propertyStack.count - 1 - i` scopes.
	private static func indexOfEntryClosedOn(
		by fulfillingProperty: Property,
		of scope: Scope,
		receivedForms: [Property],
		closesByReceive: Bool,
		propertyStack: [Property],
		concreteTypeStack: [TypeDescription],
		nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
	) -> Int? {
		if closesByReceive {
			guard let index = propertyStack.firstIndex(where: receivedForms.contains),
			      !isFulfilledByNearerDeclaration(receivedForms, thanEntryAt: index, of: propertyStack, nearestDeclaration: nearestDeclaration)
			else { return nil }
			return index
		} else {
			// Nearly every dependency repeats no entry, so the type its scope builds is found only for one that might. A
			// dependency with no built scope matches no entry: no input has one beside an entry of its property, since an
			// instantiated type nothing fulfills is rejected before scopes exist, and a dependency a mock cannot build shares
			// no property with an entry built from a scope.
			guard propertyStack.contains(receivedForms[0]) else { return nil }
			let builtType = scope.propertiesToGenerate.first { $0.property == fulfillingProperty }?.builtScope?.instantiable.concreteInstantiable
			return propertyStack.indices.first { propertyStack[$0] == receivedForms[0] && concreteTypeStack[$0] == builtType }
		}
	}

	/// Whether a receive of `receivedForms`, the first the property received, as cycle validation sees them, resolves to a
	/// declaration nearer than the one the entry at `index` of `stack` is built for: the nearest declaration of the label
	/// declares one of `receivedForms` and is declared by a scope built inside more scopes than the one that declares the
	/// entry. See `indexOfEntryClosedOn`.
	private static func isFulfilledByNearerDeclaration(
		_ receivedForms: [Property],
		thanEntryAt index: Int,
		of stack: [Property],
		nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
	) -> Bool {
		nearestDeclaration(receivedForms[0].label).map { $0.depth > stack.count - 1 - index && $0.properties.contains(where: receivedForms.contains) } ?? false
	}

	/// What a scope's subtree receives from its ancestors.
	private struct ReceivedProperties {
		/// Every property the subtree needs from an ancestor.
		let received: Set<Property>
		/// Those of `received` that every receiver in the subtree receives only if available.
		/// A property some receiver requires is not in `onlyIfAvailable`.
		let onlyIfAvailable: Set<Property>
		/// The properties receivers in the subtree require through the `onlyIfAvailable` aliases declared in it, whose
		/// label no scope in the subtree declares: the nearest declaration of each is above the subtree, which is built
		/// after it where a scope builds both (see `ScopeDeclarations.requiredAliasFulfillingProperties`).
		let requiredAliasFulfillingProperties: Set<Property>
		/// The properties the calls of other modules' public mocks in the subtree, and in the trees of the fills its calls
		/// pass, receive only if available and pass, which are in none of the other sets: a mock that is itself public takes
		/// them as parameters (see `ScopeGenerator.receivedOnlyByPublicMockCallsLeftOut`).
		let passedByPublicMockCalls: Set<Property>
		/// Those of `passedByPublicMockCalls` some called mock builds when passed `nil`, which a mock that can build one
		/// builds once and passes to every call, as the inline mock promotes it (M8.8b).
		let builtWhenNilByPublicMockCalls: Set<Property>
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
	/// - Returns: The subtree's received properties. Its `requiredAliasFulfillingProperties` mirror
	///   ScopeGenerator's.
	private static func collectReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> ReceivedProperties {
		walkReceivedProperties(from: scope, cache: &cache).receivedProperties
	}

	/// Walks the tree `scope` creates, children before the scopes that create them, and the trees of the fills a call of
	/// another module's public mock passes after its children, with a stack of the scopes whose walk is unfinished, since
	/// a tree can be as deep as the module has types.
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
			} else if walks[walkIndex].nextFillIndex < walks[walkIndex].fills.count {
				let fillScope = walks[walkIndex].fills[walks[walkIndex].nextFillIndex].scope
				walks[walkIndex].nextFillIndex += 1
				switch startWalkingReceivedProperties(from: fillScope, cache: &cache) {
				case let .walked(walkedFill):
					walks[walkIndex].record(walkedFill)
				case let .unfinished(fillWalk):
					walks.append(fillWalk)
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
				receivedProperties: ReceivedProperties(received: [], onlyIfAvailable: [], requiredAliasFulfillingProperties: [], passedByPublicMockCalls: [], builtWhenNilByPublicMockCalls: []),
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
			// A seam call's fills, in a production tree, call no public mock, so only a public mock call's are walked.
			var fills = [(scope: Scope, fieldForms: Set<Property>)]()
			if scope.publicMockCall != nil {
				for case let .fill(hole, fillScope) in scope.holeArguments {
					// A public mock takes no deferred parameter, so its fill binds every field.
					fills.append((fillScope, ScopeGenerator.fieldForms(of: hole, boundLabels: Set(hole.stages.joined().map(\.property.label)))))
				}
			}
			self.fills = fills
		}

		let scope: Scope
		let walkDepth: Int
		let propertiesToGenerate: [Scope.PropertyToGenerate]
		/// The index in `propertiesToGenerate` of the next property whose tree to walk.
		var nextPropertyIndex = 0
		/// The fills of the builders this scope's call of another module's public mock fills, each with the properties
		/// it declares (`ScopeGenerator.fieldForms(of:)`), whose trees are walked after every child's.
		let fills: [(scope: Scope, fieldForms: Set<Property>)]
		/// The index in `fills` of the next fill whose tree to walk.
		var nextFillIndex = 0

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
		var passedByPublicMockCalls = Set<Property>()
		var builtWhenNilByPublicMockCalls = Set<Property>()
		// Properties the instantiated children's subtrees require, including those this scope declares.
		var childRequiredReceived = Set<Property>()
		// The properties the instantiated children's subtrees require through `onlyIfAvailable` aliases.
		var childRequiredAliasFulfillingProperties = Set<Property>()
		var shallowestUnfinishedWalkDepth: Int?

		/// Collects from an instantiated child — mirrors ScopeGenerator's receivedProperties aggregation.
		/// Aliases are handled in `finished(cache:)`'s own-dependency loop: alias children's receivedProperties
		/// = [fulfillingProperty], but the own-dependency union unconditionally adds the same
		/// fulfillingProperty, making the child-path subtraction/filter redundant.
		mutating func record(_ walkedChild: WalkedReceivedProperties) {
			shallowestUnfinishedWalkDepth = [shallowestUnfinishedWalkDepth, walkedChild.shallowestUnfinishedWalkDepth].compactMap(\.self).min()
			// Fills are walked after every child, so the tree walked last is a fill's once one is walked.
			guard nextFillIndex == 0 else {
				recordFill(walkedChild, fieldForms: fills[nextFillIndex - 1].fieldForms)
				return
			}
			let childReceived = walkedChild.receivedProperties.received
			let childOnlyIfAvailable = walkedChild.receivedProperties.onlyIfAvailable
			childRequiredReceived.formUnion(childReceived.subtracting(childOnlyIfAvailable))
			childRequiredAliasFulfillingProperties.formUnion(walkedChild.receivedProperties.requiredAliasFulfillingProperties)
			// A forwarded `x: X` fulfills an `x: X?` beneath it, as a declared one does. A receive only if available reads
			// any form of its label this scope declares that it reads, as `ScopeGenerator` has it.
			let childReceivedFromAncestors = childReceived
				.subtracting(propertiesToDeclare)
				.subtracting(forwardedProperties)
				.filter { property in
					(
						!property.typeDescription.isOptional
							|| (!propertiesToDeclare.contains(property.asUnwrappedProperty) && !forwardedProperties.contains(property.asUnwrappedProperty))
					) && (!childOnlyIfAvailable.contains(property) || !declarations.providesAFormReadByOnlyIfAvailableReceive(of: property))
				}
			received.formUnion(childReceivedFromAncestors)
			required.formUnion(childReceivedFromAncestors.subtracting(childOnlyIfAvailable))
			for property in walkedChild.receivedProperties.passedByPublicMockCalls where !declarations.providesWhatPublicMockCallPasses(property) {
				passedByPublicMockCalls.insert(property)
			}
			for property in walkedChild.receivedProperties.builtWhenNilByPublicMockCalls where !declarations.providesWhatPublicMockCallBuildsWhenNil(property) {
				builtWhenNilByPublicMockCalls.insert(property)
			}
			// Subtract by any form a receive only if available reads — a declared `x: X` satisfies onlyIfAvailable `x: X?`.
			onlyIfAvailable.formUnion(
				childOnlyIfAvailable.filter { property in
					!declarations.providesAFormReadByOnlyIfAvailableReceive(of: property)
				},
			)
		}

		/// Collects from the tree of a fill this scope's call passes what the calls of other modules' public mocks in it pass,
		/// as `ScopeGenerator`'s fill, which declares `fieldForms`, collects it: a mock binds what it passes them, as it binds
		/// what such a call outside a fill passes. Nothing else the tree receives reaches this scope: the scope struct
		/// carries the fields, and the call passes the fills of the builders inside it that it fills
		/// (`holesFilled(byCallsOf:in:)`).
		private mutating func recordFill(_ walkedFill: WalkedReceivedProperties, fieldForms: Set<Property>) {
			func isProvidedByFields(_ property: Property) -> Bool {
				fieldForms.contains(property) || fieldForms.contains(property.asUnwrappedProperty)
			}
			for property in walkedFill.receivedProperties.passedByPublicMockCalls where !isProvidedByFields(property) {
				passedByPublicMockCalls.insert(property)
			}
			// A wrapper a called mock builds is passed by the instance it holds.
			for property in walkedFill.receivedProperties.builtWhenNilByPublicMockCalls
				where !isProvidedByFields(property.asLazilyInstantiatedInstanceProperty ?? property)
			{
				builtWhenNilByPublicMockCalls.insert(property)
			}
		}

		/// Ends the walk once every child's tree and every fill's is walked, recording its result in `cache`.
		mutating func finished(cache: inout ReceivedPropertiesCache) -> WalkedReceivedProperties {
			// This scope's own received/aliased dependencies.
			// Store exact properties (not unwrapped) in onlyIfAvailable. This avoids
			// collisions between a required `x: X` and an onlyIfAvailable `x: X?` —
			// they are distinct Properties. The subtraction in `record(_:)` uses unwrapped comparison
			// to correctly subtract when a declared property satisfies an optional one.
			// A leaf that calls another module's public mock passes a dependency it receives only if available where the
			// tree provides it, and `nil` elsewhere, so the mock binds no parameter or override for it: the public mock
			// builds what the call does not pass (see `Scope.publicMockCall`).
			if let publicMockCall = scope.publicMockCall {
				for parameter in publicMockCall.passedParameters where parameter.dependency.source == .received(onlyIfAvailable: true) {
					passedByPublicMockCalls.insert(parameter.dependency.property)
					if parameter.isBuiltWhenNil {
						// A lazily instantiated dependency is built as the wrapper the called mock builds, as the inline mock
						// promotes it, and the call is passed its instance.
						builtWhenNilByPublicMockCalls.insert(parameter.builtWrapper ?? parameter.dependency.property)
					}
				}
			}
			for dependency in scope.instantiable.dependencies where scope.publicMockCall == nil || dependency.source != .received(onlyIfAvailable: true) {
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
					// binding — it's not a received dependency that needs promoting. An
					// `onlyIfAvailable` alias binds a local of any form it reads.
					guard isOnlyIfAvailable
						? !declarations.providesAFormReadByOnlyIfAvailableReceive(of: fulfillingProperty)
						: !propertiesToDeclare.contains(fulfillingProperty) && !forwardedProperties.contains(fulfillingProperty)
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
			// What this scope's tree requires through `onlyIfAvailable` aliases of the scopes enclosing it, through any chain
			// of aliases, given what the children's trees require. No scope this walk meets calls a seam: only
			// `createSeamScopeMapping` creates a `seamCall`, and validation walks every seam's tree inline, whose receivers
			// require what `ScopeGenerator` has a seam call require through `SeamCall.requiredThroughAliasProperties`.
			let requiredAliasFulfillingProperties = declarations.requiredAliasFulfillingProperties(
				childRequiredReceived: childRequiredReceived,
				childRequiredAliasFulfillingProperties: childRequiredAliasFulfillingProperties,
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
				requiredAliasFulfillingProperties: requiredAliasFulfillingProperties,
				passedByPublicMockCalls: passedByPublicMockCalls,
				builtWhenNilByPublicMockCalls: builtWhenNilByPublicMockCalls,
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
	/// - Parameter unfulfilledInstantiationsAreHoles: Whether the fills are a public mock's, whose tree is built with holes,
	///   so a type a fill's tree instantiates that no declaration the module sees fulfills is a place of the mock's own. An
	///   internal mock's fill would read a value nothing binds there, so it does not fill the place.
	private func holesFilled(
		byCallsOf publicMockCalls: [TypeDescription: PublicMockCall],
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
		unfulfilledInstantiationsAreHoles: Bool,
	) -> [TypeDescription: [SeamSignature.Hole]] {
		guard let emittingModule = emittingModuleToCheck else { return [:] }
		struct Candidate {
			let calledType: TypeDescription
			let hole: SeamSignature.Hole
			/// What the fill's tree receives that the scope struct does not carry.
			let receivedBesideFields: Set<Property>
		}
		var receivedPropertiesCache = ReceivedPropertiesCache()
		var candidates = [Candidate]()
		for calledType in publicMockCalls.keys.sorted() {
			for hole in publicMockCalls[calledType]?.holes ?? [] {
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
				for field in hole.stages.joined() {
					for form in [field.property] + [field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding].compactMap(\.self) {
						fieldForms.insert(form)
						fieldForms.insert(form.asOptionalProperty)
					}
				}
				candidates.append(Candidate(
					calledType: calledType,
					hole: hole,
					receivedBesideFields: Self.collectReceivedProperties(from: fulfillingScope, cache: &receivedPropertiesCache).received.subtracting(fieldForms),
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
		return Dictionary(grouping: filled, by: \.calledType).mapValues { $0.map(\.hole) }
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

	/// A collection of `@Instantiable`-decorated types that are at the roots of their respective dependency trees.
	private lazy var rootInstantiables: Set<TypeDescription> = Set(
		typeDescriptionToFulfillingInstantiableMap
			.values
			.filter(\.isRoot)
			.map(\.concreteInstantiable),
	)

	/// A collection of `@Instantiable`-decorated types that are instantiated by at least one other
	/// `@Instantiable`-decorated type or do not explicitly receive dependencies, including those reached only beneath
	/// a seam another module declares.
	private lazy var reachableTypeDescriptions: Set<TypeDescription> = typesReachable(fromRoots: validatedRootInstantiables)

	/// The types whose lack of a production `@Instantiable` declaration is an error in a module that holds or calls a
	/// seam: those the roots' trees reach outside every seam's tree, the fills this module generates for the holes of the
	/// foreign seams they call included, and those a seam's tree reaches through a dependency that cannot be a hole
	/// (`canBeHole`), since only hand-written code could build its type.
	private func typesReachableOutsideSeamTrees() throws -> Set<TypeDescription> {
		let foreignSeamRoots = try foreignSeamRoots.get()
		/// The seam `typeDescription` is, when its tree is another tree's leaf: one with a signature, generated here or
		/// in another module.
		func isSeamWithTree(_ instantiable: Instantiable) -> Bool {
			guard instantiable.generatesDependencyTree else { return false }
			return generatedSeamTypes.contains(instantiable.concreteInstantiable)
				|| (foreignSeamRoots[instantiable.concreteInstantiable] ?? nil) != nil
		}
		/// The types a walk from `roots` reaches without entering a seam with a tree other than the roots, entering the
		/// fills this module generates for the holes of each foreign seam it reaches.
		func typesReached(from roots: Set<TypeDescription>) -> Set<TypeDescription> {
			var reached = Set<TypeDescription>()
			var typesToVisit = Array(roots)
			while let typeDescription = typesToVisit.popLast() {
				guard reached.insert(typeDescription).inserted,
				      let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription]
				else { continue }
				if !roots.contains(typeDescription), isSeamWithTree(instantiable) {
					for hole in (foreignSeamRoots[instantiable.concreteInstantiable] ?? nil)?.signature.holes ?? [] {
						if let fulfillingInstantiable = Self.fulfillingInstantiable(of: hole, in: typeDescriptionToFulfillingInstantiableMap) {
							typesToVisit.append(fulfillingInstantiable.concreteInstantiable)
						}
					}
					continue
				}
				for dependency in instantiable.dependencies where dependency.isInstantiated {
					typesToVisit.append(dependency.asInstantiatedType)
				}
			}
			return reached
		}
		var typesToReport = typesReached(from: rootInstantiables)
		// A seam whose module SafeDI does not know cannot take a builder: what its callers see is unknown.
		if let emittingModule, emittingModule.identity.moduleName == nil {
			var holes = [DependencyTreeGeneratorError.HoleInSeamOfUnnamedModule]()
			var reportedLocations = Set<String>()
			for seamType in generatedSeamTypes.sorted() {
				guard let seam = typeDescriptionToFulfillingInstantiableMap[seamType] else { continue }
				for typeDescription in typesReached(from: [seamType]).sorted() {
					guard let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription] else { continue }
					for dependency in instantiable.dependencies where dependency.isInstantiated
						&& Self.canBeHole(dependency)
						&& typeDescriptionToFulfillingInstantiableMap[dependency.asInstantiatedType]?.mockOnly != false
						&& reportedLocations.insert(dependency.declarationLocation.map { "\($0.filePath):\($0.line):\($0.column)" } ?? "\(typeDescription.asSource).\(dependency.property.label)").inserted
					{
						holes.append(.init(seam: seam.concreteInstantiable, owner: instantiable.concreteInstantiable, dependency: dependency))
					}
				}
			}
			if !holes.isEmpty {
				throw DependencyTreeGeneratorError.holesInSeamsOfUnnamedModule(holes)
			}
		}
		for seamType in generatedSeamTypes {
			for typeDescription in typesReached(from: [seamType]) where typeDescriptionToFulfillingInstantiableMap[typeDescription]?.mockOnly != false {
				// Only hand-written code could build a type that cannot be a hole.
				if typeDescriptionToFulfillingInstantiableMap.values.contains(where: { instantiable in
					instantiable.dependencies.contains { $0.isInstantiated && $0.asInstantiatedType == typeDescription && !Self.canBeHole($0) }
				}) {
					typesToReport.insert(typeDescription)
				}
			}
		}
		return typesToReport
	}

	/// The types the trees rooted at `roots` reach, beneath the seams other modules declare included.
	private func typesReachable(fromRoots roots: Set<TypeDescription>) -> Set<TypeDescription> {
		var reachableTypeDescriptions = Set<TypeDescription>()
		// The types reached whose instantiated types are not yet recorded. A worklist rather than recursion,
		// since a chain of types can be as long as the module has types.
		var typeDescriptionsToVisit = Array(roots)
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
	}

	private func createTypeDescriptionToScopeMapping() throws -> [TypeDescription: Scope] {
		// Create the mapping.
		let typeDescriptionToScopeMap: [TypeDescription: Scope] = reachableTypeDescriptions
			.reduce(into: [TypeDescription: Scope]()) { partialResult, typeDescription in
				if let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription],
				   partialResult[instantiable.concreteInstantiable] == nil
				{
					let scope = Scope(instantiable: instantiable, builtInlineSeamComment: builtInlineSeamComment(for: instantiable))
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
			/// The property whose instance a read of `property` reads: the property a renaming of this type renames, or
			/// `property` itself. No renaming of a type renames another (SafeDITool rejects that before it validates a
			/// tree that builds the scope).
			func propertyRead(by property: Property) -> Property {
				renamedInstanceProperties[property] ?? property
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
			// The instances of the lazily instantiated properties this type instantiates, which it always creates.
			let instantiatedLazilyInstantiatedInstanceProperties = Set(
				instantiable.dependencies.filter(\.isInstantiated).compactMap(\.lazilyInstantiatedInstanceProperty),
			)
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
					// An `onlyIfAvailable` alias is the exception when it renames the instance of a lazily instantiated
					// property this type instantiates: `orderedPropertiesToGenerate` builds an alias after the sibling
					// that fulfills it, and validation rejects a tree that needs the alias first, so it always reads it.
					if fulfillingProperty.propertyType.isConstant,
					   !onlyIfAvailable || instantiatedLazilyInstantiatedInstanceProperties.contains(fulfillingProperty)
					{
						recordRead(of: fulfillingProperty, by: dependency, receivedLabel: fulfillingProperty.label)
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
					forwardedProperties.asForwardedPropertiesTypeDescription,
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
		// its own properties. A seam this module generates receives, as the parameters of its generated initializer,
		// every property its tree receives from outside it, so its tree is validated with those receivable at its
		// root, a required wrapper with its instance, as a declaration above the seam would be. Every one stays in
		// scope beneath a declaration of its label, as a declaration above the seam would, so a receive beneath such a
		// declaration is reported hidden from the seam's chain, whatever its optionality and whatever a caller holds:
		// the generated initializer passes each dependency by label, and is generated before any caller is known.
		var rootScopes = validatedRootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] }.map { scope in
			var receivedFromOutside = Set<Property>()
			if generatedSeamTypes.contains(scope.instantiable.concreteInstantiable) {
				for property in Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received {
					receivedFromOutside.insert(property)
					if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
						receivedFromOutside.insert(instanceProperty)
					}
				}
			}
			return ValidatedRootScope(
				scope: scope,
				boundProperties: [],
				isMock: false,
				receivedFromOutside: receivedFromOutside,
			)
		}
		// When checking cycles only (mock validation), also validate non-root types
		// that have generateMock enabled — they bypass root entry points. Each one's
		// mock binds every property its tree receives from above it.
		if cyclesOnly {
			let rootInstantiableSet = Set(rootInstantiables)
			rootScopes += Set(typeDescriptionToScopeMap.values)
				.filter { scope in
					scope.instantiable.generatesMock && !rootInstantiableSet.contains(scope.instantiable.concreteInstantiable)
				}
				// A type whose hand-written mock is not passed some of its dependencies has two scopes, which only
				// identity tells apart: the full one first, then the one its hand-written mock builds.
				.sorted { ($0.instantiable.concreteInstantiable, $0.dependenciesLeftOut.count) < ($1.instantiable.concreteInstantiable, $1.dependenciesLeftOut.count) }
				.map { scope in ValidatedRootScope(scope: scope, boundProperties: Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received, isMock: true) }
		}
		try validatePropertiesAreFulfillable(
			onRootScopes: rootScopes,
			additionalMockRootScopes: additionalMockRootScopes
				.sorted { $0.instantiable.concreteInstantiable < $1.instantiable.concreteInstantiable }
				.map { scope in ValidatedRootScope(scope: scope, boundProperties: Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received, isMock: !scope.instantiable.isRoot) },
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: cyclesOnly,
		)
	}

	/// Walks, for cycles only, the tree of each foreign seam whose initializer takes a builder, from the seam's root, as
	/// the seam's own module validates it where it sees the fulfilling declarations: this module's validated scopes
	/// build the seam inline, with the fills this module generates, but a tree rooted elsewhere reaches a fill with
	/// another stack, and can close a cycle earlier, on a lazy property above the seam, than the seam's own validation
	/// does. A fill is generated with the seam's stack, so a constant repeat the seam's walk rejects is rejected here,
	/// with the diagnostic that walk reports. A seam's tree is walked whether or not this module fills each of its holes:
	/// a hole this module does not fill has no scope, and the walk stops there. A seam whose builder another seam passes
	/// up is walked too, so every seam on the chain from the outermost one this module fills down to the one whose tree
	/// holds the hole is walked from its own root.
	private func validateCyclesFromRootsOfForeignSeamsWithHoles(
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
		receivedPropertiesCache: inout ReceivedPropertiesCache,
	) throws {
		let seamTypesWithHoles = try foreignSeamTypesWithHoles()
		guard !seamTypesWithHoles.isEmpty else { return }
		let rootScopes = seamTypesWithHoles.compactMap { typeDescriptionToScopeMap[$0] }.map { scope in
			var receivedFromOutside = Set<Property>()
			for property in Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received {
				receivedFromOutside.insert(property)
				if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
					receivedFromOutside.insert(instanceProperty)
				}
			}
			return ValidatedRootScope(scope: scope, boundProperties: [], isMock: false, receivedFromOutside: receivedFromOutside)
		}
		try validatePropertiesAreFulfillable(onRootScopes: rootScopes, typeDescriptionToScopeMap: typeDescriptionToScopeMap, cyclesOnly: true)
	}

	/// The foreign seams whose initializers take a builder, in type order.
	private func foreignSeamTypesWithHoles() throws -> [TypeDescription] {
		guard !seams.foreignSeams.isEmpty else { return [] }
		let foreignSeamRoots = try foreignSeamRoots.get()
		return foreignSeamRoots.keys.filter { (foreignSeamRoots[$0] ?? nil)?.signature.holes.isEmpty == false }.sorted()
	}

	/// The generators, whose code is never started, of the tree of each foreign seam whose initializer takes a builder,
	/// from the seam's root over the validated scopes, which build the seam inline with the fills this module generates,
	/// in type order. `validateCycleLabelsArePassable` judges them: inline, the builder function a lazy cycle in the
	/// seam's tree closes on takes a label as a parameter whose forms include those a fill inside it receives, while the
	/// seam's own module, which cannot see the fill, judged the parameter without them. So a fill that receives the label
	/// in a form no one parameter carries together with the forms the seam's tree receives is rejected as its inline build
	/// is, with the same error. A hole this module does not fill has no scope, and its tree ends there.
	private func inlineTreesOfForeignSeamsWithHoles(in typeDescriptionToScopeMap: [TypeDescription: Scope]) throws -> [ScopeGenerator] {
		try foreignSeamTypesWithHoles().compactMap { typeDescriptionToScopeMap[$0] }.map { scope in
			try scope.createScopeGenerator(
				for: nil,
				lazilyInstantiatedInstanceProperties: [],
				erasedToConcreteExistential: false,
				startsCodeGeneration: false,
				validatesForwardedProperties: false,
				declaredTypeNames: declaredTypeNames,
			)
		}
	}

	/// An alias that a receive of its property resolves to: the nearest scope above the receiver that provides the
	/// property declares it with `@Received(fulfilledByDependencyNamed:ofType:)`.
	private struct ReceivableAlias {
		let fulfillingProperty: Property
		let onlyIfAvailable: Bool
		/// The `onlyIfAvailable` aliases from which an `onlyIfAvailable` alias is created in turn, in order: the alias
		/// of `fulfillingProperty` that the alias's assignment refers to, when it is `onlyIfAvailable` too – the one a
		/// receive of it resolves to where the alias is declared, declared by an enclosing scope, when the alias's own
		/// scope declares no property of that name and type (or its non-optional form); no alias of a scope renames
		/// another, since SafeDITool rejects that before it validates a tree that builds the scope – then the alias of
		/// that alias's fulfilling property, and so on. An `onlyIfAvailable` alias is created only where the alias it
		/// renames is, so a receive that requires this alias requires each of them. Empty for a required alias, whose
		/// declaring scope requires its fulfilling property itself (`Scope.requiredReceivedProperties`).
		let fulfillingOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
		/// What the last of `fulfillingOnlyIfAvailableAliases` – or the alias itself when there are none – is bound
		/// from where it is declared (see `AliasBinding`), or `nil` for an `onlyIfAvailable` alias bound to `nil`, which a
		/// required receive of it is passed. Always set for a required alias.
		let binding: AliasBinding?

		/// The declaration an alias is bound from: the nearest declaration of its fulfilling property's label where the
		/// alias is declared, which provides a form the alias reads and is not being built there.
		enum AliasBinding {
			/// A property a scope on the path instantiates or declares by an alias, which a required receive of the alias
			/// needs built before it.
			case built
			/// A property the tree is handed: one a scope on the path is forwarded, or that a seam's or a mock's root
			/// binds.
			case handed
		}

		/// The type that declares the alias.
		let declaringType: TypeDescription
		/// The type that declares the alias the property the alias is ultimately created from fulfills: the last of
		/// `fulfillingOnlyIfAvailableAliases`, or `declaringType` when there are none.
		let lastAliasDeclaringType: TypeDescription
		/// The property of the scope of `lastAliasDeclaringType`, followed by the properties of the scopes it is built
		/// inside, innermost first. Empty when a root is that scope.
		let lastAliasDeclaringInstantiationStack: [Property]
	}

	/// The scope at the root of a tree that `validatePropertiesAreFulfillable` walks.
	private struct ValidatedRootScope {
		let scope: Scope
		/// The received properties the root's mock binds — as children it promotes, `mock()`
		/// parameters, or `SafeDIOverrides` entries — which enclose its whole tree. Empty for a
		/// root of the dependency tree, which receives nothing.
		let boundProperties: Set<Property>
		/// Whether the tree is validated as the tree of a mock that promotes what its tree receives from above it: the
		/// mock of a type that is not a root of the dependency tree. A root receives nothing, so a mock of it promotes
		/// nothing and builds its production tree, and the validation of mocks, which walks every root's tree, validates
		/// a root's tree as production too.
		let isMock: Bool
		/// The properties the tree receives from outside it that the root's generated initializer takes as parameters:
		/// those of a seam this module generates, which are receivable at its root as its own properties are, a
		/// required non-optional wrapper with its instance. Empty for every other root.
		var receivedFromOutside: Set<Property> = []
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
		/// For each label in `closestDeclarationByLabel`, how many scopes the declaring scope is built inside: `0` for the
		/// root of the tree.
		let closestDeclarationDepthByLabel: [String: Int]
		/// For each of `receivableProperties` that a scope the root's tree builds made receivable, how many scopes that
		/// scope is built inside, as `closestDeclarationDepthByLabel` counts them: the scope since which the property has
		/// been receivable on this path. A property the root's own scope offers has no entry. Empty in the validation of
		/// mocks, which never reads it.
		let receivableDepthByProperty: [Property: Int]
		/// The property `scope` is built for, as cycle validation sees it. `nil` at the root of the tree.
		let property: Property?
		/// The properties of the scopes `scope` is built inside, innermost first.
		let propertyStack: [Property]
		/// The concrete types of the scopes `scope` is built inside, innermost first, beside `propertyStack`.
		let parentTypeStack: [TypeDescription]
		/// The lazily instantiated properties on the instantiation stack, keyed by the constant each is validated as.
		let lazilyInstantiatedDeclarations: [Property: Property]
	}

	/// A scope of a tree that a cycle-closing scope builds again, which `validateTreeBuiltAgainByCycle` has yet to walk, with
	/// what the scopes it is built inside give it there.
	private struct ScopeBuiltAgain {
		let scope: Scope
		/// The property `scope` is built for, as cycle validation sees it.
		let property: Property
		/// The properties of the scopes `scope` is built inside, innermost first: those the function built again builds, then
		/// those the cycle-closing scope that calls it is built inside.
		let propertyStack: [Property]
		/// The concrete types of the scopes `scope` is built inside, innermost first, beside `propertyStack`.
		let parentTypeStack: [TypeDescription]
		/// The property each label names in `scope`.
		let closestDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration]
		/// For each label in `closestDeclarationByLabel`, how many scopes the declaring scope is built inside, as
		/// `ScopeToValidate.closestDeclarationDepthByLabel` counts them along `propertyStack`.
		let closestDeclarationDepthByLabel: [String: Int]
		/// The properties the scopes `scope` is built inside make available to it.
		let receivableProperties: Set<Property>
		/// The labels whose closest declaration here the tree's first build did not see: declarations between the scope the
		/// cycle closes on and the cycle-closing scope, which bind the parameters of the function the cycle closes on,
		/// that no scope the function builds above `scope` declares again.
		let newLabels: Set<String>
		/// Those of `receivableProperties` that were not receivable where `scope` was first built: provided by a scope
		/// between, and by no scope the function builds above `scope`.
		let newReceivableProperties: Set<Property>
		/// How many of the properties on `propertyStack` belong to the first build of the scope the cycle closes on and the
		/// scopes it is built inside: the properties before them are being built inside that first build.
		let closedOnStackCount: Int
	}

	/// A tree that `validateTreeBuiltAgainByCycle` walks: where a cycle-closing scope builds the function it closes on
	/// again, and what is new to that function's tree there. Two cycle-closing scopes of one function beneath one scope,
	/// with the same new declarations and receivable properties, build the same tree again.
	private struct TreeBuiltAgain: Hashable {
		/// The scope the cycle-closing scope is a child of.
		let cycleClosingScopeParent: Scope
		/// The property the cycle closes on, as cycle validation sees it.
		let closedOnProperty: Property
		/// The closest declarations of the labels new to the tree.
		let newDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration]
		/// The properties receivable at the cycle-closing scope that were not where the tree was first built.
		let newReceivableProperties: Set<Property>
	}

	/// The property that `validateNoCycleInReceivedProperties` walked for a required receive of an `onlyIfAvailable`
	/// alias – the one the last alias the receive requires is created from, walked where that alias is declared – with
	/// everything that decides whether the walk throws.
	private struct WalkedAliasFulfillingProperty: Hashable {
		/// The property the last alias the receive requires is created from.
		let fulfillingProperty: Property
		/// The properties received through the aliases the receive requires, the receive's own first, as cycle
		/// validation sees them: the walk's received-property stack starts with them. Two aliases of one fulfilling
		/// property, or two chains of aliases that end in the same alias, walk differently.
		let receivedPropertyStack: [Property]
		/// The instantiation stack of the scope that declares the last alias the receive requires.
		let lastAliasDeclaringInstantiationStack: [Property]
		/// The properties the mock root forwards, which the walk does not follow unless a scope builds them, or `nil`
		/// for a tree validated as production.
		let mockRootForwardedProperties: Set<Property>?
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
		/// Each hidden receive as reported, with the concrete types of every chain of scopes that reaches it, which its
		/// rendering does not tell apart.
		var hiddenReceivedProperties = [DependencyTreeGeneratorError.HiddenReceivedProperty: Set<[TypeDescription]>]()
		var renamesContradictingOwnProperties = Set<DependencyTreeGeneratorError.RenameContradictingOwnProperty>()
		/// The properties a scope of `typeDescriptionToScopeMap` builds – instantiates, or renames another property to –
		/// as cycle validation sees them. Most walks never ask, so the set is built the first time one does.
		lazy var propertiesBuiltByAScope: Set<Property> = {
			var propertiesBuiltByAScope = Set<Property>()
			for scope in typeDescriptionToScopeMap.values {
				for dependency in scope.instantiable.dependencies {
					switch dependency.source {
					case .instantiated, .aliased:
						propertiesBuiltByAScope.insert(dependency.property.asValidatedForDependencyCycles)
					case .received, .forwarded:
						continue
					}
				}
			}
			return propertiesBuiltByAScope
		}()
		/// Whether a tree is handed `receivedProperty`, which the tree receives from above, rather than building it from
		/// `receivedPropertyScope`. A handed value comes from outside the tree – a `@Forwarded` value, or one a mock
		/// takes as a `mock()` parameter – so the dependencies of its type are no part of the tree: a cycle through them
		/// is reported where a tree builds that type. A property is built when a scope instantiates it or renames
		/// another property to it, wherever that scope is, since a receive of it may resolve there. A mock also builds
		/// what it promotes: a property its root does not forward and that the mock can build. A property that nothing
		/// builds or forwards is provided by nothing at all, which validation reports where it is received.
		/// - Parameter mockRootForwardedProperties: The properties the mock root forwards, or `nil` for a tree validated as
		///   production (see `ValidatedRootScope.isMock`), whose root promotes nothing.
		func isHanded(_ receivedProperty: Property, from receivedPropertyScope: Scope, mockRootForwardedProperties: Set<Property>?) -> Bool {
			if let mockRootForwardedProperties, !mockRootForwardedProperties.contains(receivedProperty), Self.mockCanBuild(receivedProperty, from: receivedPropertyScope) {
				false
			} else {
				!propertiesBuiltByAScope.contains(receivedProperty)
			}
		}
		/// Walks `requiredReceivedProperties`, which `directParent` requires, and, transitively, the required received
		/// properties of the scopes that fulfill them, throwing when one is `property` or is on `instantiationStack`.
		/// The walk descends depth first, in declaration order, and keeps its own stack of the scopes it is part way
		/// through, since a chain of received properties can be as long as the module has types. It does not descend
		/// into a property the tree is handed: see `isHanded`.
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
		///   - mockRootForwardedProperties: See `isHanded`.
		///   - nearestDeclaration: The nearest declaration of a label above the scope whose receives the walk starts from,
		///     as `indexOfEntryClosedOn` reads it: a receive of a property on `instantiationStack` that a nearer declaration
		///     fulfills is walked as a property not on it. A property received transitively, by the scope of a type the walk
		///     follows, is judged with this scope's declarations rather than those where that type is built: that scope is
		///     validated with its own, so this walk accepts nothing it would reject, and only which of two diagnostics is
		///     reported first can follow from it.
		func validateNoCycleInReceivedProperties(
			_ requiredReceivedProperties: [Scope.RequiredReceivedProperty],
			directParent: TypeDescription,
			receivedPropertyStack: [Property],
			declaredReceivedPropertyStack: [Property],
			property: Property,
			instantiationStack: [Property],
			lazilyInstantiatedDeclarations: [Property: Property],
			mockRootForwardedProperties: Set<Property>?,
			nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
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
				if let cycleIndex = instantiationStack.firstIndex(of: childProperty),
				   !Self.isFulfilledByNearerDeclaration([childProperty], thanEntryAt: cycleIndex, of: instantiationStack, nearestDeclaration: nearestDeclaration)
				{
					let instantiationProperties = Array(instantiationStack[0...cycleIndex])
					let propertiesInCycle = [childProperty]
						+ receivedPropertyStack.reversed()
						+ instantiationProperties
					try throwIfInvalidCycle(
						propertiesInCycle: propertiesInCycle,
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
				} else if let receivedPropertyScope = typeDescriptionToScopeMap[childProperty.typeDescription],
				          !isHanded(childProperty, from: receivedPropertyScope, mockRootForwardedProperties: mockRootForwardedProperties)
				{
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
			if cyclesOnly {
				validatedFulfillingProperty.formsOnMockInstantiationStack
			} else {
				[validatedFulfillingProperty, validatedFulfillingProperty.asUnwrappedProperty]
			}
		}
		/// The fulfilling properties of the `onlyIfAvailable` aliases already walked by
		/// `validateNoCycleInReceivedProperties` – each the property the last alias a receive requires is created from –
		/// with what decides whether the walk throws (see `WalkedAliasFulfillingProperty`): it starts from that property
		/// with the properties received through the aliases on its stack, bails out on a chain that reaches a property on
		/// that stack, stops at a property the tree is handed, which depends on what the mock root forwards, and throws on
		/// a chain that reaches the last alias's declaring stack; the rest it is passed only names what an error reports.
		/// A walk that throws leaves the set, so a walk in the set returned without throwing, in whichever tree walked it,
		/// and walking it again would too. A receive of another alias of the same fulfilling property is walked again: a
		/// chain that bails out at one received property can reach the declaring stack from another.
		var walkedAliasFulfillingProperties = Set<WalkedAliasFulfillingProperty>()
		/// See `labelsRead(inTreeOf:)`. Filled only by walks of a tree a cycle builds again, so a graph without cycles pays nothing.
		var labelsReadByTreeRoot = [Scope: Set<String>]()
		/// The labels `validateTreeBuiltAgainByCycle`'s judgements read anywhere `scope` reaches: the label of each `@Received`
		/// property, and of the property each alias is fulfilled by rather than the alias's own, of `scope` and every scope it
		/// instantiates, through cycle-closing scopes too, since the walk continues through them.
		///
		/// Each answer is a whole pass over what `scope` reaches, with its own visited set. It must not reuse the answers of
		/// the pass in progress: inside a cycle, a scope's answer is only complete once the pass that visits it is, so a
		/// memo of partial answers records a scope as reading nothing that it reads through the cycle. The stack is explicit
		/// because a tree can be as deep as the module has types.
		func labelsRead(inTreeOf scope: Scope) -> Set<String> {
			if let labels = labelsReadByTreeRoot[scope] {
				return labels
			} else {
				var labels = Set<String>()
				var reachedScopes: Set<Scope> = [scope]
				var scopesToVisit = [scope]
				while let reachedScope = scopesToVisit.popLast() {
					for dependency in reachedScope.instantiable.dependencies {
						switch dependency.source {
						case .received:
							labels.insert(dependency.property.label)
						case let .aliased(fulfillingProperty, _, _):
							labels.insert(fulfillingProperty.label)
						case .instantiated, .forwarded:
							break
						}
					}
					for case let .instantiated(_, childScope, _) in reachedScope.propertiesToGenerate {
						if reachedScopes.insert(childScope).inserted {
							scopesToVisit.append(childScope)
						}
					}
				}
				labelsReadByTreeRoot[scope] = labels
				return labels
			}
		}
		/// Whether the tree `scope` builds reads a label new to it that a judgement of `validateTreeBuiltAgainByCycle` can fire
		/// for: one of `newLabels`, or the label of one of `newReceivableProperties`, that is not among
		/// `labelsNoJudgementFiresFor()`.
		func treeReadsAnything(ofTreeRootedAt scope: Scope, newLabels: some Collection<String>, newReceivableProperties: Set<Property>) -> Bool {
			guard !newLabels.isEmpty || !newReceivableProperties.isEmpty else { return false }
			let readLabels = labelsRead(inTreeOf: scope)
			func canBeJudged(_ label: String) -> Bool {
				readLabels.contains(label) && !labelsNoJudgementFiresFor().contains(label)
			}
			return newLabels.contains(where: canBeJudged) || newReceivableProperties.contains { canBeJudged($0.label) }
		}
		/// See `labelsNoJudgementFiresFor()`.
		var memoizedLabelsNoJudgementFiresFor: Set<String>?
		/// The labels for which neither judgement of `validateTreeBuiltAgainByCycle` can fire anywhere in the trees of these
		/// roots, whatever is new where: every declaration of the label is one that every read of it accepts, as
		/// `recordHiddenReceives` accepts the closest declaration, so no declaration of it hides a read; and no tree built for a
		/// property of the label reads it, so no declaration of it is still being built where it is read. A value redeclared
		/// between screens with its own type, such as a flow's state, is such a label. The answer reads every scope the roots
		/// reach and no walk's outcome, so it is computed once, when a walk first finds a read label new.
		func labelsNoJudgementFiresFor() -> Set<String> {
			if let memoizedLabelsNoJudgementFiresFor {
				return memoizedLabelsNoJudgementFiresFor
			} else {
				var declarationsByLabel = [String: [(property: Property, lazilyInstantiatedInstanceProperty: Property?)]]()
				var acceptedPropertiesOfReadsByLabel = [String: [Set<Property>]]()
				var scopesBuiltByLabel = [String: [Scope]]()
				var reachedScopes = Set<Scope>()
				var scopesToVisit = [Scope]()
				for rootScope in rootScopes + additionalMockRootScopes where reachedScopes.insert(rootScope.scope).inserted {
					scopesToVisit.append(rootScope.scope)
				}
				while let reachedScope = scopesToVisit.popLast() {
					for dependency in reachedScope.instantiable.dependencies {
						// What `enterDeclarations` enters as a closest declaration.
						if reachedScope.createdProperties.contains(dependency.property) {
							declarationsByLabel[dependency.property.label, default: []].append((dependency.property, dependency.lazilyInstantiatedInstanceProperty))
						}
						// What `recordHiddenReceives` accepts for each read.
						switch dependency.source {
						case .received:
							acceptedPropertiesOfReadsByLabel[dependency.property.label, default: []].append([dependency.property, dependency.property.asUnwrappedProperty])
						case let .aliased(fulfillingProperty, _, onlyIfAvailable):
							acceptedPropertiesOfReadsByLabel[fulfillingProperty.label, default: []].append(onlyIfAvailable
								? Set(fulfillingProperty.formsReadByOnlyIfAvailableReceive)
								: [fulfillingProperty, fulfillingProperty.asUnwrappedProperty])
						case .instantiated, .forwarded:
							break
						}
					}
					for case let .instantiated(childProperty, childScope, _) in reachedScope.propertiesToGenerate {
						scopesBuiltByLabel[childProperty.label, default: []].append(childScope)
						if reachedScopes.insert(childScope).inserted {
							scopesToVisit.append(childScope)
						}
					}
				}
				var labels = Set<String>()
				for (label, acceptedPropertiesOfReads) in acceptedPropertiesOfReadsByLabel {
					let everyDeclarationIsAccepted = declarationsByLabel[label, default: []].allSatisfy { declaration in
						acceptedPropertiesOfReads.allSatisfy {
							$0.contains(declaration.property) || declaration.lazilyInstantiatedInstanceProperty.map($0.contains) == true
						}
					}
					if everyDeclarationIsAccepted, scopesBuiltByLabel[label, default: []].allSatisfy({ !labelsRead(inTreeOf: $0).contains(label) }) {
						labels.insert(label)
					}
				}
				memoizedLabelsNoJudgementFiresFor = labels
				return labels
			}
		}
		/// Validates the tree rooted at `rootScope`, scope by scope, depth first in the order each scope declares its
		/// children. It keeps its own stack of the scopes left to validate, since a tree can be as deep as the module
		/// has types.
		/// - Parameters:
		///   - validatesCycles: Whether to validate the tree for dependency cycles and unfulfillable received
		///     properties. `false` only for a tree validated for hidden received dependencies alone.
		///   - validatesHiddenProperties: Whether to record received dependencies a closer declaration hides, and renames
		///     that name another type than their own type's property of their label.
		func validatePropertiesAreFulfillable(
			inTreeRootedAt rootScope: ValidatedRootScope,
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
		) throws {
			var scopesToValidate = [ScopeToValidate(
				scope: rootScope.scope,
				receivableProperties: Set(rootScope.scope.properties).union(rootScope.receivedFromOutside),
				receivableAliases: [:],
				closestDeclarationByLabel: [:],
				closestDeclarationDepthByLabel: [:],
				receivableDepthByProperty: [:],
				property: nil,
				propertyStack: [],
				parentTypeStack: [],
				lazilyInstantiatedDeclarations: [:],
			)]
			let mockRootForwardedProperties: Set<Property>? = rootScope.isMock ? rootScope.scope.instantiable.forwardedReceivableProperties : nil
			while let scopeToValidate = scopesToValidate.popLast() {
				try validatePropertiesAreFulfillable(
					on: scopeToValidate,
					boundProperties: rootScope.boundProperties,
					mockRootForwardedProperties: mockRootForwardedProperties,
					validatesCycles: validatesCycles,
					validatesHiddenProperties: validatesHiddenProperties,
					root: rootScope.scope.instantiable.concreteInstantiable,
					scopesToValidate: &scopesToValidate,
				)
			}
		}
		/// Records each dependency of `scope` that the closest declaration of the label it receives hides, among
		/// `closestDeclarationByLabel`: the generated code passes a received dependency by its label, which resolves to that
		/// declaration, so a different property there is passed in its place. One rule for a scope on any path and for a
		/// type a cycle-closing scope builds again, so the two cannot differ.
		/// - Parameters:
		///   - receivableProperties: What the scopes `scope` is built inside make available to it.
		///   - propertyStack: The properties of the scopes `scope` is built inside, innermost first.
		///   - parentTypeStack: The concrete types of those scopes, beside `propertyStack`.
		///   - changedContext: For a scope of a tree a cycle-closing scope builds again, what is new there to the tree (see
		///     `ScopeBuiltAgain`): only a receive whose hiding declaration is new, or that only a new receivable property
		///     provides, is recorded, since the tree's first build judged every other receive as this one would.
		func recordHiddenReceives(
			of scope: Scope,
			closestDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration],
			receivableProperties: Set<Property>,
			propertyStack: [Property],
			parentTypeStack: [TypeDescription],
			root: TypeDescription,
			changedContext: (newLabels: Set<String>, newReceivableProperties: Set<Property>)? = nil,
		) {
			// What the tree's first build received here.
			let firstBuildReceivableProperties = if let changedContext, !changedContext.newReceivableProperties.isEmpty {
				receivableProperties.subtracting(changedContext.newReceivableProperties)
			} else {
				receivableProperties
			}
			// A builder an internal mock passes up to its own parameter, which the leaf that calls the public mock receives
			// under the builder's label, is a receive no declaration the person wrote can fulfill: the mock names the
			// parameter apart from every label its tree declares, and the leaf reads it there (see
			// `ScopeGenerator.mockRootParameterNames(of:)`).
			for dependency in scope.instantiable.dependencies where !(scope.publicMockCall?.passesUpBuilder(receivedAs: dependency.property) ?? false) {
				let receivedProperty: Property
				let acceptedProperties: Set<Property>
				switch dependency.source {
				case .received:
					receivedProperty = dependency.property
					// A receive of an optional property, required or `onlyIfAvailable`, resolves to its non-optional
					// form too.
					acceptedProperties = [receivedProperty, receivedProperty.asUnwrappedProperty]
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					receivedProperty = fulfillingProperty
					// An `onlyIfAvailable` alias reads the optional form of its fulfilling property too, as `nil` where it is.
					acceptedProperties = onlyIfAvailable
						? Set(fulfillingProperty.formsReadByOnlyIfAvailableReceive)
						: [fulfillingProperty, fulfillingProperty.asUnwrappedProperty]
				case .instantiated, .forwarded:
					continue
				}
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
				if let changedContext {
					// A declaration between the function and the cycle-closing scope hides the receive; or the function's
					// own tree hides it, as on its first build, which passed it `nil`, since only a scope between provides it.
					guard changedContext.newLabels.contains(receivedProperty.label)
						|| !cyclesOnly && acceptedProperties.isDisjoint(with: firstBuildReceivableProperties)
					else { continue }
				}
				hiddenReceivedProperties[.init(
					property: receivedProperty,
					declarationLocation: dependency.declarationLocation,
					hidingDeclaration: closestDeclaration,
					receiver: scope.instantiable.concreteInstantiable,
					parentStack: propertyStack.map(\.typeDescription),
					root: root,
				), default: []].insert(parentTypeStack)
			}
		}
		/// Enters each property `scope` creates in `closestDeclarationByLabel` as the closest declaration of its label for the
		/// scopes `scope` builds, calling `entering` with each label. One rule for the walk of a tree and the walk of a tree a
		/// cycle-closing scope builds again.
		func enterDeclarations(
			of scope: Scope,
			into closestDeclarationByLabel: inout [String: DependencyTreeGeneratorError.LabelDeclaration],
			entering: (String) -> Void,
		) {
			for dependency in scope.instantiable.dependencies where scope.createdProperties.contains(dependency.property) {
				closestDeclarationByLabel[dependency.property.label] = .init(
					property: dependency.property,
					lazilyInstantiatedInstanceProperty: dependency.lazilyInstantiatedInstanceProperty,
					declarationLocation: dependency.declarationLocation,
					declaringType: scope.instantiable.concreteInstantiable,
					isForwarded: dependency.isForwarded,
				)
				entering(dependency.property.label)
			}
		}
		/// Inserts into `properties` what `scope` makes available to the scopes it builds, given `receivableProperties`, what
		/// the scopes `scope` is built inside make available to it, and calls `inserted` with each property `properties` did
		/// not hold. One rule for the walk of a tree and the walk of a tree a cycle-closing scope builds again.
		/// - Parameters:
		///   - instantiationStack: The properties of `scope` and of the scopes it is built inside, innermost first.
		///   - nearestDeclaration: The nearest declaration of a label above `scope`, as `indexOfEntryClosedOn` reads it.
		func insertProperties(
			madeAvailableBy scope: Scope,
			given receivableProperties: Set<Property>,
			instantiationStack: [Property],
			nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
			into properties: inout Set<Property>,
			inserted: (Property) -> Void,
		) {
			// An `onlyIfAvailable` receive that is unavailable here is passed `nil`, so it provides nothing to the
			// scopes below. Availability mirrors `Scope.createScopeGenerator`'s: in a mock, only a property that is
			// still being built is unavailable. A receive of a property being built that a nearer declaration fulfills,
			// such as one that closes a cycle, is passed that declaration.
			func isBeingBuilt(_ property: Property) -> Bool {
				// The instantiation stack holds a lazily instantiated property as the constant it stands for.
				let validatedProperty = property.asValidatedForDependencyCycles
				return instantiationStack.firstIndex(of: validatedProperty).map {
					!Self.isFulfilledByNearerDeclaration([validatedProperty], thanEntryAt: $0, of: instantiationStack, nearestDeclaration: nearestDeclaration)
				} ?? false
			}
			func isAvailable(_ onlyIfAvailableProperty: Property) -> Bool {
				if cyclesOnly {
					![onlyIfAvailableProperty, onlyIfAvailableProperty.asUnwrappedProperty].contains(where: isBeingBuilt)
				} else {
					[onlyIfAvailableProperty, onlyIfAvailableProperty.asUnwrappedProperty].contains {
						receivableProperties.contains($0) && !isBeingBuilt($0)
					}
				}
			}
			func insert(_ property: Property) {
				if properties.insert(property).inserted {
					inserted(property)
				}
			}
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case let .received(onlyIfAvailable):
					if !onlyIfAvailable || isAvailable(dependency.property) {
						insert(dependency.property)
					}
				case .instantiated, .forwarded, .aliased:
					insert(dependency.property)
					// A lazily instantiated property can also be received by value, as the instance it creates.
					if let instanceProperty = dependency.lazilyInstantiatedInstanceProperty {
						insert(instanceProperty)
					}
				}
			}
			// A mock root also provides the received dependencies it promotes.
			for providedProperty in scope.providedProperties {
				insert(providedProperty)
			}
		}
		/// Validates the tree that a cycle-closing scope, a child of `cycleClosingScopeParent`, builds again – `scope`'s,
		/// built for `property` beneath the scopes of `propertyStack` – where it can differ from the tree's first build, at
		/// `closedOnIndex` in `propertyStack`. The tree is the body of the builder function the cycle closes on, which takes
		/// the labels the scopes between declare as parameters (see `CycleParameter`), so each receive of such a label is
		/// passed the nearest declaration above the cycle-closing scope, as on every other path.
		///
		/// The tree built again is the same code as its first build, which the walk of the tree validated. So only two
		/// things can change what a receive in it resolves to: the bindings of the function's parameters – the declarations
		/// between the scope the cycle closes on and the cycle-closing scope, until a scope the function builds declares the
		/// label again – and the providers above – the properties receivable at the cycle-closing scope that were not where
		/// the tree was first built. The walk threads that context through the tree as the walk of a tree threads its own,
		/// and judges each receive by the rule of every other path (`recordHiddenReceives`), only where the context changes
		/// the judgment: a receive hidden by a new declaration is the hidden-label error where a scope above provides it,
		/// required or only if available; one hidden by a declaration of the tree's own, as on its first build, is the
		/// error where only a new provider provides it, which the first build passed `nil`; and a required receive whose new
		/// nearest declaration is still being built is the dependency cycle error.
		///
		/// A cycle-closing scope the walk meets – of the function built again, of a function nested in it or around it, or a
		/// scope the stack holds already – calls its function with the bindings in scope there, so the walk goes on into that
		/// tree built again whenever anything is new to it there, once for each parent of a cycle-closing scope and context
		/// (`TreeBuiltAgain`), so nested cycles end.
		///
		/// The walk's work grows with every path the scopes it re-enters can be reached by, so a tree whose judgements cannot
		/// change is not walked: at its start and before each child it pushes, the walk stops unless the tree reads a label
		/// new to it (`labelsRead(inTreeOf:)`) that a judgement can fire for (`labelsNoJudgementFiresFor()`). Both of the
		/// walk's judgements fire only for a receive whose label is new, and the new labels only shrink going down, so a tree
		/// that reads none has nothing to report, on any path.
		func validateTreeBuiltAgainByCycle(
			of scope: Scope,
			for property: Property,
			closedOnIndex: Int,
			cycleClosingScopeParent: Scope,
			propertyStack: [Property],
			parentTypeStack: [TypeDescription],
			closestDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration],
			closestDeclarationDepthByLabel: [String: Int],
			receivableProperties: Set<Property>,
			receivableDepthByProperty: [Property: Int],
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
			root: TypeDescription,
		) throws {
			// The scope the cycle closes on is built inside the scopes after it on the stack.
			let closedOnDepth = propertyStack.count - closedOnIndex
			// The declarations between that bind the function's parameters. The property the cycle closes on is no
			// parameter: the cycle-closing scope's own declaration of its label is that property, which the tree built again
			// is passed `nil` for, as its first build is.
			var newDeclarationByLabel = [String: DependencyTreeGeneratorError.LabelDeclaration]()
			for (label, depth) in closestDeclarationDepthByLabel where depth > closedOnDepth && label != property.label {
				newDeclarationByLabel[label] = closestDeclarationByLabel[label]
			}
			// Nearly every cycle-closing scope has no declaration between it and the scope it closes on but its own.
			guard !newDeclarationByLabel.isEmpty else { return }
			// The properties a scope between made receivable. The validation of mocks, which judges a hidden receive whatever
			// provides it, records no depths and so finds none.
			var newReceivableProperties = Set<Property>()
			for (receivableProperty, depth) in receivableDepthByProperty where depth > closedOnDepth && receivableProperties.contains(receivableProperty) {
				newReceivableProperties.insert(receivableProperty)
			}
			guard treeReadsAnything(ofTreeRootedAt: scope, newLabels: newDeclarationByLabel.keys, newReceivableProperties: newReceivableProperties) else { return }
			var treesBuiltAgain: Set<TreeBuiltAgain> = [TreeBuiltAgain(
				cycleClosingScopeParent: cycleClosingScopeParent,
				closedOnProperty: property,
				newDeclarationByLabel: newDeclarationByLabel,
				newReceivableProperties: newReceivableProperties,
			)]
			var scopesToWalk = [ScopeBuiltAgain(
				scope: scope,
				property: property,
				propertyStack: propertyStack,
				parentTypeStack: parentTypeStack,
				closestDeclarationByLabel: closestDeclarationByLabel,
				closestDeclarationDepthByLabel: closestDeclarationDepthByLabel,
				receivableProperties: receivableProperties,
				newLabels: Set(newDeclarationByLabel.keys),
				newReceivableProperties: newReceivableProperties,
				closedOnStackCount: closedOnDepth,
			)]
			while let scopeToWalk = scopesToWalk.popLast() {
				let walkedScope = scopeToWalk.scope
				let instantiationStack = [scopeToWalk.property] + scopeToWalk.propertyStack
				if validatesHiddenProperties {
					recordHiddenReceives(
						of: walkedScope,
						closestDeclarationByLabel: scopeToWalk.closestDeclarationByLabel,
						receivableProperties: scopeToWalk.receivableProperties,
						propertyStack: scopeToWalk.propertyStack,
						parentTypeStack: scopeToWalk.parentTypeStack,
						root: root,
						changedContext: (scopeToWalk.newLabels, scopeToWalk.newReceivableProperties),
					)
				}
				for dependency in walkedScope.instantiable.dependencies where validatesCycles {
					let receivedProperty: Property
					switch dependency.source {
					case .received(onlyIfAvailable: false):
						receivedProperty = dependency.property
					case let .aliased(fulfillingProperty, _, onlyIfAvailable: false):
						// An alias of a property its own scope creates refers to that property.
						guard !walkedScope.createdProperties.contains(fulfillingProperty) else { continue }
						receivedProperty = fulfillingProperty
					case .received(onlyIfAvailable: true), .aliased(_, _, onlyIfAvailable: true), .instantiated, .forwarded:
						continue
					}
					let acceptedProperties: Set<Property> = [receivedProperty, receivedProperty.asUnwrappedProperty]
					// A new nearest declaration: the first build judged one it saw. One of another type is the hidden-label
					// error, recorded above.
					if scopeToWalk.newLabels.contains(receivedProperty.label),
					   let declaration = scopeToWalk.closestDeclarationByLabel[receivedProperty.label],
					   acceptedProperties.contains(declaration.property) || declaration.lazilyInstantiatedInstanceProperty.map(acceptedProperties.contains) == true,
					   let beingBuiltIndex = instantiationStack.firstIndex(of: declaration.property.asValidatedForDependencyCycles),
					   // The scopes being built inside the first build of the scope the cycle closes on are those before it on
					   // the stack.
					   beingBuiltIndex < instantiationStack.count - scopeToWalk.closedOnStackCount
					{
						// The nearest declaration is still being built around the cycle-closing scope.
						throw invalidCycleError(
							propertiesInCycle: [receivedProperty.asValidatedForDependencyCycles] + instantiationStack[0...beingBuiltIndex],
							property: instantiationStack[beingBuiltIndex],
							declaredProperty: dependency.property,
							declarationLocation: dependency.declarationLocation,
							directParent: walkedScope.instantiable.concreteInstantiable,
							closingReceive: CycleClosingReceive(aliasProperty: dependency.source.isReceived ? nil : dependency.property),
							lazilyInstantiatedProperties: [],
						)
					}
				}
				// What the scopes the walked scope builds see: a label it declares again names its own declaration there, as
				// on the first build, and a property it provides on the first build too is receivable there on both.
				var childClosestDeclarationByLabel = scopeToWalk.closestDeclarationByLabel
				var childClosestDeclarationDepthByLabel = scopeToWalk.closestDeclarationDepthByLabel
				var childNewLabels = scopeToWalk.newLabels
				enterDeclarations(of: walkedScope, into: &childClosestDeclarationByLabel) {
					childNewLabels.remove($0)
					childClosestDeclarationDepthByLabel[$0] = instantiationStack.count
				}
				let nearestDeclaration: (String) -> (properties: [Property], depth: Int)? = { label in
					scopeToWalk.closestDeclarationByLabel[label].map { ([$0.property.asValidatedForDependencyCycles], scopeToWalk.closestDeclarationDepthByLabel[label, default: 0]) }
				}
				var childReceivableProperties = scopeToWalk.receivableProperties
				var childNewReceivableProperties = Set<Property>()
				if scopeToWalk.newReceivableProperties.isEmpty {
					insertProperties(madeAvailableBy: walkedScope, given: scopeToWalk.receivableProperties, instantiationStack: instantiationStack, nearestDeclaration: nearestDeclaration, into: &childReceivableProperties) { _ in }
				} else {
					// A receive only if available that only a new property makes available provides a new property too.
					childNewReceivableProperties = scopeToWalk.newReceivableProperties
					insertProperties(madeAvailableBy: walkedScope, given: scopeToWalk.receivableProperties, instantiationStack: instantiationStack, nearestDeclaration: nearestDeclaration, into: &childReceivableProperties) {
						childNewReceivableProperties.insert($0)
					}
					var firstBuildProvidedProperties = Set<Property>()
					insertProperties(
						madeAvailableBy: walkedScope,
						given: scopeToWalk.receivableProperties.subtracting(scopeToWalk.newReceivableProperties),
						instantiationStack: instantiationStack,
						nearestDeclaration: nearestDeclaration,
						into: &firstBuildProvidedProperties,
					) { _ in }
					childNewReceivableProperties.subtract(firstBuildProvidedProperties)
				}
				let childParentTypeStack = [walkedScope.instantiable.concreteInstantiable] + scopeToWalk.parentTypeStack
				let firstChildIndex = scopesToWalk.endIndex
				for childPropertyToGenerate in walkedScope.propertiesToGenerate {
					switch childPropertyToGenerate {
					case let .instantiated(declaredChildProperty, childScope, _):
						// A child's tree is the same code as on its first build, and a cycle-closing scope's function's tree built
						// again here sees what it saw where it was built: only a label new to it can change what it receives.
						guard treeReadsAnything(ofTreeRootedAt: childScope, newLabels: childNewLabels, newReceivableProperties: childNewReceivableProperties) else { continue }
						// A lazily instantiated property is validated as the constant it stands for.
						let childProperty = declaredChildProperty.asValidatedForDependencyCycles
						if let childClosedOnIndex = instantiationStack.indices.first(where: {
							instantiationStack[$0] == childProperty && childParentTypeStack[$0] == childScope.instantiable.concreteInstantiable
						}) {
							var childNewDeclarationByLabel = [String: DependencyTreeGeneratorError.LabelDeclaration]()
							for label in childNewLabels {
								childNewDeclarationByLabel[label] = childClosestDeclarationByLabel[label]
							}
							guard treesBuiltAgain.insert(TreeBuiltAgain(
								cycleClosingScopeParent: walkedScope,
								closedOnProperty: childProperty,
								newDeclarationByLabel: childNewDeclarationByLabel,
								newReceivableProperties: childNewReceivableProperties,
							)).inserted else { continue }
							scopesToWalk.append(ScopeBuiltAgain(
								scope: childScope,
								property: childProperty,
								propertyStack: instantiationStack,
								parentTypeStack: childParentTypeStack,
								closestDeclarationByLabel: childClosestDeclarationByLabel,
								closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
								// As the tree of any child is given them, without the property it builds.
								receivableProperties: childReceivableProperties.subtracting(childPropertyToGenerate.receivableProperties),
								newLabels: childNewLabels,
								newReceivableProperties: childNewReceivableProperties,
								closedOnStackCount: instantiationStack.count - childClosedOnIndex,
							))
						} else {
							// Neither the child nor, when it is lazily instantiated, its instance can be received in the tree it
							// creates.
							var receivablePropertiesInChildTree = childReceivableProperties
							receivablePropertiesInChildTree.remove(declaredChildProperty)
							if let instanceProperty = childPropertyToGenerate.lazilyInstantiatedInstanceProperty {
								receivablePropertiesInChildTree.remove(instanceProperty)
							}
							scopesToWalk.append(ScopeBuiltAgain(
								scope: childScope,
								property: childProperty,
								propertyStack: instantiationStack,
								parentTypeStack: childParentTypeStack,
								closestDeclarationByLabel: childClosestDeclarationByLabel,
								closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
								receivableProperties: receivablePropertiesInChildTree,
								newLabels: childNewLabels,
								newReceivableProperties: childNewReceivableProperties,
								closedOnStackCount: scopeToWalk.closedOnStackCount,
							))
						}
					case .aliased, .hole:
						break
					}
				}
				// The scope walked next is the last one on the stack, so the first child goes last.
				scopesToWalk[firstChildIndex...].reverse()
			}
		}
		/// Validates one scope of a tree, and adds the children to validate after it to `scopesToValidate`, the first
		/// child last.
		/// - Parameters:
		///   - scopeToValidate: The scope, with what the scopes it is built inside give it.
		///   - boundProperties: The received properties the tree's mock binds. See `ValidatedRootScope`.
		///   - mockRootForwardedProperties: The properties the tree's mock root forwards, or `nil` for a tree validated
		///     as production. See `isHanded`.
		///   - validatesCycles: See `validatePropertiesAreFulfillable(inTreeRootedAt:validatesCycles:validatesHiddenProperties:)`.
		///   - validatesHiddenProperties: See `validatePropertiesAreFulfillable(inTreeRootedAt:validatesCycles:validatesHiddenProperties:)`.
		///   - root: The type at the root of the tree.
		/// What an `onlyIfAvailable` alias of `fulfillingProperty` that `scope` declares is bound from, as
		/// `Scope.createScopeGenerator` binds it: a property `scope` provides, else the nearest declaration of the
		/// fulfilling property's label above `scope` – unless it provides no form the alias reads, or the walk descended
		/// through it, so it is still being built – else what encloses the tree. `nil` where the alias is bound to `nil`.
		/// - Parameters:
		///   - closestDeclarationDepthByLabel: The count of the instantiation stack at the scope that declares each of
		///     `closestDeclarationByLabel`.
		///   - instantiationStack: The properties of `scope` and of the scopes it is built inside, innermost first.
		func aliasBinding(
			of fulfillingProperty: Property,
			declaredBy scope: Scope,
			closestDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration],
			closestDeclarationDepthByLabel: [String: Int],
			receivableProperties: Set<Property>,
			boundProperties: Set<Property>,
			instantiationStack: [Property],
		) -> ReceivableAlias.AliasBinding? {
			func isRead(_ declaredProperty: Property) -> Bool {
				ScopeGenerator.provides(declaredProperty, aFormReadBy: fulfillingProperty)
			}
			let forwardedProperties = scope.instantiable.forwardedReceivableProperties
			let ownProviders = scope.providedProperties.filter { $0.label == fulfillingProperty.label && isRead($0) }
			if !ownProviders.isEmpty {
				return ownProviders.allSatisfy(forwardedProperties.contains) ? .handed : .built
			} else if let closestDeclaration = closestDeclarationByLabel[fulfillingProperty.label] {
				guard isRead(closestDeclaration.property) else { return nil }
				// The child of the declaring scope that the walk descended through to reach `scope`.
				let descendedChildIndex = instantiationStack.count - (closestDeclarationDepthByLabel[fulfillingProperty.label] ?? 0) - 1
				if instantiationStack.indices.contains(descendedChildIndex),
				   formsOnStack(of: closestDeclaration.property.asValidatedForDependencyCycles).contains(instantiationStack[descendedChildIndex])
				{
					return nil
				} else {
					return closestDeclaration.isForwarded ? .handed : .built
				}
			} else if fulfillingProperty.formsReadByOnlyIfAvailableReceive.contains(where: { receivableProperties.contains($0) || boundProperties.contains($0) }) {
				return .handed
			} else {
				return nil
			}
		}
		func validatePropertiesAreFulfillable(
			on scopeToValidate: ScopeToValidate,
			boundProperties: Set<Property>,
			mockRootForwardedProperties: Set<Property>?,
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
			/// The nearest declaration of a label above this scope, as `indexOfEntryClosedOn` reads it.
			let nearestDeclaration: (String) -> (properties: [Property], depth: Int)? = { label in
				closestDeclarationByLabel[label].map { ([$0.property.asValidatedForDependencyCycles], scopeToValidate.closestDeclarationDepthByLabel[label, default: 0]) }
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
					mockRootForwardedProperties: mockRootForwardedProperties,
					nearestDeclaration: nearestDeclaration,
				)
			}

			// The aliases this scope declares, which a receive of their property resolves to: an `onlyIfAvailable` alias is
			// declared even where it is bound to `nil`, so it hides every declaration of its label above it.
			var declaredAliases = [Property: ReceivableAlias]()
			for case let (aliasDependency, .aliased(fulfillingProperty, _, onlyIfAvailable)) in scope.instantiable.dependencies.lazy.map({ ($0, $0.source) }) {
				let alias = ReceivableAlias(
					fulfillingProperty: fulfillingProperty,
					onlyIfAvailable: onlyIfAvailable,
					fulfillingOnlyIfAvailableAliases: [],
					binding: onlyIfAvailable
						? aliasBinding(
							of: fulfillingProperty,
							declaredBy: scope,
							closestDeclarationByLabel: closestDeclarationByLabel,
							closestDeclarationDepthByLabel: scopeToValidate.closestDeclarationDepthByLabel,
							receivableProperties: receivableProperties,
							boundProperties: boundProperties,
							instantiationStack: instantiationStack,
						)
						: .built,
					declaringType: scope.instantiable.concreteInstantiable,
					lastAliasDeclaringType: scope.instantiable.concreteInstantiable,
					lastAliasDeclaringInstantiationStack: instantiationStack,
				)
				declaredAliases[aliasDependency.property] = alias
				// A lazily instantiated alias is also received by value, as the instance it creates.
				if let aliasInstanceProperty = aliasDependency.lazilyInstantiatedInstanceProperty {
					declaredAliases[aliasInstanceProperty] = alias
				}
			}
			// An `onlyIfAvailable` alias of another `onlyIfAvailable` alias is bound from it, so it is `nil` where that
			// alias is: a receive that requires the first requires the second, and so on along any chain of them, as
			// `ScopeGenerator`'s `requiredOnlyIfAvailableAliasProperties` and `requiredAliasFulfillingProperties` order
			// them. No alias of this scope renames another, so the alias's assignment refers, when the scope declares no
			// property of the fulfilling property's label, to the alias a receive of its fulfilling property resolves to
			// here, whose chain its own scope already resolved.
			if !declaredAliases.isEmpty {
				for (aliasProperty, alias) in declaredAliases where alias.onlyIfAvailable {
					if !scope.providedProperties.contains(where: { $0.label == alias.fulfillingProperty.label }),
					   let enclosingAlias = receivableAliases[alias.fulfillingProperty],
					   enclosingAlias.onlyIfAvailable
					{
						declaredAliases[aliasProperty] = ReceivableAlias(
							fulfillingProperty: alias.fulfillingProperty,
							onlyIfAvailable: true,
							fulfillingOnlyIfAvailableAliases: [.init(property: alias.fulfillingProperty, fulfillingProperty: enclosingAlias.fulfillingProperty)]
								+ enclosingAlias.fulfillingOnlyIfAvailableAliases,
							binding: alias.binding.flatMap { _ in enclosingAlias.binding },
							declaringType: alias.declaringType,
							lastAliasDeclaringType: enclosingAlias.lastAliasDeclaringType,
							lastAliasDeclaringInstantiationStack: enclosingAlias.lastAliasDeclaringInstantiationStack,
						)
					}
				}
			}
			// A required receive of an alias reads the alias, so it needs the alias's fulfilling property built first, as
			// the scope that declares the alias would if the alias were not `onlyIfAvailable`. An `onlyIfAvailable` alias
			// is bound from the aliases it renames in turn, so it needs the property the last is bound from – where that
			// is a property the tree builds. An `onlyIfAvailable` alias bound to `nil` passes the receive `nil`.
			for case let (requiredReceivedProperty, alias?) in scope.requiredReceivedProperties.lazy.map({
				($0, declaredAliases[$0.property] ?? receivableAliases[$0.property])
			}) where validatesCycles {
				let receivedProperty = requiredReceivedProperty.property
				// The aliases the receive requires be created, nearest the receive first, each fulfilled by the next's
				// property.
				let requiredAliases = [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias(property: receivedProperty, fulfillingProperty: alias.fulfillingProperty)]
					+ alias.fulfillingOnlyIfAvailableAliases
				let lastRequiredAlias = requiredAliases[requiredAliases.count - 1]
				let fulfillingProperty = lastRequiredAlias.fulfillingProperty
				// The child of the last alias's declaring scope that this scope is built inside, as the instantiation stack
				// holds it: a lazily instantiated property as the constant it stands for. Where it is the property the last
				// alias is bound from, this scope is built inside the alias's own fulfilling sibling, which cannot be built
				// after the alias. An ancestor still being built, further up, makes the alias `nil` instead.
				let declaringChildIndex = instantiationStack.count - alias.lastAliasDeclaringInstantiationStack.count - 1
				let fulfillingSiblingBeingBuilt = instantiationStack.indices.contains(declaringChildIndex)
					? formsOnStack(of: fulfillingProperty.asValidatedForDependencyCycles).first(where: { $0 == instantiationStack[declaringChildIndex] })
					: nil
				if let fulfillingSiblingBeingBuilt {
					throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
						instantiated: fulfillingSiblingBeingBuilt,
						receivedPropertyChain: requiredAliases.map(\.property.asValidatedForDependencyCycles) + [fulfillingSiblingBeingBuilt],
						declarationLocation: requiredReceivedProperty.declarationLocation,
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: fulfillingProperty,
							validatedPropertiesInCycle: [fulfillingSiblingBeingBuilt],
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: requiredAliases.map(\.property),
						),
						requiredOnlyIfAvailableAliases: alias.onlyIfAvailable ? requiredAliases : [],
					)
				} else if alias.onlyIfAvailable,
				          case .built? = alias.binding,
				          let declaringProperty = alias.lastAliasDeclaringInstantiationStack.first,
				          case let walkedAliasFulfillingProperty = WalkedAliasFulfillingProperty(
				          	fulfillingProperty: fulfillingProperty,
				          	receivedPropertyStack: requiredAliases.map(\.property.asValidatedForDependencyCycles),
				          	lastAliasDeclaringInstantiationStack: alias.lastAliasDeclaringInstantiationStack,
				          	mockRootForwardedProperties: mockRootForwardedProperties,
				          ),
				          walkedAliasFulfillingProperties.insert(walkedAliasFulfillingProperty).inserted
				{
					// A required alias's fulfilling property is walked where the alias is declared. Walk the property
					// the last required alias is bound from there too, since the receive requires it.
					do {
						do {
							try validateNoCycleInReceivedProperties(
								[Scope.RequiredReceivedProperty(
									property: fulfillingProperty,
									aliasProperty: lastRequiredAlias.property,
									declarationLocation: requiredReceivedProperty.declarationLocation,
									identifierRange: nil,
									typeAnnotationRange: nil,
									bareAttributeRange: nil,
								)],
								directParent: alias.lastAliasDeclaringType,
								receivedPropertyStack: requiredAliases.map(\.property.asValidatedForDependencyCycles),
								declaredReceivedPropertyStack: requiredAliases.map(\.property).filter(\.propertyType.isLazilyInstantiated),
								property: declaringProperty,
								instantiationStack: alias.lastAliasDeclaringInstantiationStack,
								lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
								mockRootForwardedProperties: mockRootForwardedProperties,
								// The walk starts where the alias is declared, whose nearest declarations this scope's do not
								// describe: every receive of a property being built there is judged as being built.
								nearestDeclaration: { _ in nil },
							)
						} catch let DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(instantiated, receivedPropertyChain, declarationLocation, lazilyInstantiatedProperties, _) {
							// The chain starts with this receive, which closes it only because it requires the aliases.
							throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
								instantiated: instantiated,
								receivedPropertyChain: receivedPropertyChain,
								declarationLocation: declarationLocation,
								lazilyInstantiatedProperties: lazilyInstantiatedProperties,
								requiredOnlyIfAvailableAliases: requiredAliases,
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
						instantiatedDeclaration: .of(receivedProperty, among: typeDescriptionToFulfillingInstantiableMap),
					))
				}
			}

			if validatesHiddenProperties {
				// A rename of a label this scope's type declares refers to that declaration, before any ancestor's.
				renamesContradictingOwnProperties.formUnion(Self.renamesContradictingOwnProperties(in: scope))
				recordHiddenReceives(
					of: scope,
					closestDeclarationByLabel: closestDeclarationByLabel,
					receivableProperties: receivableProperties,
					propertyStack: propertyStack,
					parentTypeStack: scopeToValidate.parentTypeStack,
					root: root,
				)
			}

			// Check children for cycles.
			var childPropertyStack = propertyStack
			var childParentTypeStack = scopeToValidate.parentTypeStack
			if let property {
				childPropertyStack.insert(property, at: 0)
				childParentTypeStack.insert(scope.instantiable.concreteInstantiable, at: 0)
			}
			for dependency in scope.instantiable.dependencies where validatesCycles && dependency.canCloseDependencyCycle {
				let declaredPropertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
				let propertyForDependency = declaredPropertyForDependency.asValidatedForDependencyCycles
				let closingReceive = Self.closingReceive(of: dependency, in: scope)
				guard let cycleIndex = Self.indexOfEntryClosedOn(
					by: declaredPropertyForDependency,
					of: scope,
					receivedForms: [propertyForDependency],
					closesByReceive: closingReceive != nil,
					propertyStack: childPropertyStack,
					concreteTypeStack: childParentTypeStack,
					nearestDeclaration: nearestDeclaration,
				) else {
					continue
				}
				let propertiesInCycle = [propertyForDependency] + childPropertyStack[0...cycleIndex]
				try throwIfInvalidCycle(
					propertiesInCycle: propertiesInCycle,
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
						propertiesInCycle: [validatedReceivedProperty] + instantiationStack[0...beingBuiltIndex],
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
			var childClosestDeclarationDepthByLabel = scopeToValidate.closestDeclarationDepthByLabel
			enterDeclarations(of: scope, into: &childClosestDeclarationByLabel) {
				childClosestDeclarationDepthByLabel[$0] = instantiationStack.count
			}
			// A property this scope provides shadows an alias of it declared above.
			var childReceivableAliases = receivableAliases.filter {
				!scope.providedProperties.containsPropertyOrItsUnwrappedForm($0.key)
			}
			for (aliasProperty, alias) in declaredAliases {
				childReceivableAliases[aliasProperty] = alias
			}
			// What the scopes this scope builds receive, found only for a scope that builds one, with the depth since which each
			// has been receivable, which the validation of mocks never reads.
			var childReceivableProperties = Set<Property>()
			var childReceivableDepthByProperty = [Property: Int]()
			if scope.propertiesToGenerate.contains(where: { $0.builtScope != nil }) {
				childReceivableProperties = receivableProperties
				childReceivableDepthByProperty = scopeToValidate.receivableDepthByProperty
				insertProperties(madeAvailableBy: scope, given: receivableProperties, instantiationStack: instantiationStack, nearestDeclaration: nearestDeclaration, into: &childReceivableProperties) {
					if !cyclesOnly {
						childReceivableDepthByProperty[$0] = instantiationStack.count
					}
				}
			}
			let firstChildIndex = scopesToValidate.endIndex
			for childPropertyToGenerate in scope.propertiesToGenerate {
				switch childPropertyToGenerate {
				case let .instantiated(declaredChildProperty, childScope, _):
					// A lazily instantiated property is validated as the constant it stands for.
					let childProperty = declaredChildProperty.asValidatedForDependencyCycles
					if let closedOnIndex = childPropertyStack.indices.first(where: {
						childPropertyStack[$0] == childProperty && childParentTypeStack[$0] == childScope.instantiable.concreteInstantiable
					}) {
						// There is a cycle in our scope tree. Do not re-enter it. The type the cycle-closing scope builds
						// receives the nearest declaration of each label, which a scope between it and the scope it closes
						// on can make: the generated code passes that declaration where the tree is built again.
						try validateTreeBuiltAgainByCycle(
							of: childScope,
							for: childProperty,
							closedOnIndex: closedOnIndex,
							cycleClosingScopeParent: scope,
							propertyStack: childPropertyStack,
							parentTypeStack: childParentTypeStack,
							closestDeclarationByLabel: childClosestDeclarationByLabel,
							closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
							// As the tree of any child is given them, without the property it builds.
							receivableProperties: childReceivableProperties.subtracting(childPropertyToGenerate.receivableProperties),
							receivableDepthByProperty: childReceivableDepthByProperty,
							validatesCycles: validatesCycles,
							validatesHiddenProperties: validatesHiddenProperties,
							root: root,
						)
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
						closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
						receivableDepthByProperty: childReceivableDepthByProperty,
						property: childProperty,
						propertyStack: childPropertyStack,
						parentTypeStack: childParentTypeStack,
						lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
					))
				case .aliased, .hole:
					// A hole's tree is a fill's, which the module that fills it validates: the validated scopes hold no
					// hole, since they leave out a dependency no scope builds.
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
						|| rootScope.scope.instantiable.generatesMock
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

		// A rename that names another type than its own type's property of its label is not received from above, so
		// neither its absence there nor a closer declaration of its label is what is wrong with it.
		if !renamesContradictingOwnProperties.isEmpty {
			throw DependencyTreeGeneratorError.renamesContradictingOwnProperties(Array(renamesContradictingOwnProperties))
		}
		if !unfulfillableProperties.isEmpty {
			throw DependencyTreeGeneratorError.unfulfillableProperties(Array(unfulfillableProperties))
		}
		if !hiddenReceivedProperties.isEmpty {
			throw DependencyTreeGeneratorError.hiddenReceivedProperties(Self.reportingEachSeamsChainOnce(hiddenReceivedProperties, seamTypes: generatedSeamTypes))
		}
	}

	/// `hiddenReceivedProperties` without each chain that reaches a receive through a seam this module generates
	/// whose own tree reaches it the same way below the seam: the walk of the seam's tree reports that receive from
	/// the seam's chain, on every path and whatever a caller holds, so the longer chain is the same error again. An
	/// entry is matched by a seam's own entry of the same receive whose chain is strictly shorter, where the seam is
	/// the scope at that depth on the entry's chain and the chains agree below it, between the seam and the receive;
	/// the chains are matched by the concrete types of their scopes, since an entry names each by its property's type
	/// (`ScreenProtocol`, `AnyScreen`), and an entry is dropped only when every chain of scopes it stands for is
	/// matched. Nested seams therefore report the innermost seam's chain, sibling seams each their own, and a chain
	/// that reaches the receive without passing through such a seam keeps its own; since every match is to a strictly
	/// shorter entry, the shortest entries of each receive survive, and no receive loses its report.
	private static func reportingEachSeamsChainOnce(_ hiddenReceivedProperties: [DependencyTreeGeneratorError.HiddenReceivedProperty: Set<[TypeDescription]>], seamTypes: Set<TypeDescription>) -> [DependencyTreeGeneratorError.HiddenReceivedProperty] {
		struct HiddenReceive: Hashable {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			let hidingDeclaration: DependencyTreeGeneratorError.LabelDeclaration
			let receiver: TypeDescription
		}
		typealias Entry = (hidden: DependencyTreeGeneratorError.HiddenReceivedProperty, parentTypeStacks: Set<[TypeDescription]>)
		let entriesByReceive = Dictionary(grouping: hiddenReceivedProperties.map { Entry(hidden: $0.key, parentTypeStacks: $0.value) }) {
			HiddenReceive(property: $0.hidden.property, declarationLocation: $0.hidden.declarationLocation, hidingDeclaration: $0.hidden.hidingDeclaration, receiver: $0.hidden.receiver)
		}
		var reported = [DependencyTreeGeneratorError.HiddenReceivedProperty]()
		for sameReceive in entriesByReceive.values {
			let fromSeams = sameReceive.filter { seamTypes.contains($0.hidden.root) }
			for entry in sameReceive {
				func isReportedFromSeamsChain(_ parentTypeStack: [TypeDescription]) -> Bool {
					fromSeams.contains { fromSeam in
						let depth = fromSeam.hidden.parentStack.count
						return depth < entry.hidden.parentStack.count
							&& parentTypeStack[depth] == fromSeam.hidden.root
							&& Array(entry.hidden.parentStack.prefix(depth)) == fromSeam.hidden.parentStack
							&& fromSeam.parentTypeStacks.contains(Array(parentTypeStack.prefix(depth)))
					}
				}
				if !entry.parentTypeStacks.allSatisfy(isReportedFromSeamsChain) {
					reported.append(entry.hidden)
				}
			}
		}
		return reported
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

	/// Validates that no call of a seam's generated initializer in the trees rooted at `roots` drops a value the tree
	/// holds: a value for a parameter the tier the call reaches omits, or no tier takes, which the receivers inside
	/// the seam would be handed were the tree built inline. Walks each finished generator tree as generation does
	/// (`ScopeGenerator.seamTierOmissions(ofTreeRootedAt:)`), before any code is generated, and reports every finding
	/// of every root, in source order.
	private func validateNoSeamTierOmitsProvidedValue(inTreesRootedAt roots: [RootScopeInfo]) async throws {
		// A module that calls no seam's tier omitting a parameter has nothing to walk. A run that knows of a seam knows
		// its module.
		guard !seams.isEmpty, let emittingModule else { return }
		var omissions = [DependencyTreeGeneratorError.ProvidedValueOmission]()
		for root in roots {
			for omission in await root.scopeGenerator.seamTierOmissions(ofTreeRootedAt: root.instantiable, isOwnFile: emittingModule.isOwnFile) {
				// A provider in a file this run cannot read – another module's, in a build that hands this run that
				// module's declarations but not its files – is reported where this module refers to what leads to the
				// call, naming the provider's module.
				let providerIsReadable = omission.providerDeclarationLocation.map { emittingModule.isReadableFile($0.filePath) } == true
				omissions.append(DependencyTreeGeneratorError.ProvidedValueOmission(
					omission: omission,
					callingType: root.typeDescription,
					location: providerIsReadable ? omission.providerDeclarationLocation : omission.referenceLocation,
					unreadableProviderModuleName: providerIsReadable ? nil : omission.providerDeclaringType.flatMap { typeDescriptionToFulfillingInstantiableMap[$0]?.moduleName },
				))
			}
		}
		if !omissions.isEmpty {
			throw DependencyTreeGeneratorError.seamTierOmitsProvidedValue(omissions)
		}
	}

	/// Validates that every reachable type description has a corresponding `@Instantiable` that production
	/// code can build, reporting every missing type, in source order. A `mockOnly` declaration exists solely
	/// for mock generation, so it does not count. Were it counted, a type it fulfills that shares a concrete
	/// type with a production declaration would be built from whichever declaration a set iteration reached first.
	/// Rejects each of `instantiables` that has two dependencies whose labels `String` equates, which generation, keying
	/// a declaration's dependencies by label, cannot tell apart. See `RepeatedDependencyLabel`. Each is reported, in
	/// source order. Callers pass the declarations a production root's or a mock root's tree builds, whose code is
	/// generated: one no tree reaches traps nowhere, and a shape that works must not become an error.
	private static func validateDependencyLabelsAreDistinct(in instantiables: some Sequence<Instantiable>) throws {
		let errors = instantiables.compactMap { instantiable -> DependencyTreeGeneratorError? in
			var firstDependencyByLabel = [String: Dependency]()
			var repeatedDependencyLabels = [DependencyTreeGeneratorError.RepeatedDependencyLabel]()
			for dependency in instantiable.dependencies {
				if let earlierDependency = firstDependencyByLabel[dependency.property.label] {
					repeatedDependencyLabels.append(DependencyTreeGeneratorError.RepeatedDependencyLabel(
						declaringType: instantiable.concreteInstantiable,
						earlierDependency: earlierDependency,
						laterDependency: dependency,
					))
				} else {
					firstDependencyByLabel[dependency.property.label] = dependency
				}
			}
			return repeatedDependencyLabels.isEmpty ? nil : .repeatedDependencyLabels(repeatedDependencyLabels)
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
	}

	/// Rejects each of `instantiables` that declares a rename the `@Instantiable` macro rejects. See `RejectedRename`.
	/// Each is reported, in source order. Callers pass the declarations a production root's or a mock root's tree
	/// builds, before any validation walk of that tree reads their dependencies, so that nothing after this sees such a
	/// rename: the renames of one declaration are each fulfilled by a property it receives or declares as no rename, or
	/// retype the label they keep.
	private static func validateRenamesAreSpelledAsTheMacroAccepts(in instantiables: some Sequence<Instantiable>) throws {
		let errors = instantiables.compactMap { instantiable -> DependencyTreeGeneratorError? in
			let rejectedRenames = rejectedRenames(declaredBy: instantiable)
			return rejectedRenames.isEmpty ? nil : .rejectedRenames(rejectedRenames)
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
	}

	/// Rejects each declaration that the validation of the trees rooted at `rootScopes` reads and that declares a rename
	/// the `@Instantiable` macro rejects, as `validateRenamesAreSpelledAsTheMacroAccepts(in:)` does: the declarations of
	/// the scopes each tree instantiates, and of the scopes the received-dependency walk follows a required received
	/// property to – the scope of that property's type – which the walk reads without a tree building them. A
	/// declaration with a rejected rename is reported, and the received properties it requires are not followed.
	private static func validateRenamesAreSpelledAsTheMacroAccepts(
		inTreesRootedAt rootScopes: [Scope],
		typeDescriptionToScopeMap: [TypeDescription: Scope],
	) throws {
		var errors = [DependencyTreeGeneratorError]()
		var visitedScopes = Set<ObjectIdentifier>()
		var scopesToVisit = rootScopes
		while let scope = scopesToVisit.popLast() {
			guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
				scopesToVisit.append(childScope)
			}
			let rejectedRenames = rejectedRenames(declaredBy: scope.instantiable)
			guard rejectedRenames.isEmpty else {
				errors.append(.rejectedRenames(rejectedRenames))
				continue
			}
			for requiredReceivedProperty in scope.requiredReceivedProperties {
				if let receivedPropertyScope = typeDescriptionToScopeMap[requiredReceivedProperty.property.asValidatedForDependencyCycles.typeDescription] {
					scopesToVisit.append(receivedPropertyScope)
				}
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
	}

	/// The renames `instantiable` declares that the `@Instantiable` macro rejects, in declaration order.
	private static func rejectedRenames(declaredBy instantiable: Instantiable) -> [DependencyTreeGeneratorError.RejectedRename] {
		var renameLabels = Set<String>()
		for dependency in instantiable.dependencies where dependency.source.fulfillingProperty != nil {
			renameLabels.insert(dependency.property.label)
		}
		guard !renameLabels.isEmpty else { return [] }
		var rejectedRenames = [DependencyTreeGeneratorError.RejectedRename]()
		for dependency in instantiable.dependencies {
			let spelling: DependencyTreeGeneratorError.RejectedRename.Spelling
			switch dependency.source {
			case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
				let property = dependency.property
				if fulfillingProperty.label != property.label {
					guard renameLabels.contains(fulfillingProperty.label) else { continue }
					spelling = .renameOfRename(sourceLabel: fulfillingProperty.label, declaringType: instantiable.concreteInstantiable)
				} else if onlyIfAvailable,
				          !erasedToConcreteExistential,
				          fulfillingProperty.typeDescription == property.typeDescription
				          || fulfillingProperty.typeDescription == property.typeDescription.unwrapped
				{
					spelling = .renameOfItselfOnlyIfAvailable
				} else if fulfillingProperty == property {
					spelling = .renameOfItselfWithSameType
				} else {
					// A rename that keeps its label and changes its type retypes the property of that label above it.
					continue
				}
			case .instantiated, .received, .forwarded:
				continue
			}
			rejectedRenames.append(DependencyTreeGeneratorError.RejectedRename(
				property: dependency.property,
				spelling: spelling,
				declarationLocation: dependency.declarationLocation,
			))
		}
		return rejectedRenames
	}

	private func validateReachableTypeDescriptions() throws {
		// In a module that holds or calls a seam, only the types reached outside every seam's tree are reported
		// (`typesReachableOutsideSeamTrees`). A type reached only beneath a seam another module declares may be one
		// this module cannot see, which the seam's module could: it is left to that module to report, and the
		// generated call fails to compile where the two disagree. A type a seam's tree reaches that no production
		// declaration fulfills is a hole, whose builder the seam's generated initializer takes, unless only
		// hand-written code could build it; a root that calls the seam and cannot fill the builder is reported where
		// its tree is generated.
		let unbuildableTypeDescriptions = (seams.isEmpty ? reachableTypeDescriptions : try typesReachableOutsideSeamTrees())
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
			let referencingProperties = Array(referencingPropertiesByType[unbuildableTypeDescription, default: []])
			return DependencyTreeGeneratorError.noInstantiableFound(
				unbuildableTypeDescription,
				referencedBy: referencingProperties,
				fulfilledByMockOnlyDeclaration: typeDescriptionToFulfillingInstantiableMap[unbuildableTypeDescription] != nil,
				unreadImports: unreadImports.map { unreadImports in
					DependencyTreeGeneratorError.UnreadImportsOfFiles(
						integration: unreadImports.integration,
						importsModuleNotReadByFilePath: Set(referencingProperties.compactMap(\.declarationLocation?.filePath)).reduce(into: [:]) { importsModuleNotReadByFilePath, filePath in
							importsModuleNotReadByFilePath[filePath] = unreadImports.importsModuleNotRead(filePath)
						},
					)
				},
				viewDeclaringModule: typeDescriptionToFulfillingInstantiableMap[unbuildableTypeDescription] == nil ? viewDeclaringModules[unbuildableTypeDescription] : nil,
			)
		})
	}
}

// MARK: - DependencyTreeGenerator.ExtendedTypeDeclarations

extension DependencyTreeGenerator {
	/// The declarations among which the declaration of a type an extension extends bounds the types declared in or by
	/// that extension: the `@Instantiable` declarations the module reads, and the plain type declarations of each
	/// module that declares them.
	fileprivate struct ExtendedTypeDeclarations: Sendable {
		/// - Parameters:
		///   - instantiables: Every type the `@Instantiable` declarations the module reads fulfill, mapped to the
		///     declaration that fulfills it.
		///   - plainTypeDeclarations: The plain type declarations of the modules whose declarations the module reads,
		///     each module's in the order of its files and, within a file, in source order.
		init(instantiables: [TypeDescription: Instantiable], plainTypeDeclarations: [PlainTypeDeclaration]) {
			self.instantiables = instantiables
			var plainTypeDeclarationsByModuleAndType = [ModuleAndType: [PlainTypeDeclaration]]()
			for plainTypeDeclaration in plainTypeDeclarations {
				// A declaration whose module SafeDITool does not know bounds no extension's types, as an `@Instantiable`
				// declaration of the extended type does not.
				guard let moduleName = plainTypeDeclaration.moduleName else { continue }
				plainTypeDeclarationsByModuleAndType[ModuleAndType(moduleName: moduleName, type: plainTypeDeclaration.typeDescription), default: []].append(plainTypeDeclaration)
			}
			self.plainTypeDeclarationsByModuleAndType = plainTypeDeclarationsByModuleAndType
		}

		let instantiables: [TypeDescription: Instantiable]

		/// The declarations whose access bounds the types an extension of `extendedType` in the module named `moduleName`,
		/// in the file at `sourceFilePath`, declares, outermost first: those of `extendedType`'s declaration in that module
		/// and the type declarations enclosing it in its file – its `@Instantiable` declaration when it has one, and
		/// otherwise its plain declaration (`plainTypeDeclaration(of:inModuleNamed:preferringFileAt:)`) – and, when that
		/// declaration is itself inside an extension, the declarations that bound the types that extension declares, found
		/// the same way from the declaration's file, and so on. A type the module does not declare ends the walk, and the
		/// compiler checks it: an extension of a type another module declares narrower than the extension's module can see
		/// cannot be written, and a declaration of the type's name in another module could be a namesake of the extended
		/// type, the narrowest of which would then fail a construction that compiles. Each type the walk follows is the one
		/// before it without at least its last name, so the walk ends.
		func accessNeeds(boundingTypesAnExtensionOf extendedType: TypeDescription, declaresInModuleNamed moduleName: String, fromFileAt sourceFilePath: String?) -> [AccessNeed] {
			var accessNeeds = [AccessNeed]()
			var link: (type: TypeDescription, sourceFilePath: String?)? = (extendedType, sourceFilePath)
			while case let (type, sourceFilePath)? = link {
				if let extended = instantiables[type], extended.concreteInstantiable == type, !extended.declarationType.isExtension {
					// An `@Instantiable` extended type of another module ends the walk too.
					guard extended.moduleName == moduleName else { break }
					accessNeeds = extended.accessNeeds(constructingWithMockMethod: false).filter { $0.declaration.declaredType != nil } + accessNeeds
					link = extended.extendedType.map { ($0, extended.sourceFilePath) }
				} else if let declaration = plainTypeDeclaration(of: type, inModuleNamed: moduleName, preferringFileAt: sourceFilePath) {
					accessNeeds = declaration.accessNeeds + accessNeeds
					link = declaration.extendedType.map { ($0, declaration.sourceFilePath) }
				} else {
					link = nil
				}
			}
			return accessNeeds
		}

		/// The plain declaration of `type` in the module named `moduleName`: among those in the file at `sourceFilePath`
		/// when that file declares one, as a `private` type of one file can share its name with a type of another,
		/// and otherwise among those visible outside their file (`PlainTypeDeclaration.isVisibleOutsideItsFile`): a
		/// `private` type of another file cannot be what the extension extends, while an imported type of its name can.
		/// Of several, which clauses of a platform-conditioned block declare, the narrowest, which every clause the
		/// compiler may select must allow, and of equally narrow ones the first, in the order of the module's files and
		/// within a file in source order. `nil` when there is none, which leaves the extended type to the compiler, as an
		/// unrecorded one is.
		func plainTypeDeclaration(of type: TypeDescription, inModuleNamed moduleName: String, preferringFileAt sourceFilePath: String?) -> PlainTypeDeclaration? {
			let candidates = plainTypeDeclarationsByModuleAndType[ModuleAndType(moduleName: moduleName, type: type)] ?? []
			// Two declarations whose files are unknown are not known to share one.
			let inPreferredFile = candidates.filter { sourceFilePath != nil && $0.sourceFilePath == sourceFilePath }
			return (inPreferredFile.isEmpty ? candidates.filter(\.isVisibleOutsideItsFile) : inPreferredFile)
				.enumerated()
				.min { lhs, rhs in
					(AccessLevel.normalized(lhs.element.levelBeforeExtendedTypeCap), lhs.offset) < (AccessLevel.normalized(rhs.element.levelBeforeExtendedTypeCap), rhs.offset)
				}?
				.element
		}

		/// A module and a type, by the key a plain declaration of the type is recorded under
		/// (`TypeDescription.plainDeclarationKey`).
		private struct ModuleAndType: Hashable {
			init(moduleName: String, type: TypeDescription) {
				self.moduleName = moduleName
				typeKey = type.plainDeclarationKey
			}

			let moduleName: String
			let typeKey: String
		}

		private let plainTypeDeclarationsByModuleAndType: [ModuleAndType: [PlainTypeDeclaration]]
	}
}

// MARK: - DependencyTreeGenerator.EmittingModule

extension DependencyTreeGenerator.EmittingModule {
	/// The module that declares `accessNeed`, a declaration that constructing `instantiable` relies on: the module
	/// that declares the type's hand-written mock method for that method, or the extension it takes its level from,
	/// and the module that declares the type otherwise.
	fileprivate func declaringModule(of accessNeed: AccessNeed, constructing instantiable: Instantiable) -> ModuleIdentity {
		if accessNeed.isDeclaredWithMockMethod {
			ModuleIdentity(moduleName: instantiable.mockDeclarationModuleName, packageName: instantiable.mockDeclarationPackageName)
		} else {
			ModuleIdentity(moduleName: instantiable.moduleName, packageName: instantiable.packageName)
		}
	}

	/// The access `accessNeed`, a declaration that constructing `instantiable` relies on, needs for this module's
	/// generated code to construct `instantiable`.
	fileprivate func requirement(of accessNeed: AccessNeed, constructing instantiable: Instantiable) -> AccessRequirement {
		let declarationFilePath = accessNeed.isDeclaredWithMockMethod ? instantiable.mockDeclarationLocation?.filePath : instantiable.sourceFilePath
		return AccessLevel.required(
			toConstructFrom: identity,
			declaredIn: declaringModule(of: accessNeed, constructing: instantiable),
			isOwnFile: declarationFilePath.map(isOwnFile) ?? false,
		)
	}
}

// MARK: - Instantiable

extension Instantiable {
	/// The type the extension this declaration is inside extends – the type enclosing the outermost type declaration of
	/// its file, which is directly inside the extension – or, for an `@Instantiable` extension, the type it declares; `nil`
	/// for a declaration outside every extension.
	fileprivate var extendedType: TypeDescription? {
		// The extended type is the one the declaring module's declarations name, as its own name there records it.
		let declaredType = declaredName ?? concreteInstantiable
		return if declarationType.isExtension {
			declaredType
		} else if enclosingExtensionAccess != nil {
			(0...enclosingTypeAccess.count).reduce(declaredType as TypeDescription?) { type, _ in type?.popNested }
		} else {
			nil
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
		     .variadic,
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
