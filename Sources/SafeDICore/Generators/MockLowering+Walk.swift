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

/// Stage D1's core walk: the mock of a root whose tree it lowers, from the root's finished generator and its children in
/// generation order. Each construct the walk does not lower yet returns the rule it belongs to, the first it meets deciding
/// the root's outcome.
extension ScopeGenerator {
	/// The mock of `instantiable`, the mocked type of this root, whose tree is its generator's children, or the first rule
	/// the walk meets that it does not lower yet.
	func lowerMockRootWithTree(of instantiable: Instantiable, context: MockContext) -> MockLowering.Result {
		// D1 lane hook: the mocked type's own parameters (forwarded, flat received, uncovered, defaults, hand-written mock).
		if let rule = Self.unsupportedRuleOfMockedType(instantiable) {
			return .unsupported(rule)
		}
		guard unavailableOptionalProperties.isEmpty, receivedOnlyByPublicMockCalls.isEmpty else {
			return .unsupported(.onlyIfAvailable)
		}
		var labels = Set<String>()
		let nodes: [MockLowering.TreeNode]
		switch MockLowering.ConstantNode.children(of: self, inScope: [], ancestorTypes: [instantiable.concreteInstantiable], labels: &labels) {
		case let .lowered(children):
			nodes = children
		case let .unsupported(rule):
			return .unsupported(rule)
		}
		// Every dependency of the mocked type is a node of its tree, so `mock()` takes nothing but the overrides.
		let nodeProperties = Set(nodes.map(\.property))
		guard instantiable.dependencies.allSatisfy({ nodeProperties.contains($0.property) }) else {
			return .unsupported(.flatParameter)
		}
		return .lowered(Self.mockWithTree(of: instantiable, nodes: nodes, context: context))
	}

	/// The first rule the parameters and construction of the mocked type itself meet that the walk does not lower yet.
	private static func unsupportedRuleOfMockedType(_ instantiable: Instantiable) -> MockLowering.Rule? {
		guard instantiable.mockInitializer == nil, instantiable.customMockName == nil, let initializer = instantiable.initializer else { return .handWrittenMock }
		guard !initializer.arguments.contains(where: \.hasDefaultValue) else { return .defaultValuedParameter }
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				guard fulfillingTypeDescription == nil && !erasedToConcreteExistential || dependency.property.propertyType.isConstant else { return .erasure }
				guard dependency.property.propertyType.isConstant || dependency.property.propertyType == .instantiator else { return .wrapper }
			case let .received(onlyIfAvailable):
				guard !onlyIfAvailable else { return .onlyIfAvailable }
				guard dependency.property.propertyType.isConstant else { return .wrapper }
			case .aliased(_, _, onlyIfAvailable: true):
				return .onlyIfAvailable
			case .aliased(_, _, onlyIfAvailable: false):
				break
			case .forwarded:
				return .flatParameter
			}
		}
		return nil
	}

	/// The mock of `instantiable` whose tree is `nodes`, in generation order: its `SafeDIOverrides`, and `mock()`, which
	/// binds each node and returns the type built from them.
	private static func mockWithTree(of instantiable: Instantiable, nodes: [MockLowering.TreeNode], context: MockContext) -> String {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		var lines = ["extension \(typeName) {"]
		lines.append(contentsOf: overridesStruct(of: nodes.compactMap(\.builtNode), indent: indent))
		lines.append("")
		lines.append("\(indent)\(mockAttributesPrefix)static func mock(")
		lines.append("\(bodyIndent)\(ReservedName.mockOverridesParameterName): \(ReservedName.mockOverridesTypeName) = .init()")
		lines.append("\(indent)) -> \(instantiable.concreteInstantiable.asSource) {")
		for node in nodes {
			lines.append(contentsOf: node.bindingLines(path: ReservedName.mockOverridesParameterName, indent: bodyIndent))
		}
		let argumentList = instantiable.initializer?.createMockInitializerArgumentList(given: instantiable.dependencies) ?? ""
		let construction = if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}
		lines.append("\(bodyIndent)return \(construction)")
		lines.append("\(indent)}")
		lines.append("}")
		let code = lines.joined(separator: "\n")
		return if let mockConditionalCompilation = context.mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(code)\n#endif"
		} else {
			code
		}
	}

	/// The mock's `SafeDIOverrides`: an optional builder closure for each node, in generation order.
	private static func overridesStruct(of nodes: [MockLowering.ConstantNode], indent: String) -> [String] {
		let innerIndent = "\(indent)\(standardIndent)"
		let memberIndent = "\(innerIndent)\(standardIndent)"
		var lines = [
			"\(indent)/// Overrides for the mock dependency tree.",
			"\(indent)struct \(ReservedName.mockOverridesTypeName) {",
		]
		let storage = ConfigurationStorage(fields: nodes.map { node in
			let typeSource = node.hasConfiguration ? node.configurationTypeName : "(\(node.builderClosureType))?"
			return ConfigurationStorage.Field(
				name: node.property.label,
				typeSource: typeSource,
				parameterTypeSource: typeSource,
				accessPrefix: "",
				documentation: nil,
				isProvenSendable: false,
			)
		})
		lines.append("\(innerIndent)init(")
		lines.append(zip(storage.fields, nodes).map { field, node in
			"\(memberIndent)\(field.name.spelledAsAssigningParameter(labeled: field.name)): \(field.typeSource) = \(node.hasConfiguration ? ".init()" : "nil")"
		}.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		lines.append(contentsOf: storage.initialization(to: storage.fields.map(\.name.spelledAsAssigningParameterName), indent: memberIndent))
		lines.append("\(innerIndent)}")
		lines.append("")
		lines.append(contentsOf: storage.readers(indent: innerIndent))
		lines.append("")
		lines.append(contentsOf: storage.declarations(indent: innerIndent))
		lines.append("\(indent)}")
		return lines
	}
}

extension MockLowering {
	/// A node of a mock's tree that builds its type with its initializer, from the values its children, the nodes built
	/// before it in scope and, for an `Instantiator`, the values it forwards bind: as a constant, or in an `Instantiator`.
	struct ConstantNode {
		let property: Property
		/// The concrete type the node builds.
		let instantiable: Instantiable
		/// The nodes the node builds, and the aliases it binds, in generation order.
		let children: [TreeNode]
		/// Whether the node builds its type in an `Instantiator`, which is handed `forwardedProperties`.
		let isInstantiator: Bool
		/// Whether the node wraps what it builds in its property's type (`erasedToConcreteExistential: true`).
		let isErased: Bool
		/// Whether the node builds a type other than its property's, which its binding then spells (`fulfilledByType:`).
		let isFulfilledByAnotherType: Bool
		/// The properties the type forwards, by label.
		let forwardedProperties: [Property]
		/// The names the constructions of the node's subtree declare `@escaping`, which its builder function's parameters
		/// spell so.
		let typesDeclaredEscaping: Set<TypeDescription>

		/// The nodes `generator` builds, in generation order, where the nodes `scope` holds are bound before them and
		/// `ancestorTypes` are the types built around them, or the first rule they meet. `labels` holds every label the
		/// tree binds so far, which each node's label joins.
		static func children(
			of generator: ScopeGenerator,
			inScope scope: Set<Property>,
			ancestorTypes: Set<TypeDescription>,
			labels: inout Set<String>,
		) -> Lowering<[TreeNode]> {
			var nodes = [TreeNode]()
			var scope = scope
			for child in generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []) {
				// D1 lane hook: kinds of node (instantiators, wrappers, aliases, holes, calls).
				switch node(of: child.generator, inScope: scope, ancestorTypes: ancestorTypes, labels: &labels) {
				case let .lowered(node):
					nodes.append(node)
					scope.insert(node.property)
				case let .unsupported(rule):
					return .unsupported(rule)
				}
			}
			return .lowered(nodes)
		}

		/// The node of `generator`, built after the nodes `scope` holds, or the first rule it meets.
		private static func node(
			of generator: ScopeGenerator,
			inScope scope: Set<Property>,
			ancestorTypes: Set<TypeDescription>,
			labels: inout Set<String>,
		) -> Lowering<TreeNode> {
			switch generator.scopeData {
			case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall):
				switch builtNode(
					of: generator,
					building: (instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall),
					inScope: scope,
					ancestorTypes: ancestorTypes,
					labels: &labels,
				) {
				case let .lowered(node):
					return .lowered(.built(node))
				case let .unsupported(rule):
					return .unsupported(rule)
				}
			case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
				// D1 lane hook: aliases only if available, of a wrapper's instance, and bound apart from their label.
				guard !onlyIfAvailable else { return .unsupported(.onlyIfAvailable) }
				guard scope.contains(fulfillingProperty) else { return .unsupported(.alias) }
				guard labels.insert(property.label).inserted else { return .unsupported(.siblingLabelCollision) }
				return .lowered(.alias(AliasBinding(
					property: property,
					fulfillingProperty: fulfillingProperty,
					isErased: erasedToConcreteExistential,
					declarationReference: declarationReference,
				)))
			case .root, .hole, .fill:
				return .unsupported(.publicMock)
			}
		}

		/// The node of `generator`, which builds `built`, or the first rule it meets.
		private static func builtNode(
			of generator: ScopeGenerator,
			building built: (instantiable: Instantiable, property: Property, forwardedProperties: Set<Property>, erasedToConcreteExistential: Bool, isPropertyCycle: Bool, seamCall: SeamCall?),
			inScope scope: Set<Property>,
			ancestorTypes: Set<TypeDescription>,
			labels: inout Set<String>,
		) -> Lowering<ConstantNode> {
			let (instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall) = built
			guard seamCall == nil, generator.publicMockCall == nil else { return .unsupported(.publicMock) }
			guard !isPropertyCycle, !ancestorTypes.contains(instantiable.concreteInstantiable) else { return .unsupported(.cycle) }
			let isErased = erasedToConcreteExistential
			let isFulfilledByAnotherType = property.typeDescription.asInstantiatedType != instantiable.concreteInstantiable
			guard !(isErased || isFulfilledByAnotherType) || property.propertyType.isConstant else { return .unsupported(.erasure) }
			let isInstantiator = property.propertyType == .instantiator
			guard property.propertyType.isConstant && forwardedProperties.isEmpty || isInstantiator else { return .unsupported(.wrapper) }
			let forwarded = instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label }
			guard generator.unavailableOptionalProperties.isEmpty else { return .unsupported(.onlyIfAvailable) }
			guard instantiable.mockInitializer == nil, let initializer = instantiable.initializer else { return .unsupported(.handWrittenMock) }
			guard !initializer.arguments.contains(where: \.hasDefaultValue) else { return .unsupported(.defaultValuedParameter) }
			guard labels.insert(property.label).inserted else { return .unsupported(.siblingLabelCollision) }
			let children: [TreeNode]
			switch Self.children(of: generator, inScope: scope.union(forwarded), ancestorTypes: ancestorTypes.union([instantiable.concreteInstantiable]), labels: &labels) {
			case let .lowered(lowered):
				children = lowered
			case let .unsupported(rule):
				return .unsupported(rule)
			}
			let childProperties = Set(children.map(\.property))
			for dependency in instantiable.dependencies {
				switch dependency.source {
				case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
					guard fulfillingTypeDescription == nil || dependency.property.propertyType.isConstant,
					      !erasedToConcreteExistential || dependency.property.propertyType.isConstant
					else { return .unsupported(.erasure) }
					guard childProperties.contains(dependency.property) else { return .unsupported(.flatParameter) }
				case .received(onlyIfAvailable: false):
					guard scope.contains(dependency.property) else { return .unsupported(.flatParameter) }
				case .forwarded:
					guard isInstantiator else { return .unsupported(.wrapper) }
				case .received(onlyIfAvailable: true):
					return .unsupported(.onlyIfAvailable)
				case .aliased(_, _, onlyIfAvailable: true):
					return .unsupported(.onlyIfAvailable)
				case .aliased(_, _, onlyIfAvailable: false):
					guard childProperties.contains(dependency.property) else { return .unsupported(.alias) }
				}
			}
			return .lowered(ConstantNode(property: property, instantiable: instantiable, children: children, isInstantiator: isInstantiator, isErased: isErased, isFulfilledByAnotherType: isFulfilledByAnotherType, forwardedProperties: forwarded, typesDeclaredEscaping: generator.typesDeclaredEscaping))
		}

		/// The type of the closure that overrides how the node is built, handed the values its initializer takes.
		var builderClosureType: String {
			let parameterTypes = (instantiable.initializer?.arguments ?? []).map { argument in
				(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription)
					.asFunctionParameter(amongTypesDeclaredEscaping: [])
					.asSource
			}
			return "(\(parameterTypes.joined(separator: ", "))) -> \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)"
		}

		/// Whether the node's children are configured in a configuration of its own, which holds its builder too.
		var hasConfiguration: Bool {
			children.contains { $0.builtNode != nil }
		}

		/// The configuration that configures the node's children and the node.
		var configurationTypeName: String {
			"\(instantiable.concreteInstantiable.asSource).SafeDIMockConfiguration"
		}

		/// The statements that bind the node, whose overrides are at `path`: its override when set, else its construction,
		/// in a builder function where it builds children.
		func bindingLines(path: String, indent: String) -> [String] {
			let typeName = instantiable.concreteInstantiable.asSource
			let initializer = instantiable.initializer
			let builderArguments = (initializer?.arguments ?? []).map(\.innerLabel).joined(separator: ", ")
			let argumentList = initializer?.createMockInitializerArgumentList(given: instantiable.dependencies) ?? ""
			let unerasedConstruction = if instantiable.declarationType.isExtension {
				"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
			} else {
				"\(typeName)(\(argumentList))"
			}
			let construction = isErased ? "\(property.typeDescription.asSource)(\(unerasedConstruction))" : unerasedConstruction
			let builder = ReservedName.configurationBuilderPropertyName
			let nodePath = "\(path).\(property.label)"
			guard !children.isEmpty || isInstantiator else {
				let annotation = isFulfilledByAnotherType && !isErased ? ": \(property.typeDescription.asSource)" : ""
				return ["\(indent)let \(property.label)\(annotation) = if let \(builder) = \(nodePath) { \(builder)(\(builderArguments)) } else { \(construction) }"]
			}
			let functionName = "\(ReservedName.builderFunctionNamePrefix)\(property.label)".spelledAsJoinedIdentifier
			let builtType = property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource
			let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
			let parameters = forwardedProperties.map { "\($0.label): \($0.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			var lines = ["\(indent)func \(functionName)(\(parameters.joined(separator: ", "))) -> \(builtType) {"]
			for child in children {
				lines.append(contentsOf: child.bindingLines(path: nodePath, indent: bodyIndent))
			}
			let overridePath = hasConfiguration ? "\(nodePath).\(builder)" : nodePath
			let returnPrefix = children.isEmpty ? "" : "return "
			// A configuration's builder returns the concrete type, which an erased node wraps as its construction does.
			let builderCall = isErased && hasConfiguration ? "\(property.typeDescription.asSource)(\(builder)(\(builderArguments)))" : "\(builder)(\(builderArguments))"
			lines.append("\(bodyIndent)\(returnPrefix)if let \(builder) = \(overridePath) { \(builderCall) } else { \(construction) }")
			lines.append("\(indent)}")
			let wrapperType = property.typeDescription.asSource
			if !isInstantiator {
				lines.append("\(indent)let \(property.label): \(wrapperType) = \(functionName)()")
			} else if forwardedProperties.isEmpty {
				lines.append("\(indent)let \(property.label) = \(wrapperType)(\(functionName))")
			} else {
				let arguments = if forwardedProperties.count == 1 {
					["\(forwardedProperties[0].label): $0"]
				} else {
					forwardedProperties.map { "\($0.label): $0.\($0.label)" }
				}
				lines.append("\(indent)let \(property.label) = \(wrapperType) {")
				lines.append("\(bodyIndent)\(functionName)(\(arguments.joined(separator: ", ")))")
				lines.append("\(indent)}")
			}
			return lines
		}
	}

	/// A node of a mock's tree: one that builds its type, or an alias of a value bound before it.
	enum TreeNode {
		case built(ConstantNode)
		case alias(AliasBinding)

		var property: Property {
			switch self {
			case let .built(node): node.property
			case let .alias(alias): alias.property
			}
		}

		var builtNode: ConstantNode? {
			switch self {
			case let .built(node): node
			case .alias: nil
			}
		}

		/// The statements that bind the node, whose overrides, where it has any, are at `path`.
		func bindingLines(path: String, indent: String) -> [String] {
			switch self {
			case let .built(node):
				node.bindingLines(path: path, indent: indent)
			case let .alias(alias):
				[alias.bindingLines(indent: indent)]
			}
		}
	}

	/// An alias a type of the tree declares, bound from a value bound before it under its own label.
	struct AliasBinding {
		let property: Property
		let fulfillingProperty: Property
		let isErased: Bool
		let declarationReference: AliasDeclarationReferences.Reference?

		/// The statement that binds the alias, which refers to its declaration as the production tree's does.
		func bindingLines(indent: String) -> String {
			GeneratedCodeText.indentingNonEmptyLines(
				of: ScopeGenerator.referencingDeclaration(
					of: ScopeGenerator.aliasDeclaration(
						of: property,
						fulfilledBy: fulfillingProperty.label,
						ofType: fulfillingProperty.typeDescription,
						erasedToConcreteExistential: isErased,
						fulfillingValueMayBeOptional: false,
					),
					by: declarationReference,
				),
				by: indent,
			)
		}
	}

	/// What a walk step lowers, or the first rule it meets that it does not lower yet.
	enum Lowering<Lowered> {
		case lowered(Lowered)
		case unsupported(Rule)
	}
}
