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
	/// The claim of `declaration`, a node of a mock root's world, as `mockUnavailableDependency` where it stands for a property
	/// instantiated only if available that no declaration fulfills (`ConstructionScope.isUnavailableDependency`): as
	/// production's kind does, it discharges stage 1's refusal of an unavailable dependency, and of a type with no
	/// initializer, since the node builds nothing. `nil` for any other node.
	static func mockUnavailableDependencyClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.scope(of: declaration).isUnavailableDependency else { return nil }
		return NodeRecordClaim(kind: .mockUnavailableDependency, discharges: [.unavailableOrInlineSeam, .noInitializer])
	}

	/// What each call of the function of `declaration`, a node of a mock root's world, hands it of the overrides `mock()`
	/// takes of properties nothing fulfills: one argument for each such override that the node's type, or a type built
	/// beneath it, binds its property from, named as the override and in the order `SafeDIOverrides` declares them.
	///
	/// `mock()` takes one override of such a property (`MockLowering.RootSignature.unavailableDependencyOverrideNames`), a
	/// value of its own and no field of a configuration, and each type that declares the property binds it from that
	/// value. A function is declared once, in `mock()`'s body, and reads nothing of `mock()`'s but what it is handed, so
	/// the override travels as an argument: `mock()`'s body hands the field of its overrides, and a function hands on the
	/// argument it was handed.
	/// - Throws: `unavailableOrInlineSeam` for a node whose function could not take the argument: one called both by
	///   `mock()`'s body and by another function, whose calls would spell two values, and a `@Sendable` function, inside
	///   which the walk binds the property to `nil`.
	static func unavailableDependencyOverrideArguments(of declaration: DeclarationID, in world: some NodeRecordSources, children: [GeneratedCode], isSendable: Bool) throws(NodeRecordRefusal) -> [PassedArgument] {
		let mockRootNames = world.mockRootNames
		guard !mockRootNames.unavailableDependencyOverrideNamesInOrder.isEmpty else { return [] }
		var typesByName = [String: TypeDescription]()
		for child in world.edges(from: declaration) where world.scope(of: child).isUnavailableDependency {
			if let property = world.property(of: child), let name = mockRootNames.unavailableDependencyOverrideName(of: property) {
				typesByName[name] = property.typeDescription
			}
		}
		let names = Set(mockRootNames.unavailableDependencyOverrideNamesInOrder)
		for child in children {
			guard case let .indented(place, by: _) = child.node, case let .place(plan) = place.node, case let .built(record) = plan.record else { continue }
			for argument in record.passedArguments where names.contains(argument.parameterName) {
				typesByName[argument.parameterName] = argument.type
			}
		}
		guard !typesByName.isEmpty else { return [] }
		guard !isSendable, let isCalledByRoot = isCalledOnlyByRoot(declaration, in: world) else { throw .unavailableOrInlineSeam }
		return mockRootNames.unavailableDependencyOverrideNamesInOrder.compactMap { name in
			typesByName[name].map { type in
				PassedArgument(
					parameterName: name,
					type: type,
					value: isCalledByRoot ? .member(name, of: .passedArgument(ReservedName.mockOverridesParameterName)) : .passedArgument(name),
					staysOutsideSendableFunctions: true,
				)
			}
		}
	}

	/// Whether every parent of `declaration` is the root, or none is; `nil` where the root and another node both build it.
	private static func isCalledOnlyByRoot(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool? {
		let parentsAreRoot = Set(world.parents(of: declaration).map { $0.parent == 0 })
		return parentsAreRoot.count == 1 ? parentsAreRoot.first : nil
	}

	/// The record of `declaration`'s place, a node of kind `mockUnavailableDependency`: production's record of an
	/// unavailable dependency (`unavailableDependencyRecord(of:in:)`), bound to the override `mock()` takes of the
	/// property where it takes one, and to `nil` where it takes none. `mock()`'s body reads the override of `mock()`'s
	/// parameter, and a function reads the argument it is handed
	/// (`unavailableDependencyOverrideArguments(of:in:children:isSendable:)`); the engine sees neither read, and neither
	/// is a capture.
	static func mockUnavailableDependencyRecord(of declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> AliasPlaceRecord {
		let record = try unavailableDependencyRecord(of: declaration, in: world)
		// The declaration is its declaring type's alone, so its one parent is the root or is not.
		let overridesPrefix = world.parents(of: declaration).allSatisfy { $0.parent == 0 } ? "\(ReservedName.mockOverridesParameterName)." : ""
		let value = world.mockRootNames.unavailableDependencyOverrideName(of: record.property).map { overridesPrefix + $0 } ?? "nil"
		return AliasPlaceRecord(property: record.property, fulfillingProperty: nil, text: "let \(record.property.asSource) = \(value)", reads: [])
	}
}
