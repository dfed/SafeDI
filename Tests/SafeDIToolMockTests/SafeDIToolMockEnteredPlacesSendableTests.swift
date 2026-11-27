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

/// The `Sendable` form of the struct a mock root declares for the functions on its tree's cycles
/// (`MockEnteredSlot.mockEnteredPlacesDeclaration(slots:isSendable:)`), which a `@Sendable` function on a cycle captures
/// in the `SendableInstantiator` it builds. Each program declares the struct with its slots' configurations in the
/// `Sendable` form, as a mock declares every configuration a `@Sendable` function reads (piece 4 keeps every slot's
/// configuration so), and a function per slot that begins with the three statements of a function on a cycle: a plain
/// function for a slot built by an `Instantiator` and a `@Sendable nonisolated` one for a slot built by a
/// `SendableInstantiator`, each building the next function of its route in a builder of the next slot's kind.
struct SafeDIToolMockEnteredPlacesSendableTests: ~Copyable {
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

	@Test(arguments: [nil, "MainActor"] as [String?])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func enteredPlaces_compileWithNothingUnchecked_whenSendableFunctionsOnTwoCyclesOfOneRootCaptureThem(defaultIsolation: String?) async throws {
		// The root's two cycles share the struct: `homeBuilder`, a plain function, enters a ring of `@Sendable` functions
		// through `awayBuilder`, which also calls `porchBuilder`, a `@Sendable` function on no cycle; `catBuilder` and
		// `dogBuilder` close on each other in plain functions. Language mode 6 checks every capture; with the module's
		// declarations defaulting to the main actor, the struct and `Place` are `nonisolated` so that the
		// `@Sendable nonisolated` functions can enter a place.
		_ = try await executeSafeDIToolTest(
			// `Probe` gives the run generated code, without which nothing is compiled.
			swiftFileContent: [Self.program(slots: Self.twoCyclesSlots, sendableSlots: Self.twoCyclesSendableSlots, offCycleFunctions: Self.offCycleFunctions), "@Instantiable(isRoot: true)\npublic struct Probe: Instantiable {\n    public init() {}\n}\n"],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: defaultIsolation),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func enteredPlaces_returnSendableFunctionToItsPlaceAndEnterTheNearestOfItsType_whenRingRunsInsideSendableFunctions() async throws {
		// First route: `otherHomeBuilder` is entered inside `awayBuilder`'s `@Sendable` function, beneath `homeBuilder`, which
		// builds its type too, so it reads `homeBuilder`'s configuration; the route then closes on `awayBuilder`, which reads
		// the configuration it was first entered with, and enters `otherHomeBuilder` again, whose earlier place it forgets.
		// Second route: the plain cycle closes on `catBuilder`. Third route: `porchBuilder`, a `@Sendable` function on no
		// cycle that builds `Home`, enters the nearest place of its type, so `otherHomeBuilder` beneath it reads its
		// configuration.
		let program = Self.program(slots: Self.twoCyclesSlots, sendableSlots: Self.twoCyclesSendableSlots, offCycleFunctions: Self.offCycleFunctions)
		let printed = try await DifferentialValueOracle.output(
			of: DifferentialValuePath(fixtureFiles: ["Program.swift": program]),
			running: """
			let routes: [[String]] = [["homeBuilder", "awayBuilder", "otherHomeBuilder", "awayBuilder", "otherHomeBuilder"], ["catBuilder", "dogBuilder", "catBuilder"], ["homeBuilder", "awayBuilder", "porchBuilder", "otherHomeBuilder"]]
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

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Home`, built by `homeBuilder` and `otherHomeBuilder`, which share the nearest-of-type member `nearestHome`; `Away`,
	/// built by `awayBuilder`; and `Cat` and `Dog`, a second cycle's.
	private static let twoCyclesSlots = [
		MockEnteredSlot(name: "homeBuilder", configurationType: .simple(name: "Home", generics: []), nearestOfTypeSlotName: "nearestHome"),
		MockEnteredSlot(name: "awayBuilder", configurationType: .simple(name: "Away", generics: []), nearestOfTypeSlotName: nil),
		MockEnteredSlot(name: "otherHomeBuilder", configurationType: .simple(name: "Home", generics: []), nearestOfTypeSlotName: "nearestHome"),
		MockEnteredSlot(name: "catBuilder", configurationType: .simple(name: "Cat", generics: []), nearestOfTypeSlotName: nil),
		MockEnteredSlot(name: "dogBuilder", configurationType: .simple(name: "Dog", generics: []), nearestOfTypeSlotName: nil),
	]

	/// The slots of `twoCyclesSlots` built by a `SendableInstantiator`: the ring `homeBuilder` enters.
	private static let twoCyclesSendableSlots: Set<String> = ["awayBuilder", "otherHomeBuilder"]

	/// `porchBuilder`, a `@Sendable` function on no cycle that builds `Home`, and the nearest-of-type member it enters.
	private static let offCycleFunctions = [
		MockEnteredSlot(name: "porchBuilder", configurationType: .simple(name: "Home", generics: []), nearestOfTypeSlotName: "nearestHome"),
	]

	/// A program around the `Sendable` declaration written for `slots`, whose `Root.reads(along:)` calls the functions a
	/// route names and returns, a line per function, the configuration each reads. Each slot's type has a `Sendable`
	/// `SafeDIMockConfiguration` named by the path of fields it was read through, with a field per slot. A function builds
	/// the next of its route in a `SendableBuilder`, which stands in for a `SendableInstantiator`, where the next slot is
	/// in `sendableSlots`, and in a `PlainBuilder` otherwise; a route names only slots of `sendableSlots` after one of
	/// them, as everything a `@Sendable` function builds is built in `@Sendable` functions. Each of `offCycleFunctions` is
	/// a `@Sendable` function on no cycle, which a route calls as it calls a slot's, and which begins by entering the
	/// nearest-of-type member it names with the configuration it is handed.
	private static func program(slots: [MockEnteredSlot], sendableSlots: Set<String>, offCycleFunctions: [MockEnteredSlot] = []) -> String {
		// A function on no cycle is called as a slot's is, and builds as a `@Sendable` function does.
		let callees = slots + offCycleFunctions
		let sendableCallees = sendableSlots.union(offCycleFunctions.map(\.name))
		func configurationType(of typeName: String) -> [String] {
			["enum \(typeName) {", "    nonisolated struct SafeDIMockConfiguration: Sendable {", "        let name: String"]
				+ callees.map { "        var \($0.name): \($0.configurationType.asSource).SafeDIMockConfiguration { .init(name: name + \".\($0.name)\") }" }
				+ ["    }", "}"]
		}
		/// The statements that build and call the function the route names next, in a `SendableBuilder` for a slot of
		/// `sendableSlots` and in a `PlainBuilder` for any other. A `@Sendable` function (`insideSendableFunction`) calls
		/// only slots of `sendableSlots`.
		func calls(on configuration: String, insideSendableFunction: Bool, indent: String) -> [String] {
			["\(indent)switch route.first {"]
				+ callees.filter { !insideSendableFunction || sendableCallees.contains($0.name) }.flatMap { slot -> [String] in
					let builder = sendableCallees.contains(slot.name) ? "SendableBuilder" : "PlainBuilder"
					return [
						"\(indent)case \"\(slot.name)\":",
						"\(indent)    let next = route.dropFirst()",
						"\(indent)    let configuration = \(configuration).\(slot.name)",
						"\(indent)    return reads + \(builder)<[String]> { __safeDI_\(slot.name)(safeDIOverrides: configuration, __safeDI_entered: __safeDI_entered, route: next) }.build()",
					]
				}
				+ ["\(indent)default:", "\(indent)    return reads", "\(indent)}"]
		}
		var typeNames = ["Root"]
		for slot in slots where !typeNames.contains(slot.configurationType.asSource) {
			typeNames.append(slot.configurationType.asSource)
		}
		// `SafeDI`'s builders take an `Instantiable` type: these stand in for them, `nonisolated` as `SafeDI`'s module is.
		var lines = [
			"nonisolated struct PlainBuilder<Built> {",
			"    let build: () -> Built",
			"}",
			"nonisolated struct SendableBuilder<Built>: Sendable {",
			"    let build: @Sendable () -> Built",
			"}",
		]
		lines += typeNames.flatMap(configurationType(of:))
		lines.append("extension Root {")
		lines.append("    static func reads(along route: ArraySlice<String>) -> [String] {")
		lines += MockEnteredSlot.mockEnteredPlacesDeclaration(slots: slots, isSendable: true).map { "        " + $0 }
		for slot in slots {
			let isSendable = sendableSlots.contains(slot.name)
			let newConfiguration = slot.nearestOfTypeSlotName.map { "__safeDI_entered.\($0)?.configuration ?? safeDIOverrides" } ?? "safeDIOverrides"
			lines += [
				"        \(isSendable ? "@Sendable nonisolated " : "")func __safeDI_\(slot.name)(safeDIOverrides: \(slot.configurationType.asSource).SafeDIMockConfiguration, __safeDI_entered: __safeDI_EnteredPlaces, route: ArraySlice<String>) -> [String] {",
				"            let __safeDI_place = __safeDI_entered.\(slot.name) ?? .init(\(newConfiguration), above: __safeDI_entered)",
				"            let safeDIOverrides = __safeDI_place.configuration",
				"            let __safeDI_entered = __safeDI_place.enteredAbove.entering(\(slot.name): __safeDI_place)",
				"            let reads = [\"\(slot.name) reads \\(safeDIOverrides.name)\"]",
			]
			lines += calls(on: "safeDIOverrides", insideSendableFunction: isSendable, indent: "            ")
			lines.append("        }")
		}
		for function in offCycleFunctions {
			lines += [
				"        @Sendable nonisolated func __safeDI_\(function.name)(safeDIOverrides: \(function.configurationType.asSource).SafeDIMockConfiguration, __safeDI_entered: __safeDI_EnteredPlaces, route: ArraySlice<String>) -> [String] {",
				"            let __safeDI_entered = __safeDI_entered.entering(\(function.nearestOfTypeSlotName ?? ""): .init(safeDIOverrides, above: __safeDI_entered))",
				"            let reads = [\"\(function.name) reads \\(safeDIOverrides.name)\"]",
			]
			lines += calls(on: "safeDIOverrides", insideSendableFunction: true, indent: "            ")
			lines.append("        }")
		}
		lines += [
			"        let safeDIOverrides = Root.SafeDIMockConfiguration(name: \"root\")",
			"        let __safeDI_entered = __safeDI_EnteredPlaces()",
			"        let reads = [String]()",
		]
		lines += calls(on: "safeDIOverrides", insideSendableFunction: false, indent: "        ")
		lines += ["    }", "}"]
		return lines.joined(separator: "\n") + "\n"
	}
}
