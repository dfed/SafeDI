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
	init(
		instantiable: Instantiable,
		dependenciesLeftOut: [Dependency] = [],
		builtInlineSeamComment: String? = nil,
		seamCall: SeamCall? = nil,
		publicMockCall: PublicMockCall? = nil,
	) {
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

	/// How a tree that reaches this scope calls the seam it stands for, or `nil` for a scope that builds its type.
	let seamCall: SeamCall?

	/// How a mock tree that reaches this scope calls the public mock another module generated for its type, which the
	/// tree cannot build itself: `instantiable` then declares the mock's signature as its dependencies and builds
	/// nothing. `nil` for every other scope.
	let publicMockCall: PublicMockCall?

	/// What a construction memo keys and keeps alive for this scope (see `ConstructionGraph`).
	let constructionIdentity = ConstructionScopeIdentity()

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

	/// The property this scope's type creates – instantiates, is forwarded, or declares by an alias – that a dependency
	/// of the type reads for `property`, which it receives only if available: the first form of `property` (see
	/// `Property.formsReadByOnlyIfAvailableReceive`) that a created property provides (see
	/// `CycleParameter.forms(providedBy:)`). `nil` when the type creates none, and the dependency reads the nearest
	/// declaration above the scope.
	func createdBinding(of property: Property) -> Property? {
		for form in property.formsReadByOnlyIfAvailableReceive {
			if let binding = createdBindings[form] {
				return binding
			}
		}
		return nil
	}

	/// The created property that provides each form, for `createdBinding(of:)`. A type's labels are distinct, so no two
	/// of its created properties provide one form.
	/// The declaration this scope creates that provides each form, which `createdBinding(of:)` reads.
	var createdBindingsByForm: [Property: Property] {
		createdBindings
	}

	private lazy var createdBindings: [Property: Property] = {
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
	private(set) lazy var instantiatedDependenciesNotGenerated: [Dependency] = instantiable
		.dependencies
		.filter { dependency in
			switch dependency.source {
			case .instantiated:
				// A mock root can generate the dependency as the `LazilyInstantiated` its tree receives.
				!propertiesToGenerate.contains {
					$0.property == dependency.property || $0.lazilyInstantiatedInstanceProperty == dependency.property
				}
			case .received, .aliased, .forwarded:
				false
			}
		}

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
	///   - startsCodeGeneration: Whether each generator of a dependency tree starts generating its code as soon as
	///     it is created, which a tree built only to read its generators' sets skips.
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
	///
	/// The tree is created again while a scope that a lazy cycle closes on finds other parameters for its builder
	/// function than it was created with (see `CycleParameter`): its cycle-closing scopes, created before it, pass
	/// those parameters, and count what they pass among the properties they receive. Nearly every tree has no such
	/// scope and is created once. A pass changes a scope's parameters only through the parameters of the functions it
	/// is nested in or that are nested in it, which only add to what it receives or declares, so the passes end once
	/// the parameters at each level of nesting have settled. The first pass starts each generator's code as the
	/// generator is created, since nearly every tree takes one pass; a later pass starts none until the passes end,
	/// and then only the last pass's, since nothing reads the code of a pass that is not the last.
	///
	/// A tree that holds a place of a hole is also created again when a scope's children would start in another order by
	/// what its type's properties hold (`SeamDeclarationGraph`) than by what their subtrees hold on its path, which only a
	/// tangle of cycles, or a type that one declaration builds outside a cycle and another builds inside one, makes them
	/// do: the pass after creates each scope outside a fill with the properties of its type that hold a place
	/// (`ScopeGenerator.startsAsCarrier(_:)`). The order decides nothing a pass creates, so the graph of
	/// the pass after is the same.
	func createScopeGenerator(
		for property: Property?,
		nearestDeclarations: NearestDeclarations = NearestDeclarations(),
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot? = nil,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool = false,
		startsCodeGeneration: Bool = true,
		validatesForwardedProperties: Bool = true,
		declaredTypeNames: DeclaredTypeNames,
		constructionMemo: inout ConstructionMemo,
	) throws -> ScopeGenerator {
		// Every pass reads the scopes as they are now, which nothing changes while the tree is built.
		try ConstructionGraph(rootedAt: self).createScopeGenerator(
			for: property,
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			declaredTypeNames: declaredTypeNames,
			constructionMemo: &constructionMemo,
		)
	}
}

extension ConstructionGraph {
	/// `Scope.createScopeGenerator(for:…)` of the scope this graph is rooted at: the tree, then the memo oracle's builds of it.
	func createScopeGenerator(
		for property: Property?,
		nearestDeclarations: NearestDeclarations = NearestDeclarations(),
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot? = nil,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool = false,
		startsCodeGeneration: Bool = true,
		validatesForwardedProperties: Bool = true,
		declaredTypeNames: DeclaredTypeNames,
		constructionMemo: inout ConstructionMemo,
	) throws -> ScopeGenerator {
		let scopeGenerator = try createdTree(
			for: property,
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			declaredTypeNames: declaredTypeNames,
			constructionMemo: &constructionMemo,
		)
		try checkWithMemoOracle(
			for: property,
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			declaredTypeNames: declaredTypeNames,
			constructionMemo: &constructionMemo,
		)
		return scopeGenerator
	}

	/// Builds the tree `createdTree(for:…)` builds twice more, with the memo oracle's memo and with no memo, and hands both to
	/// the oracle, when one is installed. Called once for each tree created with `constructionMemo`, in the order the trees
	/// are created, so the oracle's memo holds what it would if the trees were created one after another.
	func checkWithMemoOracle(
		for property: Property?,
		nearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders?,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		validatesForwardedProperties: Bool,
		declaredTypeNames: DeclaredTypeNames,
		constructionMemo: inout ConstructionMemo,
	) throws {
		if let observer = ConstructionMemoOracle.observer {
			// The oracle's two builds start no code, so nothing changes either while it is read. The build with the memo
			// shares it across every tree created with this memo, whatever the memo's own sharing, so that the oracle judges
			// every reuse either sharing makes.
			var oracleMemo = constructionMemo.oracleMemo
			let treeBuiltWithMemo = try createdTree(
				for: property,
				nearestDeclarations: nearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				seamRoot: seamRoot,
				mockBuilders: mockBuilders,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
				startsCodeGeneration: false,
				validatesForwardedProperties: validatesForwardedProperties,
				declaredTypeNames: declaredTypeNames,
				constructionMemo: &oracleMemo,
			)
			constructionMemo.oracleMemo = oracleMemo
			let treeBuiltWithoutMemo = try ConstructionMemo.$isEnabled.withValue(false) {
				var unusedMemo = ConstructionMemo()
				return try createdTree(
					for: property,
					nearestDeclarations: nearestDeclarations,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
					seamRoot: seamRoot,
					mockBuilders: mockBuilders,
					erasedToConcreteExistential: erasedToConcreteExistential,
					forMockGeneration: forMockGeneration,
					startsCodeGeneration: false,
					validatesForwardedProperties: validatesForwardedProperties,
					declaredTypeNames: declaredTypeNames,
					constructionMemo: &unusedMemo,
				)
			}
			observer(treeBuiltWithMemo, treeBuiltWithoutMemo)
		}
	}

	/// The tree `createScopeGenerator` creates, in as many passes as it takes.
	func createdTree(
		for property: Property?,
		nearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders?,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		startsCodeGeneration: Bool,
		validatesForwardedProperties: Bool,
		declaredTypeNames: DeclaredTypeNames,
		constructionMemo: inout ConstructionMemo,
	) throws -> ScopeGenerator {
		var previousPassGenerator: ScopeGenerator?
		var firstPassMemo = ConstructionMemo()
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
		var generatorsToStart: [ScopeGenerator]?
		// Every scope of the tree is enclosed by these, so they are held in storage each scope's copy shares.
		let nearestDeclarations = nearestDeclarations.sharingDeclarations()
		var startOrderChanged: Bool
		repeat {
			if previousPassGenerator != nil {
				generatorsToStart = []
			}
			var passMemo = previousPassGenerator == nil && sharesMemo ? constructionMemo.memoForFirstPass : ConstructionMemo()
			// A place whose generator the pass before built settled is reused across passes only while the passes share
			// the place-holding properties every place's build reads.
			let settledPassMemo = placeHoldingPropertiesByType == placeHoldingPropertiesOfPreviousPass ? previousPassMemo : nil
			scopeGenerator = try createScopeGenerator(
				for: property,
				nearestDeclarations: nearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				seamRoot: seamRoot,
				mockBuilders: mockBuilders,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
				startsCodeGeneration: startsCodeGeneration,
				validatesForwardedProperties: validatesForwardedProperties,
				declaredTypeNames: declaredTypeNames,
				previousPassGenerator: previousPassGenerator,
				generatorsToStart: &generatorsToStart,
				placeHoldingPropertiesByType: placeHoldingPropertiesByType,
				memo: &passMemo,
				settledPassMemo: settledPassMemo,
			)
			if previousPassGenerator == nil {
				firstPassMemo = passMemo
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
		} while startOrderChanged || scopeGenerator.cycleParametersChangedInTree || scopeGenerator.fillStructBoundLabelsChangedInTree || scopeGenerator.receivedBuilderLoopsChangedInTree
		for generator in generatorsToStart ?? [] {
			ScopeGeneratorUnderConstruction.startCodeGeneration(of: generator)
		}
		// The entries of a tree are kept only once its construction returns. A mock root whose construction throws keeps
		// none, and its error, `ErasedInstantiatorForwardedPropertiesMismatchError`, the only one construction throws, ends
		// the whole mock pass where the root stands in type order, so no mock root after it is finished, and the roots of
		// its wave built after it are dropped. A change that adds a construction error the mock pass catches owes a test
		// that such a root, first, in the middle and last of a wave, and in a later wave, reports the same errors, and
		// leaves the other roots the same mocks, with the memo shared between mock roots and without it.
		if sharesMemo {
			constructionMemo.keepEntries(ofFirstPass: firstPassMemo)
		}
		return scopeGenerator
	}

	/// One pass of `createScopeGenerator`, which reads the parameters of the builder functions lazy cycles close on
	/// from `previousPassGenerator`, the tree the pass before created, or finds none when there is no pass before.
	/// - Parameter generatorsToStart: `nil` to start each generator's code as it is created, or where to collect the
	///   generators whose code to start, in the order they are created.
	/// - Parameter memo: The generators already finished, which a later place of the same key whose context answers their
	///   reads alike reuses, and where this pass stores the generators it finishes (see `ConstructionMemo`).
	private func createScopeGenerator(
		for property: Property?,
		nearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders?,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		startsCodeGeneration: Bool,
		validatesForwardedProperties: Bool,
		declaredTypeNames: DeclaredTypeNames,
		previousPassGenerator: ScopeGenerator?,
		generatorsToStart: inout [ScopeGenerator]?,
		placeHoldingPropertiesByType: [TypeDescription: Set<Property>]?,
		memo: inout ConstructionMemo,
		settledPassMemo: ConstructionMemo?,
	) throws -> ScopeGenerator {
		var scopeGeneratorsUnderConstruction = [ScopeGeneratorUnderConstruction(
			scope: root,
			property: property,
			propertyStack: [],
			concreteTypeStack: [],
			depthStack: [],
			depth: 0,
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			seamHoles: seamRoot.map { SeamHoles(seamType: root.instantiable.concreteInstantiable, holes: $0.signature.holes, builders: $0.signature.builders, parameters: $0.signature.parameters, callRoutes: $0.signature.callRoutes) }
				?? mockBuilders.map { SeamHoles(seamType: root.instantiable.concreteInstantiable, holes: $0.holes, builders: $0.builders, callRoutes: $0.callRoutes) }
				?? SeamHoles(),
			sitePath: [],
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			declaredTypeNames: declaredTypeNames,
			previousPassGenerator: previousPassGenerator,
			cycleParameterContexts: [:],
			placeHoldingPropertiesByType: placeHoldingPropertiesByType,
		)]
		let reusesGenerators = ConstructionMemo.isEnabled
		// The generators whose code this pass started or collected, each of which a place that reuses it does not start again.
		var startedGenerators = Set<ObjectIdentifier>()
		// Every generator this pass started or collected, in order: what each place's build started is the part of it from
		// the place's `startLogIndex` on, which a later pass that reuses the place's generator collects again.
		var startLog = [ScopeGenerator]()
		while true {
			let index = scopeGeneratorsUnderConstruction.count - 1
			if let propertyToGenerate = scopeGeneratorsUnderConstruction[index].nextPropertyToGenerate() {
				switch propertyToGenerate {
				case let .instantiated(property, scope, erasedToConcreteExistential):
					try scopeGeneratorsUnderConstruction[index].validateForwardedProperties(ofChildBuilding: scope, as: property)
					let key = reusesGenerators
						? scopeGeneratorsUnderConstruction[index].memoKey(ofChildBuilding: scope, as: property, erasedToConcreteExistential: erasedToConcreteExistential)
						: nil
					if let key, let reuse = memo.reuse(of: key, in: scopeGeneratorsUnderConstruction[index].childContext, besides: scopeGeneratorsUnderConstruction[index].childGeneratorIdentifiers) {
						scopeGeneratorsUnderConstruction[index].add(reusing: reuse)
					} else if let key, let reuse = settledPassMemo?.settledReuse(of: key, in: scopeGeneratorsUnderConstruction[index].childContext, besides: scopeGeneratorsUnderConstruction[index].childGeneratorIdentifiers) {
						// The pass before built this place's generator settled: building the place again would build it again.
						// Its code starts as the build would have started it, and the memo holds it for the places after it.
						for generator in reuse.entry.startedBeneath where startedGenerators.insert(ObjectIdentifier(generator)).inserted {
							generatorsToStart?.append(generator)
							startLog.append(generator)
						}
						memo.store(reuse.entry, for: key, keepingAlive: scope.identity)
						scopeGeneratorsUnderConstruction[index].add(reusing: reuse)
					} else {
						var child = scopeGeneratorsUnderConstruction[index].childUnderConstruction(
							scope: scope,
							property: property,
							erasedToConcreteExistential: erasedToConcreteExistential,
						)
						child.memoKey = key
						child.startLogIndex = startLog.count
						scopeGeneratorsUnderConstruction.append(child)
					}
				case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
					scopeGeneratorsUnderConstruction[index].addAliasGenerator(
						property: property,
						fulfillingProperty: fulfillingProperty,
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
						declarationReference: declarationReference,
					)
				case let .hole(property, erasedToConcreteExistential, _):
					scopeGeneratorsUnderConstruction[index].addHoleGenerator(
						property: property,
						erasedToConcreteExistential: erasedToConcreteExistential,
					)
				}
			} else if let fill = scopeGeneratorsUnderConstruction[index].nextFill() {
				try scopeGeneratorsUnderConstruction.append(scopeGeneratorsUnderConstruction[index].fillUnderConstruction(
					fill: fill.fill,
					scope: fill.scope,
				))
			} else {
				var createdScope = scopeGeneratorsUnderConstruction.removeLast()
				let scopeGenerator = createdScope.scopeGenerator(collectingGeneratorsToStartInto: &generatorsToStart, startedGenerators: &startedGenerators, startLog: &startLog)
				if scopeGeneratorsUnderConstruction.isEmpty {
					return scopeGenerator
				} else {
					// Filtered once, for the memo and the parent alike.
					let readsAnsweredAbove = createdScope.readsAnsweredAbove
					let isSettled = createdScope.isSettled(building: scopeGenerator)
					if let key = createdScope.memoKey, createdScope.isMemoizable {
						memo.store(ConstructionMemo.Entry(
							reads: readsAnsweredAbove,
							generator: scopeGenerator,
							subtreeScopeCount: createdScope.subtreeScopeCount,
							startedBeneath: Array(startLog[createdScope.startLogIndex...]),
							isSettled: isSettled,
						), for: key, keepingAlive: createdScope.builtScope.identity)
					}
					scopeGeneratorsUnderConstruction[scopeGeneratorsUnderConstruction.count - 1].add(childGenerator: scopeGenerator, createdBy: createdScope, readsAnsweredAbove: readsAnsweredAbove, isSettled: isSettled)
				}
			}
		}
	}
}

/// A scope whose generator `Scope.createScopeGenerator` is creating, with what the generator is created from once
/// the generators of the scopes it creates exist.
private struct ScopeGeneratorUnderConstruction {
	/// - Parameters:
	///   - concreteTypeStack: The concrete types of the scopes `propertyStack`'s properties are built for, beside it.
	///   - depthStack: The depth in the tree of the scope that put each entry of `propertyStack` on it, beside it.
	///   - depth: This scope's depth in the tree: 0 for the root, and one more than the scope that creates it otherwise.
	///   - fillPathStackCount: How many of the outermost entries of `propertyStack` are the path of the seam whose hole the
	///     enclosing fill fills (`SeamSignature.Hole.fillPropertyStack`): none outside a fill, and a nested fill's are its own.
	init(
		scope: ConstructionScope,
		property: Property?,
		propertyStack: [Property],
		concreteTypeStack: [TypeDescription],
		depthStack: [Int],
		depth: Int,
		fillPathStackCount: Int = 0,
		nearestDeclarations inheritedNearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		seamHoles: SeamHoles,
		sitePath: [Property],
		enclosingFills: [String: String] = [:],
		enclosingFillNames: GenerationWork.Shared<Set<String>> = .init([]),
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		startsCodeGeneration: Bool,
		validatesForwardedProperties: Bool,
		fill: Fill? = nil,
		buildsWithHandWrittenMocks: Bool = false,
		declaredTypeNames: DeclaredTypeNames,
		previousPassGenerator: ScopeGenerator?,
		cycleParameterContexts: [ScopeGenerator.BuiltDeclaration: CycleParameterContext],
		reboundProperties: Set<Property> = [],
		placeHoldingPropertiesByType: [TypeDescription: Set<Property>]? = nil,
	) {
		self.placeHoldingPropertiesByType = placeHoldingPropertiesByType
		self.depth = depth
		// Every read of the context this scope inherits goes through `context`, logged, so a construction memo can tell
		// whether another place inherits a context that answers the reads of this scope's subtree alike (see
		// `ConstructionMemo`).
		var log = ConstructionLog()
		let context = ConstructionContext(
			propertyStack: propertyStack,
			concreteTypeStack: concreteTypeStack,
			depthStack: depthStack,
			nearestDeclarations: inheritedNearestDeclarations,
			cycleParameterContexts: cycleParameterContexts,
		)
		var childPropertyStack = propertyStack
		var childConcreteTypeStack = concreteTypeStack
		var childDepthStack = depthStack
		// The index on `propertyStack` of the declaration this scope repeats when it closes a cycle.
		var closedOnDeclarationIndex: Int?
		// The declarations this scope's own dependencies are read from: those enclosing it, with every form of its own
		// property being built.
		var nearestDeclarations = inheritedNearestDeclarations.changed(atDepth: depth)
		if let property {
			// A scope closes a cycle where validation finds one: it repeats a declaration of the same property, as cycle
			// validation sees it (a lazily instantiated property as the constant it stands for), built for the same
			// concrete type. A lazily instantiated declaration's instance is on the stack just inside the declaration.
			let concreteType = scope.instantiable.concreteInstantiable
			let closedOn = context.declarationClosedOn(by: property, concreteType: concreteType)
			log.record(.declarationClosedOn(property, concreteType), answer: .declarationClosedOn(closedOn?.declaration), depth: closedOn?.depth ?? -1)
			closedOnDeclarationIndex = closedOn?.index
			childPropertyStack.insert(property, at: 0)
			childConcreteTypeStack.insert(concreteType, at: 0)
			childDepthStack.insert(depth, at: 0)
			if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
				childPropertyStack.insert(instanceProperty, at: 0)
				childConcreteTypeStack.insert(concreteType, at: 0)
				childDepthStack.insert(depth, at: 0)
			}
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
		let closedOnDeclaration = closedOnDeclarationIndex.map {
			ScopeGenerator.BuiltDeclaration(property: propertyStack[$0], concreteType: scope.instantiable.concreteInstantiable)
		}
		let isPropertyCycle = closedOnDeclaration != nil
		self.fillPathStackCount = fillPathStackCount
		let fillPathStart = propertyStack.count - fillPathStackCount
		// How many declarations of the fill's path lie beneath the one this scope closes on, when it closes on one: generation's
		// own finding, which the check of a fill reads instead of working the membership out again. A lazily instantiated
		// declaration's instance is its own entry of the stack, and no declaration.
		closedOnFillPathDeclarationsBeneath = closedOnDeclarationIndex.flatMap { index in
			index >= fillPathStart ? (fillPathStart..<index).count(where: { !(propertyStack.indices.contains($0 + 1) && propertyStack[$0 + 1].asLazilyInstantiatedInstanceProperty == propertyStack[$0]) }) : nil
		}
		// The parameters of this scope's builder function that the pass before found, when a lazy cycle closes on it,
		// or those of the function a cycle-closing scope refers to. Nearly every scope has neither.
		let ownCycleParameters = if !isPropertyCycle, property != nil {
			previousPassGenerator?.foundCycleParameters ?? []
		} else {
			[CycleParameter]()
		}
		let closedOnContext = closedOnDeclaration.flatMap { closedOnDeclaration in
			let context = cycleParameterContexts[closedOnDeclaration]
			log.record(.cycleParameterContext(closedOnDeclaration), answer: .cycleParameterContext(context?.parameters), depth: context?.depth ?? -1)
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
			where !parameter.isRequired && Self.binding(of: parameter.property, in: nearestDeclarations, log: &log) == nil
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
		/// of its label (see `NearestDeclarations.binding(of:)`).
		func binding(of property: Property) -> Property? {
			scope.createdBinding(of: property) ?? Self.binding(of: property, in: nearestDeclarations, log: &log)
		}
		var unavailableOptionalProperties = Set<Property>()
		var aliasBindings = [Property: Property]()
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				break
			case let .received(onlyIfAvailable):
				if onlyIfAvailable, binding(of: dependency.property) == nil {
					unavailableOptionalProperties.insert(dependency.property)
				}
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				// An `onlyIfAvailable` alias is always declared: bound to its fulfilling property where a form of it is
				// available, and to `nil` otherwise. The type declaring it is passed the alias either way.
				guard onlyIfAvailable else { break }
				if let aliasBinding = binding(of: fulfillingProperty) {
					aliasBindings[dependency.property] = aliasBinding
				} else {
					unavailableOptionalProperties.insert(fulfillingProperty)
				}
			}
		}
		self.unavailableOptionalProperties = unavailableOptionalProperties
		self.aliasBindings = aliasBindings
		self.scope = scope
		self.property = property
		// A scope that closes a cycle creates no children.
		propertiesToGenerate = isPropertyCycle ? [] : scope.propertiesToGenerate
		self.childPropertyStack = childPropertyStack
		self.childConcreteTypeStack = childConcreteTypeStack
		self.childDepthStack = childDepthStack
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		self.childLazilyInstantiatedInstanceProperties = childLazilyInstantiatedInstanceProperties
		self.previousPassGenerator = previousPassGenerator
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
			} else {
				childNearestDeclarations.replaceLabels(of: declaredPropertyForms)
			}
		}
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
		self.startsCodeGeneration = startsCodeGeneration
		self.validatesForwardedProperties = validatesForwardedProperties
		self.buildsWithHandWrittenMocks = buildsWithHandWrittenMocks
		// A scope that closes a cycle calls no seam; any other seam call passes a builder for each of the seam's holes. A
		// call inside a fill of a seam that holds the fill's site, or that passes the site's builder up, passes that fill
		// by name, so every instance of the seam calls the same fills with its own scopes.
		self.enclosingFills = enclosingFills
		self.enclosingFillNames = enclosingFillNames
		holeArguments = isPropertyCycle ? [] : scope.holeArguments
		// The call's own fills are those no enclosing call fills, and its own dispatchers those no enclosing call declares. One
		// pass names both, fills first, then dispatchers, apart from what encloses the call: the
		// fills and dispatchers enclosing it, and the names the seam whose tree holds it binds for its builders, which a call
		// inside it passes by name and which a closer declaration would shadow.
		var fillsOfThisCall = [(fill: Fill, scope: ConstructionScope)]()
		var dispatchersOfThisCall = [ScopeGenerator.FillDispatcher]()
		var namesOfThisCall = GeneratedNameAllocator(reserving: [])
		let builderKeysDispatchedOverTheEnum: Set<SeamSignature.ScopeEnum.Key> = if let calledBuilders = scope.calledBuilders {
			ScopeGeneratorUnderConstruction.builderKeysHandedInEnumForm(byCallsInside: holeArguments, calling: calledBuilders)
		} else {
			[]
		}
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
			for case let .fill(hole, _) in holeArguments where hole.enumPlace != nil {
				placesByCaseKey[ScopeGenerator.fillCaseKey(of: hole), default: []].append(hole)
			}
			// A place inside a fill of an inner seam's builder reads, through the scope value the inner seam handed that fill, a
			// label that some route of the inner seam's enum holds and another does not: on that other route inline reads the
			// caller's declaration, as for a label one place of the case carries and another does not.
			let innerScopeReaders = scope.calledBuilders.map { InnerScopeReaders(enumsByKey: $0.enumsByKey, nameByKey: [:]) }
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
			// (`parameterField(of:reading:)`). It reads nothing of its own scope through the root dispatcher: a route on which
			// no type binds the value passes the place up.
			if scope.publicMockCall != nil {
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
					caseFields.callerReadLabels = []
					caseFieldsByCaseKey[caseKey] = caseFields
				}
			}
			var functionNameByCaseKey = [String: String]()
			for case let .fill(hole, fulfillingScope) in holeArguments where enclosingFills[ScopeGenerator.fillKey(of: hole)] == nil {
				let key = ScopeGenerator.fillKey(of: hole)
				let caseKey = ScopeGenerator.fillCaseKey(of: hole)
				if let functionName = functionNameByCaseKey[caseKey] {
					fillNames[key] = functionName
					fillsOfThisCall.append((Fill(hole: hole, key: key, functionName: functionName, fields: hole.fields, emitsCode: false, caseHoles: [hole]), fulfillingScope))
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
				fill.innerScopeParameter = Self.innerScopeParameter(ofFillOf: hole, seamHoles: seamHoles, callPath: callPath)
				fillsOfThisCall.append((fill, fulfillingScope))
			}
			if let calledBuilders = scope.calledBuilders {
				dispatchersOfThisCall = ScopeGenerator.FillDispatcher.dispatchers(
					of: calledBuilders,
					filledSites: Self.filledSites(of: holeArguments),
					sitesPassedUpOnSomeRoute: scope.publicMockCall?.sitesPassedUpOnSomeRoute ?? [],
					enclosingDispatchers: enclosingFills,
					builderKeysDispatchedOverTheEnum: builderKeysDispatchedOverTheEnum,
					fillNames: fillNames,
					names: &names,
					innerScopeNameByKey: Dictionary(calledBuilders.scopeEnums.compactMap { scopeEnum in
						seamHoles.innerScope(at: callPath, innerKey: scopeEnum.key).map { (scopeEnum.key, $0.name) }
					}, uniquingKeysWith: { first, _ in first }),
					decidesPerRoute: scope.publicMockCall != nil,
				)
			}
			// A fill a level function calls of an instantiator's place returns the builder its wrapper keeps.
			for index in fillsOfThisCall.indices where fillsOfThisCall[index].fill.hole.property.propertyType.isAnyInstantiator {
				let key = fillsOfThisCall[index].fill.key
				fillsOfThisCall[index].fill.returnsWrapperBuilder = dispatchersOfThisCall.contains { dispatcher in
					dispatcher.returnsBuilderStruct && dispatcher.cases.contains { $0.target?.key == key }
				}
			}
		}
		self.fillsOfThisCall = fillsOfThisCall
		self.dispatchersOfThisCall = dispatchersOfThisCall
		self.namesOfThisCall = namesOfThisCall
		self.builderKeysDispatchedOverTheEnum = builderKeysDispatchedOverTheEnum
		// Gathered once for the call, not once for each of its fills, each of which is handed all of them: gathered for each
		// fill, a call's fills grew with the square of the places of the seam it calls.
		var enclosingFillsOfThisCall = enclosingFills
		if !holeArguments.isEmpty {
			for (fill, _) in fillsOfThisCall {
				enclosingFillsOfThisCall[fill.key] = fill.functionName
			}
			for dispatcher in dispatchersOfThisCall {
				enclosingFillsOfThisCall[dispatcher.key] = dispatcher.functionName
			}
			GenerationWork.record(enclosingFillsOfThisCall.count, by: .gatheringFillsOfACall)
		}
		self.enclosingFillsOfThisCall = GenerationWork.Shared(enclosingFillsOfThisCall)
		// The names of those fills, which a call inside one of them avoids, gathered once for the call's fills to share.
		if fillsOfThisCall.isEmpty {
			enclosingFillNamesOfThisCall = enclosingFillNames
		} else {
			enclosingFillNamesOfThisCall = GenerationWork.Shared(Set(enclosingFillsOfThisCall.values))
			GenerationWork.record(enclosingFillsOfThisCall.count, by: .gatheringFillsOfACall)
		}
		childGenerators.reserveCapacity(propertiesToGenerate.count + fillsOfThisCall.count)
		self.log = log
		// A fill, a scope inside one, and every scope of a tree with holes read context the log does not cover.
		isMemoizable = fill == nil && enclosingFills.isEmpty && seamHoles.isEmpty && seamRoot == nil && mockBuilders == nil && holeArguments.isEmpty
	}

	/// The binding a receive of `property` only if available reads, among `nearestDeclarations`, logged in `log`.
	private static func binding(of property: Property, in nearestDeclarations: NearestDeclarations, log: inout ConstructionLog) -> Property? {
		let (binding, depth) = nearestDeclarations.resolvingBinding(of: property)
		log.record(.binding(property), answer: .binding(binding), depth: depth)
		return binding
	}

	/// This scope's depth in the tree (see `init`).
	let depth: Int
	/// What this scope and the scopes beneath it whose generators exist read of the context above them (see
	/// `ConstructionMemo`).
	private(set) var log: ConstructionLog
	/// Whether this scope's generator may be stored in a construction memo, or reuse one stored there: neither it nor a
	/// scope beneath it is a fill, is inside one, or is in a tree with holes.
	private(set) var isMemoizable: Bool

	/// The enum keys of `calledBuilders`' builders that take a builder struct, of each hole type a call inside the trees of
	/// `holeArguments`' fills reaches the called seam's enum of through a builder that takes a closure over its own enum: a
	/// seam that passes up the called seam's place, whose case carries the called seam's enum. That call reuses this call's
	/// dispatchers over the enum, which hand a fill what a case on the way carries, as a builder struct's level hands it;
	/// a dispatcher of its own could not, since the fill is this call's. So this call keeps them over the enum, and hands
	/// the called seam the struct of their conversion.
	private static func builderKeysHandedInEnumForm(byCallsInside holeArguments: [ConstructionScope.HoleArgument], calling calledBuilders: CalledBuilders) -> Set<SeamSignature.ScopeEnum.Key> {
		let structKeys = calledBuilders.builders.filter(\.takesBuilderStruct).map(\.enumKey)
		guard !structKeys.isEmpty else { return [] }
		var keys = Set<SeamSignature.ScopeEnum.Key>()
		var visited = Set<ObjectIdentifier>()
		var scopesToVisit = holeArguments.compactMap { argument -> ConstructionScope? in
			guard case let .fill(_, scope) = argument else { return nil }
			return scope
		}
		while let scope = scopesToVisit.popLast() {
			guard visited.insert(ObjectIdentifier(scope.identity)).inserted else { continue }
			if let innerBuilders = scope.calledBuilders {
				let innerEnumsByKey = innerBuilders.enumsByKey
				var reachedKeys = Set<SeamSignature.ScopeEnum.Key>()
				var keysToVisit = innerBuilders.builders.filter { !$0.takesBuilderStruct }.map(\.enumKey)
				while let key = keysToVisit.popLast() {
					guard reachedKeys.insert(key).inserted else { continue }
					keysToVisit += innerEnumsByKey[key]?.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:)) ?? []
				}
				for key in structKeys where reachedKeys.contains(where: { $0.seamType == key.seamType && $0.holeType == key.holeType }) {
					keys.insert(key)
				}
				for case let .fill(_, fillScope) in scope.holeArguments {
					scopesToVisit.append(fillScope)
				}
			}
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
				scopesToVisit.append(childScope)
			}
		}
		return keys
	}

	/// A fill of a seam call: the hole it fills, its key (see `ScopeGenerator.fillKey(of:)`), and its function's name.
	struct Fill {
		let hole: SeamSignature.Hole
		let key: String
		let functionName: String
		/// The fields the fill can bind: its hole's, or every place's of a case nested by type, for the fill that generates
		/// the case's code.
		let fields: [SeamSignature.Hole.Field]
		/// Whether the fill's code is generated (see `ScopeGenerator.fillEmitsCode`).
		let emitsCode: Bool
		/// The places the fill stands for: its hole, or, for the fill that generates the code of a case nested by type, every
		/// place of the case, in builder order.
		let caseHoles: [SeamSignature.Hole]
		/// For the fill that generates the code of a case nested by type, the labels of `fields` that a level holds on some
		/// route to the case and none holds on another, where the root dispatcher hands the fill the caller's declaration
		/// (see `ScopeGenerator.caseFields(of:)`).
		var callerReadLabels = Set<String>()
		/// The labels of the fields of the hole's struct the fill binds from the struct (see `fillUnderConstruction`):
		/// every field but one bound from a deferred parameter, which the fill reads from the caller's scope.
		var boundLabels = Set<String>()
		/// The declarations enclosing the call, which the root dispatcher reads the values of `callerReadLabels` from.
		var callerNearestDeclarations = NearestDeclarations()
		/// The received properties in scope at the call only as the instance of a `LazilyInstantiated` property.
		var callerLazilyInstantiatedInstanceProperties = Set<Property>()
		/// For a fill of a builder whose fills lead to a place of the seam whose tree makes the call, the scope value the inner
		/// seam handed it, as the parameter the fill takes it under where its tree builds such a place or a call that passes one
		/// up (`SeamHoles.innerScope(at:innerKey:)`).
		var innerScopeParameter: SeamSignature.Hole.Field?
		/// Whether the fill is a member of a level function, a dispatcher that returns its enum's builder struct, and fills an
		/// instantiator's place: it then returns the builder the wrapper keeps, which takes the forwarded value itself, rather
		/// than the value it builds (`ScopeGenerator.fillReturnsWrapperBuilder`).
		var returnsWrapperBuilder = false
	}

	/// The parameter a fill of `hole` takes the scope value the seam whose tree holds `hole` handed it under, for the call at
	/// `callPath`, where a place inside a fill of a place of that seam's enum reads it, or `nil`.
	private static func innerScopeParameter(ofFillOf hole: SeamSignature.Hole, seamHoles: SeamHoles, callPath: [Property]) -> SeamSignature.Hole.Field? {
		guard let innerScope = seamHoles.innerScope(at: callPath, innerKey: SeamSignature.ScopeEnum.rootKey(of: hole)) else { return nil }
		return SeamSignature.Hole.Field(
			property: Property(label: innerScope.name, typeDescription: innerScope.enumType),
			access: .public,
			declaringType: hole.scopeSeamType,
			declarationLocation: nil,
		)
	}

	/// The generators created so far for `propertiesToGenerate`, in order, followed by those of `fillsOfThisCall`.
	private(set) var childGenerators = [ScopeGenerator]() {
		didSet {
			if let lastGenerator = childGenerators.last, childGenerators.count > oldValue.count {
				childGeneratorIdentifiers.insert(ObjectIdentifier(lastGenerator))
			}
		}
	}

	/// The identities of `childGenerators`, none of which a child of this scope reuses (see `ConstructionMemo`).
	private(set) var childGeneratorIdentifiers = Set<ObjectIdentifier>()
	/// How many scopes this scope's subtree has so far: itself, and every scope created beneath it. An alias or a hole,
	/// which generates a line or two, is not counted.
	private(set) var subtreeScopeCount = 1
	/// The generators among `childGenerators` whose code starts early only if this scope's subtree is large (see
	/// `startsCodeBeneathALargeSubtree`).
	private var childGeneratorsStartingBeneathALargeSubtree = [ScopeGenerator]()

	/// The smallest subtree, in scopes, whose root starts generating its code as soon as the tree exists, and starts the
	/// code of each small subtree directly beneath it as well. Every other scope's code starts when the scope above it asks
	/// for it, on a task created then and released once the code is done. A running task holds its code's async frames, so
	/// where scopes wait on one another, as in #646's graphs of instantiators, starting every scope's code at once ran most
	/// of the tree's frames together; a small subtree's scopes now run one after another, as each is asked for, while large
	/// subtrees, and the small subtrees beneath each, still generate in parallel.
	///
	/// Measured with release builds, median of three runs, against every scope starting early: #646's 16 screens peaked at
	/// 727 MB with 16, 634 MB with 64 and 639 MB with 256, rather than 1,054 MB, and took 2.43, 2.53 and 2.63 s rather than
	/// 2.62 s; a tree of 265,000 lines took 1.54, 1.52 and 1.57 s rather than 1.66 s, at the same peak. The runs cannot tell
	/// 64 from 256. 64 is the smaller, so a module of trees between 64 and 255 scopes still generates them in parallel.
	static let scopeCountOfLargeSubtree = 64

	/// Adds `childGenerator`, the generator `child` created, to this scope's children.
	/// - Parameters:
	///   - readsAnsweredAbove: `child.readsAnsweredAbove`.
	///   - isSettled: `child.isSettled(building: childGenerator)`.
	mutating func add(childGenerator: ScopeGenerator, createdBy child: ScopeGeneratorUnderConstruction, readsAnsweredAbove: ConstructionLog, isSettled: Bool) {
		childGenerators.append(childGenerator)
		subtreeScopeCount += child.subtreeScopeCount
		if child.startsCodeBeneathALargeSubtree {
			childGeneratorsStartingBeneathALargeSubtree.append(childGenerator)
		}
		log.formUnion(readsAnsweredAbove)
		if !isSettled {
			childrenAreSettled = false
		}
		if !child.isMemoizable {
			isMemoizable = false
		}
	}

	/// Adds the generator another place built, which `reuse` found, to this scope's children, as the child it builds
	/// (see `ConstructionMemo`). The child is no fill and is in no fill, so it may start its code early exactly where a
	/// child of this scope may.
	mutating func add(reusing reuse: ConstructionMemo.Reuse) {
		childGenerators.append(reuse.entry.generator)
		subtreeScopeCount += reuse.entry.subtreeScopeCount
		if mayStartCodeEarly, reuse.entry.subtreeScopeCount < Self.scopeCountOfLargeSubtree {
			childGeneratorsStartingBeneathALargeSubtree.append(reuse.entry.generator)
		}
		log.formUnion(reuse.reads)
		if !reuse.entry.isSettled {
			childrenAreSettled = false
		}
	}

	/// Whether every child this scope created or reused found everywhere in its subtree what it read from the pass before
	/// (see `ConstructionMemo.Entry.isSettled`).
	private var childrenAreSettled = true

	/// Whether `generator`, this scope's, found everywhere in its subtree what its build read from the pass before: its
	/// children did, and it found the cycle parameters and loops of builders the pass before's generator for the place
	/// found, spelled alike.
	func isSettled(building generator: ScopeGenerator) -> Bool {
		childrenAreSettled && ConstructionMemo.foundAlike(by: generator, asBy: previousPassGenerator)
	}

	/// What this scope's subtree read of the context above this scope (see `ConstructionMemo`).
	var readsAnsweredAbove: ConstructionLog {
		log.reads(answeredAbove: depth)
	}

	/// The key this scope's generator is stored under once it exists, or `nil` for a root, a fill, or a scope the memo does
	/// not cover (see `memoKey(ofChildBuilding:as:erasedToConcreteExistential:)`).
	var memoKey: ConstructionMemo.Key?

	/// How many generators the pass had started or collected when this scope's build began (see `createScopeGenerator`'s
	/// `startLog`).
	var startLogIndex = 0

	/// Whether this scope's generator may start its code as soon as its tree exists, rather than when the scope above it
	/// asks for it: a scope of a dependency tree that generates code (no mock's, no fill's, nor a tree built only to find a
	/// seam's signature). It does when its subtree is large, or when the subtree of the scope above it is.
	private var mayStartCodeEarly: Bool {
		!forMockGeneration && startsCodeGeneration && fill == nil
	}

	/// Whether this scope's generator starts its code early only when the subtree of the scope above it is large: its own
	/// subtree is small.
	private var startsCodeBeneathALargeSubtree: Bool {
		mayStartCodeEarly && subtreeScopeCount < Self.scopeCountOfLargeSubtree
	}

	/// The next of `propertiesToGenerate` to create a generator for, or `nil` once every one has its generator.
	mutating func nextPropertyToGenerate() -> ConstructionScope.PropertyToGenerate? {
		guard nextPropertyIndex < propertiesToGenerate.count else { return nil }
		let propertyToGenerate = propertiesToGenerate[nextPropertyIndex]
		nextPropertyIndex += 1
		return propertyToGenerate
	}

	/// The next of `fillsOfThisCall` to create a generator for, once every one of `propertiesToGenerate` has its
	/// generator, or `nil` once every fill has its generator.
	mutating func nextFill() -> (fill: Fill, scope: ConstructionScope)? {
		guard nextFillIndex < fillsOfThisCall.count else { return nil }
		let fill = fillsOfThisCall[nextFillIndex]
		nextFillIndex += 1
		return fill
	}

	/// The scope under construction for the property a fill of this scope's seam call builds: the scope of the type
	/// that fulfills the hole in the caller's declarations, built with the stack the seam whose tree holds the site
	/// reaches it with, and with the fields of the site's scope struct in scope beside what encloses the call.
	func fillUnderConstruction(fill: Fill, scope: ConstructionScope) throws -> ScopeGeneratorUnderConstruction {
		var fill = fill
		let hole = fill.hole
		try validateForwardedProperties(of: hole.property, declaredAt: hole.declarationLocation, on: hole.ownerType, seeingThroughModulesNamed: hole.declaringModuleNames, building: scope.instantiable)
		// A field bound from a parameter the seam defers holds the seam's memo of what the call passed, which is the
		// declaration of its label in the caller's scope: the fill reads that declaration, as inline, so the value is
		// created when the tree reads it. Except where a call inside a fill of this call passes this fill on beneath
		// another declaration of the label (see `ScopeGenerator.fillDeferredLabelsHiddenByReenteringCalls`): the fill,
		// one function, reads the struct's field there, which the pass before found.
		let deferredLabelsBoundFromStruct = previousPassGenerator?.fillDeferredLabelsHiddenByReenteringCalls[fill.key] ?? []
		let boundFields = fill.fields.filter { !$0.isDeferredParameter || deferredLabelsBoundFromStruct.contains($0.property.label) }
		fill.boundLabels = Set(boundFields.map(\.property.label))
		fill.callerNearestDeclarations = childNearestDeclarations
		fill.callerLazilyInstantiatedInstanceProperties = childLazilyInstantiatedInstanceProperties
		let fields = boundFields.map(\.property)
		let fieldLabels = Set(fields.map(\.label))
		var fieldInstanceProperties = Set<Property>()
		// A value the fill takes from the caller's scope is available as it would be to a pass-through of the call: one
		// the caller's path is still building is not, so a receive of it only if available is passed `nil`. Each field
		// the fill binds hides every declaration of its label in the caller's scope.
		var fillNearestDeclarations = childNearestDeclarations
		for field in fields {
			fillNearestDeclarations.replace(field, providing: CycleParameter.forms(providedBy: field))
			if let instanceProperty = field.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				fieldInstanceProperties.insert(instanceProperty)
			}
		}
		return ScopeGeneratorUnderConstruction(
			scope: scope,
			property: hole.property,
			propertyStack: hole.fillPropertyStack,
			concreteTypeStack: hole.fillConcreteTypeStack,
			// The fill's stack is the path of the seam whose tree holds the site, put on it above this tree.
			depthStack: hole.fillPropertyStack.map { _ in -1 },
			depth: depth + 1,
			fillPathStackCount: hole.fillPropertyStack.count,
			nearestDeclarations: fillNearestDeclarations,
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties.filter { !fieldLabels.contains($0.label) }.union(fieldInstanceProperties),
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath + hole.pathBeforePropertyInItsFill,
			enclosingFills: GenerationWork.taking(enclosingFillsOfThisCall, by: .gatheringFillsOfACall),
			enclosingFillNames: enclosingFillNamesOfThisCall,
			erasedToConcreteExistential: hole.erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			fill: fill,
			// A fill a mock declares builds the hole's tree as the mock's tree built inline would.
			buildsWithHandWrittenMocks: forMockGeneration,
			declaredTypeNames: declaredTypeNames,
			// The pass before created a fill's generator around the generator of the property it builds. A fill is a
			// function of its own, declared where the seam is called, so no function enclosing the call that a lazy cycle
			// closes on encloses a cycle-closing scope in the fill. The fill's own built scope takes the parameters the
			// pass before found for it as any scope does, when a lazy cycle inside the fill closes on its property.
			previousPassGenerator: previousPassChildGenerator?.children.first,
			cycleParameterContexts: [:],
			// A place inside the fill is a place of the type the fill builds, whose builds start their children in its order.
			placeHoldingPropertiesByType: placeHoldingPropertiesByType,
		)
	}

	/// Creates the generator of a hole this scope's type instantiates, a site of the seam whose tree is generated.
	mutating func addHoleGenerator(property: Property, erasedToConcreteExistential: Bool) {
		// A hole's generator holds the whole path to it (its owner's stacks), which the memo's log does not cover: a tree
		// built only to find a seam's or public mock's signature has holes but no `seamHoles`.
		isMemoizable = false
		childGenerators.append(ScopeGenerator(
			holeProperty: property,
			erasedToConcreteExistential: erasedToConcreteExistential,
			site: seamHoles.site(at: sitePath + [property]),
			ownerPropertyStack: childPropertyStack,
			ownerConcreteTypeStack: childConcreteTypeStack,
			ownerLazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
			// A seam that declares builder structs spells the `@Sendable` functions of its sites, too, `nonisolated`.
			sendableFunctionsAreNonisolated: seamHoles.declaresBuilderStructs,
		))
	}

	/// The scope under construction for a scope this one instantiates.
	func childUnderConstruction(
		scope: ConstructionScope,
		property: Property,
		erasedToConcreteExistential: Bool,
	) -> ScopeGeneratorUnderConstruction {
		ScopeGeneratorUnderConstruction(
			scope: scope,
			property: property,
			propertyStack: childPropertyStack,
			concreteTypeStack: childConcreteTypeStack,
			depthStack: childDepthStack,
			depth: depth + 1,
			fillPathStackCount: fillPathStackCount,
			nearestDeclarations: childNearestDeclarations,
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath,
			enclosingFills: enclosingFills,
			enclosingFillNames: enclosingFillNames,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			buildsWithHandWrittenMocks: buildsWithHandWrittenMocks,
			declaredTypeNames: declaredTypeNames,
			previousPassGenerator: previousPassChildGenerator,
			cycleParameterContexts: childCycleParameterContexts,
			// The loops the pass before found among this scope's children.
			reboundProperties: childReboundProperties,
			placeHoldingPropertiesByType: placeHoldingPropertiesByType,
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
	func memoKey(ofChildBuilding scope: ConstructionScope, as property: Property, erasedToConcreteExistential: Bool) -> ConstructionMemo.Key? {
		guard enclosingFills.isEmpty, seamHoles.isEmpty, fill == nil else { return nil }
		return ConstructionMemo.Key(
			scope: ObjectIdentifier(scope.identity),
			property: property,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			buildsWithHandWrittenMocks: buildsWithHandWrittenMocks,
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
			reboundProperties: childReboundProperties,
			spellings: Property.spellingsForConstructionMemo(of: property, childLazilyInstantiatedInstanceProperties, childReboundProperties),
			previousPassGenerator: previousPassChildGenerator.map(ObjectIdentifier.init),
		)
	}

	/// The context each scope this scope instantiates inherits (see `ConstructionContext`).
	var childContext: ConstructionContext {
		ConstructionContext(
			propertyStack: childPropertyStack,
			concreteTypeStack: childConcreteTypeStack,
			depthStack: childDepthStack,
			nearestDeclarations: childNearestDeclarations,
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
		childGenerators.append(ScopeGenerator(
			property: property,
			fulfillingProperty: fulfillingProperty,
			// An alias that keeps the label of the dependency it retypes is not in scope where its
			// own value is read, so it does not shadow a lazily instantiated property further up the tree.
			fulfillingPropertyIsLazilyInstantiatedInstance: (
				fulfillingProperty.label == property.label
					? lazilyInstantiatedInstanceProperties
					: childLazilyInstantiatedInstanceProperties,
			).contains(fulfillingProperty.asUnwrappedProperty),
			unavailableOptionalProperties: unavailableOptionalProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable,
			// The declared property an `onlyIfAvailable` alias is bound from decides whether its value may be `nil`: a
			// parameter made optional, a seam's optional parameter, or an optional property the alias reads in place of
			// its fulfilling property's non-optional form.
			fulfillingBindingIsOptional: aliasBindings[property]?.typeDescription.isOptional ?? false,
			// A seam's own alias that keeps the label of a deferred parameter is bound from the parameter's autoclosure.
			fulfillingExpression: self.property == nil && fulfillingProperty.label == property.label
				? seamRoot?.autoclosureCallByLabel(of: scope.instantiable)[property.label]
				: nil,
			declarationReference: declarationReference,
		))
	}

	/// What `fill`, which generates the code of a case nested by type, reads of the caller's scope through the root
	/// dispatcher, given `child`, the generator of what it builds: for each label a level holds on some route to the case
	/// and none holds on another, each form `child`'s tree reads of it, which the fill receives from the scopes enclosing
	/// the call as `child` would inline, so the caller builds a required one first; the parameter the fill takes for it,
	/// optional where no read requires it, so a route on which the caller declares none passes `nil`; and the argument the
	/// root dispatcher passes: the caller's declaration of the parameter's form, its instance where the caller holds it
	/// lazily, or `nil`.
	private static func callerReads(of fill: Fill, child: ScopeGenerator, log: inout ConstructionLog) -> ScopeGenerator.FillCallerReads {
		var reads = ScopeGenerator.FillCallerReads()
		// The inner scope, only where the fill's tree builds a place or a call that passes one up, whose case carries it.
		if let innerScopeParameter = fill.innerScopeParameter, child.containsBuildSite || child.passesUpBuilder {
			reads.innerScopeParameters = [innerScopeParameter]
		}
		for field in fill.fields where fill.callerReadLabels.contains(field.property.label) && fill.boundLabels.contains(field.property.label) {
			let label = field.property.label
			// No site inside the fill carries the field: a site carries the values of the levels inside the fill
			// (`ScopeGenerator.fieldsCarried(by:)`), and each level leaves out of what its sites carry the labels it declares,
			// which leaves only a label a level carries without declaring it: a member of a loop of builders its function wraps
			// again, which the scope that builds the loop declares, a scope inside the fill, since a fill's own generator finds
			// no loops; or a parameter a lazy cycle closes on, whose declaration is inside the fill, since a cycle a fill closes
			// on a declaration of the seam's tree is an error (`FillFinding.Kind.closesCycleInSeamTree`).
			let forms = Set(child.receivedProperties.filter { $0.label == label })
			guard !forms.isEmpty else { continue }
			func isRequired(_ form: Property) -> Bool {
				child.requiredReceivedProperties.contains(form)
			}
			let parameter = forms.contains(where: isRequired) || field.property.typeDescription.isOptional
				? field
				: field.withProperty(field.property.asOptionalProperty)
			reads.parameterByLabel[label] = parameter
			for form in forms.sorted() {
				reads.dependencies.append(Dependency(property: form, source: .received(onlyIfAvailable: !isRequired(form))))
				if !isRequired(form), binding(of: form, in: fill.callerNearestDeclarations, log: &log) == nil {
					reads.unavailableProperties.insert(form)
				}
			}
			reads.argumentByLabel[label] = if let binding = binding(of: parameter.property, in: fill.callerNearestDeclarations, log: &log) {
				!parameter.property.propertyType.isLazilyInstantiated
					&& (binding.propertyType.isLazilyInstantiated || fill.callerLazilyInstantiatedInstanceProperties.contains(parameter.property.asUnwrappedProperty))
					? "\(label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
					: label
			} else {
				"nil"
			}
		}
		return reads
	}

	/// The field a public mock caller's fill of a case nested by type takes for one label, given `fields`, the case's places'
	/// fields of that label in place order, and `reads`, the forms of it the fill's tree receives: the form it reads that
	/// provides every other (`CycleParameter.forms(providedBy:)`, the relation the per-place decision `holesFilled` fills
	/// by), else the first place's field that provides every form it reads. So a route whose nearest type binds a form
	/// that provides it fills the place, and every other route passes the place up, as the per-place decision does. `nil`
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

	/// The sites of the places a call whose builders `holeArguments` are fills.
	private static func filledSites(of holeArguments: [ConstructionScope.HoleArgument]) -> Set<SeamSignature.Hole.Site> {
		Set(holeArguments.compactMap { holeArgument in
			if case let .fill(hole, _) = holeArgument {
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
	private func builderCallArguments(fillNames: [String: String]) -> [ScopeGenerator.BuilderCallArgument] {
		guard let calledBuilders = scope.calledBuilders, !holeArguments.isEmpty else { return [] }
		let filledSites = Self.filledSites(of: holeArguments)
		let enumsByKey = calledBuilders.enumsByKey
		let holesBySite = Dictionary(calledBuilders.holes.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
		// A seam's caller calls the initializer only generated code calls, under its prefixed labels; a public mock's
		// caller passes each builder by the leaf's argument of its label, and passes up the places its builder's routes
		// reach that it fills on some route only (`PublicMockCall.sitesPassedUpOnSomeRoute`).
		let isPublicMockCall = scope.publicMockCall != nil
		let sitesFilledOnEveryRoute = scope.publicMockCall?.sitesFilledOnEveryRoute ?? filledSites
		// A builder struct's levels a call converts through are functions named apart from the call's fills and dispatchers.
		var names = namesOfThisCall
		return calledBuilders.builders.map { builder in
			let builtType = calledBuilders.holes.first { $0.holeType == builder.enumKey.holeType }?.builtType ?? builder.enumKey.holeType.builtType
			let label = isPublicMockCall ? builder.label : builder.generatedOnlyArgumentLabel
			let enumKey = builder.enumKey
			let reachedSites = isPublicMockCall
				? calledBuilders.sitesReachedOnItsRoutes(by: builder, in: enumsByKey)
				: SeamSignature.ScopeEnum.sitesReached(from: enumKey, in: enumsByKey)
			// In a tree built to compute the signature, which generates nothing, the case is not settled yet.
			let route = seamHoles.routeCase(at: sitePath, innerKey: enumKey)
			guard !reachedSites.isDisjoint(with: filledSites) else {
				// A seam that takes a builder struct is handed one whose members hand this seam's builder the case of this seam's
				// enum that carries the called seam's, as the closure over the called seam's enum does.
				guard builder.takesBuilderStruct else {
					return .init(label: label, value: route.map { route in "{ \(route.call(handing: "$0")) }" } ?? "")
				}
				guard let route else { return .init(label: label, value: "") }
				let conversion = ScopeGenerator.builderStructConversion(ofEnumOf: enumKey, enumsByKey: enumsByKey, holesBySite: holesBySite, builtType: builtType, reservedNames: seamHoles.namesBoundForBuilders, names: &names, handing: route.call(handing:))
				return .init(label: label, value: conversion.value, declarations: conversion.declarations)
			}
			// A seam that takes a builder struct is handed the struct its root level's function returns, but where a case of the
			// seam whose tree makes the call carries the scope value the call hands its fills, whose dispatchers keep their enum
			// form to pass it on, or an enclosing call declares those dispatchers in that form, which this call reuses: it is
			// then handed a struct whose members hand the dispatcher the case.
			let returnsBuilderStruct = builder.takesBuilderStruct && !calledBuilders.builders.contains { calledBuilder in
				calledBuilder.enumKey.holeType == enumKey.holeType
					&& (seamHoles.innerScope(at: sitePath, innerKey: calledBuilder.enumKey) != nil
						|| enclosingFills[ScopeGenerator.FillDispatcher.key(of: calledBuilder.enumKey)] != nil
						|| builderKeysDispatchedOverTheEnum.contains(calledBuilder.enumKey))
			}
			let dispatcherKey = ScopeGenerator.FillDispatcher.key(of: enumKey, returnsBuilderStruct: returnsBuilderStruct)
			let dispatcher = fillNames[dispatcherKey] ?? ""
			// What the call refers to by name: the enclosing dispatcher, whatever expression passes it.
			let enclosingFill = enclosingFills[dispatcherKey] == nil ? nil : ScopeGenerator.BuilderCallArgument.EnclosingFill(key: dispatcherKey, name: dispatcher)
			guard reachedSites.isSubset(of: sitesFilledOnEveryRoute) else {
				// The whole scope the call was given goes up, under the route's case.
				let passUp = route.map { route in route.call(handing: "scope") } ?? "\(builder.label)(scope)"
				return .init(label: label, value: "{ scope in \(dispatcher)(scope, \(ScopeGenerator.FillDispatcher.passUpParameterName): { \(passUp) }) }", enclosingFill: enclosingFill, isSendable: enumKey.isSendable)
			}
			guard builder.takesBuilderStruct else {
				return .init(label: label, value: dispatcher, enclosingFill: enclosingFill, isSendable: enumKey.isSendable)
			}
			guard !returnsBuilderStruct else {
				return .init(label: label, value: "\(dispatcher)()", enclosingFill: enclosingFill, isSendable: enumKey.isSendable)
			}
			let conversion = ScopeGenerator.builderStructConversion(ofEnumOf: enumKey, enumsByKey: enumsByKey, holesBySite: holesBySite, builtType: builtType, reservedNames: seamHoles.namesBoundForBuilders.union([dispatcher]), names: &names) { "\(dispatcher)(\($0))" }
			return .init(label: label, value: conversion.value, declarations: conversion.declarations, enclosingFill: enclosingFill, isSendable: enumKey.isSendable)
		}
	}

	/// Creates the scope's generator once `childGenerators` holds a generator for each of `propertiesToGenerate`, and starts
	/// its code, or adds it to `generatorsToStart` when that is not `nil`.
	/// - Parameter startedGenerators: The generators whose code the pass started or collected, which grows by those this
	///   scope starts or collects: a generator several places share starts once.
	/// - Parameter startLog: Every generator the pass started or collected, in order, which grows as `startedGenerators` does.
	mutating func scopeGenerator(collectingGeneratorsToStartInto generatorsToStart: inout [ScopeGenerator]?, startedGenerators: inout Set<ObjectIdentifier>, startLog: inout [ScopeGenerator]) -> ScopeGenerator {
		// Every fill this call passes is an enclosing call's or its own.
		let fillNames = holeArguments.isEmpty ? [:] : GenerationWork.taking(enclosingFillsOfThisCall, by: .gatheringFillsOfACall)
		let builtGenerator = ScopeGenerator(
			instantiable: scope.instantiable,
			property: property,
			propertiesToGenerate: childGenerators,
			// A scope that closes a cycle creates no children.
			propertiesToDeclare: isPropertyCycle ? [] : scope.propertiesToDeclare,
			unavailableOptionalProperties: unavailableOptionalProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			forwardedLazilyInstantiatedInstanceProperties: scope.forwardedLazilyInstantiatedInstanceProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			isPropertyCycle: isPropertyCycle,
			closedOnDeclaration: closedOnDeclaration,
			closedOnFillPathDeclarationsBeneath: closedOnFillPathDeclarationsBeneath,
			builtInlineSeamComment: scope.builtInlineSeamComment,
			seamCall: scope.seamCall,
			publicMockCall: scope.publicMockCall,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			holeCallArguments: holeArguments.map { holeArgument in
				switch holeArgument {
				case let .fill(hole, _):
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
			builderCallArguments: builderCallArguments(fillNames: fillNames),
			fillDispatchers: dispatchersOfThisCall,
			// A place a public mock's caller fills on some route only is passed up too.
			passedUpHoles: holeArguments.compactMap { holeArgument in
				switch holeArgument {
				case let .passUp(hole):
					hole
				case let .fill(hole, _):
					scope.publicMockCall?.sitesPassedUpOnSomeRoute.contains(hole.site) == true ? hole : nil
				}
			},
			valuesBindings: seamHoles.valuesBindings(at: sitePath),
			memberCallsInsideFunction: seamHoles.memberCallsInsideFunction(at: sitePath),
			sendableFunctionsAreNonisolated: seamHoles.declaresBuilderStructs,
			isBuiltByFill: fill != nil,
			fillReturnsWrapperBuilder: fill?.returnsWrapperBuilder ?? false,
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
			namesBoundBySeam: GenerationWork.taking(seamHoles.namesBoundBySeam, by: .joiningNamesBoundBySeam),
			placeHoldingProperties: placeHoldingPropertiesByType.map { $0[scope.instantiable.concreteInstantiable] ?? [] },
		)
		let scopeGenerator = if let fill {
			ScopeGenerator(
				fill: fill.hole,
				key: fill.key,
				functionName: fill.functionName,
				boundLabels: fill.boundLabels,
				fields: fill.fields,
				caseHoles: fill.caseHoles,
				emitsCode: fill.emitsCode,
				callerReads: Self.callerReads(of: fill, child: builtGenerator, log: &log),
				returnsWrapperBuilder: fill.returnsWrapperBuilder,
				child: builtGenerator,
			)
		} else {
			builtGenerator
		}
		// A large subtree starts its own code and that of each small subtree directly beneath it. The code of every other
		// scope starts when the scope above it, or the caller of a small tree's root, asks for it.
		if subtreeScopeCount >= Self.scopeCountOfLargeSubtree {
			var generatorsStartingNow = childGeneratorsStartingBeneathALargeSubtree
			if mayStartCodeEarly {
				generatorsStartingNow.append(scopeGenerator)
			}
			for generator in generatorsStartingNow where startedGenerators.insert(ObjectIdentifier(generator)).inserted {
				startLog.append(generator)
				if generatorsToStart != nil {
					generatorsToStart?.append(generator)
				} else {
					Self.startCodeGeneration(of: generator)
				}
			}
		}
		return scopeGenerator
	}

	/// Kicks off the generation of `scopeGenerator`'s code, which a later request for the code reads from its cache.
	static func startCodeGeneration(of scopeGenerator: ScopeGenerator) {
		CodeTaskStart.record()
		// A detached task inherits no task-local, so the work observer of the task that starts the code is handed on: the
		// code a later request reads from the cache then counts its work whichever task asks for it first.
		if let observer = GenerationWork.observer {
			_ = Task.detached {
				try await GenerationWork.$observer.withValue(observer) {
					try await scopeGenerator.generateCode()
				}
			}
		} else {
			_ = Task.detached {
				try await scopeGenerator.generateCode()
			}
		}
	}

	private let scope: ConstructionScope
	/// The scope this place builds.
	var builtScope: ConstructionScope {
		scope
	}

	private let property: Property?
	/// Whether this scope is in the tree of a fill a mock declares, whose types are built as the mock's tree built
	/// inline builds them: each with its hand-written mock where `mockReturnTypeIsCompatible` says the mock builds it.
	private let buildsWithHandWrittenMocks: Bool
	/// Whether the tree checks each erased instantiator against the type it builds (see `createScopeGenerator`).
	private let validatesForwardedProperties: Bool
	private let propertiesToGenerate: [ConstructionScope.PropertyToGenerate]
	/// The index in `propertiesToGenerate` of the next property to create a generator for.
	private var nextPropertyIndex = 0
	private let childPropertyStack: [Property]
	/// The concrete types of the scopes `childPropertyStack`'s properties are built for, beside it (see
	/// `init(scope:property:propertyStack:concreteTypeStack:…)`).
	private let childConcreteTypeStack: [TypeDescription]
	/// The depth of the scope that put each entry of `childPropertyStack` on it, beside it.
	private let childDepthStack: [Int]
	/// See `init(scope:property:propertyStack:concreteTypeStack:fillPathStackCount:…)`.
	private let fillPathStackCount: Int
	/// See `ScopeGenerator.closedOnFillPathDeclarationsBeneath`.
	private let closedOnFillPathDeclarationsBeneath: Int?
	/// The received properties in scope only as the instance of a `LazilyInstantiated` property, where this scope's type
	/// is constructed: inside its builder function, whose parameters a lazy cycle closes on hide every other declaration
	/// of their labels.
	private let lazilyInstantiatedInstanceProperties: Set<Property>
	/// `lazilyInstantiatedInstanceProperties` where this scope's builder function is called, which its parameters do
	/// not hide.
	private let callSiteLazilyInstantiatedInstanceProperties: Set<Property>
	private let childLazilyInstantiatedInstanceProperties: Set<Property>
	private let unavailableOptionalProperties: Set<Property>
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
	private let fillsOfThisCall: [(fill: Fill, scope: ConstructionScope)]
	/// The enum keys of the called seam's builders that take a builder struct whose dispatchers this call keeps over the
	/// enum, for a call inside its fills that reuses them (`builderKeysHandedInEnumForm(byCallsInside:calling:)`).
	private let builderKeysDispatchedOverTheEnum: Set<SeamSignature.ScopeEnum.Key>
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
	/// The index in `fillsOfThisCall` of the next fill to create a generator for.
	private var nextFillIndex = 0
	private let erasedToConcreteExistential: Bool
	private let isPropertyCycle: Bool
	/// The declaration this scope repeats when it closes a cycle (see `ScopeGenerator.closedOnDeclaration`), or `nil`.
	private let closedOnDeclaration: ScopeGenerator.BuiltDeclaration?
	private let forMockGeneration: Bool
	private let startsCodeGeneration: Bool
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
		let forwardedProperties = builtInstantiable.forwardedProperties
		guard propertyType.isErasedInstantiator,
		      !forwardedProperties.isEmpty,
		      let forwardedArgument = generics?.first
		else { return true }
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
		let forwardedProperties = builtInstantiable.forwardedProperties
		guard propertyType.isErasedInstantiator,
		      !forwardedProperties.isEmpty,
		      let forwardedArgument = generics?.first
		else { return true }
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
struct SeamHoles {
	/// No holes: a tree that is not a seam's, or a seam's tree without holes.
	init() {
		seamType = nil
		routeCasesByCall = [:]
		sitesByPath = [:]
		passedUpHolesBySite = [:]
		valuesBindingsByPath = [:]
		memberCallsInsideFunctionByPath = [:]
		innerScopesByCall = [:]
		namesBoundForBuilders = []
		namesBoundForDeferredParameters = []
		declaresBuilderStructs = false
		namesBoundBySeam = GenerationWork.Shared([])
	}

	init(seamType: TypeDescription, holes: [SeamSignature.Hole], builders: [SeamSignature.Builder], parameters: [SeamSignature.Parameter] = [], callRoutes: [SeamSignature.CallRoute] = []) {
		var routeCasesByCall = [RouteCall: RouteCase]()
		let internalNameByEnum = Dictionary(builders.map { ($0.enumKey, $0.internalName) }, uniquingKeysWith: { first, _ in first })
		// The payload of each case that wraps another on the way to a place or a call nested by type, bound just before the
		// case's property is built, once however many places it leads to. A case of a `@Sendable` enum carries none. A call's
		// case for a builder it fills carries the scope value the inner seam handed the fill, which the fill takes.
		var valuesBindingsByName = [[Property]: [String: ValuesBinding]]()
		var innerScopesByCall = [RouteCall: SeamSignature.Hole.RouteStep.InnerScope]()
		// Where the enums declare builder structs, each case on a route is a member call on the struct the step before it
		// returned, the root's builder's for the first, bound before the step's property, or at the top of its builder
		// function (`RouteStep.Member`). A route's steps lead to one place, so each step's parent is a fact of its path.
		func bindValues(of route: [SeamSignature.Hole.RouteStep], rootBuilderName: String) {
			var parentName = rootBuilderName
			for step in route {
				if let innerScope = step.innerScope {
					innerScopesByCall[RouteCall(sitePath: innerScope.callPath, innerKey: innerScope.innerKey)] = innerScope
				}
				if let member = step.member {
					valuesBindingsByName[member.bindingPath, default: [:]][member.bindingName] = ValuesBinding(member: member, parentName: parentName, caseName: step.caseName)
					parentName = member.bindingName
				} else if let values = step.values {
					valuesBindingsByName[values.bindingPath, default: [:]][values.bindingName] = ValuesBinding(values: values)
				}
			}
		}
		/// The cases that lead to a place or a call's case, each opened, and what closes them.
		func opening(_ route: [SeamSignature.Hole.RouteStep]) -> String {
			route.map { step in ".\(step.caseName)(\(step.leadingArguments)" }.joined()
		}
		for callRoute in callRoutes {
			guard let builderName = internalNameByEnum[callRoute.rootKey] else { continue }
			bindValues(of: callRoute.route, rootBuilderName: builderName)
			// The call's own case holds only the inner enum: no value of the calling type, so nothing it binds is captured by the
			// builder the called type holds.
			routeCasesByCall[RouteCall(sitePath: callRoute.sitePath, innerKey: callRoute.innerKey)] = RouteCase(
				builderName: builderName,
				prefix: opening(callRoute.route) + ".\(callRoute.caseName)(",
				suffix: String(repeating: ")", count: callRoute.route.count + 1),
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
				bindValues(of: enumPlace.route, rootBuilderName: hole.internalName)
			}
		}
		namesBoundForBuilders.formUnion(innerScopesByCall.values.map(\.name))
		self.innerScopesByCall = innerScopesByCall
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
			valuesBindingsByPath[path] = orderedBindings.filter { !$0.isCalledInsideFunction }
		}
		self.memberCallsInsideFunctionByPath = memberCallsInsideFunctionByPath
		declaresBuilderStructs = builders.contains(where: \.takesBuilderStruct)
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
	/// function, where a payload of the type's level is built (`MockParameterNode.valuesBindings`). A field of a
	/// `LazilyInstantiated` a public mock binds under a name apart, beside the instance it takes under the label, is read
	/// under the name `lazilyInstantiatedBindingNames` gives it by label and wrapper type where the wrapper is in scope: the
	/// mock's root level holds the wrapper (`DependencyTreeGenerator.PublicMockRootLevel`).
	static func valuesArguments(
		of fields: [SeamSignature.Hole.Field],
		readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property> = [],
		bindingNamesPassedByName: [String: String] = [:],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:],
	) -> String {
		fields.map { field in
			let label = field.property.label
			let name = bindingNamesPassedByName[label] ?? lazilyInstantiatedBindingNames[label]?[field.property.typeDescription] ?? label
			let value = if !field.isDeferredParameter, lazilyInstantiatedInstanceProperties.contains(field.property.asUnwrappedProperty) {
				"\(name).\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else {
				name
			}
			return "\(label.spelledAsArgumentLabel): \(value)"
		}.joined(separator: ", ")
	}

	/// A case's payload the seam's tree binds just before the builder function of a property on a route to a place nested
	/// by type: its binding's name, its struct's type and its fields.
	///
	/// Where the case's enum declares a builder struct, the binding is the struct the case's member returns, called on the
	/// struct `memberCall`'s parent name is bound to, with the payload.
	struct ValuesBinding: Sendable {
		init(values: SeamSignature.Hole.RouteStep.Values) {
			bindingName = values.bindingName
			type = values.type
			fields = values.fields
			memberCall = nil
			isCalledInsideFunction = false
		}

		init(member: SeamSignature.Hole.RouteStep.Member, parentName: String, caseName: String) {
			bindingName = member.bindingName
			type = member.valuesType
			fields = member.fields
			memberCall = (parentName, caseName)
			isCalledInsideFunction = member.isCalledInsideFunction
		}

		let bindingName: String
		let type: TypeDescription
		let fields: [SeamSignature.Hole.Field]
		/// The struct the member is called on, by name, and the member, or `nil` for a payload the case carries.
		let memberCall: (parentName: String, caseName: String)?
		/// Whether the member is called at the top of the builder function of the binding's property, not before it.
		let isCalledInsideFunction: Bool

		/// The line that binds the payload, each field read as
		/// `valuesArguments(of:readingInstancesOf:bindingNamesPassedByName:lazilyInstantiatedBindingNames:)` reads it.
		func line(readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property>, bindingNamesPassedByName: [String: String] = [:], lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:]) -> String {
			let payload = "\(type.asSource)(\(SeamHoles.valuesArguments(of: fields, readingInstancesOf: lazilyInstantiatedInstanceProperties, bindingNamesPassedByName: bindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)))"
			return if let memberCall {
				"let \(bindingName) = \(memberCall.parentName).\(memberCall.caseName)(\(payload))"
			} else {
				"let \(bindingName) = \(payload)"
			}
		}
	}

	/// How a call hands an inner enum up: the builder that takes it, and what wraps the inner value in the builder's enum.
	struct RouteCase {
		let builderName: String
		/// What precedes the inner value: the case that holds it, after each case that leads there.
		let prefix: String
		/// What closes the cases `prefix` opens.
		let suffix: String

		/// The call of the builder with `innerValue` wrapped.
		func call(handing innerValue: String) -> String {
			"\(builderName)(\(prefix)\(innerValue)\(suffix))"
		}
	}

	/// The name of every builder the seam's generated initializer takes, inside the initializer, which a call its tree
	/// makes passes up by name, and of each payload its tree binds. Empty outside a seam's tree.
	let namesBoundForBuilders: Set<String>
	/// The name each deferred parameter of the seam's generated initializer binds its autoclosure to, which the
	/// initializer's body reads. Empty outside a seam's tree, and in a public mock's.
	let namesBoundForDeferredParameters: Set<String>
	/// Whether a builder of the seam takes a builder struct, so its tree spells every `@Sendable` local function it declares
	/// `@Sendable nonisolated`, as a builder struct's `@Sendable` member is called at the top of one.
	let declaresBuilderStructs: Bool
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
	/// to them, take it under, and its type.
	func innerScope(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key) -> SeamSignature.Hole.RouteStep.InnerScope? {
		innerScopesByCall.isEmpty ? nil : innerScopesByCall[RouteCall(sitePath: sitePath, innerKey: innerKey)]
	}

	/// A seam call in the tree and the inner enum it carries.
	private struct RouteCall: Hashable {
		let sitePath: [Property]
		let innerKey: SeamSignature.ScopeEnum.Key
	}

	/// The seam whose tree is generated, or `nil` for a tree that is no seam's.
	private let seamType: TypeDescription?
	private let routeCasesByCall: [RouteCall: RouteCase]
	private let sitesByPath: [[Property]: SeamSignature.Hole]
	private let passedUpHolesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]
	private let valuesBindingsByPath: [[Property]: [ValuesBinding]]
	private let memberCallsInsideFunctionByPath: [[Property]: [ValuesBinding]]
	private let innerScopesByCall: [RouteCall: SeamSignature.Hole.RouteStep.InnerScope]
}

// MARK: - NearestDeclarations

/// The nearest declaration of a label on the path from a tree's root to a scope, as `Scope.createScopeGenerator` judges
/// what a scope receives only if available against it: each form the declaration provides, with the declared property
/// that binds it, and the forms of the label being built between that declaration and the scope.
struct NearestDeclaration: Equatable, Sendable {
	/// Each form the declaration provides (see `CycleParameter.forms(providedBy:)`), mapped to the declared property a
	/// reader of that form is handed: the property itself, the optional property a parameter made optional binds, or
	/// the `LazilyInstantiated` whose instance a by-value form reads.
	var bindings = [Property: Property]() {
		didSet { identity = Identity(bindings: bindings, formsBeingBuilt: formsBeingBuilt) }
	}

	/// The forms of the label being built between the declaration and the scope: a receive of one of them reads a
	/// declaration that is not built yet.
	var formsBeingBuilt = Set<Property>() {
		didSet { identity = Identity(bindings: bindings, formsBeingBuilt: formsBeingBuilt) }
	}

	/// Whether `other` is this declaration, unchanged since one was copied from the other: then it holds the same
	/// properties, spelled alike, which a construction memo compares for every read it answers again.
	func isUnchangedCopy(of other: Self) -> Bool {
		identity === other.identity
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		guard !lhs.isUnchangedCopy(of: rhs) else { return true }
		return lhs.identity.contentHash == rhs.identity.contentHash && lhs.bindings == rhs.bindings && lhs.formsBeingBuilt == rhs.formsBeingBuilt
	}

	/// Made anew by every change, and copied with the declaration. It holds a hash of the declaration's content, which
	/// declarations `==` equates share, so that two that differ are told apart without comparing their properties: a
	/// construction memo compares many declarations that differ.
	private final class Identity: Sendable {
		init(bindings: [Property: Property], formsBeingBuilt: Set<Property>) {
			var hasher = Hasher()
			hasher.combine(bindings)
			hasher.combine(formsBeingBuilt)
			contentHash = hasher.finalize()
		}

		let contentHash: Int
	}

	private var identity = Identity(bindings: [:], formsBeingBuilt: [])
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
			enclosingLayers = enclosingLayer.map { [$0] } ?? []
		}

		deinit {
			var enclosingLayers = [Layer]()
			swap(&enclosingLayers, &self.enclosingLayers)
			DeferredRelease.release(consume enclosingLayers)
		}

		let declarations: [String: NearestDeclaration]
		/// The depth in the tree of the scope that made these declarations, or -1 for those the tree was given.
		let depth: Int

		/// The layer this one is enclosed by, if any.
		var enclosingLayer: Layer? {
			enclosingLayers.first
		}

		/// `enclosingLayer`, held in an array `deinit` hands to `DeferredRelease`. Mutated only by `deinit`, which has the
		/// only access.
		nonisolated(unsafe) private var enclosingLayers: [Layer]
	}

	/// The declarations shared with the scopes above, nearest first.
	private var enclosingLayer: Layer?
	/// The declarations changed since `enclosingLayer`, which hide those of their labels there.
	private var changedDeclarations = [String: NearestDeclaration]()
	/// The depth in the tree of the scope making `changedDeclarations`, or -1 before the tree's root changes them.
	private var changedDepth = -1

	/// Makes `nearestDeclaration` the nearest declaration of `label`.
	private mutating func set(_ nearestDeclaration: NearestDeclaration, for label: String) {
		changedDeclarations[label] = nearestDeclaration
	}
}

extension NearestDeclarations {
	/// The declarations a mock root's tree is enclosed by: each of `boundProperties`, the received properties the mock
	/// binds, in `Property` order, each form bound to the first property that provides it. The mock binds each form once
	/// and names every binding apart, so no binding hides another.
	static func binding(_ boundProperties: some Collection<Property>) -> Self {
		var nearestDeclarations = Self()
		for boundProperty in boundProperties.sorted() {
			nearestDeclarations.join(boundProperty, providing: CycleParameter.forms(providedBy: boundProperty))
		}
		return nearestDeclarations.sharingDeclarations()
	}

	/// The binding a receive of `property` only if available reads, or `nil` when the property is unavailable: the
	/// first of `property.formsReadByOnlyIfAvailableReceive` that the nearest declaration of its label binds, unless a
	/// form it reads is still being built between that declaration and the receiver.
	func binding(of property: Property) -> Property? {
		resolvingBinding(of: property).binding
	}

	/// `binding(of:)`, with the depth of the scope that made the nearest declaration of `property`'s label the nearest
	/// (see `resolving(_:)`).
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
