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
	/// The text follows the three arguments and nothing else, so it is one text on every run.
	/// - Parameter isSendable: Whether a function that is handed the places is `@Sendable`. The enum and the struct are
	///   then `Sendable`, a place holds `any Sendable`, and both are `nonisolated`, so that a `nonisolated` function can
	///   enter a place in a module whose declarations default to the main actor.
	/// - Parameter entersNearest: Whether some function on no cycle enters the nearest place of its type alone.
	/// - Parameter passes: Whether some function only hands the places on.
	static func mockEnteredPlacesDeclaration(isSendable: Bool, entersNearest: Bool, passes: Bool) -> [String] {
		let indent = ScopeGenerator.standardIndent
		let places = ReservedName.mockEnteredPlacesTypeName
		let entered = ReservedName.mockEnteredTypeName
		let configuration = ReservedName.mockEnteredConfigurationMemberName
		let nearestOfType = ReservedName.mockEnteringNearestOfTypeArgumentLabel
		let handed = isSendable ? "<Handed: Sendable>" : "<Handed>"
		var lines = [
			isSendable ? "nonisolated indirect enum \(places): Sendable {" : "indirect enum \(places) {",
			"\(indent)case none",
			"\(indent)case entered(slot: String?, entered: \(isSendable ? "any Sendable" : "Any"), above: \(places))",
			"}",
			isSendable ? "nonisolated struct \(entered)<Configuration: Sendable>: Sendable {" : "struct \(entered)<Configuration> {",
			"\(indent)let \(configuration): Configuration",
			"\(indent)var places = \(places).none",
			"\(indent)func \(ReservedName.mockEnteringFunctionName)\(handed)(_ slot: String, _ handed: Handed, \(nearestOfType): Bool = false) -> \(entered)<Handed> {",
			"\(indent)\(indent)var nearest: \(entered)<Handed>?",
			"\(indent)\(indent)var above = places",
			"\(indent)\(indent)while case let .entered(enteredSlot, entered, next) = above {",
			"\(indent)\(indent)\(indent)if enteredSlot == slot || \(nearestOfType) && nearest == nil, let entered = entered as? \(entered)<Handed> {",
			"\(indent)\(indent)\(indent)\(indent)if enteredSlot == slot { return .init(\(configuration): entered.\(configuration), places: above) }",
			"\(indent)\(indent)\(indent)\(indent)nearest = entered",
			"\(indent)\(indent)\(indent)}",
			"\(indent)\(indent)\(indent)above = next",
			"\(indent)\(indent)}",
			"\(indent)\(indent)let entered = \(entered)<Handed>(\(configuration): nearest?.\(configuration) ?? handed)",
			"\(indent)\(indent)return .init(\(configuration): entered.\(configuration), places: .entered(slot: slot, entered: entered, above: places))",
			"\(indent)}",
		]
		if entersNearest {
			lines.append("\(indent)func \(ReservedName.mockEnteringNearestFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, places: .entered(slot: nil, entered: \(entered)<Handed>(\(configuration): handed), above: places))")
			lines.append("\(indent)}")
		}
		if passes {
			lines.append("\(indent)func \(ReservedName.mockPassingFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, places: places)")
			lines.append("\(indent)}")
		}
		lines.append("}")
		lines.append("let \(ReservedName.mockEnteredPlacesParameterName) = \(entered)(\(configuration): ())")
		return lines
	}
}
