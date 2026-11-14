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
/// claims its builders' internal names with their stage bindings, then the functions that build its wrapper places; a
/// filler's body claims its fills with their later stages, then its dispatchers; a mock's scope claims each function's
/// locals in the order the mock's body walk reads the overrides (`ScopeGenerator.SendableOverrideExtractor`).
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
	}

	/// What the scope types a seam or a public mock declares for its builders are named by, and how its builders spell them.
	struct ScopeTypeNames {
		/// The prefix of a plain enum's name.
		let plain: String
		/// The prefix of a `@Sendable` enum's name.
		let sendable: String
		/// The prefix of a staged place's scope type's name.
		let staged: String
		/// Whether a builder spells its own scope types qualified by the type that declares them: a public mock's builder
		/// is spelled once for its own signature and for each module that calls it, as an internal mock's parameter.
		let areQualified: Bool

		/// A seam's: `SafeDIScope_`, `SafeDISendableScope_` and `SafeDIStagedScope_`, spelled inside its extension.
		static let seam = ScopeTypeNames(plain: "SafeDIScope", sendable: "SafeDISendableScope", staged: "SafeDIStagedScope", areQualified: false)
		/// A public mock's: `SafeDIMockScope_`, `SafeDISendableMockScope_` and `SafeDIStagedMockScope_`, apart from the seam's
		/// a mocked seam declares beside them.
		static let publicMock = ScopeTypeNames(plain: "SafeDIMockScope", sendable: "SafeDISendableMockScope", staged: "SafeDIStagedMockScope", areQualified: true)
	}

	/// Shapes `holes`, every place of `seam`'s tree `generator` the seam's initializer must take a builder for, into builders.
	///
	/// A place the seam builds in plain code is a case of its hole type's plain enum. A call of an inner seam, or of another
	/// module's public mock, that passes up a place its enum reaches is a case holding that enum: of the plain enum when the
	/// call is in plain code and the inner enum plain, and of the `@Sendable` enum otherwise. A place the seam builds inside
	/// a `@Sendable` function, and a staged place of an inner seam, has a builder of its own. An enum exists only if it has a
	/// case. A seam's caller fills or passes up per instantiated type, so every place one of its enums reaches is filled or
	/// none is; a public mock's caller decides per place.
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

		// The enums' cases in the order the seam's generated code first reaches them.
		struct DraftCase {
			let rawName: String
			let disambiguatingType: TypeDescription
			let kind: SeamSignature.ScopeEnum.Case.Kind
		}
		var draftCasesByKey = [SeamSignature.ScopeEnum.Key: [DraftCase]]()
		var enumKeysInReachOrder = [SeamSignature.ScopeEnum.Key]()
		func appendCase(_ draftCase: DraftCase, to key: SeamSignature.ScopeEnum.Key) {
			if draftCasesByKey[key] == nil {
				enumKeysInReachOrder.append(key)
			}
			draftCasesByKey[key, default: []].append(draftCase)
		}
		var innerAccessByEnum = [SeamSignature.ScopeEnum.Key: [(level: AccessLevel, cause: TypeAccessProof.Cause?, seam: TypeDescription)]]()
		// An enum the builders reach: from the signature of the seam that declares it, where this module computes that seam,
		// else from the call of another module's seam, whose signature carries every enum it reaches as that module settled
		// them. A copy a seam of this module carries can be from an earlier pass.
		var calledSeamsEnums = [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]()
		func reachedEnum(_ key: SeamSignature.ScopeEnum.Key) -> SeamSignature.ScopeEnum? {
			ownScopeEnums[key] ?? calledSeamsEnums[key]
		}
		var stagedHoleSites = [SeamSignature.Hole.Site]()
		for reached in placesAndCalls(in: generator) {
			switch reached {
			case let .place(sitePath):
				let site = SeamSignature.Hole.Site(seamType: seamType, path: sitePath)
				guard let hole = holesBySite[site] else { continue }
				holesBySite[site]?.placeCaseName = SeamSignature.Hole.caseName(of: sitePath)
				if hole.stages.count == 1 {
					appendCase(DraftCase(rawName: SeamSignature.Hole.caseName(of: sitePath), disambiguatingType: hole.ownerType, kind: .own(site: site)), to: .init(seamType: seamType, holeType: hole.holeType, isSendable: false))
				} else {
					stagedHoleSites.append(site)
				}
			case let .call(sitePath, call, isInSendableFunction):
				guard let calledBuilders = call.calledBuilders else { continue }
				for scopeEnum in calledBuilders.scopeEnums where calledSeamsEnums[scopeEnum.key] == nil {
					calledSeamsEnums[scopeEnum.key] = scopeEnum
				}
				// The call hands up an enum that reaches a place it passes up.
				let passedUpSites = Set(call.passedUpHoles.map(\.site))
				let calledEnumsByKey = calledBuilders.enumsByKey
				for builder in calledBuilders.builders {
					guard case let .scopeEnum(innerKey) = builder.kind,
					      !SeamSignature.ScopeEnum.sitesReached(from: innerKey, in: calledEnumsByKey).isDisjoint(with: passedUpSites),
					      let innerEnum = reachedEnum(innerKey)
					else { continue }
					let innerEnumType = innerEnum.type
					let rawName = SeamSignature.Hole.caseName(of: sitePath) + (innerKey.isSendable ? "_Sendable" : "")
					let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: innerKey.holeType, isSendable: innerKey.isSendable || isInSendableFunction)
					appendCase(DraftCase(rawName: rawName, disambiguatingType: innerKey.seamType, kind: .inner(enumKey: innerKey, enumType: innerEnumType, sitePath: sitePath, isIndirect: false)), to: key)
					// The enum is as visible as the inner seam whose enum it holds, and the builder that takes that enum.
					let innerSeamAccess = proof.access(ofParameterTyped: innerKey.seamType, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, instantiables[innerKey.seamType]?.moduleName]))
					innerAccessByEnum[key, default: []].append((min(innerSeamAccess.level, builder.tierAccess), builder.accessCause ?? innerSeamAccess.cause, innerKey.seamType))
				}
			}
		}
		// A staged place an inner seam holds has a builder of its own, in the order the flat list holds them.
		for hole in flatHoles where hole.innerSeamType != nil && hole.stages.count > 1 {
			stagedHoleSites.append(hole.site)
		}

		// The stem of each hole type, from its instantiated type, named apart.
		let holeTypes = Array(Set(enumKeysInReachOrder.map(\.holeType) + stagedHoleSites.compactMap { holesBySite[$0]?.holeType }))
			.sorted { ($0.instantiatedType.asSource, $0.builtType.asSource) < ($1.instantiatedType.asSource, $1.builtType.asSource) }
		// Each tier's labels, widest first: the widest tier's stems also name the enums and order the builders.
		let tierNames = Self.tierNames(
			of: holeTypes,
			parameters: parameters.map { (label: $0.property.label, access: $0.tierAccess) } + otherParameters,
			widestTier: seamTypeAccess,
		)
		let stemByHoleType = tierNames[0].stemByHoleType
		func plainLabel(of holeType: SeamSignature.HoleType, in names: TierNames) -> String {
			Self.plainBuilderLabel(ofStem: names.stemByHoleType[holeType, default: ""])
		}
		func sendableLabel(of holeType: SeamSignature.HoleType, in names: TierNames) -> String {
			Self.sendableBuilderLabel(ofStem: names.stemByHoleType[holeType, default: ""])
		}
		func plainLabel(of holeType: SeamSignature.HoleType) -> String {
			plainLabel(of: holeType, in: tierNames[0])
		}
		func sendableLabel(of holeType: SeamSignature.HoleType) -> String {
			sendableLabel(of: holeType, in: tierNames[0])
		}
		/// The labels the narrower tiers take a builder under where they differ from the widest tier's.
		func narrowerTierLabels(_ label: (TierNames) -> String) -> [AccessLevel: String] {
			var labels = [AccessLevel: String]()
			let widestLabel = label(tierNames[0])
			for names in tierNames.dropFirst() where label(names) != widestLabel {
				labels[names.tier] = label(names)
			}
			return labels
		}

		// Builder order: per hole type in label order, then plain, `@Sendable`, staged.
		let orderedHoleTypes = holeTypes.sorted { plainLabel(of: $0) < plainLabel(of: $1) }
		var takenLabelsByTier = tierNames.map { names in
			var takenLabels = names.parameterLabels
			for holeType in orderedHoleTypes {
				takenLabels.insert(plainLabel(of: holeType, in: names))
				takenLabels.insert(sendableLabel(of: holeType, in: names))
			}
			return takenLabels
		}
		var takenStagedScopeTypeNames = Set<String>()
		struct StagedDraft {
			let site: SeamSignature.Hole.Site
			let label: String
			let narrowerTierLabels: [AccessLevel: String]
		}
		var stagedDraftsByHoleType = [SeamSignature.HoleType: [StagedDraft]]()
		for site in stagedHoleSites {
			guard let hole = holesBySite[site] else { continue }
			let holeType = hole.holeType
			let stem = stemByHoleType[holeType, default: ""]
			let isOwnPlace = hole.innerSeamType == nil
			let caseName = isOwnPlace ? SeamSignature.Hole.caseName(of: hole.sitePath) : hole.placeCaseName
			// Each tier's label, named apart from what that tier takes.
			let labels = tierNames.indices.map { tierIndex in
				let plainLabel = plainLabel(of: holeType, in: tierNames[tierIndex])
				var label = (isOwnPlace ? "\(plainLabel)_\(caseName)" : "\(plainLabel)_\(Self.seamStem(of: hole.scopeSeamType))_\(caseName)").spelledAsIdentifier
				while !takenLabelsByTier[tierIndex].insert(label).inserted {
					label = "\(label)_".spelledAsJoinedIdentifier
				}
				return label
			}
			let label = labels[0]
			var narrowerTierLabels = [AccessLevel: String]()
			for tierIndex in tierNames.indices.dropFirst() where labels[tierIndex] != label {
				narrowerTierLabels[tierNames[tierIndex].tier] = labels[tierIndex]
			}
			holesBySite[site]?.builderLabel = label
			holesBySite[site]?.narrowerTierBuilderLabels = narrowerTierLabels
			if isOwnPlace {
				var scopeTypeName = "\(scopeTypeNames.staged)_\(stem)_\(caseName)".spelledAsIdentifier
				while !takenStagedScopeTypeNames.insert(scopeTypeName).inserted {
					scopeTypeName = "\(scopeTypeName)_".spelledAsJoinedIdentifier
				}
				holesBySite[site]?.scopeTypeName = scopeTypeName
			}
			stagedDraftsByHoleType[holeType, default: []].append(StagedDraft(site: site, label: label, narrowerTierLabels: narrowerTierLabels))
		}

		// The names the initializer's body declares for its builders, in a fixed order. Every other name of the tree is
		// claimed first: a builder function of a property the tree builds, and a deferred parameter's closure.
		let namesDeclaredBeforeTheBuilders = treeFunctionNames.union(parameters.filter(\.isDeferred).map(\.internalName))
		var names = GeneratedNameAllocator(reserving: namesDeclaredBeforeTheBuilders)
		// The own enums and their names.
		var ownEnums = [SeamSignature.ScopeEnum]()
		var builders = [SeamSignature.Builder]()
		var internalNameByPlainHoleType = [SeamSignature.HoleType: String]()
		for holeType in orderedHoleTypes {
			let stem = stemByHoleType[holeType, default: ""]
			for isSendable in [false, true] {
				let key = SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: isSendable)
				guard let draftCases = draftCasesByKey[key] else { continue }
				let label = isSendable ? sendableLabel(of: holeType) : plainLabel(of: holeType)
				let builderNarrowerTierLabels = narrowerTierLabels { isSendable ? sendableLabel(of: holeType, in: $0) : plainLabel(of: holeType, in: $0) }
				let internalName = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: label))
				if !isSendable {
					internalNameByPlainHoleType[holeType] = internalName
				}
				let typeName = "\(isSendable ? scopeTypeNames.sendable : scopeTypeNames.plain)_\(stem)".spelledAsIdentifier
				// Two cases of one name are both named apart.
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
				// A payload struct's name is taken from the case; a type a field spells must not resolve to the struct.
				var takenStructNames = Set(caseNames)
				for draftCase in draftCases {
					switch draftCase.kind {
					case let .own(site):
						for field in holesBySite[site].map({ Array($0.stages.joined()) }) ?? [] {
							takenStructNames.formUnion(TypeAccessProof.mentionedTypes(in: field.property.typeDescription).compactMap(\.outermostTypeName))
						}
						if let forwardedType = holesBySite[site]?.forwardedType {
							takenStructNames.formUnion(TypeAccessProof.mentionedTypes(in: forwardedType).compactMap(\.outermostTypeName))
						}
					case let .inner(_, enumType, _, _):
						takenStructNames.formUnion(TypeAccessProof.mentionedTypes(in: enumType).compactMap(\.outermostTypeName))
					}
				}
				var cases = [SeamSignature.ScopeEnum.Case]()
				for (draftCase, caseName) in zip(draftCases, caseNames) {
					cases.append(SeamSignature.ScopeEnum.Case(name: caseName, kind: draftCase.kind))
					guard case let .own(site) = draftCase.kind else { continue }
					var valuesTypeName = "\(caseName)_Values".spelledAsJoinedIdentifier
					while !takenStructNames.insert(valuesTypeName).inserted {
						valuesTypeName = "\(valuesTypeName)_".spelledAsJoinedIdentifier
					}
					holesBySite[site]?.enumPlace = SeamSignature.Hole.EnumPlace(enumTypeName: typeName, caseName: caseName, valuesTypeName: valuesTypeName)
					holesBySite[site]?.scopeTypeName = typeName
				}
				ownEnums.append(SeamSignature.ScopeEnum(key: key, typeName: typeName, builderLabel: label, cases: cases))
				// The builder is as visible as the narrowest place it builds, and each inner seam it carries an enum of, capped
				// at the seam.
				var narrowest: (level: AccessLevel, cause: TypeAccessProof.Cause?, seam: TypeDescription?) = (seamTypeAccess, nil, nil)
				for draftCase in draftCases {
					if case let .own(site) = draftCase.kind, let hole = holesBySite[site], hole.tierAccess < narrowest.level {
						narrowest = (hole.tierAccess, hole.accessCause, nil)
					}
				}
				for inner in innerAccessByEnum[key, default: []] where min(inner.level, seamTypeAccess) < narrowest.level {
					narrowest = (min(inner.level, seamTypeAccess), inner.cause, inner.seam)
				}
				let enumType: TypeDescription = scopeTypeNames.areQualified ? .nested(name: typeName, parentType: seamType, generics: []) : .simple(name: typeName, generics: [])
				let parameterType = Self.builderParameterType(takingEnum: enumType, returning: returnType(of: holeType, in: flatHoles), isSendable: isSendable)
				builders.append(SeamSignature.Builder(
					kind: .scopeEnum(key),
					label: label,
					internalName: internalName,
					parameterType: parameterType,
					parameterTypeWithoutAny: parameterType.withoutAny,
					tierAccess: narrowest.level,
					accessCause: narrowest.cause,
					narrowingInnerSeam: narrowest.seam,
					narrowerTierLabels: builderNarrowerTierLabels,
				))
			}
			for staged in stagedDraftsByHoleType[holeType, default: []].sorted(by: { $0.label < $1.label }) {
				guard var hole = holesBySite[staged.site] else { continue }
				let internalName = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: staged.label), occupying: { name in
					hole.stages.indices.map { hole.stageFunctionName(at: $0, ofFunctionNamed: name) }
				})
				hole.internalName = internalName
				holesBySite[staged.site] = hole
				let qualifiedBy = hole.innerSeamType == nil && !scopeTypeNames.areQualified ? nil : hole.scopeSeamType
				builders.append(SeamSignature.Builder(
					kind: .staged(site: staged.site),
					label: staged.label,
					internalName: internalName,
					parameterType: hole.builderType(qualifiedBy: qualifiedBy),
					parameterTypeWithoutAny: hole.builderTypeWithoutAny(qualifiedBy: qualifiedBy),
					tierAccess: hole.tierAccess,
					accessCause: hole.accessCause,
					narrowingInnerSeam: nil,
					narrowerTierLabels: staged.narrowerTierLabels,
				))
			}
		}
		// Every place carries its plain builder's names, a fill's among them.
		for site in holesBySite.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
			guard let hole = holesBySite[site], hole.stages.count == 1 else { continue }
			holesBySite[site]?.builderLabel = plainLabel(of: hole.holeType)
			holesBySite[site]?.narrowerTierBuilderLabels = narrowerTierLabels { plainLabel(of: hole.holeType, in: $0) }
			holesBySite[site]?.internalName = internalNameByPlainHoleType[hole.holeType] ?? ScopeGenerator.functionName(toBuildPropertyNamed: plainLabel(of: hole.holeType))
		}
		// The functions that build the wrapper places come after the builders and their stages. Two places in separate scopes of
		// the tree may share a function name, since neither function is in scope where the other is declared; none may equal
		// a builder or a stage binding, which is in scope throughout the body.
		let namesOfBuildersAndStages = names.taken.subtracting(namesDeclaredBeforeTheBuilders)
		for site in holesBySite.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
			guard let hole = holesBySite[site], hole.innerSeamType == nil, !hole.property.propertyType.isConstant else { continue }
			var name = ScopeGenerator.functionName(toBuildPropertyNamed: hole.property.label)
			while namesOfBuildersAndStages.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			holesBySite[site]?.wrapperFunctionName = name
		}

		// This seam's enums first, then every enum their cases reach, each once, breadth first: only those, so a place that
		// a seam this one calls fills, which no builder of this one reaches, changes nothing a caller of this one passes.
		var seenKeys = Set(ownEnums.map(\.key))
		var scopeEnums = ownEnums
		var nextEnumIndex = 0
		while nextEnumIndex < scopeEnums.count {
			for enumCase in scopeEnums[nextEnumIndex].cases {
				guard case let .inner(innerKey, _, _, _) = enumCase.kind, seenKeys.insert(innerKey).inserted, let innerEnum = reachedEnum(innerKey) else { continue }
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
			switch builder.kind {
			case let .staged(site):
				if seenSites.insert(site).inserted, let hole = holesBySite[site] {
					orderedHoles.append(hole)
					builderBySite[site] = builder
				}
			case let .scopeEnum(rootKey):
				var keysToVisit = [rootKey]
				while let key = keysToVisit.popLast() {
					guard visitedEnums.insert(key).inserted, let scopeEnum = enumsByKey[key] else { continue }
					var innerKeys = [SeamSignature.ScopeEnum.Key]()
					for enumCase in scopeEnum.cases {
						switch enumCase.kind {
						case let .own(site):
							if seenSites.insert(site).inserted, let hole = holesBySite[site] {
								orderedHoles.append(hole)
								builderBySite[site] = builder
							}
						case let .inner(innerKey, _, _, _):
							innerKeys.append(innerKey)
						}
					}
					keysToVisit.append(contentsOf: innerKeys.reversed())
				}
			}
		}
		return ShapedBuilders(holes: orderedHoles, builders: builders, scopeEnums: scopeEnums, builderBySite: builderBySite)
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

	/// The identifier a seam is named by inside a staged builder's label and a fill's name.
	static func seamStem(of seamType: TypeDescription) -> String {
		seamType.spelledCanonically.simplified.asIdentifier.spelledWithoutBackticks
	}

	// MARK: Private

	private enum PlaceOrCall {
		case place(sitePath: [Property])
		case call(sitePath: [Property], generator: ScopeGenerator, isInSendableFunction: Bool)
	}

	/// Every place and every call that passes a builder up in the tree `generator` roots, in the order the generated code
	/// reaches them: a seam call's fills are declared before the call.
	private static func placesAndCalls(in generator: ScopeGenerator) -> [PlaceOrCall] {
		struct Frame {
			let generator: ScopeGenerator
			let orderedChildren: [ScopeGenerator.OrderedChild]
			var nextPosition: Int
			let path: [Property]
			let isInSendableFunction: Bool
		}
		var reached = [PlaceOrCall]()
		var frames = [Frame(generator: generator, orderedChildren: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []), nextPosition: 0, path: [], isInSendableFunction: false)]
		while let frame = frames.last {
			guard frame.nextPosition < frame.orderedChildren.count else {
				frames.removeLast()
				if !frame.generator.passedUpHoles.isEmpty {
					reached.append(.call(sitePath: frame.path, generator: frame.generator, isInSendableFunction: frame.isInSendableFunction))
				}
				continue
			}
			frames[frames.count - 1].nextPosition += 1
			let child = frame.orderedChildren[frame.nextPosition]
			if let holeSite = child.generator.holeSite {
				reached.append(.place(sitePath: frame.path + [holeSite.property]))
			} else if child.generator.containsBuildSite || child.generator.passesUpBuilder {
				frames.append(Frame(
					generator: child.generator,
					orderedChildren: child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: child.propertiesGeneratedLater),
					nextPosition: 0,
					path: frame.path + (child.generator.fillHole?.pathBeforePropertyInItsFill ?? child.generator.property.map { [$0] } ?? []),
					isInSendableFunction: frame.isInSendableFunction || child.generator.buildsInSendableFunction || frame.generator.buildsInSendableFunction(ofFill: child.generator),
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
				edges[scopeEnum.key] = scopeEnum.cases.compactMap { enumCase in
					if case let .inner(enumKey, _, _, _) = enumCase.kind {
						enumKey
					} else {
						nil
					}
				}
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
					if case let .inner(innerKey, enumType, sitePath, _) = scopeEnums[enumIndex].cases[caseIndex].kind, let component = componentByKey[declaringKey], componentByKey[innerKey] == component {
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
