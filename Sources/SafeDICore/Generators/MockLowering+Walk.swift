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
		// D1 lane hook (lane B): the mocked type's own receives only if available that nothing above provides are passed `nil`
		// (`rootArgumentList(of:given:renames:passingNilTo:)`).
		guard receivedOnlyByPublicMockCalls.isEmpty else {
			return .unsupported(.onlyIfAvailable)
		}
		// D1 lane hook (lane D): the parameters `mock()` takes before its overrides (`lowerRootSignature(of:context:)`).
		let signature: MockLowering.RootSignature
		switch lowerRootSignature(of: instantiable, context: context) {
		case let .lowered(lowered):
			signature = lowered
		case let .unsupported(rule):
			return .unsupported(rule)
		}
		let bodyIndent = "\(Self.standardIndent)\(Self.standardIndent)"
		let orderedChildren = orderedChildrenComputedAfresh(propertiesGeneratedLater: [])
		// No node binds a parameter’s label again, at any depth: the emitter names the parameter apart.
		var walk = MockLowering.Walk(cycleEdges: context.cycleEdges, rootLabels: signature.labels, uncoveredProperties: signature.uncoveredProperties)
		walk.rootFlatReceivedLabels = Set(signature.flatReceivedParameters.map(\.property.label))
		// D1 lane hook (lane B): a receive of a flat received parameter or override named apart from its label is handed that
		// name, which its builder function binds again under the label.
		walk.renames = signature.renamesByLabelAndType
		// D1 lane hook (lane B): the uncovered dependencies named apart, which the types that instantiate them are passed, and
		// a receive beneath reads, from the mocked type's own for its whole tree (`routingReceives`).
		walk.uncoveredParameterNames = signature.uncoveredParameterNamesByLabelAndType
		walk.rootOverrideNames = Set(signature.onlyIfAvailableOverrides.map(\.name))
		let mockedTypeUncoveredProperties = instantiable.dependencies.compactMap { dependency -> Property? in
			guard case .instantiated = dependency.source, signature.uncoveredProperties.contains(dependency.property) else { return nil }
			return dependency.property
		}
		walk.renames = MockLowering.removingRenames(hiddenBy: mockedTypeUncoveredProperties, from: walk.renames)
		MockLowering.routeReceives(of: mockedTypeUncoveredProperties, toParametersNamed: walk.uncoveredParameterNames, in: &walk.renames)
		walk.rootParametersKeepingTheirLabels = (signature.forwardedParameters + signature.rootDefaultParameters).map(\.property)
		// D1 lane hook (lane D): the defaults a type's hand-written mock declares, which its configuration's fields take.
		walk.handWrittenMockDefaultParameters = context.handWrittenMockDefaultParameters
		walk.sendableConfigurationTypeNames = context.sendableConfigurationTypeNames
		// D1 lane hook (lane C): a public mock builds each configured node with its type's construction function.
		walk.buildsPublicMock = instantiable.generateMock == .public
		// D1 lane hook (lane C): the nodes a public mock promotes, each bound from its caller's value when passed one.
		walk.promotedProperties = publicMockPromotedProperties(of: instantiable, among: orderedChildren)
		// D1 lane hook (lane C): the builders `mock()` takes optional for the places its calls fill.
		switch filledCallBuilders(of: orderedChildren, context: context) {
		case let .lowered(filledCallBuilders):
			walk.filledCallBuilders = filledCallBuilders
		case let .unsupported(rule):
			return .unsupported(rule)
		}
		// D1 lane hook (lane C): a public mock's calls read each builder under the internal name its plan gives it.
		if let optionalBuilderNames = publicMockOptionalBuilderNames(of: instantiable, signature: signature, filledCallBuilders: walk.filledCallBuilders, context: context) {
			switch filledCallBuilders(of: orderedChildren, context: context, optionalBuilderNames: optionalBuilderNames) {
			case let .lowered(filledCallBuilders):
				walk.filledCallBuilders = filledCallBuilders
			case let .unsupported(rule):
				return .unsupported(rule)
			}
		}
		// D1 lane hook (lane B): `mock()` first binds each override of what its tree receives only if available, which the
		// receives beneath read.
		// D1 lane hook (lane C): a public mock takes each as a parameter of `mock()` under the override's name, which binds it.
		var bindingLines = instantiable.generateMock == .public ? [] : signature.onlyIfAvailableOverrides.map { override in
			"\(bodyIndent)let \(override.name): \(override.typeDescription.asSource) = \(ReservedName.mockOverridesParameterName).\(override.name)"
		}
		// D1 lane hook (lane C): `mock()` first binds each builder a call passes up apart from its label.
		bindingLines.append(contentsOf: walk.filledCallBuilders.leadingBindingLines(indent: bodyIndent))
		let rootReceiverBindingIndex = bindingLines.endIndex
		// D1 lane hook (lane B): each override binds its receive's label, in the optional form a receive only if available
		// reads.
		let overrideProperties = Set(signature.onlyIfAvailableOverrides.flatMap { override in
			[override.receivedProperty, Property(label: override.receivedProperty.label, typeDescription: override.typeDescription)]
		})
		let nodes: [MockLowering.TreeNode]
		switch await walk.children(
			of: orderedChildren,
			loops: mockLoweringLoopMemberships,
			inScope: signature.properties.union(overrideProperties),
			path: ReservedName.mockOverridesParameterName,
			indent: bodyIndent,
			lines: &bindingLines,
		) {
		case let .lowered(children):
			nodes = children
		case let .unsupported(rule):
			return .unsupported(rule)
		}
		// The mocked type is passed its own dependencies by label, and the builder functions beneath bind theirs, so the root's
		// level names apart only labels neither reads.
		// D1 lane hook (lane D): the mocked type's construction reads the names its own dependencies are bound apart under.
		guard walk.rootNamesApart.isDisjoint(with: walk.dependencyLabelsInTree), walk.rootAliasNamesApart.isDisjoint(with: walk.dependencyLabelsInTree) else { return .unsupported(.siblingLabelCollision) }
		// The mocked type is passed each of its own dependencies the root's level names apart by that name
		// (`generateReturnArgumentList`'s disambiguation map), which reads the exact property's name.
		let lazilyInstantiatedInstances = Set(propertiesToGenerate.compactMap(\.mockLoweringDeclaredLazilyInstantiatedInstanceProperty))
			.union(mockLoweringLazilyInstantiatedInstanceProperties)
		// D1 lane hook (lane B): one read through a `LazilyInstantiated` the level names apart reads its instance.
		guard !instantiable.dependencies.contains(where: { dependency in
			walk.rootLabelsNamedApart.contains(dependency.property.label) && lazilyInstantiatedInstances.contains(dependency.property.asUnwrappedProperty)
		}) else { return .unsupported(.siblingLabelCollision) }
		// D1 lane hook (lane B): the mocked type's own receive of a flat received parameter or override named apart is bound
		// again under its label before the tree, unless the root's level binds that label (`generateMockRootCode`'s
		// `rootDependenciesToRebind`), when the mocked type is passed the name.
		let rootLevelBindingNames = walk.rootPropertyNodeBindingNames.union(signature.onlyIfAvailableOverrides.map(\.name))
		var rootRenames = walk.rootRenames
		var rootReceiverBindingLines = [String]()
		for dependency in instantiable.dependencies where dependency.source.isReceived {
			guard let names = signature.renamesByLabelAndType[dependency.property.label],
			      let name = names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription],
			      !rootLevelBindingNames.contains(dependency.property.label)
			else { continue }
			rootReceiverBindingLines.append("\(bodyIndent)let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(name)")
			rootRenames[dependency.property.label]?[dependency.property.typeDescription] = nil
		}
		bindingLines.insert(contentsOf: rootReceiverBindingLines, at: rootReceiverBindingIndex)
		// Every dependency of the mocked type is a node of its tree, a parameter of `mock()`, an override's binding or passed
		// `nil`.
		let providedProperties = Set(nodes.map(\.property)).union(signature.properties).union(overrideProperties).union(unavailableOptionalProperties)
		guard instantiable.dependencies.allSatisfy({ providedProperties.contains($0.property) }) else {
			return .unsupported(.flatParameter)
		}
		// D1 lane hook (lane C): every call that fills builders is a node the walk reached.
		guard walk.filledCallBuilders.calls.isEmpty else {
			return .unsupported(.fill)
		}
		// D1 lane hook (lane C): a public mock's tiers, overrides and guard (`MockLowering+PublicMocks.swift`).
		guard instantiable.generateMock != .public else {
			// D1 lane hook (lane C): a public mock's parameters named apart and its values passed `nil`, as the internal mock's.
			return publicMockWithTree(of: instantiable, signature: signature, nodes: nodes, bindingLines: bindingLines, rootRenames: rootRenames, unavailableProperties: unavailableOptionalProperties, filledCallBuilders: walk.filledCallBuilders, configurations: walk.configurationRecords, context: context)
		}
		return .lowered(Self.mockWithTree(of: instantiable, signature: signature, nodes: nodes, bindingLines: bindingLines, builders: walk.filledCallBuilders.parameters, rootRenames: rootRenames, unavailableProperties: unavailableOptionalProperties, context: context), configurations: walk.configurationRecords)
	}

	/// The first rule the parameters and construction of the mocked type itself meet that the walk does not lower yet.
	private static func unsupportedRuleOfMockedType(_ instantiable: Instantiable) -> MockLowering.Rule? {
		// The initializer's default-valued arguments are parameters of `mock()` (`lowerRootSignature(of:context:)`).
		guard instantiable.mockInitializer == nil, instantiable.customMockName == nil, instantiable.initializer != nil else { return .handWrittenMock }
		// D1 lane hook (lane B): every dependency of the mocked type is a node of its tree (a wrapper of any kind, erased or
		// fulfilled by another type alike, a received wrapper the mock promotes, an alias), a parameter of `mock()` or an
		// override's binding, which the walk checks it binds.
		return nil
	}

	/// The mock of `instantiable` whose tree's top-level nodes are `nodes`, in generation order, bound by `bindingLines`:
	/// its `SafeDIOverrides` where a node has an override, and `mock()`, which takes `signature`'s parameters, the builders
	/// `builders` (each label and declaration, in label order, listed among the flat received parameters) and the overrides, binds each node and returns the type built from them.
	private static func mockWithTree(of instantiable: Instantiable, signature: MockLowering.RootSignature, nodes: [MockLowering.TreeNode], bindingLines: [String], builders: [(label: String, declaration: String)], rootRenames: [String: [TypeDescription: String]], unavailableProperties: Set<Property>, context: MockContext) -> String {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		// A mock that takes nothing and binds nothing is one call of the type's construction.
		guard !nodes.isEmpty || !signature.parameters.isEmpty || !signature.onlyIfAvailableOverrides.isEmpty else { return mockWithoutTree(of: instantiable, context: context, passingNilTo: unavailableProperties) }
		var lines = ["extension \(typeName) {"]
		let overridesFields = nodes.compactMap(\.overridesField)
		// D1 lane hook (lane C): the builders `mock()` takes, listed among the flat received parameters by label.
		var parameterLines = signature.parameterLines(indent: bodyIndent, builders: builders)
		if !overridesFields.isEmpty || !signature.onlyIfAvailableOverrides.isEmpty {
			lines.append(contentsOf: overridesStruct(of: overridesFields, onlyIfAvailableOverrides: signature.onlyIfAvailableOverrides, sendableConfigurationTypeNames: context.sendableConfigurationTypeNames, indent: indent))
			lines.append("")
			parameterLines.append("\(bodyIndent)\(ReservedName.mockOverridesParameterName): \(ReservedName.mockOverridesTypeName) = .init()")
		} else if nodes.contains(where: \.isPropertyNode) {
			// D1 lane hook (lane C): a tree whose nodes have no override, such as a call of a mock that takes no overrides and
			// offers no override closure, still declares its `SafeDIOverrides`, empty.
			lines.append("\(indent)/// Overrides for the mock dependency tree.")
			lines.append("\(indent)struct \(ReservedName.mockOverridesTypeName) {")
			lines.append("\(indent)\(standardIndent)init() {}")
			lines.append("\(indent)}")
			lines.append("")
			parameterLines.append("\(bodyIndent)\(ReservedName.mockOverridesParameterName): \(ReservedName.mockOverridesTypeName) = .init()")
		}
		lines.append(contentsOf: signature.sharedValueDocumentationLines(indent: indent))
		lines.append("\(indent)\(mockAttributesPrefix)static func mock(")
		lines.append(parameterLines.joined(separator: ",\n"))
		lines.append("\(indent)) -> \(instantiable.concreteInstantiable.asSource) {")
		lines.append(contentsOf: bindingLines)
		let argumentList = instantiable.initializer.map { initializer in
			MockLowering.rootArgumentList(of: initializer, given: instantiable.dependencies, renames: rootRenames, passingNilTo: unavailableProperties)
		} ?? ""
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
	private static func overridesStruct(of fields: [MockLowering.OverridesField], onlyIfAvailableOverrides: [OnlyIfAvailableOverride], sendableConfigurationTypeNames: Set<String>, indent: String) -> [String] {
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
		var initParameters = zip(storage.fields, fields).map { storageField, field in
			"\(memberIndent)\(storageField.name.spelledAsAssigningParameter(labeled: storageField.name)): \(storageField.typeSource) = \(field.defaultValue)"
		}
		// D1 lane hook (lane B): each override of what the mock receives only if available, after the storage's fields and
		// stored beside the storage (`generateSafeDIOverridesStruct`).
		for override in onlyIfAvailableOverrides {
			initParameters.append("\(memberIndent)\(override.name.spelledAsAssigningParameter(labeled: override.name)): \(override.typeDescription.asSource) = nil")
		}
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		if !storage.fields.isEmpty {
			lines.append(contentsOf: storage.initialization(to: storage.fields.map(\.name.spelledAsAssigningParameterName), indent: memberIndent))
		}
		for override in onlyIfAvailableOverrides {
			lines.append("\(memberIndent)self.\(override.name) = \(override.name.spelledAsAssigningParameterName)")
		}
		lines.append("\(innerIndent)}")
		lines.append("")
		lines.append(contentsOf: storage.readers(indent: innerIndent))
		for override in onlyIfAvailableOverrides {
			lines.append("\(innerIndent)let \(override.name.spelledAsMemberDeclarationName): \(override.typeDescription.asSource)")
		}
		if !storage.fields.isEmpty {
			lines.append("")
			lines.append(contentsOf: storage.declarations(indent: innerIndent))
		}
		lines.append("\(indent)}")
		return lines
	}
}

extension MockLowering {
	/// The state of one root's walk: the types and labels built around the node it is at, and the labels its level binds
	/// so far. A label bound again on another branch is bound in another builder function, apart from this one.
	struct Walk {
		/// The global back edges of the module's mock graphs, beneath which a node reads no override.
		let cycleEdges: Set<ScopeGenerator.CycleEdge>
		/// The nodes built around the node the walk is at, each as `ScopeGenerator.MockParameterNode.cycleNodeKey` spells it:
		/// a node that repeats one reads no override of its own.
		var ancestorTypes = Set<String>()
		/// The concrete type of the node whose children the walk is at, or `nil` at the mock's root.
		var parentConcreteType: String?
		/// Whether the overrides of the node whose children the walk is at are reachable: no edge above it is in `cycleEdges`.
		var overridePathReachable = true
		/// The labels `mock()` binds before its tree, which no node may bind again.
		let rootLabels: Set<String>
		/// The names `mock()` binds its overrides of what its tree receives only if available under, which a builder
		/// function beneath the root may declare again: the emitter names an override apart only at the root's level.
		var rootOverrideNames = Set<String>()
		/// The names no alias at the walk's level may bind again: `rootLabels`, but for the overrides' beneath the root.
		var labelsNoAliasBindsAgain: Set<String> {
			bodyLabels.isEmpty ? rootLabels : rootLabels.subtracting(rootOverrideNames)
		}

		/// The declarations built around the node the walk is at, by label, innermost last: a node of a label one of them
		/// has binds it again in its own builder function, which hides the farther one, as Swift's lookup does.
		var ancestorDeclarationsByLabel = [String: [(declaration: ScopeGenerator.BuiltDeclaration, functionName: String, bodyLevel: Int)]]()
		/// The labels of the children of each builder function's body the walk is inside, outermost first: a builder
		/// function a body between a cycle closer and the node it repeats declares under that node's label would hide the
		/// node's function from the closer.
		var bodyLabels = [Set<String>]()
		/// The names a receive is handed in place of its label, by label and then type: a node named apart from a sibling
		/// that shares its label (`ScopeGenerator.disambiguatePropertyLabels(for:)`), which its receivers bind again under
		/// the label in their builder functions, until a declaration of the label hides it.
		// D1 lane hook (lane D): the flat parameters and overrides of `mock()` named apart, which seed it.
		var renames = [String: [TypeDescription: String]]()
		/// The names the mock root's level gives the nodes it names apart, which no builder function beneath may declare.
		var rootNamesApart = Set<String>()
		/// The names the mock root's level gives the nodes it names apart, by label and then type, under which the mocked type
		/// is passed them.
		var rootRenames = [String: [TypeDescription: String]]()
		/// The names of the parameters of `mock()` named apart that uncovered dependencies are, by label and type.
		var uncoveredParameterNames = [String: [TypeDescription: String]]()
		/// The names the property nodes of the mock root's level are bound under.
		var rootPropertyNodeBindingNames = Set<String>()
		/// The labels the mock root's level names its nodes apart under.
		var rootLabelsNamedApart = Set<String>()
		/// The labels of the dependencies the tree receives that the mock cannot build, which an alias of the mock root's
		/// level is named apart from.
		var rootFlatReceivedLabels = Set<String>()
		/// The names the mock root's level gives the aliases it names apart, which no builder function beneath may declare.
		var rootAliasNamesApart = Set<String>()
		/// The properties of `mock()`'s forwarded and default-valued parameters, which keep their labels: a node of the mock
		/// root's level under one of their labels is named apart from them
		/// (`ScopeGenerator.disambiguatePropertyLabels(for:besideParametersKeepingTheirLabels:reservedNames:)`).
		var rootParametersKeepingTheirLabels = [Property]()
		/// The properties of the mock root's level named apart from a parameter that keeps its label, which may bind a name
		/// apart from a label `mock()` binds.
		var rootPropertiesNamedApartFromParameters = Set<Property>()
		/// The labels of the dependencies of every node the walk built, which a builder function beneath the root binds.
		var dependencyLabelsInTree = Set<String>()
		var labels = Set<String>()
		// D1 lane hook (lane D): the `@Instantiated` dependencies the mock cannot build, each a parameter of `mock()`.
		/// The properties of the `@Instantiated` dependencies the mock cannot build, which `mock()` takes, so the types that
		/// instantiate them are passed the parameter.
		var uncoveredProperties = Set<Property>()
		// D1 lane hook (lane D): the configurations of the nodes the walk finished, children before their node.
		var configurationRecords = [ConfigurationRecord]()
		/// The default-valued parameters of each type's hand-written mock, by concrete type, whose defaults the fields of the
		/// type's configuration take (`MockLowering+Defaults.swift`).
		var handWrittenMockDefaultParameters = [TypeDescription: [ScopeGenerator.MockParameterNode.DefaultParameter]]()
		/// The concrete types whose configurations are `@Sendable`-typed, whose default fields are read as calls.
		var sendableConfigurationTypeNames = Set<String>()
		/// The concrete types of the configured nodes around the node the walk is at, and whether a node around it repeats one
		/// around it: a node of a type around it, or beneath such a node, records no configuration
		/// (`ScopeGenerator.collectUniqueConfigurationTypes`).
		var configuredAncestorTypes = Set<String>()
		var isBeneathRepeatedConfiguredAncestor = false
		// D1 lane hook (lane D): how many configured nodes' children the walk entered, which orders the one-way check's reads.
		var configuredNodesEntered = 0
		// D1 lane hook (lane C): the builders `mock()` takes optional for the places its calls fill, and the calls not reached yet.
		var filledCallBuilders = FilledCallBuilders.none
		// D1 lane hook (lane C): a public mock builds each configured node with its type's construction function.
		/// Whether the walk lowers a public mock, whose configured nodes call their types' construction functions.
		var buildsPublicMock = false
		// D1 lane hook (lane C): the bindings the node around the walk is passed by name, which a payload bound inside its
		// builder function reads (`ScopeGenerator.MockParameterNode.ValuesBinding.line`).
		var enclosingBindingNamesPassedByName = [String: String]()
		// D1 lane hook (lane C): the properties of the nodes a public mock promotes at its root's level, each bound from the
		// parameter its caller passes, named as the node's binding (`MockLowering+PublicMocks.swift` checks the name).
		var promotedProperties = Set<Property>()
		// D1 lane hook (lane B): the extractor of the `@Sendable` builder function the walk is inside, and the names of each
		// level it is in, from which such a function's locals are claimed (`MockLowering+Wrappers.swift`).
		var sendableOverrideExtractor: ScopeGenerator.SendableOverrideExtractor?
		var levelNames = [GeneratedNameAllocator]()
		/// Whether the walk is inside a `@Sendable` builder function, whose nodes' override closures are `@Sendable`.
		var isInsideSendableFunction = false
		// D1 lane hook (lane B): the loop of builders the node being built is a member of, the members of its level's loops,
		// the loop being emitted at the level, and how the last member's lines split (`MockLowering+Loops.swift`).
		var loopMembership: LoopMembership?
		var loopMembers = [Property: LoopMember]()
		var loopUnit: LoopUnit?
		var lastLoopMemberLineCounts: LoopMemberLineCounts?
		/// The receives only if available the node being lowered is passed `nil` for, given the siblings built before it.
		var unavailableProperties = Set<Property>()
		/// The properties built after the node being lowered, which its children are ordered by.
		var propertiesGeneratedLater = Set<Property>()

		/// The nodes `generators` build, in generation order, where the nodes `scope` holds are bound before them, their
		/// overrides at `path`, with their statements appended to `lines` at `indent`; or the first rule they meet.
		mutating func children(
			of orderedChildren: [ScopeGenerator.OrderedChild],
			loops: [LoopMembership?] = [],
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async -> Lowering<[TreeNode]> {
			let generators = orderedChildren.map(\.generator)
			let enclosingPropertiesGeneratedLater = propertiesGeneratedLater
			defer { propertiesGeneratedLater = enclosingPropertiesGeneratedLater }
			var nodes = [TreeNode]()
			var scope = scope
			var bindingNames: [String?]
			switch levelBindingNames(of: generators) {
			case let .lowered(lowered):
				bindingNames = lowered
			case let .unsupported(rule):
				return .unsupported(rule)
			}
			if bodyLabels.isEmpty {
				nameRootAliasesApart(among: generators, bindingNames: &bindingNames)
			}
			// Every node of the level and beneath it reads the level's names apart, until a declaration hides one.
			let enclosingRenames = renames
			defer { renames = enclosingRenames }
			for (generator, bindingName) in zip(generators, bindingNames) {
				guard let bindingName, let property = generator.property, bindingName != property.label else { continue }
				renames[property.label, default: [:]][property.typeDescription] = bindingName
			}
			if bodyLabels.isEmpty {
				rootRenames = renames
				// D1 lane hook (lane B): the names the root's property nodes are bound under, which a rebinding of the mocked
				// type's own receive would redeclare.
				for (generator, bindingName) in zip(generators, bindingNames) {
					guard case .property = generator.scopeData, let bindingName else { continue }
					rootPropertyNodeBindingNames.insert(bindingName)
				}
			}
			// D1 lane hook (lane B): the level's names, which a `@Sendable` builder function's locals are kept apart from.
			enterLevel(of: generators, boundAs: bindingNames)
			defer { leaveLevel() }
			// D1 lane hook (lane B): the loops of builders among the level's children, each emitted as one unit.
			let enclosingLoopMembers = loopMembers
			let enclosingLoopUnit = loopUnit
			// The enclosing functions a cycle-closing node beneath refers to by name are in scope too.
			loopMembers = MockLowering.loopMembers(among: generators, loops: loops, bindingNames: bindingNames, namesInScope: Set(ancestorDeclarationsByLabel.values.flatMap { $0.map(\.functionName) }))
			loopUnit = nil
			defer {
				loopMembers = enclosingLoopMembers
				loopUnit = enclosingLoopUnit
			}
			for (index, (generator, bindingName)) in zip(generators, bindingNames).enumerated() {
				let membership = index < loops.count ? loops[index] : nil
				loopMembership = membership
				// D1 lane hook (lane B): what the node is built where its siblings ordered after it are not bound yet, as
				// the emitter orders the level (`ScopeGenerator.OrderedChild`).
				unavailableProperties = orderedChildren[index].unavailableProperties
				propertiesGeneratedLater = orderedChildren[index].propertiesGeneratedLater
				var memberLines = [String]()
				// D1 lane hook: kinds of node (instantiators, wrappers, aliases, holes, calls).
				let lowering: Lowering<TreeNode>
				if membership == nil {
					endLoopUnit(appendingTo: &lines)
					lowering = await node(of: generator, bindingName: bindingName, inScope: scope, path: path, indent: indent, lines: &lines)
				} else if case .property = generator.scopeData, generator.publicMockCall == nil {
					lowering = await node(of: generator, bindingName: bindingName, inScope: scope, path: path, indent: indent, lines: &memberLines)
				} else if case .alias = generator.scopeData {
					// D1 lane hook (lane B): a rename the level declares of a member is bound with the loop's wrappers, after
					// them, and its members' functions bind it again (`MockLowering.loopMembers`).
					lowering = await node(of: generator, bindingName: bindingName, inScope: scope, path: path, indent: indent, lines: &memberLines)
					lastLoopMemberLineCounts = MockLowering.LoopMemberLineCounts(prelude: 0, binding: memberLines.count)
				} else {
					// D1 lane hook (lane B): a call of another module's public mock on a loop.
					lowering = .unsupported(.cycle)
				}
				loopMembership = nil
				switch lowering {
				case let .lowered(node):
					nodes.append(node)
					scope.insert(node.property)
				case let .unsupported(rule):
					return .unsupported(rule)
				}
				if let membership {
					append(memberLines, ofMemberOf: membership, to: &lines)
				}
			}
			endLoopUnit(appendingTo: &lines)
			return .lowered(nodes)
		}

		/// The name each of `generators`, one level's nodes, is bound under, `nil` for a node that is no property node: its
		/// label, or, where property nodes of the level share it, a name apart, as
		/// `ScopeGenerator.disambiguatePropertyLabels(for:)` names it; or the first rule the naming meets.
		private mutating func levelBindingNames(of generators: [ScopeGenerator]) -> Lowering<[String?]> {
			let propertyNodes: [Property?] = generators.map { generator in
				guard case let .property(_, property, _, _, _, _) = generator.scopeData else { return nil }
				return property
			}
			var seenLabels = Set<String>()
			var collidingLabels = Set<String>()
			for case let property? in propertyNodes where !seenLabels.insert(property.label).inserted {
				collidingLabels.insert(property.label)
			}
			// The mock root's level names its nodes apart from the parameters that keep their labels too.
			let parametersKeepingTheirLabels = bodyLabels.isEmpty ? rootParametersKeepingTheirLabels : []
			let parameterLabels = Set(parametersKeepingTheirLabels.map(\.label))
			let collidingParameterLabels = parameterLabels.intersection(seenLabels)
			collidingLabels.formUnion(collidingParameterLabels)
			guard !collidingLabels.isEmpty else { return .lowered(propertyNodes.map { $0?.label }) }
			// D1 lane hook (lane B): inside a `@Sendable` builder function, the extractor reserved the functions this level
			// declares under their labels before the level was named.
			guard sendableOverrideExtractor == nil else { return .unsupported(.siblingLabelCollision) }
			let collidingProperties = propertyNodes.compactMap { property in property.flatMap { collidingLabels.contains($0.label) ? $0 : nil } }
			// Two nodes of one label and type are one entry of the emitter's map, which names both alike.
			guard Set(collidingProperties).count == collidingProperties.count else { return .unsupported(.siblingLabelCollision) }
			let names = ScopeGenerator.identifierSafeNames(
				for: collidingProperties.map { property in
					let instantiatedType = property.typeDescription.asInstantiatedType
					return (label: property.label, suffixTypes: [instantiatedType.simplified, instantiatedType, property.typeDescription])
				},
				besideEntriesKeepingTheirNames: parametersKeepingTheirLabels.compactMap { parameter in
					guard collidingLabels.contains(parameter.label) else { return nil }
					let instantiatedType = parameter.typeDescription.asInstantiatedType
					return (label: parameter.label, suffixTypes: [instantiatedType.simplified, instantiatedType, parameter.typeDescription])
				},
				reservedNames: seenLabels.subtracting(collidingLabels).union(parameterLabels),
			)
			let nameByProperty = Dictionary(zip(collidingProperties, names), uniquingKeysWith: { first, _ in first })
			// D1 lane hook (lane D): the mock root's level names its nodes apart from every name a builder function beneath
			// declares.
			if bodyLabels.isEmpty {
				guard rootLabels.isDisjoint(with: names), rootLabels.intersection(collidingLabels).isSubset(of: collidingParameterLabels) else { return .unsupported(.siblingLabelCollision) }
				rootNamesApart.formUnion(names)
				rootLabelsNamedApart.formUnion(collidingLabels)
				rootPropertiesNamedApartFromParameters.formUnion(collidingProperties.filter { collidingParameterLabels.contains($0.label) })
			}
			return .lowered(propertyNodes.map { property in property.map { nameByProperty[$0] ?? $0.label } })
		}

		/// Names apart each alias of the mock root's level, among `generators`, whose label a property node of the level, or a
		/// flat received parameter of `mock()`, binds, as `ScopeGenerator.renamingAliases` does: `<label>_<simplified type>`,
		/// `_` appended while the name is taken, set as the alias's entry of `bindingNames`.
		private mutating func nameRootAliasesApart(among generators: [ScopeGenerator], bindingNames: inout [String?]) {
			let propertyNodeNames = Set(zip(generators, bindingNames).compactMap { generator, bindingName in
				generator.mockLoweringBuiltProperty == nil ? nil : bindingName
			})
			let aliases: [(index: Int, property: Property)] = generators.enumerated().compactMap { index, generator in
				guard case let .alias(property, _, _, _, _) = generator.scopeData else { return nil }
				return (index, property)
			}
			let redeclaredNames = propertyNodeNames.union(rootFlatReceivedLabels)
			var takenNames = propertyNodeNames.union(rootLabels).union(aliases.map(\.property.label))
			for alias in aliases where redeclaredNames.contains(alias.property.label) {
				var name = "\(alias.property.label)_\(alias.property.typeDescription.simplified.asIdentifier)".spelledAsJoinedIdentifier
				while !takenNames.insert(name).inserted {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				bindingNames[alias.index] = name
				rootAliasNamesApart.insert(name)
			}
		}

		/// The node of `generator`, built after the nodes `scope` holds, whose statements are appended to `lines`, or the
		/// first rule it meets.
		private mutating func node(
			of generator: ScopeGenerator,
			bindingName: String?,
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async -> Lowering<TreeNode> {
			if case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference) = generator.scopeData {
				// D1 lane hook: aliases only if available, of a wrapper's instance, and bound apart from their label.
				// D1 lane hook (lane B): an alias only if available is bound to `nil` where its fulfilling property is
				// unavailable, as production binds it (`ScopeGenerator.aliasIsBoundToNil`), and otherwise from the property in
				// scope; one the mock's root provides reads an override, which the walk does not lower yet.
				let isBoundToNil = ScopeGenerator.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: unavailableProperties)
				guard isBoundToNil || scope.contains(fulfillingProperty) else { return .unsupported(onlyIfAvailable ? .onlyIfAvailable : .alias) }
				// An alias of a label named apart reads the name it is handed; one the mock root's level names apart is bound
				// under its name.
				let aliasBindingName = bindingName ?? property.label
				guard aliasBindingName != property.label || !labelsNoAliasBindsAgain.contains(property.label), labels.insert(aliasBindingName).inserted else { return .unsupported(.siblingLabelCollision) }
				let alias = AliasBinding(
					property: property,
					bindingName: aliasBindingName,
					fulfillingProperty: fulfillingProperty,
					fulfillingName: renames[fulfillingProperty.label]?[fulfillingProperty.typeDescription] ?? fulfillingProperty.label,
					isErased: erasedToConcreteExistential,
					isOnlyIfAvailable: onlyIfAvailable,
					isBoundToNil: isBoundToNil,
					declarationReference: declarationReference,
				)
				lines.append(alias.bindingLines(indent: indent))
				return .lowered(.alias(alias))
			} else {
				// D1 lane hook (lane C): a hole site and a fill, the kinds of node a public mock's tree holds besides properties
				// and aliases, and a call of another module's public mock (`MockLowering+PublicMocks.swift`).
				guard case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall) = generator.scopeData,
				      let bindingName
				else { return await placeOrFillNode(of: generator, inScope: scope, path: path, indent: indent, lines: &lines) }
				guard generator.publicMockCall == nil else {
					// D1 lane hook (lane C): a public mock binds the payload of a case of a place inside the call's fills before the
					// call's builder function, as before any node's.
					lines.append(contentsOf: generator.valuesBindingsBeforeBuilderFunction.map { "\(indent)\($0.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: [:]))" })
					return await publicMockCallNode(of: generator, inScope: scope, path: path, indent: indent, lines: &lines)
				}
				guard !isPropertyCycle else {
					return cycleClosingNode(of: generator, instantiable: instantiable, property: property, bindingName: bindingName, seamCall: seamCall, inScope: scope, indent: indent, lines: &lines)
				}
				switch await builtNode(
					of: generator,
					building: (instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall),
					boundAs: bindingName,
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

		/// Whether a node of `concreteType` beneath a node of `parentConcreteType` is beneath an edge in `cycleEdges`: its
		/// parent's configuration has no field for it, so neither it nor anything beneath it reads an override. The one
		/// question the walk asks of the cycle edges.
		func isPruned(_ concreteType: TypeDescription, beneath parentConcreteType: String?) -> Bool {
			parentConcreteType.map { cycleEdges.contains(ScopeGenerator.CycleEdge(parent: $0, child: concreteType.asSource)) } ?? false
		}

		/// The node of `generator`, which closes a cycle on a node around it of `property`, built as `instantiable`, whose
		/// statement is appended to `lines`: it calls that node's builder function, or hands it to its wrapper, and reads no
		/// override, since the function reads the node's.
		private mutating func cycleClosingNode(
			of generator: ScopeGenerator,
			instantiable: Instantiable,
			property: Property,
			bindingName: String,
			seamCall: SeamCall?,
			inScope scope: Set<Property>,
			indent: String,
			lines: inout [String],
		) -> Lowering<TreeNode> {
			// The node is the nearest declaration of the label around the closer, and no body between the two declares
			// another node of it, so the closer reads the node's function by the name it is built with: its label's, or the
			// name the node's level names it apart by (`BuilderFunctionNames.enclosingFunctionNames`). A lazy wrapper closes
			// on a constant declaration of its instance, and a constant on a lazy wrapper's, by the same function.
			guard seamCall == nil,
			      generator.closedOnDeclaration?.concreteType == instantiable.concreteInstantiable,
			      let closedOn = ancestorDeclarationsByLabel[property.label]?.last,
			      closedOn.declaration == generator.closedOnDeclaration,
			      !bodyLabels[closedOn.bodyLevel..<(bodyLabels.count - 1)].contains(where: { $0.contains(property.label) })
			else { return .unsupported(.cycle) }
			let forwardedProperties = instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label }
			// D1 lane hook (lane B): a closer of any wrapper kind hands the function to its wrapper, inside a `@Sendable`
			// builder function too, since it reads no override.
			guard !property.propertyType.isConstant || forwardedProperties.isEmpty else { return .unsupported(.wrapper) }
			guard labels.insert(bindingName).inserted else { return .unsupported(.siblingLabelCollision) }
			// D1 lane hook (lane B): a closer passes the function's cycle parameters (`MockLowering+CycleParameters.swift`).
			guard let cycleParameterArguments = MockLowering.cycleParameterArguments(of: generator, inScope: scope, renames: renames) else { return .unsupported(.onlyIfAvailable) }
			// D1 lane hook (lane B): a closer on a loop of builders declares the `_received` function its wrappers hand, with
			// the loop's functions, and is bound with the loop's wrappers where its level binds it (`MockLowering+Loops.swift`).
			if let loopMembership, let member = loopMembers[property] {
				let receivedFunctionLines = MockLowering.receivedFunctionLines(
					of: member,
					property: property,
					cycleParameterArguments: cycleParameterArguments,
					among: loopMembers,
					typesDeclaredEscaping: generator.typesDeclaredEscaping,
					isSendable: generator.buildsInSendableFunction || property.propertyType.isSendable,
					indent: indent,
				)
				let bindingLines = loopMembership.declaresBinding
					? MockLowering.bindingLines(of: property, boundAs: bindingName, callingFunctionNamed: member.functionName, forwardedProperties: forwardedProperties, indent: indent)
					: []
				lines.append(contentsOf: receivedFunctionLines + bindingLines)
				lastLoopMemberLineCounts = LoopMemberLineCounts(prelude: 0, binding: bindingLines.count)
				return .lowered(.cycleClosing(property, bindingName: bindingName, concreteType: instantiable.concreteInstantiable))
			}
			lines.append(contentsOf: MockLowering.bindingLines(
				of: property,
				boundAs: bindingName,
				callingFunctionNamed: closedOn.functionName,
				forwardedProperties: forwardedProperties,
				cycleParameterArguments: cycleParameterArguments,
				indent: indent,
			))
			return .lowered(.cycleClosing(property, bindingName: bindingName, concreteType: instantiable.concreteInstantiable))
		}

		/// The node of `generator`, which builds `built`, whose statements are appended to `lines`, or the first rule it
		/// meets: its override when set, else its construction, in a builder function where it builds children.
		private mutating func builtNode(
			of generator: ScopeGenerator,
			building built: (instantiable: Instantiable, property: Property, forwardedProperties: Set<Property>, erasedToConcreteExistential: Bool, isPropertyCycle: Bool, seamCall: SeamCall?),
			boundAs bindingName: String,
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async -> Lowering<ConstantNode> {
			let (instantiable, property, forwardedProperties, erasedToConcreteExistential, _, seamCall) = built
			// A mock builds every seam inline, so no scope of its tree calls one.
			guard seamCall == nil else { return .unsupported(.publicMockCall) }
			let cycleNodeKey = MockLowering.cycleNodeKey(of: property, builtAs: instantiable)
			// A node that repeats a node around it reads no override of its own, and one beneath an edge in `cycleEdges`
			// reads none of its own or beneath it: its parent's configuration has no field for it.
			let isCycleNode = ancestorTypes.contains(cycleNodeKey)
			let overrideReachable = overridePathReachable && !isPruned(instantiable.concreteInstantiable, beneath: parentConcreteType)
			let isErased = erasedToConcreteExistential
			let isFulfilledByAnotherType = property.typeDescription.asInstantiatedType != instantiable.concreteInstantiable
			// D1 lane hook (lane B): every wrapper kind builds its type in a builder function, as an `Instantiator` does,
			// erased or fulfilled by another type alike (`MockLowering+Wrappers.swift`).
			let isWrapped = !property.propertyType.isConstant
			guard isWrapped || forwardedProperties.isEmpty else { return .unsupported(.wrapper) }
			let forwarded = instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label }
			// D1 lane hook (lane B): a receive only if available the node is built where nothing provides is passed `nil`.
			// A member of a loop of builders is passed the wrappers its function makes again, as production passes them
			// (`ownUnavailableProperties` in `ScopeGenerator`).
			let unavailableProperties = generator.reboundProperties.isEmpty ? unavailableProperties : unavailableProperties.subtracting(generator.reboundProperties.flatMap(CycleParameter.forms(providedBy:)))
			// D1 lane hook (lane D): a node whose type's hand-written mock returns a type its property can hold is built with the
			// mock, as `MockConstruction(useMockInitializer:)` says, where the mock returns the concrete type, in an internal mock.
			let usesMockInitializer = instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType)
			// An argument of the mock neither a dependency fulfills nor a default fills is passed what a build that compiles
			// no mock never compiles (`UnfulfilledMockParameter`).
			// D1 lane hook (lane C): a public mock builds such a node with its construction function, as an internal mock does
			// with the mock (`publicConstructionArguments`).
			guard let initializer = usesMockInitializer ? instantiable.mockInitializer : instantiable.initializer,
			      !usesMockInitializer || instantiable.mockCallReturnType == instantiable.concreteInstantiable,
			      initializer.arguments.allSatisfy({ argument in argument.hasDefaultValue || instantiable.dependencies.contains(where: argument.isFulfilled(by:)) })
			else { return .unsupported(.handWrittenMock) }
			guard !rootLabels.contains(property.label) || (bindingName != property.label && rootPropertiesNamedApartFromParameters.contains(property)), labels.insert(bindingName).inserted else { return .unsupported(.siblingLabelCollision) }
			dependencyLabelsInTree.formUnion(instantiable.dependencies.map(\.property.label))

			let orderedChildren = generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: propertiesGeneratedLater)
			let childGenerators = orderedChildren.map(\.generator)
			// D1 lane hook (lane B): a member of a loop of builders first rebinds the members its tree receives
			// (`MockLowering+Loops.swift`).
			var rebindingLines = [String]()
			// The walk of the node's children sets and clears the membership of each child.
			let ownLoopMembership = loopMembership
			if ownLoopMembership != nil {
				guard isWrapped,
				      var memberRebindingLines = MockLowering.rebindingLines(of: generator.reboundProperties, among: loopMembers, ownProperty: property, indent: "\(indent)\(ScopeGenerator.standardIndent)")
				else { return .unsupported(.cycle) }
				// D1 lane hook (lane C): a member a public mock promotes at its root is rebound as the caller's own where it passed
				// one.
				if parentConcreteType == nil, generator.reboundProperties.contains(where: promotedProperties.contains) {
					memberRebindingLines = []
					for reboundProperty in generator.reboundProperties {
						guard let member = loopMembers[reboundProperty] else { return .unsupported(.cycle) }
						if promotedProperties.contains(reboundProperty), member.rename == nil, reboundProperty != property || member.receivedFunctionName == nil {
							memberRebindingLines.append(MockLowering.promotedWrapperBindingLine(of: member.typeDescription, named: member.bindingName, passing: member.bindingName, handing: member.functionName, forwardedProperties: member.forwardedProperties, indent: "\(indent)\(ScopeGenerator.standardIndent)"))
						} else {
							guard let lines = MockLowering.rebindingLines(of: [reboundProperty], among: loopMembers, ownProperty: property, indent: "\(indent)\(ScopeGenerator.standardIndent)") else { return .unsupported(.cycle) }
							memberRebindingLines.append(contentsOf: lines)
						}
					}
				}
				rebindingLines = memberRebindingLines
			}
			// D1 lane hook (lane B): what the node's binding passes its builder function's cycle parameters, read where the node
			// is built, and the parameters, the nearest declarations of their labels in the function.
			guard let cycleParameterArguments = MockLowering.cycleParameterArguments(of: generator, inScope: scope, renames: renames) else { return .unsupported(.onlyIfAvailable) }
			let scope = scope.union(generator.reboundProperties).union(MockLowering.cycleParameterForms(of: generator))
			// D1 lane hook (lane B): a `Sendable` wrapper's, or a cycle's, builder function is `@Sendable`, and every override
			// read inside it is read into a local before the outermost such function.
			let builder = ReservedName.configurationBuilderPropertyName
			// D1 lane hook (lane D): a default-valued parameter is a field of the node's configuration (`MockLowering+Defaults.swift`).
			let defaultFields: [DefaultField]
			switch configurationDefaultFields(of: instantiable, usesMockInitializer: usesMockInitializer, startsExtraction: sendableOverrideExtractor == nil && generator.buildsInSendableFunction) {
			case let .lowered(lowered):
				defaultFields = lowered
			case let .unsupported(rule):
				return .unsupported(rule)
			}
			let hasConfiguration = childGenerators.contains { $0.mockLoweringBuiltProperty != nil } || !defaultFields.isEmpty
			let nodePath = "\(path).\(bindingName)"
			// The node's builder function binds again under its label each receive named apart, from the names its own
			// declarations, its children, forwarded properties and cycle parameters, do not hide (`ScopeGenerator.removingRenames`).
			// D1 lane hook (lane B): nor do the dependencies its type instantiates that the mock cannot build, whose receives
			// beneath read the parameter `mock()` takes under its label (`routingReceives`).
			let uncoveredInstantiatedProperties = instantiable.dependencies.compactMap { dependency -> Property? in
				guard case .instantiated = dependency.source, uncoveredProperties.contains(dependency.property) else { return nil }
				return dependency.property
			}
			var functionRenames = MockLowering.removingRenames(
				hiddenBy: childGenerators.compactMap(\.property) + (isWrapped ? forwarded : []) + MockLowering.cycleParameterForms(of: generator).sorted() + uncoveredInstantiatedProperties,
				from: renames,
			)
			MockLowering.routeReceives(of: uncoveredInstantiatedProperties, toParametersNamed: uncoveredParameterNames, in: &functionRenames)
			var receiverBindings = [(property: Property, name: String)]()
			for dependency in instantiable.dependencies {
				// A receive the node passes `nil` is not rebound (`emitReceiverBindings`): the name may not be declared yet.
				guard case .received = dependency.source, !unavailableProperties.contains(dependency.property), let names = functionRenames[dependency.property.label] else { continue }
				if generator.mockLoweringLazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
					// A receive of a lazy wrapper's instance binds the wrapper named apart again, whose instance its
					// construction reads.
					let instanceType = dependency.property.typeDescription.unwrapped
					guard let wrapper = [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
						.lazy
						.map({ TypeDescription.simple(name: $0, generics: [instanceType]) })
						.compactMap({ wrapper in names[wrapper].map { (property: Property(label: dependency.property.label, typeDescription: wrapper), name: $0) } })
						.first
					else { continue }
					receiverBindings.append(wrapper)
				} else if let name = names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription] {
					receiverBindings.append((dependency.property, name))
				}
			}
			// A receive named apart whose label a receive beneath reads by name is handed the name instead of bound again
			// under its label, which would hide the binding that receive reads (`ScopeGenerator.receivedBindingNamesPassedByName`).
			var bindingNamesPassedByName = [String: String]()
			if !childGenerators.isEmpty {
				for binding in receiverBindings {
					switch MockLowering.receiveReadsLabelByName(binding.property.label, beneath: childGenerators, renames: renames) {
					case true?:
						bindingNamesPassedByName[binding.property.label] = binding.name
					case false?:
						break
					case nil:
						return .unsupported(.siblingLabelCollision)
					}
				}
				receiverBindings.removeAll { bindingNamesPassedByName[$0.property.label] != nil }
			}
			let overrideRead: String? = isCycleNode || !overrideReachable ? nil : readingOverride(
				hasConfiguration ? "\(nodePath).\(builder)" : nodePath,
				localNameSuffix: "\(GeneratedCodeText.overrideRelativePath(of: nodePath))_\(builder)",
			)
			var node = ConstantNode(
				property: property,
				bindingName: bindingName,
				instantiable: instantiable,
				hasChildren: !childGenerators.isEmpty || !rebindingLines.isEmpty,
				receiverBindings: receiverBindings,
				isWrapped: isWrapped,
				isErased: isErased,
				isFulfilledByAnotherType: isFulfilledByAnotherType,
				usesMockInitializer: usesMockInitializer,
				forwardedProperties: forwarded,
				typesDeclaredEscaping: generator.typesDeclaredEscaping,
				// D1 lane hook (lane D): each default-valued parameter read from the node's configuration, among its dependencies.
				arguments: constructionArguments(
					of: initializer,
					given: instantiable,
					usesMockInitializer: usesMockInitializer,
					dependencyArguments: MockLowering.argumentValues(
						of: initializer,
						given: instantiable.dependencies,
						lazilyInstantiatedInstanceProperties: generator.mockLoweringLazilyInstantiatedInstanceProperties,
						unavailableProperties: unavailableProperties,
						bindingNamesPassedByName: bindingNamesPassedByName,
						uncoveredParameterNames: uncoveredParameterNames,
					),
					nodePath: nodePath,
					overrideReachable: overrideReachable,
				),
				buildsInSendableFunction: generator.buildsInSendableFunction,
				requiresSendable: isInsideSendableFunction || generator.buildsInSendableFunction,
				defaultFields: defaultFields,
			)
			node.cycleParameters = generator.cycleParameters.map(\.property)
			// D1 lane hook (lane C): a node a public mock promotes at its root's level reads its caller's value first.
			if parentConcreteType == nil, promotedProperties.contains(property) {
				node.promotedParameterName = bindingName
			}
			node.cycleParameterArguments = cycleParameterArguments
			let lazilyInstantiatedInstanceProperties = generator.mockLoweringLazilyInstantiatedInstanceProperties
			// D1 lane hook (lane D): a node whose configuration holds its default-valued parameters is built in a builder
			// function, as `MockParameterNode.requiresFunctionWrapper` says.
			guard node.hasChildren || isWrapped || !receiverBindings.isEmpty || !defaultFields.isEmpty else {
				guard let rule = Self.unsupportedRule(ofDependenciesOf: instantiable, isWrapped: isWrapped, inScope: scope, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties, unavailableProperties: unavailableProperties, childProperties: [], uncoveredProperties: uncoveredProperties) else {
					lines.append(node.constantBindingLine(overrideRead: overrideRead, indent: indent))
					return .lowered(node)
				}
				return .unsupported(rule)
			}
			let startsExtraction = sendableOverrideExtractor == nil && generator.buildsInSendableFunction
			let enclosingExtractor = startsExtraction ? startExtraction(inFunctionNamed: node.functionName) : sendableOverrideExtractor
			let wasInsideSendableFunction = isInsideSendableFunction
			isInsideSendableFunction = node.requiresSendable
			// D1 lane hook (lane C): the payloads of the cases nested by type that lead through the node to a place, bound before
			// its builder function, after a wrapper's override locals and before a constant's, and the members a `@Sendable`
			// function calls at its top (`MockLowering+PublicMocks.swift`).
			let valuesBindingLines = generator.valuesBindingsBeforeBuilderFunction.map { "\(indent)\($0.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: [:]))" }
			if !isWrapped {
				lines.append(contentsOf: valuesBindingLines)
			}
			let declarationIndex = lines.count
			if isWrapped {
				lines.append(contentsOf: valuesBindingLines)
			}
			lines.append(node.builderFunctionDeclarationLine(indent: indent))
			lines.append(contentsOf: generator.memberCallsInsideBuilderFunction.map { "\(indent)\(ScopeGenerator.standardIndent)\($0.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: [:]))" })
			lines.append(contentsOf: rebindingLines)
			lines.append(contentsOf: node.receiverBindingLines(indent: indent))
			let insertedAncestor = ancestorTypes.insert(cycleNodeKey).inserted
			ancestorDeclarationsByLabel[property.label, default: []].append((ScopeGenerator.BuiltDeclaration(property: property, concreteType: instantiable.concreteInstantiable), functionName: node.functionName, bodyLevel: bodyLabels.count))
			bodyLabels.append(Set(childGenerators.compactMap(\.property?.label)))
			let siblingLabels = labels
			labels = []
			let enclosingParentConcreteType = parentConcreteType
			let enclosingOverridePathReachable = overridePathReachable
			let enclosingRenames = renames
			renames = functionRenames
			let bindingNamesPassedByNameAround = enclosingBindingNamesPassedByName
			enclosingBindingNamesPassedByName = bindingNamesPassedByName
			parentConcreteType = instantiable.concreteInstantiable.asSource
			overridePathReachable = overrideReachable
			// D1 lane hook (lane D): the configured types around the node's children.
			let configurationEntry = enteringConfiguredNode(of: instantiable.concreteInstantiable)
			let lowering = await children(
				of: orderedChildren,
				loops: generator.mockLoweringLoopMemberships,
				inScope: scope.union(forwarded),
				path: nodePath,
				indent: "\(indent)\(ScopeGenerator.standardIndent)",
				lines: &lines,
			)
			leavingConfiguredNode(configurationEntry)
			parentConcreteType = enclosingParentConcreteType
			overridePathReachable = enclosingOverridePathReachable
			renames = enclosingRenames
			enclosingBindingNamesPassedByName = bindingNamesPassedByNameAround
			labels = siblingLabels
			ancestorDeclarationsByLabel[property.label]?.removeLast()
			bodyLabels.removeLast()
			if insertedAncestor {
				ancestorTypes.remove(cycleNodeKey)
			}
			isInsideSendableFunction = wasInsideSendableFunction
			let children: [TreeNode]
			switch lowering {
			case let .lowered(lowered):
				children = lowered
			case let .unsupported(rule):
				return .unsupported(rule)
			}
			if let rule = Self.unsupportedRule(ofDependenciesOf: instantiable, isWrapped: isWrapped, inScope: scope, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties, unavailableProperties: unavailableProperties, childProperties: Set(children.map(\.property)), uncoveredProperties: uncoveredProperties) {
				return .unsupported(rule)
			}
			// The construction is inside the function, so a function that starts the extraction reads its own override
			// into a local too, after its children's.
			let functionOverrideRead = startsExtraction ? overrideRead.map { readingOverride($0, localNameSuffix: builder) } : overrideRead
			let preludeLines = startsExtraction ? endExtraction(restoring: enclosingExtractor, indent: indent) : []
			lines.insert(contentsOf: preludeLines, at: declarationIndex)
			let configuredNode = node.configured(byChildren: children)
			let oneWayParentConcreteType = parentConcreteType
			// D1 lane hook (lane D): a node whose type repeats a configured node around it, or beneath one, records nothing.
			if configuredNode.hasConfiguration, configurationEntry.recordsConfiguration {
				let parentConcreteType = instantiable.concreteInstantiable.asSource
				// A child beneath an edge in `cycleEdges` has no member in its parent's configuration, public or internal.
				let recordedChildren = children.filter { child in child.concreteType.map { !isPruned($0, beneath: parentConcreteType) } ?? true }
				var record = ConfigurationRecord(of: configuredNode, children: recordedChildren)
				// D1 lane hook (lane D): the construction the one-way check reads, with every child, pruned or not.
				record.oneWayConstruction = OneWayConstruction(
					of: configuredNode,
					children: children,
					parentConcreteType: oneWayParentConcreteType,
					isBeneathCycleEdge: !overrideReachable,
					walkOrder: configurationEntry.walkOrder,
				)
				// D1 lane hook (lane C): a public mock's node records the construction its type's construction function makes.
				if buildsPublicMock {
					record.publicConstruction = MockLowering.publicConstructionRecord(of: configuredNode, children: recordedChildren, orderedBy: generator)
				}
				configurationRecords.append(record)
			}
			// D1 lane hook (lane C): a public mock's configured node calls its type's construction function.
			var endLines: [String]
			if buildsPublicMock, configuredNode.hasConfiguration {
				switch configuredNode.publicBuilderFunctionEndLines(children: children, overrideRead: functionOverrideRead, indent: indent) {
				case let .lowered(lowered):
					endLines = lowered
				case let .unsupported(rule):
					return .unsupported(rule)
				}
			} else {
				endLines = configuredNode.builderFunctionEndLines(overrideRead: functionOverrideRead, indent: indent)
			}
			if let loopMembership = ownLoopMembership, let member = loopMembers[property] {
				// The construction and the function's closing brace, then the member's `_received` function, then its binding,
				// which hands that function, where its level binds it.
				let bindingLines = loopMembership.declaresBinding
					? member.receivedFunctionName == nil
					? Array(endLines.dropFirst(2))
					: configuredNode.promotedParameterName.map { [MockLowering.promotedWrapperBindingLine(of: property.typeDescription, named: bindingName, passing: $0, handing: member.functionName, forwardedProperties: member.forwardedProperties, indent: indent)] }
					?? MockLowering.wrapperBindingLines(of: property.typeDescription, named: bindingName, handing: member.functionName, forwardedProperties: member.forwardedProperties, indent: indent)
					: []
				endLines = Array(endLines.prefix(2))
				endLines.append(contentsOf: MockLowering.receivedFunctionLines(
					of: member,
					property: property,
					cycleParameterArguments: cycleParameterArguments,
					among: loopMembers,
					typesDeclaredEscaping: generator.typesDeclaredEscaping,
					isSendable: generator.buildsInSendableFunction || property.propertyType.isSendable,
					indent: indent,
				))
				endLines.append(contentsOf: bindingLines)
				// D1 lane hook (lane C): a member's payloads are bound in its prelude, before every member's function.
				lastLoopMemberLineCounts = LoopMemberLineCounts(prelude: preludeLines.count + (isWrapped ? valuesBindingLines.count : 0), binding: bindingLines.count)
			}
			lines.append(contentsOf: endLines)
			return .lowered(configuredNode)
		}

		/// The first rule a dependency of `instantiable`, built after the nodes `scope` holds and from its children's
		/// `childProperties`, meets that the walk does not lower yet.
		private static func unsupportedRule(
			ofDependenciesOf instantiable: Instantiable,
			isWrapped: Bool,
			inScope scope: Set<Property>,
			lazilyInstantiatedInstanceProperties: Set<Property>,
			unavailableProperties: Set<Property>,
			childProperties: Set<Property>,
			uncoveredProperties: Set<Property>,
		) -> Rule? {
			for dependency in instantiable.dependencies {
				switch dependency.source {
				case .instantiated:
					// D1 lane hook (lane B): a wrapper child is a node of its own, erased or fulfilled by another type alike.
					// D1 lane hook (lane D): an `@Instantiated` dependency the mock cannot build is a parameter of `mock()`.
					guard childProperties.contains(dependency.property) || uncoveredProperties.contains(dependency.property) else { return .flatParameter }
				case .received(onlyIfAvailable: false):
					// D1 lane hook (lane B): a receive by value of a lazy wrapper's instance reads the wrapper in scope.
					guard scope.contains(dependency.property)
						|| lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty)
						&& MockLowering.scope(scope, holdsWrapperOfInstance: dependency.property.asUnwrappedProperty)
					else { return .flatParameter }
				case .forwarded:
					guard isWrapped else { return .wrapper }
				case .received(onlyIfAvailable: true):
					// D1 lane hook (lane B): a receive only if available is passed `nil` or what the scope provides; one the
					// mock's root provides is an override (`MockLowering+OnlyIfAvailable.swift`).
					guard MockLowering.scope(
						scope,
						provides: dependency.property,
						unavailableProperties: unavailableProperties,
						lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
					) else { return .onlyIfAvailable }
				case .aliased:
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
		/// The name the node is bound under: its label, or a name apart from a sibling's of that label.
		let bindingName: String
		/// The concrete type the node builds.
		let instantiable: Instantiable
		/// Whether the node builds children or binds aliases, which its builder function declares.
		let hasChildren: Bool
		/// The receives of the node's type its builder function binds again under their labels, from the names each is
		/// handed.
		let receiverBindings: [(property: Property, name: String)]
		/// Whether the node builds its type in a wrapper, which is handed `forwardedProperties`.
		let isWrapped: Bool
		/// Whether the node wraps what it builds in its property's type (`erasedToConcreteExistential: true`).
		let isErased: Bool
		/// Whether the node builds a type other than its property's, which its binding then spells (`fulfilledByType:`).
		let isFulfilledByAnotherType: Bool
		// D1 lane hook (lane D): a node built with its type's hand-written mock.
		/// Whether the node is built with its type's hand-written mock rather than its initializer.
		let usesMockInitializer: Bool
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
		// D1 lane hook (lane D): the fields of the node's configuration for its construction's default-valued parameters.
		/// The fields of the node's configuration for its construction's default-valued parameters, in the order it takes them.
		let defaultFields: [DefaultField]
		/// Whether the node's children are configured in a configuration of its own, which holds its builder too.
		var hasConfiguration = false
		// D1 lane hook (lane B): the parameters a lazy cycle closing on the node's builder function needs, and what the
		// node's binding passes them (`MockLowering+CycleParameters.swift`).
		/// The parameters of the builder function a lazy cycle closing on it needs, after the forwarded properties.
		var cycleParameters = [Property]()
		/// The arguments the node's binding passes `cycleParameters`.
		var cycleParameterArguments = [String]()
		// D1 lane hook (lane C): a public mock binds a node it promotes from its caller's value, when passed one.
		/// The parameter of a public mock that holds the value its caller passed for the node, which the node's binding reads
		/// first (`ScopeGenerator.passing(_:orBuilding:)`).
		var promotedParameterName: String?

		/// The node, configured in a configuration of its own where `children` hold a node that builds its type or its
		/// construction takes a default-valued parameter.
		func configured(byChildren children: [TreeNode]) -> ConstantNode {
			var node = self
			node.hasConfiguration = children.contains(where: \.isPropertyNode) || !defaultFields.isEmpty
			return node
		}

		/// The member of the enclosing overrides that configures the node: its configuration, or an optional builder closure.
		var overridesField: OverridesField {
			// D1 lane hook (lane B): a node built in or as a `@Sendable` builder function takes a `@Sendable` override, which
			// is `Sendable`, as is a configuration `@Sendable`-typed.
			hasConfiguration
				? OverridesField(name: bindingName, typeSource: configurationTypeName, defaultValue: ".init()", sendability: .whenConfigurationIsTypedSendable(instantiable.concreteInstantiable.asSource))
				: OverridesField(name: bindingName, typeSource: "(\(requiresSendable ? "@Sendable " : "")\(builderClosureType))?", defaultValue: "nil", sendability: requiresSendable ? .always : .never)
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

		/// The types of the values the node's override is handed, joined: one per argument its construction is passed, which
		/// leaves out a parameter left to its default (`ScopeGenerator.MockParameterNode.callSiteArguments`).
		/// What builds the node: its type's hand-written mock, or its initializer.
		private var constructionInitializer: Initializer? {
			usesMockInitializer ? instantiable.mockInitializer : instantiable.initializer
		}

		private var builderParameterTypes: String {
			let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
			return (constructionInitializer?.arguments ?? []).filter { !$0.isLeftToItsDefault || dependencyLabels.contains($0.innerLabel) }.map { argument in
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
			// An argument the initializer takes unlabeled is passed by position, as `defaultBuilderCall` passes it.
			let argumentList = arguments.map { $0.label == "_" ? $0.value : "\($0.label): \($0.value)" }.joined(separator: ", ")
			let unerasedConstruction = if usesMockInitializer {
				"\(typeName).\(instantiable.customMockName ?? InstantiableVisitor.mockMethodName)(\(argumentList))"
			} else if instantiable.declarationType.isExtension {
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
			MockLowering.builderFunctionName(boundAs: bindingName)
		}

		/// The statement that binds a constant node with no children, whose override `overrideRead` reads.
		func constantBindingLine(overrideRead nodePath: String?, indent: String) -> String {
			// Only the `if` expression that reads an override needs the property's type, which its two branches share.
			// D1 lane hook (lane C): a child the mock promotes for an optional receive, such as a value a called public mock
			// builds when passed `nil`, is bound as the value it builds.
			let annotation = isFulfilledByAnotherType && !isErased && nodePath != nil ? ": \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)" : ""
			return "\(indent)let \(bindingName)\(annotation) = \(passingPromotedValue(orBuilding: constructionReading(override: nodePath, builderCall: "\(ReservedName.configurationBuilderPropertyName)(\(builderArguments))")))"
		}

		/// `construction`, read after the value the public mock's caller passed for the node where it promotes the node.
		func passingPromotedValue(orBuilding construction: String) -> String {
			promotedParameterName.map { ScopeGenerator.passing($0, orBuilding: construction) } ?? construction
		}

		/// The node's construction, preceded by a read of its override at `overridePath` that `builderCall` calls, or alone
		/// where it reads no override.
		private func constructionReading(override overridePath: String?, builderCall: String) -> String {
			guard let overridePath else { return construction }
			let builder = ReservedName.configurationBuilderPropertyName
			return "if let \(builder) = \(overridePath) { \(builderCall) } else { \(construction) }"
		}

		/// The first line of the node's builder function, whose children's statements follow it.
		func builderFunctionDeclarationLine(indent: String) -> String {
			let builtType = property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource
			let parameters = forwardedProperties.map { "\($0.label): \($0.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let decorator = buildsInSendableFunction ? "@Sendable " : ""
			var parameterList = parameters.joined(separator: ", ")
			if !cycleParameters.isEmpty {
				parameterList += (parameterList.isEmpty ? "" : ", ") + cycleParameters.initializerFunctionParametersSource(amongTypesDeclaredEscaping: typesDeclaredEscaping)
			}
			return "\(indent)\(decorator)func \(functionName)(\(parameterList)) -> \(builtType) {"
		}

		/// The statements that begin the node's builder function, before its children's: each receive named apart bound
		/// again under its label.
		func receiverBindingLines(indent: String) -> [String] {
			let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
			return receiverBindings.map { "\(bodyIndent)let \($0.property.label): \($0.property.typeDescription.asSource) = \($0.name)" }
		}

		/// The lines that end the node's builder function, after its children's statements, and bind the node, whose
		/// overrides are at `nodePath`.
		func builderFunctionEndLines(overrideRead overridePath: String?, indent: String) -> [String] {
			let builder = ReservedName.configurationBuilderPropertyName
			let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
			// A constant's builder function always returns its construction (`BuilderBody`).
			let returnPrefix = hasChildren || !receiverBindings.isEmpty || !isWrapped ? "return " : ""
			// A configuration's builder returns the concrete type, which an erased node wraps as its construction does.
			let builderCall = isErased && hasConfiguration ? "\(erasedTypeSource)(\(builder)(\(builderArguments)))" : "\(builder)(\(builderArguments))"
			var lines = ["\(bodyIndent)\(returnPrefix)\(constructionReading(override: overridePath, builderCall: builderCall))"]
			lines.append("\(indent)}")
			lines.append(contentsOf: promotedBindingLines(indent: indent))
			return lines
		}

		/// The statements that bind the node from its builder function, after the value the public mock's caller passed for it
		/// where it promotes the node.
		func promotedBindingLines(indent: String) -> [String] {
			guard let promotedParameterName else {
				return MockLowering.bindingLines(of: property, boundAs: bindingName, callingFunctionNamed: functionName, forwardedProperties: forwardedProperties, cycleParameterArguments: cycleParameterArguments, indent: indent)
			}
			guard property.propertyType.isConstant else {
				return [MockLowering.promotedWrapperBindingLine(of: property.typeDescription, named: bindingName, passing: promotedParameterName, handing: functionName, forwardedProperties: forwardedProperties, cycleParameterArguments: cycleParameterArguments, indent: indent)]
			}
			return ["\(indent)let \(bindingName): \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource) = \(ScopeGenerator.passing(promotedParameterName, orBuilding: "\(functionName)(\(cycleParameterArguments.joined(separator: ", ")))"))"]
		}
	}

	/// A node of a mock's tree: one that builds its type, an alias of a value bound before it, or a call of another module's
	/// public mock.
	enum TreeNode {
		case built(ConstantNode)
		case alias(AliasBinding)
		// D1 lane hook (lane C): a call of another module's public mock (`MockLowering+PublicMocks.swift`).
		case publicMockCall(PublicMockCallNode)
		/// A node that closes a cycle, bound as `bindingName`: it calls the builder function of the node around it that it
		/// repeats, which builds `concreteType`.
		case cycleClosing(Property, bindingName: String, concreteType: TypeDescription)

		var property: Property {
			switch self {
			case let .built(node): node.property
			case let .alias(alias): alias.property
			case let .publicMockCall(call): call.property
			case let .cycleClosing(property, _, _): property
			}
		}

		var builtNode: ConstantNode? {
			switch self {
			case let .built(node): node
			case .alias, .publicMockCall, .cycleClosing: nil
			}
		}

		/// Whether the node builds a property, which gives its parent a configuration of its own
		/// (`ScopeGenerator.MockParameterNode.needsConfigurationStruct`), whether or not that configuration has a field for it.
		var isPropertyNode: Bool {
			switch self {
			case .built, .publicMockCall, .cycleClosing: true
			case .alias: false
			}
		}

		/// The member of the enclosing overrides that configures the node, if any.
		var overridesField: OverridesField? {
			switch self {
			case let .built(node): node.overridesField
			case .alias: nil
			case let .publicMockCall(call): call.overridesField
			// D1 lane hook (lane D): a node that closes a cycle is configured by the configuration of the type it repeats.
			case let .cycleClosing(_, bindingName, concreteType): MockLowering.cycleClosingOverridesField(boundAs: bindingName, concreteType: concreteType)
			}
		}

		/// The concrete type the node builds, whose edge from its parent `cycleEdges` can prune; `nil` for a node that
		/// builds none of its own.
		var concreteType: TypeDescription? {
			switch self {
			case let .built(node): node.instantiable.concreteInstantiable
			case let .cycleClosing(_, _, concreteType): concreteType
			case .alias, .publicMockCall: nil
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
		/// The name the alias is bound under: its label, or a name apart at the mock root's level.
		let bindingName: String
		let fulfillingProperty: Property
		/// The name the fulfilling property is read under: its label, or the name it is handed.
		let fulfillingName: String
		let isErased: Bool
		/// Whether the alias is `onlyIfAvailable`, so an erased alias maps over its fulfilling value.
		let isOnlyIfAvailable: Bool
		/// Whether the alias is only if available of a property unavailable where it is bound, so it is bound to `nil`.
		let isBoundToNil: Bool
		let declarationReference: AliasDeclarationReferences.Reference?

		/// The statement that binds the alias, which refers to its declaration as the production tree's does.
		func bindingLines(indent: String) -> String {
			let boundProperty = Property(label: bindingName, typeDescription: property.typeDescription)
			return GeneratedCodeText.indentingNonEmptyLines(
				of: ScopeGenerator.referencingDeclaration(
					of: isBoundToNil
						? "let \(boundProperty.asSource) = nil"
						: ScopeGenerator.aliasDeclaration(
							of: boundProperty,
							fulfilledBy: fulfillingName,
							ofType: fulfillingProperty.typeDescription,
							erasedToConcreteExistential: isErased,
							fulfillingValueMayBeOptional: isOnlyIfAvailable,
						),
					by: declarationReference,
				),
				by: indent,
			)
		}
	}

	/// The key a node of `property`, built as `instantiable`, repeats a node around it by, as
	/// `ScopeGenerator.MockParameterNode.cycleNodeKey` spells it.
	static func cycleNodeKey(of property: Property, builtAs instantiable: Instantiable) -> String {
		"\(property.typeDescription.asInstantiatedType.asSource) fulfilled by \(instantiable.concreteInstantiable.asSource)"
	}

	/// The statements that bind `property` from the builder function `functionName`, which takes `forwardedProperties`: a
	/// constant called, or an instantiator handed the function.
	static func bindingLines(of property: Property, boundAs bindingName: String, callingFunctionNamed functionName: String, forwardedProperties: [Property], cycleParameterArguments: [String] = [], indent: String) -> [String] {
		// D1 lane hook (lane B): the binding of each wrapper kind (`MockLowering+Wrappers.swift`).
		if property.propertyType.isConstant {
			// D1 lane hook (lane C): a promoted child is bound as the value it builds, as `constantBindingLine` binds it.
			["\(indent)let \(bindingName): \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource) = \(functionName)(\(cycleParameterArguments.joined(separator: ", ")))"]
		} else {
			// A mock binds a node it promotes for an optional receive to a value that is not optional, so a wrapper is
			// spelled unwrapped where it is made.
			wrapperBindingLines(of: property.typeDescription, named: bindingName, handing: functionName, forwardedProperties: forwardedProperties, cycleParameterArguments: cycleParameterArguments, indent: indent)
		}
	}

	/// The statement that binds a wrapper a public mock promotes, `typeDescription`, as `bindingName`: the caller's own,
	/// passed as `promotedParameterName`, where it passed one, and otherwise made around the builder function `functionName`,
	/// which takes `forwardedProperties`, as `wrapperBindingLines` makes it.
	static func promotedWrapperBindingLine(
		of typeDescription: TypeDescription,
		named bindingName: String,
		passing promotedParameterName: String,
		handing functionName: String,
		forwardedProperties: [Property],
		cycleParameterArguments: [String] = [],
		indent: String,
	) -> String {
		let unwrappedType = typeDescription.unwrapped
		let binding = unwrappedType.isConstructedByAnnotation ? "\(bindingName): \(unwrappedType.asSource)" : bindingName
		let wrapperType = unwrappedType.spelledForConstruction
		let arguments = forwardedProperties.map {
			forwardedProperties.count > 1
				? "\($0.label.spelledAsArgumentLabel): $0.\($0.label)"
				: "\($0.label.spelledAsArgumentLabel): $0"
		} + cycleParameterArguments
		let construction = if arguments.isEmpty {
			"\(wrapperType)(\(functionName))"
		} else {
			"\(wrapperType) {\n\(indent)\(ScopeGenerator.standardIndent)\(functionName)(\(arguments.joined(separator: ", ")))\n\(indent)}"
		}
		return "\(indent)let \(binding) = \(ScopeGenerator.passing(promotedParameterName, orBuilding: construction))"
	}

	/// The name of the builder function of a node bound as `bindingName`.
	/// The arguments the mocked type's construction `initializer` is handed for `dependencies`: each dependency's label, or
	/// the name the mock root's level binds it apart under, by its label and type (`renames`).
	static func rootArgumentList(of initializer: Initializer, given dependencies: [Dependency], renames: [String: [TypeDescription: String]], passingNilTo unavailableProperties: Set<Property>) -> String {
		var parts = [String]()
		for argument in initializer.arguments {
			if let dependency = dependencies.first(where: argument.isFulfilled(by:)) {
				// D1 lane hook (lane B): a receive only if available nothing above provides is passed `nil`, as production passes it.
				guard dependency.source != .received(onlyIfAvailable: true) || !unavailableProperties.contains(dependency.property) else {
					parts.append("\(argument.label.spelledAsArgumentLabel): nil")
					continue
				}
				parts.append("\(argument.label.spelledAsArgumentLabel): \(renames[argument.innerLabel]?[dependency.property.typeDescription] ?? argument.innerLabel)")
			} else if argument.hasDefaultValue, !argument.isLeftToItsDefault {
				parts.append("\(argument.label.spelledAsArgumentLabel): \(argument.label)")
			}
		}
		return parts.joined(separator: ", ")
	}

	/// Whether a receive among `generators`, or beneath them up to a node that declares `label`, reads `label` by name: a
	/// receive or an alias's fulfilling property whose form `renames` does not name apart; or `nil` where the walk cannot
	/// tell yet (`ScopeGenerator.receiveReadsLabelByName`).
	static func receiveReadsLabelByName(_ label: String, beneath generators: [ScopeGenerator], renames: [String: [TypeDescription: String]]) -> Bool? {
		let names = renames[label] ?? [:]
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var generatorsToVisit = generators
		while let generator = generatorsToVisit.popLast() {
			switch generator.scopeData {
			case let .alias(_, fulfillingProperty, _, onlyIfAvailable, _):
				guard fulfillingProperty.label == label else { continue }
				// D1 lane hook (lane B): an alias bound to `nil`, or of a lazy wrapper's instance.
				guard !onlyIfAvailable, !generator.mockLoweringLazilyInstantiatedInstanceProperties.contains(fulfillingProperty.asUnwrappedProperty) else { return nil }
				guard names[fulfillingProperty.typeDescription] != nil else { return true }
			case let .property(instantiable, _, _, _, isPropertyCycle, seamCall):
				guard seamCall == nil else { return nil }
				for dependency in instantiable.dependencies where dependency.source.isReceived && dependency.property.label == label && !generator.unavailableOptionalProperties.contains(dependency.property) {
					// D1 lane hook (lane B): a receive of a lazy wrapper's instance reads the wrapper named apart.
					guard !generator.mockLoweringLazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) else { return nil }
					guard names[dependency.property.typeDescription] != nil || names[dependency.property.asUnwrappedProperty.typeDescription] != nil else { return true }
				}
				// The builder function of a node that instantiates, forwards or renames the label declares it, and what is
				// beneath reads that.
				if !isPropertyCycle, !instantiable.dependencies.contains(where: { !$0.source.isReceived && $0.property.label == label }) {
					generatorsToVisit.append(contentsOf: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).map(\.generator))
				}
			// D1 lane hook (lane C): a site of a public mock's hole binds its property from the builder's label, as an alias
			// binds its own (`MockAliasNode.holeSite`).
			case let .hole(_, _, site?):
				guard site.builderLabel == label else { continue }
				guard names[site.builtType] != nil else { return true }
			case .root, .hole, .fill:
				return nil
			}
		}
		return false
	}

	static func builderFunctionName(boundAs bindingName: String) -> String {
		"\(ReservedName.builderFunctionNamePrefix)\(bindingName)".spelledAsJoinedIdentifier
	}

	/// Routes the receives of `properties`, dependencies a type instantiates that the mock cannot build, to the parameters of
	/// `mock()` they are named apart under, in `renames`, which a declaration of theirs has pruned (`routingReceives`).
	static func routeReceives(of properties: [Property], toParametersNamed parameterNames: [String: [TypeDescription: String]], in renames: inout [String: [TypeDescription: String]]) {
		for property in properties {
			if let parameterName = parameterNames[property.label]?[property.typeDescription] {
				renames[property.label, default: [:]][property.typeDescription] = parameterName
			}
		}
	}

	/// `renames` without the names that `declarations`, a builder function's children and parameters, hide: a receive of a
	/// declaration's label in its form, or its optional form, reads that declaration, as
	/// `ScopeGenerator.removingRenames(hiddenByDeclarationsOf:parameters:from:)` prunes the emitter's map.
	static func removingRenames(hiddenBy declarations: [Property], from renames: [String: [TypeDescription: String]]) -> [String: [TypeDescription: String]] {
		guard !renames.isEmpty else { return renames }
		var renames = renames
		for declaration in declarations where renames[declaration.label] != nil {
			renames[declaration.label]?[declaration.typeDescription] = nil
			renames[declaration.label]?[.optional(declaration.typeDescription)] = nil
			// A lazy wrapper's declaration is the nearest of its instance too, so it hides the rename of the other wrapper
			// kind around that instance.
			if let instance = declaration.asUnwrappedProperty.asLazilyInstantiatedInstanceProperty {
				for wrapperName in [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType] {
					let wrapper = TypeDescription.simple(name: wrapperName, generics: [instance.typeDescription])
					renames[declaration.label]?[wrapper] = nil
					renames[declaration.label]?[.optional(wrapper)] = nil
				}
			}
			if renames[declaration.label]?.isEmpty == true {
				renames[declaration.label] = nil
			}
		}
		return renames
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
			usesMockInitializer: node.usesMockInitializer,
			// A child's field is the one the overrides hold for a node at the root: its override, its configuration, or the
			// overrides of the public mock it calls.
			childFields: children.compactMap(\.overridesField).map { field in
				ChildField(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue)
			},
			concreteBuilderClosureType: node.concreteBuilderClosureType,
			defaultFields: node.defaultFields,
		)
	}
}
