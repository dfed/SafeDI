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

/// A model of the scoped dependencies required for an `@Instantiable` in the reachable dependency tree.
final class Scope: Hashable {
	// MARK: Initialization

	/// - Parameters:
	///   - dependenciesLeftOut: The dependencies `instantiable` declared before a mock scope left them out because the
	///     type's hand-written mock is not passed them.
	///   - builtInlineSeamComment: The comment that ends each line of a production tree that constructs the type: a
	///     seam this run builds inline, because SafeDI does not know which module declares it. `nil` for every other
	///     scope.
	///   - seamCall: How a tree that reaches this scope calls it, when the scope stands for a seam whose generated
	///     initializer another tree calls: `instantiable` then declares the initializer's parameters as its
	///     dependencies and builds nothing. `nil` for every other scope.
	///   - isUnavailableDependency: Whether the scope stands for an `@Instantiated(onlyIfAvailable: true)` property that
	///     no production declaration fulfills: it builds nothing, and generated code binds its property to `nil`.
	///   - isCallPlace: Whether the scope stands, in a body of a tree's plan by declaration, for a child on a cycle: see
	///     the property.
	///   - callPlaceRequiredAliasFulfillingProperties: For a call place, what the tree it stands for requires through
	///     `onlyIfAvailable` aliases: see the property.
	init(
		instantiable: Instantiable,
		dependenciesLeftOut: [Dependency] = [],
		builtInlineSeamComment: String? = nil,
		seamCall: SeamCall? = nil,
		publicMockCall: PublicMockCall? = nil,
		isUnavailableDependency: Bool = false,
		isCallPlace: Bool = false,
		callPlaceRequiredAliasFulfillingProperties: Set<Property> = [],
	) {
		self.isUnavailableDependency = isUnavailableDependency
		self.isCallPlace = isCallPlace
		self.callPlaceRequiredAliasFulfillingProperties = callPlaceRequiredAliasFulfillingProperties
		self.instantiable = instantiable
		self.dependenciesLeftOut = dependenciesLeftOut
		self.builtInlineSeamComment = builtInlineSeamComment
		self.seamCall = seamCall
		self.publicMockCall = publicMockCall
	}

	deinit {
		// A chain of scopes can be as long as the module has types, so the scopes this one instantiates are
		// released one at a time rather than from within this deinitializer.
		var propertiesToGenerate = [PropertyToGenerate]()
		swap(&propertiesToGenerate, &self.propertiesToGenerate)
		DeferredRelease.release(consume propertiesToGenerate)
	}

	// MARK: Equatable

	static func == (lhs: Scope, rhs: Scope) -> Bool {
		// Scopes are only identical if they are the same object
		lhs === rhs
	}

	// MARK: Hashable

	func hash(into hasher: inout Hasher) {
		hasher.combine(ObjectIdentifier(self))
	}

	// MARK: Internal

	let instantiable: Instantiable

	/// The dependencies of the type that this scope does not build or receive, because a mock builds the type
	/// with a hand-written mock that is not passed them. Always empty in a scope of the dependency tree.
	let dependenciesLeftOut: [Dependency]

	/// The comment that ends each line of a production tree that constructs the type, or `nil` for none.
	let builtInlineSeamComment: String?

	/// Whether this scope stands for an `@Instantiated(onlyIfAvailable: true)` property that no production declaration
	/// fulfills (`DependencyTreeGenerator.instantiates(_:)`). Its `instantiable` names the type a declaration would
	/// fulfill and declares no dependency, and generated code binds the property to `nil`, a declaration of its label like
	/// the one a fulfilled property gets, so every receive, rename and argument beneath reads it as it reads that one.
	let isUnavailableDependency: Bool

	/// Whether the scope stands, in a body of a tree's plan by declaration (`DependencyTreeGenerator.CallPlaceShadow`), for
	/// a child on a cycle: it has no children, `instantiable` receives what the child's whole tree receives from above,
	/// and it closes no cycle, since a body calls the child's one function at its first build and where a path would
	/// close on it alike. No seam's or public mock's call (`seamCall`, `publicMockCall`), so no reader of those takes it
	/// for a seam's leaf.
	let isCallPlace: Bool

	/// For a call place, the properties the tree it stands for requires through `onlyIfAvailable` aliases whose label no
	/// scope of that tree declares (`DependencyTreeGenerator.ReceivedProperties.requiredAliasFulfillingProperties`): the
	/// call place has no children to carry them, so its generator carries them up, and the sibling that declares one is
	/// built before it, as before the child it stands for today. Empty for every other scope.
	let callPlaceRequiredAliasFulfillingProperties: Set<Property>

	/// How a tree that reaches this scope calls the seam it stands for, or `nil` for a scope that builds its type.
	let seamCall: SeamCall?

	/// How a mock tree that reaches this scope calls the public mock another module generated for its type, which the
	/// tree cannot build itself: `instantiable` then declares the mock's signature as its dependencies and builds
	/// nothing. `nil` for every other scope.
	let publicMockCall: PublicMockCall?

	/// The builders the call `seamCall` or `publicMockCall` stands for passes, or `nil` for a scope that builds its type.
	var calledBuilders: CalledBuilders? {
		seamCall?.calledBuilders ?? publicMockCall?.calledBuilders
	}

	/// The properties that this scope is responsible for instantiating.
	var propertiesToGenerate = [PropertyToGenerate]()

	/// For a scope that calls a seam (`seamCall`) or another module's public mock (`publicMockCall`), how the call passes
	/// each place the builders it passes reach, in the order they reach them. Empty for every other scope.
	var holeArguments = [HoleArgument]()

	/// For a scope that calls another module's public mock, by each filled place's site, what the tree of the type that
	/// fills it receives: the forms its fill reads, which type the fill's parameters (see `parameterField(of:reading:)`).
	/// Empty for every other scope.
	var fillReceivedProperties = [SeamSignature.Hole.Site: Set<Property>]()

	/// For a scope that calls a seam, by each filled place whose fields hold a `LazilyInstantiated`, the labels the tree of
	/// the type that fills it reads in no form it requires: a fill takes such a wrapper optionally where the caller hands
	/// it (see `Fill.optionalLazilyInstantiatedLabels`). Empty for every other scope.
	var fillLabelsReadOnlyIfAvailable = [SeamSignature.Hole.Site: Set<String>]()

	/// How a seam call passes the builder for one of the seam's holes.
	enum HoleArgument {
		/// A function the caller generates, which builds the hole's property with the scope of the type that fulfills
		/// it in the caller's declarations.
		case fill(SeamSignature.Hole, Scope)
		/// The builder of the seam whose tree makes the call, which takes it from its own caller, since the caller's
		/// declarations hold no type that fulfills the hole's property.
		case passUp(SeamSignature.Hole)

		/// The hole the argument is passed for.
		var hole: SeamSignature.Hole {
			switch self {
			case let .fill(hole, _), let .passUp(hole):
				hole
			}
		}
	}

	enum PropertyToGenerate {
		case instantiated(Property, Scope, erasedToConcreteExistential: Bool)
		/// An `@Instantiated` property of a seam's tree whose type no production `@Instantiable` declaration the seam's
		/// module can see fulfills: the generated initializer takes a builder for it, which builds it here.
		case hole(Property, erasedToConcreteExistential: Bool, declarationLocation: Dependency.DeclarationLocation?)
		case aliased(
			Property,
			fulfilledBy: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			/// How the alias’s assignment refers to its `@Received` declaration.
			declarationReference: AliasDeclarationReferences.Reference?,
		)

		/// The property this scope declares.
		var property: Property {
			switch self {
			case let .instantiated(property, _, _),
			     let .hole(property, _, _),
			     let .aliased(property, _, _, _, _):
				property
			}
		}

		/// The scope of the tree this builds, or `nil` for a hole or an alias, which build none.
		var builtScope: Scope? {
			switch self {
			case let .instantiated(_, scope, _):
				scope
			case .hole, .aliased:
				nil
			}
		}

		/// The by-value property with which types further down the tree receive the instance of the lazily
		/// instantiated property this declares. `nil` when it declares none.
		var lazilyInstantiatedInstanceProperty: Property? {
			switch self {
			case let .instantiated(property, _, _), let .hole(property, _, _):
				property.asLazilyInstantiatedInstanceProperty
			case let .aliased(property, _, _, _, _):
				property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
			}
		}

		/// The property this scope declares, followed by `lazilyInstantiatedInstanceProperty` when there is one.
		var receivableProperties: [Property] {
			if let lazilyInstantiatedInstanceProperty {
				[property, lazilyInstantiatedInstanceProperty]
			} else {
				[property]
			}
		}
	}

	/// Every property this scope declares. A lazily instantiated property this scope puts in scope is followed by
	/// the property that receives its instance by value. One it only receives is not: whichever scope created it
	/// already offers that instance, and an `onlyIfAvailable` receive may have nothing behind it.
	private(set) lazy var properties: [Property] = instantiable
		.dependencies
		.flatMap(\.receivableProperties)

	private(set) lazy var createdProperties = Set(
		instantiable
			.dependencies
			.filter {
				switch $0.source {
				case .instantiated, .forwarded:
					// The source is being injected into the dependency tree.
					true
				case .aliased:
					// This property is being re-injected into the dependency tree under a new alias.
					true
				case .received:
					false
				}
			}
			// A lazily instantiated property can also be received by value, as the instance it creates.
			.flatMap(\.receivableProperties),
	)

	/// The created property that provides each form, for `ScopeRecord.createdBinding(of:)`. A type's labels are distinct, so no two
	/// of its created properties provide one form.
	private(set) lazy var createdBindings: [Property: Property] = {
		var createdBindings = [Property: Property]()
		for dependency in instantiable.dependencies where !dependency.source.isReceived {
			for form in CycleParameter.forms(providedBy: dependency.property) where createdBindings[form] == nil {
				createdBindings[form] = dependency.property
			}
		}
		return createdBindings
	}()

	/// The by-value properties with which types further down the tree receive the instance of a lazily
	/// instantiated property this scope’s type forwards.
	private(set) lazy var forwardedLazilyInstantiatedInstanceProperties: [Property] = instantiable
		.dependencies
		.filter { $0.source == .forwarded }
		.compactMap(\.lazilyInstantiatedInstanceProperty)

	/// The `@Instantiated` dependencies of this scope's type that it does not generate, because no scope builds
	/// their type: a mock is passed each as a `mock()` parameter, which the scopes this scope builds receive, as
	/// they would receive the property this scope generated. Always empty in a scope of the dependency tree,
	/// whose validation rejects a dependency no scope builds. Read only once `propertiesToGenerate` is complete.
	private(set) lazy var instantiatedDependenciesNotGenerated: [Dependency] = {
		// A mock root can generate the dependency as the `LazilyInstantiated` its tree receives. One set, not a scan of the
		// children per dependency: a record freezes this for every scope of its map, a root of a thousand children included.
		var generatedProperties = Set<Property>()
		for propertyToGenerate in propertiesToGenerate {
			generatedProperties.insert(propertyToGenerate.property)
			if let instanceProperty = propertyToGenerate.lazilyInstantiatedInstanceProperty {
				generatedProperties.insert(instanceProperty)
			}
		}
		return instantiable.dependencies.filter { dependency in
			switch dependency.source {
			case .instantiated:
				!generatedProperties.contains(dependency.property)
			case .received, .aliased, .forwarded:
				false
			}
		}
	}()

	/// The properties this scope declares for the scopes it builds, which those scopes therefore do not receive
	/// from the scopes above it: those it generates and its type's `instantiatedDependenciesNotGenerated`. A
	/// lazily instantiated property also declares the property that receives its instance by value. Read only
	/// once `propertiesToGenerate` is complete.
	private(set) lazy var propertiesToDeclare = Set(
		propertiesToGenerate.flatMap(\.receivableProperties)
			+ instantiatedDependenciesNotGenerated.flatMap(\.receivableProperties),
	)

	/// The properties this scope declares for the scopes it builds: those it generates, which for a mock root
	/// include the received dependencies promoted to its children, those its type instantiates that it does not
	/// generate, and those its type forwards. A property declared here shadows one with the same label that was
	/// lazily instantiated further up the tree. Read only once `propertiesToGenerate` is complete.
	fileprivate lazy var declaredProperties: [Property] = propertiesToGenerate.map(\.property)
		+ instantiatedDependenciesNotGenerated.map(\.property)
		+ instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property)

	/// The labels of `declaredProperties`.
	private(set) lazy var declaredLabels = Set(declaredProperties.map(\.label))

	/// `declaredProperties` in `Property` order, each with the forms it provides (`CycleParameter.forms(providedBy:)`),
	/// which every tree that builds this scope declares beneath it.
	private(set) lazy var sortedDeclaredPropertyForms: [(property: Property, forms: Set<Property>)] = declaredProperties
		.sorted()
		.map { (property: $0, forms: CycleParameter.forms(providedBy: $0)) }

	/// The by-value properties with which the scopes this scope builds receive the instance of a lazily
	/// instantiated property this scope declares. A mock root can declare a property itself and also be given
	/// a promoted lazily instantiated property with the same label. Types that receive the property by value
	/// are then built with the root's own. Read only once `propertiesToGenerate` is complete.
	private(set) lazy var declaredLazilyInstantiatedInstanceProperties = Set(
		(
			propertiesToGenerate.compactMap(\.lazilyInstantiatedInstanceProperty)
				+ instantiatedDependenciesNotGenerated.compactMap(\.lazilyInstantiatedInstanceProperty)
				+ forwardedLazilyInstantiatedInstanceProperties,
		).filter { !declaredProperties.contains($0) },
	)

	/// The properties this scope makes available to the scopes it builds: those it creates, and those a mock
	/// root builds because a type in its tree receives them. Read only once `propertiesToGenerate` is complete.
	private(set) lazy var providedProperties = createdProperties.union(
		propertiesToGenerate.flatMap { propertyToGenerate in
			switch propertyToGenerate {
			case .instantiated, .hole:
				// A lazily instantiated property is also provided by value, as the instance it creates.
				propertyToGenerate.receivableProperties
			case .aliased:
				// An alias is created, so it is already in `createdProperties`.
				[Property]()
			}
		},
	)

	/// A received property this scope requires an ancestor to provide, with the location of the declaration that requires it.
	struct RequiredReceivedProperty {
		/// The property an ancestor must provide: the fulfilling property for an aliased dependency, the declared property otherwise.
		let property: Property
		/// The declared property of an aliased dependency, which receives `property` under its own label and type. `nil`
		/// for a dependency that receives `property` as declared.
		let aliasProperty: Property?
		let declarationLocation: Dependency.DeclarationLocation?
		/// The range of the identifier a fix-it can rename to a near-match. `nil` for an aliased dependency, whose
		/// unfulfilled name lives in the `@Received(fulfilledByDependencyNamed:)` attribute, not in an identifier token.
		let identifierRange: Dependency.SourceRange?
		/// The range of the type annotation a fix-it can rewrite to a near-match’s type. `nil` for an aliased dependency,
		/// whose unfulfilled type lives in the `@Received(ofType:)` argument, not in the type annotation.
		let typeAnnotationRange: Dependency.SourceRange?
		/// The range of the `@Received` attribute when it has no arguments, which a fix-it can rewrite to
		/// `@Received(onlyIfAvailable: true)`. `nil` for an aliased dependency, whose attribute always has arguments.
		let bareAttributeRange: Dependency.SourceRange?
	}

	/// The received properties this scope requires an ancestor to provide. An alias of a property this scope creates
	/// refers to that property, so it requires nothing of an ancestor: what that property needs, its own declaration
	/// requires. No alias of this scope renames another (SafeDITool rejects that before it validates a tree that builds
	/// the scope), so such a property is one the scope instantiates or is forwarded.
	private(set) lazy var requiredReceivedProperties: [RequiredReceivedProperty] = instantiable
		.dependencies
		.compactMap {
			switch $0.source {
			case let .received(onlyIfAvailable):
				if onlyIfAvailable {
					nil
				} else {
					RequiredReceivedProperty(
						property: $0.property,
						aliasProperty: nil,
						declarationLocation: $0.declarationLocation,
						identifierRange: $0.identifierRange,
						typeAnnotationRange: $0.typeAnnotationRange,
						bareAttributeRange: $0.bareAttributeRange,
					)
				}
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				if onlyIfAvailable || createdProperties.contains(fulfillingProperty) {
					nil
				} else {
					RequiredReceivedProperty(
						property: fulfillingProperty,
						aliasProperty: $0.property,
						declarationLocation: $0.declarationLocation,
						identifierRange: nil,
						typeAnnotationRange: nil,
						bareAttributeRange: nil,
					)
				}
			case .forwarded,
			     .instantiated:
				nil
			}
		}
}

extension ScopeRecord {
	/// Creates the generator of the tree this scope creates. The generators of the scopes in the tree are
	/// created depth first, each after the generators of the scopes it creates, with a stack of the scopes
	/// whose generator is under construction, since a tree can be as deep as the module has types.
	/// - Parameters:
	///   - nearestDeclarations: The declarations that enclose the whole tree, by label: none for a root of the dependency
	///     tree, a seam's parameters (see `NearestDeclarations.replacing(_:)`), and the received properties a mock root
	///     binds (see `NearestDeclarations.binding(_:)`). Each scope judges whether what it receives only if available is
	///     available against the nearest declaration of its label (see `ScopeGeneratorUnderConstruction`).
	///   - seamRoot: What the root generator emits when the tree is a seam's: its signature and the hand-written
	///     initializer's arguments. `nil` for a root of the dependency tree and for a mock root.
	///   - validatesForwardedProperties: Whether each erased instantiator's first generic argument is checked against the
	///     `@Forwarded` properties of the type it builds. The inline tree of another module's seam, built only to read its
	///     generators' sets, skips it: that seam's module and the fills of its holes check every erased instantiator of
	///     the tree, seeing through the seam's module, which the inline tree cannot.
	///   - mockBuilders: For a public mock's root, the builders its `mock()` takes, which each site of the tree calls and
	///     each call of another module's public mock hands its places up to, as a seam's tree calls the builders of
	///     `seamRoot`'s signature.
	///   - constructionMemo: The memo of the trees created before this one, whose generators the tree's first pass may
	///     reuse when it is shared across trees, and which then keeps that pass's generators once the tree is created
	///     (see `ConstructionMemo.Sharing`).
	///   - scopeGeneratorLimit: The number of places the tree's passes may build or reuse between them, past which its
	///     caller is asked whether to abandon the tree (`ScopeGeneratorLimitExceeded`, and the memo keeps nothing of
	///     it), to build on with no limit, or to build on and be asked again past more places
	///     (`ScopeGeneratorLimit.Answer`), or `nil` for a tree built whatever its size.
	///
	/// The tree is created again while a scope that a lazy cycle closes on finds other parameters for its builder
	/// function than it was created with (see `CycleParameter`): its cycle-closing scopes, created before it, pass
	/// those parameters, and count what they pass among the properties they receive. Nearly every tree has no such
	/// scope and is created once. A pass changes a scope's parameters only through the parameters of the functions it
	/// is nested in or that are nested in it, which only add to what it receives or declares, so the passes end once
	/// the parameters at each level of nesting have settled.
	///
	/// A tree that holds a place of a hole is also created again when a scope's children would start in another order by
	/// what its type's properties hold (`SeamDeclarationGraph`) than by what their subtrees hold on its path, which only a
	/// tangle of cycles, or a type that one declaration builds outside a cycle and another builds inside one, makes them
	/// do: the pass after creates each scope outside a fill with the properties of its type that hold a place
	/// (`ScopeGenerator.startsAsCarrier(_:)`). The order decides nothing a pass creates, so the graph of
	/// the pass after is the same.
	func createScopeGenerator(
		in table: ScopeTable,
		nearestDeclarations: NearestDeclarations = NearestDeclarations(),
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot? = nil,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool = false,
		validatesForwardedProperties: Bool = true,
		declaredTypeNames: DeclaredTypeNames,
		constructionMemo: inout ConstructionMemo,
		scopeGeneratorLimit: ScopeGeneratorLimit? = nil,
	) throws -> ScopeGenerator {
		var unrecordedPlaces: TypeFactsPlaces?
		let scopeGenerator = try createdTree(
			in: table,
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			declaredTypeNames: declaredTypeNames,
			constructionMemo: &constructionMemo,
			typeFactsPlaces: &unrecordedPlaces,
			scopeGeneratorLimit: scopeGeneratorLimit,
		)
		if let observer = ConstructionMemoOracle.observer {
			// The build with the memo shares it across every tree created with this memo, whatever the memo's own sharing,
			// so that the oracle judges every reuse either sharing makes. The places it keys are the oracle's, not the tree's, so no test sees them.
			var oracleMemo = constructionMemo.oracleMemo
			let treeBuiltWithMemo = try ConstructionMemoOracle.$keyedPlaceObserver.withValue(nil) { try ConstructionMemoOracle.$reusedPlaceObserver.withValue(nil) {
				try createdTree(
					in: table,
					nearestDeclarations: nearestDeclarations,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
					seamRoot: seamRoot,
					mockBuilders: mockBuilders,
					erasedToConcreteExistential: erasedToConcreteExistential,
					forMockGeneration: forMockGeneration,
					validatesForwardedProperties: validatesForwardedProperties,
					declaredTypeNames: declaredTypeNames,
					constructionMemo: &oracleMemo,
					typeFactsPlaces: &unrecordedPlaces,
					scopeGeneratorLimit: nil,
				)
			} }
			constructionMemo.oracleMemo = oracleMemo
			// The reference tree is built with neither the memo nor the settled cycle parameter seed, so every
			// graph compares the seeded build with the plain pass loop as well.
			// It reuses nothing, so it walks every place, which it records for the graph of per-type facts to be compared with.
			var places: TypeFactsPlaces? = TypeFactsPlaces()
			let treeBuiltWithoutMemo = try ConstructionMemo.$isEnabled.withValue(false) { try CycleParameterPlan.$isEnabled.withValue(false) {
				var unusedMemo = ConstructionMemo()
				return try createdTree(
					in: table,
					nearestDeclarations: nearestDeclarations,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
					seamRoot: seamRoot,
					mockBuilders: mockBuilders,
					erasedToConcreteExistential: erasedToConcreteExistential,
					forMockGeneration: forMockGeneration,
					validatesForwardedProperties: validatesForwardedProperties,
					declaredTypeNames: declaredTypeNames,
					constructionMemo: &unusedMemo,
					typeFactsPlaces: &places,
					scopeGeneratorLimit: nil,
				)
			} }
			observer(treeBuiltWithMemo, treeBuiltWithoutMemo, TypeFactsReport(root: ConstructionScope(table: table, record: self), places: places ?? TypeFactsPlaces(), forMockGeneration: forMockGeneration))
		}
		return scopeGenerator
	}

	/// The tree `createScopeGenerator` creates, in as many passes as it takes.
	/// - Parameter scopeGeneratorLimit: The number of places the passes may build or reuse between them before the caller
	///   is asked whether to abandon the tree (`ScopeGeneratorLimitExceeded`), or `nil` for a tree built whatever its
	///   size. A tree within the limit, and one its caller keeps, is built exactly as without one.
	private func createdTree(
		in table: ScopeTable,
		nearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders?,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		validatesForwardedProperties: Bool,
		declaredTypeNames: DeclaredTypeNames,
		constructionMemo: inout ConstructionMemo,
		typeFactsPlaces: inout TypeFactsPlaces?,
		scopeGeneratorLimit: ScopeGeneratorLimit?,
	) throws -> ScopeGenerator {
		// The places every pass so far has built or reused, which `scopeGeneratorLimit` bounds until its caller keeps the
		// tree, and then no longer.
		var scopeGeneratorCount = 0
		var scopeGeneratorLimit = scopeGeneratorLimit
		var previousPassGenerator: ScopeGenerator?
		// The cycle parameters settled on the first pass's tree, which the second pass is built with in place of the first
		// pass's findings (see `CycleParameterPlan`), or `nil` where the tree is not planned.
		var cycleParameterSeed: CycleParameterSeed?
		// The memo of the pass before, whose settled generators a pass reuses (see `ConstructionMemo.settledReuse`), and the
		// place-holding properties that pass read.
		var previousPassMemo: ConstructionMemo?
		var placeHoldingPropertiesOfPreviousPass: [TypeDescription: Set<Property>]?
		// A tree with a seam root or a mock root's builders reads its own `SeamHoles` (its values bindings, member calls,
		// builder structs and the names the seam binds), constant within the tree but not across trees, so its memo is never
		// shared across trees or kept past a pass. Its places with holes store nothing; a seam without holes memoizes the
		// rest, a pass at a time.
		let sharesMemo = seamRoot == nil && mockBuilders == nil
		var placeHoldingPropertiesByType: [TypeDescription: Set<Property>]?
		var scopeGenerator: ScopeGenerator
		// Every scope of the tree is enclosed by these, so they are held in storage each scope's copy shares.
		let nearestDeclarations = nearestDeclarations.sharingDeclarations()
		var startOrderChanged: Bool
		// Every pass reads the scopes as they are now, which nothing changes while the tree is built.
		let root = ConstructionScope(table: table, record: self)
		// The tree's plan by declaration, built only where a test reads it and read by nothing that generates code.
		var placeReadLabels: PlaceReadLabels?
		if PerTypePlanObservation.observer != nil || PerTypePlanObservation.variantsObserver != nil || PlaceReadsObservation.observer != nil, let plan = PerTypePlan(root: root) {
			PerTypePlanObservation.observer?(plan.projection)
			if let variantsObserver = PerTypePlanObservation.variantsObserver {
				variantsObserver(PlanVariants(plan: plan).projection)
			}
			placeReadLabels = PlanVariants.placeReadLabels(of: plan)
		}
		// Within a pass, a memo that only this tree reads reuses a place's generator only at another place of the same scope,
		// so no pass keys, looks up or stores a place of a scope the tree builds at one place only. A memo shared across trees
		// keys every place, since a later tree can reach any of them, and so does the sharing oracle's build that offers each
		// place what a place after it built, which a place at one place can reuse. So does a tree that may take a later pass,
		// which reuses what the pass before built only through its entries (`ScopesBuiltAtOnePlace.init(treeRootedAt:)`).
		let keysPlacesAtOnePlace = sharesMemo && constructionMemo.sharing == .acrossTrees
			|| ConstructionSharingSchedule.current?.offersLaterPlacesCandidates == true
		let scopesBuiltAtOnePlace = keysPlacesAtOnePlace || !ConstructionMemo.isEnabled ? nil : ScopesBuiltAtOnePlace(treeRootedAt: root)
		repeat {
			// A memo shared across trees carries each pass to the pass after it, whose keys name the generators of the pass
			// before, so a later pass of this tree reuses what a later pass of another tree built from the same generator.
			var passMemo = sharesMemo ? constructionMemo.memo(forPassAfter: previousPassMemo) : ConstructionMemo()
			// A place whose generator the pass before built settled is reused across passes only while the passes share
			// the place-holding properties every place's build reads.
			let settledPassMemo = placeHoldingPropertiesByType == placeHoldingPropertiesOfPreviousPass ? previousPassMemo : nil
			if previousPassGenerator == nil, ConstructionMemo.isEnabled, ConstructionSharingSchedule.current?.offersLaterPlacesCandidates == true {
				// The sharing oracle offers each place what a place after it built: the first pass starts from what a
				// discarded build of the same pass stored, which the schedule asks newest first.
				var discardedPlaces: TypeFactsPlaces?
				var discardedCount = 0
				var discardedLimit: ScopeGeneratorLimit?
				_ = try createScopeGenerator(
					nearestDeclarations: nearestDeclarations,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
					seamRoot: seamRoot,
					mockBuilders: mockBuilders,
					erasedToConcreteExistential: erasedToConcreteExistential,
					forMockGeneration: forMockGeneration,
					validatesForwardedProperties: validatesForwardedProperties,
					declaredTypeNames: declaredTypeNames,
					previousPassGenerator: nil,
					cycleParameterSeed: nil,
					placeHoldingPropertiesByType: placeHoldingPropertiesByType,
					memo: &passMemo,
					settledPassMemo: nil,
					root: root,
					scopesBuiltAtOnePlace: scopesBuiltAtOnePlace,
					typeFactsPlaces: &discardedPlaces,
					placeReadLabels: placeReadLabels,
					scopeGeneratorLimit: &discardedLimit,
					scopeGeneratorCount: &discardedCount,
				)
			}
			// A recorded tree keeps the places of its last pass, which is the tree.
			var passPlaces: TypeFactsPlaces? = typeFactsPlaces == nil ? nil : TypeFactsPlaces()
			scopeGenerator = try createScopeGenerator(
				nearestDeclarations: nearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				seamRoot: seamRoot,
				mockBuilders: mockBuilders,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
				validatesForwardedProperties: validatesForwardedProperties,
				declaredTypeNames: declaredTypeNames,
				previousPassGenerator: previousPassGenerator,
				cycleParameterSeed: cycleParameterSeed,
				placeHoldingPropertiesByType: placeHoldingPropertiesByType,
				memo: &passMemo,
				settledPassMemo: settledPassMemo,
				root: root,
				scopesBuiltAtOnePlace: scopesBuiltAtOnePlace,
				typeFactsPlaces: &passPlaces,
				placeReadLabels: placeReadLabels,
				scopeGeneratorLimit: &scopeGeneratorLimit,
				scopeGeneratorCount: &scopeGeneratorCount,
			)
			if passPlaces != nil {
				typeFactsPlaces = passPlaces
			}
			if previousPassGenerator == nil {
				cycleParameterSeed = Self.cycleParameterSeed(
					ofFirstPassTree: scopeGenerator,
					seamRoot: seamRoot,
					mockBuilders: mockBuilders,
					nearestDeclarations: nearestDeclarations,
					forMockGeneration: forMockGeneration,
				)
			} else {
				cycleParameterSeed = nil
			}
			if sharesMemo {
				passMemo.keepAlive(passTree: scopeGenerator, seed: cycleParameterSeed)
			}
			previousPassMemo = passMemo
			placeHoldingPropertiesOfPreviousPass = placeHoldingPropertiesByType
			previousPassGenerator = scopeGenerator
			startOrderChanged = false
			if placeHoldingPropertiesByType == nil, scopeGenerator.containsBuildSite {
				let graph = SeamDeclarationGraph(treeRootedAt: scopeGenerator)
				if graph.ordersChildrenOtherwiseThanTheirPaths(inTreeRootedAt: scopeGenerator) {
					placeHoldingPropertiesByType = graph.placeHoldingPropertiesByType
					startOrderChanged = true
				}
			}
		} while startOrderChanged || scopeGenerator.cycleParametersChangedInTree || scopeGenerator.fillStructBoundLabelsChangedInTree || scopeGenerator.receivedBuilderLoopsChangedInTree || scopeGenerator.publicMockLevelReentriesChangedInTree
		// The entries of a tree are kept only once its construction returns. A mock root whose construction throws keeps
		// none, and its error, `ErasedInstantiatorForwardedPropertiesMismatchError`, the only one construction throws, ends
		// the whole mock pass, so no later mock root reads the memo after a root that failed. A change that adds a
		// construction error the mock pass catches owes a test that such a root, first, in the middle and last, reports
		// the same errors, and leaves the other roots the same mocks, with the memo shared between mock roots and without it.
		if sharesMemo, let previousPassMemo {
			constructionMemo.keepEntries(ofLastPass: previousPassMemo)
		}
		return scopeGenerator
	}

	/// The cycle parameters `CycleParameterPlan` settles on `tree`, a first pass's, where only they would drive the passes
	/// after it, or `nil`: a tree with a seam root, a mock root's builders, a receive a mock passes `nil`, a call or fill, or a
	/// build site keeps the plain passes, as does a tree whose parameters the first pass found settled. So does a mock's
	/// tree, where settling cost more than the passes it saved: on issue #646's graph of twelve mocks, its later passes
	/// reuse most of the pass before's generators, while the pass a seed builds reuses few of the first pass's.
	private static func cycleParameterSeed(
		ofFirstPassTree tree: ScopeGenerator,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders?,
		nearestDeclarations: NearestDeclarations,
		forMockGeneration: Bool,
	) -> CycleParameterSeed? {
		guard CycleParameterPlan.isEnabled,
		      !forMockGeneration,
		      tree.cycleParametersChangedInTree,
		      seamRoot == nil,
		      mockBuilders == nil,
		      !nearestDeclarations.mayPassNil,
		      !tree.treeHoldsCallOrFill,
		      !tree.containsBuildSite
		else { return nil }
		return CycleParameterPlan.settledSeed(ofTreeRootedAt: tree)
	}

	/// One pass of `createScopeGenerator`, which reads the parameters of the builder functions lazy cycles close on
	/// from `previousPassGenerator`, the tree the pass before created, or finds none when there is no pass before.
	/// - Parameter memo: The generators already finished, which a later place of the same key whose context answers their
	///   reads alike reuses, and where this pass stores the generators it finishes (see `ConstructionMemo`).
	/// - Parameter scopesBuiltAtOnePlace: The scopes the tree builds at one place only, whose places are not keyed, looked up
	///   or stored, or `nil` where every place is keyed: where the memo carries generators to other trees, where the sharing
	///   oracle's build offers each place what a later place built, and where the memo is off, which keys nothing. Otherwise no other place of the pass has its key, so a lookup can only miss,
	///   and its entry could serve only the pass after (`ConstructionMemo.settledReuse`), which builds the place again
	///   instead, reusing what the pass before stored of the places beneath it.
	private func createScopeGenerator(
		nearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders?,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		validatesForwardedProperties: Bool,
		declaredTypeNames: DeclaredTypeNames,
		previousPassGenerator: ScopeGenerator?,
		cycleParameterSeed: CycleParameterSeed?,
		placeHoldingPropertiesByType: [TypeDescription: Set<Property>]?,
		memo: inout ConstructionMemo,
		settledPassMemo: ConstructionMemo?,
		root: ConstructionScope,
		scopesBuiltAtOnePlace: ScopesBuiltAtOnePlace?,
		typeFactsPlaces: inout TypeFactsPlaces?,
		placeReadLabels: PlaceReadLabels?,
		scopeGeneratorLimit: inout ScopeGeneratorLimit?,
		scopeGeneratorCount: inout Int,
	) throws -> ScopeGenerator {
		// The position of each scope under construction among the places recorded, where a test records them.
		var placeIndices = [typeFactsPlaces?.start(TypeFactsDeclaration(scope: root, property: nil, propertyID: nil, erasedToConcreteExistential: false, isFill: false), parent: nil)]
		var scopeGeneratorsUnderConstruction = [ScopeGeneratorUnderConstruction(
			scope: root,
			property: nil,
			contextStack: ContextStack(),
			depth: 0,
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			seamHoles: seamRoot.map { SeamHoles(of: $0, seamType: instantiable.concreteInstantiable) }
				?? mockBuilders.map { SeamHoles(seamType: instantiable.concreteInstantiable, holes: $0.holes, builders: $0.builders, callRoutes: $0.callRoutes) }
				?? SeamHoles(),
			sitePath: [],
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			declaredTypeNames: declaredTypeNames,
			previousPassGenerator: previousPassGenerator,
			cycleParameterSeed: cycleParameterSeed,
			cycleParameterContexts: [:],
			placeHoldingPropertiesByType: placeHoldingPropertiesByType,
			// A root's place is never stored, so only a recorded place keeps what its subtree read.
			recordsReads: typeFactsPlaces != nil,
		)]
		let reusesGenerators = ConstructionMemo.isEnabled
		// The sharing oracle's schedule, test only, and how many lookups it has drawn for (`ConstructionSharingSchedule`).
		let sharingSchedule = ConstructionSharingSchedule.current
		var lookupCount = 0
		let keyedPlaceObserver = ConstructionMemoOracle.keyedPlaceObserver
		let reusedPlaceObserver = ConstructionMemoOracle.reusedPlaceObserver
		let placeReadsObserver = PlaceReadsObservation.observer
		// The generators of the calls that pass fills this tree holds, none of which it may hold twice
		// (`ConstructionMemo.Entry.callGenerators`).
		var callGeneratorsInTree = Set<ObjectIdentifier>()
		while true {
			let index = scopeGeneratorsUnderConstruction.count - 1
			if let propertyToGenerate = scopeGeneratorsUnderConstruction[index].nextPropertyToGenerate() {
				switch propertyToGenerate {
				case let .instantiated(property, scope, erasedToConcreteExistential, propertyID):
					try scopeGeneratorsUnderConstruction[index].validateForwardedProperties(ofChildBuilding: scope, as: property)
					// Every place counts, built or reused: a tree that grows with its paths reuses most of them.
					scopeGeneratorCount += 1
					if let limit = scopeGeneratorLimit, scopeGeneratorCount > limit.places {
						switch limit.answer(limit.places) {
						case .abandonsTree:
							throw ScopeGeneratorLimitExceeded()
						case .keepsTree:
							// The caller keeps this tree: it is built on as if no limit had been given.
							scopeGeneratorLimit = nil
						case let .asksAgain(pastPlaces):
							scopeGeneratorLimit = ScopeGeneratorLimit(places: pastPlaces, answer: limit.answer)
						}
					}
					let key = reusesGenerators && scopesBuiltAtOnePlace?.contains(scope) != true
						? scopeGeneratorsUnderConstruction[index].memoKey(ofChildBuilding: scope, as: property, id: propertyID, erasedToConcreteExistential: erasedToConcreteExistential)
						: nil
					if key != nil, let keyedPlaceObserver {
						keyedPlaceObserver(scope.instantiable.concreteInstantiable.asSource)
					}
					let draw = key == nil ? nil : sharingSchedule?.draw(atLookup: &lookupCount)
					if let key, let reuse = memo.reuse(of: key, in: scopeGeneratorsUnderConstruction[index].childContext(ofChildBuilding: property), besideCallGenerators: callGeneratorsInTree, drawing: draw) {
						reusedPlaceObserver?(scope.instantiable.concreteInstantiable.asSource, previousPassGenerator == nil)
						callGeneratorsInTree.formUnion(reuse.entry.callGenerators)
						scopeGeneratorsUnderConstruction[index].add(reusing: reuse)
					} else if let key, let reuse = settledPassMemo?.settledReuse(of: key, in: scopeGeneratorsUnderConstruction[index].childContext(ofChildBuilding: property)) {
						// The pass before built this place's generator settled: building the place again would build it again.
						// The memo holds it for the places after it.
						memo.store(reuse.entry, for: key, keepingAlive: scope.identity)
						scopeGeneratorsUnderConstruction[index].add(reusing: reuse)
					} else {
						var child = scopeGeneratorsUnderConstruction[index].childUnderConstruction(
							scope: scope,
							property: property,
							propertyID: propertyID,
							erasedToConcreteExistential: erasedToConcreteExistential,
							isKeyed: key != nil,
						)
						child.memoKey = key
						scopeGeneratorsUnderConstruction.append(child)
						placeIndices.append(typeFactsPlaces?.start(TypeFactsDeclaration(scope: scope, property: property, propertyID: propertyID, erasedToConcreteExistential: erasedToConcreteExistential, isFill: false), parent: placeIndices[index]))
					}
				case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
					scopeGeneratorsUnderConstruction[index].addAliasGenerator(
						property: property,
						fulfillingProperty: fulfillingProperty,
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
						declarationReference: declarationReference,
					)
				case let .hole(property, erasedToConcreteExistential):
					scopeGeneratorsUnderConstruction[index].addHoleGenerator(
						property: property,
						erasedToConcreteExistential: erasedToConcreteExistential,
					)
				}
			} else if let fill = try scopeGeneratorsUnderConstruction[index].nextFill() {
				try scopeGeneratorsUnderConstruction.append(scopeGeneratorsUnderConstruction[index].fillUnderConstruction(
					fill: fill.fill,
					scope: fill.scope,
					context: fill.context,
				))
				placeIndices.append(typeFactsPlaces?.start(TypeFactsDeclaration(scope: fill.scope, property: fill.fill.hole.property, propertyID: fill.context.propertyID, erasedToConcreteExistential: false, isFill: true), parent: placeIndices[index]))
			} else {
				var createdScope = scopeGeneratorsUnderConstruction.removeLast()
				let placeIndex = placeIndices.removeLast()
				if let placeIndex {
					typeFactsPlaces?.finish(placeIndex, closesCycle: createdScope.closesCycle, reads: createdScope.readsAnsweredAbove)
				}
				let scopeGenerator = createdScope.scopeGenerator()
				if let placeIndex {
					typeFactsPlaces?.record(placeIndex, generator: scopeGenerator)
				}
				let callGenerators = createdScope.callGenerators(including: scopeGenerator)
				callGeneratorsInTree.formUnion(callGenerators)
				if scopeGeneratorsUnderConstruction.isEmpty {
					return scopeGenerator
				} else {
					// Filtered once, for the memo and the parent alike.
					let readsAnsweredAbove = createdScope.readsAnsweredAbove
					// A call that passes fills reads the caller's declarations for its fills' trees, which the plan has no edge
					// for yet, so a place whose subtree holds a call or a fill is not compared. Nor is a place inside a fill,
					// which reads the fields of the place its fill fills: the plan has no node for it.
					if let placeReadLabels, let placeReadsObserver, createdScope.recordsReads, !scopeGenerator.treeHoldsCallOrFill, !createdScope.isInsideFill, let built = createdScope.builtProperty {
						placeReadsObserver(
							createdScope.builtScope.instantiable.concreteInstantiable.asSource,
							built.property.asSource,
							// A place reads the declaration of its own property's label, which the scope that builds the place declares,
							// to mark it as being built: the edge decides that answer, so no path's answers hold it.
							readsAnsweredAbove.labelsOfReadsOfDeclarations.subtracting([built.property.label]).sorted(),
							(placeReadLabels.plannedLabelsByPlace[PlaceReadLabels.Place(record: ObjectIdentifier(createdScope.builtScope.identity), property: built.id)] ?? []).sorted(),
						)
					}
					let isSettled = createdScope.isSettled(building: scopeGenerator)
					if let key = createdScope.memoKey, createdScope.isMemoizable {
						memo.store(ConstructionMemo.Entry(
							reads: readsAnsweredAbove,
							generator: scopeGenerator,
							isSettled: isSettled,
							cycleClosingRedeclaredLabels: createdScope.cycleClosingRedeclaredLabels,
							callGenerators: callGenerators,
						), for: key, keepingAlive: createdScope.builtScope.identity)
					}
					scopeGeneratorsUnderConstruction[scopeGeneratorsUnderConstruction.count - 1].add(childGenerator: scopeGenerator, createdBy: &createdScope, readsAnsweredAbove: readsAnsweredAbove, isSettled: isSettled)
				}
			}
		}
	}
}

/// A scope whose generator `ScopeRecord.createScopeGenerator` is creating, with what the generator is created from once
/// the generators of the scopes it creates exist.
private struct ScopeGeneratorUnderConstruction: Sendable {
	/// - Parameters:
	///   - property: The property the scope builds, with its ID in `scope`'s interner, or `nil` for a root.
	///   - contextStack: The declarations being built above the scope.
	///   - depth: This scope's depth in the tree: 0 for the root, and one more than the scope that creates it otherwise.
	///   - fillPathStackCount: How many of the outermost entries of `contextStack` are the path of the seam whose hole the
	///     enclosing fill fills (`SeamSignature.Hole.fillPropertyStack`): none outside a fill, and a nested fill's are its own.
	///   - fillCallDepth: Inside a fill, the depth of the call that passes the innermost enclosing fill, or `nil` outside one.
	init(
		scope: ConstructionScope,
		property builtProperty: (property: Property, id: PropertyID)?,
		contextStack: ContextStack,
		depth: Int,
		fillPathStackCount: Int = 0,
		fillCallDepth: Int? = nil,
		nearestDeclarations inheritedNearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		seamHoles: SeamHoles,
		sitePath: [Property],
		enclosingFills: [String: String] = [:],
		enclosingFillNames: GenerationWork.Shared<Set<String>> = .init([]),
		enclosingCarriedInnerScopes: [String: [ScopeGenerator.FillDispatcher.CarriedInnerScope]] = [:],
		enclosingLevelReentries: [String: PublicMockLevelFunctions.Reentry] = [:],
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		validatesForwardedProperties: Bool,
		fill: Fill? = nil,
		buildsWithHandWrittenMocks: Bool = false,
		declaredTypeNames: DeclaredTypeNames,
		previousPassGenerator: ScopeGenerator?,
		cycleParameterSeed: CycleParameterSeed? = nil,
		cycleParameterContexts: [ScopeGenerator.BuiltDeclaration: CycleParameterContext],
		reboundProperties: Set<Property> = [],
		placeHoldingPropertiesByType: [TypeDescription: Set<Property>]? = nil,
		recordsReads: Bool,
	) {
		self.placeHoldingPropertiesByType = placeHoldingPropertiesByType
		self.depth = depth
		self.recordsReads = recordsReads
		self.builtProperty = builtProperty
		// Every read of the context this scope inherits goes through `context`, logged, so a construction memo can tell
		// whether another place inherits a context that answers the reads of this scope's subtree alike (see
		// `ConstructionMemo`).
		var log = ConstructionLog(recording: recordsReads)
		let property = builtProperty?.property
		let interner = scope.interner
		var childContextStack = contextStack
		// The entry of `contextStack` this scope repeats when it closes a cycle, with its index.
		var closedOn: (entry: ContextStack.Entry, index: Int)?
		// The declarations this scope's own dependencies are read from: those enclosing it, with every form of its own
		// property being built.
		var nearestDeclarations = inheritedNearestDeclarations.changed(atDepth: depth)
		if let (property, propertyID) = builtProperty {
			// A scope closes a cycle where validation finds one: it repeats a declaration of the same property, as cycle
			// validation sees it (a lazily instantiated property as the constant it stands for), built for the same
			// concrete type. A lazily instantiated declaration's instance is on the stack just inside the declaration.
			// A call place closes on nothing, whatever is above it, so it reads nothing of the stack: its body calls the
			// function of the declaration it stands for.
			if !scope.isCallPlace {
				closedOn = contextStack.entryClosedOn(byPropertyID: propertyID, concreteTypeID: scope.concreteTypeID, interner: interner)
				log.record(.declarationClosedOn(propertyID, scope.concreteTypeID), answer: .declarationClosedOn(closedOn?.entry.propertyID), depth: Self.depth(ofAnswerAt: closedOn?.entry.depth, insideFillOfCallAt: fillCallDepth))
			}
			childContextStack.push(property, id: propertyID, concreteType: scope.instantiable.concreteInstantiable, concreteTypeID: scope.concreteTypeID, depth: depth, interner: interner)
			// Building the property adds its forms to the nearest declaration of its label, which it reads.
			let (buildingDeclaration, buildingDepth) = nearestDeclarations.resolving(property.label)
			log.record(.nearestDeclaration(property.label), answer: .nearestDeclaration(buildingDeclaration), depth: buildingDepth)
			nearestDeclarations.build(property)
			// A member of a loop of builders rebinds, at the top of its builder function, what its tree receives inside the
			// loop, its own property among them, so the rebinding is the nearest declaration of each such label in the body.
			for reboundProperty in reboundProperties.sorted() {
				nearestDeclarations.replace(reboundProperty, providing: CycleParameter.forms(providedBy: reboundProperty))
			}
		}
		// The declaration repeated is built for this scope's concrete type, as its entry records.
		let closedOnDeclaration = closedOn.map {
			ScopeGenerator.BuiltDeclaration(property: $0.entry.property, concreteType: scope.instantiable.concreteInstantiable)
		}
		let isPropertyCycle = closedOnDeclaration != nil
		self.fillPathStackCount = fillPathStackCount
		self.fillCallDepth = fillCallDepth
		// Whether the declaration this scope closes on, when it closes on one, is of the fill's path: generation's own finding,
		// which the check of a fill reads instead of working the membership out again.
		closesCycleOnFillPath = closedOn.map { $0.index < fillPathStackCount } ?? false
		// The parameters of this scope's builder function that the pass before found, when a lazy cycle closes on it,
		// or those of the function a cycle-closing scope refers to. Nearly every scope has neither.
		let ownCycleParameters = if !isPropertyCycle, property != nil {
			cycleParameterSeed?.foundCycleParameters ?? previousPassGenerator?.foundCycleParameters ?? []
		} else {
			[CycleParameter]()
		}
		let closedOnContext = closedOnDeclaration.flatMap { closedOnDeclaration in
			let context = cycleParameterContexts[closedOnDeclaration]
			log.record(.cycleParameterContext(closedOnDeclaration), answer: .cycleParameterContext(context?.parameters), depth: Self.depth(ofAnswerAt: context?.depth, insideFillOfCallAt: fillCallDepth))
			return context
		}
		// The function's body reads each parameter's label from the parameter, which hides every other declaration of the
		// label above it, as a forwarded property does.
		let callSiteLazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		var lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		// The parameters this scope passes the builder function a lazy cycle closes on that are unavailable where it
		// passes them, which it passes `nil`: a cycle-closing scope passes each its nearest declaration of the label, and
		// the scope that declares the function the declaration in scope where it calls it. Both are judged against the
		// declarations enclosing this scope, where the function is called. The function takes no parameter of this scope's
		// own label (see `ScopeGenerator.foundCycleParameters`).
		var cycleParameterUnavailableProperties = Set<Property>()
		for parameter in closedOnContext?.parameters ?? ownCycleParameters
			where !parameter.isRequired && Self.cycleArgumentBinding(of: parameter.property, in: nearestDeclarations, log: &log) == nil
		{
			cycleParameterUnavailableProperties.insert(parameter.property)
		}
		if !ownCycleParameters.isEmpty {
			let ownCycleParameterLabels = Set(ownCycleParameters.map(\.property.label))
			// The forms the parameters provide, which the function's body reads in place of every declaration of their labels
			// above the function: this scope's own dependencies are constructed inside the function, so they read them too.
			lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
				.filter { !ownCycleParameterLabels.contains($0.label) }
				.union(ownCycleParameters.compactMap(\.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding))
			for parameter in ownCycleParameters {
				nearestDeclarations.replace(parameter.property, providing: parameter.providedForms)
			}
		}
		// The properties this scope’s children receive by reading the instance of a `LazilyInstantiated` property.
		let childLazilyInstantiatedInstanceProperties: Set<Property> = if lazilyInstantiatedInstanceProperties.isEmpty {
			// Nearly every scope: nothing above it is lazily instantiated, so there is nothing to shadow.
			scope.declaredLazilyInstantiatedInstanceProperties
		} else if property == nil, forMockGeneration {
			// A mock root's tree is given only the instances it reads through the wrappers its public mock takes as
			// parameters, which the root binds beside its own declarations, naming apart any two of one label
			// (`ScopeGenerator.mockRootTopLevelNames`), as `childNearestDeclarations` joins them below: no declaration of
			// the root hides one.
			lazilyInstantiatedInstanceProperties.union(scope.declaredLazilyInstantiatedInstanceProperties)
		} else if scope.declaredLazilyInstantiatedInstanceProperties.isEmpty,
		          !lazilyInstantiatedInstanceProperties.contains(where: { scope.declaredLabels.contains($0.label) })
		{
			// Most scopes below a lazily instantiated property neither shadow it nor declare one of their
			// own, so they share the set they were given.
			lazilyInstantiatedInstanceProperties
		} else {
			lazilyInstantiatedInstanceProperties
				.filter { !scope.declaredLabels.contains($0.label) }
				.union(scope.declaredLazilyInstantiatedInstanceProperties)
		}
		/// The declared property a dependency of this scope's type reads for `property`, which it receives only if
		/// available, or `nil` when `property` is unavailable: a property this scope creates, else the nearest declaration
		/// of its label (see `NearestDeclarations.resolvingBinding(of:)`).
		func binding(of property: Property) -> Property? {
			scope.createdBinding(of: property) ?? Self.binding(of: property, in: nearestDeclarations, log: &log)
		}
		// A receive a mock passes `nil` reads nothing above this scope, though the mock root binds a form of it, since
		// production always passes it `nil` in this place (see `NearestDeclarations.binding(_:passingNilTo:)`).
		let concreteType = scope.instantiable.concreteInstantiable
		// A receive of a property this scope creates itself reads that binding, so it asks nothing of the declarations
		// above, and logs no read of them: a logged read no answer to which changes the place would only keep places from
		// sharing a generator, and is a read the plan by declaration has no label for (base corpus seed 1856, a type that
		// renames its own forwarded property only if available in a mock's tree, fails `PlaceReadsChecks` with the
		// operands in the other order).
		func isPassedNilByMock(_ property: Property, receivedBy dependency: Dependency) -> Bool {
			scope.createdBinding(of: property) == nil && Self.passesNil(to: property, receivedBy: dependency, on: concreteType, in: nearestDeclarations, log: &log)
		}
		var unavailableOptionalProperties = Set<Property>()
		var receivesPassedNil = Set<Property>()
		var aliasBindings = [Property: Property]()
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				break
			case let .received(onlyIfAvailable):
				guard onlyIfAvailable else { break }
				if isPassedNilByMock(dependency.property, receivedBy: dependency) {
					receivesPassedNil.insert(dependency.property)
					unavailableOptionalProperties.insert(dependency.property)
				} else if binding(of: dependency.property) == nil {
					unavailableOptionalProperties.insert(dependency.property)
				}
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				// An `onlyIfAvailable` alias is always declared: bound to its fulfilling property where a form of it is
				// available, and to `nil` otherwise. The type declaring it is passed the alias either way.
				guard onlyIfAvailable else { break }
				if isPassedNilByMock(fulfillingProperty, receivedBy: dependency) {
					receivesPassedNil.insert(fulfillingProperty)
					unavailableOptionalProperties.insert(fulfillingProperty)
				} else if let aliasBinding = binding(of: fulfillingProperty) {
					aliasBindings[dependency.property] = aliasBinding
				} else {
					unavailableOptionalProperties.insert(fulfillingProperty)
				}
			}
		}
		self.unavailableOptionalProperties = unavailableOptionalProperties
		self.receivesPassedNil = receivesPassedNil
		self.aliasBindings = aliasBindings
		self.scope = scope
		self.property = property
		// A scope that closes a cycle creates no children.
		propertiesToGenerate = isPropertyCycle ? [] : scope.propertiesToGenerate
		self.childContextStack = childContextStack
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		self.childLazilyInstantiatedInstanceProperties = childLazilyInstantiatedInstanceProperties
		self.previousPassGenerator = previousPassGenerator
		self.cycleParameterSeed = cycleParameterSeed
		self.ownCycleParameters = ownCycleParameters
		passedCycleParameters = closedOnContext?.parameters ?? ownCycleParameters
		self.cycleParameterUnavailableProperties = cycleParameterUnavailableProperties
		self.callSiteLazilyInstantiatedInstanceProperties = callSiteLazilyInstantiatedInstanceProperties
		self.reboundProperties = reboundProperties
		// The scopes beneath this one see what it declares as the nearest declaration of each label: a declaration of a
		// label hides every one above it, as Swift's scoping does. At a root, nothing is built and nothing encloses its
		// declarations but what the tree is given – a mock root's bindings name every form apart (see
		// `NearestDeclarations.join(_:providing:)`) – so its declarations join those.
		var childNearestDeclarations = nearestDeclarations
		if !isPropertyCycle {
			let declaredPropertyForms = scope.sortedDeclaredPropertyForms
			if property == nil {
				for (declaredProperty, forms) in declaredPropertyForms {
					childNearestDeclarations.join(declaredProperty, providing: forms)
				}
				// A mock root binds a dependency it promotes, or one its type declares, as a child of the root, under the label
				// (`let <label> = …`), unless another declaration of the root, or a parameter of `mock()` that keeps its label,
				// has the label (`rootLabelMap`). Another declaration, such as a forwarded property, provides forms the first
				// does not, which `markBoundUnderLabelByRoot` checks; a default-valued parameter is left out here.
				let labelsMockParametersKeep = Set(ScopeGenerator.defaultValuedMockParameterArguments(of: scope.instantiable).map(\.argument.label))
				for (declaredProperty, forms) in declaredPropertyForms where !labelsMockParametersKeep.contains(declaredProperty.label) {
					childNearestDeclarations.markBoundUnderLabelByRoot(declaredProperty.label, providing: forms)
				}
			} else {
				childNearestDeclarations.replaceLabels(of: declaredPropertyForms)
			}
		}
		// In a mock, a required receive of this scope's type pins the declaration of its label the scopes beneath read, back
		// to a declaration of the label. A mock root's own receives pin nothing in the trees of the dependencies it
		// promotes, which production builds above the mocked type.
		var promotedChildNearestDeclarations: NearestDeclarations?
		if !isPropertyCycle, childNearestDeclarations.judgesPlacesPinnedFromAbove {
			if property == nil {
				promotedChildNearestDeclarations = childNearestDeclarations.sharingDeclarations()
			}
			childNearestDeclarations.recordRequiredReceives(of: scope) { label, declaration, depth in
				log.record(.nearestDeclaration(label), answer: .nearestDeclaration(declaration), depth: depth)
			}
		}
		self.promotedChildNearestDeclarations = promotedChildNearestDeclarations
		// Each scope beneath shares these, rather than copying them.
		self.childNearestDeclarations = childNearestDeclarations.sharingDeclarations()
		// The functions enclosing the scopes this scope builds that lazy cycles close on, by the property each builds:
		// this scope's own, and those enclosing this scope. Nearly every scope is beneath no such function.
		var childCycleParameterContexts = isPropertyCycle ? [:] : cycleParameterContexts
		if let property, !ownCycleParameters.isEmpty {
			childCycleParameterContexts[ScopeGenerator.BuiltDeclaration(property: property, concreteType: scope.instantiable.concreteInstantiable)] = CycleParameterContext(parameters: ownCycleParameters, depth: depth)
		}
		self.childCycleParameterContexts = childCycleParameterContexts
		self.seamRoot = seamRoot
		self.mockBuilders = mockBuilders
		self.seamHoles = seamHoles
		self.declaredTypeNames = declaredTypeNames
		// The path is kept only where a hole needs it: a site, and the payloads bound on the routes to the sites, are found
		// by it.
		self.sitePath = seamHoles.isEmpty ? [] : sitePath + (property.map { [$0] } ?? [])
		self.fill = fill
		self.erasedToConcreteExistential = erasedToConcreteExistential
		self.isPropertyCycle = isPropertyCycle
		self.closedOnDeclaration = closedOnDeclaration
		self.forMockGeneration = forMockGeneration
		self.validatesForwardedProperties = validatesForwardedProperties
		self.buildsWithHandWrittenMocks = buildsWithHandWrittenMocks
		// A scope that closes a cycle calls no seam; any other seam call passes a builder for each of the seam's holes. A
		// call inside a fill of a seam that holds the fill's site, or that passes the site's builder up, passes that fill
		// by name, so every instance of the seam calls the same fills with its own scopes.
		self.enclosingFills = enclosingFills
		self.enclosingFillNames = enclosingFillNames
		self.enclosingCarriedInnerScopes = enclosingCarriedInnerScopes
		self.enclosingLevelReentries = enclosingLevelReentries
		holeArguments = isPropertyCycle ? [] : scope.holeArguments
		// The call's own fills are those no enclosing call fills, and its own dispatchers those no enclosing call declares. One
		// pass names both, fills first, then dispatchers, apart from what encloses the call: the
		// fills and dispatchers enclosing it, and the names the seam whose tree holds it binds for its builders, which a call
		// inside it passes by name and which a closer declaration would shadow.
		var fillsOfThisCall = [(fill: Fill, scope: ConstructionScope, context: ScopeRecord.FillContext)]()
		var dispatchersOfThisCall = [ScopeGenerator.FillDispatcher]()
		var namesOfThisCall = GeneratedNameAllocator(reserving: [])
		if !holeArguments.isEmpty {
			let callPath = self.sitePath
			// The names are asked of each set in turn, never of their union: a union made for every call holds every name the
			// seam whose tree holds the calls binds, so a seam's tree that calls another seam at every place grew with its
			// square.
			var names = GeneratedNameAllocator(reserving: GenerationWork.taking(
				NamesConsultedInTurn([GenerationWork.taking(enclosingFillNames, by: .reservingNamesOfACall), seamHoles.namesBoundForBuilders]),
				by: .reservingNamesOfACall,
			))
			defer { namesOfThisCall = names }
			var fillNames = enclosingFills
			// Every other place of a case nested by type is filled by one function, the first place's: it can read whatever
			// field any place of the case carries, each from the case or from the dispatchers that lead to it, in the form every
			// route can hand it (`ScopeGenerator.caseFields(of:)`).
			var placesByCaseKey = [String: [SeamSignature.Hole]]()
			for case let .fill(hole, _, _) in holeArguments where hole.enumPlace != nil {
				placesByCaseKey[ScopeGenerator.fillCaseKey(of: hole), default: []].append(hole)
			}
			// A place inside a fill of an inner seam's builder reads, through the scope value the inner seam handed that fill, a
			// label that some route of the inner seam's enum holds and another does not: on that other route inline reads the
			// caller's declaration, as for a label one place of the case carries and another does not.
			let innerScopeReaders = scope.calledBuilders.map { InnerScopeReaders(enumsByKey: $0.enumsByKey) }
			var caseFieldsByCaseKey = placesByCaseKey.mapValues { places in
				var caseFields = ScopeGenerator.caseFields(of: places)
				if let innerScopeReaders {
					let fieldLabels = Set(caseFields.fields.map(\.property.label))
					for place in places {
						caseFields.callerReadLabels.formUnion(innerScopeReaders.labelsSomeInnerRouteLacks(of: place).intersection(fieldLabels))
					}
				}
				return caseFields
			}
			// A public mock's caller decides per route, and a route whose nearest type binds another form of a value its fill
			// reads converts it, so the fill takes each value its case's payload does not carry in the form it reads
			// (`parameterField(of:reading:)`). A route on which no type binds the value hands the fill the caller's, which the root
			// level function takes (`PublicMockLevelFunctions`).
			// But a value the call hands the called mock from the caller's scope, which the called mock's root binds as its copy,
			// is the caller's own, as a seam's deferred parameter is (see `fillUnderConstruction`): a fill whose places' nearest
			// declaration of its label is that copy, and whose case's payload does not carry it, reads the caller's declaration,
			// so its tree reads the caller's wrapper, as inline and the twin do, and no level function takes the value
			// (`callersOwnLabels(amongLabelsOf:carrying:at:reading:handedFrom:by:whereFillsReenterCall:)`). A label the payload
			// carries the fill binds from the payload, the called mock's copy, which holds the caller's value, unless the copy does
			// not provide every form the fill reads and no fill re-enters the call.
			var mockRootBindingByLabelByCaseKey = [String: [String: Property]]()
			var fillsReenterCall = false
			if scope.publicMockCall != nil, let calledBuilders = scope.calledBuilders {
				fillsReenterCall = Self.callsInsideFills(of: holeArguments, reenter: calledBuilders)
			}
			if let publicMockCall = scope.publicMockCall {
				for (caseKey, places) in placesByCaseKey {
					guard var caseFields = caseFieldsByCaseKey[caseKey] else { continue }
					let carriedLabels = Set(places.flatMap { $0.enumPlace?.values.map(\.property.label) ?? [] })
					let reads = places.reduce(into: Set<Property>()) { reads, place in
						reads.formUnion(scope.fillReceivedProperties[place.site] ?? [])
					}
					caseFields.fields = caseFields.fields.map { field in
						let label = field.property.label
						guard !carriedLabels.contains(label) else { return field }
						let fieldsOfLabel = places.flatMap { $0.fields.filter { $0.property.label == label } }
						return Self.parameterField(of: fieldsOfLabel, reading: reads.filter { $0.label == label }) ?? field
					}
					let callersOwnLabels = Self.callersOwnLabels(amongLabelsOf: caseFields.fields, carrying: carriedLabels, at: places, reading: reads, handedFrom: childNearestDeclarations, by: publicMockCall, whereFillsReenterCall: fillsReenterCall, log: &log)
					caseFields.fields.removeAll { callersOwnLabels.labels.contains($0.property.label) }
					caseFields.callerReadLabels.subtract(callersOwnLabels.labels)
					mockRootBindingByLabelByCaseKey[caseKey] = callersOwnLabels.mockRootBindingByLabel
					caseFieldsByCaseKey[caseKey] = caseFields
				}
			}
			// A call inside a fill of this call that re-enters one of its level functions hands that function what it reads of
			// its own scope (`PublicMockLevelFunctions.Reentry`), so a value a fill reads of the caller's scope that no place of
			// its case carries is the fill's to take too, rather than the declaration enclosing this call that the fill's
			// function would capture: inline reads the declaration nearest the place, which for a place the re-entering call
			// reaches is the one nearest that call. Each such label is typed as `ScopeGenerator.FillDispatcher` types a
			// dispatcher's parameter, by a form that is no optional, then in `Property` order. Without such a call the fill
			// reads the same declaration either way, and keeps capturing it. A caller's own value (above) is such a label too:
			// the re-entering call hands its own nearest declaration, which is the one inline reads at the places it reaches.
			// The levels hand the fill the called mock's by-value copy of it, which holds the same value: a fill that reads the
			// caller's wrapper beside its place's fields, which the copy does not provide, is passed up where its called type is
			// re-entered, directly or through the fills of the calls its fills make, before any fill is built
			// (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`), and an optional copy where a
			// fill requires the value is an error.
			if fillsReenterCall {
				for (caseKey, places) in placesByCaseKey {
					guard var caseFields = caseFieldsByCaseKey[caseKey], let firstPlace = places.first else { continue }
					let fieldLabels = Set(caseFields.fields.map(\.property.label))
					var formsByLabel = [String: Set<Property>]()
					for place in places {
						for property in scope.fillReceivedProperties[place.site] ?? [] where !fieldLabels.contains(property.label) {
							formsByLabel[property.label, default: []].insert(property)
						}
					}
					for label in formsByLabel.keys.sorted() {
						let forms = formsByLabel[label, default: []].sorted()
						guard let property = forms.first(where: { !$0.typeDescription.isOptional }) ?? forms.first else { continue }
						caseFields.fields.append(SeamSignature.Hole.Field(property: property, access: .public, declaringType: firstPlace.scopeSeamType, declarationLocation: nil))
						caseFields.callerReadLabels.insert(label)
					}
					caseFieldsByCaseKey[caseKey] = caseFields
				}
			}
			var functionNameByCaseKey = [String: String]()
			for case let .fill(hole, fulfillingScope, fillContext) in holeArguments where enclosingFills[ScopeGenerator.fillKey(of: hole)] == nil {
				let key = ScopeGenerator.fillKey(of: hole)
				let caseKey = ScopeGenerator.fillCaseKey(of: hole)
				if let functionName = functionNameByCaseKey[caseKey] {
					fillNames[key] = functionName
					fillsOfThisCall.append((Fill(hole: hole, key: key, functionName: functionName, fields: hole.fields, emitsCode: false, caseHoles: [hole]), fulfillingScope, fillContext))
					continue
				}
				let functionName = names.claim(ScopeGenerator.fillFunctionName(of: hole))
				fillNames[key] = functionName
				if hole.enumPlace != nil {
					functionNameByCaseKey[caseKey] = functionName
				}
				let caseFields = caseFieldsByCaseKey[caseKey]
				var fill = Fill(
					hole: hole,
					key: key,
					functionName: functionName,
					fields: caseFields?.fields ?? hole.fields,
					emitsCode: true,
					caseHoles: placesByCaseKey[caseKey] ?? [hole],
					callerReadLabels: caseFields?.callerReadLabels ?? [],
				)
				fill.innerScopeParameters = Self.innerScopeParameters(ofFillOf: hole, seamHoles: seamHoles, callPath: callPath, calledBuilders: scope.calledBuilders)
				fill.carrierUse = scope.calledBuilders?.carrierUse(ofPlace: hole)
				fill.mockRootBindingByLabel = mockRootBindingByLabelByCaseKey[caseKey] ?? [:]
				// A label a route binds as a `LazilyInstantiated` and the caller hands from its own scope stays the wrapper, so the
				// instance is created where the fill's tree reads it, as inline; where every read of it is only if available, the
				// fill takes it optionally (`Scope.fillLabelsReadOnlyIfAvailable`, set for the places whose fields hold a wrapper,
				// each filled by the same type).
				for field in fill.fields where fill.callerReadLabels.contains(field.property.label) && field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding != nil {
					let places = placesByCaseKey[caseKey] ?? [hole]
					if places.contains(where: { scope.fillLabelsReadOnlyIfAvailable[$0.site]?.contains(field.property.label) == true }) {
						fill.optionalLazilyInstantiatedLabels.insert(field.property.label)
					}
				}
				fillsOfThisCall.append((fill, fulfillingScope, fillContext))
			}
			if let calledBuilders = scope.calledBuilders {
				dispatchersOfThisCall = ScopeGenerator.FillDispatcher.dispatchers(
					of: calledBuilders,
					filledSites: Self.filledSites(of: holeArguments),
					enclosingDispatchers: enclosingFills,
					fillNames: fillNames,
					names: &names,
					innerScopeNameByKey: Dictionary(calledBuilders.scopeEnums.compactMap { scopeEnum in
						seamHoles.innerScope(at: callPath, innerKey: scopeEnum.key).map { (scopeEnum.key, $0.name) }
					}, uniquingKeysWith: { first, _ in first }),
					// Where the call's case returns the called seam's struct, the call's level functions are handed it, one per hole
					// type and family of this seam whose places the fill holds.
					carriedInnerScopesByKey: Dictionary(calledBuilders.scopeEnums.compactMap { scopeEnum in
						guard seamHoles.carriesStruct(at: callPath, innerKey: scopeEnum.key) else { return nil }
						return (scopeEnum.key, seamHoles.innerScopes(at: callPath, innerKey: scopeEnum.key).map { (name: $0.name, type: $0.enumType) })
					}, uniquingKeysWith: { first, _ in first }),
					enclosingCarriedInnerScopes: enclosingCarriedInnerScopes,
					decidesPerRoute: scope.publicMockCall != nil,
				)
			}
			// A level on a carried route binds a deferred parameter from a call the caller's seam makes, whose memo holds what that
			// call passed, which no declaration of the caller's is (`FillDispatcher.Case.carriesDeferredFields`). A fill some route
			// hands such a memo takes a memo, so the value is created when its tree reads it on every route, as inline: its field
			// is that parameter's, which it binds as the memo (`fillUnderConstruction`), and a route that hands another form makes
			// the memo of what it hands (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`). A public mock's caller hands values.
			// A fill whose tree reads a label only as the place's own field of it, the wrapper a type further out declares, takes
			// that field, which the pass before found (`ScopeGenerator.fillLabelsReadOnlyAsPlaceField`): inline reads that
			// declaration, which the levels hand on past the deferring seam's (`FillDispatcher.Case.handsOn(_:)`).
			if scope.publicMockCall == nil, dispatchersOfThisCall.contains(where: { dispatcher in
				dispatcher.cases.contains { $0.carriesDeferredFields && $0.values?.contains(where: \.isDeferredParameter) == true }
			}) {
				for index in fillsOfThisCall.indices where fillsOfThisCall[index].fill.emitsCode {
					let fill = fillsOfThisCall[index].fill
					let payloadLabels = Set(fill.hole.enumPlace?.values.map(\.property.label) ?? [])
					let labelsReadOnlyAsPlaceField = previousPassGenerator?.fillLabelsReadOnlyAsPlaceField[fill.key] ?? []
					let handedMemos = ScopeGenerator.FillDispatcher.memosHanded(
						toFillOf: fill.key,
						labels: Set(fill.fields.filter { !$0.isDeferredParameter && !payloadLabels.contains($0.property.label) && !labelsReadOnlyAsPlaceField.contains($0.property.label) }.map(\.property.label)),
						readingSendableWrapper: previousPassGenerator?.fillSendableWrapperReads[fill.key] ?? [:],
						among: dispatchersOfThisCall,
					)
					fillsOfThisCall[index].fill.fields = fill.fields.map { field in
						handedMemos.memoByLabel[field.property.label].map { field.handedAsMemo($0) } ?? field
					}
					fillsOfThisCall[index].fill.labelsHandedAsMemo = Set(handedMemos.memoByLabel.keys)
					fillsOfThisCall[index].fill.plainMemoRoutesOfSendableWrapperReads = handedMemos.plainMemoRoutesOfSendableWrapperReads
					fillsOfThisCall[index].fill.memoOriginsByLabel = handedMemos.memoOriginsByLabel
				}
			}
			// A fill a level function calls of an instantiator's place returns the builder its wrapper keeps: every fill of a
			// public mock's call, whose dispatchers are all level functions (`PublicMockLevelFunctions`).
			for index in fillsOfThisCall.indices where fillsOfThisCall[index].fill.hole.property.propertyType.isAnyInstantiator {
				let key = fillsOfThisCall[index].fill.key
				fillsOfThisCall[index].fill.returnsWrapperBuilder = dispatchersOfThisCall.contains { dispatcher in
					(dispatcher.returnsBuilderStruct || dispatcher.decidesPerRoute) && dispatcher.cases.contains { $0.target?.key == key }
				}
			}
		}
		self.fillsOfThisCall = fillsOfThisCall
		self.dispatchersOfThisCall = dispatchersOfThisCall
		self.namesOfThisCall = namesOfThisCall
		// Gathered once for the call, not once for each of its fills, each of which is handed all of them: gathered for each
		// fill, a call's fills grew with the square of the places of the seam it calls.
		var enclosingFillsOfThisCall = enclosingFills
		if !holeArguments.isEmpty {
			for (fill, _, _) in fillsOfThisCall {
				enclosingFillsOfThisCall[fill.key] = fill.functionName
			}
			for dispatcher in dispatchersOfThisCall {
				enclosingFillsOfThisCall[dispatcher.key] = dispatcher.functionName
			}
			GenerationWork.record(enclosingFillsOfThisCall.count, by: .gatheringFillsOfACall)
		}
		self.enclosingFillsOfThisCall = GenerationWork.Shared(enclosingFillsOfThisCall)
		var enclosingCarriedInnerScopesOfThisCall = enclosingCarriedInnerScopes
		for dispatcher in dispatchersOfThisCall where !dispatcher.carriedInnerScopes.isEmpty {
			enclosingCarriedInnerScopesOfThisCall[dispatcher.key] = dispatcher.carriedInnerScopes
		}
		self.enclosingCarriedInnerScopesOfThisCall = enclosingCarriedInnerScopesOfThisCall
		// A level function of this call that takes nothing hides an enclosing call's of the same dispatcher; what each
		// takes the pass before decided from the call's level functions (`ScopeGenerator.publicMockLevelReentries`).
		var enclosingLevelReentriesOfThisCall = enclosingLevelReentries
		if scope.publicMockCall != nil {
			let levelReentries = previousPassGenerator?.publicMockLevelReentries ?? [:]
			for dispatcher in dispatchersOfThisCall {
				enclosingLevelReentriesOfThisCall[dispatcher.key] = levelReentries[dispatcher.key]
			}
		}
		self.enclosingLevelReentriesOfThisCall = enclosingLevelReentriesOfThisCall
		// The names of those fills, which a call inside one of them avoids, gathered once for the call's fills to share.
		if fillsOfThisCall.isEmpty {
			enclosingFillNamesOfThisCall = enclosingFillNames
		} else {
			enclosingFillNamesOfThisCall = GenerationWork.Shared(Set(enclosingFillsOfThisCall.values))
			GenerationWork.record(enclosingFillsOfThisCall.count, by: .gatheringFillsOfACall)
		}
		childGenerators.reserveCapacity(propertiesToGenerate.count + fillsOfThisCall.count)
		self.log = log
		// Every scope of a tree with holes reads context the log does not cover, and so does a call that passes fills outside a
		// mock's tree, until production trees are measured with it.
		subtreeIsShareable = seamHoles.isEmpty && seamRoot == nil && mockBuilders == nil && (holeArguments.isEmpty || forMockGeneration)
		// A fill and a scope inside one are built only as part of the call that passes the fill, whose place is stored whole.
		isMemoizable = subtreeIsShareable && fill == nil && enclosingFills.isEmpty
		if !holeArguments.isEmpty {
			isCall = true
		}
	}

	/// The nearest declaration of `label` among `nearestDeclarations`, logged in `log`.
	@discardableResult
	private static func logNearestDeclaration(of label: String, in nearestDeclarations: NearestDeclarations, log: inout ConstructionLog) -> NearestDeclaration? {
		let (declaration, depth) = nearestDeclarations.resolving(label)
		log.record(.nearestDeclaration(label), answer: .nearestDeclaration(declaration), depth: depth)
		return declaration
	}

	/// The binding a receive of `property` only if available reads, among `nearestDeclarations`, logged in `log`.
	private static func binding(of property: Property, in nearestDeclarations: NearestDeclarations, log: inout ConstructionLog) -> Property? {
		let (binding, depth) = nearestDeclarations.resolvingBinding(of: property)
		log.record(.binding(property), answer: .binding(binding), depth: depth)
		return binding
	}

	/// The binding this scope passes a parameter `property` of the builder function a lazy cycle closes on, among
	/// `nearestDeclarations`, logged in `log` as a read of what a cycle passes (`ConstructionLog.Read.cycleArgumentBinding`).
	private static func cycleArgumentBinding(of property: Property, in nearestDeclarations: NearestDeclarations, log: inout ConstructionLog) -> Property? {
		let (binding, depth) = nearestDeclarations.resolvingBinding(of: property)
		log.record(.cycleArgumentBinding(property), answer: .binding(binding), depth: depth)
		return binding
	}

	/// Whether a mock passes `nil` to a receive of `property` only if available, by `dependency` on `receivingType`, among
	/// `nearestDeclarations` (see `NearestDeclarations.resolvingPassesNil(to:receivedBy:on:)`), logged in `log`, `false` included: two
	/// mock roots can reach one place and differ only in this. Where no declaration enclosing the tree holds such a receive,
	/// the answer is `false` at every place of the tree, which a construction memo's key holds, so nothing is logged.
	private static func passesNil(to property: Property, receivedBy dependency: Dependency, on receivingType: TypeDescription, in nearestDeclarations: NearestDeclarations, log: inout ConstructionLog) -> Bool {
		guard nearestDeclarations.mayPassNil else { return false }
		let (passesNil, depth) = nearestDeclarations.resolvingPassesNil(to: property, receivedBy: dependency, on: receivingType)
		log.record(.passesNil(property, dependency, receivingType), answer: .passesNil(passesNil), depth: depth)
		return passesNil
	}

	/// This scope's depth in the tree (see `init`).
	let depth: Int
	/// What this scope and the scopes beneath it whose generators exist read of the context above them (see
	/// `ConstructionMemo`), recorded only where `recordsReads`.
	private(set) var log: ConstructionLog
	/// Whether this scope records what its subtree reads: where it has a construction memo key, or is beneath a scope that
	/// has one, whose stored entry holds those reads. Elsewhere the reads are never stored, and no scope above keeps them.
	let recordsReads: Bool
	/// Whether this scope's generator may be stored in a construction memo, or reuse one stored there: it is no fill and in
	/// none, and its subtree is shareable (`subtreeIsShareable`).
	private(set) var isMemoizable: Bool
	/// Whether nothing in this scope's subtree reads context the log does not cover: no scope is in a tree with holes or is a
	/// hole's generator, and every call that passes fills is in a mock's tree. A fill's subtree that is shareable leaves the
	/// call that passes the fill memoizable, since everything a fill is built from is the call's scope, which the call's key
	/// names, and reads the fill's subtree logs.
	private(set) var subtreeIsShareable: Bool
	/// Whether this scope is a call of another module's public mock or a seam that passes fills (non-empty `holeArguments`).
	private var isCall = false
	/// The generators of the calls in this scope's subtree that pass fills, as `ConstructionMemo.Entry.callGenerators` holds
	/// them, the scope's own excepted until it is created (see `callGenerators(including:)`).
	private var callGeneratorsBeneath = Set<ObjectIdentifier>()

	/// `callGeneratorsBeneath`, with `generator`, this scope's, where it is a call that passes fills.
	func callGenerators(including generator: ScopeGenerator) -> Set<ObjectIdentifier> {
		isCall ? callGeneratorsBeneath.union([ObjectIdentifier(generator)]) : callGeneratorsBeneath
	}

	/// Whether a call inside the trees of `holeArguments`' fills reaches one of `calledBuilders`' enums again, so that it
	/// re-enters a level function the call that passes those fills declares for it: a call of the same builder, which
	/// re-enters its root level function, or of another module's public mock that holds a builder of a type whose places
	/// the call fills (`.inner`), which re-enters the level function of that type's enum.
	private static func callsInsideFills(of holeArguments: [ConstructionScope.HoleArgument], reenter calledBuilders: CalledBuilders) -> Bool {
		let enumKeys = Set(calledBuilders.enumsByKey.keys)
		var visited = Set<ObjectIdentifier>()
		var scopesToVisit = holeArguments.compactMap { argument -> ConstructionScope? in
			guard case let .fill(_, scope, _) = argument else { return nil }
			return scope
		}
		while let scope = scopesToVisit.popLast() {
			guard visited.insert(ObjectIdentifier(scope.identity)).inserted else { continue }
			if let innerBuilders = scope.calledBuilders, innerBuilders.enumsByKey.keys.contains(where: enumKeys.contains) {
				return true
			}
			for case let .fill(_, fillScope, _) in scope.holeArguments {
				scopesToVisit.append(fillScope)
			}
			for case let .instantiated(_, childScope, _, _) in scope.propertiesToGenerate {
				scopesToVisit.append(childScope)
			}
		}
		return false
	}

	/// A fill of a seam call: the hole it fills, its key (see `ScopeGenerator.fillKey(of:)`), and its function's name.
	struct Fill: Sendable {
		/// The place the fill fills, without the declarations bound from the call's arguments that the caller binds itself
		/// (`fillUnderConstruction`).
		var hole: SeamSignature.Hole
		let key: String
		let functionName: String
		/// The fields the fill can bind: its hole's, or every place's of a case nested by type, for the fill that generates
		/// the case's code; a deferred parameter's the fill reads from the struct, as its memo (`fillUnderConstruction`).
		var fields: [SeamSignature.Hole.Field]
		/// Whether the fill's code is generated (see `ScopeGenerator.fillEmitsCode`).
		let emitsCode: Bool
		/// The places the fill stands for: its hole, or, for the fill that generates the code of a case nested by type, every
		/// place of the case, in builder order.
		let caseHoles: [SeamSignature.Hole]
		/// For the fill that generates the code of a case nested by type, the labels of `fields` that a level holds on some
		/// route to the case and none holds on another, where the root dispatcher hands the fill the caller's declaration
		/// (see `ScopeGenerator.caseFields(of:)`).
		var callerReadLabels = Set<String>()
		/// The labels among `callerReadLabels` of a `LazilyInstantiated` field whose tree reads every form only if available:
		/// the fill takes the wrapper optionally, which the root dispatcher passes `nil` where the caller declares none, and its
		/// tree reads the instance through the optional (see `fillUnderConstruction`).
		var optionalLazilyInstantiatedLabels = Set<String>()
		/// For the fill that generates the code of a case of a call of another module's public mock, the property the caller's
		/// mock root binds for each caller's own value whose nearest declaration is that binding, by label: the fill binds it
		/// under the label from the name the mock spells (`Scope.CallersOwnLabels.mockRootBindingByLabel`).
		var mockRootBindingByLabel = [String: Property]()
		/// The labels of the fields of the hole's struct the fill binds from the struct (see `fillUnderConstruction`):
		/// every field but one bound from a deferred parameter, which the fill reads from the caller's scope.
		var boundLabels = Set<String>()
		/// The declarations enclosing the call, which the root dispatcher reads the values of `callerReadLabels` from.
		var callerNearestDeclarations = NearestDeclarations()
		/// The received properties in scope at the call only as the instance of a `LazilyInstantiated` property.
		var callerLazilyInstantiatedInstanceProperties = Set<Property>()
		/// For a fill of a builder whose fills lead to a place of the seam whose tree makes the call, the scope value the inner
		/// seam handed it, as the parameter the fill takes it under where its tree builds such a place or a call that passes one
		/// up (`SeamHoles.innerScopes(at:innerKey:)`): for a seam's builder struct, the struct of the fill's own level, one per
		/// hole type and family of the calling seam whose places it holds.
		var innerScopeParameters = [SeamSignature.Hole.Field]()
		/// How the fill takes its case's values where the case is a seam's carrier's (`SeamCarrierValues.Use`).
		var carrierUse: SeamCarrierValues.Use?
		/// Whether the fill is a member of a level function, a dispatcher that returns its enum's builder struct, and fills an
		/// instantiator's place: it then returns the builder the wrapper keeps, which takes the forwarded value itself, rather
		/// than the value it builds (`ScopeGenerator.fillReturnsWrapperBuilder`).
		var returnsWrapperBuilder = false
		/// The labels of `fields` some route hands the fill as the memo of a deferred parameter that a level on a carried route
		/// holds (`ScopeGenerator.FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`): each such field is a deferred
		/// parameter's, which the fill binds from what it is handed, as its memo (see `fillUnderConstruction`).
		var labelsHandedAsMemo = Set<String>()
		/// By each label the fill takes a `LazilyInstantiated` memo of while its tree reads the label as a
		/// `SendableLazilyInstantiated` too, the routes that hand a seam's `LazilyInstantiated`
		/// (`ScopeGenerator.FillDispatcher.HandedMemos`), which validation reports.
		var plainMemoRoutesOfSendableWrapperReads = [String: [ScopeGenerator.FillDispatcher.PlainMemoRoute]]()
		/// By each of `labelsHandedAsMemo`, the deferred parameters whose memos the routes hand
		/// (`ScopeGenerator.FillDispatcher.HandedMemos.memoOriginsByLabel`), which validation judges the fill's reads against.
		var memoOriginsByLabel = [String: [SeamSignature.Hole.Field.SeamParameterOrigin]]()
	}

	/// The parameters a fill of `hole` takes the scope values the seam whose tree holds `hole` handed it under, for the call at
	/// `callPath`, where a place inside a fill of a place of that seam's enum reads one.
	/// A builder struct keys the value by the called seam's root enum whose builder reaches `hole`
	/// (`SeamScopeEnumsByType.filledRootKey(of:in:)`).
	private static func innerScopeParameters(ofFillOf hole: SeamSignature.Hole, seamHoles: SeamHoles, callPath: [Property], calledBuilders: CalledBuilders?) -> [SeamSignature.Hole.Field] {
		let calledRootKey = calledBuilders?.keyOfFirstBuilderReaching(hole)
		let innerKey = calledRootKey.flatMap { seamHoles.carriesStruct(at: callPath, innerKey: $0) ? $0 : nil } ?? SeamSignature.ScopeEnum.rootKey(of: hole)
		return seamHoles.innerScopes(at: callPath, innerKey: innerKey).map { innerScope in
			SeamSignature.Hole.Field(
				property: Property(label: innerScope.name, typeDescription: innerScope.enumType),
				access: .public,
				declaringType: hole.scopeSeamType,
				declarationLocation: nil,
			)
		}
	}

	/// The generators created so far for `propertiesToGenerate`, in order, followed by those of `fillsOfThisCall`.
	private(set) var childGenerators = [ScopeGenerator]()
	/// The `CycleClosingRedeclaredLabels` of `childGenerators`, merged in their order, which this scope's
	/// generator is created from; then, once `scopeGenerator(collectingGeneratorsToStartInto:)` has created it, its own,
	/// which `add(childGenerator:createdBy:readsAnsweredAbove:isSettled:)` merges into its parent's, and a memo entry of
	/// the generator keeps for a place that reuses it (`ConstructionMemo.Entry`). No generator keeps one. An alias or a hole
	/// has none.
	private(set) var cycleClosingRedeclaredLabels = CycleClosingRedeclaredLabels()
	/// Adds `childGenerator`, the generator `child` created, to this scope's children.
	/// - Parameters:
	///   - readsAnsweredAbove: `child.readsAnsweredAbove`.
	///   - isSettled: `child.isSettled(building: childGenerator)`.
	mutating func add(childGenerator: ScopeGenerator, createdBy child: inout ScopeGeneratorUnderConstruction, readsAnsweredAbove: ConstructionLog, isSettled: Bool) {
		childGenerators.append(childGenerator)
		if cycleClosingRedeclaredLabels.isEmpty {
			// Nearly every scope has at most one child that takes part in a cycle, whose map it takes whole.
			swap(&cycleClosingRedeclaredLabels, &child.cycleClosingRedeclaredLabels)
		} else {
			merge(childCycleClosingRedeclaredLabels: child.cycleClosingRedeclaredLabels)
		}
		log.formUnion(readsAnsweredAbove)
		if !isSettled {
			childrenAreSettled = false
		}
		// A fill's subtree, and the fill itself, are never stored alone, but leave this scope, the call that passes the
		// fill, memoizable when nothing in them reads context the log does not cover.
		let childKeepsThisScopeMemoizable = child.fill != nil ? child.subtreeIsShareable : child.isMemoizable
		if !childKeepsThisScopeMemoizable {
			isMemoizable = false
		}
		if !child.subtreeIsShareable {
			subtreeIsShareable = false
		}
		callGeneratorsBeneath.formUnion(child.callGenerators(including: childGenerator))
	}

	/// Merges a child's `CycleClosingRedeclaredLabels` into `cycleClosingRedeclaredLabels`.
	private mutating func merge(childCycleClosingRedeclaredLabels: CycleClosingRedeclaredLabels) {
		cycleClosingRedeclaredLabels.merge(childCycleClosingRedeclaredLabels)
	}

	/// Adds the generator another place built, which `reuse` found, to this scope's children, as the child it builds
	/// (see `ConstructionMemo`).
	mutating func add(reusing reuse: ConstructionMemo.Reuse) {
		childGenerators.append(reuse.entry.generator)
		merge(childCycleClosingRedeclaredLabels: reuse.entry.cycleClosingRedeclaredLabels)
		log.formUnion(reuse.reads)
		if !reuse.entry.isSettled {
			childrenAreSettled = false
		}
		callGeneratorsBeneath.formUnion(reuse.entry.callGenerators)
	}

	/// Whether every child this scope created or reused found everywhere in its subtree what it read from the pass before
	/// (see `ConstructionMemo.Entry.isSettled`).
	private var childrenAreSettled = true

	/// Whether `generator`, this scope's, found everywhere in its subtree what its build read from the pass before: its
	/// children did, and it found the cycle parameters and loops of builders the pass before's generator for the place
	/// found, spelled alike.
	///
	/// A call that passes fills is never settled, so neither is any scope above it: what a call's build reads from the pass
	/// before, its fills' findings among it (`ScopeGenerator.fillDeferredLabelsHiddenByReenteringCalls`,
	/// `fillLabelsReadOnlyAsPlaceField` and the others `init` reads of `previousPassGenerator`), is not compared here, and
	/// settled reuse saves nothing the profile shows above a call.
	func isSettled(building generator: ScopeGenerator) -> Bool {
		!isCall && childrenAreSettled && ConstructionMemo.foundAlike(by: generator, asBy: previousPassGenerator, builtWithCycleParameters: ownCycleParameters)
	}

	/// Whether the scope closes a cycle on a declaration above it, and so builds no children.
	var closesCycle: Bool {
		isPropertyCycle
	}

	/// What this scope's subtree read of the context above this scope (see `ConstructionMemo`).
	var readsAnsweredAbove: ConstructionLog {
		log.reads(answeredAbove: depth)
	}

	/// The key this scope's generator is stored under once it exists, or `nil` for a root, a fill, or a scope the memo does
	/// not cover (see `memoKey(ofChildBuilding:as:id:erasedToConcreteExistential:)`).
	var memoKey: ConstructionMemo.Key?

	/// The next of `propertiesToGenerate` to create a generator for, or `nil` once every one has its generator.
	mutating func nextPropertyToGenerate() -> ConstructionScope.PropertyToGenerate? {
		guard nextPropertyIndex < propertiesToGenerate.count else { return nil }
		let propertyToGenerate = propertiesToGenerate[nextPropertyIndex]
		nextPropertyIndex += 1
		return propertyToGenerate
	}

	/// The next of `fillsOfThisCall` to create a generator for, once every one of `propertiesToGenerate` has its
	/// generator, or `nil` once every fill has its generator.
	///
	/// A place of a case nested by type whose fill generates no code, and whose fill would be built from values equal, in
	/// everything the tree reads, to those an earlier such place of its case was built from, gets no generator: that
	/// place's stands for it (`ScopeGenerator.FillStoodFor`), and it is recorded in `fillsStoodFor`.
	mutating func nextFill() throws -> (fill: Fill, scope: ConstructionScope, context: ScopeRecord.FillContext)? {
		while nextFillIndex < fillsOfThisCall.count {
			let next = fillsOfThisCall[nextFillIndex]
			nextFillIndex += 1
			GenerationWork.record(1, by: .findingFillThatStandsForPlace)
			// A fill drops a declaration the caller binds itself from its hole, which no other place's fill did for this
			// one, and which its own fill would do for no other place.
			guard sharesFillsBetweenPlaces, !next.fill.emitsCode, next.fill.hole.enumPlace != nil, !next.fill.hole.uncarriedDeclarations.contains(where: \.isBoundFromCallersArgument) else {
				builtFillCount += 1
				return next
			}
			// The case's stand-ins are taken out of the dictionary while they are asked and changed, and put back, so that
			// no place copies them.
			let caseKey = ScopeGenerator.fillCaseKey(of: next.fill.hole)
			var standIns = fillStandInsByCaseKey.removeValue(forKey: caseKey) ?? FillStandIns()
			let standInKey = standInKey(forFillOf: next.fill.hole, builtBy: next.scope, among: &standIns)
			if standInKey == nil, !standIns.noFillStandsIn {
				standIns.fillWhoseTreeIsNotReadYet = FillStandIn(childIndex: childGenerators.count, key: next.fill.key, hole: next.fill.hole, scope: ObjectIdentifier(next.scope.identity))
			}
			fillStandInsByCaseKey[caseKey] = standIns
			if let standInKey {
				// What building the fill would check of the place itself.
				try validateForwardedProperties(of: next.fill.hole.property, declaredAt: next.fill.hole.declarationLocation, on: next.fill.hole.ownerType, seeingThroughModulesNamed: next.fill.hole.declaringModuleNames, building: next.scope.instantiable)
				fillsStoodFor.append(ScopeGenerator.FillStoodFor(hole: next.fill.hole, key: next.fill.key, standInKey: standInKey, builtFillCountBefore: builtFillCount))
			} else {
				builtFillCount += 1
				return next
			}
		}
		return nil
	}

	/// Whether this scope's seam call builds one fill for the places of a case whose fills would be built alike. Only a
	/// production tree's call of a seam, outside every fill: a public mock's caller decides per route, a mock's tree shares a
	/// call whole through the construction memo, and a call inside a fill passes the fills enclosing it by key. Never once a
	/// pass found a fill of every place needed (`ScopeGenerator.buildsFillOfEveryPlace`).
	private var sharesFillsBetweenPlaces: Bool {
		!SeamFillSharing.buildsFillOfEveryPlace
			&& scope.seamCall != nil
			&& scope.publicMockCall == nil
			&& !forMockGeneration
			&& fill == nil
			&& enclosingFills.isEmpty
			&& previousPassGenerator?.buildsFillOfEveryPlace != true
	}

	/// A fill this call built that generates no code, which can stand for a later place of its case.
	private struct FillStandIn {
		/// The index of the fill's generator among `childGenerators`.
		let childIndex: Int
		let key: String
		let hole: SeamSignature.Hole
		/// The scope the fill builds.
		let scope: ObjectIdentifier
	}

	/// What the tree a fill built reads of the place it was built for.
	private struct FillTreeReads: Hashable {
		/// The labels the tree receives from outside it, which the fill's fields or the caller's declarations answer.
		let labels: Set<String>
		/// The concrete types the tree builds, whose properties alone can repeat an entry of the seam's path.
		let builtTypes: Set<TypeDescription>
	}

	/// The fills this call built for one case that can stand for the case's later places, found by what a place hands its
	/// fill, so that a place neither scans nor copies the fills built before it: a case reached along thousands of paths
	/// has that many places. Held while the call's fills are created, with the scope under construction.
	private struct FillStandIns {
		/// The fill built last, whose tree the next place of the case to ask reads: its generator exists only once it is
		/// built, after `nextFill()` returns it.
		var fillWhoseTreeIsNotReadYet: FillStandIn?
		/// What each distinct tree among the fills reads, in the order the fills were built, each with the key of the fill
		/// built for each place those reads tell apart. Fills of one case build one scope, so nearly every case has one.
		var keysByVariantOfEachTreeReads = [(reads: FillTreeReads, keysByVariant: [FillVariant: String])]()
		/// Whether a fill of the case holds what no other place's judgement could read of it (`treeReads(ofFillStandingIn:)`).
		/// The fills of a case build one scope, whose tree holds it for every place, so no later fill is kept either.
		var noFillStandsIn = false
	}

	/// What the tree of a fill that generates no code is built from, of its place: two places of one case with equal
	/// values get equal trees. The place's fields of the labels the tree receives, in order, since a field is the nearest
	/// declaration of its label in the fill, each with what decides how the fill binds it; the entries of the seam's path
	/// the fill is built beneath that the tree could close a cycle on, as a set, since a scope closes on the entry of its
	/// property and concrete type wherever on the path it is; and what the fill reads of the place besides.
	private struct FillVariant: Hashable {
		struct Field: Hashable {
			let property: Property
			let spelling: String
			let deferral: SeamSignature.Parameter.Deferral
			let bindsMemo: Bool
		}

		struct PathEntry: Hashable {
			let property: Property
			let concreteType: TypeDescription
		}

		let scope: ObjectIdentifier
		let property: Property
		let propertySpelling: String
		let erasedToConcreteExistential: Bool
		let isSendable: Bool
		let isPassedUpByCalledSeam: Bool
		let fields: [Field]
		let path: Set<PathEntry>

		init(of hole: SeamSignature.Hole, builtBy scope: ObjectIdentifier, labels: Set<String>, builtTypes: Set<TypeDescription>) {
			self.scope = scope
			property = hole.property
			propertySpelling = hole.property.typeDescription.asSource
			erasedToConcreteExistential = hole.erasedToConcreteExistential
			isSendable = hole.isSendable
			isPassedUpByCalledSeam = hole.innerSeamType != nil
			fields = hole.fields.compactMap { field in
				guard labels.contains(field.property.label) else { return nil }
				return Field(property: field.property, spelling: field.property.typeDescription.asSource, deferral: field.deferral, bindsMemo: field.bindsMemo)
			}
			var path = Set<PathEntry>()
			for (property, concreteType) in zip(hole.fillPropertyStack, hole.fillConcreteTypeStack) where builtTypes.contains(concreteType) {
				path.insert(PathEntry(property: property, concreteType: concreteType))
			}
			self.path = path
		}
	}

	/// The key of the fill this call built that stands for the fill of `hole`, which would build `scope`, or `nil` when the
	/// place needs a fill of its own.
	private func standInKey(forFillOf hole: SeamSignature.Hole, builtBy scope: ConstructionScope, among standIns: inout FillStandIns) -> String? {
		if let built = standIns.fillWhoseTreeIsNotReadYet {
			standIns.fillWhoseTreeIsNotReadYet = nil
			if let reads = treeReads(ofFillStandingIn: built) {
				let variant = FillVariant(of: built.hole, builtBy: built.scope, labels: reads.labels, builtTypes: reads.builtTypes)
				if let index = standIns.keysByVariantOfEachTreeReads.firstIndex(where: { $0.reads == reads }) {
					standIns.keysByVariantOfEachTreeReads[index].keysByVariant[variant] = built.key
				} else {
					standIns.keysByVariantOfEachTreeReads.append((reads, [variant: built.key]))
				}
			} else {
				standIns = FillStandIns(noFillStandsIn: true)
			}
		}
		let scopeIdentity = ObjectIdentifier(scope.identity)
		for (reads, keysByVariant) in GenerationWork.taking(standIns.keysByVariantOfEachTreeReads, by: .findingFillThatStandsForPlace) {
			if let key = keysByVariant[FillVariant(of: hole, builtBy: scopeIdentity, labels: reads.labels, builtTypes: reads.builtTypes)] {
				return key
			}
		}
		return nil
	}

	/// What the tree of `standIn`'s fill reads, or `nil` where the tree holds a call of a seam or a public mock, a fill, or
	/// a place: what such a tree hands on is keyed by the fill's own place.
	private func treeReads(ofFillStandingIn standIn: FillStandIn) -> FillTreeReads? {
		guard childGenerators.indices.contains(standIn.childIndex) else { return nil }
		let fillGenerator = childGenerators[standIn.childIndex]
		guard let built = fillGenerator.children.first,
		      !built.treeHoldsCallOrFill,
		      !built.containsBuildSite,
		      fillGenerator.fieldsCarriedBySites.isEmpty
		else { return nil }
		var builtTypes = Set<TypeDescription>()
		var generatorsToVisit = [built]
		while let generator = generatorsToVisit.popLast() {
			if let instantiable = generator.builtInstantiable {
				builtTypes.insert(instantiable.concreteInstantiable)
			}
			generatorsToVisit.append(contentsOf: generator.children)
		}
		return FillTreeReads(labels: Set(built.receivedProperties.map(\.label)), builtTypes: builtTypes)
	}

	/// The fills this call built that can stand for later places of their cases, by `ScopeGenerator.fillCaseKey(of:)`.
	private var fillStandInsByCaseKey = [String: FillStandIns]()
	/// The places whose fills this call did not build (see `nextFill()`).
	private var fillsStoodFor = [ScopeGenerator.FillStoodFor]()
	/// How many fills `nextFill()` has handed out to build.
	private var builtFillCount = 0

	/// The generator the pass before created for the fill keyed `key`, or the one that stood for it there, or `nil` in the
	/// first pass. A pass can build a fill for a place another pass built none for, so a fill that is not where this
	/// pass's is, is found by its key.
	private mutating func previousPassFillGenerator(keyed key: String) -> ScopeGenerator? {
		guard let previousPassGenerator else { return nil }
		let previousPassChildren = previousPassGenerator.children
		if previousPassChildren.indices.contains(childGenerators.count), previousPassChildren[childGenerators.count].fillKey == key {
			return previousPassChildren[childGenerators.count]
		} else {
			if previousPassFillGeneratorsByKey == nil {
				var generatorsByKey = [String: ScopeGenerator]()
				for child in previousPassChildren {
					if let fillKey = child.fillKey {
						generatorsByKey[fillKey] = child
					}
				}
				for fillStoodFor in previousPassGenerator.fillsStoodFor {
					generatorsByKey[fillStoodFor.key] = generatorsByKey[fillStoodFor.standInKey]
				}
				previousPassFillGeneratorsByKey = generatorsByKey
			}
			return previousPassFillGeneratorsByKey?[key]
		}
	}

	/// The pass before's generator of each of this call's fills, and for each place it built none for the one that stood
	/// for it, by the fill's key: built once, when a fill is first not where this pass's is, and held while the call's
	/// fills are created.
	private var previousPassFillGeneratorsByKey: [String: ScopeGenerator]?

	/// The scope under construction for the property a fill of this scope's seam call builds: the scope of the type
	/// that fulfills the hole in the caller's declarations, built with the stack the seam whose tree holds the site
	/// reaches it with, and with the fields of the site's scope struct in scope beside what encloses the call.
	mutating func fillUnderConstruction(fill: Fill, scope: ConstructionScope, context fillContext: ScopeRecord.FillContext) throws -> ScopeGeneratorUnderConstruction {
		var fill = fill
		let hole = fill.hole
		try validateForwardedProperties(of: hole.property, declaredAt: hole.declarationLocation, on: hole.ownerType, seeingThroughModulesNamed: hole.declaringModuleNames, building: scope.instantiable)
		// A field bound from a parameter the seam defers holds the seam's memo of what the call passed, which is the
		// declaration of its label in the caller's scope: the fill reads that declaration, as inline, so the value is
		// created when the tree reads it. Except where a call inside a fill of this call passes this fill on beneath
		// another declaration of the label (see `ScopeGenerator.fillDeferredLabelsHiddenByReenteringCalls`): the fill,
		// one function, reads the struct's field there, which the pass before found.
		// A place a seam passes up from a seam it calls holds the memo of what that call passed, which no declaration of the
		// caller's is: the fill reads the struct's field, as inline reads the passing-up seam's declaration. So does a fill
		// some route hands such a memo through the levels on a carried route (`Fill.labelsHandedAsMemo`).
		let deferredLabelsBoundFromStruct = previousPassGenerator?.fillDeferredLabelsHiddenByReenteringCalls[fill.key] ?? []
		let readsDeferredFieldsFromStruct = hole.innerSeamType != nil && self.scope.publicMockCall == nil
		// A deferred parameter's field it reads from the struct, it binds as the memo (`bindingItsMemo`), whose instance its tree
		// reads where it reads the value, so the value is created when the tree reads it, as inline. The field keeps its own
		// property, which decides what it satisfies; the memo decides only when the value is created.
		// A deliberate gap against inline: where the fill's tree reads the label inside a `@Sendable` function and the memo is a
		// `LazilyInstantiated`, which no `@Sendable` function can capture, the fill binds the struct's by-value member instead,
		// which reads the memo's instance where the fill, or a level function on its route, is handed the struct, so the value
		// is created there rather than where the tree reads it (`ScopeGenerator.fillDeferredLabelsReadInsideSendableFunction`,
		// which the pass before found). The seam cannot defer it `@Sendable` instead: its signature is settled in its own
		// module, which sees no fill, and SafeDI cannot tell whether the type is `Sendable`. A `SendableLazilyInstantiated` the
		// fill takes, such as one some route hands where its tree reads that wrapper too, is bound as the memo, which a
		// `@Sendable` function captures: the pass before found the label read inside one while the fill still took a
		// `LazilyInstantiated`.
		let deferredLabelsBoundByValue = previousPassGenerator?.fillDeferredLabelsReadInsideSendableFunction[fill.key] ?? []
		func isBoundFromStruct(_ field: SeamSignature.Hole.Field) -> Bool {
			field.isDeferredParameter && (readsDeferredFieldsFromStruct || deferredLabelsBoundFromStruct.contains(field.property.label) || fill.labelsHandedAsMemo.contains(field.property.label))
		}
		func isBoundByValue(_ field: SeamSignature.Hole.Field) -> Bool {
			deferredLabelsBoundByValue.contains(field.property.label) && field.deferral != .deferred(isSendable: true)
		}
		fill.fields = fill.fields.map { isBoundFromStruct($0) && !isBoundByValue($0) ? $0.bindingItsMemo : $0 }
		let boundFields = fill.fields.filter { !$0.isDeferredParameter || isBoundFromStruct($0) }
		fill.boundLabels = Set(boundFields.map(\.property.label))
		fill.callerNearestDeclarations = childNearestDeclarations
		// A value the called public mock binds at its root from the argument the call passes, outside the `@Sendable` function
		// that builds the place, is the caller's own where the caller binds the value's form here: the call passes it, so the
		// fill reads it from the caller's scope, as the twin's fill reads the seam's parameter. Where the caller binds another
		// form or none, the mock may build a value of its own, which no fill can read: the declaration stays uncarried, a
		// deliberate gap against the twin, whose seam takes the value as a parameter (`seam-holes.md`, and the message of
		// `declarationBoundAfterSite` for such a declaration).
		// Whether the caller binds the form reads the caller's nearest declaration of the label, logged whole.
		var log = log
		fill.hole.uncarriedDeclarations.removeAll { declaration in
			guard declaration.isBoundFromCallersArgument else { return false }
			Self.logNearestDeclaration(of: declaration.property.label, in: childNearestDeclarations, log: &log)
			return childNearestDeclarations.binds(declaration.property)
		}
		self.log = log
		fill.callerLazilyInstantiatedInstanceProperties = childLazilyInstantiatedInstanceProperties
		let fieldLabels = Set(boundFields.map(\.property.label))
		var fieldInstanceProperties = Set<Property>()
		// A value the fill takes from the caller's scope is available as it would be to a pass-through of the call: one
		// the caller's path is still building is not, so a receive of it only if available is passed `nil`. Each field
		// the fill binds hides every declaration of its label in the caller's scope.
		var fillNearestDeclarations = childNearestDeclarations
		for field in boundFields {
			let property = field.property
			fillNearestDeclarations.replace(property, providing: CycleParameter.forms(providedBy: property))
			if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				// A wrapper the fill takes optionally offers its instance only as an optional, which a receive reads through the
				// optional (`Set<Property>.lazilyInstantiatedInstanceSource(of:boundAs:)`).
				fieldInstanceProperties.insert(fill.optionalLazilyInstantiatedLabels.contains(property.label) ? instanceProperty.asOptionalProperty : instanceProperty)
			}
			// A field bound as its memo is read as the memo's instance wherever the tree reads its label, as the seam's own tree
			// reads a deferred parameter's memo (`DependencyTreeGenerator.seamRootGenerator`): `tag: Tag` for `tag: Tag?`, and
			// `x: X!` itself for `x: X!`, which the tree reads as `x.instance`.
			if field.bindsMemo {
				fieldInstanceProperties.insert(property.asUnwrappedProperty)
			}
		}
		// A caller's own value the fill reads from its mock root's binding, which the fill binds under the label, hides every
		// other declaration of the label, as a field does: the tree reads a by-value form as the binding's instance.
		var mockRootBoundLabels = Set<String>()
		for (label, property) in fill.mockRootBindingByLabel {
			mockRootBoundLabels.insert(label)
			fillNearestDeclarations.replace(property, providing: CycleParameter.forms(providedBy: property))
			if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				fieldInstanceProperties.insert(instanceProperty)
			}
		}
		return ScopeGeneratorUnderConstruction(
			scope: scope,
			property: (hole.property, fillContext.propertyID),
			// The fill's stack is the path of the seam whose tree holds the site, put on it above this tree.
			contextStack: fillContext.contextStack,
			depth: depth + 1,
			fillPathStackCount: fillContext.contextStack.count,
			fillCallDepth: depth,
			nearestDeclarations: fillNearestDeclarations,
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties.filter { !fieldLabels.contains($0.label) && !mockRootBoundLabels.contains($0.label) }.union(fieldInstanceProperties),
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath + hole.pathBeforePropertyInItsFill,
			enclosingFills: GenerationWork.taking(enclosingFillsOfThisCall, by: .gatheringFillsOfACall),
			enclosingFillNames: enclosingFillNamesOfThisCall,
			enclosingCarriedInnerScopes: enclosingCarriedInnerScopesOfThisCall,
			enclosingLevelReentries: enclosingLevelReentriesOfThisCall,
			erasedToConcreteExistential: hole.erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			fill: fill,
			// A fill a mock declares builds the hole's tree as the mock's tree built inline would.
			buildsWithHandWrittenMocks: forMockGeneration,
			declaredTypeNames: declaredTypeNames,
			// The pass before created a fill's generator around the generator of the property it builds. A fill is a
			// function of its own, declared where the seam is called, so no function enclosing the call that a lazy cycle
			// closes on encloses a cycle-closing scope in the fill. The fill's own built scope takes the parameters the
			// pass before found for it as any scope does, when a lazy cycle inside the fill closes on its property.
			previousPassGenerator: previousPassFillGenerator(keyed: fill.key)?.children.first,
			cycleParameterContexts: [:],
			// A place inside the fill is a place of the type the fill builds, whose builds start their children in its order.
			placeHoldingPropertiesByType: placeHoldingPropertiesByType,
			// A fill is never stored, and leaves every scope above it unstored, so its reads are recorded only as its
			// enclosing scope's are.
			recordsReads: recordsReads,
		)
	}

	/// Creates the generator of a hole this scope's type instantiates, a site of the seam whose tree is generated.
	mutating func addHoleGenerator(property: Property, erasedToConcreteExistential: Bool) {
		// A hole's generator holds the whole path to it (its owner's stacks), which the memo's log does not cover: a tree
		// built only to find a seam's or public mock's signature has holes but no `seamHoles`.
		isMemoizable = false
		subtreeIsShareable = false
		childGenerators.append(ScopeGenerator(
			holeProperty: property,
			erasedToConcreteExistential: erasedToConcreteExistential,
			site: seamHoles.site(at: sitePath + [property]),
			// A tree that takes no builder, a root's, holds no place: the only hole validation leaves there is a property
			// instantiated only if available that nothing fulfills, which is `nil`, and orders its siblings as it does in a
			// module that generates no seam. A mock's tree keeps the place, a deliberate gap until mocks pass `nil`.
			holdsPlace: seamHoles.takesBuilders || forMockGeneration || !property.typeDescription.isOptional,
			ownerPropertyStack: childContextStack.propertiesInnermostFirst,
			ownerConcreteTypeStack: childContextStack.concreteTypesInnermostFirst,
			ownerLazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
			carrierSite: seamHoles.carrierSite(at: sitePath + [property]),
		))
	}

	/// The scope under construction for a scope this one instantiates.
	/// - Parameter isKeyed: Whether the child has a construction memo key, so that its reads are recorded for its entry.
	func childUnderConstruction(
		scope: ConstructionScope,
		property: Property,
		propertyID: PropertyID,
		erasedToConcreteExistential: Bool,
		isKeyed: Bool,
	) -> ScopeGeneratorUnderConstruction {
		ScopeGeneratorUnderConstruction(
			scope: scope,
			property: (property, propertyID),
			contextStack: childContextStack,
			depth: depth + 1,
			fillPathStackCount: fillPathStackCount,
			fillCallDepth: fillCallDepth,
			nearestDeclarations: nearestDeclarations(ofChildBuilding: property),
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath,
			enclosingFills: enclosingFills,
			enclosingFillNames: enclosingFillNames,
			enclosingCarriedInnerScopes: enclosingCarriedInnerScopes,
			enclosingLevelReentries: enclosingLevelReentries,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			buildsWithHandWrittenMocks: buildsWithHandWrittenMocks,
			declaredTypeNames: declaredTypeNames,
			previousPassGenerator: previousPassChildGenerator,
			cycleParameterSeed: cycleParameterSeed?.child(at: childGenerators.count),
			cycleParameterContexts: childCycleParameterContexts,
			// The loops the pass before found among this scope's children.
			reboundProperties: childReboundProperties,
			placeHoldingPropertiesByType: placeHoldingPropertiesByType,
			recordsReads: recordsReads || isKeyed,
		)
	}

	/// Throws when `property`, a dependency of this scope's type that `scope` builds, is an erased instantiator whose first
	/// generic argument is not the `@Forwarded` properties of `scope`'s type (see `validateForwardedProperties(of:…)`). Run for
	/// every child, whether its generator is created or reused.
	func validateForwardedProperties(ofChildBuilding scope: ConstructionScope, as property: Property) throws {
		try validateForwardedProperties(
			of: property,
			declaredAt: self.scope.instantiable.dependencies.first(where: { $0.property == property })?.declarationLocation,
			on: self.scope.instantiable.concreteInstantiable,
			seeingThroughModulesNamed: [],
			building: scope.instantiable,
		)
	}

	/// The key under which the generator of the child of this scope that builds `property` with `scope` is stored and looked
	/// up in a construction memo, or `nil` where the child reads context the memo's log does not cover: it is inside a fill,
	/// or in a tree with holes (see `ConstructionMemo`).
	func memoKey(ofChildBuilding scope: ConstructionScope, as property: Property, id propertyID: PropertyID, erasedToConcreteExistential: Bool) -> ConstructionMemo.Key? {
		guard enclosingFills.isEmpty, seamHoles.isEmpty, fill == nil else { return nil }
		return ConstructionMemo.Key(
			scope: ObjectIdentifier(scope.identity),
			property: propertyID,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			buildsWithHandWrittenMocks: buildsWithHandWrittenMocks,
			mayPassNil: nearestDeclarations(ofChildBuilding: property).mayPassNil,
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
			reboundProperties: childReboundProperties,
			spellings: Property.spellingsForConstructionMemo(of: childLazilyInstantiatedInstanceProperties, childReboundProperties),
			previousPassGenerator: previousPassChildGenerator.map(ObjectIdentifier.init),
			cycleParameterSeed: cycleParameterSeed?.child(at: childGenerators.count).map(ObjectIdentifier.init),
		)
	}

	/// The nearest declarations the child of this scope that builds `property` is built beneath: at a mock root, a child
	/// the root promotes is built beneath the declarations before the root's own required receives pinned any (see
	/// `MockReceivesPassedNil.promotedProperties`), and every other child beneath `childNearestDeclarations`.
	private func nearestDeclarations(ofChildBuilding property: Property) -> NearestDeclarations {
		if let promotedChildNearestDeclarations, childNearestDeclarations.isPromotedByMockRoot(property) {
			promotedChildNearestDeclarations
		} else {
			childNearestDeclarations
		}
	}

	/// The context the scope this scope instantiates as `property` inherits (see `ConstructionContext`).
	func childContext(ofChildBuilding property: Property) -> ConstructionContext {
		ConstructionContext(
			contextStack: childContextStack,
			interner: scope.interner,
			nearestDeclarations: nearestDeclarations(ofChildBuilding: property),
			cycleParameterContexts: childCycleParameterContexts,
		)
	}

	/// The properties the next child whose generator is created rebinds as a member of a loop of builders the pass before
	/// found among this scope's children.
	private var childReboundProperties: Set<Property> {
		previousPassGenerator?.receivedBuilderLoops.reboundPropertiesByChildIndex[childGenerators.count] ?? []
	}

	/// Throws when `property`, declared on `parent` at `declarationLocation`, is an erased instantiator whose first
	/// generic argument is not the `@Forwarded` properties of `builtInstantiable`, unless the tree skips the check
	/// (`validatesForwardedProperties`).
	/// - Parameter declaringModuleNames: The modules, beside the built type's, whose name may qualify a type either
	///   spelling names: for a fill, that of the seam that holds the hole (`SeamSignature.Hole.declaringModuleNames`).
	private func validateForwardedProperties(
		of property: Property,
		declaredAt declarationLocation: Dependency.DeclarationLocation?,
		on parent: TypeDescription,
		seeingThroughModulesNamed declaringModuleNames: [String],
		building builtInstantiable: Instantiable,
	) throws {
		guard validatesForwardedProperties, let error = ErasedInstantiatorForwardedPropertiesMismatchError(
			property: property,
			declarationLocation: declarationLocation,
			parent: parent,
			builtInstantiable: builtInstantiable,
			declaringModuleNames: declaringModuleNames,
			declaredTypeNames: declaredTypeNames,
		) else { return }
		throw error
	}

	/// The generator the pass before created for the child whose generator is created next, or `nil` in the first pass.
	private var previousPassChildGenerator: ScopeGenerator? {
		guard let previousPassChildren = previousPassGenerator?.children,
		      previousPassChildren.indices.contains(childGenerators.count)
		else { return nil }
		return previousPassChildren[childGenerators.count]
	}

	/// Creates the generator of an alias this scope declares.
	mutating func addAliasGenerator(
		property: Property,
		fulfillingProperty: Property,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool,
		declarationReference: AliasDeclarationReferences.Reference?,
	) {
		// An alias that keeps the label of the dependency it retypes is not in scope where its
		// own value is read, so it does not shadow a lazily instantiated property further up the tree.
		let instanceProperties = fulfillingProperty.label == property.label
			? lazilyInstantiatedInstanceProperties
			: childLazilyInstantiatedInstanceProperties
		// Beneath a fill that takes a wrapper optionally, an alias only if available reads the instance through the optional
		// (`Fill.optionalLazilyInstantiatedLabels`).
		let readsOptionalInstance = onlyIfAvailable
			&& !instanceProperties.contains(fulfillingProperty.asUnwrappedProperty)
			&& instanceProperties.contains(fulfillingProperty.asUnwrappedProperty.asOptionalProperty)
		let fulfillingExpression: String? = if readsOptionalInstance {
			"\(fulfillingProperty.label)?.\(Dependency.lazilyInstantiatedInstancePropertyName)"
		} else if self.property == nil, fulfillingProperty.label == property.label {
			// A seam's own alias that keeps the label of a deferred parameter is bound from the parameter's autoclosure.
			seamRoot?.autoclosureCallByLabel(of: scope.instantiable)[property.label]
		} else {
			nil
		}
		childGenerators.append(ScopeGenerator(
			property: property,
			fulfillingProperty: fulfillingProperty,
			fulfillingPropertyIsLazilyInstantiatedInstance: instanceProperties.contains(fulfillingProperty.asUnwrappedProperty),
			unavailableOptionalProperties: unavailableOptionalProperties,
			fulfillingPropertyIsPassedNil: receivesPassedNil.contains(fulfillingProperty),
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable,
			// The declared property an `onlyIfAvailable` alias is bound from decides whether its value may be `nil`: a
			// parameter made optional, a seam's optional parameter, or an optional property the alias reads in place of
			// its fulfilling property's non-optional form.
			fulfillingBindingIsOptional: readsOptionalInstance || aliasBindings[property]?.typeDescription.isOptional ?? false,
			fulfillingExpression: fulfillingExpression,
			declarationReference: declarationReference,
		))
	}

	/// What `fill`, which generates the code of a case nested by type, reads of the caller's scope through the root
	/// dispatcher, given `child`, the generator of what it builds: for each label a level holds on some route to the case
	/// and none holds on another, each form `child`'s tree reads of it, which the fill receives from the scopes enclosing
	/// the call as `child` would inline, so the caller builds a required one first; the parameter the fill takes for it,
	/// optional where no read requires it, so a route on which the caller declares none passes `nil`; and the argument the
	/// root dispatcher passes: the caller's declaration of the parameter's form, its instance where the caller holds it
	/// lazily, or `nil`. `labelsHandedToReenteredFunctions` are the labels of the values a call in `child`'s tree that
	/// re-enters a root level function of an enclosing call hands it non-optional.
	private static func callerReads(of fill: Fill, child: ScopeGenerator, labelsHandedToReenteredFunctions: Set<String>, log: inout ConstructionLog) -> ScopeGenerator.FillCallerReads {
		var reads = ScopeGenerator.FillCallerReads()
		// The inner scope, only where the fill's tree builds a place or a call that passes one up, whose case carries it, or a
		// call that re-enters an enclosing call's fill, whose case's member is called on it.
		if child.readsFillInnerScopes {
			reads.innerScopeParameters = fill.innerScopeParameters
		}
		for field in fill.fields where fill.callerReadLabels.contains(field.property.label) && fill.boundLabels.contains(field.property.label) {
			let label = field.property.label
			// No site inside the fill carries the field: a site carries the values of the levels inside the fill
			// (`ScopeGenerator.fieldsCarried(by:)`), and each level leaves out of what its sites carry the labels it declares,
			// which leaves only a label a level carries without declaring it: a member of a loop of builders its function wraps
			// again, which the scope that builds the loop declares, a scope inside the fill, since a fill's own generator finds
			// no loops; or a parameter a lazy cycle closes on, whose declaration is inside the fill, since a cycle a fill closes
			// on a declaration of the seam's tree is an error (`FillFinding.Kind.closesCycleInSeamTree`).
			var forms = Set(child.receivedProperties.filter { $0.label == label })
			// A call in `child`'s tree that re-enters a root level function hands it the fill's value of each label the function
			// takes (`PublicMockLevelFunctions.Reentry`), so the fill takes that value as a required read where the function takes
			// it non-optional, whatever the fill's own tree reads of it: as where a fill of a called type that holds no copy of the
			// caller's value builds the called type again, itself or through another call's fill, and reads the value only if
			// available, beside a fill of another place that reads it by value. Where such a fill reads none of a value the
			// module holds lazily, the place is passed up before any fill is built
			// (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`).
			let isHandedToReenteredFunction = labelsHandedToReenteredFunctions.contains(label)
			if isHandedToReenteredFunction {
				forms.insert(field.property)
			}
			guard !forms.isEmpty else { continue }
			func isRequired(_ form: Property) -> Bool {
				child.requiredReceivedProperties.contains(form) || (isHandedToReenteredFunction && form == field.property)
			}
			let parameter = !fill.optionalLazilyInstantiatedLabels.contains(label) && (forms.contains(where: isRequired) || field.property.typeDescription.isOptional)
				? field
				: field.withProperty(field.property.asOptionalProperty)
			reads.parameterByLabel[label] = parameter
			for form in forms.sorted() {
				reads.dependencies.append(Dependency(property: form, source: .received(onlyIfAvailable: !isRequired(form))))
				if !isRequired(form), binding(of: form, in: fill.callerNearestDeclarations, log: &log) == nil {
					reads.unavailableProperties.insert(form)
				}
			}
			reads.argumentByLabel[label] = callerArgument(reading: parameter.property, of: fill.callerNearestDeclarations, lazilyInstantiatedInstanceProperties: fill.callerLazilyInstantiatedInstanceProperties, log: &log).spelled
		}
		reads.mockRootBindingByLabel = fill.mockRootBindingByLabel
		for field in fill.fields where fill.labelsHandedAsMemo.contains(field.property.label) && field.bindsMemo && field.deferral == .deferred(isSendable: true) {
			let memo = field.memoProperty
			reads.memoArgumentByMemo[memo] = callerArgument(reading: memo, of: fill.callerNearestDeclarations, lazilyInstantiatedInstanceProperties: fill.callerLazilyInstantiatedInstanceProperties, log: &log).spelled
		}
		return reads
	}

	/// The labels of the values the root level functions of enclosing calls that a call in `generator`'s tree re-enters
	/// take non-optional, which the re-entering call reads of its own scope (`PublicMockLevelFunctions.Reentry`, found the
	/// pass before).
	private func labelsHandedToReenteredFunctions(by generator: ScopeGenerator) -> Set<String> {
		var labels = Set<String>()
		for key in generator.referencedFillNamesByKey.keys {
			for property in enclosingLevelReentries[key]?.parameters ?? [] where !property.typeDescription.isOptional {
				labels.insert(property.label)
			}
		}
		return labels
	}

	/// What a call hands a parameter of `property`'s form that a fill reads of the scope enclosing the call, given that
	/// scope's `nearestDeclarations` and the properties it holds only as a `LazilyInstantiated`'s instance: the nearest
	/// declaration of the form, its instance where the scope holds it lazily, or `nil`. A `LazilyInstantiated` form the
	/// scope does not declare, where it declares the instance – a route of a seam's tree binds the wrapper and the caller
	/// the value – is a wrapper the call makes of the caller's value, so the fill reads the instance where its tree reads
	/// it on every route, as inline does; an optional one maps an optional value the scope declares. Each binding read is
	/// logged in `log`: two places a construction memo shares the call at can differ in it alone.
	private static func callerArgument(reading property: Property, of nearestDeclarations: NearestDeclarations, lazilyInstantiatedInstanceProperties: Set<Property>, log: inout ConstructionLog) -> ArgumentSource {
		guard let binding = binding(of: property, in: nearestDeclarations, log: &log) else {
			guard let instanceProperty = property.asLazilyInstantiatedInstanceProperty,
			      let instanceBinding = binding(of: instanceProperty, in: nearestDeclarations, log: &log)
			else { return .nil }
			let wrapperType = property.typeDescription.unwrapped
			let instance = callerArgument(reading: instanceProperty, of: nearestDeclarations, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties, log: &log)
			return instanceBinding.typeDescription.isOptional
				? .optionalWrapper(of: instance, wrapperType: wrapperType)
				: .wrapper(of: instance, wrapperType: wrapperType)
		}
		return !property.propertyType.isLazilyInstantiated
			&& (binding.propertyType.isLazilyInstantiated || lazilyInstantiatedInstanceProperties.contains(property.asUnwrappedProperty))
			? .lazyInstance(label: property.label, throughOptional: false)
			: .binding(label: property.label)
	}

	/// The field a public mock caller's fill of a case nested by type takes for one label, given `fields`, the case's places'
	/// fields of that label in place order, and `reads`, the forms of it the fill's tree receives: the form it reads that
	/// provides every other (`CycleParameter.forms(providedBy:)`, the relation the per-place decision `holesFilled` fills
	/// by), else the first place's field that provides every form it reads, so a route whose nearest type binds a form
	/// that provides it fills the place, as the per-place decision does. `nil`
	/// where the fill reads no form of the label, or no field provides every form it reads: no place of the case is then
	/// filled through the label, and the fill keeps its first place's field.
	private static func parameterField(of fields: [SeamSignature.Hole.Field], reading reads: Set<Property>) -> SeamSignature.Hole.Field? {
		guard let firstField = fields.first, !reads.isEmpty else { return nil }
		let property = reads.sorted().first { reads.isSubset(of: CycleParameter.forms(providedBy: $0)) }
			?? fields.map(\.property).first { reads.isSubset(of: CycleParameter.forms(providedBy: $0)) }
		guard let property else { return nil }
		return SeamSignature.Hole.Field(
			property: property,
			access: firstField.access,
			accessCause: firstField.accessCause,
			declaringType: firstField.declaringType,
			declarationLocation: firstField.declarationLocation,
			isReceivedOnlyIfAvailable: firstField.isReceivedOnlyIfAvailable,
			deferral: firstField.deferral,
		)
	}

	/// The labels of `fields`, the fields of a fill of `places` – the places of one case of a call of another module's public
	/// mock – that are the caller's own values: the called mock's root binds each as its copy of the value the call hands it
	/// from the caller's scope, a received parameter `call` passes, and that copy is the nearest declaration of the label at
	/// every place of the case that carries a field of it (`SeamSignature.Hole.Field.isBoundByPublicMockRoot`), while a
	/// place that carries none has the fill read the caller's declaration already; and `callerDeclarations`, the
	/// declarations enclosing the call, bind every form of it the fill's tree reads (`reads`) under the label itself: a
	/// scope of the caller's tree does, and so does the caller's mock root where it binds the value as the root's one
	/// declaration of the label (`NearestDeclarations.markBoundUnderLabelByRoot`).
	///
	/// Two more are the caller's own where the called mock's copy does not provide every form the fill reads, such as the
	/// caller's `LazilyInstantiated`, and no fill re-enters the call (`fillsReenterCall`): a label of `carriedLabels`, which the
	/// case's payload carries, and a label whose nearest declaration is the caller's mock root's binding of a value its tree
	/// receives, which the mock can name apart from the label (`NearestDeclaration.isBoundByMockRoot`), where one property the
	/// root binds provides every form the fill reads: the fill reads that property under the name the mock spells
	/// (`CallersOwnLabels.mockRootBindingByLabel`).
	///
	/// Any other label keeps its field, which the levels on each route hand the fill. A level of the called mock that
	/// declares the label again hands its own value, which inline reads there. A level that holds only the called mock's
	/// by-value copy cannot hand a fill that reads the caller's `LazilyInstantiated`, so where a level that declares the
	/// label again hides the copy from one place of a case and the copy reaches another, the fills of that hole type read
	/// different wrappers, and `DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)` passes it up
	/// whole before any fill is generated (`SafeDIToolCallingMockMirrorsProductionTests`'
	/// `whenPlacesOfOneHoleTypeReadDifferentLazyValuesBesideTheirFields`).
	private static func callersOwnLabels(
		amongLabelsOf fields: [SeamSignature.Hole.Field],
		carrying carriedLabels: Set<String>,
		at places: [SeamSignature.Hole],
		reading reads: Set<Property>,
		handedFrom callerDeclarations: NearestDeclarations,
		by call: PublicMockCall,
		whereFillsReenterCall fillsReenterCall: Bool,
		log: inout ConstructionLog,
	) -> CallersOwnLabels {
		let labelsHandedFromCaller = Set(call.passedParameters.compactMap { parameter in
			parameter.builder == nil && parameter.dependency.source.isReceived ? parameter.dependency.property.label : nil
		})
		// Whether the fill reads the caller's declaration of `label` at `place`: where the place carries a field of the label,
		// where that field is the called mock's copy; where it carries none, always. A place carries no field of a label no
		// level holds on its route, where the fill reads the caller's declaration already (`callerReadLabels`), nor at a place
		// inside a `@Sendable` function of one bound outside it: the called mock's copy, which the fill reads as the caller's
		// declaration (`isBoundFromCallersArgument`, dropped from the fill's hole in `fillUnderConstruction`), whether the tree
		// receives it outright or only if available. A declaration of the called mock's own outside the function is an error
		// wherever a fill reads it (`boundOutsideSendableFunction`).
		func isCalledMocksCopy(of label: String, at place: SeamSignature.Hole) -> Bool {
			place.fields.first { $0.property.label == label }?.isBoundByPublicMockRoot ?? true
		}
		// Whether the called mock's copy of `label` at every place provides each of `formsRead`. A place that carries no field of
		// the label holds no copy.
		func copyProvides(_ formsRead: Set<Property>, of label: String) -> Bool {
			places.allSatisfy { place in
				place.fields.first { $0.property.label == label }.map { formsRead.isSubset(of: CycleParameter.forms(providedBy: $0.property)) } ?? false
			}
		}
		var callersOwnLabels = CallersOwnLabels()
		for label in fields.map(\.property.label) {
			let formsRead = reads.filter { $0.label == label }
			guard labelsHandedFromCaller.contains(label),
			      !formsRead.isEmpty,
			      places.allSatisfy({ isCalledMocksCopy(of: label, at: $0) }),
			      let callerDeclaration = logNearestDeclaration(of: label, in: callerDeclarations, log: &log)
			else { continue }
			// Where a fill re-enters the call, a label the payload carries, or the caller's mock root binds, keeps its field: the
			// re-entering call hands its own nearest declaration (`PublicMockLevelFunctions.Reentry`).
			let readsPastCalledMockCopy = !fillsReenterCall && !copyProvides(formsRead, of: label)
			// A label the case's payload carries the fill binds from the payload, the called mock's copy, which holds the caller's
			// value, except where the copy does not provide every form the fill reads, such as the caller's `LazilyInstantiated`
			// beside the value it holds: the fill reads the caller's declaration, which provides both.
			guard !carriedLabels.contains(label) || readsPastCalledMockCopy else { continue }
			if callerDeclaration.isBoundByMockRoot {
				// The caller's mock root binds the value, which it can name apart from the label: the fill reads the root's binding of
				// one property that provides every form it reads, under the name the mock spells: the first in `Property` order of
				// those the root binds the forms read to, else of every property it binds of the label. Where the copy provides them
				// all, the levels hand the fill the copy, which holds the same value, and where no one binding provides them all, the
				// label keeps its field.
				let bindingsOfFormsRead = Set(formsRead.compactMap { callerDeclaration.bindings[$0] }).sorted()
				guard readsPastCalledMockCopy,
				      let binding = (bindingsOfFormsRead + Set(callerDeclaration.bindings.values).sorted()).first(where: { formsRead.isSubset(of: CycleParameter.forms(providedBy: $0)) })
				else { continue }
				callersOwnLabels.labels.insert(label)
				callersOwnLabels.mockRootBindingByLabel[label] = binding
			} else if formsRead.allSatisfy({ callerDeclaration.bindings[$0]?.label == label }) {
				// The forms being built where the call is (`NearestDeclaration.formsBeingBuilt`) need no check: a fill that reads
				// one, such as an `Instantiator` whose tree makes the call, reads a label the called type receives, which its
				// mock builds itself after the place for a caller that passes `nil`, so the fill is rejected for a calling mock:
				// the place's payload does not carry the label (`requiresOtherCarrier`), and inside a `@Sendable` function the
				// mock's own declaration outside it is not handed in (`boundOutsideSendableFunction`). That is a known gate,
				// since production and the inline mock accept it, and lifting it decides how this fill reads an instantiator
				// being built.
				callersOwnLabels.labels.insert(label)
			}
		}
		return callersOwnLabels
	}

	/// The labels `callersOwnLabels(amongLabelsOf:carrying:at:reading:handedFrom:by:whereFillsReenterCall:)` finds are the
	/// caller's own values, and, for each whose nearest declaration is the caller's mock root's binding, the bound property
	/// the fill reads.
	struct CallersOwnLabels {
		var labels = Set<String>()
		/// The property the caller's mock root binds that provides every form of the label the fill reads, by label: the fill
		/// binds the label to the name the mock spells for it (`ScopeGenerator.FillPlaceBindings.rootBindingNames`).
		var mockRootBindingByLabel = [String: Property]()
	}

	/// The sites of the places a call whose builders `holeArguments` are fills.
	private static func filledSites(of holeArguments: [ConstructionScope.HoleArgument]) -> Set<SeamSignature.Hole.Site> {
		Set(holeArguments.compactMap { holeArgument in
			if case let .fill(hole, _, _) = holeArgument {
				hole.site
			} else {
				nil
			}
		})
	}

	/// What the call this scope makes passes each builder: the dispatcher that fills its enum, a closure that hands the enum
	/// up in a case of an enum of the seam or public mock whose tree makes the call, or the dispatcher handed that closure,
	/// which it passes each place it does not fill: a seam's caller fills every place an enum reaches or none, a public
	/// mock's caller each place it can. An internal mock takes each builder it passes up as a parameter, which the call
	/// passes as its leaf's dependency of the builder's label: an empty value here, or the parameter called with the scope.
	private mutating func builderCallArguments(fillNames: [String: String]) -> [ScopeGenerator.BuilderCallArgument] {
		guard let calledBuilders = scope.calledBuilders, !holeArguments.isEmpty else { return [] }
		let filledSites = calledBuilders.siteNumbers(of: Self.filledSites(of: holeArguments))
		// A seam's caller calls the initializer only generated code calls, under its prefixed labels; a public mock's
		// caller passes each builder by the leaf's argument of its label.
		let isPublicMockCall = scope.publicMockCall != nil
		return calledBuilders.builders.map { builder in
			let label = isPublicMockCall ? builder.label : builder.generatedOnlyArgumentLabel
			let enumKey = builder.enumKey
			// A public mock's caller reads only the sites on the builder's routes (`CalledBuilders.routesReachOnly(_:by:)`).
			let reachesFilledSite = calledBuilders.reaches(anyOf: filledSites, from: enumKey, onRoutesOf: isPublicMockCall ? enumKey : nil)
			// In a tree built to compute the signature, which generates nothing, the case is not settled yet.
			let route = seamHoles.routeCase(at: sitePath, innerKey: enumKey)
			/// The struct a public mock's caller passes up of the called mock's root level: the member of the caller's own struct for
			/// the call, or, as an internal mock, the struct of the builder the caller takes under the label it takes it by.
			let receivedLabel = scope.publicMockCall?.passedParameters.first { $0.builder?.enumKey == enumKey }?.dependency.property.label ?? builder.label
			let publicMockUpValue = route.map { $0.memberCall ?? "" } ?? ".init(\(ReservedName.noScopeArgumentLabel): \(receivedLabel))"
			guard reachesFilledSite else {
				// The call hands on what the call's own member of the seam's or public mock's struct returns.
				if let memberCall = route?.memberCall {
					return .init(label: label, value: memberCall, passedUpStruct: route?.passedUpStruct)
				}
				guard isPublicMockCall else {
					if enumKey.holeType.builtType.isOptional {
						return .init(label: label, value: ".init(\(ReservedName.noScopeArgumentLabel): \(ReservedName.nilBuilderSource))")
					}
					return .init(label: label, value: "")
				}
				// A public mock's caller that fills no place of the builder passes up the struct it is handed: the member of its own
				// struct for the call, or, as an internal mock, the struct of the builder it takes.
				// An override closure of the call is handed the builder an internal caller takes, as the called `mock()` takes it. A
				// public mock's body holds only the struct its caller built, from which no builder a person writes can be made.
				return .init(
					label: label,
					value: route == nil ? receivedLabel : publicMockUpValue,
					builderStruct: .init(rootDispatcherKey: nil, upValue: publicMockUpValue, carriedStructs: [:]),
					overrideHanding: route == nil ? .callersBuilder : .none,
				)
			}
			// A seam that takes a builder struct is handed the struct its root level's function returns, but where a case of the
			// seam whose tree makes the call carries the scope value the call hands its fills, whose dispatchers keep their enum
			// form to pass it on, or an enclosing call declares those dispatchers in that form, which this call reuses: it is
			// then handed a struct whose members hand the dispatcher the case. A public mock's caller declares level functions of
			// its own (`PublicMockLevelFunctions`).
			let returnsBuilderStruct = builder.takesBuilderStruct && !isPublicMockCall && !calledBuilders.builders.contains { calledBuilder in
				calledBuilder.enumKey.holeType == enumKey.holeType
					&& ((seamHoles.innerScope(at: sitePath, innerKey: calledBuilder.enumKey) != nil && !seamHoles.carriesStruct(at: sitePath, innerKey: calledBuilder.enumKey))
						|| enclosingFills[ScopeGenerator.FillDispatcher.key(of: calledBuilder.enumKey)] != nil)
			}
			let dispatcherKey = ScopeGenerator.FillDispatcher.key(of: enumKey, returnsBuilderStruct: returnsBuilderStruct)
			let dispatcher = fillNames[dispatcherKey] ?? ""
			// What the call refers to by name: the enclosing dispatcher, whatever expression passes it.
			let enclosingFill = enclosingFills[dispatcherKey] == nil ? nil : ScopeGenerator.BuilderCallArgument.EnclosingFill(key: dispatcherKey, name: dispatcher)
			guard !isPublicMockCall else {
				// A call inside a fill of an enclosing call of the same builder re-enters the enclosing call's root level function,
				// handing it, for each struct of a level it takes, what the member of the call's own case of that struct's level
				// returns, as a seam's call does, and each value it takes of the caller's scope, read of this call's own
				// (`enclosingLevelReentryArguments(ofDispatcherKeyed:)`).
				if let enclosingName = enclosingFills[dispatcherKey] {
					var arguments = (enclosingCarriedInnerScopes[dispatcherKey] ?? []).compactMap { carriedInnerScope in
						seamHoles.carriedStruct(at: sitePath, innerKey: enumKey, carrying: carriedInnerScope.type).map { "\(carriedInnerScope.upName.spelledAsArgumentLabel): \($0)" }
					}
					arguments += enclosingLevelReentryArguments(ofDispatcherKeyed: dispatcherKey)
					return .init(label: label, value: "\(enclosingName)(\(arguments.joined(separator: ", ")))", enclosingFill: .init(key: dispatcherKey, name: enclosingName), isSendable: enumKey.isSendable)
				}
				// A public mock's caller that fills some place of the builder fills every place its routes reach, so it passes the
				// call of the builder's root level function (`PublicMockLevelFunctions`). The root level function of a route to a place inside a fill is handed the struct the case of this mock's own struct
				// for the call returns, for each of its levels the fill is handed.
				var carriedStructs = [String: String]()
				for carriedInnerScope in dispatchersOfThisCall.first(where: { $0.key == dispatcherKey })?.carriedInnerScopes ?? [] {
					carriedStructs[carriedInnerScope.name] = seamHoles.carriedStruct(at: sitePath, innerKey: enumKey, innerScopeName: carriedInnerScope.name)
				}
				return .init(
					label: label,
					value: dispatcher,
					isSendable: enumKey.isSendable,
					builderStruct: .init(rootDispatcherKey: dispatcherKey, upValue: publicMockUpValue, carriedStructs: carriedStructs),
					overrideHanding: .fills,
				)
			}
			// A seam's caller fills every place the builder reaches. The root level's function of a route to a place inside a fill
			// is handed the struct the case of this seam's enum for the call returns. A call that re-enters an enclosing call's
			// level function hands it, for each struct it takes, what the member of the call's own case of that struct's level
			// returns.
			let upArgument = if let carriedInnerScopes = enclosingFill == nil ? nil : enclosingCarriedInnerScopes[dispatcherKey] {
				carriedInnerScopes.compactMap { carriedInnerScope in
					seamHoles.carriedStruct(at: sitePath, innerKey: enumKey, carrying: carriedInnerScope.type).map { "\(carriedInnerScope.upName.spelledAsArgumentLabel): \($0)" }
				}.joined(separator: ", ")
			} else {
				(dispatchersOfThisCall.first { $0.key == dispatcherKey }?.carriedInnerScopes ?? []).compactMap { carriedInnerScope in
					seamHoles.carriedStruct(at: sitePath, innerKey: enumKey, innerScopeName: carriedInnerScope.name).map { "\(carriedInnerScope.upName.spelledAsArgumentLabel): \($0)" }
				}.joined(separator: ", ")
			}
			return .init(label: label, value: "\(dispatcher)(\(upArgument))", enclosingFill: enclosingFill, isSendable: enumKey.isSendable)
		}
	}

	/// The values a call inside a fill hands the level function of the dispatcher keyed `key`, which an enclosing call
	/// declares, when it re-enters it: each value the function takes of the caller's scope, read of this call's own. A value
	/// the levels between the two calls bind is the one inline reads there, which the enclosing call's caller does not see.
	private mutating func enclosingLevelReentryArguments(ofDispatcherKeyed key: String) -> [String] {
		var arguments = [String]()
		for property in enclosingLevelReentries[key]?.parameters ?? [] {
			arguments.append(CallArgument(label: property.label, source: Self.callerArgument(reading: property, of: childNearestDeclarations, lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties, log: &log)).spelled)
		}
		return arguments
	}

	/// For a call of another module's public mock, the call of each level function an enclosing call declares that a case of
	/// one of this call's own level functions leads to, by the function's dispatcher's key: a builder the called mock holds
	/// of a type whose places the enclosing call fills (`.inner`). The case re-enters the enclosing function as a call of the
	/// same builder does, handing it what it takes of the caller's scope read of this call's own
	/// (`enclosingLevelReentryArguments(ofDispatcherKeyed:)`), and the struct of each level of the caller's it takes, which
	/// the member of the case of this call's own struct returns (`PublicMockLevelFunctions.Member.reentry`).
	private mutating func enclosingLevelCalls() -> [String: PublicMockLevelFunctions.EnclosingLevelCall] {
		var calls = [String: PublicMockLevelFunctions.EnclosingLevelCall]()
		for dispatcher in dispatchersOfThisCall {
			for dispatcherCase in dispatcher.cases {
				guard let target = dispatcherCase.target, calls[target.key] == nil, let enclosingName = enclosingFills[target.key] else { continue }
				calls[target.key] = .init(name: enclosingName, arguments: enclosingLevelReentryArguments(ofDispatcherKeyed: target.key))
			}
		}
		return calls
	}

	/// Creates the scope's generator once `childGenerators` holds a generator for each of `propertiesToGenerate`.
	mutating func scopeGenerator() -> ScopeGenerator {
		// Every fill this call passes is an enclosing call's or its own.
		let fillNames = holeArguments.isEmpty ? [:] : GenerationWork.taking(enclosingFillsOfThisCall, by: .gatheringFillsOfACall)
		// Both read the caller's declarations, which they log.
		let builderCallArguments = builderCallArguments(fillNames: fillNames)
		let enclosingLevelCalls = scope.publicMockCall == nil ? [:] : enclosingLevelCalls()
		if builtFillCount > 0, let observer = SeamFillSharing.observer {
			observer(SeamFillSharing.FillsOfCall(calledType: scope.instantiable.concreteInstantiable.asSource, builtFillCount: builtFillCount, placeStoodForCount: fillsStoodFor.count))
		}
		let builtGenerator = ScopeGenerator(
			instantiable: scope.instantiable,
			property: property,
			propertiesToGenerate: childGenerators,
			// A scope that closes a cycle creates no children.
			propertiesToDeclare: isPropertyCycle ? [] : scope.propertiesToDeclare,
			instantiatedDependenciesNotGenerated: isPropertyCycle ? [] : scope.instantiatedDependenciesNotGenerated,
			unavailableOptionalProperties: unavailableOptionalProperties,
			receivesPassedNil: receivesPassedNil,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			forwardedLazilyInstantiatedInstanceProperties: scope.forwardedLazilyInstantiatedInstanceProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			isPropertyCycle: isPropertyCycle,
			closedOnDeclaration: closedOnDeclaration,
			closesCycleOnFillPath: closesCycleOnFillPath,
			builtInlineSeamComment: scope.builtInlineSeamComment,
			isUnavailableDependency: scope.isUnavailableDependency,
			seamCall: scope.seamCall,
			publicMockCall: scope.publicMockCall,
			callPlaceRequiredAliasFulfillingProperties: scope.callPlaceRequiredAliasFulfillingProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			holeCallArguments: holeArguments.map { holeArgument in
				switch holeArgument {
				case let .fill(hole, _, _):
					// Inside a fill of the same site, the call passes that fill under the label the called seam takes it by.
					let fillKey = ScopeGenerator.fillKey(of: hole)
					return ScopeGenerator.HoleCallArgument(
						label: hole.builderLabel,
						value: fillNames[fillKey] ?? ScopeGenerator.fillFunctionName(of: hole),
						hole: hole,
						enclosingFillKey: enclosingFills[fillKey] == nil ? nil : fillKey,
					)
				case let .passUp(hole):
					// The seam whose tree makes the call takes the builder for the hole's site – its own, or one it passes up –
					// and passes it on.
					return ScopeGenerator.HoleCallArgument(
						label: hole.builderLabel,
						value: seamHoles.hole(taking: hole)?.internalName ?? hole.internalName,
						hole: hole,
					)
				}
			},
			builderCallArguments: builderCallArguments,
			fillDispatchers: dispatchersOfThisCall,
			// A public mock's call names a level that needs a second function apart from every name the call claimed.
			namesTakenByCall: scope.publicMockCall == nil ? [] : namesOfThisCall.taken,
			passedUpHoles: holeArguments.compactMap { holeArgument in
				switch holeArgument {
				case let .passUp(hole):
					hole
				case .fill:
					nil
				}
			},
			valuesBindings: seamHoles.valuesBindings(at: sitePath),
			holdsLoopPayloadsInBoxes: seamHoles.holdsLoopPayloadsInBoxes,
			memberCallsInsideFunction: seamHoles.memberCallsInsideFunction(at: sitePath),
			isBuiltByFill: fill != nil,
			fillReturnsWrapperBuilder: fill?.returnsWrapperBuilder ?? false,
			innerScopesCalledWithForwardedValue: fill.map { $0.returnsWrapperBuilder ? $0.innerScopeParameters.map(\.property.label) : [] } ?? [],
			constructsWithHandWrittenMock: buildsWithHandWrittenMocks
				&& scope.publicMockCall == nil
				&& scope.instantiable.mockInitializer != nil
				&& property.map { scope.instantiable.mockReturnTypeIsCompatible(withPropertyType: $0.typeDescription.asInstantiatedType) } ?? false,
			cycleParameters: passedCycleParameters,
			builtCycleParameters: ownCycleParameters,
			cycleParameterUnavailableProperties: cycleParameterUnavailableProperties,
			callSiteLazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties,
			reboundProperties: reboundProperties,
			previousPassReceivedBuilderLoops: previousPassGenerator?.receivedBuilderLoops,
			previousPassFillSendableWrapperReads: previousPassGenerator?.fillSendableWrapperReads ?? [:],
			previousPassFillLabelsReadOnlyAsPlaceField: previousPassGenerator?.fillLabelsReadOnlyAsPlaceField ?? [:],
			previousPassPublicMockLevelReentries: previousPassGenerator?.publicMockLevelReentries ?? [:],
			enclosingLevelCalls: enclosingLevelCalls,
			namesBoundBySeam: GenerationWork.taking(seamHoles.namesBoundBySeam, by: .joiningNamesBoundBySeam),
			placeHoldingProperties: placeHoldingPropertiesByType.map { $0[scope.instantiable.concreteInstantiable] ?? [] },
			fillsStoodFor: fillsStoodFor,
			previousPassBuildsFillOfEveryPlace: previousPassGenerator?.buildsFillOfEveryPlace ?? false,
			cycleClosingRedeclaredLabels: &cycleClosingRedeclaredLabels,
		)
		return if let fill {
			ScopeGenerator(
				fill: fill.hole,
				key: fill.key,
				functionName: fill.functionName,
				boundLabels: fill.boundLabels,
				fields: fill.fields,
				caseHoles: fill.caseHoles,
				emitsCode: fill.emitsCode,
				callerReads: Self.callerReads(of: fill, child: builtGenerator, labelsHandedToReenteredFunctions: labelsHandedToReenteredFunctions(by: builtGenerator), log: &log),
				returnsWrapperBuilder: fill.returnsWrapperBuilder,
				labelsHandedAsMemo: fill.labelsHandedAsMemo,
				plainMemoRoutesOfSendableWrapperReads: fill.plainMemoRoutesOfSendableWrapperReads,
				memoOriginsByLabel: fill.memoOriginsByLabel,
				carrierUse: fill.carrierUse,
				child: builtGenerator,
				cycleClosingRedeclaredLabels: &cycleClosingRedeclaredLabels,
			)
		} else {
			builtGenerator
		}
	}

	private let scope: ConstructionScope
	/// The scope this place builds.
	var builtScope: ConstructionScope {
		scope
	}

	private let property: Property?
	/// The property this place builds its scope as, with its ID, or `nil` for a root or a fill (`PlaceReadsObservation`).
	let builtProperty: (property: Property, id: PropertyID)?
	/// Whether this scope is in the tree of a fill a mock declares, whose types are built as the mock's tree built
	/// inline builds them: each with its hand-written mock where `mockReturnTypeIsCompatible` says the mock builds it.
	private let buildsWithHandWrittenMocks: Bool
	/// Whether the tree checks each erased instantiator against the type it builds (see `createScopeGenerator`).
	private let validatesForwardedProperties: Bool
	private let propertiesToGenerate: [ConstructionScope.PropertyToGenerate]
	/// The index in `propertiesToGenerate` of the next property to create a generator for.
	private var nextPropertyIndex = 0
	/// The declarations being built above this scope's children: those above it, then its own.
	private let childContextStack: ContextStack
	/// See `init(scope:property:contextStack:depth:fillPathStackCount:…)`.
	private let fillPathStackCount: Int
	/// See `init(scope:property:contextStack:depth:fillPathStackCount:fillCallDepth:…)`.
	private let fillCallDepth: Int?
	/// Whether this scope is built inside a fill, whose tree reads the fields of the place it fills.
	var isInsideFill: Bool {
		fillCallDepth != nil
	}

	/// The depth a read of the stack or of the cycle parameter contexts is logged at, given `answerDepth`, the depth of the
	/// scope that put the answer there, or `nil` for a miss. Outside a fill, a miss and the path of a seam whose hole is filled
	/// (-1) are the tree's. Inside a fill, the stack holds only the fill's path (`SeamSignature.Hole.fillPropertyStack`) and
	/// what the fill's own scopes push, and the contexts only what they set: the fill path comes from the hole the call fills,
	/// a function of the call's scope, which its construction memo key names, so a miss or a fill path entry is answered at the
	/// call's depth, inside any entry of the call's place, and is never asked of the context of another place the call is
	/// reused at, whose stack the fill does not read.
	private static func depth(ofAnswerAt answerDepth: Int?, insideFillOfCallAt fillCallDepth: Int?) -> Int {
		max(answerDepth ?? -1, fillCallDepth ?? -1)
	}

	/// See `ScopeGenerator.closesCycleOnFillPath`.
	private let closesCycleOnFillPath: Bool
	/// The received properties in scope only as the instance of a `LazilyInstantiated` property, where this scope's type
	/// is constructed: inside its builder function, whose parameters a lazy cycle closes on hide every other declaration
	/// of their labels.
	private let lazilyInstantiatedInstanceProperties: Set<Property>
	/// `lazilyInstantiatedInstanceProperties` where this scope's builder function is called, which its parameters do
	/// not hide.
	private let callSiteLazilyInstantiatedInstanceProperties: Set<Property>
	private let childLazilyInstantiatedInstanceProperties: Set<Property>
	private let unavailableOptionalProperties: Set<Property>
	/// Those of `unavailableOptionalProperties` that a mock passes `nil` though its root binds a form they read, which
	/// therefore receive nothing from above this scope. Empty outside a mock's tree.
	private let receivesPassedNil: Set<Property>
	/// The generator the pass before created for this scope, or `nil` in the first pass (see `createScopeGenerator`).
	private let previousPassGenerator: ScopeGenerator?
	/// The properties of each type in the tree that hold a place, by which each scope's children start
	/// (`ScopeGenerator.startsAsCarrier(_:)`), or `nil` where they start by what their subtrees hold on the scope's path,
	/// in a pass whose order by path is the same. A fill's tree, whose places are places of the type the fill builds, starts
	/// its children by the same properties.
	private let placeHoldingPropertiesByType: [TypeDescription: Set<Property>]?
	/// The parameters of this scope's builder function that the pass before found: those a lazy cycle closing on it
	/// needs. Empty for nearly every scope.
	private let ownCycleParameters: [CycleParameter]
	/// The settled cycle parameters of this place and the places beneath it, which this place reads in place of what
	/// `previousPassGenerator` found (see `CycleParameterPlan`), or `nil`.
	private let cycleParameterSeed: CycleParameterSeed?
	/// The parameters this scope passes a builder function a lazy cycle closes on: its own, or, for a cycle-closing
	/// scope, those of the function it refers to.
	private let passedCycleParameters: [CycleParameter]
	/// Those of `passedCycleParameters` that are unavailable where this scope passes them, which it passes `nil`.
	private let cycleParameterUnavailableProperties: Set<Property>
	/// For each function enclosing the scopes this scope builds that a lazy cycle closes on, by the declaration it builds,
	/// its parameters (see `CycleParameterContext`).
	private let childCycleParameterContexts: [ScopeGenerator.BuiltDeclaration: CycleParameterContext]
	/// The nearest declaration of each label, as the scopes this scope builds see it before they are built: those
	/// enclosing this scope, with this scope's own declarations in place of every other of their labels.
	private let childNearestDeclarations: NearestDeclarations
	/// At a mock root whose places a required receive above may pin, `childNearestDeclarations` without the mocked type's
	/// own required receives, which the trees of the dependencies the root promotes see; `nil` elsewhere.
	private let promotedChildNearestDeclarations: NearestDeclarations?
	/// The properties this scope's builder function rebinds as a member of a loop of builders (see
	/// `ScopeGenerator.ReceivedBuilderLoops`), which the pass before found.
	private let reboundProperties: Set<Property>
	/// The declared property each `onlyIfAvailable` alias this scope declares is bound from, where its fulfilling property
	/// is available. An alias absent here is bound to `nil`.
	private let aliasBindings: [Property: Property]
	private let seamRoot: ScopeGenerator.SeamRoot?
	/// For a public mock's root, the builders its `mock()` takes; `nil` for every other scope.
	private let mockBuilders: DependencyTreeGenerator.ShapedBuilders?
	/// The holes of the seam whose tree is generated, by site, which the sites and the payloads bound on the routes to them
	/// read. Empty outside a seam's tree, and in a seam's tree without holes.
	private let seamHoles: SeamHoles
	/// The names the modules SafeDI read declare types by at file scope, which
	/// `ErasedInstantiatorForwardedPropertiesMismatchError` reads.
	private let declaredTypeNames: DeclaredTypeNames
	/// The properties from the root of the tree down to this scope's, when `seamHoles` is not empty; otherwise empty.
	private let sitePath: [Property]
	/// For a scope a fill builds the property of, the fill's hole, its key (see `ScopeGenerator.fillKey(of:)`), and the
	/// name of its function; `nil` for every other scope.
	private let fill: Fill?
	/// How the seam call this scope makes passes each builder (see `Scope.holeArguments`).
	private let holeArguments: [ConstructionScope.HoleArgument]
	/// The fills of `holeArguments` this scope's generator holds – those no enclosing call already fills – each with the
	/// scope of the type that fulfills its hole.
	private let fillsOfThisCall: [(fill: Fill, scope: ConstructionScope, context: ScopeRecord.FillContext)]
	/// The dispatchers this scope's seam call declares – those no enclosing call declares – in the order the call's arguments
	/// first reach them.
	private let dispatchersOfThisCall: [ScopeGenerator.FillDispatcher]
	/// The names the call's fills and dispatchers took, and those they are apart from, which the functions of a builder
	/// struct's levels the call converts through are named apart from too.
	private let namesOfThisCall: GeneratedNameAllocator
	/// The fills enclosing this scope, by `ScopeGenerator.fillKey(of:)`, each with its function's name, which a call
	/// inside them of a seam that holds or passes up their site passes by name.
	private let enclosingFills: [String: String]
	/// The function names of `enclosingFills`, which this scope's seam call names its fills and dispatchers apart from.
	private let enclosingFillNames: GenerationWork.Shared<Set<String>>
	/// The fills inside one of this scope's fills can refer to: those of enclosing calls, and every fill and dispatcher of
	/// this call, shared by each of its fills.
	private let enclosingFillsOfThisCall: GenerationWork.Shared<[String: String]>
	/// The function names of `enclosingFillsOfThisCall`, shared by each of this call's fills.
	private let enclosingFillNamesOfThisCall: GenerationWork.Shared<Set<String>>
	/// The structs each level function of `enclosingFills` takes from its caller (`FillDispatcher.carriedInnerScopes`), by its
	/// key: a call that re-enters it hands it each from a member of its own case (`SeamHoles.carriedStruct`).
	private let enclosingCarriedInnerScopes: [String: [ScopeGenerator.FillDispatcher.CarriedInnerScope]]
	/// The structs the level functions a fill of this call can refer to take: those of enclosing calls, and this call's, by
	/// the level function's key, gathered once for the call.
	private let enclosingCarriedInnerScopesOfThisCall: [String: [ScopeGenerator.FillDispatcher.CarriedInnerScope]]
	/// What each level function of `enclosingFills` of a public mock's call takes of the caller's scope
	/// (`PublicMockLevelFunctions.levelReentries(amongKeys:)`), by its key: a call that re-enters it hands it each value
	/// read of this call's own scope, and a call that re-enters one it does not hold hands none.
	private let enclosingLevelReentries: [String: PublicMockLevelFunctions.Reentry]
	/// What a call inside a fill of this call that re-enters a level function hands it beside the structs of the caller's
	/// levels: those of enclosing calls, and this call's, by the level function's key, gathered once for the call.
	private let enclosingLevelReentriesOfThisCall: [String: PublicMockLevelFunctions.Reentry]
	/// The index in `fillsOfThisCall` of the next fill to create a generator for.
	private var nextFillIndex = 0
	private let erasedToConcreteExistential: Bool
	private let isPropertyCycle: Bool
	/// The declaration this scope repeats when it closes a cycle (see `ScopeGenerator.closedOnDeclaration`), or `nil`.
	private let closedOnDeclaration: ScopeGenerator.BuiltDeclaration?
	private let forMockGeneration: Bool
}

extension Instantiable {
	/// The properties the type is forwarded. A lazily instantiated one is followed by the property that
	/// receives its instance by value.
	var forwardedReceivableProperties: Set<Property> {
		Set(
			dependencies
				.filter { $0.source == .forwarded }
				.flatMap(\.receivableProperties),
		)
	}
}

// MARK: - ScopeGeneratorLimit

/// Thrown where a tree's passes have built or reused more places than the limit its caller gave it and the caller
/// abandons the tree. Never reported: the caller that gave the limit catches it and builds the root another way.
struct ScopeGeneratorLimitExceeded: Error {}

/// How many places a tree's passes may build or reuse between them before its caller is asked what to do with it.
/// A place is a property a scope of the tree instantiates, counted where its generator is built or reused from the
/// construction memo: the count reads the declarations alone, never a name.
struct ScopeGeneratorLimit {
	/// What the caller answers once the tree holds more than `places` places.
	enum Answer {
		/// The tree is abandoned (`ScopeGeneratorLimitExceeded`).
		case abandonsTree
		/// The tree is built on with no limit, and nothing built so far is thrown away.
		case keepsTree
		/// The tree is built on, and the caller is asked again once it holds more than this many places.
		case asksAgain(pastPlaces: Int)
	}

	let places: Int
	/// The caller's answer for a tree that has passed `places`, which it is handed.
	let answer: (_ places: Int) -> Answer
}

// MARK: - ErasedInstantiatorForwardedPropertiesMismatchError

/// An `@Instantiated` `ErasedInstantiator` or `SendableErasedInstantiator` whose first generic argument is not the
/// `@Forwarded` properties of the type it builds. Reported at the property's declaration.
struct ErasedInstantiatorForwardedPropertiesMismatchError: SourceLocatedError {
	/// The error for `property`, declared on `parent` at `declarationLocation` to build `builtInstantiable`, or
	/// `nil` when `property` is not an erased instantiator or its first generic argument matches.
	init?(
		property: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		parent: TypeDescription,
		builtInstantiable: Instantiable,
		declaringModuleNames: [String],
		declaredTypeNames: DeclaredTypeNames,
	) {
		guard !property.firstGenericMatchesForwardedProperties(of: builtInstantiable, declaringModuleNames: declaringModuleNames, declaredTypeNames: declaredTypeNames) else { return nil }
		self.property = property
		self.declarationLocation = declarationLocation
		self.parent = parent
		builtType = builtInstantiable.concreteInstantiable
		// The forwarded properties are spelled out rather than as `ForwardedProperties` on the built type, which the
		// module that declares the property may not be able to see.
		forwardedPropertiesType = builtInstantiable.forwardedProperties.asForwardedPropertiesTypeDescription
	}

	var sourceDiagnostics: [SourceDiagnostic] {
		[
			SourceDiagnostic(
				severity: .error,
				location: declarationLocation,
				message: "The first generic argument of `\(property.asSource)` on `\(parent.asSource)` must be the @\(Dependency.Source.forwardedRawValue) properties of `\(builtType.asSource)`, which it builds. Declare it as `\(property.propertyType.isSendable ? Dependency.sendableErasedInstantiatorType : Dependency.erasedInstantiatorType)<\(forwardedPropertiesType.asSource), \(property.typeDescription.asInstantiatedType.asSource)>`.",
			),
		]
	}

	private let property: Property
	private let declarationLocation: Dependency.DeclarationLocation?
	private let parent: TypeDescription
	private let builtType: TypeDescription
	private let forwardedPropertiesType: TypeDescription
}

extension Property {
	/// Whether the property, when it is an `ErasedInstantiator` or `SendableErasedInstantiator` that builds
	/// `builtInstantiable`, has the `@Forwarded` properties of `builtInstantiable` as its first generic argument.
	/// Any other property matches, as does one that builds a type with no `@Forwarded` properties. The comparison sees
	/// through what a declaration's spelling alone shows to be the same type
	/// (`TypeDescription.withoutSpellingDifferences(qualifiedByModulesNamed:orDeclaringModulesNamed:declaredTypeNames:)`), since the generated code
	/// reads the elements by label; it does not resolve a typealias, so a spelling only the compiler can see through is
	/// rejected, with an error that names a spelling it accepts. Whether a mock builds a received property that matches is
	/// narrower: see `mockBuildsFirstGeneric(of:)`.
	/// - Parameter declaringModuleNames: The modules, beside `Swift` and the built type's, whose name it sees through as a
	///   qualifier of either spelling, of a type no other module declares a type of the name of.
	func firstGenericMatchesForwardedProperties(of builtInstantiable: Instantiable, declaringModuleNames: [String], declaredTypeNames: DeclaredTypeNames) -> Bool {
		// Most properties are no erased instantiator, so the built type's forwarded properties are listed only for one.
		guard propertyType.isErasedInstantiator,
		      let forwardedArgument = generics?.first
		else { return true }
		let forwardedProperties = builtInstantiable.forwardedProperties
		guard !forwardedProperties.isEmpty else { return true }
		let modulesNames = ["Swift"] + (builtInstantiable.moduleName.map { [$0] } ?? [])
		// The forwarded argument is the same as `InstantiableName.ForwardedProperties`, or names the `ForwardedProperties` of a
		// type the fulfiller also fulfills: that type's conformance is trusted, as at an `Instantiator` of it. A mock does not
		// share this (`mockBuildsFirstGeneric(of:)`).
		return builtInstantiable.instantiableTypes.contains { forwardedArgument == .nested(name: Dependency.forwardedPropertiesType, parentType: $0) }
			// The forwarded argument is the same as the type the macro generates for `InstantiableName.ForwardedProperties`:
			// the type of the only `@Forwarded` property, or the tuple of all of them.
			|| forwardedArgument.withoutSpellingDifferences(qualifiedByModulesNamed: modulesNames, orDeclaringModulesNamed: declaringModuleNames, declaredTypeNames: declaredTypeNames)
			== forwardedProperties.asForwardedPropertiesTypeDescription.withoutSpellingDifferences(qualifiedByModulesNamed: modulesNames, orDeclaringModulesNamed: declaringModuleNames, declaredTypeNames: declaredTypeNames)
	}

	/// Whether a mock that receives the property can build it, for an `ErasedInstantiator` or
	/// `SendableErasedInstantiator` that builds `builtInstantiable`: its first generic argument names
	/// `InstantiableName.ForwardedProperties`, or is the type of the only `@Forwarded` property, or a tuple of the
	/// `@Forwarded` properties whose every element's type is one bare name. Any other property can be built, as can one
	/// that builds a type with no `@Forwarded` properties.
	///
	/// A deliberate gap beside `firstGenericMatchesForwardedProperties(of:)`, which also accepts a tuple whose elements
	/// are not one bare name, and `X.ForwardedProperties` for any other type `X` the fulfiller fulfills: a mock takes a
	/// received property of either as a `mock()` parameter, as it did when SafeDI rejected a declaration of it. Building it would remove the parameter that callers of the mock pass,
	/// and bring the built type's tree into the mock, whose cycles, hidden labels, and access no tree had to pass.
	func mockBuildsFirstGeneric(of builtInstantiable: Instantiable) -> Bool {
		// Most properties are no erased instantiator, so the built type's forwarded properties are listed only for one.
		guard propertyType.isErasedInstantiator,
		      let forwardedArgument = generics?.first
		else { return true }
		let forwardedProperties = builtInstantiable.forwardedProperties
		guard !forwardedProperties.isEmpty else { return true }
		return forwardedArgument == .nested(name: "ForwardedProperties", parentType: builtInstantiable.concreteInstantiable)
			|| (forwardedProperties.count == 1 && forwardedArgument == forwardedProperties[0].typeDescription)
			|| forwardedArgument == forwardedProperties.asTupleTypeDescriptionOfBareElements
	}
}

extension Instantiable {
	/// The type's `@Forwarded` properties, in declaration order.
	fileprivate var forwardedProperties: [Property] {
		dependencies
			.filter { $0.source == .forwarded }
			.map(\.property)
	}
}

// MARK: - SeamHoles

/// The holes of a seam's signature, as the generators of the seam's tree look them up: each site by its path, each
/// hole the seam passes up by the inner seam's hole it passes, and the payloads the tree binds before building each property
/// of a route to a place nested by type, by the property's path.
struct SeamHoles: Sendable {
	/// No holes: a tree that is not a seam's, or a seam's tree without holes.
	init() {
		seamType = nil
		routeCasesByCall = [:]
		sitesByPath = [:]
		passedUpHolesBySite = [:]
		valuesBindingsByPath = [:]
		memberCallsInsideFunctionByPath = [:]
		innerScopesByCall = [:]
		carriedStructsByCall = [:]
		namesBoundForBuilders = []
		namesBoundForDeferredParameters = []
		holdsLoopPayloadsInBoxes = false
		namesBoundBySeam = GenerationWork.Shared([])
		carrierValues = SeamCarrierValues()
		carrierSitesByPath = [:]
	}

	/// How each carrier level's members take its values, and the runs the tree forms.
	let carrierValues: SeamCarrierValues
	/// For each site whose case is a carrier's, how its member takes its values, and the runs the tree forms just before it
	/// where no payload binding at its path forms them.
	private let carrierSitesByPath: [[Property]: CarrierSite]

	/// How a place's member of a carrier takes its values (`SeamCarrierValues`), and the runs formed at its path.
	struct CarrierSite: Sendable {
		let use: SeamCarrierValues.Use
		var formations: [ValuesBinding]
	}

	/// How the place at `sitePath` takes its values, where its case is a carrier's.
	func carrierSite(at sitePath: [Property]) -> CarrierSite? {
		carrierSitesByPath.isEmpty ? nil : carrierSitesByPath[sitePath]
	}

	init(seamType: TypeDescription, holes: [SeamSignature.Hole], builders: [SeamSignature.Builder], parameters: [SeamSignature.Parameter] = [], callRoutes: [SeamSignature.CallRoute] = [], scopeEnums: [SeamSignature.ScopeEnum] = [], holdsLoopPayloadsInBoxes: Bool = false) {
		self.holdsLoopPayloadsInBoxes = holdsLoopPayloadsInBoxes
		var routeCasesByCall = [RouteCall: RouteCase]()
		let builderByEnum = Dictionary(builders.map { ($0.enumKey, $0) }, uniquingKeysWith: { first, _ in first })
		// The payload of each case that wraps another on the way to a place or a call nested by type, bound just before the
		// case's property is built, once however many places it leads to. A case of a `@Sendable` enum carries none. A call's
		// case for a builder it fills carries the scope value the inner seam handed the fill, which the fill takes.
		var valuesBindingsByName = [[Property]: [String: ValuesBinding]]()
		var innerScopesByCall = [RouteCall: [SeamSignature.Hole.RouteStep.InnerScope]]()
		var carriedStructsByCall = [RouteCall: [String: String]]()
		// The seam's own enums, signatures settled and their cases marked `indirect`, which decide whether a member on a
		// route, or a call's own member, is a carrier's `let` child: a level in a loop through other seams' carriers is
		// `indirect`, which only the settled enums of every seam of the module say.
		var scopeEnumByType = [TypeDescription: SeamSignature.ScopeEnum]()
		for scopeEnum in scopeEnums where scopeEnum.key.seamType == seamType {
			let type = SeamSignature.ScopeEnum.nestedType(named: scopeEnum.typeName, in: scopeEnum.rootTypeName)
			if scopeEnumByType[type] == nil {
				scopeEnumByType[type] = scopeEnum
			}
		}
		// Whether the member of the case `caseName`, handed `memberValuesType`, nested in the case's enum, is a carrier's
		// `let` child, read, not called.
		func isLetChild(ofCaseNamed caseName: String, handed memberValuesType: TypeDescription) -> Bool {
			guard case let .nested(_, enumType, _) = memberValuesType, ReservedName.seamCarrier(ofEnum: enumType) != nil, let scopeEnum = scopeEnumByType[enumType] else { return false }
			return scopeEnum.cases.first { $0.name == caseName }?.isLetChildOfCarrier(inSendableEnum: scopeEnum.key.isSendable) ?? false
		}
		// Where the enums declare builder structs, each case on a route is a member call on the struct the step before it
		// returned, the root's builder's for the first, bound before the step's property, or at the top of its builder
		// function (`RouteStep.Member`). A route's steps lead to one place, so each step's parent is a fact of its path.
		func bindValues(of route: [SeamSignature.Hole.RouteStep], onRouteTo sitePath: [Property], rootBuilderName: String) {
			var parentName = rootBuilderName
			for step in route {
				// Each scope value the call hands, once: a seam's struct of the fill's own level per hole type and family whose places
				// the fill holds, or a public mock's one inner scope.
				let routeCall = step.innerScope.map { RouteCall(sitePath: $0.callPath(onRouteTo: sitePath), innerKey: $0.innerKey) }
				if let innerScope = step.innerScope, let routeCall, !innerScopesByCall[routeCall, default: []].contains(where: { $0.name == innerScope.name }) {
					innerScopesByCall[routeCall, default: []].append(innerScope)
				}
				if let member = step.member {
					valuesBindingsByName[member.bindingPath(onRouteTo: sitePath), default: [:]][member.bindingName] = ValuesBinding(member: member, parentName: parentName, caseName: step.caseName, isLetChild: isLetChild(ofCaseNamed: step.caseName, handed: member.valuesType))
					parentName = member.bindingName
					// A call's case for a builder it fills returns the called seam's struct, which the call's level functions are
					// handed; inside the fill, the struct of the fill's own level, which the fill is handed, leads on.
					if let innerScope = step.innerScope, let routeCall {
						carriedStructsByCall[routeCall, default: [:]][innerScope.name] = member.bindingName
						parentName = innerScope.name
					}
				}
			}
		}
		for callRoute in callRoutes {
			guard let builder = builderByEnum[callRoute.rootKey] else { continue }
			let builderName = builder.internalName
			bindValues(of: callRoute.route, onRouteTo: callRoute.sitePath, rootBuilderName: builderName)
			// A call that re-enters an enclosing call's fill hands up nothing: it passes the enclosing call's level function the
			// struct its last case's member returns (`carriedStruct(at:innerKey:carrying:)`).
			guard !callRoute.reentersEnclosingFill else { continue }
			// The call's own case holds only the inner enum: no value of the calling type, so nothing it binds is captured by the
			// builder the called type holds.
			// Where the call's enum declares a builder struct, the call's own member returns the inner seam's struct, called on
			// the struct the last case on its route returned, or on the builder itself: inside a fill whose call's case leads on,
			// the struct of the fill's own level, which the fill is handed, as `bindValues` leads on from it.
			// A fulfilling call is handed the struct of the fill's own level: the inner scope its fill is handed, or, where its fill is
			// built in a `@Sendable` function, whose case carries no inner scope, what the case's member returns.
			// The struct the call's own member is called on, typed where the seam's tree binds it: the builder, or the level the
			// route's last member returns. The struct of a fill's own level, which the fill is handed, is typed by no binding.
			let parentStep = callRoute.route.last
			let memberParent: ScopeGenerator.BuilderCallArgument.PassedUpStruct? = if parentStep?.innerScope != nil {
				nil
			} else if let member = parentStep?.member {
				.init(name: member.bindingName, type: member.levelType)
			} else {
				.init(name: builderName, type: builder.parameterType)
			}
			let memberCall = if callRoute.handsFillLevelStruct {
				callRoute.route.last.flatMap { $0.innerScope?.name ?? $0.member?.bindingName }
			} else {
				callRoute.memberValuesType.map { memberValuesType in
					let parentName = callRoute.route.last.flatMap { $0.innerScope?.name ?? $0.member?.bindingName } ?? builderName
					if case let .nested(_, enumType, _) = memberValuesType, ReservedName.seamCarrier(ofEnum: enumType) != nil {
						// A carrier's member for a call's own case takes no values: a `let` child is read, any other member called.
						return isLetChild(ofCaseNamed: callRoute.caseName, handed: memberValuesType) ? "\(parentName).\(callRoute.caseName)" : "\(parentName).\(callRoute.caseName)()"
					} else {
						return "\(parentName).\(callRoute.caseName)(\(memberValuesType.asSource)())"
					}
				}
			}
			routeCasesByCall[RouteCall(sitePath: callRoute.sitePath, innerKey: callRoute.innerKey)] = RouteCase(
				memberCall: memberCall,
				passedUpStruct: callRoute.handsFillLevelStruct || memberCall == nil ? nil : memberParent,
			)
		}
		self.routeCasesByCall = routeCasesByCall
		var sitesByPath = [[Property]: SeamSignature.Hole]()
		var passedUpHolesBySite = [SeamSignature.Hole.Site: SeamSignature.Hole]()
		var namesBoundForBuilders = Set(holes.map(\.internalName) + holes.compactMap(\.wrapperFunctionName) + builders.map(\.internalName))
		for hole in holes {
			guard hole.innerSeamType == nil else {
				passedUpHolesBySite[hole.site] = hole
				continue
			}
			sitesByPath[hole.sitePath] = hole
			if let enumPlace = hole.enumPlace {
				bindValues(of: enumPlace.route, onRouteTo: hole.sitePath, rootBuilderName: hole.internalName)
			}
		}
		namesBoundForBuilders.formUnion(innerScopesByCall.values.flatMap { $0.map(\.name) })
		// Each carrier level's runs (`SeamCarrierValues`): every member and place takes the struct of the run its values
		// end, which the tree binds once in the body that binds the level, at the first path in it that takes the run or a
		// later one, read as the path whose case takes the fewest values; a level's cases bind a prefix of one sequence, in
		// the order the body builds them.
		let carrierValues = SeamCarrierValues(scopeEnums: scopeEnums, ofSeam: seamType)
		var carrierSitesByPath = [[Property]: CarrierSite]()
		var formationsByPath = [[Property]: [ValuesBinding]]()
		if !carrierValues.isEmpty {
			struct Taker {
				let path: [Property]
				let fields: [SeamSignature.Hole.Field]
			}
			struct Body: Hashable {
				let path: [Property]
				let level: String
			}
			var takersByBody = [Body: [Taker]]()
			for (path, bindings) in valuesBindingsByName {
				for name in bindings.keys {
					guard let binding = bindings[name], !binding.isLetChild, !binding.isCalledInsideFunction, case let .nested(_, enumType, _) = binding.type, let level = SeamCarrierValues.level(ofEnum: enumType), !binding.fields.isEmpty else { continue }
					valuesBindingsByName[path]?[name]?.carrierUse = carrierValues.use(ofLevel: level, count: binding.fields.count)
					takersByBody[Body(path: Array(path.dropLast()), level: level), default: []].append(Taker(path: path, fields: binding.fields))
				}
			}
			for (path, hole) in sitesByPath {
				guard hole.scopeSeamType == seamType, let enumPlace = hole.enumPlace, let level = SeamCarrierValues.level(ofEnum: enumPlace.enumType(qualifiedBy: nil)) else { continue }
				let fields = enumPlace.values
				guard !fields.isEmpty else { continue }
				carrierSitesByPath[path] = CarrierSite(use: carrierValues.use(ofLevel: level, count: fields.count), formations: [])
				takersByBody[Body(path: Array(path.dropLast()), level: level), default: []].append(Taker(path: path, fields: fields))
			}
			for (body, takers) in takersByBody {
				// The takers in the order the body builds them, the path naming the property as a tie-break, which no shape a
				// level's prefixes allow reaches: two paths of one body bind a different number of values.
				let ordered = takers.sorted { ($0.fields.count, $0.path.map(\.asSource).joined(separator: ".")) < ($1.fields.count, $1.path.map(\.asSource).joined(separator: ".")) }
				var previousEnd: Int?
				for end in carrierValues.ends(ofLevel: body.level) {
					guard let taker = ordered.first(where: { $0.fields.count >= end }) else { break }
					let previousName = previousEnd.map { SeamCarrierValues.bindingName(ofLevel: body.level, end: $0) }
					formationsByPath[taker.path, default: []].append(ValuesBinding(formingRunOf: body.level, end: end, fields: Array(taker.fields[(previousEnd ?? 0)..<end]), previousName: previousName))
					previousEnd = end
				}
			}
			for (path, formations) in formationsByPath where carrierSitesByPath[path] != nil && valuesBindingsByName[path] == nil {
				carrierSitesByPath[path]?.formations = formations
			}
		}
		self.carrierValues = carrierValues
		self.carrierSitesByPath = carrierSitesByPath
		self.innerScopesByCall = innerScopesByCall
		self.carriedStructsByCall = carriedStructsByCall
		// Each path's payloads are bound in the order of their names: none is read by another bound at the same path.
		var valuesBindingsByPath = [[Property]: [ValuesBinding]]()
		var memberCallsInsideFunctionByPath = [[Property]: [ValuesBinding]]()
		for (path, bindings) in valuesBindingsByName {
			namesBoundForBuilders.formUnion(bindings.keys)
			let orderedBindings = bindings.sorted { $0.key < $1.key }.map(\.value)
			let insideFunction = orderedBindings.filter(\.isCalledInsideFunction)
			if !insideFunction.isEmpty {
				memberCallsInsideFunctionByPath[path] = insideFunction
			}
			valuesBindingsByPath[path] = (formationsByPath[path] ?? []) + orderedBindings.filter { !$0.isCalledInsideFunction }
		}
		self.memberCallsInsideFunctionByPath = memberCallsInsideFunctionByPath
		self.seamType = seamType
		self.sitesByPath = sitesByPath
		self.passedUpHolesBySite = passedUpHolesBySite
		self.valuesBindingsByPath = valuesBindingsByPath
		self.namesBoundForBuilders = namesBoundForBuilders
		namesBoundForDeferredParameters = Set(parameters.filter(\.isDeferred).map(\.internalName))
		namesBoundBySeam = GenerationWork.Shared(namesBoundForBuilders.union(namesBoundForDeferredParameters))
		GenerationWork.record(namesBoundForBuilders.count + namesBoundForDeferredParameters.count, by: .joiningNamesBoundBySeam)
	}

	/// The arguments of a payload struct's initializer that the seam's tree calls with `fields`, each read as the tree's
	/// receivers read its label where the struct is built: by the label, or, where `lazilyInstantiatedInstanceProperties`
	/// holds the field's by-value property, by the instance of the `LazilyInstantiated` the label names there. That is a
	/// level's parameter of a builder function a lazy cycle closes on, in a build whose function does not take it, which
	/// reads the seam's deferred parameter or a lazily instantiated declaration of the label. A deferred parameter's own
	/// field takes the `LazilyInstantiated` itself. A label in `bindingNamesPassedByName` is read under the name it maps to:
	/// a public mock passes a type that name rather than binding it again under the label inside the type's builder
	/// function, where a payload of the type's level is built (`ScopeGenerator.valuesBindingsBeforeBuilderFunction`). A field of a
	/// `LazilyInstantiated` a public mock binds under a name apart, beside the instance it takes under the label, is read
	/// under the name `lazilyInstantiatedBindingNames` gives it by label and wrapper type where the wrapper is in scope: the
	/// mock's root level holds the wrapper (`DependencyTreeGenerator.PublicMockRootLevel`).
	static func valuesArguments(
		of fields: [SeamSignature.Hole.Field],
		readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property> = [],
		bindingNamesPassedByName: [String: String] = [:],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:],
		labeled: Bool = true,
	) -> String {
		fields.map { field in
			let label = field.property.label
			let name = bindingNamesPassedByName[label] ?? lazilyInstantiatedBindingNames[label]?[field.property.typeDescription] ?? label
			let value = if !field.isDeferredParameter, lazilyInstantiatedInstanceProperties.contains(field.property.asUnwrappedProperty) {
				"\(name).\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else {
				name
			}
			return labeled ? "\(label.spelledAsArgumentLabel): \(value)" : value
		}.joined(separator: ", ")
	}

	/// The arguments a member of a seam's carrier is called with for `fields`, its case's values: the struct of the run
	/// they end, as the seam's tree binds it, then each value after it, read as `valuesArguments` reads it.
	static func carrierArguments(
		of fields: [SeamSignature.Hole.Field],
		use: SeamCarrierValues.Use?,
		readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>,
		bindingNamesPassedByName: [String: String] = [:],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:],
	) -> String {
		var arguments = use?.structBindingName.map { [$0] } ?? []
		let extras = valuesArguments(of: Array(fields[use?.extras ?? 0..<fields.count]), readingInstancesOf: lazilyInstantiatedInstanceProperties, bindingNamesPassedByName: bindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames, labeled: false)
		if !extras.isEmpty {
			arguments.append(extras)
		}
		return arguments.joined(separator: ", ")
	}

	/// The name under which a member of a seam's carrier, or a fill it calls, takes `field` of a level's values, which a
	/// builder struct's member took as the payload named `payloadName`: the payload's name joined with the field's label.
	static func argumentName(of field: SeamSignature.Hole.Field, inPayloadNamed payloadName: String) -> String {
		"\(payloadName)_\(field.property.label)".spelledAsJoinedIdentifier
	}

	/// What reads `field` from the arguments `argumentName(of:inPayloadNamed:)` names, as `<payload>.<field>` read it from a
	/// payload struct: a deferred parameter's field is handed as its memo, whose instance is the value.
	static func argumentRead(of field: SeamSignature.Hole.Field, inPayloadNamed payloadName: String, bindingMemo: Bool) -> String {
		let name = argumentName(of: field, inPayloadNamed: payloadName)
		return field.isDeferredParameter && !bindingMemo ? "\(name).\(Dependency.lazilyInstantiatedInstancePropertyName)" : name
	}

	/// The struct the member of a case returns, which the seam's tree binds just before the builder function of a property
	/// on a route to a place nested by type, called on the struct `memberCall`'s parent name is bound to, with the case's
	/// payload: its binding's name, the payload struct's type and its fields.
	struct ValuesBinding: Sendable {
		init(member: SeamSignature.Hole.RouteStep.Member, parentName: String, caseName: String, isLetChild: Bool) {
			bindingName = member.bindingName
			type = member.valuesType
			boundType = member.levelType
			fields = member.fields
			memberCall = (parentName, caseName)
			isCalledInsideFunction = member.isCalledInsideFunction
			self.isLetChild = isLetChild
			carrierUse = nil
			formsRunAfter = nil
		}

		/// The binding of the struct of a run of a carrier level's values (`SeamCarrierValues`): `fields`, the run's own,
		/// after the struct of the run before it, bound as `previousName`.
		init(formingRunOf level: String, end: Int, fields: [SeamSignature.Hole.Field], previousName: String?) {
			bindingName = SeamCarrierValues.bindingName(ofLevel: level, end: end)
			type = SeamCarrierValues.structType(ofLevel: level, end: end, qualifiedBy: nil)
			boundType = type
			self.fields = fields
			memberCall = ("", "")
			isCalledInsideFunction = false
			isLetChild = false
			carrierUse = nil
			formsRunAfter = .some(previousName)
		}

		/// How the member takes its values, where its enum is a carrier's that hands them through run structs.
		var carrierUse: SeamCarrierValues.Use?
		/// For the binding of a run's struct, the binding of the run before it (`nil` inside for the first run); `nil` for a
		/// member's binding.
		let formsRunAfter: String??

		let bindingName: String
		let type: TypeDescription
		/// The type of the value the binding binds, as the seam's extension spells it: the payload struct, or the struct the
		/// member returns.
		let boundType: TypeDescription
		let fields: [SeamSignature.Hole.Field]
		/// The struct the member is called on, by name, and the member.
		let memberCall: (parentName: String, caseName: String)
		/// Whether the member is called at the top of the builder function of the binding's property, not before it.
		let isCalledInsideFunction: Bool
		/// Whether the struct is a carrier's `let` child, which the binding reads rather than calls.
		let isLetChild: Bool

		/// The line that binds the payload, each field read as
		/// `valuesArguments(of:readingInstancesOf:bindingNamesPassedByName:lazilyInstantiatedBindingNames:)` reads it.
		func line(readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>, bindingNamesPassedByName: [String: String] = [:], lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:]) -> String {
			"let \(bindingName) = \(expression(readingInstancesOf: lazilyInstantiatedInstanceProperties, bindingNamesPassedByName: bindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames))"
		}

		/// What `line(readingInstancesOf:)` reads, as the type key lists a text place's reads: the struct its member is called
		/// on, the run struct a carrier's member takes or the run before this one, and each field it reads of the scope.
		func reads(readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>) -> [PlaceRead] {
			var names = [String]()
			if let formsRunAfter {
				names.append(contentsOf: formsRunAfter.map { [$0] } ?? [])
			} else {
				names.append(memberCall.parentName)
				if case let .nested(_, enumType, _) = type, ReservedName.seamCarrier(ofEnum: enumType) != nil, !isLetChild, let structBindingName = carrierUse?.structBindingName {
					names.append(structBindingName)
				}
			}
			// A name the seam's tree binds for a level or a payload is read as a value of its own, whatever its type.
			var reads = names.map { name in
				PlaceRead(argumentLabel: name, label: name, property: Property(label: name, typeDescription: .simple(name: name)), source: .binding(label: name))
			}
			let isLetChildOfCarrier = formsRunAfter == nil && isLetChild
			guard !isLetChildOfCarrier else { return reads }
			let readFields = if formsRunAfter == nil, case let .nested(_, enumType, _) = type, ReservedName.seamCarrier(ofEnum: enumType) != nil {
				Array(fields[carrierUse?.extras ?? 0..<fields.count])
			} else {
				fields
			}
			for field in readFields {
				let label = field.property.label
				let readsInstance = !field.isDeferredParameter && lazilyInstantiatedInstanceProperties.contains(field.property.asUnwrappedProperty)
				reads.append(PlaceRead(
					argumentLabel: label,
					label: label,
					property: field.property,
					source: readsInstance ? .lazyInstance(label: label, throughOptional: false) : .binding(label: label),
				))
			}
			return reads
		}

		/// The value `line(readingInstancesOf:bindingNamesPassedByName:lazilyInstantiatedBindingNames:)` binds.
		func expression(readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>, bindingNamesPassedByName: [String: String] = [:], lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:]) -> String {
			if let formsRunAfter {
				// A run's struct, made of the run before it and the run's own values.
				// The run before it is handed on with `consume`: the body forms each run once, after every member that reads the
				// run before it, and no function captures a run's binding, so this is its last read. Without `consume`, Swift
				// 6.2's -O copies the whole chain beneath at each hand-off (the seam initializer of the generate-time check's P2-40
				// held 39 whole-chain `retain_value`s and 40 `release_value`s), which made a build of the tree five times slower.
				var arguments = formsRunAfter.map { ["\(SeamCarrierValues.previousName): consume \($0)"] } ?? []
				let values = SeamHoles.valuesArguments(of: fields, readingInstancesOf: lazilyInstantiatedInstanceProperties, bindingNamesPassedByName: bindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)
				if !values.isEmpty {
					arguments.append(values)
				}
				return "\(type.asSource)(\(arguments.joined(separator: ", ")))"
			}
			if case let .nested(_, enumType, _) = type, ReservedName.seamCarrier(ofEnum: enumType) != nil {
				// A seam's carrier takes the level's values as its member's arguments: the struct of the run they end, then any
				// after it, and holds a level handed none as a `let`.
				guard !isLetChild else { return "\(memberCall.parentName).\(memberCall.caseName)" }
				return "\(memberCall.parentName).\(memberCall.caseName)(\(SeamHoles.carrierArguments(of: fields, use: carrierUse, readingInstancesOf: lazilyInstantiatedInstanceProperties, bindingNamesPassedByName: bindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)))"
			}
			let payload = "\(type.asSource)(\(SeamHoles.valuesArguments(of: fields, readingInstancesOf: lazilyInstantiatedInstanceProperties, bindingNamesPassedByName: bindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)))"
			return "\(memberCall.parentName).\(memberCall.caseName)(\(payload))"
		}
	}

	/// How a call hands an inner seam's struct up: the member of its own case that returns it.
	struct RouteCase {
		/// The call of the call's own member, which returns the struct the inner seam is handed.
		var memberCall: String?
		/// The struct `memberCall` is called on, where the seam's tree binds it with a type: the type key's read of the call.
		var passedUpStruct: ScopeGenerator.BuilderCallArgument.PassedUpStruct?
	}

	/// The name of every builder the seam's generated initializer takes, inside the initializer, which a call its tree
	/// makes passes up by name, and of each payload its tree binds. Empty outside a seam's tree.
	let namesBoundForBuilders: Set<String>
	/// The name each deferred parameter of the seam's generated initializer binds its autoclosure to, which the
	/// initializer's body reads. Empty outside a seam's tree, and in a public mock's.
	let namesBoundForDeferredParameters: Set<String>
	/// Whether the tree's scopes hold the payloads of a loop of builders in one box (`ScopeGenerator.boxedLoops`): only a
	/// seam's own tree, whose initializer's extension declares the box's class. A public mock's tree, its fills included,
	/// binds each payload in a `let` of its own, a deliberate gap: its payloads were never builder structs, and nothing in
	/// its extension would declare the class.
	let holdsLoopPayloadsInBoxes: Bool
	/// `namesBoundForBuilders` and `namesBoundForDeferredParameters`, joined once for every scope of the tree to share: the
	/// payloads' names grow with the tree, so a join for each scope grew with the square of the tree.
	let namesBoundBySeam: GenerationWork.Shared<Set<String>>

	/// Whether the seam has no hole.
	var isEmpty: Bool {
		sitesByPath.isEmpty && passedUpHolesBySite.isEmpty
	}

	/// The hole whose site is the property at the end of `sitePath`, or `nil` when the signature holds none: a tree
	/// built to compute the signature, which generates nothing.
	func site(at sitePath: [Property]) -> SeamSignature.Hole? {
		sitesByPath[sitePath]
	}

	/// The hole of this seam that takes the builder for `hole`'s site, which a call its tree makes presents: a site of
	/// its own tree, which a call of the seam itself or of a seam that passes the site back presents, or a site it passes
	/// up. `nil` when the signature holds none: a tree built to compute the signature, which generates nothing.
	func hole(taking hole: SeamSignature.Hole) -> SeamSignature.Hole? {
		if hole.scopeSeamType == seamType {
			sitesByPath[hole.sitePath]
		} else {
			passedUpHolesBySite[hole.site]
		}
	}

	/// The builder of this seam that takes an inner seam's enum `innerKey` from the call at the end of `sitePath`, and the
	/// case that carries it. `nil` when the signature holds none: a tree built to compute the signature, which generates
	/// nothing.
	func routeCase(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key) -> RouteCase? {
		routeCasesByCall[RouteCall(sitePath: sitePath, innerKey: innerKey)]
	}

	/// The payloads bound just before the builder function of the property at the end of `sitePath`, and the structs the
	/// member calls made there return.
	func valuesBindings(at sitePath: [Property]) -> [ValuesBinding] {
		valuesBindingsByPath.isEmpty ? [] : valuesBindingsByPath[sitePath, default: []]
	}

	/// The structs the member calls made at the top of the builder function of the property at the end of `sitePath` return.
	func memberCallsInsideFunction(at sitePath: [Property]) -> [ValuesBinding] {
		memberCallsInsideFunctionByPath.isEmpty ? [] : memberCallsInsideFunctionByPath[sitePath, default: []]
	}

	/// The scope value the inner seam called at the end of `sitePath` hands the fills of its builder whose root enum is
	/// `innerKey`'s, where a place or a call inside one of them reads it: the name the fills, and each dispatcher that leads
	/// to them, take it under, and its type. The first of `innerScopes(at:innerKey:)`.
	func innerScope(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key) -> SeamSignature.Hole.RouteStep.InnerScope? {
		innerScopes(at: sitePath, innerKey: innerKey).first
	}

	/// Each scope value the inner seam called at the end of `sitePath` hands the fills of its builder whose root enum is
	/// `innerKey`'s, in the order of their names, which a fill and each level function on the way take them in: for a seam's
	/// builder struct, the struct of the fill's own level per hole type and family of this seam whose places the fills hold;
	/// for a public mock, its one inner scope.
	func innerScopes(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key) -> [SeamSignature.Hole.RouteStep.InnerScope] {
		innerScopesByCall.isEmpty ? [] : innerScopesByCall[RouteCall(sitePath: sitePath, innerKey: innerKey), default: []].sorted { $0.name < $1.name }
	}

	/// Whether the case of the call at the end of `sitePath` for its builder whose root enum is `innerKey`'s returns the called
	/// seam's struct, which the call's level functions are handed: `false` where the seam's enum declares no builder struct,
	/// or no place is inside the fill.
	func carriesStruct(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key) -> Bool {
		!carriedStructsByCall.isEmpty && carriedStructsByCall[RouteCall(sitePath: sitePath, innerKey: innerKey)] != nil
	}

	/// The name the seam's tree binds the struct the case of the call at the end of `sitePath` for its builder whose root
	/// enum is `innerKey`'s returns under, for the fill's parameter `innerScopeName`: the called seam's struct over the struct
	/// of the fill's own level of one hole type and family of this seam.
	func carriedStruct(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key, innerScopeName: String) -> String? {
		carriedStructsByCall.isEmpty ? nil : carriedStructsByCall[RouteCall(sitePath: sitePath, innerKey: innerKey)]?[innerScopeName]
	}

	/// The name the seam's tree binds the struct of type `structType` under that the case of the call at the end of `sitePath`,
	/// a call that re-enters an enclosing call's fill, returns for its builder whose root enum is `innerKey`'s: the called
	/// seam's struct over the struct of the reused fill's own level, which that call's level function takes as `structType`.
	func carriedStruct(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key, carrying structType: TypeDescription) -> String? {
		innerScopes(at: sitePath, innerKey: innerKey).first { $0.enumType == structType }.flatMap { carriedStruct(at: sitePath, innerKey: innerKey, innerScopeName: $0.name) }
	}

	/// A seam call in the tree and the inner enum it carries.
	private struct RouteCall: Hashable {
		let sitePath: [Property]
		let innerKey: SeamSignature.ScopeEnum.Key
	}

	/// The seam whose tree is generated, or `nil` for a tree that is no seam's.
	private let seamType: TypeDescription?

	/// Whether the tree takes builders for its holes: a seam's or a public mock's, never a root's, which has no caller to
	/// take one from.
	var takesBuilders: Bool {
		seamType != nil
	}

	private let routeCasesByCall: [RouteCall: RouteCase]
	private let sitesByPath: [[Property]: SeamSignature.Hole]
	private let passedUpHolesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]
	private let valuesBindingsByPath: [[Property]: [ValuesBinding]]
	private let memberCallsInsideFunctionByPath: [[Property]: [ValuesBinding]]
	private let innerScopesByCall: [RouteCall: [SeamSignature.Hole.RouteStep.InnerScope]]
	private let carriedStructsByCall: [RouteCall: [String: String]]
}

// MARK: - NearestDeclarations

/// The receives only if available in a mock's trees that production passes `nil`, since a required receive of their
/// label pins the declaration they read to a form they cannot read, as
/// `DependencyTreeGenerator.receivesPassedNilInMockTree` finds them.
struct MockReceivesPassedNil: Sendable {
	/// By label and then by the concrete type that declares each, the receives a required receive on their own type, or
	/// beneath it, pins: production passes them `nil` wherever their type is built. Each is the property it receives, an
	/// alias's fulfilling property.
	var pinnedWhereverBuilt = [String: [TypeDescription: Set<Property>]]()
	/// The labels of which a required receive above some receive only if available pins it. Production passes such a
	/// receive `nil` only in the places beneath a required receive that pins it, so the mock judges each place against
	/// the required receives above it (`NearestDeclarations.recordRequiredReceives(of:reading:)`).
	var labelsPinnedFromAbove = Set<String>()
	/// Where `labelsPinnedFromAbove` holds any label, the properties of the children the mock root promotes, whose trees
	/// production builds above the mocked type, so that the mocked type's own required receives pin nothing in them.
	var promotedProperties = Set<Property>()
}

/// The nearest declaration of a label on the path from a tree's root to a scope, as `Scope.createScopeGenerator` judges
/// what a scope receives only if available against it: each form the declaration provides, with the declared property
/// that binds it, and the forms of the label being built between that declaration and the scope.
struct NearestDeclaration: Equatable, Sendable {
	/// Each form the declaration provides (see `CycleParameter.forms(providedBy:)`), mapped to the declared property a
	/// reader of that form is handed: the property itself, the optional property a parameter made optional binds, or
	/// the `LazilyInstantiated` whose instance a by-value form reads.
	var bindings = [Property: Property]() {
		didSet { identity = Identity(of: self) }
	}

	/// The forms of the label being built between the declaration and the scope: a receive of one of them reads a
	/// declaration that is not built yet.
	var formsBeingBuilt = Set<Property>() {
		didSet { identity = Identity(of: self) }
	}

	/// The receives of the label only if available that read none of the declaration's forms wherever their type is
	/// built, by the concrete type that declares each: the property each receives (an alias's fulfilling property). Only
	/// a mock root's bindings hold any (see `NearestDeclarations.binding(_:passingNilTo:)`), so a declaration nearer the
	/// receive reads as production's.
	var receivesPassedNil = [TypeDescription: Set<Property>]() {
		didSet { identity = Identity(of: self) }
	}

	/// Whether a required receive of the label above a receive of it only if available can pin this declaration to a
	/// form the receive cannot read, in some place of the receive: only a mock root's bindings do.
	var judgesPlacesPinnedFromAbove = false {
		didSet { identity = Identity(of: self) }
	}

	/// What each required receive of the label between this declaration and the scope reads, where
	/// `judgesPlacesPinnedFromAbove`: each pins this declaration to its form (`NearestDeclarations.recordRequiredReceives(of:reading:)`).
	var propertiesReadByRequiredReceivesAbove = [Set<Property>]() {
		didSet { identity = Identity(of: self) }
	}

	/// Whether a mock root binds the declaration, from a value its tree receives, which it can name apart from its label
	/// (`NearestDeclarations.binding(_:passingNilTo:)`), rather than a scope of the tree: false where the mock binds it as
	/// the root's one declaration of the label, under the label (`NearestDeclarations.markBoundUnderLabelByRoot`).
	var isBoundByMockRoot = false {
		didSet { identity = Identity(of: self) }
	}

	/// Whether `other` is this declaration, unchanged since one was copied from the other: then it holds the same
	/// properties, spelled alike, which a construction memo compares for every read it answers again.
	func isUnchangedCopy(of other: Self) -> Bool {
		identity === other.identity
	}

	/// Compares every field, so that a construction memo's logged read of a declaration covers each: two mock roots can bind
	/// a label alike and differ only in the receives they pass `nil` or in whether the mock root binds it.
	static func == (lhs: Self, rhs: Self) -> Bool {
		guard !lhs.isUnchangedCopy(of: rhs) else { return true }
		return lhs.identity.contentHash == rhs.identity.contentHash
			&& lhs.bindings == rhs.bindings
			&& lhs.formsBeingBuilt == rhs.formsBeingBuilt
			&& lhs.receivesPassedNil == rhs.receivesPassedNil
			&& lhs.judgesPlacesPinnedFromAbove == rhs.judgesPlacesPinnedFromAbove
			&& lhs.propertiesReadByRequiredReceivesAbove == rhs.propertiesReadByRequiredReceivesAbove
			&& lhs.isBoundByMockRoot == rhs.isBoundByMockRoot
	}

	/// Made anew by every change, and copied with the declaration. It holds a hash of the declaration's content, which
	/// declarations `==` equates share, so that two that differ are told apart without comparing their properties: a
	/// construction memo compares many declarations that differ.
	private final class Identity: Sendable {
		convenience init(of declaration: NearestDeclaration) {
			self.init(
				bindings: declaration.bindings,
				formsBeingBuilt: declaration.formsBeingBuilt,
				receivesPassedNil: declaration.receivesPassedNil,
				judgesPlacesPinnedFromAbove: declaration.judgesPlacesPinnedFromAbove,
				propertiesReadByRequiredReceivesAbove: declaration.propertiesReadByRequiredReceivesAbove,
				isBoundByMockRoot: declaration.isBoundByMockRoot,
			)
		}

		init(
			bindings: [Property: Property],
			formsBeingBuilt: Set<Property>,
			receivesPassedNil: [TypeDescription: Set<Property>],
			judgesPlacesPinnedFromAbove: Bool,
			propertiesReadByRequiredReceivesAbove: [Set<Property>],
			isBoundByMockRoot: Bool,
		) {
			var hasher = Hasher()
			hasher.combine(bindings)
			hasher.combine(formsBeingBuilt)
			hasher.combine(receivesPassedNil)
			hasher.combine(judgesPlacesPinnedFromAbove)
			hasher.combine(propertiesReadByRequiredReceivesAbove)
			hasher.combine(isBoundByMockRoot)
			contentHash = hasher.finalize()
		}

		let contentHash: Int
	}

	private var identity = Identity(bindings: [:], formsBeingBuilt: [], receivesPassedNil: [:], judgesPlacesPinnedFromAbove: false, propertiesReadByRequiredReceivesAbove: [], isBoundByMockRoot: false)
}

/// The nearest declaration of each label on the path from a tree's root to a scope. A label absent here is declared
/// nowhere on the path.
///
/// Every scope of a tree holds its own, which differs from its parent's only in the labels the scope declares or builds.
/// So that no scope copies the declarations of the scopes above it, those are kept in a chain of layers every scope
/// beneath shares (`sharingDeclarations()`): a scope's own changes, then the layer of each scope enclosing it, nearest
/// first, then the declarations that enclose the whole tree – a mock root binds every property its tree receives.
struct NearestDeclarations: Sendable {
	init() {}

	/// The nearest declaration of `label`.
	subscript(label: String) -> NearestDeclaration? {
		resolving(label).declaration
	}

	/// The nearest declaration of `label`, with the depth of the scope that made it the nearest: the depth in the tree of
	/// the scope whose changes hold it, or -1 where the tree was given it or no scope on the path declares the label. A
	/// construction memo reads the depth to tell a read answered inside a subtree from one answered above it (see
	/// `ConstructionMemo`).
	func resolving(_ label: String) -> (declaration: NearestDeclaration?, depth: Int) {
		if let changedDeclaration = changedDeclarations[label] {
			return (changedDeclaration, changedDepth)
		}
		var layer = enclosingLayer
		while let currentLayer = layer {
			if let declaration = currentLayer.declarations[label] {
				return (declaration, currentLayer.depth)
			}
			layer = currentLayer.enclosingLayer
		}
		return (nil, -1)
	}

	/// These declarations, with every change held in a layer the copies of the result share.
	func sharingDeclarations() -> Self {
		guard !changedDeclarations.isEmpty else { return self }
		var sharing = Self()
		sharing.enclosingLayer = Layer(declarations: changedDeclarations, depth: changedDepth, enclosingLayer: enclosingLayer)
		sharing.changedDepth = changedDepth
		sharing.holdsReceivesPassedNil = holdsReceivesPassedNil
		sharing.judgesPlacesPinnedFromAbove = judgesPlacesPinnedFromAbove
		sharing.mockRootPromotedProperties = mockRootPromotedProperties
		return sharing
	}

	/// These declarations, as the scope at `depth` in the tree starts to change them: each change it makes is recorded as
	/// made at its depth, and the changes made before are kept at the depth that made them.
	func changed(atDepth depth: Int) -> Self {
		var changing = sharingDeclarations()
		changing.changedDepth = depth
		return changing
	}

	/// The declarations a scope changed, which hide those of their labels in the layers it is enclosed by. A chain of
	/// layers can be as long as a tree is deep, which can be as deep as the module has types, so each layer releases
	/// the one it is enclosed by after the release that freed it returns, rather than within it.
	private final class Layer: Sendable {
		init(declarations: [String: NearestDeclaration], depth: Int, enclosingLayer: Layer?) {
			self.declarations = declarations
			self.depth = depth
			enclosingLayers = DeferredReleaseSlot(enclosingLayer.map { [$0] } ?? [])
		}

		let declarations: [String: NearestDeclaration]
		/// The depth in the tree of the scope that made these declarations, or -1 for those the tree was given.
		let depth: Int

		/// The layer this one is enclosed by, if any.
		var enclosingLayer: Layer? {
			enclosingLayers.value.first
		}

		/// `enclosingLayer`, held in an array, which the slot releases after the release that freed this layer returns.
		private let enclosingLayers: DeferredReleaseSlot<[Layer]>
	}

	/// The declarations shared with the scopes above, nearest first.
	private var enclosingLayer: Layer?
	/// The declarations changed since `enclosingLayer`, which hide those of their labels there.
	private var changedDeclarations = [String: NearestDeclaration]()
	/// The depth in the tree of the scope making `changedDeclarations`, or -1 before the tree's root changes them.
	private var changedDepth = -1
	/// Whether a declaration enclosing the whole tree holds `NearestDeclaration.receivesPassedNil`, which only a mock
	/// root's can, so that no other tree looks for one.
	private var holdsReceivesPassedNil = false
	/// Whether a declaration enclosing the whole tree has `NearestDeclaration.judgesPlacesPinnedFromAbove`, which only a
	/// mock root's can, so that no other tree records its required receives.
	private(set) var judgesPlacesPinnedFromAbove = false
	/// The properties of the children a mock root promotes, where `judgesPlacesPinnedFromAbove` (see
	/// `MockReceivesPassedNil.promotedProperties`).
	private var mockRootPromotedProperties = Set<Property>()

	/// The nearest declarations of `labels` alone, as declarations a tree is given: what a body keyed by the answers to
	/// those labels is built beneath, whatever else its path declares (`VariantBodyObservation`).
	func keeping(labels: [String]) -> NearestDeclarations {
		var kept = NearestDeclarations()
		for label in labels {
			if let nearestDeclaration = self[label] {
				kept.set(nearestDeclaration, for: label)
			}
		}
		// A mock root's declarations pass `nil` to the receives its bindings say production passes `nil`, wherever they
		// are kept. A production root's declarations hold none of the three, so nothing kept of them moves.
		kept.holdsReceivesPassedNil = holdsReceivesPassedNil
		kept.judgesPlacesPinnedFromAbove = judgesPlacesPinnedFromAbove
		kept.mockRootPromotedProperties = mockRootPromotedProperties
		return kept
	}

	/// Makes `nearestDeclaration` the nearest declaration of `label`.
	private mutating func set(_ nearestDeclaration: NearestDeclaration, for label: String) {
		changedDeclarations[label] = nearestDeclaration
	}
}

extension NearestDeclarations {
	/// The declarations a mock root's tree is enclosed by: each of `boundProperties`, the received properties the mock
	/// binds, in `Property` order, each form bound to the first property that provides it. The mock binds each form once
	/// and names every binding apart, so no binding hides another. A receive `receivesPassedNil` lists reads none of them
	/// in the places it says: production always passes it `nil` there, since another receive of its label pins the one
	/// declaration both read to a form it cannot read (see `DependencyTreeGenerator.receivesPassedNilInMockTree`).
	static func binding(
		_ boundProperties: some Collection<Property>,
		passingNilTo receivesPassedNil: MockReceivesPassedNil = MockReceivesPassedNil(),
	) -> Self {
		var nearestDeclarations = Self()
		for boundProperty in boundProperties.sorted() {
			nearestDeclarations.join(boundProperty, providing: CycleParameter.forms(providedBy: boundProperty))
			nearestDeclarations.markBoundByMockRoot(boundProperty.label)
		}
		for (label, receivesPassedNilByType) in receivesPassedNil.pinnedWhereverBuilt {
			var nearestDeclaration = nearestDeclarations[label] ?? NearestDeclaration()
			nearestDeclaration.receivesPassedNil = receivesPassedNilByType
			nearestDeclarations.set(nearestDeclaration, for: label)
			nearestDeclarations.holdsReceivesPassedNil = true
		}
		for label in receivesPassedNil.labelsPinnedFromAbove {
			var nearestDeclaration = nearestDeclarations[label] ?? NearestDeclaration()
			nearestDeclaration.judgesPlacesPinnedFromAbove = true
			nearestDeclarations.set(nearestDeclaration, for: label)
			nearestDeclarations.holdsReceivesPassedNil = true
			nearestDeclarations.judgesPlacesPinnedFromAbove = true
		}
		nearestDeclarations.mockRootPromotedProperties = receivesPassedNil.promotedProperties
		return nearestDeclarations.sharingDeclarations()
	}

	/// Whether a declaration enclosing the whole tree holds `NearestDeclaration.receivesPassedNil` or
	/// `NearestDeclaration.judgesPlacesPinnedFromAbove`: `false` in every tree but a mock root's, where
	/// `resolvingPassesNil(to:receivedBy:on:)` answers `false` for every receive.
	var mayPassNil: Bool {
		holdsReceivesPassedNil
	}

	/// Whether a receive of `property` only if available, by `dependency` on `receivingType`, reads none of the forms
	/// the nearest declaration of its label binds in this place, which a mock passes `nil` as production does: wherever
	/// its type is built, or beneath a required receive of its label that pins the declaration to a form it cannot read;
	/// with the depth of the scope that made the nearest declaration of `property`'s label the nearest (see
	/// `resolving(_:)`). The answer reads that declaration alone, so a construction memo that asks it again at that depth
	/// asks it of the declaration whole. Asked only where `mayPassNil`.
	func resolvingPassesNil(to property: Property, receivedBy dependency: Dependency, on receivingType: TypeDescription) -> (passesNil: Bool, depth: Int) {
		let (nearestDeclaration, depth) = resolving(property.label)
		guard holdsReceivesPassedNil, let nearestDeclaration else { return (false, depth) }
		return (
			nearestDeclaration.receivesPassedNil[receivingType]?.contains(property) == true
				|| nearestDeclaration.propertiesReadByRequiredReceivesAbove.contains {
					DependencyTreeGenerator.requiredReceive(reading: $0, pinsReceiveOf: dependency)
				},
			depth,
		)
	}

	/// Records what each required receive of the type of `scope` reads, of a label whose nearest declaration
	/// `judgesPlacesPinnedFromAbove`, for the scopes beneath it: each pins that declaration to its form. Calls `reading` with
	/// each label it reads the nearest declaration of, that declaration, and the depth of the scope that made it the nearest,
	/// before any change: a construction memo logs each, since a declaration this changes is made at the scope's depth, inside
	/// its subtree, from one above it.
	mutating func recordRequiredReceives(of scope: ConstructionScope, reading: (_ label: String, _ declaration: NearestDeclaration?, _ depth: Int) -> Void) {
		recordRequiredReceives(of: scope.instantiable, publicMockCall: scope.publicMockCall, reading: reading)
	}

	/// Records what each required receive of `instantiable`, built as `publicMockCall` where it is one, reads, as
	/// `recordRequiredReceives(of:reading:)` does for a scope of a frozen table.
	mutating func recordRequiredReceives(of instantiable: Instantiable, publicMockCall: PublicMockCall?, reading: (_ label: String, _ declaration: NearestDeclaration?, _ depth: Int) -> Void = { _, _, _ in }) {
		for (label, propertiesRead) in DependencyTreeGenerator.propertiesReadByRequiredReceivesFromAbove(of: instantiable, publicMockCall: publicMockCall) {
			let (declaration, depth) = resolving(label)
			reading(label, declaration, depth)
			if var nearestDeclaration = declaration,
			   nearestDeclaration.judgesPlacesPinnedFromAbove,
			   !nearestDeclaration.propertiesReadByRequiredReceivesAbove.contains(propertiesRead)
			{
				nearestDeclaration.propertiesReadByRequiredReceivesAbove.append(propertiesRead)
				set(nearestDeclaration, for: label)
			}
		}
	}

	/// Whether `property` is that of a child a mock root promotes, whose tree production builds above the mocked type.
	func isPromotedByMockRoot(_ property: Property) -> Bool {
		mockRootPromotedProperties.contains(property)
	}

	/// The binding a receive of `property` only if available reads, or `nil` when the property is unavailable: the
	/// first of `property.formsReadByOnlyIfAvailableReceive` that the nearest declaration of its label binds, unless a
	/// form it reads is still being built between that declaration and the receiver; with the depth of the scope that
	/// made the nearest declaration of `property`'s label the nearest (see `resolving(_:)`).
	func resolvingBinding(of property: Property) -> (binding: Property?, depth: Int) {
		let (nearestDeclaration, depth) = resolving(property.label)
		guard let nearestDeclaration else { return (nil, depth) }
		let forms = property.formsReadByOnlyIfAvailableReceive
		guard nearestDeclaration.formsBeingBuilt.isDisjoint(with: forms) else { return (nil, depth) }
		for form in forms {
			if let binding = nearestDeclaration.bindings[form] {
				return (binding, depth)
			}
		}
		return (nil, depth)
	}

	/// Whether the nearest declaration of `property`'s label binds `property` itself, built before the scope.
	func binds(_ property: Property) -> Bool {
		guard let nearestDeclaration = self[property.label] else { return false }
		return nearestDeclaration.bindings[property] != nil && !nearestDeclaration.formsBeingBuilt.contains(property)
	}

	/// Makes `property`, which provides `forms`, the nearest declaration of its label, hiding every other.
	mutating func replace(_ property: Property, providing forms: Set<Property>) {
		var nearestDeclaration = NearestDeclaration()
		for form in forms {
			nearestDeclaration.bindings[form] = property
		}
		set(nearestDeclaration, for: property.label)
	}

	/// Makes `properties`, the declarations of one scope that is no root, each with the forms it provides, the nearest
	/// declarations of their labels, each hiding every declaration of its label above the scope. Their labels are
	/// distinct: they are the dependencies of the scope's type, which
	/// `DependencyTreeGenerator.validateDependencyLabelsAreDistinct` rejects before a tree that builds it is created when
	/// two share a label. A root's declarations, among which a mock root's forms of one label repeat it, join the
	/// bindings the tree is given instead (`join(_:providing:)`).
	mutating func replaceLabels(of properties: [(property: Property, forms: Set<Property>)]) {
		for (property, forms) in properties {
			replace(property, providing: forms)
		}
	}

	/// Adds `property`, which provides `forms`, to the nearest declaration of its label, keeping each form already bound.
	mutating func join(_ property: Property, providing forms: Set<Property>) {
		var nearestDeclaration = self[property.label] ?? NearestDeclaration()
		for form in forms where nearestDeclaration.bindings[form] == nil {
			nearestDeclaration.bindings[form] = property
		}
		set(nearestDeclaration, for: property.label)
	}

	/// Records that the nearest declaration of `label` is a mock root's binding (`NearestDeclaration.isBoundByMockRoot`).
	private mutating func markBoundByMockRoot(_ label: String) {
		var nearestDeclaration = self[label] ?? NearestDeclaration()
		nearestDeclaration.isBoundByMockRoot = true
		set(nearestDeclaration, for: label)
	}

	/// Records that a root's declaration of `label`, which provides `forms`, is bound under the label. Where a mock root binds
	/// `label` from a value its tree receives and every form the nearest declaration binds is among `forms` – so no other
	/// declaration of the root, nor a value `mock()` takes, has another form of the label – the mock binds them all as that
	/// child of the root, and the nearest declaration is no longer one the mock can name apart
	/// (`NearestDeclaration.isBoundByMockRoot`).
	mutating func markBoundUnderLabelByRoot(_ label: String, providing forms: Set<Property>) {
		guard var nearestDeclaration = self[label],
		      nearestDeclaration.isBoundByMockRoot,
		      nearestDeclaration.bindings.keys.allSatisfy(forms.contains)
		else { return }
		nearestDeclaration.isBoundByMockRoot = false
		set(nearestDeclaration, for: label)
	}

	/// Records that `property` is being built: every form it provides is unavailable until a nearer declaration of its
	/// label hides it.
	mutating func build(_ property: Property) {
		var nearestDeclaration = self[property.label] ?? NearestDeclaration()
		nearestDeclaration.formsBeingBuilt.formUnion(CycleParameter.forms(providedBy: property))
		set(nearestDeclaration, for: property.label)
	}
}

extension Property {
	/// The forms a receive of this property only if available reads, in the order it prefers them: itself, its
	/// unwrapped form, and that form made optional. An `onlyIfAvailable` alias of `x: X` therefore reads a declaration
	/// of `x: X?` too, as an `onlyIfAvailable` receive of `x: X?` reads one of `x: X`.
	var formsReadByOnlyIfAvailableReceive: [Property] {
		let unwrappedProperty = asUnwrappedProperty
		return if unwrappedProperty == self {
			[self, asOptionalProperty]
		} else {
			[self, unwrappedProperty]
		}
	}
}

extension SeamHoles {
	/// The holes, builders and routes of `seamRoot`, the seam root of `seamType`, as a tree of the seam reads them.
	init(of seamRoot: ScopeGenerator.SeamRoot, seamType: TypeDescription) {
		self.init(seamType: seamType, holes: seamRoot.signature.holes, builders: seamRoot.signature.builders, parameters: seamRoot.signature.parameters, callRoutes: seamRoot.signature.callRoutes, scopeEnums: seamRoot.signature.scopeEnums, holdsLoopPayloadsInBoxes: true)
	}
}

extension ScopeGenerator {
	/// The tree rooted at `tree`, the tree the first signature pass of `seamType` built, made again for the seam's
	/// emission from its final seam root, `seamRoot`: each generator is made again (`init(reseating:children:sitePath:seamRoot:seamHoles:namesBoundBySeam:)`)
	/// once its children are, in index order, and a generator several places share is made again once and shared alike.
	/// Only a tree that `DependencyTreeGenerator.confirmingPassFindsNothingNew` let settle is made again: it holds no
	/// call, fill or hole passed up, and its root's parameters are the final ones (see `seam-signature-passes.md`).
	static func reseating(treeRootedAt tree: ScopeGenerator, of seamType: TypeDescription, seamRoot: SeamRoot) -> ScopeGenerator {
		ScopeGeneratorUnderConstruction.reseating(treeRootedAt: tree, seamHoles: SeamHoles(of: seamRoot, seamType: seamType), seamRoot: seamRoot)
	}
}

extension ScopeGeneratorUnderConstruction {
	/// See `ScopeGenerator.reseating(treeRootedAt:of:seamRoot:)`.
	fileprivate static func reseating(treeRootedAt tree: ScopeGenerator, seamHoles: SeamHoles, seamRoot: ScopeGenerator.SeamRoot) -> ScopeGenerator {
		let namesBoundBySeam = GenerationWork.taking(seamHoles.namesBoundBySeam, by: .joiningNamesBoundBySeam)
		/// A generator being made again, whose children are made again first.
		struct Reseating {
			let generator: ScopeGenerator
			let sitePath: [Property]
			var children = [ScopeGenerator]()
		}
		// A tree can be as deep as the module has types, so it is walked on a stack of its own.
		var stack = [Reseating(generator: tree, sitePath: [])]
		var reseatedByGenerator = [ObjectIdentifier: ScopeGenerator]()
		// Replaced by the root's new generator, made last.
		var reseatedTree = tree
		while !stack.isEmpty {
			let index = stack.count - 1
			let children = stack[index].generator.children
			if stack[index].children.count < children.count {
				let child = children[stack[index].children.count]
				if let reseated = reseatedByGenerator[ObjectIdentifier(child)] {
					stack[index].children.append(reseated)
				} else {
					stack.append(Reseating(generator: child, sitePath: stack[index].sitePath + (child.property.map { [$0] } ?? [])))
				}
				continue
			}
			let reseating = stack.removeLast()
			let reseated = ScopeGenerator(
				reseating: reseating.generator,
				children: reseating.children,
				sitePath: reseating.sitePath,
				seamRoot: seamRoot,
				seamHoles: seamHoles,
				namesBoundBySeam: namesBoundBySeam,
			)
			if stack.isEmpty {
				reseatedTree = reseated
			} else {
				reseatedByGenerator[ObjectIdentifier(reseating.generator)] = reseated
				stack[stack.count - 1].children.append(reseated)
			}
		}
		return reseatedTree
	}
}
