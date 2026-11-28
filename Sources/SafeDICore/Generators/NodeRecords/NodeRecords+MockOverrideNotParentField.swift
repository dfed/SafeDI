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

/// How the type that instantiates a place of a seam's own mock binds it from the builder `mock()` takes for the place, as
/// the walk binds it at the top of the type's function (`ScopeGenerator.SendableAutoclosureParameter.binding`).
struct MockPlaceBuilderBinding: Sendable {
	/// The place's property, as the type that instantiates it declares it.
	let dependency: Property
	/// The place, under the name the binding declares.
	let property: Property
	/// The builder, under the name `mock()` binds it.
	let builder: Property
	/// The binding's statement.
	let text: String

	/// The place of the binding in a node's function, read as a rename of the builder is, so that what the node builds
	/// reads the place as any value the node declares.
	var place: GeneratedCode {
		.indented(
			.place(PlacePlan(code: .text(text), record: .alias(AliasPlaceRecord(property: property, fulfillingProperty: builder, text: text)))),
			by: ScopeGenerator.standardIndent,
		)
	}
}

/// What a mock root's lowering names that the records of its world read: values of the root's level, which no fact of
/// the world holds, so the world is made with them (`TypeFactsGraph.mockRootNames`). Empty for every production root's world.
struct MockRootNames: Sendable {
	/// - Parameters:
	///   - namesApart: The name the root's level gives each child it names apart, by the child's label and then its
	///     property's type (`MockLowering.Walk.rootRenames`).
	///   - unavailableDependencyOverrides: Each property instantiated only if available that nothing fulfills and that
	///     `mock()` takes an override of, with the override's name
	///     (`MockLowering.RootSignature.unavailableDependencyOverrideNames`).
	///   - passedUpBuilderNames: The name `mock()` binds each builder under that a call of another module's public mock passes
	///     up, by the property the call's leaf receives it as (`MockLowering.RootSignature.passedUpBuilderNames`).
	///   - uncoveredParameterNames: The name of the parameter `mock()` takes as a plain value for each dependency a type of the
	///     tree instantiates that the mock cannot build, by the dependency's property, its label where it is not named apart
	///     (`MockLowering.RootSignature.uncoveredParameters`); a `@Sendable` autoclosure parameter is none.
	///   - edgesConfigurationsLeaveOut: The edges between two types of a cycle that the module's configurations leave out,
	///     so that no configuration holds itself (`ScopeGenerator.MockContext.cycleEdges`): the parent's configuration has
	///     no field for the child. A fact of the module's types together, which no root's world holds.
	///   - placeBuilderBindings: The binding of each place of a seam's own mock from the builder `mock()` takes for it, by the
	///     place's property (`MockLowering.RootSignature.PassedUpBuilder.places`).
	///   - wrapperBindingNames: The name `mock()` binds each lazy wrapper under that it makes of an instance it takes, by the
	///     wrapper's label and then type (`MockLowering.RootSignature.lazilyInstantiatedBindingNamesByLabelAndType`), which
	///     every receive of the wrapper is passed by name.
	///   - loopMembersBoundNowhere: The members of the root's loops of builders that nothing outside their loop reads,
	///     whose function the root declares and whose wrapper it binds nowhere, as the walk writes them
	///     (`ScopeGenerator.loopMembersReadOnlyInsideTheirLoop`).
	///   - receivesPassedNil: The receives only if available in the mock's trees that production passes `nil`, as the mock
	///     root's promotion found them (`DependencyTreeGenerator.receivesPassedNilInMockTree`), which the walk reads from
	///     the mock root's bindings (`NearestDeclarations.binding(_:passingNilTo:)`).
	init(namesApart: [String: [TypeDescription: String]] = [:], unavailableDependencyOverrides: [(property: Property, name: String)] = [], passedUpBuilderNames: [Property: String] = [:], uncoveredParameterNames: [Property: String] = [:], edgesConfigurationsLeaveOut: Set<ScopeGenerator.CycleEdge> = [], placeBuilderBindings: [Property: MockPlaceBuilderBinding] = [:], wrapperBindingNames: [String: [TypeDescription: String]] = [:], loopMembersBoundNowhere: Set<Property> = [], receivesPassedNil: MockReceivesPassedNil = MockReceivesPassedNil()) {
		self.receivesPassedNil = receivesPassedNil
		self.loopMembersBoundNowhere = loopMembersBoundNowhere
		self.namesApart = namesApart
		self.edgesConfigurationsLeaveOut = edgesConfigurationsLeaveOut
		self.placeBuilderBindings = placeBuilderBindings
		self.wrapperBindingNames = wrapperBindingNames
		self.passedUpBuilderNames = passedUpBuilderNames
		self.uncoveredParameterNames = uncoveredParameterNames
		unavailableDependencyOverrideNames = Dictionary(unavailableDependencyOverrides.map { ($0.property, $0.name) }) { first, _ in first }
	}

	/// The members of the root's loops of builders whose wrapper the root binds nowhere (`init`'s `loopMembersBoundNowhere`).
	let loopMembersBoundNowhere: Set<Property>

	/// The name the mock root binds `property` under where it names it apart from a sibling of its label, and `nil`
	/// where the root binds the property under its label or does not bind it.
	func nameApart(of property: Property) -> String? {
		namesApart[property.label]?[property.typeDescription]
	}

	/// Whether production passes `nil` to the receive of `property` only if available that `type` declares wherever `type`
	/// is built beneath the mock root's bindings of the label: a required receive on `type`, or beneath it, pins the
	/// declaration the receive reads to a form it cannot read (`MockReceivesPassedNil.pinnedWhereverBuilt`).
	func passesNilWhereverBuilt(toReceiveOf property: Property, on type: TypeDescription) -> Bool {
		receivesPassedNil.pinnedWhereverBuilt[property.label]?[type]?.contains(property) ?? false
	}

	/// Whether a required receive of `label` above some receive of it only if available pins that receive in the places
	/// beneath it and in no other (`MockReceivesPassedNil.labelsPinnedFromAbove`).
	func pinsFromAbove(label: String) -> Bool {
		receivesPassedNil.labelsPinnedFromAbove.contains(label)
	}

	/// Whether `property` is that of a child the mock root promotes, whose tree production builds above the mocked type,
	/// so that the mocked type's own required receives pin nothing in it (`MockReceivesPassedNil.promotedProperties`).
	func promotes(_ property: Property) -> Bool {
		receivesPassedNil.promotedProperties.contains(property)
	}

	private let receivesPassedNil: MockReceivesPassedNil

	/// Whether the root names apart a child labeled `label`.
	func namesApart(label: String) -> Bool {
		namesApart[label].map { !$0.isEmpty } ?? false
	}

	/// The name of the override `mock()` takes of `property`, one instantiated only if available that nothing fulfills,
	/// and `nil` where it takes none.
	func unavailableDependencyOverrideName(of property: Property) -> String? {
		unavailableDependencyOverrideNames[property]
	}

	/// The edges between two types of a cycle that the module's configurations leave out (`NodeRecords+MockCycle.swift`).
	let edgesConfigurationsLeaveOut: Set<ScopeGenerator.CycleEdge>

	/// The name `mock()` binds the builder under that a call's leaf receives as `property`, and `nil` where `mock()` takes no
	/// builder the leaf receives so.
	func passedUpBuilderName(of property: Property) -> String? {
		passedUpBuilderNames[property]
	}

	/// The name of each value of the root's level a node binds again under its label where it receives it, by label and
	/// then type: each value the root names apart, and each builder a call passes up that `mock()` binds under another name
	/// (`NodeRecords.mockNamesReadApart(in:)`).
	var namesBoundAgain: [String: [TypeDescription: String]] {
		var names = namesApart
		for (property, name) in passedUpBuilderNames where name != property.label {
			names[property.label, default: [:]][property.typeDescription] = name
		}
		return names
	}

	/// The name the root gives each value of its level it names apart, by label and then type.
	var namesApart: [String: [TypeDescription: String]]

	/// The name of the parameter `mock()` takes as a plain value for `property`, a dependency a type of the tree instantiates
	/// that the mock cannot build, and `nil` where it takes none so.
	func uncoveredParameterName(of property: Property) -> String? {
		uncoveredParameterNames[property]
	}

	/// Whether `mock()` names a parameter it takes for an uncovered dependency apart from the dependency's label.
	var namesUncoveredParameterApart: Bool {
		uncoveredParameterNames.contains { $0.key.label != $0.value }
	}

	private let uncoveredParameterNames: [Property: String]

	/// The name `mock()` binds each lazy wrapper under that it makes of an instance it takes, by label and then type, which
	/// a node passes every receive of the wrapper (`NodeRecords.mockNamesReadApart(in:)`).
	let wrapperBindingNames: [String: [TypeDescription: String]]

	/// The binding of `property`, a place of a seam's own mock, from the builder `mock()` takes for it, and `nil` where
	/// `mock()` takes no builder that builds it.
	func placeBuilderBinding(of property: Property) -> MockPlaceBuilderBinding? {
		placeBuilderBindings[property]
	}

	private let placeBuilderBindings: [Property: MockPlaceBuilderBinding]

	private let passedUpBuilderNames: [Property: String]
	private let unavailableDependencyOverrideNames: [Property: String]
}

extension NodeRecords {
	/// The refusal `declaration`, a node of a mock root's world, holds for a label the root names apart, or none.
	///
	/// A mock root promotes each form of a label its tree receives and names the forms apart
	/// (`ScopeGenerator.disambiguatePropertyLabels(forProperties:besideParametersKeepingTheirLabels:reservedNames:)`), and
	/// names apart a parameter of `mock()` or an override beside another form of its label, so the override of such a child
	/// is the root's field under the name, and each type that receives the label where no declaration between hides it binds
	/// the name again under the label at the top of its function (`mockNamesReadApart(in:)`). Refused, and left to the
	/// walk: two children of one label under any other node, or under a root that was handed no name for one; a child of the
	/// root named apart whose property is optional, which the walk binds as the value it builds; a rename of such a label
	/// or from one, whose binding the walk reads otherwise. A receive of the label only if available reads the name, bound
	/// again, where it is available, and `nil` otherwise (`mockNamesReadApart(in:)`); where a required receive of another
	/// form pins the label from above (`MockRootNames.pinsFromAbove(label:)`), `OnlyIfAvailableAnswers` judge each call, and
	/// a function called both beneath the pin and away from it takes the name as a parameter
	/// (`MockNamesReadApart.bindNamesToNil(beneathPinsFoundBy:in:)`).
	static func refusalOfNamingApart(_ declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordRefusal? {
		let mockRootNames = world.mockRootNames
		var labels = Set<String>()
		for child in world.edges(from: declaration) {
			guard let property = world.property(of: child) else { continue }
			// The walk binds an optional form the root names apart without its type, so the binding is not optional; a
			// record's binding declares the property's type.
			guard declaration != 0 || mockRootNames.nameApart(of: property) == nil || !property.typeDescription.isOptional else { return .mockOverrideNotParentField }
			// A record binds and overrides a child the root names apart under that name wherever the child is built. Another
			// parent that builds the same declaration in line, as a cycle's function does, reads its override from that
			// parent's configuration, which holds the bare label: the walk names the child apart only in the root's own body.
			// A cycle that closes on the child calls the root's function, which reads the root's name.
			guard declaration != 0 || mockRootNames.nameApart(of: property) == nil || world.parents(of: child).allSatisfy({ parent in
				parent.parent == 0 || world.edgeFacts(from: parent.parent).contains { $0.child == child && $0.isCallEdge }
			}) else { return .mockOverrideNotParentField }
			guard !labels.insert(property.label).inserted else { continue }
			// Both children of the label are named apart, or neither is.
			guard declaration == 0, mockRootNames.namesApart(label: property.label) else { return .mockOverrideNotParentField }
		}
		guard declaration != 0 else { return nil }
		for dependency in world.scope(of: declaration).instantiable.dependencies {
			switch dependency.source {
			case .received:
				// A receive only if available reads the name or `nil`, as `OnlyIfAvailableAnswers` find it for every call.
				break
			case let .aliased(fulfillingProperty, _, _):
				// A rename reads its fulfilling label by name, which the walk resolves past a receive bound again.
				guard !mockRootNames.namesApart(label: dependency.property.label), !mockRootNames.namesApart(label: fulfillingProperty.label) else { return .mockOverrideNotParentField }
			case .instantiated, .forwarded:
				// A declaration of the label hides the name from what the node builds (`mockNamesReadApart(in:)`).
				break
			}
		}
		return nil
	}

	/// Whether `declaration`, a call of another module's public mock, takes a parameter under a label the mock root names
	/// apart. The walk hands such a call the name (`MockLowering.Walk.publicMockCallNode`), while a call's record reads each
	/// argument under its label and binds no name again, so the call's world keeps the walk.
	static func callTakesLabelNamedApart(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		let mockRootNames = world.mockRootNames
		return world.scope(of: declaration).instantiable.dependencies.contains { mockRootNames.namesApart(label: $0.property.label) }
	}
}
