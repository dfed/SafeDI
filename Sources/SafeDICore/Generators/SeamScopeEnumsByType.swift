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
		/// Whether this is a seam's call inside a fill that re-enters an enclosing call's fill by name, whose last step is its
		/// case for the builder that fill is passed for: the member of that case returns the struct the call passes to the
		/// enclosing call's level function.
		var reentersEnclosingFill = false
	}

	/// A case on a route, by everything that decides its step (`SeamSignature.Hole.RouteStep`) and nothing of the path it is
	/// on: the hole type, the case's enum (its type and family) and property, whether the case holds a `@Sendable` enum
	/// beneath, the builder a call's case fills, whether the step's property is built in a `@Sendable` function, whether
	/// the route is the `@Sendable` root's, and whether the seam's tree binds the case's payload before the property.
	struct RouteEdge: Hashable {
		let holeType: SeamSignature.HoleType
		let type: TypeDescription
		let isSendableEnum: Bool
		let property: Property
		let isSendableBeneath: Bool
		let filledBuilder: SeamDeclarationGraph.FilledBuilder?
		let buildsInSendableFunction: Bool
		let isSendableRoute: Bool
		let bindsPayload: Bool
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
		/// The member call each step of a site's route makes (`enumPlaceBySite`'s `route`), in the route's order.
		var routeMembersBySite = [SeamSignature.Hole.Site: [SeamSignature.Hole.RouteStep.Member?]]()
		/// The member calls the seam's tree makes where the enums declare builder structs, each for the last property of its
		/// path: one per case on a route, whether or not it carries values, by whether the route is the `@Sendable` root's,
		/// each with the nodes of the seam's graph bound there, which name it (`memberBindingNames(of:reservedNames:)`).
		var memberBindingKeysByFamily = [Bool: [ValuesBindingKey: Set<BindingNode>]]()
		/// The node of the seam's graph each call's inner scope is bound at, which names it (`innerScopeNames`).
		var innerScopeNodesByKey = [InnerScopeKey: Set<BindingNode>]()
		/// The step of each case on a route, with its member call, by its edge, with no binding path length: what a path decides
		/// of a step is only where its member and inner scope are bound (`SeamRouteStepAndMember.atBindingPathLength(_:)`).
		var routeStepByEdge = [RouteEdge: SeamRouteStepAndMember]()
		/// Each route beside its steps by edge, while the tests observe the seam's places.
		var routeStepObservations = [SeamRouteStepObservation]()

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
	/// in the `@Sendable` family, and no value. A call one of whose builders the seam's tree fills with a type whose tree
	/// leads to a place has a case per such builder after its own, `<call>_<builder>`, which holds the scope value the inner
	/// seam handed the fill and the enum of the type the fill builds, nested by type as any type of the tree: a place inside a
	/// fill is a place of that type. A place the inner seam passes up from a seam it calls has a case per such seam,
	/// `<call>_<builder>_<Seam>`, holding that seam's scope value; fills that differ in whether they carry the scope value take
	/// a case each. Every other case of the plain family carries what its type binds before the property, read from a build
	/// of the type, every build of a type binding the same values in the same order; a case of the `@Sendable` family carries
	/// none, since a place is handed only what the innermost `@Sendable` function that builds it binds, which is why a call's
	/// case that leads to a `@Sendable` function inside the fill carries no inner scope.
	/// - Parameters:
	///   - builderBuiltType: What the hole type's builder returns, the generic argument of each builder struct its levels'
	///     members return.
	///   - reached: The places of the hole type, and the calls that pass one up, in the order the seam's generated code
	///     reaches them.
	///   - bindsReceivesAgain: Whether the tree is a public mock's, whose types' levels hold the receives it binds again
	///     (`receivesBoundAgainOfAnyBuild(inTreeRootedAt:rootFields:namesApartAtRoot:)`).
	///   - reenteredFillsByKey: The fills a call inside a fill of the same call can re-enter
	///     (`emittingFillsByKey(inTreeRootedAt:)`), found once for the tree.
	///   - levels: What every hole type of the tree reads alike, found once for the tree, and each type's level
	///     declarations, kept as the hole types first compute them.
	static func scopeEnumsByType(
		of seam: Instantiable,
		holeType: SeamSignature.HoleType,
		builderBuiltType: TypeDescription,
		rootTypeNames: (plain: String, sendable: String),
		builderLabels: (plain: String, sendable: String),
		generator: ScopeGenerator,
		reached: [ReachedPlace],
		parameters: [SeamSignature.Parameter],
		bindsReceivesAgain: Bool,
		reenteredFillsByKey: [String: ScopeGenerator],
		proof: TypeAccessProof,
		instantiables: [TypeDescription: Instantiable],
		reachedEnum: (SeamSignature.ScopeEnum.Key) -> SeamSignature.ScopeEnum?,
		levels: inout LevelsOfEveryHoleType,
	) -> ScopeEnumsByType {
		let seamType = seam.concreteInstantiable
		let seamTypeAccess = parameterAccess(seam.effectiveTypeAccess)
		// The inner enum of the hole type, of the family `isSendable` says, a call hands up, by the call's generator.
		func innerKey(handedUpBy call: ScopeGenerator, isSendable: Bool) -> SeamSignature.ScopeEnum.Key? {
			let keys = levels.innerKeysHandedUp(by: call).keysByHoleType[holeType]
			return isSendable ? keys?.sendable : keys?.plain
		}
		// The graph of the hole type's places, which every hole type of the tree reads from one walk
		// (`LevelsOfEveryHoleType.placeHolding(of:inTreeRootedAt:reenteredFillsByKey:)`).
		let placeHolding = levels.placeHolding(of: holeType, inTreeRootedAt: generator, reenteredFillsByKey: reenteredFillsByKey)

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
		/// For a call's case for a builder it fills with a fulfiller that is itself a call handing up an enum of the hole type,
		/// that enum's key, by the calling type, the call's property and the filled builder's root key: the case holds it.
		struct FillOfProperty: Hashable {
			let type: TypeDescription
			let property: Property
			let innerKey: SeamSignature.ScopeEnum.Key
		}
		var handedUpKeyByFillOfProperty = [FillOfProperty: (plain: SeamSignature.ScopeEnum.Key?, sendable: SeamSignature.ScopeEnum.Key?)]()
		let typesWithCases = Set(placeHolding.plainCasePropertiesByType.keys)
			.union(placeHolding.sendableOwnCasePropertiesByType.keys)
			.union(placeHolding.sendableBeneathCasePropertiesByType.keys)
			.union(placeHolding.plainFillCasesByType.keys)
			.union(placeHolding.sendableOwnFillCasesByType.keys)
			.union(placeHolding.sendableBeneathFillCasesByType.keys)
		for type in typesWithCases {
			guard let build = placeHolding.firstBuild(of: type), let instantiable = build.builtInstantiable else { continue }
			let plainProperties = placeHolding.plainCasePropertiesByType[type, default: []]
			let sendableOwnProperties = placeHolding.sendableOwnCasePropertiesByType[type, default: []]
			let sendableBeneathProperties = placeHolding.sendableBeneathCasePropertiesByType[type, default: []]
			let plainFills = placeHolding.plainFillCasesByType[type, default: []]
			let sendableOwnFills = placeHolding.sendableOwnFillCasesByType[type, default: []]
			let sendableBeneathFills = placeHolding.sendableBeneathFillCasesByType[type, default: []]
			let declarations = plainProperties.isEmpty && plainFills.isEmpty ? [] : levels.declarations(
				of: build,
				as: type,
				seam: seam,
				parameters: parameters,
				bindsReceivesAgain: bindsReceivesAgain,
				seamTypeAccess: seamTypeAccess,
				proof: proof,
				instantiables: instantiables,
			)
			let childrenByProperty = levels.childrenByProperty(of: build)
			var plainCases = [DraftCase]()
			var sendableCases = [DraftCase]()
			func builtType(of property: Property) -> TypeDescription? {
				placeHolding.builtTypeByTypeAndProperty[SeamDeclarationGraph.TypeAndProperty(type: type, property: property)]
			}
			// In the type's declaration order, then the children a public mock's root builds that the type does not declare, in the
			// order the mock's tree first receives them (`inOrderTheMockTreeFirstReceives`), which is not always the order the root
			// builds them in: the received dependencies the mock promotes to its root (`createMockRootScopeGenerator`), whose
			// trees' places are the mock's places like any other's. Only the properties with a case of the hole type are visited,
			// so that a type's hole types together visit its properties once, not each hole type every property.
			let caseProperties = levels.caseProperties(of: build, instantiable: instantiable)
			var propertiesWithCases = plainProperties.union(sendableOwnProperties).union(sendableBeneathProperties)
			for fillCase in plainFills.union(sendableOwnFills).union(sendableBeneathFills) {
				propertiesWithCases.insert(fillCase.property)
			}
			let casePositions = propertiesWithCases.flatMap { caseProperties.positionsByProperty[$0] ?? [] }.sorted()
			for property in casePositions.map({ caseProperties.properties[$0] }) {
				guard let (childIndex, child) = childrenByProperty[property] else { continue }
				let isCall = child.holeSite == nil && !child.passedUpHoles.isEmpty
				// Where the type binds the property: a mock's root declares a child it promotes for an optional receive as the
				// non-optional value it builds (`levelDeclarations`), so what it binds before that child is found by that binding.
				let boundProperty = type == seamType && bindsReceivesAgain ? Self.mockRootBinding(ofChild: property, of: instantiable) : property
				func boundPosition() -> Int {
					declarations.firstIndex { $0.property == boundProperty } ?? declarations.count
				}
				if plainProperties.contains(property) {
					let position = boundPosition()
					// A member of the property's loop of builders (`ScopeGenerator.ReceivedBuilderLoops`) is still being built where
					// the loop's payloads are bound, before the loop's first function: the property's own function wraps again what
					// its tree receives of it. It is bound later than the payload, as the declarations after the property are. A loop
					// is built as one unit, so its members are consecutive declarations, and the case's values end at the first: a
					// prefix of the level's one sequence, as every case's are.
					let prefixLength = declarations[..<position].firstIndex { field in
						guard let fieldChild = childrenByProperty[field.property] else { return false }
						return build.areMembersOfOneLoop(childAt: fieldChild.index, childIndex)
					} ?? position
					let fields = Array(declarations[..<prefixLength])
					let labelsBoundLater = Set(declarations[prefixLength...].map(\.property.label) + [property.label])
					if child.holeSite != nil {
						plainCases.append(DraftCase(property: property, kind: .place, fields: fields, labelsBoundLater: labelsBoundLater))
					} else if isCall, let innerKey = innerKey(handedUpBy: child, isSendable: false) {
						// A call's case holds the inner enum alone, as in the `@Sendable` family: no generated fill reads what the type
						// binds before the call (`boundByPassingUpSeam`), and the builder the called type holds would capture it.
						plainCases.append(DraftCase(property: property, kind: .inner(innerKey), fields: nil))
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
				for fill in child.children where fill.fillEmitsCode {
					guard let fulfiller = fill.children.first, !fulfiller.passedUpHoles.isEmpty, let filledKey = Self.filledRootKey(of: fill, in: child) else { continue }
					let handedUpKeys = (plain: innerKey(handedUpBy: fulfiller, isSendable: false), sendable: innerKey(handedUpBy: fulfiller, isSendable: true))
					if handedUpKeys.plain != nil || handedUpKeys.sendable != nil {
						handedUpKeyByFillOfProperty[FillOfProperty(type: type, property: property, innerKey: filledKey)] = handedUpKeys
					}
				}
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
							plainCases.append(DraftCase(property: property, kind: .fill(filledBuilder, builderLabel: builderLabel, passingUpSeamStem: passingUpSeamStem, fulfiller: fulfiller, isSendable: false), fields: Array(declarations[..<boundPosition()])))
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
		/// The type of each described type's enum as it is declared: a root enum, or an enum nested in its family's root.
		var enumTypeByDescribed = [Described: TypeDescription]()
		var caseNamesByDescribed = [Described: [String]]()
		var valuesTypeNamesByDescribed = [Described: [String]]()
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
			var takenTypeNames = spelledTypeNames.union([rootTypeNames.plain, rootTypeNames.sendable])
			enumTypeNameByDescribed[Described(type: seamType, isSendable: isSendable)] = rootTypeName
			for current in familyDescribed where current.type == seamType {
				enumTypeByDescribed[current] = SeamSignature.ScopeEnum.nestedType(named: rootTypeName, in: nil)
			}
			let nestedTypes = familyDescribed.filter { $0.type != seamType }
			for (current, name) in zip(nestedTypes, nestedEnumNames(of: nestedTypes.map(\.type), instantiables: instantiables)) {
				var name = name
				while !takenTypeNames.insert(name).inserted {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				enumTypeNameByDescribed[current] = name
				enumTypeByDescribed[current] = SeamSignature.ScopeEnum.nestedType(named: name, in: rootTypeName)
			}
			// A payload struct's name is taken from its case, as is the name of the empty struct a builder struct's member of a
			// case that carries no values takes.
			for current in familyDescribed {
				valuesTypeNamesByDescribed[current] = zip(draftCases(of: current.type, isSendable: isSendable), caseNamesByDescribed[current, default: []]).map { _, caseName in
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
				let memberValuesTypeName = valuesTypeNames[index]
				let values: SeamSignature.ScopeEnum.Values? = if let fields = draftCase.fields {
					SeamSignature.ScopeEnum.Values(typeName: memberValuesTypeName, fields: fields, labelsBoundLater: draftCase.labelsBoundLater)
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
					// The case spells the enum it holds as the enum is declared, the seam's own root enum among them.
					guard let heldEnumType = enumTypeByDescribed[heldDescribed] else { continue }
					kind = .nested(enumKey: key(of: heldDescribed), enumType: heldEnumType, isIndirect: false)
				case let .inner(innerKey):
					guard let innerEnum = reachedEnum(innerKey) else { continue }
					kind = .inner(enumKey: innerKey, enumType: innerEnum.type, isIndirect: false)
				case let .fill(filledBuilder, _, _, fulfiller, isSendable):
					// A fulfiller that is itself a call handing up an enum of the hole type: the case holds that call's enum.
					let handedUpKeys = handedUpKeyByFillOfProperty[FillOfProperty(type: current.type, property: draftCase.property, innerKey: filledBuilder.innerKey)]
					if let handedUpKey = isSendable ? handedUpKeys?.sendable : handedUpKeys?.plain, let handedUpEnum = reachedEnum(handedUpKey), let innerEnum = reachedEnum(filledBuilder.innerKey) {
						kind = .fill(innerKey: filledBuilder.innerKey, innerEnumType: filledBuilder.carriesInnerScope ? innerEnum.type : nil, enumKey: handedUpKey, enumType: handedUpEnum.type, isIndirect: false)
						break
					}
					let heldDescribed = Described(type: fulfiller, isSendable: isSendable)
					guard let heldEnumType = enumTypeByDescribed[heldDescribed], let innerEnum = reachedEnum(filledBuilder.innerKey) else { continue }
					// A case that leads to a `@Sendable` function inside the fill carries no value bound outside it.
					kind = .fill(innerKey: filledBuilder.innerKey, innerEnumType: filledBuilder.carriesInnerScope ? innerEnum.type : nil, enumKey: key(of: heldDescribed), enumType: heldEnumType, isIndirect: false)
				}
				let enumCase = SeamSignature.ScopeEnum.Case(name: caseNames[index], kind: kind, values: values, memberValuesTypeName: memberValuesTypeName)
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
		/// Where the enum declares a builder struct, the step's member is called at the top of the property's own builder
		/// function when the case is a `@Sendable` enum's and `buildsInSendableFunction` (see `RouteStep.Member`).
		func routeStep(of caseOfProperty: CaseOfProperty, bindingPrefix: [Property]?, buildsInSendableFunction: Bool) -> SeamRouteStepAndMember? {
			guard let enumCase = casesByProperty[caseOfProperty] else { return nil }
			var innerScope: SeamSignature.Hole.RouteStep.InnerScope?
			if case let .fill(innerKey, _?, _, fillLevelEnumType, _) = enumCase.kind, let bindingPrefix {
				// A fill is handed the struct of its own level, which the called seam's or public mock's struct the case's member
				// returns builds at the place.
				let carriedType = ReservedName.levelType(ofEnum: fillLevelEnumType, built: builderBuiltType)
				innerScope = .init(callPathLength: bindingPrefix.count, innerKey: innerKey, enumType: carriedType, builderLabel: reachedEnum(innerKey)?.builderLabel ?? "", name: "")
			}
			let leadsIntoFill = caseOfProperty.filledBuilder != nil
			let enumType = enumTypeByDescribed[caseOfProperty.described]
			// What a member returns: the builder struct of the enum the case holds, which a place's case, the last on its
			// route, does not.
			let heldEnumType = SeamSignature.ScopeEnum.heldEnumType(of: enumCase)
			var member: SeamSignature.Hole.RouteStep.Member?
			// Deliberate gap: a loop's level re-entered through a cycle-closing scope calls no member of its own, and re-enters
			// the function built at its first opening with the struct bound there, which carries nothing bound above the
			// reopened level. A read of such a value stays rejected (`declarationBoundOnCycleReentry`); do not lift that
			// rejection before the member exists.
			if let bindingPrefix, let enumType, let memberValuesTypeName = enumCase.memberValuesTypeName, let heldEnumType {
				member = .init(
					bindingName: "",
					valuesType: .nested(name: memberValuesTypeName, parentType: enumType, generics: []),
					fields: enumCase.values?.fields ?? [],
					levelType: ReservedName.levelType(ofEnum: heldEnumType, built: builderBuiltType),
					bindingPathLength: bindingPrefix.count,
					isCalledInsideFunction: caseOfProperty.described.isSendable && buildsInSendableFunction,
				)
			}
			guard let values = enumCase.values, let enumType else {
				return SeamRouteStepAndMember(step: SeamSignature.Hole.RouteStep(caseName: enumCase.name, values: nil, innerScope: innerScope, leadsIntoFill: leadsIntoFill), member: member)
			}
			return SeamRouteStepAndMember(
				step: SeamSignature.Hole.RouteStep(
					caseName: enumCase.name,
					values: .init(bindingName: "", type: .nested(name: values.typeName, parentType: enumType, generics: []), fields: values.fields),
					innerScope: innerScope,
					leadsIntoFill: leadsIntoFill,
				),
				member: member,
			)
		}
		/// Records the node of the seam's graph that `step`, the step of `caseOfProperty`'s case on a route, binds its member
		/// and its inner scope at, under the path the route binds them at, `bindingPrefix`, which names them
		/// (`memberBindingNames(of:reservedNames:)`, `innerScopeNames`); `pathLength` is the step's own
		/// (`ReachedStep.pathLength`).
		func recordBindings(of step: SeamSignature.Hole.RouteStep, member: SeamSignature.Hole.RouteStep.Member?, caseOfProperty: CaseOfProperty, pathLength: Int, bindingPrefix: [Property]?, isSendableRoute: Bool) {
			guard let bindingPrefix else { return }
			let node = BindingNode(
				type: caseOfProperty.described.type,
				isSendableEnum: caseOfProperty.described.isSendable,
				property: caseOfProperty.property,
				caseName: step.caseName,
				bindingOffset: bindingPrefix.count - pathLength,
			)
			if let innerScope = step.innerScope {
				result.innerScopeNodesByKey[InnerScopeKey(callPath: bindingPrefix, innerKey: innerScope.innerKey, enumType: innerScope.enumType), default: []].insert(node)
			}
			if member != nil {
				result.memberBindingKeysByFamily[isSendableRoute, default: [:]][ValuesBindingKey(path: bindingPrefix, caseName: step.caseName), default: []].insert(node)
			}
		}
		// The tests compare each route with its steps by edge (`SeamPlaceLevels.routeSteps`).
		let observesRouteSteps = SeamPlaceLevels.observer != nil
		// The step of each edge, or `nil` where its case is missing, which ends every route through it.
		var stepByEdge = [RouteEdge: SeamRouteStepAndMember?]()
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
				// The member call each of `steps` makes, in its order.
				var members = [SeamSignature.Hole.RouteStep.Member?]()
				// Every step this route computes, the last included, with its member call, its edge and the length of the path its
				// member is bound at.
				var computedSteps = [SeamRouteStepAndMember]()
				var edgesOfSteps = [(edge: RouteEdge, bindingPathLength: Int)]()
				defer {
					if observesRouteSteps {
						result.routeStepObservations.append(SeamRouteStepObservation(
							seamType: seamType,
							sitePath: reached.sitePath,
							computed: computedSteps,
							rebuilt: edgesOfSteps.compactMap { result.routeStepByEdge[$0.edge]?.atBindingPathLength($0.bindingPathLength) },
						))
					}
				}
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
					// A call that is itself the fulfiller of a fill ends on the case of the call it fills, whose member is bound as a
					// step's before that call, and is handed the struct of the fill's own level.
					let isFulfillingCall = (reached.call != nil || reached.reentersEnclosingFill) && index == count - 1 && reachedStep.filledBuilder != nil
					// Where the call is built in a `@Sendable` function, the fill's own included, its member is called at the top of
					// the call's own builder function, inside that function: bound at the calling scope, before the fill, it would be
					// a plain struct a `@Sendable` function captures.
					// Likewise a call's case for a fill whose fulfiller builds its type in a `@Sendable` builder function of its own: the
					// case carries no inner scope, and the plain struct its member returns is called at the top of that function, which a
					// place inside the fill reads it in.
					let isBoundInsideFulfillersFunction = index < count - 1
						&& caseOfProperty.described.isSendable
						&& !caseOfProperty.isSendableBeneath
						&& reachedStep.filledBuilder?.carriesInnerScope == false
					let bindingPrefix: [Property]? = if isFulfillingCall, caseOfProperty.described.isSendable, reachedStep.buildsInSendableFunction {
						reached.sitePath
					} else if isBoundInsideFulfillersFunction {
						Array(reached.sitePath.prefix(reached.steps[index + 1].pathLength - 1))
					} else if index < count - 1 || isFulfillingCall {
						Array(reached.sitePath.prefix(reachedStep.pathLength))
					} else {
						nil
					}
					let buildsInSendableFunction = reachedStep.buildsInSendableFunction || isBoundInsideFulfillersFunction
					// The step is the edge's, whatever path leads to it, but for where its member and inner scope are bound
					// (`SeamRouteStepAndMember.atBindingPathLength(_:)`): each edge's step is computed once, and every route through the
					// edge reads it, bound at the route's own path length.
					let edge = RouteEdge(
						holeType: holeType,
						type: type,
						isSendableEnum: caseOfProperty.described.isSendable,
						property: property,
						isSendableBeneath: caseOfProperty.isSendableBeneath,
						filledBuilder: caseOfProperty.filledBuilder,
						buildsInSendableFunction: buildsInSendableFunction,
						isSendableRoute: innermostSendableIndex != nil,
						bindsPayload: bindingPrefix != nil,
					)
					let stepOfEdge: SeamRouteStepAndMember?
					if let storedStep = stepByEdge[edge] {
						stepOfEdge = storedStep
					} else {
						stepOfEdge = routeStep(of: caseOfProperty, bindingPrefix: bindingPrefix, buildsInSendableFunction: buildsInSendableFunction)?.atBindingPathLength(0)
						stepByEdge[edge] = .some(stepOfEdge)
						result.routeStepByEdge[edge] = stepOfEdge
					}
					guard let stepOfEdge else { break }
					let boundStep = stepOfEdge.atBindingPathLength(bindingPrefix?.count ?? 0)
					let step = boundStep.step
					let member = boundStep.member
					recordBindings(of: step, member: member, caseOfProperty: caseOfProperty, pathLength: reachedStep.pathLength, bindingPrefix: bindingPrefix, isSendableRoute: innermostSendableIndex != nil)
					// The tests compare the step each route would compute on its own with the edge's.
					if observesRouteSteps, let computedStep = routeStep(of: caseOfProperty, bindingPrefix: bindingPrefix, buildsInSendableFunction: buildsInSendableFunction) {
						computedSteps.append(computedStep)
						edgesOfSteps.append((edge, bindingPrefix?.count ?? 0))
					}
					if index < count - 1 {
						steps.append(step)
						members.append(member)
						continue
					}
					// A call that re-enters an enclosing call's fill is handed what its case's member returns, the called seam's struct,
					// which the enclosing call's level function takes.
					if isFulfillingCall, reached.reentersEnclosingFill, let filledBuilder = reachedStep.filledBuilder {
						result.callRoutes.append(SeamSignature.CallRoute(
							sitePath: reached.sitePath,
							innerKey: filledBuilder.innerKey,
							rootKey: SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: innermostSendableIndex != nil),
							route: steps + [step],
							routeMembers: members + [member],
							caseName: "",
							reentersEnclosingFill: true,
						))
						break
					}
					if isFulfillingCall, let innerKey {
						result.callRoutes.append(SeamSignature.CallRoute(
							sitePath: reached.sitePath,
							innerKey: innerKey,
							rootKey: SeamSignature.ScopeEnum.Key(seamType: seamType, holeType: holeType, isSendable: innermostSendableIndex != nil),
							route: steps + [step],
							routeMembers: members + [member],
							caseName: "",
							handsFillLevelStruct: true,
						))
						break
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
							routeMembers: members,
							caseName: enumCase.name,
							memberValuesType: enumCase.memberValuesTypeName.flatMap { memberValuesTypeName in
								enumTypeByDescribed[caseOfProperty.described].map { .nested(name: memberValuesTypeName, parentType: $0, generics: []) }
							},
						))
					} else {
						let site = SeamSignature.Hole.Site(seamType: seamType, path: reached.sitePath)
						sitesByCase[caseOfProperty, default: []].append(site)
						result.enumPlaceBySite[site] = SeamSignature.Hole.EnumPlace(
							nestedByTypeIn: enumTypeName,
							rootEnumTypeName: ownerRootTypeName,
							caseName: enumCase.name,
							valuesTypeName: enumCase.values?.typeName,
							memberValuesTypeName: enumCase.memberValuesTypeName,
							isBuiltBySendableBuilder: innermostSendableIndex != nil,
							route: steps,
							values: enumCase.values?.fields ?? [],
						)
						result.routeMembersBySite[site] = members
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
	static func cycleParametersOfAnyBuild(inTreeRootedAt root: ScopeGenerator) -> [TypeDescription: [LevelCycleParameter]] {
		var parametersByType = [TypeDescription: [LevelCycleParameter]]()
		var generatorsToVisit = [root]
		while let generator = generatorsToVisit.popLast() {
			for child in generator.children where child.holeSite == nil && !child.closesPropertyCycle {
				// A fill whose code is generated builds a type whose levels are as any other's.
				guard child.fillHole == nil else {
					if child.fillEmitsCode {
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
	/// optional declaration, and a wrapper converts to the optional form.
	static func reboundPropertiesOfAnyBuild(inTreeRootedAt root: ScopeGenerator) -> [TypeDescription: [Property]] {
		var propertiesByType = [TypeDescription: [Property]]()
		var generatorsToVisit = [root]
		while let generator = generatorsToVisit.popLast() {
			for child in generator.children where child.holeSite == nil && !child.closesPropertyCycle {
				// A fill whose code is generated builds a type whose levels are as any other's.
				guard child.fillHole == nil else {
					if child.fillEmitsCode {
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
	///
	/// A receive of a form the root binds only under a name apart (`id_Badge`), with no type on a fill's path that receives
	/// that form, leaves the fill's own receive of it unprovided: the place is passed up, and the caller's builder can capture
	/// the value. `fields(of:)` decides the same way.
	static func receivesBoundAgainOfAnyBuild(inTreeRootedAt root: ScopeGenerator, rootFields: [Property], namesApartAtRoot: PublicMockRootLevel.NamesApart) -> [TypeDescription: [Property]] {
		var propertiesByType = [TypeDescription: [Property]]()
		// The nearest declaration of each label above each scope, as `fields(of:)` declares them on a place's path: the root's
		// children, then each scope's forwarded properties, its builder function's cycle parameters, the receives the mock
		// binds again and its children.
		func declaring(_ properties: some Sequence<Property>, in nearestDeclarations: inout [String: Property]) {
			for property in properties {
				nearestDeclarations[property.label] = property
			}
		}
		// The root level's fields, the bindings `mock()` holds under their bare labels before its tree, come first. A label only
		// names apart bind there (`PublicMockRootLevel.NamesApart.labels`) has no declaration: each receiver of it binds it again
		// from the binding of its form. Nor does a child declare a label a field holds.
		var rootDeclarations = [String: Property]()
		declaring(rootFields, in: &rootDeclarations)
		let rootFieldLabels = Set(rootFields.map(\.label))
		// A child the mock promotes is declared as the non-optional value the root binds (`mockRootBinding(ofChild:of:)`).
		let rootChildren = root.children.compactMap(\.property).filter { !namesApartAtRoot.labels.contains($0.label) && !rootFieldLabels.contains($0.label) }
		declaring(root.builtInstantiable.map { mockedType in rootChildren.map { mockRootBinding(ofChild: $0, of: mockedType) } } ?? rootChildren, in: &rootDeclarations)
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
			// A wrapper the root binds apart is handed by name, never bound again.
			for dependency in instantiable.dependencies where !namesApartAtRoot.wrappers.contains(dependency.property) {
				let bindsAgain = if let nearest = nearestDeclarations[dependency.property.label] {
					mockBindsAgain(receiving: dependency, beneath: nearest)
				} else {
					dependency.source.isReceived && namesApartAtRoot.labels.contains(dependency.property.label)
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

	/// What `scopeEnumsByType` reads alike for every hole type of one tree: the hole type of each place by its owner and
	/// property, and what any build of each type binds again (cycle parameters, rebound properties, receives a mock binds
	/// again), each found by a walk of the whole tree; and each type's level declarations and children by property, which
	/// depend only on the build and the tree. `shapedBuilders` makes one for its tree and hands it to each hole type in turn,
	/// so the walks run once and each level is declared once, not once per hole type: computed per hole type, they grew with
	/// the hole types times the tree, which is the hole types squared for a public mock whose type declares every hole.
	/// It holds no reference type but the generators its memos are keyed by, and is used in one synchronous loop.
	struct LevelsOfEveryHoleType {
		init(
			generator: ScopeGenerator,
			holes: some Sequence<SeamSignature.Hole>,
			parameters: [SeamSignature.Parameter],
			bindsReceivesAgain: Bool,
			namesApartAtRoot: PublicMockRootLevel.NamesApart,
		) {
			var holeTypeByOwnedProperty = [SeamDeclarationGraph.TypeAndProperty: SeamSignature.HoleType]()
			// Every site of one declaration builds one hole type.
			for hole in holes where hole.innerSeamType == nil {
				holeTypeByOwnedProperty[SeamDeclarationGraph.TypeAndProperty(type: hole.ownerType, property: hole.property)] = hole.holeType
			}
			self.holeTypeByOwnedProperty = holeTypeByOwnedProperty
			cycleParametersOfAnyBuild = DependencyTreeGenerator.cycleParametersOfAnyBuild(inTreeRootedAt: generator)
			reboundPropertiesOfAnyBuild = DependencyTreeGenerator.reboundPropertiesOfAnyBuild(inTreeRootedAt: generator)
			receivesBoundAgainOfAnyBuild = bindsReceivesAgain
				? DependencyTreeGenerator.receivesBoundAgainOfAnyBuild(inTreeRootedAt: generator, rootFields: parameters.map(\.property), namesApartAtRoot: namesApartAtRoot)
				: [:]
			// A mock's root declares no child of a label its root level's fields hold, or one that only names apart bind.
			labelsNoRootChildDeclares = bindsReceivesAgain ? namesApartAtRoot.labels.union(parameters.map(\.property.label)) : []
		}

		/// The graph of `holeType`'s places in the tree `generator` roots, read from the graph of every hole type's places,
		/// which one walk of the tree reads the first time a hole type asks (`SeamDeclarationGraph.PlacesOfEveryHoleType`).
		/// A place of a hole type is a site of it, or a call that hands up an inner enum of it. A fill is left out with what it
		/// builds. A call's case holds the inner enum and nothing its type binds before the call: no generated fill could read
		/// such a value, since the inner seam's root dispatcher takes no parameters, and a fill that would read what this seam
		/// binds before the call is `boundByPassingUpSeam`. Nor is the call a carrier in the start order (`SeamDeclarationGraph`).
		/// A call's fill is entered where it is the fill whose code is generated and builds a place or a call that passes one
		/// up (`reenteredFillsByKey`): an edge from the call's declaration to the type the fill builds.
		mutating func placeHolding(of holeType: SeamSignature.HoleType, inTreeRootedAt generator: ScopeGenerator, reenteredFillsByKey: [String: ScopeGenerator]) -> SeamDeclarationGraph.PlaceHolding {
			if let placesOfEveryHoleType {
				return placesOfEveryHoleType.placeHolding(of: holeType)
			}
			// The graph reads only a child with a property (`SeamDeclarationGraph.PlacesOfEveryHoleType`), which a fill has none of.
			let placesOfEveryHoleType = SeamDeclarationGraph.PlacesOfEveryHoleType(treeRootedAt: generator, childPlaces: { parent, child in
				// A site whose owner and property hold no hole type falls through: a declaration that holds no place and builds no
				// type, so the graph adds no edge for it.
				if let site = child.holeSite,
				   let owner = parent.builtInstantiable?.concreteInstantiable,
				   let holeType = holeTypeByOwnedProperty[SeamDeclarationGraph.TypeAndProperty(type: owner, property: site.property)]
				{
					return .site(holeType: holeType, kind: site.property.propertyType.isSendable ? .sendablePlace : .plainPlace)
				}
				var places = [(holeType: SeamSignature.HoleType, kind: SeamDeclarationGraph.PlaceKind)]()
				if !child.passedUpHoles.isEmpty {
					let handedUp = innerKeysHandedUp(by: child)
					for holeType in handedUp.holeTypes {
						if handedUp.keysByHoleType[holeType]?.plain != nil {
							places.append((holeType, child.buildsInSendableFunction ? .sendablePlace : .plainPlace))
						}
						if handedUp.keysByHoleType[holeType]?.sendable != nil {
							places.append((holeType, .sendableBeneathPlace))
						}
					}
				}
				return .declaration(inSendableFunction: child.buildsInSendableFunction, places: places)
			}, fillEdges: { _, call in
				var fillEdges = [(edge: SeamDeclarationGraph.FillEdge, fulfiller: ScopeGenerator)]()
				for fill in call.children {
					guard fill.fillEmitsCode,
					      DependencyTreeGenerator.leadsToPlace(fill, reenteringFills: reenteredFillsByKey),
					      let fulfiller = fill.children.first,
					      let innerKey = DependencyTreeGenerator.filledRootKey(of: fill, in: call)
					else { continue }
					let inSendableFunction = call.buildsInSendableFunction || call.buildsInSendableFunction(ofFill: fill) || fulfiller.buildsInSendableFunction
					fillEdges.append((SeamDeclarationGraph.FillEdge(innerKey: innerKey, inSendableFunction: inSendableFunction, fulfillerBuildsInSendableFunction: fulfiller.buildsInSendableFunction), fulfiller))
				}
				// A call inside a fill that passes an enclosing call's fill by name re-enters it: an edge to the type that fill builds,
				// whose case on the calling type returns the called seam's or public mock's struct over that type's level, which the
				// enclosing call's level functions take.
				for reused in DependencyTreeGenerator.reenteredFills(by: call, in: reenteredFillsByKey) {
					guard let fulfiller = reused.children.first, let innerKey = DependencyTreeGenerator.filledRootKey(of: reused, in: call) else { continue }
					let inSendableFunction = call.buildsInSendableFunction || fulfiller.buildsInSendableFunction
					var edge = SeamDeclarationGraph.FillEdge(innerKey: innerKey, inSendableFunction: inSendableFunction, fulfillerBuildsInSendableFunction: fulfiller.buildsInSendableFunction)
					edge.reusesEnclosingFill = true
					fillEdges.append((edge, fulfiller))
				}
				return fillEdges
			})
			self.placesOfEveryHoleType = placesOfEveryHoleType
			return placesOfEveryHoleType.placeHolding(of: holeType)
		}

		/// The inner enums a call hands up of each hole type: of each family, the enum of its first builder of the hole type
		/// and family whose enum reaches a place the call passes up, and the hole types in the order of the builders. Found once
		/// per call, not once per hole type.
		mutating func innerKeysHandedUp(by call: ScopeGenerator) -> InnerKeysHandedUp {
			let key = ObjectIdentifier(call)
			if let handedUp = innerKeysHandedUpByCall[key] {
				return handedUp
			}
			var handedUp = InnerKeysHandedUp()
			if let calledBuilders = call.calledBuilders {
				let passedUpSites = Set(call.passedUpHoles.map(\.site))
				let calledEnumsByKey = calledBuilders.enumsByKey
				for builder in calledBuilders.builders {
					let innerKey = builder.enumKey
					let keys = handedUp.keysByHoleType[innerKey.holeType]
					guard (innerKey.isSendable ? keys?.sendable : keys?.plain) == nil,
					      !SeamSignature.ScopeEnum.sitesReached(from: innerKey, in: calledEnumsByKey).isDisjoint(with: passedUpSites)
					else { continue }
					if keys == nil {
						handedUp.holeTypes.append(innerKey.holeType)
					}
					handedUp.keysByHoleType[innerKey.holeType, default: (nil, nil)].plain = innerKey.isSendable ? keys?.plain : innerKey
					handedUp.keysByHoleType[innerKey.holeType, default: (nil, nil)].sendable = innerKey.isSendable ? innerKey : keys?.sendable
				}
			}
			innerKeysHandedUpByCall[key] = handedUp
			return handedUp
		}

		/// The inner enums a call hands up (`innerKeysHandedUp(by:)`).
		struct InnerKeysHandedUp {
			/// The plain and the `@Sendable` inner enum the call hands up of each hole type it hands one up of.
			var keysByHoleType = [SeamSignature.HoleType: (plain: SeamSignature.ScopeEnum.Key?, sendable: SeamSignature.ScopeEnum.Key?)]()
			/// The hole types of `keysByHoleType`, in the order of the call's builders.
			var holeTypes = [SeamSignature.HoleType]()
		}

		/// `build`'s case properties in the order `scopeEnumsByType` drafts a type's cases in – the type's declaration order,
		/// then the children a public mock's root builds that the type does not declare, in the order it builds them – with the
		/// positions of each property in that order, computed once per build.
		mutating func caseProperties(of build: ScopeGenerator, instantiable: Instantiable) -> CaseProperties {
			let key = ObjectIdentifier(build)
			if let caseProperties = casePropertiesByBuild[key] {
				return caseProperties
			}
			var properties = instantiable.dependencies.map(\.property)
			let declaredProperties = Set(properties)
			for child in build.children {
				guard let property = child.property, !declaredProperties.contains(property) else { continue }
				properties.append(property)
			}
			var positionsByProperty = [Property: [Int]]()
			for (position, property) in properties.enumerated() {
				positionsByProperty[property, default: []].append(position)
			}
			let caseProperties = CaseProperties(properties: properties, positionsByProperty: positionsByProperty)
			casePropertiesByBuild[key] = caseProperties
			return caseProperties
		}

		/// A build's case properties (`caseProperties(of:instantiable:)`).
		struct CaseProperties {
			let properties: [Property]
			let positionsByProperty: [Property: [Int]]
		}

		/// The hole type of each place, by its owner and property.
		private let holeTypeByOwnedProperty: [SeamDeclarationGraph.TypeAndProperty: SeamSignature.HoleType]
		private var placesOfEveryHoleType: SeamDeclarationGraph.PlacesOfEveryHoleType?
		private var innerKeysHandedUpByCall = [ObjectIdentifier: InnerKeysHandedUp]()
		private var casePropertiesByBuild = [ObjectIdentifier: CaseProperties]()

		/// What `type` binds before each of its properties (`levelDeclarations`), read from `build`, the first build any hole
		/// type reads: the level's one sequence, computed once per type, of which every case of every hole type takes a prefix
		/// (`SeamCarrierValues` cuts a carrier level's runs from it). Every build of a type that closes no cycle binds the same
		/// declarations in the same order, since the order is the type's.
		mutating func declarations(
			of build: ScopeGenerator,
			as type: TypeDescription,
			seam: Instantiable,
			parameters: [SeamSignature.Parameter],
			bindsReceivesAgain: Bool,
			seamTypeAccess: AccessLevel,
			proof: TypeAccessProof,
			instantiables: [TypeDescription: Instantiable],
		) -> [SeamSignature.Hole.Field] {
			if let declarations = declarationsByType[type] {
				return declarations
			}
			let isSeamRoot = type == seam.concreteInstantiable
			let declarations = DependencyTreeGenerator.levelDeclarations(
				of: build,
				isSeamRoot: isSeamRoot,
				bindsReceivesAgain: bindsReceivesAgain,
				labelsNamedApart: isSeamRoot ? labelsNoRootChildDeclares : [],
				cycleParameters: cycleParametersOfAnyBuild[type, default: []],
				reboundProperties: reboundPropertiesOfAnyBuild[type, default: []],
				receivesBoundAgain: receivesBoundAgainOfAnyBuild[type, default: []],
				seam: seam,
				parameters: parameters,
				seamTypeAccess: seamTypeAccess,
				proof: proof,
				instantiables: instantiables,
			)
			declarationsByType[type] = declarations
			return declarations
		}

		/// `build`'s children by their properties, the first of each with its index, which tells it apart from a sibling that
		/// holds the same generator, computed once per build.
		mutating func childrenByProperty(of build: ScopeGenerator) -> [Property: (index: Int, generator: ScopeGenerator)] {
			let key = ObjectIdentifier(build)
			if let children = childrenByPropertyByBuild[key] {
				return children
			}
			let children = Dictionary(build.children.enumerated().compactMap { index, child in child.property.map { ($0, (index: index, generator: child)) } }, uniquingKeysWith: { first, _ in first })
			childrenByPropertyByBuild[key] = children
			return children
		}

		private let cycleParametersOfAnyBuild: [TypeDescription: [LevelCycleParameter]]
		private let reboundPropertiesOfAnyBuild: [TypeDescription: [Property]]
		private let receivesBoundAgainOfAnyBuild: [TypeDescription: [Property]]
		private let labelsNoRootChildDeclares: Set<String>
		private var declarationsByType = [TypeDescription: [SeamSignature.Hole.Field]]()
		private var childrenByPropertyByBuild = [ObjectIdentifier: [Property: (index: Int, generator: ScopeGenerator)]]()
	}

	/// What the scope `build` builds declares, in the order it binds the declarations, each as a field of a payload struct:
	/// for the seam's root, its parameters, then its children but those of `labelsNamedApart`, which a mock's root does not
	/// declare as children: the labels its root level's fields hold and those it binds only under names apart
	/// (`PublicMockRootLevel`); for any other type, its `@Forwarded` properties, then the
	/// `cycleParameters` of its builder function that any build of the type declares, which hide every other declaration
	/// of their labels, then the `reboundProperties` and `receivesBoundAgain` of any build of the type, then its children. A
	/// case's payload holds those its type binds before the case's property. A mock's root (`bindsReceivesAgain`) declares a
	/// child it promotes as the non-optional value it binds (`mockRootBinding(ofChild:of:)`).
	private static func levelDeclarations(
		of build: ScopeGenerator,
		isSeamRoot: Bool,
		bindsReceivesAgain: Bool,
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
				let declaringType = firstReceiver?.declaringType ?? seam.concreteInstantiable
				let declarationLocation = firstReceiver?.declarationLocation ?? seam.dependencies.first { $0.property == parameter.property }?.declarationLocation ?? seam.declarationLocation
				fields.append(SeamSignature.Hole.Field(
					property: parameter.property,
					access: parameter.tierAccess,
					accessCause: parameter.accessCause,
					declaringType: declaringType,
					declarationLocation: declarationLocation,
					isReceivedOnlyIfAvailable: parameter.isOnlyIfAvailable,
					deferral: parameter.deferral,
					// The memo a route hands a fill of a place inside a fill of this seam's place is this parameter's
					// (`DependencyTreeGenerator.findingsOfFill`), as `fields(of:)` records it. A public mock's root level binds a receive
					// again where its nearest declaration does not provide its form, so its parameters say nothing about the forms a
					// fill may receive (the deliberate gap of contract rule 7 in `seam-and-mock-contract.md`).
					seamParameterOrigin: bindsReceivesAgain ? nil : SeamSignature.Hole.Field.SeamParameterOrigin(of: parameter, of: seam, declaringType: declaringType, declarationLocation: declarationLocation),
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
			guard let childProperty = child.generator.property, !labelsNamedApart.contains(childProperty.label) else { continue }
			// A mock's root binds what it promotes as the non-optional value it builds.
			let property = isSeamRoot && bindsReceivesAgain ? mockRootBinding(ofChild: childProperty, of: instantiable) : childProperty
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

	/// What names a payload binding: the node of the seam's graph it is bound at, whatever path leads there. The case of
	/// `property` in the enum of `type` (the `@Sendable` enum's where `isSendableEnum`), named `caseName`, bound
	/// `bindingOffset` properties beneath the property's own scope (a member called at the top of a builder function the
	/// step's property leads into).
	struct BindingNode: Hashable {
		let type: TypeDescription
		let isSendableEnum: Bool
		let property: Property
		let caseName: String
		let bindingOffset: Int

		/// A spelling that orders nodes, which no two nodes share.
		var sortKey: String {
			"\(type.asSource) \(isSendableEnum) \(property.asSource) \(caseName) \(bindingOffset)"
		}
	}

	/// The names the seam's tree binds the struct each member call of a builder struct on the routes to its places returns
	/// under, by the builder's label, before the case's property, the last of its key's path in `nodesByStem`, is built: one
	/// per node of the seam's graph and label, `__safeDI_<label>_<case>`, with `_` appended while a name in `reservedNames`,
	/// or another node's that some path binds in the same scope, above it or beneath it, has it. A name is a function of its
	/// node, never of the path to it: every path binds a node under one name, apart from every name any path binds beside
	/// it, above it or beneath it. A node recurs on one path only across a fill that builds its type again (a cycle-closing
	/// scope re-enters the function built at the level's first opening and binds nothing of its own); the fill's functions
	/// read the structs they are handed, so its binding hides the outer one only where the inner one is read, as a value the
	/// fill's tree binds again under its label does. The nodes are named shortest path first, then in the order of their
	/// spelling, so no name depends on the order the routes are met in. A key bound at several nodes (one binding serves them
	/// all) is named by the node that sorts first.
	static func memberBindingNames(
		of nodesByStem: [String: [ValuesBindingKey: Set<BindingNode>]],
		reservedNames: Set<String>,
	) -> [String: [ValuesBindingKey: String]] {
		struct Binding: Hashable {
			let stem: String
			let node: BindingNode
		}
		var bindingByKeyByStem = [String: [ValuesBindingKey: Binding]]()
		var pathsByBinding = [Binding: [[Property]]]()
		for (stem, nodesByKey) in nodesByStem {
			for (key, nodes) in nodesByKey where !key.path.isEmpty {
				guard let node = nodes.min(by: { $0.sortKey < $1.sortKey }) else { continue }
				let binding = Binding(stem: stem, node: node)
				bindingByKeyByStem[stem, default: [:]][key] = binding
				pathsByBinding[binding, default: []].append(key.path)
			}
		}
		// Each binding is spelled once, not once for every pair compared.
		let keyedBindings = pathsByBinding.map { binding, paths in
			(binding: binding, shortestPath: paths.map(\.count).min() ?? 0, sortKey: binding.node.sortKey + " " + binding.stem)
		}
		let orderedBindings = keyedBindings.sorted { first, second in
			first.shortestPath != second.shortestPath ? first.shortestPath < second.shortestPath : first.sortKey < second.sortKey
		}.map(\.binding)
		// The names bound at each path, before its last property is built; in each scope; and anywhere beneath each path.
		var namesByPath = [[Property]: Set<String>]()
		var namesByScope = [[Property]: Set<String>]()
		var namesBeneathPath = [[Property]: Set<String>]()
		var nameByBinding = [Binding: String]()
		for binding in orderedBindings {
			let paths = pathsByBinding[binding, default: []]
			// The names are released before this binding's is inserted, which would copy the sets they share otherwise.
			let name: String = {
				// Each name is asked of each set in turn, never of their union: a union made for every binding holds every
				// payload's name, so naming the payloads grew with the square of the seam's places.
				var sets = [reservedNames]
				for path in paths {
					sets.append(namesByScope[Array(path.dropLast()), default: []])
					sets += (1..<path.count).compactMap { namesByPath[Array(path.prefix($0))] }
					sets += namesBeneathPath[path].map { [$0] } ?? []
				}
				let taken = GenerationWork.taking(NamesConsultedInTurn(sets), by: .namingValuesBindings)
				var name = ScopeGenerator.functionName(toBuildPropertyNamed: "\(binding.stem)_\(binding.node.caseName)")
				while taken.contains(name) {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				return name
			}()
			nameByBinding[binding] = name
			for path in paths {
				namesByPath[path, default: []].insert(name)
				namesByScope[Array(path.dropLast()), default: []].insert(name)
				for length in 1..<path.count {
					namesBeneathPath[Array(path.prefix(length)), default: []].insert(name)
				}
			}
		}
		var namesByStem = [String: [ValuesBindingKey: String]]()
		for (stem, bindingByKey) in bindingByKeyByStem {
			for (key, binding) in bindingByKey {
				namesByStem[stem, default: [:]][key] = nameByBinding[binding]
			}
		}
		return namesByStem
	}

	/// The fills in the tree `root` roots whose code is generated and whose tree leads to a place, by key
	/// (`ScopeGenerator.fillKey`): those a call inside a fill of the same call can pass by name and so re-enter. A fill leads
	/// to a place where its tree builds one or a call that passes one up, or holds a call that re-enters such a fill, found as
	/// a fixed point, so a chain of re-entries leads there too.
	static func emittingFillsByKey(inTreeRootedAt root: ScopeGenerator) -> [String: ScopeGenerator] {
		var candidatesByKey = [String: ScopeGenerator]()
		var generatorsToVisit = [root]
		while let generator = generatorsToVisit.popLast() {
			guard generator.containsBuildSite || generator.passesUpBuilder || generator.holdsCallReenteringEnclosingFill else { continue }
			if let key = generator.fillKey, generator.fillEmitsCode {
				candidatesByKey[key] = generator
			}
			generatorsToVisit += generator.children
		}
		var fillsByKey = candidatesByKey.filter { $0.value.containsBuildSite || $0.value.passesUpBuilder }
		var foundFill = true
		while foundFill {
			foundFill = false
			for (key, fill) in candidatesByKey where fillsByKey[key] == nil && Self.holdsCallReentering(fillsByKey, in: fill) {
				fillsByKey[key] = fill
				foundFill = true
			}
		}
		return fillsByKey
	}

	/// Whether the tree of `generator` holds a call that passes one of `fillsByKey` by name.
	private static func holdsCallReentering(_ fillsByKey: [String: ScopeGenerator], in generator: ScopeGenerator) -> Bool {
		var generatorsToVisit = [generator]
		while let visited = generatorsToVisit.popLast() {
			guard reenteredFills(by: visited, in: fillsByKey).isEmpty else { return true }
			generatorsToVisit += visited.children.filter(\.holdsCallReenteringEnclosingFill)
		}
		return false
	}

	/// The fills of `fillsByKey` that `call`, a call inside a fill of an enclosing call, passes by name and so re-enters, in the
	/// order the call takes its builders.
	static func reenteredFills(by call: ScopeGenerator, in fillsByKey: [String: ScopeGenerator]) -> [ScopeGenerator] {
		call.enclosingFillsPassed.compactMap { fillsByKey[$0.key] }
	}

	/// Whether the tree of `fill`, a fill whose code is generated, leads to a place: it builds a place or a call that passes
	/// one up, or is among `fillsByKey` (`emittingFillsByKey(inTreeRootedAt:)`).
	static func leadsToPlace(_ fill: ScopeGenerator, reenteringFills fillsByKey: [String: ScopeGenerator]) -> Bool {
		fill.containsBuildSite || fill.passesUpBuilder || fill.fillKey.map { fillsByKey[$0] != nil } == true
	}

	/// The key of the called seam's or public mock's root enum whose builder reaches the place `fill` fills, its own or one it
	/// passes up from a seam it calls, so one case stands for every place of the call's builder, and the struct it returns
	/// walks every level of every seam on the place's route; the key of the root enum of the seam whose tree holds the place
	/// where no builder of the call reaches it. A value the passing-up seam binds before its call is no level of it, as no
	/// generated fill reads one (`boundByPassingUpSeam`).
	static func filledRootKey(of fill: ScopeGenerator, in call: ScopeGenerator) -> SeamSignature.ScopeEnum.Key? {
		guard let hole = fill.fillHole else { return nil }
		guard let calledBuilders = call.calledBuilders else { return SeamSignature.ScopeEnum.rootKey(of: hole) }
		return calledBuilders.keyOfFirstBuilderReaching(hole) ?? SeamSignature.ScopeEnum.rootKey(of: hole)
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

/// A route a seam's or a public mock's enums nested by type compute, beside the same route rebuilt from its steps by edge
/// (`DependencyTreeGenerator.ScopeEnumsByType.routeStepByEdge`), for the tests: a step is a function of its edge and the
/// length of the path its member is bound at, which the tests check on every route until the seam's tree reads the steps
/// by edge.
public struct SeamRouteStepObservation: Sendable {
	public let seamType: TypeDescription
	/// The properties from the seam's root to the place or the call the route leads to.
	public let sitePath: [Property]
	/// Each step the route computed, the place's or the call's own included, with its member call.
	public let computed: [SeamRouteStepAndMember]
	/// The same steps, each read from its edge's step at its binding path length.
	public let rebuilt: [SeamRouteStepAndMember]
}

/// A step of a route with the member call it makes, which only the seam's own tree reads and no module info file stores
/// (`SeamSignature.Hole.RouteStep.Member`).
public struct SeamRouteStepAndMember: Sendable {
	public let step: SeamSignature.Hole.RouteStep
	public let member: SeamSignature.Hole.RouteStep.Member?

	/// This step and its member call bound at the property `length` properties from the seam's root lead to: the only part
	/// of either the path it is on decides.
	func atBindingPathLength(_ length: Int) -> Self {
		Self(step: step.atBindingPathLength(length), member: member?.atBindingPathLength(length))
	}
}
