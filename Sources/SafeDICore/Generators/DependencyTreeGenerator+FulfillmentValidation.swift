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
	/// Validates scopes for cycles and optionally for unfulfillable properties.
	/// When `cyclesOnly` is true, unfulfillable property collection is skipped —
	/// used for mock-only types where unfulfillable received properties are expected
	/// (they become required mock parameters).
	/// - Parameters:
	///   - additionalMockRootScopes: The scopes of types whose mock is generated because `additionalMocksToGenerate`
	///     lists them. Their trees are validated for hidden received dependencies only, unless
	///     `validatesAdditionalMockRootsForCycles`.
	///   - receivedPropertiesCache: The results of `collectReceivedProperties` for scopes of
	///     `typeDescriptionToScopeMap`, which the mock validation fills.
	///   - validatesAdditionalMockRootsForCycles: Whether the trees of `additionalMockRootScopes` are validated for cycles too,
	///     each as the tree of a type with `generateMock` is, binding every property it receives from above it.
	func validatePropertiesAreFulfillable(
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		additionalMockRootScopes: Set<Scope> = [],
		receivedPropertiesCache: inout ReceivedPropertiesCache,
		cyclesOnly: Bool,
		excludingMockRootsOf typesExcludedAsMockRoots: Set<TypeDescription> = [],
		validatesAdditionalMockRootsForCycles: Bool = false,
	) throws {
		// Every tree is validated, and the errors are reported in source order, so neither depends on the order of the
		// trees; they are validated in type order regardless. A root receives nothing, so its tree binds nothing above
		// its own properties. A seam this module generates receives, as the parameters of its generated initializer,
		// every property its tree receives from outside it, so its tree is validated with those receivable at its
		// root, a required wrapper with its instance, as a declaration above the seam would be. Every one stays in
		// scope beneath a declaration of its label, as a declaration above the seam would, so a receive beneath such a
		// declaration is reported hidden from the seam's chain, whatever its optionality and whatever a caller holds:
		// the generated initializer passes each dependency by label, and is generated before any caller is known.
		var rootScopes = validatedRootInstantiables.sorted().compactMap { typeDescriptionToScopeMap[$0] }.map { scope in
			var receivedFromOutside = Set<Property>()
			if generatedSeamTypes.contains(scope.instantiable.concreteInstantiable) {
				for property in Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received {
					receivedFromOutside.insert(property)
					if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
						receivedFromOutside.insert(instanceProperty)
					}
				}
			}
			return ValidatedRootScope(
				scope: scope,
				boundProperties: [],
				isMock: false,
				receivedFromOutside: receivedFromOutside,
			)
		}
		// When checking cycles only (mock validation), also validate non-root types
		// that have generateMock enabled, and the listed ones where asked — they bypass
		// root entry points. Each one's mock binds every property its tree receives from
		// above it.
		if cyclesOnly {
			let rootInstantiableSet = Set(rootInstantiables)
			rootScopes += Set(typeDescriptionToScopeMap.values)
				.filter { scope in
					(scope.instantiable.generatesMock || validatesAdditionalMockRootsForCycles && additionalMockRootScopes.contains(scope))
						&& !rootInstantiableSet.contains(scope.instantiable.concreteInstantiable)
						&& !typesExcludedAsMockRoots.contains(scope.instantiable.concreteInstantiable)
				}
				// A type whose hand-written mock is not passed some of its dependencies has two scopes, which only
				// identity tells apart: the full one first, then the one its hand-written mock builds.
				.sorted { ($0.instantiable.concreteInstantiable, $0.dependenciesLeftOut.count) < ($1.instantiable.concreteInstantiable, $1.dependenciesLeftOut.count) }
				.map { scope in ValidatedRootScope(scope: scope, boundProperties: Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received, isMock: true) }
		}
		try validatePropertiesAreFulfillable(
			onRootScopes: rootScopes,
			additionalMockRootScopes: additionalMockRootScopes
				.sorted { $0.instantiable.concreteInstantiable < $1.instantiable.concreteInstantiable }
				.map { scope in ValidatedRootScope(scope: scope, boundProperties: Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received, isMock: !scope.instantiable.isRoot) },
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: cyclesOnly,
		)
	}

	/// Walks, for cycles only, the tree of each foreign seam whose initializer takes a builder, from the seam's root, as
	/// the seam's own module validates it where it sees the fulfilling declarations: this module's validated scopes
	/// build the seam inline, with the fills this module generates, but a tree rooted elsewhere reaches a fill with
	/// another stack, and can close a cycle earlier, on a lazy property above the seam, than the seam's own validation
	/// does. A fill is generated with the seam's stack, so a constant repeat the seam's walk rejects is rejected here,
	/// with the diagnostic that walk reports. A seam's tree is walked whether or not this module fills each of its holes:
	/// a hole this module does not fill has no scope, and the walk stops there. A seam whose builder another seam passes
	/// up is walked too, so every seam on the chain from the outermost one this module fills down to the one whose tree
	/// holds the hole is walked from its own root.
	func validateCyclesFromRootsOfForeignSeamsWithHoles(
		in typeDescriptionToScopeMap: [TypeDescription: Scope],
		foreignSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?],
		receivedPropertiesCache: inout ReceivedPropertiesCache,
	) throws {
		let seamTypesWithHoles = foreignSeamTypesWithHoles(among: foreignSeamRoots)
		guard !seamTypesWithHoles.isEmpty else { return }
		let rootScopes = seamTypesWithHoles.compactMap { typeDescriptionToScopeMap[$0] }.map { scope in
			var receivedFromOutside = Set<Property>()
			for property in Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received {
				receivedFromOutside.insert(property)
				if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
					receivedFromOutside.insert(instanceProperty)
				}
			}
			return ValidatedRootScope(scope: scope, boundProperties: [], isMock: false, receivedFromOutside: receivedFromOutside)
		}
		try validatePropertiesAreFulfillable(onRootScopes: rootScopes, typeDescriptionToScopeMap: typeDescriptionToScopeMap, cyclesOnly: true)
	}

	/// Walks, for cycles only, the trees a calling mock's production tree walks: where a mock tree calls another module's
	/// public mock that has places, the trees of the module's mock roots and of each called type, from its own root, built
	/// inline with this module's fills (`inlineTypeDescriptionToScopeMap`, the mock scope map built with no call), as
	/// production builds the called type's seam inline (`validateCyclesFromRootsOfForeignSeamsWithHoles`). The mock roots
	/// are walked first, then the called types in type order, as production walks its roots before the foreign seams.
	func validateCyclesOfCallsWithPlaces(
		publicMockCalls: [TypeDescription: PublicMockCall],
		inlineTypeDescriptionToScopeMap: [TypeDescription: Scope],
		additionalMocksToGenerate: Set<String>,
	) throws {
		let calledTypesWithPlaces = publicMockCalls.keys.filter { publicMockCalls[$0]?.holes.isEmpty == false }.sorted()
		guard !calledTypesWithPlaces.isEmpty else { return }
		// A cache of its own: the inline map's scopes are not the mock scope map's.
		var receivedPropertiesCache = ReceivedPropertiesCache()
		let additionalMockRootScopes: Set<Scope> = additionalMocksToGenerate.isEmpty ? [] : Set(
			typeDescriptionToFulfillingInstantiableMap.values.compactMap { instantiable in
				additionalMocksToGenerate.contains(instantiable.concreteInstantiable.asSource)
					? inlineTypeDescriptionToScopeMap[instantiable.concreteInstantiable]
					: nil
			},
		)
		// Another module's public mock type is not a mock root here: production walks such a type, a seam it builds inline, from
		// its own root with what its tree receives from outside it in scope (below), which a mock root's walk would report hidden
		// beneath a declaration of the label in its tree.
		let foreignPublicMockTypes = Set(seams.foreignPublicMocks.keys)
		do {
			try validatePropertiesAreFulfillable(
				typeDescriptionToScopeMap: inlineTypeDescriptionToScopeMap,
				additionalMockRootScopes: additionalMockRootScopes,
				receivedPropertiesCache: &receivedPropertiesCache,
				cyclesOnly: true,
				excludingMockRootsOf: foreignPublicMockTypes,
				// A listed type's mock fills the places of its calls as a `generateMock` type's does, so a cycle its tree closes
				// through a fill is real, and the mock would not compile: its tree, fills included, is walked for cycles as that
				// type's is, and reports the cycle its production twin reports.
				validatesAdditionalMockRootsForCycles: true,
			)
			// The walk above does not follow a received `Instantiator` to the scope it builds, which a fill's tree can close a
			// cycle through, so siblings that capture one another are judged after it, as production judges them.
			var childrenRequiringEachOtherValidation = ChildrenRequiringEachOtherValidation()
			let mockRootScopes = typeDescriptionToFulfillingInstantiableMap.values
				.filter { ($0.generatesMock || additionalMocksToGenerate.contains($0.concreteInstantiable.asSource)) && !foreignPublicMockTypes.contains($0.concreteInstantiable) }
				.map(\.concreteInstantiable)
				.sorted()
				.compactMap { inlineTypeDescriptionToScopeMap[$0] }
			try Self.validateChildrenDoNotRequireEachOther(
				inTreesRootedAt: mockRootScopes.uniqued(),
				cache: &receivedPropertiesCache,
				validation: &childrenRequiringEachOtherValidation,
			)
			let rootScopes = calledTypesWithPlaces.compactMap { inlineTypeDescriptionToScopeMap[$0] }.map { scope in
				var receivedFromOutside = Set<Property>()
				for property in Self.collectReceivedProperties(from: scope, cache: &receivedPropertiesCache).received {
					receivedFromOutside.insert(property)
					if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
						receivedFromOutside.insert(instanceProperty)
					}
				}
				return ValidatedRootScope(scope: scope, boundProperties: [], isMock: false, receivedFromOutside: receivedFromOutside)
			}
			try validatePropertiesAreFulfillable(onRootScopes: rootScopes, typeDescriptionToScopeMap: inlineTypeDescriptionToScopeMap, cyclesOnly: true)
		} catch let error as DependencyTreeGeneratorError {
			// A called type with places is built inline with the fills of its places, which its own module calls through its
			// builders, as production builds a foreign seam. Only membership in what each fill declares is read.
			let places = publicMockCalls.mapValues(\.holes)
			throw error.markingCyclesClosedInSeamFills(DependencyTreeGeneratorError.SeamFillDeclarations.ofFills(ofHolesOf: places, in: inlineTypeDescriptionToScopeMap))
		}
	}

	/// The error for each place among `places`, the places of one builder of `seam`'s – a seam, or a mock in its place – that
	/// builds `holeType` in the `@Sendable` family where `isSendable`, that forwards another value than the first place by
	/// location (`placesForwardingOtherValues(among:comparison:)`).
	static func placesForwardingOtherValuesErrors(
		of seam: Instantiable,
		places: [SeamSignature.Hole],
		holeType: SeamSignature.HoleType,
		isSendable: Bool,
		instantiables: [TypeDescription: Instantiable],
		declaredTypeNames: DeclaredTypeNames,
	) -> [DependencyTreeGeneratorError] {
		let comparison = ForwardedValueComparison(
			fillingType: holeType.instantiatedType,
			moduleNameByOwner: Dictionary(places.compactMap { place in instantiables[place.ownerType]?.moduleName.map { (place.ownerType, $0) } }, uniquingKeysWith: { first, _ in first }),
			declaredTypeNames: declaredTypeNames,
		)
		return placesForwardingOtherValues(among: places, comparison: comparison).map { place, reference in
			.seam(.init(seam: seam, kind: .placesForwardOtherValues(place: place, reference: reference, isSendable: isSendable)))
		}
	}

	/// The foreign seams whose initializers take a builder, in type order, among the signatures of the foreign seams this
	/// module's trees reach.
	private func foreignSeamTypesWithHoles(among foreignSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]) -> [TypeDescription] {
		guard !seams.foreignSeams.isEmpty else { return [] }
		return foreignSeamRoots.keys.filter { (foreignSeamRoots[$0] ?? nil)?.signature.holes.isEmpty == false }.sorted()
	}

	/// The generators, whose code is never started, of the tree of each foreign seam whose initializer takes a builder,
	/// from the seam's root over the validated scopes, which build the seam inline with the fills this module generates,
	/// in type order. `validateCycleLabelsArePassable` judges them: inline, the builder function a lazy cycle in the
	/// seam's tree closes on takes a label as a parameter whose forms include those a fill inside it receives, while the
	/// seam's own module, which cannot see the fill, judged the parameter without them. So a fill that receives the label
	/// in a form no one parameter carries together with the forms the seam's tree receives is rejected as its inline build
	/// is, with the same error. A hole this module does not fill has no scope, and its tree ends there.
	func inlineTreesOfForeignSeamsWithHoles(in typeDescriptionToScopeMap: [TypeDescription: Scope], validatedWorld: ValidatedWorld, foreignSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]) throws -> [ScopeGenerator] {
		var constructionMemo = ConstructionMemo()
		var generators = [ScopeGenerator]()
		// A tree no scope of which receives, in two forms, a label a scope of it declares holds no label to report, so its
		// generators, one per path through a lazy cycle, are not built (`canHoldUnpassableCycleLabel(inTreeRootedAt:)`).
		for scope in foreignSeamTypesWithHoles(among: foreignSeamRoots).compactMap({ typeDescriptionToScopeMap[$0] }) where Self.canHoldUnpassableCycleLabel(inTreeRootedAt: scope) {
			let (table, record) = validatedWorld.frozenScopeMap.freezing(rootScope: scope)
			try generators.append(record.createScopeGenerator(
				in: table,
				lazilyInstantiatedInstanceProperties: [],
				erasedToConcreteExistential: false,
				validatesForwardedProperties: false,
				declaredTypeNames: declaredTypeNames,
				constructionMemo: &constructionMemo,
			))
			GenerationLayerObservation.record(.inlineTreeOfForeignSeam(of: scope.instantiable.concreteInstantiable), inRunOf: seams.currentModule.moduleName)
		}
		return generators
	}

	/// An alias that a receive of its property resolves to: the nearest scope above the receiver that provides the
	/// property declares it with `@Received(fulfilledByDependencyNamed:ofType:)`.
	private struct ReceivableAlias {
		let fulfillingProperty: Property
		let onlyIfAvailable: Bool
		/// The `onlyIfAvailable` aliases from which an `onlyIfAvailable` alias is created in turn, in order: the alias
		/// of `fulfillingProperty` that the alias's assignment refers to, when it is `onlyIfAvailable` too – the one a
		/// receive of it resolves to where the alias is declared, declared by an enclosing scope, when the alias's own
		/// scope declares no property of that name and type (or its non-optional form); no alias of a scope renames
		/// another, since SafeDITool rejects that before it validates a tree that builds the scope – then the alias of
		/// that alias's fulfilling property, and so on. An `onlyIfAvailable` alias is created only where the alias it
		/// renames is, so a receive that requires this alias requires each of them. Empty for a required alias, whose
		/// declaring scope requires its fulfilling property itself (`Scope.requiredReceivedProperties`).
		let fulfillingOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
		/// What the last of `fulfillingOnlyIfAvailableAliases` – or the alias itself when there are none – is bound
		/// from where it is declared (see `AliasBinding`), or `nil` for an `onlyIfAvailable` alias bound to `nil`, which a
		/// required receive of it is passed. Always set for a required alias.
		let binding: AliasBinding?

		/// The declaration an alias is bound from: the nearest declaration of its fulfilling property's label where the
		/// alias is declared, which provides a form the alias reads and is not being built there.
		enum AliasBinding {
			/// A property a scope on the path instantiates or declares by an alias, which a required receive of the alias
			/// needs built before it.
			case built
			/// A property the tree is handed: one a scope on the path is forwarded, or that a seam's or a mock's root
			/// binds.
			case handed
		}

		/// The type that declares the alias.
		let declaringType: TypeDescription
		/// The type that declares the alias the property the alias is ultimately created from fulfills: the last of
		/// `fulfillingOnlyIfAvailableAliases`, or `declaringType` when there are none.
		let lastAliasDeclaringType: TypeDescription
		/// The property of the scope of `lastAliasDeclaringType`, followed by the properties of the scopes it is built
		/// inside, innermost first. Empty when a root is that scope.
		let lastAliasDeclaringInstantiationStack: [Property]
	}

	/// The scope at the root of a tree that `validatePropertiesAreFulfillable` walks.
	struct ValidatedRootScope {
		let scope: Scope
		/// The received properties the root's mock binds — as children it promotes, `mock()`
		/// parameters, or `SafeDIOverrides` entries — which enclose its whole tree. Empty for a
		/// root of the dependency tree, which receives nothing.
		let boundProperties: Set<Property>
		/// Whether the tree is validated as the tree of a mock that promotes what its tree receives from above it: the
		/// mock of a type that is not a root of the dependency tree. A root receives nothing, so a mock of it promotes
		/// nothing and builds its production tree, and the validation of mocks, which walks every root's tree, validates
		/// a root's tree as production too.
		let isMock: Bool
		/// The properties the tree receives from outside it that the root's generated initializer takes as parameters:
		/// those of a seam this module generates, which are receivable at its root as its own properties are, a
		/// required non-optional wrapper with its instance. Empty for every other root.
		var receivedFromOutside: Set<Property> = []
	}

	/// A map a scope hands each scope it builds: the map every scope built by one parent shares, and what the scope
	/// changes in it. A scope that builds hundreds of children, each building children of its own, would otherwise copy the
	/// whole map for each, which made the walk grow with the square of the children. It holds one shared map, which every
	/// scope beneath that changes little refers to, and the changes, which are folded into a new shared map once they are
	/// many: a map is copied only when it has grown by half since its last copy. A map smaller than
	/// `layeredMapMinimumSharedCount` is changed in place, copied when it is first changed as a plain dictionary is: a copy
	/// that small costs less than writing and consulting two maps.
	struct LayeredMap<Key: Hashable, Value> {
		init(_ map: [Key: Value]) {
			shared = map
			changes = [:]
		}

		/// The map every scope built by one parent shares.
		private var shared: [Key: Value]
		/// What the scopes from the one that made `shared` down to this one changed: a value, or `nil` for a key removed.
		private var changes: [Key: Value?]

		subscript(key: Key) -> Value? {
			get {
				if !changes.isEmpty, let change = changes[key] {
					change
				} else {
					shared[key]
				}
			}
			set {
				if changes.isEmpty, shared.count < DependencyTreeGenerator.layeredMapMinimumSharedCount {
					shared[key] = newValue
				} else {
					changes.updateValue(newValue, forKey: key)
				}
			}
		}

		subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
			self[key] ?? defaultValue()
		}

		/// Whether an entry of this map satisfies `predicate`, read without copying the map.
		func contains(where predicate: ((key: Key, value: Value)) -> Bool) -> Bool {
			changes.contains { key, value in value.map { predicate((key, $0)) } ?? false } || shared.contains { changes[$0.key] == nil && predicate($0) }
		}

		/// The greatest of what `measure` returns for the entries of this map, read without copying the map, or `nil` when it
		/// returns `nil` for each.
		func greatest<Measure: Comparable>(of measure: ((key: Key, value: Value)) -> Measure?) -> Measure? {
			var greatest: Measure?
			func consider(_ entry: (key: Key, value: Value)) {
				if let measured = measure(entry), greatest.map({ $0 < measured }) ?? true {
					greatest = measured
				}
			}
			for (key, value) in changes {
				if let value {
					consider((key, value))
				}
			}
			for entry in shared where changes[entry.key] == nil {
				consider(entry)
			}
			return greatest
		}

		/// This map as one dictionary, copied only where something changed.
		var asDictionary: [Key: Value] {
			var map = shared
			for (key, value) in changes {
				map[key] = value
			}
			return map
		}

		/// This map to hand the scopes a scope builds: its changes folded into a new shared map once they number more than
		/// half the shared map, so a lookup consults few changes and the copies grow with the map, not with the scopes.
		var compacted: Self {
			changes.count <= shared.count / 2 + 8 ? self : Self(asDictionary)
		}
	}

	/// The fewest entries a `LayeredMap` or `ReceivableProperties` shares before it keeps its changes apart rather than
	/// copying itself whenever it changes.
	static let layeredMapMinimumSharedCount = 32

	/// What the scopes a scope is built inside make available to it, shared and changed as a `LayeredMap` is (see there),
	/// with the shared properties of a large set by label, since the key of a clean subtree reads those of the few labels it
	/// reads. A set made smaller than `layeredMapMinimumSharedCount` is changed in place, as a plain set is, until a scope
	/// hands it on larger.
	struct ReceivableProperties: PropertyMembership {
		init(_ properties: Set<Property>) {
			shared = properties
			if properties.count >= DependencyTreeGenerator.layeredMapMinimumSharedCount {
				var sharedByLabel = [String: [Property]]()
				for property in properties {
					sharedByLabel[property.label, default: []].append(property)
				}
				self.sharedByLabel = sharedByLabel
			} else {
				sharedByLabel = nil
			}
			changes = [:]
		}

		/// The properties every scope built by one parent shares; for a small set, which keeps no changes apart, every
		/// property.
		private var shared: Set<Property>
		/// `shared`, by label, where it is large enough to keep its changes apart; `nil` for a small set.
		private let sharedByLabel: [String: [Property]]?
		/// What the scopes from the one that made `shared` down to this one changed: whether each property is receivable.
		private var changes: [Property: Bool]

		func contains(_ property: Property) -> Bool {
			changes.isEmpty ? shared.contains(property) : changes[property] ?? shared.contains(property)
		}

		mutating func insertIfAbsent(_ property: Property) -> Bool {
			guard sharedByLabel != nil else { return shared.insert(property).inserted }
			guard !contains(property) else { return false }
			changes[property] = true
			return true
		}

		/// These properties less `properties`.
		func withholding(_ properties: [Property]) -> Self {
			var withheld = self
			for property in properties {
				if sharedByLabel == nil {
					withheld.shared.remove(property)
				} else {
					withheld.changes[property] = false
				}
			}
			return withheld
		}

		func filter(_ isIncluded: (Property) -> Bool) -> Set<Property> {
			asSet.filter(isIncluded)
		}

		/// Those of these properties whose label is one of `labels`.
		func properties(labeledAnyOf labels: Set<String>) -> Set<Property> {
			// A small set keeps no changes apart.
			guard let sharedByLabel else { return shared.filter { labels.contains($0.label) } }
			var properties = Set<Property>()
			for label in labels {
				for property in sharedByLabel[label, default: []] where changes[property] == nil {
					properties.insert(property)
				}
			}
			for case let (property, true) in changes where labels.contains(property.label) {
				properties.insert(property)
			}
			return properties
		}

		var asSet: Set<Property> {
			var properties = shared
			for (property, isReceivable) in changes {
				if isReceivable {
					properties.insert(property)
				} else {
					properties.remove(property)
				}
			}
			return properties
		}

		/// See `LayeredMap.compacted`.
		var compacted: Self {
			if sharedByLabel == nil {
				shared.count < DependencyTreeGenerator.layeredMapMinimumSharedCount ? self : Self(shared)
			} else {
				changes.count <= shared.count / 2 + 8 ? self : Self(asSet)
			}
		}
	}

	/// A scope that `validatePropertiesAreFulfillable` has yet to validate, with what the scopes it is built inside
	/// give it.
	private struct ScopeToValidate {
		let scope: Scope
		/// The properties the scopes `scope` is built inside make available to it.
		let receivableProperties: ReceivableProperties
		/// The aliases declared above `scope` that a receive of their property resolves to.
		let receivableAliases: [Property: ReceivableAlias]
		/// The property each label names in `scope`: the one declared by the closest ancestor that declares the label.
		let closestDeclarationByLabel: LayeredMap<String, DependencyTreeGeneratorError.LabelDeclaration>
		/// For each label in `closestDeclarationByLabel`, how many scopes the declaring scope is built inside: `0` for the
		/// root of the tree.
		let closestDeclarationDepthByLabel: LayeredMap<String, Int>
		/// For each of `receivableProperties` that a scope the root's tree builds made receivable, how many scopes that
		/// scope is built inside, as `closestDeclarationDepthByLabel` counts them: the scope since which the property has
		/// been receivable on this path. A property the root's own scope offers has no entry. Empty in the validation of
		/// mocks, which never reads it.
		let receivableDepthByProperty: LayeredMap<Property, Int>
		/// The property `scope` is built for, as cycle validation sees it. `nil` at the root of the tree.
		let property: Property?
		/// The properties of the scopes `scope` is built inside, innermost first.
		let propertyStack: [Property]
		/// The concrete types of the scopes `scope` is built inside, innermost first, beside `propertyStack`.
		let parentTypeStack: [TypeDescription]
		/// The lazily instantiated properties on the instantiation stack, keyed by the constant each is validated as.
		let lazilyInstantiatedDeclarations: [Property: Property]
	}

	/// A cycle-closing scope, which builds the tree of the scope it closes on again, with what the scopes it is built inside
	/// give it there: what `validateTreeBuiltAgainByCycle` walks.
	private struct CycleClosingScopeToValidate {
		/// The scope the cycle closes on, whose tree is built again.
		let scope: Scope
		/// The property the cycle closes on, as cycle validation sees it.
		let property: Property
		/// The index in `propertyStack` of the scope the cycle closes on.
		let closedOnIndex: Int
		/// The scope the cycle-closing scope is a child of.
		let cycleClosingScopeParent: Scope
		/// The properties of the scopes the cycle-closing scope is built inside, innermost first.
		let propertyStack: [Property]
		/// The concrete types of those scopes, beside `propertyStack`.
		let parentTypeStack: [TypeDescription]
		/// The property each label names at the cycle-closing scope. The walk's own layered maps are kept as they are, since
		/// nearly every tree built again returns before it reads more than a few labels of them.
		let closestDeclarationByLabel: LayeredMap<String, DependencyTreeGeneratorError.LabelDeclaration>
		/// See `ScopeToValidate.closestDeclarationDepthByLabel`.
		let closestDeclarationDepthByLabel: LayeredMap<String, Int>
		/// The properties the scopes the cycle-closing scope is built inside make available to the scopes they build.
		let enclosingReceivableProperties: ReceivableProperties
		/// The properties the cycle-closing scope's own property makes receivable, which its tree is not given.
		let receivablePropertiesOfClosingProperty: [Property]
		/// The properties the scopes the cycle-closing scope is built inside make available to it, as the tree of any child
		/// is given them, without the property it builds. Computed only where the tree built again is walked, which is rare.
		var receivableProperties: Set<Property> {
			enclosingReceivableProperties.asSet.subtracting(receivablePropertiesOfClosingProperty)
		}

		/// See `ScopeToValidate.receivableDepthByProperty`.
		let receivableDepthByProperty: LayeredMap<Property, Int>
		/// The cycle-closing scope as the walk would validate it were its tree built here rather than called: its key tells
		/// whether the tree's first build, whose walk is in progress, is given what this one would be (see
		/// `cycle-validation.md`, "Clean subtrees").
		let asScopeToValidate: ScopeToValidate
	}

	/// What the walk of a tree in `validatePropertiesAreFulfillable` validates next. A cycle-closing scope's tree built
	/// again is walked in the cycle-closing scope's own turn, after the trees of the siblings declared before it, as the
	/// walk of that tree walks its own children. So the walk meets the chains of scopes that reach a receive depth first
	/// in declaration order: where two chains part, the one through the scope declared first, which is the one declared
	/// first in source, since a type declares its properties in one file. The first chain it meets is the one reported
	/// for a hidden receive (`hiddenReceivedProperties`), and the first error it throws, a receive of a declaration still
	/// being built among them, is the first in that order; neither depends on names or files.
	private enum TreeValidationStep {
		case scope(ScopeToValidate)
		case cycleClosingScope(CycleClosingScopeToValidate)
	}

	/// A received dependency that a closer declaration hides, as one root's tree reaches it: `hiddenReceivedProperties`
	/// records each once for each root, whatever number of chains of scopes reach it.
	private struct HiddenReceiveInTree: Hashable {
		/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
		let property: Property
		let declarationLocation: Dependency.DeclarationLocation?
		/// The closest declaration of the label, whose property differs from `property`.
		let hidingDeclaration: DependencyTreeGeneratorError.LabelDeclaration
		/// See `DependencyTreeGeneratorError.HiddenReceivedProperty.enclosingHidingDeclarations`. Chains of one tree that
		/// pass different declarations of the label above `hidingDeclaration` are reported apart, so relabeling every
		/// declaration the errors at the receive name leaves none between the receive and what provides it.
		let enclosingHidingDeclarations: [DependencyTreeGeneratorError.LabelDeclaration]
		let receiver: TypeDescription
		let root: TypeDescription
	}

	/// The chain of scopes a hidden receive is reported from.
	private struct HiddenReceiveChain {
		/// The types of the properties the chain's scopes are built for, innermost first. See
		/// `DependencyTreeGeneratorError.HiddenReceivedProperty.parentStack`.
		let parentStack: [TypeDescription]
		/// The concrete types of the chain's scopes, beside `parentStack`.
		let parentTypeStack: [TypeDescription]
	}

	/// A scope of a tree that a cycle-closing scope builds again, which `validateTreeBuiltAgainByCycle` has yet to walk, with
	/// what the scopes it is built inside give it there.
	private struct ScopeBuiltAgain {
		let scope: Scope
		/// The property `scope` is built for, as cycle validation sees it.
		let property: Property
		/// The properties of the scopes `scope` is built inside, innermost first: those the function built again builds, then
		/// those the cycle-closing scope that calls it is built inside.
		let propertyStack: [Property]
		/// The concrete types of the scopes `scope` is built inside, innermost first, beside `propertyStack`.
		let parentTypeStack: [TypeDescription]
		/// The property each label names in `scope`.
		let closestDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration]
		/// For each label in `closestDeclarationByLabel`, how many scopes the declaring scope is built inside, as
		/// `ScopeToValidate.closestDeclarationDepthByLabel` counts them along `propertyStack`.
		let closestDeclarationDepthByLabel: [String: Int]
		/// The properties the scopes `scope` is built inside make available to it.
		let receivableProperties: Set<Property>
		/// The labels whose closest declaration here the tree's first build did not see: declarations between the scope the
		/// cycle closes on and the cycle-closing scope, which bind the parameters of the function the cycle closes on,
		/// that no scope the function builds above `scope` declares again.
		let newLabels: Set<String>
		/// Those of `receivableProperties` that were not receivable where `scope` was first built: provided by a scope
		/// between, and by no scope the function builds above `scope`.
		let newReceivableProperties: Set<Property>
		/// How many of the properties on `propertyStack` belong to the first build of the scope the cycle closes on and the
		/// scopes it is built inside: the properties before them are being built inside that first build.
		let closedOnStackCount: Int
	}

	/// A tree that `validateTreeBuiltAgainByCycle` walks: where a cycle-closing scope builds the function it closes on
	/// again, and what is new to that function's tree there. Two cycle-closing scopes of one function beneath one scope,
	/// with the same new declarations and receivable properties, build the same tree again.
	private struct TreeBuiltAgain: Hashable {
		/// The scope the cycle-closing scope is a child of.
		let cycleClosingScopeParent: Scope
		/// The property the cycle closes on, as cycle validation sees it.
		let closedOnProperty: Property
		/// The closest declarations of the labels new to the tree.
		let newDeclarationByLabel: [String: DependencyTreeGeneratorError.LabelDeclaration]
		/// The properties receivable at the cycle-closing scope that were not where the tree was first built.
		let newReceivableProperties: Set<Property>
	}

	/// The property that `validateNoCycleInReceivedProperties` walked for a required receive of an `onlyIfAvailable`
	/// alias – the one the last alias the receive requires is created from, walked where that alias is declared – with
	/// everything that decides whether the walk throws.
	private struct WalkedAliasFulfillingProperty: Hashable {
		/// The property the last alias the receive requires is created from.
		let fulfillingProperty: Property
		/// The properties received through the aliases the receive requires, the receive's own first, as cycle
		/// validation sees them: the walk's received-property stack starts with them. Two aliases of one fulfilling
		/// property, or two chains of aliases that end in the same alias, walk differently.
		let receivedPropertyStack: [Property]
		/// The instantiation stack of the scope that declares the last alias the receive requires.
		let lastAliasDeclaringInstantiationStack: [Property]
		/// The properties the mock root forwards, which the walk does not follow unless a scope builds them, or `nil`
		/// for a tree validated as production.
		let mockRootForwardedProperties: Set<Property>?
	}

	/// What a root of `validatePropertiesAreFulfillable(onRootScopes:…)` gives every scope of its tree, beside the scope's
	/// own context, that a walk of a subtree reads.
	private struct CleanSubtreeRootContext: Hashable {
		let boundProperties: Set<Property>
		let mockRootForwardedProperties: Set<Property>?
		let validatesCycles: Bool
		let validatesHiddenProperties: Bool
	}

	/// What a walk of a scope's subtree reads of the declaration that is closest above it for a label: whether a receive is
	/// hidden (`LabelDeclaration.fulfills(anyOf:)`), an alias's binding, and the nearest declaration the cycle checks read.
	/// Where it is declared and by which type only a diagnostic reads.
	private struct CleanSubtreeDeclaration: Hashable {
		let property: Property
		let lazilyInstantiatedInstanceProperty: Property?
		let isForwarded: Bool
	}

	/// An element of the instantiation stack of a scope, root first, as a walk of its subtree can read it.
	private enum CleanSubtreeStackToken: Hashable {
		/// The labels the subtree reads whose closest declaration is made by the scope the next entry is built in.
		case declarations([String])
		/// An entry the subtree can compare a property with, with the concrete type of the scope built for it.
		case entry(Property, TypeDescription)
		/// One entry or more the subtree compares nothing with.
		case gap
	}

	/// An alias declared above a scope, as a walk of its subtree reads it: every field but what only a diagnostic reads.
	private struct CleanSubtreeAlias: Hashable {
		let fulfillingProperty: Property
		let onlyIfAvailable: Bool
		let fulfillingOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
		let binding: ReceivableAlias.AliasBinding?
		let declaringType: TypeDescription
		let lastAliasDeclaringType: TypeDescription
		/// The entries of the last alias's declaring instantiation stack the walk reads (see
		/// `declaringStackEntriesReadByFulfillingPropertyWalk(of:lastFulfillingProperty:)`): the stack differs on every
		/// path to the declaring scope.
		let declaringStackEntriesRead: [Property]
		/// The one entry of the instantiation stack a walk finds by the length of the last alias's declaring stack, the
		/// child of the declaring scope the subtree is built inside, where it is the property that alias is bound from:
		/// a receive that requires the alias is then built inside the alias's own fulfilling sibling.
		let fulfillingSiblingBeingBuilt: Property?
	}

	/// How the scopes a walk of a scope's subtree can reach use a label (see `CleanSubtreeLabelFacts`).
	private struct CleanSubtreeLabelUses: OptionSet, Hashable {
		let rawValue: UInt8
		/// A scope receives the label, or renames a property of it.
		static let read = Self(rawValue: 1 << 0)
		/// A scope receives the label only if available, or renames a property of it.
		static let readOtherThanByRequiredReceive = Self(rawValue: 1 << 1)
		/// A scope forwards the label.
		static let forwarded = Self(rawValue: 1 << 2)
		/// A scope builds a scope for an instantiator of the label.
		static let builtByInstantiator = Self(rawValue: 1 << 3)
		/// A scope declares the label any other way: a constant it builds, a rename, a hole.
		static let declaredOtherwise = Self(rawValue: 1 << 4)
	}

	/// What the scopes a walk of a scope's subtree can reach, its own included, do with each label: what tells which parts
	/// of its path a walk of a subtree that reaches a cycle of instantiators cannot read (`CleanSubtreeKeyLabels`).
	private struct CleanSubtreeLabelFacts {
		var usesByLabel = [String: CleanSubtreeLabelUses]()
		/// The properties the scopes forward or receive under each label.
		var forwardedOrReceivedPropertiesByLabel = [String: Set<Property>]()
		/// Every label a scope declares, or makes receivable where it was not: all but a required receive's.
		var declaredLabels = Set<String>()
		/// The labels `validateTreeBuiltAgainByCycle` can judge in the tree of a scope built for an instantiator.
		var labelsJudgedInTreesBuiltByInstantiators = Set<String>()
		/// The concrete types of the scopes.
		var builtTypes = Set<TypeDescription>()

		mutating func record(_ scope: Scope, labelsJudgedInTree: (Scope) -> Set<String>) {
			builtTypes.insert(scope.instantiable.concreteInstantiable)
			for dependency in scope.instantiable.dependencies {
				let label = dependency.property.label
				switch dependency.source {
				case let .received(onlyIfAvailable):
					usesByLabel[label, default: []].insert(.read)
					forwardedOrReceivedPropertiesByLabel[label, default: []].insert(dependency.property)
					if onlyIfAvailable {
						usesByLabel[label, default: []].insert(.readOtherThanByRequiredReceive)
						declaredLabels.insert(label)
					}
				case let .aliased(fulfillingProperty, _, _):
					usesByLabel[label, default: []].insert(.declaredOtherwise)
					usesByLabel[fulfillingProperty.label, default: []].formUnion([.read, .readOtherThanByRequiredReceive])
					declaredLabels.insert(label)
				case .forwarded:
					usesByLabel[label, default: []].insert(.forwarded)
					forwardedOrReceivedPropertiesByLabel[label, default: []].insert(dependency.property)
					declaredLabels.insert(label)
				case .instantiated:
					declaredLabels.insert(label)
				}
			}
			for providedProperty in scope.providedProperties {
				declaredLabels.insert(providedProperty.label)
			}
			for propertyToGenerate in scope.propertiesToGenerate {
				let label = propertyToGenerate.property.label
				declaredLabels.insert(label)
				switch propertyToGenerate {
				case let .instantiated(property, builtScope, _):
					if property.asValidatedForDependencyCycles.propertyType.isConstant {
						usesByLabel[label, default: []].insert(.declaredOtherwise)
					} else {
						usesByLabel[label, default: []].insert(.builtByInstantiator)
						labelsJudgedInTreesBuiltByInstantiators.formUnion(labelsJudgedInTree(builtScope))
					}
				case .hole, .aliased:
					usesByLabel[label, default: []].insert(.declaredOtherwise)
				}
			}
		}

		mutating func formUnion(_ other: Self) {
			usesByLabel.merge(other.usesByLabel) { $0.union($1) }
			forwardedOrReceivedPropertiesByLabel.merge(other.forwardedOrReceivedPropertiesByLabel) { $0.union($1) }
			declaredLabels.formUnion(other.declaredLabels)
			labelsJudgedInTreesBuiltByInstantiators.formUnion(other.labelsJudgedInTreesBuiltByInstantiators)
			builtTypes.formUnion(other.builtTypes)
		}
	}

	/// The labels the key of a scope holds (`cleanSubtreeKey(of:rootContextIndex:)`): `receivableLabels` for every scope,
	/// the others only for one that reaches a cycle of instantiators.
	private struct CleanSubtreeKeyLabels {
		/// The labels whose receivable properties a walk of the subtree looks up.
		let receivableLabels: Set<String>
		/// The labels a scope beneath receives or renames a property of, whose entries are compared with the property
		/// received; and those one forwards, kept though no comparison reads them.
		let labelsComparedWithEntries: Set<String>
		/// The concrete types of the scopes beneath, the scope's own included: an entry built for one is compared where a
		/// scope beneath builds that type again for the entry's property.
		let builtTypes: Set<TypeDescription>
		/// The labels only instantiators are built for beneath the scope, whose trees no scope beneath it can change the
		/// judgement of: an entry of one, on the scope's path, only ever ends the walk where an instantiator of it is met.
		let labelsOnlyInstantiatorsBuild: Set<String>
		/// The labels `validateTreeBuiltAgainByCycle` can judge in the trees those instantiators build.
		let labelsJudgedInTheirTrees: Set<String>
	}

	/// Everything a walk of `scope`'s subtree reads of the path it is reached by, projected to what that walk can read: the
	/// labels its scopes and the scopes they receive from declare or read (see `cycle-validation.md`, "Clean subtrees"). Two
	/// walks of one key judge every receive alike, so a subtree whose walk completed and found nothing is skipped on every
	/// other path with its key.
	private struct CleanSubtreeKey: Hashable {
		let scope: Scope
		let property: Property?
		let rootContextIndex: Int
		let receivableProperties: Set<Property>
		let closestDeclarations: [String: CleanSubtreeDeclaration]
		let stack: [CleanSubtreeStackToken]
		/// The aliases above of a label a scope beneath receives or renames a property of: a walk looks an alias up only
		/// by the property a scope requires, or by the property an `onlyIfAvailable` alias beneath is fulfilled by.
		let receivableAliases: [Property: CleanSubtreeAlias]
	}

	/// A scope whose required received properties `validateNoCycleInReceivedProperties` is walking.
	private struct ReceivedPropertyWalk {
		let requiredReceivedProperties: [Scope.RequiredReceivedProperty]
		/// The index in `requiredReceivedProperties` of the next property to walk.
		var nextIndex = 0
		let directParent: TypeDescription
		/// The received property whose scope this is, which ends the received-property stack while it is walked.
		/// `nil` for the scope the walk starts from.
		let walkedProperty: Property?
		/// Whether walking `walkedProperty` added its declaration to the declared received-property stack.
		let addedDeclaredReceivedProperty: Bool
		/// The properties on the received-property stack that this scope's walk has relied on so far.
		var stackPropertiesReliedOn = Set<Property>()
	}

	/// Validates the trees rooted at `rootScopes` for cycles and optionally for
	/// unfulfillable properties. See `validatePropertiesAreFulfillable(typeDescriptionToScopeMap:cyclesOnly:)`.
	/// Also validates, in production trees and in the trees of types that generate a mock, that no received
	/// dependency is hidden by a closer ancestor's property with the same label.
	/// - Parameter additionalMockRootScopes: The scopes of types whose mock is generated because
	///   `additionalMocksToGenerate` lists them. Their trees are validated for hidden received dependencies only.
	func validatePropertiesAreFulfillable(
		onRootScopes rootScopes: [ValidatedRootScope],
		additionalMockRootScopes: [ValidatedRootScope] = [],
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		cyclesOnly: Bool,
	) throws {
		var unfulfillableProperties = Set<DependencyTreeGeneratorError.UnfulfillableProperty>()
		/// Whether an `@Instantiated` declaration of `receivedProperty`'s non-optional form could fulfill it. One the tree
		/// of the type it builds requires, in either form, would close a dependency cycle wherever it is declared: the
		/// receive in that tree resolves to the declaration still building it. The tree is walked through the declarations
		/// the module's types fulfill, since a type no root reaches has no scope; only an unfulfillable receive asks, so the
		/// walk runs only on the failure path.
		/// - Parameters:
		///   - receiver: The scope that receives `receivedProperty`.
		///   - instantiationStack: The properties of `receiver` and of the scopes it is built inside, innermost first, as
		///     cycle validation sees them.
		///   - root: The type at the root of the tree.
		///   - closestDeclarationByLabel: The closest declaration of each label above `receiver`.
		func instantiatedDeclaration(
			of receivedProperty: Property,
			receivedBy receiver: Scope,
			instantiationStack: [Property],
			root: TypeDescription,
			closestDeclarationByLabel: LayeredMap<String, DependencyTreeGeneratorError.LabelDeclaration>,
		) -> DependencyTreeGeneratorError.UnfulfillableProperty.InstantiatedDeclaration {
			let declaration = DependencyTreeGeneratorError.UnfulfillableProperty.InstantiatedDeclaration.of(receivedProperty, among: typeDescriptionToFulfillingInstantiableMap)
			let declaredProperty = receivedProperty.asUnwrappedProperty
			// An erased instantiator's declaration names the type it builds, which the hint leaves to the user.
			guard case .possible = declaration,
			      !declaredProperty.propertyType.isErasedInstantiator,
			      let declaredInstantiable = typeDescriptionToFulfillingInstantiableMap[declaredProperty.typeDescription.asInstantiatedType]
			else { return declaration }
			// An instantiator's tree may receive that instantiator while it is still being built (see "Received builder loops"
			// in `cycle-validation.md`), so only a constant or a `LazilyInstantiated` declaration closes a cycle through itself.
			if !declaredProperty.propertyType.isInstantiator,
			   Self.treeRequires(declaredProperty, from: declaredInstantiable, typeDescriptionToFulfillingInstantiableMap: typeDescriptionToFulfillingInstantiableMap)
			{
				return .closesCycle
			}
			// Any declaration closes a cycle through the root's property for the chain, where the declaration's tree requires
			// it, it is a value (a cycle through an instantiator alone is a loop of builders, accepted), and no type of the
			// chain declares its label again: declared on the root, the two siblings require each other, and declared on any
			// type of the chain, the declaration's tree receives the root's property while it is still being built. Where a
			// type of the chain declares the label again, a declaration above that type would leave the tree's receive
			// unfulfilled, which is no cycle, so the advice is today's.
			guard let rootProperty = instantiationStack.last,
			      rootProperty.propertyType.isConstant,
			      let closestDeclaration = closestDeclarationByLabel[rootProperty.label],
			      closestDeclaration.declaringType == root,
			      closestDeclaration.property.asValidatedForDependencyCycles == rootProperty,
			      !receiver.instantiable.dependencies.contains(where: { $0.property.label == rootProperty.label }),
			      Self.treeRequires(rootProperty, from: declaredInstantiable, typeDescriptionToFulfillingInstantiableMap: typeDescriptionToFulfillingInstantiableMap)
			else { return declaration }
			return .closesCycleThrough(rootProperty)
		}
		/// The mocked types, each once, in type order, which `declarationsHidingReceiveInMocks(of:receivedBy:)` walks. Only
		/// an unfulfillable receive asks, so the list is made on the failure path.
		lazy var mockedInstantiables: [Instantiable] = {
			var mockedTypes = Set<TypeDescription>()
			return typeDescriptionToFulfillingInstantiableMap.values
				.filter { $0.generatesMock && mockedTypes.insert($0.concreteInstantiable).inserted }
				.sorted { $0.concreteInstantiable < $1.concreteInstantiable }
		}()
		var declarationsHidingReceiveByReceive = [Property: [TypeDescription: [DependencyTreeGeneratorError.UnfulfillableProperty.HidingDeclaration]]]()
		/// The declarations of `receivedProperty`'s label that the tree of a type whose mock is generated holds closest
		/// above a build of `receiver` and that do not provide the receive (its property, its unwrapped form, or a lazily
		/// instantiated wrapper of either): a declaration of the property above the mocked type, as the advice for an
		/// unfulfillable receive names, would leave the receive hidden in that mock. Each mocked type's tree is walked
		/// depth first in declaration order, each type once, so each hiding declaration is met once, in an order no set
		/// decides.
		func declarationsHidingReceiveInMocks(of receivedProperty: Property, receivedBy receiver: TypeDescription) -> [DependencyTreeGeneratorError.UnfulfillableProperty.HidingDeclaration] {
			if let memoized = declarationsHidingReceiveByReceive[receivedProperty]?[receiver] {
				return memoized
			}
			let providingProperties: Set<Property> = [receivedProperty, receivedProperty.asUnwrappedProperty]
			var hidingDeclarations = [DependencyTreeGeneratorError.UnfulfillableProperty.HidingDeclaration]()
			for mockedInstantiable in mockedInstantiables {
				var reachedTypes: Set<TypeDescription> = [mockedInstantiable.concreteInstantiable]
				var instantiablesToVisit: [(instantiable: Instantiable, closestDeclaration: DependencyTreeGeneratorError.UnfulfillableProperty.HidingDeclaration?)] = [(mockedInstantiable, nil)]
				while let instantiableToVisit = instantiablesToVisit.popLast() {
					let reachedInstantiable = instantiableToVisit.instantiable
					let closestDeclaration = instantiableToVisit.closestDeclaration
					if reachedInstantiable.concreteInstantiable == receiver,
					   let closestDeclaration,
					   !providingProperties.contains(closestDeclaration.property),
					   !providingProperties.contains(closestDeclaration.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding ?? closestDeclaration.property),
					   !hidingDeclarations.contains(closestDeclaration)
					{
						hidingDeclarations.append(closestDeclaration)
					}
					var childClosestDeclaration = closestDeclaration
					for dependency in reachedInstantiable.dependencies where dependency.property.label == receivedProperty.label {
						switch dependency.source {
						case .instantiated, .forwarded, .aliased:
							childClosestDeclaration = .init(property: dependency.property, declaringType: reachedInstantiable.concreteInstantiable)
						case .received:
							continue
						}
					}
					for dependency in reachedInstantiable.dependencies.reversed() {
						switch dependency.source {
						case .instantiated:
							if let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[dependency.asInstantiatedType],
							   reachedTypes.insert(builtInstantiable.concreteInstantiable).inserted
							{
								instantiablesToVisit.append((builtInstantiable, childClosestDeclaration))
							}
						case .received, .forwarded, .aliased:
							continue
						}
					}
				}
			}
			declarationsHidingReceiveByReceive[receivedProperty, default: [:]][receiver] = hidingDeclarations
			return hidingDeclarations
		}
		/// Each hidden receive each root's tree reaches, with the one chain of scopes it is reported from: of every chain of
		/// that tree that reaches it, the first the walk meets, which is the first in declaration order (see
		/// `TreeValidationStep`). One report per receive keeps what is reported from depending on how many paths reach it,
		/// which the walk of a tree a cycle builds again prunes.
		var hiddenReceivedProperties = [HiddenReceiveInTree: HiddenReceiveChain]()
		var renamesContradictingOwnProperties = Set<DependencyTreeGeneratorError.RenameContradictingOwnProperty>()
		/// How many times a walk recorded something, or met a judgement that reads more of its path than `CleanSubtreeKey`
		/// holds: a cycle, a receive of a property on the instantiation stack, or a tree a cycle builds again. A subtree whose
		/// walk leaves it unchanged is clean (see `cycle-validation.md`, "Clean subtrees"). Any new judgement in the walk must
		/// read only what the key holds, or add to this count where it fires.
		var memoBlockingEventCount = 0
		/// The properties a scope of `typeDescriptionToScopeMap` builds – instantiates, or renames another property to –
		/// as cycle validation sees them. Most walks never ask, so the set is built the first time one does.
		lazy var propertiesBuiltByAScope: Set<Property> = {
			var propertiesBuiltByAScope = Set<Property>()
			for scope in typeDescriptionToScopeMap.values {
				for dependency in scope.instantiable.dependencies {
					switch dependency.source {
					case .instantiated, .aliased:
						propertiesBuiltByAScope.insert(dependency.property.asValidatedForDependencyCycles)
					case .received, .forwarded:
						continue
					}
				}
			}
			return propertiesBuiltByAScope
		}()
		/// Whether a tree is handed `receivedProperty`, which the tree receives from above, rather than building it from
		/// `receivedPropertyScope`. A handed value comes from outside the tree – a `@Forwarded` value, or one a mock
		/// takes as a `mock()` parameter – so the dependencies of its type are no part of the tree: a cycle through them
		/// is reported where a tree builds that type. A property is built when a scope instantiates it or renames
		/// another property to it, wherever that scope is, since a receive of it may resolve there. A mock also builds
		/// what it promotes: a property its root does not forward and that the mock can build. A property that nothing
		/// builds or forwards is provided by nothing at all, which validation reports where it is received.
		/// - Parameter mockRootForwardedProperties: The properties the mock root forwards, or `nil` for a tree validated as
		///   production (see `ValidatedRootScope.isMock`), whose root promotes nothing.
		func isHanded(_ receivedProperty: Property, from receivedPropertyScope: Scope, mockRootForwardedProperties: Set<Property>?) -> Bool {
			if let mockRootForwardedProperties, !mockRootForwardedProperties.contains(receivedProperty), Self.mockCanBuild(receivedProperty, from: receivedPropertyScope) {
				false
			} else {
				!propertiesBuiltByAScope.contains(receivedProperty)
			}
		}
		/// Walks `requiredReceivedProperties`, which `directParent` requires, and, transitively, the required received
		/// properties of the scopes that fulfill them, throwing when one is `property` or is on `instantiationStack`.
		/// The walk descends depth first, in declaration order, and keeps its own stack of the scopes it is part way
		/// through, since a chain of received properties can be as long as the module has types. It does not descend
		/// into a property the tree is handed: see `isHanded`.
		///
		/// `stackPropertiesReliedOnByWalkedProperty` holds the received properties whose walk returned without
		/// throwing, each with the properties already on the received-property stack that the walk relied on: those
		/// it bailed out on as a cycle that isn't ours, and those that a skipped walk beneath it relied on. Walking
		/// such a property again along a stack that holds all of them checks a subset of what its first walk checked,
		/// because the stacks differ only in properties received before it, and any other property there can only
		/// make the walk bail out sooner. So that walk would also return without throwing, and skipping it reports the
		/// same error, from the same stack, as walking every path would. A property can rely only on properties that
		/// share a received cycle with it, so a property on no received cycle is walked once, rather than once for
		/// every path that leads to it.
		/// - Parameters:
		///   - declaredReceivedPropertyStack: The lazily instantiated properties on `receivedPropertyStack`, as
		///     they are declared. The walk sees each as the constant it stands for; the diagnostic names them.
		///   - lazilyInstantiatedDeclarations: The lazily instantiated properties on `instantiationStack`, keyed
		///     by the constant each is validated as.
		///   - mockRootForwardedProperties: See `isHanded`.
		///   - nearestDeclaration: The nearest declaration of a label above the scope whose receives the walk starts from,
		///     as `indexOfEntryClosedOn` reads it: a receive of a property on `instantiationStack` that a nearer declaration
		///     fulfills is walked as a property not on it. A property received transitively, by the scope of a type the walk
		///     follows, is judged with this scope's declarations rather than those where that type is built: that scope is
		///     validated with its own, so this walk accepts nothing it would reject, and only which of two diagnostics is
		///     reported first can follow from it.
		func validateNoCycleInReceivedProperties(
			_ requiredReceivedProperties: [Scope.RequiredReceivedProperty],
			directParent: TypeDescription,
			receivedPropertyStack: [Property],
			declaredReceivedPropertyStack: [Property],
			property: Property,
			instantiationStack: [Property],
			lazilyInstantiatedDeclarations: [Property: Property],
			mockRootForwardedProperties: Set<Property>?,
			nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
		) throws {
			// Most scopes require no received property.
			guard !requiredReceivedProperties.isEmpty else { return }
			// The stacks of the innermost walk, which each walk extends while it walks a received property's scope.
			var receivedPropertyStack = receivedPropertyStack
			var declaredReceivedPropertyStack = declaredReceivedPropertyStack
			var stackPropertiesReliedOnByWalkedProperty = [Property: Set<Property>]()
			var walks = [ReceivedPropertyWalk(
				requiredReceivedProperties: requiredReceivedProperties,
				directParent: directParent,
				walkedProperty: nil,
				addedDeclaredReceivedProperty: false,
			)]
			/// Ends the innermost walk, handing what it relied on to the walk that walked its property.
			func finishInnermostWalk() {
				let finishedWalk = walks.removeLast()
				if let walkedProperty = finishedWalk.walkedProperty {
					receivedPropertyStack.removeLast()
					if finishedWalk.addedDeclaredReceivedProperty {
						declaredReceivedPropertyStack.removeLast()
					}
					let childStackPropertiesReliedOn = finishedWalk.stackPropertiesReliedOn.subtracting([walkedProperty])
					stackPropertiesReliedOnByWalkedProperty[walkedProperty] = childStackPropertiesReliedOn
					walks[walks.count - 1].stackPropertiesReliedOn.formUnion(childStackPropertiesReliedOn)
				}
			}
			while !walks.isEmpty {
				let walkIndex = walks.count - 1
				let nextIndex = walks[walkIndex].nextIndex
				guard nextIndex < walks[walkIndex].requiredReceivedProperties.count else {
					finishInnermostWalk()
					continue
				}
				let requiredReceivedProperty = walks[walkIndex].requiredReceivedProperties[nextIndex]
				walks[walkIndex].nextIndex += 1
				let childProperty = requiredReceivedProperty.property.asValidatedForDependencyCycles
				// A receive of the instantiator being built is a loop through it alone, judged below as a receive of any entry of
				// the instantiation stack is. Through a received value it is a loop with that value on it: the value is received
				// from above the scope, so from the scope that declares the instantiator.
				guard childProperty != property || ScopeGenerator.isBuilder(property) && receivedPropertyStack.isEmpty else {
					throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
						instantiated: property,
						receivedPropertyChain: receivedPropertyStack + [childProperty],
						declarationLocation: requiredReceivedProperty.declarationLocation,
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: requiredReceivedProperty.property,
							validatedPropertiesInCycle: [property],
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: declaredReceivedPropertyStack,
						),
						requiredOnlyIfAvailableAliases: [],
					)
				}
				if childProperty == property {
					memoBlockingEventCount += 1
				}
				guard !receivedPropertyStack.contains(childProperty) else {
					// We've found a cycle, but it's not our cycle. Bail and let a future loop find this.
					// The remaining received properties on this scope go unwalked, so a later visit
					// along a stack without `childProperty` must walk this scope again.
					walks[walkIndex].stackPropertiesReliedOn.insert(childProperty)
					finishInnermostWalk()
					continue
				}
				let memoizedStackPropertiesReliedOn = stackPropertiesReliedOnByWalkedProperty[childProperty]
				let cycleIndex = instantiationStack.firstIndex(of: childProperty)
				if cycleIndex != nil {
					memoBlockingEventCount += 1
				}
				if let cycleIndex,
				   !Self.isFulfilledByNearerDeclaration([childProperty], thanEntryAt: cycleIndex, of: instantiationStack, nearestDeclaration: nearestDeclaration)
				{
					let instantiationProperties = Array(instantiationStack[0...cycleIndex])
					let propertiesInCycle = [childProperty]
						+ receivedPropertyStack.reversed()
						+ instantiationProperties
					try throwIfInvalidCycle(
						propertiesInCycle: propertiesInCycle,
						declaredProperty: requiredReceivedProperty.aliasProperty ?? requiredReceivedProperty.property,
						declarationLocation: requiredReceivedProperty.declarationLocation,
						directParent: walks[walkIndex].directParent,
						closingReceive: CycleClosingReceive(),
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: requiredReceivedProperty.property,
							validatedPropertiesInCycle: propertiesInCycle,
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: declaredReceivedPropertyStack,
						),
					)
				} else if let memoizedStackPropertiesReliedOn, memoizedStackPropertiesReliedOn.isSubset(of: receivedPropertyStack) {
					walks[walkIndex].stackPropertiesReliedOn.formUnion(memoizedStackPropertiesReliedOn)
				} else if let receivedPropertyScope = typeDescriptionToScopeMap[childProperty.typeDescription],
				          !isHanded(childProperty, from: receivedPropertyScope, mockRootForwardedProperties: mockRootForwardedProperties)
				{
					// A cycle back to `childProperty` itself lies within its walk, wherever that walk starts.
					receivedPropertyStack.append(childProperty)
					// Only the lazily instantiated receives are named by the diagnostic.
					let addsDeclaredReceivedProperty = childProperty != requiredReceivedProperty.property
					if addsDeclaredReceivedProperty {
						declaredReceivedPropertyStack.append(requiredReceivedProperty.property)
					}
					walks.append(ReceivedPropertyWalk(
						requiredReceivedProperties: receivedPropertyScope.requiredReceivedProperties,
						directParent: receivedPropertyScope.instantiable.concreteInstantiable,
						walkedProperty: childProperty,
						addedDeclaredReceivedProperty: addsDeclaredReceivedProperty,
					))
				}
			}
		}
		/// The forms in which an alias's fulfilling property, as cycle validation sees it, can be on an instantiation
		/// stack: as itself, unwrapped, and – in a mock, which promotes a received optional property as the
		/// non-optional value it builds – as the optional property promoted to build it.
		func formsOnStack(of validatedFulfillingProperty: Property) -> [Property] {
			if cyclesOnly {
				validatedFulfillingProperty.formsOnMockInstantiationStack
			} else {
				[validatedFulfillingProperty, validatedFulfillingProperty.asUnwrappedProperty]
			}
		}
		/// The fulfilling properties of the `onlyIfAvailable` aliases already walked by
		/// `validateNoCycleInReceivedProperties` – each the property the last alias a receive requires is created from –
		/// with what decides whether the walk throws (see `WalkedAliasFulfillingProperty`): it starts from that property
		/// with the properties received through the aliases on its stack, bails out on a chain that reaches a property on
		/// that stack, stops at a property the tree is handed, which depends on what the mock root forwards, and throws on
		/// a chain that reaches the last alias's declaring stack; the rest it is passed only names what an error reports.
		/// A walk that throws leaves the set, so a walk in the set returned without throwing, in whichever tree walked it,
		/// and walking it again would too. A receive of another alias of the same fulfilling property is walked again: a
		/// chain that bails out at one received property can reach the declaring stack from another.
		var walkedAliasFulfillingProperties = Set<WalkedAliasFulfillingProperty>()
		/// See `labelsRead(inTreeOf:)`. Filled only by walks of a tree a cycle builds again, so a graph without cycles pays nothing.
		var labelsReadByTreeRoot = [Scope: Set<String>]()
		/// The labels `validateTreeBuiltAgainByCycle`'s judgements read anywhere `scope` reaches: the label of each `@Received`
		/// property, and of the property each alias is fulfilled by rather than the alias's own, of `scope` and every scope it
		/// instantiates, through cycle-closing scopes too, since the walk continues through them.
		///
		/// Each answer is a whole pass over what `scope` reaches, with its own visited set. It must not reuse the answers of
		/// the pass in progress: inside a cycle, a scope's answer is only complete once the pass that visits it is, so a
		/// memo of partial answers records a scope as reading nothing that it reads through the cycle. The stack is explicit
		/// because a tree can be as deep as the module has types.
		func labelsRead(inTreeOf scope: Scope) -> Set<String> {
			if let labels = labelsReadByTreeRoot[scope] {
				return labels
			} else {
				var labels = Set<String>()
				var reachedScopes: Set<Scope> = [scope]
				var scopesToVisit = [scope]
				while let reachedScope = scopesToVisit.popLast() {
					for dependency in reachedScope.instantiable.dependencies {
						switch dependency.source {
						case .received:
							labels.insert(dependency.property.label)
						case let .aliased(fulfillingProperty, _, _):
							labels.insert(fulfillingProperty.label)
						case .instantiated, .forwarded:
							break
						}
					}
					for case let .instantiated(_, childScope, _) in reachedScope.propertiesToGenerate {
						if reachedScopes.insert(childScope).inserted {
							scopesToVisit.append(childScope)
						}
					}
				}
				labelsReadByTreeRoot[scope] = labels
				return labels
			}
		}
		/// Whether the tree `scope` builds reads a label new to it that a judgement of `validateTreeBuiltAgainByCycle` can fire
		/// for: one of `newLabels`, or the label of one of `newReceivableProperties`, that is not among
		/// `labelsNoJudgementFiresFor()`.
		func treeReadsAnything(ofTreeRootedAt scope: Scope, newLabels: some Collection<String>, newReceivableProperties: Set<Property>) -> Bool {
			guard !newLabels.isEmpty || !newReceivableProperties.isEmpty else { return false }
			let judgedLabels = labelsJudged(inTreeOf: scope)
			return newLabels.contains(where: judgedLabels.contains) || newReceivableProperties.contains { judgedLabels.contains($0.label) }
		}
		/// See `labelsJudged(inTreeOf:)`.
		var labelsJudgedByTreeRoot = [Scope: Set<String>]()
		/// The labels the tree `scope` builds reads (`labelsRead(inTreeOf:)`) that a judgement of `validateTreeBuiltAgainByCycle`
		/// can fire for (not among `labelsNoJudgementFiresFor()`): a tree built again is walked only where one of them is new.
		func labelsJudged(inTreeOf scope: Scope) -> Set<String> {
			if let labels = labelsJudgedByTreeRoot[scope] {
				return labels
			} else {
				let readLabels = labelsRead(inTreeOf: scope)
				let labels = readLabels.isEmpty ? readLabels : readLabels.subtracting(labelsNoJudgementFiresFor())
				labelsJudgedByTreeRoot[scope] = labels
				return labels
			}
		}
		/// See `labelsNoJudgementFiresFor()`.
		var memoizedLabelsNoJudgementFiresFor: Set<String>?
		/// The labels for which neither judgement of `validateTreeBuiltAgainByCycle` can fire anywhere in the trees of these
		/// roots, whatever is new where: every declaration of the label is one that every read of it accepts, as
		/// `recordHiddenReceives` accepts the closest declaration, so no declaration of it hides a read; and no tree built for a
		/// property of the label reads it, so no declaration of it is still being built where it is read. A value redeclared
		/// between screens with its own type, such as a flow's state, is such a label. The answer reads every scope the roots
		/// reach and no walk's outcome, so it is computed once, when a walk first finds a read label new.
		func labelsNoJudgementFiresFor() -> Set<String> {
			if let memoizedLabelsNoJudgementFiresFor {
				return memoizedLabelsNoJudgementFiresFor
			} else {
				var declarationsByLabel = [String: [(property: Property, lazilyInstantiatedInstanceProperty: Property?)]]()
				var acceptedPropertiesOfReadsByLabel = [String: [Set<Property>]]()
				var scopesBuiltByLabel = [String: [Scope]]()
				var reachedScopes = Set<Scope>()
				var scopesToVisit = [Scope]()
				for rootScope in rootScopes + additionalMockRootScopes where reachedScopes.insert(rootScope.scope).inserted {
					scopesToVisit.append(rootScope.scope)
				}
				while let reachedScope = scopesToVisit.popLast() {
					for dependency in reachedScope.instantiable.dependencies {
						// What `enterDeclarations` enters as a closest declaration.
						if reachedScope.createdProperties.contains(dependency.property) {
							declarationsByLabel[dependency.property.label, default: []].append((dependency.property, dependency.lazilyInstantiatedInstanceProperty))
						}
						// What `recordHiddenReceives` accepts for each read.
						switch dependency.source {
						case .received:
							acceptedPropertiesOfReadsByLabel[dependency.property.label, default: []].append([dependency.property, dependency.property.asUnwrappedProperty])
						case let .aliased(fulfillingProperty, _, onlyIfAvailable):
							acceptedPropertiesOfReadsByLabel[fulfillingProperty.label, default: []].append(onlyIfAvailable
								? Set(fulfillingProperty.formsReadByOnlyIfAvailableReceive)
								: [fulfillingProperty, fulfillingProperty.asUnwrappedProperty])
						case .instantiated, .forwarded:
							break
						}
					}
					for case let .instantiated(childProperty, childScope, _) in reachedScope.propertiesToGenerate {
						scopesBuiltByLabel[childProperty.label, default: []].append(childScope)
						if reachedScopes.insert(childScope).inserted {
							scopesToVisit.append(childScope)
						}
					}
				}
				var labels = Set<String>()
				for (label, acceptedPropertiesOfReads) in acceptedPropertiesOfReadsByLabel {
					let everyDeclarationIsAccepted = declarationsByLabel[label, default: []].allSatisfy { declaration in
						acceptedPropertiesOfReads.allSatisfy {
							$0.contains(declaration.property) || declaration.lazilyInstantiatedInstanceProperty.map($0.contains) == true
						}
					}
					if everyDeclarationIsAccepted, scopesBuiltByLabel[label, default: []].allSatisfy({ !labelsRead(inTreeOf: $0).contains(label) }) {
						labels.insert(label)
					}
				}
				memoizedLabelsNoJudgementFiresFor = labels
				return labels
			}
		}
		/// The walk skips nothing when a test or the graph fuzzer's oracle compares its outcome with and without the skip.
		let skipsCleanSubtrees = ValidationWalkObservation.skipsCleanSubtrees
		let validationWalkObserver = ValidationWalkObservation.observer
		/// The keys of the subtrees whose walk completed and left `memoBlockingEventCount` unchanged, shared by every root,
		/// since a key holds its root's context.
		var cleanSubtrees = Set<CleanSubtreeKey>()
		/// For each scope, how many times in a row a walk keyed it and no remembered walk had an equal key. At
		/// `cleanSubtreeMissLimit` a scope is keyed no more: where screens open each other without layers, a scope is reached
		/// along thousands of paths whose keys all differ, so every key and every comparison at a scope that closes a cycle on
		/// it was paid for nothing; and where erased screens are each reached along many paths with no cycle, every key
		/// differs as well. Shared by every root, as `cleanSubtrees`
		/// is; the walk visits roots and children in a fixed order, so the count is the same on every run, and it decides
		/// only which subtrees are walked again, never what a walk reports.
		var cleanSubtreeMissesInARowByScope = [Scope: Int]()
		/// Layered screens that open the first layer again find a scope's first equal key within three keys, and screens
		/// that are seams of their own modules within one; a scope of sixteen screens that open each other at random
		/// went up to 229 keys between two equal ones.
		let cleanSubtreeMissLimit = 8
		/// The scopes the walks reached, which alone are keyed when reached again.
		var validationWalkScopesReached = Set<Scope>()
		/// An index for each root context, so that a key holds one integer for it.
		var cleanSubtreeRootContextIndices = [CleanSubtreeRootContext: Int]()
		/// See `labelsDeclaredOrRead(beneath:)`.
		var labelsDeclaredOrReadBeneathScope = [Scope: Set<String>]()
		/// See `labelsReadThroughReceives(by:)`.
		var labelsReadThroughReceivesByScope = [Scope: Set<String>]()
		/// See `labelsReadFromAbove(by:)`.
		var labelsReadFromAboveByScope = [Scope: Set<String>]()
		/// See `reachesInstantiationCycle(from:)`.
		var reachesInstantiationCycleByScope = [Scope: Bool]()
		/// See `cleanSubtreeLabelFacts(of:)`.
		var cleanSubtreeLabelFactsByScope = [Scope: CleanSubtreeLabelFacts]()
		/// See `cleanSubtreeKeyLabels(of:)`.
		var cleanSubtreeKeyLabelsByScope = [Scope: CleanSubtreeKeyLabels]()
		/// See `propertiesReceivedTransitively(from:)`.
		var propertiesReceivedTransitivelyByProperty = [Property: Set<Property>]()
		/// `property`, as cycle validation sees it, and every property `validateNoCycleInReceivedProperties` can reach from
		/// it through the required receives of the scopes of the types it walks, whether or not it stops at one handed to
		/// the tree: the only entries of an instantiation stack that walk can find.
		func propertiesReceivedTransitively(from property: Property) -> Set<Property> {
			if let cached = propertiesReceivedTransitivelyByProperty[property] {
				return cached
			} else {
				let start = property.asValidatedForDependencyCycles
				var reached: Set<Property> = [start]
				var pending = [start]
				while let reachedProperty = pending.popLast() {
					for requiredReceivedProperty in typeDescriptionToScopeMap[reachedProperty.typeDescription]?.requiredReceivedProperties ?? [] {
						let receivedProperty = requiredReceivedProperty.property.asValidatedForDependencyCycles
						if reached.insert(receivedProperty).inserted {
							pending.append(receivedProperty)
						}
					}
				}
				propertiesReceivedTransitivelyByProperty[property] = reached
				return reached
			}
		}
		/// The scopes whose receives a walk of `scope` follows: the scopes of the types it receives or renames.
		func receivedScopes(of scope: Scope) -> [Scope] {
			var scopes = [Scope]()
			for dependency in scope.instantiable.dependencies {
				let receivedProperty: Property
				switch dependency.source {
				case .received:
					receivedProperty = dependency.property
				case let .aliased(fulfillingProperty, _, _):
					receivedProperty = fulfillingProperty
				case .instantiated, .forwarded:
					continue
				}
				for typeDescription in [receivedProperty.typeDescription, receivedProperty.asValidatedForDependencyCycles.typeDescription] {
					if let receivedScope = typeDescriptionToScopeMap[typeDescription] {
						scopes.append(receivedScope)
					}
				}
			}
			return scopes
		}
		/// The scopes `scope` instantiates.
		func instantiatedScopes(of scope: Scope) -> [Scope] {
			var scopes = [Scope]()
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
				scopes.append(childScope)
			}
			return scopes
		}
		/// The union, for `start` and every scope `successors` reaches from it, of `labels` of each, remembered in `cache` for
		/// each scope reached.
		func labelsReached(
			from start: Scope,
			successors: (Scope) -> [Scope],
			labels: (Scope) -> Set<String>,
			cache: inout [Scope: Set<String>],
		) -> Set<String> {
			valueReached(
				from: start,
				successors: successors,
				componentValue: { component, _ in
					var componentLabels = Set<String>()
					for member in component {
						componentLabels.formUnion(labels(member))
					}
					return componentLabels
				},
				combining: { $0.formUnion($1) },
				empty: [],
				cache: &cache,
			)
		}
		/// Whether a walk of `scope`'s subtree closes a dependency cycle wherever it is reached: whether a cycle of
		/// instantiated scopes is reachable from it, which the walk follows until a child repeats an entry of its instantiation
		/// stack. Such a scope is keyed by `cleanSubtreeKeyLabels(of:)`, and remembered as "Clean subtrees" in
		/// `cycle-validation.md` says.
		func reachesInstantiationCycle(from scope: Scope) -> Bool {
			valueReached(
				from: scope,
				successors: instantiatedScopes(of:),
				componentValue: { component, successorsByScope in
					component.count > 1 || component.contains { successorsByScope[$0, default: []].contains($0) }
				},
				combining: { $0 = $0 || $1 },
				empty: false,
				cache: &reachesInstantiationCycleByScope,
			)
		}
		/// For `start` and every scope `successors` reaches from it, `componentValue` of its strongly connected component
		/// (given the component and each member's successors) combined with the values of the components it reaches,
		/// remembered in `cache` for each scope reached: each component shares one answer.
		func valueReached<Value>(
			from start: Scope,
			successors: (Scope) -> [Scope],
			componentValue: (_ component: Set<Scope>, _ successorsByScope: [Scope: [Scope]]) -> Value,
			combining combine: (inout Value, Value) -> Void,
			empty: Value,
			cache: inout [Scope: Value],
		) -> Value {
			valuesReached(
				from: start,
				successors: successors,
				componentValues: { component, successorsByScope, valueByReachedScope in
					let componentScopes = Set(component)
					var value = componentValue(componentScopes, successorsByScope)
					for member in component {
						for successor in successorsByScope[member, default: []] where !componentScopes.contains(successor) {
							combine(&value, valueByReachedScope[successor, default: empty])
						}
					}
					return Dictionary(component.map { ($0, value) }, uniquingKeysWith: { first, _ in first })
				},
				empty: empty,
				cache: &cache,
			)
		}
		/// For `start` and every scope `successors` reaches from it, the value `componentValues` gives it, remembered in
		/// `cache`. `componentValues` is asked once for each strongly connected component, after every component it reaches,
		/// with the component's members, each member's successors and the values of the scopes outside it, so a value is
		/// only ever remembered whole. Tarjan's strongly connected components on an explicit stack, so a deep graph needs no
		/// recursion.
		func valuesReached<Value>(
			from start: Scope,
			successors: (Scope) -> [Scope],
			componentValues: (_ component: [Scope], _ successorsByScope: [Scope: [Scope]], _ valueByReachedScope: [Scope: Value]) -> [Scope: Value],
			empty: Value,
			cache: inout [Scope: Value],
		) -> Value {
			if let cached = cache[start] {
				return cached
			}
			var nextIndex = 0
			var indexByScope = [Scope: Int]()
			var lowLinkByScope = [Scope: Int]()
			var successorsByScope = [Scope: [Scope]]()
			var componentStack = [Scope]()
			var onComponentStack = Set<Scope>()
			var visits = [(scope: Scope, nextSuccessor: Int)]()
			func visit(_ scope: Scope) {
				indexByScope[scope] = nextIndex
				lowLinkByScope[scope] = nextIndex
				nextIndex += 1
				successorsByScope[scope] = successors(scope)
				componentStack.append(scope)
				onComponentStack.insert(scope)
				visits.append((scope, 0))
			}
			visit(start)
			while let (scope, nextSuccessor) = visits.last {
				let scopeSuccessors = successorsByScope[scope, default: []]
				if nextSuccessor < scopeSuccessors.count {
					visits[visits.count - 1].nextSuccessor += 1
					let successor = scopeSuccessors[nextSuccessor]
					if let successorIndex = indexByScope[successor] {
						if onComponentStack.contains(successor) {
							lowLinkByScope[scope] = min(lowLinkByScope[scope, default: 0], successorIndex)
						}
					} else if cache[successor] == nil {
						visit(successor)
					}
				} else {
					visits.removeLast()
					let lowLink = lowLinkByScope[scope, default: 0]
					if let (parent, _) = visits.last {
						lowLinkByScope[parent] = min(lowLinkByScope[parent, default: 0], lowLink)
					}
					if lowLink == indexByScope[scope] {
						var component = [Scope]()
						while let member = componentStack.popLast() {
							onComponentStack.remove(member)
							component.append(member)
							if member == scope {
								break
							}
						}
						cache.merge(componentValues(component, successorsByScope, cache), uniquingKeysWith: { _, value in value })
					}
				}
			}
			return cache[start, default: empty]
		}
		/// Every label a walk of `scope`'s subtree can compare with an entry of its instantiation stack, or look up in what is
		/// receivable there: each label a scope it instantiates, or a scope it follows a receive to, declares, receives,
		/// renames, provides or builds.
		func labelsDeclaredOrRead(beneath scope: Scope) -> Set<String> {
			labelsReached(
				from: scope,
				successors: { instantiatedScopes(of: $0) + receivedScopes(of: $0) },
				labels: { reachedScope in
					var labels = Set<String>()
					for dependency in reachedScope.instantiable.dependencies {
						labels.insert(dependency.property.label)
						if let fulfillingProperty = dependency.source.fulfillingProperty {
							labels.insert(fulfillingProperty.label)
						}
					}
					for providedProperty in reachedScope.providedProperties {
						labels.insert(providedProperty.label)
					}
					for propertyToGenerate in reachedScope.propertiesToGenerate {
						labels.insert(propertyToGenerate.property.label)
					}
					return labels
				},
				cache: &labelsDeclaredOrReadBeneathScope,
			)
		}
		/// The labels `scope`, and each scope a walk follows its receives to, receives or renames: those whose closest
		/// declaration above `scope` its walk reads.
		func labelsReadThroughReceives(by scope: Scope) -> Set<String> {
			labelsReached(
				from: scope,
				successors: receivedScopes(of:),
				labels: { reachedScope in
					var labels = Set<String>()
					for dependency in reachedScope.instantiable.dependencies {
						switch dependency.source {
						case .received:
							labels.insert(dependency.property.label)
						case let .aliased(fulfillingProperty, _, _):
							labels.insert(fulfillingProperty.label)
						case .instantiated, .forwarded:
							break
						}
					}
					return labels
				},
				cache: &labelsReadThroughReceivesByScope,
			)
		}
		/// The labels whose closest declaration above `scope` a walk of its subtree reads: its own reads, and those of the
		/// scopes it instantiates that it does not declare itself. Scopes that instantiate one another are answered together,
		/// each taking what the others read until nothing is added, so no scope is remembered with part of a cycle unread:
		/// a subtree that reaches a cycle of instantiators is remembered too, and its key is built from this.
		func labelsReadFromAbove(by scope: Scope) -> Set<String> {
			valuesReached(
				from: scope,
				successors: instantiatedScopes(of:),
				componentValues: { component, successorsByScope, labelsByReachedScope in
					var declaredLabelsByScope = [Scope: Set<String>]()
					var labelsByScope = [Scope: Set<String>]()
					for member in component {
						var declaredLabels = Set<String>()
						for dependency in member.instantiable.dependencies where member.createdProperties.contains(dependency.property) {
							declaredLabels.insert(dependency.property.label)
						}
						declaredLabelsByScope[member] = declaredLabels
						var labels = labelsReadThroughReceives(by: member)
						for child in successorsByScope[member, default: []] {
							labels.formUnion(labelsByReachedScope[child, default: []].subtracting(declaredLabels))
						}
						labelsByScope[member] = labels
					}
					var addedLabel = component.count > 1
					while addedLabel {
						addedLabel = false
						for member in component {
							var labels = labelsByScope[member, default: []]
							let labelCount = labels.count
							for child in successorsByScope[member, default: []] {
								labels.formUnion(labelsByScope[child, default: []].subtracting(declaredLabelsByScope[member, default: []]))
							}
							if labels.count > labelCount {
								labelsByScope[member] = labels
								addedLabel = true
							}
						}
					}
					return labelsByScope
				},
				empty: [],
				cache: &labelsReadFromAboveByScope,
			)
		}
		/// What the scopes a walk of `scope`'s subtree can reach, its own included, do with each label.
		func cleanSubtreeLabelFacts(of scope: Scope) -> CleanSubtreeLabelFacts {
			valueReached(
				from: scope,
				successors: { instantiatedScopes(of: $0) + receivedScopes(of: $0) },
				componentValue: { component, _ in
					var facts = CleanSubtreeLabelFacts()
					for member in component {
						facts.record(member, labelsJudgedInTree: labelsJudged(inTreeOf:))
					}
					return facts
				},
				combining: { $0.formUnion($1) },
				empty: CleanSubtreeLabelFacts(),
				cache: &cleanSubtreeLabelFactsByScope,
			)
		}
		/// The labels the key of `scope` holds. A walk of its subtree reads less of its path than
		/// `labelsDeclaredOrRead(beneath:)` allows for, and what it does not read differs on every path through a cycle, and on
		/// every path through screens that each declare one label with a type of their own. The first three hold for every
		/// scope; the last is read only of a scope that reaches a cycle of instantiators:
		/// - The receivable properties of a label no scope beneath receives or renames are read by no judgement.
		/// - Nor are those of a label the scopes beneath only forward and require, as one non-optional property, where every
		///   receive of it is beneath a scope that forwards it (`labelsReadFromAbove(by:)` holds it not): that scope makes the
		///   property receivable whatever is above.
		/// - An entry of the instantiation stack is compared with the property a scope receives or renames, by its label, or
		///   with the property a scope builds a scope for, which closes a cycle only on an entry built for the same concrete
		///   type (`indexOfEntryClosedOn`). An entry of a label nothing beneath receives or renames, built for a type no scope
		///   beneath is of, equals neither: builders that share a label down a path otherwise give every path another key.
		/// - An entry of a label only instantiators are built for beneath `scope` is compared only where a scope builds an
		///   instantiator of it, which then closes a cycle: the walk does not enter the tree, and
		///   `validateTreeBuiltAgainByCycle` returns at once unless a label it can judge in that tree is declared, or made
		///   receivable, deeper than the entry. No scope beneath `scope` declares such a label, or the set is empty, and
		///   `cleanSubtreeKey(of:rootContextIndex:)` keeps an entry that a declaration above `scope` is deeper than.
		///
		/// Each condition here and in `cleanSubtreeKey(of:rootContextIndex:)` makes the key hold more, so it can cost a skip
		/// and never cause a wrong one. A test shows these are needed, failing with the condition left out
		/// (`SafeDIToolCleanSubtreeTests`, "One graph for each part of the key"): a label a scope beneath reads from above
		/// keeps its receivable properties; the root's context; and a subtree skipped as found clean beneath a scope still
		/// being walked hands that scope's depth up. No graph is known for these, each left out by hand over about 43,000
		/// seeded graphs with no difference between a run that skips and one that skips nothing:
		/// - "exactly one property" and "its non-optional form" of a label fulfilled beneath. A second property, or an
		///   optional form, under a label a scope beneath forwards is received beneath that forwarder, where the walk
		///   reports it on every path or on none.
		/// - the two conditions on the labels only instantiators build (no judged label declared beneath; used no other
		///   way), and the two depths `cleanSubtreeKey(of:rootContextIndex:)` compares an entry with. A declaration deeper
		///   than an entry a cycle closes on is made by a scope between that entry's scope and `scope`, which `scope`
		///   reaches through the cycle, so the first condition appears to cover what the depths do.
		/// - a cycle that closes above its parent counting as an equal first build only for a label only instantiators
		///   build; the stack's entries; and the positions of the declarations among them.
		/// Leaving one out needs an argument that the rest of the key tells apart everything it does, not this search.
		func cleanSubtreeKeyLabels(of scope: Scope) -> CleanSubtreeKeyLabels {
			if let cached = cleanSubtreeKeyLabelsByScope[scope] {
				return cached
			} else {
				let facts = cleanSubtreeLabelFacts(of: scope)
				let labelsReadAbove = labelsReadFromAbove(by: scope)
				let receivableLabels = labelsDeclaredOrRead(beneath: scope).filter { label in
					let uses = facts.usesByLabel[label, default: []]
					guard uses.contains(.read) else { return false }
					let properties = facts.forwardedOrReceivedPropertiesByLabel[label, default: []]
					let isFulfilledBeneath = uses.isSubset(of: [.read, .forwarded])
						&& properties.count == 1
						&& properties.allSatisfy { $0 == $0.asUnwrappedProperty }
						&& !labelsReadAbove.contains(label)
					return !isFulfilledBeneath
				}
				let judgedLabels = facts.labelsJudgedInTreesBuiltByInstantiators
				let keyLabels = CleanSubtreeKeyLabels(
					receivableLabels: receivableLabels,
					labelsComparedWithEntries: Set(facts.usesByLabel.lazy.filter { !$0.value.isDisjoint(with: [.read, .readOtherThanByRequiredReceive, .forwarded]) }.map(\.key)),
					builtTypes: facts.builtTypes,
					labelsOnlyInstantiatorsBuild: judgedLabels.isDisjoint(with: facts.declaredLabels)
						? Set(facts.usesByLabel.lazy.filter { $0.value == .builtByInstantiator }.map(\.key))
						: [],
					labelsJudgedInTheirTrees: judgedLabels,
				)
				cleanSubtreeKeyLabelsByScope[scope] = keyLabels
				return keyLabels
			}
		}
		/// The entries of `alias`'s declaring instantiation stack, nearest first, that a walk of a subtree beneath it reads.
		/// Elsewhere the walk reads the stack only by its length, to find the child of the declaring scope it is built
		/// inside, whose comparison `CleanSubtreeAlias.fulfillingSiblingBeingBuilt` holds. A required receive of an
		/// `onlyIfAvailable` alias bound from a property the tree builds hands the stack to
		/// `validateNoCycleInReceivedProperties`, which reads its first entry, finds by its first index each entry that
		/// `propertiesReceivedTransitively(from:)` holds, and reads the entries up to the one it finds: the stack up to the
		/// farthest entry it holds covers every first index that walk can find, and so decides it. A walk that finds an
		/// entry raises `memoBlockingEventCount` or throws, but a second receive of the alias along the same stack is spared
		/// that walk and raises nothing, so a key can be kept from a walk whose check found a builder: an equal key holds
		/// the entries up to it, and finds it too.
		func declaringStackEntriesReadByFulfillingPropertyWalk(of alias: ReceivableAlias, lastFulfillingProperty: Property) -> [Property] {
			if alias.onlyIfAvailable, case .built? = alias.binding {
				let reachableProperties = propertiesReceivedTransitively(from: lastFulfillingProperty)
				let stack = alias.lastAliasDeclaringInstantiationStack
				let farthestIndexFound = stack.lastIndex(where: reachableProperties.contains) ?? 0
				return Array(stack.prefix(farthestIndexFound + 1))
			} else {
				return []
			}
		}
		/// What a walk of `scopeToValidate`'s subtree reads of the path it is reached by (see `CleanSubtreeKey`).
		func cleanSubtreeKey(of scopeToValidate: ScopeToValidate, rootContextIndex: Int) -> CleanSubtreeKey {
			let scope = scopeToValidate.scope
			let labelsBeneath = labelsDeclaredOrRead(beneath: scope)
			let labelsReadAbove = labelsReadFromAbove(by: scope)
			let keyLabels = cleanSubtreeKeyLabels(of: scope)
			let cycleKeyLabels = reachesInstantiationCycle(from: scope) ? keyLabels : nil
			// The first index, root first, of the entries no declaration or receivable property that
			// `validateTreeBuiltAgainByCycle` can judge is deeper than: a tree built again on one of them changes no judgement.
			var firstEntryIndexNothingJudgedIsDeeperThan = 0
			if let cycleKeyLabels, !cycleKeyLabels.labelsOnlyInstantiatorsBuild.isEmpty {
				for label in cycleKeyLabels.labelsJudgedInTheirTrees {
					if let depth = scopeToValidate.closestDeclarationDepthByLabel[label] {
						firstEntryIndexNothingJudgedIsDeeperThan = max(firstEntryIndexNothingJudgedIsDeeperThan, depth - 1)
					}
				}
				if let depth = scopeToValidate.receivableDepthByProperty.greatest(of: { cycleKeyLabels.labelsJudgedInTheirTrees.contains($0.key.label) ? $0.value : nil }) {
					firstEntryIndexNothingJudgedIsDeeperThan = max(firstEntryIndexNothingJudgedIsDeeperThan, depth - 1)
				}
			}
			var closestDeclarations = [String: CleanSubtreeDeclaration]()
			var labelsByDeclaringDepth = [Int: [String]]()
			for label in labelsReadAbove {
				if let declaration = scopeToValidate.closestDeclarationByLabel[label] {
					closestDeclarations[label] = CleanSubtreeDeclaration(
						property: declaration.property,
						lazilyInstantiatedInstanceProperty: declaration.lazilyInstantiatedInstanceProperty,
						isForwarded: declaration.isForwarded,
					)
					labelsByDeclaringDepth[scopeToValidate.closestDeclarationDepthByLabel[label, default: 0], default: []].append(label)
				}
			}
			// The instantiation stack root first, ending with the property `scope` is built for.
			var entries = Array(zip(scopeToValidate.propertyStack, scopeToValidate.parentTypeStack).reversed())
			if let property = scopeToValidate.property {
				entries.append((property, scope.instantiable.concreteInstantiable))
			}
			var stack = [CleanSubtreeStackToken]()
			for (depth, (entryProperty, entryType)) in entries.enumerated() {
				if let labels = labelsByDeclaringDepth[depth] {
					stack.append(.declarations(labels.sorted()))
				}
				if labelsBeneath.contains(entryProperty.label),
				   keyLabels.builtTypes.contains(entryType) || keyLabels.labelsComparedWithEntries.contains(entryProperty.label),
				   !(depth >= firstEntryIndexNothingJudgedIsDeeperThan && cycleKeyLabels?.labelsOnlyInstantiatorsBuild.contains(entryProperty.label) == true)
				{
					stack.append(.entry(entryProperty, entryType))
				} else if stack.last != .gap {
					stack.append(.gap)
				}
			}
			var receivableAliases = [Property: CleanSubtreeAlias]()
			let usesByLabel = scopeToValidate.receivableAliases.isEmpty ? [:] : cleanSubtreeLabelFacts(of: scope).usesByLabel
			// The walk's instantiation stack, nearest first, starts with the property `scope` is built for.
			let instantiationStack = usesByLabel.isEmpty ? [] : (scopeToValidate.property.map { [$0] } ?? []) + scopeToValidate.propertyStack
			for (aliasProperty, alias) in scopeToValidate.receivableAliases where usesByLabel[aliasProperty.label, default: []].contains(.read) {
				let declaringChild = instantiationStack.dropFirst(instantiationStack.count - alias.lastAliasDeclaringInstantiationStack.count - 1).first
				let lastFulfillingProperty = alias.fulfillingOnlyIfAvailableAliases.last?.fulfillingProperty ?? alias.fulfillingProperty
				receivableAliases[aliasProperty] = CleanSubtreeAlias(
					fulfillingProperty: alias.fulfillingProperty,
					onlyIfAvailable: alias.onlyIfAvailable,
					fulfillingOnlyIfAvailableAliases: alias.fulfillingOnlyIfAvailableAliases,
					binding: alias.binding,
					declaringType: alias.declaringType,
					lastAliasDeclaringType: alias.lastAliasDeclaringType,
					declaringStackEntriesRead: declaringStackEntriesReadByFulfillingPropertyWalk(of: alias, lastFulfillingProperty: lastFulfillingProperty),
					fulfillingSiblingBeingBuilt: formsOnStack(of: lastFulfillingProperty.asValidatedForDependencyCycles).first { $0 == declaringChild },
				)
			}
			return CleanSubtreeKey(
				scope: scope,
				property: scopeToValidate.property,
				rootContextIndex: rootContextIndex,
				receivableProperties: scopeToValidate.receivableProperties.properties(labeledAnyOf: keyLabels.receivableLabels),
				closestDeclarations: closestDeclarations,
				stack: stack,
				receivableAliases: receivableAliases,
			)
		}
		/// Validates the tree rooted at `rootScope`, scope by scope, depth first in the order each scope declares its
		/// children. It keeps its own stack of the scopes left to validate, since a tree can be as deep as the module
		/// has types.
		/// - Parameters:
		///   - validatesCycles: Whether to validate the tree for dependency cycles and unfulfillable received
		///     properties. `false` only for a tree validated for hidden received dependencies alone.
		///   - validatesHiddenProperties: Whether to record received dependencies a closer declaration hides, and renames
		///     that name another type than their own type's property of their label.
		func validatePropertiesAreFulfillable(
			inTreeRootedAt rootScope: ValidatedRootScope,
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
		) throws {
			/// A step left to validate, with its key where it is a scope whose subtree's walk may be skipped or remembered; or the end of a
			/// keyed scope's subtree, with the count of memo-blocking events when its walk began.
			enum WalkItem {
				case step(TreeValidationStep, key: CleanSubtreeKey?)
				case finished(CleanSubtreeKey, memoBlockingEventCount: Int, depth: Int, pendingCount: Int)
			}
			let mockRootForwardedProperties: Set<Property>? = rootScope.isMock ? rootScope.scope.instantiable.forwardedReceivableProperties : nil
			let rootContext = CleanSubtreeRootContext(
				boundProperties: rootScope.boundProperties,
				mockRootForwardedProperties: mockRootForwardedProperties,
				validatesCycles: validatesCycles,
				validatesHiddenProperties: validatesHiddenProperties,
			)
			let rootContextIndex: Int
			if let index = cleanSubtreeRootContextIndices[rootContext] {
				rootContextIndex = index
			} else {
				rootContextIndex = cleanSubtreeRootContextIndices.count
				cleanSubtreeRootContextIndices[rootContext] = rootContextIndex
			}
			validationWalkScopesReached.insert(rootScope.scope)
			/// The scopes whose walk is in progress, root first, each with its key where it has one.
			var scopesInProgress = [(scope: Scope, key: CleanSubtreeKey?)]()
			/// Beside `scopesInProgress`, the shallowest depth a scope beneath each closed a cycle on without the walk reading
			/// anything of it (`closesCycleOnEqualFirstBuild`), or the scope's own depth: what was found beneath a scope holds
			/// only if the walk of the scope at that depth finds nothing either.
			var shallowestDepthClosedOnBeneath = [Int]()
			/// The keys of the subtrees whose walk completed and found nothing, but closed a cycle on a scope above them whose
			/// walk is in progress, in the order they completed, each with the depth of the shallowest such scope.
			var pendingCleanSubtrees = [CleanSubtreeKey]()
			var pendingCleanSubtreeDepths = [CleanSubtreeKey: Int]()
			/// Whether `cycleClosingScope`, a child of the scope at `parentDepth`, closes its cycle on a scope whose walk, in
			/// progress, validates what a walk of the tree here would: the tree's key here equals that scope's, and the scopes
			/// between hold the entry it closes on in no key, so nothing above them reads that it closed.
			func closesCycleOnEqualFirstBuild(_ cycleClosingScope: CycleClosingScopeToValidate, parentDepth: Int) -> Bool {
				let closedOnDepth = cycleClosingScope.propertyStack.count - cycleClosingScope.closedOnIndex
				guard let closedOnKey = scopesInProgress[closedOnDepth].key else { return false }
				if closedOnDepth < parentDepth {
					guard cleanSubtreeKeyLabels(of: scopesInProgress[closedOnDepth + 1].scope).labelsOnlyInstantiatorsBuild.contains(cycleClosingScope.property.label) else { return false }
				}
				return cleanSubtreeKey(of: cycleClosingScope.asScopeToValidate, rootContextIndex: rootContextIndex) == closedOnKey
			}
			var walkItems = [WalkItem.step(.scope(ScopeToValidate(
				scope: rootScope.scope,
				receivableProperties: ReceivableProperties(Set(rootScope.scope.properties).union(rootScope.receivedFromOutside)),
				receivableAliases: [:],
				closestDeclarationByLabel: LayeredMap([:]),
				closestDeclarationDepthByLabel: LayeredMap([:]),
				receivableDepthByProperty: LayeredMap([:]),
				property: nil,
				propertyStack: [],
				parentTypeStack: [],
				lazilyInstantiatedDeclarations: [:],
			)), key: nil)]
			let root = rootScope.scope.instantiable.concreteInstantiable
			while let walkItem = walkItems.popLast() {
				switch walkItem {
				case let .step(.scope(scopeToValidate), key):
					validationWalkObserver?(.validatedScope)
					let eventCountBeforeScope = memoBlockingEventCount
					let depth = scopeToValidate.propertyStack.count + (scopeToValidate.property == nil ? 0 : 1)
					scopesInProgress.removeSubrange(depth...)
					scopesInProgress.append((scopeToValidate.scope, key))
					// The scopes at this depth and deeper are a finished subtree of the scope above, which what they closed on is
					// beneath too: a scope that is not keyed has no end of its own to hand it up at.
					if depth > 0, let shallowestDepthClosedOn = shallowestDepthClosedOnBeneath[depth...].min() {
						shallowestDepthClosedOnBeneath[depth - 1] = min(shallowestDepthClosedOnBeneath[depth - 1], shallowestDepthClosedOn)
					}
					shallowestDepthClosedOnBeneath.removeSubrange(depth...)
					shallowestDepthClosedOnBeneath.append(depth)
					var children = [TreeValidationStep]()
					try validatePropertiesAreFulfillable(
						on: scopeToValidate,
						boundProperties: rootScope.boundProperties,
						mockRootForwardedProperties: mockRootForwardedProperties,
						validatesCycles: validatesCycles,
						validatesHiddenProperties: validatesHiddenProperties,
						root: root,
						scopesToValidate: &children,
					)
					if let key {
						walkItems.append(.finished(key, memoBlockingEventCount: eventCountBeforeScope, depth: depth, pendingCount: pendingCleanSubtrees.count))
					}
					// `children` holds the first child last, so it is validated next.
					for child in children {
						switch child {
						case let .scope(childToValidate):
							// A scope reached once is never keyed: only a scope reached again can be skipped. One whose walk can close a
							// cycle is keyed wherever it is reached, since a cycle-closing scope beneath it is compared with its key.
							// This skip consults a memo inside the walk. Its planned replacement walks each distinct subtree context
							// once by construction, as a node of its own that every equal visit shares, once a measurement shows
							// that node pays for itself; it then takes this memo's place and `skipsCleanSubtrees` goes with it.
							// One keyed `cleanSubtreeMissLimit` times in a row for nothing is keyed no more, whether or not it reaches a
							// cycle: its walk is then remembered nowhere, and a cycle that closes on it blocks the memo above, as any
							// scope without a key does.
							let isReachedAgain = !validationWalkScopesReached.insert(childToValidate.scope).inserted
							let isKeyed = (isReachedAgain || reachesInstantiationCycle(from: childToValidate.scope))
								&& cleanSubtreeMissesInARowByScope[childToValidate.scope, default: 0] < cleanSubtreeMissLimit
							if skipsCleanSubtrees, isKeyed {
								validationWalkObserver?(.keyedSubtree)
								let childKey = cleanSubtreeKey(of: childToValidate, rootContextIndex: rootContextIndex)
								if cleanSubtrees.contains(childKey) {
									validationWalkObserver?(.skippedCleanSubtree)
									cleanSubtreeMissesInARowByScope[childToValidate.scope] = 0
								} else if let pendingDepth = pendingCleanSubtreeDepths[childKey] {
									// Found clean beneath a scope still being walked, which this place is beneath too.
									validationWalkObserver?(.skippedCleanSubtree)
									shallowestDepthClosedOnBeneath[depth] = min(shallowestDepthClosedOnBeneath[depth], pendingDepth)
									cleanSubtreeMissesInARowByScope[childToValidate.scope] = 0
								} else {
									walkItems.append(.step(child, key: childKey))
									cleanSubtreeMissesInARowByScope[childToValidate.scope, default: 0] += 1
								}
							} else {
								walkItems.append(.step(child, key: nil))
							}
						case let .cycleClosingScope(cycleClosingScope):
							if skipsCleanSubtrees, closesCycleOnEqualFirstBuild(cycleClosingScope, parentDepth: depth) {
								shallowestDepthClosedOnBeneath[depth] = min(shallowestDepthClosedOnBeneath[depth], cycleClosingScope.propertyStack.count - cycleClosingScope.closedOnIndex)
							} else {
								// The tree is given something here its first build is not, or a key above holds the entry it closed on, so no
								// walk above is remembered.
								memoBlockingEventCount += 1
							}
							walkItems.append(.step(child, key: nil))
						}
					}
				case let .step(.cycleClosingScope(cycleClosingScope), _):
					// The type the cycle-closing scope builds receives the nearest declaration of each label, which a scope
					// between it and the scope it closes on can make: the generated code passes that declaration where the tree
					// is built again.
					try validateTreeBuiltAgainByCycle(
						of: cycleClosingScope.scope,
						for: cycleClosingScope.property,
						closedOnIndex: cycleClosingScope.closedOnIndex,
						cycleClosingScopeParent: cycleClosingScope.cycleClosingScopeParent,
						propertyStack: cycleClosingScope.propertyStack,
						parentTypeStack: cycleClosingScope.parentTypeStack,
						closestDeclarationByLabel: cycleClosingScope.closestDeclarationByLabel,
						closestDeclarationDepthByLabel: cycleClosingScope.closestDeclarationDepthByLabel,
						receivableProperties: cycleClosingScope.receivableProperties,
						receivableDepthByProperty: cycleClosingScope.receivableDepthByProperty,
						validatesCycles: validatesCycles,
						validatesHiddenProperties: validatesHiddenProperties,
						root: root,
					)
				case let .finished(key, eventCountBeforeScope, depth, pendingCount):
					// A walk that throws never gets here, so only a completed walk is remembered.
					// The shallowest of this scope and of every scope still listed beneath it, which are the last subtree it walked.
					let shallowestDepthClosedOn = shallowestDepthClosedOnBeneath[depth...].min() ?? depth
					shallowestDepthClosedOnBeneath.removeSubrange((depth + 1)...)
					shallowestDepthClosedOnBeneath[depth] = shallowestDepthClosedOn
					if depth > 0 {
						shallowestDepthClosedOnBeneath[depth - 1] = min(shallowestDepthClosedOnBeneath[depth - 1], shallowestDepthClosedOn)
					}
					let pendingBeneath = pendingCleanSubtrees[pendingCount...]
					if memoBlockingEventCount != eventCountBeforeScope {
						// What was found clean beneath this scope held only if its own walk found nothing.
						for pendingKey in pendingBeneath {
							pendingCleanSubtreeDepths[pendingKey] = nil
						}
						pendingCleanSubtrees.removeSubrange(pendingCount...)
					} else if shallowestDepthClosedOn < depth {
						// Clean only if the walk of a scope above, which a cycle beneath this one closed on, finds nothing: so is
						// everything found clean beneath this scope, which is beneath that one.
						for pendingKey in pendingBeneath {
							pendingCleanSubtreeDepths[pendingKey] = shallowestDepthClosedOn
						}
						pendingCleanSubtrees.append(key)
						pendingCleanSubtreeDepths[key] = shallowestDepthClosedOn
					} else {
						cleanSubtrees.insert(key)
						for pendingKey in pendingBeneath {
							cleanSubtrees.insert(pendingKey)
							pendingCleanSubtreeDepths[pendingKey] = nil
						}
						pendingCleanSubtrees.removeSubrange(pendingCount...)
					}
				}
			}
		}
		/// Records each dependency of `scope` that the closest declaration of the label it receives hides, among
		/// `closestDeclarationByLabel`: the generated code passes a received dependency by its label, which resolves to that
		/// declaration, so a different property there is passed in its place. One rule for a scope on any path and for a
		/// type a cycle-closing scope builds again, so the two cannot differ.
		/// - Parameters:
		///   - receivableProperties: What the scopes `scope` is built inside make available to it.
		///   - propertyStack: The properties of the scopes `scope` is built inside, innermost first.
		///   - parentTypeStack: The concrete types of those scopes, beside `propertyStack`.
		///   - changedContext: For a scope of a tree a cycle-closing scope builds again, what is new there to the tree (see
		///     `ScopeBuiltAgain`): only a receive whose hiding declaration is new, or that only a new receivable property
		///     provides, is recorded, since the tree's first build judged every other receive as this one would.
		func recordHiddenReceives(
			of scope: Scope,
			closestDeclarationByLabel: some LabelDeclarations,
			receivableProperties: some PropertyMembership,
			propertyStack: [Property],
			parentTypeStack: [TypeDescription],
			root: TypeDescription,
			changedContext: (newLabels: Set<String>, newReceivableProperties: Set<Property>)? = nil,
		) {
			// Whether the tree's first build received `property` here.
			func firstBuildReceives(_ property: Property) -> Bool {
				receivableProperties.contains(property) && changedContext?.newReceivableProperties.contains(property) != true
			}
			// A builder an internal mock passes up to its own parameter, which the leaf that calls the public mock receives
			// under the builder's label, is a receive no declaration the person wrote can fulfill: the mock names the
			// parameter apart from every label its tree declares, and the leaf reads it there (see
			// `ScopeGenerator.mockRootParameterNames(of:)`).
			for dependency in scope.instantiable.dependencies where !(scope.publicMockCall?.passesUpBuilder(receivedAs: dependency.property) ?? false) {
				let receivedProperty: Property
				let isOnlyIfAvailableAlias: Bool
				switch dependency.source {
				case .received:
					receivedProperty = dependency.property
					isOnlyIfAvailableAlias = false
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					receivedProperty = fulfillingProperty
					isOnlyIfAvailableAlias = onlyIfAvailable
				case .instantiated, .forwarded:
					continue
				}
				// Most receives have no declaration of their label in the tree, so the forms they accept are listed only for one
				// that has.
				guard let closestDeclaration = closestDeclarationByLabel[receivedProperty.label] else { continue }
				// A receive of an optional property, required or `onlyIfAvailable`, resolves to its non-optional form too, and an
				// `onlyIfAvailable` alias reads the optional form of its fulfilling property too, as `nil` where it is.
				let acceptedProperties: Set<Property> = isOnlyIfAvailableAlias
					? Set(receivedProperty.formsReadByOnlyIfAvailableReceive)
					: [receivedProperty, receivedProperty.asUnwrappedProperty]
				guard !closestDeclaration.fulfills(anyOf: acceptedProperties),
				      // An alias of a property this scope declares refers to that declaration.
				      acceptedProperties.isDisjoint(with: scope.createdProperties),
				      // Production passes `nil` for an `onlyIfAvailable` dependency no ancestor provides. A mock
				      // declares every received dependency at its root, above every hiding declaration.
				      cyclesOnly || acceptedProperties.contains(where: receivableProperties.contains)
				else {
					continue
				}
				if let changedContext {
					// A declaration between the function and the cycle-closing scope hides the receive; or the function's
					// own tree hides it, as on its first build, which passed it `nil`, since only a scope between provides it.
					guard changedContext.newLabels.contains(receivedProperty.label)
						|| !cyclesOnly && !acceptedProperties.contains(where: firstBuildReceives)
					else { continue }
				}
				memoBlockingEventCount += 1
				let hiddenReceive = HiddenReceiveInTree(
					property: receivedProperty,
					declarationLocation: dependency.declarationLocation,
					hidingDeclaration: closestDeclaration,
					enclosingHidingDeclarations: Array(closestDeclaration.enclosingDeclarations.prefix { !$0.fulfills(anyOf: acceptedProperties) }),
					receiver: scope.instantiable.concreteInstantiable,
					root: root,
				)
				if hiddenReceivedProperties[hiddenReceive] == nil {
					hiddenReceivedProperties[hiddenReceive] = HiddenReceiveChain(
						parentStack: propertyStack.map(\.typeDescription),
						parentTypeStack: parentTypeStack,
					)
				}
			}
		}
		/// Enters each property `scope` creates in `closestDeclarationByLabel` as the closest declaration of its label for the
		/// scopes `scope` builds, with the declaration of the label it replaces there, and those that one hides, as its
		/// `enclosingDeclarations`, calling `entering` with each label. One rule for the walk of a tree and the walk of a
		/// tree a cycle-closing scope builds again.
		func enterDeclarations(
			of scope: Scope,
			into closestDeclarationByLabel: inout some LabelDeclarations,
			entering: (String) -> Void,
		) {
			for dependency in scope.instantiable.dependencies where scope.createdProperties.contains(dependency.property) {
				closestDeclarationByLabel[dependency.property.label] = DependencyTreeGeneratorError.LabelDeclaration(
					property: dependency.property,
					lazilyInstantiatedInstanceProperty: dependency.lazilyInstantiatedInstanceProperty,
					declarationLocation: dependency.declarationLocation,
					declaringType: scope.instantiable.concreteInstantiable,
					isForwarded: dependency.isForwarded,
					replacing: closestDeclarationByLabel[dependency.property.label],
				)
				entering(dependency.property.label)
			}
		}
		/// Inserts into `properties` what `scope` makes available to the scopes it builds, given `receivableProperties`, what
		/// the scopes `scope` is built inside make available to it, and calls `inserted` with each property `properties` did
		/// not hold. One rule for the walk of a tree and the walk of a tree a cycle-closing scope builds again.
		/// - Parameters:
		///   - instantiationStack: The properties of `scope` and of the scopes it is built inside, innermost first.
		///   - nearestDeclaration: The nearest declaration of a label above `scope`, as `indexOfEntryClosedOn` reads it.
		func insertProperties(
			madeAvailableBy scope: Scope,
			given receivableProperties: some PropertyMembership,
			instantiationStack: [Property],
			nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
			into properties: inout some PropertyMembership,
			inserted: (Property) -> Void,
		) {
			// An `onlyIfAvailable` receive that is unavailable here is passed `nil`, so it provides nothing to the
			// scopes below. Availability mirrors `Scope.createScopeGenerator`'s: in a mock, only a property that is
			// still being built is unavailable. A receive of a property being built that a nearer declaration fulfills,
			// such as one that closes a cycle, is passed that declaration.
			func isBeingBuilt(_ property: Property) -> Bool {
				// The instantiation stack holds a lazily instantiated property as the constant it stands for. An instantiator is
				// rebound inside its own builder function (see `ScopeGenerator.ReceivedBuilderLoops`).
				let validatedProperty = property.asValidatedForDependencyCycles
				guard !ScopeGenerator.isBuilder(validatedProperty) else { return false }
				return instantiationStack.firstIndex(of: validatedProperty).map {
					!Self.isFulfilledByNearerDeclaration([validatedProperty], thanEntryAt: $0, of: instantiationStack, nearestDeclaration: nearestDeclaration)
				} ?? false
			}
			func isAvailable(_ onlyIfAvailableProperty: Property) -> Bool {
				if cyclesOnly {
					![onlyIfAvailableProperty, onlyIfAvailableProperty.asUnwrappedProperty].contains(where: isBeingBuilt)
				} else {
					[onlyIfAvailableProperty, onlyIfAvailableProperty.asUnwrappedProperty].contains {
						receivableProperties.contains($0) && !isBeingBuilt($0)
					}
				}
			}
			func insert(_ property: Property) {
				if properties.insertIfAbsent(property) {
					inserted(property)
				}
			}
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case let .received(onlyIfAvailable):
					if !onlyIfAvailable || isAvailable(dependency.property) {
						insert(dependency.property)
					}
				case .instantiated, .forwarded, .aliased:
					insert(dependency.property)
					// A lazily instantiated property can also be received by value, as the instance it creates.
					if let instanceProperty = dependency.lazilyInstantiatedInstanceProperty {
						insert(instanceProperty)
					}
				}
			}
			// A mock root also provides the received dependencies it promotes.
			for providedProperty in scope.providedProperties {
				insert(providedProperty)
			}
		}
		/// Validates the tree that a cycle-closing scope, a child of `cycleClosingScopeParent`, builds again – `scope`'s,
		/// built for `property` beneath the scopes of `propertyStack` – where it can differ from the tree's first build, at
		/// `closedOnIndex` in `propertyStack`. The tree is the body of the builder function the cycle closes on, which takes
		/// the labels the scopes between declare as parameters (see `CycleParameter`), so each receive of such a label is
		/// passed the nearest declaration above the cycle-closing scope, as on every other path.
		///
		/// The tree built again is the same code as its first build, which the walk of the tree validated. So only two
		/// things can change what a receive in it resolves to: the bindings of the function's parameters – the declarations
		/// between the scope the cycle closes on and the cycle-closing scope, until a scope the function builds declares the
		/// label again – and the providers above – the properties receivable at the cycle-closing scope that were not where
		/// the tree was first built. The walk threads that context through the tree as the walk of a tree threads its own,
		/// and judges each receive by the rule of every other path (`recordHiddenReceives`), only where the context changes
		/// the judgment: a receive hidden by a new declaration is the hidden-label error where a scope above provides it,
		/// required or only if available; one hidden by a declaration of the tree's own, as on its first build, is the
		/// error where only a new provider provides it, which the first build passed `nil`; and a required receive whose new
		/// nearest declaration is still being built is the dependency cycle error.
		///
		/// A cycle-closing scope the walk meets – of the function built again, of a function nested in it or around it, or a
		/// scope the stack holds already – calls its function with the bindings in scope there, so the walk goes on into that
		/// tree built again whenever anything is new to it there, once for each parent of a cycle-closing scope and context
		/// (`TreeBuiltAgain`), so nested cycles end.
		///
		/// The walk's work grows with every path the scopes it re-enters can be reached by, so a tree whose judgements cannot
		/// change is not walked: at its start and before each child it pushes, the walk stops unless the tree reads a label
		/// new to it (`labelsRead(inTreeOf:)`) that a judgement can fire for (`labelsNoJudgementFiresFor()`). Both of the
		/// walk's judgements fire only for a receive whose label is new, and the new labels only shrink going down, so a tree
		/// that reads none has nothing to report, on any path.
		func validateTreeBuiltAgainByCycle(
			of scope: Scope,
			for property: Property,
			closedOnIndex: Int,
			cycleClosingScopeParent: Scope,
			propertyStack: [Property],
			parentTypeStack: [TypeDescription],
			closestDeclarationByLabel layeredClosestDeclarationByLabel: LayeredMap<String, DependencyTreeGeneratorError.LabelDeclaration>,
			closestDeclarationDepthByLabel layeredClosestDeclarationDepthByLabel: LayeredMap<String, Int>,
			receivableProperties: @autoclosure () -> Set<Property>,
			receivableDepthByProperty layeredReceivableDepthByProperty: LayeredMap<Property, Int>,
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
			root: TypeDescription,
		) throws {
			// The scope the cycle closes on is built inside the scopes after it on the stack.
			let closedOnDepth = propertyStack.count - closedOnIndex
			// Nearly every tree built again reads no label a judgement can fire for that is new to it: a label a scope between
			// declares, or the label of a property a scope between made receivable. The two guards below find that too, but
			// only once they have gathered every declaration between.
			let judgedLabels = labelsJudged(inTreeOf: scope)
			guard judgedLabels.contains(where: { label in
				layeredClosestDeclarationDepthByLabel[label].map { $0 > closedOnDepth } == true && label != property.label
			}) || layeredReceivableDepthByProperty.contains(where: { $0.value > closedOnDepth && judgedLabels.contains($0.key.label) })
			else { return }
			let closestDeclarationByLabel = layeredClosestDeclarationByLabel.asDictionary
			let closestDeclarationDepthByLabel = layeredClosestDeclarationDepthByLabel.asDictionary
			let receivableDepthByProperty = layeredReceivableDepthByProperty.asDictionary
			let receivableProperties = receivableProperties()
			// The declarations between that bind the function's parameters. The property the cycle closes on is no
			// parameter: the cycle-closing scope's own declaration of its label is that property, which the tree built again
			// is passed `nil` for, as its first build is.
			var newDeclarationByLabel = [String: DependencyTreeGeneratorError.LabelDeclaration]()
			for (label, depth) in closestDeclarationDepthByLabel where depth > closedOnDepth && label != property.label {
				newDeclarationByLabel[label] = closestDeclarationByLabel[label]
			}
			// Nearly every cycle-closing scope has no declaration between it and the scope it closes on but its own.
			guard !newDeclarationByLabel.isEmpty else { return }
			// The properties a scope between made receivable. The validation of mocks, which judges a hidden receive whatever
			// provides it, records no depths and so finds none.
			var newReceivableProperties = Set<Property>()
			for (receivableProperty, depth) in receivableDepthByProperty where depth > closedOnDepth && receivableProperties.contains(receivableProperty) {
				newReceivableProperties.insert(receivableProperty)
			}
			guard treeReadsAnything(ofTreeRootedAt: scope, newLabels: newDeclarationByLabel.keys, newReceivableProperties: newReceivableProperties) else { return }
			var treesBuiltAgain: Set<TreeBuiltAgain> = [TreeBuiltAgain(
				cycleClosingScopeParent: cycleClosingScopeParent,
				closedOnProperty: property,
				newDeclarationByLabel: newDeclarationByLabel,
				newReceivableProperties: newReceivableProperties,
			)]
			var scopesToWalk = [ScopeBuiltAgain(
				scope: scope,
				property: property,
				propertyStack: propertyStack,
				parentTypeStack: parentTypeStack,
				closestDeclarationByLabel: closestDeclarationByLabel,
				closestDeclarationDepthByLabel: closestDeclarationDepthByLabel,
				receivableProperties: receivableProperties,
				newLabels: Set(newDeclarationByLabel.keys),
				newReceivableProperties: newReceivableProperties,
				closedOnStackCount: closedOnDepth,
			)]
			while let scopeToWalk = scopesToWalk.popLast() {
				let walkedScope = scopeToWalk.scope
				let instantiationStack = [scopeToWalk.property] + scopeToWalk.propertyStack
				if validatesHiddenProperties {
					recordHiddenReceives(
						of: walkedScope,
						closestDeclarationByLabel: scopeToWalk.closestDeclarationByLabel,
						receivableProperties: scopeToWalk.receivableProperties,
						propertyStack: scopeToWalk.propertyStack,
						parentTypeStack: scopeToWalk.parentTypeStack,
						root: root,
						changedContext: (scopeToWalk.newLabels, scopeToWalk.newReceivableProperties),
					)
				}
				for dependency in walkedScope.instantiable.dependencies where validatesCycles {
					let receivedProperty: Property
					switch dependency.source {
					case .received(onlyIfAvailable: false):
						receivedProperty = dependency.property
					case let .aliased(fulfillingProperty, _, onlyIfAvailable: false):
						// An alias of a property its own scope creates refers to that property.
						guard !walkedScope.createdProperties.contains(fulfillingProperty) else { continue }
						receivedProperty = fulfillingProperty
					case .received(onlyIfAvailable: true), .aliased(_, _, onlyIfAvailable: true), .instantiated, .forwarded:
						continue
					}
					let acceptedProperties: Set<Property> = [receivedProperty, receivedProperty.asUnwrappedProperty]
					// A new nearest declaration: the first build judged one it saw. One of another type is the hidden-label
					// error, recorded above.
					if scopeToWalk.newLabels.contains(receivedProperty.label),
					   let declaration = scopeToWalk.closestDeclarationByLabel[receivedProperty.label],
					   acceptedProperties.contains(declaration.property) || declaration.lazilyInstantiatedInstanceProperty.map(acceptedProperties.contains) == true,
					   let beingBuiltIndex = instantiationStack.firstIndex(of: declaration.property.asValidatedForDependencyCycles),
					   // The scopes being built inside the first build of the scope the cycle closes on are those before it on
					   // the stack.
					   beingBuiltIndex < instantiationStack.count - scopeToWalk.closedOnStackCount,
					   // An instantiator still being built is wrapped again where the cycle-closing scope passes it (see
					   // `ScopeGenerator.ReceivedBuilderLoops`).
					   !ScopeGenerator.isBuilder(instantiationStack[beingBuiltIndex])
					{
						// The nearest declaration is still being built around the cycle-closing scope.
						throw invalidCycleError(
							propertiesInCycle: [receivedProperty.asValidatedForDependencyCycles] + instantiationStack[0...beingBuiltIndex],
							declaredProperty: dependency.property,
							declarationLocation: dependency.declarationLocation,
							directParent: walkedScope.instantiable.concreteInstantiable,
							closingReceive: CycleClosingReceive(),
							lazilyInstantiatedProperties: [],
						)
					}
				}
				// What the scopes the walked scope builds see: a label it declares again names its own declaration there, as
				// on the first build, and a property it provides on the first build too is receivable there on both.
				var childClosestDeclarationByLabel = scopeToWalk.closestDeclarationByLabel
				var childClosestDeclarationDepthByLabel = scopeToWalk.closestDeclarationDepthByLabel
				var childNewLabels = scopeToWalk.newLabels
				enterDeclarations(of: walkedScope, into: &childClosestDeclarationByLabel) {
					childNewLabels.remove($0)
					childClosestDeclarationDepthByLabel[$0] = instantiationStack.count
				}
				let nearestDeclaration: (String) -> (properties: [Property], depth: Int)? = { label in
					scopeToWalk.closestDeclarationByLabel[label].map { ([$0.property.asValidatedForDependencyCycles], scopeToWalk.closestDeclarationDepthByLabel[label, default: 0]) }
				}
				var childReceivableProperties = scopeToWalk.receivableProperties
				var childNewReceivableProperties = Set<Property>()
				if scopeToWalk.newReceivableProperties.isEmpty {
					insertProperties(madeAvailableBy: walkedScope, given: scopeToWalk.receivableProperties, instantiationStack: instantiationStack, nearestDeclaration: nearestDeclaration, into: &childReceivableProperties) { _ in }
				} else {
					// A receive only if available that only a new property makes available provides a new property too.
					childNewReceivableProperties = scopeToWalk.newReceivableProperties
					insertProperties(madeAvailableBy: walkedScope, given: scopeToWalk.receivableProperties, instantiationStack: instantiationStack, nearestDeclaration: nearestDeclaration, into: &childReceivableProperties) {
						childNewReceivableProperties.insert($0)
					}
					var firstBuildProvidedProperties = Set<Property>()
					insertProperties(
						madeAvailableBy: walkedScope,
						given: scopeToWalk.receivableProperties.subtracting(scopeToWalk.newReceivableProperties),
						instantiationStack: instantiationStack,
						nearestDeclaration: nearestDeclaration,
						into: &firstBuildProvidedProperties,
					) { _ in }
					childNewReceivableProperties.subtract(firstBuildProvidedProperties)
				}
				let childParentTypeStack = [walkedScope.instantiable.concreteInstantiable] + scopeToWalk.parentTypeStack
				let firstChildIndex = scopesToWalk.endIndex
				for childPropertyToGenerate in walkedScope.propertiesToGenerate {
					switch childPropertyToGenerate {
					case let .instantiated(declaredChildProperty, childScope, _):
						// A child's tree is the same code as on its first build, and a cycle-closing scope's function's tree built
						// again here sees what it saw where it was built: only a label new to it can change what it receives.
						guard treeReadsAnything(ofTreeRootedAt: childScope, newLabels: childNewLabels, newReceivableProperties: childNewReceivableProperties) else { continue }
						// A lazily instantiated property is validated as the constant it stands for.
						let childProperty = declaredChildProperty.asValidatedForDependencyCycles
						if let childClosedOnIndex = instantiationStack.indices.first(where: {
							instantiationStack[$0] == childProperty && childParentTypeStack[$0] == childScope.instantiable.concreteInstantiable
						}) {
							var childNewDeclarationByLabel = [String: DependencyTreeGeneratorError.LabelDeclaration]()
							for label in childNewLabels {
								childNewDeclarationByLabel[label] = childClosestDeclarationByLabel[label]
							}
							guard treesBuiltAgain.insert(TreeBuiltAgain(
								cycleClosingScopeParent: walkedScope,
								closedOnProperty: childProperty,
								newDeclarationByLabel: childNewDeclarationByLabel,
								newReceivableProperties: childNewReceivableProperties,
							)).inserted else { continue }
							scopesToWalk.append(ScopeBuiltAgain(
								scope: childScope,
								property: childProperty,
								propertyStack: instantiationStack,
								parentTypeStack: childParentTypeStack,
								closestDeclarationByLabel: childClosestDeclarationByLabel,
								closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
								// As the tree of any child is given them, without the property it builds.
								receivableProperties: childReceivableProperties.subtracting(childPropertyToGenerate.receivableProperties),
								newLabels: childNewLabels,
								newReceivableProperties: childNewReceivableProperties,
								closedOnStackCount: instantiationStack.count - childClosedOnIndex,
							))
						} else {
							// Neither the child nor, when it is lazily instantiated, its instance can be received in the tree it
							// creates.
							var receivablePropertiesInChildTree = childReceivableProperties
							receivablePropertiesInChildTree.remove(declaredChildProperty)
							if let instanceProperty = childPropertyToGenerate.lazilyInstantiatedInstanceProperty {
								receivablePropertiesInChildTree.remove(instanceProperty)
							}
							scopesToWalk.append(ScopeBuiltAgain(
								scope: childScope,
								property: childProperty,
								propertyStack: instantiationStack,
								parentTypeStack: childParentTypeStack,
								closestDeclarationByLabel: childClosestDeclarationByLabel,
								closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
								receivableProperties: receivablePropertiesInChildTree,
								newLabels: childNewLabels,
								newReceivableProperties: childNewReceivableProperties,
								closedOnStackCount: scopeToWalk.closedOnStackCount,
							))
						}
					case .aliased, .hole:
						break
					}
				}
				// The scope walked next is the last one on the stack, so the first child goes last.
				scopesToWalk.reverseElements(from: firstChildIndex)
			}
		}
		/// Validates one scope of a tree, and adds the children to validate after it to `scopesToValidate`, the first
		/// child last.
		/// - Parameters:
		///   - scopeToValidate: The scope, with what the scopes it is built inside give it.
		///   - boundProperties: The received properties the tree's mock binds. See `ValidatedRootScope`.
		///   - mockRootForwardedProperties: The properties the tree's mock root forwards, or `nil` for a tree validated
		///     as production. See `isHanded`.
		///   - validatesCycles: See `validatePropertiesAreFulfillable(inTreeRootedAt:validatesCycles:validatesHiddenProperties:)`.
		///   - validatesHiddenProperties: See `validatePropertiesAreFulfillable(inTreeRootedAt:validatesCycles:validatesHiddenProperties:)`.
		///   - root: The type at the root of the tree.
		/// What an `onlyIfAvailable` alias of `fulfillingProperty` that `scope` declares is bound from, as
		/// `Scope.createScopeGenerator` binds it: a property `scope` provides, else the nearest declaration of the
		/// fulfilling property's label above `scope` – unless it provides no form the alias reads, or the walk descended
		/// through it, so it is still being built – else what encloses the tree. `nil` where the alias is bound to `nil`.
		/// - Parameters:
		///   - closestDeclarationDepthByLabel: The count of the instantiation stack at the scope that declares each of
		///     `closestDeclarationByLabel`.
		///   - instantiationStack: The properties of `scope` and of the scopes it is built inside, innermost first.
		func aliasBinding(
			of fulfillingProperty: Property,
			declaredBy scope: Scope,
			closestDeclarationByLabel: LayeredMap<String, DependencyTreeGeneratorError.LabelDeclaration>,
			closestDeclarationDepthByLabel: LayeredMap<String, Int>,
			receivableProperties: ReceivableProperties,
			boundProperties: Set<Property>,
			instantiationStack: [Property],
		) -> ReceivableAlias.AliasBinding? {
			func isRead(_ declaredProperty: Property) -> Bool {
				ScopeGenerator.provides(declaredProperty, aFormReadBy: fulfillingProperty)
			}
			let forwardedProperties = scope.instantiable.forwardedReceivableProperties
			let ownProviders = scope.providedProperties.filter { $0.label == fulfillingProperty.label && isRead($0) }
			if !ownProviders.isEmpty {
				return ownProviders.allSatisfy(forwardedProperties.contains) ? .handed : .built
			} else if let closestDeclaration = closestDeclarationByLabel[fulfillingProperty.label] {
				guard isRead(closestDeclaration.property) else { return nil }
				// The child of the declaring scope that the walk descended through to reach `scope`.
				let descendedChildIndex = instantiationStack.count - (closestDeclarationDepthByLabel[fulfillingProperty.label] ?? 0) - 1
				if instantiationStack.indices.contains(descendedChildIndex),
				   formsOnStack(of: closestDeclaration.property.asValidatedForDependencyCycles).contains(instantiationStack[descendedChildIndex])
				{
					return nil
				} else {
					return closestDeclaration.isForwarded ? .handed : .built
				}
			} else if fulfillingProperty.formsReadByOnlyIfAvailableReceive.contains(where: { receivableProperties.contains($0) || boundProperties.contains($0) }) {
				return .handed
			} else {
				return nil
			}
		}
		func validatePropertiesAreFulfillable(
			on scopeToValidate: ScopeToValidate,
			boundProperties: Set<Property>,
			mockRootForwardedProperties: Set<Property>?,
			validatesCycles: Bool,
			validatesHiddenProperties: Bool,
			root: TypeDescription,
			scopesToValidate: inout [TreeValidationStep],
		) throws {
			let scope = scopeToValidate.scope
			let receivableProperties = scopeToValidate.receivableProperties
			let receivableAliases = scopeToValidate.receivableAliases
			let closestDeclarationByLabel = scopeToValidate.closestDeclarationByLabel
			let property = scopeToValidate.property
			let propertyStack = scopeToValidate.propertyStack
			let lazilyInstantiatedDeclarations = scopeToValidate.lazilyInstantiatedDeclarations
			let instantiationStack: [Property] = if let property {
				[property] + propertyStack
			} else {
				[]
			}
			/// The nearest declaration of a label above this scope, as `indexOfEntryClosedOn` reads it.
			let nearestDeclaration: (String) -> (properties: [Property], depth: Int)? = { label in
				closestDeclarationByLabel[label].map { ([$0.property.asValidatedForDependencyCycles], scopeToValidate.closestDeclarationDepthByLabel[label, default: 0]) }
			}
			if validatesCycles, let property {
				try validateNoCycleInReceivedProperties(
					scope.requiredReceivedProperties,
					directParent: scope.instantiable.concreteInstantiable,
					receivedPropertyStack: [],
					declaredReceivedPropertyStack: [],
					property: property,
					instantiationStack: instantiationStack,
					lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
					mockRootForwardedProperties: mockRootForwardedProperties,
					nearestDeclaration: nearestDeclaration,
				)
			}

			// The aliases this scope declares, which a receive of their property resolves to: an `onlyIfAvailable` alias is
			// declared even where it is bound to `nil`, so it hides every declaration of its label above it.
			var declaredAliases = [Property: ReceivableAlias]()
			for case let (aliasDependency, .aliased(fulfillingProperty, _, onlyIfAvailable)) in scope.instantiable.dependencies.lazy.map({ ($0, $0.source) }) {
				let alias = ReceivableAlias(
					fulfillingProperty: fulfillingProperty,
					onlyIfAvailable: onlyIfAvailable,
					fulfillingOnlyIfAvailableAliases: [],
					binding: onlyIfAvailable
						? aliasBinding(
							of: fulfillingProperty,
							declaredBy: scope,
							closestDeclarationByLabel: closestDeclarationByLabel,
							closestDeclarationDepthByLabel: scopeToValidate.closestDeclarationDepthByLabel,
							receivableProperties: receivableProperties,
							boundProperties: boundProperties,
							instantiationStack: instantiationStack,
						)
						: .built,
					declaringType: scope.instantiable.concreteInstantiable,
					lastAliasDeclaringType: scope.instantiable.concreteInstantiable,
					lastAliasDeclaringInstantiationStack: instantiationStack,
				)
				declaredAliases[aliasDependency.property] = alias
				// A lazily instantiated alias is also received by value, as the instance it creates.
				if let aliasInstanceProperty = aliasDependency.lazilyInstantiatedInstanceProperty {
					declaredAliases[aliasInstanceProperty] = alias
				}
			}
			// An `onlyIfAvailable` alias of another `onlyIfAvailable` alias is bound from it, so it is `nil` where that
			// alias is: a receive that requires the first requires the second, and so on along any chain of them, as
			// `ScopeGenerator`'s `requiredOnlyIfAvailableAliasProperties` and `requiredAliasFulfillingProperties` order
			// them. No alias of this scope renames another, so the alias's assignment refers, when the scope declares no
			// property of the fulfilling property's label, to the alias a receive of its fulfilling property resolves to
			// here, whose chain its own scope already resolved.
			if !declaredAliases.isEmpty {
				for (aliasProperty, alias) in declaredAliases where alias.onlyIfAvailable {
					if !scope.providedProperties.contains(where: { $0.label == alias.fulfillingProperty.label }),
					   let enclosingAlias = receivableAliases[alias.fulfillingProperty],
					   enclosingAlias.onlyIfAvailable
					{
						declaredAliases[aliasProperty] = ReceivableAlias(
							fulfillingProperty: alias.fulfillingProperty,
							onlyIfAvailable: true,
							fulfillingOnlyIfAvailableAliases: [.init(property: alias.fulfillingProperty, fulfillingProperty: enclosingAlias.fulfillingProperty)]
								+ enclosingAlias.fulfillingOnlyIfAvailableAliases,
							binding: alias.binding.flatMap { _ in enclosingAlias.binding },
							declaringType: alias.declaringType,
							lastAliasDeclaringType: enclosingAlias.lastAliasDeclaringType,
							lastAliasDeclaringInstantiationStack: enclosingAlias.lastAliasDeclaringInstantiationStack,
						)
					}
				}
			}
			// A required receive of an alias reads the alias, so it needs the alias's fulfilling property built first, as
			// the scope that declares the alias would if the alias were not `onlyIfAvailable`. An `onlyIfAvailable` alias
			// is bound from the aliases it renames in turn, so it needs the property the last is bound from – where that
			// is a property the tree builds. An `onlyIfAvailable` alias bound to `nil` passes the receive `nil`.
			for case let (requiredReceivedProperty, alias?) in scope.requiredReceivedProperties.lazy.map({
				($0, declaredAliases[$0.property] ?? receivableAliases[$0.property])
			}) where validatesCycles {
				let receivedProperty = requiredReceivedProperty.property
				// The aliases the receive requires be created, nearest the receive first, each fulfilled by the next's
				// property.
				let requiredAliases = [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias(property: receivedProperty, fulfillingProperty: alias.fulfillingProperty)]
					+ alias.fulfillingOnlyIfAvailableAliases
				let lastRequiredAlias = requiredAliases[requiredAliases.count - 1]
				let fulfillingProperty = lastRequiredAlias.fulfillingProperty
				// The child of the last alias's declaring scope that this scope is built inside, as the instantiation stack
				// holds it: a lazily instantiated property as the constant it stands for. Where it is the property the last
				// alias is bound from, this scope is built inside the alias's own fulfilling sibling, which cannot be built
				// after the alias. An ancestor still being built, further up, makes the alias `nil` instead.
				let declaringChildIndex = instantiationStack.count - alias.lastAliasDeclaringInstantiationStack.count - 1
				let fulfillingSiblingBeingBuilt = instantiationStack.indices.contains(declaringChildIndex)
					? formsOnStack(of: fulfillingProperty.asValidatedForDependencyCycles).first(where: { $0 == instantiationStack[declaringChildIndex] })
					: nil
				if fulfillingSiblingBeingBuilt != nil {
					memoBlockingEventCount += 1
				}
				// A rename that does not erase an instantiator still being built, required or only if available, is rebound
				// inside the instantiator's builder function, as the instantiator is (see `ScopeGenerator.ReceivedBuilderLoops`).
				// The instantiator is the one whose tree this walk is in, so nothing is left to walk.
				if let fulfillingSiblingBeingBuilt,
				   !(ScopeGenerator.isBuilder(fulfillingSiblingBeingBuilt) && requiredAliases.allSatisfy { ScopeGenerator.isBuilder($0.property) })
				{
					throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
						instantiated: fulfillingSiblingBeingBuilt,
						receivedPropertyChain: requiredAliases.map(\.property.asValidatedForDependencyCycles) + [fulfillingSiblingBeingBuilt],
						declarationLocation: requiredReceivedProperty.declarationLocation,
						lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
							closingCycleWith: fulfillingProperty,
							validatedPropertiesInCycle: [fulfillingSiblingBeingBuilt],
							lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
							receivedProperties: requiredAliases.map(\.property),
						),
						requiredOnlyIfAvailableAliases: alias.onlyIfAvailable ? requiredAliases : [],
					)
				} else if fulfillingSiblingBeingBuilt == nil,
				          alias.onlyIfAvailable,
				          case .built? = alias.binding,
				          let declaringProperty = alias.lastAliasDeclaringInstantiationStack.first,
				          case let walkedAliasFulfillingProperty = WalkedAliasFulfillingProperty(
				          	fulfillingProperty: fulfillingProperty,
				          	receivedPropertyStack: requiredAliases.map(\.property.asValidatedForDependencyCycles),
				          	lastAliasDeclaringInstantiationStack: alias.lastAliasDeclaringInstantiationStack,
				          	mockRootForwardedProperties: mockRootForwardedProperties,
				          ),
				          walkedAliasFulfillingProperties.insert(walkedAliasFulfillingProperty).inserted
				{
					// A required alias's fulfilling property is walked where the alias is declared. Walk the property
					// the last required alias is bound from there too, since the receive requires it.
					do {
						do {
							try validateNoCycleInReceivedProperties(
								[Scope.RequiredReceivedProperty(
									property: fulfillingProperty,
									aliasProperty: lastRequiredAlias.property,
									declarationLocation: requiredReceivedProperty.declarationLocation,
									identifierRange: nil,
									typeAnnotationRange: nil,
									bareAttributeRange: nil,
								)],
								directParent: alias.lastAliasDeclaringType,
								receivedPropertyStack: requiredAliases.map(\.property.asValidatedForDependencyCycles),
								declaredReceivedPropertyStack: requiredAliases.map(\.property).filter(\.propertyType.isLazilyInstantiated),
								property: declaringProperty,
								instantiationStack: alias.lastAliasDeclaringInstantiationStack,
								lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
								mockRootForwardedProperties: mockRootForwardedProperties,
								// The walk starts where the alias is declared, whose nearest declarations this scope's do not
								// describe: every receive of a property being built there is judged as being built.
								nearestDeclaration: { _ in nil },
							)
						} catch let DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(instantiated, receivedPropertyChain, declarationLocation, lazilyInstantiatedProperties, _, _) {
							// The chain starts with this receive, which closes it only because it requires the aliases.
							throw DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
								instantiated: instantiated,
								receivedPropertyChain: receivedPropertyChain,
								declarationLocation: declarationLocation,
								lazilyInstantiatedProperties: lazilyInstantiatedProperties,
								requiredOnlyIfAvailableAliases: requiredAliases,
							)
						}
					} catch {
						// The next tree that reaches this alias walks it again, and reports the same error, rather than
						// skipping it and validating what this tree did not reach because it stopped here.
						walkedAliasFulfillingProperties.remove(walkedAliasFulfillingProperty)
						throw error
					}
				}
			}

			for requiredReceivedProperty in scope.requiredReceivedProperties where validatesCycles {
				let receivedProperty = requiredReceivedProperty.property
				let parentContainsProperty = receivableProperties.contains(receivedProperty)
				let propertyIsCreatedAtThisScope = scope.createdProperties.contains(receivedProperty)
				guard !parentContainsProperty, !propertyIsCreatedAtThisScope, property != nil else { continue }
				// The instantiation stack holds a lazily instantiated property as the constant it stands for.
				let beingBuiltIndex = receivableProperties.contains(receivedProperty.asUnwrappedProperty)
					? nil
					: instantiationStack.firstIndex(of: receivedProperty.asUnwrappedProperty.asValidatedForDependencyCycles)
				if !cyclesOnly || beingBuiltIndex != nil {
					// A mock binds every property its tree receives from above it, so there only a property still
					// being built is unfulfillable. A non-optional one is a cycle, reported below.
					// This property is in a dependency tree and is unfulfillable. Record the problem.
					memoBlockingEventCount += 1
					unfulfillableProperties.insert(.init(
						property: receivedProperty,
						declarationLocation: requiredReceivedProperty.declarationLocation,
						identifierRange: requiredReceivedProperty.identifierRange,
						typeAnnotationRange: requiredReceivedProperty.typeAnnotationRange,
						bareAttributeRange: requiredReceivedProperty.bareAttributeRange,
						instantiable: scope.instantiable,
						parentStack: propertyStack.map(\.typeDescription),
						root: root,
						// A near-match that the closest declaration of its label, of another type, hides is left out: receiving it
						// would be reported as hidden (`recordHiddenReceives`).
						suggestedAlternatives: receivableProperties.filter { alternative in
							(receivedProperty.typeDescription.leastQualifiedTypeDescription == alternative.typeDescription.leastQualifiedTypeDescription
								|| receivedProperty.label == alternative.label)
								&& closestDeclarationByLabel[alternative.label]?.fulfills(anyOf: [alternative, alternative.asUnwrappedProperty]) != false
						}.sorted(),
						instantiatedDeclaration: instantiatedDeclaration(
							of: receivedProperty,
							receivedBy: scope,
							instantiationStack: instantiationStack,
							root: root,
							closestDeclarationByLabel: closestDeclarationByLabel,
						),
						sendableBoundaryAdvice: Self.sendableBoundaryAdvice(
							for: receivedProperty,
							receivedBy: scope,
							instantiationStack: instantiationStack.map { lazilyInstantiatedDeclarations[$0] ?? $0 },
							parentTypeStack: scopeToValidate.parentTypeStack,
							root: root,
							typeDescriptionToFulfillingInstantiableMap: typeDescriptionToFulfillingInstantiableMap,
						),
						declarationsHidingReceiveInMocks: declarationsHidingReceiveInMocks(of: receivedProperty, receivedBy: scope.instantiable.concreteInstantiable),
					))
				}
			}

			if validatesHiddenProperties {
				// A rename of a label this scope's type declares refers to that declaration, before any ancestor's.
				let renames = Self.renamesContradictingOwnProperties(in: scope)
				if !renames.isEmpty {
					memoBlockingEventCount += 1
					renamesContradictingOwnProperties.formUnion(renames)
				}
				recordHiddenReceives(
					of: scope,
					closestDeclarationByLabel: closestDeclarationByLabel,
					receivableProperties: receivableProperties,
					propertyStack: propertyStack,
					parentTypeStack: scopeToValidate.parentTypeStack,
					root: root,
				)
			}

			// Check children for cycles.
			var childPropertyStack = propertyStack
			var childParentTypeStack = scopeToValidate.parentTypeStack
			if let property {
				childPropertyStack.insert(property, at: 0)
				childParentTypeStack.insert(scope.instantiable.concreteInstantiable, at: 0)
			}
			for dependency in scope.instantiable.dependencies where validatesCycles && dependency.canCloseDependencyCycle {
				let declaredPropertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
				let propertyForDependency = declaredPropertyForDependency.asValidatedForDependencyCycles
				// A stack entry matches only a property of its label, and nearly every dependency's label is on no entry.
				guard childPropertyStack.contains(where: { $0.label == propertyForDependency.label }) else { continue }
				let closingReceive = Self.closingReceive(of: dependency, in: scope)
				// `throwIfInvalidCycle` throws for an instantiation only when every property on the cycle, its own included, is
				// constant, so an instantiation of an instantiator closes no cycle it could report.
				guard closingReceive != nil || propertyForDependency.propertyType.isConstant, let cycleIndex = Self.indexOfEntryClosedOn(
					by: declaredPropertyForDependency,
					of: scope,
					receivedForms: [propertyForDependency],
					closesByReceive: closingReceive != nil,
					propertyStack: childPropertyStack,
					concreteTypeOfEntry: { childParentTypeStack[$0] },
					nearestDeclaration: nearestDeclaration,
				) else {
					continue
				}
				memoBlockingEventCount += 1
				let propertiesInCycle = [propertyForDependency] + childPropertyStack[0...cycleIndex]
				try throwIfInvalidCycle(
					propertiesInCycle: propertiesInCycle,
					// A receive is reported as declared; an instantiation as the property it instantiates.
					declaredProperty: closingReceive == nil ? declaredPropertyForDependency : dependency.property,
					declarationLocation: dependency.declarationLocation,
					directParent: scope.instantiable.concreteInstantiable,
					closingReceive: closingReceive,
					lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
						closingCycleWith: declaredPropertyForDependency,
						validatedPropertiesInCycle: propertiesInCycle,
						lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations,
					),
				)
			}
			// Most scopes build no child, so what the children would see is gathered only for one that builds one.
			guard scope.propertiesToGenerate.contains(where: { $0.builtScope != nil }) else { return }
			var childClosestDeclarationByLabel = closestDeclarationByLabel
			var childClosestDeclarationDepthByLabel = scopeToValidate.closestDeclarationDepthByLabel
			enterDeclarations(of: scope, into: &childClosestDeclarationByLabel) {
				childClosestDeclarationDepthByLabel[$0] = instantiationStack.count
			}
			childClosestDeclarationByLabel = childClosestDeclarationByLabel.compacted
			childClosestDeclarationDepthByLabel = childClosestDeclarationDepthByLabel.compacted
			// A property this scope provides shadows an alias of it declared above.
			var childReceivableAliases = receivableAliases.filter {
				!scope.providedProperties.containsPropertyOrItsUnwrappedForm($0.key)
			}
			for (aliasProperty, alias) in declaredAliases {
				childReceivableAliases[aliasProperty] = alias
			}
			// What the scopes this scope builds receive, with the depth since which each has been receivable, which the validation
			// of mocks never reads.
			var childReceivableProperties = receivableProperties
			var childReceivableDepthByProperty = scopeToValidate.receivableDepthByProperty
			insertProperties(madeAvailableBy: scope, given: receivableProperties, instantiationStack: instantiationStack, nearestDeclaration: nearestDeclaration, into: &childReceivableProperties) {
				if !cyclesOnly {
					childReceivableDepthByProperty[$0] = instantiationStack.count
				}
			}
			childReceivableProperties = childReceivableProperties.compacted
			childReceivableDepthByProperty = childReceivableDepthByProperty.compacted
			let firstChildIndex = scopesToValidate.endIndex
			for childPropertyToGenerate in scope.propertiesToGenerate {
				switch childPropertyToGenerate {
				case let .instantiated(declaredChildProperty, childScope, _):
					// A lazily instantiated property is validated as the constant it stands for.
					let childProperty = declaredChildProperty.asValidatedForDependencyCycles
					// Neither the child nor, when it is lazily instantiated, its instance can be received in the tree it creates,
					// but an instantiator, which its builder function rebinds (see `ScopeGenerator.ReceivedBuilderLoops`).
					var propertiesWithheldFromChildTree = [Property]()
					if !ScopeGenerator.isBuilder(declaredChildProperty) {
						propertiesWithheldFromChildTree.append(declaredChildProperty)
					}
					if let instanceProperty = childPropertyToGenerate.lazilyInstantiatedInstanceProperty {
						propertiesWithheldFromChildTree.append(instanceProperty)
					}
					let receivablePropertiesInChildTree = childReceivableProperties.withholding(propertiesWithheldFromChildTree)
					let childToValidate = ScopeToValidate(
						scope: childScope,
						receivableProperties: receivablePropertiesInChildTree,
						receivableAliases: childReceivableAliases,
						closestDeclarationByLabel: childClosestDeclarationByLabel,
						closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
						receivableDepthByProperty: childReceivableDepthByProperty,
						property: childProperty,
						propertyStack: childPropertyStack,
						parentTypeStack: childParentTypeStack,
						lazilyInstantiatedDeclarations: lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
					)
					if let closedOnIndex = childPropertyStack.indices.first(where: {
						childPropertyStack[$0] == childProperty && childParentTypeStack[$0] == childScope.instantiable.concreteInstantiable
					}) {
						// There is a cycle in our scope tree. Do not re-enter it: walk the tree the cycle-closing scope builds
						// again, in its turn. The walk decides whether a walk above it can still be remembered.
						scopesToValidate.append(.cycleClosingScope(CycleClosingScopeToValidate(
							scope: childScope,
							property: childProperty,
							closedOnIndex: closedOnIndex,
							cycleClosingScopeParent: scope,
							propertyStack: childPropertyStack,
							parentTypeStack: childParentTypeStack,
							closestDeclarationByLabel: childClosestDeclarationByLabel,
							closestDeclarationDepthByLabel: childClosestDeclarationDepthByLabel,
							enclosingReceivableProperties: childReceivableProperties,
							receivablePropertiesOfClosingProperty: childPropertyToGenerate.receivableProperties,
							receivableDepthByProperty: childReceivableDepthByProperty,
							asScopeToValidate: childToValidate,
						)))
					} else {
						scopesToValidate.append(.scope(childToValidate))
					}
				case .aliased, .hole:
					// A hole's tree is a fill's, which the module that fills it validates: the validated scopes hold no
					// hole, since they leave out a dependency no scope builds.
					break
				}
			}
			// The scope validated next is the last one on the stack, so the first child goes last.
			scopesToValidate.reverseElements(from: firstChildIndex)
		}

		// Each tree reports the first error it throws, and the errors of every tree are reported, rather than the
		// unfulfillable and hidden properties the walks record.
		var rootErrors = [DependencyTreeGeneratorError]()
		for rootScope in rootScopes {
			do {
				try validatePropertiesAreFulfillable(
					inTreeRootedAt: rootScope,
					validatesCycles: true,
					// A production root without a mock is validated for production; only mocks generate its tree here.
					validatesHiddenProperties: !cyclesOnly
						|| rootScope.scope.instantiable.generatesMock
						|| additionalMockRootScopes.contains { $0.scope == rootScope.scope },
				)
			} catch let error as DependencyTreeGeneratorError {
				rootErrors.append(error)
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: rootErrors) {
			throw error
		}
		// Walking the other additional mock roots for cycles here could reject a mock that compiles today. Their
		// mocks are validated for cycles after promotion, in `createMockRootScopeGenerator`. That holds only where no
		// call's place is filled: over the trees built inline with the fills, `validateCyclesOfCallsWithPlaces` walks
		// them among the roots above (`validatesAdditionalMockRootsForCycles`), since a cycle through a fill is real there
		// and the mock that fills the place does not compile.
		for rootScope in additionalMockRootScopes where !rootScopes.contains(where: { $0.scope == rootScope.scope }) {
			try validatePropertiesAreFulfillable(
				inTreeRootedAt: rootScope,
				validatesCycles: false,
				validatesHiddenProperties: true,
			)
		}

		// A rename that names another type than its own type's property of its label is not received from above, so
		// neither its absence there nor a closer declaration of its label is what is wrong with it.
		if !renamesContradictingOwnProperties.isEmpty {
			throw DependencyTreeGeneratorError.renamesContradictingOwnProperties(Array(renamesContradictingOwnProperties))
		}
		if !unfulfillableProperties.isEmpty {
			let ownAccessProof = ownAccessProof()
			throw DependencyTreeGeneratorError.unfulfillableProperties(unfulfillableProperties.map { $0.withForwardingAccess(proof: ownAccessProof.proof) })
		}
		if !hiddenReceivedProperties.isEmpty {
			throw DependencyTreeGeneratorError.hiddenReceivedProperties(Self.reportingEachSeamsChainOnce(hiddenReceivedProperties, seamTypes: generatedSeamTypes))
		}
	}

	/// The hidden receives `hiddenReceivedProperties` records, each from its root's one chain, without each chain that
	/// reaches a receive through a seam this module generates whose own chain reaches it the same way below the seam: the
	/// walk of the seam's tree reports that receive from the seam's chain, on every path and whatever a caller holds, so
	/// the longer chain is the same error again. A chain is matched by a seam's own chain of the same receive that is
	/// strictly shorter, where the seam is the scope at that depth on the chain and the chains agree below it, between the
	/// seam and the receive; the chains are matched by the concrete types of their scopes, since a chain names each by its
	/// property's type (`ScreenProtocol`, `AnyScreen`). Nested seams therefore report the innermost seam's chain, sibling
	/// seams each their own, and a root whose chain reaches the receive without passing through such a seam keeps its own;
	/// since every match is to a strictly shorter chain, the shortest chains of each receive survive, and no receive loses
	/// its report.
	private static func reportingEachSeamsChainOnce(_ hiddenReceivedProperties: [HiddenReceiveInTree: HiddenReceiveChain], seamTypes: Set<TypeDescription>) -> [DependencyTreeGeneratorError.HiddenReceivedProperty] {
		struct HiddenReceive: Hashable {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			let hidingDeclaration: DependencyTreeGeneratorError.LabelDeclaration
			let receiver: TypeDescription
		}
		let entriesByReceive = Dictionary(grouping: hiddenReceivedProperties) {
			HiddenReceive(property: $0.key.property, declarationLocation: $0.key.declarationLocation, hidingDeclaration: $0.key.hidingDeclaration, receiver: $0.key.receiver)
		}
		var reported = [DependencyTreeGeneratorError.HiddenReceivedProperty]()
		for sameReceive in entriesByReceive.values {
			let fromSeams = sameReceive.filter { seamTypes.contains($0.key.root) }
			func isReportedFromSeamsChain(_ chain: HiddenReceiveChain) -> Bool {
				fromSeams.contains { fromSeam in
					let depth = fromSeam.value.parentStack.count
					return depth < chain.parentStack.count
						&& chain.parentTypeStack[depth] == fromSeam.key.root
						&& Array(chain.parentStack.prefix(depth)) == fromSeam.value.parentStack
						&& Array(chain.parentTypeStack.prefix(depth)) == fromSeam.value.parentTypeStack
				}
			}
			for (hiddenReceive, chain) in sameReceive where !isReportedFromSeamsChain(chain) {
				reported.append(.init(
					property: hiddenReceive.property,
					declarationLocation: hiddenReceive.declarationLocation,
					hidingDeclaration: hiddenReceive.hidingDeclaration,
					enclosingHidingDeclarations: hiddenReceive.enclosingHidingDeclarations,
					receiver: hiddenReceive.receiver,
					parentStack: chain.parentStack,
					root: hiddenReceive.root,
				))
			}
		}
		return reported
	}
}

/// What a walk asks of the properties a scope can receive, so one rule serves a set and a `ReceivableProperties`.
private protocol PropertyMembership {
	func contains(_ property: Property) -> Bool
	/// Inserts `property`, returning whether it was absent.
	mutating func insertIfAbsent(_ property: Property) -> Bool
}

extension Set<Property>: PropertyMembership {
	fileprivate mutating func insertIfAbsent(_ property: Property) -> Bool {
		insert(property).inserted
	}
}

/// What a walk reads and changes of the declaration of each label, so one rule serves a dictionary and a `LayeredMap`.
private protocol LabelDeclarations {
	subscript(_: String) -> DependencyTreeGenerator.DependencyTreeGeneratorError.LabelDeclaration? { get set }
}

extension [String: DependencyTreeGenerator.DependencyTreeGeneratorError.LabelDeclaration]: LabelDeclarations {}

extension DependencyTreeGenerator.LayeredMap<String, DependencyTreeGenerator.DependencyTreeGeneratorError.LabelDeclaration>: LabelDeclarations {}
