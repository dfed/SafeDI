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

/// A model of the scoped dependencies required to instantiate all constants within a `Scope` tree.
actor CombinedScope {

    // MARK: Initialization

    init(
        instantiable: Instantiable,
        childPropertyToInstantiableConstant: [Property: Instantiable],
        childPropertyToCombinedScopeMap: [Property: CombinedScope],
        inheritedProperties: Set<Property>
    ) {
        self.instantiable = instantiable
        self.childPropertyToInstantiableConstant = childPropertyToInstantiableConstant
        self.childPropertyToCombinedScopeMap = childPropertyToCombinedScopeMap
        self.inheritedProperties = inheritedProperties
    }

    // MARK: Internal

    let instantiable: Instantiable

    func generateCode(leadingWhitespace: String = "") async throws -> String {
        do {
            while let satisfiableProperty = try nextSatisfiableProperty() {
                let satisfiedProperty: Property
                let initializer: String
                switch satisfiableProperty {
                case let .constant(property, instantiable):
                    satisfiedProperty = property
                    let concreteTypeName = instantiable.concreteInstantiableType.asSource
                    let argumentList = try instantiable.initializer.createInitializerArgumentList(given: instantiable.dependencies)
                    initializer = "\(concreteTypeName)(\(argumentList))"

                case let .combinedScope(property, combinedScope):
                    satisfiedProperty = property
                    let concreteTypeName = property.typeDescription.asSource
                    let returnTypeName = property.typeDescription.asInstantiatedType.asSource
                    let argumentList = try instantiable.initializer.createInitializerArgumentList(given: instantiable.dependencies)
                    let generatedCode = try await combinedScope.generateCode(leadingWhitespace: leadingWhitespace + "    ")
                    let returnLine = "return \(returnTypeName)(\(argumentList)"

                    let closureArguments: String
                    if concreteTypeName == Dependency.forwardingInstantiatorType {
                        let forwardedProperties = instantiable.dependencies.filter { $0.source == .forwarded }
                        // TODO: Would be better to match types rather than assuming property order for the forwarded properties.
                        closureArguments = " \(forwardedProperties.map(\.property.label).joined(separator: ", ")) in"
                    } else { // Dependency.instantiatorType
                        closureArguments = ""
                    }

                    initializer = """
                        \(concreteTypeName) {\(closureArguments)
                            \(generatedCode)
                            \(returnLine)
                        }
                        """
                }

                resolvedProperties.insert(satisfiedProperty)
                generatedCode.append("let \(satisfiedProperty.label): \(satisfiedProperty.typeDescription.asSource) = \(initializer))")
            }
        } catch {
            // Reset state so next time we call this we'll regenerate the error.
            generatedCode = ""
            remainingProperties = generateRemainingProperties()
            throw error
        }

        if leadingWhitespace.isEmpty {
            return generatedCode
        } else {
            return generatedCode
                .split(separator: "\n")
                .map { leadingWhitespace + $0 }
                .joined(separator: "\n")
        }
    }

    // MARK: Private

    private let childPropertyToInstantiableConstant: [Property: Instantiable]
    private let childPropertyToCombinedScopeMap: [Property: CombinedScope]
    private let inheritedProperties: Set<Property>

    private lazy var remainingProperties: [Property] = generateRemainingProperties()
    private var resolvedProperties = Set<Property>()
    private var generatedCode = ""

    private func nextSatisfiableProperty() throws -> SatisfiableProperty? {
        guard !remainingProperties.isEmpty else {
            return nil
        }

        for property in remainingProperties {
            if
                let instantiable = childPropertyToInstantiableConstant[property],
                hasResolvedAllPropertiesRequired(for: instantiable)
            {
                return .constant(property, instantiable)
            } else if
                let combinedScope = childPropertyToCombinedScopeMap[property],
                hasResolvedAllPropertiesRequired(for: combinedScope.instantiable)
            {
                return .combinedScope(property, combinedScope)
            }
        }

        throw CombinedScopeError.unresolvableDependencies(
            remainingProperties.compactMap { property in
                if let instantiable = childPropertyToInstantiableConstant[property] {
                    return .constant(property, instantiable)
                } else if let combinedScope = childPropertyToCombinedScopeMap[property] {
                    return .combinedScope(property, combinedScope)
                } else {
                    return nil
                }
            },
            instantiable)
    }

    private func hasResolvedAllPropertiesRequired(for instantiable: Instantiable) -> Bool {
        firstUnresolvedDependency(of: instantiable) == nil
    }

    private func firstUnresolvedDependency(of instantiable: Instantiable) -> Property? {
        instantiable.dependencies.map(\.property).first(where: { property in
            !(resolvedProperties.contains(property) || inheritedProperties.contains(property))
        })
    }

    private func unresolvedDependencies(of instantiable: Instantiable) -> [Property] {
        instantiable.dependencies.map(\.property).filter { property in
            !(resolvedProperties.contains(property) || inheritedProperties.contains(property))
        }
    }

    nonisolated
    private func generateRemainingProperties() -> [Property] {
        (
            Array<Property>(childPropertyToInstantiableConstant.keys)
            + Array<Property>(childPropertyToCombinedScopeMap.keys)
        )
        .sorted()
    }

    // MARK: SatisfiableProperty

    private enum SatisfiableProperty {
        case constant(Property, Instantiable)
        case combinedScope(Property, CombinedScope)

        var cycleErrorDescription: String {
            let property: Property
            let propertyDependencies: [Property]
            switch self {
            case let .constant(problematicProperty, instantiable):
                property = problematicProperty
                propertyDependencies = instantiable.dependencies.map(\.property)
            case let .combinedScope(problematicProperty, combinedScope):
                property = problematicProperty
                propertyDependencies = combinedScope.instantiable.dependencies.map(\.property)
            }
            return "\(property.asSource) requires: \(propertyDependencies.sorted().map(\.asSource).joined(separator: ", "))"
        }
    }

    // MARK: CombinedScopeError

    private enum CombinedScopeError: Error, CustomStringConvertible {

        case unresolvableDependencies([SatisfiableProperty], Instantiable)

        var description: String {
            switch self {
            case let .unresolvableDependencies(properties, instantiable):
                """
                Unable to resolve dependencies of \(instantiable.concreteInstantiableType.asSource). There is at least one dependency cycle within the following properties:
                \(properties.map(\.cycleErrorDescription).joined(separator: "\n"))
                """
            }
        }
    }
}
