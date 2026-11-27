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

/// The struct a mock root declares for the functions on its tree's cycles is written from a list of slots alone
/// (`MockEnteredSlot.mockEnteredPlacesDeclaration`). The text tests compare the whole declaration; the others compile it
/// into a program whose functions begin as a function on a cycle does, walk a route through them, and print the
/// configuration each function reads.
struct SafeDIToolMockEnteredPlacesDeclarationTests: ~Copyable {
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
	func mockEnteredPlacesDeclaration_declaresAMemberAndAnEnteringFunctionPerSlot_whenEachTypeIsBuiltByOneProperty() {
		let slots = [
			MockEnteredSlot(name: "homeBuilder", configurationType: .simple(name: "Home", generics: []), nearestOfTypeSlotName: nil),
			MockEnteredSlot(name: "`default`", configurationType: .simple(name: "Away", generics: []), nearestOfTypeSlotName: nil),
		]
		#expect(MockEnteredSlot.mockEnteredPlacesDeclaration(slots: slots, isSendable: false).joined(separator: "\n") == """
		struct __safeDI_EnteredPlaces {
		    final class Place<Configuration> {
		        let configuration: Configuration
		        let enteredAbove: __safeDI_EnteredPlaces
		        init(_ configuration: Configuration, above enteredAbove: __safeDI_EnteredPlaces) {
		            self.configuration = configuration
		            self.enteredAbove = enteredAbove
		        }
		    }
		    var homeBuilder: Place<Home.SafeDIMockConfiguration>?
		    var `default`: Place<Away.SafeDIMockConfiguration>?
		    func entering(homeBuilder place: Place<Home.SafeDIMockConfiguration>) -> Self {
		        var entered = self
		        entered.homeBuilder = place
		        return entered
		    }
		    func entering(default place: Place<Away.SafeDIMockConfiguration>) -> Self {
		        var entered = self
		        entered.`default` = place
		        return entered
		    }
		}
		""")
	}

	@Test
	func mockEnteredPlacesDeclaration_declaresOneNearestOfTypeMemberWhichEachOfItsSlotsSets_whenTwoPropertiesBuildOneType() {
		#expect(MockEnteredSlot.mockEnteredPlacesDeclaration(slots: Self.slotsWithTwoPropertiesOfHome, isSendable: false).joined(separator: "\n") == """
		struct __safeDI_EnteredPlaces {
		    final class Place<Configuration> {
		        let configuration: Configuration
		        let enteredAbove: __safeDI_EnteredPlaces
		        init(_ configuration: Configuration, above enteredAbove: __safeDI_EnteredPlaces) {
		            self.configuration = configuration
		            self.enteredAbove = enteredAbove
		        }
		    }
		    var homeBuilder: Place<Home.SafeDIMockConfiguration>?
		    var awayBuilder: Place<Away.SafeDIMockConfiguration>?
		    var otherHomeBuilder: Place<Home.SafeDIMockConfiguration>?
		    var nearestHome: Place<Home.SafeDIMockConfiguration>?
		    func entering(homeBuilder place: Place<Home.SafeDIMockConfiguration>) -> Self {
		        var entered = self
		        entered.homeBuilder = place
		        entered.nearestHome = place
		        return entered
		    }
		    func entering(awayBuilder place: Place<Away.SafeDIMockConfiguration>) -> Self {
		        var entered = self
		        entered.awayBuilder = place
		        return entered
		    }
		    func entering(otherHomeBuilder place: Place<Home.SafeDIMockConfiguration>) -> Self {
		        var entered = self
		        entered.otherHomeBuilder = place
		        entered.nearestHome = place
		        return entered
		    }
		}
		""")
	}

	@Test
	func mockEnteredPlacesDeclaration_declaresBothTypesSendableAndNonisolated_whenAFunctionHandedThePlacesIsSendable() {
		let slots = [MockEnteredSlot(name: "homeBuilder", configurationType: .simple(name: "Home", generics: []), nearestOfTypeSlotName: nil)]
		#expect(MockEnteredSlot.mockEnteredPlacesDeclaration(slots: slots, isSendable: true).joined(separator: "\n") == """
		nonisolated struct __safeDI_EnteredPlaces: Sendable {
		    nonisolated final class Place<Configuration: Sendable>: Sendable {
		        let configuration: Configuration
		        let enteredAbove: __safeDI_EnteredPlaces
		        init(_ configuration: Configuration, above enteredAbove: __safeDI_EnteredPlaces) {
		            self.configuration = configuration
		            self.enteredAbove = enteredAbove
		        }
		    }
		    var homeBuilder: Place<Home.SafeDIMockConfiguration>?
		    func entering(homeBuilder place: Place<Home.SafeDIMockConfiguration>) -> Self {
		        var entered = self
		        entered.homeBuilder = place
		        return entered
		    }
		}
		""")
	}

	@Test
	func mockEnteredPlacesDeclaration_keepsTheOrderOfTheSlots_whenTwentySlotsAreListedAgainstTheirNames() {
		// Twenty slots whose names and types sort in another order than the list's, each type built by two properties, so
		// that an order taken from a set or from names shows in the members, the nearest-of-type members or the functions.
		let order = [13, 4, 17, 0, 9, 19, 6, 2, 15, 11, 8, 1, 18, 5, 12, 3, 16, 7, 14, 10]
		let slots = order.map { MockEnteredSlot(name: "builder\($0)", configurationType: .simple(name: "Type\(19 - $0 / 2)", generics: []), nearestOfTypeSlotName: "nearest\($0 / 2)") }
		let lines = MockEnteredSlot.mockEnteredPlacesDeclaration(slots: slots, isSendable: false)
		let members = lines.filter { $0.hasPrefix("    var ") }.map { String($0.dropFirst(8).prefix { $0 != ":" }) }
		let functions = lines.filter { $0.hasPrefix("    func ") }.map { String($0.dropFirst(18).prefix { $0 != " " }) }
		#expect(members == order.map { "builder\($0)" } + [6, 2, 8, 0, 4, 9, 3, 1, 7, 5].map { "nearest\($0)" })
		#expect(functions == order.map { "builder\($0)" })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func enteredPlaces_returnAFunctionToItsPlaceAndForgetThePlacesBeneathIt_whenARouteClosesOnAPropertyAbove() async throws {
		// The root calls `aBuilder`, which calls `bBuilder`, which calls `cBuilder`, which closes on `aBuilder`: that call
		// reads the configuration the first was entered with. `aBuilder` then calls `cBuilder`, whose earlier place was
		// beneath `aBuilder`'s and is forgotten, so it reads `aBuilder`'s field, not `bBuilder`'s.
		let slots = [
			MockEnteredSlot(name: "aBuilder", configurationType: .simple(name: "A", generics: []), nearestOfTypeSlotName: nil),
			MockEnteredSlot(name: "bBuilder", configurationType: .simple(name: "B", generics: []), nearestOfTypeSlotName: nil),
			MockEnteredSlot(name: "cBuilder", configurationType: .simple(name: "C", generics: []), nearestOfTypeSlotName: nil),
		]
		let printed = try await printedReads(slots: slots, routes: [["aBuilder", "bBuilder", "cBuilder", "aBuilder", "cBuilder"]])
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
	mutating func enteredPlaces_enterAPropertyWithTheNearestConfigurationOfItsType_whenTwoPropertiesBuildOneType() async throws {
		// First route: `otherHomeBuilder` is entered beneath `homeBuilder`, which builds its type too, so it reads
		// `homeBuilder`'s configuration and not `awayBuilder`'s field. Second route: `awayBuilder` is entered first and
		// `homeBuilder` beneath it; the route closes on `awayBuilder`, which forgets `homeBuilder`'s place, so
		// `otherHomeBuilder` finds no place of its type and reads `awayBuilder`'s field.
		let printed = try await printedReads(slots: Self.slotsWithTwoPropertiesOfHome, routes: [
			["homeBuilder", "awayBuilder", "otherHomeBuilder"],
			["awayBuilder", "homeBuilder", "awayBuilder", "otherHomeBuilder"],
		])
		#expect(printed == nil || printed == """
		homeBuilder reads root.homeBuilder
		awayBuilder reads root.homeBuilder.awayBuilder
		otherHomeBuilder reads root.homeBuilder

		awayBuilder reads root.awayBuilder
		homeBuilder reads root.awayBuilder.homeBuilder
		awayBuilder reads root.awayBuilder
		otherHomeBuilder reads root.awayBuilder.otherHomeBuilder

		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Home` built by `homeBuilder` and by `otherHomeBuilder`, which share the nearest-of-type member `nearestHome`, with
	/// `awayBuilder` listed between them.
	private static let slotsWithTwoPropertiesOfHome = [
		MockEnteredSlot(name: "homeBuilder", configurationType: .simple(name: "Home", generics: []), nearestOfTypeSlotName: "nearestHome"),
		MockEnteredSlot(name: "awayBuilder", configurationType: .simple(name: "Away", generics: []), nearestOfTypeSlotName: nil),
		MockEnteredSlot(name: "otherHomeBuilder", configurationType: .simple(name: "Home", generics: []), nearestOfTypeSlotName: "nearestHome"),
	]

	/// Compiles and runs a program around the declaration written for `slots`, and returns what it prints: for each
	/// route, a line per function called, naming the configuration the function reads, with an empty line between routes.
	///
	/// The program declares each slot's type with a `SafeDIMockConfiguration` that is named by the path of fields it was
	/// read through and has a field per slot, and a function `reads(along:)` whose body holds the declaration and a
	/// function per slot. Each of those begins with the three statements of a function on a cycle (it finds its place in
	/// its slot, or enters one with the nearest configuration of its type, else the one it is handed), records the
	/// configuration it then reads, and calls the function the route names next with its own field for it.
	/// - Returns: What the program printed, or `nil` when compile verification is disabled.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func printedReads(slots: [MockEnteredSlot], routes: [[String]]) async throws -> String? {
		func configurationType(of typeName: String) -> [String] {
			["enum \(typeName) {", "    struct SafeDIMockConfiguration {", "        let name: String"]
				+ slots.map { "        var \($0.name): \($0.configurationType.asSource).SafeDIMockConfiguration { .init(name: name + \".\($0.name)\") }" }
				+ ["    }", "}"]
		}
		func calls(on configuration: String, indent: String) -> [String] {
			["\(indent)switch route.first {"]
				+ slots.flatMap { [
					"\(indent)case \"\($0.name)\":",
					"\(indent)    __safeDI_\($0.name)(safeDIOverrides: \(configuration).\($0.name), __safeDI_entered: __safeDI_entered, route: route.dropFirst())",
				] }
				+ ["\(indent)default:", "\(indent)    break", "\(indent)}"]
		}
		var typeNames = ["Root"]
		for slot in slots where !typeNames.contains(slot.configurationType.asSource) {
			typeNames.append(slot.configurationType.asSource)
		}
		var lines = typeNames.flatMap(configurationType(of:))
		lines.append("func reads(along route: ArraySlice<String>) -> [String] {")
		lines += MockEnteredSlot.mockEnteredPlacesDeclaration(slots: slots, isSendable: false).map { "    " + $0 }
		lines.append("    var reads = [String]()")
		for slot in slots {
			let newConfiguration = slot.nearestOfTypeSlotName.map { "__safeDI_entered.\($0)?.configuration ?? safeDIOverrides" } ?? "safeDIOverrides"
			lines += [
				"    func __safeDI_\(slot.name)(safeDIOverrides: \(slot.configurationType.asSource).SafeDIMockConfiguration, __safeDI_entered: __safeDI_EnteredPlaces, route: ArraySlice<String>) {",
				"        let __safeDI_place = __safeDI_entered.\(slot.name) ?? .init(\(newConfiguration), above: __safeDI_entered)",
				"        let safeDIOverrides = __safeDI_place.configuration",
				"        let __safeDI_entered = __safeDI_place.enteredAbove.entering(\(slot.name): __safeDI_place)",
				"        reads.append(\"\(slot.name) reads \\(safeDIOverrides.name)\")",
			]
			lines += calls(on: "safeDIOverrides", indent: "        ")
			lines.append("    }")
		}
		lines += [
			"    let safeDIOverrides = Root.SafeDIMockConfiguration(name: \"root\")",
			"    let __safeDI_entered = __safeDI_EnteredPlaces()",
		]
		lines += calls(on: "safeDIOverrides", indent: "    ")
		lines += ["    return reads", "}"]
		let routesLiteral = routes.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ", ") + "]" }.joined(separator: ", ")
		return try await DifferentialValueOracle.output(
			of: DifferentialValuePath(fixtureFiles: ["Program.swift": lines.joined(separator: "\n") + "\n"]),
			running: """
			let routes: [[String]] = [\(routesLiteral)]
			for (index, route) in routes.enumerated() {
			    if index > 0 {
			        print("")
			    }
			    for read in reads(along: route[...]) {
			        print(read)
			    }
			}
			""",
			filesToDelete: &filesToDelete,
		)
	}
}
