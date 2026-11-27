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

/// A call of another module's public mock: a leaf of a mock world whose scope carries the called tier's stored plan
/// (`ConstructionScope.publicMockCall`), built by `__safeDI_mock` with the tier's parameters and the called mock's own
/// `SafeDIOverrides`, read from the enclosing configuration under the node's label, on the line after the mock's guard line
/// (`MockLowering.Walk.publicMockCallNode`). Its subtree is the called module's, so the record holds no children.
///
/// This stage makes a constant or an `Instantiator` of the called type that fills no builder, passes none up, and reads its
/// override from its parent's configuration. Every other call keeps its world on the walk, with the refusal that names its
/// shape.
extension NodeRecords {
	/// The claim of a node that calls another module's public mock: the kind, which makes the stage-1 refusals of a call
	/// (`construction`; and `onlyIfAvailable`, since the leaf receives only if available each parameter its tier omits,
	/// which no call passes), and a refusal of its own for each shape of a call this stage does not make yet. `nil` for any
	/// other node. The called type always has an initializer, since a public mock is never `mockOnly`. Every other stage-1
	/// check still runs on the node, so a call held lazily, erased, `@Sendable` or on a cycle is refused by that check.
	static func publicMockCallClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.construction(of: declaration) == .publicMockCall else { return nil }
		let scope = world.scope(of: declaration)
		guard let call = scope.publicMockCall else { return nil }
		var refusals = [NodeRecordRefusal]()
		var fills = false
		var passesUp = call.passedParameters.contains { $0.builder != nil }
		for argument in scope.holeArguments {
			switch argument {
			case .fill:
				fills = true
			case .passUp:
				passesUp = true
			}
		}
		// A call that fills a builder declares its fills and dispatchers in a builder function of its own.
		if fills {
			refusals.append(.publicMockCallFills)
		}
		// A builder the call passes up is bound again under the label the leaf receives it as.
		if passesUp {
			refusals.append(.publicMockCallPassesUp)
		}
		// A mock that takes no overrides is configured by an override closure, whose arguments read the call's fills.
		if !call.takesOverrides {
			refusals.append(.publicMockCallOverrideClosure)
		}
		// A call the mock promotes to its root reads the caller's value first (`ScopeGenerator.passing(_:orBuilding:)`).
		if isPromotedToMockRoot(declaration, in: world) {
			refusals.append(.publicMockCallPromoted)
		}
		// The leaf receives only if available each parameter its tier omits, which the call never passes, and each `T? = nil`
		// parameter of the tier, which the call passes what the caller's tree holds, or `nil`: the variant's answer, which the
		// record reads (`passedOnlyIfAvailable(_:by:variant:in:)`).
		return NodeRecordClaim(kind: .publicMockCall, discharges: [.construction, .onlyIfAvailable], refusals: refusals)
	}

	/// Whether `declaration` is a child of the mock's root that the root's own type does not declare: a dependency the mock
	/// promotes.
	private static func isPromotedToMockRoot(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		guard let property = world.property(of: declaration),
		      world.parents(of: declaration).contains(where: { $0.parent == 0 })
		else { return false }
		return !world.scope(of: 0).instantiable.dependencies.contains { dependency in
			guard dependency.property == property, case .instantiated = dependency.source else { return false }
			return true
		}
	}

	/// The function of the called tier the call passes its arguments to: the leaf's mock, which takes the tier's
	/// parameters (`publicMockLeafInstantiable`), where it returns the property's type, as the walk chooses it.
	private static func calledMockFunction(of instantiable: Instantiable, builtAs property: Property?) -> Initializer? {
		guard let property else { return nil }
		return instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType) ? instantiable.mockInitializer : instantiable.initializer
	}

	/// Where a call passes a tier's parameter the leaf receives only if available: the nearest declaration of its label,
	/// where every call into the variant binds the read of whether it is handed a value (`ReadChannel.optional`) to a
	/// declaration. A variant's keys leave that answer out (rule 1), so it is read from what each call hands its callee
	/// (`TypeFactsWorld.sources(ofCall:of:)`), followed up through each call that passes its caller's answer through. A
	/// declaration still being built, a lazy or optional form, or no declaration at all (where a mock binds its own
	/// override of the value, which the root's body answers) is a shape this stage does not make. Calls that disagree are
	/// among these, since every call that does not hand a declaration refuses, so none is `nodeHasSeveralVariants`.
	private static func passedOnlyIfAvailable(
		_ dependency: Dependency,
		by declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
	) throws(NodeRecordRefusal) -> ArgumentSource {
		let reads = world.reads(of: declaration)
		guard let position = reads.indices.first(where: {
			let asked = world.read(reads[$0])
			return asked.channel == .optional && world.text(ofLabel: asked.label) == dependency.property.label
		}) else { throw .onlyIfAvailable }
		// Each variant whose callers' answers are still to read, with the position of the read in its run of keys.
		var pending = [(variant: variant, position: position - reads.startIndex)]
		while let (callee, calleePosition) = pending.popLast() {
			var isCalled = false
			for caller in 0..<Int32(world.variantCount) {
				for (edgeIndex, called) in world.calls(of: caller).enumerated() where called == callee {
					let sources = world.sources(ofCall: edgeIndex, of: caller)
					let source = sources[sources.startIndex + calleePosition]
					switch source.kind {
					case .passedThrough:
						pending.append((variant: caller, position: Int(source.payload)))
					case .bound, .none:
						guard source.kind == .bound, world.answer(source.answer).form == .declared else { throw .onlyIfAvailable }
					}
					isCalled = true
				}
			}
			guard isCalled else { throw .onlyIfAvailable }
		}
		return .binding(label: dependency.property.label)
	}

	/// The record of `declaration`'s place, a node of kind `publicMockCall`.
	static func publicMockCallRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		typesDeclaredEscaping: Set<TypeDescription>,
		children _: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let scope = world.scope(of: declaration)
		let instantiable = scope.instantiable
		// A call is a node built as a property, whose leaf takes the called tier's parameters as its mock's
		// (`publicMockLeafInstantiable`).
		guard let property = world.property(of: declaration),
		      let call = scope.publicMockCall,
		      let initializer = calledMockFunction(of: instantiable, builtAs: property)
		else { throw NodeRecordRefusal.construction }
		let calledType = instantiable.concreteInstantiable
		var arguments = [PlaceRead]()
		for (argument, dependency) in try initializer.createInitializerArguments(given: instantiable.dependencies) {
			let source = dependency.source == .received(onlyIfAvailable: true)
				? try passedOnlyIfAvailable(dependency, by: declaration, variant: variant, in: world)
				: argument.source
			arguments.append(PlaceRead(argumentLabel: argument.label, label: dependency.property.label, property: dependency.property, source: source))
		}
		// The called mock's own overrides: the enclosing configuration's field under the node's label, which the record never
		// spells (`mockConfigurationField(named:)`).
		let isInstantiator = world.kind(of: declaration) == .instantiator
		let overridesType = TypeDescription.nested(name: ReservedName.mockOverridesTypeName, parentType: calledType, generics: [])
		let overridesProperty = Property(label: ReservedName.mockOverridesParameterName, typeDescription: overridesType)
		// The called mock's overrides are its own: the node hands no configuration to children, since it has none.
		let slot = mockOverrideSlot(of: declaration, labeled: property.label, typed: overridesType, in: world, hasFunction: isInstantiator, handsOverridesToChildren: false, isSendable: false)
		let argumentValues = [arguments.count: slot.value]
		arguments.append(PlaceRead(argumentLabel: overridesProperty.label, label: overridesProperty.label, property: overridesProperty, source: .binding(label: overridesProperty.label)))
		var record = BuiltPlaceRecord(
			property: property,
			isErased: false,
			concreteType: calledType,
			isExtension: false,
			target: .publicMockCall(calledType, guard: CallGuard(calledType: calledType, guardTypeName: call.guardTypeName, comment: call.comment)),
			arguments: arguments,
			forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			cycleParameters: [],
			callCycleArguments: [],
			functionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			isSendable: false,
			typesDeclaredEscaping: typesDeclaredEscaping.union(call.typesDeclaredEscaping),
			lineEnd: "",
			// An `Instantiator` declares the builder function it holds; a constant call is made where it is bound.
			hasFunction: isInstantiator,
			children: [],
			node: PlanNode(),
		)
		record.sharingFields = PlaceSharingFields(passedArguments: slot.passedArguments, constructionValue: nil, alternatives: [], argumentValues: argumentValues)
		return record
	}
}
