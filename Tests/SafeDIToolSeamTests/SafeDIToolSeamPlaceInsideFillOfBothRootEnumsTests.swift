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
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A case nested by type that both of an inner seam's root enums reach, filled with a type whose tree builds a place the
/// caller cannot fill, or passes one up: the one function that fills the case would be handed a scope of either root
/// enum, and the case of the place it builds can carry only one. The error names the first place the fill's tree builds
/// or passes up, in the order the tree declares them, wherever in the tree it is.
struct SafeDIToolSeamPlaceInsideFillOfBothRootEnumsTests: ~Copyable {
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
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPlaceBeneathFillRoot_whenFillBuildsPlaceInTypeItInstantiates() async {
		// `DefaultService`, which fills `Panel`'s `service`, builds no place itself: its `helper` does, which only `App` can
		// fill. The error names `Helper`'s `gadget`, a level beneath the fill's root.
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			"""
			\(fixtures["Middle"]!["Helper.swift"]):9:5: error: SafeDI fills every place of the builder for `Panel`’s `service: any Service` (case `Panel_Scope.service` of `serviceBuilder`) with one function, whose tree builds `Helper`’s `gadget: any Gadget`, which no type that module `Middle` can see fulfills. `Inner` builds `Panel` both inside and outside a `@Sendable` function, so that function is handed a scope of either of `Inner`’s two root enums, and the case of `Helper`’s `gadget: any Gadget` can carry only one. To fill it, declare an @Instantiable type that fulfills `Gadget` in module `Middle` or a module it lists among its SafeDI dependencies, or declare an @Instantiable type that fulfills `Service` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Panel.swift"]):7:5: note: `Panel` instantiates `service: any Service` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(middle: [
					seamFixtureType(named: "Helper", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
					Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let helper: Helper"], conformances: ", Sendable"),
					Self.outer,
				]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPassedUpPlace_whenFillCallsSeamWhosePlaceItPassesUp() async {
		// `DefaultService` calls `Deep`, a seam whose `gadget` `Middle` cannot fill, so the call passes it up. The error names
		// `Deep`'s `gadget`, the place the call passes up.
		await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Deep.swift"]):7:5: error: SafeDI fills every place of the builder for `Panel`’s `service: any Service` (case `Panel_Scope.service` of `serviceBuilder`) with one function, whose tree builds `Deep`’s `gadget: any Gadget`, which no type that module `Middle` can see fulfills. `Inner` builds `Panel` both inside and outside a `@Sendable` function, so that function is handed a scope of either of `Inner`’s two root enums, and the case of `Deep`’s `gadget: any Gadget` can carry only one. To fill it, declare an @Instantiable type that fulfills `Gadget` in module `Middle` or a module it lists among its SafeDI dependencies, or declare an @Instantiable type that fulfills `Service` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Panel.swift"]):7:5: note: `Panel` instantiates `service: any Service` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [seamFixtureType(named: "Deep", isSeam: true, declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable")],
					middle: [
						Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let deep: Deep"], conformances: ", Sendable"),
						Self.outer,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPlaceInsideNestedFill_whenFillCallsSeamWhoseFillBuildsPlace() async {
		// `DefaultService` calls `Deep`, a seam whose `widget` `Middle` fills with `DefaultWidget`, whose `gadget` only `App`
		// can fill: the place is inside a fill nested in `DefaultService`'s tree. The walk that names the first place a fill's
		// tree builds (`firstPlaceBuilt(inTreeRootedAt:)`) does not go into a fill, whose generator builds no type of its
		// own, so it finds none: the error says "a place", has no note, and its remedy reads "To fill it, or declare". This
		// expects the error that walk gives once it goes into fills; until then the mismatch is a known issue.
		await withKnownIssue("firstPlaceBuilt(inTreeRootedAt:) does not walk into a fill nested in the fill’s tree") {
			await assertThrowsMultiModuleError(inModule: "Middle", diagnostics: { fixtures in
				"""
				\(fixtures["Middle"]!["DefaultWidget.swift"]):9:5: error: SafeDI fills every place of the builder for `Panel`’s `service: any Service` (case `Panel_Scope.service` of `serviceBuilder`) with one function, whose tree builds `DefaultWidget`’s `gadget: any Gadget`, which no type that module `Middle` can see fulfills. `Inner` builds `Panel` both inside and outside a `@Sendable` function, so that function is handed a scope of either of `Inner`’s two root enums, and the case of `DefaultWidget`’s `gadget: any Gadget` can carry only one. To fill it, declare an @Instantiable type that fulfills `Gadget` in module `Middle` or a module it lists among its SafeDI dependencies, or declare an @Instantiable type that fulfills `Service` in module `Feature` or a module it lists among its SafeDI dependencies.
				\(fixtures["Feature"]!["Panel.swift"]):7:5: note: `Panel` instantiates `service: any Service` here.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: Self.modules(
						feature: [
							"public protocol Widget: Sendable {}",
							seamFixtureType(named: "Deep", isSeam: true, declarations: ["@Instantiated public let widget: any Widget"], conformances: ", Sendable"),
						],
						middle: [
							Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated public let gadget: any Gadget"], conformances: ", Sendable"),
							Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let deep: Deep"], conformances: ", Sendable"),
							Self.outer,
						],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Outer`, a seam of `Middle` that calls `Inner`.
	private static let outer = seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner"], conformances: ", Sendable")

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String], conformances: String = "") -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)\(conformances)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// `Feature`, which declares `Inner`, a seam that builds `Panel`, whose `service` is a hole, at its root and inside the
	/// `@Sendable` function of its `screenBuilder`, so both of `Inner`'s root enums reach `Panel_Scope.service`, and
	/// `feature`; `Middle`, which declares `middle`; and `App`, which fills `Gadget` and declares the root.
	private static func modules(feature: [String] = [], middle: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service: Sendable {}\npublic protocol Gadget: Sendable {}",
				seamFixtureType(named: "Panel", declarations: ["@Instantiated public let service: any Service"], conformances: ", Sendable"),
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let panel: Panel"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let panel: Panel", "@Instantiated public let screenBuilder: SendableInstantiator<Screen>"], conformances: ", Sendable"),
			] + feature),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"], conformances: ", Sendable"),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
	}
}
