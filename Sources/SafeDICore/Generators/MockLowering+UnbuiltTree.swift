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

/// A mock root `generateMockCode` builds no generator tree for: an internal mock that calls no other module's public mock,
/// whose world answers its tree's names (`MockTreeNamesFromWorld`), and that no check of its tree needs
/// (`MockRootTreeChecks`), laid out from node records where a test turns them on
/// (`NodeRecordsObservation.laysOutMockRoots`). Everything its lowering reads comes from its world and the signature the
/// world's names lower (`ScopeGenerator.lowerUnbuiltMockRoot(_:of:context:)`). Where its records refuse it, its tree is
/// built after all, from its promotion (`DependencyTreeGenerator.PromotedMockRoot`), and lowered as every other root's.
/// It holds the root's world, whose frozen table shares its storage with the other mock roots' tables, until the root is
/// lowered.
struct UnbuiltMockRoot: Sendable {
	/// The root of the mock root's world, with the receives only if available its promotion passes `nil`.
	let worldRoot: MockWorldRoot
	/// The mock root's world, built once for its names, its signature and its node records.
	let world: TypeFactsGraph
	/// The names of the root's tree and the inputs of its parameters, both read from its world.
	let treeNames: ScopeGenerator.TreeNames
	let inputs: MockRootParameterInputs
	/// The parameters of `mock()` other than its overrides, lowered from the world's names and inputs.
	let signature: MockLowering.RootSignature
	/// The nodes of the root's level, in build order, read off the world.
	let rootLevelNodes: [MockLowering.LevelNode]

	/// Why a mock root keeps its generator tree, for the observation that counts the roots left unbuilt.
	enum Refusal: String, Sendable {
		/// A public mock, or a call of another module's public mock in the module: the tree decides what its calls read.
		case publicMockOrCall
		/// A check of the tree the root's scopes say can find something there (`MockRootTreeChecks.needingTree`).
		case treeCheck
		/// The world does not answer the tree's names, or its signature (`MockTreeNamesFromWorld`).
		case treeNames
		/// An erased instantiator, whose built type's forwarded properties the tree's build checks.
		case erasedInstantiator
		/// The mocked type receives a value only if available, which the root passes `nil` where nothing binds it: owed by the
		/// root's facts (the fold lane's `TypeFactsMockRootRecord`).
		case onlyIfAvailableReceive
		/// A lazy wrapper at the root's level, whose instance the mocked type may be passed: owed by the root's facts (the fold
		/// lane's `TypeFactsMockRootRecord`).
		case lazyWrapperAtRoot
		/// A member of a loop of builders at the root's level that the mocked type's construction does not read, which the
		/// level binds no wrapper of: owed by the root's facts (the fold lane's `TypeFactsMockRootRecord`).
		case loopMemberReadOnlyInsideItsLoop
	}

	/// Whether a mock root is left unbuilt (`leavingTreeUnbuilt(_:worldFindsSendableCapture:flatParameterMockDefaults:)`).
	enum Outcome {
		case leftUnbuilt(UnbuiltMockRoot)
		case keepsTree(Refusal)
	}

	/// The mock root `promoted` holds, left unbuilt, or why it keeps its tree. `worldFindsSendableCapture` is the world's
	/// answer to the tree's capture check (`DependencyTreeGenerator.worldFindsSendableCapture(of:boundProperties:instancesReadThroughWrapperParameters:)`).
	static func leavingTreeUnbuilt(_ promoted: DependencyTreeGenerator.PromotedMockRoot, worldFindsSendableCapture: Bool?, flatParameterMockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault]) -> Outcome {
		let instantiable = promoted.instantiable
		guard instantiable.generateMock != .public, promoted.surfacedByPublicMockCalls.isEmpty else { return .keepsTree(.publicMockOrCall) }
		let treeChecks = worldFindsSendableCapture.map { promoted.scopeTreeChecks.answeringSendableCaptures(fromWorld: $0) } ?? promoted.scopeTreeChecks
		guard treeChecks.needingTree.isEmpty else { return .keepsTree(.treeCheck) }
		let worldRoot = promoted.worldRoot
		var declarationVisits = 0
		let passesNilToPinnedReceives = !promoted.receivesPassedNil.pinnedWhereverBuilt.isEmpty || !promoted.receivesPassedNil.labelsPinnedFromAbove.isEmpty
		let world = TypeFactsGraph(root: worldRoot, forMockGeneration: true)
		guard case let .names(names) = MockTreeNamesFromWorld.treeNames(of: instantiable, world: world, passesNilToPinnedReceives: passesNilToPinnedReceives, declarationVisits: &declarationVisits),
		      let rootInputs = MockTreeNamesFromWorld.rootInputs(ofWorld: world, spelledAs: promoted.allReceived)
		else { return .keepsTree(.treeNames) }
		// The tree's build checks the forwarded properties of the type each erased instantiator builds, which no fact holds.
		let holdsErasedInstantiator = (0..<Int32(world.declarationCount)).contains { declaration in
			switch world.kind(of: declaration) {
			case .erasedInstantiator, .sendableErasedInstantiator: true
			case .constant, .alias, .hole, .instantiator, .sendableInstantiator, .lazy, .sendableLazy: false
			}
		}
		guard !holdsErasedInstantiator else { return .keepsTree(.erasedInstantiator) }
		guard !instantiable.dependencies.contains(where: { dependency in
			switch dependency.source {
			case let .received(onlyIfAvailable), let .aliased(_, _, onlyIfAvailable): onlyIfAvailable
			case .instantiated, .forwarded: false
			}
		}) else { return .keepsTree(.onlyIfAvailableReceive) }
		let rootEdges = world.edgeFacts(from: 0)
		guard !rootEdges.contains(where: { world.property(of: $0.child)?.propertyType.isLazilyInstantiated ?? false }) else { return .keepsTree(.lazyWrapperAtRoot) }
		// The construction reads each dependency it receives or instantiates, in either form (`loopMembersReadOnlyInsideTheirLoop()`).
		let constructionReadProperties = Set(instantiable.dependencies.compactMap { dependency -> Property? in
			switch dependency.source {
			case .received, .instantiated: dependency.property.asUnwrappedProperty
			case .aliased, .forwarded: nil
			}
		})
		guard !rootEdges.contains(where: { edge in
			edge.loop >= 0 && !(world.property(of: edge.child).map { constructionReadProperties.contains($0.asUnwrappedProperty) } ?? false)
		}) else { return .keepsTree(.loopMemberReadOnlyInsideItsLoop) }
		return .leftUnbuilt(UnbuiltMockRoot(
			worldRoot: MockWorldRoot(scope: worldRoot, receivesPassedNil: promoted.receivesPassedNil),
			world: world,
			treeNames: names,
			inputs: rootInputs.inputs,
			signature: ScopeGenerator.lowerRootSignature(of: instantiable, flatParameterMockDefaults: flatParameterMockDefaults, tree: names, inputs: rootInputs.inputs),
			rootLevelNodes: MockLowering.rootLevelNodes(ofWorld: world),
		))
	}
}

extension UnbuiltMockRoot {
	/// The imports the mock of `instantiable` takes outside its tree (`ScopeGenerator.fulfillersOfMockOutsideTree(mockDefaults:)`),
	/// its parameters classified from its world's names.
	func fulfillersOfMockOutsideTree(of instantiable: Instantiable, mockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault]) -> Set<FulfillerImports.Fulfiller> {
		ScopeGenerator.fulfillersOfMockOutsideTree(of: instantiable, mockDefaults: mockDefaults) { mockDefaults in
			ScopeGenerator.mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults, treeNames: treeNames.names, inputs: inputs)
		}
	}
}

extension MockLowering {
	/// What the mocked type's construction is passed by a name other than its label, and the lines that bind its own
	/// receives again under their labels before the nodes, which the walk of its tree
	/// (`ScopeGenerator.lowerMockRootWithTree(of:context:worldRoot:)`) and a root left unbuilt both write.
	struct RootArguments {
		/// The names the construction reads: the level's names apart, the wrappers `mock()` binds, and the optional forms of
		/// the level's nodes.
		var renames: [String: [TypeDescription: String]]
		/// The mocked type's own receives `mock()` binds again under their labels.
		var receivesBoundAgain = [Property]()
		/// The lines that bind them, in the order of `receivesBoundAgain`.
		var bindingLines = [String]()
	}

	/// The arguments of `instantiable`'s construction at a mock root whose level names `namesApart` apart, binds
	/// `propertyNodeBindingNames` and builds or renames `nodeProperties`.
	static func rootArguments(of instantiable: Instantiable, signature: RootSignature, namesApart: [String: [TypeDescription: String]], propertyNodeBindingNames: Set<String>, nodeProperties: Set<Property>, bodyIndent: String) -> RootArguments {
		// The mocked type's own receive of a flat received parameter or override named apart is bound
		// again under its label before the tree, unless the root's level binds that label (`generateMockRootCode`'s
		// `rootDependenciesToRebind`), when the mocked type is passed the name.
		let rootLevelBindingNames = propertyNodeBindingNames.union(signature.onlyIfAvailableOverrides.map(\.name))
		var arguments = RootArguments(renames: namesApart)
		// The mocked type's own receive of a wrapper `mock()` binds is passed its binding by name.
		for (label, names) in signature.lazilyInstantiatedBindingNamesByLabelAndType {
			arguments.renames[label, default: [:]].merge(names) { _, wrapperName in wrapperName }
		}
		for dependency in instantiable.dependencies where dependency.source.isReceived {
			guard let names = signature.renamesByLabelAndType[dependency.property.label],
			      let name = names[dependency.property.typeDescription] ?? names[dependency.property.asUnwrappedProperty.typeDescription],
			      !rootLevelBindingNames.contains(dependency.property.label)
			else { continue }
			arguments.bindingLines.append("\(bodyIndent)let \(dependency.property.label): \(dependency.property.typeDescription.asSource) = \(name)")
			arguments.receivesBoundAgain.append(dependency.property)
			arguments.renames[dependency.property.label]?[dependency.property.typeDescription] = nil
		}
		// The mocked type's receive only if available of the optional form of a node or a parameter of `mock()` is passed
		// that binding, as `generateReturnArgumentList` passes it, and each such receive of a node named apart the node's name.
		let optionalForms = rootOptionalFormsProvidedByNodes(of: instantiable, nodeProperties: nodeProperties.union(signature.properties), renames: arguments.renames)
		for (label, names) in rootOptionalFormRenames(of: optionalForms, renames: arguments.renames) {
			arguments.renames[label, default: [:]].merge(names) { renamed, _ in renamed }
		}
		return arguments
	}
}

extension ScopeGenerator {
	/// The mock of `instantiable`, whose tree `root` leaves unbuilt, laid out from the node records of its world, or `nil`
	/// where they refuse it, and its tree must be built: what the walk of its tree writes
	/// (`lowerMockRootWithTree(of:context:worldRoot:)`) where node records lay it out, every input read from its world and
	/// its signature. A refusal is reported to no test, since the walk of the tree built after asks node records again.
	static func lowerUnbuiltMockRoot(_ root: UnbuiltMockRoot, of instantiable: Instantiable, context: MockContext) -> MockLowering.Result? {
		// A type with no dependencies and no default-valued parameter is one call of its construction (`lowerMockRoot(context:worldRoot:promotion:)`).
		if instantiable.dependencies.isEmpty, (instantiable.mockInitializer ?? instantiable.initializer)?.arguments.contains(where: \.hasDefaultValue) == false {
			return MockLowering.Result(code: mockWithoutTree(of: instantiable, context: context))
		}
		let signature = root.signature
		let bodyIndent = "\(standardIndent)\(standardIndent)"
		// What the root's level binds, read off its world by the rule the walk decides it by, with no call in the tree.
		let levelBindings = MockLowering.rootLevelBindings(of: instantiable, signature: signature, rootLevelNodes: root.rootLevelNodes, callsBindNothing: true)
		// The level's nodes that build or rename a property, as the walk's nodes hold them.
		let nodeProperties = Set(root.rootLevelNodes.compactMap { node -> Property? in
			switch node {
			case let .property(property, isUnavailableDependency): isUnavailableDependency ? nil : property
			case let .alias(property): property
			case .other: nil
			}
		})
		let rootArguments = MockLowering.rootArguments(of: instantiable, signature: signature, namesApart: levelBindings.namesApart, propertyNodeBindingNames: levelBindings.propertyNodeBindingNames, nodeProperties: nodeProperties, bodyIndent: bodyIndent)
		// `mock()` binds what it takes before its nodes as the walk does, with no builder a call passes up: each override of
		// what its tree receives only if available that something fulfills, then the wrappers it makes of the instances it
		// takes and the mocked type's own receives bound again under their labels.
		let overridesBoundBeforeNodes = signature.onlyIfAvailableOverrides.filter { signature.unavailableDependencyOverrideNames[$0.receivedProperty] == nil }
		let unavailableDependencyOverrides = signature.onlyIfAvailableOverrides.filter { signature.unavailableDependencyOverrideNames[$0.receivedProperty] != nil }
		var outerDeclarations = signature.parameters.map { Property(label: $0.name, typeDescription: $0.property.typeDescription) }
		outerDeclarations += overridesBoundBeforeNodes.map { Property(label: $0.name, typeDescription: $0.typeDescription) }
		outerDeclarations += unavailableDependencyOverrides.map { Property(label: $0.name, typeDescription: $0.typeDescription) }
		outerDeclarations += rootArguments.receivesBoundAgain
		outerDeclarations += signature.lazilyInstantiatedBindings.map { Property(label: $0.name, typeDescription: $0.boundType) }
		guard let layout = nodeRecordsMockStatements(
			of: instantiable,
			world: root.world.naming(MockRootNames(
				namesApart: levelBindings.namesApart,
				unavailableDependencyOverrides: signature.onlyIfAvailableOverrides.compactMap { override in signature.unavailableDependencyOverrideNames[override.receivedProperty].map { (override.receivedProperty, $0) } },
				passedUpBuilderNames: signature.passedUpBuilderNames,
				uncoveredParameterNames: Dictionary(
					signature.uncoveredRootParameters.filter { !$0.isSendableAutoclosure }.map { ($0.property, $0.label) },
					uniquingKeysWith: { first, _ in first },
				),
				edgesConfigurationsLeaveOut: context.cycleEdges,
				placeBuilderBindings: [:],
				wrapperBindingNames: signature.lazilyInstantiatedBindingNamesByLabelAndType,
				// `UnbuiltMockRoot.leavingTreeUnbuilt` keeps the tree of a root with such a loop member.
				loopMembersBoundNowhere: [],
				receivesPassedNil: root.worldRoot.receivesPassedNil,
			)),
			bindsOnlyNodes: levelBindings.bindsOnlyNodes,
			sendableConfigurationTypeNames: context.sendableConfigurationTypeNames,
			outerDeclarations: outerDeclarations,
			handWrittenMockDefaultParameters: context.handWrittenMockDefaultParameters,
			reportsRefusal: false,
		) else { return nil }
		var bindingLines = overridesBoundBeforeNodes.map { override in
			"\(bodyIndent)let \(override.name): \(override.typeDescription.asSource) = \(ReservedName.mockOverridesParameterName).\(override.name)"
		}
		bindingLines += unavailableDependencyOverrides.map { override in
			"\(bodyIndent)let \(override.name): \(override.typeDescription.asSource) = \(ReservedName.mockOverridesParameterName).\(override.name)"
		}
		bindingLines += signature.lazilyInstantiatedBindingLines(indent: bodyIndent)
		bindingLines += rootArguments.bindingLines
		if !layout.statements.isEmpty {
			bindingLines.append(layout.statements)
		}
		let builders = signature.placeOnlyBuilderDeclarations.sorted { $0.label < $1.label }
		// No node at the root's level is a lazy wrapper, so the mocked type is passed no wrapper's instance it reads by value.
		return MockLowering.Result(
			code: mockWithTree(of: instantiable, signature: signature, surface: layout.surface, bindingLines: bindingLines, builders: builders, rootRenames: rootArguments.renames, unavailableProperties: [], instancesReadByValue: [], context: context),
			configurations: layout.surface.configurations,
		)
	}
}

/// What a test observes of the mock roots `generateMockCode` builds no generator tree for (`UnbuiltMockRoot`).
public enum MockRootTreeSkipObservation {
	/// Whether a mock root that node records may lay out with no tree is left unbuilt, where node records lay mock roots
	/// out (`NodeRecordsObservation.laysOutMockRoots`). On unless a test turns it off, to compare a root's code with and
	/// without its tree.
	@TaskLocal public static var leavesTreesUnbuilt = true
	/// Handed each mock root's outcome where node records lay mock roots out, where set. Only a test sets it.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (MockRootTreeSkipReport) -> Void>?
}

/// One mock root's outcome (`MockRootTreeSkipObservation`).
public struct MockRootTreeSkipReport: Sendable, Equatable {
	/// The outcome of a root left unbuilt whose records laid it out.
	public static let leftUnbuilt = "left unbuilt"
	/// The outcome of a root left unbuilt whose records refused it, whose tree was built after.
	public static let builtAfterRecordsRefused = "built after its records refused"

	public init(root: String, outcome: String) {
		self.root = root
		self.outcome = outcome
	}

	/// The mocked type.
	public let root: String
	/// `leftUnbuilt`, `builtAfterRecordsRefused`, or why the root kept its tree (`UnbuiltMockRoot.Refusal`).
	public let outcome: String
}
