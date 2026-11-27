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

/// A mock root's node built in a `@Sendable` function of its own: a `SendableInstantiator`, erased or not, or a
/// `SendableLazilyInstantiated`. The function cannot capture the overrides, which are not `Sendable`, nor be handed them,
/// so its override is read into a local bound just before the function, which the function captures, as the walk writes
/// it (`ScopeGenerator.SendableOverrideExtractor`): the node's whole configuration, `<function>__overrides`, whose
/// fields its children read, or, for a node with no configuration, its override closure, `<function>__safeDIBuilder`.
/// A configuration of a type built in a `@Sendable` function takes the `Sendable` form, as does each configuration
/// beneath it, so the local can cross into the function.
///
/// A wrapper an actor is sent that is not `@Sendable` (an `Instantiator`, erased or not, or a `LazilyInstantiated` the
/// actor builds) reads its override so too (`isWrapperSentToActor(_:in:)`): its closure is sent with it, so it captures
/// the local, and hands it to the wrapper's function.
///
/// The node's record is `mockConstruction`'s, marked `@Sendable` as the production kind's is
/// (`NodeRecords+Sendable.swift`); the local is a place of its parent's body, built in place before the node's
/// (`mockOverridesBindingPlace(of:record:in:)`).
extension NodeRecords {
	/// The refusals of stage 1 a mock root's node built in a `@Sendable` function of its own discharges: `sendable`.
	static func mockSendableDischarges(of declaration: DeclarationID, in world: some NodeRecordSources) -> Set<NodeRecordRefusal> {
		isBuiltInSendableFunction(declaration, in: world) ? [.sendable] : []
	}

	/// The shapes of a node built in a `@Sendable` function this kind does not make yet, refused as `sendable`: a node
	/// with more than one parent, or a child with more than one, whose override is read from more than one place; a child
	/// built in a function of its own, which would be handed the local's field across the `@Sendable` function; and a
	/// local whose name a node's label or function takes, which the walk names apart.
	static func mockSendableRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		guard isBuiltInSendableFunction(declaration, in: world), let label = world.property(of: declaration)?.label else { return [] }
		guard world.parents(of: declaration).count == 1 else { return [.sendable] }
		for child in world.edges(from: declaration) {
			guard world.parents(of: child).count == 1, !isBuiltInFunctionOfItsOwn(child, in: world) else { return [.sendable] }
		}
		guard !overridesLocalNameIsTaken(ofNodeLabeled: label, in: world) else { return [.sendable] }
		return []
	}

	/// The shape of a wrapper an actor is sent (`isWrapperSentToActor(_:in:)`) that is not made yet, refused as
	/// `mockActor`: a local whose name a node's label or function takes, which the walk names apart.
	static func mockActorWrapperRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		guard isWrapperSentToActor(declaration, in: world),
		      let label = world.property(of: declaration)?.label,
		      overridesLocalNameIsTaken(ofNodeLabeled: label, in: world)
		else { return [] }
		return [.mockActor]
	}

	/// Whether a node's label or function takes a name of the local the override of the node labeled `label` is read
	/// into.
	private static func overridesLocalNameIsTaken(ofNodeLabeled label: String, in world: some NodeRecordSources) -> Bool {
		let localNames = Set([true, false].map { mockOverridesLocalName(ofNodeLabeled: label, isConfigured: $0) })
		// Every node but the root is built as a property.
		let labels = (1..<Int32(world.declarationCount)).compactMap { world.property(of: $0)?.label }
		return labels.contains { localNames.contains($0) || localNames.contains(ScopeGenerator.functionName(toBuildPropertyNamed: $0)) }
	}

	/// Where `declaration`, a mock root's node built in a `@Sendable` function as the property labeled `label`, reads its
	/// override, a value of `type`: the local its parent's body binds it to before the function, which a function the
	/// root's body declares captures, as the walk writes it. Every other function is declared in the root's body too, away
	/// from the local, so it is handed the local's value as `mockOverrideSlot(of:labeled:typed:in:hasFunction:handsOverridesToChildren:isSendable:)`
	/// hands any function its overrides: the value is a configuration of the `Sendable` form, or a `@Sendable` closure,
	/// so it may cross into the function.
	static func mockSendableOverrideSlot(
		of declaration: DeclarationID,
		labeled label: String,
		typed type: TypeDescription,
		in world: some NodeRecordSources,
	) -> (value: ValuePath, passedArguments: [PassedArgument]) {
		let local = ValuePath.read(mockOverridesLocal(ofNodeLabeled: label, typed: type, isConfigured: isConfigured(declaration, in: world)))
		if capturesOverridesLocal(declaration, in: world) {
			return (local, [])
		} else {
			return (
				.passedArgument(ReservedName.mockOverridesParameterName),
				[PassedArgument(parameterName: ReservedName.mockOverridesParameterName, type: type, value: local, staysOutsideSendableFunctions: false)],
			)
		}
	}

	/// Whether a mock root's node captures the local its override is read into: a node built in a `@Sendable` function
	/// where the root's body builds it, and so declares both. A wrapper an actor is sent (`isWrapperSentToActor(_:in:)`)
	/// is built in a function the root's body declares once, before the local, so it is handed the local.
	private static func capturesOverridesLocal(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		!isWrapperSentToActor(declaration, in: world) && world.parents(of: declaration).allSatisfy { $0.parent == 0 }
	}

	/// Where the children of `parent`, a node of a mock root's world, read their overrides: the local a node built in a
	/// `@Sendable` function captures; the configuration a function that takes the places `slots` enter was handed with
	/// them (`mockEnteredConfiguration`); and otherwise the overrides `parent`'s body was handed, which the root's body
	/// reads of `mock()`'s own.
	static func mockOverridesOfChildren(of parent: DeclarationID, in world: some NodeRecordSources, slots: MockEnteredSlots?) -> ValuePath {
		if parent != 0, isBuiltInSendableFunction(parent, in: world), capturesOverridesLocal(parent, in: world), let property = world.property(of: parent) {
			.read(mockOverridesLocal(
				ofNodeLabeled: property.label,
				typed: mockConfigurationType(of: world.scope(of: parent).instantiable),
				isConfigured: true,
			))
		} else if let slots, takesMockEnteredPlaces(parent, in: slots) {
			mockEnteredConfiguration
		} else {
			.passedArgument(ReservedName.mockOverridesParameterName)
		}
	}

	/// The local a node of a mock root's world built as the property labeled `label` in a `@Sendable` function of its own
	/// reads its override into, a value of `type`: its configuration where `isConfigured`, and otherwise its override
	/// closure.
	static func mockOverridesLocal(ofNodeLabeled label: String, typed type: TypeDescription, isConfigured: Bool) -> PlaceRead {
		let name = mockOverridesLocalName(ofNodeLabeled: label, isConfigured: isConfigured)
		return PlaceRead(argumentLabel: name, label: name, property: Property(label: name, typeDescription: type), source: .binding(label: name))
	}

	/// The place that binds `record`'s override before its `@Sendable` function, where `record` is the record of a mock
	/// root's node built in one (`mockOverrideSlot(of:labeled:typed:in:hasFunction:handsOverridesToChildren:isSendable:)`),
	/// and `nil` for any other record: the field of its parent's overrides under its label, built in place.
	static func mockOverridesBindingPlace(of declaration: DeclarationID, record: PlaceRecord, in world: some NodeRecordSources, slots: MockEnteredSlots?) -> BuiltPlaceRecord? {
		guard world.isMockWorld, case let .built(built) = record, built.isSendable || isWrapperSentToActor(declaration, in: world) else { return nil }
		let instantiable = world.scope(of: declaration).instantiable
		let isConfigured = isConfigured(declaration, in: world)
		let usesHandWrittenMock = world.construction(of: declaration) == .handWrittenMock && instantiable.mockInitializer != nil
		let type = mockOverrideType(of: built, usesHandWrittenMock: usesHandWrittenMock, isConfigured: isConfigured, instantiable: instantiable)
		let local = mockOverridesLocal(ofNodeLabeled: built.property.label, typed: type, isConfigured: isConfigured)
		var binding = BuiltPlaceRecord(
			property: local.property,
			isErased: false,
			concreteType: type,
			isExtension: false,
			target: .initializer(type),
			arguments: [],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: local.label,
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: false,
			children: [],
			node: PlanNode(),
		)
		binding.constructionValue = ConstructionValue(value: mockConfigurationField(of: declaration, named: built.property.label, in: world, slots: slots), resultWrapper: nil)
		return binding
	}

	/// Whether a node of a mock root's world has a configuration, as its record's override type says
	/// (`mockConstructionRecord(of:variant:in:unavailableProperties:lazilyInstantiatedInstanceProperties:receivesBoundAgain:typesDeclaredEscaping:children:)`):
	/// whether it builds a child with an override of its own (`buildsMockChildWithOverride(_:in:)`), or passes its
	/// construction a field of its configuration (`mockConfigurationFieldArguments(of:in:)`). A node whose children are
	/// all renames has none, so the local its override is bound to is named as a closure's.
	private static func isConfigured(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		buildsMockChildWithOverride(declaration, in: world) || !mockConfigurationFieldArguments(of: declaration, in: world).isEmpty
	}

	/// The type of the configuration of a node of `instantiable`'s type.
	static func mockConfigurationType(of instantiable: Instantiable) -> TypeDescription {
		.nested(name: ScopeGenerator.mockConfigurationStructName, parentType: instantiable.concreteInstantiable, generics: [])
	}

	private static func mockOverridesLocalName(ofNodeLabeled label: String, isConfigured: Bool) -> String {
		"\(ScopeGenerator.functionName(toBuildPropertyNamed: label))__\(isConfigured ? "overrides" : ReservedName.configurationBuilderPropertyName)".spelledAsJoinedIdentifier
	}

	/// Whether a node of a mock root's world is built in a `@Sendable` function of its own.
	private static func isBuiltInSendableFunction(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		switch world.kind(of: declaration) {
		case .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
			true
		case .constant, .instantiator, .erasedInstantiator, .lazy, .alias, .hole:
			false
		}
	}

	/// Whether a node of a mock root's world is a wrapper an actor's initializer is sent: an `Instantiator`, erased or
	/// not, or a `LazilyInstantiated`, built by an actor the mock builds with its initializer. The wrapper's closure would
	/// capture the overrides the actor's function was handed, which are not `Sendable`, so its override is read into a
	/// local before it, as a `@Sendable` function's is, and as the walk writes it (`isInsideActorArgument` in
	/// `MockLowering+Walk.swift`).
	static func isWrapperSentToActor(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		switch world.kind(of: declaration) {
		case .instantiator, .erasedInstantiator, .lazy:
			world.parents(of: declaration).contains { isActorBuiltWithInitializer($0.parent, in: world) }
		case .constant, .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy, .alias, .hole:
			false
		}
	}

	/// Whether a node of a mock root's world, or its root, is an actor the mock builds with its initializer, which is
	/// sent each of its arguments.
	static func isActorBuiltWithInitializer(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		let instantiable = world.scope(of: declaration).instantiable
		return instantiable.declarationType == .actorType && !(world.construction(of: declaration) == .handWrittenMock && instantiable.mockInitializer != nil)
	}

	/// Whether a node is built in a function of its own: a wrapper's, or a constant's that builds children, as its record
	/// declares one (`NodeRecords+BuiltByInitializer.swift`).
	private static func isBuiltInFunctionOfItsOwn(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		switch world.kind(of: declaration) {
		case .instantiator, .erasedInstantiator, .lazy, .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
			true
		case .constant, .alias, .hole:
			!world.edges(from: declaration).isEmpty
		}
	}
}
