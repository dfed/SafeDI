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
final class Scope {

    // MARK: Initialization

    init(instantiable: Instantiable) {
        self.instantiable = instantiable
    }

    // MARK: Internal

    let instantiable: Instantiable

    /// The properties that this scope is responsible for instantiating.
    var propertiesToInstantiate = [PropertyToInstantiate]()

    enum PropertyToInstantiate {
        case instantiated(Property, Scope)
        case aliased(Property, fulfilledBy: Property)

        var property: Property {
            switch self {
            case
                let .instantiated(property, _),
                let .aliased(property, _):
                property
            }
        }

        var scope: Scope? {
            switch self {
            case let .instantiated(_, scope):
                scope
            case .aliased:
                nil
            }
        }
    }

    var properties: [Property] {
        instantiable
            .dependencies
            .map(\.property)
    }

    var receivedProperties: [Property] {
        instantiable
            .dependencies
            .compactMap {
                switch $0.source {
                case .received:
                    $0.property
                case let .aliased(fulfillingProperty):
                    fulfillingProperty
                case .forwarded,
                        .instantiated:
                    return nil
                }
            }
    }

    func createScopeGenerator(
        for property: Property? = nil,
        instantiableStack: OrderedSet<Instantiable> = [],
        propertyStack: OrderedSet<Property> = []
    ) throws -> ScopeGenerator {
        if let cycleIndex = instantiableStack.firstIndex(of: instantiable) {
            throw ScopeError.dependencyCycleDetected([instantiable] + instantiableStack.elements[0...cycleIndex])
        } else {
            var childInstantiableStack = instantiableStack
            childInstantiableStack.insert(instantiable, at: 0)
            var childPropertyStack = propertyStack
            if let property {
                childPropertyStack.insert(property, at: 0)
            }
            let receivedProperties = Set(
                instantiableStack
                    .flatMap(\.dependencies)
                    .filter {
                        switch $0.source {
                        // The source has been injected into the dependency tree.
                        case .instantiated,
                                .forwarded,
                            // This property has been re-injected into the dependency tree under a new alias.
                                .aliased:
                            return !propertyStack.contains($0.property) && $0.property != property
                        case .received:
                            return false
                        }
                    }
                    .map(\.property)
            ).subtracting(
                // We want the local version of any instantiated property.
                propertiesToInstantiate.map(\.property)
            )
            let scopeGenerator = ScopeGenerator(
                instantiable: instantiable,
                property: property,
                propertiesToGenerate: try propertiesToInstantiate.map {
                    switch $0 {
                    case let .instantiated(property, scope):
                        try scope.createScopeGenerator(
                            for: property,
                            instantiableStack: childInstantiableStack,
                            propertyStack: childPropertyStack
                        )
                    case let .aliased(property, fulfilledBy: fulfillingProperty):
                        ScopeGenerator(
                            property: property,
                            fulfillingProperty: fulfillingProperty,
                            receivedProperties: receivedProperties
                        )
                    }
                },
                receivedProperties: receivedProperties
            )
            Task.detached {
                // Kick off code generation.
                try await scopeGenerator.generateCode()
            }
            return scopeGenerator
        }
    }

    // MARK: ScopeError

    private enum ScopeError: Error, CustomStringConvertible {

        case dependencyCycleDetected([Instantiable])

        var description: String {
            switch self {
            case let .dependencyCycleDetected(instantiables):
                """
                Dependency cycle detected!
                \(instantiables
                    .map(\.concreteInstantiableType.asSource)
                    .joined(separator: " -> "))
                """
            }
        }
    }
}
