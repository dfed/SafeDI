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

        propertiesToFulfill = (
            Array<Property>(childPropertyToInstantiableConstant.keys)
            + Array<Property>(childPropertyToCombinedScopeMap.keys)
        )
        .sorted()
    }

    // MARK: Internal

    let instantiable: Instantiable

    func generateCode(leadingWhitespace: String = "") async throws -> String {
        let generatedCode: String
        if let generateCodeTask {
            generatedCode = try await generateCodeTask.value
        } else {
            let generateCodeTask = Task {
                var generatedCode = ""
                while let satisfiableProperty = try nextSatisfiableProperty() {
                    let labelAndType: String
                    let initializer: String
                    switch satisfiableProperty {
                    case let .constant(property, instantiable):
                        resolvedProperties.insert(property)
                        let concreteTypeName = instantiable.concreteInstantiableType.asSource
                        if concreteTypeName == property.typeDescription.asSource {
                            labelAndType = property.label
                        } else {
                            labelAndType = "\(property.label): \(property.typeDescription.asSource)"
                        }
                        let argumentList = try instantiable.initializer.createInitializerArgumentList(given: instantiable.dependencies)
                        initializer = "\(concreteTypeName)(\(argumentList))"

                    case let .combinedScope(property, combinedScope):
                        let instantiable = combinedScope.instantiable
                        resolvedProperties.insert(property)
                        labelAndType = property.label
                        let concreteTypeName = property.typeDescription.asSource
                        let returnTypeName = property.typeDescription.asInstantiatedType.asSource
                        let argumentList = try instantiable.initializer.createInitializerArgumentList(given: instantiable.dependencies)

                        let leadingMemberWhitespace = "    "
                        let generatedCode = try await combinedScope.generateCode(leadingWhitespace: leadingWhitespace + "    ")
                        let returnLine = "\(returnTypeName)(\(argumentList))"
                        let memberStatements: String
                        if generatedCode.isEmpty {
                            memberStatements = "\(leadingMemberWhitespace)\(returnLine)"
                        } else {
                            memberStatements = """
                        \(generatedCode)
                        \(leadingMemberWhitespace)return \(returnLine)
                        """
                        }

                        let closureArguments: String
                        switch property.nonLazyPropertyType {
                        case .forwardingInstantiator:
                            let forwardedProperties = instantiable.dependencies.filter { $0.source == .forwarded }
                            // TODO: Would be better to match types rather than assuming property order for the forwarded properties.
                            // TODO: Throw error if forwardedProperties has multiple of the same type.
                            closureArguments = " \(forwardedProperties.map(\.property.label).joined(separator: ", ")) in"
                        case .instantiator, .lazy:
                            closureArguments = ""
                        case .constant:
                            assertionFailure("Found unexpected constant `\(property.asSource)` while inspecting combined scope!")
                            closureArguments = ""
                        }

                        initializer = """
                        \(concreteTypeName) {\(closureArguments)
                        \(memberStatements)
                        }
                        """
                    }

                    generatedCode.append("let \(labelAndType) = \(initializer)\n")
                }
                return generatedCode
            }
            self.generateCodeTask = generateCodeTask
            generatedCode = try await generateCodeTask.value
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

    private let propertiesToFulfill: [Property]
    private var resolvedProperties = Set<Property>()
    private var generateCodeTask: Task<String, Error>?

    private func nextSatisfiableProperty() throws -> SatisfiableProperty? {
        let remainingProperties = propertiesToFulfill.filter { !resolvedProperties.contains($0) }
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
                hasResolvedAllPropertiesRequired(for: combinedScope)
            {
                return .combinedScope(property, combinedScope)
            }
        }

        assertionFailure("Unexpected failure: unable to find next satisfiable property")
        return nil
    }

    private func hasResolvedAllPropertiesRequired(for instantiable: Instantiable) -> Bool {
        !instantiable
            .dependencies
            .filter {
                $0.source != .instantiated
                && $0.source != .forwarded
            }
            .map(\.property)
            .contains(where: { !isPropertyResolved($0) })
    }

    private func hasResolvedAllPropertiesRequired(for combinedScope: CombinedScope) -> Bool {
        !combinedScope
            .inheritedProperties
            .contains(where: { !isPropertyResolved($0) })
    }

    private func isPropertyResolved(_ property: Property) -> Bool {
        resolvedProperties.contains(property)
        || inheritedProperties.contains(property)
        || forwardedProperties.contains(property)
    }

    private lazy var forwardedProperties = instantiable
        .dependencies
        // Instantiated properties will self-resolve.
        .filter { $0.source == .forwarded }
        .map(\.property)

    // MARK: SatisfiableProperty

    private enum SatisfiableProperty {
        case constant(Property, Instantiable)
        case combinedScope(Property, CombinedScope)
    }
}
