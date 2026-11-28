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
	/// Where some place may be entered left out, the struct a function is handed and each place also say whether the
	/// place was: a call along an edge the configurations leave out enters its place from `leavingOut`, and every value
	/// entered from one that is left out is left out too, until a call closes on a place entered before that is not, or
	/// enters, for the nearest of its type, beneath one that is not: that place takes the nearest's configuration and is
	/// not left out, as the walk's function for a type built again beneath itself reads the overrides of the one above.
	/// A place entered left out keeps the configuration each call hands, never one entered before: the walk leaves every
	/// other construction beneath such an edge to its initializer's own defaults, evaluated again each time. The nearest
	/// place of a type is the first of that type going up, taken only where it is not left out.
	///
	/// Looking the nearest place of a type up does not grow with the places entered either. A place entered for the nearest
	/// of its type keeps, by the type of the configuration it boxes, the nearest such place of each other type above it
	/// (`nearestOfEachTypeAbove`), made once from the one above, so the lookup looks at the nearest such place and then at
	/// most one more (`entered_looksAtOnePlaceForTheNearestOfItsType_whenEveryOtherTypeOfTheRingIsEnteredAbove`). A
	/// configuration type is a cast's: the box of one type is cast only to the box of that type.
	///
	/// The text follows the five arguments and nothing else, so it is one text on every run.
	/// - Parameter isSendable: Whether a function that is handed the places is `@Sendable`. The three types are then
	///   `Sendable`, a place holds `any Sendable`, and all are `nonisolated`, so that a `nonisolated` function can enter a
	///   place in a module whose declarations default to the main actor.
	/// - Parameter entersNearest: Whether some function on no cycle enters the nearest place of its type alone.
	/// - Parameter passes: Whether some function only hands the places on.
	/// - Parameter leavesOut: Whether some place may be entered left out (`MockEnteredSlots.mayBeEnteredLeftOutByDeclaration`).
	/// - Parameter slotCount: How many slots the root's calls enter, numbered from zero. A place holds one `UInt64` of
	///   bits per 64 of them.
	static func mockEnteredPlacesDeclaration(isSendable: Bool, entersNearest: Bool, passes: Bool, leavesOut: Bool, slotCount: Int) -> [String] {
		let indent = ScopeGenerator.standardIndent
		let place = ReservedName.mockEnteredPlaceTypeName
		let configured = ReservedName.mockEnteredConfiguredTypeName
		let entered = ReservedName.mockEnteredTypeName
		let configuration = ReservedName.mockEnteredConfigurationMemberName
		let nearestOfType = ReservedName.mockEnteringNearestOfTypeArgumentLabel
		let handed = isSendable ? "<Handed: Sendable>" : "<Handed>"
		let isLeftOut = ReservedName.mockEnteredIsLeftOutMemberName
		// What each place and value made of a value that may be left out carries on.
		let carriedOn = leavesOut ? ", \(isLeftOut): \(isLeftOut)" : ""
		let anyValue = isSendable ? "any Sendable" : "Any"
		let words = 0..<max(1, (slotCount + 63) / 64)
		var lines = [
			isSendable ? "nonisolated struct \(configured)<Configuration: Sendable>: Sendable {" : "struct \(configured)<Configuration> {",
			"\(indent)let \(configuration): Configuration",
			"}",
			isSendable ? "nonisolated final class \(place): Sendable {" : "final class \(place) {",
			"\(indent)let slot: Int?",
			"\(indent)let isNearestOfType: Bool",
			"\(indent)let configured: \(anyValue)",
			"\(indent)let above: \(place)?",
			"\(indent)let jump: \(place)?",
			"\(indent)let nearestOfTypeAbove: \(place)?",
			"\(indent)let configuredType: ObjectIdentifier",
			"\(indent)let nearestOfEachTypeAbove: [ObjectIdentifier: \(place)]",
			"\(indent)let depth: Int",
		]
		if leavesOut {
			lines.append("\(indent)let \(isLeftOut): Bool")
		}
		lines += words.map { "\(indent)let entered\($0): UInt64" }
		lines += [
			"\(indent)init(slot: Int?, isNearestOfType: Bool, configured: \(anyValue)\(leavesOut ? ", \(isLeftOut): Bool" : ""), above: \(place)?) {",
			"\(indent)\(indent)self.slot = slot",
			"\(indent)\(indent)self.isNearestOfType = isNearestOfType",
			"\(indent)\(indent)self.configured = configured",
			"\(indent)\(indent)self.above = above",
		]
		if leavesOut {
			lines.append("\(indent)\(indent)self.\(isLeftOut) = \(isLeftOut)")
		}
		lines += [
			"\(indent)\(indent)let depthAbove = above?.depth ?? 0",
			"\(indent)\(indent)let near = above?.jump",
			"\(indent)\(indent)let nearDepth = near?.depth ?? 0",
			"\(indent)\(indent)depth = depthAbove + 1",
			"\(indent)\(indent)jump = depthAbove - nearDepth == nearDepth - (near?.jump?.depth ?? 0) ? near?.jump : above",
			"\(indent)\(indent)let nearestAbove = above.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }",
			"\(indent)\(indent)nearestOfTypeAbove = nearestAbove",
			"\(indent)\(indent)configuredType = ObjectIdentifier(type(of: configured))",
			"\(indent)\(indent)if isNearestOfType, let nearestAbove {",
			"\(indent)\(indent)\(indent)var nearestOfEachType = nearestAbove.nearestOfEachTypeAbove",
			"\(indent)\(indent)\(indent)nearestOfEachType[nearestAbove.configuredType] = nearestAbove",
			"\(indent)\(indent)\(indent)nearestOfEachTypeAbove = nearestOfEachType",
			"\(indent)\(indent)} else {",
			"\(indent)\(indent)\(indent)nearestOfEachTypeAbove = [:]",
			"\(indent)\(indent)}",
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
		]
		if leavesOut {
			lines.append("\(indent)var \(isLeftOut) = false")
			lines.append("\(indent)var \(ReservedName.mockEnteredLeavingOutMemberName): \(entered)<Configuration> { .init(\(configuration): \(configuration), top: top, \(isLeftOut): true) }")
		}
		lines += [
			"\(indent)func nearest\(handed)(_: Handed.Type) -> Handed? {",
			"\(indent)\(indent)let type = ObjectIdentifier(\(configured)<Handed>.self)",
			"\(indent)\(indent)var place = top.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }",
			"\(indent)\(indent)if let candidate = place, candidate.configuredType != type {",
			"\(indent)\(indent)\(indent)place = candidate.nearestOfEachTypeAbove[type]",
			"\(indent)\(indent)}",
			leavesOut
				? "\(indent)\(indent)guard let place, let found = place.configured as? \(configured)<Handed>, !place.\(isLeftOut) else { return nil }"
				: "\(indent)\(indent)guard let place, let found = place.configured as? \(configured)<Handed> else { return nil }",
			"\(indent)\(indent)return found.\(configuration)",
			"\(indent)}",
			"\(indent)func \(ReservedName.mockEnteringFunctionName)\(handed)(_ slot: Int, _ handed: @autoclosure () -> Handed, \(nearestOfType): Bool = false) -> \(entered)<Handed> {",
			"\(indent)\(indent)if var place = top, place.has(slot) {",
			"\(indent)\(indent)\(indent)while place.slot != slot, let next = place.jump.flatMap({ $0.has(slot) ? $0 : nil }) ?? place.above {",
			"\(indent)\(indent)\(indent)\(indent)place = next",
			"\(indent)\(indent)\(indent)}",
			"\(indent)\(indent)\(indent)if let found = place.configured as? \(configured)<Handed> {",
			leavesOut
				? "\(indent)\(indent)\(indent)\(indent)return .init(\(configuration): place.\(isLeftOut) ? handed() : found.\(configuration), top: place, \(isLeftOut): place.\(isLeftOut))"
				: "\(indent)\(indent)\(indent)\(indent)return .init(\(configuration): found.\(configuration), top: place)",
			"\(indent)\(indent)\(indent)}",
			"\(indent)\(indent)}",
			"\(indent)\(indent)if \(nearestOfType), let nearest = nearest(Handed.self) {",
			"\(indent)\(indent)\(indent)return .init(\(configuration): nearest, top: \(place)(slot: slot, isNearestOfType: true, configured: \(configured)(\(configuration): nearest)\(leavesOut ? ", \(isLeftOut): false" : ""), above: top))",
			"\(indent)\(indent)}",
			"\(indent)\(indent)let \(configuration) = handed()",
			"\(indent)\(indent)return .init(\(configuration): \(configuration), top: \(place)(slot: slot, isNearestOfType: \(nearestOfType), configured: \(configured)(\(configuration): \(configuration))\(carriedOn), above: top)\(carriedOn))",
			"\(indent)}",
		]
		if entersNearest {
			lines.append("\(indent)func \(ReservedName.mockEnteringNearestFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, top: \(place)(slot: nil, isNearestOfType: true, configured: \(configured)(\(configuration): handed)\(carriedOn), above: top)\(carriedOn))")
			lines.append("\(indent)}")
		}
		if passes {
			lines.append("\(indent)func \(ReservedName.mockPassingFunctionName)\(handed)(_ handed: Handed) -> \(entered)<Handed> {")
			lines.append("\(indent)\(indent).init(\(configuration): handed, top: top\(carriedOn))")
			lines.append("\(indent)}")
		}
		lines.append("}")
		lines.append("let \(ReservedName.mockEnteredPlacesParameterName) = \(entered)(\(configuration): ())")
		return lines
	}
}
