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

// TODO: There is likely a way to simplify this code and jump directly to CombinedScope that would yield a performance win.
/// A model of the scoped dependencies required for an `@Instantiable` in the reachable dependency tree.
final class Scope {

    // MARK: Initialization

    init(instantiable: Instantiable) {
        self.instantiable = instantiable

        inheritedProperties = Set(
            instantiable
                .dependencies
                .filter {
                    switch $0.source {
                    case .forwarded,
                            .instantiated,
                            .lazyInstantiated:
                        return false
                    case .inherited:
                        return true
                    }
                }
                .map(\.property)
        )
    }

    // MARK: Internal

    let instantiable: Instantiable

    /// The properties that this scope is responsible for instantiating.
    var propertiesToInstantiate = [PropertyToInstantiate]() {
        didSet {
            instantiatedProperties = Set(
                propertiesToInstantiate
                    .filter { $0.type == .constant }
                    .map(\.property)
            )
            lazyInstantiatedProperties = Set(
                propertiesToInstantiate
                    .filter { $0.type == .lazy }
                    .map(\.property)
            )
        }
    }
    /// The properties that this scope inherits + passes to children that aren't declared on `instantiable`.
    var undeclaredInheritedProperties = Set<Property>()

    struct PropertyToInstantiate {
        let property: Property
        let instantiable: Instantiable
        let scope: Scope
        let type: PropertyType

        enum PropertyType {
            /// A `let` property.
            case constant
            // TODO: Enable lazy instantiated properties to forward themselves down their own scope.
            //       We can enable this without an unexpected retain problem because lazy instantiated
            //       properties are already retained.
            /// A  lazily instantiated property. Backed by an `Instantiator`.
            /// The instantiated product is not forwarded down the dependency tree.
            case lazy
            /// An `Instantiator` property.
            /// The instantiated product is not forwarded down the dependency tree. This is done intentionally to avoid unexpected retains.
            case instantiator
            /// A `ForwardingInstantiator` property.
            /// The instantiated product is not forwarded down the dependency tree. This is done intentionally to avoid unexpected retains.
            case forwardingInstantiator
        }
    }

    private(set) var instantiatedProperties = Set<Property>()
    private(set) var lazyInstantiatedProperties = Set<Property>()
    let inheritedProperties: Set<Property>

    var allInheritedProperties: Set<Property> {
        inheritedProperties.union(undeclaredInheritedProperties)
    }

    func createCombinedScope() -> CombinedScope {
        var childPropertyToInstantiableConstant = [Property: Instantiable]()
        var childPropertyToCombinedScopeMap = [Property: CombinedScope]()

        func findCombinedScopeInformation(on scope: Scope) {
            for propertyToInstantiate in scope.propertiesToInstantiate {
                switch propertyToInstantiate.type {
                case .constant:
                    childPropertyToInstantiableConstant[propertyToInstantiate.property] = propertyToInstantiate.instantiable
                    findCombinedScopeInformation(on: propertyToInstantiate.scope)
                case .lazy,
                        .instantiator,
                        .forwardingInstantiator:
                    let childCombinedScope = propertyToInstantiate
                        .scope
                        .createCombinedScope()
                    Task {
                        // Kick off code generation.
                        try await childCombinedScope.generateCode()
                    }
                    childPropertyToCombinedScopeMap[propertyToInstantiate.property] = propertyToInstantiate
                        .scope
                        .createCombinedScope()
                }
            }
        }

        findCombinedScopeInformation(on: self)

        let combinedScope = CombinedScope(
            instantiable: instantiable,
            childPropertyToInstantiableConstant: childPropertyToInstantiableConstant,
            childPropertyToCombinedScopeMap: childPropertyToCombinedScopeMap,
            inheritedProperties: allInheritedProperties
        )
        Task {
            // Kick off code generation.
            try await combinedScope.generateCode()
        }
        return combinedScope
    }
}
