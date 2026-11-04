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

	/// The properties this scope always creates: those it instantiates, is forwarded, or assigns to a required
	/// alias. An `onlyIfAvailable` alias is left out, since it is not created while what it renames is unavailable.
	private lazy var unconditionallyCreatedProperties = Set(
		instantiable
			.dependencies
			.filter {
				switch $0.source {
				case .instantiated, .forwarded:
					true
				case let .aliased(_, _, onlyIfAvailable):
					!onlyIfAvailable
				case .received:
					false
				}
			}
			.flatMap(\.receivableProperties),
	)

	/// The received properties this scope requires an ancestor to provide. An alias of a property this scope always
	/// creates refers to that property, so it requires nothing of an ancestor: what that property needs, its own
	/// declaration requires. An alias of an `onlyIfAvailable` alias this scope declares is listed, so that validation
	/// can check the alias it refers to is created.
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
			receivableProperties: receivableProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			alwaysAvailableProperties: alwaysAvailableProperties,
			boundProperties: boundProperties,
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
					hole: fill.hole,
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
	init(
		scope: Scope,
		property: Property?,
		propertyStack: [Property],
		receivableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		alwaysAvailableProperties: Set<Property>,
		boundProperties: Set<Property>,
		runtimeOptionalProperties: Set<Property>,
		seamRoot: ScopeGenerator.SeamRoot?,
		seamHoles: SeamHoles,
		sitePath: [Property],
		enclosingFills: [String: String] = [:],
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
		startsCodeGeneration: Bool,
		fill: SeamSignature.Hole? = nil,
		fillKey: String? = nil,
		previousPassGenerator: ScopeGenerator?,
		cycleParameterContexts: [Property: CycleParameterContext],
		cycleParameterProvidedForms: Set<Property>,
	) {
		var childPropertyStack = propertyStack
		let isPropertyCycle: Bool
		if let property {
			isPropertyCycle = propertyStack.contains(property)
			childPropertyStack.insert(property, at: 0)
			if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
				childPropertyStack.insert(instanceProperty, at: 0)
			}
		} else {
			isPropertyCycle = false
		}
		// The parameters of this scope's builder function that the pass before found, when a lazy cycle closes on it,
		// or those of the function a cycle-closing scope refers to. Nearly every scope has neither.
		let ownCycleParameters = if !isPropertyCycle, fill == nil, property != nil {
			previousPassGenerator?.foundCycleParameters ?? []
		} else {
			[CycleParameter]()
		}
		let closedOnContext = if isPropertyCycle, let property {
			cycleParameterContexts[property]
		} else {
			CycleParameterContext?.none
		}
		let enclosingScopeReceivableProperties = receivableProperties
		var receivableProperties = receivableProperties.union(scope.createdProperties)
		// The parameters this scope passes the builder function a lazy cycle closes on that are unavailable where it
		// passes them, which it passes `nil`: computed below, once `isPropertyUnavailable` can be asked.
		var cycleParameterUnavailableProperties = Set<Property>()
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
		func isPropertyUnavailable(_ property: Property) -> Bool {
			if scope.createdProperties.contains(property) {
				return false
			} else if forMockGeneration, scope.publicMockCall == nil {
				// A mock builds, or is handed, every property an ancestor does not
				// create — onlyIfAvailable dependencies become optional mock parameters.
				// Only a property that is still being built is unavailable, as in production. A mock promotes a
				// received optional property as the non-optional value it builds, so a receive of either form of
				// it is unavailable inside the tree it builds.
				let unwrappedProperty = property.asUnwrappedProperty
				return childPropertyStack.contains {
					$0.label == unwrappedProperty.label && $0.typeDescription.unwrapped == unwrappedProperty.typeDescription
				}
			} else {
				// A mock binds what its tree receives, but not what only the public mocks it calls receive: a call passes
				// such a property only where the tree provides it, as production would, and `nil` elsewhere.
				func isReceivable(_ property: Property) -> Bool {
					receivableProperties.contains(property) || (forMockGeneration && boundProperties.contains(property))
				}
				let propertyIsAvailableInParentStack = isReceivable(property) && !childPropertyStack.contains(property)
				let unwrappedPropertyIsAvailableInParentStack = isReceivable(property.asUnwrappedProperty) && !childPropertyStack.contains(property.asUnwrappedProperty)
				return !(propertyIsAvailableInParentStack || unwrappedPropertyIsAvailableInParentStack)
			}
		}
		if let closedOnContext {
			// A cycle-closing scope passes each parameter its nearest declaration of the label: one a scope between it and
			// the function declares, or else the function's own parameter, which is always in scope. A declaration that
			// does not provide the parameter's form, or that is still being built around this scope, is unavailable. The
			// function takes no parameter of this scope's own label (see `ScopeGenerator.foundCycleParameters`).
			let propertiesBuiltBetween = childPropertyStack.dropFirst().prefix { $0 != property }
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
			for parameter in ownCycleParameters where !parameter.isRequired && isPropertyUnavailable(parameter.property) {
				cycleParameterUnavailableProperties.insert(parameter.property)
			}
			receivableProperties = receivableProperties
				.filter { !ownCycleParameterLabels.contains($0.label) }
				.union(ownCycleParameters.flatMap(\.providedForms))
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
		if parameterProvidedForms.isEmpty || isPropertyCycle {
			childCycleParameterProvidedForms = parameterProvidedForms
			childReceivableProperties = receivableProperties
		} else {
			let declaredProperties = scope.createdProperties.union(scope.propertiesToDeclare)
			let declaredLabels = Set(declaredProperties.map(\.label))
			childCycleParameterProvidedForms = parameterProvidedForms.filter { !declaredLabels.contains($0.label) }
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
		self.runtimeOptionalProperties = runtimeOptionalProperties.isEmpty
			? runtimeOptionalProperties
			: Self.runtimeOptionalProperties(declaredBy: scope, enclosedBy: runtimeOptionalProperties)
		self.seamRoot = seamRoot
		self.seamHoles = seamHoles
		// The path is kept only where a hole needs it: a site, and the stage calls of a staged builder, are found by it.
		self.sitePath = seamHoles.isEmpty ? [] : sitePath + (property.map { [$0] } ?? [])
		self.fill = fill
		self.fillKey = fillKey
		self.erasedToConcreteExistential = erasedToConcreteExistential
		self.isPropertyCycle = isPropertyCycle
		self.forMockGeneration = forMockGeneration
		self.startsCodeGeneration = startsCodeGeneration
		// A scope that closes a cycle calls no seam; any other seam call passes a builder for each of the seam's holes. A
		// call inside a fill of a seam that holds the fill's site, or that passes the site's builder up, passes that fill
		// by name, so every instance of the seam calls the same fills with its own scopes.
		self.enclosingFills = enclosingFills
		holeArguments = isPropertyCycle ? [] : scope.holeArguments
		holeArgumentsToFill = holeArguments.filter { holeArgument in
			if case .fill = holeArgument {
				enclosingFills[ScopeGenerator.fillKey(of: holeArgument.hole)] == nil
			} else {
				false
			}
		}
		childGenerators.reserveCapacity(propertiesToGenerate.count + holeArgumentsToFill.count)
	}

	/// The generators created so far for `propertiesToGenerate`, in order, followed by those of the fills of
	/// `holeArguments`.
	var childGenerators = [ScopeGenerator]()

	/// The next of `propertiesToGenerate` to create a generator for, or `nil` once every one has its generator.
	mutating func nextPropertyToGenerate() -> Scope.PropertyToGenerate? {
		guard nextPropertyIndex < propertiesToGenerate.count else { return nil }
		let propertyToGenerate = propertiesToGenerate[nextPropertyIndex]
		nextPropertyIndex += 1
		return propertyToGenerate
	}

	/// The next fill of `holeArguments` to create a generator for, once every one of `propertiesToGenerate` has its
	/// generator, or `nil` once every fill has its generator.
	mutating func nextFill() -> (hole: SeamSignature.Hole, scope: Scope)? {
		while nextHoleArgumentIndex < holeArgumentsToFill.count {
			let holeArgument = holeArgumentsToFill[nextHoleArgumentIndex]
			nextHoleArgumentIndex += 1
			if case let .fill(hole, scope) = holeArgument {
				return (hole, scope)
			}
		}
		return nil
	}

	/// The scope under construction for the property a fill of this scope's seam call builds: the scope of the type
	/// that fulfills the hole in the caller's declarations, built with the stack the seam whose tree holds the site
	/// reaches it with, and with the fields of the site's scope struct in scope beside what encloses the call.
	func fillUnderConstruction(hole: SeamSignature.Hole, scope: Scope) throws -> ScopeGeneratorUnderConstruction {
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
			// A value the fill takes from the caller's scope is available as it would be to a pass-through of the call:
			// one the caller's path is still building is not, so a receive of it only if available is passed `nil`.
			receivableProperties: childReceivableProperties.filter { !fieldLabels.contains($0.label) && !childPropertyStack.contains($0) }.union(fieldForms),
			lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties.filter { !fieldLabels.contains($0.label) }.union(fieldInstanceProperties),
			alwaysAvailableProperties: alwaysAvailableProperties.union(fieldForms),
			boundProperties: boundProperties,
			runtimeOptionalProperties: runtimeOptionalProperties.filter { !fieldLabels.contains($0.label) },
			seamRoot: nil,
			seamHoles: seamHoles,
			sitePath: sitePath,
			enclosingFills: enclosingFillsOfThisCall,
			erasedToConcreteExistential: hole.erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
			startsCodeGeneration: startsCodeGeneration,
			fill: hole,
			fillKey: ScopeGenerator.fillKey(of: hole),
			// The pass before created a fill's generator around the generator of the property it builds. A fill is a
			// function of its own, declared where the seam is called, so no function enclosing the call that a lazy cycle
			// closes on encloses a cycle-closing scope in the fill.
			previousPassGenerator: previousPassChildGenerator?.children.first,
			cycleParameterContexts: [:],
			cycleParameterProvidedForms: [],
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
				receivableProperties: childReceivableProperties,
				lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
				alwaysAvailableProperties: alwaysAvailableProperties,
				boundProperties: boundProperties,
				runtimeOptionalProperties: runtimeOptionalProperties,
				seamRoot: nil,
				seamHoles: seamHoles,
				sitePath: sitePath,
				enclosingFills: enclosingFills,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
				startsCodeGeneration: startsCodeGeneration,
				previousPassGenerator: previousPassChildGenerator,
				cycleParameterContexts: childCycleParameterContexts,
				cycleParameterProvidedForms: childCycleParameterProvidedForms,
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
		for case let .fill(hole, _) in holeArgumentsToFill {
			fills[ScopeGenerator.fillKey(of: hole)] = ScopeGenerator.fillFunctionName(of: hole)
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
						value: enclosingFills[fillKey] ?? ScopeGenerator.fillFunctionName(of: hole),
						enclosingFillKey: enclosingFills[fillKey] == nil ? nil : fillKey,
					)
				case let .passUp(hole):
					// The seam whose tree makes the call takes the builder for the hole's site – its own, or one it passes up –
					// and passes it on.
					return ScopeGenerator.HoleCallArgument(
						label: hole.builderLabel,
						value: seamHoles.hole(taking: hole)?.internalName ?? hole.internalName,
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
			cycleParameters: passedCycleParameters,
			builtCycleParameters: ownCycleParameters,
			cycleParameterUnavailableProperties: cycleParameterUnavailableProperties,
			callSiteLazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties,
		)
		let scopeGenerator = if let fill {
			ScopeGenerator(fill: fill, key: fillKey ?? "", child: builtGenerator)
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
	private let propertiesToGenerate: [Scope.PropertyToGenerate]
	/// The index in `propertiesToGenerate` of the next property to create a generator for.
	private var nextPropertyIndex = 0
	private let childPropertyStack: [Property]
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
	/// `receivableProperties` as the scopes this scope builds see them: without the forms of a parameter of an enclosing
	/// function that this scope's declaration of the parameter's label hides.
	private let childReceivableProperties: Set<Property>
	/// The properties in scope wherever this scope's tree is built: those this scope and the scopes enclosing it
	/// forward, and those a mock is passed.
	private let alwaysAvailableProperties: Set<Property>
	private let boundProperties: Set<Property>
	/// The properties that may be `nil` where this scope's aliases and the scopes it builds read them, each by its
	/// exact form: both forms of a seam parameter the seam's callers may pass `nil` for, the unwrapped form of a required
	/// optional parameter, and both forms of an `onlyIfAvailable` alias of one, which no declaration on the path from
	/// the seam's root down to and including this scope declares otherwise. See `createScopeGenerator`.
	private let runtimeOptionalProperties: Set<Property>

	/// `enclosingRuntimeOptionalProperties`, the properties that may be `nil` above `scope`, as the aliases `scope`
	/// declares and the scopes it builds see them. The closest declaration of a property's label decides: one `scope`
	/// instantiates, or forwards – a seam's root's own forwarded properties included – or declares by an alias that is
	/// created whenever `scope` is, is not `nil` there, so every form of its label leaves the set, while an
	/// `onlyIfAvailable` alias of a property in the set may be `nil` itself, so both of its forms join it – a chain of
	/// such aliases on `scope` included. A received property declares nothing. Each property is held by its exact
	/// form, so that an alias of exactly a required optional parameter, which the set never holds, is created.
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
		// An alias is the closest declaration of its property for the aliases of the same scope too, so an alias of
		// another of the scope's aliases may be `nil` exactly when that one may: found to a fixed point. An alias that
		// keeps the label it retypes is not in scope where its own value is read, so the forms of its fulfilling
		// property stay in the set, which `addAliasGenerator` judges the alias by; a read of those forms beneath the
		// alias is the hidden-label error, reported before any alias is judged.
		for alias in aliases {
			let formsTheAliasReads: Set<Property> = alias.property.label == alias.fulfillingProperty.label
				? [alias.fulfillingProperty, alias.fulfillingProperty.asUnwrappedProperty]
				: []
			runtimeOptionalProperties = runtimeOptionalProperties.filter { $0.label != alias.property.label || formsTheAliasReads.contains($0) }
		}
		var foundAlias = true
		while foundAlias {
			foundAlias = false
			for alias in aliases where alias.onlyIfAvailable && !runtimeOptionalProperties.contains(alias.property) && runtimeOptionalProperties.contains(alias.fulfillingProperty) {
				runtimeOptionalProperties.insert(alias.property)
				runtimeOptionalProperties.insert(alias.property.asUnwrappedProperty)
				foundAlias = true
			}
		}
		return runtimeOptionalProperties
	}

	private let seamRoot: ScopeGenerator.SeamRoot?
	/// The holes of the seam whose tree is generated, by site, which the sites and the stage calls of staged builders
	/// read. Empty outside a seam's tree, and in a seam's tree without holes.
	private let seamHoles: SeamHoles
	/// The properties from the root of the tree down to this scope's, when `seamHoles` is not empty; otherwise empty.
	private let sitePath: [Property]
	/// The hole whose fill this scope builds the property of, or `nil` for every other scope.
	private let fill: SeamSignature.Hole?
	/// How the seam call this scope makes passes each builder (see `Scope.holeArguments`).
	private let holeArguments: [Scope.HoleArgument]
	/// The fills of `holeArguments` this scope's generator holds: those no enclosing call already fills.
	private let holeArgumentsToFill: [Scope.HoleArgument]
	/// The fills enclosing this scope, by `ScopeGenerator.fillKey(of:)`, each with its function's name, which a call
	/// inside them of a seam that holds or passes up their site passes by name.
	private let enclosingFills: [String: String]
	/// For a scope a fill builds the property of, the key of that fill (see `ScopeGenerator.fillKey(of:)`).
	private let fillKey: String?
	/// The index in `holeArguments` of the next to look at for a fill.
	private var nextHoleArgumentIndex = 0
	private let erasedToConcreteExistential: Bool
	private let isPropertyCycle: Bool
	private let forMockGeneration: Bool
	private let startsCodeGeneration: Bool

	/// Whether a scope enclosing this one provides `property` to the scopes this one
	/// generates: it creates the property, or its unwrapped form, and is not an
	/// ancestor still being built. The instance of a lazily instantiated property does
	/// not count: it is read from that property, which a declaration with its label hides.
	private func isProvidedByEnclosingScope(_ property: Property) -> Bool {
		func isReceivable(_ property: Property) -> Bool {
			(enclosingScopeReceivableProperties.contains(property) || boundProperties.contains(property))
				&& !lazilyInstantiatedInstanceProperties.contains(property)
		}
		return (isReceivable(property) && !childPropertyStack.contains(property))
			|| (isReceivable(property.asUnwrappedProperty) && !childPropertyStack.contains(property.asUnwrappedProperty))
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
	}

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
