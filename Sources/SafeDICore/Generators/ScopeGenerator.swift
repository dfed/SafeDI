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

/// A model capable of generating code for a scope’s dependency tree.
actor ScopeGenerator {

    // MARK: Initialization

    init(
        instantiable: Instantiable,
        property: Property?,
        propertiesToGenerate: [ScopeGenerator]
    ) {
        if let property {
            scopeData = .property(
                instantiable: instantiable,
                property: property,
                forwardedProperties: Set(
                    instantiable
                        .dependencies
                        .filter { $0.source == .forwarded }
                        .map(\.property)
                )
            )
        } else {
            scopeData = .root(instantiable: instantiable)
        }
        self.property = property
        self.propertiesToGenerate = propertiesToGenerate
        propertiesToDeclare = Set(propertiesToGenerate.compactMap(\.property))
        requiredReceivedProperties = Set(
            propertiesToGenerate.flatMap { [propertiesToDeclare, scopeData] propertyToGenerate in
                // All the properties this child and its children require be passed in.
                propertyToGenerate.requiredReceivedProperties
                    // Minus the properties we declare.
                    .subtracting(propertiesToDeclare)
                    // Minus the properties we forward.
                    .subtracting(scopeData.forwardedProperties)
            }
        )
        // Unioned with the properties we require to fulfill our own dependencies.
        .union(Set(
            instantiable
                .dependencies
                .compactMap {
                    switch $0.source {
                    case .instantiated, .forwarded:
                        return nil
                    case .received:
                        return $0.property
                    case let .aliased(fulfillingProperty):
                        return fulfillingProperty
                    }
                }
        ))
    }

    init(
        property: Property,
        fulfillingProperty: Property
    ) {
        scopeData = .alias(property: property, fulfillingProperty: fulfillingProperty)
        requiredReceivedProperties = [fulfillingProperty]
        propertiesToGenerate = []
        propertiesToDeclare = []
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
    /// Properties that we require in order to satisfy our (and our children’s) dependencies.
    private let requiredReceivedProperties: Set<Property>
    /// Properties that will be generated as `let` constants.
    private let propertiesToGenerate: [ScopeGenerator]
    /// Properties that this scope declares as a `let` constant.
    private let propertiesToDeclare: Set<Property>
    private let property: Property?

    private var generateCodeTask: Task<String, Error>?

    private var orderedPropertiesToGenerate: [ScopeGenerator] {
        guard let firstPropertyToGenerate = propertiesToGenerate.first else { return [] }
        var orderedPropertiesToGenerate = List(firstPropertyToGenerate)
        // Use an interstion-sort algorithm to insert the remaining elements into the ordered list.
        for propertyToGenerate in propertiesToGenerate.dropFirst() {
            if propertyToGenerate.requiredReceivedProperties.isEmpty {
                // This property has no dependencies, so put it at the beginning of the list.
                orderedPropertiesToGenerate = orderedPropertiesToGenerate.prepend(propertyToGenerate)
            } else {
                var lastDependencyFound: List<ScopeGenerator>?
                for otherPropertyToGenerate in orderedPropertiesToGenerate {
                    if
                        let otherProperty = otherPropertyToGenerate.value.property,
                        propertyToGenerate
                            .requiredReceivedProperties
                            .contains(otherProperty)
                    {
                        lastDependencyFound = otherPropertyToGenerate
                    }
                }
                if let lastDependencyFound {
                    // We depend on (at least) one property in the ordered list!
                    // Make sure we are created after our dependencies.
                    lastDependencyFound.insert(propertyToGenerate)
                } else {
                    // We don't depend on any properties in the ordered list.
                    orderedPropertiesToGenerate = orderedPropertiesToGenerate.prepend(propertyToGenerate)
                }
            }
        }
        return orderedPropertiesToGenerate.map(\.value)
    }

    private func generateProperties(leadingMemberWhitespace: String) async throws -> [String] {
        var generatedProperties = [String]()
        for childGenerator in orderedPropertiesToGenerate {
            generatedProperties.append(
                try await childGenerator
                    .generateCode(leadingWhitespace: leadingMemberWhitespace)
            )
        }
        return generatedProperties
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

// MARK: - Instantiable

extension Instantiable {
    fileprivate func generateArgumentList() throws -> String {
        try initializer?
            .createInitializerArgumentList(
                given: dependencies
            ) ?? "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"
    }
}
