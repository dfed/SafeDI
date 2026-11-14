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

/// A cycle a fill closes is judged against the stack the fill was built with: a repeat of a property of the filled seam's
/// path, built for the same concrete type. A property of that label and type built for another fulfiller is built again,
/// as inline builds it.
struct SafeDIToolSeamFillCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	private static let protocols = ["public protocol Widget {}", "public protocol Gadget {}", "public protocol Pane {}", "public protocol Gizmo {}"]
	private static let rootOfInner = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let inner: Inner"])

	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
	}

	private static func fulfilling(_ name: String, _ fulfilled: String, _ declarations: [String] = []) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilled)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilled).self])\n")
	}

	/// Expects `app`'s fill of `feature`'s holes to compile and build the values of the graph with every fulfiller in `Feature`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectFillBuildsVisibleBuildsValues(feature: [String], fulfillers: [String], root: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let visibleModules = Self.modules(feature: feature + fulfillers, app: [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	// MARK: A property of the path's label and type, built for another fulfiller

	@Test(arguments: ["any Pane", "LazilyInstantiated<any Pane>"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFill_whenHolesOwnPropertyRepeatsPathPropertyBuiltForAnotherFulfiller(rowPane: String) async throws {
		try await expectFillBuildsVisibleBuildsValues(
			feature: Self.protocols + [
				seamFixtureType(named: "Row", declarations: ["@Instantiated public let pane: \(rowPane)"]),
				seamFixtureType(named: "PaneA", declarations: ["@Instantiated public let rowMaker: Instantiator<Row>"], conformances: ", Pane"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "PaneA") public let pane: any Pane"#]),
			],
			fulfillers: [Self.fulfilling("DefaultPane", "Pane")],
			root: Self.rootOfInner,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFulfillersProperty_whenFillDeclaresPathPropertyBuiltForAnotherFulfiller() async throws {
		try await expectFillBuildsVisibleBuildsValues(
			feature: Self.protocols + [
				seamFixtureType(named: "Row", declarations: ["@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "PaneA", declarations: ["@Instantiated public let rowMaker: Instantiator<Row>"], conformances: ", Pane"),
				seamFixtureType(named: "PaneC", declarations: [], conformances: ", Pane"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "PaneA") public let pane: any Pane"#]),
			],
			fulfillers: [Self.fulfilling("DefaultWidget", "Widget", [#"@Instantiated(fulfilledByType: "PaneC") public let pane: any Pane"#])],
			root: Self.rootOfInner,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsNestedFill_whenItsHolesOwnPropertyRepeatsNestedSeamsPathPropertyBuiltForAnotherFulfiller() async throws {
		try await expectFillBuildsVisibleBuildsValues(
			feature: Self.protocols + [
				seamFixtureType(named: "RowA", declarations: ["@Instantiated public let widget: any Widget"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let rowMaker: Instantiator<RowA>"]),
				seamFixtureType(named: "RowB", declarations: ["@Instantiated public let pane: any Pane"]),
				seamFixtureType(named: "PaneB", declarations: ["@Instantiated public let rowMaker: Instantiator<RowB>"], conformances: ", Pane"),
				seamFixtureType(named: "Deep", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "PaneB") public let pane: any Pane"#]),
			],
			fulfillers: [
				Self.fulfilling("DefaultWidget", "Widget", ["@Instantiated public let deep: Deep"]),
				Self.fulfilling("DefaultPane", "Pane"),
			],
			root: Self.rootOfInner,
		)
	}

	// MARK: A closer is judged only against the stack it was built with

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTree_namingTheNearestFill_whenNestedFillClosesOnItsSeamsPath() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGizmo.swift"]):9:5: error: SafeDI cannot fill the builder for `RowB`'s `gizmo: any Gizmo` (case `RowB_Scope.gizmo` of `gizmoBuilder`) in `Deep`'s dependency tree: `DefaultGizmo`, which fills it, instantiates `pane: any Pane`, which `Deep`'s tree is building where it builds `gizmo` (Deep -> pane -> PaneB -> rowMaker -> RowB -> gizmo -> DefaultGizmo -> pane). Code generated outside module `Feature` cannot refer to the function `Deep`'s initializer builds `Pane` with, and building it again would hand it other values than `Deep`'s tree holds. Instantiate the seam where `DefaultGizmo` builds `Pane` (`@Instantiated let deepBuilder: Instantiator<Deep>`), so the cycle re-enters through the initializer SafeDI generates for `Deep`, or declare an @Instantiable type that fulfills `Gizmo` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Deep.swift"]):7:5: note: `Deep` instantiates `pane: any Pane` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.protocols + [
						seamFixtureType(named: "RowA", declarations: ["@Instantiated public let widget: any Widget"]),
						seamFixtureType(named: "PaneA", declarations: ["@Instantiated public let rowMaker: Instantiator<RowA>"], conformances: ", Pane"),
						seamFixtureType(named: "Inner", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "PaneA") public let pane: any Pane"#]),
						seamFixtureType(named: "RowB", declarations: ["@Instantiated public let gizmo: any Gizmo"]),
						seamFixtureType(named: "PaneB", declarations: ["@Instantiated public let rowMaker: Instantiator<RowB>"], conformances: ", Pane"),
						seamFixtureType(named: "Deep", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "PaneB") public let pane: any Pane"#]),
					],
					app: [
						Self.fulfilling("DefaultWidget", "Widget", ["@Instantiated public let deep: Deep"]),
						Self.fulfilling("DefaultGizmo", "Gizmo", [#"@Instantiated(fulfilledByType: "PaneB") public let pane: any Pane"#]),
						Self.rootOfInner,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: What a fill's root can repeat

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rejectsFulfillerOfASeamsPathType_whenAnotherModuleDeclaresThatTypeAgain() async {
		// The only way a fill's root, the type that fulfills the hole, could close on a stack entry is to be built for that
		// entry's concrete type, which the seam's module builds. A second declaration of the entry's type in the filler's
		// module, the one way to make a type the seam's module builds fulfill the hole only there, is rejected as a duplicate.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["File.swift"]):3:1: error: Found multiple @Instantiable types or extensions that fulfill `PaneA`, in modules `App` and `Feature`. Each type can be fulfilled by only one @Instantiable declaration a module can name. If `PaneA` names different types, rename one. If it names one type, keep one, and remove `PaneA` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
			\(fixtures["Feature"]!["PaneA.swift"]):1:1: error: Found multiple @Instantiable types or extensions that fulfill `PaneA`, in modules `App` and `Feature`. Each type can be fulfilled by only one @Instantiable declaration a module can name. If `PaneA` names different types, rename one. If it names one type, keep one, and remove `PaneA` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.protocols + [
						seamFixtureType(named: "Row", declarations: ["@Instantiated public let pane: any Pane"]),
						seamFixtureType(named: "PaneA", declarations: ["@Instantiated public let rowMaker: Instantiator<Row>"]),
						seamFixtureType(named: "Inner", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "PaneA") public let pane: any Pane"#]),
					],
					app: [
						"""
						@Instantiable(fulfillingAdditionalTypes: [Pane.self])
						extension PaneA: Instantiable, Pane {
						    public static func instantiate(rowMaker: Instantiator<Row>) -> PaneA {
						        PaneA(rowMaker: rowMaker)
						    }
						}
						""",
						Self.rootOfInner,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: The rename remedy

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTree_offeringNoRename_whenClosedOnPropertyDoesNotOwnTheHole() async {
		// `panel` builds `Panel`, which does not declare `widget`, so a rename would build `Panel` again, under the fill,
		// and close the cycle on the same declarations: only re-entering through the seam's initializer stops it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):10:5: error: SafeDI cannot fill the builder for `DefaultWidget`'s `gadget: any Gadget` (case `DefaultWidget_Scope.gadget` of `gadgetBuilder`) in `Host`'s dependency tree: `DefaultGadget`, which fills it, instantiates `panel: Panel`, which `Host`'s tree is building where it builds `gadget` (Host -> shell -> Shell -> inner -> Inner -> panel -> Panel -> rowMaker -> Row -> widget -> DefaultWidget -> gadget -> DefaultGadget -> panel). Code generated outside module `Upper` cannot refer to the function `Host`'s initializer builds `Panel` with, and building it again would hand it other values than `Host`'s tree holds. Instantiate the seam where `DefaultGadget` builds `Panel` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`, or declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Inner.swift"]):7:5: note: `Inner` instantiates `panel: Panel` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"public protocol Widget {}",
						"public protocol Gadget {}",
						seamFixtureType(named: "Row", declarations: ["@Instantiated public let widget: any Widget"]),
						seamFixtureType(named: "Panel", declarations: ["@Instantiated public let rowMaker: Instantiator<Row>"]),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let panel: Panel"]),
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let inner: Inner"]),
					]),
					ModuleFixture(name: "Upper", packageName: "Other", swiftFileContent: [
						Self.fulfilling("DefaultWidget", "Widget", ["@Instantiated public let gadget: any Gadget"]),
						seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
					].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						Self.fulfilling("DefaultGadget", "Gadget", ["@Instantiated public let panel: Panel"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
					].map { "import Feature\nimport Upper\n\n" + $0 }, dependencies: ["Feature", "Upper"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFill_afterTheRenameRemedy_whenClosedOnPropertyOwnsTheHole() async throws {
		// The rename the error offers where the property closed on builds the type that declares the hole.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(
				feature: Self.protocols + [
					seamFixtureType(named: "Panel", declarations: ["@Instantiated public let widget: any Widget"]),
					seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let panelMaker: Instantiator<Panel>"]),
				],
				app: [Self.fulfilling("DefaultWidget", "Widget", ["@Instantiated public let renamed: Instantiator<Panel>"]), Self.rootOfInner],
			),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 })
	}

	private var filesToDelete: [URL]
}
