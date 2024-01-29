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
        case instantiated(Property, Scope)
        case aliased(Property, fulfilledBy: Property)
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
                    nil
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
            let scopeGenerator = ScopeGenerator(
                instantiable: instantiable,
                property: property,
                propertiesToGenerate: try propertiesToGenerate.map {
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
                            fulfillingProperty: fulfillingProperty
                        )
                    }
                }
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
                    .reversed()
                    .joined(separator: " -> "))
                """
            }
        }
    }
}
