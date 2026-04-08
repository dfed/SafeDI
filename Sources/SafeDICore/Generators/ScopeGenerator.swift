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

import Foundation

/// A model capable of generating code for a scope’s dependency tree.
actor ScopeGenerator: CustomStringConvertible, Sendable {
	// MARK: Initialization

	init(
		instantiable: Instantiable,
		property: Property?,
		propertiesToGenerate: [ScopeGenerator],
		unavailableOptionalProperties: Set<Property>,
		erasedToConcreteExistential: Bool,
		isPropertyCycle: Bool,
	) {
		if let property {
			scopeData = .property(
				instantiable: instantiable,
				property: property,
				forwardedProperties: Set(
					instantiable
						.dependencies
						.filter { $0.source == .forwarded }
						.map(\.property),
				),
				erasedToConcreteExistential: erasedToConcreteExistential,
				isPropertyCycle: isPropertyCycle,
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
		receivedProperties = Set(
			propertiesToGenerate.flatMap { [propertiesToDeclare, scopeData] propertyToGenerate in
				// All the properties this child and its children require be passed in.
				propertyToGenerate.receivedProperties
					// Minus the properties we declare.
					.subtracting(propertiesToDeclare)
					// Minus optional properties whose unwrapped form we declare.
					// This handles the case where a non-optional version is promoted
					// to satisfy both required and onlyIfAvailable receivers.
					.filter { property in
						!property.typeDescription.isOptional
							|| !propertiesToDeclare.contains(property.asUnwrappedProperty)
					}
					// Minus the properties we forward.
					.subtracting(scopeData.forwardedProperties)
			},
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
				},
		)
		onlyIfAvailableUnwrappedReceivedProperties = Set(
			propertiesToGenerate.flatMap { [propertiesToDeclare, scopeData] propertyToGenerate in
				propertyToGenerate.onlyIfAvailableUnwrappedReceivedProperties
					.subtracting(propertiesToDeclare)
					.subtracting(scopeData.forwardedProperties)
			},
		)
		.union(
			instantiable
				.dependencies
				.compactMap {
					switch $0.source {
					case .instantiated, .forwarded:
						nil
					case let .received(onlyIfAvailable):
						if onlyIfAvailable {
							$0.property.asUnwrappedProperty
						} else {
							nil
						}
					case let .aliased(fulfillingProperty, _, onlyIfAvailable):
						if onlyIfAvailable {
							fulfillingProperty.asUnwrappedProperty
						} else {
							nil
						}
					}
				},
		)
	}

	init(
		property: Property,
		fulfillingProperty: Property,
		unavailableOptionalProperties: Set<Property>,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool,
	) {
		scopeData = .alias(
			property: property,
			fulfillingProperty: fulfillingProperty,
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable,
		)
		receivedProperties = [fulfillingProperty]
		onlyIfAvailableUnwrappedReceivedProperties = if onlyIfAvailable {
			[fulfillingProperty.asUnwrappedProperty]
		} else {
			[]
		}
		description = property.asSource
		propertiesToGenerate = []
		propertiesToDeclare = []
		self.unavailableOptionalProperties = unavailableOptionalProperties
		self.property = property
	}

	// MARK: CustomStringConvertible

	let description: String

	// MARK: Internal

	/// Properties that we require in order to satisfy our (and our children's) dependencies.
	/// Used by mock generation to read unsatisfied dependencies after initial tree build.
	let receivedProperties: Set<Property>

	func generateCode(
		codeGeneration: CodeGeneration = .dependencyTree,
		propertiesAlreadyGeneratedAtThisScope: Set<Property> = [],
		leadingWhitespace: String = "",
	) async throws -> String {
		let generatedCode: String
		let unavailableProperties = unavailableOptionalProperties
			.filter {
				!(propertiesAlreadyGeneratedAtThisScope.contains($0) || propertiesAlreadyGeneratedAtThisScope.contains($0.asUnwrappedProperty))
			}
		// Mock code is not cached — the context varies per call site.
		// Dependency tree code is cached by unavailable properties.
		switch codeGeneration {
		case .dependencyTree:
			if let generateCodeTask = unavailablePropertiesToGenerateCodeTask[unavailableProperties] {
				generatedCode = try await generateCodeTask.value
			} else {
				let generateCodeTask = Task {
					try await generatePropertyCode(
						codeGeneration: .dependencyTree,
						unavailableProperties: unavailableProperties,
					)
				}
				unavailablePropertiesToGenerateCodeTask[unavailableProperties] = generateCodeTask
				generatedCode = try await generateCodeTask.value
			}
		case .mock:
			generatedCode = try await generatePropertyCode(
				codeGeneration: codeGeneration,
				unavailableProperties: unavailableProperties,
			)
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

	private enum ScopeData {
		case root(instantiable: Instantiable)
		case property(
			instantiable: Instantiable,
			property: Property,
			forwardedProperties: Set<Property>,
			erasedToConcreteExistential: Bool,
			isPropertyCycle: Bool,
		)
		case alias(
			property: Property,
			fulfillingProperty: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
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

	/// The code generation mode.
	enum CodeGeneration {
		case dependencyTree
		case mock(MockContext)
	}

	/// Context for mock code generation, threaded through the tree.
	struct MockContext {
		/// The conditional compilation flag for wrapping mock output (e.g. "DEBUG").
		let mockConditionalCompilation: String?
	}

	private let scopeData: ScopeData
	/// Unwrapped versions of received properties from transitive `@Received(onlyIfAvailable: true)` dependencies.
	/// Used by mock generation to identify dependencies that should become optional mock parameters (no guaranteed default).
	let onlyIfAvailableUnwrappedReceivedProperties: Set<Property>
	/// Received properties that are optional and not created by a parent.
	private let unavailableOptionalProperties: Set<Property>
	/// Properties that will be generated as `let` constants.
	private let propertiesToGenerate: [ScopeGenerator]
	/// Properties that this scope declares as a `let` constant.
	private let propertiesToDeclare: Set<Property>
	private let property: Property?

	private var unavailablePropertiesToGenerateCodeTask = [Set<Property>: Task<String, Error>]()

	private lazy var orderedPropertiesToGenerate: [ScopeGenerator] = {
		var orderedPropertiesToGenerate = [ScopeGenerator]()
		var propertyToUnfulfilledScopeMap = propertiesToGenerate
			.reduce(into: [Property: ScopeGenerator]()) { partialResult, scope in
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
			// Mark as fulfilled before recursing to prevent cycles.
			propertyToUnfulfilledScopeMap[property] = nil
			let receivedAndOnlyIfAvailable = scope.receivedProperties
				.union(scope.onlyIfAvailableUnwrappedReceivedProperties)
			let scopeDependencies = propertiesToGenerate
				.compactMap { childScope -> ScopeGenerator? in
					guard let childProperty = childScope.property,
					      propertyToUnfulfilledScopeMap[childProperty] != nil,
					      receivedAndOnlyIfAvailable.contains(childProperty)
					else {
						return nil
					}
					return childScope
				}
			// Fulfill the scopes we depend upon.
			for dependentScope in scopeDependencies {
				fulfill(dependentScope)
			}

			orderedPropertiesToGenerate.append(scope)
		}

		for scope in propertiesToGenerate {
			fulfill(scope)
		}

		return orderedPropertiesToGenerate
	}()

	private func generateProperties(
		codeGeneration: CodeGeneration = .dependencyTree,
		leadingMemberWhitespace: String,
	) async throws -> [String] {
		var generatedProperties = [String]()
		for (index, childGenerator) in orderedPropertiesToGenerate.enumerated() {
			try await generatedProperties.append(
				childGenerator.generateCode(
					codeGeneration: codeGeneration,
					propertiesAlreadyGeneratedAtThisScope: .init(orderedPropertiesToGenerate[0..<index].compactMap(\.property)),
					leadingWhitespace: leadingMemberWhitespace,
				),
			)
		}
		return generatedProperties
	}

	private func functionName(toBuild property: Property) -> String {
		"__safeDI_\(property.label)"
	}

	private static let standardIndent = "    "

	// MARK: Code Generation

	/// Generates code for this scope — unified for both dependency tree and mock modes.
	/// In mock mode, the only difference is the `let` binding line wraps with an override closure.
	private func generatePropertyCode(
		codeGeneration: CodeGeneration,
		unavailableProperties: Set<Property>,
	) async throws -> String {
		switch scopeData {
		case let .root(instantiable):
			switch codeGeneration {
			case .dependencyTree:
				let argumentList = try instantiable.generateArgumentList()
				if instantiable.dependencies.isEmpty {
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
			case let .mock(context):
				return try await generateMockRootCode(
					instantiable: instantiable,
					context: context,
				)
			}
		case let .property(
			instantiable,
			property,
			forwardedProperties,
			erasedToConcreteExistential,
			isPropertyCycle,
		):
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableProperties,
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
					instantiable: instantiable,
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
				let generatedProperties = try await generateProperties(
					codeGeneration: codeGeneration,
					leadingMemberWhitespace: Self.standardIndent,
				)
				let functionArguments = if forwardedProperties.isEmpty {
					""
				} else {
					forwardedProperties.initializerFunctionParameters.map(\.description).joined()
				}
				let functionName = functionName(toBuild: property)
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
				let generatedProperties = try await generateProperties(
					codeGeneration: codeGeneration,
					leadingMemberWhitespace: Self.standardIndent,
				)

				let nonEmptyGeneratedProperties = generatedProperties.filter { !$0.isEmpty }
				let hasGeneratedContent = !nonEmptyGeneratedProperties.isEmpty
				let propertyDeclaration = if erasedToConcreteExistential || (
					concreteTypeName == property.typeDescription.asSource
						&& !hasGeneratedContent
						&& !instantiable.declarationType.isExtension
				) {
					"let \(property.label)"
				} else {
					"let \(property.asSource)"
				}

				// Ideally we would be able to use an anonymous closure rather than a named function here.
				// Unfortunately, there's a bug in Swift Concurrency that prevents us from doing this: https://github.com/swiftlang/swift/issues/75003
				let functionName = functionName(toBuild: property)
				let functionDeclaration = if !hasGeneratedContent {
					""
				} else {
					"""
					func \(functionName)() -> \(concreteTypeName) {
					\(nonEmptyGeneratedProperties.joined(separator: "\n"))
					\(Self.standardIndent)return \(returnLineSansReturn)
					}

					"""
				}
				let existentialWrappedReturn = if erasedToConcreteExistential {
					"\(property.typeDescription.asSource)(\(returnLineSansReturn))"
				} else {
					returnLineSansReturn
				}
				let initializer = if !hasGeneratedContent {
					existentialWrappedReturn
				} else {
					"\(functionName)()"
				}

				return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
			}
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
			return if onlyIfAvailable, unavailableProperties.contains(fulfillingProperty) {
				"// Did not create `\(property.asSource)` because `\(fulfillingProperty.asSource)` is unavailable."
			} else if erasedToConcreteExistential {
				"let \(property.label): \(property.typeDescription.asSource) = \(fulfillingProperty.label)"
			} else {
				"let \(property.asSource) = \(fulfillingProperty.label)"
			}
		}
	}

	// MARK: Mock Root Code Generation

	/// Generates the full mock extension code for a `.root` node in mock mode.
	private func generateMockRootCode(
		instantiable: Instantiable,
		context: MockContext,
	) async throws -> String {
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		let indent = Self.standardIndent
		let bodyIndent = "\(indent)\(indent)"

		// 1. Build the parameter tree.
		let parameterTree = await collectMockParameterTree()

		// 2. Identify flat parameters.

		// Forwarded dependencies → bare required parameters.
		let forwardedDependencies = instantiable.dependencies
			.filter { $0.source == .forwarded }
			.sorted { $0.property < $1.property }

		// Root type's own non-dependency defaults (from init or customMock).
		let rootConstructionInitializer: Initializer? = if let mockInitializer = instantiable.mockInitializer {
			mockInitializer
		} else {
			instantiable.initializer
		}
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
		var rootDefaultParameters = [(label: String, typeSource: String, defaultExpression: String)]()
		if let rootConstructionInitializer {
			for argument in rootConstructionInitializer.arguments {
				guard argument.hasDefaultValue,
				      !dependencyLabels.contains(argument.innerLabel),
				      argument.label != "_",
				      let defaultExpression = argument.defaultValueExpression
				else { continue }
				rootDefaultParameters.append((
					label: argument.label,
					typeSource: argument.typeDescription.asFunctionParameter.asSource,
					defaultExpression: defaultExpression,
				))
			}
		}

		// Non-instantiable received dependencies and uncovered @Instantiated dependencies → flat parameters.
		let treePropertyLabels = Set(parameterTree.map(\.propertyLabel))
		let forwardedPropertySet = Set(forwardedDependencies.map(\.property))

		let unwrappedOptionalCounterparts = Set(
			receivedProperties
				.filter(\.typeDescription.isOptional)
				.map(\.asUnwrappedProperty),
		)
		let receivedNonOptionalProperties = Set(
			receivedProperties
				.filter { !$0.typeDescription.isOptional },
		)
		var flatReceivedParameters = [(label: String, typeSource: String, isOptional: Bool)]()
		for receivedProperty in receivedProperties.sorted() {
			guard !treePropertyLabels.contains(receivedProperty.label),
			      !forwardedPropertySet.contains(receivedProperty)
			else { continue }
			guard !receivedProperty.typeDescription.isOptional
				|| !receivedNonOptionalProperties.contains(receivedProperty.asUnwrappedProperty)
			else { continue }
			let isOnlyIfAvailable = (receivedProperty.typeDescription.isOptional
				&& onlyIfAvailableUnwrappedReceivedProperties.contains(receivedProperty.asUnwrappedProperty))
				|| (!receivedProperty.typeDescription.isOptional
					&& !unwrappedOptionalCounterparts.contains(receivedProperty)
					&& onlyIfAvailableUnwrappedReceivedProperties.contains(receivedProperty))
				|| unavailableOptionalProperties.contains(receivedProperty)
			let typeSource: String = if isOnlyIfAvailable, !receivedProperty.typeDescription.isOptional {
				"\(receivedProperty.typeDescription.asSource)?"
			} else {
				receivedProperty.typeDescription.asSource
			}
			flatReceivedParameters.append((
				label: receivedProperty.label,
				typeSource: typeSource,
				isOptional: isOnlyIfAvailable,
			))
		}

		var flatUncoveredParameters = [(label: String, typeSource: String)]()
		// Collect uncovered @Instantiated deps from the root type.
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case .instantiated:
				guard !treePropertyLabels.contains(dependency.property.label) else { continue }
				let sourceType = dependency.property.propertyType.isConstant
					? dependency.property.typeDescription.asInstantiatedType.asSource
					: dependency.property.typeDescription.asSource
				flatUncoveredParameters.append((label: dependency.property.label, typeSource: sourceType))
			case .received, .aliased, .forwarded:
				break
			}
		}
		// Also collect uncovered @Instantiated deps from child types in the tree.
		// When a child has a custom mock method, its @Instantiated deps that aren't
		// in the scope map become builder arguments. These must surface as flat params
		// so the mock body can pass them.
		Self.collectUncoveredDependenciesFromTree(
			parameterTree,
			into: &flatUncoveredParameters,
		)

		// Disambiguate flat received parameter labels when collisions exist.
		// Forwarded parameters keep their original labels (must match init signature).
		let allFlatLabels = forwardedDependencies.map(\.property.label)
			+ rootDefaultParameters.map(\.label)
			+ flatReceivedParameters.map(\.label)
			+ flatUncoveredParameters.map(\.label)
		var flatLabelCounts = [String: Int]()
		for label in allFlatLabels {
			flatLabelCounts[label, default: 0] += 1
		}
		flatReceivedParameters = flatReceivedParameters.map { parameter in
			guard let count = flatLabelCounts[parameter.label], count > 1 else {
				return parameter
			}
			let disambiguatedLabel = "\(parameter.label)_\(parameter.typeSource.replacingOccurrences(of: "?", with: ""))"
			return (label: disambiguatedLabel, typeSource: parameter.typeSource, isOptional: parameter.isOptional)
		}
		// 3. Simple mock case — no tree, no flat parameters.
		let hasTree = !parameterTree.isEmpty
		let hasFlatParameters = !forwardedDependencies.isEmpty
			|| !rootDefaultParameters.isEmpty
			|| !flatReceivedParameters.isEmpty
			|| !flatUncoveredParameters.isEmpty

		guard hasTree || hasFlatParameters else {
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableOptionalProperties,
				forMockGeneration: true,
			)
			let mockMethodName = instantiable.customMockName ?? "mock"
			let construction = if instantiable.mockInitializer != nil {
				"\(typeName).\(mockMethodName)(\(argumentList))"
			} else if instantiable.declarationType.isExtension {
				"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
			} else {
				"\(typeName)(\(argumentList))"
			}
			let code = """
			extension \(typeName) {
			    \(mockAttributesPrefix)public static func mock() -> \(typeName) {
			        \(construction)
			    }
			}
			"""
			return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
		}

		// 4. Build the mock method.
		var lines = [String]()
		lines.append("extension \(typeName) {")

		if hasTree, let safeDIParametersStruct = Self.generateSafeDIParametersStruct(
			rootChildren: parameterTree,
			indent: indent,
		) {
			lines.append(safeDIParametersStruct)
			lines.append("")
		}

		// Build mock() signature.
		var mockParameters = [String]()
		for dependency in forwardedDependencies {
			mockParameters.append("\(bodyIndent)\(dependency.property.label): \(dependency.property.typeDescription.asFunctionParameter.asSource)")
		}
		for rootDefault in rootDefaultParameters {
			mockParameters.append("\(bodyIndent)\(rootDefault.label): \(rootDefault.typeSource) = \(rootDefault.defaultExpression)")
		}
		for flatReceived in flatReceivedParameters {
			if flatReceived.isOptional {
				mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource) = nil")
			} else {
				mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource)")
			}
		}
		for flatUncovered in flatUncoveredParameters {
			mockParameters.append("\(bodyIndent)\(flatUncovered.label): \(flatUncovered.typeSource)")
		}
		if hasTree {
			mockParameters.append("\(bodyIndent)safeDIParameters: SafeDIParameters = .init()")
		}

		lines.append("\(indent)\(mockAttributesPrefix)public static func mock(")
		lines.append(mockParameters.joined(separator: ",\n"))
		lines.append("\(indent)) -> \(typeName) {")

		// Generate mock body.
		if hasTree {
			let bodyBindings = Self.generateMockBodyBindings(
				nodes: parameterTree,
				parentPath: "safeDIParameters",
				indent: bodyIndent,
			)
			lines.append(contentsOf: bodyBindings)
		}

		// Generate return statement.
		let returnArgumentList = try generateReturnArgumentList(
			instantiable: instantiable,
		)
		let mockMethodName = instantiable.customMockName ?? "mock"
		let returnConstruction = if instantiable.mockInitializer != nil {
			"\(typeName).\(mockMethodName)(\(returnArgumentList))"
		} else if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(returnArgumentList))"
		} else {
			"\(typeName)(\(returnArgumentList))"
		}
		lines.append("\(bodyIndent)return \(returnConstruction)")
		lines.append("\(indent)}")
		lines.append("}")

		let code = lines.joined(separator: "\n")
		return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
	}

	/// Generates the labeled argument list for the return statement in the mock body.
	private func generateReturnArgumentList(
		instantiable: Instantiable,
	) throws -> String {
		let constructionInitializer: Initializer? = if let mockInitializer = instantiable.mockInitializer {
			mockInitializer
		} else {
			instantiable.initializer
		}
		guard let constructionInitializer else {
			return Instantiable.incorrectlyConfiguredComment
		}
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
		var parts = [String]()
		for argument in constructionInitializer.arguments {
			if dependencyLabels.contains(argument.innerLabel) {
				parts.append("\(argument.label): \(argument.innerLabel)")
			} else if argument.hasDefaultValue, argument.label != "_" {
				parts.append("\(argument.label): \(argument.label)")
			}
		}
		return parts.joined(separator: ", ")
	}

	// MARK: MockParameterNode

	/// A node in the mock parameter tree. Each node represents one property edge
	/// in the dependency tree and carries the metadata needed to generate its
	/// `_Configuration` struct and builder call.
	struct MockParameterNode {
		/// The property label on the parent type's init (e.g., "service", "childBuilder").
		let propertyLabel: String
		/// The full type description of the property (e.g., `Instantiator<Child>`).
		let typeDescription: TypeDescription
		/// The instantiated type — `typeDescription.asInstantiatedType` (e.g., `Child`).
		/// Used for struct naming (`Child_Configuration`) and builder return type.
		let instantiatedTypeDescription: TypeDescription
		/// Whether this property is an Instantiator/ErasedInstantiator/Sendable variant.
		let isInstantiator: Bool
		/// Whether the concrete type uses extension-based `instantiate(...)` instead of `init(...)`.
		let isExtensionBased: Bool
		/// Whether this property requires erased-to-concrete existential wrapping.
		let erasedToConcreteExistential: Bool
		/// Child nodes in the dependency tree (subtree of this type's instantiated children).
		let children: [MockParameterNode]
		/// Non-dependency default-valued parameters from this type's init or customMock.
		let defaultParameters: [DefaultParameter]
		/// All arguments from the init or customMock that will be used for construction.
		/// Determines the builder closure signature (positional unlabeled parameters).
		let constructionArguments: [Initializer.Argument]
		/// The type's declared dependencies.
		let dependencies: [Dependency]
		/// Whether a compatible user-defined mock method exists for this type.
		let useMockInitializer: Bool
		/// The custom mock method name (e.g., "customMock"), if any.
		let customMockName: String?
		/// The concrete type name (e.g., "ChildA").
		let concreteTypeName: String
		/// Forwarded properties on this type (relevant for Instantiator edges).
		let forwardedProperties: Set<Property>
		/// Whether this node is part of a property cycle.
		let isPropertyCycle: Bool
		/// Whether this node is inside a sendable scope (descendant of SendableInstantiator).
		/// When `true`, the `safeDIBuilder` closure on `_Configuration` is `@Sendable`.
		let requiresSendable: Bool

		/// The `_Configuration` struct name, based on the instantiated type.
		var structName: String {
			"\(instantiatedTypeDescription.asSource)_Configuration"
		}

		/// The builder closure type as a Swift source string (unlabeled parameters).
		/// e.g., `(Service, Style) -> Grandchild` or `() -> Service`.
		var builderClosureType: String {
			let parameterTypes = constructionArguments
				.map(\.typeDescription.asFunctionParameter.asSource)
				.joined(separator: ", ")
			return "(\(parameterTypes)) -> \(concreteTypeName)"
		}

		/// The default builder expression as a direct function reference.
		/// e.g., `Grandchild.customMock(service:style:)` or `Service.init`.
		var defaultBuilderExpression: String {
			let methodName: String = if useMockInitializer {
				customMockName ?? "mock"
			} else if isExtensionBased {
				InstantiableVisitor.instantiateMethodName
			} else {
				"init"
			}
			if constructionArguments.isEmpty {
				return "\(concreteTypeName).\(methodName)"
			} else {
				let labels = constructionArguments
					.map { "\($0.label):" }
					.joined()
				return "\(concreteTypeName).\(methodName)(\(labels))"
			}
		}

		/// A non-dependency default-valued parameter from an init or customMock.
		struct DefaultParameter {
			/// The parameter label (e.g., "theme", "isPro").
			let label: String
			/// The type of the parameter.
			let typeDescription: TypeDescription
			/// The default value expression (e.g., ".light", "false").
			let defaultExpression: String
			/// Whether the parameter type is a closure/function type.
			let isClosureType: Bool
		}
	}

	/// Walks the dependency tree and builds a `[MockParameterNode]` tree representing
	/// the direct children of the current scope. Each node recursively contains its own
	/// subtree children, default parameters, and builder metadata.
	private func collectMockParameterTree(
		insideSendableScope: Bool = false,
	) async -> [MockParameterNode] {
		var nodes = [MockParameterNode]()

		for childGenerator in orderedPropertiesToGenerate {
			guard let childProperty = childGenerator.property,
			      case let .property(childInstantiable, _, _, erasedToConcreteExistential, isPropertyCycle) = childGenerator.scopeData
			else { continue }

			let isInstantiator = !childProperty.propertyType.isConstant
			let childInsideSendable = insideSendableScope || childProperty.propertyType.isSendable

			// Recurse into children to build the subtree.
			let childNodes = await childGenerator.collectMockParameterTree(
				insideSendableScope: childInsideSendable,
			)

			// Determine which initializer to use for construction arguments and defaults.
			let useMockInitializer = childInstantiable.mockReturnTypeIsCompatible(withPropertyType: childProperty.typeDescription)
			let constructionInitializer: Initializer? = if useMockInitializer, let mockInitializer = childInstantiable.mockInitializer {
				mockInitializer.arguments.isEmpty ? nil : mockInitializer
			} else {
				childInstantiable.initializer
			}

			// Collect non-dependency default-valued parameters.
			// Instantiator boundaries stop bubbling — those are user-provided closures.
			var defaultParameters = [MockParameterNode.DefaultParameter]()
			if !isInstantiator, let constructionInitializer {
				let dependencyLabels = Set(childInstantiable.dependencies.map(\.property.label))
				for argument in constructionInitializer.arguments where argument.hasDefaultValue {
					guard !dependencyLabels.contains(argument.innerLabel),
					      argument.label != "_",
					      let defaultExpression = argument.defaultValueExpression
					else { continue }
					defaultParameters.append(MockParameterNode.DefaultParameter(
						label: argument.label,
						typeDescription: argument.typeDescription.strippingEscaping,
						defaultExpression: defaultExpression,
						isClosureType: argument.typeDescription.strippingEscaping.isClosure,
					))
				}
			}

			// Collect forwarded properties for Instantiator edges.
			let forwardedProperties = Set(
				childInstantiable.dependencies
					.filter { $0.source == .forwarded }
					.map(\.property),
			)

			// Gather all construction arguments from the appropriate initializer.
			let constructionArguments: [Initializer.Argument] = if let constructionInitializer {
				constructionInitializer.arguments
			} else if let initializer = childInstantiable.initializer {
				initializer.arguments
			} else {
				[]
			}

			nodes.append(MockParameterNode(
				propertyLabel: childProperty.label,
				typeDescription: childProperty.typeDescription,
				instantiatedTypeDescription: childProperty.typeDescription.asInstantiatedType,
				isInstantiator: isInstantiator,
				isExtensionBased: childInstantiable.declarationType.isExtension,
				erasedToConcreteExistential: erasedToConcreteExistential,
				children: childNodes,
				defaultParameters: defaultParameters,
				constructionArguments: constructionArguments,
				dependencies: childInstantiable.dependencies,
				useMockInitializer: useMockInitializer,
				customMockName: childInstantiable.customMockName,
				concreteTypeName: childInstantiable.concreteInstantiable.asSource,
				forwardedProperties: forwardedProperties,
				isPropertyCycle: isPropertyCycle,
				requiresSendable: childInsideSendable,
			))
		}

		return nodes
	}

	/// Walks the parameter tree and collects `@Instantiated` dependencies from child
	/// types that aren't fulfilled by their own child nodes. These are deps that
	/// surface through builder arguments (especially via custom mock methods) but aren't
	/// fulfilled by any type in the scope map.
	private static func collectUncoveredDependenciesFromTree(
		_ nodes: [MockParameterNode],
		into flatUncoveredParameters: inout [(label: String, typeSource: String)],
	) {
		for node in nodes {
			let childLabels = Set(node.children.map(\.propertyLabel))
			let collectedLabels = Set(flatUncoveredParameters.map(\.label))
			for dependency in node.dependencies {
				guard case .instantiated = dependency.source else { continue }
				// Skip deps that are covered by a child node in the tree.
				guard !childLabels.contains(dependency.property.label) else { continue }
				// Skip deps already collected.
				guard !collectedLabels.contains(dependency.property.label) else { continue }
				let sourceType = dependency.property.propertyType.isConstant
					? dependency.property.typeDescription.asInstantiatedType.asSource
					: dependency.property.typeDescription.asSource
				flatUncoveredParameters.append((label: dependency.property.label, typeSource: sourceType))
			}
			// Skip recursion into property cycle children — they're self-references
			// whose deps would incorrectly surface as uncovered.
			let nonCycleChildren = node.children.filter { !$0.isPropertyCycle }
			collectUncoveredDependenciesFromTree(
				nonCycleChildren,
				into: &flatUncoveredParameters,
			)
		}
	}

	// MARK: SafeDIParameters Generation

	/// Computes disambiguated property labels for a list of nodes at the same scope level.
	/// When two nodes share a `propertyLabel`, appends `_TypeName` to make them unique.
	/// Returns a dictionary mapping each node's `propertyLabel` to its disambiguated label.
	private static func disambiguatePropertyLabels(
		for nodes: [MockParameterNode],
	) -> [String: String] {
		var labelCounts = [String: Int]()
		for node in nodes {
			labelCounts[node.propertyLabel, default: 0] += 1
		}
		var result = [String: String]()
		for node in nodes {
			let count = labelCounts[node.propertyLabel] ?? 1
			if count > 1 {
				let disambiguated = "\(node.propertyLabel)_\(node.instantiatedTypeDescription.asSource)"
				result["\(node.propertyLabel):\(node.instantiatedTypeDescription.asSource)"] = disambiguated
			} else {
				result["\(node.propertyLabel):\(node.instantiatedTypeDescription.asSource)"] = node.propertyLabel
			}
		}
		return result
	}

	/// Returns the disambiguated property label for a node, given a disambiguation map.
	private static func disambiguatedLabel(
		for node: MockParameterNode,
		labelMap: [String: String],
	) -> String {
		labelMap["\(node.propertyLabel):\(node.instantiatedTypeDescription.asSource)"] ?? node.propertyLabel
	}

	/// Collects all unique types from the `MockParameterNode` tree, deduplicated
	/// by `instantiatedTypeDescription`. Returns nodes in depth-first order
	/// (children before parents) so that referenced types appear before their referrers.
	private static func collectUniqueConfigurationTypes(
		from nodes: [MockParameterNode],
	) -> [MockParameterNode] {
		var seen = Set<String>()
		var result = [MockParameterNode]()

		func walk(_ node: MockParameterNode, ancestorTypes: Set<String> = []) {
			let key = node.instantiatedTypeDescription.asSource
			// Skip nodes whose type matches an ancestor — self-referencing cycle.
			guard !ancestorTypes.contains(key) else { return }
			var childAncestors = ancestorTypes
			childAncestors.insert(key)
			// Process children first (depth-first).
			for child in node.children {
				walk(child, ancestorTypes: childAncestors)
			}
			guard seen.insert(key).inserted else { return }
			result.append(node)
		}

		for node in nodes {
			walk(node)
		}
		return result
	}

	/// Generates the full `SafeDIParameters` struct including all flat `_Configuration` siblings.
	/// Returns the struct source code, or `nil` if the tree has no children.
	private static func generateSafeDIParametersStruct(
		rootChildren: [MockParameterNode],
		indent: String,
	) -> String? {
		guard !rootChildren.isEmpty else { return nil }

		let innerIndent = "\(indent)\(standardIndent)"
		let memberIndent = "\(innerIndent)\(standardIndent)"

		// Collect all unique types for flat _Configuration structs.
		let uniqueTypes = collectUniqueConfigurationTypes(from: rootChildren)

		var lines = [String]()
		lines.append("\(indent)public struct SafeDIParameters {")

		// Generate each _Configuration struct as a flat sibling.
		for uniqueType in uniqueTypes {
			lines.append(generateConfigurationStruct(
				for: uniqueType,
				indent: innerIndent,
			))
			lines.append("")
		}

		// Disambiguate root-level children property labels.
		let rootLabelMap = disambiguatePropertyLabels(for: rootChildren)

		// Generate SafeDIParameters init with root-level children.
		lines.append("\(innerIndent)public init(")
		let initParameters = rootChildren.map { child in
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			return "\(memberIndent)\(label): \(child.structName) = .init()"
		}
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		for child in rootChildren {
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			lines.append("\(memberIndent)self.\(label) = \(label)")
		}
		lines.append("\(innerIndent)}")

		// Generate stored properties.
		lines.append("")
		for child in rootChildren {
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			lines.append("\(innerIndent)public let \(label): \(child.structName)")
		}

		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// Generates a single `{TypeName}_Configuration` struct for a `MockParameterNode`.
	/// When `node.requiresSendable` is `true`, the `safeDIBuilder` closure is marked
	/// `@Sendable` (the node is inside a `SendableInstantiator` scope).
	private static func generateConfigurationStruct(
		for node: MockParameterNode,
		indent: String,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let sendableAnnotation = node.requiresSendable ? "@Sendable " : ""
		var lines = [String]()

		lines.append("\(indent)public struct \(node.structName) {")

		// Build init parameters in order: children, defaults, builder (last).
		var initParameters = [String]()
		var assignments = [String]()
		var storedProperties = [String]()

		// Child edge parameters (disambiguated if labels collide).
		// Exclude children whose type matches this node — they'd create a recursive
		// value type. These are self-referencing Instantiators (lazy cycles).
		let nonCycleChildren = node.children.filter {
			$0.instantiatedTypeDescription != node.instantiatedTypeDescription
		}
		let childLabelMap = disambiguatePropertyLabels(for: nonCycleChildren)
		for child in nonCycleChildren {
			let label = disambiguatedLabel(for: child, labelMap: childLabelMap)
			initParameters.append("\(innerIndent)\(standardIndent)\(label): \(child.structName) = .init()")
			assignments.append("\(innerIndent)\(standardIndent)self.\(label) = \(label)")
			storedProperties.append("\(innerIndent)public let \(label): \(child.structName)")
		}

		// Default-valued parameters.
		for defaultParameter in node.defaultParameters {
			let typeSource = defaultParameter.typeDescription.asSource
			// Only add @Sendable if the type doesn't already have it.
			let closureSendable = (node.requiresSendable && !typeSource.contains("@Sendable")) ? "@Sendable " : ""
			if defaultParameter.isClosureType {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(closureSendable)@escaping \(typeSource) = \(defaultParameter.defaultExpression)")
				storedProperties.append("\(innerIndent)public let \(defaultParameter.label): \(closureSendable)\(typeSource)")
			} else {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(typeSource) = \(defaultParameter.defaultExpression)")
				storedProperties.append("\(innerIndent)public let \(defaultParameter.label): \(typeSource)")
			}
			assignments.append("\(innerIndent)\(standardIndent)self.\(defaultParameter.label) = \(defaultParameter.label)")
		}

		// Builder parameter (always last, unlabeled). Optional with nil default so that
		// the default function reference (which may be @MainActor) is resolved in mock()
		// rather than in this nonisolated init.
		let closureType = node.builderClosureType
		initParameters.append("\(innerIndent)\(standardIndent)_ safeDIBuilder: (\(sendableAnnotation)\(closureType))? = nil")
		assignments.append("\(innerIndent)\(standardIndent)self.safeDIBuilder = safeDIBuilder")
		storedProperties.append("\(innerIndent)public let safeDIBuilder: (\(sendableAnnotation)\(closureType))?")

		// Emit init.
		lines.append("\(innerIndent)public init(")
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		lines.append(contentsOf: assignments)
		lines.append("\(innerIndent)}")

		// Emit stored properties.
		lines.append("")
		lines.append(contentsOf: storedProperties)

		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	// MARK: Mock Body Generation

	/// Generates the mock body bindings for the tree. Walks depth-first (children before
	/// parent), emitting `let` bindings that call through `safeDIParameters.path.safeDIBuilder(...)`.
	///
	/// For constant nodes: `let {label} = safeDIParameters.{path}.safeDIBuilder({arguments})`
	/// For Instantiator nodes: inner builder function + `Instantiator<T>` wrapping.
	/// Collects all `safeDIParameters` references that would appear inside a
	/// `@Sendable func`, so they can be extracted and resolved outside the function.
	/// Each extraction is a `(localName, expression)` pair.
	private static func collectSendableExtractions(
		nodes: [MockParameterNode],
		parentPath: String,
		functionName: String,
		ancestorTypes: Set<String>,
		into extractions: inout [(localName: String, expression: String)],
	) {
		let labelMap = disambiguatePropertyLabels(for: nodes)
		for node in nodes {
			let nodeTypeKey = node.instantiatedTypeDescription.asSource
			let isCycleNode = ancestorTypes.contains(nodeTypeKey)
			let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
			let nodePath = "\(parentPath).\(disambiguated)"
			// Convert nodePath to a local name: replace dots with underscores,
			// strip the "safeDIParameters." prefix.
			let relativePath = nodePath
				.replacingOccurrences(of: "safeDIParameters.", with: "")
				.replacingOccurrences(of: ".", with: "_")

			if !isCycleNode {
				// Extract the safeDIBuilder (nil-coalesced with default).
				let defaultBuilder = node.defaultBuilderExpression
				extractions.append((
					localName: "\(functionName)__\(relativePath)_safeDIBuilder",
					expression: "\(nodePath).safeDIBuilder ?? \(defaultBuilder)",
				))
			}

			// Extract default parameter references.
			let defaultParameterLabels = Set(node.defaultParameters.map(\.label))
			for defaultParameter in node.defaultParameters {
				extractions.append((
					localName: "\(functionName)__\(relativePath)_\(defaultParameter.label)",
					expression: "\(nodePath).\(defaultParameter.label)",
				))
			}

			// Recurse into children (for constant node children inside the sendable function).
			if !node.isInstantiator {
				var childAncestors = ancestorTypes
				childAncestors.insert(nodeTypeKey)
				collectSendableExtractions(
					nodes: node.children,
					parentPath: nodePath,
					functionName: functionName,
					ancestorTypes: childAncestors,
					into: &extractions,
				)
			}
			// Instantiator children inside a sendable function would have their own
			// extraction scope — handled recursively when generateInstantiatorBinding
			// is called for the nested Instantiator.
		}
	}

	private static func generateMockBodyBindings(
		nodes: [MockParameterNode],
		parentPath: String,
		indent: String,
		ancestorTypes: Set<String> = [],
		sendableExtractionPrefix: String? = nil,
	) -> [String] {
		var lines = [String]()

		// Disambiguate sibling labels at this level.
		let labelMap = disambiguatePropertyLabels(for: nodes)

		for node in nodes {
			let nodeTypeKey = node.instantiatedTypeDescription.asSource
			let isCycleNode = ancestorTypes.contains(nodeTypeKey)

			let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
			let nodePath = "\(parentPath).\(disambiguated)"

			let defaultBuilder = node.defaultBuilderExpression
			let relativePath = nodePath
				.replacingOccurrences(of: "safeDIParameters.", with: "")
				.replacingOccurrences(of: ".", with: "_")

			// When inside a sendable extraction, use extracted locals instead of
			// safeDIParameters paths.
			let builderExpression: String
			let argumentNodePath: String
			if isCycleNode {
				builderExpression = defaultBuilder
				argumentNodePath = nodePath
			} else if let sendableExtractionPrefix {
				let extractedName = "\(sendableExtractionPrefix)__\(relativePath)_safeDIBuilder"
				builderExpression = extractedName
				argumentNodePath = nodePath // Used for resolveBuilderArguments
			} else {
				builderExpression = "(\(nodePath).safeDIBuilder ?? \(defaultBuilder))"
				argumentNodePath = nodePath
			}

			if node.isInstantiator {
				// For Instantiator nodes, children are generated INSIDE the builder
				// function because they may depend on forwarded properties that are
				// only available as function parameters. This mirrors the production
				// code which builds the entire subtree inside the builder function.
				var childAncestors = ancestorTypes
				childAncestors.insert(nodeTypeKey)
				lines.append(contentsOf: generateInstantiatorBinding(
					for: node,
					nodePath: nodePath,
					builderExpression: builderExpression,
					arguments: resolveBuilderArguments(
						for: node,
						nodePath: argumentNodePath,
						sendableExtractionPrefix: sendableExtractionPrefix,
					),
					indent: indent,
					ancestorTypes: childAncestors,
				))
			} else {
				let arguments = resolveBuilderArguments(
					for: node,
					nodePath: argumentNodePath,
					sendableExtractionPrefix: sendableExtractionPrefix,
				)
				let argumentList = arguments.joined(separator: ", ")

				if node.children.isEmpty {
					// Leaf constant node — flat binding, no scoping needed.
					if node.erasedToConcreteExistential {
						let protocolType = node.typeDescription.asSource
						lines.append("\(indent)let \(node.propertyLabel): \(protocolType) = \(protocolType)(\(builderExpression)(\(argumentList)))")
					} else {
						lines.append("\(indent)let \(node.propertyLabel) = \(builderExpression)(\(argumentList))")
					}
				} else {
					// Constant node with children — wrap in a function scope to
					// avoid variable name collisions with sibling bindings.
					// Mirrors the production code which uses named functions.
					let functionName = "__safeDI_\(node.propertyLabel)"
					let concreteTypeName = node.concreteTypeName
					let innerIndent = "\(indent)\(standardIndent)"

					var childAncestors = ancestorTypes
					childAncestors.insert(nodeTypeKey)

					lines.append("\(indent)func \(functionName)() -> \(concreteTypeName) {")

					let childBindings = generateMockBodyBindings(
						nodes: node.children,
						parentPath: nodePath,
						indent: innerIndent,
						ancestorTypes: childAncestors,
						sendableExtractionPrefix: sendableExtractionPrefix,
					)
					lines.append(contentsOf: childBindings)

					if node.erasedToConcreteExistential {
						let protocolType = node.typeDescription.asSource
						lines.append("\(innerIndent)return \(protocolType)(\(builderExpression)(\(argumentList)))")
					} else {
						lines.append("\(innerIndent)return \(builderExpression)(\(argumentList))")
					}
					lines.append("\(indent)}")

					if node.erasedToConcreteExistential {
						let protocolType = node.typeDescription.asSource
						lines.append("\(indent)let \(node.propertyLabel): \(protocolType) = \(functionName)()")
					} else {
						lines.append("\(indent)let \(node.propertyLabel) = \(functionName)()")
					}
				}
			}
		}

		return lines
	}

	/// Resolves the positional arguments for a builder call.
	/// Each argument comes from one of:
	/// - A local variable (previously built dep or flat mock param)
	/// - A stored default on SafeDIParameters (`{nodePath}.{label}`)
	private static func resolveBuilderArguments(
		for node: MockParameterNode,
		nodePath: String,
		sendableExtractionPrefix: String? = nil,
	) -> [String] {
		let dependencyLabels = Set(node.dependencies.map(\.property.label))
		let defaultParameterLabels = Set(node.defaultParameters.map(\.label))

		let relativePath = nodePath
			.replacingOccurrences(of: "safeDIParameters.", with: "")
			.replacingOccurrences(of: ".", with: "_")

		return node.constructionArguments.compactMap { argument in
			if dependencyLabels.contains(argument.innerLabel) {
				argument.innerLabel
			} else if defaultParameterLabels.contains(argument.label) {
				if let sendableExtractionPrefix {
					"\(sendableExtractionPrefix)__\(relativePath)_\(argument.label)"
				} else {
					"\(nodePath).\(argument.label)"
				}
			} else if argument.hasDefaultValue, argument.label != "_",
			          let defaultExpression = argument.defaultValueExpression
			{
				// Non-dependency default not tracked on the _Configuration struct
				// (e.g., Instantiator children where defaults don't bubble).
				// Pass the default expression inline so the builder call has
				// the correct arity for the function reference.
				defaultExpression
			} else {
				// Unknown argument — use the label as a local variable reference.
				argument.innerLabel
			}
		}
	}

	/// Generates the Instantiator wrapping bindings for an Instantiator node.
	/// Produces: inner builder function + `let {label} = Instantiator<T>(...)`.
	private static func generateInstantiatorBinding(
		for node: MockParameterNode,
		nodePath: String,
		builderExpression: String,
		arguments: [String],
		indent: String,
		ancestorTypes: Set<String> = [],
	) -> [String] {
		let functionName = "__safeDI_\(node.propertyLabel)"
		let concreteTypeName = node.concreteTypeName
		let forwardedProperties = node.forwardedProperties.sorted()
		let propertyType = node.typeDescription.propertyType
		let innerIndent = "\(indent)\(standardIndent)"

		// Build the inner function parameter list (forwarded properties).
		let functionArguments = if forwardedProperties.isEmpty {
			""
		} else {
			forwardedProperties.initializerFunctionParameters.map(\.description).joined()
		}

		// Build the forwarded arguments for the Instantiator closure call.
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

		// Build the builder call arguments for the inner function body.
		let builderCallArguments = arguments.joined(separator: ", ")

		let functionDecorator = if propertyType.isSendable {
			"@Sendable "
		} else {
			""
		}

		var lines = [String]()

		// Emit the inner builder function (unless it's a property cycle).
		// Children are generated INSIDE the function body because they may
		// depend on forwarded properties that are only available as parameters.
		if !node.isPropertyCycle {
			if propertyType.isSendable {
				// For @Sendable functions, extract all safeDIParameters references
				// OUTSIDE the function and resolve nil-coalescing here (in the
				// @MainActor mock() context). This avoids capturing the non-Sendable
				// SafeDIParameters struct inside the @Sendable function.
				var extractions = [(localName: String, expression: String)]()
				collectSendableExtractions(
					nodes: node.children,
					parentPath: nodePath,
					functionName: functionName,
					ancestorTypes: ancestorTypes,
					into: &extractions,
				)
				// Extract the node's own safeDIBuilder.
				extractions.append((
					localName: "\(functionName)__safeDIBuilder",
					expression: "\(builderExpression)",
				))

				for extraction in extractions {
					lines.append("\(indent)let \(extraction.localName) = \(extraction.expression)")
				}

				lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(concreteTypeName) {")

				// Generate children using extracted locals.
				let childBindings = generateMockBodyBindings(
					nodes: node.children,
					parentPath: nodePath,
					indent: innerIndent,
					ancestorTypes: ancestorTypes,
					sendableExtractionPrefix: functionName,
				)
				lines.append(contentsOf: childBindings)

				let extractedBuilderName = "\(functionName)__safeDIBuilder"
				if childBindings.isEmpty {
					lines.append("\(innerIndent)\(extractedBuilderName)(\(builderCallArguments))")
				} else {
					lines.append("\(innerIndent)return \(extractedBuilderName)(\(builderCallArguments))")
				}
				lines.append("\(indent)}")
			} else {
				lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(concreteTypeName) {")

				// Generate children's bindings inside the function body.
				let childBindings = generateMockBodyBindings(
					nodes: node.children,
					parentPath: nodePath,
					indent: innerIndent,
					ancestorTypes: ancestorTypes,
				)
				lines.append(contentsOf: childBindings)

				if childBindings.isEmpty {
					lines.append("\(innerIndent)\(builderExpression)(\(builderCallArguments))")
				} else {
					lines.append("\(innerIndent)return \(builderExpression)(\(builderCallArguments))")
				}
				lines.append("\(indent)}")
			}
		}

		// Emit the Instantiator/ErasedInstantiator construction.
		let unwrappedTypeDescription = node.typeDescription.unwrapped.asSource
		let instantiatedTypeDescription = node.instantiatedTypeDescription.asSource

		let instantiatorConstruction = if forwardedArguments.isEmpty, !node.erasedToConcreteExistential {
			"\(unwrappedTypeDescription)(\(functionName))"
		} else if node.erasedToConcreteExistential {
			"""
			\(unwrappedTypeDescription) {
			\(indent)\(standardIndent)\(instantiatedTypeDescription)(\(functionName)(\(forwardedArguments)))
			\(indent)}
			"""
		} else {
			"""
			\(unwrappedTypeDescription) {
			\(indent)\(standardIndent)\(functionName)(\(forwardedArguments))
			\(indent)}
			"""
		}

		lines.append("\(indent)let \(node.propertyLabel) = \(instantiatorConstruction)")

		return lines
	}

	private func wrapInConditionalCompilation(
		_ code: String,
		mockConditionalCompilation: String?,
	) -> String {
		if let mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(code)\n#endif"
		} else {
			code
		}
	}

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
	fileprivate static let incorrectlyConfiguredComment = "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"

	fileprivate func generateArgumentList(
		unavailableProperties: Set<Property>? = nil,
		forMockGeneration: Bool = false,
		useMockInitializer: Bool = true,
	) throws -> String {
		let initializerToUse: Initializer? = if forMockGeneration, useMockInitializer, let mockInitializer {
			// User-defined mock handles construction — use its parameter list
			// (may be empty for no-arg mock methods).
			mockInitializer
		} else {
			initializer
		}
		if forMockGeneration {
			// In the simple mock case (no dependencies, no tree), the initializer is always present
			// and covers all dependencies. The SafeDIParameters pipeline handles complex cases.
			guard let initializerToUse else { return "" }
			return initializerToUse
				.createMockInitializerArgumentList(
					given: dependencies,
					unavailableProperties: unavailableProperties,
				)
		} else {
			return try initializerToUse?
				.createInitializerArgumentList(
					given: dependencies,
					unavailableProperties: unavailableProperties,
				) ?? Self.incorrectlyConfiguredComment
		}
	}
}
