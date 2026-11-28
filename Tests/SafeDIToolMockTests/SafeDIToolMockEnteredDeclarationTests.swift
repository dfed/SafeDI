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

import Foundation
import Testing
@testable import SafeDICore
@testable import SafeDIToolTestSupport

/// What a mock root declares once for the functions on its tree's cycles
/// (`MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable:entersNearest:passes:leavesOut:slotCount:)`): the list of the places entered
/// along a path, and the struct a function is handed. The text tests compare the whole declaration; the others compile it
/// into a program of hand-made functions that are handed the struct as a function of a mock is, walk a route through
/// them, and print the configuration each function reads.
struct SafeDIToolMockEnteredDeclarationTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	func mockEnteredPlacesDeclaration_declaresOnlyTheFunctionThatEntersASlot_whenNoCallEntersTheNearestOrPasses() {
		#expect(MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable: false, entersNearest: false, passes: false, leavesOut: false, slotCount: 1).joined(separator: "\n") == """
		struct __safeDI_Configured<Configuration> {
		    let configuration: Configuration
		}
		final class __safeDI_Place {
		    let slot: Int?
		    let isNearestOfType: Bool
		    let configured: Any
		    let above: __safeDI_Place?
		    let jump: __safeDI_Place?
		    let nearestOfTypeAbove: __safeDI_Place?
		    let configuredType: ObjectIdentifier
		    let nearestOfEachTypeAbove: [ObjectIdentifier: __safeDI_Place]
		    let depth: Int
		    let entered0: UInt64
		    init(slot: Int?, isNearestOfType: Bool, configured: Any, above: __safeDI_Place?) {
		        self.slot = slot
		        self.isNearestOfType = isNearestOfType
		        self.configured = configured
		        self.above = above
		        let depthAbove = above?.depth ?? 0
		        let near = above?.jump
		        let nearDepth = near?.depth ?? 0
		        depth = depthAbove + 1
		        jump = depthAbove - nearDepth == nearDepth - (near?.jump?.depth ?? 0) ? near?.jump : above
		        let nearestAbove = above.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        nearestOfTypeAbove = nearestAbove
		        configuredType = ObjectIdentifier(type(of: configured))
		        if isNearestOfType, let nearestAbove {
		            var nearestOfEachType = nearestAbove.nearestOfEachTypeAbove
		            nearestOfEachType[nearestAbove.configuredType] = nearestAbove
		            nearestOfEachTypeAbove = nearestOfEachType
		        } else {
		            nearestOfEachTypeAbove = [:]
		        }
		        let word = slot.map { $0 >> 6 } ?? -1
		        let bit: UInt64 = slot.map { 1 << UInt64($0 & 63) } ?? 0
		        entered0 = (above?.entered0 ?? 0) | (word == 0 ? bit : 0)
		    }
		    func has(_ slot: Int) -> Bool {
		        let bit: UInt64 = 1 << UInt64(slot & 63)
		        switch slot >> 6 {
		        case 0: return entered0 & bit != 0
		        default: return false
		        }
		    }
		}
		struct __safeDI_Entered<Configuration> {
		    let configuration: Configuration
		    var top: __safeDI_Place?
		    func nearest<Handed>(_: Handed.Type) -> Handed? {
		        let type = ObjectIdentifier(__safeDI_Configured<Handed>.self)
		        var place = top.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        if let candidate = place, candidate.configuredType != type {
		            place = candidate.nearestOfEachTypeAbove[type]
		        }
		        guard let place, let found = place.configured as? __safeDI_Configured<Handed> else { return nil }
		        return found.configuration
		    }
		    func entering<Handed>(_ slot: Int, _ handed: @autoclosure () -> Handed, nearestOfType: Bool = false) -> __safeDI_Entered<Handed> {
		        if var place = top, place.has(slot) {
		            while place.slot != slot, let next = place.jump.flatMap({ $0.has(slot) ? $0 : nil }) ?? place.above {
		                place = next
		            }
		            if let found = place.configured as? __safeDI_Configured<Handed> {
		                return .init(configuration: found.configuration, top: place)
		            }
		        }
		        if nearestOfType, let nearest = nearest(Handed.self) {
		            return .init(configuration: nearest, top: __safeDI_Place(slot: slot, isNearestOfType: true, configured: __safeDI_Configured(configuration: nearest), above: top))
		        }
		        let configuration = handed()
		        return .init(configuration: configuration, top: __safeDI_Place(slot: slot, isNearestOfType: nearestOfType, configured: __safeDI_Configured(configuration: configuration), above: top))
		    }
		}
		let __safeDI_entered = __safeDI_Entered(configuration: ())
		""")
	}

	@Test
	func mockEnteredPlacesDeclaration_declaresAFunctionForEachWayACallHandsThePlaces_whenCallsEnterTheNearestAndPass() {
		#expect(MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable: false, entersNearest: true, passes: true, leavesOut: false, slotCount: 1).joined(separator: "\n") == """
		struct __safeDI_Configured<Configuration> {
		    let configuration: Configuration
		}
		final class __safeDI_Place {
		    let slot: Int?
		    let isNearestOfType: Bool
		    let configured: Any
		    let above: __safeDI_Place?
		    let jump: __safeDI_Place?
		    let nearestOfTypeAbove: __safeDI_Place?
		    let configuredType: ObjectIdentifier
		    let nearestOfEachTypeAbove: [ObjectIdentifier: __safeDI_Place]
		    let depth: Int
		    let entered0: UInt64
		    init(slot: Int?, isNearestOfType: Bool, configured: Any, above: __safeDI_Place?) {
		        self.slot = slot
		        self.isNearestOfType = isNearestOfType
		        self.configured = configured
		        self.above = above
		        let depthAbove = above?.depth ?? 0
		        let near = above?.jump
		        let nearDepth = near?.depth ?? 0
		        depth = depthAbove + 1
		        jump = depthAbove - nearDepth == nearDepth - (near?.jump?.depth ?? 0) ? near?.jump : above
		        let nearestAbove = above.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        nearestOfTypeAbove = nearestAbove
		        configuredType = ObjectIdentifier(type(of: configured))
		        if isNearestOfType, let nearestAbove {
		            var nearestOfEachType = nearestAbove.nearestOfEachTypeAbove
		            nearestOfEachType[nearestAbove.configuredType] = nearestAbove
		            nearestOfEachTypeAbove = nearestOfEachType
		        } else {
		            nearestOfEachTypeAbove = [:]
		        }
		        let word = slot.map { $0 >> 6 } ?? -1
		        let bit: UInt64 = slot.map { 1 << UInt64($0 & 63) } ?? 0
		        entered0 = (above?.entered0 ?? 0) | (word == 0 ? bit : 0)
		    }
		    func has(_ slot: Int) -> Bool {
		        let bit: UInt64 = 1 << UInt64(slot & 63)
		        switch slot >> 6 {
		        case 0: return entered0 & bit != 0
		        default: return false
		        }
		    }
		}
		struct __safeDI_Entered<Configuration> {
		    let configuration: Configuration
		    var top: __safeDI_Place?
		    func nearest<Handed>(_: Handed.Type) -> Handed? {
		        let type = ObjectIdentifier(__safeDI_Configured<Handed>.self)
		        var place = top.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        if let candidate = place, candidate.configuredType != type {
		            place = candidate.nearestOfEachTypeAbove[type]
		        }
		        guard let place, let found = place.configured as? __safeDI_Configured<Handed> else { return nil }
		        return found.configuration
		    }
		    func entering<Handed>(_ slot: Int, _ handed: @autoclosure () -> Handed, nearestOfType: Bool = false) -> __safeDI_Entered<Handed> {
		        if var place = top, place.has(slot) {
		            while place.slot != slot, let next = place.jump.flatMap({ $0.has(slot) ? $0 : nil }) ?? place.above {
		                place = next
		            }
		            if let found = place.configured as? __safeDI_Configured<Handed> {
		                return .init(configuration: found.configuration, top: place)
		            }
		        }
		        if nearestOfType, let nearest = nearest(Handed.self) {
		            return .init(configuration: nearest, top: __safeDI_Place(slot: slot, isNearestOfType: true, configured: __safeDI_Configured(configuration: nearest), above: top))
		        }
		        let configuration = handed()
		        return .init(configuration: configuration, top: __safeDI_Place(slot: slot, isNearestOfType: nearestOfType, configured: __safeDI_Configured(configuration: configuration), above: top))
		    }
		    func enteringNearest<Handed>(_ handed: Handed) -> __safeDI_Entered<Handed> {
		        .init(configuration: handed, top: __safeDI_Place(slot: nil, isNearestOfType: true, configured: __safeDI_Configured(configuration: handed), above: top))
		    }
		    func passing<Handed>(_ handed: Handed) -> __safeDI_Entered<Handed> {
		        .init(configuration: handed, top: top)
		    }
		}
		let __safeDI_entered = __safeDI_Entered(configuration: ())
		""")
	}

	@Test
	func mockEnteredPlacesDeclaration_declaresWhetherAPlaceWasEnteredLeftOut_whenSomePlaceMayBe() {
		#expect(MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable: false, entersNearest: true, passes: true, leavesOut: true, slotCount: 1).joined(separator: "\n") == """
		struct __safeDI_Configured<Configuration> {
		    let configuration: Configuration
		}
		final class __safeDI_Place {
		    let slot: Int?
		    let isNearestOfType: Bool
		    let configured: Any
		    let above: __safeDI_Place?
		    let jump: __safeDI_Place?
		    let nearestOfTypeAbove: __safeDI_Place?
		    let configuredType: ObjectIdentifier
		    let nearestOfEachTypeAbove: [ObjectIdentifier: __safeDI_Place]
		    let depth: Int
		    let isLeftOut: Bool
		    let entered0: UInt64
		    init(slot: Int?, isNearestOfType: Bool, configured: Any, isLeftOut: Bool, above: __safeDI_Place?) {
		        self.slot = slot
		        self.isNearestOfType = isNearestOfType
		        self.configured = configured
		        self.above = above
		        self.isLeftOut = isLeftOut
		        let depthAbove = above?.depth ?? 0
		        let near = above?.jump
		        let nearDepth = near?.depth ?? 0
		        depth = depthAbove + 1
		        jump = depthAbove - nearDepth == nearDepth - (near?.jump?.depth ?? 0) ? near?.jump : above
		        let nearestAbove = above.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        nearestOfTypeAbove = nearestAbove
		        configuredType = ObjectIdentifier(type(of: configured))
		        if isNearestOfType, let nearestAbove {
		            var nearestOfEachType = nearestAbove.nearestOfEachTypeAbove
		            nearestOfEachType[nearestAbove.configuredType] = nearestAbove
		            nearestOfEachTypeAbove = nearestOfEachType
		        } else {
		            nearestOfEachTypeAbove = [:]
		        }
		        let word = slot.map { $0 >> 6 } ?? -1
		        let bit: UInt64 = slot.map { 1 << UInt64($0 & 63) } ?? 0
		        entered0 = (above?.entered0 ?? 0) | (word == 0 ? bit : 0)
		    }
		    func has(_ slot: Int) -> Bool {
		        let bit: UInt64 = 1 << UInt64(slot & 63)
		        switch slot >> 6 {
		        case 0: return entered0 & bit != 0
		        default: return false
		        }
		    }
		}
		struct __safeDI_Entered<Configuration> {
		    let configuration: Configuration
		    var top: __safeDI_Place?
		    var isLeftOut = false
		    var leavingOut: __safeDI_Entered<Configuration> { .init(configuration: configuration, top: top, isLeftOut: true) }
		    func nearest<Handed>(_: Handed.Type) -> Handed? {
		        let type = ObjectIdentifier(__safeDI_Configured<Handed>.self)
		        var place = top.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        if let candidate = place, candidate.configuredType != type {
		            place = candidate.nearestOfEachTypeAbove[type]
		        }
		        guard let place, let found = place.configured as? __safeDI_Configured<Handed>, !place.isLeftOut else { return nil }
		        return found.configuration
		    }
		    func entering<Handed>(_ slot: Int, _ handed: @autoclosure () -> Handed, nearestOfType: Bool = false) -> __safeDI_Entered<Handed> {
		        if var place = top, place.has(slot) {
		            while place.slot != slot, let next = place.jump.flatMap({ $0.has(slot) ? $0 : nil }) ?? place.above {
		                place = next
		            }
		            if let found = place.configured as? __safeDI_Configured<Handed> {
		                return .init(configuration: place.isLeftOut ? handed() : found.configuration, top: place, isLeftOut: place.isLeftOut)
		            }
		        }
		        if nearestOfType, let nearest = nearest(Handed.self) {
		            return .init(configuration: nearest, top: __safeDI_Place(slot: slot, isNearestOfType: true, configured: __safeDI_Configured(configuration: nearest), isLeftOut: false, above: top))
		        }
		        let configuration = handed()
		        return .init(configuration: configuration, top: __safeDI_Place(slot: slot, isNearestOfType: nearestOfType, configured: __safeDI_Configured(configuration: configuration), isLeftOut: isLeftOut, above: top), isLeftOut: isLeftOut)
		    }
		    func enteringNearest<Handed>(_ handed: Handed) -> __safeDI_Entered<Handed> {
		        .init(configuration: handed, top: __safeDI_Place(slot: nil, isNearestOfType: true, configured: __safeDI_Configured(configuration: handed), isLeftOut: isLeftOut, above: top), isLeftOut: isLeftOut)
		    }
		    func passing<Handed>(_ handed: Handed) -> __safeDI_Entered<Handed> {
		        .init(configuration: handed, top: top, isLeftOut: isLeftOut)
		    }
		}
		let __safeDI_entered = __safeDI_Entered(configuration: ())
		""")
	}

	@Test
	func mockEnteredPlacesDeclaration_declaresBothTypesSendableAndNonisolated_whenAFunctionHandedThePlacesIsSendable() {
		#expect(MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable: true, entersNearest: true, passes: true, leavesOut: false, slotCount: 65).joined(separator: "\n") == """
		nonisolated struct __safeDI_Configured<Configuration: Sendable>: Sendable {
		    let configuration: Configuration
		}
		nonisolated final class __safeDI_Place: Sendable {
		    let slot: Int?
		    let isNearestOfType: Bool
		    let configured: any Sendable
		    let above: __safeDI_Place?
		    let jump: __safeDI_Place?
		    let nearestOfTypeAbove: __safeDI_Place?
		    let configuredType: ObjectIdentifier
		    let nearestOfEachTypeAbove: [ObjectIdentifier: __safeDI_Place]
		    let depth: Int
		    let entered0: UInt64
		    let entered1: UInt64
		    init(slot: Int?, isNearestOfType: Bool, configured: any Sendable, above: __safeDI_Place?) {
		        self.slot = slot
		        self.isNearestOfType = isNearestOfType
		        self.configured = configured
		        self.above = above
		        let depthAbove = above?.depth ?? 0
		        let near = above?.jump
		        let nearDepth = near?.depth ?? 0
		        depth = depthAbove + 1
		        jump = depthAbove - nearDepth == nearDepth - (near?.jump?.depth ?? 0) ? near?.jump : above
		        let nearestAbove = above.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        nearestOfTypeAbove = nearestAbove
		        configuredType = ObjectIdentifier(type(of: configured))
		        if isNearestOfType, let nearestAbove {
		            var nearestOfEachType = nearestAbove.nearestOfEachTypeAbove
		            nearestOfEachType[nearestAbove.configuredType] = nearestAbove
		            nearestOfEachTypeAbove = nearestOfEachType
		        } else {
		            nearestOfEachTypeAbove = [:]
		        }
		        let word = slot.map { $0 >> 6 } ?? -1
		        let bit: UInt64 = slot.map { 1 << UInt64($0 & 63) } ?? 0
		        entered0 = (above?.entered0 ?? 0) | (word == 0 ? bit : 0)
		        entered1 = (above?.entered1 ?? 0) | (word == 1 ? bit : 0)
		    }
		    func has(_ slot: Int) -> Bool {
		        let bit: UInt64 = 1 << UInt64(slot & 63)
		        switch slot >> 6 {
		        case 0: return entered0 & bit != 0
		        case 1: return entered1 & bit != 0
		        default: return false
		        }
		    }
		}
		nonisolated struct __safeDI_Entered<Configuration: Sendable>: Sendable {
		    let configuration: Configuration
		    var top: __safeDI_Place?
		    func nearest<Handed: Sendable>(_: Handed.Type) -> Handed? {
		        let type = ObjectIdentifier(__safeDI_Configured<Handed>.self)
		        var place = top.flatMap { $0.isNearestOfType ? $0 : $0.nearestOfTypeAbove }
		        if let candidate = place, candidate.configuredType != type {
		            place = candidate.nearestOfEachTypeAbove[type]
		        }
		        guard let place, let found = place.configured as? __safeDI_Configured<Handed> else { return nil }
		        return found.configuration
		    }
		    func entering<Handed: Sendable>(_ slot: Int, _ handed: @autoclosure () -> Handed, nearestOfType: Bool = false) -> __safeDI_Entered<Handed> {
		        if var place = top, place.has(slot) {
		            while place.slot != slot, let next = place.jump.flatMap({ $0.has(slot) ? $0 : nil }) ?? place.above {
		                place = next
		            }
		            if let found = place.configured as? __safeDI_Configured<Handed> {
		                return .init(configuration: found.configuration, top: place)
		            }
		        }
		        if nearestOfType, let nearest = nearest(Handed.self) {
		            return .init(configuration: nearest, top: __safeDI_Place(slot: slot, isNearestOfType: true, configured: __safeDI_Configured(configuration: nearest), above: top))
		        }
		        let configuration = handed()
		        return .init(configuration: configuration, top: __safeDI_Place(slot: slot, isNearestOfType: nearestOfType, configured: __safeDI_Configured(configuration: configuration), above: top))
		    }
		    func enteringNearest<Handed: Sendable>(_ handed: Handed) -> __safeDI_Entered<Handed> {
		        .init(configuration: handed, top: __safeDI_Place(slot: nil, isNearestOfType: true, configured: __safeDI_Configured(configuration: handed), above: top))
		    }
		    func passing<Handed: Sendable>(_ handed: Handed) -> __safeDI_Entered<Handed> {
		        .init(configuration: handed, top: top)
		    }
		}
		let __safeDI_entered = __safeDI_Entered(configuration: ())
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_returnsAFunctionToItsPlaceAndForgetsThePlacesBeneathIt_whenARouteClosesOnAPropertyAbove() async throws {
		// The root calls `aBuilder`, which calls `bBuilder`, which calls `cBuilder`, which closes on `aBuilder`: that call
		// reads the configuration the first was entered with. `aBuilder` then calls `cBuilder`, whose earlier place was
		// beneath `aBuilder`'s and is forgotten, so it reads `aBuilder`'s field, not `bBuilder`'s.
		let functions = [
			Function(name: "aBuilder", typeName: "A", entry: .slot(nearestOfType: false)),
			Function(name: "bBuilder", typeName: "B", entry: .slot(nearestOfType: false)),
			Function(name: "cBuilder", typeName: "C", entry: .slot(nearestOfType: false)),
		]
		let printed = try await printedReads(functions: functions, isSendable: false, routes: [["aBuilder", "bBuilder", "cBuilder", "aBuilder", "cBuilder"]])
		#expect(printed == nil || printed == """
		aBuilder reads root.aBuilder
		bBuilder reads root.aBuilder.bBuilder
		cBuilder reads root.aBuilder.bBuilder.cBuilder
		aBuilder reads root.aBuilder
		cBuilder reads root.aBuilder.cBuilder

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_entersAPropertyWithTheNearestConfigurationOfItsType_whenTwoPropertiesBuildOneType() async throws {
		// First route: `otherHomeBuilder` is entered beneath `homeBuilder`, which builds its type too, so it reads
		// `homeBuilder`'s configuration and not `awayBuilder`'s field. Second route: `awayBuilder` is entered first and
		// `homeBuilder` beneath it; the route closes on `awayBuilder`, which forgets `homeBuilder`'s place, so
		// `otherHomeBuilder` finds no place of its type and reads `awayBuilder`'s field. Third route: `otherHomeBuilder` is
		// entered beneath `homeBuilder` and the route closes on it past a second place of its type, `homeBuilder`'s, entered
		// beneath it: it returns to its own place, not to the nearest of its type.
		let functions = [
			Function(name: "homeBuilder", typeName: "Home", entry: .slot(nearestOfType: true)),
			Function(name: "awayBuilder", typeName: "Away", entry: .slot(nearestOfType: false)),
			Function(name: "otherHomeBuilder", typeName: "Home", entry: .slot(nearestOfType: true)),
		]
		let printed = try await printedReads(functions: functions, isSendable: false, routes: [
			["homeBuilder", "awayBuilder", "otherHomeBuilder"],
			["awayBuilder", "homeBuilder", "awayBuilder", "otherHomeBuilder"],
			["awayBuilder", "otherHomeBuilder", "homeBuilder", "otherHomeBuilder", "homeBuilder"],
		])
		#expect(printed == nil || printed == """
		homeBuilder reads root.homeBuilder
		awayBuilder reads root.homeBuilder.awayBuilder
		otherHomeBuilder reads root.homeBuilder

		awayBuilder reads root.awayBuilder
		homeBuilder reads root.awayBuilder.homeBuilder
		awayBuilder reads root.awayBuilder
		otherHomeBuilder reads root.awayBuilder.otherHomeBuilder

		awayBuilder reads root.awayBuilder
		otherHomeBuilder reads root.awayBuilder.otherHomeBuilder
		homeBuilder reads root.awayBuilder.otherHomeBuilder
		otherHomeBuilder reads root.awayBuilder.otherHomeBuilder
		homeBuilder reads root.awayBuilder.otherHomeBuilder

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_castsOnlyThePlaceOfASlotsOwnName_whenTheSlotHasNoNearestOfType() async throws {
		// `homeBuilder` and `otherHomeBuilder` build one type, and neither enters the nearest place of its type: beneath
		// `homeBuilder`'s place, `otherHomeBuilder` reads the field it is handed, and the route then closes on `homeBuilder`.
		let functions = [
			Function(name: "homeBuilder", typeName: "Home", entry: .slot(nearestOfType: false)),
			Function(name: "otherHomeBuilder", typeName: "Home", entry: .slot(nearestOfType: false)),
		]
		let printed = try await printedReads(functions: functions, isSendable: false, routes: [["homeBuilder", "otherHomeBuilder", "homeBuilder"]])
		#expect(printed == nil || printed == """
		homeBuilder reads root.homeBuilder
		otherHomeBuilder reads root.homeBuilder.otherHomeBuilder
		homeBuilder reads root.homeBuilder

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_entersAPropertyWithTheConfigurationOfAFunctionOnNoCycle_whenThatFunctionBuildsThePropertysTypeAboveIt() async throws {
		// `homeBuilder` is on no cycle and has no slot; it enters only the nearest place of `Home`. `hallBuilder`, beneath
		// it, only hands the places on. Beneath that `roomBuilder` and `otherHomeBuilder`, which builds `Home` too, call each
		// other: `otherHomeBuilder` reads `homeBuilder`'s configuration at its first place, and again after the route closes
		// on `roomBuilder`, since `homeBuilder`'s place is above `roomBuilder`'s and is kept.
		let functions = [
			Function(name: "roomBuilder", typeName: "Room", entry: .slot(nearestOfType: false)),
			Function(name: "otherHomeBuilder", typeName: "Home", entry: .slot(nearestOfType: true)),
			Function(name: "homeBuilder", typeName: "Home", entry: .nearest),
			Function(name: "hallBuilder", typeName: "Hall", entry: .passing),
		]
		let printed = try await printedReads(functions: functions, isSendable: false, routes: [["homeBuilder", "hallBuilder", "roomBuilder", "otherHomeBuilder", "roomBuilder", "otherHomeBuilder"]])
		#expect(printed == nil || printed == """
		homeBuilder reads root.homeBuilder
		hallBuilder reads root.homeBuilder.hallBuilder
		roomBuilder reads root.homeBuilder.hallBuilder.roomBuilder
		otherHomeBuilder reads root.homeBuilder
		roomBuilder reads root.homeBuilder.hallBuilder.roomBuilder
		otherHomeBuilder reads root.homeBuilder

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_readsTheNearestPlaceOfItsTypeAndRetainsNothingAfterTheTreeIsReleased_whenNilsOfTwoOtherOptionalTypesAreEnteredBetween() async throws {
		// A ring of a main actor's `Parent` and a `Child` of no actor, entered from a builder on no cycle that enters only
		// the nearest place of `Parent`'s type. Between that place and `otherParentBuilder`'s the route enters a place of
		// `Int?`, and beneath `otherParentBuilder`'s a `nil` of `String?`: a cast of a place to the configuration handed
		// would take that `nil` for a `nil` of any optional type, and a cast to the struct does not, so `probe`, handed an
		// `Int?`, passes it and reads the place of `Int?` above, and every `Parent` reads the root's configuration past the
		// places of other types. The root's configuration holds a marker, which is released with the tree: a place points
		// only at the places above it.
		let declaration = MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable: false, entersNearest: true, passes: true, leavesOut: false, slotCount: 3).map { "    " + $0 }.joined(separator: "\n")
		let printed = try await DifferentialValueOracle.output(
			of: DifferentialValuePath(fixtureFiles: ["Program.swift": """
			final class Marker {}
			struct ParentConfiguration { var tag = ""; var marker: Marker? }
			struct ChildConfiguration { var tag = "" }
			final class Builder<Built> { let build: () -> Built; init(_ build: @escaping () -> Built) { self.build = build } }
			@MainActor final class Parent { let tag: String; let childBuilder: Builder<Child>; init(tag: String, childBuilder: Builder<Child>) { self.tag = tag; self.childBuilder = childBuilder } }
			final class Child { let tag: String; let parentBuilder: Builder<Parent>; init(tag: String, parentBuilder: Builder<Parent>) { self.tag = tag; self.parentBuilder = parentBuilder } }
			@MainActor func mock(safeDIOverrides: ParentConfiguration) -> Builder<Parent> {
			\(declaration)
			    func __safeDI_parentBuilder(__safeDI_entered: __safeDI_Entered<ParentConfiguration>) -> Parent {
			        let childBuilder = Builder<Child> { __safeDI_childBuilder(__safeDI_entered: __safeDI_entered.enteringNearest(Optional<Int>.some(3)).entering(0, ChildConfiguration())) }
			        return Parent(tag: __safeDI_entered.configuration.tag, childBuilder: childBuilder)
			    }
			    func __safeDI_childBuilder(__safeDI_entered: __safeDI_Entered<ChildConfiguration>) -> Child {
			        let parentBuilder = Builder<Parent> {
			            let parentEntered = __safeDI_entered.entering(1, ParentConfiguration(tag: "fresh"), nearestOfType: true)
			            let probe = parentEntered.enteringNearest(Optional<String>.none).entering(2, Optional<Int>.some(7), nearestOfType: true)
			            return __safeDI_parentBuilder(__safeDI_entered: probe.passing(probe.configuration == 3 ? parentEntered.configuration : ParentConfiguration(tag: "a nil was taken for a place")))
			        }
			        return Child(tag: __safeDI_entered.configuration.tag, parentBuilder: parentBuilder)
			    }
			    return Builder<Parent> { __safeDI_parentBuilder(__safeDI_entered: __safeDI_entered.passing(()).enteringNearest(safeDIOverrides)) }
			}
			@MainActor func run() {
			    weak var released: Marker?
			    do {
			        let marker = Marker()
			        released = marker
			        let parent = mock(safeDIOverrides: ParentConfiguration(tag: "root", marker: marker)).build()
			        let child = parent.childBuilder.build()
			        let secondParent = child.parentBuilder.build()
			        let secondChild = secondParent.childBuilder.build()
			        let thirdParent = secondChild.parentBuilder.build()
			        print([parent.tag, child.tag, secondParent.tag, secondChild.tag, thirdParent.tag])
			    }
			    print("released:", released == nil)
			}

			"""]),
			running: "await MainActor.run { run() }",
			filesToDelete: &filesToDelete,
		)
		#expect(printed == nil || printed == """
		["root", "", "root", "", "root"]
		released: true

		""")
	}

	@Test(arguments: [false, true], [nil, "MainActor"] as [String?])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_compilesWithNothingUnchecked_whenFunctionsOnTwoCyclesOfOneRootCaptureIt(isSendable: Bool, defaultIsolation: String?) async throws {
		// The root's two cycles share the declaration: `homeBuilder`, a plain function, enters a ring of `@Sendable`
		// functions (plain ones in the plain form) through `awayBuilder`, which also calls `porchBuilder`, a function on no
		// cycle; `catBuilder` and `dogBuilder` close on each other in plain functions. Language mode 6 checks every capture;
		// with the module's declarations defaulting to the main actor, the `Sendable` form's types are `nonisolated` so
		// that the `@Sendable nonisolated` functions can enter a place.
		_ = try await executeSafeDIToolTest(
			// `Probe` gives the run generated code, without which nothing is compiled.
			swiftFileContent: [Self.program(functions: Self.twoCycles(isSendable: isSendable), isSendable: isSendable), "@Instantiable(isRoot: true)\npublic struct Probe: Instantiable {\n    public init() {}\n}\n"],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: defaultIsolation),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_returnsSendableFunctionToItsPlaceAndEntersTheNearestOfItsType_whenRingRunsInsideSendableFunctions() async throws {
		// First route: `otherHomeBuilder` is entered inside `awayBuilder`'s `@Sendable` function, beneath `homeBuilder`, which
		// builds its type too, so it reads `homeBuilder`'s configuration; the route then closes on `awayBuilder`, which reads
		// the configuration it was first entered with, and enters `otherHomeBuilder` again, whose earlier place it forgets.
		// Second route: the plain cycle closes on `catBuilder`. Third route: `porchBuilder`, a `@Sendable` function on no
		// cycle that builds `Home`, enters the nearest place of its type, so `otherHomeBuilder` beneath it reads its
		// configuration.
		let printed = try await printedReads(functions: Self.twoCycles(isSendable: true), isSendable: true, routes: [
			["homeBuilder", "awayBuilder", "otherHomeBuilder", "awayBuilder", "otherHomeBuilder"],
			["catBuilder", "dogBuilder", "catBuilder"],
			["homeBuilder", "awayBuilder", "porchBuilder", "otherHomeBuilder"],
		])
		#expect(printed == nil || printed == """
		homeBuilder reads root.homeBuilder
		awayBuilder reads root.homeBuilder.awayBuilder
		otherHomeBuilder reads root.homeBuilder
		awayBuilder reads root.homeBuilder.awayBuilder
		otherHomeBuilder reads root.homeBuilder

		catBuilder reads root.catBuilder
		dogBuilder reads root.catBuilder.dogBuilder
		catBuilder reads root.catBuilder

		homeBuilder reads root.homeBuilder
		awayBuilder reads root.homeBuilder.awayBuilder
		porchBuilder reads root.homeBuilder.awayBuilder.porchBuilder
		otherHomeBuilder reads root.homeBuilder.awayBuilder.porchBuilder

		""")
	}

	@Test(arguments: [20, 40])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_looksAtPlacesByTheLogarithmOfTheRing_whenALapClosesOnItsFirstFunction(ringSize: Int) async throws {
		// A ring of `ringSize` functions, each of a type of its own. One lap enters every function's place and finds none
		// entered, which is one test of a bit and no step. The call that closes the lap finds the first function's place
		// beneath every other: a walk of the places one by one would take `ringSize - 1` steps, 19 and 39, and the pointers
		// that skip take about the logarithm. A second lap starts from the first function's place again, so it costs what
		// the first did.
		let functions = (0..<ringSize).map { Function(name: "builder\($0)", typeName: "Type\($0)", entry: .slot(nearestOfType: false)) }
		let program = Self.program(functions: functions, isSendable: false, countsPlacesLookedAt: true)
		// The walk to a slot's place, and the one step to the nearest place of a type.
		#expect(program.components(separatedBy: "placesLookedAt += 1").count == 3)
		let lap = functions.map { "\"\($0.name)\"" }.joined(separator: ", ")
		let printed = try await DifferentialValueOracle.output(
			of: DifferentialValuePath(fixtureFiles: ["Program.swift": program]),
			running: """
			let lap: [String] = [\(lap)]
			for route in [lap, lap + [lap[0]], lap + lap + [lap[0]]] {
			    placesLookedAt = 0
			    print(Root.reads(along: route[...]).last ?? "", "after looking at", placesLookedAt)
			}
			""",
			filesToDelete: &filesToDelete,
		)
		let stepsToCloseALap = [20: 9, 40: 11][ringSize] ?? 0
		#expect(printed == nil || printed == """
		builder\(ringSize - 1) reads root\(functions.map { "." + $0.name }.joined()) after looking at 0
		builder0 reads root.builder0 after looking at \(stepsToCloseALap)
		builder0 reads root.builder0 after looking at \(2 * stepsToCloseALap)

		""", "\(printed ?? "")")
	}

	@Test(arguments: [20, 40])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func entered_looksAtOnePlaceForTheNearestOfItsType_whenEveryOtherTypeOfTheRingIsEnteredAbove(ringSize: Int) async throws {
		// A ring of `ringSize` functions, each of a type of its own and entered for the nearest of its type, and then
		// `otherBuilder0`, of `builder0`'s type: its nearest place of that type is `builder0`'s, beneath every other type's
		// place. A walk of the places entered for the nearest of their types would take `ringSize - 1` steps to it, 19 and 39;
		// the nearest place of each type that every such place keeps takes one. Each function of the ring looks its own type
		// up beneath the one before it, which is of another type, so takes one step too.
		let ring = (0..<ringSize).map { Function(name: "builder\($0)", typeName: "Type\($0)", entry: .slot(nearestOfType: true)) }
		let functions = ring + [Function(name: "otherBuilder0", typeName: "Type0", entry: .slot(nearestOfType: true))]
		let program = Self.program(functions: functions, isSendable: false, countsPlacesLookedAt: true)
		let lap = ring.map { "\"\($0.name)\"" }.joined(separator: ", ")
		let printed = try await DifferentialValueOracle.output(
			of: DifferentialValuePath(fixtureFiles: ["Program.swift": program]),
			running: """
			let lap: [String] = [\(lap)]
			placesLookedAt = 0
			_ = Root.reads(along: lap[...])
			let lookingUpTheRing = placesLookedAt
			placesLookedAt = 0
			print(Root.reads(along: (lap + ["otherBuilder0"])[...]).last ?? "", "after looking at", placesLookedAt - lookingUpTheRing)
			""",
			filesToDelete: &filesToDelete,
		)
		#expect(printed == nil || printed == """
		otherBuilder0 reads root.builder0 after looking at 1

		""", "\(printed ?? "")")
	}

	// MARK: Private

	/// A hand-made function that is handed the entered places as a function of a mock's tree is.
	private struct Function {
		/// How a call of the function hands it the places.
		enum Entry {
			/// The function has a slot, which the call enters, with the nearest configuration of its type where
			/// `nearestOfType` is set.
			case slot(nearestOfType: Bool)
			/// The function has no slot, and the call enters the nearest place of its type.
			case nearest
			/// The call only hands the places on.
			case passing
		}

		let name: String
		/// The type whose `SafeDIMockConfiguration` the function reads.
		let typeName: String
		let entry: Entry
		/// Whether the function is `@Sendable nonisolated`, and built in a `SendableBuilder`.
		var isSendable = false

		/// What a call hands the function for the places, where the caller's own are `__safeDI_entered`.
		/// - Parameter slot: The function's position among the program's functions, which numbers its slot.
		func entered(handing configuration: String, slot: Int) -> String {
			switch entry {
			case let .slot(nearestOfType):
				"__safeDI_entered.entering(\(slot), \(configuration)\(nearestOfType ? ", nearestOfType: true" : ""))"
			case .nearest:
				"__safeDI_entered.enteringNearest(\(configuration))"
			case .passing:
				"__safeDI_entered.passing(\(configuration))"
			}
		}
	}

	private var filesToDelete: [URL]

	/// `Home`, built by `homeBuilder` and `otherHomeBuilder`, each entered with the nearest configuration of its type;
	/// `Away`, built by `awayBuilder`; `Cat` and `Dog`, a second cycle's; and `porchBuilder`, a function on no cycle that
	/// builds `Home`. In the `Sendable` form the ring `homeBuilder` enters, and `porchBuilder`, are `@Sendable`.
	private static func twoCycles(isSendable: Bool) -> [Function] {
		[
			Function(name: "homeBuilder", typeName: "Home", entry: .slot(nearestOfType: true)),
			Function(name: "awayBuilder", typeName: "Away", entry: .slot(nearestOfType: false), isSendable: isSendable),
			Function(name: "otherHomeBuilder", typeName: "Home", entry: .slot(nearestOfType: true), isSendable: isSendable),
			Function(name: "catBuilder", typeName: "Cat", entry: .slot(nearestOfType: false)),
			Function(name: "dogBuilder", typeName: "Dog", entry: .slot(nearestOfType: false)),
			Function(name: "porchBuilder", typeName: "Home", entry: .nearest, isSendable: isSendable),
		]
	}

	/// A program around the declaration, whose `Root.reads(along:)` calls the functions a route names and returns, a line
	/// per function, the configuration each reads. Each function's type has a `SafeDIMockConfiguration` named by the path
	/// of fields it was read through, with a field per function, `Sendable` in the `Sendable` form. A function takes the
	/// entered places as its one argument besides the route, reads its configuration from them, and builds the function
	/// its route names next in a builder whose closure enters that function's place: a `SendableBuilder`, which stands in
	/// for a `SendableInstantiator`, for a `@Sendable` function, and a `PlainBuilder` otherwise. A route names only
	/// `@Sendable` functions after one of them, as everything a `@Sendable` function builds is built in `@Sendable`
	/// functions.
	/// - Parameter countsPlacesLookedAt: Whether the program counts, in a global `placesLookedAt`, each step the
	///   declaration takes from one place to another while it looks a slot or the nearest place of a type up: the test
	///   adds the count to each line of the declaration that takes a step, the lines that set `place`.
	private static func program(functions: [Function], isSendable: Bool, countsPlacesLookedAt: Bool = false) -> String {
		func calls(on configuration: String, insideSendableFunction: Bool, indent: String) -> [String] {
			["\(indent)switch route.first {"]
				+ functions.enumerated().filter { !insideSendableFunction || $0.element.isSendable }.flatMap { slot, function in
					[
						"\(indent)case \"\(function.name)\":",
						"\(indent)    let next = route.dropFirst()",
						"\(indent)    return reads + \(function.isSendable ? "SendableBuilder" : "PlainBuilder")<[String]> { __safeDI_\(function.name)(__safeDI_entered: \(function.entered(handing: "\(configuration).\(function.name)", slot: slot)), route: next) }.build()",
					]
				}
				+ ["\(indent)default:", "\(indent)    return reads", "\(indent)}"]
		}
		var typeNames = ["Root"]
		for function in functions where !typeNames.contains(function.typeName) {
			typeNames.append(function.typeName)
		}
		// `SafeDI`'s builders take an `Instantiable` type: these stand in for them, `nonisolated` as `SafeDI`'s module is.
		var lines = countsPlacesLookedAt ? ["nonisolated(unsafe) var placesLookedAt = 0"] : []
		lines += [
			"nonisolated struct PlainBuilder<Built> {",
			"    let build: () -> Built",
			"}",
			"nonisolated struct SendableBuilder<Built>: Sendable {",
			"    let build: @Sendable () -> Built",
			"}",
		]
		for typeName in typeNames {
			lines += ["enum \(typeName) {", isSendable ? "    nonisolated struct SafeDIMockConfiguration: Sendable {" : "    struct SafeDIMockConfiguration {", "        let name: String"]
			lines += functions.map { "        var \($0.name): \($0.typeName).SafeDIMockConfiguration { .init(name: name + \".\($0.name)\") }" }
			lines += ["    }", "}"]
		}
		lines.append("extension Root {")
		lines.append("    static func reads(along route: ArraySlice<String>) -> [String] {")
		lines.append("        let safeDIOverrides = Root.SafeDIMockConfiguration(name: \"root\")")
		lines += MockEnteredSlot.mockEnteredPlacesDeclaration(
			isSendable: isSendable,
			entersNearest: functions.contains {
				if case .nearest = $0.entry {
					true
				} else {
					false
				}
			},
			passes: functions.contains {
				if case .passing = $0.entry {
					true
				} else {
					false
				}
			},
			leavesOut: false,
			slotCount: functions.count,
		).map { "        " + (countsPlacesLookedAt && $0.trimmingCharacters(in: .whitespaces).hasPrefix("place = ") ? $0 + "; placesLookedAt += 1" : $0) }
		for function in functions {
			lines += [
				"        \(function.isSendable ? "@Sendable nonisolated " : "")func __safeDI_\(function.name)(__safeDI_entered: __safeDI_Entered<\(function.typeName).SafeDIMockConfiguration>, route: ArraySlice<String>) -> [String] {",
				"            let reads = [\"\(function.name) reads \\(__safeDI_entered.configuration.name)\"]",
			]
			lines += calls(on: "__safeDI_entered.configuration", insideSendableFunction: function.isSendable, indent: "            ")
			lines.append("        }")
		}
		lines.append("        let reads = [String]()")
		lines += calls(on: "safeDIOverrides", insideSendableFunction: false, indent: "        ")
		lines += ["    }", "}"]
		return lines.joined(separator: "\n") + "\n"
	}

	/// Compiles and runs `program(functions:isSendable:)`, and returns what it prints: for each route, a line per function
	/// called, naming the configuration the function reads, with an empty line between routes.
	/// - Returns: What the program printed, or `nil` when compile verification is disabled.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func printedReads(functions: [Function], isSendable: Bool, routes: [[String]]) async throws -> String? {
		let routesLiteral = routes.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ", ") + "]" }.joined(separator: ", ")
		return try await DifferentialValueOracle.output(
			of: DifferentialValuePath(fixtureFiles: ["Program.swift": Self.program(functions: functions, isSendable: isSendable)]),
			running: """
			let routes: [[String]] = [\(routesLiteral)]
			for (index, route) in routes.enumerated() {
			    if index > 0 {
			        print("")
			    }
			    for read in Root.reads(along: route[...]) {
			        print(read)
			    }
			}
			""",
			filesToDelete: &filesToDelete,
		)
	}
}
