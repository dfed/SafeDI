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
	/// The lines, unindented, a mock root writes once before its functions where its tree holds a cycle: a struct that
	/// boxes a place's configuration; a class of the places entered along one path, each pointing at the one above it; a
	/// struct that pairs a configuration with the nearest of those places, which a function on a cycle is handed in one
	/// argument; and the value of that struct `mock()`'s own body hands on, with no place entered.
	///
	/// A place holds the number of the slot it was entered under, `nil` for a place entered only as the nearest of its
	/// type, and its configuration, boxed so that a cast to the box finds a place of one configuration type alone: a cast
	/// to a configuration type that is optional would find a `nil` of any other. `entering` returns the place entered
	/// before under a slot, with the places as they were when it was entered, and otherwise enters a new one, with the
	/// nearest configuration of its type where told to look for one, else the configuration handed, which it evaluates
	/// only then.
	///
	/// Looking a slot up does not grow with the places entered. Each place holds a bit per slot, set where the slot is
	/// entered at it or above it, so a slot not entered is one test and no walk. A path holds a slot once, since a call
	/// that finds it returns to it, so the places that hold a slot's bit are the slot's place and all beneath it, and the
	/// walk up to it skips: each place also points at one farther up (`jump`), at the distances of a skew binary number,
	/// and the walk takes that pointer wherever its place still holds the bit. It looks at a number of places that grows
	/// with the logarithm of the places entered (`entered_looksAtPlacesByTheLogarithmOfTheRing_whenALapClosesOnItsFirstFunction`).
	/// A place is immutable and made once, when entered; finding one makes nothing.
	///
	/// The text follows the four arguments and nothing else, so it is one text on every run.
	/// - Parameter isSendable: Whether a function that is handed the places is `@Sendable`. The three types are then
	///   `Sendable`, a place holds `any Sendable`, and all are `nonisolated`, so that a `nonisolated` function can enter a
	///   place in a module whose declarations default to the main actor.
	/// - Parameter entersNearest: Whether some function on no cycle enters the nearest place of its type alone.
	/// - Parameter passes: Whether some function only hands the places on.
	/// - Parameter slotCount: How many slots the root's calls enter, numbered from zero. A place holds one `UInt64` of
	///   bits per 64 of them.
	static func mockEnteredPlacesDeclaration(isSendable: Bool, entersNearest: Bool, passes: Bool, slotCount: Int) -> [String] {
		let indent = ScopeGenerator.standardIndent
		let place = ReservedName.mockEnteredPlaceTypeName
		let configured = ReservedName.mockEnteredConfiguredTypeName
		let entered = ReservedName.mockEnteredTypeName
		let configuration = ReservedName.mockEnteredConfigurationMemberName
		let nearestOfType = ReservedName.mockEnteringNearestOfTypeArgumentLabel
		let handed = isSendable ? "<Handed: Sendable>" : "<Handed>"
		let words = 0..<max(1, (slotCount + 63) / 64)
		var lines = [
			isSendable ? "nonisolated struct \(configured)<Configuration: Sendable>: Sendable {" : "struct \(configured)<Configuration> {",
			"\(indent)let \(configuration): Configuration",
			"}",
			isSendable ? "nonisolated final class \(place): Sendable {" : "final class \(place) {",
			"\(indent)let slot: Int?",
			"\(indent)let isNearestOfType: Bool",
			"\(indent)let configured: \(isSendable ? "any Sendable" : "Any")",
			"\(indent)let above: \(place)?",
			"\(indent)let jump: \(place)?",
			"\(indent)let nearestOfTypeAbove: \(place)?",
			"\(indent)let depth: Int",
		]
		lines += words.map { "\(indent)let entered\($0): UInt64" }
		lines += [
			"\(indent)init(slot: Int?, isNearestOfType: Bool, configured: \(isSendable ? "any Sendable" : "Any"), above: \(place)?) {",
			"\(indent)\(indent)self.slot = slot",
			"\(indent)\(indent)self.isNearestOfType = isNearestOfType",
			"\(indent)\(indent)self.configured = configured",
			"\(indent)\(indent)self.above = above",
			"\(indent)\(indent)let depthAbove = above?.depth ?? 0",
			"\(indent)\(indent)let near = above?.jump",
			"\(indent)\(indent)let nearDepth = near?.depth ?? 0",
			"\(indent)\(indent)depth = depthAbove + 1",
			"\(indent)\(indent)jump = depthAbove - nearDepth == nearDepth - (near?.jump?.depth ?? 0) ? near?.jump : above",
			"\(indent)\(indent)nearestOfTypeAbove = above.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }",
			"\(indent)\(indent)let word = slot.map { $0 >> 6 } ?? -1",
			"\(indent)\(indent)let bit: UInt64 = slot.map { 1 << UInt64($0 & 63) } ?? 0",
		]
		lines += words.map { "\(indent)\(indent)entered\($0) = (above?.entered\($0) ?? 0) | (word == \($0) ? bit : 0)" }
		lines += [
			"\(indent)}",
			"\(indent)func has(_ slot: Int) -> Bool {",
			"\(indent)\(indent)let bit: UInt64 = 1 << UInt64(slot & 63)",
			"\(indent)\(indent)switch slot >> 6 {",
		]
		lines += words.map { "\(indent)\(indent)case \($0): return entered\($0) & bit != 0" }
		lines += [
			"\(indent)\(indent)default: return false",
			"\(indent)\(indent)}",
			"\(indent)}",
			"}",
			isSendable ? "nonisolated struct \(entered)<Configuration: Sendable>: Sendable {" : "struct \(entered)<Configuration> {",
			"\(indent)let \(configuration): Configuration",
			"\(indent)var top: \(place)?",
			"\(indent)func nearest\(handed)(_: Handed.Type) -> Handed? {",
			"\(indent)\(indent)var place = top.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }",
			"\(indent)\(indent)while let candidate = place {",
			"\(indent)\(indent)\(indent)if let found = candidate.configured as? \(configured)<Handed> { return found.\(configuration) }",
			"\(indent)\(indent)\(indent)place = candidate.nearestOfTypeAbove",
			"\(indent)\(indent)}",
			"\(indent)\(indent)return nil",
			"\(indent)}",
			"\(indent)func \(ReservedName.mockEnteringFunctionName)\(handed)(_ slot: Int, _ handed: @autoclosure () -> Handed, \(nearestOfType): Bool = false) -> \(entered)<Handed> {",
			"\(indent)\(indent)if var place = top, place.has(slot) {",
			"\(indent)\(indent)\(indent)while place.slot != slot, let next = place.jump.flatMap({ $0.has(slot) ? $0 : nil }) ?? place.above {",
			"\(indent)\(indent)\(indent)\(indent)place = next",
			"\(indent)\(indent)\(indent)}",
			"\(indent)\(indent)\(indent)if let found = place.configured as? \(configured)<Handed> {",
			"\(indent)\(indent)\(indent)\(indent)return .init(\(configuration): found.\(configuration), top: place)",
			"\(indent)\(indent)\(indent)}",
			"\(indent)\(indent)}",
			"\(indent)\(indent)let \(configuration): Handed = (\(nearestOfType) ? nearest(Handed.self) : nil) ?? handed()",
			"\(indent)\(indent)return .init(\(configuration): \(configuration), top: \(place)(slot: slot, isNearestOfType: \(nearestOfType), configured: \(configured)(\(configuration): \(configuration)), above: top))",
			"\(indent)}",
		]
		if entersNearest {
			lines.append("\(indent)func \(ReservedName.mockEnteringNearestFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, top: \(place)(slot: nil, isNearestOfType: true, configured: \(configured)(\(configuration): handed), above: top))")
			lines.append("\(indent)}")
		}
		if passes {
			lines.append("\(indent)func \(ReservedName.mockPassingFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, top: top)")
			lines.append("\(indent)}")
		}
		lines.append("}")
		lines.append("let \(ReservedName.mockEnteredPlacesParameterName) = \(entered)(\(configuration): ())")
		return lines
	}
}
