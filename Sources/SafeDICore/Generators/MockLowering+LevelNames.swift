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

/// The names a mock's level binds its nodes under, which the walk reads off its generators and node records off the
/// declarations of the mock's world, so both name the mock root's level from one rule.
extension MockLowering {
	/// A node of one level, as its binding name depends on it.
	enum LevelNode: Equatable {
		/// A property node: one built, or one instantiated only if available that nothing fulfills.
		case property(Property, isUnavailableDependency: Bool)
		/// A rename of a property.
		case alias(Property)
		/// A node that binds no property.
		case other
	}

	/// The names the mock root's level binds into it, which name its nodes apart.
	struct RootLevelNamesTaken: Equatable {
		/// The parameters of `mock()` that keep their labels, which the level's property nodes are named apart from.
		let parametersKeepingTheirLabels: [Property]
		/// The labels of the flat received parameters of `mock()`.
		let flatReceivedLabels: Set<String>
		/// The names of the overrides `mock()` binds before its nodes.
		let overrideNames: Set<String>
		/// The labels `mock()` takes and the names of the wrappers it binds.
		let rootLabels: Set<String>
		/// The names the builder functions `mock()` takes declare.
		let namesDeclaredInBuilderFunctions: Set<String>
	}

	/// The names the mock root's level binds: what its nodes read, and what the root's own bindings are named apart from.
	struct RootLevelNames: Equatable {
		/// The names the root binds apart from their labels, by label and then type: what `mock()`'s signature names apart,
		/// with each node of the level the level names apart.
		var namesApart: [String: [TypeDescription: String]]
		/// The names the level's property nodes are bound under, which a rebinding of the mocked type's own receive would
		/// redeclare.
		var propertyNodeBindingNames: Set<String>
		/// The names apart the level's aliases are bound under.
		var aliasBindingNamesApart: Set<String>
	}

	/// What the mock root binds beside its nodes and passes the mocked type, from the names its level binds.
	struct RootBindings {
		/// The name the mocked type is passed each of its dependencies under where it is not the dependency's label.
		let renames: [String: [TypeDescription: String]]
		/// The bindings again, under their labels, of the mocked type's own receives `mock()` takes named apart.
		let receiverBindingLines: [String]
		/// The properties `receiverBindingLines` bind.
		let receivesBoundAgain: [Property]
		/// Whether each name in `renames` is one a node, an alias, a parameter, an override or a wrapper binds.
		let namesAreBindings: Bool
	}

	/// The name each node of one level, `nodes` in generation order, is bound under, `nil` for a node that is no property
	/// node: its label, or, where property nodes of the level, or `parametersKeepingTheirLabels`, share it, a name apart,
	/// as `ScopeGenerator.disambiguatePropertyLabels(forProperties:)` names it.
	static func levelBindingNames(of nodes: [LevelNode], besideParametersKeepingTheirLabels parametersKeepingTheirLabels: [Property]) -> [String?] {
		let propertyNodes: [Property?] = nodes.map { node in
			guard case let .property(property, _) = node else { return nil }
			return property
		}
		var seenLabels = Set<String>()
		var collidingLabels = Set<String>()
		for case let property? in propertyNodes where !seenLabels.insert(property.label).inserted {
			collidingLabels.insert(property.label)
		}
		let parameterLabels = Set(parametersKeepingTheirLabels.map(\.label))
		collidingLabels.formUnion(parameterLabels.intersection(seenLabels))
		guard !collidingLabels.isEmpty else { return propertyNodes.map { $0?.label } }
		let collidingProperties = propertyNodes.compactMap { property in property.flatMap { collidingLabels.contains($0.label) ? $0 : nil } }
		let names = ScopeGenerator.identifierSafeNames(
			for: collidingProperties.map { property in
				let instantiatedType = property.typeDescription.asInstantiatedType
				return (label: property.label, suffixTypes: [instantiatedType.simplified, instantiatedType, property.typeDescription])
			},
			besideEntriesKeepingTheirNames: parametersKeepingTheirLabels.compactMap { parameter in
				guard collidingLabels.contains(parameter.label) else { return nil }
				let instantiatedType = parameter.typeDescription.asInstantiatedType
				return (label: parameter.label, suffixTypes: [instantiatedType.simplified, instantiatedType, parameter.typeDescription])
			},
			reservedNames: seenLabels.subtracting(collidingLabels).union(parameterLabels),
		)
		let nameByProperty = Dictionary(zip(collidingProperties, names), uniquingKeysWith: { first, _ in first })
		return propertyNodes.map { property in property.map { nameByProperty[$0] ?? $0.label } }
	}

	/// The name each node of the mock root's level, `nodes` in generation order, is bound under: its property nodes'
	/// names (`levelBindingNames(of:besideParametersKeepingTheirLabels:)`), and each alias whose label a property node of
	/// the level, a flat received parameter or an override binds named apart, as `ScopeGenerator.renamingAliases` does:
	/// `<label>_<simplified type>`, `_` appended while the name is taken.
	static func rootLevelBindingNames(of nodes: [LevelNode], besideNamesTaken namesTaken: RootLevelNamesTaken) -> [String?] {
		var bindingNames = levelBindingNames(of: nodes, besideParametersKeepingTheirLabels: namesTaken.parametersKeepingTheirLabels)
		let propertyNodeNames = Set(zip(nodes, bindingNames).compactMap { node, bindingName -> String? in
			guard case .property(_, isUnavailableDependency: false) = node else { return nil }
			return bindingName
		})
		let aliases: [(index: Int, property: Property)] = nodes.enumerated().compactMap { index, node in
			guard case let .alias(property) = node else { return nil }
			return (index, property)
		}
		// The root binds each override of what its tree receives only if available under its name before the tree, as it
		// binds its property nodes (`MockRootTopLevelNames.rootBindingNames`).
		let redeclaredNames = propertyNodeNames.union(namesTaken.flatReceivedLabels).union(namesTaken.overrideNames)
		var takenNames = propertyNodeNames.union(namesTaken.rootLabels).union(aliases.map(\.property.label)).union(namesTaken.namesDeclaredInBuilderFunctions)
		for alias in aliases where redeclaredNames.contains(alias.property.label) {
			var name = "\(alias.property.label)_\(alias.property.typeDescription.simplified.asIdentifier)".spelledAsJoinedIdentifier
			while !takenNames.insert(name).inserted {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			bindingNames[alias.index] = name
		}
		return bindingNames
	}
}
