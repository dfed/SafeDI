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

/// A property of a mock root's tree a path can close on: the property owns one member of the places the root's
/// functions enter (`ReservedName.mockEnteredPlacesTypeName`), which holds the place of the property the nearest
/// above on the path, with the configuration that place was entered with.
struct MockEnteredSlot: Hashable, Sendable {
	/// The member of the entered places: the property’s label, in `spelledAsIdentifier` spelling.
	let name: String
	/// The type the property builds, whose `SafeDIMockConfiguration` a place of the slot holds.
	let configurationType: TypeDescription
	/// The member that holds the nearest place of `configurationType` on the path, where several properties build the
	/// type, one name for the type; `nil` where this property is the only one that builds it.
	let nearestOfTypeSlotName: String?

	/// The lines, unindented, of the struct a mock root declares once for the functions on its tree's cycles. A value
	/// of it is the places entered along one path: a member per slot of `slots`, in their order, then one per
	/// nearest-of-type member, in the order `slots` first names each. `Place` holds the configuration a place was
	/// entered with and the places entered above it, so a function that finds its place there returns to both. A value
	/// with no place entered is `.init()`, and `entering(<slot>:)` returns the value with one more place entered, which
	/// is also the nearest of its type. `entering(<nearest-of-type member>:)` returns the value with that member alone
	/// set, for a function on no cycle whose configuration is the nearest of its type for a slot beneath it.
	///
	/// The text follows `slots` and nothing else, so one list is one text on every run.
	/// - Parameter isSendable: Whether a function that is handed the places is `@Sendable`. The struct and `Place` are
	///   then `Sendable`, which the compiler proves from their stored properties, and `nonisolated`, so that a
	///   `nonisolated` function can enter a place in a module whose declarations default to the main actor.
	static func mockEnteredPlacesDeclaration(slots: [MockEnteredSlot], isSendable: Bool) -> [String] {
		let indent = ScopeGenerator.standardIndent
		let typeName = ReservedName.mockEnteredPlacesTypeName
		func placeType(of slot: MockEnteredSlot) -> String {
			"Place<\(slot.configurationType.asSource).\(ScopeGenerator.mockConfigurationStructName)>"
		}
		var lines = [
			isSendable ? "nonisolated struct \(typeName): Sendable {" : "struct \(typeName) {",
			isSendable ? "\(indent)nonisolated final class Place<Configuration: Sendable>: Sendable {" : "\(indent)final class Place<Configuration> {",
			"\(indent)\(indent)let configuration: Configuration",
			"\(indent)\(indent)let enteredAbove: \(typeName)",
			"\(indent)\(indent)init(_ configuration: Configuration, above enteredAbove: \(typeName)) {",
			"\(indent)\(indent)\(indent)self.configuration = configuration",
			"\(indent)\(indent)\(indent)self.enteredAbove = enteredAbove",
			"\(indent)\(indent)}",
			"\(indent)}",
		]
		for slot in slots {
			lines.append("\(indent)var \(slot.name): \(placeType(of: slot))?")
		}
		// Each nearest-of-type member once, with the first slot that names it, whose type is every such slot's.
		var nearestOfTypeMembers = [(name: String, slot: MockEnteredSlot)]()
		var nearestOfTypeSlotNames = Set<String>()
		for slot in slots {
			guard let nearestOfTypeSlotName = slot.nearestOfTypeSlotName, nearestOfTypeSlotNames.insert(nearestOfTypeSlotName).inserted else { continue }
			nearestOfTypeMembers.append((name: nearestOfTypeSlotName, slot: slot))
		}
		for member in nearestOfTypeMembers {
			lines.append("\(indent)var \(member.name): \(placeType(of: member.slot))?")
		}
		for slot in slots {
			lines.append("\(indent)func entering(\(slot.name.spelledAsArgumentLabel) place: \(placeType(of: slot))) -> Self {")
			lines.append("\(indent)\(indent)var entered = self")
			lines.append("\(indent)\(indent)entered.\(slot.name) = place")
			if let nearestOfTypeSlotName = slot.nearestOfTypeSlotName {
				lines.append("\(indent)\(indent)entered.\(nearestOfTypeSlotName) = place")
			}
			lines.append("\(indent)\(indent)return entered")
			lines.append("\(indent)}")
		}
		for member in nearestOfTypeMembers {
			lines.append("\(indent)func entering(\(member.name.spelledAsArgumentLabel) place: \(placeType(of: member.slot))) -> Self {")
			lines.append("\(indent)\(indent)var entered = self")
			lines.append("\(indent)\(indent)entered.\(member.name) = place")
			lines.append("\(indent)\(indent)return entered")
			lines.append("\(indent)}")
		}
		lines.append("}")
		return lines
	}
}
