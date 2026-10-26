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

	init(instantiable: Instantiable) {
		self.instantiable = instantiable
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
	}

	private(set) lazy var properties: [Property] = instantiable
		.dependencies
		.map(\.property)

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
			.map(\.property),
	)

	/// The properties this scope makes available to the scopes it builds: those it creates, and those a mock
	/// root builds because a type in its tree receives them. Read only once `propertiesToGenerate` is complete.
	private(set) lazy var providedProperties = createdProperties.union(
		propertiesToGenerate.compactMap {
			switch $0 {
			case let .instantiated(property, _, _):
				property
			case .aliased:
				// An alias is created, so it is already in `createdProperties`.
				nil
			}
		},
	)

	/// A received property this scope requires an ancestor to provide, with the location of the declaration that requires it.
	struct RequiredReceivedProperty {
		/// The property an ancestor must provide: the fulfilling property for an aliased dependency, the declared property otherwise.
		let property: Property
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
						declarationLocation: $0.declarationLocation,
						identifierRange: $0.identifierRange,
						typeAnnotationRange: $0.typeAnnotationRange,
						bareAttributeRange: $0.bareAttributeRange,
					)
				}
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				if onlyIfAvailable {
					nil
				} else {
					RequiredReceivedProperty(
						property: fulfillingProperty,
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

	func createScopeGenerator(
		for property: Property?,
		propertyStack: [Property],
		receivableProperties: Set<Property>,
		erasedToConcreteExistential: Bool,
		forMockGeneration: Bool = false,
	) throws -> ScopeGenerator {
		var childPropertyStack = propertyStack
		let isPropertyCycle: Bool
		if let property {
			isPropertyCycle = propertyStack.contains(property)
			childPropertyStack.insert(property, at: 0)
		} else {
			isPropertyCycle = false
		}
		/// Whether `property`, or its unwrapped form, is in `properties` and is not still being built.
		func isProperty(_ property: Property, availableIn properties: Set<Property>) -> Bool {
			[property, property.asUnwrappedProperty].contains {
				properties.contains($0) && !propertyStack.contains($0)
			}
		}
		let enclosingProperties = receivableProperties
		let receivableProperties = receivableProperties.union(providedProperties)
		func isPropertyUnavailable(_ property: Property) -> Bool {
			if forMockGeneration {
				// A mock builds, or is handed, every property an ancestor does not
				// create — onlyIfAvailable dependencies become optional mock parameters.
				// Only an ancestor that is still being built is unavailable, as in production.
				propertyStack.contains(property.asUnwrappedProperty)
			} else {
				!isProperty(property, availableIn: receivableProperties)
			}
		}
		let unavailableOptionalProperties = Set<Property>(instantiable.dependencies.flatMap { dependency in
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
		let scopeGenerator = try ScopeGenerator(
			instantiable: instantiable,
			property: property,
			propertiesToGenerate: isPropertyCycle ? [] : propertiesToGenerate.map {
				switch $0 {
				case let .instantiated(property, scope, erasedToConcreteExistential):
					try scope.createScopeGenerator(
						for: property,
						propertyStack: childPropertyStack,
						receivableProperties: receivableProperties,
						erasedToConcreteExistential: erasedToConcreteExistential,
						forMockGeneration: forMockGeneration,
					)
				case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
					ScopeGenerator(
						property: property,
						fulfillingProperty: fulfillingProperty,
						unavailableOptionalProperties: unavailableOptionalProperties,
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
						enclosingScopeProvidesProperty: isProperty(property, availableIn: enclosingProperties),
						declarationReference: declarationReference,
					)
				}
			},
			unavailableOptionalProperties: unavailableOptionalProperties,
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
}

extension Dependency.Source {
	var isReceived: Bool {
		switch self {
		case .received:
			true
		case .instantiated, .aliased, .forwarded:
			false
		}
	}
}
