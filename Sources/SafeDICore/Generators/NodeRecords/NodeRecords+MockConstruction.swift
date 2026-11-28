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

extension NodeRecords {
	/// The claim of `declaration` in a mock root's world, and `nil` in a production root's: of kind `mockConstruction`, the
	/// record production makes of the node decorated with its override (`mockDecoratedRecord`), for every node no term
	/// before it claims (`NodeRecords.claim(of:in:)`), discharging what the override makes and what production's marks of
	/// the node discharge (`joiningProductionMarks(_:to:of:in:)`). A refusal neither discharges is the node's.
	static func mockConstructionClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.isMockWorld else { return nil }
		// A property nothing fulfills builds nothing, so it is no construction (`NodeRecords+MockUnavailableDependency.swift`).
		guard !world.scope(of: declaration).isUnavailableDependency else { return mockUnavailableDependencyClaim(of: declaration, in: world) }
		let override = mockOverrideDischargesAndRefusals(of: declaration, in: world)
		return joiningProductionMarks([.erased, .lazy], to: NodeRecordClaim(kind: .mockConstruction, discharges: override.discharges, refusals: override.refusals), of: declaration, in: world)
	}

	/// The function that builds `declaration`'s node in a mock: its type's hand-written mock where the world says so
	/// (`TypeFactsConstruction.handWrittenMock`), else its initializer or `instantiate(…)`.
	static func mockConstructionFunction(of declaration: DeclarationID, in world: some NodeRecordSources) -> Initializer? {
		let instantiable = world.scope(of: declaration).instantiable
		return (world.construction(of: declaration) == .handWrittenMock ? instantiable.mockInitializer : nil) ?? instantiable.initializer
	}

	/// Whether `declaration`, a node of a mock root's world, is handed its overrides for its children: it builds a child
	/// other than a rename, which reads its override from what the node's function is handed. A rename reads no override,
	/// so children that are all renames hand nothing on.
	static func isConfiguredMockNode(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		world.edges(from: declaration).contains { world.kind(of: $0) != .alias }
	}

	/// Whether `declaration`, a node of a mock root's world, builds a child with an override of its own, which neither a
	/// rename nor a property nothing fulfills has. Such a child makes the node's override a configuration, as a field its
	/// construction takes does (`mockConfigurationFieldArguments(of:in:)`); a node with neither is overridden by a
	/// closure. Each record, and each local that names a node's override, asks here, so that they agree.
	static func buildsMockChildWithOverride(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		world.edges(from: declaration).contains { world.kind(of: $0) != .alias && !world.scope(of: $0).isUnavailableDependency }
	}

	/// Whether `declaration`, a node of a mock root's world, is overridden by its configuration rather than by a closure:
	/// it builds a child with an override of its own (`buildsMockChildWithOverride(_:in:)`), or its construction takes a
	/// field of its configuration (`mockConfigurationFieldArguments(of:in:)`). A property nothing fulfills is a child with
	/// no override of its own, as a rename is, so neither makes its type a configuration; its function is still handed the
	/// overrides. The record of the node and the field of its parent's configuration both ask here, so that they agree.
	static func isOverriddenByConfiguration(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		buildsMockChildWithOverride(declaration, in: world) || !mockConfigurationFieldArguments(of: declaration, in: world).isEmpty
	}

	/// The record of `declaration`'s place in a mock root's world, before an erased node's decoration
	/// (`mockDecoratedRecord`): the record `builtByInitializer` makes of it, built with its type's hand-written mock where
	/// the world says so (`TypeFactsConstruction.handWrittenMock`), which first tries
	/// the closure that overrides it (`mockOverrideSlot(of:labeled:typed:in:hasFunction:handsOverridesToChildren:isSendable:)`),
	/// called with its construction's arguments. A node that builds a child with an override of its own (neither a rename
	/// nor a property nothing fulfills), or whose construction takes a field of its configuration
	/// (`mockConfigurationFieldArguments(of:in:)`), is configured: its override is the builder of the configuration its
	/// function is handed, whose fields its children and its own construction read, a field of an `@autoclosure` parameter
	/// called once where the node is built. A rename reads no override, and a property nothing fulfills reads one `mock()`
	/// binds before its nodes, so a node whose children are all of those two kinds and whose construction takes no
	/// field is not configured. The closure of a node that is not configured returns the property's type, so every node's
	/// function does, as the walk's does.
	/// - Parameter enteredSlots: The slots of the places the world's cycles enter, and which nodes take them; `nil` for a
	///   world with no cycle.
	static func mockConstructionRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		receivesBoundAgain: [MockReceiveBoundAgain],
		enteredSlots: MockEnteredSlots?,
		wrapperArgumentNames: [Property: String],
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let instantiable = world.scope(of: declaration).instantiable
		// A child of the root's level the mock root names apart is bound, and overridden, under that name, and a type that
		// receives a value named apart binds it again under its label before its own children (`mockNamesReadApart(in:)`).
		let nameApart = world.edges(from: 0).contains(declaration) ? world.property(of: declaration).flatMap(world.mockRootNames.nameApart(of:)) : nil
		let handWrittenMock: (function: Initializer, target: ConstructionTarget)? = if world.construction(of: declaration) == .handWrittenMock, let mockInitializer = instantiable.mockInitializer {
			(mockInitializer, .mock(instantiable.concreteInstantiable, name: instantiable.customMockName ?? InstantiableVisitor.mockMethodName))
		} else {
			nil
		}
		let fieldArguments = mockConfigurationFieldArguments(of: declaration, in: world)
		// A node reached only beneath an edge the configurations leave out has no configuration: the walk builds it with
		// no override, and passes only the defaults it reads from a configuration built afresh
		// (`mockFieldArgumentsReadAfresh(of:among:in:)`); the others it leaves to the initializer's own.
		let hasConfiguration = enteredSlots.map { $0.hasConfigurationByDeclaration[Int(declaration)] } ?? true
		let fieldArgumentsPassed = hasConfiguration ? fieldArguments : mockFieldArgumentsReadAfresh(of: declaration, among: fieldArguments, in: world)
		// A node the mock builds for an optional property it promotes, a constant or an instantiator, is bound as the unwrapped
		// type it makes, as every node the mock builds is bound non-optional; the optional receiver takes it through optional
		// promotion.
		let boundProperty = world.property(of: declaration).map { property in
			property.typeDescription.isOptional ? Property(label: property.label, typeDescription: property.typeDescription.unwrapped) : property
		}
		.map { property in
			nameApart.map { Property(label: $0, typeDescription: property.typeDescription) } ?? property
		}
		var record = try builtByInitializerRecord(
			of: declaration,
			variant: variant,
			in: world,
			unavailableProperties: unavailableProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			construction: handWrittenMock,
			typeFunctionReturns: boundProperty?.typeDescription.asInstantiatedTypeSpelledAsDeclared,
			boundProperty: boundProperty,
			argumentsOfOtherValues: fieldArgumentsPassed,
			// A dependency `mock()` takes is read by the name it takes it under, and a wrapper `mock()` binds around a value it
			// takes by the name it binds it under (`mockNamesReadApart(in:)`).
			argumentNamesApart: uncoveredArgumentNames(of: declaration, in: world).merging(wrapperArgumentNames) { uncovered, _ in uncovered },
			alwaysDeclaresFunction: !fieldArguments.isEmpty,
			typesDeclaredEscaping: typesDeclaredEscaping,
			children: receivesBoundAgain.map(\.place) + children,
		)
		// A constant built in a function for its configuration's fields writes `return`, as the walk writes it.
		record.functionAlwaysWritesReturn = !fieldArguments.isEmpty && record.property.propertyType.isConstant
		let isConfiguredForChildren = isConfiguredMockNode(declaration, in: world)
		let isConfigured = isOverriddenByConfiguration(declaration, in: world)
		let slotType = mockOverrideType(of: record, usesHandWrittenMock: handWrittenMock != nil, isConfigured: isConfigured, isSendable: record.isSendable, instantiable: instantiable)
		// A function that takes the places its world's cycles enter is handed its configuration with them, in one argument,
		// by every call, a call that closes a cycle on it included (`NodeRecords+MockCycle.swift`).
		let slot: (value: ValuePath, passedArguments: [PassedArgument])? = if let enteredSlots, takesMockEnteredPlaces(declaration, in: enteredSlots) {
			(
				mockEnteredConfiguration,
				mockArgumentsHanded(to: declaration, labeled: record.property.label, by: world.parents(of: declaration).first?.parent ?? 0, in: world, slots: enteredSlots),
			)
		} else if hasConfiguration {
			mockOverrideSlot(
				of: declaration,
				labeled: record.property.label,
				typed: slotType,
				in: world,
				hasFunction: record.hasFunction,
				handsOverridesToChildren: isConfiguredForChildren,
				isSendable: record.isSendable,
				slots: enteredSlots,
			)
		} else {
			nil
		}
		record.passedArguments = slot?.passedArguments ?? []
		// A wrapper around a call that hands the places entered spells its closure on one line, so a function on a cycle
		// is no longer than the walk's, whose wrapper is handed the function itself.
		record.wrapsCallOnOneLine = enteredSlots.map { takesMockEnteredPlaces(declaration, in: $0) } ?? false
		guard hasConfiguration, let slot else {
			let configuredAfresh = ValuePath.emptyInitialization(mockConfigurationType(of: instantiable))
			for (position, argument) in fieldArgumentsPassed {
				record.argumentValues[position] = mockConfigurationFieldValue(of: argument, readFrom: configuredAfresh)
			}
			return record
		}
		for (position, argument) in fieldArguments {
			record.argumentValues[position] = mockConfigurationFieldValue(of: argument, readFrom: slot.value)
		}
		record.alternatives = [ConstructionAlternative(
			closure: isConfigured ? .member(ReservedName.configurationBuilderPropertyName, of: slot.value) : slot.value,
			bindingName: ReservedName.configurationBuilderPropertyName,
			requiresAbsent: [],
			use: .calledWithConstructionArguments,
			resultWrapper: nil,
		)]
		return record
	}

	/// The default-valued arguments among `fieldArguments` that the construction of `declaration`, which has no
	/// configuration, reads from a configuration of its type built afresh, as the walk reads them where no override
	/// reaches a node (`MockLowering.Walk.constructionArguments`): where the node is built with `init`, each default its
	/// type's hand-written mock declares too, under the same label and type, whose default the configuration holds. A node
	/// built with its hand-written mock leaves every default to the mock's own.
	static func mockFieldArgumentsReadAfresh(
		of declaration: DeclarationID,
		among fieldArguments: [(position: Int, argument: Initializer.Argument)],
		in world: some NodeRecordSources,
	) -> [(position: Int, argument: Initializer.Argument)] {
		let instantiable = world.scope(of: declaration).instantiable
		guard world.construction(of: declaration) != .handWrittenMock, let mockInitializer = instantiable.mockInitializer else { return [] }
		let handWrittenDefaults = ScopeGenerator.DefaultParameter.defaultParameters(of: mockInitializer, dependencies: instantiable.dependencies)
		return fieldArguments.filter { _, argument in
			handWrittenDefaults.contains { $0.isDefault(forParameterLabeled: argument.label, ofType: argument.typeDescription.strippingEscaping) }
		}
	}

	/// The type of the override of `record`'s node, of `instantiable`'s type: its configuration where `isConfigured`, and
	/// otherwise its override closure, as the configuration that holds it spells it
	/// (`MockLowering.ConstantNode.builderClosureType`), `@Sendable` where `isSendable`: a `@Sendable` function captures it.
	static func mockOverrideType(of record: BuiltPlaceRecord, usesHandWrittenMock: Bool, isConfigured: Bool, isSendable: Bool, instantiable: Instantiable) -> TypeDescription {
		if isConfigured {
			mockConfigurationType(of: instantiable)
		} else {
			.unknown(text: "(\(isSendable ? "@Sendable " : "")(\(MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: usesHandWrittenMock).spelled)) -> \(record.property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource))?")
		}
	}

	/// Where `declaration`, a node of a mock root's world built as the property labeled `label`, reads its override, a
	/// value of `type`: the field of its parent's configuration under its label. Every function is declared in the root's
	/// body, where it can capture no other function's argument, so a node with a function of its own is handed the value
	/// as a passed argument named as `mock()`'s own overrides are, which its body reads as the root's reads `mock()`'s; a
	/// node built in place reads the field where it is built. A function that only the root's body calls, and whose body
	/// alone reads the value, captures `mock()`'s own overrides instead and takes no argument, as the walk writes it: its
	/// one parent's configuration is `mock()`'s. A function that hands its overrides to its children keeps the argument,
	/// since a child built under two parents reads one name in both. A `@Sendable` function can neither capture the
	/// overrides nor be handed them, so it reads the local its parent's body binds the value to before it, as the walk
	/// writes it (`NodeRecords+MockSendable.swift`). Each record of a mock root's world takes its override from here, so
	/// that no record spells the path.
	/// - Parameters:
	///   - hasFunction: Whether the node is built in a function of its own.
	///   - handsOverridesToChildren: Whether the value is a configuration whose fields the node's children read.
	///   - isSendable: Whether the node's function is `@Sendable`.
	///   - slots: The slots of the places the world's cycles enter, and which nodes take them; `nil` for a world with no
	///     cycle.
	/// - Returns: The value the node's own construction reads, and what each call of its function hands it.
	static func mockOverrideSlot(
		of declaration: DeclarationID,
		labeled label: String,
		typed type: TypeDescription,
		in world: some NodeRecordSources,
		hasFunction: Bool,
		handsOverridesToChildren: Bool,
		isSendable: Bool,
		slots: MockEnteredSlots?,
	) -> (value: ValuePath, passedArguments: [PassedArgument]) {
		let field = mockConfigurationField(named: label)
		guard hasFunction else { return (field, []) }
		// A `@Sendable` function can neither capture the overrides nor be handed them: its value is read into a local before
		// it (`mockOverridesBindingPlace(of:record:in:slots:)`), which the function captures where the root's body declares both,
		// and is handed elsewhere. A wrapper an actor is sent reads its value so too, since its closure is sent with it.
		guard !isSendable, !isWrapperSentToActor(declaration, in: world) else { return mockSendableOverrideSlot(of: declaration, labeled: label, typed: type, in: world) }
		if !handsOverridesToChildren, world.parents(of: declaration).allSatisfy({ $0.parent == 0 }) {
			return (.member(label, of: .rootDeclaration(ReservedName.mockOverridesParameterName)), [])
		} else {
			// The overrides are not `Sendable`: no call inside a `@Sendable` function hands them on, but those of the `Sendable`
			// form a function that takes the places was handed with them.
			return (
				.passedArgument(ReservedName.mockOverridesParameterName),
				[PassedArgument(parameterName: ReservedName.mockOverridesParameterName, type: type, value: field, staysOutsideSendableFunctions: mockOverridesStayOutsideSendableFunctions(of: declaration, in: slots))],
			)
		}
	}

	/// The override of the node built as the property labeled `label`, as the body that builds the node reads it: the
	/// field under that label of the overrides the body hands its children (`.handedToChildrenByPlacingBody`), which
	/// each body that places the node's record resolves to its own (`mockOverridesOfChildren(of:in:slots:)`): the overrides
	/// its function was handed, which the root's body reads of `mock()`'s own, or the local a `@Sendable` function
	/// captures (`mockPlace(_:record:of:builtBy:in:slots:)`).
	static func mockConfigurationField(named label: String) -> ValuePath {
		.member(label, of: .handedToChildrenByPlacingBody)
	}
}
