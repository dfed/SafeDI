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
	/// field, and hide the farther declarations of their label, which Swift would bind instead. In a public mock's tree
	/// (`bindsReceivesAgain`), a receive the mock binds again (`mockBindsAgain(receiving:beneath:)`) is a declaration of the
	/// scope that makes it, bound before its children, and `parameters` are the mock's root level
	/// (`PublicMockRootLevel`), whose `namesApartAtRoot` no level declares and whose `receiversByParameter` are the declarations
	/// that receive each parameter's own form (`PublicMockRootLevel.receiversByField`).
	static func holes(
		of seam: Instantiable,
		generator: ScopeGenerator,
		bindsReceivesAgain: Bool = false,
		namesApartAtRoot: PublicMockRootLevel.NamesApart = .init(),
		parameters: [SeamSignature.Parameter],
		receiversByParameter: [Property: [SeamSignature.Receiver]] = [:],
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
	) -> HolesAndPlaces {
		guard generator.containsBuildSite || generator.passesUpBuilder else { return HolesAndPlaces() }
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		let sites = buildSites(in: generator)
		let seamModule = ModuleIdentity(moduleName: seam.moduleName, packageName: seam.packageName)
		// What the calls inside the fills of each seam call on a place's path hide from those fills, by the call's identity.
		var hiddenByCall = [ObjectIdentifier: [String: FillReentryHidings]]()
		// The place graph rides on the levels' observer, which hands it on at the end, so the tests set no task-local value of
		// their own around `generate()` (`serialization.md`: one more made the tests' release build abort on Linux).
		let draftsPlaceLevels = SeamPlaceLevels.observer != nil
		let (passedUpHoles, ownSiteAdditions, callPresentations) = holesPassedUp(in: generator, seamType: seam.concreteInstantiable, seamModule: seamModule, ownSitePaths: sites.map(\.sitePath), hiddenByCall: &hiddenByCall, draftsPlaceLevels: draftsPlaceLevels)

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
			let declarationsHiddenByFields: [SeamSignature.Hole.DeclarationHiddenByField]
			/// The site's levels as the place graph holds them, root first, while a test observes the graph.
			let placeLevels: [SeamPlacesBuilder.LevelDraft]
			let isBuiltInSendableFunction: Bool
		}
		// Places are drafted into the place graph, which the signature holds beside the per-site holes, only while a test
		// observes it: drafting per site costs a seam with a place on every screen as much as the rest of its generation, and
		// nothing outside the tests reads the graph until the builder that walks the seam's tree once replaces this walk.
		var declarationsBetweenByClosedOnScope = [ObjectIdentifier: [DeclarationBetween]]()
		var placesByTreePath = [[Property]: [SeamSignature.Hole.Site]]()
		var dependenciesByGenerator = [ObjectIdentifier: DependenciesByProperty]()
		var childDeclarationsByGenerator = [ObjectIdentifier: ChildDeclarations]()
		let seamDependencies = DependenciesByProperty(of: seam)
		let siteContents = sites.compactMap { site -> SiteContent? in
			guard let owner = site.frames.last?.generator.builtInstantiable else { return nil }
			let content = fields(
				of: site,
				seam: seam,
				bindsReceivesAgain: bindsReceivesAgain,
				namesApartAtRoot: namesApartAtRoot,
				parameters: parameters,
				receiversByParameter: receiversByParameter,
				seamTypeAccess: seamTypeAccess,
				proof: proof,
				instantiables: instantiables,
				declarationsBetweenByClosedOnScope: &declarationsBetweenByClosedOnScope,
				placesByTreePath: &placesByTreePath,
				seamDependencies: seamDependencies,
				dependenciesByGenerator: &dependenciesByGenerator,
				childDeclarationsByGenerator: &childDeclarationsByGenerator,
				draftsPlaceLevels: draftsPlaceLevels,
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
				declarationsHiddenByFields: content.declarationsHiddenByFields,
				placeLevels: content.placeLevels,
				isBuiltInSendableFunction: content.isBuiltInSendableFunction,
			)
		}
		// The levels of each place, beside its fields, for the tests and the graph fuzzer: generated code reads none yet.
		var observedPlaceLevels: SeamPlaceLevels?
		if draftsPlaceLevels {
			observedPlaceLevels = SeamPlaceLevels(
				seamType: seam.concreteInstantiable,
				places: siteContents.map { content in
					var place = SeamPlaceLevels.Place(
						sitePath: content.site.sitePath,
						levels: content.levels,
						fields: content.pathFields,
						uncarriedProperties: content.pathUncarriedProperties,
					)
					place.carriedFields = content.fields.map(\.property)
					place.carriedUncarriedProperties = content.uncarriedDeclarations.map(\.property)
					place.siteOpensSendableFunction = content.site.property.propertyType.isSendable
					place.carriedCycleReentryProperties = content.cycleReentryDeclarations.map(\.property)
					place.carriedHiddenByFieldProperties = content.declarationsHiddenByFields.map(\.property)
					place.carriedStack = content.site.fillPropertyStack
					place.carriedStackConcreteTypes = content.site.fillConcreteTypeStack
					return place
				},
			)
		}

		// Names. A builder is labeled `<label>Builder`; holes whose labels collide with one another or with a parameter
		// are named apart by their owner, their declared type simplified, their declared type, and their site path, a
		// parameter keeping its label. A hole a call passes up starts from the label the seam that declares it gives it,
		// its own root enum's builder for the hole's type and family, never the label a seam that passes it up in turn
		// gave it, which that seam named apart from its own holes: around a ring of seams whose signatures settle
		// together, such a label carried each seam's names into the next, and changed on every pass. A scope struct is named after the owner and the property, with the site path
		// appended for a property built at several sites, and an underscore appended while it equals an earlier one.
		struct Candidate {
			let label: String
			let suffixTypes: [TypeDescription]
		}
		let (passedUpNamingCandidates, namingCandidateByPassedUpHole) = Self.namingCandidates(amongPassedUpHoles: passedUpHoles.map(\.hole))
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
		} + passedUpNamingCandidates.map { passedUpIndex in
			let passedUp = passedUpHoles[passedUpIndex]
			return Candidate(
				label: passedUp.declaringSeamLabel,
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
		let collidingIndexSet = Set(collidingIndices)
		let keptLabels = Set(candidates.indices.filter { !collidingIndexSet.contains($0) }.map { candidates[$0].label })
		let collidingNames = ScopeGenerator.identifierSafeNames(
			for: collidingIndices.map { (label: candidates[$0].label, suffixTypes: candidates[$0].suffixTypes) },
			reservedNames: parameterLabels.union(keptLabels),
			countingWorkAs: .namingEntriesApart,
		)
		for (index, name) in zip(collidingIndices, collidingNames) {
			builderLabels[index] = name
		}
		// A builder's name inside the initializer is renamed while a property of the tree would have a builder function of that
		// name, which would shadow it. Nor may it equal a deferred parameter's name, which the parameters take first, or a name
		// another builder binds.
		let builderFunctionNames = builderFunctionNamesOfProperties(in: generator).union(parameters.filter(\.isDeferred).map(\.internalName))
		let unrenamedBuilderNames = Set(builderLabels.map(ScopeGenerator.functionName(toBuildPropertyNamed:)))
		var namesBoundByEarlierBuilders = Set<String>()
		func internalName(ofBuilderLabeled builderLabel: String) -> String {
			let unrenamedName = ScopeGenerator.functionName(toBuildPropertyNamed: builderLabel)
			// The names are released before this builder's is inserted, which would copy the set they share otherwise.
			let name: String = {
				// Each name is asked of each set, never of their union: a union made for every builder holds every builder's
				// name, so naming the builders grew with the square of the seam's places.
				let reservedNames = GenerationWork.taking(
					NamesConsultedInTurn([builderFunctionNames, namesBoundByEarlierBuilders, unrenamedBuilderNames], exceptFromTheLast: unrenamedName),
					by: .namingSeamBuilders,
				)
				var name = unrenamedName
				while reservedNames.contains(name) {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				return name
			}()
			namesBoundByEarlierBuilders.insert(name)
			return name
		}
		var siteCountByProperty = [OwnedProperty: Int]()
		for content in siteContents {
			siteCountByProperty[OwnedProperty(owner: content.owner.concreteInstantiable, property: content.site.property), default: 0] += 1
		}
		var scopeTypeNames = Set<String>()
		var holes = [SeamSignature.Hole]()
		// While a test observes the place graph: the graph, and each hole's case and route, beside `holes`.
		var placesBuilder = SeamPlacesBuilder()
		var caseIndexByHole = [Int]()
		var routeByHole = [SeamSignature.Places.Route]()
		// While a test observes the place graph, the graph one walk of the tree builds, which must equal it; each site’s presentation
		// is added to both.
		var walkedOnce = draftsPlaceLevels ? placesWalkingTreeOnce(
			of: seam,
			generator: generator,
			bindsReceivesAgain: bindsReceivesAgain,
			namesApartAtRoot: namesApartAtRoot,
			parameters: parameters,
			receiversByParameter: receiversByParameter,
			seamTypeAccess: seamTypeAccess,
			proof: proof,
			instantiables: instantiables,
		) : nil
		var walkedSiteBySite = [SeamSignature.Hole.Site: WalkedSite]()
		for walkedSite in walkedOnce?.sites ?? [] {
			walkedSiteBySite[walkedSite.site] = walkedSite
		}
		var walkedCaseIndexByHole = [Int]()
		var walkedRouteByHole = [SeamSignature.Places.Route]()
		for (index, content) in siteContents.enumerated() {
			let property = content.site.property
			var scopeTypeName = "\(ReservedName.seamScopeTypeNamePrefix)\(content.owner.concreteInstantiable.asIdentifier)_\(property.label)".spelledAsJoinedIdentifier
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
			let insideFills = unreadableInsideFills(fillContexts(of: content.site, hiddenByCall: &hiddenByCall), placeFields: [], fillingModule: seamModule)
			var hole = additions.presenting(siteHole)
			hole = hole.addingUncarriedDeclarations(insideFills.calledCopyDeclarations.filter { declaration in !hole.uncarriedDeclarations.contains { $0.property.label == declaration.property.label } }, isSendable: hole.isSendable)
			hole.reenteringCallDeclarations = Self.adding(additions.reenteringCallDeclarations, to: insideFills.reenteringCallDeclarations)
			hole.reenteringPlaceFields = Self.adding(additions.reenteringPlaceFields, to: insideFills.reenteringPlaceFields)
			hole.declarationsHiddenByFields = content.declarationsHiddenByFields
			if draftsPlaceLevels {
				let (caseIndex, route) = placesBuilder.addSite(
					content.site.site(of: seam.concreteInstantiable),
					levels: content.placeLevels,
					isBuiltInSendableFunction: content.isBuiltInSendableFunction,
					siteOpensSendableFunction: property.propertyType.isSendable,
				)
				// The uncarried declarations the presentation appends after the place's own, and those it puts in place of one the
				// place's own list holds: a declaration bound from the caller's argument that a path to a call binds otherwise.
				let ownCount = content.uncarriedDeclarations.count
				let calledCopyDeclarations = Array(hole.uncarriedDeclarations.dropFirst(ownCount))
				let uncarriedReplacedOnPathsToCalls = zip(content.uncarriedDeclarations, hole.uncarriedDeclarations.prefix(ownCount)).compactMap { own, presented in
					own.isBoundFromCallersArgument && presented != own ? presented : nil
				}
				placesBuilder.addPresentation(
					ofCase: caseIndex,
					isPassedOnSendable: hole.isSendable,
					calledCopyDeclarations: calledCopyDeclarations,
					uncarriedReplacedOnPathsToCalls: uncarriedReplacedOnPathsToCalls,
					reenteringCallDeclarations: hole.reenteringCallDeclarations,
					reenteringPlaceFields: hole.reenteringPlaceFields,
					access: SeamSignature.Places.Case.Access(level: hole.tierAccess, cause: hole.accessCause),
				)
				caseIndexByHole.append(caseIndex)
				routeByHole.append(route)
				let walkedSite = walkedSiteBySite[content.site.site(of: seam.concreteInstantiable)]
				let walkedCaseIndex = walkedSite?.caseIndex ?? -1
				if walkedCaseIndex >= 0 {
					walkedOnce?.builder.addPresentation(
						ofCase: walkedCaseIndex,
						isPassedOnSendable: hole.isSendable,
						calledCopyDeclarations: calledCopyDeclarations,
						uncarriedReplacedOnPathsToCalls: uncarriedReplacedOnPathsToCalls,
						reenteringCallDeclarations: hole.reenteringCallDeclarations,
						reenteringPlaceFields: hole.reenteringPlaceFields,
						access: SeamSignature.Places.Case.Access(level: hole.tierAccess, cause: hole.accessCause),
					)
				}
				walkedCaseIndexByHole.append(walkedCaseIndex)
				walkedRouteByHole.append(walkedSite?.route ?? SeamSignature.Places.Route(levels: []))
			}
			holes.append(hole)
		}
		// The access of the builder this seam takes for a place a call presents, `inner`, and what proves it: the builder's
		// type names the inner seam's scope struct, as visible as that seam's type, and the property's type, which this
		// seam's declarations prove again, its owner's module among those admitted. A fact of the place, the same for every
		// call that presents it, so the case of each such call and the seam's hole of the place take one access.
		func accessOfBuilder(passingUp inner: SeamSignature.Hole) -> SeamSignature.Places.Case.Access {
			let builderAccess = proof.access(
				ofParameterTyped: .closure(arguments: [inner.scopeSeamType], isAsync: false, doesThrow: false, returnType: inner.property.typeDescription),
				mentionedFrom: .declaration(seam),
				admittedModules: Set([seam.moduleName, instantiables[inner.ownerType]?.moduleName]),
			)
			return SeamSignature.Places.Case.Access(level: min(builderAccess.level, seamTypeAccess), cause: builderAccess.cause)
		}
		// While a test observes the place graph: a case for each call that presents places and each case of the called seam's
		// it presents, owned by the level that declares the call, which the same pass drafts that drafts a site's levels.
		var passedUpCaseBySite = [SeamSignature.Hole.Site: (caseIndex: Int, route: SeamSignature.Places.Route)]()
		var laterRoutesOfPassedUpCases = [(caseIndex: Int, route: SeamSignature.Places.Route)]()
		// The one walk adds the same calls' cases, in the same order.
		var walkedPassedUpCaseBySite = [SeamSignature.Hole.Site: (caseIndex: Int, route: SeamSignature.Places.Route)]()
		let walkedCalls = walkedOnce?.calls ?? []
		for (callIndex, presentation) in callPresentations.enumerated() {
			let walkedCall = callIndex < walkedCalls.count ? walkedCalls[callIndex] : nil
			// A scope on the path to a call can be shared between paths, so what it declares is found for each call.
			var childDeclarationsOnPathToCall = [ObjectIdentifier: ChildDeclarations]()
			var levels = fields(
				of: BuildSite(frames: presentation.frames, property: presentation.callProperty, erasedToConcreteExistential: false, fillPropertyStack: [], fillConcreteTypeStack: []),
				seam: seam,
				bindsReceivesAgain: bindsReceivesAgain,
				namesApartAtRoot: namesApartAtRoot,
				parameters: parameters,
				receiversByParameter: receiversByParameter,
				seamTypeAccess: seamTypeAccess,
				proof: proof,
				instantiables: instantiables,
				declarationsBetweenByClosedOnScope: &declarationsBetweenByClosedOnScope,
				placesByTreePath: &placesByTreePath,
				seamDependencies: seamDependencies,
				dependenciesByGenerator: &dependenciesByGenerator,
				childDeclarationsByGenerator: &childDeclarationsOnPathToCall,
				draftsPlaceLevels: true,
			).placeLevels
			// The call's own level, which declares nothing: the called seam's root stands beneath it.
			var opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			if presentation.opensSendableFunction {
				let function = sendableFunction(openedBy: presentation.callProperty, building: presentation.innerSeamType)
				opensSendableFunction = SeamSignature.Places.SendableFunctionOpened(property: presentation.callProperty, function: function)
			}
			levels.append(SeamPlacesBuilder.LevelDraft(
				key: SeamSignature.Places.LevelKey(builtType: presentation.innerSeamType, nextProperty: nil, isSeamRoot: false, isInFill: levels.last?.key.isInFill ?? false, filledType: nil),
				declarations: [],
				opensSendableFunction: opensSendableFunction,
				fillBaseStack: [],
				fillOwnerType: nil,
				pathSegment: [presentation.callProperty],
				pathTypes: presentation.pathTypes,
				declaredSegment: presentation.declaredSegment,
				nextPosition: nil,
				nextLoop: nil,
			))
			for place in presentation.places {
				let (caseIndex, route) = placesBuilder.addPassedUpPlace(
					place.hole.site,
					levels: levels,
					reference: SeamSignature.Places.CalledCase(
						seamType: presentation.innerSeamType,
						isPublicMock: presentation.innerIsPublicMock,
						caseIndex: place.innerCaseIndex,
					),
					isBuiltInSendableFunction: presentation.isInSendableFunction,
					siteOpensSendableFunction: presentation.opensSendableFunction,
				)
				placesBuilder.addPresentation(
					ofCase: caseIndex,
					isPassedOnSendable: presentation.isInSendableFunction,
					calledCopyDeclarations: place.calledCopyDeclarations,
					uncarriedReplacedOnPathsToCalls: [],
					reenteringCallDeclarations: place.reenteringCallDeclarations,
					reenteringPlaceFields: place.reenteringPlaceFields,
					access: accessOfBuilder(passingUp: place.hole),
				)
				// The per-site hole of a place several calls present is the first call's; the later calls' routes are kept for the
				// checks that evaluate a case route by route.
				if passedUpCaseBySite[place.hole.site] == nil {
					passedUpCaseBySite[place.hole.site] = (caseIndex, route)
				} else {
					laterRoutesOfPassedUpCases.append((caseIndex, route))
				}
			}
			for (place, walkedCaseIndex) in zip(presentation.places, walkedCall?.caseIndices ?? []) {
				walkedOnce?.builder.addPresentation(
					ofCase: walkedCaseIndex,
					isPassedOnSendable: presentation.isInSendableFunction,
					calledCopyDeclarations: place.calledCopyDeclarations,
					uncarriedReplacedOnPathsToCalls: [],
					reenteringCallDeclarations: place.reenteringCallDeclarations,
					reenteringPlaceFields: place.reenteringPlaceFields,
					access: accessOfBuilder(passingUp: place.hole),
				)
				if let walkedCall, walkedPassedUpCaseBySite[place.hole.site] == nil {
					walkedPassedUpCaseBySite[place.hole.site] = (walkedCaseIndex, walkedCall.route)
				}
			}
		}
		for (offset, passedUp) in passedUpHoles.enumerated() {
			let builderLabel = builderLabels[siteContents.count + namingCandidateByPassedUpHole[offset]]
			let inner = passedUp.hole
			let builderAccess = accessOfBuilder(passingUp: inner)
			var passedUpHole = SeamSignature.Hole(
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
				tierAccess: builderAccess.level,
				accessCause: builderAccess.cause,
				uncarriedDeclarations: inner.uncarriedDeclarations,
				cycleReentryDeclarations: inner.cycleReentryDeclarations,
				innerSeamType: passedUp.innerSeamType,
				passedUpRoute: passedUp.route + inner.passedUpRoute,
				isSendable: inner.isSendable,
				enumPlace: inner.enumPlace,
			)
			// The copy keeps every declaration of every call that presents the place.
			passedUpHole.reenteringCallDeclarations = inner.reenteringCallDeclarations
			passedUpHole.reenteringPlaceFields = inner.reenteringPlaceFields
			passedUpHole.declarationsHiddenByFields = inner.declarationsHiddenByFields
			holes.append(passedUpHole)
			if draftsPlaceLevels {
				// The case of the first call that presents the place, and the route to that call.
				let passedUpCase = passedUpCaseBySite[inner.site]
				caseIndexByHole.append(passedUpCase?.caseIndex ?? -1)
				routeByHole.append(passedUpCase?.route ?? SeamSignature.Places.Route(levels: []))
				let walkedPassedUpCase = walkedPassedUpCaseBySite[inner.site]
				walkedCaseIndexByHole.append(walkedPassedUpCase?.caseIndex ?? -1)
				walkedRouteByHole.append(walkedPassedUpCase?.route ?? SeamSignature.Places.Route(levels: []))
			}
		}
		let order = holes.indices.sorted { holes[$0].builderLabel < holes[$1].builderLabel }
		let sortedHoles = order.map { holes[$0] }
		guard draftsPlaceLevels else { return HolesAndPlaces(holes: sortedHoles) }
		// The paths to the calls that close cycles, after every place's and call's: where a cycle re-enters a scope is a fact
		// of the route, which the graph's query reads from these levels.
		placesBuilder.beginClosingCalls()
		for (closingSite, closesOn) in closingCallSites(in: generator) {
			var childDeclarationsOnPathToCall = [ObjectIdentifier: ChildDeclarations]()
			var levels = fields(
				of: closingSite,
				seam: seam,
				bindsReceivesAgain: bindsReceivesAgain,
				namesApartAtRoot: namesApartAtRoot,
				parameters: parameters,
				receiversByParameter: receiversByParameter,
				seamTypeAccess: seamTypeAccess,
				proof: proof,
				instantiables: instantiables,
				declarationsBetweenByClosedOnScope: &declarationsBetweenByClosedOnScope,
				placesByTreePath: &placesByTreePath,
				seamDependencies: seamDependencies,
				dependenciesByGenerator: &dependenciesByGenerator,
				childDeclarationsByGenerator: &childDeclarationsOnPathToCall,
				draftsPlaceLevels: true,
			).placeLevels
			levels[levels.count - 1].closesOn = closesOn
			placesBuilder.addClosingCall(levels: levels)
		}
		// Each case is named by its first place in builder-label order, as each place was named when a seam held a hole per site.
		var namingRouteByCase = [Int: [Int]]()
		for index in order where caseIndexByHole[index] >= 0 && namingRouteByCase[caseIndexByHole[index]] == nil {
			namingRouteByCase[caseIndexByHole[index]] = routeByHole[index].levels
		}
		let places = placesBuilder.places(namingRouteByCase: namingRouteByCase)
		// The graphs of the seams the calls on the places' paths fill places of, which a fill level's case refers into, after the
		// graphs of the calls that present places, once per seam.
		var calledPlaces = callPresentations.map { SeamSignature.Places.Observation.CalledPlaces(seamType: $0.innerSeamType, isPublicMock: $0.innerIsPublicMock, called: $0.innerCalled, placesOfSeamsBeneath: $0.placesOfSeamsBeneath) }
		for site in sites {
			for frame in site.frames {
				guard let calledBuilders = frame.generator.calledBuilders, let seamType = frame.generator.builtInstantiable?.concreteInstantiable else { continue }
				let isPublicMock = frame.generator.publicMockCall != nil
				guard !calledPlaces.contains(where: { $0.seamType == seamType && $0.isPublicMock == isPublicMock }) else { continue }
				calledPlaces.append(SeamSignature.Places.Observation.CalledPlaces(seamType: seamType, isPublicMock: isPublicMock, called: calledBuilders.called, placesOfSeamsBeneath: calledBuilders.placesOfSeamsBeneath))
			}
		}
		// The place graph rides on the levels' observer, which the caller hands on once the routes are computed, so the tests set
		// no task-local value of their own around `generate()` (`serialization.md`: one more made the tests' release build abort
		// on Linux).
		observedPlaceLevels?.placesObservation = SeamSignature.Places.Observation(
			seamType: seam.concreteInstantiable,
			places: places,
			siteHoles: sortedHoles,
			caseIndexBySite: order.map { caseIndexByHole[$0] },
			routeBySite: order.map { routeByHole[$0] },
			laterRoutesOfPassedUpCases: laterRoutesOfPassedUpCases,
			calledPlaces: calledPlaces,
			walkedOnce: walkedOnce.map { walkedOnce in
				// Named as the fed graph names its cases: by the first place of each in builder-label order.
				var walkedNamingRouteByCase = [Int: [Int]]()
				for index in order where walkedCaseIndexByHole[index] >= 0 && walkedNamingRouteByCase[walkedCaseIndexByHole[index]] == nil {
					walkedNamingRouteByCase[walkedCaseIndexByHole[index]] = walkedRouteByHole[index].levels
				}
				return SeamSignature.Places.Observation.WalkedOnce(
					places: walkedOnce.builder.places(namingRouteByCase: walkedNamingRouteByCase),
					sitePaths: walkedOnce.sites.map(\.site.path),
					caseIndexBySite: order.map { walkedCaseIndexByHole[$0] },
					routeBySite: order.map { walkedRouteByHole[$0] },
				)
			},
		)
		var caseIndexBySite = [SeamSignature.Hole.Site: Int]()
		for (hole, caseIndex) in zip(holes, caseIndexByHole) where caseIndex >= 0 {
			caseIndexBySite[hole.site] = caseIndex
		}
		return HolesAndPlaces(holes: sortedHoles, places: places, caseIndexBySite: caseIndexBySite, observedPlaceLevels: observedPlaceLevels)
	}

	/// A seam's or a public mock's places: one hole per site, in builder-label order, and the place graph by case beside them,
	/// with each own site's case. A place a call passes up has no case yet.
	struct HolesAndPlaces {
		var holes = [SeamSignature.Hole]()
		var places = SeamSignature.Places(levels: [], cases: [])
		var caseIndexBySite = [SeamSignature.Hole.Site: Int]()
		/// What the tests observe of the places, while they observe them (`SeamPlaceLevels.observer`), which the caller hands
		/// on with the routes its builders compute (`handOnObservedPlaceLevels(with:)`).
		var observedPlaceLevels: SeamPlaceLevels?

		/// The case of each of `holes`, or `-1` for a place a call passes up.
		func caseIndices(of holes: [SeamSignature.Hole]) -> [Int] {
			holes.map { caseIndexBySite[$0.site] ?? -1 }
		}

		/// Hands what the tests observe of the places on to them, with each route `builders` computed beside its steps by edge.
		func handOnObservedPlaceLevels(with builders: ShapedBuilders) {
			guard var observedPlaceLevels else { return }
			observedPlaceLevels.routeSteps = builders.routeStepObservations
			SeamPlaceLevels.observer?(observedPlaceLevels)
		}
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

		/// The site in the tree of `seamType`.
		func site(of seamType: TypeDescription) -> SeamSignature.Hole.Site {
			SeamSignature.Hole.Site(seamType: seamType, path: sitePath)
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
	static func declaredProperties(reaching generator: ScopeGenerator, from parent: ScopeGenerator?) -> [SeamSignature.Hole.DeclaredProperty] {
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

	/// The calls in the tree `generator` roots that close a cycle on a scope on their path, in the order the generated code
	/// makes them, each as a site at the scope that makes it with the entry it closes on, found by walking only the subtrees
	/// that hold a cycle-closing scope.
	private static func closingCallSites(in generator: ScopeGenerator) -> [(site: BuildSite, closesOn: SeamSignature.Places.StackEntry)] {
		var sites = [(site: BuildSite, closesOn: SeamSignature.Places.StackEntry)]()
		var frames = [PathFrame(generator: generator, orderedChildren: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []), nextPosition: 0)]
		while let frame = frames.last {
			guard frame.nextPosition < frame.orderedChildren.count else {
				frames.removeLast()
				continue
			}
			frames[frames.count - 1].nextPosition += 1
			let child = frame.orderedChildren[frame.nextPosition]
			guard child.generator.holdsCycleClosingScope, child.generator.fillEmitsCode else { continue }
			if child.generator.closesPropertyCycle, let declaration = child.generator.closedOnDeclaration, let property = child.generator.property {
				// A call that closes on a scope above the seam's tree, or above a fill's, re-enters no level of this graph.
				if frames.contains(where: { $0.generator.declaration == declaration }) {
					sites.append((
						BuildSite(frames: frames, property: property, erasedToConcreteExistential: false, fillPropertyStack: [], fillConcreteTypeStack: []),
						SeamSignature.Places.StackEntry(property: declaration.property, concreteType: declaration.concreteType),
					))
				}
			} else {
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

	/// The `@Sendable` function a scope built as `property`, of the type `builtType`, opens: a level of a seam's own tree,
	/// or a call that presents the places of the seam it builds.
	private static func sendableFunction(openedBy property: Property, building builtType: TypeDescription) -> SeamSignature.Hole.UncarriedDeclaration.SendableFunction {
		if ScopeGenerator.isBuilder(property) {
			.instantiator(builtType: builtType)
		} else if case .sendableLazilyInstantiated = property.propertyType {
			.sendableLazyWrapper(builtType: builtType)
		} else {
			.other
		}
	}

	/// The passed-up holes that name this seam's builders for the places it passes up, as indices into `passedUpHoles`, and,
	/// by each passed-up hole, the index among those candidates of the one whose name its builder takes.
	///
	/// One candidate per case of the called seam, the first hole of each case (`ScopeGenerator.fillCaseKey(of:)`), so a
	/// label is named apart only from builders of other cases, whatever number of places the called seam hands, and a run
	/// that is handed one place per case names as one handed every place (lead's ruling, 2026-11-27: a label per case; no
	/// label a person writes moves, only the text of errors that name a builder). 2.4.1 names apart one candidate per place:
	/// that body returns every index for both lists. A swap is an edit of this function alone.
	private static func namingCandidates(amongPassedUpHoles passedUpHoles: [SeamSignature.Hole]) -> (candidates: [Int], candidateByHole: [Int]) {
		var candidates = [Int]()
		var candidateByCaseKey = [String: Int]()
		var candidateByHole = [Int]()
		for (index, hole) in passedUpHoles.enumerated() {
			guard hole.enumPlace != nil else {
				candidateByHole.append(candidates.count)
				candidates.append(index)
				continue
			}
			let caseKey = ScopeGenerator.fillCaseKey(of: hole)
			if let candidate = candidateByCaseKey[caseKey] {
				candidateByHole.append(candidate)
			} else {
				candidateByCaseKey[caseKey] = candidates.count
				candidateByHole.append(candidates.count)
				candidates.append(index)
			}
		}
		return (candidates, candidateByHole)
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
	/// root to the call that presented it first. Every presented copy's re-entering call declarations and re-entering place
	/// fields are kept, and those of
	/// each fill of the tree a call that presents the site is made inside of (`unreadableInsideFills(_:placeFields:fillingModule:)`), with what the copies of those fills' holes leave uncarried.
	/// - Parameter hiddenByCall: What the calls inside the fills of each seam call hide from those fills, by the call's
	///   identity, filled as the walk asks.
	private static func holesPassedUp(
		in generator: ScopeGenerator,
		seamType: TypeDescription,
		seamModule: ModuleIdentity,
		ownSitePaths: [[Property]],
		hiddenByCall: inout [ObjectIdentifier: [String: FillReentryHidings]],
		draftsPlaceLevels: Bool = false,
	) -> (passedUpHoles: [(innerSeamType: TypeDescription, typesToCall: [SeamSignature.Hole.PathType], route: [SeamSignature.Hole.DeclaredProperty], hole: SeamSignature.Hole, declaringSeamLabel: String)], ownSiteAdditions: [[Property]: SiteAdditions], callPresentations: [CallPresentation]) {
		var callPresentations = [CallPresentation]()
		// While a test observes the place graph: beside each scope still to visit, the frames from the seam's root to the scope
		// that declares it, as `buildSites(in:)` gives a site's, and what it is generated with.
		var framesToVisit = [(frames: [PathFrame], propertiesGeneratedLater: Set<Property>, fillIsSendable: Bool)]()
		if draftsPlaceLevels {
			framesToVisit.append(([], [], false))
		}
		var passedUpHoles = [(innerSeamType: TypeDescription, typesToCall: [SeamSignature.Hole.PathType], route: [SeamSignature.Hole.DeclaredProperty], hole: SeamSignature.Hole, declaringSeamLabel: String)]()
		var takenSites = Set(ownSitePaths.map { SeamSignature.Hole.Site(seamType: seamType, path: $0) })
		var additionsBySite = [SeamSignature.Hole.Site: SiteAdditions]()
		var generatorsToVisit = [(generator: generator, typesToCall: [SeamSignature.Hole.PathType](), route: [SeamSignature.Hole.DeclaredProperty](), pathDeclarations: [SeamSignature.Hole.UncarriedDeclaration](), isInSendableFunction: false, fillContexts: [FillContext](), closedOnScopes: [ClosedOnScopeOnPathToCall]())]
		var declarationsBetweenByClosedOnScope = [ObjectIdentifier: [DeclarationBetween]]()
		while let (visited, typesToCall, route, pathDeclarations, isInSendableFunction, fillContexts, closedOnScopes) = generatorsToVisit.popLast() {
			let framesToVisited = framesToVisit.popLast()
			// The call is made in its scope's builder function, inside every function above it.
			let callIsInSendableFunction = isInSendableFunction || visited.buildsInSendableFunction
			// The fills around the call, each with what the scopes from its root down to the call declare. A fill's own bound
			// fields are its hole's, which its context, the last, reads from the hole.
			var fillContextsAtCall = fillContexts.map { $0.declaring(by: visited) }
			if visited.fillHole != nil, let ownContext = fillContexts.last {
				fillContextsAtCall[fillContextsAtCall.count - 1] = ownContext
			}
			if let innerSeamType = visited.builtInstantiable?.concreteInstantiable {
				var presentedPlaces = [CallPresentation.Place]()
				for hole in visited.passedUpHoles {
					if takenSites.insert(hole.site).inserted {
						// The seam that declares the place labels it: its own root enum's builder for the place's hole type and family,
						// which the called seam's signature carries, since a builder of the called seam reaches the place from it. That
						// label follows only from the declaring seam's hole types and parameters, so no passed-up label feeds another.
						let declaringSeamLabel = visited.calledBuilders?.enumsByKey[SeamSignature.ScopeEnum.rootKey(of: hole)]?.builderLabel ?? hole.builderLabel
						passedUpHoles.append((innerSeamType, typesToCall, route, hole, declaringSeamLabel))
					}
					// The call captures the builder when it is made in a `@Sendable` builder function, and takes it `@Sendable`
					// when the presented copy is.
					let presentedPlace = SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole)
					// The visible build fills the place inside the fills around the call, and that fill binds the place's fields.
					let insideFills = unreadableInsideFills(fillContextsAtCall, placeFields: hole.fields, fillingModule: seamModule)
					let boundOnPathToCall = pathDeclarations.map { $0.with(reason: .boundByPassingUpSeam(seam: seamType, module: seamModule, place: presentedPlace)) }
					additionsBySite[hole.site, default: SiteAdditions()].add(
						boundOnPathToCall + hole.uncarriedDeclarations + insideFills.calledCopyDeclarations,
						boundOnPathToCall: boundOnPathToCall + insideFills.calledCopyDeclarations,
						reenteringCallDeclarations: hole.reenteringCallDeclarations + insideFills.reenteringCallDeclarations,
						reenteringPlaceFields: hole.reenteringPlaceFields + insideFills.reenteringPlaceFields,
						isSendable: callIsInSendableFunction || hole.isSendable,
					)
					// The call is made in the builder function of each scope above it that a cycle closes on, so the seam it
					// builds, and the place inside, are built again beneath what the scopes between declare, as a place of this
					// seam's own is (`fields(of:)`). A label the path binds inside the function is bound again at each level, and
					// one the called seam's tree binds for the place is the same at every level inline too.
					for closedOnScope in closedOnScopes {
						let declarationsBetween = declarationsBetweenByClosedOnScope[ObjectIdentifier(closedOnScope.generator)]
							?? declarationsBetween(closedOnScope: closedOnScope.generator, closedOnDeclaration: closedOnScope.declaration)
						declarationsBetweenByClosedOnScope[ObjectIdentifier(closedOnScope.generator)] = declarationsBetween
						let labelsBoundInsideFunction = Set(pathDeclarations[closedOnScope.firstDeclarationInside...].map(\.property.label))
						additionsBySite[hole.site, default: SiteAdditions()].add(cycleReentryDeclarations: declarationsBetween.compactMap { between in
							guard between.property.label != hole.property.label,
							      !labelsBoundInsideFunction.contains(between.property.label),
							      !hole.fields.contains(where: { $0.property.label == between.property.label })
							else { return nil }
							return SeamSignature.Hole.CycleReentryDeclaration(
								property: between.property,
								declaringType: between.declaringType,
								declarationLocation: between.declarationLocation,
								parameterTakingType: between.parameterTakingType,
								closedOnProperty: between.closedOnProperty,
								closedOnBuiltType: closedOnScope.declaration.concreteType,
								closedOnDeclaringType: closedOnScope.declaringType,
								reenteringType: between.reenteringType,
								calledSeamType: hole.scopeSeamType,
							)
						})
					}
					presentedPlaces.append(CallPresentation.Place(
						hole: hole,
						// A call whose seam's graph was not built names no case.
						innerCaseIndex: visited.calledBuilders?.caseIndexBySite[hole.site] ?? -1,
						calledCopyDeclarations: insideFills.calledCopyDeclarations,
						reenteringCallDeclarations: insideFills.reenteringCallDeclarations,
						reenteringPlaceFields: insideFills.reenteringPlaceFields,
					))
				}
				let noPlaces: @Sendable (SeamSignature.Places.CalledCase) -> SeamSignature.Places.Called? = { _ in nil }
				let placesOfSeamsBeneath = visited.calledBuilders?.placesOfSeamsBeneath ?? noPlaces
				if let framesToVisited, let callProperty = visited.property, !presentedPlaces.isEmpty {
					callPresentations.append(CallPresentation(
						frames: framesToVisited.frames,
						callProperty: callProperty,
						pathTypes: SeamSignature.Hole.PathType.pathTypes(through: visited),
						declaredSegment: declaredProperties(reaching: visited, from: framesToVisited.frames.last?.generator),
						innerSeamType: innerSeamType,
						innerIsPublicMock: visited.publicMockCall != nil,
						innerCalled: visited.calledBuilders?.called ?? SeamSignature.Places.Called(places: SeamSignature.Places(levels: [], cases: []), holes: [], caseIndexByHole: []),
						placesOfSeamsBeneath: placesOfSeamsBeneath,
						isInSendableFunction: callIsInSendableFunction,
						opensSendableFunction: visited.buildsInSendableFunction,
						places: presentedPlaces,
					))
				}
			}
			// The seam's own forwarded properties come from its caller, which fills the builder. Each declaration's reason names
			// the place a call presents, where the call is reached.
			let childPathDeclarations = pathDeclarations + declarationsBound(by: visited, includingForwardedProperties: visited !== generator, reason: .other)
			// A fill whose code another fill of its case generates makes no call of its own.
			let children = visited.children.filter { $0.passesUpBuilder && $0.fillEmitsCode }
			if let framesToVisited {
				// A scope tells its children apart by their index, never by generator, which two of them can share.
				let childIndices = visited.children.indices.filter { visited.children[$0].passesUpBuilder && visited.children[$0].fillEmitsCode }
				let orderedChildren = visited.orderedChildrenComputedAfresh(propertiesGeneratedLater: framesToVisited.propertiesGeneratedLater)
				var positionByChildIndex = [Int: Int]()
				for (position, child) in orderedChildren.enumerated() {
					positionByChildIndex[child.index] = position
				}
				framesToVisit.append(contentsOf: childIndices.reversed().map { childIndex in
					let position = positionByChildIndex[childIndex, default: 0]
					return (
						framesToVisited.frames + [PathFrame(generator: visited, orderedChildren: orderedChildren, nextPosition: position + 1, fillIsSendable: framesToVisited.fillIsSendable)],
						orderedChildren[position].propertiesGeneratedLater,
						visited.buildsInSendableFunction(ofFill: visited.children[childIndex]),
					)
				})
			}
			generatorsToVisit.append(contentsOf: children.reversed().map { child in
				var childFillContexts = fillContextsAtCall
				if let fillHole = child.fillHole, let fillKey = child.fillKey {
					childFillContexts.append(FillContext(hidden: hidings(ofFillsOf: visited, hiddenByCall: &hiddenByCall)[fillKey] ?? FillReentryHidings(), fillHole: fillHole))
				}
				var childClosedOnScopes = closedOnScopes
				if let declaration = child.declarationACycleClosesOn {
					childClosedOnScopes.append(ClosedOnScopeOnPathToCall(
						generator: child,
						declaration: declaration,
						declaringType: visited.builtInstantiable?.concreteInstantiable ?? seamType,
						firstDeclarationInside: childPathDeclarations.count,
					))
				}
				return (child, typesToCall + SeamSignature.Hole.PathType.pathTypes(through: child), route + declaredProperties(reaching: child, from: visited), childPathDeclarations, callIsInSendableFunction || visited.buildsInSendableFunction(ofFill: child), childFillContexts, childClosedOnScopes)
			})
		}
		var ownSiteAdditions = [[Property]: SiteAdditions]()
		for path in ownSitePaths {
			ownSiteAdditions[path] = additionsBySite[SeamSignature.Hole.Site(seamType: seamType, path: path)]
		}
		return (
			passedUpHoles.map { innerSeamType, typesToCall, route, hole, declaringSeamLabel in
				let additions = additionsBySite[hole.site, default: SiteAdditions()]
				var passedUpHole = additions.presenting(hole)
				passedUpHole.reenteringCallDeclarations = additions.reenteringCallDeclarations
				passedUpHole.reenteringPlaceFields = additions.reenteringPlaceFields
				// The first of each label: the called seam's own cycles, then this seam's around its calls.
				passedUpHole.cycleReentryDeclarations += additions.cycleReentryDeclarations.filter { declaration in
					!hole.cycleReentryDeclarations.contains { $0.property.label == declaration.property.label }
				}
				return (innerSeamType, typesToCall, route, passedUpHole, declaringSeamLabel)
			},
			ownSiteAdditions,
			callPresentations,
		)
	}

	/// A call of a seam, or of another module's public mock, in a seam's tree that presents places, as the place graph reads
	/// it while a test observes the graph: where the call is, and what this seam's tree adds to each place it presents.
	private struct CallPresentation {
		struct Place {
			/// The called seam's hole of the place.
			let hole: SeamSignature.Hole
			/// The index of the place's case in the called seam's places, or `-1` where its signature holds none.
			let innerCaseIndex: Int
			/// What the fills around the call add to the place (`unreadableInsideFills(_:placeFields:fillingModule:)`).
			let calledCopyDeclarations: [SeamSignature.Hole.UncarriedDeclaration]
			let reenteringCallDeclarations: [SeamSignature.Hole.ReenteringCallDeclaration]
			let reenteringPlaceFields: [SeamSignature.Hole.ReenteringPlaceField]
		}

		/// The scopes from the seam's root to the one that declares the call, each with the position of the next on the path.
		let frames: [PathFrame]
		let callProperty: Property
		/// The types the call's own scope adds to the types on the way to it, and its property as the code declares it.
		let pathTypes: [SeamSignature.Hole.PathType]
		let declaredSegment: [SeamSignature.Hole.DeclaredProperty]
		let innerSeamType: TypeDescription
		let innerIsPublicMock: Bool
		/// The called seam's place graph, which the cases of the places refer into, with its places (`CalledBuilders.called`).
		let innerCalled: SeamSignature.Places.Called
		/// What the called seam's own passed-up cases refer into (`CalledBuilders.placesOfSeamsBeneath`).
		let placesOfSeamsBeneath: @Sendable (SeamSignature.Places.CalledCase) -> SeamSignature.Places.Called?
		/// Whether the call is made inside a `@Sendable` function, its own builder function included.
		let isInSendableFunction: Bool
		/// Whether the call's own builder function is `@Sendable`.
		let opensSendableFunction: Bool
		let places: [Place]
	}

	/// A scope on the path to a call that passes a place up whose builder function a cycle-closing scope in its tree calls.
	private struct ClosedOnScopeOnPathToCall {
		let generator: ScopeGenerator
		let declaration: ScopeGenerator.BuiltDeclaration
		/// The type that declares the scope's property.
		let declaringType: TypeDescription
		/// The index in the path's declarations of the first the scope's function binds.
		let firstDeclarationInside: Int
	}

	/// A fill of a seam call on a place's path: what the calls inside the fills of that call hide from it, its hole, and the
	/// labels the scopes beneath its root declare on the way down to the place.
	private struct FillContext {
		let hidden: FillReentryHidings
		let fillHole: SeamSignature.Hole
		var declaredLabels = Set<String>()

		/// This context with what `generator`, a scope beneath the fill's root, declares for the scopes beneath it.
		func declaring(by generator: ScopeGenerator) -> FillContext {
			var context = self
			context.declaredLabels.formUnion(generator.providedProperties.map(\.label))
			return context
		}
	}

	/// The fills of seam calls on `site`'s path, outermost first, each with what the scopes from its root down to the site's
	/// owner declare.
	private static func fillContexts(of site: BuildSite, hiddenByCall: inout [ObjectIdentifier: [String: FillReentryHidings]]) -> [FillContext] {
		var contexts = [FillContext]()
		// A fill's parent is the seam call whose fill it is.
		for (parent, frame) in zip(site.frames, site.frames.dropFirst()) {
			contexts = contexts.map { $0.declaring(by: frame.generator) }
			if let fillHole = frame.generator.fillHole, let fillKey = frame.generator.fillKey {
				contexts.append(FillContext(hidden: hidings(ofFillsOf: parent.generator, hiddenByCall: &hiddenByCall)[fillKey] ?? FillReentryHidings(), fillHole: fillHole))
			}
		}
		return contexts
	}

	/// What the calls inside the fills of `call`, a seam call, hide from each of those fills, computed once per call.
	private static func hidings(ofFillsOf call: ScopeGenerator, hiddenByCall: inout [ObjectIdentifier: [String: FillReentryHidings]]) -> [String: FillReentryHidings] {
		if let hidings = hiddenByCall[ObjectIdentifier(call)] {
			return hidings
		} else {
			let hidings = hiddenByReenteringCalls(ofFills: call.children)
			hiddenByCall[ObjectIdentifier(call)] = hidings
			return hidings
		}
	}

	/// The declarations a fill of a place inside the fills `contexts` stand for cannot read, which `fillingModule`, the
	/// module of the seam whose calls the fills are, fills, of each label a read of which in a fill's tree the visible build
	/// rejects at its last two checks: a label the fill's hole holds no field, cycle re-entry or uncarried declaration of,
	/// that no scope from the fill's root down to the place declares, nor, for a place a seam called inside the fill passes
	/// up, a field of that place (`placeFields`), which the visible build's fill of it binds. For each fill:
	/// - `calledCopyDeclarations`: what the copies of the fill's hole that the seams called inside the fills of its seam call
	///   take leave uncarried (`declarationBoundAfterSite`), which the place joins to its own uncarried declarations;
	/// - `reenteringCallDeclarations`: where no copy leaves the label uncarried, the declarations on the paths to the calls
	///   inside those fills that pass it on (`declarationBoundOnPathToReenteringCall`). Inline, the type built again reads
	///   such a declaration on the route through the call; a fill, one function, reads the outer call's value. So a field of
	///   the label bound above the seam call does not lift it: a deliberate loss of a shape inline builds correctly, until a
	///   fill is handed each route's value, in both builds.
	/// - `reenteringPlaceFields`: where neither of those holds the label, the fields of it that the places whose fills make
	///   such calls carry (`fieldOfReenteringPlace`): inline, the type built again sits beneath such a place and reads its
	///   field. A field bound above the seam call does not lift it either, for the same reason, until the same change.
	private static func unreadableInsideFills(
		_ contexts: [FillContext],
		placeFields: [SeamSignature.Hole.Field],
		fillingModule: ModuleIdentity,
	) -> (reenteringCallDeclarations: [SeamSignature.Hole.ReenteringCallDeclaration], reenteringPlaceFields: [SeamSignature.Hole.ReenteringPlaceField], calledCopyDeclarations: [SeamSignature.Hole.UncarriedDeclaration]) {
		var reenteringCallDeclarations = [SeamSignature.Hole.ReenteringCallDeclaration]()
		var reenteringPlaceFields = [SeamSignature.Hole.ReenteringPlaceField]()
		var calledCopyDeclarations = [SeamSignature.Hole.UncarriedDeclaration]()
		for context in contexts {
			let hole = context.fillHole
			var labelsReadElsewhere = context.declaredLabels.union(placeFields.map(\.property.label))
			labelsReadElsewhere.formUnion(hole.fields.map(\.property.label))
			labelsReadElsewhere.formUnion(hole.cycleReentryDeclarations.map(\.property.label))
			labelsReadElsewhere.formUnion(hole.uncarriedDeclarations.map(\.property.label))
			for label in context.hidden.calledCopyDeclarations.keys.sorted() where !labelsReadElsewhere.contains(label) {
				calledCopyDeclarations += context.hidden.calledCopyDeclarations[label] ?? []
			}
			labelsReadElsewhere.formUnion(context.hidden.calledCopyDeclarations.keys)
			for label in context.hidden.pathDeclarations.keys.sorted() where !labelsReadElsewhere.contains(label) {
				for hiding in context.hidden.pathDeclarations[label] ?? [] {
					reenteringCallDeclarations.append(hiding.reenteringCallDeclaration(reentering: hole, fillingModule: fillingModule))
				}
			}
			// The visible build reports a declaration on the path to the call before a field of a place whose fill makes it.
			labelsReadElsewhere.formUnion(context.hidden.pathDeclarations.keys)
			for label in context.hidden.fieldsOfReenteringPlaces.keys.sorted() where !labelsReadElsewhere.contains(label) {
				for carried in context.hidden.fieldsOfReenteringPlaces[label] ?? [] {
					reenteringPlaceFields.append(SeamSignature.Hole.ReenteringPlaceField(carried: carried, reenteredPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole), reenteredSeamModule: hole.scopeSeamModule, fillingModule: fillingModule))
				}
			}
		}
		return (adding(reenteringCallDeclarations, to: []), adding(reenteringPlaceFields, to: []), calledCopyDeclarations)
	}

	/// `existing`, re-entering place fields, with each of `fields` it does not hold, in the order of where each field is
	/// declared, then of what tells two apart, so no walk's order decides it.
	fileprivate static func adding(_ fields: [SeamSignature.Hole.ReenteringPlaceField], to existing: [SeamSignature.Hole.ReenteringPlaceField]) -> [SeamSignature.Hole.ReenteringPlaceField] {
		var combined = existing
		var identities = Set(existing.map(\.identity))
		for field in fields where identities.insert(field.identity).inserted {
			combined.append(field)
		}
		return combined.sorted { first, second in
			if first.carried.field.declarationLocation != second.carried.field.declarationLocation {
				// No message reads this order, since each re-sorts what it names by name; it keeps the stored list deterministic.
				Dependency.DeclarationLocation.precedesInSourceOrder(first.carried.field.declarationLocation, second.carried.field.declarationLocation)
			} else {
				first.identity.lexicographicallyPrecedes(second.identity)
			}
		}
	}

	/// `existing`, re-entering call declarations, with each of `declarations` it does not hold, in the order of where each is
	/// declared, then of what tells two apart, so no walk's order decides it.
	fileprivate static func adding(_ declarations: [SeamSignature.Hole.ReenteringCallDeclaration], to existing: [SeamSignature.Hole.ReenteringCallDeclaration]) -> [SeamSignature.Hole.ReenteringCallDeclaration] {
		var combined = existing
		var identities = Set(existing.map(\.identity))
		for declaration in declarations where identities.insert(declaration.identity).inserted {
			combined.append(declaration)
		}
		return combined.sorted { first, second in
			if first.declarationLocation != second.declarationLocation {
				Dependency.DeclarationLocation.precedesInSourceOrder(first.declarationLocation, second.declarationLocation)
			} else {
				first.identity.lexicographicallyPrecedes(second.identity)
			}
		}
	}

	/// The places the calls of other modules' public mocks in the tree of the internal mock of `mockedType`, which
	/// `generator` roots, pass up, each once, in the order the tree presents them first, each with the properties from the
	/// mock's root to the call that presents it prepended to its route, so that a message about the value it forwards is
	/// reported in the mock's module (`SeamSignature.Hole.forwardingLocation`), as its production tree reports it.
	static func placesPassedUp(inMockTreeOf mockedType: Instantiable, generator: ScopeGenerator) -> [SeamSignature.Hole] {
		let mockedModule = ModuleIdentity(moduleName: mockedType.moduleName, packageName: mockedType.packageName)
		var hiddenByCall = [ObjectIdentifier: [String: FillReentryHidings]]()
		return holesPassedUp(in: generator, seamType: mockedType.concreteInstantiable, seamModule: mockedModule, ownSitePaths: [], hiddenByCall: &hiddenByCall).passedUpHoles.map { passedUp in
			var place = passedUp.hole
			place.passedUpRoute = passedUp.route + place.passedUpRoute
			return place
		}
	}

	/// What the calls a seam's tree makes that present one site add to the builder the seam takes for it.
	private struct SiteAdditions {
		/// The declarations a fill of the site cannot read, the first of each label, in the order the calls present them.
		private var declarations = [SeamSignature.Hole.UncarriedDeclaration]()
		/// The re-entering call declarations of every call that presents the site, each once: every one of a label, which the
		/// message names, beside `declarations`, which keeps the first.
		private(set) var reenteringCallDeclarations = [SeamSignature.Hole.ReenteringCallDeclaration]()
		/// The re-entering place fields of every call that presents the site, each once.
		private(set) var reenteringPlaceFields = [SeamSignature.Hole.ReenteringPlaceField]()
		/// Whether a call that presents the site is made in a `@Sendable` function, a fill's included, or takes the builder
		/// `@Sendable`.
		private(set) var isSendable = false
		/// What the scopes on the paths to the calls that present the site declare, or the fills around such a call bind, the
		/// first of each label, in the order the calls present them.
		private var declarationsBoundOnPathsToCalls = [String: SeamSignature.Hole.UncarriedDeclaration]()

		/// Adds `newDeclarations`, those of labels not yet added, `newReenteringCallDeclarations` and `newReenteringPlaceFields`,
		/// from a call that needs the builder `@Sendable` when `isSendable`, on whose path `boundOnPathToCall` is bound.
		mutating func add(_ newDeclarations: [SeamSignature.Hole.UncarriedDeclaration], boundOnPathToCall: [SeamSignature.Hole.UncarriedDeclaration], reenteringCallDeclarations newReenteringCallDeclarations: [SeamSignature.Hole.ReenteringCallDeclaration], reenteringPlaceFields newReenteringPlaceFields: [SeamSignature.Hole.ReenteringPlaceField], isSendable: Bool) {
			for declaration in newDeclarations where !declarations.contains(where: { $0.property.label == declaration.property.label }) {
				declarations.append(declaration)
			}
			for declaration in boundOnPathToCall where declarationsBoundOnPathsToCalls[declaration.property.label] == nil {
				declarationsBoundOnPathsToCalls[declaration.property.label] = declaration
			}
			reenteringCallDeclarations = DependencyTreeGenerator.adding(newReenteringCallDeclarations, to: reenteringCallDeclarations)
			reenteringPlaceFields = DependencyTreeGenerator.adding(newReenteringPlaceFields, to: reenteringPlaceFields)
			self.isSendable = self.isSendable || isSendable
		}

		/// What the cycles of the passing-up seam's tree around the calls that present the site declare again, the first of
		/// each label, in the order the calls present them.
		private(set) var cycleReentryDeclarations = [SeamSignature.Hole.CycleReentryDeclaration]()

		/// Adds those of `newDeclarations` of labels not yet added.
		mutating func add(cycleReentryDeclarations newDeclarations: [SeamSignature.Hole.CycleReentryDeclaration]) {
			for declaration in newDeclarations where !cycleReentryDeclarations.contains(where: { $0.property.label == declaration.property.label }) {
				cycleReentryDeclarations.append(declaration)
			}
		}

		/// The declarations added of labels none of `existing` has.
		func declarations(besides existing: [SeamSignature.Hole.UncarriedDeclaration]) -> [SeamSignature.Hole.UncarriedDeclaration] {
			let existingLabels = Set(existing.map(\.property.label))
			return declarations.filter { !existingLabels.contains($0.property.label) }
		}

		/// `hole` as the calls that present its site present it: with the declarations added of labels it holds none of. A
		/// declaration its mock binds from its caller's argument (`isBoundFromCallersArgument`) whose label a call's path
		/// binds is the declaration on that path, which the mock is passed, and not the value of the caller of the type that
		/// passes the place up.
		func presenting(_ hole: SeamSignature.Hole) -> SeamSignature.Hole {
			var presented = hole.addingUncarriedDeclarations(declarations(besides: hole.uncarriedDeclarations), isSendable: isSendable)
			presented.uncarriedDeclarations = presented.uncarriedDeclarations.map { declaration in
				guard declaration.isBoundFromCallersArgument, let boundOnPath = declarationsBoundOnPathsToCalls[declaration.property.label] else { return declaration }
				return boundOnPath
			}
			return presented
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
		if generator.fillHole != nil {
			// A fill binds the fields it reads from its struct; one bound from a deferred parameter it reads from the
			// caller's scope declares nothing.
			for declaration in generator.fillUncarriedDeclarations.map({ ($0.property, $0.declaringType, $0.declarationLocation, $0.parameterTakingType) })
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

	/// The value a mock's root binds for its child `property`, as its root level declares it. The mock builds every dependency
	/// it promotes to its root and binds the non-optional value it builds, even where it promotes the dependency for a
	/// receive of its optional form (`db: Db?`, which a call of another module's public mock receives only if available and
	/// builds when passed `nil`): the root level declares the non-optional form, so a fill that requires the value reads it,
	/// as the production twin's fill reads the seam's required parameter. The mocked type's own dependencies are bound as
	/// they are declared.
	static func mockRootBinding(ofChild property: Property, of mockedType: Instantiable) -> Property {
		mockRootBinding(ofChild: property, isDependencyOfMockedType: { mockedType.dependencies.contains { $0.property == property } })
	}

	/// The value a mock's root binds for its child `property`, as `mockRootBinding(ofChild:of:)` says, given whether
	/// `property` is a dependency of the mocked type.
	static func mockRootBinding(ofChild property: Property, isDependencyOfMockedType: () -> Bool) -> Property {
		guard case .optional = property.typeDescription, !isDependencyOfMockedType() else { return property }
		return property.asUnwrappedProperty
	}

	/// What a scope on a site's path declares for each of its children, as `fields(of:)` finds it before it knows where the
	/// site is among them, and the children that hold a place.
	private struct ChildDeclarations {
		/// Each child's declaration, in the scope's child order, or `nil` for a child that declares nothing there.
		let declarations: [PathDeclaration?]
		/// The properties of the children that start as carriers (`ScopeGenerator.startsAsCarrier(_:)`).
		let carrierProperties: [Property]

		/// Each carrier property's first position among `carrierProperties`, and the carrier there.
		private let firstCarrierByProperty: [Property: (position: Int, carrier: Property)]

		init(declarations: [PathDeclaration?], carrierProperties: [Property]) {
			self.declarations = declarations
			self.carrierProperties = carrierProperties
			firstCarrierByProperty = Dictionary(
				carrierProperties.enumerated().map { ($0.element, (position: $0.offset, carrier: $0.element)) },
				uniquingKeysWith: { first, _ in first },
			)
		}

		/// The first of `carrierProperties`, other than `pathProperty`, that is among `requiredProperties`. Whichever of the
		/// two is smaller is walked and the other looked up in, so a scope of many carriers whose children each require a
		/// few properties compares only those few for each child.
		func firstCarrier(otherThan pathProperty: Property, among requiredProperties: Set<Property>) -> Property? {
			if requiredProperties.count < carrierProperties.count {
				// A set has no order of its own: the carrier at the lowest position is the one a scan in child order stops at.
				GenerationWork.record(requiredProperties.count, by: .findingCarrierASiblingRequires)
				return requiredProperties.lazy
					.compactMap { firstCarrierByProperty[$0] }
					.filter { $0.carrier != pathProperty }
					.min { $0.position < $1.position }?.carrier
			} else {
				for (position, carrier) in carrierProperties.enumerated() where carrier != pathProperty && requiredProperties.contains(carrier) {
					GenerationWork.record(position + 1, by: .findingCarrierASiblingRequires)
					return carrier
				}
				GenerationWork.record(carrierProperties.count, by: .findingCarrierASiblingRequires)
				return nil
			}
		}

		/// The first two of `carrierProperties` that are among `requiredProperties`, in their order: the first of them other
		/// than any one property is the first carrier other than it (`firstCarrier(otherThan:among:)`). For the place graph.
		func firstTwoCarriers(among requiredProperties: Set<Property>) -> [Property] {
			requiredProperties.compactMap { firstCarrierByProperty[$0] }.sorted { $0.position < $1.position }.prefix(2).map(\.carrier)
		}
	}

	/// A type's dependencies, looked up by property: what a scan of them in declaration order for the first of a property
	/// finds, and the labels the type declares other than by receiving them.
	struct DependenciesByProperty {
		init(of instantiable: Instantiable) {
			var dependencyByProperty = [Property: Dependency]()
			var labelsNotReceived = Set<String>()
			for dependency in instantiable.dependencies {
				if dependencyByProperty[dependency.property] == nil {
					dependencyByProperty[dependency.property] = dependency
				}
				if !dependency.source.isReceived {
					labelsNotReceived.insert(dependency.property.label)
				}
			}
			self.dependencyByProperty = dependencyByProperty
			self.labelsNotReceived = labelsNotReceived
		}

		/// The first dependency of each property, in declaration order.
		let dependencyByProperty: [Property: Dependency]
		/// The labels of the dependencies that are not received.
		let labelsNotReceived: Set<String>
	}

	/// Whether a mock binds `dependency`, a dependency of a scope beneath its root, again under its label at the top of that
	/// scope, given `nearestDeclaration`, the nearest declaration of the label above the scope: the dependency is received,
	/// and `nearestDeclaration` provides no form it reads. The mock then supplies it from a parameter or override of its own,
	/// which `nearestDeclaration` makes it name apart (`user_Draft` beside `user: User`), and the scope binds that back to the
	/// label (`emitReceiverBindings`), so the scopes beneath it read the received value, never `nearestDeclaration`, as
	/// inline's do. A seam's tree binds no receive again: there Swift's lookup reads `nearestDeclaration` beneath a receive
	/// that is passed `nil`.
	static func mockBindsAgain(receiving dependency: Dependency, beneath nearestDeclaration: Property) -> Bool {
		switch dependency.source {
		case let .received(onlyIfAvailable):
			if onlyIfAvailable {
				!ScopeGenerator.provides(nearestDeclaration, aFormReadBy: dependency.property)
			} else {
				!CycleParameter.forms(providedBy: nearestDeclaration).contains(dependency.property)
			}
		case .instantiated, .forwarded, .aliased:
			false
		}
	}

	/// The names of the builder functions the properties of the tree `generator` roots would have, which a builder's
	/// name inside the generated initializer must not equal.
	///
	/// The walk visits each generator once: several places of the tree can share one generator (see `ConstructionMemo`),
	/// whose property and children are the same at each, so a name is a fact of the generator, not of the path to it.
	/// Visited at every place, a seam whose screens each open three screens of the next layer was walked once per path.
	/// The set of generators visited dies with the walk.
	static func builderFunctionNamesOfProperties(in generator: ScopeGenerator, includingHoleSites: Bool = true) -> Set<String> {
		var names = Set<String>()
		var generatorsToVisit = [generator]
		var visitedGenerators = Set<ObjectIdentifier>()
		while let visited = generatorsToVisit.popLast() {
			guard visitedGenerators.insert(ObjectIdentifier(visited)).inserted else { continue }
			if let property = visited.property, includingHoleSites || visited.holeSite == nil {
				names.insert(ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
			}
			generatorsToVisit.append(contentsOf: visited.children)
		}
		GenerationWork.record(visitedGenerators.count, by: .collectingBuilderFunctionNames)
		return names
	}

	/// A declaration on a site's path: the value it binds and whether it is bound before the site.
	struct PathDeclaration {
		let property: Property
		var isBoundBeforeSite: Bool
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
		/// Whether the builder function of the scope at `frameLevel` wraps it again as a member of a loop of builders.
		var isReboundByBuilderFunction = false
		/// Whether its type forwards it.
		var isForwarded = false
		/// Where it is a parameter of a builder function a lazy cycle closes on: whose, and what the cycle passes it.
		var cycleParameterOrigin: SeamSignature.Hole.UncarriedDeclaration.CycleParameterOrigin?
		/// Where its type, the seam or a type in its tree, receives it under an alias: what fulfills it.
		var alias: SeamSignature.Hole.UncarriedDeclaration.AliasOrigin?
		/// For a parameter of a seam, its receives and the seam's declaration (`SeamSignature.Hole.Field.seamParameterOrigin`).
		var seamParameterOrigin: SeamSignature.Hole.Field.SeamParameterOrigin?
		/// Whether it is a received value a public mock binds at its root from the argument its caller passes
		/// (`SeamSignature.Hole.UncarriedDeclaration.isBoundFromCallersArgument`).
		var isBoundFromCallersArgument = false
		/// Where a type above the seam could build the tree it instantiates
		/// (`SeamSignature.Hole.UncarriedDeclaration.isBuildableAboveSeam`), that tree's generator, and the properties from the
		/// seam's root to the scope that declares it, which the sites of the places the tree holds start with.
		var treeBuildableAboveSeam: (generator: ScopeGenerator, pathToDeclaringScope: [Property])?
		/// Whether a public mock's root binds it from a value it receives (`SeamSignature.Hole.Field.isBoundByPublicMockRoot`).
		var isBoundByPublicMockRoot = false
		/// For a fill's field bound from a parameter of the filled seam, the seams a declaration it hides is named with
		/// (`SeamSignature.Places.Declaration.fillFieldHiding`).
		var fillFieldHiding: SeamSignature.Places.FillFieldHiding?
		/// For a child of its scope, while the place graph is drafted: what decides its facts before each next property.
		var childFacts: SeamSignature.Places.ChildFacts?
		/// Whether it is a fill's field bound from a parameter of the filled seam.
		var isFieldOfSeamParameter = false
	}

	/// The fields of `site`'s place, the declarations on its path that carry no field, the declarations a cycle hands the
	/// site's owner when it builds it again, the levels of its path, and the fields and uncarried declarations the levels
	/// decide, a `@Sendable` function on the path aside. A place built inside a `@Sendable` function – a builder function, a
	/// fill's function, or the `Sendable` wrapper it is held in – is handed only what the innermost such function binds: a
	/// declaration bound outside it is uncarried (`boundOutsideSendableFunction`), and the seam's parameters are no field,
	/// since a fill reads them from the caller's own scope.
	/// - Parameters:
	///   - bindsReceivesAgain: Whether the tree is a public mock's, which binds a receive again where the nearest declaration
	///     of its label does not provide its form (see `mockBindsAgain(receiving:beneath:)`).
	///   - namesApartAtRoot: For a public mock, what its root binds only under names apart, which no level declares. A fill
	///     whose own receive is of a form the root binds only under a name apart, with no type on its path that receives that
	///     form, finds no field of it: the place is passed up, and the caller's builder can capture the value, as
	///     `receivesBoundAgainOfAnyBuild(inTreeRootedAt:rootFields:namesApartAtRoot:)` says too.
	///   - declarationsBetweenByClosedOnScope: The `declarationsBetween(closedOnScope:)` of each scope already asked, by the
	///     scope's identity.
	///   - placesByTreePath: The `places(inTreeOf:…)` of each tree already asked, by the path to its place: the declaring
	///     scope's path and the property. A generator can be shared between places, and a tree's places are read at its own path.
	///   - seamDependencies: The seam's dependencies by property.
	///   - dependenciesByGenerator: The dependencies by property of the type each scope already asked builds, by its
	///     generator's identity.
	///   - childDeclarationsByGenerator: What each scope already asked declares for its children on every site's path through
	///     it, by its generator's identity.
	private static func fields(
		of site: BuildSite,
		seam: Instantiable,
		bindsReceivesAgain: Bool,
		namesApartAtRoot: PublicMockRootLevel.NamesApart,
		parameters: [SeamSignature.Parameter],
		receiversByParameter: [Property: [SeamSignature.Receiver]],
		seamTypeAccess: AccessLevel,
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
		declarationsBetweenByClosedOnScope: inout [ObjectIdentifier: [DeclarationBetween]],
		placesByTreePath: inout [[Property]: [SeamSignature.Hole.Site]],
		seamDependencies: DependenciesByProperty,
		dependenciesByGenerator: inout [ObjectIdentifier: DependenciesByProperty],
		childDeclarationsByGenerator: inout [ObjectIdentifier: ChildDeclarations],
		draftsPlaceLevels: Bool,
	) -> (fields: [SeamSignature.Hole.Field], uncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration], cycleReentryDeclarations: [SeamSignature.Hole.CycleReentryDeclaration], levels: [SeamPlaceLevels.Level], pathFields: [Property], pathUncarriedProperties: [Property], declarationsHiddenByFields: [SeamSignature.Hole.DeclarationHiddenByField], placeLevels: [SeamPlacesBuilder.LevelDraft], isBuiltInSendableFunction: Bool) {
		// A field is as visible as the narrowest type it names, which the declarations of the seam's module and of the
		// module of the type that declares the value prove, capped at the seam's type.
		func access(of property: Property, declaredBy declaringModuleName: String?) -> (level: AccessLevel, cause: TypeAccessProof.Cause?) {
			let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, declaringModuleName]))
			return (min(access.level, seamTypeAccess), access.cause)
		}
		// A mock's root declares no child of a label its root level's fields hold, which are bound before the children, or one
		// that only names apart bind (`PublicMockRootLevel`).
		let labelsNoRootChildDeclares = bindsReceivesAgain ? namesApartAtRoot.labels.union(parameters.map(\.property.label)) : []
		// The nearest declaration of each label, and the order in which the labels are bound.
		var nearestDeclarations = [String: PathDeclaration]()
		var labelsInBindingOrder = [String]()
		// Beside them, what each scope on the path declares, the level it holds, outermost first: the seam's root's starts
		// with the parameters.
		var levels = [SeamPlaceLevels.Level]()
		var levelDeclarations = [SeamPlaceLevels.Level.Declaration]()
		/// Declares `declaration`, which the place graph's level drafts as `drafted` where that is given: a child of its scope
		/// before any next property.
		func declare(_ declaration: PathDeclaration, drafted: PathDeclaration? = nil) {
			let label = declaration.property.label
			if nearestDeclarations.updateValue(declaration, forKey: label) != nil {
				labelsInBindingOrder.removeAll { $0 == label }
			}
			labelsInBindingOrder.append(label)
			var levelDeclaration = SeamPlaceLevels.Level.Declaration(property: declaration.property, isBoundBeforeNextProperty: declaration.isBoundBeforeSite)
			levelDeclaration.isSeamParameter = declaration.frameLevel < 0
			levelDeclaration.isCycleParameter = declaration.isCycleParameter
			levelDeclaration.isReboundByBuilderFunction = declaration.isReboundByBuilderFunction
			levelDeclarations.append(levelDeclaration)
			if draftsPlaceLevels {
				levelPathDeclarations.append(drafted ?? declaration)
			}
		}
		// Beside the levels, while a test observes the place graph (`SeamPlaceLevels.observer`), each level's
		// declarations as the path declares them and the facts of the level and of the edge into it, outermost first.
		struct PlaceLevelInProgress {
			let key: SeamSignature.Places.LevelKey
			let declarations: [PathDeclaration]
			let opensSendableFunction: SeamSignature.Places.SendableFunctionOpened?
			let fillBaseStack: [SeamSignature.Places.StackEntry]
			let fillOwnerType: TypeDescription?
			let pathSegment: [Property]
			let pathTypes: [SeamSignature.Hole.PathType]
			let declaredSegment: [SeamSignature.Hole.DeclaredProperty]
			let nextPosition: Int?
			let nextLoop: Int?
		}
		var placeLevelsInProgress = [PlaceLevelInProgress]()
		var levelPathDeclarations = [PathDeclaration]()
		var levelOpensFunction: SeamSignature.Places.SendableFunctionOpened?
		var levelPathSegment = [Property]()
		var levelPathTypes = [SeamSignature.Hole.PathType]()
		var levelDeclaredSegment = [SeamSignature.Hole.DeclaredProperty]()
		var isInFill = false
		// Each declaration a fill's field hides, by label, with the level of the fill that binds the field.
		var hiddenByFillFields = [String: (declaration: SeamSignature.Hole.DeclarationHiddenByField, fieldLevel: Int)]()
		var levelOpensSendableFunction = false
		func endLevel(builtType: TypeDescription?, nextProperty: Property?, filledType: TypeDescription? = nil, filledCase: SeamSignature.Places.CalledCase? = nil, fillBaseStack: [SeamSignature.Places.StackEntry] = [], fillOwnerType: TypeDescription? = nil, nextPosition: Int? = nil, nextLoop: Int? = nil) {
			var level = SeamPlaceLevels.Level(builtType: builtType, nextProperty: nextProperty, isInFill: isInFill, declarations: levelDeclarations)
			level.opensSendableFunction = levelOpensSendableFunction
			if draftsPlaceLevels {
				placeLevelsInProgress.append(PlaceLevelInProgress(
					key: SeamSignature.Places.LevelKey(builtType: builtType, nextProperty: nextProperty, isSeamRoot: levels.isEmpty, isInFill: isInFill, filledType: filledType, filledCase: filledCase),
					declarations: levelPathDeclarations,
					opensSendableFunction: levelOpensFunction,
					fillBaseStack: fillBaseStack,
					fillOwnerType: fillOwnerType,
					pathSegment: levelPathSegment,
					pathTypes: levelPathTypes,
					declaredSegment: levelDeclaredSegment,
					nextPosition: nextPosition,
					nextLoop: nextLoop,
				))
				levelPathDeclarations = []
				levelOpensFunction = nil
				levelPathSegment = []
				levelPathTypes = []
				levelDeclaredSegment = []
			}
			levels.append(level)
			levelDeclarations = []
			levelOpensSendableFunction = false
		}
		// The labels the seam receives from its caller: its parameters but the ones it forwards, which its caller hands only
		// to the seam itself. A label is matched by name only: a tree that receives a label a nearer declaration in the seam's
		// tree binds, while the seam takes a parameter of that label too, declares one label twice on a branch, a shape SafeDI
		// discourages, and would read the caller's value once built above the seam.
		let forwardedLabels = Set(seam.dependencies.filter { $0.source == .forwarded }.map(\.property.label))
		let receivedLabels = Set(parameters.map(\.property.label)).subtracting(forwardedLabels)
		/// `uncarriedDeclaration` with what decides, for `declaration`, whether a type above the seam can build it.
		func markingBuildabilityAboveSeam(of uncarriedDeclaration: SeamSignature.Hole.UncarriedDeclaration, as declaration: PathDeclaration) -> SeamSignature.Hole.UncarriedDeclaration {
			guard let tree = declaration.treeBuildableAboveSeam else { return uncarriedDeclaration }
			var marked = uncarriedDeclaration
			marked.isBuildableAboveSeam = true
			marked.labelsHeldAboveSeam = receivedLabels.union([declaration.property.label])
			// Each site whose path the tree is beside asks again. The places are read at the tree's own path, so they are keyed
			// by that path, never by the generator, which a construction memo can share between paths.
			let treePath = tree.pathToDeclaringScope + [declaration.property]
			let treePlaces = placesByTreePath[treePath] ?? places(inTreeOf: tree.generator, building: declaration.property, declaredAt: tree.pathToDeclaringScope, seamType: seam.concreteInstantiable)
			placesByTreePath[treePath] = treePlaces
			marked.placesInTree = treePlaces
			return marked
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
				declarationLocation: firstReceiver?.declarationLocation ?? seamDependencies.dependencyByProperty[parameter.property]?.declarationLocation ?? seam.declarationLocation,
				isReceivedOnlyIfAvailable: parameter.isOnlyIfAvailable,
			)
			parameterDeclaration.deferral = parameter.deferral
			parameterDeclaration.isBoundByPublicMockRoot = bindsReceivesAgain
			// A public mock's root level binds a receive again where its nearest declaration does not provide its form, so
			// its parameters say little about the forms a fill may receive: only that an optional wrapper, which its tree
			// receives only if available, gives a fill no value (`findingsOfFill`'s `publicMockHandsOptionalWrapperOfRequiredValue`).
			// Its fields keep their origin for that check alone. A deliberate gap (contract rule 7 in `seam-and-mock-contract.md`):
			// a calling mock whose fill reads a label in a form no parameter of the seam takes with the parameter's stays accepted,
			// though `validateFills` rejects its production twin as the seam's two forms (`parameterReceivedInAnotherForm`),
			// because the mock builds the called types inline and hands the reader inline's value. So the two-forms check skips a
			// field the root binds (`isBoundByPublicMockRoot`), and a fill that carries such a field on, or is handed it as a memo,
			// drops the origin (`Field.handedAsMemo`, the fill fields below); the scope enums give the root's parameters none.
			parameterDeclaration.seamParameterOrigin = SeamSignature.Hole.Field.SeamParameterOrigin(
				of: parameter,
				of: seam,
				declaringType: parameterDeclaration.declaringType,
				declarationLocation: parameterDeclaration.declarationLocation,
				// A public mock's root level records its receivers apart (`PublicMockRootLevel.receiversByField`).
				receivers: receiversByParameter[parameter.property],
			)
			declare(parameterDeclaration)
		}
		var sendableDepth = 0
		// The property each `@Sendable` function on the path builds, outermost first, with the kind of function it is.
		var sendableFunctions = [(property: Property, function: SeamSignature.Hole.UncarriedDeclaration.SendableFunction)]()
		// The scopes on the path below the root whose builder function a cycle-closing scope in their tree calls, each with
		// its level on the path and the type that declares its property.
		var scopesACycleClosesOn = [(level: Int, generator: ScopeGenerator, declaration: ScopeGenerator.BuiltDeclaration, declaringType: TypeDescription)]()
		// For the tests' checks only, so only while a test observes the levels: the index in `levels` of each closed-on
		// scope's level, by its frame's level.
		let observesLevels = SeamPlaceLevels.observer != nil
		var levelIndexByClosedOnFrameLevel = [Int: Int]()
		// How many `@Sendable` functions on the path enclose what the scope at each level binds, its own included.
		var sendableDepthByLevel = [Int: Int]()
		// The type that declares the properties of the previous frame's children: the next frame's declaring type.
		var childDeclaringType = seam.concreteInstantiable
		// The type whose scope declares the children of the frame being visited: the one the frame before built.
		var loopDeclaringInstantiable = seam
		var loopDeclaringDependencies = seamDependencies
		// The properties from the seam's root to the frame being visited, as a site's path spells them (`BuildSite.sitePath`).
		var pathToFrame = [Property]()
		for (level, frame) in site.frames.enumerated() {
			if level > 0 {
				pathToFrame += frame.generator.fillHole?.pathBeforePropertyInItsFill ?? frame.generator.property.map { [$0] } ?? []
				if draftsPlaceLevels {
					levelPathSegment += frame.generator.fillHole?.pathBeforePropertyInItsFill ?? frame.generator.property.map { [$0] } ?? []
					levelPathTypes += SeamSignature.Hole.PathType.pathTypes(through: frame.generator)
					levelDeclaredSegment += declaredProperties(reaching: frame.generator, from: site.frames[level - 1].generator)
				}
			}
			if level > 0, let declaration = frame.generator.declarationACycleClosesOn {
				scopesACycleClosesOn.append((level, frame.generator, declaration, childDeclaringType))
				if observesLevels || draftsPlaceLevels {
					levelIndexByClosedOnFrameLevel[level] = levels.count
				}
			}
			// A fill the seam generates for a seam it calls binds every field of that seam's struct a site inside it carries,
			// which is every field it binds (`ScopeGenerator.fillBoundFields`): what the struct carries is what inline holds
			// there. A field bound from a deferred parameter the fill reads from this seam's tree instead, where the call
			// passed it, so the nearest declaration of its label is the one above the call. A declaration the struct does
			// not carry is on the called seam's path too, bound after its site or still being built, and hides the farther
			// declarations of its label.
			// A fill of a case nested by type stands for every place of the case: its fields and uncarried declarations are every
			// place's (`ScopeGenerator.fillFields`, `ScopeGenerator.fillUncarriedDeclarations`), and a label whose nearest
			// declaration on one route is uncarried is uncarried for the fill, as inline's tree reads it on that route.
			if let filledHole = frame.generator.fillHole {
				// The only property a fill builds is its hole's.
				childDeclaringType = filledHole.ownerType
				isInFill = true
				let uncarriedLabels = frame.generator.fillLabelsUncarriedOnSomeRoute
				for uncarriedDeclaration in frame.generator.fillUncarriedDeclarations {
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
					levelOpensSendableFunction = true
					levelOpensFunction = SeamSignature.Places.SendableFunctionOpened(property: filledHole.property, function: .other)
					sendableFunctions.append((filledHole.property, .other))
				}
				for boundField in frame.generator.fillFields where frame.generator.fillStructBoundLabels.contains(boundField.property.label) && !uncarriedLabels.contains(boundField.property.label) {
					// A label some route hands the fill as a memo is declared, for the places inside the fill, as the place's own field of
					// it, the declaration inline reads there, such as a wrapper a type further out declares, whose levels hand it on to a
					// fill of such a place that reads that wrapper alone (`ScopeGenerator.fillLabelsReadOnlyAsPlaceField`); the memo
					// is the value the route hands this fill.
					let field = frame.generator.fillLabelsHandedAsMemo.contains(boundField.property.label)
						? frame.generator.fillCaseHoles.lazy.flatMap(\.fields).first { $0.property.label == boundField.property.label } ?? boundField
						: boundField
					// A parameter of the seam whose struct carries the field hides a declaration of another form above the call, which
					// a seam on the route to the place that passes it up, or a scope above the call, binds: kept apart, while the field
					// stays the nearest declaration of its label (`SeamSignature.Hole.DeclarationHiddenByField`).
					if field.isSeamParameter, let hidden = nearestDeclarations[field.property.label], hidden.property != field.property {
						let calledSeam = if case let .boundByPassingUpSeam(_, _, place) = hidden.reason {
							place.seamType
						} else {
							site.frames[level - 1].generator.builtInstantiable?.concreteInstantiable ?? filledHole.scopeSeamType
						}
						hiddenByFillFields[field.property.label] = (
							SeamSignature.Hole.DeclarationHiddenByField(property: hidden.property, declaringType: hidden.declaringType, declarationLocation: hidden.declarationLocation, calledSeam: calledSeam, receivingSeam: filledHole.scopeSeamType),
							level,
						)
					}
					let fieldAccess = access(of: field.property, declaredBy: instantiables[field.declaringType]?.moduleName)
					var fieldDeclaration = PathDeclaration(
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
					)
					// A field bound from a parameter of the filled seam is still that seam's parameter: a fill of a place this seam passes
					// up that reads the label in a form no one parameter takes with it gives that seam's tree two forms, which its caller
					// reports as one module reports it (`parameterReceivedInAnotherForm`), rather than passing the reader `nil`. A
					// field a called public mock's root binds keeps its origin only where that root binds it (`isBoundByPublicMockRoot`),
					// which this declaration is not, so the calling mock's deliberate gap holds here too.
					fieldDeclaration.seamParameterOrigin = field.isBoundByPublicMockRoot ? nil : field.seamParameterOrigin
					fieldDeclaration.isFieldOfSeamParameter = field.isSeamParameter
					if field.isSeamParameter {
						// The seam a declaration this field hides is named with, where that declaration is no passing-up seam's.
						fieldDeclaration.fillFieldHiding = SeamSignature.Places.FillFieldHiding(
							calledSeam: site.frames[level - 1].generator.builtInstantiable?.concreteInstantiable ?? filledHole.scopeSeamType,
							receivingSeam: filledHole.scopeSeamType,
						)
					}
					declare(fieldDeclaration)
					levelDeclarations[levelDeclarations.count - 1].isFieldOfSeamParameter = field.isSeamParameter
				}
				let call = site.frames[level - 1].generator
				endLevel(
					builtType: nil,
					nextProperty: frame.orderedChildren[frame.nextPosition - 1].generator.property,
					filledType: call.builtInstantiable?.concreteInstantiable,
					// The called seam's case of the place the fill fills, which a call whose seam's graph was not built names none of.
					filledCase: call.calledBuilders?.caseIndexBySite[filledHole.site].map {
						SeamSignature.Places.CalledCase(seamType: call.builtInstantiable?.concreteInstantiable ?? filledHole.scopeSeamType, isPublicMock: call.publicMockCall != nil, caseIndex: $0)
					},
					fillBaseStack: zip(filledHole.fillPropertyStack, filledHole.fillConcreteTypeStack).map { SeamSignature.Places.StackEntry(property: $0, concreteType: $1) },
					fillOwnerType: filledHole.ownerType,
				)
				if observesLevels {
					levels[levels.count - 1].fillBaseStack = filledHole.fillPropertyStack
					levels[levels.count - 1].fillBaseConcreteTypes = filledHole.fillConcreteTypeStack
				}
				continue
			}
			guard let instantiable = frame.generator.builtInstantiable else { continue }
			childDeclaringType = instantiable.concreteInstantiable
			// Each child of a type looks its declaration up, so the type's dependencies are indexed once across the sites.
			let dependencies = dependenciesByGenerator[ObjectIdentifier(frame.generator)] ?? DependenciesByProperty(of: instantiable)
			dependenciesByGenerator[ObjectIdentifier(frame.generator)] = dependencies
			// A `@Sendable` builder function on the path encloses what it binds: what binds it before is outside.
			if level > 0, let property = frame.generator.property, frame.generator.buildsInSendableFunction {
				sendableDepth += 1
				levelOpensSendableFunction = true
				let function = sendableFunction(openedBy: property, building: instantiable.concreteInstantiable)
				levelOpensFunction = SeamSignature.Places.SendableFunctionOpened(property: property, function: function)
				sendableFunctions.append((property, function))
			}
			sendableDepthByLevel[level] = sendableDepth
			func declaration(of property: Property, isBoundBeforeSite: Bool) -> PathDeclaration {
				let propertyAccess = access(of: property, declaredBy: instantiable.moduleName)
				return PathDeclaration(
					property: property,
					isBoundBeforeSite: isBoundBeforeSite,
					sendableDepth: sendableDepth,
					access: propertyAccess.level,
					accessCause: propertyAccess.cause,
					declaringType: instantiable.concreteInstantiable,
					declarationLocation: dependencies.dependencyByProperty[property]?.declarationLocation,
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
					var reboundDeclaration = PathDeclaration(
						property: reboundProperty,
						isBoundBeforeSite: true,
						sendableDepth: sendableDepth,
						access: reboundAccess.level,
						accessCause: reboundAccess.cause,
						declaringType: loopDeclaringInstantiable.concreteInstantiable,
						declarationLocation: loopDeclaringDependencies.dependencyByProperty[reboundProperty]?.declarationLocation,
						frameLevel: level,
					)
					reboundDeclaration.isReboundByBuilderFunction = true
					declare(reboundDeclaration)
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
			// A public mock binds a receive again, under its label, at the top of the scope that makes it, where the nearest
			// declaration of the label above does not provide its form (`mockBindsAgain(receiving:beneath:)`): that binding hides
			// the farther declaration, as a declaration of the scope's type does. `receivesBoundAgainOfAnyBuild` gives the type's
			// level the same declarations.
			// A label the mock's root names apart has no declaration above, and every receive of it is bound again; a wrapper the
			// root binds apart is handed by name and never bound again (`PublicMockRootLevel.NamesApart`).
			if bindsReceivesAgain, level > 0, !isInFill {
				for dependency in instantiable.dependencies where !namesApartAtRoot.wrappers.contains(dependency.property) {
					let bindsAgain = if let nearest = nearestDeclarations[dependency.property.label] {
						DependencyTreeGenerator.mockBindsAgain(receiving: dependency, beneath: nearest.property)
					} else {
						dependency.source.isReceived && namesApartAtRoot.labels.contains(dependency.property.label)
					}
					guard bindsAgain else { continue }
					declare(declaration(of: dependency.property, isBoundBeforeSite: true))
				}
			}
			let pathPosition = frame.nextPosition - 1
			let pathProperty = frame.orderedChildren[pathPosition].generator.property
			// What a child declares does not depend on the site, but for where the site is among the children: each scope's are
			// found once across the sites through it, keyed by its generator. A scope on a site's path holds a place beneath it,
			// so no construction memo shares its generator between paths, and its level, its `@Sendable` depth and the path to
			// it are the same at every site through it.
			let childDeclarations = childDeclarationsByGenerator[ObjectIdentifier(frame.generator)] ?? ChildDeclarations(
				declarations: frame.orderedChildren.map { child -> PathDeclaration? in
					guard let childProperty = child.generator.property, level > 0 || !labelsNoRootChildDeclares.contains(childProperty.label) else { return nil }
					// A mock's root binds what it promotes as the non-optional value it builds.
					let property = level == 0 && bindsReceivesAgain ? mockRootBinding(ofChild: childProperty, isDependencyOfMockedType: { dependencies.dependencyByProperty[childProperty] != nil }) : childProperty
					// An `onlyIfAvailable` alias is bound, to `nil` where its fulfilling property is unavailable, as every other
					// child is. Whether it is bound before the site is the site's.
					var pathDeclaration = declaration(of: property, isBoundBeforeSite: false)
					// A public mock's root binds each received dependency it promotes, which it builds where its caller passes `nil`,
					// among the mocked type's own children.
					pathDeclaration.isBoundByPublicMockRoot = bindsReceivesAgain && level == 0
						&& !dependencies.labelsNotReceived.contains(property.label)
					let source = dependencies.dependencyByProperty[property]?.source
					if case let .aliased(fulfillingProperty, _, _)? = source {
						// An alias binds its label to `fulfillingProperty`: the seam's, to the caller's, and any other type's, to one
						// the seam's tree binds.
						pathDeclaration.alias = .init(fulfillingProperty: fulfillingProperty, isSeams: level == 0)
					} else if child.generator.receivedProperties.allSatisfy({ receivedLabels.contains($0.label) || $0.label == property.label }) {
						// A type above the seam can build what the tree instantiates when the seam's caller holds everything its
						// tree receives, or the tree receives what that type would then declare.
						pathDeclaration.treeBuildableAboveSeam = (child.generator, pathToFrame)
					}
					// A public mock's root child that the mocked type or a type in its tree receives, which the mock promoted, is
					// bound from the optional parameter `mock()` takes, which a calling mock passes its own nearest declaration of
					// the label.
					pathDeclaration.isBoundFromCallersArgument = bindsReceivesAgain && level == 0 && source?.isReceived ?? true
					return pathDeclaration
				},
				carrierProperties: frame.orderedChildren.compactMap { frame.generator.startsAsCarrier($0.generator) ? $0.generator.property : nil },
			)
			childDeclarationsByGenerator[ObjectIdentifier(frame.generator)] = childDeclarations
			let nextLoop = frame.generator.receivedBuilderLoops.loopByChildIndex[frame.orderedChildren[pathPosition].index]
			// The positions of the children by their unwrapped properties, which a child's receives only if available are matched by.
			var positionsByUnwrappedProperty = [Property: [Int]]()
			if draftsPlaceLevels {
				for (position, child) in frame.orderedChildren.enumerated() {
					if let property = child.generator.property {
						positionsByUnwrappedProperty[property.asUnwrappedProperty, default: []].append(position)
					}
				}
			}
			for (position, child) in frame.orderedChildren.enumerated() {
				guard var pathDeclaration = childDeclarations.declarations[position] else { continue }
				// The place graph drafts the child as it is before any next property, with what decides its facts before each.
				var drafted: PathDeclaration?
				if draftsPlaceLevels {
					let siblingsReceivedOnlyIfAvailable = child.generator.onlyIfAvailableUnwrappedReceivedProperties
						.flatMap { positionsByUnwrappedProperty[$0] ?? [] }
						.sorted()
						.compactMap { frame.orderedChildren[$0].generator.property }
					drafted = pathDeclaration
					drafted?.childFacts = SeamSignature.Places.ChildFacts(
						position: position,
						isBuilder: ScopeGenerator.isBuilder(pathDeclaration.property),
						loop: frame.generator.receivedBuilderLoops.loopByChildIndex[child.index],
						builtType: child.generator.builtInstantiable?.concreteInstantiable,
						isPlace: child.generator.holeSite != nil,
						receivesOnlyIfAvailable: siblingsReceivedOnlyIfAvailable,
						carriers: childDeclarations.firstTwoCarriers(among: child.generator.requiredReceivedProperties),
					)
				}
				let property = pathDeclaration.property
				// A member of the loop of builders the scope on the path is on (`ScopeGenerator.ReceivedBuilderLoops`) is still
				// being built where the loop's payloads are bound, before the loop's first function.
				let isLoopMemberBuildingSite = position < pathPosition
					&& frame.generator.areMembersOfOneLoop(childAt: child.index, frame.orderedChildren[pathPosition].index)
				pathDeclaration.isBoundBeforeSite = position < pathPosition && !isLoopMemberBuildingSite
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
					} else if let carrier = childDeclarations.firstCarrier(otherThan: pathProperty, among: child.generator.requiredReceivedProperties) {
						pathDeclaration.reason = .requiresOtherCarrier(type: childType, carrier: carrier)
					}
				} else if position > pathPosition, let pathProperty, child.generator.holeSite != nil {
					// A place, which builds no type the seam's module sees, is built after the scope on the path too.
					pathDeclaration.builtAfter = pathProperty
				}
				declare(pathDeclaration, drafted: drafted)
			}
			loopDeclaringInstantiable = instantiable
			loopDeclaringDependencies = dependencies
			endLevel(builtType: instantiable.concreteInstantiable, nextProperty: pathProperty, nextPosition: pathPosition, nextLoop: nextLoop)
		}
		// A `Sendable` wrapper the seam builds around the builder is built in a `@Sendable` function of its own, which binds
		// nothing.
		if site.property.propertyType.isSendable {
			sendableDepth += 1
			sendableFunctions.append((site.property, .other))
		}
		var fields = [SeamSignature.Hole.Field]()
		var uncarriedDeclarations = [SeamSignature.Hole.UncarriedDeclaration]()
		var pathFields = [Property]()
		var pathUncarriedProperties = [Property]()
		/// The field `declaration` is where it is bound before the site and inside the innermost `@Sendable` function on its path.
		func field(of declaration: PathDeclaration) -> SeamSignature.Hole.Field {
			SeamSignature.Hole.Field(
				property: declaration.property,
				access: declaration.access,
				accessCause: declaration.accessCause,
				declaringType: declaration.declaringType,
				declarationLocation: declaration.declarationLocation,
				isReceivedOnlyIfAvailable: declaration.isReceivedOnlyIfAvailable,
				parameterTakingType: declaration.parameterTakingType,
				deferral: declaration.deferral,
				isSeamParameter: declaration.frameLevel < 0,
				isBoundByPublicMockRoot: declaration.isBoundByPublicMockRoot,
				seamParameterOrigin: declaration.seamParameterOrigin,
			)
		}
		for label in labelsInBindingOrder {
			guard let declaration = nearestDeclarations[label] else { continue }
			if declaration.isBoundBeforeSite {
				pathFields.append(declaration.property)
				if declaration.sendableDepth == sendableDepth {
					fields.append(field(of: declaration))
				} else if declaration.frameLevel >= 0, let innermostFunction = sendableFunctions.last {
					// Bound in the seam's tree outside the innermost `@Sendable` function: a fill that reads it is reported. A
					// parameter of the seam is the caller's, which a fill reads from its own scope. So is a received value a
					// public mock binds at its root where the calling mock passes it its own: the fill of such a call reads the
					// caller's (`isBoundFromCallersArgument`).
					uncarriedDeclarations.append(markingBuildabilityAboveSeam(of: SeamSignature.Hole.UncarriedDeclaration(
						property: declaration.property,
						declaringType: declaration.declaringType,
						declarationLocation: declaration.declarationLocation,
						parameterTakingType: declaration.parameterTakingType,
						builtAfter: nil,
						reason: .boundOutsideSendableFunction(functionProperty: innermostFunction.property, function: innermostFunction.function, isForwarded: declaration.isForwarded, cycleParameter: declaration.cycleParameterOrigin, alias: declaration.alias),
						isBoundFromCallersArgument: declaration.isBoundFromCallersArgument,
					), as: declaration))
				}
			} else {
				pathUncarriedProperties.append(declaration.property)
				uncarriedDeclarations.append(markingBuildabilityAboveSeam(of: SeamSignature.Hole.UncarriedDeclaration(
					property: declaration.property,
					declaringType: declaration.declaringType,
					declarationLocation: declaration.declarationLocation,
					parameterTakingType: declaration.parameterTakingType,
					builtAfter: declaration.builtAfter,
					reason: declaration.reason,
				), as: declaration))
			}
		}
		// A scope on the path whose builder function a cycle-closing scope in its tree calls is built again there, and handed,
		// for each label a scope between the two declares, that declaration (`CycleParameter`). A label whose nearest
		// declaration at the site is inside the function, the function's own parameter of the label included, is bound again
		// at each level. Any other value a fill reads is the same at every level.
		var cycleReentryDeclarations = [SeamSignature.Hole.CycleReentryDeclaration]()
		for (level, generator, closedOnDeclaration, closedOnDeclaringType) in scopesACycleClosesOn {
			// Keyed by the generator's identity: a closed-on scope on a site's path holds a hole, so no construction memo
			// shares it between places.
			let declarationsBetween = declarationsBetweenByClosedOnScope[ObjectIdentifier(generator)] ?? declarationsBetween(closedOnScope: generator, closedOnDeclaration: closedOnDeclaration)
			declarationsBetweenByClosedOnScope[ObjectIdentifier(generator)] = declarationsBetween
			if let levelIndex = levelIndexByClosedOnFrameLevel[level], levelIndex < levels.count {
				levels[levelIndex].reentryDeclarations = declarationsBetween.map(\.property)
			}
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
					closedOnBuiltType: closedOnDeclaration.concreteType,
					closedOnDeclaringType: closedOnDeclaringType,
					reenteringType: between.reenteringType,
					placeIsInFurtherSendableFunction: sendableDepthByLevel[level].map { $0 < sendableDepth } ?? false,
				))
			}
		}
		// A hidden declaration counts where the fill's field stays the nearest declaration of its label, and the place's field.
		var declarationsHiddenByFields = [SeamSignature.Hole.DeclarationHiddenByField]()
		for field in fields {
			guard let (declaration, fieldLevel) = hiddenByFillFields[field.property.label], nearestDeclarations[field.property.label]?.frameLevel == fieldLevel else { continue }
			declarationsHiddenByFields.append(declaration)
		}
		// Each level of the path as the place graph holds it: its declarations with what a fill reader is told of them.
		let placeLevels = placeLevelsInProgress.map { level in
			SeamPlacesBuilder.LevelDraft(
				key: level.key,
				declarations: level.declarations.map { declaration in
					var buildability: SeamSignature.Places.Buildability?
					var placesInTree = [SeamSignature.Hole.Site]()
					if let tree = declaration.treeBuildableAboveSeam {
						buildability = SeamSignature.Places.Buildability(labelsHeldAboveSeam: receivedLabels.union([declaration.property.label]).sorted(), placesInTree: [])
						let treePath = tree.pathToDeclaringScope + [declaration.property]
						placesInTree = placesByTreePath[treePath] ?? places(inTreeOf: tree.generator, building: declaration.property, declaredAt: tree.pathToDeclaringScope, seamType: seam.concreteInstantiable)
						placesByTreePath[treePath] = placesInTree
					}
					let placeDeclaration = SeamSignature.Places.Declaration(
						field: field(of: declaration),
						isBoundBeforeNextProperty: declaration.isBoundBeforeSite,
						builtAfter: declaration.builtAfter,
						reason: declaration.reason,
						isForwarded: declaration.isForwarded,
						cycleParameterOrigin: declaration.cycleParameterOrigin,
						alias: declaration.alias,
						isBoundFromCallersArgument: declaration.isBoundFromCallersArgument,
						isCycleParameter: declaration.isCycleParameter,
						isReboundByBuilderFunction: declaration.isReboundByBuilderFunction,
						isFieldOfSeamParameter: declaration.isFieldOfSeamParameter,
						fillFieldHiding: declaration.fillFieldHiding,
						buildability: buildability,
					)
					return SeamPlacesBuilder.DeclarationDraft(
						declaration: declaration.childFacts.map(placeDeclaration.asChild) ?? placeDeclaration,
						placesInTree: placesInTree,
					)
				},
				opensSendableFunction: level.opensSendableFunction,
				fillBaseStack: level.fillBaseStack,
				fillOwnerType: level.fillOwnerType,
				pathSegment: level.pathSegment,
				pathTypes: level.pathTypes,
				declaredSegment: level.declaredSegment,
				nextPosition: level.nextPosition,
				nextLoop: level.nextLoop,
			)
		}
		return (fields, uncarriedDeclarations, cycleReentryDeclarations, levels.reversed(), pathFields, pathUncarriedProperties, declarationsHiddenByFields, placeLevels, sendableDepth > 0)
	}

	/// The sites of the places the tree `generator` roots holds, `generator` building `property` in the scope the properties
	/// `pathToDeclaringScope` lead to from the root of `seamType`'s tree, and of the places a call in it passes up, walking
	/// only the subtrees that hold one, each path spelled as `BuildSite.sitePath` spells it.
	static func places(inTreeOf generator: ScopeGenerator, building property: Property, declaredAt pathToDeclaringScope: [Property], seamType: TypeDescription) -> [SeamSignature.Hole.Site] {
		var places = [SeamSignature.Hole.Site]()
		var generatorsToVisit = [(generator: generator, path: pathToDeclaringScope + [property])]
		while let (visited, path) = generatorsToVisit.popLast() {
			if let holeSite = visited.holeSite {
				places.append(SeamSignature.Hole.Site(seamType: seamType, path: path.dropLast() + [holeSite.property]))
			}
			places += visited.passedUpHoles.map(\.site)
			// A fill whose code another fill of its case generates builds no site of its own (`buildSites(in:)`).
			for child in visited.children where child.containsBuildSite && child.fillEmitsCode || child.passesUpBuilder {
				generatorsToVisit.append((child, path + (child.fillHole?.pathBeforePropertyInItsFill ?? child.property.map { [$0] } ?? [])))
			}
		}
		return places
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
		/// For a declaration a cycle nested inside a scope between declares, which that scope's builder function is passed
		/// wherever a type in its tree receives the label, the type that scope builds; `nil` for a declaration on the path.
		var typeOfScopeNestedCyclePassesIt: TypeDescription?
	}

	/// The declarations met on the paths from one scope down to the scopes that close a cycle on a declaration above it.
	private struct DeclarationsToCycleClosingScopes {
		/// The first declaration of each label met: the paths in a depth-first walk in declaration order, and on each
		/// path the declarations from the cycle-closing scope up. Each with the type that instantiates the closed-on
		/// property again on its path.
		var declarations: [(declaration: DeclarationOnCyclePath, reenteringType: TypeDescription)]
		/// How many of `declarations` the first path holds, which come first.
		var countOnFirstPath: Int
		/// The type that instantiates the closed-on property again on the first path.
		let reenteringTypeOfFirstPath: TypeDescription
	}

	/// What `declarationsBetween(closedOnScope:closedOnDeclaration:)` has computed for one closed-on scope's tree, kept
	/// per scope generator: a generator a construction memo shares between places has the same subtree at each, so each
	/// is read once, however many paths lead to it.
	private struct DeclarationsBetweenMemo {
		/// For each scope a nested cycle closes on, what that cycle's scopes declare for the scope's builder function, with
		/// the declarations of the cycles nested deeper.
		var declarationsOfNestedCycles = [ObjectIdentifier: [DeclarationOnCyclePath]]()
		/// The same without the cycles nested deeper: what the paths themselves declare.
		var declarationsOnPathsOfNestedCycles = [ObjectIdentifier: [DeclarationOnCyclePath]]()
		var generators = [ObjectIdentifier: ScopeGenerator]()
	}

	/// The declarations the scopes beneath `scope` declare on the paths to the scopes that close a cycle on
	/// `closedOnDeclaration`, the first of each label: the paths in a depth-first walk in declaration order, and on each the
	/// nearest to the cycle-closing scope first. Each scope generator is read once: what its subtree declares on the way to
	/// such a scope is the same wherever it is built. Where `nestedCycles` is given, a scope between that a cycle nested
	/// inside closes on stands, just above its children, for each label that cycle declares again and the scope does not
	/// bind itself: inline, its function takes that label wherever its tree receives it, and what it builds beneath
	/// receives that parameter, which no declaration on the path shows.
	private static func declarationsToScopes(
		closingCycleOn closedOnDeclaration: ScopeGenerator.BuiltDeclaration,
		beneath scope: ScopeGenerator,
		building scopeType: TypeDescription,
		nestedCycles: [ObjectIdentifier: [DeclarationOnCyclePath]]?,
	) -> [(declaration: DeclarationOnCyclePath, reenteringType: TypeDescription)] {
		// `nil` for a generator no path beneath which reaches such a scope.
		var declarationsBeneath = [ObjectIdentifier: DeclarationsToCycleClosingScopes?]()
		/// What the paths through `children`, the children of a scope that builds `type` and declares `own`, nearest first,
		/// declare; `nil` when none reaches a scope that closes the cycle.
		func joined(_ children: [ScopeGenerator], of type: TypeDescription, declaring own: [DeclarationOnCyclePath]) -> DeclarationsToCycleClosingScopes? {
			var joined: DeclarationsToCycleClosingScopes?
			var labels = Set<String>()
			for child in children {
				let beneathChild: DeclarationsToCycleClosingScopes? = if child.closesPropertyCycle, child.closedOnDeclaration == closedOnDeclaration {
					DeclarationsToCycleClosingScopes(declarations: [], countOnFirstPath: 0, reenteringTypeOfFirstPath: type)
				} else {
					declarationsBeneath[ObjectIdentifier(child)] ?? nil
				}
				guard let beneathChild else { continue }
				if var joinedSoFar = joined {
					for declaration in beneathChild.declarations where labels.insert(declaration.declaration.declaration.property.label).inserted {
						joinedSoFar.declarations.append(declaration)
					}
					joined = joinedSoFar
				} else {
					// The first path: what it declares beneath this scope, then this scope's own, then the later paths' beneath.
					var first = DeclarationsToCycleClosingScopes(declarations: [], countOnFirstPath: 0, reenteringTypeOfFirstPath: beneathChild.reenteringTypeOfFirstPath)
					for declaration in beneathChild.declarations[..<beneathChild.countOnFirstPath] {
						labels.insert(declaration.declaration.declaration.property.label)
						first.declarations.append(declaration)
					}
					for declaration in own where labels.insert(declaration.declaration.property.label).inserted {
						first.declarations.append((declaration, beneathChild.reenteringTypeOfFirstPath))
					}
					first.countOnFirstPath = first.declarations.count
					for declaration in beneathChild.declarations[beneathChild.countOnFirstPath...] where labels.insert(declaration.declaration.declaration.property.label).inserted {
						first.declarations.append(declaration)
					}
					joined = first
				}
			}
			return joined
		}
		// A stack of its own, since a tree can be as deep as the module has types. Each generator is entered once, and
		// joined once its children are.
		var generatorsToVisit = scope.children.reversed().map { (generator: $0, isEntered: false) }
		var generatorsRead = 0
		while let (generator, isEntered) = generatorsToVisit.popLast() {
			let identifier = ObjectIdentifier(generator)
			if isEntered {
				guard let instantiable = generator.builtInstantiable else { continue }
				generatorsRead += 1
				var own = [DeclarationOnCyclePath]()
				var labelsBoundByScope = Set(generator.property.map { [$0.label] } ?? [])
				for declaration in declarationsBound(by: generator, includingForwardedProperties: true, reason: .other) {
					own.append(DeclarationOnCyclePath(declaration: declaration, parameterOfScope: nil))
					labelsBoundByScope.insert(declaration.property.label)
				}
				for parameter in generator.cycleParameters {
					own.append(DeclarationOnCyclePath(
						declaration: SeamSignature.Hole.UncarriedDeclaration(property: parameter.property, declaringType: instantiable.concreteInstantiable, declarationLocation: nil, builtAfter: nil, reason: .other),
						parameterOfScope: identifier,
					))
					labelsBoundByScope.insert(parameter.property.label)
				}
				var ownNearestFirst = [DeclarationOnCyclePath]()
				for var declaration in nestedCycles?[identifier] ?? [] where !labelsBoundByScope.contains(declaration.declaration.property.label) {
					declaration.typeOfScopeNestedCyclePassesIt = instantiable.concreteInstantiable
					ownNearestFirst.append(declaration)
				}
				ownNearestFirst += own.reversed()
				declarationsBeneath[identifier] = .some(joined(generator.children, of: instantiable.concreteInstantiable, declaring: ownNearestFirst))
			} else if declarationsBeneath[identifier] == nil {
				// A scope that closes a cycle builds nothing, and a fill in the tree is another seam's.
				if generator.closesPropertyCycle || generator.fillHole != nil || generator.builtInstantiable == nil {
					declarationsBeneath[identifier] = .some(nil)
				} else {
					generatorsToVisit.append((generator, true))
					generatorsToVisit.append(contentsOf: generator.children.reversed().map { ($0, false) })
				}
			}
		}
		GenerationWork.record(generatorsRead, by: .collectingDeclarationsOfACycle)
		return joined(scope.children, of: scopeType, declaring: [])?.declarations ?? []
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
	///
	/// The work grows with the scope generators of the tree and the cycles nested in it, never with the paths through
	/// them: sixteen screens that each build three others hold tens of thousands of paths.
	static func declarationsBetween(closedOnScope: ScopeGenerator, closedOnDeclaration: ScopeGenerator.BuiltDeclaration) -> [DeclarationBetween] {
		let closedOnProperty = closedOnDeclaration.property
		var ownLabels: Set<String> = [closedOnProperty.label]
		for declaration in declarationsBound(by: closedOnScope, includingForwardedProperties: true, reason: .other) {
			ownLabels.insert(declaration.property.label)
		}
		if closedOnScope.declaresCycleParameters {
			// A label the scope declares itself is no parameter of its function, so this removes only the parameters'.
			ownLabels.subtract(closedOnScope.cycleParameters.map(\.property.label))
		}
		// The scopes beneath that a nested cycle closes on, each after every such scope beneath it, whose cycles' labels its
		// own cycle's paths then read.
		var memo = DeclarationsBetweenMemo()
		var nestedClosedOnScopes = [ScopeGenerator]()
		var generatorsToVisit = closedOnScope.children.reversed().map { (generator: $0, isEntered: false) }
		while let (generator, isEntered) = generatorsToVisit.popLast() {
			if isEntered {
				nestedClosedOnScopes.append(generator)
			} else if memo.generators.updateValue(generator, forKey: ObjectIdentifier(generator)) == nil, !generator.closesPropertyCycle, generator.fillHole == nil {
				if generator.declarationACycleClosesOn != nil, generator.builtInstantiable != nil {
					generatorsToVisit.append((generator, true))
				}
				generatorsToVisit.append(contentsOf: generator.children.reversed().map { ($0, false) })
			}
		}
		for nestedScope in nestedClosedOnScopes {
			guard let declaration = nestedScope.declarationACycleClosesOn, let type = nestedScope.builtInstantiable?.concreteInstantiable else { continue }
			memo.declarationsOfNestedCycles[ObjectIdentifier(nestedScope)] = declarationsToScopes(
				closingCycleOn: declaration,
				beneath: nestedScope,
				building: type,
				nestedCycles: memo.declarationsOfNestedCycles,
			).map(\.declaration)
		}
		return declarationsToScopes(
			closingCycleOn: closedOnDeclaration,
			beneath: closedOnScope,
			building: closedOnDeclaration.concreteType,
			nestedCycles: memo.declarationsOfNestedCycles,
		).compactMap { pathDeclaration, reenteringType in
			guard !ownLabels.contains(pathDeclaration.declaration.property.label) else { return nil }
			// A nested cycle's parameter is bound by a declaration beneath the scope that takes it, so the chain ends.
			var binding = pathDeclaration
			while let scopeIdentifier = binding.parameterOfScope, let scope = memo.generators[scopeIdentifier],
			      let declaration = scope.declarationACycleClosesOn, let type = scope.builtInstantiable?.concreteInstantiable
			{
				let declarationsOnPaths = memo.declarationsOnPathsOfNestedCycles[scopeIdentifier]
					?? declarationsToScopes(closingCycleOn: declaration, beneath: scope, building: type, nestedCycles: nil).map(\.declaration)
				memo.declarationsOnPathsOfNestedCycles[scopeIdentifier] = declarationsOnPaths
				guard let next = declarationsOnPaths.first(where: { $0.declaration.property.label == binding.declaration.property.label }) else { break }
				binding = next
			}
			return DeclarationBetween(
				property: binding.declaration.property,
				declaringType: binding.declaration.declaringType,
				declarationLocation: binding.declaration.declarationLocation,
				parameterTakingType: pathDeclaration.parameterOfScope.map { _ in pathDeclaration.declaration.declaringType } ?? pathDeclaration.typeOfScopeNestedCyclePassesIt,
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
	/// tree meets, the fills the root's module generates included. A fill that is itself a call of a seam hands that
	/// call's holes to the root too, at every depth: the walk judges them when it reaches the fill, depth first, in the
	/// order each call takes its builders, so a hole the root's own seam calls leave unfilled keeps the property and
	/// chain it was reported at before.
	/// - Parameters:
	///   - viewInstantiablesByModuleName: The declarations of the modules the root's module reads only through
	///     module info views, by module, among which a module on the way to the hole may fulfill it.
	///   - isOwnFile: Whether a file is one of the module's own files, `nil` when every root is the module's own. Only
	///     a root the module generates has the calls of its fills judged: another module's root was judged by its own
	///     module, whose run fills what this run's view of it may not see.
	static func validateRootsFillEveryHole(
		roots: [Scope],
		callerModuleName: String?,
		instantiables: [TypeDescription: Instantiable],
		viewInstantiablesByModuleName: [String: [Instantiable]],
		isReadableFile: (@Sendable (String) -> Bool)?,
		isOwnFile: (@Sendable (String) -> Bool)?,
	) throws {
		var unfilledHoles = [DependencyTreeGeneratorError.UnfilledHole]()
		for root in roots {
			let judgesCallsOfFills = isOwnFile.map { isOwnFile in root.instantiable.sourceFilePath.map(isOwnFile) == true } ?? true
			var reportedDeclarations = Set<HoleDeclaration>()
			var visitedScopes = Set<ObjectIdentifier>()
			// Each scope to visit with the chain of types to it and the root's dependency through which the tree reaches it.
			var scopesToVisit: [(scope: Scope, chain: [TypeDescription], rootDependency: Dependency?)] = [(root, [root.instantiable.concreteInstantiable], nil)]
			while let (scope, chain, rootDependency) = scopesToVisit.popLast() {
				guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
				var childrenToVisit = [(scope: Scope, chain: [TypeDescription], rootDependency: Dependency?)]()
				/// Judges each hole `call` takes, reached along `callChain` through `callRootDependency`: a fill's scope is
				/// visited after the call's, and a hole passed up is reported.
				func judgeHoles(of call: Scope, callChain: [TypeDescription], callRootDependency: Dependency?) {
					for holeArgument in call.holeArguments {
						let hole = holeArgument.hole
						// The first property on the way is the called seam's, which `callChain` ends with.
						let holeChain = callChain + (hole.passedUpRoute + hole.declaredSitePath).dropFirst().compactMap(\.declaringType)
						switch holeArgument {
						case let .fill(_, fulfillingScope):
							childrenToVisit.append((fulfillingScope, holeChain + [fulfillingScope.instantiable.concreteInstantiable], callRootDependency))
						case .passUp:
							guard !hole.builtType.isOptional, reportedDeclarations.insert(HoleDeclaration(owner: hole.ownerType, property: hole.property)).inserted else { continue }
							// The tree reaches only what the root's module lists, so a module on the way to the hole that it does not
							// list stops the walk before it meets the hole's type, and a declaration of that type gets no scope.
							let unlistedModuleNames = hole.typesToOwner
								.filter { instantiables[$0.type]?.moduleName != $0.moduleName }
								.compactMap(\.moduleName)
								.uniqued()
							unfilledHoles.append(DependencyTreeGeneratorError.UnfilledHole(
								hole: hole,
								// The seam that declares the place takes it under its own root enum's builder for the place's hole type and
								// family, which the called seam's signature carries; the label the called seam takes it under can be one it
								// named apart from its other places, which no other initializer takes.
								builderLabel: call.calledBuilders?.enumsByKey[SeamSignature.ScopeEnum.rootKey(of: hole)]?.builderLabel ?? hole.builderLabel,
								rootType: root.instantiable.concreteInstantiable,
								chain: holeChain,
								location: callRootDependency?.declarationLocation,
								noteLocation: hole.declarationLocation.flatMap { location in isReadableFile.map { $0(location.filePath) } ?? true ? location : nil },
								callerModuleName: callerModuleName,
								unlistedModuleNames: unlistedModuleNames,
								unreachedFulfillingType: unlistedModuleNames.isEmpty ? nil : fulfillingType(of: hole, seenThroughListing: unlistedModuleNames, in: instantiables, viewInstantiablesByModuleName: viewInstantiablesByModuleName),
								fulfilledByMockOnlyDeclaration: instantiables[hole.instantiatedType]?.mockOnly == true,
							))
						}
					}
				}
				// A scope this walk visits that is a seam call is a fill, since a call reached as a child is judged, never
				// visited: the fill's call takes holes of its own, which the root fills or reports.
				if judgesCallsOfFills, scope.seamCall != nil {
					judgeHoles(of: scope, callChain: chain, callRootDependency: rootDependency)
				}
				for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
					let childRootDependency = rootDependency ?? root.instantiable.dependencies.first { $0.property == property }
					let childChain = chain + [childScope.instantiable.concreteInstantiable]
					judgeHoles(of: childScope, callChain: childChain, callRootDependency: childRootDependency)
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
		/// The label the generated initializer of the seam that declares the place takes its builder under.
		let builderLabel: String
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
			let takenBuilder = hole.enumPlace.map { "`\(builderLabel)`, whose member `\($0.caseName)` builds `\(hole.property.label)`" } ?? "`\(builderLabel)`, which builds `\(hole.property.label)`"
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
	/// generated outside the seam's module cannot refer to. Each finding once, by kind and location: the findings of several
	/// fills that differ only in the places they name are one that names every such place (`FillFinding.adding(_:to:)`),
	/// since the place declared first is a fact of file names; findings that differ otherwise are each reported, none picked,
	/// in the order `FillFinding.precedesInSourceOrder` gives, which includes the file of each place. A finding about a
	/// mock's code alone is reported only where the build compiles the generated mocks (`compilesGeneratedMocks`): a build
	/// that leaves the mock condition inactive never compiles it.
	static func validateFills(
		inTreesRootedAt generators: [ScopeGenerator],
		callerModule: ModuleIdentity,
		compilesGeneratedMocks: Bool = true,
	) throws {
		// EXPERIMENT: the graph judge reports.
		let findings = fillFindings(inTreesRootedAt: generators, callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, byCase: true)
		// Test only, deleted before merge: the same findings judged once per case and answer, for the tests' oracle, which
		// rides on the levels' observer (`FillCaseJudgementComparison`).
		if let observer = SeamPlaceLevels.observer {
			let byCase = fillFindings(inTreesRootedAt: generators, callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, byCase: true)
			var observation = SeamPlaceLevels(seamType: .simple(name: "", generics: []), places: [])
			// In the order the error prints them (`DependencyTreeGeneratorError.fillFindings`), which no judge's order decides.
			func printed(_ findings: [DependencyTreeGeneratorError.FillFinding]) -> [String] {
				findings.sorted { $0.precedesInSourceOrder($1) }.flatMap(\.sourceDiagnostics).map(\.formatted)
			}
			observation.fillJudgement = .init(perPlace: printed(findings), byCase: printed(byCase))
			observer(observation)
		}
		if !findings.isEmpty {
			throw DependencyTreeGeneratorError.fillFindings(findings)
		}
	}

	/// EXPERIMENT (F2 step 2): `byCase` judges one representative place per case and per distinct answer.
	static func fillFindings(
		inTreesRootedAt generators: [ScopeGenerator],
		callerModule: ModuleIdentity,
		compilesGeneratedMocks: Bool,
		byCase: Bool,
	) -> [DependencyTreeGeneratorError.FillFinding] {
		// The findings of each key, in the order the keys are first met, those that differ only in the places they name merged.
		var keys = [String]()
		var findingsByKey = [String: [DependencyTreeGeneratorError.FillFinding]]()
		// Of the findings of a cycle a fill closes on the seam's path, one per case, closer, declaration closed on and depth beneath
		// it (`FillFinding.closer`): the one whose route to the place comes first in source order, by where the declarations
		// along it are, never by a name. The places of a case that reach the declaration at one depth differ only in the route
		// the message names, and one fix clears them all; a place that reaches it at another depth keeps a finding of its own,
		// whose remedy can differ. Kept apart until every fill is judged, so the route kept never follows the order they come in.
		var leastFindingByCloser = [DependencyTreeGeneratorError.FillFinding.Closer: DependencyTreeGeneratorError.FillFinding]()
		func record(_ finding: DependencyTreeGeneratorError.FillFinding) {
			if let closer = finding.closer {
				if let least = leastFindingByCloser[closer], least.precedesInSourceOrder(finding) {
					return
				} else {
					leastFindingByCloser[closer] = finding
				}
			} else {
				recordMerging(finding)
			}
		}
		func recordMerging(_ finding: DependencyTreeGeneratorError.FillFinding) {
			if let findings = findingsByKey[finding.key] {
				findingsByKey[finding.key] = DependencyTreeGeneratorError.FillFinding.adding(finding, to: findings)
			} else {
				keys.append(finding.key)
				findingsByKey[finding.key] = [finding]
			}
		}
		// A seam's two forms of a label are one finding however many of its fills read the label (`SeamTreeReceives`): each fill
		// records it with no receivers, which `record` merges into one, completed once every fill is walked.
		var seamTreeReceives = SeamTreeReceives()
		var walkWork = 0
		defer { GenerationWork.record(walkWork, by: .walkingTreeForFills) }
		// A tree that holds no call of another module's seam or public mock, and no fill, has nothing to judge.
		for root in generators where root.treeHoldsCallOrFill {
			// Each generator with what the calls inside every fill of its seam call hide from it, when it is such a fill, the
			// children of its parent, which are the fills of that call, and what the calls inside the fills of public mock calls
			// enclosing it hide from the fills of public mock calls nested in those fills (`inheritedCalledCopyDeclarations`).
			// A fill that stands for another place's (`ScopeGenerator.FillStoodFor`) is visited once more for that place, with
			// the place's own hole and what the calls hide from its own key, where the place's own fill would be.
			var generatorsToVisit = [(generator: root, hidden: FillReentryHidings?.none, call: ScopeGenerator?.none, isFillOfPublicMockCall: false, inheritedCalledCopyDeclarations: [String: [SeamSignature.Hole.UncarriedDeclaration]](), placeStoodFor: SeamSignature.Hole?.none)]
			while let (generator, hidden, call, isFillOfPublicMockCall, inheritedCalledCopyDeclarations, placeStoodFor) = generatorsToVisit.popLast() {
				if !byCase, let hole = placeStoodFor ?? generator.fillHole, let child = generator.children.first, let call {
					findingsOfFill(of: hole, fill: generator, reads: FillTreeReads(walking: child), call: call, hidden: hidden ?? FillReentryHidings(), requirement: AccessLevel.required(toConstructFrom: callerModule, declaredIn: hole.scopeSeamModule, isOwnFile: false), callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives).forEach(record)
				}
				// A seam call's children are its fills, which are judged against the calls inside any of them. A public mock's call
				// inside one of its fills that re-enters a level function the call declares hands it only what that call reads of its
				// own scope (`PublicMockLevelFunctions.Reentry`), the nearest declaration inline reads, so the declarations on the path
				// to it hide nothing; but the called mock's copy of the place leaves uncarried what that mock binds on its way to the
				// place, which no scope of the caller holds, as the twin's seam call does.
				let hiddenByFillKey: [String: FillReentryHidings] = if generator.seamCall != nil {
					hiddenByReenteringCalls(ofFillsOf: generator)
				} else if generator.publicMockCall != nil {
					hiddenByReenteringCalls(ofFillsOf: generator).mapValues { FillReentryHidings(calledCopyDeclarations: $0.calledCopyDeclarations) }
				} else {
					[:]
				}
				if generator.seamCall != nil {
					findingsOfCasesNestedByType(filledBy: generator.children, standingFor: generator.fillsStoodFor, calledBuilders: byCase ? generator.calledBuilders : nil, callerModule: callerModule).forEach(record)
				}
				// A public mock call nested in a fill of an enclosing public mock call hands its own fills what they read of the
				// caller's scope from that enclosing fill's, which the calls inside the enclosing call's fills that re-enter it hand
				// only the caller's values: so the fills of the nested call are hidden what the called mocks' copies of the
				// re-entered place leave uncarried, as the enclosing fill is, of each label no scope between declares and their own
				// calls hide nothing of: a fill declares the fields it binds, and any other scope what
				// `declarationsBound(by:includingForwardedProperties:reason:)` says it binds.
				var childInheritedCalledCopyDeclarations = inheritedCalledCopyDeclarations
				if isFillOfPublicMockCall, let hidden {
					for (label, declarations) in hidden.calledCopyDeclarations where childInheritedCalledCopyDeclarations[label] == nil {
						childInheritedCalledCopyDeclarations[label] = declarations
					}
				}
				let declaredLabels = if let fillHole = generator.fillHole {
					// A field the fill takes of the caller's scope for a call inside it that re-enters the call is no declaration.
					generator.fillBoundFields.map(\.property.label).filter { label in fillHole.fields.contains { $0.property.label == label } }
				} else {
					declarationsBound(by: generator, includingForwardedProperties: true, reason: .other).map(\.property.label)
				}
				for label in declaredLabels {
					childInheritedCalledCopyDeclarations[label] = nil
				}
				walkWork += 1 + generator.children.count + declaredLabels.count + childInheritedCalledCopyDeclarations.count
				// The children in the order the call's arguments list their places: each place a fill stands for after the fills
				// built before it.
				var childrenToVisit = [(child: ScopeGenerator, placeStoodFor: ScopeGenerator.FillStoodFor?)]()
				let fillsStoodFor = generator.fillsStoodFor
				if fillsStoodFor.isEmpty {
					childrenToVisit = generator.children.map { ($0, nil) }
				} else {
					let standInByKey = Dictionary(generator.children.compactMap { child in child.fillKey.map { ($0, child) } }, uniquingKeysWith: { first, _ in first })
					var nextStoodForIndex = 0
					var builtFillCount = 0
					func appendPlacesStoodFor() {
						while nextStoodForIndex < fillsStoodFor.count, fillsStoodFor[nextStoodForIndex].builtFillCountBefore <= builtFillCount {
							if let standIn = standInByKey[fillsStoodFor[nextStoodForIndex].standInKey] {
								childrenToVisit.append((standIn, fillsStoodFor[nextStoodForIndex]))
							}
							nextStoodForIndex += 1
						}
					}
					for child in generator.children {
						if child.fillKey != nil {
							appendPlacesStoodFor()
							builtFillCount += 1
						}
						childrenToVisit.append((child, nil))
					}
					appendPlacesStoodFor()
				}
				func hiddenOf(_ child: ScopeGenerator, _ stoodFor: ScopeGenerator.FillStoodFor?) -> FillReentryHidings? {
					var childHidden = (stoodFor?.key ?? child.fillKey).flatMap { hiddenByFillKey[$0] }
					if generator.publicMockCall != nil, child.fillHole != nil, !childInheritedCalledCopyDeclarations.isEmpty {
						var merged = childHidden ?? FillReentryHidings()
						for (label, declarations) in childInheritedCalledCopyDeclarations where merged.calledCopyDeclarations[label] == nil {
							merged.calledCopyDeclarations[label] = declarations
						}
						childHidden = merged
					}
					return childHidden
				}
				if byCase {
					caseJudgement(of: childrenToVisit.filter(\.child.treeHoldsCallOrFill).compactMap { child, stoodFor in
						guard let hole = stoodFor?.hole ?? child.fillHole, child.children.first != nil else { return nil }
						return CaseJudgementEntry(hole: hole, fill: child, hidden: hiddenOf(child, stoodFor) ?? FillReentryHidings())
					}, call: generator, callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives).forEach(record)
				}
				generatorsToVisit.append(contentsOf: childrenToVisit.reversed().filter(\.child.treeHoldsCallOrFill).map { child, stoodFor in
					(child, hiddenOf(child, stoodFor), generator, generator.publicMockCall != nil && child.fillHole != nil, childInheritedCalledCopyDeclarations, stoodFor?.hole)
				})
			}
		}
		for finding in leastFindingByCloser.values.sorted(by: { $0.precedesInSourceOrder($1) }) {
			recordMerging(finding)
		}
		// Every finding of a key that differs from the others in more than the places it names: each is a fact of its own, with
		// a remedy of its own, so none is picked.
		return keys.flatMap { findingsByKey[$0] ?? [] }.map(seamTreeReceives.completing)
	}

	struct CaseJudgementEntry {
		let hole: SeamSignature.Hole
		let fill: ScopeGenerator
		let hidden: FillReentryHidings
	}

	/// EXPERIMENT: the places of each case of one call judged by the place graph of the seam whose tree holds them
	/// (`CalledBuilders.holdingCase(ofSite:in:)`), the call's own for a case of the called seam's own places: the tree of the
	/// case's emitting fill (`ScopeGenerator.fillJudgementTree`, else the fill) once per label it reads and per joint value the
	/// case's routes read of that label (`SeamSignature.Places.Query.labelVariants(ofLabel:at:)`), each against the emitting
	/// place with that label's facts and naming route the variant's. A cycle a fill closes on the seam's path is judged by the
	/// graph's depths for a case of the called seam's own places, and at each place for a place the call passes up, whose
	/// path runs through the seams that pass it up. A case some of whose places have no holding case, and every case of a call
	/// with no graph, is judged per label by place.
	private static func caseJudgement(of entries: [CaseJudgementEntry], call: ScopeGenerator, callerModule: ModuleIdentity, compilesGeneratedMocks: Bool, seamTreeReceives: inout SeamTreeReceives) -> [DependencyTreeGeneratorError.FillFinding] {
		guard let calledBuilders = call.calledBuilders, !calledBuilders.places.cases.isEmpty else {
			return placeCaseJudgement(of: entries, call: call, callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives)
		}
		let callQuery = calledBuilders.placesQuery
		// The first site of the call's places of each case, in the call's graph and in the graph of the seam whose tree holds
		// the place, found the first time a declaration's buildability asks.
		var siteByHoldingCase: [HoldingCaseKey: SeamSignature.Hole.Site]?
		func site(ofCase holding: SeamSignature.Places.Query.ResolvedCase) -> SeamSignature.Hole.Site? {
			if siteByHoldingCase == nil {
				var sites = [HoldingCaseKey: SeamSignature.Hole.Site]()
				for hole in calledBuilders.holes {
					guard let caseIndex = calledBuilders.caseIndexBySite[hole.site] else { continue }
					let keys = [HoldingCaseKey(graph: ObjectIdentifier(callQuery), caseIndex: caseIndex)] + [calledBuilders.holdingCase(ofSite: hole.site, in: callQuery).map(HoldingCaseKey.init)].compactMap(\.self)
					for key in keys where sites[key] == nil {
						sites[key] = hole.site
					}
				}
				siteByHoldingCase = sites
			}
			return siteByHoldingCase?[HoldingCaseKey(holding)]
		}
		var groupKeys = [String]()
		var groups = [String: [CaseJudgementEntry]]()
		for (index, entry) in entries.enumerated() {
			let key = entry.hole.enumPlace != nil ? ScopeGenerator.fillCaseKey(of: entry.hole) : "#\(index)"
			if groups[key] == nil {
				groupKeys.append(key)
			}
			groups[key, default: []].append(entry)
		}
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		for key in groupKeys {
			guard let group = groups[key] else { continue }
			// Every place of a case is held by one seam's tree, whose graph answers them all.
			guard let holdingCases = calledBuilders.holdingCases(ofSites: group.map(\.hole.site), in: callQuery),
			      let query = holdingCases.first?.query,
			      holdingCases.allSatisfy({ $0.query === query })
			else {
				findings += placeCaseJudgement(of: group, call: call, callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives)
				continue
			}
			let caseIndices = holdingCases.map(\.caseIndex)
			let isPassedUp = query !== callQuery
			guard let emitting = group.first(where: { $0.fill.fillEmitsCode }) ?? group.first, let child = (emitting.fill.fillJudgementTree ?? emitting.fill).children.first else { continue }
			let reads = FillTreeReads(walking: child, recordsOpenScopes: !isPassedUp)
			// The case of the call's own graph each holding case's first place has, which a passed-up place's reads past the calls
			// that present it are asked at.
			var callCaseIndexByHoldingCase = [Int: Int]()
			for entry in group {
				if let holdingCaseIndex = calledBuilders.holdingCase(ofSite: entry.hole.site, in: callQuery)?.caseIndex, callCaseIndexByHoldingCase[holdingCaseIndex] == nil {
					callCaseIndexByHoldingCase[holdingCaseIndex] = calledBuilders.caseIndexBySite[entry.hole.site]
				}
			}
			// The case's own place names its builder, of its own family.
			func casePlace(at caseIndex: Int) -> SeamSignature.Hole {
				group.first { calledBuilders.holdingCase(ofSite: $0.hole.site, in: callQuery)?.caseIndex == caseIndex }?.hole ?? emitting.hole
			}
			// A cycle a fill of a place the call passes up closes is judged at each place, whose path runs through the seams that
			// pass it up, past the graph of the seam whose tree holds it.
			if isPassedUp {
				for entry in group {
					guard let entryChild = entry.fill.children.first else { continue }
					findings += findingsOfFill(of: entry.hole, fill: entry.fill, reads: FillTreeReads(walking: entryChild).keeping {
						if case .closer = $0 {
							true
						} else {
							false
						}
					}, call: call, hidden: entry.hidden, requirement: AccessLevel.required(toConstructFrom: callerModule, declaredIn: entry.hole.scopeSeamModule, isOwnFile: false), callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives)
				}
			}
			// The entries of the seam's path a scope of the fill closes a cycle on where a route's path holds one: its property
			// as cycle validation sees it, built for its type, in each form a path stacks it in.
			func closedOnEntries(of property: Property, builtAs builtType: TypeDescription) -> [SeamSignature.Places.StackEntry] {
				let validated = property.asValidatedForDependencyCycles
				let instanceType = validated.typeDescription.unwrapped
				let forms = [validated] + [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].map { wrapper in
					let wrapperType = TypeDescription.simple(name: wrapper, generics: [instanceType])
					return Property(label: validated.label, typeDescription: validated.typeDescription.isOptional ? .optional(wrapperType) : wrapperType)
				}
				return forms.map { SeamSignature.Places.StackEntry(property: $0, concreteType: builtType) }
			}
			// A question past the query's state limit (`Places.Query.defaultStateLimit`) answers nothing here yet: no finding
			// names it.
			// The open scopes some route of the case closes a cycle at, whose subtrees those routes never build.
			var closingAtSomeRoute = Set<SeamSignature.Places.StackEntry>()
			for read in reads.reads {
				guard case let .openScope(scope) = read else { continue }
				for entry in closedOnEntries(of: scope.property, builtAs: scope.builtType) where caseIndices.contains(where: { !(query.depthsBelowOwner(ofProperty: entry.property, builtAs: entry.concreteType, at: $0) ?? []).isEmpty }) {
					closingAtSomeRoute.insert(entry)
				}
			}
			// One query per set of closing scopes a read is made beneath: it ranges over the routes that build it.
			var queriesByExclusion = [Set<SeamSignature.Places.StackEntry>: SeamSignature.Places.Query]()
			func closingEntriesAbove(_ ancestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor]) -> Set<SeamSignature.Places.StackEntry> {
				Set(ancestors.flatMap { closedOnEntries(of: $0.property, builtAs: $0.builtType) }).intersection(closingAtSomeRoute)
			}
			func excludingQuery(_ excluded: Set<SeamSignature.Places.StackEntry>) -> SeamSignature.Places.Query {
				guard !excluded.isEmpty else { return query }
				if let memoized = queriesByExclusion[excluded] {
					return memoized
				}
				let made = SeamSignature.Places.Query(of: query.places, excludingRoutesWhoseStackHolds: excluded)
				queriesByExclusion[excluded] = made
				return made
			}
			for read in reads.reads {
				guard case let .openScope(scope) = read else { continue }
				let scopeQuery = excludingQuery(closingEntriesAbove(scope.fillAncestors))
				for caseIndex in caseIndices {
					for entry in closedOnEntries(of: scope.property, builtAs: scope.builtType) where closingAtSomeRoute.contains(entry) {
						for (depth, route) in scopeQuery.depthsBelowOwner(ofProperty: entry.property, builtAs: entry.concreteType, at: caseIndex) ?? [] {
							let hole = routedHole(casePlace(at: caseIndex), along: route, in: scopeQuery)
							findings.append(.init(hole: hole, kind: .closesCycleInSeamTree(
								closingProperty: scope.property,
								closingType: scope.closingType,
								declarationLocation: scope.declarationLocation,
								fillAncestors: scope.fillAncestors,
								closedOnDeclaration: hole.declaredSitePath.dropLast(depth + 1).last,
								closesOnOwnerOfHole: depth == 0,
								seamModule: hole.scopeSeamModule,
							), closer: .init(
								caseKey: ScopeGenerator.fillCaseKey(of: hole),
								closingProperty: scope.property,
								closingType: scope.closingType,
								declarationLocation: scope.declarationLocation,
								closedOnDeclaration: ScopeGenerator.BuiltDeclaration(property: entry.property, concreteType: entry.concreteType),
								declarationsBeneath: depth,
							)))
						}
					}
				}
			}
			var labels = [String]()
			for read in reads.reads {
				if case let .receive(receive) = read, !labels.contains(receive.property.label) {
					labels.append(receive.property.label)
				}
			}
			// What the calls inside the call's fills hide from any place of the case: one fill fills them all.
			var hidden = FillReentryHidings()
			for entry in group {
				for (label, declarations) in entry.hidden.pathDeclarations {
					let known = Set((hidden.pathDeclarations[label] ?? []).map { String(describing: $0) })
					hidden.pathDeclarations[label, default: []] += declarations.filter { !known.contains(String(describing: $0)) }
				}
				for (label, declarations) in entry.hidden.calledCopyDeclarations where hidden.calledCopyDeclarations[label] == nil {
					hidden.calledCopyDeclarations[label] = declarations
				}
				for (label, fields) in entry.hidden.fieldsOfReenteringPlaces {
					hidden.fieldsOfReenteringPlaces[label, default: []] += fields.filter { !(hidden.fieldsOfReenteringPlaces[label] ?? []).contains($0) }
				}
			}
			// Whether the caller binds each form a called public mock binds from its argument: a fill's hole drops the declaration
			// where it does, and every fill of the call has the one scope above it.
			var callerBindsArgument = [Property: Bool]()
			for entry in group {
				guard let presented = calledBuilders.holes.first(where: { $0.site == entry.hole.site }) else { continue }
				for declaration in presented.uncarriedDeclarations where declaration.isBoundFromCallersArgument {
					callerBindsArgument[declaration.property] = !entry.hole.uncarriedDeclarations.contains(declaration)
				}
			}
			// A declaration the caller could build above the seam stays so only where the fill of each case its tree holds
			// receives only what the caller would hold there (`resolvingBuildabilityAboveSeam(fillsOfCall:)`, by case).
			func resolvingBuildability(_ declaration: SeamSignature.Hole.UncarriedDeclaration, _ answer: SeamSignature.Places.Answer) -> SeamSignature.Hole.UncarriedDeclaration {
				let graphDeclaration: SeamSignature.Places.Declaration? = switch answer {
				case let .uncarried(level, index), let .boundOutsideSendableFunction(level, index, _):
					query.places.declaration(level: level, declaration: index)
				case .field, .callersOwn:
					nil
				}
				guard declaration.isBuildableAboveSeam, let buildability = graphDeclaration?.buildability, !buildability.placesInTree.isEmpty else { return declaration }
				var resolved = declaration
				// The cases' fills, each judged at the case's first place the call holds.
				let fulfillingScopes = buildability.placesInTree.map { caseIndex in site(ofCase: .init(query: query, caseIndex: caseIndex)).flatMap { call.fill(judgingPlaceAt: $0)?.children.first } }
				resolved.holdsPlaceFilledElsewhere = fulfillingScopes.contains { $0 == nil }
				resolved.isBuildableAboveSeam = fulfillingScopes.allSatisfy { fulfillingScope in
					fulfillingScope?.receivedProperties.allSatisfy { declaration.labelsHeldAboveSeam.contains($0.label) } ?? false
				}
				return resolved
			}
			for label in labels {
				// The label's reads, by the closing scopes they are made beneath, in the order each set is first met.
				var exclusions = [Set<SeamSignature.Places.StackEntry>]()
				for read in reads.reads {
					guard case let .receive(receive) = read, receive.property.label == label else { continue }
					let excluded = closingEntriesAbove(receive.fillAncestors)
					if !exclusions.contains(excluded) {
						exclusions.append(excluded)
					}
				}
				for excluded in exclusions {
					let labelReads = reads.keeping {
						guard case let .receive(receive) = $0, receive.property.label == label else { return false }
						return closingEntriesAbove(receive.fillAncestors) == excluded
					}
					let labelQuery = excludingQuery(excluded)
					for caseIndex in caseIndices {
						for variant in labelQuery.labelVariants(ofLabel: label, at: caseIndex) ?? [] {
							// A read that leaves the holding seam's tree on a route with no re-entry of its own is read past each call that
							// presents the place, where a cycle around the call re-enters it as the per-site walk finds (`holesPassedUp`):
							// each such re-entry stands in the variant's place, as a place's own re-entry precedes its other facts.
							var reentries: [SeamSignature.Hole.CycleReentryDeclaration?] = [variant.cycleReentry]
							if isPassedUp, variant.cycleReentry == nil, let presentedReentries = callCaseIndexByHoldingCase[caseIndex].flatMap({ callQuery.presentedCycleReentryDeclarations(ofLabel: label, reading: variant.answer, at: $0) }), !presentedReentries.isEmpty {
								reentries = presentedReentries
							}
							for reentry in reentries {
								let hole = judgedHole(casePlace(at: caseIndex), ofLabel: label, as: variant, reentry: reentry, at: caseIndex, in: labelQuery, callerBindsArgument: callerBindsArgument, resolvingBuildability: resolvingBuildability)
								findings += findingsOfFill(of: hole, fill: emitting.fill, reads: labelReads, call: call, hidden: hidden, requirement: AccessLevel.required(toConstructFrom: callerModule, declaredIn: hole.scopeSeamModule, isOwnFile: false), callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives)
							}
						}
					}
				}
			}
		}
		return findings
	}

	/// EXPERIMENT: `hole`, a case's emitting place, as the place on `variant`'s least route reads `label`: that label's field,
	/// uncarried declaration and declaration hidden by a field are the variant's, its cycle re-entry is `reentry` (the
	/// variant's, or one a cycle around a call that presents the place hands it), and the place is named by the route.
	private static func judgedHole(_ hole: SeamSignature.Hole, ofLabel label: String, as variant: SeamSignature.Places.Query.LabelVariant, reentry: SeamSignature.Hole.CycleReentryDeclaration?, at caseIndex: Int, in query: SeamSignature.Places.Query, callerBindsArgument: [Property: Bool], resolvingBuildability: (SeamSignature.Hole.UncarriedDeclaration, SeamSignature.Places.Answer) -> SeamSignature.Hole.UncarriedDeclaration) -> SeamSignature.Hole {
		var fields = hole.fields.filter { $0.property.label != label }
		if case let .field(level, declaration) = variant.answer {
			fields.append(query.places.declaration(level: level, declaration: declaration).field)
		}
		// The place's own declaration of the label is the one the graph answers; the declarations a call on the way presents
		// besides (`boundByPassingUpSeam`, copies a called place carries) stay. A declaration some place of the case carries
		// keeps that place's buildability, which the graph's leaves out.
		func sameDeclaration(_ lhs: SeamSignature.Hole.UncarriedDeclaration, _ rhs: SeamSignature.Hole.UncarriedDeclaration) -> Bool {
			lhs.property == rhs.property && lhs.declaringType == rhs.declaringType && lhs.reason == rhs.reason
		}
		// A declaration a public mock's root binds from its caller's argument that a path to a call binds otherwise is
		// presented as that call's (`Places.Case.uncarriedReplacedOnPathsToCalls`).
		let replacements = query.places.cases[caseIndex].uncarriedReplacedOnPathsToCalls.filter { $0.property.label == label }
		let graphDeclarations = query.answers(ofLabel: label, at: caseIndex).compactMap { query.uncarriedDeclaration(of: $0, at: caseIndex) } + replacements
		let variantDeclaration = query.uncarriedDeclaration(of: variant.answer, at: caseIndex).map { graphDeclaration in
			graphDeclaration.isBoundFromCallersArgument ? replacements.first ?? graphDeclaration : resolvingBuildability(graphDeclaration, variant.answer)
		}.flatMap { declaration -> SeamSignature.Hole.UncarriedDeclaration? in
			// The fill reads the caller's own where the caller binds the form the called mock binds from its argument
			// (`Scope.fillUnderConstruction`).
			declaration.isBoundFromCallersArgument && callerBindsArgument[declaration.property] == true ? nil : declaration
		}
		var uncarriedDeclarations = [SeamSignature.Hole.UncarriedDeclaration]()
		var placedVariant = false
		for declaration in hole.uncarriedDeclarations {
			guard declaration.property.label == label, graphDeclarations.contains(where: { sameDeclaration($0, declaration) }) else {
				uncarriedDeclarations.append(declaration)
				continue
			}
			if !placedVariant, let variantDeclaration {
				uncarriedDeclarations.append(variantDeclaration)
			}
			placedVariant = true
		}
		if !placedVariant, let variantDeclaration {
			uncarriedDeclarations.append(variantDeclaration)
		}
		let cycleReentryDeclarations = hole.cycleReentryDeclarations.filter { $0.property.label != label } + [reentry].compactMap(\.self)
		let declarationsHiddenByFields = hole.declarationsHiddenByFields.filter { $0.property.label != label } + [variant.hiddenByField].compactMap(\.self)
		return routedHole(hole, along: variant.leastRoute, in: query, fields: fields, uncarriedDeclarations: uncarriedDeclarations, cycleReentryDeclarations: cycleReentryDeclarations, declarationsHiddenByFields: declarationsHiddenByFields)
	}

	/// EXPERIMENT: `hole`, a case's emitting place, named by `route`, with the facts given in place of its own.
	private static func routedHole(
		_ hole: SeamSignature.Hole,
		along route: SeamSignature.Places.Route,
		in query: SeamSignature.Places.Query,
		fields: [SeamSignature.Hole.Field]? = nil,
		uncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration]? = nil,
		cycleReentryDeclarations: [SeamSignature.Hole.CycleReentryDeclaration]? = nil,
		declarationsHiddenByFields: [SeamSignature.Hole.DeclarationHiddenByField]? = nil,
	) -> SeamSignature.Hole {
		let declaredSitePath = query.declaredPathToOwner(along: route) + hole.declaredSitePath.suffix(1)
		return SeamSignature.Hole(
			storing: hole.ownerType,
			declaringModuleNames: hole.declaringModuleNames,
			property: hole.property,
			instantiatedType: hole.instantiatedType,
			declarationLocation: hole.declarationLocation,
			erasedToConcreteExistential: hole.erasedToConcreteExistential,
			sitePath: query.sitePath(along: route),
			declaredSitePath: declaredSitePath,
			fillPropertyStack: hole.fillPropertyStack,
			fillConcreteTypeStack: hole.fillConcreteTypeStack,
			builderLabel: hole.builderLabel,
			narrowerTierBuilderLabels: hole.narrowerTierBuilderLabels,
			internalName: hole.internalName,
			scopeSeamType: hole.scopeSeamType,
			scopeSeamModule: hole.scopeSeamModule,
			typesToOwner: query.typesToOwner(along: route),
			scopeTypeName: hole.scopeTypeName,
			enumPlace: hole.enumPlace,
			wrapperFunctionName: hole.wrapperFunctionName,
			fields: fields ?? hole.fields,
			tierAccess: hole.tierAccess,
			accessCause: hole.accessCause,
			uncarriedDeclarations: uncarriedDeclarations ?? hole.uncarriedDeclarations,
			cycleReentryDeclarations: cycleReentryDeclarations ?? hole.cycleReentryDeclarations,
			reenteringCallDeclarations: hole.reenteringCallDeclarations,
			reenteringPlaceFields: hole.reenteringPlaceFields,
			declarationsHiddenByFields: declarationsHiddenByFields ?? hole.declarationsHiddenByFields,
			innerSeamType: hole.innerSeamType,
			passedUpRoute: hole.passedUpRoute,
			isSendable: hole.isSendable,
		)
	}

	/// EXPERIMENT: the places of each case of one call judged once per distinct answer, each answer by the place whose
	/// path sorts first in source order, against the tree of the case's emitted fill.
	private static func placeCaseJudgement(of entries: [CaseJudgementEntry], call: ScopeGenerator, callerModule: ModuleIdentity, compilesGeneratedMocks: Bool, seamTreeReceives: inout SeamTreeReceives) -> [DependencyTreeGeneratorError.FillFinding] {
		var groupKeys = [String]()
		var groups = [String: [CaseJudgementEntry]]()
		for (index, entry) in entries.enumerated() {
			let key = entry.hole.enumPlace != nil ? ScopeGenerator.fillCaseKey(of: entry.hole) : "#\(index)"
			if groups[key] == nil {
				groupKeys.append(key)
			}
			groups[key, default: []].append(entry)
		}
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		for key in groupKeys {
			guard let group = groups[key] else { continue }
			// Each label on its own: one representative per (label, what the place and its fill hold of that label, and the
			// tree's reads of it), the place whose path sorts first in source order. A closer is judged at every place, as the
			// graph's depths will judge it per route.
			var representatives = [LabelJudgementKey: (entry: CaseJudgementEntry, reads: FillTreeReads)]()
			var keys = [LabelJudgementKey]()
			for entry in group {
				guard let child = entry.fill.children.first else { continue }
				let reads = FillTreeReads(walking: child)
				// The tree's closers, and its receives by label in the order each label is first read, from one pass.
				var closers = [FillTreeReads.Read]()
				var labels = [String]()
				var receivesByLabel = [String: [FillTreeReads.Read]]()
				for read in reads.reads {
					switch read {
					case let .receive(receive):
						if receivesByLabel[receive.property.label] == nil {
							labels.append(receive.property.label)
						}
						receivesByLabel[receive.property.label, default: []].append(read)
					case .closer:
						closers.append(read)
					case .openScope:
						break
					}
				}
				findings += findingsOfFill(of: entry.hole, fill: entry.fill, reads: reads.with(closers), call: call, hidden: entry.hidden, requirement: AccessLevel.required(toConstructFrom: callerModule, declaredIn: entry.hole.scopeSeamModule, isOwnFile: false), callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives)
				for label in labels {
					let labelReads = reads.with(receivesByLabel[label] ?? [])
					let key = LabelJudgementKey(of: entry, label: label, reads: labelReads)
					if let known = representatives[key] {
						if entry.hole.declarationLocations.lexicographicallyPrecedes(known.entry.hole.declarationLocations, by: Dependency.DeclarationLocation.precedesInSourceOrder) {
							representatives[key] = (entry, labelReads)
						}
					} else {
						keys.append(key)
						representatives[key] = (entry, labelReads)
					}
				}
			}
			for key in keys {
				guard let (entry, reads) = representatives[key] else { continue }
				findings += findingsOfFill(of: entry.hole, fill: entry.fill, reads: reads, call: call, hidden: entry.hidden, requirement: AccessLevel.required(toConstructFrom: callerModule, declaredIn: entry.hole.scopeSeamModule, isOwnFile: false), callerModule: callerModule, compilesGeneratedMocks: compilesGeneratedMocks, seamTreeReceives: &seamTreeReceives)
			}
		}
		return findings
	}

	/// EXPERIMENT: what a place's judgement of one label reads, compared for meaning: the place's facts of the label, what
	/// its fill binds of it, and the tree's reads of it. Two places of one case with equal keys are judged alike but for the
	/// place a finding names, so one judgement serves both. Each fact is kept whole, its locations included, since a finding
	/// names them; a declaration on a path to a call that passes the fill on keeps only what a finding reads of it
	/// (`DeclarationOnPathToReenteringCall.reenteringCallDeclaration(reentering:fillingModule:)`).
	private struct LabelJudgementKey: Hashable {
		struct PathDeclaration: Hashable {
			let declaration: SeamSignature.Hole.UncarriedDeclaration
			let pathPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace
			let callingType: TypeDescription
			let callProperty: Property
			let calledSeam: TypeDescription
		}

		struct CycleReentryDeclaration: Hashable {
			let property: Property
			let declaringType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let parameterTakingType: TypeDescription?
			let closedOnProperty: Property
			let closedOnBuiltType: TypeDescription
			let closedOnDeclaringType: TypeDescription
			let reenteringType: TypeDescription
		}

		struct DeclarationHiddenByField: Hashable {
			let property: Property
			let declaringType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let calledSeam: TypeDescription
			let receivingSeam: TypeDescription
		}

		struct Receive: Hashable {
			let property: Property
			let readerType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let onlyIfAvailable: Bool
			let passingCall: DependencyTreeGeneratorError.FillFinding.PassingCall?
		}

		init(of entry: CaseJudgementEntry, label: String, reads: FillTreeReads) {
			let hole = entry.hole
			self.label = label
			fields = hole.fields.filter { $0.property.label == label }
			uncarriedDeclarations = hole.uncarriedDeclarations.filter { $0.property.label == label }
			cycleReentryDeclarations = hole.cycleReentryDeclarations.filter { $0.property.label == label }.map {
				CycleReentryDeclaration(property: $0.property, declaringType: $0.declaringType, declarationLocation: $0.declarationLocation, parameterTakingType: $0.parameterTakingType, closedOnProperty: $0.closedOnProperty, closedOnBuiltType: $0.closedOnBuiltType, closedOnDeclaringType: $0.closedOnDeclaringType, reenteringType: $0.reenteringType)
			}
			reenteringCallDeclarations = hole.reenteringCallDeclarations.filter { $0.property.label == label }
			reenteringPlaceFields = hole.reenteringPlaceFields.filter { $0.carried.field.property.label == label }
			declarationsHiddenByFields = hole.declarationsHiddenByFields.filter { $0.property.label == label }.map {
				DeclarationHiddenByField(property: $0.property, declaringType: $0.declaringType, declarationLocation: $0.declarationLocation, calledSeam: $0.calledSeam, receivingSeam: $0.receivingSeam)
			}
			pathDeclarations = entry.hidden.pathDeclarations[label]?.map {
				PathDeclaration(declaration: $0.declaration, pathPlace: .init($0.pathHole), callingType: $0.callingType, callProperty: $0.callProperty, calledSeam: $0.calledSeam)
			}
			calledCopyDeclarations = entry.hidden.calledCopyDeclarations[label]
			fieldsOfReenteringPlaces = entry.hidden.fieldsOfReenteringPlaces[label]
			// What the place's own fill binds in the field's place, which its generator, not the hole, says.
			memoOrigins = entry.fill.fillMemoOriginsByLabel[label]
			boundFields = entry.fill.fillBoundFields.filter { $0.property.label == label }
			receives = reads.reads.compactMap { read in
				guard case let .receive(receive) = read else { return nil }
				return Receive(property: receive.property, readerType: receive.readerType, declarationLocation: receive.declarationLocation, onlyIfAvailable: receive.onlyIfAvailable, passingCall: receive.passingCall)
			}
		}

		let label: String
		let fields: [SeamSignature.Hole.Field]
		let uncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration]
		let cycleReentryDeclarations: [CycleReentryDeclaration]
		let reenteringCallDeclarations: [SeamSignature.Hole.ReenteringCallDeclaration]
		let reenteringPlaceFields: [SeamSignature.Hole.ReenteringPlaceField]
		let declarationsHiddenByFields: [DeclarationHiddenByField]
		let pathDeclarations: [PathDeclaration]?
		let calledCopyDeclarations: [SeamSignature.Hole.UncarriedDeclaration]?
		let fieldsOfReenteringPlaces: [SeamSignature.Hole.FieldOfReenteringPlace]?
		let memoOrigins: [SeamSignature.Hole.Field.SeamParameterOrigin]?
		let boundFields: [SeamSignature.Hole.Field]
		let receives: [Receive]
	}

	/// The findings of the cases nested by type that `fills`, the children of one seam call's generator, fill: one function
	/// fills every place of such a case, so a value its tree reads that the places' routes hold in forms that differ in more
	/// than optionality (`ScopeGenerator.irreconcilableFields(of:)`) is one no parameter can take. Each label once per
	/// case, in label order. A case whose places the inner seam's two root enums both reach, whose fill's tree builds a place
	/// or passes one up, is one such function could hand only one of the two scope values its root enums' dispatchers hold
	/// (`placeInsideFillOfCaseOfBothRootEnums`).
	private static func findingsOfCasesNestedByType(filledBy fills: [ScopeGenerator], standingFor fillsStoodFor: [ScopeGenerator.FillStoodFor], calledBuilders: CalledBuilders?, callerModule: ModuleIdentity) -> [DependencyTreeGeneratorError.FillFinding] {
		var placesByCaseKey = [String: [SeamSignature.Hole]]()
		var emittingFillByCaseKey = [String: ScopeGenerator]()
		var caseKeys = [String]()
		// The places in the order of the call's arguments, each place a fill stands for after the fills built before it.
		var nextStoodForIndex = 0
		var builtFillCount = 0
		func appendPlacesStoodFor() {
			while nextStoodForIndex < fillsStoodFor.count, fillsStoodFor[nextStoodForIndex].builtFillCountBefore <= builtFillCount {
				let hole = fillsStoodFor[nextStoodForIndex].hole
				placesByCaseKey[ScopeGenerator.fillCaseKey(of: hole), default: []].append(hole)
				nextStoodForIndex += 1
			}
		}
		for fill in fills {
			guard let hole = fill.fillHole else { continue }
			appendPlacesStoodFor()
			builtFillCount += 1
			guard hole.enumPlace != nil else { continue }
			let caseKey = ScopeGenerator.fillCaseKey(of: hole)
			if placesByCaseKey[caseKey] == nil {
				caseKeys.append(caseKey)
			}
			placesByCaseKey[caseKey, default: []].append(hole)
			if fill.fillEmitsCode {
				emittingFillByCaseKey[caseKey] = fill
			}
		}
		appendPlacesStoodFor()
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		for caseKey in caseKeys {
			guard let places = placesByCaseKey[caseKey], let firstPlace = places.first, let child = emittingFillByCaseKey[caseKey]?.children.first else { continue }
			// EXPERIMENT: over every route of the place graph where the call holds one, a place the call passes up over the
			// routes of the graph of the seam whose tree holds it.
			let holdingCases = calledBuilders.flatMap { $0.places.cases.isEmpty ? nil : $0.holdingCases(ofSites: places.map(\.site), in: $0.placesQuery) }
			let irreconcilableFields = if let holdingCases {
				ScopeGenerator.irreconcilableFields(ofResolvedCases: holdingCases, hole: firstPlace)
			} else {
				ScopeGenerator.irreconcilableFields(of: places)
			}
			for label in irreconcilableFields.keys.sorted() {
				guard let fields = irreconcilableFields[label],
				      child.receivedProperties.contains(where: { $0.label == label }) || child.fieldsCarriedBySites.contains(where: { $0.label == label })
				else { continue }
				findings.append(.init(hole: firstPlace, kind: .fieldFormsDifferBetweenPlaces(label: label, fields: fields, seamModule: firstPlace.scopeSeamModule)))
			}
			// The fill takes the scope value the inner seam handed it (`Scope.Fill.innerScopeParameter`), which the dispatchers
			// that lead to the case pass on: a dispatcher both root enums reach could pass only one root enum's value. It takes
			// that value where its tree builds a place or a call that passes one up, which the walk finds, whatever kind of place
			// the call is to the place graph: a fulfilling call made in a `@Sendable` fill is a plain place there
			// (`SeamDeclarationGraph.placeHolding`), and its fill is reached from both root enums all the same.
			if let emittingFill = emittingFillByCaseKey[caseKey],
			   Set(places.map { SeamSignature.ScopeEnum.rootKey(of: $0).isSendable }).count > 1,
			   let place = firstPlaceBuilt(inFill: emittingFill)
			{
				findings.append(.init(hole: firstPlace, kind: .placeInsideFillOfCaseOfBothRootEnums(place: place, callerModule: callerModule, seamModule: firstPlace.scopeSeamModule)))
			}
		}
		return findings
	}

	/// The first place the tree of `fill` builds or a call in it passes up, in the order the tree declares them: the type that
	/// declares it and the property, or `nil` where the tree holds neither. The walk looks at the children of every generator
	/// it visits, the fill's own among them, so the fill's root, a call that passes a place up included, is looked at first,
	/// and the walk goes on into a fill nested in the tree, a generator that builds no type of its own, whose root it looks at
	/// as any other call.
	private static func firstPlaceBuilt(inFill fill: ScopeGenerator) -> DependencyTreeGeneratorError.FillFinding.PlaceInsideFill? {
		var generatorsToVisit = [fill]
		while let generator = generatorsToVisit.popLast() {
			for child in generator.children {
				// A site is a child of the type that declares its property; a fill's child is the type that fulfills it.
				if let site = child.holeSite, let instantiable = generator.builtInstantiable {
					let dependency = instantiable.dependencies.first { $0.property == site.property }
					return .init(ownerType: instantiable.concreteInstantiable, property: site.property, instantiatedType: dependency?.asInstantiatedType ?? site.property.typeDescription.asInstantiatedType, declarationLocation: dependency?.declarationLocation)
				} else if let passedUpHole = child.passedUpHoles.first {
					return .init(ownerType: passedUpHole.ownerType, property: passedUpHole.property, instantiatedType: passedUpHole.instantiatedType, declarationLocation: passedUpHole.declarationLocation)
				}
			}
			generatorsToVisit.append(contentsOf: generator.children.reversed())
		}
		return nil
	}

	/// What one fill's tree reads, in the order its walk meets them: each receive it resolves outside the fill and each scope
	/// that closes a cycle on a declaration of the filled seam's path. A fact of the tree alone, never of the place it fills,
	/// so places that share a fill's tree are judged from one walk (`findingsOfFill`), each against its own hole.
	struct FillTreeReads {
		/// A receive the tree resolves outside the fill: no scope above it in the fill provides it.
		struct Receive {
			let property: Property
			let readerType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let onlyIfAvailable: Bool
			/// The seam call the receive is made by, where a call in the fill passes it on to the seam's tree.
			let passingCall: DependencyTreeGeneratorError.FillFinding.PassingCall?
			/// EXPERIMENT: the scopes of the fill the receive is made beneath, its reader's own last: a route whose path builds
			/// one of them closes a cycle there and never reads it.
			let fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor]
		}

		/// EXPERIMENT: a scope of a tree built with none of its scopes closing a cycle on the seam's path
		/// (`ScopeGenerator.fillJudgementTree`), which closes one on a route whose path builds its property for its type.
		struct OpenScope {
			let property: Property
			let builtType: TypeDescription
			let closingType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor]
		}

		/// A scope of the tree that closes a cycle on a declaration of the filled seam's path. A closer beneath a fill nested in
		/// this one is that fill's, which `validateFills` reaches itself, and is not listed.
		struct Closer {
			let property: Property
			let closingType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor]
			let closedOnDeclaration: ScopeGenerator.BuiltDeclaration
		}

		enum Read {
			case receive(Receive)
			case closer(Closer)
			case openScope(OpenScope)
		}

		/// The reads, in walk order: each type before the types beneath it, siblings in declaration order.
		let reads: [Read]
		/// The root of the tree, which `firstReader(of:)` walks again only where a finding names a reader.
		private let root: ScopeGenerator

		/// EXPERIMENT: the reads of this tree that `isKept` keeps, in walk order.
		func keeping(_ isKept: (Read) -> Bool) -> FillTreeReads {
			FillTreeReads(reads: reads.filter(isKept), root: root)
		}

		/// EXPERIMENT: this tree with `reads`, some of its reads in walk order, as its reads.
		func with(_ reads: [Read]) -> FillTreeReads {
			FillTreeReads(reads: reads, root: root)
		}

		private init(reads: [Read], root: ScopeGenerator) {
			self.reads = reads
			self.root = root
		}

		init(walking root: ScopeGenerator, recordsOpenScopes: Bool = false) {
			self.root = root
			var reads = [Read]()
			typealias Frame = (generator: ScopeGenerator, parent: Instantiable, providedProperties: Set<Property>, fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor], judgesClosers: Bool)
			var framesToVisit = [Frame]()
			var work = 0
			defer { GenerationWork.record(work, by: .readingFillTrees) }
			func isProvided(_ property: Property, by providedProperties: Set<Property>) -> Bool {
				providedProperties.contains(property)
					|| (property.typeDescription.isOptional && providedProperties.contains(property.asUnwrappedProperty))
			}
			/// Records the receives of `generator`'s scope and queues the scopes beneath it. A fill nested in this one is no scope
			/// of its own: what it builds is judged for receives as this tree's, and its closers by `validateFills`.
			func visit(_ generator: ScopeGenerator, parent: Instantiable?, providedProperties: Set<Property>, fillAncestors: [DependencyTreeGeneratorError.FillFinding.FillAncestor], judgesClosers: Bool) {
				let childProvidedProperties = providedProperties.union(generator.providedProperties)
				work += 1 + generator.children.count + childProvidedProperties.count
				if let instantiable = generator.builtInstantiable {
					// A seam's call receives what it passes on to the seam's tree.
					let passingCall: DependencyTreeGeneratorError.FillFinding.PassingCall? = if generator.seamCall != nil, let parent, let property = generator.property {
						.init(callingType: parent.concreteInstantiable, property: property, declarationLocation: parent.dependencies.first { $0.property == property }?.declarationLocation)
					} else {
						nil
					}
					let childFillAncestors = fillAncestors + (generator.property.map { [DependencyTreeGeneratorError.FillFinding.FillAncestor(property: $0, builtType: instantiable.concreteInstantiable)] } ?? [])
					work += instantiable.dependencies.count + childFillAncestors.count
					for dependency in instantiable.dependencies {
						switch dependency.source {
						case let .received(onlyIfAvailable):
							guard !isProvided(dependency.property, by: providedProperties) else { continue }
							reads.append(.receive(.init(property: dependency.property, readerType: instantiable.concreteInstantiable, declarationLocation: dependency.declarationLocation, onlyIfAvailable: onlyIfAvailable, passingCall: passingCall, fillAncestors: childFillAncestors)))
						case let .aliased(fulfillingProperty, _, onlyIfAvailable):
							guard !isProvided(fulfillingProperty, by: childProvidedProperties) else { continue }
							reads.append(.receive(.init(property: fulfillingProperty, readerType: instantiable.concreteInstantiable, declarationLocation: dependency.declarationLocation, onlyIfAvailable: onlyIfAvailable, passingCall: nil, fillAncestors: childFillAncestors)))
						case .instantiated, .forwarded:
							continue
						}
					}
					framesToVisit.append(contentsOf: generator.children.reversed().map { ($0, instantiable, childProvidedProperties, childFillAncestors, judgesClosers) })
				} else if let parent {
					framesToVisit.append(contentsOf: generator.children.reversed().map { ($0, parent, childProvidedProperties, fillAncestors, judgesClosers && generator.fillHole == nil) })
				}
			}
			visit(root, parent: nil, providedProperties: [], fillAncestors: [], judgesClosers: true)
			while let (generator, parent, providedProperties, fillAncestors, judgesClosers) = framesToVisit.popLast() {
				if generator.closesPropertyCycle {
					// A scope in the fill that closes a cycle on a property of the seam's path refers to a builder function
					// the seam's initializer declares, which code generated outside the seam's module cannot refer to.
					if judgesClosers, generator.closesCycleOnFillPath, let property = generator.property, let closedOnDeclaration = generator.closedOnDeclaration {
						reads.append(.closer(.init(
							property: property,
							closingType: parent.concreteInstantiable,
							declarationLocation: parent.dependencies.first { $0.property == property }?.declarationLocation,
							fillAncestors: fillAncestors,
							closedOnDeclaration: closedOnDeclaration,
						)))
					}
				} else {
					if recordsOpenScopes, judgesClosers, let property = generator.property, let instantiable = generator.builtInstantiable {
						reads.append(.openScope(.init(
							property: property,
							builtType: instantiable.concreteInstantiable,
							closingType: parent.concreteInstantiable,
							declarationLocation: parent.dependencies.first { $0.property == property }?.declarationLocation,
							fillAncestors: fillAncestors,
						)))
					}
					visit(generator, parent: parent, providedProperties: providedProperties, fillAncestors: fillAncestors, judgesClosers: judgesClosers)
				}
			}
			self.reads = reads
		}

		/// The receive of `instance`, or of its optional form, in the tree declared first in source order, by the type
		/// that receives it: a receive of the label, or an alias whose fulfilling property is the instance, which the finding
		/// names by that property, as it names a reader through an alias.
		func firstReader(of instance: Property) -> DependencyTreeGeneratorError.FillFinding.InstanceReader? {
			var readers = [DependencyTreeGeneratorError.FillFinding.InstanceReader]()
			var generatorsToVisit = [root]
			while let generator = generatorsToVisit.popLast() {
				for dependency in generator.builtInstantiable?.dependencies ?? [] {
					let receivedProperty: Property? = switch dependency.source {
					case .received:
						dependency.property
					case let .aliased(fulfillingProperty, _, _):
						fulfillingProperty
					case .instantiated, .forwarded:
						nil
					}
					if let receivedProperty, receivedProperty.asUnwrappedProperty == instance, let type = generator.builtInstantiable?.concreteInstantiable {
						readers.append(.init(property: receivedProperty, type: type, declarationLocation: dependency.declarationLocation))
					}
				}
				generatorsToVisit.append(contentsOf: generator.children)
			}
			return readers.min { [$0.declarationLocation].lexicographicallyPrecedes([$1.declarationLocation], by: Dependency.DeclarationLocation.precedesInSourceOrder) }
		}
	}

	/// The findings of the fill of `hole` whose tree `reads` walked, in the order the tree declares them. A closer is judged
	/// by what generation found (`ScopeGenerator.closesCycleOnFillPath`), so only against the stack it was built
	/// with: the walk goes on into a fill nested in this one, whose receives fall through to this fill's fields, but a closer
	/// beneath it is that fill's, which `validateFills` reaches itself. This generator tree holds a seam the fill calls as a
	/// leaf, so a property re-entered through such a call is never judged here; the cycle walk of
	/// `validateCyclesFromRootsOfForeignSeamsWithHoles`, which inlines every seam, judges those.
	/// - Parameters:
	///   - fill: The fill's generator, whose fields say which memos it binds.
	///   - call: The seam call that declares this fill, whose fills decide whether a type above the seam can
	///     build a declaration whose tree holds the places they fill.
	///   - hidden: What the calls inside the fills of the seam call that declares this fill hide from it.
	///   - compilesGeneratedMocks: Whether the build compiles the generated mocks, where a finding about a mock's code alone
	///     is reported.
	///   - seamTreeReceives: The receives of each label and seam the fills walked so far gave, which this fill's walk adds to.
	private static func findingsOfFill(
		of hole: SeamSignature.Hole,
		fill: ScopeGenerator,
		reads: FillTreeReads,
		call: ScopeGenerator,
		hidden: FillReentryHidings,
		requirement: AccessRequirement,
		callerModule: ModuleIdentity,
		compilesGeneratedMocks: Bool,
		seamTreeReceives: inout SeamTreeReceives,
	) -> [DependencyTreeGeneratorError.FillFinding] {
		GenerationWork.record(reads.reads.count, by: .readingFillTrees)
		var findings = [DependencyTreeGeneratorError.FillFinding]()
		// The hole says which module declares each seam: this run may know a seam only through a module that calls it.
		let seamModule = hole.scopeSeamModule
		let fields = hole.fields
		/// Whether `property`, which a type in the fill's tree receives, is the hole's own property, or its instance.
		func isHolesOwnProperty(_ property: Property) -> Bool {
			[hole.property, hole.property.asLazilyInstantiatedInstanceProperty]
				.compactMap(\.self)
				.contains { $0 == property || $0 == property.asUnwrappedProperty }
		}
		/// Whether `field` gives a receive of `property` its value.
		func provides(_ field: SeamSignature.Hole.Field, _ property: Property) -> Bool {
			field.property == property
				|| (property.typeDescription.isOptional && field.property == property.asUnwrappedProperty)
				|| field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding.map { $0 == property || (property.typeDescription.isOptional && $0 == property.asUnwrappedProperty) } == true
		}
		/// Checks a receive the fill resolves from the caller's scope: a call inside a fill of a place that carries the
		/// label, which opens this fill's seam again, hands this fill the outer call's value, where inline the seam opened
		/// again sits beneath that place and reads its field, so the fill would read `nil` or another value than inline's.
		func checkReadFromCallersScope(of property: Property, by reader: DependencyTreeGeneratorError.FillFinding.Reader, onlyIfAvailable: Bool) {
			let carried = (hidden.fieldsOfReenteringPlaces[property.label] ?? []).filter { provides($0.field, property) }
			guard !carried.isEmpty else { return }
			findings.append(.init(hole: hole, kind: .fieldOfReenteringPlace(reader: reader, isOnlyIfAvailable: onlyIfAvailable, carried: carried, reenteredPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole), fillingModule: callerModule, seamModule: seamModule)))
		}
		/// Whether the fill binds a memo of the label of `property`, a `LazilyInstantiated` or `SendableLazilyInstantiated` it
		/// receives, of the wrapper's own kind, which the tree reads where it reads that wrapper. The fill binds the memo where
		/// its tree reads the memo's instance; a tree that reads only the wrapper reads the caller's scope. The seam whose fill
		/// this is asks the same of its parameters (`ScopeGenerator.fillBoundMemo(servingWrapperRead:)`).
		func readsMemoOfItsOwnKind(_ property: Property) -> Bool {
			fill.fillBoundMemo(servingWrapperRead: property) != nil
		}
		/// The declaration of the wrapper `property` that a field of its label, a parameter of a seam whose struct carries it, hides
		/// on the place's path, with that field, where `property` is a `LazilyInstantiated` or `SendableLazilyInstantiated` the
		/// declaration provides: the nearest such declaration a fill's field hides (`SeamSignature.Hole.declarationsHiddenByFields`),
		/// or the nearest a passing-up seam binds above its call that presents the place itself, which the place's own field of a
		/// parameter of its seam hides.
		func declarationHiddenByField(providing property: Property) -> (declaration: SeamSignature.Hole.DeclarationHiddenByField, field: SeamSignature.Hole.Field)? {
			guard property.asLazilyInstantiatedInstanceProperty != nil else { return nil }
			func providesRead(_ declared: Property) -> Bool {
				declared == property || (property.typeDescription.isOptional && declared == property.asUnwrappedProperty)
			}
			guard let field = fields.first(where: { $0.property.label == property.label }) else { return nil }
			if let declaration = hole.declarationsHiddenByFields.first(where: { $0.property.label == property.label && providesRead($0.property) }) {
				return (declaration, field)
			} else if field.isSeamParameter,
			          let declaration = hole.uncarriedDeclarations.first(where: { declaration in
			          	guard declaration.property.label == property.label, providesRead(declaration.property), case let .boundByPassingUpSeam(_, _, place) = declaration.reason else { return false }
			          	return place.isPresentation(of: hole)
			          }),
			          case let .boundByPassingUpSeam(_, _, place) = declaration.reason
			{
				return (SeamSignature.Hole.DeclarationHiddenByField(property: declaration.property, declaringType: declaration.declaringType, declarationLocation: declaration.declarationLocation, calledSeam: place.seamType, receivingSeam: hole.scopeSeamType), field)
			} else {
				return nil
			}
		}
		/// The seams whose parameter a reader in the fill's tree receives in another form, each once per label and seam.
		var twoFormsKeys = Set<SeamTreeReceives.Key>()
		let sitePath = SeamTreeReceives.sitePath(of: hole)
		/// Reports, once per label and seam, that `origin`'s seam's tree, as the caller fills it, receives `label` in a form no
		/// one parameter takes together with `field`'s, the parameter's form: `validateFills` completes its receivers and remedy
		/// once every fill is walked (`SeamTreeReceives`).
		func reportTwoForms(of label: String, by origin: SeamSignature.Hole.Field.SeamParameterOrigin, field: SeamSignature.Hole.Field) {
			let key = SeamTreeReceives.Key(label: label, seamType: origin.seamType)
			// A receive of the parameter's own form is required where the parameter is.
			seamTreeReceives.addTwoForms(of: origin, requiredProperties: Set(field.isReceivedOnlyIfAvailable ? [] : origin.receivers.map(\.property).filter { $0 == field.property }), to: key)
			if twoFormsKeys.insert(key).inserted {
				findings.append(.init(hole: hole, kind: .parameterReceivedInAnotherForm(
					label: label,
					receivers: [],
					remedy: .receiveTheSameWay,
					seamType: origin.seamType,
					seamDeclarationLocation: origin.seamDeclarationLocation,
				)))
			}
		}
		func checkReceive(of property: Property, by readerType: TypeDescription, declaredAt declarationLocation: Dependency.DeclarationLocation?, onlyIfAvailable: Bool, passingCall: DependencyTreeGeneratorError.FillFinding.PassingCall?) {
			// The seam's tree, as the caller fills it, receives the label wherever the fill's tree resolves it outside the fill,
			// where the fill's field of the label is that seam's parameter. Where some route hands the fill the memo of a seam that
			// defers the label, which the fill binds in the field's place (`ScopeGenerator.fillMemoOriginsByLabel`), the tree of
			// each seam whose memo it is receives the label there too: the place's field is then a declaration further out, which
			// the levels hand on past that seam (`FillDispatcher.Case.handsOn`), or the parameter of another seam, further out,
			// that passes the place up and receives the label itself. A memo of the field's own seam is that parameter, whose
			// receives are recorded once. A field a public mock's root binds names no seam's
			// tree here: its origin serves only the check of an optional wrapper the fill requires the instance of
			// (`publicMockHandsOptionalWrapperOfRequiredValue`), the deliberate gap of contract rule 7.
			let fieldOrigin = fields.first(where: { $0.property.label == property.label }).flatMap { $0.isBoundByPublicMockRoot ? nil : $0.seamParameterOrigin }
			let memoOrigins = (fill.fillMemoOriginsByLabel[property.label] ?? []).filter { $0.seamType != fieldOrigin?.seamType }
			for origin in [fieldOrigin].compactMap(\.self) + memoOrigins {
				seamTreeReceives.add(
					DependencyTreeGeneratorError.SeamError.Receiver(property: property, declaringType: readerType, declarationLocation: declarationLocation, aliasProperty: nil, isInstantiateMethodParameter: false),
					isRequired: !onlyIfAvailable,
					sitePath: sitePath,
					calledSeam: passingCall.map { _ in readerType },
					to: .init(label: property.label, seamType: origin.seamType),
				)
			}
			// Inline, a receive only if available of the property the fill builds finds it still being built and is handed
			// `nil`, which the fill's tree passes it too, unless the property is an instantiator, which is handed a wrapper of
			// its own (see `instantiatorBuildingSite`).
			guard !onlyIfAvailable || ScopeGenerator.isBuilder(hole.property) || !isHolesOwnProperty(property) else { return }
			let reader = DependencyTreeGeneratorError.FillFinding.Reader(property: property, type: readerType, declarationLocation: declarationLocation, isOnlyIfAvailable: onlyIfAvailable, fillingModule: callerModule, passingCall: passingCall)
			let sameLabelFields = fields.filter { $0.property.label == property.label }
			// A declaration a called copy of a fill on the place's path leaves uncarried, which the place joins to its own
			// (`unreadableInsideFills(_:placeFields:fillingModule:)`), is nearer the place than every field of its label: each
			// field is a level's above that fill, since a label the fill's hole carries or a scope beneath its root declares is
			// never one. So it is tested before the field branch, as the visible build tests it, where the fill's hole carries no
			// field of the label. A declaration that presents the place itself, as every seam that passes the place up presents it,
			// is not one: the place's own fields are nearer than what that seam binds.
			let calledCopyDeclarations = hole.uncarriedDeclarations.filter { declaration in
				guard declaration.property.label == property.label, case let .boundByPassingUpSeam(_, _, place) = declaration.reason else { return false }
				return !place.isPresentation(of: hole)
			}
			// A value a cycle in the seam's tree hands the site's owner when it builds it again is wrong at every level but the
			// first, whether a field carries the label or the fill reads it from the caller's scope.
			// This rejection keeps a builder struct's re-entry of a reopened level safe, which carries nothing bound above it (the
			// reopened level's deliberate gap in `SeamScopeEnumsByType.routeStep`).
			if let declaration = hole.cycleReentryDeclarations.first(where: { $0.property.label == property.label }) {
				findings.append(.init(hole: hole, kind: .declarationBoundOnCycleReentry(reader: reader, declaration: declaration, seamModule: seamModule)))
			} else if case let reenteringCallDeclarations = hole.reenteringCallDeclarations.filter({ $0.property.label == property.label }), !reenteringCallDeclarations.isEmpty {
				// A place inside a fill of the call of a seam that fills another place again, which this module fills for that seam:
				// the seam recorded what its visible build rejects a read of, whether a field carries the label or the fill reads it
				// from the caller's scope, since the fill of the place built again reads the outer call's value on every route. A
				// field bound above the seam call does not lift it, a deliberate loss shared with the visible build's check below,
				// until each route is handed its own value. One finding per fill of a place built again, as the visible build
				// reports one per fill.
				var groups = [(first: SeamSignature.Hole.ReenteringCallDeclaration, hidings: [SeamSignature.Hole.ReenteringCallDeclaration])]()
				for declaration in reenteringCallDeclarations {
					if let index = groups.firstIndex(where: { $0.first.reenteredIdentity == declaration.reenteredIdentity }) {
						groups[index].hidings.append(declaration)
					} else {
						groups.append((declaration, [declaration]))
					}
				}
				for (first, hidings) in groups {
					findings.append(.init(hole: hole, kind: .declarationBoundOnPathToReenteringCall(reader: reader, readsOnlyIfAvailable: onlyIfAvailable, hidings: hidings, reenteredPlace: first.reenteredPlace, fillingModule: first.fillingModule, seamModule: first.reenteredSeamModule)))
				}
			} else if case let reenteringPlaceFields = hole.reenteringPlaceFields.filter({ provides($0.carried.field, property) }), !reenteringPlaceFields.isEmpty {
				// The same for a field of a place whose fill builds that seam again, which the visible build reports where the fill
				// reads the label from the caller's scope (`checkReadFromCallersScope`): tested after the declarations on the path,
				// as the visible build tests those first, and before the field branch, since a field bound above the seam call does
				// not lift it either. One finding per fill of a place built again.
				var groups = [(first: SeamSignature.Hole.ReenteringPlaceField, carried: [SeamSignature.Hole.FieldOfReenteringPlace])]()
				for field in reenteringPlaceFields {
					if let index = groups.firstIndex(where: { $0.first.reenteredIdentity == field.reenteredIdentity }) {
						groups[index].carried.append(field.carried)
					} else {
						groups.append((field, [field.carried]))
					}
				}
				for (first, carried) in groups {
					findings.append(.init(hole: hole, kind: .fieldOfReenteringPlace(reader: reader, isOnlyIfAvailable: onlyIfAvailable, carried: carried, reenteredPlace: first.reenteredPlace, fillingModule: first.fillingModule, seamModule: first.reenteredSeamModule)))
				}
			} else if !calledCopyDeclarations.isEmpty {
				for declaration in calledCopyDeclarations {
					if case let .boundByPassingUpSeam(_, passingUpSeamModule, _) = declaration.reason {
						findings.append(.init(hole: hole, kind: .declarationBoundAfterSite(reader: reader, declaration: declaration, seamModule: passingUpSeamModule)))
					}
				}
			} else if let field = sameLabelFields.first(where: { provides($0, property) }) {
				if !field.access.satisfies(requirement) {
					findings.append(.init(hole: hole, kind: .fieldNotReadable(reader: reader, field: field, callerModule: callerModule, seamModule: seamModule, requirement: requirement)))
				} else if onlyIfAvailable, property.typeDescription.isOptional, property.asLazilyInstantiatedInstanceProperty != nil,
				          !memoOrigins.isEmpty,
				          let memoField = fill.fillBoundFields.first(where: { $0.property.label == property.label })
				{
					// The place's field gives the read its wrapper, but the fill binds in its place the memo of a seam's deferred
					// parameter some route hands it, the parameter's value, which a read of the optional wrapper only if available
					// does not find: generation would hand the reader `nil`, where inline hands it the field's wrapper. Inline, that
					// seam's tree receives the label as the parameter's value and as the optional wrapper, which no one parameter
					// takes (`providingForm(among:)` finds none for a value and an optional wrapper), so one module reports that
					// seam's two forms. A fill whose tree reads the wrapper alone takes the place's field, no memo, and is handed the
					// wrapper inline hands (`ScopeGenerator.fillLabelsReadOnlyAsPlaceField`): accepted, though one module rejects the
					// graph, a deliberate gap `seam-hole-fills.md` names.
					for origin in memoOrigins {
						reportTwoForms(of: property.label, by: origin, field: memoField)
					}
				} else if field.isDeferredParameter, hidden.pathDeclarations[property.label] == nil {
					// A field bound from a deferred parameter is read from the caller's scope (`fillUnderConstruction`).
					checkReadFromCallersScope(of: property, by: reader, onlyIfAvailable: onlyIfAvailable)
				}
			} else if !onlyIfAvailable, let field = sameLabelFields.first(where: { $0.property.typeDescription.isOptional && $0.property.asUnwrappedProperty == property }) {
				findings.append(.init(hole: hole, kind: .fieldHeldOnlyOptionally(reader: reader, field: field, seamModule: seamModule)))
			} else if !readsMemoOfItsOwnKind(property), let (declaration, field) = declarationHiddenByField(providing: property) {
				// The fill resolves a wrapper the tree reads from the caller's scope, while inline it reads the declaration that a
				// seam on the route to the place binds above its call of the seam whose parameter the field is: the struct carries
				// only that parameter. Reported before a memo the fill takes in another form, which follows from the same field.
				findings.append(.init(hole: hole, kind: .declarationHiddenByField(reader: reader, declaration: declaration, field: field, seamModule: seamModule)))
			} else if !readsMemoOfItsOwnKind(property), property.propertyType == .sendableLazilyInstantiated, !property.typeDescription.isOptional,
			          let instance = property.asLazilyInstantiatedInstanceProperty,
			          let routes = fill.fillPlainMemoRoutesOfSendableWrapperReads[property.label],
			          let memo = fill.fillFields.first(where: { $0.property.label == property.label && $0.deferral == .deferred(isSendable: false) && $0.property.asUnwrappedProperty == instance }),
			          let instanceReader = reads.firstReader(of: instance)
			{
				// The fill takes a `LazilyInstantiated` some route hands, which is no `SendableLazilyInstantiated`, where its tree reads
				// the value too: generation found it (`ScopeGenerator.fillPlainMemoRoutesOfSendableWrapperReads`). Where the tree reads
				// the label inside a `@Sendable` function, the fill binds the memo's value rather than the memo
				// (`ScopeGenerator.fillDeferredLabelsReadInsideSendableFunction`), which the wrapper's reader cannot take either. A read of the
				// optional wrapper only if available, which generation leaves out (`fillSendableWrapperReads`), is the deferring seam's
				// two forms below (`parameterReceivedInAnotherForm`), as one module reports it.
				findings.append(.init(hole: hole, kind: .sendableWrapperReadBesidePlainMemo(reader: reader, memo: memo, instanceReader: instanceReader, routes: routes)))
			} else if sameLabelFields.isEmpty, let declarations = hole.uncarriedDeclarations.first(where: { $0.property.label == property.label }).map({ [$0] })
				// A call inside a fill that passes it to a seam passing the site up hands it that seam's copy of the hole,
				// which does not carry what that seam binds on its path to the call presenting the site: each such call's.
				?? hidden.calledCopyDeclarations[property.label]
			{
				for declaration in declarations.map({ $0.resolvingBuildabilityAboveSeam(fillsOfCall: call) }) {
					switch declaration.reason {
					case let .boundByPassingUpSeam(_, passingUpSeamModule, _):
						findings.append(.init(hole: hole, kind: .declarationBoundAfterSite(reader: reader, declaration: declaration, seamModule: passingUpSeamModule)))
					case .instantiatorBuildingSite:
						findings.append(.init(hole: hole, kind: .receivesInstantiatorBuildingSite(reader: reader, declaration: declaration, seamModule: seamModule)))
					case .receivesPathScopeOnlyIfAvailable, .requiresOtherCarrier, .other, .boundOutsideSendableFunction:
						findings.append(.init(hole: hole, kind: .declarationBoundAfterSite(reader: reader, declaration: declaration, seamModule: seamModule)))
					}
				}
			} else if compilesGeneratedMocks,
			          let field = sameLabelFields.first,
			          field.isBoundByPublicMockRoot,
			          let origin = field.seamParameterOrigin,
			          !onlyIfAvailable,
			          field.property.typeDescription.isOptional,
			          field.property.asLazilyInstantiatedInstanceProperty == property
			{
				// A called public mock's tree receives a wrapper only if available, which the mock binds as the field, an optional
				// wrapper, where the reader requires its instance: no value of the field gives it one. The production twin reports
				// the label its seam's tree receives in two forms here (the branch below), so the calling mock reports it at the
				// same sites, the mocked type's declaration and each receiver. Only where the build compiles the generated mocks:
				// elsewhere the mock, which no other code reads, is never compiled, and the fill is generated as it is.
				let receivers = origin.receivers.map {
					DependencyTreeGeneratorError.SeamError.Receiver(property: $0.property, declaringType: $0.declaringType, declarationLocation: $0.declarationLocation, aliasProperty: $0.aliasProperty, isInstantiateMethodParameter: $0.isInstantiateMethodParameter)
				} + [DependencyTreeGeneratorError.SeamError.Receiver(property: property, declaringType: readerType, declarationLocation: declarationLocation, aliasProperty: nil, isInstantiateMethodParameter: false)]
				findings.append(.init(hole: hole, kind: .publicMockHandsOptionalWrapperOfRequiredValue(
					label: property.label,
					field: field,
					receivers: receivers,
					remedy: DependencyTreeGenerator.labelCollisionRemedy(among: receivers.map(\.property), requiredProperties: [property]),
					mockedTypeDeclarationLocation: origin.seamDeclarationLocation,
				)))
			} else if let field = sameLabelFields.first,
			          !field.isBoundByPublicMockRoot,
			          let origin = field.seamParameterOrigin,
			          // A pass-through takes each form its receivers receive, so where one parameter can take the reader's form
			          // too, the seam would take that parameter, which provides the field's form: inline reads the caller's
			          // declaration, which a deferred field's fill reads too. The seam's own property is a parameter as declared,
			          // and provides only what it provides.
			          !origin.isPassThrough || DependencyTreeGenerator.providingForm(among: [field.property, onlyIfAvailable && !property.typeDescription.isOptional ? property.asOptionalProperty : property]) == nil
			{
				// One finding per label and seam, across every fill the seam's tree holds, which names every receive of the label in
				// those fills' trees, as the seam names every receive of its own tree. A deliberate gap (contract rule 7 in
				// `seam-and-mock-contract.md`): a calling mock of the same graph is not rejected, since this check skips a field a
				// public mock's root level binds (`isBoundByPublicMockRoot`), and a fill that carries one on or is handed it as a
				// memo drops its origin, and the mock builds the called types inline, handing the reader inline's value.
				reportTwoForms(of: property.label, by: origin, field: field)
			} else if sameLabelFields.isEmpty, let hidings = hidden.pathDeclarations[property.label] {
				// The seam whose call these fills are records the same for a place inside this fill that a caller of it fills
				// (`unreadableInsideFills(_:placeFields:fillingModule:)`), which the branch above reports with this message.
				findings.append(.init(hole: hole, kind: .declarationBoundOnPathToReenteringCall(
					reader: reader,
					readsOnlyIfAvailable: onlyIfAvailable,
					hidings: hidings.map { $0.reenteringCallDeclaration(reentering: hole, fillingModule: callerModule) },
					reenteredPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole),
					fillingModule: callerModule,
					seamModule: seamModule,
				)))
			} else if sameLabelFields.isEmpty {
				checkReadFromCallersScope(of: property, by: reader, onlyIfAvailable: onlyIfAvailable)
			}
			// A field of the label with another type that no parameter binds is the inline hidden-label error, which validation
			// reported. A public mock's root level binds a receive again where its declaration does not provide the form, so a
			// fill of a public mock's place that receives a root-level value in another form is judged here only where the
			// field is an optional wrapper and the fill requires its instance.
		}
		for read in reads.reads {
			switch read {
			case let .receive(receive):
				checkReceive(of: receive.property, by: receive.readerType, declaredAt: receive.declarationLocation, onlyIfAvailable: receive.onlyIfAvailable, passingCall: receive.passingCall)
			case let .closer(closer):
				// Where the declaration lies on the path is read from the place judged, whose own fill another place's can stand
				// for (`ScopeGenerator.FillStoodFor`): the two reach the declaration at depths of their own.
				if let declarationsBeneath = hole.fillPathDeclarationsBeneath(closer.closedOnDeclaration) {
					findings.append(.init(hole: hole, kind: .closesCycleInSeamTree(
						closingProperty: closer.property,
						closingType: closer.closingType,
						declarationLocation: closer.declarationLocation,
						fillAncestors: closer.fillAncestors,
						closedOnDeclaration: hole.declaredSitePath.dropLast(declarationsBeneath + 1).last,
						closesOnOwnerOfHole: declarationsBeneath == 0,
						seamModule: seamModule,
					), closer: .init(
						caseKey: ScopeGenerator.fillCaseKey(of: hole),
						closingProperty: closer.property,
						closingType: closer.closingType,
						declarationLocation: closer.declarationLocation,
						closedOnDeclaration: closer.closedOnDeclaration,
						declarationsBeneath: declarationsBeneath,
					)))
				}
			case .openScope:
				break
			}
		}
		return findings
	}

	/// Per label and seam, the receives of the label in the trees of the fills whose field of the label is that seam's
	/// parameter, and what a reader there that receives the label in another form says of the parameter. The seam's tree, as
	/// the caller fills it, receives the label at the parameter's receivers and at every receive in those fills' trees, which
	/// the seam's two forms name as the seam names its own tree's, so the error reads as one module's, once per label and
	/// seam however many fills the seam's tree holds (`completing(_:)`).
	struct SeamTreeReceives {
		struct Key: Hashable {
			let label: String
			let seamType: TypeDescription
		}

		/// The receives of one label and seam.
		struct Receives {
			/// Each receive a fill's walk meets, in the order the walks meet them – in each fill each type before the types
			/// beneath it, siblings in declaration order, as the seam's own tree lists its receivers – with whether it is required
			/// and where the place the fill fills is declared, from the root of the tree that holds it (`sitePath`).
			var fillTreeReceivers = [(receiver: DependencyTreeGeneratorError.SeamError.Receiver, isRequired: Bool, sitePath: [Dependency.DeclarationLocation?])]()
			/// The parameter, where a reader receives the label in another form.
			var origin: SeamSignature.Hole.Field.SeamParameterOrigin?
			/// The receives of the parameter's own form that are required where the parameter is.
			var originRequiredProperties = Set<Property>()
		}

		private var receivesByKey = [Key: Receives]()

		/// Where `hole`'s place is declared, from the root of the tree that holds it: the declarations of its path, then its own.
		static func sitePath(of hole: SeamSignature.Hole) -> [Dependency.DeclarationLocation?] {
			hole.declaredSitePath.map(\.declarationLocation) + [hole.declarationLocation]
		}

		/// Records `receiver`, a receive in a fill's tree, for `key`'s seam, unless it is the receive of a call of that seam
		/// itself inside the fill (`calledSeam`), which builds the seam again: the call receives what the seam's tree receives,
		/// which the parameter's receivers already name, and one module names each declaration once, never the seam for what
		/// its tree receives.
		mutating func add(_ receiver: DependencyTreeGeneratorError.SeamError.Receiver, isRequired: Bool, sitePath: [Dependency.DeclarationLocation?], calledSeam: TypeDescription?, to key: Key) {
			guard calledSeam != key.seamType else { return }
			receivesByKey[key, default: Receives()].fillTreeReceivers.append((receiver, isRequired, sitePath))
		}

		mutating func addTwoForms(of origin: SeamSignature.Hole.Field.SeamParameterOrigin, requiredProperties: Set<Property>, to key: Key) {
			receivesByKey[key, default: Receives()].origin = receivesByKey[key]?.origin ?? origin
			receivesByKey[key, default: Receives()].originRequiredProperties.formUnion(requiredProperties)
		}

		/// `finding`, where it is a seam's two forms, naming the parameter's receivers and every receive of the label in the
		/// trees of the seam's fills, with the remedy they give: each receive once, the fills in the order their places are
		/// declared, as the seam's own tree lists them, never the order the walks met them in, which follows the fills' names.
		func completing(_ finding: DependencyTreeGeneratorError.FillFinding) -> DependencyTreeGeneratorError.FillFinding {
			guard case let .parameterReceivedInAnotherForm(label, _, _, seamType, seamDeclarationLocation) = finding.kind,
			      let receives = receivesByKey[Key(label: label, seamType: seamType)],
			      let origin = receives.origin
			else { return finding }
			// By where the place is declared, then by the order the walks met them in.
			let inSiteOrder = receives.fillTreeReceivers.enumerated().sorted { lhs, rhs in
				lhs.element.sitePath.lexicographicallyPrecedes(rhs.element.sitePath, by: Dependency.DeclarationLocation.precedesInSourceOrder)
					|| (!rhs.element.sitePath.lexicographicallyPrecedes(lhs.element.sitePath, by: Dependency.DeclarationLocation.precedesInSourceOrder) && lhs.offset < rhs.offset)
			}.map(\.element)
			var fillTreeReceivers = [(receiver: DependencyTreeGeneratorError.SeamError.Receiver, isRequired: Bool)]()
			for (receiver, isRequired, _) in inSiteOrder where !fillTreeReceivers.contains(where: { $0.receiver.property == receiver.property && $0.receiver.declaringType == receiver.declaringType && $0.receiver.declarationLocation == receiver.declarationLocation }) {
				fillTreeReceivers.append((receiver, isRequired))
			}
			let receivers = origin.receivers.map {
				DependencyTreeGeneratorError.SeamError.Receiver(property: $0.property, declaringType: $0.declaringType, declarationLocation: $0.declarationLocation, aliasProperty: $0.aliasProperty, isInstantiateMethodParameter: $0.isInstantiateMethodParameter)
			} + fillTreeReceivers.map(\.receiver)
			let requiredProperties = receives.originRequiredProperties.union(fillTreeReceivers.filter(\.isRequired).map(\.receiver.property))
			var completed = DependencyTreeGeneratorError.FillFinding(hole: finding.hole, kind: .parameterReceivedInAnotherForm(
				label: label,
				receivers: receivers,
				remedy: DependencyTreeGenerator.labelCollisionRemedy(among: receivers.map(\.property), requiredProperties: requiredProperties),
				seamType: seamType,
				seamDeclarationLocation: seamDeclarationLocation,
			))
			completed.mergedPlaces = finding.mergedPlaces
			return completed
		}
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

		/// The declaration as a fill of a place inside the fill of `hole`, the place built again, cannot read it, where
		/// `fillingModule` fills `hole`.
		func reenteringCallDeclaration(reentering hole: SeamSignature.Hole, fillingModule: ModuleIdentity) -> SeamSignature.Hole.ReenteringCallDeclaration {
			SeamSignature.Hole.ReenteringCallDeclaration(
				property: declaration.property,
				declaringType: declaration.declaringType,
				declarationLocation: declaration.declarationLocation,
				pathPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(pathHole),
				callingType: callingType,
				callProperty: callProperty,
				calledSeam: calledSeam,
				reenteredPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole),
				reenteredSeamModule: hole.scopeSeamModule,
				fillingModule: fillingModule,
			)
		}
	}

	/// What the calls inside the fills of one seam call hide from a fill of that call they pass on: inline, the seam such a
	/// call re-enters hands its fill's reads from the caller's scope the nearest declaration of their label at the call,
	/// and a seam that passes the site up hands it what it binds on its path to the call presenting the site; the fill,
	/// one function, reads the outer call's values.
	struct FillReentryHidings {
		/// The declarations of the scopes on the paths from a fill's root to each call inside it that passes this fill on,
		/// by label: of each path, the first it declares of the label. Every path's, since which path a walk meets first
		/// follows the order of the files that declare the fills' places.
		var pathDeclarations = [String: [DeclarationOnPathToReenteringCall]]()
		/// The declarations the copies of this fill's hole that those calls' seams take do not carry, by label: every copy's,
		/// since which call a walk meets first follows the order of the files that declare the fills' places, and two seams'
		/// copies name different declarations. A declaration two calls hide gives findings that print the same, which
		/// `validateFills` merges.
		var calledCopyDeclarations = [String: [SeamSignature.Hole.UncarriedDeclaration]]()
		/// The fields of the places whose fills make those calls, by label, every place's: inline, the seam such a call opens
		/// again sits beneath that place, so a read of the label this fill makes from the caller's scope would find that
		/// field. Every place's, since which a walk meets first follows the order of the files that declare them.
		var fieldsOfReenteringPlaces = [String: [SeamSignature.Hole.FieldOfReenteringPlace]]()
	}

	/// What the calls inside the fills of `leaf`'s seam call hide from each of those fills, by the fill's key: the fills in
	/// the order their sites are declared, each fill's tree, from the scope of its fulfiller, is walked depth first in
	/// declaration order, and at each call inside it that
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
		var work = 0
		defer { GenerationWork.record(work, by: .findingDeclarationsHiddenByReenteringCalls) }
		// Each seam call's fills in the order their places are declared, here and at every seam call inside a fill, not
		// the order of their builders' labels, so the first path met for a label, which a diagnostic names, never depends
		// on names.
		for case let (pathHole?, fulfiller?) in children.withFillsSortedByDeclarationLocations.map({ ($0.fillHole, $0.children.first) }) {
			var generatorsToVisit = [(generator: fulfiller, callingType: TypeDescription?.none, pathDeclarations: [SeamSignature.Hole.UncarriedDeclaration]())]
			while let (generator, callingType, pathDeclarations) = generatorsToVisit.popLast() {
				guard !generator.closesPropertyCycle else { continue }
				for (fillKey, calledHole) in generator.enclosingFillsPassed {
					// Taken out of the dictionary while it grows, so appending to its lists never copies them.
					var hidden = hiddenByFillKey.removeValue(forKey: fillKey) ?? FillReentryHidings()
					for declaration in calledHole.uncarriedDeclarations {
						hidden.calledCopyDeclarations[declaration.property.label, default: []].append(declaration)
					}
					if let callProperty = generator.property, let calledSeam = generator.builtInstantiable?.concreteInstantiable {
						// The fill's root declares what is on every path, so a call that is the root itself has no scope above it.
						if let callingType {
							var labelsOfThisPath = Set<String>()
							for declaration in pathDeclarations where labelsOfThisPath.insert(declaration.property.label).inserted {
								hidden.pathDeclarations[declaration.property.label, default: []].append(DeclarationOnPathToReenteringCall(declaration: declaration, pathHole: pathHole, callingType: callingType, callProperty: callProperty, calledSeam: calledSeam))
							}
						}
						// A field bound from a parameter of the seam is the caller's own, which the call hands the seam opened again too.
						for field in pathHole.fields where !field.isSeamParameter {
							hidden.fieldsOfReenteringPlaces[field.property.label, default: []].append(SeamSignature.Hole.FieldOfReenteringPlace(field: field, reenteringPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(pathHole), callProperty: callProperty, calledSeam: calledSeam))
						}
					}
					hiddenByFillKey[fillKey] = hidden
				}
				let childPathDeclarations = pathDeclarations + declarationsBound(by: generator, includingForwardedProperties: true, reason: .other)
				work += 1 + generator.children.count + childPathDeclarations.count
				let childCallingType = generator.builtInstantiable?.concreteInstantiable ?? callingType
				generatorsToVisit.append(contentsOf: generator.children.withFillsSortedByDeclarationLocations.reversed().map { ($0, childCallingType, childPathDeclarations) })
			}
		}
		return hiddenByFillKey
	}
}

extension [ScopeGenerator] {
	/// These generators with the fills among them, the generators of a seam call that fill its places, sorted by their
	/// places' `declarationLocations` into the positions fills hold, and every other generator where it is. Two places
	/// passed up through one property share their `forwardingLocation`, so the places' own declarations, and their
	/// routes', order them, never their builders' labels.
	fileprivate var withFillsSortedByDeclarationLocations: [ScopeGenerator] {
		let fills = indices.compactMap { index in self[index].fillHole.map { (index: index, locations: $0.declarationLocations) } }
		let sortedFills = fills.sorted { first, second in
			for (firstLocation, secondLocation) in zip(first.locations, second.locations) where firstLocation != secondLocation {
				return Dependency.DeclarationLocation.precedesInSourceOrder(firstLocation, secondLocation)
			}
			// One place reached the same way: the same location everywhere, which no name decides.
			return first.locations.count == second.locations.count ? first.index < second.index : first.locations.count < second.locations.count
		}
		var ordered = self
		for (fill, sortedFill) in zip(fills, sortedFills) {
			ordered[fill.index] = self[sortedFill.index]
		}
		return ordered
	}
}

extension SeamSignature.Hole {
	/// Where the place is reached (`forwardingLocation`), where it is declared, and where each property of its route up
	/// and of its site's path is declared, in that order: what orders fills of one seam call, which no label decides.
	var declarationLocations: [Dependency.DeclarationLocation?] {
		[forwardingLocation, declarationLocation] + passedUpRoute.map(\.declarationLocation) + declaredSitePath.map(\.declarationLocation)
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
			/// Whether the reader receives it only if available.
			let isOnlyIfAvailable: Bool
			/// The module that generates the fill, which sees the reader's type.
			let fillingModule: ModuleIdentity
			/// For a receive of a seam's call, which passes it on to the seam's tree: the type that makes the call, the call's
			/// property, and where that property is declared.
			var passingCall: PassingCall?

			/// A declaration that receives the reader's property as the reader does: only if available, as an optional, where
			/// the reader receives it only if available.
			var receiveSpelling: String {
				isOnlyIfAvailable
					? "@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true) let \((property.typeDescription.isOptional ? property : property.asOptionalProperty).asSource)"
					: "@\(Dependency.Source.receivedRawValue) let \(property.asSource)"
			}
		}

		/// A receive in a fill's tree of the instance a wrapper another receive reads holds.
		struct InstanceReader {
			let property: Property
			let type: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
		}

		/// A call of a seam, by `callingType`'s `property`, declared at `declarationLocation`.
		struct PassingCall: Hashable {
			let callingType: TypeDescription
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
		}

		enum Kind {
			/// The scope struct carries the value the reader receives at an access the caller's module cannot read.
			case fieldNotReadable(reader: Reader, field: SeamSignature.Hole.Field, callerModule: ModuleIdentity, seamModule: ModuleIdentity, requirement: AccessRequirement)
			/// The scope struct carries the value only as an optional value, which the reader requires.
			case fieldHeldOnlyOptionally(reader: Reader, field: SeamSignature.Hole.Field, seamModule: ModuleIdentity)
			/// The reader receives a wrapper that `declaration`, which a seam on the route to the place binds above its call, provides
			/// inline, while the scope struct carries only `field`, a parameter of the seam whose tree receives its instance: the fill
			/// would read the caller's scope.
			case declarationHiddenByField(reader: Reader, declaration: SeamSignature.Hole.DeclarationHiddenByField, field: SeamSignature.Hole.Field, seamModule: ModuleIdentity)
			/// The reader receives a `SendableLazilyInstantiated` whose instance `instanceReader` receives too, while the fill takes
			/// `memo`, a `LazilyInstantiated`, since each of `routes` hands the `LazilyInstantiated` of a seam whose tree reads the
			/// value outside a `@Sendable` function, which no `@Sendable` function can capture.
			case sendableWrapperReadBesidePlainMemo(reader: Reader, memo: SeamSignature.Hole.Field, instanceReader: InstanceReader, routes: [ScopeGenerator.FillDispatcher.PlainMemoRoute])
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
			/// For each of `hidings`, a scope of the fill of its `pathPlace` – the fill of `reenteredPlace`, or another of the same
			/// seam call – declares the reader's label on the path from that fill's root to its `callingType`'s call of its
			/// `calledSeam` (`callProperty`), which passes the fill of `reenteredPlace` on: inline, the re-entered seam would read
			/// that declaration, and the fill, which `fillingModule` generates, reads the outer call's value. The reader is in
			/// that fill's tree, or, where a caller of the seam whose call that is fills a place inside it, in that caller's fill,
			/// whose hole carries the hidings (`SeamSignature.Hole.reenteringCallDeclarations`); the message is the same. It names
			/// every path, so none is picked by where its place is declared. `seamModule` declares `reenteredPlace`'s seam.
			case declarationBoundOnPathToReenteringCall(reader: Reader, readsOnlyIfAvailable: Bool, hidings: [SeamSignature.Hole.ReenteringCallDeclaration], reenteredPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace, fillingModule: ModuleIdentity, seamModule: ModuleIdentity)
			/// The fill of `reenteredPlace`, which `fillingModule` generates, resolves the reader's receive from the caller's
			/// scope, which a call inside the fill of each of `carried`'s places hands it from the outer call, while inline the
			/// seam that call opens again sits beneath that place, whose field gives the receive its value: the fill reads `nil`,
			/// or the outer call's value, in place of inline's. The reader is in that fill's tree, or, where a caller of the seam
			/// whose call that is fills a place inside it, in that caller's fill, whose hole carries the fields
			/// (`SeamSignature.Hole.reenteringPlaceFields`); the message is the same. It names every place, so none is picked by
			/// where it is declared. `seamModule` declares `reenteredPlace`'s seam.
			case fieldOfReenteringPlace(reader: Reader, isOnlyIfAvailable: Bool, carried: [SeamSignature.Hole.FieldOfReenteringPlace], reenteredPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace, fillingModule: ModuleIdentity, seamModule: ModuleIdentity)
			/// A scope in the fill closes a cycle on `closingProperty`, a property of the seam's path, declared by
			/// `closingType` beneath `fillAncestors`.
			/// `closedOnDeclaration` is the declaration of the seam's path it repeats, and `closesOnOwnerOfHole` says that
			/// declaration builds the type that declares the hole, so a closer under another label would close at the hole.
			case closesCycleInSeamTree(closingProperty: Property, closingType: TypeDescription, declarationLocation: Dependency.DeclarationLocation?, fillAncestors: [FillAncestor], closedOnDeclaration: SeamSignature.Hole.DeclaredProperty?, closesOnOwnerOfHole: Bool, seamModule: ModuleIdentity)
			/// The routes to the places of the hole's case, nested by type, hold `label`, which the one fill of the case reads,
			/// as `fields`, whose forms differ in more than optionality: no one parameter takes them all.
			case fieldFormsDifferBetweenPlaces(label: String, fields: [SeamSignature.Hole.Field], seamModule: ModuleIdentity)
			/// The reader receives `label`, which a parameter of `seamType` carries in a form no one parameter takes together
			/// with the reader's (`DependencyTreeGenerator.providingForm(among:)`), or which the seam's own property carries in
			/// a form that does not provide the reader's: the seam's tree, as the caller fills it, receives the label in two
			/// forms, which the seam reports where its own tree holds both (`parametersShareLabel`), and the fill would be
			/// handed another value than inline. The seam is the one whose tree holds the site, or the one whose struct a fill
			/// on the site's path binds the field from (`SeamSignature.Hole.Field.SeamParameterOrigin`). Reported as the seam
			/// reports it, once per label and seam, at the seam, with a note at each of `receivers`: the parameter's, then each
			/// receive of the label in the trees of the seam's fills (`DependencyTreeGenerator.SeamTreeReceives`).
			case parameterReceivedInAnotherForm(label: String, receivers: [SeamError.Receiver], remedy: SeamError.LabelCollisionRemedy, seamType: TypeDescription, seamDeclarationLocation: Dependency.DeclarationLocation?)
			/// The reader requires the instance of `field`, the optional `LazilyInstantiated` or `SendableLazilyInstantiated` a
			/// called public mock's root binds where its tree receives `label` only if available, which gives the fill no value.
			/// The production twin reports `parameterReceivedInAnotherForm` there, so the calling mock reports at the same sites:
			/// the mocked type's declaration, with a note at each of `receivers`, the field's, then the reader.
			case publicMockHandsOptionalWrapperOfRequiredValue(label: String, field: SeamSignature.Hole.Field, receivers: [SeamError.Receiver], remedy: SeamError.LabelCollisionRemedy, mockedTypeDeclarationLocation: Dependency.DeclarationLocation?)
			/// The places of the hole's case, nested by type, are reached from both the inner seam's plain root enum and its
			/// `@Sendable` one, and the one fill of the case builds `place`, a place `callerModule` cannot fill, or passes one up,
			/// whose case would carry the scope value of either root enum.
			case placeInsideFillOfCaseOfBothRootEnums(place: PlaceInsideFill, callerModule: ModuleIdentity, seamModule: ModuleIdentity)
		}

		/// A place a fill's tree builds: the type that declares it, and the property.
		struct PlaceInsideFill {
			let ownerType: TypeDescription
			let property: Property
			let instantiatedType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
		}

		let hole: SeamSignature.Hole
		let kind: Kind
		/// Every place the finding holds for, which its message names, where the fills of several places give it (`merged(with:)`),
		/// or `nil` for the one place it names of its own (`ownPlace`).
		var mergedPlaces: [SeamSignature.Hole.UncarriedDeclaration.PresentedPlace]?
		/// For a cycle a fill closes on the seam's path, what makes two such findings one fix: the case, the closer, the
		/// declaration it closes on, and how many declarations of the path lie beneath that declaration. The places of one
		/// case reach the declaration along routes of their own, which only name a path; of those at one depth only the
		/// least route in source order is reported (`DependencyTreeGenerator.fillFindings`).
		var closer: Closer?

		struct Closer: Hashable {
			let caseKey: String
			let closingProperty: Property
			let closingType: TypeDescription
			let declarationLocation: Dependency.DeclarationLocation?
			let closedOnDeclaration: ScopeGenerator.BuiltDeclaration
			let declarationsBeneath: Int
		}

		/// The place the message names of its own: for a declaration a seam binds on its path to a call whose builder it
		/// passes up, the place that call presents; for a declaration on the path to a call that builds a seam again, or a field
		/// of a place whose fill makes that call, the place of the fill that call is passed, which a caller filling a place
		/// inside it does not fill; and otherwise the place
		/// the fill fills.
		private var ownPlace: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace {
			if case let .declarationBoundAfterSite(_, declaration, _) = kind, case let .boundByPassingUpSeam(_, _, place) = declaration.reason {
				place
			} else if case let .declarationBoundOnPathToReenteringCall(_, _, _, reenteredPlace, _, _) = kind {
				reenteredPlace
			} else if case let .fieldOfReenteringPlace(_, _, _, reenteredPlace, _, _) = kind {
				reenteredPlace
			} else {
				SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole)
			}
		}

		/// The places the message names, in the order of their types, then their labels.
		var namedPlaces: [SeamSignature.Hole.UncarriedDeclaration.PresentedPlace] {
			mergedPlaces ?? [ownPlace]
		}

		/// `findings`, the findings of one key recorded so far, with `finding`: merged into the one whose diagnostics differ
		/// from its own only in the places they name, so that one diagnostic names every place it holds for, or else beside
		/// them. Which findings merge, and what the merged one names, never depends on the order they are recorded in, nor
		/// on where each place is declared.
		static func adding(_ finding: FillFinding, to findings: [FillFinding]) -> [FillFinding] {
			let diagnosticsWithoutPlaces = finding.diagnosticsWithoutPlaces
			var findings = findings
			if let index = findings.firstIndex(where: { $0.diagnosticsWithoutPlaces == diagnosticsWithoutPlaces }) {
				findings[index] = findings[index].merged(with: finding)
			} else {
				findings.append(finding)
			}
			return findings
		}

		/// The finding's diagnostics, printed, with no place named: two findings whose diagnostics differ only in the places
		/// they name print the same.
		private var diagnosticsWithoutPlaces: [String] {
			var finding = self
			finding.mergedPlaces = []
			return finding.sourceDiagnostics.map(\.formatted)
		}

		/// This finding and `other`, whose diagnostics differ only in the places they name, as one finding that names the
		/// places of both, each once, in the order of their types, then their labels: the finding that comes first in source
		/// order, which decides nothing it prints.
		private func merged(with other: FillFinding) -> FillFinding {
			var merged = precedesInSourceOrder(other) ? self : other
			var places = [SeamSignature.Hole.UncarriedDeclaration.PresentedPlace]()
			for place in (namedPlaces + other.namedPlaces).sorted(by: { $0.nameOrder.lexicographicallyPrecedes($1.nameOrder) }) where places.last?.nameOrder != place.nameOrder {
				places.append(place)
			}
			merged.mergedPlaces = places
			return merged
		}

		/// What identifies the finding: its kind and where it is reported, and, for a label the seam's tree receives in two
		/// forms, which the seam reports per label at its own declaration, the label.
		var key: String {
			let location = sourceDiagnostics.first?.location.map(\.identity) ?? ""
			if case let .parameterReceivedInAnotherForm(label, _, _, _, _) = kind {
				return "\(kindName) \(location) \(label)"
			} else if case let .publicMockHandsOptionalWrapperOfRequiredValue(label, _, _, _, _) = kind {
				return "\(kindName) \(location) \(label)"
			} else {
				return "\(kindName) \(location)"
			}
		}

		/// Whether this finding comes before `other`: by where each of its diagnostics is reported, then where the place it
		/// names is declared, then where each declaration of the path to that place is, then by kind, so the order of two at one
		/// location never depends on a name; it chooses nothing, and follows the file of each place. A seam that builds one type
		/// under two parents reaches one place through two paths that differ only in the declarations along them, so the
		/// path orders them. Their messages break only a tie between findings that print the same.
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
			case .declarationHiddenByField:
				"declarationHiddenByField"
			case .sendableWrapperReadBesidePlainMemo:
				"sendableWrapperReadBesidePlainMemo"
			case .declarationBoundOnCycleReentry:
				"declarationBoundOnCycleReentry"
			case .declarationBoundAfterSite:
				"declarationBoundAfterSite"
			case .receivesInstantiatorBuildingSite:
				"receivesInstantiatorBuildingSite"
			case .declarationBoundOnPathToReenteringCall:
				"declarationBoundOnPathToReenteringCall"
			case .fieldOfReenteringPlace:
				"fieldOfReenteringPlace"
			case .closesCycleInSeamTree:
				"closesCycleInSeamTree"
			case .fieldFormsDifferBetweenPlaces:
				"fieldFormsDifferBetweenPlaces"
			case .parameterReceivedInAnotherForm:
				"parameterReceivedInAnotherForm"
			case .publicMockHandsOptionalWrapperOfRequiredValue:
				"publicMockHandsOptionalWrapperOfRequiredValue"
			case .placeInsideFillOfCaseOfBothRootEnums:
				"placeInsideFillOfCaseOfBothRootEnums"
			}
		}

		var sourceDiagnostics: [SourceDiagnostic] {
			// Every place the finding holds for, which may be cases of one builder or of several, of one seam or of several.
			let places = namedPlaces
			let namesSeveralSeams = Set(places.map(\.seamType.asSource)).count > 1
			// A place in a scope enum is named by its case's name too, beside its builder, never qualified by a generated type,
			// and, where the places are several seams', by the seam whose tree holds it.
			func placeDescription(of place: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace, namingSeam: Bool) -> String {
				"`\(place.ownerType.asSource)`’s `\(place.property.asSource)`\(place.caseName.map { " (`\($0)` of `\(place.builderLabel)`)" } ?? "")\(namingSeam ? " in `\(place.seamType.asSource)`’s tree" : "")"
			}
			func builderDescription(of hole: SeamSignature.Hole) -> String {
				"the builder for \(placeDescription(of: SeamSignature.Hole.UncarriedDeclaration.PresentedPlace(hole), namingSeam: false))"
			}
			/// `items`, joined as a sentence lists them, each once: places that differ only in what an item leaves out are next
			/// to each other in `nameOrder`.
			func listed(_ items: [String]) -> String {
				var distinctItems = [String]()
				for item in items where distinctItems.last != item {
					distinctItems.append(item)
				}
				return distinctItems.count > 2 ? distinctItems.dropLast().joined(separator: ", ") + ", and " + (distinctItems.last ?? "") : distinctItems.joined(separator: " and ")
			}
			/// `items`, each once, joined as a sentence offers alternatives.
			func listedAlternatives(_ items: [String]) -> String {
				items.count > 2 ? items.dropLast().joined(separator: ", ") + ", or " + (items.last ?? "") : items.joined(separator: " or ")
			}
			// A seam takes one builder per label, so places of several seams are cases of several builders.
			let namesSeveralBuilders = Set(places.map { "\($0.seamType.asSource) \($0.builderLabel)" }).count > 1
			let namedBuilders = "the builder\(namesSeveralBuilders ? "s" : "") for \(listed(places.map { placeDescription(of: $0, namingSeam: namesSeveralSeams) }))"
			let builderPronoun = namesSeveralBuilders ? "them" : "it"
			let buildersPossessive = namesSeveralBuilders ? "builders’" : "builder’s"
			let builder = builderDescription(of: hole)
			let seamName = "`\(hole.scopeSeamType.asSource)`"
			func module(_ identity: ModuleIdentity) -> String {
				identity.moduleName.map { "module `\($0)`" } ?? "this module"
			}
			func builderOfDeclaration(_ declaration: SeamSignature.Hole.UncarriedDeclaration) -> String {
				declaration.declaringType == hole.scopeSeamType ? "\(seamName)’s dependency tree" : "`\(declaration.declaringType.asSource)`"
			}
			/// How `seam` binds `declaration` on its path to its call of `calledSeam`.
			func boundOnPathToCall(of declaration: SeamSignature.Hole.UncarriedDeclaration, seam: TypeDescription, calledSeams: String) -> String {
				if let parameterTakingType = declaration.parameterTakingType {
					"`\(parameterTakingType.asSource)`’s builder function takes as a parameter on the path where `\(seam.asSource)` calls \(calledSeams), because a cycle inside `\(parameterTakingType.asSource)`’s tree passes it"
				} else if declaration.declaringType == seam {
					"`\(seam.asSource)` builds where it calls \(calledSeams)"
				} else {
					"`\(declaration.declaringType.asSource)` builds on the path where `\(seam.asSource)` calls \(calledSeams)"
				}
			}
			/// What `calls`, made inside a fill, instantiate, named as written: `seamBuiltAgain` itself, or a seam that builds it
			/// again, such as one that passes its place up. Each list is in name order, which only presents it.
			func instantiatesAgain(_ calls: [(calledSeam: TypeDescription, label: String)], seamBuiltAgain: TypeDescription) -> String {
				let seamBuiltAgainName = seamBuiltAgain.asSource
				let directLabels = Set(calls.filter { $0.calledSeam.asSource == seamBuiltAgainName }.map(\.label)).sorted()
				let callsThroughOtherSeams = calls.filter { $0.calledSeam.asSource != seamBuiltAgainName }
				var parts = [String]()
				if !directLabels.isEmpty {
					parts.append("`\(seamBuiltAgainName)` again (\(listed(directLabels.map { "`\($0)`" })))")
				}
				if !callsThroughOtherSeams.isEmpty {
					let otherSeams = Set(callsThroughOtherSeams.map(\.calledSeam.asSource)).sorted()
					let otherLabels = Set(callsThroughOtherSeams.map(\.label)).sorted()
					parts.append("\(listed(otherSeams.map { "`\($0)`" })) (\(listed(otherLabels.map { "`\($0)`" }))), which \(otherSeams.count > 1 ? "instantiate" : "instantiates") `\(seamBuiltAgainName)` again")
				}
				return parts.joined(separator: " and ")
			}
			func fulfillRemedy(_ seamModule: ModuleIdentity) -> String {
				SeamAccessExplanation.fulfillRemedy(fulfilling: hole.instantiatedType, seamModuleName: seamModule.moduleName, effect: nil)
			}
			/// The remedies for `reader`'s receive in a fill's tree of `declaration`, an instantiator the seam's tree instantiates.
			/// Where the seam's caller holds everything the instantiator's tree receives, a type above the seam can build it: a
			/// parameter of the seam is bound before every site, and the seam's caller, which fills the builder, holds it.
			/// Otherwise, where the declaration's type builds it after the property that leads to the place, the reader's module
			/// can build both in one type of its own, which fills one hole in their place, so the reader is in the tree that
			/// builds the instantiator, unless a place of that tree is one a module whose fill the reader's does not see fills.
			/// Otherwise none moves the instantiator.
			func receiveInstantiatorRemedies(_ declaration: SeamSignature.Hole.UncarriedDeclaration, reader: Reader) -> [String] {
				if declaration.isBuildableAboveSeam {
					["instantiate `\(declaration.property.label)` on a type above \(seamName), and receive it on `\(declaration.declaringType.asSource)` in place of its @\(Dependency.Source.instantiatedRawValue) declaration, so that the caller’s tree builds it"]
				} else if let builtAfter = declaration.builtAfter, !declaration.holdsPlaceFilledElsewhere {
					["declare `\(declaration.property.label)` and `\(builtAfter.label)` on one type of \(module(reader.fillingModule)) instead, and have `\(declaration.declaringType.asSource)` instantiate a protocol that type fulfills in their place, so that type’s tree builds both"]
				} else {
					[]
				}
			}
			switch kind {
			case let .fieldNotReadable(reader, field, callerModule, seamModule, requirement):
				let level = "`\(field.access.spelledOnGeneratedDeclaration)`"
				// A caller SafeDI is told no package of may be in the seam's package all the same.
				let packageNameRemedy = ModuleIdentity.packageNameRemedy(emitter: callerModule, declarer: seamModule, declaredLevel: field.access)
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
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which SafeDI hands \(namedBuilders) only at \(level) access, and \(reach).\(causeText) \(SeamAccessExplanation.joined(remedies))"),
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
					"since `\(parameterTakingType.asSource)`’s builder function takes it as a parameter, because a cycle inside `\(parameterTakingType.asSource)`’s tree passes it, and no type \(seamName)’s tree builds in that function requires `\(reader.property.asSource)`. \(readerRemedy.prefix(1).uppercased())\(readerRemedy.dropFirst()), or \(fulfillRemedy(seamModule))."
				} else {
					"since \(seamName)’s tree receives it only if available. Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on \(seamName), or \(readerRemedy)."
				}
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which SafeDI hands \(namedBuilders) only as `\(field.property.asSource)`, \(cause)"),
					SourceDiagnostic(severity: .note, location: field.declarationLocation, message: "`\(field.declaringType.asSource)` receives `\(field.property.asSource)` here."),
				]
			case let .declarationHiddenByField(reader, declaration, field, _):
				let receivingSeam = "`\(declaration.receivingSeam.asSource)`"
				// The seam receives the wrapper the declaration provides, required, as its tree receives the instance: a seam
				// whose tree receives one label in two forms, an optional and a required one, is rejected.
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)` builds where it calls `\(declaration.calledSeam.asSource)`, but SafeDI hands \(namedBuilders) only its instance, `\(field.property.asSource)`, which \(receivingSeam)’s tree receives. Declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on \(receivingSeam), so SafeDI hands it to the builder\(namesSeveralBuilders ? "s" : "")."),
					SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "`\(declaration.declaringType.asSource)` declares `\(declaration.property.asSource)` here."),
				]
			case let .sendableWrapperReadBesidePlainMemo(reader, memo, instanceReader, routes):
				let memoProperty = Property(label: memo.property.label, typeDescription: memo.memoType ?? memo.property.typeDescription)
				var seams = [String]()
				for route in routes where !seams.contains("`\(route.seamType.asSource)`’s") {
					seams.append("`\(route.seamType.asSource)`’s")
				}
				let trees = seams.count > 1 ? "trees read" : "tree reads"
				// The reader requires the wrapper, so the value it receives instead is required too.
				let instance = reader.property.asLazilyInstantiatedInstanceProperty ?? instanceReader.property
				let builderTrees = seams.count > 1 ? "those builders’ trees receive" : "that builder’s tree receives"
				let wrapperRemedy = "receive `\(reader.property.asSource)` wherever \(builderTrees) `\(instanceReader.property.asSource)`"
				// Where the tree reads the label inside a `@Sendable` function, the fill binds the memo's value, which it creates where
				// the fill is handed its values struct: a reader of the value there would read one created before inline creates it.
				let remedy = memo.bindsMemo
					? "Receive `\(instance.asSource)` on `\(reader.type.asSource)`, or \(wrapperRemedy)."
					: "\(wrapperRemedy.prefix(1).uppercased())\(wrapperRemedy.dropFirst())."
				var diagnostics = [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which SafeDI hands \(namedBuilders) only as `\(memoProperty.asSource)`, since \(listed(seams)) \(trees) `\(reader.property.label)` outside a `@Sendable` function and `\(instanceReader.type.asSource)` receives its instance, `\(instanceReader.property.asSource)`. \(remedy)"),
					SourceDiagnostic(severity: .note, location: instanceReader.declarationLocation, message: "`\(instanceReader.type.asSource)` receives `\(instanceReader.property.asSource)` here."),
				]
				// Seams that build one type in their trees note its receive once.
				for route in routes {
					let note = SourceDiagnostic(severity: .note, location: route.receivedAt, message: "`\(route.receivingType.asSource)` receives `\(route.receivedProperty.asSource)` here.")
					if !diagnostics.contains(note) {
						diagnostics.append(note)
					}
				}
				return diagnostics
			case let .declarationBoundOnCycleReentry(reader, declaration, seamModule):
				let declaringType = "`\(declaration.declaringType.asSource)`"
				let closedOnDeclaringType = "`\(declaration.closedOnDeclaringType.asSource)`"
				let builtType = "`\(declaration.closedOnBuiltType.asSource)`"
				let between = "between where \(closedOnDeclaringType) instantiates `\(declaration.closedOnProperty.asSource)` and where `\(declaration.reenteringType.asSource)` instantiates it again"
				let declared = if let parameterTakingType = declaration.parameterTakingType {
					"which `\(parameterTakingType.asSource)`’s builder function takes as a parameter \(between), because a cycle inside `\(parameterTakingType.asSource)`’s tree passes it (\(declaringType) declares `\(declaration.property.asSource)`). Inline, the \(builtType) built again receives the `\(declaration.property.label)` that parameter is passed"
				} else {
					"which \(declaringType) declares \(between). Inline, the \(builtType) built again receives \(declaringType)’s `\(declaration.property.label)`"
				}
				// A cycle around a call of the seam the place came from reaches the builder only through what that seam receives.
				let receiveRemedy: String? = if declaration.placeIsInFurtherSendableFunction {
					nil
				} else if let calledSeamType = declaration.calledSeamType {
					"Declare `\(reader.receiveSpelling)` on `\(calledSeamType.asSource)`, so each \(builtType) passes its `\(calledSeamType.asSource)` the `\(declaration.property.label)` of its own level, which the builder is then handed"
				} else {
					"Declare `\(reader.receiveSpelling)` on \(builtType), so each \(builtType) receives the `\(declaration.property.label)` of its own level and hands it on"
				}
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, \(declared), but SafeDI hands \(namedBuilders) the same values at every level of that cycle. \(receiveRemedy.map { "\($0), or \(fulfillRemedy(seamModule))" } ?? fulfillRemedy(seamModule).prefix(1).uppercased() + fulfillRemedy(seamModule).dropFirst())."),
				] + (declaration.declarationLocation.map { [SourceDiagnostic(severity: .note, location: $0, message: "\(declaringType) declares `\(declaration.property.asSource)` here.")] } ?? [])
			case let .declarationBoundAfterSite(reader, declaration, seamModule):
				// A parameter of a builder function a lazy cycle closes on is declared, as far as the reader is told, by the first
				// type in the function's body that receives it, and an alias by the type that receives it under its label.
				let isAlias = if case .boundOutsideSendableFunction(_, _, _, _, _?) = declaration.reason {
					true
				} else {
					false
				}
				let noteVerb = declaration.parameterTakingType == nil && !isAlias && !declaration.isBoundFromCallersArgument ? "declares" : "receives"
				let declarationNote = SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "`\(declaration.declaringType.asSource)` \(noteVerb) `\(declaration.property.asSource)` here.")
				let pathScope = "`\(declaration.builtAfter?.label ?? "")`"
				// An instantiator the seam's tree builds after the site can move above the seam, or beside the place.
				var remedies = [String]()
				if ScopeGenerator.isBuilder(declaration.property) {
					remedies += receiveInstantiatorRemedies(declaration, reader: reader)
				}
				remedies.append(fulfillRemedy(seamModule))
				// What a message about a place built inside a `@Sendable` function, `functionProperty`'s, says of the values its
				// builder is handed, and the remedy every such message ends with when it has no other.
				func outside(_ functionProperty: Property) -> String {
					"outside the `@Sendable` function that builds `\(functionProperty.asSource)`, and SafeDI hands \(namedBuilders) only what that function binds."
				}
				let capitalizedFulfillRemedy = "\(fulfillRemedy(seamModule).prefix(1).uppercased())\(fulfillRemedy(seamModule).dropFirst())."
				/// The remedy that forwards `property` into `function`, the `@Sendable` function that builds `functionProperty`,
				/// `again` where an enclosing type forwards it already. Only an instantiator is passed forwarded values, so a lazy
				/// wrapper becomes an instantiator of the type as well; a function no forwarded value reaches leaves only filling
				/// the builder in the seam's module.
				func forwardingRemedy(of property: Property, into functionProperty: Property, function: SeamSignature.Hole.UncarriedDeclaration.SendableFunction, again: Bool) -> String {
					func forward(on builtType: TypeDescription) -> String {
						"Declare `@\(Dependency.Source.forwardedRawValue) let \(property.asSource)` on `\(builtType.asSource)`\(again ? " too" : "")"
					}
					return switch function {
					case let .instantiator(builtType):
						"\(forward(on: builtType)), so that function binds it, or \(fulfillRemedy(seamModule))."
					case let .sendableLazyWrapper(builtType):
						"\(forward(on: builtType)), and `\(functionProperty.label)` as `\(TypeDescription.simple(name: Dependency.sendableInstantiatorType, generics: [builtType]).asSource)`, so that function binds it, or \(fulfillRemedy(seamModule))."
					case .other:
						capitalizedFulfillRemedy
					}
				}
				/// The remedy for the declaration, which the seam's tree instantiates outside `function`, the `@Sendable` function
				/// that builds `functionProperty`: where the seam declares it and a type above the seam can build it, the seam
				/// receives it, which the function's caller then reads; otherwise the type the function builds takes it forwarded.
				/// Receiving it on the seam reaches the place only where the seam declares the value itself: a type of its tree, or a
				/// seam it calls, that declares it still binds it outside the function, and a seam it calls carries its own receive
				/// of it in the struct its fill binds, so the place would get the same error.
				func instantiatedOutsideFunctionRemedy(functionProperty: Property, function: SeamSignature.Hole.UncarriedDeclaration.SendableFunction) -> String {
					if declaration.isBuildableAboveSeam, declaration.declaringType == hole.scopeSeamType {
						"Instantiate `\(declaration.property.label)` outside \(seamName) and declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on \(seamName), so the \(buildersPossessive) caller reads its own, or \(fulfillRemedy(seamModule))."
					} else {
						forwardingRemedy(of: declaration.property, into: functionProperty, function: function, again: false)
					}
				}
				/// The message of a declaration `seam` binds on a path to calls that present the places the finding names, whose
				/// builders it passes up: each place itself, or the place a fill fills, when the reader is beneath a place inside
				/// that fill. Every part a place decides – the seams whose calls present them, the builders, each remedy – comes
				/// from every place named, so two findings that differ only in their places print alike and merge, and none is
				/// picked by where its place is declared.
				func boundByPassingUpSeamMessage(seam: TypeDescription) -> String {
					/// The seams whose trees hold `orderedPlaces`, each once, in the order of the places the message names, which a
					/// renaming of the types moves together.
					func seamsInPlaceOrder(_ orderedPlaces: [SeamSignature.Hole.UncarriedDeclaration.PresentedPlace]) -> [String] {
						var seams = [String]()
						for place in orderedPlaces where !seams.contains("`\(place.seamType.asSource)`") {
							seams.append("`\(place.seamType.asSource)`")
						}
						return seams
					}
					let calledSeams = listed(seamsInPlaceOrder(places))
					/// The remedy that fulfills the types `remediedPlaces` instantiate.
					func fulfillRemedy(of remediedPlaces: [SeamSignature.Hole.UncarriedDeclaration.PresentedPlace]) -> String {
						listed(remediedPlaces.map { SeamAccessExplanation.fulfillRemedy(fulfilling: $0.instantiatedType, seamModuleName: seamModule.moduleName, effect: .seamFillsBuilder(seam, isPlural: namesSeveralBuilders)) }.sorted())
					}
					var message = places.allSatisfy { $0.seamType == seam }
						? "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(seam.asSource)`’s tree builds where it instantiates `\(seam.asSource)` again, but that call passes the builder\(namesSeveralBuilders ? "s" : "") `\(seam.asSource)` takes for \(listed(places.map { "`\($0.ownerType.asSource)`’s `\($0.property.asSource)`" })) on unchanged, so the caller that fills \(builderPronoun) cannot hand \(builderPronoun) those values."
						: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(boundOnPathToCall(of: declaration, seam: seam, calledSeams: calledSeams)), but `\(seam.asSource)` passes \(namedBuilders) on from its own caller, which cannot hand \(builderPronoun) \(declaration.declaringType == seam ? "`\(seam.asSource)`’s values" : "that value")."
					// A place a `@Sendable` function builds is handed only what that function binds, so no parameter of the place's
					// seam carries the value: its fill reads the caller's own. Places of both kinds take each remedy once.
					let sendablePlaces = places.filter(\.isBuiltBySendableBuilder)
					let plainPlaces = places.filter { !$0.isBuiltBySendableBuilder }
					if !sendablePlaces.isEmpty {
						message += " Instantiate `\(declaration.property.label)` outside `\(seam.asSource)` and declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on `\(seam.asSource)`, so the \(buildersPossessive) caller reads its own, or \(fulfillRemedy(of: sendablePlaces))."
					}
					if !plainPlaces.isEmpty {
						// The called seam receives the value as the reader does: a required receive of an optional there is
						// unfulfilled where the caller binds the value itself.
						message += " Declare `\(reader.receiveSpelling)` on \(listed(seamsInPlaceOrder(plainPlaces))), so SafeDI hands it to the builder\(namesSeveralBuilders ? "s" : ""), or \(fulfillRemedy(of: plainPlaces))."
					}
					return message
				}
				let message = switch declaration.reason {
				case let .boundByPassingUpSeam(seam, _, _):
					boundByPassingUpSeamMessage(seam: seam)
				case let .receivesPathScopeOnlyIfAvailable(type):
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(builderOfDeclaration(declaration)) builds after \(pathScope), since `\(type.asSource)` receives \(pathScope) only if available, so SafeDI does not hand it to \(namedBuilders). Receive \(pathScope) on `\(type.asSource)` some other way, or \(fulfillRemedy(seamModule))."
				case let .requiresOtherCarrier(type, carrier):
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(builderOfDeclaration(declaration)) builds after \(pathScope), since `\(type.asSource)` requires `\(carrier.label)`, which carries another builder, so SafeDI does not hand it to \(namedBuilders). Declare `\(declaration.property.label)` before \(pathScope) in `\(declaration.declaringType.asSource)`, or \(fulfillRemedy(seamModule))."
				case .other, .instantiatorBuildingSite:
					// The builder is named once, so the sentence that it does not carry the value refers back to it.
					"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(declaration.declaringType == hole.scopeSeamType ? "\(seamName)’s tree builds only after it calls" : "`\(declaration.declaringType.asSource)` builds only after \(seamName)’s tree calls") \(namedBuilders), so SafeDI does not hand it to \(namesSeveralBuilders ? "those builders" : "that builder"). \(SeamAccessExplanation.joined(remedies))"
				case let .boundOutsideSendableFunction(functionProperty, function, isForwarded, cycleParameter, alias):
					// A place built inside a `@Sendable` function is handed only what that function binds, whether the read is
					// required or only if available: a silent `nil` would hand the fill another value than inline's.
					if let cycleParameter {
						// A parameter of a builder function a cycle closes on is the value the cycle passes: only forwarding it
						// into the `@Sendable` function binds it there.
						"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(cycleParameter.takingType.asSource)`’s builder function takes as a parameter outside the `@Sendable` function that builds `\(functionProperty.asSource)`, because a cycle inside `\(cycleParameter.takingType.asSource)`’s tree passes it (`\(cycleParameter.declaringType.asSource)` \(cycleParameter.isForwarded ? "forwards" : "declares") `\(cycleParameter.property.asSource)`), and SafeDI hands \(namedBuilders) only what that function binds. "
							+ forwardingRemedy(of: cycleParameter.property, into: functionProperty, function: function, again: true)
					} else if let alias {
						// An alias binds the label to another value than the caller's own of that label, which is all a fill reads:
						// the type receives the label without the alias, and the seam's caller hands it the label's value.
						if alias.isSeams {
							"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)` receives as the caller’s `\(alias.fulfillingProperty.label)` \(outside(functionProperty)) Declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on `\(declaration.declaringType.asSource)` without `fulfilledByDependencyNamed: \"\(alias.fulfillingProperty.label)\"`, so the \(buildersPossessive) caller reads its own, or \(fulfillRemedy(seamModule))."
						} else {
							// The alias's type is inside the seam's tree, which binds the property the alias reads: without the alias,
							// the label comes from above the seam only once nothing in its tree declares it.
							"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)` receives as `\(alias.fulfillingProperty.label)` \(outside(functionProperty)) Declare `@\(Dependency.Source.receivedRawValue) let \(declaration.property.asSource)` on `\(declaration.declaringType.asSource)` without `fulfilledByDependencyNamed: \"\(alias.fulfillingProperty.label)\"`, and instantiate `\(declaration.property.label)` outside \(seamName), so the \(buildersPossessive) caller reads its own, or \(fulfillRemedy(seamModule))."
						}
					} else if declaration.isBoundFromCallersArgument {
						// A value a public mock binds at its root from what its caller passes, which this caller holds no
						// declaration of in that form to pass (`Scope.fillUnderConstruction`): the mock may build its own, which the
						// fill cannot read. A deliberate gap against the twin, whose seam takes the value as a parameter
						// (`seam-holes.md`).
						"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)`’s public mock binds from the `\(declaration.property.label)` its caller passes, \(outside(functionProperty)) Its caller passes no `\(declaration.property.asSource)` of its own, so the mock may build its own. Instantiate `\(declaration.property.label)` above the call of `\(declaration.declaringType.asSource)`’s public mock, so the call passes it and the \(buildersPossessive) caller reads it, or \(fulfillRemedy(seamModule))."
					} else {
						"`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which `\(declaration.declaringType.asSource)` \(isForwarded ? "forwards" : "declares") \(outside(functionProperty)) "
							+ (isForwarded
								? forwardingRemedy(of: declaration.property, into: functionProperty, function: function, again: true)
								: instantiatedOutsideFunctionRemedy(functionProperty: functionProperty, function: function))
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
				let remedies = receiveInstantiatorRemedies(declaration, reader: reader) + [fulfillRemedy(seamModule)]
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(seamName)’s tree is building where it calls \(namedBuilders). Inline, `\(reader.type.asSource)` can get an instantiator of its own, made from the function \(seamName)’s initializer declares for `\(declaration.property.label)`, which code generated outside \(module(seamModule)) cannot refer to. \(SeamAccessExplanation.joined(remedies))"),
					SourceDiagnostic(severity: .note, location: declaration.declarationLocation, message: "`\(declaration.declaringType.asSource)` instantiates `\(declaration.property.asSource)` here."),
				]
			case let .declarationBoundOnPathToReenteringCall(reader, readsOnlyIfAvailable, hidings, reenteredPlace, fillingModule, seamModule):
				// One clause per declaration and call, naming the places of every path that reaches that call from that
				// declaration, in the order of the declaring type, then the call, then the places: which path a walk meets first
				// follows the order of the files that declare the fills' places, so none is picked.
				struct Clause {
					let declaration: SeamSignature.Hole.ReenteringCallDeclaration
					var places: [SeamSignature.Hole.UncarriedDeclaration.PresentedPlace]

					var order: [String] {
						[declaration.declaringType.asSource, declaration.property.asSource, declaration.callingType.asSource, declaration.calledSeam.asSource, declaration.callProperty.asSource]
					}
				}
				var clauses = [Clause]()
				for hiding in hidings {
					let clause = Clause(declaration: hiding, places: [hiding.pathPlace])
					if let index = clauses.firstIndex(where: { $0.order == clause.order }) {
						clauses[index].places += clause.places
					} else {
						clauses.append(clause)
					}
				}
				clauses.sort { $0.order.lexicographicallyPrecedes($1.order) }
				let clauseTexts = clauses.map { clause in
					let places = clause.places.sorted { $0.nameOrder.lexicographicallyPrecedes($1.nameOrder) }
					let namesSeveralPlaces = Set(places.map(\.nameOrder)).count > 1
					let namesSeveralBuilders = Set(places.map { "\($0.seamType.asSource) \($0.builderLabel)" }).count > 1
					return "`\(clause.declaration.declaringType.asSource)` declares on the path\(namesSeveralPlaces ? "s" : "") from the builder\(namesSeveralBuilders ? "s" : "") for \(listed(places.map { placeDescription(of: $0, namingSeam: false) })) to the call by which `\(clause.declaration.callingType.asSource)` instantiates \(instantiatesAgain([(clause.declaration.calledSeam, clause.declaration.callProperty.label)], seamBuiltAgain: reenteredPlace.seamType))"
				}
				let callsAreSeveral = Set(clauses.map { [$0.declaration.callingType.asSource, $0.declaration.calledSeam.asSource, $0.declaration.callProperty.label] }).count > 1
				// A declaration two calls hide from is noted once. Each note is a diagnostic of its own, so the notes follow where
				// the declarations are, not the names the clauses are ordered by.
				var notes = [SourceDiagnostic]()
				for clause in clauses {
					let note = SourceDiagnostic(severity: .note, location: clause.declaration.declarationLocation, message: "`\(clause.declaration.declaringType.asSource)` declares `\(clause.declaration.property.asSource)` here.")
					if !notes.contains(note) {
						notes.append(note)
					}
				}
				notes.sort(by: SourceDiagnostic.precedesInSourceOrder)
				let declaringTypes = listed(clauses.map { "`\($0.declaration.declaringType.asSource)`’s" })
				// The remedy fulfills the type every place the finding names instantiates, each once, so two findings that differ
				// only in their places print alike and merge, and no place's type is picked by where it is declared.
				var remediedTypes = [TypeDescription]()
				for place in places where !remediedTypes.contains(place.instantiatedType) {
					remediedTypes.append(place.instantiatedType)
				}
				let fulfillRemedies = listed(remediedTypes.map { SeamAccessExplanation.fulfillRemedy(fulfilling: $0, seamModuleName: seamModule.moduleName, effect: nil) })
				// The seam built again carries the label for its fill when it receives it as the reader does. A receive only if
				// available stays one, since a route that binds no value hands the reader `nil` inline. A required receive there
				// needs a value on every route to the seam, which the seam's module cannot see past its own callers; the reader can
				// instead receive it only if available, as the seam then does.
				let seamBuiltAgain = "`\(reenteredPlace.seamType.asSource)`"
				let receiveOnlyIfAvailable = "@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true)"
				let remedies = if readsOnlyIfAvailable {
					"Declare `\(receiveOnlyIfAvailable) let \(reader.property.asSource)` on \(seamBuiltAgain), so SafeDI hands it to the builder, or \(fulfillRemedies)."
				} else {
					"Declare `@\(Dependency.Source.receivedRawValue) let \(reader.property.asSource)` on \(seamBuiltAgain), with `\(reader.property.label)` declared on every route to \(seamBuiltAgain), so SafeDI hands it to the builder; receive it only if available on \(seamBuiltAgain) and `\(reader.type.asSource)`, with `\(receiveOnlyIfAvailable) let \(reader.property.asOptionalProperty.asSource)`; or \(fulfillRemedies)."
				}
				return [
					SourceDiagnostic(severity: .error, location: reader.declarationLocation, message: "`\(reader.type.asSource)` receives `\(reader.property.asSource)`, which \(listed(clauseTexts)), but \(callsAreSeveral ? "those calls pass" : "that call passes") the builder on as \(module(fillingModule)) fills it, which cannot hand it \(declaringTypes) values. \(remedies)"),
				] + notes
			case let .fieldOfReenteringPlace(reader, isOnlyIfAvailable, carried, reenteredPlace, fillingModule, seamModule):
				// Every place whose fill reopens the seam, every type that declares what those places carry, and every call: which
				// place a walk meets first follows the order of the files that declare them, so none is picked. Each list is in
				// name order, which only presents them.
				var places = [SeamSignature.Hole.UncarriedDeclaration.PresentedPlace]()
				for place in carried.map(\.reenteringPlace).sorted(by: { $0.nameOrder.lexicographicallyPrecedes($1.nameOrder) }) where places.last?.nameOrder != place.nameOrder {
					places.append(place)
				}
				let carriedNamesSeveralBuilders = Set(places.map { "\($0.seamType.asSource) \($0.builderLabel)" }).count > 1
				let fillsInstantiate = places.count > 1 ? "each of their fills instantiates" : "that builder’s fill instantiates"
				// The seam built again, beneath the place whose fill reopens it, which a call names as written: it can be of a
				// seam that builds the seam built again, such as one that passes its place up.
				let seamBuiltAgain = "`\(reenteredPlace.seamType.asSource)`"
				let callsAreSeveral = Set(carried.map { "\($0.calledSeam.asSource) \($0.callProperty.label)" }).count > 1
				let carriers = "the builder\(carriedNamesSeveralBuilders ? "s" : "") for \(listed(places.map { placeDescription(of: $0, namingSeam: false) })) \(carriedNamesSeveralBuilders ? "carry" : "carries") from \(listed(Set(carried.map(\.field.declaringType.asSource)).sorted().map { "`\($0)`" })), and \(fillsInstantiate) \(instantiatesAgain(carried.map { ($0.calledSeam, $0.callProperty.label) }, seamBuiltAgain: reenteredPlace.seamType))"
				let declaringTypes = Set(carried.map(\.field.declaringType.asSource)).sorted().map { "`\($0)`’s" }
				// The forms the places carry differ at most in optionality, each providing the receive: the remedy spells the
				// first in name order.
				let field = carried.map(\.field).min { $0.property.asSource < $1.property.asSource } ?? SeamSignature.Hole.Field(property: reader.property, access: .public, declaringType: reenteredPlace.seamType, declarationLocation: nil)
				let receive = isOnlyIfAvailable
					? "@\(Dependency.Source.receivedRawValue)(onlyIfAvailable: true) let \((field.property.typeDescription.isOptional ? field.property : field.property.asOptionalProperty).asSource)"
					: "@\(Dependency.Source.receivedRawValue) let \(field.property.asSource)"
				let handed = isOnlyIfAvailable ? "`nil` or another value" : "another value"
				// A seam's call in the fill passes the value on to the seam's tree: it is reported where the call is declared.
				let (readerName, receives, location) = if let passingCall = reader.passingCall {
					("the call", "The call by which `\(passingCall.callingType.asSource)` instantiates `\(reader.type.asSource)` (`\(passingCall.property.label)`) passes on `\(reader.property.asSource)`", passingCall.declarationLocation)
				} else {
					("`\(reader.type.asSource)`", "`\(reader.type.asSource)` receives `\(reader.property.asSource)`", reader.declarationLocation)
				}
				// The remedy fulfills the type every place the finding holds for instantiates, each once, so two findings that differ
				// only in their places print alike and merge, and no place's type is picked by where it is declared.
				var remediedTypes = [TypeDescription]()
				for place in namedPlaces where !remediedTypes.contains(place.instantiatedType) {
					remediedTypes.append(place.instantiatedType)
				}
				let fulfillRemedies = listed(remediedTypes.map { SeamAccessExplanation.fulfillRemedy(fulfilling: $0, seamModuleName: seamModule.moduleName, effect: nil) })
				// A place a `@Sendable` function builds carries none of the seam's parameters (`fields(of:)`), so its fill reads the
				// outer caller's value whatever the seam receives: only filling the builder in the seam's module helps.
				let remedy = if reenteredPlace.isBuiltBySendableBuilder {
					"SafeDI hands \(namedBuilders) only what a `@Sendable` function binds, so no value \(seamBuiltAgain) receives reaches \(builderPronoun): \(fulfillRemedies)."
				} else {
					"Declare `\(receive)` on \(seamBuiltAgain), so SafeDI hands it to the builder, or \(fulfillRemedies)."
				}
				return [
					SourceDiagnostic(severity: .error, location: location, message: "\(receives), which \(carriers). Inline, \(readerName) would read \(listedAlternatives(declaringTypes)) `\(field.property.label)` inside that \(seamBuiltAgain), but \(callsAreSeveral ? "those calls pass" : "the call passes") the builder on as \(module(fillingModule)) fills it, whose scope there does not carry `\(field.property.label)`, so \(readerName) would get \(handed). \(remedy)"),
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
					"instantiate `\(hole.scopeSeamType.asSource)` where \(closingTypeName) builds `\(closingProperty.typeDescription.asInstantiatedType.asSource)` (`@Instantiated let \(seamSimpleName.prefix(1).lowercased() + seamSimpleName.dropFirst())Builder: Instantiator<\(hole.scopeSeamType.asSource)>`), so the cycle re-enters through the initializer SafeDI generates for \(seamName)",
					fulfillRemedy(seamModule),
				]
				if closesOnOwnerOfHole {
					remedies.append("give `\(closingProperty.label)` on \(closingTypeName) another label, so the cycle closes at `\(hole.property.label)` itself")
				}
				return [
					SourceDiagnostic(severity: .error, location: declarationLocation, message: "SafeDI cannot fill \(builder) in \(seamName)’s dependency tree: \(closer) instantiates `\(closingProperty.asSource)`, which \(seamName)’s tree is building where it builds `\(hole.property.label)` (\(chain.joined(separator: " -> "))). Code generated outside \(module(seamModule)) cannot refer to the function \(seamName)’s initializer builds `\(closingProperty.typeDescription.asInstantiatedType.asSource)` with, and building it again would hand it other values than \(seamName)’s tree holds. \(SeamAccessExplanation.joined(remedies))"),
				] + (closedOnDeclaration.map { [SourceDiagnostic(severity: .note, location: $0.declarationLocation, message: "`\($0.declaringType?.asSource ?? "")` instantiates `\($0.property.asSource)` here.")] } ?? [])
			case let .fieldFormsDifferBetweenPlaces(label, fields, seamModule):
				let forms = fields.map { "`\($0.property.asSource)` (`\($0.declaringType.asSource)`)" }
				let formList = listed(forms)
				let firstForm = fields.first.map { "`\($0.property.asSource)`" } ?? "`\(label)`"
				return [
					SourceDiagnostic(severity: .error, location: fields.first?.declarationLocation, message: "SafeDI fills every place of \(builder) with one function, which reads `\(label)`, but the types on the routes to those places declare it in forms one value cannot carry: \(formList). Declare \(firstForm) on each, or \(fulfillRemedy(seamModule))."),
				] + fields.dropFirst().map { field in
					SourceDiagnostic(severity: .note, location: field.declarationLocation, message: "`\(field.declaringType.asSource)` declares `\(field.property.asSource)` here.")
				}
			case let .parameterReceivedInAnotherForm(label, receivers, remedy, seamType, seamDeclarationLocation):
				return [
					SourceDiagnostic(severity: .error, location: seamDeclarationLocation, message: SeamError.labelCollisionMessage(seamName: "`\(seamType.asSource)`", label: label, receivers: receivers, remedy: remedy)),
				] + SeamError.receiverNotes(receivers)
			case let .publicMockHandsOptionalWrapperOfRequiredValue(label, field, receivers, remedy, mockedTypeDeclarationLocation):
				return [
					SourceDiagnostic(severity: .error, location: mockedTypeDeclarationLocation, message: "SafeDI cannot fill \(namedBuilders) in a call of \(seamName)’s mock: its tree receives `\(label)` as \(SeamError.receivedForms(of: receivers)), so the mock hands the builder only `\(field.property.asSource)`, which holds no value where its caller passes none. \(SeamError.labelCollisionRemedyText(seamName: seamName, label: label, remedy: remedy))"),
				] + SeamError.receiverNotes(receivers)
			case let .placeInsideFillOfCaseOfBothRootEnums(place, callerModule, seamModule):
				let placeDescription = "`\(place.ownerType.asSource)`’s `\(place.property.asSource)`"
				let placeRemedy = SeamAccessExplanation.fulfillRemedy(fulfilling: place.instantiatedType, seamModuleName: callerModule.moduleName, effect: nil)
				return [
					SourceDiagnostic(severity: .error, location: place.declarationLocation ?? hole.declarationLocation, message: "SafeDI fills every place of \(builderDescription(of: hole)) with one function, whose tree builds \(placeDescription), which no type that \(module(callerModule)) can see fulfills. \(seamName) builds `\(hole.ownerType.asSource)` both inside and outside a `@Sendable` function, so that function would be handed the values of either build, and can be handed only one. To fill it, \(placeRemedy), or \(fulfillRemedy(seamModule))."),
					SourceDiagnostic(severity: .note, location: hole.declarationLocation, message: "`\(hole.ownerType.asSource)` instantiates `\(hole.property.asSource)` here."),
				]
			}
		}
	}
}

extension SeamSignature.Hole.UncarriedDeclaration.PresentedPlace {
	/// The order a diagnostic lists places in: by the type that declares the place, then its label, then everything else
	/// that tells two places apart. Two places of equal order are the same place.
	fileprivate var nameOrder: [String] {
		[ownerType.asSource, property.label, property.typeDescription.asSource, caseName ?? "", builderLabel, seamType.asSource, instantiatedType.asSource, isBuiltBySendableBuilder ? "@Sendable" : ""]
	}
}

extension SeamSignature.Hole.ReenteringCallDeclaration {
	/// Everything that tells two such declarations apart, which a place's list holds once each.
	fileprivate var identity: [String] {
		var identity = [property.label, property.typeDescription.asSource, declaringType.asSource, declarationLocation.map(\.identity) ?? ""]
		identity += pathPlace.nameOrder
		identity += [callingType.asSource, callProperty.label, callProperty.typeDescription.asSource, calledSeam.asSource]
		identity += reenteredPlace.nameOrder
		identity += [reenteredSeamModule.moduleName ?? "", reenteredSeamModule.packageName ?? "", fillingModule.moduleName ?? "", fillingModule.packageName ?? ""]
		return identity
	}

	/// The reader's finding is grouped by this, as the visible build reports one per fill of a place built again.
	fileprivate var reenteredIdentity: [String] {
		reenteredPlace.nameOrder + [reenteredSeamModule.moduleName ?? "", reenteredSeamModule.packageName ?? "", fillingModule.moduleName ?? "", fillingModule.packageName ?? ""]
	}
}

extension SeamSignature.Hole.ReenteringPlaceField {
	/// Everything that tells two such fields apart, which a place's list holds once each.
	fileprivate var identity: [String] {
		var identity = [carried.field.property.label, carried.field.property.typeDescription.asSource, carried.field.declaringType.asSource, carried.field.declarationLocation.map(\.identity) ?? ""]
		identity += carried.reenteringPlace.nameOrder
		identity += [carried.callProperty.label, carried.callProperty.typeDescription.asSource, carried.calledSeam.asSource]
		identity += reenteredIdentity
		return identity
	}

	/// The reader's finding is grouped by this, as the visible build reports one per fill of a place built again.
	fileprivate var reenteredIdentity: [String] {
		reenteredPlace.nameOrder + [reenteredSeamModule.moduleName ?? "", reenteredSeamModule.packageName ?? "", fillingModule.moduleName ?? "", fillingModule.packageName ?? ""]
	}
}

extension SeamSignature.Hole.UncarriedDeclaration {
	/// This declaration, bound after the site for `reason`.
	func with(reason: Reason) -> SeamSignature.Hole.UncarriedDeclaration {
		var declaration = SeamSignature.Hole.UncarriedDeclaration(property: property, declaringType: declaringType, declarationLocation: declarationLocation, parameterTakingType: parameterTakingType, builtAfter: builtAfter, reason: reason)
		declaration.isBuildableAboveSeam = isBuildableAboveSeam
		declaration.labelsHeldAboveSeam = labelsHeldAboveSeam
		declaration.placesInTree = placesInTree
		return declaration
	}

	/// This declaration, with `isBuildableAboveSeam` kept only where the fill of each place its tree holds, among
	/// `fillsOfCall`, the fills of the seam call whose fill reads it, receives only labels a type above the seam would hold
	/// for that tree (`labelsHeldAboveSeam`). A place none of them fills is filled by a module whose fill this one does not
	/// see, which can read what that module binds, so neither a type above the seam nor one of this module could build the
	/// tree for certain: no remedy moves the declaration (`holdsPlaceFilledElsewhere`).
	func resolvingBuildabilityAboveSeam(fillsOfCall call: ScopeGenerator) -> SeamSignature.Hole.UncarriedDeclaration {
		guard isBuildableAboveSeam, !placesInTree.isEmpty else { return self }
		var declaration = self
		let fulfillingScopes = placesInTree.map { site in call.fill(judgingPlaceAt: site)?.children.first }
		declaration.holdsPlaceFilledElsewhere = fulfillingScopes.contains { $0 == nil }
		declaration.isBuildableAboveSeam = fulfillingScopes.allSatisfy { fulfillingScope in
			fulfillingScope?.receivedProperties.allSatisfy { labelsHeldAboveSeam.contains($0.label) } ?? false
		}
		return declaration
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
