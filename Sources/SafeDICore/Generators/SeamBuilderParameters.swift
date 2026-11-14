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

// MARK: - Builder parameters

/// How a seam's generated initializer takes a builder for each place its tree builds a type no production
/// `@Instantiable` declaration the seam's module can see fulfills – a hole – and how the module that calls the seam
/// fills it. Kept apart from the rest of the seam computation, which a seam without holes runs exactly as before.
extension DependencyTreeGenerator {
	/// The holes of `seam`'s signature, read from `generator`, the generator of its tree, whose parameters are
	/// `parameters`: one per site of a hole in the tree (a hole's generator), and one per hole of a seam the tree calls
	/// that the module computing the signature cannot fill, which the seam passes up, shared by every call of that
	/// seam or public mock. In builder-label order. `shapedBuilders` settles the builders a seam or a public mock takes for
	/// them and their names.
	///
	/// A site's fields are the values whose nearest declaration on the site's path is bound before the site in the
	/// code the seam's module generates: the seam's parameters, then each scope's on the path, outermost first, each
	/// in the order it binds them – its forwarded properties, then its children in generation order, an `onlyIfAvailable`
	/// alias bound to `nil` among them. A declaration bound after the site and the property still being built carry no
	/// field, and hide the farther declarations of their label, which Swift would bind instead.
	static func holes(
		of seam: Instantiable,
		generator: ScopeGenerator,
		parameters: [SeamSignature.Parameter],
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
	) -> [SeamSignature.Hole] {
		guard generator.containsBuildSite || generator.passesUpBuilder else { return [] }
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		let sites = buildSites(in: generator)
		let seamModule = ModuleIdentity(moduleName: seam.moduleName, packageName: seam.packageName)
		let (passedUpHoles, ownSiteAdditions) = holesPassedUp(in: generator, seamType: seam.concreteInstantiable, seamModule: seamModule, ownSitePaths: sites.map(\.sitePath))

		// Every site's fields and what it does not carry.
		struct SiteContent {
			let site: BuildSite
			let owner: Instantiable
			let dependency: Dependency?
			let fields: [SeamSignature.Hole.Field]
			let uncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration]
			let cycleReentryDeclarations: [SeamSignature.Hole.CycleReentryDeclaration]
			let levels: [SeamPlaceLevels.Level]
			/// The fields and uncarried declarations of the site's path as its levels decide them, a `@Sendable` function on the
			/// path aside.
			let pathFields: [Property]
			let pathUncarriedProperties: [Property]
		}
		var declarationsBetweenByClosedOnScope = [ObjectIdentifier: [DeclarationBetween]]()
		let siteContents = sites.compactMap { site -> SiteContent? in
			guard let owner = site.frames.last?.generator.builtInstantiable else { return nil }
			let content = fields(
				of: site,
				seam: seam,
				parameters: parameters,
				seamTypeAccess: seamTypeAccess,
				proof: proof,
				instantiables: instantiables,
				declarationsBetweenByClosedOnScope: &declarationsBetweenByClosedOnScope,
			)
			return SiteContent(
				site: site,
				owner: owner,
				dependency: owner.dependencies.first { $0.property == site.property },
				fields: content.fields,
				uncarriedDeclarations: content.uncarriedDeclarations,
				cycleReentryDeclarations: content.cycleReentryDeclarations,
				levels: content.levels,
				pathFields: content.pathFields,
				pathUncarriedProperties: content.pathUncarriedProperties,
			)
		}
		// The levels of each place, beside its fields, for the tests and the graph fuzzer: generated code reads none yet.
		if let observer = SeamPlaceLevels.observer {
			observer(SeamPlaceLevels(
				seamType: seam.concreteInstantiable,
				places: siteContents.map { content in
					SeamPlaceLevels.Place(
						sitePath: content.site.sitePath,
						levels: content.levels,
						fields: content.pathFields,
						uncarriedProperties: content.pathUncarriedProperties,
					)
				},
			))
		}

		// Names. A builder is labeled `<label>Builder`; holes whose labels collide with one another or with a parameter
		// are named apart by their owner, their declared type simplified, their declared type, and their site path, a
		// parameter keeping its label. A scope struct is named after the owner and the property, with the site path
		// appended for a property built at several sites, and an underscore appended while it equals an earlier one.
		struct Candidate {
			let label: String
			let suffixTypes: [TypeDescription]
		}
		let candidates = siteContents.map { content in
			Candidate(
				label: "\(content.site.property.label)Builder".spelledAsJoinedIdentifier,
				suffixTypes: [
					content.owner.concreteInstantiable,
					content.site.property.typeDescription.simplified,
					content.site.property.typeDescription,
					.simple(name: content.site.pathLabels, generics: []),
				],
			)
		} + passedUpHoles.map { passedUp in
			Candidate(
				label: passedUp.hole.builderLabel,
				suffixTypes: [
					passedUp.hole.ownerType,
					passedUp.hole.property.typeDescription.simplified,
					passedUp.hole.property.typeDescription,
					.simple(name: SeamSignature.Hole.pathLabels(of: passedUp.hole.sitePath), generics: []),
				],
			)
		}
		let parameterLabels = Set(parameters.map(\.property.label))
		var candidateIndicesByLabel = [String: [Int]]()
		for (index, candidate) in candidates.enumerated() {
			candidateIndicesByLabel[candidate.label, default: []].append(index)
		}
		var builderLabels = candidates.map(\.label)
		let collidingIndices = candidates.indices.filter { index in
			parameterLabels.contains(candidates[index].label) || candidateIndicesByLabel[candidates[index].label, default: []].count > 1
		}
		let keptLabels = Set(candidates.indices.filter { !collidingIndices.contains($0) }.map { candidates[$0].label })
		let collidingNames = ScopeGenerator.identifierSafeNames(
			for: collidingIndices.map { (label: candidates[$0].label, suffixTypes: candidates[$0].suffixTypes) },
			reservedNames: parameterLabels.union(keptLabels),
		)
		for (index, name) in zip(collidingIndices, collidingNames) {
			builderLabels[index] = name
		}
		// A builder's name inside the initializer is renamed while a property of the tree would have a builder function of that
		// name, which would shadow it. Nor may it equal a deferred parameter's name, which the parameters take first, or a name
		// another builder binds.
		let builderFunctionNames = builderFunctionNamesOfProperties(in: generator).union(parameters.filter(\.isDeferred).map(\.internalName))
		let unrenamedBuilderNames = builderLabels.map(ScopeGenerator.functionName(toBuildPropertyNamed:))
		var namesBoundByEarlierBuilders = Set<String>()
		func internalName(ofBuilderLabeled builderLabel: String) -> String {
			let unrenamedName = ScopeGenerator.functionName(toBuildPropertyNamed: builderLabel)
			let reservedNames = builderFunctionNames.union(namesBoundByEarlierBuilders).union(unrenamedBuilderNames.filter { $0 != unrenamedName })
			var name = unrenamedName
			while reservedNames.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			namesBoundByEarlierBuilders.insert(name)
			return name
		}
		var siteCountByProperty = [OwnedProperty: Int]()
		for content in siteContents {
			siteCountByProperty[OwnedProperty(owner: content.owner.concreteInstantiable, property: content.site.property), default: 0] += 1
		}
		var scopeTypeNames = Set<String>()
		var holes = [SeamSignature.Hole]()
		for (index, content) in siteContents.enumerated() {
			let property = content.site.property
			var scopeTypeName = "SafeDIScope_\(content.owner.concreteInstantiable.asIdentifier)_\(property.label)".spelledAsJoinedIdentifier
			if siteCountByProperty[OwnedProperty(owner: content.owner.concreteInstantiable, property: property), default: 0] > 1 {
				scopeTypeName = "\(scopeTypeName)_\(content.site.pathLabels)".spelledAsJoinedIdentifier
			}
			while !scopeTypeNames.insert(scopeTypeName).inserted {
				scopeTypeName = "\(scopeTypeName)_".spelledAsJoinedIdentifier
			}
			// The struct is declared in this seam's extension, at its type's access, which caps the tier anyway; the hole's
			// owner receives the property, so its module's declarations prove the property's type too.
			let builderAccess = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, content.owner.moduleName]))
			let siteHole = SeamSignature.Hole(
				ownerType: content.owner.concreteInstantiable,
				// A seam in another module than the hole's owner respells the owner's types in its builder, where a bare name
				// may mean a type of its own module that a `.safedi` does not record.
				declaringModuleNames: seam.moduleName == content.owner.moduleName ? [seam.moduleName].compactMap(\.self) : [],
				property: property,
				instantiatedType: content.dependency?.asInstantiatedType ?? property.typeDescription.asInstantiatedType,
				declarationLocation: content.dependency?.declarationLocation,
				erasedToConcreteExistential: content.site.erasedToConcreteExistential,
				sitePath: content.site.sitePath,
				declaredSitePath: content.site.declaredSitePath,
				fillPropertyStack: content.site.fillPropertyStack,
				fillConcreteTypeStack: content.site.fillConcreteTypeStack,
				builderLabel: builderLabels[index],
				internalName: internalName(ofBuilderLabeled: builderLabels[index]),
				scopeSeamType: seam.concreteInstantiable,
				scopeSeamModule: seamModule,
				typesToOwner: content.site.typesToOwner,
				scopeTypeName: scopeTypeName,
				fields: content.fields,
				// No tier is wider than the seam's type.
				tierAccess: min(builderAccess.level, seamTypeAccess),
				accessCause: builderAccess.cause,
				uncarriedDeclarations: content.uncarriedDeclarations,
				cycleReentryDeclarations: content.cycleReentryDeclarations,
			)
			// A call the tree makes of this seam, or of a seam that passes this site back, is handed this builder.
			let additions = ownSiteAdditions[content.site.sitePath, default: SiteAdditions()]
			holes.append(siteHole.addingUncarriedDeclarations(additions.declarations(besides: siteHole.uncarriedDeclarations), isSendable: additions.isSendable))
		}
		for (offset, passedUp) in passedUpHoles.enumerated() {
			let builderLabel = builderLabels[siteContents.count + offset]
			let inner = passedUp.hole
			// The builder's type names the inner seam's scope struct, as visible as that seam's type, and the property's
			// type, which this seam's declarations prove again, its owner's module among those admitted.
			let builderAccess = proof.access(
				ofParameterTyped: .closure(arguments: [inner.scopeSeamType], isAsync: false, doesThrow: false, returnType: inner.property.typeDescription),
				mentionedFrom: .declaration(seam),
				admittedModules: Set([seam.moduleName, instantiables[inner.ownerType]?.moduleName]),
			)
			holes.append(SeamSignature.Hole(
				ownerType: inner.ownerType,
				// The module that fills the place spells its type, as it does where a seam in another module than the owner holds it.
				declaringModuleNames: [],
				property: inner.property,
				instantiatedType: inner.instantiatedType,
				declarationLocation: inner.declarationLocation,
				erasedToConcreteExistential: inner.erasedToConcreteExistential,
				sitePath: inner.sitePath,
				declaredSitePath: inner.declaredSitePath,
				fillPropertyStack: inner.fillPropertyStack,
				fillConcreteTypeStack: inner.fillConcreteTypeStack,
				builderLabel: builderLabel,
				internalName: internalName(ofBuilderLabeled: builderLabel),
				scopeSeamType: inner.scopeSeamType,
				scopeSeamModule: inner.scopeSeamModule,
				typesToOwner: passedUp.typesToCall + inner.typesToOwner,
				scopeTypeName: inner.scopeTypeName,
				fields: inner.fields,
				tierAccess: min(builderAccess.level, seamTypeAccess),
				accessCause: builderAccess.cause,
				uncarriedDeclarations: inner.uncarriedDeclarations,
				cycleReentryDeclarations: inner.cycleReentryDeclarations,
				innerSeamType: passedUp.innerSeamType,
				passedUpRoute: passedUp.route + inner.passedUpRoute,
				isSendable: inner.isSendable,
				enumPlace: inner.enumPlace,
			))
		}
		return holes.sorted { $0.builderLabel < $1.builderLabel }
	}

	/// The type that fulfills `hole` in `instantiables`, the declarations a module calling the seam sees, or `nil`
	/// when none does: no declaration, or only a `mockOnly` one, which is used only to generate mocks.
	static func fulfillingInstantiable(of hole: SeamSignature.Hole, in instantiables: [TypeDescription: Instantiable]) -> Instantiable? {
		instantiables[hole.instantiatedType].flatMap { $0.mockOnly ? nil : $0 }
	}

	/// Whether `dependency`, an `@Instantiated` one, is a hole in a seam's tree when no production declaration fulfills
	/// its type: any type a nominal type could be. A function type, a tuple, an array, a dictionary, a metatype, or
	/// `Void` is not, since only hand-written code could build one: it stays `noInstantiableFound`.
	static func canBeHole(_ dependency: Dependency) -> Bool {
		switch dependency.asInstantiatedType {
		case .simple, .nested, .any, .composition:
			true
		case .void, .optional, .implicitlyUnwrappedOptional, .some, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .unknown, .variadic:
			false
		}
	}

	// MARK: Private

	/// A property its owner declares, by which a scope struct is named.
	private struct OwnedProperty: Hashable {
		let owner: TypeDescription
		let property: Property
	}

	/// A scope on the path from a seam's root to a build site, with its children in the order its code is generated
	/// and the position among them of the next scope on the path, or of the site, and, for a fill, whether its function is
	/// `@Sendable`.
	private struct PathFrame {
		let generator: ScopeGenerator
		let orderedChildren: [ScopeGenerator.OrderedChild]
		var nextPosition: Int
		var fillIsSendable = false
	}

	/// A build site of a hole: the generator that builds the hole's property, reached through `frames`.
	private struct BuildSite {
		/// The scopes from the seam's root to the hole's owner, each with the position of the next on the path.
		let frames: [PathFrame]
		let property: Property
		let erasedToConcreteExistential: Bool
		/// The properties from the root of the seam whose tree holds the site to the owner's property, innermost first,
		/// each lazily instantiated one preceded by its instance, as `Scope.createScopeGenerator` stacks them: the stack
		/// the owner's scope was built with, which inside a fill this seam generates is the filled seam's.
		let fillPropertyStack: [Property]
		/// The concrete type each entry of `fillPropertyStack` is built for, beside it.
		let fillConcreteTypeStack: [TypeDescription]

		/// The properties from the root to the hole's property: the site's identity in the tree.
		var sitePath: [Property] {
			frames.dropFirst().flatMap { frame in
				frame.generator.fillHole?.pathBeforePropertyInItsFill ?? frame.generator.property.map { [$0] } ?? []
			} + [property]
		}

		/// The properties the code declares from the root to the hole's property, which a diagnostic prints.
		var declaredSitePath: [SeamSignature.Hole.DeclaredProperty] {
			var path = [SeamSignature.Hole.DeclaredProperty]()
			var declaringGenerator = frames.first?.generator
			for frame in frames.dropFirst() {
				path += declaredProperties(reaching: frame.generator, from: declaringGenerator)
				declaringGenerator = frame.generator
			}
			path.append(declaredProperty(property, declaredBy: declaringGenerator))
			return path
		}

		/// The types from the seam, itself excluded, to the hole's owner.
		var typesToOwner: [SeamSignature.Hole.PathType] {
			frames.dropFirst().flatMap { SeamSignature.Hole.PathType.pathTypes(through: $0.generator) }
		}

		/// The labels of the properties from the root to the owner's property, joined with `_`.
		var pathLabels: String {
			SeamSignature.Hole.pathLabels(of: sitePath)
		}
	}

	/// `property` with the type that declares it and where: the type `generator` builds, or, for a fill, the owner of the
	/// hole it fills, since the only property a fill builds is that hole's.
	private static func declaredProperty(_ property: Property, declaredBy generator: ScopeGenerator?) -> SeamSignature.Hole.DeclaredProperty {
		if let filledHole = generator?.fillHole {
			SeamSignature.Hole.DeclaredProperty(property: property, declaringType: filledHole.ownerType, declarationLocation: filledHole.declarationLocation)
		} else {
			SeamSignature.Hole.DeclaredProperty(
				property: property,
				declaringType: generator?.builtInstantiable?.concreteInstantiable,
				declarationLocation: generator?.builtInstantiable?.dependencies.first { $0.property == property }?.declarationLocation,
			)
		}
	}

	/// The properties the code declares on the way from `parent` to its child `generator`: the property the child
	/// builds, or, for a fill, the way to the hole it fills.
	private static func declaredProperties(reaching generator: ScopeGenerator, from parent: ScopeGenerator?) -> [SeamSignature.Hole.DeclaredProperty] {
		generator.fillHole?.declaredPathBeforePropertyInItsFill ?? generator.property.map { [declaredProperty($0, declaredBy: parent)] } ?? []
	}

	/// The build sites in the tree `generator` roots, in the order the generated code builds them, found by walking
	/// only the subtrees that hold one.
	private static func buildSites(in generator: ScopeGenerator) -> [BuildSite] {
		var sites = [BuildSite]()
		var frames = [PathFrame(generator: generator, orderedChildren: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []), nextPosition: 0)]
		while let frame = frames.last {
			guard frame.nextPosition < frame.orderedChildren.count else {
				frames.removeLast()
				continue
			}
			frames[frames.count - 1].nextPosition += 1
			let child = frame.orderedChildren[frame.nextPosition]
			if let holeSite = child.generator.holeSite {
				sites.append(BuildSite(frames: frames, property: holeSite.property, erasedToConcreteExistential: holeSite.erasedToConcreteExistential, fillPropertyStack: child.generator.ownerPropertyStack, fillConcreteTypeStack: child.generator.ownerConcreteTypeStack))
			} else if child.generator.containsBuildSite, child.generator.fillEmitsCode {
				// A fill whose code another fill of its case generates builds no site of its own.
				frames.append(PathFrame(
					generator: child.generator,
					orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
					nextPosition: 0,
					fillIsSendable: frame.generator.buildsInSendableFunction(ofFill: child.generator),
				))
			}
		}
		return sites
	}

	/// The holes of the seams the tree `generator` roots calls whose builders it passes up, one per site whatever route
	/// presents it, each with the seam whose call presented it first, in the order the tree first presents the site, and
	/// what the calls that present each site of the seam's own tree add to its builder. A site is never passed up twice,
	/// nor is a site of the seam's own tree, which a call of the seam itself or of a seam that passes the site back
	/// presents: the seam hands that call the builder it takes. A builder the seam takes for a site holds, beside its own
	/// uncarried declarations, the declarations the tree binds on every path to a call that presents the site and the
	/// uncarried declarations each presented copy holds, the first of each label: inline, a fill's receive of one of
	/// their labels would read it, and the caller that fills the builder does not hold it. It is `@Sendable` when a call
	/// that presents its site is made in a `@Sendable` function, a fill's included, which captures it, or takes it
	/// `@Sendable`, since the seam passes it to that call. Each passed-up hole comes with the properties from the seam's
	/// root to the call that presented it first.
	private static func holesPassedUp(
		in generator: ScopeGenerator,
		seamType: TypeDescription,
		seamModule: ModuleIdentity,
		ownSitePaths: [[Property]],
	) -> (passedUpHoles: [(innerSeamType: TypeDescription, typesToCall: [SeamSignature.Hole.PathType], route: [SeamSignature.Hole.DeclaredProperty], hole: SeamSignature.Hole)], ownSiteAdditions: [[Property]: SiteAdditions]) {
		var passedUpHoles = [(innerSeamType: TypeDescription, typesToCall: [SeamSignature.Hole.PathType], route: [SeamSignature.Hole.DeclaredProperty], hole: SeamSignature.Hole)]()
		var takenSites = Set(ownSitePaths.map { SeamSignature.Hole.Site(seamType: seamType, path: $0) })
		var additionsBySite = [SeamSignature.Hole.Site: SiteAdditions]()
		var generatorsToVisit = [(generator: generator, typesToCall: [SeamSignature.Hole.PathType](), route: [SeamSignature.Hole.DeclaredProperty](), pathDeclarations: [SeamSignature.Hole.UncarriedDeclaration](), isInSendableFunction: false)]
		while let (visited, typesToCall, route, pathDeclarations, isInSendableFunction) = generatorsToVisit.popLast() {
			// The call is made in its scope's builder function, inside every function above it.
			let callIsInSendableFunction = isInSendableFunction || visited.buildsInSendableFunction
			if let innerSeamType = visited.builtInstantiable?.concreteInstantiable {
				for hole in visited.passedUpHoles {
					if takenSites.insert(hole.site).inserted {
						passedUpHoles.append((innerSeamType, typesToCall, route, hole))
					}
					// The call captures the builder when it is made in a `@Sendable` builder function, and takes it `@Sendable`
					// when the presented copy is.
					let presentedPlace = SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole)
					additionsBySite[hole.site, default: SiteAdditions()].add(
						pathDeclarations.map { $0.with(reason: .boundByPassingUpSeam(seam: seamType, module: seamModule, place: presentedPlace)) } + hole.uncarriedDeclarations,
						isSendable: callIsInSendableFunction || hole.isSendable,
					)
				}
			}
			// The seam's own forwarded properties come from its caller, which fills the builder. Each declaration's reason names
			// the place a call presents, where the call is reached.
			let childPathDeclarations = pathDeclarations + declarationsBound(by: visited, includingForwardedProperties: visited !== generator, reason: .other)
			// A fill whose code another fill of its case generates makes no call of its own.
			let children = visited.children.filter { $0.passesUpBuilder && $0.fillEmitsCode }
			generatorsToVisit.append(contentsOf: children.reversed().map { ($0, typesToCall + SeamSignature.Hole.PathType.pathTypes(through: $0), route + declaredProperties(reaching: $0, from: visited), childPathDeclarations, callIsInSendableFunction || visited.buildsInSendableFunction(ofFill: $0)) })
		}
		var ownSiteAdditions = [[Property]: SiteAdditions]()
		for path in ownSitePaths {
			ownSiteAdditions[path] = additionsBySite[SeamSignature.Hole.Site(seamType: seamType, path: path)]
		}
		return (
			passedUpHoles.map { innerSeamType, typesToCall, route, hole in
				let additions = additionsBySite[hole.site, default: SiteAdditions()]
				return (innerSeamType, typesToCall, route, hole.addingUncarriedDeclarations(additions.declarations(besides: hole.uncarriedDeclarations), isSendable: additions.isSendable))
			},
			ownSiteAdditions,
		)
	}

	/// What the calls a seam's tree makes that present one site add to the builder the seam takes for it.
	private struct SiteAdditions {
		/// The declarations a fill of the site cannot read, the first of each label, in the order the calls present them.
		private var declarations = [SeamSignature.Hole.UncarriedDeclaration]()
		/// Whether a call that presents the site is made in a `@Sendable` function, a fill's included, or takes the builder
		/// `@Sendable`.
		private(set) var isSendable = false

		/// Adds `newDeclarations`, those of labels not yet added, from a call that needs the builder `@Sendable` when
		/// `isSendable`.
		mutating func add(_ newDeclarations: [SeamSignature.Hole.UncarriedDeclaration], isSendable: Bool) {
			for declaration in newDeclarations where !declarations.contains(where: { $0.property.label == declaration.property.label }) {
				declarations.append(declaration)
			}
			self.isSendable = self.isSendable || isSendable
		}

		/// The declarations added of labels none of `existing` has.
		func declarations(besides existing: [SeamSignature.Hole.UncarriedDeclaration]) -> [SeamSignature.Hole.UncarriedDeclaration] {
			let existingLabels = Set(existing.map(\.property.label))
			return declarations.filter { !existingLabels.contains($0.property.label) }
		}
	}

	/// The declarations the scope of `generator` binds for the scopes beneath it, each with `reason`: its children and
	/// aliases, its forwarded properties when `includingForwardedProperties`, the parameters of its builder function when
	/// a lazy cycle closes on it (`CycleParameter`), and, for a fill, every field of the filled
	/// seam's struct the fill binds (`ScopeGenerator.fillBoundFields`) and what that seam's path declares beside them,
	/// which together are what the filled seam's tree binds or is building where the fill is called. A field bound from
	/// a deferred parameter that the fill reads from the caller's scope is the caller's declaration, bound above.
	private static func declarationsBound(
		by generator: ScopeGenerator,
		includingForwardedProperties: Bool,
		reason: SeamSignature.Hole.UncarriedDeclaration.Reason,
	) -> [SeamSignature.Hole.UncarriedDeclaration] {
		var declarations = [SeamSignature.Hole.UncarriedDeclaration]()
		if let filledHole = generator.fillHole {
			// A fill binds the fields it reads from its struct; one bound from a deferred parameter it reads from the
			// caller's scope declares nothing.
			for declaration in filledHole.uncarriedDeclarations.map({ ($0.property, $0.declaringType, $0.declarationLocation, $0.parameterTakingType) })
				+ generator.fillBoundFields.map({ ($0.property, $0.declaringType, $0.declarationLocation, $0.parameterTakingType) })
			{
				declarations.append(SeamSignature.Hole.UncarriedDeclaration(
					property: declaration.0,
					declaringType: declaration.1,
					declarationLocation: declaration.2,
					parameterTakingType: declaration.3,
					builtAfter: nil,
					reason: reason,
				))
			}
		}
		if let instantiable = generator.builtInstantiable {
			for dependency in instantiable.dependencies {
				switch dependency.source {
				case .instantiated, .aliased:
					break
				case .forwarded:
					guard includingForwardedProperties else { continue }
				case .received:
					continue
				}
				declarations.append(SeamSignature.Hole.UncarriedDeclaration(
					property: dependency.property,
					declaringType: instantiable.concreteInstantiable,
					declarationLocation: dependency.declarationLocation,
					builtAfter: nil,
					reason: reason,
				))
			}
			// The parameters of the builder function a lazy cycle closes on bind their labels for every scope in its body, as
			// `fields(of:)` counts them, each declared, as far as a fill's reader is told, by the first type in the function's
			// body that receives it.
			if generator.declaresCycleParameters {
				// A receiver's chain ends at the receiving type.
				let parametersWithReceivingType = generator.cycleParameters.compactMap { parameter in
					parameter.receiver.chain.last.map { (parameter: parameter, receivingType: $0) }
				}
				for (parameter, receivingType) in parametersWithReceivingType {
					declarations.append(SeamSignature.Hole.UncarriedDeclaration(
						property: parameter.property,
						declaringType: receivingType,
						declarationLocation: parameter.receiver.declarationLocation,
						parameterTakingType: instantiable.concreteInstantiable,
						builtAfter: nil,
						reason: reason,
					))
				}
			}
		}
		return declarations
	}

	/// The names of the builder functions the properties of the tree `generator` roots would have, which a builder's
	/// name inside the generated initializer must not equal.
	static func builderFunctionNamesOfProperties(in generator: ScopeGenerator, includingHoleSites: Bool = true) -> Set<String> {
		var names = Set<String>()
		var generatorsToVisit = [generator]
		while let visited = generatorsToVisit.popLast() {
			if let property = visited.property, includingHoleSites || visited.holeSite == nil {
				names.insert(ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
			}
			generatorsToVisit.append(contentsOf: visited.children)
		}
		return names
	}

	/// A declaration on a site's path: the value it binds and whether it is bound before the site.
	private struct PathDeclaration {
		let property: Property
		let isBoundBeforeSite: Bool
		/// How many `@Sendable` functions on the path enclose it.
		let sendableDepth: Int
		let access: AccessLevel
		let accessCause: TypeAccessProof.Cause?
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		var isReceivedOnlyIfAvailable = false
		var parameterTakingType: TypeDescription?
		var deferral = SeamSignature.Parameter.Deferral.none
		var builtAfter: Property?
		var reason = SeamSignature.Hole.UncarriedDeclaration.Reason.other
		/// The position on the site's path of the scope that declares it, or whose builder function takes it as a parameter, or
		/// `-1` for a parameter of the seam.
		var frameLevel = -1
		/// Whether it is a parameter of the builder function of the scope at `frameLevel` that a lazy cycle closes on.
		var isCycleParameter = false
		/// Whether its type forwards it.
		var isForwarded = false
		/// Where it is a parameter of a builder function a lazy cycle closes on: whose, and what the cycle passes it.
		var cycleParameterOrigin: SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin?
		/// Where its type, the seam or a type in its tree, receives it under an alias: what fulfills it.
		var alias: SeamSignature.Hole.UncarriedDeclaration.AliasOrigin?
	}

	/// The fields of `site`'s place, the declarations on its path that carry no field, the declarations a cycle hands the
	/// site's owner when it builds it again, the levels of its path, and the fields and uncarried declarations the levels
	/// decide, a `@Sendable` function on the path aside. A place built inside a `@Sendable` function – a builder function, a
	/// fill's function, or the `Sendable` wrapper it is held in – is handed only what the innermost such function binds: a
	/// declaration bound outside it is uncarried (`boundOutsideSendableFunction`), and the seam's parameters are no field,
	/// since a fill reads them from the caller's own scope.
	/// - Parameters:
	///   - declarationsBetweenByClosedOnScope: The `declarationsBetween(closedOnScope:)` of each scope already asked, by the
	///     scope's identity.
	private static func fields(
		of site: BuildSite,
		seam: Instantiable,
		parameters: [SeamSignature.Parameter],
		seamTypeAccess: AccessLevel,
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
		declarationsBetweenByClosedOnScope: inout [ObjectIdentifier: [DeclarationBetween]],
	) -> (fields: [SeamSignature.Hole.Field], uncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration], cycleReentryDeclarations: [SeamSignature.Hole.CycleReentryDeclaration], levels: [SeamPlaceLevels.Level], pathFields: [Property], pathUncarriedProperties: [Property]) {
		// A field is as visible as the narrowest type it names, which the declarations of the seam's module and of the
		// module of the type that declares the value prove, capped at the seam's type.
		func access(of property: Property, declaredBy declaringModuleName: String?) -> (level: AccessLevel, cause: TypeAccessProof.Cause?) {
			let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, declaringModuleName]))
			return (min(access.level, seamTypeAccess), access.cause)
		}
		// The nearest declaration of each label, and the order in which the labels are bound.
		var nearestDeclarations = [String: PathDeclaration]()
		var labelsInBindingOrder = [String]()
		// Beside them, what each scope on the path declares, the level it holds, outermost first: the seam's root's starts
		// with the parameters.
		var levels = [SeamPlaceLevels.Level]()
		var levelDeclarations = [SeamPlaceLevels.Level.Declaration]()
		func declare(_ declaration: PathDeclaration) {
			let label = declaration.property.label
			if nearestDeclarations.updateValue(declaration, forKey: label) != nil {
				labelsInBindingOrder.removeAll { $0 == label }
			}
			labelsInBindingOrder.append(label)
			var levelDeclaration = SeamPlaceLevels.Level.Declaration(property: declaration.property, isBoundBeforeNextProperty: declaration.isBoundBeforeSite)
			levelDeclaration.isCycleParameter = declaration.isCycleParameter
			levelDeclarations.append(levelDeclaration)
		}
		var isInFill = false
		func endLevel(builtType: TypeDescription?, nextProperty: Property?) {
			levels.append(SeamPlaceLevels.Level(builtType: builtType, nextProperty: nextProperty, isInFill: isInFill, declarations: levelDeclarations))
			levelDeclarations = []
		}
		for parameter in parameters {
			// A pass-through is declared, as far as a fill's reader is told, by the first type in the tree that receives it.
			let firstReceiver = parameter.receivers.first
			var parameterDeclaration = PathDeclaration(
				property: parameter.property,
				isBoundBeforeSite: true,
				sendableDepth: 0,
				access: parameter.tierAccess,
				accessCause: parameter.accessCause,
				declaringType: firstReceiver?.declaringType ?? seam.concreteInstantiable,
				declarationLocation: firstReceiver?.declarationLocation ?? seam.dependencies.first { $0.property == parameter.property }?.declarationLocation ?? seam.declarationLocation,
				isReceivedOnlyIfAvailable: parameter.isOnlyIfAvailable,
			)
			parameterDeclaration.deferral = parameter.deferral
			declare(parameterDeclaration)
		}
		var sendableDepth = 0
		// The property each `@Sendable` function on the path builds, outermost first, with the type it builds: `nil` for a
		// `Sendable` wrapper the place is held in.
		var sendableFunctions = [(property: Property, builtType: TypeDescription?)]()
		// The scopes on the path below the root whose builder function a cycle-closing scope in their tree calls, each with
		// its level on the path and the type that declares its property.
		var scopesACycleClosesOn = [(level: Int, generator: ScopeGenerator, declaration: ScopeGenerator.BuiltDeclaration, declaringType: TypeDescription)]()
		// The type that declares the properties of the previous frame's children: the next frame's declaring type.
		var childDeclaringType = seam.concreteInstantiable
		// The type whose scope declares the children of the frame being visited: the one the frame before built.
		var loopDeclaringInstantiable = seam
		for (level, frame) in site.frames.enumerated() {
			if level > 0, let declaration = frame.generator.declarationACycleClosesOn {
				scopesACycleClosesOn.append((level, frame.generator, declaration, childDeclaringType))
			}
			// A fill the seam generates for a seam it calls binds every field of that seam's struct a site inside it carries,
			// which is every field it binds (`ScopeGenerator.fillBoundFields`): what the struct carries is what inline holds
			// there. A field bound from a deferred parameter the fill reads from this seam's tree instead, where the call
			// passed it, so the nearest declaration of its label is the one above the call. A declaration the struct does
			// not carry is on the called seam's path too, bound after its site or still being built, and hides the farther
			// declarations of its label.
			if let filledHole = frame.generator.fillHole {
				// The only property a fill builds is its hole's.
				childDeclaringType = filledHole.ownerType
				isInFill = true
				for uncarriedDeclaration in filledHole.uncarriedDeclarations {
					var pathDeclaration = PathDeclaration(
						property: uncarriedDeclaration.property,
						isBoundBeforeSite: false,
						sendableDepth: sendableDepth,
						access: seamTypeAccess,
						accessCause: nil,
						declaringType: uncarriedDeclaration.declaringType,
						declarationLocation: uncarriedDeclaration.declarationLocation,
						parameterTakingType: uncarriedDeclaration.parameterTakingType,
					)
					pathDeclaration.builtAfter = uncarriedDeclaration.builtAfter
					pathDeclaration.reason = uncarriedDeclaration.reason
					pathDeclaration.frameLevel = level
					declare(pathDeclaration)
				}
				// A `@Sendable` fill encloses what it binds: what binds it before is outside. The scope the fill's function builds
				// is next on the path.
				if frame.fillIsSendable {
					sendableDepth += 1
					sendableFunctions.append((filledHole.property, frame.generator.children.first?.builtInstantiable?.concreteInstantiable))
				}
				for field in filledHole.fields where frame.generator.fillStructBoundLabels.contains(field.property.label) {
					let fieldAccess = access(of: field.property, declaredBy: instantiables[field.declaringType]?.moduleName)
					declare(PathDeclaration(
						property: field.property,
						isBoundBeforeSite: true,
						sendableDepth: sendableDepth,
						access: fieldAccess.level,
						accessCause: fieldAccess.cause,
						declaringType: field.declaringType,
						declarationLocation: field.declarationLocation,
						isReceivedOnlyIfAvailable: field.isReceivedOnlyIfAvailable,
						parameterTakingType: field.parameterTakingType,
						frameLevel: level,
					))
				}
				endLevel(builtType: nil, nextProperty: frame.orderedChildren[frame.nextPosition - 1].generator.property)
				continue
			}
			guard let instantiable = frame.generator.builtInstantiable else { continue }
			childDeclaringType = instantiable.concreteInstantiable
			// A `@Sendable` builder function on the path encloses what it binds: what binds it before is outside.
			if level > 0, let property = frame.generator.property, frame.generator.buildsInSendableFunction {
				sendableDepth += 1
				sendableFunctions.append((property, instantiable.concreteInstantiable))
			}
			func declaration(of property: Property, isBoundBeforeSite: Bool) -> PathDeclaration {
				let propertyAccess = access(of: property, declaredBy: instantiable.moduleName)
				return PathDeclaration(
					property: property,
					isBoundBeforeSite: isBoundBeforeSite,
					sendableDepth: sendableDepth,
					access: propertyAccess.level,
					accessCause: propertyAccess.cause,
					declaringType: instantiable.concreteInstantiable,
					declarationLocation: instantiable.dependencies.first { $0.property == property }?.declarationLocation,
					frameLevel: level,
				)
			}
			// The root's forwarded properties are parameters, declared above.
			if level > 0 {
				for dependency in instantiable.dependencies where dependency.source == .forwarded {
					var forwardedDeclaration = declaration(of: dependency.property, isBoundBeforeSite: true)
					forwardedDeclaration.isForwarded = true
					declare(forwardedDeclaration)
				}
				// A member of a loop of builders begins its builder function by wrapping again what its tree receives inside
				// the loop (`ScopeGenerator.ReceivedBuilderLoops`): each wrapper is the nearest declaration of its label in the
				// function, bound before anything the function builds, and declared by the scope that declares the loop.
				for reboundProperty in frame.generator.reboundProperties {
					let reboundAccess = access(of: reboundProperty, declaredBy: loopDeclaringInstantiable.moduleName)
					declare(PathDeclaration(
						property: reboundProperty,
						isBoundBeforeSite: true,
						sendableDepth: sendableDepth,
						access: reboundAccess.level,
						accessCause: reboundAccess.cause,
						declaringType: loopDeclaringInstantiable.concreteInstantiable,
						declarationLocation: loopDeclaringInstantiable.dependencies.first { $0.property == reboundProperty }?.declarationLocation,
						frameLevel: level,
					))
				}
			}
			// The parameters of a builder function a lazy cycle closes on follow its forwarded ones, and hide every other
			// declaration of their labels, a deferred parameter's memo included: a field of such a label holds the value the
			// function was passed, as inline's site reads it. A parameter is declared, as far as a fill's reader is told, by
			// the first type in the function's body that receives it.
			if frame.generator.declaresCycleParameters {
				// A receiver's chain ends at the receiving type.
				let parametersWithReceivingType = frame.generator.cycleParameters.compactMap { parameter in
					parameter.receiver.chain.last.map { (parameter: parameter, receivingType: $0) }
				}
				for (parameter, receivingType) in parametersWithReceivingType {
					let parameterAccess = access(of: parameter.property, declaredBy: instantiables[receivingType]?.moduleName)
					var parameterDeclaration = PathDeclaration(
						property: parameter.property,
						isBoundBeforeSite: true,
						sendableDepth: sendableDepth,
						access: parameterAccess.level,
						accessCause: parameterAccess.cause,
						declaringType: receivingType,
						declarationLocation: parameter.receiver.declarationLocation,
						parameterTakingType: instantiable.concreteInstantiable,
						frameLevel: level,
					)
					parameterDeclaration.isCycleParameter = true
					parameterDeclaration.cycleParameterOrigin = SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin(
						takingType: instantiable.concreteInstantiable,
						property: parameter.redeclaration.property,
						declaringType: parameter.redeclaration.declaringType,
						declarationLocation: parameter.redeclaration.declarationLocation,
						isForwarded: instantiables[parameter.redeclaration.declaringType]?.dependencies.contains { $0.source == .forwarded && $0.property == parameter.redeclaration.property } ?? false,
					)
					declare(parameterDeclaration)
				}
			}
			let pathPosition = frame.nextPosition - 1
			let pathProperty = frame.orderedChildren[pathPosition].generator.property
			let carrierProperties = frame.orderedChildren.compactMap { frame.generator.startsAsCarrier($0.generator) ? $0.generator.property : nil }
			for (position, child) in frame.orderedChildren.enumerated() {
				guard let property = child.generator.property else { continue }
				// An `onlyIfAvailable` alias is bound, to `nil` where its fulfilling property is unavailable, as every other
				// child is.
				// A member of the loop of builders the scope on the path is on (`ScopeGenerator.ReceivedBuilderLoops`) is still
				// being built where the loop's payloads are bound, before the loop's first function.
				let isLoopMemberBuildingSite = position < pathPosition
					&& frame.generator.areMembersOfOneLoop(child.generator, frame.orderedChildren[pathPosition].generator)
				var pathDeclaration = declaration(of: property, isBoundBeforeSite: position < pathPosition && !isLoopMemberBuildingSite)
				if case let .aliased(fulfillingProperty, _, _)? = instantiable.dependencies.first(where: { $0.property == property })?.source {
					// An alias binds its label to `fulfillingProperty`: the seam's, to the caller's, and any other type's, to one
					// the seam's tree binds.
					pathDeclaration.alias = .init(fulfillingProperty: fulfillingProperty, isSeams: level == 0)
				}
				if position == pathPosition && ScopeGenerator.isBuilder(property) || isLoopMemberBuildingSite {
					// An instantiator on the path, or a member of its loop, is building the site: inline, a receive of it in a
					// fill's tree would read a wrapper made again of the function the seam's initializer declares.
					pathDeclaration.reason = .instantiatorBuildingSite
				} else if position > pathPosition, let pathProperty, let childType = child.generator.builtInstantiable?.concreteInstantiable {
					// A sibling built after the scope on the path depends on a carrier: the start order builds every other
					// one first.
					pathDeclaration.builtAfter = pathProperty
					if child.generator.onlyIfAvailableUnwrappedReceivedProperties.contains(pathProperty.asUnwrappedProperty) {
						pathDeclaration.reason = .receivesPathScopeOnlyIfAvailable(type: childType)
					} else if let carrier = carrierProperties.first(where: { $0 != pathProperty && child.generator.requiredReceivedProperties.contains($0) }) {
						pathDeclaration.reason = .requiresOtherCarrier(type: childType, carrier: carrier)
					}
				}
				declare(pathDeclaration)
			}
			loopDeclaringInstantiable = instantiable
			endLevel(builtType: instantiable.concreteInstantiable, nextProperty: pathProperty)
		}
		// A `Sendable` wrapper the seam builds around the builder is built in a `@Sendable` function of its own, which binds
		// nothing.
		if site.property.propertyType.isSendable {
			sendableDepth += 1
			sendableFunctions.append((site.property, nil))
		}
		var fields = [SeamSignature.Hole.Field]()
		var uncarriedDeclarations = [SeamSignature.Hole.UncarriedDeclaration]()
		var pathFields = [Property]()
		var pathUncarriedProperties = [Property]()
		for label in labelsInBindingOrder {
			guard let declaration = nearestDeclarations[label] else { continue }
			if declaration.isBoundBeforeSite {
				pathFields.append(declaration.property)
				if declaration.sendableDepth == sendableDepth {
					fields.append(SeamSignature.Hole.Field(
						property: declaration.property,
						access: declaration.access,
						accessCause: declaration.accessCause,
						declaringType: declaration.declaringType,
						declarationLocation: declaration.declarationLocation,
						isReceivedOnlyIfAvailable: declaration.isReceivedOnlyIfAvailable,
						parameterTakingType: declaration.parameterTakingType,
						deferral: declaration.deferral,
					))
				} else if declaration.frameLevel >= 0, let innermostFunction = sendableFunctions.last {
					// Bound in the seam's tree outside the innermost `@Sendable` function: a fill that reads it is reported. A
					// parameter of the seam is the caller's, which a fill reads from its own scope.
					uncarriedDeclarations.append(SeamSignature.Hole.UncarriedDeclaration(
						property: declaration.property,
						declaringType: declaration.declaringType,
						declarationLocation: declaration.declarationLocation,
						parameterTakingType: declaration.parameterTakingType,
						builtAfter: nil,
						reason: .boundOutsideSendableFunction(functionProperty: innermostFunction.property, functionBuiltType: innermostFunction.builtType, isForwarded: declaration.isForwarded, cycleParameter: declaration.cycleParameterOrigin, alias: declaration.alias),
					))
				}
			} else {
				pathUncarriedProperties.append(declaration.property)
				uncarriedDeclarations.append(SeamSignature.Hole.UncarriedDeclaration(
					property: declaration.property,
					declaringType: declaration.declaringType,
					declarationLocation: declaration.declarationLocation,
					parameterTakingType: declaration.parameterTakingType,
					builtAfter: declaration.builtAfter,
					reason: declaration.reason,
				))
			}
		}
		// A scope on the path whose builder function a cycle-closing scope in its tree calls is built again there, and handed,
		// for each label a scope between the two declares, that declaration (`CycleParameter`). A label whose nearest
		// declaration at the site is inside the function, the function's own parameter of the label included, is bound again
		// at each level. Any other value a fill reads is the same at every level.
		var cycleReentryDeclarations = [SeamSignature.Hole.CycleReentryDeclaration]()
		for (level, generator, closedOnDeclaration, closedOnDeclaringType) in scopesACycleClosesOn {
			let declarationsBetween = declarationsBetweenByClosedOnScope[ObjectIdentifier(generator)] ?? declarationsBetween(closedOnScope: generator, closedOnDeclaration: closedOnDeclaration)
			declarationsBetweenByClosedOnScope[ObjectIdentifier(generator)] = declarationsBetween
			/// Whether the site reads the value of `label` bound inside the function. A place nested by type reads a parameter
			/// of a builder function from its type's level, which carries every one any build of the type declares.
			func isBoundInsideFunction(_ label: String) -> Bool {
				guard let nearest = nearestDeclarations[label] else { return false }
				return nearest.frameLevel >= level
			}
			for between in declarationsBetween
				where between.property.label != site.property.label
				&& !cycleReentryDeclarations.contains(where: { $0.property.label == between.property.label })
				&& !isBoundInsideFunction(between.property.label)
			{
				cycleReentryDeclarations.append(SeamSignature.Hole.CycleReentryDeclaration(
					property: between.property,
					declaringType: between.declaringType,
					declarationLocation: between.declarationLocation,
					parameterTakingType: between.parameterTakingType,
					closedOnProperty: between.closedOnProperty,
					closedOnDeclaringType: closedOnDeclaringType,
					reenteringType: between.reenteringType,
				))
			}
		}
		return (fields, uncarriedDeclarations, cycleReentryDeclarations, levels.reversed(), pathFields, pathUncarriedProperties)
	}

	/// A declaration between the builder function of a scope a cycle closes on and a cycle-closing scope that calls it.
	struct DeclarationBetween {
		let property: Property
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		/// The type whose builder function takes the label as a parameter between the two, when a cycle nested inside passes
		/// it the declaration above, or `nil` when `declaringType` is between the two itself.
		let parameterTakingType: TypeDescription?
		/// The property whose builder function the cycle closes on.
		let closedOnProperty: Property
		/// The type that instantiates `closedOnProperty` again.
		let reenteringType: TypeDescription
	}

	/// A declaration on the path from the builder function a cycle closes on to a scope beneath it.
	private struct DeclarationOnCyclePath {
		let declaration: SeamSignature.Hole.UncarriedDeclaration
		/// For a parameter of the builder function of a scope between, which a cycle nested inside closes on, that scope.
		let parameterOfScope: ObjectIdentifier?
	}

	/// A parameter of the builder function of a scope a nested cycle closes on.
	private struct NestedCycleParameter: Hashable {
		let scope: ObjectIdentifier
		let label: String
	}

	/// A scope on the path whose builder function a nested cycle closes on.
	private struct NestedClosedOnScope {
		let scope: ObjectIdentifier
		let declaration: ScopeGenerator.BuiltDeclaration?
		let parameterLabels: [String]
		/// The index in the path's declarations of the first declaration beneath the scope.
		let firstDeclarationBeneath: Int
	}

	/// The declarations between the builder function of `closedOnScope` and each cycle-closing scope in its tree that calls
	/// that function, the nearest to the cycle-closing scope of each label on its path, the first of each label in a
	/// depth-first walk in declaration order: the instantiated, aliased and forwarded properties and the builder function
	/// parameters of each scope between, whose labels inline makes parameters of the function
	/// (`cycleClosingRedeclaredLabels`), less the scope's own property and the labels it declares itself, whose nearest
	/// declaration in the function is its own. The labels of the function's own parameters are kept: the function binds them,
	/// which `fields(of:)` decides per place. A parameter of a scope between, which a cycle nested inside passes, is
	/// reported as the declaration that cycle's cycle-closing scope passes it, the first a depth-first walk meets. A fill
	/// in the tree is another seam's, whose cycle-closing scopes close on that seam's path.
	private static func declarationsBetween(closedOnScope: ScopeGenerator, closedOnDeclaration: ScopeGenerator.BuiltDeclaration) -> [DeclarationBetween] {
		let closedOnProperty = closedOnDeclaration.property
		var ownLabels: Set<String> = [closedOnProperty.label]
		for declaration in declarationsBound(by: closedOnScope, includingForwardedProperties: true, reason: .other) {
			ownLabels.insert(declaration.property.label)
		}
		if closedOnScope.declaresCycleParameters {
			// A label the scope declares itself is no parameter of its function, so this removes only the parameters'.
			ownLabels.subtract(closedOnScope.cycleParameters.map(\.property.label))
		}
		var declarationsMet = [(declaration: DeclarationOnCyclePath, reenteringType: TypeDescription)]()
		var bindingByNestedCycleParameter = [NestedCycleParameter: DeclarationOnCyclePath]()
		var generatorsToVisit = closedOnScope.children.reversed().map { (generator: $0, parentType: closedOnDeclaration.concreteType, pathDeclarations: [DeclarationOnCyclePath](), nestedClosedOnScopes: [NestedClosedOnScope]()) }
		while let (generator, parentType, pathDeclarations, nestedClosedOnScopes) = generatorsToVisit.popLast() {
			if generator.closesPropertyCycle, generator.closedOnDeclaration == closedOnDeclaration {
				// The nearest declaration of each label on the path, which the cycle-closing scope passes the function.
				var labelsMet = Set<String>()
				for pathDeclaration in pathDeclarations.reversed()
					where labelsMet.insert(pathDeclaration.declaration.property.label).inserted
					&& !ownLabels.contains(pathDeclaration.declaration.property.label)
					&& !declarationsMet.contains(where: { $0.declaration.declaration.property.label == pathDeclaration.declaration.property.label })
				{
					declarationsMet.append((pathDeclaration, parentType))
				}
			} else if generator.closesPropertyCycle, let nestedClosedOnScope = nestedClosedOnScopes.last(where: { $0.declaration == generator.closedOnDeclaration }) {
				// A nested cycle passes each parameter of the function it closes on its nearest declaration beneath that scope.
				let declarationsBeneath = pathDeclarations[nestedClosedOnScope.firstDeclarationBeneath...]
				for label in nestedClosedOnScope.parameterLabels
					where bindingByNestedCycleParameter[NestedCycleParameter(scope: nestedClosedOnScope.scope, label: label)] == nil
				{
					bindingByNestedCycleParameter[NestedCycleParameter(scope: nestedClosedOnScope.scope, label: label)] = declarationsBeneath.last { $0.declaration.property.label == label }
				}
			} else if generator.fillHole == nil, let instantiable = generator.builtInstantiable {
				var childPathDeclarations = pathDeclarations
				for declaration in declarationsBound(by: generator, includingForwardedProperties: true, reason: .other) {
					childPathDeclarations.append(DeclarationOnCyclePath(declaration: declaration, parameterOfScope: nil))
				}
				var childNestedClosedOnScopes = nestedClosedOnScopes
				for parameter in generator.cycleParameters {
					childPathDeclarations.append(DeclarationOnCyclePath(
						declaration: SeamSignature.Hole.UncarriedDeclaration(property: parameter.property, declaringType: instantiable.concreteInstantiable, declarationLocation: nil, builtAfter: nil, reason: .other),
						parameterOfScope: ObjectIdentifier(generator),
					))
				}
				if !generator.cycleParameters.isEmpty {
					childNestedClosedOnScopes.append(NestedClosedOnScope(scope: ObjectIdentifier(generator), declaration: generator.declaration, parameterLabels: generator.cycleParameters.map(\.property.label), firstDeclarationBeneath: childPathDeclarations.count))
				}
				generatorsToVisit.append(contentsOf: generator.children.reversed().map { ($0, instantiable.concreteInstantiable, childPathDeclarations, childNestedClosedOnScopes) })
			}
		}
		return declarationsMet.map { pathDeclaration, reenteringType in
			// A nested cycle's parameter is bound by a declaration beneath the scope that takes it, so the chain ends.
			var binding = pathDeclaration
			while let scope = binding.parameterOfScope, let next = bindingByNestedCycleParameter[NestedCycleParameter(scope: scope, label: binding.declaration.property.label)] {
				binding = next
			}
			return DeclarationBetween(
				property: binding.declaration.property,
				declaringType: binding.declaration.declaringType,
				declarationLocation: binding.declaration.declarationLocation,
				parameterTakingType: pathDeclaration.parameterOfScope.map { _ in pathDeclaration.declaration.declaringType },
				closedOnProperty: closedOnProperty,
				reenteringType: reenteringType,
			)
		}
	}
}

extension SeamSignature.Hole {
	/// The labels of the properties of `sitePath` but the last, the hole's own, without backticks, joined with `_`.
	static func pathLabels(of sitePath: [Property]) -> String {
		sitePath.dropLast().map(\.label.spelledWithoutBackticks).joined(separator: "_")
	}
}

extension SeamSignature.Hole.PathType {
	/// What `generator`, a generator on the way to a hole's owner, adds to the path: the type it builds, or, for a fill,
	/// the way from the seam it fills to the hole it fills.
	static func pathTypes(through generator: ScopeGenerator) -> [SeamSignature.Hole.PathType] {
		generator.fillHole?.typesToOwner ?? generator.builtInstantiable.map { [SeamSignature.Hole.PathType(type: $0.concreteInstantiable, moduleName: $0.moduleName)] } ?? []
	}
}

// MARK: - Unfilled holes

extension DependencyTreeGenerator {
	/// Throws `unfilledHoles` for every hole a root's tree calls a seam with and cannot fill – no production declaration
	/// the root's module sees fulfills it, or the one that does is out of the tree's reach because the root's module does
	/// not list a module on the way to the hole, so the seam call would pass the builder up, which a root cannot – once
	/// per declaration of the hole's property per root, naming the first chain a declaration-order walk of the root's
	/// tree meets, the fills the root's module generates included.
	/// - Parameter viewInstantiablesByModuleName: The declarations of the modules the root's module reads only through
	///   module info views, by module, among which a module on the way to the hole may fulfill it.
	static func validateRootsFillEveryHole(
		roots: [Scope],
		callerModuleName: String?,
		instantiables: [TypeDescription: Instantiable],
		viewInstantiablesByModuleName: [String: [Instantiable]],
		isReadableFile: (@Sendable (String) -> Bool)?,
	) throws {
		var unfilledHoles = [DependencyTreeGeneratorError.UnfilledHole]()
		for root in roots {
			var reportedDeclarations = Set<HoleDeclaration>()
			var visitedScopes = Set<ObjectIdentifier>()
			// Each scope to visit with the chain of types to it and the root's dependency through which the tree reaches it.
			var scopesToVisit: [(scope: Scope, chain: [TypeDescription], rootDependency: Dependency?)] = [(root, [root.instantiable.concreteInstantiable], nil)]
			while let (scope, chain, rootDependency) = scopesToVisit.popLast() {
				guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
				var childrenToVisit = [(scope: Scope, chain: [TypeDescription], rootDependency: Dependency?)]()
				for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
					let childRootDependency = rootDependency ?? root.instantiable.dependencies.first { $0.property == property }
					let childChain = chain + [childScope.instantiable.concreteInstantiable]
					for holeArgument in childScope.holeArguments {
						let hole = holeArgument.hole
						// The first property on the way is the called seam's, which `childChain` ends with.
						let holeChain = childChain + (hole.passedUpRoute + hole.declaredSitePath).dropFirst().compactMap(\.declaringType)
						switch holeArgument {
						case let .fill(_, fulfillingScope):
							childrenToVisit.append((fulfillingScope, holeChain + [fulfillingScope.instantiable.concreteInstantiable], childRootDependency))
						case .passUp:
							guard reportedDeclarations.insert(HoleDeclaration(owner: hole.ownerType, property: hole.property)).inserted else { continue }
							// The tree reaches only what the root's module lists, so a module on the way to the hole that it does not
							// list stops the walk before it meets the hole's type, and a declaration of that type gets no scope.
							let unlistedModuleNames = hole.typesToOwner
								.filter { instantiables[$0.type]?.moduleName != $0.moduleName }
								.compactMap(\.moduleName)
								.uniqued()
							unfilledHoles.append(DependencyTreeGeneratorError.UnfilledHole(
								hole: hole,
								rootType: root.instantiable.concreteInstantiable,
								chain: holeChain,
								location: childRootDependency?.declarationLocation,
								noteLocation: hole.declarationLocation.flatMap { location in isReadableFile.map { $0(location.filePath) } ?? true ? location : nil },
								callerModuleName: callerModuleName,
								unlistedModuleNames: unlistedModuleNames,
								unreachedFulfillingType: unlistedModuleNames.isEmpty ? nil : fulfillingType(of: hole, seenThroughListing: unlistedModuleNames, in: instantiables, viewInstantiablesByModuleName: viewInstantiablesByModuleName),
								fulfilledByMockOnlyDeclaration: instantiables[hole.instantiatedType]?.mockOnly == true,
							))
						}
					}
					if childScope.seamCall == nil {
						childrenToVisit.append((childScope, childChain, childRootDependency))
					}
				}
				scopesToVisit.append(contentsOf: childrenToVisit.reversed())
			}
		}
		if !unfilledHoles.isEmpty {
			throw DependencyTreeGeneratorError.unfilledHoles(unfilledHoles)
		}
	}

	/// The type that fulfills `hole` once the root's module lists `unlistedModuleNames`: one among the declarations it
	/// reads, or else one of those modules declares, the first in chain order. A module on the way to a hole can declare a
	/// fulfilling type its own run did not use: it need not list a module beneath the seam it calls, so its walk stops
	/// before the hole, which it passes up. `nil` when none does, and listing those modules alone leaves the builder unfilled.
	private static func fulfillingType(
		of hole: SeamSignature.Hole,
		seenThroughListing unlistedModuleNames: [String],
		in instantiables: [TypeDescription: Instantiable],
		viewInstantiablesByModuleName: [String: [Instantiable]],
	) -> TypeDescription? {
		fulfillingInstantiable(of: hole, in: instantiables)?.concreteInstantiable
			?? unlistedModuleNames.lazy
			.compactMap { viewInstantiablesByModuleName[$0]?.first { !$0.mockOnly && $0.instantiableTypes.contains(hole.instantiatedType) } }
			.first?.concreteInstantiable
	}

	/// The declaration of a hole's property, by which a hole is reported once however many sites it has.
	private struct HoleDeclaration: Hashable {
		let owner: TypeDescription
		let property: Property
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError {
	/// A hole whose builder a root's tree cannot fill: no production declaration the root's module sees fulfills it, or the
	/// one that does is out of the tree's reach.
	struct UnfilledHole {
		let hole: SeamSignature.Hole
		let rootType: TypeDescription
		/// The types from the root to the hole's owner.
		let chain: [TypeDescription]
		/// The root's dependency through which its tree reaches the seam.
		let location: Dependency.DeclarationLocation?
		/// The hole's declaration, where its file can be read.
		let noteLocation: Dependency.DeclarationLocation?
		let callerModuleName: String?
		/// The modules that declare a type on the way from the seam the tree calls to the hole's owner, which the root's
		/// module does not read the declarations of, in chain order, each once. Each is a fact of the hole, so no order among
		/// modules decides which one the error names.
		let unlistedModuleNames: [String]
		/// The type that fulfills the hole among the declarations the root's module reads or the modules of
		/// `unlistedModuleNames` declare, when `unlistedModuleNames` is why the tree never reached it, so listing them is
		/// the whole fix.
		let unreachedFulfillingType: TypeDescription?
		let fulfilledByMockOnlyDeclaration: Bool

		var sourceDiagnostics: [SourceDiagnostic] {
			let typeName = "`\(hole.instantiatedType.asSource)`"
			let seamName = "`\(hole.scopeSeamType.asSource)`"
			let callerModule = callerModuleName.map { "module `\($0)`" } ?? "this module"
			let reference = "\(typeName), which @\(Dependency.Source.instantiatedRawValue) property `\(hole.property.asSource)` instantiates in chain: \(chain.map(\.asSource).joined(separator: " -> "))"
			let seamModule = if let seamModuleName = hole.scopeSeamModule.moduleName, seamModuleName != callerModuleName {
				"in module `\(seamModuleName)`, which cannot see one either"
			} else {
				"in \(callerModule)"
			}
			let unlistedModules = unlistedModuleNames.map { "`\($0)`" }.joinedAsList(conjunction: "or")
			let listRemedy = (unlistedModuleNames.count > 1 ? "for each, " : "") + DependencyTreeGenerator.DependencyTreeGeneratorError.listModuleRemedy
			let listUnlistedModules = unlistedModuleNames.isEmpty ? "" : " A module that declares a root lists every module beneath it, and \(callerModule) does not list \(unlistedModules): \(listRemedy) Listing \(unlistedModuleNames.count > 1 ? "them" : "it") lets SafeDI follow the chain, but \(typeName) still needs a declaration that fulfills it."
			let takenBuilder = hole.enumPlace.map { "`\(hole.builderLabel)`, whose case `\($0.describedCase)` builds `\(hole.property.label)`" } ?? "`\(hole.builderLabel)`, which builds `\(hole.property.label)`"
			let fill = "\(seamName) generates its dependency tree \(seamModule), so the initializer SafeDI generated for it takes \(takenBuilder), and the root `\(rootType.asSource)` must fill it.\(listUnlistedModules)"
			let message = if let unreachedFulfillingType {
				"`\(unreachedFulfillingType.asSource)` fulfills \(reference), but SafeDI cannot follow that chain, because \(callerModule) does not list \(unlistedModules). A module that declares a root lists every module beneath it: \(listRemedy)"
			} else if fulfilledByMockOnlyDeclaration {
				"No production @\(InstantiableVisitor.macroName) declaration that \(callerModule) can see fulfills \(reference). \(fill) A `mockOnly: true` declaration fulfills it, but is used only to generate mocks. Add a production @\(InstantiableVisitor.macroName) declaration that fulfills \(typeName)."
			} else {
				"No @\(InstantiableVisitor.macroName) type or extension that \(callerModule) can see fulfills \(reference). \(fill) Decorate \(typeName), or an extension of it, with @\(InstantiableVisitor.macroName); list \(typeName) in the `fulfillingAdditionalTypes` of an @\(InstantiableVisitor.macroName) type that conforms to it; \(DependencyTreeGenerator.DependencyTreeGeneratorError.fulfillingDeclarationInAnotherModuleRemedy)"
			}
			return [SourceDiagnostic(severity: .error, location: location, message: message)]
				+ (noteLocation.map { [SourceDiagnostic(severity: .note, location: $0, message: "`\(hole.ownerType.asSource)` instantiates `\(hole.property.asSource)` here.")] } ?? [])
		}
	}
}

// MARK: - What a fill cannot do

extension DependencyTreeGenerator {
	/// Throws `fillFindings` for every receive in a fill of the trees `generators` root that no value the fill holds gives
	/// inline's value for – a cycle in the seam's tree hands the site's owner another declaration of its label when it
	/// builds it again, the nearest declaration of its label on the site's path is bound after the site, the scope struct
	/// carries it at an access the caller cannot read, or carries it only as an optional value while the receive requires
	/// it – and for every scope in a fill that closes a cycle on a property of the seam's path, which code
	/// generated outside the seam's module cannot refer to. Each finding once, by kind and location: of several fills that
	/// give one, the finding that comes first in source order (`FillFinding.precedesInSourceOrder`), never the first the
	/// walk meets, since builders are in label order.
	static func validateFills(
		inTreesRootedAt generators: [ScopeGenerator],
		callerModule: ModuleIdentity,
	) throws {
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		var findingIndexByKey = [String: Int]()
		func record(_ finding: DependencyTreeGeneratorError.FillFinding) {
			if let index = findingIndexByKey[finding.key] {
				if finding.precedesInSourceOrder(findings[index]) {
					findings[index] = finding
				}
			} else {
				findingIndexByKey[finding.key] = findings.count
				findings.append(finding)
			}
		}
		for root in generators {
			// Each generator with what the calls inside every fill of its seam call hide from it, when it is such a fill.
			var generatorsToVisit = [(generator: root, hidden: FillReentryHidings?.none)]
			while let (generator, hidden) = generatorsToVisit.popLast() {
				if let hole = generator.fillHole, let child = generator.children.first {
					findingsOfFill(of: hole, child: child, hidden: hidden ?? FillReentryHidings(), requirement: AccessLevel.required(toConstructFrom: callerModule, declaredIn: hole.scopeSeamModule, isOwnFile: false), callerModule: callerModule).forEach(record)
				}
				// A seam call's children are its fills, which are judged against the calls inside any of them.
				let hiddenByFillKey = generator.seamCall == nil ? [:] : hiddenByReenteringCalls(ofFillsOf: generator)
				if generator.seamCall != nil {
					findingsOfCasesNestedByType(filledBy: generator.children).forEach(record)
				}
				generatorsToVisit.append(contentsOf: generator.children.reversed().map { child in
					(child, child.fillKey.flatMap { hiddenByFillKey[$0] })
				})
			}
		}
		if !findings.isEmpty {
			throw DependencyTreeGeneratorError.fillFindings(findings)
		}
	}

	/// The findings of the cases nested by type that `fills`, the children of one seam call's generator, fill: one function
	/// fills every place of such a case, so a value its tree reads that the places' routes hold in forms that differ in more
	/// than optionality (`ScopeGenerator.irreconcilableFields(of:)`) is one no parameter can take. Each label once per
	/// case, in label order.
	private static func findingsOfCasesNestedByType(filledBy fills: [ScopeGenerator]) -> [DependencyTreeGeneratorError.FillFinding] {
		var placesByCaseKey = [String: [SeamSignature.Hole]]()
		var emittingFillByCaseKey = [String: ScopeGenerator]()
		var caseKeys = [String]()
		for fill in fills {
			guard let hole = fill.fillHole, hole.enumPlace?.isNestedByType == true else { continue }
			let caseKey = ScopeGenerator.fillCaseKey(of: hole)
			if placesByCaseKey[caseKey] == nil {
				caseKeys.append(caseKey)
			}
			placesByCaseKey[caseKey, default: []].append(hole)
			if fill.fillEmitsCode {
				emittingFillByCaseKey[caseKey] = fill
			}
		}
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		for caseKey in caseKeys {
			guard let places = placesByCaseKey[caseKey], let firstPlace = places.first, let child = emittingFillByCaseKey[caseKey]?.children.first else { continue }
			let irreconcilableFields = ScopeGenerator.irreconcilableFields(of: places)
			for label in irreconcilableFields.keys.sorted() {
				guard let fields = irreconcilableFields[label],
				      child.receivedProperties.contains(where: { $0.label == label }) || child.fieldsCarriedBySites.contains(where: { $0.label == label })
				else { continue }
				findings.append(.init(hole: firstPlace, kind: .fieldFormsDifferBetweenPlaces(label: label, fields: fields, seamModule: firstPlace.scopeSeamModule)))
			}
		}
		return findings
	}

	/// The findings of the fill of `hole` whose tree `child` roots, in the order the tree declares them. A closer is judged
	/// by what generation found (`ScopeGenerator.closedOnFillPathDeclarationsBeneath`), so only against the stack it was built
	/// with: the walk goes on into a fill nested in this one, whose receives fall through to this fill's fields, but a closer
	/// beneath it is that fill's, which `validateFills` reaches itself. This generator tree holds a seam the fill calls as a
	/// leaf, so a property re-entered through such a call is never judged here; the cycle walk of
	/// `validateCyclesFromRootsOfForeignSeamsWithHoles`, which inlines every seam, judges those.
	/// - Parameter hidden: What the calls inside the fills of the seam call that declares this fill hide from it.
	private static func findingsOfFill(
		of hole: SeamSignature.Hole,
		child: ScopeGenerator,
		hidden: FillReentryHidings,
		requirement: AccessRequirement,
		callerModule: ModuleIdentity,
	) -> [DependencyTreeGeneratorError.FillFinding] {
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		// The hole says which module declares each seam: this run may know a seam only through a module that calls it.
		let seamModule = hole.scopeSeamModule
		let fields = hole.fields
		typealias Frame = (generator: ScopeGenerator, parent: Instantiable, providedProperties: Set<Property>, fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor], judgesClosers: Bool)
		var framesToVisit = [Frame]()
		func isProvided(_ property: Property, by providedProperties: Set<Property>) -> Bool {
			providedProperties.contains(property)
				|| (property.typeDescription.isOptional && providedProperties.contains(property.asUnwrappedProperty))
		}
		/// Whether `property`, which a type in the fill's tree receives, is the hole's own property, or its instance.
		func isHolesOwnProperty(_ property: Property) -> Bool {
			[hole.property, hole.property.asLazilyInstantiatedInstanceProperty]
				.compactMap(\.self)
				.contains { $0 == property || $0 == property.asUnwrappedProperty }
		}
		func checkReceive(of property: Property, by instantiable: Instantiable, declaredAt declarationLocation: Dependency.DeclarationLocation?, onlyIfAvailable: Bool) {
			// Inline, a receive only if available of the property the fill builds finds it still being built and is handed
			// `nil`, which the fill's tree passes it too, unless the property is an instantiator, which is handed a wrapper of
			// its own (see `instantiatorBuildingSite`).
			guard !onlyIfAvailable || ScopeGenerator.isBuilder(hole.property) || !isHolesOwnProperty(property) else { return }
			let reader = DependencyTreeGeneratorError.FillFinding.Reader(property: property, type: instantiable.concreteInstantiable, declarationLocation: declarationLocation)
			let sameLabelFields = fields.filter { $0.property.label == property.label }
			// A value a cycle in the seam's tree hands the site's owner when it builds it again is wrong at every level but the
			// first, whether a field carries the label or the fill reads it from the caller's scope.
			if let declaration = hole.cycleReentryDeclarations.first(where: { $0.property.label == property.label }) {
				findings.append(.init(hole: hole, kind: .declarationBoundOnCycleReentry(reader: reader, declaration: declaration, seamModule: seamModule)))
			} else if let field = sameLabelFields.first(where: { field in
				field.property == property
					|| (property.typeDescription.isOptional && field.property == property.asUnwrappedProperty)
					|| field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding.map { $0 == property || (property.typeDescription.isOptional && $0 == property.asUnwrappedProperty) } == true
			}) {
				if !field.access.satisfies(requirement) {
					findings.append(.init(hole: hole, kind: .fieldNotReadable(reader: reader, field: field, callerModule: callerModule, seamModule: seamModule, requirement: requirement)))
				}
			} else if !onlyIfAvailable, let field = sameLabelFields.first(where: { $0.property.typeDescription.isOptional && $0.property.asUnwrappedProperty == property }) {
				findings.append(.init(hole: hole, kind: .fieldHeldOnlyOptionally(reader: reader, field: field, seamModule: seamModule)))
			} else if sameLabelFields.isEmpty, let declaration = hole.uncarriedDeclarations.first(where: { $0.property.label == property.label })
				// A call inside a fill that passes it to a seam passing the site up hands it that seam's copy of the hole,
				// which does not carry what that seam binds on its path to the call presenting the site.
				?? hidden.calledCopyDeclarations[property.label]
			{
				switch declaration.reason {
				case let .boundByPassingUpSeam(_, passingUpSeamModule, _):
					findings.append(.init(hole: hole, kind: .declarationBoundAfterSite(reader: reader, declaration: declaration, seamModule: passingUpSeamModule)))
				case .instantiatorBuildingSite:
					findings.append(.init(hole: hole, kind: .receivesInstantiatorBuildingSite(reader: reader, declaration: declaration, seamModule: seamModule)))
				case .receivesPathScopeOnlyIfAvailable, .requiresOtherCarrier, .other, .boundOutsideSendableFunction:
					findings.append(.init(hole: hole, kind: .declarationBoundAfterSite(reader: reader, declaration: declaration, seamModule: seamModule)))
				}
			} else if sameLabelFields.isEmpty, let hiding = hidden.pathDeclarations[property.label] {
				findings.append(.init(hole: hole, kind: .declarationBoundOnPathToReenteringCall(
					reader: reader,
					declaration: hiding.declaration,
					pathHole: hiding.pathHole,
					callingType: hiding.callingType,
					callProperty: hiding.callProperty,
					calledSeam: hiding.calledSeam,
					callerModule: callerModule,
					seamModule: seamModule,
				)))
			}
			// A field of the label with another type is the inline hidden-label error, which validation reported.
		}
		/// Checks the receives of `generator`'s scope and queues the scopes beneath it. A fill nested in this one is no scope
		/// of its own: what it builds is judged for receives as this tree's, and its closers by `validateFills`.
		func visit(_ generator: ScopeGenerator, parent: Instantiable?, providedProperties: Set<Property>, fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor], judgesClosers: Bool) {
			let childProvidedProperties = providedProperties.union(generator.providedProperties)
			if let instantiable = generator.builtInstantiable {
				for dependency in instantiable.dependencies {
					switch dependency.source {
					case let .received(onlyIfAvailable):
						guard !isProvided(dependency.property, by: providedProperties) else { continue }
						checkReceive(of: dependency.property, by: instantiable, declaredAt: dependency.declarationLocation, onlyIfAvailable: onlyIfAvailable)
					case let .aliased(fulfillingProperty, _, onlyIfAvailable):
						guard !isProvided(fulfillingProperty, by: childProvidedProperties) else { continue }
						checkReceive(of: fulfillingProperty, by: instantiable, declaredAt: dependency.declarationLocation, onlyIfAvailable: onlyIfAvailable)
					case .instantiated, .forwarded:
						continue
					}
				}
				let childFillAncestors = fillAncestors + (generator.property.map { [DependencyTreeGeneratorError.FillFinding.FillAncestor(property: $0, builtType: instantiable.concreteInstantiable)] } ?? [])
				framesToVisit.append(contentsOf: generator.children.reversed().map { ($0, instantiable, childProvidedProperties, childFillAncestors, judgesClosers) })
			} else if let parent {
				framesToVisit.append(contentsOf: generator.children.reversed().map { ($0, parent, childProvidedProperties, fillAncestors, judgesClosers && generator.fillHole == nil) })
			}
		}
		visit(child, parent: nil, providedProperties: [], fillAncestors: [], judgesClosers: true)
		while let (generator, parent, providedProperties, fillAncestors, judgesClosers) = framesToVisit.popLast() {
			if generator.closesPropertyCycle {
				// A scope in the fill that closes a cycle on a property of the seam's path refers to a builder function
				// the seam's initializer declares, which code generated outside the seam's module cannot refer to.
				if judgesClosers, let property = generator.property, let declarationsBeneath = generator.closedOnFillPathDeclarationsBeneath {
					findings.append(.init(hole: hole, kind: .closesCycleInSeamTree(
						closingProperty: property,
						closingType: parent.concreteInstantiable,
						declarationLocation: parent.dependencies.first { $0.property == property }?.declarationLocation,
						fillAncestors: fillAncestors,
						closedOnDeclaration: hole.declaredSitePath.dropLast(declarationsBeneath + 1).last,
						closesOnOwnerOfHole: declarationsBeneath == 0,
						seamModule: seamModule,
					)))
				}
			} else {
				visit(generator, parent: parent, providedProperties: providedProperties, fillAncestors: fillAncestors, judgesClosers: judgesClosers)
			}
		}
		return findings
	}
}

extension DependencyTreeGenerator {
	/// A declaration on the path from a fill's root to a call inside the fill that re-enters a fill of the same seam call,
	/// with that call.
	struct DeclarationOnPathToReenteringCall {
		let declaration: SeamSignature.Hole.UncarriedDeclaration
		/// The hole of the fill whose tree holds the path.
		let pathHole: SeamSignature.Hole
		/// The type whose scope makes the call.
		let callingType: TypeDescription
		let callProperty: Property
		let calledSeam: TypeDescription
	}

	/// What the calls inside the fills of one seam call hide from a fill of that call they pass on: inline, the seam such a
	/// call re-enters hands its fill's reads from the caller's scope the nearest declaration of their label at the call,
	/// and a seam that passes the site up hands it what it binds on its path to the call presenting the site; the fill,
	/// one function, reads the outer call's values.
	struct FillReentryHidings {
		/// The declarations of the scopes on the paths from a fill's root to each call inside it that passes this fill on,
		/// by label, the first met for each.
		var pathDeclarations = [String: DeclarationOnPathToReenteringCall]()
		/// The declarations the copies of this fill's hole that those calls' seams take do not carry, by label, the first
		/// met for each.
		var calledCopyDeclarations = [String: SeamSignature.Hole.UncarriedDeclaration]()
	}

	/// What the calls inside the fills of `leaf`'s seam call hide from each of those fills, by the fill's key: each fill's
	/// tree, from the scope of its fulfiller, is walked depth first in declaration order, and at each call inside it that
	/// passes on a fill of `leaf`'s call (a call of a seam that holds the fill's site or passes its builder up), whichever
	/// fill's tree holds the call, that fill is hidden the declarations of the scopes on the path to the call – the fill's
	/// root and the calling scope included, the called seam excluded – and the declarations the called seam's copy of
	/// the hole does not carry. What a path declares is what `holesPassedUp` collects (`declarationsBound(by:…)`), the
	/// root's forwarded properties included. A cycle-closing scope declares nothing.
	fileprivate static func hiddenByReenteringCalls(ofFillsOf leaf: ScopeGenerator) -> [String: FillReentryHidings] {
		hiddenByReenteringCalls(ofFills: leaf.children)
	}

	/// What the calls inside the fills among `children`, the children of one seam call's generator, hide from each of
	/// those fills, by the fill's key (see `hiddenByReenteringCalls(ofFillsOf:)`).
	static func hiddenByReenteringCalls(ofFills children: [ScopeGenerator]) -> [String: FillReentryHidings] {
		var hiddenByFillKey = [String: FillReentryHidings]()
		for case let (pathHole?, fulfiller?) in children.map({ ($0.fillHole, $0.children.first) }) {
			var generatorsToVisit = [(generator: fulfiller, callingType: TypeDescription?.none, pathDeclarations: [SeamSignature.Hole.UncarriedDeclaration]())]
			while let (generator, callingType, pathDeclarations) = generatorsToVisit.popLast() {
				guard !generator.closesPropertyCycle else { continue }
				for (fillKey, calledHole) in generator.enclosingFillsPassed {
					var hidden = hiddenByFillKey[fillKey, default: FillReentryHidings()]
					for declaration in calledHole.uncarriedDeclarations where hidden.calledCopyDeclarations[declaration.property.label] == nil {
						hidden.calledCopyDeclarations[declaration.property.label] = declaration
					}
					// The fill's root declares what is on every path, so a call that is the root itself has no scope above it.
					if let callingType, let callProperty = generator.property, let calledSeam = generator.builtInstantiable?.concreteInstantiable {
						for declaration in pathDeclarations where hidden.pathDeclarations[declaration.property.label] == nil {
							hidden.pathDeclarations[declaration.property.label] = DeclarationOnPathToReenteringCall(declaration: declaration, pathHole: pathHole, callingType: callingType, callProperty: callProperty, calledSeam: calledSeam)
						}
					}
					hiddenByFillKey[fillKey] = hidden
				}
				let childPathDeclarations = pathDeclarations + declarationsBound(by: generator, includingForwardedProperties: true, reason: .other)
				let childCallingType = generator.builtInstantiable?.concreteInstantiable ?? callingType
				generatorsToVisit.append(contentsOf: generator.children.reversed().map { ($0, childCallingType, childPathDeclarations) })
			}
		}
		return hiddenByFillKey
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError {
	/// What a fill of `hole` cannot do.
	struct FillFinding {
		/// A scope on the path from a fill's root down to a scope that closes a cycle: the property it builds, and the
		/// type it builds it with, which declares the next property on the path.
		struct FillAncestor {
			let property: Property
			let builtType: TypeDescription
		}

		/// A receive in a fill's tree.
		struct Reader {
			let property: Property
			let type: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
		}

		enum Kind {
			/// The scope struct carries the value the reader receives at an access the caller's module cannot read.
			case fieldNotReadable(reader: Reader, field: SeamSignature.Hole.Field, callerModule: ModuleIdentity, seamModule: ModuleIdentity, requirement: AccessRequirement)
			/// The scope struct carries the value only as an optional value, which the reader requires.
			case fieldHeldOnlyOptionally(reader: Reader, field: SeamSignature.Hole.Field, seamModule: ModuleIdentity)
			/// A cycle in the seam's tree builds the site's owner again with `declaration`, which a scope between the function
			/// the cycle closes on and the cycle-closing scope declares, while the fill reads the same value at every level.
			case declarationBoundOnCycleReentry(reader: Reader, declaration: SeamSignature.Hole.CycleReentryDeclaration, seamModule: ModuleIdentity)
			/// The nearest declaration of the reader's label on the site's path is bound after the site, or the seam
			/// that passes the builder up binds it; `seamModule` is the module that must see a fulfilling declaration.
			case declarationBoundAfterSite(reader: Reader, declaration: SeamSignature.Hole.UncarriedDeclaration, seamModule: ModuleIdentity)
			/// The reader receives an instantiator the seam's tree is building where it builds the site – the hole's own, or
			/// one that builds a scope on the site's path. Inline, the reader would get a wrapper made again of the function the
			/// seam's initializer declares, which code generated outside the seam's module cannot refer to.
			case receivesInstantiatorBuildingSite(reader: Reader, declaration: SeamSignature.Hole.UncarriedDeclaration, seamModule: ModuleIdentity)
			/// A scope of the fill of `pathHole` – this fill, or another of the same seam call – declares the reader's label on
			/// the path from that fill's root to `callingType`'s call of `calledSeam` (`callProperty`), which passes this fill
			/// on: inline, the re-entered seam would read that declaration, and the fill reads the outer call's value.
			case declarationBoundOnPathToReenteringCall(
				reader: Reader,
				declaration: SeamSignature.Hole.UncarriedDeclaration,
				pathHole: SeamSignature.Hole,
				callingType: TypeDescription,
				callProperty: Property,
				calledSeam: TypeDescription,
				callerModule: ModuleIdentity,
				seamModule: ModuleIdentity,
			)
			/// A scope in the fill closes a cycle on `closingProperty`, a property of the seam's path, declared by
			/// `closingType` beneath `fillAncestors`.
			/// `closedOnDeclaration` is the declaration of the seam's path it repeats, and `closesOnOwnerOfHole` says that
			/// declaration builds the type that declares the hole, so a closer under another label would close at the hole.
			case closesCycleInSeamTree(closingProperty: Property, closingType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, fillAncestors: [FillAncestor], closedOnDeclaration: SeamSignature.Hole.DeclaredProperty?, closesOnOwnerOfHole: Bool, seamModule: ModuleIdentity)
			/// The routes to the places of the hole's case, nested by type, hold `label`, which the one fill of the case reads,
			/// as `fields`, whose forms differ in more than optionality: no one parameter takes them all.
			case fieldFormsDifferBetweenPlaces(label: String, fields: [SeamSignature.Hole.Field], seamModule: ModuleIdentity)
		}

		let hole: SeamSignature.Hole
		let kind: Kind

		/// What identifies the finding: its kind and where it is reported.
		var key: String {
			let location = sourceDiagnostics.first?.location.map { "\($0.filePath):\($0.line):\($0.column)" } ?? ""
			return "\(kindName) \(location)"
		}

		/// Whether this finding comes before `other`: by where each of its diagnostics is reported, then where the place it
		/// names is declared, then where each declaration of the path to that place is, then by kind, so which of two findings
		/// of one key is reported, and the order of two at one location, never depends on a name. A seam that builds one type
		/// under two parents reaches one place through two paths that differ only in the declarations along them, so the
		/// path decides between them. Their messages break only a tie between findings that print the same.
		func precedesInSourceOrder(_ other: FillFinding) -> Bool {
			let (diagnostics, otherDiagnostics) = (sourceDiagnostics, other.sourceDiagnostics)
			let (locations, otherLocations) = (orderingLocations, other.orderingLocations)
			guard locations.elementsEqual(otherLocations) else {
				return locations.lexicographicallyPrecedes(otherLocations, by: Dependency.DeclarationLocation.precedesInSourceOrder)
			}
			return kindName == other.kindName ? SourceDiagnostic.precedesInSourceOrder(diagnostics, otherDiagnostics) : kindName < other.kindName
		}

		/// Where each diagnostic of the finding is reported, then where its place and each declaration of the path to that
		/// place are declared.
		private var orderingLocations: [Dependency.DeclarationLocation?] {
			var locations = sourceDiagnostics.map(\.location)
			locations.append(hole.declarationLocation)
			locations.append(contentsOf: hole.declaredSitePath.map(\.declarationLocation))
			return locations
		}

		private var kindName: String {
			switch kind {
			case .fieldNotReadable:
				"fieldNotReadable"
			case .fieldHeldOnlyOptionally:
				"fieldHeldOnlyOptionally"
			case .declarationBoundOnCycleReentry:
				"declarationBoundOnCycleReentry"
			case .declarationBoundAfterSite:
				"declarationBoundAfterSite"
			case .receivesInstantiatorBuildingSite:
				"receivesInstantiatorBuildingSite"
			case .declarationBoundOnPathToReenteringCall:
				"declarationBoundOnPathToReenteringCall"
			case .closesCycleInSeamTree:
				"closesCycleInSeamTree"
			case .fieldFormsDifferBetweenPlaces:
				"fieldFormsDifferBetweenPlaces"
			}
		}

		var sourceDiagnostics: [SourceDiagnostic] {
			// A place in a scope enum is named by its case too, which is what the builder reads.
			func builderDescription(of hole: SeamSignature.Hole, apostrophe: String = "'") -> String {
				builderDescription(of: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole), apostrophe: apostrophe)
			}
			func builderDescription(of place: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace, apostrophe: String = "'") -> String {
				"the builder for `\(place.ownerType.asSource)`\(apostrophe)s `\(place.property.asSource)`\(place.caseName.map { " (case `\($0)` of `\(place.builderLabel)`)" } ?? "")"
			}
			let builder = builderDescription(of: hole)
			let scope = "the scope SafeDI hands \(builder)"
			let seamName = "`\(hole.scopeSeamType.asSource)`"
			func module(_ identity: ModuleIdentity) -> String {
				identity.moduleName.map { "module `\($0)`" } ?? "this module"
			}
			func builderOfDeclaration(_ declaration: SeamSignature.Hole.UncarriedDeclaration) -> String {
				declaration.declaringType == hole.scopeSeamType ? "\(seamName)'s dependency tree" : "`\(declaration.declaringType.asSource)`"
			}
			/// How `seam` binds `declaration` on its path to its call of `calledSeam`.
			func boundOnPathToCall(of declaration: SeamSignature.Hole.UncarriedDeclaration, seam: TypeDescription, calledSeam: TypeDescription) -> String {
				if let parameterTakingType = declaration.parameterTakingType {
					"`\(parameterTakingType.asSource)`'s builder function takes as a parameter on the path where `\(seam.asSource)` calls `\(calledSeam.asSource)`, because a cycle inside `\(parameterTakingType.asSource)`'s tree passes it"
				} else if declaration.declaringType == seam {
					"`\(seam.asSource)` builds where it calls `\(calledSeam.asSource)`"
				} else {
					"`\(declaration.declaringType.asSource)` builds on the path where `\(seam.asSource)` calls `\(calledSeam.asSource)`"
				}
			}
			func fulfillRemedy(_ seamModule: ModuleIdentity) -> String {
				SeamAccessExplanation.fulfillRemedy(fulfilling: hole.instantiatedType, seamModuleName: seamModule.moduleName, effect: nil)
			}
			/// The remedy for a receive in a fill's tree of `declaration`, an instantiator the seam's tree instantiates: a
			/// parameter of the seam is bound before every site, and the seam's caller, which fills the builder, holds it.
			func receiveInstantiatorRemedy(_ declaration: SeamSignature.Hole.UncarriedDeclaration) -> String {
				"instantiate `\(declaration.property.label)` on a type above \(seamName), and receive it on `\(declaration.declaringType.asSource)` in place of its @\(Dependency.Source.instantiatedRawValue) declaration, so that the caller’s tree builds it"
			}
			switch kind {
			case let .fieldNotReadable(reader, field, callerModule, seamModule, requirement):
				let level = "`\(field.access.spelledOnGeneratedDeclaration)`"
				// A caller SafeDI is told no package of may be in the seam's package all the same.
				let packageNameRemedy = ModuleIdentity.packageNameRemedy(emitter: callerModule, declarer: seamModule, requirement: requirement, declaredLevel: field.access)
				let reach = if field.access == .package, let packageName = seamModule.packageName {
					callerModule.packageName == nil
						? "\(module(callerModule)) is not told it is in package `\(packageName)`"
						: "\(module(callerModule)) is not in package `\(packageName)`"
				} else {
					"\(module(callerModule)) is not \(module(seamModule))"
				}
				// How the field's type is proven, and what proves it as widely as the filler needs, as the shared formatter
				// explains a seam parameter's access. A filler is never in the seam's own module, which then has no hole.
				let neededLevel: AccessLevel = requirement == .public ? .public : .package
				let causeText = field.accessCause.map { " " + SeamAccessExplanation.causeSentence($0, receivers: []) } ?? ""
				var remedies = [String]()
				if let packageNameRemedy {
					remedies.append(packageNameRemedy)
				}
				remedies += SeamAccessExplanation.causeRemedies(field.accessCause, neededLevel: neededLevel)
				remedies.append(SeamAccessExplanation.fulfillRemedy(fulfilling: hole.instantiatedType, seamModuleName: seamModule.moduleName, effect: .seamTreeBuildsIt(hole.scopeSeamType)))
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(scope) carries only at \(level) access, and \(reach).\(causeText) \(SeamAccessExplanation.joined(remedies))"),
				] + SeamAccessExplanation.declarationNotes(for: field.accessCause, neededLevel: neededLevel) + [
					SourceDiagnostic(severity: .note, location: field.declarationLocation, message: "`\(field.declaringType.asSource)` declares `\(field.property.asSource)` here."),
				]
			case let .fieldHeldOnlyOptionally(reader, field, seamModule):
				let readerRemedy = "receive it on `\(reader.type.asSource)` with `@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true) let \(field.property.asSource)`"
				// A field is optional where the reader requires it only for a reason the seam adds: a declaration that is
				// optional itself (a forwarded `x: X?`, an optional rename, a pass-through every receiver requires as `x: X?`)
				// leaves no value of the required type above the fill, which the received-property walk reports first. So the
				// seam takes the label only if available, or a builder function a lazy cycle closes on takes it optionally,
				// since no type in its body requires it; inline, the reader would be in that body and make it required.
				let cause = if let parameterTakingType = field.parameterTakingType {
					"since `\(parameterTakingType.asSource)`'s builder function takes it as a parameter, because a cycle inside `\(parameterTakingType.asSource)`'s tree passes it, and no type \(seamName)'s tree builds in that function requires `\(reader.property.asSource)`. \(readerRemedy.prefix(1).uppercased())\(readerRemedy.dropFirst()), or \(fulfillRemedy(seamModule))."
				} else {
					"since \(seamName)'s tree receives it only if available. Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on \(seamName), or \(readerRemedy)."
				}
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(scope) carries only as `\(field.property.asSource)`, \(cause)"),
					SourceDiagnostic(severity: .note, location: field.declarationLocation, message: "`\(field.declaringType.asSource)` receives `\(field.property.asSource)` here."),
				]
			case let .declarationBoundOnCycleReentry(reader, declaration, seamModule):
				let declaringType = "`\(declaration.declaringType.asSource)`"
				let closedOnDeclaringType = "`\(declaration.closedOnDeclaringType.asSource)`"
				let builtType = "`\(declaration.closedOnProperty.typeDescription.asInstantiatedType.asSource)`"
				let between = "between where \(closedOnDeclaringType) instantiates `\(declaration.closedOnProperty.asSource)` and where `\(declaration.reenteringType.asSource)` instantiates it again"
				let declared = if let parameterTakingType = declaration.parameterTakingType {
					"which `\(parameterTakingType.asSource)`'s builder function takes as a parameter \(between), because a cycle inside `\(parameterTakingType.asSource)`'s tree passes it (\(declaringType) declares `\(declaration.property.asSource)`). Inline, the \(builtType) built again receives the `\(declaration.property.label)` that parameter is passed"
				} else {
					"which \(declaringType) declares \(between). Inline, the \(builtType) built again receives \(declaringType)'s `\(declaration.property.label)`"
				}
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, \(declared), but \(scope) holds the same values at every level of that cycle. Give `\(declaration.property.label)` on \(declaringType) another label, or \(fulfillRemedy(seamModule))."),
				] + (declaration.declarationLocation.map { [SourceDiagnostic(severity: .note, location: $0, message: "\(declaringType) declares `\(declaration.property.asSource)` here.")] } ?? [])
			case let .declarationBoundAfterSite(reader, declaration, seamModule):
				// A parameter of a builder function a lazy cycle closes on is declared, as far as the reader is told, by the first
				// type in the function's body that receives it, and an alias by the type that receives it under its label.
				let isAlias = if case .boundOutsideSendableFunction(_, _, _, _, _?) = declaration.reason {
					true
				} else {
					false
				}
				let noteVerb = declaration.parameterTakingType == nil && !isAlias ? "declares" : "receives"
				let declarationNote = SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "`\(declaration.declaringType.asSource)` \(noteVerb) `\(declaration.property.asSource)` here.")
				let pathScope = "`\(declaration.builtAfter?.label ?? "")`"
				// An instantiator the seam's tree builds after the site can be declared above the seam and received.
				var remedies = [String]()
				if ScopeGenerator.isBuilder(declaration.property) {
					remedies.append(receiveInstantiatorRemedy(declaration))
				}
				remedies.append(fulfillRemedy(seamModule))
				// What a message about a place built inside a `@Sendable` function, `functionProperty`'s, says of the scope it is
				// handed, and the remedy every such message ends with when it has no other.
				let sendableScope = "the scope SafeDI hands \(builderDescription(of: hole, apostrophe: "’"))"
				func outside(_ functionProperty: Property) -> String {
					"outside the `@Sendable` function that builds `\(functionProperty.asSource)`, and \(sendableScope) carries only what that function binds."
				}
				let capitalizedFulfillRemedy = "\(fulfillRemedy(seamModule).prefix(1).uppercased())\(fulfillRemedy(seamModule).dropFirst())."
				let message = switch declaration.reason {
				case let .boundByPassingUpSeam(seam, _, place):
					// `seam` binds the label on a path to a call that presents `place`, whose builder it passes up: the place
					// itself, or the place a fill fills, when the reader is beneath a place inside that fill.
					(seam == place.seamType
						? "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(place.seamType.asSource)`'s tree builds where it instantiates `\(place.seamType.asSource)` again, but that call passes the builder `\(place.seamType.asSource)` takes for `\(place.ownerType.asSource)`'s `\(place.property.asSource)` on unchanged, so the caller that fills it cannot hand it those values."
						: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(boundOnPathToCall(of: declaration, seam: seam, calledSeam: place.seamType)), but `\(seam.asSource)` passes \(builderDescription(of: place)) on from its own caller, which cannot hand it \(declaration.declaringType == seam ? "`\(seam.asSource)`'s values" : "that value").")
						+ (place.isBuiltBySendableBuilder
							// A place a `@Sendable` function builds is handed only what that function binds, so no parameter of the
							// place's seam carries the value: its fill reads the caller's own.
							? " Instantiate `\(declaration.property.label)` outside `\(seam.asSource)` and declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on `\(seam.asSource)`, so the builder’s caller reads its own, or \(SeamAccessExplanation.fulfillRemedy(fulfilling: place.instantiatedType, seamModuleName: seamModule.moduleName, effect: .seamFillsBuilder(seam)))."
							: " Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on `\(place.seamType.asSource)`, so the builder’s scope carries it, or \(SeamAccessExplanation.fulfillRemedy(fulfilling: place.instantiatedType, seamModuleName: seamModule.moduleName, effect: .seamFillsBuilder(seam))).")
				case let .receivesPathScopeOnlyIfAvailable(type):
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(builderOfDeclaration(declaration)) builds after \(pathScope), since `\(type.asSource)` receives \(pathScope) only if available, so \(scope) does not carry it. Receive \(pathScope) on `\(type.asSource)` some other way, or \(fulfillRemedy(seamModule))."
				case let .requiresOtherCarrier(type, carrier):
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(builderOfDeclaration(declaration)) builds after \(pathScope), since `\(type.asSource)` requires `\(carrier.label)`, which carries another builder, so \(scope) does not carry it. Declare `\(declaration.property.label)` before \(pathScope) in `\(declaration.declaringType.asSource)`, or \(fulfillRemedy(seamModule))."
				case .other, .instantiatorBuildingSite:
					// The builder is named once, so the sentence that it does not carry the value refers back to it.
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(declaration.declaringType == hole.scopeSeamType ? "\(seamName)’s tree builds only after it calls" : "`\(declaration.declaringType.asSource)` builds only after \(seamName)’s tree calls") \(builderDescription(of: hole, apostrophe: "’")), so that builder’s scope does not carry it. \(SeamAccessExplanation.joined(remedies))"
				case let .boundOutsideSendableFunction(functionProperty, functionBuiltType, isForwarded, cycleParameter, alias):
					// A place built inside a `@Sendable` function is handed only what that function binds, whether the read is
					// required or only if available: a silent `nil` would hand the fill another value than inline's.
					if let cycleParameter {
						// A parameter of a builder function a cycle closes on is the value the cycle passes: only forwarding it
						// into the `@Sendable` function binds it there.
						"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(cycleParameter.takingType.asSource)`’s builder function takes as a parameter outside the `@Sendable` function that builds `\(functionProperty.asSource)`, because a cycle inside `\(cycleParameter.takingType.asSource)`’s tree passes it (`\(cycleParameter.declaringType.asSource)` \(cycleParameter.isForwarded ? "forwards" : "declares") `\(cycleParameter.property.asSource)`), and \(sendableScope) carries only what that function binds. "
							+ (functionBuiltType.map { "Declare `@\(Dependency.Source.forwardedRawValue) let \(cycleParameter.property.asSource)` on `\($0.asSource)` too, so that function binds it, or \(fulfillRemedy(seamModule))." } ?? capitalizedFulfillRemedy)
					} else if let alias {
						// An alias binds the label to another value than the caller's own of that label, which is all a fill reads:
						// the type receives the label without the alias, and the seam's caller hands it the label's value.
						if alias.isSeams {
							"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)` receives as the caller’s `\(alias.fulfillingProperty.label)` \(outside(functionProperty)) Declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on `\(declaration.declaringType.asSource)` without `fulfilledByDependencyNamed: \"\(alias.fulfillingProperty.label)\"`, so the builder’s caller reads its own, or \(fulfillRemedy(seamModule))."
						} else {
							// The alias's type is inside the seam's tree, which binds the property the alias reads: without the alias,
							// the label comes from above the seam only once nothing in its tree declares it.
							"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)` receives as `\(alias.fulfillingProperty.label)` \(outside(functionProperty)) Declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on `\(declaration.declaringType.asSource)` without `fulfilledByDependencyNamed: \"\(alias.fulfillingProperty.label)\"`, and instantiate `\(declaration.property.label)` outside \(seamName), so the builder’s caller reads its own, or \(fulfillRemedy(seamModule))."
						}
					} else {
						"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)` \(isForwarded ? "forwards" : "declares") \(outside(functionProperty)) "
							+ (isForwarded
								? functionBuiltType.map { "Declare `@\(Dependency.Source.forwardedRawValue) let \(declaration.property.asSource)` on `\($0.asSource)` too, so that function binds it, or \(fulfillRemedy(seamModule))." } ?? capitalizedFulfillRemedy
								: "Instantiate `\(declaration.property.label)` outside \(seamName) and declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on \(seamName), so the builder’s caller reads its own, or \(fulfillRemedy(seamModule)).")
					}
				}
				// A parameter of a builder function a cycle closes on is noted where the cycle declares the value it passes.
				let note = if case let .boundOutsideSendableFunction(_, _, _, cycleParameter?, _) = declaration.reason {
					SourceDiagnostic(severity: .note, location: cycleParameter.declarationLocation, message: "`\(cycleParameter.declaringType.asSource)` \(cycleParameter.isForwarded ? "forwards" : "declares") `\(cycleParameter.property.asSource)` here.")
				} else {
					declarationNote
				}
				return [SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: message), note]
			case let .receivesInstantiatorBuildingSite(reader, declaration, seamModule):
				let remedies = [receiveInstantiatorRemedy(declaration), fulfillRemedy(seamModule)]
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(seamName)’s tree is building where it calls \(builderDescription(of: hole, apostrophe: "’")). Inline, `\(reader.type.asSource)` can get an instantiator of its own, made from the function \(seamName)’s initializer declares for `\(declaration.property.label)`, which code generated outside \(module(seamModule)) cannot refer to. \(SeamAccessExplanation.joined(remedies))"),
					SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "`\(declaration.declaringType.asSource)` instantiates `\(declaration.property.asSource)` here."),
				]
			case let .declarationBoundOnPathToReenteringCall(reader, declaration, pathHole, callingType, callProperty, calledSeam, callerModule, seamModule):
				let declaringType = "`\(declaration.declaringType.asSource)`"
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(declaringType) declares on the path from \(builderDescription(of: pathHole)) to the call by which `\(callingType.asSource)` instantiates `\(calledSeam.asSource)` again (`\(callProperty.label)`), but that call passes the builder on as \(module(callerModule)) fills it, which cannot hand it \(declaringType)'s values. Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on \(seamName), so the builder’s scope carries it, or \(fulfillRemedy(seamModule))."),
					SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "\(declaringType) declares `\(declaration.property.asSource)` here."),
				]
			case let .closesCycleInSeamTree(closingProperty, closingType, declarationLocation, fillAncestors, closedOnDeclaration, closesOnOwnerOfHole, seamModule):
				let closingTypeName = "`\(closingType.asSource)`"
				// The type that fills the builder is the fill's root; a closer beneath it is named beneath it.
				let closer = fillAncestors.count > 1 ? "\(closingTypeName), beneath `\(fillAncestors[0].builtType.asSource)`, which fills it," : "\(closingTypeName), which fills it,"
				var chain = [String]()
				for declared in hole.declaredSitePath {
					chain += [declared.declaringType?.asSource, declared.property.label].compactMap(\.self)
				}
				// Each property beneath the fill's root, after the type that builds it: the one its ancestor built.
				for (ancestor, property) in zip(fillAncestors, fillAncestors.dropFirst()) {
					chain += [ancestor.builtType.asSource, property.property.label]
				}
				chain += [closingType.asSource, closingProperty.label]
				// Under another label, the closing property builds the path's type again, inside the fill. Where that type
				// declares the hole, its tree reaches the hole beneath the closer, which is no longer a repeat of the path, and the
				// cycle closes at the hole itself with an instantiator along it (a cycle with none is reported as such before a
				// fill is judged). Where the type is further up, its tree reaches the closer's own property again, on a path the
				// fill's stack now holds, and the rename only moves the same error: re-entering through the initializer is then
				// the one remedy that stops it.
				// The suggested label is the seam's own name, without its enclosing types or generic arguments, which a label
				// cannot spell.
				let seamSpelling = hole.scopeSeamType.strippingGenerics.asSource
				let seamSimpleName = seamSpelling[(seamSpelling.lastIndex(of: ".").map { seamSpelling.index(after: $0) } ?? seamSpelling.startIndex)...]
				var remedies = [
					"instantiate the seam where \(closingTypeName) builds `\(closingProperty.typeDescription.asInstantiatedType.asSource)` (`@Instantiated let \(seamSimpleName.prefix(1).lowercased() + seamSimpleName.dropFirst())Builder: Instantiator<\(hole.scopeSeamType.asSource)>`), so the cycle re-enters through the initializer SafeDI generates for \(seamName)",
					fulfillRemedy(seamModule),
				]
				if closesOnOwnerOfHole {
					remedies.append("give `\(closingProperty.label)` on \(closingTypeName) another label, so the cycle closes at `\(hole.property.label)` itself")
				}
				return [
					SourceDiagnostic(severity: .error, location: declarationLocation, message: "SafeDI cannot fill \(builder) in \(seamName)'s dependency tree: \(closer) instantiates `\(closingProperty.asSource)`, which \(seamName)'s tree is building where it builds `\(hole.property.label)` (\(chain.joined(separator: " -> "))). Code generated outside \(module(seamModule)) cannot refer to the function \(seamName)'s initializer builds `\(closingProperty.typeDescription.asInstantiatedType.asSource)` with, and building it again would hand it other values than \(seamName)'s tree holds. \(SeamAccessExplanation.joined(remedies))"),
				] + (closedOnDeclaration.map { [SourceDiagnostic(severity: .note, location: $0.declarationLocation, message: "`\($0.declaringType?.asSource ?? "")` instantiates `\($0.property.asSource)` here.")] } ?? [])
			case let .fieldFormsDifferBetweenPlaces(label, fields, seamModule):
				let forms = fields.map { "`\($0.property.asSource)` (`\($0.declaringType.asSource)`)" }
				let formList = forms.count > 2 ? forms.dropLast().joined(separator: ", ") + ", and " + (forms.last ?? "") : forms.joined(separator: " and ")
				let firstForm = fields.first.map { "`\($0.property.asSource)`" } ?? "`\(label)`"
				return [
					SourceDiagnostic(severity: .error, location: fields.first?.declarationLocation, message: "SafeDI fills every place of \(builder) with one function, which reads `\(label)`, but the types on the routes to those places declare it in forms one value cannot carry: \(formList). Declare \(firstForm) on each, or \(fulfillRemedy(seamModule))."),
				] + fields.dropFirst().map { field in
					SourceDiagnostic(severity: .note, location: field.declarationLocation, message: "`\(field.declaringType.asSource)` declares `\(field.property.asSource)` here.")
				}
			}
		}
	}
}

extension SeamSignature.Hole.UncarriedDeclaration {
	/// This declaration, bound after the site for `reason`.
	func with(reason: Reason) -> SeamSignature.Hole.UncarriedDeclaration {
		SeamSignature.Hole.UncarriedDeclaration(property: property, declaringType: declaringType, declarationLocation: declarationLocation, parameterTakingType: parameterTakingType, builtAfter: builtAfter, reason: reason)
	}
}

extension SeamSignature.Hole {
	/// This hole with `declarations` among the declarations a fill cannot read.
	func addingUncarriedDeclarations(_ declarations: [UncarriedDeclaration], isSendable: Bool) -> SeamSignature.Hole {
		var hole = self
		hole.uncarriedDeclarations += declarations
		hole.isSendable = isSendable
		return hole
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError {
	/// What a target the Xcode project plugin builds does for SafeDI to know its modules, in both errors that a run that
	/// names no module reports about a seam, so the two read alike. A sentence of its own, beside one for a run by hand.
	static let xcodeProjectPluginCannotNameModules = "Under the Xcode project plugin, which cannot name modules, move the modules and the root into a local Swift package that the app target depends on."

	/// What `package` access needs where SafeDI cannot tell whether two modules are in one package, which happens only in
	/// a run that names no module or no package: under the Xcode project plugin, which passes no `-package-name`, or in
	/// a run by hand. A clause that follows the suggestion to make a declaration `package`.
	static let unverifiedPackageAccessNeed = "which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project)"

	/// A hole in the tree of a seam whose module SafeDI does not know – a run without a module name, as a target the
	/// Xcode project plugin builds is – so the initializer it generates cannot take a builder: what the module's callers
	/// see is unknown, and they build the seam inline. The message leads with the remedies every such run can apply, and
	/// then says how SafeDI comes to know the module, under the Xcode project plugin and in a run by hand, the only runs
	/// that name no module. It never suggests reading a module that depends on this one, whose files the generated code
	/// could not see.
	struct HoleInSeamOfUnnamedModule {
		let seam: TypeDescription
		let owner: TypeDescription
		let dependency: Dependency

		var sourceDiagnostic: SourceDiagnostic {
			let seamName = "`\(seam.asSource)`"
			let typeName = "`\(dependency.asInstantiatedType.asSource)`"
			let label = "`\(dependency.property.label)`"
			return SourceDiagnostic(
				severity: .error,
				location: dependency.declarationLocation,
				message: "\(seamName) generates its dependency tree, and `\(owner.asSource)`’s @\(Dependency.Source.instantiatedRawValue) property `\(dependency.property.asSource)` in it instantiates \(typeName), which no @\(InstantiableVisitor.macroName) declaration this module reads fulfills. SafeDI does not know which module declares \(seamName), so it cannot know what that module’s callers see, and the initializer it generates cannot take a builder for \(label). Declare an @\(InstantiableVisitor.macroName) type that fulfills \(typeName) in this module or in a module it depends on, or declare \(seamName) without `generateDependencyTree: true`. For the initializer to take a builder instead, SafeDI must know \(seamName)’s module. \(DependencyTreeGenerator.DependencyTreeGeneratorError.xcodeProjectPluginCannotNameModules) A SafeDITool run by hand names this module with `--module-name`.",
			)
		}
	}
}
