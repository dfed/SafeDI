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

		var instantiable: Instantiable? {
			switch self {
			case let .root(instantiable),
			     let .property(instantiable, _, _, _, _):
				instantiable
			case .alias:
				nil
			}
		}

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

		var isMock: Bool {
			switch self {
			case .dependencyTree:
				false
			case .mock:
				true
			}
		}
	}

	/// Context for mock code generation, threaded through the tree.
	struct MockContext {
		/// The conditional compilation flag for wrapping mock output (e.g. "DEBUG").
		let mockConditionalCompilation: String?
		/// Maps mock parameter identifiers to their disambiguated parameter labels.
		let parameterLabelMap: [MockParameterIdentifier: String]
		/// Mock parameters declared as optional (`T? = nil`) rather than `@autoclosure`.
		/// Used by `generatePropertyCode` to pick the binding pattern.
		let subtreeParameters: Set<MockParameterIdentifier>
		/// Parameters already bound at root scope. Child functions skip bindings for these
		/// since the values are captured from the enclosing scope.
		let resolvedParameters: Set<MockParameterIdentifier>

		init(
			mockConditionalCompilation: String?,
			parameterLabelMap: [MockParameterIdentifier: String] = [:],
			subtreeParameters: Set<MockParameterIdentifier> = [],
			resolvedParameters: Set<MockParameterIdentifier> = [],
		) {
			self.mockConditionalCompilation = mockConditionalCompilation
			self.parameterLabelMap = parameterLabelMap
			self.subtreeParameters = subtreeParameters
			self.resolvedParameters = resolvedParameters
		}
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
			// Mark as fulfilled before recursing to prevent cycles.
			propertyToUnfulfilledScopeMap[property] = nil
			let scopeDependencies = propertyToUnfulfilledScopeMap
				.keys
				.intersection(
					scope.receivedProperties
						.union(scope.onlyIfAvailableUnwrappedReceivedProperties),
				)
				.compactMap { propertyToUnfulfilledScopeMap[$0] }
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
	}

	private func generateProperties(
		codeGeneration: CodeGeneration = .dependencyTree,
		leadingMemberWhitespace: String,
	) async throws -> [String] {
		var generatedProperties = [String]()
		// In mock mode, accumulate resolved identifiers across siblings so later
		// siblings' descendants know earlier siblings' bindings are already in scope.
		var currentCodeGeneration = codeGeneration
		for (index, childGenerator) in orderedPropertiesToGenerate.enumerated() {
			try await generatedProperties.append(
				childGenerator.generateCode(
					codeGeneration: currentCodeGeneration,
					propertiesAlreadyGeneratedAtThisScope: .init(orderedPropertiesToGenerate[0..<index].compactMap(\.property)),
					leadingWhitespace: leadingMemberWhitespace,
				),
			)
			if case let .mock(context) = currentCodeGeneration,
			   let childProperty = childGenerator.property
			{
				// Use the same sourceType that generatePropertyCode uses for each property type.
				let sourceType = childProperty.propertyType.isConstant
					? childProperty.typeDescription.asInstantiatedType.asSource
					: childProperty.typeDescription.asSource
				let identifier = MockParameterIdentifier(
					propertyLabel: childProperty.label,
					sourceType: sourceType,
				)
				currentCodeGeneration = .mock(MockContext(
					mockConditionalCompilation: context.mockConditionalCompilation,
					parameterLabelMap: context.parameterLabelMap,
					subtreeParameters: context.subtreeParameters,
					resolvedParameters: context.resolvedParameters.union([identifier]),
				))
			}
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
				forMockGeneration: codeGeneration.isMock && property.propertyType.isConstant,
			)
			let concreteTypeName = instantiable.concreteInstantiable.asSource
			let instantiationDeclaration: String = switch codeGeneration {
			case .dependencyTree:
				if instantiable.declarationType.isExtension {
					"\(concreteTypeName).\(InstantiableVisitor.instantiateMethodName)"
				} else {
					concreteTypeName
				}
			case .mock:
				// Types with a user-defined mock() use .mock() for construction.
				// The user's mock method handles all defaults and test configuration.
				if instantiable.mockInitializer != nil {
					"\(concreteTypeName).mock"
				} else if instantiable.declarationType.isExtension {
					"\(concreteTypeName).\(InstantiableVisitor.instantiateMethodName)"
				} else {
					concreteTypeName
				}
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

				// Mock mode: wrap the binding with an override closure.
				switch codeGeneration {
				case .dependencyTree:
					return """
					\(functionDeclaration)\(propertyDeclaration) = \(instantiatorInstantiation)
					"""
				case let .mock(context):
					let identifier = MockParameterIdentifier(
						propertyLabel: property.label,
						sourceType: property.typeDescription.asSource,
					)
					if context.resolvedParameters.contains(identifier) {
						// Already resolved by an ancestor scope — use inline construction.
						return """
						\(functionDeclaration)\(propertyDeclaration) = \(instantiatorInstantiation)
						"""
					} else if let parameterLabel = context.parameterLabelMap[identifier] {
						return """
						\(functionDeclaration)\(propertyDeclaration) = \(parameterLabel) ?? \(instantiatorInstantiation)
						"""
					} else {
						return """
						\(functionDeclaration)\(propertyDeclaration) = \(instantiatorInstantiation)
						"""
					}
				}
			case .constant:
				// In mock mode, mark this property as resolved so descendant scopes
				// don't re-generate ?? or () bindings for it.
				let childCodeGeneration: CodeGeneration = switch codeGeneration {
				case .dependencyTree:
					.dependencyTree
				case let .mock(context):
					.mock(MockContext(
						mockConditionalCompilation: context.mockConditionalCompilation,
						parameterLabelMap: context.parameterLabelMap,
						subtreeParameters: context.subtreeParameters,
						resolvedParameters: context.resolvedParameters.union([MockParameterIdentifier(
							propertyLabel: property.label,
							sourceType: property.typeDescription.asInstantiatedType.asSource,
						)]),
					))
				}
				let generatedProperties = try await generateProperties(
					codeGeneration: childCodeGeneration,
					leadingMemberWhitespace: Self.standardIndent,
				)

				// In mock mode, generate bindings for:
				// 1. Default-valued init parameters (evaluates @autoclosure parameter)
				// 2. Uncovered @Instantiated dependencies (evaluates required @autoclosure parameter)
				// Wrapping in a function scopes the bindings to avoid name collisions between siblings.
				let mockExtraBindings: [String] = switch codeGeneration {
				case .dependencyTree:
					[]
				case let .mock(context):
					Self.defaultValueBindings(
						for: instantiable,
						parameterLabelMap: context.parameterLabelMap,
						resolvedParameters: context.resolvedParameters,
					) + Self.uncoveredDependencyBindings(
						for: instantiable,
						declaredProperties: propertiesToDeclare,
						parameterLabelMap: context.parameterLabelMap,
						resolvedParameters: context.resolvedParameters,
					)
				}

				let hasGeneratedContent = !generatedProperties.isEmpty || !mockExtraBindings.isEmpty
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
				let allFunctionBodyLines = mockExtraBindings.map { "\(Self.standardIndent)\($0)" } + generatedProperties
				let functionDeclaration = if !hasGeneratedContent {
					""
				} else {
					"""
					func \(functionName)() -> \(concreteTypeName) {
					\(allFunctionBodyLines.joined(separator: "\n"))
					\(Self.standardIndent)return \(returnLineSansReturn)
					}

					"""
				}
				let returnLineSansReturn = if erasedToConcreteExistential {
					"\(property.typeDescription.asSource)(\(returnLineSansReturn))"
				} else {
					returnLineSansReturn
				}
				let initializer = if !hasGeneratedContent {
					returnLineSansReturn
				} else {
					"\(functionName)()"
				}

				switch codeGeneration {
				case .dependencyTree:
					return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
				case let .mock(context):
					let identifier = MockParameterIdentifier(
						propertyLabel: property.label,
						sourceType: property.typeDescription.asInstantiatedType.asSource,
					)
					// If this property was already resolved by an ancestor scope,
					// use inline construction — the value is available from outer scope.
					if context.resolvedParameters.contains(identifier) {
						return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
					} else if let parameterLabel = context.parameterLabelMap[identifier] {
						if context.subtreeParameters.contains(identifier) {
							// Optional parameter (T? = nil): use ?? inline fallback
							let mockInitializer = if erasedToConcreteExistential {
								"\(property.typeDescription.asSource)(\(initializer))"
							} else {
								initializer
							}
							return "\(functionDeclaration)\(propertyDeclaration) = \(parameterLabel) ?? \(mockInitializer)\n"
						} else {
							// Autoclosure parameter: evaluate
							return "\(propertyDeclaration) = \(parameterLabel)()\n"
						}
					} else {
						// Nested child (no root parameter): inline construction
						return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
					}
				}
			}
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
			// Aliases are identical in both modes.
			return if onlyIfAvailable, unavailableProperties.contains(fulfillingProperty) {
				"// Did not create `\(property.asSource)` because `\(fulfillingProperty.asSource)` is unavailable."
			} else {
				if erasedToConcreteExistential {
					"let \(property.label): \(property.typeDescription.asSource) = \(fulfillingProperty.label)"
				} else {
					"let \(property.asSource) = \(fulfillingProperty.label)"
				}
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

		// Collect forwarded properties — these become bare (non-closure) parameters.
		let forwardedDependencies = instantiable.dependencies
			.filter { $0.source == .forwarded }
			.sorted { $0.property < $1.property }

		// Collect all declarations from the dependency tree.
		var allDeclarations = await collectMockDeclarations()

		// Find dependencies not covered by the tree.
		let coveredRootIdentifiers = Set(allDeclarations.map(\.identifier))
		// Identifiers of declarations needing root-level `let x = x()` bindings.
		// These are uncovered and received dependencies NOT handled by generatePropertyCode.
		var rootBindingIdentifiers = Set<MockParameterIdentifier>()

		// Check this type's own dependencies for uncovered @Instantiated dependencies.
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case .instantiated:
				let dependencyType = dependency.property.typeDescription.asInstantiatedType
				let sourceType = dependency.property.propertyType.isConstant
					? dependencyType.asSource
					: dependency.property.typeDescription.asSource
				let dependencyIdentifier = MockParameterIdentifier(propertyLabel: dependency.property.label, sourceType: sourceType)
				guard !coveredRootIdentifiers.contains(dependencyIdentifier) else { continue }
				allDeclarations.append(MockDeclaration(
					propertyLabel: dependency.property.label,
					parameterLabel: dependency.property.label,
					sourceType: sourceType,
					isForwarded: false,
					requiresSendable: false,
					defaultValueExpression: nil,
					hasSubtree: false,
					defaultConstruction: nil,
					isClosureType: false,
				))
				rootBindingIdentifiers.insert(dependencyIdentifier)
			case .received, .aliased, .forwarded:
				break
			}
		}

		// Check transitive received dependencies not satisfied by the tree.
		let forwardedPropertySet = Set(forwardedDependencies.map(\.property))
		let updatedCoveredIdentifiers = Set(
			allDeclarations
				.filter { $0.defaultValueExpression == nil }
				.map(\.identifier),
		)
		let unwrappedOptionalCounterparts = Set(
			receivedProperties
				.filter(\.typeDescription.isOptional)
				.map(\.asUnwrappedProperty),
		)
		let receivedNonOptionalProperties = Set(
			receivedProperties
				.filter { !$0.typeDescription.isOptional },
		)
		for receivedProperty in receivedProperties.sorted() {
			guard !updatedCoveredIdentifiers.contains(MockParameterIdentifier(propertyLabel: receivedProperty.label, sourceType: receivedProperty.typeDescription.asSource)),
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

			// For onlyIfAvailable, ensure sourceType is Optional so the autoclosure returns T?.
			let receivedSourceType: String = if isOnlyIfAvailable, !receivedProperty.typeDescription.isOptional {
				"\(receivedProperty.typeDescription.asSource)?"
			} else {
				receivedProperty.typeDescription.asSource
			}

			allDeclarations.append(MockDeclaration(
				propertyLabel: receivedProperty.label,
				parameterLabel: receivedProperty.label,
				sourceType: receivedSourceType,
				isForwarded: false,
				requiresSendable: false,
				defaultValueExpression: nil,
				hasSubtree: false,
				defaultConstruction: isOnlyIfAvailable ? "nil" : nil,
				isClosureType: false,
			))
			rootBindingIdentifiers.insert(MockParameterIdentifier(propertyLabel: receivedProperty.label, sourceType: receivedSourceType))
		}

		// Add forwarded dependencies as bare parameter declarations.
		let forwardedDeclarations = forwardedDependencies.map { dependency in
			MockDeclaration(
				propertyLabel: dependency.property.label,
				parameterLabel: dependency.property.label,
				sourceType: dependency.property.typeDescription.asFunctionParameter.asSource,
				isForwarded: true,
				requiresSendable: false,
				defaultValueExpression: nil,
				hasSubtree: false,
				defaultConstruction: nil,
				isClosureType: false,
			)
		}

		// Collect the root type's own default-valued init parameters.
		var rootDefaultIdentifiers = Set<MockParameterIdentifier>()
		if let rootInitializer = instantiable.initializer {
			let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
			for argument in rootInitializer.arguments {
				guard argument.hasDefaultValue,
				      !dependencyLabels.contains(argument.innerLabel),
				      let defaultExpr = argument.defaultValueExpression
				else { continue }
				let strippedType = argument.typeDescription.strippingEscaping
				allDeclarations.append(MockDeclaration(
					propertyLabel: argument.innerLabel,
					parameterLabel: argument.innerLabel,
					sourceType: strippedType.asSource,
					isForwarded: false,
					requiresSendable: false,
					defaultValueExpression: defaultExpr,
					hasSubtree: false,
					defaultConstruction: defaultExpr,
					isClosureType: argument.typeDescription.strippingEscaping.isClosure,
				))
				rootDefaultIdentifiers.insert(allDeclarations[allDeclarations.count - 1].identifier)
			}
		}

		// If no declarations at all, generate simple mock.
		if allDeclarations.isEmpty, forwardedDeclarations.isEmpty {
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableOptionalProperties,
				forMockGeneration: true,
			)
			let construction = if instantiable.declarationType.isExtension {
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

		// Deduplicate declarations with same (parameterLabel, sourceType).
		var seenIdentifiers = Set<MockParameterIdentifier>()
		allDeclarations = allDeclarations.filter { declaration in
			seenIdentifiers.insert(declaration.identifier).inserted
		}

		// Disambiguate duplicate parameter labels.
		disambiguateParameterLabels(&allDeclarations, forwardedDeclarations: forwardedDeclarations)

		// Build parameterLabelMap for body bindings.
		var parameterLabelMap = [MockParameterIdentifier: String]()
		for declaration in allDeclarations {
			parameterLabelMap[declaration.identifier] = declaration.parameterLabel
		}

		// Build mock method parameters.
		let indent = Self.standardIndent
		var parameters = [String]()
		for declaration in forwardedDeclarations {
			parameters.append("\(indent)\(indent)\(declaration.parameterLabel): \(declaration.sourceType)")
		}
		for declaration in allDeclarations.sorted(by: { $0.parameterLabel < $1.parameterLabel }) {
			let sendablePrefix = declaration.requiresSendable ? "@Sendable " : ""
			if declaration.hasSubtree {
				parameters.append("\(indent)\(indent)\(declaration.parameterLabel): \(declaration.sourceType)? = nil")
			} else if declaration.isClosureType, let defaultExpr = declaration.defaultConstruction {
				// Closure-typed default: @escaping directly (no @autoclosure).
				parameters.append("\(indent)\(indent)\(declaration.parameterLabel): \(sendablePrefix)@escaping \(declaration.sourceType) = \(defaultExpr)")
			} else if let defaultExpr = declaration.defaultConstruction {
				parameters.append("\(indent)\(indent)\(declaration.parameterLabel): \(sendablePrefix)@autoclosure @escaping () -> \(declaration.sourceType) = \(defaultExpr)")
			} else {
				// Required autoclosure (uncovered dependency).
				parameters.append("\(indent)\(indent)\(declaration.parameterLabel): \(sendablePrefix)@autoclosure @escaping () -> \(declaration.sourceType)")
			}
		}
		let parametersString = parameters.joined(separator: ",\n")

		// Build the mock method body.
		let bodyIndent = "\(indent)\(indent)"

		let subtreeParameters = Set(
			allDeclarations
				.filter(\.hasSubtree)
				.map(\.identifier),
		)
		let forwardedLabels = Set(forwardedDeclarations.map(\.propertyLabel))
		var resolvedParameters = Set<MockParameterIdentifier>()
		for declaration in allDeclarations {
			if rootBindingIdentifiers.contains(declaration.identifier) {
				resolvedParameters.insert(declaration.identifier)
			} else if rootDefaultIdentifiers.contains(declaration.identifier),
			          !forwardedLabels.contains(declaration.propertyLabel),
			          !declaration.isClosureType
			{
				// Root default-valued params bound at root scope.
				resolvedParameters.insert(declaration.identifier)
			}
		}
		let bodyContext = MockContext(
			mockConditionalCompilation: context.mockConditionalCompilation,
			parameterLabelMap: parameterLabelMap,
			subtreeParameters: subtreeParameters,
			resolvedParameters: resolvedParameters,
		)
		let propertyLines = try await generateProperties(
			codeGeneration: .mock(bodyContext),
			leadingMemberWhitespace: bodyIndent,
		)

		// Build the return statement.
		let argumentList = try instantiable.generateArgumentList(
			unavailableProperties: unavailableOptionalProperties,
			forMockGeneration: true,
		)
		let construction = if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}

		var lines = [String]()
		lines.append("extension \(typeName) {")
		lines.append("\(indent)\(mockAttributesPrefix)public static func mock(")
		lines.append(parametersString)
		lines.append("\(indent)) -> \(typeName) {")
		// Bindings for uncovered and received dependencies (must come before child constructions).
		for declaration in allDeclarations {
			guard rootBindingIdentifiers.contains(declaration.identifier) else { continue }
			lines.append("\(bodyIndent)let \(declaration.propertyLabel) = \(declaration.parameterLabel)()")
		}
		// Bindings for root default-valued init params.
		// Skip labels matching forwarded params — forwarded values take precedence.
		for declaration in allDeclarations where declaration.defaultValueExpression != nil {
			guard rootDefaultIdentifiers.contains(declaration.identifier),
			      !rootBindingIdentifiers.contains(declaration.identifier),
			      !forwardedLabels.contains(declaration.propertyLabel),
			      !declaration.isClosureType
			else { continue }
			lines.append("\(bodyIndent)let \(declaration.propertyLabel) = \(declaration.parameterLabel)()")
		}
		lines.append(contentsOf: propertyLines)
		lines.append("\(bodyIndent)return \(construction)")
		lines.append("\(indent)}")
		lines.append("}")

		let code = lines.joined(separator: "\n")
		return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
	}

	/// Identifies a mock parameter by its property label and source type.
	/// Used to track disambiguation, subtree status, and root-bound state
	/// across different phases of mock code generation.
	struct MockParameterIdentifier: Hashable {
		/// The property label from the initializer (e.g., "service").
		let propertyLabel: String
		/// The mock parameter's type as it appears in the signature (e.g., "ExternalService").
		/// Two parameters with the same label but different source types are distinct.
		let sourceType: String
	}

	/// A mock declaration collected from the tree.
	private struct MockDeclaration {
		/// The original property label from the init (before disambiguation).
		let propertyLabel: String
		/// The parameter label used in the mock() signature (may be disambiguated).
		var parameterLabel: String
		let sourceType: String
		let isForwarded: Bool
		/// Whether this parameter is captured by a @Sendable function and must be @Sendable.
		var requiresSendable: Bool
		/// The default value expression for a default-valued init parameter (e.g., `"nil"`, `".init()"`).
		/// When set, this declaration represents a bubbled-up default-valued parameter, not a tree child.
		let defaultValueExpression: String?
		/// Whether this declaration represents a tree child that needs inline construction
		/// (has subtree, uncovered dependencies, or default-valued params). Uses `T? = nil` parameter style.
		let hasSubtree: Bool
		/// The default construction expression for `@autoclosure` parameters (e.g., `"T()"`, `"T.mock()"`).
		/// nil for subtree children (which use `T? = nil` instead) and forwarded params.
		let defaultConstruction: String?
		/// The identifier for this declaration, combining label and type.
		var identifier: MockParameterIdentifier {
			MockParameterIdentifier(propertyLabel: propertyLabel, sourceType: sourceType)
		}

		/// Whether the source type is a closure/function type. Closure-typed defaults use
		/// `@escaping T = default` instead of `@autoclosure @escaping () -> T = default`.
		let isClosureType: Bool
	}

	/// Walks the tree and collects all mock declarations for the mock() parameters.
	private func collectMockDeclarations(
		insideSendableScope: Bool = false,
	) async -> [MockDeclaration] {
		var declarations = [MockDeclaration]()

		for childGenerator in orderedPropertiesToGenerate {
			guard let childProperty = childGenerator.property,
			      let childInstantiable = childGenerator.scopeData.instantiable
			else { continue }

			let isInstantiator = !childProperty.propertyType.isConstant
			let childInsideSendable = insideSendableScope || childProperty.propertyType.isSendable

			// Recurse into children first to determine subtree status.
			let childDeclarations = await childGenerator.collectMockDeclarations(
				insideSendableScope: childInsideSendable,
			)
			declarations.append(contentsOf: childDeclarations)

			let sourceType = isInstantiator
				? childProperty.typeDescription.asSource
				: childProperty.typeDescription.asInstantiatedType.asSource

			// Collect default-valued init parameters from constant children.
			// These bubble up to the root mock so users can override them.
			// Instantiator boundaries stop bubbling — those are user-provided closures.
			var childDefaultParams = [MockDeclaration]()
			if !isInstantiator {
				let constructionInitializer: Initializer? = if let mockInitializer = childInstantiable.mockInitializer {
					mockInitializer.arguments.isEmpty ? nil : mockInitializer
				} else {
					childInstantiable.initializer
				}
				if let constructionInitializer {
					let dependencyLabels = Set(childInstantiable.dependencies.map(\.property.label))
					for argument in constructionInitializer.arguments where argument.hasDefaultValue {
						guard !dependencyLabels.contains(argument.innerLabel),
						      argument.defaultValueExpression != nil
						else { continue }
						let strippedType = argument.typeDescription.strippingEscaping
						childDefaultParams.append(MockDeclaration(
							propertyLabel: argument.innerLabel,
							parameterLabel: argument.innerLabel,
							sourceType: strippedType.asSource,
							isForwarded: false,
							requiresSendable: insideSendableScope,
							defaultValueExpression: argument.defaultValueExpression,
							hasSubtree: false,
							defaultConstruction: argument.defaultValueExpression,
							isClosureType: argument.typeDescription.strippingEscaping.isClosure,
						))
					}
				}
			}
			declarations.append(contentsOf: childDefaultParams)

			// Check for @Instantiated dependencies that have no tree child.
			var childUncoveredDependencies = [MockDeclaration]()
			if !isInstantiator {
				let coveredChildIdentifiers = Set(childDeclarations.map(\.identifier))
				for dependency in childInstantiable.dependencies {
					let dependencyIdentifier = MockParameterIdentifier(
						propertyLabel: dependency.property.label,
						sourceType: dependency.property.typeDescription.asInstantiatedType.asSource,
					)
					guard case .instantiated = dependency.source,
					      !coveredChildIdentifiers.contains(dependencyIdentifier),
					      dependency.property.propertyType.isConstant
					else { continue }
					let dependencyType = dependency.property.typeDescription.asInstantiatedType
					childUncoveredDependencies.append(MockDeclaration(
						propertyLabel: dependency.property.label,
						parameterLabel: dependency.property.label,
						sourceType: dependencyType.asSource,
						isForwarded: false,
						requiresSendable: childInsideSendable,
						defaultValueExpression: nil,
						hasSubtree: false,
						defaultConstruction: nil,
						isClosureType: false,
					))
				}
			}
			declarations.append(contentsOf: childUncoveredDependencies)

			// Determine if child needs inline construction (subtree pattern: T? = nil)
			// or can use a simple @autoclosure default.
			let needsInlineConstruction: Bool = if isInstantiator {
				true
			} else if let mockInitializer = childInstantiable.mockInitializer, !mockInitializer.arguments.isEmpty {
				true
			} else {
				!childDeclarations.isEmpty
					|| !childDefaultParams.isEmpty
					|| !childUncoveredDependencies.isEmpty
					|| !childInstantiable.dependencies.isEmpty
			}

			// Compute the default construction expression for leaf types.
			let defaultConstruction: String? = if needsInlineConstruction {
				nil
			} else if let mockInitializer = childInstantiable.mockInitializer, mockInitializer.arguments.isEmpty {
				"\(childInstantiable.concreteInstantiable.asSource).mock()"
			} else if childInstantiable.declarationType.isExtension {
				"\(childInstantiable.concreteInstantiable.asSource).\(InstantiableVisitor.instantiateMethodName)()"
			} else {
				"\(childInstantiable.concreteInstantiable.asSource)()"
			}

			declarations.append(MockDeclaration(
				propertyLabel: childProperty.label,
				parameterLabel: childProperty.label,
				sourceType: sourceType,
				isForwarded: false,
				requiresSendable: insideSendableScope,
				defaultValueExpression: nil,
				hasSubtree: needsInlineConstruction,
				defaultConstruction: defaultConstruction,
				isClosureType: false,
			))
		}

		return declarations
	}

	private func disambiguateParameterLabels(
		_ declarations: inout [MockDeclaration],
		forwardedDeclarations: [MockDeclaration] = [],
	) {
		// Count ALL labels (including forwarded) to detect collisions.
		// Only non-forwarded are renamed — forwarded must match the init signature.
		var labelCounts = [String: Int]()
		for declaration in declarations {
			labelCounts[declaration.parameterLabel, default: 0] += 1
		}
		for declaration in forwardedDeclarations {
			labelCounts[declaration.parameterLabel, default: 0] += 1
		}
		declarations = declarations.map { declaration in
			guard !declaration.isForwarded,
			      let count = labelCounts[declaration.parameterLabel],
			      count > 1
			else { return declaration }
			let suffix = Self.sanitizeForIdentifier(declaration.sourceType)
			return MockDeclaration(
				propertyLabel: declaration.propertyLabel,
				parameterLabel: "\(declaration.parameterLabel)_\(suffix)",
				sourceType: declaration.sourceType,
				isForwarded: declaration.isForwarded,
				requiresSendable: declaration.requiresSendable,
				defaultValueExpression: declaration.defaultValueExpression,
				hasSubtree: declaration.hasSubtree,
				defaultConstruction: declaration.defaultConstruction,
				isClosureType: false,
			)
		}
	}

	/// Generates `let` bindings for default-valued init parameters of an instantiable.
	/// Each binding evaluates the corresponding `@autoclosure` parameter.
	private static func defaultValueBindings(
		for instantiable: Instantiable,
		parameterLabelMap: [MockParameterIdentifier: String],
		resolvedParameters: Set<MockParameterIdentifier>,
	) -> [String] {
		// Collect non-dependency default-valued params from the construction initializer.
		// When a user-defined mock() exists, use its params (nil for no-arg mocks).
		// When no mock exists, use the regular init.
		// The dependencyLabels guard below ensures SafeDI dependencies
		// (even those with defaults) are never bubbled as default params.
		let constructionInitializer: Initializer? = if let mockInitializer = instantiable.mockInitializer {
			mockInitializer.arguments.isEmpty ? nil : mockInitializer
		} else {
			instantiable.initializer
		}
		guard let constructionInitializer else { return [] }
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))

		var bindings = [String]()
		for argument in constructionInitializer.arguments {
			guard argument.hasDefaultValue,
			      !dependencyLabels.contains(argument.innerLabel),
			      argument.defaultValueExpression != nil,
			      !argument.typeDescription.strippingEscaping.isClosure
			else { continue }
			let strippedType = argument.typeDescription.strippingEscaping
			let identifier = MockParameterIdentifier(propertyLabel: argument.innerLabel, sourceType: strippedType.asSource)
			guard !resolvedParameters.contains(identifier) else { continue }
			let parameterLabel = parameterLabelMap[identifier] ?? argument.innerLabel
			bindings.append("let \(argument.innerLabel) = \(parameterLabel)()")
		}
		return bindings
	}

	/// Generates `let` bindings for @Instantiated dependencies that have no tree child
	/// (e.g., type from a parallel dependency tree not in the scope map).
	/// These are required mock parameters that need to be evaluated before
	/// passing to the init or .mock() call.
	private static func uncoveredDependencyBindings(
		for instantiable: Instantiable,
		declaredProperties: Set<Property>,
		parameterLabelMap: [MockParameterIdentifier: String],
		resolvedParameters: Set<MockParameterIdentifier>,
	) -> [String] {
		var bindings = [String]()
		for dependency in instantiable.dependencies {
			guard case .instantiated = dependency.source,
			      !declaredProperties.contains(dependency.property),
			      dependency.property.propertyType.isConstant
			else { continue }
			let dependencyType = dependency.property.typeDescription.asInstantiatedType
			let identifier = MockParameterIdentifier(propertyLabel: dependency.property.label, sourceType: dependencyType.asSource)
			guard !resolvedParameters.contains(identifier) else { continue }
			let parameterLabel = parameterLabelMap[identifier] ?? dependency.property.label
			bindings.append("let \(dependency.property.label) = \(parameterLabel)()")
		}
		return bindings
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

	static func sanitizeForIdentifier(_ typeName: String) -> String {
		typeName
			// Replace empty argument list before parens are stripped.
			.replacingOccurrences(of: "()", with: "Void")
			// Arrow before angle bracket close — `>` in `->` must not be stripped first.
			.replacingOccurrences(of: "->", with: "_to_")
			.replacingOccurrences(of: "<", with: "__")
			.replacingOccurrences(of: ">", with: "")
			.replacingOccurrences(of: ", ", with: "_")
			.replacingOccurrences(of: ",", with: "_")
			.replacingOccurrences(of: ".", with: "_")
			.replacingOccurrences(of: "[", with: "Array_")
			.replacingOccurrences(of: "]", with: "")
			.replacingOccurrences(of: ":", with: "_")
			.replacingOccurrences(of: "(", with: "")
			.replacingOccurrences(of: ")", with: "")
			.replacingOccurrences(of: "&", with: "_and_")
			.replacingOccurrences(of: "?", with: "_Optional")
			.replacingOccurrences(of: "@", with: "")
			.replacingOccurrences(of: " ", with: "")
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
	) throws -> String {
		let initializerToUse: Initializer? = if forMockGeneration, let mockInitializer {
			// User-defined mock handles construction — use its parameter list
			// (may be empty for no-arg mock methods).
			mockInitializer
		} else {
			initializer
		}
		if forMockGeneration {
			guard let initializerToUse else {
				return Self.incorrectlyConfiguredComment
			}
			// When using a user-defined mock(), validate it covers all dependencies.
			// If not, emit a comment that triggers a build error directing the user
			// to the @Instantiable macro fix-it (same pattern as production code gen).
			if mockInitializer != nil, !initializerToUse.isValid(forFulfilling: dependencies) {
				return Self.incorrectlyConfiguredComment
			}
			return try initializerToUse
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
