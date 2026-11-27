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
	/// A receive a node of a mock root's world binds again under its label at the top of its builder function, from the
	/// name the mock root binds the value apart under (`MockRootNames.namesBoundAgain`): a child of the root's level, a
	/// parameter of `mock()` or an override of what the tree receives only if available, each named apart from another form
	/// of its label, or a builder a call of another module's public mock passes up, which `mock()` binds under its internal
	/// name.
	struct MockReceiveBoundAgain: Equatable {
		/// The receive, as the node's type declares it.
		let property: Property
		/// The declaration the mock root binds apart, which the binding reads.
		let nameApart: Property

		/// The place of the binding, the first statement of the node's builder function, as the mock's walk writes it
		/// (`MockLowering.ConstantNode.receiverBindingLines(indent:)`), read as a rename of the name is, so the function is
		/// handed the name as it is any value it reads.
		var place: GeneratedCode {
			// A builder a call passes up is received `@escaping`, which no binding spells.
			let type = property.typeDescription.strippingEscaping
			let text = "let \(property.label): \(type.asSource) = \(nameApart.label)"
			let record = AliasPlaceRecord(
				property: Property(label: property.label, typeDescription: type),
				fulfillingProperty: Property(label: nameApart.label, typeDescription: type),
				text: text,
			)
			return .indented(
				.place(PlacePlan(code: .text(text), record: .alias(record))),
				by: ScopeGenerator.standardIndent,
			)
		}
	}

	/// What each variant of a mock root's world reads under a name the mock root binds apart, by variant.
	struct MockNamesReadApart {
		/// The receives each variant binds again under their labels at the top of its builder function.
		var receivesBoundAgain: [[MockReceiveBoundAgain]]
		/// The name each variant's construction passes a receive of a lazy wrapper `mock()` makes of an instance it takes
		/// (`MockRootNames.wrapperBindingName(of:)`), by the receive's property, as the walk passes it by name, never bound
		/// again under its label, which would hide the instance from the receives by value beside it.
		var wrapperArgumentNames: [[Property: String]]
		/// The variants that are renames of such a wrapper, which the walk passes the wrapper's name and no record writes yet.
		var renamesOfWrappersPassedByName: Set<VariantID>
	}

	/// What each variant of a mock root's world reads under a name the mock root binds apart, read from the names the mock
	/// root binds apart (`MockRootNames.namesBoundAgain`) and the lazy wrappers `mock()` makes of the instances it takes
	/// (`MockRootNames.wrapperBindingNames`). A node reads a name apart where no node above it, below the root, declares its
	/// label, as the walk prunes them (`MockLowering.removingRenames(hiddenBy:from:)`): each node's own children and, for a
	/// wrapper, its forwarded properties hide the label from the scopes beneath. A receive named apart is bound again under
	/// its label at the top of the node's builder function, in the order its type declares the receives, as the walk binds
	/// it; it reads the name of its own form, else of its unwrapped form, which a non-optional node or parameter provides. A
	/// receive of a wrapper `mock()` makes is passed the wrapper's name instead, as the walk passes it.
	///
	/// The walk hands a node the name instead where a receive beneath it reads the label by name
	/// (`ScopeGenerator.receivedBindingNamesPassedByName`): a receive of another form of the label beneath a required one is
	/// hidden, which validation rejects, unless it is received only if available, which keeps the walk
	/// (`refusalOfNamingApart(_:in:)`).
	static func mockNamesReadApart(in world: some NodeRecordSources) -> MockNamesReadApart {
		var namesRead = MockNamesReadApart(
			receivesBoundAgain: [[MockReceiveBoundAgain]](repeating: [], count: world.variantCount),
			wrapperArgumentNames: [[Property: String]](repeating: [:], count: world.variantCount),
			renamesOfWrappersPassedByName: [],
		)
		let namesBoundAgain = world.mockRootNames.namesBoundAgain
		let wrapperBindingNames = world.mockRootNames.wrapperBindingNames
		guard !namesBoundAgain.isEmpty || !wrapperBindingNames.isEmpty || world.mockRootNames.namesUncoveredParameterApart else { return namesRead }
		// The names apart and the wrappers' names each variant's node sees where it is built, by variant.
		var visibleNames = [(namesApart: [String: [TypeDescription: String]], wrapperNames: [String: [TypeDescription: String]])?](repeating: nil, count: world.variantCount)
		visibleNames[0] = (namesBoundAgain, wrapperBindingNames)
		// The root's calls come first and every variant is reached from the root, so a variant's names are set before its calls.
		var variantsToVisit: [VariantID] = [0]
		while let variant = variantsToVisit.popLast() {
			let declaration = world.declaration(of: variant)
			let calls = world.calls(of: variant)
			// The names a node's builder function sees: those above it, less those its own declarations hide.
			let functionNames: (namesApart: [String: [TypeDescription: String]], wrapperNames: [String: [TypeDescription: String]])
			if variant == 0 {
				functionNames = (namesBoundAgain, wrapperBindingNames)
			} else if world.kind(of: declaration) == .alias {
				// A rename is a leaf, which reads its fulfilling property where its scope binds it.
				functionNames = ([:], [:])
				let visible = visibleNames[Int(variant)]?.wrapperNames ?? [:]
				if let fulfillingProperty = renamedProperty(of: declaration, in: world), Self.name(of: fulfillingProperty, among: visible) != nil {
					namesRead.renamesOfWrappersPassedByName.insert(variant)
				}
			} else {
				let instantiable = world.scope(of: declaration).instantiable
				let isWrapper = switch world.kind(of: declaration) {
				case .instantiator, .erasedInstantiator, .lazy, .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
					true
				case .constant, .alias, .hole:
					false
				}
				var declarations = calls.compactMap { world.property(of: world.declaration(of: $0)) }
				if isWrapper {
					declarations += instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property)
				}
				// A dependency the node's type instantiates that the mock cannot build is declared by the node too, and the
				// receives beneath read the parameter `mock()` takes for it, under its name apart, as the walk routes them
				// (`MockLowering.routeReceives(of:toParametersNamed:in:)`).
				let uncoveredProperties = world.scope(of: declaration).instantiatedDependenciesNotGenerated.map(\.property)
				declarations += uncoveredProperties
				let visible = visibleNames[Int(variant)] ?? ([:], [:])
				var namesApart = MockLowering.removingRenames(hiddenBy: declarations, from: visible.namesApart)
				for property in uncoveredProperties {
					guard let name = world.mockRootNames.uncoveredParameterName(of: property), name != property.label else { continue }
					namesApart[property.label, default: [:]][property.typeDescription] = name
				}
				let wrapperNames = MockLowering.removingRenames(hiddenBy: declarations, from: visible.wrapperNames)
				functionNames = (namesApart, wrapperNames)
				for dependency in instantiable.dependencies where dependency.source.isReceived {
					if let name = Self.name(of: dependency.property, among: wrapperNames) {
						// A receive of a wrapper `mock()` makes of an instance it takes is passed the wrapper by name.
						namesRead.wrapperArgumentNames[Int(variant)][dependency.property] = name
						continue
					}
					guard let names = namesApart[dependency.property.label] else { continue }
					// The receive's own form, or the non-optional form the root binds for its optional one.
					if let nameApart = [dependency.property.typeDescription, dependency.property.asUnwrappedProperty.typeDescription].lazy.compactMap({ type in names[type].map { Property(label: $0, typeDescription: type) } }).first {
						namesRead.receivesBoundAgain[Int(variant)].append(MockReceiveBoundAgain(property: dependency.property, nameApart: nameApart))
					} else if let wrapper = Self.lazyWrapperNamedApart(providingInstanceReadBy: dependency.property, among: names) {
						// A receive by value of a lazy wrapper's instance binds the wrapper named apart again under its label,
						// whose instance its construction reads, as the walk binds it.
						namesRead.receivesBoundAgain[Int(variant)].append(MockReceiveBoundAgain(property: Property(label: dependency.property.label, typeDescription: wrapper.typeDescription), nameApart: wrapper))
					}
				}
			}
			// A variant's calls all see the names its reads resolve to: a declaration that hides a name apart from one call
			// answers the read otherwise, which makes another variant (`NodeRecordRefusal.nodeHasSeveralVariants`), so the
			// first call's names stand for every call's.
			for callee in calls where visibleNames[Int(callee)] == nil {
				visibleNames[Int(callee)] = functionNames
				variantsToVisit.append(callee)
			}
		}
		return namesRead
	}

	/// The name among `names`, by label and then type, of `property` or of its unwrapped form, which a non-optional wrapper
	/// gives an optional receive of it; `nil` where neither is named.
	private static func name(of property: Property, among names: [String: [TypeDescription: String]]) -> String? {
		names[property.label].flatMap { $0[property.typeDescription] ?? $0[property.asUnwrappedProperty.typeDescription] }
	}

	/// The property the rename `declaration` reads, as its scope declares it.
	private static func renamedProperty(of declaration: DeclarationID, in world: some NodeRecordSources) -> Property? {
		world.scope(of: declaration).propertiesToGenerate.lazy.compactMap { propertyToGenerate in
			if case let .aliased(property, fulfillingProperty, _, _, _) = propertyToGenerate, property == world.property(of: declaration) {
				fulfillingProperty
			} else {
				nil
			}
		}.first
	}

	/// The lazy wrapper among `names`, the names apart of one label by type, whose instance a receive of `property` by value
	/// reads, a `LazilyInstantiated` before a `SendableLazilyInstantiated`, as the walk looks it up, and `nil` where none is
	/// named apart.
	private static func lazyWrapperNamedApart(providingInstanceReadBy property: Property, among names: [TypeDescription: String]) -> Property? {
		let instanceType = property.typeDescription.unwrapped
		return [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
			.lazy
			.map { TypeDescription.simple(name: $0, generics: [instanceType]) }
			.compactMap { wrapper in names[wrapper].map { Property(label: $0, typeDescription: wrapper) } }
			.first
	}
}
