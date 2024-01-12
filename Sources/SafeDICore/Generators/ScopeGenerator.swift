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

/// A model capable of generating code for a scope's dependency tree.
actor ScopeGenerator {

    // MARK: Initialization

    init(
        instantiable: Instantiable,
        property: Property?,
        propertiesToGenerate: [ScopeGenerator],
        receivedProperties: Set<Property>
    ) {
        if let property {
            scopeData = .property(
                instantiable: instantiable,
                property: property,
                forwardedProperties: Set(
                    instantiable
                        .dependencies
                    // Instantiated properties will self-resolve.
                        .filter { $0.source == .forwarded }
                        .map(\.property)
                )
            )
        } else {
            scopeData = .root(instantiable: instantiable)
        }
        self.property = property
        self.receivedProperties = receivedProperties
        self.propertiesToGenerate = propertiesToGenerate
        forwardedProperties = scopeData.forwardedProperties
        propertiesMadeAvailableByChildren = Set(
            instantiable
                .dependencies
                .filter {
                    // If the source is not received, the property is being made available.
                    $0.source != .received
                    // If the dependency has a fulfilling property, the property is being aliased.
                    || $0.fulfillingProperty != nil
                }
                .map(\.property)
        ).union(propertiesToGenerate
            .flatMap(\.propertiesMadeAvailableByChildren))

        requiredReceivedProperties = Set(
            instantiable
                .dependencies
                .filter { $0.source == .received }
                .map(\.property)
        ).union(propertiesToGenerate.flatMap(\.requiredReceivedProperties))
            .subtracting(propertiesMadeAvailableByChildren)
    }

    init(
        property: Property,
        fulfillingProperty: Property,
        receivedProperties: Set<Property>
    ) {
        scopeData = .alias(property: property, fulfillingProperty: fulfillingProperty)
        requiredReceivedProperties = [fulfillingProperty]
        propertiesToGenerate = []
        forwardedProperties = []
        propertiesMadeAvailableByChildren = []
        self.receivedProperties = receivedProperties
        self.property = property
    }

    // MARK: Internal

    func generateCode(leadingWhitespace: String = "") async throws -> String {
        let generatedCode: String
        if let generateCodeTask {
            generatedCode = try await generateCodeTask.value
        } else {
            let generateCodeTask = Task {
                switch scopeData {
                case let .root(instantiable):
                    let argumentList = try instantiable.generateArgumentList()
                    if instantiable.dependencies.isEmpty {
                        // Nothing to do here! We already have an empty initializer.
                        return ""
                    } else {
                        return """
                            extension \(instantiable.concreteInstantiableType.asSource) {
                                public \(instantiable.declarationType == .classType ? "convenience " : "")init() {
                            \(try await generateProperties(leadingMemberWhitespace: "        ").joined(separator: "\n"))
                                    self.init(\(argumentList))
                                }
                            }
                            """
                    }
                case let .property(
                    instantiable,
                    property,
                    forwardedProperties
                ):
                    let argumentList = try instantiable.generateArgumentList()
                    let concreteTypeName = instantiable.concreteInstantiableType.asSource
                    let instantiationDeclaration = switch instantiable.declarationType {
                    case .actorType, .classType, .structType:
                        concreteTypeName
                    case .extensionType:
                        "\(concreteTypeName).\(InstantiableVisitor.instantiateMethodName)"
                    }
                    let returnLineSansReturn = "\(instantiationDeclaration)(\(argumentList))"

                    let isConstant: Bool
                    let propertyDeclaration: String
                    let leadingConcreteTypeName: String
                    let closureArguments: String
                    if forwardedProperties.isEmpty {
                        closureArguments = ""
                    } else {
                        if
                            let firstForwardedProperty = forwardedProperties.first,
                            let forwardedArgument = property.generics.first,
                            !(
                                // The forwarded argument is the same type as our only `@Forwarded` property.
                                (forwardedProperties.count == 1 && forwardedArgument == firstForwardedProperty.typeDescription)
                                // The forwarded argument is the same as `InstantiableTypeName.ForwardedArguments`.
                                || forwardedArgument == .nested(name: "ForwardedArguments", parentType: instantiable.concreteInstantiableType)
                                // The forwarded argument is the same as the tuple we generated for `InstantiableTypeName.ForwardedArguments`.
                                || forwardedArgument == forwardedProperties.asTupleTypeDescription
                            )
                        {
                            throw GenerationError.forwardingInstantiatorGenericDoesNotMatch(
                                property: property,
                                instantiable: instantiable
                            )
                        }

                        let forwardedArgumentList = forwardedProperties
                            .sorted()
                            .map(\.label)
                            .joined(separator: ", ")
                        closureArguments = " \(forwardedArgumentList) in"
                    }
                    switch property.propertyType {
                    case .instantiator, .forwardingInstantiator:
                        isConstant = false
                        propertyDeclaration = "let \(property.label)"
                        leadingConcreteTypeName = property.typeDescription.asSource
                    case .constant:
                        isConstant = true
                        if concreteTypeName == property.typeDescription.asSource {
                            propertyDeclaration = "let \(property.label)"
                        } else {
                            propertyDeclaration = "let \(property.label): \(property.typeDescription.asSource)"
                        }
                        leadingConcreteTypeName = ""
                    }

                    let leadingMemberWhitespace = "    "
                    let generatedProperties = try await generateProperties(leadingMemberWhitespace: leadingMemberWhitespace)
                    let initializer: String
                    if isConstant && generatedProperties.isEmpty {
                        initializer = returnLineSansReturn
                    } else {
                        initializer = """
                            \(leadingConcreteTypeName)\(leadingConcreteTypeName.isEmpty ? "" : " "){\(closureArguments)
                            \(generatedProperties.joined(separator: "\n"))
                            \(leadingMemberWhitespace)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)
                            }\(isConstant ? "()" : "")
                            """
                    }

                    return "\(propertyDeclaration) = \(initializer)\n"
                case let .alias(property, fulfillingProperty):
                    return "let \(property.asSource) = \(fulfillingProperty.label)"
                }
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

    private enum ScopeData {
        case root(instantiable: Instantiable)
        case property(
            instantiable: Instantiable,
            property: Property,
            forwardedProperties: Set<Property>
        )
        case alias(
            property: Property,
            fulfillingProperty: Property
        )

        var forwardedProperties: Set<Property> {
            switch self {
            case let .property(_, _, forwardedProperties):
                return forwardedProperties
            case .root, .alias:
                return []
            }
        }
    }

    private let scopeData: ScopeData
    private let requiredReceivedProperties: Set<Property>
    private let propertiesMadeAvailableByChildren: Set<Property>
    private let receivedProperties: Set<Property>
    private let propertiesToGenerate: [ScopeGenerator]
    private let property: Property?
    private let forwardedProperties: Set<Property>

    private var resolvedProperties = Set<Property>()
    private var generateCodeTask: Task<String, Error>?

    private func generateProperties(leadingMemberWhitespace: String) async throws -> [String] {
        var generatedProperties = [String]()
        while
            let childGenerator = nextSatisfiableProperty(),
            let childProperty = childGenerator.property
        {
            resolvedProperties.insert(childProperty)
            generatedProperties.append(
                try await childGenerator
                    .generateCode(leadingWhitespace: leadingMemberWhitespace)
            )
        }
        return generatedProperties
    }

    private func nextSatisfiableProperty() -> ScopeGenerator? {
        let remainingProperties = propertiesToGenerate.filter {
            if let property = $0.property {
                !resolvedProperties.contains(property)
            } else {
                false
            }
        }
        guard !remainingProperties.isEmpty else {
            return nil
        }

        for propertyToGenerate in remainingProperties {
            guard hasResolvedAllPropertiesRequired(for: propertyToGenerate) else {
                continue
            }
            return propertyToGenerate
        }

        assertionFailure("Unexpected failure: unable to find next satisfiable property")
        return nil
    }

    private func hasResolvedAllPropertiesRequired(for propertyToGenerate: ScopeGenerator) -> Bool {
        !propertyToGenerate
            .requiredReceivedProperties
            .contains(where: {
                !isPropertyResolved($0) 
                && !propertyToGenerate.forwardedProperties.contains($0)
            })
    }

    private func isPropertyResolved(_ property: Property) -> Bool {
        resolvedProperties.contains(property)
        || receivedProperties.contains(property)
        || forwardedProperties.contains(property)
    }

    // MARK: GenerationError

    private enum GenerationError: Error, CustomStringConvertible {
        case forwardingInstantiatorGenericDoesNotMatch(property: Property, instantiable: Instantiable)

        var description: String {
            switch self {
            case let .forwardingInstantiatorGenericDoesNotMatch(property, instantiable):
                "Property `\(property.asSource)` on \(instantiable.concreteInstantiableType.asSource) incorrectly configured. Property should instead be of type `\(Dependency.forwardingInstantiatorType)<\(instantiable.concreteInstantiableType.asSource).ForwardedArguments, \(property.typeDescription.asInstantiatedType.asSource)>`."
            }
        }
    }
}

extension Instantiable {
    fileprivate func generateArgumentList() throws -> String {
        try initializer?
            .createInitializerArgumentList(
                given: dependencies
            ) ?? "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"
    }
}
