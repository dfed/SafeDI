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

import Collections

/// A model of the scoped dependencies required for an `@Instantiable` in the reachable dependency tree.
final class Scope: Hashable {
	// MARK: Initialization

	init(instantiable: Instantiable) {
		self.instantiable = instantiable
	}

	// MARK: Equatable

	static func == (lhs: Scope, rhs: Scope) -> Bool {
		// Scopes are only identicial if they are the same object
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
		case aliased(Property, fulfilledBy: Property, erasedToConcreteExistential: Bool, onlyIfAvailable: Bool)
	}

	var properties: [Property] {
		instantiable
			.dependencies
			.map(\.property)
	}

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
			.map(\.property)
	)

	var requiredReceivedProperties: [Property] {
		instantiable
			.dependencies
			.compactMap {
				switch $0.source {
				case let .received(onlyIfAvailable):
					if onlyIfAvailable {
						nil
					} else {
						$0.property
					}
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					if onlyIfAvailable {
						nil
					} else {
						fulfillingProperty
					}
				case .forwarded,
				     .instantiated:
					nil
				}
			}
	}

	func createScopeGenerator(
		for property: Property?,
		propertyStack: OrderedSet<Property>,
		receivableProperties: Set<Property>,
		erasedToConcreteExistential: Bool
	) throws -> ScopeGenerator {
		var childPropertyStack = propertyStack
		let isPropertyCycle: Bool
		if let property {
			isPropertyCycle = propertyStack.contains(property)
			childPropertyStack.insert(property, at: 0)
		} else {
			isPropertyCycle = false
		}
		let receivableProperties = receivableProperties.union(createdProperties)
		func isPropertyUnavailable(_ property: Property) -> Bool {
			let propertyIsAvailableInParentStack = receivableProperties.contains(property) && !propertyStack.contains(property)
			let unwrappedPropertyIsAvailableInParentStack = receivableProperties.contains(property.asUnwrappedProperty) && !propertyStack.contains(property.asUnwrappedProperty)
			return !(propertyIsAvailableInParentStack || unwrappedPropertyIsAvailableInParentStack)
		}
		let unavailableOptionalProperties = Set<Property>(instantiable.dependencies.compactMap { dependency in
			switch dependency.source {
			case .instantiated, .forwarded:
				nil
			case let .received(onlyIfAvailable):
				if onlyIfAvailable, isPropertyUnavailable(dependency.property) {
					dependency.property
				} else {
					nil
				}
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				if onlyIfAvailable, isPropertyUnavailable(fulfillingProperty) {
					fulfillingProperty
				} else {
					nil
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
						erasedToConcreteExistential: erasedToConcreteExistential
					)
				case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
					ScopeGenerator(
						property: property,
						fulfillingProperty: fulfillingProperty,
						unavailableOptionalProperties: unavailableOptionalProperties,
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable
					)
				}
			},
			unavailableOptionalProperties: unavailableOptionalProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			isPropertyCycle: isPropertyCycle
		)
		Task.detached {
			// Kick off code generation.
			try await scopeGenerator.generateCode()
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
