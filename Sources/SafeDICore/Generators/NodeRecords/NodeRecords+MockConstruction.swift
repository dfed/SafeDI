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
	/// node stage 1 makes in a production root's world (`refusalsOfBuiltByInitializer(_:in:)`), whose override is the field
	/// of its parent's configuration under the node's own label, discharging nothing and holding each refusal of a node
	/// whose override a later stage reads. A node stage 1 refuses is left unclaimed, so its first refusal is stage 1's.
	static func mockConstructionClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.isMockWorld, refusalsOfBuiltByInitializer(declaration, in: world).isEmpty else { return nil }
		var refusals = [NodeRecordRefusal]()
		let instantiable = world.scope(of: declaration).instantiable
		// An actor's arguments are sent to it, and each node built for one reads its override before its function.
		if instantiable.declarationType == .actorType {
			refusals.append(.mockActor)
		}
		// The root's own such parameters are parameters of `mock()`, which the root's lowering judges
		// (`ScopeGenerator.nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:)`). A type's configuration
		// takes the defaults its hand-written mock declares too, whichever way a node builds it.
		if declaration != 0 {
			let takesDefaultValuedParameter = instantiable.initializer.map { !ScopeGenerator.DefaultParameter.defaultParameters(of: $0, dependencies: instantiable.dependencies).isEmpty } ?? false
			if takesDefaultValuedParameter || instantiable.mockInitializer != nil {
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
		return NodeRecordClaim(kind: .mockConstruction, discharges: [], refusals: refusals)
	}

	/// The record of `declaration`'s place, a node of kind `mockConstruction`: the record stage 1 makes of it, which
	/// first tries the closure that overrides it (`mockOverrideSlot(ofNodeLabeled:typed:hasFunction:)`), called with its
	/// initializer's arguments. A node that builds children is configured: its override is the builder of the
	/// configuration its function is handed, whose fields its children read.
	static func mockConstructionRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		// A mock world that holds a lazily instantiated property is refused (`refusalsOfBuiltByInitializer(_:in:)`), so no
		// receive of this node reads a wrapper's instance.
		var record = try builtByInitializerRecord(of: declaration, variant: variant, in: world, lazilyInstantiatedInstanceProperties: [], typesDeclaredEscaping: typesDeclaredEscaping, children: children)
		let instantiable = world.scope(of: declaration).instantiable
		let isConfigured = !children.isEmpty
		let slotType: TypeDescription = if isConfigured {
			.nested(name: ScopeGenerator.mockConfigurationStructName, parentType: instantiable.concreteInstantiable, generics: [])
		} else {
			// The closure's type as the configuration that holds it spells it (`MockLowering.ConstantNode.builderClosureType`).
			.unknown(text: "((\(MockLowering.BuilderParameters(of: instantiable, usesMockInitializer: false).spelled)) -> \(record.property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asSource))?")
		}
		let slot = mockOverrideSlot(ofNodeLabeled: record.property.label, typed: slotType, hasFunction: record.hasFunction)
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

	/// Where a node of a mock root's world built as the property labeled `label` reads its override, a value of
	/// `type`: the field of its parent's configuration under its label. Every function is declared in the root's body,
	/// where it can capture no other function's argument, so a node with a function of its own is handed the value as a
	/// passed argument named as `mock()`'s own overrides are, which its body reads as the root's reads `mock()`'s; a
	/// node built in place reads the field where it is built. Each record of a mock root's world takes its override from
	/// here, so that no record spells the path.
	/// - Returns: The value the node's own construction reads, and what each call of its function hands it.
	static func mockOverrideSlot(ofNodeLabeled label: String, typed type: TypeDescription, hasFunction: Bool) -> (value: ValuePath, passedArguments: [PassedArgument]) {
		let field = mockConfigurationField(named: label)
		if hasFunction {
			// The overrides are not `Sendable`: no call inside a `@Sendable` function hands them on.
			return (
				.passedArgument(ReservedName.mockOverridesParameterName),
				[PassedArgument(parameterName: ReservedName.mockOverridesParameterName, type: type, value: field, staysOutsideSendableFunctions: true)],
			)
		} else {
			return (field, [])
		}
	}

	/// The override of the node built as the property labeled `label`, as the body that builds the node reads it: the
	/// field under that label of the overrides the body's function was handed, which the root's body reads of `mock()`'s
	/// own.
	static func mockConfigurationField(named label: String) -> ValuePath {
		.member(label.spelledAsMemberDeclarationName, of: .passedArgument(ReservedName.mockOverridesParameterName))
	}
}
