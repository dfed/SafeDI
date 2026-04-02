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

	/// The instantiable associated with this scope, if any (nil for aliases).
	var instantiable: Instantiable? {
		scopeData.instantiable
	}

	/// Creates a mock-root version of this scope generator and generates mock code for it.
	func generateMockCodeAsMockRoot(
		mockConditionalCompilation: String?,
	) async throws -> String {
		try await asMockRoot.generateCode(
			codeGeneration: .mock(MockContext(
				path: [],
				mockConditionalCompilation: mockConditionalCompilation,
			)),
		)
	}

	/// Collects all descendant ScopeGenerators (non-alias) in the tree.
	func collectAllDescendants() async -> [ScopeGenerator] {
		var result = [ScopeGenerator]()
		for child in propertiesToGenerate {
			if await child.scopeData.instantiable != nil {
				result.append(child)
				result.append(contentsOf: await child.collectAllDescendants())
			}
		}
		return result
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
			case let .root(instantiable):
				instantiable
			case let .property(instantiable, _, _, _, _):
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
	/// Properties that we require in order to satisfy our (and our children’s) dependencies.
	private let receivedProperties: Set<Property>
	/// Unwrapped versions of received properties from transitive `@Received(onlyIfAvailable: true)` dependencies.
	private let onlyIfAvailableUnwrappedReceivedProperties: Set<Property>
	/// Received properties that are optional and not created by a parent.
	private let unavailableOptionalProperties: Set<Property>
	/// Properties that will be generated as `let` constants.
	private let propertiesToGenerate: [ScopeGenerator]
	/// Properties that this scope declares as a `let` constant.
	private let propertiesToDeclare: Set<Property>
	private let property: Property?

	private var unavailablePropertiesToGenerateCodeTask = [Set<Property>: Task<String, Error>]()

	/// Creates a mock-root ScopeGenerator that reuses the existing children.
	/// Mock roots have no received properties — all dependencies become mock parameters.
	private var asMockRoot: ScopeGenerator {
		guard let instantiable = scopeData.instantiable else {
			fatalError("asMockRoot called on .alias ScopeGenerator")
		}
		return ScopeGenerator(
			instantiable: instantiable,
			property: nil,
			propertiesToGenerate: propertiesToGenerate,
			unavailableOptionalProperties: unavailableOptionalProperties,
			erasedToConcreteExistential: false,
			isPropertyCycle: false,
		)
	}

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
			let childCodeGeneration: CodeGeneration
			switch codeGeneration {
			case .dependencyTree:
				childCodeGeneration = .dependencyTree
			case let .mock(context):
				childCodeGeneration = await childMockCodeGeneration(
					for: childGenerator,
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

				// Mock mode: wrap the binding with an override closure.
				switch codeGeneration {
				case .dependencyTree:
					return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
				case let .mock(context):
					let pathCaseName = context.path.isEmpty ? "root" : context.path.joined(separator: "_")
					let derivedPropertyLabel = context.overrideParameterLabel ?? property.label
					return "\(functionDeclaration)\(propertyDeclaration) = \(derivedPropertyLabel)?(.\(pathCaseName)) ?? \(initializer)\n"
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

		// Collect received dependencies — these become closure-wrapped parameters with path case "parent".
		// onlyIfAvailable deps are included so users can optionally provide them in mocks.
		let receivedDependencies: [(property: Property, onlyIfAvailable: Bool)] = instantiable.dependencies
			.compactMap { dependency in
				switch dependency.source {
				case let .received(onlyIfAvailable):
					return (property: dependency.property, onlyIfAvailable: onlyIfAvailable)
				case let .aliased(_, _, onlyIfAvailable):
					return (property: dependency.property, onlyIfAvailable: onlyIfAvailable)
				case .instantiated, .forwarded:
					return nil
				}
			}

		// Collect all declarations from the instantiated dependency tree.
		var allDeclarations = await collectMockDeclarations(path: [])

		// Add received deps as declarations with path case "parent".
		for received in receivedDependencies {
			let depType = received.property.typeDescription.asInstantiatedType
			let depTypeName = depType.asSource
			let sanitizedName = Self.sanitizeForIdentifier(depTypeName)
			allDeclarations.append(MockDeclaration(
				enumName: sanitizedName,
				propertyLabel: received.property.label,
				parameterLabel: received.property.label,
				sourceType: received.property.typeDescription.asSource,
				hasKnownMock: true,
				pathCaseName: "parent",
				isForwarded: false,
			))
		}

		// Add forwarded deps as bare parameter declarations.
		let forwardedDeclarations = forwardedDependencies.map { dependency in
			MockDeclaration(
				enumName: dependency.property.label,
				propertyLabel: dependency.property.label,
				parameterLabel: dependency.property.label,
				sourceType: dependency.property.typeDescription.asSource,
				hasKnownMock: false,
				pathCaseName: "",
				isForwarded: true,
			)
		}

		// If no declarations at all, generate simple mock.
		if allDeclarations.isEmpty, forwardedDeclarations.isEmpty {
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableOptionalProperties,
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
			let casesStr = cases.map { "case \($0)" }.joined(separator: "; ")
			enumLines.append("\(indent)\(indent)public enum \(enumName) { \(casesStr) }")
		}
		enumLines.append("\(indent)}")

		// Build mock method parameters.
		var params = [String]()
		for declaration in forwardedDeclarations {
			params.append("\(indent)\(indent)\(declaration.parameterLabel): \(declaration.sourceType)")
		}
		for (enumName, declarations) in enumNameToDeclarations.sorted(by: { $0.key < $1.key }) {
			let firstDecl = declarations[0]
			if firstDecl.hasKnownMock {
				params.append("\(indent)\(indent)\(firstDecl.parameterLabel): ((SafeDIMockPath.\(enumName)) -> \(firstDecl.sourceType))? = nil")
			} else {
				params.append("\(indent)\(indent)\(firstDecl.parameterLabel): @escaping (SafeDIMockPath.\(enumName)) -> \(firstDecl.sourceType)")
			}
		}
		let paramsStr = params.joined(separator: ",\n")

		// Build the mock method body.
		let bodyIndent = "\(indent)\(indent)"

		// Phase 1: Generate received dep bindings (not in propertiesToGenerate).
		var receivedBindingLines = [String]()
		for received in receivedDependencies {
			if received.onlyIfAvailable {
				// onlyIfAvailable: no default construction — nil if not provided.
				receivedBindingLines.append("\(bodyIndent)let \(received.property.label) = \(received.property.label)?(.parent)")
			} else {
				let depType = received.property.typeDescription.asInstantiatedType
				let defaultConstruction = depType.asSource + "()"
				receivedBindingLines.append("\(bodyIndent)let \(received.property.label) = \(received.property.label)?(.parent) ?? \(defaultConstruction)")
			}
		}

		// Phase 2: Generate instantiated dep bindings via recursive generateProperties.
		let bodyContext = MockContext(
			path: context.path,
			mockConditionalCompilation: context.mockConditionalCompilation,
			propertyToParameterLabel: propertyToParameterLabel,
		)
		let propertyLines = try await generateProperties(
			codeGeneration: .mock(bodyContext),
			leadingMemberWhitespace: bodyIndent,
		)

		// Build the return statement. Received deps that we generated bindings for are now
		// in scope, so remove them from the unavailable set.
		let receivedPropertySet = Set(receivedDependencies.map(\.property))
		let returnUnavailableProperties = unavailableOptionalProperties.subtracting(receivedPropertySet)
		let argumentList = try instantiable.generateArgumentList(
			unavailableProperties: returnUnavailableProperties,
		)
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
		lines.append(paramsStr)
		lines.append("\(indent)) -> \(typeName) {")
		lines.append(contentsOf: receivedBindingLines)
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
		let hasKnownMock: Bool
		let pathCaseName: String
		let isForwarded: Bool
	}

	/// Walks the tree and collects all mock declarations for the SafeDIMockPath enum and mock() parameters.
	private func collectMockDeclarations(
		path: [String],
	) async -> [MockDeclaration] {
		var declarations = [MockDeclaration]()

		for childGenerator in orderedPropertiesToGenerate {
			let childProperty = await childGenerator.property
			let childScopeData = await childGenerator.scopeData

			guard let childProperty else { continue }
			if case .alias = childScopeData { continue }

			let isInstantiator = !childProperty.propertyType.isConstant
			let pathCaseName = path.isEmpty ? "root" : path.joined(separator: "_")

			let enumName: String
			if isInstantiator {
				let label = childProperty.label
				enumName = String(label.prefix(1).uppercased()) + label.dropFirst()
			} else if let childInstantiable = childScopeData.instantiable {
				enumName = Self.sanitizeForIdentifier(childInstantiable.concreteInstantiable.asSource)
			} else {
				enumName = Self.sanitizeForIdentifier(childProperty.typeDescription.asInstantiatedType.asSource)
			}

			let sourceType = isInstantiator
				? childProperty.typeDescription.asSource
				: childProperty.typeDescription.asInstantiatedType.asSource

			declarations.append(MockDeclaration(
				enumName: enumName,
				propertyLabel: childProperty.label,
				parameterLabel: childProperty.label,
				sourceType: sourceType,
				hasKnownMock: childScopeData.instantiable != nil,
				pathCaseName: pathCaseName,
				isForwarded: false,
			))

			// Recurse into children.
			let childPath = path + [childProperty.label]
			let childDeclarations = await childGenerator.collectMockDeclarations(path: childPath)
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
				hasKnownMock: declaration.hasKnownMock,
				pathCaseName: declaration.pathCaseName,
				isForwarded: declaration.isForwarded,
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
				hasKnownMock: declaration.hasKnownMock,
				pathCaseName: declaration.pathCaseName,
				isForwarded: declaration.isForwarded,
			)
		}
	}

	/// Computes the child's mock context by extending the path and looking up disambiguated labels.
	private func childMockCodeGeneration(
		for childGenerator: ScopeGenerator,
		parentContext: MockContext,
	) async -> CodeGeneration {
		let childProperty = await childGenerator.property
		guard let childProperty else {
			return .mock(parentContext)
		}

		// Extend the path: children of this node use a path that includes
		// this node's property label (so grandchild pathCaseNames reflect their parent).
		let childPath = if let selfLabel = property?.label {
			parentContext.path + [selfLabel]
		} else {
			parentContext.path
		}

		// Look up the disambiguated parameter label for this child.
		let pathCaseName = childPath.isEmpty ? "root" : childPath.joined(separator: "_")
		let lookupKey = "\(pathCaseName)/\(childProperty.label)"
		let overrideLabel = parentContext.propertyToParameterLabel[lookupKey]

		return .mock(MockContext(
			path: childPath,
			mockConditionalCompilation: parentContext.mockConditionalCompilation,
			overrideParameterLabel: overrideLabel,
			propertyToParameterLabel: parentContext.propertyToParameterLabel,
		))
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
			.replacingOccurrences(of: "<", with: "__")
			.replacingOccurrences(of: ">", with: "")
			.replacingOccurrences(of: "->", with: "_to_")
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
	fileprivate func generateArgumentList(
		unavailableProperties: Set<Property>? = nil,
	) throws -> String {
		try initializer?
			.createInitializerArgumentList(
				given: dependencies,
				unavailableProperties: unavailableProperties,
			) ?? "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"
	}
}

// MARK: - Array Extension

extension Array where Element: Hashable {
	fileprivate func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
