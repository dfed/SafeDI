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

/// What the mock root's level binds, decided from `mock()`'s signature and the root's level of nodes alone, which the
/// walk reads off its generator tree and a mock root's world off its declarations, so both decide it by one rule.
extension MockLowering {
	/// The names the mock root's level binds apart and whether `mock()` binds nothing before its nodes that node records
	/// do not read.
	struct RootLevelBindings: Equatable {
		/// The name the root's level gives each node it names apart, by the node's label and then its property's type,
		/// beside the flat parameters and overrides of `mock()` named apart (`Walk.rootRenames`, which node records read as
		/// `MockRootNames.namesApart`).
		let namesApart: [String: [TypeDescription: String]]
		/// The names the property nodes of the root's level are bound under (`Walk.rootPropertyNodeBindingNames`).
		let propertyNodeBindingNames: Set<String>
		/// Whether `mock()` binds nothing but its nodes, so that its nodes can be laid out from the node records of its
		/// world (`ScopeGenerator.nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:sendableConfigurationTypeNames:rootNames:outerDeclarations:)`):
		/// before them only the builders its calls pass up, the places of a seam's own mock and the overrides of what its
		/// tree receives only if available, and every name the mocked type is passed apart from its label one the records
		/// bind too.
		let bindsOnlyNodes: Bool
	}

	/// What the mock root's level of `instantiable`'s mock binds (`RootLevelBindings`).
	/// - Parameters:
	///   - signature: `mock()`'s signature (`ScopeGenerator.lowerRootSignature(of:context:)`).
	///   - rootLevelNodes: The nodes of the root's level, in the order the mock's body builds them.
	///   - callsBindNothing: Whether the calls of other modules' public mocks in the tree make `mock()` bind no builder
	///     apart and no builder for a place they build inline (`FilledCallBuilders`); a root that makes no call binds none.
	static func rootLevelBindings(of instantiable: Instantiable, signature: RootSignature, rootLevelNodes: [LevelNode], callsBindNothing: Bool) -> RootLevelBindings {
		let mockedTypeUncoveredProperties = instantiable.dependencies.compactMap { dependency -> Property? in
			guard case .instantiated = dependency.source, signature.uncoveredProperties.contains(dependency.property) else { return nil }
			return dependency.property
		}
		// The renames the root's level starts from, as the walk seeds them: the flat parameters and overrides named apart,
		// less those the mocked type's own uncovered dependencies hide, which route to their parameters instead.
		var namesApart = removingRenames(hiddenBy: mockedTypeUncoveredProperties, from: signature.renamesByLabelAndType)
		routeReceives(of: mockedTypeUncoveredProperties, toParametersNamed: signature.uncoveredParameterNamesByLabelAndType, in: &namesApart)
		let bindingNames = rootLevelBindingNames(
			of: rootLevelNodes,
			besideNamesTaken: RootLevelNamesTaken(
				parametersKeepingTheirLabels: (signature.forwardedParameters + signature.rootDefaultParameters).map(\.property),
				flatReceivedLabels: Set(signature.flatReceivedParameters.map(\.property.label)),
				overrideNames: Set(signature.onlyIfAvailableOverrides.map(\.name)),
				rootLabels: signature.labels.union(signature.lazilyInstantiatedBindings.map(\.name)),
				namesDeclaredInBuilderFunctions: signature.namesDeclaredInBuilderFunctions,
			),
		)
		var propertyNodeBindingNames = Set<String>()
		// The names apart the aliases of the root's level are bound under, which their records bind too.
		var aliasBindingNamesApart = Set<String>()
		var nodeProperties = Set<Property>()
		for node in rootLevelNodes {
			switch node {
			case let .property(property, _), let .alias(property):
				nodeProperties.insert(property)
			case .other:
				continue
			}
		}
		for (node, bindingName) in zip(rootLevelNodes, bindingNames) {
			guard let bindingName else { continue }
			switch node {
			case let .property(property, _):
				propertyNodeBindingNames.insert(bindingName)
				if bindingName != property.label {
					namesApart[property.label, default: [:]][property.typeDescription] = bindingName
				}
			case let .alias(property):
				if bindingName != property.label {
					namesApart[property.label, default: [:]][property.typeDescription] = bindingName
					aliasBindingNamesApart.insert(bindingName)
				}
			case .other:
				continue
			}
		}

		// The names the mocked type is passed apart from its labels: the level's, each wrapper `mock()` makes of an instance
		// it takes, and each optional form of a node named apart; its own receives `mock()` binds again under their labels
		// are passed those labels.
		var rootRenames = namesApart
		for (label, names) in signature.lazilyInstantiatedBindingNamesByLabelAndType {
			rootRenames[label, default: [:]].merge(names) { _, wrapperName in wrapperName }
		}
		let rootLevelBindingNames = propertyNodeBindingNames.union(signature.onlyIfAvailableOverrides.map(\.name))
		for dependency in instantiable.dependencies where dependency.source.isReceived {
			guard let names = signature.renamesByLabelAndType[dependency.property.label],
			      (names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription]) != nil,
			      !rootLevelBindingNames.contains(dependency.property.label)
			else { continue }
			rootRenames[dependency.property.label]?[dependency.property.typeDescription] = nil
		}
		let rootOptionalForms = rootOptionalFormsProvidedByNodes(of: instantiable, nodeProperties: nodeProperties.union(signature.properties), renames: rootRenames)
		for (label, names) in rootOptionalFormRenames(of: rootOptionalForms, renames: rootRenames) {
			rootRenames[label, default: [:]].merge(names) { renamed, _ in renamed }
		}

		// What `mock()` binds before its nodes beyond the builders its calls pass up, which both counts hold: the mocked type's
		// receives of such a builder bound again under their labels, each `@Sendable` autoclosure read into a local, each
		// value of one the mocked type instantiates, and each override of an internal mock that its tree receives only if
		// available, against what node records bind there: the places of a seam's own mock and those overrides.
		let passedUpBuilderNames = signature.passedUpBuilderNames
		var bindingsBeforeTree = signature.uncoveredRootParameters.count { $0.isSendableAutoclosure }
		for dependency in instantiable.dependencies where dependency.source.isReceived {
			guard let name = passedUpBuilderNames[dependency.property], name != dependency.property.label else { continue }
			bindingsBeforeTree += 1
		}
		let sendableAutoclosureBindings = signature.sendableAutoclosureBindings
		bindingsBeforeTree += mockedTypeUncoveredProperties.count { sendableAutoclosureBindings[$0] != nil }
		let overridesBoundBeforeNodes = signature.onlyIfAvailableOverrides.count { signature.unavailableDependencyOverrideNames[$0.receivedProperty] == nil }
		if instantiable.generateMock != .public {
			bindingsBeforeTree += overridesBoundBeforeNodes
		}
		let rootPlaceCount = mockedTypeUncoveredProperties.count { property in signature.passedUpBuilders.contains { $0.places.contains { $0.property == property } } }

		let bindsOnlyNodes = bindingsBeforeTree == rootPlaceCount + overridesBoundBeforeNodes
			&& !signature.uncoveredRootParameters.contains(where: \.isSendableAutoclosure)
			&& callsBindNothing
			&& signature.passedUpBuilders.allSatisfy(\.adapters.isEmpty)
			// A node or an alias the root's level names apart is bound under that name by its record, and a parameter or
			// override under the name `mock()` gives it, an uncovered dependency's included; any other name is neither's.
			&& rootRenames.allSatisfy { label, names in
				names.allSatisfy { type, name in
					propertyNodeBindingNames.contains(name)
						|| aliasBindingNamesApart.contains(name)
						|| signature.renamesByLabelAndType[label]?[type] == name
						|| signature.uncoveredParameterNamesByLabelAndType[label]?[type] == name
						|| signature.lazilyInstantiatedBindingNamesByLabelAndType[label]?[type] == name
				}
			}
		return RootLevelBindings(namesApart: namesApart, propertyNodeBindingNames: propertyNodeBindingNames, bindsOnlyNodes: bindsOnlyNodes)
	}
}

extension MockLowering {
	/// The nodes of the mock root's level in the world whose root is `worldRoot`, in the order the mock's body builds them,
	/// as the walk reads them off the root's generator's children (`ScopeGenerator.mockLevelNode`): each of the root's
	/// declarations by its edge's build position, a property listed again after a sibling left out, as the generator
	/// builds only the first (`orderedPropertiesToGenerate`). A fill is no child of the root's level, and a hole's site
	/// binds no property node.
	static func rootLevelNodes(ofWorldRootedAt worldRoot: ConstructionScope) -> [LevelNode] {
		rootLevelNodes(ofWorld: TypeFactsGraph(root: worldRoot, forMockGeneration: true))
	}

	/// The same, read from `world`, the mock root's world, which a root left unbuilt builds once (`UnbuiltMockRoot`).
	static func rootLevelNodes(ofWorld world: TypeFactsGraph) -> [LevelNode] {
		var listed = Set<Property>()
		var nodes = [LevelNode]()
		for edge in world.edgeFacts(from: 0).sorted(by: { $0.buildPosition < $1.buildPosition }) where !edge.isFill {
			guard let property = world.property(of: edge.child), listed.insert(property).inserted else { continue }
			switch world.kind(of: edge.child) {
			case .alias:
				nodes.append(.alias(property))
			case .hole:
				nodes.append(.other)
			case .constant, .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .lazy, .sendableLazy:
				nodes.append(.property(property, isUnavailableDependency: world.scope(of: edge.child).isUnavailableDependency))
			}
		}
		return nodes
	}
}
