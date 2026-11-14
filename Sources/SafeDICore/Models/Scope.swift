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

	/// The builders the call `seamCall` or `publicMockCall` stands for passes, or `nil` for a scope that builds its type.
	var calledBuilders: CalledBuilders? {
		seamCall?.calledBuilders ?? publicMockCall?.calledBuilders
	}

	/// The properties that this scope is responsible for instantiating.
	var propertiesToGenerate = [PropertyToGenerate]()

	/// For a scope that calls a seam (`seamCall`) or another module's public mock (`publicMockCall`), how the call passes
	/// each place the builders it passes reach, in the order they reach them. Empty for every other scope.
	var holeArguments = [HoleArgument]()

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
	fileprivate lazy var declaredLabels = Set(declaredProperties.map(\.label))

	/// The by-value properties with which the scopes this scope builds receive the instance of a lazily
	/// instantiated property this scope declares. A mock root can declare a property itself and also be given
	/// a promoted lazily instantiated property with the same label. Types that receive the property by value
	/// are then built with the root's own. Read only once `propertiesToGenerate` is complete.
	fileprivate lazy var declaredLazilyInstantiatedInstanceProperties = Set(
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
	///
	/// The tree is created again while a scope that a lazy cycle closes on finds other parameters for its builder
	/// function than it was created with (see `CycleParameter`): its cycle-closing scopes, created before it, pass
	/// those parameters, and count what they pass among the properties they receive. Nearly every tree has no such
	/// scope and is created once. A pass changes a scope's parameters only through the parameters of the functions it
	/// is nested in or that are nested in it, which only add to what it receives or declares, so the passes end once
	/// the parameters at each level of nesting have settled. The first pass starts each generator's code as the
	/// generator is created, since nearly every tree takes one pass; a later pass starts none until the passes end,
	/// and then only the last pass's, since nothing reads the code of a pass that is not the last.
	func createScopeGenerator(
		for property: Property?,
		nearestDeclarations: NearestDeclarations = [:],
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot? = nil,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool = false,
		startsCodeGeneration: Bool = true,
		validatesForwardedProperties: Bool = true,
		declaredTypeNames: DeclaredTypeNames,
	) throws -> ScopeGenerator {
		var previousPassGenerator: ScopeGenerator?
		var scopeGenerator: ScopeGenerator
		var generatorsToStart: [ScopeGenerator]?
		repeat {
			if previousPassGenerator != nil {
				generatorsToStart = []
			}
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
			)
			previousPassGenerator = scopeGenerator
		} while scopeGenerator.cycleParametersChangedInTree || scopeGenerator.fillStructBoundLabelsChangedInTree || scopeGenerator.receivedBuilderLoopsChangedInTree
		for generator in generatorsToStart ?? [] {
			ScopeGeneratorUnderConstruction.startCodeGeneration(of: generator)
		}
		return scopeGenerator
	}

	/// One pass of `createScopeGenerator`, which reads the parameters of the builder functions lazy cycles close on
	/// from `previousPassGenerator`, the tree the pass before created, or finds none when there is no pass before.
	/// - Parameter generatorsToStart: `nil` to start each generator's code as it is created, or where to collect the
	///   generators whose code to start, in the order they are created.
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
	) throws -> ScopeGenerator {
		var scopeGeneratorsUnderConstruction = [ScopeGeneratorUnderConstruction(
			scope: self,
			property: property,
			propertyStack: [],
			concreteTypeStack: [],
			nearestDeclarations: nearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			seamRoot: seamRoot,
			mockBuilders: mockBuilders,
			seamHoles: seamRoot.map { SeamHoles(seamType: instantiable.concreteInstantiable, holes: $0.signature.holes, builders: $0.signature.builders, scopeEnums: $0.signature.scopeEnums) }
				?? mockBuilders.map { SeamHoles(seamType: instantiable.concreteInstantiable, holes: $0.holes, builders: $0.builders, scopeEnums: $0.scopeEnums) }
				?? SeamHoles(),
			sitePath: [],
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			declaredTypeNames: declaredTypeNames,
			previousPassGenerator: previousPassGenerator,
			cycleParameterContexts: [:],
		)]
		while true {
			let index = scopeGeneratorsUnderConstruction.count - 1
			if let propertyToGenerate = scopeGeneratorsUnderConstruction[index].nextPropertyToGenerate() {
				switch propertyToGenerate {
				case let .instantiated(property, scope, erasedToConcreteExistential):
					try scopeGeneratorsUnderConstruction.append(scopeGeneratorsUnderConstruction[index].childUnderConstruction(
						scope: scope,
						property: property,
						erasedToConcreteExistential: erasedToConcreteExistential,
					))
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
				let scopeGenerator = scopeGeneratorsUnderConstruction.removeLast().scopeGenerator(collectingGeneratorsToStartInto: &generatorsToStart)
				if scopeGeneratorsUnderConstruction.isEmpty {
					return scopeGenerator
				} else {
					scopeGeneratorsUnderConstruction[scopeGeneratorsUnderConstruction.count - 1].childGenerators.append(scopeGenerator)
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
	///   - fillPathStackCount: How many of the outermost entries of `propertyStack` are the path of the seam whose hole the
	///     enclosing fill fills (`SeamSignature.Hole.fillPropertyStack`): none outside a fill, and a nested fill's are its own.
	init(
		scope: Scope,
		property: Property?,
		propertyStack: [Property],
		concreteTypeStack: [TypeDescription],
		fillPathStackCount: Int = 0,
		nearestDeclarations inheritedNearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		seamHoles: SeamHoles,
		sitePath: [Property],
		enclosingFills: [String: String] = [:],
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
	) {
		var childPropertyStack = propertyStack
		var childConcreteTypeStack = concreteTypeStack
		// The index on `propertyStack` of the declaration this scope repeats when it closes a cycle.
		var closedOnDeclarationIndex: Int?
		// The declarations this scope's own dependencies are read from: those enclosing it, with every form of its own
		// property being built.
		var nearestDeclarations = inheritedNearestDeclarations
		if let property {
			// A scope closes a cycle where validation finds one: it repeats a declaration of the same property, as cycle
			// validation sees it (a lazily instantiated property as the constant it stands for), built for the same
			// concrete type.
			let validatedProperty = property.asValidatedForDependencyCycles
			let concreteType = scope.instantiable.concreteInstantiable
			let closedOnEntryIndex = propertyStack.indices.first {
				propertyStack[$0].asValidatedForDependencyCycles == validatedProperty && concreteTypeStack[$0] == concreteType
			}
			// A lazily instantiated declaration's instance is on the stack just inside the declaration.
			closedOnDeclarationIndex = closedOnEntryIndex.map { index in
				propertyStack.indices.contains(index + 1) && propertyStack[index + 1].asLazilyInstantiatedInstanceProperty == propertyStack[index] ? index + 1 : index
			}
			childPropertyStack.insert(property, at: 0)
			childConcreteTypeStack.insert(concreteType, at: 0)
			if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
				childPropertyStack.insert(instanceProperty, at: 0)
				childConcreteTypeStack.insert(concreteType, at: 0)
			}
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
		let closedOnContext = closedOnDeclaration.flatMap { cycleParameterContexts[$0] }
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
			where !parameter.isRequired && nearestDeclarations.binding(of: parameter.property) == nil
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
			scope.createdBinding(of: property) ?? nearestDeclarations.binding(of: property)
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
			let declaredProperties = scope.declaredProperties.sorted()
			if property == nil {
				for declaredProperty in declaredProperties {
					childNearestDeclarations.join(declaredProperty, providing: CycleParameter.forms(providedBy: declaredProperty))
				}
			} else {
				childNearestDeclarations.replaceLabels(of: declaredProperties)
			}
		}
		self.childNearestDeclarations = childNearestDeclarations
		// The functions enclosing the scopes this scope builds that lazy cycles close on, by the property each builds:
		// this scope's own, and those enclosing this scope. Nearly every scope is beneath no such function.
		var childCycleParameterContexts = isPropertyCycle ? [:] : cycleParameterContexts
		if let property, !ownCycleParameters.isEmpty {
			childCycleParameterContexts[ScopeGenerator.BuiltDeclaration(property: property, concreteType: scope.instantiable.concreteInstantiable)] = CycleParameterContext(parameters: ownCycleParameters)
		}
		self.childCycleParameterContexts = childCycleParameterContexts
		self.seamRoot = seamRoot
		self.mockBuilders = mockBuilders
		self.seamHoles = seamHoles
		self.declaredTypeNames = declaredTypeNames
		// The path is kept only where a hole needs it: a site, and the stage calls of a staged builder, are found by it.
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
		holeArguments = isPropertyCycle ? [] : scope.holeArguments
		// The call's own fills are those no enclosing call fills, and its own dispatchers those no enclosing call declares. One
		// pass names both, fills and their later stages first, then dispatchers, apart from what encloses the call: the
		// fills and dispatchers enclosing it, and the names the seam whose tree holds it binds for its builders, which a call
		// inside it passes by name and which a closer declaration would shadow.
		var fillsOfThisCall = [(fill: Fill, scope: Scope)]()
		var dispatchersOfThisCall = [ScopeGenerator.FillDispatcher]()
		if !holeArguments.isEmpty {
			var names = GeneratedNameAllocator(reserving: Set(enclosingFills.values).union(seamHoles.namesBoundForBuilders))
			var fillNames = enclosingFills
			for case let .fill(hole, fulfillingScope) in holeArguments where enclosingFills[ScopeGenerator.fillKey(of: hole)] == nil {
				let functionName = names.claim(ScopeGenerator.fillFunctionName(of: hole), occupying: { name in
					hole.stages.indices.map { hole.stageFunctionName(at: $0, ofFunctionNamed: name) }
				})
				let key = ScopeGenerator.fillKey(of: hole)
				fillNames[key] = functionName
				fillsOfThisCall.append((Fill(hole: hole, key: key, functionName: functionName), fulfillingScope))
			}
			if let calledBuilders = scope.calledBuilders {
				dispatchersOfThisCall = ScopeGenerator.FillDispatcher.dispatchers(
					of: calledBuilders,
					filledSites: Self.filledSites(of: holeArguments),
					enclosingDispatchers: enclosingFills,
					fillNames: fillNames,
					names: &names,
				)
			}
		}
		self.fillsOfThisCall = fillsOfThisCall
		self.dispatchersOfThisCall = dispatchersOfThisCall
		childGenerators.reserveCapacity(propertiesToGenerate.count + fillsOfThisCall.count)
	}

	/// A fill of a seam call: the hole it fills, its key (see `ScopeGenerator.fillKey(of:)`), and its function's name.
	struct Fill {
		let hole: SeamSignature.Hole
		let key: String
		let functionName: String
		/// The labels of the fields of the hole's struct the fill binds from the struct (see `fillUnderConstruction`):
		/// every field but one bound from a deferred parameter, which the fill reads from the caller's scope.
		var boundLabels = Set<String>()
	}

	/// The generators created so far for `propertiesToGenerate`, in order, followed by those of `fillsOfThisCall`.
	var childGenerators = [ScopeGenerator]()

	/// The next of `propertiesToGenerate` to create a generator for, or `nil` once every one has its generator.
	mutating func nextPropertyToGenerate() -> Scope.PropertyToGenerate? {
		guard nextPropertyIndex < propertiesToGenerate.count else { return nil }
		let propertyToGenerate = propertiesToGenerate[nextPropertyIndex]
		nextPropertyIndex += 1
		return propertyToGenerate
	}

	/// The next of `fillsOfThisCall` to create a generator for, once every one of `propertiesToGenerate` has its
	/// generator, or `nil` once every fill has its generator.
	mutating func nextFill() -> (fill: Fill, scope: Scope)? {
		guard nextFillIndex < fillsOfThisCall.count else { return nil }
		let fill = fillsOfThisCall[nextFillIndex]
		nextFillIndex += 1
		return fill
	}

	/// The scope under construction for the property a fill of this scope's seam call builds: the scope of the type
	/// that fulfills the hole in the caller's declarations, built with the stack the seam whose tree holds the site
	/// reaches it with, and with the fields of the site's scope struct in scope beside what encloses the call.
	func fillUnderConstruction(fill: Fill, scope: Scope) throws -> ScopeGeneratorUnderConstruction {
		var fill = fill
		let hole = fill.hole
		try validateForwardedProperties(of: hole.property, declaredAt: hole.declarationLocation, on: hole.ownerType, seeingThroughModulesNamed: hole.declaringModuleNames, building: scope.instantiable)
		// A field bound from a parameter the seam defers holds the seam's memo of what the call passed, which is the
		// declaration of its label in the caller's scope: the fill reads that declaration, as inline, so the value is
		// created when the tree reads it. Except where a call inside a fill of this call passes this fill on beneath
		// another declaration of the label (see `ScopeGenerator.fillDeferredLabelsHiddenByReenteringCalls`): the fill,
		// one function, reads the struct's field there, which the pass before found.
		let deferredLabelsBoundFromStruct = previousPassGenerator?.fillDeferredLabelsHiddenByReenteringCalls[fill.key] ?? []
		let boundFields = hole.stages.joined().filter { !$0.isDeferredParameter || deferredLabelsBoundFromStruct.contains($0.property.label) }
		fill.boundLabels = Set(boundFields.map(\.property.label))
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
			fillPathStackCount: hole.fillPropertyStack.count,
			nearestDeclarations: fillNearestDeclarations,
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties.filter { !fieldLabels.contains($0.label) }.union(fieldInstanceProperties),
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath + hole.pathBeforePropertyInItsFill,
			enclosingFills: enclosingFillsOfThisCall,
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
		)
	}

	/// Creates the generator of a hole this scope's type instantiates, a site of the seam whose tree is generated.
	mutating func addHoleGenerator(property: Property, erasedToConcreteExistential: Bool) {
		childGenerators.append(ScopeGenerator(
			holeProperty: property,
			erasedToConcreteExistential: erasedToConcreteExistential,
			site: seamHoles.site(at: sitePath + [property]),
			stageCalls: seamHoles.stageCalls(at: sitePath + [property]),
			ownerPropertyStack: childPropertyStack,
			ownerConcreteTypeStack: childConcreteTypeStack,
		))
	}

	/// The scope under construction for a scope this one instantiates.
	func childUnderConstruction(
		scope: Scope,
		property: Property,
		erasedToConcreteExistential: Bool,
	) throws -> ScopeGeneratorUnderConstruction {
		try validateForwardedProperties(
			of: property,
			declaredAt: self.scope.instantiable.dependencies.first(where: { $0.property == property })?.declarationLocation,
			on: self.scope.instantiable.concreteInstantiable,
			seeingThroughModulesNamed: [],
			building: scope.instantiable,
		)
		return ScopeGeneratorUnderConstruction(
			scope: scope,
			property: property,
			propertyStack: childPropertyStack,
			concreteTypeStack: childConcreteTypeStack,
			fillPathStackCount: fillPathStackCount,
			nearestDeclarations: childNearestDeclarations,
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath,
			enclosingFills: enclosingFills,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			validatesForwardedProperties: validatesForwardedProperties,
			buildsWithHandWrittenMocks: buildsWithHandWrittenMocks,
			declaredTypeNames: declaredTypeNames,
			previousPassGenerator: previousPassChildGenerator,
			cycleParameterContexts: childCycleParameterContexts,
			// The loops the pass before found among this scope's children.
			reboundProperties: previousPassGenerator?.receivedBuilderLoops.reboundPropertiesByChildIndex[childGenerators.count] ?? [],
		)
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

	/// The fills inside one of this scope's fills can refer to: those of enclosing calls, and every fill of this call.
	private var enclosingFillsOfThisCall: [String: String] {
		var fills = enclosingFills
		for (fill, _) in fillsOfThisCall {
			fills[fill.key] = fill.functionName
		}
		for dispatcher in dispatchersOfThisCall {
			fills[dispatcher.key] = dispatcher.functionName
		}
		return fills
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

	/// The sites of the places a call whose builders `holeArguments` are fills.
	private static func filledSites(of holeArguments: [Scope.HoleArgument]) -> Set<SeamSignature.Hole.Site> {
		Set(holeArguments.compactMap { holeArgument in
			if case let .fill(hole, _) = holeArgument {
				hole.site
			} else {
				nil
			}
		})
	}

	/// What the call this scope makes passes each builder: the fill of a staged place or the staged builder of the seam or
	/// public mock whose tree makes the call, and for an enum the dispatcher that fills it, a closure that hands the enum up
	/// in a case of an enum of the seam or public mock whose tree makes the call, or the dispatcher handed that closure,
	/// which it passes each place it does not fill: a seam's caller fills every place an enum reaches or none, a public
	/// mock's caller each place it can. An internal mock takes each builder it passes up as a parameter, which the call
	/// passes as its leaf's dependency of the builder's label: an empty value here, or the parameter called with the scope.
	private func builderCallArguments(fillNames: [String: String]) -> [ScopeGenerator.BuilderCallArgument] {
		guard let calledBuilders = scope.calledBuilders, !holeArguments.isEmpty else { return [] }
		let holeArgumentsBySite = Dictionary(holeArguments.map { ($0.hole.site, $0) }, uniquingKeysWith: { first, _ in first })
		let filledSites = Self.filledSites(of: holeArguments)
		let enumsByKey = calledBuilders.enumsByKey
		// A seam's caller calls the initializer only generated code calls, under its prefixed labels; a public mock's
		// caller passes each builder by the leaf's argument of its label.
		let isPublicMockCall = scope.publicMockCall != nil
		return calledBuilders.builders.map { builder in
			let label = isPublicMockCall ? builder.label : builder.generatedOnlyArgumentLabel
			switch builder.kind {
			case let .staged(site):
				guard let holeArgument = holeArgumentsBySite[site] else { return .init(label: label, value: "") }
				switch holeArgument {
				case let .fill(hole, _):
					let fillKey = ScopeGenerator.fillKey(of: hole)
					return .init(label: label, value: fillNames[fillKey] ?? ScopeGenerator.fillFunctionName(of: hole), enclosingFillKey: enclosingFills[fillKey] == nil ? nil : fillKey, isSendable: hole.isSendable)
				case let .passUp(hole):
					let takingBuilder = seamHoles.hole(taking: hole)?.internalName
					return .init(label: label, value: takingBuilder ?? (isPublicMockCall ? "" : hole.internalName))
				}
			case let .scopeEnum(enumKey):
				let reachedSites = SeamSignature.ScopeEnum.sitesReached(from: enumKey, in: enumsByKey)
				// In a tree built to compute the signature, which generates nothing, the case is not settled yet.
				let route = seamHoles.routeCase(at: sitePath, innerKey: enumKey)
				guard !reachedSites.isDisjoint(with: filledSites) else {
					return .init(label: label, value: route.map { route in "{ \(route.builderName)(.\(route.caseName)($0)) }" } ?? "")
				}
				let dispatcherKey = ScopeGenerator.FillDispatcher.key(of: enumKey)
				let dispatcher = fillNames[dispatcherKey] ?? ""
				let enclosingFillKey = enclosingFills[dispatcherKey] == nil ? nil : dispatcherKey
				guard reachedSites.isSubset(of: filledSites) else {
					// The whole scope the call was given goes up, under the route's case.
					let passUp = route.map { route in "\(route.builderName)(.\(route.caseName)(scope))" } ?? "\(builder.label)(scope)"
					return .init(label: label, value: "{ scope in \(dispatcher)(scope, \(ScopeGenerator.FillDispatcher.passUpParameterName): { \(passUp) }) }", enclosingFillKey: enclosingFillKey, isSendable: enumKey.isSendable)
				}
				return .init(label: label, value: dispatcher, enclosingFillKey: enclosingFillKey, isSendable: enumKey.isSendable)
			}
		}
	}

	/// Creates the scope's generator once `childGenerators` holds a generator for each of `propertiesToGenerate`, and starts
	/// its code, or adds it to `generatorsToStart` when that is not `nil`.
	func scopeGenerator(collectingGeneratorsToStartInto generatorsToStart: inout [ScopeGenerator]?) -> ScopeGenerator {
		// Every fill this call passes is an enclosing call's or its own.
		let fillNames = holeArguments.isEmpty ? [:] : enclosingFillsOfThisCall
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
			passedUpHoles: holeArguments.compactMap { holeArgument in
				if case let .passUp(hole) = holeArgument {
					hole
				} else {
					nil
				}
			},
			stageCalls: seamHoles.stageCalls(at: sitePath),
			isBuiltByFill: fill != nil,
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
		)
		let scopeGenerator = if let fill {
			ScopeGenerator(fill: fill.hole, key: fill.key, functionName: fill.functionName, boundLabels: fill.boundLabels, stageCalls: seamHoles.fillStageCalls(at: sitePath), child: builtGenerator)
		} else {
			builtGenerator
		}
		if !forMockGeneration, startsCodeGeneration, fill == nil {
			if generatorsToStart != nil {
				generatorsToStart?.append(scopeGenerator)
			} else {
				Self.startCodeGeneration(of: scopeGenerator)
			}
		}
		return scopeGenerator
	}

	/// Kicks off the generation of `scopeGenerator`'s code, which a later request for the code reads from its cache.
	static func startCodeGeneration(of scopeGenerator: ScopeGenerator) {
		_ = Task.detached {
			try await scopeGenerator.generateCode()
		}
	}

	private let scope: Scope
	private let property: Property?
	/// Whether this scope is in the tree of a fill a mock declares, whose types are built as the mock's tree built
	/// inline builds them: each with its hand-written mock where `mockReturnTypeIsCompatible` says the mock builds it.
	private let buildsWithHandWrittenMocks: Bool
	/// Whether the tree checks each erased instantiator against the type it builds (see `createScopeGenerator`).
	private let validatesForwardedProperties: Bool
	private let propertiesToGenerate: [Scope.PropertyToGenerate]
	/// The index in `propertiesToGenerate` of the next property to create a generator for.
	private var nextPropertyIndex = 0
	private let childPropertyStack: [Property]
	/// The concrete types of the scopes `childPropertyStack`'s properties are built for, beside it (see
	/// `init(scope:property:propertyStack:concreteTypeStack:…)`).
	private let childConcreteTypeStack: [TypeDescription]
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
	/// The holes of the seam whose tree is generated, by site, which the sites and the stage calls of staged builders
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
	private let holeArguments: [Scope.HoleArgument]
	/// The fills of `holeArguments` this scope's generator holds – those no enclosing call already fills – each with the
	/// scope of the type that fulfills its hole.
	private let fillsOfThisCall: [(fill: Fill, scope: Scope)]
	/// The dispatchers this scope's seam call declares – those no enclosing call declares – in the order the call's arguments
	/// first reach them.
	private let dispatchersOfThisCall: [ScopeGenerator.FillDispatcher]
	/// The fills enclosing this scope, by `ScopeGenerator.fillKey(of:)`, each with its function's name, which a call
	/// inside them of a seam that holds or passes up their site passes by name.
	private let enclosingFills: [String: String]
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
		// The forwarded argument is the same as `InstantiableName.ForwardedProperties`.
		return forwardedArgument == .nested(name: "ForwardedProperties", parentType: builtInstantiable.concreteInstantiable)
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
	/// are not one bare name: a mock takes a received property of such a tuple as a `mock()` parameter, as it did when
	/// SafeDI rejected a declaration of that tuple. Building it would remove the parameter that callers of the mock pass,
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
/// hole the seam passes up by the inner seam's hole it passes, and the stage calls of each staged builder by the path
/// of the `@Sendable` function before which they are made.
struct SeamHoles {
	/// No holes: a tree that is not a seam's, or a seam's tree without holes.
	init() {
		seamType = nil
		routeCasesByCall = [:]
		sitesByPath = [:]
		passedUpHolesBySite = [:]
		stageCallsByPath = [:]
		fillStageCallsByPath = [:]
		namesBoundForBuilders = []
	}

	init(seamType: TypeDescription, holes: [SeamSignature.Hole], builders: [SeamSignature.Builder], scopeEnums: [SeamSignature.ScopeEnum]) {
		var routeCasesByCall = [RouteCall: (builderName: String, caseName: String)]()
		let internalNameByEnum = Dictionary(builders.compactMap { builder -> (SeamSignature.ScopeEnum.Key, String)? in
			if case let .scopeEnum(key) = builder.kind {
				(key, builder.internalName)
			} else {
				nil
			}
		}, uniquingKeysWith: { first, _ in first })
		for scopeEnum in scopeEnums where scopeEnum.key.seamType == seamType {
			guard let builderName = internalNameByEnum[scopeEnum.key] else { continue }
			for enumCase in scopeEnum.cases {
				if case let .inner(enumKey, _, sitePath, _) = enumCase.kind {
					routeCasesByCall[RouteCall(sitePath: sitePath, innerKey: enumKey)] = (builderName, enumCase.name)
				}
			}
		}
		self.routeCasesByCall = routeCasesByCall
		var sitesByPath = [[Property]: SeamSignature.Hole]()
		var passedUpHolesBySite = [SeamSignature.Hole.Site: SeamSignature.Hole]()
		var stageCallsByPath = [[Property]: [String]]()
		var fillStageCallsByPath = [[Property]: [Int: [String]]]()
		var namesBoundForBuilders = Set(holes.map(\.internalName) + holes.compactMap(\.wrapperFunctionName) + builders.map(\.internalName))
		for hole in holes {
			guard hole.innerSeamType == nil else {
				passedUpHolesBySite[hole.site] = hole
				continue
			}
			sitesByPath[hole.sitePath] = hole
			// Each stage but the last is called just before the `@Sendable` function that starts the next.
			for (stageIndex, boundary) in hole.stageBoundaries.enumerated() {
				let stageFunction = hole.stageFunctionName(at: stageIndex, ofFunctionNamed: hole.internalName)
				let nextStageFunction = hole.stageFunctionName(at: stageIndex + 1, ofFunctionNamed: hole.internalName)
				namesBoundForBuilders.insert(nextStageFunction)
				let arguments = hole.stages[stageIndex].map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.label)" }.joined(separator: ", ")
				let call = "let \(nextStageFunction) = \(stageFunction)(\(hole.stageStructType(at: stageIndex, qualifiedBy: nil).asSource)(\(arguments)))"
				let path = Array(hole.sitePath.prefix(boundary.pathLength))
				if let fillStageIndex = boundary.fillStageIndex {
					fillStageCallsByPath[path, default: [:]][fillStageIndex, default: []].append(call)
				} else {
					stageCallsByPath[path, default: []].append(call)
				}
			}
		}
		self.seamType = seamType
		self.sitesByPath = sitesByPath
		self.passedUpHolesBySite = passedUpHolesBySite
		self.stageCallsByPath = stageCallsByPath
		self.fillStageCallsByPath = fillStageCallsByPath
		self.namesBoundForBuilders = namesBoundForBuilders
	}

	/// The name of every builder the seam's generated initializer takes, inside the initializer, which a call its tree
	/// makes passes up by name, and of the later stage each of its stage calls binds. Empty outside a seam's tree.
	let namesBoundForBuilders: Set<String>

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
	func routeCase(at sitePath: [Property], innerKey: SeamSignature.ScopeEnum.Key) -> (builderName: String, caseName: String)? {
		routeCasesByCall[RouteCall(sitePath: sitePath, innerKey: innerKey)]
	}

	/// The stage calls made just before the `@Sendable` builder function of the property at the end of `sitePath`.
	func stageCalls(at sitePath: [Property]) -> [String] {
		stageCallsByPath.isEmpty ? [] : stageCallsByPath[sitePath, default: []]
	}

	/// The stage calls made just before each function of the fill that builds the property at the end of `sitePath`, by
	/// the function's stage among the fill's.
	func fillStageCalls(at sitePath: [Property]) -> [Int: [String]] {
		fillStageCallsByPath[sitePath, default: [:]]
	}

	/// A seam call in the tree and the inner enum it carries.
	private struct RouteCall: Hashable {
		let sitePath: [Property]
		let innerKey: SeamSignature.ScopeEnum.Key
	}

	/// The seam whose tree is generated, or `nil` for a tree that is no seam's.
	private let seamType: TypeDescription?
	private let routeCasesByCall: [RouteCall: (builderName: String, caseName: String)]
	private let sitesByPath: [[Property]: SeamSignature.Hole]
	private let passedUpHolesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]
	private let stageCallsByPath: [[Property]: [String]]
	private let fillStageCallsByPath: [[Property]: [Int: [String]]]
}

// MARK: - NearestDeclarations

/// The nearest declaration of a label on the path from a tree's root to a scope, as `Scope.createScopeGenerator` judges
/// what a scope receives only if available against it: each form the declaration provides, with the declared property
/// that binds it, and the forms of the label being built between that declaration and the scope.
struct NearestDeclaration: Sendable {
	/// Each form the declaration provides (see `CycleParameter.forms(providedBy:)`), mapped to the declared property a
	/// reader of that form is handed: the property itself, the optional property a parameter made optional binds, or
	/// the `LazilyInstantiated` whose instance a by-value form reads.
	var bindings = [Property: Property]()
	/// The forms of the label being built between the declaration and the scope: a receive of one of them reads a
	/// declaration that is not built yet.
	var formsBeingBuilt = Set<Property>()
}

/// The nearest declaration of each label on the path from a tree's root to a scope. A label absent here is declared
/// nowhere on the path.
typealias NearestDeclarations = [String: NearestDeclaration]

extension [String: NearestDeclaration] {
	/// The declarations a mock root's tree is enclosed by: each of `boundProperties`, the received properties the mock
	/// binds, in `Property` order, each form bound to the first property that provides it. The mock binds each form once
	/// and names every binding apart, so no binding hides another.
	static func binding(_ boundProperties: some Collection<Property>) -> Self {
		var nearestDeclarations = Self()
		for boundProperty in boundProperties.sorted() {
			nearestDeclarations.join(boundProperty, providing: CycleParameter.forms(providedBy: boundProperty))
		}
		return nearestDeclarations
	}

	/// The binding a receive of `property` only if available reads, or `nil` when the property is unavailable: the
	/// first of `property.formsReadByOnlyIfAvailableReceive` that the nearest declaration of its label binds, unless a
	/// form it reads is still being built between that declaration and the receiver.
	func binding(of property: Property) -> Property? {
		guard let nearestDeclaration = self[property.label] else { return nil }
		let forms = property.formsReadByOnlyIfAvailableReceive
		guard nearestDeclaration.formsBeingBuilt.isDisjoint(with: forms) else { return nil }
		for form in forms {
			if let binding = nearestDeclaration.bindings[form] {
				return binding
			}
		}
		return nil
	}

	/// Makes `property`, which provides `forms`, the nearest declaration of its label, hiding every other.
	mutating func replace(_ property: Property, providing forms: Set<Property>) {
		var nearestDeclaration = NearestDeclaration()
		for form in forms {
			nearestDeclaration.bindings[form] = property
		}
		self[property.label] = nearestDeclaration
	}

	/// Makes `properties`, the declarations of one scope that is no root, the nearest declarations of their labels, each
	/// hiding every declaration of its label above the scope. Their labels are distinct: they are the dependencies of the
	/// scope's type, which `DependencyTreeGenerator.validateDependencyLabelsAreDistinct` rejects before a tree that builds
	/// it is created when two share a label. A root's declarations, among which a mock root's forms of one label repeat
	/// it, join the bindings the tree is given instead (`join(_:providing:)`).
	mutating func replaceLabels(of properties: [Property]) {
		for property in properties {
			replace(property, providing: CycleParameter.forms(providedBy: property))
		}
	}

	/// Adds `property`, which provides `forms`, to the nearest declaration of its label, keeping each form already bound.
	mutating func join(_ property: Property, providing forms: Set<Property>) {
		var nearestDeclaration = self[property.label] ?? NearestDeclaration()
		for form in forms where nearestDeclaration.bindings[form] == nil {
			nearestDeclaration.bindings[form] = property
		}
		self[property.label] = nearestDeclaration
	}

	/// Records that `property` is being built: every form it provides is unavailable until a nearer declaration of its
	/// label hides it.
	mutating func build(_ property: Property) {
		self[property.label, default: NearestDeclaration()].formsBeingBuilt.formUnion(CycleParameter.forms(providedBy: property))
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
