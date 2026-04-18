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
				.compactMap { [propertiesToDeclare] in
					switch $0.source {
					case .instantiated, .forwarded:
						nil
					case .received:
						$0.property
					case let .aliased(fulfillingProperty, _, _):
						// If the alias's fulfilling property is locally declared
						// (e.g., as an @Instantiated sibling), the alias binds
						// against that local — it doesn't need to be received.
						propertiesToDeclare.contains(fulfillingProperty) ? nil : fulfillingProperty
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
				.compactMap { [propertiesToDeclare] in
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
						// Skip locally-declared fulfilling properties — the
						// alias binds to the local, not to an ancestor.
						if onlyIfAvailable, !propertiesToDeclare.contains(fulfillingProperty) {
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
	/// Used both to order child generation (dependencies before dependents) and by mock
	/// generation to surface dependencies the tree does not itself provide.
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

	/// Context for mock code generation, consumed by the mock root when emitting the
	/// `mock()` method and its conditional-compilation wrapper.
	struct MockContext {
		/// The conditional compilation flag for wrapping mock output (e.g. "DEBUG").
		let mockConditionalCompilation: String?
		/// Maps types with hand-written mock methods to their mock method name (e.g. "mock" or a custom name).
		/// Used to provide default values for forwarded dependencies whose type has a hand-written mock.
		let forwardedParameterMockDefaults: [TypeDescription: String]
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

	/// Generates code for this scope. Dependency-tree mode emits the full subtree
	/// recursively. Mock mode only reaches this function for `.root` scopes, which
	/// delegate to `generateMockRootCode`; non-root mock code is produced via
	/// `collectMockParameterTree` + `generateMockBodyBindings` instead.
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

		// Forwarded dependencies → flat parameters on mock(). Defaults may be supplied
		// from the construction initializer or from a hand-written mock on the forwarded type.
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
		var flatReceivedParameters = [(label: String, typeSource: String)]()
		var onlyIfAvailableSafeDIParameterEntries = [(label: String, typeSource: String)]()
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
			if isOnlyIfAvailable {
				let typeSource: String = if receivedProperty.typeDescription.isOptional {
					receivedProperty.typeDescription.asSource
				} else {
					"\(receivedProperty.typeDescription.asSource)?"
				}
				onlyIfAvailableSafeDIParameterEntries.append((
					label: receivedProperty.label,
					typeSource: typeSource,
				))
			} else {
				flatReceivedParameters.append((
					label: receivedProperty.label,
					typeSource: receivedProperty.typeDescription.asSource,
				))
			}
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
		// Include onlyIfAvailable labels so flat params with the same label
		// get disambiguated (onlyIfAvailable entries are accessed via
		// safeDIOverrides.label, so they don't need disambiguation).
		// Forwarded parameters keep their original labels (must match init signature).
		let allFlatLabels = forwardedDependencies.map(\.property.label)
			+ rootDefaultParameters.map(\.label)
			+ flatReceivedParameters.map(\.label)
			+ flatUncoveredParameters.map(\.label)
			+ onlyIfAvailableSafeDIParameterEntries.map(\.label)
		var flatLabelCounts = [String: Int]()
		for label in allFlatLabels {
			flatLabelCounts[label, default: 0] += 1
		}
		// Map of (label → (typeSource → disambiguatedLabel)) for flat received
		// parameters whose label collided with another flat parameter. Builder calls
		// for child nodes that would reference the original label must substitute
		// the disambiguated name so the generated code references a real binding.
		var flatParameterDisambiguationMap = [String: [String: String]]()
		flatReceivedParameters = flatReceivedParameters.map { parameter in
			guard let count = flatLabelCounts[parameter.label], count > 1 else {
				return parameter
			}
			let disambiguatedLabel = "\(parameter.label)_\(parameter.typeSource.replacingOccurrences(of: "?", with: ""))"
			flatParameterDisambiguationMap[parameter.label, default: [:]][parameter.typeSource] = disambiguatedLabel
			return (label: disambiguatedLabel, typeSource: parameter.typeSource)
		}
		// 3. Simple mock case — no tree, no flat parameters.
		let hasTree = !parameterTree.isEmpty || !onlyIfAvailableSafeDIParameterEntries.isEmpty
		let hasFlatParameters = !forwardedDependencies.isEmpty
			|| !rootDefaultParameters.isEmpty
			|| !flatReceivedParameters.isEmpty
			|| !flatUncoveredParameters.isEmpty

		guard hasTree || hasFlatParameters else {
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableOptionalProperties,
				forMockGeneration: true,
			)
			let mockMethodName = instantiable.customMockName ?? InstantiableVisitor.mockMethodName
			let construction = if instantiable.mockInitializer != nil {
				"\(typeName).\(mockMethodName)(\(argumentList))"
			} else if instantiable.declarationType.isExtension {
				"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
			} else {
				"\(typeName)(\(argumentList))"
			}
			let code = """
			extension \(typeName) {
			    \(mockAttributesPrefix)static func mock() -> \(typeName) {
			        \(construction)
			    }
			}
			"""
			return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
		}

		// 4. Build the mock method.
		var lines = [String]()
		lines.append("extension \(typeName) {")

		if hasTree {
			lines.append(Self.generateSafeDIOverridesStruct(
				rootChildren: parameterTree,
				onlyIfAvailableEntries: onlyIfAvailableSafeDIParameterEntries,
				indent: indent,
			))
			lines.append("")
		}

		// Build mock() signature.
		// Build a lookup of default values from the construction initializer
		// so forwarded deps with defaults on customMock preserve them.
		let constructionDefaults: [String: String] = {
			guard let rootConstructionInitializer else { return [:] }
			var defaults = [String: String]()
			for argument in rootConstructionInitializer.arguments {
				if let defaultExpression = argument.defaultValueExpression {
					defaults[argument.innerLabel] = defaultExpression
				}
			}
			return defaults
		}()
		var mockParameters = [String]()
		for dependency in forwardedDependencies {
			let typeSource = dependency.property.typeDescription.asFunctionParameter.asSource
			if let defaultExpression = constructionDefaults[dependency.property.label] {
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource) = \(defaultExpression)")
			} else if let mockMethodName = context.forwardedParameterMockDefaults[dependency.property.typeDescription] {
				let mockTypeName = dependency.property.typeDescription.asSource
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource) = \(mockTypeName).\(mockMethodName)()")
			} else {
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource)")
			}
		}
		for rootDefault in rootDefaultParameters {
			mockParameters.append("\(bodyIndent)\(rootDefault.label): \(rootDefault.typeSource) = \(rootDefault.defaultExpression)")
		}
		for flatReceived in flatReceivedParameters {
			mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource)")
		}
		for flatUncovered in flatUncoveredParameters {
			mockParameters.append("\(bodyIndent)\(flatUncovered.label): \(flatUncovered.typeSource)")
		}
		if hasTree {
			mockParameters.append("\(bodyIndent)safeDIOverrides: SafeDIOverrides = .init()")
		}

		lines.append("\(indent)\(mockAttributesPrefix)static func mock(")
		lines.append(mockParameters.joined(separator: ",\n"))
		lines.append("\(indent)) -> \(typeName) {")

		// Generate mock body.
		// Fold root-sibling disambiguation into the receiver map so that:
		// (a) the root-return call below can reference disambiguated names when
		//     a root `.instantiated` dep label collided with a promoted sibling;
		// (b) `emitReceiverBindings` for root's own deps sees the merged map.
		var rootDisambiguationMap = flatParameterDisambiguationMap
		Self.mergeSiblingDisambiguations(into: &rootDisambiguationMap, for: parameterTree)

		// Emit the root's own receiver bindings (aliases + disambiguated
		// `.received` deps). `preChild` goes BEFORE tree bindings so nested
		// builder functions emitted among those bindings can capture these
		// aliases without forward-referencing. `postChildByFulfilling` is
		// threaded into the tree-binding walk so each entry emits right after
		// its fulfilling child — keeping the alias in scope for subsequent
		// siblings (matches production's `.alias` scope case).
		let rootReceiverBindings = Self.emitReceiverBindings(
			for: instantiable.dependencies,
			flatParameterDisambiguationMap: rootDisambiguationMap,
			localChildLabelAndTypes: Set(parameterTree.map { "\($0.propertyLabel):\($0.typeDescription.asSource)" }),
			indent: bodyIndent,
		)

		if hasTree {
			// Bind onlyIfAvailable entries first — tree bindings may reference them.
			for entry in onlyIfAvailableSafeDIParameterEntries {
				lines.append("\(bodyIndent)let \(entry.label): \(entry.typeSource) = safeDIOverrides.\(entry.label)")
			}
			lines.append(contentsOf: rootReceiverBindings.preChild)
			let bodyBindings = Self.generateMockBodyBindings(
				nodes: parameterTree,
				parentPath: "safeDIOverrides",
				indent: bodyIndent,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
				postChildBindingsByFulfilling: rootReceiverBindings.postChildByFulfilling,
			)
			lines.append(contentsOf: bodyBindings)
		} else {
			// No tree children — `postChildByFulfilling` is empty by
			// construction, so only `preChild` needs emitting.
			lines.append(contentsOf: rootReceiverBindings.preChild)
		}

		// Generate return statement.
		let returnArgumentList = try generateReturnArgumentList(
			instantiable: instantiable,
			disambiguationMap: rootDisambiguationMap,
		)
		let mockMethodName = instantiable.customMockName ?? InstantiableVisitor.mockMethodName
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
	/// Every dependency is resolved via its own label at the current scope —
	/// aliased deps have been emitted as `let <alias>: <Type> = <fulfilling>`
	/// bindings earlier in the body, so they reference the alias name directly.
	/// When root's own `.instantiated` dep label collided with a promoted
	/// sibling, the root-sibling disambiguation in `disambiguationMap` remaps
	/// the reference to the disambiguated binding name.
	private func generateReturnArgumentList(
		instantiable: Instantiable,
		disambiguationMap: [String: [String: String]] = [:],
	) throws -> String {
		let constructionInitializer: Initializer? = if let mockInitializer = instantiable.mockInitializer {
			mockInitializer
		} else {
			instantiable.initializer
		}
		guard let constructionInitializer else {
			return Instantiable.incorrectlyConfiguredComment
		}
		let dependenciesByLabel = Dictionary(
			uniqueKeysWithValues: instantiable.dependencies.map { ($0.property.label, $0) },
		)
		var parts = [String]()
		for argument in constructionInitializer.arguments {
			if let dependency = dependenciesByLabel[argument.innerLabel] {
				// When the dep's label was sibling-disambiguated in the tree
				// (e.g. root's `service: TypeA` when a promoted sibling is also
				// labeled `service`), the bound `let` uses the disambiguated
				// name. Rewrite the reference so the Root init call finds it.
				let typeSource = dependency.property.typeDescription.asSource
				let resolved = disambiguationMap[argument.innerLabel]?[typeSource] ?? argument.innerLabel
				parts.append("\(argument.label): \(resolved)")
			} else if argument.hasDefaultValue, argument.label != "_" {
				parts.append("\(argument.label): \(argument.label)")
			}
		}
		return parts.joined(separator: ", ")
	}

	// MARK: Mock scope context

	/// Emits the `let <label>: <Type> = <source>` bindings a scope needs to make
	/// its construction arguments resolvable via plain Swift lexical scoping.
	/// Mirrors production's `.alias` scope case: every dep that requires a local
	/// name becomes a real Swift binding so descendants (and the current scope's
	/// own constructor call) reference the dep by its natural label.
	///
	/// Two cases produce a binding:
	///
	/// 1. `.aliased(fulfilling, _, _)` — always. The `<fulfilling>` reference is
	///    routed through `flatParameterDisambiguationMap` when the fulfilling
	///    label points to a disambiguated flat parameter; otherwise the bare
	///    label resolves via lexical scoping (forwarded function parameter,
	///    ancestor tree `let`, or non-disambiguated flat mock parameter).
	/// 2. `.received` whose `(label, typeSource)` has an entry in
	///    `flatParameterDisambiguationMap` — the flat mock parameter was renamed
	///    to `<label>_<TypeSource>` to break a collision, so the scope introduces
	///    a local `let <label>: <Type> = <disambiguatedName>` alias that
	///    consumers reference by the bare label. This is the one-to-one analog
	///    of `.aliased` for the mock-specific disambiguation concern.
	///
	/// `.instantiated` and `.forwarded` never need a receiver binding: the
	/// former is bound as a child `let` at this scope, the latter as a function
	/// parameter on the wrapping builder.
	/// Emits receiver `let` bindings for a scope, partitioned by whether they
	/// reference a label that is locally bound by a sibling child node.
	///
	/// - `preChild`: receivers whose fulfilling label is NOT bound as a local
	///   child. These must be declared BEFORE sibling child bindings so that any
	///   nested builder functions emitted among those children can reference
	///   them (Swift does not allow nested functions to forward-reference
	///   `let`s declared later in the same scope).
	/// - `postChildByFulfilling`: aliases whose fulfilling `(label, typeSource)`
	///   IS bound as a local child, keyed by that specific pair. Sibling
	///   disambiguation allows multiple children to share a `propertyLabel`
	///   (distinguished by type), so keying by label alone would emit the alias
	///   after every same-labeled sibling. Callers emit each alias immediately
	///   after the specific fulfilling child's own binding so subsequent sibling
	///   nested functions can capture the alias without forward-referencing
	///   (Swift rejects nested-function captures of locals declared later in
	///   the same scope).
	fileprivate static func emitReceiverBindings(
		for dependencies: [Dependency],
		flatParameterDisambiguationMap: [String: [String: String]],
		localChildLabelAndTypes: Set<String> = [],
		indent: String,
	) -> (preChild: [String], postChildByFulfilling: [String: [String: [String]]]) {
		var preChild = [String]()
		var postChildByFulfilling = [String: [String: [String]]]()
		for dependency in dependencies {
			switch dependency.source {
			case let .aliased(fulfillingProperty, _, _):
				let aliasLabel = dependency.property.label
				let aliasTypeSource = dependency.property.typeDescription.asSource
				let fulfillingLabel = fulfillingProperty.label
				let fulfillingTypeSource = fulfillingProperty.typeDescription.asSource
				let resolvedFulfilling = flatParameterDisambiguationMap[fulfillingLabel]?[fulfillingTypeSource] ?? fulfillingLabel
				let line = "\(indent)let \(aliasLabel): \(aliasTypeSource) = \(resolvedFulfilling)"
				let fulfillingKey = "\(fulfillingLabel):\(fulfillingTypeSource)"
				if localChildLabelAndTypes.contains(fulfillingKey) {
					postChildByFulfilling[fulfillingLabel, default: [:]][fulfillingTypeSource, default: []].append(line)
				} else {
					preChild.append(line)
				}
			case .received:
				let label = dependency.property.label
				let typeSource = dependency.property.typeDescription.asSource
				if let disambiguatedLabel = flatParameterDisambiguationMap[label]?[typeSource] {
					preChild.append("\(indent)let \(label): \(typeSource) = \(disambiguatedLabel)")
				}
			case .instantiated, .forwarded:
				break
			}
		}
		return (preChild, postChildByFulfilling)
	}

	/// Whether a node's construction references any `.received` dependency whose
	/// flat mock parameter was disambiguated by type. Such nodes need a wrapping
	/// scope to emit the `let <label>: <Type> = <disambiguatedName>` alias, so
	/// that `resolveBuilderArguments` can reference the bare label.
	private static func hasDisambiguatedReceiver(
		_ node: MockParameterNode,
		flatParameterDisambiguationMap: [String: [String: String]],
	) -> Bool {
		guard !flatParameterDisambiguationMap.isEmpty else { return false }
		return node.dependencies.contains { dependency in
			guard case .received = dependency.source else { return false }
			let label = dependency.property.label
			let typeSource = dependency.property.typeDescription.asSource
			return flatParameterDisambiguationMap[label]?[typeSource] != nil
		}
	}

	// MARK: MockParameterNode

	/// A node in the mock parameter tree. Each node represents one property edge
	/// in the dependency tree and carries the metadata needed to generate its
	/// `SafeDIMockConfiguration` struct and builder call.
	struct MockParameterNode {
		/// The property label on the parent type's init (e.g., "service", "childBuilder").
		let propertyLabel: String
		/// The full type description of the property (e.g., `Instantiator<Child>`).
		let typeDescription: TypeDescription
		/// The instantiated type — `typeDescription.asInstantiatedType` (e.g., `Child`).
		/// Used for the builder closure's return type, disambiguation keys, and
		/// cycle detection. Configuration struct nesting uses `concreteType` instead.
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
		/// The concrete type (e.g., `ConcreteService`), which may differ from `instantiatedTypeDescription`
		/// when the property uses an existential wrapper (e.g., `AnyService` fulfilled by `ConcreteService`).
		let concreteType: TypeDescription
		/// Forwarded properties on this type (relevant for Instantiator edges).
		let forwardedProperties: Set<Property>
		/// Whether this node is part of a property cycle.
		let isPropertyCycle: Bool
		/// Whether this node is inside a sendable scope (descendant of SendableInstantiator).
		/// When `true`, the `safeDIBuilder` closure on `SafeDIMockConfiguration` is `@Sendable`.
		let requiresSendable: Bool

		/// Whether this node needs a full `SafeDIMockConfiguration` struct or can be
		/// inlined as an optional builder closure on the parent. A node needs a struct
		/// when it has children (subtree customization), non-dependency defaults, or is
		/// a property cycle (the struct may exist from a non-cycle instance of the same type).
		var needsConfigurationStruct: Bool {
			!children.isEmpty || !defaultParameters.isEmpty || isPropertyCycle
		}

		/// Whether this node declares any `@Received(fulfilledByDependencyNamed:)`
		/// dependencies. Aliases require a dedicated Swift scope to emit their
		/// `let <alias>: <Type> = <fulfilling>` bindings so descendants (and the
		/// node's own constructor) resolve them via lexical scoping.
		var hasAliasedDependencies: Bool {
			dependencies.contains {
				if case .aliased = $0.source { true } else { false }
			}
		}

		/// True when this node must be wrapped in a `__safeDI_<label>()` helper
		/// function — either because it needs a configuration struct or because
		/// it has aliased dependencies whose bindings must live in a local scope.
		var requiresFunctionWrapper: Bool {
			needsConfigurationStruct || hasAliasedDependencies
		}

		/// The nested configuration struct name (used in struct definitions).
		static let configurationStructName = "SafeDIMockConfiguration"

		/// The qualified configuration type name for references (e.g., `ChildA.SafeDIMockConfiguration`).
		/// Uses the concrete fulfilling type so the struct can be nested in a concrete type
		/// extension. Protocol extensions cannot contain nested type declarations.
		var configurationTypeName: String {
			"\(concreteType.asSource).\(Self.configurationStructName)"
		}

		/// The builder closure type as a Swift source string (unlabeled parameters).
		/// Uses the property type (not the concrete fulfilling type) so the override
		/// closure matches what the parent init expects. Swift covariant return types
		/// ensure a concrete builder (e.g., `ConcreteService.init`) is assignable to
		/// a closure returning the property type (e.g., `() -> ServiceProtocol`).
		var builderClosureType: String {
			let parameterTypes = constructionArguments
				.map(\.typeDescription.asFunctionParameter.asSource)
				.joined(separator: ", ")
			return "(\(parameterTypes)) -> \(instantiatedTypeDescription.asSource)"
		}

		/// The builder closure type using the concrete type for the return.
		/// Used in `SafeDIMockConfiguration` structs which are deduplicated by
		/// concrete type and must have a single consistent builder signature.
		var concreteBuilderClosureType: String {
			let parameterTypes = constructionArguments
				.map(\.typeDescription.asFunctionParameter.asSource)
				.joined(separator: ", ")
			return "(\(parameterTypes)) -> \(concreteType.asSource)"
		}

		/// The default builder expression as a direct function reference.
		/// e.g., `Grandchild.customMock(service:style:)` or `Service.init`.
		var defaultBuilderExpression: String {
			let methodName: String = if useMockInitializer {
				customMockName ?? InstantiableVisitor.mockMethodName
			} else if isExtensionBased {
				InstantiableVisitor.instantiateMethodName
			} else {
				"init"
			}
			if constructionArguments.isEmpty {
				return "\(concreteType.asSource).\(methodName)"
			} else {
				let labels = constructionArguments
					.map { "\($0.label):" }
					.joined()
				return "\(concreteType.asSource).\(methodName)(\(labels))"
			}
		}

		/// A direct call expression using the default builder with labeled arguments.
		/// e.g., `ConcreteService(helper: helper)` or `ConcreteService.instantiate(helper: helper)`.
		/// Unlike `defaultBuilderExpression` (a function reference for `??` coalescing),
		/// this produces a complete call that's faster for the compiler to type-check.
		func defaultBuilderCall(arguments: [String]) -> String {
			let methodName: String = if useMockInitializer {
				customMockName ?? InstantiableVisitor.mockMethodName
			} else if isExtensionBased {
				InstantiableVisitor.instantiateMethodName
			} else {
				"init"
			}
			let labeledArguments = zip(constructionArguments, arguments)
				.map { $0.0.label == "_" ? $0.1 : "\($0.0.label): \($0.1)" }
				.joined(separator: ", ")
			if methodName == "init" {
				return "\(concreteType.asSource)(\(labeledArguments))"
			} else {
				return "\(concreteType.asSource).\(methodName)(\(labeledArguments))"
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

	/// Collects all unique configuration types from this scope's mock parameter tree.
	func collectConfigurationTypes() async -> [(typeName: String, structCode: String)] {
		let parameterTree = await collectMockParameterTree()
		let uniqueTypes = Self.collectUniqueConfigurationTypes(from: parameterTree)
		let indent = Self.standardIndent
		return uniqueTypes.map { node in
			(
				typeName: node.concreteType.asSource,
				structCode: Self.generateConfigurationStruct(for: node, indent: indent),
			)
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
			var defaultParameters = [MockParameterNode.DefaultParameter]()
			if let constructionInitializer {
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
			// The macro validates that an initializer always exists, so one of
			// these will always be non-nil for well-formed types.
			let constructionArguments: [Initializer.Argument] = if let constructionInitializer {
				constructionInitializer.arguments
			} else {
				childInstantiable.initializer?.arguments ?? []
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
				concreteType: childInstantiable.concreteInstantiable,
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
			let collectedKeys = Set(flatUncoveredParameters.map { "\($0.label):\($0.typeSource)" })
			for dependency in node.dependencies {
				guard case .instantiated = dependency.source else { continue }
				// Skip deps that are covered by a child node in the tree.
				guard !childLabels.contains(dependency.property.label) else { continue }
				let sourceType = dependency.property.propertyType.isConstant
					? dependency.property.typeDescription.asInstantiatedType.asSource
					: dependency.property.typeDescription.asSource
				// Skip deps already collected (by label AND type).
				let key = "\(dependency.property.label):\(sourceType)"
				guard !collectedKeys.contains(key) else { continue }
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

	// MARK: SafeDIOverrides Generation

	/// Merges the sibling-level disambiguations for a given level of tree nodes
	/// into an existing receiver disambiguation map. Used at both the root scope
	/// and within `generateMockBodyBindings` so that consumers at the current
	/// scope can rebind disambiguated labels back to their natural labels via
	/// `emitReceiverBindings`, and so that the root's return call can reference
	/// disambiguated bindings when the root's own `.instantiated` dep label
	/// collides with a promoted sibling.
	private static func mergeSiblingDisambiguations(
		into map: inout [String: [String: String]],
		for nodes: [MockParameterNode],
	) {
		let labelMap = disambiguatePropertyLabels(for: nodes)
		for node in nodes {
			let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
			if disambiguated != node.propertyLabel {
				map[node.propertyLabel, default: [:]][node.typeDescription.asSource] = disambiguated
			}
		}
	}

	/// Computes disambiguated property labels for a list of nodes at the same scope level.
	/// When two nodes share a `propertyLabel`, appends `_TypeName` to make them unique.
	/// If the disambiguated name collides with another node's original label, appends
	/// additional underscores until unique.
	/// Returns a dictionary mapping each node's key to its disambiguated label.
	private static func disambiguatePropertyLabels(
		for nodes: [MockParameterNode],
	) -> [String: String] {
		var labelCounts = [String: Int]()
		for node in nodes {
			labelCounts[node.propertyLabel, default: 0] += 1
		}
		// Collect labels that don't need disambiguation (unique labels) as reserved.
		var reservedLabels = Set<String>()
		for node in nodes where labelCounts[node.propertyLabel]! == 1 {
			reservedLabels.insert(node.propertyLabel)
		}
		var result = [String: String]()
		for node in nodes {
			let key = "\(node.propertyLabel):\(node.instantiatedTypeDescription.asSource)"
			let count = labelCounts[node.propertyLabel]!
			if count > 1 {
				var disambiguated = "\(node.propertyLabel)_\(node.instantiatedTypeDescription.asSource)"
				while reservedLabels.contains(disambiguated) {
					disambiguated += "_"
				}
				reservedLabels.insert(disambiguated)
				result[key] = disambiguated
			} else {
				result[key] = node.propertyLabel
			}
		}
		return result
	}

	/// Returns the disambiguated property label for a node, given a disambiguation map.
	private static func disambiguatedLabel(
		for node: MockParameterNode,
		labelMap: [String: String],
	) -> String {
		labelMap["\(node.propertyLabel):\(node.instantiatedTypeDescription.asSource)"]!
	}

	/// Collects all unique types from the `MockParameterNode` tree, deduplicated
	/// by `concreteType`. Returns nodes in depth-first order (children before
	/// parents) so that referenced types appear before their referrers.
	/// Uses `concreteType` (not `instantiatedTypeDescription`) because config
	/// structs are nested in concrete type extensions — protocol extensions
	/// cannot contain nested type declarations.
	/// When the same type appears in both sendable and non-sendable contexts,
	/// the sendable version is preferred (`@Sendable` closures work in both contexts).
	private static func collectUniqueConfigurationTypes(
		from nodes: [MockParameterNode],
	) -> [MockParameterNode] {
		var seen = Set<String>()
		var result = [MockParameterNode]()

		func walk(_ node: MockParameterNode, ancestorTypes: Set<String> = []) {
			let key = node.concreteType.asSource
			// Skip nodes whose type matches an ancestor — self-referencing cycle.
			guard !ancestorTypes.contains(key) else { return }
			var childAncestors = ancestorTypes
			childAncestors.insert(key)
			// Process children first (depth-first).
			for child in node.children {
				walk(child, ancestorTypes: childAncestors)
			}
			// Skip leaf nodes that don't need a SafeDIMockConfiguration struct.
			guard node.needsConfigurationStruct else { return }
			if seen.contains(key) {
				// If this node requires sendable and the existing one doesn't,
				// replace it — @Sendable closures are compatible in both contexts.
				if node.requiresSendable,
				   let existingIndex = result.firstIndex(where: {
				   	$0.concreteType.asSource == key && !$0.requiresSendable
				   })
				{
					result[existingIndex] = node
				}
				return
			}
			seen.insert(key)
			result.append(node)
		}

		for node in nodes {
			walk(node)
		}
		return result
	}

	/// Generates the `SafeDIOverrides` struct. Configuration type references
	/// use qualified names (e.g., `ChildA.SafeDIMockConfiguration`).
	private static func generateSafeDIOverridesStruct(
		rootChildren: [MockParameterNode],
		onlyIfAvailableEntries: [(label: String, typeSource: String)],
		indent: String,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let memberIndent = "\(innerIndent)\(standardIndent)"

		var lines = [String]()
		lines.append("\(indent)/// Overrides for the mock dependency tree.")
		lines.append("\(indent)struct SafeDIOverrides {")

		// Disambiguate root-level children property labels.
		let rootLabelMap = disambiguatePropertyLabels(for: rootChildren)

		// Generate SafeDIOverrides init with root-level children and onlyIfAvailable entries.
		lines.append("\(innerIndent)init(")
		var initParameters = rootChildren.map { child in
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			if child.needsConfigurationStruct {
				return "\(memberIndent)\(label): \(child.configurationTypeName) = .init()"
			} else {
				let sendableAnnotation = child.requiresSendable ? "@Sendable " : ""
				return "\(memberIndent)\(label): (\(sendableAnnotation)\(child.builderClosureType))? = nil"
			}
		}
		for entry in onlyIfAvailableEntries {
			initParameters.append("\(memberIndent)\(entry.label): \(entry.typeSource) = nil")
		}
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		for child in rootChildren {
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			lines.append("\(memberIndent)self.\(label) = \(label)")
		}
		for entry in onlyIfAvailableEntries {
			lines.append("\(memberIndent)self.\(entry.label) = \(entry.label)")
		}
		lines.append("\(innerIndent)}")

		// Generate stored properties.
		lines.append("")
		for child in rootChildren {
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			if child.needsConfigurationStruct {
				lines.append("\(innerIndent)let \(label): \(child.configurationTypeName)")
			} else {
				let sendableAnnotation = child.requiresSendable ? "@Sendable " : ""
				lines.append("\(innerIndent)let \(label): (\(sendableAnnotation)\(child.builderClosureType))?")
			}
		}
		for entry in onlyIfAvailableEntries {
			lines.append("\(innerIndent)let \(entry.label): \(entry.typeSource)")
		}

		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// Generates a single `SafeDIMockConfiguration` struct for a `MockParameterNode`.
	/// When `node.requiresSendable` is `true`, the `safeDIBuilder` closure is marked
	/// `@Sendable` (the node is inside a `SendableInstantiator` scope).
	private static func generateConfigurationStruct(
		for node: MockParameterNode,
		indent: String,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let sendableAnnotation = node.requiresSendable ? "@Sendable " : ""
		var lines = [String]()

		lines.append("\(indent)/// Configuration for how this type is constructed within a mock tree.")
		lines.append("\(indent)struct \(MockParameterNode.configurationStructName) {")

		// Build init parameters in order: children, defaults, builder (last).
		var initParameters = [String]()
		var assignments = [String]()
		var storedProperties = [String]()

		// Child edge parameters (disambiguated if labels collide).
		// Exclude children whose type matches this node — they'd create a recursive
		// value type. These are self-referencing Instantiators (lazy cycles).
		let nonCycleChildren = node.children.filter {
			$0.concreteType != node.concreteType
		}
		let childLabelMap = disambiguatePropertyLabels(for: nonCycleChildren)
		for child in nonCycleChildren {
			let label = disambiguatedLabel(for: child, labelMap: childLabelMap)
			if child.needsConfigurationStruct {
				initParameters.append("\(innerIndent)\(standardIndent)\(label): \(child.configurationTypeName) = .init()")
				storedProperties.append("\(innerIndent)let \(label): \(child.configurationTypeName)")
			} else {
				let childSendable = child.requiresSendable ? "@Sendable " : ""
				initParameters.append("\(innerIndent)\(standardIndent)\(label): (\(childSendable)\(child.builderClosureType))? = nil")
				storedProperties.append("\(innerIndent)let \(label): (\(childSendable)\(child.builderClosureType))?")
			}
			assignments.append("\(innerIndent)\(standardIndent)self.\(label) = \(label)")
		}

		// Default-valued parameters.
		for defaultParameter in node.defaultParameters {
			let typeSource = defaultParameter.typeDescription.asSource
			// Only add @Sendable if the type doesn't already have it.
			let closureSendable = (node.requiresSendable && !typeSource.contains("@Sendable")) ? "@Sendable " : ""
			if defaultParameter.isClosureType {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(closureSendable)@escaping \(typeSource) = \(defaultParameter.defaultExpression)")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): \(closureSendable)\(typeSource)")
			} else {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(typeSource) = \(defaultParameter.defaultExpression)")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): \(typeSource)")
			}
			assignments.append("\(innerIndent)\(standardIndent)self.\(defaultParameter.label) = \(defaultParameter.label)")
		}

		// Builder parameter (always last, unlabeled). Optional with nil default so that
		// the default function reference (which may be @MainActor) is resolved in mock()
		// rather than in this nonisolated init.
		let closureType = node.concreteBuilderClosureType
		initParameters.append("\(innerIndent)\(standardIndent)_ safeDIBuilder: (\(sendableAnnotation)\(closureType))? = nil")
		assignments.append("\(innerIndent)\(standardIndent)self.safeDIBuilder = safeDIBuilder")
		storedProperties.append("\(innerIndent)/// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.")
		storedProperties.append("\(innerIndent)let safeDIBuilder: (\(sendableAnnotation)\(closureType))?")

		// Emit init.
		lines.append("\(innerIndent)init(")
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

	/// Collects all `safeDIOverrides` references that would appear inside a
	/// `@Sendable func`, so they can be extracted and resolved outside the function.
	/// Each extraction is a `(localName, optionalPath, defaultExpression)` tuple.
	/// When `optionalPath` is non-nil, the extraction resolves an optional builder via nil-coalescing.
	/// When `optionalPath` is nil, the extraction is a direct assignment — used for default
	/// parameter references and for erased-wrapper overrides whose defaults are resolved inside
	/// the builder function rather than via nil-coalescing.
	private static func collectSendableExtractions(
		nodes: [MockParameterNode],
		parentPath: String,
		functionName: String,
		ancestorTypes: Set<String>,
		into extractions: inout [(localName: String, optionalPath: String?, defaultExpression: String)],
	) {
		let labelMap = disambiguatePropertyLabels(for: nodes)
		for node in nodes {
			let nodeTypeKey = node.instantiatedTypeDescription.asSource
			let isCycleNode = ancestorTypes.contains(nodeTypeKey)
			let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
			let nodePath = "\(parentPath).\(disambiguated)"
			// Convert nodePath to a local name: replace dots with underscores,
			// strip the "safeDIOverrides." prefix.
			let relativePath = nodePath
				.replacingOccurrences(of: "safeDIOverrides.", with: "")
				.replacingOccurrences(of: ".", with: "_")

			if !isCycleNode {
				let defaultBuilder = node.defaultBuilderExpression
				if node.erasedToConcreteExistential {
					// Erased wrappers: the override returns the property type but
					// the default returns the concrete type — not covariant.
					// Extract only the override; the function body handles the default.
					let overridePath = if node.needsConfigurationStruct {
						"\(nodePath).safeDIBuilder"
					} else {
						nodePath
					}
					extractions.append((
						localName: "\(functionName)__\(relativePath)_safeDIBuilder",
						optionalPath: nil,
						defaultExpression: overridePath,
					))
				} else if node.needsConfigurationStruct {
					extractions.append((
						localName: "\(functionName)__\(relativePath)_safeDIBuilder",
						optionalPath: "\(nodePath).safeDIBuilder",
						defaultExpression: defaultBuilder,
					))
				} else {
					// Leaf builder — inline optional closure, no .safeDIBuilder path.
					extractions.append((
						localName: "\(functionName)__\(relativePath)_safeDIBuilder",
						optionalPath: nodePath,
						defaultExpression: defaultBuilder,
					))
				}
			}

			// Extract default parameter references — direct assignment, no optional.
			for defaultParameter in node.defaultParameters {
				extractions.append((
					localName: "\(functionName)__\(relativePath)_\(defaultParameter.label)",
					optionalPath: nil,
					defaultExpression: "\(nodePath).\(defaultParameter.label)",
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

	/// Generates the mock body bindings for the tree. Walks depth-first (children before
	/// parent), emitting `let` bindings that call through `safeDIOverrides.path.safeDIBuilder(...)`.
	///
	/// For leaf constant nodes: `let {label} = (safeDIOverrides.{path} ?? {defaultBuilder})({arguments})`
	/// For constant nodes with children: a nested helper function that returns the property type.
	/// For Instantiator nodes: an inner builder function plus `Instantiator<T>(...)` wrapping.
	/// When `sendableExtractionPrefix` is set, references resolve against extracted locals
	/// (produced by `collectSendableExtractions`) instead of `safeDIOverrides` paths.
	private static func generateMockBodyBindings(
		nodes: [MockParameterNode],
		parentPath: String,
		indent: String,
		ancestorTypes: Set<String> = [],
		sendableExtractionPrefix: String? = nil,
		flatParameterDisambiguationMap: [String: [String: String]] = [:],
		postChildBindingsByFulfilling: [String: [String: [String]]] = [:],
	) -> [String] {
		var lines = [String]()

		// Disambiguate sibling labels at this level.
		let labelMap = disambiguatePropertyLabels(for: nodes)

		// Merge sibling-level disambiguations into the receiver-disambiguation
		// map so consumers can rebind colliding sibling names back to their raw
		// labels via `emitReceiverBindings`, and construction arguments resolve
		// via Swift lexical scoping inside a wrapper function body.
		var combinedDisambiguationMap = flatParameterDisambiguationMap
		mergeSiblingDisambiguations(into: &combinedDisambiguationMap, for: nodes)

		for node in nodes {
			let nodeTypeKey = node.instantiatedTypeDescription.asSource
			let isCycleNode = ancestorTypes.contains(nodeTypeKey)

			let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
			let nodePath = "\(parentPath).\(disambiguated)"
			// When this node's label collides with a sibling, use the
			// disambiguated label for the outer `let` binding and for the
			// inner `__safeDI_<name>` function so neither redeclares across
			// siblings. Consumer nodes reach the value either directly (when
			// the dep also resolves to this sibling) via a rebinding emitted
			// by `emitReceiverBindings` inside the consumer's wrapper.
			let outerBindingName = disambiguated

			let defaultBuilder = node.defaultBuilderExpression
			let relativePath = nodePath
				.replacingOccurrences(of: "safeDIOverrides.", with: "")
				.replacingOccurrences(of: ".", with: "_")

			// When inside a sendable extraction, use extracted locals instead of
			// safeDIOverrides paths.
			let builderExpression: String
			let optionalBuilderPath: String?
			let argumentNodePath: String
			if isCycleNode {
				builderExpression = defaultBuilder
				optionalBuilderPath = nil
				argumentNodePath = nodePath
			} else if let sendableExtractionPrefix {
				let extractedName = "\(sendableExtractionPrefix)__\(relativePath)_safeDIBuilder"
				builderExpression = extractedName
				optionalBuilderPath = nil
				argumentNodePath = nodePath
			} else if node.needsConfigurationStruct {
				builderExpression = "(\(nodePath).safeDIBuilder ?? \(defaultBuilder))"
				optionalBuilderPath = "\(nodePath).safeDIBuilder"
				argumentNodePath = nodePath
			} else {
				// Leaf builder — inline optional closure, no .safeDIBuilder path.
				builderExpression = "(\(nodePath) ?? \(defaultBuilder))"
				optionalBuilderPath = nodePath
				argumentNodePath = nodePath
			}

			let arguments = resolveBuilderArguments(
				for: node,
				nodePath: argumentNodePath,
				sendableExtractionPrefix: sendableExtractionPrefix,
			)
			let argumentList = arguments.joined(separator: ", ")

			if node.isInstantiator {
				// For Instantiator nodes, children are generated INSIDE the builder
				// function because they may depend on forwarded properties that are
				// only available as function parameters. This mirrors the production
				// code which builds the entire subtree inside the builder function.
				var childAncestors = ancestorTypes
				childAncestors.insert(nodeTypeKey)
				lines.append(contentsOf: generateInstantiatorBinding(
					for: node,
					outerBindingName: outerBindingName,
					nodePath: nodePath,
					builderExpression: builderExpression,
					optionalBuilderPath: optionalBuilderPath,
					arguments: arguments,
					indent: indent,
					ancestorTypes: childAncestors,
					flatParameterDisambiguationMap: combinedDisambiguationMap,
				))
			} else if node.requiresFunctionWrapper || hasDisambiguatedReceiver(node, flatParameterDisambiguationMap: combinedDisambiguationMap) {
				// Constant node that needs a dedicated Swift scope — either for its
				// own children/defaults/cycle, for aliased deps, or to host the
				// `let <label>: <Type> = <disambiguatedName>` binding that aliases a
				// disambiguated flat mock parameter back to its natural label. A
				// function scope keeps child bindings from colliding with siblings'
				// child bindings that share the same property label and gives these
				// receiver bindings a place to live.
				let functionName = "__safeDI_\(disambiguated)"
				let propertyTypeName = node.instantiatedTypeDescription.asSource
				let innerIndent = "\(indent)\(standardIndent)"

				let receiverBindings = emitReceiverBindings(
					for: node.dependencies,
					flatParameterDisambiguationMap: combinedDisambiguationMap,
					localChildLabelAndTypes: Set(node.children.map { "\($0.propertyLabel):\($0.typeDescription.asSource)" }),
					indent: innerIndent,
				)

				var childAncestors = ancestorTypes
				childAncestors.insert(nodeTypeKey)
				let childBindings = generateMockBodyBindings(
					nodes: node.children,
					parentPath: nodePath,
					indent: innerIndent,
					ancestorTypes: childAncestors,
					sendableExtractionPrefix: sendableExtractionPrefix,
					flatParameterDisambiguationMap: combinedDisambiguationMap,
					postChildBindingsByFulfilling: receiverBindings.postChildByFulfilling,
				)

				if node.erasedToConcreteExistential {
					// The default builder returns the concrete type and must be wrapped.
					// The override closure's return type depends on whether the node has
					// a configuration struct: the struct's `safeDIBuilder` returns the
					// concrete type (must be wrapped), while the inline closure used
					// when there is no struct already returns the property/wrapper type
					// (wrapping it again is a double-wrap and won't compile for erasers
					// that don't accept their own erased type).
					// In sendable context, use the extracted local (builderExpression)
					// instead of referencing safeDIOverrides directly.
					// Note: constant erased cycles are rejected by mock validation
					// before reaching this point, so isCycleNode is always false here.
					let wrapperType = node.typeDescription.asSource
					let overridePath = optionalBuilderPath ?? builderExpression
					lines.append("\(indent)func \(functionName)() -> \(propertyTypeName) {")
					lines.append(contentsOf: receiverBindings.preChild)
					lines.append(contentsOf: childBindings)
					lines.append("\(innerIndent)if let safeDIBuilder = \(overridePath) {")
					if node.needsConfigurationStruct {
						lines.append("\(innerIndent)\(standardIndent)return \(wrapperType)(safeDIBuilder(\(argumentList)))")
					} else {
						lines.append("\(innerIndent)\(standardIndent)return safeDIBuilder(\(argumentList))")
					}
					lines.append("\(innerIndent)} else {")
					lines.append("\(innerIndent)\(standardIndent)return \(wrapperType)(\(node.defaultBuilderCall(arguments: arguments)))")
					lines.append("\(innerIndent)}")
					lines.append("\(indent)}")
				} else {
					lines.append("\(indent)func \(functionName)() -> \(propertyTypeName) {")
					lines.append(contentsOf: receiverBindings.preChild)
					lines.append(contentsOf: childBindings)
					lines.append("\(innerIndent)return \(builderExpression)(\(argumentList))")
					lines.append("\(indent)}")
				}

				lines.append("\(indent)let \(outerBindingName): \(propertyTypeName) = \(functionName)()")
			} else {
				// Leaf constant node — flat binding, no scoping needed.
				if let optionalBuilderPath {
					if node.erasedToConcreteExistential {
						// The override closure returns the property type directly.
						// The default builder returns the concrete type, which must
						// be wrapped. Use optional chaining + ?? to split the paths.
						let wrapperType = node.typeDescription.asSource
						lines.append("\(indent)let \(outerBindingName) = \(optionalBuilderPath)?(\(argumentList)) ?? \(wrapperType)(\(node.defaultBuilderCall(arguments: arguments)))")
					} else {
						let leafBuilderExpression = "(\(optionalBuilderPath) ?? \(node.defaultBuilderExpression))"
						lines.append("\(indent)let \(outerBindingName) = \(leafBuilderExpression)(\(argumentList))")
					}
				} else if node.erasedToConcreteExistential {
					// Sendable context: extracted local is optional.
					let wrapperType = node.typeDescription.asSource
					lines.append("\(indent)let \(outerBindingName) = \(builderExpression)?(\(argumentList)) ?? \(wrapperType)(\(node.defaultBuilderCall(arguments: arguments)))")
				} else {
					lines.append("\(indent)let \(outerBindingName) = \(builderExpression)(\(argumentList))")
				}
			}

			// Interleave any enclosing-scope alias bindings whose fulfilling
			// label matches this child's propertyLabel. Emitting here (rather
			// than after all siblings) keeps the alias in scope for any
			// subsequent sibling nested functions, which Swift forbids from
			// forward-referencing later-declared locals.
			if let postChild = postChildBindingsByFulfilling[node.propertyLabel]?[node.typeDescription.asSource] {
				lines.append(contentsOf: postChild)
			}
		}

		return lines
	}

	/// Resolves the positional arguments for a builder call.
	/// Every dependency is referenced by its bare property label at this scope —
	/// `.aliased` and disambiguated `.received` deps are bound as `let`s by
	/// `emitReceiverBindings` in the enclosing wrapper; `.instantiated` is bound
	/// as a sibling `let`; `.forwarded` is bound as a function parameter;
	/// undisambiguated `.received` labels reach a flat mock parameter (or
	/// ancestor tree binding) via Swift lexical scoping. Non-dependency
	/// arguments come from `SafeDIOverrides` storage or their inline default.
	private static func resolveBuilderArguments(
		for node: MockParameterNode,
		nodePath: String,
		sendableExtractionPrefix: String? = nil,
	) -> [String] {
		let dependenciesByLabel = Dictionary(
			uniqueKeysWithValues: node.dependencies.map { ($0.property.label, $0) },
		)
		let defaultParameterLabels = Set(node.defaultParameters.map(\.label))

		let relativePath = nodePath
			.replacingOccurrences(of: "safeDIOverrides.", with: "")
			.replacingOccurrences(of: ".", with: "_")

		return node.constructionArguments.compactMap { argument in
			if dependenciesByLabel[argument.innerLabel] != nil {
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
				// Argument has a default value but isn't tracked on the child's
				// SafeDIMockConfiguration (e.g., when a zero-arg mock initializer
				// overrides a production init that still carries default-valued
				// non-dependency parameters). Pass the default expression inline
				// so the builder call has the correct arity.
				defaultExpression
			} else {
				// Unknown argument — use the label as a local variable reference.
				argument.innerLabel
			}
		}
	}

	/// Generates the wrapping bindings for an Instantiator-family node
	/// (`Instantiator`, `SendableInstantiator`, `ErasedInstantiator`, or
	/// `SendableErasedInstantiator`). Produces an inner builder function plus a
	/// `let {label} = <WrapperType>(...)` construction.
	private static func generateInstantiatorBinding(
		for node: MockParameterNode,
		outerBindingName: String,
		nodePath: String,
		builderExpression: String,
		optionalBuilderPath: String?,
		arguments: [String],
		indent: String,
		ancestorTypes: Set<String> = [],
		flatParameterDisambiguationMap: [String: [String: String]] = [:],
	) -> [String] {
		let functionName = "__safeDI_\(outerBindingName)"
		let forwardedProperties = node.forwardedProperties.sorted()
		let propertyType = node.typeDescription.propertyType
		let innerIndent = "\(indent)\(standardIndent)"

		// Emit alias and disambiguated-receiver bindings inside the inner
		// builder function so construction arguments resolve by bare label via
		// Swift lexical scoping. An alias whose fulfilling property is itself a
		// local child is deferred to `postChild` so the fulfilling `let` is
		// declared first; others come before children so nested builder
		// functions can capture them without forward-referencing.
		let receiverBindings = emitReceiverBindings(
			for: node.dependencies,
			flatParameterDisambiguationMap: flatParameterDisambiguationMap,
			localChildLabelAndTypes: Set(node.children.map { "\($0.propertyLabel):\($0.typeDescription.asSource)" }),
			indent: innerIndent,
		)

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
				// For @Sendable functions, extract all safeDIOverrides references
				// OUTSIDE the function and resolve nil-coalescing here (in the
				// @MainActor mock() context). This avoids capturing the non-Sendable
				// SafeDIOverrides struct inside the @Sendable function.
				var extractions = [(localName: String, optionalPath: String?, defaultExpression: String)]()
				collectSendableExtractions(
					nodes: node.children,
					parentPath: nodePath,
					functionName: functionName,
					ancestorTypes: ancestorTypes,
					into: &extractions,
				)
				// Extract the node's own safeDIBuilder.
				let extractedBuilderName = "\(functionName)__safeDIBuilder"
				if node.erasedToConcreteExistential, let optionalBuilderPath {
					// For erased wrappers, the override returns the property type
					// but the default returns the concrete type — not covariant.
					// Extract only the override; handle the default inside the function.
					extractions.append((
						localName: extractedBuilderName,
						optionalPath: nil,
						defaultExpression: optionalBuilderPath,
					))
				} else if let optionalBuilderPath {
					extractions.append((
						localName: extractedBuilderName,
						optionalPath: optionalBuilderPath,
						defaultExpression: node.defaultBuilderExpression,
					))
				} else {
					extractions.append((
						localName: extractedBuilderName,
						optionalPath: nil,
						defaultExpression: builderExpression,
					))
				}

				for extraction in extractions {
					if let optionalPath = extraction.optionalPath {
						lines.append("\(indent)let \(extraction.localName) = \(optionalPath) ?? \(extraction.defaultExpression)")
					} else {
						lines.append("\(indent)let \(extraction.localName) = \(extraction.defaultExpression)")
					}
				}

				let functionReturnType = node.instantiatedTypeDescription.asSource
				lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(functionReturnType) {")

				lines.append(contentsOf: receiverBindings.preChild)

				// Generate children using extracted locals.
				// Include this node's type in ancestors for cycle detection.
				var functionAncestors = ancestorTypes
				functionAncestors.insert(node.instantiatedTypeDescription.asSource)
				let childBindings = generateMockBodyBindings(
					nodes: node.children,
					parentPath: nodePath,
					indent: innerIndent,
					ancestorTypes: functionAncestors,
					sendableExtractionPrefix: functionName,
					flatParameterDisambiguationMap: flatParameterDisambiguationMap,
					postChildBindingsByFulfilling: receiverBindings.postChildByFulfilling,
				)
				lines.append(contentsOf: childBindings)

				// Swift's implicit-return rule only applies when the function
				// body is a single expression. Receiver bindings and child
				// bindings both add extra statements, so either one forces an
				// explicit `return`.
				let hasPreamble = !childBindings.isEmpty
					|| !receiverBindings.preChild.isEmpty

				if node.erasedToConcreteExistential {
					let wrapperType = node.typeDescription.unwrapped.asInstantiatedType.asSource
					let returnKeyword = hasPreamble ? "return " : ""
					lines.append("\(innerIndent)if let \(extractedBuilderName) {")
					if node.needsConfigurationStruct {
						// Config struct's safeDIBuilder returns the concrete type — wrap.
						lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(wrapperType)(\(extractedBuilderName)(\(builderCallArguments)))")
					} else {
						// Inline closure returns the property type — no wrap.
						lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(extractedBuilderName)(\(builderCallArguments))")
					}
					lines.append("\(innerIndent)} else {")
					lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(wrapperType)(\(node.defaultBuilderCall(arguments: arguments)))")
					lines.append("\(innerIndent)}")
				} else if !hasPreamble {
					lines.append("\(innerIndent)\(extractedBuilderName)(\(builderCallArguments))")
				} else {
					lines.append("\(innerIndent)return \(extractedBuilderName)(\(builderCallArguments))")
				}
				lines.append("\(indent)}")
			} else {
				let functionReturnType = node.instantiatedTypeDescription.asSource

				lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(functionReturnType) {")

				lines.append(contentsOf: receiverBindings.preChild)

				// Generate children's bindings inside the function body.
				// Include this node's type in ancestors so self-referencing
				// cycles (e.g., Instantiator<Self>) are detected.
				var functionAncestors = ancestorTypes
				functionAncestors.insert(node.instantiatedTypeDescription.asSource)
				let childBindings = generateMockBodyBindings(
					nodes: node.children,
					parentPath: nodePath,
					indent: innerIndent,
					ancestorTypes: functionAncestors,
					flatParameterDisambiguationMap: flatParameterDisambiguationMap,
					postChildBindingsByFulfilling: receiverBindings.postChildByFulfilling,
				)
				lines.append(contentsOf: childBindings)

				// Swift's implicit-return rule only applies when the function
				// body is a single expression. Receiver bindings and child
				// bindings both add extra statements, so either one forces an
				// explicit `return`.
				let hasPreamble = !childBindings.isEmpty
					|| !receiverBindings.preChild.isEmpty

				if node.erasedToConcreteExistential, let optionalBuilderPath {
					let wrapperType = node.typeDescription.unwrapped.asInstantiatedType.asSource
					let returnKeyword = hasPreamble ? "return " : ""
					lines.append("\(innerIndent)if let safeDIBuilder = \(optionalBuilderPath) {")
					if node.needsConfigurationStruct {
						// Config struct's safeDIBuilder returns the concrete type — wrap.
						lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(wrapperType)(safeDIBuilder(\(builderCallArguments)))")
					} else {
						// Inline closure returns the property type — no wrap.
						lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)safeDIBuilder(\(builderCallArguments))")
					}
					lines.append("\(innerIndent)} else {")
					lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(wrapperType)(\(node.defaultBuilderCall(arguments: arguments)))")
					lines.append("\(innerIndent)}")
				} else if node.erasedToConcreteExistential {
					// Sendable-extracted context: builderExpression is the extracted
					// optional local.
					let wrapperType = node.typeDescription.unwrapped.asInstantiatedType.asSource
					let returnKeyword = hasPreamble ? "return " : ""
					lines.append("\(innerIndent)if let \(builderExpression) {")
					if node.needsConfigurationStruct {
						lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(wrapperType)(\(builderExpression)(\(builderCallArguments)))")
					} else {
						lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(builderExpression)(\(builderCallArguments))")
					}
					lines.append("\(innerIndent)} else {")
					lines.append("\(innerIndent)\(standardIndent)\(returnKeyword)\(wrapperType)(\(node.defaultBuilderCall(arguments: arguments)))")
					lines.append("\(innerIndent)}")
				} else if let optionalBuilderPath {
					let nilCoalescingExpression = "(\(optionalBuilderPath) ?? \(node.defaultBuilderExpression))"
					if !hasPreamble {
						lines.append("\(innerIndent)\(nilCoalescingExpression)(\(builderCallArguments))")
					} else {
						lines.append("\(innerIndent)return \(nilCoalescingExpression)(\(builderCallArguments))")
					}
				} else if !hasPreamble {
					lines.append("\(innerIndent)\(builderExpression)(\(builderCallArguments))")
				} else {
					lines.append("\(innerIndent)return \(builderExpression)(\(builderCallArguments))")
				}
				lines.append("\(indent)}")
			}
		}

		// Emit the Instantiator/ErasedInstantiator construction.
		let unwrappedTypeDescription = node.typeDescription.unwrapped.asSource

		// The builder function now returns the property type directly (including
		// wrapping for erasedToConcreteExistential), so no outer wrapping needed.
		let instantiatorConstruction = if forwardedArguments.isEmpty {
			"\(unwrappedTypeDescription)(\(functionName))"
		} else {
			"""
			\(unwrappedTypeDescription) {
			\(indent)\(standardIndent)\(functionName)(\(forwardedArguments))
			\(indent)}
			"""
		}

		lines.append("\(indent)let \(outerBindingName) = \(instantiatorConstruction)")

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
			// and covers all dependencies. The SafeDIOverrides pipeline handles complex cases.
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
