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
	///   - compilesGeneratedMocks: Whether the build compiles the generated mocks
	///     (`ConditionalCompilationEvaluator.compilesGeneratedMocks`). A call of a hand-written mock, or a calling mock's
	///     fill of a place it cannot fill, that a build compiles no generated mock in is never compiled, so each is checked
	///     only where they are compiled.
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
		compilesGeneratedMocks: Bool,
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
		self.compilesGeneratedMocks = compilesGeneratedMocks
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
		if let observer = HeldCodeTasks.observer {
			for rootInfo in rootScopeGenerators {
				let heldTaskCount = await rootInfo.scopeGenerator.codeTasksHeldInTree()
				observer(heldTaskCount)
			}
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
					: "// SafeDI generates \(rootType)’s init() only in \(declaringModule). If \(rootType)() does not compile, add the SafeDI plugin to the target that declares \(rootType).",
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

	/// `publicMockContext`, once made.
	var memoizedPublicMockContext: PublicMockContext?

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

	// MARK: Private

	let importStatements: [ImportStatement]
	let mockImportStatements: [ImportStatement]
	/// How the imports of each generated file spell their access levels.
	private let importAccess: GeneratedImportAccess
	/// How the imports of a generated file spell their access levels once the module's own files are known to spell the
	/// given ones, which `importAccess` is without any.
	private let importAccessSpellingOwnLevels: @Sendable ([String: Set<AccessLevel>]) -> GeneratedImportAccess
	private let readOwnFiles: (@Sendable () async -> FulfillerImports.OwnFiles)?
	/// What the first generated file that would gain an import had read, since every later one asks the same.
	private var ownFilesRead: OwnFilesRead?
	let typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
	let aliasDeclarationReferences: AliasDeclarationReferences
	/// See `init`.
	let compilesGeneratedMocks: Bool
	let emittingModule: EmittingModule?
	let unreadImports: UnreadImports?
	let seams: SeamResolution
	/// The declarations of types that are not `@Instantiable` this generator was given, which a generator computing
	/// another module's view is given too.
	let plainTypeDeclarations: [PlainTypeDeclaration]
	/// The names the modules SafeDI read declare types by at file scope (`namesOfTypesDeclaredAtFileScope`).
	let declaredTypeNames: DeclaredTypeNames
	/// See `init`'s `viewInstantiablesByModuleName`.
	let viewInstantiablesByModuleName: [String: [Instantiable]]
	/// See `init`'s `viewDeclaringModules`.
	let viewDeclaringModules: [TypeDescription: ViewDeclaringModule]
	/// The declarations among which the declaration of a type an extension extends bounds the types declared in or by
	/// that extension.
	let extendedTypeDeclarations: ExtendedTypeDeclarations
	struct RootScopeInfo {
		let typeDescription: TypeDescription
		let instantiable: Instantiable
		let sourceFilePath: String?
		let scopeGenerator: ScopeGenerator
	}

	/// The scopes of the dependency tree `rootScopeGenerators` last built and validated, which
	/// `generateWarnings()` analyzes. Empty until the tree has been generated.
	var validatedScopes = Set<Scope>()

	var rootScopeGenerators: [RootScopeInfo] {
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
				do {
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
				} catch let error as DependencyTreeGeneratorError {
					// The trees build each foreign seam inline with the fills of its holes, which the seam's module calls
					// through its builders. Only membership in what each fill declares is read, so the seams' order is moot.
					let foreignSeamHoles = try foreignSeamRoots.get().compactMapValues { $0?.signature.holes }
					throw error.markingCyclesClosedInSeamFills(DependencyTreeGeneratorError.SeamFillDeclarations.ofFills(ofHolesOf: foreignSeamHoles, in: typeDescriptionToScopeMap))
				}
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
	static func validateCycleLabelsArePassable(inTreesRootedAt generators: [ScopeGenerator]) throws {
		let unpassableCycleLabels = generators.flatMap(\.unpassableCycleLabelsInTree).uniqued()
		if let error = DependencyTreeGeneratorError.reportingAll(of: unpassableCycleLabels.map(DependencyTreeGeneratorError.unpassableCycleLabel)) {
			throw error
		}
	}

	/// Whether every declaration any generated code could construct, with any of the methods that construct it, is
	/// `public` or `open` where it is declared, which code in every module can use. No construction then needs to be
	/// checked, which is the case for a project whose types are all `public`.
	lazy var constructsOnlyPublicDeclarations: Bool = typeDescriptionToFulfillingInstantiableMap.values.allSatisfy { instantiable in
		Self.isPubliclyConstructible(instantiable, withMockMethod: false, extendedTypes: extendedTypeDeclarations)
			&& (instantiable.mockInitializer == nil || Self.isPubliclyConstructible(instantiable, withMockMethod: true, extendedTypes: extendedTypeDeclarations))
	}

	/// The emitting module whose constructions need checking, or `nil` when none do: no module was given, or every
	/// declaration any generated code could construct is `public` or `open`.
	lazy var emittingModuleToCheck: EmittingModule? = constructsOnlyPublicDeclarations ? nil : emittingModule

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
	func rootScopesThisModuleGenerates(
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
		// A calling mock whose fill of a called public mock's place makes such a construction passes the place up and is
		// accepted instead, a deliberate gap accepted for now that the calling-mock mirror work in 2.3.1 closes
		// (`holesFilled(byCallsOf:in:)`, `seam-and-mock-contract.md`, rule 7).
		guard inaccessibleConstructions.isEmpty else {
			throw DependencyTreeGeneratorError.inaccessibleConstructions(inaccessibleConstructions)
		}
		self.rootsOfOtherModules = rootsOfOtherModules
		return rootScopesToGenerate
	}

	/// The roots another module declares, in type order, whose `init()` that module generates rather than this one.
	/// Empty until the tree has been generated.
	private var rootsOfOtherModules = [Instantiable]()

	/// The generators of the modules whose public mocks this module's mock trees call, by module name.
	var publicMockGeneratorsByModuleName = [String: DependencyTreeGenerator]()

	/// The mock scopes `publicMockPlan(ofOwnType:)` builds its mock roots from, once built.
	var memoizedPublicMockPlanScopes: MockScopes?

	// MARK: Seams

	/// The concrete types of the seams this module generates the initializers of: those declared in its own files,
	/// among the declarations it reads.
	lazy var generatedSeamTypes: Set<TypeDescription> = Set(
		typeDescriptionToFulfillingInstantiableMap
			.values
			.filter { $0.generatesDependencyTree && seams.generatedSeams.contains($0.concreteInstantiable) }
			.map(\.concreteInstantiable),
	)

	/// The types at the roots of the trees validation walks: the roots of the dependency tree and the seams this
	/// module generates, whose trees it validates as it validates a root's, with what each tree receives from outside
	/// the seam fulfilled by the seam's parameters.
	lazy var validatedRootInstantiables: Set<TypeDescription> = rootInstantiables.union(generatedSeamTypes)

	/// `foreignSeamRoots`, once computed.
	var memoizedForeignSeamRoots: Result<[TypeDescription: ScopeGenerator.SeamRoot?], any Error>?

	/// `seamRoots`, once computed.
	var memoizedSeamRoots: Result<[TypeDescription: ScopeGenerator.SeamRoot?], any Error>?

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

	/// A collection of `@Instantiable`-decorated types that are at the roots of their respective dependency trees.
	lazy var rootInstantiables: Set<TypeDescription> = Set(
		typeDescriptionToFulfillingInstantiableMap
			.values
			.filter(\.isRoot)
			.map(\.concreteInstantiable),
	)

	/// A collection of `@Instantiable`-decorated types that are instantiated by at least one other
	/// `@Instantiable`-decorated type or do not explicitly receive dependencies, including those reached only beneath
	/// a seam another module declares.
	lazy var reachableTypeDescriptions: Set<TypeDescription> = typesReachable(fromRoots: validatedRootInstantiables)
}

// MARK: - Instantiable

extension Instantiable {
	/// The type the extension this declaration is inside extends – the type enclosing the outermost type declaration of
	/// its file, which is directly inside the extension – or, for an `@Instantiable` extension, the type it declares; `nil`
	/// for a declaration outside every extension.
	var extendedType: TypeDescription? {
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
	var isInstantiated: Bool {
		switch source {
		case .instantiated:
			true
		case .aliased, .forwarded, .received:
			false
		}
	}

	var isForwarded: Bool {
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
	var canCloseDependencyCycle: Bool {
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
	func containsPropertyOrItsUnwrappedForm(_ property: Property) -> Bool {
		contains(property) || contains(property.asUnwrappedProperty)
	}
}

// MARK: - TypeDescription

extension TypeDescription {
	var leastQualifiedTypeDescription: TypeDescription {
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
	func recordingLazilyInstantiated(_ declaredProperty: Property) -> Self {
		guard declaredProperty.propertyType.isLazilyInstantiated else { return self }
		var lazilyInstantiatedDeclarations = self
		lazilyInstantiatedDeclarations[declaredProperty.asValidatedForDependencyCycles] = declaredProperty
		return lazilyInstantiatedDeclarations
	}
}
