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
		let nodes: [MockLowering.ConstantNode]
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
		guard instantiable.mockInitializer == nil, instantiable.customMockName == nil else { return .handWrittenMock }
		guard let initializer = instantiable.initializer else { return .handWrittenMock }
		guard !initializer.arguments.contains(where: \.hasDefaultValue) else { return .defaultValuedParameter }
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				guard fulfillingTypeDescription == nil, !erasedToConcreteExistential else { return .erasure }
				guard dependency.property.propertyType.isConstant || dependency.property.propertyType == .instantiator else { return .wrapper }
			case let .received(onlyIfAvailable):
				guard !onlyIfAvailable else { return .onlyIfAvailable }
				guard dependency.property.propertyType.isConstant else { return .wrapper }
			case .aliased:
				return .alias
			case .forwarded:
				return .flatParameter
			}
		}
		return nil
	}

	/// The mock of `instantiable` whose tree is `nodes`, in generation order: its `SafeDIOverrides`, and `mock()`, which
	/// binds each node and returns the type built from them.
	private static func mockWithTree(of instantiable: Instantiable, nodes: [MockLowering.ConstantNode], context: MockContext) -> String {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		var lines = ["extension \(typeName) {"]
		lines.append(contentsOf: overridesStruct(of: nodes, indent: indent))
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
			let typeSource = node.children.isEmpty ? "(\(node.builderClosureType))?" : node.configurationTypeName
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
			"\(memberIndent)\(field.name.spelledAsAssigningParameter(labeled: field.name)): \(field.typeSource) = \(node.children.isEmpty ? "nil" : ".init()")"
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
		/// The nodes the node builds, in generation order.
		let children: [ConstantNode]
		/// Whether the node builds its type in an `Instantiator`, which is handed `forwardedProperties`.
		let isInstantiator: Bool
		/// The properties the type forwards, by label.
		let forwardedProperties: [Property]

		/// The nodes `generator` builds, in generation order, where the nodes `scope` holds are bound before them and
		/// `ancestorTypes` are the types built around them, or the first rule they meet. `labels` holds every label the
		/// tree binds so far, which each node's label joins.
		static func children(
			of generator: ScopeGenerator,
			inScope scope: Set<Property>,
			ancestorTypes: Set<TypeDescription>,
			labels: inout Set<String>,
		) -> Lowering<[ConstantNode]> {
			var nodes = [ConstantNode]()
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
		) -> Lowering<ConstantNode> {
			guard case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall) = generator.scopeData else {
				return .unsupported(.alias)
			}
			guard seamCall == nil, generator.publicMockCall == nil else { return .unsupported(.publicMock) }
			guard !isPropertyCycle, !ancestorTypes.contains(instantiable.concreteInstantiable) else { return .unsupported(.cycle) }
			guard !erasedToConcreteExistential, property.typeDescription.asInstantiatedType == instantiable.concreteInstantiable else { return .unsupported(.erasure) }
			let isInstantiator = property.propertyType == .instantiator
			guard property.propertyType.isConstant && forwardedProperties.isEmpty || isInstantiator else { return .unsupported(.wrapper) }
			let forwarded = instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label }
			guard generator.unavailableOptionalProperties.isEmpty else { return .unsupported(.onlyIfAvailable) }
			guard instantiable.mockInitializer == nil, let initializer = instantiable.initializer else { return .unsupported(.handWrittenMock) }
			guard !initializer.arguments.contains(where: \.hasDefaultValue) else { return .unsupported(.defaultValuedParameter) }
			guard labels.insert(property.label).inserted else { return .unsupported(.siblingLabelCollision) }
			let children: [ConstantNode]
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
					guard fulfillingTypeDescription == nil, !erasedToConcreteExistential else { return .unsupported(.erasure) }
					guard childProperties.contains(dependency.property) else { return .unsupported(.flatParameter) }
				case .received(onlyIfAvailable: false):
					guard scope.contains(dependency.property) else { return .unsupported(.flatParameter) }
				case .forwarded:
					guard isInstantiator else { return .unsupported(.wrapper) }
				case .received(onlyIfAvailable: true):
					return .unsupported(.onlyIfAvailable)
				case .aliased:
					return .unsupported(.alias)
				}
			}
			return .lowered(ConstantNode(property: property, instantiable: instantiable, children: children, isInstantiator: isInstantiator, forwardedProperties: forwarded))
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
			let construction = if instantiable.declarationType.isExtension {
				"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
			} else {
				"\(typeName)(\(argumentList))"
			}
			let builder = ReservedName.configurationBuilderPropertyName
			let nodePath = "\(path).\(property.label)"
			guard !children.isEmpty || isInstantiator else {
				return ["\(indent)let \(property.label) = if let \(builder) = \(nodePath) { \(builder)(\(builderArguments)) } else { \(construction) }"]
			}
			let functionName = "\(ReservedName.builderFunctionNamePrefix)\(property.label)".spelledAsJoinedIdentifier
			let builtType = property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource
			let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
			let parameters = forwardedProperties.map { "\($0.label): \($0.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: []).asSource)" }
			var lines = ["\(indent)func \(functionName)(\(parameters.joined(separator: ", "))) -> \(builtType) {"]
			for child in children {
				lines.append(contentsOf: child.bindingLines(path: nodePath, indent: bodyIndent))
			}
			let overridePath = children.isEmpty ? nodePath : "\(nodePath).\(builder)"
			let returnPrefix = children.isEmpty ? "" : "return "
			lines.append("\(bodyIndent)\(returnPrefix)if let \(builder) = \(overridePath) { \(builder)(\(builderArguments)) } else { \(construction) }")
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

	/// What a walk step lowers, or the first rule it meets that it does not lower yet.
	enum Lowering<Lowered> {
		case lowered(Lowered)
		case unsupported(Rule)
	}
}
