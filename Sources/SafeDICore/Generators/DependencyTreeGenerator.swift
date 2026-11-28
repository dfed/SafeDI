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
	///     (`ConditionalCompilationEvaluator.compilesGeneratedMocks`). A call of a hand-written mock, a calling mock's fill
	///     of a place it cannot fill, and a calling mock's fill that a called public mock hands only an optional wrapper of
	///     a value the fill requires, that a build compiles no generated mock in are never compiled, so each is checked
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
	///   - unfulfilledReceiveLocations: Where each received dependency and alias is declared that the trees are built
	///     around although nothing provides it: `validatePropertiesAreFulfillable` reports no such dependency as
	///     unfulfillable. Only `query graph` passes any, to read what the other receives of a graph mid-edit are handed
	///     (`receivedValueSupplies()`); `generate` passes none, and reports every one.
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
		unfulfilledReceiveLocations: Set<Dependency.DeclarationLocation> = [],
	) {
		self.unreadImports = unreadImports
		self.unfulfilledReceiveLocations = unfulfilledReceiveLocations
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
		// What the declarations spell is interned first, in the order of their keys, which no arrival order decides. The
		// order assigns the IDs, which only an `==` reads, never output: the tests intern in other orders to show it.
		internerSpace = ConstructionInternerSpace(declarationsOf: Self.declarationsInInterningOrder(of: typeDescriptionToFulfillingInstantiableMap))
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
		/// The plan of each public mock the module's own files declare, sorted by type, as a module that calls the mock
		/// reads it, which the module's module info carries (`SeamResolution.ForeignPublicMock.storedPlans`); empty unless
		/// the request stores them (`MockRequest.storesPublicMockPlans`).
		public let storedPublicMockPlans: [StoredPublicMockPlan]
	}

	/// The code a generated file holds, which decides what its header imports.
	public enum GeneratedFileContent: Sendable {
		/// Dependency-tree code. Each case holds its code as a function, which the header calls only where the file's
		/// imports spell levels, since a module's whole output can be tens of megabytes to join.
		case dependencyTree(code: @Sendable () -> String)
		/// Mock code, as each generated mock file and the shared mock configuration file hold, which only builds in
		/// which `mockConditionalCompilation` is active compile, or every build when it is `nil`.
		case mock(code: @Sendable () -> String, mockConditionalCompilation: String?)
		/// Both dependency-tree code and mock code, as one file that holds a module's whole output does.
		case dependencyTreeAndMock(dependencyTreeCode: @Sendable () -> String, mockCode: @Sendable () -> String, mockConditionalCompilation: String?)
	}

	/// A generated file whose header `fileHeaders(for:)` makes: its code, and the types the trees it holds build that the
	/// properties they are built for do not name.
	public struct GeneratedFile: Sendable {
		public init(content: GeneratedFileContent, fulfillers: Set<FulfillerImports.Fulfiller>) {
			self.content = content
			self.fulfillers = fulfillers
		}

		public let content: GeneratedFileContent
		public let fulfillers: Set<FulfillerImports.Fulfiller>
	}

	/// The file header to prepend to each of `files`, in their order: the imports its content needs, each spelling the
	/// access level the file's declarations need where they compile (`GeneratedImportAccess`). Every file of a run is
	/// asked for in one call, so that what the module's own files say is read at most once, by the first file that would
	/// gain an import for a fulfiller, and kept for the others in a local of this call.
	public func fileHeaders(for files: [GeneratedFile]) async -> [String] {
		var ownFilesRead: OwnFilesRead?
		var headers = [String]()
		for file in files {
			let imports = switch file.content {
			case let .dependencyTree(code):
				await imports(importStatements, building: file.fulfillers, forUnconditionalCode: code, mockCode: nil, ownFilesRead: &ownFilesRead)
			case let .mock(code, mockConditionalCompilation):
				if let mockConditionalCompilation {
					await imports(mockImportStatements, building: file.fulfillers, forUnconditionalCode: { "" }, mockCode: (code, mockConditionalCompilation), ownFilesRead: &ownFilesRead)
				} else {
					await imports(mockImportStatements, building: file.fulfillers, forUnconditionalCode: code, mockCode: nil, ownFilesRead: &ownFilesRead)
				}
			case let .dependencyTreeAndMock(dependencyTreeCode, mockCode, mockConditionalCompilation):
				if let mockConditionalCompilation {
					await imports(importStatements + mockImportStatements, building: file.fulfillers, forUnconditionalCode: dependencyTreeCode, mockCode: (mockCode, mockConditionalCompilation), ownFilesRead: &ownFilesRead)
				} else {
					await imports(importStatements + mockImportStatements, building: file.fulfillers, forUnconditionalCode: { dependencyTreeCode() + "\n\n" + mockCode() }, mockCode: nil, ownFilesRead: &ownFilesRead)
				}
			}
			headers.append(Self.fileHeader(importing: imports))
		}
		return headers
	}

	/// What a run of `generate` asks `generate(_:)` for.
	public struct GenerationRequest: Sendable {
		/// - Parameters:
		///   - generatesDependencyTrees: Whether to generate the code of the roots and seams this module generates, and the
		///     warnings about their trees.
		///   - mocks: What to generate mocks with, or `nil` to generate none.
		///   - generatesDOTTree: Whether to draw the roots' and seams' trees as a DOT graph.
		///   - namesNodeRecordRefusals: Whether the report of what forced each tree (`GenerationResults.treeForcers`) names,
		///     for each root of a module with seams, the kind node records refuse its world with, which only a measurement
		///     reads: making the records costs a run that builds the tree anyway.
		public init(generatesDependencyTrees: Bool, mocks: MockRequest?, generatesDOTTree: Bool, namesNodeRecordRefusals: Bool = false) {
			self.generatesDependencyTrees = generatesDependencyTrees
			self.mocks = mocks
			self.generatesDOTTree = generatesDOTTree
			self.namesNodeRecordRefusals = namesNodeRecordRefusals
		}

		public let generatesDependencyTrees: Bool
		public let mocks: MockRequest?
		public let generatesDOTTree: Bool
		public let namesNodeRecordRefusals: Bool
	}

	/// What `generate(_:)` generates mocks with.
	public struct MockRequest: Sendable {
		/// - Parameters:
		///   - mockConditionalCompilation: The condition the generated mocks compile under, or `nil` for every build.
		///   - currentModuleSourceFilePaths: The module's own files, whose `generateMock` types get a mock, or `nil` when
		///     every file is the module's.
		///   - additionalMocksToGenerate: The names of the types whose mocks are generated because they are listed.
		///   - storesPublicMockPlans: Whether the result holds the plan of each public mock the module declares, which a
		///     run that writes a module info file stores in it.
		public init(mockConditionalCompilation: String?, currentModuleSourceFilePaths: Set<String>? = nil, additionalMocksToGenerate: Set<String> = [], storesPublicMockPlans: Bool = false) {
			self.mockConditionalCompilation = mockConditionalCompilation
			self.currentModuleSourceFilePaths = currentModuleSourceFilePaths
			self.additionalMocksToGenerate = additionalMocksToGenerate
			self.storesPublicMockPlans = storesPublicMockPlans
		}

		public let mockConditionalCompilation: String?
		public let currentModuleSourceFilePaths: Set<String>?
		public let additionalMocksToGenerate: Set<String>
		public let storesPublicMockPlans: Bool
	}

	/// What `generate(_:)` generated.
	public struct GenerationResults: Sendable {
		/// The code of each root and seam this module generates, then a file for each root another module declares;
		/// empty unless the request generates dependency trees.
		public let generatedRoots: [GeneratedRoot]
		/// Warnings about trees that generate successfully, which `SafeDITool generate` returns rather than throwing; empty
		/// unless the request generates dependency trees.
		public let warnings: [SourceDiagnostic]
		/// The mocks, or `nil` when the request generates none.
		public let mocks: MockGenerationResult?
		/// The DOT graph of the roots' and seams' trees, or `nil` when the request draws none.
		public let dotTree: String?
		/// The signature of each seam this module generates, sorted by seam, which its module info carries for the
		/// modules that call the seams (`SeamResolution.ForeignSeam.storedSignature`); empty unless the request generates
		/// dependency trees, so a module info written without them makes its callers compute the signatures.
		public let storedSeamSignatures: [StoredSeamSignature]
		/// What made this run build each root's and seam's tree (`TreeForcer`); empty unless the request builds trees.
		public let treeForcers: TreeForcerReport
	}

	/// Generates what `request` asks for, building each layer of the work once, in order, and handing it down as a value:
	/// the trees of the roots and seams, once, which their code, their warnings and the DOT graph all read; then the mocks.
	/// The first error, in that order, is thrown: an error in the roots' and seams' trees before any mock is built.
	///
	/// The trees of the roots and seams are validated and built serially on this actor, and their code is generated by a task group, one child per tree; the mock roots are planned serially
	/// and their code is generated by a task group, one child per mock root.
	public func generate(_ request: GenerationRequest) async throws -> GenerationResults {
		let buildsDependencyTrees = request.generatesDependencyTrees || request.generatesDOTTree
		let declaresPublicMock = typeDescriptionToFulfillingInstantiableMap.values.contains(where: { $0.generateMock == .public })
		// The proof of every type's access over the module's declarations, which the public mock context and the
		// signatures of the module's own seams share, built once, when the first of them reads it.
		let ownAccessProof = ownAccessProof()
		// The context the module's public mocks share, whose comment the initializers of its seams carry too, made once
		// when either is generated.
		let publicMockContext: PublicMockContext? = if (declaresPublicMock && request.mocks != nil) || (buildsDependencyTrees && !seams.isEmpty && !generatedSeamTypes.isEmpty) {
			makePublicMockContext(proof: ownAccessProof.proof)
		} else {
			nil
		}
		// The report of what forced each tree names what node records refuse of each seam world's root, which reads the
		// root's scope once its tree is built.
		let trees = try await buildsDependencyTrees
			? RootScopeInfo.$keepsRootScopes.withValue(request.namesNodeRecordRefusals) {
				try await dependencyTrees(unreadTypeComment: publicMockContext?.unreadTypeComment, ownAccessProof: ownAccessProof, readersOfEveryTree: request.generatesDOTTree ? [.reader(.dotGraph)] : [])
			}
			: nil
		// The checks run in this task, not the one that plans the code: their walks are as deep as the trees, and a task
		// frees the memory its frames took when it ends, which on a deep module took as long as releasing the trees.
		if request.generatesDependencyTrees, let trees {
			try await validateBeforeGeneratingCode(of: trees.roots)
		}
		// The roots' plans generate in a child task while the warnings and the DOT graph are made from the same trees.
		// The mocks are made only once the trees are released, so a module's root trees and its mock trees are never held
		// at once: making them beside the plans raised a mock-heavy module's peak memory by a fifth.
		let treeForcers = TreeForcerReport(forcersByRoot: trees?.roots.map { root in
			(root: root.instantiable.concreteInstantiable.asSource, forcers: root.treeForcers + (request.namesNodeRecordRefusals ? Self.nodeRecordRefusal(ofSeamWorldRoot: root, declaredTypeNames: declaredTypeNames) : []))
		} ?? [])
		let storedSeamSignatures = if request.generatesDependencyTrees, let trees {
			trees.storedSeamSignatures
		} else {
			[StoredSeamSignature]()
		}
		let plans: [PlannedRoot]
		let warnings: [SourceDiagnostic]
		let drawnTree: String?
		do {
			// The trees as the work below reads them, released at the end of this block, or as an error in the roots' and
			// seams' code leaves it, which is reported before any mock is built.
			let trees = trees
			(plans, warnings, drawnTree) = try await withThrowingTaskGroup(
				of: [PlannedRoot].self,
				returning: ([PlannedRoot], [SourceDiagnostic], String?).self,
			) { taskGroup in
				if request.generatesDependencyTrees, let trees {
					taskGroup.addTask { [roots = trees.roots, rootsOfOtherModules = trees.rootsOfOtherModules] in
						try await self.plannedCode(of: roots, rootsOfOtherModules: rootsOfOtherModules)
					}
				}
				let warnings = if let trees, request.generatesDependencyTrees {
					trees.warnings
				} else {
					[SourceDiagnostic]()
				}
				// Drawn from the trees the code is generated from, before any mock is built. Drawing a tree throws nothing.
				let drawnTree: String? = if let trees, request.generatesDOTTree {
					await generateDOTTree(of: trees.roots)
				} else {
					nil
				}
				let plans = try await taskGroup.next() ?? []
				return (plans, warnings, drawnTree)
			}
		}
		// A read, not an assignment, so the optimizer cannot keep the trees past this point.
		_ = consume trees
		// The roots' plans are spelled in a child task while the mocks are made.
		async let roots = Self.spelled(plans)
		var mocks: MockGenerationResult?
		if let mockRequest = request.mocks {
			mocks = try await generateMockCode(
				mockConditionalCompilation: mockRequest.mockConditionalCompilation,
				currentModuleSourceFilePaths: mockRequest.currentModuleSourceFilePaths,
				additionalMocksToGenerate: mockRequest.additionalMocksToGenerate,
				storesPublicMockPlans: mockRequest.storesPublicMockPlans,
				publicMockContext: declaresPublicMock ? publicMockContext : nil,
			)
		}
		return await GenerationResults(generatedRoots: roots, warnings: warnings, mocks: mocks, dotTree: drawnTree, storedSeamSignatures: storedSeamSignatures, treeForcers: treeForcers)
	}

	/// Runs every whole-module check of `roots`, the trees this module generates, which their code needs to pass.
	private func validateBeforeGeneratingCode(of roots: [RootScopeInfo]) async throws {
		// A root laid out from its node records has no tree, and needs none of these checks: node records refuse a world
		// with a fill (`fill`) or a seam call (`construction`), and one whose `@Sendable` function captures a wrapper that is
		// not `Sendable` (`sendableFunctionCapturesWrapper`), so each such root keeps its tree.
		try Self.validateFills(
			inTreesRootedAt: roots.compactMap(\.scopeGenerator),
			callerModule: seams.currentModule,
		)
		try await validateSendableBuildersCaptureNoNonSendableWrapper(inTreesRootedAt: roots.compactMap(\.tree))
		try await validateNoSeamTierOmitsProvidedValue(inTreesRootedAt: roots)
	}

	/// The plan of each root's and seam's code among `roots`, the trees this module generates, then a file for each of
	/// `rootsOfOtherModules`, the roots another module declares.
	private func plannedCode(of roots: [RootScopeInfo], rootsOfOtherModules: [Instantiable]) async throws -> [PlannedRoot] {
		let rootScopeGenerators = roots
		let declaredTypeNames = declaredTypeNames
		// A seam's root plans its children at once only where the module plans few trees: each tree is planned on a task
		// of its own, so many trees keep every processor busy, and planning their children at once too only holds more
		// frames (1,200 seams of two children each held 13% more peak memory, at the same wall time).
		let seamRootsPlanChildrenAtOnce = rootScopeGenerators.count <= ConcurrentChildCode.maximumChildrenAtOnce
		let plannedRoots = try await ConcurrentChildCode.$seamRootsPlanChildrenAtOnce.withValue(seamRootsPlanChildrenAtOnce) {
			try await withThrowingTaskGroup(
				of: PlannedRoot?.self,
				returning: [PlannedRoot].self,
			) { taskGroup in
				for rootInfo in rootScopeGenerators {
					taskGroup.addTask {
						let code = try await Self.plannedRootCode(of: rootInfo, declaredTypeNames: declaredTypeNames)
						// The fold's imports, found where the tree was built, are compared with the walk of the tree emitted,
						// which for a seam whose first signature pass settled is that pass's tree made again.
						if let observer = TypeFactsImportsObservation.comparesWalk, let tree = rootInfo.observedTree {
							let walkedFulfillers = await GenerationWork.$observer.withValue(nil) {
								await tree.fulfillersOfTree(buildingMock: false)
							}
							observer(TypeFactsImportsComparison(root: rootInfo.typeDescription.asSource, foldedFulfillers: rootInfo.fulfillers, walkedFulfillers: walkedFulfillers))
						}
						if let observer = TypeFactsReceivedValueSuppliesObservation.comparesWalk, let tree = rootInfo.observedTree, let folded = rootInfo.receivedValueSupplies {
							await GenerationWork.$observer.withValue(nil) {
								// A tree `generate` plans is built around no receive nothing provides, which the walk always judges.
								let walked = await tree.receivedValueSupplies(
									ofTreeRootedAt: rootInfo.instantiable,
									unfulfilledReceives: ScopeGenerator.UnfulfilledReceives(locations: [], labels: []),
								)
								observer(TypeFactsReceivedValueSuppliesComparison(
									root: rootInfo.typeDescription.asSource,
									folded: folded,
									walked: walked.map { ReceivedValueSupplies(supplies: $0.supplies.uniqued(), constructedTypes: $0.constructedTypes.uniqued()) },
								))
							}
						}
						return PlannedRoot(
							typeDescription: rootInfo.typeDescription,
							sourceFilePath: rootInfo.sourceFilePath,
							code: code,
							fulfillers: rootInfo.fulfillers,
						)
					}
				}
				var plannedRoots = [PlannedRoot]()
				for try await plannedRoot in taskGroup {
					if let plannedRoot {
						plannedRoots.append(plannedRoot)
					}
				}
				return plannedRoots
			}
		}
		if let observer = HeldCodeTasks.observer {
			for scopeGenerator in rootScopeGenerators.compactMap(\.scopeGenerator) {
				let heldTaskCount = await scopeGenerator.codeTasksHeldInTree()
				observer(heldTaskCount)
			}
		}
		// The file `scan` plans for a root another module declares holds no code: that module generates the root's
		// `init()`, so the file says where, and what to do when that module does not run SafeDI. A root without
		// dependencies gets no `init()` in its own module either, so its file says nothing.
		return plannedRoots + rootsOfOtherModules.map { root in
			let rootType = root.concreteInstantiable.asSource
			// Type and module names are written bare in generated comments, as the root's is.
			let declaringModule = root.moduleName.map { "\($0), the module that declares \(rootType)" } ?? "the module that declares \(rootType)"
			return PlannedRoot(
				typeDescription: root.concreteInstantiable,
				sourceFilePath: root.sourceFilePath,
				code: root.dependencies.isEmpty
					? .empty
					: .text("// SafeDI generates \(rootType)’s init() only in \(declaringModule). If \(rootType)() does not compile, add the SafeDI plugin to the target that declares \(rootType)."),
				fulfillers: [],
			)
		}
	}

	/// Warnings about a dependency tree that generates successfully, whose validated scopes are `validatedScopes`.
	/// `SafeDITool generate` returns them rather than throwing them.
	///
	/// There is one warning: a `LazilyInstantiated` dependency that is instantiated whenever the type that
	/// declares it is created, because a type created along with that one reads its instance. Nothing is lazy
	/// about such a dependency, and nothing else says so.
	private func generateWarnings(validatedScopes: Set<Scope>) -> [SourceDiagnostic] {
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

	/// The DOT graph of the trees `rootScopeGenerators` root.
	private func generateDOTTree(of rootScopeGenerators: [RootScopeInfo]) async -> String {
		let dependencyTree = await withTaskGroup(
			of: String.self,
			returning: String.self,
		) { taskGroup in
			for scopeGenerator in rootScopeGenerators.compactMap(\.scopeGenerator) {
				taskGroup.addTask { await scopeGenerator.generateDOT() }
			}
			var generatedRoots = [String]()
			for await generatedRoot in taskGroup {
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
	let typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable]
	/// Where each received dependency and alias is declared that the trees are built around although nothing provides
	/// it. Empty but for `query graph`'s generator of a graph whose only errors are such dependencies.
	let unfulfilledReceiveLocations: Set<Dependency.DeclarationLocation>
	/// The generator's one ID space: every map it freezes interns its records' values here, so that every ID a tree or a
	/// construction memo compares means one value however many maps and tables the generator makes. Only the generator's
	/// serial code reaches it.
	let internerSpace: ConstructionInternerSpace

	/// The declarations of `instantiables` in the order a generator interns them: the order of their keys, which no arrival
	/// order decides, or the order the tests set (`ConstructionInternerObservation.declarationOrder`).
	static func declarationsInInterningOrder(of instantiables: [TypeDescription: Instantiable]) -> [Instantiable] {
		let declarations = instantiables.map { (order: TypeDescription.ScopeOrderKey($0.key), declaration: $0.value) }
			.sorted { $0.order.precedes($1.order) }
			.map(\.declaration)
		guard let declarationOrder = ConstructionInternerObservation.declarationOrder else { return declarations }
		return declarationOrder(declarations.count).map { declarations[$0] }
	}

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
	struct RootScopeInfo: Sendable {
		/// How a root's code is made.
		enum Built: Sendable {
			/// From its place tree.
			case tree(ScopeGenerator)
			/// From its node records, where no `TreeForcer` holds. `comparisonTree` is the tree built beside them only
			/// where a test observes node records, which compares the two (`plannedRootCode(of:declaredTypeNames:)`); a plain run builds
			/// none.
			case nodeRecords(NodeRecordsLayout, comparisonTree: ScopeGenerator?)
		}

		let typeDescription: TypeDescription
		let instantiable: Instantiable
		let sourceFilePath: String?
		let built: Built
		/// The modules the root's file imports for the types its tree builds, the union over the declarations its tree is
		/// built from (`TypeFactsImports`). Read where the tree is built, so that the table the root's scope is frozen
		/// into, a copy of the module's frozen map, is freed with the build rather than kept for every root at once.
		let fulfillers: Set<FulfillerImports.Fulfiller>
		/// The supplies of the root's tree, read where the tree is built for the same reason, or `nil` where nothing reads
		/// them (`TypeFactsReceivedValueSupplies.whereRead(root:)`).
		let receivedValueSupplies: ReceivedValueSupplies?
		/// The root's scope, frozen, from which node records are made beside its tree after it is built: kept only where
		/// a test observes node records or the run names what they refuse (`kept(_:)`), and `nil` otherwise, so that its
		/// table is freed with the build. A production root, of a module with seams or without, or a seam's own root,
		/// whose records a test only compares.
		let rootScope: ConstructionScope?
		/// For a seam's own tree, its root, held only where `rootScope` is; `nil` for every other root.
		let ownSeamRoot: ScopeGenerator.SeamRoot?

		/// Whether a root's scope is kept after its tree is built (`rootScope`): set where the run names what node records
		/// refuse (`GenerationRequest.namesNodeRecordRefusals`).
		@TaskLocal static var keepsRootScopes = false

		/// `rootScope`, where a test observes node records or the run names what they refuse, which read it once the root's
		/// tree is built; `nil` otherwise.
		static func kept(_ rootScope: ConstructionScope) -> ConstructionScope? {
			NodeRecordsObservation.observer == nil && !keepsRootScopes ? nil : rootScope
		}

		/// What node records read of a seam's own tree beside its world.
		struct SeamTree: Sendable {
			/// What the seam's root is handed as instances of `LazilyInstantiated` properties, which its tree reads through
			/// their wrappers (`DependencyTreeGenerator.seamRootDeclarations(of:seamRoot:)`).
			let rootLazilyInstantiatedInstanceProperties: Set<Property>
			/// The labels of what the seam's root is handed in a wrapper that is not `Sendable`, which a `@Sendable` function
			/// of its tree would capture (`DependencyTreeGenerator.seamRootDeclarations(of:seamRoot:)`).
			let rootNonSendableWrapperLabels: Set<String>
			/// The seam's parameters, the nearest declarations of their labels in its tree, in signature order.
			let parameters: [Property]
			/// What the seam's root is handed, each in the form its tree reads it under its label, in signature order: a
			/// parameter, or the `LazilyInstantiated` a deferred one is held in. Its world's keys read them
			/// (`TypeFactsGraph(root:forMockGeneration:mockRootNames:seamRootDeclarations:)`).
			let handedProperties: [Property]
			/// The labels of the deferred parameters the seam's own rename of the label reads from the autoclosure
			/// (`ScopeGenerator.SeamRoot.autoclosureCallByLabel(of:)`).
			let autoclosureLabels: Set<String>
			/// The seam's signature, whose call routes say how its tree passes its builders' structs up to the seams it calls.
			let signature: SeamSignature
			/// The seam's root, from which a test makes the seam's holes (`SeamHoles(of:seamType:)`), and the seam's type.
			let seamRoot: ScopeGenerator.SeamRoot
			let seamType: TypeDescription

			init(seam: Instantiable, seamRoot: ScopeGenerator.SeamRoot) {
				let declarations = DependencyTreeGenerator.seamRootDeclarations(of: seam, seamRoot: seamRoot)
				rootLazilyInstantiatedInstanceProperties = declarations.lazilyInstantiatedInstanceProperties
				rootNonSendableWrapperLabels = declarations.nonSendableWrapperLabels
				handedProperties = declarations.handedProperties
				parameters = seamRoot.signature.parameters.map(\.property)
				autoclosureLabels = Set(seamRoot.autoclosureCallByLabel(of: seam).keys)
				signature = seamRoot.signature
				self.seamRoot = seamRoot
				seamType = seam.concreteInstantiable
			}

			/// How the seam's tree hands each inner seam's enum up from a call (`ScopeGenerator.SeamRoot.callRoutes`).
			var callRoutes: [SeamSignature.CallRoute] {
				seamRoot.callRoutes
			}

			/// The seam's holes, by path (`SeamHoles(of:seamType:)`).
			func makeSeamHoles() -> SeamHoles {
				SeamHoles(of: seamRoot, seamType: seamType)
			}
		}

		/// For a seam's own tree, what node records read of it beside its world, worked out only where it is read; `nil` for
		/// every other root.
		var seamTree: SeamTree? {
			ownSeamRoot.map { SeamTree(seam: instantiable, seamRoot: $0) }
		}

		/// What made this run build the root's tree (`TreeForcer`); empty where it built none.
		var treeForcers: [TreeForcer] = [.seamWorld]

		init(typeDescription: TypeDescription, instantiable: Instantiable, sourceFilePath: String?, built: Built, fulfillers: Set<FulfillerImports.Fulfiller>, receivedValueSupplies: ReceivedValueSupplies?, rootScope: ConstructionScope?, ownSeamRoot: ScopeGenerator.SeamRoot? = nil, treeForcers: [TreeForcer] = [.seamWorld]) {
			self.typeDescription = typeDescription
			self.instantiable = instantiable
			self.sourceFilePath = sourceFilePath
			self.built = built
			self.fulfillers = fulfillers
			self.receivedValueSupplies = receivedValueSupplies
			self.rootScope = rootScope
			self.ownSeamRoot = ownSeamRoot
			self.treeForcers = treeForcers
		}

		/// The root's place tree, where this run built one for its code.
		var scopeGenerator: ScopeGenerator? {
			switch built {
			case let .tree(scopeGenerator):
				scopeGenerator
			case .nodeRecords:
				nil
			}
		}

		/// The root's place tree, where this run built one: for its code, or beside its node records for a test that
		/// compares them.
		var observedTree: ScopeGenerator? {
			switch built {
			case let .tree(scopeGenerator):
				scopeGenerator
			case let .nodeRecords(_, comparisonTree):
				comparisonTree
			}
		}

		/// The root and its place tree, where this run built one for its code.
		var tree: (instantiable: Instantiable, scopeGenerator: ScopeGenerator)? {
			scopeGenerator.map { (instantiable, $0) }
		}
	}

	/// The validated scopes, frozen. Made only in this file, once `dependencyTrees(unreadTypeComment:)` has validated them,
	/// and handed to each construction that validation must come first for: the trees of the roots of a module without
	/// seams, the inline trees of foreign seams with holes (`inlineTreesOfForeignSeamsWithHoles(in:validatedWorld:foreignSeamRoots:)`),
	/// this module's own seams' signature trees (`SignatureConstruction.ownSeams`), and, through a `SeamWorld`, the trees of
	/// the roots and seams a module with seams generates. It is a convention the compiler enforces by access, not a proof
	/// that the walks ran correctly. Another module's seams' signature trees and its public mocks' plans take none: they
	/// read the declarations alone.
	struct ValidatedWorld {
		fileprivate init(frozenScopeMap: FrozenScopeMap) {
			self.frozenScopeMap = frozenScopeMap
		}

		/// The validated scopes' table.
		let frozenScopeMap: FrozenScopeMap

		/// That this world's walks have passed, as a value a task can hold.
		var passed: ValidationPassed {
			ValidationPassed()
		}
	}

	/// That the validated world's walks have passed: made only from a `ValidatedWorld`.
	struct ValidationPassed: Sendable {
		fileprivate init() {}
	}

	/// A root's code as a plan, which `spelled(_:)` writes once the trees are no longer needed.
	struct PlannedRoot: Sendable {
		let typeDescription: TypeDescription
		let sourceFilePath: String?
		let code: GeneratedCode
		let fulfillers: Set<FulfillerImports.Fulfiller>
	}

	/// The text of each root's plan.
	private static func spelled(_ plannedRoots: [PlannedRoot]) -> [GeneratedRoot] {
		plannedRoots.map { plannedRoot in
			GeneratedRoot(
				typeDescription: plannedRoot.typeDescription,
				sourceFilePath: plannedRoot.sourceFilePath,
				code: plannedRoot.code.spelled(),
				fulfillers: plannedRoot.fulfillers,
			)
		}
	}

	/// The trees of the roots and seams a run of `generate` builds once, validated, which their code, their warnings and
	/// the DOT graph read.
	struct DependencyTrees {
		/// The generators of the trees this module generates: the roots of the dependency tree, then the seams this module
		/// generates.
		let roots: [RootScopeInfo]
		/// The warnings about the validated dependency tree (`generateWarnings(validatedScopes:)`), found while its scopes
		/// are built so that no scope outlives the trees into code generation, whose peak memory it would raise.
		let warnings: [SourceDiagnostic]
		/// The roots another module declares, in type order, whose `init()` that module generates rather than this one.
		let rootsOfOtherModules: [Instantiable]
		/// See `GenerationResults.storedSeamSignatures`.
		let storedSeamSignatures: [StoredSeamSignature]
	}

	/// Validates the dependency tree and builds the trees this module generates, computing the signatures of the seams
	/// this module calls or generates once, here, and handing them down.
	/// - Parameters:
	///   - unreadTypeComment: The comment the `public` initializers of the seams this module generates carry
	///     (`PublicMockContext.unreadTypeComment`).
	///   - ownAccessProof: The proof of every type's access over the module's declarations, which the signatures of the
	///     seams this module generates read (`ownAccessProof()`).
	///   - readersOfEveryTree: What this run reads of every root's tree beside its code, which no root's node records stand
	///     in for (`TreeForcer`).
	func dependencyTrees(unreadTypeComment: UnreadTypeComment?, ownAccessProof: OwnAccessProof, readersOfEveryTree: [TreeForcer]) async throws -> DependencyTrees {
		// The trees of the foreign seams with holes, built inline with the fills this module generates.
		var inlineForeignSeamTrees = [ScopeGenerator]()
		var validatedScopes = Set<Scope>()
		var rootsOfOtherModules = [Instantiable]()
		var storedSeamSignatures = [StoredSeamSignature]()
		let rootScopeGenerators: [RootScopeInfo]
		do {
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
			let foreignSeamRoots = try await computeForeignSeamRoots()
			try validateReachableTypeDescriptions(foreignSeamRoots: foreignSeamRoots)

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
			} catch let error as DependencyTreeGeneratorError {
				// The trees build each foreign seam inline with the fills of its holes, which the seam's module calls
				// through its builders. Only membership in what each fill declares is read, so the seams' order is moot.
				let foreignSeamHoles = foreignSeamRoots.compactMapValues { $0?.signature.holes }
				throw error.markingCyclesClosedInSeamFills(DependencyTreeGeneratorError.SeamFillDeclarations.ofFills(ofHolesOf: foreignSeamHoles, in: typeDescriptionToScopeMap))
			}
			// Every tree built from the validated scopes reads them frozen, once.
			let validatedWorld = ValidatedWorld(frozenScopeMap: FrozenScopeMap(freezing: typeDescriptionToScopeMap.lazy.map { (key: $0.key, scope: $0.value) }, interningIn: internerSpace))
			inlineForeignSeamTrees = try inlineTreesOfForeignSeamsWithHoles(in: typeDescriptionToScopeMap, validatedWorld: validatedWorld, foreignSeamRoots: foreignSeamRoots)
			validatedScopes = Set(typeDescriptionToScopeMap.values)
			// A module whose declarations hold no seam generates from the validated scopes.
			// One that holds a seam generates from a second map, in which every reach of a seam is a call to
			// its generated initializer, built once the validated scopes have been checked. Each construction is
			// checked where it is generated, so the validated scopes decide nothing about access in a module
			// that holds a seam: a root's tree constructs the seam with its generated initializer, and the
			// seam's tree compiles in the module that declares the seam.
			if seams.isEmpty {
				// Creating a generator starts generating its code, so every construction must be known to compile first.
				let rootScopesToGenerate = try rootScopesThisModuleGenerates(
					from: rootInstantiables.sorted().compactMap { typeDescription in
						typeDescriptionToScopeMap[typeDescription].map { (typeDescription: typeDescription, scope: $0) }
					},
				)
				rootsOfOtherModules = rootScopesToGenerate.rootsOfOtherModules
				var constructionMemo = ConstructionMemo()
				// The trees a test builds beside the node records of roots that need none, which keep a memo of their own,
				// so that the trees a plain run builds share what they share without them.
				var comparisonMemo = ConstructionMemo()
				var roots = [RootScopeInfo]()
				for (typeDescription, scope) in rootScopesToGenerate.rootScopes {
					let (table, record) = validatedWorld.frozenScopeMap.freezing(rootScope: scope)
					let constructionScope = ConstructionScope(table: table, record: record)
					func tree(memo: inout ConstructionMemo) throws -> ScopeGenerator {
						try record.createScopeGenerator(
							in: table,
							lazilyInstantiatedInstanceProperties: [],
							erasedToConcreteExistential: false,
							declaredTypeNames: declaredTypeNames,
							constructionMemo: &memo,
						)
					}
					let (layout, treeForcers) = Self.nodeRecordsLayout(of: scope.instantiable, constructionScope: constructionScope, declaredTypeNames: declaredTypeNames, readersOfEveryTree: readersOfEveryTree)
					let built: RootScopeInfo.Built = if let layout {
						// The work of building it is no run's, so the tests that count a run's work count none of it.
						try .nodeRecords(layout, comparisonTree: NodeRecordsObservation.observer == nil ? nil : GenerationWork.$observer.withValue(nil) { try tree(memo: &comparisonMemo) })
					} else {
						try .tree(tree(memo: &constructionMemo))
					}
					roots.append(RootScopeInfo(
						typeDescription: typeDescription,
						instantiable: scope.instantiable,
						sourceFilePath: typeDescriptionToFulfillingInstantiableMap[typeDescription]?.sourceFilePath,
						built: built,
						fulfillers: TypeFactsImports(root: constructionScope).fulfillers,
						receivedValueSupplies: TypeFactsReceivedValueSupplies.whereRead(root: constructionScope),
						rootScope: RootScopeInfo.kept(constructionScope),
						treeForcers: treeForcers,
					))
				}
				rootScopeGenerators = roots
			} else {
				let seamWorldRoots = try await seamWorldRootScopeGenerators(validatedWorld: validatedWorld, foreignSeamRoots: foreignSeamRoots, unreadTypeComment: unreadTypeComment, ownAccessProof: ownAccessProof)
				rootsOfOtherModules = seamWorldRoots.rootsOfOtherModules
				storedSeamSignatures = seamWorldRoots.storedSeamSignatures
				rootScopeGenerators = seamWorldRoots.roots
			}
		}
		// A root laid out from its node records has no tree, and no cycle: node records refuse a world with one (`cycle`).
		try Self.validateCycleLabelsArePassable(inTreesRootedAt: rootScopeGenerators.compactMap(\.scopeGenerator) + inlineForeignSeamTrees)
		for root in rootScopeGenerators {
			GenerationLayerObservation.record(.dependencyTree(of: root.typeDescription), inRunOf: seams.currentModule.moduleName)
		}
		return DependencyTrees(roots: rootScopeGenerators, warnings: generateWarnings(validatedScopes: validatedScopes), rootsOfOtherModules: rootsOfOtherModules, storedSeamSignatures: storedSeamSignatures)
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
	/// by the module that declares it, which the result's `rootsOfOtherModules` records, in type order, so nothing is
	/// reported about it here.
	/// - Parameters:
	///   - rootScopes: The module's roots in type order, each with the scope its tree is generated from.
	///   - seamTrees: The seams this module generates an initializer for, each with the scope its tree is generated
	///     from. A seam is declared in one of the module's own files, so its tree's constructions are checked as an
	///     own root's are, and reported together with the roots'.
	func rootScopesThisModuleGenerates(
		from rootScopes: [(typeDescription: TypeDescription, scope: Scope)],
		checkingSeamTrees seamTrees: [(instantiable: Instantiable, scope: Scope)] = [],
	) throws -> (rootScopes: [(typeDescription: TypeDescription, scope: Scope)], rootsOfOtherModules: [Instantiable]) {
		guard let emittingModule else { return (rootScopes, []) }
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
		// A calling mock whose fill of a called public mock's place makes such a construction reports it too, where the mock
		// makes it as the twin does (`holesFilled(byCallsOf:in:)`).
		guard inaccessibleConstructions.isEmpty else {
			throw DependencyTreeGeneratorError.inaccessibleConstructions(inaccessibleConstructions)
		}
		return (rootScopesToGenerate, rootsOfOtherModules)
	}

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

	private static func fileHeader(importing imports: String) -> String {
		let importsWhitespace = imports.isEmpty ? "" : "\n"
		return "// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.\n// Any modifications made to this file will be overwritten on subsequent builds.\n// Please refrain from editing this file directly.\n\(importsWhitespace)\(imports)\(importsWhitespace)\n"
	}

	/// The imports of a generated file whose code is `unconditionalCode`, which every build compiles, and `mockCode`, which
	/// only builds in which its condition is active compile, from `importStatements`, each spelling the access level
	/// `importAccess` decides.
	/// - Parameter ownFilesReadByEarlierFile: What the module's own files say, once a file before this one of the same
	///   `fileHeaders(for:)` call read it; this file reads it when it needs it and no file before it did.
	private func imports(
		_ importStatements: [ImportStatement],
		building fulfillers: Set<FulfillerImports.Fulfiller>,
		forUnconditionalCode unconditionalCode: () -> String,
		mockCode: (code: () -> String, condition: String)?,
		ownFilesRead ownFilesReadByEarlierFile: inout OwnFilesRead?,
	) async -> String {
		let fulfillersToImport = FulfillerImports.fulfillers(among: fulfillers, notMadeVisibleBy: importStatements, emittingModuleName: emittingModule?.identity.moduleName)
		let ownFilesRead: OwnFilesRead?
		if fulfillersToImport.isEmpty {
			ownFilesRead = nil
		} else if let ownFilesReadByEarlierFile {
			ownFilesRead = ownFilesReadByEarlierFile
		} else {
			let read = await ownFilesReadNow()
			ownFilesReadByEarlierFile = read
			ownFilesRead = read
		}
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
				unconditional: importAccess.namedTypes(inGeneratedCode: unconditionalCode()),
				underMockCondition: mockCode.map { mockCode in (mockCode.condition, importAccess.namedTypes(inGeneratedCode: mockCode.code())) },
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

	/// What the module's own files say, read when a generated file would gain an import apart from a type of the module that
	/// shadows the fulfiller, which only this read can find.
	private func ownFilesReadNow() async -> OwnFilesRead {
		let ownFiles = await readOwnFiles?() ?? FulfillerImports.OwnFiles(typeNames: [], importStatements: [])
		return OwnFilesRead(ownFiles: ownFiles, importAccess: importAccessSpellingOwnLevels(ownFiles.levelsByModuleName))
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
