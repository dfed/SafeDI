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
	///   - constructionComments: The comments the generated code ends the lines that construct the type with.
	///   - seamCall: How a tree that reaches this scope calls it, when the scope stands for a seam whose generated
	///     initializer another tree calls: `instantiable` then declares the initializer's parameters as its
	///     dependencies and builds nothing. `nil` for every other scope.
	init(
		instantiable: Instantiable,
		dependenciesLeftOut: [Dependency] = [],
		constructionComments: ConstructionComments = ConstructionComments(),
		seamCall: SeamCall? = nil,
		publicMockCall: PublicMockCall? = nil,
	) {
		self.instantiable = instantiable
		self.dependenciesLeftOut = dependenciesLeftOut
		self.constructionComments = constructionComments
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

	/// The comments the generated code ends the lines that construct the type with.
	let constructionComments: ConstructionComments

	/// The comment the generated code ends a line that constructs a type with, for each way it can construct the type.
	struct ConstructionComments: Sendable {
		init(initializer: String? = nil, mockMethod: String? = nil) {
			self.initializer = initializer
			self.mockMethod = mockMethod
		}

		/// The comment for a construction with the type's initializer or `instantiate()` method, or `nil` for none.
		let initializer: String?
		/// The comment for a construction with the type's hand-written mock method, or `nil` for none.
		let mockMethod: String?
	}

	/// How a tree that reaches this scope calls the seam it stands for, or `nil` for a scope that builds its type.
	let seamCall: SeamCall?

	/// How a mock tree that reaches this scope calls the public mock another module generated for its type, which the
	/// tree cannot build itself: `instantiable` then declares the mock's signature as its dependencies and builds
	/// nothing. `nil` for every other scope.
	let publicMockCall: PublicMockCall?

	/// The properties that this scope is responsible for instantiating.
	var propertiesToGenerate = [PropertyToGenerate]()

	/// For a scope that calls a seam (`seamCall`), how the call passes each builder the seam's generated initializer
	/// takes, in builder-label order. Empty for every other scope.
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
	private lazy var declaredProperties: [Property] = propertiesToGenerate.map(\.property)
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

	/// The properties this scope always creates: those it instantiates or is forwarded. No alias of this scope renames
	/// another (SafeDITool rejects that before it validates a tree that builds the scope), so no alias is among them.
	private lazy var unconditionallyCreatedProperties = Set(
		instantiable
			.dependencies
			.filter {
				switch $0.source {
				case .instantiated, .forwarded:
					true
				case .aliased, .received:
					false
				}
			}
			.flatMap(\.receivableProperties),
	)

	/// The received properties this scope requires an ancestor to provide. An alias of a property this scope always
	/// creates refers to that property, so it requires nothing of an ancestor: what that property needs, its own
	/// declaration requires.
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
				if onlyIfAvailable || unconditionallyCreatedProperties.contains(fulfillingProperty) {
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
	///   - boundProperties: The received properties a mock root binds, which enclose its whole tree. Kept apart
	///     from `receivableProperties`, which grows at every scope, so that the scopes of a mock tree do not each
	///     copy them.
	///   - onlyIfAvailableOverrideProperties: Those of `boundProperties` the mock root binds only to the override of an
	///     `onlyIfAvailable` receive, which defaults to `nil`. Such an override provides its property as every bound
	///     property does, but it alone does not keep an `onlyIfAvailable` alias of its label from being created (see
	///     `isProvidedOnlyByOnlyIfAvailableOverride`).
	///   - alwaysAvailableProperties: The properties in scope wherever the tree is built: those a mock is passed.
	///     The properties each scope forwards are added for the scopes beneath it.
	///   - runtimeOptionalProperties: The forms of a seam's optional parameters that are in scope wherever the tree
	///     is built but may be `nil` where inline they would be unavailable – both forms of a parameter the callers
	///     may pass `nil` for, the unwrapped form of a required optional parameter – each by its exact form: an
	///     `onlyIfAvailable` alias of one is bound from it as an optional value, as a mock binds an alias from an
	///     optional override. Each scope prunes the set it hands the scopes it builds, and its own aliases, by what it
	///     declares (see `ScopeGeneratorUnderConstruction.runtimeOptionalProperties(declaredBy:enclosedBy:)`).
	///   - seamRoot: What the root generator emits when the tree is a seam's: its signature and the hand-written
	///     initializer's arguments. `nil` for a root of the dependency tree and for a mock root.
	///   - startsCodeGeneration: Whether each generator of a dependency tree starts generating its code as soon as
	///     it is created, which a tree built only to read its generators' sets skips.
	///   - mockHoles: For a public mock's root, the holes its `mock()` takes a builder for, which each site of the tree
	///     calls, as a seam's tree calls the builders of `seamRoot`'s signature.
	///
	/// The tree is created again while a scope that a lazy cycle closes on finds other parameters for its builder
	/// function than it was created with (see `CycleParameter`): its cycle-closing scopes, created before it, pass
	/// those parameters, and count what they pass among the properties they receive. Nearly every tree has no such
	/// scope and is created once. A pass changes a scope's parameters only through the parameters of the functions it
	/// is nested in or that are nested in it, which only add to what it receives or declares, so the passes end once
	/// the parameters at each level of nesting have settled. A pass that is not the last kicks off code generation
	/// that nothing reads.
	func createScopeGenerator(
		for property: Property?,
		propertyStack: [Property],
		receivableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		boundProperties: Set<Property> = [],
		onlyIfAvailableOverrideProperties: Set<Property> = [],
		alwaysAvailableProperties: Set<Property> = [],
		runtimeOptionalProperties: Set<Property> = [],
		seamRoot: ScopeGenerator.SeamRoot? = nil,
		mockHoles: [SeamSignature.Hole] = [],
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool = false,
		startsCodeGeneration: Bool = true,
	) throws -> ScopeGenerator {
		var previousPassGenerator: ScopeGenerator?
		var scopeGenerator: ScopeGenerator
		repeat {
			scopeGenerator = try createScopeGenerator(
				for: property,
				propertyStack: propertyStack,
				receivableProperties: receivableProperties,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				boundProperties: boundProperties,
				onlyIfAvailableOverrideProperties: onlyIfAvailableOverrideProperties,
				alwaysAvailableProperties: alwaysAvailableProperties,
				runtimeOptionalProperties: runtimeOptionalProperties,
				seamRoot: seamRoot,
				mockHoles: mockHoles,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
				startsCodeGeneration: startsCodeGeneration,
				previousPassGenerator: previousPassGenerator,
			)
			previousPassGenerator = scopeGenerator
		} while scopeGenerator.cycleParametersChangedInTree
		return scopeGenerator
	}

	/// One pass of `createScopeGenerator`, which reads the parameters of the builder functions lazy cycles close on
	/// from `previousPassGenerator`, the tree the pass before created, or finds none when there is no pass before.
	private func createScopeGenerator(
		for property: Property?,
		propertyStack: [Property],
		receivableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		boundProperties: Set<Property>,
		onlyIfAvailableOverrideProperties: Set<Property>,
		alwaysAvailableProperties: Set<Property>,
		runtimeOptionalProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		mockHoles: [SeamSignature.Hole],
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		startsCodeGeneration: Bool,
		previousPassGenerator: ScopeGenerator?,
	) throws -> ScopeGenerator {
		var scopeGeneratorsUnderConstruction = [ScopeGeneratorUnderConstruction(
			scope: self,
			property: property,
			propertyStack: propertyStack,
			concreteTypeStack: propertyStack.map { _ in nil },
			propertiesBeingBuilt: propertyStack,
			receivableProperties: receivableProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			alwaysAvailableProperties: alwaysAvailableProperties,
			boundProperties: boundProperties,
			onlyIfAvailableOverrideProperties: onlyIfAvailableOverrideProperties,
			runtimeOptionalProperties: runtimeOptionalProperties,
			seamRoot: seamRoot,
			seamHoles: seamRoot.map { SeamHoles(seamType: instantiable.concreteInstantiable, holes: $0.signature.holes) }
				?? (mockHoles.isEmpty ? SeamHoles() : SeamHoles(seamType: instantiable.concreteInstantiable, holes: mockHoles)),
			sitePath: [],
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			previousPassGenerator: previousPassGenerator,
			cycleParameterContexts: [:],
			cycleParameterProvidedForms: [],
			cycleParameterFormsNotProvidedAboveFunction: [],
			cycleParameterFormsNoDeclarationCreates: [],
			cycleParameterLabelsBeingBuilt: [],
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
				let scopeGenerator = scopeGeneratorsUnderConstruction.removeLast().scopeGenerator()
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
	///   - concreteTypeStack: The concrete types of the scopes `propertyStack`'s properties are built for, beside it, or
	///     `nil` for a property of a fill's stack (`SeamSignature.Hole.fillPropertyStack`), which records none.
	///   - propertiesBeingBuilt: Those of `propertyStack` whose declaration is the nearest of its property on the path to
	///     this scope: still being built here. A scope between that declares the same property – one that closes a cycle,
	///     or one built for another concrete type – is what a receive of it here is passed.
	init(
		scope: Scope,
		property: Property?,
		propertyStack: [Property],
		concreteTypeStack: [TypeDescription?],
		propertiesBeingBuilt: [Property],
		receivableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		alwaysAvailableProperties: Set<Property>,
		boundProperties: Set<Property>,
		onlyIfAvailableOverrideProperties: Set<Property>,
		runtimeOptionalProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		seamHoles: SeamHoles,
		sitePath: [Property],
		enclosingFills: [String: String] = [:],
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		startsCodeGeneration: Bool,
		fill: Fill? = nil,
		buildsWithHandWrittenMocks: Bool = false,
		previousPassGenerator: ScopeGenerator?,
		cycleParameterContexts: [Property: CycleParameterContext],
		cycleParameterProvidedForms: Set<Property>,
		cycleParameterFormsNotProvidedAboveFunction: Set<Property>,
		cycleParameterFormsNoDeclarationCreates: Set<Property>,
		cycleParameterLabelsBeingBuilt: Set<String>,
	) {
		var childPropertyStack = propertyStack
		var childConcreteTypeStack = concreteTypeStack
		// What this scope's own receives and the scopes it builds find still being built: this scope's own property, and
		// those being built around it that it does not declare again itself.
		var childPropertiesBeingBuilt = propertiesBeingBuilt.isEmpty ? propertiesBeingBuilt : propertiesBeingBuilt.filter {
			!scope.createdProperties.contains($0) && !scope.declaredLazilyInstantiatedInstanceProperties.contains($0)
		}
		// The index on `propertyStack` of the entry this scope repeats when it closes a cycle, and of the declaration that
		// entry is: they differ where the entry is the instance a lazily instantiated declaration offers.
		var closedOnEntryIndex: Int?
		var closedOnDeclarationIndex: Int?
		// The labels of the parameters with a form no declaration creates that a scope in the body of the innermost function
		// taking them is built as, this one included (see `childCycleParameterLabelsBeingBuilt`): found here, as
		// `childPropertyStack` is.
		var cycleParameterLabelsBeingBuilt = cycleParameterLabelsBeingBuilt
		if let property {
			// A scope closes a cycle where validation finds one: it repeats a declaration of the same property, as cycle
			// validation sees it (a lazily instantiated property as the constant it stands for), built for the same
			// concrete type. An entry of a fill's stack records no type and is matched by its property alone.
			let validatedProperty = property.asValidatedForDependencyCycles
			let concreteType = scope.instantiable.concreteInstantiable
			closedOnEntryIndex = propertyStack.indices.first {
				propertyStack[$0].asValidatedForDependencyCycles == validatedProperty && (concreteTypeStack[$0] ?? concreteType) == concreteType
			}
			// A lazily instantiated declaration's instance is on the stack just inside the declaration.
			closedOnDeclarationIndex = closedOnEntryIndex.map { index in
				propertyStack.indices.contains(index + 1) && propertyStack[index + 1].asLazilyInstantiatedInstanceProperty == propertyStack[index] ? index + 1 : index
			}
			childPropertyStack.insert(property, at: 0)
			childConcreteTypeStack.insert(concreteType, at: 0)
			childPropertiesBeingBuilt.insert(property, at: 0)
			if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
				childPropertyStack.insert(instanceProperty, at: 0)
				childConcreteTypeStack.insert(concreteType, at: 0)
				childPropertiesBeingBuilt.insert(instanceProperty, at: 0)
			}
			if cycleParameterFormsNoDeclarationCreates.contains(where: { $0.label == property.label }) {
				cycleParameterLabelsBeingBuilt.insert(property.label)
			}
		}
		let closedOnProperty = closedOnDeclarationIndex.map { propertyStack[$0] }
		let isPropertyCycle = closedOnProperty != nil
		// The parameters of this scope's builder function that the pass before found, when a lazy cycle closes on it,
		// or those of the function a cycle-closing scope refers to. Nearly every scope has neither.
		let ownCycleParameters = if !isPropertyCycle, property != nil {
			previousPassGenerator?.foundCycleParameters ?? []
		} else {
			[CycleParameter]()
		}
		let closedOnContext = closedOnProperty.flatMap { cycleParameterContexts[$0] }
		let enclosingScopeReceivableProperties = receivableProperties
		var receivableProperties = receivableProperties.union(scope.createdProperties)
		// The parameters this scope passes the builder function a lazy cycle closes on that are unavailable where it
		// passes them, which it passes `nil`: computed below, once `isPropertyUnavailable` can be asked.
		var cycleParameterUnavailableProperties = Set<Property>()
		// The forms of the parameters of the functions enclosing the scopes this scope builds whose label nothing above the
		// function provides (see `cycleParameterFormsNotProvidedAboveFunction`): those enclosing this scope, joined below by
		// those of this scope's own function.
		var parameterFormsNotProvidedAboveFunction = cycleParameterFormsNotProvidedAboveFunction
		// The forms of the parameters of the functions enclosing this scope that no declaration creates (see
		// `childCycleParameterFormsNoDeclarationCreates`): those enclosing the scope declaring this scope's own function,
		// joined below, for the function's body, by those of its own function's parameters.
		var cycleParameterFormsNoDeclarationCreates = cycleParameterFormsNoDeclarationCreates
		// The function's body reads each parameter's label from the parameter, which hides every other declaration of the
		// label above it, as a forwarded property does.
		let callSiteLazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		var lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		var alwaysAvailableProperties = alwaysAvailableProperties
		var runtimeOptionalProperties = runtimeOptionalProperties
		let ownCycleParameterLabels = Set(ownCycleParameters.map(\.property.label))
		if !ownCycleParameters.isEmpty {
			// The forms the parameters provide, made available below once the call site's availability is known.
			lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
				.filter { !ownCycleParameterLabels.contains($0.label) }
				.union(ownCycleParameters.compactMap(\.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding))
			for parameter in ownCycleParameters {
				if parameter.property.typeDescription.isOptional {
					// A parameter that may be `nil` is read as a seam's optional parameter is: an `onlyIfAvailable` alias of
					// its unwrapped form, or of the parameter itself when a caller may pass `nil`, is bound from it as an
					// optional value.
					runtimeOptionalProperties = runtimeOptionalProperties.filter { $0.label != parameter.property.label }
					runtimeOptionalProperties.insert(parameter.property.asUnwrappedProperty)
					if !parameter.isRequired {
						runtimeOptionalProperties.insert(parameter.property)
					}
				} else {
					runtimeOptionalProperties = runtimeOptionalProperties.filter { $0.label != parameter.property.label }
					alwaysAvailableProperties.formUnion(parameter.providedForms)
				}
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
		/// Whether an `onlyIfAvailable` dependency of `property` is unavailable. A property this scope
		/// creates is available. Otherwise, the property this scope is built for and its ancestors are
		/// still being built, so they are unavailable.
		/// - Parameter mockBindsEveryReceive: Whether, in a mock, every receive of `property` is bound by the mock where it
		///   is not declared above. `false` for a parameter of this scope's builder function that a lazy cycle closes on:
		///   its label may be one only the calls of other modules' public mocks receive, which the mock leaves out
		///   (`ScopeGenerator.receivedOnlyByPublicMockCallsLeftOut`), so the scope declaring the function passes it, as
		///   production does, only what a declaration above the function or the mock's own binding provides, and `nil`
		///   otherwise.
		func isPropertyUnavailable(_ property: Property, mockBindsEveryReceive: Bool = true) -> Bool {
			if scope.createdProperties.contains(property) {
				return false
			} else if forMockGeneration, scope.publicMockCall == nil, mockBindsEveryReceive {
				// A mock builds, or is handed, every property an ancestor does not
				// create — onlyIfAvailable dependencies become optional mock parameters.
				// Only a property that is still being built is unavailable, as in production. A mock promotes a
				// received optional property as the non-optional value it builds, so a receive of either form of
				// it is unavailable inside the tree it builds.
				let unwrappedProperty = property.asUnwrappedProperty
				return childPropertiesBeingBuilt.contains {
					$0.label == unwrappedProperty.label && $0.typeDescription.unwrapped == unwrappedProperty.typeDescription
				}
			} else {
				// A mock binds what its tree receives, but not what only the public mocks it calls receive: a call passes
				// such a property only where the tree provides it, as production would, and `nil` elsewhere. The instance of
				// a wrapper the tree holds – one the mock root promotes, or a scope above declares – is provided: the call
				// passes it by reading the wrapper's instance, as the arguments read it (`lazilyInstantiatedInstanceProperties`).
				// A form only a parameter provides is not, while a form of its label is still being built inside the
				// function's body (see `cycleParameterFormsBeingBuilt`).
				func isReceivable(_ property: Property) -> Bool {
					(
						receivableProperties.contains(property)
							|| (forMockGeneration && boundProperties.contains(property))
							|| lazilyInstantiatedInstanceProperties.contains(property),
					) && !(cycleParameterLabelsBeingBuilt.contains(property.label) && cycleParameterFormsNoDeclarationCreates.contains(property))
				}
				let propertyIsAvailableInParentStack = isReceivable(property) && !childPropertiesBeingBuilt.contains(property)
				let unwrappedPropertyIsAvailableInParentStack = isReceivable(property.asUnwrappedProperty) && !childPropertiesBeingBuilt.contains(property.asUnwrappedProperty)
				return !(propertyIsAvailableInParentStack || unwrappedPropertyIsAvailableInParentStack)
			}
		}
		if let closedOnContext {
			// A cycle-closing scope passes each parameter its nearest declaration of the label: one a scope between it and
			// the function declares, or else the function's own parameter, which is always in scope. A declaration that
			// does not provide the parameter's form, or that is still being built around this scope, is unavailable. The
			// function takes no parameter of this scope's own label (see `ScopeGenerator.foundCycleParameters`).
			let propertiesBuiltBetween = propertyStack.prefix(closedOnEntryIndex ?? 0)
			for parameter in closedOnContext.parameters where !parameter.isRequired {
				guard let declaredForms = closedOnContext.nearestDeclaredForms(ofLabel: parameter.property.label) else { continue }
				let providingForm = declaredForms.contains(parameter.property) ? parameter.property : parameter.property.asUnwrappedProperty
				if !declaredForms.contains(providingForm) || propertiesBuiltBetween.contains(providingForm) {
					cycleParameterUnavailableProperties.insert(parameter.property)
				}
			}
		} else if !ownCycleParameters.isEmpty {
			// The scope that declares the function passes each parameter the binding in scope where it calls it, as the
			// function's body read it before, and the body reads every form the parameters provide.
			for parameter in ownCycleParameters where !parameter.isRequired && isPropertyUnavailable(parameter.property, mockBindsEveryReceive: false) {
				cycleParameterUnavailableProperties.insert(parameter.property)
			}
			// A parameter stands for an enclosing provider of an `onlyIfAvailable` alias of its label in the body only where
			// the binding the scope declaring the function passes would be one: otherwise the alias is created as it is
			// where the function takes no parameter of its label.
			parameterFormsNotProvidedAboveFunction = parameterFormsNotProvidedAboveFunction.filter { !ownCycleParameterLabels.contains($0.label) }
			let callSiteHiddenCycleParameterForms = Self.formsBeingBuilt(
				ofCycleParameterFormsNoDeclarationCreates: cycleParameterFormsNoDeclarationCreates,
				labelsBeingBuilt: cycleParameterLabelsBeingBuilt,
			)
			for parameter in ownCycleParameters where !Self.isProvided(
				parameter.property,
				byEnclosingScopeReceivableProperties: enclosingScopeReceivableProperties,
				exceptCycleParameterForms: cycleParameterFormsNotProvidedAboveFunction,
				andCycleParameterFormsBeingBuilt: callSiteHiddenCycleParameterForms,
				orBoundProperties: boundProperties,
				exceptOnlyIfAvailableOverrides: onlyIfAvailableOverrideProperties,
				lazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties,
				childPropertyStack: childPropertyStack,
			) {
				parameterFormsNotProvidedAboveFunction.formUnion(parameter.providedForms)
			}
			receivableProperties = receivableProperties
				.filter { !ownCycleParameterLabels.contains($0.label) }
				.union(ownCycleParameters.flatMap(\.providedForms))
			// Inside the function's body, a form a parameter provides that nothing where the function is called creates or
			// binds – a declaration, a lazily instantiated instance, or what a mock binds other than its override of a receive
			// only if available, which provides no form (see `isProvided`) – is a form no declaration creates. A form of an
			// enclosing function's parameter that no declaration creates stays one.
			let enclosingFormsNoDeclarationCreates = cycleParameterFormsNoDeclarationCreates
			cycleParameterFormsNoDeclarationCreates = enclosingFormsNoDeclarationCreates.filter { !ownCycleParameterLabels.contains($0.label) }
			for parameter in ownCycleParameters {
				for form in parameter.providedForms where enclosingFormsNoDeclarationCreates.contains(form) || !(
					enclosingScopeReceivableProperties.contains(form)
						|| (boundProperties.contains(form) && !onlyIfAvailableOverrideProperties.contains(form))
						|| callSiteLazilyInstantiatedInstanceProperties.contains(form)
				) {
					cycleParameterFormsNoDeclarationCreates.insert(form)
				}
			}
			// Nothing in the body is built yet.
			cycleParameterLabelsBeingBuilt.subtract(ownCycleParameterLabels)
		}
		unavailableOptionalProperties = Set<Property>(scope.instantiable.dependencies.flatMap { dependency in
			switch dependency.source {
			case .instantiated, .forwarded:
				[Property]()
			case let .received(onlyIfAvailable):
				if onlyIfAvailable, isPropertyUnavailable(dependency.property) {
					[dependency.property]
				} else {
					[Property]()
				}
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				if onlyIfAvailable, isPropertyUnavailable(fulfillingProperty) {
					[dependency.property, fulfillingProperty]
				} else {
					[Property]()
				}
			}
		})
		self.scope = scope
		self.property = property
		// A scope that closes a cycle creates no children.
		propertiesToGenerate = isPropertyCycle ? [] : scope.propertiesToGenerate
		self.childPropertyStack = childPropertyStack
		self.childConcreteTypeStack = childConcreteTypeStack
		self.childPropertiesBeingBuilt = childPropertiesBeingBuilt
		self.enclosingScopeReceivableProperties = enclosingScopeReceivableProperties
		self.receivableProperties = receivableProperties
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		self.childLazilyInstantiatedInstanceProperties = childLazilyInstantiatedInstanceProperties
		self.previousPassGenerator = previousPassGenerator
		self.ownCycleParameters = ownCycleParameters
		passedCycleParameters = closedOnContext?.parameters ?? ownCycleParameters
		self.cycleParameterUnavailableProperties = cycleParameterUnavailableProperties
		self.callSiteLazilyInstantiatedInstanceProperties = callSiteLazilyInstantiatedInstanceProperties
		// The scopes beneath this one see what it declares as the nearest declaration of each parameter's label of the
		// functions enclosing it that lazy cycles close on, and this scope's own function's parameters. Nearly every
		// scope is beneath no such function.
		var childCycleParameterContexts = isPropertyCycle ? [:] : cycleParameterContexts
		if !childCycleParameterContexts.isEmpty {
			let declaredProperties = scope.createdProperties.union(scope.propertiesToDeclare).union(ownCycleParameters.flatMap(\.providedForms))
			childCycleParameterContexts = childCycleParameterContexts.mapValues { $0.declaring(declaredProperties) }
		}
		if let property, !ownCycleParameters.isEmpty {
			childCycleParameterContexts[property] = CycleParameterContext(parameters: ownCycleParameters)
		}
		self.childCycleParameterContexts = childCycleParameterContexts
		// The forms the parameters of the functions enclosing this scope provide, which a declaration of their label here
		// hides from the scopes beneath it, as it hides any declaration above: they then resolve the label to this
		// scope's declaration, which validation has checked provides what they receive or is passed `nil` for. Nearly
		// every scope is beneath no such function.
		var parameterProvidedForms = cycleParameterProvidedForms
		if !ownCycleParameters.isEmpty {
			parameterProvidedForms = parameterProvidedForms.filter { !ownCycleParameterLabels.contains($0.label) }.union(ownCycleParameters.flatMap(\.providedForms))
		}
		self.cycleParameterFormsNotProvidedAboveFunction = cycleParameterFormsNotProvidedAboveFunction
		cycleParameterFormsBeingBuilt = Self.formsBeingBuilt(
			ofCycleParameterFormsNoDeclarationCreates: cycleParameterFormsNoDeclarationCreates,
			labelsBeingBuilt: cycleParameterLabelsBeingBuilt,
		)
		childCycleParameterLabelsBeingBuilt = cycleParameterLabelsBeingBuilt
		// A form this scope declares is created beneath it. Nearly every scope is beneath no function a lazy cycle closes on.
		childCycleParameterFormsNoDeclarationCreates = cycleParameterFormsNoDeclarationCreates.isEmpty
			? cycleParameterFormsNoDeclarationCreates
			: cycleParameterFormsNoDeclarationCreates.subtracting(scope.createdProperties.union(scope.propertiesToDeclare))
		if parameterProvidedForms.isEmpty || isPropertyCycle {
			childCycleParameterProvidedForms = parameterProvidedForms
			childCycleParameterFormsNotProvidedAboveFunction = parameterFormsNotProvidedAboveFunction
			childReceivableProperties = receivableProperties
		} else {
			let declaredProperties = scope.createdProperties.union(scope.propertiesToDeclare)
			let declaredLabels = Set(declaredProperties.map(\.label))
			childCycleParameterProvidedForms = parameterProvidedForms.filter { !declaredLabels.contains($0.label) }
			childCycleParameterFormsNotProvidedAboveFunction = parameterFormsNotProvidedAboveFunction.filter { !declaredLabels.contains($0.label) }
			childReceivableProperties = receivableProperties.subtracting(parameterProvidedForms.filter { form in
				declaredLabels.contains(form.label) && !declaredProperties.contains(form) && !declaredProperties.contains(form.asUnwrappedProperty)
			})
		}
		// A forwarded property is a parameter of the function that builds the scope, so it is in scope wherever
		// the scope's tree is built. Nearly every scope forwards nothing, so most share the set they were given.
		let forwardedProperties = scope.instantiable.forwardedReceivableProperties
		self.alwaysAvailableProperties = forwardedProperties.isEmpty
			? alwaysAvailableProperties
			: alwaysAvailableProperties.union(forwardedProperties)
		self.boundProperties = boundProperties
		self.onlyIfAvailableOverrideProperties = onlyIfAvailableOverrideProperties
		self.runtimeOptionalProperties = runtimeOptionalProperties.isEmpty
			? runtimeOptionalProperties
			: Self.runtimeOptionalProperties(declaredBy: scope, enclosedBy: runtimeOptionalProperties)
		self.seamRoot = seamRoot
		self.seamHoles = seamHoles
		// The path is kept only where a hole needs it: a site, and the stage calls of a staged builder, are found by it.
		self.sitePath = seamHoles.isEmpty ? [] : sitePath + (property.map { [$0] } ?? [])
		self.fill = fill
		self.erasedToConcreteExistential = erasedToConcreteExistential
		self.isPropertyCycle = isPropertyCycle
		self.closedOnProperty = closedOnProperty
		self.forMockGeneration = forMockGeneration
		self.startsCodeGeneration = startsCodeGeneration
		self.buildsWithHandWrittenMocks = buildsWithHandWrittenMocks
		// A scope that closes a cycle calls no seam; any other seam call passes a builder for each of the seam's holes. A
		// call inside a fill of a seam that holds the fill's site, or that passes the site's builder up, passes that fill
		// by name, so every instance of the seam calls the same fills with its own scopes.
		self.enclosingFills = enclosingFills
		holeArguments = isPropertyCycle ? [] : scope.holeArguments
		// The call's own fills are those no enclosing call fills. A fill is named apart from the fills enclosing it and from
		// the builders the seam whose tree holds it takes, which a call inside it passes by name and which the fill, declared
		// closer, would shadow. One seam's builder labels are distinct, so the call's own fills never share a name.
		var fillsOfThisCall = [(fill: Fill, scope: Scope)]()
		if !holeArguments.isEmpty {
			let reservedNames = Set(enclosingFills.values).union(seamHoles.internalNames)
			for case let .fill(hole, fulfillingScope) in holeArguments where enclosingFills[ScopeGenerator.fillKey(of: hole)] == nil {
				var functionName = ScopeGenerator.fillFunctionName(of: hole)
				while reservedNames.contains(functionName) {
					functionName = "\(functionName)_".spelledAsJoinedIdentifier
				}
				fillsOfThisCall.append((Fill(hole: hole, key: ScopeGenerator.fillKey(of: hole), functionName: functionName), fulfillingScope))
			}
		}
		self.fillsOfThisCall = fillsOfThisCall
		childGenerators.reserveCapacity(propertiesToGenerate.count + fillsOfThisCall.count)
	}

	/// A fill of a seam call: the hole it fills, its key (see `ScopeGenerator.fillKey(of:)`), and its function's name.
	struct Fill {
		let hole: SeamSignature.Hole
		let key: String
		let functionName: String
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
		let hole = fill.hole
		let fields = hole.stages.joined().map(\.property)
		let fieldLabels = Set(fields.map(\.label))
		var fieldForms = Set<Property>()
		var fieldInstanceProperties = Set<Property>()
		for field in fields {
			fieldForms.insert(field)
			if let instanceProperty = field.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				fieldForms.insert(instanceProperty)
				fieldInstanceProperties.insert(instanceProperty)
			}
		}
		return ScopeGeneratorUnderConstruction(
			scope: scope,
			property: hole.property,
			propertyStack: hole.fillPropertyStack,
			concreteTypeStack: hole.fillPropertyStack.map { _ in nil },
			propertiesBeingBuilt: hole.fillPropertyStack,
			// A value the fill takes from the caller's scope is available as it would be to a pass-through of the call:
			// one the caller's path is still building is not, so a receive of it only if available is passed `nil`.
			receivableProperties: childReceivableProperties.filter { !fieldLabels.contains($0.label) && !childPropertyStack.contains($0) }.union(fieldForms),
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties.filter { !fieldLabels.contains($0.label) }.union(fieldInstanceProperties),
			alwaysAvailableProperties: alwaysAvailableProperties.union(fieldForms),
			boundProperties: boundProperties,
			onlyIfAvailableOverrideProperties: onlyIfAvailableOverrideProperties,
			runtimeOptionalProperties: runtimeOptionalProperties.filter { !fieldLabels.contains($0.label) },
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath,
			enclosingFills: enclosingFillsOfThisCall,
			erasedToConcreteExistential: hole.erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			fill: fill,
			// A fill a mock declares builds the hole's tree as the mock's tree built inline would.
			buildsWithHandWrittenMocks: forMockGeneration,
			// The pass before created a fill's generator around the generator of the property it builds. A fill is a
			// function of its own, declared where the seam is called, so no function enclosing the call that a lazy cycle
			// closes on encloses a cycle-closing scope in the fill. The fill's own built scope takes the parameters the
			// pass before found for it as any scope does, when a lazy cycle inside the fill closes on its property.
			previousPassGenerator: previousPassChildGenerator?.children.first,
			cycleParameterContexts: [:],
			cycleParameterProvidedForms: [],
			// The fill reads the parameters of the functions enclosing the call that a field does not hide, as the call's
			// tree built inline reads them.
			cycleParameterFormsNotProvidedAboveFunction: childCycleParameterFormsNotProvidedAboveFunction.filter { !fieldLabels.contains($0.label) },
			cycleParameterFormsNoDeclarationCreates: childCycleParameterFormsNoDeclarationCreates.filter { !fieldLabels.contains($0.label) },
			cycleParameterLabelsBeingBuilt: childCycleParameterLabelsBeingBuilt.subtracting(fieldLabels),
		)
	}

	/// Creates the generator of a hole this scope's type instantiates, a site of the seam whose tree is generated.
	mutating func addHoleGenerator(property: Property, erasedToConcreteExistential: Bool) {
		childGenerators.append(ScopeGenerator(
			holeProperty: property,
			erasedToConcreteExistential: erasedToConcreteExistential,
			site: seamHoles.site(at: sitePath + [property]),
			ownerPropertyStack: childPropertyStack,
		))
	}

	/// The scope under construction for a scope this one instantiates.
	func childUnderConstruction(
		scope: Scope,
		property: Property,
		erasedToConcreteExistential: Bool,
	) throws -> ScopeGeneratorUnderConstruction {
		if let error = ErasedInstantiatorForwardedPropertiesMismatchError(
			property: property,
			declarationLocation: self.scope.instantiable.dependencies.first(where: { $0.property == property })?.declarationLocation,
			parent: self.scope.instantiable.concreteInstantiable,
			builtInstantiable: scope.instantiable,
		) {
			throw error
		} else {
			ScopeGeneratorUnderConstruction(
				scope: scope,
				property: property,
				propertyStack: childPropertyStack,
				concreteTypeStack: childConcreteTypeStack,
				propertiesBeingBuilt: childPropertiesBeingBuilt,
				receivableProperties: childReceivableProperties,
				lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
				alwaysAvailableProperties: alwaysAvailableProperties,
				boundProperties: boundProperties,
				onlyIfAvailableOverrideProperties: onlyIfAvailableOverrideProperties,
				runtimeOptionalProperties: runtimeOptionalProperties,
				seamRoot: nil,
				seamHoles: seamHoles,
				sitePath: sitePath,
				enclosingFills: enclosingFills,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
				startsCodeGeneration: startsCodeGeneration,
				buildsWithHandWrittenMocks: buildsWithHandWrittenMocks,
				previousPassGenerator: previousPassChildGenerator,
				cycleParameterContexts: childCycleParameterContexts,
				cycleParameterProvidedForms: childCycleParameterProvidedForms,
				cycleParameterFormsNotProvidedAboveFunction: childCycleParameterFormsNotProvidedAboveFunction,
				cycleParameterFormsNoDeclarationCreates: childCycleParameterFormsNoDeclarationCreates,
				cycleParameterLabelsBeingBuilt: childCycleParameterLabelsBeingBuilt,
			)
		}
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
			isProvidedByEnclosingScope: isProvidedByEnclosingScope(property),
			isProvidedOnlyByOnlyIfAvailableOverride: isProvidedOnlyByOnlyIfAvailableOverride(property),
			// A forwarded or bound fulfilling property is in scope wherever the alias is built, so the alias is
			// always created from it. Any other is built by a scope, which can build it after the alias.
			fulfillingPropertyIsAlwaysAvailable: alwaysAvailableProperties.contains(fulfillingProperty)
				|| alwaysAvailableProperties.contains(fulfillingProperty.asUnwrappedProperty),
			// The exact form of a seam parameter that may be `nil`, which no declaration hides: validation reports a
			// receive beneath a declaration of its label. An alias of a form the set lacks – exactly a required optional
			// parameter – is created wherever the tree is built.
			fulfillingPropertyIsRuntimeOptional: runtimeOptionalProperties.contains(fulfillingProperty),
			declarationReference: declarationReference,
		))
	}

	/// Creates the scope's generator once `childGenerators` holds a generator for each of `propertiesToGenerate`.
	func scopeGenerator() -> ScopeGenerator {
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
			closedOnProperty: closedOnProperty,
			constructionComments: scope.constructionComments,
			seamCall: scope.seamCall,
			publicMockCall: scope.publicMockCall,
			seamRoot: seamRoot,
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
			passedUpHoles: holeArguments.compactMap { holeArgument in
				if case let .passUp(hole) = holeArgument {
					hole
				} else {
					nil
				}
			},
			stageCalls: seamHoles.stageCalls(at: sitePath),
			constructsWithHandWrittenMock: buildsWithHandWrittenMocks
				&& scope.publicMockCall == nil
				&& scope.instantiable.mockInitializer != nil
				&& property.map { scope.instantiable.mockReturnTypeIsCompatible(withPropertyType: $0.typeDescription.asInstantiatedType) } ?? false,
			cycleParameters: passedCycleParameters,
			builtCycleParameters: ownCycleParameters,
			cycleParameterUnavailableProperties: cycleParameterUnavailableProperties,
			callSiteLazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties,
		)
		let scopeGenerator = if let fill {
			ScopeGenerator(fill: fill.hole, key: fill.key, functionName: fill.functionName, child: builtGenerator)
		} else {
			builtGenerator
		}
		if !forMockGeneration, startsCodeGeneration, fill == nil {
			_ = Task.detached {
				// Kick off code generation.
				try await scopeGenerator.generateCode()
			}
		}
		return scopeGenerator
	}

	private let scope: Scope
	private let property: Property?
	/// Whether this scope is in the tree of a fill a mock declares, whose types are built as the mock's tree built
	/// inline builds them: each with its hand-written mock where `mockReturnTypeIsCompatible` says the mock builds it.
	private let buildsWithHandWrittenMocks: Bool
	private let propertiesToGenerate: [Scope.PropertyToGenerate]
	/// The index in `propertiesToGenerate` of the next property to create a generator for.
	private var nextPropertyIndex = 0
	private let childPropertyStack: [Property]
	/// The concrete types of the scopes `childPropertyStack`'s properties are built for, beside it (see
	/// `init(scope:property:propertyStack:concreteTypeStack:…)`).
	private let childConcreteTypeStack: [TypeDescription?]
	/// What the scopes this scope builds find still being built (see `init(scope:property:propertyStack:concreteTypeStack:propertiesBeingBuilt:…)`).
	private let childPropertiesBeingBuilt: [Property]
	/// The properties the scopes enclosing this one make receivable.
	private let enclosingScopeReceivableProperties: Set<Property>
	/// `enclosingScopeReceivableProperties` and the properties this scope creates.
	private let receivableProperties: Set<Property>
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
	/// For each function enclosing the scopes this scope builds that a lazy cycle closes on, by the property it builds,
	/// its parameters with the nearest declaration of each label (see `CycleParameterContext`).
	private let childCycleParameterContexts: [Property: CycleParameterContext]
	/// The forms the parameters of the functions enclosing the scopes this scope builds provide, which no declaration
	/// between those functions and the scopes this one builds hides.
	private let childCycleParameterProvidedForms: Set<Property>
	/// The forms in `enclosingScopeReceivableProperties` that a parameter of a function enclosing this scope, which a lazy
	/// cycle closes on, provides where nothing above the function provides the parameter's label: the scope declaring the
	/// function passes the parameter `nil`, a mock's override of an `onlyIfAvailable` receive, or the instance of a lazily
	/// instantiated property, none of which keeps an `onlyIfAvailable` alias of the label from being created (see
	/// `isProvidedByEnclosingScope`). A declaration of the label between the function and this scope removes them. Empty
	/// for nearly every scope.
	private let cycleParameterFormsNotProvidedAboveFunction: Set<Property>
	/// `cycleParameterFormsNotProvidedAboveFunction` as the scopes this scope builds see them, with those of this scope's
	/// own function's parameters.
	private let childCycleParameterFormsNotProvidedAboveFunction: Set<Property>
	/// The forms the parameters of the functions enclosing this scope that lazy cycles close on put in
	/// `receivableProperties` that no declaration creates – none where the scope declaring the function calls it, and
	/// none between the function and this scope – whose label this scope, or a scope between the function and it, is
	/// built as: they are unavailable here. Such a form stands for a declaration of another form: a parameter made
	/// optional stands for the non-optional declaration it is made from, which, where the label is still being built,
	/// is unavailable to a receive only if available of either form, as it is where the function takes no such
	/// parameter. A form of its label still being built above the function does not count: what the scope declaring
	/// the function, and each cycle-closing scope, finds unavailable there it passes `nil`. Empty for nearly every scope.
	private let cycleParameterFormsBeingBuilt: Set<Property>
	/// The forms the parameters of the functions enclosing the scopes this scope builds put in `receivableProperties`
	/// that no declaration creates – none where the scope declaring the function calls it, and none between the
	/// function and the scopes this one builds – each a form of a declaration of another form. Empty for nearly every
	/// scope.
	private let childCycleParameterFormsNoDeclarationCreates: Set<Property>
	/// The labels of the parameters of the functions enclosing the scopes this scope builds that have a form no
	/// declaration creates, which this scope, or a scope between the innermost function taking the label and this scope,
	/// is built as. Empty for nearly every scope.
	private let childCycleParameterLabelsBeingBuilt: Set<String>
	/// `receivableProperties` as the scopes this scope builds see them: without the forms of a parameter of an enclosing
	/// function that this scope's declaration of the parameter's label hides.
	private let childReceivableProperties: Set<Property>
	/// The properties in scope wherever this scope's tree is built: those this scope and the scopes enclosing it
	/// forward, and those a mock is passed.
	private let alwaysAvailableProperties: Set<Property>
	private let boundProperties: Set<Property>
	/// See `createScopeGenerator`.
	private let onlyIfAvailableOverrideProperties: Set<Property>
	/// The properties that may be `nil` where this scope's aliases and the scopes it builds read them, each by its
	/// exact form: both forms of a seam parameter the seam's callers may pass `nil` for, the unwrapped form of a required
	/// optional parameter, and both forms of an `onlyIfAvailable` alias of one, which no declaration on the path from
	/// the seam's root down to and including this scope declares otherwise. See `createScopeGenerator`.
	private let runtimeOptionalProperties: Set<Property>

	/// `enclosingRuntimeOptionalProperties`, the properties that may be `nil` above `scope`, as the aliases `scope`
	/// declares and the scopes it builds see them. The closest declaration of a property's label decides: one `scope`
	/// instantiates, or forwards – a seam's root's own forwarded properties included – or declares by an alias that is
	/// created whenever `scope` is, is not `nil` there, so every form of its label leaves the set, while an
	/// `onlyIfAvailable` alias of a property in the set may be `nil` itself, so both of its forms join it. No alias of
	/// `scope` renames another (SafeDITool rejects that before it validates a tree that builds the scope). A received
	/// property declares nothing. Each property is held by its exact form, so that an alias of exactly a required
	/// optional parameter, which the set never holds, is created.
	private static func runtimeOptionalProperties(
		declaredBy scope: Scope,
		enclosedBy enclosingRuntimeOptionalProperties: Set<Property>,
	) -> Set<Property> {
		var runtimeOptionalProperties = enclosingRuntimeOptionalProperties
		var aliases = [(property: Property, fulfillingProperty: Property, onlyIfAvailable: Bool)]()
		func removeEveryForm(ofLabel label: String) {
			runtimeOptionalProperties = runtimeOptionalProperties.filter { $0.label != label }
		}
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				removeEveryForm(ofLabel: dependency.property.label)
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				aliases.append((dependency.property, fulfillingProperty, onlyIfAvailable))
			case .received:
				break
			}
		}
		guard !aliases.isEmpty else { return runtimeOptionalProperties }
		// An alias that keeps the label it retypes is not in scope where its own value is read, so the forms of its
		// fulfilling property stay in the set, which `addAliasGenerator` judges the alias by; a read of those forms
		// beneath the alias is the hidden-label error, reported before any alias is judged.
		for alias in aliases {
			let formsTheAliasReads: Set<Property> = alias.property.label == alias.fulfillingProperty.label
				? [alias.fulfillingProperty, alias.fulfillingProperty.asUnwrappedProperty]
				: []
			runtimeOptionalProperties = runtimeOptionalProperties.filter { $0.label != alias.property.label || formsTheAliasReads.contains($0) }
		}
		let enclosingAndRetypedRuntimeOptionalProperties = runtimeOptionalProperties
		for alias in aliases where alias.onlyIfAvailable && enclosingAndRetypedRuntimeOptionalProperties.contains(alias.fulfillingProperty) {
			runtimeOptionalProperties.insert(alias.property)
			runtimeOptionalProperties.insert(alias.property.asUnwrappedProperty)
		}
		return runtimeOptionalProperties
	}

	private let seamRoot: ScopeGenerator.SeamRoot?
	/// The holes of the seam whose tree is generated, by site, which the sites and the stage calls of staged builders
	/// read. Empty outside a seam's tree, and in a seam's tree without holes.
	private let seamHoles: SeamHoles
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
	/// The fills enclosing this scope, by `ScopeGenerator.fillKey(of:)`, each with its function's name, which a call
	/// inside them of a seam that holds or passes up their site passes by name.
	private let enclosingFills: [String: String]
	/// The index in `fillsOfThisCall` of the next fill to create a generator for.
	private var nextFillIndex = 0
	private let erasedToConcreteExistential: Bool
	private let isPropertyCycle: Bool
	/// The declaration this scope repeats when it closes a cycle (see `ScopeGenerator.closedOnProperty`), or `nil`.
	private let closedOnProperty: Property?
	private let forMockGeneration: Bool
	private let startsCodeGeneration: Bool

	/// Whether a scope enclosing this one provides `property` to the scopes this one
	/// generates: it creates the property, or its unwrapped form, and is not an
	/// ancestor still being built. The instance of a lazily instantiated property does
	/// not count: it is read from that property, which a declaration with its label hides.
	/// Nor does a parameter of a function enclosing this scope that a lazy cycle closes on
	/// where nothing above the function provides its label: the parameter only carries a
	/// cycle-closing scope's nearest declaration into the function's body, which is
	/// generated as where the function takes no parameter of that label
	/// (`cycleParameterFormsNotProvidedAboveFunction`).
	private func isProvidedByEnclosingScope(_ property: Property) -> Bool {
		isProvidedByEnclosingScope(property, countingOnlyIfAvailableOverrides: true)
	}

	/// Whether the only enclosing provider of `property` is the override a mock root binds a property its tree receives
	/// only if available to, which defaults to `nil`: no enclosing scope creates the property, and the mock binds it to
	/// no node it builds and no parameter of `mock()`. A receiver of an `onlyIfAvailable` alias of that property reads
	/// the override where the alias is not created, but the alias is still created from its fulfilling property where
	/// that closes no cycle, so the type declaring it is handed what production hands it where no ancestor provides
	/// the property.
	private func isProvidedOnlyByOnlyIfAvailableOverride(_ property: Property) -> Bool {
		isProvidedByEnclosingScope(property)
			&& !isProvidedByEnclosingScope(property, countingOnlyIfAvailableOverrides: false)
	}

	private func isProvidedByEnclosingScope(_ property: Property, countingOnlyIfAvailableOverrides: Bool) -> Bool {
		Self.isProvided(
			property,
			byEnclosingScopeReceivableProperties: enclosingScopeReceivableProperties,
			exceptCycleParameterForms: cycleParameterFormsNotProvidedAboveFunction,
			andCycleParameterFormsBeingBuilt: cycleParameterFormsBeingBuilt,
			orBoundProperties: boundProperties,
			exceptOnlyIfAvailableOverrides: countingOnlyIfAvailableOverrides ? [] : onlyIfAvailableOverrideProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			childPropertyStack: childPropertyStack,
		)
	}

	/// Whether `property`, or its unwrapped form, is in `enclosingScopeReceivableProperties` but not among
	/// `cycleParameterFormsNotProvidedAboveFunction` or `cycleParameterFormsBeingBuilt`, or in `boundProperties` but not
	/// among `onlyIfAvailableOverrideProperties`, and is neither among `lazilyInstantiatedInstanceProperties` nor on
	/// `childPropertyStack`: what `isProvidedByEnclosingScope` asks of the scopes enclosing a scope, and what the scope
	/// declaring a function a lazy cycle closes on asks of the binding it passes each of the function's parameters.
	private static func isProvided(
		_ property: Property,
		byEnclosingScopeReceivableProperties enclosingScopeReceivableProperties: Set<Property>,
		exceptCycleParameterForms cycleParameterFormsNotProvidedAboveFunction: Set<Property>,
		andCycleParameterFormsBeingBuilt cycleParameterFormsBeingBuilt: Set<Property>,
		orBoundProperties boundProperties: Set<Property>,
		exceptOnlyIfAvailableOverrides onlyIfAvailableOverrideProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		childPropertyStack: [Property],
	) -> Bool {
		func isReceivable(_ property: Property) -> Bool {
			(
				(
					enclosingScopeReceivableProperties.contains(property)
						&& !cycleParameterFormsNotProvidedAboveFunction.contains(property)
						&& !cycleParameterFormsBeingBuilt.contains(property)
				)
					|| (boundProperties.contains(property) && !onlyIfAvailableOverrideProperties.contains(property)),
			) && !lazilyInstantiatedInstanceProperties.contains(property)
		}
		return (isReceivable(property) && !childPropertyStack.contains(property))
			|| (isReceivable(property.asUnwrappedProperty) && !childPropertyStack.contains(property.asUnwrappedProperty))
	}

	/// The forms of `formsNoDeclarationCreates` whose label is among `labelsBeingBuilt` (see `cycleParameterFormsBeingBuilt`).
	private static func formsBeingBuilt(
		ofCycleParameterFormsNoDeclarationCreates formsNoDeclarationCreates: Set<Property>,
		labelsBeingBuilt: Set<String>,
	) -> Set<Property> {
		formsNoDeclarationCreates.filter { labelsBeingBuilt.contains($0.label) }
	}
}

extension Dependency {
	/// The by-value property with which types further down the tree receive the instance of the lazily
	/// instantiated property this dependency puts in scope. `nil` when it puts none in scope: a received
	/// dependency declares nothing, whichever type it is.
	var lazilyInstantiatedInstanceProperty: Property? {
		switch source {
		case .instantiated:
			property.asLazilyInstantiatedInstanceProperty
		case .aliased, .forwarded:
			property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
		case .received:
			nil
		}
	}

	/// The dependency’s property, followed by `lazilyInstantiatedInstanceProperty` when there is one.
	var receivableProperties: [Property] {
		if let lazilyInstantiatedInstanceProperty {
			[property, lazilyInstantiatedInstanceProperty]
		} else {
			[property]
		}
	}
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

extension Dependency.Source {
	/// Whether the dependency is `@Received` under its declared label and type. An aliased dependency is not: the
	/// generated code binds it from its fulfilling property. Cycle validation counts a required alias as receiving
	/// that property; see `DependencyTreeGenerator.closingReceive(of:in:)`.
	var isReceived: Bool {
		switch self {
		case .received:
			true
		case .instantiated, .aliased, .forwarded:
			false
		}
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
	) {
		guard !property.firstGenericMatchesForwardedProperties(of: builtInstantiable) else { return nil }
		self.property = property
		self.declarationLocation = declarationLocation
		self.parent = parent
		builtType = builtInstantiable.concreteInstantiable
		// The forwarded properties are spelled out rather than as `ForwardedProperties` on the built type, which the
		// module that declares the property may not be able to see.
		forwardedPropertiesType = builtInstantiable.forwardedProperties.asForwardedPropertiesType.typeDescription
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
	/// Any other property matches, as does one that builds a type with no `@Forwarded` properties.
	func firstGenericMatchesForwardedProperties(of builtInstantiable: Instantiable) -> Bool {
		let forwardedProperties = builtInstantiable.forwardedProperties
		guard propertyType.isErasedInstantiator,
		      !forwardedProperties.isEmpty,
		      let forwardedArgument = generics?.first
		else { return true }
		// The forwarded argument is the same type as the only `@Forwarded` property.
		return (forwardedProperties.count == 1 && forwardedArgument == forwardedProperties[0].typeDescription)
			// The forwarded argument is the same as `InstantiableName.ForwardedProperties`.
			|| forwardedArgument == .nested(name: "ForwardedProperties", parentType: builtInstantiable.concreteInstantiable)
			// The forwarded argument is the same as the tuple the macro generates for `InstantiableName.ForwardedProperties`.
			|| forwardedArgument == forwardedProperties.asTupleTypeDescription
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
/// of the `@Sendable` builder function before which they are made.
struct SeamHoles {
	/// No holes: a tree that is not a seam's, or a seam's tree without holes.
	init() {
		seamType = nil
		sitesByPath = [:]
		passedUpHolesBySite = [:]
		stageCallsByPath = [:]
		internalNames = []
	}

	init(seamType: TypeDescription, holes: [SeamSignature.Hole]) {
		var sitesByPath = [[Property]: SeamSignature.Hole]()
		var passedUpHolesBySite = [SeamSignature.Hole.Site: SeamSignature.Hole]()
		var stageCallsByPath = [[Property]: [String]]()
		for hole in holes {
			guard hole.innerSeamType == nil else {
				passedUpHolesBySite[hole.site] = hole
				continue
			}
			sitesByPath[hole.sitePath] = hole
			// Each stage but the last is called just before the `@Sendable` builder function that starts the next.
			for (stageIndex, depth) in hole.stageBoundaryDepths.enumerated() {
				let stageFunction = stageIndex == 0 ? hole.internalName : "\(hole.internalName)_\(SeamSignature.Hole.stageName(at: stageIndex))"
				let nextStageFunction = "\(hole.internalName)_\(SeamSignature.Hole.stageName(at: stageIndex + 1))"
				let arguments = hole.stages[stageIndex].map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.label)" }.joined(separator: ", ")
				stageCallsByPath[Array(hole.sitePath.prefix(depth)), default: []].append(
					"let \(nextStageFunction) = \(stageFunction)(\(hole.stageStructType(at: stageIndex, qualifiedBy: nil).asSource)(\(arguments)))",
				)
			}
		}
		self.seamType = seamType
		self.sitesByPath = sitesByPath
		self.passedUpHolesBySite = passedUpHolesBySite
		self.stageCallsByPath = stageCallsByPath
		internalNames = Set(holes.map(\.internalName))
	}

	/// The name of every builder the seam's generated initializer takes, inside the initializer, which a call its tree
	/// makes passes up by name. Empty outside a seam's tree.
	let internalNames: Set<String>

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

	/// The stage calls made just before the `@Sendable` builder function of the property at the end of `sitePath`.
	func stageCalls(at sitePath: [Property]) -> [String] {
		stageCallsByPath.isEmpty ? [] : stageCallsByPath[sitePath, default: []]
	}

	/// The seam whose tree is generated, or `nil` for a tree that is no seam's.
	private let seamType: TypeDescription?
	private let sitesByPath: [[Property]: SeamSignature.Hole]
	private let passedUpHolesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]
	private let stageCallsByPath: [[Property]: [String]]
}
