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
	/// Validates that no `@Sendable` builder function in the trees rooted at `roots` would capture an
	/// `Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated` declared outside it, none of which is
	/// `Sendable`. See `ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`.
	///
	/// A receiver that several roots, or several paths through one tree, reach is reported once for each chain, as
	/// an unfulfillable dependency is, rather than once with the chain of whichever root sorts first: which root a
	/// diagnostic names must not depend on the order of names.
	func validateSendableBuildersCaptureNoNonSendableWrapper(
		inTreesRootedAt roots: [(instantiable: Instantiable, scopeGenerator: ScopeGenerator)],
	) async throws {
		// Walking the trees costs a pass over every scope, so only a module whose types name both a wrapper
		// that is not `Sendable` and a `Sendable` builder pays for it.
		let dependencies = typeDescriptionToFulfillingInstantiableMap.values.lazy.flatMap(\.dependencies)
		guard dependencies.contains(where: { !$0.property.propertyType.isConstant && !$0.property.propertyType.isSendable }),
		      dependencies.contains(where: \.property.propertyType.isSendable)
		else { return }
		// Two paths can reach one receiver through the same chain of types, so identical captures are reported once.
		// The trees are walked in parallel: the captures are a set, which the error sorts into source order.
		let captures = await withTaskGroup(
			of: [ScopeGenerator.NonSendableWrapperCapture].self,
			returning: Set<ScopeGenerator.NonSendableWrapperCapture>.self,
		) { taskGroup in
			for root in roots {
				taskGroup.addTask {
					await root.scopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt: root.instantiable)
				}
			}
			var captures = Set<ScopeGenerator.NonSendableWrapperCapture>()
			for await rootCaptures in taskGroup {
				captures.formUnion(rootCaptures)
			}
			return captures
		}
		if !captures.isEmpty {
			throw DependencyTreeGeneratorError.nonSendableWrapperCapturedBySendableBuilder(Array(captures))
		}
	}

	/// The calls of seams' tiers in the tree rooted at `rootScope` that omit a value the tree holds, read where the tree is
	/// built, so that no root keeps its frozen table until validation; `nil` where the module checks none.
	func seamTierOmissions(ofTreeRootedAt rootScope: ConstructionScope, instantiable: Instantiable, seamRoot: ScopeGenerator.SeamRoot?) -> [ScopeGenerator.SeamTierOmission]? {
		guard !seams.isEmpty, let emittingModule else { return nil }
		return TypeFactsSeamTierOmissions(root: rootScope, instantiable: instantiable, seamRoot: seamRoot, isOwnFile: emittingModule.isOwnFile).omissions
	}

	/// Validates that no call of a seam's generated initializer in the trees rooted at `roots` drops a value the tree
	/// holds: a value for a parameter the tier the call reaches omits, or no tier takes, which the receivers inside
	/// the seam would be handed were the tree built inline. Reads each root's per-type graph (`TypeFactsSeamTierOmissions`),
	/// before any code is generated, and reports every finding of every root, in source order.
	func validateNoSeamTierOmitsProvidedValue(inTreesRootedAt roots: [RootScopeInfo]) async throws {
		// A module that calls no seam's tier omitting a parameter has nothing to read. A run that knows of a seam knows
		// its module.
		guard !seams.isEmpty, let emittingModule else { return }
		var omissions = [DependencyTreeGeneratorError.ProvidedValueOmission]()
		for root in roots {
			let folded = root.seamTierOmissions ?? []
			if let observer = TypeFactsSeamTierOmissionsObservation.comparesWalk {
				let walked = await GenerationWork.$observer.withValue(nil) {
					await root.scopeGenerator.seamTierOmissions(ofTreeRootedAt: root.instantiable, isOwnFile: emittingModule.isOwnFile)
				}
				observer(TypeFactsSeamTierOmissionsComparison(root: root.typeDescription.asSource, folded: folded.map(\.comparedSpelling), walked: walked.map(\.comparedSpelling)))
			}
			for omission in folded {
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
	static func validateDependencyLabelsAreDistinct(in instantiables: some Sequence<Instantiable>) throws {
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

	/// Rejects each hand-written mock the mock tree rooted at `mockRootScope` calls that takes a parameter without a
	/// default value the generated call cannot pass: the mocked type's own mock, which builds it, and the mock of each type
	/// the tree, or a fill a call in it declares, builds with its mock, as generation chooses one – where the mock returns a
	/// type the property it builds accepts. Each is reported, in source order. A type no mock tree builds with its
	/// hand-written mock traps nowhere, so it is not reported: a shape that works must not become an error.
	static func validateHandWrittenMocksTakeOnlyFulfilledParameters(inMockTreeRootedAt mockRootScope: Scope) throws {
		var unfulfilledMockParameters = [DependencyTreeGeneratorError.UnfulfilledMockParameter]()
		var checkedScopes = Set<ObjectIdentifier>()
		var visitedScopes = Set<ObjectIdentifier>()
		var scopesToVisit = [(scope: mockRootScope, isBuiltWithHandWrittenMock: true)]
		while let scopeToVisit = scopesToVisit.popLast() {
			let scope = scopeToVisit.scope
			// A call of another module's public mock, or of a seam's generated initializer, calls no hand-written mock.
			if scopeToVisit.isBuiltWithHandWrittenMock,
			   scope.publicMockCall == nil,
			   scope.seamCall == nil,
			   checkedScopes.insert(ObjectIdentifier(scope)).inserted
			{
				unfulfilledMockParameters += DependencyTreeGeneratorError.UnfulfilledMockParameter.parameters(ofMockOf: scope.instantiable)
			}
			guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
				scopesToVisit.append((childScope, childScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType)))
			}
			for case let .fill(hole, fillScope) in scope.holeArguments {
				scopesToVisit.append((fillScope, fillScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: hole.property.typeDescription.asInstantiatedType)))
			}
		}
		if !unfulfilledMockParameters.isEmpty {
			throw DependencyTreeGeneratorError.unfulfilledMockParameters(unfulfilledMockParameters)
		}
	}

	/// Rejects each of `instantiables` that declares a rename the `@Instantiable` macro rejects. See `RejectedRename`.
	/// Each is reported, in source order. Callers pass the declarations a production root's or a mock root's tree
	/// builds, before any validation walk of that tree reads their dependencies, so that nothing after this sees such a
	/// rename: the renames of one declaration are each fulfilled by a property it receives or declares as no rename, or
	/// retype the label they keep.
	static func validateRenamesAreSpelledAsTheMacroAccepts(in instantiables: some Sequence<Instantiable>) throws {
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
	static func validateRenamesAreSpelledAsTheMacroAccepts(
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
	static func rejectedRenames(declaredBy instantiable: Instantiable) -> [DependencyTreeGeneratorError.RejectedRename] {
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

	/// - Parameter foreignSeamRoots: The signatures of the foreign seams this module's trees reach
	///   (`computeForeignSeamRoots()`).
	func validateReachableTypeDescriptions(foreignSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]) throws {
		// In a module that holds or calls a seam, only the types reached outside every seam's tree are reported
		// (`typesReachableOutsideSeamTrees`). A type reached only beneath a seam another module declares may be one
		// this module cannot see, which the seam's module could: it is left to that module to report, and the
		// generated call fails to compile where the two disagree. A type a seam's tree reaches that no production
		// declaration fulfills is a hole, whose builder the seam's generated initializer takes, unless only
		// hand-written code could build it; a root that calls the seam and cannot fill the builder is reported where
		// its tree is generated.
		let unbuildableTypeDescriptions = (seams.isEmpty ? reachableTypeDescriptions : try typesReachableOutsideSeamTrees(foreignSeamRoots: foreignSeamRoots))
			.filter { typeDescriptionToFulfillingInstantiableMap[$0]?.mockOnly != false }
		guard !unbuildableTypeDescriptions.isEmpty else { return }
		throw noInstantiableFoundErrors(of: unbuildableTypeDescriptions)
	}

	/// The error that no declaration fulfills each of `unbuildableTypeDescriptions`, at every property that instantiates it.
	func noInstantiableFoundErrors(of unbuildableTypeDescriptions: Set<TypeDescription>) -> DependencyTreeGeneratorError {
		// The map's values can hold the same instantiable under several keys, so collect into sets.
		var referencingPropertiesByType = [TypeDescription: Set<DependencyTreeGeneratorError.LocatedProperty>]()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			for dependency in instantiable.dependencies where dependency.isInstantiated && unbuildableTypeDescriptions.contains(dependency.asInstantiatedType) {
				referencingPropertiesByType[dependency.asInstantiatedType, default: []].insert(
					DependencyTreeGeneratorError.LocatedProperty(property: dependency.property, declarationLocation: dependency.declarationLocation),
				)
			}
		}
		return DependencyTreeGeneratorError.independentErrors(unbuildableTypeDescriptions.map { unbuildableTypeDescription in
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
