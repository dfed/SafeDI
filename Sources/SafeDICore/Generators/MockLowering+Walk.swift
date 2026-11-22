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
/// the root's outcome. The walk writes each node's statements as it reaches the node and keeps no tree of nodes, and it
/// recurses through `async` functions, whose frames the task allocates, so a tree as deep as the module has types neither
/// overflows a thread's stack nor releases a chain of nested nodes.
extension ScopeGenerator {
	/// The mock of `instantiable`, the mocked type of this root, whose tree is its generator's children, or the first rule
	/// the walk meets that it does not lower yet.
	func lowerMockRootWithTree(of instantiable: Instantiable, context: MockContext) async -> MockLowering.Result {
		// D1 lane hook: the mocked type's own parameters (forwarded, flat received, uncovered, defaults, hand-written mock).
		if let rule = Self.unsupportedRuleOfMockedType(instantiable) {
			return .unsupported(rule)
		}
		guard unavailableOptionalProperties.isEmpty, receivedOnlyByPublicMockCalls.isEmpty else {
			return .unsupported(.onlyIfAvailable)
		}
		let bodyIndent = "\(Self.standardIndent)\(Self.standardIndent)"
		var walk = MockLowering.Walk(ancestorTypes: [instantiable.concreteInstantiable])
		var bindingLines = [String]()
		let nodes: [MockLowering.TreeNode]
		switch await walk.children(
			of: orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator),
			inScope: [],
			path: ReservedName.mockOverridesParameterName,
			indent: bodyIndent,
			lines: &bindingLines,
		) {
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
		// A configuration `Sendable`-typed makes the overrides' storage `Sendable`, which lane B's family lowers.
		guard !nodes.contains(where: { $0.builtNode.map { $0.hasConfiguration && context.sendableConfigurationTypeNames.contains($0.instantiable.concreteInstantiable.asSource) } ?? false }) else {
			return .unsupported(.wrapper)
		}
		return .lowered(Self.mockWithTree(of: instantiable, nodes: nodes, bindingLines: bindingLines, context: context), configurations: walk.configurationRecords)
	}

	/// The first rule the parameters and construction of the mocked type itself meet that the walk does not lower yet.
	private static func unsupportedRuleOfMockedType(_ instantiable: Instantiable) -> MockLowering.Rule? {
		guard instantiable.mockInitializer == nil, instantiable.customMockName == nil, let initializer = instantiable.initializer else { return .handWrittenMock }
		guard !initializer.arguments.contains(where: \.hasDefaultValue) else { return .defaultValuedParameter }
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				// D1 lane hook (lane B): the wrapper kinds a node of the tree builds.
				guard fulfillingTypeDescription == nil && !erasedToConcreteExistential || dependency.property.propertyType.isConstant else { return .erasure }
				guard dependency.property.propertyType.isConstant || dependency.property.propertyType == .instantiator else { return .wrapper }
			case let .received(onlyIfAvailable):
				guard !onlyIfAvailable else { return .onlyIfAvailable }
				// D1 lane hook (lane B): a received wrapper the mock promotes.
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

	/// The mock of `instantiable` whose tree's top-level nodes are `nodes`, in generation order, bound by `bindingLines`:
	/// its `SafeDIOverrides`, and `mock()`, which binds each node and returns the type built from them.
	private static func mockWithTree(of instantiable: Instantiable, nodes: [MockLowering.TreeNode], bindingLines: [String], context: MockContext) -> String {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		var lines = ["extension \(typeName) {"]
		lines.append(contentsOf: overridesStruct(of: nodes.compactMap(\.overridesField), sendableConfigurationTypeNames: context.sendableConfigurationTypeNames, indent: indent))
		lines.append("")
		lines.append("\(indent)\(mockAttributesPrefix)static func mock(")
		lines.append("\(bodyIndent)\(ReservedName.mockOverridesParameterName): \(ReservedName.mockOverridesTypeName) = .init()")
		lines.append("\(indent)) -> \(instantiable.concreteInstantiable.asSource) {")
		lines.append(contentsOf: bindingLines)
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

	/// The mock's `SafeDIOverrides`: the member that configures each node, in generation order.
	private static func overridesStruct(of fields: [MockLowering.OverridesField], sendableConfigurationTypeNames: Set<String>, indent: String) -> [String] {
		let innerIndent = "\(indent)\(standardIndent)"
		let memberIndent = "\(innerIndent)\(standardIndent)"
		var lines = [
			"\(indent)/// Overrides for the mock dependency tree.",
			"\(indent)struct \(ReservedName.mockOverridesTypeName) {",
		]
		let storage = ConfigurationStorage(fields: fields.map { field in
			ConfigurationStorage.Field(
				name: field.name,
				typeSource: field.typeSource,
				parameterTypeSource: field.typeSource,
				accessPrefix: "",
				documentation: nil,
				isProvenSendable: field.isProvenSendable(amongConfigurationsTypedSendable: sendableConfigurationTypeNames),
			)
		})
		lines.append("\(innerIndent)init(")
		lines.append(zip(storage.fields, fields).map { storageField, field in
			"\(memberIndent)\(storageField.name.spelledAsAssigningParameter(labeled: storageField.name)): \(storageField.typeSource) = \(field.defaultValue)"
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
	/// The state of one root's walk: the types and labels built around the node it is at, and the labels its level binds
	/// so far. A label bound again on another branch is bound in another builder function, apart from this one.
	struct Walk {
		var ancestorTypes: Set<TypeDescription>
		var ancestorLabels = Set<String>()
		var labels = Set<String>()
		// D1 lane hook (lane D): the configurations of the nodes the walk finished, children before their node.
		var configurationRecords = [ConfigurationRecord]()
		// D1 lane hook (lane B): the extractor of the `@Sendable` builder function the walk is inside, and the names of each
		// level it is in, from which such a function's locals are claimed (`MockLowering+Wrappers.swift`).
		var sendableOverrideExtractor: ScopeGenerator.SendableOverrideExtractor?
		var levelNames = [GeneratedNameAllocator]()
		/// Whether the walk is inside a `@Sendable` builder function, whose nodes' override closures are `@Sendable`.
		var isInsideSendableFunction = false

		/// The nodes `generators` build, in generation order, where the nodes `scope` holds are bound before them, their
		/// overrides at `path`, with their statements appended to `lines` at `indent`; or the first rule they meet.
		mutating func children(
			of generators: [ScopeGenerator],
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async -> Lowering<[TreeNode]> {
			var nodes = [TreeNode]()
			var scope = scope
			// D1 lane hook (lane B): the level's names, which a `@Sendable` builder function's locals are kept apart from.
			for generator in generators {
				// D1 lane hook: kinds of node (instantiators, wrappers, aliases, holes, calls).
				switch await node(of: generator, inScope: scope, path: path, indent: indent, lines: &lines) {
				case let .lowered(node):
					nodes.append(node)
					scope.insert(node.property)
				case let .unsupported(rule):
					return .unsupported(rule)
				}
			}
			return .lowered(nodes)
		}

		/// The node of `generator`, built after the nodes `scope` holds, whose statements are appended to `lines`, or the
		/// first rule it meets.
		private mutating func node(
			of generator: ScopeGenerator,
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async -> Lowering<TreeNode> {
			if case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference) = generator.scopeData {
				// D1 lane hook: aliases only if available, of a wrapper's instance, and bound apart from their label.
				guard !onlyIfAvailable else { return .unsupported(.onlyIfAvailable) }
				guard scope.contains(fulfillingProperty) else { return .unsupported(.alias) }
				guard !ancestorLabels.contains(property.label), labels.insert(property.label).inserted else { return .unsupported(.siblingLabelCollision) }
				let alias = AliasBinding(
					property: property,
					fulfillingProperty: fulfillingProperty,
					isErased: erasedToConcreteExistential,
					declarationReference: declarationReference,
				)
				lines.append(alias.bindingLines(indent: indent))
				return .lowered(.alias(alias))
			} else {
				// D1 lane hook (lane C): a hole site and a fill, the kinds of node a public mock's tree holds besides properties
				// and aliases, and a call of another module's public mock (`MockLowering+PublicMocks.swift`).
				guard case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall) = generator.scopeData else { return await placeOrFillNode(of: generator, inScope: scope, path: path, indent: indent, lines: &lines) }
				guard generator.publicMockCall == nil else { return await publicMockCallNode(of: generator, inScope: scope, path: path, indent: indent, lines: &lines) }
				switch await builtNode(
					of: generator,
					building: (instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall),
					inScope: scope,
					path: path,
					indent: indent,
					lines: &lines,
				) {
				case let .lowered(node):
					return .lowered(.built(node))
				case let .unsupported(rule):
					return .unsupported(rule)
				}
			}
		}

		/// The node of `generator`, which builds `built`, whose statements are appended to `lines`, or the first rule it
		/// meets: its override when set, else its construction, in a builder function where it builds children.
		private mutating func builtNode(
			of generator: ScopeGenerator,
			building built: (instantiable: Instantiable, property: Property, forwardedProperties: Set<Property>, erasedToConcreteExistential: Bool, isPropertyCycle: Bool, seamCall: SeamCall?),
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async -> Lowering<ConstantNode> {
			let (instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall) = built
			// A mock builds every seam inline, so no scope of its tree calls one.
			guard seamCall == nil else { return .unsupported(.publicMockCall) }
			guard !isPropertyCycle, !ancestorTypes.contains(instantiable.concreteInstantiable) else { return .unsupported(.cycle) }
			let isErased = erasedToConcreteExistential
			let isFulfilledByAnotherType = property.typeDescription.asInstantiatedType != instantiable.concreteInstantiable
			// D1 lane hook (lane B): the wrapper kinds and `@Sendable` builder functions a node builds its type in.
			guard !(isErased || isFulfilledByAnotherType) || property.propertyType.isConstant else { return .unsupported(.erasure) }
			let isWrapped = !property.propertyType.isConstant
			guard property.propertyType.isConstant && forwardedProperties.isEmpty || property.propertyType == .instantiator,
			      !generator.buildsInSendableFunction
			else { return .unsupported(.wrapper) }
			let forwarded = instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label }
			guard generator.unavailableOptionalProperties.isEmpty else { return .unsupported(.onlyIfAvailable) }
			guard instantiable.mockInitializer == nil, let initializer = instantiable.initializer else { return .unsupported(.handWrittenMock) }
			guard !initializer.arguments.contains(where: \.hasDefaultValue) else { return .unsupported(.defaultValuedParameter) }
			guard !ancestorLabels.contains(property.label), labels.insert(property.label).inserted else { return .unsupported(.siblingLabelCollision) }

			let childGenerators = generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator)
			// D1 lane hook (lane B): the expression that reads the node's override, which inside a `@Sendable` builder
			// function reads a local.
			let nodePath = "\(path).\(property.label)"
			let overrideRead = nodePath
			let node = ConstantNode(
				property: property,
				instantiable: instantiable,
				hasChildren: !childGenerators.isEmpty,
				isWrapped: isWrapped,
				isErased: isErased,
				isFulfilledByAnotherType: isFulfilledByAnotherType,
				forwardedProperties: forwarded,
				typesDeclaredEscaping: generator.typesDeclaredEscaping,
				arguments: initializer.arguments.compactMap { argument in
					// D1 lane hook (lane B): the value a lazy wrapper's instance is read by.
					instantiable.dependencies.contains(where: argument.isFulfilled(by:)) ? (label: argument.label.spelledAsArgumentLabel, value: argument.innerLabel) : nil
				},
				buildsInSendableFunction: generator.buildsInSendableFunction,
				requiresSendable: isInsideSendableFunction || generator.buildsInSendableFunction,
			)
			guard node.hasChildren || isWrapped else {
				guard let rule = Self.unsupportedRule(ofDependenciesOf: instantiable, isWrapped: isWrapped, inScope: scope, childProperties: []) else {
					lines.append(node.constantBindingLine(overrideRead: overrideRead, indent: indent))
					return .lowered(node)
				}
				return .unsupported(rule)
			}
			// D1 lane hook (lane B): the extraction a `@Sendable` builder function starts.
			let wasInsideSendableFunction = isInsideSendableFunction
			isInsideSendableFunction = node.requiresSendable
			lines.append(node.builderFunctionDeclarationLine(indent: indent))
			ancestorTypes.insert(instantiable.concreteInstantiable)
			ancestorLabels.insert(property.label)
			let siblingLabels = labels
			labels = []
			let lowering = await children(
				of: childGenerators,
				inScope: scope.union(forwarded),
				path: nodePath,
				indent: "\(indent)\(ScopeGenerator.standardIndent)",
				lines: &lines,
			)
			labels = siblingLabels
			ancestorLabels.remove(property.label)
			ancestorTypes.remove(instantiable.concreteInstantiable)
			isInsideSendableFunction = wasInsideSendableFunction
			let children: [TreeNode]
			switch lowering {
			case let .lowered(lowered):
				children = lowered
			case let .unsupported(rule):
				return .unsupported(rule)
			}
			if let rule = Self.unsupportedRule(ofDependenciesOf: instantiable, isWrapped: isWrapped, inScope: scope, childProperties: Set(children.map(\.property))) {
				return .unsupported(rule)
			}
			let configuredNode = node.configured(byChildren: children)
			// D1 lane hook (lane B): the override read of a function that ends an extraction, and the locals it read.
			let functionOverrideRead = configuredNode.hasConfiguration ? "\(overrideRead).\(ReservedName.configurationBuilderPropertyName)" : overrideRead
			if configuredNode.hasConfiguration {
				configurationRecords.append(ConfigurationRecord(of: configuredNode, children: children))
			}
			lines.append(contentsOf: configuredNode.builderFunctionEndLines(overrideRead: functionOverrideRead, indent: indent))
			return .lowered(configuredNode)
		}

		/// The first rule a dependency of `instantiable`, built after the nodes `scope` holds and from its children's
		/// `childProperties`, meets that the walk does not lower yet.
		private static func unsupportedRule(
			ofDependenciesOf instantiable: Instantiable,
			isWrapped: Bool,
			inScope scope: Set<Property>,
			childProperties: Set<Property>,
		) -> Rule? {
			for dependency in instantiable.dependencies {
				switch dependency.source {
				case .instantiated:
					// D1 lane hook (lane B): a wrapper child is a node of its own, erased or fulfilled by another type alike.
					guard childProperties.contains(dependency.property) else { return .flatParameter }
				case .received(onlyIfAvailable: false):
					// D1 lane hook (lane B): a receive by value of a lazy wrapper's instance.
					guard scope.contains(dependency.property) else { return .flatParameter }
				case .forwarded:
					guard isWrapped else { return .wrapper }
				case .received(onlyIfAvailable: true), .aliased(_, _, onlyIfAvailable: true):
					// An alias only if available is its own node, which the walk rejects before its type's dependencies.
					return .onlyIfAvailable
				case .aliased(_, _, onlyIfAvailable: false):
					guard childProperties.contains(dependency.property) else { return .alias }
				}
			}
			return nil
		}
	}

	/// A node of a mock's tree that builds its type with its initializer, from the values its children, the nodes built
	/// before it in scope and, for an `Instantiator`, the values it forwards bind: as a constant, or in an `Instantiator`.
	struct ConstantNode {
		let property: Property
		/// The concrete type the node builds.
		let instantiable: Instantiable
		/// Whether the node builds children or binds aliases, which its builder function declares.
		let hasChildren: Bool
		/// Whether the node builds its type in a wrapper, which is handed `forwardedProperties`.
		let isWrapped: Bool
		/// Whether the node wraps what it builds in its property's type (`erasedToConcreteExistential: true`).
		let isErased: Bool
		/// Whether the node builds a type other than its property's, which its binding then spells (`fulfilledByType:`).
		let isFulfilledByAnotherType: Bool
		/// The properties the type forwards, by label.
		let forwardedProperties: [Property]
		/// The names the constructions of the node's subtree declare `@escaping`, which its builder function's parameters
		/// spell so.
		let typesDeclaredEscaping: Set<TypeDescription>
		// D1 lane hook (lane B): what the construction is handed, a lazy wrapper's instance included, and whether the node
		// is built in a `@Sendable` builder function of its own or inside one.
		/// The labels and values of the construction's arguments, in the initializer's order.
		let arguments: [(label: String, value: String)]
		/// Whether the node's builder function is `@Sendable`.
		let buildsInSendableFunction: Bool
		/// Whether the node is built in or as a `@Sendable` builder function, so its override closure is `@Sendable`.
		let requiresSendable: Bool
		/// Whether the node's children are configured in a configuration of its own, which holds its builder too.
		var hasConfiguration = false

		/// The node, configured in a configuration of its own where `children` hold a node that builds its type.
		func configured(byChildren children: [TreeNode]) -> ConstantNode {
			var node = self
			node.hasConfiguration = children.contains { $0.overridesField != nil }
			return node
		}

		/// The member of the enclosing overrides that configures the node: its configuration, or an optional builder closure.
		var overridesField: OverridesField {
			// D1 lane hook (lane B): a node built in or as a `@Sendable` builder function takes a `@Sendable` override, which
			// is `Sendable`, as is a configuration `@Sendable`-typed.
			hasConfiguration
				? OverridesField(name: property.label, typeSource: configurationTypeName, defaultValue: ".init()", sendability: .whenConfigurationIsTypedSendable(instantiable.concreteInstantiable.asSource))
				: OverridesField(name: property.label, typeSource: "(\(requiresSendable ? "@Sendable " : "")\(builderClosureType))?", defaultValue: "nil", sendability: requiresSendable ? .always : .never)
		}

		/// The type of the closure that overrides how the node is built, handed the values its initializer takes.
		var builderClosureType: String {
			"(\(builderParameterTypes)) -> \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)"
		}

		/// The type of the closure the node's configuration holds to override how it is built, which returns the concrete
		/// type, since every node of the type shares the configuration.
		var concreteBuilderClosureType: String {
			"(\(builderParameterTypes)) -> \(instantiable.concreteInstantiable.asSource)"
		}

		/// The types of the values the node's override is handed, joined.
		private var builderParameterTypes: String {
			(instantiable.initializer?.arguments ?? []).map { argument in
				(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription)
					.asFunctionParameter(amongTypesDeclaredEscaping: [])
					.asSource
			}.joined(separator: ", ")
		}

		/// The configuration that configures the node's children and the node.
		var configurationTypeName: String {
			"\(instantiable.concreteInstantiable.asSource).SafeDIMockConfiguration"
		}

		/// The arguments the node's override is handed: its initializer's, by name.
		private var builderArguments: String {
			arguments.map(\.value).joined(separator: ", ")
		}

		/// How the node is built without an override.
		private var construction: String {
			let typeName = instantiable.concreteInstantiable.asSource
			let argumentList = arguments.map { "\($0.label): \($0.value)" }.joined(separator: ", ")
			let unerasedConstruction = if instantiable.declarationType.isExtension {
				"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
			} else {
				"\(typeName)(\(argumentList))"
			}
			return isErased ? "\(erasedTypeSource)(\(unerasedConstruction))" : unerasedConstruction
		}

		/// The type an erased node wraps what it builds in: its property's, or the type a wrapper builds.
		private var erasedTypeSource: String {
			isWrapped ? property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource : property.typeDescription.asSource
		}

		/// The name of the node's builder function.
		var functionName: String {
			"\(ReservedName.builderFunctionNamePrefix)\(property.label)".spelledAsJoinedIdentifier
		}

		/// The statement that binds a constant node with no children, whose override `overrideRead` reads.
		func constantBindingLine(overrideRead nodePath: String, indent: String) -> String {
			let builder = ReservedName.configurationBuilderPropertyName
			let annotation = isFulfilledByAnotherType && !isErased ? ": \(property.typeDescription.asSource)" : ""
			return "\(indent)let \(property.label)\(annotation) = if let \(builder) = \(nodePath) { \(builder)(\(builderArguments)) } else { \(construction) }"
		}

		/// The first line of the node's builder function, whose children's statements follow it.
		func builderFunctionDeclarationLine(indent: String) -> String {
			let builtType = property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource
			let parameters = forwardedProperties.map { "\($0.label): \($0.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let decorator = buildsInSendableFunction ? "@Sendable " : ""
			return "\(indent)\(decorator)func \(functionName)(\(parameters.joined(separator: ", "))) -> \(builtType) {"
		}

		/// The lines that end the node's builder function, after its children's statements, and bind the node, whose
		/// overrides are at `nodePath`.
		func builderFunctionEndLines(overrideRead overridePath: String, indent: String) -> [String] {
			let builder = ReservedName.configurationBuilderPropertyName
			let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
			let returnPrefix = hasChildren ? "return " : ""
			// A configuration's builder returns the concrete type, which an erased node wraps as its construction does.
			let builderCall = isErased && hasConfiguration ? "\(erasedTypeSource)(\(builder)(\(builderArguments)))" : "\(builder)(\(builderArguments))"
			var lines = ["\(bodyIndent)\(returnPrefix)if let \(builder) = \(overridePath) { \(builderCall) } else { \(construction) }"]
			lines.append("\(indent)}")
			// D1 lane hook (lane B): the binding of each wrapper kind.
			if isWrapped, forwardedProperties.isEmpty {
				lines.append("\(indent)let \(property.label) = \(property.typeDescription.asSource)(\(functionName))")
			} else if isWrapped {
				let arguments = if forwardedProperties.count == 1 {
					["\(forwardedProperties[0].label): $0"]
				} else {
					forwardedProperties.map { "\($0.label): $0.\($0.label)" }
				}
				lines.append("\(indent)let \(property.label) = \(property.typeDescription.asSource) {")
				lines.append("\(bodyIndent)\(functionName)(\(arguments.joined(separator: ", ")))")
				lines.append("\(indent)}")
			} else {
				lines.append("\(indent)let \(property.label): \(property.typeDescription.asSource) = \(functionName)()")
			}
			return lines
		}
	}

	/// A node of a mock's tree: one that builds its type, an alias of a value bound before it, or a call of another module's
	/// public mock.
	enum TreeNode {
		case built(ConstantNode)
		case alias(AliasBinding)
		// D1 lane hook (lane C): a call of another module's public mock (`MockLowering+PublicMocks.swift`).
		case publicMockCall(PublicMockCallNode)

		var property: Property {
			switch self {
			case let .built(node): node.property
			case let .alias(alias): alias.property
			case let .publicMockCall(call): call.property
			}
		}

		var builtNode: ConstantNode? {
			switch self {
			case let .built(node): node
			case .alias, .publicMockCall: nil
			}
		}

		/// The member of the enclosing overrides that configures the node, if any.
		var overridesField: OverridesField? {
			switch self {
			case let .built(node): node.overridesField
			case .alias: nil
			case let .publicMockCall(call): call.overridesField
			}
		}
	}

	/// A member of a mock's overrides, or of a configuration, that configures one node: its name, type and default.
	struct OverridesField {
		let name: String
		let typeSource: String
		let defaultValue: String
		let sendability: Sendability

		/// What proves the member `Sendable`.
		enum Sendability {
			/// A `@Sendable` closure.
			case always
			/// A value SafeDI does not prove `Sendable`.
			case never
			/// The configuration of the named type, `Sendable` where it is `@Sendable`-typed.
			case whenConfigurationIsTypedSendable(String)
		}

		/// Whether SafeDI proves the member `Sendable`, given the types whose configurations are `@Sendable`-typed.
		func isProvenSendable(amongConfigurationsTypedSendable typeNames: Set<String>) -> Bool {
			switch sendability {
			case .always: true
			case .never: false
			case let .whenConfigurationIsTypedSendable(typeName): typeNames.contains(typeName)
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

extension MockLowering.ConfigurationRecord {
	/// The configuration `node`, which `children` build beneath, is configured by.
	// D1 lane hook (lane D): each child's field as the core's `SafeDIOverrides` spells it.
	init(of node: MockLowering.ConstantNode, children: [MockLowering.TreeNode]) {
		self.init(
			concreteType: node.instantiable.concreteInstantiable,
			usesMockInitializer: false,
			childFields: children.compactMap(\.builtNode).map { child in
				ChildField(
					name: child.property.label,
					typeSource: child.hasConfiguration ? child.configurationTypeName : "(\(child.builderClosureType))?",
					defaultValue: child.hasConfiguration ? ".init()" : "nil",
				)
			},
			concreteBuilderClosureType: node.concreteBuilderClosureType,
		)
	}
}
