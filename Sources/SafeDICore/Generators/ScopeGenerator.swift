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
        self.instantiable = instantiable
        self.property = property
        self.propertiesToGenerate = propertiesToGenerate
        self.receivedProperties = receivedProperties

        forwardedProperty = instantiable
            .dependencies
            // Instantiated properties will self-resolve.
            .filter { $0.source == .forwarded }
            .map(\.property)
            // Our @Instantiable macro enforces that we have at most one forwarded property.
            .first

        propertiesMadeAvailableByChildren = Set(
            instantiable
                .dependencies
                .filter { $0.source != .received }
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

    // MARK: Internal

    func generateCode(leadingWhitespace: String = "") async throws -> String {
        let generatedCode: String
        if let generateCodeTask {
            generatedCode = try await generateCodeTask.value
        } else {
            let generateCodeTask = Task {
                let argumentList = try instantiable
                    .initializer?
                    .createInitializerArgumentList(
                        given: instantiable.dependencies
                    ) ?? "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"

                if let property {
                    let concreteTypeName = instantiable.concreteInstantiableType.asSource
                    let instantiationDeclaration = switch instantiable.declarationType {
                    case .actorType, .classType, .structType:
                        concreteTypeName
                    case .extensionType:
                        "\(concreteTypeName).\(ExternalInstantiableVisitor.instantiateMethodName)"
                    }
                    let returnLineSansReturn = "\(instantiationDeclaration)(\(argumentList))"

                    let isConstant: Bool
                    let propertyDeclaration: String
                    let leadingConcreteTypeName: String
                    let closureArguments: String
                    if let forwardedProperty {
                        guard property.generics.first == forwardedProperty.typeDescription else {
                            throw GenerationError.forwardingInstantiatorGenericDoesNotMatch(
                                property: property,
                                expectedType: forwardedProperty.typeDescription,
                                instantiable: instantiable
                            )
                        }
                        closureArguments = " \(forwardedProperty.label) in"
                    } else {
                        closureArguments = ""
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
                } else {
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

    private let instantiable: Instantiable
    private let property: Property?
    private let receivedProperties: Set<Property>
    private let propertiesToGenerate: [ScopeGenerator]
    private let forwardedProperty: Property?
    private let requiredReceivedProperties: Set<Property>
    private let propertiesMadeAvailableByChildren: Set<Property>

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
                && propertyToGenerate.forwardedProperty != $0
            })
    }

    private func isPropertyResolved(_ property: Property) -> Bool {
        resolvedProperties.contains(property)
        || receivedProperties.contains(property)
        || forwardedProperty == property
    }

    // MARK: GenerationError

    private enum GenerationError: Error, CustomStringConvertible {
        case forwardingInstantiatorGenericDoesNotMatch(property: Property, expectedType: TypeDescription, instantiable: Instantiable)

        var description: String {
            switch self {
            case let .forwardingInstantiatorGenericDoesNotMatch(property, expectedType, instantiable):
                "Property `\(property.asSource)` on \(instantiable.concreteInstantiableType.asSource) incorrectly configured. Property should instead be of type `\(Dependency.forwardingInstantiatorType)<\(expectedType.asSource), \(property.typeDescription.asInstantiatedType.asSource)>`. First generic argument must match type of @\(Dependency.Source.forwarded.rawValue) property."
            }
        }
    }
}
