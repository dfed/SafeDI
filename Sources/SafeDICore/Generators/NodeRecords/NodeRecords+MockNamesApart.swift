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

	/// The receives each variant of a mock root's world binds again, by variant, read from the names the mock root binds
	/// apart (`MockRootNames.namesBoundAgain`). A node reads a name apart where no node above it, below the root, declares its
	/// label, as the walk prunes them (`MockLowering.removingRenames(hiddenBy:from:)`): each node's own children and, for a
	/// wrapper, its forwarded properties hide the label from the scopes beneath. A receive named apart is bound again under
	/// its label at the top of the node's builder function, in the order its type declares the receives, as the walk binds
	/// it; it reads the name of its own form, else of its unwrapped form, which a non-optional node or parameter provides.
	///
	/// The walk hands a node the name instead where a receive beneath it reads the label by name
	/// (`ScopeGenerator.receivedBindingNamesPassedByName`): a receive of another form of the label beneath a required one is
	/// hidden, which validation rejects, unless it is received only if available, which keeps the walk
	/// (`refusalOfNamingApart(_:in:)`).
	static func mockReceivesBoundAgain(in world: some NodeRecordSources) -> [[MockReceiveBoundAgain]] {
		var receivesBoundAgain = [[MockReceiveBoundAgain]](repeating: [], count: world.variantCount)
		let namesBoundAgain = world.mockRootNames.namesBoundAgain
		guard !namesBoundAgain.isEmpty || world.mockRootNames.namesUncoveredParameterApart else { return receivesBoundAgain }
		// The names apart each variant's node sees where it is built, by variant.
		var visibleNamesApart = [[String: [TypeDescription: String]]?](repeating: nil, count: world.variantCount)
		visibleNamesApart[0] = namesBoundAgain
		// The root's calls come first and every variant is reached from the root, so a variant's names are set before its calls.
		var variantsToVisit: [VariantID] = [0]
		while let variant = variantsToVisit.popLast() {
			let declaration = world.declaration(of: variant)
			let calls = world.calls(of: variant)
			// The names a node's builder function sees: those above it, less those its own declarations hide.
			let functionNamesApart: [String: [TypeDescription: String]]
			if variant == 0 {
				functionNamesApart = namesBoundAgain
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
				var namesApart = MockLowering.removingRenames(hiddenBy: declarations, from: visibleNamesApart[Int(variant)] ?? [:])
				for property in uncoveredProperties {
					guard let name = world.mockRootNames.uncoveredParameterName(of: property), name != property.label else { continue }
					namesApart[property.label, default: [:]][property.typeDescription] = name
				}
				functionNamesApart = namesApart
				for dependency in instantiable.dependencies where dependency.source.isReceived {
					guard let names = functionNamesApart[dependency.property.label] else { continue }
					// The receive's own form, or the non-optional form the root binds for its optional one.
					if let nameApart = [dependency.property.typeDescription, dependency.property.asUnwrappedProperty.typeDescription].lazy.compactMap({ type in names[type].map { Property(label: $0, typeDescription: type) } }).first {
						receivesBoundAgain[Int(variant)].append(MockReceiveBoundAgain(property: dependency.property, nameApart: nameApart))
					} else if let wrapper = Self.lazyWrapperNamedApart(providingInstanceReadBy: dependency.property, among: names) {
						// A receive by value of a lazy wrapper's instance binds the wrapper named apart again under its label,
						// whose instance its construction reads, as the walk binds it.
						receivesBoundAgain[Int(variant)].append(MockReceiveBoundAgain(property: Property(label: dependency.property.label, typeDescription: wrapper.typeDescription), nameApart: wrapper))
					}
				}
			}
			// A variant's calls all see the names its reads resolve to: a declaration that hides a name apart from one call
			// answers the read otherwise, which makes another variant with a record of its own, so the first call's names
			// stand for every call's.
			for callee in calls where visibleNamesApart[Int(callee)] == nil {
				visibleNamesApart[Int(callee)] = functionNamesApart
				variantsToVisit.append(callee)
			}
		}
		return receivesBoundAgain
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
