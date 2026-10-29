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

	/// - Parameter dependenciesLeftOut: The dependencies `instantiable` declared before a mock scope
	///   left them out because the type's hand-written mock is not passed them.
	init(instantiable: Instantiable, dependenciesLeftOut: [Dependency] = []) {
		self.instantiable = instantiable
		self.dependenciesLeftOut = dependenciesLeftOut
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

	/// The properties that this scope is responsible for instantiating.
	var propertiesToGenerate = [PropertyToGenerate]()

	enum PropertyToGenerate {
		case instantiated(Property, Scope, erasedToConcreteExistential: Bool)
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
			     let .aliased(property, _, _, _, _):
				property
			}
		}

		/// The by-value property with which types further down the tree receive the instance of the lazily
		/// instantiated property this declares. `nil` when it declares none.
		var lazilyInstantiatedInstanceProperty: Property? {
			switch self {
			case let .instantiated(property, _, _):
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

	/// The properties this scope declares for the scopes it builds: those it generates, which for a mock root
	/// include the received dependencies promoted to its children, and those its type forwards. A property
	/// declared here shadows one with the same label that was lazily instantiated further up the tree.
	/// Read only once `propertiesToGenerate` is complete.
	private lazy var declaredProperties: [Property] = propertiesToGenerate.map(\.property)
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
				+ forwardedLazilyInstantiatedInstanceProperties,
		).filter { !declaredProperties.contains($0) },
	)

	/// The properties this scope makes available to the scopes it builds: those it creates, and those a mock
	/// root builds because a type in its tree receives them. Read only once `propertiesToGenerate` is complete.
	private(set) lazy var providedProperties = createdProperties.union(
		propertiesToGenerate.flatMap { propertyToGenerate in
			switch propertyToGenerate {
			case .instantiated:
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
	func createScopeGenerator(
		for property: Property?,
		propertyStack: [Property],
		receivableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		boundProperties: Set<Property> = [],
		alwaysAvailableProperties: Set<Property> = [],
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool = false,
	) throws -> ScopeGenerator {
		var scopeGeneratorsUnderConstruction = [ScopeGeneratorUnderConstruction(
			scope: self,
			property: property,
			propertyStack: propertyStack,
			receivableProperties: receivableProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			alwaysAvailableProperties: alwaysAvailableProperties,
			boundProperties: boundProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			forMockGeneration: forMockGeneration,
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
				}
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
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool,
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
		let enclosingScopeReceivableProperties = receivableProperties
		let receivableProperties = receivableProperties.union(scope.createdProperties)
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
			} else if forMockGeneration {
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
				let propertyIsAvailableInParentStack = receivableProperties.contains(property) && !childPropertyStack.contains(property)
				let unwrappedPropertyIsAvailableInParentStack = receivableProperties.contains(property.asUnwrappedProperty) && !childPropertyStack.contains(property.asUnwrappedProperty)
				return !(propertyIsAvailableInParentStack || unwrappedPropertyIsAvailableInParentStack)
			}
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
		// A forwarded property is a parameter of the function that builds the scope, so it is in scope wherever
		// the scope's tree is built. Nearly every scope forwards nothing, so most share the set they were given.
		let forwardedProperties = scope.instantiable.forwardedReceivableProperties
		self.alwaysAvailableProperties = forwardedProperties.isEmpty
			? alwaysAvailableProperties
			: alwaysAvailableProperties.union(forwardedProperties)
		self.boundProperties = boundProperties
		self.erasedToConcreteExistential = erasedToConcreteExistential
		self.isPropertyCycle = isPropertyCycle
		self.forMockGeneration = forMockGeneration
		childGenerators.reserveCapacity(propertiesToGenerate.count)
	}

	/// The generators created so far for `propertiesToGenerate`, in order.
	var childGenerators = [ScopeGenerator]()

	/// The next of `propertiesToGenerate` to create a generator for, or `nil` once every one has its generator.
	mutating func nextPropertyToGenerate() -> Scope.PropertyToGenerate? {
		guard nextPropertyIndex < propertiesToGenerate.count else { return nil }
		let propertyToGenerate = propertiesToGenerate[nextPropertyIndex]
		nextPropertyIndex += 1
		return propertyToGenerate
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
				receivableProperties: receivableProperties,
				lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
				alwaysAvailableProperties: alwaysAvailableProperties,
				boundProperties: boundProperties,
				erasedToConcreteExistential: erasedToConcreteExistential,
				forMockGeneration: forMockGeneration,
			)
		}
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
			declarationReference: declarationReference,
		))
	}

	/// Creates the scope's generator once `childGenerators` holds a generator for each of `propertiesToGenerate`.
	func scopeGenerator() -> ScopeGenerator {
		let scopeGenerator = ScopeGenerator(
			instantiable: scope.instantiable,
			property: property,
			propertiesToGenerate: childGenerators,
			unavailableOptionalProperties: unavailableOptionalProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			forwardedLazilyInstantiatedInstanceProperties: scope.forwardedLazilyInstantiatedInstanceProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			isPropertyCycle: isPropertyCycle,
		)
		if !forMockGeneration {
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
	private let lazilyInstantiatedInstanceProperties: Set<Property>
	private let childLazilyInstantiatedInstanceProperties: Set<Property>
	private let unavailableOptionalProperties: Set<Property>
	/// The properties in scope wherever this scope's tree is built: those this scope and the scopes enclosing it
	/// forward, and those a mock is passed.
	private let alwaysAvailableProperties: Set<Property>
	private let boundProperties: Set<Property>
	private let erasedToConcreteExistential: Bool
	private let isPropertyCycle: Bool
	private let forMockGeneration: Bool

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
