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
        case aliased(Property, fulfilledBy: Property, erasedToConcreteExistential: Bool)
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
                case let .aliased(fulfillingProperty, _):
                    fulfillingProperty
                case .forwarded,
                     .instantiated:
                    nil
                }
            }
    }

    func createScopeGenerator(
        for property: Property?,
        propertyStack: OrderedSet<Property>,
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
        let scopeGenerator = try ScopeGenerator(
            instantiable: instantiable,
            property: property,
            propertiesToGenerate: isPropertyCycle ? [] : propertiesToGenerate.map {
                switch $0 {
                case let .instantiated(property, scope, erasedToConcreteExistential):
                    try scope.createScopeGenerator(
                        for: property,
                        propertyStack: childPropertyStack,
                        erasedToConcreteExistential: erasedToConcreteExistential
                    )
                case let .aliased(property, fulfillingProperty, erasedToConcreteExistential):
                    ScopeGenerator(
                        property: property,
                        fulfillingProperty: fulfillingProperty,
                        erasedToConcreteExistential: erasedToConcreteExistential
                    )
                }
            },
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
