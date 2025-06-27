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

/// A model capable of generating code for a scope’s dependency tree.
actor ScopeGenerator: CustomStringConvertible, Sendable {
	// MARK: Initialization

	init(
		instantiable: Instantiable,
		property: Property?,
		propertiesToGenerate: [ScopeGenerator],
		unavailableOptionalProperties: Set<Property>,
		erasedToConcreteExistential: Bool,
		isPropertyCycle: Bool
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
				),
				erasedToConcreteExistential: erasedToConcreteExistential,
				isPropertyCycle: isPropertyCycle
			)
			description = instantiable.concreteInstantiable.asSource
		} else {
			scopeData = .root(instantiable: instantiable)
			description = instantiable.concreteInstantiable.asSource
		}
		self.property = property
		self.propertiesToGenerate = propertiesToGenerate
		propertiesToDeclare = Set(propertiesToGenerate.compactMap(\.property))
		self.unavailableOptionalProperties = unavailableOptionalProperties
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
		.union(
			instantiable
				.dependencies
				.compactMap {
					switch $0.source {
					case .instantiated, .forwarded:
						nil
					case .received:
						$0.property
					case let .aliased(fulfillingProperty, _, _):
						fulfillingProperty
					}
				}
		)
	}

	init(
		property: Property,
		fulfillingProperty: Property,
		unavailableOptionalProperties: Set<Property>,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool
	) {
		scopeData = .alias(
			property: property,
			fulfillingProperty: fulfillingProperty,
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable
		)
		requiredReceivedProperties = [fulfillingProperty]
		description = property.asSource
		propertiesToGenerate = []
		propertiesToDeclare = []
		self.unavailableOptionalProperties = unavailableOptionalProperties
		self.property = property
	}

	// MARK: CustomStringConvertible

	let description: String

	// MARK: Internal

	func generateCode(
		propertiesAlreadyGeneratedAtThisScope: Set<Property> = [],
		leadingWhitespace: String = ""
	) async throws -> String {
		let generatedCode: String
		let unavailableProperties = unavailableOptionalProperties
			.filter {
				!(propertiesAlreadyGeneratedAtThisScope.contains($0) || propertiesAlreadyGeneratedAtThisScope.contains($0.asUnwrappedProperty))
			}
		if let generateCodeTask = unavailablePropertiesToGenerateCodeTask[unavailableProperties] {
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
						return try await """
						extension \(instantiable.concreteInstantiable.asSource) {
						    public \(instantiable.declarationType == .classType ? "convenience " : "")init() {
						\(generateProperties(leadingMemberWhitespace: "        ").joined(separator: "\n"))
						        self.init(\(argumentList))
						    }
						}
						"""
					}
				case let .property(
					instantiable,
					property,
					forwardedProperties,
					erasedToConcreteExistential,
					isPropertyCycle
				):
					let argumentList = try instantiable.generateArgumentList(
						unavailableProperties: unavailableProperties
					)
					let concreteTypeName = instantiable.concreteInstantiable.asSource
					let instantiationDeclaration = if instantiable.declarationType.isExtension {
						"\(concreteTypeName).\(InstantiableVisitor.instantiateMethodName)"
					} else {
						concreteTypeName
					}
					let returnLineSansReturn = "\(instantiationDeclaration)(\(argumentList))"

					let propertyType = property.propertyType
					if propertyType.isErasedInstantiator,
					   let firstForwardedProperty = forwardedProperties.first,
					   let forwardedArgument = property.generics?.first,
					   !(
					   	// The forwarded argument is the same type as our only `@Forwarded` property.
					   	(forwardedProperties.count == 1 && forwardedArgument == firstForwardedProperty.typeDescription)
					   		// The forwarded argument is the same as `InstantiableName.ForwardedProperties`.
					   		|| forwardedArgument == .nested(name: "ForwardedProperties", parentType: instantiable.concreteInstantiable)
					   		// The forwarded argument is the same as the tuple we generated for `InstantiableName.ForwardedProperties`.
					   		|| forwardedArgument == forwardedProperties.asTupleTypeDescription
					   )
					{
						throw GenerationError.erasedInstantiatorGenericDoesNotMatch(
							property: property,
							instantiable: instantiable
						)
					}

					switch propertyType {
					case .instantiator,
					     .erasedInstantiator,
					     .sendableInstantiator,
					     .sendableErasedInstantiator:
						let forwardedProperties = forwardedProperties.sorted()
						let forwardedPropertiesHaveLabels = forwardedProperties.count > 1
						let forwardedArguments = forwardedProperties
							.map {
								if forwardedPropertiesHaveLabels {
									"\($0.label): $0.\($0.label)"
								} else {
									"\($0.label): $0"
								}
							}
							.joined(separator: ", ")
						let generatedProperties = try await generateProperties(leadingMemberWhitespace: Self.standardIndent)
						let functionArguments = if forwardedProperties.isEmpty {
							""
						} else {
							forwardedProperties.initializerFunctionParameters.map(\.description).joined()
						}
						let functionName = self.functionName(toBuild: property)
						let functionDecorator = if propertyType.isSendable {
							"@Sendable "
						} else {
							""
						}
						let functionDeclaration = if isPropertyCycle {
							""
						} else {
							"""
							\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(concreteTypeName) {
							\(generatedProperties.joined(separator: "\n"))
							\(Self.standardIndent)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)
							}

							"""
						}

						let typeDescription = property.typeDescription.asSource
						let unwrappedTypeDescription = property
							.typeDescription
							.unwrapped
							.asSource
						let instantiatedTypeDescription = property
							.typeDescription
							.unwrapped
							.asInstantiatedType
							.asSource
						let propertyDeclaration = if !instantiable.declarationType.isExtension, typeDescription == unwrappedTypeDescription {
							"let \(property.label)"
						} else {
							"let \(property.asSource)"
						}
						let instantiatorInstantiation = if forwardedArguments.isEmpty, !erasedToConcreteExistential {
							"\(unwrappedTypeDescription)(\(functionName))"
						} else if erasedToConcreteExistential {
							"""
							\(unwrappedTypeDescription) {
							\(Self.standardIndent)\(instantiatedTypeDescription)(\(functionName)(\(forwardedArguments)))
							}
							"""
						} else {
							"""
							\(unwrappedTypeDescription) {
							\(Self.standardIndent)\(functionName)(\(forwardedArguments))
							}
							"""
						}
						return """
						\(functionDeclaration)\(propertyDeclaration) = \(instantiatorInstantiation)
						"""
					case .constant:
						let generatedProperties = try await generateProperties(leadingMemberWhitespace: Self.standardIndent)
						let propertyDeclaration = if erasedToConcreteExistential || (
							concreteTypeName == property.typeDescription.asSource
								&& generatedProperties.isEmpty
								&& !instantiable.declarationType.isExtension
						) {
							"let \(property.label)"
						} else {
							"let \(property.asSource)"
						}

						// Ideally we would be able to use an anonymous closure rather than a named function here.
						// Unfortunately, there's a bug in Swift Concurrency that prevents us from doing this: https://github.com/swiftlang/swift/issues/75003
						let functionName = self.functionName(toBuild: property)
						let functionDeclaration = if generatedProperties.isEmpty {
							""
						} else {
							"""
							func \(functionName)() -> \(concreteTypeName) {
							\(generatedProperties.joined(separator: "\n"))
							\(Self.standardIndent)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)
							}

							"""
						}
						let returnLineSansReturn = if erasedToConcreteExistential {
							"\(property.typeDescription.asSource)(\(returnLineSansReturn))"
						} else {
							returnLineSansReturn
						}
						let initializer = if generatedProperties.isEmpty {
							returnLineSansReturn
						} else {
							"\(functionName)()"
						}
						return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
					}
				case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
					return if onlyIfAvailable, unavailableOptionalProperties.contains(fulfillingProperty) {
						"// Did not create `\(property.asSource)` because `\(fulfillingProperty.asSource)` is unavailable."
					} else {
						if erasedToConcreteExistential {
							"let \(property.label) = \(property.typeDescription.asSource)(\(fulfillingProperty.label))"
						} else {
							"let \(property.asSource) = \(fulfillingProperty.label)"
						}
					}
				}
			}
			unavailablePropertiesToGenerateCodeTask[unavailableProperties] = generateCodeTask
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

	func generateDOT() async throws -> String {
		let orderedPropertiesToGenerate = orderedPropertiesToGenerate
		let instantiatedProperties = orderedPropertiesToGenerate.map(\.scopeData.asDOTNode)
		var childDOTs = [String]()
		for orderedPropertyToGenerate in orderedPropertiesToGenerate {
			let childDOT = try await orderedPropertyToGenerate.generateDOT()
			if !childDOT.isEmpty {
				childDOTs.append(childDOT)
			}
		}

		let root = scopeData.asDOTNode
		let forwardedProperties = scopeData.forwardedProperties.sorted().map { "\"\($0.asSource)\"" }
		return ((instantiatedProperties + forwardedProperties).map {
			"    \(root) -- \($0)"
		} + childDOTs).joined(separator: "\n")
	}

	// MARK: Private

	private enum ScopeData: Sendable {
		case root(instantiable: Instantiable)
		case property(
			instantiable: Instantiable,
			property: Property,
			forwardedProperties: Set<Property>,
			erasedToConcreteExistential: Bool,
			isPropertyCycle: Bool
		)
		case alias(
			property: Property,
			fulfillingProperty: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool
		)

		var forwardedProperties: Set<Property> {
			switch self {
			case let .property(_, _, forwardedProperties, _, _):
				forwardedProperties
			case .root, .alias:
				[]
			}
		}

		var asDOTNode: String {
			switch self {
			case let .root(instantiable):
				instantiable.concreteInstantiable.asSource
			case let .property(_, property, _, _, _):
				"\"\(property.asSource)\""
			case let .alias(property, fulfillingProperty, _, _):
				"\"\(property.asSource) <- \(fulfillingProperty.asSource)\""
			}
		}
	}

	private let scopeData: ScopeData
	/// Properties that we require in order to satisfy our (and our children’s) dependencies.
	private let requiredReceivedProperties: Set<Property>
	/// Received properties that are optional and not created by a parent.
	private let unavailableOptionalProperties: Set<Property>
	/// Properties that will be generated as `let` constants.
	private let propertiesToGenerate: [ScopeGenerator]
	/// Properties that this scope declares as a `let` constant.
	private let propertiesToDeclare: Set<Property>
	private let property: Property?

	private var unavailablePropertiesToGenerateCodeTask = [Set<Property>: Task<String, Error>]()

	private var orderedPropertiesToGenerate: [ScopeGenerator] {
		var orderedPropertiesToGenerate = [ScopeGenerator]()
		var propertyToUnfulfilledScopeMap = propertiesToGenerate
			.reduce(into: OrderedDictionary<Property, ScopeGenerator>()) { partialResult, scope in
				if let property = scope.property {
					partialResult[property] = scope
				}
			}
		func fulfill(_ scope: ScopeGenerator) {
			guard let property = scope.property,
			      propertyToUnfulfilledScopeMap[property] != nil
			else {
				return
			}
			let scopeDependencies = propertyToUnfulfilledScopeMap
				.keys
				.intersection(scope.requiredReceivedProperties)
				.union(scope.unavailableOptionalProperties)
				.union(scope.unavailableOptionalProperties.map(\.asUnwrappedProperty))
				.compactMap { propertyToUnfulfilledScopeMap[$0] }
			// Fulfill the scopes we depend upon.
			for dependentScope in scopeDependencies {
				fulfill(dependentScope)
			}

			// We can now be marked as fulfilled!
			orderedPropertiesToGenerate.append(scope)
			propertyToUnfulfilledScopeMap[property] = nil
		}

		for scope in propertiesToGenerate {
			fulfill(scope)
		}

		return orderedPropertiesToGenerate
	}

	private func generateProperties(leadingMemberWhitespace: String) async throws -> [String] {
		var generatedProperties = [String]()
		for (index, childGenerator) in orderedPropertiesToGenerate.enumerated() {
			try await generatedProperties.append(
				childGenerator.generateCode(
					propertiesAlreadyGeneratedAtThisScope: .init(orderedPropertiesToGenerate[0..<index].compactMap(\.property)),
					leadingWhitespace: leadingMemberWhitespace
				)
			)
		}
		return generatedProperties
	}

	private func functionName(toBuild property: Property) -> String {
		"__safeDI_\(property.label)"
	}

	private static let standardIndent = "    "

	// MARK: GenerationError

	private enum GenerationError: Error, CustomStringConvertible {
		case erasedInstantiatorGenericDoesNotMatch(property: Property, instantiable: Instantiable)

		var description: String {
			switch self {
			case let .erasedInstantiatorGenericDoesNotMatch(property, instantiable):
				"Property `\(property.asSource)` on \(instantiable.concreteInstantiable.asSource) incorrectly configured. Property should instead be of type `\(Dependency.erasedInstantiatorType)<\(instantiable.concreteInstantiable.asSource).ForwardedProperties, \(property.typeDescription.asInstantiatedType.asSource)>`."
			}
		}
	}
}

// MARK: - Instantiable

extension Instantiable {
	fileprivate func generateArgumentList(
		unavailableProperties: Set<Property>? = nil
	) throws -> String {
		try initializer?
			.createInitializerArgumentList(
				given: dependencies,
				unavailableProperties: unavailableProperties
			) ?? "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"
	}
}
