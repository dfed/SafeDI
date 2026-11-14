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

// MARK: - Generated names

/// The `__safeDI_` names one generated Swift scope declares. One allocator serves one scope – a seam's initializer body, a
/// filler's body around one seam call, or a mock's scope that declares the locals its `@Sendable` builder functions read
/// overrides into – and each name is claimed in a fixed order, so two namers can never hand one name out: a seam's body
/// claims its builders' internal names, then the functions that build its wrapper places, then the payloads it binds; a
/// filler's body claims its fills, then its dispatchers; a mock's scope claims each function's locals in the order the
/// mock's body walk reads the overrides (`ScopeGenerator.SendableOverrideExtractor`).
struct GeneratedNameAllocator {
	init(reserving names: Set<String>) {
		taken = names
	}

	/// Claims `base`, with `_` appended while it or any name `occupied` gives for it is taken, and returns what it claimed.
	mutating func claim(_ base: String, occupying occupied: (String) -> [String] = { [$0] }) -> String {
		var name = base
		while occupied(name).contains(where: taken.contains) {
			name = "\(name)_".spelledAsJoinedIdentifier
		}
		taken.formUnion(occupied(name))
		return name
	}

	/// Takes `names` without claiming them: names a scope declares by rules of their own, which nothing claimed later may share.
	mutating func reserve(_ names: some Sequence<String>) {
		taken.formUnion(names)
	}

	private(set) var taken: Set<String>
}

// MARK: - Shaping a seam's builders

extension DependencyTreeGenerator {
	/// The builders a seam's generated initializer, or a public mock, takes for `holes`, its places: `holes` itself, in the
	/// order the builders reach the places and carrying the names the builders settle; the builders; the enums they are
	/// handed; and the first builder, in builder order, that reaches each place, which a diagnostic about the place names.
	struct ShapedBuilders: Sendable {
		let holes: [SeamSignature.Hole]
		let builders: [SeamSignature.Builder]
		let scopeEnums: [SeamSignature.ScopeEnum]
		let builderBySite: [SeamSignature.Hole.Site: SeamSignature.Builder]
		/// How the seam's tree hands each inner seam's enum up from a call whose case is nested by type.
		var callRoutes = [SeamSignature.CallRoute]()
	}

	/// What the scope types a seam or a public mock declares for its builders are named by, and how its builders spell them.
	struct ScopeTypeNames {
		/// The prefix of a plain enum's name.
		let plain: String
		/// The prefix of a `@Sendable` enum's name.
		let sendable: String
		/// Whether a builder spells its own scope types qualified by the type that declares them: a public mock's builder
		/// is spelled once for its own signature and for each module that calls it, as an internal mock's parameter.
		let areQualified: Bool

		/// A seam's: `SafeDIScope_` and `SafeDISendableScope_`, spelled inside its extension.
		static let seam = ScopeTypeNames(plain: "SafeDIScope", sendable: "SafeDISendableScope", areQualified: false)
		/// A public mock's: `SafeDIMockScope_` and `SafeDISendableMockScope_`, apart from the seam's a mocked seam declares beside
		/// them.
		static let publicMock = ScopeTypeNames(plain: "SafeDIMockScope", sendable: "SafeDISendableMockScope", areQualified: true)
	}

	/// Shapes `holes`, every place of `seam`'s tree `generator` the seam's initializer must take a builder for, into builders.
	///
	/// A place the seam builds in plain code is a case of its hole type's plain enum, and a place it builds inside a
	/// `@Sendable` function – a builder function that is `@Sendable`, or a `Sendable` wrapper the place is held in – a case of
	/// its `@Sendable` enum, which the `@Sendable` builder is handed. A call of an inner seam, or of another module's public
	/// mock, that passes up a place its enum reaches is a case holding that enum: of the plain enum when the call is in plain
	/// code and the inner enum plain, and of the `@Sendable` enum otherwise. An enum exists only if it has a case. A seam's
	/// caller fills or passes up per instantiated type, so every place one of its enums reaches is filled or none is; a public
	/// mock's caller decides per place.
	///
	/// Each tier names its builders apart from the parameters it takes, which are its own and those of every wider tier, so
	/// a parameter only a narrower tier takes never renames a wider tier's builder. The widest tier's stems name the enums,
	/// one per hole type and family whatever tier takes them.
	/// - Parameters:
	///   - otherParameters: The labels of a public mock's parameters, each with the access of the narrowest tier that takes
	///     it, which its builders follow and are named apart from as a seam's builders are from its parameters.
	///   - bindsReceivesAgain: Whether the tree is a public mock's, whose levels hold the receives it binds again (see
	///     `mockBindsAgain(receiving:beneath:)`).
	static func shapedBuilders(
		of seam: Instantiable,
		generator: ScopeGenerator,
		holes flatHoles: [SeamSignature.Hole],
		parameters: [SeamSignature.Parameter],
		otherParameters: [(label: String, access: AccessLevel)] = [],
		treeFunctionNames: Set<String>,
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
		ownScopeEnums: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum],
		scopeTypeNames: ScopeTypeNames = .seam,
		bindsReceivesAgain: Bool = false,
	) -> ShapedBuilders {
		guard !flatHoles.isEmpty else { return ShapedBuilders(holes: [], builders: [], scopeEnums: [], builderBySite: [:]) }
		let seamType = seam.concreteInstantiable
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		var holesBySite = Dictionary(flatHoles.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })

		var holeTypesInReachOrder = [SeamSignature.HoleType]()
		var seenHoleTypes = Set<SeamSignature.HoleType>()
		func reach(_ holeType: SeamSignature.HoleType) {
			if seenHoleTypes.insert(holeType).inserted {
				holeTypesInReachOrder.append(holeType)
			}
		}
		var innerAccessByEnum = [SeamSignature.ScopeEnum.Key: [(level: AccessLevel, cause: TypeAccessProof.Cause?, seam: TypeDescription)]]()
		// An enum the builders reach: from the signature of the seam that declares it, where this module computes that seam,
		// else from the call of another module's seam, whose signature carries every enum it reaches as that module settled
		// them. A copy a seam of this module carries can be from an earlier pass.
		var calledSeamsEnums = [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]()
		func reachedEnum(_ key: SeamSignature.ScopeEnum.Key) -> SeamSignature.ScopeEnum? {
			ownScopeEnums[key] ?? calledSeamsEnums[key]
		}
		// A call reaches its enums through its fills too, where it passes no place up: a public mock, which computes no
		// called mock's signature, reads them from each call whose tree leads to a place.
		var generatorsToVisit = [generator]
		while let visited = generatorsToVisit.popLast() {
			for child in visited.children where child.containsBuildSite || child.passesUpBuilder {
				for scopeEnum in child.calledBuilders?.scopeEnums ?? [] where calledSeamsEnums[scopeEnum.key] == nil {
					calledSeamsEnums[scopeEnum.key] = scopeEnum
				}
				generatorsToVisit.append(child)
			}
		}
		// The places and calls of a seam's or a public mock's tree, by hole type, whose enums are nested by type
		// (`scopeEnumsByType`), a place inside a fill included.
		var reachedByHoleType = [SeamSignature.HoleType: [ReachedPlace]]()
		for reached in placesAndCalls(in: generator) {
			switch reached {
			case let .place(sitePath, steps):
				guard let hole = holesBySite[SeamSignature.Hole.Site(seamType: seamType, path: sitePath)] else { continue }
				reach(hole.holeType)
				reachedByHoleType[hole.holeType, default: []].append(ReachedPlace(sitePath: sitePath, steps: steps, call: nil))
			case let .call(sitePath, call, steps, isInSendableFunction):
				guard let calledBuilders = call.calledBuilders else { continue }
				for scopeEnum in calledBuilders.scopeEnums where calledSeamsEnums[scopeEnum.key] == nil {
					calledSeamsEnums[scopeEnum.key] = scopeEnum
				}
				// The call hands up an enum that reaches a place it passes up.
				let passedUpSites = Set(call.passedUpHoles.map(\.site))
				let calledEnumsByKey = calledBuilders.enumsByKey
				// Each hole type the call hands up is reached once, whichever of its families the call hands up.
				var reachedHoleTypes = Set<SeamSignature.HoleType>()
				for builder in calledBuilders.builders {
					let innerKey = builder.enumKey
					guard !SeamSignature.ScopeEnum.sitesReached(from: innerKey, in: calledEnumsByKey).isDisjoint(with: passedUpSites),
					      reachedEnum(innerKey) != nil
					else { continue }
					reach(innerKey.holeType)
					let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: innerKey.holeType, isSendable: innerKey.isSendable || isInSendableFunction)
					if reachedHoleTypes.insert(innerKey.holeType).inserted {
						reachedByHoleType[innerKey.holeType, default: []].append(ReachedPlace(sitePath: sitePath, steps: steps, call: call))
					}
					// The enum is as visible as the inner seam whose enum it holds, and the builder that takes that enum.
					let innerSeamAccess = proof.access(ofParameterTyped: innerKey.seamType, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, instantiables[innerKey.seamType]?.moduleName]))
					innerAccessByEnum[key, default: []].append((min(innerSeamAccess.level, builder.tierAccess), builder.accessCause ?? innerSeamAccess.cause, innerKey.seamType))
				}
			}
		}

		// The stem of each hole type, from its instantiated type, named apart.
		let holeTypes = holeTypesInReachOrder.sorted { ($0.instantiatedType.asSource, $0.builtType.asSource) < ($1.instantiatedType.asSource, $1.builtType.asSource) }
		// Each tier's labels, widest first: the widest tier's stems also name the enums and order the builders.
		let tierNames = Self.tierNames(
			of: holeTypes,
			parameters: parameters.map { (label: $0.property.label, access: $0.tierAccess) } + otherParameters,
			widestTier: seamTypeAccess,
		)
		let stemByHoleType = tierNames[0].stemByHoleType
		func label(of holeType: SeamSignature.HoleType, isSendable: Bool, in names: TierNames) -> String {
			let stem = names.stemByHoleType[holeType, default: ""]
			return isSendable ? Self.sendableBuilderLabel(ofStem: stem) : Self.plainBuilderLabel(ofStem: stem)
		}
		func label(of holeType: SeamSignature.HoleType, isSendable: Bool) -> String {
			label(of: holeType, isSendable: isSendable, in: tierNames[0])
		}
		/// The labels the narrower tiers take a builder under where they differ from the widest tier's.
		func narrowerTierLabels(of holeType: SeamSignature.HoleType, isSendable: Bool) -> [AccessLevel: String] {
			var labels = [AccessLevel: String]()
			let widestLabel = label(of: holeType, isSendable: isSendable)
			for names in tierNames.dropFirst() where label(of: holeType, isSendable: isSendable, in: names) != widestLabel {
				labels[names.tier] = label(of: holeType, isSendable: isSendable, in: names)
			}
			return labels
		}

		// The names the initializer's body declares for its builders, in a fixed order. Every other name of the tree is
		// claimed first: a builder function of a property the tree builds, and a deferred parameter's closure.
		let namesDeclaredBeforeTheBuilders = treeFunctionNames.union(parameters.filter(\.isDeferred).map(\.internalName))
		var names = GeneratedNameAllocator(reserving: namesDeclaredBeforeTheBuilders)
		// The own enums and their names, in builder order: per hole type in label order, then plain, `@Sendable`.
		let orderedHoleTypes = holeTypes.sorted { label(of: $0, isSendable: false) < label(of: $1, isSendable: false) }
		var ownEnums = [SeamSignature.ScopeEnum]()
		var callRoutes = [SeamSignature.CallRoute]()
		var valuesBindingKeysByStem = [String: Set<ValuesBindingKey>]()
		var builders = [SeamSignature.Builder]()
		var internalNameByFamily = [SeamSignature.ScopeEnum.Key: String]()
		for holeType in orderedHoleTypes {
			let stem = stemByHoleType[holeType, default: ""]
			let rootTypeNames = (plain: "\(scopeTypeNames.plain)_\(stem)".spelledAsIdentifier, sendable: "\(scopeTypeNames.sendable)_\(stem)".spelledAsIdentifier)
			// The enums, nested by type.
			var byType = ScopeEnumsByType()
			if let reached = reachedByHoleType[holeType] {
				byType = scopeEnumsByType(
					of: seam,
					holeType: holeType,
					rootTypeNames: rootTypeNames,
					builderLabels: (plain: label(of: holeType, isSendable: false), sendable: label(of: holeType, isSendable: true)),
					generator: generator,
					reached: reached,
					holesBySite: holesBySite,
					parameters: parameters,
					bindsReceivesAgain: bindsReceivesAgain,
					proof: proof,
					instantiables: instantiables,
					reachedEnum: reachedEnum,
				)
				valuesBindingKeysByStem[loweredLeadingCapitals(of: stem)] = byType.valuesBindingKeys
				callRoutes += byType.callRoutes
				for (site, enumPlace) in byType.enumPlaceBySite {
					holesBySite[site]?.enumPlace = enumPlace
					holesBySite[site]?.scopeTypeName = enumPlace.enumTypeName
				}
			}
			for isSendable in [false, true] {
				let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: isSendable)
				let typeName = isSendable ? rootTypeNames.sendable : rootTypeNames.plain
				let nestedEnums = byType.enums.filter { $0.key.isSendable == isSendable && $0.rootTypeName != nil }
				let cases = byType.rootEnum(isSendable: isSendable)?.cases ?? []
				// A root with no case of its own takes no builder, and is declared only where the `@Sendable` enum holds an enum
				// nested in it.
				guard !cases.isEmpty || !nestedEnums.isEmpty else { continue }
				ownEnums.append(SeamSignature.ScopeEnum(key: key, typeName: typeName, builderLabel: label(of: holeType, isSendable: isSendable), cases: cases))
				ownEnums += nestedEnums
				guard !cases.isEmpty else { continue }
				let builderLabel = label(of: holeType, isSendable: isSendable)
				let internalName = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: builderLabel))
				internalNameByFamily[key] = internalName
				// The builder is as visible as the narrowest place it builds, and each inner seam it carries an enum of, capped
				// at the seam.
				// The enums the builder reaches: its root, then the enums nested by type its cases lead to, in their order.
				var narrowest: (level: AccessLevel, cause: TypeAccessProof.Cause?, seam: TypeDescription?) = (seamTypeAccess, nil, nil)
				let rootEnum = SeamSignature.ScopeEnum(key: key, typeName: typeName, builderLabel: builderLabel, cases: cases)
				let nestedByTypeEnums = byType.enums.filter { $0.rootTypeName != nil }
				let reachedKeys = Self.enumKeysReached(from: key, in: Dictionary(([rootEnum] + nestedByTypeEnums).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }))
				for reachedEnum in [rootEnum] + nestedByTypeEnums where reachedKeys.contains(reachedEnum.key) {
					for enumCase in reachedEnum.cases {
						let sites: [SeamSignature.Hole.Site] = switch enumCase.kind {
						case let .place(sites):
							sites
						case .nested, .inner, .fill:
							[]
						}
						for site in sites {
							if let hole = holesBySite[site], hole.tierAccess < narrowest.level {
								narrowest = (hole.tierAccess, hole.accessCause, nil)
							}
						}
					}
				}
				for reachedKey in [key] + nestedByTypeEnums.map(\.key) where reachedKeys.contains(reachedKey) {
					for inner in innerAccessByEnum[reachedKey, default: []] where min(inner.level, seamTypeAccess) < narrowest.level {
						narrowest = (min(inner.level, seamTypeAccess), inner.cause, inner.seam)
					}
				}
				let enumType: TypeDescription = scopeTypeNames.areQualified ? .nested(name: typeName, parentType: seamType, generics: []) : .simple(name: typeName, generics: [])
				let parameterType = Self.builderParameterType(takingEnum: enumType, returning: returnType(of: holeType, in: flatHoles), isSendable: isSendable)
				builders.append(SeamSignature.Builder(
					enumKey: key,
					label: builderLabel,
					internalName: internalName,
					parameterType: parameterType,
					parameterTypeWithoutAny: parameterType.withoutAny,
					tierAccess: narrowest.level,
					accessCause: narrowest.cause,
					narrowingInnerSeam: narrowest.seam,
					narrowerTierLabels: narrowerTierLabels(of: holeType, isSendable: isSendable),
				))
			}
		}
		// Every place carries the names of the builder of its family, a fill's among them: a place in a `@Sendable` enum is
		// built by the `@Sendable` builder, which its fill is handed to, so the fill is `@Sendable`.
		for site in holesBySite.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
			guard let hole = holesBySite[site], hole.innerSeamType == nil else { continue }
			let isSendable = hole.enumPlace?.isBuiltBySendableBuilder ?? false
			let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: hole.holeType, isSendable: isSendable)
			holesBySite[site]?.builderLabel = label(of: hole.holeType, isSendable: isSendable)
			holesBySite[site]?.narrowerTierBuilderLabels = narrowerTierLabels(of: hole.holeType, isSendable: isSendable)
			holesBySite[site]?.internalName = internalNameByFamily[key] ?? ScopeGenerator.functionName(toBuildPropertyNamed: label(of: hole.holeType, isSendable: isSendable))
			if isSendable {
				holesBySite[site]?.isSendable = true
			}
		}
		// The functions that build the wrapper places come after the builders. Two places in separate scopes of the tree may
		// share a function name, since neither function is in scope where the other is declared; none may equal a builder,
		// which is in scope throughout the body.
		let namesOfBuilders = names.taken.subtracting(namesDeclaredBeforeTheBuilders)
		for site in holesBySite.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
			guard let hole = holesBySite[site], hole.innerSeamType == nil, !hole.property.propertyType.isConstant else { continue }
			var name = ScopeGenerator.functionName(toBuildPropertyNamed: hole.property.label)
			while namesOfBuilders.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			holesBySite[site]?.wrapperFunctionName = name
		}
		// The names the seam's tree binds the payloads of the cases that wrap others under, after every other name it binds
		// for its builders, and apart from the functions that build the wrapper places.
		let reservedForBindings = names.taken.union(holesBySite.values.compactMap(\.wrapperFunctionName))
		let valuesBindingNamesByStem = valuesBindingNames(of: valuesBindingKeysByStem, reservedNames: reservedForBindings)
		// The names the fills of a call whose fill leads to a place take the scope value the inner seam handed them under, one
		// per call and builder filled, whatever hole type it leads to, apart from every name above.
		var innerScopes = [SeamSignature.Hole.RouteStep.InnerScope]()
		for hole in holesBySite.values {
			innerScopes += hole.enumPlace?.route.compactMap(\.innerScope) ?? []
		}
		for callRoute in callRoutes {
			innerScopes += callRoute.route.compactMap(\.innerScope)
		}
		let innerScopeNames = Self.innerScopeNames(
			of: innerScopes,
			reservedNames: reservedForBindings.union(valuesBindingNamesByStem.values.flatMap(\.values)),
		)
		func namedRoute(_ route: [SeamSignature.Hole.RouteStep], ofHoleType holeType: SeamSignature.HoleType) -> [SeamSignature.Hole.RouteStep] {
			let nameByKey = valuesBindingNamesByStem[loweredLeadingCapitals(of: stemByHoleType[holeType, default: ""]), default: [:]]
			return route.map { step in
				step.named(
					step.values.flatMap { nameByKey[ValuesBindingKey(path: $0.bindingPath, caseName: step.caseName)] },
					innerScopeName: step.innerScope.flatMap { innerScopeNames[InnerScopeKey(callPath: $0.callPath, innerKey: $0.innerKey)] },
				)
			}
		}
		for site in holesBySite.keys {
			guard let hole = holesBySite[site], hole.innerSeamType == nil, let enumPlace = hole.enumPlace else { continue }
			holesBySite[site]?.enumPlace = SeamSignature.Hole.EnumPlace(
				nestedByTypeIn: enumPlace.enumTypeName,
				rootEnumTypeName: enumPlace.rootEnumTypeName,
				caseName: enumPlace.caseName,
				valuesTypeName: enumPlace.valuesTypeName,
				isBuiltBySendableBuilder: enumPlace.isBuiltBySendableBuilder,
				route: namedRoute(enumPlace.route, ofHoleType: hole.holeType),
				values: enumPlace.values,
			)
		}
		callRoutes = callRoutes.map { callRoute in
			SeamSignature.CallRoute(
				sitePath: callRoute.sitePath,
				innerKey: callRoute.innerKey,
				rootKey: callRoute.rootKey,
				route: namedRoute(callRoute.route, ofHoleType: callRoute.rootKey.holeType),
				caseName: callRoute.caseName,
			)
		}

		// This seam's enums first, then every enum their cases reach, each once, breadth first: only those, so a place that
		// a seam this one calls fills, which no builder of this one reaches, changes nothing a caller of this one passes. A
		// call's case for a builder it fills reaches the inner seam's enum whose value it carries, which a caller's reader of
		// the inner seam's levels walks.
		var seenKeys = Set(ownEnums.map(\.key))
		// A public mock's enums are generated by its module alone, and computed again by each module that calls the mock, so
		// each marks the cases of its own cycles of enums `indirect` here, as a module's seams are once they settle.
		var scopeEnums = scopeTypeNames.areQualified ? Self.markingIndirectCases(of: ownEnums, componentByKey: Self.componentByKey(of: ownEnums)) : ownEnums
		var nextEnumIndex = 0
		while nextEnumIndex < scopeEnums.count {
			for enumCase in scopeEnums[nextEnumIndex].cases {
				for innerKey in [SeamSignature.ScopeEnum.heldKey(of: enumCase), SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase)].compactMap(\.self) {
					guard seenKeys.insert(innerKey).inserted, let innerEnum = reachedEnum(innerKey) else { continue }
					scopeEnums.append(innerEnum)
				}
			}
			nextEnumIndex += 1
		}
		// The places in the order the builders reach them, with an explicit stack: cases can recurse.
		var orderedHoles = [SeamSignature.Hole]()
		var seenSites = Set<SeamSignature.Hole.Site>()
		let enumsByKey = Dictionary(scopeEnums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		var visitedEnums = Set<SeamSignature.ScopeEnum.Key>()
		var builderBySite = [SeamSignature.Hole.Site: SeamSignature.Builder]()
		for builder in builders {
			var keysToVisit = [builder.enumKey]
			while let key = keysToVisit.popLast() {
				guard visitedEnums.insert(key).inserted, let scopeEnum = enumsByKey[key] else { continue }
				var innerKeys = [SeamSignature.ScopeEnum.Key]()
				for enumCase in scopeEnum.cases {
					var sites = [SeamSignature.Hole.Site]()
					switch enumCase.kind {
					case let .place(placeSites):
						sites = placeSites
					case let .nested(innerKey, _, _),
					     let .inner(innerKey, _, _),
					     let .fill(_, _, innerKey, _, _):
						innerKeys.append(innerKey)
					}
					for site in sites where seenSites.insert(site).inserted {
						if let hole = holesBySite[site] {
							orderedHoles.append(hole)
							builderBySite[site] = builder
						}
					}
				}
				keysToVisit.append(contentsOf: innerKeys.reversed())
			}
		}
		return ShapedBuilders(holes: orderedHoles, builders: builders, scopeEnums: scopeEnums, builderBySite: builderBySite, callRoutes: callRoutes)
	}

	/// A call whose fill leads to a place, and the builder filled: what one inner scope's name is per.
	private struct InnerScopeKey: Hashable {
		let callPath: [Property]
		let innerKey: SeamSignature.ScopeEnum.Key
	}

	/// The names the fills of each call and builder in `innerScopes` take the scope value the inner seam handed them under:
	/// `__safeDI_<call>_<builder>`, with `_` appended while a name in
	/// `reservedNames`, or one of a call on the way to this one, has it. Calls are named shortest path first, then in the
	/// order of their spelling, so no name depends on the order the routes are met in.
	private static func innerScopeNames(of innerScopes: [SeamSignature.Hole.RouteStep.InnerScope], reservedNames: Set<String>) -> [InnerScopeKey: String] {
		var builderLabelByKey = [InnerScopeKey: String]()
		for innerScope in innerScopes {
			let key = InnerScopeKey(callPath: innerScope.callPath, innerKey: innerScope.innerKey)
			builderLabelByKey[key] = innerScope.builderLabel
		}
		func sortKey(of key: InnerScopeKey) -> String {
			key.callPath.map(\.asSource).joined(separator: " ") + " " + key.innerKey.spelling
		}
		let orderedKeys = builderLabelByKey.keys.sorted { first, second in
			first.callPath.count != second.callPath.count ? first.callPath.count < second.callPath.count : sortKey(of: first) < sortKey(of: second)
		}
		var namesByCallPath = [[Property]: Set<String>]()
		var nameByKey = [InnerScopeKey: String]()
		for key in orderedKeys {
			guard let callProperty = key.callPath.last else { continue }
			var taken = reservedNames
			for length in 1...key.callPath.count {
				taken.formUnion(namesByCallPath[Array(key.callPath.prefix(length)), default: []])
			}
			var name = ScopeGenerator.functionName(toBuildPropertyNamed: "\(callProperty.label.spelledWithoutBackticks)_\(builderLabelByKey[key, default: ""])".spelledAsIdentifier)
			while taken.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			nameByKey[key] = name
			namesByCallPath[key.callPath, default: []].insert(name)
		}
		return nameByKey
	}

	/// The keys of the enums the enum of `key` reaches among `enumsByKey`, itself included.
	private static func enumKeysReached(from key: SeamSignature.ScopeEnum.Key, in enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]) -> Set<SeamSignature.ScopeEnum.Key> {
		var visited = Set<SeamSignature.ScopeEnum.Key>()
		var keysToVisit = [key]
		while let visitedKey = keysToVisit.popLast() {
			guard visited.insert(visitedKey).inserted else { continue }
			for enumCase in enumsByKey[visitedKey]?.cases ?? [] {
				if let heldKey = SeamSignature.ScopeEnum.heldKey(of: enumCase), enumsByKey[heldKey] != nil {
					keysToVisit.append(heldKey)
				}
			}
		}
		return visited
	}

	/// The type of a builder over an enum.
	private static func builderParameterType(takingEnum enumType: TypeDescription, returning builtType: TypeDescription, isSendable: Bool) -> TypeDescription {
		let functionType = TypeDescription.closure(arguments: [enumType], isAsync: false, doesThrow: false, returnType: builtType)
		return (isSendable ? functionType.asSendableFunction : functionType).asFunctionParameter
	}

	/// The type the builder of `holeType` returns, as a place of the type spells it: the first in `holes`, which `holes(of:)`
	/// lists in a fixed order, so a caller's spelling never depends on anything else.
	private static func returnType(of holeType: SeamSignature.HoleType, in holes: [SeamSignature.Hole]) -> TypeDescription {
		holes.first { $0.holeType == holeType }?.builtType ?? holeType.builtType
	}

	/// What one tier names its builders by.
	struct TierNames {
		let tier: AccessLevel
		/// The labels of the parameters the tier takes: its own and every wider tier's.
		let parameterLabels: Set<String>
		let stemByHoleType: [SeamSignature.HoleType: String]
	}

	/// The names of each tier that `parameters`, each with the access of the narrowest tier that takes it, give `holeTypes`,
	/// widest first: `widestTier`, then each narrower access among `parameters`, each tier's stems computed from the labels
	/// it takes alone, so they never depend on the order the parameters are declared in.
	private static func tierNames(
		of holeTypes: [SeamSignature.HoleType],
		parameters: [(label: String, access: AccessLevel)],
		widestTier: AccessLevel,
	) -> [TierNames] {
		let tiers = [widestTier] + Set(parameters.map(\.access)).filter { $0 < widestTier }.sorted(by: >)
		return tiers.map { tier in
			let parameterLabels = Set(parameters.filter { $0.access >= tier }.map(\.label))
			return TierNames(tier: tier, parameterLabels: parameterLabels, stemByHoleType: stems(of: holeTypes, parameterLabels: parameterLabels))
		}
	}

	/// The stem each of `holeTypes` is named by: its instantiated type as an identifier, unless it collides with another's or a
	/// label equals a parameter's, when it takes the returned type's stem after it. What still collides is named apart by its
	/// types; no rung names an owner or a path, so adding a place never renames a hole type.
	private static func stems(of holeTypes: [SeamSignature.HoleType], parameterLabels: Set<String>) -> [SeamSignature.HoleType: String] {
		func stem(of type: TypeDescription) -> String {
			type.simplified.asIdentifier.spelledWithoutBackticks
		}
		func labels(of stem: String) -> Set<String> {
			[plainBuilderLabel(ofStem: stem), sendableBuilderLabel(ofStem: stem)]
		}
		let firstStems = holeTypes.map { stem(of: $0.instantiatedType) }
		func collides(_ index: Int, among stems: [String]) -> Bool {
			!labels(of: stems[index]).isDisjoint(with: parameterLabels)
				|| stems.indices.contains { other in
					other != index && (stems[other] == stems[index] || !labels(of: stems[other]).isDisjoint(with: labels(of: stems[index])))
				}
		}
		var stems = holeTypes.indices.map { index in
			collides(index, among: firstStems) ? "\(firstStems[index])_\(stem(of: holeTypes[index].builtType))" : firstStems[index]
		}
		let stillColliding = holeTypes.indices.filter { collides($0, among: stems) }
		if !stillColliding.isEmpty {
			let renamed = ScopeGenerator.identifierSafeNames(
				for: stillColliding.map { (label: stems[$0], suffixTypes: [holeTypes[$0].instantiatedType, holeTypes[$0].builtType]) },
				reservedNames: Set(holeTypes.indices.filter { !stillColliding.contains($0) }.map { stems[$0] }),
			)
			for (index, name) in zip(stillColliding, renamed) {
				stems[index] = name.spelledWithoutBackticks
			}
			// Two stems may still give one label: each that does takes a trailing underscore until none does.
			for index in stems.indices {
				while collides(index, among: stems) {
					stems[index] += "_"
				}
			}
		}
		return Dictionary(zip(holeTypes, stems), uniquingKeysWith: { first, _ in first })
	}

	/// The stem with its leading capitals lowered, keeping the last when a lowercase letter follows it, then `Builder`.
	static func plainBuilderLabel(ofStem stem: String) -> String {
		"\(loweredLeadingCapitals(of: stem))Builder".spelledAsIdentifier
	}

	static func sendableBuilderLabel(ofStem stem: String) -> String {
		"\(loweredLeadingCapitals(of: stem))SendableBuilder".spelledAsIdentifier
	}

	private static func loweredLeadingCapitals(of stem: String) -> String {
		let characters = Array(stem)
		var capitalCount = 0
		while capitalCount < characters.count, characters[capitalCount].isUppercase {
			capitalCount += 1
		}
		guard capitalCount > 0 else { return stem }
		let lowerCount = capitalCount < characters.count && characters[capitalCount].isLowercase ? max(capitalCount - 1, 1) : capitalCount
		return String(characters[..<lowerCount]).lowercased() + String(characters[lowerCount...])
	}

	/// The identifier a seam is named by inside a fill's or a dispatcher's name.
	static func seamStem(of seamType: TypeDescription) -> String {
		seamType.spelledCanonically.simplified.asIdentifier.spelledWithoutBackticks
	}

	// MARK: Private

	private enum PlaceOrCall {
		/// A place, with the cases on its path (see `ReachedPlace.steps`).
		case place(sitePath: [Property], steps: [ReachedStep])
		/// A call that passes a builder up, with the cases on its path, and whether any `@Sendable` function, a fill's
		/// included, encloses it.
		case call(sitePath: [Property], generator: ScopeGenerator, steps: [ReachedStep], isInSendableFunction: Bool)
	}

	/// Every place and every call that passes a builder up in the tree `generator` roots, in the order the generated code
	/// reaches them: a seam call's fills are declared before the call. A fill's `@Sendable` function counts as one on the
	/// call's step, whose case for the builder filled leads to what the fill builds.
	private static func placesAndCalls(in generator: ScopeGenerator) -> [PlaceOrCall] {
		struct Frame {
			let generator: ScopeGenerator
			let orderedChildren: [ScopeGenerator.OrderedChild]
			var nextPosition: Int
			let path: [Property]
			/// The cases on the path to this scope's children (see `ReachedPlace.steps`).
			let steps: [ReachedStep]
			/// Whether a `@Sendable` function, a fill's included, encloses this scope's children.
			let isInSendableFunction: Bool
			/// The type that declares this scope's children, or `nil` for a call and a fill, whose children no case stands for.
			let type: TypeDescription?
		}
		var reached = [PlaceOrCall]()
		var frames = [Frame(
			generator: generator,
			orderedChildren: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []),
			nextPosition: 0,
			path: [],
			steps: [],
			isInSendableFunction: false,
			type: generator.builtInstantiable?.concreteInstantiable,
		)]
		while let frame = frames.last {
			guard frame.nextPosition < frame.orderedChildren.count else {
				frames.removeLast()
				if !frame.generator.passedUpHoles.isEmpty {
					reached.append(.call(sitePath: frame.path, generator: frame.generator, steps: frame.steps, isInSendableFunction: frame.isInSendableFunction))
				}
				continue
			}
			frames[frames.count - 1].nextPosition += 1
			let child = frame.orderedChildren[frame.nextPosition]
			if let holeSite = child.generator.holeSite {
				guard let type = frame.type else { continue }
				let isSendableWrapper = holeSite.property.propertyType.isSendable
				let sitePath = frame.path + [holeSite.property]
				reached.append(.place(
					sitePath: sitePath,
					steps: frame.steps + [ReachedStep(type: type, property: holeSite.property, pathLength: sitePath.count, buildsInSendableFunction: isSendableWrapper, filledBuilder: nil)],
				))
			} else if child.generator.containsBuildSite || child.generator.passesUpBuilder, child.generator.fillEmitsCode {
				if child.generator.fillHole != nil {
					// A fill of the call this frame is: the call's step becomes its case for the builder filled, on which the fill's
					// `@Sendable` function counts. The filled place's path in the inner seam's tree has no case of this seam's.
					guard let callStep = frame.steps.last, let innerKey = filledRootKey(of: child.generator) else { continue }
					// A place inside a fill that builds its type in a `@Sendable` builder function of the type's own carries no inner
					// scope, a value bound outside that function.
					let fulfillerBuildsInSendableFunction = child.generator.children.first?.buildsInSendableFunction ?? false
					let fillIsSendable = frame.generator.buildsInSendableFunction(ofFill: child.generator)
					frames.append(Frame(
						generator: child.generator,
						orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
						nextPosition: 0,
						path: frame.path + (child.generator.fillHole?.pathBeforePropertyInItsFill ?? []),
						steps: frame.steps.dropLast() + [ReachedStep(
							type: callStep.type,
							property: callStep.property,
							pathLength: callStep.pathLength,
							buildsInSendableFunction: callStep.buildsInSendableFunction || fillIsSendable,
							filledBuilder: SeamDeclarationGraph.FilledBuilder(innerKey: innerKey, carriesInnerScope: !fulfillerBuildsInSendableFunction),
						)],
						isInSendableFunction: frame.isInSendableFunction || fillIsSendable,
						type: nil,
					))
				} else if frame.generator.fillHole != nil {
					// What a fill builds: the type the call's case for the builder filled holds the enum of. Its builder function, a
					// `Sendable` wrapper's, counts on the call's step too.
					var steps = frame.steps
					if child.generator.buildsInSendableFunction, let callStep = steps.popLast() {
						steps.append(ReachedStep(type: callStep.type, property: callStep.property, pathLength: callStep.pathLength, buildsInSendableFunction: true, filledBuilder: callStep.filledBuilder))
					}
					frames.append(Frame(
						generator: child.generator,
						orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
						nextPosition: 0,
						path: frame.path + (child.generator.property.map { [$0] } ?? []),
						steps: steps,
						isInSendableFunction: frame.isInSendableFunction || child.generator.buildsInSendableFunction,
						type: child.generator.builtInstantiable?.concreteInstantiable,
					))
				} else if let type = frame.type, let property = child.generator.property {
					let path = frame.path + [property]
					frames.append(Frame(
						generator: child.generator,
						orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
						nextPosition: 0,
						path: path,
						steps: frame.steps + [ReachedStep(type: type, property: property, pathLength: path.count, buildsInSendableFunction: child.generator.buildsInSendableFunction, filledBuilder: nil)],
						isInSendableFunction: frame.isInSendableFunction || child.generator.buildsInSendableFunction,
						// A call's children are its fills, which no case of its own stands for.
						type: child.generator.calledBuilders == nil ? child.generator.builtInstantiable?.concreteInstantiable : nil,
					))
				}
			}
		}
		return reached
	}

	/// Marks each case of `seamRoots`' enums that holds an enum of its own strongly connected component `indirect`. Every
	/// enum of a cycle is generated by one module, whose seams are the ones computed here, and membership is a set property,
	/// so no name order reaches the output.
	static func markingIndirectCases(in seamRoots: [ScopeGenerator.SeamRoot?]) -> [ScopeGenerator.SeamRoot?] {
		var ownEnums = [SeamSignature.ScopeEnum]()
		for seamRoot in seamRoots.compactMap(\.self) {
			ownEnums += seamRoot.signature.scopeEnums.filter { $0.key.seamType == seamRoot.signature.seamType }
		}
		let componentByKey = componentByKey(of: ownEnums)
		return seamRoots.map { seamRoot in
			guard let seamRoot else { return nil }
			// The enums are marked in a copy, assigned once, since each assignment computes the signature's call shape again.
			var signature = seamRoot.signature
			signature.scopeEnums = markingIndirectCases(of: seamRoot.signature.scopeEnums, componentByKey: componentByKey)
			return ScopeGenerator.SeamRoot(signature: signature, unreadTypeComment: seamRoot.unreadTypeComment)
		}
	}

	/// The strongly connected component of each of `ownEnums` among them, by key: an index shared by the enums of one
	/// component. The components are found in the order of the keys' spellings.
	static func componentByKey(of ownEnums: [SeamSignature.ScopeEnum]) -> [SeamSignature.ScopeEnum.Key: Int] {
		var edges = [SeamSignature.ScopeEnum.Key: [SeamSignature.ScopeEnum.Key]]()
		for scopeEnum in ownEnums {
			edges[scopeEnum.key] = scopeEnum.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:))
		}
		let nodes = edges.keys.sorted { $0.spelling < $1.spelling }
		var componentByKey = [SeamSignature.ScopeEnum.Key: Int]()
		for (index, component) in stronglyConnectedComponents(of: nodes, edges: { edges[$0, default: []].filter { edges[$0] != nil } }).enumerated() {
			for key in component {
				componentByKey[key] = index
			}
		}
		return componentByKey
	}

	/// `scopeEnums`, with each case that holds an enum of its own enum's component in `componentByKey` marked `indirect`.
	static func markingIndirectCases(of scopeEnums: [SeamSignature.ScopeEnum], componentByKey: [SeamSignature.ScopeEnum.Key: Int]) -> [SeamSignature.ScopeEnum] {
		var scopeEnums = scopeEnums
		for enumIndex in scopeEnums.indices {
			guard let component = componentByKey[scopeEnums[enumIndex].key] else { continue }
			for caseIndex in scopeEnums[enumIndex].cases.indices {
				if case let .nested(innerKey, enumType, _) = scopeEnums[enumIndex].cases[caseIndex].kind, componentByKey[innerKey] == component {
					scopeEnums[enumIndex].cases[caseIndex].kind = .nested(enumKey: innerKey, enumType: enumType, isIndirect: true)
				} else if case let .inner(innerKey, enumType, _) = scopeEnums[enumIndex].cases[caseIndex].kind, componentByKey[innerKey] == component {
					scopeEnums[enumIndex].cases[caseIndex].kind = .inner(enumKey: innerKey, enumType: enumType, isIndirect: true)
				} else if case let .fill(innerKey, innerEnumType, heldKey, heldEnumType, _) = scopeEnums[enumIndex].cases[caseIndex].kind, componentByKey[heldKey] == component {
					scopeEnums[enumIndex].cases[caseIndex].kind = .fill(innerKey: innerKey, innerEnumType: innerEnumType, enumKey: heldKey, enumType: heldEnumType, isIndirect: true)
				}
			}
		}
		return scopeEnums
	}
}

extension SeamSignature.Hole.Site {
	/// A spelling that orders sites.
	var sortKey: String {
		"\(seamType.asSource) \(path.map(\.asSource).joined(separator: " "))"
	}
}
