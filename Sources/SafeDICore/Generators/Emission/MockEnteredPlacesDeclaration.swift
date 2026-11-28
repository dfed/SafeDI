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

/// The declarations a mock root's functions on its tree's cycles enter places with (`NodeRecords+MockCycle.swift`).
extension MockEnteredSlot {
	/// The lines, unindented, a mock root writes once before its functions where its tree holds a cycle: an enum of the
	/// places entered along one path, nearest first; a struct that pairs a configuration with those places, which a
	/// function on a cycle is handed in one argument; and the value of that struct `mock()`'s own body hands on, with no
	/// place entered.
	///
	/// A place holds the slot it was entered under, `nil` for a place entered only as the nearest of its type, and its
	/// configuration, boxed in the struct with no places so that a cast to the struct finds a place of one configuration
	/// type alone: a cast to a configuration type that is optional would find a `nil` of any other. `entering` returns
	/// the place entered before under a slot, with the places as they were when it was entered, and otherwise enters a new
	/// one, with the nearest configuration of its type where told to look for one, else the configuration handed.
	///
	/// Where some place may be entered left out, the struct also says whether its place was: a call along an edge the
	/// configurations leave out enters its place from `leavingOut`, and every value entered from one that is left out is
	/// left out too, until a call closes on a place entered before that is not, or enters, for the nearest of its type,
	/// beneath one that is not: that place takes the nearest's configuration and is not left out, as the walk's function
	/// for a type built again beneath itself reads the overrides of the one above. A place entered left out keeps the
	/// configuration each call hands, never one entered before: the walk leaves every other construction beneath such
	/// an edge to its initializer's own defaults, evaluated again each time.
	///
	/// The text follows the four arguments and nothing else, so it is one text on every run.
	/// - Parameter isSendable: Whether a function that is handed the places is `@Sendable`. The enum and the struct are
	///   then `Sendable`, a place holds `any Sendable`, and both are `nonisolated`, so that a `nonisolated` function can
	///   enter a place in a module whose declarations default to the main actor.
	/// - Parameter entersNearest: Whether some function on no cycle enters the nearest place of its type alone.
	/// - Parameter passes: Whether some function only hands the places on.
	/// - Parameter leavesOut: Whether some place may be entered left out (`MockEnteredSlots.mayBeEnteredLeftOutByDeclaration`).
	static func mockEnteredPlacesDeclaration(isSendable: Bool, entersNearest: Bool, passes: Bool, leavesOut: Bool) -> [String] {
		let indent = ScopeGenerator.standardIndent
		let places = ReservedName.mockEnteredPlacesTypeName
		let entered = ReservedName.mockEnteredTypeName
		let configuration = ReservedName.mockEnteredConfigurationMemberName
		let nearestOfType = ReservedName.mockEnteringNearestOfTypeArgumentLabel
		let handed = isSendable ? "<Handed: Sendable>" : "<Handed>"
		let isLeftOut = ReservedName.mockEnteredIsLeftOutMemberName
		// What each value made of one that may be left out carries on.
		let carriedOn = leavesOut ? ", \(isLeftOut): \(isLeftOut)" : ""
		var lines = [
			isSendable ? "nonisolated indirect enum \(places): Sendable {" : "indirect enum \(places) {",
			"\(indent)case none",
			"\(indent)case entered(slot: String?, entered: \(isSendable ? "any Sendable" : "Any"), above: \(places))",
			"}",
			isSendable ? "nonisolated struct \(entered)<Configuration: Sendable>: Sendable {" : "struct \(entered)<Configuration> {",
			"\(indent)let \(configuration): Configuration",
			"\(indent)var places = \(places).none",
		]
		if leavesOut {
			lines.append("\(indent)var \(isLeftOut) = false")
			lines.append("\(indent)var \(ReservedName.mockEnteredLeavingOutMemberName): \(entered)<Configuration> { .init(\(configuration): \(configuration), places: places, \(isLeftOut): true) }")
		}
		lines += [
			"\(indent)func \(ReservedName.mockEnteringFunctionName)\(handed)(_ slot: String, _ handed: Handed, \(nearestOfType): Bool = false) -> \(entered)<Handed> {",
			"\(indent)\(indent)var nearest: \(entered)<Handed>?",
			"\(indent)\(indent)var above = places",
			"\(indent)\(indent)while case let .entered(enteredSlot, entered, next) = above {",
			"\(indent)\(indent)\(indent)if enteredSlot == slot || \(nearestOfType) && nearest == nil, let entered = entered as? \(entered)<Handed> {",
			leavesOut
				? "\(indent)\(indent)\(indent)\(indent)if enteredSlot == slot { return .init(\(configuration): entered.\(isLeftOut) ? handed : entered.\(configuration), places: above, \(isLeftOut): entered.\(isLeftOut)) }"
				: "\(indent)\(indent)\(indent)\(indent)if enteredSlot == slot { return .init(\(configuration): entered.\(configuration), places: above) }",
			"\(indent)\(indent)\(indent)\(indent)nearest = entered",
			"\(indent)\(indent)\(indent)}",
			"\(indent)\(indent)\(indent)above = next",
			"\(indent)\(indent)}",
			leavesOut
				? "\(indent)\(indent)let entered = if let nearest, !nearest.\(isLeftOut) { nearest } else { \(entered)<Handed>(\(configuration): handed\(carriedOn)) }"
				: "\(indent)\(indent)let entered = \(entered)<Handed>(\(configuration): nearest?.\(configuration) ?? handed)",
			leavesOut
				? "\(indent)\(indent)return .init(\(configuration): entered.\(configuration), places: .entered(slot: slot, entered: entered, above: places), \(isLeftOut): entered.\(isLeftOut))"
				: "\(indent)\(indent)return .init(\(configuration): entered.\(configuration), places: .entered(slot: slot, entered: entered, above: places))",
			"\(indent)}",
		]
		if entersNearest {
			lines.append("\(indent)func \(ReservedName.mockEnteringNearestFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, places: .entered(slot: nil, entered: \(entered)<Handed>(\(configuration): handed\(carriedOn)), above: places)\(carriedOn))")
			lines.append("\(indent)}")
		}
		if passes {
			lines.append("\(indent)func \(ReservedName.mockPassingFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, places: places\(carriedOn))")
			lines.append("\(indent)}")
		}
		lines.append("}")
		lines.append("let \(ReservedName.mockEnteredPlacesParameterName) = \(entered)(\(configuration): ())")
		return lines
	}
}
