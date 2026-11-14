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

// MARK: - A seam's or a public mock's enums, nested by type

extension DependencyTreeGenerator {
	/// A place, or a call of an inner seam or another module's public mock that passes a place up, in a seam's tree or in a
	/// public mock's outside every fill, with the cases on its path.
	struct ReachedPlace {
		/// The properties from the seam's root to the place's property, or to the call's: inside a fill, the filled place's
		/// path in the inner seam's tree comes between the call and what the fill builds (`Hole.pathBeforePropertyInItsFill`).
		let sitePath: [Property]
		/// Each property on the path that a case stands for, outermost first, ending with the place's or the call's: every
		/// property but those of the filled places' paths and the properties the fills build, whose cases are the calls'.
		let steps: [ReachedStep]
		/// The call's generator, or `nil` for a place.
		let call: ScopeGenerator?
	}

	/// A property on the path to a place or a call, which a case of the seam's enums stands for.
	struct ReachedStep {
		/// The type that declares the property: the seam's, or the type the property of the step before builds, or the type
		/// the fill of the step before builds.
		let type: TypeDescription
		let property: Property
		/// How many properties of the path, this one's included, lead to the scope that builds this one: the path the seam's
		/// tree binds the case's payload at, just before building the property.
		let pathLength: Int
		/// Whether the property is built in a `@Sendable` function of its own: a builder function that is `@Sendable`, a place
		/// held in a `Sendable` wrapper, a call made in such a builder function, or, for a call whose fill leads on, a
		/// `@Sendable` fill.
		let buildsInSendableFunction: Bool
		/// For a call whose fill leads on, the builder the fill is passed for: the step's case is the call's case for that
		/// builder, which holds the enum of the type the fill builds.
		let filledBuilder: SeamDeclarationGraph.FilledBuilder?
	}

	/// A seam's enums of one hole type, nested by type, and what its tree reads of them.
	struct ScopeEnumsByType {
		/// The plain root enum, then each enum nested in it, then the `@Sendable` root enum, then each enum nested in it: each
		/// family's nested enums in the order the roots' cases first lead to their described types, breadth first, the plain
		/// root's before the `@Sendable` root's, each enum's cases in its type's declaration order – an order no type's name
		/// decides. The plain root is declared, with no case of its own, where only the `@Sendable` enum's cases lead to plain
		/// enums; a root with no case of its own takes no builder.
		var enums = [SeamSignature.ScopeEnum]()
		/// Where the enums carry each place: its case, and the cases that lead to it.
		var enumPlaceBySite = [SeamSignature.Hole.Site: SeamSignature.Hole.EnumPlace]()
		/// How the seam's tree hands each call's inner enum up.
		var callRoutes = [SeamSignature.CallRoute]()
		/// The payloads the seam's tree binds, each before building the last property of its path.
		var valuesBindingKeys = Set<ValuesBindingKey>()

		/// The root enum of the family `isSendable` says, if the seam declares it.
		func rootEnum(isSendable: Bool) -> SeamSignature.ScopeEnum? {
			enums.first { $0.rootTypeName == nil && $0.key.isSendable == isSendable }
		}
	}

	/// The enums of `holeType` that the builders of `seam` are handed, nested by type.
	///
	/// The cases are a fact of the seam's graph of declarations (`SeamDeclarationGraph`), never of its paths. A type has a plain
	/// enum when one of its declarations reaches a place of the hole type in plain code, after the edges that close a cycle on
	/// every build are removed, with a case for each of its properties that holds such a place, in its declaration order. A
	/// type has a `@Sendable` enum when one of its declarations reaches a place built inside a `@Sendable` function: its case
	/// `p` holds the plain enum of the type `p`'s own `@Sendable` builder function builds, or is a place held in a `Sendable`
	/// wrapper; its case `p_Sendable` holds the `@Sendable` enum of the type `p` builds. A call of an inner seam whose enum
	/// reaches a place the call passes up holds a place: its plain enum in the family the call is made in, its `@Sendable` enum
	/// in the `@Sendable` family. A call one of whose builders the seam's tree fills with a type whose tree leads to a place
	/// has a case per such builder after its own, `<call>_<builder>`, which holds the scope value the inner seam handed the
	/// fill and the enum of the type the fill builds, nested by type as any type of the tree: a place inside a fill is a place
	/// of that type. A place the inner seam passes up from a seam it calls has a case per such seam, `<call>_<builder>_<Seam>`,
	/// holding that seam's scope value; fills that differ in whether they carry the scope value take a case each. A case of the plain family carries what its type binds before the property, read from a build of the
	/// type, every build of a type binding the same values in the same order; a case of the `@Sendable` family carries none,
	/// since a place is handed only what the innermost `@Sendable` function that builds it binds, which is why a call's case
	/// that leads to a `@Sendable` function inside the fill carries no inner scope.
	/// - Parameters:
	///   - reached: The places of the hole type, and the calls that pass one up, in the order the seam's generated code
	///     reaches them.
	///   - takenTypeNames: The names every generated type nested in a root enum must not take beside those its own cases spell:
	///     the names the root's other cases – cases per path, of a place inside a public mock's fill – declare or spell, in
	///     their fields, forwarded values and inner enums.
	///   - bindsReceivesAgain: Whether the tree is a public mock's, whose types' levels hold the receives it binds again
	///     (`receivesBoundAgainOfAnyBuild(inTreeRootedAt:)`).
	static func scopeEnumsByType(
		of seam: Instantiable,
		holeType: SeamSignature.HoleType,
		rootTypeNames: (plain: String, sendable: String),
		builderLabels: (plain: String, sendable: String),
		generator: ScopeGenerator,
		reached: [ReachedPlace],
		takenTypeNames externallyTakenTypeNames: Set<String>,
		holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole],
		parameters: [SeamSignature.Parameter],
		bindsReceivesAgain: Bool,
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
		reachedEnum: (SeamSignature.ScopeEnum.Key) -> SeamSignature.ScopeEnum?,
		entersFills: Bool = true,
	) -> ScopeEnumsByType {
		let seamType = seam.concreteInstantiable
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		// The hole type of each place, by its owner and property: every site of one declaration builds one hole type.
		var holeTypeByOwnedProperty = [SeamDeclarationGraph.TypeAndProperty: SeamSignature.HoleType]()
		for hole in holesBySite.values where hole.innerSeamType == nil {
			holeTypeByOwnedProperty[SeamDeclarationGraph.TypeAndProperty(type: hole.ownerType, property: hole.property)] = hole.holeType
		}
		// The inner enum of the hole type, of the family `isSendable` says, a call hands up, by the call's generator.
		func innerKey(handedUpBy call: ScopeGenerator, isSendable: Bool) -> SeamSignature.ScopeEnum.Key? {
			guard let calledBuilders = call.calledBuilders else { return nil }
			let passedUpSites = Set(call.passedUpHoles.map(\.site))
			let calledEnumsByKey = calledBuilders.enumsByKey
			for builder in calledBuilders.builders {
				let innerKey = builder.enumKey
				guard innerKey.isSendable == isSendable,
				      innerKey.holeType == holeType,
				      !SeamSignature.ScopeEnum.sitesReached(from: innerKey, in: calledEnumsByKey).isDisjoint(with: passedUpSites)
				else { continue }
				return innerKey
			}
			return nil
		}
		// The graph: a place of the hole type is a site of it, or a call that hands up an inner enum of it. A fill is left out
		// with what it builds. A call's case carries what its type binds before the call for a builder a person writes: no
		// generated fill reads it, since the inner seam's root dispatcher takes no parameters, and a fill that would read
		// what this seam binds before the call is `boundByPassingUpSeam`, by ruling for 2.3.0. Nor is the call a carrier in
		// the start order (`SeamDeclarationGraph`).
		// A call's fill is entered where it is the fill whose code is generated and builds a place or a call that passes one
		// up: an edge from the call's declaration to the type the fill builds.
		let placeHolding = SeamDeclarationGraph.placeHolding(inTreeRootedAt: generator, edges: { parent, child in
			if child.fillHole != nil {
				return []
			} else if let site = child.holeSite {
				guard let owner = parent.builtInstantiable?.concreteInstantiable,
				      holeTypeByOwnedProperty[SeamDeclarationGraph.TypeAndProperty(type: owner, property: site.property)] == holeType
				else { return [] }
				return [site.property.propertyType.isSendable ? .sendablePlace : .plainPlace]
			} else if !child.passedUpHoles.isEmpty, innerKey(handedUpBy: child, isSendable: false) != nil || innerKey(handedUpBy: child, isSendable: true) != nil {
				var edges = [SeamDeclarationGraph.PlaceEdge]()
				if innerKey(handedUpBy: child, isSendable: false) != nil {
					edges.append(child.buildsInSendableFunction ? .sendablePlace : .plainPlace)
				}
				if innerKey(handedUpBy: child, isSendable: true) != nil {
					edges.append(.sendableBeneathPlace)
				}
				return edges
			} else {
				return [.declaration(inSendableFunction: child.buildsInSendableFunction)]
			}
		}, fillEdges: { _, call in
			// A public mock's places inside a fill keep a case per path: no fill of its own enters its enums.
			guard entersFills else { return [] }
			return call.children.compactMap { fill in
				guard fill.fillEmitsCode,
				      fill.containsBuildSite || fill.passesUpBuilder,
				      let fulfiller = fill.children.first,
				      let innerKey = Self.filledRootKey(of: fill)
				else { return nil }
				let inSendableFunction = call.buildsInSendableFunction || call.buildsInSendableFunction(ofFill: fill) || fulfiller.buildsInSendableFunction
				return (SeamDeclarationGraph.FillEdge(innerKey: innerKey, inSendableFunction: inSendableFunction, fulfillerBuildsInSendableFunction: fulfiller.buildsInSendableFunction), fulfiller)
			}
		})
		let cycleParametersOfAnyBuild = Self.cycleParametersOfAnyBuild(inTreeRootedAt: generator, entersFills: entersFills)
		let reboundPropertiesOfAnyBuild = Self.reboundPropertiesOfAnyBuild(inTreeRootedAt: generator, entersFills: entersFills)
		let receivesBoundAgainOfAnyBuild = bindsReceivesAgain ? Self.receivesBoundAgainOfAnyBuild(inTreeRootedAt: generator) : [:]

		// What each type with an enum binds, in its order, and the cases each family's enum has.
		struct DraftCase {
			let property: Property
			let kind: Kind
			/// What the type binds before the property, for a case of the plain family; `nil` for a case of the `@Sendable`
			/// family, which carries no values.
			let fields: [SeamSignature.Hole.Field]?
			/// The labels the type binds from the property on, for a case of the plain family (see
			/// `SeamSignature.ScopeEnum.Values.labelsBoundLater`).
			var labelsBoundLater = Set<String>()
			/// Whether the case is `<label>_Sendable`, holding the `@Sendable` enum of what the property builds or hands up.
			var isSendableBeneath = false

			enum Kind {
				case place
				case nested(TypeDescription, isSendable: Bool)
				case inner(SeamSignature.ScopeEnum.Key)
				/// A call's case for the builder `filledBuilder`, labeled `builderLabel`, which the seam's tree fills with
				/// `fulfiller`: its enum of the family `isSendable` says, after the inner scope where the builder carries it. For a
				/// place the called seam passes up from a seam it calls, `passingUpSeamStem` is the stem of the seam whose tree holds
				/// the place, whose root enum the case carries: a case for each such seam.
				case fill(_ filledBuilder: SeamDeclarationGraph.FilledBuilder, builderLabel: String, passingUpSeamStem: String?, fulfiller: TypeDescription, isSendable: Bool)
			}

			/// The builder of a call's case for a builder it fills, or `nil` for any other case.
			var filledBuilder: SeamDeclarationGraph.FilledBuilder? {
				if case let .fill(filledBuilder, _, _, _, _) = kind {
					filledBuilder
				} else {
					nil
				}
			}
		}
		var plainDraftCasesByType = [TypeDescription: [DraftCase]]()
		var sendableDraftCasesByType = [TypeDescription: [DraftCase]]()
		let typesWithCases = Set(placeHolding.plainCasePropertiesByType.keys)
			.union(placeHolding.sendableOwnCasePropertiesByType.keys)
			.union(placeHolding.sendableBeneathCasePropertiesByType.keys)
			.union(placeHolding.plainFillCasesByType.keys)
			.union(placeHolding.sendableOwnFillCasesByType.keys)
			.union(placeHolding.sendableBeneathFillCasesByType.keys)
		for type in typesWithCases {
			guard let build = placeHolding.firstBuildByType[type], let instantiable = build.builtInstantiable else { continue }
			let plainProperties = placeHolding.plainCasePropertiesByType[type, default: []]
			let sendableOwnProperties = placeHolding.sendableOwnCasePropertiesByType[type, default: []]
			let sendableBeneathProperties = placeHolding.sendableBeneathCasePropertiesByType[type, default: []]
			let plainFills = placeHolding.plainFillCasesByType[type, default: []]
			let sendableOwnFills = placeHolding.sendableOwnFillCasesByType[type, default: []]
			let sendableBeneathFills = placeHolding.sendableBeneathFillCasesByType[type, default: []]
			let declarations = plainProperties.isEmpty && plainFills.isEmpty ? [] : levelDeclarations(
				of: build,
				isSeamRoot: type == seamType,
				labelsNamedApart: bindsReceivesAgain && type == seamType ? build.labelsChildrenShare : [],
				cycleParameters: cycleParametersOfAnyBuild[type, default: []],
				reboundProperties: reboundPropertiesOfAnyBuild[type, default: []],
				receivesBoundAgain: receivesBoundAgainOfAnyBuild[type, default: []],
				seam: seam,
				parameters: parameters,
				seamTypeAccess: seamTypeAccess,
				proof: proof,
				instantiables: instantiables,
			)
			let childrenByProperty = Dictionary(build.children.compactMap { child in child.property.map { ($0, child) } }, uniquingKeysWith: { first, _ in first })
			var plainCases = [DraftCase]()
			var sendableCases = [DraftCase]()
			func builtType(of property: Property) -> TypeDescription? {
				placeHolding.builtTypeByTypeAndProperty[SeamDeclarationGraph.TypeAndProperty(type: type, property: property)]
			}
			// In the type's declaration order.
			for dependency in instantiable.dependencies {
				let property = dependency.property
				guard let child = childrenByProperty[property] else { continue }
				let isCall = child.holeSite == nil && !child.passedUpHoles.isEmpty
				if plainProperties.contains(property) {
					let position = declarations.firstIndex { $0.property == property } ?? declarations.count
					// A member of the property's loop of builders (`ScopeGenerator.ReceivedBuilderLoops`) is still being built where
					// the loop's payloads are bound, before the loop's first function: the property's own function wraps again what
					// its tree receives of it. It is bound later than the payload, as the declarations after the property are.
					var fields = [SeamSignature.Hole.Field]()
					var labelsBoundLater = Set(declarations[position...].map(\.property.label) + [property.label])
					for field in declarations[..<position] {
						if let fieldChild = childrenByProperty[field.property], build.areMembersOfOneLoop(fieldChild, child) {
							labelsBoundLater.insert(field.property.label)
						} else {
							fields.append(field)
						}
					}
					if child.holeSite != nil {
						plainCases.append(DraftCase(property: property, kind: .place, fields: fields, labelsBoundLater: labelsBoundLater))
					} else if isCall, let innerKey = innerKey(handedUpBy: child, isSendable: false) {
						plainCases.append(DraftCase(property: property, kind: .inner(innerKey), fields: fields, labelsBoundLater: labelsBoundLater))
					} else if !isCall, let builtType = builtType(of: property) {
						plainCases.append(DraftCase(property: property, kind: .nested(builtType, isSendable: false), fields: fields, labelsBoundLater: labelsBoundLater))
					}
				}
				if sendableOwnProperties.contains(property) {
					if child.holeSite != nil {
						sendableCases.append(DraftCase(property: property, kind: .place, fields: nil))
					} else if isCall, let innerKey = innerKey(handedUpBy: child, isSendable: false) {
						sendableCases.append(DraftCase(property: property, kind: .inner(innerKey), fields: nil))
					} else if !isCall, let builtType = builtType(of: property) {
						sendableCases.append(DraftCase(property: property, kind: .nested(builtType, isSendable: false), fields: nil))
					}
				}
				if sendableBeneathProperties.contains(property) {
					if isCall, let innerKey = innerKey(handedUpBy: child, isSendable: true) {
						sendableCases.append(DraftCase(property: property, kind: .inner(innerKey), fields: nil, isSendableBeneath: true))
					} else if !isCall, let builtType = builtType(of: property) {
						sendableCases.append(DraftCase(property: property, kind: .nested(builtType, isSendable: true), fields: nil, isSendableBeneath: true))
					}
				}
				// A call's case for each builder it fills with a type whose tree leads to a place, after the call's own, in the
				// order the call takes its builders.
				guard !plainFills.isEmpty || !sendableOwnFills.isEmpty || !sendableBeneathFills.isEmpty, let calledBuilders = child.calledBuilders else { continue }
				// A builder whose fills differ in whether a place inside them carries the inner scope has a case for each, the one
				// that carries it first: the inner scope is bound in the fill, outside a builder function of the fulfiller's own that
				// is `@Sendable`.
				for (innerKey, builderLabel) in Self.rootEnumKeys(of: calledBuilders) {
					// The case of a place a seam the called seam calls passes up is named after the seam whose tree holds it, never
					// after where that seam's call is among the called seam's properties.
					let passingUpSeamStem = innerKey.seamType == child.builtInstantiable?.concreteInstantiable ? nil : DependencyTreeGenerator.seamStem(of: innerKey.seamType)
					for carriesInnerScope in [true, false] {
						let filledBuilder = SeamDeclarationGraph.FilledBuilder(innerKey: innerKey, carriesInnerScope: carriesInnerScope)
						let fillCase = SeamDeclarationGraph.FillCase(property: property, filledBuilder: filledBuilder)
						guard let fulfiller = placeHolding.fulfillerTypeByTypeAndFillCase[SeamDeclarationGraph.TypeAndFillCase(type: type, fillCase: fillCase)] else { continue }
						if plainFills.contains(fillCase) {
							let position = declarations.firstIndex { $0.property == property } ?? declarations.count
							plainCases.append(DraftCase(property: property, kind: .fill(filledBuilder, builderLabel: builderLabel, passingUpSeamStem: passingUpSeamStem, fulfiller: fulfiller, isSendable: false), fields: Array(declarations[..<position])))
						}
						if sendableOwnFills.contains(fillCase) {
							sendableCases.append(DraftCase(property: property, kind: .fill(filledBuilder, builderLabel: builderLabel, passingUpSeamStem: passingUpSeamStem, fulfiller: fulfiller, isSendable: false), fields: nil))
						}
						if sendableBeneathFills.contains(fillCase) {
							sendableCases.append(DraftCase(property: property, kind: .fill(filledBuilder, builderLabel: builderLabel, passingUpSeamStem: passingUpSeamStem, fulfiller: fulfiller, isSendable: true), fields: nil, isSendableBeneath: true))
						}
					}
				}
			}
			if !plainCases.isEmpty {
				plainDraftCasesByType[type] = plainCases
			}
			if !sendableCases.isEmpty {
				sendableDraftCasesByType[type] = sendableCases
			}
		}
		func draftCases(of type: TypeDescription, isSendable: Bool) -> [DraftCase] {
			(isSendable ? sendableDraftCasesByType : plainDraftCasesByType)[type, default: []]
		}

		// Only the enums the roots' cases lead to are declared: breadth first from the plain root, then the `@Sendable` root.
		struct Described: Hashable {
			let type: TypeDescription
			let isSendable: Bool
		}
		var described = [Described]()
		for isSendable in [false, true] where !draftCases(of: seamType, isSendable: isSendable).isEmpty {
			described.append(Described(type: seamType, isSendable: isSendable))
		}
		var describedSet = Set(described)
		var nextDescribedIndex = 0
		while nextDescribedIndex < described.count {
			let current = described[nextDescribedIndex]
			for draftCase in draftCases(of: current.type, isSendable: current.isSendable) {
				let next: Described
				switch draftCase.kind {
				case let .nested(builtType, isSendable),
				     let .fill(_, _, _, builtType, isSendable):
					guard !draftCases(of: builtType, isSendable: isSendable).isEmpty else { continue }
					next = Described(type: builtType, isSendable: isSendable)
				case .place, .inner:
					continue
				}
				if describedSet.insert(next).inserted {
					described.append(next)
				}
			}
			nextDescribedIndex += 1
		}
		guard !described.isEmpty else { return ScopeEnumsByType() }

		// Names. A nested enum is named by its type as the seam's module spells it; every generated type nested in a root takes
		// `_` while a type spelled inside that root, a case, or another generated type has its name.
		var enumTypeNameByDescribed = [Described: String]()
		var caseNamesByDescribed = [Described: [String]]()
		var valuesTypeNamesByDescribed = [Described: [String?]]()
		for isSendable in [false, true] {
			let rootTypeName = isSendable ? rootTypeNames.sendable : rootTypeNames.plain
			let familyDescribed = described.filter { $0.isSendable == isSendable }
			// The cases keep their labels; a `<label>_Sendable` case, and a call's case for a builder it fills,
			// `<label>_<builder>` or `<label>_<builder>_<Seam>`, take `_` while another case of their enum has their name, in case
			// order.
			for current in familyDescribed {
				let cases = draftCases(of: current.type, isSendable: isSendable)
				var takenCaseNames = Set(cases.filter { !$0.isSendableBeneath && $0.filledBuilder == nil }.map(\.property.label.spelledAsIdentifier))
				caseNamesByDescribed[current] = cases.map { draftCase in
					let label = draftCase.property.label.spelledWithoutBackticks
					var name: String
					if case let .fill(_, builderLabel, passingUpSeamStem, _, _) = draftCase.kind {
						name = "\(label)_\(builderLabel.spelledWithoutBackticks)\(passingUpSeamStem.map { "_\($0)" } ?? "")\(draftCase.isSendableBeneath ? "_Sendable" : "")".spelledAsIdentifier
					} else if draftCase.isSendableBeneath {
						name = "\(label)_Sendable".spelledAsIdentifier
					} else {
						return draftCase.property.label.spelledAsIdentifier
					}
					while !takenCaseNames.insert(name).inserted {
						name = "\(name)_".spelledAsJoinedIdentifier
					}
					return name
				}
			}
			var spelledTypeNames = Set<String>()
			for current in familyDescribed {
				for (draftCase, caseName) in zip(draftCases(of: current.type, isSendable: isSendable), caseNamesByDescribed[current, default: []]) {
					spelledTypeNames.insert(caseName)
					for field in draftCase.fields ?? [] {
						spelledTypeNames.formUnion(TypeAccessProof.mentionedTypes(in: field.property.typeDescription).compactMap(\.outermostTypeName))
					}
					if case .place = draftCase.kind, let forwardedType = draftCase.property.typeDescription.forwardedTypeOfWrapper {
						spelledTypeNames.formUnion(TypeAccessProof.mentionedTypes(in: forwardedType).compactMap(\.outermostTypeName))
					}
					if case let .inner(innerKey) = draftCase.kind, let innerEnum = reachedEnum(innerKey) {
						spelledTypeNames.formUnion(TypeAccessProof.mentionedTypes(in: innerEnum.type).compactMap(\.outermostTypeName))
					}
					if let innerKey = draftCase.filledBuilder?.innerKey, let innerEnum = reachedEnum(innerKey) {
						spelledTypeNames.formUnion(TypeAccessProof.mentionedTypes(in: innerEnum.type).compactMap(\.outermostTypeName))
					}
				}
			}
			var takenTypeNames = spelledTypeNames.union([rootTypeNames.plain, rootTypeNames.sendable]).union(externallyTakenTypeNames)
			enumTypeNameByDescribed[Described(type: seamType, isSendable: isSendable)] = rootTypeName
			let nestedTypes = familyDescribed.filter { $0.type != seamType }
			for (current, name) in zip(nestedTypes, nestedEnumNames(of: nestedTypes.map(\.type), instantiables: instantiables)) {
				var name = name
				while !takenTypeNames.insert(name).inserted {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				enumTypeNameByDescribed[current] = name
			}
			// A payload struct's name is taken from its case.
			for current in familyDescribed {
				valuesTypeNamesByDescribed[current] = zip(draftCases(of: current.type, isSendable: isSendable), caseNamesByDescribed[current, default: []]).map { draftCase, caseName in
					guard draftCase.fields != nil else { return nil }
					var valuesTypeName = "\(caseName)_Values".spelledAsJoinedIdentifier
					while takenTypeNames.contains(valuesTypeName) {
						valuesTypeName = "\(valuesTypeName)_".spelledAsJoinedIdentifier
					}
					return valuesTypeName
				}
			}
		}
		func rootTypeName(isSendable: Bool) -> String {
			isSendable ? rootTypeNames.sendable : rootTypeNames.plain
		}
		func key(of current: Described) -> SeamSignature.ScopeEnum.Key {
			SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: current.isSendable, describedType: current.type == seamType ? nil : current.type)
		}
		func enumType(of current: Described) -> TypeDescription? {
			enumTypeNameByDescribed[current].map { SeamSignature.ScopeEnum.nestedType(named: $0, in: current.type == seamType ? nil : rootTypeName(isSendable: current.isSendable)) }
		}

		// The enums: the plain family's, its root declared where a case of either family leads to a plain enum, then the
		// `@Sendable` family's.
		var result = ScopeEnumsByType()
		struct CaseOfProperty: Hashable {
			let described: Described
			let property: Property
			let isSendableBeneath: Bool
			/// For a call's case for a builder it fills, the builder.
			var filledBuilder: SeamDeclarationGraph.FilledBuilder?
		}
		var casesByProperty = [CaseOfProperty: SeamSignature.ScopeEnum.Case]()
		var caseIndexByProperty = [CaseOfProperty: (enumIndex: Int, caseIndex: Int)]()
		let plainRoot = Described(type: seamType, isSendable: false)
		let declaresPlainRoot = described.contains { !$0.isSendable }
		var orderedDescribed = described.filter { !$0.isSendable }
		if declaresPlainRoot, !describedSet.contains(plainRoot) {
			orderedDescribed.insert(plainRoot, at: 0)
			enumTypeNameByDescribed[plainRoot] = rootTypeNames.plain
		}
		orderedDescribed += described.filter(\.isSendable)
		for current in orderedDescribed {
			guard let typeName = enumTypeNameByDescribed[current] else { continue }
			var cases = [SeamSignature.ScopeEnum.Case]()
			let caseNames = caseNamesByDescribed[current, default: []]
			let valuesTypeNames = valuesTypeNamesByDescribed[current, default: []]
			for (index, draftCase) in draftCases(of: current.type, isSendable: current.isSendable).enumerated() {
				let values: SeamSignature.ScopeEnum.Values? = if let typeName = valuesTypeNames[index], let fields = draftCase.fields {
					SeamSignature.ScopeEnum.Values(typeName: typeName, fields: fields, labelsBoundLater: draftCase.labelsBoundLater)
				} else {
					nil
				}
				let kind: SeamSignature.ScopeEnum.Case.Kind
				switch draftCase.kind {
				case .place:
					// Filled in below, in the order the builders reach the sites.
					kind = .place(sites: [])
				case let .nested(builtType, isSendable):
					let heldDescribed = Described(type: builtType, isSendable: isSendable)
					guard describedSet.contains(heldDescribed) else { continue }
					kind = .nested(enumKey: key(of: heldDescribed), isIndirect: false)
				case let .inner(innerKey):
					guard let innerEnum = reachedEnum(innerKey) else { continue }
					kind = .inner(enumKey: innerKey, enumType: innerEnum.type, sitePath: [], isIndirect: false)
				case let .fill(filledBuilder, _, _, fulfiller, isSendable):
					let heldDescribed = Described(type: fulfiller, isSendable: isSendable)
					guard describedSet.contains(heldDescribed), let innerEnum = reachedEnum(filledBuilder.innerKey) else { continue }
					// A case that leads to a `@Sendable` function inside the fill carries no value bound outside it.
					kind = .fill(innerKey: filledBuilder.innerKey, innerEnumType: filledBuilder.carriesInnerScope ? innerEnum.type : nil, enumKey: key(of: heldDescribed), isIndirect: false)
				}
				let enumCase = SeamSignature.ScopeEnum.Case(name: caseNames[index], kind: kind, values: values)
				let caseOfProperty = CaseOfProperty(described: current, property: draftCase.property, isSendableBeneath: draftCase.isSendableBeneath, filledBuilder: draftCase.filledBuilder)
				casesByProperty[caseOfProperty] = enumCase
				caseIndexByProperty[caseOfProperty] = (result.enums.count, cases.count)
				cases.append(enumCase)
			}
			result.enums.append(SeamSignature.ScopeEnum(
				key: key(of: current),
				typeName: typeName,
				rootTypeName: current.type == seamType ? nil : rootTypeName(isSendable: current.isSendable),
				builderLabel: current.isSendable ? builderLabels.sendable : builderLabels.plain,
				cases: cases,
			))
		}

		// Each place and call, by the cases on its path. A path's steps are cases of the `@Sendable` family down to the
		// innermost `@Sendable` function on it, which carry no values; beneath that function, cases of the plain family, each
		// of whose payload the seam's tree binds before building the step's property, and the place's or the call's own case.
		// A step of a call whose fill leads on is the call's case for the builder filled, which carries, beneath the innermost
		// `@Sendable` function, the scope value the inner seam handed the fill.
		var sitesByCase = [CaseOfProperty: [SeamSignature.Hole.Site]]()
		/// The step of `caseOfProperty`'s case, whose payload the seam's tree binds before building the last property of
		/// `bindingPrefix`, or builds where the place or the call is, when `bindingPrefix` is `nil`.
		func routeStep(of caseOfProperty: CaseOfProperty, bindingPrefix: [Property]?) -> SeamSignature.Hole.RouteStep? {
			guard let enumCase = casesByProperty[caseOfProperty] else { return nil }
			var innerScope: SeamSignature.Hole.RouteStep.InnerScope?
			if case let .fill(innerKey, innerEnumType?, _, _) = enumCase.kind, let bindingPrefix {
				innerScope = .init(callPath: bindingPrefix, innerKey: innerKey, enumType: innerEnumType, builderLabel: reachedEnum(innerKey)?.builderLabel ?? "", name: "")
			}
			let leadsIntoFill = caseOfProperty.filledBuilder != nil
			guard let values = enumCase.values, let enumType = enumType(of: caseOfProperty.described) else {
				return SeamSignature.Hole.RouteStep(caseName: enumCase.name, values: nil, innerScope: innerScope, leadsIntoFill: leadsIntoFill)
			}
			if let bindingPrefix {
				result.valuesBindingKeys.insert(ValuesBindingKey(path: bindingPrefix, caseName: enumCase.name))
			}
			return SeamSignature.Hole.RouteStep(
				caseName: enumCase.name,
				values: .init(bindingName: "", type: .nested(name: values.typeName, parentType: enumType, generics: []), fields: values.fields, bindingPath: bindingPrefix ?? []),
				innerScope: innerScope,
				leadsIntoFill: leadsIntoFill,
			)
		}
		for reached in reached {
			let count = reached.steps.count
			guard count > 0 else { continue }
			// The routes the place or call takes: one per inner family a call hands up, the inner `@Sendable` enum's through
			// `@Sendable` cases all the way.
			var routes = [(innerKey: SeamSignature.ScopeEnum.Key?, isAllSendable: Bool)]()
			if let call = reached.call {
				if let innerKey = innerKey(handedUpBy: call, isSendable: false) {
					routes.append((innerKey, false))
				}
				if let innerKey = innerKey(handedUpBy: call, isSendable: true) {
					routes.append((innerKey, true))
				}
			} else {
				routes.append((nil, false))
			}
			for (innerKey, isAllSendable) in routes {
				// The index of the innermost property built in a `@Sendable` function of its own, every step before which is a
				// `<label>_Sendable` case.
				let innermostSendableIndex = isAllSendable ? count : reached.steps.lastIndex(where: \.buildsInSendableFunction)
				var steps = [SeamSignature.Hole.RouteStep]()
				for (index, reachedStep) in reached.steps.enumerated() {
					let type = reachedStep.type
					let property = reachedStep.property
					let caseOfProperty = if let innermostSendableIndex, index < innermostSendableIndex {
						CaseOfProperty(described: Described(type: type, isSendable: true), property: property, isSendableBeneath: true, filledBuilder: reachedStep.filledBuilder?.withoutInnerScope)
					} else if let innermostSendableIndex, index == innermostSendableIndex {
						CaseOfProperty(described: Described(type: type, isSendable: true), property: property, isSendableBeneath: false, filledBuilder: reachedStep.filledBuilder)
					} else {
						CaseOfProperty(described: Described(type: type, isSendable: false), property: property, isSendableBeneath: false, filledBuilder: reachedStep.filledBuilder)
					}
					guard let step = routeStep(of: caseOfProperty, bindingPrefix: index < count - 1 ? Array(reached.sitePath.prefix(reachedStep.pathLength)) : nil) else { break }
					if index < count - 1 {
						steps.append(step)
						continue
					}
					// Every edge of a path to a place is left in the graph, so each step has its case.
					guard let enumTypeName = enumTypeNameByDescribed[caseOfProperty.described], let enumCase = casesByProperty[caseOfProperty] else { break }
					let ownerRootTypeName = type == seamType ? nil : rootTypeName(isSendable: caseOfProperty.described.isSendable)
					if reached.call != nil, let innerKey {
						result.callRoutes.append(SeamSignature.CallRoute(
							sitePath: reached.sitePath,
							innerKey: innerKey,
							rootKey: SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: innermostSendableIndex != nil),
							route: steps,
							caseName: enumCase.name,
							values: step.values.map { ($0.type, $0.fields) },
						))
					} else {
						let site = SeamSignature.Hole.Site(seamType: seamType, path: reached.sitePath)
						sitesByCase[caseOfProperty, default: []].append(site)
						result.enumPlaceBySite[site] = SeamSignature.Hole.EnumPlace(
							nestedByTypeIn: enumTypeName,
							rootEnumTypeName: ownerRootTypeName,
							caseName: enumCase.name,
							valuesTypeName: enumCase.values?.typeName,
							isBuiltBySendableBuilder: innermostSendableIndex != nil,
							route: steps,
							values: enumCase.values?.fields ?? [],
						)
					}
				}
			}
		}
		for (caseOfProperty, sites) in sitesByCase {
			guard let (enumIndex, caseIndex) = caseIndexByProperty[caseOfProperty] else { continue }
			result.enums[enumIndex].cases[caseIndex].kind = .place(sites: sites)
		}
		return result
	}

	/// The name of each of `types`' enums nested by type: `<Type>_Scope`, the type spelled as the seam's module spells it.
	/// A caller's run computes the seam's tree over the declarations the seam's module sees, which spell its types as that
	/// module does, so a caller that declares a type of the same name names the enum the seam's module declares
	/// (`SafeDIToolSeamScopeByTypeTests`). Two types of one name are both named apart, by their module and then in the order
	/// of their spelling, so a name never depends on the order the types are met in.
	private static func nestedEnumNames(of types: [TypeDescription], instantiables: [TypeDescription: Instantiable]) -> [String] {
		let stems = types.map(\.asIdentifier.spelledWithoutBackticks)
		var names = stems
		var indicesByStem = [String: [Int]]()
		for (index, stem) in stems.enumerated() {
			indicesByStem[stem, default: []].append(index)
		}
		for indices in indicesByStem.values where indices.count > 1 {
			let ordered = indices.sorted { (instantiables[types[$0]]?.moduleName ?? "", types[$0].asSource) < (instantiables[types[$1]]?.moduleName ?? "", types[$1].asSource) }
			var taken = Set<String>()
			for index in ordered {
				var name = instantiables[types[index]]?.moduleName.map { "\($0)_\(stems[index])" } ?? stems[index]
				while !taken.insert(name).inserted {
					name += "_"
				}
				names[index] = name
			}
		}
		return names.map { "\($0)_Scope".spelledAsIdentifier }
	}

	/// A parameter of the builder function a lazy cycle closes on that a level nested by type carries: the property, in the
	/// form the builds that take it bind, and the receive a fill's reader is told declares it.
	struct LevelCycleParameter {
		let property: Property
		let receiver: CycleParameter.Receiver
	}

	/// The parameters of the builder function a lazy cycle closes on (`CycleParameter`) that any build of each type in the
	/// tree `root` roots declares, inside every fill whose code is generated too, by type, in the order the builds first
	/// declare them. A level nested by
	/// type carries each (`levelDeclarations`). A build whose function takes it binds the field from the parameter, so a
	/// place built inside such a function is handed the value the function was passed, as inline's place reads it, never the
	/// caller's, which the enum's chain, the first build's, would otherwise lead a fill to. A build whose function does not
	/// take it binds the field as the type's tree reads the label there, from the nearest declaration or the seam's
	/// parameter, so it holds what inline reads: the label itself, or the instance of the `LazilyInstantiated` it names
	/// where that is the seam's deferred parameter or a lazily instantiated declaration
	/// (`SeamHoles.valuesArguments(of:readingInstancesOf:)`). Every build takes a label in one form: a parameter's form
	/// follows from the receivers in the type's own tree, which every build shares. A build in a `@Sendable` function counts
	/// as any other: its function binds its parameters.
	/// A public mock's levels are its builds' outside every fill (`entersFills` false), since a place inside its fill keeps a
	/// case per path.
	static func cycleParametersOfAnyBuild(inTreeRootedAt root: ScopeGenerator, entersFills: Bool = true) -> [TypeDescription: [LevelCycleParameter]] {
		var parametersByType = [TypeDescription: [LevelCycleParameter]]()
		var generatorsToVisit = [root]
		while let generator = generatorsToVisit.popLast() {
			for child in generator.children where child.holeSite == nil && !child.closesPropertyCycle {
				// A fill whose code is generated builds a type whose levels are as any other's.
				guard child.fillHole == nil else {
					if entersFills, child.fillEmitsCode {
						generatorsToVisit.append(child)
					}
					continue
				}
				guard let type = child.builtInstantiable?.concreteInstantiable else { continue }
				generatorsToVisit.append(child)
				guard child.declaresCycleParameters else { continue }
				var parameters = parametersByType[type, default: []]
				for parameter in child.cycleParameters where !parameters.contains(where: { $0.property.label == parameter.property.label }) {
					parameters.append(LevelCycleParameter(property: parameter.property, receiver: parameter.receiver))
				}
				parametersByType[type] = parameters
			}
		}
		return parametersByType
	}

	/// The properties the builder function of any build of each type in the tree `root` roots rebinds as a member of a loop
	/// of builders among its scope's children (`ScopeGenerator.reboundProperties`), inside every fill whose code is generated
	/// too, by type, in the order the builds first rebind them. A level nested by type carries each (`levelDeclarations`), as
	/// `fields(of:)` declares the rebinding on a place's path. A build whose function rebinds it binds the field from that
	/// wrapper, so a place built inside the function is handed the wrapper inline's place reads, never the sibling's own. A
	/// build whose function does not binds the field from the label as Swift sees it there, the nearest declaration, which
	/// the type's tree receives, and so reads inline. Where every receiver in the type's tree receives the label only if
	/// available, the field takes the optional form: a build whose function does not rebind it can bind the label from an
	/// optional declaration, and a wrapper converts to the optional form. A public mock's levels are its builds' outside
	/// every fill (`entersFills` false), as `cycleParametersOfAnyBuild(inTreeRootedAt:entersFills:)` reads them.
	static func reboundPropertiesOfAnyBuild(inTreeRootedAt root: ScopeGenerator, entersFills: Bool = true) -> [TypeDescription: [Property]] {
		var propertiesByType = [TypeDescription: [Property]]()
		var generatorsToVisit = [root]
		while let generator = generatorsToVisit.popLast() {
			for child in generator.children where child.holeSite == nil && !child.closesPropertyCycle {
				// A fill whose code is generated builds a type whose levels are as any other's.
				guard child.fillHole == nil else {
					if entersFills, child.fillEmitsCode {
						generatorsToVisit.append(child)
					}
					continue
				}
				guard let type = child.builtInstantiable?.concreteInstantiable else { continue }
				generatorsToVisit.append(child)
				guard !child.reboundProperties.isEmpty else { continue }
				var properties = propertiesByType[type, default: []]
				for property in child.reboundProperties where !properties.contains(where: { $0.label == property.label }) {
					properties.append(child.onlyIfAvailableUnwrappedReceivedProperties.contains(property.asUnwrappedProperty) ? property.asOptionalProperty : property)
				}
				propertiesByType[type] = properties
			}
		}
		return propertiesByType
	}

	/// The received properties a public mock binds again (`mockBindsAgain(receiving:beneath:)`) in any build of each type
	/// in the tree `root` roots, outside every fill, by type, in the type's declaration order. A level nested by type carries
	/// each (`levelDeclarations`), as `fields(of:)` declares it on a place's path. A build that binds it again binds the field
	/// from that binding, so a place beneath it is handed the value the type received, as inline's place reads it, never the
	/// farther declaration of the label the binding hides. A build that does not binds the field from the label as Swift
	/// sees it there, the nearest declaration, which provides the form the type receives, and so reads inline.
	static func receivesBoundAgainOfAnyBuild(inTreeRootedAt root: ScopeGenerator) -> [TypeDescription: [Property]] {
		var propertiesByType = [TypeDescription: [Property]]()
		// The nearest declaration of each label above each scope, as `fields(of:)` declares them on a place's path: the root's
		// children, then each scope's forwarded properties, its builder function's cycle parameters, the receives the mock
		// binds again and its children.
		func declaring(_ properties: some Sequence<Property>, in nearestDeclarations: inout [String: Property]) {
			for property in properties {
				nearestDeclarations[property.label] = property
			}
		}
		// A label the root's children share is named apart there, so none of them declares it (`labelsChildrenShare`): each
		// receiver of it binds it again from the binding the mock names apart.
		let labelsNamedApart = root.labelsChildrenShare
		var rootDeclarations = [String: Property]()
		declaring(root.children.compactMap(\.property).filter { !labelsNamedApart.contains($0.label) }, in: &rootDeclarations)
		var generatorsToVisit = root.children.map { (generator: $0, nearestDeclarations: rootDeclarations) }
		while let (generator, inheritedDeclarations) = generatorsToVisit.popLast() {
			guard generator.fillHole == nil, generator.holeSite == nil, !generator.closesPropertyCycle, let instantiable = generator.builtInstantiable else { continue }
			var nearestDeclarations = inheritedDeclarations
			declaring(instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property), in: &nearestDeclarations)
			// A scope that closes no cycle declares every parameter of its builder function a lazy cycle closes on.
			declaring(generator.cycleParameters.map(\.property), in: &nearestDeclarations)
			// Every build of a type has its dependencies, so the type's are kept in their declaration order, whichever build
			// binds each again.
			var boundAgain = Set(propertiesByType[instantiable.concreteInstantiable, default: []])
			for dependency in instantiable.dependencies {
				let bindsAgain = if let nearest = nearestDeclarations[dependency.property.label] {
					mockBindsAgain(receiving: dependency, beneath: nearest)
				} else {
					dependency.source.isReceived && labelsNamedApart.contains(dependency.property.label)
				}
				guard bindsAgain else { continue }
				nearestDeclarations[dependency.property.label] = dependency.property
				boundAgain.insert(dependency.property)
			}
			if !boundAgain.isEmpty {
				propertiesByType[instantiable.concreteInstantiable] = instantiable.dependencies.map(\.property).filter(boundAgain.contains)
			}
			declaring(generator.children.compactMap(\.property), in: &nearestDeclarations)
			generatorsToVisit.append(contentsOf: generator.children.map { (generator: $0, nearestDeclarations: nearestDeclarations) })
		}
		return propertiesByType
	}

	/// What the scope `build` builds declares, in the order it binds the declarations, each as a field of a payload struct:
	/// for the seam's root, its parameters, then its children but those of `labelsNamedApart`, which a mock's root names
	/// apart and so does not declare (`ScopeGenerator.labelsChildrenShare`); for any other type, its `@Forwarded` properties, then the
	/// `cycleParameters` of its builder function that any build of the type declares, which hide every other declaration
	/// of their labels, then the `reboundProperties` and `receivesBoundAgain` of any build of the type, then its children. A
	/// case's payload holds those its type binds before the case's property.
	private static func levelDeclarations(
		of build: ScopeGenerator,
		isSeamRoot: Bool,
		labelsNamedApart: Set<String>,
		cycleParameters: [LevelCycleParameter],
		reboundProperties: [Property],
		receivesBoundAgain: [Property],
		seam: Instantiable,
		parameters: [SeamSignature.Parameter],
		seamTypeAccess: AccessLevel,
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
	) -> [SeamSignature.Hole.Field] {
		guard let instantiable = build.builtInstantiable else { return [] }
		var fields = [SeamSignature.Hole.Field]()
		func field(of property: Property) -> SeamSignature.Hole.Field {
			let access = proof.access(ofParameterTyped: property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, instantiable.moduleName]))
			return SeamSignature.Hole.Field(
				property: property,
				access: min(access.level, seamTypeAccess),
				accessCause: access.cause,
				declaringType: instantiable.concreteInstantiable,
				declarationLocation: instantiable.dependencies.first { $0.property == property }?.declarationLocation,
			)
		}
		if isSeamRoot {
			for parameter in parameters {
				// A pass-through is declared, as far as a fill's reader is told, by the first type in the tree that receives it.
				let firstReceiver = parameter.receivers.first
				fields.append(SeamSignature.Hole.Field(
					property: parameter.property,
					access: parameter.tierAccess,
					accessCause: parameter.accessCause,
					declaringType: firstReceiver?.declaringType ?? seam.concreteInstantiable,
					declarationLocation: firstReceiver?.declarationLocation ?? seam.dependencies.first { $0.property == parameter.property }?.declarationLocation ?? seam.declarationLocation,
					isReceivedOnlyIfAvailable: parameter.isOnlyIfAvailable,
					deferral: parameter.deferral,
				))
			}
		} else {
			for dependency in instantiable.dependencies where dependency.source == .forwarded {
				fields.append(field(of: dependency.property))
			}
			// A parameter is declared, as far as a fill's reader is told, by the first type in the function's body that
			// receives it, as `fields(of:)` declares it.
			for parameter in cycleParameters {
				guard let receivingType = parameter.receiver.chain.last else { continue }
				let access = proof.access(ofParameterTyped: parameter.property.typeDescription, mentionedFrom: .declaration(seam), admittedModules: Set([seam.moduleName, instantiables[receivingType]?.moduleName]))
				fields.removeAll { $0.property.label == parameter.property.label }
				fields.append(SeamSignature.Hole.Field(
					property: parameter.property,
					access: min(access.level, seamTypeAccess),
					accessCause: access.cause,
					declaringType: receivingType,
					declarationLocation: parameter.receiver.declarationLocation,
				))
			}
			for property in reboundProperties {
				fields.removeAll { $0.property.label == property.label }
				fields.append(field(of: property))
			}
			for property in receivesBoundAgain {
				fields.removeAll { $0.property.label == property.label }
				fields.append(field(of: property))
			}
		}
		for child in build.orderedChildrenComputedAfresh(propertiesGeneratedLater: []) {
			guard let property = child.generator.property, !labelsNamedApart.contains(property.label) else { continue }
			// A declaration hides an earlier one of its label: the seam's own alias that keeps a deferred parameter's label.
			fields.removeAll { $0.property.label == property.label }
			fields.append(field(of: property))
		}
		return fields
	}

	/// A payload the seam's tree binds: the path of the property it binds it just before building, and the case whose payload
	/// it is, of that property's type: the property's own, or a call's for a builder it fills, of which a call can have
	/// several.
	struct ValuesBindingKey: Hashable {
		let path: [Property]
		let caseName: String
	}

	/// The names the seam's tree binds the payload of each case on the routes to its places under, by the builder's stem,
	/// before the case's property, the last of its key's path in `keysByStem`, is built: one per path to the property, case
	/// and stem, `__safeDI_<stem>Values_<case>`, with `_` appended while a name in `reservedNames`, one bound on the way to
	/// the property, or one its scope binds already has it. The keys are named shortest path first, then in the order of
	/// their spelling, so no name depends on the order the routes are met in.
	static func valuesBindingNames(
		of keysByStem: [String: Set<ValuesBindingKey>],
		reservedNames: Set<String>,
	) -> [String: [ValuesBindingKey: String]] {
		struct Binding: Hashable {
			let stem: String
			let key: ValuesBindingKey
		}
		var bindings = Set<Binding>()
		for (stem, keys) in keysByStem {
			for key in keys {
				bindings.insert(Binding(stem: stem, key: key))
			}
		}
		func sortKey(of binding: Binding) -> String {
			binding.key.path.map(\.asSource).joined(separator: " ") + " " + binding.key.caseName + " " + binding.stem
		}
		let orderedBindings = bindings.sorted { first, second in
			first.key.path.count != second.key.path.count ? first.key.path.count < second.key.path.count : sortKey(of: first) < sortKey(of: second)
		}
		var namesByPath = [[Property]: Set<String>]()
		var nameByBinding = [Binding: String]()
		var namesByScope = [[Property]: Set<String>]()
		for binding in orderedBindings {
			let path = binding.key.path
			guard !path.isEmpty else { continue }
			let scope = Array(path.dropLast())
			var taken = reservedNames.union(namesByScope[scope, default: []])
			for length in 1..<path.count {
				taken.formUnion(namesByPath[Array(path.prefix(length)), default: []])
			}
			var name = ScopeGenerator.functionName(toBuildPropertyNamed: "\(binding.stem)Values_\(binding.key.caseName)")
			while taken.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			nameByBinding[binding] = name
			namesByPath[path, default: []].insert(name)
			namesByScope[scope, default: []].insert(name)
		}
		var namesByStem = [String: [ValuesBindingKey: String]]()
		for (binding, name) in nameByBinding {
			namesByStem[binding.stem, default: [:]][binding.key] = name
		}
		return namesByStem
	}

	/// The key of the root enum of the seam whose tree holds the place `fill` fills, of the family that builds it: the scope
	/// value that seam hands its builder, which the fill is handed whether the seam called makes it or passes it up, and so
	/// what a place inside the fill carries. A value the passing-up seam binds before its call is no level of it, as no
	/// generated fill reads one (`boundByPassingUpSeam`).
	static func filledRootKey(of fill: ScopeGenerator) -> SeamSignature.ScopeEnum.Key? {
		fill.fillHole.map(SeamSignature.ScopeEnum.rootKey(of:))
	}

	/// The keys of the root enums of `calledBuilders`, each once, with the label of the called seam's builder that is handed
	/// it or the enum that holds it: each builder's, then each the enums it reaches hold through an inner seam's call, breadth
	/// first, in case order.
	private static func rootEnumKeys(of calledBuilders: CalledBuilders) -> [(key: SeamSignature.ScopeEnum.Key, builderLabel: String)] {
		let enumsByKey = calledBuilders.enumsByKey
		var keys = [(key: SeamSignature.ScopeEnum.Key, builderLabel: String)]()
		var seen = Set<SeamSignature.ScopeEnum.Key>()
		var queue = calledBuilders.builders.map { (key: $0.enumKey, builderLabel: $0.label) }
		var nextIndex = 0
		while nextIndex < queue.count {
			let (key, builderLabel) = queue[nextIndex]
			nextIndex += 1
			guard seen.insert(key).inserted else { continue }
			if key.describedType == nil {
				keys.append((key, builderLabel))
			}
			queue += (enumsByKey[key]?.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:)) ?? []).map { (key: $0, builderLabel: builderLabel) }
		}
		return keys
	}
}

extension SeamSignature.ScopeEnum {
	/// The key of the root enum of the seam whose tree holds `hole`, of the family whose builder builds it.
	static func rootKey(of hole: SeamSignature.Hole) -> Key {
		Key(seamType: hole.scopeSeamType, holeType: hole.holeType, isSendable: hole.enumPlace?.isBuiltBySendableBuilder ?? false)
	}
}

extension SeamSignature.ScopeEnum {
	/// The type of an enum named `name`, nested in the root enum `rootTypeName`, as the seam's extension spells it.
	static func nestedType(named name: String, in rootTypeName: String?) -> TypeDescription {
		if let rootTypeName {
			.nested(name: name, parentType: .simple(name: rootTypeName, generics: []), generics: [])
		} else {
			.simple(name: name, generics: [])
		}
	}
}
