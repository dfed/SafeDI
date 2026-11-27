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
	/// The claim of `declaration` in a mock root's world, and `nil` in a production root's: of kind `mockConstruction`, for a
	/// node `builtByInitializer` makes in a production root's world (`refusalsOfBuiltByInitializer(_:in:)`) and for one its
	/// type's hand-written mock builds, whose override is the field of its parent's configuration under the node's own
	/// label, holding each refusal of a node whose override it does not read yet. A node `builtByInitializer` refuses for
	/// anything a mock kind does not make is left unclaimed, so its first refusal is its own. Each mock kind adds its term
	/// to `discharges`, the refusals of `builtByInitializer` that the node its record makes no longer has, and the node is
	/// of the kind whose term discharged one.
	static func mockConstructionClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.isMockWorld else { return nil }
		// A property nothing fulfills builds nothing, so it is no construction (`NodeRecords+MockUnavailableDependency.swift`).
		guard !world.scope(of: declaration).isUnavailableDependency else { return mockUnavailableDependencyClaim(of: declaration, in: world) }
		// A rename is a node of its own kind, which reads no override.
		let renameClaim = mockRenameClaim(of: declaration, in: world)
		guard renameClaim == nil else { return renameClaim }
		// A hand-written mock builds its type with or without an initializer: a fake has none.
		let buildsWithHandWrittenMock = world.construction(of: declaration) == .handWrittenMock
		let erasedDischarges = mockErasedDischarges(of: declaration, in: world)
		let lazyDischarges = mockLazyDischarges(of: declaration, in: world)
		let rename = mockRenameDischargesAndRefusals(of: declaration, in: world)
		var discharges: Set<NodeRecordRefusal> = buildsWithHandWrittenMock ? [.construction, .noInitializer] : []
		discharges.formUnion(mockOnlyIfAvailableDischarges(of: declaration))
		discharges.formUnion(erasedDischarges)
		discharges.formUnion(lazyDischarges)
		discharges.formUnion(rename.discharges)
		// A node built in a `@Sendable` function of its own reads its override from a local bound before the function
		// (`NodeRecords+MockSendable.swift`).
		discharges.formUnion(mockSendableDischarges(of: declaration, in: world))
		guard refusalsOfBuiltByInitializer(declaration, in: world).allSatisfy(discharges.contains) else { return nil }
		// A `Sendable` wrapper erased to its property's type is made as `mockErased` makes an erased node:
		// `builtByInitializer` refuses it as `sendable` alone. An erased `LazilyInstantiated`'s override returns the erased
		// type, as an erased node's does, so its record is the erased kind's too
		// (`mockErasedRecord(of:variant:in:unavailableProperties:lazilyInstantiatedInstanceProperties:receivesBoundAgain:typesDeclaredEscaping:children:)`).
		let kind: NodeRecordKind = erasedDischarges.isEmpty && !isErasedSendableWrapper(declaration, in: world) && (lazyDischarges.isEmpty || !world.isErased(declaration)) ? .mockConstruction : .mockErased
		var refusals = rename.refusals + mockSendableRefusals(of: declaration, in: world)
		let instantiable = world.scope(of: declaration).instantiable
		// An actor is claimed as any node is. The closure that overrides it takes each argument `sending`
		// (`MockLowering.BuilderParameters`), and what it is sent is built by functions that are each handed their
		// configuration, the `Sendable` form beneath an actor (`ScopeGenerator.sendableConfigurationTypeNames(ofMockRootOf:)`),
		// so none captures `mock()`'s overrides, as the walk's read of them into a local before each function keeps its own
		// from doing.
		// The root's own default-valued parameters are parameters of `mock()`, which the root's lowering judges
		// (`ScopeGenerator.nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:sendableConfigurationTypeNames:rootNames:outerDeclarations:)`).
		if declaration != 0, mockConstructionFunction(of: declaration, in: world).map({ passesValueNoRecordMakes($0, given: instantiable.dependencies) }) ?? false {
			refusals.append(.mockDefaultValuedParameter)
		}
		// A child the mock root names apart reads the root's field under that name, where every read of its label is one
		// the records make (`NodeRecords+MockOverrideNotParentField.swift`).
		if let refusal = refusalOfNamingApart(declaration, in: world) {
			refusals.append(refusal)
		}
		return NodeRecordClaim(kind: kind, discharges: discharges, refusals: refusals)
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

	/// The record of `declaration`'s place, a node of kind `mockConstruction`: the record `builtByInitializer` makes of it, built with
	/// its type's hand-written mock where the world says so (`TypeFactsConstruction.handWrittenMock`), which first tries
	/// the closure that overrides it (`mockOverrideSlot(of:labeled:typed:in:hasFunction:handsOverridesToChildren:isSendable:)`),
	/// called with its construction's arguments. A node that builds a child with an override of its own (neither a rename
	/// nor a property nothing fulfills), or whose construction takes a field of its configuration
	/// (`mockConfigurationFieldArguments(of:in:)`), is configured: its override is the builder of the configuration its
	/// function is handed, whose fields its children and its own construction read, a field of an `@autoclosure` parameter
	/// called once where the node is built. A rename reads no override, and a property nothing fulfills reads one the root
	/// hands down beside the node's, so a node whose children are all of those two kinds and whose construction takes no
	/// field is not configured. The closure of a node that is not configured returns the property's type, so every node's
	/// function does, as the walk's does.
	static func mockConstructionRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		receivesBoundAgain: [MockReceiveBoundAgain],
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let instantiable = world.scope(of: declaration).instantiable
		// A child of the root's level the mock root names apart is bound, and overridden, under that name, and a type that
		// receives a value named apart binds it again under its label before its own children (`mockReceivesBoundAgain(in:)`).
		let nameApart = world.edges(from: 0).contains(declaration) ? world.property(of: declaration).flatMap(world.mockRootNames.nameApart(of:)) : nil
		let handWrittenMock: (function: Initializer, target: ConstructionTarget)? = if world.construction(of: declaration) == .handWrittenMock, let mockInitializer = instantiable.mockInitializer {
			(mockInitializer, .mock(instantiable.concreteInstantiable, name: instantiable.customMockName ?? InstantiableVisitor.mockMethodName))
		} else {
			nil
		}
		let fieldArguments = mockConfigurationFieldArguments(of: declaration, in: world)
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
			argumentsOfOtherValues: fieldArguments,
			alwaysDeclaresFunction: !fieldArguments.isEmpty,
			typesDeclaredEscaping: typesDeclaredEscaping,
			children: receivesBoundAgain.map(\.place) + children,
		)
		// A constant built in a function for its configuration's fields writes `return`, as the walk writes it.
		record.functionAlwaysWritesReturn = !fieldArguments.isEmpty && record.property.propertyType.isConstant
		let isConfiguredForChildren = isConfiguredMockNode(declaration, in: world)
		// A property nothing fulfills is a child with no override of its own, as a rename is, so neither makes its type a
		// configuration; its function is still handed the overrides, beside which it takes that property’s.
		let buildsChildWithOverride = world.edges(from: declaration).contains { world.kind(of: $0) != .alias && !world.scope(of: $0).isUnavailableDependency }
		let isConfigured = buildsChildWithOverride || !fieldArguments.isEmpty
		let slotType = mockOverrideType(of: record, usesHandWrittenMock: handWrittenMock != nil, isConfigured: isConfigured, instantiable: instantiable)
		let slot = mockOverrideSlot(
			of: declaration,
			labeled: record.property.label,
			typed: slotType,
			in: world,
			hasFunction: record.hasFunction,
			handsOverridesToChildren: isConfiguredForChildren,
			isSendable: record.isSendable,
		)
		// The override `mock()` takes of a property nothing fulfills is handed down to the function of the type that
		// declares the property (`NodeRecords+MockUnavailableDependency.swift`).
		record.passedArguments = try slot.passedArguments + unavailableDependencyOverrideArguments(of: declaration, in: world, children: children, isSendable: record.isSendable)
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

	/// The type of the override of `record`'s node, of `instantiable`'s type: its configuration where `isConfigured`, and
	/// otherwise its override closure, as the configuration that holds it spells it
	/// (`MockLowering.ConstantNode.builderClosureType`), `@Sendable` where a `@Sendable` function captures it.
	static func mockOverrideType(of record: BuiltPlaceRecord, usesHandWrittenMock: Bool, isConfigured: Bool, instantiable: Instantiable) -> TypeDescription {
		if isConfigured {
			mockConfigurationType(of: instantiable)
		} else {
			.unknown(text: "(\(record.isSendable ? "@Sendable " : "")(\(MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: usesHandWrittenMock).spelled)) -> \(record.property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource))?")
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
	/// - Returns: The value the node's own construction reads, and what each call of its function hands it.
	static func mockOverrideSlot(
		of declaration: DeclarationID,
		labeled label: String,
		typed type: TypeDescription,
		in world: some NodeRecordSources,
		hasFunction: Bool,
		handsOverridesToChildren: Bool,
		isSendable: Bool,
	) -> (value: ValuePath, passedArguments: [PassedArgument]) {
		let field = mockConfigurationField(of: declaration, named: label, in: world)
		guard hasFunction else { return (field, []) }
		// A `@Sendable` function can neither capture the overrides nor be handed them: its value is read into a local before
		// it (`mockOverridesBindingPlace(of:record:in:)`), which the function captures where the root's body declares both,
		// and is handed elsewhere.
		guard !isSendable else { return mockSendableOverrideSlot(of: declaration, labeled: label, typed: type, in: world, handsOverridesToChildren: handsOverridesToChildren) }
		if !handsOverridesToChildren, world.parents(of: declaration).allSatisfy({ $0.parent == 0 }) {
			return (.member(label.spelledAsMemberDeclarationName, of: .rootDeclaration(ReservedName.mockOverridesParameterName)), [])
		} else {
			// The overrides are not `Sendable`: no call inside a `@Sendable` function hands them on.
			return (
				.passedArgument(ReservedName.mockOverridesParameterName),
				[PassedArgument(parameterName: ReservedName.mockOverridesParameterName, type: type, value: field, staysOutsideSendableFunctions: true)],
			)
		}
	}

	/// The override of `declaration`, the node built as the property labeled `label`, as the body that builds the node
	/// reads it: the field under that label of the overrides the body's function was handed, which the root's body reads
	/// of `mock()`'s own, and a `@Sendable` function's of the local it captures (`mockOverridesOfChildren(of:in:)`). A
	/// node with more than one parent has no parent built in a `@Sendable` function (`mockSendableRefusals(of:in:)`), so
	/// its first parent's is every parent's.
	static func mockConfigurationField(of declaration: DeclarationID, named label: String, in world: some NodeRecordSources) -> ValuePath {
		.member(label.spelledAsMemberDeclarationName, of: mockOverridesOfChildren(of: world.parents(of: declaration).first?.parent ?? 0, in: world))
	}
}
