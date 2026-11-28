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

extension ValuePath {
	/// The path with `.handedToChildrenByPlacingBody` resolved to `handed`, the overrides the body that places the
	/// path's record hands its children. A record reads its configuration as a member of the term, a chain of member reads
	/// above it, which is walked without recursing, since it can be as deep as the configurations it reads through. A path
	/// that holds the term anywhere else keeps it, and spells nothing (`TypeKeyLayout.spelledValuePath`), so that its root
	/// keeps the path key's body. A body that hands a node no configuration is known before the node's record is made
	/// (`MockEnteredSlots.hasConfigurationByDeclaration`), and the record then reads none.
	func resolvingHandedToChildrenByPlacingBody(to handed: ValuePath) -> ValuePath {
		var members = [(name: String, throughOptional: Bool)]()
		var current = self
		while true {
			switch current {
			case let .memberRead(name, base):
				members.append((name, false))
				current = base.value
			case let .optionalMemberRead(name, base):
				members.append((name, true))
				current = base.value
			case .rootDeclaration,
			     .read,
			     .passedArgument,
			     .call,
			     .implicitMemberCall,
			     .emptyInitialization,
			     .spliced:
				return self
			case .handedToChildrenByPlacingBody:
				var resolved = handed
				for member in members.reversed() {
					resolved = member.throughOptional ? .optionalMember(member.name, of: resolved) : .member(member.name, of: resolved)
				}
				return resolved
			}
		}
	}
}

extension PassedArgument {
	/// The argument with `.handedToChildrenByPlacingBody` resolved to `handed`
	/// (`ValuePath.resolvingHandedToChildrenByPlacingBody(to:)`).
	func resolvingHandedToChildrenByPlacingBody(to handed: ValuePath) -> PassedArgument {
		var argument = PassedArgument(parameterName: parameterName, type: type, value: value.resolvingHandedToChildrenByPlacingBody(to: handed), staysOutsideSendableFunctions: staysOutsideSendableFunctions)
		argument.bindsBeforeCall = bindsBeforeCall
		return argument
	}
}

extension ConstructionAlternative {
	/// The alternative with `.handedToChildrenByPlacingBody` resolved to `handed`
	/// (`ValuePath.resolvingHandedToChildrenByPlacingBody(to:)`) in its closure and in each value that must be absent.
	func resolvingHandedToChildrenByPlacingBody(to handed: ValuePath) -> ConstructionAlternative {
		ConstructionAlternative(
			closure: closure.resolvingHandedToChildrenByPlacingBody(to: handed),
			bindingName: bindingName,
			requiresAbsent: requiresAbsent.map { $0.resolvingHandedToChildrenByPlacingBody(to: handed) },
			use: use,
			resultWrapper: resultWrapper,
		)
	}
}

extension BuiltPlaceRecord {
	/// The record with `.handedToChildrenByPlacingBody` resolved to `handed` in every value it holds
	/// (`ValuePath.resolvingHandedToChildrenByPlacingBody(to:)`): what its calls hand its function, the closures its
	/// construction tries first, its arguments' values and its construction value. A record that holds no value is itself.
	func resolvingHandedToChildrenByPlacingBody(to handed: ValuePath) -> BuiltPlaceRecord {
		guard let sharingFields else { return self }
		var record = self
		record.sharingFields = PlaceSharingFields(
			passedArguments: sharingFields.passedArguments.map { $0.resolvingHandedToChildrenByPlacingBody(to: handed) },
			constructionValue: sharingFields.constructionValue.map { ConstructionValue(value: $0.value.resolvingHandedToChildrenByPlacingBody(to: handed), resultWrapper: $0.resultWrapper) },
			alternatives: sharingFields.alternatives.map { $0.resolvingHandedToChildrenByPlacingBody(to: handed) },
			argumentValues: sharingFields.argumentValues.mapValues { $0.resolvingHandedToChildrenByPlacingBody(to: handed) },
			functionReturnType: sharingFields.functionReturnType,
		)
		return record
	}
}
