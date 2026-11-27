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
/// overrides into; a closure nested in it claims from a copy holding the names it can see, as a builder struct
/// conversion's members do – and each name is claimed in a fixed order, so two namers can never hand one name out: a seam's body
/// claims its builders' internal names, then the functions that build its wrapper places, then the payloads it binds; a
/// filler's body claims its fills, then its dispatchers; a mock's scope claims each function's locals in the order the
/// mock's body walk reads the overrides (`ScopeGenerator.SendableOverrideExtractor`).
struct GeneratedNameAllocator: Sendable {
	init(reserving names: Set<String>) {
		taken = names
		consulted = NamesConsultedInTurn([])
	}

	/// An allocator that asks `names` in turn, never copying them, beside what it takes.
	init(reserving names: NamesConsultedInTurn) {
		taken = []
		consulted = names
	}

	/// Claims `base`, with `_` appended while it or any name `occupied` gives for it is taken, and returns what it claimed.
	mutating func claim(_ base: String, occupying occupied: (String) -> [String] = { [$0] }) -> String {
		var name = base
		while occupied(name).contains(where: { taken.contains($0) || consulted.contains($0) }) {
			name = "\(name)_".spelledAsJoinedIdentifier
		}
		taken.formUnion(occupied(name))
		return name
	}

	/// Takes `names` without claiming them: names a scope declares by rules of their own, which nothing claimed later may share.
	mutating func reserve(_ names: some Sequence<String>) {
		taken.formUnion(names)
	}

	/// The names taken: those reserved as a set, those reserved later, and those claimed; never the names `consulted` holds.
	private(set) var taken: Set<String>
	/// The names reserved without being copied, asked in turn.
	private let consulted: NamesConsultedInTurn
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
		/// Each of `holes`, in its order, with the builder `builderBySite` gives its site: the first builder whose enum
		/// reaches the place.
		var holesWithBuilders = [(hole: SeamSignature.Hole, builder: SeamSignature.Builder)]()
		/// How the seam's tree hands each inner seam's enum up from a call whose case is nested by type.
		var callRoutes = [SeamSignature.CallRoute]()
		/// The member call each step of the route of each of the seam's own sites makes, in the route's order
		/// (`SeamSignature.Hole.RouteStep.Member`).
		var routeMembersBySite = [SeamSignature.Hole.Site: [SeamSignature.Hole.RouteStep.Member?]]()
	}

	/// What the scope types a seam or a public mock declares for its builders are named by, and how its builders spell them.
	struct ScopeTypeNames {
		/// The prefix of a plain enum's name, which the stem follows.
		let plain: String
		/// The prefix of a `@Sendable` enum's name, which the stem follows.
		let sendable: String
		/// Whether a builder spells its own scope types qualified by the type that declares them: a public mock's builder
		/// is spelled once for its own signature and for each module that calls it, as an internal mock's parameter.
		let areQualified: Bool

		/// A seam's: `SafeDIScope_` and `SafeDISendableScope_`, spelled inside its extension. `ReservedName` spells the prefixes,
		/// which a type a person names is rejected for beginning with.
		static let seam = ScopeTypeNames(plain: ReservedName.seamScopeTypeNamePrefix, sendable: ReservedName.sendableSeamScopeTypeNamePrefix, areQualified: false)
		/// A public mock's: `SafeDIMockScope_` and `SafeDISendableMockScope_`, apart from the seam's a mocked seam declares beside
		/// them.
		/// A seam's whose levels are carriers (`ReservedName.seamCarrier(ofEnum:)`): `SafeDICarrierScope_` and
		/// `SafeDISendableCarrierScope_`, names no generated code spells.
		static let seamCarriers = ScopeTypeNames(plain: ReservedName.seamCarrierScopeTypeNamePrefix, sendable: ReservedName.sendableSeamCarrierScopeTypeNamePrefix, areQualified: false)
		/// Whether these are a seam's names, never a public mock's.
		var isSeams: Bool {
			plain == ReservedName.seamScopeTypeNamePrefix
		}

		static let publicMock = ScopeTypeNames(plain: ReservedName.publicMockScopeTypeNamePrefix, sendable: ReservedName.sendablePublicMockScopeTypeNamePrefix, areQualified: true)
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
	/// A builder's label depends only on what it builds: its hole type's stem (`stems(of:)`), which also names the enums,
	/// one per hole type and family whatever tier takes them. Each tier appends `_` to a label that equals a parameter
	/// it takes, its own or a wider tier's, so a parameter only a narrower tier takes never relabels a wider tier's builder.
	/// - Parameters:
	///   - otherParameters: The labels of a public mock's parameters, each with the access of the narrowest tier that takes
	///     it, which its builders follow and are named apart from as a seam's builders are from its parameters.
	///   - bindsReceivesAgain: Whether the tree is a public mock's, whose levels hold the receives it binds again (see
	///     `mockBindsAgain(receiving:beneath:)`).
	///   - namesApartAtRoot: For a public mock, what its root binds only under names apart, which no level declares.
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
		namesApartAtRoot: PublicMockRootLevel.NamesApart = .init(),
	) -> ShapedBuilders {
		guard !flatHoles.isEmpty else { return ShapedBuilders(holes: [], builders: [], scopeEnums: [], builderBySite: [:]) }
		let seamType = seam.concreteInstantiable
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		var holesBySite = Dictionary(flatHoles.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
		// Each site's key is spelled once: spelled inside a comparison, a path was spelled again for every pair compared.
		let sortKeyBySite = holesBySite.mapValues(\.site.sortKey)

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
		// called mock's signature, reads them from each call whose tree leads to a place, or holds a call that re-enters an
		// enclosing call's fill or level function, whose case on the type that makes it holds the re-entering call's enum.
		var generatorsToVisit = [generator]
		while let visited = generatorsToVisit.popLast() {
			for child in visited.children where child.containsBuildSite || child.passesUpBuilder || child.holdsCallReenteringEnclosingFill {
				for scopeEnum in child.calledBuilders?.scopeEnums ?? [] where calledSeamsEnums[scopeEnum.key] == nil {
					calledSeamsEnums[scopeEnum.key] = scopeEnum
				}
				generatorsToVisit.append(child)
			}
		}
		// The places and calls of a seam's or a public mock's tree, by hole type, whose enums are nested by type
		// (`scopeEnumsByType`), a place inside a fill included.
		var reachedByHoleType = [SeamSignature.HoleType: [ReachedPlace]]()
		var reenteringCalls = [ReachedPlace]()
		// The fills a call inside a fill of the same call can re-enter, found once for the tree.
		let reenteredFillsByKey = emittingFillsByKey(inTreeRootedAt: generator)
		for reached in placesAndCalls(in: generator, reenteredFillsByKey: reenteredFillsByKey) {
			switch reached {
			case let .reenteringCall(sitePath, steps):
				reenteringCalls.append(ReachedPlace(sitePath: sitePath, steps: steps, call: nil, reentersEnclosingFill: true))
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

		// A call that re-enters an enclosing call's fill has a route in each hole type whose enums have its case.
		for holeType in reachedByHoleType.keys {
			reachedByHoleType[holeType, default: []] += reenteringCalls
		}

		// The stem of each hole type, from what it builds alone, named apart only from another hole type's.
		let holeTypes = holeTypesInReachOrder.sorted { ($0.instantiatedType.asSource, $0.builtType.asSource) < ($1.instantiatedType.asSource, $1.builtType.asSource) }
		// Each tier's labels, widest first: the widest tier's also order the builders and name what is derived from a label.
		let tierNames = Self.tierNames(
			of: holeTypes,
			parameters: parameters.map { (label: $0.property.label, access: $0.tierAccess) } + otherParameters,
			widestTier: seamTypeAccess,
		)
		let stemByHoleType = tierNames.stemByHoleType
		// Each tier's two labels of each hole type, spelled once: spelled at each use, a label was spelled again for every
		// comparison of the sort below and for every place, case and route that names it.
		var labelsByTier = [AccessLevel: [SeamSignature.HoleType: (plain: String, sendable: String)]]()
		func label(of holeType: SeamSignature.HoleType, isSendable: Bool, in names: TierNames) -> String {
			let labels: (plain: String, sendable: String)
			if let spelledLabels = labelsByTier[names.tier]?[holeType] {
				labels = spelledLabels
			} else {
				let stem = stemByHoleType[holeType, default: ""]
				labels = (plain: names.label(ofStem: stem, isSendable: false), sendable: names.label(ofStem: stem, isSendable: true))
				labelsByTier[names.tier, default: [:]][holeType] = labels
			}
			return isSendable ? labels.sendable : labels.plain
		}
		func label(of holeType: SeamSignature.HoleType, isSendable: Bool) -> String {
			label(of: holeType, isSendable: isSendable, in: tierNames.tiers[0])
		}
		/// The labels the narrower tiers take a builder under where they differ from the widest tier's.
		func narrowerTierLabels(of holeType: SeamSignature.HoleType, isSendable: Bool) -> [AccessLevel: String] {
			var labels = [AccessLevel: String]()
			let widestLabel = label(of: holeType, isSendable: isSendable)
			for names in tierNames.tiers.dropFirst() where label(of: holeType, isSendable: isSendable, in: names) != widestLabel {
				labels[names.tier] = label(of: holeType, isSendable: isSendable, in: names)
			}
			return labels
		}

		// The names the initializer's body declares for its builders, in a fixed order. Every other name of the tree is
		// claimed first: a builder function of a property the tree builds, and a deferred parameter's closure.
		let namesDeclaredBeforeTheBuilders = treeFunctionNames.union(parameters.filter(\.isDeferred).map(\.internalName))
		// The allocator copies them, once for the seam's builders.
		var names = GeneratedNameAllocator(reserving: GenerationWork.taking(namesDeclaredBeforeTheBuilders, by: .namingSeamBuilders))
		// The own enums and their names, in builder order: per hole type in label order, then plain, `@Sendable`.
		let orderedHoleTypes = holeTypes.sorted { label(of: $0, isSendable: false) < label(of: $1, isSendable: false) }
		var ownEnums = [SeamSignature.ScopeEnum]()
		var callRoutes = [SeamSignature.CallRoute]()
		var routeMembersBySite = [SeamSignature.Hole.Site: [SeamSignature.Hole.RouteStep.Member?]]()
		var memberBindingKeysByLabel = [String: Set<ValuesBindingKey>]()
		var builders = [SeamSignature.Builder]()
		var internalNameByFamily = [SeamSignature.ScopeEnum.Key: String]()
		var levels = LevelsOfEveryHoleType(
			generator: generator,
			holes: flatHoles,
			parameters: parameters,
			bindsReceivesAgain: bindsReceivesAgain,
			namesApartAtRoot: namesApartAtRoot,
		)
		// Each hole type's built type, found in one pass over the places: found per hole type, every place was read once per type.
		let builtTypeByHoleType = flatHoles.builtTypeByHoleType
		for holeType in orderedHoleTypes {
			let stem = stemByHoleType[holeType, default: ""]
			// A hole type whose routes lead through a fill keeps its builder structs until carriers for places inside fills exist.
			let leadsThroughFill = reachedByHoleType[holeType, default: []].contains { $0.steps.contains { $0.filledBuilder != nil } }
			let typeNames = scopeTypeNames.isSeams && !leadsThroughFill && reenteringCalls.isEmpty ? ScopeTypeNames.seamCarriers : scopeTypeNames
			let rootTypeNames = (plain: "\(typeNames.plain)\(stem)".spelledAsIdentifier, sendable: "\(typeNames.sendable)\(stem)".spelledAsIdentifier)
			let builtType = builtTypeByHoleType[holeType, default: holeType.builtType]
			// The enums, nested by type.
			var byType = ScopeEnumsByType()
			if let reached = reachedByHoleType[holeType] {
				byType = scopeEnumsByType(
					of: seam,
					holeType: holeType,
					builderBuiltType: builtType,
					rootTypeNames: rootTypeNames,
					builderLabels: (plain: label(of: holeType, isSendable: false), sendable: label(of: holeType, isSendable: true)),
					generator: generator,
					reached: reached,
					parameters: parameters,
					bindsReceivesAgain: bindsReceivesAgain,
					reenteredFillsByKey: reenteredFillsByKey,
					proof: proof,
					instantiables: instantiables,
					reachedEnum: reachedEnum,
					levels: &levels,
				)
				// Every hole type of a seam and of a public mock takes a builder struct, whatever places it reaches: the seam's tree
				// calls a member per level, bound under names of their own, and binds no payload. A seam's own internal mock takes
				// builders of its own (`ScopeGenerator.seamMockBuilders`), whatever this gives the seam's builder.
				for isSendable in [false, true] {
					memberBindingKeysByLabel[label(of: holeType, isSendable: isSendable), default: []].formUnion(byType.memberBindingKeysByFamily[isSendable, default: []])
				}
				callRoutes += byType.callRoutes
				// A site is one hole type's, so no two types name it; as its enum place below, a site's members are the last given.
				for (site, members) in byType.routeMembersBySite {
					routeMembersBySite[site] = members
				}
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
				// The places the builder reaches, which decide the type of the builder a person writes.
				var reachedPlaces = [SeamSignature.Hole]()
				for reachedEnum in [rootEnum] + nestedByTypeEnums where reachedKeys.contains(reachedEnum.key) {
					for enumCase in reachedEnum.cases {
						let sites: [SeamSignature.Hole.Site] = switch enumCase.kind {
						case let .place(sites):
							sites
						case .nested, .inner, .fill:
							[]
						}
						for site in sites {
							guard let hole = holesBySite[site] else { continue }
							reachedPlaces.append(hole)
							if hole.tierAccess < narrowest.level {
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
				// The type of the builder a person writes is the one every place the builder reaches takes, its own and those it
				// hands up from the seams it calls, as the struct's no-scope initializer is handed it.
				var enumsReachedByKey = calledSeamsEnums
				for reachedEnum in [rootEnum] + nestedByTypeEnums {
					enumsReachedByKey[reachedEnum.key] = reachedEnum
				}
				let placesOfReadableType = SeamSignature.ScopeEnum.sitesReached(from: key, in: enumsReachedByKey)
					.compactMap { site in sortKeyBySite[site].map { (site: site, sortKey: $0) } }
					.sorted { $0.sortKey < $1.sortKey }
					.compactMap { holesBySite[$0.site] }
				let parameterType = ReservedName.levelType(ofEnum: enumType, built: builtType)
				builders.append(SeamSignature.Builder(
					enumKey: key,
					label: builderLabel,
					internalName: internalName,
					parameterType: parameterType,
					readableParameterType: Self.readableBuilderType(of: Self.builderForm(ofPlaces: placesOfReadableType), returning: builtType, isSendable: isSendable),
					takesBuilderStruct: true,
					tierAccess: narrowest.level,
					accessCause: narrowest.cause,
					narrowingInnerSeam: narrowest.seam,
					narrowerTierLabels: narrowerTierLabels(of: holeType, isSendable: isSendable),
				))
			}
		}
		// Every place carries the names of the builder of its family, a fill's among them: a place in a `@Sendable` enum is
		// built by the `@Sendable` builder, which its fill is handed to, so the fill is `@Sendable`.
		let sitesInOrder = sortKeyBySite.map { (site: $0.key, sortKey: $0.value) }.sorted { $0.sortKey < $1.sortKey }.map(\.site)
		for site in sitesInOrder {
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
		for site in sitesInOrder {
			guard let hole = holesBySite[site], hole.innerSeamType == nil, !hole.property.propertyType.isConstant else { continue }
			var name = ScopeGenerator.functionName(toBuildPropertyNamed: hole.property.label)
			while namesOfBuilders.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			holesBySite[site]?.wrapperFunctionName = name
		}
		// The names the seam's tree binds the structs its member calls return under, after every other name it binds for its
		// builders, and apart from the functions that build the wrapper places.
		let reservedForBindings = names.taken.union(holesBySite.values.compactMap(\.wrapperFunctionName))
		// The names the fills of a call whose fill leads to a place take the scope value the inner seam handed them under, one
		// per call and builder filled, whatever hole type it leads to, apart from every name above; for a seam's builder struct,
		// one per type of the struct of the fill's own level, each after the label of the builder whose route leads there.
		var innerScopes = [(innerScope: SeamSignature.Hole.RouteStep.InnerScope, callPath: [Property], rootBuilderLabel: String)]()
		for hole in holesBySite.values {
			guard let enumPlace = hole.enumPlace else { continue }
			let rootBuilderLabel = label(of: hole.holeType, isSendable: enumPlace.isBuiltBySendableBuilder)
			innerScopes += enumPlace.route.compactMap(\.innerScope).map { ($0, $0.callPath(onRouteTo: hole.sitePath), rootBuilderLabel) }
		}
		for callRoute in callRoutes {
			let rootBuilderLabel = label(of: callRoute.rootKey.holeType, isSendable: callRoute.rootKey.isSendable)
			innerScopes += callRoute.route.compactMap(\.innerScope).map { ($0, $0.callPath(onRouteTo: callRoute.sitePath), rootBuilderLabel) }
		}
		// One per path and case: `__safeDI_<builder>_<case>`, after the label of the builder whose root enum the route starts at.
		let memberBindingNamesByLabel = memberBindingNames(of: memberBindingKeysByLabel, reservedNames: reservedForBindings)
		let innerScopeNames = Self.innerScopeNames(of: innerScopes, reservedNames: reservedForBindings)
		func namedRoute(_ route: [SeamSignature.Hole.RouteStep], to sitePath: [Property]) -> [SeamSignature.Hole.RouteStep] {
			route.map { step in
				step.named(
					nil,
					innerScopeName: step.innerScope.flatMap { innerScopeNames[InnerScopeKey(callPath: $0.callPath(onRouteTo: sitePath), innerKey: $0.innerKey, enumType: $0.enumType)] },
				)
			}
		}
		// Each step's member call bound under its name, and no member call for a step whose call has no name.
		func namedMembers(_ members: [SeamSignature.Hole.RouteStep.Member?], of route: [SeamSignature.Hole.RouteStep], to sitePath: [Property], ofHoleType holeType: SeamSignature.HoleType, isSendable: Bool) -> [SeamSignature.Hole.RouteStep.Member?] {
			let memberNameByKey = memberBindingNamesByLabel[label(of: holeType, isSendable: isSendable), default: [:]]
			return zip(members, route).map { member, step in
				member.flatMap { member in
					memberNameByKey[ValuesBindingKey(path: member.bindingPath(onRouteTo: sitePath), caseName: step.caseName)].map { member.named($0) }
				}
			}
		}
		for site in holesBySite.keys {
			guard let hole = holesBySite[site], hole.innerSeamType == nil, let enumPlace = hole.enumPlace else { continue }
			holesBySite[site]?.enumPlace = SeamSignature.Hole.EnumPlace(
				nestedByTypeIn: enumPlace.enumTypeName,
				rootEnumTypeName: enumPlace.rootEnumTypeName,
				caseName: enumPlace.caseName,
				valuesTypeName: enumPlace.valuesTypeName,
				memberValuesTypeName: enumPlace.memberValuesTypeName,
				isBuiltBySendableBuilder: enumPlace.isBuiltBySendableBuilder,
				route: namedRoute(enumPlace.route, to: hole.sitePath),
				values: enumPlace.values,
			)
			routeMembersBySite[site] = namedMembers(routeMembersBySite[site] ?? [], of: enumPlace.route, to: hole.sitePath, ofHoleType: hole.holeType, isSendable: enumPlace.isBuiltBySendableBuilder)
		}
		callRoutes = callRoutes.map { callRoute in
			SeamSignature.CallRoute(
				sitePath: callRoute.sitePath,
				innerKey: callRoute.innerKey,
				rootKey: callRoute.rootKey,
				route: namedRoute(callRoute.route, to: callRoute.sitePath),
				routeMembers: namedMembers(callRoute.routeMembers, of: callRoute.route, to: callRoute.sitePath, ofHoleType: callRoute.rootKey.holeType, isSendable: callRoute.rootKey.isSendable),
				caseName: callRoute.caseName,
				memberValuesType: callRoute.memberValuesType,
				handsFillLevelStruct: callRoute.handsFillLevelStruct,
				reentersEnclosingFill: callRoute.reentersEnclosingFill,
			)
		}

		// This seam's enums first, then every enum their cases reach, each once, breadth first: only those, so a place that
		// a seam this one calls fills, which no builder of this one reaches, changes nothing a caller of this one passes. A
		// call's case for a builder it fills reaches the inner seam's enum whose value it carries, which a caller's reader of
		// the inner seam's levels walks.
		// Which of this seam's carrier levels take their values positionally is decided here, by the seam's own module, and
		// recorded on its enums, which every caller reads. A carrier's members are `public`, so the seam's type caps them.
		let positionalLevels = SeamCarrierValues.positionalLevels(of: ownEnums, memberAccess: seamTypeAccess)
		for index in ownEnums.indices {
			guard let level = SeamCarrierValues.level(ofEnum: ownEnums[index].type), positionalLevels.contains(level) else { continue }
			ownEnums[index].takesValuesPositionally = true
		}
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
		var holesWithBuilders = [(hole: SeamSignature.Hole, builder: SeamSignature.Builder)]()
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
							holesWithBuilders.append((hole, builder))
						}
					}
				}
				keysToVisit.append(contentsOf: innerKeys.reversed())
			}
		}
		return ShapedBuilders(holes: orderedHoles, builders: builders, scopeEnums: scopeEnums, builderBySite: builderBySite, holesWithBuilders: holesWithBuilders, callRoutes: callRoutes, routeMembersBySite: routeMembersBySite)
	}

	/// A call whose fill leads to a place, the builder filled, and the type of the scope value it hands: what one inner scope's
	/// name is per. A public mock hands one inner scope per call and builder, and a seam's builder struct the struct of the
	/// fill's own level per hole type and family whose places the fill holds.
	private struct InnerScopeKey: Hashable {
		let callPath: [Property]
		let innerKey: SeamSignature.ScopeEnum.Key
		let enumType: TypeDescription
	}

	/// The names the fills of each call and builder in `innerScopes` take the scope value the inner seam handed them under:
	/// `__safeDI_<call>_<builder>`, followed, where the call hands the fills of one builder more than one, by `_` and the label
	/// of the builder whose route leads to each, with `_` appended while a name in `reservedNames`, or one of a call on the way
	/// to this one, has it. Calls are named shortest path first, then in the order of their spelling, so no name depends on
	/// the order the routes are met in.
	private static func innerScopeNames(of innerScopes: [(innerScope: SeamSignature.Hole.RouteStep.InnerScope, callPath: [Property], rootBuilderLabel: String)], reservedNames: Set<String>) -> [InnerScopeKey: String] {
		var builderLabelByKey = [InnerScopeKey: String]()
		var rootBuilderLabelByKey = [InnerScopeKey: String]()
		var countByCallAndBuilder = [[Property]: [SeamSignature.ScopeEnum.Key: Set<TypeDescription>]]()
		for (innerScope, callPath, rootBuilderLabel) in innerScopes {
			let key = InnerScopeKey(callPath: callPath, innerKey: innerScope.innerKey, enumType: innerScope.enumType)
			builderLabelByKey[key] = innerScope.builderLabel
			// The label that sorts first, so no name depends on the order the routes are met in.
			rootBuilderLabelByKey[key] = min(rootBuilderLabelByKey[key] ?? rootBuilderLabel, rootBuilderLabel)
			countByCallAndBuilder[callPath, default: [:]][innerScope.innerKey, default: []].insert(innerScope.enumType)
		}
		func sortKey(of key: InnerScopeKey) -> String {
			key.callPath.map(\.asSource).joined(separator: " ") + " " + key.innerKey.spelling + " " + key.enumType.asSource
		}
		// Each key is spelled once, not once for every pair compared.
		let keyedKeys = builderLabelByKey.keys.map { (key: $0, sortKey: sortKey(of: $0)) }
		let orderedKeys = keyedKeys.sorted { first, second in
			first.key.callPath.count != second.key.callPath.count ? first.key.callPath.count < second.key.callPath.count : first.sortKey < second.sortKey
		}.map(\.key)
		var namesByCallPath = [[Property]: Set<String>]()
		var nameByKey = [InnerScopeKey: String]()
		for key in orderedKeys {
			guard let callProperty = key.callPath.last else { continue }
			// The names are released before this key's is inserted, which would copy the set they share otherwise.
			let name: String = {
				// Each name is asked of each set in turn, never of their union: a union made for every key holds every
				// payload's name, so naming the inner scopes grew with the square of the seam's places.
				let taken = GenerationWork.taking(
					NamesConsultedInTurn([reservedNames] + (1...key.callPath.count).compactMap { namesByCallPath[Array(key.callPath.prefix($0))] }),
					by: .namingInnerScopes,
				)
				let isOneOfSeveral = (countByCallAndBuilder[key.callPath]?[key.innerKey]?.count ?? 0) > 1
				let rootBuilderSuffix = isOneOfSeveral ? "_\(rootBuilderLabelByKey[key, default: ""].spelledWithoutBackticks)" : ""
				var name = ScopeGenerator.functionName(toBuildPropertyNamed: "\(callProperty.label.spelledWithoutBackticks)_\(builderLabelByKey[key, default: ""])\(rootBuilderSuffix)".spelledAsIdentifier)
				while taken.contains(name) {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				return name
			}()
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

	// MARK: The type of a builder a person writes

	/// What the builder a person writes for some places of one hole type, in one family, takes: its type follows from what
	/// the places forward, and nothing else (`builderForm(ofPlaces:)`).
	enum BuilderForm: Sendable {
		/// Nothing: every place is a plain or lazy one, or an instantiator that forwards nothing (`ErasedInstantiator<(), T>`),
		/// or `T.ForwardedProperties` beside such a place. The builder is `() -> B` whether or not a plain place is among the
		/// places, so a place that joins or leaves never flips it to a wrapper's `Builder` that takes `()`.
		case value
		/// Every place is an instantiator that forwards a value, whose type, `wrapperType`, is spelled alike: the builder is
		/// that wrapper's `Builder`, or its `Sendable` twin's in the `@Sendable` family.
		case wrapper(TypeDescription)
		/// Every place is an instantiator that forwards `forwarded`, through wrappers or spellings that differ: the builder is
		/// the erased wrapper's `Builder` over it.
		case erased(forwarded: TypeDescription)

		/// The value the builder takes, or `nil` for a builder that takes none.
		var forwardedValue: TypeDescription? {
			switch self {
			case .value:
				nil
			case let .wrapper(wrapperType):
				wrapperType.forwardedTypeOfWrapper?.strippingEscaping
			case let .erased(forwarded):
				forwarded
			}
		}
	}

	/// The form of the builder a person writes for `places`, places of one hole type reached by one family's builder or
	/// level, whose forwarded values agree (`placesForwardingOtherValues(among:comparison:)` reports those that do not). A
	/// builder of places that forward nothing takes nothing, as a plain place's does. The value the erased form takes is the
	/// most explicit of the places' spellings of it (`TypeDescription.mostExplicitSpelling(among:)`): chosen by the
	/// spellings' shapes, never by where the places are, their names or the order of levels, so renaming a file or a type
	/// never respells it. Reads nothing but the places, so a mock's builder can take the same type over its own places
	/// (`builderForm(ofPlaceProperties:)`).
	static func builderForm(ofPlaces places: [SeamSignature.Hole]) -> BuilderForm {
		builderForm(ofPlaceProperties: places.map(\.property))
	}

	/// The form of the builder a person writes for places whose properties are `properties`, as `builderForm(ofPlaces:)`.
	static func builderForm(ofPlaceProperties properties: [Property]) -> BuilderForm {
		guard !properties.isEmpty, properties.allSatisfy(\.propertyType.isAnyInstantiator) else { return .value }
		// A place that forwards nothing makes the builder take nothing: the places forward the same value, so each other place
		// forwards nothing too, or `T.ForwardedProperties`, which beside it is nothing.
		let forwardedTypes = properties.compactMap { $0.typeDescription.forwardedTypeOfWrapper?.strippingEscaping }
		guard forwardedTypes.count == properties.count, let firstForwardedType = forwardedTypes.first else { return .value }
		let wrapperTypes = properties.map(\.typeDescription.unwrapped.strippingEscaping)
		if Set(wrapperTypes.map(\.asSource)).count == 1 {
			return .wrapper(wrapperTypes[0])
		}
		return .erased(forwarded: firstForwardedType.mostExplicitSpelling(among: forwardedTypes.dropFirst()))
	}

	/// The type of the builder a person writes in `form`, returning `builtType`, in the `@Sendable` family where `isSendable`,
	/// as a parameter of the readable initializer spells it.
	static func readableBuilderType(of form: BuilderForm, returning builtType: TypeDescription, isSendable: Bool) -> TypeDescription {
		switch form {
		case .value:
			let functionType = TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: builtType)
			return (isSendable ? functionType.asSendableFunction : functionType).asFunctionParameter
		case let .wrapper(wrapperType):
			return wrapperType.wrapperBuilderParameterType(isSendable: isSendable)
		case let .erased(forwarded):
			return .attributed(erasedBuilderType(forwarding: forwarded, returning: builtType, isSendable: isSendable), specifiers: [], attributes: ["escaping"])
		}
	}

	/// `ErasedInstantiator<forwarded, builtType>.Builder`, or `SendableErasedInstantiator`'s where `isSendable`: how a builder
	/// struct spells a builder that takes a forwarded value, since the constrained wrappers cannot be spelled over its
	/// generic parameter.
	static func erasedBuilderType(forwarding forwarded: TypeDescription, returning builtType: TypeDescription, isSendable: Bool) -> TypeDescription {
		.nested(
			name: Dependency.wrapperBuilderTypeName,
			parentType: .simple(name: isSendable ? Dependency.sendableErasedInstantiatorType : Dependency.erasedInstantiatorType, generics: [forwarded, builtType]),
			generics: [],
		)
	}

	/// How two places of one builder are compared for the value they forward: a type the projection
	/// `TypeDescription.withoutSpellingDifferences(qualifiedByModulesNamed:orDeclaringModulesNamed:declaredTypeNames:)` shows
	/// two spellings of are one value, and nothing is the same value as the `ForwardedProperties` of the type that fills
	/// the builder, which a type that conforms to `Instantiable` by hand may declare as anything.
	struct ForwardedValueComparison {
		/// The type a declaration must fulfill to fill the builder.
		let fillingType: TypeDescription
		/// The modules that declare each place's owner, by owner.
		let moduleNameByOwner: [TypeDescription: String]
		let declaredTypeNames: DeclaredTypeNames

		/// Whether `place` and `otherPlace` forward the same value.
		func forwardsSameValue(_ place: SeamSignature.Hole, as otherPlace: SeamSignature.Hole) -> Bool {
			switch (place.forwardedType, otherPlace.forwardedType) {
			case (nil, nil):
				true
			case let (forwardedType?, nil), let (nil, forwardedType?):
				isForwardedPropertiesOfFillingType(forwardedType, seenFrom: [place, otherPlace])
			case let (forwardedType?, otherForwardedType?):
				projected(forwardedType.strippingEscaping, seenFrom: [place, otherPlace]) == projected(otherForwardedType.strippingEscaping, seenFrom: [place, otherPlace])
			}
		}

		/// Whether `forwardedType` is `T.ForwardedProperties`, `T` the type that fills the builder.
		private func isForwardedPropertiesOfFillingType(_ forwardedType: TypeDescription, seenFrom places: [SeamSignature.Hole]) -> Bool {
			guard case let .nested(name, parentType, generics) = forwardedType, name == Dependency.forwardedPropertiesType, generics.isEmpty else { return false }
			return projected(parentType, seenFrom: places).spelledCanonically == projected(fillingType, seenFrom: places).spelledCanonically
		}

		/// `type` without the spelling differences that the modules of `places`' owners, and the modules a spelling of the
		/// places may be qualified by, show; a name two modules declare is never seen through.
		private func projected(_ type: TypeDescription, seenFrom places: [SeamSignature.Hole]) -> TypeDescription {
			let ownerModuleNames = places.compactMap { moduleNameByOwner[$0.ownerType] }
			return type.withoutSpellingDifferences(
				qualifiedByModulesNamed: ["Swift"],
				orDeclaringModulesNamed: ownerModuleNames + places.flatMap(\.declaringModuleNames),
				declaredTypeNames: declaredTypeNames,
			)
		}
	}

	/// The places among `places`, of one builder, that forward another value than the first place by location, each with
	/// that first place: the reference follows declaration order by design, never names or the order places are visited in.
	static func placesForwardingOtherValues(among places: [SeamSignature.Hole], comparison: ForwardedValueComparison) -> [(place: SeamSignature.Hole, reference: SeamSignature.Hole)] {
		let orderedPlaces = places.sortedByForwardingLocation
		return orderedPlaces.first.map { reference in
			orderedPlaces.dropFirst().filter { !comparison.forwardsSameValue($0, as: reference) }.map { (place: $0, reference: reference) }
		} ?? []
	}

	/// What one tier names its builders by.
	struct TierNames {
		let tier: AccessLevel
		/// The labels of the parameters the tier takes: its own and every wider tier's.
		let parameterLabels: Set<String>

		/// The label the tier takes the builder of a hole type of `stem` under, in its family: the stem's label, with `_`
		/// appended while a parameter the tier takes has it.
		func label(ofStem stem: String, isSendable: Bool) -> String {
			var label = isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem)
			while parameterLabels.contains(label) {
				label = "\(label)_".spelledAsJoinedIdentifier
			}
			return label
		}
	}

	/// The stems of a seam's or a public mock's hole types, and the names of each of its tiers.
	struct BuilderNames {
		let stemByHoleType: [SeamSignature.HoleType: String]
		/// Each tier's names, widest first.
		let tiers: [TierNames]
	}

	/// The stems of `holeTypes`, and the names of each tier that `parameters`, each with the access of the narrowest tier
	/// that takes it, give their builders, widest first: `widestTier`, then each narrower access among `parameters`, each
	/// tier's labels computed from the labels it takes alone, so they never depend on the order the parameters are
	/// declared in.
	private static func tierNames(
		of holeTypes: [SeamSignature.HoleType],
		parameters: [(label: String, access: AccessLevel)],
		widestTier: AccessLevel,
	) -> BuilderNames {
		let tiers = [widestTier] + Set(parameters.map(\.access)).filter { $0 < widestTier }.sorted(by: >)
		return BuilderNames(
			stemByHoleType: stems(of: holeTypes),
			tiers: tiers.map { tier in
				TierNames(tier: tier, parameterLabels: Set(parameters.filter { $0.access >= tier }.map(\.label)))
			},
		)
	}

	/// The stem each of `holeTypes` is named by, from what it builds alone: its instantiated type as an identifier where
	/// the type it returns is the same, else the instantiated type's followed by `_` and the returned type's. Only a stem
	/// that equals another's, or whose plain label equals another's plain or `@Sendable` label, is named apart, by its types; no rung names an owner, a
	/// path or a parameter, so adding a place of a hole type already built never renames one, and adding a hole type renames
	/// another only when their stems or labels coincide.
	static func stems(of holeTypes: [SeamSignature.HoleType]) -> [SeamSignature.HoleType: String] {
		func stem(of type: TypeDescription) -> String {
			type.simplified.asIdentifier.spelledWithoutBackticks
		}
		// A builder of a place instantiated only if available returns an optional: its stem is its type's followed by
		// `Optional` in every seam, so a required builder of the same type added later renames neither.
		var stems = holeTypes.map { holeType in
			let stemOfType = holeType.instantiatedType == holeType.builtType.unwrapped
				? stem(of: holeType.instantiatedType)
				: "\(stem(of: holeType.instantiatedType))_\(stem(of: holeType.builtType.unwrapped))"
			return holeType.builtType.isOptional ? stemOfType + "Optional" : stemOfType
		}
		// A stem collides where another stem equals it, or gives its plain label as its own plain or `@Sendable` label: a
		// stem's plain label equal to another's `@Sendable` label names apart only the stem whose plain label it is
		// (`ServiceSendable` beside `Service`), so a hole type's own labels never follow another type's name. Equal stems give
		// equal plain labels, so counting the stems that give each label in each family finds every collision with one pass
		// over the stems: comparing every pair of stems, and lowering both stems' capitals for each pair, grew with the
		// square of the hole types. An optional builder's stem that collides is named apart first, so a required builder
		// keeps its name beside it.
		var labelCounts = BuilderLabelCounts(stems: stems)
		for namesApartOptionalStems in [true, false] {
			let colliding = holeTypes.indices.filter {
				(!namesApartOptionalStems || holeTypes[$0].builtType.isOptional) && labelCounts.collides(stems[$0])
			}
			guard !colliding.isEmpty else { continue }
			let collidingIndices = Set(colliding)
			let renamed = ScopeGenerator.identifierSafeNames(
				for: colliding.map { (label: stems[$0], suffixTypes: [holeTypes[$0].instantiatedType, holeTypes[$0].builtType]) },
				reservedNames: Set(holeTypes.indices.filter { !collidingIndices.contains($0) }.map { stems[$0] }),
				countingWorkAs: .namingEntriesApart,
			)
			for (index, name) in zip(colliding, renamed) {
				labelCounts.replace(stems[index], with: name.spelledWithoutBackticks)
				stems[index] = name.spelledWithoutBackticks
			}
			// Two stems may still give one label: each that does takes a trailing underscore until none does.
			for index in namesApartOptionalStems ? colliding : Array(stems.indices) {
				while labelCounts.collides(stems[index]) {
					labelCounts.replace(stems[index], with: stems[index] + "_")
					stems[index] += "_"
				}
			}
		}
		return Dictionary(zip(holeTypes, stems), uniquingKeysWith: { first, _ in first })
	}

	/// How many of a set of stems give each builder label, in each family (`stems(of:)`).
	private struct BuilderLabelCounts {
		init(stems: [String]) {
			for stem in stems {
				add(stem)
			}
		}

		/// Whether another stem than one `stem` stands for gives `stem`'s plain label, as its plain or its `@Sendable` label. A
		/// stem's own two labels differ, so its own `@Sendable` label is never counted against it.
		func collides(_ stem: String) -> Bool {
			let plainLabel = plainBuilderLabel(ofStem: stem)
			return plainCountByLabel[plainLabel, default: 0] > 1 || sendableCountByLabel[plainLabel, default: 0] > 0
		}

		/// Counts `newStem` in the place of one `oldStem`.
		mutating func replace(_ oldStem: String, with newStem: String) {
			plainCountByLabel[plainBuilderLabel(ofStem: oldStem), default: 0] -= 1
			sendableCountByLabel[sendableBuilderLabel(ofStem: oldStem), default: 0] -= 1
			add(newStem)
		}

		private var plainCountByLabel = [String: Int]()
		private var sendableCountByLabel = [String: Int]()

		private mutating func add(_ stem: String) {
			plainCountByLabel[plainBuilderLabel(ofStem: stem), default: 0] += 1
			sendableCountByLabel[sendableBuilderLabel(ofStem: stem), default: 0] += 1
		}
	}

	/// The stem with its leading capitals lowered, keeping the last when a lowercase letter follows it, then `Builder`.
	static func plainBuilderLabel(ofStem stem: String) -> String {
		"\(loweredLeadingCapitals(of: stem))Builder".spelledAsIdentifier
	}

	static func sendableBuilderLabel(ofStem stem: String) -> String {
		"\(loweredLeadingCapitals(of: stem))SendableBuilder".spelledAsIdentifier
	}

	private static func loweredLeadingCapitals(of stem: String) -> String {
		// An ASCII stem, as nearly every identifier is, is read by its bytes: each is one `Character`, upper or lowercase
		// exactly where it is a Latin letter of that case, and lowered by its letter alone, so the result is the one the
		// reading by `Character` gives, without decoding a grapheme per letter.
		if stem.utf8.allSatisfy({ $0 < 0x80 }) {
			var bytes = Array(stem.utf8)
			let lowerCount = countOfLeadingCapitalsToLower(in: bytes, isUppercase: { $0 >= 0x41 && $0 <= 0x5A }, isLowercase: { $0 >= 0x61 && $0 <= 0x7A })
			for index in 0..<lowerCount {
				bytes[index] += 0x20
			}
			return lowerCount > 0 ? String(decoding: bytes, as: UTF8.self) : stem
		} else {
			let characters = Array(stem)
			let lowerCount = countOfLeadingCapitalsToLower(in: characters, isUppercase: \.isUppercase, isLowercase: \.isLowercase)
			return lowerCount > 0 ? String(characters[..<lowerCount]).lowercased() + String(characters[lowerCount...]) : stem
		}
	}

	/// How many of `elements`' leading capitals `loweredLeadingCapitals(of:)` lowers: every one, but the last when a
	/// lowercase letter follows it and it is not the first.
	private static func countOfLeadingCapitalsToLower<Element>(in elements: [Element], isUppercase: (Element) -> Bool, isLowercase: (Element) -> Bool) -> Int {
		var capitalCount = 0
		while capitalCount < elements.count, isUppercase(elements[capitalCount]) {
			capitalCount += 1
		}
		guard capitalCount > 0 else { return 0 }
		return capitalCount < elements.count && isLowercase(elements[capitalCount]) ? max(capitalCount - 1, 1) : capitalCount
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
		/// A seam's call inside a fill that re-enters an enclosing call's fill by name, with the cases on its path,
		/// the last its case for the builder the reused fill is passed for.
		case reenteringCall(sitePath: [Property], steps: [ReachedStep])
	}

	/// Every place and every call that passes a builder up in the tree `generator` roots, in the order the generated code
	/// reaches them: a seam call's fills are declared before the call. A fill's `@Sendable` function counts as one on the
	/// call's step, whose case for the builder filled leads to what the fill builds, which carries the called seam's root
	/// enum (`filledRootKey(of:in:)`).
	/// - Parameter reenteredFillsByKey: The fills a call inside a fill can re-enter (`emittingFillsByKey(inTreeRootedAt:)`):
	///   a call that re-enters one takes the called seam's struct from a member of its own case.
	private static func placesAndCalls(in generator: ScopeGenerator, reenteredFillsByKey: [String: ScopeGenerator]) -> [PlaceOrCall] {
		/// Whether the walk enters `child`: its tree leads to a place, or to a call that re-enters a fill whose tree does.
		func leadsOn(_ child: ScopeGenerator) -> Bool {
			child.containsBuildSite || child.passesUpBuilder || (child.holdsCallReenteringEnclosingFill && !reenteredFillsByKey.isEmpty)
		}
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
				if let callStep = frame.steps.last {
					for reusedFill in reenteredFills(by: frame.generator, in: reenteredFillsByKey) {
						guard let innerKey = filledRootKey(of: reusedFill, in: frame.generator) else { continue }
						let fulfillerBuildsInSendableFunction = reusedFill.children.first?.buildsInSendableFunction ?? false
						reached.append(.reenteringCall(sitePath: frame.path, steps: frame.steps.dropLast() + [ReachedStep(
							type: callStep.type,
							property: callStep.property,
							pathLength: callStep.pathLength,
							buildsInSendableFunction: callStep.buildsInSendableFunction,
							filledBuilder: SeamDeclarationGraph.FilledBuilder(innerKey: innerKey, carriesInnerScope: !fulfillerBuildsInSendableFunction),
						)]))
					}
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
			} else if leadsOn(child.generator), child.generator.fillEmitsCode {
				if child.generator.fillHole != nil {
					// A fill of the call this frame is: the call's step becomes its case for the builder filled, on which the fill's
					// `@Sendable` function counts. The filled place's path in the inner seam's tree has no case of this seam's.
					guard let callStep = frame.steps.last, let innerKey = filledRootKey(of: child.generator, in: frame.generator) else { continue }
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
			// A seam none of whose enums is in a cycle keeps its signature, whose call shape assigning the enums computes again.
			guard seamRoot.signature.scopeEnums.contains(where: { componentByKey[$0.key] != nil }) else { return seamRoot }
			// The enums are marked in a copy, assigned once, since each assignment computes the signature's call shape again.
			var signature = seamRoot.signature
			signature.scopeEnums = markingIndirectCases(of: seamRoot.signature.scopeEnums, componentByKey: componentByKey)
			return ScopeGenerator.SeamRoot(signature: signature, callRoutes: seamRoot.callRoutes, routeMembersBySite: seamRoot.routeMembersBySite, unreadTypeComment: seamRoot.unreadTypeComment)
		}
	}

	/// The strongly connected component of each of `ownEnums` among them that holds another of them, by key: an index
	/// shared by the enums of one component. An enum that holds none of them is alone in its component, so it has no entry,
	/// and no case is marked for it. The components are found in the order of the keys' spellings.
	static func componentByKey(of ownEnums: [SeamSignature.ScopeEnum]) -> [SeamSignature.ScopeEnum.Key: Int] {
		var heldKeys = [SeamSignature.ScopeEnum.Key: [SeamSignature.ScopeEnum.Key]]()
		for scopeEnum in ownEnums {
			heldKeys[scopeEnum.key] = scopeEnum.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:))
		}
		// Every enum of a cycle holds another enum of it, so the enums that hold none of `ownEnums` are left out.
		var edges = [SeamSignature.ScopeEnum.Key: [SeamSignature.ScopeEnum.Key]]()
		for (key, held) in heldKeys {
			let ownHeld = held.filter { heldKeys[$0] != nil }
			if !ownHeld.isEmpty {
				edges[key] = ownHeld
			}
		}
		let nodes = edges.keys.map { (key: $0, spelling: $0.spelling) }.sorted { $0.spelling < $1.spelling }.map(\.key)
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

extension Sequence<SeamSignature.Hole> {
	/// The type a builder of each hole type of these places returns, as these places spell it: the most explicit of their
	/// spellings (`TypeDescription.mostExplicitSpelling(among:)`), which reads the spellings alone, so neither the places'
	/// labels, the types that declare them nor the order they are declared in decide it, and every site that spells it – the
	/// builder, the struct of a fill's own level, a caller's dispatchers and conversions – spells it alike. Found in one pass,
	/// since a scan of every place per hole type grows with their product; a hole type no place is of is absent, and a caller
	/// spells `holeType.builtType` for it.
	var builtTypeByHoleType: [SeamSignature.HoleType: TypeDescription] {
		var builtTypeByHoleType = [SeamSignature.HoleType: TypeDescription]()
		for hole in self {
			let holeType = hole.holeType
			builtTypeByHoleType[holeType] = builtTypeByHoleType[holeType].map { $0.mostExplicitSpelling(among: [hole.builtType]) } ?? hole.builtType
		}
		return builtTypeByHoleType
	}
}

extension SeamSignature.Hole.Site {
	/// A spelling that orders sites.
	var sortKey: String {
		"\(seamType.asSource) \(path.map(\.asSource).joined(separator: " "))"
	}
}

extension SeamSignature.Hole {
	/// Where a message about the value the place forwards is reported: at its declaration, or, for a place an inner seam
	/// passes up, at the property of this seam's tree through which the tree reaches that inner seam, since a build never
	/// reports in a file another module owns.
	var forwardingLocation: Dependency.DeclarationLocation? {
		passedUpRoute.first?.declarationLocation ?? declarationLocation
	}
}

extension [SeamSignature.Hole] {
	/// The places by `forwardingLocation`, places at one location in their order here, which keeps an inner seam's order.
	var sortedByForwardingLocation: [SeamSignature.Hole] {
		enumerated().sorted { first, second in
			let (firstLocation, secondLocation) = (first.element.forwardingLocation, second.element.forwardingLocation)
			return firstLocation == secondLocation ? first.offset < second.offset : Dependency.DeclarationLocation.precedesInSourceOrder(firstLocation, secondLocation)
		}.map(\.element)
	}
}
