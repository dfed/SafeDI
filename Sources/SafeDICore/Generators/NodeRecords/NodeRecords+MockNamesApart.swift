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
	/// name `mock()` binds the value apart under: a parameter of `mock()` or an override of what the tree receives only if
	/// available, named apart from another form of its label (`ScopeGenerator.MockRootParameters`).
	struct MockReceiveBoundAgain: Equatable {
		/// The receive, as the node's type declares it.
		let property: Property
		/// The declaration `mock()` binds apart, which the binding reads.
		let nameApart: Property

		/// The place of the binding, the first statement of the node's builder function, as the mock's walk writes it
		/// (`MockLowering.ConstantNode.receiverBindingLines(indent:)`).
		var place: GeneratedCode {
			let text = "let \(property.label): \(property.typeDescription.asSource) = \(nameApart.label)"
			return .indented(
				.place(PlacePlan(code: .text(text), record: .alias(AliasPlaceRecord(property: property, fulfillingProperty: nameApart, text: text)))),
				by: ScopeGenerator.standardIndent,
			)
		}
	}

	/// The receives each variant of a mock root's world binds again, by variant, read from `namesApart`, the names `mock()`
	/// binds its values named apart under, by label and type. A node reads a name apart where no node above it, below the
	/// root, declares its label, as the walk prunes them (`MockLowering.removingRenames(hiddenBy:from:)`): each node's own
	/// children and, for a wrapper, its forwarded properties hide the label from the scopes beneath. A receive named apart
	/// is bound again under its label at the top of the node's builder function, as the walk binds it.
	///
	/// The walk hands a node the name instead where a receive beneath it reads the label by name
	/// (`ScopeGenerator.receivedBindingNamesPassedByName`): a receive of another form of the label beneath a required one is
	/// hidden, which validation rejects, unless it is received only if available, which no record of a mock root's world
	/// makes yet (`NodeRecordRefusal.onlyIfAvailable`). The kind that makes one hands such a node the name.
	static func mockReceivesBoundAgain(in world: some NodeRecordSources, namesApart: [String: [TypeDescription: String]]) -> [[MockReceiveBoundAgain]] {
		var receivesBoundAgain = [[MockReceiveBoundAgain]](repeating: [], count: world.variantCount)
		guard !namesApart.isEmpty else { return receivesBoundAgain }
		// The names apart each variant's node sees where it is built, by variant.
		var visibleNamesApart = [[String: [TypeDescription: String]]?](repeating: nil, count: world.variantCount)
		visibleNamesApart[0] = namesApart
		// The root's calls come first and every variant is reached from the root, so a variant's names are set before its calls.
		var variantsToVisit: [VariantID] = [0]
		while let variant = variantsToVisit.popLast() {
			let declaration = world.declaration(of: variant)
			let calls = world.calls(of: variant)
			// The names a node's builder function sees: those above it, less those its own declarations hide.
			let functionNamesApart: [String: [TypeDescription: String]]
			if variant == 0 {
				functionNamesApart = namesApart
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
				functionNamesApart = MockLowering.removingRenames(hiddenBy: declarations, from: visibleNamesApart[Int(variant)] ?? [:])
				for dependency in instantiable.dependencies where dependency.source.isReceived {
					// The receive's own form, or the non-optional form `mock()` binds for its optional one.
					guard let names = functionNamesApart[dependency.property.label],
					      let nameApart = [dependency.property.typeDescription, dependency.property.asUnwrappedProperty.typeDescription].lazy.compactMap({ type in names[type].map { Property(label: $0, typeDescription: type) } }).first
					else { continue }
					receivesBoundAgain[Int(variant)].append(MockReceiveBoundAgain(property: dependency.property, nameApart: nameApart))
				}
			}
			// A variant's calls all see the names its reads resolve to: a declaration that hides a name apart from one call
			// answers the read otherwise, which makes another variant (`NodeRecordRefusal.nodeHasSeveralVariants`), so the
			// first call's names stand for every call's.
			for callee in calls where visibleNamesApart[Int(callee)] == nil {
				visibleNamesApart[Int(callee)] = functionNamesApart
				variantsToVisit.append(callee)
			}
		}
		return receivesBoundAgain
	}
}
