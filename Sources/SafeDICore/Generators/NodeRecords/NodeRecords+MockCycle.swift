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

/// A cycle of a mock root's world.
///
/// A mock's function on a cycle cannot tell from its text whether a call of it enters a new place or returns to one a
/// function above it entered: the builders that close the cycle are called when the mock runs, as often as the test
/// calls them. So each call of a function that a path can close on looks its slot up among the places entered above the
/// call (`ReservedName.mockEnteringFunctionName`, which `mock()` declares once: `MockEnteredSlot`'s declaration): a
/// place found there is the one entered before, whose configuration the function reads, as the mock's walk reads the
/// override of the nearest place on the path that builds the same property (`MockLowering.AncestorOverridePath`);
/// otherwise the call enters a new place with the configuration it hands. The function is handed that configuration
/// and the places entered, its own included, in one argument (`ReservedName.mockEnteredPlacesParameterName`), so it
/// begins with no statement of its own and is as long as a function on no cycle. No record of the form is a closer's
/// alone: a call that closes a cycle and a call that enters it hand the same argument
/// (`mockArgumentsHanded(to:labeled:by:in:slots:)`), and the node's record is the mock construction record with it.
///
/// A configuration has no field for a child along an edge the module's configurations leave out, which keeps a
/// configuration from holding itself (`DependencyTreeGenerator.computeCycleEdges(in:)`), so a call along such an edge
/// hands an empty configuration: the function called finds its place among those entered, or builds as a mock with no
/// override does, which is what the walk builds beneath such an edge.
extension NodeRecords {
	/// The refusals of stage 1 a node on a cycle of a mock root's world discharges: `cycle`.
	static func mockCycleDischarges(of declaration: DeclarationID, in world: some NodeRecordSources) -> Set<NodeRecordRefusal> {
		world.isOnCycle(declaration) ? [.cycle] : []
	}

	/// Whether the configuration of `parent`'s type has no field for `declaration`, which `parent` builds: the edge between
	/// their types is one the module's configurations leave out. The root's overrides are no configuration of its type,
	/// and hold a field for every child the root builds.
	static func mockConfigurationLeavesOut(_ declaration: DeclarationID, builtBy parent: DeclarationID, in world: some NodeRecordSources) -> Bool {
		let edgesLeftOut = world.mockRootNames.edgesConfigurationsLeaveOut
		// Nearly every mock's module has no such edge, and spelling the types is most of the question's cost.
		guard parent != 0, !edgesLeftOut.isEmpty else { return false }
		return edgesLeftOut.contains(ScopeGenerator.CycleEdge(
			parent: world.scope(of: parent).instantiable.concreteInstantiable.asSource,
			child: world.scope(of: declaration).instantiable.concreteInstantiable.asSource,
		))
	}

	/// What a call in the body of `parent`'s place hands the function of `declaration`, a node of a mock root's world that
	/// takes the places entered (`takesMockEnteredPlaces(_:in:)`): one argument, the node's configuration with the places
	/// entered. The configuration handed is the field named `label` of the configuration `parent`'s body reads, or an
	/// empty one along an edge the configurations leave out. The places are those `parent`'s body holds: its function's
	/// own argument, or `mock()`'s own value, with none entered, in the root's body and in the body of a function that
	/// takes none. Such a function is on no cycle and between no two places of one configuration, so no place entered
	/// above it is one a function beneath it reads. The call looks the node's slot up among them where a path can close
	/// on the node, for the nearest configuration of its type too where several slots build that type; enters the
	/// nearest place of its type alone for a node on no cycle that a slot of its configuration is entered beneath; and
	/// otherwise only hands the places on. A built place in each body that holds it
	/// (`mockPlace(_:record:of:builtBy:in:slots:)`) and a call that closes a cycle on the node both take their argument
	/// from here, so two calls of one function differ only by who calls.
	static func mockArgumentsHanded(to declaration: DeclarationID, labeled label: String, by parent: DeclarationID, in world: some NodeRecordSources, slots: MockEnteredSlots) -> [PassedArgument] {
		let configurationType = mockConfigurationType(of: world.scope(of: declaration).instantiable)
		let configuration: ValuePath = if mockConfigurationLeavesOut(declaration, builtBy: parent, in: world) {
			.emptyInitialization(configurationType)
		} else {
			.member(label, of: mockOverridesOfChildren(of: parent, in: world, slots: slots))
		}
		let entered: ValuePath = takesMockEnteredPlaces(parent, in: slots)
			? .passedArgument(ReservedName.mockEnteredPlacesParameterName)
			: .rootDeclaration(ReservedName.mockEnteredPlacesParameterName)
		let value: ValuePath = if let slot = mockEnteredSlot(of: declaration, in: slots) {
			.callHanding(
				ReservedName.mockEnteringFunctionName,
				of: entered,
				literal: slot.name,
				value: configuration,
				flags: slot.nearestOfTypeSlotName == nil ? [] : [ReservedName.mockEnteringNearestOfTypeArgumentLabel],
			)
		} else if mockNearestOfTypeEntered(by: declaration, in: slots) != nil {
			.callHanding(ReservedName.mockEnteringNearestFunctionName, of: entered, literal: nil, value: configuration, flags: [])
		} else {
			.callHanding(ReservedName.mockPassingFunctionName, of: entered, literal: nil, value: configuration, flags: [])
		}
		return [
			// Neither the configuration nor the places are `Sendable`: no call inside a `@Sendable` function hands them on.
			PassedArgument(
				parameterName: ReservedName.mockEnteredPlacesParameterName,
				type: .simple(name: ReservedName.mockEnteredTypeName, generics: [configurationType]),
				value: value,
				staysOutsideSendableFunctions: true,
			),
		]
	}

	/// The configuration the body of `declaration`'s function reads as its own, where the function takes the places
	/// entered: the member of its one argument that holds it.
	static let mockEnteredConfiguration = ValuePath.member(ReservedName.mockEnteredConfigurationMemberName, of: .passedArgument(ReservedName.mockEnteredPlacesParameterName))

	/// `place`, the place of `declaration` whose record is `record`, as the body of `parent`'s place holds it. One place
	/// stands for a node in every body that builds it, and a function that takes the places entered is handed by each
	/// parent a field of that parent's own configuration, or none along an edge the configurations leave out, so each
	/// body's place hands its own values to the one function (`TypeKeyLayout` keeps the values of each call). A node whose
	/// function takes no places reads its override as a field of the configuration its first parent's body reads
	/// (`mockConfigurationField(of:named:in:slots:)`), which a function that takes the places reads of its one argument
	/// and every other body of the overrides it was handed: where `parent`'s body reads another configuration than the
	/// first parent's, its place reads the field of its own, in the value it hands the node's function, or, for a node
	/// built in place, in the closure the construction tries first. Every other place is the same in each body.
	static func mockPlace(_ place: GeneratedCode, record: PlaceRecord?, of declaration: DeclarationID, builtBy parent: DeclarationID, in world: some NodeRecordSources, slots: MockEnteredSlots?) -> GeneratedCode {
		guard let slots, case var .built(built) = record else { return place }
		if takesMockEnteredPlaces(declaration, in: slots) {
			let handed = mockArgumentsHanded(to: declaration, labeled: built.property.label, by: parent, in: world, slots: slots)
			built.passedArguments = handed + built.passedArguments.dropFirst(handed.count)
		} else {
			let firstParent = world.parents(of: declaration).first?.parent ?? 0
			guard takesMockEnteredPlaces(parent, in: slots) != takesMockEnteredPlaces(firstParent, in: slots) else { return place }
			let label = built.property.label
			let fieldOfFirstParent = mockConfigurationField(of: declaration, named: label, in: world, slots: slots)
			let field = ValuePath.member(label, of: mockOverridesOfChildren(of: parent, in: world, slots: slots))
			if built.hasFunction {
				built.passedArguments = built.passedArguments.map { argument in
					PassedArgument(
						parameterName: argument.parameterName,
						type: argument.type,
						value: argument.value == fieldOfFirstParent ? field : argument.value,
						staysOutsideSendableFunctions: argument.staysOutsideSendableFunctions,
					)
				}
			} else {
				built.alternatives = built.alternatives.map { alternative in
					ConstructionAlternative(
						closure: alternative.closure == fieldOfFirstParent ? field : alternative.closure,
						bindingName: alternative.bindingName,
						requiresAbsent: alternative.requiresAbsent,
						use: alternative.use,
						resultWrapper: alternative.resultWrapper,
					)
				}
			}
		}
		return .place(PlacePlan(code: .empty, record: .built(built)))
	}

	/// The types of the configurations the functions of `world`, a mock root's, that take the places entered are handed,
	/// where an actor the mock builds with its initializer is sent a value such a function builds; `nil` where none is.
	///
	/// A value a function builds of an argument that is not `Sendable` cannot be sent, so there `mock()` declares the
	/// places in their `Sendable` form (`MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable:entersNearest:passes:)`),
	/// which holds only configurations of the `Sendable` form: the root's lowering, which knows which types take that
	/// form, refuses the world as `mockActor` where one of these does not
	/// (`ScopeGenerator.nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:sendableConfigurationTypeNames:rootNames:outerDeclarations:)`).
	/// The walk builds such a value of what the actor's own function captures.
	static func mockConfigurationTypeNamesHandedWithPlacesAnActorIsSentValueOf(in world: some NodeRecordSources, slots: MockEnteredSlots) -> Set<String>? {
		let declarationsHandedPlaces = (1..<Int32(world.declarationCount)).filter { takesMockEnteredPlaces($0, in: slots) }
		let actorIsSentValue = declarationsHandedPlaces.contains { declaration in
			world.parents(of: declaration).contains { isActorBuiltWithInitializer($0.parent, in: world) }
		}
		guard actorIsSentValue else { return nil }
		return Set(declarationsHandedPlaces.map { world.scope(of: $0).instantiable.concreteInstantiable.asSource })
	}

	/// Refuses `world`, a mock root's that holds a cycle, in the shapes the slot form does not make yet.
	///
	/// A function that takes the places and is `@Sendable` needs no refusal here: a node built in a `@Sendable` function
	/// whose child is built in a function of its own is refused as `sendable` before this
	/// (`mockSendableRefusals(of:in:)`), and every node that takes the places has such a child, the next node toward the
	/// place entered. The engine also lays out no `@Sendable` function that is handed a value that stays outside one, as
	/// the places and the overrides do (`TypeKeyLayout.checkSendableMarks()`).
	/// - Throws: `mockCycleLazy` where a function that takes the places entered builds a `LazilyInstantiated`, whose
	///   closing is the lazy kind's to add; `mockDefaultValuedParameter` where a node built along an edge the
	///   configurations leave out, or beneath one, reads a field of its configuration for a default-valued parameter. The
	///   empty configuration such a call hands holds one value of the parameter's default, which every node built of it
	///   and of the place that keeps it would share, where the walk leaves each construction beneath such an edge to its
	///   initializer's own default, evaluated again each time.
	static func checkMockCycles(in world: some NodeRecordSources, slots: MockEnteredSlots) throws(NodeRecordRefusal) {
		var builtOfEmptyConfiguration = Set<DeclarationID>()
		var pending = (1..<Int32(world.declarationCount)).filter { declaration in
			world.parents(of: declaration).contains { mockConfigurationLeavesOut(declaration, builtBy: $0.parent, in: world) }
		}
		while let declaration = pending.popLast() {
			guard builtOfEmptyConfiguration.insert(declaration).inserted else { continue }
			pending.append(contentsOf: world.edges(from: declaration))
		}
		guard builtOfEmptyConfiguration.allSatisfy({ mockConfigurationFieldArguments(of: $0, in: world).isEmpty }) else { throw .mockDefaultValuedParameter }
		for declaration in 1..<Int32(world.declarationCount) where takesMockEnteredPlaces(declaration, in: slots) {
			switch world.kind(of: declaration) {
			case .lazy, .sendableLazy:
				throw .mockCycleLazy
			case .constant, .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .alias, .hole:
				break
			}
		}
	}
}
