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

import SafeDICore

/// `unnormalizedInstantiables` with each type a declaration spells – each dependency's property type, `fulfilledByType:`
/// type, and alias `ofType:` type, the arguments of its initializer, other initializers, and hand-written mock, and that
/// mock's return type – qualified as the compiler resolves it where the declaration spells it, so generated code outside
/// the declaration names the same type. The type a dependency instantiates is qualified among the types the
/// instantiables fulfill, so a nested type wins over a top-level type of the same name
/// (`TypeDescription.qualifyingInstantiatedType(within:amongInstantiableTypes:searchingTypesEnclosingIt:namesOfNestedInstantiableTypes:)`);
/// then each outermost name is qualified among those types and `plainTypeDeclarations`
/// (`TypeAccessProof.NestedTypeQualifier`), so a type nested in the declaration's type, or in a type enclosing it, is
/// qualified though it is not `@Instantiable`.
/// - Parameters:
///   - plainTypeDeclarations: The plain type declarations of the modules whose declarations `unnormalizedInstantiables`
///     holds, each with the module that declares it.
///   - reach: Which declarations a mention in each module can name.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func normalizingInstantiableTypes(of unnormalizedInstantiables: [Instantiable], plainTypeDeclarations: [PlainTypeDeclaration], reach: TypeAccessProof.ModuleReach) -> [Instantiable] {
	let instantiableTypes = Set(unnormalizedInstantiables.flatMap(\.instantiableTypes))
	let nestedTypeQualifier = TypeAccessProof.NestedTypeQualifier(instantiables: unnormalizedInstantiables, plainTypeDeclarations: plainTypeDeclarations, reach: reach)
	return unnormalizedInstantiables.map { unnormalizedInstantiable in
		let mentioningModule = TypeAccessProof.MentioningModule.declaration(unnormalizedInstantiable)
		// An extension-based declaration's members are written in an extension at file scope.
		let searchingTypesEnclosingIt = !unnormalizedInstantiable.declarationType.isExtension
		/// The instantiated type of `typeDescription` qualified among the instantiable types, or `nil` when no option
		/// of it is one or the option is the type as written.
		func qualifyingInstantiatedType(_ typeDescription: TypeDescription) -> TypeDescription? {
			nestedTypeQualifier.qualifyingInstantiatedType(
				in: typeDescription,
				writtenWithin: unnormalizedInstantiable.concreteInstantiable,
				searchingTypesEnclosingIt: searchingTypesEnclosingIt,
			)
			// Every option but the type as written nests a name the type as written does not, so an option `==` finds
			// the same is the type as written, which is kept rather than rebuilt.
			.flatMap { $0 == typeDescription ? nil : $0 }
		}
		/// `typeDescription`, which a member of the declaration spells, qualified as the compiler resolves it there, or
		/// `nil` when that qualifies nothing, so that what spells it is kept rather than rebuilt.
		func normalized(_ typeDescription: TypeDescription) -> TypeDescription? {
			let instantiatedTypeQualified = qualifyingInstantiatedType(typeDescription)
			return nestedTypeQualifier.qualifyingNestedTypes(
				in: instantiatedTypeQualified ?? typeDescription,
				writtenWithin: unnormalizedInstantiable.concreteInstantiable,
				searchingTypesEnclosingIt: searchingTypesEnclosingIt,
				mentionedFrom: mentioningModule,
			) ?? instantiatedTypeQualified
		}
		/// `argument` with its type normalized, as its declaration spells it.
		func normalizedArgument(_ argument: Initializer.Argument) -> Initializer.Argument {
			normalized(argument.typeDescription).map(argument.withUpdatedTypeDescription) ?? argument
		}

		let normalizedDependencies = unnormalizedInstantiable.dependencies.map { dependency in
			// The type that fulfills an instantiated or aliased dependency is written where the property is.
			let normalizedSource: Dependency.Source? = switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				// `fulfilledByType:` names an `@Instantiable` type, or the dependency is reported unfulfillable.
				fulfillingTypeDescription.flatMap(qualifyingInstantiatedType).map {
					.instantiated(
						fulfillingTypeDescription: $0,
						erasedToConcreteExistential: erasedToConcreteExistential,
					)
				}
			case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
				normalized(fulfillingProperty.typeDescription).map {
					.aliased(
						fulfillingProperty: fulfillingProperty.withUpdatedTypeDescription($0),
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
					)
				}
			case .forwarded, .received:
				nil
			}
			let normalizedPropertyType = normalized(dependency.property.typeDescription)
			guard normalizedSource != nil || normalizedPropertyType != nil else {
				// Normalization qualifies nothing the dependency spells.
				return dependency
			}
			return Dependency(
				property: normalizedPropertyType.map(dependency.property.withUpdatedTypeDescription) ?? dependency.property,
				source: normalizedSource ?? dependency.source,
				declarationLocation: dependency.declarationLocation,
				identifierRange: dependency.identifierRange,
				typeAnnotationRange: dependency.typeAnnotationRange,
				bareAttributeRange: dependency.bareAttributeRange,
			)
		}
		// Each argument is qualified on its own, which qualifies a dependency's argument as its property: the same type
		// written in the same place.
		let normalizedInitializer = unnormalizedInstantiable.initializer?.mapArguments(normalizedArgument)
		let normalizedAdditionalInstantiables = unnormalizedInstantiable.instantiableTypes.dropFirst().map {
			if let enclosingType = unnormalizedInstantiable.concreteInstantiable.popNested, !unnormalizedInstantiable.declarationType.isExtension {
				// `fulfillingAdditionalTypes:` is written in the macro's attribute, outside the type, in the types
				// enclosing it; on an extension, at file scope, where every name is as written.
				let qualifiedInstantiableType = TypeDescription.nestedOptions(
					referencedType: $0,
					within: enclosingType,
				).first(where: { instantiableTypes.contains($0) }) ?? $0
				return nestedTypeQualifier.qualifyingNestedTypes(
					in: qualifiedInstantiableType,
					writtenWithin: enclosingType,
					searchingTypesEnclosingIt: true,
					mentionedFrom: mentioningModule,
				) ?? qualifiedInstantiableType
			} else {
				// A top-level type's attribute is written at file scope, where every name is as written.
				return $0
			}
		}
		var normalizedInstantiable = Instantiable(
			instantiableType: unnormalizedInstantiable.concreteInstantiable,
			isRoot: unnormalizedInstantiable.isRoot,
			generatesDependencyTree: unnormalizedInstantiable.generatesDependencyTree,
			initializer: normalizedInitializer,
			// An initializer SafeDI never constructs the type with is compared with a generated tier's parameters by
			// type, so each argument's type is qualified on its own, as a hand-written mock's are: a nested
			// pass-through type it names unqualified must match the qualified parameter.
			otherInitializers: unnormalizedInstantiable.otherInitializers.compactMap { $0.mapArguments(normalizedArgument) },
			additionalInstantiables: normalizedAdditionalInstantiables,
			dependencies: normalizedDependencies,
			declarationType: unnormalizedInstantiable.declarationType,
			access: unnormalizedInstantiable.access,
			enclosingTypeAccess: unnormalizedInstantiable.enclosingTypeAccess,
			enclosingExtensionAccess: unnormalizedInstantiable.enclosingExtensionAccess,
			generatedInitializerAttributes: unnormalizedInstantiable.generatedInitializerAttributes,
			mockAttributes: unnormalizedInstantiable.mockAttributes,
			declarationIsolation: unnormalizedInstantiable.declarationIsolation,
			generateMock: unnormalizedInstantiable.generateMock,
			mockGenerationArgumentRange: unnormalizedInstantiable.mockGenerationArgumentRange,
			mockOnly: unnormalizedInstantiable.mockOnly,
			// A hand-written mock's arguments are matched to dependencies by type. A `mockOnly` declaration has no
			// dependencies of its own to map them by, and its mock is matched to those of the declaration it merges
			// into, so each argument's type is qualified on its own.
			mockInitializer: unnormalizedInstantiable.mockInitializer?.mapArguments(normalizedArgument),
			// The macro requires a hand-written mock to return `Self` or the type's name as its declaration spells
			// it, so a nested type's mock returns its unqualified name.
			mockReturnType: unnormalizedInstantiable.mockReturnType.map { normalized($0) ?? $0 },
			customMockName: unnormalizedInstantiable.customMockName,
			mockDeclarationLocation: unnormalizedInstantiable.mockDeclarationLocation,
			mockDeclarationAccess: unnormalizedInstantiable.mockDeclarationAccess,
			mockDeclarationModuleName: unnormalizedInstantiable.mockDeclarationModuleName,
			mockDeclarationPackageName: unnormalizedInstantiable.mockDeclarationPackageName,
			declarationLocation: unnormalizedInstantiable.declarationLocation,
			moduleName: unnormalizedInstantiable.moduleName,
			packageName: unnormalizedInstantiable.packageName,
		)
		normalizedInstantiable.sourceFilePath = unnormalizedInstantiable.sourceFilePath
		normalizedInstantiable.isInsideCompilerDecidedBlock = unnormalizedInstantiable.isInsideCompilerDecidedBlock
		return normalizedInstantiable
	}
}

/// `normalizedInstantiables` with each type two or more production declarations fulfill told apart from the types `viewer`
/// cannot name, so that those stop competing with each other and with what `viewer` can name, and SafeDI still checks
/// them: a declaration `viewer` cannot name fulfills the type under the name spelled with its module (`ModA.Store`), and
/// each mention of the type in the declaring module is spelled that way too, since that module's own declaration of the
/// name shadows every module it imports. A `fulfillingAdditionalTypes` claim of a type `viewer` can write, by a declaration
/// it cannot construct, is told apart the same way, and a mention of that type keeps its spelling, since it means the same
/// type everywhere, while a dependency of the declaring module that instantiates it is fulfilled by the distinguished
/// name. Only names `resolveSafeDIFulfilledTypes` would reject are touched, so nothing that resolves today changes.
///
/// SafeDI cannot tell what any other module means by the name: it can read a module SafeDI reads nothing of (a fetched
/// package, a library built without SafeDI, Foundation), and which modules each of its files imports decides. So a
/// declaration of another module that spells the name, in a module that can name a declaration told apart under it
/// (`TypeAccessProof.MentionedDeclarations.meaning(of:mentionedFrom:)`), leaves the name whole, which reports the
/// duplicate error: a rejection has a remedy, and a wrong spelling does not compile. A module that cannot name such a
/// declaration – it is `internal`, or `package` across a package boundary SafeDI knows, or the module declares a type of
/// the name itself or does not read the declaring module – keeps its mention as written, as `viewer` keeps its own. Of a
/// claim of a name `viewer` can write, only another module's dependency that instantiates the name, or its `mockOnly`
/// declaration of it, is such a mention, since a mention of the name means the one type wherever it is written.
///
/// This follows normalization, since a mention of a nested type equals the type it names only once it is qualified. A
/// declaration whose name `viewer` can write is left alone, even beside another of its name, so two that `viewer` can name
/// stay the duplicate error, as does every declaration of a run that knows no module name for `viewer` or the declaration:
/// the Xcode project plugin's. A name stays whole when one of the declarations `viewer` cannot name is a seam or has a
/// public mock, whose signatures are computed and looked up by type in each module's own view, when the spelling with
/// the module is already another type's, or when `viewer` can write a claimed name that another declaration it can name
/// means differently, since a bare mention of what the claim claims would then resolve to that other type.
/// - Parameters:
///   - viewer: The module whose view of the declarations this is: the module generating code, or the module a seam's or
///     public mock's signature is computed for.
///   - normalizedInstantiables: The declarations as `normalizingInstantiableTypes(of:plainTypeDeclarations:reach:)` returned them.
///   - plainTypeDeclarations: The plain type declarations of the modules that declare them, which bound what an extension
///     declares and name what a `fulfillingAdditionalTypes` claim names.
///   - moduleNamesRead: The modules whose declarations the run of `generate` for a named module, other than `viewer`, reads.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func distinguishingTypesUnnameable(
	from viewer: ModuleIdentity,
	among normalizedInstantiables: [Instantiable],
	plainTypeDeclarations: [PlainTypeDeclaration],
	moduleNamesRead: (String) -> Set<String>,
) -> [Instantiable] {
	guard viewer.moduleName != nil else { return normalizedInstantiables }
	var declarationIndicesByType = [TypeDescription: [Int]]()
	for (index, instantiable) in normalizedInstantiables.enumerated() where !instantiable.mockOnly {
		for instantiableType in Set(instantiable.instantiableTypes) {
			declarationIndicesByType[instantiableType, default: []].append(index)
		}
	}
	declarationIndicesByType = declarationIndicesByType.filter { $0.value.count > 1 }
	guard !declarationIndicesByType.isEmpty else { return normalizedInstantiables }

	let moduleReach = TypeAccessProof.ModuleReach(viewer: viewer, instantiables: normalizedInstantiables, plainTypeDeclarations: plainTypeDeclarations, moduleNamesReadByRunOfModule: moduleNamesRead)
	let mentionedDeclarations = TypeAccessProof.MentionedDeclarations(instantiables: normalizedInstantiables, plainTypeDeclarations: plainTypeDeclarations, reach: moduleReach)
	/// What a mention of `type` in the module named `moduleName` means.
	func meaning(of type: TypeDescription, inModuleNamed moduleName: String?) -> TypeAccessProof.MentionMeaning {
		mentionedDeclarations.meaning(of: type, mentionedFrom: .generatedCode(ofModuleNamed: moduleName, isRunsOwnModule: false))
	}
	/// How a mention of `instantiableType` in the module named `moduleName` reaches `declaration`, which fulfills it: whether
	/// the module can write the name and construct the declaration. An extension's own level says nothing of the type it
	/// extends, and a claim's name can be narrower than the type that claims it, so each is capped by the plain declaration
	/// its module records, if it does.
	func reach(of declaration: Instantiable, as instantiableType: TypeDescription, fromModuleNamed moduleName: String?) -> TypeAccessProof.ModuleReach.Reach {
		guard let declaringModuleName = declaration.moduleName else { return .nameable }
		let level = meaning(of: instantiableType, inModuleNamed: declaringModuleName).declarations
			.filter { $0.moduleName == declaringModuleName }
			.reduce(AccessLevel.effective(ofTypeDeclaredBy: declaration)) { $0.capped(by: $1.levelBeforeExtendedTypeCap) }
		return moduleReach.reach(ofDeclarationsIn: declaringModuleName, at: level, from: moduleName)
	}
	func canName(_ instantiableType: TypeDescription, as declaration: Instantiable, fromModuleNamed moduleName: String?) -> Bool {
		reach(of: declaration, as: instantiableType, fromModuleNamed: moduleName) == .nameable
	}
	/// The modules `declaration` means by `instantiableType`, where it is written. Empty when no module SafeDI reads declares
	/// the name, as for a protocol of the standard library.
	func modulesMeant(by instantiableType: TypeDescription, in declaration: Instantiable) -> Set<String> {
		meaning(of: instantiableType, inModuleNamed: declaration.moduleName).moduleNames
	}
	/// The declaration told apart that a mention of `type` in the module named `moduleName`, which declares one of those told
	/// apart, means: its own, or `nil` when the module can name another declaration of the name that means what its own
	/// means (its own run's duplicate error), or the name may mean more than one declaration SafeDI records there.
	func claimMentioned(by type: TypeDescription, fulfilledBy declarationIndices: [Int], distinguishedAs claims: [Int: DistinguishedClaim], inModuleNamed moduleName: String) -> DistinguishedClaim? {
		let meaning = meaning(of: type, inModuleNamed: moduleName)
		let mayMeanDistinguishedDeclaration = claims.keys.contains {
			!modulesMeant(by: type, in: normalizedInstantiables[$0]).isDisjoint(with: meaning.moduleNamesItMayMean)
		}
		guard !mayMeanDistinguishedDeclaration || meaning.isSingleKnownDeclaration else { return nil }
		// The module's own declaration is among the fulfillers.
		let fulfillers = declarationIndices.filter {
			canName(type, as: normalizedInstantiables[$0], fromModuleNamed: moduleName) && modulesMeant(by: type, in: normalizedInstantiables[$0]) == meaning.moduleNames
		}
		guard fulfillers.count == 1 else { return nil }
		return claims[fulfillers[0]]
	}
	/// Whether a mention of `instantiableType` in the module named `moduleName`, which does not declare `declaration`, may
	/// mean `declaration`, which `viewer` cannot name: the module may name the type it declares, or, for a claim, the
	/// mention may mean what the claim claims and the module may construct the claimant.
	func mayName(_ declaration: Instantiable, declaredInModuleNamed declaringModuleName: String, as instantiableType: TypeDescription, fromModuleNamed moduleName: String) -> Bool {
		let meaning = meaning(of: instantiableType, inModuleNamed: moduleName)
		if declaration.concreteInstantiable == instantiableType {
			return meaning.moduleNamesItMayMean.contains(declaringModuleName)
		} else {
			let meant = modulesMeant(by: instantiableType, in: declaration)
			return (meant == meaning.moduleNames || !meant.isDisjoint(with: meaning.moduleNamesItMayMean))
				&& reach(of: declaration, as: instantiableType, fromModuleNamed: moduleName) != .unreachable
		}
	}

	/// The modules other than `viewer` with a declaration that spells each type two or more declarations fulfill, and the
	/// modules with a declaration that instantiates it or provides a mock of it.
	var moduleNamesSpellingType = [TypeDescription: Set<String>]()
	var moduleNamesInstantiatingType = [TypeDescription: Set<String>]()
	for instantiable in normalizedInstantiables {
		guard let moduleName = instantiable.moduleName, moduleName != viewer.moduleName else { continue }
		// A `mockOnly` declaration names the production declaration it provides a mock for.
		let mockedTypes = instantiable.mockOnly ? instantiable.instantiableTypes : []
		for mentionedType in (instantiable.typesMembersSpell + mockedTypes).flatMap(TypeAccessProof.mentionedTypes(in:)) where declarationIndicesByType[mentionedType] != nil {
			moduleNamesSpellingType[mentionedType, default: []].insert(moduleName)
		}
		let instantiatedTypes = instantiable.dependencies.compactMap { dependency -> TypeDescription? in
			switch dependency.source {
			case .instantiated:
				dependency.asInstantiatedType
			case .aliased, .forwarded, .received:
				nil
			}
		}
		for instantiatedType in instantiatedTypes + mockedTypes where declarationIndicesByType[instantiatedType] != nil {
			moduleNamesInstantiatingType[instantiatedType, default: []].insert(moduleName)
		}
	}

	let fulfilledTypes = Set(normalizedInstantiables.flatMap(\.instantiableTypes))
	var distinguishedClaimsByType = [TypeDescription: [Int: DistinguishedClaim]]()
	var mentionsByModuleName = [String: Mentions]()
	for (instantiableType, declarationIndices) in declarationIndicesByType {
		var distinguishedClaims = [Int: DistinguishedClaim]()
		var canBeDistinguished = true
		let meaningToViewer = meaning(of: instantiableType, inModuleNamed: viewer.moduleName)
		for index in declarationIndices where !canName(instantiableType, as: normalizedInstantiables[index], fromModuleNamed: viewer.moduleName) {
			let declaration = normalizedInstantiables[index]
			let meant = modulesMeant(by: instantiableType, in: declaration)
			// A claim names a type `viewer` can write unless SafeDI reads a declaration of it that `viewer` cannot name. A
			// type the declaration itself declares is the one `viewer` cannot name.
			let isClaimOfNameViewerCanWrite = declaration.concreteInstantiable != instantiableType
				&& (meant.isEmpty || !meant.isDisjoint(with: meaningToViewer.moduleNames))
			// Another declaration `viewer` can name, which means a different type by the name, keeps a claimed name whole: a
			// mention elsewhere of what the claim claims, which no module may settle, would resolve to that other declaration.
			let competesWithDifferentType = declaration.concreteInstantiable != instantiableType && declarationIndices.contains {
				canName(instantiableType, as: normalizedInstantiables[$0], fromModuleNamed: viewer.moduleName) && modulesMeant(by: instantiableType, in: normalizedInstantiables[$0]) != meant
			}
			// Every declaration `viewer` cannot name knows its module.
			if !competesWithDifferentType,
			   let moduleName = declaration.moduleName,
			   let distinguishedType = instantiableType.qualified(byModuleNamed: moduleName),
			   !fulfilledTypes.contains(distinguishedType),
			   declaration.concreteInstantiable != instantiableType || (!declaration.generatesDependencyTree && declaration.generateMock != .public)
			{
				distinguishedClaims[index] = DistinguishedClaim(type: distinguishedType, moduleName: moduleName, viewerCanWriteName: isClaimOfNameViewerCanWrite)
			} else {
				canBeDistinguished = false
			}
		}
		guard canBeDistinguished else { continue }
		// What each declaring module that spells the name means by it.
		let moduleNamesSpelling = moduleNamesSpellingType[instantiableType] ?? []
		var mentionedClaimByModuleName = [String: DistinguishedClaim]()
		var isMentionUndetermined = false
		for moduleName in Set(distinguishedClaims.values.map(\.moduleName)) where moduleNamesSpelling.contains(moduleName) {
			if let claim = claimMentioned(by: instantiableType, fulfilledBy: declarationIndices, distinguishedAs: distinguishedClaims, inModuleNamed: moduleName) {
				mentionedClaimByModuleName[moduleName] = claim
			} else {
				isMentionUndetermined = true
			}
		}
		// Another module that may name a declaration told apart keeps the name whole.
		let mayBeMeantByAnotherModule = distinguishedClaims.contains { index, claim in
			let mentioningModuleNames = claim.viewerCanWriteName ? moduleNamesInstantiatingType[instantiableType] ?? [] : moduleNamesSpelling
			return mentioningModuleNames.contains { moduleName in
				moduleName != claim.moduleName && mayName(normalizedInstantiables[index], declaredInModuleNamed: claim.moduleName, as: instantiableType, fromModuleNamed: moduleName)
			}
		}
		if !isMentionUndetermined, !mayBeMeantByAnotherModule {
			distinguishedClaimsByType[instantiableType] = distinguishedClaims
			for (moduleName, claim) in mentionedClaimByModuleName {
				mentionsByModuleName[moduleName, default: Mentions()].record(claim, mentionedAs: instantiableType)
			}
		}
	}
	guard !distinguishedClaimsByType.isEmpty else { return normalizedInstantiables }

	return normalizedInstantiables.enumerated().map { index, instantiable in
		let mentions = instantiable.moduleName.flatMap { mentionsByModuleName[$0] } ?? Mentions()
		// A `mockOnly` declaration names the production declaration it provides a mock for, as any other mention does.
		let ownReplacements: [TypeDescription: TypeDescription] = instantiable.mockOnly
			? mentions.ofEveryName
			: distinguishedClaimsByType.compactMapValues { $0[index]?.type }
		guard !mentions.ofEveryName.isEmpty || !ownReplacements.isEmpty else { return instantiable }
		return instantiable.distinguished(
			asFulfilling: instantiable.instantiableTypes.map { ownReplacements[$0] ?? $0 },
			replacingMentions: mentions.ofTypesViewerCannotName,
			fulfillingInstantiationsOf: mentions.claimsOfNamesViewerCanWrite,
		)
	}
}

/// How the view of `distinguishingTypesUnnameable(from:among:plainTypeDeclarations:moduleNamesRead:)` tells a declaration
/// that the view's module cannot name apart under a name it would otherwise share.
private struct DistinguishedClaim {
	/// The name the declaration fulfills in the view.
	let type: TypeDescription
	/// The module that declares the declaration, whose own mentions of the name mean it.
	let moduleName: String
	/// Whether the type the declaration claims, under the name the view replaces, is a type the view's module can write:
	/// a `public` protocol that a type the module cannot name fulfills. A mention of that name keeps its spelling, since
	/// it means the type the view's module writes; only what instantiates it is fulfilled by `type`.
	let viewerCanWriteName: Bool
}

/// What the members of a declaration of one module mean by the names the view distinguishes.
private struct Mentions {
	/// The distinguished name of each type the view's module cannot name, wherever a member spells it.
	var ofTypesViewerCannotName = [TypeDescription: TypeDescription]()
	/// The distinguished name of the declaration that fulfills each name that view's module can write, read only by a
	/// dependency that instantiates the name.
	var claimsOfNamesViewerCanWrite = [TypeDescription: TypeDescription]()

	/// The distinguished name of the declaration each name means, whichever kind of name it is. The two kinds hold
	/// different names, so neither overrides the other.
	var ofEveryName: [TypeDescription: TypeDescription] {
		ofTypesViewerCannotName.merging(claimsOfNamesViewerCanWrite) { first, _ in first }
	}

	/// Records that a mention of `type` means the declaration `claim` tells apart.
	mutating func record(_ claim: DistinguishedClaim, mentionedAs type: TypeDescription) {
		if claim.viewerCanWriteName {
			claimsOfNamesViewerCanWrite[type] = claim.type
		} else {
			ofTypesViewerCannotName[type] = claim.type
		}
	}
}

/// The `@Instantiable` declaration that fulfills each type, merging a `mockOnly` declaration's mock into the
/// production declaration for the same type. Throws when two production declarations fulfill one type, or
/// when a type has more than one hand-written mock.
func resolveSafeDIFulfilledTypes(instantiables: [Instantiable]) throws -> [TypeDescription: Instantiable] {
	// Errors cite every declaration claiming the type rather than the pair that collided: a merged entry
	// no longer knows which declaration it came from, and the pair would depend on collection order.
	func productionDeclarations(fulfilling instantiableType: TypeDescription) -> [Instantiable] {
		instantiables.filter { !$0.mockOnly && $0.instantiableTypes.contains(instantiableType) }
	}
	func mockProviderDeclarationLocations(fulfilling instantiableType: TypeDescription) -> [Dependency.DeclarationLocation?] {
		instantiables
			.filter { ($0.mockOnly || $0.mockInitializer != nil) && $0.instantiableTypes.contains(instantiableType) }
			.map(\.declarationLocation)
	}
	var typeDescriptionToFulfillingInstantiableMap = [TypeDescription: Instantiable]()
	// Track types that have already had a mockOnly merged in, so a second
	// mockOnly is rejected even after the merged entry appears non-mockOnly.
	var typesWithMockOnlyMerge = Set<TypeDescription>()
	// Every type fulfilled more than once is reported, in source order, so which is reported never depends on the
	// order of the modules and files. A type is no longer resolved once it has an error.
	var errorByInstantiableType = [TypeDescription: CollectInstantiablesError]()
	for instantiable in instantiables {
		for instantiableType in instantiable.instantiableTypes where errorByInstantiableType[instantiableType] == nil {
			if let existing = typeDescriptionToFulfillingInstantiableMap[instantiableType] {
				// Allow one mockOnly and one non-mockOnly for the same type.
				switch (existing.mockOnly, instantiable.mockOnly) {
				case (true, true):
					errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
				case (false, true):
					guard !typesWithMockOnlyMerge.contains(instantiableType) else {
						errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
						continue
					}
					typesWithMockOnlyMerge.insert(instantiableType)
					if existing.concreteInstantiable == instantiable.concreteInstantiable {
						// Same concrete type: two hand-written mocks is ambiguous.
						guard existing.mockInitializer == nil else {
							errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
							continue
						}
						// Only merge if the mockOnly's return type is compatible
						// with this slot. Check against instantiableType (the key)
						// so a mock returning ServiceProtocol merges for the
						// ServiceProtocol slot but not the MyService slot.
						if instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiableType) {
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = existing.mergedWithMockProvider(instantiable)
						}
					} else {
						// Different concrete types: non-mockOnly already holds the
						// slot, so the mockOnly is not registered here.
					}
				case (true, false):
					typesWithMockOnlyMerge.insert(instantiableType)
					if existing.concreteInstantiable == instantiable.concreteInstantiable {
						// Same concrete type: two hand-written mocks is ambiguous.
						guard instantiable.mockInitializer == nil else {
							errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
							continue
						}
						// Only merge if the mockOnly's return type is compatible
						// with this slot.
						if existing.mockReturnTypeIsCompatible(withPropertyType: instantiableType) {
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable.mergedWithMockProvider(existing)
						} else {
							// mockOnly's mock returns incompatible type — replace
							// with production entry (no mock merge).
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
						}
					} else {
						// Different concrete types: non-mockOnly wins the slot.
						typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
					}
				case (false, false):
					errorByInstantiableType[instantiableType] = .duplicate(of: instantiableType, declaredBy: productionDeclarations(fulfilling: instantiableType))
				}
			} else {
				typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
			}
		}
	}
	guard errorByInstantiableType.isEmpty else {
		throw CollectInstantiablesError.independentErrors(Array(errorByInstantiableType.values))
	}

	// Propagate merged mock info to sibling entries: when a mockOnly merged
	// into one key for a concreteInstantiable, other keys for the same
	// concreteInstantiable (from fulfillingAdditionalTypes) may still lack
	// the mock info. Copy it so all entries are consistent.
	// Only propagate when the mock return type is compatible with the
	// target entry's concrete type — a mock returning ServiceProtocol
	// should not spread to the MyService slot.
	var mockProviderByConcreteType = [TypeDescription: Instantiable]()
	for instantiable in typeDescriptionToFulfillingInstantiableMap.values
		where !instantiable.mockOnly && instantiable.mockInitializer != nil
	{
		mockProviderByConcreteType[instantiable.concreteInstantiable] = instantiable
	}
	for (typeDescription, instantiable) in typeDescriptionToFulfillingInstantiableMap {
		if !instantiable.mockOnly,
		   instantiable.mockInitializer == nil,
		   let mockProvider = mockProviderByConcreteType[instantiable.concreteInstantiable],
		   mockProvider.mockReturnTypeIsCompatible(withPropertyType: instantiable.concreteInstantiable)
		{
			typeDescriptionToFulfillingInstantiableMap[typeDescription] = instantiable.mergedWithMockProvider(mockProvider)
		}
	}

	return typeDescriptionToFulfillingInstantiableMap
}

private enum CollectInstantiablesError: SourceLocatedError {
	/// Two or more production declarations fulfill the type. `isEachInsideCompilerDecidedBlock` says whether each is
	/// inside an `#if` block whose condition only the compiler decides, so that the compiler may compile only one. The
	/// flag does not say whether the blocks exclude one another (two files may each guard the type with `#if os(iOS)`),
	/// so the message offers both remedies.
	case foundDuplicateInstantiable(TypeDescription, declaredAt: [Dependency.DeclarationLocation?], isEachInsideCompilerDecidedBlock: Bool)
	/// Each declaration is a type of this name, and at least one is in a module SafeDI does not know, which may or may not
	/// be another's. The message offers renaming, for types that have nothing to do with each other, beside keeping one.
	case foundTypesOfOneNameInUnknownModules(TypeDescription, declaredAt: [Dependency.DeclarationLocation?], isEachInsideCompilerDecidedBlock: Bool)
	/// Each of the two or more modules `moduleNames` lists, in sorted order, declares a type of this name, and those
	/// `repeatingModuleNames` lists, in sorted order, declare it more than once. `isSeamOrPublicMockAmongThem` says whether
	/// one is a seam or has a public mock, which keeps a name whole even when the module cannot name them.
	/// `isEachInsideCompilerDecidedBlock` is as for `foundDuplicateInstantiable`: SafeDI cannot tell one type split by
	/// platform across modules from two types that have nothing to do with each other, so the message offers both remedies.
	case foundTypesOfOneNameInSeveralModules(TypeDescription, moduleNames: [String], repeatingModuleNames: [String], declaredAt: [Dependency.DeclarationLocation?], isSeamOrPublicMockAmongThem: Bool, isEachInsideCompilerDecidedBlock: Bool)
	/// At least one declaration is an extension or a `fulfillingAdditionalTypes` claim of this name, and the declarations are
	/// in the two or more modules `moduleNames` lists, in sorted order, or, when `moduleNames` is `nil`, at least one is in a
	/// module SafeDI does not know. SafeDI reads only `@Instantiable` declarations here, so it cannot tell one type of this
	/// name from a type of the name in each module, and the message offers renaming beside keeping one. Those
	/// `repeatingModuleNames` lists, in sorted order, fulfill it more than once.
	case foundClaimsOfOneName(TypeDescription, moduleNames: [String]?, repeatingModuleNames: [String], declaredAt: [Dependency.DeclarationLocation?], isEachInsideCompilerDecidedBlock: Bool)
	/// One declaration fulfills this type twice: its `fulfillingAdditionalTypes` names its own type, or repeats an entry.
	case foundRepeatedClaim(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])
	case duplicateMockProvider(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])
	/// The errors of different types, each reported as it would be alone, in source order.
	case independentErrors([CollectInstantiablesError])

	/// The error for `declarations`, two or more production declarations that fulfill `type`.
	static func duplicate(of type: TypeDescription, declaredBy declarations: [Instantiable]) -> CollectInstantiablesError {
		let isEachInsideCompilerDecidedBlock = declarations.allSatisfy(\.isInsideCompilerDecidedBlock)
		let declaredAt = declarations.map(\.declarationLocation)
		let moduleNames = declarations.compactMap(\.moduleName)
		// Sorted, so the message does not depend on the order the modules were read in.
		let distinctModuleNames = Set(moduleNames).sorted()
		let isEachInKnownModule = moduleNames.count == declarations.count
		guard declarations.count > 1 else {
			return .foundRepeatedClaim(type, declaredAt: declaredAt)
		}
		// A module's own duplicates are one type, so keeping one is the remedy.
		guard !isEachInKnownModule || distinctModuleNames.count > 1 else {
			return .foundDuplicateInstantiable(type, declaredAt: declaredAt, isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock)
		}
		let repeatingModuleNames = distinctModuleNames.filter { moduleName in
			moduleNames.count(where: { $0 == moduleName }) > 1
		}
		guard declarations.allSatisfy({ !$0.declarationType.isExtension && $0.concreteInstantiable == type }) else {
			return .foundClaimsOfOneName(
				type,
				moduleNames: isEachInKnownModule ? distinctModuleNames : nil,
				repeatingModuleNames: repeatingModuleNames,
				declaredAt: declaredAt,
				isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
			)
		}
		guard isEachInKnownModule else {
			return .foundTypesOfOneNameInUnknownModules(type, declaredAt: declaredAt, isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock)
		}
		return .foundTypesOfOneNameInSeveralModules(
			type,
			moduleNames: distinctModuleNames,
			repeatingModuleNames: repeatingModuleNames,
			declaredAt: declaredAt,
			isSeamOrPublicMockAmongThem: declarations.contains { $0.generatesDependencyTree || $0.generateMock == .public },
			isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
		)
	}

	var sourceDiagnostics: [SourceDiagnostic] {
		switch self {
		case let .foundDuplicateInstantiable(duplicateInstantiable, declaredAt, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: "Found multiple @\(InstantiableVisitor.macroName) types or extensions that fulfill `\(duplicateInstantiable.asSource)`. "
					+ (isEachInsideCompilerDecidedBlock
						? "Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If no build compiles more than one of them, fulfill `\(duplicateInstantiable.asSource)` with one @\(InstantiableVisitor.macroName) declaration outside the `#if`, and put the platform difference \(Self.placeOfPlatformDifference). Otherwise, keep one, and remove `\(duplicateInstantiable.asSource)` from the others’ `fulfillingAdditionalTypes` or remove their @\(InstantiableVisitor.macroName)."
						: "Each type can be fulfilled by only one @\(InstantiableVisitor.macroName) declaration, across all modules. Keep one, and remove `\(duplicateInstantiable.asSource)` from the others’ `fulfillingAdditionalTypes` or remove their @\(InstantiableVisitor.macroName)."),
				declaredAt: declaredAt,
			)
		case let .foundTypesOfOneNameInUnknownModules(type, declaredAt, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: "Found multiple @\(InstantiableVisitor.macroName) types or extensions that fulfill `\(type.asSource)`. "
					+ (isEachInsideCompilerDecidedBlock
						? "Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If they are one type that differs by platform, fulfill `\(type.asSource)` with one @\(InstantiableVisitor.macroName) declaration outside the `#if`, and put the platform difference \(Self.placeOfPlatformDifference). If they are different types, \(Self.renameRemedy(forTypeCount: declaredAt.count)). Otherwise, keep one, and remove the others’ @\(InstantiableVisitor.macroName)."
						: "Each type can be fulfilled by only one @\(InstantiableVisitor.macroName) declaration, across all modules. If they are different types, \(Self.renameRemedy(forTypeCount: declaredAt.count)). If they are one type, keep one, and remove the others’ @\(InstantiableVisitor.macroName)."),
				declaredAt: declaredAt,
			)
		case let .foundTypesOfOneNameInSeveralModules(type, moduleNames, repeatingModuleNames, declaredAt, isSeamOrPublicMockAmongThem, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: Self.severalModulesMessage(
					for: type,
					moduleNames: moduleNames,
					repeatingModuleNames: repeatingModuleNames,
					isSeamOrPublicMockAmongThem: isSeamOrPublicMockAmongThem,
					isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
				),
				declaredAt: declaredAt,
			)
		case let .foundClaimsOfOneName(type, moduleNames, repeatingModuleNames, declaredAt, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: Self.claimsMessage(
					for: type,
					moduleNames: moduleNames,
					repeatingModuleNames: repeatingModuleNames,
					declarationCount: declaredAt.count,
					isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
				),
				declaredAt: declaredAt,
			)
		case let .foundRepeatedClaim(type, declaredAt):
			Self.sourceDiagnostics(
				message: "`fulfillingAdditionalTypes` repeats `\(type.asSource)`, which this @\(InstantiableVisitor.macroName) declaration already fulfills. Remove the repeat.",
				declaredAt: declaredAt,
			)
		case let .duplicateMockProvider(duplicateInstantiable, declaredAt):
			Self.sourceDiagnostics(
				message: "Found multiple hand-written mocks for `\(duplicateInstantiable.asSource)`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.",
				declaredAt: declaredAt,
			)
		case let .independentErrors(errors):
			SourceDiagnostic.joiningInSourceOrder(errors.map(\.sourceDiagnostics))
		}
	}

	private static let nameRule = "SafeDI tells apart by name the @\(InstantiableVisitor.macroName) types a module can name"
	private static let placeOfPlatformDifference = "inside its body or its `\(InstantiableVisitor.instantiateMethodName)(…)` method"

	private static func severalModulesMessage(for type: TypeDescription, moduleNames: [String], repeatingModuleNames: [String], isSeamOrPublicMockAmongThem: Bool, isEachInsideCompilerDecidedBlock: Bool) -> String {
		let declaredIn = "`\(type.asSource)` is declared in modules \(listed(moduleNames))"
			+ (repeatingModuleNames.isEmpty ? ". " : ", and more than once in \(listed(repeatingModuleNames)). ")
		// `distinguishingTypesUnnameable(from:among:plainTypeDeclarations:moduleNamesRead:)` leaves such a name whole.
		let reason = nameRule + (isSeamOrPublicMockAmongThem ? ", and every seam and public mock a run reads" : "")
			+ (isEachInsideCompilerDecidedBlock ? ", and reads every clause of an `#if` that only the compiler decides, such as `#if os(iOS)`. " : ". ")
		// A module's duplicates share a name whichever other module is renamed, so they are resolved first.
		let rename = renameRemedy(forTypeCount: moduleNames.count)
		let remedy = repeatingModuleNames.isEmpty
			? rename
			: "declare it once in \(repeatingModuleNames.count == 1 ? "" : "each of ")\(listed(repeatingModuleNames)), with any platform difference \(placeOfPlatformDifference), then \(rename)"
		return declaredIn + reason + (isEachInsideCompilerDecidedBlock
			? "If they are one type that differs by platform, declare it with one @\(InstantiableVisitor.macroName) declaration, in one of these modules and outside the `#if`, and put the platform difference \(placeOfPlatformDifference). If they are different types, \(remedy)."
			: "\(remedy.prefix(1).uppercased())\(remedy.dropFirst()).")
	}

	private static func claimsMessage(for type: TypeDescription, moduleNames: [String]?, repeatingModuleNames: [String], declarationCount: Int, isEachInsideCompilerDecidedBlock: Bool) -> String {
		let declaredIn = moduleNames.map { moduleNames in
			", in modules \(listed(moduleNames))" + (repeatingModuleNames.isEmpty ? "" : ", and more than once in \(listed(repeatingModuleNames))")
		} ?? ""
		// A module's own repeats fulfill the name whichever other module renames it, so they are resolved first.
		let rename = renameRemedy(forTypeCount: moduleNames?.count ?? declarationCount)
		let remedy = repeatingModuleNames.isEmpty
			? rename
			: "fulfill it once in \(repeatingModuleNames.count == 1 ? "" : "each of ")\(listed(repeatingModuleNames)), with any platform difference \(placeOfPlatformDifference), then \(rename)"
		let keepOne = "keep one, and remove `\(type.asSource)` from the others’ `fulfillingAdditionalTypes` or remove their @\(InstantiableVisitor.macroName)."
		// A declaration in a module SafeDI does not know competes with every other, whichever module the run is for.
		let fulfillmentRule = "Each type can be fulfilled by only one @\(InstantiableVisitor.macroName) declaration" + (moduleNames == nil ? ", across all modules." : " a module can name.")
		return "Found multiple @\(InstantiableVisitor.macroName) types or extensions that fulfill `\(type.asSource)`\(declaredIn). " + (isEachInsideCompilerDecidedBlock
			? "Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If `\(type.asSource)` names one type that differs by platform, fulfill `\(type.asSource)` with one @\(InstantiableVisitor.macroName) declaration outside the `#if`, and put the platform difference \(placeOfPlatformDifference). If it names different types, \(remedy). Otherwise, \(keepOne)"
			: "\(fulfillmentRule) If `\(type.asSource)` names different types, \(remedy). If it names one type, \(keepOne)")
	}

	/// How to tell apart `typeCount` types, two or more, that share a name, as the end of a sentence without its period.
	private static func renameRemedy(forTypeCount typeCount: Int) -> String {
		typeCount == 2 ? "rename one" : "rename all but one"
	}

	/// `moduleNames`, one or more, in the given order, each in backticks: "`A`", "`A` and `B`", or "`A`, `B`, and `C`".
	private static func listed(_ moduleNames: [String]) -> String {
		let spelledNames = moduleNames.map { "`\($0)`" }
		return if spelledNames.count <= 2 {
			spelledNames.joined(separator: " and ")
		} else {
			"\(spelledNames.dropLast().joined(separator: ", ")), and \(spelledNames[spelledNames.count - 1])"
		}
	}

	/// An error at each of `declarationLocations`, in source order, so the output does not depend on collection order.
	private static func sourceDiagnostics(message: String, declaredAt declarationLocations: [Dependency.DeclarationLocation?]) -> [SourceDiagnostic] {
		declarationLocations
			.map { declarationLocation in
				SourceDiagnostic(
					severity: .error,
					location: declarationLocation,
					message: message,
				)
			}
			.sorted(by: SourceDiagnostic.precedesInSourceOrder)
	}
}
