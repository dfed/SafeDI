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

/// A cycle of a mock root's world, in the slot form.
///
/// A mock's function on a cycle cannot tell from its text whether a call of it enters a new place or returns to one a
/// function above it entered: the builders that close the cycle are called when the mock runs, as often as the test
/// calls them. So each function that a path can close on reads its slot of the places entered above it
/// (`ReservedName.mockEnteredPlacesParameterName`), which every call hands on beside its overrides: a place found there
/// is the one entered before, whose configuration the function reads, as the mock's walk reads the override of the
/// nearest place on the path that builds the same property (`MockLowering.AncestorOverridePath`); otherwise the function
/// enters a new place with the overrides it was handed (`EnteredPlace`, which the engine spells). No record of the form
/// is a closer's alone: a call that closes a cycle and a call that enters it hand the same two arguments
/// (`mockArgumentsHanded(to:labeled:by:in:slots:)`), and the node's record is the mock construction record with them.
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
	/// takes the places entered (`takesMockEnteredPlaces(_:in:)`): the node's overrides, the field named `label` of the
	/// configuration `parent`'s body was handed, or an empty configuration along an edge the configurations leave out;
	/// then the places entered, as `parent`'s body holds them: those its function was handed, or `mock()`'s own, with none
	/// entered, in the root's body and in the body of a function that takes none. Such a function is on no cycle and
	/// between no two places of one configuration, so no place entered above it is one a function beneath it reads. A
	/// built place in each body that holds it (`mockPlace(_:record:of:builtBy:in:slots:)`) and a call that closes a cycle
	/// on the node both take their arguments from here, so two calls of one function differ only by who calls.
	static func mockArgumentsHanded(to declaration: DeclarationID, labeled label: String, by parent: DeclarationID, in world: some NodeRecordSources, slots: MockEnteredSlots) -> [PassedArgument] {
		let configurationType = mockConfigurationType(of: world.scope(of: declaration).instantiable)
		let overrides: ValuePath = if mockConfigurationLeavesOut(declaration, builtBy: parent, in: world) {
			.emptyInitialization(configurationType)
		} else {
			.member(label.spelledAsMemberDeclarationName, of: mockOverridesOfChildren(of: parent, in: world))
		}
		return [
			// Neither the overrides nor the places are `Sendable`: no call inside a `@Sendable` function hands them on.
			PassedArgument(parameterName: ReservedName.mockOverridesParameterName, type: configurationType, value: overrides, staysOutsideSendableFunctions: true),
			PassedArgument(
				parameterName: ReservedName.mockEnteredPlacesParameterName,
				type: .simple(name: ReservedName.mockEnteredPlacesTypeName),
				value: takesMockEnteredPlaces(parent, in: slots)
					? .passedArgument(ReservedName.mockEnteredPlacesParameterName)
					: .rootDeclaration(ReservedName.mockEnteredPlacesParameterName),
				staysOutsideSendableFunctions: true,
			),
		]
	}

	/// `place`, the place of `declaration` whose record is `record`, as the body of `parent`'s place holds it. One place
	/// stands for a node in every body that builds it, and a function that takes the places entered is handed by each
	/// parent a field of that parent's own configuration, or none along an edge the configurations leave out, so each
	/// body's place hands its own values to the one function (`TypeKeyLayout` keeps the values of each call). Every other
	/// place is the same in each body.
	static func mockPlace(_ place: GeneratedCode, record: PlaceRecord?, of declaration: DeclarationID, builtBy parent: DeclarationID, in world: some NodeRecordSources, slots: MockEnteredSlots?) -> GeneratedCode {
		guard let slots, takesMockEnteredPlaces(declaration, in: slots), case var .built(built) = record else { return place }
		let handed = mockArgumentsHanded(to: declaration, labeled: built.property.label, by: parent, in: world, slots: slots)
		built.passedArguments = handed + built.passedArguments.dropFirst(handed.count)
		return .place(PlacePlan(code: .empty, record: .built(built)))
	}

	/// The statement the function of `declaration` begins with, where it enters a place: its slot's, for a node a path can
	/// close on, with the member that holds the nearest place of its configuration where another property builds it; that
	/// member alone, for a node off every cycle that a place of its configuration is entered beneath; `nil` for a node
	/// that only hands the places on, and for one that takes none.
	static func mockEnteredPlace(of declaration: DeclarationID, in slots: MockEnteredSlots) -> EnteredPlace? {
		if let slot = mockEnteredSlot(of: declaration, in: slots) {
			EnteredPlace(slot: slot.name, nearestOfTypeSlot: slot.nearestOfTypeSlotName)
		} else {
			mockNearestOfTypeEntered(by: declaration, in: slots).map { EnteredPlace(slot: nil, nearestOfTypeSlot: $0) }
		}
	}

	/// Refuses `world`, a mock root's that holds a cycle, in the shapes the slot form does not make yet.
	///
	/// A function that takes the places and is `@Sendable` needs no refusal here: a node built in a `@Sendable` function
	/// whose child is built in a function of its own is refused as `sendable` before this
	/// (`mockSendableRefusals(of:in:)`), and every node that takes the places has such a child, the next node toward the
	/// place entered, a `SendableLazilyInstantiated`'s instance included. The engine also lays out no `@Sendable` function
	/// that is handed a value that stays outside one, as the places and the overrides do (`TypeKeyLayout.checkSendableMarks()`).
	/// A function that takes the places and builds a `LazilyInstantiated` needs none either: its builder function is handed
	/// the places as an instantiator's is, and the wrapper makes the instance once, where the walk's does.
	/// - Throws: `mockActor` where an actor is sent a value a function that takes the places entered builds, which is
	///   built of the places the function was handed and so cannot be sent, where the walk builds the value of what the
	///   actor's own function captures; `mockDefaultValuedParameter` where a node built along an edge the
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
			guard !world.parents(of: declaration).contains(where: { isActorBuiltWithInitializer($0.parent, in: world) }) else { throw .mockActor }
		}
	}
}
