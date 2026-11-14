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
	/// - Parameter otherParameters: The labels of a public mock's parameters, each with the access of the narrowest tier
	///   that takes it, which its builders follow and are named apart from as a seam's builders are from its parameters.
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
	) -> ShapedBuilders {
		guard !flatHoles.isEmpty else { return ShapedBuilders(holes: [], builders: [], scopeEnums: [], builderBySite: [:]) }
		let seamType = seam.concreteInstantiable
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		var holesBySite = Dictionary(flatHoles.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })

		// The enums' cases per path, in the order the seam's generated code first reaches them.
		struct DraftCase {
			let rawName: String
			let disambiguatingType: TypeDescription
			let kind: SeamSignature.ScopeEnum.Case.Kind
		}
		var draftCasesByKey = [SeamSignature.ScopeEnum.Key: [DraftCase]]()
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
		// A seam's places and calls outside every fill, by hole type, whose enums are nested by type (`scopeEnumsByType`). A
		// public mock's enums keep a case per path, as does a place inside a fill.
		let nestsByType = !scopeTypeNames.areQualified
		var reachedByHoleType = [SeamSignature.HoleType: [ReachedPlace]]()
		for reached in placesAndCalls(in: generator) {
			switch reached {
			case let .place(sitePath, pathTypes, buildsInSendableFunction, isInSendableFunction, isInFill):
				let site = SeamSignature.Hole.Site(seamType: seamType, path: sitePath)
				guard let hole = holesBySite[site] else { continue }
				reach(hole.holeType)
				if nestsByType, !isInFill {
					reachedByHoleType[hole.holeType, default: []].append(ReachedPlace(sitePath: sitePath, pathTypes: pathTypes, buildsInSendableFunction: buildsInSendableFunction, call: nil))
				} else {
					let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: hole.holeType, isSendable: isInSendableFunction)
					draftCasesByKey[key, default: []].append(DraftCase(rawName: SeamSignature.Hole.caseName(of: sitePath), disambiguatingType: hole.ownerType, kind: .own(site: site)))
				}
			case let .call(sitePath, call, pathTypes, buildsInSendableFunction, isInSendableFunction, isInFill):
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
					      let innerEnum = reachedEnum(innerKey)
					else { continue }
					reach(innerKey.holeType)
					let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: innerKey.holeType, isSendable: innerKey.isSendable || isInSendableFunction)
					if nestsByType, !isInFill {
						if reachedHoleTypes.insert(innerKey.holeType).inserted {
							reachedByHoleType[innerKey.holeType, default: []].append(ReachedPlace(sitePath: sitePath, pathTypes: pathTypes, buildsInSendableFunction: buildsInSendableFunction, call: call))
						}
					} else {
						let rawName = SeamSignature.Hole.caseName(of: sitePath) + (innerKey.isSendable ? "_Sendable" : "")
						draftCasesByKey[key, default: []].append(DraftCase(rawName: rawName, disambiguatingType: innerKey.seamType, kind: .inner(enumKey: innerKey, enumType: innerEnum.type, sitePath: sitePath, isIndirect: false)))
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
		var valuesBindingPrefixesByStem = [String: Set<[Property]>]()
		var builders = [SeamSignature.Builder]()
		var internalNameByFamily = [SeamSignature.ScopeEnum.Key: String]()
		for holeType in orderedHoleTypes {
			let stem = stemByHoleType[holeType, default: ""]
			let rootTypeNames = (plain: "\(scopeTypeNames.plain)_\(stem)".spelledAsIdentifier, sendable: "\(scopeTypeNames.sendable)_\(stem)".spelledAsIdentifier)
			// Each family's cases per path, named: two cases of one name are both named apart.
			var namedDraftCasesByFamily = [Bool: [(draftCase: DraftCase, name: String)]]()
			// A payload struct's name is taken from the case; a type a field spells must not resolve to the struct.
			var takenStructNamesByFamily = [Bool: Set<String>]()
			for isSendable in [false, true] {
				let draftCases = draftCasesByKey[SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: isSendable)] ?? []
				var indicesByName = [String: [Int]]()
				for (index, draftCase) in draftCases.enumerated() {
					indicesByName[draftCase.rawName, default: []].append(index)
				}
				let collidingIndices = draftCases.indices.filter { indicesByName[draftCases[$0].rawName, default: []].count > 1 }
				var caseNames = draftCases.map(\.rawName.spelledAsIdentifier)
				let renamed = ScopeGenerator.identifierSafeNames(
					for: collidingIndices.map { (label: draftCases[$0].rawName, suffixTypes: [draftCases[$0].disambiguatingType]) },
					reservedNames: Set(draftCases.indices.filter { !collidingIndices.contains($0) }.map { caseNames[$0] }),
				)
				for (index, name) in zip(collidingIndices, renamed) {
					caseNames[index] = name.spelledAsIdentifier
				}
				namedDraftCasesByFamily[isSendable] = Array(zip(draftCases, caseNames))
				var takenStructNames = Set(caseNames)
				for draftCase in draftCases {
					switch draftCase.kind {
					case let .own(site):
						for field in holesBySite[site]?.fields ?? [] {
							takenStructNames.formUnion(TypeAccessProof.mentionedTypes(in: field.property.typeDescription).compactMap(\.outermostTypeName))
						}
						if let forwardedType = holesBySite[site]?.forwardedType {
							takenStructNames.formUnion(TypeAccessProof.mentionedTypes(in: forwardedType).compactMap(\.outermostTypeName))
						}
					case let .inner(_, enumType, _, _):
						takenStructNames.formUnion(TypeAccessProof.mentionedTypes(in: enumType).compactMap(\.outermostTypeName))
					case .place, .nested:
						// Only an enum nested by type has these, which `scopeEnumsByType` names.
						break
					}
				}
				takenStructNamesByFamily[isSendable] = takenStructNames
			}
			// A seam's enums are nested by type where its places and calls are outside every fill; the cases of the places inside a
			// fill, which keep a case per path, follow each root's own.
			var byType = ScopeEnumsByType()
			if let reached = reachedByHoleType[holeType] {
				byType = scopeEnumsByType(
					of: seam,
					holeType: holeType,
					rootTypeNames: rootTypeNames,
					builderLabels: (plain: label(of: holeType, isSendable: false), sendable: label(of: holeType, isSendable: true)),
					generator: generator,
					reached: reached,
					// The names the roots' cases per path declare and spell, which their nested types must not shadow.
					takenTypeNames: takenStructNamesByFamily[false, default: []].union(takenStructNamesByFamily[true, default: []]),
					holesBySite: holesBySite,
					parameters: parameters,
					proof: proof,
					instantiables: instantiables,
					reachedEnum: reachedEnum,
				)
				valuesBindingPrefixesByStem[loweredLeadingCapitals(of: stem)] = byType.valuesBindingPrefixes
				callRoutes += byType.callRoutes
				for (site, enumPlace) in byType.enumPlaceBySite {
					holesBySite[site]?.enumPlace = enumPlace
					holesBySite[site]?.scopeTypeName = enumPlace.enumTypeName
				}
			}
			for isSendable in [false, true] {
				let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: isSendable)
				let typeName = isSendable ? rootTypeNames.sendable : rootTypeNames.plain
				let byTypeRoot = byType.rootEnum(isSendable: isSendable)
				let nestedEnums = byType.enums.filter { $0.key.isSendable == isSendable && $0.rootTypeName != nil }
				var takenStructNames = takenStructNamesByFamily[isSendable, default: []]
				takenStructNames.formUnion((byTypeRoot?.cases ?? []).compactMap(\.values?.typeName))
				var cases = byTypeRoot?.cases ?? []
				for (draftCase, caseName) in namedDraftCasesByFamily[isSendable, default: []] {
					var caseName = caseName
					while cases.contains(where: { $0.name == caseName }) {
						caseName = "\(caseName)_".spelledAsJoinedIdentifier
					}
					cases.append(SeamSignature.ScopeEnum.Case(name: caseName, kind: draftCase.kind))
					guard case let .own(site) = draftCase.kind else { continue }
					var valuesTypeName = "\(caseName)_Values".spelledAsJoinedIdentifier
					while !takenStructNames.insert(valuesTypeName).inserted {
						valuesTypeName = "\(valuesTypeName)_".spelledAsJoinedIdentifier
					}
					holesBySite[site]?.enumPlace = SeamSignature.Hole.EnumPlace(enumTypeName: typeName, caseName: caseName, valuesTypeName: valuesTypeName, isBuiltBySendableBuilder: isSendable)
					holesBySite[site]?.scopeTypeName = typeName
				}
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
						case let .own(site):
							[site]
						case let .place(sites):
							sites
						case .nested, .inner:
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
		let valuesBindingNamesByStem = valuesBindingNames(
			ofPrefixes: valuesBindingPrefixesByStem,
			reservedNames: names.taken.union(holesBySite.values.compactMap(\.wrapperFunctionName)),
		)
		func namedRoute(_ route: [SeamSignature.Hole.RouteStep], toSiteAt sitePath: [Property], ofHoleType holeType: SeamSignature.HoleType) -> [SeamSignature.Hole.RouteStep] {
			let nameByPrefix = valuesBindingNamesByStem[loweredLeadingCapitals(of: stemByHoleType[holeType, default: ""]), default: [:]]
			return route.enumerated().map { index, step in
				step.named(nameByPrefix[Array(sitePath.prefix(index + 1))])
			}
		}
		for site in holesBySite.keys {
			guard let hole = holesBySite[site], hole.innerSeamType == nil, let enumPlace = hole.enumPlace, enumPlace.isNestedByType else { continue }
			holesBySite[site]?.enumPlace = SeamSignature.Hole.EnumPlace(
				nestedByTypeIn: enumPlace.enumTypeName,
				rootEnumTypeName: enumPlace.rootEnumTypeName,
				caseName: enumPlace.caseName,
				valuesTypeName: enumPlace.valuesTypeName,
				isBuiltBySendableBuilder: enumPlace.isBuiltBySendableBuilder,
				route: namedRoute(enumPlace.route, toSiteAt: hole.sitePath, ofHoleType: hole.holeType),
				values: enumPlace.values,
			)
		}
		callRoutes = callRoutes.map { callRoute in
			SeamSignature.CallRoute(
				sitePath: callRoute.sitePath,
				innerKey: callRoute.innerKey,
				rootKey: callRoute.rootKey,
				route: namedRoute(callRoute.route, toSiteAt: callRoute.sitePath, ofHoleType: callRoute.rootKey.holeType),
				caseName: callRoute.caseName,
				values: callRoute.values,
			)
		}

		// This seam's enums first, then every enum their cases reach, each once, breadth first: only those, so a place that
		// a seam this one calls fills, which no builder of this one reaches, changes nothing a caller of this one passes.
		var seenKeys = Set(ownEnums.map(\.key))
		var scopeEnums = ownEnums
		var nextEnumIndex = 0
		while nextEnumIndex < scopeEnums.count {
			for enumCase in scopeEnums[nextEnumIndex].cases {
				guard let innerKey = SeamSignature.ScopeEnum.heldKey(of: enumCase), seenKeys.insert(innerKey).inserted, let innerEnum = reachedEnum(innerKey) else { continue }
				scopeEnums.append(innerEnum)
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
					case let .own(site):
						sites = [site]
					case let .place(placeSites):
						sites = placeSites
					case let .nested(innerKey, _),
					     let .inner(innerKey, _, _, _):
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
		/// A place, with the types on its path (see `ReachedPlace.pathTypes`), whether each property on its path is built in a
		/// `@Sendable` function of its own (see `ReachedPlace.buildsInSendableFunction`), whether any `@Sendable` function, a
		/// fill's included, encloses it, and whether a fill is on the path.
		case place(sitePath: [Property], pathTypes: [TypeDescription], buildsInSendableFunction: [Bool], isInSendableFunction: Bool, isInFill: Bool)
		case call(sitePath: [Property], generator: ScopeGenerator, pathTypes: [TypeDescription], buildsInSendableFunction: [Bool], isInSendableFunction: Bool, isInFill: Bool)
	}

	/// Every place and every call that passes a builder up in the tree `generator` roots, in the order the generated code
	/// reaches them: a seam call's fills are declared before the call. A fill's `@Sendable` function counts as one on the path
	/// of what it builds.
	private static func placesAndCalls(in generator: ScopeGenerator) -> [PlaceOrCall] {
		struct Frame {
			let generator: ScopeGenerator
			let orderedChildren: [ScopeGenerator.OrderedChild]
			var nextPosition: Int
			let path: [Property]
			/// Beside `path`, whether each property on it is built in a `@Sendable` function of its own.
			let buildsInSendableFunction: [Bool]
			/// Whether a `@Sendable` function, a fill's included, encloses this scope's children.
			let isInSendableFunction: Bool
			/// The type each scope on the path builds, this one's included, fills left out.
			let pathTypes: [TypeDescription]
			let isInFill: Bool
		}
		var reached = [PlaceOrCall]()
		var frames = [Frame(
			generator: generator,
			orderedChildren: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []),
			nextPosition: 0,
			path: [],
			buildsInSendableFunction: [],
			isInSendableFunction: false,
			pathTypes: generator.builtInstantiable.map { [$0.concreteInstantiable] } ?? [],
			isInFill: false,
		)]
		while let frame = frames.last {
			guard frame.nextPosition < frame.orderedChildren.count else {
				frames.removeLast()
				if !frame.generator.passedUpHoles.isEmpty {
					reached.append(.call(sitePath: frame.path, generator: frame.generator, pathTypes: Array(frame.pathTypes.dropLast()), buildsInSendableFunction: frame.buildsInSendableFunction, isInSendableFunction: frame.isInSendableFunction, isInFill: frame.isInFill))
				}
				continue
			}
			frames[frames.count - 1].nextPosition += 1
			let child = frame.orderedChildren[frame.nextPosition]
			if let holeSite = child.generator.holeSite {
				let isSendableWrapper = holeSite.property.propertyType.isSendable
				reached.append(.place(sitePath: frame.path + [holeSite.property], pathTypes: frame.pathTypes, buildsInSendableFunction: frame.buildsInSendableFunction + [isSendableWrapper], isInSendableFunction: frame.isInSendableFunction || isSendableWrapper, isInFill: frame.isInFill))
			} else if child.generator.containsBuildSite || child.generator.passesUpBuilder, child.generator.fillEmitsCode {
				let isFill = child.generator.fillHole != nil
				let pathAddition = child.generator.fillHole?.pathBeforePropertyInItsFill ?? child.generator.property.map { [$0] } ?? []
				// A fill's `@Sendable` function encloses everything it builds: it counts on the first property it adds.
				let addsSendableFunction = child.generator.buildsInSendableFunction || frame.generator.buildsInSendableFunction(ofFill: child.generator)
				frames.append(Frame(
					generator: child.generator,
					orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
					nextPosition: 0,
					path: frame.path + pathAddition,
					buildsInSendableFunction: frame.buildsInSendableFunction + pathAddition.indices.map { $0 == 0 && addsSendableFunction },
					isInSendableFunction: frame.isInSendableFunction || addsSendableFunction,
					pathTypes: frame.pathTypes + (isFill ? [] : child.generator.builtInstantiable.map { [$0.concreteInstantiable] } ?? []),
					isInFill: frame.isInFill || isFill,
				))
			}
		}
		return reached
	}

	/// Marks each case of `seamRoots`' enums that holds an enum of its own strongly connected component `indirect`. Every
	/// enum of a cycle is generated by one module, whose seams are the ones computed here, and membership is a set property,
	/// so no name order reaches the output.
	static func markingIndirectCases(in seamRoots: [ScopeGenerator.SeamRoot?]) -> [ScopeGenerator.SeamRoot?] {
		var edges = [SeamSignature.ScopeEnum.Key: [SeamSignature.ScopeEnum.Key]]()
		for seamRoot in seamRoots.compactMap(\.self) {
			for scopeEnum in seamRoot.signature.scopeEnums where scopeEnum.key.seamType == seamRoot.signature.seamType {
				edges[scopeEnum.key] = scopeEnum.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:))
			}
		}
		let nodes = edges.keys.sorted { $0.spelling < $1.spelling }
		var componentByKey = [SeamSignature.ScopeEnum.Key: Int]()
		for (index, component) in stronglyConnectedComponents(of: nodes, edges: { edges[$0, default: []].filter { edges[$0] != nil } }).enumerated() {
			for key in component {
				componentByKey[key] = index
			}
		}
		return seamRoots.map { seamRoot in
			guard let seamRoot else { return nil }
			// The enums are marked in a copy, assigned once, since each assignment computes the signature's call shape again.
			var scopeEnums = seamRoot.signature.scopeEnums
			for enumIndex in scopeEnums.indices {
				let declaringKey = scopeEnums[enumIndex].key
				for caseIndex in scopeEnums[enumIndex].cases.indices {
					guard let component = componentByKey[declaringKey] else { continue }
					if case let .nested(innerKey, _) = scopeEnums[enumIndex].cases[caseIndex].kind, componentByKey[innerKey] == component {
						scopeEnums[enumIndex].cases[caseIndex].kind = .nested(enumKey: innerKey, isIndirect: true)
					} else if case let .inner(innerKey, enumType, sitePath, _) = scopeEnums[enumIndex].cases[caseIndex].kind, componentByKey[innerKey] == component {
						scopeEnums[enumIndex].cases[caseIndex].kind = .inner(enumKey: innerKey, enumType: enumType, sitePath: sitePath, isIndirect: true)
					}
				}
			}
			var signature = seamRoot.signature
			signature.scopeEnums = scopeEnums
			return ScopeGenerator.SeamRoot(signature: signature, unreadTypeComment: seamRoot.unreadTypeComment)
		}
	}
}

extension SeamSignature.Hole {
	/// A place's case name, unspelled: the labels of its path, joined by `_`.
	static func caseName(of sitePath: [Property]) -> String {
		sitePath.map(\.label.spelledWithoutBackticks).joined(separator: "_")
	}
}

extension SeamSignature.Hole.Site {
	/// A spelling that orders sites.
	var sortKey: String {
		"\(seamType.asSource) \(path.map(\.asSource).joined(separator: " "))"
	}
}
