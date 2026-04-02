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
		/// Accumulated path segments for SafeDIMockPath case names.
		let path: [String]
		/// The conditional compilation flag for wrapping mock output (e.g. "DEBUG").
		let mockConditionalCompilation: String?
		/// Override parameter label when disambiguated (differs from property.label).
		let overrideParameterLabel: String?
		/// Maps property labels to disambiguated mock parameter labels for all declarations.
		let propertyToParameterLabel: [String: String]

		init(
			path: [String],
			mockConditionalCompilation: String?,
			overrideParameterLabel: String? = nil,
			propertyToParameterLabel: [String: String] = [:],
		) {
			self.path = path
			self.mockConditionalCompilation = mockConditionalCompilation
			self.overrideParameterLabel = overrideParameterLabel
			self.propertyToParameterLabel = propertyToParameterLabel
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
		for (index, childGenerator) in orderedPropertiesToGenerate.enumerated() {
			let childCodeGeneration: CodeGeneration = switch codeGeneration {
			case .dependencyTree:
				.dependencyTree
			case let .mock(context):
				childMockCodeGeneration(
					forChildLabel: childGenerator.property?.label,
					parentContext: context,
				)
			}
			try await generatedProperties.append(
				childGenerator.generateCode(
					codeGeneration: childCodeGeneration,
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
					let pathCaseName = context.path.isEmpty ? "root" : context.path.joined(separator: "_")
					let derivedPropertyLabel = context.overrideParameterLabel ?? property.label
					return """
					\(functionDeclaration)\(propertyDeclaration) = \(derivedPropertyLabel)?(.\(pathCaseName)) ?? \(instantiatorInstantiation)
					"""
				}
			case .constant:
				let generatedProperties = try await generateProperties(
					codeGeneration: codeGeneration,
					leadingMemberWhitespace: Self.standardIndent,
				)

				// In mock mode, generate bindings for default-valued init parameters.
				// Each binding resolves the override closure or falls back to the default expression.
				// Wrapping in a function scopes the bindings to avoid name collisions between siblings.
				let defaultArgBindings: [String] = switch codeGeneration {
				case .dependencyTree:
					[]
				case let .mock(context):
					Self.defaultValueBindings(
						for: instantiable,
						path: context.path + [property.label],
						propertyToParameterLabel: context.propertyToParameterLabel,
					)
				}

				let hasGeneratedContent = !generatedProperties.isEmpty || !defaultArgBindings.isEmpty
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
				let allFunctionBodyLines = defaultArgBindings.map { "\(Self.standardIndent)\($0)" } + generatedProperties
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

				// Mock mode: wrap the binding with an override closure.
				// When erasedToConcreteExistential, wrap the default in the erased type
				// so the ?? operator has matching types on both sides.
				switch codeGeneration {
				case .dependencyTree:
					return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
				case let .mock(context):
					let pathCaseName = context.path.isEmpty ? "root" : context.path.joined(separator: "_")
					let derivedPropertyLabel = context.overrideParameterLabel ?? property.label
					let mockInitializer = if erasedToConcreteExistential, !generatedProperties.isEmpty {
						"\(property.typeDescription.asSource)(\(initializer))"
					} else {
						initializer
					}
					return "\(functionDeclaration)\(propertyDeclaration) = \(derivedPropertyLabel)?(.\(pathCaseName)) ?? \(mockInitializer)\n"
				}
			}
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
			// Aliases are identical in both modes.
			return if onlyIfAvailable, unavailableProperties.contains(fulfillingProperty) {
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
		// Received dependencies whose type is @Instantiable are in the tree.
		var allDeclarations = await collectMockDeclarations(path: [])

		// Find dependencies not covered by the tree. This includes:
		// - @Instantiated dependencies whose type is not in the scope map (e.g., defined
		//   in another module not visible to this module's mock generator)
		// - Received dependencies (including transitive) whose type is not constructible
		// These become mock parameters so the user can provide them.
		// Only root-level tree declarations suppress uncovered root dependencies.
		// Nested declarations (from children) may share a label with a root dependency
		// but refer to a different type — those must not suppress the root one.
		let coveredRootPropertyLabels = Set(
			allDeclarations
				.filter { $0.pathCaseName == "root" }
				.map(\.propertyLabel),
		)
		var uncoveredProperties = [(property: Property, isOnlyIfAvailable: Bool)]()

		// Check this type's own dependencies for uncovered @Instantiated dependencies.
		// This handles types that are @Instantiable in another module but not visible here.
		for dependency in instantiable.dependencies {
			guard !coveredRootPropertyLabels.contains(dependency.property.label) else { continue }
			switch dependency.source {
			case .instantiated:
				let dependencyType = dependency.property.typeDescription.asInstantiatedType
				let enumName = Self.sanitizeForIdentifier(dependencyType.asSource)
				let sourceType = dependency.property.propertyType.isConstant
					? dependencyType.asSource
					: dependency.property.typeDescription.asSource
				allDeclarations.append(MockDeclaration(
					enumName: enumName,
					propertyLabel: dependency.property.label,
					parameterLabel: dependency.property.label,
					sourceType: sourceType,
					isOptionalParameter: false,
					pathCaseName: "root",
					isForwarded: false,
					requiresSendable: false,
					defaultValueExpression: nil,
				))
				uncoveredProperties.append((property: dependency.property, isOnlyIfAvailable: false))
			case .received, .aliased, .forwarded:
				break
			}
		}

		// Check transitive received dependencies not satisfied by the tree.
		// Skip forwarded properties — they're bare mock parameters, not promoted children.
		let forwardedPropertySet = Set(forwardedDependencies.map(\.property))
		// Exclude default-valued parameter declarations from coverage — they are child-scoped
		// bindings that must not suppress root-level received property bindings.
		let updatedCoveredLabels = Set(allDeclarations.filter { $0.defaultValueExpression == nil }.map(\.propertyLabel))
		// Unwrapped forms of Optional received properties. Used to distinguish a required
		// non-optional property from an aliased onlyIfAvailable non-optional one.
		// Matching by unwrapped Property (label + type) avoids false collisions when
		// unrelated types share a label (e.g., `service: ConcreteService` aliased
		// onlyIfAvailable vs `service: ServiceProtocol?` Optional received).
		let unwrappedOptionalCounterparts = Set(
			receivedProperties
				.filter(\.typeDescription.isOptional)
				.map(\.asUnwrappedProperty),
		)
		// When both `user: User` (required) and `user: User?` (onlyIfAvailable) are received,
		// only the non-optional version should produce a parameter and binding.
		// The optional path uses the same value (Swift auto-wraps to Optional).
		let receivedLabelsWithNonOptionalVersion = Set(
			receivedProperties
				.filter { !$0.typeDescription.isOptional }
				.map(\.label),
		)
		for receivedProperty in receivedProperties.sorted() {
			guard !updatedCoveredLabels.contains(receivedProperty.label),
			      !forwardedPropertySet.contains(receivedProperty)
			else { continue }

			// Skip optional properties when a non-optional version with the same label exists.
			// The non-optional version subsumes it — Swift auto-wraps for optional paths.
			guard !receivedProperty.typeDescription.isOptional
				|| !receivedLabelsWithNonOptionalVersion.contains(receivedProperty.label)
			else { continue }

			// A property is onlyIfAvailable if:
			// (a) it's Optional and tracked as onlyIfAvailable (standard @Received case), OR
			// (b) it's non-optional, has no Optional counterpart with the same unwrapped type,
			//     and is tracked as onlyIfAvailable (aliased case where fulfilling type is
			//     non-optional). Matching by unwrapped Property identity (not just label)
			//     avoids false collisions when unrelated types share a label.
			let isOnlyIfAvailable = (receivedProperty.typeDescription.isOptional
				&& onlyIfAvailableUnwrappedReceivedProperties.contains(receivedProperty.asUnwrappedProperty))
				|| (!receivedProperty.typeDescription.isOptional
					&& !unwrappedOptionalCounterparts.contains(receivedProperty)
					&& onlyIfAvailableUnwrappedReceivedProperties.contains(receivedProperty))
				|| unavailableOptionalProperties.contains(receivedProperty)

			let receivedType = receivedProperty.typeDescription.asInstantiatedType
			let enumName = Self.sanitizeForIdentifier(receivedType.asSource)
			allDeclarations.append(MockDeclaration(
				enumName: enumName,
				propertyLabel: receivedProperty.label,
				parameterLabel: receivedProperty.label,
				sourceType: receivedProperty.typeDescription.asSource,
				isOptionalParameter: isOnlyIfAvailable,
				pathCaseName: "root",
				isForwarded: false,
				requiresSendable: false,
				defaultValueExpression: nil,
			))
			uncoveredProperties.append((property: receivedProperty, isOnlyIfAvailable: isOnlyIfAvailable))
		}

		// Add forwarded dependencies as bare parameter declarations.
		// Use asFunctionParameter to add @escaping for closure types.
		let forwardedDeclarations = forwardedDependencies.map { dependency in
			MockDeclaration(
				enumName: dependency.property.label,
				propertyLabel: dependency.property.label,
				parameterLabel: dependency.property.label,
				sourceType: dependency.property.typeDescription.asFunctionParameter.asSource,
				isOptionalParameter: false,
				pathCaseName: "",
				isForwarded: true,
				requiresSendable: false,
				defaultValueExpression: nil,
			)
		}

		// Collect the root type's own default-valued init parameters.
		// These are init arguments that have defaults and don't match any dependency.
		if let rootInitializer = instantiable.initializer {
			let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
			for argument in rootInitializer.arguments {
				guard argument.hasDefaultValue,
				      !dependencyLabels.contains(argument.innerLabel),
				      argument.defaultValueExpression != nil
				else { continue }
				let strippedType = argument.typeDescription.strippingEscaping
				let argEnumName = Self.sanitizeForIdentifier(strippedType.asInstantiatedType.asSource)
				allDeclarations.append(MockDeclaration(
					enumName: argEnumName,
					propertyLabel: argument.innerLabel,
					parameterLabel: argument.innerLabel,
					sourceType: strippedType.asSource,
					isOptionalParameter: true,
					pathCaseName: "root",
					isForwarded: false,
					requiresSendable: false,
					defaultValueExpression: argument.defaultValueExpression,
				))
			}
		}

		// If no declarations at all, generate simple mock.
		if allDeclarations.isEmpty, forwardedDeclarations.isEmpty {
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableOptionalProperties,
				forMockGeneration: true,
			)
			// Types with user-defined mock methods are skipped in generateMockCode,
			// so this path only handles types without mock initializers.
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

		// Disambiguate duplicate enum names and parameter labels.
		disambiguateEnumNames(&allDeclarations)
		disambiguateParameterLabels(&allDeclarations)

		// Build a mapping from (pathCaseName, propertyLabel) → disambiguated parameter label.
		// Only includes entries where disambiguation changed the label.
		// Keyed by "pathCaseName/propertyLabel" to handle same propertyLabel at different paths.
		var propertyToParameterLabel = [String: String]()
		for declaration in allDeclarations where !declaration.isForwarded {
			if declaration.parameterLabel != declaration.propertyLabel {
				let key = "\(declaration.pathCaseName)/\(declaration.propertyLabel)"
				propertyToParameterLabel[key] = declaration.parameterLabel
			}
		}

		// Deduplicate by enumName (same type at multiple paths → one enum with multiple cases).
		var enumNameToDeclarations = OrderedDictionary<String, [MockDeclaration]>()
		for declaration in allDeclarations where !declaration.isForwarded {
			enumNameToDeclarations[declaration.enumName, default: []].append(declaration)
		}

		// Build SafeDIMockPath enum.
		let indent = Self.standardIndent
		var enumLines = [String]()
		enumLines.append("\(indent)public enum SafeDIMockPath {")
		for (enumName, declarations) in enumNameToDeclarations.sorted(by: { $0.key < $1.key }) {
			let cases = declarations.map(\.pathCaseName).uniqued()
			let casesString = cases.map { "case \($0)" }.joined(separator: "; ")
			enumLines.append("\(indent)\(indent)public enum \(enumName) { \(casesString) }")
		}
		enumLines.append("\(indent)}")

		// Build mock method parameters.
		var parameters = [String]()
		for declaration in forwardedDeclarations {
			parameters.append("\(indent)\(indent)\(declaration.parameterLabel): \(declaration.sourceType)")
		}
		for (enumName, declarations) in enumNameToDeclarations.sorted(by: { $0.key < $1.key }) {
			let sendablePrefix = declarations.contains(where: \.requiresSendable) ? "@Sendable " : ""
			// Multiple declarations may share the same enum type but have different parameter labels
			// (e.g., installScopedDefaultsService and userScopedDefaultsService both typed UserDefaultsService).
			// Each unique parameter label gets its own mock parameter.
			var seenParameterLabels = Set<String>()
			for declaration in declarations.sorted(by: { $0.parameterLabel < $1.parameterLabel }) {
				guard seenParameterLabels.insert(declaration.parameterLabel).inserted else { continue }
				if declaration.isOptionalParameter {
					parameters.append("\(indent)\(indent)\(declaration.parameterLabel): (\(sendablePrefix)(SafeDIMockPath.\(enumName)) -> \(declaration.sourceType))? = nil")
				} else {
					parameters.append("\(indent)\(indent)\(declaration.parameterLabel): \(sendablePrefix)@escaping (SafeDIMockPath.\(enumName)) -> \(declaration.sourceType)")
				}
			}
		}
		let parametersString = parameters.joined(separator: ",\n")

		// Build the mock method body.
		let bodyIndent = "\(indent)\(indent)"

		// Generate all dependency bindings via recursive generateProperties.
		// Received dependencies are in the tree (built by createMockRootScopeGenerator).
		let bodyContext = MockContext(
			path: context.path,
			mockConditionalCompilation: context.mockConditionalCompilation,
			propertyToParameterLabel: propertyToParameterLabel,
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
		// Types with user-defined mock methods are skipped in generateMockCode,
		// so this path only handles types without mock initializers.
		let construction = if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}

		var lines = [String]()
		lines.append("extension \(typeName) {")
		lines.append(contentsOf: enumLines)
		lines.append("")
		lines.append("\(indent)\(mockAttributesPrefix)public static func mock(")
		lines.append(parametersString)
		lines.append("\(indent)) -> \(typeName) {")
		// Bindings for uncovered dependencies.
		// Use the disambiguated parameter name when the label was changed by disambiguation.
		for uncovered in uncoveredProperties {
			let parameterName = propertyToParameterLabel["root/\(uncovered.property.label)"] ?? uncovered.property.label
			if uncovered.isOnlyIfAvailable {
				// Optional: evaluates to nil if not provided by the user.
				lines.append("\(bodyIndent)let \(uncovered.property.label) = \(parameterName)?(.root)")
			} else {
				// Required: user must provide the closure.
				lines.append("\(bodyIndent)let \(uncovered.property.label) = \(parameterName)(.root)")
			}
		}
		// Bindings for root's own default-valued init parameters.
		// Uses `if let ... else` instead of `??` so that closure literals in the else branch
		// inherit the correct type context (@MainActor, @Sendable, etc.) from the binding.
		for declaration in allDeclarations {
			guard let defaultExpr = declaration.defaultValueExpression,
			      declaration.pathCaseName == "root"
			else { continue }
			let parameterName = propertyToParameterLabel["root/\(declaration.propertyLabel)"] ?? declaration.parameterLabel
			lines.append("\(bodyIndent)let \(declaration.propertyLabel): \(declaration.sourceType) = if let \(declaration.propertyLabel) = \(parameterName)?(.root) { \(declaration.propertyLabel) } else { \(defaultExpr) }")
		}
		lines.append(contentsOf: propertyLines)
		lines.append("\(bodyIndent)return \(construction)")
		lines.append("\(indent)}")
		lines.append("}")

		let code = lines.joined(separator: "\n")
		return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
	}

	/// A mock declaration collected from the tree.
	private struct MockDeclaration {
		let enumName: String
		/// The original property label from the init (before disambiguation).
		let propertyLabel: String
		/// The parameter label used in the mock() signature (may be disambiguated).
		var parameterLabel: String
		let sourceType: String
		/// Whether this parameter is optional (`= nil`) in the mock signature.
		/// True when the dependency is covered by the tree (has a default inline construction)
		/// or is onlyIfAvailable.
		/// False when the type is not constructible and must be provided by the caller.
		let isOptionalParameter: Bool
		let pathCaseName: String
		let isForwarded: Bool
		/// Whether this parameter is captured by a @Sendable function and must be @Sendable.
		var requiresSendable: Bool
		/// The default value expression for a default-valued init parameter (e.g., `"nil"`, `".init()"`).
		/// When set, this declaration represents a bubbled-up default-valued parameter, not a tree child.
		let defaultValueExpression: String?
	}

	/// Walks the tree and collects all mock declarations for the SafeDIMockPath enum and mock() parameters.
	private func collectMockDeclarations(
		path: [String],
		insideSendableScope: Bool = false,
	) async -> [MockDeclaration] {
		var declarations = [MockDeclaration]()

		for childGenerator in orderedPropertiesToGenerate {
			guard let childProperty = childGenerator.property,
			      childGenerator.scopeData.instantiable != nil
			else { continue }
			let childScopeData = childGenerator.scopeData

			let isInstantiator = !childProperty.propertyType.isConstant
			let pathCaseName = path.isEmpty ? "root" : path.joined(separator: "_")

			let enumName: String
			if isInstantiator {
				let label = childProperty.label
				enumName = String(label.prefix(1).uppercased()) + label.dropFirst()
			} else {
				// The `.instantiable != nil` guard above filters out aliases (which have no instantiable).
				let childInstantiable = childScopeData.instantiable!
				enumName = Self.sanitizeForIdentifier(childInstantiable.concreteInstantiable.asSource)
			}

			let sourceType = isInstantiator
				? childProperty.typeDescription.asSource
				: childProperty.typeDescription.asInstantiatedType.asSource

			declarations.append(MockDeclaration(
				enumName: enumName,
				propertyLabel: childProperty.label,
				parameterLabel: childProperty.label,
				sourceType: sourceType,
				isOptionalParameter: childScopeData.instantiable != nil,
				pathCaseName: pathCaseName,
				isForwarded: false,
				requiresSendable: insideSendableScope,
				defaultValueExpression: nil,
			))

			// Collect default-valued init parameters from constant children.
			// These bubble up to the root mock so users can override them.
			// Instantiator boundaries stop bubbling — those are user-provided closures.
			// Types with user-defined mock() methods stop bubbling — the mock handles construction.
			let childPath = path + [childProperty.label]
			if !isInstantiator, let childInstantiable = childScopeData.instantiable {
				let constructionInitializer: Initializer? = if let mockInit = childInstantiable.mockInitializer {
					// User-defined mock handles construction — only bubble args from mock method.
					// No-arg mocks produce nil here, stopping default-valued arg collection.
					mockInit.arguments.isEmpty ? nil : mockInit
				} else {
					childInstantiable.initializer
				}
				if let constructionInitializer {
					let dependencyLabels = Set(childInstantiable.dependencies.map(\.property.label))
					let childPathCaseName = childPath.joined(separator: "_")
					for argument in constructionInitializer.arguments where argument.hasDefaultValue {
						guard !dependencyLabels.contains(argument.innerLabel) else { continue }
						let strippedType = argument.typeDescription.strippingEscaping
						let argEnumName = Self.sanitizeForIdentifier(strippedType.asInstantiatedType.asSource)
						declarations.append(MockDeclaration(
							enumName: argEnumName,
							propertyLabel: argument.innerLabel,
							parameterLabel: argument.innerLabel,
							sourceType: strippedType.asSource,
							isOptionalParameter: true,
							pathCaseName: childPathCaseName,
							isForwarded: false,
							requiresSendable: insideSendableScope,
							defaultValueExpression: argument.defaultValueExpression,
						))
					}
				}
			}

			// Recurse into children. If this child is a Sendable instantiator,
			// everything inside its scope is captured by a @Sendable function.
			let childInsideSendable = insideSendableScope || childProperty.propertyType.isSendable
			let childDeclarations = await childGenerator.collectMockDeclarations(
				path: childPath,
				insideSendableScope: childInsideSendable,
			)
			declarations.append(contentsOf: childDeclarations)
		}

		return declarations
	}

	private func disambiguateEnumNames(_ declarations: inout [MockDeclaration]) {
		var enumNameCounts = [String: Int]()
		for declaration in declarations where !declaration.isForwarded {
			enumNameCounts[declaration.enumName, default: 0] += 1
		}
		declarations = declarations.map { declaration in
			guard !declaration.isForwarded,
			      let count = enumNameCounts[declaration.enumName],
			      count > 1
			else { return declaration }
			let suffix = Self.sanitizeForIdentifier(declaration.sourceType)
			return MockDeclaration(
				enumName: "\(declaration.enumName)_\(suffix)",
				propertyLabel: declaration.propertyLabel,
				parameterLabel: declaration.parameterLabel,
				sourceType: declaration.sourceType,
				isOptionalParameter: declaration.isOptionalParameter,
				pathCaseName: declaration.pathCaseName,
				isForwarded: declaration.isForwarded,
				requiresSendable: declaration.requiresSendable,
				defaultValueExpression: declaration.defaultValueExpression,
			)
		}
	}

	private func disambiguateParameterLabels(_ declarations: inout [MockDeclaration]) {
		var labelCounts = [String: Int]()
		for declaration in declarations where !declaration.isForwarded {
			labelCounts[declaration.parameterLabel, default: 0] += 1
		}
		declarations = declarations.map { declaration in
			guard !declaration.isForwarded,
			      let count = labelCounts[declaration.parameterLabel],
			      count > 1
			else { return declaration }
			return MockDeclaration(
				enumName: declaration.enumName,
				propertyLabel: declaration.propertyLabel,
				parameterLabel: "\(declaration.parameterLabel)_\(declaration.enumName)",
				sourceType: declaration.sourceType,
				isOptionalParameter: declaration.isOptionalParameter,
				pathCaseName: declaration.pathCaseName,
				isForwarded: declaration.isForwarded,
				requiresSendable: declaration.requiresSendable,
				defaultValueExpression: declaration.defaultValueExpression,
			)
		}
	}

	/// Computes the child's mock context by extending the path and looking up disambiguated labels.
	private func childMockCodeGeneration(
		forChildLabel childLabel: String?,
		parentContext: MockContext,
	) -> CodeGeneration {
		// Extend the path: children of this node use a path that includes
		// this node's property label (so grandchild pathCaseNames reflect their parent).
		let childPath = if let selfLabel = property?.label {
			parentContext.path + [selfLabel]
		} else {
			parentContext.path
		}

		// Look up the disambiguated parameter label for this child.
		let overrideLabel: String? = childLabel.flatMap { label in
			let pathCaseName = childPath.isEmpty ? "root" : childPath.joined(separator: "_")
			return parentContext.propertyToParameterLabel["\(pathCaseName)/\(label)"]
		}

		return .mock(MockContext(
			path: childPath,
			mockConditionalCompilation: parentContext.mockConditionalCompilation,
			overrideParameterLabel: overrideLabel,
			propertyToParameterLabel: parentContext.propertyToParameterLabel,
		))
	}

	/// Generates `let` bindings for default-valued init parameters of an instantiable.
	/// Each binding resolves the mock override closure or falls back to the original default.
	/// - Parameters:
	///   - instantiable: The type whose initializer may have default-valued parameters.
	///   - path: The mock path for this type in the tree (used to compute pathCaseName).
	///   - propertyToParameterLabel: Disambiguation map from `generateMockRootCode`.
	/// - Returns: An array of binding lines (e.g., `"let flag = flag?(.child) ?? false"`).
	private static func defaultValueBindings(
		for instantiable: Instantiable,
		path: [String],
		propertyToParameterLabel: [String: String],
	) -> [String] {
		let constructionInitializer: Initializer? = if let mockInit = instantiable.mockInitializer {
			// User-defined mock handles construction — only bubble args from mock method.
			// No-arg mocks produce nil here, stopping default-valued arg collection.
			mockInit.arguments.isEmpty ? nil : mockInit
		} else {
			instantiable.initializer
		}
		guard let constructionInitializer else { return [] }
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
		let pathCaseName = path.joined(separator: "_")
		guard !pathCaseName.isEmpty else { return [] }

		var bindings = [String]()
		for argument in constructionInitializer.arguments {
			guard argument.hasDefaultValue,
			      !dependencyLabels.contains(argument.innerLabel),
			      let defaultExpr = argument.defaultValueExpression
			else { continue }
			let parameterLabel = propertyToParameterLabel["\(pathCaseName)/\(argument.innerLabel)"] ?? argument.innerLabel
			let typeAnnotation = argument.typeDescription.strippingEscaping.asSource
			bindings.append("let \(argument.innerLabel): \(typeAnnotation) = if let \(argument.innerLabel) = \(parameterLabel)?(.\(pathCaseName)) { \(argument.innerLabel) } else { \(defaultExpr) }")
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
		let initializerToUse: Initializer? = if forMockGeneration, let mockInit = mockInitializer {
			// User-defined mock handles construction — use its parameter list
			// (may be empty for no-arg mock methods).
			mockInit
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

// MARK: - Array Extension

extension Array where Element: Hashable {
	fileprivate func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
