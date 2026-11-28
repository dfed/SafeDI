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

import Foundation

extension DependencyTreeGenerator {
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
	func validateCalledSeamModulesShareMockCondition() throws {
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
	/// generated signature equals its own initializer's (see `computeSeamRoots(foreignSeamRoots:)`), computed once per
	/// run, before the inlined trees are validated: a module info this run lacks is then reported with its remedy, rather
	/// than as the dependencies that module's declarations would have fulfilled.
	func computeForeignSeamRoots() async throws -> [TypeDescription: ScopeGenerator.SeamRoot?] {
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
		var visibleDeclarationsByModuleName = [String: SeamResolution.VisibleDeclarations]()
		var modulesToCompute = Array(foreignModules(reachedFrom: reachableTypeDescriptions, in: typeDescriptionToFulfillingInstantiableMap, seenBy: nil).reversed())
		// The stored signatures of the modules this module's trees reach are decoded side by side, each once, before the
		// loop reads them: decoding is most of reading a module info file, and the loop runs one module at a time.
		let modulesWithStoredSignatures = modulesToCompute.compactMap { module in
			module.seams.allSatisfy { $0.seam.storedSignatures != nil } ? module.seams[0].seam.storedSignatures.map { (moduleName: module.moduleName, storedSignatures: $0) } : nil
		}
		var decodedStoredSignaturesByModuleName = try await Dictionary(
			zip(
				modulesWithStoredSignatures.map(\.moduleName),
				BoundedConcurrency.map(modulesWithStoredSignatures.map(\.storedSignatures), width: ProcessInfo.processInfo.activeProcessorCount) { storedSignatures, _ in
					try storedSignatures.read()
				},
			),
			uniquingKeysWith: { first, _ in first },
		)
		while let module = modulesToCompute.last {
			guard !computedModules.contains(module.moduleName) else {
				modulesToCompute.removeLast()
				continue
			}
			let moduleSeam = module.seams[0].seam
			// A module info carries the signatures its module's own run computed, beside the declarations it computed them
			// from and only once every validation passed, so a module whose every seam has one is read, never computed again.
			// A foreign public mock's plan is read the same way (`computePublicMockPlans`).
			// The module's stored signatures are decoded here, once, and only for a module whose every seam has one.
			let storedSeamRoots: [(type: TypeDescription, seamRoot: ScopeGenerator.SeamRoot?)]
			if module.seams.allSatisfy({ $0.seam.storedSignatures != nil }), let storedSignatures = moduleSeam.storedSignatures {
				var storedSignatureBySeam = [TypeDescription: StoredSeamSignature]()
				// Of two signatures of one seam, the first is kept.
				for stored in try decodedStoredSignaturesByModuleName.removeValue(forKey: module.moduleName) ?? storedSignatures.read() where storedSignatureBySeam[stored.seamType] == nil {
					storedSignatureBySeam[stored.seamType] = stored
				}
				storedSeamRoots = module.seams.compactMap { seam in
					storedSignatureBySeam[seam.type].map { (type: seam.type, seamRoot: $0.signature.map { ScopeGenerator.SeamRoot(signature: $0, callRoutes: [], routeMembersBySite: [:]) }) }
				}
			} else {
				storedSeamRoots = []
			}
			if storedSeamRoots.count == module.seams.count {
				modulesToCompute.removeLast()
				computedModules.insert(module.moduleName)
				for (seamType, seamRoot) in storedSeamRoots {
					seamRoots[seamType] = seamRoot
				}
				continue
			}
			// Resolved once per module, on its first visit.
			let visible: SeamResolution.VisibleDeclarations
			if let resolved = visibleDeclarationsByModuleName[module.moduleName] {
				visible = resolved
			} else {
				visible = try moduleSeam.visibleDeclarations()
				visibleDeclarationsByModuleName[module.moduleName] = visible
			}
			// A module's reached modules are pushed above it on its first visit only; on its second it is computed
			// with the signatures found by then, so the loop ends whatever the module infos claim to reach.
			if expandedModules.insert(module.moduleName).inserted {
				let dependencies = foreignModules(reachedFrom: Set(module.seams.map(\.type)), in: visible.instantiables, seenBy: module.moduleName)
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
			GenerationLayerObservation.record(.seamSignatures(ofModule: module.moduleName, inCallersView: false), inRunOf: seams.currentModule.moduleName)
			let computation = try await Self.seamSignatures(
				forSeams: Set(module.seams.map(\.type)),
				construction: .foreignModule,
				in: visible.instantiables,
				plainTypeDeclarations: visible.plainTypeDeclarations,
				aliasDeclarationReferences: aliasDeclarationReferences,
				fixedSignatures: seamRoots.compactMapValues(\.self),
				callerModule: moduleSeam.declaringModule,
				seams: seams.resolution(seenByModuleNamed: module.moduleName),
				// Another module's own run checks its constructions; whether that check reports a call is not known
				// here, so an omission such a call would let its seam skip is reported.
				checkingModule: nil,
				// Another module's seams are computed from its named module's declarations.
				proof: {
					GenerationLayerObservation.record(.accessProof(ofModule: module.moduleName, inCallersView: false), inRunOf: seams.currentModule.moduleName)
					return TypeAccessProof(
						instantiables: visible.instantiables,
						plainTypeDeclarations: visible.plainTypeDeclarations,
						isOwnFile: nil,
						reach: Self.moduleReach(viewedFrom: moduleSeam.declaringModule, instantiables: visible.instantiables, plainTypeDeclarations: visible.plainTypeDeclarations, modulesReadByRunOfModule: emittingModule?.modulesReadByRunOfModule),
					)
				},
				internerSpace: internerSpace,
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
	/// whose file holds no code. Computed once per run, from the signatures of the foreign seams, `foreignSeamRoots`, and
	/// over the proof of every type's access the public mock context reads too, `ownAccessProof`.
	/// Beside them, the tree the first signature pass built of each seam this module generates that the pass settled
	/// without the pass that confirms it, which emission makes again rather than building anew
	/// (`ScopeGenerator.reseating(treeRootedAt:of:seamRoot:)`).
	private func computeSeamRoots(validatedWorld: ValidatedWorld, foreignSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?], ownAccessProof: OwnAccessProof) async throws -> (seamRoots: [TypeDescription: ScopeGenerator.SeamRoot?], firstPassTrees: [TypeDescription: SeamRootTree]) {
		var seamRoots = foreignSeamRoots
		GenerationLayerObservation.record(.seamSignatures(ofModule: seams.currentModule.moduleName, inCallersView: false), inRunOf: seams.currentModule.moduleName)
		let ownComputation = try await Self.seamSignatures(
			forSeams: generatedSeamTypes,
			construction: .ownSeams(validatedWorld.passed),
			in: typeDescriptionToFulfillingInstantiableMap,
			plainTypeDeclarations: plainTypeDeclarations,
			aliasDeclarationReferences: aliasDeclarationReferences,
			fixedSignatures: seamRoots.compactMapValues(\.self),
			callerModule: seams.currentModule,
			seams: seams,
			checkingModule: emittingModuleToCheck,
			proof: { ownAccessProof.proof },
			internerSpace: internerSpace,
			builtInlineSeamComment: { [seams] in Self.builtInlineSeamComment(for: $0, seams: seams) },
			keepsFirstPassTrees: true,
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
		if let callersVisibleInstantiables = seams.callersVisibleInstantiables, let ownProof = ownComputation.proof {
			let unseenDeclarations = Set(typeDescriptionToFulfillingInstantiableMap.values.map(\.concreteInstantiable))
				.subtracting(callersVisibleInstantiables.values.map(\.concreteInstantiable))
			GenerationLayerObservation.record(.seamSignatures(ofModule: seams.currentModule.moduleName, inCallersView: true), inRunOf: seams.currentModule.moduleName)
			let callersComputation = try await Self.seamSignatures(
				forSeams: generatedSeamTypes,
				construction: .ownSeams(validatedWorld.passed),
				in: callersVisibleInstantiables,
				plainTypeDeclarations: seams.callersVisiblePlainTypeDeclarations,
				aliasDeclarationReferences: aliasDeclarationReferences,
				fixedSignatures: seamRoots.compactMapValues(\.self),
				callerModule: seams.currentModule,
				seams: seams,
				checkingModule: emittingModuleToCheck,
				proof: {
					GenerationLayerObservation.record(.accessProof(ofModule: seams.currentModule.moduleName, inCallersView: true), inRunOf: seams.currentModule.moduleName)
					return TypeAccessProof(
						instantiables: callersVisibleInstantiables,
						plainTypeDeclarations: seams.callersVisiblePlainTypeDeclarations,
						isOwnFile: emittingModule?.isOwnFile,
						reach: Self.moduleReach(viewedFrom: seams.currentModule, instantiables: callersVisibleInstantiables, plainTypeDeclarations: seams.callersVisiblePlainTypeDeclarations, modulesReadByRunOfModule: emittingModule?.modulesReadByRunOfModule),
					)
				},
				internerSpace: internerSpace,
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
					proof: ownProof,
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
		return (seamRoots, ownComputation.firstPassTrees)
	}

	/// The parameters of `ownSignature` a seam's callers would not pass as this run declares them: those
	/// `labelsCallersFailedOn` names, where the callers could not compute the signature and the error they hit names a
	/// parameter, else those whose call shape `callersSignature` does not hold.
	static func differingParameters(
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
		Dependency.DeclarationLocation.precedesInSourceOrder(leftLocation, rightLocation)
	}

	/// The generators of the trees this module generates, in a world where every reach of a seam calls its generated
	/// initializer: the roots of the dependency tree, then the seams this module generates, each with its signature; and
	/// the roots another module declares, in type order.
	/// - Parameters:
	///   - foreignSeamRoots: The signatures of the foreign seams this module's trees reach (`computeForeignSeamRoots()`).
	///   - unreadTypeComment: The comment the `public` initializers of the seams this module generates carry.
	///   - ownAccessProof: The proof of every type's access over the module's declarations (`ownAccessProof()`).
	func seamWorldRootScopeGenerators(
		validatedWorld: ValidatedWorld,
		foreignSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?],
		unreadTypeComment: UnreadTypeComment?,
		ownAccessProof: OwnAccessProof,
		plansCyclesPerType: Bool,
		drawsTrees: Bool,
	) async throws -> (roots: [RootScopeInfo], rootsOfOtherModules: [Instantiable], storedSeamSignatures: [StoredSeamSignature]) {
		var (seamRoots, firstPassTrees) = try await computeSeamRoots(validatedWorld: validatedWorld, foreignSeamRoots: foreignSeamRoots, ownAccessProof: ownAccessProof)
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
			isOwnFile: emittingModule?.isOwnFile,
		)
		// Every tree of the seam world reads its scopes frozen, once.
		let seamWorld = SeamWorld(validatedWorld: validatedWorld, frozenScopeMap: FrozenScopeMap(freezing: seamScopeMap.lazy.map { (key: $0.key, scope: $0.value) }, interningIn: internerSpace))
		// A seam whose signature equals its own initializer's generates no code: its file holds the header alone.
		var generatedSeams = [(seam: Instantiable, seamRoot: ScopeGenerator.SeamRoot, rootScope: Scope)]()
		// Once for every seam: taken for each, it copied every scope's declaration once per seam.
		let seamScopeInstantiables = seamScopeMap.mapValues(\.instantiable)
		for seamType in generatedSeamTypes.sorted() {
			guard let seam = typeDescriptionToFulfillingInstantiableMap[seamType],
			      let seamRoot = seamRoots[seamType] ?? nil
			else { continue }
			generatedSeams.append((seam, seamRoot, Self.seamRootScope(of: seam, in: seamScopeMap, instantiables: seamScopeInstantiables, callerModule: seams.currentModule, aliasDeclarationReferences: aliasDeclarationReferences)))
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
		var constructionMemo = ConstructionMemo()
		// A root is built as in a module without seams: today's tree per path, or its per-type plan past the limit, where
		// each seam its tree calls is a leaf. What a scope of the seam world receives is collected apart from the
		// validated scopes'.
		var receivedPropertiesCache = ReceivedPropertiesCache()
		var rootScopeGenerators = try await rootTrees(
			of: rootScopesToGenerate.rootScopes,
			frozenScopeMap: seamWorld.frozenScopeMap,
			plansCyclesPerType: plansCyclesPerType,
			drawsTrees: drawsTrees,
			// A test compares the records of a seam world's production root with its tree's places, and no run lays it out
			// from them until node records make a seam call (`NodeRecords`).
			readersOfEveryTree: nil,
			constructionMemo: &constructionMemo,
			cache: &receivedPropertiesCache,
		)
		for (seam, seamRoot, seamRootScope) in generatedSeams {
			var seamRoot = seamRoot
			seamRoot.unreadTypeComment = unreadTypeComment
			seamRoot.generatesPlainInitializers = seams.generatesPlainDependencyTreeInitializers
			let finalSeamRoot = seamRoot
			let declaredTypeNames = declaredTypeNames
			func builtTree() throws -> (generator: ScopeGenerator, rootScope: ConstructionScope) {
				try Self.seamRootGenerator(
					rootScope: seamRootScope,
					in: .seamWorld(seamWorld),
					seamRoot: finalSeamRoot,
					declaredTypeNames: declaredTypeNames,
				)
			}
			// A tree its first signature pass settled is made again from the final signature, which it holds as the tree
			// built here would (`seam-signature-passes.md`); the pass's tree is released once it is.
			let scopeGenerator: ScopeGenerator
			let fulfillers: Set<FulfillerImports.Fulfiller>
			let receivedValueSupplies: ReceivedValueSupplies?
			let rootScope: ConstructionScope?
			if let firstPassTree = firstPassTrees.removeValue(forKey: seam.concreteInstantiable) {
				scopeGenerator = ScopeGenerator.reseating(treeRootedAt: firstPassTree.generator, of: seam.concreteInstantiable, seamRoot: seamRoot)
				// The pass's tree holds no seam call or fill (`confirmingPassFindsNothingNew`), so every record it reaches is
				// the base's, which the seam world's table holds too: its declarations are those of the tree built anew.
				fulfillers = firstPassTree.fulfillers
				receivedValueSupplies = firstPassTree.receivedValueSupplies
				rootScope = firstPassTree.rootScope
				if let observer = SeamTreeReuseObservation.comparesBuiltTrees {
					let treeBuiltAnew = try builtTree().generator
					observer(ReusedSeamTree(
						signature: StoredSeamSignature(seamType: seam.concreteInstantiable, signature: finalSeamRoot.signature),
						reusedTreeCode: { try await scopeGenerator.generatePlan().spelled() },
						builtTreeCode: { try await treeBuiltAnew.generatePlan().spelled() },
					))
				}
			} else {
				let tree = try builtTree()
				scopeGenerator = tree.generator
				fulfillers = TypeFactsImports(root: tree.rootScope, buildingMock: false).fulfillers
				receivedValueSupplies = TypeFactsReceivedValueSupplies.whereRead(root: tree.rootScope)
				rootScope = RootScopeInfo.kept(tree.rootScope)
			}
			// A test compares the records of a seam's own tree with its tree's places, and no run lays the seam's
			// initializers out from them: they are written around its tree's body (`ScopeGenerator.generateSeamRootCode`).
			rootScopeGenerators.append(RootScopeInfo(
				typeDescription: seam.concreteInstantiable,
				instantiable: seam,
				sourceFilePath: seam.sourceFilePath,
				built: .tree(scopeGenerator),
				fulfillers: fulfillers,
				receivedValueSupplies: receivedValueSupplies,
				rootScope: rootScope,
				// Held only beside the root's scope, where node records are made of it: a run keeps a root's info for
				// every seam, and holding each seam's root in it grew what a run of many seams allocates by about 1%.
				ownSeamRoot: rootScope == nil ? nil : finalSeamRoot,
			))
		}
		// The signature of each seam this module generates, sorted by seam, which its module info carries for the modules
		// that call the seams (`SeamResolution.ForeignSeam.storedSignature`).
		let storedSeamSignatures = generatedSeamTypes.sorted().compactMap { seamType in
			seamRoots[seamType].map { StoredSeamSignature(seamType: seamType, signature: $0?.signature) }
		}
		return (rootScopeGenerators, rootScopesToGenerate.rootsOfOtherModules, storedSeamSignatures)
	}

	/// The seam world's scopes, frozen, in which every reach of a seam with a signature calls its generated initializer.
	/// Made only in this file, from a `ValidatedWorld`, once the seams' signatures have settled and
	/// `validateRootsFillEveryHole` has passed, and handed to each tree of a root or seam this module generates. As
	/// `ValidatedWorld` is, a convention the compiler enforces by access.
	struct SeamWorld {
		fileprivate init(validatedWorld _: ValidatedWorld, frozenScopeMap: FrozenScopeMap) {
			self.frozenScopeMap = frozenScopeMap
		}

		/// The seam world's table.
		let frozenScopeMap: FrozenScopeMap
	}

	/// Whose seams a computation of signatures builds trees for, which decides the guard those trees are built under.
	enum SignatureConstruction: Sendable {
		/// This module's own seams, once the validated world's walks have passed.
		case ownSeams(ValidationPassed)
		/// Another module's seams, which read the declarations alone: exempt, since that module's own run validated
		/// them, and bounded by the passes a component may take.
		case foreignModule

		/// The world a signature pass over `frozenScopeMap` builds its seams' trees in.
		func signaturePass(over frozenScopeMap: FrozenScopeMap) -> SeamTreeWorld {
			switch self {
			case let .ownSeams(validatedWorld):
				.ownSignaturePass(frozenScopeMap, validatedBy: validatedWorld)
			case .foreignModule:
				.foreignSignaturePass(frozenScopeMap)
			}
		}
	}

	/// The table a seam's tree is built from, with the guard that has passed before it.
	enum SeamTreeWorld {
		/// A signature pass of this module's own seams.
		case ownSignaturePass(FrozenScopeMap, validatedBy: ValidationPassed)
		/// A signature pass of another module's seams.
		case foreignSignaturePass(FrozenScopeMap)
		/// The seam world, for a seam this module generates.
		case seamWorld(SeamWorld)

		var frozenScopeMap: FrozenScopeMap {
			switch self {
			case let .ownSignaturePass(frozenScopeMap, _), let .foreignSignaturePass(frozenScopeMap):
				frozenScopeMap
			case let .seamWorld(seamWorld):
				seamWorld.frozenScopeMap
			}
		}
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
	struct SeamReceiver {
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

	/// The enums `seamRoot`'s signature declares itself, rather than carries from a seam it reaches.
	private static func ownScopeEnums(of seamRoot: ScopeGenerator.SeamRoot) -> [SeamSignature.ScopeEnum] {
		seamRoot.signature.scopeEnums.filter { $0.key.seamType == seamRoot.signature.seamType }
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
		construction: SignatureConstruction,
		in instantiables: [TypeDescription: Instantiable],
		plainTypeDeclarations: [PlainTypeDeclaration],
		aliasDeclarationReferences: AliasDeclarationReferences,
		fixedSignatures: [TypeDescription: ScopeGenerator.SeamRoot],
		callerModule: ModuleIdentity,
		seams: SeamResolution,
		checkingModule: EmittingModule?,
		proof makeProof: () -> TypeAccessProof,
		internerSpace: ConstructionInternerSpace,
		builtInlineSeamComment: @escaping @Sendable (Instantiable) -> String? = { _ in nil },
		keepsFirstPassTrees: Bool = false,
		isolation _: isolated (any Actor)? = #isolation,
	) async throws -> SeamSignatureComputation {
		let seamInstantiables = seamTypes.sorted().compactMap { instantiables[$0] }.filter(\.generatesDependencyTree)
		guard !seamInstantiables.isEmpty else { return SeamSignatureComputation(seamRoots: [:], errors: [], failedSeams: [], proof: nil) }
		// One proof of every type's access over `instantiables`, which every seam of the computation reads, made only when
		// the computation has a seam.
		let proof = makeProof()
		let ownSeamTypes = Set(seamInstantiables.map(\.concreteInstantiable))
		let declaredTypeNames = namesOfTypesDeclaredAtFileScope(instantiables: Array(instantiables.values), plainTypeDeclarations: plainTypeDeclarations)
		// The declarations of this map are given the interner before any of its scopes is frozen, as the generator's own
		// are: a seam module's view, or the callers', can hold declarations the generator's map does not.
		internerSpace.internDeclarations(of: declarationsInInterningOrder(of: instantiables))
		// The base of every pass's table: the seam world of every declaration, in which every seam is built and none is
		// called. A record of a type that is no seam depends on the declarations alone, so every pass reads it from here; a
		// pass overlays the records of the seams it calls (`FrozenScopeMap.overlaying`).
		let baseScopeMap = Self.createSeamScopeMapping(
			in: instantiables,
			reachableTypeDescriptions: Set(instantiables.keys),
			seamRoots: [:],
			ownSeamTypes: ownSeamTypes,
			callerModule: callerModule,
			seams: seams,
			aliasDeclarationReferences: aliasDeclarationReferences,
			checkingModule: checkingModule,
			builtInlineSeamComment: builtInlineSeamComment,
		)
		let baseFrozenScopeMap = FrozenScopeMap(freezing: baseScopeMap.lazy.map { (key: $0.key, scope: $0.value) }, interningIn: internerSpace)
		func initialSeamRoot(of seam: Instantiable) -> ScopeGenerator.SeamRoot {
			let parameters = Self.ownParameters(of: seam, proof: proof)
			return ScopeGenerator.SeamRoot(
				signature: SeamSignature(seamType: seam.concreteInstantiable, parameters: parameters, tiers: Self.tiers(of: seam, parameters: parameters)),
				callRoutes: [],
				routeMembersBySite: [:],
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
		var firstPassTrees = [TypeDescription: SeamRootTree]()
		// A seam's parameters depend on the signatures of the seams its tree reaches, so the seams are settled inner
		// first: each strongly connected component of the seam-reaches-seam graph sees the final signatures of the seams
		// it reaches outside it, and only seams that reach one another are computed again until none changes.
		// Every seam's latest root, the other modules' from `fixedSignatures`, and the enums each seam declares itself,
		// which a seam's builders read from the seam that declares them: a copy another seam carries can be from an
		// earlier pass, and copies of different ages taken from different neighbors would keep a cycle of seams from
		// settling. Brought up to date with each component's own seams once the component settles.
		var knownSeamRoots = fixedSignatures.mapValues { Optional($0) }
		for (seamType, seamRoot) in seamRoots {
			knownSeamRoots[seamType] = seamRoot
		}
		var ownScopeEnumsBySeamType = [TypeDescription: [SeamSignature.ScopeEnum]]()
		for case let (seamType, seamRoot?) in knownSeamRoots {
			ownScopeEnumsBySeamType[seamType] = Self.ownScopeEnums(of: seamRoot)
		}
		// Each seam's position in `seamInstantiables`, so that a component's seams are listed in that order without a
		// scan of every seam per component.
		let seamIndicesBySeamType = Dictionary(grouping: seamInstantiables.indices, by: { seamInstantiables[$0].concreteInstantiable })
		let seamComponents = Self.stronglyConnectedComponents(of: seamInstantiables, in: instantiables, among: ownSeamTypes)
		// The components come in reverse topological order: a component after every component it reaches. A component
		// whose trees reach no other component's seam is in level 0, and every other one in the level after the latest
		// level of a component it reaches, so the components of one level reach none of one another and are computed at
		// once, each from what the levels before it settled. Each reads only the seams its own trees reach
		// (`createSeamScopeMapping` reads the signature of a reached seam alone, and `seamRoot(of:)` the enums of the
		// seams the builders reach), so each computes what it would one after another.
		var componentIndexBySeamType = [TypeDescription: Int]()
		for (index, component) in seamComponents.components.enumerated() {
			for seamType in component {
				componentIndexBySeamType[seamType] = index
			}
		}
		var plans = [SeamComponentPlan]()
		var levelOfComponent = [Int]()
		for (index, component) in seamComponents.components.enumerated() {
			let reachableTypeDescriptions = Self.typesReachable(fromRoots: component, in: instantiables)
			var level = 0
			var reachedSeamTypes = [TypeDescription]()
			for typeDescription in reachableTypeDescriptions.sorted() {
				guard let concreteType = instantiables[typeDescription]?.concreteInstantiable, knownSeamRoots[concreteType] != nil else { continue }
				reachedSeamTypes.append(concreteType)
				if let reachedComponent = componentIndexBySeamType[concreteType], reachedComponent != index {
					level = max(level, levelOfComponent[reachedComponent] + 1)
				}
			}
			levelOfComponent.append(level)
			plans.append(SeamComponentPlan(
				index: index,
				component: component,
				seams: component.flatMap { seamIndicesBySeamType[$0] ?? [] }.sorted().map { seamInstantiables[$0] },
				reachableTypeDescriptions: reachableTypeDescriptions,
				reachedSeamTypes: reachedSeamTypes,
			))
		}
		let context = SeamComponentContext(
			construction: construction,
			instantiables: instantiables,
			ownSeamTypes: ownSeamTypes,
			callerModule: callerModule,
			seams: seams,
			aliasDeclarationReferences: aliasDeclarationReferences,
			checkingModule: checkingModule,
			builtInlineSeamComment: builtInlineSeamComment,
			proof: proof,
			declaredTypeNames: declaredTypeNames,
			keepsFirstPassTrees: keepsFirstPassTrees,
			seamsReachingThemselves: seamComponents.seamsReachingThemselves,
		)
		let width = SeamSignatureObservation.width ?? ProcessInfo.processInfo.activeProcessorCount
		// Made only when a level runs on more than one task: each task freezes its passes in an ID space of its own.
		var base: FrozenScopeMap.Base?
		var settledComponents = [Int: SettledSeamComponent]()
		// Every level holds a component: one is in a level after the first only for a component it reaches in the level
		// before. A component's computation throws only an error no pass reports, which no input is known to reach (every
		// error a pass meets is a `SourceLocatedError`, which the pass reports); the level's earliest such component in
		// component order decides it, as computing the level's components one after another would.
		for level in 0..<((levelOfComponent.max() ?? -1) + 1) {
			let inputs = plans.filter { levelOfComponent[$0.index] == level }.map { plan in
				var reachedSeamRoots = [TypeDescription: ScopeGenerator.SeamRoot?]()
				var reachedScopeEnums = [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]()
				for seamType in plan.reachedSeamTypes {
					reachedSeamRoots[seamType] = knownSeamRoots[seamType]
					for scopeEnum in ownScopeEnumsBySeamType[seamType] ?? [] {
						reachedScopeEnums[scopeEnum.key] = scopeEnum
					}
				}
				return SeamComponentInput(plan: plan, knownSeamRoots: reachedSeamRoots, ownScopeEnums: reachedScopeEnums)
			}
			// A level runs on more than one task only where its components reach mostly types of their own: at least half
			// of the types they reach, counted once per component, are distinct. Components that reach the same types run
			// several times slower side by side than one after another, all reading the same scopes and records, so they gain
			// no wall time and spend the processor time of every task. Measured on Linux with four processors: a module of
			// ten layers of four seams, each reaching the layers beneath it (N5i-10, whose first level reaches 75% distinct
			// types and every level after it 47% down to 28%), took 1.39 s of CPU in parallel and 0.73 s in turn, at the same wall
			// time; 1,200 seams that each reach a leaf of their own (E6d-1200, one level of 67% distinct types) settle in
			// parallel 21% faster in wall time than in turn, at the same CPU. The sets are the plans' own, so this adds no walk.
			let reachedTypeCount = inputs.reduce(0) { $0 + $1.plan.reachableTypeDescriptions.count }
			let distinctReachedTypeCount = inputs.reduce(into: Set<TypeDescription>()) { $0.formUnion($1.plan.reachableTypeDescriptions) }.count
			let taskCount = 2 * distinctReachedTypeCount >= reachedTypeCount ? min(width, inputs.count) : 1
			SeamSignatureObservation.observesLevels?(SeamSignatureLevel(componentCount: inputs.count, taskCount: taskCount))
			let settledInputs: [SettledSeamComponent]
			if taskCount <= 1 {
				settledInputs = try inputs.map { try Self.settle($0, context: context, baseFrozenScopeMap: baseFrozenScopeMap) }
			} else {
				let levelBase = base ?? baseFrozenScopeMap.base
				base = levelBase
				// Contiguous runs of the level's components, one per task, so that each task makes its map once.
				let runs = (0..<taskCount).map { run in
					Array(inputs[(inputs.count * run / taskCount)..<(inputs.count * (run + 1) / taskCount)])
				}
				settledInputs = try await BoundedConcurrency.map(runs, width: taskCount) { run, _ in
					let taskBaseFrozenScopeMap = FrozenScopeMap(base: levelBase)
					return try SettledSeamComponentRun(components: run.map { try Self.settle($0, context: context, baseFrozenScopeMap: taskBaseFrozenScopeMap) })
				}.flatMap(\.components)
			}
			for (input, settled) in zip(inputs, settledInputs) {
				settledComponents[input.plan.index] = settled
				for (seamType, seamRoot) in settled.seamRoots {
					seamRoots[seamType] = seamRoot
					knownSeamRoots[seamType] = .some(seamRoot)
					ownScopeEnumsBySeamType[seamType] = seamRoot.map(Self.ownScopeEnums(of:)) ?? []
				}
			}
		}
		for (_, settled) in settledComponents.sorted(by: { $0.key < $1.key }) {
			errors += settled.errors
			failedSeams.formUnion(settled.failedSeams)
			// Kept only for a component of one seam that its first pass settled with a signature and no error.
			if let firstPassTree = settled.firstPassTree, let seamType = settled.seamRoots.first?.0 {
				firstPassTrees[seamType] = firstPassTree
			}
		}
		// Every enum of a cycle is generated by one module, whose seams are the ones settled here.
		let seamTypesInOrder = seamRoots.keys.sorted()
		let markedSeamRoots = Self.markingIndirectCases(in: seamTypesInOrder.map { seamRoots[$0] ?? nil })
		for (seamType, seamRoot) in zip(seamTypesInOrder, markedSeamRoots) {
			seamRoots[seamType] = seamRoot
		}
		return SeamSignatureComputation(seamRoots: seamRoots, errors: errors, failedSeams: failedSeams, proof: proof, firstPassTrees: firstPassTrees)
	}

	/// One strongly connected component of a module's seams, as `seamSignatures` plans its computation.
	private struct SeamComponentPlan: Sendable {
		/// The component's position in reverse topological order, which orders its errors among the others'.
		let index: Int
		let component: Set<TypeDescription>
		/// The component's seams, in the order of the computation's seams.
		let seams: [Instantiable]
		let reachableTypeDescriptions: Set<TypeDescription>
		/// The seams, of this module or another, that the component's trees reach, its own included, in type order.
		let reachedSeamTypes: [TypeDescription]
	}

	/// What a component is computed from: its plan, and the roots and enums of the seams it reaches as the levels before
	/// it left them.
	private struct SeamComponentInput: Sendable {
		let plan: SeamComponentPlan
		let knownSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]
		let ownScopeEnums: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]
	}

	/// What every component of one computation reads alike.
	private struct SeamComponentContext: Sendable {
		let construction: SignatureConstruction
		let instantiables: [TypeDescription: Instantiable]
		let ownSeamTypes: Set<TypeDescription>
		let callerModule: ModuleIdentity
		let seams: SeamResolution
		let aliasDeclarationReferences: AliasDeclarationReferences
		let checkingModule: EmittingModule?
		let builtInlineSeamComment: @Sendable (Instantiable) -> String?
		let proof: TypeAccessProof
		let declaredTypeNames: DeclaredTypeNames
		let keepsFirstPassTrees: Bool
		let seamsReachingThemselves: Set<TypeDescription>

		func initialSeamRoot(of seam: Instantiable) -> ScopeGenerator.SeamRoot {
			let parameters = DependencyTreeGenerator.ownParameters(of: seam, proof: proof)
			return ScopeGenerator.SeamRoot(
				signature: SeamSignature(seamType: seam.concreteInstantiable, parameters: parameters, tiers: DependencyTreeGenerator.tiers(of: seam, parameters: parameters)),
				callRoutes: [],
				routeMembersBySite: [:],
			)
		}
	}

	/// What settling one component found: the latest root of each of its seams, in the component's order, and the errors of
	/// its last pass, with the seams they belong to.
	private struct SettledSeamComponent: Sendable {
		let seamRoots: [(TypeDescription, ScopeGenerator.SeamRoot?)]
		let errors: [DependencyTreeGeneratorError]
		let failedSeams: Set<TypeDescription>
		let firstPassTree: SeamRootTree?
	}

	/// What one task of a level settled, in its components' order.
	private struct SettledSeamComponentRun: Sendable {
		let components: [SettledSeamComponent]
	}

	/// Settles one component of `seamSignatures`, from the roots and enums of the seams it reaches.
	private static func settle(_ input: SeamComponentInput, context: SeamComponentContext, baseFrozenScopeMap: FrozenScopeMap) throws -> SettledSeamComponent {
		let component = input.plan.component
		let componentSeams = input.plan.seams
		let reachableTypeDescriptions = input.plan.reachableTypeDescriptions
		let instantiables = context.instantiables
		let ownSeamTypes = context.ownSeamTypes
		let callerModule = context.callerModule
		let seams = context.seams
		let aliasDeclarationReferences = context.aliasDeclarationReferences
		let checkingModule = context.checkingModule
		let builtInlineSeamComment = context.builtInlineSeamComment
		let construction = context.construction
		let proof = context.proof
		let declaredTypeNames = context.declaredTypeNames
		let keepsFirstPassTrees = context.keepsFirstPassTrees
		let seamsReachingThemselves = context.seamsReachingThemselves
		let internerSpace = baseFrozenScopeMap.space
		var knownSeamRoots = input.knownSeamRoots
		var ownScopeEnums = input.ownScopeEnums
		var seamRoots = [TypeDescription: ScopeGenerator.SeamRoot?]()
		for seam in componentSeams {
			seamRoots[seam.concreteInstantiable] = knownSeamRoots[seam.concreteInstantiable] ?? nil
		}
		func initialSeamRoot(of seam: Instantiable) -> ScopeGenerator.SeamRoot {
			context.initialSeamRoot(of: seam)
		}
		// A component settles in a fixed point in which every input to `seamRoot` only grows: a tree built with more
		// parameters in scope receives no less from outside it, each label's form only strengthens (`X?` received
		// only if available, then a required `X?`, `X`, a wrapper), a parameter that stops being received only if
		// available never is again, and the receivers of each parameter only accumulate. Nothing else a pass finds
		// feeds the next: an alias bound from a parameter that may be `nil` is bound from that parameter alone, as an
		// optional value passed to its declaring type, and every other read of it is rejected before emission, so it
		// adds no parameter. The computation ends when a pass changes no signature's content – never the receivers'
		// order, which a tree carrying the receivers of a seam that carries its own meets differently on every pass –
		// or at the limit, which reports the component. The argument needs each pass to read the component's other seams
		// as one pass left them: an enum a seam's builders
		// reach is read from the seam that declares it (`ownScopeEnums`), since copies of different ages, each carried
		// by a different neighbor, would differ on every pass around a cycle of four seams. For the same reason a place
		// a seam passes up is labeled by the seam that declares it, with that seam's own builder label for the place's
		// hole type and family (`holes(of:…)`), which follows only from that seam's hole types and parameters, both of
		// which only grow: a label is a function of the places a pass settles, and never an input to another seam's
		// label. A label a passing seam named apart from its own holes would carry each seam's names into the next
		// around a ring, and change on every pass. The rest of a passed-up place – its fields, the values its case
		// carries, its uncarried declarations – is still copied from the seam that presents it first, which inside a ring
		// can be a neighbor's copy from the pass before: a ring in which a value reaches a place only after the first
		// pass can alternate between two copies until the limit, or settle on a stale one, as every release has. Reading
		// the whole place from the seam that declares it, as its label is, is the follow-up that closes this.
		var errorsOfLastPass = [DependencyTreeGeneratorError]()
		var failedSeamsOfLastPass = Set<TypeDescription>()
		var settled = false
		// A component of one seam that does not reach itself settles after its first pass when the pass that would
		// confirm it would read nothing the first pass changed (`confirmingPassFindsNothingNew`). The seam's signature,
		// holes included, then comes from a tree the first pass built with the construction memo on, since its root had no
		// holes yet; the memo oracle checks that tree too. In a test, the confirming pass runs anyway and must find the
		// same signature (`SeamSignatureObservation.confirmsSkippedPasses`).
		let maySkipConfirmingPass = componentSeams.count == 1 && !seamsReachingThemselves.contains(componentSeams[0].concreteInstantiable)
		var isFirstPass = true
		var skippedPass: SkippedPass?
		// The first pass's tree of a seam that pass settles, kept for emission where the computation keeps them.
		var firstPassTree: SeamRootTree?
		for _ in 0..<Self.seamSignatureComputationLimit(forComponentOf: component.count) {
			let scopeMap = Self.createSeamScopeMapping(
				in: instantiables,
				reachableTypeDescriptions: reachableTypeDescriptions,
				seamRoots: knownSeamRoots,
				ownSeamTypes: ownSeamTypes,
				callerModule: callerModule,
				seams: seams,
				aliasDeclarationReferences: aliasDeclarationReferences,
				checkingModule: checkingModule,
				builtInlineSeamComment: builtInlineSeamComment,
			)
			let scopeInstantiables = scopeMap.mapValues(\.instantiable)
			let rootScopes = componentSeams.map { seam in
				Self.seamRootScope(of: seam, in: scopeMap, instantiables: scopeInstantiables, callerModule: callerModule, aliasDeclarationReferences: aliasDeclarationReferences)
			}
			let fulfillingKey = { (hole: SeamSignature.Hole) in
				Self.fulfillingInstantiable(of: hole, in: instantiables)?.concreteInstantiable
			}
			let frozenScopeMap = baseFrozenScopeMap.overlaying(passScopeMap: scopeMap, rootScopes: rootScopes, fulfillingKey: fulfillingKey)
			if let overlayOracle = ScopeTableObservation.overlayOracle {
				// The table every pass's map would freeze to, compared by key: what the pass's map holds and its seams
				// reach, the same record; what it does not hold, no record. A key whose scope the seams do not reach
				// keeps the base's record, which construction never reads.
				let passTable = FrozenScopeMap(freezing: scopeMap.lazy.map { (key: $0.key, scope: $0.value) }, interningIn: internerSpace).table
				let reachedScopes = Set(FrozenScopeMap.scopesReached(from: rootScopes, passScopeMap: scopeMap, fulfillingKey: fulfillingKey).map(ObjectIdentifier.init))
				let passKeys = scopeMap.compactMap { reachedScopes.contains(ObjectIdentifier($0.value)) ? $0.key : nil }
				let expected = passTable.projectionByKey(passKeys)
				let assembled = frozenScopeMap.table.projectionByKey(passKeys)
				var mismatches = [String]()
				for key in passKeys.sorted() where assembled[key] != expected[key] {
					mismatches.append("\(key.asSource): \(assembled[key] ?? "absent") instead of \(expected[key] ?? "absent")")
				}
				for key in instantiables.keys.sorted() where scopeMap[key] == nil && frozenScopeMap.table.id(forKey: key) != nil {
					mismatches.append("\(key.asSource): present outside the pass")
				}
				overlayOracle(mismatches)
			}
			var changed = false
			var skipsConfirmingPass = false
			var passErrors = [DependencyTreeGeneratorError]()
			var passFailedSeams = Set<TypeDescription>()
			for (seam, rootScope) in zip(componentSeams, rootScopes) {
				// A seam found to equal its own initializer is computed again from that initializer's parameters:
				// a change to the trees of the module's other seams can make it a seam after all.
				let previousSeamRoot = seamRoots[seam.concreteInstantiable] ?? nil
				do {
					let tree = try Self.seamRootGenerator(
						rootScope: rootScope,
						in: construction.signaturePass(over: frozenScopeMap),
						seamRoot: previousSeamRoot ?? initialSeamRoot(of: seam),
						declaredTypeNames: declaredTypeNames,
					)
					let generator = tree.generator
					let seamRoot = try Self.seamRoot(
						of: seam,
						generator: generator,
						proof: proof,
						instantiables: instantiables,
						ownScopeEnums: ownScopeEnums,
						generatesPlainInitializers: seams.generatesPlainDependencyTreeInitializers,
						declaredTypeNames: declaredTypeNames,
					)
					if seamRoot?.signature.settledContent != previousSeamRoot?.signature.settledContent {
						changed = true
					}
					if isFirstPass, maySkipConfirmingPass {
						skipsConfirmingPass = Self.confirmingPassFindsNothingNew(after: seamRoot, startingFrom: initialSeamRoot(of: seam), in: generator)
						// A seam equal to its own initializer generates no tree, so its pass's tree is released at once.
						if skipsConfirmingPass, keepsFirstPassTrees, seamRoot != nil {
							firstPassTree = SeamRootTree(
								generator: generator,
								fulfillers: TypeFactsImports(root: tree.rootScope, buildingMock: false).fulfillers,
								receivedValueSupplies: TypeFactsReceivedValueSupplies.whereRead(root: tree.rootScope),
								rootScope: RootScopeInfo.kept(tree.rootScope),
							)
						}
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
			// The pass read every seam as the pass before left it; the next reads what this one found.
			for seam in componentSeams {
				let seamType = seam.concreteInstantiable
				if case let previousSeamRoot?? = knownSeamRoots[seamType] {
					for scopeEnum in Self.ownScopeEnums(of: previousSeamRoot) {
						ownScopeEnums[scopeEnum.key] = nil
					}
				}
				let seamRoot = seamRoots[seamType] ?? nil
				knownSeamRoots[seamType] = .some(seamRoot)
				if let seamRoot {
					for scopeEnum in Self.ownScopeEnums(of: seamRoot) {
						ownScopeEnums[scopeEnum.key] = scopeEnum
					}
				}
			}
			if let skippedPass {
				// The test's confirming pass, run as every second pass runs, must have found what the first found. Its
				// state is put back to the first pass's, so the test generates what the tool generates.
				let seamType = componentSeams[0].concreteInstantiable
				skippedPass.confirm(StoredSeamSignature(seamType: seamType, signature: passFailedSeams.isEmpty ? (seamRoots[seamType] ?? nil)?.signature : nil), !passFailedSeams.isEmpty)
				seamRoots[seamType] = .some(skippedPass.seamRoot)
				knownSeamRoots = skippedPass.knownSeamRoots
				ownScopeEnums = skippedPass.ownScopeEnums
				settled = true
				break
			}
			if !changed || skipsConfirmingPass && passErrors.isEmpty {
				if changed, let confirmsSkippedPass = SeamSignatureObservation.confirmsSkippedPasses {
					let seamType = componentSeams[0].concreteInstantiable
					let seamRoot = seamRoots[seamType] ?? nil
					skippedPass = SkippedPass(seamRoot: seamRoot, knownSeamRoots: knownSeamRoots, ownScopeEnums: ownScopeEnums, confirm: { confirmed, threw in
						confirmsSkippedPass(SkippedConfirmingPass(
							skipped: StoredSeamSignature(seamType: seamType, signature: seamRoot?.signature),
							confirmed: confirmed,
							confirmingPassThrew: threw,
						))
					})
					isFirstPass = false
					continue
				}
				errorsOfLastPass = passErrors
				failedSeamsOfLastPass = passFailedSeams
				settled = true
				break
			}
			isFirstPass = false
		}
		if !settled {
			// A component holds at least one seam, so the first by location exists.
			if let firstSeam = componentSeams.min(by: { left, right in
				Dependency.DeclarationLocation.precedesInSourceOrder(left.declarationLocation, right.declarationLocation)
			}) {
				errorsOfLastPass = [.seam(.init(seam: firstSeam, kind: .signaturesDidNotSettle(seams: component.sorted())))]
			}
			failedSeamsOfLastPass = component
		}
		return SettledSeamComponent(
			seamRoots: componentSeams.map { ($0.concreteInstantiable, seamRoots[$0.concreteInstantiable] ?? nil) },
			errors: errorsOfLastPass,
			failedSeams: failedSeamsOfLastPass,
			firstPassTree: firstPassTree,
		)
	}

	/// What `seamSignatures` computed: each seam's signature, the errors of the last pass of each component, and the
	/// seams those errors belong to, which keep the signature they had.
	private struct SeamSignatureComputation {
		let seamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]
		let errors: [DependencyTreeGeneratorError]
		let failedSeams: Set<TypeDescription>
		/// The proof of every type's access the computation read, which says what a parameter's access depends on.
		/// `nil` when the computation has no seam, which builds no proof.
		let proof: TypeAccessProof?
		/// Where the computation keeps them, the tree the first pass built of each seam that pass settled without the
		/// pass that confirms it, with a signature and no error, by seam (see `seam-signature-passes.md`).
		var firstPassTrees = [TypeDescription: SeamRootTree]()
	}

	/// The strongly connected components of the graph in which a seam reaches another when its tree, built from
	/// `instantiables` without entering any seam of `seamTypes`, instantiates it, in reverse topological order: a
	/// component after every component it reaches (Tarjan's algorithm on an explicit stack), and the seams that reach
	/// themselves, which Tarjan's algorithm returns as a component of one seam like any other.
	static func stronglyConnectedComponents(of seams: [Instantiable], in instantiables: [TypeDescription: Instantiable], among seamTypes: Set<TypeDescription>) -> SeamComponents {
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
		return SeamComponents(
			components: stronglyConnectedComponents(of: seams.map(\.concreteInstantiable), edges: { reachedSeamsBySeam[$0, default: []] }),
			seamsReachingThemselves: Set(reachedSeamsBySeam.compactMap { seamType, reachedSeams in reachedSeams.contains(seamType) ? seamType : nil }),
		)
	}

	/// Whether a second pass over `seam`'s component, a component of one seam that does not reach itself, would find
	/// `firstPassSeamRoot` again, so that the first pass settles it. The pass reads nothing but its own seam root that the
	/// first pass changed: every seam its tree reaches is in a settled component, and its own entries in `knownSeamRoots`
	/// and `ownScopeEnums` are read only by a call of the seam itself or of a seam with holes. Of its seam root, the tree
	/// reads two things (see `seam-signature-passes.md`):
	/// - The parameters, put in scope at the root: the same when the first pass added none, compared by spelling, deferral
	///   and internal name in order. A `nil` root, a seam equal to its own initializer, is computed again from
	///   `initialSeamRoot`, as the first pass was.
	/// - The holes, builders and call routes (`SeamHoles`): read by code generation and the construction memo's sharing
	///   alone, but for reads made only where the tree calls a seam or a public mock, or builds a fill or passes a hole up.
	///   So the tree must hold none of those.
	private static func confirmingPassFindsNothingNew(after firstPassSeamRoot: ScopeGenerator.SeamRoot?, startingFrom initialSeamRoot: ScopeGenerator.SeamRoot, in generator: ScopeGenerator) -> Bool {
		if let firstPassSeamRoot {
			let firstParameters = firstPassSeamRoot.signature.parameters
			let initialParameters = initialSeamRoot.signature.parameters
			guard firstParameters.count == initialParameters.count else { return false }
			for (first, initial) in zip(firstParameters, initialParameters) {
				guard first.property.label == initial.property.label,
				      first.property.typeDescription.asSource == initial.property.typeDescription.asSource,
				      first.deferral == initial.deferral,
				      // Implied today by the checks above: the first pass adds no parameter, and a seam's own parameters are never
				      // deferred (`ownParameter`), so none is renamed apart from the tree's builder functions. Kept as a guard.
				      first.internalName == initial.internalName
				else { return false }
			}
		}
		var visited = Set<ObjectIdentifier>()
		var generatorsToVisit = [generator]
		while let visiting = generatorsToVisit.popLast() {
			// No shape found today needs this check: the seams a call reaches are in components settled before this one, and
			// the seam does not call itself (`seamsReachingThemselves`), so a call reads no signature the first pass changed,
			// and no seam test or seam corpus seed differs without it, even where the seam's fill of another seam's hole
			// builds a place that is a hole of this seam. Kept as a guard, since the reads of `SeamHoles` it excludes were
			// never shown not to reach a signature.
			guard visiting.seamCall == nil, visiting.publicMockCall == nil, visiting.fillKey == nil, visiting.passedUpHoles.isEmpty else { return false }
			for child in visiting.children where visited.insert(ObjectIdentifier(child)).inserted {
				generatorsToVisit.append(child)
			}
		}
		return true
	}

	/// A first pass whose confirming pass runs only for a test (`SeamSignatureObservation.confirmsSkippedPasses`): the
	/// state the skip left, which is put back after the confirming pass, and where to report what that pass found.
	private struct SkippedPass {
		let seamRoot: ScopeGenerator.SeamRoot?
		let knownSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]
		let ownScopeEnums: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]
		let confirm: (_ confirmed: StoredSeamSignature, _ threw: Bool) -> Void
	}

	/// The strongly connected components of the seam-reaches-seam graph (`stronglyConnectedComponents(of:in:among:)`).
	struct SeamComponents {
		/// The components, in reverse topological order.
		let components: [Set<TypeDescription>]
		/// The seams whose trees instantiate themselves, directly or through types that are not seams: each a component of
		/// one seam, whose pass reads its own signature.
		let seamsReachingThemselves: Set<TypeDescription>
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
	static func buildsTree(_ instantiable: Instantiable) -> Bool {
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

	static func ownParameter(_ property: Property, of seam: Instantiable, typeLevel: AccessLevel, isOnlyIfAvailable: Bool, proof: TypeAccessProof) -> SeamSignature.Parameter {
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
	static func tiers(of seam: Instantiable, parameters: [SeamSignature.Parameter]) -> [AccessLevel] {
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
	static func typesReachable(fromRoots roots: Set<TypeDescription>, in instantiables: [TypeDescription: Instantiable]) -> Set<TypeDescription> {
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
	///     (`DependencyTreeGenerator.builtInlineSeamComment(for:)`).
	private static func createSeamScopeMapping(
		in instantiables: [TypeDescription: Instantiable],
		reachableTypeDescriptions: Set<TypeDescription>,
		seamRoots: [TypeDescription: ScopeGenerator.SeamRoot?],
		ownSeamTypes: Set<TypeDescription>,
		callerModule: ModuleIdentity,
		seams: SeamResolution,
		aliasDeclarationReferences: AliasDeclarationReferences,
		checkingModule: EmittingModule?,
		builtInlineSeamComment: (Instantiable) -> String?,
	) -> [TypeDescription: Scope] {
		var typeDescriptionToScopeMap = [TypeDescription: Scope]()
		var scopes = [Scope]()
		// Visited in type order: a type the map holds under several keys gets one scope whichever key is met first.
		for typeDescription in reachableTypeDescriptions.sortedBySpelling() {
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
				Self.populatePropertiesToGenerate(of: scope, from: typeDescriptionToScopeMap, instantiables: instantiables, callerModule: callerModule, aliasDeclarationReferences: aliasDeclarationReferences)
			}
		}
		// Which labels each fill reads only if available, once every scope's tree is complete, for a place whose fields hold a
		// `LazilyInstantiated`: a fill takes such a wrapper optionally where the caller hands it
		// (`Scope.Fill.optionalLazilyInstantiatedLabels`). No other fill's parameters depend on it, so no other fill is walked.
		// The walk enters the fills of the seam calls inside the fulfilling type's tree, which receive from the fill's scope as
		// the fill's tree does.
		var receivedPropertiesCache = ReceivedPropertiesCache(walksSeamCallFills: true)
		for scope in scopes where scope.seamCall != nil {
			for case let .fill(hole, fulfillingScope) in scope.holeArguments where hole.fields.contains(where: { $0.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding != nil }) {
				let received = Self.collectReceivedProperties(from: fulfillingScope, cache: &receivedPropertiesCache)
				let requiredLabels = Set(received.received.subtracting(received.onlyIfAvailable).map(\.label))
				scope.fillLabelsReadOnlyIfAvailable[hole.site] = Set(received.received.map(\.label)).subtracting(requiredLabels)
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
		callerModule: ModuleIdentity,
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
				} else if dependency.isInstantiatedOnlyIfAvailable, callerModule.moduleName == nil {
					// A seam whose module SafeDI does not know takes no builder (`holesInSeamsOfUnnamedModule`), and no
					// module that could declare the type reads this one, so the property is `nil`, as in a module without a seam.
					scope.propertiesToGenerate.append(Self.unavailableDependency(dependency))
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
					declarationReference: aliasDeclarationReferences.reference(to: dependency.declarationLocation),
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
		instantiables: [TypeDescription: Instantiable],
		callerModule: ModuleIdentity,
		aliasDeclarationReferences: AliasDeclarationReferences,
	) -> Scope {
		let rootScope = Scope(instantiable: seam)
		populatePropertiesToGenerate(
			of: rootScope,
			from: typeDescriptionToScopeMap,
			instantiables: instantiables,
			callerModule: callerModule,
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
	/// as hidden, from the seam's own chain. Beside it, the root scope it is built from, whose table only a caller that keeps
	/// the tree reads, for its imports, and then drops.
	private static func seamRootGenerator(
		rootScope: Scope,
		in world: SeamTreeWorld,
		seamRoot: ScopeGenerator.SeamRoot,
		declaredTypeNames: DeclaredTypeNames,
	) throws -> (generator: ScopeGenerator, rootScope: ConstructionScope) {
		let (nearestDeclarations, lazilyInstantiatedInstanceProperties, _) = seamRootDeclarations(of: rootScope.instantiable, seamRoot: seamRoot)
		// A seam's tree reads its own `SeamHoles`, constant within the tree but not across trees, so it keeps a memo of its
		// own, for one pass: a seam without holes reuses its places within a pass, and one with holes stores none.
		var constructionMemo = ConstructionMemo()
		let (table, rootRecord) = world.frozenScopeMap.freezing(rootScope: rootScope)
		return try (
			generator: rootRecord.createScopeGenerator(
				in: table,
				nearestDeclarations: nearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				seamRoot: seamRoot,
				erasedToConcreteExistential: false,
				declaredTypeNames: declaredTypeNames,
				constructionMemo: &constructionMemo,
			),
			rootScope: ConstructionScope(table: table, record: rootRecord),
		)
	}

	/// What a seam's root is handed (`seamRootGenerator`): its parameters, as the nearest declarations of their labels, and
	/// the instances of `LazilyInstantiated` properties among them, a deferred parameter's memo included; and, for the
	/// seam's node records, the labels of those held in a wrapper that is not `Sendable`.
	static func seamRootDeclarations(
		of seam: Instantiable,
		seamRoot: ScopeGenerator.SeamRoot,
	) -> (nearestDeclarations: NearestDeclarations, lazilyInstantiatedInstanceProperties: Set<Property>, nonSendableWrapperLabels: Set<String>) {
		var nearestDeclarations = NearestDeclarations()
		var lazilyInstantiatedInstanceProperties = Set<Property>()
		var nonSendableWrapperLabels = Set<String>()
		let autoclosureCallByLabel = seamRoot.autoclosureCallByLabel(of: seam)
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
			// A `@Sendable` function of the tree that reads a parameter held in a wrapper that is not `Sendable` captures
			// it, as `ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)` declares them: a wrapper parameter, or
			// the memo of a deferred one that no `@Sendable` function was found to read.
			let isHeldInNonSendableWrapper = if case let .deferred(isSendable) = parameter.deferral, autoclosureCallByLabel[property.label] == nil {
				!isSendable
			} else {
				!property.propertyType.isConstant && !property.propertyType.isSendable
			}
			if isHeldInNonSendableWrapper {
				nonSendableWrapperLabels.insert(property.label)
			}
		}
		return (nearestDeclarations, lazilyInstantiatedInstanceProperties, nonSendableWrapperLabels)
	}

	/// A seam's tree kept for emission, with the modules its file imports for the types it builds, read from the
	/// declarations it was built from (`TypeFactsImports`) when it is kept, so that the table its root scope was frozen
	/// into, a copy of the module's frozen map, is freed once the generator is built rather than held for every seam.
	struct SeamRootTree: Sendable {
		let generator: ScopeGenerator
		let fulfillers: Set<FulfillerImports.Fulfiller>
		/// The supplies of the tree, read where it is built, or `nil` where nothing reads them
		/// (`TypeFactsReceivedValueSupplies.whereRead(root:)`).
		let receivedValueSupplies: ReceivedValueSupplies?
		/// The root scope the tree is built from, kept only where node records are made of it beside the tree
		/// (`RootScopeInfo.kept(_:)`).
		let rootScope: ConstructionScope?
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
	/// from the facts the emitters decorate from: `buildsInSendableFunction` and
	/// `ScopeGenerator.buildsInSendableFunction(ofFill:)`.
	static func receivers(in generator: ScopeGenerator, of _: Instantiable, instantiables: [TypeDescription: Instantiable]) -> (receivers: [SeamReceiver], parameterReads: ParameterReads) {
		var receivers = [SeamReceiver]()
		var keptDeclarationIndices = [ReceiverDeclaration: Int]()
		var parameterReads = ParameterReads()
		/// A generator to visit, with what the scopes enclosing it provide, whether it is built inside a `@Sendable`
		/// function, the labels the scopes enclosing it declare or forward, and, by label, the nearest fill enclosing it that
		/// binds the label from its struct, where no scope between declares it.
		struct Frame {
			let generator: ScopeGenerator
			let providedProperties: Set<Property>
			let insideSendable: Bool
			let declaredLabels: Set<String>
			let fillsBindingLabels: [String: ScopeGenerator]
		}
		var generatorsToVisit = [Frame(generator: generator, providedProperties: [], insideSendable: false, declaredLabels: [], fillsBindingLabels: [:])]
		// Several places of the tree can share one generator (see `ConstructionMemo`), so a seam whose screens each open
		// three screens of the next layer reaches the last layer's along a number of paths that grows with the layers'
		// power. A visit reads its frame only through what its generator's subtree reads from above it (`ReadsFromAbove`),
		// and what it hands each child is made of its frame label by label, so two visits of one generator whose frames
		// agree on those reads find the same receivers and record the same reads; the later one is not made. The reads and
		// the visits made die with the walk.
		let readsFromAbove = ReadsFromAbove(treeRootedAt: generator)
		var visitsMade = Set<ReceiversVisit>()
		var framesTaken = 0
		while let frame = generatorsToVisit.popLast() {
			framesTaken += 1
			let visited = frame.generator
			if let readsOfSubtree = readsFromAbove.projection(readBy: visited) {
				let visit = ReceiversVisit(
					generator: ObjectIdentifier(visited),
					insideSendable: frame.insideSendable,
					declaredLabels: frame.declaredLabels.intersection(readsOfSubtree.labels),
					providedProperties: frame.providedProperties.filter(readsOfSubtree.formsProviding.contains),
					fillsBindingLabels: frame.fillsBindingLabels.filter { readsOfSubtree.labels.contains($0.key) }.mapValues(ObjectIdentifier.init),
				)
				guard visitsMade.insert(visit).inserted else { continue }
			}
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
			// a place built in plain code reads them at the site, and one built inside a `@Sendable` function carries none, its
			// fill reading the caller's own.
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
						// A wrapper whose memo the nearest fill binding its label binds, of the wrapper's own kind, which validation lets
						// the read take too.
						|| frame.fillsBindingLabels[property.label]?.fillBoundMemo(servingWrapperRead: property) != nil
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
			// A declaration of a label hides an enclosing fill's binding of it; a fill's own binding is nearer than either.
			var childFillsBindingLabels = frame.fillsBindingLabels
			for property in visited.providedProperties where !childFillsBindingLabels.isEmpty {
				childFillsBindingLabels[property.label] = nil
			}
			for label in visited.fillStructBoundLabels {
				childFillsBindingLabels[label] = visited
			}
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
					fillsBindingLabels: childFillsBindingLabels,
				))
			}
			generatorsToVisit.reverseElements(from: firstChildIndex)
		}
		GenerationWork.record(framesTaken, by: .findingSeamReceivers)
		return (receivers, parameterReads)
	}

	/// A visit `receivers(in:of:instantiables:)` made: a generator, with its frame projected to what its subtree reads from
	/// above it. Each part is a part of the frame some judgement of the visit, or of a visit beneath it, reads: whether the
	/// scope is built inside a `@Sendable` function (each read), the labels declared above it (each read that reaches a
	/// parameter), what the scopes above provide of the forms that would provide a receive or an alias's fulfilling
	/// property (its provider), and the fill nearest it that binds a label (a wrapper read the fill's memo serves).
	/// `visitsMade` holds one per visit made, each holding a set of labels and one of properties no larger than what the
	/// visited subtree reads from above, until the walk returns.
	private struct ReceiversVisit: Hashable {
		let generator: ObjectIdentifier
		let insideSendable: Bool
		let declaredLabels: Set<String>
		let providedProperties: Set<Property>
		let fillsBindingLabels: [String: ObjectIdentifier]
	}

	/// What each generator's subtree in a seam's tree reads from the scopes above it, as `receivers(in:of:instantiables:)`
	/// reads it: by label, each label received, each label an alias is fulfilled by, each parameter label of a nested seam
	/// the scope calls, and each parameter label of the function a cycle-closing scope calls; and by form, each property
	/// received and each property an alias is fulfilled by, whose provider the walk looks for. What a scope provides is
	/// nearer its subtree than anything above it: its labels are declared, and no fill above binds them, wherever its
	/// subtree reads them, and a form it provides provides every read of that form. So a scope's reads from above are
	/// its own, and its children's less what it provides. Built once per walk, from the leaves up, visiting each generator
	/// once; it holds a set of labels and one of properties per generator, each no larger than what its subtree reads,
	/// and dies with the walk.
	private struct ReadsFromAbove {
		init(treeRootedAt root: ScopeGenerator) {
			var generatorsToVisit = [(generator: root, childrenAreRead: false)]
			while let (visited, childrenAreRead) = generatorsToVisit.popLast() {
				let identifier = ObjectIdentifier(visited)
				guard readsByGenerator[identifier] == nil else { continue }
				guard childrenAreRead else {
					generatorsToVisit.append((visited, true))
					for child in visited.children where readsByGenerator[ObjectIdentifier(child)] == nil {
						generatorsToVisit.append((child, false))
					}
					continue
				}
				// A site reads every parameter whose label no scope enclosing it declares, so the subtree that holds one reads
				// every label.
				var reads = Reads(labels: [], requests: [], readsEveryLabel: visited.holeSite != nil)
				let providedLabels = Set(visited.providedProperties.map(\.label))
				for child in visited.children {
					if let childReads = readsByGenerator[ObjectIdentifier(child)] {
						reads.labels.formUnion(childReads.labels.subtracting(providedLabels))
						for request in childReads.requests where !Self.isProvided(request, by: visited.providedProperties) {
							reads.requests.insert(request)
						}
						reads.readsEveryLabel = reads.readsEveryLabel || childReads.readsEveryLabel
					}
				}
				for parameter in visited.seamCallParameters ?? [] {
					reads.labels.insert(parameter.property.label)
				}
				if visited.closesPropertyCycle {
					for parameter in visited.cycleParameters {
						reads.labels.insert(parameter.property.label)
					}
				}
				for dependency in visited.builtInstantiable?.dependencies ?? [] {
					switch dependency.source {
					case .received:
						reads.labels.insert(dependency.property.label)
						reads.requests.insert(dependency.property)
					case let .aliased(fulfillingProperty, _, _):
						reads.labels.insert(fulfillingProperty.label)
						reads.requests.insert(fulfillingProperty)
					case .instantiated, .forwarded:
						continue
					}
				}
				readsByGenerator[identifier] = reads
			}
		}

		/// What the subtree `generator` roots reads from above it, or `nil` where it holds a site, which reads every label.
		func projection(readBy generator: ScopeGenerator) -> Projection? {
			guard let reads = readsByGenerator[ObjectIdentifier(generator)], !reads.readsEveryLabel else { return nil }
			var formsProviding = reads.requests
			for request in reads.requests where request.typeDescription.isOptional {
				formsProviding.insert(request.asUnwrappedProperty)
			}
			return Projection(labels: reads.labels, formsProviding: formsProviding)
		}

		/// What a subtree reads from above it: the labels it reads, and each form of a property that would provide one of
		/// its receives or aliases' fulfilling properties.
		struct Projection {
			let labels: Set<String>
			let formsProviding: Set<Property>
		}

		/// Whether `providedProperties` provides a read of `property`, as the walk's own check finds it but for a fill's memo,
		/// which a scope never provides.
		private static func isProvided(_ property: Property, by providedProperties: Set<Property>) -> Bool {
			providedProperties.contains(property)
				|| (property.typeDescription.isOptional && providedProperties.contains(property.asUnwrappedProperty))
		}

		private struct Reads {
			var labels: Set<String>
			var requests: Set<Property>
			var readsEveryLabel: Bool
		}

		private var readsByGenerator = [ObjectIdentifier: Reads]()
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
	private static func seamRoot(of seam: Instantiable, generator: ScopeGenerator, proof: TypeAccessProof, instantiables: [TypeDescription: Instantiable], ownScopeEnums: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum], generatesPlainInitializers: Bool, declaredTypeNames: DeclaredTypeNames) throws -> ScopeGenerator.SeamRoot? {
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
			var remedy = Self.labelCollisionRemedy(among: collidingReceivers.map(\.property), requiredProperties: requiredProperties)
			if case .declareProvidingForm = remedy,
			   let requiredForm = Self.requiredFormOfWrapperOnlySeamReceives(
			   	among: collidingReceivers.map { ($0.property, $0.declaringType) },
			   	seam: seam.concreteInstantiable,
			   	requiredProperties: requiredProperties,
			   	instantiables: instantiables,
			   )
			{
				remedy = .declareRequiredForm(requiredForm.typeDescription.asSource)
			}
			return .seam(.init(seam: seam, kind: .parameters(.parametersShareLabel(
				label: label,
				receivers: collidingReceivers.map(\.asErrorReceiver),
				remedy: remedy,
			))))
		}

		// The forms the tree receives, from the receives that leave the seam on some path. Every tree receiver is a
		// parameter candidate: a receive beneath a declaration of its label that does not provide it never reaches
		// here, since validation reports it as the inline hidden-label error from the seam's chain.
		// Each in its receivers' most explicit spelling, an alias's receive as its property spells it, so which of two
		// spellings `==` calls equal (`any P` and `P`) a parameter takes is decided by neither the walk's order nor the
		// set's (`ValueSpellings`).
		var receivedProperties = Set<Property>()
		for receiver in treeReceivers {
			receivedProperties.insertKeepingMostExplicitSpelling(receiver.aliasProperty.map { ValueSpellings.fulfillingProperty(receiver.property, spelledAsAlias: $0) } ?? receiver.property)
		}
		// In sorted order, so that the forms of each label are in the same order in every process, in the seam's module
		// and in each caller's. An `onlyIfAvailable` alias's fulfilling property is spelled non-optional (`ofType: X.self`)
		// and received only if available: it is the optional form, which the parameter its optional receives take provides,
		// and from which the alias is bound.
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
			// The forms of the label are one value, which every parameter of it spells one way.
			let valueSpellings = ValueSpellings(of: forms)
			if !ownLabels.contains(label), !labelReceivers.isEmpty, labelReceivers.allSatisfy(\.isNoTier), let form = forms.first {
				let unspelledProperty = form.typeDescription.isOptional ? form : form.asOptionalProperty
				let property = valueSpellings.spelling(ofValueOf: unspelledProperty)
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
			// A form the seam's own property of the label does not provide is a second parameter under the label, as is a form
			// beside which no one parameter takes the others.
			guard !ownLabels.contains(label), let providingForm = Self.providingForm(among: forms) else {
				errors.append(labelCollision(label, among: receivers(ofLabel: label)))
				continue
			}
			let unspelledParameterProperty: Property
			let isRequired: Bool
			var deferral = SeamSignature.Parameter.Deferral.none
			switch providingForm {
			case let .requiredWrapper(requiredWrapper):
				unspelledParameterProperty = requiredWrapper
				isRequired = true
			case let .value(value):
				// One by-value property and its optional form are one parameter: the unwrapped form where a receiver
				// requires a non-optional form, and otherwise the optional type, required where some receiver requires
				// it, since the property the caller's tree declares may be optional too (a forwarded `x: X?`).
				let takesUnwrappedForm = requiredProperties.contains(value)
				unspelledParameterProperty = takesUnwrappedForm ? value : Property(label: label, typeDescription: .optional(value.typeDescription))
				isRequired = takesUnwrappedForm || forms.contains(where: requiredProperties.contains)
				// A by-value pass-through the tree reads is deferred: the tree reads it where it would read the caller's value
				// inline, when a receiver is first built. An instantiator is a value whose instantiation is deferred already,
				// which the caller hands on as inline. It is `@Sendable` where a `@Sendable` function inside the tree reads it.
				if unspelledParameterProperty.asUnwrappedProperty.propertyType.isConstant, parameterReads.reads(label) {
					deferral = .deferred(isSendable: parameterReads.readsInsideSendableFunction(label))
				}
			case let .optionalWrapper(wrapper):
				unspelledParameterProperty = Property(label: label, typeDescription: .optional(wrapper.typeDescription))
				isRequired = requiredProperties.contains(unspelledParameterProperty)
			}
			let parameterProperty = valueSpellings.spelling(ofValueOf: unspelledParameterProperty)
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
		for (hole, builder) in shapedBuilders.holesWithBuilders {
			guard let tier = tiers.first(where: { $0 > hole.tierAccess }),
			      reportedHoleDeclarations.insert(OwnedHoleDeclaration(owner: hole.ownerType, property: hole.property)).inserted
			else { continue }
			errors.append(.seam(.init(seam: seam, kind: .tierOmitsBuilder(hole: hole, builder: builder, tier: tier))))
		}
		// The places of one builder must forward one value, since the builder a person writes takes it: each place that forwards
		// another value than the first by location is reported, wherever the builder's places are, an inner seam's included.
		let enumsByKey = Dictionary(shapedBuilders.scopeEnums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		for builder in shapedBuilders.builders {
			let reachedSites = SeamSignature.ScopeEnum.sitesReached(from: builder.enumKey, in: enumsByKey)
			errors += placesForwardingOtherValuesErrors(
				of: seam,
				places: holes.filter { reachedSites.contains($0.site) },
				holeType: builder.enumKey.holeType,
				isSendable: builder.enumKey.isSendable,
				instantiables: instantiables,
				declaredTypeNames: declaredTypeNames,
			)
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
		return ScopeGenerator.SeamRoot(
			signature: SeamSignature(
				seamType: seam.concreteInstantiable,
				parameters: parameters,
				tiers: tiers,
				noTierParameters: noTierParameters,
				holes: holes,
				builders: shapedBuilders.builders,
				scopeEnums: shapedBuilders.scopeEnums,
				typesDeclaredEscaping: generator.typesDeclaredEscaping.intersection(parameters.map(\.property.typeDescription)),
			),
			callRoutes: shapedBuilders.callRoutes,
			routeMembersBySite: shapedBuilders.routeMembersBySite,
		)
	}

	/// Whether a call of `initializer` can pass exactly `labels`, in order: they match its arguments' labels in order,
	/// and every argument they leave out has a default value.
	static func initializer(_ initializer: Initializer, isCallableWithLabels labels: [String]) -> Bool {
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
	static func labelCollisionRemedy(among forms: [Property], requiredProperties: Set<Property>) -> DependencyTreeGeneratorError.SeamError.LabelCollisionRemedy {
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

	/// The by-value form of one label that a type of a seam's tree requires, where every wrapper form of the label is the
	/// seam's own receive and no declaration `instantiables` holds outside the seam provides that wrapper: then
	/// `labelCollisionRemedy(among:requiredProperties:)`'s providing form, the wrapper, is one nothing proves a caller
	/// holds, while the tree's requirement of the value is a fact of the graph in hand. `nil` otherwise. Only the seam's
	/// own collision asks: a fill's collision keeps the providing form, since its caller is the module that fills it.
	static func requiredFormOfWrapperOnlySeamReceives(
		among receivers: [(property: Property, declaringType: TypeDescription)],
		seam: TypeDescription,
		requiredProperties: Set<Property>,
		instantiables: [TypeDescription: Instantiable],
	) -> Property? {
		let wrappers = receivers.filter { $0.property.typeDescription.unwrapped.lazilyInstantiatedInstanceType != nil }
		guard !wrappers.isEmpty,
		      wrappers.allSatisfy({ $0.declaringType == seam }),
		      let requiredForm = receivers.first(where: { receiver in
		      	receiver.property.typeDescription.lazilyInstantiatedInstanceType == nil
		      		&& !receiver.property.typeDescription.isOptional
		      		&& requiredProperties.contains(receiver.property)
		      })?.property
		else { return nil }
		let wrapperProperties = Set(wrappers.map(\.property.asUnwrappedProperty))
		// Whether any declaration outside the seam provides the wrapper; the answer, not an element, is what is used, so
		// the dictionary's order decides nothing.
		let wrapperProvidedOutsideSeam = instantiables.values.contains { instantiable in
			instantiable.concreteInstantiable != seam && instantiable.dependencies.contains { dependency in
				switch dependency.source {
				case .instantiated, .forwarded, .aliased:
					wrapperProperties.contains(dependency.property)
				case .received:
					false
				}
			}
		}
		return wrapperProvidedOutsideSeam ? nil : requiredForm
	}

	/// The one form that provides each of `forms`, the forms of one label a seam's tree receives from outside it that the
	/// seam's own properties do not provide, each received only if available spelled optional, or `nil` where no one
	/// parameter can take them all (`parametersShareLabel`). A required non-optional wrapper (a wrapper received only if
	/// available is optional) provides every by-value form of its instance and the optional form of its kind, and any
	/// other form beside it is a second parameter; one by-value type is one parameter with its optional form; an optional
	/// wrapper provides nothing but itself, so a by-value form or another kind beside it is a second parameter.
	static func providingForm(among forms: [Property]) -> ProvidingForm? {
		let wrappers = forms.filter { $0.typeDescription.unwrapped.lazilyInstantiatedInstanceType != nil }
		let unwrappedWrappers = Set(wrappers.map(\.asUnwrappedProperty))
		let unwrappedValues = Set(forms.filter { $0.typeDescription.unwrapped.lazilyInstantiatedInstanceType == nil }.map(\.asUnwrappedProperty))
		if let requiredWrapper = wrappers.filter({ !$0.typeDescription.isOptional }).sorted().first {
			guard unwrappedWrappers == [requiredWrapper],
			      unwrappedValues.allSatisfy({ $0.typeDescription == requiredWrapper.typeDescription.lazilyInstantiatedInstanceType })
			else { return nil }
			return .requiredWrapper(requiredWrapper)
		} else if unwrappedWrappers.isEmpty {
			guard unwrappedValues.count == 1, let value = unwrappedValues.first else { return nil }
			return .value(value)
		} else {
			guard unwrappedValues.isEmpty, unwrappedWrappers.count == 1, let wrapper = unwrappedWrappers.first else { return nil }
			return .optionalWrapper(wrapper)
		}
	}

	/// The form that provides every form of one label a seam's tree receives (`providingForm(among:)`), unwrapped.
	enum ProvidingForm {
		/// A non-optional `LazilyInstantiated` or `SendableLazilyInstantiated` some receiver requires.
		case requiredWrapper(Property)
		/// A by-value property.
		case value(Property)
		/// A wrapper every receiver of which receives it only if available.
		case optionalWrapper(Property)
	}

	/// The forms of `parameter`'s label that a seam parameter of that property provides to the seam's tree, which then
	/// add no parameter: a non-optional `LazilyInstantiated` or `SendableLazilyInstantiated` provides its optional form
	/// and the by-value forms of its instance, as a wrapper a type receives offers its instance to the types beneath
	/// it; a by-value property provides its optional form; an optional wrapper provides nothing but itself.
	static func formsProvided(by parameter: Property) -> Set<Property> {
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
}

/// The test hooks of seam signature computation: test only.
public enum SeamSignatureObservation {
	/// Called, when set, for each seam whose first signature pass settled it without the pass that confirms it
	/// (`DependencyTreeGenerator.confirmingPassFindsNothingNew`), after running that pass anyway as every second pass runs:
	/// the two must find the same signature. The tool generates from the first pass's either way.
	@TaskLocal public static var confirmsSkippedPasses: (@Sendable (SkippedConfirmingPass) -> Void)?
	/// When set, how many tasks settle one level of a module's seam components at once, in place of the processor
	/// count, so that a test runs a level on one task or on several whatever machine runs it.
	@TaskLocal public static var width: Int?
	/// Called, when set, for each level of a module's seam components, in level order, with how many tasks settle it.
	@TaskLocal public static var observesLevels: (@Sendable (SeamSignatureLevel) -> Void)?
}

/// One level of a module's seam components, as `seamSignatures` settles it.
public struct SeamSignatureLevel: Equatable, Sendable {
	/// How many components the level holds.
	public let componentCount: Int
	/// How many tasks settle them.
	public let taskCount: Int

	public init(componentCount: Int, taskCount: Int) {
		self.componentCount = componentCount
		self.taskCount = taskCount
	}
}

/// Observes the trees of the seams this module generates that emission makes again from their first signature pass's
/// tree (`ScopeGenerator.reseating(treeRootedAt:of:seamRoot:)`), for tests.
public enum SeamTreeReuseObservation {
	/// Called, when set, for each seam whose tree emission made again, with the code of that tree and of the tree built
	/// anew as emission builds every other seam's: the two must be the same text.
	@TaskLocal public static var comparesBuiltTrees: (@Sendable (ReusedSeamTree) -> Void)?
}

/// A seam whose tree emission made again from its first signature pass's, with the code of both trees.
public struct ReusedSeamTree: Sendable {
	/// The seam's final signature, from which both trees are made.
	public let signature: StoredSeamSignature
	/// The code of the tree made again, which the tool generates.
	public let reusedTreeCode: @Sendable () async throws -> String
	/// The code of the tree built anew from the final signature.
	public let builtTreeCode: @Sendable () async throws -> String
}

/// A seam's signature from the first pass that settled it, and the one the confirming pass the tool skipped finds.
public struct SkippedConfirmingPass: Sendable {
	/// What the first pass found, which the tool keeps.
	public let skipped: StoredSeamSignature
	/// What the confirming pass found: no signature when it threw (`confirmingPassThrew`).
	public let confirmed: StoredSeamSignature
	public let confirmingPassThrew: Bool
}
