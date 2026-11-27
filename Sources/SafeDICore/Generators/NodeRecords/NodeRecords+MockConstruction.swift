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
	/// node stage 1 makes in a production root's world (`refusalsOfBuiltByInitializer(_:in:)`) and for one its type's
	/// hand-written mock builds, whose override is the field of its parent's configuration under the node's own label,
	/// holding each refusal of a node whose override a later stage reads. A node stage 1 refuses for anything this kind
	/// does not make is left unclaimed, so its first refusal is stage 1's.
	static func mockConstructionClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.isMockWorld else { return nil }
		// A hand-written mock builds its type with or without an initializer: a fake has none.
		let buildsWithHandWrittenMock = world.construction(of: declaration) == .handWrittenMock
		var discharges: Set<NodeRecordRefusal> = buildsWithHandWrittenMock ? [.construction, .noInitializer] : []
		discharges.formUnion(mockOnlyIfAvailableDischarges(of: declaration))
		guard refusalsOfBuiltByInitializer(declaration, in: world).allSatisfy(discharges.contains) else { return nil }
		var refusals = [NodeRecordRefusal]()
		let instantiable = world.scope(of: declaration).instantiable
		// An actor's arguments are sent to it, and each node built for one reads its override before its function.
		if instantiable.declarationType == .actorType {
			refusals.append(.mockActor)
		}
		// The root's own such parameters are parameters of `mock()`, which the root's lowering judges
		// (`ScopeGenerator.nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:)`). A type's configuration takes the
		// defaults of its initializer and of its hand-written mock, whichever of the two builds a node.
		if declaration != 0 {
			let (construction, otherConstruction) = buildsWithHandWrittenMock ? (instantiable.mockInitializer, instantiable.initializer) : (instantiable.initializer, instantiable.mockInitializer)
			let callPassesValueNoDependencyFulfills = construction.map { takesValueNoDependencyFulfills($0, given: instantiable.dependencies) } ?? false
			let otherConstructionDeclaresDefault = otherConstruction.map { !ScopeGenerator.DefaultParameter.defaultParameters(of: $0, dependencies: instantiable.dependencies).isEmpty } ?? false
			if callPassesValueNoDependencyFulfills || otherConstructionDeclaresDefault {
				refusals.append(.mockDefaultValuedParameter)
			}
		}
		// Two children of one label are named apart, so neither reads the field of its own label: only a mock root, which
		// promotes each form of a label its tree receives, builds two.
		var labels = Set<String>()
		for child in world.edges(from: declaration) where !labels.insert(world.property(of: child)?.label ?? "").inserted {
			refusals.append(.mockOverrideNotParentField)
			break
		}
		return NodeRecordClaim(kind: .mockConstruction, discharges: discharges, refusals: refusals)
	}

	/// Whether a call of `construction` a mock writes passes a value none of `dependencies` fulfills, which the node's
	/// configuration holds: every argument but one a dependency fulfills and one the call leaves to its default
	/// (`Initializer.Argument.isLeftToItsDefault`, which a dependency's label is never left to).
	private static func takesValueNoDependencyFulfills(_ construction: Initializer, given dependencies: [Dependency]) -> Bool {
		construction.arguments.contains { argument in
			!dependencies.contains(where: argument.isFulfilled(by:))
				&& !(argument.isLeftToItsDefault && !dependencies.contains { $0.property.label == argument.innerLabel })
		}
	}

	/// The record of `declaration`'s place, a node of kind `mockConstruction`: the record stage 1 makes of it, built with
	/// its type's hand-written mock where the world says so (`TypeFactsConstruction.handWrittenMock`), which first tries
	/// the closure that overrides it (`mockOverrideSlot(of:labeled:typed:in:hasFunction:handsOverridesToChildren:isSendable:)`),
	/// called with its
	/// construction's arguments. A node that builds children is configured: its override is the builder of the
	/// configuration its function is handed, whose fields its children read. The closure of a node that is not
	/// configured returns the property's type, so every node's function does, as the walk's does.
	static func mockConstructionRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		unavailableProperties: Set<Property>,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let instantiable = world.scope(of: declaration).instantiable
		let handWrittenMock: (function: Initializer, target: ConstructionTarget)? = if world.construction(of: declaration) == .handWrittenMock, let mockInitializer = instantiable.mockInitializer {
			(mockInitializer, .mock(instantiable.concreteInstantiable, name: instantiable.customMockName ?? InstantiableVisitor.mockMethodName))
		} else {
			nil
		}
		// A mock world that holds a lazily instantiated property is refused (`refusalsOfBuiltByInitializer(_:in:)`), so no
		// receive of this node reads a wrapper's instance.
		// A constant the mock builds for an optional property it promotes is bound as the unwrapped type its function returns,
		// as every node the mock builds is bound non-optional; the optional receiver takes it through optional promotion.
		let boundProperty = world.property(of: declaration).map { property in
			property.propertyType == .constant && property.typeDescription.isOptional ? Property(label: property.label, typeDescription: property.typeDescription.unwrapped) : property
		}
		var record = try builtByInitializerRecord(
			of: declaration,
			variant: variant,
			in: world,
			unavailableProperties: unavailableProperties,
			lazilyInstantiatedInstanceProperties: [],
			construction: handWrittenMock,
			typeFunctionReturns: boundProperty?.typeDescription.asInstantiatedTypeSpelledAsDeclared,
			boundProperty: boundProperty,
			typesDeclaredEscaping: typesDeclaredEscaping,
			children: children,
		)
		let isConfigured = !children.isEmpty
		let slotType: TypeDescription = if isConfigured {
			.nested(name: ScopeGenerator.mockConfigurationStructName, parentType: instantiable.concreteInstantiable, generics: [])
		} else {
			// The closure's type as the configuration that holds it spells it (`MockLowering.ConstantNode.builderClosureType`).
			.unknown(text: "((\(MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: handWrittenMock != nil).spelled)) -> \(record.property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource))?")
		}
		let slot = mockOverrideSlot(
			of: declaration,
			labeled: record.property.label,
			typed: slotType,
			in: world,
			hasFunction: record.hasFunction,
			handsOverridesToChildren: isConfigured,
			isSendable: record.isSendable,
		)
		record.passedArguments = slot.passedArguments
		record.alternatives = [ConstructionAlternative(
			closure: isConfigured ? .member(ReservedName.configurationBuilderPropertyName, of: slot.value) : slot.value,
			bindingName: ReservedName.configurationBuilderPropertyName,
			requiresAbsent: [],
			use: .calledWithConstructionArguments,
			resultWrapper: nil,
		)]
		return record
	}

	/// Where `declaration`, a node of a mock root's world built as the property labeled `label`, reads its override, a
	/// value of `type`: the field of its parent's configuration under its label. Every function is declared in the root's
	/// body, where it can capture no other function's argument, so a node with a function of its own is handed the value
	/// as a passed argument named as `mock()`'s own overrides are, which its body reads as the root's reads `mock()`'s; a
	/// node built in place reads the field where it is built. A function that only the root's body calls, and whose body
	/// alone reads the value, captures `mock()`'s own overrides instead and takes no argument, as the walk writes it: its
	/// one parent's configuration is `mock()`'s. A function that hands its overrides to its children keeps the argument,
	/// since a child built under two parents reads one name in both, and so does a `@Sendable` function, which cannot
	/// capture the overrides. Each record of a mock root's world takes its override from here, so that no record spells
	/// the path.
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
		let field = mockConfigurationField(named: label)
		guard hasFunction else { return (field, []) }
		if !handsOverridesToChildren, !isSendable, world.parents(of: declaration).allSatisfy({ $0.parent == 0 }) {
			return (.member(label.spelledAsMemberDeclarationName, of: .rootDeclaration(ReservedName.mockOverridesParameterName)), [])
		} else {
			// The overrides are not `Sendable`: no call inside a `@Sendable` function hands them on.
			return (
				.passedArgument(ReservedName.mockOverridesParameterName),
				[PassedArgument(parameterName: ReservedName.mockOverridesParameterName, type: type, value: field, staysOutsideSendableFunctions: true)],
			)
		}
	}

	/// The override of the node built as the property labeled `label`, as the body that builds the node reads it: the
	/// field under that label of the overrides the body's function was handed, which the root's body reads of `mock()`'s
	/// own.
	static func mockConfigurationField(named label: String) -> ValuePath {
		.member(label.spelledAsMemberDeclarationName, of: .passedArgument(ReservedName.mockOverridesParameterName))
	}
}
