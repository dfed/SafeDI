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
/// generation order. The walk writes each node's statements as it reaches the node and keeps no tree of nodes, and it
/// recurses through `async` functions, whose frames the task allocates, so a tree as deep as the module has types neither
/// overflows a thread's stack nor releases a chain of nested nodes.
extension ScopeGenerator {
	/// The mock of `instantiable`, the mocked type of this root, whose tree is its generator's children.
	/// `worldRoot` is the root of the mock root's world, where a test observes node records.
	func lowerMockRootWithTree(of instantiable: Instantiable, context: MockContext, worldRoot: ConstructionScope? = nil) async throws -> MockLowering.Result {
		// The mocked type's hand-written mock builds it, internal or public (`MockLowering+HandWrittenMocks.swift`), and every
		// dependency is a node of its tree, a parameter of `mock()`, an override's binding or passed `nil`.
		// The parameters `mock()` takes before its overrides (`lowerRootSignature(of:context:)`).
		let signature = lowerRootSignature(of: instantiable, context: context)
		let bodyIndent = "\(Self.standardIndent)\(Self.standardIndent)"
		let orderedChildren = orderedChildrenComputedAfresh(propertiesGeneratedLater: [])
		// No node binds a parameter’s label again, at any depth: the emitter names the parameter apart.
		var walk = MockLowering.Walk(cycleEdges: context.cycleEdges, rootLabels: signature.labels.union(signature.lazilyInstantiatedBindings.map(\.name)), uncoveredProperties: signature.uncoveredProperties)
		walk.rootFlatReceivedLabels = Set(signature.flatReceivedParameters.map(\.property.label))
		walk.rootNamesDeclaredInBuilderFunctions = signature.namesDeclaredInBuilderFunctions
		// A receive of a flat received parameter or override named apart from its label is handed that
		// name, which its builder function binds again under the label.
		walk.renames = signature.renamesByLabelAndType
		// The wrappers `mock()` binds around the instances it is passed, which their receivers are
		// passed by name.
		walk.lazilyInstantiatedNames = signature.lazilyInstantiatedBindingNamesByLabelAndType
		// A public mock's wrapper parameters, as the emitter's `lazilyInstantiatedBindingNameMap` holds
		// them, a non-optional one under its optional form too.
		if instantiable.generateMock == .public {
			for parameter in signature.flatReceivedParameters where parameter.property.typeDescription.lazilyInstantiatedInstanceType != nil {
				walk.publicMockWrapperParameterNames[parameter.property.label, default: [:]][parameter.property.typeDescription] = parameter.name
			}
			for parameter in signature.flatReceivedParameters where parameter.property.typeDescription.lazilyInstantiatedInstanceType != nil && !parameter.property.typeDescription.isOptional {
				let optionalType = TypeDescription.optional(parameter.property.typeDescription)
				if walk.publicMockWrapperParameterNames[parameter.property.label]?[optionalType] == nil {
					walk.publicMockWrapperParameterNames[parameter.property.label]?[optionalType] = parameter.name
				}
			}
		}
		// The uncovered dependencies named apart, which the types that instantiate them are passed, and
		// a receive beneath reads, from the mocked type's own for its whole tree (`routingReceives`).
		walk.uncoveredParameterNames = signature.uncoveredParameterNamesByLabelAndType
		walk.sendableAutoclosureBindings = signature.sendableAutoclosureBindings
		walk.rootOverrideNames = Set(signature.onlyIfAvailableOverrides.map(\.name))
		walk.unavailableDependencyOverrideNames = signature.unavailableDependencyOverrideNames
		let mockedTypeUncoveredProperties = instantiable.dependencies.compactMap { dependency -> Property? in
			guard case .instantiated = dependency.source, signature.uncoveredProperties.contains(dependency.property) else { return nil }
			return dependency.property
		}
		walk.renames = MockLowering.removingRenames(hiddenBy: mockedTypeUncoveredProperties, from: walk.renames)
		// No wrapper `mock()` binds is hidden by the mocked type's own uncovered dependencies, which
		// the emitter routes through the flat renames alone: a promoted sibling's receive of the other wrapper kind around
		// such a dependency's instance is passed the wrapper `mock()` makes of the instance it takes.
		MockLowering.routeReceives(of: mockedTypeUncoveredProperties, toParametersNamed: walk.uncoveredParameterNames, in: &walk.renames)
		walk.rootParametersKeepingTheirLabels = (signature.forwardedParameters + signature.rootDefaultParameters).map(\.property)
		// The defaults a type's hand-written mock declares, which its configuration's fields take.
		walk.handWrittenMockDefaultParameters = context.handWrittenMockDefaultParameters
		walk.sendableConfigurationTypeNames = context.sendableConfigurationTypeNames
		// A public mock builds each configured node with its type's construction function.
		walk.buildsPublicMock = instantiable.generateMock == .public
		// The mocked type's own initializer takes the root's level, an actor's into its isolation, so the root's children
		// read their overrides as a `@Sendable` builder function does. A public mock's configurations are never `Sendable`, so
		// it reads each field into a local of its own, and its construction functions take an actor's arguments `sending`
		// (`MockLowering.PublicConstructionRecord.sendsArguments`).
		walk.isInsideActorArgument = instantiable.declarationType == .actorType
		// The nodes a public mock promotes, each bound from its caller's value when passed one.
		walk.promotedProperties = publicMockPromotedProperties(of: instantiable, among: orderedChildren)
		// Each override binds its receive's label, in the optional form a receive only if available
		// reads.
		let overrideProperties = Set(signature.onlyIfAvailableOverrides.flatMap { override in
			[override.receivedProperty, Property(label: override.receivedProperty.label, typeDescription: override.typeDescription)]
		})
		// The builders `mock()` takes optional for the places its calls fill.
		// A call's builder of a family the calls pass up reads the builder `mock()` takes for it.
		walk.filledCallBuilders = try filledCallBuilders(of: orderedChildren, context: context, seamMockBuilders: signature.seamMockBuilders)
		// A public mock's plan, computed once from the names the root's level binds its nodes under,
		// names the parameters its promoted nodes read their callers' values from, and the builders its calls read, which the
		// walk and the mock's tiers both take from it.
		var publicMockRoot: (plan: PublicMockPlan, context: PublicMockContext)?
		if instantiable.generateMock == .public, let publicMockContext = context.publicMockContext {
			let rootBindingNames = walk.rootLevelBindingNames(of: orderedChildren.map(\.generator))
			let plan = publicMockPlan(
				of: instantiable,
				signature: signature,
				// A promoted call is bound under its label (`publicMockCallNode`).
				promotedNodes: zip(orderedChildren, rootBindingNames).compactMap { child, bindingName in
					guard let property = child.generator.mockLoweringBuiltProperty, let bindingName, walk.promotedProperties.contains(property) else { return nil }
					return (property: property, name: child.generator.publicMockCall == nil ? bindingName : property.label)
				},
				filledCallBuilders: walk.filledCallBuilders,
				// A public mock takes each property received only if available as a parameter, so only the tree's property
				// nodes make a `SafeDIOverrides`; a place is bound as an alias.
				hasOverrides: orderedChildren.contains { $0.generator.mockLoweringBuiltProperty != nil },
				context: context,
				publicMockContext: publicMockContext,
			)
			walk.promotedParameterNames = plan.promotedParameterNames
			publicMockRoot = (plan, publicMockContext)
			// A public mock's calls read each builder under the internal name its plan gives it.
			if !walk.filledCallBuilders.families.isEmpty {
				walk.filledCallBuilders = try filledCallBuilders(of: orderedChildren, context: context, optionalBuilderNames: plan.optionalBuilderNames)
			}
		}
		// `mock()` first binds each builder a call passes up apart from its label, as it binds a flat
		// parameter's `@Sendable` autoclosure, before anything else.
		walk.filledCallBuilders.passedUpBuilderNames = signature.passedUpBuilderNames
		// With each builder `mock()` takes for its calls' places that it binds apart, in label order.
		var builderBindingLines = walk.filledCallBuilders.builderBindingLines
		var rootBindings = [NodeRecordsReport.RootBinding]()
		if !builderBindingLines.isEmpty {
			rootBindings.append(.builderBoundApart)
		}
		// Then the adapters of a builder passed up, which drop the value a call's form takes.
		for builder in signature.passedUpBuilders {
			if builder.internalName != builder.label {
				builderBindingLines.append((builder.label, "let \(builder.internalName) = \(builder.label)"))
			}
			for adapter in builder.adapters {
				builderBindingLines.append((builder.label, "let \(adapter.name): \(adapter.typeSource) = { _ in \(builder.internalName)() }"))
			}
		}
		// A stable sort keeps a builder's binding before its adapters.
		var bindingLines = builderBindingLines.enumerated().sorted { ($0.element.label, $0.offset) < ($1.element.label, $1.offset) }.map { "\(bodyIndent)\($0.element.line)" }
		// The mocked type's own receive of a builder its tree's calls pass up is bound again under its
		// label, as a receive of a flat parameter named apart is at the mock root.
		for dependency in instantiable.dependencies where dependency.source.isReceived {
			guard let name = signature.passedUpBuilderNames[dependency.property], name != dependency.property.label else { continue }
			bindingLines.append("\(bodyIndent)let \(dependency.property.label): \(dependency.property.typeDescription.strippingEscaping.asSource) = \(name)")
		}
		// Each `@Sendable` autoclosure parameter is read into a local, and the value of one the mocked
		// type instantiates is bound under the parameter's name.
		let sendableAutoclosureLines = signature.sendableAutoclosureLocalBindingLines(indent: bodyIndent)
		if !sendableAutoclosureLines.isEmpty {
			rootBindings.append(.sendableAutoclosure)
		}
		bindingLines.append(contentsOf: sendableAutoclosureLines)
		bindingLines.append(contentsOf: mockedTypeUncoveredProperties.compactMap { property in
			signature.sendableAutoclosureBindings[property].map { "\(bodyIndent)\($0.binding)" }
		})
		// `mock()` then binds each override of what its tree receives only if available, which the
		// receives beneath read.
		// A public mock takes each as a parameter of `mock()` under the override's name, which binds it.
		if instantiable.generateMock != .public {
			// The override of a property instantiated only if available that nothing fulfills is bound by the type that declares
			// the property, where production binds it.
			bindingLines.append(contentsOf: signature.onlyIfAvailableOverrides.lazy.filter { signature.unavailableDependencyOverrideNames[$0.receivedProperty] == nil }.map { override in
				"\(bodyIndent)let \(override.name): \(override.typeDescription.asSource) = \(ReservedName.mockOverridesParameterName).\(override.name)"
			})
		}
		let rootReceiverBindingIndex = bindingLines.endIndex
		let nodes = try await walk.children(
			of: orderedChildren,
			loops: mockLoweringLoopMemberships,
			inScope: signature.properties.union(overrideProperties).union(signature.lazilyInstantiatedProperties),
			path: ReservedName.mockOverridesParameterName,
			indent: bodyIndent,
			lines: &bindingLines,
		)
		// The mocked type is passed its own dependencies by label, and the builder functions beneath bind theirs, so the root's
		// level names apart only labels neither reads.
		// The mocked type's construction reads the names its own dependencies are bound apart under.
		// The mocked type is passed each of its own dependencies the root's level names apart by that name
		// (`generateReturnArgumentList`'s disambiguation map), which reads the exact property's name.
		// One read through a `LazilyInstantiated` the level names apart reads that name's instance
		// (`rootArgumentList`).
		let lazilyInstantiatedInstances = Set(propertiesToGenerate.compactMap(\.mockLoweringDeclaredLazilyInstantiatedInstanceProperty))
			.union(mockLoweringLazilyInstantiatedInstanceProperties)
		// The mocked type's own receive of a flat received parameter or override named apart is bound
		// again under its label before the tree, unless the root's level binds that label (`generateMockRootCode`'s
		// `rootDependenciesToRebind`), when the mocked type is passed the name.
		let rootLevelBindingNames = walk.rootPropertyNodeBindingNames.union(signature.onlyIfAvailableOverrides.map(\.name))
		var rootRenames = walk.rootRenames
		// The mocked type's own receive of a wrapper `mock()` binds is passed its binding by name.
		for (label, names) in signature.lazilyInstantiatedBindingNamesByLabelAndType {
			rootRenames[label, default: [:]].merge(names) { _, wrapperName in wrapperName }
		}
		var rootReceiverBindingLines = [String]()
		for dependency in instantiable.dependencies where dependency.source.isReceived {
			guard let names = signature.renamesByLabelAndType[dependency.property.label],
			      let name = names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription],
			      !rootLevelBindingNames.contains(dependency.property.label)
			else { continue }
			rootReceiverBindingLines.append("\(bodyIndent)let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(name)")
			rootRenames[dependency.property.label]?[dependency.property.typeDescription] = nil
		}
		if !signature.lazilyInstantiatedBindings.isEmpty {
			rootBindings.append(.wrapperAroundInstance)
		}
		if !rootReceiverBindingLines.isEmpty {
			rootBindings.append(.receiveBoundAgainUnderLabel)
		}
		let linesBoundBesideNodes = signature.lazilyInstantiatedBindingLines(indent: bodyIndent) + rootReceiverBindingLines
		bindingLines.insert(contentsOf: linesBoundBesideNodes, at: rootReceiverBindingIndex)
		// The mocked type's own receive or instantiation of a lazy wrapper's instance is passed the
		// wrapper's instance, and a receive only if available of the optional form of a node or a parameter of `mock()` is passed
		// that binding, as `generateReturnArgumentList` passes them.
		// A public mock's root passes its instances alike (`publicMockWithTree`).
		let rootInstancesReadByValue = MockLowering.rootInstancesReadByValue(of: instantiable, among: lazilyInstantiatedInstances)
		// A public mock's root passes them alike, as `generateReturnArgumentList` does for every root.
		let rootOptionalForms = MockLowering.rootOptionalFormsProvidedByNodes(of: instantiable, nodeProperties: Set(nodes.map(\.property)).union(signature.properties), renames: rootRenames)
		// Each such receive of a node named apart is passed the node's name.
		for (label, names) in MockLowering.rootOptionalFormRenames(of: rootOptionalForms, renames: rootRenames) {
			rootRenames[label, default: [:]].merge(names) { renamed, _ in renamed }
		}
		let builders = (walk.filledCallBuilders.parameters + signature.placeOnlyBuilderDeclarations).sorted { $0.label < $1.label }
		// Where a test observes node records, an internal mock that binds nothing but its nodes has the statements that build
		// them laid out from the records of its world (`nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:rootBindings:outerDeclarations:)`).
		if let worldRoot {
			// `mock()`'s parameters and the overrides it binds before the nodes are the declarations the nodes' reads resolve
			// to, as a seam's parameters are for its root's body, each by its label: one named apart, or an uncovered
			// parameter handed to the type that instantiates it, is no declaration the records read.
			let overridesBoundBeforeNodes = signature.onlyIfAvailableOverrides.filter { signature.unavailableDependencyOverrideNames[$0.receivedProperty] == nil }
			let bindsOnlyNodes = rootReceiverBindingIndex == overridesBoundBeforeNodes.count
				&& linesBoundBesideNodes.isEmpty
				&& signature.uncoveredParameters.isEmpty
				&& signature.parameters.allSatisfy { $0.name == $0.property.label }
				&& signature.onlyIfAvailableOverrides.allSatisfy { $0.name == $0.receivedProperty.label }
				&& builders.isEmpty
				&& rootRenames.values.allSatisfy(\.isEmpty)
				&& rootInstancesReadByValue.isEmpty
			if !signature.forwardedParameters.isEmpty {
				rootBindings.append(.forwardedParameter)
			}
			if !signature.rootDefaultParameters.isEmpty {
				rootBindings.append(.defaultValuedParameter)
			}
			if !signature.flatReceivedParameters.isEmpty {
				rootBindings.append(.receivedParameter)
			}
			if !signature.uncoveredParameters.isEmpty {
				rootBindings.append(.uncoveredParameter)
			}
			if !signature.onlyIfAvailableOverrides.isEmpty {
				rootBindings.append(.onlyIfAvailableOverride)
			}
			if !builders.isEmpty {
				rootBindings.append(.builder)
			}
			var namedApartKinds = Set<NodeRecordsReport.RootBinding>()
			for (label, names) in rootRenames {
				for (type, name) in names {
					if signature.renamesByLabelAndType[label]?[type] == name {
						namedApartKinds.insert(.rootReceivesParameterNamedApart)
					} else if signature.lazilyInstantiatedBindingNamesByLabelAndType[label]?[type] == name {
						namedApartKinds.insert(.rootReceivesWrapperNamedApart)
					} else {
						namedApartKinds.insert(.rootReceivesNodeNamedApart)
					}
				}
			}
			for kind in [NodeRecordsReport.RootBinding.rootReceivesNodeNamedApart, .rootReceivesParameterNamedApart, .rootReceivesWrapperNamedApart] where namedApartKinds.contains(kind) {
				rootBindings.append(kind)
			}
			if !rootInstancesReadByValue.isEmpty {
				rootBindings.append(.instanceReadThroughWrapper)
			}
			let outerDeclarations = signature.parameters.map(\.property) + overridesBoundBeforeNodes.map { Property(label: $0.name, typeDescription: $0.typeDescription) }
			if let statements = try Self.nodeRecordsMockStatements(of: instantiable, worldRoot: worldRoot, bindsOnlyNodes: bindsOnlyNodes, rootBindings: rootBindings, outerDeclarations: outerDeclarations) {
				// The overrides' bindings stay before the nodes that read them.
				bindingLines = Array(bindingLines.prefix(overridesBoundBeforeNodes.count)) + (statements.isEmpty ? [] : [statements])
			}
		}
		// A public mock's tiers, overrides and guard (`MockLowering+PublicMocks.swift`).
		if let publicMockRoot {
			// A public mock's parameters named apart and its values passed `nil`, as the internal mock's.
			return publicMockWithTree(of: instantiable, plan: publicMockRoot.plan, publicMockContext: publicMockRoot.context, signature: signature, nodes: nodes, bindingLines: bindingLines, rootRenames: rootRenames, unavailableProperties: unavailableOptionalProperties, instancesReadByValue: rootInstancesReadByValue, configurations: walk.configurationRecords, context: context)
		} else {
			return MockLowering.Result(code: Self.mockWithTree(of: instantiable, signature: signature, nodes: nodes, inlineOrderedNodes: inlineOrdered(nodes, property: \.property), bindingLines: bindingLines, builders: builders, rootRenames: rootRenames, unavailableProperties: unavailableOptionalProperties, instancesReadByValue: rootInstancesReadByValue, context: context), configurations: walk.configurationRecords)
		}
	}

	/// The mock of `instantiable` whose tree's top-level nodes are `nodes`, in generation order, bound by `bindingLines`:
	/// its `SafeDIOverrides` where a node has an override, its members in the inline order of `inlineOrderedNodes`, and `mock()`, which takes `signature`'s parameters, the builders
	/// `builders` (each label and declaration, in label order, listed among the flat received parameters) and the overrides, binds each node and returns the type built from them.
	private static func mockWithTree(of instantiable: Instantiable, signature: MockLowering.RootSignature, nodes: [MockLowering.TreeNode], inlineOrderedNodes: [MockLowering.TreeNode], bindingLines: [String], builders: [(label: String, declaration: String)], rootRenames: [String: [TypeDescription: String]], unavailableProperties: Set<Property>, instancesReadByValue: Set<Property>, context: MockContext) -> String {
		let indent = standardIndent
		let bodyIndent = "\(indent)\(indent)"
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		// A mock that takes nothing and binds nothing is one call of the type's construction.
		guard !nodes.isEmpty || !signature.parameters.isEmpty || !signature.onlyIfAvailableOverrides.isEmpty || !builders.isEmpty else { return mockWithoutTree(of: instantiable, context: context, passingNilTo: unavailableProperties) }
		var lines = ["extension \(typeName) {"]
		let overridesFields = inlineOrderedNodes.compactMap(\.overridesField)
		// The builders `mock()` takes, listed among the flat received parameters by label.
		var parameterLines = signature.parameterLines(indent: bodyIndent, builders: builders)
		if !overridesFields.isEmpty || !signature.onlyIfAvailableOverrides.isEmpty {
			lines.append(contentsOf: overridesStruct(of: overridesFields, onlyIfAvailableOverrides: signature.onlyIfAvailableOverrides, sendableConfigurationTypeNames: context.sendableConfigurationTypeNames, indent: indent))
			lines.append("")
			parameterLines.append("\(bodyIndent)\(ReservedName.mockOverridesParameterName): \(ReservedName.mockOverridesTypeName) = .init()")
		} else if nodes.contains(where: \.isPropertyNode) {
			// A tree whose nodes have no override, such as a call of a mock that takes no overrides and
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
		// The type the mocked type's hand-written mock returns.
		lines.append("\(indent)) -> \(MockLowering.rootReturnType(of: instantiable)) {")
		lines.append(contentsOf: bindingLines)
		// The mocked type built with its hand-written mock where it has one.
		let argumentList = MockLowering.rootConstructionInitializer(of: instantiable).map { initializer in
			MockLowering.rootArgumentList(of: initializer, given: instantiable.dependencies, renames: rootRenames, passingNilTo: unavailableProperties, readingInstancesOf: instancesReadByValue)
		} ?? Instantiable.incorrectlyConfiguredComment
		let construction = MockLowering.rootConstruction(of: instantiable, argumentList: argumentList)
		lines.append("\(bodyIndent)return \(construction)")
		lines.append("\(indent)}")
		lines.append("}")
		if let mockConditionalCompilation = context.mockConditionalCompilation {
			lines.insert("#if \(mockConditionalCompilation)", at: 0)
			lines.append("#endif")
		}
		return MockLowering.joinedLines(lines)
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
		// Each override of what the mock receives only if available, after the storage's fields and
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
		/// The nodes built around the node the walk is at, each as `MockLowering.cycleNodeKey(of:builtAs:)` spells it:
		/// a node that repeats one reads no override of its own.
		var ancestorTypes = Set<String>()
		/// The concrete type of the node whose children the walk is at, or `nil` at the mock's root.
		var parentConcreteType: String?
		/// Whether the overrides of the node whose children the walk is at are reachable: no edge above it is in `cycleEdges`.
		var overridePathReachable = true
		/// The override path each configured type around the node the walk is at read, nearest last, with whether its
		/// node read its configuration rather than a closure: a node a cycle builds again, which its parent's configuration
		/// has no field for, reads the nearest one of its type (`MockLowering+CycleOverrides.swift`).
		var overridePathsByType = [String: [MockLowering.AncestorOverridePath]]()
		/// The labels `mock()` binds before its tree, which no node may bind again.
		let rootLabels: Set<String>
		/// The names `mock()` binds its overrides of what its tree receives only if available under, which a builder
		/// function beneath the root may declare again: the emitter names an override apart only at the root's level.
		var rootOverrideNames = Set<String>()
		/// The name of the override of each property instantiated only if available that nothing fulfills, which the type that
		/// declares the property binds it from (`RootSignature.unavailableDependencyOverrideNames`).
		var unavailableDependencyOverrideNames = [Property: String]()

		/// The declarations built around the node the walk is at, by label, innermost last: a node of a label one of them
		/// has binds it again in its own builder function, which hides the farther one, as Swift's lookup does.
		var ancestorDeclarationsByLabel = [String: [(declaration: ScopeGenerator.BuiltDeclaration, functionName: String, bodyLevel: Int)]]()
		/// The labels of the children of each builder function's body the walk is inside, outermost first: a builder
		/// function a body between a cycle closer and the node it repeats declares under that node's label would hide the
		/// node's function from the closer.
		var bodyLabels = [Set<String>]()
		// The names of the builder functions each body declares, which a cycle-closing node, declaring
		// none, is not among.
		/// The names of the builder functions the nodes of each body of `bodyLabels` declare, which a closer's reference
		/// could resolve to.
		var bodyFunctionNames = [Set<String>]()
		/// The name the level renames the builder function of the node the walk is about to build to
		/// (`ScopeGenerator.mockLoweringBuilderFunctionNames(of:boundAs:enclosingFunctionNames:)`), which that node takes.
		var pendingRenamedFunctionName: String?
		/// The names a receive is handed in place of its label, by label and then type: a node named apart from a sibling
		/// that shares its label (`ScopeGenerator.disambiguatePropertyLabels(forProperties:)`), which its receivers bind again under
		/// the label in their builder functions, until a declaration of the label hides it.
		// The flat parameters and overrides of `mock()` named apart, which seed it.
		var renames = [String: [TypeDescription: String]]()
		// The wrappers an internal mock binds around the instances it is passed, by label and type,
		// which a receive is passed by name, never bound again, until a declaration of the label hides it
		// (`lazilyInstantiatedBindingNames`).
		var lazilyInstantiatedNames = [String: [TypeDescription: String]]()
		// The wrappers a public mock takes as parameters, by label and type, which a fill reading the
		// caller's own wrapper binds its label to (`FillPlaceBindings.rootBindingNames`).
		var publicMockWrapperParameterNames = [String: [TypeDescription: String]]()
		/// The names the mock root's level gives the nodes it names apart, by label and then type, under which the mocked type
		/// is passed them.
		var rootRenames = [String: [TypeDescription: String]]()
		/// The names of the parameters of `mock()` named apart that uncovered dependencies are, by label and type.
		var uncoveredParameterNames = [String: [TypeDescription: String]]()
		// The `@Sendable` autoclosure parameters of `mock()`, by the property each stands for.
		// Also the places its builders build.
		var sendableAutoclosureBindings = [Property: ScopeGenerator.SendableAutoclosureParameter]()
		/// The names the property nodes of the mock root's level are bound under.
		var rootPropertyNodeBindingNames = Set<String>()
		/// The labels of the dependencies the tree receives that the mock cannot build, which an alias of the mock root's
		/// level is named apart from.
		var rootFlatReceivedLabels = Set<String>()
		/// The labels the builder functions of the root's tree declare, which an alias of the root's level is named apart from.
		var rootNamesDeclaredInBuilderFunctions = Set<String>()
		/// The properties of `mock()`'s forwarded and default-valued parameters, which keep their labels: a node of the mock
		/// root's level under one of their labels is named apart from them
		/// (`ScopeGenerator.disambiguatePropertyLabels(forProperties:besideParametersKeepingTheirLabels:reservedNames:)`).
		var rootParametersKeepingTheirLabels = [Property]()
		/// The properties of the mock root's level named apart from a parameter that keeps its label, which may bind a name
		/// apart from a label `mock()` binds.
		var rootPropertiesNamedApartFromParameters = Set<Property>()
		var labels = Set<String>()
		// The `@Instantiated` dependencies the mock cannot build, each a parameter of `mock()`.
		/// The properties of the `@Instantiated` dependencies the mock cannot build, which `mock()` takes, so the types that
		/// instantiate them are passed the parameter.
		var uncoveredProperties: Set<Property>
		// The configurations of the nodes the walk finished, children before their node.
		var configurationRecords = [ConfigurationRecord]()
		/// The default-valued parameters of each type's hand-written mock, by concrete type, whose defaults the fields of the
		/// type's configuration take (`MockLowering+Defaults.swift`).
		var handWrittenMockDefaultParameters = [TypeDescription: [ScopeGenerator.DefaultParameter]]()
		/// The constructions the walk has worked out, which every later node of the same type and declaration shares, as the
		/// emitter's nodes share theirs (`ScopeGenerator.MockConstructions`).
		var mockConstructions = ScopeGenerator.MockConstructions()

		/// The construction of a node of `instantiable`, built with its type's hand-written mock where `usesMockInitializer`.
		mutating func mockConstruction(of instantiable: Instantiable, usesMockInitializer: Bool) -> ScopeGenerator.MockConstruction {
			mockConstructions.construction(of: instantiable, useMockInitializer: usesMockInitializer, builderTypesDeclaredEscaping: [])
		}

		/// The concrete types whose configurations are `@Sendable`-typed, whose default fields are read as calls.
		var sendableConfigurationTypeNames = Set<String>()
		/// The concrete types of the configured nodes around the node the walk is at, and whether a node around it repeats one
		/// around it: a node of a type around it, or beneath such a node, records no configuration
		/// (`ScopeGenerator.collectUniqueConfigurationTypes`).
		var configuredAncestorTypes = Set<String>()
		var isBeneathRepeatedConfiguredAncestor = false
		// How many configured nodes' children the walk entered, which orders the one-way check's reads.
		var configuredNodesEntered = 0
		// The configured children each configured node around the walk has finished, innermost last.
		var finishedConfiguredChildren = [[MockLowering.FinishedConfiguredChild]]()
		// The builders `mock()` takes optional for the places its calls fill, and the calls not reached yet.
		var filledCallBuilders = FilledCallBuilders.none
		// A public mock builds each configured node with its type's construction function.
		/// Whether the walk lowers a public mock, whose configured nodes call their types' construction functions.
		var buildsPublicMock = false
		// The bindings the node around the walk is passed by name, which a payload bound inside its
		// builder function reads (`ScopeGenerator.MockValuesBinding.line`).
		var enclosingBindingNamesPassedByName = [String: String]()
		// The properties of the nodes a public mock promotes at its root's level, each bound from the
		// parameter its caller passes, named as its plan names it (`promotedParameterNames`).
		var promotedProperties = Set<Property>()
		// The names of the parameters the public mock takes for its promoted nodes, as its plan names
		// them (`PublicMockPlan.promotedParameterNames`).
		var promotedParameterNames = [Property: String]()
		// The extractor of the `@Sendable` builder function the walk is inside, and the names of each
		// level it is in, from which such a function's locals are claimed (`MockLowering+Wrappers.swift`).
		var sendableOverrideExtractor: ScopeGenerator.SendableOverrideExtractor?
		var levelNames = [GeneratedNameAllocator]()
		/// Whether the walk is inside a `@Sendable` builder function, whose nodes' override closures are `@Sendable`.
		var isInsideSendableFunction = false
		/// Whether the nodes the walk is at build what an actor's initializer is handed, outside every lazy wrapper's builder
		/// function: the initializer takes each argument into the actor's isolation, so in Swift 6 the argument must share no
		/// region with `safeDIOverrides`, which `mock()` is handed. Such a node reads its overrides into a local first, as a
		/// `@Sendable` builder function does, of the `Sendable` form (`ScopeGenerator.sendableConfigurationTypeNames(ofMockRootOf:)`), so no
		/// builder function beneath it captures the overrides; capturing them would join the argument to their region.
		var isInsideActorArgument = false
		// The loop of builders the node being built is a member of, the members of its level's loops,
		// the loop being emitted at the level, and how the last member's lines split (`MockLowering+Loops.swift`).
		var loopMembership: LoopMembership?
		var loopMembers = [Property: LoopMember]()
		var loopUnit: LoopUnit?
		var lastLoopMemberLineCounts: LoopMemberLineCounts?
		/// The receives only if available the node being lowered is passed `nil` for, given the siblings built before it.
		var unavailableProperties = Set<Property>()
		/// The properties built after the node being lowered, which its children are ordered by.
		var propertiesGeneratedLater = Set<Property>()
		// The path of child indices (`OrderedChild.index`) from the root to the node being lowered,
		// which keys what the walk reads per place.
		var childIndexPath = [Int]()

		/// The nodes `generators` build, in generation order, where the nodes `scope` holds are bound before them, their
		/// overrides at `path`, with their statements appended to `lines` at `indent`.
		mutating func children(
			of orderedChildren: [ScopeGenerator.OrderedChild],
			loops: [LoopMembership?] = [],
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async throws -> [TreeNode] {
			let generators = orderedChildren.map(\.generator)
			let enclosingPropertiesGeneratedLater = propertiesGeneratedLater
			defer { propertiesGeneratedLater = enclosingPropertiesGeneratedLater }
			var nodes = [TreeNode]()
			var scope = scope
			var bindingNames = levelBindingNames(of: generators)
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
				// A fill reading the caller's own value from the root's binding binds its label to the name
				// the root binds it apart under: a parameter, an override, a node of the level, or a wrapper `mock()` makes.
				var rootBindingNames = renames
				for (label, names) in lazilyInstantiatedNames.merging(publicMockWrapperParameterNames, uniquingKeysWith: { names, parameterNames in names.merging(parameterNames) { name, _ in name } }) {
					rootBindingNames[label, default: [:]].merge(names) { _, wrapperName in wrapperName }
				}
				filledCallBuilders.bindingRootNames(rootBindingNames)
				// The names the root's property nodes are bound under, which a rebinding of the mocked
				// type's own receive would redeclare.
				for (generator, bindingName) in zip(generators, bindingNames) {
					guard case .property = generator.scopeData, let bindingName else { continue }
					rootPropertyNodeBindingNames.insert(bindingName)
				}
			}
			// A level whose nodes take part in a cycle renames a builder function that would hide an
			// enclosing one a cycle-closing node beneath refers to, as the emitter does.
			// Each declaration's ancestors are listed under its one label, innermost last, which the closer resolves to.
			// The enclosing names are gathered only for a level that names a function apart, which nearly no level does.
			let renamedFunctionNames = ScopeGenerator.mockLoweringBuilderFunctionNames(of: generators, boundAs: bindingNames) {
				Dictionary(
					ancestorDeclarationsByLabel.values.joined()
						.filter { $0.functionName != MockLowering.builderFunctionName(boundAs: $0.declaration.property.label) }
						.map { ($0.declaration, $0.functionName) },
				) { _, innerFunctionName in innerFunctionName }
			}
			if !bodyFunctionNames.isEmpty {
				var functionNames = Set<String>()
				for (index, (generator, bindingName)) in zip(generators, bindingNames).enumerated() {
					switch generator.scopeData {
					case let .property(_, property, _, _, isPropertyCycle, _) where !isPropertyCycle:
						functionNames.insert(renamedFunctionNames?[index] ?? MockLowering.builderFunctionName(boundAs: bindingName ?? property.label))
					case .hole:
						// A site held in a wrapper declares the function the level names for it.
						if let holeFunctionName = renamedFunctionNames?[index] {
							functionNames.insert(holeFunctionName)
						}
					case .root, .fill, .alias, .property:
						continue
					}
				}
				bodyFunctionNames[bodyFunctionNames.count - 1] = functionNames
			}
			// The level's names, which a `@Sendable` builder function's locals are kept apart from.
			enterLevel(of: generators, boundAs: bindingNames, renamedFunctionNames: renamedFunctionNames)
			defer { leaveLevel() }
			// The loops of builders among the level's children, each emitted as one unit.
			let enclosingLoopMembers = loopMembers
			let enclosingLoopUnit = loopUnit
			// The enclosing functions a cycle-closing node beneath refers to by name are in scope too.
			// A level without a loop has no member, and nearly every level has none.
			loopMembers = loops.contains(where: { $0 != nil })
				? MockLowering.loopMembers(among: generators, loops: loops, bindingNames: bindingNames, namesInScope: Set(ancestorDeclarationsByLabel.values.flatMap { $0.map(\.functionName) }))
				: [:]
			loopUnit = nil
			defer {
				loopMembers = enclosingLoopMembers
				loopUnit = enclosingLoopUnit
			}
			for (index, (generator, bindingName)) in zip(generators, bindingNames).enumerated() {
				let membership = index < loops.count ? loops[index] : nil
				loopMembership = membership
				// What the node is built where its siblings ordered after it are not bound yet, as
				// the emitter orders the level (`ScopeGenerator.OrderedChild`).
				unavailableProperties = orderedChildren[index].unavailableProperties
				propertiesGeneratedLater = orderedChildren[index].propertiesGeneratedLater
				var memberLines = [String]()
				pendingRenamedFunctionName = renamedFunctionNames?[index]
				childIndexPath.append(orderedChildren[index].index)
				let node: TreeNode?
				if membership == nil {
					endLoopUnit(appendingTo: &lines)
					node = try await self.node(of: generator, bindingName: bindingName, inScope: scope, path: path, indent: indent, lines: &lines)
				} else if case .alias = generator.scopeData {
					// A rename the level declares of a member is bound with the loop's wrappers, after
					// them, and its members' functions bind it again (`MockLowering.loopMembers`).
					node = try await self.node(of: generator, bindingName: bindingName, inScope: scope, path: path, indent: indent, lines: &memberLines)
					lastLoopMemberLineCounts = MockLowering.LoopMemberLineCounts(prelude: 0, binding: memberLines.count)
				} else {
					// A call of another module's public mock on a loop reads in its function the members it
					// rebinds there, and names its guard where its level makes it, before the loop's unit, as the emitter names it.
					// A call that fills a builder names its guard inside its function, after its fills.
					let memberScope = generator.publicMockCall == nil ? scope : scope.union(generator.reboundProperties)
					node = try await self.node(of: generator, bindingName: bindingName, inScope: memberScope, path: path, indent: indent, lines: &memberLines)
					if generator.publicMockCall != nil, !generator.fillsABuilder {
						lines.append(memberLines.removeFirst())
					}
				}
				childIndexPath.removeLast()
				loopMembership = nil
				pendingRenamedFunctionName = nil
				if let node {
					nodes.append(node)
					scope.insert(node.property)
				}
				if let membership {
					append(memberLines, ofMemberOf: membership, to: &lines)
				}
			}
			endLoopUnit(appendingTo: &lines)
			return nodes
		}

		/// The name each of `generators`, one level's nodes, is bound under, `nil` for a node that is no property node: its
		/// label, or, where property nodes of the level share it, a name apart, as
		/// `ScopeGenerator.disambiguatePropertyLabels(forProperties:)` names it.
		private mutating func levelBindingNames(of generators: [ScopeGenerator]) -> [String?] {
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
			guard !collidingLabels.isEmpty else { return propertyNodes.map { $0?.label } }
			let collidingProperties = propertyNodes.compactMap { property in property.flatMap { collidingLabels.contains($0.label) ? $0 : nil } }
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
			if bodyLabels.isEmpty {
				rootPropertiesNamedApartFromParameters.formUnion(collidingProperties.filter { collidingParameterLabels.contains($0.label) || rootOverrideNames.contains($0.label) })
			}
			return propertyNodes.map { property in property.map { nameByProperty[$0] ?? $0.label } }
		}

		/// Names apart each alias of the mock root's level, among `generators`, whose label a property node of the level, or a
		/// flat received parameter of `mock()`, binds, as `ScopeGenerator.renamingAliases` does: `<label>_<simplified type>`,
		/// `_` appended while the name is taken, set as the alias's entry of `bindingNames`.
		/// The names the mock root's level, `generators`, binds its nodes under, as the walk names them when it reaches the
		/// level; named on a copy, so the walk's own record of the names it keeps apart starts empty.
		func rootLevelBindingNames(of generators: [ScopeGenerator]) -> [String?] {
			var walk = self
			return walk.levelBindingNames(of: generators)
		}

		private mutating func nameRootAliasesApart(among generators: [ScopeGenerator], bindingNames: inout [String?]) {
			let propertyNodeNames = Set(zip(generators, bindingNames).compactMap { generator, bindingName in
				generator.mockLoweringBuiltProperty == nil ? nil : bindingName
			})
			let aliases: [(index: Int, property: Property)] = generators.enumerated().compactMap { index, generator in
				guard case let .alias(property, _, _, _, _) = generator.scopeData else { return nil }
				return (index, property)
			}
			// The root binds each override of what its tree receives only if available under its name
			// before the tree, as it binds its property nodes (`MockRootTopLevelNames.rootBindingNames`).
			let redeclaredNames = propertyNodeNames.union(rootFlatReceivedLabels).union(rootOverrideNames)
			var takenNames = propertyNodeNames.union(rootLabels).union(aliases.map(\.property.label)).union(rootNamesDeclaredInBuilderFunctions)
			for alias in aliases where redeclaredNames.contains(alias.property.label) {
				var name = "\(alias.property.label)_\(alias.property.typeDescription.simplified.asIdentifier)".spelledAsJoinedIdentifier
				while !takenNames.insert(name).inserted {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				bindingNames[alias.index] = name
			}
		}

		/// The node of `generator`, built after the nodes `scope` holds, whose statements are appended to `lines`; `nil` for a
		/// generator that is no node of a mock's tree.
		@inline(never)
		private mutating func node(
			of generator: ScopeGenerator,
			bindingName: String?,
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async throws -> TreeNode? {
			if case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference) = generator.scopeData {
				return aliasNode(of: generator, property: property, fulfillingProperty: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, onlyIfAvailable: onlyIfAvailable, declarationReference: declarationReference, bindingName: bindingName, inScope: scope, indent: indent, lines: &lines)
			} else if case let .property(_, property, _, _, _, _) = generator.scopeData, generator.isUnavailableDependency {
				// A property instantiated only if available that nothing fulfills is bound where production binds it to `nil`,
				// from the override `mock()` takes of it, so it reads no declaration above its type. It is `nil` inside a
				// `@Sendable` builder function, which could not capture the override, and where `mock()` takes none.
				let overrideName = isInsideSendableFunction ? nil : unavailableDependencyOverrideNames[property]
				let binding = AliasBinding(
					property: property,
					bindingName: bindingName ?? property.label,
					fulfillingProperty: property,
					fulfillingName: overrideName.map { "\(ReservedName.mockOverridesParameterName).\($0)" } ?? property.label,
					isErased: false,
					isOnlyIfAvailable: true,
					isBoundToNil: overrideName == nil,
					declarationReference: nil,
				)
				lines.append(binding.bindingLines(indent: indent))
				return .alias(binding)
			} else {
				// A hole site and a fill, the kinds of node a public mock's tree holds besides properties
				// and aliases, and a call of another module's public mock (`MockLowering+PublicMocks.swift`).
				guard case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall) = generator.scopeData,
				      let bindingName
				else { return await placeOrFillNode(of: generator, inScope: scope, path: path, indent: indent, lines: &lines) }
				if let publicMockCall = generator.publicMockCall {
					// A public mock binds the payload of a case of a place inside the call's fills before the
					// call's builder function, as before any node's.
					lines.append(contentsOf: generator.valuesBindingsBeforeBuilderFunction.map { "\(indent)\($0.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: [:]))" })
					return try await publicMockCallNode(of: generator, publicMockCall: publicMockCall, building: (instantiable, property, forwardedProperties, erasedToConcreteExistential), inScope: scope, path: path, indent: indent, lines: &lines)
				} else if isPropertyCycle {
					return cycleClosingNode(of: generator, instantiable: instantiable, property: property, bindingName: bindingName, inScope: scope, indent: indent, lines: &lines)
				}
				return try await .built(builtNode(
					of: generator,
					building: (instantiable, property, forwardedProperties, erasedToConcreteExistential, isPropertyCycle, seamCall),
					boundAs: bindingName,
					inScope: scope,
					path: path,
					indent: indent,
					lines: &lines,
				))
			}
		}

		/// The node of `generator`, an alias of `fulfillingProperty` as `property`, whose statement is appended to `lines`.
		/// Synchronous and never inlined into `node(of:…)`, whose `async` frame the task keeps for every
		/// level of the tree being walked.
		@inline(never)
		private mutating func aliasNode(
			of generator: ScopeGenerator,
			property: Property,
			fulfillingProperty: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: AliasDeclarationReferences.Reference?,
			bindingName: String?,
			inScope scope: Set<Property>,
			indent: String,
			lines: inout [String],
		) -> TreeNode {
			// An alias only if available is bound to `nil` where its fulfilling property is
			// unavailable, as production binds it (`ScopeGenerator.aliasIsBoundToNil`), and otherwise from the property in
			// scope.
			let isBoundToNil = ScopeGenerator.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: unavailableProperties)
			// An alias only if available reads the node of its label the scope holds in the other
			// optionality, which the mock binds non-optional: `let y: X? = x` from a promoted `x: X`, and
			// `let aBuilderAlias: Instantiator<A>? = aBuilder` from a node promoted for `aBuilder: Instantiator<A>?`.
			// A required alias of an optional form reads the node of its label the mock binds
			// non-optional, as a promoted `x: X` beside a rename `ofType: X?.self`.
			let scopeFulfillingProperty = scope.contains(fulfillingProperty) || !onlyIfAvailable && !fulfillingProperty.typeDescription.isOptional
				? fulfillingProperty
				: fulfillingProperty.typeDescription.isOptional ? fulfillingProperty.asUnwrappedProperty : fulfillingProperty.asOptionalProperty
			// An alias of the instance of a `LazilyInstantiated` its scope holds reads the wrapper's
			// instance, from the name the wrapper is bound apart under, as `emitAliasBinding` reads it.
			let instanceWrapper: Property? = if !isBoundToNil, generator.mockLoweringFulfillingPropertyIsLazilyInstantiatedInstance {
				[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
					.map { Property(label: fulfillingProperty.label, typeDescription: .simple(name: $0, generics: [fulfillingProperty.typeDescription.unwrapped])) }
					.first { scope.contains($0) }
			} else {
				nil
			}
			// An alias of a label named apart reads the name it is handed; one the mock root's level names apart is bound
			// under its name.
			let aliasBindingName = bindingName ?? property.label
			let alias = AliasBinding(
				property: property,
				bindingName: aliasBindingName,
				fulfillingProperty: fulfillingProperty,
				fulfillingName: instanceWrapper.map { wrapper in
					// A public mock's wrapper parameter is named apart where its root binds another value of the label
					// (`instancesReadThroughPublicMockWrapperParameters`).
					let wrapperName = renames[wrapper.label]?[wrapper.typeDescription]
						?? (buildsPublicMock ? publicMockWrapperParameterNames[wrapper.label]?[wrapper.typeDescription] : nil)
						?? wrapper.label
					return "\(wrapperName).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} ?? lazilyInstantiatedNames[fulfillingProperty.label]?[scopeFulfillingProperty.typeDescription] ?? renames[fulfillingProperty.label]?[scopeFulfillingProperty.typeDescription] ?? fulfillingProperty.label,
				isErased: erasedToConcreteExistential,
				isOnlyIfAvailable: onlyIfAvailable,
				isBoundToNil: isBoundToNil,
				declarationReference: declarationReference,
			)
			lines.append(alias.bindingLines(indent: indent))
			return .alias(alias)
		}

		/// Whether a node of `concreteType` beneath a node of `parentConcreteType` is beneath an edge in `cycleEdges`: its
		/// parent's configuration has no field for it, so neither it nor anything beneath it reads an override. The one
		/// question the walk asks of the cycle edges.
		func isPruned(_ concreteType: TypeDescription, beneath parentConcreteType: String?) -> Bool {
			// Nearly every mock graph has no cycle edge, and spelling the type is most of the question's cost.
			guard !cycleEdges.isEmpty, let parentConcreteType else { return false }
			return cycleEdges.contains(ScopeGenerator.CycleEdge(parent: parentConcreteType, child: concreteType.asSource))
		}

		/// The node of `generator`, which closes a cycle on a node around it of `property`, built as `instantiable`, whose
		/// statement is appended to `lines`: it calls that node's builder function, or hands it to its wrapper, and reads no
		/// override, since the function reads the node's.
		@inline(never)
		private mutating func cycleClosingNode(
			of generator: ScopeGenerator,
			instantiable: Instantiable,
			property: Property,
			bindingName: String,
			inScope scope: Set<Property>,
			indent: String,
			lines: inout [String],
		) -> TreeNode {
			// The node is the innermost declaration around the closer of the one it repeats, and every body between the two
			// names its builder functions apart from that node's (`ScopeGenerator.mockLoweringBuilderFunctionNames`), so the
			// closer reads the node's function by the name it is built with: its label's, or the name its level renames it
			// to or names it apart by (`BuilderFunctionNames.enclosingFunctionNames`). A lazy wrapper closes
			// on a constant declaration of its instance, and a constant on a lazy wrapper's, by the same function.
			let closedOnFunctionName = ancestorDeclarationsByLabel[property.label]?.last(where: { $0.declaration == generator.closedOnDeclaration })?.functionName ?? MockLowering.builderFunctionName(boundAs: property.label)
			let forwardedProperties = instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label }
			// A closer of any wrapper kind hands the function to its wrapper, inside a `@Sendable`
			// builder function too, since it reads no override.
			// A closer passes the function's cycle parameters (`MockLowering+CycleParameters.swift`); a
			// closer on a loop of builders passes a member of the level's loops its `_received` function wraps again.
			let cycleParameterArguments = MockLowering.cycleParameterArguments(of: generator, inScope: loopMembership == nil ? scope : scope.union(loopMembers.keys), unavailableProperties: unavailableProperties, renames: renames, lazilyInstantiatedNames: lazilyInstantiatedNames)
			// A closer on a loop of builders declares the `_received` function its wrappers hand, with
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
				return .cycleClosing(property, bindingName: bindingName, concreteType: instantiable.concreteInstantiable)
			}
			lines.append(contentsOf: MockLowering.bindingLines(
				of: property,
				boundAs: bindingName,
				callingFunctionNamed: closedOnFunctionName,
				forwardedProperties: forwardedProperties,
				cycleParameterArguments: cycleParameterArguments,
				indent: indent,
			))
			return .cycleClosing(property, bindingName: bindingName, concreteType: instantiable.concreteInstantiable)
		}

		/// The node of `generator`, which builds `built`, whose statements are appended to `lines`: its override when set, else its construction, in a builder function where it builds children. Only the walk of
		/// the node’s children is `async`: the task keeps this function’s frame for every level of the tree being walked, so
		/// what the node decides before and after its children is in two synchronous functions, never inlined here, and the
		/// frame holds one reference to what the first hands the second.
		@inline(never)
		private mutating func builtNode(
			of generator: ScopeGenerator,
			building built: (instantiable: Instantiable, property: Property, forwardedProperties: Set<Property>, erasedToConcreteExistential: Bool, isPropertyCycle: Bool, seamCall: SeamCall?),
			boundAs bindingName: String,
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) async throws -> ConstantNode {
			let descending: DescendingBuiltNode
			switch startBuiltNode(of: generator, building: built, boundAs: bindingName, inScope: scope, path: path, indent: indent, lines: &lines) {
			case let .finished(node):
				return node
			case let .descending(started):
				descending = started
			}
			let children = try await children(
				of: descending.orderedChildren,
				loops: descending.generator.mockLoweringLoopMemberships,
				inScope: descending.scope.union(descending.forwarded),
				path: descending.nodePath,
				indent: "\(descending.indent)\(ScopeGenerator.standardIndent)",
				lines: &lines,
			)
			return finishBuiltNode(descending, children: children, lines: &lines)
		}

		/// What `builtNode(of:…)` decided before the walk of the node’s children, which it reads after it: a class, so the
		/// `async` frame holds one reference, freed when the node is finished.
		private final class DescendingBuiltNode {
			let generator: ScopeGenerator
			let instantiable: Instantiable
			let property: Property
			let bindingName: String
			let indent: String
			let scope: Set<Property>
			let forwarded: [Property]
			let orderedChildren: [ScopeGenerator.OrderedChild]
			let isWrapped: Bool
			let unavailableProperties: Set<Property>
			let initializer: Initializer
			let usesMockInitializer: Bool
			let ownLoopMembership: LoopMembership?
			let cycleParameterArguments: [String]
			let builder: String
			let nodePath: String
			let overrideReachable: Bool
			let overrideRead: String?
			let dependencyArguments: [(label: String, value: String)]
			let lazilyInstantiatedInstanceProperties: Set<Property>
			let startsExtraction: Bool
			let enclosingExtractor: ScopeGenerator.SendableOverrideExtractor?
			let wasInsideSendableFunction: Bool
			let wasInsideActorArgument: Bool
			let valuesBindingLines: [String]
			let declarationIndex: Int
			let insertedAncestor: Bool
			let cycleNodeKey: String
			let siblingLabels: Set<String>
			let enclosingParentConcreteType: String?
			let enclosingOverridePathReachable: Bool
			let enclosingRenames: [String: [TypeDescription: String]]
			let enclosingLazilyInstantiatedNames: [String: [TypeDescription: String]]
			let bindingNamesPassedByNameAround: [String: String]
			let configurationEntry: ConfiguredNodeEntry
			var node: ConstantNode

			init(
				generator: ScopeGenerator,
				instantiable: Instantiable,
				property: Property,
				bindingName: String,
				indent: String,
				scope: Set<Property>,
				forwarded: [Property],
				orderedChildren: [ScopeGenerator.OrderedChild],
				isWrapped: Bool,
				unavailableProperties: Set<Property>,
				initializer: Initializer,
				usesMockInitializer: Bool,
				ownLoopMembership: LoopMembership?,
				cycleParameterArguments: [String],
				builder: String,
				nodePath: String,
				overrideReachable: Bool,
				overrideRead: String?,
				dependencyArguments: [(label: String, value: String)],
				lazilyInstantiatedInstanceProperties: Set<Property>,
				startsExtraction: Bool,
				enclosingExtractor: ScopeGenerator.SendableOverrideExtractor?,
				wasInsideSendableFunction: Bool,
				wasInsideActorArgument: Bool,
				valuesBindingLines: [String],
				declarationIndex: Int,
				insertedAncestor: Bool,
				cycleNodeKey: String,
				siblingLabels: Set<String>,
				enclosingParentConcreteType: String?,
				enclosingOverridePathReachable: Bool,
				enclosingRenames: [String: [TypeDescription: String]],
				enclosingLazilyInstantiatedNames: [String: [TypeDescription: String]],
				bindingNamesPassedByNameAround: [String: String],
				configurationEntry: ConfiguredNodeEntry,
				node: ConstantNode,
			) {
				self.generator = generator
				self.instantiable = instantiable
				self.property = property
				self.bindingName = bindingName
				self.indent = indent
				self.scope = scope
				self.forwarded = forwarded
				self.orderedChildren = orderedChildren
				self.isWrapped = isWrapped
				self.unavailableProperties = unavailableProperties
				self.initializer = initializer
				self.usesMockInitializer = usesMockInitializer
				self.ownLoopMembership = ownLoopMembership
				self.cycleParameterArguments = cycleParameterArguments
				self.builder = builder
				self.nodePath = nodePath
				self.overrideReachable = overrideReachable
				self.overrideRead = overrideRead
				self.dependencyArguments = dependencyArguments
				self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
				self.startsExtraction = startsExtraction
				self.enclosingExtractor = enclosingExtractor
				self.wasInsideSendableFunction = wasInsideSendableFunction
				self.wasInsideActorArgument = wasInsideActorArgument
				self.valuesBindingLines = valuesBindingLines
				self.declarationIndex = declarationIndex
				self.insertedAncestor = insertedAncestor
				self.cycleNodeKey = cycleNodeKey
				self.siblingLabels = siblingLabels
				self.enclosingParentConcreteType = enclosingParentConcreteType
				self.enclosingOverridePathReachable = enclosingOverridePathReachable
				self.enclosingRenames = enclosingRenames
				self.enclosingLazilyInstantiatedNames = enclosingLazilyInstantiatedNames
				self.bindingNamesPassedByNameAround = bindingNamesPassedByNameAround
				self.configurationEntry = configurationEntry
				self.node = node
			}
		}

		/// How `startBuiltNode(of:…)` ends: with the node, or with what the walk of its children needs.
		private enum BuiltNodeStart {
			case finished(ConstantNode)
			case descending(DescendingBuiltNode)
		}

		/// The part of `builtNode(of:…)` before the walk of the node’s children.
		@inline(never)
		private mutating func startBuiltNode(
			of generator: ScopeGenerator,
			building built: (instantiable: Instantiable, property: Property, forwardedProperties: Set<Property>, erasedToConcreteExistential: Bool, isPropertyCycle: Bool, seamCall: SeamCall?),
			boundAs bindingName: String,
			inScope scope: Set<Property>,
			path: String,
			indent: String,
			lines: inout [String],
		) -> BuiltNodeStart {
			let (instantiable, property, _, erasedToConcreteExistential, _, _) = built
			let renamedFunctionName = pendingRenamedFunctionName
			pendingRenamedFunctionName = nil
			let cycleNodeKey = MockLowering.cycleNodeKey(of: property, builtAs: instantiable)
			// A node that repeats a node around it reads no override of its own, and one beneath an edge in `cycleEdges`
			// reads none of its own or beneath it: its parent's configuration has no field for it.
			let isCycleNode = ancestorTypes.contains(cycleNodeKey)
			let ownFieldReachable = overridePathReachable && !isPruned(instantiable.concreteInstantiable, beneath: parentConcreteType)
			let isErased = erasedToConcreteExistential
			let isFulfilledByAnotherType = property.typeDescription.asInstantiatedType != instantiable.concreteInstantiable
			// Every wrapper kind builds its type in a builder function, as an `Instantiator` does,
			// erased or fulfilled by another type alike (`MockLowering+Wrappers.swift`).
			let isWrapped = !property.propertyType.isConstant
			// A node built by value is handed no forwarded value: its construction reads each by name from
			// the scope, as the emitter's argument list does, in a graph production rejects (`mockCanBuild`).
			let forwarded = isWrapped ? instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label } : []
			// A receive only if available the node is built where nothing provides is passed `nil`.
			// A member of a loop of builders is passed the wrappers its function makes again, and its type the parameters a lazy
			// cycle closing on its function takes, as production passes them
			// (`ownUnavailableProperties` in `ScopeGenerator`).
			let unavailableProperties = generator.mockLoweringBodyUnavailableProperties(unavailableProperties)
			// A node whose type's hand-written mock returns a type its property can hold is built with the
			// mock, as `MockConstruction(useMockInitializer:)` says, where the mock returns the concrete type, in an internal mock.
			let usesMockInitializer = instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType)
			// An argument of the mock neither a dependency fulfills nor a default fills reads its node's
			// configuration as a default does (`resolveBuilderArguments`), in a build that compiles no mock
			// (`UnfulfilledMockParameter`).
			// A public mock builds such a node with its construction function, as an internal mock does
			// with the mock (`publicConstructionArguments`).
			let initializer = (usesMockInitializer ? instantiable.mockInitializer : instantiable.initializer) ?? Initializer(arguments: [])

			// The node's builder function binds what it rebinds and its cycle parameters before its
			// children, as the emitter orders them (`bodyPropertiesGeneratedLater`).
			let orderedChildren = generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: generator.mockLoweringBodyPropertiesGeneratedLater(propertiesGeneratedLater))
			let childGenerators = orderedChildren.map(\.generator)
			// A member of a loop of builders first rebinds the members its tree receives
			// (`MockLowering+Loops.swift`).
			var rebindingLines = [String]()
			// The walk of the node's children sets and clears the membership of each child.
			let ownLoopMembership = loopMembership
			if ownLoopMembership != nil {
				var memberRebindingLines = MockLowering.rebindingLines(of: generator.reboundProperties, among: loopMembers, ownProperty: property, indent: "\(indent)\(ScopeGenerator.standardIndent)")
				// A member a public mock promotes at its root is rebound as the caller's own where it passed
				// one.
				if parentConcreteType == nil, generator.reboundProperties.contains(where: promotedProperties.contains) {
					memberRebindingLines = []
					for reboundProperty in generator.reboundProperties {
						if let member = loopMembers[reboundProperty], promotedProperties.contains(reboundProperty), member.rename == nil, reboundProperty != property || member.receivedFunctionName == nil {
							memberRebindingLines.append(MockLowering.promotedWrapperBindingLine(of: member.typeDescription, named: member.bindingName, passing: member.bindingName, handing: member.functionName, forwardedProperties: member.forwardedProperties, indent: "\(indent)\(ScopeGenerator.standardIndent)"))
						} else {
							memberRebindingLines.append(contentsOf: MockLowering.rebindingLines(of: [reboundProperty], among: loopMembers, ownProperty: property, indent: "\(indent)\(ScopeGenerator.standardIndent)"))
						}
					}
				}
				rebindingLines = memberRebindingLines
			}
			// What the node's binding passes its builder function's cycle parameters, read where the node
			// is built, and the parameters, the nearest declarations of their labels in the function. A member of a loop of
			// builders passes a member of the level's loops its `_received` function wraps again (`receivedFunctionLines`).
			let cycleParameterArguments = MockLowering.cycleParameterArguments(of: generator, inScope: ownLoopMembership == nil ? scope : scope.union(loopMembers.keys), unavailableProperties: self.unavailableProperties, renames: renames, lazilyInstantiatedNames: lazilyInstantiatedNames)
			let scope = scope.union(generator.reboundProperties).union(MockLowering.cycleParameterForms(of: generator))
			// A `Sendable` wrapper's, or a cycle's, builder function is `@Sendable`, and every override
			// read inside it is read into a local before the outermost such function.
			let builder = ReservedName.configurationBuilderPropertyName
			// A default-valued parameter is a field of the node's configuration (`MockLowering+Defaults.swift`).
			let defaultFields = configurationDefaultFields(of: instantiable, usesMockInitializer: usesMockInitializer)
			let hasConfiguration = childGenerators.contains { $0.mockLoweringBuiltProperty != nil } || !defaultFields.isEmpty
			// A node a cycle builds again reads the overrides of the nearest node of its type around it
			// (`MockLowering+CycleOverrides.swift`).
			let ownOverridePath = MockLowering.AncestorOverridePath.own(
				path: "\(path).\(bindingName)",
				hasConfiguration: hasConfiguration,
				builtWithHandWrittenMock: usesMockInitializer,
				isReachable: !isCycleNode && ownFieldReachable,
				nearest: overridePathsByType[instantiable.concreteInstantiable.asSource]?.last,
			)
			let nodePath = ownOverridePath?.path ?? "\(path).\(bindingName)"
			let overrideReachable = ownOverridePath != nil
			// The node's builder function binds again under its label each receive named apart, from the names its own
			// declarations, its children, forwarded properties and cycle parameters, do not hide (`ScopeGenerator.removingRenames`).
			// Nor do the dependencies its type instantiates that the mock cannot build, whose receives
			// beneath read the parameter `mock()` takes under its label (`routingReceives`).
			let uncoveredInstantiatedProperties = instantiable.dependencies.compactMap { dependency -> Property? in
				guard case .instantiated = dependency.source, uncoveredProperties.contains(dependency.property) else { return nil }
				return dependency.property
			}
			let declarationsHidingRenames = childGenerators.compactMap(\.property) + (isWrapped ? forwarded : []) + MockLowering.cycleParameterForms(of: generator).sorted() + uncoveredInstantiatedProperties
			var functionRenames = MockLowering.removingRenames(hiddenBy: declarationsHidingRenames, from: renames)
			// The wrappers `mock()` binds that the node's builder function does not hide, which its
			// construction reads where a lazy cycle closes on the function (`builderLazilyInstantiatedBindingNames`).
			let functionLazilyInstantiatedNames = MockLowering.removingRenames(hiddenBy: declarationsHidingRenames, from: lazilyInstantiatedNames)
			let argumentLazilyInstantiatedNames = generator.cycleParameters.isEmpty ? lazilyInstantiatedNames : functionLazilyInstantiatedNames
			MockLowering.routeReceives(of: uncoveredInstantiatedProperties, toParametersNamed: uncoveredParameterNames, in: &functionRenames)
			var receiverBindings = [(property: Property, name: String)]()
			var publicWrapperParametersReadByName = [String: String]()
			let functionPublicMockWrapperParameterNames = buildsPublicMock ? MockLowering.removingRenames(hiddenBy: declarationsHidingRenames, from: publicMockWrapperParameterNames) : [:]
			for dependency in instantiable.dependencies {
				// A receive the node passes `nil` is not rebound (`emitReceiverBindings`): the name may not be declared yet.
				guard case .received = dependency.source, !unavailableProperties.contains(dependency.property) else { continue }
				let isInstanceOfLazyWrapper = generator.mockLoweringLazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty)
				// A public mock's wrapper parameter is no rename: a type that reads its instance reads it by name
				// (`lazilyInstantiatedBindingNameMap`).
				let wrapperParameterNames = isInstanceOfLazyWrapper && buildsPublicMock ? functionPublicMockWrapperParameterNames[dependency.property.label] : nil
				guard let names = functionRenames[dependency.property.label] ?? wrapperParameterNames else { continue }
				if isInstanceOfLazyWrapper {
					// A receive of a lazy wrapper's instance binds the wrapper named apart again, whose instance its
					// construction reads.
					let instanceType = dependency.property.typeDescription.unwrapped
					guard let wrapper = [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
						.lazy
						.map({ TypeDescription.simple(name: $0, generics: [instanceType]) })
						.compactMap({ wrapper in names[wrapper].map { (property: Property(label: dependency.property.label, typeDescription: wrapper), name: $0) } })
						.first
					else { continue }
					// A public mock's wrapper parameter is read by name, its instance where the
					// construction reads it, with no binding again (`dependencyArgument`, `lazilyInstantiatedBindingNames`).
					// A wrapper node the root's level names apart is bound again, as any receive named apart is.
					if buildsPublicMock, !rootPropertyNodeBindingNames.contains(wrapper.name) {
						publicWrapperParametersReadByName[dependency.property.label] = wrapper.name
					} else {
						receiverBindings.append(wrapper)
					}
				} else if let name = names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription] {
					receiverBindings.append((dependency.property, name))
				}
			}
			// A receive named apart whose label a receive beneath reads by name is handed the name instead of bound again
			// under its label, which would hide the binding that receive reads (`ScopeGenerator.receivedBindingNamesPassedByName`).
			var bindingNamesPassedByName = publicWrapperParametersReadByName
			if !childGenerators.isEmpty {
				for binding in receiverBindings where MockLowering.receiveReadsLabelByName(binding.property.label, beneath: orderedChildren, renames: renames, lazilyInstantiatedNames: functionLazilyInstantiatedNames, publicMockNodeBindingNames: buildsPublicMock ? rootPropertyNodeBindingNames : nil) {
					bindingNamesPassedByName[binding.property.label] = binding.name
				}
				receiverBindings.removeAll { bindingNamesPassedByName[$0.property.label] != nil }
			}
			let overrideRead: String? = !overrideReachable ? nil : readingOverride(
				hasConfiguration ? "\(nodePath).\(builder)" : nodePath,
				localNameSuffix: "\(GeneratedCodeText.overrideRelativePath(of: nodePath))_\(builder)",
			)
			let dependencyArguments = MockLowering.argumentValues(
				of: initializer,
				given: instantiable.dependencies,
				lazilyInstantiatedInstanceProperties: generator.mockLoweringLazilyInstantiatedInstanceProperties,
				unavailableProperties: unavailableProperties,
				bindingNamesPassedByName: MockLowering.passingWrappersByName(argumentLazilyInstantiatedNames, to: instantiable.dependencies, besides: bindingNamesPassedByName),
				uncoveredParameterNames: uncoveredParameterNames,
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
				// Each default-valued parameter read from the node's configuration, among its dependencies.
				arguments: constructionArguments(
					of: initializer,
					given: instantiable,
					usesMockInitializer: usesMockInitializer,
					dependencyArguments: dependencyArguments,
					nodePath: nodePath,
					overrideReachable: overrideReachable,
				),
				buildsInSendableFunction: generator.buildsInSendableFunction,
				requiresSendable: isInsideSendableFunction || generator.buildsInSendableFunction || isInsideActorArgument,
				defaultFields: defaultFields,
			)
			node.cycleParameters = generator.cycleParameters.map(\.property)
			node.renamedFunctionName = renamedFunctionName
			node.sendableAutoclosureBindings = uncoveredInstantiatedProperties.compactMap { sendableAutoclosureBindings[$0] }
			// A node a public mock promotes at its root's level reads its caller's value first.
			if parentConcreteType == nil, promotedProperties.contains(property) {
				node.promotedParameterName = promotedParameterNames[property] ?? bindingName
			}
			node.cycleParameterArguments = cycleParameterArguments
			// A place of another module's public mock the tree builds inline reads the builder `mock()`
			// takes for its hole type and family (`MockLowering+PublicMockCalls.swift`).
			if let inlinePlaceBuilder = filledCallBuilders.holeBuildersByInlinePlace[childIndexPath] {
				node.inlinePlace = InlinePlace(builder: inlinePlaceBuilder, overrideRead: overrideRead)
			}
			let lazilyInstantiatedInstanceProperties = generator.mockLoweringLazilyInstantiatedInstanceProperties
			// A node whose configuration holds its default-valued parameters is built in a builder
			// function.
			guard node.hasChildren || isWrapped || !receiverBindings.isEmpty || !defaultFields.isEmpty || !node.sendableAutoclosureBindings.isEmpty else {
				lines.append(node.constantBindingLine(overrideRead: overrideRead, indent: indent))
				return .finished(node)
			}
			// A node that builds an actor's argument reads its overrides as a `@Sendable` builder function does, so that no builder
			// function beneath it captures `safeDIOverrides`.
			let startsForSendableFunction = sendableOverrideExtractor == nil && (generator.buildsInSendableFunction || isInsideActorArgument)
			// So does one whose construction passes a configuration read to a `@Sendable` autoclosure, which would capture
			// the overrides the read names; a public mock passes the read to the type's construction function instead. Its
			// configuration may be the plain form, which is not `Sendable`, so that function reads each field.
			let startsExtraction = startsForSendableFunction || (
				sendableOverrideExtractor == nil
					&& !buildsPublicMock
					&& overrideReachable
					&& constructionPassesConfigurationReadToSendableAutoclosure(of: instantiable, usesMockInitializer: usesMockInitializer)
			)
			// A function that builds a node with a configuration reads that configuration whole into one local: its type is built
			// in a `@Sendable` function, so the configuration takes the `Sendable` form, and every configuration beneath it
			// does too (`ScopeGenerator.sendableConfigurationTypeNames(ofMockRootOf:)`), so each field is proven `Sendable` and the
			// configuration is `Sendable`. A public mock's configurations are never `Sendable`, so its functions read each field.
			let configurationPath = startsForSendableFunction && hasConfiguration && !buildsPublicMock ? nodePath : nil
			let enclosingExtractor = startsExtraction ? startExtraction(inFunctionNamed: node.functionName, configurationPath: configurationPath) : sendableOverrideExtractor
			let wasInsideSendableFunction = isInsideSendableFunction
			isInsideSendableFunction = node.requiresSendable
			let wasInsideActorArgument = isInsideActorArgument
			// The node's children are its initializer's arguments: an actor's, or, outside a lazy wrapper's builder
			// function, what an enclosing actor's argument is built from.
			isInsideActorArgument = (instantiable.declarationType == .actorType && !usesMockInitializer) || (isInsideActorArgument && !isWrapped)
			// The payloads of the cases nested by type that lead through the node to a place, bound before
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
			// The level's names are known once `children(of:…)` names its nodes, which fills this.
			bodyFunctionNames.append([])
			let siblingLabels = labels
			labels = []
			let enclosingParentConcreteType = parentConcreteType
			let enclosingOverridePathReachable = overridePathReachable
			let enclosingRenames = renames
			renames = functionRenames
			let enclosingLazilyInstantiatedNames = lazilyInstantiatedNames
			lazilyInstantiatedNames = functionLazilyInstantiatedNames
			let bindingNamesPassedByNameAround = enclosingBindingNamesPassedByName
			enclosingBindingNamesPassedByName = bindingNamesPassedByName
			parentConcreteType = instantiable.concreteInstantiable.asSource
			overridePathReachable = overrideReachable
			if let ownOverridePath {
				overridePathsByType[instantiable.concreteInstantiable.asSource, default: []].append(ownOverridePath)
			}
			// The configured types around the node's children.
			let configurationEntry = enteringConfiguredNode(of: instantiable.concreteInstantiable)
			return .descending(DescendingBuiltNode(
				generator: generator,
				instantiable: instantiable,
				property: property,
				bindingName: bindingName,
				indent: indent,
				scope: scope,
				forwarded: forwarded,
				orderedChildren: orderedChildren,
				isWrapped: isWrapped,
				unavailableProperties: unavailableProperties,
				initializer: initializer,
				usesMockInitializer: usesMockInitializer,
				ownLoopMembership: ownLoopMembership,
				cycleParameterArguments: cycleParameterArguments,
				builder: builder,
				nodePath: nodePath,
				overrideReachable: overrideReachable,
				overrideRead: overrideRead,
				dependencyArguments: dependencyArguments,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				startsExtraction: startsExtraction,
				enclosingExtractor: enclosingExtractor,
				wasInsideSendableFunction: wasInsideSendableFunction,
				wasInsideActorArgument: wasInsideActorArgument,
				valuesBindingLines: valuesBindingLines,
				declarationIndex: declarationIndex,
				insertedAncestor: insertedAncestor,
				cycleNodeKey: cycleNodeKey,
				siblingLabels: siblingLabels,
				enclosingParentConcreteType: enclosingParentConcreteType,
				enclosingOverridePathReachable: enclosingOverridePathReachable,
				enclosingRenames: enclosingRenames,
				enclosingLazilyInstantiatedNames: enclosingLazilyInstantiatedNames,
				bindingNamesPassedByNameAround: bindingNamesPassedByNameAround,
				configurationEntry: configurationEntry,
				node: node,
			))
		}

		/// The part of `builtNode(of:…)` after the walk of the node’s children, `children`.
		@inline(never)
		private mutating func finishBuiltNode(_ descending: DescendingBuiltNode, children: [TreeNode], lines: inout [String]) -> ConstantNode {
			let generator = descending.generator
			let instantiable = descending.instantiable
			let property = descending.property
			let bindingName = descending.bindingName
			let indent = descending.indent
			let isWrapped = descending.isWrapped
			let initializer = descending.initializer
			let usesMockInitializer = descending.usesMockInitializer
			let ownLoopMembership = descending.ownLoopMembership
			let cycleParameterArguments = descending.cycleParameterArguments
			let builder = descending.builder
			let nodePath = descending.nodePath
			let overrideReachable = descending.overrideReachable
			let overrideRead = descending.overrideRead
			let dependencyArguments = descending.dependencyArguments
			let startsExtraction = descending.startsExtraction
			let enclosingExtractor = descending.enclosingExtractor
			let wasInsideSendableFunction = descending.wasInsideSendableFunction
			let valuesBindingLines = descending.valuesBindingLines
			let declarationIndex = descending.declarationIndex
			let insertedAncestor = descending.insertedAncestor
			let cycleNodeKey = descending.cycleNodeKey
			let siblingLabels = descending.siblingLabels
			let enclosingParentConcreteType = descending.enclosingParentConcreteType
			let enclosingOverridePathReachable = descending.enclosingOverridePathReachable
			let enclosingRenames = descending.enclosingRenames
			let enclosingLazilyInstantiatedNames = descending.enclosingLazilyInstantiatedNames
			let bindingNamesPassedByNameAround = descending.bindingNamesPassedByNameAround
			let configurationEntry = descending.configurationEntry
			var node = descending.node
			let finishedChildren = leavingConfiguredNode(configurationEntry)
			if overrideReachable {
				overridePathsByType[instantiable.concreteInstantiable.asSource]?.removeLast()
			}
			parentConcreteType = enclosingParentConcreteType
			overridePathReachable = enclosingOverridePathReachable
			renames = enclosingRenames
			lazilyInstantiatedNames = enclosingLazilyInstantiatedNames
			enclosingBindingNamesPassedByName = bindingNamesPassedByNameAround
			labels = siblingLabels
			ancestorDeclarationsByLabel[property.label]?.removeLast()
			bodyLabels.removeLast()
			bodyFunctionNames.removeLast()
			if insertedAncestor {
				ancestorTypes.remove(cycleNodeKey)
			}
			isInsideSendableFunction = wasInsideSendableFunction
			isInsideActorArgument = descending.wasInsideActorArgument
			// The construction is inside the function, so a function that starts the extraction reads its own override
			// into a local too, after its children's.
			// Also the defaults it reads from its configuration: an instantiator's before its override, a
			// constant's after it, in the order the emitter reads them (`generateInstantiatorBinding`, the constant branch of
			// `generateMockBodyBindings`).
			func readingDefaultsInsideFunction() -> [(label: String, value: String)] {
				constructionArguments(of: initializer, given: instantiable, usesMockInitializer: usesMockInitializer, dependencyArguments: dependencyArguments, nodePath: nodePath, overrideReachable: overrideReachable)
			}
			// Also an argument of its hand-written mock no dependency fulfills, which it reads as a default.
			let readsConfiguration = constructionReadsConfiguration(of: instantiable, usesMockInitializer: usesMockInitializer)
			if startsExtraction, isWrapped, readsConfiguration {
				node.arguments = readingDefaultsInsideFunction()
			}
			let functionOverrideRead = startsExtraction ? overrideRead.map { readingOverride($0, localNameSuffix: builder) } : overrideRead
			if startsExtraction, !isWrapped, readsConfiguration {
				node.arguments = readingDefaultsInsideFunction()
			}
			let preludeLines = startsExtraction ? endExtraction(restoring: enclosingExtractor, indent: indent) : []
			lines.insert(contentsOf: preludeLines, at: declarationIndex)
			let configuredNode = node.configured(byChildren: children)
			let oneWayParentConcreteType = parentConcreteType
			// A node whose type repeats a configured node around it, or beneath one, records nothing.
			if configuredNode.hasConfiguration, configurationEntry.recordsConfiguration {
				let parentConcreteType = instantiable.concreteInstantiable.asSource
				// A child beneath an edge in `cycleEdges` has no member in its parent's configuration, public or internal.
				let recordedChildren = children.filter { child in child.concreteType.map { !isPruned($0, beneath: parentConcreteType) } ?? true }
				// The members are in inline order, as `SafeDIOverrides`' are (`inlineOrdered(_:property:)`).
				var record = ConfigurationRecord(of: configuredNode, children: generator.inlineOrdered(recordedChildren, property: \.property))
				// What a configuration generated from the record imports.
				record.fulfillers = configurationFulfillers(of: configuredNode)
				// The construction the one-way check reads, with every child, pruned or not.
				record.oneWayConstruction = OneWayConstruction(
					of: configuredNode,
					construction: mockConstruction(of: configuredNode.instantiable, usesMockInitializer: configuredNode.usesMockInitializer),
					children: children,
					parentConcreteType: oneWayParentConcreteType,
					isBeneathCycleEdge: !overrideReachable,
					walkOrder: configurationEntry.walkOrder,
				)
				// A public mock's node records the construction its type's construction function makes.
				if buildsPublicMock {
					record.publicConstruction = MockLowering.publicConstructionRecord(of: configuredNode, children: recordedChildren, orderedBy: generator)
					record.publicConstruction?.fulfillers = record.fulfillers
				}
				configurationRecords.append(record)
				finishConfiguredNode(configuredNode, recordIndex: configurationRecords.count - 1)
			} else if buildsPublicMock, configuredNode.hasConfiguration {
				// Every node a public mock builds with a construction function declares it, beneath a
				// repeated configured ancestor too (`ScopeGenerator.collectPublicConstructionNodes`).
				var record = ConfigurationRecord(of: configuredNode, children: [])
				record.publicConstruction = MockLowering.publicConstructionRecord(of: configuredNode, children: [], orderedBy: generator)
				record.publicConstruction?.describesConfiguration = false
				// What its construction function imports.
				record.publicConstruction?.fulfillers = configurationFulfillers(of: configuredNode)
				configurationRecords.append(record)
				finishConfiguredNode(configuredNode, recordIndex: nil)
			} else if configuredNode.hasConfiguration, configurationEntry.recordsBeneathRepeatedAncestor {
				// A node beneath a repeated ancestor records what the module's choice reads.
				recordBeneathRepeatedAncestor(configuredNode, children: generator.inlineOrdered(children, property: \.property), finishedChildren: finishedChildren)
			} else if configuredNode.hasConfiguration {
				finishConfiguredNode(configuredNode, recordIndex: nil)
			}
			// A public mock's configured node calls its type's construction function.
			var endLines: [String] = if buildsPublicMock, configuredNode.hasConfiguration {
				configuredNode.publicBuilderFunctionEndLines(children: children, overrideRead: functionOverrideRead, indent: indent)
			} else {
				configuredNode.builderFunctionEndLines(overrideRead: functionOverrideRead, indent: indent)
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
				// A member's payloads are bound in its prelude, before every member's function.
				lastLoopMemberLineCounts = LoopMemberLineCounts(prelude: preludeLines.count + (isWrapped ? valuesBindingLines.count : 0), binding: bindingLines.count)
			}
			lines.append(contentsOf: endLines)
			return configuredNode
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
		// A node built with its type's hand-written mock.
		/// Whether the node is built with its type's hand-written mock rather than its initializer.
		let usesMockInitializer: Bool
		/// The properties the type forwards, by label.
		let forwardedProperties: [Property]
		/// The names the constructions of the node's subtree declare `@escaping`, which its builder function's parameters
		/// spell so.
		let typesDeclaredEscaping: Set<TypeDescription>
		// What the construction is handed, a lazy wrapper's instance included, and whether the node
		// is built in a `@Sendable` builder function of its own or inside one.
		/// The labels and values of the construction's arguments, in the initializer's order.
		// Read again inside a `@Sendable` builder function the node starts the extraction of.
		var arguments: [(label: String, value: String)]
		/// Whether the node's builder function is `@Sendable`.
		let buildsInSendableFunction: Bool
		/// Whether the node is built in or as a `@Sendable` builder function, so its override closure is `@Sendable`.
		let requiresSendable: Bool
		// The fields of the node's configuration for its construction's default-valued parameters.
		/// The fields of the node's configuration for its construction's default-valued parameters, in the order it takes them.
		let defaultFields: [DefaultField]
		/// Whether the node's children are configured in a configuration of its own, which holds its builder too.
		var hasConfiguration = false
		// The parameters a lazy cycle closing on the node's builder function needs, and what the
		// node's binding passes them (`MockLowering+CycleParameters.swift`).
		/// The parameters of the builder function a lazy cycle closing on it needs, after the forwarded properties.
		var cycleParameters = [Property]()
		/// The arguments the node's binding passes `cycleParameters`.
		var cycleParameterArguments = [String]()
		// A public mock binds a node it promotes from its caller's value, when passed one.
		/// The parameter of a public mock that holds the value its caller passed for the node, which the node's binding reads
		/// first (`ScopeGenerator.passing(_:orBuilding:)`).
		var promotedParameterName: String?
		// The `@Sendable` autoclosure parameters of the values the node's type instantiates that the
		// mock cannot build, each bound in its builder function from the local `mock()` reads it into.
		// Also the places it instantiates that a builder of `mock()` builds.
		/// The `@Sendable` autoclosure parameters and builders whose values the node's builder function binds.
		var sendableAutoclosureBindings = [ScopeGenerator.SendableAutoclosureParameter]()
		// A place of another module's public mock built inline.
		/// The builder `mock()` takes that the node reads where it is a place of another module's public mock the tree builds
		/// inline, with the read of its override outside its builder function.
		var inlinePlace: InlinePlace?

		/// The node, configured in a configuration of its own where `children` hold a node that builds its type or its
		/// construction takes a default-valued parameter.
		func configured(byChildren children: [TreeNode]) -> ConstantNode {
			var node = self
			node.hasConfiguration = children.contains(where: \.isPropertyNode) || !defaultFields.isEmpty
			return node
		}

		/// The member of the enclosing overrides that configures the node: its configuration, or an optional builder closure.
		var overridesField: OverridesField {
			// A node built in or as a `@Sendable` builder function takes a `@Sendable` override, which
			// is `Sendable`, as is a configuration `@Sendable`-typed.
			hasConfiguration
				? OverridesField(name: bindingName, typeSource: configurationTypeName, defaultValue: ".init()", sendability: .whenConfigurationIsTypedSendable(instantiable.concreteInstantiable.asSource))
				: OverridesField(name: bindingName, typeSource: "(\(requiresSendable ? "@Sendable " : "")\(builderClosureType))?", defaultValue: "nil", sendability: requiresSendable ? .always : .never)
		}

		/// The type of the closure that overrides how the node is built, handed the values its initializer takes.
		var builderClosureType: String {
			"(\(builderParameterTypes)) -> \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)"
		}

		/// The types of the values the node's override is handed, joined: one per argument its construction is passed, which
		/// leaves out a parameter left to its default (`ScopeGenerator.MockConstruction.callSiteArguments`).
		private var builderParameterTypes: String {
			MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: usesMockInitializer).spelled
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

		// The name the node's level renames its builder function to, apart from an enclosing function
		// a cycle-closing node beneath refers to.
		/// The name of the node's builder function where its level renames it, else `nil`.
		var renamedFunctionName: String?

		/// The name of the node's builder function.
		var functionName: String {
			renamedFunctionName ?? MockLowering.builderFunctionName(boundAs: bindingName)
		}

		/// The statement that binds a constant node with no children, whose override `overrideRead` reads.
		func constantBindingLine(overrideRead nodePath: String?, indent: String) -> String {
			// Only the `if` expression that reads an override needs the property's type, which its two branches share.
			// A child the mock promotes for an optional receive, such as a value a called public mock
			// builds when passed `nil`, is bound as the value it builds.
			let annotation = isFulfilledByAnotherType && !isErased && nodePath != nil ? ": \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource)" : ""
			return "\(indent)let \(bindingName)\(annotation) = \(passingPromotedValue(orBuilding: readingInlinePlaceBuilder(constructionReading(override: nodePath, builderCall: "\(ReservedName.configurationBuilderPropertyName)(\(builderArguments))"), override: nodePath)))"
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

		/// `construction`, a constant's, read after the builder `mock()` takes where the node is a place of another module's
		/// public mock built inline and no override at `overridePath` is set (`HoleBuilder.inlinePlaceValue`). A wrapper reads
		/// the builder where it is made (`promotedBindingLines`).
		private func readingInlinePlaceBuilder(_ construction: String, override overridePath: String?) -> String {
			guard let inlinePlace, !isWrapped else { return construction }
			return inlinePlace.builder.inlinePlaceValue(construction: construction, overrideExpression: overridePath)
		}

		/// The first line of the node's builder function, whose children's statements follow it.
		func builderFunctionDeclarationLine(indent: String) -> String {
			let builtType = property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource
			let parameters = forwardedProperties.map { "\($0.label): \($0.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let decorator = ScopeGenerator.localFunctionPrefix(isSendable: buildsInSendableFunction)
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
				// Then the value of each `@Sendable` autoclosure parameter it instantiates.
				+ sendableAutoclosureBindings.map { "\(bodyIndent)\($0.binding)" }
		}

		/// The lines that end the node's builder function, after its children's statements, and bind the node, whose
		/// overrides are at `nodePath`.
		func builderFunctionEndLines(overrideRead overridePath: String?, indent: String) -> [String] {
			let builder = ReservedName.configurationBuilderPropertyName
			let bodyIndent = "\(indent)\(ScopeGenerator.standardIndent)"
			// A constant's builder function always returns its construction (`BuilderBody`).
			let returnPrefix = hasChildren || !receiverBindings.isEmpty || !sendableAutoclosureBindings.isEmpty || !isWrapped ? "return " : ""
			// A configuration's builder returns the concrete type, which an erased node wraps as its construction does.
			let builderCall = isErased && hasConfiguration ? "\(erasedTypeSource)(\(builder)(\(builderArguments)))" : "\(builder)(\(builderArguments))"
			var lines = ["\(bodyIndent)\(returnPrefix)\(readingInlinePlaceBuilder(constructionReading(override: overridePath, builderCall: builderCall), override: overridePath))"]
			lines.append("\(indent)}")
			lines.append(contentsOf: promotedBindingLines(indent: indent))
			return lines
		}

		/// The statements that bind the node from its builder function, after the value the public mock's caller passed for it
		/// where it promotes the node.
		func promotedBindingLines(indent: String) -> [String] {
			guard let promotedParameterName else {
				if let inlinePlace, isWrapped {
					return inlinePlace.wrapperBindingLines(of: property.typeDescription, named: bindingName, handing: functionName, forwardedProperties: forwardedProperties, cycleParameterArguments: cycleParameterArguments, indent: indent)
				}
				return MockLowering.bindingLines(of: property, boundAs: bindingName, callingFunctionNamed: functionName, forwardedProperties: forwardedProperties, cycleParameterArguments: cycleParameterArguments, indent: indent)
			}
			guard property.propertyType.isConstant else {
				return [MockLowering.promotedWrapperBindingLine(of: property.typeDescription, named: bindingName, passing: promotedParameterName, handing: functionName, forwardedProperties: forwardedProperties, cycleParameterArguments: cycleParameterArguments, indent: indent)]
			}
			return ["\(indent)let \(bindingName): \(property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource) = \(ScopeGenerator.passing(promotedParameterName, orBuilding: "\(functionName)(\(cycleParameterArguments.joined(separator: ", ")))"))"]
		}
	}

	/// `lines` joined by newlines, in storage sized once for all of them: a mock's code can run to megabytes, which
	/// `joined(separator:)` grows into by copying.
	static func joinedLines(_ lines: [String]) -> String {
		var code = ""
		code.reserveCapacity(lines.reduce(lines.count) { $0 + $1.utf8.count })
		for (index, line) in lines.enumerated() {
			if index > 0 {
				code.append("\n")
			}
			code.append(line)
		}
		return code
	}

	/// A node of a mock's tree: one that builds its type, an alias of a value bound before it, or a call of another module's
	/// public mock. Indirect, so that the walk's many copies of a node, in its parent's children and in the records, share
	/// one box rather than copying every field of a `ConstantNode`.
	indirect enum TreeNode {
		case built(ConstantNode)
		case alias(AliasBinding)
		// A call of another module's public mock (`MockLowering+PublicMocks.swift`).
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

		/// Whether the node builds a property, which gives its parent a configuration of its own,
		/// whether or not that configuration has a field for it.
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
			// A node that closes a cycle is configured by the configuration of the type it repeats.
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

	/// The key a node of `property`, built as `instantiable`, repeats a node around it by: the property and the concrete
	/// type, so a node reads no override of its own where both repeat an ancestor's.
	static func cycleNodeKey(of property: Property, builtAs instantiable: Instantiable) -> String {
		"\(property.typeDescription.asInstantiatedType.asSource) fulfilled by \(instantiable.concreteInstantiable.asSource)"
	}

	/// The statements that bind `property` from the builder function `functionName`, which takes `forwardedProperties`: a
	/// constant called, or an instantiator handed the function.
	static func bindingLines(of property: Property, boundAs bindingName: String, callingFunctionNamed functionName: String, forwardedProperties: [Property], cycleParameterArguments: [String] = [], indent: String) -> [String] {
		// The binding of each wrapper kind (`MockLowering+Wrappers.swift`).
		if property.propertyType.isConstant {
			// A promoted child is bound as the value it builds, as `constantBindingLine` binds it.
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
	// A dependency among `instancesReadByValue` is passed its wrapper's instance.
	static func rootArgumentList(of initializer: Initializer, given dependencies: [Dependency], renames: [String: [TypeDescription: String]], passingNilTo unavailableProperties: Set<Property>, readingInstancesOf instancesReadByValue: Set<Property> = []) -> String {
		var parts = [String]()
		for argument in initializer.arguments {
			// An argument takes the dependency of its label, whatever its type.
			if let dependency = MockLowering.dependency(passedTo: argument, among: dependencies) {
				// A receive only if available nothing above provides is passed `nil`, as production passes it.
				guard dependency.source != .received(onlyIfAvailable: true) || !unavailableProperties.contains(dependency.property) else {
					parts.append("\(argument.label.spelledAsArgumentLabel): nil")
					continue
				}
				guard !instancesReadByValue.contains(dependency.property) else {
					// Through the wrapper's name where the root's level names it apart, as
					// `generateReturnArgumentList` reads `disambiguatedLazilyInstantiatedBinding`.
					let wrapperName = renames[argument.innerLabel].flatMap { wrapperRename(ofInstanceOfType: dependency.property.typeDescription.unwrapped, among: $0) } ?? argument.innerLabel
					parts.append("\(argument.label.spelledAsArgumentLabel): \(wrapperName).\(Dependency.lazilyInstantiatedInstancePropertyName)")
					continue
				}
				parts.append("\(argument.label.spelledAsArgumentLabel): \(renames[argument.innerLabel]?[dependency.property.typeDescription] ?? argument.innerLabel)")
			} else if argument.hasDefaultValue, !argument.isLeftToItsDefault {
				// An `@autoclosure` parameter of `mock()` is passed its call.
				let parameterValue = argument.typeDescription.strippingEscaping.autoclosureValueType == nil ? argument.label : "\(argument.label)()"
				parts.append("\(argument.label.spelledAsArgumentLabel): \(parameterValue)")
			}
		}
		return parts.joined(separator: ", ")
	}

	/// Whether a receive among `generators`, or beneath them up to a node that declares `label`, reads `label` by name: a
	/// receive or an alias's fulfilling property whose form `renames` does not name apart
	/// (`ScopeGenerator.receiveReadsLabelByName`).
	static func receiveReadsLabelByName(_ label: String, beneath children: [ScopeGenerator.OrderedChild], renames: [String: [TypeDescription: String]], lazilyInstantiatedNames: [String: [TypeDescription: String]], publicMockNodeBindingNames: Set<String>?) -> Bool {
		let names = renames[label] ?? [:]
		// A receive of a wrapper the mock names apart reads that name, not the label.
		let wrapperNames = lazilyInstantiatedNames[label] ?? [:]
		// A wrapper's instance is read through a wrapper the flat parameters name apart. A public mock's wrapper parameter is
		// none: the emitter names apart the instance it stands for (`publicMockWrapperParameters`), and
		// `dependencyArgument` reads the wrapper by name. A wrapper node the root's level names apart is one, read through its
		// name.
		let flatWrapperNames = publicMockNodeBindingNames.map { nodeBindingNames in names.filter { nodeBindingNames.contains($0.value) } } ?? names
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var childrenToVisit = children
		while let child = childrenToVisit.popLast() {
			let generator = child.generator
			switch generator.scopeData {
			case let .alias(_, fulfillingProperty, _, onlyIfAvailable, _):
				// An alias bound to `nil` reads nothing (`emitAliasBinding`).
				guard fulfillingProperty.label == label, !ScopeGenerator.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: child.unavailableProperties), wrapperNames[fulfillingProperty.typeDescription] == nil else { continue }
				// An alias of a lazy wrapper's instance reads the wrapper's binding named apart, if
				// any, as `emitAliasBinding` resolves it, by whether the property it renames is in scope only as an instance.
				if generator.mockLoweringFulfillingPropertyIsLazilyInstantiatedInstance {
					guard wrapperRename(ofInstanceOfType: fulfillingProperty.typeDescription.unwrapped, among: flatWrapperNames) != nil else { return true }
				} else {
					guard names[fulfillingProperty.typeDescription] != nil else { return true }
				}
			case let .property(instantiable, _, _, _, isPropertyCycle, _):
				for dependency in instantiable.dependencies where dependency.source.isReceived && dependency.property.label == label && !generator.unavailableOptionalProperties.contains(dependency.property) && wrapperNames[dependency.property.typeDescription] == nil {
					// A receive of a lazy wrapper's instance reads the wrapper's binding named apart, if
					// any, as `dependencyArgument` resolves it.
					if generator.mockLoweringLazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
						guard wrapperRename(ofInstanceOfType: dependency.property.typeDescription.unwrapped, among: flatWrapperNames) != nil else { return true }
					} else {
						guard names[dependency.property.typeDescription] != nil || names[dependency.property.asUnwrappedProperty.typeDescription] != nil else { return true }
					}
				}
				// The builder function of a node that instantiates, forwards or renames the label declares it, and what is
				// beneath reads that.
				if !isPropertyCycle, !instantiable.dependencies.contains(where: { !$0.source.isReceived && $0.property.label == label }) {
					childrenToVisit.append(contentsOf: generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: generator.mockLoweringBodyPropertiesGeneratedLater(child.propertiesGeneratedLater)))
				}
			// A site of a public mock's hole reads its builder by the builder's internal name, never by its label, and its
			// fields by their labels, which the rebinding of a receive named apart provides (`placeOrFillNode`).
			// A fill of a call of another module's public mock is generated with production emission,
			// which the emitter's walk of the mock tree does not enter.
			case .fill, .root, .hole:
				continue
			}
		}
		return false
	}

	/// The name `names` gives the `LazilyInstantiated` or `SendableLazilyInstantiated` of `instanceType`, as
	/// `ScopeGenerator.disambiguatedLazilyInstantiatedBinding` finds it.
	private static func wrapperRename(ofInstanceOfType instanceType: TypeDescription, among names: [TypeDescription: String]) -> String? {
		[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
			.lazy
			.compactMap { names[TypeDescription.simple(name: $0, generics: [instanceType])] }
			.first
	}

	/// The local `mock()` reads its `@Sendable` autoclosure parameter named `name` into, before any builder function.
	static func sendableAutoclosureLocalName(of name: String) -> String {
		"\(ReservedName.builderFunctionNamePrefix)\(name)".spelledAsJoinedIdentifier
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
}

extension MockLowering.ConfigurationRecord {
	/// The configuration `node`, which `children` build beneath, is configured by.
	// Each child's field as the core's `SafeDIOverrides` spells it.
	init(of node: MockLowering.ConstantNode, children: [MockLowering.TreeNode]) {
		self.init(
			concreteType: node.instantiable.concreteInstantiable,
			usesMockInitializer: node.usesMockInitializer,
			// A child's field is the one the overrides hold for a node at the root: its override, its configuration, or the
			// overrides of the public mock it calls.
			// A built child's field is spelled where a configuration is generated from the record.
			// A configuration `@Sendable`-typed takes each child's override `@Sendable` (`ScopeGenerator.configurationField`).
			childFieldSources: children.compactMap { child in
				switch child {
				case let .built(childNode):
					return .built(bindingName: childNode.bindingName, hasConfiguration: childNode.hasConfiguration, requiresSendable: childNode.requiresSendable, concreteType: childNode.instantiable.concreteInstantiable, builderParameters: MockLowering.BuilderParameters(of: childNode.instantiable, usesMockInitializer: childNode.usesMockInitializer), propertyType: childNode.property.typeDescription)
				case .alias:
					return nil
				// A node that closes a cycle is configured by the configuration of the type it repeats.
				case let .cycleClosing(_, bindingName, concreteType):
					let field = MockLowering.cycleClosingOverridesField(boundAs: bindingName, concreteType: concreteType)
					return .spelled(ChildField(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: .init(typeSource: field.typeSource, defaultValue: field.defaultValue, configuredTypeName: concreteType.asSource)))
				// A call's member in a configuration `@Sendable`-typed is a `@Sendable` closure
				// (`publicMockOverridesMember(sendable:)`).
				case let .publicMockCall(call):
					return call.overridesField.map { field in
						.spelled(ChildField(name: field.name, typeSource: field.typeSource, defaultValue: field.defaultValue, sendableForm: call.sendableConfigurationFieldForm))
					}
				}
			},
			builderParameters: MockLowering.BuilderParameters(of: node.instantiable, usesMockInitializer: node.usesMockInitializer),
			defaultFields: node.defaultFields,
		)
	}
}

extension MockLowering {
	/// The parameters of a node's construction that the closure overriding how the node is built is handed: every argument
	/// of its construction initializer but one left to its default that no dependency names. It holds the two arrays it
	/// reads rather than the node's `Instantiable`, so a configuration record copies two references, not a declaration.
	struct BuilderParameters: Sendable, Equatable {
		init(of instantiable: Instantiable, usesMockInitializer: Bool) {
			arguments = (usesMockInitializer ? instantiable.mockInitializer : instantiable.initializer)?.arguments ?? []
			dependencies = instantiable.dependencies
			sendsArguments = instantiable.declarationType == .actorType && !usesMockInitializer
		}

		/// The parameters' types, spelled as the closure's parameter list.
		var spelled: String {
			let dependencyLabels = Set(dependencies.map(\.property.label))
			return arguments.filter { !$0.isLeftToItsDefault || dependencyLabels.contains($0.innerLabel) }.map { argument in
				let parameter = (argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription)
					.asFunctionParameter(amongTypesDeclaredEscaping: [])
					.asSource
				return sendsArguments ? "sending \(parameter)" : parameter
			}.joined(separator: ", ")
		}

		private let arguments: [Initializer.Argument]
		private let dependencies: [Dependency]
		/// Whether the closure hands each value to an actor's initializer, which takes it into the actor's isolation: Swift 6
		/// lets a closure send only a parameter declared `sending`, so an override written as `{ worker in Store(worker: worker) }`
		/// compiles only so. Each value the mock hands it is a local nothing else holds.
		private let sendsArguments: Bool
	}
}

extension MockLowering {
	/// `bindingNamesPassedByName` with the name of each wrapper in `lazilyInstantiatedNames` a received dependency among
	/// `dependencies` reads, which the node is passed by name (`ScopeGenerator.dependencyArgument`).
	static func passingWrappersByName(_ lazilyInstantiatedNames: [String: [TypeDescription: String]], to dependencies: [Dependency], besides bindingNamesPassedByName: [String: String]) -> [String: String] {
		guard !lazilyInstantiatedNames.isEmpty else { return bindingNamesPassedByName }
		var bindingNamesPassedByName = bindingNamesPassedByName
		for dependency in dependencies where dependency.source.isReceived {
			guard let name = lazilyInstantiatedNames[dependency.property.label]?[dependency.property.typeDescription] else { continue }
			bindingNamesPassedByName[dependency.property.label] = name
		}
		return bindingNamesPassedByName
	}
}
